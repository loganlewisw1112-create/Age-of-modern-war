extends RefCounted
## G7 playtest flow wallturret7 (WTUR7 / WTUR7-2, G7_REFERENCE 13.9c-9 "unmanned AI turrets attached to the sides of
## some of the walls (can be selected and destroyed + rebought and placed elsewhere along the outer or inner walls of
## facility only)", 13.9c-12 the facility runs itself). In the real game: the player's counter-nanite facility rises
## with its start set of wall turrets (once FACB7 lists it); the Wall Turret is found on an engineer's build card
## (Defences tab) and placed with the build ghost on an OUTER face (east wall, engineer outside) and an INNER face
## (north wall, engineer inside); the ghost is red on open ground and snaps to a face next to the cursor; enemies
## attack the walls and the turrets fire outward (outer at the attackers, inner at an infiltrator); the outer one is
## destroyed (wreck mark, wall-walk kept); the facility queues its rebuild by itself (13.9c-12) and the player
## cancels it from the construction card (player control first); the player rebuys one and places it on another
## face; the turret is selected by a click. Shots at zoom 1 / 1.75 / 2.5 of a near-face turret, a far-face turret
## (head over the parapet), the inner-face turret, the fight, the wreck, the queued rebuild and the rebought one.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-wallturret7   (ORCH registered "wallturret7")

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
const WallTurret7 = preload("res://sim/systems/wallturret7.gd")
const Construction = preload("res://sim/systems/construction.gd")
const HotState = preload("res://sim/hot_state.gd")


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
		await pt._shot("wallturret7_%s_z%d" % [tag, int(z * 100)])


func _turret_at(w: SimWorld, cell: Vector2i) -> int:
	for id in WallTurret7.turret_ids(w):
		var e = w.entities.get(id)
		if e != null and Vector2i(e.cell) == cell:
			return int(id)
	return -1


## Player gesture: engineer selected, build tool armed with the wall turret, left click on the face cell.
func _place(pt, mv, def_id: String, eng: int, cell: Vector2i) -> int:
	mv.selection.clear()
	mv.selection.append(eng)
	mv.begin_build_placement(def_id)
	_zoom(mv, 1.0)
	mv.center_camera_on(Vector2(cell))
	await pt._wait(0.4)
	await pt._click(pt._to_screen(Vector2(cell) + Vector2(0.5, 0.5)))
	var ok: bool = await pt._wait_until(func(): mv.join_sim(); return _turret_at(pt._w(), cell) >= 0, 6.0)
	mv.join_sim()
	if mv.placing_def != "":
		mv.cancel_placement()
	return _turret_at(pt._w(), cell) if ok else -1


## Shot events of shooter sid in the latest tick (the poll runs every frame), or its firing hint.
func _shot_by(w: SimWorld, sid: int) -> bool:
	for ev in w.events:
		if String(ev.get("type", "")) == "ShotFired" and int(ev.get("shooter", -1)) == sid:
			return true
	return int(w.entities.get(sid, {}).get("firing", 0)) > 0


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty() or Content.building("a_wt7_wall_turret").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var foe := -1
	for f in w.factions:
		if int(f) != me and w.is_enemy(me, int(f)):
			foe = int(f)
			break
	w.factions[me].stage = maxi(int(w.factions[me].get("stage", 1)), 10)
	w.credit(me, {"credits": 20000, "ore": 5000}, "playtest")
	var c: Vector2i = h._open(w, 24)
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(14, 14)
	var fid := w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): mv.join_sim(); return not CnFacility.facilities(pt._w(), me).is_empty(), 8.0)
	pt._log("wallturret7_facility_raised", raised, "facility %d" % fid)
	if not raised:
		return
	await pt._wait(0.5)
	mv.join_sim()
	var reg := SimWorld.SYSTEM_ORDER.has(WallTurret7)
	pt._log("wallturret7_system_registered", reg, "WallTurret7 in SYSTEM_ORDER (ORCH CR change_request.world_wallturret7)")
	var F: Dictionary = CnFacility.fac(w, CnFacility.facilities(w, me)[0])
	var O: Vector2i = CnFacility.origin(F)
	var ex: PackedByteArray = w.fog[me].explored
	ex.fill(1)
	w.fog[me].explored = ex
	var def_id := WallTurret7.def_for(w, me)
	var listed: Array = CnFacility.conf().get("wall_turrets", [])
	var start := WallTurret7.turret_ids(w).size()
	pt._log("wallturret7_facility_starts_with_turrets", start == listed.size() and (start >= 8 or listed.is_empty()), "%d wall turrets at start, %d listed in the facility layout (FACB7 conf wall_turrets; 0 = not switched yet)" % [start, listed.size()])
	var nests := 0
	for e in w.entities.values():
		if e.kind == "building" and String(e.def) == "a_t7_hmg_nest" and int(e.get("cn_fac", -1)) >= 0:
			nests += 1
	pt._log("wallturret7_no_manned_nests", true, "%d manned nests left on the facility (FACB7 removes them; info)" % nests)
	if start > 0:
		await _shots(pt, mv, Vector2(O) + Vector2(14.0, 14.0), "start_set")
		await _shots(pt, mv, Vector2(O) + Vector2(9.5, 27.5), "start_set_south_wall")   # the camera-facing outer row
	# the build card: an engineer inside the compound, Defences tab, the Wall Turret button arms the ghost
	var eng: Dictionary = h._unit(w, "engineer", me, Vector2(O) + Vector2(14.5, 12.5))
	mv.selection.clear()
	mv.selection.append(int(eng.id))
	_zoom(mv, 1.0)
	mv.center_camera_on(Vector2(eng.pos))
	await pt._wait(0.6)
	await pt._click_button("Defences")
	await pt._wait(0.3)
	var btn = pt._find_button(pt.get_tree().root, "Wall Turret")
	var pages := 0
	while btn == null and pages < 4 and pt._find_button(pt.get_tree().root, "More") != null:
		await pt._click_button("More")
		await pt._wait(0.3)
		pages += 1
		btn = pt._find_button(pt.get_tree().root, "Wall Turret")
	pt._log("wallturret7_on_build_card", btn != null and not btn.disabled, "Wall Turret on the engineer's Defences card (page %d)%s" % [pages + 1, "" if btn == null else (", disabled" if btn.disabled else ", enabled")])
	await pt._shot("wallturret7_build_card")
	if btn != null:
		await pt._click(btn.get_global_rect().get_center())
		await pt._wait(0.3)
	pt._log("wallturret7_card_arms_ghost", mv.placing_def == def_id, "placing_def %s" % String(mv.placing_def))
	if mv.placing_def != def_id:
		mv.begin_build_placement(def_id)
	# ghost: red on open ground, snaps to a face next to the cursor
	var red := Construction.placement_error(w, me, def_id, mv.placement_origin(def_id, Vector2(O) + Vector2(14.5, 12.5)))
	var outer := O + Vector2i(27, 10)    # east wall outer row (a camera-facing face)
	var inner := O + Vector2i(11, 1)     # north wall inner row (faces into the compound, camera-facing)
	var gh: Vector2i = mv.placement_origin(def_id, Vector2(outer) + Vector2(0.9, 0.4))
	pt._log("wallturret7_ghost_red_off_wall", red != "", "open yard: %s" % red)
	pt._log("wallturret7_ghost_snaps_to_face", gh == outer and Construction.placement_error(w, me, def_id, gh) == "", "cursor next to the east outer face -> origin %s (want %s): %s" % [str(gh - O), str(outer - O), Construction.placement_error(w, me, def_id, gh)])
	_zoom(mv, 1.75)
	mv.center_camera_on(Vector2(outer) + Vector2(0.9, 0.4))
	mv.demo_mouse_world = Vector2(outer) + Vector2(0.9, 0.4)   # the cursor next to the face: the ghost snaps onto it
	await pt._wait(0.5)
	await pt._shot("wallturret7_ghost_snap_z175")
	mv.demo_mouse_world = Vector2(O) + Vector2(31.5, 4.5)      # open ground outside: red
	await pt._wait(0.5)
	await pt._shot("wallturret7_ghost_red_z175")
	mv.demo_mouse_world = null
	mv.cancel_placement()
	# outer face: an engineer outside the east wall; inner face: the engineer inside
	var eng_out: Dictionary = h._unit(w, "engineer", me, Vector2(O) + Vector2(30.5, 10.5))
	var t_out: int = await _place(pt, mv, def_id, int(eng_out.id), outer)
	pt._log("wallturret7_placed_outer_face", t_out >= 0, "turret %d on the east outer face %s" % [t_out, str(outer - O)])
	var t_in: int = await _place(pt, mv, def_id, int(eng.id), inner)
	pt._log("wallturret7_placed_inner_face", t_in >= 0, "turret %d on the north inner face %s" % [t_in, str(inner - O)])
	if t_out < 0 or t_in < 0:   # keep the rest of the flow running (the failure is logged above)
		mv.join_sim()
		if t_out < 0:
			t_out = w.spawn_building(def_id, me, outer, true)
		if t_in < 0:
			t_in = w.spawn_building(def_id, me, inner, true)
	var built: bool = await pt._wait_until(func(): mv.join_sim(); var ww: SimWorld = pt._w(); return ww.entities.has(t_out) and bool(ww.entities[t_out].built) and ww.entities.has(t_in) and bool(ww.entities[t_in].built), 60.0)
	pt._log("wallturret7_engineer_built_both", built, "outer built %s, inner built %s" % [str(w.entities.has(t_out) and bool(w.entities[t_out].built)), str(w.entities.has(t_in) and bool(w.entities[t_in].built))])
	mv.join_sim()
	await _shots(pt, mv, Vector2(outer) + Vector2(0.5, 0.5), "outer_face_east")
	await _shots(pt, mv, Vector2(inner) + Vector2(0.5, 1.5), "inner_face_north")
	# far faces (the wall stands between the camera and the turret: the head must show over the parapet)
	var far := -1
	for id in WallTurret7.turret_ids(w):
		var e: Dictionary = w.entities[id]
		if int(e.get("wt_m", 0)) >= 2 and not bool(WallTurret7.face_info(w, -1, def_id, Vector2i(e.cell), int(id)).get("inner", true)):
			far = int(id)
			break
	if far < 0:   # no start set yet: put two up on the north and west outer faces for the look (built directly)
		mv.join_sim()
		far = w.spawn_building(def_id, me, O + Vector2i(13, 0), true)
		w.spawn_building(def_id, me, O + Vector2i(0, 15), true)
		await pt._wait(0.3)
		mv.join_sim()
	await _shots(pt, mv, Vector2(w.entities[far].pos), "far_face_over_parapet")
	# select by clicking the turret
	mv.join_sim()
	_zoom(mv, 1.75)
	mv.center_camera_on(Vector2(outer) + Vector2(0.5, 0.5))
	await pt._wait(0.4)
	await pt._click(pt._to_screen(Vector2(outer) + Vector2(0.5, 0.5)))
	await pt._wait(0.3)
	pt._log("wallturret7_selected_by_click", mv.selection.has(t_out), "selection %s (ORCH CR match_view_wallturret7 picks the turret over its wall)" % str(mv.selection))
	await pt._shot("wallturret7_selected_z175")
	# enemies attack the east wall from outside, and an infiltrator inside the north wall
	var foes := []
	var inf_id := -1
	var atk := "no enemy side"
	if foe >= 0:
		# WTUR7-3: a real assault on the east wall: two main battle tanks and four AT gunners (anti-structure weapons; a
		# rifle does 0.15x to a building) close to 4-5 tiles outside the wall, ordered onto the outer turret. The facility's towers and
		# its other wall turrets fire back at them as they would in a match.
		var squad := []
		for i in 6:
			var ud := "mbt" if i < 2 else "at_gunner"
			var en: Dictionary = h._unit(w, ud, foe, Vector2(O) + Vector2(31.5 + (i % 2), 7.5 + i * 1.0))
			if ud != "mbt":
				en.max_hp = 400.0   # hardened AT team: they have to live through the turret's fire long enough to hit it
				h._hp(w, en, 400.0)   # through HotState (a plain e.hp write is lost to the hot arrays)
			foes.append(int(en.id))
			squad.append(int(en.id))
		var fg = w.fog.get(foe)
		if fg != null:   # the attackers know where the turret is (scouted): the attack order needs it explored
			var fx: PackedByteArray = fg.explored
			fx.fill(1)
			fg.explored = fx
		await pt._wait(0.6)   # their own eyes on the turret first (an attack on an unseen target walks to its last spot,
		mv.join_sim()         # a wall cell, and drops the order)
		var r: Dictionary = w.submit({"type": "attack", "issuer": foe, "unit_ids": squad, "target_id": t_out})
		atk = "attack order ok=%s %s" % [str(r.get("ok", false)), String(r.get("error", r.get("reason", "")))]
		var inf: Dictionary = h._unit(w, "rifleman", foe, Vector2(O) + Vector2(12.5, 6.5))
		HotState.set_order(w, int(inf.id), "hold")
		inf.max_hp = 100000.0   # the facility's own guards would drop it before the inner turret's first scan
		h._hp(w, inf, 100000.0)
		inf_id = int(inf.id)
		foes.append(inf_id)
	# WTUR7-3: the turret starts the fight at full health (no pre-wear): 2 MBTs + 4 AT gunners take it down in ~20 s
	var st := {"out": false, "in": false}
	var fired: bool = await pt._wait_until(func():
		mv.join_sim()
		var ww: SimWorld = pt._w()
		st.out = bool(st.out) or _shot_by(ww, t_out)
		st["in"] = bool(st["in"]) or _shot_by(ww, t_in)
		return bool(st.out) or not ww.entities.has(t_out), 20.0)
	if fired and w.entities.has(t_out):
		_zoom(mv, 1.75)
		mv.center_camera_on(Vector2(outer) + Vector2(2.5, 0.5))
		await pt._shot("wallturret7_firing_outer_z175")
	await pt._wait_until(func():
		mv.join_sim()
		var ww: SimWorld = pt._w()
		st.out = bool(st.out) or _shot_by(ww, t_out)
		st["in"] = bool(st["in"]) or _shot_by(ww, t_in)
		return not ww.entities.has(t_out) and bool(st["in"]), 45.0)
	mv.join_sim()
	pt._log("wallturret7_fires_outward", bool(st.out), "outer turret fired at the attackers outside")
	pt._log("wallturret7_inner_covers_compound", bool(st["in"]) or foe < 0, "inner turret fired at the infiltrator inside")
	if inf_id >= 0 and w.entities.has(inf_id):
		_zoom(mv, 1.75)
		mv.center_camera_on(Vector2(inner) + Vector2(1.0, 3.0))
		await pt._wait(0.3)
		await pt._shot("wallturret7_inner_firing_z175")
	var lost := not w.entities.has(t_out)
	if not lost:
		w.destroy(t_out, "playtest", foe)   # attackers too slow: finish it so the rest of the flow runs
		mv.join_sim()
	pt._log("wallturret7_destroyed_in_fight", lost, "outer turret destroyed by the attackers (%s)" % atk)
	await pt._wait(0.3)
	mv.join_sim()
	var wreck := false
	for e in w.entities.values():
		if e.kind == "wreck" and String(e.def) == def_id and w.cell_of(e.pos) == outer:
			wreck = true
	pt._log("wallturret7_wreck_mark", wreck, "wreck at the face")
	pt._log("wallturret7_wall_walk_kept", Movement.wallwalk_team(w, outer) >= 0, "wall-walk on the cell %s" % str(Movement.wallwalk_team(w, outer)))
	for id in foes:
		if w.entities.has(id):
			w.destroy(id, "playtest", me)
	await _shots(pt, mv, Vector2(outer) + Vector2(0.5, 0.5), "wreck")
	# 13.9c-12: the facility queues the rebuild of its lost turret by itself
	var auto: bool = await pt._wait_until(func(): mv.join_sim(); var t := _turret_at(pt._w(), outer); return t >= 0 and not bool(pt._w().entities[t].built), 30.0)
	mv.join_sim()
	var site := _turret_at(w, outer)
	pt._log("wallturret7_auto_rebuild_queued", auto, "site %d on the lost face, paid by the facility (13.9c-12)" % site)
	if site >= 0:
		await _shots(pt, mv, Vector2(outer) + Vector2(0.5, 0.5), "auto_rebuild_site")
		# player control first: select the queued site and cancel it from its construction card
		_zoom(mv, 1.75)
		mv.center_camera_on(Vector2(outer) + Vector2(0.5, 0.5))
		await pt._wait(0.3)
		await pt._click(pt._to_screen(Vector2(outer) + Vector2(0.5, 0.5)))
		await pt._wait(0.4)
		var cancelled: bool = await pt._click_button("Cancel build")
		var gone: bool = await pt._wait_until(func(): mv.join_sim(); return _turret_at(pt._w(), outer) < 0, 4.0)
		pt._log("wallturret7_player_cancels_rebuild", cancelled and gone, "Cancel build on the card: button %s, site gone %s" % [str(cancelled), str(gone)])
		var again_q: bool = await pt._wait_until(func(): mv.join_sim(); return _turret_at(pt._w(), outer) >= 0, 12.0)
		pt._log("wallturret7_cancel_sticks", not again_q, "the facility does not queue a cancelled face again")
	# rebuy: place another on a different face (south outer, by the gate)
	var again := O + Vector2i(23, 27)
	if _turret_at(w, again) >= 0:
		again = O + Vector2i(25, 27)
	var eng2: Dictionary = h._unit(w, "engineer", me, Vector2(again) + Vector2(0.5, 3.5))
	var t_re: int = await _place(pt, mv, def_id, int(eng2.id), again)
	pt._log("wallturret7_rebought_and_placed", t_re >= 0, "turret %d on %s" % [t_re, str(again - O)])
	if t_re >= 0:
		var b2: bool = await pt._wait_until(func(): mv.join_sim(); return pt._w().entities.has(t_re) and bool(pt._w().entities[t_re].built), 60.0)
		pt._log("wallturret7_rebuy_built", b2, "built")
		await _shots(pt, mv, Vector2(again) + Vector2(0.5, 0.5), "rebought_south")
