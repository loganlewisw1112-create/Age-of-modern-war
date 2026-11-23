extends "res://tests/test_base.gd"
## Done-when 7: mid-run LP save/resume keeps the same state hash and future with Wave 3–5 boards live.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Hive71 = preload("res://sim/systems/hive71.gd")
const Fire71 = preload("res://sim/systems/fire71.gd")
const Death71 = preload("res://sim/systems/death71.gd")
const Capture71 = preload("res://sim/systems/capture71.gd")
const Evolve71 = preload("res://sim/systems/evolve71.gd")
const Harvest71 = preload("res://sim/systems/harvest71.gd")


func test_mid_siege_save_resume_same_future() -> void:
	var c := LastProtocol.make_config(107, "industrial_heartland_m")
	var a := SimWorld.new_match(c)
	if not check(a != null, "LP match"):
		return
	for i in 80:
		a.step()
	# Force a few board writes so sys_state keys are populated before the snapshot.
	if Hive71.active(a):
		Hive71.add_nest(a, "save_nest", Vector2(10, 10))
	if Fire71.active(a):
		Fire71.ignite_cell(a, Vector2(12, 12), 0, 0.9)
	var h0 := a.state_hash()
	var loaded := SimWorld.from_dict(a.to_dict().duplicate(true))
	check_eq(loaded.state_hash(), h0, "reload matches mid-run hash")
	check_eq(Hive71.board(loaded).get("nests", -1), Hive71.board(a).get("nests", -2), "hive nests survive save")
	check_eq(Fire71.board(loaded).get("n", -1), Fire71.board(a).get("n", -2), "fire cells survive save")
	check_eq(Death71.board(loaded).get("blasts", -1), Death71.board(a).get("blasts", -2), "death board survives save")
	check_eq(Capture71.board(loaded), Capture71.board(a), "capture board survives save")
	check_eq(Evolve71.board(loaded), Evolve71.board(a), "evolve board survives save")
	check_eq(Harvest71.board(loaded), Harvest71.board(a), "harvest board survives save")
	for i in 60:
		a.step()
		loaded.step()
	check_eq(a.state_hash(), loaded.state_hash(), "save / load mid-siege keeps the same future")


func test_two_run_determinism_with_boards() -> void:
	var ha := _run_hash(108)
	var hb := _run_hash(108)
	check_eq(ha, hb, "two LP runs share a hash with Wave 3–5 boards")


func _run_hash(seed: int) -> String:
	var c := LastProtocol.make_config(seed, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if w == null:
		return ""
	for i in 120:
		w.step()
	return w.state_hash()
