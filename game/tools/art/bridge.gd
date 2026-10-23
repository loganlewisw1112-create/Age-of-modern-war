extends RefCounted
## Bridge-span overlays (agent E2), one sprite per bridge cell, drawn over the terrain bake.
## States: intact (railings), damaged (broken planks, holes, scorch, bent railing), ruined (collapsed
## girders and deck slabs sticking out of the water; the cells are WATER terrain by then).
## Side: "l" / "c" / "r" from sign(cell.x - cell.y) (the River Crossing bridge is the |x - y| <= 1
## road band, so the outer cells carry the railings). 3 deterministic variants per (state, side).
## Anchor: the CELL CENTRE, world_to_screen(cell + (0.5, 0.5)), like ArtCatalog.decor; pivot (32, 40).
const P = preload("res://tools/art/pix.gd")
const TER = preload("res://tools/art/terrain.gd")

const W := 64
const H := 56
const PIV := Vector2i(32, 40)
const STATES := ["intact", "damaged", "ruined"]
const SIDES := {"l": -1, "c": 0, "r": 1}
const VARIANTS := 3
const STEEL := Color8(96, 100, 100)
const RUST := Color8(122, 78, 50)
const HOLE := Color8(26, 44, 54)
const FOAM := Color8(176, 196, 200)


static func build(out: Dictionary) -> void:
	var man := {"pivot": [PIV.x, PIV.y], "variants": VARIANTS, "anchor": "cell_centre", "states": {}}
	for st in STATES:
		man.states[st] = {}
		for side in SIDES:
			var files: Array = []
			for v in VARIANTS:
				var cv = P.Canvas.new(W, H)
				draw(cv, st, int(SIDES[side]), v)
				var rel := "bridge/%s_%s_%d.png" % [st, side, v]
				out.images[rel] = cv.img
				files.append(rel)
			man.states[st][side] = files
	out.manifest["bridge"] = man


## Local world offset (u, v) in tiles from the cell centre of overlay pixel (x, y).
static func _uv(x: int, y: int) -> Vector2:
	var sx := (x + 0.5 - PIV.x) / 32.0
	var sy := (y + 0.5 - PIV.y) / 16.0
	return Vector2((sx + sy) * 0.5, (sy - sx) * 0.5)


static func _own(x: int, y: int) -> bool:
	var uv := _uv(x, y)
	return absf(uv.x) <= 0.5 and absf(uv.y) <= 0.5


static func _plank(x: int, y: int, s: int) -> Color:
	var board := int(floor(y / 3.0))
	var c := P.mul(TER.PLANK, 0.85 + P.hn(board, (x + board * 13) / 22, s) * 0.3)
	return P.mul(c, 0.55) if y % 3 == 2 else c


static func draw(cv, st: String, sgn: int, v: int) -> void:
	var s := 900 + v * 17 + (sgn + 1) * 5
	var rx := PIV.x + 16 * sgn
	if st != "ruined" and sgn != 0:
		# square off the deck edge up to the railing line (fills the neighbour cells' corner triangles)
		for y in range(PIV.y - 16, PIV.y + 16):
			for x in range(mini(PIV.x, rx), maxi(PIV.x, rx) + 1):
				if not _own(x, y):
					cv.px(x, y, _plank(x, y, s))
	if st == "intact":
		if sgn != 0:
			_railing(cv, rx, sgn, -1, s)
		else:
			for x in [PIV.x - 9, PIV.x + 8]:  # worn tyre tracks
				for y in range(PIV.y - 14, PIV.y + 14):
					if _own(x, y):
						cv.px(x, y, Color(0, 0, 0, 0.12))
	elif st == "damaged":
		_damage(cv, s)
		if sgn != 0:
			_railing(cv, rx, sgn, P.hi(v, sgn, s, 3), s)
	else:
		_ruin(cv, sgn, v, s)
	cv.outline(Color(0.09, 0.09, 0.08, 1))


## Railing: a 3-px steel girder strip along the screen-vertical bridge axis with posts and rivets.
## `gap` >= 0 knocks out one segment (0..2) and leaves a bent stub.
static func _railing(cv, rx: int, sgn: int, gap: int, s: int) -> void:
	for y in range(PIV.y - 22, PIV.y + 10):
		var seg := int((y - (PIV.y - 22)) / 11)
		if seg == gap:
			continue
		var g := P.mix(STEEL, RUST, P.hn(rx, y / 3, s) * 0.5)
		cv.px(rx - 1, y, P.mul(g, 1.25))
		cv.px(rx, y, g)
		cv.px(rx + 1, y, P.mul(g, 0.7))
		if y % 8 == 0:  # posts
			cv.px(rx, y, P.mul(g, 1.5))
			cv.px(rx - 1 * sgn, y + 1, P.mul(g, 0.6))
	if gap >= 0:
		var y0 := PIV.y - 22 + gap * 11
		cv.line(rx, y0, rx + 4 * sgn, y0 + 5, P.mix(STEEL, RUST, 0.6))
		cv.line(rx, y0 + 10, rx + 3 * sgn, y0 + 7, P.mix(STEEL, RUST, 0.7))


## Broken planks (holes showing dark water with splintered ends) and scorch marks on the own deck.
static func _damage(cv, s: int) -> void:
	for k in 2:
		var c := Vector2(PIV.x + (P.hn(k, 1, s) - 0.5) * 30.0, PIV.y + (P.hn(k, 2, s) - 0.5) * 12.0)
		var r := 4.0 + P.hn(k, 3, s) * 4.0
		for y in range(int(c.y - r), int(c.y + r) + 1):
			for x in range(int(c.x - r * 1.8), int(c.x + r * 1.8) + 1):
				if not _own(x, y):
					continue
				var d := Vector2((x - c.x) / (r * 1.8), (y - c.y) / r).length() + (P.vnoise(x, y, 2.0, s + k) - 0.5) * 0.6
				if k == 0 and d < 0.62:
					cv.px(x, y, HOLE if d < 0.5 else P.mul(TER.PLANK, 1.25))  # hole + splintered rim
				elif d < 1.0:
					cv.px(x, y, Color(0.05, 0.04, 0.03, 0.5 * (1.0 - d) + 0.15))  # scorch
	for i in 5:  # loose debris
		var p := Vector2i(PIV.x + int((P.hn(i, 7, s) - 0.5) * 40), PIV.y + int((P.hn(i, 8, s) - 0.5) * 20))
		if _own(p.x, p.y):
			cv.rect(p.x, p.y, 2, 1, P.mul(TER.PLANK, 0.7))


## Collapsed span: tilted deck slab and girders sticking out of the water, with foam at the waterline.
static func _ruin(cv, sgn: int, v: int, s: int) -> void:
	var base := Vector2(PIV.x + sgn * 12 + (P.hn(v, 1, s) - 0.5) * 10, PIV.y + (P.hn(v, 2, s) - 0.5) * 8)
	if sgn == 0 or v != 1:
		# tilted deck slab, half under water
		var a := (P.hn(v, 3, s) - 0.5) * 0.9
		var pts := PackedVector2Array()
		for q in [Vector2(-11, -2), Vector2(9, -7), Vector2(11, 3), Vector2(-9, 6)]:
			pts.append(base + Vector2(q.x * cos(a) - q.y * sin(a), q.x * sin(a) + q.y * cos(a)) + Vector2(0, -3))
		cv.poly(pts, TER.PLANK, func(x: int, y: int, _c: Color) -> Color: return _plank(x, y, s))
		cv.line_v(pts[3], pts[2], P.mul(TER.PLANK, 0.5))
		cv.line_v(pts[0], pts[1], P.mul(TER.PLANK, 1.25))
	for g in (2 if sgn != 0 else 1):  # girders: bent steel sticking up at an angle
		var gb := base + Vector2((g - 0.5) * 14.0 * absf(sgn), 4 + g * 2)
		var ang := -PI / 2 + (P.hn(v, 10 + g, s) - 0.5) * 1.6
		var ln := 12.0 + P.hn(v, 20 + g, s) * 12.0
		var tip := gb + Vector2(cos(ang), sin(ang)) * ln
		var col := P.mix(STEEL, RUST, 0.35 + P.hn(v, 30 + g, s) * 0.5)
		cv.line_v(gb, tip, col)
		cv.line_v(gb + Vector2(1, 0), tip + Vector2(1, 0), P.mul(col, 0.65))
		cv.line_v(gb + Vector2(-1, 0), tip + Vector2(-1, 0), P.mul(col, 1.3))
		var bend := tip + Vector2(3 * (1 if g == 0 else -1), 3)
		cv.line_v(tip, bend, P.mul(col, 0.9))
		for t in [0.3, 0.6]:  # rivets
			var rp := gb.lerp(tip, t)
			cv.px(int(rp.x), int(rp.y), P.mul(col, 1.6))
		for f in 5:  # foam ring at the waterline
			var fp := gb + Vector2(-4 + f * 2, 1 + (f % 2))
			cv.px(int(fp.x), int(fp.y), Color(FOAM.r, FOAM.g, FOAM.b, 0.55))
