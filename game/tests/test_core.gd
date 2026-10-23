extends "res://tests/test_base.gd"
## Core contracts owned by the orchestrator: config validation, map, ledger, IDs, hashing.

func test_default_match_starts_with_two_sides() -> void:
	var w := make_world()
	check(w != null, "new_match returned null")
	if w == null:
		return
	check_eq(w.factions.size(), 2, "side count")
	for fid in w.factions:
		check_eq(w.buildings_of(fid, "hq").size(), 1, "HQ for side %d" % fid)
		check_eq(w.units_of(fid).size(), 6, "start units for side %d" % fid)
		check_eq(w.factions[fid].stage, 8, "stage for side %d" % fid)


func test_invalid_configs_rejected_with_reason() -> void:
	var c := SimWorld.default_config()
	c.sides[0].stage = 7
	check(SimWorld.validate_config(c).contains("not playable"), "stage 7 must be rejected in slice")
	c = SimWorld.default_config()
	c.sides[0].stage = 14
	check(SimWorld.validate_config(c).contains("not a valid stage"), "stage 14 invalid ID")
	c = SimWorld.default_config()
	c.victory = "diplomacy"
	check(SimWorld.validate_config(c).contains("Unsupported victory"), "unsupported victory")
	c = SimWorld.default_config()
	c.sides[1].credits = -5
	check(SimWorld.validate_config(c).contains("negative"), "negative credits")


func test_stage_registry_has_exactly_13_ids() -> void:
	var ids := []
	for s in Content.stages():
		ids.append(int(s.id))
	check_eq(ids, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13], "stage ids 1..13")


func test_map_same_seed_identical_and_symmetric() -> void:
	var MapGen = load("res://sim/map_gen.gd")
	var a: Dictionary = MapGen.generate(42)
	var b: Dictionary = MapGen.generate(42)
	check_eq(a.terrain, b.terrain, "same seed -> same terrain")
	check_eq(MapGen.validate(a), "", "map validates")
	var c: Dictionary = MapGen.generate(43)
	check(a.terrain != c.terrain, "different seed varies terrain")
	var t: PackedByteArray = a.terrain
	var asym := 0
	for y in 96:
		for x in 96:
			if t[y * 96 + x] != t[(95 - y) * 96 + (95 - x)]:
				asym += 1
	check_eq(asym, 0, "point-symmetric terrain")
	check_eq(a.resources.size() % 2, 0, "resources mirrored in pairs")


func test_many_seeds_validate() -> void:
	var MapGen = load("res://sim/map_gen.gd")
	for s in range(1, 41):
		var m: Dictionary = MapGen.generate(s)
		check_eq(MapGen.validate(m), "", "seed %d validates" % s)


func test_ledger_spend_is_atomic() -> void:
	var w := make_world()
	var f: Dictionary = w.factions[0]
	var c0 := int(f.credits)
	var s0 := int(f.stock.salvage)
	check(not w.spend(0, {"credits": 1, "salvage": s0 + 1}, "test"), "overspend must fail")
	check_eq(int(f.credits), c0, "credits untouched after failed spend")
	check(w.spend(0, {"credits": 100, "salvage": 10}, "test"), "affordable spend")
	check_eq(int(f.credits), c0 - 100, "credits deducted once")
	check_eq(int(f.stock.salvage), s0 - 10, "salvage deducted once")


func test_state_hash_and_save_dict_roundtrip() -> void:
	var w := make_world()
	w.run_ticks(40)
	var h := w.state_hash()
	var bytes := var_to_bytes(w.to_dict())
	var w2 := SimWorld.from_dict(bytes_to_var(bytes))
	check(w2 != null, "from_dict")
	check_eq(w2.state_hash(), h, "hash survives var_to_bytes round trip")
	w.run_ticks(60)
	w2.run_ticks(60)
	check_eq(w2.state_hash(), w.state_hash(), "continued runs stay identical")


func test_unique_entity_ids() -> void:
	var w := make_world()
	var seen := {}
	for id in w.entities:
		check(not seen.has(id), "duplicate id %d" % id)
		seen[id] = true
		check_eq(int(w.entities[id].id), int(id), "entity id field matches key")
