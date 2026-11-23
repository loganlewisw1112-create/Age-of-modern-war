extends "res://tests/test_base.gd"
## G7.1 J14 conduct cost: dark marks block gold and shift ending.

const Conduct71 = preload("res://sim/systems/conduct71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_dark_mark_blocks_gold() -> void:
	var c := LastProtocol.make_config(68, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 5:
		w.step()
	check(Conduct71.gold_ok(w), "gold open at start")
	check_eq(Conduct71.ending(w), "clean", "clean ending")
	Conduct71.mark(w, "gas_friendly")
	check(not Conduct71.gold_ok(w), "gold blocked after dark mark")
	check(Conduct71.score(w) < 0, "score dropped")
	check(Conduct71.ending(w) != "clean", "ending no longer clean")
