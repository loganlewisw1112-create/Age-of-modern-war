extends RefCounted
## G7 playtest flow atmo7 (ATMO7, 13.9c-7): the counter-nanite facility's atmosphere layer in a real windowed match.
## Raises a facility, then shots at zoom 1 / 1.75 / 2.5 of: signage + ground wear (gate approach, APC wash wet tracks,
## garage aprons, lanes), windsock / flags at the helipad, the alarm (lockdown: beacons, wall lamps, searchlights, blast
## doors, helipad shields, decon mist flood) by day and night, the night look (floodlights, door lamps, garage spill,
## pad edge lights), dusk, damage (a burning tower, the core-driven zone damage), a destroyed tower's rubble and the
## ruin after the facility is lost. Logs the layer's draw counters per shot and a frame-time A/B (layer on / off).
## Uses match_view.fac_atmo7 when ORCH has wired it, else adds the layer itself (auto mode).

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Atmo = preload("res://presentation/view/fac_atmo7.gd")
const ZL := {1: 1.0, 2: 1.75, 3: 2.5}
var _hidden: Array = []


func _clean_view(mv, on: bool) -> void:
	if on:
		_hidden.clear()
		var hud = mv.get_parent().get("hud") if mv.get_parent() != null else null
		var cands: Array = []
		if hud is Node:
			cands.append(hud)
			cands.append_array((hud as Node).get_children())
		for n in cands:
			if (n is CanvasItem or n is CanvasLayer) and bool(n.visible):
				n.visible = false
				_hidden.append(n)
		var fl = mv.get("fog_layer")
		if fl is CanvasItem and (fl as CanvasItem).visible:
			(fl as CanvasItem).visible = false
			_hidden.append(fl)
	else:
		for n in _hidden:
			n.visible = true
		_hidden.clear()


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _has_fac(pt) -> bool:
	pt._mv().join_sim()
	return not CnFacility.render_entries(pt._w()).is_empty()


func _layer(mv):
	var L = mv.get("fac_atmo7")
	if L != null:
		return L
	L = Atmo.new()
	L.name = "FacAtmo7"
	L.auto = true
	L.z_index = 0
	mv.add_child(L)
	var bp = mv.get("baseprops_layer")
	if bp is Node and (bp as Node).get_parent() == mv:
		mv.move_child(L, (bp as Node).get_index() + 1)
	L.setup(mv)
	L.set_process(true)
	return L


func _shots(pt, mv, L, name: String, at: Vector2, zooms: Array) -> void:
	for z in zooms:
		_zoom(mv, float(ZL[z]))
		mv.center_camera_on(at)
		await pt._wait(0.5)
		await pt._shot("atmo7_%s_z%d" % [name, z])
		print("ATMO7_COUNTS %s_z%d %s" % [name, z, JSON.stringify(L.counts)])


## Mean / p90 frame time (ms) over n frames.
func _frames(mv, n: int) -> Array:
	var ts: Array = []
	var vp: RID = mv.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var gpu := 0.0
	var cpu := 0.0
	var last := Time.get_ticks_usec()
	for i in n:
		await mv.get_tree().process_frame
		var now := Time.get_ticks_usec()
		ts.append(float(now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	ts.sort()
	var s := 0.0
	for v in ts:
		s += v
	return [s / float(n), ts[int(float(n) * 0.9)], gpu / float(n), cpu / float(n)]



## LIGHT7-2 bisect: at night with a garage door open, the same two views with each drawing layer hidden in turn.
func _quick(pt, mv, L, F: Dictionary, centre: Vector2, zc: Callable, fid: int) -> void:
	L.set_time_of_day("night")
	await pt._wait(2.6)
	var life = mv.get("fac_life7")
	var ng: int = (F.get("garage_rects", []) as Array).size()
	var force := func() -> void:   # hold every garage door fully open for the shot (LIFE7 eases them toward a target each frame)
		if life != null:
			for Lf in life.life:
				if int(Lf.id) == fid:
					for k in Lf.doors:
						Lf.doors[k] = 1.0
	force.call()
	await pt._wait(0.1)
	pt._log("light7_quick_door_open", life != null and float(life.door_open(fid, "g0")) > 0.5, "garage doors forced open at night (%d garages)" % ng)
	var g0: Array = F.get("garage_rects", [])
	var views := {"plan": zc.call("planning") + Vector2(0.5, 0.5)}
	if g0.size() > 0:
		var gr: Array = g0[1 if g0.size() > 1 else 0]
		views["gar"] = Vector2(float(gr[0]) + float(gr[2]) + 0.8, float(gr[1]) + 1.5)
	for vn in views:
		_zoom(mv, float(ZL[3]))
		mv.center_camera_on(views[vn])
		await pt._wait(0.5)
		force.call()
		await pt._wait(0.05)
		await pt._shot("atmo7_q_%s_all" % vn)
		for what in ["atmo", "life", "glow", "over"]:
			var node = null
			match what:
				"atmo":
					node = L
				"life":
					node = life
				"glow":
					node = L.glow
				"over":
					node = L.over
			if node == null:
				continue
			node.visible = false
			force.call()
			await pt._wait(0.05)
			await pt._shot("atmo7_q_%s_no%s" % [vn, what])
			node.visible = true


## LIGHT7-3 (owner 13.9c-24a): the lit window panes of the multi-storey buildings at night, zoom 2.5 / 1.75 on each.
func _wins(pt, mv, L, zc: Callable) -> void:
	var g: Dictionary = L.geo[0]
	var by := {}
	var st := [0, 0, 0, 0]
	for P in g.get("win", []):
		by[String(P.zn)] = int(by.get(String(P.zn), 0)) + 1
		st[int(P.kind)] += 1
	var need := ["planning", "workshop", "barracks", "armory"]
	var miss := []
	for zn in need:
		if (g.zones as Dictionary).has(zn) and zn != "armory" and int(by.get(zn, 0)) < 6:
			miss.append(zn)
	pt._log("light7_windows_plan", miss.is_empty() and st[1] + st[2] + st[3] > 20 and st[0] > 4 and st[1] > 4 and st[3] >= 1,
		"panes per building %s; dark %d dim %d lit %d screen %d; missing %s" % [str(by), st[0], st[1], st[2], st[3], str(miss)])
	for zn in need:
		if (g.zones as Dictionary).has(zn):
			await _shots(pt, mv, L, "win_night_%s" % zn, zc.call(zn) + Vector2(0.6, 0.6), [3, 2])
	pt._log("light7_windows_drawn", int(L.counts.get("panes_lit", 0)) >= 10, "panes drawn %d, lit %d (last view)" % [int(L.counts.get("panes", 0)), int(L.counts.get("panes_lit", 0))])


## LIGHT7-4 (pane overdraw): a hovering attack helicopter right against the command centre's visible faces at night: the lit window panes
## must never be drawn over it (the panes behind its sprite are cut away: counts.panes_cut > 0, its rect is in the layer's cut list).
func _overdraw(pt, mv, L, zc: Callable) -> void:
	var w: SimWorld = pt._w()
	var h = H.new()
	var g: Dictionary = L.geo[0]
	var zr: Rect2 = g.zones.planning
	var me := int(mv.player_fid)
	var ids: Array = []
	for sp in [Vector2(zr.end.x + 0.25, zr.position.y + zr.size.y * 0.35), Vector2(zr.position.x + zr.size.x * 0.55, zr.end.y + 0.25)]:
		var u: Dictionary = h._unit(w, "a_attack_heli", me, sp)
		if u.is_empty():
			continue
		u.max_hp = 1.0e6
		u.hp = 1.0e6
		u.order = {"type": "hold"}
		ids.append(int(u.id))
	await pt._wait(1.2)
	await _shots(pt, mv, L, "overdraw_night_planning", zc.call("planning") + Vector2(0.6, 0.6), [3, 2])
	var nc := 0
	for fid in L._cuts:
		nc += (L._cuts[fid] as Array).size()
	pt._log("light7_pane_overdraw", not ids.is_empty() and nc >= 1 and int(L.counts.get("panes_cut", 0)) >= 1,
		"helicopters %d, unit rects in front of the panes %d, panes cut by them %d (last view)" % [ids.size(), nc, int(L.counts.get("panes_cut", 0))])
	mv.join_sim()
	for uid in ids:
		w.entities.erase(int(uid))
	w.cache.clear()


## LIGHT7-2 (13.9c-24b): the perimeter at night with own riflemen outside (gate approach + east wall), zoom 1 / 1.75.
func _perim(pt, mv, L, h, w: SimWorld, me: int) -> void:
	# LIGHT7-2 (13.9c-24b "outer facing floodlights much brighter"): own riflemen standing outside the gate approach and the
	# east wall at night: the perimeter floods (wall / gate / tower, hot core + wide wash, ground only) must show them plainly
	mv.join_sim()
	var gg: Dictionary = L.geo[0]
	var gc: Vector2 = (gg.zones.gate_outer as Rect2).get_center()
	var gqq: Vector2 = gc - (gg.O as Vector2)
	var dnn := [gqq.y, float(gg.cs) - gqq.y, gqq.x, float(gg.cs) - gqq.x]
	var gdir: Vector2 = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)][dnn.find(dnn.min())]
	var gperp := Vector2(-gdir.y, gdir.x)
	var outside_ids: Array = []
	var spots: Array = []
	for i in 4:
		spots.append(gc + gdir * (3.5 + 1.2 * float(i % 2)) + gperp * (-3.0 + 2.0 * float(i)))
	for i in 3:
		spots.append((gg.O as Vector2) + Vector2(float(gg.cs) + 2.2 + 1.0 * float(i % 2), float(gg.cs) * 0.5 + 2.0 + 2.5 * float(i)))
	for sp in spots:
		var ou: Dictionary = h._unit(w, "rifleman", me, sp)
		ou.max_hp = 1.0e6
		ou.hp = 1.0e6
		ou.order = {"type": "hold"}
		outside_ids.append(int(ou.id))
	await pt._wait(0.6)
	await _shots(pt, mv, L, "light_night_out_gate", gc + gdir * 3.5, [1, 2])
	await _shots(pt, mv, L, "light_night_out_e", (gg.O as Vector2) + Vector2(float(gg.cs) + 2.0, float(gg.cs) * 0.5 + 4.5), [1, 2])
	mv.join_sim()
	for uid in outside_ids:
		w.entities.erase(int(uid))
	w.cache.clear()


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var c: Vector2i = h._open(w, 18)
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(16, 16)
	var fid := w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): return _has_fac(pt), 8.0)
	pt._log("atmo7_facility_raised", raised, "facility %d" % fid)
	if not raised:
		return
	var L = _layer(mv)
	pt._log("atmo7_layer", L != null and L.get_parent() != null, "wired by match_view" if mv.get("fac_atmo7") != null else "added by the flow (auto)")
	mv.join_sim()
	var F: Dictionary = CnFacility.render_entries(w)[0]
	var cr: Array = F.compound
	var centre := Vector2(float(cr[0]) + float(cr[2]) * 0.5, float(cr[1]) + float(cr[3]) * 0.5)
	var zs: Dictionary = F.zones
	var zc := func(zn: String) -> Vector2:
		var r: Array = zs.get(zn, [centre.x, centre.y, 0, 0])
		return Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)
	_clean_view(mv, true)
	L.set_time_of_day("day")
	await pt._wait(1.0)
	pt._log("atmo7_geometry", L.geo.size() == 1 and (L.geo[0].towers as Array).size() >= 4, "geo %d, towers %d" % [L.geo.size(), (L.geo[0].towers as Array).size() if L.geo.size() > 0 else 0])
	# LIGHT7_QUICK=1: only the layer bisect at night (which layer draws what): all / no atmo7 / no life7 / no glow / no over
	if OS.get_environment("LIGHT7_QUICK") == "off":   # LIGHT7-7: run with ATMO7_OFF=1 (the lighting layer draws nothing): is a see-through box at the command centre this layer's?
		print("LIGHT7_OFF layer off %s geo %d" % [str(L.off), L.geo.size()])
		await _shots(pt, mv, L, "off_planning", zc.call("planning") + Vector2(1.0, 1.0), [2, 3])
		await _shots(pt, mv, L, "off_workshop", zc.call("workshop") + Vector2(1.0, 1.0), [2])
		_clean_view(mv, false)
		return
	if OS.get_environment("LIGHT7_QUICK") == "perim":
		L.set_time_of_day("night")
		await pt._wait(2.6)
		await _perim(pt, mv, L, h, w, me)
		_clean_view(mv, false)
		return
	if OS.get_environment("LIGHT7_QUICK") == "yard":   # LIGHT7-4 (13.9c-24d): the compound interior at night, zoom 1 / 1.75
		L.set_time_of_day("night")
		await pt._wait(2.6)
		await _shots(pt, mv, L, "yard_night", centre, [1, 2])
		await _shots(pt, mv, L, "yard_night_wash", zc.call("apc_wash"), [2])
		await _shots(pt, mv, L, "yard_night_staging", zc.call("staging"), [2])
		var gy: Dictionary = L.geo[0]
		var kc := {}
		var kh := {}   # LIGHT7-7: fixtures a building stands in front of (hid), per kind
		for fx in gy.fix:
			kc[String(fx.k)] = int(kc.get(String(fx.k), 0)) + 1
			if fx.hid:
				kh[String(fx.k)] = int(kh.get(String(fx.k), 0)) + 1
		print("LIGHT7_YARD fixtures %s total %d walk_drop %d mast_drop %d hidden %s" % [str(kc), (gy.fix as Array).size(), int(gy.get("walk_drop", 0)), int(gy.get("mast_drop", 0)), str(kh)])
		var wl: PackedFloat32Array = gy.get("work_lv", PackedFloat32Array())
		var wmin := 9.0
		var wdark := 0
		for v in wl:
			wmin = minf(wmin, v)
			wdark += 1 if v < L.IL_MIN else 0
		print("LIGHT7_YARD work cells %d min lift %.3f below %.2f: %d" % [wl.size(), wmin, L.IL_MIN, wdark])
		var dk := []
		for i in wl.size():
			if wl[i] < L.IL_MIN:
				dk.append("%s:%.2f" % [str(gy.work[i] - gy.O), wl[i]])
		print("LIGHT7_YARD dark %s" % " ".join(dk))
		var ms := []
		for fx in gy.fix:
			if String(fx.k) in ["mast", "wallf"]:
				ms.append("%s %s zv %.0f hid %s" % [String(fx.k), str(fx.at - gy.O), float(fx.get("zv", 0.0)), str(fx.hid)])
		print("LIGHT7_YARD masts %s" % str(ms))
		for mfid in L._mask:   # LIGHT7-6: the baked tint-lift mask (r interior, g outward) as rendered, and where it sits
			var mk: Dictionary = L._mask[mfid]
			var mim: Image = (mk.vp as SubViewport).get_texture().get_image()
			if mim != null:
				mim.save_png(pt.shot_dir.path_join("lift_mask_%d.png" % int(mfid)) if "shot_dir" in pt else "user://lift_mask.png")
			print("LIGHT7_MASK fid %d rect %s size %s builds %d" % [int(mfid), str(mk.rect), str((mk.vp as SubViewport).size), L._mask_builds])
		if OS.get_environment("LIGHT7_OCC") == "1":   # LIGHT7-5 diagnosis: every occluder silhouette (cyan) and pool outline (yellow) over the night view
			var ov := Node2D.new()
			ov.z_index = 200
			ov.draw.connect(func() -> void:
				for s in gy.get("lsil", gy.sil):   # LIGHT7-6: the light silhouettes (drawn blocks)
					var p: PackedVector2Array = (s[0] as PackedVector2Array).duplicate()
					p.append(p[0])
					ov.draw_polyline(p, Color(0, 1, 1), 1.5)
				for fx in gy.fix:
					if fx.has("P") and not (fx.P as Dictionary).is_empty():
						for poly in fx.P.polys:
							var q: PackedVector2Array = (poly as PackedVector2Array).duplicate()
							q.append(q[0])
							ov.draw_polyline(q, Color(1, 1, 0, 0.7), 1.0))
			mv.add_child(ov)
			print("LIGHT7_OCC O %s zones %s garages %s occ %s" % [str(gy.O), str(gy.zones), str(gy.garages), str(gy.occ)])
			await _shots(pt, mv, L, "yard_occ", centre, [1])
			await _shots(pt, mv, L, "yard_occ_sw", zc.call("range"), [2])
			await _shots(pt, mv, L, "yard_occ_wash", zc.call("apc_wash"), [2])
			ov.queue_free()
		_clean_view(mv, false)
		return
	if OS.get_environment("LIGHT7_QUICK") == "cost":   # LIGHT7-5: the layer's frame cost at the compound at night (calm, then lockdown), 3 on / off pairs each
		L.set_time_of_day("night")
		await pt._wait(2.6)
		_zoom(mv, 1.0)
		mv.center_camera_on(centre)
		await pt._wait(0.5)
		for phase in ["calm", "lock"]:
			if phase == "lock":
				mv.join_sim()
				CnFacility._lockdown(w, CnFacility.fac(w, fid), true)
				await pt._wait(1.0)
			L.prof.clear()
			var ons := []
			var offs := []
			for rep in 3:
				var a: Array = await _frames(mv, 120)
				L.visible = false
				L.off = true
				var b: Array = await _frames(mv, 120)
				L.off = false
				L.visible = true
				await pt._wait(0.2)
				ons.append(a[0])
				offs.append(b[0])
				print("LIGHT7_COST %s rep %d on mean %.2f p90 %.2f gpu %.2f rcpu %.2f | off mean %.2f p90 %.2f gpu %.2f rcpu %.2f" % [phase, rep, a[0], a[1], a[2], a[3], b[0], b[1], b[2], b[3]])
			ons.sort()
			offs.sort()
			print("LIGHT7_COST %s median on %.2f off %.2f delta %.2f ms lights %d prof %s" % [phase, ons[1], offs[1], ons[1] - offs[1], int(L.counts.get("lights", 0)), str(L.prof)])
		_clean_view(mv, false)
		return
	if OS.get_environment("LIGHT7_QUICK") == "mast":   # LIGHT7-5 (CR 5927): the comms-mast blink points on the command centre roof, zoom 2.5
		L.set_time_of_day("night")
		await pt._wait(2.6)
		var life7 = mv.get("fac_life7")
		var pc: Vector2 = zc.call("planning")
		await _shots(pt, mv, L, "mast_night_planning", pc - Vector2(5.5, 5.5), [3])   # the roof (~200 px up) in view
		if life7 != null:
			var mo := Node2D.new()
			mo.z_index = 200
			mo.draw.connect(func() -> void:
				for tip in life7.MAST_TIPS:
					mo.draw_arc(L._iso(pc) + tip, 3.0, 0.0, TAU, 12, Color(0, 1, 1), 1.0))
			mv.add_child(mo)
			print("LIGHT7_MAST tips %s at %s" % [str(life7.MAST_TIPS), str(L._iso(pc))])
			await _shots(pt, mv, L, "mast_marks_planning", pc - Vector2(5.5, 5.5), [3])
			mo.queue_free()
		_clean_view(mv, false)
		return
	if OS.get_environment("LIGHT7_QUICK") == "pane":   # LIGHT7-4: units against the facade
		L.set_time_of_day("night")
		await pt._wait(2.6)
		await _overdraw(pt, mv, L, zc)
		_clean_view(mv, false)
		return
	if OS.get_environment("LIGHT7_QUICK") == "bay":   # LIGHT7-4: the Suit Foundry's bay work lights only
		L.set_time_of_day("night")
		await pt._wait(2.6)
		await _shots(pt, mv, L, "bay_night_armory", zc.call("armory") + Vector2(0.6, 0.6), [3, 2])
		if L.geo[0].has("bay"):
			var B: Dictionary = L.geo[0].bay
			print("LIGHT7_BAY open %s gl %s hid %s lamps0 %s pools %d" % [str(B.open), str(B.gl), str(B.gl_hid), str(B.lamps[0]), (B.pools as Array).size()])
		_clean_view(mv, false)
		return
	if OS.get_environment("LIGHT7_QUICK") == "win":
		if (L.geo[0].zones as Dictionary).has("armory"):   # the Suit Foundry by day (plaque off the bay opening, atmo7.foundry_plaque_off_bay)
			await _shots(pt, mv, L, "win_day_armory", zc.call("armory") + Vector2(0.6, 0.6), [3, 2])
		L.set_time_of_day("night")
		await pt._wait(2.6)
		await _wins(pt, mv, L, zc)
		_clean_view(mv, false)
		return
	if OS.get_environment("LIGHT7_QUICK") != "":
		await _quick(pt, mv, L, F, centre, zc, fid)
		_clean_view(mv, false)
		return
	# 1. day: compound, signage + wear
	await _shots(pt, mv, L, "compound_day", centre, [1])
	# LIGHT7 (13.9c-24 / 24a): the fixtures by day (housings, poles, brackets: nothing floats, nothing lit)
	await _shots(pt, mv, L, "light_day_yard", centre + Vector2(1.0, 1.0), [2, 3])
	await _shots(pt, mv, L, "light_day_wall_e", L.geo[0].O + Vector2(float(L.geo[0].cs) - 1.0, float(L.geo[0].cs) * 0.5 + 3.0), [3])
	var go: Vector2 = zc.call("gate_outer")
	await _shots(pt, mv, L, "gate_approach", go + Vector2(0, 1.5), [1, 2, 3])
	pt._log("atmo7_signs", int(L.counts.get("signs", 0)) >= 8, "signs %d stencils %d arrows %d" % [int(L.counts.get("signs", 0)), int(L.counts.get("stencils", 0)), int(L.counts.get("arrows", 0))])
	await _shots(pt, mv, L, "wash_tracks", zc.call("apc_wash") + Vector2(0, -1.5), [1, 2, 3])
	pt._log("atmo7_wear", int(L.counts.get("tracks", 0)) >= 4 and int(L.counts.get("oil", 0)) >= 8 and int(L.counts.get("stripes", 0)) >= 4,
		"tracks %d wet %d oil %d stripes %d" % [int(L.counts.get("tracks", 0)), int(L.counts.get("wet", 0)), int(L.counts.get("oil", 0)), int(L.counts.get("stripes", 0))])
	var g0: Array = F.get("garage_rects", [])
	if g0.size() > 0:
		var gr: Array = g0[1 if g0.size() > 1 else 0]
		await _shots(pt, mv, L, "garages", Vector2(float(gr[0]) + float(gr[2]) + 0.8, float(gr[1]) + 1.5), [1, 2, 3])
	await _shots(pt, mv, L, "planning", zc.call("planning") + Vector2(1.0, 1.0), [2, 3])
	# POLISH7-4 (owner 13.9c-21 / 13.9c-18): the marked fuel-bowser bay; the workshop + drone-bay storey and the barracks
	# with their own signs (no DRONE BAY plaque on the barracks, none hung by this layer on the stacked storey)
	var bayr := Rect2(Vector2(float(cr[0]), float(cr[1])) + L.Engineer7.bay_local().position, L.Engineer7.bay_local().size)
	await _shots(pt, mv, L, "fuel_bay", bayr.get_center() + Vector2(0.5, 0.5), [2, 3])
	var dbp := 0
	for p in L._plaques(L.geo[0]):
		if String(p[0]) == "board_drone_bay":
			dbp += 1
	pt._log("atmo7_bowser_bay", int(L.counts.get("bay", 0)) == 1 and dbp == 0, "bay markings %d, DRONE BAY plaques %d (want 1, 0)" % [int(L.counts.get("bay", 0)), dbp])
	await _shots(pt, mv, L, "workshop_barracks", zc.call("workshop") + Vector2(0.5, 2.5), [2])
	await _shots(pt, mv, L, "helipad_wind", zc.call("helipad") + Vector2(2.0, 2.0), [2, 3])
	pt._log("atmo7_smoke_flags", int(L.counts.get("puffs", 0)) >= 12 and int(L.counts.get("flags", 0)) >= 2, "puffs %d mist %d flags %d" % [int(L.counts.get("puffs", 0)), int(L.counts.get("mist", 0)), int(L.counts.get("flags", 0))])
	await _shots(pt, mv, L, "decon_mist", zc.call("decon_hall"), [2, 3])
	if L.geo.size() > 0:
		await _shots(pt, mv, L, "hq_flags", (L.geo[0].flags[0] as Vector2) + Vector2(0.5, 0.5), [2, 3])
	# 2. night (and dusk): lights
	L.set_time_of_day("night")
	await pt._wait(2.6)
	await _shots(pt, mv, L, "compound_night", centre, [1])
	# LIGHT7: the lighting plan at night: lane poles, door bulkheads, apron floods, wall-top floods, roof obstruction lamps
	var fix: Array = L.geo[0].get("fix", []) if L.geo.size() > 0 else []
	var kinds := {}
	for Fx in fix:
		kinds[String(Fx.k)] = int(kinds.get(String(Fx.k), 0)) + 1
	pt._log("light7_plan", int(kinds.get("pole", 0)) >= 4 and int(kinds.get("wall", 0)) >= 6 and int(kinds.get("door", 0)) >= 6 and int(kinds.get("obst", 0)) == 4,
		"fixtures %s" % str(kinds))
	await _perim(pt, mv, L, h, w, me)
	await _shots(pt, mv, L, "light_night_yard", centre + Vector2(1.0, 1.0), [1, 2, 3])
	await _shots(pt, mv, L, "light_night_pads", zc.call("pad") + Vector2(4.0, 1.0), [2, 3])
	await _shots(pt, mv, L, "light_night_wall_s", go + Vector2(-4.0, 1.0), [2, 3])
	await _shots(pt, mv, L, "light_night_planning", zc.call("planning") + Vector2(0.5, 0.5), [3])
	await _wins(pt, mv, L, zc)   # LIGHT7-3: lit window panes
	await _shots(pt, mv, L, "light_night_gate", go + Vector2(0, 2.5), [1, 2])
	# LIGHT7-2: the wall at WALL7-2's heights: the east wall's outer face (battlement floods + strobes), the north wall's inner
	# face (walkway lamps under the deck edge), the north-west corner (junction mast floodlight)
	var Og: Vector2 = L.geo[0].O
	var csg: float = L.geo[0].cs
	await _shots(pt, mv, L, "light_night_wall_e", Og + Vector2(csg - 1.0, csg * 0.5 + 3.0), [2, 3])
	await _shots(pt, mv, L, "light_night_wall_n", Og + Vector2(csg * 0.5, 3.0), [2, 3])
	await _shots(pt, mv, L, "light_night_corner_nw", Og + Vector2(1.5, 1.5), [3])
	pt._log("light7_night_lit", int(L.counts.get("lights", 0)) >= 60 and int(L.counts.get("lights", 0)) <= L.LIGHT_CAP and int(L.counts.get("fixtures", 0)) >= 40,
		"lights %d (cap %d) fixtures %d" % [int(L.counts.get("lights", 0)), L.LIGHT_CAP, int(L.counts.get("fixtures", 0))])
	pt._log("atmo7_night", L.night_amount() > 0.95 and int(L.counts.get("dark", 0)) == 1 and int(L.counts.get("lights", 0)) >= 40, "night %.2f lights %d" % [L.night_amount(), int(L.counts.get("lights", 0))])
	if g0.size() > 0:
		var gr2: Array = g0[1 if g0.size() > 1 else 0]
		await _shots(pt, mv, L, "garages_night", Vector2(float(gr2[0]) + float(gr2[2]) + 0.8, float(gr2[1]) + 1.5), [2, 3])
	await _shots(pt, mv, L, "pad_night", zc.call("pad"), [1, 2])
	await _shots(pt, mv, L, "gate_night", go + Vector2(0, 1.0), [2])
	L.set_time_of_day("dusk")
	await pt._wait(1.5)
	await _shots(pt, mv, L, "compound_dusk", centre, [1, 2, 3])
	# POLISH7-2 (owner 13.9c-17): a tank shooting from outside = under fire = amber beacons only (no lamps / searchlights
	# / shutters); the full lockdown look comes with the real breach below
	mv.join_sim()
	var gu: Dictionary = L.geo[0]
	var tu: Vector2 = gu.towers[0]
	for q in gu.towers:
		if (q as Vector2).x + (q as Vector2).y > tu.x + tu.y:
			tu = q
	var tk := w.spawn_unit("mbt", 1 if me == 0 else 0, tu + (tu - (gu.ctr as Vector2)).normalized().rotated(0.5) * 6.0)
	if w.entities.has(tk):
		w.entities[tk].order = {"type": "hold"}
		w.entities[tk].hp = 1.0e9
		w.entities[tk].max_hp = 1.0e9
	# POLISH7-4 (ORCH): damage.gd stamps last_hit_tick on units only (POLISH7-3 board warn seq 4677), so the tank's hits on
	# the towers / walls never make BaseState7 "under_fire"; ORCH decides that sim fix. Authority, owner 13.9c-17: the
	# facility goes into full lockdown "ONLY ... when facility is breached"; "contested" and "under fire" both show the
	# amber alert only (both are "not breached"), so this check accepts either state with the same amber / no-lockdown
	# requirement. The breach check below is unchanged (red only on a real breach).
	var uf: bool = await pt._wait_until(func(): return CnFacility.secure_state(w, fid) in ["contested", "under_fire"] and L.alarm_level(fid) > 0.0, 12.0)
	var au: Dictionary = L._alarm.get(fid, {})
	pt._log("atmo7_under_fire_amber", uf and L.alarm_level(fid) == 0.5 and not bool(au.get("red", false)) and not bool(au.get("lock_on", false)),
		"state %s alarm %.1f red %s lock %s (want contested or under_fire, 0.5 amber, no lockdown)" % [CnFacility.secure_state(w, fid), L.alarm_level(fid), str(au.get("red", false)), str(au.get("lock_on", false))])
	await _shots(pt, mv, L, "amber_under_fire", tu + Vector2(1.5, 1.5), [1, 2])
	mv.join_sim()
	if w.entities.has(tk):
		w.destroy(tk, "pt_cleanup")
	# 3. alarm: a real breach (hostiles inside the compound) -> the sim's own lockdown -> CnLockdown -> the layer.
	# ATMO7-2: the old scripted CnFacility._lockdown + mv.paused never showed: a step already queued for this frame's
	# frame_pre_draw (match_view._kick_pending, set before the pause) still ran and the sim lifted the lockdown at once
	# (no intruder). Now: real breach, wait for the alarm through the wired path, then pause (and wait a frame so no
	# queued step is left) to hold the alarm for the shots.
	L.set_time_of_day("day")
	await pt._wait(1.2)
	mv.join_sim()
	var foe := 1 if me == 0 else 0
	var Fs: Dictionary = CnFacility.fac(w, fid)
	var foes: Array = []
	for i in 3:
		var fu: Dictionary = h._unit(w, "rifleman", foe, CnFacility.zone(Fs, "pad").get_center() + Vector2(i, 0))
		fu.max_hp = 1.0e6   # a held breach for the shots: the defenders cannot clear it before the pause
		fu.hp = 1.0e6
		fu.order = {"type": "hold"}
		foes.append(int(fu.id))
	var lock_ev: bool = await pt._wait_until(func(): return L.alarm_level(fid) >= 1.0 and bool(L._alarm.get(fid, {}).get("lock_on", false)), 12.0)
	mv.paused = true
	await pt._wait(0.3)   # one frame for match_view to drop _kick_pending, then nothing steps
	mv.join_sim()
	var fe: Array = CnFacility.render_entries(w)
	print("ATMO7_DBG fid=%d entries=%s alarm=%s frame=%d" % [fid, str(fe.map(func(x): return [x.id, x.lock, x.state])), str(L._alarm), L._frame])
	pt._log("atmo7_alarm_real", lock_ev, "breach -> lockdown -> layer alarm via the wired events / entries (state %s)" % CnFacility.secure_state(w, fid))
	pt._log("atmo7_alarm", L.alarm_level(fid) >= 1.0, "alarm %.1f" % L.alarm_level(fid))
	await _shots(pt, mv, L, "alarm_day", centre, [1])
	pt._log("atmo7_alarm_draw", int(L.counts.get("beacons", 0)) >= 10 and int(L.counts.get("searchlights", 0)) >= 4 and int(L.counts.get("shutters", 0)) >= 4,
		"beacons %d searchlights %d shutters %d mist %d" % [int(L.counts.get("beacons", 0)), int(L.counts.get("searchlights", 0)), int(L.counts.get("shutters", 0)), int(L.counts.get("mist", 0))])
	var tw: Vector2 = L.geo[0].towers[0] if L.geo.size() > 0 else centre
	await _shots(pt, mv, L, "alarm_tower", tw + Vector2(1.5, 1.5), [1, 2, 3])
	if g0.size() > 0:
		var gr3: Array = g0[1 if g0.size() > 1 else 0]
		await _shots(pt, mv, L, "alarm_garages", Vector2(float(gr3[0]) + float(gr3[2]) + 0.8, float(gr3[1]) + 1.5), [2, 3])
	await _shots(pt, mv, L, "alarm_helipad", zc.call("helipad"), [2])
	await _shots(pt, mv, L, "alarm_planning", zc.call("planning") + Vector2(1.0, 1.0), [3])   # POLISH7: shutters on FACB7 doors
	await _shots(pt, mv, L, "alarm_lab", zc.call("lab") + Vector2(1.0, 1.0), [3])
	await _shots(pt, mv, L, "alarm_decon", zc.call("apc_wash") + Vector2(2, -2), [1])
	# POLISH7-2 (13.9c-14): every alarm light on a real fixture: tower roof slab corner, gate bastion caps, checkpoint
	# parapet, wall capping beam; nothing hangs in the air or in front of a building
	var gb: Dictionary = L.geo[0]
	var tws0: Array = gb.towers
	var bk: Vector2 = tws0[0]
	for q in tws0:
		if (q as Vector2).x + (q as Vector2).y < bk.x + bk.y:
			bk = q
	var on_slab: bool = absf(L.BEACON_OFF.x) * 4.0 <= 2.15 - 0.2 and absf(L.BEACON_OFF.y) * 4.0 <= 2.15 - 0.2 and absf(L.TOWER_ROOF_Z - 10.84 * 9.8) < 0.5
	var posts: Array = L._gate_posts(gb)
	var on_caps := posts.size() >= 3
	for i in posts.size() - 1:   # gate bastion caps: 5.85 m, inside a gate zone
		var inz := false
		for zn in ["gate_outer", "gate_inner"]:
			inz = inz or ((gb.zones as Dictionary).has(zn) and (gb.zones[zn] as Rect2).grow(0.01).has_point(posts[i][0]))
		on_caps = on_caps and inz and absf(float(posts[i][1]) - 5.85 * 9.8) < 0.5
	var nh := (gb.get("hid", {}) as Dictionary).size()
	pt._log("atmo7_beacon_fixtures", on_slab and on_caps and absf(L.WALL_CAP_Z - 46.0) < 0.5 and absf(L.MAST_TOP_Z - 12.78 * 9.8) < 0.5,
		"tower beacon %s on the 2.15 m roof slab at %.1f px; %d entry beacons on bastion caps / checkpoint parapet; wall floods / strobes on the battlement top at %.1f px (WALL7-2); %d lights hidden behind buildings" % [str(L.BEACON_OFF), L.TOWER_ROOF_Z, posts.size(), L.WALL_CAP_Z, nh])
	await _shots(pt, mv, L, "alarm_gate", go + Vector2(0, -0.5), [1, 2, 3])
	await _shots(pt, mv, L, "alarm_cp", Vector2(posts[posts.size() - 1][0]), [3])
	await _shots(pt, mv, L, "alarm_back_tower", bk + Vector2(1.0, 1.0), [1, 2, 3])
	L.set_time_of_day("night")
	await pt._wait(2.6)
	await _shots(pt, mv, L, "alarm_night", centre, [1, 2, 3])
	# frame-time A/B at the compound, night + alarm (worst case for this layer)
	_zoom(mv, 1.0)
	mv.center_camera_on(centre)
	await pt._wait(0.5)
	var on_ft: Array = await _frames(mv, 240)
	L.visible = false
	L.off = true
	var off_ft: Array = await _frames(mv, 240)
	L.off = false
	L.visible = true
	print("ATMO7_FRAMES on mean %.2f p90 %.2f gpu %.2f rcpu %.2f | off mean %.2f p90 %.2f gpu %.2f rcpu %.2f ms | layer draw us %s" % [on_ft[0], on_ft[1], on_ft[2], on_ft[3], off_ft[0], off_ft[1], off_ft[2], off_ft[3], str(L.prof)])
	pt._log("atmo7_frame_cost", true, "layer on mean %.2f p90 %.2f ms, off mean %.2f p90 %.2f ms (shared PC)" % [on_ft[0], on_ft[1], off_ft[0], off_ft[1]])
	mv.join_sim()
	for uid in foes:   # the breach ends: the sim lifts the lockdown by itself once the base is clear
		w.entities.erase(int(uid))
	w.cache.clear()
	mv.paused = false
	L.set_time_of_day("day")
	await pt._wait_until(func(): return L.alarm_level(fid) == 0.0, 15.0)
	await pt._wait(0.5)
	pt._log("atmo7_alarm_off", L.alarm_level(fid) == 0.0, "alarm %.1f after the lockdown lifts" % L.alarm_level(fid))
	# 4. damage: a burning tower, zone buildings by the core's hp, a destroyed tower's rubble, the ruin
	mv.join_sim()
	var towers: Array = []
	for id in w.entities:
		var te: Dictionary = w.entities[id]
		if String(te.get("def", "")) == "cn_tower" and Rect2(float(cr[0]) - 1.0, float(cr[1]) - 1.0, float(cr[2]) + 2.0, float(cr[3]) + 2.0).has_point(te.pos):
			towers.append(int(id))
	towers.sort()
	if towers.size() >= 2:
		w.entities[towers[0]].hp = float(w.entities[towers[0]].max_hp) * 0.12
		w.entities[towers[1]].hp = float(w.entities[towers[1]].max_hp) * 0.55
	w.entities[fid].hp = float(w.entities[fid].max_hp) * 0.25
	await pt._wait(1.5)
	await _shots(pt, mv, L, "damage", centre, [1])
	pt._log("atmo7_damage", int(L.counts.get("fires", 0)) >= 2 and int(L.counts.get("cracks", 0)) >= 3, "fires %d cracks %d" % [int(L.counts.get("fires", 0)), int(L.counts.get("cracks", 0))])
	if towers.size() >= 1:
		await _shots(pt, mv, L, "damage_tower", Vector2(w.entities[towers[0]].pos) if w.entities.has(towers[0]) else centre, [2, 3])
	await _shots(pt, mv, L, "damage_zone", zc.call("planning"), [2])
	if towers.size() >= 3:
		mv.join_sim()
		var tp: Vector2 = w.entities[towers[2]].pos
		w.destroy(towers[2], "pt_atmo7")
		await pt._wait(1.5)
		pt._log("atmo7_rubble", L._gone.size() >= 1, "rubble where a tower fell: %d" % L._gone.size())
		await _shots(pt, mv, L, "rubble_tower", tp, [2, 3])
	mv.join_sim()
	w.destroy(fid, "pt_atmo7")
	var ruined: bool = await pt._wait_until(func(): return L._ruins.size() >= 1, 6.0)
	await pt._wait(1.0)
	pt._log("atmo7_ruin", ruined, "ruins %d" % L._ruins.size())
	await _shots(pt, mv, L, "ruin", centre, [1, 2])
	_clean_view(mv, false)
