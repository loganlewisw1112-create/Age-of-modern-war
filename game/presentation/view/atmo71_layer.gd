extends Node2D
## G7.1 E1 atmosphere draw: parachute flares + optional ash tint. Camera shake on MatchView.camera.
## Snapshot provider "atmo71"; null when idle. Never mv.world from refresh.

const RenderSnap = preload("res://sim/render_snap.gd")
const KEY := "atmo71"

static var _reg_owner := 0
static var _cache: Variant = null
static var _cache_tick := -999
const CACHE_EVERY := 3

var mv: Node = null
var _flares: Array = []
var _ash := false
var _shake := 0.0
var _sig := -1


func _init() -> void:
	_reg_owner = get_instance_id()
	RenderSnap.register_g71(KEY, Callable(get_script(), "snap"))


func _exit_tree() -> void:
	if _reg_owner == get_instance_id():
		RenderSnap.unregister_g71(KEY)


static func snap(w, _sn: Dictionary):
	if not w.sys_state.has("lp"):
		return null
	if _cache != null and w.tick - _cache_tick < CACHE_EVERY:
		return _cache
	var st = w.sys_state.get("atmo71")
	if st == null or not (st is Dictionary):
		_cache = null
		_cache_tick = w.tick
		return null
	var Atmo71 = preload("res://sim/systems/atmo71.gd")
	var b: Dictionary = Atmo71.board(w)
	var flares: Array = (st.get("flares", []) as Array).duplicate()
	var ash := bool(b.get("ash", false))
	var shake := float(b.get("shake", 0.0))
	if flares.is_empty() and not ash and shake < 0.01:
		_cache = null
		_cache_tick = w.tick
		return null
	_cache = {"flares": flares, "ash": ash, "shake": shake}
	_cache_tick = w.tick
	return _cache


func setup(view: Node) -> void:
	mv = view


func refresh(snap: Dictionary) -> void:
	if snap.is_empty() or mv == null:
		return
	var row = (snap.get("g71", {}) as Dictionary).get(KEY)
	if row == null:
		if _ash or _shake > 0.01 or not _flares.is_empty():
			_ash = false
			_shake = 0.0
			_flares = []
			_sig = -1
			if mv.camera != null:
				mv.camera.offset = Vector2.ZERO
			queue_redraw()
		return
	var ash := bool(row.get("ash", false))
	var shake := float(row.get("shake", 0.0))
	var flares: Array = row.get("flares", [])
	var sig := flares.size() + (1 if ash else 0) + int(shake * 100.0)
	if mv.camera != null:
		if shake > 0.01:
			var ox := float(int(snap.get("tick", 0)) % 7) - 3.0
			var oy := float(int(snap.get("tick", 0)) % 5) - 2.0
			mv.camera.offset = Vector2(ox, oy) * shake * 2.5
		else:
			mv.camera.offset = Vector2.ZERO
	if sig == _sig:
		return
	_sig = sig
	_ash = ash
	_shake = shake
	_flares = flares
	queue_redraw()


func _draw() -> void:
	if _ash:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.15, 0.12, 0.1, 0.08))
	if mv == null:
		return
	for f in _flares:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var pos = f.get("pos", [0, 0])
		var wp := Vector2(float(pos[0]), float(pos[1])) if pos is Array and pos.size() >= 2 else Vector2.ZERO
		var sp: Vector2 = mv.world_to_screen(wp)
		draw_circle(sp, 18.0, Color(1.0, 0.85, 0.35, 0.18))
		draw_circle(sp, 6.0, Color(1.0, 0.9, 0.5, 0.55))
		draw_line(sp + Vector2(0, -22), sp, Color(0.9, 0.75, 0.4, 0.5), 1.5)
