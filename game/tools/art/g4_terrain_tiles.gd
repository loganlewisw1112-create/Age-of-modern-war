extends RefCounted
## G4 terrain tiles (ART-T, CONTRACTS_G4 s2.2): codes 8-13 and the desert / snow / wasteland biome
## looks. 64x32 iso diamonds in the style of tools/art/terrain.gd. Raised codes (CLIFF, HILL) are
## taller: the top face sits in rows 0-31 and the side faces hang RAISE px below it; the renderer
## lifts the tile by RAISE so the faces end on the cell's ground diamond.
## Water codes only use lattice-periodic patterns (functions of g1/g2 with integer frequencies) so
## neighbouring cells tile seamlessly; their variants are animation phases.
const P = preload("res://tools/art/pix.gd")
const T = preload("res://tools/art/terrain.gd")

const RAISE := {12: 16, 13: 6}
const ANIM := {9: 4, 10: 4}
const NEW_NAMES := {8: "building", 9: "shallow", 10: "deep", 11: "beach", 12: "cliff", 13: "hill"}
const NEW_VARIANTS := {8: 2, 9: 4, 10: 4, 11: 3, 12: 2, 13: 2}
## Codes with desert/snow/wasteland looks (files <name>_b<biome>_<v>.png), variants per biome.
const BIOME_VARIANTS := {0: 3, 1: 2, 2: 2, 3: 2, 7: 2, 8: 2, 9: 4, 10: 4, 11: 2, 12: 2, 13: 2}
const BIOMES := ["temperate", "desert", "snow", "wasteland"]
const SNOW := Color8(214, 220, 226)

## [dark, base, light] per biome: temperate, desert, snow, wasteland.
const GRASS := [[Color8(74, 86, 48), Color8(90, 102, 58), Color8(112, 120, 70)],
	[Color8(130, 110, 66), Color8(154, 134, 82), Color8(178, 158, 102)],
	[Color8(178, 186, 196), Color8(204, 210, 218), Color8(228, 232, 236)],
	[Color8(82, 78, 60), Color8(100, 94, 70), Color8(122, 114, 84)]]
const DIRT := [[Color8(92, 72, 48), Color8(124, 100, 66), Color8(150, 126, 88)],
	[Color8(150, 118, 78), Color8(178, 146, 100), Color8(202, 172, 124)],
	[Color8(110, 102, 94), Color8(134, 126, 116), Color8(160, 154, 146)],
	[Color8(70, 64, 58), Color8(92, 86, 78), Color8(116, 108, 98)]]
const ROAD := [Color8(100, 96, 86), Color8(146, 130, 106), Color8(128, 130, 136), Color8(78, 76, 74)]
const FOREST := [[Color8(52, 64, 40), Color8(86, 74, 48)], [Color8(120, 104, 68), Color8(90, 74, 48)],
	[Color8(172, 180, 190), Color8(84, 92, 80)], [Color8(58, 54, 46), Color8(34, 32, 30)]]
const ROCK := [[Color8(74, 70, 64), Color8(104, 100, 92), Color8(140, 134, 122)],
	[Color8(124, 88, 60), Color8(156, 118, 82), Color8(186, 150, 108)],
	[Color8(84, 88, 96), Color8(112, 116, 124), Color8(150, 154, 162)],
	[Color8(52, 50, 50), Color8(70, 68, 66), Color8(96, 92, 88)]]
const SAND := [[Color8(150, 132, 94), Color8(178, 160, 116), Color8(200, 184, 142)],
	[Color8(186, 158, 104), Color8(210, 182, 124), Color8(230, 206, 150)],
	[Color8(118, 116, 112), Color8(142, 140, 134), Color8(166, 164, 158)],
	[Color8(88, 82, 70), Color8(110, 102, 86), Color8(132, 124, 106)]]
const CONCRETE := [[Color8(98, 98, 94), Color8(128, 126, 120), Color8(150, 148, 140)],
	[Color8(132, 120, 100), Color8(162, 150, 128), Color8(184, 172, 150)],
	[Color8(112, 116, 122), Color8(150, 154, 160), Color8(206, 210, 216)],
	[Color8(70, 68, 64), Color8(98, 96, 90), Color8(118, 114, 106)]]
## Water [deep, base, light].
const SHALLOW := [[Color8(64, 92, 104), Color8(84, 116, 120), Color8(150, 170, 160)],
	[Color8(52, 108, 116), Color8(80, 144, 140), Color8(170, 200, 180)],
	[Color8(84, 108, 124), Color8(112, 138, 152), Color8(196, 212, 222)],
	[Color8(66, 76, 60), Color8(90, 100, 74), Color8(130, 128, 96)]]
const DEEP := [[Color8(22, 36, 54), Color8(36, 54, 74), Color8(92, 118, 138)],
	[Color8(18, 44, 64), Color8(30, 64, 86), Color8(96, 140, 156)],
	[Color8(28, 40, 56), Color8(44, 60, 80), Color8(130, 150, 170)],
	[Color8(28, 34, 30), Color8(42, 50, 42), Color8(96, 100, 80)]]


static func file_for(code: int, b: int, v: int) -> String:
	var name: String = T.NAMES[code] if code < T.NAMES.size() else String(NEW_NAMES[code])
	return "terrain/%s_%d.png" % [name, v] if b == 0 else "terrain/%s_b%d_%d.png" % [name, b, v]


static func tile(code: int, b: int, v: int) -> Image:
	var r: int = RAISE.get(code, 0)
	var cv = P.Canvas.new(64, 32 + r)
	var s := code * 101 + v * 7 + 3 + b * 1009
	for y in 32:
		for x in 64:
			if P.in_diamond(x, y):
				var sx := (x + 0.5 - 32.0) / 32.0
				var sy := (y + 0.5) / 16.0
				cv.px(x, y, _col(code, b, v, x, y, s, (sy + sx) * 0.5, (sy - sx) * 0.5))
	if code == 7 or code == 12:
		_cracks(cv, v, s, ROCK[b][0], ROCK[b][2])
	if r > 0:
		_faces(cv, code, b, r, s)
	return cv.img


static func _ground(pal: Array, x: int, y: int, v: int, s: int) -> Color:
	var n := P.vnoise(x + v * 97, y * 2 + v * 31, 7.0, s)
	var r := P.hn(x, y, s)
	var c: Color = P.mix(pal[0], pal[1], n * 1.6) if n < 0.6 else P.mix(pal[1], pal[2], (n - 0.6) * 2.0)
	if r > 0.95:
		c = P.mul(c, 0.8)
	elif r > 0.92:
		c = P.mul(c, 1.12)
	return c


static func _col(code: int, b: int, v: int, x: int, y: int, s: int, u: float, w: float) -> Color:
	var n := P.vnoise(x + v * 97, y * 2 + v * 31, 7.0, s)
	var r := P.hn(x, y, s)
	match code:
		0, 13:  # grass (hill top: same sward, lit from the north-west crest)
			var c := _ground(GRASS[b], x, y, v, s)
			if b == 2 and P.hn(x, y, s + 3) > 0.985:
				c = Color8(96, 106, 70)  # grass tips through the snow
			elif b == 3 and r < 0.02:
				c = Color8(60, 56, 50)
			if code == 13:
				c = P.mul(c, 1.07 + 0.12 * (0.5 - (u + w) * 0.5))
			return c
		1:
			if r > 0.975:
				return P.mul(DIRT[b][2], 1.1)
			if r < 0.03:
				return DIRT[b][0]
			var c := _ground(DIRT[b], x, y, v, s)
			if b == 2 and P.vnoise(x, y * 2, 6.0, s + 9) > 0.64:
				c = P.mix(c, SNOW, 0.75)
			return c
		2:  # road with two ruts (as terrain.gd); snow piles between ruts, wasteland potholes
			var rut := absi(x - 21) <= 1 or absi(x - 43) <= 1
			var c := P.mul(ROAD[b], 0.92 + n * 0.16 + (r - 0.5) * 0.12)
			if rut:
				c = P.mul(c, 0.86)
			elif b == 2 and P.vnoise(x, y * 2, 5.0, s + 4) > 0.5:
				c = P.mix(c, SNOW, 0.6)
			if b == 3 and P.vnoise(x, y * 2, 4.0, s + 8) > 0.74:
				c = P.mul(c, 0.7)
			if r > 0.985:
				c = P.mul(c, 1.25)
			return c
		3:
			var c := P.mul(FOREST[b][0], 0.85 + n * 0.3)
			if r > 0.9:
				c = P.mix(c, FOREST[b][1], 0.6)
			return c
		7, 12:  # rock (ridge / cliff top)
			var pal: Array = ROCK[b]
			var c: Color = P.mix(pal[0], pal[1], n * 1.5) if n < 0.66 else P.mix(pal[1], pal[2], (n - 0.66) * 3.0)
			c = P.mul(c, 1.0 + (r - 0.5) * 0.12)
			var m := P.vnoise(x, y * 2, 6.0, s + 21)
			if b == 2:  # snow lies on the rock; cracks and steep bits show through
				c = P.mix(c, SNOW, clampf((m - (0.3 if code == 12 else 0.42)) * 4.0, 0.0, 0.88))
			elif b == 0 and code == 12 and m > 0.66:
				c = P.mix(c, GRASS[0][0], 0.55)  # moss on the cliff top
			return c
		8:
			return _concrete(b, v, x, y, s, u, w)
		9:
			return _shallow(x, y, v, b)
		10:
			return _deep(x, y, v, b)
		11:  # beach: sand, pebbles, shells (wasteland: rusty debris)
			var c := _ground(SAND[b], x, y, v, s)
			if r > 0.975:
				c = SAND[b][0]
			elif r < 0.012:
				c = Color8(110, 70, 44) if b == 3 else Color8(230, 226, 214)
			return c
	return Color.MAGENTA


static func _concrete(b: int, v: int, x: int, y: int, s: int, u: float, w: float) -> Color:
	var pal: Array = CONCRETE[b]
	var n := P.vnoise(x + v * 53, y * 2, 9.0, s)
	var r := P.hn(x, y, s)
	var c: Color = P.mul(pal[1], 0.94 + n * 0.12 + (r - 0.5) * 0.06)
	var pu := fposmod(u * 4.0, 1.0)
	var pv := fposmod(w * 4.0, 1.0)
	if pu < 0.06 or pv < 0.06:
		c = pal[0]  # expansion joints, continuous across neighbouring slabs
	elif pu < 0.12 or pv < 0.12:
		c = P.mul(c, 1.06)
	if P.vnoise(x, y * 2, 5.0, s + 77) > 0.72:
		c = P.mul(c, 0.87)  # stains
	if v == 1 and absf(u - 0.5) < 0.035 and fposmod(w * 6.0, 1.0) < 0.5:
		c = P.mix(c, Color8(176, 154, 72), 0.55 if b != 3 else 0.25)  # faded lane paint
	match b:
		1:
			if P.vnoise(x, y * 2, 6.0, s + 5) > 0.66:
				c = P.mix(c, SAND[1][1], 0.7)
		2:
			c = P.mix(c, SNOW, clampf((P.vnoise(x, y * 2, 6.0, s + 5) - 0.5) * 4.0, 0.0, 0.85))
		3:
			if r > 0.965:
				c = Color8(58, 56, 52)
	return c


static func _gg(x: int, y: int) -> Vector2:
	return Vector2(x / 32.0 + y / 16.0, y / 16.0 - x / 32.0)


static func _shallow(x: int, y: int, f: int, b: int) -> Color:
	var g := _gg(x, y)
	var ph := f * TAU / 4.0
	var pal: Array = SHALLOW[b]
	var bottom := 0.5 + 0.25 * sin(PI * 2.0 * g.x) * sin(PI * 3.0 * g.y) + 0.25 * sin(PI * 4.0 * g.y + 1.0)
	var c: Color = P.mix(pal[0], pal[1], bottom)
	if b == 2 and bottom > 0.84:
		return P.mix(pal[2], SNOW, 0.5)  # thin ice
	var wv := sin(PI * 4.0 * g.x + ph) * 0.55 + sin(PI * 6.0 * g.y - ph) * 0.45
	if wv > 0.86:
		c = P.mix(c, pal[2], 0.5)
	elif wv > 0.68:
		c = P.mix(c, pal[2], 0.18)
	return c


static func _deep(x: int, y: int, f: int, b: int) -> Color:
	var g := _gg(x, y)
	var ph := f * TAU / 4.0
	var pal: Array = DEEP[b]
	var c: Color = P.mix(pal[0], pal[1], 0.5 + 0.3 * sin(PI * 2.0 * g.y + ph) + 0.2 * sin(PI * g.x))
	var sw := sin(PI * 3.0 * g.x + ph) * sin(PI * 5.0 * g.y - ph)
	if sw > 0.9:
		c = P.mix(c, pal[2], 0.55)  # shimmer glints (move with the phase)
	elif sw > 0.74:
		c = P.mix(c, pal[2], 0.16)
	return c


static func _cracks(cv, v: int, s: int, dark: Color, light: Color) -> void:
	for i in 3:
		var x0 := 14 + P.hi(i, v, 71 + s, 36)
		var y0 := 8 + P.hi(i, v, 72 + s, 14)
		var x1 := x0 + 4 + P.hi(i, v, 73 + s, 8)
		var y1 := y0 + 2 + P.hi(i, v, 74 + s, 4)
		if P.in_diamond(x0, y0) and P.in_diamond(x1, y1):
			cv.line(x0, y0, x1, y1, dark)
			cv.line(x0, y0 - 1, x1, y1 - 1, P.mul(light, 0.95))


## Side faces of a raised tile: column x hangs r px below the bottom edge of the top diamond.
static func _faces(cv, code: int, b: int, r: int, s: int) -> void:
	for x in 64:
		var bot := -1
		for y in 32:
			if P.in_diamond(x, y):
				bot = y
		if bot < 0:
			continue
		for k in range(1, r + 1):
			cv.px(x, bot + k, _face(code, b, x, k, r, x < 32, s))


static func _face(code: int, b: int, x: int, k: int, r: int, left: bool, s: int) -> Color:
	var j := 0.94 + P.hn(x, k, s + 13) * 0.12
	if code == 12:  # cliff: strata, vertical cracks, lit lip, dark foot
		var pal: Array = ROCK[b]
		var c: Color = P.mul(pal[1], 0.86) if left else P.mul(pal[0], 0.9)
		if (k + P.hi(x / 6, 0, s + 5, 3)) % 5 == 0:
			c = P.mul(c, 0.8)
		if P.hn(x, 1, s + 9) > 0.9 and k > 2 and k < r:
			c = P.mul(c, 0.72)
		if b == 2 and P.hn(x / 2, k / 3, s + 2) > 0.78:
			c = P.mix(c, SNOW, 0.5)
		if k == 1:
			c = SNOW if b == 2 else P.mul(pal[2], 0.95 if left else 0.8)
		elif k == r:
			c = P.mul(c, 0.68)
		return P.mul(c, j)
	var c2: Color = P.mul(GRASS[b][0], 0.92 if left else 0.76) if k <= 2 else P.mul(DIRT[b][1], 0.84 if left else 0.66)
	if k == r:
		c2 = P.mul(c2, 0.8)
	return P.mul(c2, j)
