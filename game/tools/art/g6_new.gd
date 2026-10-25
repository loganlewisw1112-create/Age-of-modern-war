extends RefCounted
## G6 new pieces not on the art page (agent ART-G6b, CONTRACTS_G6 s3.2), drawn with the game's own libraries:
##   buildings (H.bld: rot_0..3, damaged, build_0..2, all from one local-frame part list, g5_bld_lib roles)
##     a_company_hq   Human A two-storey concrete command post: team roof, satellite dish, roof mast, comms
##                    annex, generator, flag on a parade pad, parked jeep
##     b_company_hq   Human B brick manor HQ: pitched tile roof, team banner on the facade, watchtower, wire
##                    aerial mast, field-kitchen tent, staff car, flag
##     m_company_hq   Machine command nexus: stacked hex core with a big eye, crown spire, three relay pylons
##                    linked by cyan conduits
##     a_exo_garage   Human A suit garage (size 2): tall shed with a roll-up door, yellow gantry crane over a
##                    hazard-striped work pad with a parked a_exo_rifle suit, charging pylon
##   units
##     a/b_commander, a/b_captain, a/b_lieutenant  G5 figure kit officers (1-man squads, 48x36): officer cap /
##       helmet bars, gold shoulder boards, pistol or carbine, radio for captains; frame `command` = pointing
##     m_commander / m_captain / m_lieutenant      Machine command nodes (vehicle sheets): hovering hex core,
##       one-eyed, rank = antenna crossbars + orbiting relay shards (3 / 2 / 1); `command` = relay pulse ring
##     a_exo_rifle / a_exo_missile / a_exo_aa      Human A AMP-style exo suits (2.5x a soldier): open glass
##       cockpit with the pilot, walking legs, big rifle / shoulder missile pod / twin AA cannon + radar
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const D = preload("res://tools/art/vdetail.gd")
const VH = preload("res://tools/art/vehicles.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const SQ = preload("res://tools/art/g5_units_sq.gd")
const FIG = preload("res://tools/art/g5_units_fig.gd")
const U = preload("res://tools/art/units.gd")
const BI = preload("res://tools/art/faction_b_inf.gd")
const M = preload("res://tools/art/faction_m_lib.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const H = preload("res://tools/art/g6_lib.gd")
const S2 = preload("res://tools/art/g6_new_units.gd")
const SU = preload("res://tools/art/g6_new_suits.gd")

const YELLOW := Color8(206, 168, 52)
const HAZARD := Color8(40, 38, 34)
const POLE := Color8(70, 72, 70)
const FLAGPOLE := Color8(170, 170, 164)


static func build(out: Dictionary) -> void:
	H.bld(out, "a_company_hq", 3, 66, hq_a)
	H.bld(out, "b_company_hq", 3, 72, hq_b)
	H.bld(out, "m_company_hq", 3, 84, hq_m)
	H.bld(out, "a_exo_garage", 2, 60, exo_garage)
	S2.build(out)


static func _front(f: int, sd: Dictionary) -> bool:
	return (sd.n as Vector2).dot(K.AX[f]) > 0.5


## Team flag on a pole tip (same cloth as the FOB flag).
static func _flag(cv, tip: Vector2) -> void:
	cv.team = true
	for yy in 6:
		for xx in 10:
			var wave := int(1.2 * sin(xx * 0.8))
			cv.px(int(tip.x) + 1 + xx, int(tip.y) + yy + wave, Color(0.9, 0.9, 0.9) if yy < 3 else Color(0.72, 0.72, 0.72))
	cv.team = false
	cv.px(int(tip.x), int(tip.y) - 1, Color8(220, 200, 120))


# ---------------------------------------------------------------- Company HQs
static func hq_a(cv, o: Vector2, f: int) -> void:
	var wall := K.pal("a", "wall")
	var trim := K.pal("a", "trim")
	var slab := K.pal("a", "slab")
	var ps: Array = [[0, 0, 0, 1.45, 1.45, 2, slab, "slab"],
		[0.55, 0.6, 2, 0.8, 0.75, 0, P.mul(slab, 1.12), "mat"],
		[-0.45, -0.4, 2, 0.95, 0.85, 28, wall, "hq"], [-0.45, -0.4, 30, 0.85, 0.75, 3, K.pal("a", "roof"), "team"],
		[-0.85, -0.8, 33, 0.28, 0.22, 7, K.pal("a", "metal"), "box"],
		[0.95, -0.85, 2, 0.45, 0.5, 16, P.mul(wall, 0.94), "annex"], [0.95, -0.85, 18, 0.38, 0.42, 2, K.pal("a", "roof"), "box"],
		[1.05, 0.2, 2, 0.24, 0.17, 8, trim, "box"],
		[0.9, 1.05, 2, 0.26, 0.15, 7, trim, "veh"], [1.22, 1.05, 2, 0.1, 0.13, 5, P.mul(trim, 0.8), "veh"],
		[0.05, 1.05, 2, 0.03, 0.03, 46, FLAGPOLE, "pole"], [-1.25, -1.15, 33, 0.03, 0.03, 28, POLE, "pole"]]
	for i in 5:  # sandbag revetment along the -v side of the pad
		ps.append([-0.2 + i * 0.3, 1.32, 2, 0.13, 0.08, 5, P.mul(Color8(150, 134, 98), 0.94 + 0.03 * (i % 2)), "bags"])
	K.render(cv, o, f, ps, 1.0, false, func(c, oo, ff, p, r): _dress_hq(c, oo, ff, p, r, "a"))
	K.gquad(cv, o, f, 0.0, 0.5, 0.06, 1.3, 2.1, K.pal("a", "mark"))  # walkway to the door
	var tip := K.pt(o, f, 0.05, 1.05, 46)
	_flag(cv, tip)
	var mt := K.pt(o, f, -1.25, -1.15, 61)
	cv.line_v(mt + Vector2(-3, 3), mt + Vector2(3, 3), POLE)
	K.lamp(cv, mt + Vector2(0, -1), Color8(238, 64, 48))
	var dc := K.pt(o, f, -0.05, -0.85, 34)  # satellite dish on the roof
	cv.ellipse(dc.x, dc.y - 4, 5.0, 3.5, Color8(196, 198, 190))
	cv.ellipse(dc.x + 1, dc.y - 4, 3.6, 2.4, Color8(160, 164, 158))
	cv.line_v(dc, dc + Vector2(0, -3), POLE)
	cv.line_v(dc + Vector2(1, -4), dc + Vector2(4, -9), POLE)
	cv.px(int(dc.x) + 4, int(dc.y) - 10, Color8(230, 230, 220))


static func hq_b(cv, o: Vector2, f: int) -> void:
	var wall := K.pal("b", "wall")
	var trim := K.pal("b", "trim")
	var slab := K.pal("b", "slab")
	var ps: Array = [[0, 0, 0, 1.45, 1.45, 2, slab, "slab"],
		[0.6, 0.55, 2, 0.75, 0.8, 0, P.mul(slab, 1.1), "mat"],
		[-0.4, -0.35, 2, 1.0, 0.85, 24, wall, "hq"], [-0.4, -0.35, 26, 1.02, 0.87, 15, Color8(110, 64, 50), "tent"],
		[1.0, -1.0, 2, 0.2, 0.2, 36, P.mul(wall, 0.9), "tower"], [1.0, -1.0, 38, 0.27, 0.27, 4, Color8(70, 66, 60), "box"],
		[1.0, 0.6, 2, 0.32, 0.26, 13, K.pal("b", "canvas"), "tent"],
		[0.2, 1.05, 2, 0.25, 0.13, 7, trim, "veh"], [0.52, 1.05, 2, 0.09, 0.12, 5, P.mul(trim, 0.8), "veh"],
		[0.6, 0.12, 2, 0.03, 0.03, 42, FLAGPOLE, "pole"], [-1.25, 0.95, 2, 0.03, 0.03, 50, POLE, "pole"]]
	K.render(cv, o, f, ps, 1.0, false, func(c, oo, ff, p, r): _dress_hq(c, oo, ff, p, r, "b"))
	var tip := K.pt(o, f, 0.6, 0.12, 42)
	_flag(cv, tip)
	var mt := K.pt(o, f, -1.25, 0.95, 52)
	var eave := K.pt(o, f, -1.2, -0.35, 33)
	B.cable(cv, mt, eave, 3.0, Color8(40, 38, 34))  # long-wire aerial to the roof
	cv.line_v(mt + Vector2(-2, 2), mt + Vector2(2, 2), POLE)
	var tw := K.pt(o, f, 1.0, -1.0, 42)
	cv.line_v(tw, tw + Vector2(0, -8), POLE)
	K.lamp(cv, tw + Vector2(0, -9), Color8(240, 200, 80))


static func hq_m(cv, o: Vector2, f: int) -> void:
	for e in [[1.05, -0.9], [-1.1, 0.75], [1.0, 1.0]]:  # glowing conduits from the core to each pylon
		K.gline(cv, o, f, 0.0, 0.0, e[0], e[1], 3.2, M.TEAL)
	var ps: Array = [[0, 0, 0, 1.45, 1.45, 3, M.SLAB, "slab"],
		[0, 0, 3, 1.0, 0, 14, M.GRAPH, "hex"], [0, 0, 17, 0.64, 0, 18, M.GRAPH_D, "hex"],
		[0, 0, 35, 0.38, 0, 8, M.PANEL, "hex"], [0, 0, 43, 0.03, 0.03, 24, M.PANEL, "pole"],
		[1.05, -0.9, 3, 0.17, 0, 30, M.GRAPH_D, "hex"], [-1.1, 0.75, 3, 0.17, 0, 26, M.GRAPH_D, "hex"],
		[1.0, 1.0, 3, 0.15, 0, 22, M.GRAPH_D, "hex"]]
	K.render(cv, o, f, ps, 1.0, false, func(c, oo, ff, p, r): _dress_hq(c, oo, ff, p, r, "m"))
	for e in [[1.05, -0.9, 34], [-1.1, 0.75, 30], [1.0, 1.0, 26]]:
		var t := K.pt(o, f, e[0], e[1], e[2])
		cv.px(int(t.x), int(t.y), M.CYAN_HOT)
		cv.px(int(t.x), int(t.y) + 1, M.CYAN)
	var sp := K.pt(o, f, 0, 0, 67)
	cv.px(int(sp.x), int(sp.y), M.CYAN_HOT)
	for i in 28:  # holo command ring around the crown
		var a := i * TAU / 28.0
		var q := K.pt(o, f, cos(a) * 0.55, sin(a) * 0.55, 46)
		cv.px(int(q.x), int(q.y), Color(M.CYAN.r, M.CYAN.g, M.CYAN.b, 0.75 if i % 2 == 0 else 0.4))


static func _dress_hq(cv, o: Vector2, f: int, p: Array, r: Dictionary, fk: String) -> void:
	var role := String(p[7])
	var col: Color = p[6]
	match role:
		"hq", "annex":
			var n := 0
			for sd in r.sides:
				if role == "hq":
					B.window_row(cv, sd.quad, 0.2, 0.36, 4, col, 611 + n)
					B.window_row(cv, sd.quad, 0.58 if fk == "a" else 0.55, 0.74, 4, col, 621 + n)
				else:
					B.window_row(cv, sd.quad, 0.4, 0.62, 2, col, 631 + n)
				if _front(f, sd) and role == "hq":
					B.door(cv, sd.quad, 0.42, 0.58, 0.42, col)
					if fk == "b":  # regimental banner over the door
						cv.team = true
						cv.poly(P.sub(sd.quad, 0.44, 0.48, 0.56, 0.95), Color(0.74, 0.74, 0.74))
						cv.team = false
					else:  # entrance canopy
						cv.poly(P.sub(sd.quad, 0.36, 0.38, 0.64, 0.46), P.mul(col, 0.7))
				n += 1
		"tower":
			for sd in r.sides:
				B.window_row(cv, sd.quad, 0.08, 0.2, 1, col, 641)
		"bags":
			for sd in r.sides:
				cv.line_v(P.sub(sd.quad, 0, 0.5, 1, 0.5)[0], P.sub(sd.quad, 0, 0.5, 1, 0.5)[1], P.mul(col, 0.8))
		"hex":
			if not r.has("top") or (r.top as PackedVector2Array).size() < 6:
				return
			var t: PackedVector2Array = r.top
			var c := (t[0] + t[3]) * 0.5
			var rad := float(p[3])
			if rad > 0.9 or (rad < 0.2 and float(p[5]) > 25.0):
				cv.team = true
				cv.poly(PackedVector2Array([t[0].lerp(c, 0.3), t[1].lerp(c, 0.3), t[2].lerp(c, 0.3)]), Color(0.75, 0.75, 0.75))
				cv.team = false
			if rad > 0.3 and rad < 0.9:
				M.eye(cv, c, true)
			for sd in r.sides:
				M.seam(cv, sd.quad, 0.5)
				if rad > 0.5 and rad < 0.9:
					M.seam(cv, sd.quad, 0.25)


# ---------------------------------------------------------------- Exo-suit garage
static func exo_garage(cv, o: Vector2, f: int) -> void:
	var wall := K.pal("a", "wall")
	var ps0: Array = [[0, 0, 0, 0.95, 0.95, 2, K.pal("a", "slab"), "slab"],
		[0.45, 0.45, 2, 0.45, 0.45, 0, Color8(96, 96, 90), "mat"]]
	K.render(cv, o, f, ps0, 1.0, false, Callable())
	for i in 9:  # hazard stripes round the work pad
		var u := 0.02 + i * 0.1
		K.gquad(cv, o, f, u, 0.02, u + 0.05, 0.08, 2.1, YELLOW if i % 2 == 0 else HAZARD)
		K.gquad(cv, o, f, 0.02, u, 0.08, u + 0.05, 2.1, YELLOW if i % 2 == 0 else HAZARD)
	var ps: Array = [[-0.3, -0.3, 2, 0.6, 0.6, 38, wall, "garage"], [-0.3, -0.3, 40, 0.53, 0.53, 3, K.pal("a", "roof"), "team"],
		[-0.55, -0.55, 43, 0.12, 0.12, 4, K.pal("a", "metal"), "box"],
		[0.75, -0.72, 2, 0.11, 0.11, 15, K.pal("a", "metal"), "cyl"],
		[0.85, 0.06, 2, 0.03, 0.03, 40, YELLOW, "pole"], [0.85, 0.86, 2, 0.03, 0.03, 40, YELLOW, "pole"],
		[-0.75, 0.75, 2, 0.13, 0.1, 6, K.pal("a", "trim"), "box"], [-0.5, 0.8, 2, 0.1, 0.09, 5, P.mul(K.pal("a", "trim"), 0.9), "box"]]
	var pad := K.wp(f, 0.45, 0.45)
	var shed := K.wp(f, -0.3, -0.3)
	var suit_first := pad.x + pad.y < shed.x + shed.y
	if suit_first:
		_parked_suit(cv, o, f)
	K.render(cv, o, f, ps, 1.0, false, func(c, oo, ff, p, r): _dress_garage(c, oo, ff, p, r))
	if not suit_first:
		_parked_suit(cv, o, f)
	var a := K.pt(o, f, 0.85, 0.06, 42)
	var b := K.pt(o, f, 0.85, 0.86, 42)
	for t in [0, 1]:  # gantry beam + hoist cable
		cv.line_v(a + Vector2(0, t), b + Vector2(0, t), P.mul(YELLOW, 1.0 - 0.25 * t))
	var hk := a.lerp(b, 0.5)
	cv.line_v(hk, hk + Vector2(0, 6), Color8(40, 40, 38))
	var ch := K.pt(o, f, 0.75, -0.72, 17)
	B.cable(cv, ch, K.pt(o, f, 0.45, 0.25, 8), 4.0, Color8(36, 36, 34))
	cv.px(int(ch.x), int(ch.y) - 1, Color8(120, 236, 120))


## An a_exo_rifle suit standing on the work pad, facing out of the garage (rotation f's +v).
static func _parked_suit(cv, o: Vector2, f: int) -> void:
	var sc = P.Canvas.new(cv.w, cv.h)
	var po := K.pt(o, f, 0.45, 0.45, 2)
	var dv: Vector2 = (K.AX[f] as Vector2) + K.pp(f)
	SU.suit(sc, atan2(dv.y, dv.x), 0, false, po, "rifle")
	SL.stamp(cv, sc, 0, 0)


static func _dress_garage(cv, o: Vector2, f: int, p: Array, r: Dictionary) -> void:
	if String(p[7]) != "garage":
		return
	var col: Color = p[6]
	for sd in r.sides:
		if _front(f, sd) or (sd.n as Vector2).dot(K.pp(f)) > 0.5:
			B.rollup(cv, sd.quad, 0.18, 0.82, 0.78, 0.35 if _front(f, sd) else 0.0, 651)
			cv.poly(P.sub(sd.quad, 0.12, 0.08, 0.88, 0.16), YELLOW)
		else:
			B.window_row(cv, sd.quad, 0.12, 0.26, 3, col, 661)
