extends RefCounted
## G6 terrain-height art (owner: ELEV-VIEW; CONTRACTS_G6 s1/s7, PLAN_G6 A1 render). Drawn with the G4 terrain
## palettes (tools/art/g4_terrain_tiles.gd) and pix.gd noise so height reads as the same game. Written by
## tools/art/g6_terrain_gen.gd to res://assets/art/g6_terrain/ (+ manifest.json):
##   faces.png       1024x96 cliff-face material, block (biome * 4 + style) 64x96, row = px below the lip.
##                   Styles: 0 earth (grass/dirt/forest tops: turf lip, soil, rock low down), 1 rock (ridge/
##                   cliff/water: weathered natural rock), 2 sand (beach), 3 wall (man-made ground only:
##                   road/building/rail/bridge, concrete retaining wall). The renderer maps each face
##                   quad onto it (strata follow the tile edge, like the G4 cliff faces) and shades it with
##                   vertex colours (left face lit, right face dark, darker towards the foot).
##   ramp.png        1024x32 worn track + contour steps over a ramp tile, block (biome * 4 + rise dir N/E/S/W).
##   hscree_<b>.png  1024x64 G4 transition atlas layout (column = mask 1..15, row 0 edges, row 1 corners):
##                   stones and shadow on the low cell at the foot of a height cliff.
##   hrim.png        same layout: lit crest on the high cell along a drop.
##   rail_b<b>.png   64x32 RAIL (code 14) ballast bed per biome; rail_tracks.png 1024x32 sleepers + rails from
##                   the centre to each connected edge (column = 4-bit mask N1 E2 S4 W8; 0 = straight N-S).
const P = preload("res://tools/art/pix.gd")
const TL = preload("res://tools/art/g4_terrain_tiles.gd")
const TR = preload("res://tools/art/g4_terrain_trans.gd")

const STYLES := ["earth", "rock", "sand", "wall"]
const STYLE_OF_CODE := {0: 0, 1: 0, 2: 3, 3: 0, 4: 1, 5: 3, 6: 1, 7: 1, 8: 3, 9: 1, 10: 1, 11: 2, 12: 1, 13: 0, 14: 3}
const FACE_H := 96
const DIRS := ["N", "E", "S", "W"]
const RAIL_CODE := 14
const VU = preload("res://presentation/view/view_util.gd")   # level_px: the one tunable lift constant
## Edge midpoints in tile-local world units (u = x fraction, w = y fraction): N, E, S, W.
const MIDS := [Vector2(0.5, 0.0), Vector2(1.0, 0.5), Vector2(0.5, 1.0), Vector2(0.0, 0.5)]


static func build(out: Dictionary) -> void:
	out.images["faces.png"] = faces()
	out.images["ramp.png"] = ramps()
	out.images["hrim.png"] = trans_atlas("rim", 0)
	var scree := []
	var rail := []
	for b in 4:
		out.images["hscree_%d.png" % b] = trans_atlas("scree", b)
		scree.append("hscree_%d.png" % b)
		out.images["rail_b%d.png" % b] = rail_base(b)
		rail.append("rail_b%d.png" % b)
	out.images["rail_tracks.png"] = rail_tracks()
	var soc := {}
	for c in STYLE_OF_CODE:
		soc[str(c)] = STYLE_OF_CODE[c]
	out.manifest = {
		"group": "g6_terrain", "version": 1, "level_px": int(VU.LEVEL_PX_DEFAULT),
		"faces": {"file": "faces.png", "block": [64, FACE_H], "styles": STYLES, "style_of_code": soc},
		"ramp": {"file": "ramp.png", "block": [64, 32], "dirs": DIRS},
		"scree": scree, "rim": "hrim.png",
		"rail": {"code": RAIL_CODE, "base": rail, "tracks": "rail_tracks.png"},
	}


# ---------------------------------------------------------------- cliff faces
static func faces() -> Image:
	var img := Image.create(1024, FACE_H, false, Image.FORMAT_RGBA8)
	for b in 4:
		for s in 4:
			var ox := (b * 4 + s) * 64
			var sd := 4001 + b * 131 + s * 17
			for k in FACE_H:
				for x in 64:
					img.set_pixel(ox + x, k, _face_px(s, b, x, k, sd))
	return img


static func _face_px(s: int, b: int, x: int, k: int, sd: int) -> Color:
	var j := 0.95 + P.hn(x, k, sd + 13) * 0.1
	var rock: Array = TL.ROCK[b]
	var c: Color
	match s:
		0:  # earth (grass / dirt / forest tops): turf lip, soil bank, rock lower down on tall drops
			c = _earth(b, x, k, sd)
		1:  # rock (ridge / cliff / water banks): weathered natural rock
			c = (TL.SNOW if b == 2 else P.mul(rock[2], 0.95)) if k == 0 else _rock(rock, x, k, sd)
		2:  # sand bank (beach): soft sediment layers and slumped runnels
			c = _sand(b, x, k, sd)
		_:  # wall (road / building / rail / bridge only): concrete courses and joints under a bright coping
			var con: Array = TL.CONCRETE[b]
			c = P.mul(con[1], 0.92 + P.vnoise(x, k, 7.0, sd) * 0.12)
			if k <= 1:
				c = con[2]
			elif k % 8 == 2 or (x + (k / 8) * 8) % 16 == 0:
				c = con[0]
			if P.vnoise(x, k * 2, 4.0, sd + 9) > 0.74:
				c = P.mul(c, 0.86)
	if b == 2 and s != 3 and k > 2 and _pn(x, k, 8, 7.0, sd + 20) > 0.66:
		c = P.mix(c, TL.SNOW, 0.6)  # drifted snow patches
	return P.mul(c, j)


## Periodic value noise: lattice sx x sy px, wrapping every 64 px in x (sx divides 64), so a face block tiles
## seamlessly along a cliff edge (neighbouring cells sample the two 32-px halves of the block alternately).
static func _pn(x: float, y: float, sx: int, sy: float, s: int) -> float:
	var per := 64 / sx
	var fx := x / float(sx)
	var fy := y / sy
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var tx := fx - ix
	var ty := fy - iy
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var x0 := posmod(ix, per)
	var x1 := posmod(ix + 1, per)
	var a := lerpf(P.hn(x0, iy, s), P.hn(x1, iy, s), tx)
	var b := lerpf(P.hn(x0, iy + 1, s), P.hn(x1, iy + 1, s), tx)
	return lerpf(a, b, ty)


## Natural rock face: vertical weathering streaks, broken ledges (lit top, shadow under), meandering cracks,
## grit, darker towards the foot. No regular courses or joints (those read as masonry).
static func _rock(pal: Array, x: int, k: int, sd: int) -> Color:
	var streak := _pn(x, k, 4, 22.0, sd) * 0.6 + _pn(x, k, 16, 40.0, sd + 1) * 0.4
	var c: Color = P.mix(pal[0], pal[1], 0.15 + streak * 0.85)
	c = P.mul(c, 0.9 + _pn(x, k, 8, 8.0, sd + 2) * 0.2)
	for li in 3:
		var ly := 10.0 + li * 23.0 + (_pn(x, li * 7, 16, 1.0, sd + 3 + li) - 0.5) * 14.0
		var d := float(k) - ly
		if _pn(x, li, 8, 1.0, sd + 9 + li) > 0.38:
			if d >= -1.0 and d < 0.0:
				c = P.mix(c, pal[2], 0.5)
			elif d >= 0.0 and d < 2.5:
				c = P.mul(c, 0.68)
	var cr := absf(_pn(x, k, 4, 14.0, sd + 5) - 0.5)
	if k > 3 and cr < 0.035:
		c = P.mul(c, 0.64)
	elif k > 3 and cr < 0.07:
		c = P.mul(c, 0.88)
	var g := P.hn(x, k, sd + 7)
	if g > 0.965:
		c = P.mul(c, 1.16)
	elif g < 0.035:
		c = P.mul(c, 0.78)
	return P.mul(c, 1.0 - float(k) / FACE_H * 0.18)


## Natural earth bank: turf lip with tufts hanging over, mottled soil with pebbles and roots, rock showing
## lower down on tall drops (2+ levels).
static func _earth(b: int, x: int, k: int, sd: int) -> Color:
	var grass: Array = TL.GRASS[b]
	var dirt: Array = TL.DIRT[b]
	var tuft := 2 + int(_pn(x, 0, 4, 1.0, sd + 1) * 3.0) + (1 if P.hn(x, 0, sd + 2) > 0.8 else 0)
	if k == 0:
		return TL.SNOW if b == 2 else P.mul(grass[2], 1.04)
	if k < tuft:
		return P.mul(grass[0] if P.hn(x, k, sd) > 0.45 else grass[1], 0.95)
	var rock_at := 27.0 + (_pn(x, 0, 8, 1.0, sd + 3) - 0.5) * 16.0
	if float(k) > rock_at:
		var r := _rock(TL.ROCK[b], x, k, sd)
		return P.mul(r, 0.8) if float(k) < rock_at + 2.0 else r
	var m := _pn(x, k, 8, 6.0, sd + 4) * 0.65 + _pn(x, k, 4, 3.0, sd + 5) * 0.35
	var c: Color = P.mix(dirt[0], dirt[1], 0.2 + m * 0.8)
	if k <= tuft + 1:
		c = P.mul(c, 0.86)  # shade under the turf
	if P.hn(x, k, sd + 6) > 0.955:
		c = P.mul(dirt[2], 0.95)  # pebble
	elif P.hn(x, k - 1, sd + 6) > 0.955:
		c = P.mul(dirt[0], 0.7)   # its shadow
	elif k < tuft + 6 and absf(_pn(x, k, 4, 5.0, sd + 8) - 0.5) < 0.03:
		c = P.mul(dirt[0], 0.75)  # roots
	return c


## Natural sand bank: soft sediment layers of irregular tone, slumped lighter runnels, a bright crest.
static func _sand(b: int, x: int, k: int, sd: int) -> Color:
	var sand: Array = TL.SAND[b]
	if k <= 1:
		return sand[2]
	var wav := float(k) + (_pn(x, 0, 16, 1.0, sd + 1) - 0.5) * 8.0 + (_pn(x, k, 8, 12.0, sd + 2) - 0.5) * 3.0
	var band := int(floor(wav / 5.0))
	var c: Color = P.mix(sand[0], sand[1], 0.35 + _pn(x, k, 8, 10.0, sd) * 0.5)
	c = P.mul(c, 0.93 + P.hn(band, 0, sd + 3) * 0.1)
	if _pn(x, k, 4, 26.0, sd + 4) > 0.7:
		c = P.mix(c, sand[2], 0.3)
	if P.hn(x, k, sd + 5) > 0.97:
		c = P.mul(c, 0.85)
	return P.mul(c, 1.0 - float(k) / FACE_H * 0.12)


# ---------------------------------------------------------------- ramps
static func ramps() -> Image:
	var img := Image.create(1024, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for b in 4:
		var dark: Color = TL.DIRT[b][0]
		for d in 4:
			var ox := (b * 4 + d) * 64
			for y in 32:
				for x in 64:
					if not P.in_diamond(x, y):
						continue
					var sx := (x + 0.5 - 32.0) / 32.0
					var sy := (y + 0.5) / 16.0
					var u := (sy + sx) * 0.5
					var w := (sy - sx) * 0.5
					var across := w if d % 2 == 1 else u  # E/W rise: the track runs along x
					var along := u if d % 2 == 1 else w
					var a := 0.0
					if minf(absf(across - 0.36), absf(across - 0.64)) < 0.05:
						a = 0.55  # tyre ruts
					elif absf(across - 0.5) < 0.2:
						a = 0.18  # worn path between them
					if fposmod(along * 4.0, 1.0) < 0.07:
						a = maxf(a, 0.24)  # contour steps across the slope
					a *= 0.85 + P.hn(x, y, 77 + d) * 0.3
					if a > 0.0:
						img.set_pixel(ox + x, y, Color(dark.r, dark.g, dark.b, clampf(a, 0.0, 1.0)))
	return img


# ---------------------------------------------------------------- scree / rim (G4 transition layout)
static func trans_atlas(kind: String, b: int) -> Image:
	var img := Image.create(1024, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var k := TR.KINDS.find(kind)
	for row in 2:
		for m in range(1, 16):
			for y in 32:
				for x in 64:
					if not P.in_diamond(x, y):
						continue
					var sx := (x + 0.5 - 32.0) / 32.0
					var sy := (y + 0.5) / 16.0
					var t: float = TR._field(kind, k, (sy + sx) * 0.5, (sy - sx) * 0.5, m, row == 1)
					t += (P.hn(x, y, 1900 + k) - 0.5) * 0.06
					if t >= 1.0:
						continue
					var c := _tpaint(kind, b, t, x, y)
					if c.a > 0.0:
						img.set_pixel(m * 64 + x, row * 32 + y, c)
	return img


static func _tpaint(kind: String, b: int, t: float, x: int, y: int) -> Color:
	if kind == "rim":
		return Color(1, 1, 1, 0.34) if t < 0.45 else Color(1, 1, 1, 0.14)
	var rock: Array = TL.ROCK[b]
	if t < 0.85 and P.hn(x / 2, y / 2, 1950 + b) > 0.8:
		return P.mul(rock[2], 0.9) if y % 2 == 0 else rock[0]
	if t < 0.5:
		return Color(0, 0, 0, 0.36)
	return Color(0, 0, 0, 0.16)


# ---------------------------------------------------------------- rail (code 14)
static func rail_base(b: int) -> Image:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pal: Array = TL.ROCK[b]
	var g: Array = TL.GRASS[b] if b != 3 else TL.DIRT[b]
	for y in 32:
		for x in 64:
			if not P.in_diamond(x, y):
				continue
			var sx := (x + 0.5 - 32.0) / 32.0
			var sy := (y + 0.5) / 16.0
			var u := (sy + sx) * 0.5
			var w := (sy - sx) * 0.5
			var c: Color = P.mix(pal[0], pal[2], P.vnoise(x, y * 2, 3.0, 5100 + b))
			var r := P.hn(x, y, 5200 + b)
			if r > 0.82:
				c = P.mul(c, 1.15)
			elif r < 0.18:
				c = P.mul(c, 0.8)
			var edge := minf(minf(u, 1.0 - u), minf(w, 1.0 - w))
			if edge < 0.1 + P.hn(x, y, 5300) * 0.05:
				c = P.mix(c, g[1], 0.7)  # ground shows at the bed's margin so beds join cell to cell
			img.set_pixel(x, y, c)
	return img


static func rail_tracks() -> Image:
	var img := Image.create(1024, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood := Color8(70, 52, 36)
	var steel := Color8(158, 160, 164)
	var shade := Color8(52, 52, 54)
	for m in 16:
		var mask := m if m != 0 else 5
		var segs: Array = []
		for k in 4:
			if mask & (1 << k):
				segs.append(MIDS[k])
		for pass_i in 2:
			for e in segs:
				var a := Vector2(0.5, 0.5)
				var dir: Vector2 = (e - a).normalized()
				var nrm := Vector2(-dir.y, dir.x)
				var length: float = (e - a).length()
				if pass_i == 0:
					var t := 0.04
					while t < length:
						var c: Vector2 = a + dir * t
						_wline(img, m * 64, c - nrm * 0.2, c + nrm * 0.2, wood)
						t += 0.09
				else:
					for side in [-1.0, 1.0]:
						var o: Vector2 = nrm * 0.1 * side
						_wline(img, m * 64, a + o + Vector2(0, 0.02), e + o + Vector2(0, 0.02), shade)
						_wline(img, m * 64, a + o, e + o, steel)
	return img


## Line between tile-local world points (u, w) in a 64x32 block at x offset ox, clipped to the diamond.
static func _wline(img: Image, ox: int, a: Vector2, b: Vector2, c: Color) -> void:
	var pa := Vector2(32.0 + (a.x - a.y) * 32.0, (a.x + a.y) * 16.0)
	var pb := Vector2(32.0 + (b.x - b.y) * 32.0, (b.x + b.y) * 16.0)
	var n := int(maxf(absf(pb.x - pa.x), absf(pb.y - pa.y))) + 1
	for i in n + 1:
		var p := pa.lerp(pb, float(i) / float(n))
		var x := int(floor(p.x))
		var y := int(floor(p.y))
		if P.in_diamond(x, y):
			img.set_pixel(ox + x, y, c)
