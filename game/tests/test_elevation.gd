extends "res://tests/test_base.gd"
## G6 acceptance (owner: ELEV). CONTRACTS_G6 section 5.2, section 7, section 17. Real checks of the
## Elevation API on a small authored test map (32x32), the map file migration, save/load, and the
## built-in maps' authored height.

const Elevation = preload("res://sim/systems/elevation.gd")
const MapCheck = preload("res://sim/maps/map_check.gd")
const MapUtil = preload("res://sim/maps/map_util.gd")
const MapIO = preload("res://sim/map_io.gd")
const MapGen = preload("res://sim/map_gen.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const N := 32


## World with a flat 32x32 map; `layer` true adds an all-plain height layer and no ramps.
func _w(layer: bool = true) -> SimWorld:
	var w := make_world()
	var t := PackedByteArray()
	t.resize(N * N)
	t.fill(Terrain.GRASS)
	w.map = {"id": "elev_test", "w": N, "h": N, "terrain": t, "spawns": [Vector2i(4, 4), Vector2i(27, 27)], "resources": []}
	if layer:
		w.map.height = MapUtil.new_layer(N, N, 1)
		w.map.ramps = MapUtil.new_layer(N, N, 0)
	return w


func _put(w: SimWorld, key: String, c: Vector2i, v: int) -> void:
	var a: PackedByteArray = w.map[key]
	a[c.y * N + c.x] = v
	w.map[key] = a


func _ids() -> Array:   # [ground unit def, air unit def, rules]
	var ground := ""
	var air := ""
	var keys: Array = Content.table("units").keys()
	keys.sort()
	for k in keys:
		var d: Dictionary = Content.unit(String(k))
		if bool(d.get("is_air", false)):
			if air == "":
				air = String(k)
		elif ground == "" and String(d.get("weapon", "")) != "":
			ground = String(k)
	return [ground, air, Elevation.rules()]


func _u(def: String, x: float, y: float) -> Dictionary:
	return {"id": 1, "kind": "unit", "def": def, "owner": 0, "pos": Vector2(x, y)}


func test_levels_0_to_3_and_ramps() -> void:
	var flat := _w(false)
	check(not Elevation.has_height(flat), "no height layer by default on the test map")
	check_eq(Elevation.height_at(flat, Vector2i(5, 5)), 1, "absent height = plain")
	check(not Elevation.ramp_at(flat, Vector2i(5, 5)), "absent ramps = none")
	var w := _w()
	for lv in 4:
		_put(w, "height", Vector2i(10 + lv, 10), lv)
	for lv in 4:
		check_eq(Elevation.height_at(w, Vector2i(10 + lv, 10)), lv, "level %d stored and read" % lv)
	check_eq(Elevation.height_at(w, Vector2i(-1, 3)), 1, "outside the map reads plain")
	var rp := MapUtil.derive_ramps(w.map.height, w.map.terrain, N, N, [1, 1, 1])
	check_eq(rp[10 * N + 11], 1, "derive_ramps flags a 0->1 / 1->2 boundary cell")
	check_eq(rp[20 * N + 20], 0, "derive_ramps leaves flat ground alone")
	w.map.ramps = rp
	check(Elevation.ramp_at(w, Vector2i(11, 10)), "ramp_at reads the ramp layer")
	check_eq(MapCheck.height_issue(w.map, false), "", "valid layer passes height_issue")
	_put(w, "ramps", Vector2i(25, 25), 1)
	check(MapCheck.height_issue(w.map, false).contains("Ramp"), "a ramp on flat ground is rejected")
	_put(w, "ramps", Vector2i(25, 25), 0)
	_put(w, "height", Vector2i(2, 2), 4)
	check(MapCheck.height_issue(w.map, false).contains("out of range"), "level 4 is rejected")


func test_cliff_impassable_for_ground() -> void:
	var w := _w()
	check(Elevation.edge_ok(_w(false), Vector2i(1, 1), Vector2i(2, 1)), "no height: every edge open")
	_put(w, "height", Vector2i(6, 5), 2)       # one level up, no ramp: cliff
	check(Elevation.edge_ok(w, Vector2i(4, 5), Vector2i(5, 5)), "same level open")
	check(not Elevation.edge_ok(w, Vector2i(5, 5), Vector2i(6, 5)), "1 level up without ramp is a cliff")
	check(not Elevation.edge_ok(w, Vector2i(5, 4), Vector2i(6, 5)), "diagonal past a cliff corner is closed")
	check(Elevation.edge_ok(w, Vector2i(4, 4), Vector2i(5, 5)), "diagonal on flat ground is open")
	_put(w, "ramps", Vector2i(6, 5), 1)
	check(Elevation.edge_ok(w, Vector2i(5, 5), Vector2i(6, 5)), "1 level up through a ramp is open")
	check(Elevation.edge_ok(w, Vector2i(6, 5), Vector2i(5, 5)), "edge rule is symmetric")
	_put(w, "height", Vector2i(7, 5), 0)
	_put(w, "ramps", Vector2i(7, 5), 1)
	check(not Elevation.edge_ok(w, Vector2i(6, 5), Vector2i(7, 5)), "2 levels apart is a cliff even with ramps")
	# plateau ringed by cliffs: unreachable by foot and vehicle until one ramp joins it
	var p := _w()
	for y in range(12, 17):
		for x in range(12, 17):
			_put(p, "height", Vector2i(x, y), 2)
	for mc in ["foot", "vehicle"]:
		var pm := MapCheck.passmask(p.map.terrain, mc)
		var d := MapCheck.bfs(pm, N, N, 2 * N + 2, p.map.height, p.map.ramps)
		check_eq(d[14 * N + 14], -1, "%s cannot climb a cliff-ringed plateau" % mc)
	_put(p, "ramps", Vector2i(14, 12), 1)
	var d2 := MapCheck.bfs(MapCheck.passmask(p.map.terrain, "vehicle"), N, N, 2 * N + 2, p.map.height, p.map.ramps)
	check(d2[14 * N + 14] > 0, "one ramp makes the plateau reachable")
	for mc in ["foot", "vehicle", "amphibious", "rail", "hover"]:
		check(Terrain.uses_height(mc), "%s obeys height" % mc)
	for mc in ["air", "air_low", "air_high", "naval", "naval_small"]:
		check(not Terrain.uses_height(mc), "%s ignores height" % mc)
	check_eq(Terrain.RAIL, 14, "Terrain.RAIL = 14")
	check(Terrain.passable(Terrain.RAIL, "foot") and Terrain.passable(Terrain.RAIL, "vehicle"), "RAIL open to foot and vehicle")
	check(Terrain.passable(Terrain.RAIL, "rail") and not Terrain.passable(Terrain.ROAD, "rail"), "rail class: RAIL only")
	check(Terrain.passable(Terrain.DEEP, "hover") and not Terrain.passable(Terrain.CLIFF, "hover") and not Terrain.passable(Terrain.FOREST, "hover"), "hover over water, not cliff/forest")


func test_los_blocked_by_higher_ground() -> void:
	var w := _w()
	check(Elevation.los(_w(false), Vector2(2.5, 8.5), Vector2(20.5, 8.5)), "no height: LOS open")
	for y in N:
		_put(w, "height", Vector2i(10, y), 2)   # a hill wall at x = 10
	var a := Vector2(4.5, 8.5)
	var b := Vector2(16.5, 8.5)
	check(not Elevation.los(w, a, b), "level-2 wall blocks plain-to-plain LOS")
	check(not Elevation.los(w, b, a), "blocked both ways")
	check(not Elevation.los(w, Vector2(4.5, 3.5), Vector2(16.5, 20.5)), "blocked on a diagonal")
	check(Elevation.los(w, Vector2(4.5, 8.5), Vector2(9.5, 20.5)), "LOS open when the segment misses the wall")
	_put(w, "height", Vector2i(4, 8), 2)
	check(Elevation.los(w, a, b), "shooter on level 2 sees over a level-2 wall")
	for y in N:
		_put(w, "height", Vector2i(12, y), 3)   # a ridge line behind it
	check(not Elevation.los(w, a, b), "level-3 ridge blocks a level-2 shooter")
	_put(w, "height", Vector2i(16, 8), 3)
	check(Elevation.los(w, a, b), "target on level 3: nothing between is higher")
	check_eq(Elevation.adv(w, Vector2(16.5, 8.5), a), 1, "adv: level 3 over level 2 = 1")


func test_height_bonus_sight_range_defence_per_level() -> void:
	var ids := _ids()
	var r: Dictionary = ids[2]
	check(String(ids[0]) != "", "found a ground unit def")
	check_eq(float(r.sight_per_level), 2.0, "D24 sight +2 per level")
	check(is_equal_approx(float(r.range_mult_per_level), 1.10), "D24 range x1.10 per level")
	check(is_equal_approx(float(r.defence_mult_per_level), 0.85), "D24 damage taken x0.85 per level")
	var w := _w()
	for lv in 4:
		_put(w, "height", Vector2i(4 + lv * 4, 4), lv)
	var s := {"indirect": false, "is_air": false}
	var expect_sight := [0.0, 0.0, 2.0, 4.0]
	var expect_range := [1.0, 1.0, 1.1, 1.21]
	for lv in 4:
		var e := _u(ids[0], 4.5 + lv * 4, 4.5)
		check(is_equal_approx(Elevation.sight_bonus(w, e), expect_sight[lv]), "sight bonus at level %d" % lv)
		check(is_equal_approx(Elevation.range_mult(w, e, s), expect_range[lv]), "range mult at level %d" % lv)
	var low := _u(ids[0], 4.5, 4.5)        # level 0
	var high := _u(ids[0], 16.5, 4.5)      # level 3
	var mid := _u(ids[0], 12.5, 4.5)       # level 2
	check(is_equal_approx(Elevation.defence_mult(w, low, high), pow(0.85, 3)), "target 3 levels above: x0.85^3")
	check(is_equal_approx(Elevation.defence_mult(w, mid, high), 0.85), "target 1 level above: x0.85")
	check_eq(Elevation.defence_mult(w, high, low), 1.0, "target below the attacker: no reduction")
	check(is_equal_approx(Elevation.range_mult_vs(w, high, s, low), pow(1.1, 3)), "per-target range: 3 levels over")
	check_eq(Elevation.range_mult_vs(w, low, s, high), 1.0, "shooting uphill: no range bonus")
	var f := _w(false)
	check_eq(Elevation.sight_bonus(f, high) + Elevation.range_mult(f, high, s) + Elevation.defence_mult(f, low, high), 2.0, "flat map: neutral")


func test_ramp_climb_slows_to_0_7() -> void:
	var ids := _ids()
	check_eq(float(ids[2].ramp_speed_mult), 0.7, "D24 ramp speed x0.7")
	var w := _w()
	_put(w, "height", Vector2i(9, 9), 2)
	_put(w, "height", Vector2i(10, 9), 2)
	_put(w, "ramps", Vector2i(9, 9), 1)
	check(is_equal_approx(Elevation.slope_mult(w, _u(ids[0], 9.5, 9.5)), 0.7), "ground unit on a ramp: x0.7")
	check_eq(Elevation.slope_mult(w, _u(ids[0], 10.5, 9.5)), 1.0, "hill top (no ramp): full speed")
	check_eq(Elevation.slope_mult(w, _u(ids[0], 3.5, 3.5)), 1.0, "plain: full speed")
	if String(ids[1]) != "":
		check_eq(Elevation.slope_mult(w, _u(ids[1], 9.5, 9.5)), 1.0, "aircraft ignore ramps")
	check_eq(Elevation.slope_mult(_w(false), _u(ids[0], 9.5, 9.5)), 1.0, "flat map: neutral")


func test_air_and_indirect_ignore_los() -> void:
	var ids := _ids()
	check(String(ids[1]) != "", "found an air unit def")
	var w := _w()
	for y in N:
		_put(w, "height", Vector2i(10, y), 3)
	var shooter := _u(ids[0], 4.5, 8.5)
	var target := _u(ids[0], 16.5, 8.5)
	var direct := {"indirect": false, "is_air": false}
	check(not Elevation.los_for(w, shooter, direct, target), "direct fire blocked by the ridge")
	check(Elevation.los_for(w, shooter, {"indirect": true, "is_air": false}, target), "indirect fire ignores height LOS")
	check(Elevation.los_for(w, _u(ids[1], 4.5, 8.5), {"indirect": false, "is_air": true}, target), "air shooter ignores height LOS")
	check(Elevation.los_for(w, shooter, direct, _u(ids[1], 16.5, 8.5)), "air target ignores height LOS")
	_put(w, "height", Vector2i(4, 8), 2)
	check(is_equal_approx(Elevation.range_mult(w, shooter, {"indirect": true, "is_air": false}), 1.1), "indirect keeps the range bonus")
	var plane := _u(ids[1], 4.5, 8.5)
	check_eq(Elevation.range_mult(w, plane, {"indirect": false, "is_air": true}), 1.0, "aircraft: no range bonus")
	check_eq(Elevation.sight_bonus(w, plane), 0.0, "aircraft: no sight bonus")
	check_eq(Elevation.defence_mult(w, _u(ids[0], 16.5, 8.5), plane), 1.0, "aircraft: no defence bonus")


func test_old_maps_load_plain_hill_becomes_level_2() -> void:
	var w := _w(false)
	var t: PackedByteArray = w.map.terrain
	for c in [Vector2i(8, 8), Vector2i(9, 8), Vector2i(8, 9)]:
		t[c.y * N + c.x] = Terrain.HILL
	t[20 * N + 20] = Terrain.CLIFF
	w.map.terrain = t
	var sc := {"name": "old", "players": [{"slot": 0, "faction": "human_a", "team": 0}, {"slot": 1, "faction": "human_a", "team": 1}]}
	var raw := MapIO.encode(w.map, sc)
	check_eq(int(raw.version), 2, "files are written as version 2")
	check(not raw.has("height_b64"), "a flat map writes no height")
	raw.version = 1
	var r := MapIO.decode(JSON.parse_string(JSON.stringify(raw)))
	check(not r.has("error"), "version-1 file loads: %s" % r.get("error", ""))
	var m: Dictionary = r.get("map", {})
	check(m.has("height"), "HILL tiles create a height layer")
	if m.has("height"):
		check_eq(int(m.height[8 * N + 8]), 2, "HILL -> level 2")
		check_eq(int(m.height[3 * N + 3]), 1, "other cells plain")
		check_eq(int(m.terrain[8 * N + 8]), Terrain.GRASS, "HILL bonuses replaced by height (code -> GRASS)")
		check_eq(int(m.terrain[20 * N + 20]), Terrain.CLIFF, "CLIFF kept")
		check_eq(int(m.ramps[8 * N + 8]), 1, "migrated hill edge is a ramp (stays walkable)")
	var flat := _w(false)
	var raw2 := MapIO.encode(flat.map, sc)
	raw2.version = 1
	var r2 := MapIO.decode(JSON.parse_string(JSON.stringify(raw2)))
	check(not (r2.get("map", {}) as Dictionary).has("height"), "version-1 file without HILL stays flat (no layer)")
	raw2.version = 3
	check(MapIO.decode(raw2).has("error"), "unknown future version rejected")
	var tut := MapIO.read("res://content/scenarios/tutorial.rtsmap")
	check(not tut.has("error") and not (tut.get("map", {}) as Dictionary).has("height"), "tutorial (v1, no HILL) loads flat")


func test_save_load_keeps_height() -> void:
	var w := make_world()
	var mw := int(w.map.w)
	var hg := MapUtil.new_layer(mw, int(w.map.h), 1)
	hg[5 * mw + 5] = 3
	hg[6 * mw + 5] = 0
	var rp := MapUtil.new_layer(mw, int(w.map.h), 0)
	rp[7 * mw + 7] = 1
	w.map.height = hg
	w.map.ramps = rp
	var path := "user://test_elev_save.sav"
	check_eq(SaveSystem.save(w, path), "", "save ok")
	var l: SimWorld = SaveSystem.load(path)
	check(l != null, "load ok")
	if l != null:
		check_eq(l.map.get("height"), hg, "height round-trips through SaveSystem")
		check_eq(l.map.get("ramps"), rp, "ramps round-trip through SaveSystem")
		check_eq(l.state_hash(), w.state_hash(), "state hash equal after load (height is hashed)")
	var before := w.state_hash()
	hg[5 * mw + 5] = 2
	w.map.height = hg
	check(w.state_hash() != before, "height is part of the state hash")
	var sc := {"name": "h", "players": [{"slot": 0, "faction": "human_a", "team": 0}, {"slot": 1, "faction": "human_a", "team": 1}]}
	var mp := "user://test_elev_map.rtsmap"
	check_eq(MapIO.save(mp, w.map, sc), "", "rtsmap save ok")
	var rr := MapIO.read(mp)
	check(not rr.has("error"), "rtsmap read ok")
	if not rr.has("error"):
		check_eq(rr.map.get("height"), hg, "rtsmap keeps height")
		check_eq(rr.map.get("ramps"), rp, "rtsmap keeps ramps")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mp))


func test_builtin_maps_validate_reachable() -> void:
	var levels := {}
	for id in MapGen.ids():
		var m := MapGen.generate(1, String(id))
		check_eq(MapGen.validate(m), "", "%s validates" % id)
		check(m.has("height") and m.has("ramps"), "%s carries authored height" % id)
		if not m.has("height"):
			continue
		check_eq(MapGen.validate_height(m), [], "%s: validate_height clean" % id)
		var hg: PackedByteArray = m.height
		var seen := {}
		for i in hg.size():
			seen[int(hg[i])] = true
			levels[int(hg[i])] = true
		check(seen.size() >= 2, "%s has more than one level" % id)
		var w := int(m.w)
		for mc in ["foot", "vehicle"]:
			var pm := MapCheck.passmask(m.terrain, mc)
			var s0: Vector2i = m.spawns[0] + Vector2i(0, 3)
			var d := MapCheck.bfs(pm, w, int(m.h), s0.y * w + s0.x, m.height, m.ramps)
			for s in m.spawns:
				var p: Vector2i = s + Vector2i(0, 3)
				check(d[p.y * w + p.x] >= 0, "%s: spawn %s reachable by %s through ramps" % [id, s, mc])
	check_eq(levels.size(), 4, "built-in maps use all four levels")
