extends VBoxContainer
## Shared tool behaviour for the ED1 tabs (owner: ED1). A tab extends this, builds its controls
## in _build(), and overrides _apply(cells) (cells = the brush footprint BEFORE symmetry; the
## doc applies symmetry). Modes: "brush" (drag paints, one stroke = one undo step),
## "line" (press a, release b), "rect" (filled rectangle a..b), "click" (one apply per click).

const W = preload("res://presentation/editor/editor_widgets.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const Brushes = preload("res://presentation/editor/brushes.gd")
const Symmetry = preload("res://presentation/editor/symmetry.gd")

var ed                       # editor_scene.gd
var shape := "circle"
var bsize := 3
var mode := "brush"
var stroke_label := "edit"
var preview_color := Color(1, 1, 1, 0.3)
var _a = null                # line/rect anchor cell
var _last := Vector2i.ZERO


func setup(editor) -> void:
	ed = editor
	add_theme_constant_override("separation", 6)
	_build()


func _build() -> void:
	pass


## Override: apply the tool to these footprint cells (inside an open stroke).
func _apply(_cells: Array) -> void:
	pass


func _mw() -> int:
	return int(ed.doc.map.w)


func _mh() -> int:
	return int(ed.doc.map.h)


func footprint(c: Vector2i) -> Array:
	return Brushes.shape_cells(c, bsize, shape, _mw(), _mh())


## Brush shape / size / mode controls. modes: subset of ["brush", "line", "rect"].
func brush_controls(modes: Array = ["brush", "line", "rect"]) -> void:
	W.header(self, "Brush")
	W.choice_row(self, ["Circle", "Square"], 0 if shape == "circle" else 1, func(i: int): shape = ["circle", "square"][i])
	W.slider(self, "Size", 1, 15, 1, bsize, func(v: float): bsize = int(v))
	if modes.size() > 1:
		var labels := []
		for m in modes:
			labels.append({"brush": "Brush", "line": "Line", "rect": "Rectangle", "click": "Click"}[m])
		W.choice_row(self, labels, maxi(0, modes.find(mode)), func(i: int): _pick_mode(modes[i]))


func _pick_mode(m: String) -> void:
	mode = m
	_a = null


func tool_begin(c: Vector2i) -> void:
	match mode:
		"brush":
			ed.doc.begin_stroke(stroke_label)
			_last = c
			_apply(footprint(c))
		"line", "rect":
			_a = c
		"click":
			ed.doc.begin_stroke(stroke_label)
			_apply([c])
			ed.stroke_done()


func tool_drag(c: Vector2i) -> void:
	if mode != "brush" or not ed.doc.in_stroke():
		return
	var cells: Array = []
	var seen := {}
	for p in Brushes.line_cells(_last, c):
		if p == _last:
			continue
		for q in footprint(p):
			if not seen.has(q):
				seen[q] = true
				cells.append(q)
	_last = c
	_apply(cells)


func tool_end(c: Vector2i) -> void:
	match mode:
		"brush":
			if ed.doc.in_stroke():
				ed.stroke_done()
		"line", "rect":
			if _a == null:
				return
			ed.doc.begin_stroke(stroke_label)
			_apply(_shape_cells(_a, c))
			ed.stroke_done()
			_a = null


func _shape_cells(a: Vector2i, b: Vector2i) -> Array:
	if mode == "line":
		return Brushes.thick_line(a, b, bsize, shape, _mw(), _mh())
	return Brushes.rect_cells(a, b, true, _mw(), _mh())


func tool_cancel() -> void:
	if ed != null and ed.doc.in_stroke():
		ed.stroke_done()
	_a = null


func tool_preview(c: Vector2i) -> Dictionary:
	var cells: Array
	if (mode == "line" or mode == "rect") and _a != null:
		cells = _shape_cells(_a, c)
	elif mode == "click":
		cells = [c]
	else:
		cells = footprint(c)
	return {"cells": ed.doc.sym_cells(cells), "color": preview_color}


## Symmetric single-object placement: every footprint image of (origin, size).
func sym_footprints(origin: Vector2i, fsize: Vector2i) -> Array:
	return Symmetry.footprints(origin, fsize, ed.doc.symmetry, _mw(), _mh())
