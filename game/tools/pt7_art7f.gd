extends RefCounted
## G7 playtest flow art7f (ART7F, 13.9c): the counter-nanite facility rises; a frame-by-frame capture over 360
## frames with the OLD facility draw path (fac_cache_off: skips every frame a sim step is in flight) and 360 with
## the fix (cached entries), logging per frame the facility sprite count + draw-list hash; then shots of the compound
## and every interior building at zoom 1 / 2 / 3, the wall joins (corner, tower, gate), lockdown, and the dropship
## pad when its def exists.

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const EntityLayerRef = preload("res://presentation/view/entity_layer.gd")

const ZONES := ["planning", "lab", "drone_bay", "workshop", "range", "decon", "gate", "helipad", "pad", "staging", "core", "gate_outer", "apc_wash", "gate_inner", "decon_hall",
	"magazine", "armory", "aid_station", "barracks", "fuel_point", "runoff"]   # FACB7-3: + the 13.9c-6 buildings
## FACB7-3: extra compound-local spots shot at zoom 1 / 1.75 / 2.5: the foot entry (gatehouse + mantrap + bunker + the
## serpentine approach), the enclosed wash seen from outside, a tower-base locker, the entry-walkway lockers, wall turrets.
const SPOTS := [["ecp", Vector2(19.0, 28.5)], ["wash_enclosed", Vector2(14.0, 24.0)], ["locker_w", Vector2(2.5, 11.5)],
	["lockers_entry", Vector2(18.5, 25.0)], ["wturret_e", Vector2(27.0, 15.5)], ["wturret_n", Vector2(13.5, 1.0)]]
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


## FLOWA7: the open 29x29 spot (block 28 x 25 + the 8-tile side split) farthest from the compound rect cr.
func _far_open(w: SimWorld, h, cr: Array) -> Vector2i:
	var rc := Rect2(float(cr[0]), float(cr[1]), float(cr[2]), float(cr[3]))
	var best: Vector2i = h._open(w, 22)
	var bd := -1.0
	var y := 14
	while y < int(w.map.h) - 14:
		var x := 14
		while x < int(w.map.w) - 14:
			var c := Vector2i(x, y)
			var cp := Vector2(c) + Vector2(0.5, 0.5)
			var d: float = cp.distance_to(Vector2(clampf(cp.x, rc.position.x, rc.end.x), clampf(cp.y, rc.position.y, rc.end.y)))
			if d > bd and h._clear(w, c, 14):
				bd = d
				best = c
			x += 2
		y += 2
	return best


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
	# FLOWA7 (G7 final verification, 2026-10-28): the load fight is placed as FAR from the compound as the map allows.
	# h._open(w, 22) put it at the map centre (48, 48), its blocks spanning y 36..61: right against the north wall
	# (compound y 61..89). Since 13.9c-38 ("Double the watch": 48 Sentinels manning every wall and tower) and the
	# 24-drone hive, the facility engages that block and the block shoots back into the compound, so the facility
	# went "secure" -> "under_fire" mid-capture (diagnosis run: k0 false|secure|0|[..] -> false|under_fire|0|[..]) and
	# the "state unchanged" precondition of the flicker check failed. The fight is only CPU load for the capture; the
	# checks are unchanged.
	var lc: Vector2i = _far_open(w, h, cr)
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
	print("ART7F_LOAD units=%d at %s compound %s" % [nload, str(lc), str(cr)])
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
			int(spd), a[0], a[4], a[1], a[2], a[3], b[0], b[4], b[1], b[2], b[3], "unchanged" if k0 == k1 else "CHANGED %s -> %s" % [k0, k1]]
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
	await _facb75(pt, mv, w, F, fid, me, centre)   # FACB7-5 (13.9c-18): barracks + pad, workshop + drone-bay storey, no see-through
	var stk: Dictionary = F.get("stacked", {})
	for zn in ZONES:
		var r: Array = zs.get(zn, [])
		if r.size() != 4 or stk.has(zn):   # FACB7-5: an upper storey is shot with its host
			continue
		var zc := Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)
		for z in [1, 2, 3]:
			_zoom(mv, float(ZL[z]))
			mv.center_camera_on(zc)
			await pt._wait(0.4)
			await pt._shot("art7f_%s_z%d" % [zn, z])
	for sp in SPOTS:
		var spc: Vector2 = Vector2(float(cr[0]), float(cr[1])) + (sp[1] as Vector2)
		for z in [1, 2, 3]:
			_zoom(mv, float(ZL[z]))
			mv.center_camera_on(spc)
			await pt._wait(0.4)
			await pt._shot("art7f_%s_z%d" % [sp[0], z])
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
	var gt: Array = zs.get("gate_outer", zs.get("gate", [0, 0, 0, 0]))   # BASE7-3: "gate" retired
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
	# FACB7-3: the ruin states (the magazine's armoured cell cooked off, the Sentinel barracks destroyed), shot at 1.75 / 2.5
	for rz in [["magazine", "mag"], ["barracks", "bar"]]:
		mv.join_sim()
		var rid := int(Fs.get(rz[1], 0))
		if rid > 0 and w.entities.has(rid):
			w.destroy(rid, "pt_ruin", 1 - me if me <= 1 else 0)
		var rr: Array = zs.get(rz[0], [])
		if rr.size() != 4:
			continue
		await pt._wait(1.5)
		for z in [2, 3]:
			_zoom(mv, float(ZL[z]))
			mv.center_camera_on(Vector2(float(rr[0]) + float(rr[2]) * 0.5, float(rr[1]) + float(rr[3]) * 0.5))
			await pt._wait(0.5)
			await pt._shot("art7f_%s_ruin_z%d" % [rz[0], z])
	pt._log("art7f_ruins", true, "magazine / barracks ruin shots taken")
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


## FACB7-5 (owner 13.9c-18): the barracks at the drone bay's old site with a CN Vanta landed on its rooftop pad, the
## workshop with the drone-bay second storey, the whole compound, and our troops clearing a facility building: the
## building stays solid (opaque badge; no building / wreck sprite with alpha < 1 in any frame).
func _facb75(pt, mv, w: SimWorld, F: Dictionary, fid: int, me: int, centre: Vector2) -> void:
	var el = mv.entity_layer
	var zs: Dictionary = F.zones
	var br: Array = zs.get("barracks", [])
	var wr: Array = zs.get("workshop", [])
	mv.join_sim()
	var vid := -1
	for vd in ["cn_vanta_a", "cn_vanta_b"]:
		if vid < 0 and not Content.unit(vd).is_empty():
			var rp := CnFacility.roof_pad(w, CnFacility.fac(w, fid))
			vid = w.spawn_unit(vd, me, Vector2(rp.get("centre", centre)) + Vector2(0.0, 3.0))
	await pt._wait(1.5)
	mv.join_sim()
	var rp2 := CnFacility.roof_pad(w, CnFacility.fac(w, fid))
	var landed: bool = vid >= 0 and w.entities.has(vid) and not rp2.is_empty() and (rp2.rect as Rect2).grow(0.05).has_point(Vector2(w.entities[vid].pos))
	pt._log("facb75_vanta_on_barracks_pad", landed or vid < 0, "Vanta %d on the barracks roof pad at its new site %s" % [vid, str(rp2.get("rect", ""))])
	var bc := Vector2(float(br[0]) + float(br[2]) * 0.5, float(br[1]) + float(br[3]) * 0.5)
	var wc := Vector2(float(wr[0]) + float(wr[2]) * 0.5, float(wr[1]) + float(wr[3]) * 0.5)
	for sh in [["facb75_barracks_pad", bc, [1.75, 2.5]], ["facb75_workshop_dronebay", wc, [1.75, 2.5]], ["facb75_barracks_workshop_pair", (bc + wc) * 0.5, [1.0, 1.4]]]:
		for z in sh[2]:
			_zoom(mv, float(z))
			mv.center_camera_on(sh[1])
			await pt._wait(0.5)
			await pt._shot("%s_z%d" % [sh[0], int(float(z) * 10)])
	for z in [0.6, 1.0]:
		_zoom(mv, z)
		mv.center_camera_on(centre)
		await pt._wait(0.5)
		await pt._shot("facb75_compound_z%d" % int(z * 10))
	# troops clearing inside: the facility core and the armory part of the compound with roof_open for us
	mv.join_sim()
	var opened: Array = []
	var bids: Array = w.entities.keys()
	bids.sort()
	for id in bids:
		var e: Dictionary = w.entities[id]
		if String(e.kind) == "building" and int(e.owner) == me and Vector2(e.pos).distance_to(centre) < 18.0 \
				and not EntityLayerRef.WALL_LINK.has(String(e.def)) and opened.size() < 3 and int(Content.building(String(e.def)).get("size", 1)) >= 2:
			e["roof_open"] = me
			opened.append(int(id))
	var worst := 0
	var badges := 0
	for i in 40:
		await mv.get_tree().process_frame
		worst = maxi(worst, int(el.bld_see_through))
		badges = maxi(badges, int(el.g61_counts.get("roof", 0)))
	pt._log("facb75_no_see_through", worst == 0 and badges >= 1, "buildings being cleared: %d, badges drawn %d, building sprites with alpha < 1 in 40 frames: %d" % [opened.size(), badges, worst])
	if not opened.is_empty():
		var oc: Vector2 = Vector2(w.entities[int(opened[0])].pos) if w.entities.has(int(opened[0])) else centre
		for z in [1.75, 2.5]:
			_zoom(mv, z)
			mv.center_camera_on(oc)
			await pt._wait(0.5)
			await pt._shot("facb75_clearing_opaque_z%d" % int(z * 10))
	mv.join_sim()
	for id in opened:
		if w.entities.has(int(id)):
			w.entities[int(id)].erase("roof_open")
