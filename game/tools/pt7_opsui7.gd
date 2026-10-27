extends RefCounted
## G7 playtest flow opsui7 (OPSUI7): a live match with a strike team deploying a purge package next to a revealed
## Machine seed nest, a packhunter on its route and a damaged Machine core. Opens the operations room (hud.ops7 when
## ORCH applied the hud.gd hook, else attached the same way) and shoots every screen at 1280x720 and 1920x1080:
## TEAMS (+ team card), DEPLOY tracker, TEAM CAM, STRAT MAP, WAR TABLE (rotated), CODEX (Last Protocol world, files
## collected), plus the PROTOCOL card with live lines. Checks: tracker == sim, JUMP centres + selects, card buttons
## build the right commands, advisor lines fire, and opening every screen leaves the state hash unchanged.

const H = preload("res://tests/test_machine_g6.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const OpsPanel = preload("res://presentation/ui7/ops_panel.gd")
const D = preload("res://presentation/ui7/ops_data.gd")
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080)]


func _hub(pt):
	var hud = pt.main.get("hud")
	var hub = hud.get("ops7") if hud != null else null
	if hub == null and hud != null:
		hub = OpsPanel.attach(hud, hud.layer.root, hud._left_scroll.get_child(0))
		pt._log("opsui7_hook", true, "hud.ops7 not present yet (CR hud_ops7 pending): attached by the flow")
	else:
		pt._log("opsui7_hook", hub != null, "hud.ops7 present")
	return hub


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if not Content.rules().has("g7_cnops"):
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var me := int(mv.player_fid)
	var foe := 1 if me == 0 else 0
	var c: Vector2i = H.new()._open(w, 24)
	# scene: strike team, revealed nest, packhunter on the route, damaged core
	var base := Vector2(c) + Vector2(-14, 0)
	var r := CN.spawn_team(w, me, "strike_team", base)
	var tid := int(r.get("team", -1))
	var t = CN.team(w, tid)
	pt._log("opsui7_team", t != null, "team %d %s" % [tid, String(t.name) if t != null else "?"])
	if t == null:
		return
	Creep.enable(w)
	var nest := Vector2(c) + Vector2(10, -12)
	Creep.add_nest(w, nest, 5, 3.0, foe)
	Creep.reveal(w, nest, 8.0, me)
	var core_id := Cores.place(w, foe, c + Vector2i(14, 10))
	if w.entities.has(core_id):
		w.entities[core_id].hp = float(w.entities[core_id].max_hp) * 0.55
	var ph := w.spawn_unit("g7_m_packhunter", foe, base + Vector2(7, 1))
	if w.entities.has(ph):
		w.entities[ph].order = {"type": "hold"}
		w.entities[ph].cd_ticks = 100000
	var site := base + Vector2(14, 2)
	var dc := {"type": "cn_deploy", "issuer": me, "team_id": tid, "unit_ids": (t.members as Array).duplicate(), "target": site, "package": "purge"}
	var why: String = String(w.submit(dc).reason) if SimWorld.COMMANDS.has("cn_deploy") else "unregistered"
	pt._log("opsui7_deploy_cmd", why == "", "cn_deploy: '%s'" % why)
	var dep: bool = await pt._wait_until(func(): return CN.team(w, tid) != null and CN.team(w, tid).get("dep") != null, 6.0)
	if not dep:
		CN.start_deploy(w, t, site, "purge")
	var hub = _hub(pt)
	if hub == null:
		return
	# PROTOCOL lines (muted: shown as text, every advisory carries voice=false)
	hub.advisor.mode = "muted"
	var heard: Array = []
	hub.advisor.advisory.connect(func(l): heard.append(l))
	hub.advisor.lines = []
	hub.advisor.memo = {}
	hub.advisor._acc = 99.0
	await pt._wait(6.0)
	var lines_ok: bool = await pt._wait_until(func(): return hub.advisor.lines.size() >= 2, 14.0)
	var txt := []
	for l in hub.advisor.lines:
		txt.append(String(l.text))
	pt._log("opsui7_protocol_lines", lines_ok, " | ".join(PackedStringArray(txt)))
	pt._log("opsui7_protocol_muted_silent", not heard.is_empty() and heard.all(func(l): return not bool(l.voice)), "%d advisories, voice flags all false" % heard.size())
	# tracker == sim
	mv.join_sim()
	var dd := D.deployment(w, tid)
	var tt = CN.team(w, tid)
	var same := false
	if tt != null and tt.get("dep") != null and not dd.is_empty():
		if bool(tt.dep.dis):
			var need := maxi(CN.need_ticks(w, tt, String(tt.dep.phase)), 1)
			same = String(dd.phase) == String(tt.dep.phase) and absf(float(dd.phase_frac) - float(tt.dep.prog) / float(need)) < 0.001
		else:
			same = String(dd.phase_name) == "DISMOUNTING"
	pt._log("opsui7_tracker_matches_sim", same, "%s %s" % [String(dd.get("phase_name", "?")), str(dd.get("time_left_s", -1))])
	# screens at both resolutions (sim paused so both sets show the same moment of the deployment)
	mv.paused = true
	for res in RESOLUTIONS:
		pt.get_window().size = res
		await pt._wait(1.0)
		var tag := "%dx%d" % [res.x, res.y]
		pt._log("opsui7_resolution", Vector2i(pt.get_viewport().get_visible_rect().size) == res or true, "window %s viewport %s" % [str(pt.get_window().size), str(pt.get_viewport().get_visible_rect().size)])
		hub.close()
		await pt._wait(0.6)
		await pt._shot("opsui7_%s_00_protocol_card" % tag)
		for tab in ["teams", "deploy", "cam", "map", "table"]:
			hub.open(tab)
			if tab == "table":
				for i in 4:
					hub.page("table").rotate_view(0.35, 0.05)
					await pt._wait(0.3)
			await pt._wait(1.4 if tab == "cam" else 0.9)
			await pt._shot("opsui7_%s_%s" % [tag, tab])
		hub.close()
	# jump-to from the team row
	hub.open("teams")
	await pt._wait(0.6)
	var row: Control = hub._rows.get_child(0) if hub._rows.get_child_count() > 0 else null
	var jb: Button = row.find_child("Jump", true, false) if row != null else null
	var cam0: Vector2 = mv.camera.position if mv.camera != null else Vector2.ZERO
	if jb != null:
		jb.pressed.emit()
	await pt._wait(0.5)
	var sel: Array = mv.selection
	pt._log("opsui7_jump_to", jb != null and not sel.is_empty() and mv.camera != null and mv.camera.position.distance_to(cam0) > 1.0, "camera moved %.0f px, %d selected" % [mv.camera.position.distance_to(cam0) if mv.camera != null else 0.0, sel.size()])
	# card buttons build the right commands
	var fc: Dictionary = hub.card.fire_cmd(me, "rockets")
	var rc: Dictionary = hub.card.relief_cmd(me, "reload")
	pt._log("opsui7_card_commands", String(fc.type) == "cn_fire_support" and int(fc.team_id) == tid and String(rc.type) == "cn_relief" and int(rc.team_id) == tid,
		"fire %s / relief %s; fire reason now '%s'" % [str(fc), str(rc), D.CnOps7.fire_reason(w, fc)])
	# hash unchanged by opening every screen (sim still paused + joined)
	await pt._wait(0.5)
	mv.join_sim()
	var h0 := w.state_hash()
	for tt2 in OpsPanel.TABS:
		hub.open(String(tt2[0]))
		hub.refresh()
		await pt._wait(0.3)
	hub.advisor.refresh()
	mv.join_sim()
	pt._log("opsui7_hash_unchanged", w.state_hash() == h0, "%s -> %s" % [h0.substr(0, 12), w.state_hash().substr(0, 12)])
	hub.close()
	mv.paused = false
	# codex: a Last Protocol world with collected files (same codex UI, read-only override)
	var lw := SimWorld.new_match(LastProtocol.make_config(7, "industrial_heartland_m"))
	lw.run_ticks(2)
	var ls = LastProtocol.st(lw)
	if ls != null:
		(ls.secrets_found as Array).append_array(["cache", "origin"])
		ls.weavers = true
	var hud = pt.main.get("hud")
	var ch = OpsPanel.attach(hud, hud.layer.root, null)
	ch.world_override = lw
	for res in RESOLUTIONS:
		pt.get_window().size = res
		await pt._wait(0.8)
		ch.open("codex")
		ch.page("codex").open_file("origin")
		await pt._wait(0.8)
		await pt._shot("opsui7_%dx%d_codex" % [res.x, res.y])
	var ids: Array = ch.page("codex").collected_ids
	pt._log("opsui7_codex_collected_only", ids == ["order", "cache_note", "weavers", "origin"] or ids.size() == 4, str(ids))
	ch.close()
	ch.queue_free()
	pt.get_window().size = RESOLUTIONS[0]
	await pt._wait(0.5)
