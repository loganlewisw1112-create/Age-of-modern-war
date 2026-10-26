extends Control
## G6.1 command layer map overlay (owner: PLAN61). Full-rect Control on the HUD layer, visible only in
## Command mode: dims the map, draws formations as NATO symbols, the side's plans and the draft, and
## takes the map clicks / drags while active (wheel zoom and middle-drag pan are passed to the camera).

const ViewUtil = preload("res://presentation/view/view_util.gd")

var hub = null                  # command_layer.gd
var drag_from: Variant = null   # Vector2i cell where the current drag started
var drag_to := Vector2i.ZERO
var hover := Vector2i.ZERO
var _mid := false
var _mid_last := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


## G6.1 (INTEG61): the HUD root Control has zero size (its panels are anchored to the viewport), so the
## FULL_RECT anchors gave this overlay a 0x0 rect and real map clicks never reached it (plan61 playtest).
## Size it to the visible canvas explicitly; command_layer calls this on activation and every update.
func fit() -> void:
	var p := get_parent() as Control
	var s := p.size if p != null else Vector2.ZERO
	if s.x < 1.0 or s.y < 1.0:
		var sc := get_global_transform_with_canvas().get_scale()
		s = get_viewport_rect().size / Vector2(maxf(0.01, sc.x), maxf(0.01, sc.y))
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	if size != s:
		size = s


# ---------------------------------------------------------------- coordinates
func _mv():
	return hub.mv() if hub != null else null


func _canvas_xf() -> Transform2D:
	var mv = _mv()
	return mv.get_viewport().get_canvas_transform() if mv != null else Transform2D.IDENTITY


## Local overlay point -> world tile position (height-aware pick when the camera provides it).
func to_world(local: Vector2) -> Vector2:
	var mv = _mv()
	if mv == null:
		return Vector2.ZERO
	var vp := get_global_transform_with_canvas() * local
	return mv.pick_world(_canvas_xf().affine_inverse() * vp)


## World tile position -> local overlay point.
func to_local_pt(p: Vector2) -> Vector2:
	var mv = _mv()
	if mv == null:
		return Vector2.ZERO
	var c: Vector2 = mv.world_to_screen(p)
	var cam = mv.get("camera")
	if cam != null and cam.has_method("height_map"):
		c = ViewUtil.world_to_screen_h(cam.height_map(), p)
	return get_global_transform_with_canvas().affine_inverse() * (_canvas_xf() * c)


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


static func _ctr(c: Vector2i) -> Vector2:
	return Vector2(c) + Vector2(0.5, 0.5)


# ---------------------------------------------------------------- input
func _gui_input(event: InputEvent) -> void:
	if hub == null:
		return
	var mv = _mv()
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		hover = _cell(to_world(mm.position))
		if drag_from != null:
			drag_to = hover
			if hub.tool == "axis":
				hub.model.add_axis_point(hover)
		if _mid and mv != null and mv.get("camera") != null:
			mv.camera.pan_screen(_mid_last - mm.position)
			_mid_last = mm.position
		queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var cell := _cell(to_world(mb.position))
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and mv != null and mv.get("camera") != null:
					mv.camera.zoom_at(mb.position, 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
			MOUSE_BUTTON_MIDDLE:
				_mid = mb.pressed
				_mid_last = mb.position
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					drag_from = cell
					drag_to = cell
					hub.on_press(cell, to_world(mb.position))
				elif drag_from != null:
					var a: Vector2i = drag_from
					drag_from = null
					hub.on_release(a, cell)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					hub.on_right(cell, to_world(mb.position), mb.position)
		queue_redraw()
	accept_event()


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if hub == null or _mv() == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.06, 0.22))
	var m = hub.model
	for p in m.plans:
		if bool(p.active):
			_draw_plan(p, m.col(int(p.id)), 1.0)
	if m.has_draft():
		_draw_draft(m.draft)
	for fm in m.formations:
		_draw_symbol(fm, not m.draft.is_empty() and m.draft.formation == fm.f)
	if drag_from != null and hub.tool in ["phase", "screen"]:
		_dash(to_local_pt(_ctr(drag_from)), to_local_pt(_ctr(drag_to)), Color(1, 1, 1, 0.9), 3.0)
	if hub.hint != "":
		_label(Vector2(16, size.y - 120), hub.hint, Color(1, 0.95, 0.75), 16)


func _font() -> Font:
	return get_theme_default_font()


func _label(at: Vector2, text: String, c: Color, fs: int = 13) -> void:
	var f := _font()
	draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
	draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


func _dash(a: Vector2, b: Vector2, c: Color, wdt: float) -> void:
	draw_dashed_line(a, b, c, wdt, 10.0)


func _poly(cells: Array, c: Color, wdt: float, arrow: bool) -> void:
	if cells.size() < 2:
		return
	var pts := PackedVector2Array()
	for cc in cells:
		pts.append(to_local_pt(_ctr(cc)))
	draw_polyline(pts, Color(0, 0, 0, 0.6), wdt + 3.0, true)
	draw_polyline(pts, c, wdt, true)
	if arrow:
		var tip: Vector2 = pts[pts.size() - 1]
		var dir := (tip - pts[pts.size() - 2]).normalized()
		var side := dir.orthogonal() * 9.0
		draw_colored_polygon(PackedVector2Array([tip + dir * 6.0, tip - dir * 12.0 + side, tip - dir * 12.0 - side]), c)


func _objective(c: Vector2i, n: int, col: Color, held: bool) -> void:
	var p := to_local_pt(_ctr(c))
	if held:
		draw_circle(p, 14.0, Color(col, 0.35))
	draw_arc(p, 14.0, 0.0, TAU, 28, Color(0, 0, 0, 0.7), 5.0)
	draw_arc(p, 14.0, 0.0, TAU, 28, col, 2.5)
	_label(p + Vector2(17, 5), "OBJ %d" % n, col)


func _draw_plan(p: Dictionary, col: Color, a: float) -> void:
	var c := Color(col, a)
	_poly(p.axis, c, 3.0, true)
	var i := 0
	for pl in p.phase_lines:
		var pts: Array = pl.points
		_poly(pts, c, 2.0, false)
		var reached := i < int(p.pl_reached)
		var head := to_local_pt(_ctr(pts[0]))
		_label(head + Vector2(6, -6), String(pl.name) + ("  ✓" if reached else ""), c)
		if reached:
			draw_circle(head, 5.0, c)
		i += 1
	var k := 0
	for o in p.objectives:
		_objective(o, k + 1, c, k < (p.obj_held as Array).size() and bool(p.obj_held[k]))
		k += 1
	var legs: Array = p.legs
	if int(p.leg) >= 0 and int(p.leg) < legs.size():
		var tgt := to_local_pt(legs[int(p.leg)].pos)
		draw_arc(tgt, 6.0, 0.0, TAU, 16, Color.WHITE, 2.0)


func _draw_draft(d: Dictionary) -> void:
	var c := Color(1, 1, 1, 0.95)
	var cells: Array = d.axis
	_poly(cells, c, 3.0, true)
	for pl in d.phase_lines:
		_poly(pl.points, Color(1, 1, 0.6), 2.0, false)
		_label(to_local_pt(_ctr(pl.points[0])) + Vector2(6, -6), String(pl.name), Color(1, 1, 0.6))
	var k := 0
	for o in d.objectives:
		_objective(o, k + 1, c, false)
		k += 1


## NATO-style friendly unit symbol: blue frame, infantry cross, echelon mark above, label below.
func _draw_symbol(fm: Dictionary, picked: bool) -> void:
	var p := to_local_pt(fm.pos) + Vector2(0, -26)
	var kind := String(fm.f.kind)
	var sz := Vector2(34, 22) if kind != "platoon" else Vector2(26, 17)
	var r := Rect2(p - sz * 0.5, sz)
	draw_rect(r, Color("6fa8dc") if not picked else Color("e8d25a"))
	draw_rect(r, Color(0.05, 0.08, 0.1), false, 2.0)
	draw_line(r.position, r.end, Color(0.05, 0.08, 0.1), 1.5)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), Color(0.05, 0.08, 0.1), 1.5)
	var mark := String(hub.model.ECHELON.get(kind, ""))
	var f := _font()
	var mw := f.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_label(Vector2(p.x - mw * 0.5, r.position.y - 3), mark, Color.WHITE, 12)
	if kind != "platoon" or picked:
		var lw := f.get_string_size(String(fm.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_label(Vector2(p.x - lw * 0.5, r.end.y + 13), String(fm.label), Color(0.9, 0.95, 1.0), 12)
