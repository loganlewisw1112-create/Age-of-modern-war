extends RefCounted
## G4e editor tool icons (agent ART-U): 32x32 glyphs on the fx_ui dark panel, light ink + accents, dark
## outline. Writes icons/ed_<id>.png, manifest.icons["ed_<id>"] and manifest.editor_icons[<id>] = path.
## Symmetry ids follow presentation/editor/symmetry.gd MODES ("sym_" + mode).
const P = preload("res://tools/art/pix.gd")
const FX = preload("res://tools/art/fx_ui.gd")

const IDS := ["brush", "line", "rect", "fill", "river", "lake", "bridge", "tree", "rock", "resource", "eraser",
	"sym_off", "sym_mirror_x", "sym_mirror_y", "sym_mirror_diag", "sym_rotate_180", "sym_four_way",
	"undo", "redo", "validate", "test_play", "player_start", "region", "trigger"]
const INK := Color8(222, 224, 210)
const INK_D := Color8(150, 154, 140)
const WATER := Color8(86, 150, 206)
const WATER_L := Color8(150, 200, 236)
const LEAF := Color8(92, 150, 70)
const BARK := Color8(120, 88, 56)
const STONE := Color8(150, 146, 136)
const GOLD := Color8(232, 190, 80)
const TEAM := Color8(92, 140, 210)
const OK := Color8(110, 200, 100)
const WARN := Color8(236, 110, 70)


static func build(out: Dictionary) -> void:
	var icons: Dictionary = out.manifest.get("icons", {})
	var ed: Dictionary = out.manifest.get("editor_icons", {})
	for id in IDS:
		var cv = P.Canvas.new(32, 32)
		glyph(cv, id)
		cv.outline(Color(0.04, 0.04, 0.035, 1))
		var im: Image = FX._panel()
		im.blend_rect(cv.img, Rect2i(0, 0, 32, 32), Vector2i.ZERO)
		var path := "icons/ed_%s.png" % id
		out.images[path] = im
		icons["ed_" + id] = path
		ed[id] = path
	out.manifest["icons"] = icons
	out.manifest["editor_icons"] = ed


static func _thick(cv, a: Vector2, b: Vector2, c: Color, w := 2) -> void:
	for dy in w:
		for dx in w:
			cv.line_v(a + Vector2(dx, dy), b + Vector2(dx, dy), c)


static func _ring(cv, cx: float, cy: float, r: float, c: Color, w := 2.0) -> void:
	for y in 32:
		for x in 32:
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if d <= r and d >= r - w:
				cv.px(x, y, c)


static func _tri(cv, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	cv.poly(PackedVector2Array([a, b, c]), col)


## Arc arrow around (cx, cy) from angle a0 to a1 (radians), arrowhead at a1.
static func _arc(cv, cx: float, cy: float, r: float, a0: float, a1: float, c: Color) -> void:
	var n := 14
	for i in n:
		var t0 := a0 + (a1 - a0) * i / n
		var t1 := a0 + (a1 - a0) * (i + 1) / n
		_thick(cv, Vector2(cx + cos(t0) * r, cy + sin(t0) * r), Vector2(cx + cos(t1) * r, cy + sin(t1) * r), c)
	var tip := Vector2(cx + cos(a1) * r, cy + sin(a1) * r)
	var tg := Vector2(-sin(a1), cos(a1)) * signf(a1 - a0)
	var nrm := Vector2(cos(a1), sin(a1))
	_tri(cv, tip + tg * 5.0, tip + nrm * 4.5, tip - nrm * 4.5, c)


static func _dash(cv, a: Vector2, b: Vector2, c: Color) -> void:
	var n := int(a.distance_to(b) / 3.0)
	for i in n:
		if i % 2 == 0:
			cv.line_v(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), c)


static func _shape(cv, p: Vector2, c: Color, flip_x := false, flip_y := false) -> void:
	var sx := -1.0 if flip_x else 1.0
	var sy := -1.0 if flip_y else 1.0
	_tri(cv, p + Vector2(-3 * sx, -4 * sy), p + Vector2(4 * sx, 0), p + Vector2(-3 * sx, 4 * sy), c)


static func glyph(cv, id: String) -> void:
	match id:
		"brush":
			_thick(cv, Vector2(24, 6), Vector2(14, 17), BARK, 3)
			cv.rect(12, 16, 4, 3, INK_D)
			cv.ellipse(10, 22, 5, 4, INK)
			cv.ellipse(8, 24, 2, 1.5, TEAM)
		"line":
			_thick(cv, Vector2(7, 24), Vector2(24, 7), INK)
			cv.ellipse(7.5, 24.5, 2.5, 2.5, TEAM)
			cv.ellipse(24.5, 7.5, 2.5, 2.5, TEAM)
		"rect":
			for r in [[6, 8, 20, 2], [6, 22, 20, 2], [6, 8, 2, 16], [24, 8, 2, 16]]:
				cv.rect(r[0], r[1], r[2], r[3], INK)
			cv.rect(9, 11, 14, 10, Color(TEAM.r, TEAM.g, TEAM.b, 0.45))
		"fill":
			cv.poly(PackedVector2Array([Vector2(8, 12), Vector2(17, 6), Vector2(24, 15), Vector2(15, 22)]), INK)
			cv.poly(PackedVector2Array([Vector2(8, 12), Vector2(17, 6), Vector2(18, 9), Vector2(10, 14)]), INK_D)
			cv.ellipse(25, 21, 2, 3, TEAM)
			cv.rect(24, 17, 2, 3, TEAM)
		"river":
			for x in range(3, 29):
				var y := 16.0 + sin(x * 0.35) * 5.0
				cv.rect(x, int(y) - 2, 1, 5, WATER)
				cv.px(x, int(y) - 1, WATER_L)
		"lake":
			cv.ellipse(16, 17, 12, 8, WATER)
			cv.ellipse(14, 15, 7, 4, P.mul(WATER, 1.15))
			cv.rect(10, 14, 5, 1, WATER_L)
		"bridge":
			cv.rect(3, 22, 26, 5, WATER)
			cv.rect(3, 13, 26, 3, INK)
			for x in [6, 15, 24]:
				cv.rect(x, 16, 2, 8, INK_D)
		"tree":
			cv.rect(15, 18, 3, 9, BARK)
			cv.ellipse(16, 13, 8, 8, LEAF)
			cv.ellipse(13, 10, 3.5, 3, P.mul(LEAF, 1.25))
		"rock":
			cv.poly(PackedVector2Array([Vector2(5, 25), Vector2(9, 12), Vector2(17, 7), Vector2(25, 13), Vector2(27, 25)]), STONE)
			cv.poly(PackedVector2Array([Vector2(9, 12), Vector2(17, 7), Vector2(15, 17), Vector2(7, 20)]), P.mul(STONE, 1.2))
			cv.line(17, 7, 19, 24, P.mul(STONE, 0.7))
		"resource":
			for c in [[10, 14, 4], [17, 10, 5], [22, 17, 4]]:
				_tri(cv, Vector2(c[0], c[1] - c[2] * 2), Vector2(c[0] + c[2], c[1] + 8), Vector2(c[0] - c[2], c[1] + 8), GOLD)
				cv.line(c[0], c[1] - c[2] * 2 + 2, c[0], c[1] + 6, P.mul(GOLD, 1.25))
			cv.rect(5, 25, 22, 2, P.mul(STONE, 0.8))
		"eraser":
			cv.poly(PackedVector2Array([Vector2(6, 20), Vector2(16, 9), Vector2(26, 17), Vector2(16, 27)]), Color8(226, 150, 160))
			cv.poly(PackedVector2Array([Vector2(6, 20), Vector2(11, 14), Vector2(21, 22), Vector2(16, 27)]), INK)
		"sym_off":
			_shape(cv, Vector2(15, 16), INK)
			_ring(cv, 16, 16, 12, WARN)
			_thick(cv, Vector2(8, 24), Vector2(24, 8), WARN)
		"sym_mirror_x":
			_dash(cv, Vector2(16, 3), Vector2(16, 29), INK_D)
			cv.rect(15, 3, 2, 26, Color(INK_D.r, INK_D.g, INK_D.b, 0.5))
			_shape(cv, Vector2(9, 16), INK, true)
			_shape(cv, Vector2(23, 16), TEAM)
		"sym_mirror_y":
			cv.rect(3, 15, 26, 2, Color(INK_D.r, INK_D.g, INK_D.b, 0.5))
			_tri(cv, Vector2(10, 12), Vector2(22, 12), Vector2(16, 5), INK)
			_tri(cv, Vector2(10, 20), Vector2(22, 20), Vector2(16, 27), TEAM)
		"sym_mirror_diag":
			_thick(cv, Vector2(4, 27), Vector2(27, 4), Color(INK_D.r, INK_D.g, INK_D.b, 0.6))
			_tri(cv, Vector2(6, 6), Vector2(16, 7), Vector2(7, 16), INK)
			_tri(cv, Vector2(25, 25), Vector2(15, 24), Vector2(24, 15), TEAM)
		"sym_rotate_180":
			_shape(cv, Vector2(10, 11), INK)
			_shape(cv, Vector2(22, 21), TEAM, true, true)
			_arc(cv, 16, 16, 11, -0.4, 1.2, INK_D)
		"sym_four_way":
			cv.rect(15, 3, 2, 26, Color(INK_D.r, INK_D.g, INK_D.b, 0.5))
			cv.rect(3, 15, 26, 2, Color(INK_D.r, INK_D.g, INK_D.b, 0.5))
			for p in [Vector2(9, 9), Vector2(23, 9), Vector2(9, 23), Vector2(23, 23)]:
				cv.ellipse(p.x, p.y, 3.5, 3.5, TEAM if p.x > 16 and p.y > 16 else INK)
		"undo":
			_arc(cv, 17, 18, 8, 0.6, -PI * 1.0, INK)
		"redo":
			_arc(cv, 15, 18, 8, PI - 0.6, PI * 2.0, INK)
		"validate":
			_thick(cv, Vector2(6, 16), Vector2(13, 23), OK, 3)
			_thick(cv, Vector2(13, 23), Vector2(25, 8), OK, 3)
		"test_play":
			_tri(cv, Vector2(10, 6), Vector2(25, 16), Vector2(10, 26), OK)
			_tri(cv, Vector2(12, 10), Vector2(18, 13), Vector2(12, 14), P.mul(OK, 1.25))
		"player_start":
			cv.rect(9, 5, 2, 22, INK_D)
			cv.poly(PackedVector2Array([Vector2(11, 6), Vector2(25, 9), Vector2(11, 15)]), TEAM)
			cv.ellipse(10, 27, 6, 2, INK)
		"region":
			for e in [[Vector2(6, 7), Vector2(26, 7)], [Vector2(6, 25), Vector2(26, 25)], [Vector2(6, 7), Vector2(6, 25)], [Vector2(26, 7), Vector2(26, 25)]]:
				_dash(cv, e[0], e[1], INK)
			for p in [Vector2(5, 6), Vector2(25, 6), Vector2(5, 24), Vector2(25, 24)]:
				cv.rect(int(p.x), int(p.y), 3, 3, GOLD)
		"trigger":
			cv.poly(PackedVector2Array([Vector2(18, 3), Vector2(8, 18), Vector2(15, 18), Vector2(12, 29), Vector2(24, 12), Vector2(17, 12)]), GOLD)
