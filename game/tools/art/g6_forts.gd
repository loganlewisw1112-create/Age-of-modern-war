extends RefCounted
## G6 fortifications (agent art-forts-2): field works + Machine wall/gate + Human A support buildings, all
## building-type assets (H.bld, rotations f = 0, 1), drawn in the local (u, v) frame of g5_bld_lib so one
## drawer renders every rotation. Line pieces (sandbags, trench, wire, traps) are one tileable segment
## running along local u from cell edge to cell edge, like the G4 wall arms.
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const BLD = preload("res://tools/art/buildings.gd")
const VH = preload("res://tools/art/vehicles.gd")
const H = preload("res://tools/art/g6_lib.gd")

const SAND := Color8(150, 134, 98)
const EARTH := Color8(104, 84, 60)
const EARTH_D := Color8(66, 52, 38)
const STEEL := Color8(92, 96, 98)
const STEEL_L := Color8(150, 154, 152)
const WOOD := Color8(128, 104, 70)
const OLIVE := BLD.OLIVE
const CONCRETE := BLD.CONCRETE
const YELLOW := Color8(206, 168, 52)

const SHOW := {
	"s_sandbags": {"row": 0, "ground": "grass"},
	"s_trench": {"row": 0, "ground": "dirt"},
	"s_tank_traps": {"row": 0, "ground": "grass"},
	"s_barbed_wire": {"row": 0, "ground": "grass"},
	"s_minefield": {"row": 0, "ground": "grass"},
	"s_garrison_bld": {"row": 0, "ground": "building"},
	"s_camo_decoy": {"row": 0, "ground": "grass"},
	"m_nanite_wall": {"row": 0, "ground": "grass"},
	"m_phase_gate": {"row": 0, "ground": "grass"},
	"a_radar_station": {"row": 0, "ground": "building"},
	"a_fob": {"row": 0, "ground": "dirt"},
	"a_repair_bay": {"row": 0, "ground": "building"},
	"a_cruise_battery": {"row": 0, "ground": "building"},
}


static func build(out: Dictionary) -> void:
	H.bld(out, "s_sandbags", 1, 14, sandbags)
	H.bld(out, "s_trench", 1, 10, trench)
	H.bld(out, "s_tank_traps", 1, 20, tank_traps)
	H.bld(out, "s_barbed_wire", 1, 16, barbed_wire)
	H.bld(out, "s_minefield", 2, 14, minefield)
	H.bld(out, "s_garrison_bld", 2, 48, garrison)
	H.bld(out, "s_camo_decoy", 2, 22, camo_decoy)
	H.bld(out, "m_nanite_wall", 1, 30, nanite_wall)
	H.bld(out, "m_phase_gate", 1, 44, phase_gate)
	H.bld(out, "a_radar_station", 2, 64, radar_station)
	H.bld(out, "a_fob", 3, 40, fob)
	H.bld(out, "a_repair_bay", 3, 52, repair_bay)
	H.bld(out, "a_cruise_battery", 2, 70, cruise_battery)


# ---------------------------------------------------------------- shared helpers
## Screen depth of a local point (bigger = nearer the camera).
static func dep(f: int, u: float, v: float) -> float:
	var q := K.wp(f, u, v)
	return q.x + q.y


## Draw [[depth, Callable], ...] back to front.
static func layered(items: Array) -> void:
	items.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for it in items:
		(it[1] as Callable).call()


static func bx(cv, o: Vector2, f: int, u: float, v: float, z: float, hu: float, hv: float, hz: float, col: Color,
		tex := 0.08, s := 1) -> Dictionary:
	var c := K.wp(f, u, v)
	return P.box(cv, o, Vector3(c.x, c.y, z), hu, hv, hz, K.rot(f), col, tex, s)


static func bshadow(cv, o: Vector2, f: int, u: float, v: float, z: float, hu: float, hv: float, hz: float) -> void:
	var c := K.wp(f, u, v)
	P.box_shadow(cv, o, Vector3(c.x, c.y, z), hu, hv, hz, K.rot(f))


static func team_flag(cv, o: Vector2, f: int, u: float, v: float, h := 12.0) -> void:
	var b := K.pt(o, f, u, v, 0)
	var t := K.pt(o, f, u, v, h)
	cv.line_v(b, t, Color8(60, 58, 52))
	cv.team = true
	cv.rect(int(t.x) + 1, int(t.y), 5, 3, Color(0.85, 0.85, 0.85))
	cv.rect(int(t.x) + 1, int(t.y), 5, 1, Color(1, 1, 1))
	cv.team = false


static func _ph(cv, o: Vector2, f: int, n: int, col: Color) -> void:
	var ps: Array = [[0, 0, 0, 0.4 * n, 0.4 * n, 2, Color8(112, 110, 102), "slab"], [0, 0, 2, 0.3 * n, 0.3 * n, 12, col, "box"],
		[0, 0, 14, 0.2 * n, 0.2 * n, 2, Color(0.8, 0.8, 0.8), "team"]]
	K.render(cv, o, f, ps, 1.0, false, Callable())


# ---------------------------------------------------------------- placeholders (replaced one by one)
# ---------------------------------------------------------------- s_trench
## ART-G6: s_trench is a 1-cell line piece (content/g6 line: true), so the zig-zag spans one cell (ends +-0.5).
const TR_PTS := [Vector2(-0.5, 0.0), Vector2(-0.25, -0.13), Vector2(0.0, 0.13), Vector2(0.25, -0.13), Vector2(0.5, 0.0)]
const REVET := Color8(118, 94, 62)


## Polyline offset by `d` (tiles, + = local left/+v side) with mitred joints.
static func offset_line(pts: Array, d: float) -> Array:
	var out: Array = []
	for i in pts.size():
		var a: Vector2 = pts[maxi(i - 1, 0)]
		var b: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var t := (b - a).normalized()
		var n := Vector2(-t.y, t.x)
		var k := 1.0
		if i > 0 and i < pts.size() - 1:
			var t0: Vector2 = (pts[i] - pts[i - 1]).normalized()
			k = 1.0 / maxf(0.4, n.dot(Vector2(-t0.y, t0.x)))
		var p: Vector2 = pts[i]
		out.append(p + n * d * k)
	return out


static func lpoly(o: Vector2, f: int, pts: Array, z: float) -> PackedVector2Array:
	var r := PackedVector2Array()
	for p in pts:
		r.append(K.pt(o, f, p.x, p.y, z))
	return r


static func trench(cv, o: Vector2, f: int) -> void:
	var w := 0.2
	var dd := 12.0
	var lt := offset_line(TR_PTS, w)
	var rt := offset_line(TR_PTS, -w)
	var rev := rt.duplicate()
	rev.reverse()
	var opening := lpoly(o, f, lt + rev, 0.0)
	# interior drawn on a scratch canvas, then clipped to the opening
	var tc = P.Canvas.new(cv.w, cv.h)
	tc.poly(opening, Color8(44, 34, 24))
	var floor_pts := lpoly(o, f, lt + rev, -dd)
	tc.poly(floor_pts, Color8(78, 62, 44), P.speckle(0.12, 501))
	for i in range(1, 40):  # duckboards along the floor
		var t := float(i) / 40.0
		var seg := t * (TR_PTS.size() - 1)
		var si := mini(int(seg), TR_PTS.size() - 2)
		var c: Vector2 = (TR_PTS[si] as Vector2).lerp(TR_PTS[si + 1], seg - si)
		var dir: Vector2 = (TR_PTS[si + 1] - TR_PTS[si]).normalized()
		var nn := Vector2(-dir.y, dir.x) * 0.08
		tc.line_v(K.pt(o, f, c.x + nn.x, c.y + nn.y, -dd), K.pt(o, f, c.x - nn.x, c.y - nn.y, -dd), WOOD if i % 2 == 0 else P.mul(WOOD, 0.8))
	for side in [[lt, -1.0], [rt, 1.0]]:
		var ln: Array = side[0]
		for i in ln.size() - 1:
			var a: Vector2 = ln[i]
			var b: Vector2 = ln[i + 1]
			var t := (b - a).normalized()
			var inner := Vector2(-t.y, t.x) * float(side[1])
			var wn := K.wp(f, inner.x, inner.y)
			if wn.x + wn.y <= 0.02:
				continue
			var q := PackedVector2Array([K.pt(o, f, a.x, a.y, 0), K.pt(o, f, b.x, b.y, 0), K.pt(o, f, b.x, b.y, -dd), K.pt(o, f, a.x, a.y, -dd)])
			tc.poly(q, P.mul(REVET, P.side_shade(wn) * 0.95), P.speckle(0.1, 510 + i))
			for vv in [0.3, 0.62]:  # revetment planks
				tc.line_v(q[0].lerp(q[3], vv), q[1].lerp(q[2], vv), P.mul(REVET, 0.62))
			for uu in [0.0, 0.5]:  # pickets
				tc.line_v(q[0].lerp(q[1], uu + 0.25), q[3].lerp(q[2], uu + 0.25), P.mul(WOOD, 0.55))
			tc.line_v(q[0], q[1], P.mul(EARTH, 1.25))  # lit lip
	for y in cv.h:
		for x in cv.w:
			var c2: Color = tc.img.get_pixel(x, y)
			if c2.a > 0.0 and Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), opening):
				cv.px(x, y, c2)
	# spoil berms: the far lip carries a sandbagged parapet, the near lip only a low spoil ridge (keeps the cut readable)
	var items: Array = []
	var lo := offset_line(TR_PTS, w + 0.1)
	var ro := offset_line(TR_PTS, -w - 0.1)
	var far_left := dep(f, 0, 1) < dep(f, 0, -1)
	for side in [[lo, far_left], [ro, not far_left]]:
		var ln: Array = side[0]
		var far: bool = side[1]
		for i in ln.size() - 1:
			var a: Vector2 = ln[i]
			var b: Vector2 = ln[i + 1]
			var ang := atan2(b.y - a.y, b.x - a.x)
			var nseg := 3
			for k in nseg:
				var c: Vector2 = a.lerp(b, (k + 0.5) / nseg)
				var hl := a.distance_to(b) / nseg * 0.62
				var ii := i * 3 + k
				items.append([dep(f, c.x, c.y), func() -> void:
					var cc := K.wp(f, c.x, c.y)
					var ecol := P.mul(EARTH, 0.96 + 0.08 * P.hn(ii, int(far), 520))
					P.box(cv, o, Vector3(cc.x, cc.y, 0), hl + 0.03, 0.1 if far else 0.08, 2.5 if far else 1.5, K.rot(f) + ang, ecol, 0.16, 521 + ii)
					if far:
						bag(cv, o, f, c.x, c.y, 2.5, hl * 0.92, 0.065, 4.0, P.mul(SAND, 1.0 + 0.12 * P.hn(ii, 1, 522)), 530 + ii, ang)])
	layered(items)
	# firing-step crate + team marker on the parapet
	var mk: Vector2 = (lo if far_left else ro)[3]
	team_flag(cv, o, f, mk.x, mk.y, 14.0)
	var cr: Vector2 = (ro if far_left else lo)[4]
	var crate := bx(cv, o, f, cr.x, cr.y, 0, 0.07, 0.05, 4.0, Color8(96, 100, 66), 0.08, 550)
	B.edges(cv, crate, Color8(96, 100, 66))


# ---------------------------------------------------------------- s_sandbags
## One bag: a small box with a dark seam frame on every visible face, a lighter belly line and a tied ear,
## so each bag reads on its own at 1x.
static func bag(cv, o: Vector2, f: int, u: float, v: float, z: float, hu: float, hv: float, hz: float, col: Color, s: int, ang := 0.0) -> Dictionary:
	var c := K.wp(f, u, v)
	var r := P.box(cv, o, Vector3(c.x, c.y, z), hu, hv, hz, K.rot(f) + ang, col, 0.1, s)
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		var k := P.side_shade(sd.n)
		cv.line_v(q[0], q[1], P.mul(col, k * 0.6))
		cv.line_v(q[0], q[3], P.mul(col, k * 0.5))
		cv.line_v(q[1], q[2], P.mul(col, k * 0.5))
		cv.px(int(q[3].x), int(q[3].y), Color(0, 0, 0, 0.35))  # rounded shoulders
		cv.px(int(q[2].x), int(q[2].y), Color(0, 0, 0, 0.35))
		var m0: Vector2 = q[0].lerp(q[3], 0.55)
		var m1: Vector2 = q[1].lerp(q[2], 0.55)
		cv.line_v(m0.lerp(m1, 0.2), m0.lerp(m1, 0.8), P.mul(col, k * 1.1))
	var t: PackedVector2Array = r.top
	cv.line_v(t[0].lerp(t[3], 0.5), t[1].lerp(t[2], 0.5), P.mul(col, 1.12))
	cv.line_v(t[3], t[2], P.mul(col, 0.8))
	var ear: Vector2 = t[1].lerp(t[2], 0.5)
	cv.px(int(ear.x), int(ear.y), P.mul(col, 0.72))
	return r


static func sandbags(cv, o: Vector2, f: int) -> void:
	bshadow(cv, o, f, 0, 0, 0, 0.5, 0.18, 12)
	cv.flush_shadow()
	var items: Array = []  # [z, depth, u, v, hu, hv]
	var sp := 0.25
	for i in 4:  # bottom course, two rows
		for vv in [-0.09, 0.09]:
			items.append([0.0, -0.5 + sp * (i + 0.5), vv, 0.112, 0.085])
	for i in 5:  # second course, offset half a bag (half bags at the cell edges so the line tiles)
		var c := -0.5 + sp * i
		var hu := 0.112
		if i == 0:
			c = -0.5 + 0.056
			hu = 0.054
		elif i == 4:
			c = 0.5 - 0.056
			hu = 0.054
		for vv in [-0.075, 0.075]:
			items.append([4.2, c, vv, hu, 0.078])
	for i in 4:  # top course, one row
		items.append([8.4, -0.5 + sp * (i + 0.5), 0.0, 0.112, 0.088])
	items.sort_custom(func(a, b):
		if float(a[0]) != float(b[0]):
			return float(a[0]) < float(b[0])
		return dep(f, a[1], a[2]) < dep(f, b[1], b[2]))
	var n := 0
	for it in items:
		n += 1
		var col := P.mul(SAND, 0.86 + 0.2 * P.hn(n, int(it[0]), 77))
		if P.hn(n, 3, 78) < 0.18:
			col = P.mix(col, Color8(124, 116, 80), 0.6)  # an older, olive-drab bag here and there
		bag(cv, o, f, it[1], it[2], it[0], it[3], it[4], 4.2, col, 70 + n)
	# team cloth tied round the middle top bag
	var tp := K.pt(o, f, 0.125, 0.088, 11.5)
	cv.team = true
	cv.rect(int(tp.x) - 1, int(tp.y) - 1, 3, 2, Color(0.8, 0.8, 0.8))
	cv.px(int(tp.x) + 1, int(tp.y) + 1, Color(0.7, 0.7, 0.7))
	cv.team = false


# ---------------------------------------------------------------- s_tank_traps
## Truncated pyramid (dragon's tooth): base half hb, top half ht (tiles), height hz px.
static func frustum(cv, o: Vector2, f: int, u: float, v: float, hb: float, ht: float, hz: float, col: Color, s: int) -> Dictionary:
	var c := K.wp(f, u, v)
	var rt := K.rot(f) + 0.35
	var ax := Vector2(cos(rt), sin(rt))
	var ay := Vector2(-sin(rt), cos(rt))
	var loc := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var gb: Array = []
	var gt: Array = []
	for l in loc:
		var wb: Vector2 = c + ax * l.x * hb + ay * l.y * hb
		var wt: Vector2 = c + ax * l.x * ht + ay * l.y * ht
		gb.append(P.proj(o, Vector3(wb.x, wb.y, 0)))
		gt.append(P.proj(o, Vector3(wt.x, wt.y, hz)))
	var normals := [-ay, ax, ay, -ax]
	var sides: Array = []
	for i in 4:
		var nn: Vector2 = normals[i]
		if nn.x + nn.y <= 0.001:
			continue
		var j := (i + 1) % 4
		var q := PackedVector2Array([gb[i], gb[j], gt[j], gt[i]])
		cv.poly(q, P.mul(col, P.side_shade(nn)), P.speckle(0.1, s + i))
		sides.append({"quad": q, "n": nn})
	var top := PackedVector2Array(gt)
	cv.poly(top, P.mul(col, 1.06), P.speckle(0.08, s + 7))
	return {"sides": sides, "top": top}


static func tooth(cv, o: Vector2, f: int, u: float, v: float, s: int) -> void:
	var col := P.mul(BLD.JERSEY, 0.96 + 0.08 * P.hn(s, 1, 5))
	var r := frustum(cv, o, f, u, v, 0.12, 0.05, 15.0, col, s)
	B.wall_ao(cv, r, 0.24)
	cv.team = true
	for sd in r.sides:
		cv.poly(P.sub(sd.quad, 0.0, 0.62, 1.0, 0.74), Color(0.8, 0.8, 0.8))
	cv.team = false
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		cv.line_v(q[3], q[2], P.mul(col, 1.25))
		for k in 3:  # chips / weathering
			var cp: Vector2 = P.sub(q, P.hn(k, s, 7), P.hn(k, s, 8) * 0.5, 0, 0)[0]
			cv.px(int(cp.x), int(cp.y), P.mul(col, 0.7))


static func hedgehog(cv, o: Vector2, f: int, u: float, v: float, s: int) -> void:
	var beams: Array = []
	for k in 3:
		var a := K.rot(f) + 0.5 + k * TAU / 3.0
		var d := Vector2(cos(a), sin(a)) * 0.18
		var c := K.wp(f, u, v)
		var lo := Vector3(c.x - d.x, c.y - d.y, 1.0)
		var hi := Vector3(c.x + d.x, c.y + d.y, 17.0)
		beams.append([hi.x + hi.y - (lo.x + lo.y) * 0.2, lo, hi])
	beams.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var rust := Color8(118, 78, 52)
	for bm in beams:
		var a2 := P.proj(o, bm[1])
		var b2 := P.proj(o, bm[2])
		cv.line_v(a2 + Vector2(1, 0), b2 + Vector2(1, 0), P.mul(STEEL, 0.62))
		cv.line_v(a2, b2, P.mul(STEEL, 0.95))
		cv.line_v(a2 + Vector2(-1, 0), b2 + Vector2(-1, 0), P.mul(STEEL_L, 0.95))
		for t in [0.25, 0.7]:
			var rp := a2.lerp(b2, t + 0.08 * P.hn(s, int(t * 10), 3))
			cv.px(int(rp.x), int(rp.y), rust)
		cv.rect(int(b2.x) - 1, int(b2.y) - 1, 3, 1, P.mul(STEEL_L, 1.05))  # flange cap


static func tank_traps(cv, o: Vector2, f: int) -> void:
	var spots := [[-0.375, -0.13, 0], [-0.125, 0.13, 1], [0.125, -0.13, 1], [0.375, 0.13, 0]]
	for sp in spots:
		if int(sp[2]) == 0:
			bshadow(cv, o, f, sp[0], sp[1], 0, 0.08, 0.08, 13)
		else:
			bshadow(cv, o, f, sp[0], sp[1], 0, 0.1, 0.1, 9)
	cv.flush_shadow()
	var items: Array = []
	var n := 0
	for sp in spots:
		n += 1
		var nn := n
		if int(sp[2]) == 0:
			items.append([dep(f, sp[0], sp[1]), func() -> void: tooth(cv, o, f, sp[0], sp[1], 300 + nn * 11)])
		else:
			items.append([dep(f, sp[0], sp[1]), func() -> void: hedgehog(cv, o, f, sp[0], sp[1], 400 + nn * 11)])
	layered(items)


# ---------------------------------------------------------------- s_barbed_wire
## Concertina coil along local u at (v, zc): helix of radius rv (tiles) x rz (px). pass 0 = far half only,
## pass 1 = near half only.
static func coil(cv, o: Vector2, f: int, v: float, zc: float, rv: float, rz: float, pass_near: int, s: int) -> void:
	var steps := 220
	var prev := Vector2.ZERO
	var c0 := dep(f, 0, v)
	for i in steps + 1:
		var u := -0.5 + float(i) / steps
		var a := (u + 0.5) * TAU / 0.125 + s
		var pv := v + rv * cos(a)
		var pz := zc + rz * sin(a)
		var p2 := K.pt(o, f, u + 0.015 * sin(a), pv, pz)
		var near := dep(f, 0, pv) >= c0
		if i > 0 and int(near) == pass_near:
			var col := STEEL_L if near else Color(STEEL.r, STEEL.g, STEEL.b, 0.55)
			if near and sin(a) > 0.6:
				col = P.mul(col, 1.18)
			cv.line_v(prev, p2, col)
			if i % 9 == 0:  # barbs
				cv.px(int(p2.x) + 1, int(p2.y) - 1, P.mul(col, 0.85))
				cv.px(int(p2.x) - 1, int(p2.y) + 1, P.mul(col, 0.85))
		prev = p2


static func picket(cv, o: Vector2, f: int, u: float, v: float, h: float) -> void:
	var b := K.pt(o, f, u, v, 0)
	var t := K.pt(o, f, u, v, h)
	cv.line_v(b, t, P.mul(STEEL, 0.85))
	cv.line_v(b + Vector2(1, 0), t + Vector2(1, 0), P.mul(STEEL, 0.6))
	cv.px(int(t.x), int(t.y), STEEL_L)
	for z in [h * 0.35, h * 0.75]:  # eye loops holding the wire
		var e := K.pt(o, f, u, v, z)
		cv.px(int(e.x) - 1, int(e.y), STEEL_L)


static func barbed_wire(cv, o: Vector2, f: int) -> void:
	bshadow(cv, o, f, 0, 0, 0, 0.5, 0.2, 7)
	cv.flush_shadow(Color(0.04, 0.05, 0.03, 0.26))
	var coils := [[-0.12, 5.0], [0.12, 5.0], [0.0, 13.5]]
	var order := coils.duplicate()
	order.sort_custom(func(a, b):
		if float(a[1]) != float(b[1]):
			return float(a[1]) < float(b[1])
		return dep(f, 0, a[0]) < dep(f, 0, b[0]))
	for c in order:
		coil(cv, o, f, c[0], c[1], 0.1, 5.0, 0, int(c[0] * 10.0) + 3)
	var posts := [[-0.25, -0.2], [0.25, -0.2], [-0.25, 0.2], [0.25, 0.2]]
	var pitems: Array = []
	for pt in posts:
		pitems.append([dep(f, pt[0], pt[1]), func() -> void: picket(cv, o, f, pt[0], pt[1], 19.0)])
	layered(pitems)
	for c in order:
		coil(cv, o, f, c[0], c[1], 0.1, 5.0, 1, int(c[0] * 10.0) + 3)
	# team rag tied to a front picket
	var r0 := K.pt(o, f, 0.25, 0.2, 17.0)
	cv.team = true
	cv.rect(int(r0.x) + 1, int(r0.y), 3, 2, Color(0.82, 0.82, 0.82))
	cv.px(int(r0.x) + 3, int(r0.y) + 2, Color(0.7, 0.7, 0.7))
	cv.team = false


# ---------------------------------------------------------------- s_minefield
const MINE_AT := Color8(84, 92, 62)
const MINE_AP := Color8(60, 66, 48)


static func minefield(cv, o: Vector2, f: int) -> void:
	var e := 0.86
	# disturbed soil over every mine, then the mines half covered by soil
	var mines: Array = []
	for k in 7:
		mines.append([-0.65 + P.hn(k, 1, 601) * 1.3, -0.65 + P.hn(k, 2, 601) * 1.3, 0])
	for k in 10:
		mines.append([-0.72 + P.hn(k, 3, 602) * 1.44, -0.72 + P.hn(k, 4, 602) * 1.44, 1])
	mines.sort_custom(func(a, b): return dep(f, a[0], a[1]) < dep(f, b[0], b[1]))
	for m in mines:
		var c := K.pt(o, f, m[0], m[1], 0)
		var big := int(m[2]) == 0
		var rx := 5.0 if big else 3.0
		cv.ellipse(c.x, c.y, rx, rx * 0.5, Color(0.25, 0.2, 0.12, 0.5))
		cv.ellipse(c.x - 1, c.y - 1, rx * 0.8, rx * 0.4, Color(0.55, 0.44, 0.3, 0.45))
	var n := 0
	for m in mines:
		n += 1
		var c := K.pt(o, f, m[0], m[1], 0)
		if int(m[2]) == 0:  # AT mine: olive disc, pressure plate, soil grains over the near half
			cv.ellipse(c.x, c.y, 3.6, 1.9, P.mul(MINE_AT, 0.7))
			cv.ellipse(c.x, c.y - 1, 3.4, 1.7, MINE_AT)
			cv.ellipse(c.x, c.y - 1.2, 1.5, 0.8, P.mul(MINE_AT, 1.3))
			cv.px(int(c.x), int(c.y) - 2, Color8(160, 160, 148))
			for g in 6:
				var gx := int(c.x - 3 + P.hi(n, g, 603, 7))
				var gy := int(c.y - 1 + P.hi(n, g, 604, 2))
				cv.px(gx, gy, P.mul(EARTH, 0.9 + 0.3 * P.hn(n, g, 605)))
		else:  # AP mine: small dark disc with fuse prongs, a few with a tripwire stake
			cv.rect(int(c.x) - 1, int(c.y) - 1, 3, 2, MINE_AP)
			cv.px(int(c.x), int(c.y) - 2, Color8(130, 130, 120))
			cv.px(int(c.x) - 1, int(c.y) - 2, P.mul(MINE_AP, 1.3))
			if n % 4 == 0:
				var s2 := K.pt(o, f, m[0] + 0.14, m[1] - 0.06, 0)
				cv.line_v(s2, s2 + Vector2(0, -3), WOOD)
				cv.line_v(c + Vector2(0, -2), s2 + Vector2(0, -2), Color(0.75, 0.75, 0.7, 0.6))
	# owner-view boundary: dashed team-colour line painted on the ground around the field
	var corners := [Vector2(-e, -e), Vector2(e, -e), Vector2(e, e), Vector2(-e, e)]
	cv.team = true
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var segs := 9
		for k in segs:
			var t0 := float(k) / segs
			var t1 := t0 + 0.55 / segs
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			var q0 := K.pt(o, f, p0.x, p0.y, 0)
			var q1 := K.pt(o, f, p1.x, p1.y, 0)
			cv.line_v(q0, q1, Color(0.92, 0.92, 0.92))
			cv.line_v(q0 + Vector2(0, 1), q1 + Vector2(0, 1), Color(0.62, 0.62, 0.62))
	cv.team = false
	# boundary stakes with red warning signs (corners) and plain pickets (edge midpoints)
	var stakes: Array = []
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		stakes.append([a, true])
		stakes.append([a.lerp(b, 0.5), false])
	var items: Array = []
	for st in stakes:
		var p: Vector2 = st[0]
		var sign: bool = st[1]
		items.append([dep(f, p.x, p.y), func() -> void:
			var b0 := K.pt(o, f, p.x, p.y, 0)
			var h := 13 if sign else 9
			cv.line_v(b0, b0 + Vector2(0, -h), WOOD)
			cv.line_v(b0 + Vector2(1, 0), b0 + Vector2(1, -h), P.mul(WOOD, 0.7))
			if sign:
				var t := b0 + Vector2(0, -h)
				cv.poly(PackedVector2Array([t + Vector2(-3, 0), t + Vector2(4, 0), t + Vector2(0.5, -6)]), K.RED)
				cv.poly(PackedVector2Array([t + Vector2(-1, -1), t + Vector2(2, -1), t + Vector2(0.5, -4)]), K.WHITE)
				cv.px(int(t.x), int(t.y) - 2, Color8(30, 28, 26))
			else:
				var t2 := b0 + Vector2(0, -h)
				cv.rect(int(t2.x), int(t2.y), 2, 2, K.RED)])
	layered(items)


# ---------------------------------------------------------------- s_garrison_bld
const PLASTER := Color8(150, 142, 124)
const BRICK := Color8(140, 82, 62)


## Rubble heap of concrete / brick chips around local (u, v).
static func rubble(cv, o: Vector2, f: int, u: float, v: float, r: float, s: int) -> void:
	var c := K.pt(o, f, u, v, 0)
	cv.ellipse(c.x, c.y - 1, r * 22.0, r * 10.0, Color8(104, 98, 88))
	cv.ellipse(c.x - 1, c.y - 2, r * 15.0, r * 7.0, Color8(120, 114, 102))
	for k in int(8 + r * 30):
		var dx := (P.hn(k, s, 1) - 0.5) * r * 40.0
		var dy := (P.hn(k, s, 2) - 0.5) * r * 18.0 - 1.0
		var col: Color = [Color8(150, 144, 132), BRICK, Color8(92, 88, 80), PLASTER][P.hi(k, s, 3, 4)]
		cv.rect(int(c.x + dx), int(c.y + dy), 2, 1 + P.hi(k, s, 4, 2), col)


## Sandbags stacked in the lower part of a window opening on a side quad.
static func sandbag_window(cv, q: PackedVector2Array, u0: float, u1: float, v0: float, v1: float) -> void:
	cv.poly(P.sub(q, u0 - 0.01, v0 - 0.02, u1 + 0.01, v1 + 0.02), Color8(70, 66, 58))
	cv.poly(P.sub(q, u0, v0, u1, v1), Color8(26, 28, 26))
	var vm := v0 + (v1 - v0) * 0.55
	var n := 3
	for i in n:
		var a := u0 + (u1 - u0) * i / n
		var b := u0 + (u1 - u0) * (i + 1) / n
		var bq := P.sub(q, a + 0.004, v0, b - 0.004, v0 + (vm - v0) * 0.5)
		cv.poly(bq, P.mul(SAND, 0.92))
		var tq := P.sub(q, a + (b - a) * 0.5, v0 + (vm - v0) * 0.5, minf(b + (b - a) * 0.5, u1) - 0.004, vm)
		cv.poly(tq, SAND)
	cv.line_v(P.sub(q, u0, vm, u1, vm)[0], P.sub(q, u0, vm, u1, vm)[1], P.mul(SAND, 1.15))


static func garrison(cv, o: Vector2, f: int) -> void:
	bshadow(cv, o, f, 0, -0.38, 0, 0.72, 0.36, 32)
	bshadow(cv, o, f, 0, 0.38, 0, 0.72, 0.36, 18)
	cv.flush_shadow()
	var items: Array = []
	items.append([dep(f, 0, -0.38), func() -> void:  # intact 2-storey half
		var a := bx(cv, o, f, 0, -0.38, 0, 0.72, 0.36, 32.0, PLASTER, 0.1, 701)
		B.wall_ao(cv, a, 0.28)
		for sd in a.sides:
			var q: PackedVector2Array = sd.quad
			cv.line_v(q[0].lerp(q[3], 0.5), q[1].lerp(q[2], 0.5), P.mul(PLASTER, 0.75))  # floor line
			var nw := 3 if absf(K.wp(f, 1, 0).dot(sd.n)) > 0.5 else 2
			for i in nw:
				var u0 := 0.12 + i * 0.8 / nw
				var u1 := u0 + 0.8 / nw * 0.55
				sandbag_window(cv, q, u0, u1, 0.12, 0.38)
				sandbag_window(cv, q, u0, u1, 0.6, 0.85)
			for k in 4:  # exposed brick where plaster spalled off
				var pu := P.hn(k, 702, 1) * 0.85
				var pv := 0.1 + P.hn(k, 702, 2) * 0.8
				cv.poly(P.sub(q, pu, pv, pu + 0.06, pv + 0.07), BRICK)
		var t: PackedVector2Array = a.top
		var par := bx(cv, o, f, 0, -0.38, 32, 0.72, 0.36, 0.0, PLASTER)
		cv.line_v(t[3], t[0], P.mul(PLASTER, 1.2))
		cv.line_v(t[0], t[1], P.mul(PLASTER, 1.1))
		cv.poly(P.sub(t, 0.04, 0.06, 0.96, 0.94), P.mul(PLASTER, 0.82))  # roof inside the parapet
		cv.poly(P.sub(t, 0.55, 0.3, 0.75, 0.6), Color8(30, 30, 28))  # shell hole in the roof
		cv.poly(P.sub(t, 0.57, 0.33, 0.7, 0.5), Color8(64, 54, 44))
		B.hvac(cv, o, Vector3(K.wp(f, -0.4, -0.45).x, K.wp(f, -0.4, -0.45).y, 32), 0.1, 0.08, 703)
		var fp := K.wp(f, -0.55, -0.6)
		var fb := P.proj(o, Vector3(fp.x, fp.y, 32))
		cv.line_v(fb, fb + Vector2(0, -14), Color8(60, 58, 52))
		cv.team = true
		cv.rect(int(fb.x) + 1, int(fb.y) - 14, 7, 4, Color(0.85, 0.85, 0.85))
		cv.rect(int(fb.x) + 1, int(fb.y) - 14, 7, 1, Color(1, 1, 1))
		cv.team = false
		for sd in a.sides:  # team banner hung from the upper floor
			if absf(K.wp(f, 0, 1).dot(sd.n)) > 0.5:
				cv.team = true
				cv.poly(P.sub(sd.quad, 0.86, 0.5, 0.95, 0.92), Color(0.8, 0.8, 0.8))
				cv.team = false])
	items.append([dep(f, 0, 0.38), func() -> void:  # gutted half: ground floor + broken upper wall stubs
		var b2 := bx(cv, o, f, 0, 0.38, 0, 0.72, 0.36, 16.0, P.mul(PLASTER, 0.96), 0.1, 711)
		B.wall_ao(cv, b2, 0.28)
		for sd in b2.sides:
			var q: PackedVector2Array = sd.quad
			sandbag_window(cv, q, 0.12, 0.32, 0.2, 0.75)
			sandbag_window(cv, q, 0.68, 0.88, 0.2, 0.75)
			B.door(cv, q, 0.43, 0.57, 0.72, PLASTER)
		var t: PackedVector2Array = b2.top
		cv.poly(t, Color8(96, 92, 84), P.speckle(0.14, 712))  # exposed floor slab
		for k in 10:
			var cp: Vector2 = P.sub(t, P.hn(k, 713, 1), P.hn(k, 713, 2), 0, 0)[0]
			cv.rect(int(cp.x), int(cp.y), 2, 1, Color8(128, 122, 110) if k % 2 == 0 else BRICK)
		# broken wall stubs along the two outer edges of the gutted floor
		var stubs: Array = []
		for k in 7:
			var uu := -0.66 + k * 0.22
			stubs.append([uu, 0.72, 0.11, 0.04])
		for k in 3:
			var vv := 0.1 + k * 0.22
			stubs.append([0.68, vv, 0.04, 0.11])
			stubs.append([-0.68, vv, 0.04, 0.11])
		stubs.sort_custom(func(p1, p2): return dep(f, p1[0], p1[1]) < dep(f, p2[0], p2[1]))
		var n := 0
		for st in stubs:
			n += 1
			var hz := 2.0 + P.hn(n, 714, 1) * 11.0
			if n % 3 == 0:
				hz = 1.0
			var sr := bx(cv, o, f, st[0], st[1], 16, st[2], st[3], hz, PLASTER, 0.1, 715 + n)
			for sd in sr.sides:
				if hz > 8.0:
					cv.poly(P.sub(sd.quad, 0.2, 0.35, 0.8, 0.8), Color8(30, 30, 28))
			var tp: PackedVector2Array = sr.top
			cv.px(int(tp[0].x), int(tp[0].y) - 1, Color8(84, 62, 46))  # rebar
		rubble(cv, o, f, 0.1, 0.4, 0.18, 716)])
	layered(items)
	for rp in [[0.85, 0.75, 0.2, 721], [-0.9, 0.55, 0.14, 722], [0.82, -0.8, 0.12, 723]]:
		rubble(cv, o, f, rp[0], rp[1], rp[2], rp[3])


# ---------------------------------------------------------------- s_camo_decoy
const NET_A := Color8(86, 92, 56)
const NET_B := Color8(112, 100, 66)
const NET_C := Color8(62, 70, 44)


## Copy a scratch canvas onto cv (alpha blend, team mask carried over).
static func paste_cv(cv, tc) -> void:
	for y in cv.h:
		for x in cv.w:
			var c: Color = tc.img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			cv.img.set_pixel(x, y, cv.img.get_pixel(x, y).blend(c))
			if tc.mask.get_pixel(x, y).a > 0.0:
				cv.mask.set_pixel(x, y, Color(1, 1, 1, 1))
			elif c.a > 0.9:
				cv.mask.set_pixel(x, y, Color(0, 0, 0, 0))


## Camouflage net draped over poles above a vehicle at local (u, v): lumpy facets from a ground skirt to
## three ridge peaks, mottled 3-tone fill with burlap strips; the muzzle pokes out at the front.
static func net(cv, o: Vector2, f: int, u: float, v: float) -> void:
	var rim: Array = []
	for i in 10:
		var a := i * TAU / 10.0
		var ru := 0.78 + 0.06 * P.hn(i, 1, 801)
		var rv := 0.5 + 0.05 * P.hn(i, 2, 801)
		var z := 0.0 if cos(a) < 0.3 else 4.0
		rim.append(Vector3(u + cos(a) * ru, v + sin(a) * rv, z))
	var peaks := [Vector3(u - 0.4, v, 15.0), Vector3(u + 0.05, v + 0.04, 19.0), Vector3(u + 0.45, v - 0.03, 14.0)]
	var facets: Array = []
	for i in 10:
		var a3: Vector3 = rim[i]
		var b3: Vector3 = rim[(i + 1) % 10]
		var mid := Vector2((a3.x + b3.x) * 0.5, (a3.y + b3.y) * 0.5)
		var best: Vector3 = peaks[0]
		for pk in peaks:
			if Vector2(pk.x, pk.y).distance_to(mid) < Vector2(best.x, best.y).distance_to(mid):
				best = pk
		facets.append([a3, b3, best])
	for i in 2:
		facets.append([peaks[i], peaks[i + 1], rim[2 if i == 0 else 1]])
		facets.append([peaks[i], peaks[i + 1], rim[7 if i == 0 else 8]])
	facets.sort_custom(func(p1, p2):
		var c1: Vector3 = (p1[0] + p1[1] + p1[2]) / 3.0
		var c2: Vector3 = (p2[0] + p2[1] + p2[2]) / 3.0
		return dep(f, c1.x, c1.y) + c1.z * 0.01 < dep(f, c2.x, c2.y) + c2.z * 0.01)
	var hullp := PackedVector2Array()
	for p3 in rim + peaks:
		hullp.append(K.pt(o, f, p3.x, p3.y, p3.z))
	cv.poly(Geometry2D.convex_hull(hullp), P.mul(NET_C, 0.85))
	var nf := 0
	for fc in facets:
		nf += 1
		var pts := PackedVector2Array()
		for p3 in fc:
			pts.append(K.pt(o, f, p3.x, p3.y, p3.z))
		var cen: Vector3 = (fc[0] + fc[1] + fc[2]) / 3.0
		var tilt := K.wp(f, cen.x - u, cen.y - v)
		var k := 0.82 + 0.22 * clampf(tilt.normalized().dot(Vector2(-0.94, -0.33)), -1.0, 1.0) + 0.06 * (cen.z / 19.0)
		var sd := 810 + nf
		cv.poly(pts, NET_A, func(x: int, y: int, _b: Color) -> Color:
			var n2 := P.vnoise(x, y, 3.5, 811)
			var col := NET_A if n2 < 0.45 else (NET_B if n2 < 0.7 else NET_C)
			if (x + y * 2) % 5 == 0:
				col = P.mul(col, 0.78)  # mesh holes
			return P.mul(col, k * (0.94 + 0.12 * P.hn(x, y, sd))))
	for i in 10:  # burlap strips along the skirt
		var a3: Vector3 = rim[i]
		var p2 := K.pt(o, f, a3.x, a3.y, a3.z)
		cv.line_v(p2, p2 + Vector2(P.hi(i, 3, 812, 3) - 1, -3), P.mul(NET_B, 1.15))
	for pk in peaks:  # pole tips pushing the net up
		var tp := K.pt(o, f, pk.x, pk.y, pk.z)
		cv.px(int(tp.x), int(tp.y) - 1, P.mul(WOOD, 1.1))


## Inflatable decoy: the real MBT drawer repainted as smooth, slightly glossy rubber (3 flat tones, bright
## seams and specular streaks), staked down with guy ropes and fed by a small blower.
static func decoy(cv, o: Vector2, f: int, u: float, v: float) -> void:
	var tc = P.Canvas.new(cv.w, cv.h)
	var po := K.pt(o, f, u, v, 0)
	VH.draw(tc, "mbt", K.rot(f), 0, false, po)
	var rub := Color8(124, 136, 90)
	for y in tc.h:
		for x in tc.w:
			var c: Color = tc.img.get_pixel(x, y)
			if c.a < 0.6:
				continue
			var l := c.get_luminance()
			var tone: Color
			if l < 0.13:
				tone = P.mul(rub, 0.42)
			elif l < 0.3:
				tone = P.mul(rub, 0.8)
			else:
				tone = P.mul(rub, 1.06)
			if tc.mask.get_pixel(x, y).a > 0.0:
				tone = Color(l * 1.1, l * 1.1, l * 1.1)
			tc.img.set_pixel(x, y, Color(tone.r, tone.g, tone.b, c.a))
	for k in 3:  # specular streaks
		var sp := K.pt(o, f, u - 0.2 + k * 0.18, v - 0.1, 12.0 + (2.0 if k == 1 else 0.0))
		tc.line_v(sp, sp + Vector2(4, 2), Color8(196, 204, 168))
		tc.line_v(sp + Vector2(1, 1), sp + Vector2(3, 2), Color8(160, 170, 130))
	paste_cv(cv, tc)
	for c4 in [[0.6, 0.45], [-0.6, 0.45], [0.6, -0.45], [-0.6, -0.45]]:  # guy ropes to pegs
		var a2 := K.pt(o, f, u + c4[0] * 0.75, v + c4[1] * 0.75, 7.0)
		var b2 := K.pt(o, f, u + c4[0] * 1.15, v + c4[1] * 1.3, 0.0)
		if dep(f, c4[0], c4[1]) > 0.0:
			cv.line_v(a2, b2, Color8(196, 190, 160))
			cv.px(int(b2.x), int(b2.y), WOOD)
	var bl := Vector2(u - 0.8, v + 0.35)
	var hb := K.pt(o, f, bl.x, bl.y, 3.0)
	B.cable(cv, hb, K.pt(o, f, u - 0.5, v + 0.15, 3.0), 2.0, Color8(36, 36, 34))
	var blow := bx(cv, o, f, bl.x, bl.y, 0, 0.08, 0.06, 5.0, Color8(176, 150, 52), 0.06, 820)
	B.edges(cv, blow, Color8(176, 150, 52))


static func camo_decoy(cv, o: Vector2, f: int) -> void:
	var nu := 0.0
	var nv := -0.5
	var du := 0.05
	var dv := 0.52
	var items: Array = []
	items.append([dep(f, nu, nv), func() -> void:
		var tc = P.Canvas.new(cv.w, cv.h)
		VH.draw(tc, "mbt", K.rot(f), 0, false, K.pt(o, f, nu, nv, 0))
		paste_cv(cv, tc)
		net(cv, o, f, nu, nv)])
	items.append([dep(f, du, dv), func() -> void: decoy(cv, o, f, du, dv)])
	layered(items)


# ---------------------------------------------------------------- m_nanite_wall
static func _cy(a: float) -> Color:
	return Color(L.CYAN.r, L.CYAN.g, L.CYAN.b, a)


## Hex-cell graphite wall segment along local u; panel 2 is breached and regrowing: a ragged stump, the
## missing volume outlined by a holo lattice, half-printed cyan hex cells and a swarm of nanite sparks.
static func nanite_wall(cv, o: Vector2, f: int) -> void:
	var hzw := 22.0
	bshadow(cv, o, f, 0, 0, 0, 0.5, 0.12, hzw + 3.0)
	cv.flush_shadow()
	var rail := bx(cv, o, f, 0, 0, 0, 0.5, 0.13, 3.0, L.GRAPH_D, 0.05, 901)
	for sd in rail.sides:
		if absf(K.wp(f, 0, 1).dot(sd.n)) > 0.5:
			L.team_panel(cv, sd.quad, 0.0, 0.3, 1.0, 0.75)
	var ids := [0, 1, 2, 3]
	ids.sort_custom(func(a, b): return dep(f, -0.375 + a * 0.25, 0) < dep(f, -0.375 + b * 0.25, 0))
	for i: int in ids:
		var u := -0.375 + i * 0.25
		var broken := i == 2
		var h := 9.0 if broken else hzw
		var r := bx(cv, o, f, u, 0, 3, 0.12, 0.09, h, L.GRAPH, 0.06, 910 + i)
		for sd in r.sides:
			var q: PackedVector2Array = sd.quad
			var along := absf(K.wp(f, 0, 1).dot(sd.n)) > 0.5
			if along:
				for hv in [[0.3, 0.3], [0.7, 0.3], [0.5, 0.62], [0.3, 0.9], [0.7, 0.9]]:
					if broken and hv[1] > 0.5:
						continue
					L.hex_plate(cv, q, hv[0], hv[1] if not broken else hv[1] * 1.6, 2.2, L.GRAPH_D, P.hn(i, int(hv[0] * 10), 911) < 0.3)
				if not broken:
					cv.poly(P.sub(q, 0.14, 0.56, 0.86, 0.9), P.mul(L.PANEL, 0.72 + 0.2 * (P.side_shade(sd.n) - 0.6)))  # light armour inlay
					cv.line_v(P.sub(q, 0.14, 0.9, 0.86, 0.9)[0], P.sub(q, 0.14, 0.9, 0.86, 0.9)[1], P.mul(L.PANEL, 1.05))
					L.hex_plate(cv, P.sub(q, 0.14, 0.56, 0.86, 0.9), 0.5, 0.5, 1.8, L.GRAPH_D, true)
					L.seam(cv, q, 0.48)
			cv.line_v(q[0], q[3], L.JOINT)
		if not broken:
			var cap := bx(cv, o, f, u, 0, 3 + h, 0.125, 0.1, 2.0, L.PANEL, 0.04, 920 + i)
			B.edges(cv, cap, L.PANEL)
			var tc := K.pt(o, f, u, 0, 5 + h)
			cv.px(int(tc.x), int(tc.y), L.CYAN)
		else:
			var t: PackedVector2Array = r.top
			for k in 5:  # ragged break
				var cp: Vector2 = t[0].lerp(t[1], k / 4.0)
				cv.rect(int(cp.x), int(cp.y) - P.hi(k, i, 912, 3), 2, 1 + P.hi(k, i, 913, 3), P.mul(L.GRAPH, 1.1))
			L.holo_box(cv, o, Vector3(K.wp(f, u, 0).x, K.wp(f, u, 0).y, 3 + h), 0.12, 0.09, hzw - h + 2.0, 0.5)
			var top := K.pt(o, f, u, 0, 3 + h)
			for k in 3:  # half-printed hex cells climbing the breach
				var hc := top + Vector2(-4 + k * 4, -3 - k * 3)
				var pts := PackedVector2Array()
				for j in 6:
					var a := j * PI / 3.0
					pts.append(hc + Vector2(cos(a) * 3.2, sin(a) * 2.0))
				cv.poly(pts, _cy(0.42 - k * 0.1))
				cv.px(int(hc.x), int(hc.y), L.CYAN_HOT)
			for k in 16:  # nanite sparks
				var sx := top.x + (P.hn(k, 1, 914) - 0.5) * 12.0
				var sy := top.y - P.hn(k, 2, 914) * (hzw - h + 4.0)
				cv.px(int(sx), int(sy), L.CYAN_HOT if k % 3 == 0 else _cy(0.55))
	# repair-feed conduit glow along the rail
	for k in 6:
		var gp := K.pt(o, f, -0.45 + k * 0.18, 0.13, 3.0)
		cv.px(int(gp.x), int(gp.y), L.CYAN)


# ---------------------------------------------------------------- m_phase_gate
static func _emitter(cv, o: Vector2, f: int, u: float, ph: float) -> void:
	var c := K.wp(f, u, 0)
	var base: Dictionary = L.hexp(cv, o, Vector3(c.x, c.y, 0), 0.15, 8.0, K.rot(f), L.GRAPH_D, 951)
	for sd in base.sides:
		L.team_panel(cv, sd.quad, 0.15, 0.25, 0.85, 0.7)
	var col: Dictionary = L.hexp(cv, o, Vector3(c.x, c.y, 8), 0.1, ph - 8.0, K.rot(f), L.GRAPH, 952)
	for sd in col.sides:
		var q: PackedVector2Array = sd.quad
		for vv in [0.25, 0.5, 0.75]:  # emitter rings
			cv.line_v(q[0].lerp(q[3], vv), q[1].lerp(q[2], vv), L.CYAN)
		L.seam(cv, q, 0.9)
	var cap: Dictionary = L.hexp(cv, o, Vector3(c.x, c.y, ph), 0.13, 3.0, K.rot(f), L.PANEL, 953)
	var tip := P.proj(o, Vector3(c.x, c.y, ph + 3.0))
	cv.ellipse(tip.x, tip.y - 3, 4.5, 5.5, _cy(0.22))
	cv.poly(PackedVector2Array([tip + Vector2(0, 0), tip + Vector2(2.5, -4), tip + Vector2(0, -9), tip + Vector2(-2.5, -4)]), L.CYAN)
	cv.poly(PackedVector2Array([tip + Vector2(0, -1), tip + Vector2(1.2, -4), tip + Vector2(0, -7), tip + Vector2(-1, -4)]), L.CYAN_HOT)


static func phase_gate(cv, o: Vector2, f: int) -> void:
	var ph := 34.0
	for u in [-0.38, 0.38]:
		var c := K.wp(f, u, 0)
		L.hex_shadow(cv, o, Vector3(c.x, c.y, 0), 0.15, ph, K.rot(f))
	bshadow(cv, o, f, 0, 0, 0, 0.3, 0.12, 2)
	cv.flush_shadow()
	var plate := bx(cv, o, f, 0, 0, 0, 0.3, 0.14, 1.5, L.GRAPH_D, 0.05, 960)
	for k in 3:  # threshold chevrons
		var a := K.pt(o, f, -0.18 + k * 0.18, -0.08, 1.5)
		var m := K.pt(o, f, -0.12 + k * 0.18, 0.0, 1.5)
		var b := K.pt(o, f, -0.18 + k * 0.18, 0.08, 1.5)
		cv.line_v(a, m, L.CYAN)
		cv.line_v(m, b, L.CYAN)
	var us := [-0.38, 0.38]
	us.sort_custom(func(a, b): return dep(f, a, 0) < dep(f, b, 0))
	_emitter(cv, o, f, us[0], ph)
	# shimmering phase field: vertical interference bands, scan lines, hot rims; alpha < 0.6 (no outline)
	var z0 := 2.0
	var z1 := ph - 2.0
	var q := PackedVector2Array([K.pt(o, f, -0.3, 0, z0), K.pt(o, f, 0.3, 0, z0), K.pt(o, f, 0.3, 0, z1), K.pt(o, f, -0.3, 0, z1)])
	cv.poly(q, _cy(0.26))
	var nb := 9
	for i in nb + 1:
		var t := float(i) / nb
		var wob := 0.03 * sin(i * 1.7)
		var a2: Vector2 = q[0].lerp(q[1], clampf(t + wob, 0, 1))
		var b2: Vector2 = q[3].lerp(q[2], clampf(t - wob, 0, 1))
		var al := 0.16 + 0.22 * (0.5 + 0.5 * sin(t * PI * 3.0))
		cv.line_v(a2, b2, _cy(al))
	for vv in [0.2, 0.4, 0.6, 0.8]:
		cv.line_v(q[0].lerp(q[3], vv), q[1].lerp(q[2], vv), _cy(0.18))
	for k in 14:  # sparkles drifting through the field
		var sp: Vector2 = P.sub(q, P.hn(k, 1, 961), P.hn(k, 2, 961), 0, 0)[0]
		cv.px(int(sp.x), int(sp.y), Color(L.CYAN_HOT.r, L.CYAN_HOT.g, L.CYAN_HOT.b, 0.55))
	cv.line_v(q[0], q[3], Color(L.CYAN_HOT.r, L.CYAN_HOT.g, L.CYAN_HOT.b, 0.5))
	cv.line_v(q[1], q[2], Color(L.CYAN_HOT.r, L.CYAN_HOT.g, L.CYAN_HOT.b, 0.5))
	cv.line_v(q[3], q[2], _cy(0.5))
	_emitter(cv, o, f, us[1], ph)


# ---------------------------------------------------------------- shared Human A building bits
const DOME := Color8(222, 222, 214)


## Shaded hemisphere (radome) of radius r tiles sitting at height z over local (u, v).
static func dome(cv, o: Vector2, f: int, u: float, v: float, z: float, r: float) -> void:
	var c := K.pt(o, f, u, v, z)
	var rx := r * 32.0 * 1.41
	var n := 8
	for i in n:
		var t := float(i) / n
		var k := sqrt(1.0 - t * t)
		var cy := c.y - t * rx * 0.95
		cv.ellipse(c.x, cy, rx * k, rx * k * 0.5, P.mul(DOME, 0.8 + 0.08 * t))
		cv.ellipse(c.x - rx * k * 0.25, cy - 0.5, rx * k * 0.6, rx * k * 0.32, P.mul(DOME, 0.92 + 0.08 * t))
	cv.ellipse(c.x - rx * 0.35, c.y - rx * 0.75, rx * 0.25, rx * 0.15, Color8(244, 244, 238))
	for k in 3:  # panel seams
		var a := -0.6 + k * 0.6
		cv.line_v(Vector2(c.x + a * rx * 0.8, c.y - 1), Vector2(c.x + a * rx * 0.35, c.y - rx * 0.8), P.mul(DOME, 0.78))


## Olive equipment shelter / ISO container with a team roof panel, door and AC unit.
static func shelter(cv, o: Vector2, f: int, u: float, v: float, hu: float, hv: float, hz: float, s: int, col := OLIVE) -> Dictionary:
	var r := bx(cv, o, f, u, v, 2, hu, hv, hz, col, 0.06, s)
	B.wall_ao(cv, r, 0.24)
	B.edges(cv, r, col)
	var n := 0
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		for k in 7:  # container ribs
			var t := 0.06 + k * 0.145
			cv.line_v(q[0].lerp(q[1], t), q[3].lerp(q[2], t), P.mul(col, P.side_shade(sd.n) * 0.86))
		if n == 0:
			B.door(cv, q, 0.62, 0.8, 0.8, col)
		else:
			cv.poly(P.sub(q, 0.15, 0.45, 0.32, 0.75), Color8(120, 122, 118))  # AC unit
			cv.line_v(P.sub(q, 0.15, 0.6, 0.32, 0.6)[0], P.sub(q, 0.15, 0.6, 0.32, 0.6)[1], Color8(70, 72, 70))
		n += 1
	cv.team = true
	cv.poly(P.sub(r.top, 0.12, 0.2, 0.88, 0.8), Color(0.8, 0.8, 0.8))
	cv.team = false
	return r


# ---------------------------------------------------------------- a_radar_station
static func lattice(cv, o: Vector2, f: int, u: float, v: float, b: float, t: float, h: float) -> void:
	var cs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	cs.sort_custom(func(a, c): return dep(f, a.x, a.y) < dep(f, c.x, c.y))
	var levels := 5
	for pass_front in [false, true]:
		for ci in 4:
			var cc: Vector2 = cs[ci]
			var front := ci >= 2
			if front != pass_front:
				continue
			var p0 := K.pt(o, f, u + cc.x * b, v + cc.y * b, 0)
			var p1 := K.pt(o, f, u + cc.x * t, v + cc.y * t, h)
			cv.line_v(p0, p1, STEEL_L if front else STEEL)
		if not pass_front:
			for lv in levels:  # bracing (X between levels on each face) drawn once behind the front legs
				var z0 := h * lv / levels
				var z1 := h * (lv + 1) / levels
				var w0 := lerpf(b, t, float(lv) / levels)
				var w1 := lerpf(b, t, float(lv + 1) / levels)
				for e in 4:
					var a: Vector2 = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)][e]
					var c2: Vector2 = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)][(e + 1) % 4]
					var col := P.mul(STEEL_L, 0.85) if dep(f, (a.x + c2.x), (a.y + c2.y)) > 0 else P.mul(STEEL, 0.8)
					cv.line_v(K.pt(o, f, u + a.x * w0, v + a.y * w0, z0), K.pt(o, f, u + c2.x * w1, v + c2.y * w1, z1), col)
					cv.line_v(K.pt(o, f, u + a.x * w1, v + a.y * w1, z1), K.pt(o, f, u + c2.x * w1, v + c2.y * w1, z1), col)


static func radar_station(cv, o: Vector2, f: int) -> void:
	var ps: Array = [[0, 0, 0, 0.95, 0.95, 2, K.pal("a", "slab"), "slab"]]
	K.render(cv, o, f, ps, 1.0, false, Callable())
	bshadow(cv, o, f, -0.42, 0.42, 2, 0.36, 0.26, 12)
	bshadow(cv, o, f, 0.35, -0.3, 0, 0.12, 0.12, 50)
	bshadow(cv, o, f, -0.45, -0.45, 2, 0.24, 0.24, 24)
	cv.flush_shadow()
	var tu := 0.35
	var tv := -0.3
	var th := 40.0
	var items: Array = []
	items.append([dep(f, -0.42, 0.42), func() -> void: shelter(cv, o, f, -0.42, 0.42, 0.36, 0.24, 12.0, 1001)])
	items.append([dep(f, -0.45, -0.45), func() -> void:  # radome on a concrete drum
		var c := K.wp(f, -0.45, -0.45)
		B.cyl(cv, o, Vector3(c.x, c.y, 2), 0.22, 10.0, CONCRETE, 1002, 0.7, 2)
		dome(cv, o, f, -0.45, -0.45, 12.0, 0.2)])
	items.append([dep(f, tu, tv), func() -> void:  # lattice tower + rotating planar array
		lattice(cv, o, f, tu, tv, 0.17, 0.07, th)
		var deck := bx(cv, o, f, tu, tv, th, 0.1, 0.1, 2.0, STEEL, 0.05, 1003)
		B.edges(cv, deck, STEEL)
		var ang := 0.6
		var d := Vector2(cos(ang), sin(ang))
		var pr := Vector2(-d.y, d.x)
		var hw := 0.3
		var bot := Vector2(tu, tv) + d * 0.02
		var topc := Vector2(tu, tv) - d * 0.07
		var q := PackedVector2Array([K.pt(o, f, bot.x - pr.x * hw, bot.y - pr.y * hw, th + 4), K.pt(o, f, bot.x + pr.x * hw, bot.y + pr.y * hw, th + 4),
			K.pt(o, f, topc.x + pr.x * hw, topc.y + pr.y * hw, th + 17), K.pt(o, f, topc.x - pr.x * hw, topc.y - pr.y * hw, th + 17)])
		var mast := K.pt(o, f, tu, tv, th + 2)
		cv.line_v(mast, mast + Vector2(0, -6), Color8(60, 62, 60))
		var face := dep(f, d.x, d.y) > 0.0
		cv.poly(q, Color8(176, 180, 176) if face else Color8(96, 100, 100))
		for k in 6:
			var tt := (k + 1) / 7.0
			cv.line_v(q[0].lerp(q[1], tt), q[3].lerp(q[2], tt), Color8(130, 134, 132) if face else Color8(70, 74, 74))
		for vv in [0.33, 0.66]:
			cv.line_v(q[0].lerp(q[3], vv), q[1].lerp(q[2], vv), Color8(140, 144, 140) if face else Color8(76, 80, 80))
		cv.line_v(q[3], q[2], Color8(210, 212, 206))
		cv.team = true
		cv.poly(P.sub(q, 0.0, 0.0, 1.0, 0.12), Color(0.75, 0.75, 0.75))
		cv.team = false
		B.lamp(cv, K.pt(o, f, tu, tv, th + 19))])
	items.append([dep(f, 0.55, 0.55), func() -> void:  # generator + cable to the shelter
		var g := bx(cv, o, f, 0.6, 0.5, 2, 0.16, 0.1, 7.0, Color8(104, 108, 70), 0.06, 1004)
		B.edges(cv, g, Color8(104, 108, 70))
		for sd in g.sides:
			for tt in [0.3, 0.45, 0.6]:
				cv.line_v(P.sub(sd.quad, tt, 0.25, tt, 0.8)[0], P.sub(sd.quad, tt, 0.25, tt, 0.8)[3], Color8(54, 56, 44))
		B.cable(cv, K.pt(o, f, 0.45, 0.5, 4), K.pt(o, f, -0.06, 0.42, 6), 2.0)])
	layered(items)
	var wp := K.pt(o, f, -0.7, 0.62, 14)
	cv.line_v(wp, wp + Vector2(0, -16), Color8(50, 52, 50))  # whip antenna on the shelter


# ---------------------------------------------------------------- a_fob
const HESCO := Color8(158, 144, 106)


## One HESCO bastion cube: sand-filled wire-mesh basket (mesh grid on the sides, sand fill on top).
static func hesco(cv, o: Vector2, f: int, u: float, v: float, s: int) -> void:
	var col := P.mul(HESCO, 0.95 + 0.08 * P.hn(s, 1, 1201))
	var r := bx(cv, o, f, u, v, 0, 0.13, 0.13, 11.0, col, 0.12, s)
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		var k := P.side_shade(sd.n)
		for tt in [0.33, 0.66]:
			cv.line_v(q[0].lerp(q[1], tt), q[3].lerp(q[2], tt), P.mul(col, k * 1.18))
		cv.line_v(q[0].lerp(q[3], 0.5), q[1].lerp(q[2], 0.5), P.mul(col, k * 1.18))
		cv.line_v(q[0], q[3], P.mul(col, k * 0.7))
		cv.line_v(q[3], q[2], Color8(170, 172, 166))  # wire rim
	cv.poly(P.sub(r.top, 0.08, 0.08, 0.92, 0.92), P.mul(SAND, 0.82), P.speckle(0.14, s + 3))


static func crate_stack(cv, o: Vector2, f: int, u: float, v: float, s: int) -> void:
	var cols := [Color8(96, 100, 66), Color8(122, 104, 70), Color8(96, 100, 66)]
	var spots := [[0.0, 0.0, 0.0], [0.17, 0.0, 0.0], [0.08, 0.0, 6.0]]
	for i in 3:
		var sp: Array = spots[i]
		var c := bx(cv, o, f, u + sp[0], v + sp[1], sp[2], 0.08, 0.1, 6.0, cols[i], 0.08, s + i)
		B.edges(cv, c, cols[i])
		for sd in c.sides:
			cv.line_v(sd.quad[0].lerp(sd.quad[3], 0.5), sd.quad[1].lerp(sd.quad[2], 0.5), P.mul(cols[i], 0.6))


static func fob(cv, o: Vector2, f: int) -> void:
	var e := 1.3
	K.gquad(cv, o, f, -1.45, -1.45, 1.45, 1.45, 0, Color8(122, 110, 86))  # gravel pad
	for k in 60:
		var gp := K.pt(o, f, (P.hn(k, 1, 1210) - 0.5) * 2.8, (P.hn(k, 2, 1210) - 0.5) * 2.8, 0)
		cv.px(int(gp.x), int(gp.y), Color8(140, 128, 102) if k % 2 == 0 else Color8(100, 90, 70))
	var cubes: Array = []
	var n := 11
	for i in n:
		var t := -e + i * (2.0 * e / (n - 1))
		cubes.append(Vector2(t, -e))
		cubes.append(Vector2(t, e))
		if i > 0 and i < n - 1:
			cubes.append(Vector2(-e, t))
			if absf(t) > 0.3:  # gate gap on the +u side
				cubes.append(Vector2(e, t))
	for c in cubes:
		bshadow(cv, o, f, c.x, c.y, 0, 0.13, 0.13, 11)
	bshadow(cv, o, f, -0.5, -0.5, 0, 0.45, 0.32, 16)
	bshadow(cv, o, f, 0.4, -0.6, 2, 0.42, 0.18, 12)
	cv.flush_shadow()
	var items: Array = []
	var ci := 0
	for c in cubes:
		ci += 1
		var cc: Vector2 = c
		var sd := 1220 + ci
		items.append([dep(f, cc.x, cc.y), func() -> void: hesco(cv, o, f, cc.x, cc.y, sd)])
	items.append([dep(f, -0.5, -0.5), func() -> void:
		K.tent(cv, o, f, -0.5, -0.5, 0, 0.45, 0.32, 17.0, K.pal("a", "canvas"))
		var dp := K.pt(o, f, -0.05, -0.5, 4)
		cv.rect(int(dp.x) - 1, int(dp.y) - 4, 3, 5, Color8(46, 48, 36))])  # tent door flap
	items.append([dep(f, 0.4, -0.6), func() -> void:  # container HQ with sandbagged roof edge and mast
		shelter(cv, o, f, 0.4, -0.6, 0.42, 0.18, 12.0, 1240)
		var mp := K.pt(o, f, 0.7, -0.7, 14)
		cv.line_v(mp, mp + Vector2(0, -20), Color8(52, 54, 52))
		cv.line_v(mp + Vector2(-3, -16), mp + Vector2(3, -16), Color8(52, 54, 52))
		B.lamp(cv, mp + Vector2(0, -21))])
	items.append([dep(f, -0.15, 0.2), func() -> void:  # flag pole
		var b0 := K.pt(o, f, -0.15, 0.2, 0)
		cv.line_v(b0, b0 + Vector2(0, -34), Color8(170, 170, 164))
		cv.team = true
		for yy in 6:
			for xx in 10:
				var wave := int(1.2 * sin(xx * 0.8))
				cv.px(int(b0.x) + 1 + xx, int(b0.y) - 34 + yy + wave, Color(0.9, 0.9, 0.9) if yy < 3 else Color(0.72, 0.72, 0.72))
		cv.team = false
		cv.px(int(b0.x), int(b0.y) - 35, Color8(220, 200, 120))])
	items.append([dep(f, 0.55, 0.65), func() -> void: crate_stack(cv, o, f, 0.5, 0.65, 1250)])
	items.append([dep(f, 0.15, 0.85), func() -> void:  # fuel drums for the supply trucks
		for k in 3:
			var c := K.wp(f, 0.0 + k * 0.13, 0.9)
			B.cyl(cv, o, Vector3(c.x, c.y, 0), 0.06, 7.0, BLD.DRUM_G, 1260 + k, 0.6)])
	items.append([dep(f, -0.85, 0.75), func() -> void:  # sandbag bunker in the corner
		for row in 2:
			for k in 3:
				bag(cv, o, f, -0.95 + k * 0.2, 0.62, row * 4.0, 0.09, 0.07, 4.0, P.mul(SAND, 0.92 + 0.12 * P.hn(k, row, 1270)), 1271 + k + row * 3)
		var roof := bx(cv, o, f, -0.75, 0.85, 8, 0.28, 0.25, 2.0, Color8(104, 98, 80), 0.12, 1280)
		B.edges(cv, roof, Color8(104, 98, 80))])
	items.append([dep(f, e + 0.1, 0.0) + 0.2, func() -> void:  # gate boom (red / white) across the entrance
		var a := K.pt(o, f, e, -0.3, 7)
		var b := K.pt(o, f, e, 0.3, 7)
		for k in 6:
			cv.line_v(a.lerp(b, k / 6.0), a.lerp(b, (k + 1) / 6.0), K.RED if k % 2 == 0 else K.WHITE)
		var p0 := K.pt(o, f, e, -0.34, 0)
		cv.rect(int(p0.x) - 1, int(p0.y) - 8, 3, 8, Color8(70, 72, 68))])
	layered(items)


# ---------------------------------------------------------------- a_repair_bay
static func repair_bay(cv, o: Vector2, f: int) -> void:
	var ps: Array = [[0, 0, 0, 1.42, 1.42, 2, K.pal("a", "slab"), "slab"]]
	K.render(cv, o, f, ps, 1.0, false, Callable())
	for k in 6:  # oil stains on the work pad
		var c := K.pt(o, f, 0.3 + (P.hn(k, 1, 1301) - 0.5) * 1.2, (P.hn(k, 2, 1301) - 0.5) * 1.6, 2)
		cv.ellipse(c.x, c.y, 4.0 + P.hn(k, 3, 1301) * 4.0, 2.0, Color(0.08, 0.08, 0.07, 0.25))
	var a := K.pt(o, f, 1.3, -0.9, 2)
	var b := K.pt(o, f, 1.3, 0.9, 2)
	cv.line_v(a, b, Color8(206, 190, 96))  # bay marking
	bshadow(cv, o, f, -0.78, 0, 2, 0.55, 1.1, 28)
	bshadow(cv, o, f, 0.5, 0, 2, 0.2, 0.9, 36)
	cv.flush_shadow()
	var gu := 0.5
	var gh := 36.0
	var items: Array = []
	items.append([dep(f, -0.78, 0) - 0.3, func() -> void:  # workshop hall with two open roll-up doors facing the pad
		var r := bx(cv, o, f, -0.78, 0, 2, 0.55, 1.1, 28.0, CONCRETE, 0.08, 1310)
		B.wall_ao(cv, r, 0.28)
		B.edges(cv, r, CONCRETE)
		for sd in r.sides:
			var q: PackedVector2Array = sd.quad
			if K.wp(f, 1, 0).dot(sd.n) > 0.5:
				B.rollup(cv, q, 0.08, 0.44, 0.72, 0.85, 1311)
				B.rollup(cv, q, 0.56, 0.92, 0.72, 0.3, 1312)
				cv.team = true
				cv.poly(P.sub(q, 0.0, 0.8, 1.0, 0.9), Color(0.8, 0.8, 0.8))
				cv.team = false
			else:
				B.window_row(cv, q, 0.55, 0.78, 3, CONCRETE, 1313)
				B.door(cv, q, 0.42, 0.58, 0.6, CONCRETE)
		var roof := bx(cv, o, f, -0.78, 0, 30, 0.57, 1.12, 2.0, K.pal("a", "roof"), 0.06, 1314)
		B.edges(cv, roof, K.pal("a", "roof"))
		for k in 5:  # corrugation
			var t := 0.1 + k * 0.2
			cv.line_v(roof.top[0].lerp(roof.top[3], t), roof.top[1].lerp(roof.top[2], t), P.mul(K.pal("a", "roof"), 0.85))
		B.vent(cv, o, Vector3(K.wp(f, -0.9, -0.6).x, K.wp(f, -0.9, -0.6).y, 32), 1315)
		B.hvac(cv, o, Vector3(K.wp(f, -0.8, 0.5).x, K.wp(f, -0.8, 0.5).y, 32), 0.12, 0.1, 1316)])
	var legs := [-0.9, 0.9]
	legs.sort_custom(func(p1, p2): return dep(f, gu, p1) < dep(f, gu, p2))
	for li in 2:
		var lv: float = legs[li]
		var front := li == 1
		items.append([dep(f, gu, lv) + (0.4 if front else -0.6), func() -> void:  # A-frame gantry leg on rail bogies
			var bog := bx(cv, o, f, gu, lv, 2, 0.26, 0.05, 3.0, P.mul(YELLOW, 0.6), 0.05, 1320)
			for s in [-1.0, 1.0]:
				var p0 := K.pt(o, f, gu + 0.22 * s, lv, 5)
				var p1 := K.pt(o, f, gu, lv, gh)
				cv.line_v(p0, p1, YELLOW)
				cv.line_v(p0 + Vector2(1, 0), p1 + Vector2(1, 0), P.mul(YELLOW, 0.7))
			cv.line_v(K.pt(o, f, gu - 0.11, lv, 20), K.pt(o, f, gu + 0.11, lv, 20), P.mul(YELLOW, 0.85))
			if front:  # beam, hazard stripes, trolley, hoist cable + hanging power pack
				var beam := bx(cv, o, f, gu, 0, gh, 0.06, 0.95, 4.0, YELLOW, 0.05, 1321)
				B.edges(cv, beam, YELLOW)
				for sd in beam.sides:
					for k in 8:
						var t := k / 8.0
						cv.poly(P.sub(sd.quad, t, 0.0, t + 0.05, 1.0), Color8(40, 38, 32))
				var tro := bx(cv, o, f, gu, 0.1, gh - 4, 0.08, 0.08, 4.0, P.mul(YELLOW, 0.8), 0.05, 1322)
				var hk := K.pt(o, f, gu, 0.1, gh - 4)
				var pk := K.pt(o, f, gu, 0.1, 22)
				cv.line_v(hk, pk, Color8(40, 40, 38))
				var pack := bx(cv, o, f, gu, 0.1, 15, 0.13, 0.1, 7.0, Color8(70, 74, 64), 0.08, 1323)
				B.edges(cv, pack, Color8(70, 74, 64))
				for sd in pack.sides:
					cv.poly(P.sub(sd.quad, 0.15, 0.3, 0.85, 0.7), Color8(44, 46, 42))
				B.lamp(cv, K.pt(o, f, gu, -0.7, gh - 1))])
	items.append([dep(f, gu, 0.0), func() -> void:  # MBT under the gantry, engine deck open
		var tc = P.Canvas.new(cv.w, cv.h)
		VH.draw(tc, "mbt", K.rot(f) + PI * 0.5, 0, false, K.pt(o, f, gu, 0.0, 2))
		paste_cv(cv, tc)
		var deck := K.pt(o, f, gu, -0.4, 13)
		cv.rect(int(deck.x) - 3, int(deck.y) - 1, 6, 3, Color8(30, 32, 30))])
	items.append([dep(f, 1.05, 0.95), func() -> void:  # tyre stack + drums + tool cabinet
		for k in 3:
			var c := K.wp(f, 1.05, 0.95)
			B.cyl(cv, o, Vector3(c.x, c.y, 2 + k * 3.0), 0.12, 3.0, Color8(36, 36, 34), 1330 + k)
		for k in 2:
			var c2 := K.wp(f, 0.75 + k * 0.14, 1.15)
			B.cyl(cv, o, Vector3(c2.x, c2.y, 2), 0.06, 7.0, BLD.DRUM_R, 1335 + k, 0.6)])
	items.append([dep(f, 1.0, -1.05), func() -> void:
		var cab := bx(cv, o, f, 1.0, -1.05, 2, 0.2, 0.08, 10.0, Color8(160, 48, 40), 0.05, 1340)
		B.edges(cv, cab, Color8(160, 48, 40))
		for sd in cab.sides:
			for t in [0.33, 0.66]:
				cv.line_v(sd.quad[0].lerp(sd.quad[3], t), sd.quad[1].lerp(sd.quad[2], t), Color8(100, 30, 26))])
	layered(items)


# ---------------------------------------------------------------- a_cruise_battery
## Screen-space tube between two 3D local points (radius px), shaded light on the upper-left edge.
static func tube(cv, o: Vector2, f: int, a: Vector3, b: Vector3, r: float, col: Color) -> Array:
	var pa := K.pt(o, f, a.x, a.y, a.z)
	var pb := K.pt(o, f, b.x, b.y, b.z)
	var d := (pb - pa).normalized()
	var n := Vector2(-d.y, d.x)
	if n.dot(Vector2(-0.7, -0.7)) < 0.0:
		n = -n  # n points to the lit (upper-left) side
	for i in 5:
		var t0 := -1.0 + i * 0.4
		var t1 := t0 + 0.4
		var k: float = [1.22, 1.08, 0.95, 0.82, 0.68][i]
		cv.poly(PackedVector2Array([pa + n * r * t1, pb + n * r * t1, pb + n * r * t0, pa + n * r * t0]), P.mul(col, k))
	return [pa, pb, n]


static func truck_wheels(cv, o: Vector2, f: int, us: Array, v: float, hv: float, pass_near: bool) -> void:
	for s in [-1.0, 1.0]:
		if (dep(f, 0, s) > 0.0) != pass_near:
			continue
		for u in us:
			var c := K.pt(o, f, u, v + s * hv, 3.0)
			cv.ellipse(c.x, c.y, 3.2, 3.0, VH.WHEEL)
			cv.ellipse(c.x - 0.5, c.y - 0.5, 1.4, 1.3, Color8(72, 74, 68))


static func cruise_battery(cv, o: Vector2, f: int) -> void:
	var ps: Array = [[0, 0, 0, 0.95, 0.95, 2, K.pal("a", "slab"), "slab"]]
	K.render(cv, o, f, ps, 1.0, false, Callable())
	for k in 9:  # blast scorch on the pad behind the launcher
		var c := K.pt(o, f, -0.75 + P.hn(k, 1, 1101) * 0.35, 0.15 + (P.hn(k, 2, 1101) - 0.5) * 0.6, 2)
		cv.ellipse(c.x, c.y, 6.0 + P.hn(k, 3, 1101) * 5.0, 3.0, Color(0.08, 0.07, 0.06, 0.22))
	for t in [-0.3, 0.3]:  # painted pad lines
		var a := K.pt(o, f, -0.9, 0.2 + t, 2)
		var b := K.pt(o, f, 0.9, 0.2 + t, 2)
		cv.line_v(a, b, Color8(206, 190, 96))
	var tv := 0.2
	bshadow(cv, o, f, 0.0, tv, 0, 0.78, 0.22, 12)
	bshadow(cv, o, f, -0.35, tv, 8, 0.3, 0.08, 34)
	bshadow(cv, o, f, 0.25, -0.62, 2, 0.32, 0.2, 12)
	cv.flush_shadow()
	var hull := VH.HULL
	var items: Array = []
	items.append([dep(f, 0.25, -0.62), func() -> void:  # launch control container + antenna
		shelter(cv, o, f, 0.25, -0.62, 0.32, 0.18, 11.0, 1110)
		var mp := K.pt(o, f, 0.5, -0.72, 13)
		cv.line_v(mp, mp + Vector2(0, -14), Color8(56, 58, 56))
		cv.rect(int(mp.x) - 2, int(mp.y) - 15, 5, 2, Color8(90, 94, 92))])
	items.append([dep(f, 0.0, tv), func() -> void:  # TEL: 8x8 truck, cab, raised erector with one cruise missile
		var axles := [-0.6, -0.35, 0.25, 0.5]
		truck_wheels(cv, o, f, axles, tv, 0.17, false)
		var ch := bx(cv, o, f, 0.0, tv, 2, 0.75, 0.16, 5.0, P.mul(hull, 0.8), 0.06, 1111)
		truck_wheels(cv, o, f, axles, tv, 0.17, true)
		var bed := bx(cv, o, f, -0.2, tv, 7, 0.52, 0.19, 3.0, hull, 0.07, 1112)
		B.edges(cv, bed, hull)
		var cab := bx(cv, o, f, 0.58, tv, 7, 0.16, 0.19, 9.0, hull, 0.07, 1113)
		B.edges(cv, cab, hull)
		for sd in cab.sides:
			cv.poly(P.sub(sd.quad, 0.12, 0.45, 0.88, 0.85), B.GLASS)
			cv.line_v(P.sub(sd.quad, 0.12, 0.85, 0.88, 0.85)[0], P.sub(sd.quad, 0.12, 0.85, 0.88, 0.85)[1], B.GLASS_HI)
		cv.team = true
		cv.poly(P.sub(cab.top, 0.15, 0.2, 0.85, 0.8), Color(0.78, 0.78, 0.78))
		for sd in bed.sides:
			cv.poly(P.sub(sd.quad, 0.05, 0.2, 0.3, 0.85), Color(0.75, 0.75, 0.75))
		cv.team = false
		# erector arm hinged at the rear, missile on top, hydraulic ram from the bed
		var hinge := Vector3(-0.7, tv, 11.0)
		var top := Vector3(-0.28, tv, 50.0)
		var ram0 := K.pt(o, f, -0.2, tv, 10.0)
		var ram1 := K.pt(o, f, -0.5, tv, 30.0)
		cv.line_v(ram0, ram1, Color8(150, 154, 150))
		cv.line_v(ram0 + Vector2(1, 0), ram1 + Vector2(1, 0), Color8(80, 84, 80))
		tube(cv, o, f, hinge, top, 2.2, P.mul(hull, 0.85))
		var mb := Vector3(-0.66, tv, 14.0)
		var mt := Vector3(-0.27, tv, 53.0)
		var tb: Array = tube(cv, o, f, mb, mt, 2.6, Color8(196, 198, 190))
		var pa: Vector2 = tb[0]
		var pb: Vector2 = tb[1]
		var n: Vector2 = tb[2]
		var dd := (pb - pa).normalized()
		cv.poly(PackedVector2Array([pb + n * 2.6, pb - n * 2.6, pb + dd * 4.0]), Color8(44, 46, 46))  # nose
		cv.team = true
		var bm := pa.lerp(pb, 0.72)
		cv.poly(PackedVector2Array([bm + n * 2.6, bm - n * 2.6, bm - n * 2.6 + dd * 2.0, bm + n * 2.6 + dd * 2.0]), Color(0.8, 0.8, 0.8))
		cv.team = false
		var wm := pa.lerp(pb, 0.45)
		cv.line_v(wm - n * 6.0, wm + n * 6.0, Color8(160, 162, 156))  # folded wings
		for s in [-1.0, 1.0]:  # tail fins
			cv.line_v(pa + n * 2.0 * s, pa + n * 5.0 * s - dd * 2.0, Color8(150, 152, 146))
		cv.rect(int(pa.x) - 1, int(pa.y), 3, 2, Color8(60, 58, 54))  # booster nozzle
		for k in 2:
			B.lamp(cv, K.pt(o, f, 0.72, tv - 0.12 + k * 0.24, 16))])
	layered(items)
