extends RefCounted
## G5 naval buildings (agent ART-BLD, CONTRACTS_G5 s3.4 / s8): shipyard (shore art), supply pier and
## coastal battery for Human A, Human B and Machine. Shore defs (shipyard, pier) are drawn with the local
## +u axis pointing at the water (var / facing = water side d, AX[d]); the water half of the footprint
## is left transparent so the terrain water shows through, with slipways / jetties standing in it.
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")

const CONCRETE := Color8(140, 136, 124)
const WOOD := Color8(122, 98, 66)
const HULL_A := Color8(118, 126, 132)
const HULL_B := Color8(124, 80, 54)
const CRANE_A := Color8(206, 168, 52)
const CRANE_B := Color8(150, 72, 44)
const SAND := Color8(150, 134, 98)


static func draw(cv, o: Vector2, kind: String, fk: String, f: int, _var: int, hk: float, raw: bool) -> Array:
	var ps := parts(kind, fk)
	K.render(cv, o, f, ps, hk, raw, func(c, oo, ff, p, r): dress(c, oo, ff, p, r, fk))
	if not raw:
		extras(cv, o, kind, fk, f)
	return ps


static func parts(kind: String, fk: String) -> Array:
	var wall := K.pal(fk, "wall")
	var roof := K.pal(fk, "roof")
	var slab := K.pal(fk, "slab")
	match kind:
		"shipyard":
			var ps: Array = [[-0.7, 0, 0, 0.8, 1.45, 2, slab, "slab"],
				[0.75, -1.2, 0, 0.75, 0.16, 5, CONCRETE if fk != "m" else L.GRAPH_D, "quay"],
				[0.75, 1.2, 0, 0.75, 0.16, 5, CONCRETE if fk != "m" else L.GRAPH_D, "quay"],
				[0.55, 0, 0, 0.95, 0.42, 2, P.mul(slab, 0.85), "box"]]
			if fk == "m":
				ps.append([-0.95, -0.4, 2, 0.6, 0.6, 22, L.GRAPH, "hex"])
				ps.append([-0.95, -0.4, 24, 0.36, 0.36, 8, L.PANEL, "hex"])
				ps.append([-0.95, 0.95, 2, 0.32, 0.32, 14, L.GRAPH_D, "hex"])
				ps.append([0.55, 0, 2, 0.7, 0.24, 6, L.PANEL_D, "hull"])
			else:
				ps.append([-1.0, -0.5, 2, 0.45, 0.85, 26 if fk == "a" else 30, wall, "hall"])
				ps.append([-1.0, -0.5, 28 if fk == "a" else 32, 0.4, 0.8, 3, roof, "team"])
				ps.append([-1.05, 0.9, 2, 0.32, 0.3, 12, P.mul(wall, 0.92), "annex"])
				ps.append([0.55, 0, 2, 0.72, 0.26, 9, HULL_A if fk == "a" else HULL_B, "hull"])
				var cr := CRANE_A if fk == "a" else CRANE_B
				ps.append([0.25, -1.2, 5, 0.04, 0.04, 34, cr, "pole"])
				ps.append([0.25, 1.2, 5, 0.04, 0.04, 34, cr, "pole"])
				ps.append([0.25, 0, 39, 0.06, 1.24, 3, cr, "beam"])
				if fk == "b":
					ps.append([-1.3, -1.15, 2, 0.12, 0.12, 40, Color8(84, 78, 72), "cyl"])
			return ps
		"pier":
			var ps: Array = [[-0.6, 0, 0, 0.4, 0.95, 2, slab, "slab"],
				[0.4, 0, 2, 0.62, 0.26, 2, WOOD if fk == "a" else (CONCRETE if fk == "b" else L.GRAPH_D), "deck"]]
			for u in [0.0, 0.5, 0.95]:
				for v in [-0.24, 0.24]:
					ps.append([u, v, 0, 0.04, 0.04, 2, P.mul(WOOD, 0.7), "pole"])
			match fk:
				"a":
					ps.append([-0.65, -0.5, 2, 0.28, 0.3, 12, wall, "hall"])
					ps.append([-0.65, -0.5, 14, 0.24, 0.26, 2, roof, "team"])
					ps.append([-0.55, 0.55, 2, 0.14, 0.14, 7, Color8(104, 108, 70), "box"])
					ps.append([-0.75, 0.6, 2, 0.12, 0.12, 5, Color8(128, 104, 70), "box"])
					ps.append([0.1, -0.5, 2, 0.05, 0.05, 30, CRANE_A, "pole"])
				"b":
					ps.append([-0.7, -0.5, 2, 0.26, 0.26, 18, Color8(150, 148, 140), "cyl"])
					ps.append([-0.7, 0.35, 2, 0.26, 0.26, 18, Color8(126, 120, 108), "cyl"])
					ps.append([-0.35, -0.85, 2, 0.12, 0.1, 10, wall, "team"])
				"m":
					ps.append([-0.65, -0.4, 2, 0.32, 0.32, 14, L.GRAPH, "hex"])
					ps.append([0.35, -0.05, 4, 0.12, 0.12, 18, L.GRAPH_D, "coil"])
					ps.append([0.85, -0.05, 4, 0.12, 0.12, 18, L.GRAPH_D, "coil"])
			return ps
		"battery":
			match fk:
				"a":
					return [[0, 0, 0, 0.95, 0.95, 2, slab, "slab"],
						[0.05, 0.05, 2, 0.8, 0.8, 8, CONCRETE, "hex"],
						[-0.7, -0.7, 2, 0.24, 0.2, 7, P.mul(CONCRETE, 0.9), "box"],
						[0.05, 0.05, 10, 0.36, 0.32, 9, Color8(108, 112, 96), "turret"],
						[0.05, 0.05, 19, 0.24, 0.22, 3, Color8(200, 200, 200), "team"],
						[0.8, -0.55, 2, 0.12, 0.3, 5, SAND, "bags"]]
				"b":
					return [[0, 0, 0, 0.95, 0.95, 2, slab, "slab"],
						[-0.15, -0.15, 2, 0.75, 0.7, 14, wall, "casemate"],
						[-0.15, -0.15, 16, 0.7, 0.65, 3, P.mul(roof, 0.9), "team"],
						[0.05, 0.05, 19, 0.32, 0.32, 9, Color8(96, 98, 92), "cyl"],
						[0.75, 0.75, 2, 0.14, 0.14, 6, Color8(132, 62, 46), "cyl"]]
			return [[0, 0, 0, 0.95, 0.95, 3, L.SLAB, "slab"],
				[0, 0, 3, 0.75, 0.75, 10, L.GRAPH, "hex"],
				[0, 0, 13, 0.4, 0.4, 14, L.GRAPH_D, "hex"],
				[-0.7, 0.55, 3, 0.18, 0.18, 22, L.GRAPH_D, "coil"],
				[0.55, -0.7, 3, 0.18, 0.18, 22, L.GRAPH_D, "coil"]]
	return [[0, 0, 0, 0.9, 0.9, 2, slab, "slab"]]


static func dress(cv, o: Vector2, f: int, p: Array, r: Dictionary, fk: String) -> void:
	var role := String(p[7])
	var col: Color = p[6]
	match role:
		"hall":
			var n := 0
			for sd in r.sides:
				if n == 0:
					B.rollup(cv, sd.quad, 0.2, 0.8, 0.7, 0.3, 41)
				else:
					B.window_row(cv, sd.quad, 0.55, 0.75, 3, col, 43)
				n += 1
		"annex", "casemate":
			for sd in r.sides:
				if role == "casemate":
					cv.poly(P.sub(sd.quad, 0.3, 0.45, 0.7, 0.7), Color8(26, 26, 24))
				else:
					B.door(cv, sd.quad, 0.35, 0.55, 0.65, col)
				break
		"hull":
			var t: PackedVector2Array = r.top
			for i in 4:
				var u := 0.15 + i * 0.22
				cv.line_v(t[0].lerp(t[3], 0.0).lerp(t[1], u), t[3].lerp(t[2], u), P.mul(col, 0.8))
			if fk == "m":
				cv.line_v(t[0].lerp(t[3], 0.5), t[1].lerp(t[2], 0.5), L.CYAN)
			for sd in r.sides:
				cv.line_v(P.sub(sd.quad, 0, 0.3, 1, 0.3)[0], P.sub(sd.quad, 0, 0.3, 1, 0.3)[1], Color8(150, 50, 40))
		"quay", "deck":
			var t: PackedVector2Array = r.top
			for i in 5:
				var u := 0.1 + i * 0.2
				cv.line_v(t[0].lerp(t[1], u), t[3].lerp(t[2], u), P.mul(col, 0.84))
			if role == "quay":
				cv.team = true
				cv.poly(P.sub(t, 0.0, 0.3, 0.12, 0.7), Color(0.8, 0.8, 0.8))
				cv.team = false
		"turret":
			for sd in r.sides:
				cv.line_v(P.sub(sd.quad, 0, 0.6, 1, 0.6)[0], P.sub(sd.quad, 0, 0.6, 1, 0.6)[1], P.mul(col, 0.8))
		"hex":
			if r.has("top") and r.top.size() >= 6:
				var t: PackedVector2Array = r.top
				var c := (t[0] + t[3]) * 0.5
				if fk == "m":
					L.eye(cv, c, float(p[3]) > 0.45)
					cv.team = true
					cv.poly(PackedVector2Array([t[4].lerp(c, 0.3), t[5].lerp(c, 0.3), t[0].lerp(c, 0.3)]), Color(0.75, 0.75, 0.75))
					cv.team = false
					for sd in r.sides:
						L.seam(cv, sd.quad, 0.5)
				else:
					for sd in r.sides:
						cv.line_v(P.sub(sd.quad, 0, 0.75, 1, 0.75)[0], P.sub(sd.quad, 0, 0.75, 1, 0.75)[1], P.mul(col, 1.15))
		"coil":
			var t: PackedVector2Array = r.top
			for sd in r.sides:
				for i in 4:
					var v := 0.2 + i * 0.2
					cv.line_v(P.sub(sd.quad, 0, v, 1, v)[0], P.sub(sd.quad, 0, v, 1, v)[1], L.CYAN if i % 2 == 0 else L.TEAL)
			cv.px(int((t[0].x + t[2].x) * 0.5), int((t[0].y + t[2].y) * 0.5) - 1, L.CYAN_HOT)
		"bags":
			for sd in r.sides:
				cv.line_v(P.sub(sd.quad, 0, 0.5, 1, 0.5)[0], P.sub(sd.quad, 0, 0.5, 1, 0.5)[1], P.mul(col, 0.8))


static func _barrel(cv, o: Vector2, a: Vector3, dir: Vector2, length: float, col: Color, thick := 2) -> void:
	var b := a + Vector3(dir.x * length, dir.y * length, -2)
	for t in thick:
		cv.line_v(P.proj(o, a) + Vector2(0, -t), P.proj(o, b) + Vector2(0, -t), P.mul(col, 1.0 - 0.18 * t))


static func extras(cv, o: Vector2, kind: String, fk: String, f: int) -> void:
	var gun := Vector2(0.85, -0.4).normalized()
	match kind:
		"battery":
			match fk:
				"a":
					for s in [-0.09, 0.09]:
						var a: Vector2 = K.wp(f, 0.05, 0.05) + Vector2(-gun.y, gun.x) * s
						_barrel(cv, o, Vector3(a.x, a.y, 15), gun, 1.05, Color8(70, 74, 64))
				"b":
					var a := K.wp(f, 0.05, 0.05)
					_barrel(cv, o, Vector3(a.x, a.y, 24), gun, 1.25, Color8(64, 64, 60), 3)
				"m":
					var a := K.wp(f, 0.0, 0.0)
					_barrel(cv, o, Vector3(a.x, a.y, 25), gun, 1.3, L.GRAPH_D, 2)
					var b := a + gun * 1.2
					cv.line_v(P.proj(o, Vector3(a.x, a.y, 26)), P.proj(o, Vector3(b.x, b.y, 24)), L.CYAN)
					for c in [Vector2(-0.7, 0.55), Vector2(0.55, -0.7)]:
						var t := K.pt(o, f, c.x, c.y, 26)
						cv.px(int(t.x), int(t.y), L.CYAN_HOT)
		"shipyard":
			if fk == "m":
				var a := K.pt(o, f, -0.95, -0.4, 32)
				var b := K.pt(o, f, 0.4, 0.0, 14)
				cv.line_v(a, b, L.PANEL)
				cv.line_v(a + Vector2(1, 0), b + Vector2(1, 0), L.PANEL_D)
				cv.px(int(b.x), int(b.y) + 1, L.CYAN_HOT)
				return
			var tr := K.pt(o, f, 0.25, 0.1, 39)
			cv.rect(int(tr.x) - 2, int(tr.y), 5, 3, Color8(60, 60, 56))
			cv.line_v(tr + Vector2(0, 3), K.pt(o, f, 0.35, 0.1, 14), Color8(40, 40, 38))
		"pier":
			if fk == "a":
				var a := K.pt(o, f, 0.1, -0.5, 32)
				var b := K.pt(o, f, 0.75, 0.0, 26)
				cv.line_v(a, b, CRANE_A)
				cv.line_v(b, b + Vector2(0, 8), Color8(40, 40, 38))
			elif fk == "b":
				B.pipe(cv, o, Vector3(K.wp(f, -0.5, 0.0).x, K.wp(f, -0.5, 0.0).y, 6), Vector3(K.wp(f, 0.95, 0.0).x, K.wp(f, 0.95, 0.0).y, 6), Color8(92, 94, 92))
			else:
				for u in [0.35, 0.85]:
					var t := K.pt(o, f, u, -0.05, 23)
					cv.px(int(t.x), int(t.y), L.CYAN_HOT)
			for u in [0.2, 0.75]:
				var bp := K.pt(o, f, u, 0.3, 4)
				cv.rect(int(bp.x), int(bp.y) - 2, 2, 2, Color8(40, 40, 38))
