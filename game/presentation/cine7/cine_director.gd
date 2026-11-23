extends CanvasLayer
## G7 (CINE7): Last Protocol cinematic director (master scope 13.1, 13.5). Plays one cinematic module's shot list
## (presentation/cine7/cine_*.gd, format in cine_shot.gd) over the real map: drives the match camera along the
## shot paths, grades the screen, draws world-space effects (cine_fx.gd), title cards, teletype, countdown digits,
## the Remembered roll, letterbox bars, fades, and a skip prompt (Space / Esc / Enter, or the on-screen button).
##
## SIM CONTRACT (decided): the match is PAUSED while a cinematic plays (match_view.paused = true; the sim does not
## step) and the previous pause state is restored when it ends or is skipped. The director only writes presentation
## state (camera, layer visibility, the HUD root's visibility, match_view.paused / _edge_pan_enabled); it never
## writes the world, so the state hash at any tick is identical with cinematics on, off or skipped (test_cine7).
## Before Last Protocol's setup has run (the first sim tick), the opening holds on black and lets the sim reach it.
##
## Music: at every shot with a `cue` the director calls get_tree().call_group("cine7_music", "cine_cue", cue) and
## "cine_end" when it finishes (fact cine.cues; AUDIO7 adds its music node to that group).

signal finished(skipped: bool)

const D = preload("res://presentation/cine7/cine_data.gd")
const S = preload("res://presentation/cine7/cine_shot.gd")
const CineFx = preload("res://presentation/cine7/cine_fx.gd")
const CineUi = preload("res://presentation/cine7/cine_ui.gd")
const ViewUtil = preload("res://presentation/view/view_util.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Settings = preload("res://presentation/menu/settings.gd")
const MUSIC_GROUP := "cine7_music"
const OPEN_MAX_S := 12.0       # the opening plays only if the run is this young (sim seconds since LP setup)
const SKIP_FADE_S := 0.35

## Runs whose opening already played this session (seed -> true): a HUD rebuild or a load never replays it.
static var opened: Dictionary = {}
static var force_play := false   # playtest / tests: ignore the skip setting

var mv: Node = null
var hud_root: Control = null
var kind := ""
var result: Dictionary = {}
var data: Dictionary = {}
var shots: Array = []
var idx := -1
var t := 0.0                 # time in the current shot
var elapsed := 0.0
var total := 0.0
var waiting := false         # opening before LP setup: black hold
var done := false
var skipped := false
var cues: Array = []         # cues posted (tests / playtest log)
var on_done: Callable = Callable()
var _skip_t := -1.0
var _was_paused := false
var _was_edge := true
var _fog_vis := true
var _fx: Node2D = null
var ui = null                # CineUi (built when inside the tree)


# ---------------------------------------------------------------- settings
static func skip_intro_setting() -> bool:
	var v = Settings.get_value("last_protocol", "skip_intro")
	return v != null and bool(v)


static func set_skip_intro(on: bool) -> void:
	Settings.set_value("last_protocol", "skip_intro", on)
	Settings.save()


## False in automated runs (UI playtests, autostart / bench / fps runs, headless) so other agents' flows and soaks
## never sit behind a paused cinematic; the cine7 flow and tests set force_play.
static func auto_ok() -> bool:
	if force_play:
		return true
	if DisplayServer.get_name() == "headless":
		return false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui-playtest") or a.begins_with("--autostart") or a.begins_with("--fps") or a.begins_with("--autoshot") 				or a.begins_with("--demo-script") or a.begins_with("--spawn-test"):
			return false
	return true


## True when a Last Protocol run is starting and its opening has not played yet.
static func want_opening(w: SimWorld) -> bool:
	if w == null or not LastProtocol.active(w) or opened.has(w.seed_value) or not auto_ok():
		return false
	if skip_intro_setting() and not force_play:
		return false
	var s = LastProtocol.st(w)
	if s is Dictionary:
		if bool(s.get("ended", false)):
			return false
		if float(w.tick - int(s.get("t0", 0))) * SimWorld.DT > OPEN_MAX_S:
			return false
	elif float(w.tick) * SimWorld.DT > OPEN_MAX_S:
		return false
	return true


## Starts a cinematic: kind "opening" or an LP ending id. Returns the director (already in the tree when mv is).
static func play(match_view: Node, root: Control, what: String, res: Dictionary = {}, cb: Callable = Callable()) -> Node:
	var dd = (load("res://presentation/cine7/cine_director.gd") as GDScript).new()
	dd.mv = match_view
	dd.hud_root = root
	dd.kind = what
	dd.result = res
	dd.on_done = cb
	var w: SimWorld = match_view.get("_world") as SimWorld if match_view != null else null
	if what == "opening" and w != null:
		opened[w.seed_value] = true
	if match_view != null and match_view.is_inside_tree():
		match_view.get_tree().root.add_child(dd)
		match_view.tree_exiting.connect(func(): if is_instance_valid(dd): dd.queue_free())
	dd.begin()
	return dd


func _world() -> SimWorld:
	return mv.get("_world") as SimWorld if mv != null else null


func _ready() -> void:
	layer = 100
	name = "CineDirector"
	ui = CineUi.new()
	add_child(ui)
	ui.skip_pressed.connect(skip)
	if idx >= 0 and idx < shots.size():
		ui.on_shot(shots[idx], data)


func begin() -> void:
	_was_paused = bool(mv.get("paused")) if mv != null else false
	_was_edge = bool(mv.get("_edge_pan_enabled")) if mv != null and mv.get("_edge_pan_enabled") != null else true
	if hud_root != null:
		hud_root.visible = false
	if mv != null and mv.get("_edge_pan_enabled") != null:
		mv.set("_edge_pan_enabled", false)
	var fl = mv.get("fog_layer") if mv != null else null
	_fog_vis = fl.visible if fl is CanvasItem else true
	var w := _world()
	var s = LastProtocol.st(w) if w != null else null
	if kind == "opening" and w != null and not (s is Dictionary and (s as Dictionary).has("base")):
		waiting = true   # let the sim reach LP setup (one tick) on black
		return
	_load_shots()


func _load_shots() -> void:
	waiting = false
	if mv != null:
		if mv.has_method("join_sim"):
			mv.join_sim()
		mv.set("paused", true)
	data = D.gather(_world(), result)
	var w := _world()
	var s = LastProtocol.st(w) if w != null else null
	if s is Dictionary and float(s.get("cd_rate", 0.0)) > 0.0:
		data.eta_min = int(float(s.get("cd_left", 0.0)) / float(s.cd_rate) / 60.0)
	var mod := D.module(kind)
	shots = mod.call("shots", data) if mod != null else []
	total = S.total(shots)
	if mv != null and mv.is_inside_tree() and mv.get("camera") != null:
		_fx = CineFx.new()
		_fx.hm = mv.camera.height_map() if mv.camera.has_method("height_map") else {}
		mv.add_child(_fx)
	_enter(0)


func _enter(i: int) -> void:
	idx = i
	t = 0.0
	if i >= shots.size():
		_finish()
		return
	var sh: Dictionary = shots[i]
	if sh.has("cue"):
		cues.append(String(sh.cue))
		if is_inside_tree():
			get_tree().call_group(MUSIC_GROUP, "cine_cue", String(sh.cue))
	var fl = mv.get("fog_layer") if mv != null else null
	if fl is CanvasItem:
		(fl as CanvasItem).visible = false   # cinematics show the real map un-fogged (display only; restored after)
	if _fx != null:
		_fx.set_shot(sh.get("fx", []), float(sh.dur))
		_fx.visible = not bool(sh.get("black", false))
	if ui != null:
		ui.on_shot(sh, data)
	_camera()


func _camera() -> void:
	if idx < 0 or idx >= shots.size() or mv == null or mv.get("camera") == null:
		return
	var c := S.cam_at(shots[idx], t)
	if c.is_empty():
		return
	var cam = mv.camera
	var hm: Dictionary = _fx.hm if _fx != null else {}
	cam.position = ViewUtil.world_to_screen_h(hm, c.pos) if not hm.is_empty() else ViewUtil.iso(c.pos)
	cam.zoom = Vector2(c.zoom, c.zoom)


func _process(delta: float) -> void:
	advance(delta)


## One frame of the cinematic (tests call it directly with any dt).
func advance(dt: float) -> void:
	if done:
		return
	if waiting:
		# G7 PERF7D (PERF7C need seq 1956): mv.world joins an in-flight threaded step (the frame waits for the whole
		# step); while a step runs keep the waiting frame and look again on a frame with the world free (hand-over)
		if mv != null and mv.has_method("sim_busy") and bool(mv.sim_busy()):
			if ui != null:
				ui.waiting_frame(dt)
			return
		var w := _world()
		var s = LastProtocol.st(w) if w != null else null
		if s is Dictionary and (s as Dictionary).has("base"):
			_load_shots()
		elif ui != null:
			ui.waiting_frame(dt)
		return
	if _skip_t >= 0.0:
		_skip_t += dt
		if ui != null:
			ui.fade_black(clampf(_skip_t / SKIP_FADE_S, 0.0, 1.0))
		if _skip_t >= SKIP_FADE_S:
			_finish()
		return
	t += dt
	elapsed += dt
	while idx < shots.size() and t >= float(shots[idx].dur):
		var over := t - float(shots[idx].dur)
		_enter(idx + 1)
		if done:
			return
		t = over
	_camera()
	if _fx != null:
		_fx.advance(t)
	if ui != null and idx < shots.size():
		ui.frame(shots[idx], t, elapsed)


func skip() -> void:
	if done or _skip_t >= 0.0:
		return
	skipped = true
	if waiting:
		_load_shots()
	_skip_t = 0.0 if ui != null else SKIP_FADE_S


func _input(event: InputEvent) -> void:
	if done:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
			skip()
		elif ui != null:
			ui.show_hint()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and ui != null:
		ui.show_hint()


func _finish() -> void:
	if done:
		return
	done = true
	# the opening ends on the hand-over framing even when skipped
	if kind == "opening" and not shots.is_empty() and mv != null and mv.get("camera") != null:
		idx = shots.size() - 1
		t = float(shots[idx].dur)
		_camera()
	if mv != null:
		mv.set("paused", _was_paused)
		if mv.get("_edge_pan_enabled") != null:
			mv.set("_edge_pan_enabled", _was_edge)
		var fl = mv.get("fog_layer")
		if fl is CanvasItem:
			(fl as CanvasItem).visible = _fog_vis
	if hud_root != null:
		hud_root.visible = true
	if _fx != null:
		_fx.queue_free()
		_fx = null
	cues.append("cine_end")
	if is_inside_tree():
		get_tree().call_group(MUSIC_GROUP, "cine_cue", "cine_end")
	finished.emit(skipped)
	if on_done.is_valid():
		on_done.call(skipped)
	if is_inside_tree():
		queue_free()
