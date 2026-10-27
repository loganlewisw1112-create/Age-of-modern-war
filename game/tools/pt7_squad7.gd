extends RefCounted
## G7 playtest flow squad7 (SQUAD7): formations rebuilt, techniques, halts, building clear, convoy.
## On a cleared test ground with a painted north-south road: a rifle platoon selected with the mouse and moved by
## ordinary player orders (no formation picked: the G7 default) into a staggered column on the road (+ a 10-shot
## 0.3 s strip of the column on the move), a wedge across open ground, 4 IFVs halting into a herringbone, a squad
## bounding under fire, a building clear (stack + roof_open), and a 5-vehicle convoy taking contact on a flank.
## Every order goes through MatchView.issue / w.submit. Shots of each scene in the --ui-playtest dir.

const H = preload("res://tests/test_machine_g6.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SquadAI = preload("res://sim/systems/squad_ai.gd")
const F7 = preload("res://sim/systems/formations7.gd")
const Convoy = preload("res://sim/systems/convoy.gd")

const SQ_P := 7701   # platoon (one squad id so it regroups as one group)
const SQ_V := 7702   # IFV section
const SQ_B := 7703   # bounding squad

var _road_x := 0


func _sub(w: SimWorld, cmd: Dictionary) -> bool:
	cmd["issuer"] = 0
	var r: Dictionary = w.submit(cmd)
	if not bool(r.get("ok", false)):
		print("PLAYTEST-DBG squad7 rejected %s: %s" % [String(cmd.type), String(r.get("reason", ""))])
	return bool(r.get("ok", false))


func _ents(w: SimWorld, ids: Array) -> Array:
	var out := []
	for id in ids:
		if w.entities.has(int(id)):
			out.append(w.entities[int(id)])
	return out


func _nn_min(es: Array) -> float:
	var lo := INF
	for i in es.size():
		for j in range(i + 1, es.size()):
			lo = minf(lo, Vector2(es[i].pos).distance_to(Vector2(es[j].pos)))
	return lo


func _idle(w: SimWorld, ids: Array) -> bool:
	for e in _ents(w, ids):
		if bool(e.get("moving", false)):
			return false
	return true


func _zoom(pt, z: float) -> void:
	var cam = pt._mv().get("camera")
	if cam != null and cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)


func _spawn_block(w: SimWorld, h, def: String, n: int, at: Vector2, cols: int, step: float, squad: int) -> Array:
	var ids := []
	for k in n:
		var p := at + Vector2(float(k % cols) * step, float(k / cols) * step)
		var c := Movement.nearest_free_cell(w, Vector2i(floori(p.x), floori(p.y)), "foot" if def == "rifleman" else "vehicle")
		var e: Dictionary = h._unit(w, def, 0, Vector2(c) + Vector2(0.5, 0.5))
		if squad >= 0:
			e.squad = squad
		ids.append(int(e.id))
	SquadAI.touch(w)
	return ids


## Debug: each member's slot and spot in the move frame (f forward, l lateral right, tiles from the target).
func _dbg_frame(w: SimWorld, es: Array, slots: Dictionary, tgt: Vector2, tag: String) -> void:
	var c0 := Vector2.ZERO
	for e in es:
		c0 += Vector2(e.pos)
	var fwd := (tgt - c0 / maxf(1.0, float(es.size()))).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	var parts := []
	for e in es:
		var s: Vector2 = slots.get(int(e.id), Vector2(e.pos)) - tgt
		var p := Vector2(e.pos) - tgt
		parts.append("%d slot(%.1f,%.1f) at(%.1f,%.1f) mv=%s o=%s" % [int(e.id), s.dot(fwd), s.dot(side), p.dot(fwd), p.dot(side),
			str(e.get("moving", false)), String(e.order.get("type", "")) + "/" + String(e.order.get("sq", ""))])
	print("PLAYTEST-DBG squad7 %s tick %d: %s" % [tag, w.tick, "; ".join(parts)])


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	var c: Vector2i = h._open(w, 14)
	var cf := Vector2(c) + Vector2(0.5, 0.5)
	# test ground: a north-south road east of the centre, painted over passable ground only
	_road_x = c.x + 6
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	var painted := 0
	for y in range(maxi(c.y - 26, 1), mini(c.y + 26, int(w.map.h) - 1)):
		var rc := Vector2i(_road_x, y)
		if w.terrain_at(rc) != Terrain.ROAD and Movement.is_passable(w, rc, "vehicle"):
			t[y * mw + _road_x] = Terrain.ROAD
			painted += 1
	w.map.terrain = t
	Movement.rebuild_nav(w)
	if mv.get("terrain_layer") != null and mv.terrain_layer.has_method("rebuild"):
		mv.terrain_layer.rebuild()
	# a quiet test ground: enemy units within 40 tiles are removed (the scenes add their own enemies)
	var cleared := 0
	var keys := w.entities.keys()
	keys.sort()
	for id in keys:
		var e = w.entities.get(id)
		if e != null and e.kind == "unit" and int(e.owner) != 0 and w.is_enemy(0, int(e.owner)) and Vector2(e.pos).distance_to(cf) <= 40.0:
			w.destroy(int(id), "playtest")
			cleared += 1
	mv.speed = 1.0
	await pt._wait(1.5)
	mv.join_sim()
	pt._log("squad7_ground", painted >= 30, "open ground at %s, road x=%d (%d tiles), %d enemy units cleared, threat dist %.1f" % [str(c), _road_x, painted, cleared, F7.threat_dist(w, 0, cf)])
	_zoom(pt, 1.1)

	# 1. platoon on the road: an ordinary player move, no formation picked -> staggered column
	var plat := _spawn_block(w, h, "rifleman", 9, cf + Vector2(-4.0, 14.0), 3, 1.5, SQ_P)
	var nsel: int = await pt._g5_select_many(plat)
	if nsel < plat.size():   # a Shift+click can land on a neighbour's sprite (iso overlap): click the missed ones once more
		for id in plat:
			var se = pt._w().entities.get(int(id))
			if se != null and not mv.selection.has(int(id)):
				await pt._click(pt._to_screen(se.pos), MOUSE_BUTTON_LEFT, false, true)
				await pt._wait(0.15)
		nsel = plat.filter(func(x): return mv.selection.has(int(x))).size()
	pt._log("squad7_select_platoon", nsel == plat.size(), "selected %d/%d" % [nsel, plat.size()])
	mv.join_sim()
	var road_a := Vector2(float(_road_x) + 0.5, cf.y + 2.5)
	mv.issue({"type": "move", "unit_ids": plat.duplicate(), "target": road_a})
	mv.center_camera_on(road_a + Vector2(0.0, 4.0))
	await pt._wait(0.3)
	mv.join_sim()
	var f := String(w.entities.get(plat[0], {}).get("f7_auto", ""))
	pt._log("squad7_default_column", f == "staggered_column", "f7_auto=%s (player move, no formation picked)" % f)
	await pt._wait_until(func(): return _idle(pt._w(), plat), 25.0)
	await pt._wait(1.0)
	mv.join_sim()
	var pe := _ents(w, plat)
	var left := 0
	var right := 0
	for e in pe:
		if Vector2(e.pos).x < float(_road_x) + 0.5:
			left += 1
		else:
			right += 1
	var nn := _nn_min(pe)
	pt._log("squad7_column_spacing", nn >= 0.7, "nearest neighbour %.2f tiles (~%.0f m)" % [nn, nn * 7.0])
	pt._log("squad7_column_staggered", left >= 3 and right >= 3, "left of road %d, right %d" % [left, right])
	await pt._shot("squad7_01_column_road")
	# the column marches on up the road: 10 shots 0.3 s apart
	var road_b := Vector2(float(_road_x) + 0.5, cf.y - 14.5)
	mv.issue({"type": "move", "unit_ids": plat.duplicate(), "target": road_b})
	await pt._wait(1.2)
	for k in 10:
		mv.join_sim()
		var cen := Vector2.ZERO
		var es := _ents(pt._w(), plat)
		for e in es:
			cen += Vector2(e.pos)
		if not es.is_empty():
			mv.center_camera_on(cen / float(es.size()))
		await pt._shot("squad7_strip_%02d" % k)
		await pt._wait(0.3)
	await pt._wait_until(func(): return _idle(pt._w(), plat), 25.0)

	# 2. wedge across open ground (same platoon, ordinary move off the road)
	mv.join_sim()
	# heading world (-1, +1) = screen left, so the wedge reads as a ">" on the iso view (apex left, arms back)
	var open_t := road_b + Vector2(-9.0, 9.0)
	mv.issue({"type": "move", "unit_ids": plat.duplicate(), "target": open_t})
	await pt._wait(0.3)
	mv.join_sim()
	f = String(w.entities.get(plat[0], {}).get("f7_auto", ""))
	pt._log("squad7_default_wedge", f == "wedge", "f7_auto=%s" % f)
	mv.center_camera_on(open_t + Vector2(0.0, 2.0))
	var slots := {}
	for e in _ents(w, plat):
		slots[int(e.id)] = Vector2(e.order.get("target", e.pos))
	var w_idle: bool = await pt._wait_until(func(): return _idle(pt._w(), plat), 25.0)
	# shot at once: a long halt turns the squad into a 360 degree ring (halt drill), which is not this scene
	await pt._shot("squad7_02_wedge_open")
	mv.join_sim()
	pe = _ents(w, plat)
	_dbg_frame(w, pe, slots, open_t, "wedge idle=%s" % w_idle)
	var lo := INF
	var hi := -INF
	var top := INF
	var bot := -INF
	for e in pe:
		lo = minf(lo, Vector2(e.pos).x)
		hi = maxf(hi, Vector2(e.pos).x)
		top = minf(top, Vector2(e.pos).y)
		bot = maxf(bot, Vector2(e.pos).y)
	nn = _nn_min(pe)
	pt._log("squad7_wedge_shape", hi - lo >= 3.0 and bot - top >= 1.0 and nn >= 0.7,
		"width %.1f depth %.1f tiles, nearest neighbour %.2f" % [hi - lo, bot - top, nn])

	# 3. IFV section down the road, halt -> herringbone
	var ifv := _spawn_block(w, h, "ifv", 4, Vector2(float(_road_x) - 6.5, cf.y + 20.0), 4, 2.0, SQ_V)
	mv.join_sim()
	var vt := Vector2(float(_road_x) + 0.5, cf.y - 2.5)
	mv.issue({"type": "move", "unit_ids": ifv.duplicate(), "target": vt})
	await pt._wait(0.3)
	mv.join_sim()
	f = String(w.entities.get(ifv[0], {}).get("f7_auto", ""))
	pt._log("squad7_vehicles_column", f == "staggered_column", "f7_auto=%s" % f)
	mv.center_camera_on(vt + Vector2(0.0, 8.0))
	_zoom(pt, 0.8)
	await pt._wait_until(func(): return _idle(pt._w(), ifv), 30.0)
	var hb: bool = await pt._wait_until(func():
		var n := 0
		for e in _ents(pt._w(), ifv):
			if e.has("f7_hb"):
				n += 1
		return n >= 2, 20.0)
	mv.join_sim()
	var nhb := 0
	for e in _ents(w, ifv):
		nhb += 1 if e.has("f7_hb") else 0
	pt._log("squad7_herringbone", hb, "%d of %d vehicles angled off (f7_hb)" % [nhb, ifv.size()])
	await pt._shot("squad7_03_herringbone")
	_zoom(pt, 1.1)

	# 4. bounding overwatch under fire
	mv.join_sim()
	var bq := _spawn_block(w, h, "rifleman", 6, cf + Vector2(-12.0, 12.0), 3, 1.0, SQ_B)
	var foes := []
	for k in 2:
		var fc := Movement.nearest_free_cell(w, Vector2i(c.x - 11 + k * 2, c.y - 6), "foot")
		var fe: Dictionary = h._unit(w, "rifleman", 1, Vector2(fc) + Vector2(0.5, 0.5))
		fe.order = {"type": "hold"}
		foes.append(int(fe.id))
	_sub(w, {"type": "set_technique", "unit_ids": bq.duplicate(), "technique": "bounding_overwatch"})
	mv.issue({"type": "move", "unit_ids": bq.duplicate(), "target": cf + Vector2(-11.0, 1.0)})
	mv.center_camera_on(cf + Vector2(-11.0, 6.0))
	var held := {0: false, 1: false}
	var shot_mid := false
	for i in 60:
		await pt._wait(0.25)
		mv.join_sim()
		for k in bq.size():
			var e = pt._w().entities.get(int(bq[k]))
			if e != null and e.has("f7_bw"):
				held[0 if (k == 0 or (k - 1) % 2 == 0) else 1] = true
		if not shot_mid and held[0] and held[1]:
			shot_mid = true
			await pt._shot("squad7_04_bounding")
	if not shot_mid:
		await pt._shot("squad7_04_bounding")
	pt._log("squad7_bounding", held[0] and held[1], "team A held %s, team B held %s" % [held[0], held[1]])

	# 5. building clear: stack at the door, then inside (roof_open)
	mv.join_sim()
	var bid := -1
	var bc := Vector2i(c.x - 2, c.y + 6)
	if Content.building("s_garrison_bld").size() > 0:
		bid = w.spawn_building("s_garrison_bld", 0, bc, true)
	pt._log("squad7_clear_building_spawned", bid >= 0, "s_garrison_bld at %s" % str(bc))
	if bid >= 0:
		var b: Dictionary = w.entities[bid]
		b.built = true
		Movement.rebuild_nav(w)
		var cq := _spawn_block(w, h, "rifleman", 4, Vector2(b.pos) + Vector2(5.0, 4.0), 2, 1.0, -1)
		var ok := _sub(w, {"type": "clear_building", "unit_ids": cq.duplicate(), "building_id": bid})
		mv.center_camera_on(Vector2(b.pos) + Vector2(2.0, 2.0))
		# the shot waits for the stack itself: every member at the wall by the door (f7_clr 1 and halted, or already
		# going in with f7_clr 2), not just the order stamp
		var bp := Vector2(b.pos)
		var stacked: bool = await pt._wait_until(func():
			for id in cq:
				var e = pt._w().entities.get(int(id))
				if e == null:
					continue
				var st := int(e.get("f7_clr", 0))
				if st == 0 or (st == 1 and bool(e.get("moving", false))) or Vector2(e.pos).distance_to(bp) > 4.0:
					return false
			return true, 15.0)
		mv.join_sim()
		var dmax := 0.0
		for e in _ents(w, cq):
			dmax = maxf(dmax, Vector2(e.pos).distance_to(bp))
		pt._log("squad7_clear_stack", ok and stacked, "clear_building accepted %s, stacked at the door %s (farthest %.1f tiles from the building)" % [ok, stacked, dmax])
		await pt._shot("squad7_05_clear_stack")
		var roof: bool = await pt._wait_until(func(): return int(pt._w().entities.get(bid, {}).get("roof_open", -1)) == 0, 40.0)
		pt._log("squad7_clear_roof_open", roof, "roof_open while own troops are inside")
		await pt._shot("squad7_06_clear_inside")

	# 6. a 5-vehicle convoy on the road takes contact on its flank
	mv.join_sim()
	# clear the road: the IFV section moves off east as one player group (its own formation, not a pile-up)
	mv.issue({"type": "move", "unit_ids": ifv.duplicate(), "target": Vector2(float(_road_x) + 8.5, cf.y + 2.5)})
	var cv := []
	var defs := ["ifv", "logistics_truck", "logistics_truck", "logistics_truck", "ifv"]
	for k in defs.size():
		var vc := Movement.nearest_free_cell(w, Vector2i(_road_x, c.y + 22 - k * 4 + 0), "vehicle")
		var ve: Dictionary = h._unit(w, defs[k], 0, Vector2(vc) + Vector2(0.5, 0.5))
		cv.append(int(ve.id))
	SquadAI.touch(w)
	var formed := _sub(w, {"type": "convoy_form", "unit_ids": cv.duplicate()})
	var moved := _sub(w, {"type": "convoy_move", "unit_ids": cv.duplicate(), "target": Vector2(float(_road_x) + 0.5, cf.y - 22.5)})
	pt._log("squad7_convoy_orders", formed and moved, "convoy_form %s, convoy_move %s" % [formed, moved])
	_zoom(pt, 0.8)
	await pt._wait(4.0)
	mv.join_sim()
	var cid := Convoy.of_unit(w, int(cv[2]))
	var core = w.entities.get(int(cv[2]))
	var en := -1
	if core != null:
		var ec := Movement.nearest_free_cell(w, Vector2i(floori(core.pos.x) + 9, floori(core.pos.y) - 4), "foot")
		var ee: Dictionary = h._unit(w, "rifleman", 1, Vector2(ec) + Vector2(0.5, 0.5))
		ee.order = {"type": "hold_fire"}
		ee.hp = 1000000.0
		ee.max_hp = 1000000.0
		en = int(ee.id)
		mv.center_camera_on(Vector2(core.pos))
	await pt._shot("squad7_07_convoy_move")
	var best := INF
	for i in 40:
		await pt._wait(0.25)
		mv.join_sim()
		var ww: SimWorld = pt._w()
		var cr = ww.entities.get(int(cv[2]))
		var tg = ww.entities.get(en)
		if cr == null or tg == null:
			continue
		var cp := Vector2(cr.pos)
		var tp := Vector2(tg.pos)
		if i % 8 == 0:
			mv.center_camera_on(cp)
		for id in cv:
			if int(id) == int(cv[1]) or int(id) == int(cv[2]) or int(id) == int(cv[3]) or not ww.entities.has(int(id)):
				continue
			var p := Vector2(ww.entities[int(id)].pos)
			var tt := clampf((p - cp).dot(tp - cp) / maxf((tp - cp).length_squared(), 0.01), 0.0, 1.0)
			best = minf(best, p.distance_to(cp.lerp(tp, tt)))
	pt._log("squad7_convoy_contact", cid > 0 and best <= 2.5, "convoy %d, escort closest to the threat line %.2f tiles" % [cid, best])
	await pt._shot("squad7_08_convoy_contact")
	_zoom(pt, 1.1)
