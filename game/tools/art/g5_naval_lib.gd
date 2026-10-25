extends RefCounted
## G5 naval art helpers (agent ART-NAV, CONTRACTS_G5 s3.3 / s8). Same sheet layout as g4_units_lib:
## rows = 8 facings (world angle k * 45 deg), columns = named frames, greyscale `_mask.png` twin.
## A ship is drawn floating: the water layer (waterline shadow, foam, bow wave, oil slick) is painted
## first by inverse iso projection onto the z = 0 plane, then the hull prism and the deck parts on top,
## so the hull hides the water behind it. Everything is clipped at z = 0 after a `sink` (px) offset, which
## gives the sinking frames and the half-submerged wreck for free. Water-layer alpha stays < 0.6 so the
## outline pass never rims foam. Deterministic: integer hashes only, no RNG.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")

const FOAM := Color(0.93, 0.97, 1.0)
const WATER_SH := Color(0.02, 0.07, 0.12, 0.34)
const BURNT := Color8(58, 52, 46)
const OUTL := Color(0.08, 0.09, 0.1, 1)
const SINK_FRAMES := ["sink_0", "sink_1", "sink_2", "sink_3"]
const SINK_K := [0.1, 0.32, 0.56, 0.86]        # fraction of shape.depth submerged per sinking frame
const WAKE_FRAMES := 3


## Frame size for a hull of half length L and half beam B (tiles) with parts up to H px above the water.
static func frame_spec(sh: Dictionary) -> Dictionary:
	var r := sqrt(float(sh.L) * float(sh.L) + float(sh.B) * float(sh.B))
	var xh := int(ceil(45.3 * r)) + 5
	var up := int(ceil(22.7 * r + float(sh.H))) + 5
	var dn := int(ceil(22.7 * r)) + 6
	return {"fw": xh * 2, "fh": up + dn, "pivot": [xh, up]}


## Relative half beam at t = fwd / L (-1 stern .. 1 bow). bow: 0 blunt (ramp bows) .. 1 sharp.
static func half_beam(t: float, bow: float) -> float:
	if t > 1.0 or t < -1.0:
		return 0.0
	if t > 0.3:
		var u := (t - 0.3) / 0.7
		return maxf(0.0, lerpf(1.0, 1.0 - pow(u, 1.8), bow))
	if t < -0.85:
		return 1.0 - pow((-t - 0.85) / 0.15, 2.0) * 0.25
	return 1.0


## Approximate distance (tiles, negative inside) from local (f, r) to the hull waterline.
static func dist(f: float, r: float, sh: Dictionary) -> float:
	var lh: float = sh.L
	var b: float = sh.B
	var t := f / lh
	if t > 1.0:
		return (f - lh) + maxf(0.0, absf(r) - b * half_beam(1.0, sh.bow))
	if t < -1.0:
		return (-lh - f) + maxf(0.0, absf(r) - b * half_beam(-1.0, sh.bow))
	return absf(r) - b * half_beam(t, sh.bow)


## Hull outline in local (fwd, right) tiles: right side stern -> bow, then left side bow -> stern.
static func outline(sh: Dictionary) -> Array:
	var ts := [-1.0, -0.95, -0.85, -0.5, 0.0, 0.3, 0.5, 0.7, 0.85, 0.95, 1.0]
	var pts: Array = []
	for t: float in ts:
		pts.append(Vector2(t * sh.L, sh.B * half_beam(t, sh.bow)))
	for i in range(ts.size() - 1, -1, -1):
		var p := Vector2(ts[i] * sh.L, -sh.B * half_beam(ts[i], sh.bow))
		if p.distance_to(pts[pts.size() - 1]) > 0.0001:
			pts.append(p)
	return pts


## Water-layer mode for a frame state.
static func mode(st: Dictionary) -> String:
	if bool(st.wreck) and int(st.stage) < 0:
		return "wreck"
	if int(st.stage) >= 0:
		return "sink"
	if String(st.f).ends_with("move"):
		return "move"
	return "idle"


## Screen bounding rect (clamped to the canvas) of a local box on the water plane.
static func bbox(cv, o: Vector2, rot: float, f0: float, f1: float, r0: float, r1: float) -> Rect2i:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for f in [f0, f1]:
		for r in [r0, r1]:
			var p := D.sp(o, rot, f, r, 0.0)
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	var a := Vector2i(clampi(int(floor(mn.x)), 0, cv.w), clampi(int(floor(mn.y)), 0, cv.h))
	var b := Vector2i(clampi(int(ceil(mx.x)) + 1, 0, cv.w), clampi(int(ceil(mx.y)) + 1, 0, cv.h))
	return Rect2i(a, b - a)


## Inverse iso projection of a pixel centre onto the z = 0 plane, in the ship's local (fwd, right).
static func local(o: Vector2, rot: float, x: int, y: int) -> Vector2:
	var sx := (x + 0.5 - o.x) / 32.0
	var sy := (y + 0.5 - o.y) / 16.0
	var wx := (sx + sy) * 0.5
	var wy := (sy - sx) * 0.5
	return Vector2(wx * cos(rot) + wy * sin(rot), -wx * sin(rot) + wy * cos(rot))


static func _fa(a: float) -> Color:
	return Color(FOAM.r, FOAM.g, FOAM.b, minf(a, 0.55))


## Waterline shadow + foam / bow wave / stern wash / oil slick around the hull (under the ship).
static func water(cv, o: Vector2, rot: float, sh: Dictionary, st: Dictionary) -> void:
	var md := mode(st)
	var stage := int(st.stage)
	var lh: float = sh.L
	var pad := 0.5
	var bb := bbox(cv, o, rot, -lh - pad, lh + pad, -float(sh.B) - pad, float(sh.B) + pad)
	for y in range(bb.position.y, bb.end.y):
		for x in range(bb.position.x, bb.end.x):
			var q := local(o, rot, x, y)
			var d := dist(q.x, q.y, sh)
			var n := P.hn(x, y, 4513)
			var c := Color(0, 0, 0, 0)
			if d < 0.0:
				c = WATER_SH
			elif md == "idle":
				if d < 0.045 and n > 0.2:
					c = _fa(0.42)
				elif d < 0.16:
					c = Color(WATER_SH.r, WATER_SH.g, WATER_SH.b, 0.3 * (1.0 - d / 0.16))
			elif md == "move":
				var bw := 0.06 + 0.13 * clampf((q.x / lh - 0.4) / 0.6, 0.0, 1.0)
				if q.x < -lh * 0.85:
					bw += 0.09
				if d < bw and n > 0.12:
					c = _fa(0.52 - 0.2 * d / bw)
				elif d < bw + 0.12:
					c = Color(WATER_SH.r, WATER_SH.g, WATER_SH.b, 0.26)
			elif md == "sink":
				var ring := 0.07 + 0.06 * stage
				if d < ring and n > 0.2 and P.vnoise(x, y, 3.0, 61 + stage) > 0.42:
					c = _fa(0.5)
				elif d < 0.14 + 0.12 * stage and P.vnoise(x, y, 4.0, 77) > 0.45:
					c = Color(0.05, 0.05, 0.04, 0.34)
			else:
				if d < 0.05 and n > 0.4:
					c = _fa(0.36)
				elif d < 0.24 and P.vnoise(x, y, 4.0, 91) > 0.5:
					c = Color(0.2, 0.17, 0.1, 0.3)
			if c.a > 0.0:
				cv.px(x, y, c)


## Hull prism from the waterline (z = max(0, -sink)) to the deck (F - sink). Returns {top, sides, zt}.
## sides: [{quad: [wl_i, wl_j, dk_j, dk_i], n: world normal}] for camera-facing faces only.
static func hull(cv, o: Vector2, rot: float, sh: Dictionary, col: Color, deck: Color, sink: float, s: int) -> Dictionary:
	var zt: float = float(sh.F) - sink
	var zb := maxf(0.0, -sink)
	var res := {"top": PackedVector2Array(), "sides": [], "zt": zt}
	if zt <= 0.5:
		return res
	var pts := outline(sh)
	var wl: Array = []
	var dk: Array = []
	for p: Vector2 in pts:
		wl.append(D.sp(o, rot, p.x * 0.97, p.y * 0.86, zb))
		dk.append(D.sp(o, rot, p.x, p.y, zt))
	var c := cos(rot)
	var sn := sin(rot)
	for i in pts.size():
		var j := (i + 1) % pts.size()
		var e: Vector2 = pts[j] - pts[i]
		var nl := Vector2(-e.y, e.x).normalized()
		var nw := Vector2(c * nl.x - sn * nl.y, sn * nl.x + c * nl.y)
		if nw.x + nw.y <= 0.001:
			continue
		var q := PackedVector2Array([wl[i], wl[j], dk[j], dk[i]])
		cv.poly(q, P.mul(col, P.side_shade(nw)), P.speckle(0.07, s + i))
		res.sides.append({"quad": q, "n": nw})
	res.top = PackedVector2Array(dk)
	cv.poly(res.top, deck, P.speckle(0.08, s + 31))
	return res


## Box part clipped at the water after `sink`. Returns P.box's {top, sides} or {} when submerged.
static func zbox(cv, o: Vector2, rot: float, f: float, r: float, z: float, hx: float, hy: float, hz: float,
		col: Color, sink: float, s: int, ro := 0.0, top_col = null) -> Dictionary:
	var zz := z - sink
	if zz + hz <= 0.5:
		return {}
	if zz < 0.0:
		hz += zz
		zz = 0.0
	return P.box(cv, o, D.w(rot, f, r, zz), hx, hy, hz, rot + ro, col, 0.07, s, top_col)


## Screen point of local (f, r, z) after sink, or null when under water.
static func zp(o: Vector2, rot: float, f: float, r: float, z: float, sink: float):
	if z - sink < 0.0:
		return null
	return D.sp(o, rot, f, r, z - sink)


## Straight gun barrel from local base (f, r, z) along `yaw` (relative to the hull) for `ln` tiles,
## rising `elev` px. Returns the muzzle point (or null when the base is submerged).
static func barrel(cv, o: Vector2, rot: float, f: float, r: float, z: float, yaw: float, ln: float, elev: float,
		col: Color, sink: float, thick := false):
	var a = zp(o, rot, f, r, z, sink)
	if a == null:
		return null
	var b := D.sp(o, rot, f + cos(yaw) * ln, r + sin(yaw) * ln, z + elev - sink)
	cv.line_v(a, b, col)
	if thick:
		cv.line_v(a + Vector2(0, 1), b + Vector2(0, 1), P.mul(col, 0.7))
	return b


## Mast from z0 up h px with a yard and an optional radar bar on top. Returns the top point or null.
static func mast(cv, o: Vector2, rot: float, f: float, z0: float, h: float, col: Color, sink: float, yard := 0.1):
	var a = zp(o, rot, f, 0.0, maxf(z0, sink), sink)
	if z0 + h - sink <= 0.0 or a == null:
		return null
	var top := D.sp(o, rot, f, 0.0, z0 + h - sink)
	cv.line_v(a, top, col)
	if yard > 0.0:
		var y0 := D.sp(o, rot, f, -yard, z0 + h * 0.72 - sink)
		var y1 := D.sp(o, rot, f, yard, z0 + h * 0.72 - sink)
		cv.line_v(y0, y1, P.mul(col, 1.15))
	return top


## Painter's order for deck parts: [f, r, Callable()] sorted far -> near for this facing.
static func draw_parts(rot: float, parts: Array) -> void:
	var c := cos(rot)
	var s := sin(rot)
	parts.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] * (c + s) + a[1] * (c - s) < b[0] * (c + s) + b[1] * (c - s))
	for p: Array in parts:
		(p[2] as Callable).call()


## Faction colour after damage: wreck / sinking stages blend toward burnt steel.
static func pal(col: Color, st: Dictionary) -> Color:
	var stage := int(st.stage)
	if stage >= 0:
		return P.mix(col, BURNT, [0.2, 0.45, 0.6, 0.68][stage])
	return P.mix(col, BURNT, 0.62) if bool(st.wreck) else col


static func live(st: Dictionary) -> bool:
	return not bool(st.wreck) and int(st.stage) < 0
