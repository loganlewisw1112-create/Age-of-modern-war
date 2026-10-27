extends "res://tests/test_base.gd"
## G7 SCALE7: 512x512+ maps. Load/save/validate round trips at 512 and 768, the lp_test512 test map,
## corner-to-corner pathing within a time budget, fog grid size + sight at the far corner, unit lists and
## combat at the far corner, same seed twice = same hash on lp_test512, existing maps unchanged.

const MapIO = preload("res://sim/map_io.gd")
const MapGen = preload("res://sim/map_gen.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Fog = preload("res://sim/systems/fog.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const LpTest = preload("res://sim/maps/lp_test512.gd")
const DIR := "user://test_scale7"
const C := Vector2(0.5, 0.5)
## Terrain + height + ramps md5 of every pre-G7 map at seed 1234 (captured before any G7 map change).
const OLD_MAPS := {
	"river_crossing_s": "6f0059b6184fc69a111383cb6ad748a8",
	"industrial_heartland_m": "701c4ec952e11f85b0d44354245416e9",
	"valley_conquest_l": "02df5504a93480a903b5888d006d961e",
	"coastal_front_m": "847243b173ea98c56637b059e2fbfc7e",
	"ridge_bastion_m": "ee312bb50753fa0d1cac3c6affbf742e",
	"river_dam_m": "bb54b3912d1bf75d375a9e427cff12ee",
}

static var _w512: SimWorld = null


static func _layers_md5(m: Dictionary) -> String:
	var b: PackedByteArray = (m.terrain as PackedByteArray).duplicate()
	b.append_array(m.get("height", PackedByteArray()))
	b.append_array(m.get("ramps", PackedByteArray()))
	return b.hex_encode().md5_text()


static func _cleanup() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


## One shared lp_test512 match (generation + nav build cost ~2 s; tests that change it make their own).
func _world512() -> SimWorld:
	if _w512 == null:
		var c := SimWorld.default_config()
		c.map = "lp_test512"
		c.sides[1].ai = false
		_w512 = SimWorld.new_match(c)
		_w512.ai_state = {}
	return _w512


func _open(w: SimWorld, near: Vector2i, mc := "foot") -> Vector2i:
	return Movement.nearest_free_cell(w, near, mc)


func test_scale7_lp_maps_generate_valid() -> void:
	for id in ["lp_test512", "lp_test768"]:
		check(MapGen.has_map(id), "%s registered" % id)
		var m: Dictionary = MapGen.generate(77, id)
		var n := 512 if id == "lp_test512" else 768
		check_eq(String(m.get("id", "")), id, "%s id" % id)
		check_eq(int(m.w), n, "%s width" % id)
		check_eq(int(m.h), n, "%s height" % id)
		check_eq(String(m.get("last_validation_error", "")), "", "%s validates" % id)
		check(m.has("gen_attempt"), "%s produced a valid variant" % id)
		check_eq((m.height as PackedByteArray).size(), n * n, "%s height layer" % id)
		check_eq((m.bridges as Array).size(), 3, "%s three bridges" % id)
		check(not (m.ford_cells as Array).is_empty(), "%s has fords" % id)
		var towns := 0
		for p in m.pois:
			if String(p.type) == "town":
				towns += 1
		check(towns >= 6, "%s has towns (%d)" % [id, towns])
		var s0: Vector2i = m.spawns[0]
		var s1: Vector2i = m.spawns[1]
		check(Vector2(s0).distance_to(Vector2(s1)) > float(n) * 1.1, "%s sides far apart" % id)
	check_eq(_layers_md5(MapGen.generate(77, "lp_test512")), _layers_md5(MapGen.generate(77, "lp_test512")), "lp_test512 same seed same map")


func test_scale7_existing_maps_unchanged() -> void:
	for id in OLD_MAPS:
		check_eq(_layers_md5(MapGen.generate(1234, id)), String(OLD_MAPS[id]), "%s terrain/height unchanged" % id)


func test_scale7_mapio_round_trip_512_768() -> void:
	for id in ["lp_test512", "lp_test768"]:
		var m: Dictionary = MapGen.generate(5, id)
		var n := int(m.w)
		var sc := {"name": id, "author": "SCALE7", "description": "scale test", "start_packages": true,
			"players": [{"slot": 0, "faction": "human_a", "team": 0, "stage": 8, "credits": 3000, "ai": false, "start": m.spawns[0]},
				{"slot": 1, "faction": "human_b", "team": 1, "stage": 8, "credits": 3000, "ai": false, "start": m.spawns[1]}],
			"entities": [{"kind": "unit", "def": "rifleman", "owner_slot": 0, "cell": Vector2i(n - 30, n - 40), "tag": "far"}],
			"victory": {"victory": "hq_elimination"}, "regions": [], "triggers": []}
		var errs := []
		for iss in MapIO.validate(m, sc):
			if String(iss.get("level", iss.get("severity", "error"))) == "error":
				errs.append(String(iss.code))
		check(not errs.has("terrain_size"), "%s passes the size check (%s)" % [id, str(errs)])
		var p := DIR.path_join(id + ".rtsmap")
		check_eq(MapIO.save(p, m, sc), "", "%s saved" % id)
		var r := MapIO.read(p)
		if not check(not r.has("error"), "%s read back: %s" % [id, r.get("error", "")]):
			continue
		check_eq(int(r.map.w), n, "%s w after read" % id)
		check_eq(int(r.map.h), n, "%s h after read" % id)
		check_eq(_layers_md5(r.map), _layers_md5(m), "%s terrain/height/ramps identical after round trip" % id)
		var p2 := DIR.path_join(id + "_2.rtsmap")
		check_eq(MapIO.save(p2, r.map, r.scenario), "", "%s re-saved" % id)
		check_eq(FileAccess.get_file_as_bytes(p2).size(), FileAccess.get_file_as_bytes(p).size(), "%s stable bytes" % id)
		if n == 512:
			var w := SimWorld.new_match(MapIO.config_for(p, {"seed": 3}))
			if check(w != null, "file match on 512 built"):
				check_eq(int(w.map.w), 512, "file match map is 512")
				var far := 0
				for e in w.units_of(0):
					if Vector2(e.pos).x > 400.0:
						far += 1
				check(far >= 1, "placed unit at the far corner")
	var big := MapIO.validate({"w": 1100, "h": 1100, "terrain": PackedByteArray()}, {})
	var codes := []
	for iss in big:
		codes.append(String(iss.code))
	check(codes.has("terrain_size"), "over the cap still rejected")
	_cleanup()


func test_scale7_path_corner_to_corner_budget() -> void:
	var w := _world512()
	for mc in ["vehicle", "foot"]:
		var a := _open(w, Vector2i(8, 8), mc)
		var b := _open(w, Vector2i(503, 503), mc)
		var t0 := Time.get_ticks_usec()
		var path: Array = Movement._compute(w, mc, a, b, Vector2(b) + C)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		print("  scale7 %s corner path %d points in %.1f ms (native=%s)" % [mc, path.size(), ms, str(Movement._native(w) != null)])
		if check(not path.is_empty(), "%s path corner to corner found" % mc):
			var last: Vector2 = path[path.size() - 1]
			check(last.distance_to(Vector2(b) + C) < 2.0, "%s path ends at the goal" % mc)
		check(ms < (250.0 if Movement._native(w) != null else 4000.0), "%s corner path within budget (%.1f ms)" % [mc, ms])


func test_scale7_fog_far_corner() -> void:
	var w := _world512()
	check_eq((w.fog[0].visible as PackedByteArray).size(), 512 * 512, "fog visible grid 512x512")
	check_eq((w.fog[0].explored as PackedByteArray).size(), 512 * 512, "fog explored grid 512x512")
	var c := _open(w, Vector2i(500, 500))
	var id := w.spawn_unit("rifleman", 0, Vector2(c) + C)
	Fog.recompute(w)
	check(Fog.is_visible(w, 0, Vector2(c) + Vector2(2.5, 1.5)), "far-corner sight reveals cells next to the unit")
	check(not Fog.is_visible(w, 1, Vector2(c) + C), "the other side does not see it")
	check(not Fog.is_visible(w, 0, Vector2(300.5, 300.5)), "an empty mid-map cell stays dark")
	w.destroy(id, "test")
	Fog.recompute(w)


func test_scale7_index_and_combat_far_corner() -> void:
	var c0 := SimWorld.default_config()
	c0.map = "lp_test512"
	c0.sides[1].ai = false
	var w := SimWorld.new_match(c0)
	w.ai_state = {}
	var a := _open(w, Vector2i(496, 300))
	var b := _open(w, Vector2i(500, 300))
	var ia := w.spawn_unit("rifleman", 0, Vector2(a) + C)
	var ib := w.spawn_unit("rifleman", 1, Vector2(b) + C)
	var ids := []
	for e in SimIndex.of(w, "unit"):
		ids.append(int(e.id))
	check(ids.has(ia) and ids.has(ib), "index lists both far-corner units")
	var own: Dictionary = SimIndex.units_by_owner(w)
	check((own.get(1, []) as Array).any(func(e): return int(e.id) == ib), "index owner list has the enemy")
	var hp0 := float(w.entities[ib].hp)
	w.run_ticks(80)
	var hurt := not w.entities.has(ib) or float(w.entities[ib].hp) < hp0
	check(hurt, "far-corner units find and fight each other")


func test_scale7_same_seed_same_hash_lp512() -> void:
	var hs := []
	for run in 2:
		var c := SimWorld.default_config()
		c.map = "lp_test512"
		c.seed = 4242
		c.sides[1].ai = false
		var w := SimWorld.new_match(c)
		w.ai_state = {}
		var rng := SimRng.new(99)
		for side in [0, 1]:
			for g in 10:
				var ctr := _open(w, Vector2i(rng.randi_range(20, 490), rng.randi_range(20, 230) + side * 260), "vehicle")
				var ids := []
				for k in 25:
					var cell := _open(w, ctr + Vector2i(k % 5, k / 5), "foot")
					ids.append(w.spawn_unit("mbt" if k % 8 == 0 else "rifleman", side, Vector2(cell) + C))
				w.submit({"type": "attack_move", "issuer": side, "unit_ids": ids, "target": Vector2(ctr) + Vector2(0.5, 30.5 if side == 0 else -29.5)})
		check_eq(w.units_of(0).size() + w.units_of(1).size() >= 500, true, "500 units placed (run %d)" % run)
		w.run_ticks(200)
		hs.append(w.state_hash())
	print("  scale7 lp_test512 200-tick hash ", hs[0])
	check_eq(hs[1], hs[0], "same seed + commands on lp_test512 = same hash")
