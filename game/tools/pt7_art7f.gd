extends RefCounted
## G7 playtest flow art7f (ART7F, 13.9c): the counter-nanite facility rises; a frame-by-frame capture over 360
## frames with the OLD facility draw path (fac_cache_off: skips every frame a sim step is in flight) and 360 with
## the fix (cached entries), logging per frame the facility sprite count + draw-list hash; then shots of the compound
## and every interior building at zoom 1 / 2 / 3, the wall joins (corner, tower, gate), lockdown, and the dropship
## pad when its def exists.

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")

const ZONES := ["planning", "lab", "drone_bay", "workshop", "range", "decon", "gate", "helipad", "pad", "staging", "core", "gate_outer", "apc_wash", "gate_inner", "decon_hall"]
## ART7F-2: shot zoom levels named z1 / z2 / z3 (the camera clamps at ZOOM_MAX 2.5, so "3" is the closest it allows).
const ZL := {1: 1.0, 2: 1.75, 3: 2.5}
var _hidden: Array = []


## Shots show the art itself: HUD panels and the fog overlay off while shooting (display only), back on after.
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


## n frames of capture: [frames, frames with 0 facility sprites, distinct (count, hash) pairs, sig changes, busy frames]
func _capture(pt, mv, n: int) -> Array:
	var el = mv.entity_layer
	var zero := 0
	var busy := 0
	var changes := 0
	var last := -1
	var seen := {}
	for i in n:
		await mv.get_tree().process_frame
		if mv.sim_busy():
			busy += 1
		var fd := int(el.fac_drawn)
		var sg := int(el.fac_sig)
		if fd == 0:
			zero += 1
		var k := "%d:%d" % [fd, sg]
		seen[k] = true
		if last >= 0 and sg != last:
			changes += 1
		last = sg
	return [n, zero, seen.size(), changes, busy]


func _has_fac(pt) -> bool:
	pt._mv().join_sim()
	return not CnFacility.render_entries(pt._w()).is_empty()


func _fac_key(F: Dictionary) -> String:
	return "%s|%s|%d|%s" % [str(F.lock), str(F.state), int(F.heli), str(F.garage_team)]


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
	pt._log("art7f_facility_raised", raised, "facility %d" % fid)
	if not raised:
		return
	mv.join_sim()
	var F: Dictionary = CnFacility.render_entries(w)[0]
	var cr: Array = F.compound
	var centre := Vector2(float(cr[0]) + float(cr[2]) * 0.5, float(cr[1]) + float(cr[3]) * 0.5)
	mv.center_camera_on(centre)
	_zoom(mv, 1.0)
	await pt._wait(1.0)
	# 1. flicker: old path vs fixed path, same scene, facility state unchanged during both captures
	var el = mv.entity_layer
	var k0 := _fac_key(F)
	# a real fight elsewhere on the map (two 700-man blocks), so sim steps run longer than a frame like in a big match
	mv.join_sim()
	var lc: Vector2i = h._open(w, 22)
	var foe := 1 if me == 0 else 0
	var nload := 0
	var load_ids: Array = []
	for i in 700:
		for side in [me, foe]:
			var p := Vector2(lc) + Vector2(float(i % 28) - 14.0 + (8.0 if side == foe else -8.0) * 0.5, float(i / 28) - 12.0)
			var uid := w.spawn_unit("rifleman", side, p)
			if uid >= 0:
				nload += 1
				load_ids.append(uid)
	print("ART7F_LOAD units=%d at %s" % [nload, str(lc)])
	var ok_all := true
	var old_empty := 0
	for spd in [1.0, 3.0]:   # 3x: a step is in flight at most frames' entity refresh (PERF7D chain kick), like a heavy fight
		mv.speed = spd
		await pt._wait(0.5)
		el.fac_cache_off = true
		var fb0 := int(el.fac_busy)
		var a: Array = await _capture(pt, mv, 360)
		a[4] = int(el.fac_busy) - fb0
		el.fac_cache_off = false
		await pt._wait(0.2)
		fb0 = int(el.fac_busy)
		var b: Array = await _capture(pt, mv, 360)
		b[4] = int(el.fac_busy) - fb0
		mv.join_sim()
		var k1 := _fac_key(CnFacility.render_entries(w)[0])
		var line := "speed %dx OLD frames=%d busy_refresh=%d empty=%d distinct=%d sig_changes=%d | FIXED frames=%d busy_refresh=%d empty=%d distinct=%d sig_changes=%d | state %s" % [
			int(spd), a[0], a[4], a[1], a[2], a[3], b[0], b[4], b[1], b[2], b[3], "unchanged" if k0 == k1 else "CHANGED"]
		print("ART7F_FLICKER " + line)
		old_empty += int(a[1])
		ok_all = ok_all and k0 == k1 and int(b[1]) == 0 and int(b[3]) == 0 and int(b[2]) == 1
		pt._log("art7f_flicker_fixed_%dx" % int(spd), k0 == k1 and int(b[1]) == 0 and int(b[3]) == 0 and int(b[2]) == 1, line)
	mv.speed = 1.0
	pt._log("art7f_flicker_cause_reproduced", old_empty > 0, "old path frames with the whole compound missing: %d" % old_empty)
	pt._log("art7f_ground", int(mv.get("baseprops_layer").get("drawn_ground")) >= 1 if mv.get("baseprops_layer") != null else true, "compound hardstand drawn")
	pt._log("art7f_walls_linked", int(el.walls_linked) >= 20, "wall segments drawn with the conn sheet: %d" % int(el.walls_linked))
	# ART7F-2: the load fight is only for the flicker capture; clear it so the shots show the facility alone
	mv.join_sim()
	for uid in load_ids:
		if w.entities.has(int(uid)):
			w.destroy(int(uid), "pt_cleanup")
	await pt._wait(0.6)
	_clean_view(mv, true)
	# 2. shots: compound + every interior building at zoom 1 / 2 / 3
	for z in [0.6, 1.0]:
		_zoom(mv, z)
		mv.center_camera_on(centre)
		await pt._wait(0.6)
		await pt._shot("art7f_compound_z%d" % int(z * 10))
	var zs: Dictionary = F.zones
	for zn in ZONES:
		var r: Array = zs.get(zn, [])
		if r.size() != 4:
			continue
		var zc := Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)
		for z in [1, 2, 3]:
			_zoom(mv, float(ZL[z]))
			mv.center_camera_on(zc)
			await pt._wait(0.4)
			await pt._shot("art7f_%s_z%d" % [zn, z])
	var g0: Array = F.get("garage_rects", [])
	for gi in [0, g0.size() - 1]:   # ART7F-2: first garage of the west row and last of the east row, centred on the rect
		if gi < 0 or gi >= g0.size():
			continue
		var gr: Array = g0[gi]
		var gc := Vector2(float(gr[0]) + float(gr[2]) * 0.5, float(gr[1]) + float(gr[3]) * 0.5)
		for z in [2, 3]:
			_zoom(mv, float(ZL[z]))
			mv.center_camera_on(gc)
			await pt._wait(0.4)
			await pt._shot("art7f_garage%d_z%d" % [gi, z])
	# 3. wall joins: NW corner, a tower, the gate
	var gt: Array = zs.get("gate", [0, 0, 0, 0])
	var joins: Array = [["corner_nw", Vector2(float(cr[0]) + 1.0, float(cr[1]) + 1.0)], ["corner_se", Vector2(float(cr[0] + cr[2]) - 1.0, float(cr[1] + cr[3]) - 1.0)],
			["gate", Vector2(float(gt[0]) + float(gt[2]) * 0.5, float(gt[1]) + 1.0)]]
	mv.join_sim()
	var tws: Array = []   # ART7F-2 (13.9c-3): every hardened tower's wall join
	for id in w.entities:
		var te: Dictionary = w.entities[id]
		if String(te.get("def", "")) == "cn_tower" and Rect2(float(cr[0]) - 1.0, float(cr[1]) - 1.0, float(cr[2]) + 2.0, float(cr[3]) + 2.0).has_point(te.pos):
			tws.append(te.pos)
	tws.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for ti in tws.size():
		joins.append(["tower%d" % ti, tws[ti]])
	pt._log("art7f_towers_shot", tws.size() >= 4, "towers in the ring: %d" % tws.size())
	for jn in joins:
		for z in [2, 3]:
			_zoom(mv, float(ZL[z]))
			mv.center_camera_on(jn[1])
			await pt._wait(0.4)
			await pt._shot("art7f_wall_%s_z%d" % [jn[0], z])
	# 4. lockdown look
	mv.join_sim()
	var Fs: Dictionary = CnFacility.fac(w, fid)
	Fs.lock = true
	_zoom(mv, 1.0)
	mv.center_camera_on(centre)
	await pt._wait(1.0)
	await pt._shot("art7f_compound_lockdown_z10")
	mv.join_sim()
	Fs.lock = false
	# 5. dropship landing site (BASE7-2 def a_g7_vtol_pad), approach on +y
	if not Content.building("a_g7_vtol_pad").is_empty():
		mv.join_sim()
		var pc := Vector2i(int(cr[0]) + int(cr[2]) + 4, int(cr[1]) + 4)
		var pid := w.spawn_building("a_g7_vtol_pad", me, pc, true)
		if w.entities.has(pid):
			w.entities[pid].facing_i = 1
		for z in [1, 2]:
			_zoom(mv, float(ZL[z]))
			mv.center_camera_on(Vector2(pc) + Vector2(3, 3))
			await pt._wait(0.6)
			await pt._shot("art7f_vtol_pad_z%d" % z)
		pt._log("art7f_vtol_pad", w.entities.has(pid), "pad %d" % pid)
	else:
		pt._log("art7f_vtol_pad", true, "a_g7_vtol_pad def not in content yet (BASE7-2): pad shot skipped")
	_clean_view(mv, false)
	_zoom(mv, 1.0)
