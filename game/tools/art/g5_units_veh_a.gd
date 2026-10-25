extends RefCounted
## G5 Human A vehicles (agent ART-U5), vehicles.gd olive with team bands / roof panels:
##   a_spaag       tracked SPAAG: twin cannons either side of the turret, search radar dish on the back,
##                 tracking radar in front. idle / move (dish turned) / fire (both barrels, elevated).
##   a_recon_car   low 4x4 scout car: sloped cab, autocannon RWS, telescoping sensor mast. idle / move / fire.
##   a_ambulance   6x6 armoured ambulance: box body with red crosses (sides + roof), beacons.
##                 idle / move / fire (beacons lit) / unload (rear doors open, stretcher out).
## All leave 1-column wreck sheets.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const VH = preload("res://tools/art/vehicles.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")

const OUTL := Color(0.09, 0.09, 0.07, 1)
const SPEC := {
	"a_spaag": {"fw": 66, "fh": 58, "pivot": [33, 38]},
	"a_recon_car": {"fw": 60, "fh": 46, "pivot": [30, 30]},
	"a_ambulance": {"fw": 64, "fh": 54, "pivot": [32, 35]},
}
const WHITE := Color8(226, 224, 214)
const RED := Color8(196, 38, 34)
const BEACON := Color8(80, 140, 255)


static func build(out: Dictionary) -> void:
	SL.veh_sheet(out, "a_spaag", SPEC.a_spaag, spaag, ["idle", "move", "fire"])
	SL.veh_sheet(out, "a_recon_car", SPEC.a_recon_car, recon, ["idle", "move", "fire"])
	SL.veh_sheet(out, "a_ambulance", SPEC.a_ambulance, ambulance, ["idle", "move", "fire", "unload"])


## Red cross on a white field painted onto a box face / roof quad.
static func cross(cv, q: PackedVector2Array, u0: float, v0: float, u1: float, v1: float) -> void:
	cv.poly(P.sub(q, u0, v0, u1, v1), WHITE)
	var um := (u0 + u1) * 0.5
	var vm := (v0 + v1) * 0.5
	var du := (u1 - u0) * 0.14
	var dv := (v1 - v0) * 0.14
	cv.poly(P.sub(q, um - du, v0 + dv * 1.2, um + du, v1 - dv * 1.2), RED)
	cv.poly(P.sub(q, u0 + du * 1.2, vm - dv, u1 - du * 1.2, vm + dv), RED)


static func _team_band(cv, q: PackedVector2Array, u0: float, u1: float) -> void:
	cv.team = true
	cv.poly(P.sub(q, u0, 0.25, u1, 0.7), Color(0.62, 0.62, 0.62))
	cv.team = false


# ---------------------------------------------------------------- a_spaag
static func spaag(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = VH.BURNT if wreck else VH.HULL
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 2), 0.52, 0.22, 16.0, rot)
	cv.flush_shadow()
	var ax := Vector2(cos(rot), sin(rot))
	for pass_near in [false, true]:
		for s: float in [-1.0, 1.0]:
			if D.faces_cam(rot, 0.0, s) != pass_near:
				continue
			var tr: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.19 * s, 0), 0.5, 0.06, 6.0, rot, VH.TRACK, 0.05, 801)
			for sd in tr.sides:
				if absf((sd.n as Vector2).dot(ax)) < 0.3:
					D.track_side(cv, sd.quad, f, wreck, 6)
		if not pass_near:
			var lo: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 4), 0.48, 0.14, 6.0, rot, P.mul(hull, 0.92), 0.08, 802)
			if wreck:
				VH._scorch(cv, lo)
	var hl: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 9), 0.47, 0.2, 2.0, rot, hull, 0.08, 803)
	if not wreck:
		D.box_edges(cv, hl, hull, 804)
	var trot := rot
	var tur: Dictionary = P.box(cv, o, D.w(rot, -0.04, 0.0, 11), 0.19, 0.14, 7.0, trot, hull, 0.08, 805)
	if wreck:
		VH._scorch(cv, tur)
	else:
		for sd in tur.sides:
			if absf((sd.n as Vector2).dot(ax)) < 0.3:
				_team_band(cv, sd.quad, 0.15, 0.85)
		D.hatch(cv, tur.top, 0.15, 0.25, 0.45, 0.75, hull)
	var tips: Array = []
	var elev := 0.0 if wreck else (11.0 if f != 1 else 6.0)
	for s: float in [-1.0, 1.0]:  # gun pods on the turret cheeks, barrels elevated
		var base := D.sp(o, rot, 0.0, 0.2 * s, 15)
		var tip := D.sp(o, rot, 0.46 if not wreck else 0.3, 0.2 * s, 15.0 + elev - (3.0 if wreck else 0.0))
		var front := D.faces_cam(rot, 0.0, s)
		if not front:
			cv.line_v(base, tip, VH.GUNMETAL if not wreck else VH.BURNT)
		P.box(cv, o, D.w(rot, 0.02, 0.2 * s, 12), 0.12, 0.035, 5.0, rot, P.mul(hull, 0.85), 0.05, 806)
		if front:
			cv.line_v(base, tip, VH.GUNMETAL if not wreck else VH.BURNT)
		tips.append(tip)
	if not wreck:  # tracking radar (front), search radar dish on a mast (back), turned while moving
		var tr := D.sp(o, rot, 0.16, 0.0, 19)
		cv.ellipse(tr.x, tr.y, 1.8, 1.6, Color8(70, 74, 64))
		cv.px(int(tr.x), int(tr.y), D.VISION)
		var mast := D.sp(o, rot, -0.14, 0.0, 18)
		var top := mast + Vector2(0, -5)
		cv.line_v(mast, top, Color8(52, 54, 50))
		var dr := rot + (PI / 2.0 if f == 1 else 0.0)
		var dl := Vector2(cos(dr) - sin(dr), (cos(dr) + sin(dr)) * 0.5).normalized()
		cv.line_v(top - dl * 4.5, top + dl * 4.5, Color8(84, 88, 80))
		cv.line_v(top - dl * 4.0 + Vector2(0, -1), top + dl * 4.0 + Vector2(0, -1), Color8(108, 112, 102))
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, 0.0, 0.0, 16), 6.0, 807)
	elif f == 2:
		for t: Vector2 in tips:
			L.flash(cv, t, 1.0)
			L.puff(cv, t + Vector2(1, -2), 1.8, 0.4)


# ---------------------------------------------------------------- a_recon_car
static func recon(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = VH.BURNT if wreck else VH.HULL
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 3), 0.42, 0.19, 9.0, rot)
	cv.flush_shadow()
	var ax := Vector2(cos(rot), sin(rot))
	for s: float in [-1.0, 1.0]:
		if not D.faces_cam(rot, 0.0, s):
			_wheels4(cv, o, rot, s, f, wreck)
	var lo: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 4), 0.42, 0.17, 5.0, rot, P.mul(hull, 0.92), 0.08, 811)
	var cab: Dictionary = P.box(cv, o, D.w(rot, -0.06, 0.0, 9), 0.26, 0.15, 4.0, rot, hull, 0.08, 812)
	if wreck:
		VH._scorch(cv, lo)
		VH._scorch(cv, cab)
	else:
		D.box_edges(cv, cab, hull, 813)
		for sd in cab.sides:
			var dd: float = (sd.n as Vector2).dot(ax)
			if absf(dd) < 0.3:
				_team_band(cv, sd.quad, 0.1, 0.55)
			elif dd > 0.7:
				cv.poly(P.sub(sd.quad, 0.1, 0.25, 0.9, 0.75), D.VISION)  # windscreen
		for sd in lo.sides:
			if (sd.n as Vector2).dot(ax) > 0.7:
				for u in [0.15, 0.85]:
					var hp: Vector2 = P.sub(sd.quad, u, 0.6, u, 0.6)[0]
					cv.px(int(hp.x), int(hp.y), Color8(236, 226, 172))
	var gun := VH.GUNMETAL if not wreck else VH.BURNT
	var front := D.faces_cam(rot, 1.0, 0.0)
	var tip := D.sp(o, rot, 0.5 if not wreck else 0.32, 0.03, 16.0)
	if not front:
		cv.line_v(D.sp(o, rot, 0.0, 0.03, 16), tip, gun)
	P.box(cv, o, D.w(rot, -0.04, 0.03, 13), 0.08, 0.07, 4.0, rot, P.mul(hull, 0.8), 0.06, 814)
	if front:
		cv.line_v(D.sp(o, rot, 0.0, 0.03, 16), tip, gun)
	for s: float in [-1.0, 1.0]:
		if D.faces_cam(rot, 0.0, s):
			_wheels4(cv, o, rot, s, f, wreck)
	cv.outline(OUTL)
	if not wreck:  # sensor mast with an optics head, raised when halted
		var mb := D.sp(o, rot, -0.2, -0.08, 13)
		var h := 10 if f != 1 else 4
		for i in h:
			if cv.get_px(int(mb.x), int(mb.y) - i).a < 0.5:
				cv.px(int(mb.x), int(mb.y) - i, Color8(48, 50, 46))
		cv.rect(int(mb.x) - 1, int(mb.y) - h - 2, 3, 2, Color8(60, 64, 58))
		cv.px(int(mb.x) + 1, int(mb.y) - h - 1, D.VISION)
	else:
		V.soot(cv, D.sp(o, rot, 0.0, 0.0, 12), 5.0, 815)
	if f == 2 and not wreck:
		L.flash(cv, tip, 0.9)
		L.puff(cv, tip + Vector2(2, -2), 1.8, 0.4)


static func _wheels4(cv, o: Vector2, rot: float, s: float, f: int, wreck: bool) -> void:
	for i in 2:
		if wreck and i == 0 and s > 0:
			continue
		D.road_wheel(cv, D.sp(o, rot, -0.27 + i * 0.54, 0.19 * s, 3.5), 3.4, 3.6, f, wreck)


# ---------------------------------------------------------------- a_ambulance
static func ambulance(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = VH.BURNT if wreck else VH.HULL
	var body_c: Color = VH.BURNT if wreck else P.mul(VH.HULL, 1.12)
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 3), 0.48, 0.2, 14.0, rot)
	cv.flush_shadow()
	var ax := Vector2(cos(rot), sin(rot))
	var doors := f == 3 and not wreck
	var rear_cam := D.faces_cam(rot, -1.0, 0.0)
	for s: float in [-1.0, 1.0]:
		if not D.faces_cam(rot, 0.0, s):
			_wheels6(cv, o, rot, s, f, wreck)
	if doors and not rear_cam:
		_rear_open(cv, o, rot)
	var lo: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 4), 0.47, 0.18, 6.0, rot, P.mul(hull, 0.9), 0.08, 821)
	var cab: Dictionary = P.box(cv, o, D.w(rot, 0.32, 0.0, 10), 0.13, 0.17, 6.0, rot, hull, 0.08, 822)
	var body: Dictionary = P.box(cv, o, D.w(rot, -0.13, 0.0, 10), 0.32, 0.19, 9.0, rot, body_c, 0.06, 823)
	if wreck:
		for r in [lo, cab, body]:
			VH._scorch(cv, r)
	else:
		D.box_edges(cv, body, body_c, 824)
		for sd in cab.sides:
			var dd: float = (sd.n as Vector2).dot(ax)
			if absf(dd) < 0.3:
				_team_band(cv, sd.quad, 0.1, 0.9)
			elif dd > 0.7:
				cv.poly(P.sub(sd.quad, 0.12, 0.2, 0.88, 0.6), D.VISION)
		for sd in body.sides:
			var dd: float = (sd.n as Vector2).dot(ax)
			if absf(dd) < 0.3:
				cross(cv, sd.quad, 0.3, 0.12, 0.7, 0.88)
			elif dd < -0.7 and doors:
				cv.poly(P.sub(sd.quad, 0.12, 0.05, 0.88, 1.0), Color8(30, 30, 28))  # open rear
		cross(cv, body.top, 0.25, 0.2, 0.75, 0.8)
		for sd in lo.sides:
			if (sd.n as Vector2).dot(ax) > 0.7:
				for u in [0.15, 0.85]:
					var hp: Vector2 = P.sub(sd.quad, u, 0.6, u, 0.6)[0]
					cv.px(int(hp.x), int(hp.y), Color8(236, 226, 172))
	if doors and rear_cam:
		_rear_open(cv, o, rot)
	for s: float in [-1.0, 1.0]:
		if D.faces_cam(rot, 0.0, s):
			_wheels6(cv, o, rot, s, f, wreck)
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, -0.1, 0.0, 16), 6.0, 825)
		return
	for s: float in [-1.0, 1.0]:  # roof beacons, lit on the "fire" frame (siren / emergency run)
		var b := D.sp(o, rot, 0.36, 0.1 * s, 17)
		var lit := f == 2
		cv.rect(int(b.x), int(b.y) - 1, 2, 2, (BEACON if s < 0 else RED) if lit else Color8(70, 80, 110))
		if lit:
			cv.ellipse(b.x + 1, b.y, 3.0, 2.0, Color(BEACON.r, BEACON.g, BEACON.b, 0.25) if s < 0 else Color(1, 0.2, 0.2, 0.25))


static func _wheels6(cv, o: Vector2, rot: float, s: float, f: int, wreck: bool) -> void:
	for i in 3:
		if wreck and i == 2 and s > 0:
			continue
		D.road_wheel(cv, D.sp(o, rot, -0.3 + i * 0.3, 0.19 * s, 3.5), 3.2, 3.5, f, wreck)


## Rear doors swung open with a loaded stretcher sliding out onto the ground.
static func _rear_open(cv, o: Vector2, rot: float) -> void:
	for s: float in [-1.0, 1.0]:
		var hinge := D.sp(o, rot, -0.45, 0.19 * s, 10)
		var q := PackedVector2Array([hinge, D.sp(o, rot, -0.45, 0.32 * s, 10), D.sp(o, rot, -0.45, 0.32 * s, 18), D.sp(o, rot, -0.45, 0.19 * s, 18)])
		cv.poly(q, P.mul(VH.HULL, 1.05))
	var a := D.sp(o, rot, -0.5, 0.0, 6)
	var b := D.sp(o, rot, -0.85, 0.0, 1)
	var pr := Vector2(-sin(rot) - cos(rot), (cos(rot) - sin(rot)) * 0.5).normalized() * 2.0
	cv.poly(PackedVector2Array([a - pr, a + pr, b + pr, b - pr]), Color8(196, 188, 150))
	var m := a.lerp(b, 0.5)
	cv.rect(int(m.x) - 1, int(m.y) - 1, 3, 2, Color8(118, 124, 88))
	cv.px(int(m.x), int(m.y) - 1, RED)
