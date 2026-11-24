extends "res://tests/test_base.gd"

const Pace71 = preload("res://sim/systems/pace71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Creep = preload("res://sim/systems/creep.gd")


func _skirmish() -> SimWorld:
	return make_world({
		"victory": "endless",
		"sides": [
			{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "H", "team": 0},
			{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 1},
		],
	})


func _check_mode(w: SimWorld, label: String) -> void:
	var fid := int(w.factions.keys()[0])
	var at := Vector2(20.5, 20.5)
	for y in range(4, mini(int(w.map.h), 40)):
		for x in range(4, mini(int(w.map.w), 40)):
			if not Creep.on_creep(w, Vector2i(x, y)) and Terrain.passable(w.terrain_at(Vector2i(x, y)), "vehicle"):
				at = Vector2(x, y) + Vector2(0.5, 0.5)
				break
		if at != Vector2(20.5, 20.5):
			break
	var id := w.spawn_unit("mbt", fid, at)
	var e: Dictionary = w.entities[id]
	var open := Pace71.speed_mult(w, e, e.pos)
	check(open >= 1.69, "%s open-ground vehicle pace is ~1.7x (%.2f)" % [label, open])
	var cell := w.cell_of(e.pos)
	w.map.terrain[cell.y * w.map.w + cell.x] = Terrain.ROAD
	var road_effective := Pace71.speed_mult(w, e, e.pos) * Terrain.speed_mult(Terrain.ROAD, "vehicle")
	check(road_effective > open * 1.19, "%s road is about 20%% faster than open" % label)
	w.map.terrain[cell.y * w.map.w + cell.x] = Terrain.GRASS
	e.g71_mud = true
	var mud := Pace71.speed_mult(w, e, e.pos)
	check(mud < open * 0.71, "%s mud/rubble/creep penalty is about 30%%" % label)
	check(not e.has("pace71_accel") and not e.has("pace71_turn") and not e.has("pace71_deploy"),
		"%s pace does not bypass accel/turn/deploy state" % label)


func test_vehicle_pace_skirmish_and_lp() -> void:
	_check_mode(_skirmish(), "skirmish")
	var lp := SimWorld.new_match(LastProtocol.make_config(711, "industrial_heartland_m"))
	check(lp != null, "LP match")
	if lp != null:
		_check_mode(lp, "LP")
