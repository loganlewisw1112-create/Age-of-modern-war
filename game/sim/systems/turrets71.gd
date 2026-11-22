extends RefCounted
## Turrets71 (owner: BASTION71, G7.1 wave 2). docs/G71_SCOPE.md B1 (rotary railgun, laser CIWS, HPM), G3 (flak tower),
## I2 (disabled, not dead; drone repairs). Content: content/g71/defs_g71_defences.json (buildings carry a "t71" block
## and NO def.weapon / NO "t7" block, so Combat's tower path and Turrets7 both skip them: this system drives them),
## rules.g71_defences.disable in content/g71/rules_g71_defences.json. Every number PROVISIONAL.
##   rotary  Rotary railgun: spins up (spin_up_s), then fires a slug every fire_every ticks; every slug pierces the
##           line (up to t71.pierce more enemies within t71.lane of it, damage x falloff^n) found through the shared
##           Turrets7 bucket grid along the line only (never a scan of all units). Heat builds per slug; at heat_max
##           the barrels are in FORCED COOLDOWN until heat <= heat_resume. Power draw = def.power (Airdef.source_active).
##   laser   Laser CIWS: a held beam; dwell (dwell_s + target hp x dwell_per_hp) on one target kills it; switching
##           target restarts the dwell; heat per beam tick, forced cooldown at heat_max; a smoke cloud across the line
##           of fire cuts the range to smoke_range_mult (Senses7 clouds).
##   hpm     HPM emitter: when >= min_targets enemy units are in the cone it fires: Machine units are held (MachineEW7
##           stun, stun_s), airborne drones drop; recharge = weapon cooldown (long).
##   flak    Flak tower: proximity fuse. Bursts at the centroid of the densest cluster of >= min_cluster enemy aircraft
##           within fuse_r of each other; every enemy aircraft inside burst_r takes damage x (1 - 0.5 d / r).
## Disabled, not dead (Last Protocol only): on_zero_hp(w, b) is the lethal-hit hook (Damage.apply_hit, by change
## request to DAMAGE71): a defence that would die is left DISABLED at hp_frac x max hp; a second lethal hit while
## disabled destroys it. One hit of >= jam_hit_frac of max hp jams it for jam_s (seen as an hp drop per tick).
## Engineers revive it (repair order next to it: revive_s), maintenance drones (def.maint71) in drone_revive_s.
## State (saved, hashed; created only on a first act / disable, so a match without these never has it):
##   w.sys_state.turrets71 = {ver, ready, aim, heat, spin, cool, dwell, dis, jam, hp0, rev}
## Caches (runtime only): w.cache.t71_sub (turret ids by next_id).
## Determinism: ascending ids, integer ticks, w.rng only for the slug accuracy roll.
## Events: ShotFired (t71 kind), T71Rail {bid,from,to,n}, T71Beam {bid,target,from,to,dwell,need}, T71BeamKill,
## T71Hpm {bid,pos,dir,range,half,n,drones}, T71Flak {bid,pos,r,n}, T71Cool {bid,on}, T71Disabled {id,def},
## T71Jammed {id,until}, T71Revived {id,by}.
const VER := 1
const SCAN := 10
const BK := 8.0
const T7 = preload("res://sim/systems/turrets7.gd")
const HotState = preload("res://sim/hot_state.gd")
const Airdef = preload("res://sim/systems/airdef.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Traverse7 = preload("res://sim/systems/traverse7.gd")   # lay before fire (t71.traverse_deg)

static var _ew = null


static func _mew():
	if _ew == null:
		_ew = load("res://sim/systems/machine_ew7.gd")
	return _ew


# ================================================================ content
static func R() -> Dictionary:
	return Content.rules().get("g71_defences", {})


static func is_t71(def_id: String) -> bool:
	return Content.building(def_id).has("t71")


static func cfg_of(def_id: String) -> Dictionary:
	return Content.building(def_id).get("t71", {})


static func weapon_of(def_id: String) -> Dictionary:
	return Content.weapon(String(cfg_of(def_id).get("weapon", "")))


static func defs() -> Array:
	var out := []
	for id in Content.ids("buildings"):
		if is_t71(String(id)):
			out.append(String(id))
	return out


## True for any defence the disabled / jam rules apply to (this system's turrets, the Turrets7 turrets and the Combat
## towers with a def.weapon: wall_tower, howitzer_pit, sam_site... held by Combat._tower_tick's guard, ARMY71 CR 1720).
static func is_defence(def_id: String) -> bool:
	var d := Content.building(def_id)
	return d.has("t71") or d.has("t7") or String(d.get("weapon", "")) != ""


static func _ticks(sec: float) -> int:
	return maxi(roundi(sec * SimWorld.TICK_RATE), 1)


# ================================================================ state + lists
static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get("turrets71")
	if s == null:
		s = {"ver": VER, "ready": {}, "aim": {}, "heat": {}, "spin": {}, "cool": {}, "dwell": {}, "dis": {}, "jam": {},
			"hp0": {}, "rev": {}, "dwell_t": {}}
		w.sys_state["turrets71"] = s
	return s


static func state(w: SimWorld):
	return w.sys_state.get("turrets71")


static func _add(sub: Dictionary, e: Dictionary) -> void:
	if e.kind == "building" and is_t71(String(e.def)):
		(sub.ids as Array).append(int(e.id))


## Live Turrets71 turret ids, ascending (incremental by next_id, like Turrets7.turret_ids).
static func turret_ids(w: SimWorld) -> Array:
	var sub = w.cache.get("t71_sub")
	var nid := int(w.next_id)
	if sub == null:
		sub = {"ids": [], "next_id": nid}
		var ids: Array = w.entities.keys()
		ids.sort()
		for id in ids:
			_add(sub, w.entities[id])
		w.cache["t71_sub"] = sub
	elif nid > int(sub.next_id):
		for id in range(int(sub.next_id), nid):
			var e = w.entities.get(id)
			if e != null:
				_add(sub, e)
		sub.next_id = nid
	var arr: Array = sub.ids
	for id in arr:
		if not w.entities.has(id):
			var keep := []
			var s = w.sys_state.get("turrets71")
			for j in arr:
				if w.entities.has(j):
					keep.append(j)
				elif s != null:
					for k in ["ready", "aim", "heat", "spin", "cool", "dwell", "dis", "jam", "hp0", "rev", "dwell_t"]:
						(s[k] as Dictionary).erase(j)
			sub.ids = keep
			return keep
	return arr


## Every defence the disabled rules apply to, ascending (Turrets71 + Turrets7 turrets).
static func _defence_ids(w: SimWorld) -> Array:
	var a: Array = turret_ids(w)
	var b: Array = T7.turret_ids(w)
	if b.is_empty():
		return a
	var out := a.duplicate()
	out.append_array(b)
	out.sort()
	return out


# ================================================================ public queries
static func disabled(w: SimWorld, e: Dictionary) -> bool:
	var s = w.sys_state.get("turrets71")
	return s != null and (s.dis as Dictionary).has(int(e.id))


static func jammed(w: SimWorld, e: Dictionary) -> bool:
	var s = w.sys_state.get("turrets71")
	return s != null and int((s.jam as Dictionary).get(int(e.id), 0)) > w.tick


## True while turret b may not fire (disabled, jammed or in forced cooldown). Turrets7 / WallTurret7 call this.
static func blocked(w: SimWorld, b: Dictionary) -> bool:
	var s = w.sys_state.get("turrets71")
	if s == null:
		return false
	var id := int(b.id)
	return (s.dis as Dictionary).has(id) or int((s.jam as Dictionary).get(id, 0)) > w.tick


static func heat_of(w: SimWorld, e: Dictionary) -> int:
	var s = w.sys_state.get("turrets71")
	return 0 if s == null else int((s.heat as Dictionary).get(int(e.id), 0))


static func spin_of(w: SimWorld, e: Dictionary) -> int:
	var s = w.sys_state.get("turrets71")
	return 0 if s == null else int((s.spin as Dictionary).get(int(e.id), 0))


static func cooling(w: SimWorld, e: Dictionary) -> bool:
	var s = w.sys_state.get("turrets71")
	return s != null and (s.cool as Dictionary).has(int(e.id))


## Per-turret display rows for the render snapshot provider: [[id, heat, spin, flags]], flags bit 1 disabled, 2 jammed,
## 4 forced cooldown. Ascending ids; [] when the state does not exist.
static func rows(w: SimWorld) -> Array:
	var s = w.sys_state.get("turrets71")
	if s == null:
		return []
	var ids := {}
	for k in ["heat", "spin", "cool", "dis", "jam"]:
		for id in (s[k] as Dictionary).keys():
			ids[int(id)] = true
	var keys: Array = ids.keys()
	keys.sort()
	var out := []
	for id in keys:
		if not w.entities.has(id):
			continue
		var f := 0
		if (s.dis as Dictionary).has(id):
			f |= 1
		if int((s.jam as Dictionary).get(id, 0)) > w.tick:
			f |= 2
		if (s.cool as Dictionary).has(id):
			f |= 4
		out.append([id, int((s.heat as Dictionary).get(id, 0)), int((s.spin as Dictionary).get(id, 0)), f])
	return out


# ================================================================ disabled, not dead
## Lethal-hit hook (Damage.apply_hit before destroy, building targets): true = keep the building alive (disabled).
static func on_zero_hp(w: SimWorld, b: Dictionary) -> bool:
	if b.kind != "building" or not LastProtocol.active(w) or not is_defence(String(b.def)):
		return false
	var dr: Dictionary = R().get("disable", {})
	if not bool(dr.get("enabled", false)):
		return false
	var s := _st(w)
	var id := int(b.id)
	if (s.dis as Dictionary).has(id):
		return false   # a second lethal hit while disabled destroys it
	s.dis[id] = w.tick
	(s.rev as Dictionary).erase(id)
	b.hp = snappedf(float(b.max_hp) * float(dr.get("hp_frac", 0.12)), 0.01)
	s.hp0[id] = b.hp
	w.emit("T71Disabled", {"id": id, "def": String(b.def), "owner": int(b.owner)})
	return true


## Starts / continues a revive of disabled turret b by unit `by` (-1 = a maintenance drone swarm). True = accepted.
static func revive(w: SimWorld, b: Dictionary, by: int) -> bool:
	var s = w.sys_state.get("turrets71")
	if s == null or not (s.dis as Dictionary).has(int(b.id)):
		return false
	var id := int(b.id)
	var dr: Dictionary = R().get("disable", {})
	var secs := float(dr.get("revive_s", 8.0)) if by >= 0 else float(dr.get("drone_revive_s", 20.0))
	var rv = (s.rev as Dictionary).get(id)
	if rv == null:
		s.rev[id] = {"by": by, "left": _ticks(secs), "tot": _ticks(secs)}
	elif by >= 0 and int(rv.by) < 0:
		s.rev[id] = {"by": by, "left": mini(int(rv.left), _ticks(secs)), "tot": _ticks(secs)}
	return true


static func _finish_revive(w: SimWorld, s: Dictionary, b: Dictionary, by: int) -> void:
	var id := int(b.id)
	var dr: Dictionary = R().get("disable", {})
	(s.dis as Dictionary).erase(id)
	(s.rev as Dictionary).erase(id)
	(s.jam as Dictionary).erase(id)
	(s.heat as Dictionary).erase(id)
	(s.cool as Dictionary).erase(id)
	b.hp = snappedf(maxf(float(b.hp), float(b.max_hp) * float(dr.get("revive_hp_frac", 0.5))), 0.01)
	s.hp0[id] = b.hp
	w.emit("T71Revived", {"id": id, "by": by, "owner": int(b.owner)})


## Revive progress of disabled turrets, jam detection by hp drop, forced-cooldown bookkeeping. Ascending ids.
static func _upkeep(w: SimWorld, s: Dictionary) -> void:
	var dr: Dictionary = R().get("disable", {})
	var jam_frac := float(dr.get("jam_hit_frac", 0.35))
	var jam_t := _ticks(float(dr.get("jam_s", 6.0)))
	var lp := LastProtocol.active(w)
	if lp and bool(dr.get("enabled", false)):
		for id in _defence_ids(w):
			var b = w.entities.get(id)
			if b == null or not bool(b.get("built", false)):
				continue
			var hp := float(b.hp)
			var h0 := float((s.hp0 as Dictionary).get(id, hp))
			if h0 - hp >= jam_frac * float(b.max_hp) and not (s.dis as Dictionary).has(id):
				s.jam[id] = w.tick + jam_t
				w.emit("T71Jammed", {"id": id, "until": w.tick + jam_t})
			if h0 != hp or not (s.hp0 as Dictionary).has(id):
				s.hp0[id] = hp
	var ids: Array = (s.rev as Dictionary).keys()
	ids.sort()
	for id in ids:
		var b = w.entities.get(id)
		if b == null or not (s.dis as Dictionary).has(id):
			(s.rev as Dictionary).erase(id)
			continue
		var rv: Dictionary = s.rev[id]
		var by := int(rv.by)
		if by >= 0:
			var u = w.entities.get(by)
			var ok := u != null and Vector2(u.pos).distance_to(T7.center(b)) <= float(dr.get("reach", 3.5)) + float(b.size) * 0.5
			if ok:
				var ord: Dictionary = u.get("order", {})
				ok = String(ord.get("type", "")) == "repair" and int(ord.get("target_id", -1)) == int(id)
			if not ok:
				(s.rev as Dictionary).erase(id)
				continue
		rv.left = int(rv.left) - 1
		if int(rv.left) <= 0:
			_finish_revive(w, s, b, by)
		else:
			s.rev[id] = rv


## Engineers (repair order, next to the turret) and maintenance drones start revives on their own. A disabled defence
## nobody is working on calls the nearest IDLE helper of its side within dispatch_r (PROVISIONAL): an engineer
## (def.can_build) gets a normal Repair order on it, a maintenance drone (def.maint71) walks to it. Units on Hold
## Position or on any player order are never taken. Every 5 ticks, only while something is disabled (LP).
static func _helpers(w: SimWorld, s: Dictionary) -> void:
	if (s.dis as Dictionary).is_empty():
		return
	var dr: Dictionary = R().get("disable", {})
	var mr := float(dr.get("maint_r", 14.0))
	var reach := float(dr.get("reach", 3.5))
	var disp := float(dr.get("dispatch_r", 40.0))
	var dids: Array = (s.dis as Dictionary).keys()
	dids.sort()
	var owners := {}
	for id in dids:
		var b0 = w.entities.get(id)
		if b0 != null:
			owners[int(b0.owner)] = true
	var fids: Array = owners.keys()
	fids.sort()
	var drones := []
	var engs := []
	var worked := {}   # turret id -> true while an engineer holds a repair order on it
	var ubo: Dictionary = SimIndex.units_by_owner(w)
	for fid in fids:
		var hl := _help_lists(w, int(fid), ubo.get(int(fid), []))   # BASTION71-8: def tests once per unit
		for u in hl[0]:
			if w.entities.has(int(u.id)):
				drones.append(u)
		for u in hl[1]:
			if w.entities.has(int(u.id)) and not bool(u.get("wounded", false)):
				# BASTION71-6: a wounded (downed) engineer looks idle, but Medical resets its order every tick: never call it
				engs.append(u)
				var o0: Dictionary = u.get("order", {})
				if String(o0.get("type", "")) == "repair":
					worked[int(o0.get("target_id", -1))] = true
	for id in dids:
		var b = w.entities.get(id)
		var rv0 = (s.rev as Dictionary).get(id)
		if b == null or (rv0 != null and int(rv0.by) >= 0):
			continue   # an engineer revive runs; a slow drone revive (by -1) is still taken over by an engineer below
		var bc := T7.center(b)
		var own := int(b.owner)
		var started := false
		for u in engs:   # an engineer that walked up on its repair order starts the fast revive
			var o: Dictionary = u.get("order", {})
			if int(u.owner) == own and String(o.get("type", "")) == "repair" and int(o.get("target_id", -1)) == int(id) 					and Vector2(u.pos).distance_to(bc) <= reach + float(b.size) * 0.5:
				started = revive(w, b, int(u.id))
				break
		if started:
			continue
		var best = null
		var bd := INF
		var far = null
		var fd := INF
		for u in drones:
			if int(u.owner) != own:
				continue
			var d := Vector2(u.pos).distance_to(bc)
			if d <= mr and d < bd:
				bd = d
				best = u
			elif d > mr and d <= disp and d < fd and _idle(u):
				fd = d
				far = u
		if best != null and rv0 == null:
			revive(w, b, -1)
			continue
		if not worked.has(int(id)):
			var eng = null
			var ed := INF
			for u in engs:
				if int(u.owner) != own or not _idle(u):
					continue
				var d2 := Vector2(u.pos).distance_to(bc)
				if d2 <= disp and d2 < ed:
					ed = d2
					eng = u
			if eng != null:
				var cmd := {"type": "repair", "issuer": own, "unit_ids": [int(eng.id)], "target_id": int(id)}
				if SimWorld.Repair.validate_command(w, cmd) == "":
					SimWorld.Repair.apply_command(w, cmd)
					worked[int(id)] = true
					w.emit("T71Call", {"id": int(id), "by": int(eng.id)})
		if far != null and rv0 == null:
			SimWorld.Construction.approach_point(w, far, int(id), bc)
			w.emit("T71Call", {"id": int(id), "by": -int(far.id) - 1})


## Idle = free for an automatic job: not moving, no order but idle (Hold Position and player orders are kept).
static func _idle(u: Dictionary) -> bool:
	return not bool(u.get("moving", false)) and String((u.get("order", {}) as Dictionary).get("type", "idle")) == "idle"


## Maintenance drones repair damaged (not disabled) turrets in range: hp per second, mid-wave.
static func _maint_repair(w: SimWorld, s: Dictionary) -> void:
	var rep := float(R().get("disable", {}).get("maint_hp_per_s", 40.0))
	var rr := float(R().get("disable", {}).get("maint_r", 14.0))
	var any := false
	var drones := []
	var ubo: Dictionary = SimIndex.units_by_owner(w)
	for fid in w.factions.keys():
		var src = ubo.get(int(fid))
		if src == null:
			continue
		for u in _help_lists(w, int(fid), src)[0]:   # BASTION71-8: def tests once per unit
			if w.entities.has(int(u.id)):
				drones.append(u)
				any = true
	if not any:
		return
	for id in _defence_ids(w):
		var b = w.entities.get(id)
		if b == null or not bool(b.get("built", false)) or (s.dis as Dictionary).has(id):
			continue
		if float(b.hp) >= float(b.max_hp):
			continue
		var bc := T7.center(b)
		var n := 0
		for u in drones:
			if int(u.owner) == int(b.owner) and Vector2(u.pos).distance_to(bc) <= rr:
				n += 1
		if n > 0:
			b.hp = snappedf(minf(float(b.max_hp), float(b.hp) + rep * float(mini(n, 3)) * 10.0 / float(SimWorld.TICK_RATE)), 0.01)


# ================================================================ lane query (rotary pierce)
## Enemy ground units within `lane` of the segment from -> from + dir x rr, ahead of the muzzle, as [[u, entity]]
## ascending u. Visits only the 8-tile buckets the lane touches (shared Turrets7 grid): never every unit.
static func lane_units(w: SimWorld, fid: int, from: Vector2, dir: Vector2, rr: float, lane: float) -> Array:
	# BASTION71-8 (cost): the same rows as before. A bucket is read only when the lane band can reach it (bucket rect to
	# segment distance <= lane, with a margin), and the geometry test runs before the owner / air tests (enemy test cached
	# per owner for the query). Positions are read exactly like HotState.get_pos.
	var g: Dictionary = T7._grid(w)
	var hot = w.get("hot")
	var hcap := 0
	var hlive := PackedByteArray()
	var hpos := PackedVector2Array()
	if hot != null:
		hcap = int(hot.cap)
		hlive = hot.live
		hpos = hot.pos
	var seen := {}
	var en := {}
	var rows := []
	var step := BK * 0.5
	var s := 0.0
	var tip := from + dir * rr
	var band := dir.length_squared() > 0.25
	while s <= rr + step:
		var p := from + dir * minf(s, rr)
		var pad := step * 0.5 + lane + 0.1
		for by in range(floori((p.y - pad) / BK), floori((p.y + pad) / BK) + 1):
			for bx in range(floori((p.x - pad) / BK), floori((p.x + pad) / BK) + 1):
				var k := bx + by * 4096
				if seen.has(k):
					continue
				seen[k] = true
				var arr = g.get(k)
				if arr == null:
					continue
				if band and _rect_seg_d(Vector2(bx * BK, by * BK), from, tip) > lane + 0.05:
					continue
				for e in arr:
					var id := int(e.id)
					var q: Vector2
					if id >= 0 and id < hcap and hlive[id] == 1:
						q = hpos[id]
					else:
						q = e.pos
					var v := q - from
					var u := v.dot(dir)
					if u <= 0.0 or u > rr or absf(v.cross(dir)) > lane:
						continue
					if not w.entities.has(id):
						continue
					var o := int(e.owner)
					var ev = en.get(o)
					if ev == null:
						ev = w.is_enemy(fid, o)
						en[o] = ev
					if not ev or T7._airborne(e):
						continue
					rows.append([u, id])
		s += step
	rows.sort()
	return rows


## Distance from the bucket rect [o, o + BK] to segment a-b (0 when they touch).
static func _rect_seg_d(o: Vector2, a: Vector2, b: Vector2) -> float:
	var r := Rect2(o, Vector2(BK, BK))
	if r.has_point(a) or r.has_point(b):
		return 0.0
	var c := [o, o + Vector2(BK, 0.0), o + Vector2(BK, BK), o + Vector2(0.0, BK)]
	var best := INF
	for i in 4:
		var p0: Vector2 = c[i]
		var p1: Vector2 = c[(i + 1) % 4]
		if Geometry2D.segment_intersects_segment(a, b, p0, p1) != null:
			return 0.0
		var cp: PackedVector2Array = Geometry2D.get_closest_points_between_segments(a, b, p0, p1)
		best = minf(best, cp[0].distance_to(cp[1]))
	return best


## BASTION71-8 (cost): T7.pick with the same result: the lowest key (rank x 1e5 + distance x 10 + id x 1e-6) among the
## same candidates that pass can_engage; keys are distinct, so the visiting order does not matter. Cheaper: the enemy
## test is cached per owner, a candidate whose key cannot beat the best even at rank 0 skips rank and can_engage, and
## rank is cached per (owner, def) for plain units. Inert7 off (the on/off check): T7.pick itself.
static func _pick71(w: SimWorld, b: Dictionary, c: Dictionary, wd: Dictionary):
	if not T7.Inert7.enabled:
		return T7.pick(w, b, c, wd)
	var bp := T7.center(b)
	var fid := int(b.owner)
	var r := float(wd.get("range", 0))
	var r2 := r * r
	var g: Dictionary = T7._grid(w)
	var hot = w.get("hot")
	var hcap := 0
	var hlive := PackedByteArray()
	var hpos := PackedVector2Array()
	if hot != null:
		hcap = int(hot.cap)
		hlive = hot.live
		hpos = hot.pos
	var en := {}
	var rk := {}
	var best = null
	var bk := INF
	for by in range(floori((bp.y - r) / BK), floori((bp.y + r) / BK) + 1):
		for bx in range(floori((bp.x - r) / BK), floori((bp.x + r) / BK) + 1):
			var arr = g.get(bx + by * 4096)
			if arr == null:
				continue
			for e in arr:
				var o := int(e.owner)
				var ev = en.get(o)
				if ev == null:
					ev = w.is_enemy(fid, o)
					en[o] = ev
				if not ev:
					continue
				var id := int(e.id)
				if not w.entities.has(id):
					continue
				var rn := _rank71(w, c, e, o, rk)
				if rn < 0:
					continue   # T7.allowed is false for this (owner, def) whatever the entity: can_engage would fail
				var q: Vector2
				if id >= 0 and id < hcap and hlive[id] == 1:
					q = hpos[id]
				else:
					q = e.pos
				if q.distance_squared_to(bp) > r2:
					continue
				var dk := bp.distance_to(q) * 10.0
				if dk + float(id) * 1e-6 >= bk:
					continue
				var k := float(rn) * 100000.0 + dk + float(id) * 1e-6
				if k < bk and T7.can_engage(w, b, c, wd, e):
					bk = k
					best = e
	if bool(c.get("buildings", false)):
		for t in T7._blds_near(w, fid, bp, r):
			if w.entities.has(int(t.id)) and w.is_enemy(fid, int(t.owner)) and T7.center(t).distance_to(bp) <= r + float(t.size):
				var k2 := float(T7.rank(w, c, t)) * 100000.0 + bp.distance_to(T7.pos_of(w, t)) * 10.0 + float(int(t.id)) * 1e-6
				if k2 < bk and T7.can_engage(w, b, c, wd, t):
					bk = k2
					best = t
	return best


## T7.rank, cached per (owner, def) within one query for units without per-entity tags (core7, leech_on); -1 when
## T7.allowed's tag test (t7.only) fails for that (owner, def): such a unit can never pass can_engage. Other entities:
## T7.rank (never -1).
static func _rank71(w: SimWorld, c: Dictionary, e: Dictionary, o: int, rk: Dictionary) -> int:
	if e.kind != "unit" or e.has("core7") or e.has("leech_on"):
		return T7.rank(w, c, e)
	var d := String(e.def)
	var m = rk.get(o)
	if m == null:
		m = {}
		rk[o] = m
	var v = m.get(d)
	if v == null:
		var only: Array = c.get("only", [])
		if not only.is_empty() and T7.tags_of(w, e) & T7.bits_of(only) == 0:
			v = -1
		else:
			v = T7.rank(w, c, e)
		m[d] = v
	return int(v)


## BASTION71-8 (cost): maintenance drones and engineers of one SimIndex.units_by_owner list, in list order, each unit's
## def tested once: the owner lists only grow until the index is rebuilt (a new array -> scanned again). Runtime cache
## only (w.cache.t71_help, rebuilt after a load); callers still test life and wounds every time.
## Returns [drones, engineers] (may hold dead units).
static func _help_lists(w: SimWorld, fid: int, src: Array) -> Array:
	var hc = w.cache.get("t71_help")
	if hc == null:
		hc = {}
		w.cache["t71_help"] = hc
	var h = hc.get(fid)
	if h == null or not is_same(h.src, src) or int(h.n) > src.size():
		h = {"src": src, "n": 0, "dr": [], "en": []}
		hc[fid] = h
	if int(h.n) < src.size():
		for i in range(int(h.n), src.size()):
			var u: Dictionary = src[i]
			var ud := Content.unit(String(u.def))
			if ud.has("maint71"):
				(h.dr as Array).append(u)
			elif bool(ud.get("can_build", false)):
				(h.en as Array).append(u)
		h.n = src.size()
	return [h.dr, h.en]


# ================================================================ system API
static func tick(w: SimWorld) -> void:
	var ids := turret_ids(w)
	var s = w.sys_state.get("turrets71")
	if ids.is_empty() and s == null:
		return
	if s == null:
		if w.tick % SCAN != 0 and not LastProtocol.active(w):
			return
		s = _st(w)
	_upkeep(w, s)
	if w.tick % 5 == 0:
		_helpers(w, s)
		_maint_repair(w, s)
	var scan := w.tick % SCAN == 0
	for bid in ids:
		var b = w.entities.get(bid)
		if b == null or not bool(b.get("built", false)):
			continue
		var c := cfg_of(String(b.def))
		var kind := String(c.get("kind", ""))
		var live: bool = Airdef.source_active(w, b) and not blocked(w, b)
		if kind == "rotary":
			_rotary(w, s, b, c, live, scan)
		elif live:
			match kind:
				"laser":
					_laser(w, s, b, c, scan)
				"hpm":
					if scan:
						_hpm(w, s, b, c)
				"flak":
					if (w.tick + int(bid)) % 5 == 0:
						_flak(w, s, b, c)


static func _shot(w: SimWorld, b: Dictionary, t, to: Vector2, hit: bool, kind: String) -> void:
	w.emit("ShotFired", {"shooter": int(b.id), "target": -1 if t == null else int(t.id), "weapon": String(cfg_of(String(b.def)).get("weapon", "")),
		"hit": hit, "from": T7.center(b), "to": to, "indirect": false, "t71": kind})


## Traverse7 lay toward world point `to` (the mount turns at t71.traverse_deg; true = laid, may fire this tick).
static func _lay(w: SimWorld, b: Dictionary, to: Vector2, cd_s: float, tid: int) -> bool:
	return Traverse7.lay(w, b, to - T7.center(b) + Vector2(b.pos), cd_s, false, tid)


static func _s(wd: Dictionary, wid: String, dmg: float) -> Dictionary:
	return {"weapon": wid, "cls": String(wd.get("class", "")), "damage": dmg}


## Common aim: held target kept between scans while it stays engageable; retarget on scan ticks (or every other tick
## for `fast`, the laser). Returns the target entity or null.
static func _aim(w: SimWorld, s: Dictionary, b: Dictionary, c: Dictionary, wd: Dictionary, scan: bool, fast: bool) -> Variant:
	var bid := int(b.id)
	var aim := int((s.aim as Dictionary).get(bid, -1))
	var t = null
	if aim >= 0:
		t = w.entities.get(aim)
		if t != null and not T7.can_engage(w, b, c, wd, t):
			t = null
	if t == null and (scan or (fast and (w.tick + bid) % 2 == 0)):
		t = _pick71(w, b, c, wd)
	if t == null:
		if aim >= 0:
			(s.aim as Dictionary).erase(bid)
		return null
	if aim != int(t.id):
		s.aim[bid] = int(t.id)
	return t


# ---------------------------------------------------------------- rotary railgun
static func _rotary(w: SimWorld, s: Dictionary, b: Dictionary, c: Dictionary, live: bool, scan: bool) -> void:
	var bid := int(b.id)
	var wd := weapon_of(String(b.def))
	var heat := int((s.heat as Dictionary).get(bid, 0))
	var spin := int((s.spin as Dictionary).get(bid, 0))
	var cool := (s.cool as Dictionary).has(bid)
	var t = null
	if live:
		t = _aim(w, s, b, c, wd, scan, false)
	var firing := false
	if t != null and not cool:
		spin = mini(1000, spin + roundi(1000.0 / float(_ticks(float(c.get("spin_up_s", 1.5))))))
		if spin >= 400:
			var every := int(c.get("fire_every", 2)) * (1 if spin >= 1000 else 2)
			if (w.tick + bid) % maxi(every, 1) == 0:
				firing = true
	else:
		spin = maxi(0, spin - roundi(1000.0 / float(_ticks(float(c.get("spin_down_s", 3.0))))))
	if firing and not _lay(w, b, T7.pos_of(w, t), float(c.get("fire_every", 2)) / SimWorld.TICK_RATE, int(t.id)):
		firing = false   # still traversing onto the target (the barrels keep spinning)
	if firing:
		heat += int(c.get("heat_per_shot", 9)) * int(c.get("fire_every", 2)) / 2 + 0
		_rotary_shot(w, b, c, wd, t)
		if heat >= int(c.get("heat_max", 1000)):
			s.cool[bid] = w.tick
			cool = true
			w.emit("T71Cool", {"bid": bid, "on": true})
	else:
		heat = maxi(0, heat - int(c.get("cool_per_tick", 6)))
		if cool and heat <= int(c.get("heat_resume", 300)):
			(s.cool as Dictionary).erase(bid)
			w.emit("T71Cool", {"bid": bid, "on": false})
	if heat > 0:
		s.heat[bid] = heat
	else:
		(s.heat as Dictionary).erase(bid)
	if spin > 0:
		s.spin[bid] = spin
	else:
		(s.spin as Dictionary).erase(bid)


static func _rotary_shot(w: SimWorld, b: Dictionary, c: Dictionary, wd: Dictionary, t: Dictionary) -> void:
	var bp := T7.center(b)
	var tp := T7.pos_of(w, t)
	var dir := (tp - bp).normalized()
	var rr := float(wd.get("range", 20))
	var hit := w.rng.chance(float(wd.get("accuracy", 0.9)))
	var dmg := float(wd.get("damage", 30))
	var wid := String(c.get("weapon", ""))
	_shot(w, b, t, bp + dir * rr, hit, "rotary")
	T7._damage().apply_hit(w, b, t, _s(wd, wid, dmg), hit)
	if not hit:
		return
	var n := 0
	var f := float(c.get("falloff", 0.88))
	var cap := int(c.get("pierce", 8))
	for row in lane_units(w, int(b.owner), bp, dir, rr, float(c.get("lane", 0.6))):
		if n >= cap:
			break
		if int(row[1]) == int(t.id):
			continue
		var e = w.entities.get(int(row[1]))
		if e == null:
			continue
		n += 1
		T7._damage().apply_hit(w, b, e, _s(wd, wid, dmg * pow(f, n)), true)
	w.emit("T71Rail", {"bid": int(b.id), "owner": int(b.owner), "from": bp, "to": bp + dir * rr, "target": int(t.id), "n": n})


# ---------------------------------------------------------------- laser CIWS
static func _smoked(w: SimWorld, a: Vector2, z: Vector2) -> bool:
	if not w.sys_state.has("senses7"):
		return false
	var S = load("res://sim/systems/senses7.gd")
	var clouds: Array = S._clouds(w, S.state(w))
	return not clouds.is_empty() and bool(S._smoke_blocks(clouds, a, z))


static func _laser(w: SimWorld, s: Dictionary, b: Dictionary, c: Dictionary, scan: bool) -> void:
	var bid := int(b.id)
	var wd := weapon_of(String(b.def))
	var heat := int((s.heat as Dictionary).get(bid, 0))
	var cool := (s.cool as Dictionary).has(bid)
	var t = null
	if not cool:
		t = _aim(w, s, b, c, wd, scan, true)
	var bp := T7.center(b)
	if t != null:
		var tp := T7.pos_of(w, t)
		var rng := float(wd.get("range", 14))
		if _smoked(w, bp, tp):
			rng *= float(c.get("smoke_range_mult", 0.35))
		var wt = w.cfg.get("weather")   # BASTION71-7: the weather key Accuracy8 reads; t71 weather_range_mult (PROVISIONAL)
		if wt != null:
			rng *= float((c.get("weather_range_mult", {}) as Dictionary).get(String(wt), 1.0))
		if bp.distance_to(tp) > rng:
			t = null
	var dwell := int((s.dwell as Dictionary).get(bid, 0))
	if t == null or int(t.id) != int((s.dwell_t as Dictionary).get(bid, -1)):
		dwell = 0
	if t != null and not _lay(w, b, T7.pos_of(w, t), 0.05, int(t.id)):
		t = null   # the beam director is still slewing onto the target: no dwell yet
	if t != null:
		s.dwell_t[bid] = int(t.id)
		dwell += 1
		heat += int(c.get("heat_per_tick", 14))
		var need := _ticks(float(c.get("dwell_s", 0.7))) + roundi(float(t.hp) * float(c.get("dwell_per_hp", 0.0015)) * SimWorld.TICK_RATE)
		if dwell % 4 == 1:
			w.emit("T71Beam", {"bid": bid, "owner": int(b.owner), "target": int(t.id), "from": bp, "to": T7.pos_of(w, t), "dwell": dwell, "need": need})
		if dwell >= need:
			T7._damage().apply_hit(w, b, t, _s(wd, String(c.get("weapon", "")), 1.0e6), true)
			w.emit("T71BeamKill", {"bid": bid, "target": int(t.id)})
			dwell = 0
			(s.aim as Dictionary).erase(bid)
		if heat >= int(c.get("heat_max", 1000)):
			s.cool[bid] = w.tick
			cool = true
			dwell = 0
			w.emit("T71Cool", {"bid": bid, "on": true})
	else:
		heat = maxi(0, heat - int(c.get("cool_per_tick", 5)))
		if cool and heat <= int(c.get("heat_resume", 250)):
			(s.cool as Dictionary).erase(bid)
			w.emit("T71Cool", {"bid": bid, "on": false})
	if dwell > 0:
		s.dwell[bid] = dwell
	else:
		(s.dwell as Dictionary).erase(bid)
	if heat > 0:
		s.heat[bid] = heat
	else:
		(s.heat as Dictionary).erase(bid)


# ---------------------------------------------------------------- HPM
static func _hpm(w: SimWorld, s: Dictionary, b: Dictionary, c: Dictionary) -> void:
	var bid := int(b.id)
	if int((s.ready as Dictionary).get(bid, 0)) > w.tick:
		return
	var wd := weapon_of(String(b.def))
	var t = _pick71(w, b, c, wd)
	if t == null:
		return
	var bp := T7.center(b)
	var dir := (T7.pos_of(w, t) - bp).normalized()
	var half := deg_to_rad(float(c.get("cone_deg", 70.0)) * 0.5)
	var rr := float(wd.get("range", 9))
	var hits := []
	for e in T7._near(w, int(b.owner), bp, rr):
		if not w.entities.has(int(e.id)) or not T7.allowed(w, c, e) or not T7._visible(w, int(b.owner), e):
			continue
		var v := HotState.get_pos(w, int(e.id)) - bp
		if v.length_squared() > 0.0001 and absf(dir.angle_to(v)) > half:
			continue
		hits.append(e)
	if hits.size() < int(c.get("min_targets", 3)):
		return
	if not _lay(w, b, T7.pos_of(w, t), float(wd.get("cooldown", 22.0)), int(t.id)):
		return   # the emitter is still turning onto the cone
	s.ready[bid] = w.tick + _ticks(float(wd.get("cooldown", 22.0)))
	var mf: Array = SimWorld.Creep.machine_fids(w)
	var n := 0
	var drones := 0
	for e in hits:
		if not w.entities.has(int(e.id)):
			continue
		if T7._airborne(e) and bool(c.get("drop_drones", true)) and T7.tags_of(w, e) & T7.bit("drone") != 0:
			T7._damage().apply_hit(w, b, e, _s({"class": "energy"}, String(c.get("weapon", "")), 1.0e6), true)
			drones += 1
		elif mf.has(int(e.owner)):
			_mew()._hold(w, e, "emp", float(c.get("stun_s", 6.0)), bid)
			T7._damage().apply_hit(w, b, e, _s(wd, String(c.get("weapon", "")), float(wd.get("damage", 60))), true)
			n += 1
	_shot(w, b, t, bp + dir * rr, true, "hpm")
	w.emit("T71Hpm", {"bid": bid, "owner": int(b.owner), "pos": bp, "dir": dir, "range": rr, "half": half, "n": n, "drones": drones})


# ---------------------------------------------------------------- flak
static func _flak(w: SimWorld, s: Dictionary, b: Dictionary, c: Dictionary) -> void:
	var bid := int(b.id)
	if int((s.ready as Dictionary).get(bid, 0)) > w.tick:
		return
	var wd := weapon_of(String(b.def))
	var bp := T7.center(b)
	var air := []
	for e in T7._near(w, int(b.owner), bp, float(wd.get("range", 16))):
		if w.entities.has(int(e.id)) and T7._airborne(e) and T7.allowed(w, c, e) and T7._visible(w, int(b.owner), e):
			air.append(e)
	if air.is_empty():
		return
	air.sort_custom(func(a, z): return int(a.id) < int(z.id))
	if air.size() > 32:
		air.resize(32)
	var fuse := float(c.get("fuse_r", 2.6))
	var need := int(c.get("min_cluster", 3))
	var best := -1
	var bn := 0
	for i in air.size():
		var pi := HotState.get_pos(w, int(air[i].id))
		var n := 0
		for j in air.size():
			if HotState.get_pos(w, int(air[j].id)).distance_to(pi) <= fuse:
				n += 1
		if n > bn:
			bn = n
			best = i
	if best < 0 or bn < need:
		return
	var pc := HotState.get_pos(w, int(air[best].id))
	var members := []
	var sum := Vector2.ZERO
	for e in air:
		var p := HotState.get_pos(w, int(e.id))
		if p.distance_to(pc) <= fuse:
			members.append(e)
			sum += p
	var at := Vector2(snappedf(sum.x / members.size(), 0.01), snappedf(sum.y / members.size(), 0.01))
	var br := float(c.get("burst_r", 3.2))
	if not _lay(w, b, at, float(wd.get("cooldown", 1.6)), int(air[best].id)):
		return   # the flak gun is still traversing onto the cloud
	s.ready[bid] = w.tick + _ticks(float(wd.get("cooldown", 1.6)))
	var n2 := 0
	for e in air:
		if not w.entities.has(int(e.id)):
			continue
		var d := HotState.get_pos(w, int(e.id)).distance_to(at)
		if d <= br:
			T7._damage().apply_hit(w, b, e, _s(wd, String(c.get("weapon", "")), float(wd.get("damage", 70)) * (1.0 - 0.5 * d / maxf(br, 0.01))), true)
			n2 += 1
	_shot(w, b, air[best], at, true, "flak")
	w.emit("T71Flak", {"bid": bid, "owner": int(b.owner), "pos": at, "r": br, "n": n2})


# ================================================================ commands
## turret_revive {unit_ids, target_id}: engineers go to a disabled turret and revive it (a repair order next to it).
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if String(cmd.get("type", "")) != "turret_revive":
		return "Unknown turret command."
	if (cmd.get("unit_ids", []) as Array).is_empty():
		return "Select engineers to revive the turret."
	var t = w.entities.get(int(cmd.get("target_id", -1)))
	if t == null or t.kind != "building" or int(t.owner) != int(cmd.get("issuer", -2)):
		return "Not your turret."
	if not disabled(w, t):
		return "That turret is not disabled."
	return SimWorld.Repair.validate_command(w, {"type": "repair", "issuer": cmd.issuer, "unit_ids": cmd.get("unit_ids", []), "target_id": cmd.target_id})


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	SimWorld.Repair.apply_command(w, {"type": "repair", "issuer": cmd.issuer, "unit_ids": cmd.get("unit_ids", []), "target_id": cmd.target_id})
	var t = w.entities.get(int(cmd.target_id))
	if t == null:
		return
	for id in cmd.get("unit_ids", []):
		var u = w.entities.get(int(id))
		if u != null and String(u.get("order", {}).get("type", "")) == "repair":
			revive(w, t, int(id))
			return


# ================================================================ render snapshot provider (RenderSnap.register_g71)
## {"t": [[id, heat, spin, flags, x, y]], "sc": [[fid, id, x, y]]} read by presentation/view/turret71_look.gd. Read-only.
static func snap(w: SimWorld, _snap: Dictionary) -> Dictionary:
	var tr := []
	for r in rows(w):
		var e = w.entities.get(int(r[0]))
		tr.append([int(r[0]), int(r[1]), int(r[2]), int(r[3]), float(e.pos.x), float(e.pos.y)])
	var out := {"t": tr, "sc": [], "a": []}
	var st = w.sys_state.get("turrets71")
	if st != null:   # tracking lines: [[id, cx, cy, tx, ty]] for every turret holding a target (display only)
		var aids: Array = (st.aim as Dictionary).keys()
		aids.sort()
		for id in aids:
			var b = w.entities.get(int(id))
			var t = w.entities.get(int(st.aim[id]))
			if b != null and t != null:
				var c := T7.center(b)
				var tp := T7.pos_of(w, t)
				out.a.append([int(id), c.x, c.y, tp.x, tp.y])
	var s = w.sys_state.get("sensors71")
	if s != null:
		var fids: Array = (s.c as Dictionary).keys()
		fids.sort()
		for fid in fids:
			for r in s.c[fid]:
				out.sc.append([int(fid), int(r[0]), float(r[1]), float(r[2])])
	return out
