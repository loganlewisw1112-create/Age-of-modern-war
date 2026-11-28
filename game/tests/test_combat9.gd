extends "res://tests/test_base.gd"
## G9 COMBAT9 Done-when #4 (crater/breach save-load) and #5 (ballistics per match family). PROVISIONAL.

const Combat9 = preload("res://sim/systems/combat9.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Parts71 = preload("res://sim/systems/parts71.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Blast8 = preload("res://sim/systems/blast8.gd")
const VehicleCrew9 = preload("res://sim/systems/vehicle_crew9.gd")
const VehicleWear9 = preload("res://sim/systems/vehicle_wear9.gd")
const MachineEW7 = preload("res://sim/systems/machine_ew7.gd")


func _lp() -> SimWorld:
	var c := LastProtocol.make_config(902, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	check(w != null, "LP match")
	for i in 6:
		if w != null:
			w.step()
	return w


func test_crater_persists_save_load() -> void:
	var w := make_world({"seed": 902})
	var cell := Vector2i(22, 18)
	Combat9.add_crater(w, Vector2(cell))
	check_eq(Combat9.crater_count(w), 1, "one crater recorded")
	check(Combat9.crater_at(w, cell), "impact cell is crater terrain")
	var raw := w.to_dict().duplicate(true)
	var w2 := SimWorld.from_dict(raw)
	check(w2 != null, "reload ok")
	check_eq(Combat9.crater_count(w2), 1, "crater list survives save/load")
	check(Combat9.crater_at(w2, cell), "crater terrain survives save/load")


func test_crater_repaths_only_routes_it_crosses() -> void:
	var w := make_world({"seed": 902})
	var terrain: PackedByteArray = w.map.terrain
	for y in range(26, 34):
		for x in range(20, 36):
			terrain[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = terrain
	w.map.erase("height")
	w.map.erase("ramps")
	Movement.rebuild_nav(w)

	var crossing := w.entities[w.spawn_unit("mbt", 0, Vector2(21.5, 28.5))] as Dictionary
	var clear := w.entities[w.spawn_unit("mbt", 0, Vector2(21.5, 31.5))] as Dictionary
	Movement.order_path(w, crossing, Vector2(34.5, 28.5))
	Movement.order_path(w, clear, Vector2(34.5, 31.5))
	for i in 4:
		w.step()
	if not check(crossing.path_req < 0 and clear.path_req < 0 and not crossing.path.is_empty() and not clear.path.is_empty(),
			"both vehicles have an active route"):
		return

	var crossing_path: Array = crossing.path.duplicate()
	var clear_path: Array = clear.path.duplicate()
	var clear_index := int(clear.path_i)
	var impact := Vector2i(28, 28)
	Combat9.add_crater(w, Vector2(impact))
	check(Combat9.crater_at(w, impact) and not Movement.is_passable(w, impact, "vehicle"), "crater remains a vehicle obstacle")
	check(crossing.moving and (int(crossing.path_req) >= 0 or crossing.path != crossing_path),
		"the route through the impact cell is replaced or queued for replanning")
	check_eq(int(clear.path_req), -1, "the route clear of the impact cell keeps its request state")
	check_eq(clear.path, clear_path, "the route clear of the impact cell keeps its waypoints")
	check_eq(int(clear.path_i), clear_index, "the route clear of the impact cell keeps its progress")


func test_breach_persists_save_load() -> void:
	var w := make_world({"seed": 903})
	var cell := Vector2i(40, 40)
	Combat9.add_breach(w, cell, "sandbags")
	check_eq(Combat9.breach_count(w), 1, "one breach")
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	check_eq(Combat9.breach_count(w2), 1, "breach survives save/load")
	var br: Array = w2.sys_state.combat9.breaches
	check_eq(String(br[0][2]), "sandbags", "breach kind intact")


func test_field_fort_persists_save_load() -> void:
	var w := make_world({"seed": 9031})
	var cell := Vector2i(32, 31)
	check(Combat9.dig_fort(w, 0, cell, "sandbag_nest"), "dig fort")
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	var fort := Combat9.fort_at(w2, cell)
	check_eq(String(fort.get("kind", "")), "sandbag_nest", "fort kind survives")
	check_eq(int(fort.get("owner", -1)), 0, "fort owner survives")


func test_vehicle_crew_bail_and_recrew() -> void:
	var w := make_world({"seed": 9032})
	var id := w.spawn_unit("mbt", 0, Vector2(20, 20))
	check(id >= 0 and VehicleCrew9.adopt(w.entities[id], 2), "vehicle crew adopted")
	check(VehicleCrew9.crew_kill(w, id, 2), "crew loss bails")
	check(VehicleCrew9.capturable(w, id), "empty hull capturable")
	check(VehicleCrew9.recrew(w, id, 1, 1), "enemy recrews hull")
	check_eq(int(w.entities[id].owner), 1, "ownership transfers")


func test_vehicle_wear_breakdown_and_recovery() -> void:
	var w := make_world({"seed": 9033})
	var id := w.spawn_unit("mbt", 0, Vector2(20, 20))
	check(VehicleWear9.add_wear(w, id, 1.0), "wear causes breakdown")
	check(bool(w.entities[id].wear9.broken), "vehicle broken")
	check(VehicleWear9.request_recovery(w, id, -1), "tow/recovery requested")
	w.tick = int(w.entities[id].wear9.recover_until)
	VehicleWear9.tick(w)
	check(not bool(w.entities[id].wear9.broken), "vehicle recovered")


func test_ew_jam_vehicle_skirmish_and_lp() -> void:
	for w in [make_world({"seed": 9034}), _lp()]:
		if w == null:
			continue
		var id: int = w.spawn_unit("mbt", 0, Vector2(20, 20))
		check(MachineEW7.jam(w, w.entities[id], 2.0, -1), "vehicle jam accepted")
		check_eq(MachineEW7.held(w, id), "jam", "EW jam active in match family")


func test_blast8_wires_crater() -> void:
	var w := make_world({"seed": 904})
	var pos := Vector2(25, 25)
	var prof := {"name": "mortar", "charge_kg": 0.9, "blast_dmg": 80.0}
	Blast8.on_burst(w, pos, prof, [], {})
	check(Combat9.crater_count(w) >= 1, "mortar-scale burst leaves a crater")


func test_ballistics_skirmish_family() -> void:
	var w := make_world({"seed": 905})
	check_eq(Combat9.match_family(w), "skirmish", "default conquest family")
	var r: Dictionary = Combat9.exercise_ballistics(w, "mbt")
	check(r.ok, "mbt facing + rear path (%s)" % str(r))
	check_eq(String(r.rear_side), "rear", "shooter behind target")
	check(r.rear_dmg >= r.front_dmg, "rear >= front damage")
	check(Combat9.harness_ok(w, "skirmish"), "harness skirmish")


func test_ballistics_last_protocol_family() -> void:
	var w := _lp()
	if w == null:
		return
	Parts71.enable(w)
	check_eq(Combat9.match_family(w), "last_protocol", "LP family")
	var r: Dictionary = Combat9.exercise_ballistics(w, "m_walker")
	check(r.ok, "walker weak-spot + facing (%s)" % str(r))
	check(r.weak_mult > 1.05, "weak part mult > 1 (%s @ %.2f)" % [r.weak_part, r.weak_mult])
	check(Combat9.harness_ok(w, "last_protocol"), "harness LP")


func test_ballistics_editor_live_family() -> void:
	var w := make_world({"seed": 906, "live_mode": true}, false)
	check_eq(Combat9.match_family(w), "editor_live", "editor live family")
	var def := "apc"
	if Content.unit(def).is_empty():
		def = "mbt"
	var r: Dictionary = Combat9.exercise_ballistics(w, def)
	check(r.ok, "%s editor_live ballistics (%s)" % [def, str(r)])
	check(Combat9.harness_ok(w, "editor_live"), "harness editor_live")