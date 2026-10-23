extends RefCounted
## Logistics truck (agent E2): 6-wheel cab-over truck with an open cargo bed loaded with crates,
## ammo boxes and jerrycans. Same box/iso pipeline and detail helpers as the armoured vehicles.
## Team colour: cab roof + a stripe on the bed side boards. Frames idle/move/fire (fire = idle; unarmed).
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")

const BODY := Color8(98, 102, 76)
const CHASSIS := Color8(50, 50, 46)
const GLASS := Color8(44, 58, 64)
const GLASS_HI := Color8(140, 170, 176)
const WOOD := Color8(132, 106, 70)
const AMMO := Color8(78, 84, 58)
const LAMP := Color8(236, 226, 172)
const BURNT := Color8(58, 52, 46)
const CHAR := Color8(40, 36, 32)
# Cargo: [fwd, right, hx, hy, hz, colour, kind]
const CARGO := [
	[-0.36, -0.11, 0.11, 0.1, 6.0, WOOD, "crate"], [-0.36, 0.11, 0.1, 0.1, 4.5, AMMO, "ammo"],
	[-0.13, -0.11, 0.1, 0.1, 5.0, WOOD, "crate"], [-0.13, 0.11, 0.08, 0.09, 5.5, Color8(72, 84, 54), "cans"],
]


static func draw(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var body: Color = BURNT if wreck else BODY
	# shadows
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 0), 0.52, 0.22, 4.0, rot)
	P.box_shadow(cv, o, D.w(rot, 0.36, 0.0, 4.5), 0.16, 0.22, 9.5, rot)
	P.box_shadow(cv, o, D.w(rot, -0.2, 0.0, 4.5), 0.34, 0.23, 6.0, rot)
	cv.flush_shadow()
	_wheels(cv, o, rot, f, wreck, false)
	var ch: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 2.0), 0.52, 0.16, 2.5, rot, CHASSIS if not wreck else CHAR, 0.08, 11)
	for sd in ch.sides:
		if absf((sd.n as Vector2).dot(Vector2(cos(rot), sin(rot)))) > 0.7:
			D.tow_hooks(cv, sd.quad)
	_wheels(cv, o, rot, f, wreck, true)
	if D.faces_cam(rot, 1.0, 0.0):
		_bed(cv, o, rot, body, wreck)
		_exhaust(cv, o, rot, wreck)
		_cab(cv, o, rot, body, wreck)
	else:
		_cab(cv, o, rot, body, wreck)
		_exhaust(cv, o, rot, wreck)
		_bed(cv, o, rot, body, wreck)
	cv.outline(Color(0.08, 0.08, 0.07, 1))


static func _wheels(cv, o: Vector2, rot: float, f: int, wreck: bool, near: bool) -> void:
	for s in [-1, 1]:
		if D.faces_cam(rot, 0.0, s) != near:
			continue
		for a in [0.34, -0.2, -0.4]:
			var c := D.sp(o, rot, a, 0.21 * s, 3.4)
			D.road_wheel(cv, c, 2.9, 2.8, f, wreck)
			if near and not wreck and P.hn(int(a * 10), s, 23) > 0.3:
				cv.px(int(c.x), int(c.y) + 2, Color(D.MUD.r, D.MUD.g, D.MUD.b, 0.85))


static func _cab(cv, o: Vector2, rot: float, body: Color, wreck: bool) -> void:
	var ax := Vector2(cos(rot), sin(rot))
	var r: Dictionary = P.box(cv, o, D.w(rot, 0.36, 0.0, 4.5), 0.16, 0.22, 9.5, rot, body, 0.08, 13)
	if wreck:
		_scorch(cv, r.top)
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		var d: float = (sd.n as Vector2).dot(ax)
		if d > 0.7:  # front: windscreen, radiator grille, headlights, bumper
			var wq := P.sub(q, 0.08, 0.56, 0.92, 0.9)
			cv.poly(wq, GLASS if not wreck else CHAR)
			if not wreck:
				cv.line_v(wq[3] + Vector2(1, 1), wq[3].lerp(wq[2], 0.35) + Vector2(0, 1), GLASS_HI)
			cv.line_v((wq[0] + wq[1]) * 0.5, (wq[3] + wq[2]) * 0.5, P.mul(body, 0.8))
			D.grille(cv, PackedVector2Array([q[0].lerp(q[3], 0.12), q[1].lerp(q[3], 0.0).lerp(q[1].lerp(q[2], 0.12), 1.0),
				q[1].lerp(q[2], 0.4), q[0].lerp(q[3], 0.4)]), 0.3, 0.0, 0.7, 1.0, body, 3)
			for u in [0.1, 0.9]:
				var lp: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.28)
				cv.px(int(lp.x), int(lp.y), LAMP if not wreck else CHAR)
			cv.line_v(q[0] + Vector2(0, -1), q[1] + Vector2(0, -1), CHASSIS)
		elif absf(d) < 0.3:  # side: door window, door seam, mirror
			var sq := P.sub(q, 0.2, 0.56, 0.78, 0.88)
			cv.poly(sq, GLASS if not wreck else CHAR)
			if not wreck:
				cv.px(int(sq[3].x) + 1, int(sq[3].y) + 1, GLASS_HI)
			cv.line_v(q[0].lerp(q[1], 0.82), q[3].lerp(q[2], 0.82), P.mul(body, 0.72))
			D.mud(cv, q, 520 + int(q[0].x), 0.3)
		else:  # rear wall of the cab: small window
			cv.poly(P.sub(q, 0.3, 0.62, 0.7, 0.85), GLASS if not wreck else CHAR)
	D.contact_ao(cv, r)
	if not wreck:
		D.box_edges(cv, r, body, 131)
		cv.team = true
		cv.poly(P.sub(r.top, 0.12, 0.12, 0.88, 0.88), Color(0.76, 0.76, 0.76))
		cv.team = false
		var t: PackedVector2Array = r.top
		cv.px(int(t[2].x), int(t[2].y) - 1, LAMP)  # roof beacon
		D.antenna(cv, D.sp(o, rot, 0.26, -0.2, 14), 10, false)
	else:
		D.antenna(cv, D.sp(o, rot, 0.26, -0.2, 14), 10, true)


static func _exhaust(cv, o: Vector2, rot: float, wreck: bool) -> void:
	var r: Dictionary = P.box(cv, o, D.w(rot, 0.18, 0.19, 4.5), 0.025, 0.025, 12.0, rot, Color8(62, 62, 58) if not wreck else CHAR, 0.04, 17)
	var t: PackedVector2Array = r.top
	cv.px(int(t[0].x), int(t[0].y), D.DARK)


static func _bed(cv, o: Vector2, rot: float, body: Color, wreck: bool) -> void:
	var r: Dictionary = P.box(cv, o, D.w(rot, -0.2, 0.0, 4.5), 0.34, 0.23, 4.0, rot, body, 0.08, 19)
	cv.poly(P.sub(r.top, 0.04, 0.06, 0.96, 0.94), P.mul(body, 0.5) if not wreck else CHAR)  # open bed floor
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		cv.line_v(q[0].lerp(q[3], 0.45), q[1].lerp(q[2], 0.45), P.mul(body, 0.72))  # board seam
		for u in [0.33, 0.66]:
			cv.line_v(q[0].lerp(q[1], u), q[3].lerp(q[2], u), P.mul(body, 0.8))  # stakes
		if not wreck:
			cv.team = true
			cv.poly(P.sub(q, 0.04, 0.62, 0.96, 0.84), Color(0.64, 0.64, 0.64))
			cv.team = false
			D.mud(cv, q, 540 + int(q[0].x), 0.22)
	D.contact_ao(cv, r)
	if not wreck:
		D.box_edges(cv, r, body, 137)
	# cargo, back-to-front
	var items: Array = []
	for c in CARGO:
		var wp := D.w(rot, c[0], c[1])
		items.append([wp.x + wp.y, c])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		var c: Array = it[1]
		var col: Color = c[5] if not wreck else P.mix(CHAR, BURNT, P.hn(int(c[0] * 10), int(c[1] * 10), 5))
		var cr: Dictionary = P.box(cv, o, D.w(rot, c[0], c[1], 5.0), c[2], c[3], c[4], rot, col, 0.07, 23)
		for sd in cr.sides:
			var q: PackedVector2Array = sd.quad
			if c[6] == "crate":
				cv.line_v(q[0], q[2], P.mul(col, 0.72))                  # cross brace
				cv.line_v(q[0].lerp(q[3], 0.85), q[1].lerp(q[2], 0.85), P.mul(col, 0.7))
			elif c[6] == "ammo":
				cv.line_v(q[0].lerp(q[3], 0.6), q[1].lerp(q[2], 0.6), P.mul(col, 0.65))
				if not wreck:
					var sp: Vector2 = q[0].lerp(q[1], 0.5).lerp(q[3].lerp(q[2], 0.5), 0.3)
					cv.px(int(sp.x), int(sp.y), Color8(190, 170, 90))  # stencil mark
			else:
				cv.line_v(q[0].lerp(q[1], 0.5), q[3].lerp(q[2], 0.5), P.mul(col, 0.7))
		if not wreck:
			D.box_edges(cv, cr, col, 149, 0.28)
		else:
			_scorch(cv, cr.top)


static func _scorch(cv, q: PackedVector2Array) -> void:
	cv.poly(q, BURNT, func(x: int, y: int, c: Color) -> Color:
		var h := P.hn(x, y, 919)
		if h > 0.82:
			return Color8(104, 66, 44)
		return P.mul(c, 0.55 + h * 0.4))
