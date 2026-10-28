extends "res://tests/test_base.gd"
## ORCH regression (CNROLE7 board sim.hang.walkers): Machine walkers inside the CN compound made a facility APC re-route
## along a path that doubles straight back (a cusp); the corner fillet's tangent went to infinity, the route became
## ~1.6e15 tiles long and FacDrive7's route walks never ended (the match froze at tick ~119). A cusp is now a
## stop-and-reverse point. The match must keep stepping and every cached APC route must have a sane length.
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")


func test_walkers_inside_compound_do_not_freeze_fac_drive() -> void:
	var w := SimWorld.new_match(LastProtocol.make_config(4242, "industrial_heartland_m"))
	w.run_ticks(25)
	w.ai_state = {}
	var s: Dictionary = w.sys_state.lp
	var rc := CnFacility.compound_rect(CnFacility.fac(w, int(CnFacility.facilities(w, 0)[0])))
	for i in 4:
		w.spawn_unit("m_walker", int(s.mfid), rc.get_center() + Vector2(float(i) - 1.5, 6.0))
	var t0 := Time.get_ticks_msec()
	w.run_ticks(200)
	check(Time.get_ticks_msec() - t0 < 60000, "200 ticks with walkers in the compound finish (%d ms)" % (Time.get_ticks_msec() - t0))
	var worst := 0.0
	var C = w.cache.get("fd7_rt", {})
	for k in C:
		worst = maxf(worst, float((C[k] as Dictionary).get("len", 0.0)))
	check(worst < 500.0, "every cached APC route has a sane length (longest %.1f tiles)" % worst)
