extends "res://tests/test_base.gd"
## G7.1 I6 hive nests/relays: cut relay isolates nests; creep raises prod mult.

const Hive71 = preload("res://sim/systems/hive71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_relay_cut_isolates_and_prod_mult() -> void:
	var c := LastProtocol.make_config(82, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 8:
		w.step()
	check(int(Hive71.board(w).get("nests", 0)) >= 2, "nests seeded")
	check(int(Hive71.board(w).get("relays", 0)) >= 1, "relay seeded")
	check(Hive71.prod_mult(w) >= 1.0, "prod mult at least base")
	Hive71.cut_relay(w, "r0")
	check(Hive71.is_isolated(w, "n0"), "n0 isolated after cut")
	check(Hive71.is_isolated(w, "n1"), "n1 isolated after cut")


func test_heartbeat_pulses() -> void:
	var c := LastProtocol.make_config(85, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	var beats0 := 0
	for i in 120:
		w.step()
		beats0 = maxi(beats0, int(Hive71.board(w).get("beat", 0)))
	check(beats0 >= 1, "heartbeat fired at least once")
