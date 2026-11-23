extends Node2D
## G7.1 J7 horror atmosphere draw: silence vignette, night-eye clusters, body markers.
## Snapshot provider "horror71"; null when idle. Never mv.world from refresh.

const RenderSnap = preload("res://sim/render_snap.gd")
const KEY := "horror71"

static var _reg_owner := 0
static var _cache: Variant = null
static var _cache_tick := -999
const CACHE_EVERY := 4

var mv: Node = null
var _silence := false
var _eyes := false
var _bodies: Array = []
var _song := 0.0
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
	var st = w.sys_state.get("horror71")
	var Horror71 = preload("res://sim/systems/horror71.gd")
	if not Horror71.active(w):
		_cache = null
		_cache_tick = w.tick
		return null
	var b: Dictionary = Horror71.board(w)
	var bodies: Array = []
	if st is Dictionary:
		bodies = (st.get("bodies", []) as Array).duplicate()
	var sil := bool(b.get("silence", false))
	var eyes := bool(b.get("night_eyes", false))
	var song := float(b.get("tide_song", 0.0))
	if not sil and not eyes and bodies.is_empty() and song < 0.01:
		_cache = null
		_cache_tick = w.tick
		return null
	_cache = {"silence": sil, "night_eyes": eyes, "tide_song": song, "bodies": bodies}
	_cache_tick = w.tick
	return _cache


func setup(view: Node) -> void:
	mv = view
	z_index = 40


func refresh(snap: Dictionary) -> void:
	if snap.is_empty() or mv == null:
		return
	var row = (snap.get("g71", {}) as Dictionary).get(KEY)
	if row == null:
		if _silence or _eyes or not _bodies.is_empty() or _song > 0.01:
			_silence = false
			_eyes = false
			_bodies = []
			_song = 0.0
			_sig = -1
			queue_redraw()
		return
	var sil := bool(row.get("silence", false))
	var eyes := bool(row.get("night_eyes", false))
	var song := float(row.get("tide_song", 0.0))
	var bodies: Array = row.get("bodies", [])
	var sig := bodies.size() + (2 if sil else 0) + (4 if eyes else 0) + int(song * 50.0)
	if sig == _sig:
		return
	_sig = sig
	_silence = sil
	_eyes = eyes
	_song = song
	_bodies = bodies
	queue_redraw()


func _draw() -> void:
	if _silence:
		var r := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, r), Color(0.02, 0.02, 0.05, 0.18))
	if _eyes and mv != null:
		var n := 24 + int(_song * 40.0)
		for i in n:
			var x := fmod(float(i * 97 + 13), 1.0)
			var y := fmod(float(i * 53 + 29), 1.0)
			var p := Vector2(x, y) * get_viewport_rect().size
			var a := 0.35 + 0.25 * _song
			draw_circle(p, 2.2, Color(0.7, 0.95, 0.4, a))
			draw_circle(p + Vector2(5, 0), 2.2, Color(0.7, 0.95, 0.4, a))
	if mv != null and not _bodies.is_empty():
		for b in _bodies:
			if typeof(b) != TYPE_DICTIONARY:
				continue
			var pos = b.get("pos", [0, 0])
			var wp := Vector2(float(pos[0]), float(pos[1])) if pos is Array and pos.size() >= 2 else Vector2.ZERO
			var sp: Vector2 = mv.world_to_screen(wp)
			draw_rect(Rect2(sp + Vector2(-3, -14), Vector2(6, 14)), Color(0.45, 0.1, 0.1, 0.85))
			draw_circle(sp + Vector2(0, -16), 3.0, Color(0.6, 0.15, 0.12, 0.9))
