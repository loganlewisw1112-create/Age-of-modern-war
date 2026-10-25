extends RefCounted
## G5 hangars (agent ART-BLD, CONTRACTS_G5 s3.5): Light / Heavy hangars for Human A and B and the Machine
## Drone Bay, each in 4 upgrade looks (var = hangar.level 0..3; looks are cumulative):
##   L0 plain; L1 rearm/refuel kit (fuel bowser + ammo crates / Machine charge pylon);
##   L2 + maintenance gantry and tool cart (Machine: twin repair arms);
##   L3 + armored roof: concrete cap and earth berms (Machine: dark hex armour shell).
## The hangar door faces local +u (screen lower right at f = 0). Size 2 footprints.
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")

const CONCRETE := Color8(146, 142, 130)
const BERM := Color8(104, 98, 64)
const FUEL := Color8(150, 132, 52)
const CRATE := Color8(104, 108, 70)
const GANTRY := Color8(206, 168, 52)


static func draw(cv, o: Vector2, kind: String, fk: String, f: int, lvl: int, hk: float, raw: bool) -> Array:
	var ps := parts(kind, fk, lvl)
	K.render(cv, o, f, ps, hk, raw, func(c, oo, ff, p, r): dress(c, oo, ff, p, r, fk, lvl))
	if not raw:
		extras(cv, o, kind, fk, f, lvl)
	return ps


static func parts(kind: String, fk: String, lvl: int) -> Array:
	var ps: Array = [[0, 0, 0, 0.95, 0.95, 2, K.pal(fk, "slab"), "slab"]]
	var heavy := kind == "hangar_heavy"
	var armored := lvl >= 3
	if fk == "m":
		ps.append([-0.05, 0, 2, 0.82, 0.82, 16, L.GRAPH, "hex"])
		ps.append([-0.05, 0, 18, 0.58, 0.58, 8 if not armored else 11, L.GRAPH_D if armored else L.PANEL_D, "hex"])
		ps.append([0.72, 0.0, 2, 0.08, 0.34, 12, L.GRAPH_D, "iris"])
		if armored:
			for i in 3:
				var a := PI * 0.5 + i * PI * 0.5
				ps.append([cos(a) * 0.62 - 0.05, sin(a) * 0.62, 6, 0.22, 0.22, 14, P.mul(L.GRAPH_D, 0.9), "hex"])
		if lvl >= 1:
			ps.append([0.62, -0.72, 2, 0.16, 0.16, 20, L.GRAPH, "pylon"])
		if lvl >= 2:
			ps.append([0.78, 0.62, 2, 0.03, 0.03, 18, L.PANEL, "pole"])
			ps.append([0.78, -0.3, 2, 0.03, 0.03, 18, L.PANEL, "pole"])
		return ps
	var body := K.pal(fk, "metal") if fk == "a" else K.pal(fk, "roof")
	if armored:
		body = CONCRETE
	if heavy:
		ps.append([-0.1, 0, 2, 0.84, 0.84, 30, K.pal(fk, "wall"), "hall"])
		if fk == "b" and not armored:
			for i in 3:
				ps.append([-0.1, -0.56 + i * 0.56, 32, 0.84, 0.28, 10, K.pal(fk, "roof"), "tent"])
			ps.append([-0.1, 0.86, 22, 0.8, 0.03, 6, Color(0.8, 0.8, 0.8), "team"])
		else:
			if armored:
				ps.append([-0.1, 0, 32, 0.86, 0.86, 7, P.mul(CONCRETE, 0.92), "cap"])
				ps.append([-0.1, 0.6, 39, 0.6, 0.06, 2, Color(0.8, 0.8, 0.8), "team"])
			else:
				ps.append([-0.1, 0, 32, 0.8, 0.8, 3, K.pal(fk, "roof"), "team"])
		ps.append([-0.55, -0.92, 2, 0.32, 0.1, 12, P.mul(K.pal(fk, "wall"), 0.95), "annex"])
	else:
		ps.append([-0.1, 0, 2, 0.8, 0.72, 26 if not armored else 28, body, "arch"])
		ps.append([-0.1, 0, 2 + (26 if not armored else 28), 0.7, 0.08, 2, Color(0.8, 0.8, 0.8), "team"])
	if armored:
		ps.append([-0.15, 0.9, 2, 0.75, 0.08, 14 if heavy else 12, BERM, "berm"])
		if not heavy:
			ps.append([-0.1, 0, 30, 0.55, 0.45, 5, P.mul(CONCRETE, 0.92), "cap"])
	if lvl >= 1:
		ps.append([0.72, -0.72, 2, 0.22, 0.12, 9, FUEL, "bowser"])
		ps.append([0.78, 0.7, 2, 0.12, 0.12, 5, CRATE, "box"])
		ps.append([0.6, 0.78, 2, 0.1, 0.1, 4, P.mul(CRATE, 0.9), "box"])
	if lvl >= 2:
		ps.append([0.88, -0.45, 2, 0.03, 0.03, 30 if heavy else 26, GANTRY, "pole"])
		ps.append([0.88, 0.45, 2, 0.03, 0.03, 30 if heavy else 26, GANTRY, "pole"])
		ps.append([0.88, 0.0, 30 if heavy else 26, 0.04, 0.48, 3, GANTRY, "beam"])
		ps.append([0.55, 0.62, 2, 0.1, 0.07, 6, Color8(176, 52, 40), "box"])
	return ps


static func dress(cv, o: Vector2, f: int, p: Array, r: Dictionary, fk: String, lvl: int) -> void:
	var role := String(p[7])
	var col: Color = p[6]
	match role:
		"hall", "arch":
			for sd in r.sides:
				var front: bool = absf(sd.n.dot(K.AX[f % 4])) > 0.7
				if front:
					B.rollup(cv, sd.quad, 0.12, 0.88, 0.86 if role == "hall" else 0.92, 0.0, 51)
					if lvl >= 3:
						cv.poly(P.sub(sd.quad, 0.08, 0.86, 0.92, 1.0), P.mul(CONCRETE, 0.8))
				else:
					if role == "hall":
						B.window_row(cv, sd.quad, 0.6, 0.78, 3, col, 77)
					else:
						for i in 5:
							var u := 0.1 + i * 0.2
							cv.line_v(P.sub(sd.quad, u, 0, u, 1)[0], P.sub(sd.quad, u, 0, u, 1)[3], P.mul(col, 0.82))
		"annex":
			for sd in r.sides:
				B.door(cv, sd.quad, 0.3, 0.5, 0.7, col)
				break
		"bowser":
			for sd in r.sides:
				cv.poly(P.sub(sd.quad, 0.05, 0.0, 0.25, 0.4), Color8(40, 40, 38))
				cv.poly(P.sub(sd.quad, 0.7, 0.0, 0.9, 0.4), Color8(40, 40, 38))
		"berm":
			for sd in r.sides:
				for i in 4:
					var v := 0.2 + i * 0.2
					var q := P.sub(sd.quad, 0.0, v, 1.0, v)
					cv.line_v(q[0], q[1], P.mul(col, 0.86 + 0.06 * (i % 2)))
		"hex":
			if r.has("top") and r.top.size() >= 6:
				var t: PackedVector2Array = r.top
				var c := (t[0] + t[3]) * 0.5
				if float(p[3]) > 0.5:
					cv.team = true
					cv.poly(PackedVector2Array([t[0].lerp(c, 0.3), t[1].lerp(c, 0.3), t[2].lerp(c, 0.3), t[3].lerp(c, 0.3)]), Color(0.75, 0.75, 0.75))
					cv.team = false
				for sd in r.sides:
					L.seam(cv, sd.quad, 0.45)
		"iris":
			for sd in r.sides:
				if absf(sd.n.dot(K.AX[f % 4])) > 0.7:
					var c: Vector2 = (sd.quad[0] + sd.quad[2]) * 0.5
					for i in 5:
						cv.line_v(c, sd.quad[0].lerp(sd.quad[1], i / 4.0), L.JOINT)
					cv.px(int(c.x), int(c.y), L.CYAN_HOT)
		"pylon":
			cv.line_v(r.top[0], r.top[2], L.CYAN)


static func extras(cv, o: Vector2, kind: String, fk: String, f: int, lvl: int) -> void:
	if fk == "m":
		if lvl >= 1:
			var t := K.pt(o, f, 0.62, -0.72, 23)
			cv.px(int(t.x), int(t.y), L.CYAN_HOT)
			cv.px(int(t.x), int(t.y) + 1, L.CYAN)
		if lvl >= 2:
			for v in [0.62, -0.3]:
				var a := K.pt(o, f, 0.78, v, 20)
				var b := K.pt(o, f, 0.55, v * 0.6, 14)
				cv.line_v(a, b, L.PANEL)
				cv.px(int(b.x), int(b.y), L.CYAN)
		return
	if lvl >= 2:
		var hook := K.pt(o, f, 0.88, 0.1, 28 if kind == "hangar_heavy" else 24)
		cv.line_v(hook, hook + Vector2(0, 7), Color8(40, 40, 38))
	var lp := K.pt(o, f, 0.7, 0.0, 30 if kind == "hangar_heavy" else 24)
	K.lamp(cv, lp, Color8(240, 222, 140))
