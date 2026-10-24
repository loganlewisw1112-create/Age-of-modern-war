extends RefCounted
## Human A fort pieces (agent ART-F): precast concrete T-wall barriers on a jersey foot with a painted
## team band, a steel double-leaf gate between steel posts under a lintel, and a concrete MG tower
## with an olive firing cabin. Palette from buildings.gd. API used by g4_fort_lib: T, H, SLAB, HOLO,
## GATE_OUT, core_half(kind), core_h(kind), arm(cv, o, dir, s0, v), core(cv, o, kind, mask, v).
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const FL = preload("res://tools/art/g4_fort_lib.gd")
const BLD = preload("res://tools/art/buildings.gd")

const T := 0.12        # arm half-thickness (tiles)
const H := 22.0        # arm height (px)
const SLAB := BLD.SLAB
const HOLO := false
const GATE_OUT := 0.45  # gate posts' outer face; run-axis arms start here
const JERSEY := BLD.JERSEY
const CONCRETE := BLD.CONCRETE
const STEEL := BLD.STEEL
const STEEL_L := Color8(122, 128, 128)
const OLIVE := BLD.OLIVE
const GLASS := BLD.GLASS
const SAND := BLD.SAND
const RAW := Color8(150, 146, 136)


static func core_half(kind: String) -> float:
	return {"wall": 0.17, "gate": 0.45, "tower": 0.3}[kind]


static func core_h(kind: String) -> float:
	return {"wall": H + 5.0, "gate": H + 10.0, "tower": 43.0}[kind]


static func arm(cv, o: Vector2, i: int, s0: float, _v: Dictionary) -> void:
	var foot: Dictionary = FL.arm_box(cv, o, i, s0, 0.5, T + 0.04, 0.0, 4.0, P.mul(CONCRETE, 0.92), 0.1, 11)
	B.wall_ao(cv, foot, 0.2)
	FL.arm_box(cv, o, i, s0, 0.5, T, 4.0, H - 4.0, JERSEY, 0.07, 12 + i)
	FL.face_band(cv, o, i, s0, 0.5, T, 14.0, 16.5, Color(0.82, 0.82, 0.82), true)
	FL.face_band(cv, o, i, s0, 0.5, T, 4.0, 5.0, P.mul(JERSEY, 0.72))
	for s in [0.25, 0.5]:
		if s > s0 + 0.02:
			FL.joint(cv, o, i, s - 0.01, T, 4.0, H - 4.0, P.mul(JERSEY, 0.66))
	# lifting-eye nubs on the top edge
	var nub := FL.on_face(i, (s0 + 0.5) * 0.5, 0.0)
	var pn := P.proj(o, Vector3(nub.x, nub.y, H))
	cv.px(int(pn.x), int(pn.y) - 1, P.mul(STEEL, 0.8))


static func _band(cv, r: Dictionary, v0: float, v1: float, lum := 0.8) -> void:
	cv.team = true
	for sd in r.sides:
		cv.poly(P.sub(sd.quad, 0.0, v0, 1.0, v1), Color(lum, lum, lum))
	cv.team = false


static func core(cv, o: Vector2, kind: String, mask: int, v: Dictionary) -> void:
	var hk: float = v.hk
	var raw: bool = v.raw
	match kind:
		"wall":
			var col := RAW if raw else CONCRETE
			var r: Dictionary = P.box(cv, o, Vector3(0, 0, 0), 0.17, 0.17, (H + 3.0) * hk, 0.0, col, 0.08, 21)
			B.wall_ao(cv, r, 0.3)
			if not raw:
				var cap: Dictionary = P.box(cv, o, Vector3(0, 0, H + 3.0), 0.19, 0.19, 2.0, 0.0, P.mul(CONCRETE, 1.08), 0.05, 22)
				B.edges(cv, cap, CONCRETE)
				_band(cv, r, 0.36, 0.48)
		"gate":
			_gate(cv, o, FL.gate_axis(mask), hk, raw, bool(v.open))
		"tower":
			_tower(cv, o, hk, raw)


static func _gate(cv, o: Vector2, ax: int, hk: float, raw: bool, open: bool) -> void:
	var a := Vector2(1, 0) if ax == 0 else Vector2(0, 1)   # run axis
	var p := Vector2(0, 1) if ax == 0 else Vector2(1, 0)   # across (toward the viewer)
	var ph := (H + 10.0) * hk
	var pcol := P.mix(STEEL, RAW, 0.4) if raw else P.mul(STEEL, 0.85)
	if open and not raw:
		for sgn in [-1.0, 1.0]:  # leaves swung back against the posts
			var c: Vector2 = a * 0.31 * sgn - p * 0.17
			var hx := 0.03 if ax == 0 else 0.15
			var hy := 0.15 if ax == 0 else 0.03
			var lf: Dictionary = P.box(cv, o, Vector3(c.x, c.y, 1), hx, hy, H - 3.0, 0.0, STEEL_L, 0.06, 31)
			for sd in lf.sides:
				for vv in [0.3, 0.6]:
					cv.line_v(sd.quad[0].lerp(sd.quad[3], vv), sd.quad[1].lerp(sd.quad[2], vv), P.mul(STEEL_L, 0.7))
				cv.team = true  # team stripe stays visible on the folded leaves
				cv.poly(P.sub(sd.quad, 0.1, 0.4, 0.9, 0.52), Color(0.8, 0.8, 0.8))
				cv.team = false
	var back: Vector2 = -a * 0.38
	var front: Vector2 = a * 0.38
	P.box(cv, o, Vector3(back.x, back.y, 0), 0.07, 0.07, ph, 0.0, pcol, 0.05, 32)
	if not open and hk >= 0.4:
		var lh := (H - 3.0) * hk
		var hx := 0.31 if ax == 0 else 0.04
		var hy := 0.04 if ax == 0 else 0.31
		var lf: Dictionary = P.box(cv, o, Vector3(0, 0, 1), hx, hy, lh, 0.0, P.mix(STEEL_L, RAW, 0.5) if raw else STEEL_L, 0.06, 33)
		if not raw:
			for sd in lf.sides:
				var q: PackedVector2Array = sd.quad
				for vv in [0.25, 0.5, 0.75]:
					cv.line_v(q[0].lerp(q[3], vv), q[1].lerp(q[2], vv), P.mul(STEEL_L, 0.68))
				cv.line_v(q[0].lerp(q[1], 0.5), q[3].lerp(q[2], 0.5), P.mul(STEEL_L, 0.55))
				cv.team = true
				cv.poly(P.sub(q, 0.08, 0.38, 0.92, 0.5), Color(0.8, 0.8, 0.8))
				cv.team = false
	P.box(cv, o, Vector3(front.x, front.y, 0), 0.07, 0.07, ph, 0.0, pcol, 0.05, 34)
	if not raw:
		var lx := 0.45 if ax == 0 else 0.05
		var ly := 0.05 if ax == 0 else 0.45
		var lin: Dictionary = P.box(cv, o, Vector3(0, 0, H + 6.0), lx, ly, 3.0, 0.0, P.mul(STEEL, 0.95), 0.05, 35)
		B.edges(cv, lin, STEEL)
		for sgn in [-1.0, 1.0]:  # gate lamps on the post tops
			var lp: Vector2 = a * 0.38 * sgn
			B.lamp(cv, P.proj(o, Vector3(lp.x, lp.y, ph + 1.0)))


static func _tower(cv, o: Vector2, hk: float, raw: bool) -> void:
	var col := RAW if raw else CONCRETE
	var bh := 30.0 * hk if not raw else 43.0 * hk
	var base: Dictionary = P.box(cv, o, Vector3(0, 0, 0), 0.3, 0.3, bh, 0.0, col, 0.08, 41)
	B.wall_ao(cv, base, 0.3)
	if raw:
		return
	_band(cv, base, 0.1, 0.2)
	for sd in base.sides:  # pour lines
		var q: PackedVector2Array = sd.quad
		cv.line_v(q[0].lerp(q[3], 0.55), q[1].lerp(q[2], 0.55), P.mul(CONCRETE, 0.82))
	var cab: Dictionary = P.box(cv, o, Vector3(0, 0, 30), 0.33, 0.33, 11.0, 0.0, OLIVE, 0.08, 42)
	for sd in cab.sides:
		cv.poly(P.sub(sd.quad, 0.12, 0.38, 0.88, 0.62), GLASS)
	var roof: Dictionary = P.box(cv, o, Vector3(0, 0, 41), 0.38, 0.38, 2.0, 0.0, P.mul(STEEL, 1.05), 0.05, 43)
	B.edges(cv, roof, STEEL)
	for k in 4:  # sandbags along the roof's front edges
		var u := 0.18 + k * 0.2
		var sb := P.proj(o, Vector3(0.3, -0.3 + u * 0.75, 43))
		cv.rect(int(sb.x) - 1, int(sb.y) - 2, 3, 2, SAND)
		var sc := P.proj(o, Vector3(0.3 - u * 0.75, 0.3, 43))
		cv.rect(int(sc.x) - 1, int(sc.y) - 2, 3, 2, P.mul(SAND, 0.9))
	var m0 := P.proj(o, Vector3(0.33, 0.12, 35))
	var m1 := P.proj(o, Vector3(0.58, 0.22, 36))
	cv.line_v(m0, m1, Color8(36, 38, 38))
	cv.line_v(m0 + Vector2(0, 1), m1 + Vector2(0, 1), Color8(56, 58, 58))
	var mast := P.proj(o, Vector3(-0.25, -0.25, 43))
	cv.line(int(mast.x), int(mast.y), int(mast.x), int(mast.y) - 12, Color8(60, 60, 56))
	B.lamp(cv, Vector2(mast.x, mast.y - 12))
