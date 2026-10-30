extends RefCounted
## G7 APCOUT8 playtest (owner bug on the packaged LP build: "i CANT send my apcs outside of the facility -- they just stop
## and cant make it through wash area"; same for the strike team and other units). Starts Last Protocol on the 768 map,
## selects every APC in the facility (strike teams + tactical squads aboard) plus a few foot units, right-clicks a point
## south of the outer wall through match_view.smart_command (the player's right-click path), and checks that every one
## of them gets past the outer wall, with the Machine near (outer gate hardened, sally port). Shots: the column leaving the gate, and all of them outside.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const FacDrive7 = preload("res://sim/systems/fac_drive7.gd")
const MapGen = preload("res://sim/map_gen.gd")
const OUT_D := 33.0


var _en := -1
var _at := Vector2.ZERO
var _mf := -1


## FACFLOW8C (13.9c-50): the Machine keeps coming: the threat by the compound is respawned whenever the base's guns
## kill it (as test_facexit8.keep_threat), so the gate stays hardened through the whole sally and return.
func _keep(w: SimWorld) -> void:
	if _mf < 0 or (_en >= 0 and w.entities.has(_en)):
		return
	_en = w.spawn_unit("rifleman", _mf, _at)
	var ee: Dictionary = w.entities[_en]
	ee.order = {"type": "hold"}
	ee.cd_ticks = 100000
	ee.hp = 1.0e9
	ee.max_hp = 1.0e9


func _cheb(a: Vector2, c: Vector2) -> float:
	return maxf(absf(a.x - c.x), absf(a.y - c.y))


func run(pt) -> void:
	if not MapGen.has_map("last_protocol"):
		pt._log("facexit8_registered", false, "last_protocol map not registered")
		return
	var cfg: Dictionary = SimWorld.LastProtocol.make_config(77, "last_protocol")
	var started: bool = pt.main.start_match(cfg)
	pt._log("facexit8_match_started", started, "")
	if not started:
		return
	await pt._wait(2.0)
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	mv.join_sim()
	var fid := int(w.sys_state.lp.fid)
	var facs: Array = CnFacility.facilities(w, fid)
	if facs.is_empty():
		pt._log("facexit8_facility", false, "no facility")
		return
	var F := CnFacility.fac(w, int(facs[0]))
	var cr := CnFacility.compound_rect(F)
	var C := Vector2(w.map.lp.base.center)
	var apcs := []
	var foot := []
	var ids: Array = []
	for e in w.units_of(fid):
		ids.append(int(e.id))
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if not cr.has_point(Vector2(e.pos)) or e.get("in_transport", false) or e.has("carrier"):
			continue
		if String(e.def).contains("apc"):
			apcs.append(id)
		elif (String(e.def) == "g7_fac_engineer" or String(e.def).begins_with("g7_sent_")) and foot.size() < 4:
			foot.append(id)
	pt._log("facexit8_units", apcs.size() == 8 and foot.size() >= 3, "APCs %d foot %d in the facility" % [apcs.size(), foot.size()])
	var ex: PackedByteArray = w.fog[0].explored
	ex.fill(1)
	w.fog[0].explored = ex
	var cam = mv.get("camera")
	# APCOUT8B: under pressure: a Machine-side rifleman holds near the base, so the outer gate hardens (13.9c-22) and
	# the APCs must sally out through the airlock (inner closes, outer opens, outer closes, inner opens)
	var mf := -1
	for f in w.factions.size():
		if w.is_enemy(fid, f):
			mf = f
			break
	_mf = mf
	_at = cr.end + Vector2(6, 8)
	_en = -1
	_keep(w)
	for id in apcs + foot:
		w.entities[id].cd_ticks = 100000
	var th := Time.get_ticks_msec()
	while Time.get_ticks_msec() - th < 30000 and not bool(F.get("gate", {}).get("hard", false)):
		await pt._wait(0.5)
		mv.join_sim()
		_keep(w)
	pt._log("facexit8_hardened", bool(F.get("gate", {}).get("hard", false)), "outer gate hardened with the Machine near: %s" % [F.get("gate", {})])
	# the player's right-click: select, then smart_command at a point outside (APCs, then the foot units nearer)
	mv.select_ids(apcs)
	# ORCH (RETURN8B finding): the move-group spreads 8 APCs over slots up to ~12 tiles from the clicked point; at
	# +44.5 one slot (C+(12.5,32.5)) sat past the outer wall (30) but inside OUT_D (33). Click farther out so every slot
	# is clear of OUT_D; the OUT_D check itself is unchanged.
	mv.smart_command(C + Vector2(0.5, 54.5))
	mv.select_ids(foot)
	mv.smart_command(C + Vector2(0.5, 40.5))
	mv.select_ids([])
	var out := {}
	var shot_gate := false
	var shot_air := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 360000 and out.size() < apcs.size() + foot.size():
		await pt._wait(0.5)
		mv.join_sim()
		_keep(w)
		for id in apcs + foot:
			var e = w.entities.get(id)
			if e != null and not out.has(id) and _cheb(Vector2(e.pos), C) >= OUT_D:
				out[id] = w.tick
		var GTa: Dictionary = F.get("gate", {})
		var o_up := String(GTa.get("o", "")) == "open" or (String(GTa.get("o", "")) == "opening" and int(GTa.get("ot", 99)) <= CnFacility.secs(FacDrive7.GATE_S) / 2)
		if not shot_air and o_up and String(GTa.get("i", "")) == "closed":
			var wz: Rect2 = CnFacility.zone(F, "apc_wash")
			var nw := 0
			for id in apcs:
				var e = w.entities.get(id)
				if e != null and wz.grow(0.3).has_point(Vector2(e.pos)):
					nw += 1
			if nw >= 3:   # FACFLOW8C (13.9c-50): 3 APCs in the longer airlock, outer gate open, inner gate shut
				shot_air = true
				cam.set_zoom_level(1.3)
				mv.center_camera_on(wz.get_center())
				await pt._wait(0.3)
				await pt._shot("facexit8_airlock_3apcs")
				pt._log("facexit8_airlock_3", true, "3 APCs in the airlock with the outer gate open and the inner gate shut")
		if not shot_gate and out.size() >= 2:
			shot_gate = true
			cam.set_zoom_level(0.9)
			mv.center_camera_on(C + Vector2(0, 30))
			await pt._wait(0.6)
			await pt._shot("facexit8_leaving_gate")
	var na := 0
	for id in out:
		if apcs.has(id):
			na += 1
	var stuck := []
	for id in apcs + foot:
		var e = w.entities.get(id)
		if not out.has(id):
			stuck.append([id, (Vector2(e.pos) - cr.position).snapped(Vector2(0.1, 0.1)) if e != null else "dead", preload("res://sim/systems/fac_drive7.gd").vstate(w, id).get("st", ""), F.get("gate", {})])
	pt._log("facexit8_apcs_out", na == apcs.size(), "APCs past the outer wall %d/%d (sim +%d ticks, %d s wall; not out %s)" % [na, apcs.size(), w.tick, (Time.get_ticks_msec() - t0) / 1000, stuck])
	pt._log("facexit8_foot_out", out.size() - na == foot.size(), "foot units past the outer wall %d/%d" % [out.size() - na, foot.size()])
	cam.set_zoom_level(0.7)
	mv.center_camera_on(C + Vector2(0, 41))
	await pt._wait(1.0)
	await pt._shot("facexit8_all_outside")
	# G7 RETURN8B (owner: several APCs returning together "can't come back in"): every team ordered home together
	# (cn_return, the facility panel's Return), the foot units walked back in; every APC must park in its garage.
	await _return_home(pt, w, F, cr, apcs, foot)


func _cmd(pt, cmd: Dictionary) -> String:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	cmd.issuer = int(mv.player_fid)
	if SimWorld.COMMANDS.has(String(cmd.type)):
		return String(w.submit(cmd).reason)
	var why := CnFacility.validate_command(w, cmd)
	if why == "":
		CnFacility.apply_command(w, cmd)
	return why


func _return_home(pt, w: SimWorld, F: Dictionary, cr: Rect2, apcs: Array, foot: Array) -> void:

	var mv = pt._mv()
	var cam = mv.get("camera")
	var fid := int(mv.player_fid)
	var tids := []
	for k in w.sys_state[CnFacility.KEY].teams:
		var TT: Dictionary = w.sys_state[CnFacility.KEY].teams[k]
		if int(TT.owner) == fid and not (TT.apcs as Array).is_empty():
			tids.append(int(k))
	tids.sort()
	var t1 := Time.get_ticks_msec()
	var allout := false
	while Time.get_ticks_msec() - t1 < 60000 and not allout:
		await pt._wait(0.5)
		mv.join_sim()
		_keep(w)
		allout = true
		for tid in tids:
			if String(CnFacility.team(w, tid).phase) != "out":
				allout = false
	pt._log("facexit8_teams_out", allout, "every team in phase out before the return (%d teams)" % tids.size())
	var bad := []
	for tid in tids:
		var why := _cmd(pt, {"type": "cn_return", "team": tid})
		if why != "":
			bad.append([tid, why])
	mv.join_sim()
	mv.select_ids(foot)
	mv.smart_command(cr.get_center() + Vector2(0.5, 4.5))
	mv.select_ids([])
	pt._log("facexit8_return_ordered", bad.is_empty(), "cn_return for %d teams together, refused %s" % [tids.size(), bad])
	var c0 := CnFacility.conf()
	var parked := {}
	var shot_mid := false
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 420000 and parked.size() < apcs.size():
		await pt._wait(0.5)
		mv.join_sim()
		_keep(w)
		for id in apcs:
			var V := FacDrive7.vstate(w, id)
			var at := String(V.get("at", ""))
			var e = w.entities.get(id)
			if e != null and String(V.get("st", "")) == "park" and at.begins_with("g"):
				if Vector2(e.pos).distance_to(FacDrive7.garage_park(c0, int(at.substr(1))) + cr.position) <= 0.5:
					parked[id] = w.tick
		if not shot_mid and parked.size() >= 3:
			shot_mid = true
			cam.set_zoom_level(1.0)
			mv.center_camera_on(cr.get_center() + Vector2(0, -2))
			await pt._wait(0.6)
			await pt._shot("facexit8_returning_to_garages")
	var nin := 0
	for id in foot:
		var e = w.entities.get(id)
		if e != null and cr.has_point(Vector2(e.pos)):
			nin += 1
	pt._log("facexit8_apcs_parked", parked.size() == apcs.size(), "APCs back in their garages %d/%d" % [parked.size(), apcs.size()])
	pt._log("facexit8_foot_home", nin == foot.size(), "foot units back inside the compound %d/%d" % [nin, foot.size()])
	cam.set_zoom_level(1.1)
	mv.center_camera_on(cr.get_center() + Vector2(0, -3))
	await pt._wait(1.0)
	await pt._shot("facexit8_apcs_parked_in_garages")
