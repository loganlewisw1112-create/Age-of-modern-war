extends "res://tests/test_base.gd"
## G7 acceptance (owner: OPSUI7). Master scope 6.11 (operations UI), 13.6 (command screens), 13.7 (PROTOCOL advisor),
## 13.1 (lore codex), 6.10 + 13.4 (team card). Every panel builds from a world with and without counter-nanite teams;
## tracker values match the sim; advisor lines fire on the right conditions and stay silent when off / muted; the
## codex lists collected files only; buttons submit the right commands; opening panels never changes the sim hash.

const CN = preload("res://sim/systems/counter_nanite.gd")
const CnOps7 = preload("res://sim/systems/cn_ops7.gd")
const CnProgress7 = preload("res://sim/systems/cn_progress7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const OpsData = preload("res://presentation/ui7/ops_data.gd")


func _ensure_g7() -> void:
	if not Content.rules().has("g7_cnops"):
		Content._merge_fragment_dir("res://content/g7")


## Inert 2-side world with a 60x60 GRASS arena; returns [w, arena origin] (same fixture as test_cnops7).
func _setup(sd: int = 0) -> Array:
	var w := make_world({} if sd == 0 else {"seed": sd})
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(60, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.grow(16).has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	w.factions[0].credits = 200000
	return [w, o]


func _step(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()
		if not SimWorld.SYSTEM_ORDER.has(CnOps7):
			CnOps7.tick(w)
			CnProgress7.tick(w)


func _team(w: SimWorld, pos: Vector2) -> Dictionary:
	var r := CN.spawn_team(w, 0, "strike_team", pos)
	return CN.team(w, int(r.team))


# ================================================================ data model
func test_data_without_and_with_teams() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var o: Vector2i = S[1]
	check(OpsData.team_ids(w, 0).is_empty(), "no counter-nanite team: empty team list")
	check(not OpsData.has_ops(w, 0), "no team, facility or Last Protocol: nothing to show")
	var h0 := w.state_hash()
	var t := _team(w, Vector2(o) + Vector2(20, 30))
	_step(w, 3)
	var h1 := w.state_hash()
	var row := OpsData.team_row(w, int(t.id))
	check(OpsData.has_ops(w, 0), "a team: the operations room has something to show")
	check(int(row.members) == (t.members as Array).size() and int(row.apcs) == 2, "row counts members %d and APCs %d" % [int(row.members), int(row.apcs)])
	check(String(row.grid) == OpsData.grid_ref(w, Vector2(row.pos)), "row grid ref matches its position")
	check(w.state_hash() == h1, "reading the team row leaves the state hash unchanged")
	check(h0 != h1, "(sanity) the world itself moved while stepping")
	check(OpsData.grid_ref(w, Vector2(0, 0)) == "A1" and OpsData.grid_ref(w, Vector2(w.map.w - 1, w.map.h - 1)) == "J10", "grid refs A1..J10")


# ================================================================ helpers for the panel tests
const OpsPanel = preload("res://presentation/ui7/ops_panel.gd")
const Advisor = preload("res://presentation/ui7/protocol_advisor.gd")
const Tracker = preload("res://presentation/ui7/deploy_tracker.gd")
const TeamCam = preload("res://presentation/ui7/team_cam.gd")
const Codex = preload("res://presentation/ui7/codex.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


class FakeMV extends Node:
	var world: SimWorld = null
	var player_fid := 0
	var centered := Vector2(-1, -1)
	var selected: Array = []
	var issued: Array = []

	func center_camera_on(p: Vector2) -> void:
		centered = p

	func select_ids(ids: Array) -> void:
		selected = ids.duplicate()

	func issue(c: Dictionary) -> Dictionary:
		c.issuer = player_fid
		issued.append(c)
		return {"ok": true}

	static func world_to_screen(p: Vector2) -> Vector2:
		return Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)


func _hub(w: SimWorld) -> Array:
	var mv := FakeMV.new()
	mv.world = w
	var hub = OpsPanel.new()
	hub.mv = mv
	hub._ready()
	return [hub, mv]


func _open_all(hub) -> void:
	for t in OpsPanel.TABS:
		hub.open(String(t[0]))
		hub.refresh()
		var p = hub.page(String(t[0]))
		if p != null and p.has_method("_draw"):
			pass


func _free(arr: Array) -> void:
	for n in arr:
		if n is Node and is_instance_valid(n):
			n.free()


func _enemy(w: SimWorld, pos: Vector2, def: String = "a_old_tank") -> int:
	var id := w.spawn_unit(def, 1, pos)
	var e: Dictionary = w.entities[id]
	e.order = {"type": "hold"}
	e.cd_ticks = 100000
	return id


# ================================================================ panels
func test_every_panel_builds_without_teams() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var H := _hub(w)
	var hub = H[0]
	var h0 := w.state_hash()
	_open_all(hub)
	check(hub._rows.get_child_count() == 1 and hub._rows.get_child(0) is Label, "teams page: one 'no teams' line")
	check(hub.page("deploy").deps.is_empty(), "tracker: no deployments")
	check(hub.page("codex").collected_ids.is_empty(), "codex: nothing collected outside Last Protocol")
	check(String(hub.page("cam").feed.source) == "none", "team cam: no feed without a team")
	check(w.state_hash() == h0, "opening every screen without teams leaves the state hash unchanged")
	_free([hub, H[1]])


func test_every_panel_builds_with_a_team_and_never_changes_the_hash() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var o: Vector2i = S[1]
	var t := _team(w, Vector2(o) + Vector2(20, 30))
	_step(w, 3)
	_enemy(w, Vector2(o) + Vector2(25, 30))
	_step(w, 2)
	var H := _hub(w)
	var hub = H[0]
	var adv = Advisor.new()
	adv.hub = hub
	adv._ready()
	adv.mode = "muted"
	var h0 := w.state_hash()
	for i in 3:
		_open_all(hub)
		adv.refresh()
		adv._last_tick = -1
	check(w.state_hash() == h0, "opening every screen + advisor scans x3 leaves the state hash unchanged")
	check(hub._rows.get_child_count() == 1, "teams page: one row per team (%d)" % hub._rows.get_child_count())
	check(String(hub.card._head.text).contains(String(t.name).to_upper()), "team card shows the team name (%s)" % hub.card._head.text)
	check(hub.card._members.get_child_count() == (t.members as Array).size(), "team card lists every operator (%d)" % hub.card._members.get_child_count())
	check(String(hub.page("cam").feed.source) in ["overwatch", "helmet"], "team cam follows the overwatch drone or a helmet")
	check(not (hub.page("map").layers.teams as Array).is_empty(), "strategic map shows the team")
	_free([adv, hub, H[1]])


func test_jump_to_centres_and_selects() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var o: Vector2i = S[1]
	var t := _team(w, Vector2(o) + Vector2(20, 30))
	_step(w, 3)
	var H := _hub(w)
	var hub = H[0]
	var mv: FakeMV = H[1]
	hub.open("teams")
	hub.refresh()
	var row: Control = hub._rows.get_child(0)
	var jb: Button = row.find_child("Jump", true, false)
	check(jb != null, "team row has a JUMP button")
	if jb != null:
		jb.pressed.emit()
	var r := OpsData.team_row(w, int(t.id))
	check(mv.centered.distance_to(Vector2(r.pos)) < 0.01, "JUMP centres the camera on the team (%s vs %s)" % [mv.centered, r.pos])
	check(mv.selected.size() == (r.ids as Array).size() and not mv.selected.is_empty(), "JUMP selects the team's units on the map")
	hub.open("map")
	hub.refresh()
	_free([hub, mv])


func test_tracker_values_match_the_sim() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var o: Vector2i = S[1]
	var t := _team(w, Vector2(o) + Vector2(20, 30))
	_step(w, 3)
	var site := Vector2(o) + Vector2(26, 30)
	CN.start_deploy(w, t, site, "purge")
	var d0 := OpsData.deployment(w, int(t.id))
	check(String(d0.phase_name) == "DISMOUNTING" and not bool(d0.dismounted), "before the dismount the tracker shows DISMOUNTING")
	var ok := false
	for i in 60:
		_step(w, 20)
		if t.dep == null:
			break
		if bool(t.dep.dis) and int(t.dep.prog) > 0:
			ok = true
			break
	check(ok, "the deployment reaches a phase with progress")
	if ok:
		var d := OpsData.deployment(w, int(t.id))
		var ph := String(t.dep.phase)
		var need := CN.need_ticks(w, t, ph)
		check(String(d.phase) == ph, "tracker phase %s == sim %s" % [d.phase, ph])
		check(absf(float(d.phase_frac) - float(t.dep.prog) / float(need)) < 0.0001, "tracker phase progress %.3f == sim %d/%d" % [float(d.phase_frac), int(t.dep.prog), need])
		var left := need - int(t.dep.prog)
		for p in range(OpsData.PHASES.find(ph) + 1, 3):
			left += CN.need_ticks(w, t, String(OpsData.PHASES[p]))
		check(absf(float(d.time_left_s) - float(left) / float(SimWorld.TICK_RATE)) < 0.001, "tracker time left %.2f s == sim remaining ticks %d" % [float(d.time_left_s), left])
		var L := Tracker.lines(d)
		check(String(L.time).begins_with("T-"), "tracker time line: %s" % L.time)
		check(bool(d.dome.has), "tracker reads the APC dome")


func test_advisor_fires_on_conditions_and_is_silent_when_off_or_muted() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var o: Vector2i = S[1]
	var t := _team(w, Vector2(o) + Vector2(10, 30))
	_step(w, 3)
	# 1) exposed nest
	Creep.enable(w)
	var nc := Vector2(o) + Vector2(40, 10)
	Creep.add_nest(w, nc, 5, 3.0, 1)
	Creep.reveal(w, nc, 8.0, 0)
	var memo := {}
	var out: Array = Advisor.scan(w, 0, memo)
	var nest_line := ""
	for l in out:
		if String(l.key).begins_with("nest:"):
			nest_line = String(l.text)
	check(nest_line == "Seed nest exposed at grid %s." % OpsData.grid_ref(w, nc), "exposed nest line: '%s'" % nest_line)
	check(Advisor.scan(w, 0, memo).filter(func(l): return String(l.key).begins_with("nest:")).is_empty(), "the same line does not repeat inside its cooldown")
	# 2) convoy route across packhunter territory (deploying team still mounted: route anchor -> site)
	var site := Vector2(o) + Vector2(30, 30)
	CN.start_deploy(w, t, site, "purge")
	_enemy(w, Vector2(o) + Vector2(16, 32), "g7_m_packhunter")
	_step(w, 2)
	var got_route := false
	for l in Advisor.scan(w, 0, memo):
		if String(l.key) == "route:%d" % int(t.id):
			got_route = String(l.text).begins_with("Convoy route crosses packhunter territory")
	check(got_route, "a visible packhunter near the route fires the packhunter-territory line")
	# 3) core plating crossing 60 %
	var bid := Cores.place(w, 1, Vector2i(o) + Vector2i(50, 50))
	Advisor.scan(w, 0, memo)
	w.entities[bid].hp = float(w.entities[bid].max_hp) * 0.55
	var core_line := ""
	for l in Advisor.scan(w, 0, memo):
		if String(l.key).begins_with("core:"):
			core_line = String(l.text)
	check(core_line == "Core 1 plating at 60%.", "core plating line: '%s'" % core_line)
	# 4) modes: off = nothing, muted = text without voice, on = voice
	var H := _hub(w)
	var hub = H[0]
	var adv = Advisor.new()
	adv.hub = hub
	adv._ready()
	var heard := []
	adv.advisory.connect(func(l): heard.append(l))
	adv.mode = "off"
	adv.refresh()
	check(adv.lines.is_empty() and heard.is_empty(), "OFF: no lines and no advisory signal")
	adv.mode = "muted"
	adv._last_tick = -1
	adv.memo = {}
	adv.refresh()
	check(not adv.lines.is_empty() and not heard.is_empty() and heard.all(func(l): return not bool(l.voice)), "MUTED: lines shown, every advisory has voice=false (silent)")
	adv.mode = "on"
	adv._last_tick = -1
	adv.memo = {}
	heard.clear()
	adv.refresh()
	check(not heard.is_empty() and heard.all(func(l): return bool(l.voice)), "ON: advisories carry voice=true for AUDIO7")
	_free([adv, hub, H[1]])


func test_buttons_submit_the_right_commands() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var o: Vector2i = S[1]
	var t := _team(w, Vector2(o) + Vector2(20, 30))
	_step(w, 3)
	var eid := _enemy(w, Vector2(o) + Vector2(24, 30))
	_step(w, 3)
	var H := _hub(w)
	var hub = H[0]
	var mv: FakeMV = H[1]
	hub.open("teams")
	hub.refresh()
	var card = hub.card
	check(card._targets.has(eid), "the card lists the enemy the team sees as a fire-support target")
	var fb: Button = card.fire_btns.artillery
	check(not fb.disabled, "artillery is available (%s)" % fb.tooltip_text)
	fb.pressed.emit()
	var c: Dictionary = mv.issued[-1] if not mv.issued.is_empty() else {}
	check(String(c.get("type", "")) == "cn_fire_support" and int(c.get("team_id", -1)) == int(t.id) and String(c.get("kind", "")) == "artillery" and int(c.get("target_id", -1)) == eid,
		"artillery submits cn_fire_support {team_id, kind, target_id}: %s" % str(c))
	check(CnOps7.fire_reason(w, c) == "", "the submitted fire-support command is valid for the sim")
	card.relief_btns.reload.pressed.emit()
	var r: Dictionary = mv.issued[-1]
	check(String(r.type) == "cn_relief" and String(r.kind) == "reload" and int(r.team_id) == int(t.id), "relief button submits cn_relief {team_id, kind}")
	check(card.relief_btns.reload.disabled and String(card.relief_btns.reload.tooltip_text).contains("facility"), "relief is disabled with the sim's reason without a facility")
	var n0: int = mv.issued.size()
	for k in card.spec_btns:
		(card.spec_btns[k] as Button).pressed.emit()
		break
	if not card.spec_btns.is_empty():
		var sp: Dictionary = mv.issued[-1]
		check(mv.issued.size() == n0 + 1 and String(sp.type) == "cn_specialize" and sp.has("unit_id") and String(sp.path) in ["lab", "workshop", "medical"], "upgrade button submits cn_specialize {unit_id, path}: %s" % str(sp))
	else:
		check(false, "the card offers at least one specialist upgrade button")
	_free([hub, mv])


func test_codex_lists_collected_files_only() -> void:
	var S := _setup()
	check(Codex.collected(S[0]).is_empty(), "no Last Protocol: no files")
	var w := SimWorld.new_match(LastProtocol.make_config(7, "industrial_heartland_m"))
	w.run_ticks(2)
	var got := Codex.collected(w)
	check(got == ["order"], "Last Protocol start: only the order file (%s)" % str(got))
	var h0 := w.state_hash()
	var H := _hub(w)
	var hub = H[0]
	hub.open("codex")
	hub.refresh()
	var cx = hub.page("codex")
	check(cx._list.item_count == 1 and String(cx._list.get_item_text(0)).contains("Order 0"), "codex lists exactly the collected file")
	check(w.state_hash() == h0, "opening the codex leaves the hash unchanged")
	(LastProtocol.st(w).secrets_found as Array).append("origin")
	hub.refresh()
	check(cx.collected_ids == ["order", "origin"] and cx._list.item_count == 2, "finding the origin secret adds its file (%s)" % str(cx.collected_ids))
	check(cx.open_file("origin") and String(cx._title.text).contains("ORIGIN"), "a collected file opens in the reader")
	check(not cx.open_file("core_3"), "an uncollected file cannot be opened")
	var cd := OpsData.lp_countdown(LastProtocol.hud(w))
	check(absf(float(cd.real_s) - float(LastProtocol.hud(w).cd_left) / float(LastProtocol.hud(w).cd_rate)) < 0.01 and String(cd.text).contains("real min"), "LP countdown also as projected real minutes: %s" % cd.text)
	_free([hub, H[1]])


func test_radio_lines_and_countdown_maths() -> void:
	var b := OpsPanel.radio_line({"type": "CnBark", "owner": 0, "team": 3, "call_sign": "Halcyon 1-2", "pers": "joker", "kind": "kill"}, 0)
	check(String(b.who) == "Halcyon 1-2" and String(b.text) != "" and int(b.team) == 3, "bark -> radio subtitle")
	check(OpsPanel.radio_line({"type": "CnBark", "owner": 1, "team": 3, "kind": "kill"}, 0).is_empty(), "the enemy's radio is not heard")
	var f := OpsPanel.radio_line({"type": "CnFireSupport", "owner": 0, "team": 3, "kind": "rockets", "eta": 12, "left": 1, "call_sign": "Halcyon 1-1"}, 0)
	check(String(f.text) == "Rockets on the way, ETA 12s. 1 call left.", "fire support subtitle: %s" % f.text)
	var cd := OpsData.lp_countdown({"cd_left": 9000.0, "cd_rate": 1.94})
	check(int(ceil(float(cd.real_min))) == 78 and String(cd.text).contains("~78 real min"), "9000 protocol-s at x1.94 = ~78 real minutes (%s)" % cd.text)
