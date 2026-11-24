extends RefCounted
## G10 IEDs / traps: roadside, building, drone-borne. Numbers PROVISIONAL.

const KEY := "ieds10"
const VER := 1
const Territory9 = preload("res://sim/systems/territory9.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")
const CivilianCells10 = preload("res://sim/systems/civilian_cells10.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g10_ieds", {})
	return c if c is Dictionary else {}


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"ver": VER, "traps": {}, "next_id": 1}
	return w.sys_state[KEY]


static func board(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		return {}
	return {"n": (_st(w).traps as Dictionary).size()}


static func plant(w: SimWorld, fid: int, kind: String, cell: Vector2i, trigger: String) -> int:
	if not Coalition10.active(w, fid) and not w.factions.has(fid):
		return -1
	var kinds: Array = R().get("kinds", ["roadside", "building", "drone"])
	var triggers: Array = R().get("triggers", ["proximity", "timer", "remote"])
	var k := String(kind)
	var t := String(trigger)
	if not kinds.has(k):
		return -1
	if not triggers.has(t):
		return -1
	var s := _st(w)
	var tid := int(s.next_id)
	s.next_id = tid + 1
	var timer_left := 0
	if t == "timer":
		timer_left = 60
	s.traps[str(tid)] = {
		"id": tid,
		"fid": fid,
		"kind": k,
		"trigger": t,
		"cell": [cell.x, cell.y],
		"armed": true,
		"timer_left": timer_left,
		"drone_borne": k == "drone",
	}
	w.emit("Ieds10Plant", {"id": tid, "fid": fid, "kind": k, "trigger": t, "cell": [cell.x, cell.y]})
	return tid


static func disarm(w: SimWorld, fid: int, trap_id: int) -> bool:
	if not w.sys_state.has(KEY):
		return false
	var s := _st(w)
	var key := str(trap_id)
	if not (s.traps as Dictionary).has(key):
		return false
	var trap: Dictionary = s.traps[key]
	# Engineer / recon / sapper on the disarming side (or any Coalition sapper test path).
	var ok := false
	for e in w.units_of(fid):
		var def := String(e.get("def", ""))
		var roles: Array = R().get("disarm_roles", ["engineer", "recon", "sapper"])
		for role in roles:
			if def.contains(String(role)) or def == "engineer" or def.ends_with("_sapper"):
				ok = true
				break
		if ok:
			break
	if not ok:
		return false
	(s.traps as Dictionary).erase(key)
	w.emit("Ieds10Disarm", {"id": trap_id, "fid": fid})
	return true


static func trap(w: SimWorld, trap_id: int) -> Dictionary:
	if not w.sys_state.has(KEY):
		return {}
	return (_st(w).traps as Dictionary).get(str(trap_id), {}).duplicate()


static func _cell_of_entity(e: Dictionary) -> Vector2i:
	return Vector2i(int(floor(float(e.pos.x))), int(floor(float(e.pos.y))))


static func _detonate(w: SimWorld, s: Dictionary, trap: Dictionary) -> void:
	var tid := int(trap.id)
	var cell := Vector2i(int(trap.cell[0]), int(trap.cell[1]))
	var r := float(R().get("blast_radius", 2.5))
	var dmg := float(R().get("damage", 55))
	var owner_fid := int(trap.fid)
	var friendly_hit := false
	var civ_proxy := false
	var ids: Array = w.entities.keys()
	ids.sort()
	for eid in ids:
		var e = w.entities[eid]
		if e == null or String(e.get("kind", "")) != "unit":
			continue
		var p: Vector2 = e.pos
		var c := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
		if p.distance_to(c) > r:
			continue
		e.hp = maxf(0.0, float(e.get("hp", 0.0)) - dmg)
		if int(e.get("owner", -1)) == owner_fid:
			friendly_hit = true
		if bool(e.get("civilian_disguise", false)) or CivilianCells10.is_disguised(w, int(eid)):
			civ_proxy = true
			CivilianCells10.break_disguise(w, int(eid), "hostile")
		if float(e.get("hp", 0.0)) <= 0.0:
			w.destroy(int(eid), "ied")
	if friendly_hit or civ_proxy:
		Territory9.civilian_harm(w, owner_fid, int(R().get("civ_harm_on_friendly_blast", 2)))
	(s.traps as Dictionary).erase(str(tid))
	w.emit("Ieds10Detonate", {"id": tid, "cell": [cell.x, cell.y], "friendly": friendly_hit})


## Remote trigger by owner.
static func trigger_remote(w: SimWorld, fid: int, trap_id: int) -> bool:
	if not w.sys_state.has(KEY):
		return false
	var s := _st(w)
	var trap: Dictionary = s.traps.get(str(trap_id), {})
	if trap.is_empty() or int(trap.get("fid", -1)) != fid:
		return false
	if String(trap.get("trigger", "")) != "remote" and String(trap.get("kind", "")) != "drone":
		return false
	_detonate(w, s, trap)
	return true


static func tick(w: SimWorld) -> void:
	if not w.sys_state.has(KEY):
		return
	var s := _st(w)
	var keys: Array = (s.traps as Dictionary).keys()
	keys.sort()
	for k in keys:
		var trap: Dictionary = s.traps.get(k, {})
		if trap.is_empty() or not bool(trap.get("armed", true)):
			continue
		var trig := String(trap.get("trigger", ""))
		if trig == "timer":
			trap.timer_left = int(trap.get("timer_left", 0)) - 1
			if int(trap.timer_left) <= 0:
				_detonate(w, s, trap)
			continue
		if trig == "proximity" or String(trap.get("kind", "")) == "roadside" or String(trap.get("kind", "")) == "building":
			var cell := Vector2i(int(trap.cell[0]), int(trap.cell[1]))
			var owner_fid := int(trap.fid)
			var ids: Array = w.entities.keys()
			ids.sort()
			for eid in ids:
				var e = w.entities[eid]
				if e == null or String(e.get("kind", "")) != "unit":
					continue
				if int(e.get("owner", -1)) == owner_fid:
					continue
				if _cell_of_entity(e) == cell:
					_detonate(w, s, trap)
					break
