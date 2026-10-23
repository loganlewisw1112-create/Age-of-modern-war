extends RefCounted
## Vehicle detail helpers (agent E2 detail pass): road wheels, track links, hatches, cupola,
## antenna whips, stowage, smoke launchers, grilles, tow hooks, mud, chipped edges and ambient
## occlusion. Everything is deterministic (integer hashes only).
const P = preload("res://tools/art/pix.gd")

const MUD := Color8(98, 80, 56)
const MUD_D := Color8(70, 56, 40)
const DARK := Color8(24, 24, 22)
const RUBBER := Color8(34, 34, 32)
const RIM := Color8(84, 86, 78)
const VISION := Color8(126, 168, 176)
const STOW := Color8(86, 90, 64)
const CAN := Color8(74, 84, 56)
const BURNT := Color8(58, 52, 46)


## Local (forward, right) offset in tiles + z (px) -> world point for a vehicle at origin facing `rot`.
static func w(rot: float, fwd: float, right: float, z: float = 0.0) -> Vector3:
	return Vector3(cos(rot) * fwd - sin(rot) * right, sin(rot) * fwd + cos(rot) * right, z)


static func sp(o: Vector2, rot: float, fwd: float, right: float, z: float) -> Vector2:
	return P.proj(o, w(rot, fwd, right, z))


## True when the local direction (fwd, right) points toward the camera (screen-down).
static func faces_cam(rot: float, fwd: float, right: float) -> bool:
	var v := w(rot, fwd, right)
	return v.x + v.y > 0.001


## Shade callable that only paints over already-opaque pixels (no halo outside the sprite).
static func clipped(cv, c: Color) -> Callable:
	return func(x: int, y: int, _b: Color) -> Color:
		return c if cv.get_px(x, y).a > 0.6 else Color(0, 0, 0, 0)


## Soft ambient occlusion: a translucent dark footprint (slightly grown, pushed away from the light)
## painted on the surface below a part, clipped to existing pixels.
static func ao(cv, o: Vector2, c: Vector3, hx: float, hy: float, rot: float, a := 0.36, grow := 1.22) -> void:
	var ax := Vector2(cos(rot), sin(rot))
	var ay := Vector2(-sin(rot), cos(rot))
	var pts := PackedVector2Array()
	for l in [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]:
		var w2: Vector2 = Vector2(c.x, c.y) + (ax * l.x + ay * l.y) * grow + Vector2(0.03, 0.02)
		pts.append(P.proj(o, Vector3(w2.x, w2.y, c.z)))
	cv.poly(pts, Color(0, 0, 0, a), clipped(cv, Color(0, 0, 0, a)))


## Mud splatter on the lower part of a side quad (heavier near the ground).
static func mud(cv, q: PackedVector2Array, s: int, top := 0.45) -> void:
	var f := func(x: int, y: int, _b: Color) -> Color:
		var n := P.vnoise(x, y, 2.2, s)
		var h := P.hn(x, y, s + 3)
		if n > 0.58 or h > 0.93:
			return Color(MUD.r, MUD.g, MUD.b, 0.82)
		if n > 0.47:
			return Color(MUD_D.r, MUD_D.g, MUD_D.b, 0.4)
		return Color(0, 0, 0, 0)
	cv.poly(P.sub(q, 0.0, 0.0, 1.0, top), MUD, f)
	cv.poly(P.sub(q, 0.0, 0.0, 1.0, top * 0.4), MUD, func(x: int, y: int, _b: Color) -> Color:
		return Color(MUD_D.r, MUD_D.g, MUD_D.b, 0.55) if P.hn(x, y, s + 9) > 0.35 else Color(0, 0, 0, 0))


## Chipped paint + a faint rim highlight along an edge.
static func chips(cv, a: Vector2, b: Vector2, base: Color, s: int, rim := 0.14) -> void:
	var n := maxi(1, int(a.distance_to(b)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var h := P.hn(int(p.x), int(p.y), s)
		if h > 0.84:
			cv.px(int(p.x), int(p.y), P.mul(base, 1.5))
		elif h < 0.07:
			cv.px(int(p.x), int(p.y), P.mul(base, 0.55))
		elif rim > 0.0:
			cv.px(int(p.x), int(p.y), Color(1, 1, 0.92, rim))


## Highlight/chip the top edges of every visible side face of a box result.
static func box_edges(cv, r: Dictionary, base: Color, s: int, rim := 0.14) -> void:
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		chips(cv, q[3], q[2], base, s, rim)


## Dark contact line along the bottom edge of the visible sides (hull meets tracks / wheels).
static func contact_ao(cv, r: Dictionary) -> void:
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		cv.line_v(q[0], q[1], Color(0, 0, 0, 0.5))
		cv.line_v(q[0] + Vector2(0, -1), q[1] + Vector2(0, -1), Color(0, 0, 0, 0.22))


## A road wheel / tyre with rim, hub and an upper-left highlight. `f` = 1 offsets the spokes (motion).
static func road_wheel(cv, c: Vector2, rx: float, ry: float, f: int, wreck: bool) -> void:
	var tyre := RUBBER if not wreck else Color8(30, 26, 24)
	var rim := RIM if not wreck else Color8(74, 56, 42)
	cv.ellipse(c.x, c.y, rx, ry, tyre)
	cv.ellipse(c.x - 0.15, c.y - 0.15, rx * 0.56, ry * 0.56, rim)
	cv.px(int(floor(c.x - rx * 0.45)), int(floor(c.y - ry * 0.55)), P.mul(rim, 1.4))
	cv.px(int(floor(c.x)), int(floor(c.y)), DARK if not wreck else Color8(40, 30, 24))
	if not wreck:
		var k := 1 if f == 1 else -1
		cv.px(int(floor(c.x + k * rx * 0.75)), int(floor(c.y + ry * 0.2)), P.mul(tyre, 1.7))


## Tracked running gear on a track box's long faces: road wheels, return-roller run, link teeth.
static func track_side(cv, q: PackedVector2Array, f: int, wreck: bool, nwheels := 6) -> void:
	var span := absf(q[1].x - q[0].x)
	var link := Color8(28, 28, 26) if not wreck else Color8(34, 30, 26)
	var top := Color8(70, 68, 62) if not wreck else Color8(66, 52, 42)
	var n := maxi(4, int(q[0].distance_to(q[1]) / 2.0))
	for i in n:  # link teeth along the bottom and top runs
		var u := (i + (0.5 if f == 1 else 0.0)) / n
		var a: Vector2 = q[0].lerp(q[1], u)
		var b: Vector2 = q[3].lerp(q[2], u)
		cv.px(int(a.x), int(a.y) - 1, link)
		cv.px(int(b.x), int(b.y), P.mul(top, 0.8) if i % 2 == 0 else top)
	cv.line_v(q[3].lerp(q[0], 0.12), q[2].lerp(q[1], 0.12), top)  # sunlit top run
	if span < 9.0:
		return
	var k := clampf(span / q[0].distance_to(q[1]), 0.55, 1.0)
	for i in nwheels:
		var u := 0.09 + (i + 0.5) * 0.82 / nwheels
		var c: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.48)
		road_wheel(cv, c, 1.9 * k + 0.3, 2.0, f, wreck)
	# drive sprocket / idler at the ends
	for u in [0.05, 0.95]:
		var c: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.55)
		cv.px(int(c.x), int(c.y), P.mul(top, 1.2))


## Flat hatch on a top quad: darker plate, lit rim on the upper-left, hinge dot.
static func hatch(cv, top: PackedVector2Array, u0: float, v0: float, u1: float, v1: float, base: Color) -> void:
	var q := P.sub(top, u0, v0, u1, v1)
	cv.poly(q, P.mul(base, 0.74))
	cv.line_v(q[0], q[1], P.mul(base, 1.25))
	cv.line_v(q[0], q[3], P.mul(base, 1.18))
	var c: Vector2 = (q[0] + q[2]) * 0.5
	cv.px(int(c.x), int(c.y), P.mul(base, 0.5))


## Commander cupola: a small box with vision blocks on its visible sides and a hatch on top.
static func cupola(cv, o: Vector2, rot: float, fwd: float, right: float, z: float, base: Color, wreck: bool) -> void:
	var r: Dictionary = P.box(cv, o, w(rot, fwd, right, z), 0.075, 0.075, 2.6, rot, P.mul(base, 0.96), 0.05, 61)
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		var c: Vector2 = q[3].lerp(q[2], 0.5).lerp(q[0].lerp(q[1], 0.5), 0.35)
		cv.px(int(c.x), int(c.y), VISION if not wreck else DARK)
	var t: PackedVector2Array = r.top
	var m: Vector2 = (t[0] + t[2]) * 0.5
	cv.ellipse(m.x, m.y, 2.0, 1.2, P.mul(base, 0.72) if not wreck else DARK)
	cv.px(int(m.x) - 1, int(m.y) - 1, P.mul(base, 1.3))


## Antenna whip: thin, slightly leaning line with a lighter tip. Wrecks keep a snapped stub.
static func antenna(cv, base: Vector2, length: int, wreck: bool) -> void:
	var ln := length if not wreck else 3
	var tip := base + Vector2(1 if ln > 6 else 0, -ln)
	cv.px(int(base.x), int(base.y), Color8(50, 52, 48))
	cv.px(int(base.x) + 1, int(base.y), Color8(36, 36, 34))
	cv.line_v(base + Vector2(0, -1), tip, Color8(30, 31, 29))
	if not wreck:
		cv.px(int(tip.x), int(tip.y), Color8(120, 120, 110))


## Cluster of three smoke-grenade launcher tubes at a screen point.
static func smoke_launchers(cv, p: Vector2, wreck: bool) -> void:
	var d := Color8(38, 40, 36) if not wreck else Color8(36, 30, 26)
	cv.px(int(p.x), int(p.y), d)
	cv.px(int(p.x) + 1, int(p.y), d)
	cv.px(int(p.x), int(p.y) - 1, d)
	cv.px(int(p.x) + 1, int(p.y) - 1, P.mul(d, 1.8))


## Louvred grille (exhaust / engine deck): slats across a sub-quad of a top face.
static func grille(cv, top: PackedVector2Array, u0: float, v0: float, u1: float, v1: float, base: Color, slats := 4) -> void:
	var q := P.sub(top, u0, v0, u1, v1)
	cv.poly(q, P.mul(base, 0.62))
	for i in slats:
		var t := (i + 0.5) / slats
		cv.line_v(q[0].lerp(q[1], t), q[3].lerp(q[2], t), P.mul(base, 0.95))


## Tow hooks: two dark nubs at the bottom corners of a visible front/rear face.
static func tow_hooks(cv, q: PackedVector2Array) -> void:
	for u in [0.2, 0.8]:
		var p: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), 0.25)
		cv.px(int(p.x), int(p.y), DARK)
		cv.px(int(p.x), int(p.y) + 1, Color8(60, 58, 52))


## A small stowage box (or jerrycan when `can`) as a real 3D box with a lid line.
static func stowage(cv, o: Vector2, rot: float, fwd: float, right: float, z: float, hx: float, hy: float,
		hz: float, can: bool, wreck: bool) -> void:
	var col := (CAN if can else STOW) if not wreck else BURNT
	var r: Dictionary = P.box(cv, o, w(rot, fwd, right, z), hx, hy, hz, rot, col, 0.06, 71 + int(can))
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		cv.line_v(q[0].lerp(q[3], 0.7), q[1].lerp(q[2], 0.7), P.mul(col, 0.7))
	if not wreck:
		box_edges(cv, r, col, 83, 0.3)
