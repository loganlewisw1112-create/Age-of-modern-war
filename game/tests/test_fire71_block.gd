extends "res://tests/test_base.gd"
## G7.1 I4: Fire71.blocks_at is the fire-line API cores / tide pathing consult.

const Fire71 = preload("res://sim/systems/fire71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_blocks_at_api() -> void:
	var c := LastProtocol.make_config(87, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 4:
		w.step()
	var p := Vector2(w.sys_state.lp.base.center) + Vector2(10, 0)
	_force_grass(w, floori(p.x), floori(p.y))
	check(not Fire71.blocks_at(w, p), "clear before ignite")
	Fire71.ignite_cell(w, p, 0, 0.9)
	check(Fire71.blocks_at(w, p), "blocks after hard burn")


func _force_grass(w: SimWorld, x: int, y: int) -> void:
	if w.map == null or x < 0 or y < 0 or x >= w.map.w or y >= w.map.h:
		return
	w.map.terrain[y * w.map.w + x] = Terrain.GRASS
