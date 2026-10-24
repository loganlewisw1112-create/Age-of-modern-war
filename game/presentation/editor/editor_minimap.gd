extends Control
## Editor minimap (owner: ED1): the whole map as an iso diamond (one pixel per cell, drawn
## through a transform), the camera view outline, player starts; click/drag to jump.
## Only changed cells are re-coloured.

const W = preload("res://presentation/editor/editor_widgets.gd")

var ev                        # editor_view.gd
var _img: Image
var _tex: ImageTexture
var _lut: Array = []
var _xf := Transform2D.IDENTITY


func setup(view) -> void:
	ev = view
	custom_minimum_size = Vector2(230, 130)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_lut.clear()
	for c in W.TERRAIN_COLORS:
		_lut.append(Color(c))
	rebuild()


func rebuild() -> void:
	var m: Dictionary = ev.doc.map
	var w := int(m.w)
	var h := int(m.h)
	_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var t: PackedByteArray = m.terrain
	for y in h:
		for x in w:
			_img.set_pixel(x, y, _lut[mini(int(t[y * w + x]), _lut.size() - 1)])
	_tex = ImageTexture.create_from_image(_img)
	queue_redraw()


func on_cells_changed(cells: Array) -> void:
	if _img == null:
		return
	var m: Dictionary = ev.doc.map
	var w := int(m.w)
	if _img.get_width() != w or _img.get_height() != int(m.h):
		rebuild()
		return
	for c in cells:
		_img.set_pixel(c.x, c.y, _lut[mini(int(m.terrain[c.y * w + c.x]), _lut.size() - 1)])
	_tex.update(_img)
	queue_redraw()


func _update_xf() -> void:
	var w := float(ev.doc.map.w)
	var h := float(ev.doc.map.h)
	var sz := size
	# diamond spans (w + h) units wide and (w + h) / 2 tall
	var s := minf(sz.x / (w + h), sz.y * 2.0 / (w + h))
	var ox := (sz.x - (w + h) * s) * 0.5 + h * s
	var oy := (sz.y - (w + h) * s * 0.5) * 0.5
	_xf = Transform2D(Vector2(s, s * 0.5), Vector2(-s, s * 0.5), Vector2(ox, oy))


func _draw() -> void:
	if ev == null or _tex == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.08))
	_update_xf()
	draw_set_transform_matrix(_xf)
	draw_texture(_tex, Vector2.ZERO)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var players: Array = ev.doc.scenario.get("players", [])
	for i in players.size():
		var s := Vector2(Vector2i(players[i].get("start", Vector2i.ZERO))) + Vector2(0.5, 0.5)
		draw_circle(_xf * s, 3.5, ev.team_color(i))
	var vs := get_viewport().get_visible_rect().size
	var inv: Transform2D = ev.get_viewport().get_canvas_transform().affine_inverse()
	var pts := PackedVector2Array()
	for sp in [Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y), Vector2.ZERO]:
		pts.append(_xf * ev.screen_to_world(inv * sp))
	draw_polyline(pts, Color(1, 1, 1, 0.85), 1.0)


func _process(_d: float) -> void:
	if visible:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var press := event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	var drag := event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if press or drag:
		_update_xf()
		var p: Vector2 = _xf.affine_inverse() * (event as InputEventMouse).position
		ev.center_camera_on(p)
		accept_event()
