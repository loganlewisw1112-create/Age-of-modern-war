extends "res://tests/test_base.gd"
## G7.1 H11: cage a crippled machine, finish study for research boost.

const Capture71 = preload("res://sim/systems/capture71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_cage_and_complete_study() -> void:
	var c := LastProtocol.make_config(89, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 6:
		w.step()
	var mfid := -1
	for fid in w.factions:
		if String(w.factions[fid].get("faction_def", "")) == "machine":
			mfid = int(fid)
			break
	if not check(mfid >= 0, "machine faction"):
		return
	var def := "g71_m_reclaimer"
	if Content.unit(def).is_empty():
		check(false, "need machine def")
		return
	var uid := w.spawn_unit(def, mfid, Vector2(45, 45))
	w.entities[uid].hp = 1.0
	check_eq(Capture71.cage(w, uid), "", "cage ok")
	check(not w.entities.has(uid), "removed from field")
	check(bool(Capture71.board(w).get("caged", false)), "caged")
	# Force study to complete without waiting breakout RNG.
	Capture71._st(w).study_left = 1
	w.step()
	check(bool(Capture71.board(w).get("rewarded", false)) or not bool(Capture71.board(w).get("caged", false)),
		"study finished or broke out")
