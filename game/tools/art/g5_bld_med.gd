extends RefCounted
## G5 medical buildings (agent ART-BLD, CONTRACTS_G5 s3.4 / s10): Hospital and Field Hospital for
## Human A (modular containers + ward tents, white/olive) and Human B (brick infirmary, canvas triage
## tents). Red crosses on roofs and ground panels read at zoom-out.
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")

const CONT := Color8(196, 196, 184)
const CANVAS_A := Color8(112, 116, 78)
const CANVAS_B := Color8(168, 152, 116)
const SAND := Color8(150, 134, 98)
const CRATE := Color8(128, 104, 70)


static func draw(cv, o: Vector2, kind: String, fk: String, f: int, _var: int, hk: float, raw: bool) -> Array:
	var ps := parts(kind, fk)
	K.render(cv, o, f, ps, hk, raw, func(c, oo, ff, p, r): dress(c, oo, ff, p, r, fk))
	if not raw:
		extras(cv, o, kind, fk, f)
	return ps


static func parts(kind: String, fk: String) -> Array:
	var slab := K.pal(fk, "slab")
	if kind == "hospital":
		if fk == "a":
			return [[0, 0, 0, 1.45, 1.45, 2, slab, "slab"],
				[-0.75, -0.65, 2, 0.62, 0.32, 13, CONT, "cont"], [-0.75, 0.05, 2, 0.62, 0.32, 13, P.mul(CONT, 0.96), "cont"],
				[-0.75, -0.3, 15, 0.55, 0.28, 10, CONT, "cont_top"],
				[0.6, -0.55, 2, 0.6, 0.8, 18, CANVAS_A, "tent"],
				[0.6, 0.85, 2, 0.45, 0.3, 14, P.mul(CANVAS_A, 0.95), "tent"],
				[-0.8, 0.95, 2, 0.4, 0.32, 1, Color8(70, 72, 70), "mat"],
				[-1.25, -1.25, 2, 0.1, 0.1, 6, Color8(84, 96, 62), "cyl"]]
		return [[0, 0, 0, 1.45, 1.45, 2, slab, "slab"],
			[-0.45, -0.45, 2, 0.95, 0.75, 22, K.pal("b", "wall"), "hall"],
			[-0.45, -0.45, 24, 0.9, 0.7, 4, K.pal("b", "roof"), "roof"],
			[-1.15, -1.0, 26, 0.1, 0.1, 12, P.mul(K.pal("b", "wall"), 0.9), "box"],
			[0.85, 0.55, 2, 0.48, 0.35, 15, CANVAS_B, "tent"],
			[-0.2, 1.0, 2, 0.4, 0.3, 13, P.mul(CANVAS_B, 0.95), "tent"],
			[1.1, -0.9, 2, 0.14, 0.14, 6, CRATE, "box"]]
	if fk == "a":
		return [[0, 0, 0, 0.95, 0.95, 1, P.mix(slab, SAND, 0.4), "slab"],
			[-0.2, -0.25, 1, 0.6, 0.45, 16, CANVAS_A, "tent"],
			[0.62, -0.62, 1, 0.12, 0.3, 5, SAND, "bags"], [-0.75, 0.6, 1, 0.12, 0.12, 6, CRATE, "box"],
			[0.45, 0.5, 1, 0.22, 0.07, 3, Color8(210, 210, 200), "box"], [0.45, 0.72, 1, 0.22, 0.07, 3, Color8(210, 210, 200), "box"],
			[-0.85, -0.85, 1, 0.08, 0.08, 7, Color8(84, 96, 62), "cyl"]]
	return [[0, 0, 0, 0.95, 0.95, 1, P.mix(slab, SAND, 0.5), "slab"],
		[-0.15, -0.15, 1, 0.7, 0.55, 18, CANVAS_B, "tent"],
		[0.7, 0.35, 1, 0.14, 0.14, 6, CRATE, "box"], [0.7, 0.62, 1, 0.12, 0.12, 4, P.mul(CRATE, 0.9), "box"],
		[0.4, 0.75, 1, 0.2, 0.07, 3, Color8(210, 206, 190), "box"], [-0.8, 0.7, 1, 0.08, 0.08, 6, Color8(132, 62, 46), "cyl"]]


static func dress(cv, o: Vector2, f: int, p: Array, r: Dictionary, fk: String) -> void:
	var role := String(p[7])
	var col: Color = p[6]
	match role:
		"cont", "cont_top":
			for sd in r.sides:
				for i in 6:
					var u := 0.08 + i * 0.17
					cv.line_v(P.sub(sd.quad, u, 0, u, 1)[0], P.sub(sd.quad, u, 0, u, 1)[3], P.mul(col, 0.86))
				cv.team = true
				cv.poly(P.sub(sd.quad, 0.0, 0.82, 1.0, 0.94), Color(0.78, 0.78, 0.78))
				cv.team = false
			if role == "cont_top":
				K.cross(cv, r.top, 0.5, 0.5, 0.3)
				for sd in r.sides:
					B.door(cv, sd.quad, 0.42, 0.58, 0.7, col)
					break
		"hall":
			var n := 0
			for sd in r.sides:
				B.window_row(cv, sd.quad, 0.5, 0.75, 4, col, 63 + n)
				if n == 0:
					B.door(cv, sd.quad, 0.44, 0.58, 0.4, col)
				n += 1
		"roof":
			K.cross(cv, r.top, 0.5, 0.5, 0.28)
			cv.team = true
			cv.poly(P.sub(r.top, 0.0, 0.0, 1.0, 0.08), Color(0.78, 0.78, 0.78))
			cv.team = false
		"bags":
			for sd in r.sides:
				cv.line_v(P.sub(sd.quad, 0, 0.5, 1, 0.5)[0], P.sub(sd.quad, 0, 0.5, 1, 0.5)[1], P.mul(col, 0.8))


static func extras(cv, o: Vector2, kind: String, fk: String, f: int) -> void:
	if kind == "hospital":
		if fk == "a":
			K.gquad(cv, o, f, -1.15, 0.7, -0.45, 1.2, 2.2, Color8(230, 226, 210))
			K.gquad(cv, o, f, -1.0, 0.8, -0.6, 0.86, 2.3, Color8(70, 72, 70))
			K.gquad(cv, o, f, -1.0, 1.04, -0.6, 1.1, 2.3, Color8(70, 72, 70))
			K.gquad(cv, o, f, -0.83, 0.86, -0.77, 1.04, 2.3, Color8(70, 72, 70))
		_flag(cv, K.pt(o, f, 1.25, 1.25, 2), 24)
		_ground_cross(cv, o, f, 0.65, -0.1 if fk == "a" else 0.55, 2.3, 0.0)
	else:
		_ground_cross(cv, o, f, 0.5, -0.45, 1.2, 0.0)
		_flag(cv, K.pt(o, f, -0.8, 0.8, 1), 18)


## Tent-side cross: a white panel with a red cross laid flat on the ground plane (reads from above).
static func _ground_cross(cv, o: Vector2, f: int, u: float, v: float, z: float, _x: float) -> void:
	var s := 0.2
	K.gquad(cv, o, f, u - s, v - s, u + s, v + s, z, K.WHITE)
	K.gquad(cv, o, f, u - s * 0.72, v - s * 0.22, u + s * 0.72, v + s * 0.22, z, K.RED)
	K.gquad(cv, o, f, u - s * 0.22, v - s * 0.72, u + s * 0.22, v + s * 0.72, z, K.RED)


static func _flag(cv, base: Vector2, h: int) -> void:
	cv.line_v(base, base + Vector2(0, -h), Color8(70, 70, 66))
	var t := base + Vector2(1, -h)
	cv.rect(int(t.x), int(t.y), 8, 5, K.WHITE)
	cv.rect(int(t.x) + 3, int(t.y), 2, 5, K.RED)
	cv.rect(int(t.x) + 1, int(t.y) + 2, 6, 1, K.RED)
	cv.team = true
	cv.rect(int(t.x), int(t.y) + 5, 8, 1, Color(0.8, 0.8, 0.8))
	cv.team = false
