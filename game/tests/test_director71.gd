extends "res://tests/test_base.gd"
## G7.1 C1 first slice: the dread meter is pure, rises with the fight, and does not move the phase clock.

const Director71 = preload("res://sim/systems/director71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_pressure_is_pure_and_ordered() -> void:
	check(not Director71.rules().is_empty(), "rules.g71_director loaded")
	check_eq(Director71.pressure(0.0, 0, 0.0, 0), 0.0, "a fresh run is 0")
	var mid := Director71.pressure(0.5, 0, 0.0, 0)
	var late := Director71.pressure(1.0, 0, 0.0, 0)
	check(late > mid and mid > 0.0, "time raises dread (%.3f then %.3f)" % [mid, late])
	check(Director71.pressure(0.2, 1, 0.0, 0) > Director71.pressure(0.2, 0, 0.0, 0), "a fallen ring raises dread")
	check(Director71.pressure(0.2, 0, 0.8, 0) > Director71.pressure(0.2, 0, 0.1, 0), "creep raises dread")
	check(Director71.pressure(0.2, 0, 0.0, 4) > Director71.pressure(0.2, 0, 0.0, 0), "losses raise dread")
	check(Director71.pressure(5.0, 9, 5.0, 99) <= 1.0, "dread stays at most 1")
	check_eq(Director71.band(0.1), "probe", "early band")
	check_eq(Director71.band(0.5), "mixed", "middle band")
	check_eq(Director71.band(0.9), "siege", "peak band")


func test_live_meter_does_not_move_the_phase() -> void:
	var c := LastProtocol.make_config(77, "industrial_heartland_m")
	var a := SimWorld.new_match(c)
	var b := SimWorld.new_match(c)
	if not check(a != null and b != null, "two Last Protocol matches start"):
		return
	for i in 40:
		a.step()
		b.step()
	check_eq(a.state_hash(), b.state_hash(), "two runs share a hash with the meter on")
	var s: Dictionary = a.sys_state.lp
	check(s.has("dread"), "the match stores dread")
	check(float(s.dread) >= 0.0 and float(s.dread) <= 1.0, "dread is in range (%.3f)" % float(s.dread))
	check_eq(int(s.phase), 0, "40 ticks do not advance the phase (still %d)" % int(s.phase))
	var h: Dictionary = LastProtocol.hud(a)
	check(h.has("dread") and String(h.band) == Director71.band(float(h.dread)), "the HUD shows the same band")
