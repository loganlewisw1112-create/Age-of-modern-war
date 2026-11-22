extends RefCounted
## G7.1 DAMAGE71 playtest (windowed, Last Protocol): B2 / J3 machine damage drawn in a real game.
## Starts a Last Protocol run, puts a firing line of the player's side (riflemen + any heavier gun teams the content
## has) on open ground just outside the west outer wall and a few Machines with part layouts (m_walker + crawlers) in
## front of them, steps the game and counts what fx_layer drew from the Parts71 events (fx61 `made` counters):
##   damage71_sparks.png  ricochet sparks + plate shear off the walkers (Ricochet71 / PlateShear71)
##   damage71_silver.png  silver nanite fluid over broken parts / regrowing machines (PartDestroyed71 / NaniteRegrow71)
##   damage71_wide.png    the same fight at normal zoom (wrecks, half-dead machines, bodies)
## The flow writes the sim only between steps (match_view.join_sim) and says what it forces: the spawned units and the
## explored fog. Every hit, ricochet, shear and regrowth is Parts71 deciding on its own.
const MapGen = preload("res://sim/map_gen.gd")
const GUNS := ["a_hmg_team", "at_gunner", "mbt", "a_mg_team", "mg_team", "a_lmg_team"]


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _made(mv, k: String) -> int:
	var fl = mv.fx_layer
	if fl == null or fl.get("fx61") == null:
		return 0
	return int(fl.fx61.made.get(k, 0))


func _machines(w: SimWorld, mfid: int, near: Vector2, r: float) -> int:
	var n := 0
	for e in w.units_of(mfid):
		if Vector2(e.pos).distance_to(near) <= r:
			n += 1
	return n


func _wave(w: SimWorld, mfid: int, W: Vector2) -> int:
	var n := 0
	for i in 3:
		if w.spawn_unit("m_walker", mfid, W + Vector2(0.0, float(i) * 3.0 - 3.0)) >= 0:
			n += 1
	for i in 2:
		if w.spawn_unit("m_scout_crawler", mfid, W + Vector2(1.5, float(i) * 3.0 - 1.5)) >= 0:
			n += 1
	return n


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	if not pt.main.start_match(LP.make_config(79, map)):
		pt._log("damage71_start", false, "start_match failed")
		return
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 60.0)
	pt._log("damage71_lp_ready", ok, "map %s" % map)
	if not ok:
		return
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	var s: Dictionary = w.sys_state.lp
	var fid := int(s.fid)
	var mfid := int(s.mfid)
	var ex: PackedByteArray = w.fog[fid].explored
	ex.fill(1)
	w.fog[fid].explored = ex
	var r0: Rect2i = s.base.rings[0].rect
	var P := Vector2(r0.position.x - 9, r0.get_center().y) + Vector2(0.5, 0.5)
	var nr := 0
	for i in 18:
		var id := w.spawn_unit("rifleman", fid, P + Vector2(float(i % 3), float(i / 3) - 3.0))
		if id >= 0:
			w.entities[id].order = {"type": "hold", "target": w.entities[id].pos}
			nr += 1
	var guns := []
	for g in GUNS:
		if not Content.unit(g).is_empty() and guns.size() < 3:
			var gid := w.spawn_unit(g, fid, P + Vector2(2.0, float(guns.size()) * 2.0 - 2.0))
			if gid >= 0:
				w.entities[gid].order = {"type": "hold", "target": w.entities[gid].pos}
				guns.append(g)
	# two flank groups 9 tiles north / south of the machines' lane: hits from the side meet the plates at a steep angle
	# (ricochets), and the at_gunner + mbt wear plates through (plate shear)
	var nf := 0
	for sgn in [-1.0, 1.0]:
		for i in 6:
			var fid2 := w.spawn_unit("rifleman", fid, P + Vector2(-7.0 + float(i % 3), sgn * (9.0 + float(i / 3))))
			if fid2 >= 0:
				w.entities[fid2].order = {"type": "hold", "target": w.entities[fid2].pos}
				nf += 1
	pt._log("damage71_flanks", nf == 12, "flow spawned %d flank riflemen 9-10 tiles north / south of the lane" % nf)
	var W := P + Vector2(-10.0, 0.0)
	var nm := _wave(w, mfid, W)
	pt._log("damage71_forced_fight", nr == 18 and nm > 0, "flow spawned %d riflemen + guns %s (side %d) at %s and %d machines (side %d) at %s" % [nr, str(guns), fid, str(P), nm, mfid, str(W)])
	mv.center_camera_on(P + Vector2(-5, 0))
	_zoom(mv, 2.5)
	# ---- sparks: step until ricochet or plate-shear effects were drawn (more machines if the first ones die early)
	var waves := 1
	var shot_sp := false
	var shot_si := false
	for step in 200:
		await pt._wait(0.5)
		mv.join_sim()
		if not shot_sp and (_made(mv, "ricochet71") >= 3 or _made(mv, "plate_shear71") >= 1):
			await pt._shot("damage71_sparks")
			shot_sp = true
		if not shot_si and (_made(mv, "part_down71") >= 1 or _made(mv, "silver71") >= 3):
			await pt._wait(0.3)
			await pt._shot("damage71_silver")
			shot_si = true
		if shot_sp and shot_si and step >= 20:
			break
		if _machines(w, mfid, P, 30.0) == 0 and waves < 6:
			_wave(w, mfid, W)
			waves += 1
	var counts := {}
	for k in ["ricochet71", "plate_shear71", "part_down71", "silver71"]:
		counts[k] = _made(mv, k)
	pt._log("damage71_sparks", counts.ricochet71 + counts.plate_shear71 > 0, "fx drawn %s, machine waves %d, tick %d" % [str(counts), waves, w.tick])
	pt._log("damage71_silver", counts.part_down71 + counts.silver71 > 0, "silver effects %d + %d" % [counts.part_down71, counts.silver71])
	if not shot_sp:
		await pt._shot("damage71_sparks")
	if not shot_si:
		await pt._shot("damage71_silver")
	var silver := 0
	var fl = mv.fx_layer
	if fl != null and fl.get("fx61") != null:
		for d in fl.fx61.decals:
			if String(d.tx) == "silver" and float(d.fade) < 0.0:
				silver += 1
	pt._log("damage71_silver_pools", true, "live silver pools %d" % silver)
	mv.center_camera_on(P + Vector2(-5, 0))
	_zoom(mv, 1.5)
	await pt._wait(1.0)
	await pt._shot("damage71_wide")
