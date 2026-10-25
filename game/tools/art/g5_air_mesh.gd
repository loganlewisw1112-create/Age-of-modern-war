extends RefCounted
## G5 aircraft art (agent ART-AIR): a tiny deterministic 3D rasteriser for the aircraft sheets.
## Model space: x = forward (nose), y = right wing, z = up; x / y in "lu" (32 lu = 1 tile, so 1 lu is about
## 1 screen px), z in px. A model fills a Mesh (triangles + z-tested lines + spinning discs + effect marks);
## render() rotates it to world facing `rot`, projects with pix.gd's iso proj, z-buffers it (depth
## D = (wx + wy) * 16 + z, larger = nearer the viewer), shades each triangle by its normal against a
## top-left sun and paints per-pixel material detail anchored in model space (A panel lines, B rivets +
## rust, Machine cyan seams). No randomness: every speckle is an integer hash of model coordinates.
const P = preload("res://tools/art/pix.gd")

const LDIR := Vector3(-0.62, -0.28, 0.73)
const CAM := Vector3(0.5, 0.5, 0.7071)


class AMesh:
	var tris: Array = []    # [Vector3 a, Vector3 b, Vector3 c, String mat]
	var lines: Array = []   # [Vector3 a, Vector3 b, String mat, bool after_outline]
	var discs: Array = []   # {c, n, r, blades, ph, mode: spin | slow | stop}
	var marks: Array = []   # {p, kind, dir, s}
	var xf := Transform3D.IDENTITY

	func tri(a: Vector3, b: Vector3, c: Vector3, m: String) -> void:
		tris.append([xf * a, xf * b, xf * c, m])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, m: String) -> void:
		tri(a, b, c, m)
		tri(a, c, d, m)

	func line(a: Vector3, b: Vector3, m: String, after := false) -> void:
		lines.append([xf * a, xf * b, m, after])

	func disc(c: Vector3, n: Vector3, r: float, blades: int, ph: float, mode: String) -> void:
		discs.append({"c": xf * c, "n": (xf.basis * n).normalized(), "r": r, "blades": blades, "ph": ph, "mode": mode})

	func mark(p: Vector3, kind: String, dir := Vector3(1, 0, 0), s := 1.0) -> void:
		marks.append({"p": xf * p, "kind": kind, "dir": (xf.basis * dir), "s": s})


# ---------------------------------------------------------------- primitives
## Lofted body. rings: [x, hw, zb, zt] (+ optional [4] = y offset). sq < 1 squares the section (B boxy).
static func loft(m: AMesh, rings: Array, mat: String, sq := 1.0, nose_mat := "", n := 8) -> void:
	var vs: Array = []
	for r: Array in rings:
		var ring: Array = []
		var yo: float = r[4] if r.size() > 4 else 0.0
		var zc: float = (r[2] + r[3]) * 0.5
		var hh: float = (r[3] - r[2]) * 0.5
		for i in n:
			var a := (float(i) + 0.5) * TAU / n
			var ca := cos(a)
			var sa := sin(a)
			ca = signf(ca) * pow(absf(ca), sq)
			sa = signf(sa) * pow(absf(sa), sq)
			ring.append(Vector3(r[0], yo + r[1] * ca, zc + hh * sa))
		vs.append(ring)
	for j in vs.size() - 1:
		var mt := mat if (nose_mat == "" or j < vs.size() - 2) else nose_mat
		for i in n:
			var i2 := (i + 1) % n
			m.quad(vs[j][i], vs[j][i2], vs[j + 1][i2], vs[j + 1][i], mt)
	for e in [0, vs.size() - 1]:
		var c := Vector3.ZERO
		for v: Vector3 in vs[e]:
			c += v / float(n)
		for i in n:
			m.tri(c, vs[e][i], vs[e][(i + 1) % n], mat if e == 0 or nose_mat == "" else nose_mat)


## Axis-aligned box (model space, through the current xf): centre c, half extents h.
static func box(m: AMesh, c: Vector3, h: Vector3, mat: String, top_mat := "") -> void:
	var v: Array = []
	for i in 8:
		v.append(c + Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	var tm := mat if top_mat == "" else top_mat
	m.quad(v[4], v[5], v[7], v[6], tm)
	m.quad(v[0], v[1], v[3], v[2], mat)
	m.quad(v[0], v[1], v[5], v[4], mat)
	m.quad(v[2], v[3], v[7], v[6], mat)
	m.quad(v[0], v[2], v[6], v[4], mat)
	m.quad(v[1], v[3], v[7], v[5], mat)


## Flat convex plate (wing / stabiliser) from model-space outline pts (x, y) at height z, thickness th.
## dz: Callable(Vector2) -> float extra height (dihedral) or null.
static func slab(m: AMesh, pts: Array, z: float, th: float, mat: String, dihedral := 0.0) -> void:
	var top: Array = []
	var bot: Array = []
	for p: Vector2 in pts:
		var zz := z + absf(p.y) * dihedral
		top.append(Vector3(p.x, p.y, zz + th * 0.5))
		bot.append(Vector3(p.x, p.y, zz - th * 0.5))
	for i in range(1, pts.size() - 1):
		m.tri(top[0], top[i], top[i + 1], mat)
		m.tri(bot[0], bot[i], bot[i + 1], mat)
	for i in pts.size():
		var j := (i + 1) % pts.size()
		m.quad(bot[i], bot[j], top[j], top[i], mat)


## Mirrored wing pair: root leading/trailing x at y = yr, tip leading/trailing x at y = yt.
static func wings(m: AMesh, rl: float, rt: float, tl: float, tt: float, yr: float, yt: float, z: float,
		th: float, mat: String, dihedral := 0.0) -> void:
	for s: float in [-1.0, 1.0]:
		slab(m, [Vector2(rl, yr * s), Vector2(tl, yt * s), Vector2(tt, yt * s), Vector2(rt, yr * s)], z, th, mat, dihedral)


## Vertical fin: outline pts (x, z) in the plane y = y0, thickness th.
static func fin(m: AMesh, pts: Array, y0: float, th: float, mat: String) -> void:
	var a: Array = []
	var b: Array = []
	for p: Vector2 in pts:
		a.append(Vector3(p.x, y0 - th * 0.5, p.y))
		b.append(Vector3(p.x, y0 + th * 0.5, p.y))
	for i in range(1, pts.size() - 1):
		m.tri(a[0], a[i], a[i + 1], mat)
		m.tri(b[0], b[i], b[i + 1], mat)
	for i in pts.size():
		var j := (i + 1) % pts.size()
		m.quad(a[i], a[j], b[j], b[i], mat)


## Cylinder / cone from a to b (radius r at a, r2 at b), n sides, capped.
static func cyl(m: AMesh, a: Vector3, b: Vector3, r: float, mat: String, r2 := -1.0, n := 6) -> void:
	if r2 < 0.0:
		r2 = r
	var ax := (b - a).normalized()
	var up := Vector3(0, 0, 1) if absf(ax.z) < 0.9 else Vector3(1, 0, 0)
	var u := ax.cross(up).normalized()
	var v := ax.cross(u).normalized()
	var ra: Array = []
	var rb: Array = []
	for i in n:
		var t := (float(i) + 0.5) * TAU / n
		var d := u * cos(t) + v * sin(t)
		ra.append(a + d * r)
		rb.append(b + d * r2)
	for i in n:
		var j := (i + 1) % n
		m.quad(ra[i], ra[j], rb[j], rb[i], mat)
		m.tri(a, ra[i], ra[j], mat)
		m.tri(b, rb[j], rb[i], mat)


## Ducted fan ring (open short cylinder) of radius r around centre c with axis n, depth dp.
static func duct(m: AMesh, c: Vector3, n: Vector3, r: float, dp: float, mat: String, sides := 10) -> void:
	var ax := n.normalized()
	var up := Vector3(0, 0, 1) if absf(ax.z) < 0.9 else Vector3(1, 0, 0)
	var u := ax.cross(up).normalized()
	var v := ax.cross(u).normalized()
	for i in sides:
		var t0 := float(i) * TAU / sides
		var t1 := float(i + 1) * TAU / sides
		var p0 := c + (u * cos(t0) + v * sin(t0)) * r
		var p1 := c + (u * cos(t1) + v * sin(t1)) * r
		m.quad(p0 - ax * dp * 0.5, p1 - ax * dp * 0.5, p1 + ax * dp * 0.5, p0 + ax * dp * 0.5, mat)


# ---------------------------------------------------------------- projection
static func to_w(v: Vector3, ca: float, sa: float) -> Vector3:
	var lx := v.x / 32.0
	var ly := v.y / 32.0
	return Vector3(lx * ca - ly * sa, lx * sa + ly * ca, v.z)


static func scr(o: Vector2, w: Vector3) -> Vector2:
	return P.proj(o, w)


static func depth(w: Vector3) -> float:
	return (w.x + w.y) * 16.0 + w.z


## Screen point of a model point (for overlays).
static func sp(o: Vector2, rot: float, v: Vector3) -> Vector2:
	return scr(o, to_w(v, cos(rot), sin(rot)))
