extends RefCounted
## G2 inspector additions (owner: agent D2): ammo/fuel bars, MOB/WPN/SEN chips, status tags,
## and the officer group card (mission, phase, reason, progress, last 3 reports).
## Read-only; built into the G1 HUD by hud.gd.

const HT = preload("res://presentation/hud/hud_theme.gd")
const G2 = preload("res://presentation/view/g2_data.gd")

var row_bars: HBoxContainer
var ammo_lbl: Label
var ammo_bar: ProgressBar
var fuel_lbl: Label
var fuel_bar: ProgressBar
var row_chips: HBoxContainer
var chips: Dictionary = {}      # comp key -> Label
var tag_labels: Array = []      # pooled Labels
var form_lbl: Label
var group_panel: PanelContainer
var g_title: Label
var g_phase: Label
var g_prog: ProgressBar
var g_reason: Label
var g_hist: Array = []


func build(iv: VBoxContainer, after: Control, root: Control) -> void:
	row_bars = HBoxContainer.new()
	row_bars.add_theme_constant_override("separation", 6)
	row_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(row_bars)
	iv.move_child(row_bars, after.get_index() + 1)
	ammo_lbl = HT.make_label("Ammo", HT.TEXT, 13)
	row_bars.add_child(ammo_lbl)
	ammo_bar = _bar(Color("d08a4a"))
	row_bars.add_child(ammo_bar)
	fuel_lbl = HT.make_label("Fuel", HT.TEXT, 13)
	row_bars.add_child(fuel_lbl)
	fuel_bar = _bar(Color("d9c05a"))
	row_bars.add_child(fuel_bar)
	row_chips = HBoxContainer.new()
	row_chips.add_theme_constant_override("separation", 4)
	row_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(row_chips)
	iv.move_child(row_chips, row_bars.get_index() + 1)
	for k in ["mobility", "weapon", "sensors"]:
		var l := HT.make_label("", HT.BG, 13)
		row_chips.add_child(l)
		chips[k] = l
	for i in 5:
		var t := HT.make_label("", HT.TEXT, 13)
		row_chips.add_child(t)
		tag_labels.append(t)
	form_lbl = HT.make_label("", HT.DIM, 13)
	row_chips.add_child(form_lbl)
	_build_group_card(root)


func _bar(fill: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, 12)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.show_percentage = false
	b.max_value = 1.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("fill", HT.box(fill, fill.darkened(0.3), 0, 1, 0))
	b.add_theme_stylebox_override("background", HT.box(Color("0b0e10"), HT.EDGE, 1, 1, 0))
	return b


func _build_group_card(root: Control) -> void:
	group_panel = PanelContainer.new()
	group_panel.anchor_left = 1.0
	group_panel.anchor_right = 1.0
	group_panel.anchor_top = 1.0
	group_panel.anchor_bottom = 1.0
	group_panel.offset_left = -440
	group_panel.offset_right = -14
	group_panel.offset_top = -380
	group_panel.offset_bottom = -222
	group_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	group_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group_panel.add_theme_stylebox_override("panel", HT.box(Color("161b1e"), HT.AMBER.darkened(0.3), 1, 2, 8))
	group_panel.visible = false
	root.add_child(group_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group_panel.add_child(v)
	g_title = HT.make_label("", HT.AMBER, 15)
	v.add_child(g_title)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 8)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ph)
	g_phase = HT.make_label("", HT.TEXT, 14)
	g_phase.custom_minimum_size = Vector2(150, 0)
	ph.add_child(g_phase)
	g_prog = _bar(HT.OLIVE)
	ph.add_child(g_prog)
	g_reason = HT.make_label("", HT.TEXT, 14)
	g_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g_reason.custom_minimum_size = Vector2(400, 0)
	v.add_child(g_reason)
	v.add_child(HT.make_label("Reports", HT.DIM, 12))
	for i in 3:
		var l := HT.make_label("", HT.DIM, 13)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size = Vector2(400, 0)
		v.add_child(l)
		g_hist.append(l)


static func comp_color(v: float) -> Color:
	if v > 50.0:
		return HT.GREEN
	if v > 0.0:
		return HT.AMBER
	return HT.RED


static func tag_color(t: String) -> Color:
	match t:
		"IN COVER": return HT.BLUE
		"SUPPRESSED": return HT.YELLOW
		"PINNED", "NO FUEL": return HT.AMBER
	return HT.RED


func update(w: SimWorld, ents: Array) -> void:
	var single: bool = ents.size() == 1 and ents[0].kind == "unit"
	var e: Dictionary = ents[0] if single else {}
	# ammo / fuel
	var af: float = G2.ammo_frac(e) if single else -1.0
	var ff: float = G2.fuel_frac(e) if single else -1.0
	row_bars.visible = af >= 0.0 or ff >= 0.0
	ammo_lbl.visible = af >= 0.0
	ammo_bar.visible = af >= 0.0
	fuel_lbl.visible = ff >= 0.0
	fuel_bar.visible = ff >= 0.0
	if af >= 0.0:
		ammo_bar.value = af
		ammo_lbl.text = "Ammo %d/%d" % [int(e.ammo), int(Content.unit(e.def).get("ammo_max", 0))]
		ammo_lbl.add_theme_color_override("font_color", HT.RED if int(e.ammo) <= 0 else HT.TEXT)
	if ff >= 0.0:
		fuel_bar.value = ff
		fuel_lbl.text = "%s %d/%d" % [("Charge" if bool(Content.unit(e.def).get("energy", false)) else "Fuel"), int(e.fuel), int(Content.unit(e.def).get("fuel_max", 0))]  # G3a: Machine energy
		fuel_lbl.add_theme_color_override("font_color", HT.RED if float(e.fuel) <= 0.0 else HT.TEXT)
	# component chips
	var has_comp: bool = single and e.has("comp")
	for k in chips:
		var l: Label = chips[k]
		l.visible = has_comp
		if has_comp:
			var v := G2.comp_value(e, String(k))
			var c := comp_color(v)
			l.text = " %s %d " % [{"mobility": "MOB", "weapon": "WPN", "sensors": "SEN"}[k], int(v)]
			l.add_theme_stylebox_override("normal", HT.box(c.darkened(0.55), c, 1, 2, 3))
			l.add_theme_color_override("font_color", c.lightened(0.35))
	# tags
	var tags: Array = G2.tags(e) if single else []
	for i in tag_labels.size():
		var t: Label = tag_labels[i]
		t.visible = i < tags.size()
		if i < tags.size():
			var c2 := tag_color(String(tags[i]))
			t.text = " %s " % tags[i]
			t.add_theme_stylebox_override("normal", HT.box(c2.darkened(0.6), c2, 1, 2, 3))
			t.add_theme_color_override("font_color", c2.lightened(0.3))
	form_lbl.visible = single and e.has("formation")
	if form_lbl.visible:
		form_lbl.text = "  Formation: %s" % String(e.formation)
	row_chips.visible = has_comp or not tags.is_empty() or form_lbl.visible
	_update_group(w, ents)


func _update_group(w: SimWorld, ents: Array) -> void:
	var g: Dictionary = {}
	for e in ents:
		if e.kind == "unit" and G2.is_officer(e):
			g = G2.group_of(w, int(e.id))
			if not g.is_empty():
				break
	if g.is_empty() and ents.size() == 1 and ents[0].kind == "unit":
		g = G2.group_of(w, int(ents[0].id))
	group_panel.visible = not g.is_empty()
	if g.is_empty():
		return
	var m := G2.mission_of(g)
	var mt := G2.mission_type(g)
	var members: Array = g.get("members", [])
	var off = w.entities.get(int(g.get("officer", -1)))
	g_title.text = "GROUP %s  -  %s%s  -  %d members" % [str(g.get("id", "?")), G2.mission_name(mt),
		("  (%s risk)" % String(m.get("risk", "medium"))) if mt != "" else "", members.size()]
	if off == null:
		g_title.text += "  (no officer)"
	var phase := String(g.get("phase", "idle"))
	g_phase.text = "Phase: %s" % phase.to_upper()
	g_phase.add_theme_color_override("font_color", HT.RED if phase == "withdraw" else (HT.GREEN if phase in ["hold", "secure"] else HT.TEXT))
	g_prog.value = clampf(float(g.get("progress", 0.0)), 0.0, 1.0)
	g_reason.text = String(g.get("reason", ""))
	var hist: Array = g.get("history", [])
	for i in 3:
		var l: Label = g_hist[i]
		var idx := hist.size() - 1 - i
		if idx < 0:
			l.text = ""
			continue
		var h = hist[idx]
		if typeof(h) == TYPE_DICTIONARY:
			l.text = "[%s] %s: %s" % [HT.clock_text(int(h.get("tick", 0))), String(h.get("phase", "")).to_upper(), String(h.get("reason", ""))]
		else:
			l.text = str(h)
