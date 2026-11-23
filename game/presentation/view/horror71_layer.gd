extends Node2D
## G7.1 J7 horror atmosphere draw: silence vignette cue, night-eye clusters, body markers.
## Reads MatchView snap / horror board only when world_readable; never mv.world.

var mv: Node = null
var _silence := false
var _eyes := false
var _bodies: Array = []
var _song := 0.0


func setup(view: Node) -> void:
	mv = view
	z_index = 40


## Called each frame from G71Attach.refresh_all with the latest render snap.
func refresh(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	if mv == null or not mv.has_method("world_readable") or not mv.world_readable():
		return
	var w = mv.get("_world")
	if w == null:
		return
	var Horror71 = preload("res://sim/systems/horror71.gd")
	var b: Dictionary = Horror71.board(w)
	var sil := bool(b.get("silence", false))
	var eyes := bool(b.get("night_eyes", false))
	var song := float(b.get("tide_song", 0.0))
	var st = w.sys_state.get("horror71")
	var bodies: Array = []
	if st is Dictionary:
		bodies = (st.get("bodies", []) as Array).duplicate()
	if sil == _silence and eyes == _eyes and is_equal_approx(song, _song) and bodies.size() == _bodies.size():
		return
	_silence = sil
	_eyes = eyes
	_song = song
	_bodies = bodies
	queue_redraw()


func _draw() -> void:
	if _silence:
		# Soft edge darken: the silence-before cue.
		var r := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, r), Color(0.02, 0.02, 0.05, 0.18))
	if _eyes and mv != null:
		# Cluster of glowing eyes across the far field (screen-space scatter, deterministic).
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
