extends RefCounted
## Resource nodes (salvage pile, ore deposit) and building rubble (sizes 1-3).
const P = preload("res://tools/art/pix.gd")

const RUST := Color8(132, 80, 48)
const RUST_D := Color8(92, 58, 40)
const GUNMETAL := Color8(70, 72, 72)
const ORE_ROCK := Color8(96, 88, 80)
const GLINT := Color8(214, 196, 120)
const GLINT2 := Color8(150, 200, 196)
const RUBBLE := Color8(128, 124, 114)
const CHAR := Color8(46, 42, 38)


static func build(out: Dictionary) -> void:
	var res := {}
	for i in 2:
		var nm := "salvage" if i == 0 else "ore"
		var cv = P.Canvas.new(56, 44)
		var o := Vector2(28, 28)
		if i == 0:
			_salvage(cv, o)
		else:
			_ore(cv, o)
		out.images["resources/%s.png" % nm] = cv.img
		res[nm] = {"file": "resources/%s.png" % nm, "pivot": [28, 28]}
	out.manifest["resources"] = res
	var rub := {}
	for size in [1, 2, 3]:
		var w: int = size * 64 + 8
		var hgt: int = size * 32 + 30
		var o := Vector2(w / 2, 22 + size * 16)
		var cv = P.Canvas.new(w, hgt)
		_rubble(cv, o, size)
		out.images["wrecks/rubble_%d.png" % size] = cv.img
		rub[str(size)] = {"file": "wrecks/rubble_%d.png" % size, "pivot": [int(o.x), int(o.y)]}
	out.manifest["rubble"] = rub


static func _pieces(n: int, s: int, spread: float, hmax: float) -> Array:
	var arr: Array = []
	for k in n:
		var a := P.hn(k, s, 1) * TAU
		var rr := sqrt(P.hn(k, s, 2)) * spread
		arr.append([Vector3(cos(a) * rr, sin(a) * rr, 0), 0.05 + P.hn(k, s, 3) * 0.12, 0.03 + P.hn(k, s, 4) * 0.08,
			2.0 + P.hn(k, s, 5) * hmax * (1.0 - rr / spread * 0.6), P.hn(k, s, 6) * PI])
	arr.sort_custom(func(a, b): return a[0].x + a[0].y < b[0].x + b[0].y)
	return arr


static func _salvage(cv, o: Vector2) -> void:
	var ps := _pieces(14, 11, 0.42, 10.0)
	for p in ps:
		P.box_shadow(cv, o, p[0], p[1], p[2], p[3], p[4])
	cv.ellipse(o.x, o.y + 1, 18, 7, Color.BLACK, true)
	cv.flush_shadow(Color(0.05, 0.04, 0.03, 0.35))
	for k in ps.size():
		var p: Array = ps[k]
		var col: Color = [RUST, RUST_D, GUNMETAL, Color8(110, 106, 92)][k % 4]
		var r: Dictionary = P.box(cv, o, p[0], p[1], p[2], p[3], p[4], col, 0.22, 70 + k)
		if k % 3 == 0:
			cv.line_v(r.top[0], r.top[2], P.mul(col, 0.6))
	# a tyre and a bent pipe on top
	var t := P.proj(o, Vector3(0.05, 0.1, 9))
	cv.ellipse(t.x, t.y, 4.5, 2.6, Color8(32, 32, 30))
	cv.ellipse(t.x, t.y, 1.8, 1.0, Color8(70, 66, 58))
	var a := P.proj(o, Vector3(-0.2, -0.1, 12))
	cv.line(int(a.x), int(a.y), int(a.x) + 9, int(a.y) + 3, Color8(150, 92, 56))
	cv.outline(Color(0.10, 0.08, 0.07, 1))


static func _ore(cv, o: Vector2) -> void:
	var ps := _pieces(9, 23, 0.4, 14.0)
	for p in ps:
		P.box_shadow(cv, o, p[0], p[1] * 1.4, p[2] * 1.6, p[3], p[4])
	cv.flush_shadow()
	for k in ps.size():
		var p: Array = ps[k]
		var r: Dictionary = P.box(cv, o, p[0], p[1] * 1.4, p[2] * 1.6, p[3], p[4], ORE_ROCK, 0.18, 90 + k,
			P.mul(ORE_ROCK, 1.22))
		# mineral veins + glints on the faces
		for sd in r.sides:
			var q: PackedVector2Array = sd.quad
			var u := P.hn(k, 3, 91)
			cv.line_v(P.sub(q, u, 0.2, u, 0.2)[0], P.sub(q, u + 0.3, 0.7, u + 0.3, 0.7)[0], Color8(150, 120, 70))
		var g: Vector2 = P.sub(r.top, 0.4, 0.4, 0.4, 0.4)[0]
		cv.px(int(g.x), int(g.y), GLINT if k % 2 == 0 else GLINT2)
		cv.px(int(g.x) + 1, int(g.y), Color(1, 1, 0.9))
	cv.outline(Color(0.10, 0.09, 0.08, 1))


static func _rubble(cv, o: Vector2, size: int) -> void:
	var half := size * 0.5 - 0.08
	cv.poly(PackedVector2Array([P.proj(o, Vector3(-half, -half, 0)), P.proj(o, Vector3(half, -half, 0)),
		P.proj(o, Vector3(half, half, 0)), P.proj(o, Vector3(-half, half, 0))]), CHAR,
		func(x: int, y: int, c: Color) -> Color:
			var h := P.hn(x, y, 300 + size)
			return P.mix(c, RUBBLE, 0.35 * h) if h > 0.3 else P.mul(c, 0.8))
	var ps := _pieces(6 + size * 6, 40 + size, half * 0.9, 6.0 + size * 3.0)
	for p in ps:
		P.box_shadow(cv, o, p[0], p[1] * size * 0.7, p[2] * size * 0.7, p[3], p[4])
	cv.flush_shadow()
	for k in ps.size():
		var p: Array = ps[k]
		var col := RUBBLE if k % 3 != 0 else P.mix(RUBBLE, CHAR, 0.6)
		P.box(cv, o, p[0], p[1] * size * 0.7, p[2] * size * 0.7, p[3], p[4], col, 0.2, 120 + k)
	# a few bent rebar strands
	for k in size * 2:
		var a := P.proj(o, Vector3(P.hn(k, size, 7) - 0.5, P.hn(k, size, 8) - 0.5, 3) * half)
		cv.line(int(a.x), int(a.y), int(a.x) + 2 + k % 3, int(a.y) - 6, Color8(96, 62, 44))
	cv.outline(Color(0.09, 0.08, 0.07, 1))
