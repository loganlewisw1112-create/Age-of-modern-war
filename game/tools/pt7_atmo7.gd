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
	# 1. day: compound, signage + wear
	await _shots(pt, mv, L, "compound_day", centre, [1])
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
	await _shots(pt, mv, L, "helipad_wind", zc.call("helipad") + Vector2(2.0, 2.0), [2, 3])
	pt._log("atmo7_smoke_flags", int(L.counts.get("puffs", 0)) >= 12 and int(L.counts.get("flags", 0)) >= 2, "puffs %d mist %d flags %d" % [int(L.counts.get("puffs", 0)), int(L.counts.get("mist", 0)), int(L.counts.get("flags", 0))])
	await _shots(pt, mv, L, "decon_mist", zc.call("decon_hall"), [2, 3])
	if L.geo.size() > 0:
		await _shots(pt, mv, L, "hq_flags", (L.geo[0].flags[0] as Vector2) + Vector2(0.5, 0.5), [2, 3])
	# 2. night (and dusk): lights
	L.set_time_of_day("night")
	await pt._wait(2.6)
	await _shots(pt, mv, L, "compound_night", centre, [1])
	pt._log("atmo7_night", L.night_amount() > 0.95 and int(L.counts.get("dark", 0)) == 1 and int(L.counts.get("lights", 0)) >= 40, "night %.2f lights %d" % [L.night_amount(), int(L.counts.get("lights", 0))])
	if g0.size() > 0:
		var gr2: Array = g0[1 if g0.size() > 1 else 0]
		await _shots(pt, mv, L, "garages_night", Vector2(float(gr2[0]) + float(gr2[2]) + 0.8, float(gr2[1]) + 1.5), [2, 3])
	await _shots(pt, mv, L, "pad_night", zc.call("pad"), [1, 2])
	await _shots(pt, mv, L, "gate_night", go + Vector2(0, 1.0), [2])
	L.set_time_of_day("dusk")
	await pt._wait(1.5)
	await _shots(pt, mv, L, "compound_dusk", centre, [1])
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
	var uf: bool = await pt._wait_until(func(): return CnFacility.secure_state(w, fid) == "under_fire" and L.alarm_level(fid) > 0.0, 12.0)
	var au: Dictionary = L._alarm.get(fid, {})
	pt._log("atmo7_under_fire_amber", uf and L.alarm_level(fid) == 0.5 and not bool(au.get("red", false)) and not bool(au.get("lock_on", false)),
		"state %s alarm %.1f red %s lock %s (want under_fire, 0.5 amber, no lockdown)" % [CnFacility.secure_state(w, fid), L.alarm_level(fid), str(au.get("red", false)), str(au.get("lock_on", false))])
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
	pt._log("atmo7_beacon_fixtures", on_slab and on_caps and absf(L.WALL_CAP_Z - 3.78 * 9.8) < 0.5,
		"tower beacon %s on the 2.15 m roof slab at %.1f px; %d entry beacons on bastion caps / checkpoint parapet; wall lamps on the cap at %.1f px; %d lights hidden behind buildings" % [str(L.BEACON_OFF), L.TOWER_ROOF_Z, posts.size(), L.WALL_CAP_Z, nh])
	await _shots(pt, mv, L, "alarm_gate", go + Vector2(0, -0.5), [1, 2, 3])
	await _shots(pt, mv, L, "alarm_cp", Vector2(posts[posts.size() - 1][0]), [3])
	await _shots(pt, mv, L, "alarm_back_tower", bk + Vector2(1.0, 1.0), [1, 2, 3])
	L.set_time_of_day("night")
	await pt._wait(2.6)
	await _shots(pt, mv, L, "alarm_night", centre, [1, 2])
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
