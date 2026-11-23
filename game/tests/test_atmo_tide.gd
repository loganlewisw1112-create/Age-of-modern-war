extends "res://tests/test_base.gd"
## G7.1 I6/E1: tide song rises on hive heartbeat.

const Atmo71 = preload("res://sim/systems/atmo71.gd")
const Hive71 = preload("res://sim/systems/hive71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_tide_song_pulses_on_heartbeat() -> void:
	var c := LastProtocol.make_config(92, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 4:
		w.step()
	w.sys_state.lp.dread = 0.4
	var song0 := float(Atmo71.board(w).get("tide_song", 0.0))
	w.emit("Hive71Heartbeat", {"beat": 1, "period": 90, "dread": 0.4})
	Atmo71.tick(w)
	check(float(Atmo71.board(w).get("tide_song", 0.0)) > song0, "tide song rose on beat")
