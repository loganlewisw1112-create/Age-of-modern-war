extends "res://tests/test_base.gd"
## G7.1 J7 horror atmosphere: silence before, night eyes, bodies on display, tide song.

const Horror71 = preload("res://sim/systems/horror71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_silence_and_tide_song() -> void:
	var c := LastProtocol.make_config(72, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 6:
		w.step()
	Horror71.start_silence(w, 1.0)
	check(bool(Horror71.board(w).get("silence", false)), "silence on")
	var need := int(ceil(1.0 * float(SimWorld.TICK_RATE))) + 3
	for i in need:
		w.step()
	check(not bool(Horror71.board(w).get("silence", false)), "silence ends")
	w.sys_state.lp.dread = 0.6
	w.step()
	check(float(Horror71.board(w).get("tide_song", 0.0)) >= 0.5, "tide song tracks dread")


func test_night_eyes_and_body_display() -> void:
	var c := LastProtocol.make_config(73, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 6:
		w.step()
	Horror71.set_night(w, true)
	w.sys_state.lp.dread = 0.5
	w.step()
	check(bool(Horror71.board(w).get("night_eyes", false)), "night eyes open")
	Horror71.display_body(w, Vector2(10, 10), 99)
	check_eq(int(Horror71.board(w).get("bodies_n", 0)), 1, "one body on display")
