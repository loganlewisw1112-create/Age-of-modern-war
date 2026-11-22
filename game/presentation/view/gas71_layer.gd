extends Node2D
## G7.1 CNOPS71 J10 (docs/G71_SCOPE.md): the counter-nanite gas cloud and the masks, drawn over the units.
## Snapshot provider "gas71" (RenderSnap.register_g71): null while sys_state.gas71 is absent or has no cloud and no
## masked soldier (the layer then costs nothing). Rows:
##   cells:  [x, y, conc]   one per gas cell (Gas71 cell size, conc 0..1+), rebuilt when the field changes
##   masks:  [x, y, filt]   one per soldier wearing a mask now (Gas71.masked), filter left 0..1 (red when nearly spent)
## The cloud: soft drifting puffs per cell, alpha by concentration, green-yellow (the scope's counter-nanite gas);
## the masks: a dark respirator glyph with a filter canister above the soldier's head, visible at play zoom.
## CNOPS71-9 contrast (the cloud was faint under the LP night tint, the glyphs small and dark): the cloud draws with
## ADDITIVE blending (it lights the ground green instead of covering it, so the units under it stay fully visible) plus
## a brighter rim on the outer puffs; the mask glyphs are ~1.6x larger with a pale outline, drawn by a child node with
## normal blending (the additive material would wash them out).
## The masked set is rescanned every MASK_RESCAN snapshots (positions follow every snapshot), only while a cloud is up
## or masks were on at the last scan.
const RenderSnap = preload("res://sim/render_snap.gd")
const Gas71 = preload("res://sim/systems/gas71.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const KEY := "gas71"
const MASK_RESCAN := 6
const HEAD := 15.0      # px above the unit's ground point
const GAS := Color(0.62, 0.86, 0.20)
const GAS_D := Color(0.42, 0.66, 0.12)
const RIM := Color(0.86, 1.0, 0.42)
const GLYPH := 1.6     # mask glyph scale

static var _p_cells := PackedFloat32Array()
static var _p_sig := -1
static var _p_ver := 0
static var _p_ids: Array = []
static var _p_age := 0
static var _reg_owner := 0

var _cells := PackedFloat32Array()
var _masks := PackedFloat32Array()
var _ver := -2
var _t := 0.0
var _cs := 2.0
var _mk: Node2D = null   # mask glyphs (normal blending)


func _init() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_mk = Node2D.new()
	_mk.name = "Masks"
	add_child(_mk)
	_mk.draw.connect(_draw_masks)
	_reg_owner = get_instance_id()
	RenderSnap.register_g71(KEY, Callable(get_script(), "snap"))


func _exit_tree() -> void:
	if _reg_owner != get_instance_id():
		return
	RenderSnap.unregister_g71(KEY)


static func snap(w, _sn: Dictionary):
	var s = w.sys_state.get(Gas71.KEY)
	if s == null:
		return null
	var cd: Dictionary = s.c
	if cd.is_empty() and _p_ids.is_empty():
		_p_cells = PackedFloat32Array()
		return null
	var cs := float(Gas71.ri("cell"))
	var gw := int(ceil(float(w.map.w) / cs))
	var sig := cd.size()
	for k in cd:
		sig = (sig * 31 + int(k) * 7 + int(cd[k])) & 0x3fffffff
	if sig != _p_sig:
		_p_sig = sig
		var ks: Array = cd.keys()
		ks.sort()
		var rows := PackedFloat32Array()
		rows.resize(ks.size() * 3)
		var i := 0
		for k in ks:
			rows[i] = (float(int(k) % gw) + 0.5) * cs
			rows[i + 1] = (float(int(k) / gw) + 0.5) * cs
			rows[i + 2] = float(cd[k]) / 1000.0
			i += 3
		_p_cells = rows
		_p_ver += 1
	_p_age += 1
	if _p_age >= MASK_RESCAN:
		_p_age = 0
		var ids := []
		for id in SimIndex.unit_ids(w):
			var e = w.entities.get(int(id))
			if e != null and e.has("g71mk") and Gas71.masked(e):
				ids.append(int(id))
		_p_ids = ids
	var ms := PackedFloat32Array()
	for id in _p_ids:
		var e = w.entities.get(int(id))
		if e == null or not Gas71.masked(e):
			continue
		ms.append(float(e.pos.x))
		ms.append(float(e.pos.y))
		ms.append(clampf(float(Gas71.mask_of(e).get("f", 1000)) / 1000.0, 0.0, 1.0))
	if _p_cells.is_empty() and ms.is_empty():
		return null
	return {"ver": _p_ver, "cells": _p_cells, "masks": ms, "cs": cs}


func refresh(snap_d: Dictionary) -> void:
	var d = (snap_d.get("g71", {}) as Dictionary).get(KEY)
	if d == null:
		if not _cells.is_empty() or not _masks.is_empty():
			_cells = PackedFloat32Array()
			_masks = PackedFloat32Array()
			_ver = -2
			queue_redraw()
			_mk.queue_redraw()
		return
	_cs = float(d.cs)
	_cells = d.cells
	_ver = int(d.ver)
	_masks = d.masks
	queue_redraw()
	_mk.queue_redraw()


func _process(delta: float) -> void:
	if _cells.is_empty():
		return
	_t += delta   # the puffs drift and breathe; redraw only while a cloud is up
	queue_redraw()


static func _iso(x: float, y: float) -> Vector2:
	return Vector2((x - y) * 32.0, (x + y) * 16.0)


static func _h(i: int, k: int) -> float:
	var x := (i * 374761393 + k * 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x % 1000) / 1000.0


static func _pts(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 14:
		var a := TAU * float(k) / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _ellipse(c: Vector2, rx: float, ry: float, col: Color, ci: CanvasItem = null) -> void:
	(ci if ci != null else self).draw_colored_polygon(_pts(c, rx, ry), col)


func _draw() -> void:
	var n := _cells.size() / 3
	var r0 := _cs * 22.0
	for j in n:
		var o := j * 3
		var cx := _cells[o]
		var cy := _cells[o + 1]
		var c := clampf(_cells[o + 2], 0.0, 1.2)
		var seed := int(cx * 13.0 + cy * 977.0)
		for k in 3:
			var ph := _t * (0.35 + _h(seed, k) * 0.3) + _h(seed, k + 7) * TAU
			var ox := (_h(seed, k + 1) - 0.5) * _cs * 0.9 + sin(ph) * 0.25
			var oy := (_h(seed, k + 2) - 0.5) * _cs * 0.9 + cos(ph * 0.8) * 0.25
			var p := _iso(cx + ox, cy + oy) - Vector2(0, 6.0 + 4.0 * k)
			var r := r0 * (0.55 + 0.25 * _h(seed, k + 3)) * (0.85 + 0.15 * sin(ph))
			var col := (GAS if k != 1 else GAS_D)
			col.a = clampf(0.10 + 0.28 * c, 0.08, 0.40) * (0.8 if k == 2 else 1.0)
			_ellipse(p, r, r * 0.5, col)
			if k == 0:
				var rim := RIM
				rim.a = clampf(0.12 + 0.30 * c, 0.10, 0.42)
				var ring := _pts(p, r, r * 0.5)
				ring.append(ring[0])
				draw_polyline(ring, rim, 1.5, true)


func _draw_masks() -> void:
	var m := _masks.size() / 3
	var g := GLYPH
	for j in m:
		var o2 := j * 3
		var p2 := _iso(_masks[o2], _masks[o2 + 1]) - Vector2(0, HEAD + 2.0)
		var f := _masks[o2 + 2]
		_ellipse(p2, 3.2 * g + 1.0, 2.6 * g + 1.0, Color(0.86, 0.94, 0.80, 0.95), _mk)   # pale outline
		_ellipse(p2, 3.2 * g, 2.6 * g, Color(0.08, 0.09, 0.08, 0.97), _mk)               # face piece
		_ellipse(p2 + Vector2(-1.3, -0.7) * g, 0.95 * g, 0.75 * g, Color(0.60, 0.85, 0.95, 0.95), _mk)   # eye lenses
		_ellipse(p2 + Vector2(1.3, -0.7) * g, 0.95 * g, 0.75 * g, Color(0.60, 0.85, 0.95, 0.95), _mk)
		var can := Color(0.90, 0.22, 0.15) if f <= 0.2 else Color(0.52, 0.60, 0.40)
		var cr := Rect2(p2 + Vector2(-1.4, 1.5) * g, Vector2(2.8, 2.5) * g)
		_mk.draw_rect(cr.grow(0.8), Color(0.86, 0.94, 0.80, 0.95))   # outline
		_mk.draw_rect(cr, can)                                          # filter canister
