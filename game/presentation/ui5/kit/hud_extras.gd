extends RefCounted
## UI5a (G5): HUD extras built by hud.gd: the control-group bar and idle-workers button
## (bottom-right, just above the bottom panel) and the F1 hotkey sheet (modal, centred).
## Reads the world only from hud._refresh(), which never runs while a sim step is in flight.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")

const SHEET := [
	["Left click / drag", "Select a unit / box-select. Shift adds to the selection."],
	["Double-click", "Select every unit of that type on screen."],
	["Right click", "Move, attack, gather, repair or load: the order fits the target."],
	["A, then click", "Attack-move to the point."],
	["S / H", "Stop / hold position."],
	["1-9", "Select control group. Press twice to centre the camera on it."],
	["Ctrl+1-9 / Shift+1-9", "Assign the selection to a group / add the group to the selection."],
	[".", "Select the next idle worker (Shift+.: every idle worker)."],
	["[Letter] on a button", "Card hotkey: build, train, research or order."],
	["Space", "Jump to the last alert."],
	["W A S D / arrows", "Pan (edge of the screen and middle-drag pan too). Wheel zooms."],
	["P", "Pause / resume."],
	["Esc", "Cancel placement or order, clear the selection, then the pause menu."],
	["F1", "Show / hide this sheet."],
]

var hud: Node = null
var bar: HFlowContainer
var idle_btn: Button
var group_btns: Dictionary = {}     # g -> Button
var sheet: PanelContainer
var _idle: Array = []               # own idle worker ids (ascending)
var _idle_next := 0


func build(h: Node, root: Control) -> void:
	hud = h
	bar = HFlowContainer.new()
	bar.name = "GroupBar"
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_right = -h.EDGE_M
	bar.offset_left = -(h.EDGE_M + 420.0)
	bar.offset_bottom = -(h.BOTTOM_H + 6.0)
	bar.offset_top = bar.offset_bottom - 30.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.alignment = FlowContainer.ALIGNMENT_END
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("h_separation", 4)
	bar.add_theme_constant_override("v_separation", 4)
	root.add_child(bar)
	for g in range(1, 10):
		var b := Button.new()
		b.text = str(g)
		b.custom_minimum_size = Vector2(46, 28)
		b.tooltip_text = UiKit.tooltip("Control group %d" % g, str(g), {}, "Click or press %d: select. Press twice: centre the camera. Ctrl+%d assigns." % [g, g])
		b.pressed.connect(_on_group.bind(g))
		b.visible = false
		bar.add_child(b)
		group_btns[g] = b
	idle_btn = UiKit.button("Idle 0", ".", "Select the next idle worker. Shift+click or Shift+. selects every idle worker.")
	idle_btn.custom_minimum_size = Vector2(0, 28)
	idle_btn.pressed.connect(func(): select_idle(Input.is_key_pressed(KEY_SHIFT)))
	bar.add_child(idle_btn)
	_build_sheet(root)


func _build_sheet(root: Control) -> void:
	sheet = UiKit.panel("modal")
	sheet.name = "HotkeySheet"
	sheet.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sheet.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sheet.grow_vertical = Control.GROW_DIRECTION_BOTH
	sheet.visible = false
	UiKit.fit_register(sheet, true)
	root.add_child(sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	sheet.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UiKit.label("HOTKEYS", "header")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UiKit.button("Close", "F1", "Hide the hotkey sheet")
	close.pressed.connect(toggle_sheet)
	head.add_child(close)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 5)
	for row in SHEET:
		var k := UiKit.label(String(row[0]), "number")
		k.add_theme_color_override("font_color", UiKit.AMBER)
		grid.add_child(k)
		var d := UiKit.label(String(row[1]))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(380, 0)
		grid.add_child(d)
	var sc := UiKit.scroll(grid)
	sc.name = "HotkeyScroll"
	v.add_child(sc)
	_size_sheet()


func _size_sheet() -> void:
	if sheet == null or hud == null or hud.layer == null:
		return
	var cs: Vector2 = hud.layer.canvas_size()
	var sc: ScrollContainer = sheet.find_child("HotkeyScroll", true, false)
	if sc != null:
		sc.custom_minimum_size = Vector2(minf(620.0, cs.x - 80.0), clampf(cs.y - 260.0, 160.0, 470.0))


func toggle_sheet() -> void:
	_size_sheet()
	sheet.visible = not sheet.visible


func update(w: SimWorld, mv: Node) -> void:
	if w == null or mv == null:
		return
	var pf := int(mv.get("player_fid"))
	var groups: Dictionary = mv.get("control_groups") if mv.get("control_groups") != null else {}
	for g in group_btns:
		var n := 0
		for id in groups.get(g, []):
			if w.entities.has(id):
				n += 1
		var b: Button = group_btns[g]
		b.visible = n > 0
		b.text = "%d  x%d" % [g, n]
	_idle.clear()
	for e in w.units_of(pf):
		var d: Dictionary = Content.unit(String(e.def))
		if not (bool(d.get("can_build", false)) or bool(d.get("can_gather", false))):
			continue
		if String((e.get("order", {}) as Dictionary).get("type", "idle")) == "idle":
			_idle.append(int(e.id))
	_idle.sort()
	idle_btn.text = "[.] Idle %d" % _idle.size()
	idle_btn.disabled = _idle.is_empty()
	# the bar keeps clear of the centred cargo strip (UI5b, 600 px wide) on narrow canvases
	var cs: Vector2 = hud.layer.canvas_size()
	bar.offset_left = -(hud.EDGE_M + clampf(cs.x * 0.5 - 300.0 - 2.0 * hud.EDGE_M, 150.0, 480.0))


func select_idle(all: bool) -> void:
	if _idle.is_empty() or hud == null or hud.mv == null:
		return
	var mv: Node = hud.mv
	if all:
		mv.select_ids(_idle.duplicate())
		return
	_idle_next = _idle_next % _idle.size()
	var id: int = _idle[_idle_next]
	_idle_next += 1
	mv.select_ids([id])
	var w: SimWorld = mv.get("world")
	if w != null and w.entities.has(id) and mv.has_method("center_camera_on"):
		mv.center_camera_on(w.entities[id].pos)


func _on_group(g: int) -> void:
	if hud != null and hud.mv != null and hud.mv.has_method("_recall_group"):
		hud.mv._recall_group(g, Input.is_key_pressed(KEY_SHIFT))


## Returns true when the key was consumed (called from hud._unhandled_input).
func on_key(k: InputEventKey) -> bool:
	if k.keycode == KEY_F1:
		toggle_sheet()
		return true
	if k.keycode == KEY_PERIOD:
		select_idle(k.shift_pressed)
		return true
	if k.keycode == KEY_ESCAPE and sheet.visible:
		sheet.visible = false
		return true
	return false
