extends Node
## App root (owner: agent E / hud-menus). Main menu -> match (MatchView + HUD) -> pause / end screen.
## Build UI in code; keep .tscn files minimal. Contract: docs/CONTRACTS.md section 7.
##
## Command line (after `--`):
##   --autostart [--autostart-seed=N]    skip the menu and start the default match
##   --autostart-factions=human_b,machine[,human_a]   (G3a) one side per faction, side 0 = you
##   --autostart-teams=0,1,1             (G3a) team per side;  --autostart-victory=territory
##   --autostart-map=industrial_heartland_m   (G3b) map id (alias --map=<id>)
##   --autostart-stages=7,8,9            (G3b) stage per side (adds AI sides if there are more stages)
##   --autostart-advancement=free|standard|simulation   (G3b)
##   --player-ai                         (with --autostart) the AI plays side 0 too (demo)
##   --autoshot=ABS.png --autoshot-delay=4   save the viewport after N seconds, then quit (KEEP)
##   --debug-end=win|lose                force the end screen (debug)
##   --debug-select=engineers|barracks|hq   select entities / add a barracks (debug)
##   --debug-pause                       open the pause menu (debug)
##   --debug-menu-howto                  open the How to Play panel (debug)
##   --editor [--editor-open=user://maps/x.rtsmap]   (G4e) open the map editor directly
##   --editor-demo=ABS_DIR               (G4e) scripted editor tour: one screenshot per tab, then quit

const MatchViewScript = preload("res://presentation/match_view.gd")
const HudScript = preload("res://presentation/hud/hud.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const ScaledLayer = preload("res://presentation/hud/scaled_layer.gd")
const MainMenuScript = preload("res://presentation/menu/main_menu.gd")
const PauseMenuScript = preload("res://presentation/menu/pause_menu.gd")
const EndScreenScript = preload("res://presentation/menu/end_screen.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")
const G3Score = preload("res://presentation/hud/g3_score.gd")
const MapEditorScene = preload("res://presentation/editor/editor_scene.gd")
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
var _editor: Node = null          # G4e map editor (ED1); kept alive (hidden) during a test play
var _editor_test := false


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
		_apply_autostart_g3(cfg)
		if _args.has("player-ai"):
			# Debug/demo: the AI also plays the player's side (rendered AI-vs-AI match).
			cfg.sides[0].ai = true
		start_match(cfg)
		if _args.has("speed") and match_view != null:
			match_view.speed = clampf(float(_args["speed"]), 0.25, 12.0)  # demo/debug only
	elif _args.has("editor") or _args.has("editor-demo"):
		open_editor()
		if _args.has("editor-open"):
			_editor.open_path(String(_args["editor-open"]))
		if _args.has("editor-demo"):
			var demo = load("res://presentation/editor/editor_demo.gd").new()
			demo.editor = _editor
			demo.shot_dir = String(_args["editor-demo"])
			add_child(demo)
	else:
		show_menu()
	_setup_debug()
	_setup_autoshot()
	if _args.has("ui-playtest"):
		# UI-01 playtest: synthetic input events through the real viewport (tools/ui_playtest.gd).
		var pt = load("res://tools/ui_playtest.gd").new()
		pt.main = self
		pt.shot_dir = String(_args["ui-playtest"])
		pt.faction = String(_args.get("ui-playtest-faction", ""))  # G3a: human_b | machine
		pt.stages_flow = _args.has("ui-playtest-stages")  # G3b: map + stage pick, research, gates
		add_child(pt)


## G3a debug: --autostart-factions / --autostart-teams / --autostart-victory.
func _apply_autostart_g3(cfg: Dictionary) -> void:
	if _args.has("autostart-factions"):
		var facs: PackedStringArray = String(_args["autostart-factions"]).split(",", false)
		var proto: Dictionary = cfg.sides[0]
		var sides: Array = []
		for i in facs.size():
			var s: Dictionary = proto.duplicate(true)
			s.faction = facs[i]
			s.ai = i != 0
			s.team = i
			s.name = "You" if i == 0 else "%s AI" % String(Content.faction(facs[i]).get("name", facs[i])).get_slice(" ", 0)
			sides.append(s)
		cfg.sides = sides
	if _args.has("autostart-teams"):
		var ts: PackedStringArray = String(_args["autostart-teams"]).split(",", false)
		for i in mini(ts.size(), cfg.sides.size()):
			cfg.sides[i].team = int(ts[i])
	if _args.has("autostart-victory"):
		cfg.victory = String(_args["autostart-victory"])
	# G3b (UI4): map, per-side stages, advancement rules
	var map_id := String(_args.get("autostart-map", _args.get("map", "")))
	if map_id != "":
		cfg.map = map_id
	if _args.has("autostart-stages"):
		var st: PackedStringArray = String(_args["autostart-stages"]).split(",", false)
		while cfg.sides.size() < st.size():
			var extra: Dictionary = (cfg.sides[cfg.sides.size() - 1] as Dictionary).duplicate(true)
			extra.ai = true
			extra.team = cfg.sides.size()
			extra.name = "AI (%d)" % (cfg.sides.size() + 1)
			cfg.sides.append(extra)
		for i in mini(st.size(), cfg.sides.size()):
			cfg.sides[i].stage = int(st[i])
	if _args.has("autostart-advancement"):
		cfg.advancement = String(_args["autostart-advancement"])


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
	if _editor != null and _editor_test:
		# G4e: leaving a test play (pause menu / end screen "Main menu") goes back to the editor
		_editor_test = false
		_editor.set_active(true)
		_menu_layer.visible = false
		return
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
	if _menu.has_signal("editor_requested"):
		_menu.editor_requested.connect(open_editor)
	_menu_layer.visible = true


# ------------------------------------------------------------------ G4e map editor (ED1)
func open_editor() -> void:
	_teardown_match()
	_clear_overlays()
	if _menu != null:
		_menu.queue_free()
		_menu = null
	_menu_layer.visible = false
	if _editor != null:
		_editor.queue_free()
	_editor = MapEditorScene.new()
	_editor.ui_scale = _ui_scale
	add_child(_editor)
	_editor.exit_requested.connect(_close_editor)
	_editor.test_play_requested.connect(_editor_test_play)
	_editor_test = false


func _close_editor() -> void:
	if _editor != null:
		_editor.queue_free()
		_editor = null
	_editor_test = false
	show_menu()


## Test Play (hook for ED2): start cfg, hide the editor, come back to it when the match is left.
func _editor_test_play(cfg: Dictionary) -> void:
	if _editor == null:
		return
	if start_match(cfg):
		_editor.set_active(false)
		_editor_test = true
	else:
		_editor.status("Test Play could not start the match (see the debugger output).", HT.RED)


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
	_pause.editor_test = _editor_test and _editor != null
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
	if match_view.has_method("sim_busy") and match_view.sim_busy():
		return   # G4 THREAD CR 1462: never read the world while a worker step is in flight
	var w := match_view.get("world") as SimWorld
	if w != null and bool(w.match_state.get("ended", false)):
		var pf := int(match_view.get("player_fid"))
		_show_end(bool(G3Score.end_info(w, pf).won), w)


func _show_end(won: bool, w: SimWorld) -> void:
	_end_shown = true
	if _end != null:
		_end.queue_free()
	var pf := int(match_view.get("player_fid"))
	var st: Dictionary = w.factions[pf].stats if w.factions.has(pf) else {}
	var info: Dictionary = G3Score.end_info(w, pf)
	_end = EndScreenScript.new()
	_overlay_layer.root.add_child(_end)
	_end.setup({
		"won": won, "clock": HT.clock_text(w.tick),
		"trained": int(st.get("trained", 0)), "built": int(st.get("built", 0)),
		"lost": int(st.get("lost", 0)), "killed": int(st.get("killed", 0)),
		"subtitle": String(info.subtitle) if bool(w.match_state.get("ended", false)) else ("Debug end screen."),
		"teams": info.teams,
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
	# G3a: role-based (no def names): builders = can_build units, barracks/hq = faction roles
	var hq_def := G3.role_def(w, pf, "hq")
	if what == "engineers":
		for u in w.units_of(pf):
			if bool(Content.unit(String(u.def)).get("can_build", false)):
				ids.append(int(u.id))
	elif (what == "barracks" or what == "hq") and not w.buildings_of(pf, hq_def).is_empty():
		var hq: Dictionary = w.buildings_of(pf, hq_def)[0]
		if what == "barracks":
			var origin: Vector2i = hq.cell + Vector2i(6, -1)
			var bdef := G3.role_def(w, pf, "barracks")
			var bid := w.spawn_building(bdef, pf, origin, true)
			ids.append(bid)
			for item in Content.building(bdef).get("produces", []):
				match_view.issue({"type": "queue_unit", "building_id": bid, "item": String(item)})
		else:
			ids.append(int(hq.id))
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
