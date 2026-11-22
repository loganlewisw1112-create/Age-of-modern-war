extends RefCounted
## G7.1 FIRES71 playtest (windowed, Last Protocol): the hold-key radial fire menu (presentation/ui71/fire_radial.gd),
## strike shapes (line barrage along a wall lane, smoke box), FPF on one face, a painted kill-zone sector for one
## turret / unit (presentation/ui71/killzone_paint.gd), and the CONDUCTOR orbit placed from the radial; the
## presentation/view/fires71_view.gd layer draws missions, rounds, the FPF strips, sectors and the orbit.
## Click counts (player actions, before = fact fires71.survey seq 1831): lane barrage ~13 -> 2, smoke screen
## impossible -> 2, one turret / squad sector impossible -> 3. Screenshots: fires71_*.png.
## The view nodes are attached by presentation/view/g71_attach.gd (CR change_request.match_view71); until that line
## lands the flow attaches them itself (logged).
const KillZone71 = preload("res://sim/systems/killzone71.gd")
const Fires71 = preload("res://sim/systems/fires71.gd")
const Conductor71 = preload("res://sim/systems/conductor71.gd")
const MapGen = preload("res://sim/map_gen.gd")


func _node(mv, nm: String, path: String) -> Array:
	var n = mv.get_node_or_null(nm)
	if n != null:
		return [n, false]
	n = (load(path) as GDScript).new()
	n.z_index = 60
	mv.add_child(n)
	n.setup(mv)
	return [n, true]


func run(pt) -> void:
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	if not pt.main.start_match(SimWorld.LastProtocol.make_config(77, map)):
		pt._log("fires71_start", false, "start_match failed")
		return
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 60.0)
	pt._log("fires71_lp_ready", ok, "map %s" % map)
	if not ok:
		return
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	mv.join_sim()
	var f := int(w.sys_state.lp.fid)
	pt._log("fires71_player_side", int(mv.player_fid) == f, "player_fid=%d lp.fid=%d" % [int(mv.player_fid), f])
	w.credit(f, {"ammo": 100000, "credits": 100000, "fuel": 50000}, "pt71_fires71")
	var fg = w.fog.get(f)
	if fg != null:
		var ex: PackedByteArray = fg.explored
		ex.fill(1)
		fg.explored = ex
	var kz_r: Array = _node(mv, "KillZonePaint71", "res://presentation/ui71/killzone_paint.gd")
	var fr_r: Array = _node(mv, "FireRadial71", "res://presentation/ui71/fire_radial.gd")
	var fv_r: Array = _node(mv, "FiresView71", "res://presentation/view/fires71_view.gd")
	var kz = kz_r[0]
	var fr = fr_r[0]
	var fv = fv_r[0]
	if bool(fv_r[1]):
		fv.self_refresh = true
	pt._log("fires71_nodes", kz != null and fr != null and fv != null,
		"self-attached: kz=%s radial=%s view=%s (false = g71_attach line in)" % [str(kz_r[1]), str(fr_r[1]), str(fv_r[1])])
	# ---- a battery inside the base behind face 0 (the strips are ~40 tiles from the base centre, a howitzer reaches 20:
	# probe .plan/fires71/probe_flow.gd), the lane just outside the face 0 strip, 18 tiles long (max_len 24)
	var c := KillZone71.base_centre(w)
	var st0: Dictionary = KillZone71.fpf_strip(w, 0)
	var la := Vector2(float(st0.a[0]), float(st0.a[1]))
	var lb := Vector2(float(st0.b[0]), float(st0.b[1]))
	var mid0 := la.lerp(lb, 0.5)
	var dir0 := (lb - la).normalized()
	var bat := c + (mid0 - c).normalized() * 28.0
	var guns := []
	for i in 4:
		guns.append(w.spawn_unit("a_sp_howitzer", f, bat + dir0 * (float(i) * 1.5 - 2.0)))
	guns.append(w.spawn_unit("a_g71_mlrs", f, bat - (mid0 - c).normalized() * 2.0))
	guns.append(w.spawn_unit("a_mortar", f, bat + dir0 * 4.0))
	await pt._wait(0.5)
	mv.join_sim()
	var lane_a := mid0 - dir0 * 9.0 + KillZone71.normal(0) * 4.0
	var lane_b := mid0 + dir0 * 9.0 + KillZone71.normal(0) * 4.0
	mv.center_camera_on((lane_a + lane_b) * 0.5 - KillZone71.normal(0) * 6.0)
	mv.camera.set_zoom_level(0.9)
	await pt._wait(0.5)
	# ---- the radial (hold the key): open at the lane start, screenshot, pick HE (1 action)
	fr.open_at(lane_a)
	await pt._wait(0.4)
	await pt._shot("fires71_radial")
	var c0: int = fr.clicks
	var he := 0
	for i in fr.SLOTS.size():
		if String(fr.SLOTS[i][0]) == "he":
			he = i
	pt._log("fires71_radial_pick_he", fr.pick(he) == "he", "armed=%s" % fr.armed)
	mv.join_sim()
	var res: Dictionary = fr.finish(lane_a, lane_b, false, false)   # drag along the lane = line barrage (1 action)
	var lane_clicks: int = fr.clicks - c0
	pt._log("fires71_line_barrage_issued", bool(res.get("ok", false)), "res=%s" % str(res))
	await pt._wait(1.5)
	mv.join_sim()
	var st: Dictionary = w.sys_state.get("fires71", {})
	var lines := 0
	for k in st.get("missions", {}):
		if String(st.missions[k].shape) == "line" and String(st.missions[k].kind) == "he":
			lines += 1
	pt._log("fires71_line_mission_live", lines >= 1, "line missions=%d" % lines)
	pt._log("fires71_clicks_lane_barrage", lane_clicks <= 3, "after=%d (before ~13, fact fires71.survey)" % lane_clicks)
	await pt._wait(2.0)
	await pt._shot("fires71_line_barrage")
	# ---- smoke box (Shift + drag): 2 actions. The first battery is busy with the barrage: a second one fires the smoke
	for i in 2:
		guns.append(w.spawn_unit("a_sp_howitzer", f, bat - dir0 * (5.0 + float(i) * 1.5)))
	await pt._wait(0.3)
	mv.join_sim()
	c0 = fr.clicks
	var sm := 0
	for i in fr.SLOTS.size():
		if String(fr.SLOTS[i][0]) == "smoke":
			sm = i
	fr.pick(sm)
	mv.join_sim()
	res = fr.finish(mid0 + KillZone71.normal(0) * 2.0 - dir0 * 4.0, mid0 + KillZone71.normal(0) * 7.0 + dir0 * 4.0, true, false)
	pt._log("fires71_smoke_box_issued", bool(res.get("ok", false)), "res=%s clicks=%d (before: impossible)" % [str(res), fr.clicks - c0])
	await pt._wait(1.0)
	mv.join_sim()
	var smokes := 0
	for k in w.sys_state.get("fires71", {}).get("missions", {}):
		var ms: Dictionary = w.sys_state.fires71.missions[k]
		if String(ms.shape) == "box" and String(ms.kind) == "smoke":
			smokes += 1
	pt._log("fires71_smoke_mission_live", smokes >= 1, "smoke box missions=%d" % smokes)
	await pt._wait(1.5)
	await pt._shot("fires71_smoke_box")
	# ---- FPF on face 0 (radial FPF + click near the face)
	var fp := 0
	for i in fr.SLOTS.size():
		if String(fr.SLOTS[i][0]) == "fpf":
			fp = i
	fr.pick(fp)
	mv.join_sim()
	res = fr.finish(la.lerp(lb, 0.5), la.lerp(lb, 0.5), false, false)
	pt._log("fires71_fpf_issued", bool(res.get("ok", false)), "res=%s" % str(res))
	await pt._wait(1.5)
	mv.join_sim()
	var fs: Dictionary = (w.sys_state.get("fires71", {}).get("fpf", {}) as Dictionary)
	var firing: bool = fs.has("0") and w.tick < int(fs["0"].until)
	pt._log("fires71_fpf_firing", firing, "fpf=%s tick=%d" % [str(fs.get("0", {})), w.tick])
	mv.center_camera_on(la.lerp(lb, 0.5))
	# FIRES71-9: shoot as the first FPF rounds land (impact fx in frame), not before they arrive
	var fpf_n := int(fs.get("0", {}).get("n", -1))
	var fpf_land: bool = await pt._wait_until(func(): return (pt._w().sys_state.get("fires71", {}).get("rounds", []) as Array).any(func(r): return int(r.n) == fpf_n and int(r.t) <= 3), 15.0)
	await pt._wait(0.5)
	await pt._shot("fires71_fpf_strip")
	pt._log("fires71_fpf_landing_shot", true, "rounds about to land seen=%s (info)" % str(fpf_land))
	# ---- a sector for one gun: select (1) + radial Sectors (1) + drag (1) = 3
	mv.select_ids([guns[5]])
	var sel_clicks := 1
	var sc := 0
	for i in fr.SLOTS.size():
		if String(fr.SLOTS[i][0]) == "sectors":
			sc = i
	c0 = fr.clicks
	var k0: int = kz.clicks
	fr.pick(sc)
	pt._log("fires71_sectors_tool_opens", bool(kz.active), "")
	mv.join_sim()
	var ap := Vector2(w.entities[int(guns[5])].pos)
	res = kz.finish_drag(ap, ap + KillZone71.normal(0) * 14.0, false)
	var sec_clicks: int = sel_clicks + (fr.clicks - c0) + (kz.clicks - k0)
	pt._log("fires71_sector_painted", bool(res.get("ok", false)), "res=%s" % str(res))
	await pt._wait(0.6)
	mv.join_sim()
	pt._log("fires71_sector_in_sim", not KillZone71.sector_of(w, int(guns[5])).is_empty(), str(KillZone71.sector_of(w, int(guns[5]))))
	pt._log("fires71_clicks_one_sector", sec_clicks <= 3, "after=%d (before: impossible)" % sec_clicks)
	kz.stop()
	mv.center_camera_on(ap + KillZone71.normal(0) * 6.0)
	await pt._wait(0.6)
	await pt._shot("fires71_sector")
	# ---- CONDUCTOR orbit from the radial (a gunship + 4 wingmen spawned for the flow until the LP-base file is approved)
	if Conductor71.gunship(w, f) < 0:
		w.spawn_unit("a_g71_conductor", f, c + Vector2(0, -3))
		for i in 4:
			w.spawn_unit("a_g71_wingman", f, c + Vector2(1.0 + i, -1.5))
		await pt._wait(0.5)
		mv.join_sim()
	var gs := 0
	for i in fr.SLOTS.size():
		if String(fr.SLOTS[i][0]) == "gunship":
			gs = i
	fr.pick(gs)
	var oc := c + KillZone71.normal(0) * 12.0
	res = fr.finish(oc, oc + Vector2(8, 0), false, false)
	pt._log("fires71_conductor_orbit_issued", bool(res.get("ok", false)), "res=%s" % str(res))
	var orb: bool = await pt._wait_until(func(): return bool(Conductor71.record(pt._w(), f).get("on", false)), 20.0)
	pt._log("fires71_conductor_on_orbit", orb, str(Conductor71.snap71(w, f)))
	await pt._wait(6.0)
	mv.center_camera_on(oc)
	await pt._wait(0.5)
	await pt._shot("fires71_conductor_orbit")
	pt._log("fires71_view_drawn", fv.visible, "g71 keys=%s" % str((mv.snap.get("g71", {}) as Dictionary).keys()))
	# ---- FIRES71-7 shots: a fresh barrage late in its run, counter-battery, incendiary belts burning, an FO call, and the
	# world markers under the Last Protocol night tint (fires71_view / killzone_paint z 5, over FacAtmo7's z 3 tint)
	mv.join_sim()
	var lb_a := mid0 - dir0 * 7.0 + KillZone71.normal(0) * 3.0
	var lb_b := mid0 + dir0 * 7.0 + KillZone71.normal(0) * 3.0
	var r2n := int(w.sys_state.get("fires71", {}).get("next", 1))   # FIRES71-9: missions of this barrage get n >= r2n
	var r2: Dictionary = mv.issue({"type": "fire_mission", "kind": "he", "shape": "line", "a": [lb_a.x, lb_a.y], "b": [lb_b.x, lb_b.y]})
	pt._log("fires71_late_barrage_issued", bool(r2.get("ok", false)), "res=%s" % str(r2))
	mv.center_camera_on((lb_a + lb_b) * 0.5 - KillZone71.normal(0) * 4.0)
	# FIRES71-9: wait for the barrage's rounds to reach the ground (was a fixed 5 s: the shot caught 0 impacts)
	await pt._wait_until(func(): return (pt._w().sys_state.get("fires71", {}).get("rounds", []) as Array).any(func(r): return int(r.n) >= r2n and int(r.t) <= 3), 15.0)
	await pt._wait(0.5)
	mv.join_sim()
	var landed := 0
	for ev in pt._w().events:
		if String(ev.get("type", "")) == "Fires71Impact" or String(ev.get("type", "")) == "RoundLanded":
			landed += 1
	await pt._shot("fires71_barrage_late")
	pt._log("fires71_barrage_late_shot", true, "impact events this tick=%d" % landed)
	# counter-battery: an enemy mortar 30 tiles out from our radar fires; the radar tracks it, our guns answer
	var mf := -1
	for fid2 in w.factions:
		if w.is_enemy(f, int(fid2)):
			mf = int(fid2)
			break
	var radar := -1
	for b in w.entities.values():
		if b.kind == "building" and int(b.owner) == f and Content.building(String(b.def)).has("radar"):
			radar = int(b.id)
			break
	var cb_ok := false
	if radar >= 0 and mf >= 0:
		var rp: Vector2 = w.entities[radar].pos
		var away := (rp - c).normalized() if rp.distance_to(c) > 1.0 else Vector2(1, 0)
		var src := w.spawn_unit("a_mortar", mf, rp + away * 30.0)
		guns.append(w.spawn_unit("a_sp_howitzer", f, rp + away * 12.0))
		w.cache.erase("f71_cb")
		await pt._wait(0.3)
		mv.join_sim()
		cb_ok = await pt._wait_until(func():
			var ww: SimWorld = pt._w()
			if ww.entities.has(src):
				ww.entities[src].last_fired_tick = ww.tick
			for k in ww.sys_state.get("fires71", {}).get("missions", {}):
				if int(ww.sys_state.fires71.missions[k].get("cb", -1)) == src:
					return true
			return false, 20.0)
		mv.center_camera_on(rp + away * 22.0)
		await pt._wait(2.5)
		await pt._shot("fires71_counter_battery")
	pt._log("fires71_counter_battery_answer", cb_ok, "radar=%d enemy fid=%d" % [radar, mf])
	# incendiary belts: lay two in front of face 0, ignite all
	mv.join_sim()
	var b1a := mid0 - dir0 * 8.0 + KillZone71.normal(0) * 1.0
	var r3: Dictionary = mv.issue({"type": "belt_lay", "a": [b1a.x, b1a.y], "b": [(b1a + dir0 * 8.0).x, (b1a + dir0 * 8.0).y]})
	var b2a := mid0 + dir0 * 1.0 + KillZone71.normal(0) * 1.0
	var r4: Dictionary = mv.issue({"type": "belt_lay", "a": [b2a.x, b2a.y], "b": [(b2a + dir0 * 8.0).x, (b2a + dir0 * 8.0).y]})
	pt._log("fires71_belts_laid", bool(r3.get("ok", false)) and bool(r4.get("ok", false)), "res=%s / %s" % [str(r3), str(r4)])
	await pt._wait(0.5)
	mv.join_sim()
	var r5: Dictionary = mv.issue({"type": "belt_ignite", "all": true})
	pt._log("fires71_belts_ignite_issued", bool(r5.get("ok", false)), "res=%s" % str(r5))
	var burn: bool = await pt._wait_until(func():
		for k in pt._w().sys_state.get("fires71", {}).get("belts", {}):
			if String(pt._w().sys_state.fires71.belts[k].s) == "burning":
				return true
		return false, 10.0)
	pt._log("fires71_belts_burning", burn, "")
	mv.center_camera_on(mid0 - KillZone71.normal(0) * 3.0)
	await pt._wait(2.0)
	await pt._shot("fires71_belts_burning")
	# an FO call: the forward observer team calls the Conductor onto a point it can see
	mv.join_sim()
	var fo := -1
	var ids2 := w.entities.keys()
	ids2.sort()
	for id in ids2:
		var e2: Dictionary = w.entities[id]
		if int(e2.owner) == f and e2.kind == "unit" and Content.unit(String(e2.def)).has("fo71"):
			fo = int(id)
			break
	if fo < 0:
		fo = w.spawn_unit("a_g71_fo_team", f, c + KillZone71.normal(0) * 20.0)
		await pt._wait(0.3)
		mv.join_sim()
	var fop: Vector2 = Vector2(w.entities[fo].pos)
	var tgt := fop + (mid0 - fop).normalized() * 6.0
	mv.select_ids([fo])
	var r6: Dictionary = mv.issue({"type": "fo_call", "unit_id": fo, "what": "conductor", "cell": [tgt.x, tgt.y]})
	pt._log("fires71_fo_call_conductor", bool(r6.get("ok", false)), "fo=%d at %s -> %s res=%s" % [fo, str(fop.round()), str(tgt.round()), str(r6)])
	mv.center_camera_on((fop + tgt) * 0.5)
	await pt._wait(4.0)
	await pt._shot("fires71_fo_call")
	# the same markers at night (LP default is dusk)
	var atmo = mv.get("fac_atmo7")   # FIRES71-9: the node is unnamed (match_view.gd add_child), find_child missed it
	if atmo != null and atmo.has_method("set_time_of_day"):
		atmo.set_time_of_day("night")
	mv.join_sim()
	var r7: Dictionary = mv.issue({"type": "fire_mission", "kind": "smoke", "shape": "box", "a": [(mid0 - dir0 * 3.0).x, (mid0 - dir0 * 3.0).y], "b": [(mid0 + dir0 * 3.0 + KillZone71.normal(0) * 5.0).x, (mid0 + dir0 * 3.0 + KillZone71.normal(0) * 5.0).y]})
	mv.center_camera_on(mid0 - KillZone71.normal(0) * 2.0)
	await pt._wait(4.0)
	var na: float = float(atmo.night_amount()) if atmo != null and atmo.has_method("night_amount") else -1.0
	await pt._shot("fires71_markers_night")
	pt._log("fires71_night_tint_on", na > 0.6, "FacAtmo7=%s night=%.2f smoke res=%s" % [str(atmo != null), na, str(r7)])
	if atmo != null and atmo.has_method("set_time_of_day"):
		atmo.set_time_of_day("")
