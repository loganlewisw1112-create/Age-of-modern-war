extends RefCounted
## G4b Human A vehicle (agent ART-U): a_apc, an 8x8 wheeled APC in vehicles.gd olive: stepped hull,
## remote weapon station with an LMG, smoke dischargers, whip antenna, team bands on the long sides.
## Frames idle, move, fire, unload (rear ramp down, troop door open). 1-column wreck sheet.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const VH = preload("res://tools/art/vehicles.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const L = preload("res://tools/art/g4_units_lib.gd")

const SPEC := {"fw": 64, "fh": 48, "pivot": [32, 31]}
const FRAMES := ["idle", "move", "fire", "unload"]
const OUTL := Color(0.09, 0.09, 0.07, 1)
const WHEELS := [-0.34, -0.12, 0.12, 0.34]


static func build(out: Dictionary) -> void:
	L.sheet(out, "a_apc", SPEC, apc, FRAMES, "vehicles", true)


static func apc(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = VH.BURNT if wreck else VH.HULL
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 3), 0.5, 0.21, 10.0, rot)
	cv.flush_shadow()
	var ramp := f == 3 and not wreck
	var rear_cam := D.faces_cam(rot, -1.0, 0.0)
	for s: float in [-1.0, 1.0]:
		if not D.faces_cam(rot, 0.0, s):
			_wheels(cv, o, rot, s, f, wreck)
	if ramp and not rear_cam:
		_ramp(cv, o, rot)
	var lo: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 4), 0.48, 0.19, 6.0, rot, P.mul(hull, 0.92), 0.08, 701)
	var up: Dictionary = P.box(cv, o, D.w(rot, -0.06, 0.0, 10), 0.4, 0.17, 4.0, rot, hull, 0.08, 702)
	var ax := Vector2(cos(rot), sin(rot))
	for bi in 2:
		var r: Dictionary = lo if bi == 0 else up
		if wreck:
			VH._scorch(cv, r)
			continue
		for sd in r.sides:
			var q: PackedVector2Array = sd.quad
			var dd: float = (sd.n as Vector2).dot(ax)
			if absf(dd) < 0.3:
				if bi == 1:
					cv.team = true
					cv.poly(P.sub(q, 0.08, 0.2, 0.92, 0.72), Color(0.62, 0.62, 0.62))
					cv.team = false
				else:
					D.mud(cv, q, 703)
			elif dd > 0.7 and bi == 0:
				for u in [0.18, 0.82]:  # headlights
					var hp: Vector2 = P.sub(q, u, 0.7, u, 0.7)[0]
					cv.px(int(hp.x), int(hp.y), Color8(236, 226, 172))
			elif dd < -0.7 and bi == 0 and ramp:
				cv.poly(P.sub(q, 0.22, 0.1, 0.78, 0.98), Color8(26, 26, 24))  # open troop door
	if not wreck:
		D.box_edges(cv, up, hull, 704)
		D.hatch(cv, up.top, 0.08, 0.25, 0.3, 0.75, hull)
		D.hatch(cv, up.top, 0.36, 0.55, 0.5, 0.9, hull)
		cv.team = true  # air-recognition panel on the roof: team colour from every facing
		cv.poly(P.sub(up.top, 0.62, 0.12, 0.9, 0.42), Color(0.62, 0.62, 0.62))
		cv.team = false
	if ramp and rear_cam:
		_ramp(cv, o, rot)
	var gun := VH.GUNMETAL if not wreck else VH.BURNT
	var rws := D.w(rot, 0.1, 0.05, 14)
	var front := D.faces_cam(rot, 1.0, 0.0)
	var tip := D.sp(o, rot, 0.44 if not wreck else 0.3, 0.05, 16.5 if not wreck else 15.0)
	if not front:
		cv.line_v(D.sp(o, rot, 0.17, 0.05, 16), tip, gun)
	P.box(cv, o, rws, 0.07, 0.06, 4.0, rot, gun, 0.06, 705)
	if front:
		cv.line_v(D.sp(o, rot, 0.17, 0.05, 16), tip, gun)
	if not wreck:
		var sight := D.sp(o, rot, 0.14, 0.05, 18)
		cv.px(int(sight.x), int(sight.y), D.VISION)
		for s: float in [-1.0, 1.0]:  # smoke dischargers on the front corners
			var sp := D.sp(o, rot, 0.3, 0.14 * s, 14)
			cv.rect(int(sp.x), int(sp.y), 2, 1, Color8(52, 56, 44))
	for s: float in [-1.0, 1.0]:
		if D.faces_cam(rot, 0.0, s):
			_wheels(cv, o, rot, s, f, wreck)
	cv.outline(OUTL)
	var ab := D.sp(o, rot, -0.38, -0.12, 14)
	if not wreck:
		for i in 11:
			if cv.get_px(int(ab.x), int(ab.y) - i).a < 0.5:
				cv.px(int(ab.x), int(ab.y) - i, Color8(44, 44, 40) if i < 10 else Color8(156, 156, 140))
	else:
		V.soot(cv, D.sp(o, rot, 0.0, 0.0, 14), 5.0, 706)
	if f == 2 and not wreck:
		L.flash(cv, tip, 1.0)
		L.puff(cv, tip + Vector2(2, -2), 2.0, 0.4)


static func _wheels(cv, o: Vector2, rot: float, s: float, f: int, wreck: bool) -> void:
	for i in WHEELS.size():
		if wreck and i == 1 and s > 0:
			continue  # blown-off wheel
		D.road_wheel(cv, D.sp(o, rot, WHEELS[i], 0.2 * s, 3.5), 3.0, 3.4, f, wreck)


## Rear ramp lowered to the ground, with tread strips.
static func _ramp(cv, o: Vector2, rot: float) -> void:
	var q := PackedVector2Array([D.sp(o, rot, -0.48, -0.14, 5), D.sp(o, rot, -0.48, 0.14, 5),
		D.sp(o, rot, -0.8, 0.14, 0), D.sp(o, rot, -0.8, -0.14, 0)])
	cv.poly(q, P.mul(VH.HULL, 0.78))
	for t in [0.3, 0.6]:
		var a: Vector2 = q[0].lerp(q[3], t)
		var b: Vector2 = q[1].lerp(q[2], t)
		cv.line_v(a, b, P.mul(VH.HULL, 0.6))
