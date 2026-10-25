extends RefCounted
## Medical (owner: SUPPORT). Wounded state, auto evac, hospitals. CONTRACTS_G5 sections 3.4, 4, 5, 6, 10.
## Command: set_auto_evac {issuer, unit_id, on: bool, center?: [x,y], radius?}
## - Wounded (D16): Damage calls on_zero_hp(w, e) before destroying a unit (wired by CORE10K). Human
##   infantry (def armor "infantry", def faction human_a / human_b) is kept alive: wounded = true,
##   hp 1, pinned in place (e.wnd_pos), no orders, weapon held (cooldown pinned), still counted in pop.
##   A second 0 hp (splash) kills it. Not evacuated within rules.medical.bleed_out_s (60 s) -> destroyed.
##   ORCH design rule (G5): only while the unit's faction has medical capability right now (has_medical:
##   a live, non-wounded own unit with def med_unit or an evac capacity, or an own built hospital /
##   field_hospital). Otherwise on_zero_hp returns false and the unit dies exactly as in G4.
## - Evac: a unit with capacity (def wounded_slots, else rules.medical.capacity[def]) on auto evac
##   picks up the wounded of its own side inside its area, nearest first (ties by id), until full or
##   none are left, then drives to the nearest own built Hospital / Field Hospital. Bleeding stops
##   once aboard (e.evac_by = carrier id; the unit rides at the carrier position).
## - Field Hospital (def field_hospital): heals light wounds (bleed used <= light_s, 30 s) in place;
##   the rest stay aboard and are forwarded to the nearest Hospital (def hospital).
## - Hospital: heals fully; the unit re-spawns beside the Hospital at full hp, ammo and squad, free
##   (event Reinforcement). Wounded keep their entity id throughout.
## State (saved, hashed): w.sys_state.medical = {wounded: {id: t_left ticks}, carriers: {id: [ids]},
##   evac: {id: {center: [x,y], radius, phase: "collect"|"deliver", cur, fwd, tp?, home?}}, ver}
## G5 entity fields: e.wounded (bool), e.wnd_pos (Vector2), e.evac_by (int carrier id while aboard).
## Untargetable-by-direct-fire and no-fire are honoured by Combat / Status via CORE10K / ORCH CRs
## (field e.wounded); this file additionally pins e.cooldown so a wounded unit never fires.
## Runtime caches (never saved; pure functions of the current state): w.cache.med_cap (per tick),
##   w.cache.med_evac (carrier buckets + live target map, rebuilt from st.evac when it changes).

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const HotState = preload("res://sim/hot_state.gd")   # direct dict writes are followed by HotState.touch

const STEP := 10
const HUMAN := ["human_a", "human_b"]
const HOLD_FIRE := 600.0


static func cfg() -> Dictionary:
	return Content.rules().get("medical", {})


static func _state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("medical"):
		w.sys_state["medical"] = {"wounded": {}, "carriers": {}, "evac": {}, "ver": 1}
	return w.sys_state["medical"]


static func bleed_ticks() -> int:
	return int(float(cfg().get("bleed_out_s", 60)) * 20.0)


# ================================================================ public API (medical.api_ready)
static func is_wounded(e: Dictionary) -> bool:
	return bool(e.get("wounded", false))


## Ids of the wounded aboard carrier e (ascending pick-up order).
static func carrying(e: Dictionary) -> Array:
	# entity-only API: the carrier mirrors sys_state.medical.carriers[id] in e.evac_load
	return (e.get("evac_load", []) as Array).duplicate()


static func capacity(def_id: String) -> int:
	var d := Content.unit(def_id)
	if d.has("wounded_slots"):
		return int(d.wounded_slots)
	return int((cfg().get("capacity", {}) as Dictionary).get(def_id, 0))


## A def that gives its faction medical capability (def med_unit, or any evac capacity).
static func is_med_def(def_id: String) -> bool:
	return capacity(def_id) > 0 or bool(Content.unit(def_id).get("med_unit", false))


static func can_be_wounded(e: Dictionary) -> bool:
	if e.kind != "unit" or not bool(cfg().get("enabled", true)):
		return false
	var d := Content.unit(String(e.def))
	return String(d.get("armor", "")) == "infantry" and HUMAN.has(String(d.get("faction", "")))


## ORCH design rule: fid has medical capability right now: a live, non-wounded own unit of a med def
## (is_med_def) or an own built hospital / field_hospital. Cached per tick in w.cache.med_cap (a
## negative answer is recomputed when a new entity id appears in the same tick); a hint id per
## faction makes the positive case O(1). Never touches sim state.
static func has_medical(w: SimWorld, fid: int) -> bool:
	var mc = w.cache.get("med_cap")
	if mc == null:
		mc = {"tick": -1, "val": {}, "nid": {}, "defs": {}, "hint": {}}
		w.cache["med_cap"] = mc
	if int(mc.tick) != w.tick:
		mc.tick = w.tick
		mc.val = {}
		mc.nid = {}
		mc.defs = {}   # rebuilt each tick: content / rules may be patched between ticks (tests)
	var v = mc.val.get(fid)
	if v != null and (bool(v) or int(mc.nid[fid]) == int(w.next_id)):
		return bool(v)
	var r := _scan_medical(w, fid, mc)
	mc.val[fid] = r
	mc.nid[fid] = int(w.next_id)
	return r


static func _med_unit_ok(u, fid: int, defs: Dictionary) -> bool:
	if u == null or u.kind != "unit" or int(u.owner) != fid or bool(u.get("wounded", false)):
		return false
	var dk := String(u.def)
	var ok = defs.get(dk)
	if ok == null:
		ok = is_med_def(dk)
		defs[dk] = ok
	return bool(ok)


static func _scan_medical(w: SimWorld, fid: int, mc: Dictionary) -> bool:
	var defs: Dictionary = mc.defs
	var hint := int(mc.hint.get(fid, -1))
	if hint >= 0 and _med_unit_ok(w.entities.get(hint), fid, defs):
		return true
	for b in SimIndex.of(w, "building"):
		if int(b.owner) != fid or not bool(b.built) or not w.entities.has(int(b.id)):
			continue
		var bd := Content.building(String(b.def))
		if bool(bd.get("hospital", false)) or bool(bd.get("field_hospital", false)):
			return true
	for u in SimIndex.units_by_owner(w).get(fid, []):
		if _med_unit_ok(u, fid, defs) and w.entities.has(int(u.id)):
			mc.hint[fid] = int(u.id)
			return true
	return false


## Called by Damage before a unit at 0 HP is destroyed. true = keep it alive as Wounded.
static func on_zero_hp(w: SimWorld, e: Dictionary) -> bool:
	if is_wounded(e) or not can_be_wounded(e) or not w.entities.has(int(e.id)):
		return false
	if not has_medical(w, int(e.owner)):
		return false   # ORCH rule: no medics / hospitals -> dies as in G4
	var st := _state(w)
	e.wounded = true
	e.hp = 1.0
	e.wnd_pos = e.pos
	e.target = -1
	e.cooldown = HOLD_FIRE
	e.order = {"type": "idle"}
	Movement.stop_path(e)
	HotState.touch(w, int(e.id))
	st.wounded[int(e.id)] = bleed_ticks()
	for k in ["resup_by", "resume_order", "resup_t"]:   # a claimed unit drops its resupply claim
		e.erase(k)
	w.emit("UnitWounded", {"id": int(e.id), "owner": int(e.owner), "def": String(e.def), "pos": e.pos})
	return true


# ================================================================ command
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if String(cmd.get("type", "")) != "set_auto_evac":
		return "Unknown command."
	var e = w.entities.get(int(cmd.get("unit_id", -1)))
	if e == null or e.kind != "unit" or int(e.owner) != int(cmd.get("issuer", -1)):
		return "Not your unit."
	if capacity(String(e.def)) <= 0:
		return "This unit cannot evacuate wounded."
	if cmd.has("center"):
		var c = cmd.center
		if typeof(c) != TYPE_ARRAY or (c as Array).size() != 2:
			return "Bad center."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var cid := int(cmd.unit_id)
	var e: Dictionary = w.entities[cid]
	var st := _state(w)
	if not bool(cmd.get("on", true)):
		st.evac.erase(cid)   # wounded already aboard stay aboard until it is switched on again
		w.cache.erase("med_evac")
		return
	var center: Array = [float(e.pos.x), float(e.pos.y)]
	if cmd.has("center"):
		center = [float(cmd.center[0]), float(cmd.center[1])]
	st.evac[cid] = {"center": center, "radius": clampf(float(cmd.get("radius", cfg().get("radius", 14))), 2.0, 48.0),
		"phase": "collect", "cur": -1, "fwd": false}
	if not st.carriers.has(cid):
		st.carriers[cid] = []
	w.cache.erase("med_evac")


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("medical")
	if st == null:
		return
	_tick_impl(w, st)


static func _tick_impl(w: SimWorld, st: Dictionary) -> void:
	_bleed(w, st)
	if not (st.evac as Dictionary).is_empty():
		_evac(w, st)


## Every tick: pin, hold fire, ride along aboard, bleed; bled out -> destroyed. Ascending id (a
## carrier that bleeds out drops its passengers before they are processed, as before).
static func _bleed(w: SimWorld, st: Dictionary) -> void:
	var wd: Dictionary = st.wounded
	if wd.is_empty():
		return
	var ids: Array = wd.keys()
	ids.sort()
	var ents: Dictionary = w.entities
	for id in ids:
		var e = ents.get(id)
		if e == null or not e.get("wounded", false):
			wd.erase(id)
			continue
		if e.target != -1:
			e.target = -1
		e.cooldown = HOLD_FIRE
		var cb = e.get("evac_by")
		if cb != null:
			var c = ents.get(cb)
			if c != null:
				var cp: Vector2 = c.pos
				if e.pos != cp:
					e.wnd_pos = cp
					HotState.set_pos(w, id, cp)   # pos only (dict + mirror): cheaper than a full touch
				continue
			e.erase("evac_by")   # carrier lost: back on the ground, bleeding resumes
		if e.moving or not (e.path as Array).is_empty():
			Movement.stop_path(e)
		if e.order.get("type", "idle") != "idle":
			e.order = {"type": "idle"}
		if e.pos != e.wnd_pos:
			e.pos = e.wnd_pos
			HotState.touch(w, id)
		var t: int = wd[id] - 1
		if t > 0:
			wd[id] = t
			continue
		wd.erase(id)
		w.emit("BledOut", {"id": int(id), "owner": int(e.owner), "def": String(e.def)})
		w.destroy(int(id), "bled_out")


## PERF (G5 CR): each carrier decides on its own tick bucket ((tick + _slot(id)) % STEP == 0; _slot
## spreads ids evenly even when carrier ids share id % STEP, so no tick gets every carrier); one shared
## prep per tick (ground wounded bucketed by owner and GRID cell, targets already taken, med
## buildings by owner), path orders throttled (REPATH ticks per target, one order home) and capped
## at MAX_ORDERS per tick (ascending carrier id; the rest retry on their next bucket).
const REPATH := 40
const GRID := 16.0
const MAX_ORDERS := 8

## Runtime cache (never saved; rebuilt from st.evac after a load, a command or an outside change):
## carrier ids bucketed by _slot(id) (ascending) and the live {cur wounded id: carrier id} map.
static func _ecache(w: SimWorld, st: Dictionary) -> Dictionary:
	var evs: Dictionary = st.evac
	var ec = w.cache.get("med_evac")
	if ec != null and is_same(ec.src, evs) and int(ec.n) == evs.size():
		return ec
	var b := []
	for i in STEP:
		b.append([])
	var tk := {}
	for cid in evs:   # insertion order (a later carrier wins), as a per-tick rebuild would
		b[_slot(int(cid))].append(int(cid))
		var cur := int(evs[cid].get("cur", -1))
		if cur >= 0:
			tk[cur] = int(cid)
	for a in b:
		a.sort()
	ec = {"src": evs, "n": evs.size(), "b": b, "taken": tk}
	w.cache["med_evac"] = ec
	return ec


## Decision bucket of carrier id (multiplicative hash, deterministic, in [0, STEP)).
static func _slot(id: int) -> int:
	return ((id * 2654435761) >> 13) % STEP


static func _set_cur(pt: Dictionary, cid: int, ev: Dictionary, v: int) -> void:
	var old := int(ev.get("cur", -1))
	if old >= 0 and int(pt.get(old, -1)) == cid:
		pt.erase(old)
	ev.cur = v
	if v >= 0:
		pt[v] = cid


static func _evac(w: SimWorld, st: Dictionary) -> void:
	var ec := _ecache(w, st)
	var due: Array = ec.b[posmod(-w.tick, STEP)]   # = (tick + _slot(id)) % STEP == 0, ascending id
	if due.is_empty():
		return
	due = due.duplicate()
	var pt: Dictionary = ec.taken                  # live map, kept in step with every ev.cur write
	var taken := pt.duplicate()   # wounded id -> carrier id currently heading for it (this tick)
	var grid := {}    # owner -> {cell key: [wounded on the ground, ascending id]}
	var gall := {}    # id -> wounded on the ground
	var wids: Array = st.wounded.keys()
	wids.sort()
	for id in wids:
		var u = w.entities.get(int(id))
		if u == null or u.has("evac_by"):
			continue
		var g = grid.get(int(u.owner))
		if g == null:
			g = {}
			grid[int(u.owner)] = g
		var k := _gkey(Vector2(u.pos))
		var cell = g.get(k)
		if cell == null:
			g[k] = [u]
		else:
			cell.append(u)
		gall[int(id)] = u
	var meds := {}
	var caps := {}
	var orders := 0
	var c0 := cfg()
	var pick_r := float(c0.get("pickup_radius", 1.5))
	var del_r := float(c0.get("deliver_radius", 2.5))
	for cid in due:
		var c = w.entities.get(cid)
		if c == null or c.kind != "unit":
			_drop_all(w, st, cid)
			_set_cur(pt, cid, st.evac[cid], -1)
			st.evac.erase(cid)
			st.carriers.erase(cid)
			(ec.b[_slot(cid)] as Array).erase(cid)
			ec.n = int(ec.n) - 1
			continue
		var ev: Dictionary = st.evac[cid]
		var load: Array = _clean_load(w, st, cid)
		var cap = caps.get(c.def)
		if cap == null:
			cap = capacity(String(c.def))
			caps[c.def] = cap
		if String(ev.phase) == "collect":
			var tgt = null
			if load.size() < int(cap):
				tgt = _pick_target(c, ev, grid.get(int(c.owner), {}), gall, taken)
			if tgt != null:
				ev.erase("home")
				if (Vector2(tgt.pos) - Vector2(c.pos)).length() <= pick_r:
					var gc: Array = grid[int(c.owner)][_gkey(Vector2(tgt.pos))]   # cell key before the pick-up moves it
					gc.erase(tgt)
					_pick_up(w, c, tgt, load)
					taken.erase(int(tgt.id))
					gall.erase(int(tgt.id))
					_set_cur(pt, cid, ev, -1)
					continue
				if int(ev.cur) != int(tgt.id) or (not bool(c.moving) and w.tick - int(ev.get("tp", -100000)) >= REPATH):
					if orders >= MAX_ORDERS:
						if int(ev.cur) != int(tgt.id):
							_set_cur(pt, cid, ev, -1)   # capped: choose again on the next bucket
						continue
					orders += 1
					Movement.order_move(w, c, tgt.pos)
					ev["tp"] = w.tick
				_set_cur(pt, cid, ev, int(tgt.id))
				taken[int(tgt.id)] = cid
				continue
			_set_cur(pt, cid, ev, -1)
			if load.is_empty():
				var center := Vector2(float(ev.center[0]), float(ev.center[1]))
				if not ev.has("home") and not bool(c.moving) and (Vector2(c.pos) - center).length() > 3.0 and orders < MAX_ORDERS:
					orders += 1
					Movement.order_move(w, c, center)
					ev["home"] = true
				continue
			ev.phase = "deliver"
			ev.fwd = false
			ev["tp"] = -100000
		if load.is_empty():
			ev.phase = "collect"
			continue
		var b = _nearest_med(w, c, bool(ev.fwd), meds)
		if b == null:
			if load.size() < int(cap):
				ev.phase = "collect"   # no (further) hospital: keep collecting, the aboard stay stable
			continue
		ev.erase("home")
		if Construction.footprint_dist(c.pos, b.cell, int(b.size)) <= del_r:
			if bool(c.moving):
				Movement.stop_path(c)
				c.order = {"type": "idle"}
			_deliver(w, st, c, b, load, ev)
		elif not bool(c.moving) and w.tick - int(ev.get("tp", -100000)) >= REPATH and orders < MAX_ORDERS:
			orders += 1
			Movement.order_move(w, c, _bcenter(b))
			ev["tp"] = w.tick


static func _gkey(p: Vector2) -> int:
	return int(floorf(p.x / GRID)) * 65536 + int(floorf(p.y / GRID))


## The carrier's load with dead / healed / dropped entries removed (kept as the same array when
## nothing changed and the entity mirror e.evac_load already matches).
static func _clean_load(w: SimWorld, st: Dictionary, cid: int) -> Array:
	var cur = st.carriers.get(cid)
	var c = w.entities.get(cid)
	if cur != null and c != null and c.has("evac_load") and c.evac_load == cur:
		var ok := true
		for id in cur:
			var u = w.entities.get(int(id))
			if u == null or not is_wounded(u) or int(u.get("evac_by", -1)) != cid:
				ok = false
				break
		if ok:
			return cur
	var keep := []
	for id in st.carriers.get(cid, []):
		var u = w.entities.get(int(id))
		if u != null and is_wounded(u) and int(u.get("evac_by", -1)) == cid:
			keep.append(int(id))
	st.carriers[cid] = keep
	if c != null:
		c.evac_load = keep.duplicate()
	return keep


## The carrier's current target if still valid, else the nearest free wounded of its side in its area
## (ties by lowest id). Only the GRID cells overlapping the area are scanned.
static func _pick_target(c: Dictionary, ev: Dictionary, grid: Dictionary, gall: Dictionary, taken: Dictionary):
	var cid := int(c.id)
	var center := Vector2(float(ev.center[0]), float(ev.center[1]))
	var rad := float(ev.radius)
	var r2 := rad * rad
	var cur := int(ev.cur)
	if cur >= 0:
		var cu = gall.get(cur)
		if cu != null and int(cu.owner) == int(c.owner) and int(taken.get(cur, cid)) == cid \
				and (Vector2(cu.pos) - center).length_squared() <= r2:
			return cu
	if grid.is_empty():
		return null
	var best = null
	var bd := INF
	var bid := 0
	var cp := Vector2(c.pos)
	var x0 := int(floorf((center.x - rad) / GRID))
	var x1 := int(floorf((center.x + rad) / GRID))
	var y0 := int(floorf((center.y - rad) / GRID))
	var y1 := int(floorf((center.y + rad) / GRID))
	for gx in range(x0, x1 + 1):
		for gy in range(y0, y1 + 1):
			var cell = grid.get(gx * 65536 + gy)
			if cell == null:
				continue
			for u in cell:
				var id := int(u.id)
				if int(taken.get(id, cid)) != cid:
					continue
				if (Vector2(u.pos) - center).length_squared() > r2:
					continue
				var d := (Vector2(u.pos) - cp).length_squared()
				if d < bd or (d == bd and id < bid):
					bd = d
					best = u
					bid = id
	return best


static func _pick_up(w: SimWorld, c: Dictionary, u: Dictionary, load: Array) -> void:
	u.evac_by = int(c.id)
	u.pos = c.pos
	u.wnd_pos = c.pos
	load.append(int(u.id))
	c.evac_load = load.duplicate()
	HotState.touch(w, int(u.id))
	w.emit("WoundedPickedUp", {"carrier": int(c.id), "id": int(u.id), "owner": int(c.owner)})


## Field Hospital: heal light wounds, keep the rest aboard (forward). Hospital: heal everyone.
static func _deliver(w: SimWorld, st: Dictionary, c: Dictionary, b: Dictionary, load: Array, ev: Dictionary) -> void:
	var hosp := bool(Content.building(String(b.def)).get("hospital", false))
	var light_left := bleed_ticks() - int(float(cfg().get("light_s", 30)) * 20.0)
	var keep := []
	for id in load:
		var u = w.entities.get(int(id))
		if u == null:
			continue
		if hosp or int(st.wounded.get(int(id), 0)) >= light_left:
			_revive(w, st, u, b)
		else:
			keep.append(int(id))
	load.clear()
	load.append_array(keep)
	c.evac_load = keep.duplicate()
	ev.phase = "deliver" if not keep.is_empty() else "collect"
	ev.fwd = not keep.is_empty()


## Healed: back beside the building at full hp / ammo / fuel / squad, free (same entity id).
static func _revive(w: SimWorld, st: Dictionary, u: Dictionary, b: Dictionary) -> void:
	var id := int(u.id)
	st.wounded.erase(id)
	for k in ["wounded", "wnd_pos", "evac_by"]:
		u.erase(k)
	var d := Content.unit(String(u.def))
	u.hp = float(u.get("max_hp", d.get("hp", 1)))
	if d.has("ammo_max") and u.has("ammo"):
		u.ammo = int(d.ammo_max)
	if d.has("fuel_max") and u.has("fuel"):
		u.fuel = float(d.fuel_max)
	if u.has("squad_size") and u.has("squad_alive"):
		u.squad_alive = u.squad_size
	if u.has("morale") and d.has("morale"):
		u.morale = type_convert(d.morale, typeof(u.morale))
	if u.has("broken"):
		u.broken = false
	u.cooldown = 0.0
	u.target = -1
	u.order = {"type": "idle"}
	Movement.stop_path(u)
	var mc := String(d.get("move_class", "foot"))
	var p := _bcenter(b) + Vector2(float(b.size) * 0.5 + 1.0, 0.0)
	u.pos = Vector2(Movement.nearest_free_cell(w, w.cell_of(p), mc, Movement.team_of(w, u))) + Vector2(0.5, 0.5)
	u.supply_prev_pos = u.pos
	HotState.touch(w, id)
	w.emit("Reinforcement", {"id": id, "owner": int(u.owner), "def": String(u.def), "building": int(b.id), "free": true})


static func _drop_all(w: SimWorld, st: Dictionary, cid: int) -> void:
	for id in st.carriers.get(cid, []):
		var u = w.entities.get(int(id))
		if u != null and int(u.get("evac_by", -1)) == cid:
			u.erase("evac_by")
			u.wnd_pos = u.pos


static func _nearest_med(w: SimWorld, c: Dictionary, hosp_only: bool, meds: Dictionary):
	var fid := int(c.owner)
	if not meds.has(fid):   # per-tick cache (local): own built Hospitals / Field Hospitals, ascending id
		var l := []
		for b in SimIndex.of(w, "building"):
			if int(b.owner) != fid or not bool(b.built) or not w.entities.has(int(b.id)):
				continue
			var d := Content.building(String(b.def))
			if bool(d.get("hospital", false)) or bool(d.get("field_hospital", false)):
				l.append([b, bool(d.get("hospital", false))])
		meds[fid] = l
	var best = null
	var bd := INF
	for q in meds[fid]:
		if hosp_only and not bool(q[1]):
			continue
		var b: Dictionary = q[0]
		var dist := Construction.footprint_dist(c.pos, b.cell, int(b.size))
		if dist < bd:
			bd = dist
			best = b
	return best


static func _bcenter(b: Dictionary) -> Vector2:
	return Vector2(b.cell) + Vector2(float(b.size), float(b.size)) * 0.5
