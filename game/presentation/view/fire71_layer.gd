extends Node2D
## G7.1 I4 wildfire draw: orange cells + block-line ring. Never mv.world.

var mv: Node = null
var _cells: Array = []


func setup(view: Node) -> void:
	mv = view
	z_index = 12


func refresh(snap: Dictionary) -> void:
	if snap.is_empty() or mv == null:
		return
	if not mv.has_method("world_readable") or not mv.world_readable():
		return
	var w = mv.get("_world")
	if w == null:
		return
	var st = w.sys_state.get("fire71")
	var cells: Array = []
	if st is Dictionary:
		for k in (st.get("cells", {}) as Dictionary).keys():
			var c: Dictionary = st.cells[k]
			cells.append({
				"pos": String(k).split(","),
				"i": float(c.get("i", 0.0)),
			})
	if cells.size() == _cells.size():
		var same := true
		for i in mini(cells.size(), 8):
			if float(cells[i].get("i", 0.0)) != float(_cells[i].get("i", -1.0)):
				same = false
				break
		if same and cells.size() == _cells.size():
			return
	_cells = cells
	queue_redraw()


func _draw() -> void:
	if mv == null or _cells.is_empty():
		return
	for c in _cells:
		var parts = c.get("pos", [])
		if not (parts is Array) or parts.size() < 2:
			continue
		var wp := Vector2(float(parts[0]) + 0.5, float(parts[1]) + 0.5)
		var sp: Vector2 = mv.world_to_screen(wp)
		var i := float(c.get("i", 0.5))
		var a := 0.25 + 0.55 * i
		draw_circle(sp, 6.0 + 4.0 * i, Color(1.0, 0.35 + 0.2 * i, 0.05, a))
		if i >= 0.55:
			draw_arc(sp, 10.0, 0.0, TAU, 12, Color(1.0, 0.15, 0.0, 0.7), 2.0)
