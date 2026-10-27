extends "res://tests/test_base.gd"
## Military systems (agent B): movement, combat, fog, victory. CONTRACTS.md section 5.

const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Fog = preload("res://sim/systems/fog.gd")
const C := Vector2(0.5, 0.5)


## Fresh default match with the AI controller disabled (tests drive both sides directly).
func _world(overrides: Dictionary = {}) -> SimWorld:
	var w := make_world(overrides)
	w.ai_state = {}
	return w


## Test sandbox: paint a rectangle of terrain and rebuild nav.
func _paint(w: SimWorld, rect: Rect2i, code: int) -> void:
	var t: PackedByteArray = w.map.terrain
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			t[y * int(w.map.w) + x] = code
	w.map.terrain = t
	Movement.rebuild_nav(w)


## Open grass arena x 22..73, y 0..25 (away from both HQs).
func _arena(w: SimWorld) -> void:
	_paint(w, Rect2i(22, 0, 52, 26), Terrain.GRASS)


func _bad_units(w: SimWorld) -> Array:
	var bad := []
	for e in w.units_of(0) + w.units_of(1):
		var mc := Movement.move_class(e)
		var cell := w.cell_of(e.pos)
		if not Movement.is_passable(w, cell, mc) or not Terrain.passable(w.terrain_at(cell), mc):
			bad.append("%s#%d@%s" % [e.def, e.id, cell])
	return bad


func _spawn(w: SimWorld, def: String, fid: int, cell: Vector2i) -> int:
	var mc: String = Movement.udef(def).mc
	return w.spawn_unit(def, fid, Vector2(Movement.nearest_free_cell(w, cell, mc)) + C)


func _ids_of(arr: Array) -> Array:
	var out := []
	for e in arr:
		out.append(int(e.id))
	return out


# ---------------------------------------------------------------- movement
func test_mil01_group_move_across_bridge_arrives() -> void:
	var w := _world()
	check(not w.map.bridge_cells.is_empty(), "map has a bridge")
	var ids := []
	for i in 8:
		ids.append(_spawn(w, "rifleman", 0, Vector2i(38 + i % 4, 40 + i / 4)))
	var goal := Vector2(56.5, 56.5)
	var ev := do_cmd(w, 0, {"type": "move", "unit_ids": ids, "target": goal})
	check_eq(rejected_reason(ev), "", "move accepted")
	# G7 (SQUAD7-4): a player group move now takes a real formation by default (G7_REFERENCE section 3, owner order
	# "formations rebuilt like a real military"; here a staggered column ~6 tiles long), so the old "every man within 3
	# tiles of the click" oracle measured the G1 clump. Each man must instead reach HIS OWN slot, and the slots
	# themselves must be the formation anchored at the goal (front within 1 tile of it, no slot over 8 tiles away).
	var slot := {}
	for id in ids:
		slot[id] = Vector2(w.entities[id].order.target)
	var front := INF
	for id in ids:
		front = minf(front, (slot[id] as Vector2).distance_to(goal))
		check((slot[id] as Vector2).distance_to(goal) <= 8.0, "slot of %d belongs to the formation at the goal (d=%.2f)" % [id, (slot[id] as Vector2).distance_to(goal)])
	check(front <= 1.0, "the formation front is at the goal (%.2f)" % front)
	var bad := []
	var on_bridge := false
	for t in 600:
		w.step()
		bad.append_array(_bad_units(w))
		for id in ids:
			if w.terrain_at(w.cell_of(w.entities[id].pos)) == Terrain.BRIDGE:
				on_bridge = true
	check(on_bridge, "group crossed via the bridge")
	check_eq(bad.size(), 0, "no unit ever in an impassable cell %s" % str(bad.slice(0, 5)))
	for id in ids:
		var e: Dictionary = w.entities[id]
		check(e.pos.distance_to(slot[id]) <= 1.5, "rifleman %d within 1.5 tiles of his formation slot (d=%.2f)" % [id, e.pos.distance_to(slot[id])])
		check_eq(String(e.order.type), "idle", "arrived unit %d is idle" % id)
		check(not e.moving, "arrived unit %d stopped" % id)


func test_vehicles_path_around_forest() -> void:
	var w := _world()
	_paint(w, Rect2i(26, 0, 30, 17), Terrain.GRASS)
	_paint(w, Rect2i(38, 3, 4, 10), Terrain.FOREST)   # wall x 38..41, y 3..12
	var id := w.spawn_unit("mbt", 0, Vector2(32.5, 7.5))
	var goal := Vector2(47.5, 7.5)
	do_cmd(w, 0, {"type": "move", "unit_ids": [id], "target": goal})
	var in_forest := 0
	for t in 600:
		w.step()
		if w.terrain_at(w.cell_of(w.entities[id].pos)) == Terrain.FOREST:
			in_forest += 1
	check_eq(in_forest, 0, "MBT never in a FOREST cell")
	check(w.entities[id].pos.distance_to(goal) <= 1.0, "MBT reached the far side (d=%.2f)" % w.entities[id].pos.distance_to(goal))
	# infantry may cut straight through the forest
	check(Movement.is_passable(w, Vector2i(39, 7), "foot"), "forest passable on foot")
	check(not Movement.is_passable(w, Vector2i(39, 7), "vehicle"), "forest blocks vehicles")


func test_order_path_snaps_and_rejects_unreachable() -> void:
	var w := _world()
	_arena(w)
	var id := w.spawn_unit("ifv", 0, Vector2(30.5, 10.5))
	var e: Dictionary = w.entities[id]
	_paint(w, Rect2i(44, 8, 3, 3), Terrain.WATER)
	check(Movement.order_path(w, e, Vector2(45.5, 9.5)), "goal in a small lake snaps to the shore")
	var last: Vector2 = e.path[e.path.size() - 1]
	check(Movement.is_passable(w, w.cell_of(last), "vehicle"), "snapped goal is passable")
	check_eq(String(e.order.type), "idle", "order_path does not change the order")
	_paint(w, Rect2i(55, 2, 16, 16), Terrain.WATER)
	check(not Movement.order_path(w, e, Vector2(63.5, 10.5)), "goal >6 tiles inside water is unreachable")
	var r := w.preview_command({"type": "move", "issuer": 0, "unit_ids": [id], "target": Vector2(63.5, 10.5)})
	check(r != "", "unreachable move is rejected with a reason")
	check_eq(Movement.nearest_free_cell(w, Vector2i(60, 10), "foot").x < 55 or Movement.nearest_free_cell(w, Vector2i(60, 10), "foot").y >= 18, true, "nearest_free_cell leaves the lake")


func test_footprint_blocks_and_nudges_units() -> void:
	var w := _world()
	_arena(w)
	var id := w.spawn_unit("rifleman", 0, Vector2(41.5, 11.5))
	var bid := w.spawn_building("depot", 0, Vector2i(41, 11), true)
	check(not Movement.is_passable(w, Vector2i(41, 11), "foot"), "footprint solid for foot")
	check(not Movement.is_passable(w, Vector2i(42, 12), "vehicle"), "footprint solid for vehicle")
	check(Movement.is_passable(w, w.cell_of(w.entities[id].pos), "foot"), "unit nudged out of the footprint")
	w.destroy(bid, "test")
	check(Movement.is_passable(w, Vector2i(41, 11), "foot"), "footprint released on destroy")


# ---------------------------------------------------------------- combat
func test_dead_units_removed_and_never_act() -> void:
	var w := _world()
	_arena(w)
	var a := w.spawn_unit("rifleman", 0, Vector2(30.5, 10.5))
	var b := w.spawn_unit("rifleman", 1, Vector2(34.5, 10.5))
	w.entities[b].hp = 5.0
	var dead_tick := -1
	var acted_after := 0
	var destroyed_events := 0
	for t in 300:
		w.step()
		for ev in w.events:
			if ev.type == "EntityDestroyed" and int(ev.id) == b:
				destroyed_events += 1
			if dead_tick >= 0 and ev.type == "ShotFired" and (int(ev.shooter) == b or int(ev.target) == b):
				acted_after += 1
		if dead_tick < 0 and not w.entities.has(b):
			dead_tick = w.tick
	check(dead_tick > 0, "target was killed")
	check_eq(destroyed_events, 1, "destroyed exactly once")
	check_eq(acted_after, 0, "dead unit never fires or is fired at again")
	check(not _ids_of(w.units_of(1)).has(b), "dead unit removed from units_of")
	check(not _ids_of(w.visible_enemies(0)).has(b), "dead unit not in visible_enemies")
	check(w.entities.has(a), "shooter survives")


func test_armor_table_rifle_vs_mbt() -> void:
	var w := _world()
	_arena(w)
	var r1 := w.spawn_unit("rifleman", 0, Vector2(30.5, 4.5))
	var mbt := w.spawn_unit("mbt", 1, Vector2(34.5, 4.5))
	var r2 := w.spawn_unit("rifleman", 0, Vector2(30.5, 18.5))
	var inf := w.spawn_unit("rifleman", 1, Vector2(34.5, 18.5))
	w.entities[mbt].cooldown = 1e9   # dummies never fire
	w.entities[mbt].facing = PI      # G2 (A2): face the shooter (front arc x1.0) so only the armor table is measured
	w.entities[inf].cooldown = 1e9
	w.entities[inf].hp = 1e6
	var hits := {r1: 0, r2: 0}
	for t in 300:
		w.step()
		for ev in w.events:
			if ev.type == "ShotFired" and ev.hit and hits.has(int(ev.shooter)):
				hits[int(ev.shooter)] += 1
	check(hits[r1] > 0 and hits[r2] > 0, "both riflemen scored hits (%d, %d)" % [hits[r1], hits[r2]])
	if hits[r1] == 0 or hits[r2] == 0:
		return
	var per_mbt: float = (1000.0 - float(w.entities[mbt].hp)) / float(hits[r1])
	var per_inf: float = (1e6 - float(w.entities[inf].hp)) / float(hits[r2])
	print("    armor: rifle per hit vs MBT %.3f, vs infantry %.3f" % [per_mbt, per_inf])
	check(per_mbt <= 0.05 * per_inf + 0.002, "rifle vs MBT <= 5%% of rifle vs infantry (%.3f vs %.3f)" % [per_mbt, per_inf])
	check(Combat.shot_damage(w.entities[r1], w.entities[mbt]) <= 0.05 * Combat.shot_damage(w.entities[r2], w.entities[inf]), "shot_damage table")


func test_hold_never_chases_idle_does() -> void:
	var w := _world()
	_arena(w)
	var h := w.spawn_unit("rifleman", 0, Vector2(30.5, 5.5))
	var e1 := w.spawn_unit("rifleman", 1, Vector2(30.5, 12.5))   # 7 tiles: in sight, out of range
	var idle := w.spawn_unit("rifleman", 0, Vector2(50.5, 5.5))
	var e2 := w.spawn_unit("rifleman", 1, Vector2(50.5, 12.5))
	for id in [e1, e2]:
		w.entities[id].cooldown = 1e9
		w.entities[id].order = {"type": "hold"}
	do_cmd(w, 0, {"type": "hold", "unit_ids": [h]})
	var p0: Vector2 = w.entities[h].pos
	var shots := {h: 0, idle: 0}
	for t in 100:
		w.step()
		for ev in w.events:
			if ev.type == "ShotFired" and shots.has(int(ev.shooter)):
				shots[int(ev.shooter)] += 1
	check(w.entities[h].pos.distance_to(p0) < 0.01, "hold unit did not move")
	check_eq(shots[h], 0, "hold unit did not fire out of range")
	check(w.entities[idle].pos.y > 6.0, "idle unit chased the enemy in sight")
	check(shots[idle] > 0, "idle unit engaged after closing in")


# ---------------------------------------------------------------- fog
func test_initial_fog_only_own_sight() -> void:
	var w := _world()
	check(not Fog.is_explored(w, 0, Vector2(48.5, 48.5)), "map centre unexplored at start")
	check(Fog.is_explored(w, 0, Vector2(14.5, 14.5)), "own HQ explored")
	check(Fog.is_visible(w, 0, Vector2(14.5, 14.5)), "own HQ visible")
	check(not Fog.is_visible(w, 0, Vector2(81.5, 81.5)), "enemy HQ not visible")
	check_eq(w.visible_enemies(0).size(), 0, "no enemies visible at start")


func test_ai02_fog_hides_enemies_and_rejects_attack() -> void:
	var w := _world()
	var enemy := w.spawn_unit("rifleman", 1, Vector2(60.5, 10.5))
	var shooter := _spawn(w, "rifleman", 0, Vector2i(20, 20))
	var depot := w.spawn_building("depot", 1, Vector2i(62, 5), true)
	w.run_ticks(4)
	check(not _ids_of(w.visible_enemies(0)).has(enemy), "unseen enemy not in visible_enemies")
	check(not Fog.is_explored(w, 0, w.entities[enemy].pos), "enemy cell unexplored")
	var ev := do_cmd(w, 0, {"type": "attack", "unit_ids": [shooter], "target_id": enemy})
	check_eq(rejected_reason(ev), "Target not visible.", "attack on unseen target rejected")
	check_eq(String(w.entities[shooter].order.type), "idle", "rejected attack did not mutate the order")
	# a scout reveals it
	var recon := w.spawn_unit("recon", 0, Vector2(55.5, 10.5))
	w.run_ticks(4)
	check(_ids_of(w.visible_enemies(0)).has(enemy), "enemy visible once scouted")
	check(_ids_of(w.visible_enemies(0)).has(depot), "enemy building visible once scouted")
	check(w.memory[0].has(depot), "enemy building remembered")
	ev = do_cmd(w, 0, {"type": "attack", "unit_ids": [shooter], "target_id": enemy})
	check_eq(rejected_reason(ev), "", "attack on visible target accepted")
	do_cmd(w, 0, {"type": "stop", "unit_ids": [shooter]})
	# scout leaves (dies): explored stays, visibility goes, memory persists
	w.destroy(recon, "test")
	w.run_ticks(8)
	if w.entities.has(enemy):
		var ep: Vector2 = w.entities[enemy].pos
		check(not Fog.is_visible(w, 0, ep), "enemy cell no longer visible")
		check(Fog.is_explored(w, 0, ep), "enemy cell stays explored")
		check(not _ids_of(w.visible_enemies(0)).has(enemy), "enemy hidden again")
		ev = do_cmd(w, 0, {"type": "attack", "unit_ids": [shooter], "target_id": enemy})
		check_eq(rejected_reason(ev), "Target not visible.", "attack rejected after losing sight")
	check(Fog.is_explored(w, 0, Vector2(55.5, 10.5)), "scout cell stays explored")
	check(w.memory[0].has(depot), "memory kept while out of sight")
	w.destroy(depot, "test")
	w.run_ticks(4)
	check(w.memory[0].has(depot), "stale memory kept until re-scouted")
	w.spawn_unit("recon", 0, Vector2(55.5, 10.5))
	w.run_ticks(4)
	check(not w.memory[0].has(depot), "memory dropped once the empty site is seen")


# ---------------------------------------------------------------- victory
func test_hq_destruction_ends_match() -> void:
	var w := _world()
	for u in w.units_of(1):
		w.destroy(int(u.id), "test")
	var hq: Dictionary = w.buildings_of(1, "hq")[0]
	hq.hp = 3.0
	for i in 4:
		_spawn(w, "rifleman", 0, Vector2i(77, 79 + i))
	var elim := 0
	var ended := 0
	for t in 600:
		w.step()
		for ev in w.events:
			if ev.type == "SideEliminated":
				elim += 1
				check_eq(int(ev.faction), 1, "eliminated side")
			if ev.type == "MatchEnded":
				ended += 1
				check_eq(int(ev.winner), 0, "MatchEnded winner")
		if w.match_state.ended:
			break
	check(w.match_state.ended, "match ended")
	check_eq(int(w.match_state.winner), 0, "winner is the player")
	check_eq(String(w.match_state.reason), "hq_elimination", "reason")
	check_eq(int(w.match_state.end_tick), w.tick, "end tick")
	check(not w.factions[1].alive, "side 1 eliminated")
	var t_end := w.tick
	w.run_ticks(20)
	check_eq(w.tick, t_end, "no ticks after the end")
	check_eq(elim, 1, "SideEliminated once")
	check_eq(ended, 1, "MatchEnded once")


func test_endless_never_ends() -> void:
	var w := _world({"victory": "endless"})
	w.destroy(int(w.buildings_of(1, "hq")[0].id), "test")
	var elim := 0
	for t in 60:
		w.step()
		for ev in w.events:
			if ev.type == "SideEliminated":
				elim += 1
			check(ev.type != "MatchEnded", "endless emits no MatchEnded")
	check_eq(elim, 1, "side still eliminated once")
	check(not w.factions[1].alive, "side 1 not alive")
	check(not w.match_state.ended, "endless match not ended")
	check_eq(w.tick, 60, "ticks keep running")


# ---------------------------------------------------------------- save / perf
func _fight(w: SimWorld, per_side: int, x0: int) -> void:
	var defs := ["rifleman", "rifleman", "at_gunner", "ifv", "mbt", "rifleman", "recon", "rifleman"]
	var rows := (per_side + 15) / 16
	for i in per_side:
		var x := x0 + i % 16
		var r := i / 16
		w.spawn_unit(defs[i % defs.size()], 0, Vector2(x, 1 + r) + C)
		w.spawn_unit(defs[(i + 3) % defs.size()], 1, Vector2(x, rows + 6 + r) + C)


func test_save_restore_mid_fight_hash_equal() -> void:
	var w := _world()
	_arena(w)
	_fight(w, 24, 26)
	# G7 (SQUAD7-4): the movers stand in a cliff pen (exit at its top-left corner). The G7 default formation (a
	# 60-man wedge of 5 fire-team wedges abreast, G7_REFERENCE section 3) put most slots within straight-line reach on
	# open grass, so no move needed A* and the queue was already empty at save time. Out of the pen every one of the
	# 60 paths is an A* request (budget 40 + 8 drained a tick), so the save provably holds a non-empty path queue
	# whatever formation the default picks.
	_paint(w, Rect2i(48, 2, 1, 9), Terrain.CLIFF)    # west wall x 48, y 2..10 (gap at y 0..1)
	_paint(w, Rect2i(63, 0, 1, 11), Terrain.CLIFF)   # east wall x 63
	_paint(w, Rect2i(48, 9, 16, 2), Terrain.CLIFF)   # south wall y 9..10
	w.run_ticks(30)
	var movers := []
	for i in 60:
		movers.append(w.spawn_unit("rifleman", 0, Vector2(50 + i % 12, 3 + i / 12) + C))
	do_cmd(w, 0, {"type": "move", "unit_ids": movers, "target": Vector2(60.5, 20.5)})
	check(String(w.entities[movers[0]].get("f7_auto", "")) != "", "the move took the G7 default formation")
	var q: Array = w.sys_state.movement.queue
	check(q.size() > 0, "path queue non-empty at save time (%d)" % q.size())
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check(w2 != null, "from_dict")
	if w2 == null:
		return
	w2.ai_state = {}
	if not check_eq(w2.state_hash(), w.state_hash(), "hash equal right after restore"):
		_print_first_diff(var_to_str(w.to_dict()), var_to_str(w2.to_dict()))
	w.run_ticks(200)
	w2.run_ticks(200)
	check_eq(w2.state_hash(), w.state_hash(), "hash equal after 200 more ticks")
	var shots := 0
	for ev in w.event_log:
		if ev.type == "ShotFired":
			shots += 1
	check(shots > 0, "the fight was live")


func _print_first_diff(a: String, b: String) -> void:
	var k := 0
	while k < mini(a.length(), b.length()) and a[k] == b[k]:
		k += 1
	print("ERROR: save text sizes %d vs %d, first diff at char %d: '%s' vs '%s'" % [a.length(), b.length(), k, a.substr(maxi(k - 80, 0), 160).c_escape(), b.substr(maxi(k - 80, 0), 160).c_escape()])
	var la := a.split("\n")
	var lb := b.split("\n")
	var shown := 0
	for i in mini(la.size(), lb.size()):
		if la[i] != lb[i] and shown < 4:
			print("ERROR: save diff line %d: '%s' vs '%s'" % [i, la[i].strip_edges().substr(0, 120), lb[i].strip_edges().substr(0, 120)])
			shown += 1


func test_perf_256_units_fighting() -> void:
	var w := _world()
	_arena(w)
	_fight(w, 128, 26)
	var total := 0
	var worst := 0
	var n := 200
	for t in n:
		var t0 := Time.get_ticks_usec()
		w.step()
		var dt := Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
	var alive := w.units_of(0).size() + w.units_of(1).size()
	print("    PERF mil: 256 mixed units, %d ticks: avg %.2f ms, max %.2f ms, alive at end %d" % [n, total / 1000.0 / n, worst / 1000.0, alive])
	check(alive < 256 + 12, "units died in the fight")
	var bad := _bad_units(w)
	check_eq(bad.size(), 0, "no unit inside an impassable cell after a long fight %s" % str(bad.slice(0, 5)))
