extends "res://tests/test_base.gd"
## G7.1 H11: hive evolve stages rise with dread and tag machines.

const Evolve71 = preload("res://sim/systems/evolve71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_stage_rises_with_dread() -> void:
	var c := LastProtocol.make_config(90, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 4:
		w.step()
	check_eq(Evolve71.stage(w), 0, "start at stage 0")
	# Drive dread and tick Evolve71 directly (director may rewrite dread mid-step).
	w.sys_state.lp.dread = 0.6
	Evolve71.tick(w)
	check(Evolve71.stage(w) >= 2, "stage >= 2 at dread 0.6")
	check(Evolve71.harden_mult(w) > 1.0, "harden mult rises")
	w.sys_state.lp.dread = 0.95
	Evolve71.tick(w)
	check(Evolve71.stage(w) >= 4, "stage 4 at high dread")
	# Harden divides incoming damage in Damage.apply_hit when g71_evolve > 0.
	check(is_equal_approx(Evolve71.harden_mult(w), 1.0 + 4.0 * 0.08) or Evolve71.harden_mult(w) > 1.2, "harden at stage 4")
