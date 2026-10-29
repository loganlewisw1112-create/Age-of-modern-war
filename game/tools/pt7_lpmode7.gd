extends RefCounted
## G7 LPMODE7 playtest: start a Last Protocol run (the last_protocol map when registered, else lp_test512), check the
## HUD meters, force a breach of the outer ring (Machine walkers dropped between the outer and economy walls) and watch
## the defenders fall back and the economy gates seal, bring the countdown to its final stage so THE TIDE starts, then
## end the run by the win rule (cores finished, creep pushed under the line) and shoot the end-of-run panel.
## The flow writes the sim only between steps (match_view.join_sim) and says what it forces. Records of this flow go to
## user://pt7_lp_records.json (never the player's own record file).

const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const MapGen = preload("res://sim/map_gen.gd")
const LpHud = preload("res://presentation/ui7/lp_hud.gd")
const REC := "user://pt7_lp_records.json"


func _hud_panel(pt) -> Control:
	var n = pt.get_tree().root.find_child("LpHud", true, false)
	return n as Control


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	var t0 := Time.get_ticks_msec()
	var started: bool = pt.main.start_match(LP.make_config(77, map))
	pt._log("lpmode7_match_started", started, "map %s, start_match %d ms" % [map, Time.get_ticks_msec() - t0])
	if not started:
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 60.0)
	mv.join_sim()
	var w: SimWorld = pt._w()
	pt._log("lpmode7_setup", ok, "setup + facility fill seen at tick %d (%d ms after start)" % [w.tick, Time.get_ticks_msec() - t0])
	if not ok:
		return
	var s: Dictionary = w.sys_state.lp
	var wall0 := Time.get_ticks_msec()
	# 13.9c-36 authority record (owner: "TOO mf big ... shrink it down drastically"): two rings (was 3)
	pt._log("lpmode7_start_state", (s.base.rings as Array).size() == 2 and (Cores.list(w) as Array).size() == 3 and int(s.army_n) >= 80,
		"rings %d cores %d army %d teams %d creep %.3f from_map %s" % [(s.base.rings as Array).size(), (Cores.list(w) as Array).size(),
		int(s.army_n), int(s.teams_total), Creep.coverage(w), str(String(w.map.get("id", "")) == "last_protocol")])
	# the whole map explored for the player so the shots show ground (flows may write the sim)
	var ex: PackedByteArray = w.fog[0].explored
	ex.fill(1)
	w.fog[0].explored = ex
	var hp := _hud_panel(pt)
	pt._log("lpmode7_hud_hook", true, "ORCH hud.gd hook %s" % ("present" if hp != null else "not applied yet (CR change_request.lp_hud_hook): the flow attaches the panel itself"))
	if hp == null:
		hp = LpHud.attach(pt.main.hud._left_scroll.get_child(0), mv, pt.main.hud.layer.root)
	hp.set("records_path", REC)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REC))
	await pt._wait_until(func(): return pt._w().sys_state.lp.has("pop_floor"), 20.0)  # set the tick after the fill
	mv.join_sim()
	var fs: Dictionary = w.factions[int(s.fid)]
	pt._log("lpmode7_power_pop", int(fs.power_prod) >= int(fs.power_use) and int(fs.get("pop_cap_floor", 0)) >= int(fs.pop),
		"PWR %d/%d, POP %d, cap %d (floor %d; Economy honours the floor once ORCH applies CR economy.pop_cap_floor)" % [int(fs.power_use), int(fs.power_prod), int(fs.pop), int(fs.pop_cap), int(fs.get("pop_cap_floor", 0))])
	var obp = pt.get_tree().root.find_child("ObjectivesPanel", true, false)
	var vcp = pt.get_tree().root.find_child("VictoryPanel", true, false)
	var hidden0: bool = (obp == null or not obp.visible) and (vcp == null or not vcp.visible)
	if not hidden0:
		LpHud.hide_skirmish_cards(pt.main.hud)
	await pt._wait(0.3)
	var hidden1: bool = (obp == null or not obp.is_visible_in_tree()) and (vcp == null or not vcp.is_visible_in_tree())
	pt._log("lpmode7_skirmish_cards_hidden", hidden1, "objectives + victory cards hidden (%s)" % ("ORCH hud.gd hook present" if hidden0 else "hook not applied yet (CR change_request.lp_skirmish_cards): the flow called LpHud.hide_skirmish_cards"))
	var C := Vector2(s.base.center) + Vector2(0.5, 0.5)
	mv.center_camera_on(C)
	await pt._wait(1.5)
	var txt := LpHud.lines(LP.hud(w))
	pt._log("lpmode7_hud_meters", hp.visible and String(txt.get("countdown", "")).begins_with("PROTOCOL"), "%s | %s | %s" % [txt.get("title", ""), txt.get("creep", ""), txt.get("countdown", "")])
	await pt._shot("lpmode7_start")
	# ---- breach + fallback: Machine walkers between the outer and the economy wall (west side)
	mv.join_sim()
	var r0: Rect2i = s.base.rings[0].rect
	var r1: Rect2i = s.base.rings[1].rect
	var p := Vector2((r0.position.x + r1.position.x) / 2, r0.get_center().y) + Vector2(0.5, 0.5)
	for i in 10:
		w.spawn_unit("m_walker", int(s.mfid), p + Vector2(float(i % 2), float(i / 2) - 2.0))
	mv.center_camera_on(p + Vector2(4, 0))
	var br: bool = await pt._wait_until(func(): return bool(pt._w().sys_state.lp.base.rings[0].fallen), 45.0)
	mv.join_sim()
	var locked := 0
	for g in s.base.rings[1].gates:
		var gb = w.entities.get(int(g))
		if gb != null and bool(gb.get("locked", false)):
			locked += 1
	var outer := 0
	for e in w.units_of(int(s.fid)):
		if e.has("lp_ring") and int(e.lp_ring) == 0:
			outer += 1
	pt._log("lpmode7_breach_fallback", br and locked > 0 and locked == (s.base.rings[1].gates as Array).size() and outer == 0,
		"outer ring fallen %s, economy gates locked %d/%d, units still homed on the outer ring %d" % [str(br), locked, (s.base.rings[1].gates as Array).size(), outer])
	await pt._wait(2.0)
	await pt._shot("lpmode7_breach")
	# ---- THE TIDE: the countdown forced to its final stage (the flow sets cd_left; the rules do the rest)
	mv.join_sim()
	s.cd_left = 0.1 * float(s.cd_total)
	var td: bool = await pt._wait_until(func(): return bool(pt._w().sys_state.lp.tide), 20.0)
	mv.join_sim()
	txt = LpHud.lines(LP.hud(w))
	pt._log("lpmode7_tide", td and String(s.posture) == "maximum" and Cores.phase(w) == 4 and String(txt.flags).contains("THE TIDE"),
		"tide %s posture %s phase %d hud flags '%s'" % [str(td), String(s.posture), Cores.phase(w), txt.flags])
	mv.center_camera_on(C)
	await pt._wait(2.0)
	await pt._shot("lpmode7_tide")
	# ---- an ending by the win rule: the flow finishes the 3 cores and pushes the creep under the line
	mv.join_sim()
	s.cd_left = 0.5 * float(s.cd_total)  # keep the countdown from ending the run first
	for c in Cores.list(w):
		Cores.finish(w, int(c.ix), int(s.fid))
	var cs = Creep.st(w)
	cs.on_n = int(float(cs.land) * 0.05)
	var en: bool = await pt._wait_until(func(): return bool(pt._w().sys_state.lp.ended), 20.0)
	mv.join_sim()
	var res: Dictionary = s.get("result", {})
	# time_s is sim time since setup (ticks x DT); the wall clock since setup is shown next to it (the sim on a 512 map
	# can run slower than real time while the flow waits in wall-clock seconds)
	var sim_s := float(w.tick - int(s.t0)) * SimWorld.DT
	pt._log("lpmode7_ending", en and bool(res.get("won", false)) and int(res.get("cores_destroyed", 0)) == 3 and absf(float(res.get("time_s", -1.0)) - sim_s) < 1.0,
		"ending %s won %s time %.1f s (= %d ticks x %.2f s; wall %.1f s since setup) score %d medal '%s' remembered %d" % [String(res.get("ending", "")), str(res.get("won", false)),
		float(res.get("time_s", 0.0)), w.tick - int(s.t0), SimWorld.DT, float(Time.get_ticks_msec() - wall0) / 1000.0, int(res.get("score", 0)), String(res.get("medal", "")), (res.get("remembered", []) as Array).size()])
	await pt._wait(1.5)
	var endp = pt.get_tree().root.find_child("LpEnd", true, false)
	pt._log("lpmode7_end_panel", endp != null and (endp as Control).is_visible_in_tree(), "end-of-run panel %s" % ("shown" if endp != null else "missing"))
	pt._log("lpmode7_records_saved", FileAccess.file_exists(REC), REC)
	await pt._shot("lpmode7_ending")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REC))
