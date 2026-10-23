extends RefCounted
## Machine building dressing (agent ART3-M): panel joints, emissive seams, hex plates, bay doors, coils,
## cargo, team panels, the team beacon pylon, slab hex tiling, hologram lattice and printer drones.
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/faction_m_lib.gd")


static func _long(sd: Dictionary) -> bool:  # side faces +y (screen down-left) vs +x (down-right)
	return (sd.n as Vector2).y > (sd.n as Vector2).x


static func dress(cv, o: Vector2, def: String, p: Array, r: Dictionary) -> void:
	var role: String = p[8]
	var col: Color = p[7]
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		match role:
			"main", "hall", "hangar":
				L.joints(cv, q, [0.2, 0.4, 0.6, 0.8], col)
				L.seam(cv, q, 0.82, false, 0.02, 0.98)
				L.team_panel(cv, q, 0.04, 0.88, 0.96, 0.97, 0.66)
				if role == "hall" and _long(sd):
					_hex_door(cv, q)
				elif role == "hangar" and not _long(sd):
					_bay(cv, q)
				elif role == "main" and def == "m_reprocessor" and _long(sd):
					_bay(cv, q)
			"tower":
				L.team_panel(cv, q, 0.1, 0.55, 0.9, 0.8)
				L.seam(cv, q, 0.3)
			"crown", "vent":
				L.seam(cv, q, 0.5)
			"coil":
				for v in [0.25, 0.45, 0.65, 0.85]:
					L.seam(cv, q, v)
			"tank":
				L.team_panel(cv, q, 0.0, 0.6, 1.0, 0.78)
				L.joints(cv, q, [0.5], col)
			"hopper":
				L.joints(cv, q, [0.33, 0.66], col)
				L.team_panel(cv, q, 0.06, 0.3, 0.94, 0.55)
			"turret", "module", "roofhex":
				L.team_panel(cv, q, 0.12, 0.3, 0.88, 0.75)
			"base":
				L.seam(cv, q, 0.6)
	L.rims(cv, r, col)
	var t: PackedVector2Array = r.top
	match role:
		"crown":
			var c: Vector2 = (t[0] + t[3]) * 0.5
			L.eye(cv, c + Vector2(0, 1), true)
		"pad":
			var c2 := P.proj(o, Vector3(p[1], p[2], p[3] + p[6]))
			for i in 6:
				var a := i * PI / 3.0
				var b := (i + 1) * PI / 3.0
				var rp: float = p[4] * 32.0 * 0.62
				cv.line_v(c2 + Vector2(cos(a) * rp, sin(a) * rp * 0.5), c2 + Vector2(cos(b) * rp, sin(b) * rp * 0.5), L.CYAN)
			cv.px(int(c2.x), int(c2.y), L.CYAN_HOT)
		"coil":
			var c3 := P.proj(o, Vector3(p[1], p[2], p[3] + p[6]))
			cv.ellipse(c3.x + 0.5, c3.y - 1.5, 3.5, 3.0, Color(L.CYAN.r, L.CYAN.g, L.CYAN.b, 0.35))
			cv.ellipse(c3.x + 0.5, c3.y - 0.5, 1.6, 1.2, L.CYAN_HOT)
		"vent":
			var c4 := P.proj(o, Vector3(p[1], p[2], p[3] + p[6]))
			cv.ellipse(c4.x, c4.y, 3.0, 1.5, Color8(24, 26, 28))
			cv.px(int(c4.x), int(c4.y), L.TEAL)
		"hopper":
			var inner := P.sub(t, 0.1, 0.1, 0.9, 0.9)
			cv.poly(inner, Color8(32, 34, 36))
			for i in 14:
				var q2 := P.sub(inner, P.hn(i, 1, 211) * 0.85 + 0.05, P.hn(i, 2, 211) * 0.85 + 0.05, 0.0, 0.0)
				cv.rect(int(q2[0].x), int(q2[0].y), 2, 1, [Color8(120, 98, 70), Color8(112, 112, 106), Color8(88, 70, 54)][i % 3])
		"belt":
			for u in [0.1, 0.25, 0.4, 0.55, 0.7, 0.85]:
				cv.line_v(t[0].lerp(t[1], u), t[3].lerp(t[2], u), P.mul(col, 1.4))
		"roof":
			for i in 3:
				for j in 3:
					L.hex_plate(cv, t, 0.2 + i * 0.3, 0.2 + j * 0.3, 3.5, P.mul(col, 0.8), (i + j) % 2 == 0)
		"main", "hall", "module", "roofhex":
			L.hex_plate(cv, t, 0.3, 0.3, 4.0, P.mul(col, 0.78), true)
			L.hex_plate(cv, t, 0.7, 0.6, 3.0, P.mul(col, 0.78), false)
		"head":
			var c5 := P.proj(o, Vector3(0.12, 0.12, p[3] + 3))
			L.eye(cv, c5, true)
			cv.team = true
			L.hexp(cv, o, Vector3(p[1], p[2], p[3] + p[6]), p[4] * 0.6, 0.0, 0.0, Color(0.75, 0.75, 0.75), 7)
			cv.team = false


## Glowing hexagonal bay door on a long wall face.
static func _hex_door(cv, q: PackedVector2Array) -> void:
	var d := P.sub(q, 0.3, 0.0, 0.7, 0.62)
	cv.poly(d, Color8(28, 30, 33))
	var c: Vector2 = (d[0] + d[1] + d[2] + d[3]) * 0.25
	for i in 6:
		var a := i * PI / 3.0 + PI / 6.0
		var b := (i + 1) * PI / 3.0 + PI / 6.0
		cv.line_v(c + Vector2(cos(a) * 6, sin(a) * 5), c + Vector2(cos(b) * 6, sin(b) * 5), L.CYAN)
	L.eye(cv, c, true)


## Vehicle bay: dark opening with a cyan frame and shutter slats.
static func _bay(cv, q: PackedVector2Array) -> void:
	var d := P.sub(q, 0.22, 0.0, 0.78, 0.7)
	cv.poly(d, Color8(30, 32, 35))
	for v in [0.25, 0.45, 0.65]:
		cv.line_v(d[0].lerp(d[3], v), d[1].lerp(d[2], v), Color8(46, 49, 53))
	cv.line_v(d[3], d[2], L.CYAN)
	cv.line_v(d[0], d[3], L.TEAL)
	cv.line_v(d[1], d[2], L.TEAL)


## Extra post-pass props for finished buildings (cables, small lamps).
static func post(cv, o: Vector2, def: String) -> void:
	match def:
		"m_crawler_works":  # crane hook on the gantry beam
			var a := P.proj(o, Vector3(1.22, 0.25, 30))
			cv.line_v(a, a + Vector2(0, 9), L.JOINT)
			cv.rect(int(a.x) - 1, int(a.y) + 9, 3, 2, L.PANEL_D)
		"m_sentry":
			for s in [-1, 1]:
				var b0 := P.proj(o, Vector3(0.1, 0.06 * s, 14))
				var b1 := P.proj(o, Vector3(0.48, 0.06 * s, 14))
				cv.line_v(b0, b1, L.GRAPH_D)
				cv.line_v(b0 + Vector2(0, 1), b1 + Vector2(0, 1), L.JOINT)
			L.eye(cv, P.proj(o, Vector3(0.22, -0.08, 14)), true)
		"m_core", "m_charging_hub":
			var a2 := P.proj(o, Vector3(1.22, -0.9, 26))
			var b2 := P.proj(o, Vector3(-0.9, 1.22, 26))
			if def == "m_core":
				cv.px(int(a2.x), int(a2.y), L.CYAN_HOT)
				cv.px(int(b2.x), int(b2.y), L.CYAN_HOT)
		"m_sensor_relay":  # flat sensor panels on the mast
			for z in [20, 30]:
				var m := P.proj(o, Vector3(0, 0, z))
				cv.rect(int(m.x) - 4, int(m.y), 3, 2, L.PANEL_D)
				cv.rect(int(m.x) + 2, int(m.y), 3, 2, P.mul(L.PANEL_D, 0.8))
				cv.px(int(m.x) - 4, int(m.y), L.CYAN)


## Hex tiling scored into the foundation slab.
static func slab_pattern(cv, top: PackedVector2Array, size: int, raw: bool) -> void:
	var n := size * 3
	for i in n:
		for j in n:
			var u := (i + 0.5 + (0.5 if j % 2 == 1 else 0.0)) / n
			var v := (j + 0.5) / n
			if u > 0.98:
				continue
			L.hex_plate(cv, top, u, v, 3.0 if size > 1 else 2.5, P.mul(L.SLAB, 0.86 if not raw else 0.8), false)


static func holo_hex(cv, o: Vector2, c: Vector3, r: float, hz: float, sq: float) -> void:
	var col := Color(L.CYAN.r, L.CYAN.g, L.CYAN.b, 0.5)
	var pts: Array = []
	for i in 6:
		var a := i * PI / 3.0
		var b := Vector3(c.x + cos(a) * r, c.y + sin(a) * r * sq, 0)
		pts.append([P.proj(o, Vector3(b.x, b.y, c.z)), P.proj(o, Vector3(b.x, b.y, c.z + hz))])
	for i in 6:
		var j := (i + 1) % 6
		cv.line_v(pts[i][1], pts[j][1], col)
		if pts[i][0].y >= pts[(i + 3) % 6][0].y:
			cv.line_v(pts[i][0], pts[i][1], col)


## Small fabricator drones hovering over a building site.
static func printers(cv, o: Vector2, size: int, st: int) -> void:
	for i in mini(size, 2) + 1:
		var a := Vector3(-0.3 + P.hn(i, st, 233) * 0.6, -0.3 + P.hn(i, st, 234) * 0.6, 24 + i * 6) * Vector3(size, size, 1)
		var p := P.proj(o, a)
		cv.rect(int(p.x) - 2, int(p.y), 5, 2, L.GRAPH)
		cv.px(int(p.x), int(p.y) + 2, L.CYAN_HOT)
		for k in 6:  # deposition beam
			cv.px(int(p.x), int(p.y) + 3 + k * 2, Color(L.CYAN.r, L.CYAN.g, L.CYAN.b, 0.6 - k * 0.08))


## Team beacon pylon at the front-left corner (stake under construction).
static func beacon(cv, o: Vector2, half: float, raw: bool) -> void:
	var base := P.proj(o, Vector3(-half + 0.12, half - 0.12, 2))
	var ph := 30 if not raw else 12
	cv.line(int(base.x), int(base.y), int(base.x), int(base.y) - ph, L.GRAPH_D)
	cv.line(int(base.x) + 1, int(base.y), int(base.x) + 1, int(base.y) - ph, L.JOINT)
	var bw := 8 if not raw else 4
	var bh := 6 if not raw else 3
	cv.team = true
	for yy in bh:
		for xx in bw:
			var lum := 0.92 if yy == 0 or xx == 0 else 0.78
			cv.px(int(base.x) + 2 + xx, int(base.y) - ph + yy + xx / 3, Color(lum, lum, lum))
	cv.team = false
	cv.px(int(base.x), int(base.y) - ph - 1, L.CYAN_HOT)
