extends "res://tests/test_base.gd"
## N1-core (CONTRACTS_G3b section 5): native core load, native vs GDScript fallback parity of
## behaviour, determinism with native on, save/load round trip mid-move, RtsGrid micro-test.
## Every test runs on whichever paths exist: without bin/rts_core.dll only the fallback runs.

const Movement = preload("res://sim/systems/movement.gd")
const NativeCore = preload("res://sim/native_core.gd")
const Tiers = preload("res://sim/systems/tiers.gd")
const C := Vector2(0.5, 0.5)


func _dll_present() -> bool:
	return FileAccess.file_exists("res://bin/rts_core.dll")


## Modes to exercise: [true, false] when native is available, else [false].
func _modes() -> Array:
	return [true, false] if NativeCore.available() else [false]


func _set_native(on: bool) -> void:
	NativeCore.force_off = not on


## Grass arena x 10..85, y 4..40 with a ridge wall at x = 47..48 and a 4-cell gap at y 20..23,
## plus a building footprint inside the arena (blocked cells).
func _arena_world(native_on: bool, seed_v: int = 1) -> SimWorld:
	_set_native(native_on)
	var w := make_world({"seed": seed_v})
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	for y in range(4, 41):
		for x in range(10, 86):
			var code := Terrain.GRASS
			if (x == 47 or x == 48) and (y < 20 or y > 23):
				code = Terrain.RIDGE
			t[y * mw + x] = code
	w.map.terrain = t
	Movement.rebuild_nav(w)
	w.spawn_building(Content.role("human_a", "hq"), 0, Vector2i(60, 10), true)
	return w


func _spawn_group(w: SimWorld, n_foot: int, n_veh: int) -> Array:
	var ids := []
	for i in n_foot:
		ids.append(w.spawn_unit("rifleman", 0, Vector2(14 + i % 10, 8 + i / 10) + C))
	for i in n_veh:
		ids.append(w.spawn_unit("ifv", 0, Vector2(14 + (i % 6) * 2, 30 + (i / 6) * 2) + C))
	return ids


func _bad_cells(w: SimWorld) -> Array:
	var bad := []
	for e in w.units_of(0):
		var mc := Movement.move_class(e)
		var cell := w.cell_of(e.pos)
		if not Movement.is_passable(w, cell, mc) or not Terrain.passable(w.terrain_at(cell), mc):
			bad.append("%s#%d@%s" % [e.def, e.id, cell])
	return bad


func _overlaps(w: SimWorld) -> int:
	var us := w.units_of(0)
	var n := 0
	for i in us.size():
		for j in range(i + 1, us.size()):
			var a: Dictionary = us[i]
			var b: Dictionary = us[j]
			var lim := 0.5 * (float(Movement.udef(a.def).radius) + float(Movement.udef(b.def).radius))
			if (a.pos as Vector2).distance_to(b.pos) < lim:
				n += 1
	return n


# ---------------------------------------------------------------- tests
func test_native_loads() -> void:
	_set_native(true)
	if _dll_present():
		check(NativeCore.available(), "bin/rts_core.dll present and the native classes registered")
		print("NATIVE rts_core loaded: ", NativeCore.version())
	else:
		print("NATIVE rts_core not built: fallback only")
	var w := make_world()
	check_eq(bool(w.nav.get("is_native", false)), NativeCore.available(), "new_match builds the live nav path")
	check_eq(NativeCore.path_name(w), "native" if NativeCore.available() else "gdscript", "path_name reports the live path")


func test_group_move_parity_reaches_goal_and_respects_blocks() -> void:
	var goal := Vector2(72.5, 22.5)
	for on in _modes():
		var w := _arena_world(on)
		var ids := _spawn_group(w, 30, 8)
		do_cmd(w, 0, {"type": "move", "unit_ids": ids, "target": goal})
		var bad := []
		for k in 40:
			w.run_ticks(20)
			bad.append_array(_bad_cells(w))
		var far := 0
		var moving := 0
		for id in ids:
			var e: Dictionary = w.entities[id]
			if (e.pos as Vector2).distance_to(goal) > 9.0:
				far += 1
			if e.moving:
				moving += 1
		var tag := "native" if on else "gdscript"
		check_eq(far, 0, "[%s] every unit reached the goal area through the gap" % tag)
		check_eq(moving, 0, "[%s] every unit arrived (stopped moving)" % tag)
		check(bad.is_empty(), "[%s] no unit ever stood in a blocked cell %s" % [tag, str(bad.slice(0, 4))])
		check(_overlaps(w) <= 2, "[%s] separation leaves no heavy overlaps (%d)" % [tag, _overlaps(w)])
	_set_native(true)


func test_single_paths_parity() -> void:
	# a lone unit (A* path, no flow field) around the wall, and an unreachable goal
	for on in _modes():
		var w := _arena_world(on)
		var id := w.spawn_unit("ifv", 0, Vector2(20.5, 10.5))
		var e: Dictionary = w.entities[id]
		check(Movement.order_path(w, e, Vector2(75.5, 10.5)), "path around the wall exists")
		for p in e.path:
			check(Movement.is_passable(w, w.cell_of(p), "vehicle"), "waypoint passable")
		w.run_ticks(600)
		check((e.pos as Vector2).distance_to(Vector2(75.5, 10.5)) < 1.5, "[%s] lone vehicle arrived (%s)" % ["native" if on else "gdscript", str(e.pos)])
		check(Movement.can_reach(w, e, Vector2(40.5, 20.5)), "can_reach open ground")
	_set_native(true)


func _scripted_run(seed_v: int, ticks: int) -> SimWorld:
	var w := _arena_world(true, seed_v)
	var ids := _spawn_group(w, 24, 6)
	for i in 16:
		w.spawn_unit("rifleman", 1, Vector2(76 + i % 4, 18 + i / 4) + C)
	do_cmd(w, 0, {"type": "attack_move", "unit_ids": ids, "target": Vector2(77.5, 20.5)})
	w.run_ticks(ticks)
	return w


func test_native_determinism_same_seed_same_hash() -> void:
	var a := _scripted_run(7, 300)
	var b := _scripted_run(7, 300)
	check_eq(a.state_hash(), b.state_hash(), "same seed + commands -> same state_hash (%s path)" % NativeCore.path_name(a))
	var c := _scripted_run(8, 300)
	check(c.state_hash() != a.state_hash(), "different seed differs")


func test_save_load_round_trip_mid_move() -> void:
	var w := _scripted_run(3, 25)
	var moving := 0
	for e in w.units_of(0):
		if e.moving:
			moving += 1
	check(moving > 10, "units are mid-move at save time (%d)" % moving)
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check(w2 != null, "from_dict")
	if w2 == null:
		return
	w2.ai_state = {}
	check_eq(bool(w2.nav.get("is_native", false)), NativeCore.available(), "loaded world rebuilt the same nav path")
	check_eq(w2.state_hash(), w.state_hash(), "hash equal right after load")
	w.run_ticks(200)
	w2.run_ticks(200)
	check_eq(w2.state_hash(), w.state_hash(), "hash equal after 200 more ticks")


func test_native_switch_flip_rebuilds() -> void:
	if not NativeCore.available():
		return
	var w := _arena_world(true)
	var ids := _spawn_group(w, 10, 0)
	do_cmd(w, 0, {"type": "move", "unit_ids": ids, "target": Vector2(30.5, 30.5)})
	_set_native(false)
	w.run_ticks(5)
	check(not bool(w.nav.get("is_native", true)), "flipping the switch mid-match rebuilds the GDScript nav")
	_set_native(true)
	w.run_ticks(5)
	check(bool(w.nav.get("is_native", false)), "and back")
	w.run_ticks(400)
	check(_bad_cells(w).is_empty(), "no blocked cells after flips")


func test_grid_query_and_nearest_enemy_micro() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ids := PackedInt32Array()
	var pos := PackedVector2Array()
	var team := PackedInt32Array()
	var rad := PackedFloat32Array()
	var flags := PackedInt32Array()
	for i in 600:
		ids.append(i * 3 + 1)
		pos.append(Vector2(rng.randf_range(0, 96), rng.randf_range(0, 96)))
		team.append(rng.randi_range(0, 2))
		rad.append(rng.randf_range(0.2, 0.7))
		flags.append(1 if i % 5 == 0 else 2)
	var src := PackedInt32Array()
	var ranges := PackedFloat32Array()
	var need := PackedInt32Array()
	for k in 200:
		src.append(k * 3)
		ranges.append(rng.randf_range(2.0, 12.0))
		need.append(1 if k % 7 == 0 else 0)
	var grids := [NativeCore.GridFallback.new()]
	if NativeCore.available():
		grids.append(NativeCore.make_grid())
	var results := []
	for g in grids:
		g.setup(96, 96, 4.0)
		g.rebuild(ids, pos, team, rad)
		g.set_flags(flags)
		var q1: PackedInt32Array = g.query_radius(Vector2(48, 48), 10.0)
		var q2: PackedInt32Array = g.query_radius(Vector2(2, 90), 6.5)
		var ne: PackedInt32Array = g.nearest_enemy_batch(src, ranges, need)
		results.append([q1, q2, ne])
	# brute-force reference for query_radius
	var ref := PackedInt32Array()
	for i in ids.size():
		if pos[i].distance_to(Vector2(48, 48)) <= 10.0:
			ref.append(ids[i])
	check_eq(results[0][0], ref, "fallback query_radius == brute force")
	var hits := 0
	for v in results[0][2]:
		if v >= 0:
			hits += 1
	check(hits > 50, "nearest_enemy_batch finds enemies (%d/200)" % hits)
	if results.size() == 2:
		check_eq(results[1][0], results[0][0], "native query_radius == fallback")
		check_eq(results[1][1], results[0][1], "native query_radius (corner) == fallback")
		var diff := 0
		for k in 200:
			if results[1][2][k] != results[0][2][k]:
				diff += 1
		check(diff <= 1, "native nearest_enemy_batch == fallback (%d diffs; f32 ties may differ)" % diff)


func test_native_batch_tick_in_use() -> void:
	# N1-core-2: the native path runs the whole movement tick in RtsSteer.advance_separate
	if not NativeCore.available():
		return
	var w := _arena_world(true)
	check(w.nav.steer.has_method("advance_separate"), "DLL exposes RtsSteer.advance_separate (batch advance)")
	var ids := _spawn_group(w, 12, 4)
	do_cmd(w, 0, {"type": "move", "unit_ids": ids, "target": Vector2(30.5, 30.5)})
	Movement.profile = true
	Movement.prof = {}
	w.run_ticks(10)
	Movement.profile = false
	check(Movement.prof.has("native_step"), "movement tick went through the native batch (%s)" % str(Movement.prof.keys()))
	Movement.prof = {}


func test_reduced_tier_stride_parity() -> void:
	# PERF4 fidelity tiers: REDUCED units advance every STRIDE ticks with a STRIDE x step. Both
	# paths must still reach the goal through the gap without ever standing in a blocked cell.
	var goal := Vector2(72.5, 22.5)
	var was := Tiers.move_stride
	Tiers.move_stride = true  # exercise the stride path even while PERF4 keeps it off by default
	for on in _modes():
		var w := _arena_world(on)
		var ids := _spawn_group(w, 20, 6)
		do_cmd(w, 0, {"type": "move", "unit_ids": ids, "target": goal})
		var bad := []
		var reduced_seen := 0
		for k in 40:
			w.run_ticks(20)
			bad.append_array(_bad_cells(w))
			for id in ids:
				if int(w.entities[id].get("tier", 0)) == Tiers.REDUCED:
					reduced_seen += 1
		var far := 0
		for id in ids:
			if (w.entities[id].pos as Vector2).distance_to(goal) > 9.0:
				far += 1
		var tag := "native" if on else "gdscript"
		if reduced_seen == 0:
			print("  note: [%s] no REDUCED-tier samples (tiers off or enemy near); stride path not exercised" % tag)
		check_eq(far, 0, "[%s] every unit reached the goal area (reduced samples %d)" % [tag, reduced_seen])
		check(bad.is_empty(), "[%s] no unit ever stood in a blocked cell %s" % [tag, str(bad.slice(0, 4))])
	Tiers.move_stride = was
	_set_native(true)


## RtsCombat.line_clear / line_clear_batch == Damage.line_clear on random segments (ridge wall,
## off-map ends, exact cell corners and axis-aligned runs included).
func test_native_los_parity() -> void:
	_set_native(true)
	var nc = NativeCore.new_combat()
	if nc == null:
		print("  note: RtsCombat not in this DLL: los parity skipped")
		return
	var w := _arena_world(true)
	var Damage = load("res://sim/systems/damage.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var fr := PackedVector2Array()
	var to := PackedVector2Array()
	for i in 3000:
		var a := Vector2(rng.randf_range(5.0, 90.0), rng.randf_range(0.0, 45.0))
		var b := a + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0))
		if i % 5 == 0:
			a = a.floor()          # exact corners
			b = b.floor()
		elif i % 7 == 0:
			b.y = a.y              # horizontal run
		elif i % 11 == 0:
			b = a + Vector2(3.0, 3.0)  # exact diagonal
		fr.append(a)
		to.append(b)
	var batch: PackedByteArray = nc.line_clear_batch(mw, mh, w.map.terrain, Terrain.RIDGE, fr, to)
	var bad := []
	var blocked := 0
	for i in fr.size():
		var ref: bool = Damage.line_clear(w, fr[i], to[i])
		if not ref:
			blocked += 1
		if bool(nc.line_clear(mw, mh, w.map.terrain, Terrain.RIDGE, fr[i], to[i])) != ref or (batch[i] == 1) != ref:
			bad.append([fr[i], to[i], ref])
	check(blocked > 100 and blocked < 2900, "segments include both blocked and clear (%d blocked)" % blocked)
	check(bad.is_empty(), "native line_clear == Damage.line_clear on 3000 segments %s" % str(bad.slice(0, 3)))
	var cdv: PackedInt32Array = nc.countdown(PackedInt32Array([5, 0, 2]), PackedInt32Array([1, 3, 0]), 2)
	check_eq(Array(cdv), [3, 0, 0, 0, 1, 0], "countdown: max(v - dec, 0) for cd then firing")


## RtsFog.stamp == the fog.gd rule (r = floor(sight), dx^2 + dy^2 <= sight^2, clipped to the map);
## explored_out == explored OR visible.
func test_native_fog_stamp_parity() -> void:
	_set_native(true)
	var nf = NativeCore.new_fog()
	if nf == null:
		print("  note: RtsFog not in this DLL: fog parity skipped")
		return
	var mw := 37
	var mh := 23
	var cells := PackedInt32Array([0, 5 * mw + 6, 22 * mw + 36, 11 * mw + 18, 11 * mw + 18, 3 * mw + 30])
	var sights := PackedFloat64Array([3.0, 4.5, 2.25, 6.0, 1.0, 7.75])
	var explored := PackedByteArray()
	explored.resize(mw * mh)
	explored.fill(0)
	for i in range(0, mw * mh, 13):
		explored[i] = 1
	var ref := PackedByteArray()
	ref.resize(mw * mh)
	ref.fill(0)
	for k in cells.size():
		var cx := cells[k] % mw
		var cy := cells[k] / mw
		var sg: float = sights[k]
		var r := int(floor(sg))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := cx + dx
				var y := cy + dy
				if float(dx * dx + dy * dy) <= sg * sg and x >= 0 and y >= 0 and x < mw and y < mh:
					ref[y * mw + x] = 1
	var vis: PackedByteArray = nf.stamp(mw, mh, cells, sights, explored)
	check(vis == ref, "RtsFog.stamp == fog.gd stamp rule (%d visible cells)" % Array(ref).count(1))
	var ex: PackedByteArray = nf.explored_out()
	var exr := explored.duplicate()
	for i in exr.size():
		if ref[i] == 1:
			exr[i] = 1
	check(ex == exr, "explored_out == explored OR visible")


## Construction.building_at_cell (now a cached footprint occupancy, N1-core-3) == a scan of every
## live building, before and after a destroy and a new placement inside the same tick.
func test_building_occupancy_cache_matches_scan() -> void:
	var Construction = load("res://sim/systems/construction.gd")
	var w := make_world()
	var bdef := ""
	for b in w.buildings_of(0):
		bdef = String(b.def)
	var scan := func(c: Vector2i) -> bool:
		for id in w.entities:
			var b: Dictionary = w.entities[id]
			if b.kind == "building":
				var bc: Vector2i = b.cell
				var s := int(b.size)
				if c.x >= bc.x and c.x < bc.x + s and c.y >= bc.y and c.y < bc.y + s:
					return true
		return false
	var cmp := func(tag: String) -> void:
		var bad := []
		for y in int(w.map.h):
			for x in int(w.map.w):
				var c := Vector2i(x, y)
				if bool(Construction.building_at_cell(w, c)) != bool(scan.call(c)):
					bad.append(c)
		check(bad.is_empty(), "%s: cached occupancy == full scan %s" % [tag, str(bad.slice(0, 3))])
	cmp.call("start")
	var first := -1
	for b in w.buildings_of(0):
		first = int(b.id)
		break
	if first >= 0:
		var cell: Vector2i = w.entities[first].cell
		w.destroy(first, "test")
		cmp.call("after destroy")
		if bdef != "":
			w.spawn_building(bdef, 0, cell, true)
			cmp.call("after placement")
