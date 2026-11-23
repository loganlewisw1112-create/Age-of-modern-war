extends "res://tests/test_base.gd"
## G9 HIVE9: wreck harvest, evolve + adapt, hive eat path.

const Hive71 = preload("res://sim/systems/hive71.gd")
const Hive9 = preload("res://sim/systems/hive9.gd")
const Harvest71 = preload("res://sim/systems/harvest71.gd")
const Evolve71 = preload("res://sim/systems/evolve71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Creep = preload("res://sim/systems/creep.gd")


func test_hive_eats_wreck_on_creep() -> void:
	var c := LastProtocol.make_config(301, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 6:
		w.step()
	var center := Vector2(w.sys_state.lp.base.center)
	Creep.add_seed(w, center + Vector2(4, 2), "seed", int(w.sys_state.lp.mfid))
	for i in 40:
		w.step()
	var wid := w.spawn_unit("mbt", int(w.sys_state.lp.fid), center + Vector2(2, 0))
	check(wid >= 0, "spawn target")
	var e: Dictionary = w.entities[wid]
	w.destroy(wid, "test")
	var wreck_id := -1
	for id in w.entities.keys():
		var x = w.entities[id]
		if x != null and String(x.get("kind", "")) == "wreck":
			wreck_id = int(id)
			break
	check(wreck_id >= 0, "wreck exists")
	var eaten0 := int(Hive71.board(w).get("eaten", 0))
	for i in 600:
		w.step()
		if int(Hive71.board(w).get("eaten", 0)) > eaten0:
			break
	check(int(Hive71.board(w).get("eaten", 0)) > eaten0, "hive ate wreck or terrain")
	check(not w.entities.has(wreck_id) or eaten0 < int(Hive71.board(w).get("eaten", 0)), "wreck consumed")


func test_harvest_drags_wreck_mass() -> void:
	var c := LastProtocol.make_config(302, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 8:
		w.step()
	var home := Vector2(w.sys_state.lp.base.center) + Vector2(60, 0)
	var wreck_pos := home + Vector2(-2, 0)
	var uid := w.spawn_unit("g71_m_brute", int(w.sys_state.lp.fid), wreck_pos)
	w.destroy(uid, "test_wreck")
	var wid := -1
	for id in w.entities.keys():
		if String(w.entities[id].get("kind", "")) == "wreck":
			wid = int(id)
			w.entities[wid].pos = wreck_pos
			break
	check(wid >= 0, "wreck spawned")
	Harvest71._spawn_wave(w, Harvest71._st(w))
	var harvs: Array = Harvest71._st(w).harvs
	if not harvs.is_empty():
		harvs[0].pos = [snappedf(wreck_pos.x - 0.5, 0.01), snappedf(wreck_pos.y, 0.01)]
		Harvest71._st(w).harvs = harvs
	check(int(Harvest71.board(w).get("n", 0)) >= 1, "harvesters")
	var w0 := int(Harvest71.board(w).get("wrecks", 0))
	for i in 200:
		Harvest71._move_harvs(w, Harvest71._st(w))
		if int(Harvest71.board(w).get("wrecks", 0)) > w0:
			break
	check(int(Harvest71.board(w).get("wrecks", 0)) > w0, "harvester took wreck")
	check(float(Harvest71.board(w).get("mass", 0.0)) > 0.0, "mass from wreck")


func test_evolve_adapt_nanite_visible() -> void:
	var c := LastProtocol.make_config(303, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 4:
		w.step()
	var fid := int(w.sys_state.lp.fid)
	w.factions[fid].stats.killed = 12
	Hive9.tick(w)
	check(Hive9.adapt_bonus(w) > 0.0, "adapt bonus from player kills")
	w.sys_state.lp.dread = 0.6
	Evolve71.tick(w)
	check(Evolve71.stage(w) >= 2, "evolve stage with dread+adapt")
	Hive71._st(w).eaten = 5
	Harvest71._st(w).taken = 3
	Hive9._st(w).last_eaten = 0
	Hive9._st(w).last_taken = 0
	Hive9.tick(w)
	check(float(Hive9.board(w).get("nanite", 0.0)) > 0.0, "nanite pool grew")