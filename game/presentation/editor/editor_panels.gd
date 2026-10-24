extends RefCounted
## Editor screen layout (owner: ED1): top bar, left tab column, right column (minimap,
## symmetry, layers, properties, issues), status bar, open/save dialog. Built in code.

const HT = preload("res://presentation/hud/hud_theme.gd")
const W = preload("res://presentation/editor/editor_widgets.gd")
const Symmetry = preload("res://presentation/editor/symmetry.gd")
const LEFT_W := 300.0
const RIGHT_W := 262.0
const TOP_H := 46.0
const BOTTOM_H := 28.0

var ed                      # editor_scene.gd
var tab_group := ButtonGroup.new()
var tab_bar: HFlowContainer
var tool_box: VBoxContainer
var minimap_slot: VBoxContainer
var status_label: Label
var hover_label: Label
var title_label: Label
var props_title: Label
var props_body: Label
var issues_box: VBoxContainer
var undo_btn: Button
var redo_btn: Button
var sym_opt: OptionButton
var dialog: FileDialog
var _dialog_save := false


func _panel(root: Control, preset: int) -> PanelContainer:
	var p := PanelContainer.new()
	root.add_child(p)
	p.set_anchors_preset(preset)
	return p


func build(editor) -> void:
	ed = editor
	var root: Control = ed.ui.root
	# ---- top bar
	var top := _panel(root, Control.PRESET_TOP_WIDE)
	top.offset_bottom = TOP_H
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 6)
	top.add_child(tb)
	tb.add_child(HT.make_label("MAP EDITOR", HT.AMBER, 18))
	W.button(tb, "New", ed.action_new, "New map (Map tab)")
	W.button(tb, "Open", ed.action_open, "Open a .rtsmap from user://maps")
	W.button(tb, "Save", ed.action_save, "Save (Ctrl+S)")
	W.button(tb, "Save As", ed.action_save_as)
	undo_btn = W.button(tb, "Undo", ed.action_undo, "Undo (Ctrl+Z)")
	redo_btn = W.button(tb, "Redo", ed.action_redo, "Redo (Ctrl+Y)")
	W.button(tb, "Validate", ed.action_validate, "Check starts, reachability, placements")
	W.button(tb, "Test Play", ed.action_test_play, "Play this map now, then come back")
	W.button(tb, "Exit", ed.action_exit, "Back to the main menu")
	title_label = HT.make_label("", HT.TEXT, 15)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tb.add_child(title_label)
	# ---- left column
	var left := _panel(root, Control.PRESET_LEFT_WIDE)
	left.offset_top = TOP_H + 4
	left.offset_bottom = -BOTTOM_H - 4
	left.offset_right = LEFT_W
	var lv := VBoxContainer.new()
	left.add_child(lv)
	tab_bar = HFlowContainer.new()
	lv.add_child(tab_bar)
	lv.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	tool_box = VBoxContainer.new()
	tool_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tool_box)
	# ---- right column
	var right := _panel(root, Control.PRESET_RIGHT_WIDE)
	right.offset_top = TOP_H + 4
	right.offset_bottom = -BOTTOM_H - 4
	right.offset_left = -RIGHT_W
	var rscroll := ScrollContainer.new()
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rscroll)
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.add_child(rv)
	minimap_slot = VBoxContainer.new()
	rv.add_child(minimap_slot)
	W.header(rv, "Symmetry")
	sym_opt = W.option(rv, "", Symmetry.LABELS, 0, _on_sym)
	W.header(rv, "Layers")
	W.check(rv, "Grid", false, func(on: bool): _layer("grid", on))
	W.check(rv, "Decor", true, func(on: bool): _layer("decor", on))
	W.check(rv, "Units & resources", true, func(on: bool): _layer("units", on))
	W.option(rv, "Passability", ["Off", "Foot", "Vehicle", "Amphibious", "Naval (small)", "Naval", "Air"], 0, _on_pass)
	W.header(rv, "Properties")
	props_title = HT.make_label("", HT.TEXT, 14)
	rv.add_child(props_title)
	props_body = W.note(rv, "Hover the map or pick a tool.")
	W.header(rv, "Issues")
	issues_box = VBoxContainer.new()
	rv.add_child(issues_box)
	W.note(issues_box, "Press Validate to check the map.")
	# ---- status bar
	var bottom := _panel(root, Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -BOTTOM_H
	var bb := HBoxContainer.new()
	bottom.add_child(bb)
	status_label = HT.make_label("", HT.DIM, 13)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	bb.add_child(status_label)
	hover_label = HT.make_label("", HT.TEXT, 13)
	bb.add_child(hover_label)
	for c in [top, left, right, bottom]:
		c.mouse_filter = Control.MOUSE_FILTER_STOP
	# ---- file dialog
	dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_USERDATA
	dialog.filters = PackedStringArray(["*.rtsmap ; RTS map"])
	dialog.use_native_dialog = false
	dialog.file_selected.connect(_on_file)
	ed.add_child(dialog)


func _layer(key: String, on: bool) -> void:
	ed.view.layers_on[key] = on
	if key == "units":
		ed.view._sync_world()
	ed.view.overlay.queue_redraw()


func _on_pass(i: int) -> void:
	ed.view.layers_on["pass"] = ["", "foot", "vehicle", "amphibious", "naval_small", "naval", "air"][i]
	ed.view.overlay.queue_redraw()


func _on_sym(i: int) -> void:
	var mode: String = Symmetry.MODES[i]
	if not Symmetry.valid_for(mode, int(ed.doc.map.w), int(ed.doc.map.h)):
		ed.status("Mirror diagonal needs a square map.", HT.YELLOW)
		sync_symmetry()
		return
	ed.set_symmetry(mode)


func sync_symmetry() -> void:
	sym_opt.select(maxi(0, Symmetry.MODES.find(ed.doc.symmetry)))


func open_dialog(save: bool) -> void:
	_dialog_save = save
	DirAccess.make_dir_recursive_absolute("user://maps")
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	dialog.title = "Save map" if save else "Open map"
	dialog.current_dir = "user://maps"
	if save:
		dialog.current_file = String(ed.doc.scenario.get("name", "map")).to_snake_case() + ".rtsmap"
	dialog.popup_centered(Vector2i(760, 520))


func _on_file(path: String) -> void:
	if _dialog_save:
		ed.save_to(path)
	else:
		ed.open_path(path)


func show_issues(issues: Array) -> void:
	for c in issues_box.get_children():
		c.queue_free()
	if issues.is_empty():
		var ok := HT.make_label("No problems found.", HT.GREEN, 14)
		issues_box.add_child(ok)
		return
	for it in issues:
		var row := HBoxContainer.new()
		issues_box.add_child(row)
		var l := W.note(row, "%s: %s" % [String(it.get("code", "")), String(it.get("msg", ""))])
		l.custom_minimum_size = Vector2(170, 0)
		l.add_theme_color_override("font_color", HT.YELLOW)
		if it.has("cell") and it.cell != null:
			var c = it.cell
			var cell := Vector2i(int(c[0]), int(c[1])) if c is Array else Vector2i(c)
			W.button(row, "Go", func(): ed.view.center_camera_on(Vector2(cell) + Vector2(0.5, 0.5)), "Jump to %s" % cell)
