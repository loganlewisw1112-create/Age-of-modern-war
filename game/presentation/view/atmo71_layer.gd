extends Node2D
## G7.1 E1 atmosphere draw: parachute flares + optional ash tint. Camera shake applied to MatchView.camera.

var mv: Node = null
var _flares: Array = []
var _ash := false
var _shake := 0.0


func setup(view: Node) -> void:
	mv = view


func refresh(snap: Dictionary) -> void:
	if snap.is_empty() or mv == null:
		return
	if not mv.has_method("world_readable") or not mv.world_readable():
		return
	var w = mv.get("_world")
	if w == null:
		return
	var Atmo71 = preload("res://sim/systems/atmo71.gd")
	var b: Dictionary = Atmo71.board(w)
	_ash = bool(b.get("ash", false))
	_shake = float(b.get("shake", 0.0))
	var st = w.sys_state.get("atmo71")
	_flares = []
	if st is Dictionary:
		_flares = (st.get("flares", []) as Array).duplicate()
	# Subtle camera shake (toggleable later via settings).
	if mv.camera != null and _shake > 0.01:
		var ox := float(int(snap.get("tick", 0)) % 7) - 3.0
		var oy := float(int(snap.get("tick", 0)) % 5) - 2.0
		mv.camera.offset = Vector2(ox, oy) * _shake * 2.5
	elif mv.camera != null:
		mv.camera.offset = Vector2.ZERO
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
