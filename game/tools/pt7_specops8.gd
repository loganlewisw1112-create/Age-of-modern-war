extends RefCounted
## G7 SPECOPS8 playtest flow (master scope 13.9c-44): the four spec-ops missions of the tactical operator squads, each
## ordered from the real UI on the Last Protocol map:
##   1. Recon & mark (DRIVE) from the command bar: click the squad's APC in its garage, press "Recon & mark", click a
##      clean-of-nothing spot first (refused), then the creep area: the APC leaves the gates, scouts, marks.
##   2. Core raid (FLY) from the F4 ops room: team card -> INSERT: FLY -> SpecOps CORE RAID -> click the core on the
##      strategic map: the squad loads the dropship, flies, plants, withdraws, detonates, flies home.
##   3. Escort (DRIVE) from the command bar with the hotkey (Shift+G): click the strike team on its purge mission.
##   4. Rescue (DRIVE) from the command bar (Shift+M): click the downed group; the wounded man is carried aboard.
## The flow writes the sim only to set the stage and says so: the map explored, Machine fire held, creep spread off, a
## creep patch + Machine unit to scout, a core to raid, a downed group (one wounded) to rescue, and the strike team's
## purge mission (submitted as a cn_mission command: its UI is CNMISSION8's flow). Missions are launched one after the
## other (each once the previous one has left the facility) so the shots show each one; the sim lets them out together
## too (test_specops8 test_drive_all).
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-specops8

const SO = preload("res://sim/systems/specops8.gd")
const M8 = preload("res://sim/systems/cn_mission8.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const Medical = preload("res://sim/systems/medical.gd")
const MapGen = preload("res://sim/map_gen.gd")

var pt
var fid := 0
var mfid := -1
var C := Vector2.ZERO


func _w() -> SimWorld:
	return pt._w()


func _ph(tid: int) -> String:
	return String(SO.mission_of(_w(), tid).get("phase", ""))


func _team_pos(tid: int) -> Vector2:
	var t = CN.team(_w(), tid)
	if t == null:
		return C
	for id in (t.apcs as Array) + (t.members as Array):
		var e = _w().entities.get(int(id))
		if e != null and not bool(e.get("in_transport", false)) and e.get("carried_by") == null:
			return Vector2(e.pos)
	for id in t.apcs:
		var e = _w().entities.get(int(id))
		if e != null:
			return Vector2(e.pos)
	return C


func _shot_at(p: Vector2, name: String) -> void:
	pt._mv().center_camera_on(p)
	await pt._wait(0.6)
	var sp: float = pt._mv().speed
	pt._mv().speed = 0.0
	await pt._wait(0.3)
	await pt._shot(name)
	pt._mv().speed = sp


func _wait_phase(tid: int, phs: Array, secs: float) -> bool:
	return await pt._wait_until(func():
		_keep_clean()
		return phs.has(_ph(tid)) or not SO.active(SO.mission_of(_w(), tid)), secs)


## SPECOPS8E (stage): the downed group waits on clean ground. Creep has no "spread off" switch (cfg creep_spread is not
## read), so the riflemen died of nanite exposure before the rescue squad (4th out of the garage) arrived and shot 9
## showed an empty field. The flow clears creep round them until the rescue squad starts searching.
var clean_at := Vector2(-1, -1)
var clean_tid := -1
var clean_tick := -1


func _keep_clean() -> void:
	if clean_at.x < 0:
		return
	var w := _w()
	if w.tick == clean_tick or (clean_tid >= 0 and not ["", "board", "exit", "travel"].has(_ph(clean_tid))):
		return
	clean_tick = w.tick
	var cs = Creep.enable(w)
	var v: PackedByteArray = cs.v
	var c0 := w.cell_of(clean_at)
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			if w.in_bounds(c0 + Vector2i(dx, dy)):
				v[Creep._k(cs, c0 + Vector2i(dx, dy))] = 0
	cs.v = v


func _shift_key(code: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.shift_pressed = true
		k.pressed = pressed
		pt._push(k)
		await pt.get_tree().process_frame


## Select team tid through the UI: click its APC (or a member) where it stands.
func _select_team(tid: int) -> bool:
	var t = CN.team(_w(), tid)
	if t == null:
		return false
	var mv = pt._mv()
	for attempt in 3:
		var pick = null
		for id in (t.apcs as Array) + (t.members as Array):
			var e = _w().entities.get(int(id))
			if e != null and not bool(e.get("in_transport", false)):
				pick = e
				break
		if pick == null:
			return false
		var sp: float = mv.speed
		mv.speed = 0.0
		mv.center_camera_on(Vector2(pick.pos))
		await pt._wait(0.5)
		await pt._click(pt._to_screen(Vector2(pick.pos)))
		await pt._wait(0.4)
		mv.speed = sp
		mv.join_sim()
		for id in mv.selection:
			var e = _w().entities.get(int(id))
			if e != null and CN.team_of(e) == tid:
				return true
	return false


func run(p_) -> void:
	pt = p_
	if not MapGen.has_map("last_protocol"):
		pt._log("specops8_map", false, "last_protocol map not registered")
		return
	var LP = SimWorld.LastProtocol
	var started: bool = pt.main.start_match(LP.make_config(77, "last_protocol"))
	pt._log("specops8_match_started", started, "Last Protocol, seed 77")
	if not started:
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return _w().sys_state.has("lp") and bool(_w().sys_state.lp.get("filled", false)), 60.0)
	pt._log("specops8_facility_filled", ok, "facility filled at tick %d" % _w().tick)
	if not ok:
		return
	mv.join_sim()
	var w := _w()
	var s: Dictionary = w.sys_state.lp
	fid = int(s.fid)
	mfid = int(s.mfid)
	C = Vector2(s.base.center) + Vector2(0.5, 0.5)
	# ---- stage (flow-set, see the header)
	var ex: PackedByteArray = w.fog[fid].explored
	ex.fill(1)
	w.fog[fid].explored = ex
	w.cfg["creep_spread"] = false
	var cs = Creep.enable(w)
	var v: PackedByteArray = cs.v
	var purge := C + Vector2(0, 46)
	var rp := C + Vector2(-26, 56)
	for pc in [[purge, 5], [rp, 4]]:
		var c0: Vector2i = w.cell_of(pc[0])
		var r: int = pc[1]
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy <= r * r and w.in_bounds(c0 + Vector2i(dx, dy)):
					v[Creep._k(cs, c0 + Vector2i(dx, dy))] = 200
	cs.v = v
	var mu := w.spawn_unit("m_hauler", mfid, rp + Vector2(3, 2))
	w.entities[mu].order = {"type": "hold"}
	var core_id := Cores.place(w, mfid, w.cell_of(C + Vector2(34, 58)))
	var core_hp0 := float(w.entities[core_id].hp)
	var resc := C + Vector2(14, 70)
	clean_at = resc
	_keep_clean()
	var surv := []
	for i in 3:
		surv.append(w.spawn_unit("rifleman", fid, resc + Vector2(float(i), 0.0)))
	Medical.wound(w, w.entities[surv[0]])
	Medical._state(w).wounded[int(surv[0])] = 1 << 28   # no bleed-out while the flow runs
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and w.is_enemy(fid, int(e.owner)):
			e.cd_ticks = 1 << 30
	var tac := []
	var st := []
	for t_ in CN.team_ids(w):
		var t: Dictionary = CN.team(w, int(t_))
		if int(t.fid) != fid:
			continue
		if String(t.kind) == "tactical":
			tac.append(int(t_))
		elif String(t.kind) == "strike":
			st.append(int(t_))
	tac.sort()
	st.sort()
	pt._log("specops8_stage", tac.size() >= 4 and st.size() >= 1, "flow-set stage: creep patches, Machine hauler, core %d, downed group (1 wounded); %d operator squads, %d strike teams" % [core_id, tac.size(), st.size()])
	if tac.size() < 4 or st.is_empty():
		return
	# ================================================== 1. RECON & MARK, drive, command bar button
	var t_rec: int = tac[0]
	ok = await _select_team(t_rec)
	pt._log("specops8_recon_selected", ok, "operator squad %d selected by clicking its APC" % t_rec)
	await pt._wait(0.6)
	var rb: Button = pt._card_find("Recon & mark")
	var ib: Button = pt._card_find("Insert")
	pt._log("specops8_buttons", rb != null and not rb.disabled and ib != null and pt._card_find("Core raid") != null and pt._card_find("Escort") != null and pt._card_find("Rescue") != null,
		"command bar: Escort / Core raid / Recon & mark / Rescue / Insert%s" % ("" if rb == null else " (Recon tooltip: %s)" % rb.tooltip_text.get_slice("\n", 0)))
	await pt._shot("specops8_1_command_bar")
	if rb == null:
		return
	await pt._click(rb.get_global_rect().get_center())
	await pt._wait(0.3)
	pt._log("specops8_recon_armed", String(mv.g2.mode) == "cell_cmd", "click-target mode: %s" % mv.g2.status_text())
	mv.center_camera_on(rp)
	await pt._wait(0.6)
	await pt._click(pt._to_screen(rp))
	ok = await pt._wait_until(func(): return SO.active(SO.mission_of(_w(), t_rec)), 10.0)
	pt._log("specops8_recon_started", ok and String(SO.mission_of(_w(), t_rec).get("kind", "")) == "recon", "so_mission recon/drive from the button: %s" % SO.status_line(_w(), t_rec))
	if not ok:
		return
	mv.speed = 4.0
	await _wait_phase(t_rec, ["exit"], 60.0)
	await pt._wait(3.0)
	await _shot_at(_team_pos(t_rec), "specops8_2_recon_leaving")
	# ================================================== 2. CORE RAID, fly, F4 ops room team card + strategic map
	var t_raid: int = tac[1]
	var card = pt.get_tree().root.find_child("TeamCard", true, false)
	ok = card != null and card.get("hub") != null
	pt._log("specops8_team_card_found", ok, "F4 ops room team card")
	if ok:
		card.hub.open("teams")
		card.hub.select_team(t_raid)
		await pt._wait(0.8)
		var ins = card.find_child("SpecOps_insert", true, false)
		var rd = card.find_child("SpecOps_raid", true, false)
		var sl = card.find_child("SpecOpsLine", true, false)
		pt._log("specops8_card_section", ins != null and rd != null and sl != null and not (rd as Button).disabled, "SPEC OPS section: %s" % (String(sl.text) if sl != null else "missing"))
		if ins != null:
			await pt._click((ins as Button).get_global_rect().get_center())
			await pt._wait(0.3)
		pt._log("specops8_card_fly", ins != null and String((ins as Button).text).contains("FLY"), "insert toggled: %s" % (String((ins as Button).text) if ins != null else "?"))
		await pt._shot("specops8_3_team_card_fly")
		if rd != null:
			await pt._click((rd as Button).get_global_rect().get_center())
			await pt._wait(0.8)
		var sm = card.hub.page("map") if card.hub.has_method("page") else null
		ok = sm != null and (sm.get("pick") as Dictionary).get("so", "") == "raid"
		pt._log("specops8_map_pick", ok, "strategic map in pick mode: %s" % (str(sm.get("pick")) if sm != null else "no map"))
		if ok:
			await pt._shot("specops8_4_map_pick")
			var cp: Vector2 = Vector2(_w().entities[core_id].pos)
			var px: Vector2 = (sm as Control).get_global_transform() * sm._to_px(cp, _w())
			await pt._click(px)
			await pt._wait(0.5)
		var lp_ = sm.get("last_pick") if sm != null else null
		pt._log("specops8_raid_picked", lp_ is Dictionary and String(lp_.get("type", "")) == "so_mission" and String(lp_.get("mode", "")) == "fly", "map click submitted: %s" % str(lp_))
		card.hub.close()
	ok = await pt._wait_until(func(): return SO.active(SO.mission_of(_w(), t_raid)), 10.0)
	pt._log("specops8_raid_started", ok and String(SO.mission_of(_w(), t_raid).get("mode", "")) == "fly", SO.status_line(_w(), t_raid))
	# ================================================== 3. ESCORT, drive, hotkey Shift+G on the command bar
	var t_esc: int = tac[2]
	var why: String = pt._mv().world.preview_command({"type": "cn_mission", "issuer": fid, "team_id": int(st[0]), "target": [purge.x, purge.y], "mode": "drive"})
	pt.main.hud._issue({"type": "cn_mission", "team_id": int(st[0]), "target": [purge.x, purge.y], "mode": "drive"})
	ok = await pt._wait_until(func(): return M8.active(M8.mission_of(_w(), int(st[0]))), 10.0)
	pt._log("specops8_purge_stage", ok, "flow-set: strike team %d on a purge mission (cn_mission; %s)" % [int(st[0]), why if why != "" else M8.status_line(_w(), int(st[0]))])
	ok = await _select_team(t_esc)
	pt._log("specops8_escort_selected", ok, "operator squad %d selected" % t_esc)
	await pt._wait(0.5)
	await _shift_key(KEY_G)
	await pt._wait(0.3)
	pt._log("specops8_escort_armed", String(mv.g2.mode) == "cell_cmd", "Shift+G: %s" % mv.g2.status_text())
	var sp_ := _team_pos(int(st[0]))
	mv.speed = 0.0
	mv.center_camera_on(sp_)
	await pt._wait(0.5)
	await pt._click(pt._to_screen(_team_pos(int(st[0]))))
	mv.speed = 4.0
	ok = await pt._wait_until(func(): return SO.active(SO.mission_of(_w(), t_esc)), 10.0)
	pt._log("specops8_escort_started", ok and String(SO.mission_of(_w(), t_esc).get("kind", "")) == "escort", SO.status_line(_w(), t_esc))
	# ================================================== 4. RESCUE, drive, hotkey Shift+M (SPREAD8: was Shift+Y)
	var t_res: int = tac[3]
	clean_tid = t_res
	ok = await _select_team(t_res)
	pt._log("specops8_rescue_selected", ok, "operator squad %d selected" % t_res)
	await pt._wait(0.5)
	await _shift_key(KEY_M)
	await pt._wait(0.3)
	pt._log("specops8_rescue_armed", String(mv.g2.mode) == "cell_cmd", "Shift+M: %s" % mv.g2.status_text())
	mv.speed = 0.0
	mv.center_camera_on(resc)
	await pt._wait(0.5)
	await pt._click(pt._to_screen(resc + Vector2(1, 0)))
	mv.speed = 4.0
	ok = await pt._wait_until(func(): return SO.active(SO.mission_of(_w(), t_res)), 10.0)
	pt._log("specops8_rescue_started", ok and String(SO.mission_of(_w(), t_res).get("kind", "")) == "rescue", SO.status_line(_w(), t_res))
	# ================================================== watch them work
	await _wait_phase(t_raid, ["air_fly"], 240.0)
	await pt._wait(2.0)
	await _shot_at(_team_pos(t_raid), "specops8_5_raid_flying")
	await _wait_phase(t_rec, ["scout"], 300.0)
	await pt._wait(6.0)
	await _shot_at(rp, "specops8_6_recon_scouting")
	await _wait_phase(t_raid, ["plant", "withdraw"], 300.0)
	await _shot_at(C + Vector2(34, 58), "specops8_7_raid_planting")
	await _wait_phase(t_esc, ["screen"], 300.0)
	await _shot_at(_team_pos(t_esc), "specops8_8_escort_screen")
	await _wait_phase(t_res, ["recover"], 300.0)
	await pt._wait(3.0)
	await _shot_at(resc, "specops8_9_rescue_recover")
	var all := [t_rec, t_raid, t_esc, t_res]
	ok = await pt._wait_until(func():
		for tid in all:
			if SO.active(SO.mission_of(_w(), int(tid))):
				return false
		return true, 600.0)
	mv.speed = 1.0
	w = _w()
	for tid in all:
		var M := SO.mission_of(w, int(tid))
		pt._log("specops8_%s_done" % String(M.get("kind", "?")), String(M.get("phase", "")) == "done", SO.status_line(w, int(tid)))
	var core = w.entities.get(core_id)
	pt._log("specops8_core_hit", core == null or float(core.hp) < core_hp0, "core hp %.0f -> %s" % [core_hp0, str(core.hp) if core != null else "destroyed"])
	pt._log("specops8_marks", SO.marks(w, fid).size() >= 1, "%d live recon marks" % SO.marks(w, fid).size())
	pt._log("specops8_rescued", int(SO.mission_of(w, t_res).get("saved", 0)) >= 3, "recovered %d" % int(SO.mission_of(w, t_res).get("saved", 0)))
	# ---- the ops room map with the recon marks (diamonds)
	if card != null and card.get("hub") != null:
		card.hub.open("map")
		await pt._wait(0.8)
		await pt._shot("specops8_10_map_marks")
		card.hub.close()
	await _shot_at(C + Vector2(0, 30), "specops8_11_home")
