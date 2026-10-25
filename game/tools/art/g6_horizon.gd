extends RefCounted
## G6 horizon vehicles (orchestrator), built from the game's own art libraries:
##   b_rhomboid       Stage 6 rhomboid landcrawler: tall all-round tracks, side sponson guns, riveted body, stack.
##   a_laser_tank     Stage 10 beam tank: low sloped hull, flat turret with coolant fins, lens emitter, beam on fire.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const VH = preload("res://tools/art/vehicles.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const FIG = preload("res://tools/art/g5_units_fig.gd")

const OUTL := Color(0.09, 0.09, 0.07, 1)
const TAN := Color8(170, 146, 102)
const PATCH := [Color8(150, 128, 88), Color8(112, 104, 70), Color8(138, 70, 50), Color8(96, 92, 84)]
const FLAG := Color8(176, 52, 40)
const LENS := Color8(150, 220, 240)
const BEAM := Color8(220, 248, 255)
const IRR := {"coat": Color8(112, 104, 70), "trouser": Color8(96, 88, 66), "boot": Color8(52, 44, 34),
	"skin": Color8(160, 122, 92), "head": "cap_b", "weapon": "hmg"}

const SHOW := {
	"b_rhomboid": {"row": 0, "frame": "fire", "ground": "dirt"},
	"a_laser_tank": {"row": 0, "frame": "fire", "ground": "road"},
}


static func build(out: Dictionary) -> void:
	SL.veh_sheet(out, "b_rhomboid", {"fw": 84, "fh": 64, "pivot": [42, 42]}, rhomboid, ["idle", "move", "fire"])
	SL.veh_sheet(out, "a_laser_tank", {"fw": 96, "fh": 60, "pivot": [44, 36]}, laser_tank, ["idle", "move", "fire"])


static func _side_long(sd: Dictionary, rot: float) -> bool:
	return absf((sd.n as Vector2).dot(Vector2(cos(rot), sin(rot)))) < 0.3


# ---------------------------------------------------------------- b_rhomboid
static func rhomboid(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = V.BURNT if wreck else V.HULL
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 0), 0.66, 0.38, 16.0, rot)
	cv.flush_shadow()
	var tips: Array = []
	for pass_near in [false, true]:
		if pass_near:  # central fighting compartment between the track frames
			var body: Dictionary = P.box(cv, o, D.w(rot, -0.04, 0.0, 3), 0.5, 0.2, 12.0, rot, P.mul(hull, 0.95), 0.1, 960)
			if wreck:
				V.scorch(cv, body.top)
			else:
				cv.team = true
				cv.poly(P.sub(body.top, 0.25, 0.2, 0.75, 0.8), Color(0.66, 0.66, 0.66))
				cv.team = false
				D.hatch(cv, body.top, 0.78, 0.3, 0.92, 0.7, hull)
		for s: float in [-1.0, 1.0]:
			if D.faces_cam(rot, 0.0, s) != pass_near:
				continue
			_frame(cv, o, rot, s, f, wreck, hull)
			# sponson with a short gun poking out sideways-forward
			var sp: Dictionary = P.box(cv, o, D.w(rot, 0.02, 0.42 * s, 4), 0.2, 0.07, 9.0, rot, P.mul(hull, 1.08), 0.1, 965)
			if not wreck:
				for sd2 in sp.sides:
					V.rivets(cv, sd2.quad, 0.8, 4, hull)
			if wreck:
				V.scorch(cv, sp.top)
			var a0 := D.sp(o, rot, 0.12, 0.48 * s, 9)
			var a1 := D.sp(o, rot, 0.4 if not wreck else 0.25, 0.56 * s, 9)
			cv.line_v(a0, a1, V.GUNMETAL)
			cv.line_v(a0 + Vector2(0, -1), a1 + Vector2(0, -1), P.mul(V.GUNMETAL, 1.3))
			if pass_near:
				tips.append(a1)
	# exhaust stack
	var sb := D.sp(o, rot, -0.32, -0.08, 15)
	cv.rect(int(sb.x) - 1, int(sb.y) - 8, 3, 8, Color8(48, 46, 42))
	cv.px(int(sb.x), int(sb.y) - 8, Color8(24, 22, 20))
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, 0.0, 0.0, 16), 7.0, 966)
		return
	L.puff(cv, sb + Vector2(1, -11), 2.2, 0.45)
	if f == 1:
		L.puff(cv, sb + Vector2(3, -15), 2.8, 0.3)
	if f == 2:
		for t: Vector2 in tips:
			L.flash(cv, t, 1.1)
			L.puff(cv, t + Vector2(2, -2), 2.0, 0.4)


## Rhomboid track frame: a prism whose side profile (fwd, z) is the classic rhombus, extruded between
## right = 0.22*s and 0.38*s. Track surface strips are painted back-to-front, then the outer face: a track
## border all round with the riveted armour plate inset.
const PROF := [Vector2(-0.62, 0), Vector2(0.44, 0), Vector2(0.74, 11), Vector2(0.6, 18), Vector2(-0.56, 18), Vector2(-0.74, 7)]


static func _frame(cv, o: Vector2, rot: float, s: float, f: int, wreck: bool, hull: Color) -> void:
	var ri := 0.22 * s
	var ro := 0.38 * s
	var strips: Array = []
	for i in PROF.size():
		var a: Vector2 = PROF[i]
		var b: Vector2 = PROF[(i + 1) % PROF.size()]
		if i == 0:
			continue  # bottom run sits on the ground
		var q := PackedVector2Array([D.sp(o, rot, a.x, ri, a.y), D.sp(o, rot, b.x, ri, b.y), D.sp(o, rot, b.x, ro, b.y), D.sp(o, rot, a.x, ro, a.y)])
		var c := D.w(rot, (a.x + b.x) * 0.5, (ri + ro) * 0.5, 0)
		strips.append([c.x + c.y + (a.y + b.y) * 0.02, q, i])
	strips.sort_custom(func(x, y): return x[0] < y[0])
	var link := Color8(40, 38, 34) if not wreck else Color8(36, 32, 28)
	for st in strips:
		var q: PackedVector2Array = st[1]
		cv.poly(q, link)
		var n := maxi(3, int(q[0].distance_to(q[1]) / 2.0))
		for k in n:
			var u := (k + (0.5 if f == 1 else 0.0)) / n
			var m: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.5)
			cv.px(int(m.x), int(m.y), Color8(70, 68, 62) if not wreck else Color8(60, 48, 40))
	var r := ro if D.faces_cam(rot, 0.0, s) else ri
	var face := PackedVector2Array()
	var inner := PackedVector2Array()
	var cen := Vector2.ZERO
	for pnt: Vector2 in PROF:
		cen += pnt / PROF.size()
	for pnt: Vector2 in PROF:
		face.append(D.sp(o, rot, pnt.x, r, pnt.y))
		var ip: Vector2 = cen + (pnt - cen) * 0.74
		inner.append(D.sp(o, rot, ip.x, r, ip.y))
	cv.poly(face, link)
	var sh := P.side_shade(Vector2(-sin(rot), cos(rot)) * s)
	cv.poly(inner, P.mul(hull, sh), P.speckle(0.1, 975 + int(s)))
	if wreck:
		V.scorch(cv, inner)
		return
	for k in 6:  # road wheels along the bottom run, under the plate
		var u := 0.12 + k * 0.15
		var wp: Vector2 = PROF[0].lerp(PROF[1], u) + Vector2(0, 2.5)
		D.road_wheel(cv, D.sp(o, rot, wp.x, r, wp.y), 1.7, 1.8, f, wreck)
	for v in [0.2, 0.85]:
		var a: Vector2 = inner[0].lerp(inner[4], v)
		var b: Vector2 = inner[1].lerp(inner[3], v)
		for k in 7:
			var p: Vector2 = a.lerp(b, (k + 0.5) / 7.0)
			cv.px(int(p.x), int(p.y), P.mul(hull, 1.38))
			cv.px(int(p.x), int(p.y) + 1, P.mul(hull, 0.62))
	V.patch(cv, PackedVector2Array([inner[0], inner[1], inner[3], inner[4]]), 0.58, 0.3, 0.86, 0.7, V.PRIMER, 976)


# ---------------------------------------------------------------- a_laser_tank
static func laser_tank(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = VH.BURNT if wreck else P.mul(VH.HULL, 1.06)
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 2), 0.6, 0.33, 14.0, rot)
	cv.flush_shadow()
	for pass_near in [false, true]:
		for s: float in [-1.0, 1.0]:
			if D.faces_cam(rot, 0.0, s) != pass_near:
				continue
			var tr: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.25 * s, 0), 0.6, 0.08, 6.0, rot, VH.TRACK, 0.05, 980)
			for sd in tr.sides:
				if _side_long(sd, rot):
					D.track_side(cv, sd.quad, f, wreck, 6)
					if not wreck:  # side skirt over the upper run
						cv.poly(P.sub(sd.quad, 0.0, 0.55, 1.0, 1.0), P.mul(hull, 0.8))
		if not pass_near:
			P.box(cv, o, D.w(rot, 0.0, 0.0, 4), 0.56, 0.17, 5.0, rot, P.mul(hull, 0.9), 0.06, 981)
	var hl: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 8), 0.6, 0.33, 3.0, rot, hull, 0.05, 982)
	var nose: Dictionary = P.box(cv, o, D.w(rot, 0.5, 0.0, 8), 0.1, 0.3, 1.5, rot, P.mul(hull, 1.08), 0.04, 983)
	if wreck:
		VH._scorch(cv, hl)
	else:
		D.box_edges(cv, hl, hull, 984)
		D.grille(cv, hl.top, 0.02, 0.25, 0.18, 0.75, hull, 5)
	var front := D.faces_cam(rot, 1.0, 0.0)
	var em0 := D.sp(o, rot, 0.15, 0.0, 15)
	var em1 := D.sp(o, rot, 0.52 if not wreck else 0.35, 0.0, 15)
	if not front:
		_emitter(cv, em0, em1, wreck)
	var tur: Dictionary = P.box(cv, o, D.w(rot, -0.08, 0.0, 11), 0.26, 0.24, 5.0, rot, hull, 0.05, 985)
	if wreck:
		VH._scorch(cv, tur)
	else:
		D.box_edges(cv, tur, hull, 986)
		for sd in tur.sides:
			if _side_long(sd, rot):
				for i in 5:  # coolant fins
					var a: PackedVector2Array = P.sub(sd.quad, 0.15 + i * 0.15, 0.15, 0.19 + i * 0.15, 0.85)
					cv.line_v(a[0], a[3], Color8(54, 58, 56))
				cv.team = true
				cv.poly(P.sub(sd.quad, 0.0, 0.7, 1.0, 0.95), Color(0.62, 0.62, 0.62))
				cv.team = false
		D.hatch(cv, tur.top, 0.15, 0.55, 0.38, 0.85, hull)
		var sens := D.sp(o, rot, -0.02, -0.17, 17)
		cv.rect(int(sens.x) - 1, int(sens.y) - 1, 3, 2, Color8(44, 48, 46))
		cv.px(int(sens.x), int(sens.y) - 1, D.VISION)
		D.antenna(cv, D.sp(o, rot, -0.3, 0.16, 16), 9, false)
	if front:
		_emitter(cv, em0, em1, wreck)
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, -0.05, 0.0, 16), 6.0, 987)
	elif f == 2:  # beam to the frame edge along the facing
		var dir := (em1 - em0).normalized()
		if dir.length() < 0.1:
			dir = Vector2(0, 1)
		var far := em1 + dir * 60.0
		cv.line_v(em1 + Vector2(0, 1), far + Vector2(0, 1), Color(LENS.r, LENS.g, LENS.b, 0.45))
		cv.line_v(em1 + Vector2(0, -1), far + Vector2(0, -1), Color(LENS.r, LENS.g, LENS.b, 0.45))
		cv.line_v(em1, far, BEAM)
		cv.ellipse(em1.x, em1.y, 2.6, 2.2, Color(LENS.r, LENS.g, LENS.b, 0.5))
		cv.px(int(em1.x), int(em1.y), Color.WHITE)


static func _emitter(cv, a: Vector2, b: Vector2, wreck: bool) -> void:
	var c: Color = VH.GUNMETAL if not wreck else VH.BURNT
	for t in [-1, 0, 1]:
		cv.line_v(a + Vector2(0, t), b + Vector2(0, t), P.mul(c, 1.0 + 0.2 * -t))
	cv.ellipse(b.x, b.y, 1.8, 1.8, P.mul(c, 0.9))
	if not wreck:
		cv.px(int(b.x), int(b.y), LENS)


