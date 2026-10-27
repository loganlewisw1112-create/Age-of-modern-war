extends RefCounted
## G7 CINE7 playtest: start a Last Protocol run and watch the opening cinematic (frames from every beat: the archive
## pre-roll, the first outbreak, the network waking, the order, the sweep over the 3 rings, the hand-over), check the
## match stayed paused (no sim tick) and control came back; skip a replayed opening with Space; preview every ending
## cinematic over the real map (several frames each, skipped at the end, the run itself untouched); then end the run
## for real (pyrrhic, after named operators fell) so the HUD plays the ending by itself and opens the end-of-run
## screen, shot at 1280x720 and 1920x1080. The flow writes the sim only between steps (match_view.join_sim) and says
## what it forces. Records go to user://pt7_cine7_records.json (never the player's file).

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CineDirector = preload("res://presentation/cine7/cine_director.gd")
const CineShot = preload("res://presentation/cine7/cine_shot.gd")
const CineData = preload("res://presentation/cine7/cine_data.gd")
const MapGen = preload("res://sim/map_gen.gd")
const REC := "user://pt7_cine7_records.json"
const OPEN_SHOTS := [[1.5, "a_preroll"], [9.0, "b_outbreak"], [16.0, "c_outbreak_late"], [19.5, "d_second_site"],
	[29.0, "e_network"], [38.0, "f_network_wide"], [45.5, "g_order"], [49.8, "h_order_stamp"], [55.5, "i_outer_ring"],
	[61.5, "j_economy_ring"], [68.0, "k_core_ring"], [72.0, "l_facility"], [76.5, "m_handover_title"], [80.6, "n_handover_open"]]


func _hud(pt):
	return pt.get_tree().root.find_child("LpHud", true, false)


## Jumps a playing director to absolute cinematic time `at` (it advances through shots like real frames would).
func _seek(cine, at: float) -> void:
	var guard := 0
	while cine != null and is_instance_valid(cine) and not cine.done and cine.elapsed < at and guard < 4000:
		cine.advance(minf(0.25, at - cine.elapsed))
		guard += 1


func _frames(pt, cine, kind: String, times: Array) -> int:
	var n := 0
	for tm in times:
		if cine == null or not is_instance_valid(cine) or cine.done:
			break
		_seek(cine, float(tm[0]))
		await pt._wait(0.45)   # a few real frames: fades, bars, teletype settle
		await pt._shot("cine7_%s_%s" % [kind, String(tm[1])])
		n += 1
	return n


func _alive_cs(w: SimWorld, fid: int, cs: String) -> bool:
	for e in w.units_of(fid):
		if String(e.get("call_sign", "")) == cs:
			return true
	return false


func _key(pt, k: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = true
	pt._push(ev)
	await pt.get_tree().process_frame
	var up := ev.duplicate()
	up.pressed = false
	pt._push(up)
	await pt.get_tree().process_frame


func run(pt) -> void:
	CineDirector.force_play = true
	CineDirector.opened.clear()
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	var started: bool = pt.main.start_match(LastProtocol.make_config(91, map))
	pt._log("cine7_match_started", started, "map %s" % map)
	if not started:
		CineDirector.force_play = false
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return _hud(pt) != null and _hud(pt).cine != null and not _hud(pt).cine.waiting, 90.0)
	var hp = _hud(pt)
	if hp == null:
		pt._log("cine7_hud", false, "LpHud missing (ORCH hud.gd hook)")
		CineDirector.force_play = false
		return
	hp.records_path = REC
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REC))
	var cine = hp.cine
	pt._log("cine7_opening_autoplays", ok and cine != null and hp.cine_log.has("opening"), "the HUD started the opening by itself (cine_log %s)" % str(hp.cine_log))
	if cine == null:
		CineDirector.force_play = false
		return
	mv.join_sim()
	var w: SimWorld = pt._w()
	var tick0 := w.tick
	var hash0 := w.state_hash()
	pt._log("cine7_opening_paused", bool(mv.paused), "match paused while the opening plays (tick %d); length %.1f s" % [tick0, cine.total])
	var n := await _frames(pt, cine, "opening", OPEN_SHOTS)
	pt._log("cine7_opening_frames", n == OPEN_SHOTS.size(), "%d opening frames shot" % n)
	var cues: Array = cine.cues if is_instance_valid(cine) else []
	mv.join_sim()   # right after the last frame (the hand-over is still playing): no tick may have run
	pt._log("cine7_opening_no_sim_ticks", pt._w().tick == tick0 and pt._w().state_hash() == hash0 and bool(mv.paused),
		"78 s of opening: tick %d -> %d, hash unchanged %s" % [tick0, pt._w().tick, str(pt._w().state_hash() == hash0)])
	if is_instance_valid(cine):
		_seek(cine, cine.total + 1.0)
	await pt._wait(0.6)
	var fac := Vector2(CineData.gather(w).facility)
	var cam_tile := Vector2(mv.screen_to_world(mv.camera.position))
	pt._log("cine7_control_handed_over", not mv.paused and hp.modal_root.visible and hp.cine == null and cam_tile.distance_to(fac) < 6.0,
		"paused %s, HUD visible %s, camera %.0f,%.0f vs facility %.0f,%.0f, cues %s" % [str(mv.paused), str(hp.modal_root.visible), cam_tile.x, cam_tile.y, fac.x, fac.y, str(cues)])
	await pt._wait(1.0)
	await pt._shot("cine7_opening_o_control")
	# ---- skip: replay the opening and press Space
	var c2 = hp.play_cinematic("opening")
	await pt._wait(1.2)
	await _key(pt, KEY_SPACE)
	var sk: bool = await pt._wait_until(func(): return c2 == null or not is_instance_valid(c2) or c2.done, 5.0)
	pt._log("cine7_skip_space", sk and (not is_instance_valid(c2) or c2.skipped) and not mv.paused, "Space skipped the opening; match unpaused %s" % str(not mv.paused))
	# ---- every ending's cinematic, previewed over the live map (the run is not ended by these)
	mv.join_sim()
	var s: Dictionary = w.sys_state.lp
	var cp = w.sys_state.get("cnprog7")
	var names := []
	if cp != null:
		var ks: Array = (cp.ops as Dictionary).keys()
		ks.sort_custom(func(a, b): return int(a) < int(b))
		for k in ks:
			if names.size() < 9:
				names.append(String(cp.ops[k].cs))
	for e in LastProtocol.ENDINGS:
		mv.join_sim()
		var r := LastProtocol.result(w, s, e)
		r.ending = e
		r.won = not e.begins_with("defeat")
		if e == "pyrrhic":
			r.remembered = names
		var ce = hp.play_cinematic(e, r)
		await pt._wait(0.3)
		mv.join_sim()
		var tick_s: int = pt._w().tick
		var tot: float = ce.total
		var times := [[tot * 0.12, "1"], [tot * 0.4, "2"], [tot * 0.68, "3"], [tot * 0.92, "4"]]
		var m := await _frames(pt, ce, e, times)
		mv.join_sim()
		var tick_e: int = pt._w().tick
		await _key(pt, KEY_ESCAPE)
		var de: bool = await pt._wait_until(func(): return ce == null or not is_instance_valid(ce) or ce.done, 5.0)
		pt._log("cine7_ending_%s" % e, m == times.size() and de and tick_s == tick_e and bool(mv.paused) == false, "%d frames, %.1f s, skipped with Esc, sim held at tick %d -> %d while it played" % [m, tot, tick_s, tick_e])
	# ---- the real ending: named operators fall, the run ends (pyrrhic), the HUD plays it and opens the screen
	mv.join_sim()
	var CN = load("res://sim/systems/counter_nanite.gd")
	var cst = w.sys_state.get("cn7")
	if cst != null:
		var teams = cst.get("teams", [])
		for t in (teams.values() if teams is Dictionary else teams):
			CN.dismount(w, t)
	pt._log("cine7_forced", true, "flow forces: every counter-nanite team dismounted, 4 named operators killed, then LastProtocol.finish(pyrrhic)")
	await pt._wait_until(func(): return (pt._w().sys_state.lp.roster as Dictionary).size() >= 8, 30.0)
	mv.join_sim()
	var killed := []
	for e2 in w.units_of(int(s.fid)):
		if killed.size() < 4 and e2.has("call_sign") and (s.roster as Dictionary).has(int(e2.id)):
			killed.append(String(e2.call_sign))
			SimWorld.HotState.set_hp(w, int(e2.id), -10.0)
	await pt._wait_until(func(): return (pt._w().sys_state.lp.remembered as Array).size() >= killed.size(), 20.0)
	mv.join_sim()
	await pt._wait(3.0)
	mv.join_sim()
	var dead_now := killed.filter(func(x): return not _alive_cs(w, int(s.fid), x))
	pt._log("cine7_remembered_recorded", not dead_now.is_empty() and dead_now.all(func(x): return (s.remembered as Array).has(x)),
		"hit %s; dead (gone from the field) %s; LP remembered %s (a hit soldier can be downed / treated instead of killed: WOUND7)" % [str(killed), str(dead_now), str(s.remembered)])
	LastProtocol.finish(w, s, "pyrrhic")
	var auto: bool = await pt._wait_until(func(): return hp.cine != null and hp.cine_log.count("pyrrhic") >= 2, 10.0)
	pt._log("cine7_real_ending_autoplays", auto, "the HUD played the pyrrhic ending by itself on LpEnding (cine_log %s)" % str(hp.cine_log))
	if auto:
		var cr = hp.cine
		await _frames(pt, cr, "real_pyrrhic", [[12.0, "epilogue"], [cr.total - 4.0, "roll"]])
		_seek(cr, cr.total + 1.0)
	var shown: bool = await pt._wait_until(func(): return hp.end_screen != null and hp.end_screen.is_visible_in_tree(), 10.0)
	var cs: Array = hp.end_screen.remembered_call_signs() if hp.end_screen != null else []
	var want := (s.result.remembered as Array).duplicate()
	pt._log("cine7_end_screen", shown and FileAccess.file_exists(REC), "end-of-run screen shown, records saved %s" % str(FileAccess.file_exists(REC)))
	var want2: Array = CineData.remembered_call_signs(w, want)
	pt._log("cine7_end_remembered", shown and cs == want2 and dead_now.all(func(x): return cs.has(x)), "screen lists %s (LP %s + CnProgress7 dead)" % [str(cs), str(want)])
	var win = pt.get_tree().root
	var sizes := [Vector2i(1280, 720), Vector2i(1920, 1080)]
	for sz in sizes:
		win.size = sz
		await pt._wait(1.0)
		var vp: Vector2 = win.get_visible_rect().size
		var pr: Rect2 = hp.end_panel.get_global_rect() if hp.end_panel != null else Rect2()
		var lay = hp.end_screen.get_parent()
		var root_sz: Vector2 = (lay as Control).size if lay is Control else vp
		var fits: bool = pr.position.x >= 0.0 and pr.position.y >= 0.0 and pr.end.x <= root_sz.x + 0.5 and pr.end.y <= root_sz.y + 0.5
		pt._log("cine7_end_screen_fits_%dx%d" % [sz.x, sz.y], fits, "viewport %s, panel %s inside %s" % [str(vp), str(pr), str(root_sz)])
		await pt._shot("cine7_end_screen_%dx%d" % [sz.x, sz.y])
	# replay button
	hp.end_screen.replay_btn.emit_signal("pressed")
	var rp: bool = await pt._wait_until(func(): return hp.cine != null, 3.0)
	await pt._wait(0.5)
	await _key(pt, KEY_ESCAPE)
	var back: bool = await pt._wait_until(func(): return hp.end_screen.is_visible_in_tree(), 5.0)
	pt._log("cine7_replay_ending", rp and back, "Watch the ending again plays it, Esc returns to the screen")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REC))
	CineDirector.force_play = false
