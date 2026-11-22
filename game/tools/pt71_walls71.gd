extends RefCounted
## G7.1 BASTION71 playtest (windowed): start a Last Protocol run and shoot the G3 / I2 wall tech the owner should see:
## wall armour tiers (composite, nanite-resistant), hidden firing ports (ORCH's LP-base port fits), an electrified top,
## a wall lift, a gate with murder holes + pop-up gun + reinforcement under attack, a choke door sealing against
## crawlers, and sonic-sensor contacts (burrowers) on the map and the minimap. The flow writes the sim only between
## steps (match_view.join_sim) and says what it forces: the tier upgrades and fits (free, the same calls the wall_tier /
## gate_reinforce commands make), the Machines it spawns, the map explored. Registration: ORCH (flow name walls71).

const MapGen = preload("res://sim/map_gen.gd")
const Walls71 = preload("res://sim/systems/walls71.gd")
const Sensors71 = preload("res://sim/systems/sensors71.gd")
const Threats7 = preload("res://sim/systems/threats7.gd")


func _of(w: SimWorld, fid: int, def_id: String) -> Array:
	var out := []
	for e in w.entities.values():
		if e.kind == "building" and int(e.owner) == fid and String(e.def) == def_id and bool(e.get("built", false)):
			out.append(e)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


func _walls_near(w: SimWorld, fid: int, p: Vector2, r: float) -> Array:
	var out := []
	for e in w.entities.values():
		if e.kind == "building" and int(e.owner) == fid and String(e.def) == "a_wall" and Vector2(e.pos).distance_to(p) <= r:
			out.append(e)
	out.sort_custom(func(a, b): return Vector2(a.pos).distance_to(p) < Vector2(b.pos).distance_to(p) or (Vector2(a.pos).distance_to(p) == Vector2(b.pos).distance_to(p) and int(a.id) < int(b.id)))
	return out


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	var started: bool = pt.main.start_match(LP.make_config(71, map))
	pt._log("walls71_match_started", started, "map %s" % map)
	if not started:
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 60.0)
	mv.join_sim()
	var w: SimWorld = pt._w()
	pt._log("walls71_setup", ok, "LP filled at tick %d" % w.tick)
	if not ok:
		return
	var s: Dictionary = w.sys_state.lp
	var fid := int(s.fid)
	var ex: PackedByteArray = w.fog[0].explored
	ex.fill(1)
	w.fog[0].explored = ex
	var C := Vector2(s.base.center) + Vector2(0.5, 0.5)
	var gates := _of(w, fid, "a_gate")
	pt._log("walls71_gate_found", not gates.is_empty(), "%d gates" % gates.size())
	if gates.is_empty():
		return
	var g: Dictionary = gates[0]
	var gp := Vector2(g.pos)
	var out := (gp - C).normalized()
	# forced (free): the gate's defences and a row of walls beside it in each tier / fit
	var gf := [Walls71.fit(w, g, "murder"), Walls71.fit(w, g, "popup"), Walls71.fit(w, g, "reinforce")]
	var near := _walls_near(w, fid, gp, 9.0)
	var tiers := []
	for i in mini(near.size(), 8):
		var b: Dictionary = near[i]
		var t := 2 if i % 2 == 0 else 1
		tiers.append([int(b.id), Walls71.upgrade(w, b, t, true)])
	var wa = near[0] if near.size() > 0 else null
	var wb = near[1] if near.size() > 1 else null
	var wc = near[2] if near.size() > 2 else null
	if wa != null: Walls71.fit(w, wa, "electric")
	if wb != null: Walls71.fit(w, wb, "choke")
	if wc != null: Walls71.fit(w, wc, "lift")
	var ports := 0
	var st = w.sys_state.get("walls71")
	if st != null:
		for id in (st.fit as Dictionary).keys():
			if (st.fit[id] as Array).has("port"):
				ports += 1
	pt._log("walls71_fits", gf == [true, true, true] and wa != null and wb != null and wc != null, "gate %d murder/popup/reinforce %s; tiers %s; ports in base %d" % [int(g.id), gf, tiers, ports])
	mv.center_camera_on(gp - out * 2.0)
	await pt._wait(2.0)
	await pt._shot("walls71_tiers_ports_gate")
	# forced: 12 crawlers onto the gate and the choke wall
	mv.join_sim()
	w = pt._w()
	var side := Vector2(-out.y, out.x)
	var mids := []
	for i in 12:
		mids.append(w.spawn_unit("m_scout_crawler", int(s.mfid), gp + out * 6.0 + side * (float(i % 4) - 1.5) * 0.8 + out * float(i / 4) * 0.8))
	w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": mids, "target": gp})
	var gid := int(g.id)
	var bid := int(wb.id)
	# g9: the choke wall can stand up to 9 tiles from the gate, so the gate crawlers never came within its seal radius
	# before the murder holes killed them; a second group of 4 starts on the choke wall's outer side (setup only)
	var cmids := []
	for i in 4:
		cmids.append(w.spawn_unit("m_scout_crawler", int(s.mfid), Vector2(wb.pos) + out * (3.0 + float(i) * 0.5)))
	w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": cmids, "target": gp})
	var hit: bool = await pt._wait_until(func():
		var s2 = pt._w().sys_state.get("walls71")
		return s2 != null and (s2.seal as Dictionary).has(bid) and (s2.cd as Dictionary).has(gid * 8 + 3), 30.0)
	var s3 = pt._w().sys_state.get("walls71")
	pt._log("walls71_gate_guns_choke_sealed", hit, "choke %d sealed %s, gate guns fired %s" % [bid, s3 != null and (s3.seal as Dictionary).has(bid), s3 != null and (s3.cd as Dictionary).has(gid * 8 + 3)])
	await pt._shot("walls71_gate_fight_choke_sealed")
	# sonic sensors: burrowers tunnelling at the base (forced spawn beside an outer sensor)
	mv.join_sim()
	w = pt._w()
	var sens := _of(w, fid, "a_g71_sonic_sensor")
	pt._log("walls71_sensor_found", not sens.is_empty(), "%d sonic sensors" % sens.size())
	if sens.is_empty():
		return
	var sp := Vector2(sens[0].pos)
	var so := (sp - C).normalized()
	var bur := []
	for i in 3:
		bur.append(Threats7.spawn(w, "g7_m_burrower", int(s.mfid), sp + so * (8.0 + float(i) * 1.5) + Vector2(-so.y, so.x) * float(i - 1) * 2.0))
	w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": bur, "target": sp - so * 4.0})
	mv.center_camera_on(sp + so * 3.0)
	var got: bool = await pt._wait_until(func(): return not Sensors71.contacts(pt._w(), fid).is_empty(), 40.0)
	pt._log("walls71_sensor_contacts", got, "contacts %s" % [str(Sensors71.contacts(pt._w(), fid)).left(200)])
	await pt._wait(1.0)
	await pt._shot("walls71_sensor_contacts_minimap")
	# BASTION71-8: a wall gun firing at the FPF strip of face 0 (FIRES71 fpf_fire; no target in range)
	mv.join_sim()
	w = pt._w()
	var KZ = load("res://sim/systems/killzone71.gd")
	var fs: Dictionary = KZ.fpf_strip(w, 0)
	var fmid := (Vector2(float(fs.a[0]), float(fs.a[1])) + Vector2(float(fs.b[0]), float(fs.b[1]))) * 0.5
	var wall_x := float(KZ.face_line(w, 0)[0].x)
	var gun := w.spawn_building("a_t7_hmg_nest", fid, Vector2i(int(wall_x) - 3, int(fmid.y)), true)
	w.spawn_unit("a_mortar", fid, fmid + Vector2(-9, 0))
	w.submit({"type": "fpf_fire", "issuer": fid, "face": 0})
	mv.center_camera_on(Vector2(float(wall_x) + 5.0, float(fmid.y)))
	mv.camera.set_zoom_level(1.4)
	await pt._wait(3.0)
	pt._log("walls71_fpf_wall_gun", w.entities.has(gun), "hmg nest %d on face 0 firing at the FPF strip %s" % [gun, str(fs).left(80)])
	await pt._shot("walls71_wall_gun_fpf")
	# BASTION71-8: a breacher dozer clears wrecks / bodies, then pushes up an earth berm
	mv.join_sim()
	w = pt._w()
	var G = load("res://sim/systems/gore71.gd")
	var spot := gp + out * 7.0 + side * 5.0   # g9: open ground outside the gate (inside the base the camera framed buildings)
	var dz := w.spawn_unit("a_g71_breacher", fid, spot - out * 3.0)
	for i in 6:
		G.add_body(w, {"kind": "wreck" if i % 2 == 0 else "body", "def": "m_scout_crawler", "owner": int(s.mfid), "pos": spot + side * (float(i % 3) - 1.0) * 0.9 + out * float(i / 3) * 0.8, "rot": float(i), "out": "", "t": 0, "sz": 0.6 if i % 2 == 0 else 0.4})
	w.submit({"type": "doze_clear", "issuer": fid, "unit_ids": [dz], "at": [spot.x, spot.y]})
	mv.center_camera_on(spot)
	mv.camera.set_zoom_level(2.5)
	await pt._wait(4.0)
	mv.center_camera_on(Vector2(pt._w().entities[dz].pos) if pt._w().entities.has(dz) else spot)
	await pt._wait(0.1)
	pt._log("walls71_dozer_clearing", pt._w().entities.has(dz), "dozer %d clearing 6 wrecks / bodies at %s" % [dz, spot])
	await pt._shot("walls71_dozer_clearing")
	var bf := Vector2i(spot + side * 3.0)
	var bt := Vector2i(spot + side * 3.0 + out * 4.0)
	pt._w().submit({"type": "berm_build", "issuer": fid, "unit_ids": [dz], "from": [bf.x, bf.y], "to": [bt.x, bt.y]})
	var bermed: bool = await pt._wait_until(func():
		for e in pt._w().entities.values():
			if e.kind == "building" and String(e.def) == "a_g71_berm" and int(e.owner) == fid and bool(e.get("built", false)):
				return true
		return false, 40.0)
	pt._log("walls71_dozer_berm", bermed, "berm from %s to %s" % [bf, bt])
	mv.center_camera_on((Vector2(bf) + Vector2(bt)) * 0.5 + Vector2(0.5, 0.5))
	mv.camera.set_zoom_level(2.5)
	await pt._wait(1.0)
	await pt._shot("walls71_dozer_berm")
