extends "res://tests/test_base.gd"
## G3b maps (owner: MAP4, docs/CONTRACTS_G3b.md section 4): maps.json <-> generators, all 3 maps
## validate for seeds 1-20 (foot + vehicle reachability between all spawns, resources reachable,
## symmetry, fairness, open ground), determinism, River Crossing bytes unchanged, 3/4-side starts,
## multi-bridge, territory at the new sizes, save round trip, AI-vs-AI 2000 ticks on the big maps.

const MapGen = preload("res://sim/map_gen.gd")
const Bridges = preload("res://sim/systems/bridges.gd")
const Territory = preload("res://sim/systems/territory.gd")
const Victory = preload("res://sim/systems/victory.gd")
const MapCheck = preload("res://sim/maps/map_check.gd")   # G6 (ELEV)
const MapUtil = preload("res://sim/maps/map_util.gd")

const BIG := ["industrial_heartland_m", "valley_conquest_l"]
## sha256 of River Crossing terrain bytes from the pre-G3b generator (git 7f3f604), computed by
## running that file side by side with this one (terrain, resources, bridge/ford cells all equal).
const RC_GOLDEN := {
	1: "0334e2244c63f627bd6ab0757c2bb894a3e186094630e0aeafec2f6c43bf72fc",
	2: "341aeda512c5e2e3cc333020f8da16291a330de863b8d3553b987a0e8e6dbe63",
	3: "c985a3fe8161bac0128f5cd75caa0e669b58b1281ccc2468d7b84fb8c9e38d7e",
	42: "096461953e5e7a122cbf8e3624d8ac58b990922aec3f6e7369dc7c7061f34ff1",
}


func _sha(b: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b)
	return ctx.finish().hex_encode()


func _side(f: String, team: int, ai := false) -> Dictionary:
	return {"faction": f, "team": team, "ai": ai, "stage": 8, "credits": 2500, "name": "%s %d" % [f, team]}


func _match(map_id: String, sides: Array, seed_value := 7) -> SimWorld:
	var c := SimWorld.default_config()
	c.map = map_id
	c.seed = seed_value
	c.sides = sides
	return SimWorld.new_match(c)


func test_maps_json_matches_generators() -> void:
	var defs := MapGen.defs()
	check_eq(defs.size(), 6, "maps.json lists 6 maps (G5: + coastal_front_m; G6 MODES6: + ridge_bastion_m, river_dam_m survival)")
	for id in MapGen.ids():
		check(defs.has(id), "maps.json has %s" % id)
		if not defs.has(id):
			continue
		var d: Dictionary = defs[id]
		var m := MapGen.generate(1, id)
		check_eq(String(m.id), id, "%s id" % id)
		check_eq([int(d.w), int(d.h)], [int(m.w), int(m.h)], "%s size" % id)
		var sp := []
		for s in m.spawns:
			sp.append([s.x, s.y])
		var jsp := []
		for s in d.spawns:
			jsp.append([int(s[0]), int(s[1])])
		check_eq(sp, jsp, "%s spawns match maps.json" % id)
		for k in ["2", "3", "4"]:
			var a := []
			for v in d.spawn_sets[k]:
				a.append(int(v))
			check_eq(a, m.spawn_sets[k], "%s spawn_sets[%s]" % [id, k])
		check_eq(int(d.max_sides), int(m.max_sides), "%s max_sides" % id)
		check_eq(int(d.hold_bridge), int(m.hold_bridge), "%s hold_bridge" % id)
		check_eq(int(d.bridges), (m.bridges as Array).size(), "%s bridge count" % id)
		check_eq(String(d.size), String(m.size), "%s size class" % id)
	check_eq([int(defs.industrial_heartland_m.w), int(defs.valley_conquest_l.w)], [160, 256], "160 and 256 wide")
	check_eq(MapGen.SPAWNS.size(), 4, "River Crossing keeps its 4 spawns")


func test_all_maps_validate_seeds_1_to_20() -> void:
	for id in MapGen.ids():
		var worst := 0
		for s in range(1, 21):
			var m := MapGen.generate(s, id)
			var r := MapGen.validate(m)
			check_eq(r, "", "%s seed %d validates" % [id, s])
			worst = maxi(worst, int(m.get("gen_attempt", 0)))
		print("    %s: seeds 1-20 valid, worst attempt index %d" % [id, worst])


func test_big_maps_requirements() -> void:
	for id in BIG:
		var m := MapGen.generate(3, id)
		check_eq(MapGen.validate(m), "", "%s validates" % id)
		var n := int(m.w) * int(m.h)
		var open := int(m.open_cells)
		print("    %s: open vehicle ground %d / %d cells (%.1f%%), fair2 %s fair3 %s fair4 %s, %d resources, %d decor" % [
			id, open, n, 100.0 * open / n, m.fair_2, m.fair_3, m.fair_4, (m.resources as Array).size(), (m.decor as Array).size()])
		var types := {}
		for p in m.pois:
			types[String(p.type)] = true
		for t in MapGen.defs()[id].pois:
			check(types.has(String(t)), "%s has POI %s" % [id, t])
		var crossings := (m.bridges as Array).size()
		check(crossings >= 2, "%s has >= 2 bridges" % id)
		check(not (m.ford_cells as Array).is_empty(), "%s has fords" % id)
	var v := MapGen.generate(3, "valley_conquest_l")
	check(int(v.open_cells) >= 40000, "valley: >= 40,000 open vehicle cells for 10,000 units (%d)" % int(v.open_cells))
	check_eq((v.spawns as Array).size(), 8, "valley: 8 spawns")
	check_eq((MapGen.generate(3, "industrial_heartland_m").spawns as Array).size(), 6, "heartland: 6 spawns")


func test_same_seed_same_bytes() -> void:
	for id in MapGen.ids():
		var a := MapGen.generate(5, id)
		var b := MapGen.generate(5, id)
		check_eq(_sha(a.terrain), _sha(b.terrain), "%s: same seed -> same terrain bytes" % id)
		check_eq(var_to_bytes(a.resources), var_to_bytes(b.resources), "%s: same seed -> same resources" % id)
		var c := MapGen.generate(6, id)
		check(_sha(a.terrain) != _sha(c.terrain), "%s: different seed varies terrain" % id)


func test_river_crossing_bytes_unchanged() -> void:
	for s in RC_GOLDEN:
		var m := MapGen.generate(int(s))
		check_eq(_sha(m.terrain), String(RC_GOLDEN[s]), "River Crossing seed %s terrain identical to pre-G3b" % s)
	var d := MapGen.generate(4)
	check_eq(String(d.id), "river_crossing_s", "default map id")
	check_eq((d.bridges as Array).size(), 1, "River Crossing: one bridge")
	check_eq(d.bridges[0].cells, d.bridge_cells, "bridge 0 == bridge_cells")


func test_3_and_4_side_starts_on_every_map() -> void:
	var f4 := ["human_a", "human_b", "machine", "human_a"]
	for id in MapGen.ids():
		for n in [3, 4]:
			var sides := []
			for i in n:
				sides.append(_side(f4[i], i))
			var w := _match(id, sides)
			if not check(w != null, "%s %d-side match created" % [id, n]):
				continue
			var seen := {}
			for i in n:
				var want: Vector2i = w.map.spawns[int(w.map.spawn_sets[str(n)][i])]
				check_eq(w.factions[i].spawn, want, "%s n=%d side %d uses its spawn_set cell" % [id, n, i])
				seen[w.factions[i].spawn] = true
				check(not w.buildings_of(i).is_empty(), "%s n=%d side %d has an HQ" % [id, n, i])
			check_eq(seen.size(), n, "%s n=%d distinct spawns" % [id, n])
			for t in 20:
				w.step()
			check_eq(w.tick, 20, "%s n=%d steps" % [id, n])


func test_multi_bridge_spawn_destroy_and_hold() -> void:
	var w := _match("industrial_heartland_m", [_side("human_a", 0), _side("human_b", 1)])
	if not check(w != null, "heartland match"):
		return
	var spans := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "structure" and String(e.def) == "bridge_span":
			spans[int(e.bridge_index)] = e
	check_eq(spans.size(), 2, "two bridge structures")
	var hold = Victory.bridge_entity(w)
	check(hold != null and int(hold.bridge_index) == 0, "hold-the-bridge uses bridge 0")
	check_eq(Victory.validate_rules({"map": "industrial_heartland_m", "seed": 7, "victory": "hold_bridge", "victory_params": {"seconds": 60}}), "", "hold_bridge valid on heartland")
	var east: Dictionary = spans[1]
	var cell: Vector2i = east.cells[0]
	w.destroy(int(east.id), "test", SimWorld.NEUTRAL)
	check_eq(String(east.state), "ruined", "east bridge ruined")
	check_eq(String(w.map.bridges[1].state), "ruined", "map.bridges[1] ruined")
	check_eq(String(w.map.bridge_state), "intact", "hold bridge state unchanged")
	check_eq(w.terrain_at(cell), Terrain.WATER, "ruined east cells are water")
	check(Bridges.any_ruined(w), "any_ruined sees the east bridge")
	w.destroy(int(spans[0].id), "test", SimWorld.NEUTRAL)
	check_eq(String(w.map.bridge_state), "ruined", "hold bridge ruined drives map.bridge_state")
	for t in 20:
		w.step()
	var l := SimWorld.from_dict(w.to_dict())
	check_eq(l.state_hash(), w.state_hash(), "save round trip with two ruined bridges")
	check_eq(String(l.map.bridges[1].state), "ruined", "ruin survives load")


func test_valley_dam_is_the_hold_bridge() -> void:
	var w := _match("valley_conquest_l", [_side("machine", 0), _side("human_a", 1)])
	if not check(w != null, "valley match"):
		return
	var n := 0
	for id in w.entities:
		if w.entities[id].kind == "structure":
			n += 1
	check_eq(n, 3, "dam + 2 bridges")
	var b = Victory.bridge_entity(w)
	check(b != null and int(b.bridge_index) == 0, "dam (bridge 0) is the hold bridge")
	var c: Vector2 = b.pos
	check(absf(c.x - 128.0) < 1.5 and absf(c.y - 128.0) < 1.5, "dam is at the map centre (%s)" % c)


func test_territory_at_new_sizes() -> void:
	for id in BIG:
		var w := _match(id, [_side("human_a", 0), _side("human_b", 1)])
		if not check(w != null, "%s match" % id):
			continue
		var st := Territory.state(w)
		var want := (int(w.map.w) + 11) / 12
		check_eq([int(st.cols), int(st.rows)], [want, want], "%s: %dx%d sectors" % [id, want, want])
		check(int(st.total) > want * want / 2, "%s: most sectors count (%d)" % [id, int(st.total)])
		Territory.recompute(w)
		check(Territory.percent(w, 0) >= 0.0, "%s: territory percent computes" % id)
		var far := Vector2(float(w.map.w) - 1.0, float(w.map.h) - 1.0)
		check_eq(Territory.sector_of(w, far), want * want - 1, "%s: last cell is in the last sector" % id)
		check_eq(Territory.sector_count(w), want * want, "%s: sector_count" % id)


func test_save_round_trip_big_map() -> void:
	var w := _match("industrial_heartland_m", [_side("human_a", 0, true), _side("machine", 1, true), _side("human_b", 2, true)])
	if not check(w != null, "3-side heartland"):
		return
	for t in 60:
		w.step()
	var l := SimWorld.from_dict(w.to_dict())
	check_eq(l.state_hash(), w.state_hash(), "heartland save round trip hash")
	for t in 40:
		w.step()
		l.step()
	check_eq(l.state_hash(), w.state_hash(), "loaded world stays in lockstep")


func test_ai_vs_ai_2000_ticks_on_big_maps() -> void:
	for id in BIG:
		var w := _match(id, [_side("human_a", 0, true), _side("machine", 1, true)], 11)
		if not check(w != null, "%s AI match" % id):
			continue
		var t0 := Time.get_ticks_msec()
		for t in 2000:
			w.step()
			if w.match_state.ended:
				break
		var units := 0
		for eid in w.entities:
			if w.entities[eid].kind == "unit":
				units += 1
		print("    %s: AI vs AI %d ticks in %d ms, %d units alive" % [id, w.tick, Time.get_ticks_msec() - t0, units])
		check(w.tick >= 2000 or w.match_state.ended, "%s ran 2000 ticks" % id)
		check(units > 0, "%s has units" % id)


## G6 (ELEV, CONTRACTS_G6 section 7.5): every built-in map carries valid, point-symmetric authored height,
## generated deterministically (same seed -> same height and ramps bytes).
func test_g6_builtin_height_symmetric_and_deterministic() -> void:
	for id in MapGen.ids():
		var a := MapGen.generate(5, id)
		var b := MapGen.generate(5, id)
		check(a.has("height") and a.has("ramps"), "%s has height + ramps" % id)
		if not a.has("height"):
			continue
		check_eq(_sha(a.height), _sha(b.height), "%s: same seed -> same height bytes" % id)
		check_eq(_sha(a.ramps), _sha(b.ramps), "%s: same seed -> same ramp bytes" % id)
		check_eq(MapCheck.height_issue(a, true), "", "%s: height valid and point-symmetric" % id)
		check_eq(MapGen.validate_height(a), [], "%s: validate_height clean" % id)


## G6 (ELEV, task 6): height noise + ramp placement + validation for generated / editor maps.
func test_g6_height_noise_and_validate_height() -> void:
	var base := MapGen.generate(3)
	base.erase("height")
	base.erase("ramps")
	check_eq(MapGen.validate_height(base), [], "flat map: no height issues")
	var m := base.duplicate(true)
	MapGen.add_height_noise(m, 11, {"symmetric": true})
	var hist := [0, 0, 0, 0]
	for i in (m.height as PackedByteArray).size():
		hist[int(m.height[i])] += 1
	check(hist[0] > 0 and hist[2] > 0 and hist[3] > 0, "noise uses valley, hill and ridge levels %s" % str(hist))
	check_eq(MapGen.validate_height(m), [], "noise map: validate_height clean (ramps join every spawn)")
	check_eq(MapCheck.height_issue(m, true), "", "symmetric noise stays point-symmetric")
	check_eq(MapGen.validate(m), "", "noise map passes the River Crossing validator")
	var m2 := base.duplicate(true)
	MapGen.add_height_noise(m2, 11, {"symmetric": true})
	check_eq(_sha(m2.height) + _sha(m2.ramps), _sha(m.height) + _sha(m.ramps), "same seed -> same noise")
	var m3 := base.duplicate(true)
	MapGen.add_height_noise(m3, 12, {"symmetric": true})
	check(_sha(m3.height) != _sha(m.height), "different seed -> different noise")
	# an editor-style mistake: wall spawn 0 in with a ridge ring and no ramps
	var bad := m.duplicate(true)
	var hg: PackedByteArray = bad.height
	var rp: PackedByteArray = bad.ramps
	var s0: Vector2i = bad.spawns[0]
	var w := int(bad.w)
	for y in int(bad.h):
		for x in w:
			var d := Vector2(x - s0.x, y - s0.y).length()
			if d >= 9.5 and d <= 13.5:
				hg[y * w + x] = 3 if d >= 10.5 and d <= 12.5 else 1
				rp[y * w + x] = 0
	MapUtil.prune_ramps(hg, rp, w, int(bad.h))   # editor brushes prune stale ramps after an edit
	bad.height = hg
	bad.ramps = rp
	var codes := []
	for it in MapGen.validate_height(bad):
		codes.append(String(it.code))
	check(codes.has("spawn_unreachable"), "walled-in start reported: %s" % str(codes))
	var odd := m.duplicate(true)
	var oh: PackedByteArray = odd.height
	oh[(s0.y + 1) * w + s0.x + 1] = 2
	odd.height = oh
	var c2 := []
	for it in MapGen.validate_height(odd):
		c2.append(String(it.code))
	check(c2.has("spawn_not_flat") or c2.has("height_invalid"), "mixed levels under a start reported: %s" % str(c2))
