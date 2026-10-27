extends RefCounted
## G7 playtest flow cnops7 (CNOPS7): a strike team outside its facility gets its overwatch drone; the drone spots an
## enemy and warns; the team leader calls fire support on it; a reload APC relief convoy drives from the facility
## gate to the team; the team card shows the named operators, call signs, personalities and signature skills.
## CNOPS7 commands go through w.submit when ORCH has registered them, else straight through validate/apply.
## Until ORCH puts CnOps7 / CnProgress7 in SYSTEM_ORDER this flow ticks them after every joined sim batch
## (logged as "fallback ticking"; the drone then flies at batch rate).

const H = preload("res://tests/test_machine_g6.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const CnOps7 = preload("res://sim/systems/cn_ops7.gd")
const CnProgress7 = preload("res://sim/systems/cn_progress7.gd")

var evs: Array = []
var _w: SimWorld = null


func _registered() -> bool:
	return SimWorld.SYSTEM_ORDER.has(CnOps7)


func _on_events(e: Array) -> void:
	if not _registered() and _w != null:   # fallback: the sim is joined while this signal runs
		var keep: Array = _w.events
		_w.events = e.duplicate()
		CnOps7.tick(_w)
		CnProgress7.tick(_w)
		var st = CnOps7.state(_w)   # batches of k ticks can skip the staggered spotting cadence: spot once per batch
		if st != null:
			for k in (st.drones as Dictionary).keys():
				var dr = _w.entities.get(int(st.drones[k].id))
				var tm = CN.team(_w, int(k))
				if dr != null and tm != null:
					CnOps7._spot(_w, st, tm, dr)
		var extra: Array = _w.events.slice(e.size())
		_w.events = keep
		e = e + extra
	for ev in e:
		var t := String(ev.get("type", ""))
		if t.begins_with("Cn") or t.begins_with("Strike"):
			evs.append(ev)


func _has(t: String) -> bool:
	for ev in evs:
		if String(ev.type) == t:
			return true
	return false


func _count(t: String) -> int:
	var n := 0
	for ev in evs:
		if String(ev.type) == t:
			n += 1
	return n


func _cmd(pt, sys, cmd: Dictionary) -> String:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	cmd.issuer = int(mv.player_fid)
	if SimWorld.COMMANDS.has(String(cmd.type)):
		return String(w.submit(cmd).reason)
	var why: String = sys.validate_command(w, cmd)
	if why == "":
		var n0: int = w.events.size()
		sys.apply_command(w, cmd)
		for ev in w.events.slice(n0):   # applied between steps: its events never reach world_events
			if String(ev.get("type", "")).begins_with("Cn"):
				evs.append(ev)
	return why


func _card_text(c: Dictionary) -> String:
	var s := "%s   level %d   XP %.0f   missions %d\n" % [c.name, int(c.level), float(c.xp), int(c.missions)]
	for m in c.members:
		s += "%-14s %-16s %-15s %-22s %s\n" % [m.cs, m.name, String(m.pers).replace("_", " "), m.skill_label, String(m.role)]
	return s


func _show_card(pt, c: Dictionary) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 50
	var panel := PanelContainer.new()
	panel.position = Vector2(330, 60)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.1, 0.94)
	sb.border_color = Color(0.85, 0.65, 0.2)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	var lab := Label.new()
	lab.text = _card_text(c)
	lab.add_theme_font_size_override("font_size", 13)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	lab.add_theme_font_override("font", mono)
	panel.add_child(lab)
	layer.add_child(panel)
	pt._mv().add_child(layer)
	return layer


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if not Content.rules().has("g7_cnops"):
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	_w = w
	var h = H.new()
	var me := int(mv.player_fid)
	var foe := 1 if me == 0 else 0
	var c: Vector2i = h._open(w, 18)
	w.factions[me].credits = int(w.factions[me].credits) + 100000
	mv.world_events.connect(_on_events)
	pt._log("cnops7_mode", true, "registered" if _registered() else "fallback ticking (CR world_cnops7 pending)")
	# 1. facility + strike team outside the gate: the overwatch drone launches from the drone bay
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(16, 16)
	w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): return _has("CnFacilityRaised"), 6.0)
	pt._log("cnops7_facility", raised)
	mv.join_sim()
	var base := Vector2(c) + Vector2(0.5, 24.5)
	var res: Dictionary = CN.spawn_team(w, me, "strike_team", base)
	var tid := int(res.get("team", -1))
	var t = CN.team(w, tid)
	var up: bool = await pt._wait_until(func(): return _has("CnOverwatchLaunched"), 8.0)
	mv.join_sim()
	var did := CnOps7.drone_of(w, tid)
	pt._log("cnops7_overwatch_launched", up and w.entities.has(did), "team %d drone %d" % [tid, did])
	mv.center_camera_on(base)
	await pt._wait(4.0)
	pt._shot("cnops7_overwatch_drone")
	await pt._wait(0.8)
	# 2. an enemy walks into view: the drone shares the sighting and warns
	mv.join_sim()
	var eid := w.spawn_unit("a_old_tank", foe, base + Vector2(13, -3))
	w.entities[eid].order = {"type": "hold"}
	w.entities[eid].cd_ticks = 100000
	w.entities[eid].hp = 6000.0
	w.entities[eid].max_hp = 6000.0
	var warned: bool = await pt._wait_until(func(): return _has("CnOverwatchWarning"), 30.0)
	mv.join_sim()
	var wt := -1
	for ev in evs:
		if String(ev.type) == "CnOverwatchWarning":
			wt = int(ev.target)
	pt._log("cnops7_overwatch_warning", warned and wt == eid, "target %d (enemy %d)" % [wt, eid])
	mv.center_camera_on(base + Vector2(7, -2))
	await pt._wait(0.5)
	pt._shot("cnops7_overwatch_warning")
	await pt._wait(0.8)
	# 3. the team leader calls fire support on the seen enemy
	var far := w.spawn_unit("a_old_tank", foe, base + Vector2(-40, 0))
	w.entities[far].order = {"type": "hold"}
	w.entities[far].cd_ticks = 100000
	mv.join_sim()   # the unseen target: checked through the command's own validation (a submit only reports it a tick later)
	var why_far := CnOps7.fire_reason(w, {"type": "cn_fire_support", "issuer": me, "team_id": tid, "kind": "artillery", "target_id": far})
	var why := _cmd(pt, CnOps7, {"type": "cn_fire_support", "team_id": tid, "kind": "artillery", "target_id": eid})
	var called: bool = await pt._wait_until(func(): return _has("CnFireSupport"), 4.0)
	pt._log("cnops7_fire_support_call", why == "" and called and why_far != "", "cmd '%s', unseen target refused: '%s'" % [why, why_far])
	mv.center_camera_on(base + Vector2(13, -3))
	var hit: bool = await pt._wait_until(func(): return _count("StrikeImpact") >= 2, 12.0)
	pt._shot("cnops7_fire_support_impact")
	await pt._wait(0.8)
	mv.join_sim()
	pt._log("cnops7_fire_support_impact", hit, "impacts %d, calls left %d" % [_count("StrikeImpact"), CnOps7.calls_left(w, tid)])
	# 4. a reload APC relief convoy from the facility gate to the team
	why = _cmd(pt, CnOps7, {"type": "cn_relief", "team_id": tid, "kind": "reload"})
	var sent: bool = await pt._wait_until(func(): return _has("CnReliefSent"), 4.0)
	pt._log("cnops7_relief_sent", why == "" and sent, "cmd '%s'" % why)
	mv.join_sim()
	var rid := -1
	for ev in evs:
		if String(ev.type) == "CnReliefSent":
			rid = int(ev.units[0])
	if w.entities.has(rid):
		mv.center_camera_on(Vector2(w.entities[rid].pos))
	await pt._wait(2.0)
	pt._shot("cnops7_relief_convoy")
	await pt._wait(0.8)
	var arrived: bool = await pt._wait_until(func(): return _has("CnReliefArrived") or _has("CnReliefLost"), 90.0)
	pt._log("cnops7_relief_arrived", arrived and _has("CnReliefArrived"), "lost" if _has("CnReliefLost") else "")
	mv.center_camera_on(base)
	await pt._wait(1.0)
	pt._shot("cnops7_relief_arrived")
	await pt._wait(0.8)
	# 5. the team card: named operators, call signs, personalities, signature skills
	mv.join_sim()
	var card := CnProgress7.team_card(w, tid)
	var ok_card := not card.is_empty() and (card.members as Array).size() == 20
	for m in card.get("members", []):
		if String(m.name) == "" or String(m.cs) == "" or String(m.skill) == "":
			ok_card = false
	pt._log("cnops7_team_card", ok_card, "%s, %d operators" % [card.get("name", "?"), (card.get("members", []) as Array).size()])
	var layer := _show_card(pt, card)
	await pt._wait(0.6)
	pt._shot("cnops7_team_card")
	await pt._wait(1.5)
	layer.queue_free()
	mv.world_events.disconnect(_on_events)
