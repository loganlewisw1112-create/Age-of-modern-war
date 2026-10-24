extends RefCounted
## Human B fort pieces (agent ART-F): brick walls patched with corrugated scrap, a barbed-wire coping
## and painted team plates; a rolling iron shutter gate in hazard-striped I-beam posts (shutter rolls up
## into the head drum when open); a brick flak tower with a twin-barrel mount behind scrap plates.
## Palette from faction_b_bld.gd / faction_b_bdress.gd. Same API as g4_fort_a.gd.
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const FL = preload("res://tools/art/g4_fort_lib.gd")
const FB = preload("res://tools/art/faction_b_bld.gd")
const RB = preload("res://tools/art/faction_b_bdress.gd")

const T := 0.11
const H := 20.0
const SLAB := FB.SLAB
const HOLO := false
const GATE_OUT := 0.45
const BRICK := FB.BRICK
const BRICK_D := FB.BRICK_D
const IRON := FB.IRON
const RUSTY := FB.RUSTY
const STEEL := FB.STEEL
const CONCRETE := FB.CONCRETE
const MORTAR := RB.MORTAR
const WIRE := Color8(70, 70, 66)
const HAZARD := Color8(196, 160, 52)
const RAW := Color8(150, 132, 116)


static func core_half(kind: String) -> float:
	return {"wall": 0.16, "gate": 0.45, "tower": 0.3}[kind]


static func core_h(kind: String) -> float:
	return {"wall": H + 5.0, "gate": H + 12.0, "tower": 44.0}[kind]


static func _fpt(o: Vector2, i: int, s: float, z: float) -> Vector2:
	var f := FL.on_face(i, s, T)
	return P.proj(o, Vector3(f.x, f.y, z))


static func arm(cv, o: Vector2, i: int, s0: float, _v: Dictionary) -> void:
	var r: Dictionary = FL.arm_box(cv, o, i, s0, 0.5, T, 0.0, H, BRICK, 0.1, 51 + i)
	B.wall_ao(cv, r, 0.28)
	var mc := P.mix(BRICK, MORTAR, 0.4)
	for c in 6:  # mortar courses + staggered head joints, placed in absolute s so runs line up
		var z := 3.0 + c * 3.0
		cv.line_v(_fpt(o, i, s0, z), _fpt(o, i, 0.5, z), mc)
		var k := 0
		while true:
			var s := 0.5 - (k * 2 + (c % 2)) * 0.0625
			if s <= s0 + 0.02:
				break
			var q := _fpt(o, i, s, z - 1.5)
			cv.px(int(q.x), int(q.y), mc)
			k += 1
	if s0 < 0.2:  # corrugated scrap patch, varies per direction
		var a0 := 0.18 + P.hn(i, 3, 61) * 0.06
		var q := FL.face_quad(o, i, a0, a0 + 0.17, T + 0.005, 5.0 + P.hn(i, 4, 61) * 3.0, 15.0)
		cv.poly(q, RUSTY, P.speckle(0.18, 62 + i))
		for u in [0.2, 0.4, 0.6, 0.8]:
			cv.line_v(q[0].lerp(q[1], u), q[3].lerp(q[2], u), P.mul(RUSTY, 0.72))
	if s0 < 0.28:  # painted team plate
		FL.face_band(cv, o, i, 0.34, 0.44, T + 0.005, 9.0, 14.0, Color(0.78, 0.78, 0.78), true)
	FL.face_band(cv, o, i, s0, 0.5, T, H - 1.0, H, P.mul(CONCRETE, 0.95))
	var prev := Vector2.ZERO
	var sw := s0
	while sw <= 0.5001:  # barbed wire coping: sine in absolute s, continuous across the cell edge
		var cw := FL.on_face(i, sw, 0.0)
		var qw := P.proj(o, Vector3(cw.x, cw.y, H + 2.0 + sin(sw * 40.0) * 1.2))
		if sw > s0:
			cv.line_v(prev, qw, WIRE)
		prev = qw
		sw += 0.025
	for k in 4:
		var st := s0 + (0.5 - s0) * (k + 0.5) / 4.0
		var c := FL.on_face(i, st, 0.0)
		var q := P.proj(o, Vector3(c.x, c.y, H))
		cv.line(int(q.x), int(q.y), int(q.x), int(q.y) - 3, P.mul(STEEL, 0.7))


static func core(cv, o: Vector2, kind: String, mask: int, v: Dictionary) -> void:
	var hk: float = v.hk
	var raw: bool = v.raw
	match kind:
		"wall":
			var r: Dictionary = P.box(cv, o, Vector3(0, 0, 0), 0.16, 0.16, (H + 3.0) * hk, 0.0, RAW if raw else BRICK_D, 0.1, 71)
			B.wall_ao(cv, r, 0.3)
			if not raw:
				for sd in r.sides:
					var q: PackedVector2Array = sd.quad
					for vv in [0.25, 0.5, 0.75]:
						cv.line_v(q[0].lerp(q[3], vv), q[1].lerp(q[2], vv), P.mix(BRICK_D, MORTAR, 0.4))
					cv.team = true
					cv.poly(P.sub(q, 0.2, 0.3, 0.8, 0.45), Color(0.8, 0.8, 0.8))
					cv.team = false
				P.box(cv, o, Vector3(0, 0, H + 3.0), 0.18, 0.18, 2.0, 0.0, CONCRETE, 0.06, 72)
		"gate":
			_gate(cv, o, FL.gate_axis(mask), hk, raw, bool(v.open))
		"tower":
			_tower(cv, o, hk, raw)


static func _post(cv, o: Vector2, c: Vector2, ph: float, raw: bool) -> void:
	var r: Dictionary = P.box(cv, o, Vector3(c.x, c.y, 0), 0.07, 0.07, ph, 0.0, RAW if raw else IRON, 0.05, 81)
	if raw:
		return
	for sd in r.sides:  # hazard stripes at the foot
		var q: PackedVector2Array = sd.quad
		for k in 3:
			cv.poly(P.sub(q, 0.0, 0.62 + k * 0.12, 1.0, 0.68 + k * 0.12), HAZARD if k % 2 == 0 else Color8(40, 38, 34))


static func _gate(cv, o: Vector2, ax: int, hk: float, raw: bool, open: bool) -> void:
	var a := Vector2(1, 0) if ax == 0 else Vector2(0, 1)
	var ph := (H + 12.0) * hk
	_post(cv, o, -a * 0.38, ph, raw)
	if hk >= 0.4:
		var hx := 0.31 if ax == 0 else 0.03
		var hy := 0.03 if ax == 0 else 0.31
		var top := H + 6.0 if not raw else (H + 6.0) * hk
		var z0 := 1.0 if not open else H + 3.0
		var sh: Dictionary = P.box(cv, o, Vector3(0, 0, z0), hx, hy, top - z0, 0.0, RAW if raw else RUSTY, 0.16, 82)
		if not raw:
			for sd in sh.sides:
				var q: PackedVector2Array = sd.quad
				var n := 9 if not open else 1
				for k in n:
					var vv := (k + 1.0) / (n + 1.0)
					cv.line_v(q[0].lerp(q[3], vv), q[1].lerp(q[2], vv), P.mul(RUSTY, 0.7))
				if not open:
					cv.team = true
					cv.poly(P.sub(q, 0.3, 0.3, 0.7, 0.5), Color(0.78, 0.78, 0.78))
					cv.team = false
					cv.line_v(q[0].lerp(q[1], 0.0), q[0].lerp(q[1], 1.0), P.mul(IRON, 0.6))
	_post(cv, o, a * 0.38, ph, raw)
	if not raw:
		var lx := 0.45 if ax == 0 else 0.09
		var ly := 0.09 if ax == 0 else 0.45
		var drum: Dictionary = P.box(cv, o, Vector3(0, 0, H + 6.0), lx, ly, 6.0, 0.0, P.mul(IRON, 0.9), 0.08, 83)
		B.edges(cv, drum, IRON)
		for sd in drum.sides:
			cv.team = true
			cv.poly(P.sub(sd.quad, 0.05, 0.3, 0.2, 0.7), Color(0.75, 0.75, 0.75))
			cv.team = false


static func _tower(cv, o: Vector2, hk: float, raw: bool) -> void:
	var bh := 30.0 * hk if not raw else 44.0 * hk
	var top := B.cyl(cv, o, Vector3(0, 0, 0), 0.3, bh, RAW if raw else BRICK, 91, -1.0 if raw else 0.82, 0 if raw else 3)
	if raw:
		return
	P.box(cv, o, Vector3(0, 0, 30), 0.34, 0.34, 3.0, 0.0, STEEL, 0.06, 92)
	var plates := [[-0.3, 0.0, 0.03, 0.26], [0.0, -0.3, 0.26, 0.03]]
	for pl in plates:  # back scrap plates, then the gun, then the front plates
		P.box(cv, o, Vector3(pl[0], pl[1], 33), pl[2], pl[3], 6.0, 0.0, RUSTY, 0.18, 93)
	P.box(cv, o, Vector3(0, 0, 33), 0.11, 0.11, 5.0, 0.0, IRON, 0.06, 94)
	var m := P.proj(o, Vector3(0.02, 0.0, 38))
	for d in [-2, 2]:
		var b0 := m + Vector2(d, 0)
		var b1 := m + Vector2(d + 9, -14)
		cv.line_v(b0, b1, Color8(40, 40, 38))
		cv.line_v(b0 + Vector2(1, 0), b1 + Vector2(1, 0), Color8(70, 70, 66))
		cv.rect(int(b1.x) - 1, int(b1.y) - 1, 3, 2, Color8(30, 30, 28))
	for pl in [[0.3, 0.0, 0.03, 0.26], [0.0, 0.3, 0.26, 0.03]]:
		var r: Dictionary = P.box(cv, o, Vector3(pl[0], pl[1], 33), pl[2], pl[3], 5.0, 0.0, P.mul(RUSTY, 1.05), 0.18, 95)
		for sd in r.sides:
			cv.line_v(sd.quad[0].lerp(sd.quad[3], 0.5), sd.quad[1].lerp(sd.quad[2], 0.5), P.mul(RUSTY, 0.7))
	B.lamp(cv, top + Vector2(-10, -1))
