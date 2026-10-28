extends RefCounted
## G7 (CREEP7): minimum Machine EW (master scope section 8): hack (jam / brief take-over) and EMP stun.
## Called from MachineG6.tick (after Movement and Combat), so a held unit is put back where it was held and its weapon
## cooldown is kept up for the rest of the hold: it neither moves nor fires.
##   stun(w, center, radius, secs, by=-1) -> int    EMP: every Machine unit in radius is held for secs.
##   can_hack(e, w=null) -> bool                    a human vehicle or drone, not flagged unhackable (CNSIM7 sets
##                                                  e.unhackable or def.unhackable), not a Machine unit.
##   jam(w, e, secs, by) / takeover(w, e, secs, by) jam = held in place, weapons down; take-over (drones) = weapons
##                                                  down and the drone is pulled toward the hacker.
## Hackers: units/buildings whose def id is in rules.g7_machine.ew.hackers {def: range tiles}; each one hacks the
## nearest hackable enemy in range every every_ticks (then cooldown_s). Automatic hacking runs only in creep matches
## (Creep enabled) or with rules ew.always / cfg.machine_ew7, so G6.1 matches keep their hashes.
## State: w.sys_state.machine_ew7 = {held: {id: {k: "emp"|"jam"|"take", until, pos, by}}, cd: {hacker id: tick}},
##   created on first use. e.ew7 = k while held (display). Events: MachineHack {hacker, target, kind, secs},
##   EmpStun {pos, radius, n, by}.

const HotState = preload("res://sim/hot_state.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Creep = preload("res://sim/systems/creep.gd")


static func RE() -> Dictionary:
	return Content.rules().get("g7_machine", {}).get("ew", {})


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get("machine_ew7")
	if s == null:
		s = {"held": {}, "cd": {}}
		w.sys_state["machine_ew7"] = s
	return s


static func _def(e: Dictionary) -> Dictionary:
	return Content.building(String(e.def)) if e.kind == "building" else Content.unit(String(e.def))


static func is_drone(e: Dictionary) -> bool:
	var d := Content.unit(String(e.def))
	var mc := String(d.get("move_class", ""))
	var id := String(e.def)
	var dv = d.get("drone", null)
	if dv != null and not (typeof(dv) == TYPE_BOOL and not dv):
		return true
	return (Terrain.is_air(mc) and (id.contains("drone") or id.contains("fpv")
		or String(d.get("role", "")) == "drone"))


static func can_hack(e: Dictionary, w: SimWorld = null) -> bool:
	if e.get("kind", "") != "unit" or bool(e.get("unhackable", false)):
		return false
	var d := Content.unit(String(e.def))
	if d.is_empty() or bool(d.get("unhackable", false)):
		return false
	if w != null and Creep.is_machine(w, int(e.owner)):
		return false
	return String(d.get("move_class", "foot")) != "foot" or is_drone(e)


static func held(w: SimWorld, id: int) -> String:
	var s = w.sys_state.get("machine_ew7")
	if s == null:
		return ""
	var h = s.held.get(id)
	return "" if h == null else String(h.k)


static func _hold(w: SimWorld, e: Dictionary, k: String, secs: float, by: int) -> void:
	var s := _st(w)
	var id := int(e.id)
	var until := w.tick + maxi(roundi(secs * SimWorld.TICK_RATE), 1)
	var old = s.held.get(id)
	if old != null and int(old.until) >= until:
		return
	s.held[id] = {"k": k, "until": until, "pos": HotState.get_pos(w, id), "by": by}
	e.ew7 = k


## EMP: holds every Machine unit within radius for secs. Returns how many.
static func stun(w: SimWorld, center: Vector2, radius: float, secs: float, by: int = -1) -> int:
	var n := 0
	var r2 := radius * radius
	var byown: Dictionary = SimIndex.units_by_owner(w)
	for fid in Creep.machine_fids(w):
		for e in byown.get(fid, []):
			if w.entities.has(int(e.id)) and HotState.get_pos(w, int(e.id)).distance_squared_to(center) <= r2:
				_hold(w, e, "emp", secs, by)
				if e.has("leech_on"):   # EMP shakes latched leeches off (THREAT7 field)
					w.emit("LeechDetached", {"id": e.id, "vehicle": int(e.leech_on)})
					e.erase("leech_on")
				n += 1
	w.emit("EmpStun", {"pos": center, "radius": radius, "n": n, "by": by})
	return n


static func jam(w: SimWorld, e: Dictionary, secs: float, by: int = -1) -> bool:
	if not can_hack(e, w):
		return false
	_hold(w, e, "jam", secs, by)
	return true


static func takeover(w: SimWorld, e: Dictionary, secs: float, by: int = -1) -> bool:
	if not can_hack(e, w):
		return false
	_hold(w, e, "take", secs, by)
	return true


static func _auto(w: SimWorld) -> bool:
	return Creep.enabled(w) or bool(RE().get("always", false)) or bool(w.cfg.get("machine_ew7", false))


static func tick(w: SimWorld) -> void:
	var s = w.sys_state.get("machine_ew7")
	if _auto(w):
		var every := maxi(int(RE().get("every_ticks", 80)), 1)
		if w.tick % every == 0:
			_hack_step(w)
			s = w.sys_state.get("machine_ew7")
	if s == null or (s.held as Dictionary).is_empty():
		return
	_enforce(w, s)


static func _enforce(w: SimWorld, s: Dictionary) -> void:
	var ids: Array = s.held.keys()
	ids.sort()
	var spd := float(RE().get("takeover_speed", 2.5)) / SimWorld.TICK_RATE
	for id in ids:
		var h: Dictionary = s.held[id]
		var e = w.entities.get(id)
		if e == null or w.tick >= int(h.until):
			s.held.erase(id)
			if e != null:
				e.erase("ew7")
			continue
		var p: Vector2 = h.pos
		if String(h.k) == "take":
			var hk = w.entities.get(int(h.by))
			if hk != null:
				var to: Vector2 = hk.pos
				p = p.move_toward(to, spd)
				p = Vector2(snappedf(p.x, 1.0 / 1024.0), snappedf(p.y, 1.0 / 1024.0))
				h.pos = p
		HotState.set_pos(w, int(id), p)
		HotState.set_moving(w, int(id), false)
		HotState.set_cd(w, int(id), maxi(HotState.get_cd(w, int(id)), int(h.until) - w.tick))


static func _hack_step(w: SimWorld) -> void:
	var hk: Dictionary = RE().get("hackers", {})
	if hk.is_empty():
		return
	var mfs := Creep.machine_fids(w)
	if mfs.is_empty():
		return
	var cands := []
	for kind in ["building", "unit"]:
		for e in SimIndex.of(w, kind):
			if hk.has(String(e.def)) and mfs.has(int(e.owner)) and w.entities.has(int(e.id)) and bool(e.get("built", true)):
				cands.append(e)
	if cands.is_empty():
		return
	var s := _st(w)
	var units: Array = SimIndex.of(w, "unit")
	for h in cands:
		var hid := int(h.id)
		if int(s.cd.get(hid, -1)) > w.tick or held(w, hid) != "":
			continue
		var rng: float = float(hk[String(h.def)])
		var best = null
		var bd := rng * rng
		for u in units:
			if mfs.has(int(u.owner)) or not w.is_enemy(int(h.owner), int(u.owner)) or held(w, int(u.id)) != "" or not w.entities.has(int(u.id)):   # DET7: stale index entry
				continue
			var d2 := (u.pos as Vector2).distance_squared_to(h.pos)
			if d2 <= bd and can_hack(u, w):
				if best == null or d2 < bd or (d2 == bd and int(u.id) < int(best.id)):
					best = u
					bd = d2
		if best == null:
			continue
		var take := is_drone(best)
		var secs := float(RE().get("takeover_s" if take else "jam_s", 4.0))
		_hold(w, best, "take" if take else "jam", secs, hid)
		s.cd[hid] = w.tick + roundi(float(RE().get("cooldown_s", 10.0)) * SimWorld.TICK_RATE)
		w.emit("MachineHack", {"hacker": hid, "target": int(best.id), "kind": "take" if take else "jam", "secs": secs})
