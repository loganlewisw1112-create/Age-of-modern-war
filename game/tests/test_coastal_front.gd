extends "res://tests/test_base.gd"
## G5 acceptance (owner: NAVAL). Coastal Front (coastal_front_m), CONTRACTS_G5 sections 8, 11.

const CF = preload("res://sim/maps/coastal_front.gd")
const MapUtil = preload("res://sim/maps/map_util.gd")
const MapCheck = preload("res://sim/maps/map_check.gd")
const MapGen = preload("res://sim/map_gen.gd")


func test_coastal_front_validates_seeds_1_to_5() -> void:
	for s in range(1, 6):
		var m := CF.generate(s)
		check_eq(String(m.get("last_validation_error", "")), "", "seed %d: a valid variant within %d attempts" % [s, CF.MAX_ATTEMPTS])
		check_eq(CF.validate(m), "", "seed %d validates" % s)
		check_eq([int(m.w), int(m.h)], [192, 192], "seed %d is 192x192" % s)
		check_eq(String(m.id), "coastal_front_m", "map id")
		check(int(m.max_sides) >= 2 and int(m.max_sides) <= 4, "2-4 sides")
		for k in ["2", "3", "4"]:
			check_eq((m.spawn_sets[k] as Array).size(), int(k), "seed %d spawn_sets[%s]" % [s, k])
	var a := CF.generate(5)
	var b := CF.generate(5)
	var c := CF.generate(6)
	check(a.terrain == b.terrain and var_to_bytes(a.resources) == var_to_bytes(b.resources), "same seed -> same map")
	check(a.terrain != c.terrain, "different seed -> different coast")
	# the shared map registry (ORCH registers coastal_front_m on NAVAL's change request)
	check(MapGen.has_map("coastal_front_m"), "MapGen lists coastal_front_m")
	if MapGen.has_map("coastal_front_m"):
		for s in range(1, 6):
			var m := MapGen.generate(s, "coastal_front_m")
			check_eq(MapGen.validate(m), "", "MapGen seed %d validates" % s)
			check_eq(CF.validate(m), "", "MapGen seed %d passes the coastal checks" % s)


func test_spawns_reachable_by_land_or_sea() -> void:
	for s in range(1, 6):
		var m := CF.generate(s)
		var rep := CF.reach_report(m)
		check_eq(rep.size(), (m.spawns as Array).size(), "one report row per spawn")
		for r in rep:
			check(bool(r.land) or bool(r.sea), "seed %d spawn %s reachable by land or sea" % [s, r.spawn])
			check(bool(r.sea), "seed %d spawn %s has sea access" % [s, r.spawn])
		for k in ["2", "3", "4"]:
			for si in m.spawn_sets[k]:
				var sp: Vector2i = m.spawns[int(si)]
				check(MapUtil.inb(sp, 192, 192), "spawn in bounds")
	# a match really starts on the map (4 sides, every HQ on buildable ground), when registered
	if MapGen.has_map("coastal_front_m"):
		var cfg := SimWorld.default_config()
		cfg.map = "coastal_front_m"
		cfg.seed = 3
		var sides := []
		for i in 4:
			sides.append({"faction": ["human_a", "human_b", "machine", "human_a"][i], "stage": 8, "credits": 2000, "ai": false, "name": "S%d" % i, "team": i})
		cfg.sides = sides
		var w := SimWorld.new_match(cfg)
		check(w != null, "4-side match starts on Coastal Front")
		if w != null:
			var hqs := 0
			for id in w.entities:
				var e: Dictionary = w.entities[id]
				if e.kind == "building" and bool(Content.building(String(e.def)).get("is_hq", false)):
					hqs += 1
			check_eq(hqs, 4, "4 HQs placed")


func test_has_beaches_islands_estuary() -> void:
	for s in range(1, 6):
		var m := CF.generate(s)
		var t: PackedByteArray = m.terrain
		var counts := {}
		for i in t.size():
			counts[t[i]] = int(counts.get(t[i], 0)) + 1
		check(int(counts.get(Terrain.BEACH, 0)) >= 300, "seed %d beaches (%d cells)" % [s, int(counts.get(Terrain.BEACH, 0))])
		check(int(counts.get(Terrain.DEEP, 0)) >= 2000, "seed %d open sea (%d deep cells)" % [s, int(counts.get(Terrain.DEEP, 0))])
		check(int(counts.get(Terrain.CLIFF, 0)) > 0, "seed %d has cliff stretches (beaches are not everywhere)" % s)
		var isl := 0
		for n in CF.island_sizes(t):
			if int(n) >= 40:
				isl += 1
		check_eq(isl, 2, "seed %d: 2 islands" % s)
		# estuary: small boats cross the mainland from the west sea to the east sea; deep ships cannot
		var small := MapCheck.bfs(CF.class_mask(t, "naval_small"), 192, 192, 96 * 192 + 1)
		var deep := MapCheck.bfs(CF.class_mask(t, "naval"), 192, 192, 96 * 192 + 1)
		check(small[95 * 192 + 190] >= 0, "seed %d: estuary joins the seas for naval_small" % s)
		check(deep[95 * 192 + 190] < 0, "seed %d: the fords stop naval ships" % s)
		var fords: Array = m.ford_cells
		check(fords.size() >= 6, "seed %d: estuary fords (%d cells)" % [s, fords.size()])
		for c in fords:
			check_eq(t[c.y * 192 + c.x], Terrain.SHALLOW, "ford cell %s is SHALLOW" % c)
		var types := {}
		for p in m.pois:
			types[String(p.type)] = true
		for ty in ["island", "estuary", "ford", "beach"]:
			check(types.has(ty), "seed %d POI %s" % [s, ty])
