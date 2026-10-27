extends "res://tests/test_base.gd"
## G6 MECH6c (CONTRACTS_G6 section 9, section 17): mobility. The bridge layer lays / packs a 1xN span over
## water <= 6, airdrops land paratroopers or a supply pallet in a 3x3 area, marines get ashore twice as fast
## from a timed (staged) beach unload.

const Mobility = preload("res://sim/systems/mobility.gd")
const Transport = preload("res://sim/systems/transport.gd")
const Movement = preload("res://sim/systems/movement.gd")


func _setup(code: int = Terrain.GRASS) -> Array:
	var w := make_world()
	w.ai_state = {}
	var mw := int(w.map.w)
	var o := Vector2i(mw / 2 - 15, int(w.map.h) / 2 - 15)
	var r := Rect2i(o, Vector2i(30, 30))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = code
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" and e.kind != "building" and r.grow(2).has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	Movement.rebuild_nav(w)
	return [w, o]


func _c(o: Vector2i, x: int, y: int) -> Vector2:
	return Vector2(o) + Vector2(x, y) + Vector2(0.5, 0.5)


func _load(w: SimWorld, c: int, u: int) -> void:
	Transport._load(w, Transport._cache(w), w.entities[c], w.entities[u])


func test_deploy_and_pack_bridge() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var mw := int(w.map.w)
	var t: PackedByteArray = w.map.terrain
	for y in int(w.map.h):   # a 4-wide river across the whole map: no way around
		for x in range(o.x + 12, o.x + 16):
			t[y * mw + x] = Terrain.WATER
	w.map.terrain = t
	Movement.rebuild_nav(w)
	var bl := w.spawn_unit("a_bridge_layer", 0, _c(o, 10, 15))
	var rifle := w.spawn_unit("rifleman", 0, _c(o, 9, 13))
	var goal := _c(o, 19, 13)
	check(not Movement.order_path(w, w.entities[rifle], goal), "no path across the river before the bridge")
	Movement.stop_path(w.entities[rifle])
	w.entities[rifle].order = {"type": "idle"}
	check(Mobility.validate_command(w, {"type": "deploy_bridge", "issuer": 0, "unit_id": rifle, "cell": [o.x + 11, o.y + 15], "dir": "e"}) != "", "only a bridge layer deploys")
	check(typeof(Mobility.span(w, Vector2i(o.x + 11, o.y + 15), Vector2i(1, 0), 3)) == TYPE_STRING, "a 4-wide gap is refused for max_len 3")
	check(typeof(Mobility.span(w, Vector2i(o.x + 5, o.y + 15), Vector2i(1, 0), 6)) == TYPE_STRING, "no water next to that cell")
	var ev := do_cmd(w, 0, {"type": "deploy_bridge", "unit_id": bl, "cell": [o.x + 11, o.y + 15], "dir": "e"})
	check(rejected_reason(ev) == "", "deploy accepted: %s" % rejected_reason(ev))
	check_eq(String(w.sys_state.mobility.bridges[bl].state), "deploying", "deploying during deploy_s")
	check_eq(w.terrain_at(Vector2i(o.x + 12, o.y + 15)), Terrain.WATER, "water until deployed")
	for i in 8 * 20 + 2:
		w.step()
	check_eq(String(w.sys_state.mobility.bridges[bl].state), "up", "bridge up after deploy_s")
	for x in range(o.x + 12, o.x + 16):
		check_eq(w.terrain_at(Vector2i(x, o.y + 15)), Terrain.BRIDGE, "span cell %d is BRIDGE" % x)
	check_eq(w.terrain_at(Vector2i(o.x + 16, o.y + 15)), Terrain.GRASS, "the far bank is untouched")
	check(Mobility.is_bridge_cell(w, Vector2i(o.x + 13, o.y + 15)), "is_bridge_cell on the span")
	check(Terrain.passable(Terrain.BRIDGE, "foot") and Terrain.passable(Terrain.BRIDGE, "vehicle"), "BRIDGE is foot + vehicle passable")
	var r: Dictionary = w.entities[rifle]
	r.order = {"type": "move", "target": goal}
	check(Movement.order_path(w, r, goal), "a path across the bridge")
	var crossed := false
	for i in 400:
		w.step()
		if Vector2(r.pos).x > float(o.x + 16):
			crossed = true
			break
	check(crossed, "the rifleman crossed the river on the bridge (at %s)" % [r.pos])
	# pack: refused while a unit stands on the span, then the river comes back
	var on := w.spawn_unit("rifleman", 0, _c(o, 13, 15))
	check_eq(Mobility.validate_command(w, {"type": "pack_bridge", "issuer": 0, "unit_id": bl}), "Units are on the bridge.", "pack refused with a unit on the span")
	w.destroy(on, "test")
	ev = do_cmd(w, 0, {"type": "pack_bridge", "unit_id": bl})
	check(rejected_reason(ev) == "", "pack accepted: %s" % rejected_reason(ev))
	check_eq(w.terrain_at(Vector2i(o.x + 13, o.y + 15)), Terrain.WATER, "packed: the river is back")
	check(not w.sys_state.mobility.bridges.has(bl), "no bridge record after packing")
	check(not Mobility.is_bridge_cell(w, Vector2i(o.x + 13, o.y + 15)), "is_bridge_cell false after packing")
	# moving the layer while deploying cancels it
	do_cmd(w, 0, {"type": "deploy_bridge", "unit_id": bl, "cell": [o.x + 11, o.y + 15], "dir": [1, 0]})
	var e: Dictionary = w.entities[bl]
	e.order = {"type": "move", "target": _c(o, 6, 15)}
	Movement.order_path(w, e, _c(o, 6, 15))
	for i in 5:
		w.step()
	check(not w.sys_state.mobility.bridges.has(bl), "moving cancels the deploy")
	check_eq(w.terrain_at(Vector2i(o.x + 12, o.y + 15)), Terrain.WATER, "no span after a cancelled deploy")


func test_airdrop_paratroopers() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var lift := w.spawn_unit("a_airlift", 0, _c(o, 3, 3))
	var p1 := w.spawn_unit("a_paratroopers", 0, _c(o, 3, 4))
	var p2 := w.spawn_unit("a_paratroopers", 0, _c(o, 4, 4))
	w.step()
	_load(w, lift, p1)
	_load(w, lift, p2)
	check(not w.entities.has(p1) and not w.entities.has(p2), "paratroopers aboard")
	check(Mobility.validate_command(w, {"type": "airdrop", "issuer": 0, "carrier_id": w.spawn_unit("rifleman", 0, _c(o, 5, 5)), "cell": [o.x + 20, o.y + 20]}) != "", "only aircraft airdrop")
	var cell := Vector2i(o.x + 20, o.y + 20)
	var ev := do_cmd(w, 0, {"type": "airdrop", "carrier_id": lift, "cell": [cell.x, cell.y]})
	check(rejected_reason(ev) == "", "airdrop accepted: %s" % rejected_reason(ev))
	var done := false
	for i in 600:
		w.step()
		if not w.sys_state.mobility.drops.has(lift):
			done = true
			break
	check(done, "the airlift reached the drop point (at %s)" % [w.entities[lift].pos if w.entities.has(lift) else "gone"])
	for pid in [p1, p2]:
		check(w.entities.has(pid), "paratrooper %d landed" % pid)
		if w.entities.has(pid):
			var pc := w.cell_of(w.entities[pid].pos)
			check(absi(pc.x - cell.x) <= 1 and absi(pc.y - cell.y) <= 1, "paratrooper %d inside the 3x3 drop area (%s)" % [pid, pc])
	check((w.entities[lift].get("cargo", []) as Array).is_empty(), "the airlift is empty after the drop")


func test_airdrop_supply_pallet() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var lift := w.spawn_unit("a_airlift", 0, _c(o, 3, 3))
	var cell := Vector2i(o.x + 18, o.y + 18)
	var mortar := w.spawn_unit("a_mortar", 0, _c(o, 18, 19))
	var apc := w.spawn_unit("a_apc", 0, _c(o, 19, 18))
	var foe := w.spawn_unit("a_mortar", 1, _c(o, 17, 17))
	var outside := w.spawn_unit("a_mortar", 0, _c(o, 23, 18))
	for id in [mortar, foe, outside]:
		w.entities[id].ammo = 0
	var fmax := float(Content.unit("a_apc").get("fuel_max", 0.0))
	w.entities[apc].fuel = 5.0
	var ev := do_cmd(w, 0, {"type": "airdrop", "carrier_id": lift, "cell": [cell.x, cell.y]})
	check(rejected_reason(ev) == "", "pallet airdrop accepted (empty airlift): %s" % rejected_reason(ev))
	var dropped := false
	for i in 600:
		w.step()
		if not (w.sys_state.mobility.pallets as Dictionary).is_empty():
			dropped = true
			break
	check(dropped, "a supply pallet was dropped")
	var pals := Mobility.pallets(w)
	check(pals.size() == 1 and int(pals[0].cell[0]) == cell.x and int(pals[0].cell[1]) == cell.y, "the pallet sits on the drop cell (%s)" % [pals])
	check(Mobility.validate_command(w, {"type": "airdrop", "issuer": 0, "carrier_id": lift, "cell": [cell.x, cell.y]}) != "", "the next pallet waits for its cooldown")
	for i in 21:
		w.step()
	check_eq(int(w.entities[mortar].ammo), int(Content.unit("a_mortar").get("ammo_max", 0)), "friendly in the 3x3 area rearmed")
	if fmax > 0.0:
		check(is_equal_approx(float(w.entities[apc].fuel), fmax), "friendly vehicle in the area refuelled")
	# G7 (REGRESS7-2): the foe can now die in the window (wounds); a dead foe got nothing either (same oracle)
	check(not w.entities.has(foe) or int(w.entities[foe].ammo) == 0, "the enemy gets nothing from the pallet")
	check_eq(int(w.entities[outside].ammo), 0, "units outside the 3x3 area get nothing")
	var left := Mobility.pallets(w)
	check(left.size() == 1 and int(left[0].ammo) < int(Content.rules().g6_support.mobility.pallet_ammo), "the pallet stock went down")


func test_marines_unload_twice_as_fast() -> void:
	var s := _setup(Terrain.BEACH)
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var hov_m := w.spawn_unit("a_hovercraft", 0, _c(o, 8, 8))
	var hov_r := w.spawn_unit("a_hovercraft", 0, _c(o, 20, 20))
	var lc := w.spawn_unit("a_landing_craft", 0, _c(o, 8, 22))
	var m1 := w.spawn_unit("a_marines", 0, _c(o, 8, 9))
	var m2 := w.spawn_unit("a_marines", 0, _c(o, 9, 9))
	var r1 := w.spawn_unit("rifleman", 0, _c(o, 20, 21))
	var r2 := w.spawn_unit("rifleman", 0, _c(o, 21, 21))
	var r3 := w.spawn_unit("rifleman", 0, _c(o, 8, 23))
	w.step()
	for pair in [[hov_m, m1], [hov_m, m2], [hov_r, r1], [hov_r, r2], [lc, r3]]:
		_load(w, pair[0], pair[1])
	check(Mobility.staged_carrier(w.entities[hov_m]), "the hovercraft (g6 beach carrier) unloads timed")
	check(not Mobility.staged_carrier(w.entities[lc]), "the G5 landing craft is unchanged (staged_g5 off)")
	check(not Mobility.begin_unload(w, w.entities[lc], [], w.entities[lc].pos), "G5 carriers unload at once (begin_unload false)")
	check_eq(Mobility.unload_ticks(w.entities[hov_m].cargo[0]) * 2, Mobility.unload_ticks(w.entities[hov_r].cargo[0]), "a marine squad needs half a rifle squad's unload time")
	var t0 := w.tick
	check(Mobility.begin_unload(w, w.entities[hov_m], [], w.entities[hov_m].pos), "staged unload starts (marines)")
	check(Mobility.begin_unload(w, w.entities[hov_r], [], w.entities[hov_r].pos), "staged unload starts (riflemen)")
	check(not w.entities.has(m1) and not w.entities.has(r1), "nobody is ashore at once")
	var done_m := -1
	var done_r := -1
	for i in 200:
		w.step()
		if done_m < 0 and w.entities.has(m1) and w.entities.has(m2):
			done_m = w.tick - t0
		if done_r < 0 and w.entities.has(r1) and w.entities.has(r2):
			done_r = w.tick - t0
		if done_m >= 0 and done_r >= 0:
			break
	check(done_m > 0 and done_r > 0, "both carriers finished unloading (marines %d, riflemen %d ticks)" % [done_m, done_r])
	check(done_m > 0 and absi(done_r - 2 * done_m) <= 1, "marines get ashore twice as fast (%d vs %d ticks)" % [done_m, done_r])
	check((w.entities[hov_m].get("cargo", []) as Array).is_empty(), "the marines' hovercraft is empty")
	check(not (w.sys_state.mobility.unloads as Dictionary).has(hov_m), "the unload job is finished")
	# the real order path: a driven unload order (Transport.order_unload) ends in the timed unload too
	var m3 := w.spawn_unit("a_marines", 0, _c(o, 4, 15))
	var hov3 := w.spawn_unit("a_hovercraft", 0, _c(o, 3, 15))
	w.step()
	_load(w, hov3, m3)
	Transport.order_unload(w, w.entities[hov3], _c(o, 12, 15), [])
	var started := -1
	var ashore := -1
	for i in 400:
		w.step()
		if started < 0 and (w.sys_state.mobility.unloads as Dictionary).has(hov3):
			started = w.tick
			check(not w.entities.has(m3), "the marines are still aboard when the timed unload starts")
		if w.entities.has(m3):
			ashore = w.tick
			break
	check(started > 0 and ashore > 0, "the driven unload order became a timed unload (start %d, ashore %d)" % [started, ashore])
	check(ashore - started == Mobility.unload_ticks({"def": "a_marines"}) - 1 or ashore - started == Mobility.unload_ticks({"def": "a_marines"}), "marines ashore after their unload time (%d ticks)" % [ashore - started])
