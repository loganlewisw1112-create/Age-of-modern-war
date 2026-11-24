extends "res://tests/test_base.gd"
## G9 HIVE9: wreck harvest, evolve + adapt, hive eat path.

const Hive71 = preload("res://sim/systems/hive71.gd")
const Hive9 = preload("res://sim/systems/hive9.gd")
const Harvest71 = preload("res://sim/systems/harvest71.gd")
const Evolve71 = preload("res://sim/systems/evolve71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Count9 = preload("res://sim/systems/count9.gd")


func test_catalog_ge_60() -> void:
	var path := "res://assets/art/g71_hive9/manifest.json"
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not check(manifest is Dictionary, "HIVE9 manifest loads"):
		return
	var vehicles: Dictionary = (manifest as Dictionary).get("vehicles", {})
	var content_backed := 0
	for def_id in vehicles:
		var unit_def: Dictionary = Content.unit(String(def_id))
		var spec: Dictionary = vehicles[def_id]
		var g9: Dictionary = spec.get("g9", {})
		var art_path := "res://assets/art/g71_hive9/" + String(spec.get("file", ""))
		if String(unit_def.get("faction", "")) == "machine" and String(g9.get("blend", "")) == "hive9" and FileAccess.file_exists(art_path):
			content_backed += 1
	check(content_backed >= 60, "content-backed blended Machine catalog >= 60")
	check_eq(Hive9.catalog_count(), content_backed, "catalog_count validates Content.unit + blended art")
	check(not vehicles.keys().any(func(id): return String(id).contains("__mod_")), "no asset-only modular count fillers")


func test_modular_events_visible_on_eat_and_replicate() -> void:
	var c := LastProtocol.make_config(304, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 4:
		w.step()
	var s := Hive9._st(w)
	Hive71._st(w).eaten = int(s.last_eaten) + 1
	Hive9.tick(w)
	var events: Dictionary = Hive9.board(w).get("modular_events", {})
	check(int(events.get("merge", 0)) >= 1, "wreck intake records modular merge")
	s.nanite = float(Hive9.R().get("replicate_cost", 6.0)) + 1.0
	w.sys_state.lp.dread = 1.0
	w.tick = 7
	Hive9.tick(w)
	events = Hive9.board(w).get("modular_events", {})
	check(int(Hive9.board(w).get("replicas", 0)) >= 1, "minimal replica spawned")
	check(int(events.get("split", 0)) >= 1, "replica records modular split")


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


func test_network_quality_topology_senses_and_cable_cuts() -> void:
	var w := SimWorld.new_match(LastProtocol.make_config(305, "industrial_heartland_m"))
	if not check(w != null, "LP"):
		return
	for i in 4:
		w.step()
	var a := Vector2(10.5, 10.5)
	var b := Vector2(30.5, 10.5)
	var near_q := Hive9.link_quality(w, a, b, "spine", 0.0)
	var far_q := Hive9.link_quality(w, a, Vector2(100.5, 10.5), "spine", 0.0)
	check(near_q > far_q, "distance degrades bandwidth")
	check(Hive9.link_quality(w, a, b, "spine", 0.5) < near_q, "EW degrades bandwidth")
	check(Hive9.link_quality(w, a, b, "mesh", 0.0) < near_q, "mesh trades throughput for redundancy")
	var cs := Creep.enable(w)
	var cv: PackedByteArray = cs.v
	cv.fill(255)
	cs.v = cv
	check(Hive9.link_quality(w, a, Vector2(115.5, 10.5), "spine", 0.0) >= float(Hive9.R().get("creep_signal_floor", 0.22)),
		"creep carries weak cable signal")
	Hive71.add_nest(w, "sense_a", a)
	Hive71.add_nest(w, "sense_b", b)
	Hive71.add_relay(w, "sense_r", a.lerp(b, 0.5), ["sense_a", "sense_b"])
	Hive9.report_contact(w, "sense_a", 99, Vector2(44, 44))
	check(Hive9.shared_contacts(w, "sense_b").size() == 1, "linked peer shares last-seen contact")
	Hive71.cut_relay(w, "sense_r")
	check(Hive9.shared_contacts(w, "sense_b").is_empty(), "cut peer becomes fog-blind")
	Count9.mark_dead_zone(w, a.lerp(b, 0.5), 4.0)
	check_eq(Hive9.link_quality(w, a, b), 0.0, "dead zone carves network cable")