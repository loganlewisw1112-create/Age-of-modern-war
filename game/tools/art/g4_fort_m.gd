extends RefCounted
## Machine fort pieces (agent ART-F): a translucent cyan energy barrier between graphite emitter pylons
## on a low rail (team strip on the rail), a field gate (dense field between two emitter posts over a
## threshold plate; open = field off, dim teal emitters) and a tapered hex sentry spire with a glowing
## crystal. Palette and hex prisms from faction_m_lib.gd. Field pixels stay below alpha 0.6 so the
## outline pass never darkens them. Same API as g4_fort_a.gd.
const P = preload("res://tools/art/pix.gd")
const FL = preload("res://tools/art/g4_fort_lib.gd")
const L = preload("res://tools/art/faction_m_lib.gd")

const T := 0.07
const H := 20.0
const SLAB := L.SLAB
const HOLO := true
const GATE_OUT := 0.46
const GRAPH := L.GRAPH
const GRAPH_D := L.GRAPH_D
const PANEL := L.PANEL
const CYAN := L.CYAN
const CYAN_HOT := L.CYAN_HOT
const TEAL := L.TEAL
const RAW := L.RAW


static func core_half(kind: String) -> float:
	return {"wall": 0.09, "gate": 0.46, "tower": 0.26}[kind]


static func core_h(kind: String) -> float:
	return {"wall": H + 8.0, "gate": H + 12.0, "tower": 60.0}[kind]


static func _fc(a: float) -> Color:
	return Color(CYAN.r, CYAN.g, CYAN.b, a)


## Vertical field plane along the axis line between distances s0..s1 of DIRS[i] (or any two points).
static func _field(cv, o: Vector2, a: Vector2, b: Vector2, z0: float, z1: float, dense: bool) -> void:
	var q := PackedVector2Array([P.proj(o, Vector3(a.x, a.y, z0)), P.proj(o, Vector3(b.x, b.y, z0)),
		P.proj(o, Vector3(b.x, b.y, z1)), P.proj(o, Vector3(a.x, a.y, z1))])
	cv.poly(q, _fc(0.4 if dense else 0.3))
	var lines := [0.2, 0.45, 0.7] if not dense else [0.15, 0.3, 0.45, 0.6, 0.75]
	for vv in lines:
		cv.line_v(q[0].lerp(q[3], vv), q[1].lerp(q[2], vv), _fc(0.22))
	cv.line_v(q[3], q[2], Color(CYAN_HOT.r, CYAN_HOT.g, CYAN_HOT.b, 0.35))
	cv.line_v(q[0] + Vector2(0, -1), q[1] + Vector2(0, -1), _fc(0.3))


static func arm(cv, o: Vector2, i: int, s0: float, _v: Dictionary) -> void:
	var a := FL.on_face(i, s0, 0.0)
	var b := FL.on_face(i, 0.5, 0.0)
	_field(cv, o, a, b, 3.0, H, false)
	FL.arm_box(cv, o, i, s0, 0.5, T, 0.0, 3.0, GRAPH, 0.06, 111 + i)
	FL.face_band(cv, o, i, s0, 0.5, T, 1.0, 2.2, Color(0.75, 0.75, 0.75), true)
	for s in [0.25, 0.5]:
		if s > s0 + 0.03:
			var f := FL.on_face(i, s - 0.01, T)
			var p := P.proj(o, Vector3(f.x, f.y, 2.5))
			cv.px(int(p.x), int(p.y), CYAN)


static func _pylon(cv, o: Vector2, c: Vector2, hr: float, ph: float, raw: bool, lit: bool) -> void:
	var r: Dictionary = P.box(cv, o, Vector3(c.x, c.y, 0), hr, hr, ph, 0.0, RAW if raw else GRAPH, 0.05, 121)
	if raw:
		return
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		cv.line_v(q[0].lerp(q[1], 0.5), q[3].lerp(q[2], 0.5) + Vector2(0, 2), CYAN if lit else TEAL)
		L.team_panel(cv, q, 0.15, 0.55, 0.85, 0.7)
	P.box(cv, o, Vector3(c.x, c.y, ph), hr * 0.7, hr * 0.7, 3.0, 0.0, PANEL, 0.04, 122)
	var tip := P.proj(o, Vector3(c.x, c.y, ph + 3.0))
	if lit:
		cv.ellipse(tip.x, tip.y - 1, 3.5, 2.5, _fc(0.28))
		cv.px(int(tip.x), int(tip.y) - 1, CYAN_HOT)
		cv.px(int(tip.x), int(tip.y), CYAN)
	else:
		cv.px(int(tip.x), int(tip.y) - 1, TEAL)


static func core(cv, o: Vector2, kind: String, mask: int, v: Dictionary) -> void:
	var hk: float = v.hk
	var raw: bool = v.raw
	match kind:
		"wall":
			_pylon(cv, o, Vector2.ZERO, 0.09, (H + 5.0) * hk, raw, true)
		"gate":
			_gate(cv, o, FL.gate_axis(mask), hk, raw, bool(v.open))
		"tower":
			_spire(cv, o, hk, raw)


static func _gate(cv, o: Vector2, ax: int, hk: float, raw: bool, open: bool) -> void:
	var a := Vector2(1, 0) if ax == 0 else Vector2(0, 1)
	var ph := (H + 9.0) * hk
	var hx := 0.3 if ax == 0 else 0.1
	var hy := 0.1 if ax == 0 else 0.3
	var plate: Dictionary = P.box(cv, o, Vector3(0, 0, 0), hx, hy, 1.0, 0.0, GRAPH_D if not raw else RAW, 0.05, 131)
	_pylon(cv, o, -a * 0.38, 0.08, ph, raw, not open)
	if not raw:
		for k in 5:
			var p: Vector2 = a * (-0.24 + k * 0.12)
			var pp := P.proj(o, Vector3(p.x, p.y, 1))
			cv.px(int(pp.x), int(pp.y), CYAN if not open else TEAL)
		if not open:
			_field(cv, o, -a * 0.3, a * 0.3, 1.0, H + 4.0, true)
		else:
			for k in 7:
				var p: Vector2 = a * (-0.27 + k * 0.09)
				var pp := P.proj(o, Vector3(p.x, p.y, 2))
				cv.px(int(pp.x), int(pp.y), _fc(0.4))
	_pylon(cv, o, a * 0.38, 0.08, ph, raw, not open)
	if raw:
		return
	var hb := P.proj(o, Vector3(0, 0, H + 9.0))
	if plate.is_empty() or open:
		return
	cv.px(int(hb.x), int(hb.y), CYAN_HOT)


static func _spire(cv, o: Vector2, hk: float, raw: bool) -> void:
	if raw:
		L.hexp(cv, o, Vector3(0, 0, 0), 0.28, 58.0 * hk, 0.0, RAW, 141)
		return
	var base: Dictionary = L.hexp(cv, o, Vector3(0, 0, 0), 0.3, 10.0, 0.0, GRAPH, 142)
	for sd in base.sides:
		L.team_panel(cv, sd.quad, 0.15, 0.3, 0.85, 0.6)
	var mid: Dictionary = L.hexp(cv, o, Vector3(0, 0, 10), 0.21, 22.0, 0.0, PANEL, 143)
	for sd in mid.sides:
		L.seam(cv, sd.quad, 0.35)
		L.seam(cv, sd.quad, 0.7)
	var up: Dictionary = L.hexp(cv, o, Vector3(0, 0, 32), 0.12, 14.0, 0.0, GRAPH, 144)
	for sd in up.sides:
		var q: PackedVector2Array = sd.quad
		cv.line_v(q[0].lerp(q[1], 0.5), q[3].lerp(q[2], 0.5), CYAN)
	var c := P.proj(o, Vector3(0, 0, 46))
	cv.ellipse(c.x, c.y - 7, 7.0, 9.0, _fc(0.18))
	cv.poly(PackedVector2Array([c + Vector2(0, 1), c + Vector2(4, -6), c + Vector2(0, -15), c + Vector2(-4, -6)]), CYAN)
	cv.poly(PackedVector2Array([c + Vector2(0, -1), c + Vector2(2, -6), c + Vector2(0, -12), c + Vector2(-1, -6)]), CYAN_HOT)
