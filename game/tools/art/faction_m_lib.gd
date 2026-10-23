extends RefCounted
## Machine (Autonomous Network) art helpers + palette (agent ART3-M). Graphite and off-white panels,
## cyan/teal emissive seams, hexagonal modules, no windows. Deterministic (integer hashes only).
const P = preload("res://tools/art/pix.gd")

const GRAPH := Color8(64, 68, 72)
const GRAPH_D := Color8(44, 47, 51)
const PANEL := Color8(172, 175, 168)
const PANEL_D := Color8(136, 139, 134)
const JOINT := Color8(30, 33, 36)
const CYAN := Color8(86, 222, 216)
const CYAN_HOT := Color8(206, 255, 250)
const TEAL := Color8(34, 120, 122)
const DEAD := Color8(56, 54, 52)       # wreck char
const DEAD_D := Color8(38, 36, 35)
const DEAD_SEAM := Color8(52, 66, 66)  # cold, unlit seam
const SLAB := Color8(84, 88, 90)
const RAW := Color8(118, 124, 126)     # freshly printed material


## Local (forward, right) offset in tiles + z (px) -> world point for something facing `rot`.
static func w(rot: float, fwd: float, right: float, z: float = 0.0) -> Vector3:
	return Vector3(cos(rot) * fwd - sin(rot) * right, sin(rot) * fwd + cos(rot) * right, z)


static func sp(o: Vector2, rot: float, fwd: float, right: float, z: float) -> Vector2:
	return P.proj(o, w(rot, fwd, right, z))


## Hex prism centred at c (tiles; z = bottom px), circumradius r (tiles), height hz (px), rotated by
## `rot`. sq < 1 squashes it along the local right axis (elongated hex). Same return shape as P.box.
static func hexp(cv, o: Vector2, c: Vector3, r: float, hz: float, rot: float, col: Color,
		s: int = 1, top_col = null, sq: float = 1.0) -> Dictionary:
	var gb: Array = []
	var gt: Array = []
	var loc: Array = []
	for i in 6:
		var a := i * PI / 3.0
		var l := Vector2(cos(a) * r, sin(a) * r * sq)
		loc.append(l)
		var p3 := Vector3(c.x, c.y, 0) + w(rot, l.x, l.y)
		gb.append(P.proj(o, Vector3(p3.x, p3.y, c.z)))
		gt.append(P.proj(o, Vector3(p3.x, p3.y, c.z + hz)))
	var out := {"sides": [], "top": PackedVector2Array(gt)}
	for i in 6:
		var j := (i + 1) % 6
		var mid: Vector2 = (loc[i] + loc[j]) * 0.5
		var n3 := w(rot, mid.x, mid.y)
		var n := Vector2(n3.x, n3.y).normalized()
		if n.x + n.y <= 0.001 or hz <= 0.0:
			continue
		var q := PackedVector2Array([gb[i], gb[j], gt[j], gt[i]])
		cv.poly(q, P.mul(col, P.side_shade(n)), P.speckle(0.06, s + i))
		out.sides.append({"quad": q, "n": n})
	var tc: Color = col if top_col == null else top_col
	cv.poly(out.top, P.mul(tc, 1.06), P.speckle(0.05, s + 9))
	return out


## Shadow of a hex prism (or any footprint radius r) into cv.sh, cast toward world +x/+y.
static func hex_shadow(cv, o: Vector2, c: Vector3, r: float, hz: float, rot: float, sq: float = 1.0) -> void:
	var off := Vector2(0.9, 0.35) * (c.z + hz) / 32.0
	var pts := PackedVector2Array()
	for i in 6:
		var a := i * PI / 3.0
		var p3 := Vector3(c.x, c.y, 0) + w(rot, cos(a) * r, sin(a) * r * sq)
		pts.append(P.proj(o, Vector3(p3.x, p3.y, 0)))
		pts.append(P.proj(o, Vector3(p3.x + off.x, p3.y + off.y, 0)))
	cv.poly(Geometry2D.convex_hull(pts), Color.BLACK, Callable(), true)


## Emissive seam across a side quad at height fraction v (0 = bottom, 1 = top). Dead = cold seam.
static func seam(cv, q: PackedVector2Array, v: float, dead := false, u0 := 0.0, u1 := 1.0) -> void:
	var a: Vector2 = q[0].lerp(q[1], u0).lerp(q[3].lerp(q[2], u0), v)
	var b: Vector2 = q[0].lerp(q[1], u1).lerp(q[3].lerp(q[2], u1), v)
	if dead:
		cv.line_v(a, b, DEAD_SEAM)
		return
	cv.line_v(a + Vector2(0, 1), b + Vector2(0, 1), Color(TEAL.r, TEAL.g, TEAL.b, 0.55))
	cv.line_v(a, b, CYAN)


## Dark vertical panel joints across a side quad.
static func joints(cv, q: PackedVector2Array, us: Array, col: Color) -> void:
	for u in us:
		var a: Vector2 = q[0].lerp(q[1], u)
		var b: Vector2 = q[3].lerp(q[2], u)
		cv.line_v(a, b, P.mul(col, 0.62))


## Lit rim along the top edges of visible sides.
static func rims(cv, r: Dictionary, col: Color) -> void:
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		cv.line_v(q[3], q[2], P.mul(col, 1.3))


## Small glowing light (sensor eye / status lamp).
static func eye(cv, p: Vector2, big := false, dead := false) -> void:
	if dead:
		cv.px(int(p.x), int(p.y), JOINT)
		return
	if big:
		cv.ellipse(p.x + 0.5, p.y + 0.5, 2.6, 2.0, Color(CYAN.r, CYAN.g, CYAN.b, 0.35))
		cv.px(int(p.x) + 1, int(p.y), CYAN)
		cv.px(int(p.x) - 1, int(p.y), CYAN)
	cv.px(int(p.x), int(p.y), CYAN_HOT)


## Two-segment mechanical leg: hip -> knee (pushed outward + up) -> foot, `th` px thick.
static func leg(cv, o: Vector2, hip: Vector3, foot: Vector3, out_dir: Vector2, knee_up: float,
		col: Color, th := 2, dead := false) -> void:
	var mid := (hip + foot) * 0.5
	var knee := Vector3(mid.x + out_dir.x, mid.y + out_dir.y, maxf(hip.z, foot.z) + knee_up)
	var ph := P.proj(o, hip)
	var pk := P.proj(o, knee)
	var pf := P.proj(o, foot)
	for t in th:
		cv.line_v(ph + Vector2(t, 0), pk + Vector2(t, 0), P.mul(col, 1.15 if t == 0 else 0.85))
		cv.line_v(pk + Vector2(t, 0), pf + Vector2(t, 0), P.mul(col, 1.0 if t == 0 else 0.75))
	cv.rect(int(pk.x), int(pk.y), th, 1, JOINT)
	if not dead and th >= 2:
		cv.px(int(pk.x), int(pk.y) - 1, P.mul(col, 1.4))
	cv.rect(int(pf.x) - 1, int(pf.y), th + 2, 1, JOINT)  # foot pad


## Team-coloured inset panel on a quad (top or side) via the team mask.
static func team_panel(cv, q: PackedVector2Array, u0: float, v0: float, u1: float, v1: float, lum := 0.72) -> void:
	cv.team = true
	cv.poly(P.sub(q, u0, v0, u1, v1), Color(lum, lum, lum))
	cv.team = false


## Hex vent / plate drawn flat on a top quad at (u, v).
static func hex_plate(cv, top: PackedVector2Array, u: float, v: float, rpx: float, col: Color, glow := false) -> void:
	var c: Vector2 = top[0].lerp(top[1], u).lerp(top[3].lerp(top[2], u), v)
	var pts := PackedVector2Array()
	for i in 6:
		var a := i * PI / 3.0
		pts.append(c + Vector2(cos(a) * rpx, sin(a) * rpx * 0.5))
	cv.poly(pts, col)
	if glow:
		cv.px(int(c.x), int(c.y), CYAN)


## Holographic lattice of a box footprint (construction): cyan edges of the full-height volume.
static func holo_box(cv, o: Vector2, c: Vector3, hx: float, hy: float, hz: float, a := 0.55) -> void:
	var col := Color(CYAN.r, CYAN.g, CYAN.b, a)
	var corners: Array = []
	for l in [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]:
		corners.append([P.proj(o, Vector3(c.x + l.x, c.y + l.y, c.z)), P.proj(o, Vector3(c.x + l.x, c.y + l.y, c.z + hz))])
	for i in 4:
		var j := (i + 1) % 4
		cv.line_v(corners[i][1], corners[j][1], col)
		if i != 0:
			cv.line_v(corners[i][0], corners[i][1], col)
	for i in [1, 2]:
		cv.line_v(corners[i][0], corners[i + 1][0], col)
