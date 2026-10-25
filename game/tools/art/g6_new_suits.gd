extends RefCounted
## G6 exo suits (agent ART-G6b, CONTRACTS_G6 s3.2 / s14): Human A AMP-style walkers, about 2.5x a soldier's
## height (G5 figure kit soldier ~18 px, suit ~45 px), built from the same vehicle box kit as a_exo_trooper:
## open glass cockpit in the chest with the pilot, hydraulic walking legs, power pack with a team top.
##   a_exo_rifle    big drum-fed rifle in the right hand
##   a_exo_missile  6-tube missile pod on the right shoulder + short autocannon
##   a_exo_aa       twin AA cannon raised on the right arm + radar dish on the pack
## Frames idle / walk_a / walk_b / fire (+ wreck). veh_sheet draw signature + kind bound last.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const VH = preload("res://tools/art/vehicles.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const U = preload("res://tools/art/units.gd")

const OUTL := Color(0.09, 0.09, 0.07, 1)
const HULL := Color8(126, 130, 100)
const DARK := Color8(74, 76, 70)
const GLASS := Color8(70, 104, 112)
const GLASS_HI := Color8(176, 220, 228)
const PISTON := Color8(150, 150, 140)
const KINDS := {"a_exo_rifle": "rifle", "a_exo_missile": "missile", "a_exo_aa": "aa"}
const FR := ["idle", "walk_a", "walk_b", "fire"]


static func build(out: Dictionary) -> void:
	for id in KINDS:
		SL.veh_sheet(out, id, {"fw": 64, "fh": 68, "pivot": [32, 56]}, suit.bind(String(KINDS[id])), FR)


static func suit(cv, rot: float, f: int, wreck: bool, o: Vector2, kind: String) -> void:
	if wreck:
		_wreck(cv, rot, o, kind)
		return
	var stride := 0.0
	var bob := 0.0
	if f == 1:
		stride = 0.07
		bob = -1.5
	elif f == 2:
		stride = -0.07
		bob = -1.5
	cv.ellipse(o.x + 3, o.y + 1, 15.0, 5.5, Color.BLACK, true)
	cv.flush_shadow()
	var near_s := 1.0 if D.faces_cam(rot, 0.0, 1.0) else -1.0
	var fnear := D.faces_cam(rot, 1.0, 0.0)
	_leg(cv, o, rot, -near_s, stride)
	_arm(cv, o, rot, -near_s, bob, kind)
	if fnear:
		_pack(cv, o, rot, bob, kind)
	_leg(cv, o, rot, near_s, stride)
	P.box(cv, o, D.w(rot, 0.0, 0.0, 21 + bob), 0.07, 0.12, 5.0, rot, DARK, 0.05, 801)  # hip
	var t: Dictionary = P.box(cv, o, D.w(rot, 0.01, 0.0, 26 + bob), 0.12, 0.14, 14.0, rot, HULL, 0.08, 803)
	D.box_edges(cv, t, HULL, 804)
	var ax := Vector2(cos(rot), sin(rot))
	for sd in t.sides:
		var dn := (sd.n as Vector2).dot(ax)
		if dn > 0.5:
			_canopy(cv, sd.quad)
		elif dn < -0.5:
			cv.poly(P.sub(sd.quad, 0.2, 0.25, 0.8, 0.7), P.mul(HULL, 0.82))
		else:
			for i in 3:
				var a: PackedVector2Array = P.sub(sd.quad, 0.2 + i * 0.25, 0.45, 0.24 + i * 0.25, 0.85)
				cv.line_v(a[0], a[3], P.mul(HULL, 0.72))
	cv.team = true
	cv.poly(P.sub(t.top, 0.08, 0.15, 0.42, 0.85), Color(0.66, 0.66, 0.66))
	cv.team = false
	if not fnear:
		_pack(cv, o, rot, bob, kind)
	if kind == "missile":
		_pod(cv, o, rot, bob, f)
	_arm(cv, o, rot, near_s, bob, kind)
	cv.outline(OUTL)
	if f == 3:
		_fire(cv, o, rot, bob, kind)


static func _leg(cv, o: Vector2, rot: float, s: float, stride: float) -> void:
	var fw := stride * s
	var lift := 2.0 if fw > 0.0 else 0.0
	var sx := 0.11 * s
	P.box(cv, o, D.w(rot, fw + 0.035, sx, lift), 0.08, 0.05, 3.0, rot, DARK, 0.05, 811)  # foot
	P.box(cv, o, D.w(rot, fw - 0.06, sx, lift), 0.025, 0.04, 2.0, rot, DARK, 0.05, 812)  # heel spur
	var sh: Dictionary = P.box(cv, o, D.w(rot, fw, sx, 3 + lift), 0.042, 0.04, 10.0, rot, P.mul(HULL, 0.9), 0.06, 813)
	D.box_edges(cv, sh, HULL, 816)
	cv.line_v(D.sp(o, rot, fw - 0.05, sx, 4 + lift), D.sp(o, rot, fw * 0.5 - 0.05, sx, 16), PISTON)  # hydraulic ram
	P.box(cv, o, D.w(rot, fw * 0.7 + 0.03, sx, 11 + lift * 0.5), 0.035, 0.045, 4.0, rot, DARK, 0.05, 814)  # knee
	P.box(cv, o, D.w(rot, fw * 0.35, sx, 14 + lift * 0.3), 0.055, 0.05, 8.0, rot, HULL, 0.06, 815)  # thigh


static func _pack(cv, o: Vector2, rot: float, bob: float, kind: String) -> void:
	var r: Dictionary = P.box(cv, o, D.w(rot, -0.15, 0.0, 26 + bob), 0.04, 0.1, 13.0, rot, DARK, 0.06, 821)
	cv.team = true
	cv.poly(P.sub(r.top, 0.1, 0.15, 0.9, 0.85), Color(0.62, 0.62, 0.62))
	cv.team = false
	for sd in r.sides:
		if (sd.n as Vector2).dot(Vector2(cos(rot), sin(rot))) < -0.5:
			for i in 4:
				var a: Vector2 = (sd.quad[0] as Vector2).lerp(sd.quad[1], 0.2 + i * 0.2)
				cv.line_v(a + Vector2(0, -2), a + Vector2(0, -9), P.mul(DARK, 0.7))  # heat-sink fins
	for s in [-0.05, 0.05]:  # exhaust stubs
		var e := D.sp(o, rot, -0.17, s, 39 + bob)
		cv.rect(int(e.x), int(e.y) - 2, 2, 3, Color8(40, 40, 38))
	if kind == "aa":  # fire-control radar on the pack
		var dc := D.sp(o, rot, -0.15, 0.0, 44 + bob)
		cv.line_v(dc + Vector2(0, 4), dc, Color8(70, 72, 70))
		cv.ellipse(dc.x, dc.y - 2, 4.5, 2.6, Color8(176, 180, 172))
		cv.ellipse(dc.x + 1, dc.y - 2, 3.0, 1.6, Color8(140, 144, 138))


## s = +1 right arm (weapon), s = -1 left arm.
static func _arm(cv, o: Vector2, rot: float, s: float, bob: float, kind: String) -> void:
	var sx := 0.23 * s
	P.box(cv, o, D.w(rot, 0.0, sx, 27 + bob), 0.04, 0.04, 8.0, rot, DARK, 0.05, 831)  # upper arm
	var fa: Dictionary = P.box(cv, o, D.w(rot, 0.08, sx, 23.5 + bob), 0.085, 0.042, 4.5, rot, HULL, 0.05, 833)
	D.box_edges(cv, fa, HULL, 832)
	P.box(cv, o, D.w(rot, 0.17, sx, 23.5 + bob), 0.025, 0.035, 3.0, rot, DARK, 0.05, 834)  # fist
	if s > 0.0:
		match kind:
			"rifle":
				var g: Dictionary = P.box(cv, o, D.w(rot, 0.2, 0.24, 22 + bob), 0.12, 0.03, 5.0, rot, VH.GUNMETAL, 0.05, 835)
				D.box_edges(cv, g, VH.GUNMETAL, 836)
				P.box(cv, o, D.w(rot, 0.14, 0.24, 18.5 + bob), 0.035, 0.035, 3.5, rot, P.mul(VH.GUNMETAL, 0.8), 0.05, 838)
				for t in [0, 1]:
					cv.line_v(D.sp(o, rot, 0.32, 0.24, 24.5 + bob + t), D.sp(o, rot, 0.49, 0.24, 24.5 + bob + t), Color8(70, 72, 70) if t == 0 else Color8(96, 98, 96))
			"missile":
				P.box(cv, o, D.w(rot, 0.18, 0.24, 22 + bob), 0.07, 0.025, 4.0, rot, VH.GUNMETAL, 0.05, 835)
				cv.line_v(D.sp(o, rot, 0.25, 0.24, 24 + bob), D.sp(o, rot, 0.37, 0.24, 24 + bob), Color8(76, 78, 76))
			"aa":
				var g: Dictionary = P.box(cv, o, D.w(rot, 0.17, 0.25, 23 + bob), 0.09, 0.045, 5.0, rot, VH.GUNMETAL, 0.05, 835)
				D.box_edges(cv, g, VH.GUNMETAL, 836)
				for dy in [-0.016, 0.016]:
					cv.line_v(D.sp(o, rot, 0.25, 0.25 + dy, 26 + bob), D.sp(o, rot, 0.42, 0.25 + dy, 37 + bob), Color8(80, 82, 80))
	var pad: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.21 * s, 34 + bob), 0.075, 0.07, 6.0, rot, HULL, 0.06, 837)
	cv.team = true
	cv.poly(P.sub(pad.top, 0.1, 0.1, 0.9, 0.9), Color(0.68, 0.68, 0.68))
	cv.team = false


static func _pod(cv, o: Vector2, rot: float, bob: float, f: int) -> void:
	var pd: Dictionary = P.box(cv, o, D.w(rot, -0.01, 0.2, 40 + bob), 0.09, 0.07, 7.0, rot, P.mul(HULL, 0.95), 0.06, 841)
	D.box_edges(cv, pd, HULL, 842)
	for sd in pd.sides:
		if (sd.n as Vector2).dot(Vector2(cos(rot), sin(rot))) > 0.5:
			for i in 3:
				for j in 2:
					var c: Vector2 = P.sub(sd.quad, 0.2 + i * 0.3, 0.25 + j * 0.4, 0.2 + i * 0.3, 0.25 + j * 0.4)[0]
					cv.px(int(c.x), int(c.y), Color8(26, 26, 24))
					if not (f == 3 and i == 0 and j == 1):
						cv.px(int(c.x), int(c.y), Color8(196, 60, 46))
	cv.team = true
	cv.poly(P.sub(pd.top, 0.15, 0.2, 0.5, 0.8), Color(0.7, 0.7, 0.7))
	cv.team = false


static func _canopy(cv, q: PackedVector2Array) -> void:
	var g := P.sub(q, 0.1, 0.1, 0.9, 0.72)
	cv.poly(g, GLASS)
	var hd: Vector2 = P.sub(q, 0.5, 0.42, 0.5, 0.42)[0]
	cv.rect(int(hd.x) - 1, int(hd.y), 3, 3, U.SKIN)  # pilot
	cv.rect(int(hd.x) - 1, int(hd.y) - 1, 3, 1, U.UNIFORM)
	cv.rect(int(hd.x) - 2, int(hd.y) + 3, 5, 2, U.UNIFORM)
	cv.line_v(g[0], g[3], P.mul(HULL, 0.7))
	cv.line_v(g[1], g[2], P.mul(HULL, 0.7))
	cv.line_v(g[0].lerp(g[1], 0.2), g[3].lerp(g[2], 0.45), Color(GLASS_HI.r, GLASS_HI.g, GLASS_HI.b, 0.7))


static func _fire(cv, o: Vector2, rot: float, bob: float, kind: String) -> void:
	match kind:
		"rifle":
			L.flash(cv, D.sp(o, rot, 0.52, 0.24, 25 + bob), 1.4)
			var ej := D.sp(o, rot, 0.17, 0.29, 23 + bob)
			for i in 3:
				cv.px(int(ej.x) + i, int(ej.y) + 1 + i, Color8(214, 176, 80))
		"missile":
			var p0 := D.sp(o, rot, 0.09, 0.2, 44 + bob)
			var dir := D.sp(o, rot, 1.0, 0.0, 0) - D.sp(o, rot, 0.0, 0.0, 0)
			dir = dir.normalized() if dir.length() > 0.1 else Vector2(1, 0)
			var m0 := p0 + dir * 7.0 + Vector2(0, -3)
			var m1 := m0 + dir * 5.0 + Vector2(0, -1)
			L.puff(cv, p0 + dir * 2.0, 2.4, 0.5)
			L.puff(cv, p0 + dir * 4.5 + Vector2(0, -2), 1.8, 0.4)
			cv.line_v(m0, m1, Color8(222, 222, 212))
			cv.px(int(m1.x), int(m1.y), Color8(200, 60, 46))
			cv.px(int(m0.x), int(m0.y), Color8(255, 200, 90))
		"aa":
			for dy in [-0.016, 0.016]:
				var tip := D.sp(o, rot, 0.44, 0.25 + dy, 38 + bob)
				L.flash(cv, tip, 0.9)
				var up := D.sp(o, rot, 0.62, 0.25 + dy, 50 + bob)
				cv.line_v(tip + (up - tip) * 0.4, up, Color(1.0, 0.86, 0.4, 0.6))


static func _wreck(cv, rot: float, o: Vector2, kind: String) -> void:
	var b: Color = VH.BURNT
	cv.ellipse(o.x + 2, o.y + 1, 16.0, 5.0, Color8(40, 36, 32))
	P.box(cv, o, D.w(rot, -0.25, 0.08, 0), 0.16, 0.045, 4.0, rot + 0.15, P.mul(b, 0.85), 0.06, 851)
	P.box(cv, o, D.w(rot, -0.22, -0.12, 0), 0.15, 0.045, 4.0, rot - 0.3, P.mul(b, 0.85), 0.06, 852)
	P.box(cv, o, D.w(rot, -0.16, 0.0, 0), 0.05, 0.1, 8.0, rot, P.mul(b, 0.9), 0.06, 854)
	var t: Dictionary = P.box(cv, o, D.w(rot, 0.02, 0.0, 0), 0.14, 0.13, 9.0, rot, b, 0.08, 853)
	VH._scorch(cv, t)
	for sd in t.sides:
		if (sd.n as Vector2).dot(Vector2(cos(rot), sin(rot))) > 0.5:
			cv.poly(P.sub(sd.quad, 0.15, 0.15, 0.85, 0.7), Color8(30, 32, 32))
			var gl: Vector2 = P.sub(sd.quad, 0.3, 0.3, 0.3, 0.3)[0]
			cv.px(int(gl.x), int(gl.y), GLASS_HI)
	P.box(cv, o, D.w(rot, 0.22, 0.24, 0), 0.16, 0.03, 4.0, rot + 0.2, VH.GUNMETAL, 0.05, 855)
	if kind == "missile":
		P.box(cv, o, D.w(rot, 0.1, -0.24, 0), 0.08, 0.07, 6.0, rot - 0.4, P.mul(b, 1.1), 0.06, 856)
	cv.outline(OUTL)
	V.soot(cv, D.sp(o, rot, 0, 0, 10), 7.0, 857)
