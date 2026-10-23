extends Node
## App root (owner: agent E / hud-menus). Main menu -> match (MatchView + HUD) -> pause / end screen.
## Build UI in code; keep .tscn files minimal. Contract: docs/CONTRACTS.md section 7.
##
## Command line (after `--`):
##   --autostart [--autostart-seed=N]    skip the menu and start the default match
##   --autoshot=ABS.png --autoshot-delay=4   save the viewport after N seconds, then quit (KEEP)
##   --debug-end=win|lose                force the end screen (debug)
##   --debug-select=engineers|barracks|hq   select entities / add a barracks (debug)
##   --debug-pause                       open the pause menu (debug)
##   --debug-menu-howto                  open the How to Play panel (debug)

const MatchViewScript = preload("res://presentation/match_view.gd")
const HudScript = preload("res://presentation/hud/hud.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const ScaledLayer = preload("res://presentation/hud/scaled_layer.gd")
const MainMenuScript = preload("res://presentation/menu/main_menu.gd")
const PauseMenuScript = preload("res://presentation/menu/pause_menu.gd")
const EndScreenScript = preload("res://presentation/menu/end_screen.gd")
const SAVE_SYSTEM := "res://sim/save_system.gd"
const QUICK_SAVE := "user://saves/quick.sav"

var match_view: Node = null
var hud: Node = null
var _menu_layer: Node = null
var _menu: Control = null
var _overlay_layer: Node = null
var _pause: Control = null
var _end: Control = null
var _end_shown: bool = false
var _end_dismissed: bool = false
var _prev_paused: bool = false
var _ui_scale: float = 1.0
var _esc_had_state: bool = false
var _end_check_acc: float = 0.0
var _args: Dictionary = {}


func _ready() -> void:
	_parse_args()
	_overlay_layer = ScaledLayer.new()
	_overlay_layer.layer = 30
	add_child(_overlay_layer)
	_overlay_layer.root.theme = HT.make_theme()
	_menu_layer = ScaledLayer.new()
	_menu_layer.layer = 20
	add_child(_menu_layer)
	_menu_layer.root.theme = HT.make_theme()
	if _args.has("autostart"):
		var cfg := SimWorld.default_config()
		if _args.has("autostart-seed"):
			cfg.seed = int(_args["autostart-seed"])
		start_match(cfg)
	else:
		show_menu()
	_setup_debug()
	_setup_autoshot()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = a
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			_args[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			_args[s] = "1"


# ------------------------------------------------------------------ flow
func show_menu() -> void:
	_teardown_match()
	_clear_overlays()
	if _menu != null:
		_menu.queue_free()
	_menu = MainMenuScript.new()
	_menu_layer.root.add_child(_menu)
	_menu.set_save_system_available(_save_system() != null)
	_menu.set_scale_index(_ui_scale)
	_menu.start_requested.connect(_on_menu_start)
	_menu.load_requested.connect(_on_load_requested)
	_menu.quit_requested.connect(func(): get_tree().quit())
	_menu.ui_scale_changed.connect(_set_ui_scale)
	_menu_layer.visible = true


func _on_menu_start(cfg: Dictionary) -> void:
	if not start_match(cfg) and _menu != null:
		_menu.show_error("The match could not be created. See the debugger output.")


## Starts a fresh match from a config. Returns false if the config is invalid.
func start_match(cfg: Dictionary) -> bool:
	var reason := SimWorld.validate_config(cfg)
	if reason != "":
		push_warning("start_match: " + reason)
		return false
	var w := SimWorld.new_match(cfg)
	if w == null:
		return false
	_begin_world(w)
	return true


func _begin_world(w: SimWorld) -> void:
	_teardown_match()
	_clear_overlays()
	_end_shown = false
	_end_dismissed = false
	match_view = MatchViewScript.new()
	match_view.world = w
	add_child(match_view)
	hud = HudScript.new()
	add_child(hud)
	hud.setup(match_view, _ui_scale)
	hud.menu_requested.connect(open_pause)
	if _menu != null:
		_menu.queue_free()
		_menu = null
	_menu_layer.visible = false


func _teardown_match() -> void:
	if hud != null:
		hud.queue_free()
		hud = null
	if match_view != null:
		match_view.queue_free()
		match_view = null


func _clear_overlays() -> void:
	if _pause != null:
		_pause.queue_free()
		_pause = null
	if _end != null:
		_end.queue_free()
		_end = null


func _set_ui_scale(s: float) -> void:
	_ui_scale = s
	_overlay_layer.set_ui_scale(s)
	_menu_layer.set_ui_scale(s)
	if hud != null:
		hud.set_ui_scale(s)


# ------------------------------------------------------------------ pause
func open_pause() -> void:
	if match_view == null or _pause != null or _end != null:
		return
	_prev_paused = bool(match_view.get("paused"))
	match_view.set("paused", true)
	if hud != null:
		hud.suppress_banner = true
	_pause = PauseMenuScript.new()
	_overlay_layer.root.add_child(_pause)
	_pause.set_save_system_available(_save_system() != null)
	_pause.set_scale_index(_ui_scale)
	_pause.resume_requested.connect(close_pause)
	_pause.save_requested.connect(_on_save_requested)
	_pause.load_requested.connect(_on_load_requested)
	_pause.menu_requested.connect(show_menu)
	_pause.ui_scale_changed.connect(_set_ui_scale)


func close_pause() -> void:
	if _pause != null:
		_pause.queue_free()
		_pause = null
	if hud != null:
		hud.suppress_banner = false
	if match_view != null:
		match_view.set("paused", _prev_paused)


# ------------------------------------------------------------------ save / load
func _save_system() -> Variant:
	if ResourceLoader.exists(SAVE_SYSTEM):
		return load(SAVE_SYSTEM)
	return null


func _on_save_requested(path: String) -> void:
	var msg := save_to(path)
	if _pause != null:
		_pause.set_status("Saved." if msg == "" else "Save failed: " + msg, msg == "")


## Returns "" on success, else a reason.
func save_to(path: String) -> String:
	var S = _save_system()
	if S == null:
		return "Save system pending."
	if match_view == null:
		return "No match running."
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	var r = S.save(match_view.world, path)
	return String(r) if r != null else ""


func _on_load_requested(path: String) -> void:
	var msg := load_from(path)
	if msg != "":
		if _pause != null:
			_pause.set_status("Load failed: " + msg, false)
		elif _menu != null:
			_menu.show_error("Load failed: " + msg)


## Returns "" on success, else a reason. Rebuilds the MatchView around the loaded world.
func load_from(path: String) -> String:
	var S = _save_system()
	if S == null:
		return "Save system pending."
	if not FileAccess.file_exists(path):
		return "No save file at %s." % path
	var w = S.load(path)
	if w == null or not (w is SimWorld):
		return "The save file is missing, corrupt or from an unsupported version."
	_begin_world(w)
	return ""


# ------------------------------------------------------------------ end of match
func _process(delta: float) -> void:
	if match_view == null or _end_shown:
		return
	_end_check_acc += delta
	if _end_check_acc < 0.25:
		return
	_end_check_acc = 0.0
	var w := match_view.get("world") as SimWorld
	if w != null and bool(w.match_state.get("ended", false)):
		var pf := int(match_view.get("player_fid"))
		_show_end(int(w.match_state.get("winner", -1)) == pf, w)


func _show_end(won: bool, w: SimWorld) -> void:
	_end_shown = true
	if _end != null:
		_end.queue_free()
	var pf := int(match_view.get("player_fid"))
	var st: Dictionary = w.factions[pf].stats if w.factions.has(pf) else {}
	var reason := String(w.match_state.get("reason", ""))
	_end = EndScreenScript.new()
	_overlay_layer.root.add_child(_end)
	_end.setup({
		"won": won, "clock": HT.clock_text(w.tick),
		"trained": int(st.get("trained", 0)), "built": int(st.get("built", 0)),
		"lost": int(st.get("lost", 0)), "killed": int(st.get("killed", 0)),
		"subtitle": "The enemy HQ has fallen." if won else "Your HQ has been destroyed." if reason == "hq_elimination" else "The match has ended.",
	})
	_end.continue_requested.connect(_on_end_continue)
	_end.menu_requested.connect(show_menu)


func _on_end_continue() -> void:
	if _end != null:
		_end.queue_free()
		_end = null
	_end_dismissed = true


# ------------------------------------------------------------------ input
func _placing() -> bool:
	if match_view == null:
		return false
	if match_view.has_method("is_placing"):
		return bool(match_view.is_placing())
	for p in ["placing", "placement_def", "placing_def", "build_def"]:
		var v = match_view.get(p)
		if v != null and (typeof(v) != TYPE_STRING or v != "") and (typeof(v) != TYPE_BOOL or v):
			return true
	return false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _pause != null:
			close_pause()
			get_viewport().set_input_as_handled()
			return
		# Remember whether Esc has a job in the match itself (cancel placement / deselect).
		var sel = match_view.get("selection") if match_view != null else null
		_esc_had_state = _placing() or (sel != null and not sel.is_empty())


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if match_view == null:
		return
	match event.keycode:
		KEY_ESCAPE:
			if _end == null and not _esc_had_state:
				open_pause()
		KEY_F5:
			var msg := save_to(QUICK_SAVE)
			_notify("Quick-saved." if msg == "" else "Quick-save failed: " + msg, HT.GREEN if msg == "" else HT.RED)
		KEY_F9:
			var msg2 := load_from(QUICK_SAVE)
			if msg2 != "":
				_notify("Quick-load failed: " + msg2, HT.RED)
			else:
				_notify("Quick-loaded.", HT.GREEN)


func _notify(text: String, color: Color) -> void:
	if hud != null and hud.has_method("notify"):
		hud.notify(text, color)


# ------------------------------------------------------------------ debug + autoshot
func _setup_debug() -> void:
	if _args.has("debug-menu-howto") and _menu != null:
		_menu._toggle_howto()
	if match_view == null:
		return
	if _args.has("debug-select"):
		_debug_select(String(_args["debug-select"]))
	if _args.has("debug-pause"):
		await get_tree().create_timer(1.5).timeout
		open_pause()
	if _args.has("debug-end"):
		await get_tree().create_timer(1.5).timeout
		if match_view != null:
			_show_end(String(_args["debug-end"]) == "win", match_view.world)


func _debug_select(what: String) -> void:
	await get_tree().create_timer(0.6).timeout
	if match_view == null:
		return
	var w: SimWorld = match_view.world
	var pf := int(match_view.get("player_fid"))
	var ids: Array = []
	if what == "engineers":
		for u in w.units_of(pf):
			if u.def == "engineer":
				ids.append(int(u.id))
	elif what == "barracks" or what == "hq":
		if what == "barracks":
			var hq: Dictionary = w.buildings_of(pf, "hq")[0]
			var origin: Vector2i = hq.cell + Vector2i(6, -1)
			var bid := w.spawn_building("barracks", pf, origin, true)
			ids.append(bid)
			for item in ["rifle_squad", "at_team", "recon"]:
				match_view.issue({"type": "queue_unit", "building_id": bid, "item": item})
		else:
			ids.append(int(w.buildings_of(pf, "hq")[0].id))
	_select(ids)


func _select(ids: Array) -> void:
	if match_view.has_method("select_ids"):
		match_view.select_ids(ids)
	else:
		var typed: Array[int] = []
		for i in ids:
			typed.append(int(i))
		match_view.selection = typed
		if match_view.has_signal("selection_changed"):
			match_view.selection_changed.emit()


## Debug hook (KEEP: used by every visual agent and the orchestrator):
##   godot --path game -- --autoshot=C:/abs/out.png --autoshot-delay=4 [--autostart]
## Saves the viewport after N seconds of real time, then quits.
func _setup_autoshot() -> void:
	var shot := String(_args.get("autoshot", ""))
	var delay := float(_args.get("autoshot-delay", 4.0))
	if shot == "":
		return
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot)
	print("AUTOSHOT saved ", shot)
	get_tree().quit()
