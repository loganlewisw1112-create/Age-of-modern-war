extends RefCounted
## G5 Human A ships (agent ART-NAV), modern haze grey with a red boot-topping, glazed bridges, team
## bands on funnels / wheelhouses:
##   a_patrol_boat    fast patrol craft: wheelhouse + radar mast, bow autocannon, twin MG aft
##   a_landing_craft  LCM: open well deck between gunwales, stern wheelhouse, hinged bow ramp
##                    (frames ramp_half / unload = ramp down onto the beach)
##   a_destroyer      bow gun, VLS block, two-tier bridge, mast with arrays, funnel, hangar + CIWS, helipad
##   a_aa_frigate     SAM launchers fore and aft, tall radar tower with array faces, two CIWS domes
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const N = preload("res://tools/art/g5_naval_lib.gd")
const S = preload("res://tools/art/g5_naval_sheet.gd")
const K = preload("res://tools/art/g5_naval_parts.gd")

const HULL := Color8(118, 126, 132)
const DECK := Color8(86, 92, 96)
const SUPER := Color8(152, 158, 162)
const BOOT := Color8(104, 42, 38)
const PAINT := Color8(222, 222, 214)
const SHAPE := {
	"a_patrol_boat": {"L": 0.62, "B": 0.16, "bow": 1.0, "F": 4.0, "H": 22.0, "depth": 16.0},
	"a_landing_craft": {"L": 0.8, "B": 0.3, "bow": 0.18, "F": 6.0, "H": 22.0, "depth": 18.0},
	"a_destroyer": {"L": 1.25, "B": 0.21, "bow": 1.0, "F": 7.0, "H": 36.0, "depth": 30.0},
	"a_aa_frigate": {"L": 1.05, "B": 0.2, "bow": 1.0, "F": 7.0, "H": 36.0, "depth": 30.0},
}


static func build(out: Dictionary) -> void:
	S.ship_sheet(out, "a_patrol_boat", SHAPE.a_patrol_boat, patrol, ["idle", "move", "fire"])
	S.ship_sheet(out, "a_landing_craft", SHAPE.a_landing_craft, landing, ["idle", "move", "fire", "ramp_half", "unload"])
	S.ship_sheet(out, "a_destroyer", SHAPE.a_destroyer, destroyer, ["idle", "move", "fire"])
	S.ship_sheet(out, "a_aa_frigate", SHAPE.a_aa_frigate, frigate, ["idle", "move", "fire"])


static func pc(name: String) -> Callable:
	return Callable(K, name)


## Hull + boot-topping + lit deck edge. Returns the hull dict.
static func base(cv, o: Vector2, rot: float, sh: Dictionary, st: Dictionary, s: int) -> Dictionary:
	N.water(cv, o, rot, sh, st)
	var hc := N.pal(HULL, st)
	var h := N.hull(cv, o, rot, sh, hc, N.pal(DECK, st), float(st.sink), s)
	for sd in h.sides:
		var q: PackedVector2Array = sd.quad
		if float(st.sink) <= 0.0:
			cv.poly(P.sub(q, 0.0, 0.0, 1.0, 0.26), N.pal(BOOT, st))
		cv.line_v(q[3], q[2], P.mul(hc, 1.22))
	return h


## Painted circle (+ H) on the deck at local (f, 0), radius rt tiles, at deck height zt.
static func helipad(cv, o: Vector2, rot: float, f: float, rt: float, zt: float, st: Dictionary) -> void:
	if zt <= 0.5:
		return
	var col := N.pal(PAINT, st)
	var prev := Vector2.ZERO
	for i in 17:
		var a := i * TAU / 16.0
		var p := D.sp(o, rot, f + cos(a) * rt, sin(a) * rt, zt)
		if i > 0:
			cv.line_v(prev, p, col)
		prev = p
	cv.line_v(D.sp(o, rot, f - rt * 0.45, -rt * 0.35, zt), D.sp(o, rot, f + rt * 0.45, -rt * 0.35, zt), col)
	cv.line_v(D.sp(o, rot, f - rt * 0.45, rt * 0.35, zt), D.sp(o, rot, f + rt * 0.45, rt * 0.35, zt), col)
	cv.line_v(D.sp(o, rot, f, -rt * 0.35, zt), D.sp(o, rot, f, rt * 0.35, zt), col)


# ---------------------------------------------------------------- a_patrol_boat
static func patrol(cv, o: Vector2, rot: float, st: Dictionary) -> void:
	var sh: Dictionary = SHAPE.a_patrol_boat
	var cx := K.ctx(cv, o, rot, st)
	var fz: float = sh.F
	base(cv, o, rot, sh, st, 1101)
	N.draw_parts(rot, [
		[-0.08, 0.0, pc("house").bind(cx, -0.08, 0.0, fz, 0.17, 0.11, 6.0, SUPER, "a", true, 1102, true)],
		[-0.12, 0.0, pc("mast").bind(cx, -0.12, fz + 6.0, 9.0, SUPER, "bar")],
		[0.36, 0.0, pc("turret").bind(cx, 0.36, 0.0, fz, 0.045, 0.045, 2.5, SUPER, 0.0, 0.2, 1.5, 1, 0.0, "a", 1103)],
		[-0.44, 0.0, pc("turret").bind(cx, -0.44, 0.0, fz, 0.035, 0.05, 2.0, SUPER, PI, 0.12, 1.0, 2, 0.05, "a", 1104)],
	])
	S.finish(cv, o, rot, sh, st, cx.tips, cx.hot)


# ---------------------------------------------------------------- a_landing_craft
static func landing(cv, o: Vector2, rot: float, st: Dictionary) -> void:
	var sh: Dictionary = SHAPE.a_landing_craft
	var cx := K.ctx(cv, o, rot, st)
	var fz: float = sh.F
	var h := base(cv, o, rot, sh, st, 1201)
	var zt: float = h.zt
	if zt > 0.5:  # tie-down rails on the well floor
		for rr: float in [-0.12, 0.0, 0.12]:
			cv.line_v(D.sp(o, rot, -0.42, rr, zt), D.sp(o, rot, 0.66, rr, zt), N.pal(Color8(74, 78, 82), st))
	var parts := [
		[0.1, -0.27, pc("house").bind(cx, 0.08, -0.27, fz, 0.6, 0.03, 4.0, HULL, "a", false, 1202)],
		[0.1, 0.27, pc("house").bind(cx, 0.08, 0.27, fz, 0.6, 0.03, 4.0, HULL, "a", false, 1203)],
		[-0.64, 0.0, pc("house").bind(cx, -0.64, 0.0, fz, 0.13, 0.2, 9.0, SUPER, "a", true, 1204, true)],
		[-0.68, 0.0, pc("mast").bind(cx, -0.68, fz + 9.0, 7.0, SUPER, "bar")],
		[-0.58, 0.12, pc("turret").bind(cx, -0.58, 0.12, fz + 9.0, 0.03, 0.03, 2.0, SUPER, 0.0, 0.12, 1.0, 1, 0.0, "a", 1205)],
		[0.78, 0.0, Callable(S, "ramp").bind(cv, o, rot, 0.77, 0.25, 1.0, 0.27, 10.0, st, N.pal(HULL, st), 1206)],
	]
	N.draw_parts(rot, parts)
	S.finish(cv, o, rot, sh, st, cx.tips, cx.hot)


# ---------------------------------------------------------------- a_destroyer
static func destroyer(cv, o: Vector2, rot: float, st: Dictionary) -> void:
	var sh: Dictionary = SHAPE.a_destroyer
	var cx := K.ctx(cv, o, rot, st)
	var fz: float = sh.F
	var h := base(cv, o, rot, sh, st, 1301)
	helipad(cv, o, rot, -1.02, 0.13, float(h.zt), st)
	N.draw_parts(rot, [
		[0.7, 0.0, pc("turret").bind(cx, 0.7, 0.0, fz, 0.09, 0.08, 4.0, SUPER, 0.0, 0.32, 2.0, 1, 0.0, "a", 1302)],
		[0.48, 0.0, pc("launcher").bind(cx, 0.48, 0.0, fz, 0.08, 0.1, 1.5, DECK, 4, 1303)],
		[0.16, 0.0, pc("house").bind(cx, 0.16, 0.0, fz, 0.2, 0.16, 10.0, SUPER, "a", false, 1304)],
		[0.2, 0.01, pc("house").bind(cx, 0.2, 0.0, fz + 10.0, 0.1, 0.11, 4.0, SUPER, "a", false, 1305, true)],
		[0.08, 0.02, pc("house").bind(cx, 0.08, 0.0, fz + 14.0, 0.05, 0.05, 6.0, SUPER, "a", false, 1306)],
		[0.08, 0.03, pc("mast").bind(cx, 0.08, fz + 20.0, 10.0, SUPER, "array")],
		[-0.28, 0.0, pc("funnel").bind(cx, -0.28, 0.0, fz, 0.1, 0.08, 12.0, SUPER, "a", true, 1307)],
		[-0.62, 0.0, pc("house").bind(cx, -0.62, 0.0, fz, 0.22, 0.17, 8.0, SUPER, "a", false, 1308)],
		[-0.52, 0.01, pc("dome").bind(cx, -0.52, 0.0, fz + 8.0, PI, 1309)],
	])
	S.finish(cv, o, rot, sh, st, cx.tips, cx.hot)
	if N.live(st) and String(st.f) == "fire":
		K.plumes(cx)


# ---------------------------------------------------------------- a_aa_frigate
static func frigate(cv, o: Vector2, rot: float, st: Dictionary) -> void:
	var sh: Dictionary = SHAPE.a_aa_frigate
	var cx := K.ctx(cv, o, rot, st)
	var fz: float = sh.F
	base(cv, o, rot, sh, st, 1401)
	N.draw_parts(rot, [
		[0.66, 0.0, pc("turret").bind(cx, 0.66, 0.0, fz, 0.07, 0.065, 3.5, SUPER, 0.0, 0.22, 2.0, 1, 0.0, "a", 1402)],
		[0.44, 0.0, pc("launcher").bind(cx, 0.44, 0.0, fz, 0.07, 0.11, 4.0, Color8(96, 102, 106), 4, 1403)],
		[0.04, 0.0, pc("house").bind(cx, 0.04, 0.0, fz, 0.3, 0.17, 10.0, SUPER, "a", false, 1404)],
		[0.1, 0.01, pc("house").bind(cx, 0.1, 0.0, fz + 10.0, 0.13, 0.12, 6.0, SUPER, "a", false, 1405)],
		[0.0, 0.02, pc("house").bind(cx, 0.0, 0.0, fz + 16.0, 0.07, 0.07, 8.0, Color8(128, 136, 142), "a", true, 1406, true)],
		[0.0, 0.03, pc("mast").bind(cx, 0.0, fz + 24.0, 8.0, SUPER, "array")],
		[0.3, 0.0, pc("dome").bind(cx, 0.3, 0.0, fz + 10.0, 0.0, 1407)],
		[-0.26, 0.0, pc("funnel").bind(cx, -0.26, 0.0, fz, 0.08, 0.09, 9.0, SUPER, "a", false, 1408)],
		[-0.56, 0.0, pc("house").bind(cx, -0.56, 0.0, fz, 0.16, 0.15, 6.0, SUPER, "a", false, 1409)],
		[-0.52, 0.01, pc("dome").bind(cx, -0.52, 0.0, fz + 6.0, PI, 1410)],
		[-0.84, 0.0, pc("launcher").bind(cx, -0.84, 0.0, fz, 0.07, 0.1, 4.0, Color8(96, 102, 106), 4, 1411)],
	])
	S.finish(cv, o, rot, sh, st, cx.tips, cx.hot)
	if N.live(st) and String(st.f) == "fire":
		K.plumes(cx)
