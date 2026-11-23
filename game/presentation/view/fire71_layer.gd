extends Node2D
## G7.1 I4 wildfire draw: orange cells + block-line ring.
## Snapshot provider "fire71" (RenderSnap.register_g71): null while no cells (layer then costs nothing).
## Never touches mv.world / _world from refresh — only snap.g71.

const RenderSnap = preload("res://sim/render_snap.gd")
const KEY := "fire71"

static var _reg_owner := 0

var mv: Node = null
var _cells: Array = []
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
	var st = w.sys_state.get("fire71")
	if st == null or not (st is Dictionary):
		return null
	var bag: Dictionary = st.get("cells", {})
	if bag.is_empty():
		return null
	var cells: Array = []
	var keys: Array = bag.keys()
	keys.sort()
	for k in keys:
		var c: Dictionary = bag[k]
		var parts := String(k).split(",")
		if parts.size() < 2:
			continue
		cells.append([float(parts[0]), float(parts[1]), float(c.get("i", 0.0))])
	return {"cells": cells} if not cells.is_empty() else null


func setup(view: Node) -> void:
	mv = view
	z_index = 12


func refresh(snap: Dictionary) -> void:
	if snap.is_empty() or mv == null:
		return
	var g71: Dictionary = snap.get("g71", {})
	var row = g71.get(KEY)
	if row == null:
		if not _cells.is_empty():
			_cells = []
			_sig = -1
			queue_redraw()
		return
	var cells: Array = row.get("cells", [])
	var sig := cells.size()
	for i in mini(cells.size(), 6):
		sig = (sig * 31 + int(float(cells[i][2]) * 100.0)) & 0x3fffffff
	if sig == _sig:
		return
	_sig = sig
	_cells = cells
	queue_redraw()


func _draw() -> void:
	if mv == null or _cells.is_empty():
		return
	for c in _cells:
		if not (c is Array) or c.size() < 3:
			continue
		var wp := Vector2(float(c[0]) + 0.5, float(c[1]) + 0.5)
		var sp: Vector2 = mv.world_to_screen(wp)
		var i := float(c[2])
		var a := 0.25 + 0.55 * i
		draw_circle(sp, 6.0 + 4.0 * i, Color(1.0, 0.35 + 0.2 * i, 0.05, a))
		if i >= 0.55:
			draw_arc(sp, 10.0, 0.0, TAU, 12, Color(1.0, 0.15, 0.0, 0.7), 2.0)
