extends RefCounted
## G3b Human A units (agent ART4), olive-drab regular-army look of vehicles.gd / truck.gd:
##   a_old_tank    Cold-War tank: cast dome turret, long barrel with bore evacuator, rear fuel drums, IR lamp
##   a_guided_arty tracked self-propelled howitzer: big boxy rear turret, elevated barrel, datalink dome
##   a_ew_truck    6-wheel truck with an EW shelter and a lattice mast + dish (fire = EW pulse)
##   a_uav         Recon-strike UAV (air): drawn resting on the pivot; altitude/shadow via manifest
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const B = preload("res://tools/art/bdetail.gd")
const T = preload("res://tools/art/truck.gd")
const G = preload("res://tools/art/g3b_lib.gd")

const SPEC := {
	"a_old_tank": {"fw": 68, "fh": 50, "pivot": [34, 32]},
	"a_guided_arty": {"fw": 76, "fh": 60, "pivot": [38, 38]},
	"a_ew_truck": {"fw": 64, "fh": 66, "pivot": [32, 46]},
	"a_uav": {"fw": 52, "fh": 38, "pivot": [26, 22]},
}
const OLD := Color8(86, 96, 62)       # older, greener drab than the MBT
const HULL := Color8(96, 100, 74)
const TRACK := Color8(44, 44, 40)
const GUNMETAL := Color8(58, 60, 58)
const BURNT := Color8(58, 52, 46)
const UAV := Color8(148, 152, 148)
const OUTL := Color(0.08, 0.08, 0.07, 1)


static func build(out: Dictionary) -> void:
	G.sheet(out, "a_old_tank", SPEC.a_old_tank, old_tank)
	G.sheet(out, "a_guided_arty", SPEC.a_guided_arty, guided_arty)
	G.sheet(out, "a_ew_truck", SPEC.a_ew_truck, ew_truck)
	G.sheet(out, "a_uav", SPEC.a_uav, uav, false, false)
	G.air(out, "a_uav", 22, 1, G.shadow_blobs(44, 18, [[22, 9, 17.0, 2.6], [22, 9, 6.0, 4.6]]), [22, 9])


static func _tracks(cv, o: Vector2, rot: float, f: int, wreck: bool, hx: float, off: float, hz: float) -> void:
	for s in [-1, 1]:
		var r: Dictionary = P.box(cv, o, D.w(rot, 0, off * s), hx, 0.09, hz, rot, TRACK if not wreck else Color8(40, 36, 32), 0.1, 901 + s)
		for sd in r.sides:
			if absf((sd.n as Vector2).dot(Vector2(-sin(rot), cos(rot)))) > 0.7:
				if not wreck:
					D.mud(cv, sd.quad, 903 + int(off * 50) + s, 0.55)
				D.track_side(cv, sd.quad, f, wreck, 5)


## Hull dress shared by the tracked pair: team band on the long sides, tow hooks, mud, edges.
static func _hull(cv, o: Vector2, rot: float, r: Dictionary, hull: Color, wreck: bool, s: int) -> void:
	if wreck:
		T._scorch(cv, r.top)
		return
	var ax := Vector2(cos(rot), sin(rot))
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		var d: float = (sd.n as Vector2).dot(ax)
		if absf(d) < 0.3:
			cv.team = true
			cv.poly(P.sub(q, 0.08, 0.5, 0.55, 0.82), Color(0.6, 0.6, 0.6))
			cv.team = false
			D.mud(cv, q, s + int(q[0].x), 0.42)
		elif d > 0.7:
			D.tow_hooks(cv, q)
			for u in [0.15, 0.85]:
				var lp: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.75)
				cv.px(int(lp.x), int(lp.y), Color8(226, 214, 160))
	D.contact_ao(cv, r)
	D.box_edges(cv, r, hull, s + 1)


# ---------------------------------------------------------------- a_old_tank
static func old_tank(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = BURNT if wreck else OLD
	var trot := rot + (0.7 if wreck else 0.0)
	var toward := cos(trot) + sin(trot) > 0.0
	var bl := 0.34 if f != 2 else 0.29
	for s in [-1, 1]:
		P.box_shadow(cv, o, D.w(rot, 0, 0.235 * s), 0.55, 0.09, 6.0, rot)
	P.box_shadow(cv, o, D.w(rot, 0, 0, 5), 0.53, 0.3, 5.0, rot)
	P.box_shadow(cv, o, D.w(trot, -0.03, 0, 10), 0.19, 0.19, 7.0, trot)
	cv.flush_shadow()
	_tracks(cv, o, rot, f, wreck, 0.55, 0.235, 6.0)
	var r: Dictionary = P.box(cv, o, D.w(rot, 0, 0, 5), 0.53, 0.3, 5.0, rot, hull, 0.1, 911)
	_hull(cv, o, rot, r, hull, wreck, 912)
	if not wreck:
		D.grille(cv, r.top, 0.0, 0.25, 0.2, 0.75, hull, 4)
		for s in [-1, 1]:  # external fuel drums on the rear deck
			var dr: Dictionary = P.box(cv, o, D.w(rot, -0.45, 0.16 * s, 10), 0.05, 0.1, 3.0, rot, Color8(70, 78, 52), 0.06, 914)
			for sd in dr.sides:
				cv.line_v(sd.quad[0].lerp(sd.quad[1], 0.3), sd.quad[3].lerp(sd.quad[2], 0.3), Color8(46, 50, 36))
	if not toward:
		_old_barrel(cv, o, trot, bl, wreck)
	# cast dome turret: three stacked tiers, the middle one team-coloured
	var tc := D.w(trot, -0.03, 0, 10)
	B.cyl(cv, o, tc, 0.2, 3.0, P.mul(hull, 1.02), 915)
	if wreck:
		B.cyl(cv, o, tc + Vector3(0, 0, 3), 0.16, 2.0, P.mul(hull, 0.9), 916)
	else:
		cv.team = true
		B.cyl(cv, o, tc + Vector3(0, 0, 3), 0.17, 2.0, Color(0.64, 0.64, 0.64), 916)
		cv.team = false
	var top := B.cyl(cv, o, tc + Vector3(0, 0, 5), 0.12, 2.0, P.mul(hull, 1.06), 917)
	if wreck:
		cv.ellipse(top.x, top.y, 3.5, 1.8, Color8(36, 32, 30))
	else:
		D.cupola(cv, o, trot, -0.09, 0.08, 16, hull, false)
		P.box(cv, o, D.w(trot, 0.08, -0.17, 13), 0.05, 0.05, 2.5, trot, Color8(56, 58, 52), 0.05, 918)
		if toward:
			var lp := D.sp(o, trot, 0.13, -0.17, 14)
			cv.px(int(lp.x), int(lp.y), Color8(150, 46, 40))  # IR searchlight lens
		D.antenna(cv, D.sp(o, trot, -0.18, -0.1, 15), 10, false)
	if toward:
		_old_barrel(cv, o, trot, bl, wreck)
	if f == 2 and not wreck:
		G.flash(cv, D.sp(o, trot, 0.17 + bl * 2.0 + 0.05, 0, 13.5))
	cv.outline(OUTL)


static func _old_barrel(cv, o: Vector2, trot: float, bl: float, wreck: bool) -> void:
	var col: Color = GUNMETAL if not wreck else BURNT
	var z := 12.5 if not wreck else 10.5
	P.box(cv, o, D.w(trot, 0.17 + bl, 0, z), bl, 0.026, 1.8, trot, col, 0.04, 921)
	P.box(cv, o, D.w(trot, 0.17 + bl * 1.25, 0, z - 0.4), 0.04, 0.04, 2.5, trot, P.mul(col, 1.12), 0.04, 922)  # bore evacuator


# ---------------------------------------------------------------- a_guided_arty
static func guided_arty(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = BURNT if wreck else HULL
	var trot := rot + (0.5 if wreck else 0.0)
	var toward := cos(trot) + sin(trot) > 0.0
	for s in [-1, 1]:
		P.box_shadow(cv, o, D.w(rot, 0, 0.25 * s), 0.58, 0.09, 6.0, rot)
	P.box_shadow(cv, o, D.w(rot, 0, 0, 5), 0.56, 0.32, 5.0, rot)
	P.box_shadow(cv, o, D.w(trot, -0.14, 0, 10), 0.3, 0.27, 8.0, trot)
	cv.flush_shadow()
	_tracks(cv, o, rot, f, wreck, 0.58, 0.25, 6.0)
	var r: Dictionary = P.box(cv, o, D.w(rot, 0, 0, 5), 0.56, 0.32, 5.0, rot, hull, 0.1, 931)
	_hull(cv, o, rot, r, hull, wreck, 932)
	if not wreck:
		D.hatch(cv, r.top, 0.78, 0.2, 0.92, 0.45, hull)
		D.grille(cv, r.top, 0.72, 0.55, 0.95, 0.85, hull, 3)
	if not toward:
		_arty_barrel(cv, o, trot, f, wreck)
	var t: Dictionary = P.box(cv, o, D.w(trot, -0.14, 0, 10), 0.3, 0.27, 8.0, trot, P.mul(hull, 1.03), 0.1, 935)
	if wreck:
		T._scorch(cv, t.top)
	else:
		for sd in t.sides:
			var q: PackedVector2Array = sd.quad
			cv.team = true
			cv.poly(P.sub(q, 0.1, 0.4, 0.9, 0.72), Color(0.62, 0.62, 0.62))
			cv.team = false
			cv.line_v(q[0].lerp(q[1], 0.5), q[3].lerp(q[2], 0.5), P.mul(hull, 0.78))  # door seam
		D.box_edges(cv, t, hull, 936)
		D.hatch(cv, t.top, 0.2, 0.15, 0.45, 0.4, hull)
		D.cupola(cv, o, trot, -0.22, 0.14, 18, hull, false)
		var dm := B.cyl(cv, o, D.w(trot, -0.3, -0.12, 18), 0.07, 2.0, Color8(196, 196, 186), 937)  # datalink dome
		cv.px(int(dm.x), int(dm.y), Color8(120, 200, 230))
		D.stowage(cv, o, trot, -0.46, 0.0, 12, 0.04, 0.2, 3.0, false, false)
		G.whip(cv, D.sp(o, trot, -0.38, 0.2, 18), 12, Color8(140, 140, 130))
		G.whip(cv, D.sp(o, trot, -0.38, -0.22, 18), 9, Color8(140, 140, 130))
	if toward:
		_arty_barrel(cv, o, trot, f, wreck)
	cv.outline(OUTL)
	if f == 2 and not wreck:
		var tip := D.sp(o, trot, 0.92, 0, 25)
		G.flash(cv, tip, 1.4)
		cv.ellipse(tip.x - 2, tip.y - 3, 3.0, 2.0, Color(0.8, 0.78, 0.72, 0.45))


## Elevated howitzer barrel: thick line rising from the mantlet (recoils on the fire frame).
static func _arty_barrel(cv, o: Vector2, trot: float, f: int, wreck: bool) -> void:
	var col: Color = GUNMETAL if not wreck else BURNT
	var len := 0.76 if f != 2 else 0.66
	var rise := 11.0 if not wreck else 2.0
	P.box(cv, o, D.w(trot, 0.17, 0, 12), 0.04, 0.12, 5.0, trot, P.mul(col, 1.1), 0.05, 938)  # mantlet
	var a := D.sp(o, trot, 0.2, 0, 14.5)
	var b := D.sp(o, trot, 0.2 + len, 0, 14.5 + rise)
	cv.line_v(a + Vector2(0, 1), b + Vector2(0, 1), P.mul(col, 0.7))
	cv.line_v(a, b, col)
	cv.line_v(a + Vector2(0, -1), b + Vector2(0, -1), P.mul(col, 1.3))
	var mz := a.lerp(b, 0.97)
	cv.rect(int(mz.x) - 1, int(mz.y) - 1, 3, 3, P.mul(col, 1.15))  # muzzle brake
	var ev := a.lerp(b, 0.55)
	cv.rect(int(ev.x) - 1, int(ev.y) - 1, 2, 3, P.mul(col, 1.2))  # bore evacuator


# ---------------------------------------------------------------- a_ew_truck
static func ew_truck(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var body: Color = BURNT if wreck else T.BODY
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 0), 0.52, 0.22, 4.0, rot)
	P.box_shadow(cv, o, D.w(rot, 0.36, 0.0, 4.5), 0.16, 0.22, 9.5, rot)
	P.box_shadow(cv, o, D.w(rot, -0.2, 0.0, 4.5), 0.34, 0.23, 10.0, rot)
	cv.flush_shadow()
	T._wheels(cv, o, rot, f, wreck, false)
	var ch: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 2.0), 0.52, 0.16, 2.5, rot, T.CHASSIS if not wreck else T.CHAR, 0.08, 941)
	for sd in ch.sides:
		if absf((sd.n as Vector2).dot(Vector2(cos(rot), sin(rot)))) > 0.7:
			D.tow_hooks(cv, sd.quad)
	T._wheels(cv, o, rot, f, wreck, true)
	if D.faces_cam(rot, 1.0, 0.0):
		_shelter(cv, o, rot, body, wreck)
		T._exhaust(cv, o, rot, wreck)
		T._cab(cv, o, rot, body, wreck)
	else:
		T._cab(cv, o, rot, body, wreck)
		T._exhaust(cv, o, rot, wreck)
		_shelter(cv, o, rot, body, wreck)
	# lattice mast at the rear of the shelter: raised when parked/emitting, stowed low when driving
	var mh := 6.0 if f == 1 else 17.0
	if wreck:
		mh = 4.0
	var mb := D.sp(o, rot, -0.42, 0.0, 15)
	var mt := mb + Vector2(0, -mh)
	G.lattice(cv, mb, mt, 1.2, Color8(70, 72, 66))
	var tip := G.dish(cv, o, Vector3(0, 0, 0) + D.w(rot, -0.42, 0.0, 15 + mh + 3), rot + 0.6, 5.0, Color8(176, 178, 168), wreck)
	cv.outline(OUTL)
	if f == 2 and not wreck:
		G.pulse(cv, tip, 9.0)


static func _shelter(cv, o: Vector2, rot: float, body: Color, wreck: bool) -> void:
	var col: Color = P.mul(body, 0.94)
	var r: Dictionary = P.box(cv, o, D.w(rot, -0.2, 0.0, 4.5), 0.33, 0.22, 10.0, rot, col, 0.07, 943)
	if wreck:
		T._scorch(cv, r.top)
		return
	var ax := Vector2(cos(rot), sin(rot))
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		var d: float = (sd.n as Vector2).dot(ax)
		if absf(d) < 0.3:
			cv.team = true
			cv.poly(P.sub(q, 0.04, 0.72, 0.96, 0.86), Color(0.66, 0.66, 0.66))
			cv.team = false
			B.door(cv, q, 0.62, 0.82, 0.62, P.mul(col, 0.8))
			for i in 3:  # vent louvres
				var a: Vector2 = q[0].lerp(q[1], 0.14 + i * 0.07).lerp(q[3].lerp(q[2], 0.14 + i * 0.07), 0.6)
				cv.px(int(a.x), int(a.y), D.DARK)
			D.mud(cv, q, 944 + int(q[0].x), 0.2)
		else:
			cv.line_v(q[0].lerp(q[3], 0.5), q[1].lerp(q[2], 0.5), P.mul(col, 0.8))
	D.contact_ao(cv, r)
	D.box_edges(cv, r, col, 945)
	D.grille(cv, r.top, 0.55, 0.2, 0.8, 0.5, col, 3)  # roof AC unit
	for s in [-1, 1]:
		G.whip(cv, D.sp(o, rot, 0.08, 0.2 * s, 15), 13, Color8(200, 60, 50))


# ---------------------------------------------------------------- a_uav
## Long straight wings, V-tail, satcom hump, chin sensor ball, pusher prop. Move = banked, fire =
## missile launch from the near-wing pylon. Body rests on the pivot; no baked ground shadow.
static func uav(cv, rot: float, f: int, _wreck: bool, o: Vector2) -> void:
	var bank := 1.8 if f == 1 else 0.0
	var near_s := 1 if D.faces_cam(rot, 0.0, 1.0) else -1
	_wing(cv, o, rot, -near_s, bank)
	var fu: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0, 4), 0.3, 0.05, 3.5, rot, UAV, 0.05, 951)
	D.box_edges(cv, fu, UAV, 953, 0.2)
	P.box(cv, o, D.w(rot, 0.17, 0, 7.5), 0.1, 0.045, 1.5, rot, P.mul(UAV, 1.06), 0.04, 952)
	cv.team = true
	cv.poly(P.sub(fu.top, 0.32, 0.1, 0.58, 0.9), Color(0.72, 0.72, 0.72))
	cv.team = false
	var sb := D.sp(o, rot, 0.25, 0, 3.5)
	cv.ellipse(sb.x, sb.y + 1, 1.7, 1.5, Color8(52, 54, 56))
	cv.px(int(sb.x), int(sb.y) + 1, Color8(120, 176, 196))
	_wing(cv, o, rot, near_s, bank)
	for s in [-1, 1]:
		cv.line_v(D.sp(o, rot, -0.25, 0, 7), D.sp(o, rot, -0.33, 0.11 * s, 12), P.mul(UAV, 0.82))
		cv.line_v(D.sp(o, rot, -0.24, 0, 7), D.sp(o, rot, -0.31, 0.11 * s, 12), P.mul(UAV, 1.1))
	cv.outline(OUTL)
	if f == 2:
		var mp := D.sp(o, rot, 0.16, 0.22 * near_s, 4.5)
		G.flash(cv, mp)
		cv.line_v(mp + Vector2(-2, 1), mp + Vector2(-5, 2), Color(0.85, 0.85, 0.8, 0.6))  # launch trail
	var pp := D.sp(o, rot, -0.32, 0, 6)
	for y in range(int(pp.y) - 4, int(pp.y) + 5):
		for x in range(int(pp.x) - 2, int(pp.x) + 3):
			var dy := (y + 0.5 - pp.y) / 4.0
			var dx := (x + 0.5 - pp.x) / 2.0
			if dx * dx + dy * dy <= 1.0:
				cv.px(x, y, Color(0.8, 0.82, 0.8, 0.2 + 0.2 * float((x + y + f) % 2)))


static func _wing(cv, o: Vector2, rot: float, s: int, bank: float) -> void:
	var zr := 6.0
	var zt := zr + bank * s
	var pts := PackedVector2Array([D.sp(o, rot, 0.07, 0.04 * s, zr), D.sp(o, rot, 0.04, 0.46 * s, zt),
		D.sp(o, rot, -0.02, 0.46 * s, zt), D.sp(o, rot, -0.05, 0.04 * s, zr)])
	var under := PackedVector2Array()
	for p in pts:
		under.append(p + Vector2(0, 1))
	cv.poly(under, P.mul(UAV, 0.6))
	cv.poly(pts, P.mul(UAV, 1.08), P.speckle(0.04, 955 + s))
	cv.line_v(pts[0], pts[1], P.mul(UAV, 1.28))
	var py := D.sp(o, rot, 0.03, 0.22 * s, zr - 1.5 + bank * s * 0.5)  # missile under the pylon
	cv.line_v(py, py + (D.sp(o, rot, 0.14, 0.22 * s, 0) - D.sp(o, rot, 0.0, 0.22 * s, 0)), Color8(70, 72, 66))
