extends RefCounted
## G4b Human B vehicles (agent ART-U), riveted khaki-rust look of faction_b_veh / g3b_human_b:
##   b_halftrack     front wheels + rear track units, bonnet, armoured cab, open troop bay with helmets,
##                   pintle HMG behind a shield; unload = rear doors swung open.
##   b_rocket_truck  g3b_human_b truck + 2x3 rocket-tube rack (lowered on the move); fire = salvo.
## Frames: halftrack idle, move, fire, unload; rocket truck idle, move, fire. Both leave wrecks.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const TRK = preload("res://tools/art/faction_b_trk.gd")
const HB = preload("res://tools/art/g3b_human_b.gd")
const L = preload("res://tools/art/g4_units_lib.gd")

const SPEC := {
	"b_halftrack": {"fw": 66, "fh": 52, "pivot": [33, 35]},
	"b_rocket_truck": {"fw": 68, "fh": 58, "pivot": [34, 40]},
}
const OUTL := Color(0.08, 0.07, 0.06, 1)


static func build(out: Dictionary) -> void:
	L.sheet(out, "b_halftrack", SPEC.b_halftrack, halftrack, ["idle", "move", "fire", "unload"], "vehicles", true)
	L.sheet(out, "b_rocket_truck", SPEC.b_rocket_truck, rocket_truck, ["idle", "move", "fire"], "vehicles", true)


# ---------------------------------------------------------------- b_halftrack
static func halftrack(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var col: Color = V.BURNT if wreck else V.HULL
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 2), 0.54, 0.22, 10.0, rot)
	cv.flush_shadow()
	var door := f == 3 and not wreck
	var rear_cam := D.faces_cam(rot, -1.0, 0.0)
	for s: float in [-1.0, 1.0]:
		if not D.faces_cam(rot, 0.0, s):
			_running(cv, o, rot, s, f, wreck)
	if door and not rear_cam:
		_doors(cv, o, rot)
	if D.faces_cam(rot, 1.0, 0.0):
		_bay(cv, o, rot, col, wreck, door)
		_cab(cv, o, rot, col, wreck)
	else:
		_cab(cv, o, rot, col, wreck)
		_bay(cv, o, rot, col, wreck, door)
	if door and rear_cam:
		_doors(cv, o, rot)
	var tip := _hmg(cv, o, rot, wreck)
	for s: float in [-1.0, 1.0]:
		if D.faces_cam(rot, 0.0, s):
			_running(cv, o, rot, s, f, wreck)
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, -0.1, 0.0, 12), 6.0, 741)
	elif f == 2:
		L.flash(cv, tip, 1.0)
		L.puff(cv, tip + Vector2(2, -2), 2.0, 0.4)


static func _running(cv, o: Vector2, rot: float, s: float, f: int, wreck: bool) -> void:
	var ay := Vector2(-sin(rot), cos(rot))
	var tr: Dictionary = P.box(cv, o, D.w(rot, -0.2, 0.19 * s, 0), 0.27, 0.045, 6.0, rot, V.TRACK, 0.06, 742)
	for sd in tr.sides:
		if (sd.n as Vector2).dot(ay * s) > 0.7:
			D.track_side(cv, sd.quad, f, wreck, 4)
	if not (wreck and s > 0):
		D.road_wheel(cv, D.sp(o, rot, 0.38, 0.19 * s, 3.5), 3.2, 3.6, f, wreck)


## Open troop bay: riveted walls, dark interior with a few helmets, team band on the long sides.
static func _bay(cv, o: Vector2, rot: float, col: Color, wreck: bool, door: bool) -> void:
	var bay: Dictionary = P.box(cv, o, D.w(rot, -0.2, 0.0, 4), 0.32, 0.2, 8.0, rot, col, 0.08, 743)
	var ax := Vector2(cos(rot), sin(rot))
	for sd in bay.sides:
		var q: PackedVector2Array = sd.quad
		var dd: float = (sd.n as Vector2).dot(ax)
		if wreck:
			V.scorch(cv, q)
		elif absf(dd) < 0.3:
			cv.team = true
			cv.poly(P.sub(q, 0.08, 0.45, 0.92, 0.75), Color(0.62, 0.62, 0.62))
			cv.team = false
			V.rivets(cv, q, 0.9, 7, col)
			V.patch(cv, q, 0.66, 0.08, 0.9, 0.36, V.RUST, 744)
			V.streaks(cv, q, 745)
		elif dd < -0.7 and door:
			cv.poly(P.sub(q, 0.2, 0.05, 0.8, 0.95), Color8(24, 22, 20))
	cv.poly(P.sub(bay.top, 0.07, 0.1, 0.93, 0.9), P.mul(col, 0.42) if not wreck else Color8(30, 28, 26))
	if not wreck:
		for u in [0.3, 0.55, 0.78]:  # helmets of the squad riding in the bay
			for v in [0.32, 0.68]:
				var hp: Vector2 = P.sub(bay.top, u, v, u, v)[0]
				cv.rect(int(hp.x) - 1, int(hp.y) - 1, 3, 2, Color8(84, 80, 64))
				cv.px(int(hp.x) - 1, int(hp.y) - 1, Color8(110, 104, 84))


## Engine bonnet with radiator grille + armoured cab with vision slits (drawn in depth order).
static func _cab(cv, o: Vector2, rot: float, col: Color, wreck: bool) -> void:
	var ax := Vector2(cos(rot), sin(rot))
	var front := D.faces_cam(rot, 1.0, 0.0)
	var parts := [[0.12, 0.07, 0.2, 11.0, 747], [0.36, 0.16, 0.15, 7.0, 748]]
	if not front:
		parts.reverse()
	for pt in parts:
		var r: Dictionary = P.box(cv, o, D.w(rot, pt[0], 0.0, 4), pt[1], pt[2], pt[3], rot, col, 0.08, pt[4])
		for sd in r.sides:
			var q: PackedVector2Array = sd.quad
			var dd: float = (sd.n as Vector2).dot(ax)
			if wreck:
				V.scorch(cv, q)
			elif dd > 0.7 and pt[4] == 748:
				for i in 4:
					var a: Vector2 = P.sub(q, 0.2 + i * 0.2, 0.2, 0.2 + i * 0.2, 0.8)[0]
					var b: Vector2 = P.sub(q, 0.2 + i * 0.2, 0.2, 0.2 + i * 0.2, 0.8)[3]
					cv.line_v(a, b, Color8(36, 32, 28))
			elif dd > 0.7:
				cv.poly(P.sub(q, 0.15, 0.7, 0.85, 0.82), Color8(22, 20, 18))
			else:
				V.rivets(cv, q, 0.85, 4, col)
		if not wreck:
			D.box_edges(cv, r, col, 749)
			if pt[4] == 747:  # team recognition panel on the cab roof (reads from every facing)
				cv.team = true
				cv.poly(P.sub(r.top, 0.18, 0.2, 0.82, 0.8), Color(0.62, 0.62, 0.62))
				cv.team = false


## Pintle HMG with a gun shield on the bay front; returns the muzzle point.
static func _hmg(cv, o: Vector2, rot: float, wreck: bool) -> Vector2:
	var gun: Color = V.GUNMETAL if not wreck else V.BURNT
	var front := D.faces_cam(rot, 1.0, 0.0)
	var tip := D.sp(o, rot, 0.34 if not wreck else 0.2, 0.0, 18.0 if not wreck else 15.0)
	var post := D.sp(o, rot, 0.02, 0.0, 12)
	cv.line_v(post, post + Vector2(0, -5), gun)
	if not front:
		cv.line_v(D.sp(o, rot, 0.02, 0.0, 17.5), tip, gun)
	P.box(cv, o, D.w(rot, 0.06, 0.0, 15), 0.015, 0.08, 5.0, rot, P.mul(V.HULL if not wreck else V.BURNT, 1.05), 0.06, 750)
	if front:
		cv.line_v(D.sp(o, rot, 0.02, 0.0, 17.5), tip, gun)
	return tip


static func _doors(cv, o: Vector2, rot: float) -> void:
	for s: float in [-1.0, 1.0]:
		var r: Dictionary = P.box(cv, o, D.w(rot, -0.6, 0.17 * s, 4), 0.08, 0.012, 7.0, rot, V.HULL, 0.06, 751)
		for sd in r.sides:
			V.rivets(cv, sd.quad, 0.8, 2, V.HULL)


# ---------------------------------------------------------------- b_rocket_truck
static func rocket_truck(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	HB._truck(cv, o, rot, f, wreck, 12.0, func(body: Color) -> void:
		var r: Dictionary = TRK._bed_box(cv, o, rot, body, wreck, 2.5, 760)
		cv.poly(P.sub(r.top, 0.04, 0.06, 0.96, 0.94), P.mul(body, 0.62)))
	var lr := rot + (0.35 if wreck else 0.0)
	var lift := 0.0 if f == 1 or wreck else 4.0
	var steel: Color = V.GUNMETAL if not wreck else V.BURNT
	P.box(cv, o, D.w(rot, -0.32, 0, 7), 0.06, 0.08, 3.0 + lift, rot, steel, 0.06, 761)
	var rack: Dictionary = P.box(cv, o, D.w(lr, -0.2, 0, 9 + lift), 0.3, 0.16, 7.0, lr, V.HULL if not wreck else V.BURNT, 0.08, 762)
	var ax := Vector2(cos(lr), sin(lr))
	for sd in rack.sides:
		var q: PackedVector2Array = sd.quad
		var dd: float = (sd.n as Vector2).dot(ax)
		if wreck:
			V.scorch(cv, q)
		elif absf(dd) > 0.7:  # 2x3 tube mouths, front and back
			for yy in 2:
				for xx in 3:
					var c := P.sub(q, 0.1 + xx * 0.28, 0.16 + yy * 0.42, 0.32 + xx * 0.28, 0.48 + yy * 0.42)
					cv.poly(c, Color8(28, 26, 24))
					if dd > 0.7:
						var m: Vector2 = c[2]
						cv.px(int(m.x), int(m.y), Color8(150, 70, 40))  # warhead tip
		else:
			cv.team = true
			cv.poly(P.sub(q, 0.06, 0.3, 0.94, 0.62), Color(0.62, 0.62, 0.62))
			cv.team = false
			V.rivets(cv, q, 0.9, 7, V.HULL)
			V.streaks(cv, q, 763)
	if not wreck:
		D.box_edges(cv, rack, V.HULL, 764)
		for v in [0.33, 0.66]:
			var ln := P.sub(rack.top, 0.0, v, 1.0, v)
			cv.line_v(ln[0], ln[1], P.mul(V.HULL, 0.7))
	cv.outline(OUTL)
	if wreck:
		V.soot(cv, D.sp(o, rot, -0.2, 0.0, 16), 6.0, 765)
	elif f == 2:  # salvo: three rockets leaving with trails, backblast behind the rack
		for i in 3:
			var a := D.sp(o, lr, 0.12, -0.1 + i * 0.1, 15 + lift)
			var b := D.sp(o, lr, 0.42 + i * 0.07, -0.1 + i * 0.1, 26 + lift + i * 3)
			cv.line_v(a, b, Color(0.86, 0.84, 0.78, 0.55))
			L.flash(cv, b, 0.7)
		L.flash(cv, D.sp(o, lr, 0.12, 0.0, 14 + lift), 1.1)
		L.puff(cv, D.sp(o, lr, -0.55, 0.0, 10 + lift), 4.0, 0.5)
		L.puff(cv, D.sp(o, lr, -0.7, 0.08, 6 + lift), 3.0, 0.35)
