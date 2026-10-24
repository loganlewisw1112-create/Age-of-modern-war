extends "res://tests/test_base.gd"
## G4a (THREAD): sim off the main thread + render snapshot (CONTRACTS_G4 section 4).
## - a recorded command stream gives the same state_hash threaded (WorkerThreadPool) and inline;
## - 2,000 ticks at ~2k units on the worker with the main thread reading snapshots meanwhile;
## - the snapshot matches world state for sampled ids;
## (MatchView itself needs a SceneTree, which the _init test runner lacks: it is covered by the
## windowed playtests / fps runs, which print SIM_THREAD / SIMTHREAD lines.)

const SimRunner = preload("res://presentation/view/sim_runner.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const TD = preload("res://tests/test_determinism.gd")


## Spawns n combat units split between fids 0 and 1 near their spawns, attack-moving across.
func _spawn_fight(w: SimWorld, n: int) -> void:
	var fids: Array = w.factions.keys()
	for side in 2:
		var fid: int = fids[side]
		var other: int = fids[1 - side]
		var defs: Array = []
		for e in w.units_of(fid):
			if not Content.unit(e.def).get("can_build", false) and not defs.has(String(e.def)):
				defs.append(String(e.def))
		if defs.is_empty():
			for e in w.units_of(fid):
				defs.append(String(e.def))
		var spawn := Vector2(w.factions[fid].spawn) + Vector2(0.5, 0.5)
		var toward := (Vector2(w.factions[other].spawn) - spawn).normalized()
		var base := spawn + toward * 9.0
		var ids := []
		var ring := 0
		while ids.size() < n / 2 and ring < 80:
			var cnt := maxi(1, ring * 6)
			for k in cnt:
				if ids.size() >= n / 2:
					break
				var ang := float(k) / float(cnt) * TAU
				var pos := base + Vector2(cos(ang), sin(ang)) * float(ring) * 0.9
				var c := Vector2i(floori(pos.x), floori(pos.y))
				var def: String = defs[ids.size() % defs.size()]
				var mc := String(Content.unit(def).get("move_class", "foot"))
				if w.in_bounds(c) and Terrain.passable(w.terrain_at(c), mc):
					ids.append(w.spawn_unit(def, fid, pos))
			ring += 1
		w.submit({"type": "attack_move", "issuer": fid, "unit_ids": ids, "target": Vector2(w.factions[other].spawn) + Vector2(0.5, 0.5)})


## Runs `ticks` steps through a SimRunner, feeding TD.drive's scripted commands between steps
## (the same hand-over point MatchView uses). Returns [hash per 100 ticks..., final hash].
func _run(threaded: bool, ticks: int, native: bool) -> Array:
	var w := make_world({"seed": 4242}, true)
	w.native_enabled = native
	var r = SimRunner.new()
	r.setup(w, threaded)
	var hashes: Array = []
	for t in ticks:
		for fid in w.factions:
			TD.drive(w, int(fid))
		r.start(1)
		r.join()
		if w.tick % 100 == 0:
			hashes.append(w.state_hash())
	hashes.append(w.state_hash())
	return hashes


func test_hash_threaded_equals_inline() -> void:
	var a := _run(false, 1200, true)
	var b := _run(true, 1200, true)
	check_eq(b, a, "threaded (native on) hash stream == inline")
	var c := _run(true, 600, false)
	var d := _run(false, 600, false)
	check_eq(c, d, "threaded (native off / fallback) hash stream == inline")
	print("THREAD_HASH native_on=%s native_off=%s" % [String(a[a.size() - 1]), String(d[d.size() - 1])])


## Commands queued while a step is in flight apply exactly like a submit between steps.
func test_queued_commands_match_inline() -> void:
	var out: Array = []
	for threaded in [false, true]:
		var w := make_world({"seed": 77})
		var r = SimRunner.new()
		r.setup(w, threaded)
		var ids: Array = []
		for e in w.units_of(0):
			ids.append(int(e.id))
		for t in 300:
			r.start(1)
			if t % 25 == 5:
				# while busy (threaded) this queues; inline it submits now -> same apply tick
				var res: Dictionary = r.submit({"type": "move", "issuer": 0, "unit_ids": ids, "target": Vector2(10 + t % 30, 12 + t % 20)})
				check(bool(res.ok), "submit ok")
			r.join()
		out.append(w.state_hash())
	check_eq(out[1], out[0], "queued-command run hash == inline run hash")


func test_2k_units_2000_ticks_threaded() -> void:
	var w := make_world({"seed": 9, "victory": "endless"}, true)
	_spawn_fight(w, 2000)
	var r = SimRunner.new()
	r.setup(w, true)
	var reads := 0
	var max_n := 0
	var snap_us: Array = []
	var t0 := Time.get_ticks_msec()
	# the main thread takes a snapshot ONLY at the hand-over (as MatchView does) and reads that
	# one while the worker steps: w.cache / w.render_snap themselves are sim-thread state
	var held: Dictionary = RenderSnap.latest(w)
	for t in 2000:
		r.start(1)
		while not r.finished():
			var s: Dictionary = held
			var pos: PackedVector2Array = s.get("pos", PackedVector2Array())
			var acc := Vector2.ZERO
			for i in range(0, pos.size(), 64):
				acc += pos[i]
			reads += 1
		var res: Dictionary = r.join()
		held = RenderSnap.latest(w)
		snap_us.append(int(res.get("snap_us", 0)))
		max_n = maxi(max_n, int(RenderSnap.latest(w).n))
		if bool(w.match_state.ended):
			break
	snap_us.sort()
	var med: int = snap_us[snap_us.size() / 2]
	print("THREAD_2K ticks=%d max_units=%d main_reads=%d wall_ms=%d snap_us_median=%d snap_us_p90=%d" % [w.tick, max_n, reads, Time.get_ticks_msec() - t0, med, snap_us[int(snap_us.size() * 0.9)]])
	check(w.tick >= 2000, "ran 2000 ticks (endless victory)")
	check(max_n >= 2000, "~2k units in the snapshot (got %d)" % max_n)


func test_snapshot_matches_world() -> void:
	var w := make_world({"seed": 5}, true)
	_spawn_fight(w, 2000)
	var r = SimRunner.new()
	r.setup(w, true)
	for t in 60:
		r.start(1)
		r.join()
	var sel: Array = []
	for e in w.units_of(0):
		if sel.size() < 3:
			sel.append(int(e.id))
	var b0: Dictionary = w.buildings_of(0)[0]
	sel.append(int(b0.id))
	RenderSnap.request(w, sel)
	r.start(1)
	r.join()
	var s: Dictionary = RenderSnap.latest(w)
	check_eq(int(s.tick), w.tick, "snapshot tick")
	var n_units := 0
	for id in w.entities:
		if w.entities[id].kind == "unit":
			n_units += 1
	check_eq(int(s.n), n_units, "unit count")
	var ids: PackedInt32Array = s.ids
	var bad := 0
	for i in range(0, ids.size(), 37):
		var e: Dictionary = w.entities[ids[i]]
		if (s.pos as PackedVector2Array)[i] != e.pos or int((s.owner as PackedInt32Array)[i]) != int(e.owner) \
				or String((s.defs as PackedStringArray)[(s.def as PackedInt32Array)[i]]) != String(e.def) \
				or absf((s.hp as PackedFloat32Array)[i] - float(e.hp) / float(e.max_hp)) > 0.001 \
				or absf((s.facing as PackedFloat32Array)[i] - float(e.facing)) > 0.001 \
				or (((s.flags as PackedInt32Array)[i] & RenderSnap.FLAG_MOVING) != 0) != bool(e.moving):
			bad += 1
	check_eq(bad, 0, "sampled units match world")
	var sb: Dictionary = s.statics.get(int(b0.id), {})
	check_eq(sb.get("built"), b0.built, "building built")
	check_eq(sb.get("cell"), b0.cell, "building cell")
	for id in sel:
		check_eq(s.detail.get(id), w.entities[id], "detail copy for %d" % id)
	check(s.detail.get(sel[0]) != null and not is_same(s.detail[sel[0]], w.entities[sel[0]]), "detail is a copy")
	check_eq(s.events, w.events, "this tick's events")
	check_eq(int(s.factions[0].credits), int(w.factions[0].credits), "top-bar credits")
	check_eq(s.fog[0].visible, w.fog[0].visible, "fog visible copy")
	# Cost: the brief's target is < 2 ms at 2k. Absolute times on the shared (loaded) machine are
	# reported, not asserted (CONTRACTS_G4 0.7: orchestrator takes final numbers on a quiet
	# machine); asserted is the ratio to the floor any GDScript snapshot pays: reading the 7
	# per-unit fields it needs from the entity dicts once.
	var us: Array = []
	var base: Array = []
	for k in 9:
		var t0 := Time.get_ticks_usec()
		RenderSnap.build(w)
		us.append(Time.get_ticks_usec() - t0)
		t0 = Time.get_ticks_usec()
		var acc := 0.0
		for id in w.entities:
			var e: Dictionary = w.entities[id]
			if e.kind == "unit":
				acc += float(e.facing) + float(e.hp) + float(e.max_hp) + float(e.owner) + (1.0 if e.moving else 0.0) + float(e.firing) + (e.pos as Vector2).x
		base.append(Time.get_ticks_usec() - t0)
	us.sort()
	base.sort()
	print("SNAP_BUILD units=%d statics=%d median_us=%d min_us=%d field_read_floor_us=%d target_2ms=%s" % [int(s.n), s.statics.size(), us[4], us[0], base[4], "MET" if int(us[4]) < 2000 else "NOT_MET"])
	check(float(us[4]) <= 2.0 * float(base[4]) + 300.0, "snapshot build <= 2x the field-read floor (%d vs %d us)" % [us[4], base[4]])
