extends RefCounted
## Human B building dressing (agent ART3-B): brick / corrugated-iron textures, factory windows,
## gates, firing slits, sawtooth roofs, sooty stacks with dark smoke, riveted boilers, the furnace
## glow, scrap piles, sandbags, plus a per-building post pass (crane magnet, skip bridge, pipes).
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const V = preload("res://tools/art/faction_b_veh.gd")

const MORTAR := Color8(150, 138, 120)
const TAR := Color8(62, 58, 54)
const GLOW := Color8(255, 150, 50)
const SOOT := Color8(30, 28, 26)


static func _face(sd: Dictionary) -> String:
	var n: Vector2 = sd.n
	return "y" if n.y > 0.7 else ("x" if n.x > 0.7 else "")


## Re-shade the pixels already inside q with a running-bond brick pattern (3x2 px bricks).
static func brick_tex(cv, q: PackedVector2Array, s: int) -> void:
	cv.poly(q, MORTAR, func(x: int, y: int, _b: Color) -> Color:
		var e: Color = cv.get_px(x, y)
		if e.a < 0.6:
			return Color(0, 0, 0, 0)
		if y % 3 == 2:
			return P.mix(e, MORTAR, 0.35)
		if (x + (y / 3) % 2 * 2) % 4 == 0:
			return P.mul(e, 0.8)
		return P.mul(e, 0.94 + P.hn(x / 4, y / 3, s) * 0.14))


## Corrugated sheet: vertical ridges (walls) or diagonal ridges (roofs, `diag`).
static func corr_tex(cv, q: PackedVector2Array, diag := false) -> void:
	cv.poly(q, MORTAR, func(x: int, y: int, _b: Color) -> Color:
		var e: Color = cv.get_px(x, y)
		if e.a < 0.6:
			return Color(0, 0, 0, 0)
		var k: float = [1.14, 1.0, 0.8, 0.94][posmod(x + (2 * y if diag else 0), 4)]
		return P.mul(e, k))


static func oil_stains(cv, top: PackedVector2Array, s: int) -> void:
	for i in 3:
		var u := 0.2 + P.hn(i, s, 1) * 0.6
		var v := 0.2 + P.hn(i, s, 2) * 0.6
		var c: Vector2 = top[0].lerp(top[1], u).lerp(top[3].lerp(top[2], u), v)
		cv.ellipse(c.x, c.y, 4.0 + i, 2.0 + i * 0.5, Color(0.08, 0.07, 0.06, 0.28))


## Dark, sooty smoke drifting up and to the right.
static func dark_plume(cv, p: Vector2, s: int, n := 7) -> void:
	for i in n:
		var t := float(i) / (n - 1)
		var c := p + Vector2(1.5 + t * 11.0, -3.0 - t * 18.0)
		var r := 2.0 + t * 3.6
		for y in range(int(c.y - r), int(c.y + r) + 1):
			for x in range(int(c.x - r * 1.2), int(c.x + r * 1.2) + 1):
				var dx := (x + 0.5 - c.x) / (r * 1.2)
				var dy := (y + 0.5 - c.y) / r
				var d := dx * dx + dy * dy
				if d <= 1.0 and P.vnoise(x, y, 2.5, s + i) > 0.32:
					var g := 0.22 + 0.2 * t + 0.08 * (1.0 - d)
					cv.px(x, y, Color(g, g * 0.97, g * 0.94, 0.5 * (1.0 - t * 0.5)))


static func cyl_dress(cv, o: Vector2, def: String, role: String, c: Vector3, r: float, hz: float, top: Vector2) -> void:
	var rx := r * 45.25
	match role:
		"stack":
			for k in [0.3, 0.62]:  # iron bands
				var by: float = top.y + hz * (1.0 - k)
				cv.line(int(top.x - rx), int(by), int(top.x + rx), int(by), Color8(60, 52, 46))
			cv.ellipse(top.x, top.y, rx, rx * 0.5, SOOT)
			for y in range(int(top.y), int(top.y + 5)):  # soot-blackened crown
				for x in range(int(top.x - rx), int(top.x + rx) + 1):
					if cv.get_px(x, y).a > 0.6 and P.hn(x, y, 901) > 0.25:
						cv.px(x, y, Color(SOOT.r, SOOT.g, SOOT.b, 0.75 - (y - top.y) * 0.12))
			if hz > 40:
				dark_plume(cv, top, 905 + int(c.x * 10))
		"boiler":
			for k in [0.2, 0.5]:  # rivet rings
				var by: float = top.y + hz * (1.0 - k) + rx * 0.45
				for i in 7:
					var x := int(top.x - rx * 0.8 + i * rx * 0.26)
					cv.px(x, int(by), Color8(150, 152, 146))
			cv.ellipse(top.x, top.y, rx * 0.3, rx * 0.15, Color8(60, 62, 60))  # safety valve
			B.plume(cv, top + Vector2(0, -2), 911)
		"furnace":
			var gy := top.y + hz + rx * 0.3
			cv.ellipse(top.x + rx * 0.4, gy - 4, 3.5, 2.5, GLOW)                 # tap hole
			cv.ellipse(top.x + rx * 0.4, gy - 4, 1.6, 1.2, Color8(255, 230, 150))
			cv.ellipse(top.x + rx * 0.4, gy + 1, 7.0, 2.4, Color(1.0, 0.55, 0.2, 0.35))  # glow on the ground
			cv.ellipse(top.x, top.y, rx * 0.55, rx * 0.27, SOOT)                   # charging throat
			var cone := top + Vector2(0, -8)
			cv.line_v(top + Vector2(-rx * 0.5, 0), cone, Color8(80, 76, 70))
			cv.line_v(top + Vector2(rx * 0.5, 0), cone, Color8(64, 60, 56))
			dark_plume(cv, cone, 915, 6)
		"drum":
			cv.line(int(top.x - rx), int(top.y + hz * 0.5), int(top.x + rx), int(top.y + hz * 0.5), P.mul(V.RUST, 0.8))


## A heap of rusty scrap: several small tilted boxes in mixed colours, plus a few bright edges.
static func scrap_pile(cv, o: Vector2, c: Vector3, hx: float, hy: float, hz: float, col: Color, s: int, raw: bool) -> void:
	var n := 7
	var items := []
	for i in n:
		var u := (P.hn(i, s, 1) - 0.5) * 2.0 * hx * 0.8
		var v := (P.hn(i, s, 2) - 0.5) * 2.0 * hy * 0.8
		items.append([u + v, u, v, i])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		var i: int = it[3]
		var k := P.hn(i, s, 3)
		var cc: Color = col if k < 0.45 else (V.PRIMER if k < 0.7 else (Color8(84, 92, 64) if k < 0.85 else Color8(70, 64, 58)))
		if raw:
			cc = P.mix(cc, Color8(150, 140, 126), 0.3)
		var h := hz * (0.4 + P.hn(i, s, 4) * 0.8)
		var r: Dictionary = P.box(cv, o, c + Vector3(it[1], it[2], 0), hx * 0.32, hy * 0.24, h, P.hn(i, s, 5) * 3.0, cc, 0.16, s + i)
		if not raw:
			V.streaks(cv, r.top, s + i, 0.6)
			if k > 0.5:
				cv.line_v(r.top[0], r.top[1], P.mul(cc, 1.4))


static func dress(cv, o: Vector2, def: String, role: String, p: Array, r: Dictionary, col: Color) -> void:
	var s := int(p[0] * 100 + p[1] * 37)
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		var face := _face(sd)
		var n := maxi(2, int(q[0].distance_to(q[1]) / 9.0))
		match role:
			"brick":
				brick_tex(cv, q, s)
				if def == "b_barracks":  # fortified: steel-shuttered firing slits, a door
					for i in n + 1:
						var u0 := 0.08 + i * 0.84 / (n + 1)
						cv.poly(P.sub(q, u0, 0.55, u0 + 0.06, 0.62), Color8(20, 20, 18))
						cv.line_v(P.sub(q, u0 - 0.01, 0.64, u0 + 0.07, 0.64)[0], P.sub(q, u0 - 0.01, 0.64, u0 + 0.07, 0.64)[1], V.PRIMER)
					if face == "y":
						B.door(cv, q, 0.46, 0.56, 0.5, V.PRIMER)
				else:
					B.window_row(cv, q, 0.5, 0.74, n, Color8(84, 80, 72), s + 3, 0.3)
					if def == "b_works":
						B.window_row(cv, q, 0.18, 0.36, n, Color8(84, 80, 72), s + 4, 0.2)
					if face == "y":
						B.rollup(cv, q, 0.3, 0.62, 0.42 if def == "b_works" else 0.38, 0.5, s + 5)
				cv.team = true
				cv.poly(P.sub(q, 0.0, 0.86, 1.0, 0.93), Color(0.7, 0.7, 0.7))  # painted cornice band
				cv.team = false
			"shed", "sawtooth":
				corr_tex(cv, q)
				V.streaks(cv, q, s + 6, 0.75)
				if face == "y":
					B.rollup(cv, q, 0.12, 0.45, 0.6, 0.55, s + 7)
					if role == "sawtooth":
						B.rollup(cv, q, 0.55, 0.88, 0.6, 0.0, s + 8)
				elif face == "x":
					B.door(cv, q, 0.66, 0.78, 0.5, col)
				B.window_row(cv, q, 0.72, 0.82, n, col, s + 9, 0.15)
				cv.team = true
				cv.poly(P.sub(q, 0.03, 0.88, 0.97, 0.95), Color(0.7, 0.7, 0.7))
				cv.team = false
			"bunker":
				cv.poly(P.sub(q, 0.15, 0.5, 0.85, 0.68), Color8(18, 18, 16))  # firing slit
				cv.line_v(P.sub(q, 0.13, 0.7, 0.87, 0.7)[0], P.sub(q, 0.13, 0.7, 0.87, 0.7)[1], P.mul(col, 1.3))
				V.patch(cv, q, 0.05, 0.1, 0.3, 0.42, V.PRIMER, s + 10)
				cv.team = true
				cv.poly(P.sub(q, 0.4, 0.1, 0.6, 0.4), Color(0.66, 0.66, 0.66))
				cv.team = false
			"plate":
				V.rivets(cv, q, 0.5, 6, col)
			"sandbag":
				var rows := maxi(2, int(q[0].distance_to(q[3]) / 2.0))
				for i in rows:
					var t := float(i) / rows
					cv.line_v(q[0].lerp(q[3], t), q[1].lerp(q[2], t), P.mul(col, 0.74))
				for i in maxi(2, int(q[0].distance_to(q[1]) / 4.0)):
					var u := (i + 0.5 * (i % 2)) / maxf(2.0, q[0].distance_to(q[1]) / 4.0)
					cv.line_v(q[0].lerp(q[1], u), q[3].lerp(q[2], u), P.mul(col, 0.85))
	# roofs / tops
	match role:
		"brick":
			cv.poly(P.sub(r.top, 0.04, 0.04, 0.96, 0.96), TAR if def != "b_barracks" else V.PRIMER)
			corr_tex(cv, P.sub(r.top, 0.04, 0.04, 0.96, 0.96), true)
			B.edges(cv, r, col)
			if def == "b_barracks":
				for v in [0.3, 0.7]:
					V.rivets(cv, PackedVector2Array([r.top[0], r.top[1], r.top[2], r.top[3]]), v, 10, V.PRIMER)
			else:
				B.vent(cv, o, Vector3(p[0] + 0.3, p[1] + 0.2, p[2] + p[5]), 920)
		"shed":
			corr_tex(cv, r.top, true)
			B.edges(cv, r, col)
		"sawtooth":
			_sawtooth(cv, r.top, col)
		"bunker", "plate":
			B.edges(cv, r, col)


## North-light sawtooth roof: 4 sloped iron strips, each ending in a raised glazed face.
static func _sawtooth(cv, top: PackedVector2Array, col: Color) -> void:
	for i in 4:
		var u0 := i / 4.0
		var u1 := (i + 1) / 4.0
		var l0: Vector2 = top[0].lerp(top[1], u0)
		var l1: Vector2 = top[3].lerp(top[2], u0)
		var r0: Vector2 = top[0].lerp(top[1], u1)
		var r1: Vector2 = top[3].lerp(top[2], u1)
		var up := Vector2(0, -7)
		var slope := PackedVector2Array([l0, r0 + up, r1 + up, l1])
		cv.poly(slope, P.mul(col, 1.08), P.speckle(0.08, 930 + i))
		corr_tex(cv, slope, true)
		cv.poly(PackedVector2Array([r0, r1, r1 + up, r0 + up]), Color8(48, 58, 62))
		cv.line_v(r0 + up, r1 + up, P.mul(col, 1.35))
		cv.line_v(r0.lerp(r0 + up, 0.5), r1.lerp(r1 + up, 0.5), Color8(96, 116, 124))


static func post(cv, o: Vector2, def: String) -> void:
	match def:
		"b_works":
			B.lamp(cv, P.proj(o, Vector3(0.6, 1.05, 18)))
			B.pipe(cv, o, Vector3(-0.83, -0.95, 30), Vector3(-0.55, -0.85, 24), Color8(90, 84, 76))
		"b_salvage_yard":  # magnet crane: boom from the mast head over the scrap, cable and magnet disc
			var head := P.proj(o, Vector3(-0.5, -0.5, 44))
			var tip := P.proj(o, Vector3(0.25, -0.5, 36))
			cv.line_v(head, tip, Color8(176, 112, 48))
			cv.line_v(head + Vector2(0, 1), tip + Vector2(0, 1), Color8(120, 74, 38))
			cv.line_v(head + Vector2(0, 6), tip, Color8(120, 74, 38))
			var mag := tip + Vector2(0, 14)
			cv.line_v(tip, mag, Color8(36, 36, 32))
			cv.ellipse(mag.x, mag.y + 1, 4.5, 2.2, Color8(54, 54, 50))
			cv.ellipse(mag.x - 0.5, mag.y, 3.5, 1.5, Color8(96, 98, 94))
			cv.team = true
			cv.rect(int(head.x) - 1, int(head.y) - 2, 3, 2, Color(0.8, 0.8, 0.8))  # cab on the mast head
			cv.team = false
		"b_heavy_plant":
			B.lamp(cv, P.proj(o, Vector3(1.1, 0.4, 20)))
			B.cable(cv, P.proj(o, Vector3(-1.08, -1.05, 40)), P.proj(o, Vector3(-0.4, -0.6, 28)), 2.0)
		"b_smelter":  # inclined skip bridge from the casting shed to the furnace throat
			for s in [-1, 1]:
				var a := P.proj(o, Vector3(0.3, 0.2 + s * 0.06, 16))
				var b := P.proj(o, Vector3(-0.4, -0.4 + s * 0.06, 44))
				cv.line_v(a, b, Color8(70, 66, 60) if s < 0 else Color8(96, 90, 82))
			for i in 5:
				var t := (i + 0.5) / 5.0
				var m := P.proj(o, Vector3(0.3, 0.2, 16)).lerp(P.proj(o, Vector3(-0.4, -0.4, 44)), t)
				cv.px(int(m.x), int(m.y) + 1, Color8(60, 56, 50))
		"b_bunker":  # MG barrel poking out of the front slit
			var a := P.proj(o, Vector3(0.72, 0.1, 7))
			cv.line_v(a, a + Vector2(6, 3), Color8(40, 40, 36))
			cv.px(int(a.x) + 6, int(a.y) + 3, Color8(70, 70, 64))
