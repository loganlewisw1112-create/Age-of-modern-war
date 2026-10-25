extends RefCounted
## G6 proposal art harness helpers (scratch only, never written into the repo).
## Modules render with the game's own art libraries (res://tools/art/*) and register sheets in `out`
## exactly like the game's modules do:
##   vehicles  -> SL.veh_sheet(out, id, {"fw","fh","pivot"}, draw(cv, rot, f, wreck, o), frames)
##   squads    -> SL.squad_sheet(out, id, n, draw(cv48x36, k, f, alive), frames)
##   buildings / emplacements / fortifications -> bld(out, id, size, top, draw(cv, o, f))   (f = rotation 0..3)
## Then each module lists showcase picks in SHOW: {id: {"row": facing (vehicles 0, squads 1, buildings f),
## "frame": frame name, "ground": terrain tile name, "fx": optional}}.
const P = preload("res://tools/art/pix.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")

const TEAM := Color("#4f7db0")    # content/rules.json side colour 1 (player)
const ENEMY := Color("#b5583a")   # side colour 2


## Building-type asset: rendered for rotations f = 0 and 1 (game buildings use 4; two are enough for a
## proposal plate). draw: Callable(cv, o: Vector2, f: int). Outline applied here, like g5_bld._state.
static func bld(out: Dictionary, id: String, size: int, top: int, draw: Callable) -> void:
	var man: Dictionary = out.manifest.get("buildings", {})
	var entry := {"size": size, "rots": {}}
	for f in 2:
		var co: Array = K.canvas(size, top)
		var cv = co[0]
		var o: Vector2 = co[1]
		draw.call(cv, o, f)
		cv.outline()
		var stem := "buildings/%s_f%d" % [id, f]
		out.images[stem + ".png"] = cv.img
		out.images[stem + "_mask.png"] = cv.mask
		entry.rots[str(f)] = {"file": stem + ".png", "mask": stem + "_mask.png"}
		entry["pivot"] = [int(o.x), int(o.y)]
		entry["fw"] = cv.w
		entry["fh"] = cv.h
	man[id] = entry
	out.manifest["buildings"] = man


## Team tint exactly as presentation/art/art_catalog.gd _sheet().
static func tint(img: Image, mask: Image, col: Color) -> Image:
	var r := img.duplicate()
	if mask == null or mask.get_size() != img.get_size():
		return r
	for y in r.get_height():
		for x in r.get_width():
			if mask.get_pixel(x, y).a > 0.0:
				var b: Color = r.get_pixel(x, y)
				var k: float = 0.45 + b.r * 0.9
				r.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, b.a).clamp())
	return r


static var _tiles := {}


const ALIAS := {"conc": "road", "sand": "beach", "mud": "dirt", "rubble": "dirt", "concrete": "road"}


static func tiles(name: String) -> Array:
	name = String(ALIAS.get(name, name))
	if _tiles.has(name):
		return _tiles[name]
	var arr: Array = []
	for i in 8:
		var p := "res://assets/generated/terrain/%s_%d.png" % [name, i]
		if not FileAccess.file_exists(p):
			break
		var im := Image.load_from_file(ProjectSettings.globalize_path(p))
		im.convert(Image.FORMAT_RGBA8)
		arr.append(im)
	_tiles[name] = arr
	return arr


## Iso terrain ground (64x32 tiles) covering a w x h image. ground: tile name, or "a|b" to split the plate
## (left/top part a, right/bottom part b along the screen diagonal) for coasts and river banks.
static func ground(w: int, h: int, name: String, seed := 1) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color8(70, 76, 50))
	var names := name.split("|")
	var cx := w / 2
	var cy := h / 2
	for i in range(-8, 9):
		for j in range(-8, 9):
			var tx := cx + (i - j) * 32 - 32
			var ty := cy + (i + j) * 16 - 16
			if tx < -64 or ty < -32 or tx > w or ty > h:
				continue
			var nm: String = names[0]
			if names.size() > 1 and i + j > 0:
				nm = names[1]
			var set: Array = tiles(nm)
			if set.is_empty():
				set = tiles("grass")
			var t: Image = set[P.hi(i + 20, j + 20, seed, set.size())]
			img.blend_rect(t, Rect2i(0, 0, 64, 32), Vector2i(tx, ty))
	return img


## Cut one frame (col, row) of a sheet.
static func frame(sheet: Image, fw: int, fh: int, col: int, row: int) -> Image:
	return sheet.get_region(Rect2i(col * fw, row * fh, fw, fh))


## Plate: terrain + tinted sprite, integer zoom so the sprite fills a 240x150 plate. Returns [image, zoom].
## Aircraft: alt = px the sprite floats above its ground point (game renderer convention: alt_px), shadow =
## [rx, ry] soft ellipse drawn on the ground under the pivot. pivot = the sheet pivot [x, y].
static func plate(spr: Image, ground_name: String, seed := 1, pw := 240, ph := 150, alt := 0, shadow := [], pivot := []) -> Array:
	var w := spr.get_width()
	var h := spr.get_height()
	var s := clampi(mini((pw - 16) / w, (ph - 12 - alt) / h), 1, 3)
	var nw := int(ceil(float(pw) / s))
	var nh := int(ceil(float(ph) / s))
	var g := ground(nw, nh, ground_name, seed)
	var x0 := (nw - w) / 2
	var y0 := (nh - h) / 2 + 2 - alt / 2
	if shadow.size() == 2 and pivot.size() == 2:
		var sc = P.Canvas.new(nw, nh)
		sc.ellipse(x0 + float(pivot[0]), y0 + float(pivot[1]) + alt, float(shadow[0]), float(shadow[1]), Color.BLACK, true)
		sc.flush_shadow(Color(0.04, 0.05, 0.03, 0.38))
		g.blend_rect(sc.img, Rect2i(0, 0, nw, nh), Vector2i.ZERO)
	g.blend_rect(spr, Rect2i(0, 0, w, h), Vector2i(x0, y0))
	g.resize(nw * s, nh * s, Image.INTERPOLATE_NEAREST)
	return [g.get_region(Rect2i(0, 0, pw, ph)), s]
