extends "res://tests/test_base.gd"
## G7 acceptance (owner: FISSURE7). Master scope 13.9a: creep fissures, canyons and growths.
## Most tests run with fast rules (_fast) so a canyon opens in a few hundred ticks instead of ~10 minutes.

const Creep = preload("res://sim/systems/creep.gd")
const Fissures7 = preload("res://sim/systems/fissures7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const Damage = preload("res://sim/systems/damage.gd")
const NOFIRE := 100000
const H := 0
const M := 1

var _saved := {}


func _setup(creep: bool = true) -> SimWorld:
	var w := make_world({"victory": "endless", "sides": [
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 1}]})
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	t.fill(Terrain.GRASS)
	w.map.terrain = t
	w.map.erase("burnt")
	for id in w.entities.keys():
		w.entities.erase(id)
	w.cache.clear()
	if w.hot != null:
		HotState.sync(w)
	Movement.rebuild_nav(w)
	if creep:
		Creep.enable(w)
	return w


func _rule(path: String, v) -> void:
	var parts := path.split(".")
	var d: Dictionary = Content.rules().g7_fissures
	for i in parts.size() - 1:
		d = d[parts[i]]
	if not _saved.has(path):
		_saved[path] = d[parts[-1]]
	d[parts[-1]] = v


func _restore() -> void:
	for path in _saved:
		var parts := String(path).split(".")
		var d: Dictionary = Content.rules().g7_fissures
		for i in parts.size() - 1:
			d = d[parts[i]]
		d[parts[-1]] = _saved[path]
	_saved = {}


## Fast rules: cracks after ~3 visits, canyons ~10 s after a point is laid.
func _fast() -> void:
	_rule("age_stripes", 2)
	_rule("crack_age", 3)
	_rule("fissure_age", 4)
	_rule("canyon_age", 6)
	_rule("dense_v", 150)
	_rule("seed_chance", 1.0)
	_rule("seed_spacing_cells", 4)
	_rule("grow_every", 20)
	_rule("fissure_after_s", 3)
	_rule("canyon_after_s", 8)
	_rule("commit_every", 20)
	_rule("close_after_s", 10)
	_rule("max_len", 30)
	_rule("max_len_jitter", 10)


func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].order = {"type": "hold"}
	w.entities[id].cd_ticks = NOFIRE
	return id


func _run(w: SimWorld, n: int, types: Array = []) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.is_empty() or types.has(String(ev.type)):
				out.append(ev)
	return out


func _mid(w: SimWorld) -> Vector2i:
	return Vector2i(int(w.map.w) / 2, int(w.map.h) / 2)


## A Machine hive at the map centre and n ticks of creep (fast rules on).
func _crept(n: int = 900) -> SimWorld:
	_fast()
	var w := _setup()
	w.spawn_building("m_hive_node", M, _mid(w), true)
	_run(w, n)
	return w


func _first_tile(w: SimWorld, stage: int) -> Vector2i:
	var s = Fissures7.st(w)
	var ts: PackedByteArray = s.ts
	var mw := int(w.map.w)
	for i in ts.size():
		if ts[i] & 7 == stage and ts[i] & 16 == 0:
			return Vector2i(i % mw, i / mw)
	return Vector2i(-1, -1)


# ================================================================ stages
func test_cracks_fissures_canyons_with_age() -> void:
	_fast()
	var w := _setup()
	w.spawn_building("m_hive_node", M, _mid(w), true)
	var seen := {"crack": -1, "fissure": -1, "canyon": -1}
	for i in 40:
		_run(w, 50)
		var c := Fissures7.counts(w)
		for k in seen:
			if seen[k] < 0 and int(c[k]) > 0:
				seen[k] = w.tick
	var c := Fissures7.counts(w)
	print("FISSURE7_STAGES first_tick crack=%d fissure=%d canyon=%d counts=%s" % [seen.crack, seen.fissure, seen.canyon, c])
	check(seen.crack > 0 and seen.fissure > 0 and seen.canyon > 0, "creep cracks, then fissures, then canyons open")
	check(seen.crack <= seen.fissure and seen.fissure <= seen.canyon, "stages open in order crack -> fissure -> canyon")
	check(int(c.veins) >= 3, "several veins (%d), branching networks not one blob" % int(c.veins))
	# lines, not blobs: openings are long and thin (points >> width) and some branch
	var deep := 0
	for vn in Fissures7.st(w).veins:
		if int(vn.d) > 0:
			deep += 1
	check(deep > 0, "veins branch (%d branches)" % deep)
	check(int(c.points) >= 30, "veins grow long lines (%d points)" % int(c.points))
	# terrain codes follow the stages
	var ct := _first_tile(w, 1)
	var ft := _first_tile(w, 2)
	var kt := _first_tile(w, 3)
	check_eq(w.terrain_at(ct), Terrain.FORD, "crack tiles are slow ground")
	check_eq(w.terrain_at(ft), Terrain.FOREST, "fissure tiles block vehicles")
	check_eq(w.terrain_at(kt), Terrain.CHASM, "canyon tiles are CHASM (all ground blocked, fire passes)")
	_restore()


func test_stage_movement_rules() -> void:
	var w := _crept(1600)
	var ct := _first_tile(w, 1)
	var ft := _first_tile(w, 2)
	var kt := _first_tile(w, 3)
	check(ct.x >= 0 and ft.x >= 0 and kt.x >= 0, "all three stages present")
	check(Movement.is_passable(w, ct, "foot") and Movement.is_passable(w, ct, "vehicle"), "crack: ground passes")
	check(Terrain.speed_mult(w.terrain_at(ct), "vehicle") < 1.0 and Terrain.speed_mult(w.terrain_at(ct), "foot") < 1.0,
		"crack: ground is slowed")
	check(Movement.is_passable(w, ft, "foot") and not Movement.is_passable(w, ft, "vehicle"),
		"fissure: infantry climb across, vehicles blocked")
	check(Terrain.speed_mult(w.terrain_at(ft), "foot") < 1.0, "fissure: infantry slowed crossing")
	check(not Movement.is_passable(w, kt, "foot") and not Movement.is_passable(w, kt, "vehicle")
		and not Movement.is_passable(w, kt, "hover"), "canyon: all ground blocked")
	check(Movement.is_passable(w, kt, "air") and Movement.is_passable(w, ft, "air_low"), "air unaffected")
	# G7 LPPERF7 (CR 711): canyons are CHASM: every ground class blocked, line of fire / sight across stays open
	check_eq(w.terrain_at(kt), Terrain.CHASM, "canyon tile is CHASM")
	for mc in ["foot", "vehicle", "amphibious", "hover", "rail", "naval", "naval_small"]:
		check(not Movement.is_passable(w, kt, mc), "canyon blocks %s" % mc)
	check(Damage.line_clear(w, Vector2(kt) + Vector2(-2.5, 0.5), Vector2(kt) + Vector2(3.5, 0.5))
		or w.terrain_at(kt + Vector2i(-2, 0)) == Terrain.RIDGE or w.terrain_at(kt + Vector2i(3, 0)) == Terrain.RIDGE,
		"line of fire passes across a canyon tile")
	_restore()


## G7 LPPERF7 (FISSURE7 CR 711): a CHASM strip across the whole map. No ground unit gets across (rules + a real move
## order), line of fire crosses it (Damage.line_clear and a real shot), and RIDGE in the same place blocks the shot.
func test_chasm_blocks_ground_not_fire() -> void:
	var w := _setup(false)
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var cx := mw / 2
	var t: PackedByteArray = w.map.terrain
	for y in mh:
		for dx in 3:
			t[y * mw + cx - 1 + dx] = Terrain.CHASM
	w.map.terrain = t
	Movement.on_terrain_changed(w)
	var c := Vector2i(cx, 20)
	for mc in Terrain.CLASSES:
		if Terrain.is_air(mc):
			check(Movement.is_passable(w, c, mc), "CHASM: %s passes" % mc)
		else:
			check(not Movement.is_passable(w, c, mc), "CHASM: %s blocked" % mc)
			check_eq(Terrain.speed_mult(Terrain.CHASM, mc), 0.0, "CHASM: %s speed 0" % mc)
	check(not Terrain.blocks_los(Terrain.CHASM), "CHASM does not block line of sight / fire")
	check(not Terrain.buildable(Terrain.CHASM), "CHASM is not buildable")
	check_eq(String(Terrain.NAMES[Terrain.CHASM]), "chasm", "CHASM has a name")
	var a := Vector2(cx - 2.5, 20.5)
	var b := Vector2(cx + 3.5, 20.5)
	check(Damage.line_clear(w, a, b), "line of fire crosses the chasm")
	# ground units ordered across never cross
	var tank := _unit(w, "mbt", H, Vector2(cx - 6.5, 30.5))
	var eng := _unit(w, "engineer", H, Vector2(cx - 6.5, 32.5))
	w.submit({"type": "move", "issuer": H, "unit_ids": [tank, eng], "target": Vector2(cx + 6.5, 31.5)})
	_run(w, 400)
	check(float(w.entities[tank].pos.x) < float(cx - 1), "tank stays on its side (x %.1f)" % float(w.entities[tank].pos.x))
	check(float(w.entities[eng].pos.x) < float(cx - 1), "infantry stays on its side (x %.1f)" % float(w.entities[eng].pos.x))
	# a real shot across
	var sh := _unit(w, "mbt", H, a)
	var tg := _unit(w, "mbt", M, b)
	w.entities[sh].cd_ticks = 0
	w.entities[sh].order = {"type": "attack", "target_id": tg}
	var hp0 := float(w.entities[tg].hp)
	_run(w, 120)
	check(not w.entities.has(tg) or float(w.entities[tg].hp) < hp0, "a tank hits a target across the chasm")
	# the same strip as RIDGE blocks the line of fire (the old canyon code)
	t = w.map.terrain
	for y in mh:
		for dx in 3:
			t[y * mw + cx - 1 + dx] = Terrain.RIDGE
	w.map.terrain = t
	Movement.on_terrain_changed(w)
	check(not Damage.line_clear(w, a, b), "RIDGE in the same place blocks the line of fire")


## G7 LPPERF7 (CR 755): nav signature for the equivalence test: solid bytes + components of four classes and the
## paths order_path gives two units to three goals.
func _nav_sig(w: SimWorld, units: Array, goals: Array) -> Dictionary:
	var out := {}
	for mc in ["foot", "vehicle", "naval", "hover"]:
		out["solid_" + mc] = Movement._solid_of(w, mc).duplicate()
		out["comp_" + mc] = Movement._comp(w, mc).duplicate()
	for u in units:
		var e: Dictionary = w.entities[u]
		for g in goals:
			Movement.order_path(w, e, g)
			out["path_%d_%s" % [u, str(g)]] = (e.path as Array).duplicate()
			Movement.stop_path(e)
	return out


## G7 LPPERF7 (FISSURE7 CR 755): Movement.on_cells_changed gives the same nav as a full rebuild_nav (native and
## GDScript nav), including a cell cut out of a naval channel, wall footprints and the classes built on demand.
func test_cells_changed_equals_full_rebuild() -> void:
	for nat in [true, false]:
		var w := _setup(false)
		w.set("native_enabled", nat)
		var mw := int(w.map.w)
		var mh := int(w.map.h)
		var t: PackedByteArray = w.map.terrain
		for y in range(4, mh - 4):
			for x in range(30, 37):
				t[y * mw + x] = Terrain.WATER
		w.map.terrain = t
		Movement.rebuild_nav(w)
		for y in range(5, 15):
			w.spawn_building("a_wall", H, Vector2i(10, y), true)
		var u1 := _unit(w, "mbt", H, Vector2(5.5, 20.5))
		var u2 := _unit(w, "engineer", H, Vector2(6.5, 22.5))
		var goals := [Vector2(20.5, 8.5), Vector2(45.5, 20.5), Vector2(14.5, 30.5)]
		_nav_sig(w, [u1, u2], goals)   # builds naval / hover so they are kept classes
		var cells := []
		var codes := [Terrain.CHASM, Terrain.FOREST, Terrain.FORD, Terrain.DIRT, Terrain.CHASM]
		t = w.map.terrain
		for k in 160:
			var i := (k * 7919 + 13) % (mw * mh)
			t[i] = codes[k % codes.size()]
			cells.append(i)
		for y in range(10, 20):
			t[y * mw + 33] = Terrain.CHASM   # cut the channel
			cells.append(y * mw + 33)
		w.map.terrain = t
		Movement.on_cells_changed(w, cells)
		var a := _nav_sig(w, [u1, u2], goals)
		Movement.rebuild_nav(w)
		var b := _nav_sig(w, [u1, u2], goals)
		var same := 0
		for k in b:
			if check(a.has(k) and a[k] == b[k], "native=%s %s: on_cells_changed == rebuild_nav" % [nat, k]):
				same += 1
		check_eq(same, b.size(), "native=%s every nav part equal (%d)" % [nat, b.size()])
		check(not Movement.is_passable(w, Vector2i(33, 12), "naval"), "native=%s chasm cell cuts the channel" % nat)


# ================================================================ protection
func test_never_under_buildings_bridges_barriers() -> void:
	_fast()
	var w := _setup()
	var c := _mid(w)
	var mw := int(w.map.w)
	w.spawn_building("m_hive_node", M, c, true)
	# a human building, a bridge row and a barrier line inside the creep
	var bid := w.spawn_building("depot", H, c + Vector2i(-10, 6), true)
	var t: PackedByteArray = w.map.terrain
	for x in range(c.x + 4, c.x + 20):
		t[(c.y - 8) * mw + x] = Terrain.BRIDGE
	w.map.terrain = t
	Movement.on_terrain_changed(w)
	Creep.purge(w, Vector2(c) + Vector2(0, 14), 12.0, "barrier", H, Vector2(1, 0))
	_run(w, 2000)
	var s = Fissures7.st(w)
	check(s != null and Fissures7.counts(w).canyon > 0, "canyons opened around the protected ground")
	var b: Dictionary = w.entities[bid]
	var bad := 0
	var near := 0
	for y in range(b.cell.y - 1, b.cell.y + int(b.size) + 1):
		for x in range(b.cell.x - 1, b.cell.x + int(b.size) + 1):
			var st := Fissures7.stage_at(w, Vector2i(x, y))
			var inside := Rect2i(b.cell, Vector2i(int(b.size), int(b.size))).has_point(Vector2i(x, y))
			if inside and st != 0:
				bad += 1
			elif not inside and st >= 2:
				near += 1
	check_eq(bad, 0, "nothing opens under a building")
	check_eq(near, 0, "fissures and canyons keep a tile off buildings")
	var br := 0
	for x in range(c.x + 4, c.x + 20):
		if w.terrain_at(Vector2i(x, c.y - 8)) != Terrain.BRIDGE:
			br += 1
		for dy in [-1, 1]:
			if Fissures7.stage_at(w, Vector2i(x, c.y - 8 + dy)) >= 2:
				br += 1
	check_eq(br, 0, "bridges stay bridges and nothing deeper than a crack opens next to them")
	var ts: PackedByteArray = s.ts
	var cst = w.sys_state.creep
	var on_barrier := 0
	for i in ts.size():
		if ts[i] & 7 == 0:
			continue
		var x := i % mw
		var y := i / mw
		if int((cst.fl as PackedByteArray)[(y / int(cst.cs)) * int(cst.cw) + x / int(cst.cs)]) & (1 | 8) != 0 \
				and ts[i] & 16 == 0:
			on_barrier += 1
	check_eq(on_barrier, 0, "nothing opens on sterile or barrier ground")
	_restore()


func test_base_never_cut_off() -> void:
	_fast()
	_rule("connect_r", 30)   # the check radius (110 on the 512 map) scaled to the small test map
	var w := _setup()
	var mw := int(w.map.w)
	var c := _mid(w)
	# a base walled in by rock (RIDGE ring of radius 14) with a single 3-tile gap on its east side
	var hq := w.spawn_building("depot", H, c, true)
	var t: PackedByteArray = w.map.terrain
	for y in range(c.y - 14, c.y + 15):
		for x in range(c.x - 14, c.x + 15):
			var d := Vector2(x - c.x, y - c.y).length()
			if d >= 13.5 and d < 14.5 and not (x > c.x + 10 and absi(y - c.y) <= 1):
				t[y * mw + x] = Terrain.RIDGE
	w.map.terrain = t
	Movement.on_terrain_changed(w)
	var cst := Creep.enable(w)
	cst.on_n = 1
	var s := Fissures7._enable(w, cst)
	# a canyon about to fill the gap (and a far canyon elsewhere that is fine)
	var pend: Dictionary = s.pend
	for y in range(c.y - 3, c.y + 4):
		for x in range(c.x + 12, c.x + 17):
			pend[y * mw + x] = 3
	var far := Vector2i(6, 6)
	pend[far.y * mw + far.x] = 3
	var a: Dictionary = Fissures7._anchors(w)[0]
	check(Fissures7._escapes(w, a, pend, false, Fissures7.R()), "the base reaches the map before the canyon")
	check(not Fissures7._escapes(w, a, pend, true, Fissures7.R()), "the pending canyon would seal the gap")
	Fissures7._commit(w, s, Fissures7.R())
	var gap := Vector2i(c.x + 14, c.y)
	check(Movement.is_passable(w, gap, "vehicle", 0), "the gap stays open for vehicles (held at crack)")
	check_eq(Fissures7.stage_at(w, gap), 1, "the held tile is a crack")
	check(int(s.rejects) >= 1, "the connectivity check rejected the batch near the base")
	check_eq(Fissures7.stage_at(w, far), 3, "a canyon far from the base still opens")
	check(Fissures7._escapes(w, Fissures7._anchors(w)[0], {}, false, Fissures7.R()), "the base still reaches the map")
	check(w.entities.has(hq), "base intact")
	_restore()


# ================================================================ fighting it
func test_purge_stops_growth_kills_growths_and_scar_closes() -> void:
	_fast()
	_rule("big.every", 1)
	_rule("big.spacing", 3)
	var w := _setup()
	var c := _mid(w)
	w.spawn_building("m_hive_node", M, c, true)
	_run(w, 1600)
	var s = Fissures7.st(w)
	check(not (s.big as Array).is_empty(), "big growths rose from the canyons (%d)" % (s.big as Array).size())
	var g: Dictionary = s.big[0]
	var gp := Vector2(int(g.x) + 0.5, int(g.y) + 0.5)
	check(w.entities.has(int(g.id)) and int(w.entities[int(g.id)].owner) == M, "big growth is a Machine entity")
	check(Creep.on_creep(w, Vector2i(int(g.x), int(g.y))), "big growth sits on creep (it is a creep source)")
	var kt := _first_tile(w, 3)
	var evs := _run(w, 1, [])
	Creep.purge(w, Vector2(kt) + Vector2(0.5, 0.5), 10.0, "standard", H)
	Creep.purge(w, gp, 6.0, "standard", H)
	check(not w.entities.has(int(g.id)), "purging kills the big growth")
	check(Fissures7.is_scar(w, kt), "purged canyon is scarred")
	var before := Fissures7.stage_at(w, kt)
	_run(w, 200)
	check_eq(Fissures7.stage_at(w, kt), before, "scarred opening stops growing")
	var stopped := true
	for vn in s.veins:
		if bool(vn.alive) and Vector2(float(vn.tx), float(vn.ty)).distance_to(Vector2(kt)) < 9.0:
			stopped = false
	check(stopped, "no live vein tip inside the purge")
	_run(w, 200)
	check_eq(Fissures7.stage_at(w, kt), 0, "after close_after_s the scar closes")
	check_eq(w.terrain_at(kt), Terrain.DIRT, "closed back to rough ground")
	check(Movement.is_passable(w, kt, "vehicle"), "closed ground is passable again")
	_restore()


func test_engineer_span() -> void:
	var w := _crept(1600)
	var s = Fissures7.st(w)
	var plan := {}
	var cell := Vector2i(-1, -1)
	var ts: PackedByteArray = s.ts
	var mw := int(w.map.w)
	for i in ts.size():
		if ts[i] & 7 == 3 and ts[i] & 16 == 0:
			plan = Fissures7.span_plan(w, Vector2i(i % mw, i / mw))
			if not plan.is_empty():
				cell = Vector2i(i % mw, i / mw)
				break
	check(not plan.is_empty(), "a canyon can be spanned")
	var a: Vector2i = plan.a
	var b: Vector2i = plan.b
	check(Movement.is_passable(w, a, "foot") and Movement.is_passable(w, b, "foot"), "both banks are ground")
	var eng := _unit(w, "engineer", H, Vector2(a) + Vector2(0.5, 0.5))
	var tank := _unit(w, "mbt", H, Vector2(2.5, 2.5))
	var bad := {"type": "fissure_span", "issuer": H, "unit_ids": [tank], "cell": cell}
	check(Fissures7.validate_command(w, bad) != "", "only engineers lay spans")
	var cmd := {"type": "fissure_span", "issuer": H, "unit_ids": [eng], "cell": cell}
	check_eq(Fissures7.validate_command(w, cmd), "", "engineer span command valid")
	Fissures7.apply_command(w, cmd)
	w.entities[eng].order = {"type": "hold"}
	Movement.stop_path(w.entities[eng])
	w.entities[eng].pos = Vector2(a) + Vector2(0.5, 0.5)
	HotState.touch(w, eng)
	var evs := _run(w, 1200, ["FissureSpanned"])
	check_eq(evs.size(), 1, "the engineer finished the span")
	var all_bridge := true
	for i in plan.tiles:
		if w.terrain_at(Vector2i(int(i) % mw, int(i) / mw)) != Terrain.BRIDGE:
			all_bridge = false
	check(all_bridge, "span tiles are bridge ground")
	check(Movement.is_passable(w, cell, "vehicle"), "vehicles cross the canyon on the span")
	_restore()


# ================================================================ big growth: destructible, feeds the spread
func test_big_growth_destructible_and_feeds() -> void:
	_fast()
	_rule("big.every", 1)
	_rule("big.spacing", 3)
	var w := _setup()
	var c := _mid(w)
	w.spawn_building("m_hive_node", M, c, true)
	_run(w, 1600)
	var s = Fissures7.st(w)
	check(not (s.big as Array).is_empty(), "a big growth exists")
	var g: Dictionary = s.big[0]
	var id := int(g.id)
	# feeds the spread: Creep counts every Machine building as a source
	var src: Dictionary = Creep._sources(w, w.sys_state.creep).src
	var cst = w.sys_state.creep
	var k := (int(g.y) / int(cst.cs)) * int(cst.cw) + int(g.x) / int(cst.cs)
	check(src.has(k), "big growth is a creep source")
	# feeds the cracking: cells next to it age faster than the same rules without it
	var age0 := int((s.age as PackedByteArray)[k])
	_run(w, 40)
	check(int((s.age as PackedByteArray)[k]) >= mini(age0 + 2, 255), "creep around a big growth ages faster")
	# destructible: damage it to zero through the normal damage path
	var e: Dictionary = w.entities[id]
	check(e.kind == "building" and float(e.max_hp) > 0.0, "big growth has hit points")
	HotState.set_hp(w, id, 1.0)
	var gp := Vector2(int(g.x), int(g.y)) + Vector2(0.5, 0.5)
	var spot := Vector2(-1, -1)
	for rad in range(3, 9):
		for q in 16:
			var p := gp + Vector2.RIGHT.rotated(TAU * q / 16.0) * rad
			if Movement.is_passable(w, w.cell_of(p), "vehicle") and Damage.line_clear(w, p, gp):
				spot = Vector2(w.cell_of(p)) + Vector2(0.5, 0.5)
				break
		if spot.x >= 0:
			break
	check(spot.x >= 0, "the growth on the canyon rim is in line of sight from open ground")
	var t := _unit(w, "mbt", H, spot)
	w.entities[t].cd_ticks = 0
	w.entities[t].order = {"type": "attack", "target_id": id}
	_run(w, 200)
	check(not w.entities.has(id), "big growth is destroyed by fire")
	_run(w, 20)
	check(not (Fissures7.st(w).big as Array).has(g), "destroyed growth leaves the list")
	_restore()


# ================================================================ determinism
func test_same_seed_same_hash_and_save_roundtrip() -> void:
	_fast()
	var a := _setup()
	var b := _setup()
	a.spawn_building("m_hive_node", M, _mid(a), true)
	b.spawn_building("m_hive_node", M, _mid(b), true)
	_run(a, 900)
	_run(b, 900)
	check(Fissures7.counts(a).fissure > 0, "fissures open in the hash scenario")
	check_eq(a.state_hash(), b.state_hash(), "same seed = same hash with fissures")
	var c2 := SimWorld.from_dict(a.to_dict().duplicate(true))
	check_eq(c2.state_hash(), a.state_hash(), "save round-trip keeps the hash")
	_run(a, 300)
	_run(c2, 300)
	check_eq(c2.state_hash(), a.state_hash(), "a loaded match continues identically")
	_restore()


func test_match_without_creep_untouched() -> void:
	var w := make_world()
	_run(w, 300)
	check(not w.sys_state.has("fissures7"), "a match without creep never creates fissure state")
	var wm := _setup(false)
	wm.spawn_building("m_hive_node", M, _mid(wm), true)
	_run(wm, 300)
	check(not wm.sys_state.has("fissures7") and not wm.sys_state.has("creep"), "Machine match without creep: no fissures")
	check(not Content.rules().g7_fissures.is_empty(), "rules loaded from content/g7/defs_g7_fissures.json")
	check(not Content.building("g7_growth_spire").is_empty() and not Content.building("g7_growth_heart").is_empty(),
		"big growth defs registered")


## Cost on a fully crept 512 x 512 map at a late-run creep age (every cell pre-aged to 150, so veins start
## everywhere at once: worse than a real run). Reports FISSURE7_COST (shared PC, not a gate number).
func test_cost_512_late_creep() -> void:
	var w := _setup(false)
	var mp: Dictionary = w.map.duplicate()
	mp.w = 512
	mp.h = 512
	var t := PackedByteArray()
	t.resize(512 * 512)
	t.fill(Terrain.GRASS)
	mp.terrain = t
	mp.erase("burnt")
	w.map = mp
	Movement.rebuild_nav(w)
	Creep.enable(w)
	for y in 8:
		for x in 8:
			Creep.add_seed(w, Vector2(32 + x * 64, 32 + y * 64), "nest", M)
	_rule("every", 1000000000)
	for i in 2600:
		w.tick += 1
		Creep.tick(w)
	var b0 := Time.get_ticks_usec()
	for i in 400:
		w.tick += 1
		Creep.tick(w)
	var base_us := float(Time.get_ticks_usec() - b0) / 400.0
	_restore()
	var cst = w.sys_state.creep
	var s := Fissures7._enable(w, cst)
	var age: PackedByteArray = s.age
	age.fill(150)
	s.age = age
	var r0 := Time.get_ticks_usec()
	Movement.on_terrain_changed(w)
	var rebuild_us := Time.get_ticks_usec() - r0
	var tot := 0
	var worst := 0
	var worst_commit := 0
	var n := 6000
	for i in n:
		w.tick += 1
		var c0 := int(s.commits)
		var t0 := Time.get_ticks_usec()
		Creep.tick(w)
		var dt := Time.get_ticks_usec() - t0
		tot += dt
		if int(s.commits) != c0:
			worst_commit = maxi(worst_commit, dt)
		else:
			worst = maxi(worst, dt)
	var us := float(tot) / float(n)
	var c := Fissures7.counts(w)
	print("FISSURE7_COST map=512x512 ticks=%d creep_only_us=%.1f creep+fissures_us=%.1f fissures_share_us=%.1f worst_noncommit_us=%d worst_commit_tick_us=%d commits=%d nav_rebuild_us=%d counts=%s" % [
		n, base_us, us, us - base_us, worst, worst_commit, int(s.commits), rebuild_us, c])
	check(int(c.canyon) > 0, "canyons open on the late-creep 512 map")
	check(us - base_us < 400.0, "fissure share per tick under 0.4 ms (%.1f us)" % (us - base_us))
