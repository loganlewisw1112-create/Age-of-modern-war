extends StyleBox
## UI5a (G5): military plate StyleBox. A chamfered gunmetal plate with a 1 px top bevel, an
## optional accent stripe along the top edge and optional corner rivets. Drawn with plain
## RenderingServer primitives (no textures), so it scales cleanly at every UI scale.

var fill := Color("1b2226")
var edge := Color("4a565c")
var accent := Color(0, 0, 0, 0)     # top stripe colour (alpha 0 = none)
var stripe := 0                      # stripe height in px
var edge_w := 1.0
var chamfer := 6.0
var rivets := false
var bevel := true
var shade := 0.0                     # 0..1 darkening toward the bottom (two-tone plate)


static func make(p_fill: Color, p_edge: Color, p_chamfer: float = 6.0, margin: float = 8.0) -> StyleBox:
	var s = load("res://presentation/ui5/kit/mil_box.gd").new()
	s.fill = p_fill
	s.edge = p_edge
	s.chamfer = p_chamfer
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.75
	s.content_margin_bottom = margin * 0.75
	return s


func _shape(r: Rect2) -> PackedVector2Array:
	var c := minf(chamfer, minf(r.size.x, r.size.y) * 0.3)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	if c < 0.5:
		return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])
	# top-left and bottom-right corners are cut (asymmetric "stencil plate" look)
	return PackedVector2Array([Vector2(x0 + c, y0), Vector2(x1, y0), Vector2(x1, y1 - c),
		Vector2(x1 - c, y1), Vector2(x0, y1), Vector2(x0, y0 + c)])


func _draw(ci: RID, rect: Rect2) -> void:
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return
	var pts := _shape(rect)
	if fill.a > 0.0:
		if shade > 0.0:
			var lo := fill.darkened(shade)
			var cols := PackedColorArray()
			for p in pts:
				cols.append(fill.lerp(lo, clampf((p.y - rect.position.y) / rect.size.y, 0.0, 1.0)))
			RenderingServer.canvas_item_add_polygon(ci, pts, cols)
		else:
			RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([fill]))
	if stripe > 0 and accent.a > 0.0:
		var c := minf(chamfer, minf(rect.size.x, rect.size.y) * 0.3)
		var sh := float(stripe)
		var sp := PackedVector2Array([Vector2(rect.position.x + c, rect.position.y), Vector2(rect.end.x, rect.position.y),
			Vector2(rect.end.x, rect.position.y + sh), Vector2(rect.position.x + c + sh, rect.position.y + sh)])
		if c < 0.5:
			sp = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
				Vector2(rect.end.x, rect.position.y + sh), rect.position + Vector2(0, sh)])
		RenderingServer.canvas_item_add_polygon(ci, sp, PackedColorArray([accent]))
	if bevel and rect.size.y > 8.0:
		var c2 := minf(chamfer, minf(rect.size.x, rect.size.y) * 0.3)
		var yb := rect.position.y + float(stripe) + 1.5
		RenderingServer.canvas_item_add_line(ci, Vector2(rect.position.x + c2 + 1.0, yb), Vector2(rect.end.x - 1.5, yb),
			Color(1, 1, 1, 0.07), 1.0)
		RenderingServer.canvas_item_add_line(ci, Vector2(rect.position.x + 1.5, rect.end.y - 1.5),
			Vector2(rect.end.x - c2 - 1.0, rect.end.y - 1.5), Color(0, 0, 0, 0.35), 1.0)
	if edge.a > 0.0 and edge_w > 0.0:
		var loop := pts.duplicate()
		loop.append(pts[0])
		RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([edge]), edge_w)
	if rivets and rect.size.x > 40.0 and rect.size.y > 30.0:
		var inset := chamfer + 4.0
		for p in [Vector2(rect.end.x - 6.0, rect.position.y + 6.0 + stripe), Vector2(rect.position.x + 6.0, rect.end.y - 6.0),
				Vector2(rect.position.x + inset, rect.position.y + 6.0 + stripe), Vector2(rect.end.x - inset, rect.end.y - 6.0)]:
			RenderingServer.canvas_item_add_circle(ci, p + Vector2(0.6, 0.8), 1.9, Color(0, 0, 0, 0.55))
			RenderingServer.canvas_item_add_circle(ci, p, 1.6, edge.lightened(0.25))
