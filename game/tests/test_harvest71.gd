extends "res://tests/test_base.gd"
## G7.1 J4 harvesters: spawn, drag gore body home, raise hive prod bonus.

const Harvest71 = preload("res://sim/systems/harvest71.gd")
const Hive71 = preload("res://sim/systems/hive71.gd")
const Gore71 = preload("res://sim/systems/gore71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_harvesters_take_body_and_boost_prod() -> void:
	var c := LastProtocol.make_config(86, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 8:
		w.step()
	var home := Vector2(w.sys_state.lp.base.center) + Vector2(60, 0)
	var body_pos := home + Vector2(-5, 0)
	var bid := Gore71.add_body(w, {
		"kind": "body", "def": "rifleman", "owner": 0, "pos": body_pos,
		"rot": 0.0, "out": "bleed", "t": w.tick, "sz": 0.4, "lost": 0, "ch": false, "tr": 0, "rc": "",
	})
	check(bid >= 0, "body added")
	# Force a harvester wave.
	Harvest71._spawn_wave(w, Harvest71._st(w))
	check(int(Harvest71.board(w).get("n", 0)) >= 1, "harvesters spawned")
	var taken0 := int(Harvest71.board(w).get("taken", 0))
	var prod0 := Hive71.prod_mult(w)
	for i in 200:
		w.step()
		if int(Harvest71.board(w).get("taken", 0)) > taken0:
			break
	check(int(Harvest71.board(w).get("taken", 0)) > taken0, "body harvested")
	check(Harvest71.prod_bonus(w) > 0.0, "prod bonus from mass")
	check(Hive71.prod_mult(w) >= prod0, "hive prod mult not lower")
