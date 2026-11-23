extends "res://tests/test_base.gd"
## G7.1 E1 atmosphere: flares, shake, haze/ash from dread.

const Atmo71 = preload("res://sim/systems/atmo71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_flare_shake_and_haze() -> void:
	var c := LastProtocol.make_config(75, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 6:
		w.step()
	Atmo71.drop_flare(w, Vector2(12, 12), 2.0)
	Atmo71.request_shake(w, 0.5)
	check_eq(int(Atmo71.board(w).get("flares_n", 0)), 1, "flare live")
	check(float(Atmo71.board(w).get("shake", 0.0)) >= 0.5, "shake armed")
	w.sys_state.lp.dread = 0.8
	w.step()
	check(bool(Atmo71.board(w).get("haze", false)), "haze at high dread")
	check(bool(Atmo71.board(w).get("ash", false)), "ash at high dread")
	var need := int(ceil(2.0 * float(SimWorld.TICK_RATE))) + 3
	for i in need:
		w.step()
	check_eq(int(Atmo71.board(w).get("flares_n", 0)), 0, "flare expired")
