extends Node2D
## G7.1 J4 harvester swarm draw: spider dots dragging bodies home.
## Snapshot provider "harvest71"; null when empty. Never mv.world from refresh.

const RenderSnap = preload("res://sim/render_snap.gd")
const KEY := "harvest71"

static var _reg_owner := 0

var mv: Node = null
var _harvs: Array = []
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
	var st = w.sys_state.get("harvest71")
	if st == null or not (st is Dictionary):
		return null
	var harvs: Array = st.get("harvs", [])
	if harvs.is_empty():
		return null
	return {"harvs": (harvs as Array).duplicate(true)}


func setup(view: Node) -> void:
	mv = view
	z_index = 16


func refresh(snap: Dictionary) -> void:
	if snap.is_empty() or mv == null:
		return
	var row = (snap.get("g71", {}) as Dictionary).get(KEY)
	if row == null:
		if not _harvs.is_empty():
			_harvs = []
			_sig = -1
			queue_redraw()
		return
	var harvs: Array = row.get("harvs", [])
	var sig := harvs.size()
	for i in mini(harvs.size(), 4):
		var p = harvs[i].get("pos", [0, 0])
		sig = (sig * 31 + int(float(p[0]) * 10.0) + int(float(p[1]) * 10.0)) & 0x3fffffff
	if sig == _sig:
		return
	_sig = sig
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
		for a in [0.4, 1.2, 2.0, 2.8, 3.6, 4.4]:
			draw_line(sp, sp + Vector2(cos(a), sin(a)) * 7.0, Color(col.r, col.g, col.b, 0.55), 1.0)
		if carry:
			draw_circle(sp + Vector2(0, -6), 3.0, Color(0.5, 0.12, 0.12, 0.9))
