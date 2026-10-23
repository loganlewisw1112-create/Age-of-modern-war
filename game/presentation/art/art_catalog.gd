class_name ArtCatalog
extends RefCounted
## Runtime access to the generated pixel art (owner: agent C-art). Contract: docs/CONTRACTS.md section 7.
## PNGs are read from res://assets/generated/ with Image.load_from_file (no import pipeline), described by
## manifest.json (written by tools/gen_art.gd). Team colour is applied lazily per (sprite, colour) from a
## greyscale mask. Missing art never crashes: it returns a magenta placeholder.

const BASE := "res://assets/generated/"
const FACING_STEP := PI / 4.0

static var _placeholder: Texture2D = null
static var _loaded := false
static var _man: Dictionary = {}
static var _imgs: Dictionary = {}    # rel path -> Image (null when missing)
static var _texs: Dictionary = {}    # rel path -> Texture2D
static var _sheets: Dictionary = {}  # "rel|#color" -> tinted Image
static var _frames: Dictionary = {}  # "rel|#color|col|row" -> Texture2D
static var _fx: Dictionary = {}
static var _rings: Dictionary = {}
static var _fog: Dictionary = {}


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	# res:// paths work both from source and inside an exported .pck (globalize_path does not).
	var p := BASE + "manifest.json"
	if FileAccess.file_exists(p):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			_man = parsed
	if _man.is_empty():
		push_warning("ArtCatalog: manifest.json missing; run tools/gen_art.gd. Using placeholders.")


static func manifest() -> Dictionary:
	load_all()
	return _man


static func _ph() -> Texture2D:
	if _placeholder == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA)
		_placeholder = ImageTexture.create_from_image(img)
	return _placeholder


static func _image(rel: String) -> Image:
	if _imgs.has(rel):
		return _imgs[rel]
	var img: Image = null
	var p := BASE + rel
	if rel != "" and FileAccess.file_exists(p):
		img = Image.load_from_file(p)  # running from source: raw PNG
	elif rel != "" and ResourceLoader.exists(p):
		# exported build: only the imported (lossless) texture is packed, not the raw PNG
		var tex = load(p)
		if tex is Texture2D:
			img = tex.get_image()
	if img != null and img.is_empty():
		img = null
	if img != null:
		if img.is_compressed():
			img.decompress()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
	_imgs[rel] = img
	return img


static func _texture(rel: String) -> Texture2D:
	if _texs.has(rel):
		return _texs[rel]
	var img := _image(rel)
	var t: Texture2D = ImageTexture.create_from_image(img) if img != null else _ph()
	_texs[rel] = t
	return t


## Sheet tinted with the team colour wherever the mask is set (mask "" = untinted).
static func _sheet(rel: String, mask: String, col: Color) -> Image:
	var key := "%s|%s" % [rel, col.to_html()]
	if _sheets.has(key):
		return _sheets[key]
	var img := _image(rel)
	var m := _image(mask) if mask != "" else null
	if img != null and m != null and m.get_size() == img.get_size():
		img = img.duplicate()
		for y in img.get_height():
			for x in img.get_width():
				if m.get_pixel(x, y).a > 0.0:
					var b := img.get_pixel(x, y)
					var k := 0.45 + b.r * 0.9
					img.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, b.a).clamp())
	_sheets[key] = img
	return img


static func _frame(rel: String, mask: String, col: Color, fw: int, fh: int, cx: int, cy: int) -> Texture2D:
	var key := "%s|%s|%d|%d" % [rel, col.to_html(), cx, cy]
	if _frames.has(key):
		return _frames[key]
	var sheet := _sheet(rel, mask, col)
	var t: Texture2D = _ph()
	if sheet != null and (cx + 1) * fw <= sheet.get_width() and (cy + 1) * fh <= sheet.get_height():
		t = ImageTexture.create_from_image(sheet.get_region(Rect2i(cx * fw, cy * fh, fw, fh)))
	_frames[key] = t
	return t


static func _ihash(x: int, y: int, s: int) -> int:
	var h := (x * 374761393 + y * 668265263 + s * 1442695041) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return (h ^ (h >> 16)) & 0xFFFF


# ---------------------------------------------------------------- terrain
static func terrain_texture(code: int, variant: int) -> Texture2D:
	load_all()
	var t: Dictionary = _man.get("terrain", {}).get(str(code), {})
	if t.is_empty():
		return _ph()
	var n := maxi(1, int(t.get("variants", 1)))
	return _texture("terrain/%s_%d.png" % [String(t.name), posmod(variant, n)])


static func terrain_variants(code: int) -> int:
	load_all()
	if code == 4:  # water: variants are animation phases; a static bake uses phase 0 (seamless waves)
		return 1
	return maxi(1, int(_man.get("terrain", {}).get(str(code), {}).get("variants", 1)))


## Animated water tile for time t (seconds). Optional API.
static func water_frame(t_seconds: float) -> Texture2D:
	return terrain_texture(4, int(floor(t_seconds * 3.0)))


static func decor(code: int, cell: Vector2i) -> Dictionary:
	load_all()
	var kind := ""
	var h := _ihash(cell.x, cell.y, 17)
	if code == 3:
		kind = "tree"
	elif code == 7 and h % 100 < 70:
		kind = "rock"
	if kind == "":
		return {}
	var list: Array = _man.get("decor", {}).get(kind, [])
	if list.is_empty():
		return {}
	var d: Dictionary = list[_ihash(cell.x, cell.y, 23) % list.size()]
	var jx := _ihash(cell.x, cell.y, 29) % 13 - 6
	var jy := _ihash(cell.x, cell.y, 31) % 7 - 3
	return {"texture": _texture(String(d.file)), "offset": Vector2(-float(d.pivot[0]) + jx, -float(d.pivot[1]) + jy)}


# ---------------------------------------------------------------- entities
static func facing_index(facing: float) -> int:
	return posmod(int(round(facing / FACING_STEP)), 8)


static func entity_sprite(e: Dictionary, team_color: Color, anim_time: float) -> Dictionary:
	load_all()
	var def := String(e.get("def", ""))
	match String(e.get("kind", "")):
		"unit":
			var spec: Dictionary = _man.get("infantry", {}).get(def, _man.get("vehicles", {}).get(def, {}))
			if not spec.is_empty():
				var frames: Array = spec.frames
				var fi := 0
				if int(e.get("firing", 0)) > 0:
					fi = frames.find("fire")
				elif bool(e.get("moving", false)):
					var ph := int(floor(anim_time * 6.0 + int(e.get("id", 0)) * 0.37))
					if frames.has("walk_a"):
						fi = frames.find("walk_a") if ph % 2 == 0 else frames.find("walk_b")
					else:
						fi = frames.find("move") if ph % 2 == 0 else 0
				return _sheet_sprite(spec, team_color, maxi(0, fi), facing_index(float(e.get("facing", 0.0))))
		"building":
			var b: Dictionary = _man.get("buildings", {}).get(def, {})
			if not b.is_empty():
				var st := "built"
				if not bool(e.get("built", true)):
					st = "build_%d" % clampi(int(float(e.get("progress", 0.0)) * 3.0), 0, 2)
				var s: Dictionary = b.states.get(st, b.states.built)
				var img := _sheet(String(s.file), String(s.mask), team_color)
				if img != null:
					return {"texture": _frame(String(s.file), String(s.mask), team_color, img.get_width(), img.get_height(), 0, 0),
						"offset": Vector2(-float(b.pivot[0]), -float(b.pivot[1])), "flip_h": false}
		"resource":
			var r: Dictionary = _man.get("resources", {}).get(String(e.get("res", def)), _man.get("resources", {}).get(def, {}))
			if not r.is_empty():
				return {"texture": _texture(String(r.file)), "offset": Vector2(-float(r.pivot[0]), -float(r.pivot[1])), "flip_h": false}
		"wreck":
			var vw: Dictionary = _man.get("vehicle_wrecks", {}).get(def, {})
			if not vw.is_empty():
				return _sheet_sprite(vw, Color.WHITE, 0, facing_index(float(e.get("facing", 0.0))), false)
			var rb: Dictionary = _man.get("rubble", {}).get(str(clampi(int(e.get("size", 1)), 1, 3)), {})
			if not rb.is_empty():
				return {"texture": _texture(String(rb.file)), "offset": Vector2(-float(rb.pivot[0]), -float(rb.pivot[1])), "flip_h": false}
	return {"texture": _ph(), "offset": Vector2(-8, -16), "flip_h": false}


## Bridge-span overlay for ONE bridge cell (G2). state: "intact" | "damaged" | "ruined".
## Draw at world_to_screen(cell + Vector2(0.5, 0.5)) + offset (anchor = cell centre, like decor()),
## over the terrain bake and under entities. The outer cells of the |x - y| <= 1 road band carry the
## railings (side from sign(cell.x - cell.y)); the variant is deterministic per cell.
## Unknown state or missing art -> {texture: placeholder, offset: (-8, -16)}.
static func bridge_overlay(state: String, cell: Vector2i) -> Dictionary:
	load_all()
	var b: Dictionary = _man.get("bridge", {})
	var d := cell.x - cell.y
	var side := "r" if d > 0 else ("l" if d < 0 else "c")
	var st: Dictionary = b.get("states", {}).get(state, {})
	var files: Array = st.get(side, [])
	if files.is_empty():
		return {"texture": _ph(), "offset": Vector2(-8, -16)}
	var rel := String(files[_ihash(cell.x, cell.y, 41) % files.size()])
	var piv: Array = b.get("pivot", [32, 40])
	return {"texture": _texture(rel), "offset": Vector2(-float(piv[0]), -float(piv[1]))}


static func _sheet_sprite(spec: Dictionary, col: Color, frame: int, row: int, tinted := true) -> Dictionary:
	var mask := String(spec.get("mask", "")) if tinted else ""
	var t := _frame(String(spec.file), mask, col, int(spec.fw), int(spec.fh), frame, row)
	return {"texture": t, "offset": Vector2(-float(spec.pivot[0]), -float(spec.pivot[1])), "flip_h": false}


# ---------------------------------------------------------------- effects / UI
## Effects: muzzle, explosion_small, explosion_large, smoke; G2: disabled_smoke (6-frame loop, pivot at
## the base of the column), pinned (2-frame marker), cover (1-frame pip), retreat (2-frame chevron, +x).
static func effect_frames(name: String) -> Array:
	load_all()
	if _fx.has(name):
		return _fx[name]
	var spec: Dictionary = _man.get("effects", {}).get(name, {})
	var arr: Array = []
	var img := _image(String(spec.get("file", "")))
	if img != null:
		var fw := int(spec.fw)
		for i in int(spec.frames):
			arr.append(ImageTexture.create_from_image(img.get_region(Rect2i(i * fw, 0, fw, int(spec.fh)))))
	if arr.is_empty():
		arr = [_ph()]
	_fx[name] = arr
	return arr


static func icon(id: String) -> Texture2D:
	load_all()
	var rel = _man.get("icons", {}).get(id)
	if rel == null:
		return _ph()
	return _texture(String(rel))


## Iso ellipse ring sized to `size_tiles` (footprint width in tiles); drawn centred on the entity.
static func selection_ring(size_tiles: float) -> Texture2D:
	var s := snappedf(clampf(size_tiles, 0.25, 6.0), 0.25)
	if _rings.has(s):
		return _rings[s]
	var rx := maxf(9.0, s * 32.0 * 0.92)
	var ry := rx * 0.5
	var w := int(ceil(rx * 2.0)) + 4
	var h := int(ceil(ry * 2.0)) + 4
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := w * 0.5
	var cy := h * 0.5
	for y in h:
		for x in w:
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var d := sqrt(dx * dx + dy * dy)
			var px := absf(d - 1.0) * rx
			if px < 1.6:
				var a := 1.0 if px < 0.8 else 0.5
				var front := 1.0 if dy > -0.2 else 0.7
				img.set_pixel(x, y, Color(0.62, 0.95, 0.55, a * front))
	var t := ImageTexture.create_from_image(img)
	_rings[s] = t
	return t


static func fog_tile(kind: String) -> Texture2D:
	load_all()
	if _fog.has(kind):
		return _fog[kind]
	var rel = _man.get("fog", {}).get(kind)
	var t: Texture2D = _texture(String(rel)) if rel != null else _ph()
	if t == _ph() and (kind == "unexplored" or kind == "explored"):
		var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
		var c := Color(0.03, 0.035, 0.04, 1.0) if kind == "unexplored" else Color(0.10, 0.12, 0.16, 0.55)
		for y in 32:
			var hw := (y + 1) * 2 if y < 16 else (32 - y) * 2
			for x in range(32 - hw, 32 + hw):
				img.set_pixel(x, y, c)
		t = ImageTexture.create_from_image(img)
	_fog[kind] = t
	return t
