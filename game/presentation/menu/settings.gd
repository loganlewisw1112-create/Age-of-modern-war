extends Control
## G5 (UI5b) settings menu + persistent store (user://settings.cfg, ConfigFile).
##   Graphics: window mode, vsync, frame cap.   Game: default speed, edge-pan (+speed), health bars.
##   Keys: rebinding for every G5 command-card action (Hotkeys.ACTIONS; G1-G4 keys are fixed).
## Static store API (no instance needed): Settings.get_value(section, key), set_value(...), save(),
## get_bindings(), set_binding(action, key) -> "" | reason, reset_bindings(), apply_graphics(),
## apply_to_match(mv). Tests call Settings.use_path(<temp file>) and restore with Settings.use_path(Settings.DEFAULT_PATH).
## Consumers: match_view should call Settings.apply_to_match(self) at match start (edge-pan, speed);
## entity_layer reads Settings.health_bars() ("always" | "damaged" | "selected" | "off").

signal closed

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")

const DEFAULTS := {
	"graphics": {"window_mode": "windowed", "vsync": true, "max_fps": 0},
	"game": {"speed": 1.0, "edge_pan": true, "edge_pan_speed": 1.0, "health_bars": "damaged"},
}
const WINDOW_MODES := ["windowed", "borderless", "fullscreen"]
const FPS_CAPS := [0, 30, 60, 120, 144]
const SPEEDS := [1.0, 2.0, 3.0]
const HEALTH_BARS := ["always", "damaged", "selected", "off"]
const PAN_SPEEDS := [0.5, 0.75, 1.0, 1.5, 2.0]

const DEFAULT_PATH := "user://settings.cfg"
## Store state lives in Engine metadata, not static vars: a static var was seen to fall back to its
## initializer mid-run (test probe, 2026-10-25), which sent test writes to the real settings file.
const META_PATH := "ui5b_settings_path"
const META_CFG := "ui5b_settings_cfg"

var _capture := ""               # action waiting for a key press ("" = none)
var _key_btns: Dictionary = {}   # action -> Button
var _msg: Label
var panel: PanelContainer


# ------------------------------------------------------------------ static store
static func _path() -> String:
	return String(Engine.get_meta(META_PATH, DEFAULT_PATH))


static func _c() -> ConfigFile:
	var c: ConfigFile = Engine.get_meta(META_CFG) if Engine.has_meta(META_CFG) else null
	if c == null:
		c = ConfigFile.new()
		if FileAccess.file_exists(_path()):
			c.load(_path())
		Engine.set_meta(META_CFG, c)
	return c


## Point the store at another file and reload from it (tests / probe).
static func use_path(p: String) -> void:
	Engine.set_meta(META_PATH, p)
	reload()


static func current_path() -> String:
	return _path()


## Drop the cache (tests: reload from the file as a fresh game start would).
static func reload() -> void:
	if Engine.has_meta(META_CFG):
		Engine.remove_meta(META_CFG)
	Hotkeys.set_user_bindings(get_bindings())


static func get_value(section: String, key: String):
	var d = DEFAULTS.get(section, {}).get(key)
	return _c().get_value(section, key, d)


static func set_value(section: String, key: String, v) -> void:
	_c().set_value(section, key, v)


static func save() -> int:
	return _c().save(_path())


static func get_bindings() -> Dictionary:
	var out := {}
	if _c().has_section("keys"):
		for a in _c().get_section_keys("keys"):
			out[a] = String(_c().get_value("keys", a, ""))
	return out


static func set_binding(action: String, k: String) -> String:
	var err := Hotkeys.rebind_error(action, k)
	if err != "":
		return err
	_c().set_value("keys", action, k.to_upper())
	Hotkeys.set_user_bindings(get_bindings())
	return ""


static func reset_bindings() -> void:
	if _c().has_section("keys"):
		_c().erase_section("keys")
	Hotkeys.set_user_bindings({})


static func health_bars() -> String:
	return String(get_value("game", "health_bars"))


static func apply_graphics() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var m := String(get_value("graphics", "window_mode"))
	match m:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(get_value("graphics", "vsync")) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("graphics", "max_fps"))


## Match start: default speed and edge-pan (never re-enables edge-pan a tool run switched off).
static func apply_to_match(mv) -> void:
	if mv == null:
		return
	mv.set("speed", float(get_value("game", "speed")))
	if not bool(get_value("game", "edge_pan")):
		mv.set("_edge_pan_enabled", false)


# ------------------------------------------------------------------ menu
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel = UiKit.panel("modal")
	panel.name = "SettingsPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	UiKit.fit_register(panel, true)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UiKit.label("SETTINGS", "header")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UiKit.button("Close", "Esc", "Save and close the settings")
	close.name = "SettingsClose"
	close.pressed.connect(_close)
	head.add_child(close)
	var tabs := TabContainer.new()
	tabs.name = "SettingsTabs"
	v.add_child(tabs)
	tabs.add_child(_graphics_tab())
	tabs.add_child(_game_tab())
	tabs.add_child(_keys_tab())
	tabs.add_child(preload("res://presentation/audio/audio_tab.gd").build())  # G6.1 AUDIO61: Master/Battle/Radio/UI/Music + mute
	_msg = UiKit.label("", "warn")
	_msg.name = "SettingsMsg"
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(420, 0)
	v.add_child(_msg)


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 6)
	return g


func _option(g: GridContainer, title: String, nm: String, items: Array, texts: Array, cur, cb: Callable) -> OptionButton:
	g.add_child(UiKit.label(title))
	var o := OptionButton.new()
	o.name = nm
	o.custom_minimum_size = Vector2(200, UiKit.BTN_H)
	for i in items.size():
		o.add_item(String(texts[i]), i)
	var idx := 0
	for i in items.size():
		if str(items[i]) == str(cur):
			idx = i
	o.select(idx)
	o.item_selected.connect(func(i): cb.call(items[i]))
	g.add_child(o)
	return o


func _check(g: GridContainer, title: String, nm: String, cur: bool, cb: Callable) -> CheckButton:
	g.add_child(UiKit.label(title))
	var c := CheckButton.new()
	c.name = nm
	c.button_pressed = cur
	c.toggled.connect(cb)
	g.add_child(c)
	return c


func _graphics_tab() -> Control:
	var g := _grid()
	g.name = "Graphics"
	_option(g, "Window", "OptWindow", WINDOW_MODES, ["Windowed", "Borderless", "Fullscreen"],
		get_value("graphics", "window_mode"), func(x): _store("graphics", "window_mode", x, true))
	_check(g, "V-Sync", "OptVsync", bool(get_value("graphics", "vsync")), func(on): _store("graphics", "vsync", on, true))
	_option(g, "Frame cap", "OptFps", FPS_CAPS, ["Unlimited", "30", "60", "120", "144"],
		get_value("graphics", "max_fps"), func(x): _store("graphics", "max_fps", x, true))
	return g


func _game_tab() -> Control:
	var g := _grid()
	g.name = "Game"
	_option(g, "Default speed", "OptSpeed", SPEEDS, ["1x", "2x", "3x"], get_value("game", "speed"),
		func(x): _store("game", "speed", x, false))
	_check(g, "Edge-pan", "OptEdgePan", bool(get_value("game", "edge_pan")), func(on): _store("game", "edge_pan", on, false))
	_option(g, "Edge-pan speed", "OptPanSpeed", PAN_SPEEDS, ["50%", "75%", "100%", "150%", "200%"],
		get_value("game", "edge_pan_speed"), func(x): _store("game", "edge_pan_speed", x, false))
	_option(g, "Health bars", "OptHealth", HEALTH_BARS, ["Always", "Damaged units", "Selected only", "Off"],
		get_value("game", "health_bars"), func(x): _store("game", "health_bars", x, false))
	return g


func _keys_tab() -> Control:
	var v := VBoxContainer.new()
	v.name = "Keys"
	v.add_theme_constant_override("separation", 6)
	var tip := UiKit.label("Click a key, then press a letter. Keys shared only by cards that never show together are allowed.", "dim")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(420, 0)
	v.add_child(tip)
	var g := _grid()
	var acts: Array = Hotkeys.ACTIONS.keys()
	acts.sort_custom(func(a, b): return Hotkeys._order(a) < Hotkeys._order(b))
	for a in acts:
		g.add_child(UiKit.label(Hotkeys.label(String(a))))
		var b := Button.new()
		b.name = "Key_" + String(a)
		b.custom_minimum_size = Vector2(90, UiKit.BTN_H)
		b.text = Hotkeys.key(String(a))
		b.pressed.connect(_begin_capture.bind(String(a)))
		g.add_child(b)
		_key_btns[String(a)] = b
	var sc := UiKit.scroll(g, 260.0)
	sc.name = "KeysScroll"
	v.add_child(sc)
	var reset := UiKit.button("Reset keys", "", "Restore every default key")
	reset.name = "KeysReset"
	reset.pressed.connect(_on_reset)
	v.add_child(reset)
	return v


func _on_reset() -> void:
	reset_bindings()
	save()
	_refresh_keys()
	_msg.text = "Default keys restored."


func _store(section: String, key: String, v, gfx: bool) -> void:
	set_value(section, key, v)
	save()
	if gfx:
		apply_graphics()


func _refresh_keys() -> void:
	for a in _key_btns:
		(_key_btns[a] as Button).text = Hotkeys.key(String(a))


func _begin_capture(action: String) -> void:
	_capture = action
	(_key_btns[action] as Button).text = "press..."
	_msg.text = "Press a letter for %s (Esc cancels)." % Hotkeys.label(action)


## Key capture for rebinding; returns the error text ("" = bound). Public for tests.
func capture_key(keycode: int) -> String:
	var action := _capture
	_capture = ""
	if action == "":
		return "Nothing to rebind."
	var err := set_binding(action, OS.get_keycode_string(keycode))
	if err == "":
		save()
		_msg.text = "%s is now %s." % [Hotkeys.label(action), Hotkeys.key(action)]
	else:
		_msg.text = err
	_refresh_keys()
	return err


func begin_capture(action: String) -> void:
	_begin_capture(action)


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if _capture != "":
		if k.keycode == KEY_ESCAPE:
			_capture = ""
			_refresh_keys()
			_msg.text = ""
		else:
			capture_key(k.keycode)
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	save()
	closed.emit()
	queue_free()
