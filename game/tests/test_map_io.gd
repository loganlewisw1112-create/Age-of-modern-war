extends "res://tests/test_base.gd"
## MAPIO (CONTRACTS_G4 section 5): .rtsmap save/read/validate, built-in export round trip,
## file-map matches (placement, save/load hash), seed-repeat on every built-in map.

const MapIO = preload("res://sim/map_io.gd")
const MapGen = preload("res://sim/map_gen.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const DIR := "user://test_mapio"


static func cleanup() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


## A flat grass map (size n) with 2 players at (8,8) / (n-9,n-9) and two salvage piles.
static func flat(n: int = 48) -> Dictionary:
	var t := PackedByteArray()
	t.resize(n * n)
	t.fill(Terrain.GRASS)
	return {"w": n, "h": n, "terrain": t, "decor": [], "bridges": [], "hold_bridge": 0,
		"resources": [{"res": "salvage", "amount": 1500, "cell": Vector2i(14, 8)},
			{"res": "ore", "amount": 2000, "cell": Vector2i(n - 15, n - 9)}]}


static func scenario(n: int = 48, pkgs: bool = true) -> Dictionary:
	return {"name": "Test Flats", "author": "MAPIO", "description": "unit test map", "start_packages": pkgs,
		"players": [{"slot": 0, "faction": "human_a", "team": 0, "stage": 8, "credits": 3000, "ai": false, "start": Vector2i(8, 8)},
			{"slot": 1, "faction": "human_b", "team": 1, "stage": 8, "credits": 2000, "ai": false, "start": Vector2i(n - 9, n - 9),
				"stock": {"salvage": 77}}],
		"entities": [], "victory": {"victory": "hq_elimination"}, "regions": [], "triggers": []}


static func write(name: String, m: Dictionary, sc: Dictionary) -> String:
	var p := DIR.path_join(name)
	var err := MapIO.save(p, m, sc)
	assert(err == "", err)
	return p


func _codes(issues: Array) -> Array:
	var out := []
	for i in issues:
		out.append(String(i.code))
	return out


func test_mapio_save_read_round_trip_and_stable_bytes() -> void:
	var m := flat()
	m.terrain[20 * 48 + 20] = Terrain.WATER
	m.decor = [{"id": "hangar", "cell": Vector2i(30, 3), "size": Vector2i(3, 2)}]
	m.bridges = [{"id": 0, "name": "Span", "cells": [Vector2i(20, 20)], "state": "intact"}]
	var bio := PackedByteArray()
	bio.resize(48 * 48)
	bio.fill(2)
	bio[5] = 1
	m.biome = bio
	var sc := scenario()
	sc.entities = [{"kind": "building", "def": "barracks", "owner_slot": 0, "cell": Vector2i(14, 14), "built": true, "tag": "hq_b"},
		{"kind": "unit", "def": "rifleman", "owner_slot": 1, "pos": Vector2(30.25, 30.5), "facing": 1.5}]
	sc.regions = [{"id": "mid", "name": "Middle", "rect": Rect2i(20, 20, 8, 8)}]
	sc.triggers = [{"id": "t1", "when": {"type": "time_reached", "t": 5}, "then": [{"type": "message", "text": "hi"}]}]
	var p := write("rt.rtsmap", m, sc)
	var r := MapIO.read(p)
	if not check(not r.has("error"), "read error: %s" % r.get("error", "")):
		return
	check_eq(r.map.terrain, m.terrain, "terrain bytes round trip")
	check_eq(r.map.get("biome"), bio, "biome bytes round trip")
	check_eq(r.map.spawns, [Vector2i(8, 8), Vector2i(39, 39)], "spawns = player starts by slot")
	check_eq(r.map.resources, m.resources, "resources round trip")
	check_eq(r.map.decor[0].size, Vector2i(3, 2), "decor size")
	check_eq(r.map.bridge_cells, [Vector2i(20, 20)], "hold bridge cells")
	check_eq(r.map.regions[0].rect, Rect2i(20, 20, 8, 8), "region rect")
	check_eq(r.scenario.entities[0].cell, Vector2i(14, 14), "building cell")
	check_eq(r.scenario.entities[1].pos, Vector2(30.25, 30.5), "unit pos exact")
	check_eq(r.scenario.entities[0].tag, "hq_b", "tag kept")
	check_eq(r.scenario.players[1].stock, {"salvage": 77}, "player stock")
	check_eq(String(r.scenario.author), "MAPIO", "author")
	var p2 := write("rt2.rtsmap", r.map, r.scenario)
	check_eq(FileAccess.get_file_as_string(p2), FileAccess.get_file_as_string(p), "save(read(x)) is byte-identical")
	check(not FileAccess.file_exists(p + ".tmp"), "no tmp left")
	cleanup()


func test_mapio_read_rejects_bad_files() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var cases := {"garbage": "{not json", "fmt": '{"format":"x","version":1}', "ver": '{"format":"rtsmap","version":9,"w":4,"h":4}',
		"size": '{"format":"rtsmap","version":1,"w":4,"h":4,"terrain_b64":"AAAA"}'}
	for k in cases:
		var f := FileAccess.open(DIR.path_join(k), FileAccess.WRITE)
		f.store_string(cases[k])
		f.close()
		check(MapIO.read(DIR.path_join(k)).has("error"), "bad file '%s' rejected" % k)
	check(MapIO.read(DIR.path_join("missing.rtsmap")).has("error"), "missing file rejected")
	check(MapIO.save(DIR.path_join("x.rtsmap"), {"w": 0, "h": 4}, {}) != "", "bad map not saved")
	cleanup()


func test_mapio_export_every_builtin_round_trips() -> void:
	for id in MapGen.ids():
		var p := DIR.path_join("%s.rtsmap" % id)
		check_eq(MapGen.to_file(42, id, p), "", "%s exported" % id)
		var g := MapGen.generate(42, id)
		var r := MapIO.read(p)
		if not check(not r.has("error"), "%s read: %s" % [id, r.get("error", "")]):
			continue
		check_eq(r.map.terrain, g.terrain, "%s terrain identical" % id)
		check_eq(r.map.resources, g.resources, "%s resources identical" % id)
		check_eq(r.map.spawns, g.spawns, "%s spawns identical" % id)
		check_eq(r.map.spawn_sets, g.spawn_sets, "%s spawn sets identical" % id)
		check_eq(r.map.bridge_cells, g.get("bridge_cells", []), "%s hold bridge identical" % id)
		check_eq(r.map.bridges.size(), (g.bridges as Array).size(), "%s bridge count" % id)
		check_eq(r.map.decor.size(), (g.decor as Array).size(), "%s decor count" % id)
		check_eq(MapIO.validate(r.map, r.scenario), [], "%s export validates clean" % id)
	check_eq(MapGen.to_file(1, "nope", DIR.path_join("n.rtsmap")), "Unknown map 'nope'.", "unknown id refused")
	cleanup()


func test_mapio_file_match_matches_builtin_layout() -> void:
	var p := DIR.path_join("rc.rtsmap")
	MapGen.to_file(1337, "river_crossing_s", p)
	var c := MapIO.config_for(p, {"seed": 1337})
	if not check(not c.has("error"), "config_for: %s" % c.get("error", "")):
		return
	c.sides = c.sides.slice(0, 2)
	c.sides[1].ai = false
	var wf := SimWorld.new_match(c)
	var b := SimWorld.default_config()
	b.sides[1].ai = false
	var wb := SimWorld.new_match(b)
	if not check(wf != null and wb != null, "both worlds built"):
		return
	check_eq(wf.map.terrain, wb.map.terrain, "file terrain == built-in")
	check_eq(wf.factions[1].spawn, wb.factions[1].spawn, "side 1 spawn equal")
	check_eq(wf.entities.size(), wb.entities.size(), "same entity count (packages, piles, bridge)")
	check_eq(wf.buildings_of(0)[0].cell, wb.buildings_of(0)[0].cell, "HQ cell equal")
	cleanup()


func test_mapio_file_match_save_load_equal_hash() -> void:
	var m := flat()
	var sc := scenario()
	sc.entities = [{"kind": "unit", "def": "rifleman", "owner_slot": 0, "cell": Vector2i(20, 20), "tag": "vip"}]
	sc.regions = [{"id": "mid", "name": "Mid", "rect": Rect2i(18, 18, 10, 10)}]
	sc.triggers = [{"when": {"type": "unit_in_region", "region": "mid", "owner_slot": 0}, "then": [{"type": "grant", "slot": 0, "res": "credits", "amount": 100}]}]
	var p := write("hash.rtsmap", m, sc)
	var w := SimWorld.new_match(MapIO.config_for(p, {"seed": 9}))
	if not check(w != null, "file match built"):
		return
	w.run_ticks(120)
	var sp := DIR.path_join("hash.sav")
	check_eq(SaveSystem.save(w, sp), "", "saved")
	var l: SimWorld = SaveSystem.load(sp)
	if not check(l != null, "loaded"):
		return
	check_eq(l.state_hash(), w.state_hash(), "hash equal after load")
	w.run_ticks(80)
	l.run_ticks(80)
	check_eq(l.state_hash(), w.state_hash(), "hash equal after 80 more ticks")
	check_eq(int(w.sys_state.triggers.fired[0]), 1, "trigger fired in the file match")
	cleanup()


func test_mapio_validate_reports_each_problem() -> void:
	check_eq(MapIO.validate(flat(), scenario()), [], "clean flat map has no issues")
	var m := flat()
	for y in 48:
		m.terrain[y * 48 + 24] = Terrain.RIDGE   # wall splits the map
	for c in [Vector2i(30, 5), Vector2i(31, 5)]:
		m.terrain[c.y * 48 + c.x] = Terrain.WATER
	m.terrain[44 * 48 + 2] = Terrain.RIDGE
	var sc := scenario()
	sc.entities = [{"kind": "building", "def": "barracks", "owner_slot": 0, "cell": Vector2i(30, 4)},
		{"kind": "unit", "def": "rifleman", "owner_slot": 0, "cell": Vector2i(2, 44)},
		{"kind": "unit", "def": "rifleman", "owner_slot": 5, "cell": Vector2i(3, 3)},
		{"kind": "unit", "def": "no_such_unit", "owner_slot": 0, "cell": Vector2i(4, 4)},
		{"kind": "building", "def": "barracks", "owner_slot": 0, "cell": Vector2i(7, 7)}]
	sc.regions = [{"id": "r", "name": "r", "rect": Rect2i(40, 40, 20, 20)}]
	var issues := MapIO.validate(m, sc)
	var codes := _codes(issues)
	for want in ["start_unreachable", "resource_unreachable", "illegal_placement", "bad_owner", "unknown_def", "region_bad"]:
		check(codes.has(want), "reports %s (%s)" % [want, str(codes)])
	check_eq(codes.count("start_unreachable"), 2, "foot and vehicle both cut")
	check_eq(codes.count("illegal_placement"), 3, "water building, ridge unit, building on the start")
	for i in issues:
		check(i.has("code") and i.has("msg") and String(i.msg) != "", "issue has code + msg")
	var one := scenario()
	one.players = [one.players[0]]
	check(_codes(MapIO.validate(flat(), one)).has("player_count"), "1 player rejected")
	var blocked := flat()
	blocked.terrain[9 * 48 + 9] = Terrain.FOREST
	check(_codes(MapIO.validate(blocked, scenario())).has("start_blocked"), "forest in the HQ footprint")
	var mm := flat()
	mm.spawns = [Vector2i(8, 8), Vector2i(39, 39), Vector2i(8, 39)]
	check(_codes(MapIO.validate(mm, scenario())).has("player_count"), "3 starts vs 2 players")


func test_mapio_placed_entities_stock_cargo_no_packages() -> void:
	var sc := scenario(48, false)
	var carrier := "a_apc" if not Content.unit("a_apc").is_empty() else "b_carrier"
	sc.entities = [{"kind": "building", "def": "hq", "owner_slot": 0, "cell": Vector2i(6, 6)},
		{"kind": "building", "def": "barracks", "owner_slot": 0, "cell": Vector2i(14, 14), "built": false},
		{"kind": "unit", "def": carrier, "owner_slot": 0, "cell": Vector2i(20, 12), "facing": 1.25, "cargo": ["rifleman", "rifleman"]},
		{"kind": "building", "def": "b_works", "owner_slot": 1, "cell": Vector2i(37, 37), "tag": "base"},
		{"kind": "unit", "def": "b_militia", "owner_slot": 2, "cell": Vector2i(30, 30)}]
	var p := write("place.rtsmap", flat(), sc)
	var w := SimWorld.new_match(MapIO.config_for(p, {"seed": 4}))
	if not check(w != null, "built"):
		return
	check_eq(w.buildings_of(0).size(), 2, "slot 0: placed HQ + foundation, no start package")
	check(not bool(w.buildings_of(0, "barracks")[0].built), "built:false gives a foundation")
	check_eq(w.units_of(1).size(), 0, "slot 1: no start units")
	check_eq(int(w.factions[1].stock.salvage), 77, "player stock applied")
	var car: Dictionary = w.units_of(0)[0]
	check_eq(String(car.def), carrier, "carrier placed")
	check_eq(float(car.facing), 1.25, "facing kept")
	check_eq((car.get("cargo", []) as Array).size(), 2, "cargo inside the carrier dict")
	check_eq(int(w.factions[0].credits), 3000, "credits from the file")
	check_eq(String(w.buildings_of(1)[0].get("tag", "")), "base", "tag on entity")
	check_eq(w.sys_state.triggers.tags.base.ids, [int(w.buildings_of(1)[0].id)], "tag registry")
	cleanup()


## Task 7: every built-in map, 2 seeds, AI vs AI: the same hash twice; and its exported file too.
func test_mapio_seed_repeat_every_builtin_and_file() -> void:
	for id in MapGen.ids():
		for sd in [3, 11]:
			var hs := []
			for run in 2:
				var c := SimWorld.default_config()
				c.map = id
				c.seed = sd
				c.sides[0].ai = true
				var w := SimWorld.new_match(c)
				w.run_ticks(150)
				hs.append(w.state_hash())
			check_eq(hs[0], hs[1], "%s seed %d: same hash twice" % [id, sd])
			print("    seed-repeat %s seed %d: %s" % [id, sd, String(hs[0]).substr(0, 16)])
		var p := DIR.path_join("rep_%s.rtsmap" % id)
		MapGen.to_file(3, id, p)
		var fh := []
		for run in 2:
			var c := MapIO.config_for(p, {"seed": 3})
			c.sides = c.sides.slice(0, 2)
			var w := SimWorld.new_match(c)
			w.run_ticks(150)
			fh.append(w.state_hash())
		check_eq(fh[0], fh[1], "%s file map: same hash twice" % id)
	cleanup()
