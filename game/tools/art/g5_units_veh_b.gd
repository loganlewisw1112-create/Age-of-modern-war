extends RefCounted
## G5 Human B vehicles (agent ART-U5), riveted khaki-rust look of faction_b_veh / g4_units_b:
##   b_armored_car      high-sided riveted 4x4, slab mudguards, round-ish turret with a heavy MG behind a
##                      shield, spare wheel on the flank. idle / move / fire.
##   b_field_ambulance  bonneted truck with a canvas tilt marked with red crosses, rust streaks.
##                      idle / move / fire (beacon lit) / unload (tailgate down, stretcher out).
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const VA = preload("res://tools/art/g5_units_veh_a.gd")

const OUTL := Color(0.08, 0.07, 0.06, 1)
const SPEC := {
	"b_armored_car": {"fw": 62, "fh": 50, "pivot": [31, 33]},
	"b_field_ambulance": {"fw": 66, "fh": 56, "pivot": [33, 37]},
}
const CANVAS := Color8(150, 140, 104)


static func build(out: Dictionary) -> void:
	SL.veh_sheet(out, "b_armored_car", SPEC.b_armored_car, armored_car, ["idle", "move", "fire"])
	SL.veh_sheet(out, "b_field_ambulance", SPEC.b_field_ambulance, field_ambulance, ["idle", "move", "fire", "unload"])


static func _wheels(cv, o: Vector2, rot: float, s: float, f: int, wreck: bool, xs: Array, r: float) -> void:
	for i in xs.size():
		if wreck and i == 0 and s > 0:
			continue
		D.road_wheel(cv, D.sp(o, rot, xs[i], 0.2 * s, 4.0), r, r + 0.3, f, wreck)


# ---------------------------------------------------------------- b_armored_car
static func armored_car(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var col: Color = V.BURNT if wreck else V.HULL
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 3), 0.44, 0.2, 14.0, rot)
	cv.flush_shadow()
	var ax := Vector2(cos(rot), sin(rot))
	for s: float in [-1.0, 1.0]:
		if not D.faces_cam(rot, 0.0, s):
			_wheels(cv, o, rot, s, f, wreck, [-0.26, 0.26], 3.8)
	var lo: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 5), 0.42, 0.16, 8.0, rot, P.mul(col, 0.92), 0.1, 851)
	var bon: Dictionary = P.box(cv, o, D.w(rot, 0.3, 0.0, 13), 0.12, 0.13, 2.0, rot, col, 0.1, 852)
	var tur: Dictionary = P.box(cv, o, D.w(rot, -0.08, 0.0, 13), 0.14, 0.12, 6.0, rot, col, 0.1, 853)
	if wreck:
		for r in [lo, bon, tur]:
			V.scorch(cv, (r.top as PackedVector2Array))
	else:
		for sd in lo.sides:
			var q: PackedVector2Array = sd.quad
			var dd: float = (sd.n as Vector2).dot(ax)
			V.rivets(cv, q, 0.2, 7, col)
			V.rivets(cv, q, 0.85, 7, col)
			if absf(dd) < 0.3:
				cv.team = true
				cv.poly(P.sub(q, 0.55, 0.35, 0.95, 0.7), Color(0.62, 0.62, 0.62))
				cv.team = false
				var wc: Vector2 = P.sub(q, 0.3, 0.5, 0.3, 0.5)[0]  # spare wheel
				cv.ellipse(wc.x, wc.y, 2.4, 2.6, D.RUBBER)
				cv.px(int(wc.x), int(wc.y), D.RIM)
				V.patch(cv, q, 0.02, 0.1, 0.16, 0.9, V.PRIMER, 854)
			elif dd > 0.7:
				cv.poly(P.sub(q, 0.3, 0.1, 0.7, 0.35), Color8(28, 26, 24))  # vision slit / grille
		V.streaks(cv, lo.top, 855)
		for sd in tur.sides:
			V.rivets(cv, sd.quad, 0.5, 4, col)
			if absf((sd.n as Vector2).dot(ax)) < 0.3:
				cv.team = true
				cv.poly(P.sub(sd.quad, 0.2, 0.3, 0.8, 0.7), Color(0.62, 0.62, 0.62))
				cv.team = false
	var gun := V.GUNMETAL if not wreck else V.BURNT
	var front := D.faces_cam(rot, 1.0, 0.0)
	var tip := D.sp(o, rot, 0.5 if not wreck else 0.25, 0.0, 20.0)
	var gb := D.sp(o, rot, 0.0, 0.0, 20)
	if not front:
		_mg(cv, gb, tip, gun)
	if not wreck:  # gun shield
		P.box(cv, o, D.w(rot, 0.08, 0.0, 17), 0.015, 0.08, 5.0, rot, P.mul(col, 0.85), 0.06, 856)
	if front:
		_mg(cv, gb, tip, gun)
	for s: float in [-1.0, 1.0]:
		if D.faces_cam(rot, 0.0, s):
			_wheels(cv, o, rot, s, f, wreck, [-0.26, 0.26], 3.8)
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, 0.0, 0.0, 14), 6.0, 857)
	elif f == 2:
		L.flash(cv, tip, 1.0)
		L.puff(cv, tip + Vector2(2, -2), 1.8, 0.4)


## Heavy MG: thick receiver + barrel with a lit top edge so it reads against the khaki hull.
static func _mg(cv, a: Vector2, b: Vector2, gun: Color) -> void:
	cv.line_v(a, b, gun)
	cv.line_v(a + Vector2(0, 1), a.lerp(b, 0.55) + Vector2(0, 1), P.mul(gun, 0.8))
	cv.line_v(a + Vector2(0, -1), a.lerp(b, 0.4) + Vector2(0, -1), P.mul(gun, 1.6))


# ---------------------------------------------------------------- b_field_ambulance
static func field_ambulance(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var col: Color = V.BURNT if wreck else V.HULL
	var tilt: Color = V.BURNT if wreck else CANVAS
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 3), 0.5, 0.2, 16.0, rot)
	cv.flush_shadow()
	var ax := Vector2(cos(rot), sin(rot))
	var gate := f == 3 and not wreck
	var rear_cam := D.faces_cam(rot, -1.0, 0.0)
	for s: float in [-1.0, 1.0]:
		if not D.faces_cam(rot, 0.0, s):
			_wheels(cv, o, rot, s, f, wreck, [-0.3, -0.12, 0.32], 3.4)
	if gate and not rear_cam:
		_tailgate(cv, o, rot)
	var chassis: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 5), 0.48, 0.15, 3.0, rot, P.mul(col, 0.7), 0.06, 861)
	var bon: Dictionary = P.box(cv, o, D.w(rot, 0.38, 0.0, 8), 0.1, 0.12, 5.0, rot, col, 0.1, 862)
	var cab: Dictionary = P.box(cv, o, D.w(rot, 0.2, 0.0, 8), 0.09, 0.17, 9.0, rot, col, 0.1, 863)
	var bed: Dictionary = P.box(cv, o, D.w(rot, -0.17, 0.0, 8), 0.29, 0.19, 12.0, rot, tilt, 0.05, 864)
	if wreck:
		for r in [chassis, bon, cab, bed]:
			V.scorch(cv, (r.top as PackedVector2Array))
	else:
		for sd in cab.sides:
			var dd: float = (sd.n as Vector2).dot(ax)
			if absf(dd) < 0.3:
				cv.poly(P.sub(sd.quad, 0.2, 0.08, 0.8, 0.4), Color8(40, 44, 42))  # side window
				cv.team = true
				cv.poly(P.sub(sd.quad, 0.15, 0.55, 0.85, 0.85), Color(0.62, 0.62, 0.62))
				cv.team = false
			elif dd > 0.7:
				cv.poly(P.sub(sd.quad, 0.12, 0.08, 0.88, 0.4), D.VISION)
		for sd in bon.sides:
			if (sd.n as Vector2).dot(ax) > 0.7:
				cv.poly(P.sub(sd.quad, 0.2, 0.2, 0.8, 0.9), Color8(36, 34, 30))  # radiator
		for sd in bed.sides:
			var dd: float = (sd.n as Vector2).dot(ax)
			for v in [0.33, 0.66]:  # tilt hoops
				cv.line_v(P.sub(sd.quad, 0.0, v, 0.0, v)[0], P.sub(sd.quad, 1.0, v, 1.0, v)[0], P.mul(tilt, 0.85))
			if absf(dd) < 0.3:
				VA.cross(cv, sd.quad, 0.3, 0.1, 0.7, 0.85)
			elif dd < -0.7 and gate:
				cv.poly(P.sub(sd.quad, 0.1, 0.0, 0.9, 1.0), Color8(32, 30, 26))
		VA.cross(cv, bed.top, 0.3, 0.25, 0.7, 0.75)
		V.streaks(cv, cab.top, 865)
	if gate and rear_cam:
		_tailgate(cv, o, rot)
	for s: float in [-1.0, 1.0]:
		if D.faces_cam(rot, 0.0, s):
			_wheels(cv, o, rot, s, f, wreck, [-0.3, -0.12, 0.32], 3.4)
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, -0.1, 0.0, 18), 7.0, 866)
		return
	var b := D.sp(o, rot, 0.22, 0.0, 18)  # single rotating lamp on the cab roof
	cv.rect(int(b.x), int(b.y) - 1, 2, 2, Color8(240, 160, 40) if f == 2 else Color8(120, 90, 50))
	if f == 2:
		cv.ellipse(b.x + 1, b.y, 3.0, 2.0, Color(1.0, 0.65, 0.2, 0.3))


static func _tailgate(cv, o: Vector2, rot: float) -> void:
	var q := PackedVector2Array([D.sp(o, rot, -0.46, -0.17, 8), D.sp(o, rot, -0.46, 0.17, 8),
		D.sp(o, rot, -0.6, 0.17, 4), D.sp(o, rot, -0.6, -0.17, 4)])
	cv.poly(q, P.mul(V.HULL, 0.85))
	V.rivets(cv, q, 0.5, 4, V.HULL)
	var a := D.sp(o, rot, -0.62, 0.0, 3)
	var bb := D.sp(o, rot, -0.92, 0.0, 0)
	var pr := Vector2(-sin(rot) - cos(rot), (cos(rot) - sin(rot)) * 0.5).normalized() * 2.0
	cv.poly(PackedVector2Array([a - pr, a + pr, bb + pr, bb - pr]), Color8(196, 188, 150))
	var m := a.lerp(bb, 0.5)
	cv.rect(int(m.x) - 1, int(m.y) - 1, 3, 2, Color8(92, 86, 58))
	cv.px(int(m.x), int(m.y) - 1, VA.RED)
