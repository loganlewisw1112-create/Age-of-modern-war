extends RefCounted
## DL7-3 faceted model renderer (owner: ARTCN7; rev3, 2026-10-27). Vehicles and aircraft are modelled in real
## metres (local f = forward, r = right, z = up) and rasterised straight to pixels at the ONE real-world scale
## (fact art.scale): 4 m per 64x32 tile, 9.8 px per metre of height. Every face is a flat polygon shaded from its
## 3D normal (one light from the upper left), with bevel highlights on its lit edges and creases on its dark
## edges, so hulls read as sloped, faceted armour rather than boxes. Pure and deterministic.
##
## A scene S is an Array of parts {f: faces, layer, c: centroid, bias, dec: decals}. Parts are painted by
## (layer, depth); faces inside a part are back-face culled and depth sorted. Builders take a pose T
## (pose()) so sub-assemblies (gun pods, fans, wheels) carry their own rotation.
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")

const MT := 4.0                                   # metres per tile
const ZP := 9.8                                   # px per metre of height (2:1 dimetric, 30 deg elevation)
const VIEW := Vector3(0.6124, 0.6124, 0.5)        # toward the camera (world metres)
const LIGHT := Vector3(-0.5, 0.35, 0.79)        # toward the light: upper left of the screen, high
const SHADOW := Color(0.03, 0.04, 0.03, 0.40)


# ------------------------------------------------------------------ poses
## Pose: pivot pixel o, world position pos (metres; z = height above ground), yaw (rad), pitch (nose up +),
## roll (right side down +). Child poses: sub(T, local offset, yaw, pitch).
static func pose(o: Vector2, yaw: float, pos := Vector3.ZERO, pitch := 0.0, roll := 0.0) -> Dictionary:
	return {"o": o, "yaw": yaw, "pos": pos, "pitch": pitch, "roll": roll, "par": null}


static func sub(T: Dictionary, at: Vector3, yaw := 0.0, pitch := 0.0, roll := 0.0) -> Dictionary:
	return {"o": T.o, "yaw": yaw, "pos": at, "pitch": pitch, "roll": roll, "par": T}


static func _rot(T: Dictionary, p: Vector3) -> Vector3:
	var f := p.x
	var r := p.y
	var z := p.z
	var rl: float = T.roll
	if rl != 0.0:
		var r2 := r * cos(rl) - z * sin(rl)
		z = r * sin(rl) + z * cos(rl)
		r = r2
	var pt: float = T.pitch
	if pt != 0.0:
		var f2 := f * cos(pt) - z * sin(pt)
		z = f * sin(pt) + z * cos(pt)
		f = f2
	var a: float = T.yaw
	return Vector3(f * cos(a) - r * sin(a), f * sin(a) + r * cos(a), z) + (T.pos as Vector3)


## Local point -> world metres (through every parent pose).
static func wm(T: Dictionary, p: Vector3) -> Vector3:
	var q := _rot(T, p)
	var par = T.par
	while par != null:
		q = _rot(par, q)
		par = par.par
	return q


static func scr_w(o: Vector2, w: Vector3) -> Vector2:
	return P.proj(o, Vector3(w.x / MT, w.y / MT, w.z * ZP))


static func scr(T: Dictionary, p: Vector3) -> Vector2:
	return scr_w(T.o, wm(T, p))


## Direction of a local axis in world space (no translation).
static func wdir(T: Dictionary, d: Vector3) -> Vector3:
	return (wm(T, d) - wm(T, Vector3.ZERO)).normalized()


# ------------------------------------------------------------------ parts
static func part(S: Array, layer := 0.0, bias := 0.0) -> Dictionary:
	var p := {"f": [], "layer": layer, "bias": bias, "dec": [], "sum": Vector3.ZERO, "n": 0}
	S.append(p)
	return p


## A 2D sprite drawn in painter's order at world point w (metres): draw = Callable(cv).
static func sprite(S: Array, w: Vector3, draw: Callable, layer := 1.0, bias := 0.0) -> void:
	var p := part(S, layer, bias)
	p["draw"] = draw
	p.sum = w
	p.n = 1


## Moves every part of scene S2 into S at layer base + its own layer * 0.1 (keeps its inner order).
static func merge(S: Array, S2: Array, base: float, bias := 0.0, obj := -1) -> void:
	for p in S2:
		p.layer = base + float(p.layer) * 0.1
		p.bias = float(p.bias) + bias
		if obj >= 0:   # rev4: object id for render_z's depth edges (cargo vs craft)
			p["obj"] = obj
		S.append(p)


## One face from local points (any winding); ref = a local point inside the solid (sets the outward normal).
static func face(pt: Dictionary, T: Dictionary, pts: Array, ref: Vector3, rp: Array, opt := {}) -> void:
	var w := PackedVector3Array()
	var cen := Vector3.ZERO
	for p in pts:
		var q := wm(T, p)
		w.append(q)
		cen += q
	cen /= float(pts.size())
	var n := Vector3.ZERO
	for i in w.size():   # Newell normal
		var a := w[i]
		var b := w[(i + 1) % w.size()]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	if n.length() < 0.000001:
		return
	n = n.normalized()
	if n.dot(cen - wm(T, ref)) < 0.0:
		n = -n
	if opt.get("flip", false):
		n = -n
	pt.f.append({"w": w, "n": n, "c": cen, "rp": rp, "team": bool(opt.get("team", false)),
		"t": int(opt.get("t", -1)), "dt": int(opt.get("dt", 0)), "edge": bool(opt.get("edge", true)),
		"glass": bool(opt.get("glass", false))})
	pt.sum += cen
	pt.n += 1


## Loft: sections [[f, PackedVector2Array of (r, z)], ...] along local f, same vertex count each.
static func loft(pt: Dictionary, T: Dictionary, secs: Array, rp: Array, opt := {}) -> void:
	var nv: int = (secs[0][1] as PackedVector2Array).size()
	var cs: Array = []
	for s in secs:
		var c := Vector2.ZERO
		for q in s[1]:
			c += q
		cs.append(Vector3(float(s[0]), c.x / nv, c.y / nv))
	for i in secs.size() - 1:
		var a: PackedVector2Array = secs[i][1]
		var b: PackedVector2Array = secs[i + 1][1]
		var fa: float = secs[i][0]
		var fb: float = secs[i + 1][0]
		var ref: Vector3 = (cs[i] + cs[i + 1]) * 0.5
		for j in nv:
			var k := (j + 1) % nv
			var q := [Vector3(fa, a[j].x, a[j].y), Vector3(fa, a[k].x, a[k].y), Vector3(fb, b[k].x, b[k].y),
				Vector3(fb, b[j].x, b[j].y)]
			if (q[0] as Vector3).distance_to(q[1]) < 0.001 and (q[2] as Vector3).distance_to(q[3]) < 0.001:
				continue
			if opt.has("skip") and (opt.skip as Array).has([i, j]):
				continue
			var o2: Dictionary = opt
			var rq: Array = rp
			if opt.has("mats") and (opt.mats as Dictionary).has("%d,%d" % [i, j]):
				rq = opt.mats["%d,%d" % [i, j]]
			if opt.has("team_faces") and (opt.team_faces as Array).has([i, j]):
				o2 = opt.duplicate()
				o2["team"] = true
			face(pt, T, q, ref, rq, o2)
	if opt.get("caps", true):
		for e in [0, secs.size() - 1]:
			if not opt.get("cap%d" % (0 if e == 0 else 1), true):
				continue
			var s: PackedVector2Array = secs[e][1]
			var f0: float = secs[e][0]
			var pts: Array = []
			for q in s:
				pts.append(Vector3(f0, q.x, q.y))
			var inner: Vector3 = cs[1] if e == 0 else cs[secs.size() - 2]
			face(pt, T, pts, inner, rp, opt.merged({"team": opt.get("cap_team", false)}, true))


## Flat convex slab: top polygon pts (local), extruded by `down` (local offset to the bottom face).
static func prism(pt: Dictionary, T: Dictionary, pts: Array, down: Vector3, rp: Array, opt := {}) -> void:
	var c := Vector3.ZERO
	for q in pts:
		c += q
	c = c / float(pts.size()) + down * 0.5
	var bot: Array = []
	for q in pts:
		bot.append(q + down)
	face(pt, T, pts, c, rp, opt)
	face(pt, T, bot, c, rp, opt)
	for i in pts.size():
		var k := (i + 1) % pts.size()
		face(pt, T, [pts[i], pts[k], bot[k], bot[i]], c, rp, opt)


## Box (as a loft) centred at c, half extents h; top inset ti = (front, back, side) metres for sloped armour.
static func box(pt: Dictionary, T: Dictionary, c: Vector3, h: Vector3, rp: Array, ti := Vector3.ZERO, opt := {}) -> void:
	var lo := c.z - h.z
	var hi := c.z + h.z
	var s0 := PackedVector2Array([Vector2(c.y - h.y, lo), Vector2(c.y + h.y, lo), Vector2(c.y + h.y - ti.z, hi), Vector2(c.y - h.y + ti.z, hi)])
	var s1 := s0.duplicate()
	var secs := [[c.x - h.x, s0], [c.x - h.x + 0.0001, s0], [c.x + h.x - 0.0001, s1], [c.x + h.x, s1]]
	if ti.x != 0.0 or ti.y != 0.0:
		var top_f := PackedVector2Array([Vector2(c.y - h.y, lo), Vector2(c.y + h.y, lo), Vector2(c.y + h.y - ti.z, lo + 0.001), Vector2(c.y - h.y + ti.z, lo + 0.001)])
		secs = [[c.x - h.x, top_f], [c.x - h.x + ti.y, s0], [c.x + h.x - ti.x, s1], [c.x + h.x, top_f]]
	loft(pt, T, secs, rp, opt)


## Cylinder / prism with n sides: centre c, local axis ax, radius r, half length hl. phase rotates the sides.
static func cyl(pt: Dictionary, T: Dictionary, c: Vector3, ax: Vector3, r: float, hl: float, n: int, rp: Array,
		opt := {}, phase := 0.0, r2 := -1.0) -> void:
	ax = ax.normalized()
	var u := ax.cross(Vector3(0, 0, 1))
	if u.length() < 0.01:
		u = ax.cross(Vector3(1, 0, 0))
	u = u.normalized()
	var v := ax.cross(u).normalized()
	var rb := r if r2 < 0.0 else r2
	var a0: Array = []
	var a1: Array = []
	for i in n:
		var t := phase + TAU * i / n
		a0.append(c - ax * hl + (u * cos(t) + v * sin(t)) * r)
		a1.append(c + ax * hl + (u * cos(t) + v * sin(t)) * rb)
	for i in n:
		var k := (i + 1) % n
		face(pt, T, [a0[i], a0[k], a1[k], a1[i]], c, rp, opt)
	if opt.get("caps", true):
		face(pt, T, a0, c, rp, opt.merged({"t": opt.get("cap_t", -1), "dt": opt.get("cap_dt", 0)}, true))
		face(pt, T, a1, c, rp, opt.merged({"t": opt.get("cap_t", -1), "dt": opt.get("cap_dt", 0)}, true))


# ------------------------------------------------------------------ decals (drawn with their part)
## A line between local points, shown only while the surface normal nl (local) faces the camera.
static func dline(pt: Dictionary, T: Dictionary, a: Vector3, b: Vector3, col: Color, nl := Vector3.ZERO) -> void:
	pt.dec.append({"k": "line", "a": wm(T, a), "b": wm(T, b), "col": col,
		"n": wdir(T, nl) if nl != Vector3.ZERO else Vector3.ZERO})


static func dpx(pt: Dictionary, T: Dictionary, a: Vector3, col: Color, nl := Vector3.ZERO, team := false) -> void:
	pt.dec.append({"k": "px", "a": wm(T, a), "col": col, "team": team,
		"n": wdir(T, nl) if nl != Vector3.ZERO else Vector3.ZERO})


static func dpoly(pt: Dictionary, T: Dictionary, pts: Array, col: Color, nl := Vector3.ZERO, team := false) -> void:
	var w := PackedVector3Array()
	for p in pts:
		w.append(wm(T, p))
	pt.dec.append({"k": "poly", "w": w, "col": col, "team": team,
		"n": wdir(T, nl) if nl != Vector3.ZERO else Vector3.ZERO})


# ------------------------------------------------------------------ render
static func tone(n: Vector3) -> int:
	var d := n.dot(LIGHT.normalized())
	if d > 0.93:
		return 4
	if d > 0.72:
		return 3
	if d > 0.35:
		return 2
	if d > -0.6:
		return 1
	return 0


static func _depth(w: Vector3) -> float:
	return w.dot(VIEW)


## Ground shadow of every face, cast along the light onto z = 0, composited once.
static func shadow(cv, S: Array, o: Vector2, a := SHADOW.a, sd := Vector2(0.42, -0.10)) -> void:
	# sd: ground offset per metre of height (light from the upper left)
	for pt in S:
		for fc in pt.f:
			var pts := PackedVector2Array()
			for q in fc.w:
				pts.append(scr_w(o, Vector3(q.x + q.z * sd.x, q.y + q.z * sd.y, 0.0)))
			var ar := 0.0
			for i in pts.size():
				ar += pts[i].cross(pts[(i + 1) % pts.size()])
			if absf(ar) < 1.0:   # rev4: an edge-on face casts no shadow (its sliver could scan into a stray line)
				continue
			cv.poly(pts, Color.WHITE, Callable(), true)
	cv.flush_shadow(Color(SHADOW.r, SHADOW.g, SHADOW.b, a))


static func render(cv, S: Array, o: Vector2, seed := 1) -> void:
	for pt in S:
		pt["c"] = pt.sum / float(maxi(1, pt.n))
	var order := S.duplicate()
	order.sort_custom(func(x, y):
		if float(x.layer) != float(y.layer):
			return float(x.layer) < float(y.layer)
		return _depth(x.c) + float(x.bias) < _depth(y.c) + float(y.bias))
	var sp := P.speckle(0.03, seed)
	for pt in order:
		if pt.has("draw"):
			(pt.draw as Callable).call(cv)
			continue
		var fs: Array = []
		for fc in pt.f:
			if (fc.n as Vector3).dot(VIEW) > 0.015:
				fs.append(fc)
		fs.sort_custom(func(x, y): return _depth(x.c) < _depth(y.c))
		for fc in fs:
			_fill(cv, fc, o, sp)
		for d in pt.dec:
			if d.n != Vector3.ZERO and (d.n as Vector3).dot(VIEW) <= 0.015:
				continue
			cv.team = bool(d.get("team", false))
			match String(d.k):
				"line":
					cv.line_v(scr_w(o, d.a), scr_w(o, d.b), d.col)
				"px":
					var p := scr_w(o, d.a)
					cv.px(int(floor(p.x)), int(floor(p.y)), d.col)
				"poly":
					var pts := PackedVector2Array()
					for q in d.w:
						pts.append(scr_w(o, q))
					cv.poly(pts, d.col)
			cv.team = false


static func _fill(cv, fc: Dictionary, o: Vector2, sp: Callable) -> void:
	var rp: Array = fc.rp
	var t: int = fc.t if int(fc.t) >= 0 else tone(fc.n)
	if int(fc.t) < 0 and (fc.c as Vector3).z < 0.95 and (fc.c as Vector3).z > 0.05:
		t -= 1   # grime / occlusion: low hull faces sit in their own shadow
	t = clampi(t + int(fc.dt), 0, rp.size() - 1)
	var pts := PackedVector2Array()
	for q in fc.w:
		pts.append(scr_w(o, q))
	var area := 0.0
	var cen := Vector2.ZERO
	for i in pts.size():
		area += pts[i].cross(pts[(i + 1) % pts.size()])
		cen += pts[i]
	cen /= float(pts.size())
	area = absf(area) * 0.5
	cv.team = fc.team
	cv.poly(pts, rp[t], sp if not fc.glass else Callable())
	cv.team = false
	if not fc.edge or area < 10.0:
		return
	for i in pts.size():   # bevels: lit edges catch light, dark edges crease
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		if a.distance_to(b) < 1.5:
			continue
		var e := b - a
		var nn := Vector2(e.y, -e.x).normalized()
		if nn.dot((a + b) * 0.5 - cen) < 0.0:
			nn = -nn
		var up := nn.dot(Vector2(-0.55, -0.83))
		if up > 0.45:
			cv.line_v(a, b, C.ca(rp[mini(t + 1, rp.size() - 1)], 0.75))
		elif up < -0.6:
			cv.line_v(a, b, C.ca(rp[maxi(t - 1, 0)], 0.6))


# ------------------------------------------------------------------ z-buffered render (rev4, ARTCN7-5)
const ZE := 0.03     # depth tolerance (m): a coplanar face drawn later still wins
const ZDEC := 0.07   # decals lie on their surface: tested this far toward the camera
const ZFIG := 0.3    # soldier sprites: half the body depth (m), so feet on a deck are never cut
const ZEDGE := 0.6   # depth step (m) between two objects that gets a dark separating edge
static var _ids := PackedInt32Array()   # per-pixel object id of the nearest surface (render_z only)
static var _zid := 0

## Real per-pixel depth (rev4; opt-in, render() above is unchanged for older callers such as ART7B). Each face is
## rasterised with its exact depth (orthographic: depth is affine in screen x, y over a flat face), so whatever is
## behind a hull, wing, fan, nacelle or ramp side is hidden wherever the nearer surface covers it, in every facing.
## Parts with layer < 0 are ground marks (dust) drawn first without depth. Sprite parts (soldier figures) are drawn
## to a scratch canvas and composited per pixel as an upright billboard standing at their world point. Translucent
## decals (alpha < 0.98: rotor discs, smoke, glow) are deferred and blended last, far to near, tested, not written.
static func render_z(cv, S: Array, o: Vector2, seed := 1) -> void:
	for pt in S:
		pt["c"] = pt.sum / float(maxi(1, pt.n))
	var order := S.duplicate()
	order.sort_custom(func(x, y):
		if float(x.layer) != float(y.layer):
			return float(x.layer) < float(y.layer)
		return _depth(x.c) + float(x.bias) < _depth(y.c) + float(y.bias))
	var zb := PackedFloat32Array()
	zb.resize(int(cv.w) * int(cv.h))
	zb.fill(-1.0e9)
	# speckle anchored to the pivot, not the cell corner: sheets with different cells (main / load / weapon) give
	# the same pixels for the same surface, so swapping sheets in game never shimmers
	var sp0 := P.speckle(0.03, seed)
	var ox := int(o.x)
	var oy := int(o.y)
	var sp := func(x: int, y: int, c: Color) -> Color: return sp0.call(x - ox + 4096, y - oy + 4096, c)
	var late: Array = []
	_ids = PackedInt32Array()
	_ids.resize(zb.size())
	_ids.fill(-1)
	var multi := false
	for pt in order:   # ground marks: no depth
		if float(pt.layer) >= 0.0 or pt.has("draw"):
			continue
		for fc in pt.f:
			_fill(cv, fc, o, sp)
		for d in pt.dec:
			_dec(cv, d, o)
	for pt in order:
		if float(pt.layer) < 0.0 and not pt.has("draw"):
			continue
		_zid = int(pt.get("obj", 0))
		if pt.has("draw"):
			_zid = 1000 + order.find(pt)
			multi = true
			_sprite_z(cv, zb, pt, o)
			continue
		if _zid != 0:
			multi = true
		var fs: Array = []
		for fc in pt.f:
			if (fc.n as Vector3).dot(VIEW) > 0.015:
				fs.append(fc)
		fs.sort_custom(func(x, y): return _depth(x.c) < _depth(y.c))
		for fc in fs:
			_fill_z(cv, zb, fc, o, sp)
		for d in pt.dec:
			if d.n != Vector3.ZERO and (d.n as Vector3).dot(VIEW) <= 0.015:
				continue
			if (d.col as Color).a < 0.98:
				late.append(d)
			else:
				_dec_z(cv, zb, d, o, true)
	if multi:
		_edges(cv, zb)
	late.sort_custom(func(x, y): return _dmid(x) < _dmid(y))
	_zid = 0
	for d in late:
		_dec_z(cv, zb, d, o, false)


## Separate objects in depth (cargo / soldiers vs the craft): where two different objects meet and the neighbour is
## more than ZEDGE nearer, the farther pixel becomes a dark edge, like the sheet's sel-out outline against empty space.
static func _edges(cv, zb: PackedFloat32Array) -> void:
	var w: int = cv.w
	var h: int = cv.h
	var mark: Array = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			var id := _ids[i]
			if id < 0:
				continue
			var d := zb[i]
			for j in [i - 1, i + 1, i - w, i + w]:
				if _ids[j] >= 0 and _ids[j] != id and zb[j] > d + ZEDGE:
					mark.append(i)
					break
	for i in mark:
		cv.px(i % w, i / w, C.OUTLINE)


## One decal without depth (render() and ground marks).
static func _dec(cv, d: Dictionary, o: Vector2) -> void:
	if d.n != Vector3.ZERO and (d.n as Vector3).dot(VIEW) <= 0.015:
		return
	cv.team = bool(d.get("team", false))
	match String(d.k):
		"line":
			cv.line_v(scr_w(o, d.a), scr_w(o, d.b), d.col)
		"px":
			var p := scr_w(o, d.a)
			cv.px(int(floor(p.x)), int(floor(p.y)), d.col)
		"poly":
			var pts := PackedVector2Array()
			for q in d.w:
				pts.append(scr_w(o, q))
			cv.poly(pts, d.col)
	cv.team = false


static func _dmid(d: Dictionary) -> float:
	match String(d.k):
		"line":
			return (_depth(d.a) + _depth(d.b)) * 0.5
		"px":
			return _depth(d.a)
	var s := 0.0
	for q in d.w:
		s += _depth(q)
	return s / float(maxi(1, (d.w as PackedVector3Array).size()))


## Depth plane over screen space from a polygon's projected points: Vector3(a, b, c) with depth = a x + b y + c.
## Degenerate (edge-on) polygons get a flat plane at their mean depth.
static func _plane(pts: PackedVector2Array, ds: PackedFloat32Array) -> Vector3:
	var best := 0.0
	var bi := -1
	for i in range(1, pts.size() - 1):
		var ar := absf((pts[i] - pts[0]).cross(pts[i + 1] - pts[0]))
		if ar > best:
			best = ar
			bi = i
	if bi < 0 or best < 0.05:
		var m := 0.0
		for q in ds:
			m += q
		return Vector3(0, 0, m / float(maxi(1, ds.size())))
	var e1 := pts[bi] - pts[0]
	var e2 := pts[bi + 1] - pts[0]
	var d1 := ds[bi] - ds[0]
	var d2 := ds[bi + 1] - ds[0]
	var det := e1.x * e2.y - e1.y * e2.x
	var a := (d1 * e2.y - d2 * e1.y) / det
	var b := (e1.x * d2 - e2.x * d1) / det
	return Vector3(a, b, ds[0] - a * pts[0].x - b * pts[0].y)


## Depth-tested scanline fill (same pixel coverage rule as Canvas.poly).
static func _scan(cv, zb: PackedFloat32Array, pts: PackedVector2Array, pl: Vector3, col: Color, shade: Callable,
		tol: float, write: bool) -> void:
	if pts.size() < 3:
		return
	var w: int = cv.w
	var h: int = cv.h
	var miny := INF
	var maxy := -INF
	for p in pts:
		miny = minf(miny, p.y)
		maxy = maxf(maxy, p.y)
	var n := pts.size()
	for y in range(maxi(0, int(floor(miny))), mini(h - 1, int(ceil(maxy))) + 1):
		var sy := y + 0.5
		var xs: Array = []
		for i in n:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
				xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			for x in range(maxi(0, int(ceil(xs[k] - 0.5))), mini(w, int(ceil(xs[k + 1] - 0.5)))):
				var d := pl.x * (x + 0.5) + pl.y * sy + pl.z
				var i := y * w + x
				if d >= zb[i] - tol:
					if write and d > zb[i]:
						zb[i] = d
						_ids[i] = _zid
					cv.px(x, y, shade.call(x, y, col) if shade.is_valid() else col)
			k += 2


## Depth-tested line (Bresenham like Canvas.line), depth interpolated between the end depths.
static func _line_z(cv, zb: PackedFloat32Array, a: Vector2, b: Vector2, col: Color, da: float, db: float, tol: float,
		write: bool) -> void:
	var x0 := int(floor(a.x))
	var y0 := int(floor(a.y))
	var x1 := int(floor(b.x))
	var y1 := int(floor(b.y))
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var n := maxi(1, maxi(dx, -dy))
	var s := 0
	var w: int = cv.w
	while true:
		if x0 >= 0 and y0 >= 0 and x0 < w and y0 < int(cv.h):
			var d := lerpf(da, db, float(s) / float(n))
			var i := y0 * w + x0
			if d >= zb[i] - tol:
				if write and d > zb[i]:
					zb[i] = d
					_ids[i] = _zid
				cv.px(x0, y0, col)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
		s += 1


static func _fill_z(cv, zb: PackedFloat32Array, fc: Dictionary, o: Vector2, sp: Callable) -> void:
	var rp: Array = fc.rp
	var t: int = fc.t if int(fc.t) >= 0 else tone(fc.n)
	if int(fc.t) < 0 and (fc.c as Vector3).z < 0.95 and (fc.c as Vector3).z > 0.05:
		t -= 1
	t = clampi(t + int(fc.dt), 0, rp.size() - 1)
	var pts := PackedVector2Array()
	var ds := PackedFloat32Array()
	for q in fc.w:
		pts.append(scr_w(o, q))
		ds.append(_depth(q))
	var pl := _plane(pts, ds)
	var area := 0.0
	var cen := Vector2.ZERO
	for i in pts.size():
		area += pts[i].cross(pts[(i + 1) % pts.size()])
		cen += pts[i]
	cen /= float(pts.size())
	area = absf(area) * 0.5
	cv.team = fc.team
	_scan(cv, zb, pts, pl, rp[t], sp if not fc.glass else Callable(), ZE, true)
	cv.team = false
	if not fc.edge or area < 10.0:
		return
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		if a.distance_to(b) < 1.5:
			continue
		var e := b - a
		var nn := Vector2(e.y, -e.x).normalized()
		if nn.dot((a + b) * 0.5 - cen) < 0.0:
			nn = -nn
		var up := nn.dot(Vector2(-0.55, -0.83))
		var da := ds[i]
		var db := ds[(i + 1) % pts.size()]
		if up > 0.45:
			_line_z(cv, zb, a, b, C.ca(rp[mini(t + 1, rp.size() - 1)], 0.75), da, db, ZE + 0.02, false)
		elif up < -0.6:
			_line_z(cv, zb, a, b, C.ca(rp[maxi(t - 1, 0)], 0.6), da, db, ZE + 0.02, false)


static func _dec_z(cv, zb: PackedFloat32Array, d: Dictionary, o: Vector2, write: bool) -> void:
	cv.team = bool(d.get("team", false))
	match String(d.k):
		"line":
			_line_z(cv, zb, scr_w(o, d.a), scr_w(o, d.b), d.col, _depth(d.a), _depth(d.b), ZDEC, write)
		"px":
			var p := scr_w(o, d.a)
			var x := int(floor(p.x))
			var y := int(floor(p.y))
			if x >= 0 and y >= 0 and x < int(cv.w) and y < int(cv.h):
				var dd := _depth(d.a)
				var i := y * int(cv.w) + x
				if dd >= zb[i] - ZDEC:
					if write and dd > zb[i]:
						zb[i] = dd
						_ids[i] = _zid
					cv.px(x, y, d.col)
		"poly":
			var pts := PackedVector2Array()
			var ds := PackedFloat32Array()
			for q in d.w:
				pts.append(scr_w(o, q))
				ds.append(_depth(q))
			_scan(cv, zb, pts, _plane(pts, ds), d.col, Callable(), ZDEC, write)
	cv.team = false


## A sprite part (soldier figure) composited as an upright billboard at its world point: a pixel h px above the
## foot is the point h / ZP metres up, so its depth is the foot depth + 0.5 per metre (VIEW.z) + the body depth.
static func _sprite_z(cv, zb: PackedFloat32Array, pt: Dictionary, o: Vector2) -> void:
	var tmp = P.Canvas.new(int(cv.w), int(cv.h))
	(pt.draw as Callable).call(tmp)
	var u: Rect2i = (tmp.img as Image).get_used_rect()
	if u.size.x <= 0:
		return
	var w0: Vector3 = pt.sum
	var foot := scr_w(o, w0)
	var d0 := _depth(w0) + ZFIG
	var w: int = cv.w
	for y in range(u.position.y, u.end.y):
		var d := d0 + VIEW.z * maxf(0.0, (foot.y - (y + 0.5)) / ZP)
		for x in range(u.position.x, u.end.x):
			var c: Color = tmp.img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var i := y * w + x
			if d < zb[i] - ZE:
				continue
			if c.a > 0.9 and d > zb[i]:
				zb[i] = d
				_ids[i] = _zid
			cv.team = tmp.mask.get_pixel(x, y).a > 0.5
			cv.px(x, y, c)
	cv.team = false
