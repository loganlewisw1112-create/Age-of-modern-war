extends "res://tests/test_base.gd"
## G7 CNMISSION8 (master scope 13.9c-44): the one-click PURGE MISSION for counter-nanite strike teams. On the real
## Last Protocol start (map last_protocol, facility with 2 strike teams + the stealth dropship on its helipad):
## drive mode and fly mode run end to end and purge a creep area; a manual order cancels; save/load mid-mission
## gives the same future; the reason functions refuse what the sim refuses.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const M8 = preload("res://sim/systems/cn_mission8.gd")
const Creep = preload("res://sim/systems/creep.gd")

static var _base: Dictionary = {}


func _lp() -> SimWorld:
	if not preload("res://sim/map_gen.gd").has_map("last_protocol"):
		return null
	if _base.is_empty():
		var w0 := SimWorld.new_match(LastProtocol.make_config(77, "last_protocol"))
		if w0 == null:
			return null
		w0.run_ticks(25)
		_base = w0.to_dict().duplicate(true)
	var w := SimWorld.from_dict(_base.duplicate(true))
	w.ai_state = {}
	return w


func _fid(w: SimWorld) -> int:
	return int(w.sys_state.lp.fid)


func _strike(w: SimWorld) -> Dictionary:
	for tid in CN.team_ids(w):
		var t: Dictionary = CN.team(w, int(tid))
		if String(t.kind) == "strike" and int(t.fid) == _fid(w):
			return t
	return {}


## A creep patch near the base: paints creep over a radius-5 disc at a fixed open spot outside the walls (the LP
## start's own creep is far out; a test needs a site the team reaches in a few minutes). Returns the centre.
func _patch(w: SimWorld, off: Vector2) -> Vector2:
	var C := Vector2(w.map.lp.base.center)
	var p := C + off
	var s = Creep.enable(w)
	var c := w.cell_of(p)
	var v: PackedByteArray = s.v
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			if dx * dx + dy * dy <= 25:
				var q := c + Vector2i(dx, dy)
				if w.in_bounds(q):
					v[Creep._k(s, q)] = 200
	s.v = v
	var mf := -1
	for f in w.factions:
		if Creep.is_machine(w, int(f)):
			mf = int(f)
	Creep.add_nest(w, p, 5, 3.0, mf)
	return p


func _quiet(w: SimWorld) -> void:
	# no Machine pressure while the mission runs (the test is about the order flow, not the fight)
	w.cfg["creep_spread"] = false
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and w.is_enemy(_fid(w), int(e.owner)):
			e.cd_ticks = 1 << 30


func _submit(w: SimWorld, cmd: Dictionary) -> String:
	cmd.issuer = _fid(w)
	var why := w.preview_command(cmd)
	if why != "":
		return why
	var r := w.submit(cmd)
	return "" if r.ok else String(r.reason)


func _outside(w: SimWorld, p: Vector2) -> bool:
	var C := Vector2(w.map.lp.base.center)
	return maxf(absf(p.x - C.x), absf(p.y - C.y)) >= 31.0


func _end_to_end(mode: String, off: Vector2, limit: int) -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var t := _strike(w)
	var tid := int(t.id)
	var p := _patch(w, off)
	_quiet(w)
	check(M8.cover(w, p) > 0.5, "%s: a creep area at the target (%.2f)" % [mode, M8.cover(w, p)])
	check_eq(_submit(w, {"type": "cn_mission", "team_id": tid, "target": [p.x, p.y], "mode": mode}), "", "%s: PURGE MISSION accepted" % mode)
	var purged := false
	var purge_cover := 1.0
	var left := false
	var at_site := false
	var seen := []
	for i in limit:
		w.step()
		for ev in w.events:
			if String(ev.get("type", "")) == "CnMissionPurged" and int(ev.get("team", -1)) == tid:
				purged = true
				purge_cover = M8.cover(w, p)
		var M := M8.mission_of(w, tid)
		var ph := String(M.get("phase", ""))
		if seen.is_empty() or seen[-1] != ph:
			seen.append(ph)
			print("  [cnm8] %s t=%d %s  %s" % [mode, w.tick, ph, M8.status_line(w, tid)])
		if w.tick % 20 == 0:
			for aid in t.apcs:
				var a = w.entities.get(int(aid))
				if a != null and _outside(w, Vector2(a.pos)):
					left = true
				if a != null and Vector2(a.pos).distance_to(p) <= 9.0:
					at_site = true
		if not M.is_empty() and not M8.active(M):
			break
	var M := M8.mission_of(w, tid)
	print("  [cnm8] %s phases %s" % [mode, str(seen)])
	if mode == "drive":
		check(seen.has("exit") and seen.has("travel"), "drive: the team rolled out of the facility and travelled (%s)" % str(seen))
		check(left, "drive: an APC got outside the base walls")
	else:
		check(seen.has("air_board") and seen.has("air_fly") and seen.has("air_unload"), "fly: loaded, flew and unloaded (%s)" % str(seen))
	check(at_site, "%s: the strike APCs reached the site" % mode)
	check(seen.has("deploy"), "%s: deployed counter-nanites" % mode)
	check(purged, "%s: the area was purged (CnMissionPurged)" % mode)
	check(purge_cover <= M8.PURGE_FRAC, "%s: creep at the target when cleared %.2f <= %.2f" % [mode, purge_cover, M8.PURGE_FRAC])
	check_eq(String(M.get("phase", "")), "done", "%s: mission complete (note: %s)" % [mode, String(M.get("note", ""))])
	var T := M8.fac_team(w, tid)
	check_eq(String(T.get("phase", "")), "garage", "%s: the team is back in its garage" % mode)


func test_drive_mission_end_to_end() -> void:
	_end_to_end("drive", Vector2(0, 46), 9000)


func test_fly_mission_end_to_end() -> void:
	_end_to_end("fly", Vector2(46, 4), 12000)


func test_manual_order_cancels() -> void:
	var w := _lp()
	if w == null:
		return
	var t := _strike(w)
	var tid := int(t.id)
	var p := _patch(w, Vector2(0, 46))
	_quiet(w)
	_submit(w, {"type": "cn_mission", "team_id": tid, "target": [p.x, p.y], "mode": "drive"})
	w.run_ticks(60)
	check(M8.active(M8.mission_of(w, tid)), "mission running")
	_submit(w, {"type": "set_stance", "unit_ids": t.apcs.duplicate(), "stance": "defensive"})
	w.run_ticks(3)
	check(M8.active(M8.mission_of(w, tid)), "a stance change keeps the mission")
	var r := w.submit({"type": "move", "issuer": _fid(w), "unit_ids": [int(t.apcs[0])], "target": Vector2(w.map.lp.base.center)})
	check(r.ok, "move submitted")
	w.run_ticks(3)
	var M := M8.mission_of(w, tid)
	check_eq(String(M.get("phase", "")), "cancelled", "a player move order cancels the mission")
	check(String(M.get("note", "")).contains("move"), "the note names the order (%s)" % String(M.get("note", "")))
	check_eq(_submit(w, {"type": "cn_mission", "team_id": tid, "target": [p.x, p.y], "mode": "drive", "hold": true}), "", "re-tasked")
	w.run_ticks(3)
	check(M8.active(M8.mission_of(w, tid)) and bool(M8.mission_of(w, tid).hold), "new mission with hold")
	check_eq(_submit(w, {"type": "cn_mission_cancel", "team_id": tid}), "", "cancel accepted")
	w.run_ticks(3)
	check_eq(String(M8.mission_of(w, tid).phase), "cancelled", "Cancel mission ends it")
	check_eq(w.preview_command({"type": "cn_mission_cancel", "issuer": _fid(w), "team_id": tid}), "The team has no mission running.", "nothing to cancel now")


func test_save_load_mid_mission_same_future() -> void:
	var w := _lp()
	if w == null:
		return
	var t := _strike(w)
	var tid := int(t.id)
	var p := _patch(w, Vector2(0, 46))
	_quiet(w)
	_submit(w, {"type": "cn_mission", "team_id": tid, "target": [p.x, p.y], "mode": "drive"})
	w.run_ticks(400)
	var ph := String(M8.mission_of(w, tid).phase)
	check(M8.active(M8.mission_of(w, tid)), "mid-mission at the save (%s)" % ph)
	# the real save format (sim/save_system.gd): var_to_bytes. var_to_str is lossy for doubles (save_system.gd header)
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(w2.state_hash(), w.state_hash(), "loaded world has the same hash")
	check_eq(String(M8.mission_of(w2, tid).phase), ph, "mission phase survives the save")
	w.run_ticks(500)
	w2.run_ticks(500)
	check_eq(w2.state_hash(), w.state_hash(), "same future after save/load (500 ticks)")
	check_eq(String(M8.mission_of(w2, tid).phase), String(M8.mission_of(w, tid).phase), "same mission phase after 500 ticks")


func test_same_seed_same_hash_and_untouched_match() -> void:
	var hs := []
	for k in 2:
		var w := _lp()
		if w == null:
			return
		var t := _strike(w)
		var p := _patch(w, Vector2(0, 46))
		_quiet(w)
		_submit(w, {"type": "cn_mission", "team_id": int(t.id), "target": [p.x, p.y], "mode": "fly"})
		w.run_ticks(300)
		hs.append(w.state_hash())
	check_eq(hs[0], hs[1], "same seed, same mission: same hash")
	var w3 := make_world()
	w3.run_ticks(30)
	check(not w3.sys_state.has(M8.KEY), "a match that never issues cn_mission has no mission state")


func test_reasons_match_the_sim() -> void:
	var w := _lp()
	if w == null:
		return
	var fid := _fid(w)
	var t := _strike(w)
	var tid := int(t.id)
	var C := Vector2(w.map.lp.base.center)
	var p := _patch(w, Vector2(0, 46))
	var clean := C + Vector2(-20, -20)
	check_eq(M8.team_reason(w, fid, tid), "", "a strike team in its garage can take a mission")
	check_eq(M8.mission_reason(w, fid, tid, clean, "drive"), "No creep or core there to purge.", "clean ground refused")
	check_eq(M8.mission_reason(w, fid, tid, p, "walk"), "Pick Drive or Fly.", "unknown mode refused")
	check_eq(M8.mission_reason(w, fid, tid, p, "fly"), "", "fly ok: the stealth dropship sits on its helipad")
	var other := -1
	for f in w.factions:
		if int(f) != fid:
			other = int(f)
	check_eq(M8.mission_reason(w, other, tid, p, "drive"), "Not your team.", "not your team")
	var tac := -1
	for k in CN.team_ids(w):
		if String(CN.team(w, int(k)).kind) == "tactical" and int(CN.team(w, int(k)).fid) == fid:
			tac = int(k)
	check(M8.team_reason(w, fid, tac).begins_with("Only a strike team"), "an operator squad is refused (%s)" % M8.team_reason(w, fid, tac))
	for tg in [p, clean]:
		var c := {"type": "cn_mission", "issuer": fid, "team_id": tid, "target": [tg.x, tg.y], "mode": "drive"}
		check_eq(w.preview_command(c), M8.mission_reason(w, fid, tid, tg, "drive"), "preview == reason at %s" % str(tg))
	check_eq(M8.step_reason(w, fid, tid, "mount"), "Everyone is already aboard.", "Mount disabled: all aboard")
	check_eq(M8.step_reason(w, fid, tid, "dismount"), "", "Dismount enabled: crews aboard")
	check_eq(M8.extract_reason(w, fid, tid), "The team is in its garage.", "Extract disabled in the garage")
	check_eq(w.preview_command({"type": "cn_hero_detonate", "issuer": fid, "team_id": tid, "unit_id": -1}), "No package is being deployed.", "Hero detonate disabled without a deployment")
	for fk in CnFacility.facilities(w, fid):
		var F := CnFacility.fac(w, int(fk))
		var ds = w.entities.get(int(F.heli))
		if ds != null:
			ds.air_landed = false
	if M8.dropship(w, fid, C).is_empty():
		check(M8.mission_reason(w, fid, tid, p, "fly").begins_with("No dropship ready"), "Fly refused with no landed dropship")
	for aid in t.apcs:
		CN.find(w, int(aid)).a7.pk = []
	check(M8.team_reason(w, fid, tid).begins_with("No packages loaded"), "no packages: refused")
	check_eq(w.preview_command({"type": "cn_mission", "issuer": fid, "team_id": tid, "target": [p.x, p.y], "mode": "drive"}), M8.team_reason(w, fid, tid), "the sim refuses the same")


## The command bar: a strike team's card gets PURGE MISSION + Team orders; each CNMISSION8 button's disabled state
## and tooltip come from the sim reason functions (headless: a stub hud around the real g2_commands module).
class StubHud:
	extends RefCounted
	var w: SimWorld
	var fid := 0
	var issued: Array = []
	var _card_buttons: Array = []
	var _card_title := Label.new()
	var _card_sig := ""
	var mv = null
	func _world():
		return w
	func _pf() -> int:
		return fid
	func _card_button(title: String, sub: String, _k: String, _x: String) -> Button:
		var b := Button.new()
		b.text = title + "\n" + sub
		return b
	func _register_hotkey(_k, _b) -> void:
		pass
	func _issue(c: Dictionary) -> void:
		issued.append(c)
	func _refresh() -> void:
		pass


func test_command_bar_buttons_and_reasons() -> void:
	var w := _lp()
	if w == null:
		return
	var t := _strike(w)
	var hud := StubHud.new()
	hud.w = w
	hud.fid = _fid(w)
	var cmds = load("res://presentation/hud/g2_commands.gd").new()
	cmds.hud = hud
	cmds._ids = [int(t.apcs[0])]
	cmds._add_cn_buttons()
	var kinds := {}
	for rec in cmds._recs:
		kinds[String(rec.g2)] = rec
	check(kinds.has("cn8_purge") and kinds.has("cn8_team"), "PURGE MISSION and Team orders on the strike APC card (%s)" % str(kinds.keys()))
	cmds.update_state(w)
	check(not (kinds.cn8_purge.btn as Button).disabled, "PURGE MISSION enabled for a ready team")
	cmds.page = "cn8_team"
	cmds._page_ids = cmds._ids.duplicate()
	check(cmds.add_page(cmds._ids.duplicate()), "Team orders page builds")
	cmds.update_state(w)
	var by := {}
	for rec in cmds._recs:
		by[String(rec.g2)] = rec
	for k in ["cn8_mount", "cn8_move", "cn8_dismount", "cn8_deploy", "cn8_hero", "cn8_loadout", "cn8_extract", "cn8_cancel", "cn8_hold"]:
		check(by.has(k), "step button %s on the page" % k)
	check((by.cn8_mount.btn as Button).disabled and String(by.cn8_mount.btn.tooltip_text).contains("Everyone is already aboard."), "Mount disabled with the reason as tooltip")
	check((by.cn8_hero.btn as Button).disabled and String(by.cn8_hero.btn.tooltip_text).contains("No package is being deployed."), "Hero detonate disabled with the reason")
	check((by.cn8_cancel.btn as Button).disabled and String(by.cn8_cancel.btn.tooltip_text).contains("no mission"), "Cancel disabled: no mission")
	check(not (by.cn8_dismount.btn as Button).disabled, "Dismount enabled")
	# the purge flow: a creep click opens Drive / Fly, which submit cn_mission
	var p := _patch(w, Vector2(0, 46))
	cmds.page = ""
	cmds._recs.clear()
	cmds._cn_teams = {int(t.id): [int(t.apcs[0])]}
	cmds._cn8_target = p
	cmds.page = "cn8_purge"
	check(cmds.add_page(cmds._ids.duplicate()), "Drive / Fly page builds")
	cmds.update_state(w)
	var pp := {}
	for rec in cmds._recs:
		pp[String(rec.g2)] = rec
	check(not (pp.cn8_drive.btn as Button).disabled and not (pp.cn8_fly.btn as Button).disabled, "Drive and Fly enabled on creep")
	cmds.cn8_issue("drive")
	check(not hud.issued.is_empty() and String(hud.issued[-1].type) == "cn_mission" and String(hud.issued[-1].mode) == "drive", "Drive submits cn_mission (%s)" % str(hud.issued))
	cmds._cn8_target = Vector2(w.map.lp.base.center) + Vector2(-20, -20)
	cmds.update_state(w)
	check((pp.cn8_drive.btn as Button).disabled and String(pp.cn8_drive.btn.tooltip_text).contains("No creep or core there to purge."), "Drive disabled on clean ground with the reason")
	for rec in cmds._recs:
		rec.btn.free()
