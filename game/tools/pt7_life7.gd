extends RefCounted
## G7 playtest flow life7 (LIFE7, 13.9c-7): the living facility. Raises a counter-nanite facility, checks the
## fac_life7 layer is wired and laid out, then shots of every feature at zoom 1 / 1.75 / 2.5: the compound, staff,
## forklifts, the fuel bowser, the tow tractor, the guard dog, the gate check of an arrival, a garage shutter open for
## a unit at its door, the range during live fire, the ops building (radar, comms mast, window glow, ops-room inset),
## a tower cupola tracking an enemy, the perimeter drone. Display only: nothing here changes the layer's rules.

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
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


func _actor(L, kind: String, k := 0) -> Dictionary:
	if L.life.is_empty():
		return {}
	var n := 0
	for a in L.life[0].actors:
		if String(a.kind) == kind:
			if n == k:
				return a
			n += 1
	return {}


## Three shots of one feature; centre = a Callable returning the world point (actors move between shots).
func _shots3(pt, mv, name: String, centre: Callable, zooms := [1, 2, 3]) -> void:
	for z in zooms:
		_zoom(mv, float(ZL[z]))
		mv.center_camera_on(centre.call())
		await pt._wait(0.35)
		mv.center_camera_on(centre.call())
		await pt._wait(0.1)
		await pt._shot("life7_%s_z%d" % [name, z])


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var foe_side := 1 if me == 0 else 0
	var c: Vector2i = h._open(w, 18)
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(16, 16)
	var fid := w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): return _has_fac(pt), 8.0)
	pt._log("life7_facility_raised", raised, "facility %d" % fid)
	if not raised:
		return
	var L = mv.get("fac_life7")
	pt._log("life7_layer_wired", L != null, "match_view.fac_life7")
	if L == null:
		return
	mv.join_sim()
	var F: Dictionary = CnFacility.render_entries(w)[0]
	var cr: Array = F.compound
	var centre := Vector2(float(cr[0]) + float(cr[2]) * 0.5, float(cr[1]) + float(cr[3]) * 0.5)
	_clean_view(mv, true)
	_zoom(mv, 1.0)
	mv.center_camera_on(centre)
	var laid: bool = await pt._wait_until(func(): return not (L.life as Array).is_empty() and bool(L.visible), 6.0)
	var kinds := {}
	if laid:
		for a in L.life[0].actors:
			kinds[String(a.kind)] = int(kinds.get(String(a.kind), 0)) + 1
	pt._log("life7_laid_out", laid and int(kinds.get("tech", 0)) >= 4 and kinds.has("forklift") and kinds.has("fuel") and kinds.has("tug") and kinds.has("drone"), "actors %s" % str(kinds))
	if not laid:
		_clean_view(mv, false)
		return
	var Lf: Dictionary = L.life[0]
	await pt._wait(2.0)
	# 1. compound overview
	for z in [1, 2]:
		_zoom(mv, float(ZL[z]))
		mv.center_camera_on(centre)
		await pt._wait(0.6)
		await pt._shot("life7_compound_z%d" % z)
	pt._log("life7_drawn", (L.drawn as Dictionary).size() >= 3, "sprites drawn by id: %s" % str(L.drawn))
	# 2. moving actors, followed
	for kd in [["tech", 0], ["tech", 2], ["forklift", 0], ["forklift", 1], ["fuel", 0], ["tug", 0], ["dog", 0], ["drone", 0]]:
		var a: Dictionary = _actor(L, kd[0], kd[1])
		if a.is_empty():
			pt._log("life7_actor_%s%d" % [kd[0], kd[1]], false, "missing")
			continue
		if String(kd[0]) == "tech":   # wait until the technician is outside (not inside a building)
			await pt._wait_until(func(): return not bool(a.hidden), 25.0)
		await _shots3(pt, mv, "%s%d" % [kd[0], kd[1]], func(): return a.p)
		pt._log("life7_actor_%s%d" % [kd[0], kd[1]], not bool(a.hidden) or String(kd[0]) == "drone", "at %s pose %s" % [str(a.p), String(a.pose)])
	# POLISH7-2 (ENG7 4056): an engineer driving a display forklift / the fuel bowser: the vehicle (z 2, over the entity
	# layer) must cover the engineer figure drawn at the same point at every zoom. Shots only when ENG7 attaches one.
	var drv := {}
	var seen_drv: bool = await pt._wait_until(func():
		for Lx in L.life:
			for ax in Lx.actors:
				if String(ax.kind) in ["forklift", "fuel"] and int(ax.get("driver", -1)) >= 0:
					drv["a"] = ax
					return true
		return false, 40.0)
	if seen_drv:
		var da: Dictionary = drv.a
		await _shots3(pt, mv, "eng_drive", func(): return da.p)
		pt._log("life7_eng_drive", int(da.get("driver", -1)) >= 0 and not bool(da.hidden), "%s driven by engineer %d at %s pose %s (shots life7_eng_drive_z1..z3: the figure must not show)" % [String(da.kind), int(da.get("driver", -1)), str(da.p), String(da.pose)])
	else:
		print("LIFE7_INFO eng_drive not exercised: no engineer attached to a display vehicle within 40 s")
	# 3. ops building: radar, comms mast, window glow; the ops-room inset shows from zoom 1.6
	var pr: Rect2 = (Lf.zones as Dictionary).get("planning", Rect2())
	if pr.size != Vector2.ZERO:
		await _shots3(pt, mv, "ops", func(): return pr.get_center())
		pt._log("life7_ops_inset", bool(L.inset_shown), "inset drawn at zoom 2.5: %s" % str(L.inset_shown))
	# 4. range during live fire (drill cycle 44 s, live 6..28 s)
	var rr: Rect2 = (Lf.zones as Dictionary).get("range", Rect2())
	if rr.size != Vector2.ZERO:
		_zoom(mv, 1.75)
		mv.center_camera_on(rr.get_center())
		var live: bool = await pt._wait_until(func(): return bool(L.life[0].get("live_fire", false)), 50.0)
		await pt._wait(2.5)
		await _shots3(pt, mv, "range_live", func(): return rr.get_center())
		pt._log("life7_range_live_fire", live, "live fire seen on the range")
	# 5. gate check: a friendly rifleman arrives at the outer gate
	var gate: Dictionary = _actor(L, "gate", 0)
	if not gate.is_empty():
		mv.join_sim()
		var post: Vector2 = gate.post
		var dir := Vector2.from_angle(float(gate.post_face))
		var arr := w.spawn_unit("rifleman", me, post + dir * 2.2 + Vector2(0.6, 0))
		if w.entities.has(arr):
			w.entities[arr].order = {"type": "hold"}
		var checked: bool = await pt._wait_until(func(): return L.now() - float(gate.arr_t) < 9.0, 6.0)
		await _shots3(pt, mv, "gate_check", func(): return post + dir * 1.0)
		pt._log("life7_gate_check", checked, "gate guard pose %s" % String(gate.pose))
		mv.join_sim()
		if w.entities.has(arr):
			w.destroy(arr, "pt_cleanup")
	# 6. a garage shutter rolls open for a unit at its door (west row: the open face looks at the camera)
	var gd: Array = Lf.garage_door
	var gi := -1
	for i in gd.size():
		if (gd[i] as Vector2).x < centre.x:
			gi = i
			break
	if gi >= 0:
		mv.join_sim()
		var gu := w.spawn_unit("rifleman", me, gd[gi])
		if w.entities.has(gu):
			w.entities[gu].order = {"type": "hold"}
		var opened: bool = await pt._wait_until(func(): return L.door_open(fid, "g%d" % gi) > 0.9, 6.0)
		await _shots3(pt, mv, "garage_open", func(): return gd[gi], [2, 3])
		pt._log("life7_garage_open", opened, "g%d open %.2f" % [gi, L.door_open(fid, "g%d" % gi)])
		mv.join_sim()
		if w.entities.has(gu):
			w.destroy(gu, "pt_cleanup")
	# 7. tower cupola tracking an enemy tank outside the front (south-east) tower
	var tws: Array = Lf.towers
	var ti := 0
	for i in tws.size():
		if (tws[i] as Vector2).x + (tws[i] as Vector2).y > (tws[ti] as Vector2).x + (tws[ti] as Vector2).y:
			ti = i
	var tp: Vector2 = tws[ti]
	await _shots3(pt, mv, "tower_idle", func(): return tp)
	mv.join_sim()
	var out := (tp - centre).normalized()
	var ep := tp + out.rotated(0.5) * 6.0
	var en := w.spawn_unit("mbt", foe_side, ep)
	if w.entities.has(en):
		w.entities[en].order = {"type": "hold"}
		w.entities[en].hp = 1.0e9
		w.entities[en].max_hp = 1.0e9
	# POLISH7-2: read the layer's live entry each time (a rebuild that drops and re-adds the facility replaces the
	# dict, and a handle taken earlier would keep the frozen aim of the old one: run 1's "aim 0.51" failure)
	var Lv := func() -> Dictionary: return L.life[0] if not (L.life as Array).is_empty() else Lf
	# POLISH7-2 (13.9c-17): sampled while the tank is shooting (the state drops back to contested between its volleys)
	var uf: bool = await pt._wait_until(func(): return CnFacility.secure_state(w, fid) == "under_fire", 12.0)
	var st_uf := CnFacility.secure_state(w, fid)
	var al_uf := bool(Lv.call().alarm)
	await pt._wait(0.5)   # a frame or two for the layer to see the entry change
	al_uf = al_uf or bool(Lv.call().alarm)
	pt._log("life7_under_fire_life_goes_on", uf and not al_uf, "state %s, life7 alarm %s (want under_fire, false)" % [st_uf, str(al_uf)])
	var tracking: bool = await pt._wait_until(func(): return bool((Lv.call().aims as Dictionary).get("t%d" % ti, false)), 8.0)
	await pt._wait(1.5)
	await _shots3(pt, mv, "tower_tracking", func(): return tp)
	var want := (ep - tp).angle()
	var Lf2: Dictionary = Lv.call()
	var got := float((Lf2.aims as Dictionary).get(ti, 99.0))
	var foes_near := []   # POLISH7: diagnostics only (which hostiles the layer sees round this tower)
	for u in L._near:
		if int(u[1]) != int(Lf.owner) and int(u[1]) >= 0 and (u[0] as Vector2).distance_to(tp) < 14.0:
			foes_near.append("%s d%.1f a%.2f" % [str(u[0]), (u[0] as Vector2).distance_to(tp), ((u[0] as Vector2) - tp).angle()])
	var tank_at: Vector2 = w.entities[en].pos if w.entities.has(en) else ep
	pt._log("life7_cupola_tracks", tracking and absf(wrapf(got - want, -PI, PI)) < 0.3, "tower %d aim %.2f want %.2f tracking %s tank now %s (a %.2f) foes %s same_entry %s rebuilds %d" % [ti, got, want, str((Lf2.aims as Dictionary).get("t%d" % ti, false)), str(tank_at), (tank_at - tp).angle(), str(foes_near), str(is_same(Lf, Lf2)), int(L.rebuilds)])
	# POLISH7-2 (owner 13.9c-17): a tank shooting from outside = under fire = amber only: life goes on (no shelter,
	# vehicles drive, range not cold); the full alarm only on a real breach (hostiles inside the compound)
	await _shots3(pt, mv, "under_fire", func(): return centre, [1])
	mv.join_sim()
	if w.entities.has(en):
		w.destroy(en, "pt_cleanup")
	var bfoes := []
	var padr2: Rect2 = (Lf.zones as Dictionary).get("pad", Rect2(centre, Vector2.ONE))
	for i in 3:
		var bu := w.spawn_unit("rifleman", foe_side, padr2.get_center() + Vector2(i, 0))
		if w.entities.has(bu):
			w.entities[bu].order = {"type": "hold"}
			w.entities[bu].hp = 1.0e6
			w.entities[bu].max_hp = 1.0e6
			bfoes.append(bu)
	var br_ok: bool = await pt._wait_until(func(): return bool(Lv.call().alarm), 12.0)
	pt._log("life7_breach_alarm", br_ok, "breach (hostiles on the pad): state %s, life7 alarm %s" % [CnFacility.secure_state(w, fid), str(Lv.call().alarm)])
	await pt._wait(1.5)
	await _shots3(pt, mv, "alarm", func(): return centre, [1])
	mv.join_sim()
	for bu in bfoes:
		if w.entities.has(bu):
			w.destroy(bu, "pt_cleanup")
	# 8. A/B: layer off draws nothing
	L.on = false
	await pt._wait(0.3)
	var off_ok := not bool(L.visible)
	L.on = true
	await pt._wait(0.3)
	pt._log("life7_off_switch", off_ok and bool(L.visible), "off hides the layer, on brings it back")
	_clean_view(mv, false)
	_zoom(mv, 1.0)
