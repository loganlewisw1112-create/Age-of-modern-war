extends RefCounted
## G5 aircraft art (agent ART-AIR): renders a g5_air_mesh.AMesh into a pix.gd Canvas.
## Order: [cast shadow] -> z-buffered triangles -> solid lines -> outline -> thin lines -> rotor / fan
## discs (translucent, z-tested) -> effect marks. Material detail is anchored in model space so it turns
## with the aircraft: style "a" faint panel lines, "b" heavy panel seams + rivet rows + rust, "m" cyan
## seams on graphite. Team-colour materials ("team") write the mask (greyscale + mask = 1).
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const MS = preload("res://tools/art/g5_air_mesh.gd")

const LDIR := Vector3(-0.45, 0.5, 0.75)
const CAMV := Vector3(0.5, 0.5, 0.7071)
const EMISSIVE := ["cyan", "navr", "navg", "glow", "lamp"]
const SKIN := ["body", "body2", "under"]
const OUTL := {"a": Color(0.09, 0.1, 0.11, 1), "b": Color(0.08, 0.07, 0.05, 1), "m": Color(0.04, 0.05, 0.07, 1)}
const RUST := Color8(132, 74, 40)


## opts: {style, pal, ground (cast shadow under it), seed}
static func render(cv, o: Vector2, rot: float, m, opts: Dictionary) -> void:
	var ca := cos(rot)
	var sa := sin(rot)
	var style: String = opts.get("style", "a")
	var pal: Dictionary = opts.pal
	if bool(opts.get("ground", false)):
		footprint(cv, o, rot, m, true)
		cv.flush_shadow(Color(0.04, 0.05, 0.03, 0.42))
	var zb := PackedFloat32Array()
	zb.resize(cv.w * cv.h)
	zb.fill(-1.0e9)
	for t: Array in m.tris:
		var wa := MS.to_w(t[0], ca, sa)
		var wb := MS.to_w(t[1], ca, sa)
		var wc := MS.to_w(t[2], ca, sa)
		var nl: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
		var nw := Vector3(nl.x * ca - nl.y * sa, nl.x * sa + nl.y * ca, nl.z)
		if nw.length() < 0.0001:
			continue
		nw = nw.normalized()
		if nw.dot(CAMV) < 0.0:
			nw = -nw
		var b := 0.62 + 0.45 * maxf(0.0, nw.dot(LDIR.normalized()))
		_tri(cv, zb, MS.scr(o, wa), MS.scr(o, wb), MS.scr(o, wc), MS.depth(wa), MS.depth(wb), MS.depth(wc),
			t[0], t[1], t[2], String(t[3]), b, pal, style)
	for ln: Array in m.lines:
		if not bool(ln[3]):
			_line(cv, zb, o, ca, sa, ln[0], ln[1], pal.get(ln[2], Color.MAGENTA), true, String(ln[2]) == "team")
	cv.outline(OUTL.get(style, OUTL.a))
	var keep: Image = cv.mask.duplicate()
	for ln: Array in m.lines:
		if bool(ln[3]):
			_line(cv, zb, o, ca, sa, ln[0], ln[1], pal.get(ln[2], Color.MAGENTA), false, false)
	for d: Dictionary in m.discs:
		_disc(cv, zb, o, ca, sa, d, pal)
	# translucent rotor discs / cables blended over team paint must not strip its team mask
	for y in cv.h:
		for x in cv.w:
			if keep.get_pixel(x, y).a > 0.5 and cv.mask.get_pixel(x, y).a < 0.5:
				var c: Color = cv.img.get_pixel(x, y)
				var l := c.get_luminance()
				cv.img.set_pixel(x, y, Color(l, l, l, c.a))
				cv.mask.set_pixel(x, y, Color(1, 1, 1, 1))
	var i := 0
	for mk: Dictionary in m.marks:
		_mark(cv, o, rot, mk, int(opts.get("seed", 0)) + i * 31)
		i += 1


static func _tri(cv, zb: PackedFloat32Array, s0: Vector2, s1: Vector2, s2: Vector2, d0: float, d1: float, d2: float,
		l0: Vector3, l1: Vector3, l2: Vector3, mat: String, b: float, pal: Dictionary, style: String) -> void:
	var area := (s1.x - s0.x) * (s2.y - s0.y) - (s1.y - s0.y) * (s2.x - s0.x)
	if absf(area) < 0.02:
		return
	var x0 := maxi(0, int(floor(minf(s0.x, minf(s1.x, s2.x)))))
	var x1 := mini(cv.w - 1, int(ceil(maxf(s0.x, maxf(s1.x, s2.x)))))
	var y0 := maxi(0, int(floor(minf(s0.y, minf(s1.y, s2.y)))))
	var y1 := mini(cv.h - 1, int(ceil(maxf(s0.y, maxf(s1.y, s2.y)))))
	var base: Color = pal.get(mat, Color.MAGENTA)
	var emis := EMISSIVE.has(mat)
	var skin := SKIN.has(mat)
	for y in range(y0, y1 + 1):
		var py := y + 0.5
		for x in range(x0, x1 + 1):
			var px := x + 0.5
			var w0 := ((s1.x - px) * (s2.y - py) - (s1.y - py) * (s2.x - px)) / area
			var w1 := ((s2.x - px) * (s0.y - py) - (s2.y - py) * (s0.x - px)) / area
			var w2 := 1.0 - w0 - w1
			if w0 < -0.001 or w1 < -0.001 or w2 < -0.001:
				continue
			var d := d0 * w0 + d1 * w1 + d2 * w2
			var idx: int = y * cv.w + x
			if d <= zb[idx]:
				continue
			zb[idx] = d
			if emis:
				cv.px(x, y, base)
				continue
			var lp := l0 * w0 + l1 * w1 + l2 * w2
			var c := P.mul(base, b)
			if mat == "glass" and fposmod(lp.x + lp.y * 0.5 + lp.z, 7.0) < 1.1:
				c = P.mix(c, Color(0.9, 0.95, 1.0), 0.45)
			elif skin:
				c = _skin(c, lp, style, pal)
			if mat == "team":
				cv.team = true
				cv.px(x, y, P.mul(base, b))
				cv.team = false
			else:
				cv.px(x, y, c)


## Faction surface detail on a shaded skin colour at model point lp.
static func _skin(c: Color, lp: Vector3, style: String, pal: Dictionary) -> Color:
	match style:
		"a":
			if fposmod(lp.x + 0.5, 9.0) < 0.9:
				return P.mul(c, 0.86)
		"b":
			var u := fposmod(lp.x + 0.5, 6.0)
			if u < 0.95:
				return P.mul(c, 0.72)
			if u < 2.0 and fposmod(lp.y + lp.z + 0.5, 2.5) < 1.0:
				return P.mul(c, 1.22)
			if P.hn(int(floor(lp.x * 0.5)), int(floor(lp.y * 0.7 + lp.z * 0.6)), 7331) > 0.88:
				return P.mix(c, RUST, 0.55)
		"m":
			if fposmod(lp.x + 0.5, 8.0) < 1.0:
				return pal.get("cyan", Color8(80, 230, 240))
			if P.hn(int(floor(lp.x * 0.5)), int(floor(lp.y * 0.5 + lp.z * 0.5)), 913) > 0.9:
				return P.mul(c, 1.12)
	return c


## Z-tested screen line between model points. write = also write depth (solid parts before outline).
static func _line(cv, zb: PackedFloat32Array, o: Vector2, ca: float, sa: float, a: Vector3, b: Vector3, col: Color,
		write: bool, team: bool) -> void:
	var wa := MS.to_w(a, ca, sa)
	var wb := MS.to_w(b, ca, sa)
	var sa2 := MS.scr(o, wa)
	var sb := MS.scr(o, wb)
	var da := MS.depth(wa)
	var db := MS.depth(wb)
	var n := int(ceil(maxf(absf(sb.x - sa2.x), absf(sb.y - sa2.y)))) + 1
	for i in n + 1:
		var t := float(i) / float(maxi(1, n))
		var p := sa2.lerp(sb, t)
		var x := int(floor(p.x))
		var y := int(floor(p.y))
		if x < 0 or y < 0 or x >= cv.w or y >= cv.h:
			continue
		var d := lerpf(da, db, t) + 1.5
		var idx: int = y * cv.w + x
		if d <= zb[idx]:
			continue
		if write:
			zb[idx] = d
		cv.team = team
		cv.px(x, y, P.mul(Color(0.8, 0.8, 0.8), 0.9) if team else col)
		cv.team = false


## Rotor / prop / fan disc: translucent z-tested fill + rim + blades (spin), or hard blades (stop).
static func _disc(cv, zb: PackedFloat32Array, o: Vector2, ca: float, sa: float, d: Dictionary, pal: Dictionary) -> void:
	var c: Vector3 = d.c
	var n: Vector3 = d.n
	var r: float = d.r
	var up := Vector3(0, 0, 1) if absf(n.z) < 0.9 else Vector3(1, 0, 0)
	var u := n.cross(up).normalized()
	var v := n.cross(u).normalized()
	var mode: String = d.mode
	var blade: Color = pal.get("rotor", Color8(30, 30, 30))
	if mode != "stop" and mode != "fan_stop":
		var fan := mode.begins_with("fan")
		var fill := Color(0.18, 0.2, 0.22, 0.5) if fan else Color(0.86, 0.88, 0.88, 0.07 if mode == "slow" else 0.17)
		var wh := MS.to_w(c, ca, sa)
		var sh := MS.scr(o, wh)
		var dh := MS.depth(wh)
		var cov := {}
		var rim: Array = []
		for i in 20:
			var t0 := float(i) * TAU / 20.0
			var t1 := float(i + 1) * TAU / 20.0
			var w0 := MS.to_w(c + (u * cos(t0) + v * sin(t0)) * r, ca, sa)
			var w1 := MS.to_w(c + (u * cos(t1) + v * sin(t1)) * r, ca, sa)
			rim.append([MS.scr(o, w0), MS.depth(w0)])
			_cover(cv, zb, sh, MS.scr(o, w0), MS.scr(o, w1), dh, MS.depth(w0), MS.depth(w1), cov)
		var keys: Array = cov.keys()
		keys.sort()
		for idx: int in keys:
			cv.px(idx % cv.w, idx / cv.w, fill)
		if not fan:
			for rp: Array in rim:
				var p: Vector2 = rp[0]
				var x := int(floor(p.x))
				var y := int(floor(p.y))
				if x >= 0 and y >= 0 and x < cv.w and y < cv.h and float(rp[1]) + 1.5 > zb[y * cv.w + x]:
					cv.px(x, y, Color(0.92, 0.93, 0.92, 0.22 if mode == "slow" else 0.3))
	var nb: int = d.blades
	for k in nb:
		if (mode == "spin" or mode == "fan_spin") and k > 1:
			break  # a spinning rotor shows only a blurred blade pair
		var ang: float = float(d.ph) + float(k) * TAU / float(nb)
		var tip := c + (u * cos(ang) + v * sin(ang)) * r * (0.98 if mode != "spin" else 0.95)
		var col := blade
		if mode == "spin":
			col = Color(blade.r, blade.g, blade.b, 0.42)
		elif mode == "slow":
			col = Color(blade.r, blade.g, blade.b, 0.8)
		elif mode == "fan_spin":
			col = Color(0.7, 0.72, 0.72, 0.55)
		var a := c if mode != "spin" else c + (tip - c) * 0.12
		_line(cv, zb, o, ca, sa, a, tip, col, false, false)
		if mode == "spin":
			_line(cv, zb, o, ca, sa, c - (tip - c) * 0.12, c - (tip - c), col, false, false)


static func _cover(cv, zb: PackedFloat32Array, s0: Vector2, s1: Vector2, s2: Vector2, d0: float, d1: float, d2: float,
		cov: Dictionary) -> void:
	var area := (s1.x - s0.x) * (s2.y - s0.y) - (s1.y - s0.y) * (s2.x - s0.x)
	if absf(area) < 0.02:
		return
	var x0 := maxi(0, int(floor(minf(s0.x, minf(s1.x, s2.x)))))
	var x1 := mini(cv.w - 1, int(ceil(maxf(s0.x, maxf(s1.x, s2.x)))))
	var y0 := maxi(0, int(floor(minf(s0.y, minf(s1.y, s2.y)))))
	var y1 := mini(cv.h - 1, int(ceil(maxf(s0.y, maxf(s1.y, s2.y)))))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var px := x + 0.5
			var py := y + 0.5
			var w0 := ((s1.x - px) * (s2.y - py) - (s1.y - py) * (s2.x - px)) / area
			var w1 := ((s2.x - px) * (s0.y - py) - (s2.y - py) * (s0.x - px)) / area
			var w2 := 1.0 - w0 - w1
			if w0 < -0.001 or w1 < -0.001 or w2 < -0.001:
				continue
			var idx: int = y * cv.w + x
			if d0 * w0 + d1 * w1 + d2 * w2 + 1.0 > zb[idx]:
				cov[idx] = true


## Ground footprint of every triangle into cv.sh. cast = sun-cast offset by height (on the ground);
## otherwise the flat top-down silhouette (the airborne shadow sheet).
static func footprint(cv, o: Vector2, rot: float, m, cast: bool) -> void:
	var ca := cos(rot)
	var sa := sin(rot)
	for t: Array in m.tris:
		var pts := PackedVector2Array()
		for k in 3:
			var w := MS.to_w(t[k], ca, sa)
			var off := Vector2(0.9, 0.35) * (w.z / 32.0) if cast else Vector2.ZERO
			pts.append(P.proj(o, Vector3(w.x + off.x, w.y + off.y, 0.0)))
		cv.poly(pts, Color.BLACK, Callable(), true)


static func _mark(cv, o: Vector2, rot: float, mk: Dictionary, seed: int) -> void:
	var s := MS.sp(o, rot, mk.p)
	var e := MS.sp(o, rot, mk.p + (mk.dir as Vector3).normalized() * 8.0)
	var dv := (e - s).normalized() if (e - s).length() > 0.1 else Vector2(0, 1)
	var k: float = mk.s
	match String(mk.kind):
		"flash":
			L.flash(cv, s, k)
		"exhaust":
			L.flame(cv, s, dv, 3.0 + 5.0 * k, seed)
		"plasma":
			var n := int(3.0 + 5.0 * k)
			for i in n:
				var t := float(i) / float(n)
				cv.px(int(s.x + dv.x * i), int(s.y + dv.y * i), Color(0.55 + 0.4 * (1.0 - t), 0.95, 1.0, 1.0 - t * 0.8))
		"heat":
			cv.ellipse(s.x + dv.x * 2.0, s.y + dv.y * 2.0, 1.6, 1.0, Color(0.9, 0.85, 0.75, 0.3))
		"glow":
			cv.px(int(s.x), int(s.y), Color8(255, 170, 70))
		"rocket":
			cv.line_v(s, s + dv * 7.0 * k, Color8(255, 236, 170))
			cv.px(int(s.x + dv.x * 7.0 * k), int(s.y + dv.y * 7.0 * k), Color8(255, 255, 240))
			L.puff(cv, s - dv * 1.5, 1.6, 0.4)
		"missile":
			var h := s + dv * 6.0 * k
			cv.line_v(h - dv * 3.0, h, Color8(236, 236, 228))
			L.flame(cv, h - dv * 3.0, -dv, 3.0, seed)
			for i in 4:
				L.puff(cv, h - dv * (5.0 + i * 2.5), 1.0 + i * 0.3, 0.45 - i * 0.08, Color(0.9, 0.9, 0.88))
		"bomb":
			var b := s + Vector2(0, 4.0 * k)
			cv.line_v(b - Vector2(0, 5), b - Vector2(0, 3), Color(1, 1, 1, 0.3))
			cv.ellipse(b.x, b.y, 1.9, 2.7, Color8(20, 20, 18))
			cv.ellipse(b.x, b.y, 1.2, 2.0, Color8(104, 110, 92))
			cv.px(int(b.x) - 1, int(b.y) - 2, Color8(150, 154, 140))
			cv.rect(int(b.x) - 2, int(b.y) - 3, 4, 1, Color8(40, 42, 36))
		"tracer":
			cv.line_v(s, s + dv * 10.0 * k, Color(1.0, 0.88, 0.45, 0.85))
		"bolt":
			cv.line_v(s, s + dv * 9.0 * k, Color8(120, 245, 255))
			cv.px(int(s.x + dv.x * 9.0 * k), int(s.y + dv.y * 9.0 * k), Color8(230, 255, 255))
		"smoke":
			for i in 3:
				L.puff(cv, s + Vector2(float(i) * 1.5, -float(i) * 3.0), 2.0 + i * 0.8, 0.5 - i * 0.1, Color(0.24, 0.23, 0.22))
		"fire":
			L.flame(cv, s, Vector2(0.15, -1.0), 3.0 + 2.0 * k, seed)
		"navr":
			cv.px(int(s.x), int(s.y), Color8(255, 60, 50))
		"navg":
			cv.px(int(s.x), int(s.y), Color8(80, 255, 110))
		"cyanpx":
			cv.px(int(s.x), int(s.y), Color8(120, 245, 255))
		"drone":
			cv.ellipse(s.x, s.y, 1.6, 1.0, Color8(46, 50, 56))
			cv.px(int(s.x), int(s.y), Color8(120, 245, 255))
		"dust":
			L.puff(cv, s, 2.5 * k, 0.4, Color(0.62, 0.56, 0.44))
