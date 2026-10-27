extends "res://tests/test_base.gd"
## G7 SQUAD7: formations rebuilt like a real military, movement technique by threat, halts, bounding, backing off,
## building clearing, convoys. make_world() gives an inert side 1; the whole map is cleared to grass first.

const Movement = preload("res://sim/systems/movement.gd")
const SquadAI = preload("res://sim/systems/squad_ai.gd")
const F7 = preload("res://sim/systems/formations7.gd")
const Convoy = preload("res://sim/systems/convoy.gd")
const C := Vector2(0.5, 0.5)
const M := 7.0   # metres per tile


func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for i in t.size():
		t[i] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	return w


func _spawn(w: SimWorld, def: String, fid: int, cell: Vector2i, squad := -1) -> int:
	var mc: String = Movement.udef(def).mc
	var id := w.spawn_unit(def, fid, Vector2(Movement.nearest_free_cell(w, cell, mc)) + C)
	if squad >= 0:
		w.entities[id].squad = squad
	SquadAI.touch(w)
	return id


func _units(w: SimWorld, defs: Array, at: Vector2i, form: String, squad := -1) -> Array:
	var us := []
	for k in defs.size():
		var e: Dictionary = w.entities[_spawn(w, String(defs[k]), 0, at + Vector2i(k % 4, k / 4), squad)]
		e.formation = form
		us.append(e)
	return us


func _nn(pts: Array) -> Array:   # [min, max] nearest-neighbour distance in tiles
	var lo := INF
	var hi := 0.0
	for i in pts.size():
		var best := INF
		for j in pts.size():
			if i != j:
				best = minf(best, Vector2(pts[i]).distance_to(pts[j]))
		lo = minf(lo, best)
		hi = maxf(hi, best)
	return [lo, hi]


func _seg_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var d1 := (b - a).cross(c - a)
	var d2 := (b - a).cross(d - a)
	var d3 := (d - c).cross(a - c)
	var d4 := (d - c).cross(b - c)
	return d1 * d2 < 0.0 and d3 * d4 < 0.0


func test_staggered_column_spacing_and_alternating_sides() -> void:
	var w := _world()
	var us := _units(w, ["rifleman"].duplicate().map(func(x): return x) + ["rifleman", "rifleman", "rifleman", "rifleman", "rifleman", "rifleman", "rifleman", "rifleman"], Vector2i(40, 60), "staggered_column")
	var target := Vector2(40.5, 30.5)   # straight up: fwd = (0, -1), side = (1, 0)
	var slots := Movement.formation_slots(w, us, target)
	var nn := _nn(slots)
	check(nn[0] * M >= 5.0 and nn[1] * M <= 10.0, "foot staggered column: nearest neighbour 5-10 m (got %.1f-%.1f m)" % [nn[0] * M, nn[1] * M])
	var ordered := slots.duplicate()
	ordered.sort_custom(func(a, b): return a.y < b.y)
	var alt := 0
	for i in range(1, ordered.size()):
		if signf(ordered[i].x - 40.5) != signf(ordered[i - 1].x - 40.5):
			alt += 1
	check(alt >= ordered.size() - 2, "two offset files, alternating sides (%d alternations of %d)" % [alt, ordered.size() - 1])
	var vs := _units(w, ["ifv", "mbt", "ifv", "mbt"], Vector2i(70, 80), "staggered_column")
	var vslots := Movement.formation_slots(w, vs, Vector2(70.5, 20.5))
	check(_nn(vslots)[0] * M >= 50.0, "vehicle staggered column: 50 m+ apart (got %.0f m)" % (_nn(vslots)[0] * M))


func test_wedge_and_diamond_layout() -> void:
	var w := _world()
	var defs := ["rifleman", "rifleman", "b_heavy_rifle", "rifleman", "rifleman", "b_heavy_rifle", "rifleman", "rifleman", "rifleman"]
	for form in ["wedge", "diamond"]:
		var us := _units(w, defs, Vector2i(40, 70), form)
		var target := Vector2(40.5, 40.5)
		var slots := Movement.formation_slots(w, us, target)
		var lead := 0
		for k in us.size():
			if int(us[k].id) < int(us[lead].id):
				lead = k
		var front := true
		for k in slots.size():
			if k != lead and slots[k].y < slots[lead].y - 0.01:
				front = false
		check(front and absf(slots[lead].x - 40.5) < 0.6, "%s: leader at the front centre" % form)
		var left := 0
		var right := 0
		for p in slots:
			if p.x < 40.0:
				left += 1
			elif p.x > 41.0:
				right += 1
		check(left >= 3 and right >= 3, "%s: fire teams on both sides (%d left, %d right)" % [form, left, right])
		for k in us.size():
			if String(us[k].def) == "b_heavy_rifle":
				check(absf(slots[k].x - 40.5) >= 1.5, "%s: automatic rifle on a flank (lateral %.2f)" % [form, absf(slots[k].x - 40.5)])
		check(_nn(slots)[0] * M >= 5.0, "%s: real spacing, no clump (%.1f m)" % [form, _nn(slots)[0] * M])
		for e in us:
			w.entities.erase(int(e.id))


func test_spacing_widens_under_threat_and_every_member_has_a_sector() -> void:
	var w := _world()
	var us := _units(w, ["rifleman", "rifleman", "rifleman", "rifleman", "rifleman", "rifleman", "rifleman", "rifleman"], Vector2i(40, 70), "box")
	var a: float = _nn(Movement.formation_slots(w, us, Vector2(40.5, 40.5)))[0]
	var secs := {}
	for e in us:
		check(e.has("f7_sec") and e.has("f7_hd"), "unit %d has a sector of fire" % int(e.id))
		secs[int(e.get("f7_sec", -1))] = true
	check(secs.size() == 4, "box covers front, both flanks and rear (%s)" % str(secs.keys()))
	F7.note_threat(w, us[0], 200)
	var b: float = _nn(Movement.formation_slots(w, us, Vector2(40.5, 40.5)))[0]
	check(b >= a * 1.4, "spacing widens under a threat flag (%.2f -> %.2f tiles)" % [a, b])


func test_squeeze_through_gap_then_reopen_and_no_slot_in_buildings() -> void:
	var w := _world()
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	for x in range(20, 61):
		if x < 39 or x > 41:
			t[40 * mw + x] = Terrain.BUILDING   # a wall with a 3-tile gap at x 39..41
	for y in range(50, 54):
		for x in range(44, 48):
			t[y * mw + x] = Terrain.BUILDING     # a house right on the next target
	w.map.terrain = t
	Movement.rebuild_nav(w)
	var us := _units(w, ["rifleman", "rifleman", "rifleman", "rifleman", "rifleman", "rifleman", "rifleman"], Vector2i(38, 70), "line")
	var gap := Movement.formation_slots(w, us, Vector2(40.5, 40.5))
	var lo := INF
	var hi := -INF
	for p in gap:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
		check(Movement.is_passable(w, Vector2i(floori(p.x), floori(p.y)), "foot"), "gap slot (%.1f, %.1f) is passable" % [p.x, p.y])
	check(hi - lo <= 3.0, "the line squeezes to file through the gap (width %.1f)" % (hi - lo))
	var open := Movement.formation_slots(w, us, Vector2(39.5, 58.5))
	lo = INF
	hi = -INF
	for p in open:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	check(hi - lo >= 5.0, "in the open the line reopens (width %.1f)" % (hi - lo))
	for p in Movement.formation_slots(w, us, Vector2(45.5, 51.5)):
		check(w.terrain_at(Vector2i(floori(p.x), floori(p.y))) != Terrain.BUILDING, "no slot inside a building (%.1f, %.1f)" % [p.x, p.y])


func test_reforming_assignment_has_no_crossings() -> void:
	var w := _world()
	var us := []
	for k in 10:
		var e: Dictionary = w.entities[_spawn(w, "rifleman", 0, Vector2i(30 + (k * 7) % 11, 50 + (k * 5) % 9))]
		us.append(e)
	var pts := []
	var roles := []
	for k in 10:
		pts.append(Vector2(32.5 + float(k % 5) * 1.3, 40.5 + float(k / 5) * 1.3))
		roles.append(F7.ROLE_RIFLE)
	var perm := F7.assign(us, pts, roles)
	var crossings := 0
	for i in 10:
		for j in range(i + 1, 10):
			if i == perm.find(0) or j == perm.find(0):
				continue
			if _seg_cross(us[i].pos, pts[perm[i]], us[j].pos, pts[perm[j]]):
				crossings += 1
	check(crossings == 0, "nobody crosses through another while reforming (%d crossings)" % crossings)


func test_technique_by_threat() -> void:
	check(F7.technique_for(INF, false) == 0, "no threat: traveling")
	check(F7.technique_for(30.0, false) == 1, "contact possible: traveling overwatch")
	check(F7.technique_for(10.0, false) == 2, "contact expected: bounding overwatch")
	check(F7.technique_for(INF, true) == 2, "under fire: bounding overwatch")
	check(F7.gait_for(INF, 0.0, true) == 0 and F7.gait_for(25.0, 0.0, true) == 1 and F7.gait_for(8.0, 0.0, false) == 2 \
		and F7.gait_for(8.0, 0.0, true) == 3 and F7.gait_for(INF, 80.0, true) == 3, "gait: walk / crouch / duck-run / sprint")
	var w := _world()
	var ids := []
	for k in 4:
		ids.append(_spawn(w, "rifleman", 0, Vector2i(30 + k, 60), 7001))
	_spawn(w, "rifleman", 1, Vector2i(31, 50))
	for i in 60:
		w.step()
	check(int(w.entities[ids[0]].get("f7_tech", 0)) == 2, "a squad 10 tiles from the enemy picks bounding overwatch (got %d)" % int(w.entities[ids[0]].get("f7_tech", 0)))


func test_halts_herringbone_coil_and_infantry_ring() -> void:
	var hb := F7.herringbone([Vector2(10, 10), Vector2(10, 14), Vector2(10, 18), Vector2(10, 22)], Vector2(0, -1))
	check(signf(hb[1][0].x - 10.0) != signf(hb[2][0].x - 10.0), "herringbone: vehicles angle off alternately")
	check(int(hb[0][1]) == -90 and absi(int(hb[3][1])) == 90 or int(hb[3][1]) == 90, "herringbone: lead faces front, tail faces rear")
	var co := F7.coil(6, Vector2(20, 20), 4.0, Vector2(0, -1))
	var outward := true
	for p in co:
		if F7.dir_of(int(p[1])).dot((Vector2(p[0]) - Vector2(20, 20)).normalized()) < 0.95:
			outward = false
	check(outward, "coil: every vehicle faces outward")
	var w := _world()
	var ids := []
	for k in 6:
		ids.append(_spawn(w, "rifleman", 0, Vector2i(40 + k, 40), 7002))
	for i in 140:
		w.step()
	var cen := Vector2.ZERO
	for id in ids:
		cen += Vector2(w.entities[id].pos)
	cen /= 6.0
	var secs := {}
	var ring := true
	for id in ids:
		var e: Dictionary = w.entities[id]
		secs[int(e.get("f7_sec", -1))] = true
		if Vector2(e.pos).distance_to(cen) < 0.5:
			ring = false
	check(int(w.entities[ids[0]].get("f7_ring", 0)) >= 1 and ring, "an idle squad forms a 360 degree security ring")
	check(secs.size() >= 3, "ring members watch different sectors (%s)" % str(secs.keys()))
	var vids := []
	for k in 3:
		vids.append(_spawn(w, "ifv", 0, Vector2i(60, 20 + k * 5), 7003))
	for i in 250:
		w.step()
	check(w.entities[vids[1]].has("f7_hb"), "a halted vehicle squad angles into a herringbone (f7_hb)")


func test_bounding_alternates_teams() -> void:
	var w := _world()
	var ids := []
	for k in 6:
		ids.append(_spawn(w, "rifleman", 0, Vector2i(40 + k, 80), 7004))
	SquadAI.apply_command(w, {"type": "set_technique", "issuer": 0, "unit_ids": ids, "technique": "bounding_overwatch"})
	Movement.apply_command(w, {"type": "move", "issuer": 0, "unit_ids": ids, "target": Vector2(42.5, 30.5)})
	var held := {0: false, 1: false}
	for i in 600:
		w.step()
		for k in ids.size():
			var e = w.entities.get(ids[k])
			if e != null and e.has("f7_bw"):
				held[0 if (k == 0 or (k - 1) % 2 == 0) else 1] = true
	check(held[0] and held[1], "teams A and B both halted to cover in turns (A %s, B %s)" % [held[0], held[1]])
	var moved := Vector2(w.entities[ids[0]].pos).y < 60.0
	check(moved, "the bounding squad still advances (leader y %.1f)" % Vector2(w.entities[ids[0]].pos).y)


func test_backing_off_keeps_facing_and_broken_turn() -> void:
	var w := _world()
	var ids := []
	for k in 4:
		ids.append(_spawn(w, "rifleman", 0, Vector2i(40 + k, 40), 7005))
	SquadAI.apply_command(w, {"type": "fall_back", "issuer": 0, "unit_ids": ids, "target": Vector2(41.5, 55.5)})
	for id in ids:
		var e: Dictionary = w.entities[id]
		check(bool(e.order.get("bk", false)), "fall-back order walks backwards (bk)")
		var face := F7.dir_of(int(e.get("f7_hd", 0)))
		check(face.dot(Vector2(e.order.target) - Vector2(e.pos)) < 0.0, "unit %d faces away from its retreat (toward the enemy)" % id)
	var b: Dictionary = w.entities[ids[0]]
	b.broken = true
	b.order = {"type": "idle"}
	SquadAI.fall_back(w, [b], Vector2(41.5, 70.5))
	check(not bool(b.order.get("bk", false)), "a broken unit never backs off facing the enemy")


func test_convoy_keeps_formation_and_escort_interposes() -> void:
	var w := _world()
	var ids := []
	ids.append(_spawn(w, "ifv", 0, Vector2i(50, 70)))
	for k in 3:
		ids.append(_spawn(w, "logistics_truck", 0, Vector2i(50, 74 + k * 4)))
	ids.append(_spawn(w, "ifv", 0, Vector2i(50, 88)))
	var cid := Convoy.form(w, 0, ids)
	check(cid > 0, "convoy formed")
	var c := Convoy._conv(w, cid)
	check((c.core as Array).size() == 3 and (c.col as Array).size() == 5, "core = 3 trucks in the centre, escorts lead and rear")
	Convoy.move(w, cid, Vector2(50.5, 5.5))
	for i in 260:
		w.step()
	var col: Array = c.col
	var gaps := []
	for k in range(1, col.size()):
		gaps.append(Vector2(w.entities[col[k]].pos).distance_to(w.entities[col[k - 1]].pos))
	var ok := true
	for g in gaps:
		if g < 2.0 or g > 6.5:
			ok = false
	check(ok, "the convoy keeps its spacing on the move (%s)" % str(gaps))
	var en := _spawn(w, "rifleman", 1, Vector2i(58, int(Vector2(w.entities[col[2]].pos).y) - 6))
	w.entities[en].order = {"type": "hold_fire"}
	w.entities[en].hp = 1000000.0   # the threat must stay alive while we watch the escort
	var best := INF
	for i in 200:
		w.step()
		var core := Vector2(w.entities[col[2]].pos)
		var tp := Vector2(w.entities[en].pos) if w.entities.has(en) else core
		for id in Convoy.members(c):
			if (c.core as Array).has(id) or not w.entities.has(id):
				continue
			var p := Vector2(w.entities[id].pos)
			var t := clampf((p - core).dot(tp - core) / maxf((tp - core).length_squared(), 0.01), 0.0, 1.0)
			best = minf(best, p.distance_to(core.lerp(tp, t)))
	check(best <= 2.0, "an escort drives between the threat and the core (closest %.2f tiles off the line)" % best)


func test_clear_building_stacks_and_opens_the_roof() -> void:
	var w := _world()
	var bid := -1
	for e in w.entities.values():
		if e.kind == "building" and int(e.owner) == 0 and SimWorld.Garrison.slots_of(String(e.def)) > 0:
			bid = int(e.id)
	if bid < 0 and Content.building("s_garrison_bld").size() > 0:
		bid = w.spawn_building("s_garrison_bld", 0, Vector2i(60, 60), true)
	if bid < 0:
		check(true, "no garrisonable building in this world (skipped)")
		return
	var b: Dictionary = w.entities[bid]
	b.built = true
	var ids := []
	for k in 3:
		ids.append(_spawn(w, "rifleman", 0, Vector2i(int(b.pos.x) + 6 + k, int(b.pos.y) + 6)))
	SimWorld.Garrison.apply_command(w, {"type": "clear_building", "issuer": 0, "unit_ids": ids, "building_id": bid})
	check(int(w.entities[ids[0]].get("f7_clr", 0)) == 1, "the squad stacks at the door")
	var roof := false
	for i in 600:
		w.step()
		if int(b.get("roof_open", -1)) == 0:
			roof = true
	check(roof, "the roof opens while own troops are inside")


func test_same_seed_same_hash() -> void:
	var hs := []
	for run in 2:
		var w := _world()
		var ids := []
		for k in 6:
			ids.append(_spawn(w, "rifleman", 0, Vector2i(40 + k, 80), 7006))
		for e in ids:
			w.entities[e].formation = "wedge"
		_spawn(w, "rifleman", 1, Vector2i(42, 55))
		Movement.apply_command(w, {"type": "move", "issuer": 0, "unit_ids": ids, "target": Vector2(42.5, 50.5)})
		var cid := Convoy.form(w, 0, [_spawn(w, "ifv", 0, Vector2i(70, 70)), _spawn(w, "logistics_truck", 0, Vector2i(70, 74)), _spawn(w, "ifv", 0, Vector2i(70, 78))])
		Convoy.move(w, cid, Vector2(70.5, 40.5))
		for i in 300:
			w.step()
		hs.append(w.state_hash())
	check(hs[0] == hs[1], "same seed and commands give the same hash (%s / %s)" % [hs[0], hs[1]])


## G7 (SQUAD7-2): an ordinary player group move without a chosen formation uses a real formation by default
## (rules default_player_formation "auto"), not the G1 grid; AI sides, cmd.grid and a chosen formation keep theirs.
func _move_ids(w: SimWorld, fid: int, ids: Array, target: Vector2, extra := {}) -> Array:
	var cmd := {"type": "move", "unit_ids": ids, "target": target}
	cmd.merge(extra)
	do_cmd(w, fid, cmd)
	var out := []
	for id in ids:
		out.append(Vector2(w.entities[id].order.get("target", w.entities[id].pos)))
	return out


func test_player_moves_default_to_a_real_formation() -> void:
	check_eq(F7.player_default(), "auto", "rules default_player_formation is auto")
	var w := _world()
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	for y in range(4, 92):
		t[y * mw + 70] = Terrain.ROAD                      # a north-south road at x = 70
	for y in range(8, 20):
		for x in range(14, 30):
			if (x + y) % 5 != 0:
				t[y * mw + x] = Terrain.FOREST           # a wood with a few lanes
	w.map.terrain = t
	Movement.rebuild_nav(w)
	var ids := []
	for k in 7:
		ids.append(_spawn(w, "rifleman", 0, Vector2i(40 + k % 4, 70 + k / 4)))
	# open ground: a wedge (leader slot in front, the rest fanning back), not a grid
	var open := _move_ids(w, 0, ids, Vector2(40.5, 40.5))
	check_eq(String(w.entities[ids[0]].get("f7_auto", "")), "wedge", "open ground -> wedge")
	var grid := _move_ids(w, 0, ids, Vector2(40.5, 40.5), {"grid": true})
	check(not w.entities[ids[0]].has("f7_auto"), "cmd.grid clears the default")
	var so := open.duplicate()
	var sg := grid.duplicate()
	so.sort()
	sg.sort()
	check(so != sg, "the default wedge is not the G1 grid")
	var nn := _nn(open)
	check(nn[0] >= 0.8, "wedge members keep >= 0.8 tiles (~6 m) apart (min %.2f)" % nn[0])
	# a road at the goal: staggered column bending along it
	var road := _move_ids(w, 0, ids, Vector2(70.5, 40.5))
	check_eq(String(w.entities[ids[0]].get("f7_auto", "")), "staggered_column", "road -> staggered column")
	var ys := []
	for p in road:
		ys.append(p.y)
	check(ys.max() - ys.min() >= 4.0, "the column strings out along the road (depth %.1f)" % (ys.max() - ys.min()))
	# close terrain: file
	_move_ids(w, 0, ids, Vector2(22.5, 14.5))
	check_eq(String(w.entities[ids[0]].get("f7_auto", "")), "file", "wood -> file")
	# a long selection stays out of a column (its tail would stop far behind the click)
	var many := ids.duplicate()
	for k in 30:
		many.append(_spawn(w, "rifleman", 0, Vector2i(50 + k % 6, 60 + k / 6)))
	_move_ids(w, 0, many, Vector2(70.5, 30.5))
	check_eq(String(w.entities[many[0]].get("f7_auto", "")), "wedge", "37 men on a road -> wedges abreast")
	# enemy close to the goal: wedge even on the road
	_spawn(w, "rifleman", 1, Vector2i(70, 52))
	F7.build_grid(w, w.entities.values().filter(func(e): return e.kind == "unit"))
	_move_ids(w, 0, ids, Vector2(70.5, 44.5))
	check_eq(String(w.entities[ids[0]].get("f7_auto", "")), "wedge", "enemy expected -> wedge")
	# a chosen formation wins
	for id in ids:
		w.entities[id].formation = "line"
	var line := _move_ids(w, 0, ids, Vector2(40.5, 40.5))
	var lys := []
	var lxs := []
	for p in line:
		lys.append(p.y)
		lxs.append(p.x)
	check(lys.max() - lys.min() <= 0.6 and lxs.max() - lxs.min() >= 5.0, "the player's chosen line stays one rank %s" % str(line))
	# AI sides keep their own choices (no default stamped)
	var w2 := _world()
	w2.ai_state = {0: {}}
	var ai_ids := []
	for k in 5:
		ai_ids.append(_spawn(w2, "rifleman", 0, Vector2i(40 + k, 70)))
	Movement.apply_command(w2, {"type": "move", "unit_ids": ai_ids, "target": Vector2(40.5, 40.5), "issuer": 0})   # no step: AI brain not set up
	check(String(w2.entities[ai_ids[0]].order.get("type", "")) == "move", "the AI move was applied")
	check(not w2.entities[ai_ids[0]].has("f7_auto"), "an AI-side move gets no player default")


## G7 (WOUND7 CR seq 102): casualty care keys are Shift chords (Shift+T first aid, Shift+E evacuate), rebindable,
## collision-free; Shift+<letter> without a registered chord still reaches the plain-letter button.
func test_casualty_hotkeys_are_shift_chords() -> void:
	var HK = load("res://presentation/ui5/panels/hotkeys.gd")
	check_eq(HK.key("treat_casualty"), "SHIFT+T", "treat_casualty default Shift+T")
	check_eq(HK.key("evacuate_casualty"), "SHIFT+E", "evacuate_casualty default Shift+E")
	check_eq(HK.badge("SHIFT+T"), "Sh+T", "badge for a Shift chord")
	check_eq(HK.collisions().filter(func(c): return String(c).contains("casualty")), [], "no casualty key collision")
	var ev := InputEventKey.new()
	ev.keycode = KEY_T
	ev.shift_pressed = true
	check_eq(HK.event_key(ev, {"SHIFT+T": 1, "T": 1}), "SHIFT+T", "Shift+T resolves to the chord")
	check_eq(HK.event_key(ev, {"T": 1}), "T", "Shift+T falls back to T without a chord")
	ev.shift_pressed = false
	check_eq(HK.event_key(ev, {"SHIFT+T": 1, "T": 1}), "T", "plain T stays T")


## A halt after a player move: the vehicles still angle into a herringbone (f7_hb heading) but in place, since the
## player's spots stand inside the override window (player control first).
func test_player_halt_turns_in_place() -> void:
	var w := _world()
	var vids := []
	for k in 3:
		vids.append(_spawn(w, "ifv", 0, Vector2i(30, 60 + k * 6), 7004))
	_move_ids(w, 0, vids, Vector2(30.5, 30.5))
	var arrived := false
	for i in 400:
		w.step()
		if vids.all(func(id): return not bool(w.entities[id].moving)):
			arrived = true
			break
	check(arrived, "the player's vehicles arrived")
	var at := []
	for id in vids:
		at.append(Vector2(w.entities[id].pos))
	for i in 120:
		w.step()
	var hb := vids.filter(func(id): return w.entities[id].has("f7_hb"))
	check(hb.size() >= 2, "player-halted vehicles angle off (f7_hb on %d)" % hb.size())
	var moved := 0.0
	for k in vids.size():
		moved = maxf(moved, Vector2(w.entities[vids[k]].pos).distance_to(at[k]))
	check(moved <= 0.3, "the halt drill did not move the player's vehicles (max %.2f tiles)" % moved)
