extends RefCounted
## G3a victory / score panel (owner: UI3). Contract: docs/CONTRACTS_G3a.md sections 4 + 6.
## Per-team progress for the active victory terms (territory %, hold-bridge timer, HQs left),
## read from Victory.progress(w, team) (V3). Also builds the end screen's team result rows.
## Pure read: never mutates the world.

const HT = preload("res://presentation/hud/hud_theme.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")
const Victory = preload("res://sim/systems/victory.gd")
const VictoryBuilder = preload("res://presentation/menu/victory_builder.gd")

var panel: PanelContainer
var _title: Label
var _body: VBoxContainer
var _obj_panel: Control
var _sig := ""
var _acc := 0
var _last_rows_ms: int = -1000


func build(root: Control, obj_panel: Control) -> void:
	_obj_panel = obj_panel
	panel = PanelContainer.new()
	panel.name = "VictoryPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -320
	panel.offset_right = -14
	panel.offset_top = 46
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate = Color(1, 1, 1, 0.93)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	panel.add_child(v)
	_title = HT.make_label("VICTORY", HT.AMBER, 14)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 1)
	v.add_child(_body)


## Number of HQ buildings (built or not) per team.
static func hqs_per_team(w: SimWorld) -> Dictionary:
	var out := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building" and w.factions.has(int(e.owner)) and bool(Content.building(String(e.def)).get("is_hq", false)):
			var t := G3.team_of(w, int(e.owner))
			out[t] = int(out.get(t, 0)) + 1
	return out


static func team_label(w: SimWorld, team: int, pf: int) -> String:
	var names: Array = []
	for f in G3.teams(w).get(team, []):
		names.append("You" if int(f) == pf else String(w.factions[f].name))
	return "Team %d: %s" % [team + 1, ", ".join(names)]


## Rows for the HUD panel and the end screen: [{text, color, size}] (pure; testable headless).
static func rows(w: SimWorld, pf: int) -> Array:
	var out: Array = []
	var hqs := hqs_per_team(w)
	var my_team := G3.team_of(w, pf)
	var tdict := G3.teams(w)
	var keys: Array = tdict.keys()
	keys.sort()
	for team in keys:
		var fids: Array = tdict[team]
		var col: Color = G3.side_color(w, int(fids[0]))
		var prog: Dictionary = Victory.progress(w, int(team))
		var alive: bool = bool(prog.get("team_alive", int(hqs.get(team, 0)) > 0))
		var head := team_label(w, int(team), pf) + ("  (you)" if int(team) == my_team and fids.size() > 1 else "")
		if not alive:
			head += "  ELIMINATED"
		out.append({"text": head, "color": col.lightened(0.2) if alive else HT.DIM, "size": 13})
		var hq_txt := "    HQs left: %d" % int(hqs.get(team, 0))
		out.append({"text": hq_txt, "color": HT.TEXT if alive else HT.DIM, "size": 12})
		for t in prog.get("terms", []):
			out.append({"text": "    " + _term_line(t), "color": HT.GREEN if bool(t.get("satisfied", false)) else HT.TEXT, "size": 12})
	return out


static func _term_line(t: Dictionary) -> String:
	var mark := "[x] " if bool(t.get("satisfied", false)) else "[ ] "
	match String(t.get("type", "")):
		"territory":
			return mark + "Territory %d%% / %d%%" % [int(floor(float(t.get("value", 0.0)))), int(t.get("target", 0))]
		"hold_bridge":
			var extra := ""
			if bool(t.get("contested", false)):
				extra = "  (held by another team)"
			elif String(t.get("bridge_state", "")) == "ruined":
				extra = "  (bridge ruined)"
			return mark + "Bridge held %ds / %ds%s" % [int(t.get("value", 0)), int(t.get("target", 0)), extra]
		"hq_elimination":
			return mark + "Enemy teams left: %d" % int(t.get("value", 0))
	return mark + String(t.get("label", t.get("type", "?")))


func update(w: SimWorld, pf: int) -> void:
	if panel == null or w == null:
		return
	if _obj_panel != null and _obj_panel.visible:
		panel.offset_top = _obj_panel.position.y + _obj_panel.size.y + 8.0
	else:
		panel.offset_top = 46
	_acc += 1
	if _acc % 2 == 1 and _sig != "":
		return
	# Perf (UI4-2): rows() scans every entity (HQ count + Victory.progress); on big worlds do it at most 2 Hz.
	var now_ms := Time.get_ticks_msec()
	if _sig != "" and w.entities.size() > 400 and now_ms - _last_rows_ms < 500:
		return
	_last_rows_ms = now_ms
	var op := ""
	if String(w.cfg.get("victory", "")) == "combined":
		op = "  (all terms)" if String(w.cfg.get("victory_rules", {}).get("op", "and")) == "and" else "  (any term)"
	_title.text = "VICTORY: %s%s" % [VictoryBuilder.describe(w.cfg), op]
	var rs := rows(w, pf)
	var sig := str(rs.size())
	if sig != _sig:
		_sig = sig
		for c in _body.get_children():
			_body.remove_child(c)
			c.queue_free()
		for r in rs:
			_body.add_child(HT.make_label("", HT.TEXT, int(r.size)))
	for i in rs.size():
		var l: Label = _body.get_child(i)
		l.text = String(rs[i].text)
		l.add_theme_color_override("font_color", rs[i].color)


## End-screen data: subtitle + team rows (winner first).
static func end_info(w: SimWorld, pf: int) -> Dictionary:
	var ms: Dictionary = w.match_state
	var wt := int(ms.get("winner_team", G3.team_of(w, int(ms.get("winner", -1)))))
	var my_team := G3.team_of(w, pf)
	var won := wt >= 0 and wt == my_team
	var reason := String(ms.get("reason", ""))
	var sub := "The match has ended."
	match reason:
		"hq_elimination":
			sub = "Every enemy HQ has fallen." if won else "Your team's HQs have been destroyed."
		"territory":
			sub = "Your team controls the map." if won else "Team %d took control of the map." % (wt + 1)
		"hold_bridge":
			sub = "Your team held the bridge." if won else "Team %d held the bridge." % (wt + 1)
		"combined":
			sub = "Your team met the victory conditions." if won else "Team %d met the victory conditions." % (wt + 1)
	var lines: Array = []
	var tdict := G3.teams(w)
	var keys: Array = tdict.keys()
	keys.sort()
	if wt >= 0 and keys.has(wt):
		keys.erase(wt)
		keys.push_front(wt)
	var hqs := hqs_per_team(w)
	for team in keys:
		var kills := 0
		var lost := 0
		for f in tdict[team]:
			kills += int(w.factions[f].stats.get("killed", 0))
			lost += int(w.factions[f].stats.get("lost", 0))
		# No winner yet (debug end screen, or watching on): report who is still standing.
		var res := "WINNER" if int(team) == wt else ("defeated" if wt >= 0 or int(hqs.get(team, 0)) == 0 else "in play")
		lines.append({"text": "%s   %s   kills %d, lost %d" % [team_label(w, int(team), pf), res, kills, lost],
			"color": HT.GREEN if int(team) == wt else HT.DIM})
	return {"won": won, "subtitle": sub, "teams": lines, "winner_team": wt}
