extends RefCounted
## G7 playtest flow gate7 (GATE7, owner note 13.9c-26): the APC entry's blast doors, driven by the real sim gate
## (13.9c-22). A facility is raised; the test map's AI units near it harden the outer gate at once, so they are cleared
## (kept away for the flow): the gate stands down and opens (shot mid-travel), stands open (leaves parked in the bastion
## pockets, the wash visible through the opening); then one enemy rifleman close to the base hardens it again: shots while
## the leaves travel (closing), with the lock bars driving home, and sealed. Each step checks the frame entity_layer
## actually drew (FacGate7.dbg) against the sim state. Zoom 1.75 and 2.5.

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const FacDrive7 = preload("res://sim/systems/fac_drive7.gd")
const FacGate7 = preload("res://presentation/view/fac_gate7.gd")

var evs: Array = []


func _on_events(e: Array) -> void:
	for ev in e:
		if String(ev.get("type", "")).begins_with("Cn"):
			evs.append(ev)


func _has(t: String) -> int:
	var n := 0
	for ev in evs:
		if String(ev.type) == t:
			n += 1
	return n


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam != null and cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	elif cam != null:
		cam.zoom = Vector2(z, z)


func _shots(pt, mv, at: Vector2, name: String, zs := [[1.75, "z175"], [2.5, "z25"]]) -> void:
	for z in zs:
		mv.center_camera_on(at)
		_zoom(mv, float(z[0]))
		await pt._wait(0.25)
		pt._shot("gate7_%s_%s" % [name, z[1]])


## Removes hostile units within 34 tiles of the compound (the test map's AI) so the gate can stand down.
func _clear(w: SimWorld, F: Dictionary, me: int, keep: int) -> void:
	var r := CnFacility.compound_rect(F).grow(34.0)
	var n := 0
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if int(id) != keep and e.kind == "unit" and w.is_enemy(me, int(e.owner)) and r.has_point(Vector2(e.pos)):
			w.entities.erase(id)
			n += 1
	if n > 0:
		w.cache.erase("sim_index")


## Polls cond every 0.03 s (the heavy-travel and lock-bar windows last only a fraction of a second at 3x game speed).
func _until(pt, cond: Callable, timeout_sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) < timeout_sec * 1000.0:
		if cond.call():
			return true
		await pt._wait(0.03)
	return bool(cond.call())


func _frame(fid: int) -> String:
	return String(FacGate7.dbg.get("%d:o" % fid, "?"))


func _travel_k(fid: int) -> int:
	var f := _frame(fid)
	return int(f.substr(4)) if f.begins_with("_gm_") else -1


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var c: Vector2i = h._open(w, 18)
	mv.world_events.connect(_on_events)
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(16, 16)
	var fid := w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): return _has("CnFacilityRaised") > 0, 6.0)
	mv.join_sim()
	var F := CnFacility.fac(w, fid)
	pt._log("gate7_facility", raised and not F.is_empty())
	if not raised or F.is_empty():
		return
	var go: Rect2 = CnFacility.zone(F, "gate_outer")
	var gi: Rect2 = CnFacility.zone(F, "gate_inner")
	var at_o := go.get_center() + Vector2(0.5, -1.0)
	var at_i := gi.get_center() + Vector2(0.5, 0.5)
	mv.center_camera_on(at_o)
	_zoom(mv, 2.5)
	# 1. keep the AI away: the gate stands down and opens (shot while the leaves slide back)
	var keep := -1
	var t0 := Time.get_ticks_msec()
	var opening := false
	while Time.get_ticks_msec() - t0 < 60000:
		mv.join_sim()
		_clear(w, F, me, keep)
		var gs := FacDrive7.gate_state(w, fid)
		if gs == "opening" and _travel_k(fid) >= 5 and _travel_k(fid) <= 10:
			opening = true
			break
		if gs == "open":
			break
		await pt._wait(0.03)
	# (log-only here: the test map's AI can be cleared before the gate ever hardens, so there is no opening cycle to
	# catch at the start; the real opening-mid-travel check is step 3, where the cycle is guaranteed)
	pt._log("gate7_start_state_note", true, "sim %s, drawn %s, opening caught at start: %s" % [FacDrive7.gate_state(w, fid), _frame(fid), opening])
	if opening:
		pt._shot("gate7_outer_opening_start_z25")
	var open: bool = await pt._wait_until(func(): _clear(w, F, me, keep); return FacDrive7.gate_state(w, fid) == "open", 20.0)
	await pt._wait(0.3)
	mv.join_sim()
	_clear(w, F, me, keep)
	pt._log("gate7_open_drawn_open", open and _frame(fid) == "", "sim %s, drawn '%s' (open = no suffix)" % [FacDrive7.gate_state(w, fid), _frame(fid)])
	await _shots(pt, mv, at_o, "outer_open")
	await _shots(pt, mv, at_i, "inner_open", [[1.75, "z175"]])
	mv.join_sim()
	_clear(w, F, me, keep)
	# 2. one enemy near the base: the outer gate closes (leaves travel, lock bars drive home) and hardens
	var cr := CnFacility.compound_rect(F)
	var foe := -1
	for fk in w.factions:
		if w.is_enemy(me, int(fk)):
			foe = int(fk)
			break
	if foe >= 0:
		keep = w.spawn_unit("rifleman", foe, cr.end + Vector2(-14, 9))
		var ee: Dictionary = w.entities[keep]
		ee.order = {"type": "hold"}
		ee.cd_ticks = 100000
		ee.hp = 1.0e9
		ee.max_hp = 1.0e9
	mv.center_camera_on(at_o)
	_zoom(mv, 2.5)
	var mid: bool = await _until(pt, func(): mv.join_sim(); return FacDrive7.gate_state(w, fid) == "closing" and _travel_k(fid) >= 6 and _travel_k(fid) <= 11, 20.0)
	pt._log("gate7_closing_mid_travel", mid, "sim %s, drawn %s" % [FacDrive7.gate_state(w, fid), _frame(fid)])
	if mid:
		pt._shot("gate7_outer_closing_z25")
	var bars: bool = await _until(pt, func(): mv.join_sim(); return _frame(fid).begins_with("_gb_"), 10.0)
	pt._log("gate7_lock_bars_drawn", bars, "drawn %s while sim %s" % [_frame(fid), FacDrive7.gate_state(w, fid)])
	if bars:
		pt._shot("gate7_outer_bolting_z25")
	var hard: bool = await pt._wait_until(func(): return FacDrive7.gate_state(w, fid) == "hardened", 12.0)
	await pt._wait(0.3)
	pt._log("gate7_sealed_drawn_sealed", hard and _frame(fid) == "_lockdown", "sim %s, drawn %s" % [FacDrive7.gate_state(w, fid), _frame(fid)])
	await _shots(pt, mv, at_o, "outer_sealed")
	mv.join_sim()
	# 3. the enemy is gone and the AI kept away: the gate stands down (20 s) and opens: shot while the leaves slide back
	if keep >= 0 and w.entities.has(keep):
		w.entities.erase(keep)
		w.cache.erase("sim_index")
	keep = -1
	mv.center_camera_on(at_o)
	_zoom(mv, 2.5)
	var opn: bool = await _until(pt, func(): mv.join_sim(); _clear(w, F, me, keep); mv.center_camera_on(at_o); return FacDrive7.gate_state(w, fid) == "opening" and _travel_k(fid) >= 5 and _travel_k(fid) <= 10, 40.0)
	pt._log("gate7_opening_mid_travel", opn, "sim %s, drawn %s" % [FacDrive7.gate_state(w, fid), _frame(fid)])
	if opn:
		pt._shot("gate7_outer_opening_z25")
	var open2: bool = await pt._wait_until(func(): _clear(w, F, me, keep); return FacDrive7.gate_state(w, fid) == "open", 20.0)
	await pt._wait(0.3)
	mv.join_sim()
	_clear(w, F, me, keep)
	pt._log("gate7_reopened_drawn_open", open2 and _frame(fid) == "", "sim %s, drawn '%s' (open = no suffix)" % [FacDrive7.gate_state(w, fid), _frame(fid)])
	await _shots(pt, mv, at_o, "outer_reopened")
	await _inner_cycle(pt, mv, w, F, me, fid, cr, at_i, at_o)


func _cmd(pt, cmd: Dictionary) -> String:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	cmd.issuer = int(mv.player_fid)
	if SimWorld.COMMANDS.has(String(cmd.type)):
		var r: Dictionary = w.submit(cmd)
		return String(r.reason)
	var sys = FacDrive7 if String(cmd.type) == "fd7_go" else CnFacility
	var why: String = sys.validate_command(w, cmd)
	if why == "":
		sys.apply_command(w, cmd)
	return why


func _frame_i(fid: int) -> String:
	return String(FacGate7.dbg.get("%d:i" % fid, "?"))


func _travel_i(fid: int) -> int:
	var f := _frame_i(fid)
	return int(f.substr(4)) if f.begins_with("_gm_") else -1


## 4. The inner gate: the wash is a sally port, so with the outer gate hardened an APC sent out first makes the INNER gate
## close, then the outer opens for it, it passes, the outer closes and the inner opens again. A strike team's two APCs are
## trained, one enemy near the base hardens the outer gate, the APCs are sent out (no shooting), and the inner gate's drawn
## frame is shot closing, sealed (outer opening behind it), and opening again; each check compares the frame entity_layer
## drew (FacGate7.dbg) with the sim state.
func _inner_cycle(pt, mv, w: SimWorld, F: Dictionary, me: int, fid: int, cr: Rect2, at_i: Vector2, at_o: Vector2) -> void:
	var n0 := _has("CnTeamReady")
	_cmd(pt, {"type": "cn_train", "building_id": fid, "kind": "strike_team"})
	await pt._wait(0.3)
	mv.join_sim()
	if not (F.queue as Array).is_empty():
		F.queue[0].left = 2.0
	await pt._wait_until(func(): _clear(w, F, me, -1); return _has("CnTeamReady") > n0, 10.0)
	mv.join_sim()
	var apcs := []
	for ev in evs:
		if String(ev.type) == "CnTeamReady" and int(ev.get("fac", fid)) == fid:
			for a in CnFacility.team(w, int(ev.team)).get("apcs", []):
				if not apcs.has(int(a)):
					apcs.append(int(a))
	for id in apcs:   # no shooting in this flow
		if w.entities.has(id):
			w.entities[id].cd_ticks = 100000
	pt._log("gate7_apcs_ready", apcs.size() >= 2, "%d APCs" % apcs.size())
	if apcs.size() < 2:
		return
	await pt._wait(1.0)
	var foe := -1
	for fk in w.factions:
		if w.is_enemy(me, int(fk)):
			foe = int(fk)
			break
	var keep := -1
	if foe >= 0:
		keep = w.spawn_unit("rifleman", foe, cr.end + Vector2(-14, 9))
		var ee: Dictionary = w.entities[keep]
		ee.order = {"type": "hold"}
		ee.cd_ticks = 100000
		ee.hp = 1.0e9
		ee.max_hp = 1.0e9
	var hard: bool = await pt._wait_until(func(): _clear(w, F, me, keep); return FacDrive7.gate_state(w, fid) == "hardened", 20.0)
	pt._log("gate7_hardened_for_sally", hard, "outer %s" % FacDrive7.gate_state(w, fid))
	if not hard:
		return
	var o2 := Vector2(CnFacility.origin(F))
	var outp := Vector2(o2.x + 14.0, cr.end.y + 7.0)   # straight out of the gate mouth (clear apron); the APCs must leave the gate's keep-clear margin so it can close
	var why := _cmd(pt, {"type": "fd7_go", "ids": [apcs[0]], "to": "out", "target": outp})
	_cmd(pt, {"type": "fd7_go", "ids": [apcs[1]], "to": "out", "target": outp + Vector2(3.0, 2.0)})
	print("PLAYTEST-DBG gate7 fd7_go out reason '%s', APC states %s / %s" % [why, FacDrive7.vstate(w, apcs[0]).get("st", "-"), FacDrive7.vstate(w, apcs[1]).get("st", "-")])
	mv.center_camera_on(at_i)
	_zoom(mv, 2.5)
	var seen_close := false
	var seen_shut := false
	var seen_reopen := false
	var shot_close := false
	var shot_shut := false
	var shot_reopen := false
	var both_open := false
	var inner_drawn_ok := true
	var t0 := Time.get_ticks_msec()
	var dbg_t := 0
	var closed_since := -1
	var closed_judged := 0
	while Time.get_ticks_msec() - t0 < 120000:
		mv.join_sim()
		_clear(w, F, me, keep)
		var gv: Array = FacDrive7.gate_view(F)
		if Time.get_ticks_msec() - dbg_t > 4000:
			dbg_t = Time.get_ticks_msec()
			var V0 := FacDrive7.vstate(w, apcs[0])
			print("PLAYTEST-DBG gate7 sally gates %s GT %s apc0 %s at %s apc1 %s at %s clear o/i %s/%s foe %s" % [gv, F.get("gate", {}), V0.get("st", "-"), (Vector2(w.entities[apcs[0]].pos) - o2).snappedf(0.1), FacDrive7.vstate(w, apcs[1]).get("st", "-"), (Vector2(w.entities[apcs[1]].pos) - o2).snappedf(0.1), FacDrive7._gate_clear(w, F, "gate_outer"), FacDrive7._gate_clear(w, F, "gate_inner"), w.entities.has(keep)])
		var si := String(gv[1])
		var so := String(gv[0])
		if si != "closed":
			closed_since = -1
		if si == "open" and so == "open":
			both_open = true   # outer and inner must never be open together while hardened (sally port)
		if si == "closing":
			seen_close = true
			if not shot_close and _travel_i(fid) >= 6 and _travel_i(fid) <= 11:
				pt._shot("gate7_inner_closing_z25")
				shot_close = true
		elif si == "closed":
			seen_shut = true
			if closed_since < 0:
				closed_since = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - closed_since > 400:   # the drawn frame follows the sim by one refresh: judge a closed state that has held 0.4 s
				inner_drawn_ok = inner_drawn_ok and _frame_i(fid) == "_lockdown"
				closed_judged += 1
			if not shot_shut and so == "opening":
				pt._shot("gate7_inner_sealed_outer_opening_z25")
				mv.center_camera_on(at_o)
				await pt._wait(0.2)
				pt._shot("gate7_outer_opening_sally_z25")
				mv.center_camera_on(at_i)
				shot_shut = true
		elif si == "opening" and seen_shut:
			seen_reopen = true
			if not shot_reopen and _travel_i(fid) >= 5 and _travel_i(fid) <= 10:
				pt._shot("gate7_inner_opening_z25")
				shot_reopen = true
		if seen_reopen and shot_reopen and FacDrive7.vstate(w, apcs[0]).is_empty() and FacDrive7.vstate(w, apcs[1]).is_empty():
			break
		await pt._wait(0.05)
	mv.join_sim()
	pt._log("gate7_never_both_open", not both_open, "outer and inner open at once: %s" % both_open)
	pt._log("gate7_inner_closes_for_sally", seen_close and shot_close, "closing seen %s, shot %s" % [seen_close, shot_close])
	pt._log("gate7_inner_sealed_drawn_sealed", seen_shut and closed_judged > 0 and inner_drawn_ok, "closed seen %s, every closed sample that held 0.4 s (%d) drawn _lockdown: %s" % [seen_shut, closed_judged, inner_drawn_ok])
	pt._log("gate7_inner_reopens_after_sally", seen_reopen and shot_reopen, "reopening seen %s, shot %s, gates now %s" % [seen_reopen, shot_reopen, FacDrive7.gate_view(F)])
	await _shots(pt, mv, at_i, "inner_after_sally", [[1.75, "z175"]])
	if keep >= 0 and w.entities.has(keep):
		w.entities.erase(keep)
		w.cache.erase("sim_index")
