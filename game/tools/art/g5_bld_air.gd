extends RefCounted
## G5 air buildings (agent ART-BLD): airfield / aerodrome aprons, airstrips, forward strips, the Machine
## launch rail, helipads, forward helipads and control towers. Local frame of g5_bld_lib: +v is the
## side the strips run along (airfield.gd strip_points), so taxi lines and edge lights face +v.
## draw(cv, o, kind, fk, f, var, hk, raw) -> the part list used (for scaffolds).
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")

const OLIVE := Color8(98, 100, 72)
const SAND := Color8(150, 134, 98)
const SOCK := Color8(236, 120, 40)
const LAMP_G := Color8(120, 236, 120)
const LAMP_R := Color8(238, 64, 48)


static func draw(cv, o: Vector2, kind: String, fk: String, f: int, _var: int, hk: float, raw: bool) -> Array:
	var ps := parts(kind, fk)
	var slab: Array = ps[0]
	K.part(cv, o, f, slab, 1.0, raw)
	if not raw:
		decals(cv, o, kind, fk, f)
	K.render(cv, o, f, ps.slice(1), hk, raw, func(c, oo, ff, p, r): dress(c, oo, ff, p, r, fk))
	if not raw:
		extras(cv, o, kind, fk, f)
	return ps


static func parts(kind: String, fk: String) -> Array:
	var wall := K.pal(fk, "wall")
	var roof := K.pal(fk, "roof")
	var metal := K.pal(fk, "metal")
	var tar := K.pal(fk, "tarmac")
	var trim := K.pal(fk, "trim")
	match kind:
		"airfield":
			var ps: Array = [[0, 0, 0, 2.95, 2.95, 2, P.mix(tar, K.pal(fk, "slab"), 0.35), "slab"],
				[-1.7, -1.7, 2, 1.05, 0.85, 20 if fk == "a" else 24, wall, "ops"],
				[-1.7, -1.7, 22 if fk == "a" else 26, 0.95, 0.75, 3, roof, "team"],
				[1.5, -2.3, 2, 0.34, 0.34, 18, metal, "cyl"], [2.35, -2.3, 2, 0.34, 0.34, 18, metal, "cyl"],
				[0.2, -2.55, 2, 0.75, 0.1, 8, P.mul(K.pal(fk, "slab"), 1.15), "wall"],
				[0.9, 0.9, 2, 0.26, 0.15, 6, trim, "veh"], [1.35, 0.9, 2, 0.14, 0.12, 4, P.mul(trim, 0.8), "veh"],
				[-2.55, -0.4, 2, 0.04, 0.04, 40, Color8(70, 72, 70), "pole"]]
			if fk == "b":
				ps.append([-0.55, -2.35, 2, 0.32, 0.32, 40, P.mul(wall, 0.9), "clock"])
				ps.append([2.35, -1.2, 22, 0.42, 0.42, 14, metal, "cyl"])
				for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					ps.append([2.35 + s.x * 0.3, -1.2 + s.y * 0.3, 2, 0.03, 0.03, 20, Color8(70, 66, 60), "pole"])
			return ps
		"airstrip":
			return [[0, 0, 0, 1.95, 1.95, 2, P.mix(tar, K.pal(fk, "slab"), 0.35), "slab"],
				[-1.1, -1.1, 2, 0.7, 0.55, 14, wall, "ops"], [-1.1, -1.1, 16, 0.62, 0.47, 3, roof, "team"],
				[1.1, -1.3, 2, 0.5, 0.3, 4, Color8(54, 58, 50), "bladder"],
				[0.6, 0.7, 2, 0.24, 0.14, 6, trim, "veh"]]
		"fwd_strip":
			var cvs := K.pal(fk, "canvas")
			return [[0, 0, 0, 1.45, 1.45, 1, P.mix(SAND, tar, 0.25), "slab"],
				[-0.1, 0.3, 1, 1.3, 1.0, 0, Color8(108, 112, 106), "mat"],
				[-0.85, -0.85, 1, 0.5, 0.36, 14, cvs, "tent"], [0.55, -1.05, 1, 0.34, 0.26, 10, P.mul(cvs, 0.92), "tent"],
				[0.05, -0.5, 1, 0.08, 0.08, 6, Color8(132, 62, 46), "cyl"], [0.25, -0.45, 1, 0.08, 0.08, 6, Color8(84, 96, 62), "cyl"],
				[-1.25, 0.3, 1, 0.1, 0.45, 5, SAND, "bags"], [1.0, -0.1, 1, 0.18, 0.18, 5, Color8(128, 104, 70), "box"],
				[-1.3, -1.25, 1, 0.12, 0.12, 4, Color8(220, 220, 210), "team"]]
		"rail":
			var ps: Array = [[0, 0, 0, 2.45, 2.45, 3, L.SLAB, "slab"],
				[-1.4, -1.35, 3, 0.75, 0.75, 16, L.GRAPH, "hex"], [-1.4, -1.35, 19, 0.45, 0.45, 6, L.PANEL, "hex"],
				[1.5, -1.5, 3, 0.28, 0.28, 26, L.GRAPH_D, "hex"], [-1.9, 1.5, 3, 0.28, 0.28, 22, L.GRAPH_D, "hex"]]
			for i in 5:  # launch ramp rising along +u
				ps.append([-1.6 + i * 0.85, 1.2, 3, 0.43, 0.32, 4 + i * 3, P.mul(L.PANEL_D, 0.9 + i * 0.03), "ramp"])
			return ps
		"helipad":
			return [[0, 0, 0, 0.95, 0.95, 3, P.mix(tar, K.pal(fk, "slab"), 0.5), "slab"],
				[-0.82, 0.55, 3, 0.1, 0.16, 6, trim, "veh"]]
		"fwd_helipad":
			var ps: Array = [[0, 0, 0, 0.95, 0.95, 1, P.mix(SAND, tar, 0.3), "slab"],
				[0, 0, 1, 0.8, 0.8, 0, Color8(104, 108, 100), "mat"],
				[-0.75, -0.75, 1, 0.12, 0.12, 6, Color8(68, 72, 62), "cyl"]]
			for i in 5:
				var a := PI * 0.9 + i * 0.32
				ps.append([cos(a) * 0.86, sin(a) * 0.86, 1, 0.14, 0.09, 4, SAND, "bags"])
			return ps
		"tower":
			if fk == "b":
				return [[0, 0, 0, 0.95, 0.95, 2, K.pal(fk, "slab"), "slab"],
					[0.35, 0.35, 2, 0.5, 0.42, 12, wall, "ops"],
					[-0.25, -0.25, 2, 0.34, 0.34, 46, wall, "shaft"],
					[-0.25, -0.25, 48, 0.46, 0.46, 3, Color8(70, 66, 60), "box"],
					[-0.25, -0.25, 51, 0.4, 0.4, 10, Color8(40, 46, 48), "glass"],
					[-0.25, -0.25, 61, 0.46, 0.46, 3, metal, "team"]]
			return [[0, 0, 0, 0.95, 0.95, 2, K.pal(fk, "slab"), "slab"],
				[0.35, 0.35, 2, 0.5, 0.45, 10, wall, "ops"],
				[-0.25, -0.25, 2, 0.26, 0.26, 44, P.mul(wall, 1.05), "shaft"],
				[-0.25, -0.25, 46, 0.44, 0.44, 11, Color8(40, 48, 52), "glass"],
				[-0.25, -0.25, 57, 0.48, 0.48, 3, roof, "team"]]
	return [[0, 0, 0, 0.9, 0.9, 2, K.pal(fk, "slab"), "slab"]]


## Ground markings on the slab (taxi lines, pads, circles), drawn before the parts.
static func decals(cv, o: Vector2, kind: String, fk: String, f: int) -> void:
	var mk := K.pal(fk, "mark")
	match kind:
		"airfield":
			K.gquad(cv, o, f, -0.06, -0.6, 0.06, 2.95, 2.1, mk)
			K.gquad(cv, o, f, -2.9, 1.95, 2.9, 2.07, 2.1, mk)
			for i in 3:
				var u := -1.4 + i * 1.4
				K.gquad(cv, o, f, u - 0.5, 0.2, u + 0.5, 0.24, 2.1, P.mul(mk, 0.85))
				K.gquad(cv, o, f, u - 0.5, 0.2, u - 0.46, 1.2, 2.1, P.mul(mk, 0.85))
			K.gquad(cv, o, f, -2.9, 2.75, 2.9, 2.9, 2.1, Color(0.85, 0.85, 0.85), true)
		"airstrip":
			K.gquad(cv, o, f, -0.05, -0.2, 0.05, 1.95, 2.1, mk)
			K.gquad(cv, o, f, -1.9, 1.3, 1.9, 1.38, 2.1, mk)
			K.gquad(cv, o, f, -1.9, 1.78, 1.9, 1.9, 2.1, Color(0.85, 0.85, 0.85), true)
		"fwd_strip":
			for i in 7:
				K.gline(cv, o, f, -1.2 + i * 0.38, -0.6, -1.2 + i * 0.38, 1.2, 1.1, Color8(84, 88, 82))
			K.gquad(cv, o, f, 1.0, 1.0, 1.35, 1.35, 1.2, Color(0.85, 0.85, 0.85), true)
		"rail":
			for i in 4:
				K.gline(cv, o, f, -2.3, -0.3 + i * 0.12, 2.3, -0.3 + i * 0.12, 3.2, P.mul(L.CYAN, 0.55 + 0.1 * (i % 2)))
			K.gline(cv, o, f, -1.4, -0.6, -1.4, 0.8, 3.2, L.TEAL)
			K.gquad(cv, o, f, -2.4, 2.25, 2.4, 2.4, 3.2, Color(0.8, 0.8, 0.8), true)
		"helipad", "fwd_helipad":
			var z := 3.2 if kind == "helipad" else 1.2
			var col := mk if kind == "helipad" else Color8(220, 214, 190)
			for i in 40:
				var a := i * TAU / 40.0
				var a2 := (i + 0.6) * TAU / 40.0
				K.gline(cv, o, f, cos(a) * 0.72, sin(a) * 0.72, cos(a2) * 0.72, sin(a2) * 0.72, z, col)
			if fk == "b" and kind == "helipad":
				K.gquad(cv, o, f, -0.38, -0.38, 0.38, 0.38, z, P.mul(mk, 0.3))
			K.gquad(cv, o, f, -0.3, -0.36, -0.18, 0.36, z, col)
			K.gquad(cv, o, f, 0.18, -0.36, 0.3, 0.36, z, col)
			K.gquad(cv, o, f, -0.18, -0.05, 0.18, 0.05, z, col)
			K.gquad(cv, o, f, -0.92, 0.8, 0.92, 0.92, z, Color(0.85, 0.85, 0.85), true)


static func dress(cv, o: Vector2, f: int, p: Array, r: Dictionary, fk: String) -> void:
	var role := String(p[7])
	var col: Color = p[6]
	match role:
		"ops", "clock":
			var n := 0
			for sd in r.sides:
				B.window_row(cv, sd.quad, 0.42 if role == "ops" else 0.7, 0.68 if role == "ops" else 0.82, 3 if role == "ops" else 1, col, 91 + n)
				if n == 0 and role == "ops":
					B.door(cv, sd.quad, 0.7, 0.86, 0.36, col)
				n += 1
			if role == "clock":
				var t: PackedVector2Array = r.top
				cv.poly(P.sub(t, 0.2, 0.2, 0.8, 0.8), P.mul(K.pal(fk, "roof"), 0.9))
		"shaft":
			for sd in r.sides:
				for i in 4:
					var v := 0.15 + i * 0.22
					cv.line_v(P.sub(sd.quad, 0, v, 1, v)[0], P.sub(sd.quad, 0, v, 1, v)[1], P.mul(col, 0.84))
		"glass":
			for sd in r.sides:
				for i in 3:
					var u := 0.18 + i * 0.32
					cv.line_v(P.sub(sd.quad, u, 0, u, 1)[0], P.sub(sd.quad, u, 0, u, 1)[3], Color8(96, 104, 102))
				cv.line_v(sd.quad[3], sd.quad[2], Color8(150, 200, 210))
		"ramp":
			var t: PackedVector2Array = r.top
			cv.line_v(t[0].lerp(t[3], 0.3), t[1].lerp(t[2], 0.3), L.CYAN)
			cv.line_v(t[0].lerp(t[3], 0.7), t[1].lerp(t[2], 0.7), L.CYAN)
		"hex":
			if not r.has("top") or r.top.size() < 6:
				return
			var t: PackedVector2Array = r.top
			var c := (t[0] + t[3]) * 0.5
			L.eye(cv, c, float(p[3]) > 0.5)
			if float(p[3]) > 0.5:
				cv.team = true
				cv.poly(PackedVector2Array([t[0].lerp(c, 0.25), t[1].lerp(c, 0.25), t[2].lerp(c, 0.25)]), Color(0.75, 0.75, 0.75))
				cv.team = false
			for sd in r.sides:
				L.seam(cv, sd.quad, 0.5)
		"bags":
			for sd in r.sides:
				cv.line_v(P.sub(sd.quad, 0, 0.5, 1, 0.5)[0], P.sub(sd.quad, 0, 0.5, 1, 0.5)[1], P.mul(col, 0.8))
		"cyl":
			pass


## Masts, windsocks, lamps and antennas drawn after the parts.
static func extras(cv, o: Vector2, kind: String, fk: String, f: int) -> void:
	match kind:
		"airfield":
			var tip := K.pt(o, f, -2.55, -0.4, 42)
			cv.rect(int(tip.x) - 3, int(tip.y) - 1, 7, 2, Color8(150, 154, 150))
			K.lamp(cv, tip + Vector2(0, -2), LAMP_R)
			for i in 7:
				K.lamp(cv, K.pt(o, f, -2.8 + i * 0.93, 2.93, 2.5), LAMP_G if i % 2 == 0 else Color8(240, 230, 150))
			_sock(cv, K.pt(o, f, 2.6, 2.5, 2))
		"airstrip":
			_sock(cv, K.pt(o, f, 1.7, 1.5, 2))
			for i in 5:
				K.lamp(cv, K.pt(o, f, -1.8 + i * 0.9, 1.93, 2.5), LAMP_G)
		"fwd_strip":
			_sock(cv, K.pt(o, f, 1.2, -1.2, 1))
		"helipad":
			for s in [Vector2(-0.9, -0.9), Vector2(0.9, -0.9), Vector2(0.9, 0.9), Vector2(-0.9, 0.9)]:
				K.lamp(cv, K.pt(o, f, s.x, s.y, 3.5), LAMP_G if fk == "a" else Color8(240, 200, 80))
			_sock(cv, K.pt(o, f, 0.85, -0.8, 3))
		"fwd_helipad":
			var p := K.pt(o, f, 0.7, -0.75, 1)
			cv.rect(int(p.x), int(p.y) - 3, 2, 3, Color8(60, 66, 56))
			for i in 6:
				cv.px(int(p.x) + i / 2, int(p.y) - 4 - i, Color(0.45, 0.78, 0.4, 0.7 - i * 0.09))
		"tower":
			var top := K.pt(o, f, -0.25, -0.25, 60 if fk == "a" else 64)
			cv.line_v(top, top + Vector2(0, -14), Color8(60, 62, 60))
			K.lamp(cv, top + Vector2(0, -15), LAMP_R)
			cv.rect(int(top.x) + 3, int(top.y) - 6, 5, 1, Color8(150, 152, 148))
		"rail":
			for c in [Vector2(1.5, -1.5), Vector2(-1.9, 1.5)]:
				var tip := K.pt(o, f, c.x, c.y, 29 if c.x > 0 else 25)
				cv.px(int(tip.x), int(tip.y) - 1, L.CYAN_HOT)
				cv.px(int(tip.x), int(tip.y), L.CYAN)


static func _sock(cv, base: Vector2) -> void:
	cv.line_v(base, base + Vector2(0, -16), Color8(70, 70, 66))
	for i in 6:
		var c := SOCK if (i / 2) % 2 == 0 else Color8(236, 230, 220)
		cv.rect(int(base.x) + 1 + i, int(base.y) - 16 + i / 3, 1, 3 - i / 3, c)
