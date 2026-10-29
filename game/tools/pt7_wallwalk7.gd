extends RefCounted
## G7 playtest flow wallwalk7 (WALL7, G7_REFERENCE 13.9c-4 "walls of facility need to be walkable for your units").
## In the real game: the player's counter-nanite facility rises; a rifle squad inside the compound is box-selected and
## right-clicked onto the north wall; it climbs up from inside, lines up on the wall top, walks along it on a second
## order, and fires from it at an enemy squad outside. An own APC ordered onto the wall stays below. Shots at zoom
## 1 / 1.75 / 2.5 of the squad on the wall (drawn on top of the wall, never behind it) and walking along it.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-wallwalk7   (ORCH registered "wallwalk7")

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
const SQUAD := 6


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _shots(pt, mv, at: Vector2, tag: String) -> void:
	for z in [1.0, 1.75, 2.5]:
		_zoom(mv, z)
		mv.center_camera_on(at)
		await pt._wait(0.8)
		await pt._shot("wallwalk7_%s_z%d" % [tag, int(z * 100)])


func _on_wall_n(w: SimWorld, ids: Array) -> int:
	var n := 0
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null and WallWalk7.on_wall(w, e):
			n += 1
	return n


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var foe := -1
	for f in w.factions:
		if int(f) != me and w.is_enemy(me, int(f)):
			foe = int(f)
			break
	var c: Vector2i = h._open(w, 22)
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(14, 14)
	var fid := w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): mv.join_sim(); return not CnFacility.facilities(pt._w(), me).is_empty(), 8.0)
	pt._log("wallwalk7_facility_raised", raised, "facility %d" % fid)
	if not raised:
		return
	mv.join_sim()
	if not WallWalk7.any(w):
		WallWalk7.tick(w)   # until ORCH registers the system slot (idempotent afterwards)
	var F: Dictionary = CnFacility.fac(w, CnFacility.facilities(w, me)[0])
	var O: Vector2i = CnFacility.origin(F)
	var ring := WallWalk7.ring_cells(w, F)
	pt._log("wallwalk7_ring_walkable", WallWalk7.any(w) and ring.size() >= 100, "%d wall-walk cells" % ring.size())
	# squad inside, below the north wall run between the towers at local x 8 and 16
	var ids := []
	for i in SQUAD:
		var u: Dictionary = h._unit(w, "rifleman", me, Vector2(O) + Vector2(9.5 + i * 0.9, 5.5 + (i % 2) * 0.8))
		ids.append(int(u.id))
	var apc: Dictionary = h._unit(w, "ifv", me, Vector2(O) + Vector2(5.5, 8.5))
	var wall_a := Vector2(O) + Vector2(12.5, 1.5)
	var wall_b := Vector2(O) + Vector2(21.5, 1.5)
	_zoom(mv, 1.0)
	mv.center_camera_on(Vector2(O) + Vector2(12.0, 5.0))
	await pt._wait(0.8)
	# player gesture: box-select the squad, right-click the wall
	var a: Vector2 = pt._to_screen(Vector2(O) + Vector2(8.6, 4.6))
	var b: Vector2 = pt._to_screen(Vector2(O) + Vector2(15.4, 7.4))
	await pt._drag(Vector2(minf(a.x, b.x) - 40.0, minf(a.y, b.y) - 50.0), Vector2(maxf(a.x, b.x) + 40.0, maxf(a.y, b.y) + 30.0))
	await pt._wait(0.3)
	var sel := 0
	for id in ids:
		if mv.selection.has(id):
			sel += 1
	pt._log("wallwalk7_squad_selected", sel == SQUAD, "%d of %d selected" % [sel, SQUAD])
	await pt._tut_rclick(wall_a)
	var up: bool = await pt._wait_until(func(): mv.join_sim(); return _on_wall_n(pt._w(), ids) == SQUAD, 40.0)
	mv.join_sim()
	pt._log("wallwalk7_squad_on_wall", up, "%d of %d soldiers on the wall top" % [_on_wall_n(w, ids), SQUAD])
	pt._log("wallwalk7_drawn_on_top", int(mv.entity_layer.get("ww_drawn")) >= 1, "entity layer drew %d soldiers on a wall top" % int(mv.entity_layer.get("ww_drawn")))
	await _shots(pt, mv, wall_a, "squad_on_wall")
	# own APC ordered onto the wall: stays below
	mv.join_sim()
	Movement.apply_command(w, {"type": "move", "unit_ids": [int(apc.id)], "target": wall_a + Vector2(-3.0, 0.0), "issuer": me})
	# walk along the wall top
	mv.selection.clear()
	for id in ids:
		mv.selection.append(id)
	_zoom(mv, 1.0)
	mv.center_camera_on(wall_b)
	await pt._wait(0.5)
	await pt._tut_rclick(wall_b)
	var left := 0
	var arrived := false
	var mid_shot := false
	for k in 160:
		await pt._wait(0.1)
		mv.join_sim()
		left += SQUAD - _on_wall_n(w, ids)
		var e0 = w.entities.get(int(ids[0]))
		if e0 != null and not mid_shot and Vector2(e0.pos).x > wall_a.x + 4.0:
			mid_shot = true
			_zoom(mv, 1.75)
			mv.center_camera_on(Vector2(e0.pos))
			await pt._wait(0.2)
			await pt._shot("wallwalk7_walking_along_z175")
		if e0 != null and Vector2(e0.pos).distance_to(wall_b) < 3.5 and not bool(e0.get("moving", false)):
			arrived = true
			break
	pt._log("wallwalk7_walked_along", arrived and left == 0, "arrived %s, soldier-samples off the wall %d" % [str(arrived), left])
	var apc_on := Movement.wallwalk_team(w, w.cell_of(apc.pos)) >= 0
	pt._log("wallwalk7_vehicle_stays_below", not apc_on, "APC cell %s" % str(w.cell_of(apc.pos)))
	# enemy squad outside the north wall: the squad fires from the wall top
	var foes := []
	if foe >= 0:
		for i in 4:
			var en: Dictionary = h._unit(w, "rifleman", foe, Vector2(O) + Vector2(18.5 + i * 1.2, -5.5))
			en.order = {"type": "hold"}
			foes.append(int(en.id))
	# a soldier fired from the wall top = it acquired a target (e.target) while standing on a wall-walk cell (events
	# are per sim step and the 3x harness steps several per frame, so they are not polled here)
	var fired := {}
	var mid := false
	for k in 120:
		await pt._wait(0.05)
		mv.join_sim()
		for id in ids:
			var e = w.entities.get(int(id))
			if e != null and int(e.get("target", -1)) >= 0 and WallWalk7.on_wall(w, e):
				fired[int(id)] = true
		if not mid and fired.size() >= 2:
			mid = true
			await _shots(pt, mv, wall_b + Vector2(0.0, -2.0), "firing_from_wall")
		if fired.size() >= 3 and mid:
			break
	pt._log("wallwalk7_fires_from_wall", foe < 0 or fired.size() >= 1, "%d soldiers engaged from the wall top (foe faction %d)" % [fired.size(), foe])
	if not mid:
		await _shots(pt, mv, wall_b, "firing_from_wall")
	pt._log("wallwalk7_still_on_wall", _on_wall_n(w, ids) >= SQUAD - 2, "%d on the wall after the fight" % _on_wall_n(w, ids))
	await _sentinel_wall(pt, mv, w, me, foe, O)


## WALL7-2 (13.9c-23): the facility's own Sentinels man the east wall (its outer armoured parapet faces the camera)
## under attack from outside: they stand on the deck behind the parapet (the parapet strip drawn over their legs),
## one is reloading crouched behind it, the others rise to fire and duck between shots. Shots at zoom 1 / 1.75 / 2.5,
## plus the NE corner tower join.
func _sentinel_wall(pt, mv, w: SimWorld, me: int, foe: int, O: Vector2i) -> void:
	var cs := float(CnFacility.conf().get("compound", 32))
	var east_x := float(O.x) + cs - 2.5
	var hh = H.new()
	if foe >= 0:
		for i in 5:
			var en: Dictionary = hh._unit(w, "rifleman", foe, Vector2(O) + Vector2(cs + 6.0, cs * 0.3 + i * 1.6))
			en.order = {"type": "hold"}
	var sents := []
	# WALLWALK7_FORCE_ORDER=1 skips the 20 s wait for the alarm drill so the player-orders path below runs every time
	# (same pass condition: >= 2 Sentinels on the east wall-walk); unset = the normal flow
	var force_order := OS.get_environment("WALLWALK7_FORCE_ORDER") == "1"
	var ok: bool = await pt._wait_until(func():
		mv.join_sim()
		sents.clear()   # in place: a lambda captures the Array reference, not the variable
		sents.append_array(_east_sentinels(pt._w(), me, east_x))
		return sents.size() >= 2, 0.2 if force_order else 20.0)
	mv.join_sim()
	var how := "on their own (alarm drill)"
	var ordered := []
	if not ok:
		# WALL7-3: the Sentinel alarm drill races the facility's turrets (when the attackers die first nobody stands
		# to on the east face, r7), so the player mans the wall: the free Sentinels nearest to the east wall-walk get a
		# move order each onto their own east wall cell (player command, issuer = the player), then Hold Position.
		var cells := _east_wall_cells(w, me, east_x, O, cs)
		ordered = _free_sentinels(w, me, sents, cells, 2 - sents.size())
		for i in ordered.size():
			Movement.apply_command(w, {"type": "move", "unit_ids": [int(ordered[i])], "target": Vector2(cells[i]) + Vector2(0.5, 0.5), "issuer": me})
		for id in ordered:
			var oe: Dictionary = w.entities[int(id)]
			print("WALLWALK7 ordered %d (%s) from %s: order %s moving %s path %s" % [int(id), String(oe.s7), str(oe.pos), str(oe.order), str(oe.get("moving")), str(oe.get("path", [])).left(160)])
		how = "%d on their own + %d ordered onto east wall cells by the player" % [sents.size(), ordered.size()]
		# each one gets Hold Position once he stands on his own wall cell (an order that is done hands a Sentinel
		# back to his automatic job board, which would walk him off to his old post: 13.9c-12)
		ok = await pt._wait_until(func():
			mv.join_sim()
			var ww: SimWorld = pt._w()
			sents.clear()
			sents.append_array(_east_sentinels(ww, me, east_x))
			_hold_arrived(ww, me, ordered, cells, sents)
			return sents.size() >= 2, 45.0)
		mv.join_sim()
		for i in ordered.size():   # flow diagnostics: where the ordered Sentinels ended up
			var se = w.entities.get(int(ordered[i]))
			var st = w.sys_state.get("sent7", {}).get("jobs", {}).get(str(ordered[i]))
			print("WALLWALK7 ordered sentinel %d cell %s: %s" % [int(ordered[i]), str(cells[i]), "gone" if se == null else "pos %s order %s job %s on_wall %s" % [str(se.pos), str(se.order), str(st).left(80), str(WallWalk7.on_wall(w, se))]])
	pt._log("wallwalk7_sentinels_man_east_wall", ok, "%d Sentinels on the east wall-walk (%s)" % [sents.size(), how])
	if sents.is_empty():
		return
	if foe >= 0:
		# the first attackers usually fall to the tower guns while the wall is being manned (r1: nobody left to shoot
		# at): a second group closes on the east wall now that it is manned, inside rifle range of the wall-walk
		# FLOWB7B (probe 2026-10-28): the Sentinels who man the east wall stand where the alarm drill / job board put
		# them (r: y 59..62), but this group stood at compound y 0.35..0.55 (~11-12 tiles north of them, outside every
		# Sentinel's range 4.5..8); they only engaged after walking up the wall-walk, and the suite run's softer group
		# was dead to the towers by then ("up to 0 Sentinels ... engaging"). Sentinel targeting itself was fine: every
		# Sentinel on Hold with a foe in range had a target; ones on a move order only return fire. The group now
		# closes on the stretch of wall the Sentinels actually hold (their mean y, kept off the corner towers), inside
		# rifle range of the wall-walk; the check below is unchanged.
		var sy := 0.0
		for id in sents:
			sy += float(w.entities[int(id)].pos.y)
		sy = clampf(sy / float(sents.size()), float(O.y) + 5.0, float(O.y) + cs - 5.0)
		for i in 5:
			var en2: Dictionary = hh._unit(w, "rifleman", foe, Vector2(float(O.x) + cs + 3.5, sy + (i - 2) * 1.4))
			en2.order = {"type": "hold"}
			# FLOWB7 (suite 2026-10-28): with the 13.9c-38 watch (a manned deck on every tower, wall turrets on the east
			# face, patrol pairs) the attackers die fast; hardened attackers (as pt7_wallturret7's AT team) live long
			# enough for the men on the wall to engage.
			en2.max_hp = 3000.0
			hh._hp(w, en2, 3000.0)
	var el = mv.entity_layer
	var crouch := 0
	var front := 0
	var fired := 0
	var at := Vector2(w.entities[int(sents[0])].pos)
	_zoom(mv, 1.75)
	var fshot := 0
	for k in 300:   # the fight on the east wall: Sentinels rise to fire and duck between shots
		await pt._wait(0.05)
		mv.join_sim()
		var cur := _east_sentinels(w, me, east_x)
		if not cur.is_empty():
			at = Vector2(w.entities[int(cur[0])].pos)
		mv.center_camera_on(at)
		crouch = maxi(crouch, int(el.get("ww_crouch")))
		front = maxi(front, int(el.get("ww_front")))
		var f := 0
		var shooter := -1
		for id in cur:
			if int(w.entities[int(id)].get("target", -1)) >= 0:
				f += 1
				shooter = int(id)
		fired = maxi(fired, f)
		if shooter >= 0 and fshot < 2 and k > 8 and k % 9 == 0:
			# WALL7-3: close-ups of a Sentinel in the fight (rises to fire over the battlements, ducks between shots)
			_zoom(mv, 2.5)
			mv.center_camera_on(Vector2(w.entities[shooter].pos))
			await pt._wait(0.05)
			await pt._shot("wallwalk7_sentinel_firing_z250_%d" % fshot)
			fshot += 1
			_zoom(mv, 1.75)
		if crouch >= 1 and front >= 1 and fired >= 1 and k > 40 and (fshot >= 2 or foe < 0):
			break
	pt._log("wallwalk7_parapet_over_legs", front >= 1, "%d parapet occluder strips drawn over soldiers on the wall" % front)
	pt._log("wallwalk7_sentinels_fire_from_wall", foe < 0 or fired >= 1, "up to %d Sentinels on the east wall engaging at once" % fired)
	# one Sentinel changes magazines (scripted: render_snap s7 bit 1 for 15 s of sim): crouched behind the parapet
	mv.join_sim()
	var cur2 := _east_sentinels(w, me, east_x)
	var rid := int(cur2[0]) if not cur2.is_empty() else int(sents[0])
	var rl: Dictionary = w.entities[rid]
	rl["s7_rl"] = int(w.tick) + 300
	var rc := 0
	for z in [2.5, 1.75, 1.0]:
		_zoom(mv, z)
		mv.center_camera_on(Vector2(rl.pos))
		await pt._wait(0.35)
		rc = maxi(rc, int(el.get("ww_crouch")))
		await pt._shot("wallwalk7_sentinels_east_wall_z%d" % int(z * 100))
	mv.join_sim()
	pt._log("wallwalk7_sentinel_reload_crouched", rc >= 1 and WallWalk7.on_wall(w, rl), "%d soldiers drawn crouched behind the parapet; reloading Sentinel %d still on the wall-walk: %s" % [rc, rid, str(WallWalk7.on_wall(w, rl))])
	for z in [1.75, 2.5]:
		_zoom(mv, z)
		mv.center_camera_on(Vector2(O) + Vector2(cs - 2.0, 2.0))
		await pt._wait(0.8)
		await pt._shot("wallwalk7_corner_tower_z%d" % int(z * 100))


## WALL7-4: Hold Position for a player-ordered Sentinel only once he has ARRIVED (within 0.45 tile of his wall cell's
## centre, or his move order has ended) and is on the wall-walk. WALL7-3's first version held him the instant he
## crossed onto the wall piece (x = the wall's inner edge): a 0.03-tile nudge then put him back on the compound floor
## and nobody manned the wall (r4, headless repro: x 46.0254 -> 45.9995).
func _hold_arrived(ww: SimWorld, me: int, ordered: Array, cells: Array, sents: Array) -> void:
	for i in ordered.size():
		var id := int(ordered[i])
		var se = ww.entities.get(id)
		if se == null or not sents.has(id) or String(se.order.get("type", "")) == "hold":
			continue
		var there: bool = Vector2(se.pos).distance_to(Vector2(cells[i]) + Vector2(0.5, 0.5)) <= 0.45 or String(se.order.get("type", "")) != "move"
		if there:
			Movement.apply_command(ww, {"type": "hold", "unit_ids": [id], "issuer": me})


## East wall-walk cells of the player's facility on plain wall pieces (no tower: a man there could be garrisoned),
## facing the attackers (compound y 0.3 .. 0.6), two rows apart, the inner deck column first.
func _east_wall_cells(w: SimWorld, me: int, east_x: float, O: Vector2i, cs: float) -> Array:
	var F: Dictionary = CnFacility.fac(w, CnFacility.facilities(w, me)[0])
	var cells := []
	for pid in F.get("parts", []):
		var b = w.entities.get(int(pid))
		if b == null or String(Content.building(String(b.def)).get("cn_part", "")) != "wall":
			continue
		var sz := int(b.size)
		for y in sz:
			for x in sz:
				var c := Vector2i(b.cell) + Vector2i(x, y)
				if float(c.x) + 0.5 >= east_x and c.y >= O.y + int(cs * 0.3) and c.y <= O.y + int(cs * 0.6):
					cells.append(c)
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out := []
	for c in cells:
		if out.is_empty() or (c.y >= int(out[-1].y) + 2):
			out.append(c)
		if out.size() >= 2:
			break
	return out


## Up to n Sentinels free for the player to order (not garrisoned, not down, not a Mender / Ammo Bearer, not already
## on the east wall), nearest to the first target cell first, ascending id on ties.
func _free_sentinels(w: SimWorld, me: int, have: Array, cells: Array, n: int) -> Array:
	if cells.is_empty() or n <= 0:
		return []
	var at := Vector2(cells[0]) + Vector2(0.5, 0.5)
	var c := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" or int(e.owner) != me or not e.has("s7") or e.has("garrisoned_in") or have.has(int(id)):
			continue
		if ["mender", "bearer", "arc"].has(String(e.s7)) or SimWorld.Wounds.is_down(e):
			continue
		c.append([Vector2(e.pos).distance_to(at), int(id)])
	c.sort()
	var out := []
	for i in mini(n, c.size()):
		out.append(int(c[i][1]))
	return out


func _east_sentinels(w: SimWorld, me: int, east_x: float) -> Array:
	var out := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and int(e.owner) == me and e.has("s7") and not e.has("garrisoned_in") and float(e.pos.x) >= east_x and WallWalk7.on_wall(w, e):   # out on the wall-walk, not inside a tower
			out.append(int(id))
	return out
