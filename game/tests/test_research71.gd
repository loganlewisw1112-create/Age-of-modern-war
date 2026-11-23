extends "res://tests/test_base.gd"
## G7.1 H7 siege tech tree stubs.

const Research71 = preload("res://sim/systems/research71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_research_tree_unlocks() -> void:
	check(Research71.TREE.has("ammo_ap"), "ammo_ap in tree")
	check(Research71.TREE.has("robot_harden"), "robot_harden in tree")
	var c := LastProtocol.make_config(77, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match for research"):
		return
	for i in 20:
		w.step()
	var board: Dictionary = Research71.board(w)
	check((board.get("avail", []) as Array).has("ammo_ap"), "ammo_ap available at start")
	check(not (board.get("avail", []) as Array).has("ammo_he"), "ammo_he gated on ammo_ap")
	var why := w.preview_command({"type": "research71_start", "issuer": 0, "tech": "ammo_ap"})
	check_eq(why, "", "research71_start accepted (%s)" % why)
	var sub := w.submit({"type": "research71_start", "issuer": 0, "tech": "ammo_ap"})
	check(bool(sub.get("ok", false)), "research71_start submitted")
	w.step()  # apply runs next tick
	check_eq(str(Research71._st(w).cur), "ammo_ap", "research running")
	# Fast-forward past cost_s.
	var need := int(ceil(float(Research71.TREE.ammo_ap.cost_s) * float(SimWorld.TICK_RATE))) + 5
	for i in need:
		w.step()
	check(Research71.unlocked(w, "ammo_ap"), "ammo_ap unlocks after cost")
	check_eq(str(Research71._st(w).cur), "", "queue clear after done")
	check((Research71.board(w).get("avail", []) as Array).has("ammo_he"), "ammo_he opens after ammo_ap")
	var hud: Dictionary = LastProtocol.hud(w)
	check(hud.has("research"), "HUD exposes research board")
	# Save / resume keeps unlocks (Done-when 7 style).
	var loaded := SimWorld.from_dict(w.to_dict().duplicate(true))
	check(Research71.unlocked(loaded, "ammo_ap"), "save keeps ammo_ap unlock")
	check((Research71.board(loaded).get("avail", []) as Array).has("ammo_he"), "save keeps ammo_he available")
