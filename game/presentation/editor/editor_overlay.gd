extends Node2D
## Editor overlays (owner: ED1). mode "static": passability tint per movement class, grid,
## map decor (generated art when present, coloured footprint otherwise), player start markers,
## bridges. Redrawn only when the document changes (the camera moves the canvas, not the
## drawing). mode "preview": the active tool's cursor/preview, redrawn on mouse moves.
## Per-cell layers are one w x h Image drawn through the iso transform, so a 256 map costs a
## single textured quad.

const Catalog = preload("res://presentation/editor/decor_catalog.gd")
const ViewUtil = preload("res://presentation/view/view_util.gd")
const ISO := Transform2D(Vector2(32, 16), Vector2(-32, 16), Vector2.ZERO)

var mode := "static"
var ev                        # editor_view.gd
var _pass_img: Image
var _pass_tex: ImageTexture
var _pass_class := ""
var _tex_cache: Dictionary = {}


func setup(view) -> void:
	ev = view
	_pass_class = ""
	_pass_img = null
	queue_redraw()


func on_cells_changed(cells: Array) -> void:
	if _pass_img != null and _pass_class != "":
		var w := int(ev.doc.map.w)
		for c in cells:
			_pass_img.set_pixel(c.x, c.y, _pass_color(int(ev.doc.map.terrain[c.y * w + c.x])))
		_pass_tex.update(_pass_img)
	queue_redraw()


func _pass_color(code: int) -> Color:
	if Terrain.passable(code, _pass_class):
		return Color(0.2, 0.9, 0.3, 0.0)
	return Color(0.95, 0.15, 0.1, 0.42)


func _ensure_pass() -> void:
	var cls := String(ev.layers_on.get("pass", ""))
	if cls == _pass_class and (_pass_img != null or cls == ""):
		return
	_pass_class = cls
	if cls == "":
		_pass_img = null
		return
	var w := int(ev.doc.map.w)
	var h := int(ev.doc.map.h)
	_pass_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var t: PackedByteArray = ev.doc.map.terrain
	var lut := {}
	for y in h:
		for x in w:
			var code := int(t[y * w + x])
			if not lut.has(code):
				lut[code] = _pass_color(code)
			_pass_img.set_pixel(x, y, lut[code])
	_pass_tex = ImageTexture.create_from_image(_pass_img)


func _diamond(c: Vector2i, size: Vector2i = Vector2i.ONE) -> PackedVector2Array:
	var p := Vector2(c)
	return PackedVector2Array([ev.world_to_screen(p), ev.world_to_screen(p + Vector2(size.x, 0)),
		ev.world_to_screen(p + Vector2(size)), ev.world_to_screen(p + Vector2(0, size.y))])


func _draw() -> void:
	if ev == null or ev.doc == null:
		return
	if mode == "preview":
		_draw_preview()
		return
	var m: Dictionary = ev.doc.map
	var w := int(m.w)
	var h := int(m.h)
	_ensure_pass()
	if _pass_img != null:
		draw_set_transform_matrix(ISO)
		draw_texture(_pass_tex, Vector2.ZERO)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	if bool(ev.layers_on.get("grid", false)):
		var gc := Color(0, 0, 0, 0.22)
		for x in w + 1:
			draw_line(ev.world_to_screen(Vector2(x, 0)), ev.world_to_screen(Vector2(x, h)), gc, 1.0)
		for y in h + 1:
			draw_line(ev.world_to_screen(Vector2(0, y)), ev.world_to_screen(Vector2(w, y)), gc, 1.0)
	if bool(ev.layers_on.get("decor", true)):
		for e in m.get("decor", []):
			_draw_decor(e)
	for br in m.get("bridges", []):
		for c in br.get("cells", []):
			draw_colored_polygon(_diamond(Vector2i(c)), Color(0.75, 0.6, 0.35, 0.35))
	if ev.entity_layer == null:
		for r in m.get("resources", []):
			var col := Color(0.85, 0.55, 0.2) if String(r.res) == "ore" else Color(0.7, 0.75, 0.8)
			draw_circle(ev.world_to_screen(Vector2(r.cell) + Vector2(0.5, 0.5)), 9.0, col)
	var players: Array = ev.doc.scenario.get("players", [])
	var font := ThemeDB.fallback_font
	for i in players.size():
		var s := Vector2i(players[i].get("start", Vector2i.ZERO))
		var col2: Color = ev.team_color(i)
		var p: Vector2 = ev.world_to_screen(Vector2(s) + Vector2(0.5, 0.5))
		draw_polyline(_ring(p, 22.0), col2, 3.0)
		draw_line(p, p + Vector2(0, -46), Color(0.1, 0.1, 0.1), 3.0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -46), p + Vector2(26, -38), p + Vector2(0, -30)]), col2)
		draw_string(font, p + Vector2(-12, 40), "P%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


func _ring(p: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 25:
		var a := TAU * k / 24.0
		pts.append(p + Vector2(cos(a) * r, sin(a) * r * 0.5))
	return pts


func _texture_for(key: String):
	if _tex_cache.has(key):
		return _tex_cache[key]
	var spec: Dictionary = ArtCatalog.manifest().get("poi_decor", {}).get(key, {})
	var out = null
	if not spec.is_empty():
		var tex = ArtCatalog._texture(String(spec.file))
		if tex != null and not ViewUtil.is_placeholder(tex):
			out = [tex, Vector2(float(spec.pivot[0]), float(spec.pivot[1]))]
	_tex_cache[key] = out
	return out


func _draw_decor(e: Dictionary) -> void:
	var id := String(e.get("id", ""))
	var o := Vector2i(e.cell)
	var size := Vector2i(e.get("size", Catalog.size_of(id)))
	var d := Catalog.get_def(id)
	var art := String(d.get("art", id))
	var t = _texture_for(art)
	if t != null:
		# anchor: the footprint's bottom corner area, like the generator's pivot convention
		var anchor: Vector2 = ev.world_to_screen(Vector2(o) + Vector2(size) * 0.5)
		draw_texture(t[0], anchor - t[1] + Vector2(0, float(size.y + size.x) * 8.0 - 16.0))
		return
	var col := Color(String(d.get("color", "8a7a6a")))
	var c: Vector2 = ev.world_to_screen(Vector2(o) + Vector2(size) * 0.5)
	match id:
		"bush", "plant":
			draw_circle(c + Vector2(0, -6), 9.0 if id == "bush" else 6.0, col)
			draw_circle(c + Vector2(6, -3), 6.0, col.darkened(0.2))
		"rocks", "boulder":
			var r := 7.0 if id == "rocks" else 13.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r, 0), c + Vector2(-r * 0.4, -r), c + Vector2(r * 0.6, -r * 0.8), c + Vector2(r, 0), c + Vector2(0, r * 0.4)]), col)
		_:
			draw_colored_polygon(_diamond(o, size), Color(col, 0.85))
			var top := PackedVector2Array()
			for q in _diamond(o, size):
				top.append(q + Vector2(0, -14))
			draw_colored_polygon(top, col.lightened(0.15))
			draw_polyline(PackedVector2Array([top[0], top[1], top[2], top[3], top[0]]), col.darkened(0.4), 1.5)


func _draw_preview() -> void:
	var t = ev.tool
	if t == null or not t.has_method("tool_preview") or not ev.in_map(ev.hover):
		if ev.in_map(ev.hover):
			draw_polyline(_closed(_diamond(ev.hover)), Color(1, 1, 1, 0.8), 1.5)
		return
	var pv: Dictionary = t.tool_preview(ev.hover)
	var col: Color = pv.get("color", Color(1, 1, 1, 0.35))
	var cells: Array = pv.get("cells", [])
	for c in cells:
		draw_colored_polygon(_diamond(c), col)
	for ln in pv.get("lines", []):
		draw_line(ev.world_to_screen(Vector2(ln[0]) + Vector2(0.5, 0.5)), ev.world_to_screen(Vector2(ln[1]) + Vector2(0.5, 0.5)), Color(1, 1, 0.4, 0.9), 3.0)
	for p in pv.get("points", []):
		draw_circle(ev.world_to_screen(Vector2(p) + Vector2(0.5, 0.5)), 6.0, Color(1, 0.9, 0.2))
	draw_polyline(_closed(_diamond(ev.hover)), Color(1, 1, 1, 0.9), 1.5)
	var txt := String(pv.get("text", ""))
	if txt != "":
		var p2: Vector2 = ev.world_to_screen(Vector2(ev.hover) + Vector2(1.2, 0.2))
		draw_string(ThemeDB.fallback_font, p2, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, pv.get("text_color", Color.WHITE))


func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var out := p.duplicate()
	out.append(p[0])
	return out
