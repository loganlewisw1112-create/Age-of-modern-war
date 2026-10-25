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
const EditorLive = preload("res://sim/editor_live.gd")
const ED2_ENTRY := "res://presentation/editor/ed2_tabs.gd"
const ED1_TABS := [
	["map", "Map", "res://presentation/editor/tab_map.gd", 10],
	["terrain", "Terrain", "res://presentation/editor/tab_terrain.gd", 20],
	["height", "Height", "res://presentation/editor/tab_height.gd", 25],   # G6 (ED6)
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
# G6 Live (ED6, CONTRACTS_G6 s15): L toggles; the doc and its undo history are never touched.
var live_world: SimWorld = null
var live_snap: Dictionary = {}
var live_bar: PanelContainer
var _live_label: Label
var _live_speed_btns: Array = []
var _live_acc := 0.0


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
	_build_live_bar()
	view.live_blocked.connect(func(): status("Live is running: press L to stop Live before editing the map.", HT.YELLOW))
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
	# clear the previous tab's properties; tabs that show their own set them in tab_activated
	set_properties(String((tabs[id].button as Button).text), [])
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
	if live_on():
		status("Live is running: press L to stop Live first (undo history is kept).", HT.YELLOW)
		return
	if doc.undo():
		view.stroke_finished()
		status("Undo", HT.DIM)
	_refresh_buttons()


func action_redo() -> void:
	if live_on():
		status("Live is running: press L to stop Live first (undo history is kept).", HT.YELLOW)
		return
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
	live_stop()
	if test_play_handler.is_valid():
		test_play_handler.call(self)
	else:
		status("Test Play is not available yet (scenario tools not installed).", HT.YELLOW)


func action_exit() -> void:
	live_stop()
	exit_requested.emit()


# ------------------------------------------------------------------ G6 Live mode (ED6)
func live_on() -> bool:
	return live_world != null


func toggle_live() -> void:
	if live_on():
		live_stop()
	else:
		live_start()


## Builds the Live world from the doc (placed units/buildings only, every side AI, endless), snapshots
## it and starts stepping. Returns "" or why Live could not start.
func live_start() -> String:
	if live_on():
		return ""
	if doc.in_stroke():
		doc.end_stroke()
	var r: Dictionary = EditorLive.make_world(doc.map_for_save(), doc.scenario_for_save())
	if r.world == null:
		status("Live: %s" % String(r.reason), HT.RED)
		_sync_live_bar()
		return String(r.reason)
	live_world = r.world
	live_snap = EditorLive.start(live_world)
	_live_acc = 0.0
	view.set_live_world(live_world)
	_sync_live_bar()
	status("LIVE: placed units fight (combat + AI tactics, no economy). L stops and rewinds.", HT.GREEN)
	return ""


## Leaves Live: restores the Live world's snapshot (exact) and shows the untouched doc again.
func live_stop() -> void:
	if not live_on():
		return
	EditorLive.stop(live_world, live_snap)
	live_world = null
	live_snap = {}
	view.set_live_world(null)
	_sync_live_bar()
	status("Live stopped: the map is back exactly as it was before Live.", HT.DIM)


func set_live_speed(n: int) -> void:
	EditorLive.set_speed(n)
	_sync_live_bar()


## Unit placement while Live runs: spawn into the Live world only (gone when Live stops).
func live_place(e: Dictionary) -> int:
	if not live_on():
		return -1
	var id := EditorLive.spawn(live_world, e)
	if id >= 0:
		view.live_step(0)
	return id


## Steps `n` Live ticks now (tests / scripted demos; the frame loop uses the speed).
func live_advance(n: int) -> void:
	if live_on():
		view.live_step(n)
		_sync_live_bar()


func _process(delta: float) -> void:
	if not live_on():
		return
	var sp := EditorLive.speed()
	if sp > 0:
		_live_acc += delta * float(SimWorld.TICK_RATE * sp)
		var n := mini(int(_live_acc), 8 * sp)
		_live_acc = minf(_live_acc - float(n), 1.0)
		view.live_step(n)
	if Engine.get_process_frames() % 10 == 0:
		_sync_live_bar()


func _build_live_bar() -> void:
	live_bar = PanelContainer.new()
	live_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	live_bar.offset_top = Panels.TOP_H + 6.0
	live_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ui.root.add_child(live_bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	live_bar.add_child(hb)
	_live_label = HT.make_label("LIVE", HT.RED, 16)
	hb.add_child(_live_label)
	var grp := ButtonGroup.new()
	for sp in EditorLive.SPEEDS:
		var b := Button.new()
		b.text = "Pause" if int(sp) == 0 else "%dx" % int(sp)
		b.toggle_mode = true
		b.button_group = grp
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Pause Live" if int(sp) == 0 else "Live speed %dx" % int(sp)
		var v := int(sp)
		b.pressed.connect(func(): set_live_speed(v))
		hb.add_child(b)
		_live_speed_btns.append(b)
	var stop := Button.new()
	stop.text = "Stop (L)"
	stop.focus_mode = Control.FOCUS_NONE
	stop.tooltip_text = "Stop Live and rewind to the map as it was"
	stop.pressed.connect(live_stop)
	hb.add_child(stop)
	_sync_live_bar()


func _sync_live_bar() -> void:
	if live_bar == null:
		return
	live_bar.visible = live_on()
	if _p != null and _p.live_btn != null:
		_p.live_btn.button_pressed = live_on()
	if not live_on():
		return
	var sp := EditorLive.speed()
	for i in _live_speed_btns.size():
		(_live_speed_btns[i] as Button).set_pressed_no_signal(int(EditorLive.SPEEDS[i]) == sp)
	var units := 0
	for e in live_world.entities.values():
		if String(e.kind) == "unit":
			units += 1
	_live_label.text = "● LIVE %s  %.0fs  %d units" % ["(paused)" if sp == 0 else "", float(live_world.tick) / float(SimWorld.TICK_RATE), units]


func set_symmetry(mode: String) -> void:
	doc.symmetry = mode
	status("Symmetry: %s" % mode, HT.DIM)


func _on_doc_changed(cells: Array, kind: String) -> void:
	if kind == "all" and cells.is_empty():
		minimap.rebuild()
		_p.sync_symmetry()
		_p.reset_issues()
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
	elif k.keycode == KEY_L and not k.ctrl_pressed and not k.alt_pressed and not view._typing():
		toggle_live()
	elif k.keycode == KEY_ESCAPE and view.tool != null and view.tool.has_method("tool_cancel"):
		view.tool.tool_cancel()
	else:
		return
	get_viewport().set_input_as_handled()
