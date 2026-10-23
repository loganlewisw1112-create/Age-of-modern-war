extends RefCounted
## Human B (Industrial) armour (agent ART3-B): b_rebuilt_mbt (tracked, patched, long-barrel cast
## turret) and b_carrier (8-wheel riveted carrier with a shielded HMG). Same box/iso pipeline as
## vehicles.gd. Also hosts the shared industrial detail helpers (rivets, welded patches, rust streaks,
## soot) used by the truck and building modules. Frames idle/move/fire, wrecks 1 frame.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")

const HULL := Color8(110, 96, 66)        # weathered khaki-brown
const RUST := Color8(146, 80, 42)
const PRIMER := Color8(96, 98, 90)       # grey replacement plate
const TRACK := Color8(44, 40, 36)
const GUNMETAL := Color8(60, 58, 54)
const BURNT := Color8(58, 52, 46)
const SOOT := Color8(30, 28, 26)


# ---------------------------------------------------------------- shared industrial details
## Row of rivets near the top (v) of a side quad: lit dot with a dark under-pixel.
static func rivets(cv, q: PackedVector2Array, v: float, n: int, base: Color) -> void:
	for i in n:
		var u := (i + 0.5) / n
		var p: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), v)
		cv.px(int(p.x), int(p.y), P.mul(base, 1.38))
		cv.px(int(p.x), int(p.y) + 1, P.mul(base, 0.62))


## Welded patch plate over a sub-quad: flat colour, bright weld bead on top/left, dark seam below.
static func patch(cv, q: PackedVector2Array, u0: float, v0: float, u1: float, v1: float, col: Color, s: int) -> void:
	var pq := P.sub(q, u0, v0, u1, v1)
	cv.poly(pq, col, P.speckle(0.12, s))
	cv.line_v(pq[3], pq[2], P.mul(col, 1.35))
	cv.line_v(pq[0], pq[3], P.mul(col, 1.2))
	cv.line_v(pq[0], pq[1], P.mul(col, 0.6))


## Vertical rust streaks running down from the top of a side quad (only over existing pixels).
static func streaks(cv, q: PackedVector2Array, s: int, amt := 0.82) -> void:
	cv.poly(P.sub(q, 0.0, 0.25, 1.0, 1.0), RUST, func(x: int, y: int, _b: Color) -> Color:
		if cv.get_px(x, y).a < 0.6 or P.hn(x, 0, s) < amt or P.hn(x, y / 3, s + 1) < 0.35:
			return Color(0, 0, 0, 0)
		return Color(RUST.r, RUST.g, RUST.b, 0.55))


## Soot smudge: dark translucent blotch around a screen point (stack tops, exhausts).
static func soot(cv, p: Vector2, r: float, s: int) -> void:
	for y in range(int(p.y - r), int(p.y + r) + 1):
		for x in range(int(p.x - r), int(p.x + r) + 1):
			var dx := (x + 0.5 - p.x) / r
			var dy := (y + 0.5 - p.y) / r
			if dx * dx + dy * dy <= 1.0 and cv.get_px(x, y).a > 0.6 and P.hn(x, y, s) > 0.3:
				cv.px(x, y, Color(SOOT.r, SOOT.g, SOOT.b, 0.55))


static func scorch(cv, q: PackedVector2Array) -> void:
	cv.poly(q, BURNT, func(x: int, y: int, c: Color) -> Color:
		var h := P.hn(x, y, 929)
		if h > 0.9:
			return P.mix(c, Color8(104, 64, 40), 0.75)
		return P.mul(c, 0.55 + h * 0.4))


# ---------------------------------------------------------------- vehicles
static func draw(cv, def: String, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	if def == "b_carrier":
		_carrier(cv, rot, f, wreck, o)
	else:
		_tank(cv, rot, f, wreck, o)
	cv.outline(Color(0.08, 0.07, 0.06, 1))


static func _tank(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = BURNT if wreck else HULL
	var trot := rot + (0.8 if wreck else 0.0)
	var bl := 0.38 if f != 2 else 0.33
	var toward := cos(trot) + sin(trot) > 0.0
	var parts := []
	for s in [-1, 1]:
		parts.append([D.w(rot, 0, 0.26 * s), 0.6, 0.1, 6.0, rot, TRACK, "track"])
	parts.append([D.w(rot, 0, 0, 5), 0.58, 0.36, 6.0, rot, hull, "hull"])
	parts.append([D.w(trot, -0.3, 0, 11), 0.12, 0.2, 4.0, trot, P.mul(hull, 0.92), "bustle"])
	parts.append([D.w(trot, -0.04, 0, 11), 0.27, 0.24, 6.0, trot, hull, "turret"])
	for p in parts:
		P.box_shadow(cv, o, p[0], p[1], p[2], p[3], p[4])
	cv.flush_shadow()
	for p in parts:
		var kind: String = p[6]
		if kind == "turret" and not toward:
			_tank_barrel(cv, o, trot, bl, wreck)
		var r: Dictionary = P.box(cv, o, p[0], p[1], p[2], p[3], p[4], p[5], 0.11, 40 + kind.length())
		if kind == "track":
			for sd in r.sides:
				if absf((sd.n as Vector2).dot(Vector2(-sin(rot), cos(rot)))) > 0.7:
					if not wreck:
						D.mud(cv, sd.quad, 610 + int(p[0].x * 50), 0.6)
					D.track_side(cv, sd.quad, f, wreck, 5)
			continue
		if wreck:
			scorch(cv, r.top)
			continue
		for sd in r.sides:
			var q: PackedVector2Array = sd.quad
			if kind == "hull":
				patch(cv, q, 0.12, 0.3, 0.38, 0.8, RUST, 611)
				patch(cv, q, 0.6, 0.25, 0.86, 0.75, PRIMER, 612)
				rivets(cv, q, 0.85, 7, hull)
				D.mud(cv, q, 613 + int(q[0].x), 0.35)
			elif kind == "turret":
				cv.team = true
				cv.poly(P.sub(q, 0.1, 0.12, 0.9, 0.7), Color(0.62, 0.62, 0.62))
				cv.team = false
				rivets(cv, q, 0.82, 5, hull)
			streaks(cv, q, 620 + kind.length())
		if kind == "hull":
			D.contact_ao(cv, r)
			D.box_edges(cv, r, hull, 631)
			D.grille(cv, r.top, 0.0, 0.2, 0.2, 0.8, hull, 5)
			D.hatch(cv, r.top, 0.82, 0.55, 0.94, 0.78, hull)
			for s in [-1, 1]:  # twin exhaust stubs with soot on the rear deck
				var ep := D.sp(o, rot, -0.5, 0.2 * s, 11)
				soot(cv, ep, 3.0, 640 + s)
				cv.rect(int(ep.x), int(ep.y) - 1, 2, 2, SOOT)
		elif kind == "bustle":
			for sd in r.sides:  # stowage rack bars
				cv.line_v(sd.quad[0].lerp(sd.quad[3], 0.5), sd.quad[1].lerp(sd.quad[2], 0.5), P.mul(hull, 0.65))
		elif kind == "turret":
			D.box_edges(cv, r, hull, 637)
			D.cupola(cv, o, trot, -0.12, 0.1, 17, hull, false)
			D.hatch(cv, r.top, 0.25, 0.15, 0.48, 0.4, hull)
			cv.team = true  # team-colour stencil panel on the turret roof (the side bands alone are only 1-2 px tall)
			cv.poly(P.sub(r.top, 0.56, 0.22, 0.9, 0.78), Color(0.62, 0.62, 0.62))
			cv.team = false
			D.antenna(cv, D.sp(o, trot, -0.36, -0.14, 17), 11, false)
	if toward:
		_tank_barrel(cv, o, trot, bl, wreck)
	if f == 2 and not wreck:
		var tip := D.sp(o, trot, 0.23 + bl * 2.0 + 0.06, 0, 14.5)
		cv.ellipse(tip.x, tip.y, 2.6, 1.8, Color8(255, 226, 140))
		cv.px(int(tip.x), int(tip.y), Color8(255, 255, 230))


static func _tank_barrel(cv, o: Vector2, trot: float, bl: float, wreck: bool) -> void:
	var col: Color = GUNMETAL if not wreck else BURNT
	var z := 13.5 if not wreck else 11.0
	P.box(cv, o, D.w(trot, 0.22, 0, z - 2), 0.05, 0.11, 4.5, trot, P.mul(BURNT if wreck else HULL, 0.9), 0.05, 650)  # mantlet
	P.box(cv, o, D.w(trot, 0.23 + bl, 0, z), bl, 0.028, 1.8, trot, col, 0.04, 651)
	P.box(cv, o, D.w(trot, 0.23 + bl * 2.0, 0, z - 0.6), 0.045, 0.05, 2.8, trot, P.mul(col, 1.15), 0.04, 652)  # muzzle brake


static func _carrier(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = BURNT if wreck else HULL
	P.box_shadow(cv, o, D.w(rot, 0, 0, 0), 0.54, 0.29, 10.0, rot)
	P.box_shadow(cv, o, D.w(rot, 0.12, 0, 13), 0.08, 0.08, 4.0, rot)
	cv.flush_shadow()
	_wheels(cv, o, rot, f, false, wreck)
	var r: Dictionary = P.box(cv, o, D.w(rot, 0, 0, 3), 0.54, 0.28, 7.0, rot, hull, 0.1, 660)
	var ax := Vector2(cos(rot), sin(rot))
	if wreck:
		scorch(cv, r.top)
	else:
		for sd in r.sides:
			var q: PackedVector2Array = sd.quad
			var d: float = (sd.n as Vector2).dot(ax)
			if absf(d) < 0.3:
				patch(cv, q, 0.55, 0.35, 0.8, 0.85, RUST, 661)
				cv.team = true
				cv.poly(P.sub(q, 0.06, 0.18, 0.5, 0.36), Color(0.64, 0.64, 0.64))
				cv.team = false
				D.mud(cv, q, 662 + int(q[0].x), 0.4)
			elif d > 0.7:  # front: vision slits and headlamp guards
				cv.line_v(P.sub(q, 0.2, 0.7, 0.8, 0.7)[0], P.sub(q, 0.2, 0.7, 0.8, 0.7)[1], D.DARK)
				for u in [0.12, 0.88]:
					var lp: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.4)
					cv.px(int(lp.x), int(lp.y), Color8(226, 214, 160))
				D.tow_hooks(cv, q)
			rivets(cv, q, 0.88, 8, hull)
			streaks(cv, q, 663)
		D.contact_ao(cv, r)
		D.box_edges(cv, r, hull, 664)
	var up: Dictionary = P.box(cv, o, D.w(rot, -0.12, 0, 10), 0.34, 0.22, 3.0, rot, P.mul(hull, 1.04), 0.1, 665)
	if wreck:
		scorch(cv, up.top)
	else:
		D.hatch(cv, up.top, 0.05, 0.15, 0.3, 0.45, hull)
		D.hatch(cv, up.top, 0.05, 0.55, 0.3, 0.85, hull)
		D.grille(cv, up.top, 0.72, 0.6, 0.95, 0.92, hull, 3)
		cv.team = true
		cv.poly(P.sub(up.top, 0.36, 0.2, 0.62, 0.8), Color(0.74, 0.74, 0.74))
		cv.team = false
		D.stowage(cv, o, rot, -0.38, 0.17, 13, 0.06, 0.05, 2.5, true, false)
		D.antenna(cv, D.sp(o, rot, -0.42, -0.18, 13), 12, false)
	# ring mount: gun shield box + HMG barrel
	var grot := rot + (0.9 if wreck else 0.0)
	var toward := cos(grot) + sin(grot) > 0.0
	if not toward:
		P.box(cv, o, D.w(grot, 0.32, 0, 15), 0.2, 0.018, 1.2, grot, GUNMETAL if not wreck else BURNT, 0.04, 667)
	var sh: Dictionary = P.box(cv, o, D.w(rot, 0.12, 0, 13), 0.06, 0.12, 4.0, grot, P.mul(hull, 0.95), 0.06, 666)
	if not wreck:
		D.box_edges(cv, sh, hull, 668, 0.25)
	if toward:
		P.box(cv, o, D.w(grot, 0.32, 0, 15), 0.2, 0.018, 1.2, grot, GUNMETAL if not wreck else BURNT, 0.04, 667)
	_wheels(cv, o, rot, f, true, wreck)
	if f == 2 and not wreck:
		var tip := D.sp(o, grot, 0.55, 0, 16)
		cv.ellipse(tip.x, tip.y, 1.8, 1.3, Color8(255, 226, 140))
		cv.px(int(tip.x), int(tip.y), Color8(255, 255, 230))


static func _wheels(cv, o: Vector2, rot: float, f: int, near: bool, wreck: bool) -> void:
	for s in [-1, 1]:
		if D.faces_cam(rot, 0.0, s) != near:
			continue
		for i in 4:
			var c := D.sp(o, rot, -0.38 + i * 0.25, 0.28 * s, 3)
			D.road_wheel(cv, c, 3.2, 3.0, f, wreck)
			if near and not wreck and P.hn(i, s, 671) > 0.35:
				cv.px(int(c.x), int(c.y) + 2, Color(D.MUD.r, D.MUD.g, D.MUD.b, 0.85))
