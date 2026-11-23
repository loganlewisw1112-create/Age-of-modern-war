extends "res://tests/test_base.gd"
## G7.1 I4 wildfire: wind-spread, fire line block, night light.

const Fire71 = preload("res://sim/systems/fire71.gd")
const Night71 = preload("res://sim/systems/night71.gd")
const Weather71 = preload("res://sim/systems/weather71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_ignite_spreads_blocks_and_lights() -> void:
	var c := LastProtocol.make_config(83, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 6:
		w.step()
	Night71.set_night(w, true)
	# Force a flammable origin near base.
	var origin := Vector2(w.sys_state.lp.base.center) + Vector2(6, 0)
	# Stamp grass under origin + downwind cell so ignite/spread can land.
	_force_grass(w, floori(origin.x), floori(origin.y))
	var wind := Weather71.wind(w)
	var n := wind.normalized() if wind.length_squared() > 0.0001 else Vector2.RIGHT
	var wx := int(sign(n.x)) if absf(n.x) >= absf(n.y) * 0.5 else 0
	var wy := int(sign(n.y)) if absf(n.y) >= absf(n.x) * 0.5 else 0
	if wx == 0 and wy == 0:
		wx = 1
	_force_grass(w, floori(origin.x) + wx, floori(origin.y) + wy)
	Fire71.ignite_cell(w, origin, 0, 0.9)
	check(Fire71.burning_at(w, origin), "origin burning")
	check(Fire71.blocks_at(w, origin), "fire line blocks")
	check(Night71.lit(w, origin), "fire lights night")
	# Advance enough step ticks for a spread attempt.
	for i in 40:
		w.step()
	check(int(Fire71.board(w).get("n", 0)) >= 1, "cells persist or spread")


func _force_grass(w: SimWorld, x: int, y: int) -> void:
	if w.map == null or x < 0 or y < 0 or x >= w.map.w or y >= w.map.h:
		return
	w.map.terrain[y * w.map.w + x] = Terrain.GRASS
