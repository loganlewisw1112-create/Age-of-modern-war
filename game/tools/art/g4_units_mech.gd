extends RefCounted
## G4b Human B b_scrap_mech (agent ART-U): biped walker welded from scrap: riveted khaki body with
## mismatched primer and rust plates, heavy front plate with a vision slit, arm cannon on the right,
## twin exhaust stacks. Frames idle, walk_a, walk_b, fire, move (move = mid-stride so a renderer that
## looks for "move" still animates). Section vehicles (move_class vehicle) with legged: true.
## Wreck: collapsed on its knees, scorched.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const L = preload("res://tools/art/g4_units_lib.gd")

const SPEC := {"fw": 64, "fh": 64, "pivot": [32, 50]}
const FRAMES := ["idle", "walk_a", "walk_b", "fire", "move"]
const OUTL := Color(0.08, 0.07, 0.06, 1)


static func build(out: Dictionary) -> void:
	L.sheet(out, "b_scrap_mech", SPEC, mech, FRAMES, "vehicles", true, {"legged": true})


static func mech(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	if wreck:
		_collapsed(cv, rot, o)
		return
	var stride := 0.0
	match f:
		1:
			stride = 0.14
		2:
			stride = -0.14
		4:
			stride = 0.07
	var bz := 19.0 - (1.0 if f == 1 or f == 2 else 0.0)
	cv.ellipse(o.x + 3, o.y + 1, 15.0, 6.0, Color.BLACK, true)
	cv.flush_shadow()
	for s: float in [-1.0, 1.0]:
		if not D.faces_cam(rot, 0.0, s):
			_leg(cv, o, rot, s, stride * s, bz)
	var arm_near := D.faces_cam(rot, 0.0, 1.0)
	if not arm_near:
		_arm(cv, o, rot, bz)
	var front := D.faces_cam(rot, 1.0, 0.0)
	if not front:
		_plate(cv, o, rot, bz)
	_body(cv, o, rot, bz, f)
	if front:
		_plate(cv, o, rot, bz)
	if arm_near:
		_arm(cv, o, rot, bz)
	for s: float in [-1.0, 1.0]:
		if D.faces_cam(rot, 0.0, s):
			_leg(cv, o, rot, s, stride * s, bz)
	cv.outline(OUTL)
	for s: float in [-1.0, 1.0]:  # exhaust soot wisps
		var ex := D.sp(o, rot, -0.15, 0.07 * s, bz + 17)
		L.puff(cv, ex + Vector2(1, -2), 1.6 + (0.6 if f != 0 else 0.0), 0.3, Color(0.3, 0.29, 0.27))
	if f == 3:
		var tip := D.sp(o, rot, 0.34, 0.25, bz + 6)
		L.flash(cv, tip, 1.4)
		L.puff(cv, tip + Vector2(2, -3), 3.0, 0.45)


static func _leg(cv, o: Vector2, rot: float, s: float, fw: float, bz: float) -> void:
	var hip := D.sp(o, rot, 0.0, 0.13 * s, bz + 2)
	var knee := D.sp(o, rot, fw * 0.5 + 0.07, 0.15 * s, bz * 0.5)
	var foot := D.sp(o, rot, fw, 0.15 * s, 1.5)
	var dark := P.mul(V.GUNMETAL, 0.8)
	for dx in [-1, 0, 1]:
		cv.line_v(hip + Vector2(dx, 0), knee + Vector2(dx, 0), V.GUNMETAL if dx < 1 else dark)
		cv.line_v(knee + Vector2(dx, 0), foot + Vector2(dx, -1), P.mul(V.HULL, 0.9) if dx < 1 else P.mul(V.HULL, 0.7))
	cv.ellipse(knee.x, knee.y, 2.4, 2.0, V.PRIMER)  # knee joint
	cv.px(int(knee.x) - 1, int(knee.y) - 1, P.mul(V.PRIMER, 1.3))
	cv.line_v(knee + Vector2(-2, 2), foot + Vector2(-2, -3), Color8(70, 66, 58))  # hydraulic ram
	P.box(cv, o, D.w(rot, fw + 0.02, 0.15 * s, 0), 0.08, 0.055, 2.5, rot, V.TRACK, 0.06, 771)


static func _body(cv, o: Vector2, rot: float, bz: float, f: int) -> void:
	var r: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, bz), 0.2, 0.17, 12.0, rot, V.HULL, 0.1, 772)
	var ax := Vector2(cos(rot), sin(rot))
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		if absf((sd.n as Vector2).dot(ax)) < 0.3:
			cv.team = true
			cv.poly(P.sub(q, 0.1, 0.52, 0.9, 0.78), Color(0.62, 0.62, 0.62))
			cv.team = false
			V.patch(cv, q, 0.08, 0.08, 0.42, 0.4, V.PRIMER, 773)
			V.patch(cv, q, 0.6, 0.1, 0.9, 0.42, V.RUST, 774)
			V.rivets(cv, q, 0.92, 6, V.HULL)
		V.streaks(cv, q, 775)
	D.box_edges(cv, r, V.HULL, 776)
	cv.team = true  # team stripe across the top deck (reads from every facing)
	cv.poly(P.sub(r.top, 0.62, 0.08, 0.86, 0.92), Color(0.62, 0.62, 0.62))
	cv.team = false
	D.hatch(cv, r.top, 0.2, 0.25, 0.55, 0.75, V.HULL)
	for s: float in [-1.0, 1.0]:  # exhaust stacks
		var a := D.sp(o, rot, -0.15, 0.07 * s, bz + 12)
		cv.line_v(a, a + Vector2(0, -5), Color8(52, 48, 42))
		cv.line_v(a + Vector2(1, 0), a + Vector2(1, -5), Color8(40, 36, 32))
		cv.px(int(a.x), int(a.y) - 5, Color8(30, 28, 26) if f == 0 else Color8(200, 110, 50))


## Thick welded front plate with a vision slit.
static func _plate(cv, o: Vector2, rot: float, bz: float) -> void:
	var r: Dictionary = P.box(cv, o, D.w(rot, 0.22, 0.0, bz - 2), 0.035, 0.2, 15.0, rot, V.PRIMER, 0.1, 777)
	var ax := Vector2(cos(rot), sin(rot))
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		if (sd.n as Vector2).dot(ax) > 0.7:
			cv.poly(P.sub(q, 0.2, 0.74, 0.8, 0.82), Color8(20, 18, 16))
			cv.px(int(P.sub(q, 0.3, 0.78, 0.3, 0.78)[0].x), int(P.sub(q, 0.3, 0.78, 0.3, 0.78)[0].y), Color8(220, 150, 60))
			V.rivets(cv, q, 0.95, 5, V.PRIMER)
			V.rivets(cv, q, 0.08, 5, V.PRIMER)
			V.patch(cv, q, 0.55, 0.15, 0.85, 0.5, V.RUST, 778)


## Right-arm cannon: shoulder block + long barrel with a muzzle brake.
static func _arm(cv, o: Vector2, rot: float, bz: float) -> void:
	P.box(cv, o, D.w(rot, 0.0, 0.22, bz + 4), 0.07, 0.05, 6.0, rot, P.mul(V.HULL, 0.9), 0.08, 779)
	P.box(cv, o, D.w(rot, 0.14, 0.25, bz + 5), 0.16, 0.025, 2.5, rot, V.GUNMETAL, 0.05, 780)
	P.box(cv, o, D.w(rot, 0.31, 0.25, bz + 4.5), 0.03, 0.04, 3.5, rot, P.mul(V.GUNMETAL, 1.2), 0.05, 781)


static func _collapsed(cv, rot: float, o: Vector2) -> void:
	var wr := rot + 0.3
	cv.ellipse(o.x + 2, o.y + 1, 15.0, 6.0, Color.BLACK, true)
	cv.flush_shadow()
	for s: float in [-1.0, 1.0]:
		var hip := D.sp(o, wr, -0.05, 0.14 * s, 4)
		var foot := D.sp(o, wr, -0.42, 0.3 * s, 0.5)
		cv.line_v(hip, foot, V.BURNT)
		cv.line_v(hip + Vector2(0, 1), foot + Vector2(0, 1), P.mul(V.BURNT, 0.7))
	var r: Dictionary = P.box(cv, o, D.w(wr, 0.05, 0.0, 2), 0.2, 0.17, 10.0, wr, V.BURNT, 0.12, 782)
	for sd in r.sides:
		V.scorch(cv, sd.quad)
	P.box(cv, o, D.w(wr, 0.28, 0.0, 0), 0.03, 0.2, 9.0, wr, P.mul(V.BURNT, 1.1), 0.1, 783)
	P.box(cv, o, D.w(wr + 0.5, 0.2, 0.3, 1), 0.16, 0.025, 2.5, wr + 0.5, V.SOOT, 0.05, 784)
	cv.outline(OUTL)
	V.soot(cv, D.sp(o, wr, 0.0, 0.0, 14), 6.0, 785)
