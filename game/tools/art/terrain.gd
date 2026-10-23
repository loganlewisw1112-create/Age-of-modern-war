extends RefCounted
## Terrain tiles (64x32 iso diamonds) and decor (trees, rock outcrops).
const P = preload("res://tools/art/pix.gd")

const NAMES := ["grass", "dirt", "road", "forest", "water", "bridge", "ford", "ridge"]
const VARIANTS := [4, 3, 2, 3, 4, 1, 2, 3]   # water variants are animation frames

const GRASS := Color8(90, 102, 58)
const GRASS_D := Color8(74, 86, 48)
const GRASS_L := Color8(112, 120, 70)
const DIRT := Color8(124, 100, 66)
const DIRT_D := Color8(92, 72, 48)
const DIRT_L := Color8(150, 126, 88)
const ROAD := Color8(100, 96, 86)
const FOREST := Color8(52, 64, 40)
const LITTER := Color8(86, 74, 48)
const WATER := Color8(56, 76, 96)
const WATER_D := Color8(42, 60, 80)
const FOAM := Color8(156, 174, 184)
const FORD := Color8(84, 104, 106)
const STONE := Color8(124, 120, 108)
const ROCK := Color8(104, 100, 92)
const ROCK_D := Color8(74, 70, 64)
const ROCK_L := Color8(140, 134, 122)
const PLANK := Color8(112, 88, 62)
const STEEL := Color8(72, 76, 78)
const RUST := Color8(122, 74, 46)


static func build(out: Dictionary) -> void:
	var man := {}
	for code in NAMES.size():
		man[str(code)] = {"name": NAMES[code], "variants": VARIANTS[code]}
		for v in VARIANTS[code]:
			out.images["terrain/%s_%d.png" % [NAMES[code], v]] = tile(code, v)
	out.manifest["terrain"] = man
	var dec := {"tree": [], "rock": []}
	for i in 5:
		var t: Dictionary = tree(i)
		out.images["decor/tree_%d.png" % i] = t.img
		dec.tree.append({"file": "decor/tree_%d.png" % i, "pivot": t.pivot})
	for i in 3:
		var r: Dictionary = rock(i)
		out.images["decor/rock_%d.png" % i] = r.img
		dec.rock.append({"file": "decor/rock_%d.png" % i, "pivot": r.pivot})
	out.manifest["decor"] = dec


static func tile(code: int, v: int) -> Image:
	var cv = P.Canvas.new(64, 32)
	var s := code * 101 + v * 7 + 3
	for y in 32:
		for x in 64:
			if P.in_diamond(x, y):
				cv.px(x, y, _col(code, v, x, y, s))
	if code == 6:  # ford stones
		for i in 7:
			var sx := 10 + P.hi(i, v, 61, 44)
			var sy := 8 + P.hi(i, v, 62, 16)
			if P.in_diamond(sx, sy) and P.in_diamond(sx + 4, sy) and P.in_diamond(sx - 4, sy):
				cv.ellipse(sx + 0.5, sy + 1.5, 3.5, 2.0, P.mix(FORD, FOAM, 0.55))
				cv.ellipse(sx, sy, 2.6, 1.6, STONE)
				cv.px(sx - 1, sy - 1, P.mul(STONE, 1.25))
	if code == 7:  # ridge cracks
		for i in 3:
			var x0 := 14 + P.hi(i, v, 71, 36)
			var y0 := 8 + P.hi(i, v, 72, 14)
			var x1 := x0 + 4 + P.hi(i, v, 73, 8)
			var y1 := y0 + 2 + P.hi(i, v, 74, 4)
			if P.in_diamond(x0, y0) and P.in_diamond(x1, y1):
				cv.line(x0, y0, x1, y1, ROCK_D)
				cv.line(x0, y0 - 1, x1, y1 - 1, P.mul(ROCK_L, 0.95))
	return cv.img


static func _col(code: int, v: int, x: int, y: int, s: int) -> Color:
	var n := P.vnoise(x + v * 97, y * 2 + v * 31, 7.0, s)
	var r := P.hn(x, y, s)
	match code:
		0:  # grass: moss/olive with tufts
			var c := P.mix(GRASS_D, GRASS, n * 1.6) if n < 0.6 else P.mix(GRASS, GRASS_L, (n - 0.6) * 2.0)
			if v == 3:
				c = P.mix(c, Color8(128, 118, 74), 0.25 * P.vnoise(x, y * 2, 12.0, s + 5))
			if r > 0.95:
				c = P.mul(c, 0.78)
			elif r > 0.92:
				c = P.mul(c, 1.14)
			return c
		1:  # dirt: ochre/umber with pebbles
			var c := P.mix(DIRT_D, DIRT, n * 1.4) if n < 0.7 else P.mix(DIRT, DIRT_L, (n - 0.7) * 3.0)
			if r > 0.975:
				return P.mul(DIRT_L, 1.1)
			if r < 0.03:
				return DIRT_D
			return P.mul(c, 1.0 + (r - 0.5) * 0.08)
		2:  # road: packed gravel with two worn ruts running screen-vertical
			var c := P.mul(ROAD, 0.92 + n * 0.16 + (r - 0.5) * 0.12)
			if absi(x - 21) <= 1 or absi(x - 43) <= 1:
				c = P.mul(c, 0.86)
			if r > 0.985:
				c = P.mul(c, 1.25)
			return c
		3:  # forest floor: dark moss with needle litter
			var c := P.mul(FOREST, 0.85 + n * 0.3)
			if r > 0.9:
				c = P.mix(c, LITTER, 0.6)
			return c
		4:  # water: lattice-periodic waves (tiles seamlessly), v = animation frame
			return _water(x, y, v, WATER, WATER_D, 0.0)
		5:  # bridge: planks across the deck, steel girders at the side corners
			if absi(x - 32) >= 27:
				var g := P.mix(STEEL, RUST, P.hn(x / 2, y, s) * 0.6)
				return P.mul(g, 0.8 if y % 4 == 0 else 1.0)
			var board := int(floor(y / 3.0))
			var c := P.mul(PLANK, 0.85 + P.hn(board, (x + board * 13) / 22, s) * 0.3)
			if y % 3 == 2:
				c = P.mul(c, 0.55)
			elif r > 0.97:
				c = P.mul(c, 0.75)
			return c
		6:  # ford: shallow, lighter water over gravel
			var c := _water(x, y, 0, FORD, P.mix(FORD, DIRT_D, 0.35), 0.15)
			return P.mix(c, DIRT, 0.12 * n)
		7:  # ridge rock
			var c := P.mix(ROCK_D, ROCK, n * 1.5) if n < 0.66 else P.mix(ROCK, ROCK_L, (n - 0.66) * 3.0)
			return P.mul(c, 1.0 + (r - 0.5) * 0.12)
	return Color.MAGENTA


static func _water(x: int, y: int, f: int, base: Color, deep: Color, bias: float) -> Color:
	var g1 := x / 32.0 + y / 16.0
	var g2 := y / 16.0 - x / 32.0
	var ph := f * TAU / 4.0
	var w := sin(PI * 3.0 * g1 + ph) * 0.6 + sin(PI * 5.0 * g2 - ph) * 0.4
	var c := P.mix(deep, base, 0.5 + 0.5 * sin(PI * 2.0 * g2 + ph * 0.5))
	if w > 0.82 - bias:
		c = P.mix(c, FOAM, 0.55)
	elif w > 0.62 - bias:
		c = P.mix(c, FOAM, 0.18)
	return c


# ---------------------------------------------------------------- trees
static func tree(i: int) -> Dictionary:
	var cv = P.Canvas.new(34, 50)
	var bx := 17
	var by := 45
	cv.ellipse(bx + 6, by - 1, 12, 4.5, Color.BLACK, true)
	cv.flush_shadow()
	if i <= 2:  # conifers of different heights
		var hgt := 34 + i * 4
		cv.rect(bx - 1, by - 6, 2, 6, Color8(70, 52, 38))
		var tiers := 4
		for t in tiers:
			var ty1 := by - 4 - t * (hgt - 6) / tiers
			var ty0 := ty1 - (hgt - 6) / tiers - 6
			var hw := 11.0 - t * 2.2 + (1 if i == 2 else 0)
			var base := Color8(44, 62, 40) if i != 1 else Color8(50, 66, 42)
			cv.poly(PackedVector2Array([Vector2(bx, ty0), Vector2(bx + hw, ty1), Vector2(bx - hw, ty1)]), base,
				func(x: int, y: int, c: Color) -> Color:
					var k := 1.15 - float(x - bx + hw) / (2.0 * hw) * 0.45
					k *= 0.85 + 0.15 * float(y - ty0) / maxf(1.0, ty1 - ty0)
					if (y - ty0) >= (ty1 - ty0) - 2:
						k *= 0.72
					return P.mul(c, k * (0.92 + P.hn(x, y, 400 + i) * 0.16)))
	else:  # deciduous clusters / dead snag
		cv.rect(bx - 1, by - 14, 3, 14, Color8(66, 52, 40))
		if i == 4:
			cv.line(bx, by - 14, bx - 6, by - 24, Color8(84, 76, 66))
			cv.line(bx + 1, by - 12, bx + 7, by - 22, Color8(84, 76, 66))
			cv.line(bx, by - 18, bx + 1, by - 30, Color8(84, 76, 66))
		var base: Color = Color8(72, 86, 46) if i == 3 else Color8(98, 92, 52)
		var n := 6 if i == 3 else 4
		var cy := by - 24 if i == 3 else by - 26
		for b in n:
			var ox := -8.0 + P.hn(b, i, 501) * 16.0
			var oy := -8.0 + P.hn(b, i, 502) * 12.0
			var rr := 6.0 + P.hn(b, i, 503) * 3.0
			if i == 4:
				rr *= 0.6
			var ccx := bx + ox
			var ccy := cy + oy
			for y in range(int(ccy - rr), int(ccy + rr) + 1):
				for x in range(int(ccx - rr), int(ccx + rr) + 1):
					var dx := (x + 0.5 - ccx) / rr
					var dy := (y + 0.5 - ccy) / (rr * 0.9)
					if dx * dx + dy * dy <= 1.0:
						var k := 1.0 - (dx + dy) * 0.22 + (P.hn(x, y, 510 + i) - 0.5) * 0.22
						cv.px(x, y, P.mul(base, k))
	cv.outline(Color(0.09, 0.11, 0.07, 1))
	return {"img": cv.img, "pivot": [bx, by]}


static func rock(i: int) -> Dictionary:
	var cv = P.Canvas.new(52, 40)
	var o := Vector2(26, 23)
	var parts: Array = []
	for k in 3 - (i % 2):
		var cx := -0.25 + P.hn(k, i, 601) * 0.5
		var cy := -0.25 + P.hn(k, i, 602) * 0.5
		var hz := 6.0 + P.hn(k, i, 603) * 10.0
		parts.append([Vector3(cx, cy, 0), 0.16 + P.hn(k, i, 604) * 0.14, 0.14 + P.hn(k, i, 605) * 0.12, hz,
			P.hn(k, i, 606) * 1.5])
	parts.sort_custom(func(a, b): return a[0].x + a[0].y < b[0].x + b[0].y)
	for p in parts:
		P.box_shadow(cv, o, p[0], p[1], p[2], p[3], p[4])
	cv.flush_shadow()
	for p in parts:
		P.box(cv, o, p[0], p[1], p[2], p[3], p[4], ROCK, 0.14, 610 + i, ROCK_L)
	cv.outline(Color(0.13, 0.12, 0.11, 1))
	return {"img": cv.img, "pivot": [26, 23]}
