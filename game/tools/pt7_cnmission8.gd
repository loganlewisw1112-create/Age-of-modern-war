extends RefCounted
## G7 CNMISSION8 playtest flow (master scope 13.9c-44): on the Last Protocol map, select a counter-nanite strike team
## through the UI (click its APC in the facility garage), press PURGE MISSION on the command bar, click a creep area,
## pick Drive on the card, then watch the team roll out of the facility, travel, deploy counter-nanites under the dome,
## purge the area and drive home to its garage. Also opens the F4 ops room team card (mission line + loadout).
## The flow writes the sim only to set the stage (a creep patch with a nest outside the south gate, the map explored,
## no Machine fire at the team) and says so. Shots at each stage (frame-exact: the sim pauses for the shot).
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-cnmission8

const M8 = preload("res://sim/systems/cn_mission8.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const Creep = preload("res://sim/systems/creep.gd")
const MapGen = preload("res://sim/map_gen.gd")

var pt
var tid := -1
var fid := 0


func _w() -> SimWorld:
	return pt._w()


func _phase() -> String:
	return String(M8.mission_of(_w(), tid).get("phase", ""))


func _apc_pos() -> Vector2:
	var t = CN.team(_w(), tid)
	for aid in t.apcs:
		var a = _w().entities.get(int(aid))
		if a != null:
			return Vector2(a.pos)
	return Vector2(-1, -1)


func _shot_at(p: Vector2, name: String) -> void:
	pt._mv().center_camera_on(p)
	await pt._wait(0.6)
	var sp: float = pt._mv().speed
	pt._mv().speed = 0.0
	await pt._wait(0.3)
	await pt._shot(name)
	pt._mv().speed = sp


func _wait_phase(phs: Array, secs: float) -> bool:
	return await pt._wait_until(func(): return phs.has(_phase()) or not M8.active(M8.mission_of(_w(), tid)), secs)


func run(p_) -> void:
	pt = p_
	if not MapGen.has_map("last_protocol"):
		pt._log("cnmission8_map", false, "last_protocol map not registered")
		return
	var LP = SimWorld.LastProtocol
	var started: bool = pt.main.start_match(LP.make_config(77, "last_protocol"))
	pt._log("cnmission8_match_started", started, "Last Protocol, seed 77")
	if not started:
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return _w().sys_state.has("lp") and bool(_w().sys_state.lp.get("filled", false)), 60.0)
	pt._log("cnmission8_facility_filled", ok, "facility filled (strike teams + stealth dropship) at tick %d" % _w().tick)
	if not ok:
		return
	mv.join_sim()
	var w := _w()
	var s: Dictionary = w.sys_state.lp
	fid = int(s.fid)
	var ex: PackedByteArray = w.fog[fid].explored
	ex.fill(1)
	w.fog[fid].explored = ex
	# stage: a creep patch with a Machine nest 46 tiles south of the base centre (outside the walls)
	var C := Vector2(s.base.center) + Vector2(0.5, 0.5)
	var site := C + Vector2(0, 46)
	var cs = Creep.enable(w)
	var v: PackedByteArray = cs.v
	var c0 := w.cell_of(site)
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			if dx * dx + dy * dy <= 25 and w.in_bounds(c0 + Vector2i(dx, dy)):
				v[Creep._k(cs, c0 + Vector2i(dx, dy))] = 200
	cs.v = v
	Creep.add_nest(w, site, 5, 3.0, int(s.mfid))
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and w.is_enemy(fid, int(e.owner)):
			e.cd_ticks = 1 << 30
	pt._log("cnmission8_stage", M8.cover(w, site) > 0.5, "flow-set stage: creep patch + nest at %s (creep %.0f%%), Machine fire held" % [str(site), M8.cover(w, site) * 100.0])
	# ---- select a strike team through the UI: click its APC in the garage
	var n: int = await pt._select_units(["g7_cn_strike_apc"])
	mv.join_sim()
	for id in mv.selection:
		var e = w.entities.get(int(id))
		if e != null and CN.team_of(e) >= 0 and String(CN.team(w, CN.team_of(e)).kind) == "strike":
			tid = CN.team_of(e)
			break
	# the card's purge team = the lowest strike team id in the selection
	var tids := []
	for id in mv.selection:
		var e = w.entities.get(int(id))
		if e != null and CN.team_of(e) >= 0 and String(CN.team(w, CN.team_of(e)).kind) == "strike" and not tids.has(CN.team_of(e)):
			tids.append(CN.team_of(e))
	tids.sort()
	if not tids.is_empty():
		tid = int(tids[0])
	pt._log("cnmission8_selected", n > 0 and tid >= 0, "%d selected, strike team %d" % [n, tid])
	if tid < 0:
		return
	await pt._wait(0.6)
	var pb: Button = pt._card_find("PURGE MISSION")
	pt._log("cnmission8_button", pb != null and not pb.disabled, "PURGE MISSION on the command bar%s" % ("" if pb == null else (" (tooltip: %s)" % pb.tooltip_text.get_slice("\n", 0))))
	var tb: Button = pt._card_find("Team orders")
	pt._log("cnmission8_team_orders_button", tb != null and not tb.disabled, "Team orders button present")
	await pt._shot("cnmission8_1_card")
	if pb == null:
		return
	await pt._click(pb.get_global_rect().get_center())
	await pt._wait(0.3)
	pt._log("cnmission8_armed", String(mv.g2.mode) == "cell_cmd", "click-target mode armed: %s" % mv.g2.status_text())
	# click a clean spot first: refused with the reason, the mode stays armed. The spot must lie beyond TARGET_R of
	# every creep cell (the patch has radius 5, so 14 tiles off was still a valid target): 22 tiles west of the site.
	var clean := site + Vector2(-22, 0)
	var cwhy: String = M8.mission_reason(w, fid, tid, clean, "drive")
	mv.center_camera_on(site + Vector2(-11, 0))
	await pt._wait(0.6)
	await pt._click(pt._to_screen(clean))
	await pt._wait(0.2)
	pt._log("cnmission8_clean_refused", cwhy == "No creep or core there to purge." and String(mv.g2.mode) == "cell_cmd", "clean ground refused (%s), still armed (%s)" % [cwhy, mv.g2.status_text()])
	mv.center_camera_on(site)
	await pt._wait(0.4)
	await pt._click(pt._to_screen(site))
	await pt._wait(0.5)
	var db: Button = pt._card_find("Drive")
	var fb: Button = pt._card_find("Fly")
	pt._log("cnmission8_drive_or_fly", db != null and fb != null and not db.disabled, "the card asks Drive or Fly (fly %s)" % ("enabled" if fb != null and not fb.disabled else ("disabled: " + fb.tooltip_text) if fb != null else "missing"))
	await pt._shot("cnmission8_2_drive_or_fly")
	if db == null:
		return
	await pt._click(db.get_global_rect().get_center())
	ok = await pt._wait_until(func(): return M8.active(M8.mission_of(_w(), tid)), 10.0)
	pt._log("cnmission8_mission_started", ok, "cn_mission drive submitted from the card: %s" % M8.status_line(_w(), tid))
	if not ok:
		return
	mv.speed = 4.0
	ok = await _wait_phase(["exit"], 30.0)
	await pt._wait(6.0)
	await _shot_at(_apc_pos(), "cnmission8_3_leaving_facility")
	ok = await _wait_phase(["travel"], 240.0)
	pt._log("cnmission8_left_facility", _phase() == "travel", "%s (tick %d)" % [M8.status_line(_w(), tid), _w().tick])
	await pt._wait(4.0)
	await _shot_at(_apc_pos(), "cnmission8_4_travel")
	ok = await _wait_phase(["deploy"], 240.0)
	pt._log("cnmission8_deploying", _phase() == "deploy", M8.status_line(_w(), tid))
	await pt._wait_until(func(): var t = CN.team(_w(), tid); return t != null and t.dep != null and String(t.dep.phase) == "arm", 120.0)
	await _shot_at(site, "cnmission8_5_deploying")
	ok = await _wait_phase(["return", "home", "hold"], 300.0)
	pt._log("cnmission8_purged", M8.cover(_w(), site) <= M8.PURGE_FRAC, "creep at the site %.0f%% after the purge (%s)" % [M8.cover(_w(), site) * 100.0, M8.status_line(_w(), tid)])
	await _shot_at(site, "cnmission8_6_purged")
	# ---- F4 ops room team card: mission line + loadout
	var card = pt.get_tree().root.find_child("TeamCard", true, false)
	if card != null and card.get("hub") != null:
		card.hub.open("teams")
		card.hub.select_team(tid)
		await pt._wait(0.8)
		var ml = card.find_child("MissionLine", true, false)
		pt._log("cnmission8_team_card", ml != null and String(ml.text).begins_with("PURGE"), "team card: %s" % (String(ml.text) if ml != null else "no mission line"))
		await pt._shot("cnmission8_7_team_card")
		card.hub.close()
	else:
		pt._log("cnmission8_team_card", false, "ops room team card not found")
	ok = await pt._wait_until(func(): return not M8.active(M8.mission_of(_w(), tid)), 400.0)
	var M := M8.mission_of(_w(), tid)
	pt._log("cnmission8_home", String(M.get("phase", "")) == "done", "%s; facility phase %s" % [M8.status_line(_w(), tid), String(M8.fac_team(_w(), tid).get("phase", ""))])
	mv.speed = 1.0
	await _fly_leg(C)


func _roles() -> Dictionary:
	return _roles_of(tid)


func _roles_of(team_id: int) -> Dictionary:
	var out := {}
	var t = CN.team(_w(), team_id)
	if t == null:
		return out
	for id in t.members:
		var e = CN.find(_w(), int(id))
		if e != null:
			var r := CN.role_of(e)
			out[r] = int(out.get(r, 0)) + 1
	return out


## FLY8B: the same team flies a second purge (Fly on the card) to a flow-set creep patch 46 tiles east of the base:
## shots of the strike APC rolling down the stealth dropship's ramp at the landing zone and of the purge blast.
func _fly_leg(C: Vector2) -> void:
	var mv = pt._mv()
	var w := _w()
	var site := C + Vector2(46, 4)
	var cs = Creep.enable(w)
	var v: PackedByteArray = cs.v
	var c0 := w.cell_of(site)
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			if dx * dx + dy * dy <= 25 and w.in_bounds(c0 + Vector2i(dx, dy)):
				v[Creep._k(cs, c0 + Vector2i(dx, dy))] = 200
	cs.v = v
	Creep.add_nest(w, site, 5, 3.0, int(w.sys_state.lp.mfid))
	pt._log("cnmission8_fly_stage", M8.cover(w, site) > 0.5, "flow-set stage: second creep patch + nest at %s (creep %.0f%%); team roles after the drive leg %s" % [str(site), M8.cover(w, site) * 100.0, str(_roles())])
	# the drive leg's team came home short-handed (no scanner / EW left), so the fly leg takes the facility's OTHER
	# strike team, fresh: click its APC in the garage (the card's purge team = the strike team in the selection)
	var t1 := tid
	var t2 := -1
	for x in CN.team_ids(w):
		var tt = CN.team(w, int(x))
		if String(tt.kind) == "strike" and int(tt.fid) == fid and int(x) != t1 and t2 < 0:
			t2 = int(x)
	var a2 = null
	if t2 >= 0:
		for aid in CN.team(w, t2).apcs:
			if a2 == null and w.entities.has(int(aid)):
				a2 = w.entities[int(aid)]
	pt._log("cnmission8_fly_team", a2 != null, "second strike team %d (APC %s), roles %s" % [t2, str(a2.id) if a2 != null else "-", str(_roles_of(t2))])
	if a2 == null:
		return
	mv.center_camera_on(Vector2(a2.pos))
	await pt._wait(0.6)
	await pt._click(pt._to_screen(Vector2(a2.pos)))
	await pt._wait(0.6)
	tid = t2
	var pb: Button = pt._card_find("PURGE MISSION")
	pt._log("cnmission8_fly_button", pb != null and not pb.disabled and mv.selection.has(int(a2.id)), "clicked team %d's APC (%d selected); PURGE MISSION for the fly leg" % [t2, mv.selection.size()])
	if pb == null or pb.disabled:
		return
	await pt._click(pb.get_global_rect().get_center())
	await pt._wait(0.3)
	mv.center_camera_on(site)
	await pt._wait(0.4)
	await pt._click(pt._to_screen(site))
	await pt._wait(0.5)
	var fb: Button = pt._card_find("Fly")
	pt._log("cnmission8_fly_offered", fb != null and not fb.disabled, "Fly on the card%s" % ("" if fb == null or not fb.disabled else ": " + fb.tooltip_text))
	if fb == null or fb.disabled:
		return
	await pt._click(fb.get_global_rect().get_center())
	var ok: bool = await pt._wait_until(func(): return M8.active(M8.mission_of(_w(), tid)) and String(M8.mission_of(_w(), tid).get("mode", "")) == "fly", 10.0)
	pt._log("cnmission8_fly_started", ok, "cn_mission fly submitted from the card: %s" % M8.status_line(_w(), tid))
	if not ok:
		return
	var team_id := tid
	mv.speed = 4.0
	ok = await _wait_phase(["air_unload"], 240.0)
	pt._log("cnmission8_fly_landed", _phase() == "air_unload", "%s (tick %d)" % [M8.status_line(_w(), tid), _w().tick])
	var ds_id := int(M8.mission_of(_w(), tid).get("ds", -1))
	var rolling := func():
		var ds = _w().entities.get(ds_id)
		return ds != null and ds.has("bay_seq") and String(ds.bay_seq.get("ph", "")) == "apc_out"
	ok = await pt._wait_until(rolling, 120.0)
	var dp := Vector2(_w().entities[ds_id].pos) if _w().entities.has(ds_id) else site
	if ok:
		mv.speed = 1.0
		await pt._wait(0.8)
	pt._log("cnmission8_fly_apc_out", ok, "bay sequence apc_out: the strike APC rolls down the ramp (tick %d)" % _w().tick)
	await _shot_at(dp, "cnmission8_8_fly_apc_off_ramp")
	mv.speed = 4.0
	ok = await _wait_phase(["deploy"], 240.0)
	pt._log("cnmission8_fly_deploying", _phase() == "deploy", "%s; roles %s (tick %d)" % [M8.status_line(_w(), tid), str(_roles()), _w().tick])
	var near_blast := func():
		var t = CN.team(_w(), team_id)
		if t == null or t.dep == null:
			return not ["deploy", "travel"].has(_phase())
		return String(t.dep.phase) == "arm" and int(t.dep.prog) + 40 >= CN.need_ticks(_w(), t, "arm")
	await pt._wait_until(near_blast, 300.0)
	mv.center_camera_on(site)
	mv.speed = 1.0
	await pt._wait_until(func(): var t = CN.team(_w(), team_id); return t == null or t.dep == null, 20.0)
	await pt._wait(0.15)
	mv.speed = 0.0
	await pt._wait(0.2)
	await pt._shot("cnmission8_9_fly_purge_blast")
	mv.speed = 4.0
	ok = await _wait_phase(["return", "air_pick", "home", "hold"], 300.0)
	pt._log("cnmission8_fly_purged", M8.cover(_w(), site) <= M8.PURGE_FRAC, "creep at the fly site %.0f%% after the purge (%s); roles %s (tick %d)" % [M8.cover(_w(), site) * 100.0, M8.status_line(_w(), tid), str(_roles()), _w().tick])
	ok = await pt._wait_until(func(): return not M8.active(M8.mission_of(_w(), tid)), 500.0)
	var M := M8.mission_of(_w(), tid)
	pt._log("cnmission8_fly_home", String(M.get("phase", "")) == "done", "%s; facility phase %s" % [M8.status_line(_w(), tid), String(M8.fac_team(_w(), tid).get("phase", ""))])
	mv.speed = 1.0
