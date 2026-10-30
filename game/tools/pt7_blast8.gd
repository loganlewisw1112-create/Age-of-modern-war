extends RefCounted
## G7 playtest flow blast8 (BLAST8, G7_REFERENCE 13.9c-47): a real enemy self-propelled howitzer (a_sp_howitzer, its own
## g6_sp_howitzer shells through Combat's splash -> Shrapnel.burst -> Blast8) shells our infantry group in the
## open (the shells come from an enemy gun with a spotter; our men are the ones thrown, so they are drawn). Shots: before, mid-throw (sim paused while men are in the air: arc height, ground shadow, tumble), after
## landing (knocked-down / unconscious men with the "zzz" marker), and an unconscious soldier selected (wound card
## UNCONSCIOUS). Checks: someone was thrown, the arc is drawn (g7v bt while flying), landing on walkable ground,
## someone is unconscious and ignores a move order, and wakes up later.

const H = preload("res://tests/test_machine_g6.gd")
const Blast8 = preload("res://sim/systems/blast8.gd")
const Shrapnel = preload("res://sim/systems/shrapnel.gd")
const Movement = preload("res://sim/systems/movement.gd")


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam != null and cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	elif cam != null:
		cam.zoom = Vector2(z, z)


func _fl(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get("blast8")
	return (st.fl as Dictionary) if st != null else {}


func _unc_ids(w: SimWorld, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		if w.entities.has(int(id)) and Blast8.unconscious(w, int(id)):
			out.append(int(id))
	return out


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	pt._log("blast8_registered", Blast8.registered(), "Blast8 in SYSTEM_ORDER")
	var c: Vector2i = h._open(w, 9)
	var cf := Vector2(c) + Vector2(0.5, 0.5)
	# our infantry group (owner 0, drawn and selectable) in the open, tight 4 x 3
	var grp: Array = []
	for k in 12:
		var e: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(float(k % 4) * 0.55 - 0.8, float(k / 4) * 0.6 - 0.6))
		e.order = {"type": "hold", "target": e.pos}
		grp.append(int(e.id))
	# an enemy howitzer + its spotter (vision on the group for side 1)
	var how: Dictionary = h._unit(w, "a_sp_howitzer", 1, cf + Vector2(-12.0, 4.0))
	var spot: Dictionary = h._unit(w, "rifleman", 1, cf + Vector2(-5.0, -3.0))
	spot.order = {"type": "hold", "target": spot.pos}
	spot["hold_fire"] = true
	mv.center_camera_on(cf)
	_zoom(mv, 2.0)
	mv.speed = 1.0
	await pt._wait(0.8)
	await pt._shot("blast8_before")
	var r: Dictionary = w.submit({"type": "attack", "unit_ids": [int(how.id)], "target_id": int(grp[5]), "issuer": 1})
	pt._log("blast8_fire_order", bool(r.get("ok", false)), str(r.get("reason", "")))
	# wait (per frame) until someone is in the air
	var t0 := Time.get_ticks_msec()
	while _fl(w).is_empty() and Time.get_ticks_msec() - t0 < 40000:
		await pt.get_tree().process_frame
	var fallback := false
	if _fl(w).is_empty():
		fallback = true   # the gun never hit: one shell of its own weapon at the group (same Shrapnel path as Combat)
		var s := Content.weapon("g6_sp_howitzer").duplicate()
		Shrapnel.burst(w, cf, Shrapnel.from_weapon(s), how, false, false)
	pt._log("blast8_real_shell", not fallback, "thrown by the howitzer's own shell (fallback burst used: %s)" % str(fallback))
	var thrown := _fl(w).keys()
	pt._log("blast8_thrown", not thrown.is_empty(), "%d men thrown" % thrown.size())
	if thrown.is_empty():
		return
	var fid := int(thrown[0])
	for id in thrown:   # the highest flight
		if float(_fl(w)[id][4]) > float(_fl(w)[fid][4]):
			fid = int(id)
	var f: Array = _fl(w)[fid]
	# mid-throw: let the flight reach ~40 %, freeze the sim, take the shot
	var t1 := Time.get_ticks_msec()
	while _fl(w).has(fid) and float(w.tick - int(f[5])) / float(f[6]) < 0.4 and Time.get_ticks_msec() - t1 < 5000:
		await pt.get_tree().process_frame
	mv.speed = 0.0
	var fe = w.entities.get(fid)
	var gv: Dictionary = (w.sys_state.get("g7v", {}) as Dictionary).get(fid, {})
	pt._log("blast8_arc_display", gv.has("bt") and fe != null, "g7v %s, peak %.2f m over %d ticks" % [str(gv.get("bt", [])), float(f[4]), int(f[6])])
	if fe != null:
		mv.center_camera_on(Vector2(fe.pos))
	await pt._wait(0.3)
	await pt._shot("blast8_mid_throw")
	_zoom(mv, 3.0)
	await pt._wait(0.3)
	await pt._shot("blast8_mid_throw_close")
	# ANIM8B (13.9c-52): the impact a few ticks after he lands (impact frame, bounce, skid along the throw, dust puff)
	mv.speed = 1.0
	var land_t := int(f[5]) + int(f[6]) + 3
	var t2 := Time.get_ticks_msec()
	while w.tick < land_t and Time.get_ticks_msec() - t2 < 8000:
		await pt.get_tree().process_frame
	mv.speed = 0.0
	if w.entities.has(fid):
		mv.center_camera_on(Vector2(w.entities[fid].pos))
	await pt._wait(0.3)
	await pt._shot("blast8_impact_skid")
	_zoom(mv, 2.0)
	mv.speed = 1.0
	var landed: bool = await pt._wait_until(func(): return _fl(w).is_empty(), 10.0)
	var ok_cells := true
	for id in thrown:
		var e = w.entities.get(int(id))
		if e != null and not Movement.is_passable_e(w, e, w.cell_of(Vector2(e.pos))):
			ok_cells = false
	pt._log("blast8_landed_walkable", landed and ok_cells, "all landed %s, walkable %s" % [str(landed), str(ok_cells)])
	var unc := _unc_ids(w, grp)
	pt._log("blast8_unconscious", not unc.is_empty(), "%d of %d unconscious, %d alive" % [unc.size(), grp.size(), grp.filter(func(i): return w.entities.has(int(i))).size()])
	# ACCURACY8B (13.9c-53): men near the burst who were not knocked out are dazed (e.b8d)
	var dz := 0
	var awake := 0   # alive and not knocked out: the men who could be dazed
	for id in grp:
		var ge = w.entities.get(int(id))
		if ge != null and not unc.has(int(id)):
			awake += 1
		if ge != null and int(ge.get("b8d", -1)) > w.tick:
			dz += 1
	pt._log("blast8_dazed", dz > 0 or awake == 0, "%d dazed (e.b8d) of %d awake survivors (%d unconscious, %d of 12 alive)" % [dz, awake, unc.size(), grp.filter(func(i): return w.entities.has(int(i))).size()])
	mv.center_camera_on(cf)
	await pt._wait(0.6)
	await pt._shot("blast8_after_landing")
	if unc.is_empty():
		await _ff_scene(pt, mv, w, h, cf, grp + [int(how.id), int(spot.id)])
		return
	var u: Dictionary = w.entities[int(unc[0])]
	mv.center_camera_on(Vector2(u.pos))
	_zoom(mv, 3.0)
	mv.select_ids([int(u.id)])
	await pt._wait(0.6)
	await pt._shot("blast8_unconscious_selected")
	var up0: Vector2 = u.pos
	var mr: Dictionary = w.submit({"type": "move", "unit_ids": [int(u.id)], "target": up0 + Vector2(4.0, 0.0), "issuer": 0})
	await pt._wait(1.0)
	pt._log("blast8_unconscious_ignores_orders", not w.entities.has(int(u.id)) or Vector2(u.pos).distance_to(up0) < 0.05,
		"order ok %s, moved %.2f" % [str(mr.get("ok", false)), Vector2(u.pos).distance_to(up0)])
	mv.select_ids([])
	_zoom(mv, 2.0)
	mv.speed = 3.0
	var woke: bool = await pt._wait_until(func(): return not w.entities.has(int(u.id)) or not Blast8.unconscious(w, int(u.id)), 40.0)
	pt._log("blast8_wakes", woke, "alive %s, unconscious %s" % [str(w.entities.has(int(u.id))), str(w.entities.has(int(u.id)) and Blast8.unconscious(w, int(u.id)))])
	# ANIM8B (13.9c-52): mid wake-up (the view lies him down K8_KD = 30 ticks after his knock-down, then 30 ticks of
	# coming round): pause about 12 ticks into it and take a close shot
	mv.speed = 1.0
	if woke and w.entities.has(int(u.id)):
		var gv2: Dictionary = (w.sys_state.get("g7v", {}) as Dictionary).get(int(u.id), {})
		var wake_t := maxi(w.tick, int(gv2.get("kd", -100000)) + 30) + 12
		var t3 := Time.get_ticks_msec()
		while w.tick < wake_t and Time.get_ticks_msec() - t3 < 8000:
			await pt.get_tree().process_frame
		mv.speed = 0.0
		mv.center_camera_on(Vector2(u.pos))
		_zoom(mv, 3.0)
		await pt._wait(0.3)
		await pt._shot("blast8_mid_wake")
		_zoom(mv, 2.0)
		mv.speed = 1.0
	await pt._shot("blast8_after_wake")
	await _ff_scene(pt, mv, w, h, cf, grp + [int(how.id), int(spot.id)])


## ACCURACY8B (13.9c-53): friendly fire from a stray round. Our rifleman fires at an enemy with one of our men standing
## just off the line of fire; a missed round flies on and hits him (Stray8: StrayHit + FriendlyFire events). The sim is
## frozen on the first friendly hit and the shot is taken with the event's text shown in a playtest overlay label.
func _ff_scene(pt, mv, w: SimWorld, h, cf: Vector2, clear_ids: Array) -> void:
	for id in clear_ids:
		if w.entities.has(int(id)):
			w.destroy(int(id), "playtest")
	await pt._wait(0.3)
	var sh: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(-4.0, 0.0))
	var fr: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(-0.5, 0.12))
	fr.order = {"type": "hold", "target": fr.pos}
	fr["hold_fire"] = true
	var en: Dictionary = h._unit(w, "rifleman", 1, cf + Vector2(1.8, 0.0))
	en.order = {"type": "hold", "target": en.pos}
	en["hold_fire"] = true
	mv.center_camera_on(cf + Vector2(-0.5, 0.0))
	_zoom(mv, 3.0)
	mv.speed = 1.0
	var r: Dictionary = w.submit({"type": "attack", "unit_ids": [int(sh.id)], "target_id": int(en.id), "issuer": 0})
	pt._log("ff_attack_order", bool(r.get("ok", false)), str(r.get("reason", "")))
	var ev_txt := ""
	var t0 := Time.get_ticks_msec()
	while ev_txt == "" and Time.get_ticks_msec() - t0 < 60000:
		for ev in w.events:
			if String(ev.get("type", "")) == "FriendlyFire":
				ev_txt = "FriendlyFire  tick %d: stray round from rifleman #%d hit OUR rifleman #%d" % [w.tick, int(ev.shooter), int(ev.target)]
		if w.entities.has(int(en.id)):
			en.hp = 1.0e6   # keep the enemy standing so the fire continues
		if ev_txt == "":
			await pt.get_tree().process_frame
	mv.speed = 0.0
	pt._log("ff_stray_hit", ev_txt != "", ev_txt if ev_txt != "" else "no friendly-fire stray in 60 s")
	if ev_txt == "":
		return
	var lb := Label.new()
	lb.text = "[playtest log] " + ev_txt
	lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	lb.position = Vector2(330, 600)
	var cl := CanvasLayer.new()
	cl.layer = 120   # above the HUD
	cl.add_child(lb)
	pt.get_tree().root.add_child(cl)
	await pt._wait(0.4)
	await pt._shot("accuracy8b_friendly_fire")
	cl.queue_free()
	mv.speed = 1.0
