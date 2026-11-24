extends RefCounted
## G10 civilian disguise, sleeper activation and shock-raid intent. Numbers PROVISIONAL.

const KEY := "civilian_cells10"
const VER := 1
const Territory9 = preload("res://sim/systems/territory9.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g10_civilians", {})
	return c if c is Dictionary else {}


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"ver": VER, "disguised": {}, "activated": {}}
	return w.sys_state[KEY]


static func is_disguised(w: SimWorld, unit_id: int) -> bool:
	if not w.sys_state.has(KEY):
		return false
	return (_st(w).disguised as Dictionary).has(str(unit_id))


static func can_capture(w: SimWorld, unit_id: int) -> bool:
	## Sleepers cannot capture while disguised.
	if is_disguised(w, unit_id) and bool(R().get("sleeper_cannot_capture_while_disguised", true)):
		return false
	return true


static func disguise(w: SimWorld, unit_id: int) -> bool:
	var e = w.entities.get(unit_id)
	if e == null or String(e.get("kind", "")) != "unit":
		return false
	var fid := int(e.get("owner", -1))
	if not Coalition10.active(w, fid):
		return false
	var def := String(e.get("def", ""))
	# Sleeper / cell / infiltrator forms may take civilian cover.
	if not (def.begins_with("x_") and (def.contains("sleeper") or def.contains("cell") or def.contains("ghost_infiltrator") or def.contains("ambush"))):
		# Allow any Coalition infantry tagged g10 for tests / pmc sleepers.
		var ud: Dictionary = Content.unit(def)
		if not bool(ud.get("g10", false)):
			return false
	var s := _st(w)
	s.disguised[str(unit_id)] = {
		"fid": fid,
		"since": w.tick,
		"def": def,
	}
	e["civilian_disguise"] = true
	e["disguised"] = true
	w.emit("CivilianCells10Disguise", {"id": unit_id, "fid": fid})
	return true


static func break_disguise(w: SimWorld, unit_id: int, reason: String) -> void:
	if not is_disguised(w, unit_id):
		return
	var s := _st(w)
	var rec: Dictionary = s.disguised.get(str(unit_id), {})
	(s.disguised as Dictionary).erase(str(unit_id))
	var e = w.entities.get(unit_id)
	if e != null:
		e.erase("civilian_disguise")
		e.erase("disguised")
	var fid := int(rec.get("fid", -1))
	if fid < 0 and e != null:
		fid = int(e.get("owner", -1))
	# Civilian harm / support hit via Territory9 public API when break looks hostile.
	if String(reason) in ["fire", "hostile", "sprint"] and fid >= 0:
		Territory9.civilian_harm(w, fid, int(R().get("civ_harm_on_break", 1)))
	w.emit("CivilianCells10Break", {"id": unit_id, "fid": fid, "reason": String(reason)})


## Hostile action / detector contact / sprint / fire — call from tests or future combat hooks.
static func note_action(w: SimWorld, unit_id: int, action: String) -> void:
	if not is_disguised(w, unit_id):
		return
	var breaks: Array = R().get("disguise_break_on", ["sprint", "fire", "hostile", "detector"])
	if breaks.has(String(action)):
		break_disguise(w, unit_id, String(action))


static func activate(w: SimWorld, unit_ids: Array, intent: String) -> void:
	var s := _st(w)
	var want := String(intent)
	var sorted: Array = []
	for raw in unit_ids:
		sorted.append(int(raw))
	sorted.sort()
	for uid in sorted:
		var e = w.entities.get(uid)
		if e == null or String(e.get("kind", "")) != "unit":
			continue
		var fid := int(e.get("owner", -1))
		if not Coalition10.active(w, fid):
			continue
		if is_disguised(w, uid):
			break_disguise(w, uid, "hostile")
		s.activated[str(uid)] = {"intent": want, "tick": w.tick, "fid": fid}
		e["cell_intent"] = want
		if want == String(R().get("shock_raid_intent", "shock_raid")):
			# Combined shock-raid: mark intent; movement/damage systems consume later.
			e["shock_raid"] = true
			Coalition10.note_evidence(w, fid, "probes", 1)
		w.emit("CivilianCells10Activate", {"id": uid, "fid": fid, "intent": want})


static func tick(w: SimWorld) -> void:
	if not w.sys_state.has(KEY):
		return
	# Prune dead disguised units.
	var s := _st(w)
	var keys: Array = (s.disguised as Dictionary).keys()
	keys.sort()
	for k in keys:
		if not w.entities.has(int(k)):
			(s.disguised as Dictionary).erase(k)
	var ak: Array = (s.activated as Dictionary).keys()
	ak.sort()
	for k in ak:
		if not w.entities.has(int(k)):
			(s.activated as Dictionary).erase(k)
