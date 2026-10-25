extends Control
## Victory / defeat screen (owner: agent E).

signal continue_requested
signal menu_requested

const HT = preload("res://presentation/hud/hud_theme.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")   # G5 (UI5a)


## stats: {won:bool, clock:String, trained:int, built:int, lost:int, killed:int, reason:String}
func setup(stats: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var won: bool = bool(stats.get("won", false))
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UiKit.panel("modal")
	panel.name = "EndPanel"
	panel.custom_minimum_size = Vector2(440, 0)
	panel.add_theme_stylebox_override("panel", HT.box(HT.PANEL, HT.GREEN if won else HT.RED, 2, 2, 16))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := HT.make_label("VICTORY" if won else "DEFEAT", HT.GREEN if won else HT.RED, 48)
	title.add_theme_font_override("font", UiKit.font(true))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := HT.make_label(String(stats.get("subtitle", "")), HT.DIM, 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(HSeparator.new())
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 40)
	v.add_child(g)
	for row in [["Match time", stats.get("clock", "")], ["Units trained", stats.get("trained", 0)],
			["Structures built", stats.get("built", 0)], ["Units and structures lost", stats.get("lost", 0)],
			["Enemy kills", stats.get("killed", 0)]]:
		g.add_child(HT.make_label(String(row[0]), HT.DIM))
		g.add_child(HT.make_label(str(row[1]), HT.TEXT))
	# G3a: team results (winner first): [{text, color}]
	var teams: Array = stats.get("teams", [])
	if not teams.is_empty():
		v.add_child(HSeparator.new())
		v.add_child(HT.make_label("TEAM RESULTS", HT.AMBER, 14))
		for t in teams:
			v.add_child(HT.make_label(String(t.get("text", "")), t.get("color", HT.TEXT), 14))
	v.add_child(HSeparator.new())
	var cont := Button.new()
	cont.text = "Continue watching"
	cont.custom_minimum_size = Vector2(0, 40)
	cont.pressed.connect(func(): continue_requested.emit())
	v.add_child(cont)
	var menu := Button.new()
	menu.text = "Main menu"
	menu.custom_minimum_size = Vector2(0, 40)
	menu.pressed.connect(func(): menu_requested.emit())
	v.add_child(menu)
