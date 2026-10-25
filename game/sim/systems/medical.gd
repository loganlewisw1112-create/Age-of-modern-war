extends RefCounted
## Medical (owner: SUPPORT). Wounded state, auto evac, hospitals. CONTRACTS_G5 sections 3.4, 4, 5, 6, 10.
## Command: set_auto_evac {issuer, unit_id, on: bool, center?: [x,y], radius?}
## - Wounded (D16): Damage calls on_zero_hp(w, e) before destroying a unit (wired by CORE10K). Human
##   infantry (def armor "infantry", def faction human_a / human_b) is kept alive: wounded = true,
##   hp 1, pinned in place (e.wnd_pos), no orders, weapon held (cooldown pinned), still counted in pop.
##   A second 0 hp (splash) kills it. Not evacuated within rules.medical.bleed_out_s (60 s) -> destroyed.
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


static func can_be_wounded(e: Dictionary) -> bool:
	if e.kind != "unit" or not bool(cfg().get("enabled", true)):
		return false
	var d := Content.unit(String(e.def))
	return String(d.get("armor", "")) == "infantry" and HUMAN.has(String(d.get("faction", "")))


## Called by Damage before a unit at 0 HP is destroyed. true = keep it alive as Wounded.
static func on_zero_hp(w: SimWorld, e: Dictionary) -> bool:
	if is_wounded(e) or not can_be_wounded(e) or not w.entities.has(int(e.id)):
		return false
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
		return
	var center: Array = [float(e.pos.x), float(e.pos.y)]
	if cmd.has("center"):
		center = [float(cmd.center[0]), float(cmd.center[1])]
	st.evac[cid] = {"center": center, "radius": clampf(float(cmd.get("radius", cfg().get("radius", 14))), 2.0, 48.0),
		"phase": "collect", "cur": -1, "fwd": false}
	if not st.carriers.has(cid):
		st.carriers[cid] = []


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


## Every tick: pin, hold fire, ride along aboard, bleed; bled out -> destroyed.
static func _bleed(w: SimWorld, st: Dictionary) -> void:
	var wd: Dictionary = st.wounded
	if wd.is_empty():
		return
	var ids: Array = wd.keys()
	ids.sort()
	for id in ids:
		var e = w.entities.get(int(id))
		if e == null or not is_wounded(e):
			wd.erase(id)
			continue
		e.target = -1
		e.cooldown = HOLD_FIRE
		if e.has("evac_by"):
			var c = w.entities.get(int(e.evac_by))
			if c != null:
				if e.pos != c.pos:
					e.pos = c.pos
					e.wnd_pos = c.pos
					HotState.touch(w, int(id))
				continue
			e.erase("evac_by")   # carrier lost: back on the ground, bleeding resumes
		if bool(e.moving) or not (e.path as Array).is_empty():
			Movement.stop_path(e)
		if String(e.order.get("type", "idle")) != "idle":
			e.order = {"type": "idle"}
		if e.pos != e.wnd_pos:
			e.pos = e.wnd_pos
			HotState.touch(w, int(id))
		var t := int(wd[id]) - 1
		if t > 0:
			wd[id] = t
			continue
		wd.erase(id)
		w.emit("BledOut", {"id": int(id), "owner": int(e.owner), "def": String(e.def)})
		w.destroy(int(id), "bled_out")


## PERF (G5 CR): each carrier decides on its own tick bucket ((tick + id) % STEP == 0); one shared
## prep per tick (ground wounded by owner, targets already taken, med buildings by owner), and path
## orders are throttled (REPATH ticks per target, one order home), so idle carriers cost ~nothing.
const REPATH := 40

static func _evac(w: SimWorld, st: Dictionary) -> void:
	var due := []
	var taken := {}   # wounded id -> carrier id currently heading for it
	for cid in st.evac:
		if (w.tick + int(cid)) % STEP == 0:
			due.append(int(cid))
		var cur := int(st.evac[cid].get("cur", -1))
		if cur >= 0:
			taken[cur] = int(cid)
	if due.is_empty():
		return
	due.sort()
	var ground := {}   # owner -> [wounded on the ground, ascending id]
	var wids: Array = st.wounded.keys()
	wids.sort()
	for id in wids:
		var u = w.entities.get(int(id))
		if u == null or u.has("evac_by"):
			continue
		if not ground.has(int(u.owner)):
			ground[int(u.owner)] = []
		ground[int(u.owner)].append(u)
	var meds := {}
	var c0 := cfg()
	var pick_r := float(c0.get("pickup_radius", 1.5))
	var del_r := float(c0.get("deliver_radius", 2.5))
	for cid in due:
		var c = w.entities.get(cid)
		if c == null or c.kind != "unit":
			_drop_all(w, st, cid)
			st.evac.erase(cid)
			st.carriers.erase(cid)
			continue
		var ev: Dictionary = st.evac[cid]
		var load: Array = _clean_load(w, st, cid)
		var cap := capacity(String(c.def))
		if String(ev.phase) == "collect":
			var tgt = null
			if load.size() < cap:
				tgt = _pick_target(c, ev, ground.get(int(c.owner), []), taken)
			if tgt != null:
				ev.erase("home")
				if (Vector2(tgt.pos) - Vector2(c.pos)).length() <= pick_r:
					_pick_up(w, c, tgt, load)
					taken.erase(int(tgt.id))
					(ground[int(c.owner)] as Array).erase(tgt)
					ev.cur = -1
					continue
				if int(ev.cur) != int(tgt.id) or (not bool(c.moving) and w.tick - int(ev.get("tp", -100000)) >= REPATH):
					Movement.order_move(w, c, tgt.pos)
					ev["tp"] = w.tick
				ev.cur = int(tgt.id)
				taken[int(tgt.id)] = cid
				continue
			ev.cur = -1
			if load.is_empty():
				var center := Vector2(float(ev.center[0]), float(ev.center[1]))
				if not ev.has("home") and not bool(c.moving) and (Vector2(c.pos) - center).length() > 3.0:
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
			if load.size() < cap:
				ev.phase = "collect"   # no (further) hospital: keep collecting, the aboard stay stable
			continue
		ev.erase("home")
		if Construction.footprint_dist(c.pos, b.cell, int(b.size)) <= del_r:
			if bool(c.moving):
				Movement.stop_path(c)
				c.order = {"type": "idle"}
			_deliver(w, st, c, b, load, ev)
		elif not bool(c.moving) and w.tick - int(ev.get("tp", -100000)) >= REPATH:
			Movement.order_move(w, c, _bcenter(b))
			ev["tp"] = w.tick


static func _clean_load(w: SimWorld, st: Dictionary, cid: int) -> Array:
	var keep := []
	for id in st.carriers.get(cid, []):
		var u = w.entities.get(int(id))
		if u != null and is_wounded(u) and int(u.get("evac_by", -1)) == cid:
			keep.append(int(id))
	st.carriers[cid] = keep
	var c = w.entities.get(cid)
	if c != null:
		c.evac_load = keep.duplicate()
	return keep


## The carrier's current target if still valid, else the nearest free wounded of its side in its area.
static func _pick_target(c: Dictionary, ev: Dictionary, ground: Array, taken: Dictionary):
	var cid := int(c.id)
	var center := Vector2(float(ev.center[0]), float(ev.center[1]))
	var r2 := float(ev.radius) * float(ev.radius)
	var best = null
	var bd := INF
	for u in ground:
		var id := int(u.id)
		if int(taken.get(id, cid)) != cid:
			continue
		if (Vector2(u.pos) - center).length_squared() > r2:
			continue
		if id == int(ev.cur):
			return u
		var d := (Vector2(u.pos) - Vector2(c.pos)).length_squared()
		if d < bd:
			bd = d
			best = u
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
