extends "res://tests/test_base.gd"
## G2 agent C2: officers + missions, patrol/guard/formation, destructible bridge (QA-007).
## Contract: docs/CONTRACTS_G2.md section 4, brief .plan/agents/prompts/C2-ops.md.

const Movement = preload("res://sim/systems/movement.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Ops = preload("res://sim/systems/ops.gd")
const Bridges = preload("res://sim/systems/bridges.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const C := Vector2(0.5, 0.5)


func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	return w


func _paint(w: SimWorld, rect: Rect2i, code: int) -> void:
	var t: PackedByteArray = w.map.terrain
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			t[y * int(w.map.w) + x] = code
	w.map.terrain = t
	Movement.rebuild_nav(w)


## Open grass arena x 22..73, y 0..25 (away from both HQs), as in test_mil.
func _arena(w: SimWorld) -> void:
	_paint(w, Rect2i(22, 0, 52, 26), Terrain.GRASS)


func _spawn(w: SimWorld, def: String, fid: int, cell: Vector2i) -> int:
	var mc: String = Movement.udef(def).mc
	return w.spawn_unit(def, fid, Vector2(Movement.nearest_free_cell(w, cell, mc)) + C)


func _bridge(w: SimWorld) -> Dictionary:
	for id in w.entities:
		if w.entities[id].kind == "structure":
			return w.entities[id]
	return {}


## Road points just off each end of the bridge (the road runs along x == y).
func _banks(w: SimWorld) -> Array:
	var ymin := 1000
	var ymax := -1000
	for c in w.map.bridge_cells:
		ymin = mini(ymin, int(c.y))
		ymax = maxi(ymax, int(c.y))
	return [Vector2(ymin - 4, ymin - 4) + C, Vector2(ymax + 4, ymax + 4) + C]


func _squad(w: SimWorld, def: String, n: int, at: Vector2) -> Array:
	var ids := []
	for i in n:
		ids.append(_spawn(w, def, 0, w.cell_of(at) + Vector2i(i % 3 - 1, i / 3)))
	return ids


func _units_in_water(w: SimWorld) -> Array:
	var bad := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and w.terrain_at(w.cell_of(e.pos)) == Terrain.WATER:
			bad.append("%s#%d@%s" % [e.def, e.id, w.cell_of(e.pos)])
	return bad


func _officer_squad(w: SimWorld, at: Vector2, n: int) -> Dictionary:
	var off := _spawn(w, "officer", 0, w.cell_of(at) + Vector2i(0, -2))
	var ids := _squad(w, "rifleman", n, at)
	var ev := do_cmd(w, 0, {"type": "assign_officer", "officer_id": off, "unit_ids": ids})
	check_eq(rejected_reason(ev), "", "assign_officer accepted")
	return {"off": off, "ids": ids}


func _mission(w: SimWorld, off: int, mission: String, target: Vector2, risk: String = "medium", extra: Dictionary = {}) -> Array:
	var cmd := {"type": "set_mission", "officer_id": off, "mission": mission, "target": target, "radius": 6.0, "risk": risk}
	cmd.merge(extra, true)
	var ev := do_cmd(w, 0, cmd)
	check_eq(rejected_reason(ev), "", "set_mission %s accepted" % mission)
	return ev


func _reports(events: Array) -> Array:
	return events.filter(func(ev) -> bool: return ev.type == "OfficerReport")


# ---------------------------------------------------------------- officers
func test_ops01_secure_point_at_bridge_reaches_hold() -> void:
	var w := _world()
	var bc: Vector2 = _bridge(w).pos
	var sq := _officer_squad(w, _banks(w)[0], 6)
	var reports := _reports(_mission(w, sq.off, "secure_point", bc))
	var g := Ops.group_led_by(w, sq.off)
	for i in 1500:
		w.step()
		reports.append_array(_reports(w.events))
		if String(g.phase) == "hold":
			break
	check_eq(String(g.phase), "hold", "secure_point reaches hold")
	check_eq(float(g.progress), 1.0, "progress 1.0 in hold")
	check(reports.size() >= 3, "at least 3 OfficerReports (got %d)" % reports.size())
	var phases := []
	for r in reports:
		check(String(r.reason).length() > 10, "report has a reason sentence: '%s'" % r.reason)
		check(r.has("gid") and r.has("owner") and r.has("officer") and r.has("progress"), "report fields")
		phases.append(String(r.phase))
	for p in ["assess", "move", "secure", "hold"]:
		check(phases.has(p), "phase %s reported" % p)
	check((g.history as Array).size() >= 3 and (g.history as Array).size() <= 10, "history keeps last <= 10")
	var off: Dictionary = w.entities[sq.off]
	var inside := 0
	for id in sq.ids:
		var q: Vector2 = w.entities[id].pos
		if q.distance_to(bc) <= 6.0:
			inside += 1
	check(inside * 2 >= 6, "at least half the members inside the radius (%d)" % inside)
	var op: Vector2 = off.pos
	check(op.distance_to(bc) < 12.0, "officer stays with the group (%.1f from target)" % op.distance_to(bc))
	check(_units_in_water(w).is_empty(), "nobody in water: %s" % str(_units_in_water(w)))


func test_ops02_withdraw_on_losses_past_low_risk() -> void:
	var w := _world()
	var bc: Vector2 = _bridge(w).pos
	var sq := _officer_squad(w, _banks(w)[0], 6)
	_mission(w, sq.off, "secure_point", bc, "low")
	w.run_ticks(20)
	var g := Ops.group_led_by(w, sq.off)
	check(String(g.phase) != "withdraw", "no withdraw before losses")
	w.destroy(sq.ids[0], "killed", 1)
	w.destroy(sq.ids[1], "killed", 1)  # 2/6 = 33% > 25% low bound
	var saw := ""
	for i in 40:
		w.step()
		for r in _reports(w.events):
			if String(r.phase) == "withdraw":
				saw = String(r.reason)
	check_eq(String(g.phase), "withdraw", "withdraw triggered")
	check(saw.contains("withdraw") and saw.contains("33%"), "withdraw reason names the losses: '%s'" % saw)
	check_eq(String(g.result), "failed", "mission marked failed")
	check_eq(int(g.losses), 2, "two losses counted")
	for i in 2500:
		w.step()
		if String(g.phase) == "idle":
			break
	check_eq(String(g.phase), "idle", "withdrawal completes")
	check((g.mission as Dictionary).is_empty(), "mission ended")


func test_ops03_player_override_detaches_member() -> void:
	var w := _world()
	_arena(w)
	var sq := _officer_squad(w, Vector2(30.5, 12.5), 4)
	_mission(w, sq.off, "secure_point", Vector2(50.5, 12.5))
	var x := int(sq.ids[0])
	var mine := Vector2(30.5, 22.5)
	var ev := do_cmd(w, 0, {"type": "move", "unit_ids": [x], "target": mine})
	check_eq(rejected_reason(ev), "", "direct move accepted")
	var xe: Dictionary = w.entities[x]
	var until := int(xe.get("ops_override_until", -1))
	check(until > w.tick, "override set")
	while w.tick < until - 1:
		w.step()
		var ot := String(xe.order.type)
		if ot != "move" and ot != "idle":
			check(false, "officer moved the overridden member (order %s at tick %d)" % [ot, w.tick])
			break
	var q: Vector2 = xe.pos
	check(q.distance_to(mine) < 2.0, "member went where the player sent it (%.1f)" % q.distance_to(mine))
	check(Ops.group_of(w, x).has("id"), "member stays in the group")
	var took := false
	for i in 40:
		w.step()
		if String(xe.order.type) == "attack_move":
			took = true
			break
	check(took, "officer resumes control after override_ticks")


func test_ops04_officer_death_dissolves_group() -> void:
	var w := _world()
	_arena(w)
	var sq := _officer_squad(w, Vector2(30.5, 12.5), 3)
	_mission(w, sq.off, "secure_point", Vector2(45.5, 12.5))
	w.run_ticks(10)
	var gid := int(Ops.group_led_by(w, sq.off).id)
	var m0 := []
	for id in sq.ids:
		m0.append(float(w.entities[id].get("morale", 100.0)))
	w.destroy(sq.off, "killed", 1)
	w.step()
	var killed := w.events.filter(func(ev) -> bool: return ev.type == "OfficerKilled")
	check_eq(killed.size(), 1, "OfficerKilled emitted once")
	if killed.size() == 1:
		check_eq(int(killed[0].gid), gid, "OfficerKilled names the group")
	check(not (w.sys_state.ops.groups as Dictionary).has(gid), "group dissolved")
	check(Ops.group_of(w, int(sq.ids[0])).is_empty(), "members no longer in a group")
	for i in sq.ids.size():
		var e: Dictionary = w.entities[sq.ids[i]]
		if e.has("morale"):
			check(float(e.morale) <= float(m0[i]) - 19.0, "member morale hit (%.1f -> %.1f)" % [m0[i], e.morale])


# ---------------------------------------------------------------- orders
func test_ops05_patrol_loops_between_points() -> void:
	var w := _world()
	_arena(w)
	var u := _spawn(w, "rifleman", 0, Vector2i(30, 12))
	var p1 := Vector2(30.5, 12.5)
	var p2 := Vector2(42.5, 12.5)
	var ev := do_cmd(w, 0, {"type": "patrol", "unit_ids": [u], "points": [p1, p2]})
	check_eq(rejected_reason(ev), "", "patrol accepted")
	check(rejected_reason(do_cmd(w, 0, {"type": "patrol", "unit_ids": [u], "points": [p1]})) != "", "1 point rejected")
	check(rejected_reason(do_cmd(w, 0, {"type": "patrol", "unit_ids": [u], "points": [p1, Vector2(500, 5)]})) != "", "out of bounds rejected")
	do_cmd(w, 0, {"type": "patrol", "unit_ids": [u], "points": [p1, p2]})
	var e: Dictionary = w.entities[u]
	var visits := [0, 0]
	var at := -1
	for i in 1600:
		w.step()
		var q: Vector2 = e.pos
		var now := 0 if q.distance_to(p1) < 2.0 else (1 if q.distance_to(p2) < 2.0 else -1)
		if now >= 0 and now != at:
			visits[now] += 1
			at = now
	check(visits[0] >= 2 and visits[1] >= 2, "visits each point >= 2 times (%s)" % str(visits))
	check(e.has("patrol"), "still patrolling")
	do_cmd(w, 0, {"type": "stop", "unit_ids": [u]})
	check(not e.has("patrol"), "a direct order ends the patrol")


func test_ops06_guard_follows_moving_unit() -> void:
	var w := _world()
	_arena(w)
	var ward := _spawn(w, "rifleman", 0, Vector2i(30, 12))
	var gu := _spawn(w, "rifleman", 0, Vector2i(26, 12))
	check(rejected_reason(do_cmd(w, 0, {"type": "guard", "unit_ids": [gu], "target_id": gu})) != "", "cannot guard itself")
	var ev := do_cmd(w, 0, {"type": "guard", "unit_ids": [gu], "target_id": ward})
	check_eq(rejected_reason(ev), "", "guard accepted")
	do_cmd(w, 0, {"type": "move", "unit_ids": [ward], "target": Vector2(55.5, 20.5)})
	var g: Dictionary = w.entities[gu]
	var wd: Dictionary = w.entities[ward]
	var maxd := 0.0
	for i in 500:
		w.step()
		if i > 100:
			var q: Vector2 = g.pos
			maxd = maxf(maxd, q.distance_to(wd.pos))
	var qg: Vector2 = g.pos
	check(qg.distance_to(wd.pos) <= 4.0, "guard ends near the ward (%.1f)" % qg.distance_to(wd.pos))
	check(maxd <= 8.0, "guard keeps up while the ward moves (max %.1f)" % maxd)
	check(g.has("guard"), "still guarding")


func test_ops07_formation_slots_differ() -> void:
	var w := _world()
	_arena(w)
	var ids := []
	for i in 5:
		ids.append(_spawn(w, "rifleman", 0, Vector2i(30 + i, 12)))
	check(rejected_reason(do_cmd(w, 0, {"type": "set_formation", "unit_ids": ids, "formation": "blob"})) != "", "bad formation rejected")
	var units := []
	for id in ids:
		units.append(w.entities[id])
	var target := Vector2(32.5, 22.5)   # straight "south" of the group
	var slots := {}
	for f in ["line", "column", "wedge"]:
		check_eq(rejected_reason(do_cmd(w, 0, {"type": "set_formation", "unit_ids": ids, "formation": f})), "", "set_formation %s" % f)
		check_eq(String(units[0].formation), f, "e.formation stored")
		slots[f] = Movement.formation_slots(w, units, target)
	check(slots.line != slots.column and slots.line != slots.wedge and slots.column != slots.wedge, "slots differ")
	var ly := []
	var cx := []
	for p in slots.line:
		ly.append(snappedf(p.y, 0.01))
	for p in slots.column:
		cx.append(snappedf(p.x, 0.01))
	check(ly.count(ly[0]) == 5, "line: one rank across the direction of travel %s" % str(slots.line))
	check(cx.count(cx[0]) == 5, "column: one file along the direction of travel %s" % str(slots.column))
	do_cmd(w, 0, {"type": "set_formation", "unit_ids": ids, "formation": "column"})
	do_cmd(w, 0, {"type": "move", "unit_ids": ids, "target": target})
	w.run_ticks(200)
	var xs := []
	for u in units:
		xs.append(u.pos.x)
	check(xs.max() - xs.min() < 1.5, "column move ends in a file (x spread %.2f)" % (xs.max() - xs.min()))


# ---------------------------------------------------------------- bridge (QA-007)
## Knocks the bridge down with one explicit attack. Returns the BridgeDestroyed event or {}.
func _blow_bridge(w: SimWorld, from: Vector2) -> Dictionary:
	var br := _bridge(w)
	var tank := _spawn(w, "mbt", 0, w.cell_of(from) + Vector2i(2, 2))
	Fog.recompute(w)
	br.hp = 1.0
	var ev := do_cmd(w, 0, {"type": "attack", "unit_ids": [tank], "target_id": int(br.id)})
	check_eq(rejected_reason(ev), "", "explicit attack on the bridge accepted")
	for i in 400:
		for e in w.events:
			if e.type == "BridgeDestroyed":
				return e
		w.step()
	return {}


func test_ops08_qa007_ruined_bridge_reroutes_via_ford() -> void:
	var w := _world()
	var banks := _banks(w)
	var cells: Array = w.map.bridge_cells
	var dead := {}
	for c in cells:
		dead[c] = true
	# a rifleman standing on the near end of the span must be nudged ashore, never left in water
	var edge: Vector2i = cells[0]
	for c in cells:
		if c.x + c.y < edge.x + edge.y:
			edge = c
	var swimmer := w.spawn_unit("rifleman", 0, Vector2(edge) + C)
	var bd := _blow_bridge(w, banks[0])
	check(not bd.is_empty(), "BridgeDestroyed emitted")
	var br := _bridge(w)
	check_eq(String(br.state), "ruined", "state ruined")
	check_eq(float(br.hp), 0.0, "hp 0")
	check_eq(String(br.kind), "structure", "still a structure")
	check_eq(String(w.map.bridge_state), "ruined", "map.bridge_state ruined")
	for c in cells:
		check_eq(w.terrain_at(c), Terrain.WATER, "cell %s is water" % str(c))
	check(w.entities.has(swimmer), "unit on the span edge was nudged ashore, not drowned")
	check(_units_in_water(w).is_empty(), "nobody in water after collapse: %s" % str(_units_in_water(w)))
	var v := _spawn(w, "ifv", 0, w.cell_of(banks[0]))
	var ve: Dictionary = w.entities[v]
	var ev := do_cmd(w, 0, {"type": "move", "unit_ids": [v], "target": banks[1]})
	check_eq(rejected_reason(ev), "", "move across accepted (reachable via a ford)")
	var arrived := false
	var on_dead := 0
	var path_dead := 0
	var water := []
	for i in 4000:
		w.step()
		if dead.has(w.cell_of(ve.pos)):
			on_dead += 1
		for p in ve.path:
			if dead.has(w.cell_of(p)):
				path_dead += 1
		if water.is_empty():
			water = _units_in_water(w)
		var q: Vector2 = ve.pos
		if q.distance_to(banks[1]) < 2.5:
			arrived = true
			break
	check(arrived, "vehicle arrives on the far bank via a ford (at %s, tick %d)" % [str(ve.pos), w.tick])
	check_eq(on_dead, 0, "vehicle never on an ex-bridge cell")
	check_eq(path_dead, 0, "path never contains an ex-bridge cell")
	check(water.is_empty(), "no unit ever in a water cell: %s" % str(water))
	# a ruined span is not a target any more
	var t := _spawn(w, "rifleman", 0, w.cell_of(banks[0]))
	Fog.recompute(w)
	do_cmd(w, 0, {"type": "attack", "unit_ids": [t], "target_id": int(br.id)})
	w.run_ticks(20)
	check(String(w.entities[t].order.type) != "attack", "attack order on a ruin is dropped")
	check_eq(float(br.hp), 0.0, "ruin stays at hp 0")


func test_ops09_repair_restores_crossing() -> void:
	var w := _world()
	var banks := _banks(w)
	_blow_bridge(w, banks[0])
	var br := _bridge(w)
	Bridges.on_repaired(w, br)
	check(w.events.any(func(ev) -> bool: return ev.type == "BridgeRepaired"), "BridgeRepaired emitted")
	check_eq(String(br.state), "intact", "state intact")
	check_eq(float(br.hp), float(br.max_hp), "hp restored")
	check_eq(String(w.map.bridge_state), "intact", "map.bridge_state intact")
	var span := {}
	for c in w.map.bridge_cells:
		span[c] = true
		check_eq(w.terrain_at(c), Terrain.BRIDGE, "cell %s is bridge again" % str(c))
	var v := _spawn(w, "ifv", 0, w.cell_of(banks[0]))
	var ve: Dictionary = w.entities[v]
	do_cmd(w, 0, {"type": "move", "unit_ids": [v], "target": banks[1]})
	var crossed := false
	var arrived_at := -1
	for i in 600:
		w.step()
		if span.has(w.cell_of(ve.pos)):
			crossed = true
		var q: Vector2 = ve.pos
		if q.distance_to(banks[1]) < 2.5:
			arrived_at = i
			break
	check(crossed, "vehicle drives over the repaired bridge")
	check(arrived_at >= 0 and arrived_at < 400, "short crossing, no ford detour (%d ticks)" % arrived_at)


func test_ops10_save_round_trip_mission_and_ruin() -> void:
	var w := _world()
	var bc: Vector2 = _bridge(w).pos
	var banks := _banks(w)
	var sq := _officer_squad(w, banks[0], 5)
	_mission(w, sq.off, "secure_point", banks[0] + Vector2(-6, 0))
	w.destroy(int(_bridge(w).id), "killed", 0)
	w.run_ticks(60)
	var d := SaveSystem.decode_bytes(SaveSystem.encode_dict(w.to_dict()))
	check(d.ok, "decode ok: %s" % d.reason)
	var l := SimWorld.from_dict(d.dict)
	check_eq(l.state_hash(), w.state_hash(), "hash equal right after load")
	check_eq(String(l.map.bridge_state), "ruined", "ruin survives load")
	check_eq(l.terrain_at(w.map.bridge_cells[0]), Terrain.WATER, "ruined cells still water after load")
	check(not Movement.is_passable(l, w.map.bridge_cells[0], "foot"), "nav after load sees the ruin")
	w.run_ticks(300)
	l.run_ticks(300)
	check_eq(l.state_hash(), w.state_hash(), "hash equal after 300 ticks")
	check(not Ops.group_led_by(l, sq.off).is_empty(), "group survives load")
	check_eq(String(Ops.group_led_by(l, sq.off).phase), String(Ops.group_led_by(w, sq.off).phase), "same phase")
