extends Control
## Main menu + skirmish setup (owner: agent E). Built in code. Emits signals; main.gd acts on them.

signal start_requested(cfg: Dictionary)
signal load_requested(path: String)
signal quit_requested
signal ui_scale_changed(s: float)

const HT = preload("res://presentation/hud/hud_theme.gd")
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
  Select Work Crew (engineers): the BUILD panel appears bottom right.
  Click a structure (or press its hotkey), then click the map to place it.
  Select your HQ or a Barracks to train units. Locked buttons say why.

START HERE
  1. Build a Generator Substation (power).   2. Build a Barracks.
  3. Train a Rifle Squad.                    4. Find and destroy the enemy HQ.
  Engineers right-clicking salvage or ore will gather it."""

var _seed: LineEdit
var _credits: SpinBox
var _difficulty: OptionButton
var _victory: OptionButton
var _stage: OptionButton
var _summary: Label
var _scale_opt: OptionButton
var _load_panel: VBoxContainer
var _howto: PanelContainer
var _load_note: Label
var _save_system_ok: bool = false
var _stage_ids: Array = []
var _diffs: Array = []
var _victories: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_validate()


func set_save_system_available(ok: bool) -> void:
	_save_system_ok = ok
	_refresh_load()


func _build() -> void:
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

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	center.add_child(row)

	# ---- left column: title + buttons
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	left.add_child(HT.make_label("RTS", HT.OLIVE, 22))
	left.add_child(HT.make_label("AGE OF\nMODERN WAR", HT.AMBER, 46))
	left.add_child(HT.make_label("First playable slice: River Crossing", HT.DIM, 14))
	left.add_child(_spacer(18))
	var start := _menu_button("Start Skirmish", left)
	start.pressed.connect(_on_start)
	var load_b := _menu_button("Load Game", left)
	load_b.pressed.connect(_toggle_load)
	var how := _menu_button("How to Play", left)
	how.pressed.connect(_toggle_howto)
	var quit := _menu_button("Quit", left)
	quit.pressed.connect(func(): quit_requested.emit())
	_load_panel = VBoxContainer.new()
	_load_panel.visible = false
	_load_panel.add_theme_constant_override("separation", 4)
	left.add_child(_load_panel)
	_load_note = HT.make_label("", HT.YELLOW, 14)
	left.add_child(_load_note)
	left.add_child(_spacer(10))
	var sc := HBoxContainer.new()
	left.add_child(sc)
	sc.add_child(HT.make_label("UI scale  ", HT.DIM, 14))
	_scale_opt = OptionButton.new()
	for s in ["1.0", "1.25", "1.5"]:
		_scale_opt.add_item(s)
	_scale_opt.item_selected.connect(_on_scale)
	sc.add_child(_scale_opt)

	# ---- right column: skirmish setup
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 0)
	row.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	panel.add_child(pv)
	pv.add_child(HT.make_label("SKIRMISH SETUP", HT.AMBER, 20))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	pv.add_child(grid)

	grid.add_child(HT.make_label("Map", HT.DIM))
	grid.add_child(HT.make_label("River Crossing (96 x 96)", HT.TEXT))

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

	grid.add_child(HT.make_label("Starting credits", HT.DIM))
	_credits = SpinBox.new()
	_credits.min_value = 0
	_credits.max_value = 50000
	_credits.step = 500
	_credits.value = int(Content.rules().defaults.starting_credits) if Content.rules().has("defaults") else 5000
	_credits.value_changed.connect(_on_changed_num)
	grid.add_child(_credits)

	grid.add_child(HT.make_label("AI difficulty", HT.DIM))
	_difficulty = OptionButton.new()
	var diffs: Dictionary = Content.rules().get("ai_difficulties", {})
	for d in diffs:
		_diffs.append(String(d))
		_difficulty.add_item(String(d).capitalize())
	var def_diff := String(Content.rules().get("defaults", {}).get("ai_difficulty", "normal"))
	_difficulty.select(maxi(0, _diffs.find(def_diff)))
	_difficulty.item_selected.connect(_on_changed_num)
	grid.add_child(_difficulty)

	grid.add_child(HT.make_label("Victory", HT.DIM))
	_victory = OptionButton.new()
	for v in Content.rules().get("victory_types", []):
		_victories.append(String(v))
		_victory.add_item("HQ elimination" if v == "hq_elimination" else "Endless")
	_victory.item_selected.connect(_on_changed_num)
	grid.add_child(_victory)

	grid.add_child(HT.make_label("Stage", HT.DIM))
	_stage = OptionButton.new()
	_stage.custom_minimum_size = Vector2(380, 0)
	var sel_idx := 0
	for st in Content.stages():
		var playable: bool = bool(st.get("playable_now", false))
		_stage.add_item("Stage %d  %s%s" % [int(st.id), String(st.working_name), "" if playable else "   (not in this slice)"])
		var idx := _stage.item_count - 1
		_stage_ids.append(int(st.id))
		if not playable:
			_stage.set_item_disabled(idx, true)
		elif int(st.id) == 8:
			sel_idx = idx
	_stage.select(sel_idx)
	_stage.item_selected.connect(_on_changed_num)
	grid.add_child(_stage)

	pv.add_child(HSeparator.new())
	_summary = HT.make_label("", HT.TEXT, 14)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(540, 40)
	pv.add_child(_summary)
	var go := Button.new()
	go.text = "START MATCH"
	go.custom_minimum_size = Vector2(0, 46)
	go.pressed.connect(_on_start)
	pv.add_child(go)

	# ---- how to play overlay
	_howto = PanelContainer.new()
	_howto.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_howto.visible = false
	add_child(_howto)
	var hv := VBoxContainer.new()
	_howto.add_child(hv)
	hv.add_child(HT.make_label("HOW TO PLAY", HT.AMBER, 20))
	var txt := HT.make_label(HOW_TO_PLAY, HT.TEXT, 14)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	txt.add_theme_font_override("font", mono)
	hv.add_child(txt)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_toggle_howto)
	hv.add_child(close)
	_howto.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_refresh_load()


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
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
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
	var vals := [1.0, 1.25, 1.5]
	ui_scale_changed.emit(vals[i])


func set_scale_index(s: float) -> void:
	if _scale_opt == null:
		return
	var vals := [1.0, 1.25, 1.5]
	for i in vals.size():
		if is_equal_approx(vals[i], s):
			_scale_opt.select(i)


## Builds the match config from the form. Returns {"cfg": Dictionary, "error": String}.
func build_config() -> Dictionary:
	var cfg := SimWorld.default_config()
	var st := _seed.text.strip_edges()
	if not st.is_valid_int():
		return {"cfg": cfg, "error": "Seed must be a whole number."}
	cfg.seed = int(st)
	cfg.victory = _victories[_victory.selected] if _victory.selected >= 0 and _victory.selected < _victories.size() else "hq_elimination"
	cfg.ai_difficulty = _diffs[_difficulty.selected] if _difficulty.selected >= 0 and _difficulty.selected < _diffs.size() else "normal"
	var stage_id: int = _stage_ids[_stage.selected] if _stage.selected >= 0 else 8
	for s in cfg.sides:
		s.credits = int(_credits.value)
		s.stage = stage_id
	return {"cfg": cfg, "error": SimWorld.validate_config(cfg)}


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
	_summary.text = "River Crossing  |  seed %d  |  %d credits each  |  AI %s  |  %s  |  Stage %d (Modern Nations)" % [
		int(cfg.seed), int(cfg.sides[0].credits), String(cfg.ai_difficulty),
		"HQ elimination" if cfg.victory == "hq_elimination" else "Endless", int(cfg.sides[0].stage)]
	_summary.add_theme_color_override("font_color", HT.GREEN)
	return true


func _on_start() -> void:
	if _validate():
		start_requested.emit(build_config().cfg)


func show_error(msg: String) -> void:
	_summary.text = "Cannot start: " + msg
	_summary.add_theme_color_override("font_color", HT.RED)


func _toggle_howto() -> void:
	_howto.visible = not _howto.visible


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
