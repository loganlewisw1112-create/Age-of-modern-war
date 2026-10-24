extends RefCounted
## G3b far-zoom LOD icons for R4 (agent ART4-2, board seq 509): manifest.lod_icons = {"*": {class:
## {file, pivot}}}. White/greyscale 16x16 glyphs with a dark 1 px outline; R4 tints them with the side
## colour via modulate. R4's four classes (infantry, vehicle, air, building) plus vehicle_light,
## vehicle_heavy, artillery and dot. Deterministic pixel plotting, no RNG.
const S := 16
const HI := Color(1, 1, 1, 1)
const MID := Color(0.8, 0.8, 0.8, 1)
const LO := Color(0.62, 0.62, 0.62, 1)
const EDGE := Color(0.06, 0.06, 0.06, 1)
const CLASSES := ["infantry", "vehicle", "vehicle_light", "vehicle_heavy", "artillery", "air", "building", "dot"]


static func build(out: Dictionary) -> void:
	var set := {}
	for c in CLASSES:
		var path := "icons/lod_%s.png" % c
		out.images[path] = glyph(c)
		set[c] = {"file": path, "pivot": [S / 2, S / 2]}
	var man: Dictionary = out.manifest.get("lod_icons", {})
	man["*"] = set
	out.manifest["lod_icons"] = man


static func _r(im: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx >= 0 and yy >= 0 and xx < S and yy < S:
				im.set_pixel(xx, yy, c)


## Body with a lit top half and a darker lower half, so the shape reads as a solid at 1x.
static func _body(im: Image, x: int, y: int, w: int, h: int) -> void:
	_r(im, x, y, w, h, MID)
	_r(im, x, y, w, maxi(1, h / 2), HI)


static func glyph(c: String) -> Image:
	var im := Image.create(S, S, false, Image.FORMAT_RGBA8)
	match c:
		"infantry":
			_r(im, 6, 2, 4, 4, HI)
			_body(im, 5, 6, 6, 5)
			_r(im, 5, 11, 2, 3, LO)
			_r(im, 9, 11, 2, 3, LO)
		"vehicle":
			_body(im, 2, 7, 12, 5)
			_r(im, 5, 4, 6, 3, HI)
			_r(im, 11, 5, 4, 1, MID)
			_r(im, 3, 12, 10, 1, LO)
		"vehicle_light":
			_body(im, 3, 6, 10, 5)
			_r(im, 4, 11, 2, 2, LO)
			_r(im, 10, 11, 2, 2, LO)
		"vehicle_heavy":
			_body(im, 1, 7, 14, 6)
			_r(im, 4, 4, 7, 3, HI)
			_r(im, 11, 5, 5, 1, MID)
			_r(im, 2, 13, 12, 1, LO)
		"artillery":
			_body(im, 2, 9, 10, 4)
			for i in 8:
				_r(im, 6 + i, 8 - i, 2, 1, HI)
			_r(im, 3, 13, 8, 1, LO)
		"air":
			_r(im, 7, 1, 2, 14, HI)
			_r(im, 1, 6, 14, 2, HI)
			_r(im, 2, 8, 12, 1, MID)
			_r(im, 4, 13, 8, 1, MID)
		"building":
			_body(im, 2, 5, 12, 9)
			_r(im, 4, 2, 3, 3, MID)
			_r(im, 6, 10, 4, 4, LO)
		"dot":
			_r(im, 6, 5, 4, 6, HI)
			_r(im, 5, 6, 6, 4, HI)
			_r(im, 6, 9, 4, 2, MID)
	_outline(im)
	return im


static func _outline(im: Image) -> void:
	var src := im.duplicate()
	for y in S:
		for x in S:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = Vector2i(x, y) + d
				if p.x >= 0 and p.y >= 0 and p.x < S and p.y < S and src.get_pixel(p.x, p.y).a > 0.0:
					im.set_pixel(x, y, EDGE)
					break
