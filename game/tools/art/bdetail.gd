extends RefCounted
## Building detail helpers (agent E2 detail pass): framed windows (some lit), doors, roll-up gates,
## rooftop clutter (HVAC, vents, pipes), cylinders (tanks, drums, columns), cables, lamps, plume,
## wall-base AO. Deterministic: integer hashes only.
const P = preload("res://tools/art/pix.gd")

const GLASS := Color8(36, 42, 46)
const GLASS_HI := Color8(96, 116, 124)
const LIT := Color8(222, 190, 112)
const LIT_HI := Color8(250, 228, 160)
const STEEL := Color8(92, 96, 98)
const STEEL_L := Color8(150, 154, 152)
const DARK := Color8(28, 30, 28)
const LAMP := Color8(255, 236, 170)


## Darken the bottom strip of every visible side (ambient occlusion at the wall base).
static func wall_ao(cv, r: Dictionary, a := 0.34) -> void:
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		cv.poly(P.sub(q, 0.0, 0.0, 1.0, 0.07), Color(0, 0, 0, a))
		cv.poly(P.sub(q, 0.0, 0.07, 1.0, 0.16), Color(0, 0, 0, a * 0.45))


## Light rim along the top edges of the visible sides, plus the lit parapet corner.
static func edges(cv, r: Dictionary, col: Color) -> void:
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		cv.line_v(q[3], q[2], P.mul(col, 1.32))
	var t: PackedVector2Array = r.top
	cv.line_v(t[3], t[0], P.mul(col, 1.18))
	cv.line_v(t[0], t[1], P.mul(col, 1.1))


## One row of framed windows across a side quad (v0..v1). About 1 in 4 is lit (deterministic).
static func window_row(cv, q: PackedVector2Array, v0: float, v1: float, n: int, col: Color, s: int, lit_p := 0.25) -> void:
	for i in n:
		var u0 := 0.08 + i * 0.84 / n
		var u1 := u0 + 0.84 / n * 0.62
		var fq := P.sub(q, u0 - 0.012, v0 - 0.04, u1 + 0.012, v1 + 0.03)
		cv.poly(fq, P.mul(col, 1.2))                                   # frame
		var g := P.sub(q, u0, v0, u1, v1)
		var lit := P.hn(i, s, 211) < lit_p
		cv.poly(g, LIT if lit else GLASS)
		cv.line_v(g[3], g[2], LIT_HI if lit else GLASS_HI)             # glint on the top edge
		var m0: Vector2 = g[0].lerp(g[1], 0.5)
		cv.line_v(m0, g[3].lerp(g[2], 0.5), P.mul(col, 0.95))          # mullion
		cv.line_v(fq[0] + Vector2(0, 1), fq[1] + Vector2(0, 1), P.mul(col, 0.6))  # sill shadow


## A personnel door at the bottom of a side quad, with frame and a step.
static func door(cv, q: PackedVector2Array, u0: float, u1: float, v1: float, col: Color) -> void:
	cv.poly(P.sub(q, u0 - 0.02, 0.0, u1 + 0.02, v1 + 0.05), P.mul(col, 1.22))
	var d := P.sub(q, u0, 0.0, u1, v1)
	cv.poly(d, Color8(52, 54, 48))
	cv.line_v(d[0].lerp(d[1], 0.5), d[3].lerp(d[2], 0.5), Color8(36, 38, 34))
	var k: Vector2 = d[0].lerp(d[1], 0.8).lerp(d[3].lerp(d[2], 0.8), 0.45)
	cv.px(int(k.x), int(k.y), Color8(170, 160, 120))
	cv.line_v(q[0].lerp(q[1], u0 - 0.04) + Vector2(0, 1), q[0].lerp(q[1], u1 + 0.04) + Vector2(0, 1), Color8(150, 146, 136))


## Roll-up gate: slatted steel shutter, `open` = fraction raised (dark interior below).
static func rollup(cv, q: PackedVector2Array, u0: float, u1: float, v1: float, open: float, s: int) -> void:
	cv.poly(P.sub(q, u0 - 0.02, 0.0, u1 + 0.02, v1 + 0.06), Color8(70, 72, 70))
	if open > 0.0:
		cv.poly(P.sub(q, u0, 0.0, u1, v1 * open), Color8(26, 28, 26))
	var g := P.sub(q, u0, v1 * open, u1, v1)
	cv.poly(g, STEEL, P.speckle(0.06, s))
	var rows := maxi(2, int(g[0].distance_to(g[3]) / 2.0))
	for i in rows:
		var t := float(i) / rows
		cv.line_v(g[0].lerp(g[3], t), g[1].lerp(g[2], t), P.mul(STEEL, 0.72))
	cv.line_v(g[3], g[2], STEEL_L)
	var stripe := P.sub(q, u0, v1 * open, u1, v1 * open + 0.04)
	cv.poly(stripe, Color8(176, 146, 52))  # hazard edge


## Vertical cylinder (tank, drum, column) centred at c (z = bottom), radius r tiles, height hz px.
## Left side lit. `band` (0..1 height) paints a team band there. Returns the top-centre screen point.
static func cyl(cv, o: Vector2, c: Vector3, r: float, hz: float, col: Color, s: int, band := -1.0, seams := 0) -> Vector2:
	var p0 := P.proj(o, c)
	var p1 := P.proj(o, c + Vector3(0, 0, hz))
	var rx := r * 45.25
	var ry := r * 22.63
	for x in range(int(floor(p0.x - rx)), int(ceil(p0.x + rx)) + 1):
		var dx := (x + 0.5 - p0.x) / rx
		if absf(dx) > 1.0:
			continue
		var e := ry * sqrt(1.0 - dx * dx)
		var k := 0.92 - 0.3 * dx - 0.14 * dx * dx
		for y in range(int(floor(p1.y)), int(ceil(p0.y + e))):
			var yy := y + 0.5
			if yy < p1.y or yy > p0.y + e:
				continue
			var cc := P.mul(col, k * (1.0 + (P.hn(x, y, s) - 0.5) * 0.06))
			var hfrac := (p0.y + e - yy) / maxf(1.0, hz)
			if band >= 0.0 and absf(hfrac - band) < 0.07:
				cv.team = true
				cv.px(x, y, Color(0.5 + 0.3 * (1.0 - dx), 0.5, 0.5))
				cv.team = false
				continue
			cv.px(x, y, cc)
		for i in seams:  # weld seams follow the lower half-ellipse
			var sy := p0.y - hz * (i + 1) / (seams + 1.0) + e
			cv.px(x, int(sy), P.mul(col, k * 0.78))
	cv.ellipse(p1.x, p1.y, rx, ry, P.mul(col, 1.1))
	cv.ellipse(p1.x - rx * 0.12, p1.y - ry * 0.12, rx * 0.72, ry * 0.68, P.mul(col, 1.22))
	return p1


## Pipe between two world points (2 px: lit top, shaded bottom).
static func pipe(cv, o: Vector2, a: Vector3, b: Vector3, col: Color) -> void:
	var pa := P.proj(o, a)
	var pb := P.proj(o, b)
	cv.line_v(pa + Vector2(0, 1), pb + Vector2(0, 1), P.mul(col, 0.62))
	cv.line_v(pa, pb, P.mul(col, 1.15))


## Sagging power cable between two screen points.
static func cable(cv, a: Vector2, b: Vector2, sag: float, col := Color8(26, 26, 24)) -> void:
	var n := maxi(2, int(a.distance_to(b)))
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) + Vector2(0, sag * 4.0 * t * (1.0 - t))
		cv.line_v(prev, p, col)
		prev = p


## Small floodlight: housing, bright lens and a soft glow halo.
static func lamp(cv, p: Vector2) -> void:
	cv.ellipse(p.x + 0.5, p.y + 0.5, 3.2, 2.4, Color(1.0, 0.92, 0.6, 0.22))
	cv.rect(int(p.x) - 1, int(p.y) - 1, 3, 2, Color8(52, 54, 50))
	cv.px(int(p.x), int(p.y), LAMP)
	cv.px(int(p.x) + 1, int(p.y), Color8(236, 200, 120))


## Faint plume of steam/smoke rising and drifting to the right from a stack top.
static func plume(cv, p: Vector2, s: int) -> void:
	for i in 6:
		var t := float(i) / 5.0
		var c := p + Vector2(2.0 + t * 9.0, -3.0 - t * 15.0)
		var r := 2.0 + t * 3.2
		var a := 0.30 * (1.0 - t * 0.6)
		for y in range(int(c.y - r), int(c.y + r) + 1):
			for x in range(int(c.x - r * 1.2), int(c.x + r * 1.2) + 1):
				var dx := (x + 0.5 - c.x) / (r * 1.2)
				var dy := (y + 0.5 - c.y) / r
				var d := dx * dx + dy * dy
				if d <= 1.0 and P.vnoise(x, y, 2.5, s + i) > 0.3:
					var g := 0.74 + 0.12 * (1.0 - d)
					cv.px(x, y, Color(g, g, g * 0.97, a * (1.0 - d * 0.5)))


## Rooftop HVAC unit: box with a fan disc on top.
static func hvac(cv, o: Vector2, c: Vector3, hx: float, hy: float, s: int) -> void:
	var r: Dictionary = P.box(cv, o, c, hx, hy, 4.0, 0.0, Color8(128, 130, 126), 0.05, s)
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		for u in [0.25, 0.5, 0.75]:
			cv.line_v(q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.2), q[3].lerp(q[2], u), Color8(96, 98, 94))
	var t: PackedVector2Array = r.top
	var m: Vector2 = (t[0] + t[2]) * 0.5
	var fr := minf(hx, hy) * 32.0
	cv.ellipse(m.x, m.y, fr, fr * 0.5, Color8(46, 48, 46))
	cv.px(int(m.x), int(m.y), Color8(120, 122, 118))
	edges(cv, r, Color8(128, 130, 126))


## Vent stub: small box with a dark cap opening.
static func vent(cv, o: Vector2, c: Vector3, s: int) -> void:
	var r: Dictionary = P.box(cv, o, c, 0.05, 0.05, 3.0, 0.0, Color8(112, 114, 110), 0.04, s)
	cv.poly(P.sub(r.top, 0.2, 0.2, 0.8, 0.8), DARK)
