extends RefCounted
## Machine Heavy Walker body (agent ART3-M): armoured hull on four legs (legs drawn by faction_m_units),
## off-white hex turret with team panels, long rail gun with cyan coil rings. Wreck: slumped and cold.
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/faction_m_lib.gd")


static func walker(cv, o: Vector2, rot: float, f: int, bob: float, wreck: bool) -> void:
	var hz0 := 4.0 if wreck else 16.0 + bob
	var trot := rot + (0.7 if wreck else 0.0)
	var hull: Color = L.DEAD if wreck else L.GRAPH
	var shell: Color = P.mul(L.DEAD, 1.15) if wreck else L.PANEL
	var tz := hz0 + 8.0 - (1.0 if wreck else 0.0)
	var toward := cos(trot) + sin(trot) > 0.0
	var rl := 0.2 if wreck else 0.24
	var rail_c := L.w(trot, 0.2 + rl, 0, tz + 3.0)
	# hull: graphite box with joints, emissive seam, side vents
	var h: Dictionary = P.box(cv, o, Vector3(0, 0, hz0), 0.3, 0.24, 8.0, rot, hull, 0.08, 121)
	for sd in h.sides:
		L.joints(cv, sd.quad, [0.33, 0.66], hull)
		L.seam(cv, sd.quad, 0.38, wreck, 0.06, 0.94)
		if not wreck:
			for i in 3:  # louvres
				var a: Vector2 = (sd.quad as PackedVector2Array)[0].lerp(sd.quad[1], 0.12 + i * 0.06).lerp(sd.quad[3].lerp(sd.quad[2], 0.12 + i * 0.06), 0.75)
				cv.px(int(a.x), int(a.y), L.JOINT)
	L.rims(cv, h, hull)
	if wreck:
		_scorch(cv, h.top)
	if not toward:
		_rail(cv, o, trot, rail_c, rl, f, wreck)
	# turret
	var t: Dictionary = L.hexp(cv, o, Vector3(-0.04 * cos(trot), -0.04 * sin(trot), tz), 0.21, 6.0, trot, shell, 123, null, 0.85)
	for sd in t.sides:
		if not wreck:
			L.team_panel(cv, sd.quad, 0.14, 0.3, 0.86, 0.75)
		L.seam(cv, sd.quad, 0.9, wreck)
	if not wreck:
		L.hex_plate(cv, t.top, 0.35, 0.5, 3.0, L.GRAPH_D, true)
		var ant := P.proj(o, L.w(trot, -0.16, 0.1, tz + 6))
		cv.line_v(ant, ant + Vector2(0, -7), L.JOINT)
		cv.px(int(ant.x), int(ant.y) - 8, L.CYAN)
		if toward:
			L.eye(cv, P.proj(o, L.w(trot, 0.17, -0.07, tz + 4)), true)
	else:
		_scorch(cv, t.top)
	if toward:
		_rail(cv, o, trot, rail_c, rl, f, wreck)


static func _rail(cv, o: Vector2, trot: float, c: Vector3, rl: float, f: int, wreck: bool) -> void:
	var col: Color = L.DEAD_D if wreck else L.GRAPH_D
	for s in [-1, 1]:
		var cc := c + L.w(trot, 0, 0.035 * s)
		P.box(cv, o, cc, rl, 0.02, 2.0, trot, col, 0.04, 127)
	if wreck:
		return
	for i in 4:  # coil rings
		var p := P.proj(o, c + L.w(trot, -rl + 0.08 + i * 0.1, 0, 1.5))
		cv.px(int(p.x), int(p.y), L.CYAN)
		cv.px(int(p.x), int(p.y) + 1, L.TEAL)
	if f == 3:
		var tip := P.proj(o, c + L.w(trot, rl + 0.05, 0, 1.5))
		cv.ellipse(tip.x, tip.y, 3.5, 2.6, Color(L.CYAN.r, L.CYAN.g, L.CYAN.b, 0.55))
		cv.ellipse(tip.x, tip.y, 1.8, 1.3, L.CYAN_HOT)
		var far := P.proj(o, c + L.w(trot, rl + 0.2, 0, 1.5))
		cv.line_v(tip, far, Color(L.CYAN_HOT.r, L.CYAN_HOT.g, L.CYAN_HOT.b, 0.8))


static func _scorch(cv, q: PackedVector2Array) -> void:
	cv.poly(q, L.DEAD, func(x: int, y: int, c: Color) -> Color:
		var hh := P.hn(x, y, 919)
		if hh > 0.82:
			return Color8(96, 70, 52)
		if hh < 0.3:
			return P.mul(c, 0.55)
		return P.mul(c, 0.8 + hh * 0.3))
