extends "res://tests/test_base.gd"
## G6 acceptance (owner: PERF6). CONTRACTS_G6 section 5.1 (G6Hooks call sites), section 0.2 (determinism),
## PLAN_G6 A2 (elevation budget). The hook call sites are proven live with a spy (SimIndex.g6_spy): the
## spy returns non-neutral values and the test checks the effect in both the native and the GDScript
## paths. Hash checks use tools/scale_bench.gd AB "2k_fight_elev" (a map carrying height).

const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Damage = preload("res://sim/systems/damage.gd")
const NativeCore = preload("res://sim/native_core.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Bench = preload("res://tools/scale_bench.gd")
const C := Vector2(0.5, 0.5)


class Spy:
	var calls := {}
	var dmg := 1.0
	var acc := 1.0
	var rng := 1.0
	var los := true
	var sight := 0.0
	var vis := true
	var spd := 1.0
	var pas := false
	var mor := 0.0
	func _n(k: String) -> void:
		calls[k] = int(calls.get(k, 0)) + 1
	func damage_mult(_w, _src, _s, _t) -> float:
		_n("damage_mult")
		return dmg
	func accuracy_mult(_w, _src, _s, _t) -> float:
		_n("accuracy_mult")
		return acc
	func range_mult(_w, _src, _s) -> float:
		_n("range_mult")
		return rng
	func los_ok(_w, _a, _b) -> bool:
		_n("los_ok")
		return los
	func sight_bonus(_w, _e) -> float:
		_n("sight_bonus")
		return sight
	func visible_to(_w, _fid, _t) -> bool:
		_n("visible_to")
		return vis
	func speed_mult(_w, _e) -> float:
		_n("speed_mult")
		return spd
	func passable(_def, _mc) -> bool:
		_n("passable")
		return pas
	func morale_delta(_w, _e) -> float:
		_n("morale_delta")
		return mor
	func on_destroyed(_w, _e) -> void:
		_n("on_destroyed")


func _world(native: bool) -> SimWorld:
	NativeCore.force_off = not native
	SimIndex.g6_skip = false   # the spy stands in for owners: G6Hooks.active must not mask it
	var w := make_world()
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 26):
		for x in range(22, 74):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	return w


func _spawn(w: SimWorld, def: String, fid: int, cell: Vector2i) -> Dictionary:
	var mc: String = Movement.udef(def).mc
	return w.entities[w.spawn_unit(def, fid, Vector2(Movement.nearest_free_cell(w, cell, mc)) + C)]


func _after() -> void:
	SimIndex.g6_spy = null
	SimIndex.g6_hooks_on = true
	SimIndex.g6_skip = true
	NativeCore.force_off = false


## Shooter rifleman (fid 0) on hold, target rifleman (fid 1) at distance d; returns [shots, hits, first dmg].
func _duel(native: bool, spy: Spy, d: float, ticks: int) -> Array:
	var w := _world(native)
	SimIndex.g6_spy = spy
	var sh := _spawn(w, "rifleman", 0, Vector2i(40, 10))
	var tg := _spawn(w, "rifleman", 1, Vector2i(40, 10) + Vector2i(int(d), 0))
	sh.order = {"type": "hold"}
	tg.order = {"type": "hold"}
	tg.max_hp = 100000.0
	tg.hp = 100000.0
	var shots := 0
	var hits := 0
	var first := -1.0
	for i in ticks:
		w.step()
		for ev in w.events:
			if ev.type == "ShotFired" and int(ev.shooter) == int(sh.id):
				shots += 1
				hits += 1 if bool(ev.hit) else 0
			elif ev.type == "Damage" and int(ev.target) == int(tg.id) and first < 0.0:
				first = float(ev.amount)
	SimIndex.g6_spy = null
	return [shots, hits, first]


func test_hooks_wired_damage_accuracy_range() -> void:
	var s: Dictionary = Combat.stats({"kind": "unit", "def": "rifleman"})
	var rr := float(s.range)
	for native in [true, false]:
		var tag := "native" if native else "gd"
		var neutral := Spy.new()
		var a := _duel(native, neutral, rr - 1.0, 120)
		check(int(a[0]) > 0 and int(a[1]) > 0 and float(a[2]) > 0.0, "%s: neutral duel fires and hits %s" % [tag, str(a)])
		check(int(neutral.calls.get("damage_mult", 0)) > 0 and int(neutral.calls.get("accuracy_mult", 0)) > 0, "%s: damage_mult + accuracy_mult called %s" % [tag, str(neutral.calls)])
		var half := Spy.new()
		half.dmg = 0.5
		var b := _duel(native, half, rr - 1.0, 120)
		check(absf(float(b[2]) - 0.5 * float(a[2])) <= 0.02 * float(a[2]) + 0.01, "%s: damage_mult 0.5 halves the hit (%s vs %s)" % [tag, str(b[2]), str(a[2])])
		var blind := Spy.new()
		blind.acc = 0.0
		var c := _duel(native, blind, rr - 1.0, 120)
		check(int(c[0]) > 0 and int(c[1]) == 0, "%s: accuracy_mult 0 -> every shot misses %s" % [tag, str(c)])
		var far := Spy.new()
		var d0 := _duel(native, far, rr + 2.0, 80)
		check(int(d0[0]) == 0, "%s: hold unit does not fire beyond range %s" % [tag, str(d0)])
		var longr := Spy.new()
		longr.rng = 2.0
		var d1 := _duel(native, longr, rr + 2.0, 80)
		check(int(d1[0]) > 0 and int(longr.calls.get("range_mult", 0)) > 0, "%s: range_mult 2.0 -> fires beyond base range %s" % [tag, str(d1)])
		var nolos := Spy.new()
		nolos.los = false
		var e := _duel(native, nolos, rr - 1.0, 80)
		check(int(e[0]) == 0 and int(nolos.calls.get("los_ok", 0)) > 0, "%s: los_ok false blocks direct fire %s" % [tag, str(e)])
	_after()


func test_hooks_wired_visibility_sight_speed_morale() -> void:
	for native in [true, false]:
		var tag := "native" if native else "gd"
		# visible_to: an enemy next to our unit is visible, hidden by the hook
		var w := _world(native)
		var own := _spawn(w, "rifleman", 0, Vector2i(40, 10))
		var en := _spawn(w, "rifleman", 1, Vector2i(42, 10))
		Fog.recompute(w)
		check(Fog.entity_visible(w, 0, en), "%s: neutral enemy visible" % tag)
		var hide := Spy.new()
		hide.vis = false
		SimIndex.g6_spy = hide
		check(not Fog.entity_visible(w, 0, en), "%s: visible_to false hides it (Fog.entity_visible)" % tag)
		var shots := 0
		for i in 40:
			w.step()
			for ev in w.events:
				if ev.type == "ShotFired" and int(ev.shooter) == int(own.id):
					shots += 1
		check(shots == 0, "%s: combat does not fire at a hidden enemy (%d shots)" % [tag, shots])
		SimIndex.g6_spy = null
		# sight_bonus: a cell beyond sight becomes visible
		var w2 := _world(native)
		var sc := _spawn(w2, "rifleman", 0, Vector2i(40, 20))
		var sight := Fog.sight_of(sc)
		var far := Vector2(sc.pos) + Vector2(sight + 2.0, 0.0)
		Fog.recompute(w2)
		check(not Fog.is_visible(w2, 0, far), "%s: cell at sight+2 hidden" % tag)
		var eye := Spy.new()
		eye.sight = 4.0
		SimIndex.g6_spy = eye
		Fog.recompute(w2)
		check(Fog.is_visible(w2, 0, far), "%s: sight_bonus 4 reveals it" % tag)
		SimIndex.g6_spy = null
		# speed_mult: half speed covers about half the distance
		var dist := []
		for f in [1.0, 0.5]:
			var w3 := _world(native)
			var u := _spawn(w3, "rifleman", 0, Vector2i(30, 5))
			var sp := Spy.new()
			sp.spd = f
			SimIndex.g6_spy = sp
			var p0: Vector2 = u.pos
			Movement.order_move(w3, u, Vector2(70.5, 5.5))
			for i in 40:
				w3.step()
			dist.append(Vector2(u.pos).distance_to(p0))
			check(int(sp.calls.get("speed_mult", 0)) > 0, "%s: speed_mult called" % tag)
			SimIndex.g6_spy = null
		check(float(dist[0]) > 1.0 and absf(float(dist[1]) / float(dist[0]) - 0.5) < 0.1, "%s: speed_mult 0.5 halves the distance %s" % [tag, str(dist)])
		# morale_delta: a negative delta lowers a full-morale unit
		var w4 := _world(native)
		var m := _spawn(w4, "rifleman", 0, Vector2i(50, 20))
		var m0 := float(m.morale)
		var low := Spy.new()
		low.mor = -5.0
		SimIndex.g6_spy = low
		for i in 12:
			w4.step()
		SimIndex.g6_spy = null
		check(float(m.morale) < m0 and int(low.calls.get("morale_delta", 0)) > 0, "%s: morale_delta -5 lowers morale %s -> %s" % [tag, str(m0), str(m.morale)])
	_after()


func test_hooks_wired_nav_passable_and_on_destroyed() -> void:
	for native in [true, false]:
		var tag := "native" if native else "gd"
		# passable: a footprint passable for every ground class (runtime placement and nav rebuild)
		var w := _world(native)
		var pas := Spy.new()
		pas.pas = true
		SimIndex.g6_spy = pas
		var bid := w.spawn_building("depot", 0, Vector2i(44, 14), true)
		var cell: Vector2i = w.entities[bid].cell + Vector2i(1, 1)
		check(Movement.is_passable(w, cell, "foot") and Movement.is_passable(w, cell, "vehicle"), "%s: passable footprint open after placement" % tag)
		Movement.rebuild_nav(w)
		check(Movement.is_passable(w, cell, "foot"), "%s: passable footprint open after rebuild_nav" % tag)
		check(int(pas.calls.get("passable", 0)) > 0, "%s: passable called" % tag)
		SimIndex.g6_spy = null
		Movement.rebuild_nav(w)
		check(not Movement.is_passable(w, cell, "foot"), "%s: neutral footprint solid" % tag)
		w.destroy(bid, "test")
		check(Movement.is_passable(w, cell, "foot"), "%s: removed footprint open" % tag)
		# cliff edges: a wall of cut edges between x 49|50 with a gap at y 20 forces a detour
		var bits := PackedByteArray()
		var mw := int(w.map.w)
		bits.resize(mw * int(w.map.h))
		for y in range(0, 26):
			if y != 20:
				bits[y * mw + 49] = bits[y * mw + 49] | 1
				bits[y * mw + 50] = bits[y * mw + 50] | 4
		w.nav["edge"] = bits
		w.nav.comp_dirty = true
		if native:
			w.nav.native.set_edges(bits)
		else:
			w.nav.erase("foot")
			w.nav.solid.erase("foot")
			Movement._ensure_class(w, "foot")
		var path: Array = Movement._compute(w, "foot", Vector2i(45, 5), Vector2i(55, 5), Vector2(55.5, 5.5))
		var maxy := 0.0
		for p in path:
			maxy = maxf(maxy, float(p.y))
		check(not path.is_empty() and maxy >= 18.0, "%s: path detours through the gap (max y %s, %d pts)" % [tag, str(maxy), path.size()])
		check(not Movement._line_clear(w, "foot", Vector2(48.5, 5.5), Vector2(51.5, 5.5)), "%s: line across a cliff edge is not clear" % tag)
		check(Movement._line_clear(w, "foot", Vector2(48.5, 20.5), Vector2(51.5, 20.5)), "%s: line through the gap is clear" % tag)
		# on_destroyed runs before removal
		var w2 := _world(native)
		var spy := Spy.new()
		SimIndex.g6_spy = spy
		var a := _spawn(w2, "rifleman", 0, Vector2i(40, 10))
		var t := _spawn(w2, "rifleman", 1, Vector2i(42, 10))
		var s: Dictionary = Combat.stats(a).duplicate()
		s.damage = 1.0e6
		Damage.apply_hit(w2, a, t, s, true)
		check(not w2.entities.has(int(t.id)) and int(spy.calls.get("on_destroyed", 0)) == 1, "%s: on_destroyed called once on the kill %s" % [tag, str(spy.calls)])
		SimIndex.g6_spy = null
	_after()


## Native == GDScript for the G6 native code on a map carrying height: RtsCombat.height_los (port of
## Elevation.los_map) on vs off, the sim thread on vs off, and the hook wiring itself (neutral hooks on
## a flat map change nothing; mask-skipping changes nothing). Note: the whole native core on vs off
## already differs in G5 (tests/test_hot_state.gd GOLD 2k_fight/on vs /off), so it is not compared here.
func test_native_equals_gdscript_hash_on_elevated_map() -> void:
	var n := 120
	var on := Bench.ab_hash("2k_fight_elev", true, false, n)
	Combat.native_elev = false
	var gd := Bench.ab_hash("2k_fight_elev", true, false, n)
	Combat.native_elev = true
	check_eq(on, gd, "2k_fight_elev: native height LOS == GDScript Elevation.los hash")
	var thr := Bench.ab_hash("2k_fight_elev", true, true, n)
	check_eq(thr, on, "2k_fight_elev: threaded == unthreaded hash")
	var flat := Bench.ab_hash("2k_fight_flat", true, false, n)
	check(flat != on, "the height changes the 2k fight (elevation live)")
	SimIndex.g6_hooks_on = false
	var bare := Bench.ab_hash("2k_fight_flat", true, false, n)
	var bare_off := Bench.ab_hash("2k_fight_flat", false, false, n)
	SimIndex.g6_hooks_on = true
	check_eq(bare, flat, "flat 2k_fight: neutral hooks wired == not wired (native)")
	check_eq(Bench.ab_hash("2k_fight_flat", false, false, n), bare_off, "flat 2k_fight: neutral hooks wired == not wired (GDScript)")
	SimIndex.g6_skip = false
	var all := Bench.ab_hash("2k_fight_elev", true, false, n)
	SimIndex.g6_skip = true
	check_eq(all, on, "every hook called == mask-skipped")
	# non-neutral hooks through the spy: still deterministic with the sim thread on
	var spy := Spy.new()
	spy.dmg = 0.875
	spy.acc = 0.75
	spy.rng = 1.125
	spy.sight = 1.0
	spy.spd = 0.875
	spy.mor = -0.25
	SimIndex.g6_spy = spy
	var son := Bench.ab_hash("2k_fight_elev", true, false, n)
	var sthr := Bench.ab_hash("2k_fight_elev", true, true, n)
	SimIndex.g6_spy = null
	check(son != on, "non-neutral hooks change the result")
	check_eq(sthr, son, "non-neutral hooks: threaded == unthreaded hash")
	_after()


## Elevation + hook overhead probe: ms/tick of 2k_fight_elev with every hook called (mask off, worst
## case) vs never called. Budget: elevation <= 5 ms/tick at 10k (PLAN_G6 A2), i.e. <= 1 ms at 2k;
## the assert allows 5 ms at 2k for a loaded shared PC, the real number is printed for the report.
func test_elevation_cost_within_budget_probe() -> void:
	var ms := []
	for mode in [0, 1]:
		SimIndex.g6_hooks_on = mode == 1
		SimIndex.g6_skip = false
		var st := Bench.build("river_crossing_s", 2000, ["human_a", "human_b"], "fight", 1)
		var w: SimWorld = st.w
		for i in 20:
			w.step()
		var t0 := Time.get_ticks_usec()
		for i in 60:
			w.step()
		ms.append(float(Time.get_ticks_usec() - t0) / 60000.0)
	_after()
	var over := float(ms[1]) - float(ms[0])
	print("PERF6 probe 2k_fight_elev ms/tick: hooks off %.2f, all hooks on %.2f, overhead %.2f (CPU load not controlled)" % [ms[0], ms[1], over])
	check(over <= 5.0, "hook + elevation overhead %.2f ms/tick at 2k <= 5" % over)


## Regression (ORCH CR native_mc_rail_hover): rail / hover units must not overwrite the foot nav (the
## native class table used to alias unknown classes to foot, freezing every infantry unit).
func test_native_rail_hover_classes_keep_foot_nav() -> void:
	for native in [true, false]:
		var tag := "native" if native else "gd"
		var w := _world(native)
		var t: PackedByteArray = w.map.terrain
		for x in range(22, 74):
			t[24 * int(w.map.w) + x] = Terrain.RAIL
		w.map.terrain = t
		Movement.rebuild_nav(w)
		w.spawn_unit("b_armored_train", 1, Vector2(30.5, 24.5))
		_spawn(w, "a_hovercraft", 0, Vector2i(34, 18))
		var u := _spawn(w, "rifleman", 0, Vector2i(30, 5))
		w.step()
		check(Movement.is_passable(w, Vector2i(40, 5), "foot"), "%s: grass still passable for foot" % tag)
		check(not Movement.is_passable(w, Vector2i(40, 5), "rail") and Movement.is_passable(w, Vector2i(40, 24), "rail"), "%s: rail class = RAIL tiles only" % tag)
		var p0: Vector2 = u.pos
		Movement.order_move(w, u, Vector2(60.5, 5.5))
		for i in 40:
			w.step()
		check(Vector2(u.pos).distance_to(p0) > 3.0, "%s: infantry still paths with a train + hovercraft on the map (moved %.2f)" % [tag, Vector2(u.pos).distance_to(p0)])
	_after()

## G6 PERF6-4 (ORCH decision): the path queue keeps its 40/tick budget but serves player-side requests first,
## then smaller AI groups, then mass AI orders (stable keys, no wall clock); a world with no AI side keeps the
## old FIFO entries (no "pk" key: hash-compatible).
func test_path_queue_priority_player_first_then_small_groups() -> void:
	NativeCore.force_off = false
	var w := make_world({}, true)   # side 1 is an AI side (is_ai); no controller thinks in this test
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 26):
		for x in range(22, 74):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	check(bool(w.factions[1].is_ai) and not bool(w.factions[0].is_ai), "fixture: side 1 is AI, side 0 is not")
	var mass := []
	for i in 120:
		mass.append(int(_spawn(w, "rifleman", 1, Vector2i(23 + i % 12, 1 + i / 12)).id))
	var small := []
	for i in 8:
		small.append(int(_spawn(w, "rifleman", 1, Vector2i(37 + i % 4, 1 + i / 4)).id))
	var mine := []
	for i in 3:
		mine.append(int(_spawn(w, "rifleman", 0, Vector2i(23 + i, 22)).id))
	var goal := Vector2(70.5, 20.5)
	Movement.apply_command(w, {"type": "move", "issuer": 1, "unit_ids": mass, "target": goal})
	Movement.apply_command(w, {"type": "move", "issuer": 1, "unit_ids": small, "target": goal + Vector2(0, -6)})
	Movement.apply_command(w, {"type": "move", "issuer": 0, "unit_ids": mine, "target": goal + Vector2(0, 3)})
	var st: Dictionary = w.sys_state.movement
	var waiting := func(ids: Array) -> int:
		var n := 0
		for id in ids:
			if int(w.entities[id].get("path_req", -1)) >= 0:
				n += 1
		return n
	check(int(waiting.call(mass)) > 0, "fixture: the mass AI order overflows the budget (%d queued)" % int(waiting.call(mass)))
	var q: Array = st.queue
	check(q.size() > 0 and not q[0].has("pk") and mine.has(int(q[0].id)), "a player request waits at the queue head, ahead of the AI mass order")
	w.step()
	check_eq(int(waiting.call(mine)), 0, "player requests served on the next drain")
	check_eq(int(waiting.call(small)), 0, "the small AI group is served before the mass AI order")
	check(int(waiting.call(mass)) > 0, "the mass AI order is still partly queued (budget 40/tick)")
	for i in 10:
		w.step()
	check_eq(int(waiting.call(mass)), 0, "the mass AI order drains within its budget (never starved)")
	# no AI side: FIFO entries without a pk key (pre-G6 queue format)
	var w2 := make_world()
	w2.ai_state = {}
	var ids2 := []
	for i in 60:
		ids2.append(int(w2.entities[w2.spawn_unit("rifleman", 1, Vector2(Movement.nearest_free_cell(w2, Vector2i(10 + i % 10, 10 + i / 10), "foot")) + C)].id))
	Movement.apply_command(w2, {"type": "move", "issuer": 1, "unit_ids": ids2, "target": Vector2(60.5, 40.5)})
	var pk_any := false
	for qe in w2.sys_state.movement.queue:
		pk_any = pk_any or qe.has("pk")
	check(not pk_any and not w2.sys_state.movement.has("qin"), "non-AI sides keep plain FIFO entries (no pk / qin keys)")
