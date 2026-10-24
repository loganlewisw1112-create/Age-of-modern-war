extends Node
## Map editor root (owner: ED1, CONTRACTS_G4 section 9 / PLAN_G4 section 3.1). Opened by main.gd.
## Top bar: New / Open / Save / Save As / Undo / Redo / Validate / Test Play / Exit.
## Left: tab bar + tool panel. Right: minimap, symmetry, layer toggles, properties, issues.
##
## Extension API (ED2):
##   res://presentation/editor/ed2_tabs.gd  with  static func register_editor(editor) -> void
##   is loaded automatically when it exists. From there:
##     editor.register_tab(id, title, panel: Control, order := 100)   panel.setup(editor) is called
##       if present; while its tab is active the panel is the map tool (see editor_view.gd).
##     editor.doc (editor_doc.gd: map, scenario, begin_stroke/mark/end_stroke, push_command,
##       apply(brush, cells, params), sym_cells), editor.view (editor_view.gd)
##     editor.stroke_done()   call after a tool finishes a stroke (commits undo, refreshes views)
##     editor.status(text, color)   editor.set_properties(title, lines: Array[String])
##     editor.test_play_handler: Callable(editor)   editor.validate_handler: Callable(editor) -> Array
##     editor.request_test_play(cfg)   asks main.gd to start cfg and come back to the editor.

signal exit_requested
signal test_play_requested(cfg: Dictionary)

const HT = preload("res://presentation/hud/hud_theme.gd")
const ScaledLayer = preload("res://presentation/hud/scaled_layer.gd")
const Doc = preload("res://presentation/editor/editor_doc.gd")
const View = preload("res://presentation/editor/editor_view.gd")
const Minimap = preload("res://presentation/editor/editor_minimap.gd")
const Panels = preload("res://presentation/editor/editor_panels.gd")
const MapIO = preload("res://sim/map_io.gd")
const ED2_ENTRY := "res://presentation/editor/ed2_tabs.gd"
const ED1_TABS := [
	["map", "Map", "res://presentation/editor/tab_map.gd", 10],
	["terrain", "Terrain", "res://presentation/editor/tab_terrain.gd", 20],
	["water", "Water", "res://presentation/editor/tab_water.gd", 30],
	["nature", "Nature & objects", "res://presentation/editor/tab_nature.gd", 40],
	["resources", "Resources", "res://presentation/editor/tab_resources.gd", 50],
]

var doc: Doc
var view: View
var ui: Node
var minimap: Control
var tabs: Dictionary = {}          # id -> {title, panel, button, order}
var active_tab: String = ""
var test_play_handler: Callable
var validate_handler: Callable
var ui_scale: float = 1.0
var _p: Panels


func _ready() -> void:
	Content.load_all()
	doc = Doc.new()
	view = View.new()
	add_child(view)
	view.setup(doc)
	ui = ScaledLayer.new()
	ui.layer = 10
	add_child(ui)
	ui.root.theme = HT.make_theme()
	ui.set_ui_scale(ui_scale)
	_p = Panels.new()
	_p.build(self)
	minimap = Minimap.new()
	_p.minimap_slot.add_child(minimap)
	minimap.setup(view)
	doc.changed.connect(_on_doc_changed)
	view.hover_changed.connect(_on_hover)
	for t in ED1_TABS:
		var panel: Control = load(String(t[2])).new()
		register_tab(String(t[0]), String(t[1]), panel, int(t[3]))
	if ResourceLoader.exists(ED2_ENTRY):
		var s = load(ED2_ENTRY)
		if s != null:
			s.register_editor(self)
	select_tab("terrain")
	_refresh_buttons()
	status("Map editor ready. Left-drag paints, middle-drag or WASD pans, wheel zooms, right-click cancels.", HT.DIM)


# ------------------------------------------------------------------ extension API
func register_tab(id: String, title: String, panel: Control, order: int = 100) -> void:
	if tabs.has(id):
		push_warning("editor: tab %s registered twice" % id)
		return
	var b := Button.new()
	b.text = title
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.button_group = _p.tab_group
	b.pressed.connect(select_tab.bind(id))
	tabs[id] = {"title": title, "panel": panel, "button": b, "order": order}
	var ids := tabs.keys()
	ids.sort_custom(func(a, c): return int(tabs[a].order) < int(tabs[c].order))
	for k in _p.tab_bar.get_children():
		_p.tab_bar.remove_child(k)
	for k in ids:
		_p.tab_bar.add_child(tabs[k].button)
	panel.visible = false
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p.tool_box.add_child(panel)
	if panel.has_method("setup"):
		panel.setup(self)


func select_tab(id: String) -> void:
	if not tabs.has(id):
		return
	if active_tab != "" and tabs.has(active_tab):
		var old: Control = tabs[active_tab].panel
		if old.has_method("tool_cancel"):
			old.tool_cancel()
		old.visible = false
	active_tab = id
	var p: Control = tabs[id].panel
	p.visible = true
	(tabs[id].button as Button).button_pressed = true
	view.tool = p
	if p.has_method("tab_activated"):
		p.tab_activated()
	view.preview.queue_redraw()


func tab_panel(id: String) -> Control:
	return tabs[id].panel if tabs.has(id) else null


func stroke_done() -> void:
	doc.end_stroke()
	view.stroke_finished()
	_refresh_buttons()


func status(text: String, color: Color = HT.TEXT) -> void:
	_p.status_label.text = text
	_p.status_label.add_theme_color_override("font_color", color)


func set_properties(title: String, lines: Array) -> void:
	_p.props_title.text = title
	_p.props_body.text = "\n".join(PackedStringArray(lines))


func request_test_play(cfg: Dictionary) -> void:
	test_play_requested.emit(cfg)


## main.gd hides the editor during a test play and shows it again afterwards.
func set_active(on: bool) -> void:
	view.visible = on
	ui.visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		view.camera.make_current()


# ------------------------------------------------------------------ top bar actions
func action_new() -> void:
	select_tab("map")
	var p: Control = tab_panel("map")
	if p != null and p.has_method("create_new"):
		p.create_new()


func action_open() -> void:
	_p.open_dialog(false)


func action_save() -> void:
	if doc.path == "":
		_p.open_dialog(true)
	else:
		save_to(doc.path)


func action_save_as() -> void:
	_p.open_dialog(true)


func save_to(path: String) -> String:
	if not path.ends_with(".rtsmap"):
		path += ".rtsmap"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := MapIO.save(path, doc.map_for_save(), doc.scenario_for_save())
	if err == "":
		doc.path = path
		doc.dirty = false
		status("Saved %s" % path, HT.GREEN)
	else:
		status("Save failed: %s" % err, HT.RED)
	_refresh_buttons()
	return err


func open_path(path: String) -> String:
	var r: Dictionary = MapIO.read(path)
	if r.has("error"):
		status("Open failed: %s" % r.error, HT.RED)
		return String(r.error)
	doc.set_doc(r.map, r.get("scenario", {}), path)
	status("Opened %s" % path, HT.GREEN)
	return ""


func action_undo() -> void:
	if doc.undo():
		view.stroke_finished()
		status("Undo", HT.DIM)
	_refresh_buttons()


func action_redo() -> void:
	if doc.redo():
		view.stroke_finished()
		status("Redo", HT.DIM)
	_refresh_buttons()


## Runs MapIO.validate (+ ED2's handler) and lists the issues with "jump to" buttons.
func action_validate() -> Array:
	var issues: Array = MapIO.validate(doc.map_for_save(), doc.scenario_for_save())
	if validate_handler.is_valid():
		issues.append_array(validate_handler.call(self))
	_p.show_issues(issues)
	status("Validate: %s" % ("no problems found" if issues.is_empty() else "%d problem(s)" % issues.size()),
		HT.GREEN if issues.is_empty() else HT.YELLOW)
	return issues


func action_test_play() -> void:
	if test_play_handler.is_valid():
		test_play_handler.call(self)
	else:
		status("Test Play is not available yet (scenario tools not installed).", HT.YELLOW)


func action_exit() -> void:
	exit_requested.emit()


func set_symmetry(mode: String) -> void:
	doc.symmetry = mode
	status("Symmetry: %s" % mode, HT.DIM)


func _on_doc_changed(cells: Array, kind: String) -> void:
	if kind == "all" and cells.is_empty():
		minimap.rebuild()
		_p.sync_symmetry()
	else:
		minimap.on_cells_changed(cells)
	_refresh_buttons()


func _on_hover(c: Vector2i) -> void:
	if not view.in_map(c):
		_p.hover_label.text = ""
		return
	var code := int(doc.map.terrain[c.y * int(doc.map.w) + c.x])
	_p.hover_label.text = "%d, %d  %s" % [c.x, c.y, Terrain.NAMES[code] if code < Terrain.NAMES.size() else str(code)]


func _refresh_buttons() -> void:
	if _p == null:
		return
	_p.undo_btn.disabled = not doc.can_undo()
	_p.redo_btn.disabled = not doc.can_redo()
	var nm := String(doc.scenario.get("name", "Untitled"))
	_p.title_label.text = "%s%s  (%dx%d)" % [nm, " *" if doc.dirty else "", int(doc.map.w), int(doc.map.h)]


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.ctrl_pressed and k.keycode == KEY_Z:
		if k.shift_pressed:
			action_redo()
		else:
			action_undo()
	elif k.ctrl_pressed and k.keycode == KEY_Y:
		action_redo()
	elif k.ctrl_pressed and k.keycode == KEY_S:
		action_save()
	elif k.keycode == KEY_ESCAPE and view.tool != null and view.tool.has_method("tool_cancel"):
		view.tool.tool_cancel()
	else:
		return
	get_viewport().set_input_as_handled()
