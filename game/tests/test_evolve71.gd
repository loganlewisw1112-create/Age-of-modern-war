extends "res://tests/test_base.gd"
## G7.1 H11: hive evolve stages rise with dread and tag machines.

const Evolve71 = preload("res://sim/systems/evolve71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_stage_rises_with_dread() -> void:
	var c := LastProtocol.make_config(90, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 6:
		w.step()
	check_eq(Evolve71.stage(w), 0, "start at stage 0")
	w.sys_state.lp.dread = 0.6
	for i in 40:
		w.step()
	check(Evolve71.stage(w) >= 2, "stage >= 2 at dread 0.6")
	check(Evolve71.harden_mult(w) > 1.0, "harden mult rises")
