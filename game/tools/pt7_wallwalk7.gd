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
