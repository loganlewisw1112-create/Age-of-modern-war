extends Node2D
## G7.1 J4 harvester swarm draw: spider dots dragging bodies home. Never mv.world.

var mv: Node = null
var _harvs: Array = []


func setup(view: Node) -> void:
	mv = view
	z_index = 16


func refresh(snap: Dictionary) -> void:
	if snap.is_empty() or mv == null:
		return
	if not mv.has_method("world_readable") or not mv.world_readable():
		return
	var w = mv.get("_world")
	if w == null:
		return
	var st = w.sys_state.get("harvest71")
	var harvs: Array = []
	if st is Dictionary:
		harvs = (st.get("harvs", []) as Array).duplicate(true)
	if harvs.size() == _harvs.size():
		var same := true
		for i in mini(harvs.size(), 4):
			var a = harvs[i].get("pos", [0, 0])
			var b = _harvs[i].get("pos", [0, 0])
			if float(a[0]) != float(b[0]) or float(a[1]) != float(b[1]):
				same = false
				break
		if same:
			return
	_harvs = harvs
	queue_redraw()


func _draw() -> void:
	if mv == null or _harvs.is_empty():
		return
	for h in _harvs:
		var pos = h.get("pos", [0, 0])
		if not (pos is Array) or pos.size() < 2:
			continue
		var sp: Vector2 = mv.world_to_screen(Vector2(float(pos[0]), float(pos[1])))
		var carry := int(h.get("carry", -1)) >= 0
		var col := Color(0.75, 0.55, 0.15, 0.95) if carry else Color(0.55, 0.4, 0.1, 0.85)
		draw_circle(sp, 4.5, col)
		# Legs hint.
		for a in [0.4, 1.2, 2.0, 2.8, 3.6, 4.4]:
			draw_line(sp, sp + Vector2(cos(a), sin(a)) * 7.0, Color(col.r, col.g, col.b, 0.55), 1.0)
		if carry:
			draw_circle(sp + Vector2(0, -6), 3.0, Color(0.5, 0.12, 0.12, 0.9))
