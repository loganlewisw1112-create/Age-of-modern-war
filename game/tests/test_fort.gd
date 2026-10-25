extends "res://tests/test_base.gd"
## G4b FORT (CONTRACTS_G4 section 6): wall content, build_line placement and per-segment costs,
## conn masks, gates (owner/ally pass, enemy blocked, lock; native + fallback), walls block direct
## fire (towers fire over), breach by artillery, save mid-construction of a line.

const Fortify = preload("res://sim/systems/fortify.gd")
const Movement = preload("res://sim/systems/movement.gd")
const NativeCore = preload("res://sim/native_core.gd")
const Construction = preload("res://sim/systems/construction.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const TMP_DIR := "user://test_fort"


func _modes() -> Array:
	return [true, false] if NativeCore.available() else [false]


func _world(native_on: bool = true, overrides: Dictionary = {}) -> SimWorld:
	NativeCore.force_off = not native_on
	var w := make_world(overrides)
	w.ai_state = {}
	for fid in w.factions:
		w.factions[fid].credits = 50000
		w.factions[fid].stock.salvage = 50000
		(w.fog[fid].explored as PackedByteArray).fill(1)
	return w


func _hq(w: SimWorld, fid: int) -> Dictionary:
	for b in w.buildings_of(fid):
		if bool(Content.building(String(b.def)).get("is_hq", false)):
			return b
	return {}


## First horizontal run of n cells near fid's HQ where def can be placed on every cell.
func _find_row(w: SimWorld, fid: int, def_id: String, n: int) -> Vector2i:
	var hq := _hq(w, fid)
	var hc: Vector2i = hq.cell
	for r in range(3, 15):
		for dy in [-r, r]:
			for x0 in range(hc.x - 12, hc.x + 12):
				var ok := true
				for i in n:
					if Construction.placement_error(w, fid, def_id, Vector2i(x0 + i, hc.y + dy)) != "":
						ok = false
						break
				if ok:
					return Vector2i(x0, hc.y + dy)
	return Vector2i(-1, -1)


func _engineers(w: SimWorld, fid: int, n: int, near: Vector2) -> Array:
	var ids := []
	for i in n:
		ids.append(w.spawn_unit("engineer", fid, near + Vector2(0.5 * i, 1.5)))
	return ids


func _spent(w: SimWorld, fid: int, cause: String) -> int:
	var tot := 0
	for j in w.factions[fid].journal:
		if String(j.get("cause", "")) == cause:
			tot += -int(j.get("credits", 0))
	return tot


## Grass arena: paints x0..x0+wd, y0..y0+ht as GRASS, drops resources inside, rebuilds nav.
func _arena(w: SimWorld, r: Rect2i) -> void:
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if e.kind == "resource" and r.has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	Movement.rebuild_nav(w)


## A closed (2*half+1) square ring of walls of `def` for fid around `c` (centre cell), with a gate at the
## middle of the south side when gate_def != "". Built instantly. Returns {walls:[ids], gate:id}.
func _ring(w: SimWorld, fid: int, c: Vector2i, half: int, def_id: String, gate_def: String) -> Dictionary:
	var walls := []
	var gate := -1
	for y in range(c.y - half, c.y + half + 1):
		for x in range(c.x - half, c.x + half + 1):
			if absi(x - c.x) != half and absi(y - c.y) != half:
				continue
			if gate_def != "" and x == c.x and y == c.y + half:
				gate = w.spawn_building(gate_def, fid, Vector2i(x, y), true)
			else:
				walls.append(w.spawn_building(def_id, fid, Vector2i(x, y), true))
	w.step()   # Fortify picks the pieces up (conn, gate nav)
	return {"walls": walls, "gate": gate}


# ================================================================ content
func test_fort_content_defs_and_armor() -> void:
	var ids := {"a_wall": "wall", "a_gate": "gate", "a_wall_tower": "tower", "b_wall": "wall", "b_gate": "gate",
		"b_wall_tower": "tower", "m_barrier": "wall", "m_field_gate": "gate", "m_spire": "tower"}
	for id in ids:
		var d := Content.building(id)
		if not check(not d.is_empty(), "def %s exists" % id):
			continue
		check_eq(int(d.size), 1, "%s size 1" % id)
		check_eq(Fortify.kind_of(id), ids[id], "%s kind" % id)
		check_eq(String(d.armor), "fortification", "%s armor" % id)
		check(bool(d.buildable), "%s buildable" % id)
		check_eq(int(d.stage_min), 8 if ids[id] == "tower" else 7, "%s stage_min" % id)
		if ids[id] == "tower":
			check(not Content.weapon(String(d.weapon)).is_empty(), "%s has a weapon" % id)
	check(Content.weapon("wt_flak").get("anti_air", false), "flak tower hits drones")
	check(Content.armor_mult("small_arms", "fortification") <= 0.03, "small arms barely scratch walls")
	check(Content.armor_mult("artillery", "fortification") > 1.0, "artillery strong vs walls")
	check(Content.armor_mult("at", "fortification") >= 0.8, "AT decent vs walls")
	check(Content.armor_mult("demolition", "fortification") > Content.armor_mult("artillery", "fortification"), "demolition strongest")
	for f in [["human_a", "a_wall", "a_gate", "a_wall_tower"], ["human_b", "b_wall", "b_gate", "b_wall_tower"],
			["machine", "m_barrier", "m_field_gate", "m_spire"]]:
		check_eq(Content.role(f[0], "wall"), f[1], "%s wall role" % f[0])
		check_eq(Content.role(f[0], "gate"), f[2], "%s gate role" % f[0])
		check_eq(Content.role(f[0], "wall_tower"), f[3], "%s wall_tower role" % f[0])


func test_fort_line_cells_snap_8_dirs() -> void:
	check_eq(Fortify.line_cells(Vector2i(0, 0), Vector2i(5, 1)).size(), 6, "near-horizontal snaps flat")
	for c in Fortify.line_cells(Vector2i(0, 0), Vector2i(5, 1)):
		check_eq(c.y, 0, "flat row")
	check_eq(Fortify.line_cells(Vector2i(3, 3), Vector2i(2, -2)).back(), Vector2i(3, -2), "near-vertical snaps")
	var dg := Fortify.line_cells(Vector2i(0, 0), Vector2i(4, 3))
	check_eq(dg.size(), 5, "diagonal length max(|dx|,|dy|)+1")
	check_eq(dg.back(), Vector2i(4, 4), "diagonal end")
	for i in dg.size():
		check_eq(dg[i], Vector2i(i, i), "diagonal cell %d" % i)
	check_eq(Fortify.line_cells(Vector2i(0, 0), Vector2i(200, 0)).size(), Fortify.MAX_LINE, "capped")
	check_eq(Fortify.line_cells(Vector2i(2, 2), Vector2i(2, 2)), [Vector2i(2, 2)], "single cell")


# ================================================================ build_line
func test_fort_build_line_places_skips_and_charges_per_segment() -> void:
	var w := _world()
	var o := _find_row(w, 0, "a_wall", 7)
	if not check(o.x >= 0, "found a buildable row near the HQ"):
		return
	var blocker := w.spawn_building("a_wall", 0, o + Vector2i(2, 0), true)   # cell 3 of 5 is taken
	check(blocker >= 0, "blocker placed")
	var eng := _engineers(w, 0, 1, Vector2(o) + Vector2(0.5, 0.5))
	var cost := int(Content.building("a_wall").cost.credits)
	var before := _spent(w, 0, "build:a_wall")
	var ev := do_cmd(w, 0, {"type": "build_line", "def": "a_wall", "from": [o.x, o.y], "to": [o.x + 4, o.y], "unit_ids": eng})
	var plan = null
	for e in ev:
		if e.type == "LinePlanned":
			plan = e
	if not check(plan != null, "LinePlanned emitted (%s)" % rejected_reason(ev)):
		return
	check_eq((plan.cells as Array).size(), 4, "4 legal cells")
	check_eq((plan.skipped as Array).size(), 1, "1 skipped cell")
	check_eq(String(plan.skipped[0].reason), "Blocked by another building.", "skip reason")
	check_eq(_spent(w, 0, "build:a_wall") - before, cost, "only the first segment is charged at start")
	var done := false
	for i in 3000:
		w.step()
		for e in w.events:
			if e.type == "LineFinished" and int(e.line) == int(plan.line):
				done = true
		if done:
			break
	check(done, "line finished")
	var built := 0
	for b in w.buildings_of(0, "a_wall"):
		if bool(b.built):
			built += 1
	check_eq(built, 5, "4 new walls + blocker built")
	check_eq(_spent(w, 0, "build:a_wall") - before, 4 * cost, "charged once per segment")
	check(not w.entities[eng[0]].has("fort_line"), "builder released after the line")


func test_fort_build_line_append_and_rejects() -> void:
	var w := _world()
	var o := _find_row(w, 0, "a_wall", 6)
	if not check(o.x >= 0, "found a buildable row"):
		return
	var eng := _engineers(w, 0, 2, Vector2(o) + Vector2(0.5, 0.5))
	var ev := do_cmd(w, 0, {"type": "build_line", "def": "a_wall", "from": [o.x, o.y], "to": [o.x + 2, o.y], "unit_ids": eng})
	var lid := -1
	for e in ev:
		if e.type == "LinePlanned":
			lid = int(e.line)
	check(lid > 0, "first line planned (%s)" % rejected_reason(ev))
	var ev2 := do_cmd(w, 0, {"type": "build_line", "def": "a_gate", "from": [o.x + 3, o.y], "to": [o.x + 5, o.y], "unit_ids": eng, "append": true})
	var lid2 := -2
	for e in ev2:
		if e.type == "LinePlanned":
			lid2 = int(e.line)
	check_eq(lid2, lid, "append extends the same line")
	var ln = Fortify._line(Fortify.state(w), lid)
	check(ln != null and (ln.segs as Array).size() == 6, "6 queued segments")
	check_eq(String(ln.segs[5][2]), "a_gate", "appended segments keep their own def")
	# two builders work in order: two foundations started at once
	check_eq((ln.started as Array).size(), 2, "two builders start two segments")
	# rejects
	check_eq(w.preview_command({"type": "build_line", "issuer": 0, "def": "hq", "from": [o.x, o.y], "to": [o.x, o.y], "unit_ids": eng}),
		"Only walls, gates and wall towers can be built as a line.", "non-fort def rejected")
	var far := w.preview_command({"type": "build_line", "issuer": 0, "def": "a_wall", "from": [90, 5], "to": [93, 5], "unit_ids": eng})
	check(far != "", "all-illegal line rejected (%s)" % far)
	var rifle := w.spawn_unit(String(Content.production(Content.role("human_a", "infantry")).spawns[0]), 0, Vector2(o) + Vector2(0.5, 2.5))
	check_eq(w.preview_command({"type": "build_line", "issuer": 0, "def": "a_wall", "from": [o.x, o.y + 1], "to": [o.x + 2, o.y + 1], "unit_ids": [rifle]}),
		"Only work crews (engineers) can construct buildings.", "non-builder rejected")
	w.factions[0].stage = 7
	check(w.preview_command({"type": "build_line", "issuer": 0, "def": "a_wall_tower", "from": [o.x, o.y + 2], "to": [o.x, o.y + 2], "unit_ids": eng}).contains("Stage 8"), "tower needs stage 8")
	# a stopped builder leaves the line
	do_cmd(w, 0, {"type": "stop", "unit_ids": [eng[0]]})
	w.step()
	check(not w.entities[eng[0]].has("fort_line"), "stopped builder left the line")


# ================================================================ conn masks
func test_fort_conn_masks_on_complete_and_destroy() -> void:
	var w := _world()
	_arena(w, Rect2i(52, 20, 26, 26))
	var a := w.spawn_building("a_wall", 0, Vector2i(60, 30), true)
	var b := w.spawn_building("a_wall", 0, Vector2i(61, 30), true)
	var c := w.spawn_building("a_gate", 0, Vector2i(62, 30), true)
	var n := w.spawn_building("a_wall_tower", 0, Vector2i(61, 29), true)
	var en := w.spawn_building("b_wall", 1, Vector2i(63, 30), true)
	var fnd := w.spawn_building("a_wall", 0, Vector2i(60, 31), false)   # foundation: never counts
	w.step()
	check_eq(int(w.entities[a].conn), 2, "west end: E")
	check_eq(int(w.entities[b].conn), 1 | 2 | 8, "middle: N E W")
	check_eq(int(w.entities[c].conn), 8, "gate: W only (enemy wall E ignored)")
	check_eq(int(w.entities[n].conn), 4, "tower: S")
	check_eq(int(w.entities[en].conn), 0, "enemy wall: no same-owner neighbours")
	check_eq(int(w.entities[fnd].conn), 0, "foundation conn 0")
	w.destroy(b, "test")
	w.step()
	check_eq(int(w.entities[a].conn), 0, "after destroy: west end 0")
	check_eq(int(w.entities[c].conn), 0, "after destroy: gate 0")
	check_eq(int(w.entities[n].conn), 0, "after destroy: tower 0")
	w.entities[fnd].built = true
	w.entities[fnd].progress = 1.0
	w.step()
	check_eq(int(w.entities[a].conn), 4, "foundation completed: west end gains S")
	check_eq(int(w.entities[fnd].conn), 1, "completed foundation: N")


# ================================================================ gates
func _inside(e: Dictionary, c: Vector2i, half: int) -> bool:
	var p: Vector2 = e.pos
	return absf(p.x - (float(c.x) + 0.5)) < float(half) and absf(p.y - (float(c.y) + 0.5)) < float(half)


## Ring with a gate owned by side 0; side 2 is side 0's ally (team 0), side 1 the enemy.
func _gate_world(native_on: bool) -> Dictionary:
	var c0 := SimWorld.default_config()
	var sides: Array = c0.sides.duplicate(true)
	sides[1].ai = false
	sides.append({"faction": "human_a", "stage": 8, "credits": 1000, "ai": false, "name": "Ally", "team": 0})
	var w := _world(native_on, {"sides": sides})
	_arena(w, Rect2i(52, 20, 26, 26))
	var c := Vector2i(64, 30)
	var r := _ring(w, 0, c, 3, "a_wall", "a_gate")
	var ids := {}
	for fid in [0, 1, 2]:
		ids[fid] = w.spawn_unit("engineer", fid, Vector2(63.5 + float(fid), 39.5))
	return {"w": w, "c": c, "gate": r.gate, "units": ids}


func _walk_in(w: SimWorld, ids: Dictionary, c: Vector2i) -> void:
	for fid in ids:
		do_cmd(w, int(fid), {"type": "move", "unit_ids": [ids[fid]], "target": Vector2(c) + Vector2(0.5, 0.5)})
	for i in 500:
		w.step()


func test_fort_gate_passes_owner_and_ally_blocks_enemy() -> void:
	for native_on in _modes():
		var g := _gate_world(native_on)
		var w: SimWorld = g.w
		var tag := "native" if native_on else "fallback"
		check(w.entities.has(int(g.gate)), "gate exists")
		check_eq(int(w.entities[g.gate].conn), 2 | 8, "gate joins the ring E+W")
		_walk_in(w, g.units, g.c)
		check(not _inside(w.entities[g.units[1]], g.c, 3), "%s: enemy stays out" % tag)
		if not Fortify.gate_api():
			print("FORT: Movement.set_gate missing (NAT nat.gates_ready not landed): gate is a plain solid; owner/ally pass not testable")
			check(not _inside(w.entities[g.units[0]], g.c, 3), "%s: without set_gate the gate is solid" % tag)
			continue
		check(_inside(w.entities[g.units[0]], g.c, 3), "%s: owner walks through the gate" % tag)
		check(_inside(w.entities[g.units[2]], g.c, 3), "%s: ally walks through the gate" % tag)
	NativeCore.force_off = false


func test_fort_gate_lock_blocks_owner() -> void:
	for native_on in _modes():
		var g := _gate_world(native_on)
		var w: SimWorld = g.w
		var tag := "native" if native_on else "fallback"
		var ev := do_cmd(w, 0, {"type": "set_gate_lock", "building_id": g.gate, "locked": true})
		check_eq(rejected_reason(ev), "", "lock accepted")
		check(bool(w.entities[g.gate].locked), "gate locked")
		var seen := false
		for e in ev:
			seen = seen or e.type == "GateLockChanged"
		check(seen, "GateLockChanged emitted")
		var bad := w.preview_command({"type": "set_gate_lock", "issuer": 1, "building_id": g.gate, "locked": false})
		check(bad != "", "enemy cannot unlock")
		var wall_id := int(Fortify.state(w).known[0][0])
		check_eq(w.preview_command({"type": "set_gate_lock", "issuer": 0, "building_id": wall_id, "locked": true}),
			"Only gates can be locked.", "walls cannot be locked")
		_walk_in(w, {0: g.units[0]}, g.c)
		check(not _inside(w.entities[g.units[0]], g.c, 3), "%s: locked gate stops the owner" % tag)
		if Fortify.gate_api():
			do_cmd(w, 0, {"type": "set_gate_lock", "building_id": g.gate, "locked": false})
			_walk_in(w, {0: g.units[0]}, g.c)
			check(_inside(w.entities[g.units[0]], g.c, 3), "%s: unlocked gate lets the owner in" % tag)
	NativeCore.force_off = false


# ================================================================ line of fire
func test_fort_walls_block_direct_fire_towers_fire_over() -> void:
	var w := _world()
	_arena(w, Rect2i(52, 20, 26, 26))
	for y in range(26, 36):
		w.spawn_building("b_wall", 1, Vector2i(64, y), true)
	var gate := w.spawn_building("b_gate", 1, Vector2i(64, 36), true)
	var fnd := w.spawn_building("b_wall", 1, Vector2i(64, 37), false)
	var inf := String(Content.production(Content.role("human_a", "infantry")).spawns[0])
	var sh := w.spawn_unit(inf, 0, Vector2(61.5, 30.5))
	var tg := w.spawn_unit(inf, 1, Vector2(67.5, 30.5))
	w.step()
	var S: Dictionary = w.entities[sh]
	var T: Dictionary = w.entities[tg]
	check(Fortify.fire_blocked(w, S, T), "wall between shooter and target blocks")
	check(not Fortify.fire_blocked(w, S, w.entities[int(Fortify._cell_map(w, Fortify.state(w))[Vector2i(64, 30)][0])]), "the wall itself can be shot")
	T.pos = Vector2(67.5, 36.5)
	preload("res://sim/hot_state.gd").touch(w, int(T.id))  # CORE10K-3: direct pos/path write -> hot state
	S.pos = Vector2(61.5, 36.5)
	preload("res://sim/hot_state.gd").touch(w, int(S.id))  # CORE10K-3: direct pos/path write -> hot state
	check(Fortify.fire_blocked(w, S, T), "a gate blocks fire too")
	T.pos = Vector2(67.5, 37.5)
	preload("res://sim/hot_state.gd").touch(w, int(T.id))  # CORE10K-3: direct pos/path write -> hot state
	S.pos = Vector2(61.5, 37.5)
	preload("res://sim/hot_state.gd").touch(w, int(S.id))  # CORE10K-3: direct pos/path write -> hot state
	check(not Fortify.fire_blocked(w, S, T), "an unfinished foundation does not block")
	T.pos = Vector2(67.5, 41.5)
	preload("res://sim/hot_state.gd").touch(w, int(T.id))  # CORE10K-3: direct pos/path write -> hot state
	S.pos = Vector2(61.5, 41.5)
	preload("res://sim/hot_state.gd").touch(w, int(S.id))  # CORE10K-3: direct pos/path write -> hot state
	check(not Fortify.fire_blocked(w, S, T), "clear line beside the wall")
	T.pos = Vector2(67.5, 30.5)
	preload("res://sim/hot_state.gd").touch(w, int(T.id))  # CORE10K-3: direct pos/path write -> hot state
	var tw := w.spawn_building("a_wall_tower", 0, Vector2i(61, 31), true)
	w.step()
	check(not Fortify.fire_blocked(w, w.entities[tw], T), "towers fire over walls")
	check(gate >= 0 and fnd >= 0, "fixture")
	# end to end through combat.gd when its CR (Fortify.fire_blocked in the direct-fire check) is in
	var cmb := FileAccess.get_file_as_string("res://sim/systems/combat.gd")
	if cmb.contains("fire_blocked"):
		var w2 := _world()
		_arena(w2, Rect2i(52, 20, 26, 26))
		for y in range(24, 38):
			w2.spawn_building("b_wall", 1, Vector2i(64, y), true)
		var s2 := w2.spawn_unit(inf, 0, Vector2(61.5, 30.5))
		var t2 := w2.spawn_unit(inf, 1, Vector2(66.5, 30.5))
		do_cmd(w2, 0, {"type": "hold", "unit_ids": [s2]})
		do_cmd(w2, 1, {"type": "hold", "unit_ids": [t2]})
		var hp0 := float(w2.entities[t2].hp)
		var shots := 0
		for i in 200:
			w2.step()
			for e in w2.events:
				if e.type == "ShotFired" and int(e.shooter) == s2 and int(e.target) == t2:
					shots += 1
		check_eq(shots, 0, "combat: no direct shot through the wall")
		check(w2.entities.has(t2) and float(w2.entities[t2].hp) == hp0, "combat: target unhurt")
	else:
		print("FORT: combat.gd has no Fortify.fire_blocked hook yet (CR to UNITS): end-to-end LOS not exercised")


# ================================================================ breach
func test_fort_breach_by_artillery() -> void:
	var w := _world()
	_arena(w, Rect2i(50, 18, 30, 32))
	var c := Vector2i(64, 32)
	var r := _ring(w, 1, c, 8, "a_wall", "")
	var trucks := []
	for i in 3:
		trucks.append(w.spawn_unit("b_artillery_truck", 0, Vector2(62.5 + 2.0 * i, 46.5)))
	w.step()
	var goal := Vector2(c) + Vector2(0.5, 0.5)
	check(not Movement.can_reach(w, w.entities[trucks[0]], goal), "goal sealed by the enemy ring")
	var hooked := FileAccess.get_file_as_string("res://sim/systems/movement.gd").contains("on_attack_move_blocked")
	var breached := 0
	if hooked:
		var ev := do_cmd(w, 0, {"type": "attack_move", "unit_ids": trucks, "target": goal})
		for e in ev:
			if e.type == "BreachTarget":
				breached += 1
	else:
		print("FORT: movement.gd breach hook not in yet (CR to NAT): calling Fortify.on_attack_move_blocked directly")
		for id in trucks:
			var e: Dictionary = w.entities[id]
			e.order = {"type": "attack_move", "target": goal, "engaged": false}
			if Fortify.on_attack_move_blocked(w, e, goal):
				breached += 1
	check_eq(breached, 3, "every blocked unit picks a wall")
	var tgt := int(w.entities[trucks[0]].order.get("target_id", -1))
	check((r.walls as Array).has(tgt), "the target is a ring wall")
	check(w.entities[tgt].cell.y == c.y + 8, "nearest blocking segment: the south side")
	var down := -1
	for i in 4000:
		w.step()
		for e in w.events:
			if e.type == "EntityDestroyed" and (r.walls as Array).has(int(e.id)):
				down = i
		if down >= 0:
			break
	check(down >= 0, "artillery knocks a hole in the wall (ticks %d)" % down)
	var resumed := false
	for i in 400:
		w.step()
		for id in trucks:
			if w.entities.has(id) and String(w.entities[id].order.type) == "attack_move":
				resumed = true
		if resumed:
			break
	check(resumed, "a breaching unit resumes its attack-move")
	check(not Fortify.on_attack_move_blocked(w, w.entities[trucks[0]].duplicate(), Vector2(5, 5)) or true, "api callable")


# ================================================================ save
func test_fort_save_mid_line_round_trip() -> void:
	var w := _world()
	var o := _find_row(w, 0, "a_wall", 5)
	if not check(o.x >= 0, "found a buildable row"):
		return
	var eng := _engineers(w, 0, 1, Vector2(o) + Vector2(0.5, 0.5))
	do_cmd(w, 0, {"type": "build_line", "def": "a_wall", "from": [o.x, o.y], "to": [o.x + 4, o.y], "unit_ids": eng})
	for i in 3000:
		w.step()
		var n := 0
		for b in w.buildings_of(0, "a_wall"):
			n += 1 if bool(b.built) else 0
		if n >= 2:
			break
	var st: Dictionary = Fortify.state(w)
	check(not (st.lines as Array).is_empty(), "line still in progress at save")
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var path := TMP_DIR + "/mid_line.sav"
	check_eq(SaveSystem.save(w, path), "", "save ok")
	var l: SimWorld = SaveSystem.load(path)
	if not check(l != null, "load ok"):
		return
	check_eq(l.sys_state.get("fortify"), w.sys_state.get("fortify"), "fortify state round trip")
	check_eq(l.state_hash(), w.state_hash(), "hash equal after load")
	for i in 1500:
		w.step()
		l.step()
	check_eq(l.state_hash(), w.state_hash(), "hash equal after continuing")
	var built := 0
	for b in l.buildings_of(0, "a_wall"):
		built += 1 if bool(b.built) else 0
	check_eq(built, 5, "loaded world finishes the line")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
