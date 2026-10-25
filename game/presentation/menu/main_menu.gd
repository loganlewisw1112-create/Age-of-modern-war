extends Control
## Main menu + skirmish setup (owner: agent E). Built in code. Emits signals; main.gd acts on them.

signal start_requested(cfg: Dictionary)
signal load_requested(path: String)
signal quit_requested
signal ui_scale_changed(s: float)
signal editor_requested   # G4e (ED1): "Map Editor" button

const HT = preload("res://presentation/hud/hud_theme.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")   # G5 (UI5a)
const ScaledLayer = preload("res://presentation/hud/scaled_layer.gd")
const WIDE_W := 1360.0
const MENU_BTN_W := 170.0
const SkirmishSetup = preload("res://presentation/menu/skirmish_setup.gd")
const VictoryBuilder = preload("res://presentation/menu/victory_builder.gd")
const G3bData = preload("res://presentation/hud/g3b_data.gd")  # G3b (UI4): maps, stages, advancement
const SAVE_SLOTS := [
	{"label": "Quick save", "path": "user://saves/quick.sav"},
	{"label": "Slot 1", "path": "user://saves/slot_1.sav"},
]
const HOW_TO_PLAY := """MOUSE
  Left click / drag      Select units (shift adds, double-click selects all of a type)
  Right click            Smart command: attack, gather, assist build, or move
  Mouse wheel            Zoom
  Screen edge / WASD     Pan the camera
  Minimap                Click or drag to jump the camera

KEYS
  A + left click   Attack-move        S  Stop        H  Hold position
  Ctrl+1..9        Set control group  1..9  Recall group
  Space            Jump to last alert Esc  Cancel / deselect / pause menu
  P                Pause              F5 / F9   Quick save / quick load

BUILDING AND TRAINING
  Select your builders (Work Crew, Works Crew, Repair Bots): the BUILD panel
  appears bottom right. Click a structure (or press its hotkey), then click
  the map to place it. Select your HQ or barracks to train units.
  Locked buttons say why.

START HERE (the OBJECTIVES panel names your faction's buildings)
  1. Build a power building.        2. Build a barracks.
  3. Train an infantry unit.        4. Meet the VICTORY panel's conditions.
  Gatherers (engineers, crews, Cargo Haulers) right-click salvage or ore."""

var _seed: LineEdit
var setup: VBoxContainer       # skirmish_setup.gd (slots, economy)
var victory: VBoxContainer     # victory_builder.gd
var map_opt: OptionButton      # G3b map picker (hidden once the G4e map browser drives it)
var _map_lbl: Label = null
var adv_opt: OptionButton      # G3b advancement rules
var _map_rows: Array = []
var _adv_ids: Array = []
var _summary: Label
var _scale_opt: OptionButton
var _load_panel: VBoxContainer
var _howto: PanelContainer
var _howto_scroll: ScrollContainer
var _row: BoxContainer
var _margin: MarginContainer
var _left: VBoxContainer
var _btn_flow: HFlowContainer
var _title: Label
var _title_small: Label
var _tagline: Label
var _setup_scroll: ScrollContainer
var _load_note: Label
var _save_system_ok: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_validate()


func set_save_system_available(ok: bool) -> void:
	_save_system_ok = ok
	_refresh_load()


func _build() -> void:
	# G5 (UI5a): responsive layout. Wide canvases put the title/buttons column beside the setup
	# panel; narrow ones (< WIDE_W) stack them. The setup panel scrolls vertically when the canvas
	# is short, so nothing is ever cut off (tools/ui_fit_test.gd).
	var bg := ColorRect.new()
	bg.color = Color("0d1113")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# decorative diagonal bands
	var deco := Control.new()
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(_draw_deco.bind(deco))
	add_child(deco)

	var margin := MarginContainer.new()
	_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	_row = BoxContainer.new()
	_row.add_theme_constant_override("separation", 24)
	margin.add_child(_row)

	# ---- title + buttons column (a row of buttons when stacked)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 8)
	_row.add_child(_left)
	_title_small = UiKit.label("RTS", "header")
	_title_small.add_theme_color_override("font_color", HT.OLIVE)
	_left.add_child(_title_small)
	_title = UiKit.label("AGE OF\nMODERN WAR", "title")
	_title.add_theme_font_size_override("font_size", 46)
	_left.add_child(_title)
	_tagline = UiKit.label("Three maps, Stages 7-9, up to 4 sides", "dim")
	_left.add_child(_tagline)
	_btn_flow = HFlowContainer.new()
	_btn_flow.add_theme_constant_override("h_separation", 8)
	_btn_flow.add_theme_constant_override("v_separation", 8)
	_left.add_child(_btn_flow)
	var start := _menu_button("Start Skirmish", _btn_flow)
	start.pressed.connect(_on_start)
	var load_b := _menu_button("Load Game", _btn_flow)
	load_b.pressed.connect(_toggle_load)
	var editor_b := _menu_button("Map Editor", _btn_flow)
	editor_b.pressed.connect(func(): editor_requested.emit())
	var how := _menu_button("How to Play", _btn_flow)
	how.pressed.connect(_toggle_howto)
	var quit := _menu_button("Quit", _btn_flow)
	quit.pressed.connect(func(): quit_requested.emit())
	_load_panel = VBoxContainer.new()
	_load_panel.visible = false
	_load_panel.add_theme_constant_override("separation", 4)
	_left.add_child(_load_panel)
	_load_note = HT.make_label("", HT.YELLOW, 14)
	_load_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left.add_child(_load_note)
	var sc := HBoxContainer.new()
	_left.add_child(sc)
	sc.add_child(UiKit.label("UI scale", "dim"))
	_scale_opt = OptionButton.new()
	_scale_opt.tooltip_text = "Interface size (on top of the automatic resolution scaling)"
	for s in ScaledLayer.SCALE_STEPS:
		_scale_opt.add_item("%d%%" % int(round(float(s) * 100.0)))
	_scale_opt.item_selected.connect(_on_scale)
	sc.add_child(_scale_opt)

	# ---- skirmish setup (scrolls vertically on short canvases)
	_setup_scroll = ScrollContainer.new()
	_setup_scroll.name = "SetupScroll"
	_setup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_setup_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_setup_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_row.add_child(_setup_scroll)
	var panel := UiKit.panel("frame")
	panel.name = "SetupPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_setup_scroll.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	panel.add_child(pv)
	pv.add_child(UiKit.label("SKIRMISH SETUP", "header"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	pv.add_child(grid)

	_map_lbl = HT.make_label("Map", HT.DIM)
	grid.add_child(_map_lbl)
	map_opt = OptionButton.new()
	map_opt.name = "MapOption"
	map_opt.custom_minimum_size = Vector2(300, 0)
	map_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_rows = G3bData.map_rows()
	for m in _map_rows:
		map_opt.add_item(G3bData.map_label(m))
		if not bool(m.present):
			map_opt.set_item_disabled(map_opt.item_count - 1, true)
	map_opt.select(0)
	map_opt.item_selected.connect(_on_changed_num)
	grid.add_child(map_opt)

	grid.add_child(HT.make_label("Seed", HT.DIM))
	var sh := HBoxContainer.new()
	_seed = LineEdit.new()
	_seed.text = str(int(Content.rules().defaults.seed)) if Content.rules().has("defaults") else "1337"
	_seed.custom_minimum_size = Vector2(160, 0)
	_seed.text_changed.connect(_on_changed_text)
	sh.add_child(_seed)
	var rnd := Button.new()
	rnd.text = "Randomize"
	rnd.pressed.connect(_on_randomize)
	sh.add_child(rnd)
	grid.add_child(sh)

	grid.add_child(HT.make_label("Advancement", HT.DIM))
	adv_opt = OptionButton.new()
	adv_opt.name = "AdvancementOption"
	adv_opt.custom_minimum_size = Vector2(300, 0)
	adv_opt.tooltip_text = "Free: advancing costs nothing. Standard: normal cost. Simulation: x1.5 cost."
	_adv_ids = G3bData.advancement_ids()
	for a_id in _adv_ids:
		adv_opt.add_item(G3bData.advancement_label(String(a_id)))
	adv_opt.select(maxi(0, _adv_ids.find("standard")))
	adv_opt.item_selected.connect(_on_changed_num)
	grid.add_child(adv_opt)

	pv.add_child(HSeparator.new())
	setup = SkirmishSetup.new()
	setup.name = "SkirmishSetup"
	setup.build()
	setup.changed.connect(_on_changed_num)
	pv.add_child(setup)
	victory = VictoryBuilder.new()
	victory.name = "VictoryBuilder"
	victory.build()
	victory.changed.connect(_on_changed_num)
	pv.add_child(victory)
	pv.add_child(HSeparator.new())
	_summary = HT.make_label("", HT.TEXT, 14)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(0, 58)
	pv.add_child(_summary)
	var go := UiKit.button("START MATCH")
	go.tooltip_text = "Start the match with these settings"
	go.custom_minimum_size = Vector2(0, 46)
	go.pressed.connect(_on_start)
	pv.add_child(go)

	# ---- how to play overlay (modal; its text scrolls on short canvases)
	_howto = UiKit.panel("modal")
	_howto.name = "HowToPanel"
	_howto.visible = false
	add_child(_howto)
	var hv := VBoxContainer.new()
	_howto.add_child(hv)
	hv.add_child(UiKit.label("HOW TO PLAY", "header"))
	var txt := HT.make_label(HOW_TO_PLAY, HT.TEXT, 14)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	txt.add_theme_font_override("font", mono)
	_howto_scroll = UiKit.scroll(txt)
	hv.add_child(_howto_scroll)
	var close := UiKit.button("Close", "", "Close How to Play")
	close.pressed.connect(_toggle_howto)
	hv.add_child(close)
	resized.connect(_relayout)
	_relayout()
	_refresh_load()


## Side-by-side when the canvas is wide, stacked (buttons in a row on top) when it is narrow.
func _relayout() -> void:
	if _row == null:
		return
	var wide := size.x >= WIDE_W
	_row.vertical = not wide
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 20 if wide else 8)
	_left.custom_minimum_size = Vector2(300 if wide else 0, 0)
	_title.text = "AGE OF\nMODERN WAR" if wide else "AGE OF MODERN WAR"
	_title.add_theme_font_size_override("font_size", 46 if wide else 30)
	_tagline.visible = wide
	for b in _btn_flow.get_children():
		(b as Control).custom_minimum_size.x = 280.0 if wide else MENU_BTN_W
	if _howto != null:
		_howto_scroll.custom_minimum_size = Vector2(minf(720.0, size.x - 120.0), clampf(size.y - 220.0, 120.0, 560.0))
		_howto.reset_size()
		_howto.position = ((size - _howto.get_combined_minimum_size()) * 0.5).floor()


func _draw_deco(deco: Control) -> void:
	var sz := deco.size
	for i in 6:
		var x := sz.x * 0.55 + i * 90.0
		deco.draw_line(Vector2(x, sz.y), Vector2(x + sz.y * 0.6, 0), Color(0.89, 0.66, 0.23, 0.05 + 0.01 * i), 24.0)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _menu_button(text: String, parent: Control) -> Button:
	var b := UiKit.button(text, "", text)
	b.custom_minimum_size = Vector2(MENU_BTN_W, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b


# ------------------------------------------------------------------ logic
func _on_changed_text(_t: String) -> void:
	_validate()


func _on_changed_num(_v: Variant = null) -> void:
	_validate()


func _on_randomize() -> void:
	var r := RandomNumberGenerator.new()
	r.randomize()
	_seed.text = str(r.randi_range(1, 999999))
	_validate()


func _on_scale(i: int) -> void:
	ui_scale_changed.emit(float(ScaledLayer.SCALE_STEPS[i]))


func set_scale_index(s: float) -> void:
	if _scale_opt == null:
		return
	var vals: Array = ScaledLayer.SCALE_STEPS
	for i in vals.size():
		if is_equal_approx(float(vals[i]), s):
			_scale_opt.select(i)


## Builds the match config from the form. Returns {"cfg": Dictionary, "error": String}.
## G3a: sides/economy come from the slot table, victory fields from the victory builder.
func build_config() -> Dictionary:
	var cfg := SimWorld.default_config()
	var st := _seed.text.strip_edges()
	if not st.is_valid_int():
		return {"cfg": cfg, "error": "Seed must be a whole number."}
	cfg.seed = int(st)
	var ui_reason := ""
	var m := selected_map()
	cfg.map = String(m.id)
	if adv_opt != null and adv_opt.selected >= 0 and adv_opt.selected < _adv_ids.size():
		cfg.advancement = String(_adv_ids[adv_opt.selected])
	if setup != null:
		ui_reason = setup.apply(cfg, 8)
	if ui_reason == "" and cfg.sides.size() > int(m.get("max_sides", 4)):
		ui_reason = "%s holds at most %d sides." % [String(m.name), int(m.get("max_sides", 4))]
	if ui_reason == "" and not bool(m.get("present", true)):
		ui_reason = "%s is not available yet." % String(m.name)
	if victory != null:
		victory.apply(cfg)
	if setup != null and setup.has_method("finalize"):
		setup.finalize(cfg)   # G4e: a custom map file's victory / players override the form
	var err := SimWorld.validate_config(cfg)
	if err == "":
		err = ui_reason
	return {"cfg": cfg, "error": err}


func _validate() -> bool:
	if _summary == null:
		return false
	var r := build_config()
	var err := String(r.error)
	if err != "":
		_summary.text = "Cannot start: " + err
		_summary.add_theme_color_override("font_color", HT.RED)
		return false
	var cfg: Dictionary = r.cfg
	var prof: Dictionary = Content.rules().get("economy_profiles", {}).get(String(cfg.get("economy", "standard")), {})
	var m := selected_map()
	if setup != null and setup.get("browser") != null:
		# G4e: a custom map picked in the browser names the summary (the MapOption row stays: it is
		# synced with the browser's built-in rows and the stages UI playtest drives it)
		if setup.has_method("is_custom") and setup.is_custom():
			var cur: Dictionary = setup.browser.current
			m = {"name": String(cur.get("name", "Custom map")), "w": int(cur.get("w", 0)), "h": int(cur.get("h", 0))}
	var stages: Array = []
	for sd in cfg.sides:
		stages.append(str(int(sd.get("stage", 8))))
	_summary.text = "%s (%d x %d)  |  seed %d  |  %s economy  |  %s advancement  |  %s  |  Stages %s
%s" % [
		String(m.name), int(m.get("w", 0)), int(m.get("h", 0)), int(cfg.seed),
		String(prof.get("name", cfg.get("economy", ""))), String(cfg.get("advancement", "standard")).capitalize(),
		VictoryBuilder.describe(cfg), "/".join(stages), setup.describe(cfg) if setup != null else ""]
	_summary.add_theme_color_override("font_color", HT.GREEN)
	return true


## G3b: the picked map row ({id, name, w, h, max_sides, present}).
func selected_map() -> Dictionary:
	if map_opt != null and map_opt.selected >= 0 and map_opt.selected < _map_rows.size():
		return _map_rows[map_opt.selected]
	return G3bData.map_row("river_crossing_s")


func _on_start() -> void:
	if _validate():
		start_requested.emit(build_config().cfg)


func show_error(msg: String) -> void:
	_summary.text = "Cannot start: " + msg
	_summary.add_theme_color_override("font_color", HT.RED)


func _toggle_howto() -> void:
	_howto.visible = not _howto.visible
	_relayout()


func _toggle_load() -> void:
	_load_panel.visible = not _load_panel.visible
	_refresh_load()


func _refresh_load() -> void:
	if _load_panel == null:
		return
	for c in _load_panel.get_children():
		_load_panel.remove_child(c)
		c.queue_free()
	_load_note.text = "" if _save_system_ok else "Save system pending: loading is disabled."
	for slot in SAVE_SLOTS:
		var b := Button.new()
		var exists := FileAccess.file_exists(String(slot.path))
		b.text = "%s%s" % [slot.label, "" if exists else "  (empty)"]
		b.disabled = (not exists) or (not _save_system_ok)
		b.pressed.connect(func(): load_requested.emit(String(slot.path)))
		_load_panel.add_child(b)
