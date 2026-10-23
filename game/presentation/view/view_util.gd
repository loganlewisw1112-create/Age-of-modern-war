extends RefCounted
## Shared helpers for the view layers (owner: agent D). No class_name: preload it.
## Detects ArtCatalog's magenta placeholder and supplies readable procedural fallbacks so the
## match stays legible while real art is missing. Never crashes on missing art.

const TERRAIN_COLORS := [
	Color(0.36, 0.47, 0.24),  # grass
	Color(0.52, 0.42, 0.28),  # dirt
	Color(0.47, 0.45, 0.41),  # road
	Color(0.20, 0.33, 0.17),  # forest
	Color(0.17, 0.31, 0.49),  # water
	Color(0.46, 0.35, 0.22),  # bridge
	Color(0.30, 0.43, 0.52),  # ford
	Color(0.43, 0.41, 0.37),  # ridge
]

static var _ph_cache: Dictionary = {}     # texture rid id -> bool
static var _fallback: Dictionary = {}     # key -> Texture2D


## True if tex is null or ArtCatalog's magenta placeholder (or any solid-magenta texture).
static func is_placeholder(tex: Texture2D) -> bool:
	if tex == null:
		return true
	var key := tex.get_rid().get_id()
	if _ph_cache.has(key):
		return _ph_cache[key]
	var ph := false
	var sz := tex.get_size()
	if sz.x <= 16 and sz.y <= 16:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			var c := img.get_pixel(int(sz.x) / 2, int(sz.y) / 2)
			ph = c.r > 0.95 and c.b > 0.95 and c.g < 0.05
	_ph_cache[key] = ph
	return ph


## Flat diamond tile (64x32) for a terrain code, with a little per-variant/per-cell noise.
static func terrain_tile_image(code: int, variant: int) -> Image:
	var key := "t%d_%d" % [code, variant]
	if _fallback.has(key):
		return _fallback[key]
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var base: Color = TERRAIN_COLORS[clampi(code, 0, TERRAIN_COLORS.size() - 1)]
	var sd := code * 977 + variant * 131
	for y in 32:
		# half-width of the diamond at row y (rows 0..15 grow, 16..31 shrink)
		var hw := (y + 1) * 2 if y < 16 else (32 - y) * 2
		for x in range(32 - hw, 32 + hw):
			var h := ((x * 73856093) ^ (y * 19349663) ^ sd) & 255
			var n := (float(h) / 255.0 - 0.5) * 0.06
			var c := Color(base.r + n, base.g + n, base.b + n, 1.0)
			if code == Terrain.ROAD and abs(x - 32) < 3 and y % 6 < 3:
				c = c.lightened(0.15)
			if code == Terrain.WATER and (h & 31) == 0:
				c = c.lightened(0.18)
			img.set_pixel(x, y, c)
	_fallback[key] = img
	return img


static func _circle_tex(key: String, radius: int, fill: Color, outline: Color) -> Texture2D:
	if _fallback.has(key):
		return _fallback[key]
	var d := radius * 2 + 2
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(d, d) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if dist <= radius - 1.0:
				img.set_pixel(x, y, fill)
			elif dist <= radius + 0.5:
				img.set_pixel(x, y, outline)
	var t := ImageTexture.create_from_image(img)
	_fallback[key] = t
	return t


## Procedural iso block for a building footprint of `size` tiles.
static func _block_tex(key: String, size: int, col: Color, height: int, unfinished: bool) -> Texture2D:
	if _fallback.has(key):
		return _fallback[key]
	var w := size * 64
	var dh := size * 32
	var img := Image.create(w, dh + height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half := w / 2
	for y in dh + height:
		for x in w:
			var fx := float(x - half) / float(half)
			# top face: diamond centred at (half, dh/2) shifted up by 0 (top of image)
			var ty := float(y) - dh * 0.5
			var in_top: bool = abs(fx) + abs(ty / (dh * 0.5)) <= 1.0
			# side band: below the lower edge of the top diamond, height `height`
			var lower_edge: float = dh * 0.5 + (1.0 - abs(fx)) * dh * 0.5
			var in_side: bool = float(y) > lower_edge and float(y) <= lower_edge + height and abs(fx) <= 1.0
			if in_top:
				var c := col.lightened(0.25)
				if unfinished and ((x / 6 + y / 6) % 2 == 0):
					c = Color(0.55, 0.5, 0.35)
				img.set_pixel(x, y, c)
			elif in_side:
				img.set_pixel(x, y, col.darkened(0.25 if fx < 0 else 0.45))
	var t := ImageTexture.create_from_image(img)
	_fallback[key] = t
	return t


## Fallback sprite dict {texture, offset, flip_h} matching the ArtCatalog.entity_sprite contract.
static func fallback_sprite(e: Dictionary, team: Color) -> Dictionary:
	match String(e.kind):
		"unit":
			var r := float(Content.unit(e.def).get("radius", 0.3))
			var px := 5 if r < 0.45 else 8
			var t := _circle_tex("u%d_%s" % [px, team.to_html()], px, team, Color(0.05, 0.05, 0.05))
			return {"texture": t, "offset": Vector2(-px - 1, -px * 2 - 2), "flip_h": false}
		"building":
			var s := int(e.size)
			var unfinished := not bool(e.get("built", true))
			var hgt := 10 + s * 6
			var t := _block_tex("b%d_%s_%s" % [s, team.to_html(), unfinished], s, team, hgt, unfinished)
			# ground contact (sprite position) = footprint centre; image top-face centre at (s*32, s*16)
			return {"texture": t, "offset": Vector2(-s * 32, -s * 16 - hgt), "flip_h": false}
		"resource":
			var col := Color(0.75, 0.62, 0.35) if e.get("res", "") == "salvage" else Color(0.55, 0.6, 0.68)
			var t := _circle_tex("r_%s" % col.to_html(), 5, col, Color(0.15, 0.12, 0.08))
			return {"texture": t, "offset": Vector2(-6, -9), "flip_h": false}
		"wreck":
			var s := int(e.get("size", 1))
			var px := 6 if s <= 1 else 14
			var t := _circle_tex("w%d" % px, px, Color(0.18, 0.17, 0.16), Color(0.08, 0.08, 0.08))
			return {"texture": t, "offset": Vector2(-px - 1, -px - 1), "flip_h": false}
	return {}
