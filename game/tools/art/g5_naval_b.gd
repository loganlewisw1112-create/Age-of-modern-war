extends RefCounted
## G5 Human B ships (agent ART-NAV), riveted industrial: dark weathered steel with rivet rows, a rust
## waterline, rust streaks, plank decks, soot-blackened stacks, team pennant / turret bands:
##   b_river_gunboat  riveted river boat: armoured pilot house, bow gun turret, tall stack, aft MG
##   b_barge_carrier  flat riveted barge with tarped cargo, pusher-tug wheelhouse aft, hinged bow ramp
##                    (frames ramp_half / unload)
##   b_monitor        low-freeboard monitor: big twin-gun turret fore, single turret aft, conning tower
##                    with spotting top, fat stack
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const N = preload("res://tools/art/g5_naval_lib.gd")
const S = preload("res://tools/art/g5_naval_sheet.gd")
const K = preload("res://tools/art/g5_naval_parts.gd")
const FB = preload("res://tools/art/faction_b_veh.gd")

const HULL := Color8(92, 86, 76)
const DECK := Color8(116, 94, 64)
const SUPER := Color8(110, 100, 84)
const STACK := Color8(72, 66, 60)
const TARP := Color8(96, 102, 70)
const SHAPE := {
	"b_river_gunboat": {"L": 0.7, "B": 0.2, "bow": 0.8, "F": 4.5, "H": 28.0, "depth": 18.0},
	"b_barge_carrier": {"L": 0.95, "B": 0.32, "bow": 0.1, "F": 5.0, "H": 30.0, "depth": 22.0},
	"b_monitor": {"L": 1.2, "B": 0.3, "bow": 0.7, "F": 4.0, "H": 38.0, "depth": 26.0},
}


static func build(out: Dictionary) -> void:
	S.ship_sheet(out, "b_river_gunboat", SHAPE.b_river_gunboat, gunboat, ["idle", "move", "fire"])
	S.ship_sheet(out, "b_barge_carrier", SHAPE.b_barge_carrier, barge, ["idle", "move", "fire", "ramp_half", "unload"])
	S.ship_sheet(out, "b_monitor", SHAPE.b_monitor, monitor, ["idle", "move", "fire"])


static func pc(name: String) -> Callable:
	return Callable(K, name)


## Riveted hull: rust waterline, two rivet rows, rust streaks, plank seams on the deck.
static func base(cv, o: Vector2, rot: float, sh: Dictionary, st: Dictionary, s: int) -> Dictionary:
	N.water(cv, o, rot, sh, st)
	var hc := N.pal(HULL, st)
	var h := N.hull(cv, o, rot, sh, hc, N.pal(DECK, st), float(st.sink), s)
	for sd in h.sides:
		var q: PackedVector2Array = sd.quad
		if float(st.sink) <= 0.0:
			cv.poly(P.sub(q, 0.0, 0.0, 1.0, 0.24), N.pal(FB.RUST, st), P.speckle(0.2, s + 9))
		var nr := maxi(3, int(q[0].distance_to(q[1]) / 3.0))
		FB.rivets(cv, q, 0.82, nr, hc)
		FB.rivets(cv, q, 0.45, nr, hc)
		FB.streaks(cv, q, s + 11, 0.8)
		cv.line_v(q[3], q[2], P.mul(hc, 1.25))
	var zt: float = h.zt
	if zt > 0.5:
		for rr: float in [-0.5, 0.0, 0.5]:
			var r: float = rr * float(sh.B) * 0.8
			cv.line_v(D.sp(o, rot, -float(sh.L) * 0.9, r, zt), D.sp(o, rot, float(sh.L) * 0.55, r, zt),
				P.mul(N.pal(DECK, st), 0.8))
	return h


## Pennant on a short staff: team-coloured when live (masked), plain rag otherwise.
static func pennant(cx: Dictionary, f: float, z0: float, h: float) -> void:
	var top = N.mast(cx.cv, cx.o, cx.rot, f, z0, h, Color8(60, 56, 50), cx.sink, 0.0)
	if top == null:
		return
	var cv = cx.cv
	var q := PackedVector2Array([top, top + Vector2(6, 1), top + Vector2(5, 3), top + Vector2(0, 3)])
	if N.live(cx.st):
		cv.team = true
		cv.poly(q, Color(0.7, 0.7, 0.7))
		cv.team = false
	else:
		cv.poly(q, Color8(70, 60, 50))


# ---------------------------------------------------------------- b_river_gunboat
static func gunboat(cv, o: Vector2, rot: float, st: Dictionary) -> void:
	var sh: Dictionary = SHAPE.b_river_gunboat
	var cx := K.ctx(cv, o, rot, st)
	var fz: float = sh.F
	base(cv, o, rot, sh, st, 2101)
	N.draw_parts(rot, [
		[-0.08, 0.0, pc("house").bind(cx, -0.08, 0.0, fz, 0.16, 0.12, 7.0, SUPER, "b", true, 2102, true)],
		[0.38, 0.0, pc("turret").bind(cx, 0.38, 0.0, fz, 0.08, 0.08, 4.0, SUPER, 0.0, 0.24, 2.0, 1, 0.0, "b", 2103)],
		[-0.34, 0.0, pc("funnel").bind(cx, -0.34, 0.0, fz, 0.045, 0.045, 12.0, STACK, "b", false, 2104)],
		[-0.56, 0.0, pc("turret").bind(cx, -0.56, 0.0, fz, 0.06, 0.07, 2.0, Color8(140, 124, 92), PI, 0.1, 1.0, 1, 0.0, "b", 2105)],
		[-0.04, 0.01, pennant.bind(cx, -0.04, fz + 7.0, 9.0)],
	])
	S.finish(cv, o, rot, sh, st, cx.tips, cx.hot)


# ---------------------------------------------------------------- b_barge_carrier
static func barge(cv, o: Vector2, rot: float, st: Dictionary) -> void:
	var sh: Dictionary = SHAPE.b_barge_carrier
	var cx := K.ctx(cv, o, rot, st)
	var fz: float = sh.F
	base(cv, o, rot, sh, st, 2201)
	N.draw_parts(rot, [
		[0.1, -0.29, pc("house").bind(cx, 0.08, -0.29, fz, 0.72, 0.025, 3.0, HULL, "b", false, 2202)],
		[0.1, 0.29, pc("house").bind(cx, 0.08, 0.29, fz, 0.72, 0.025, 3.0, HULL, "b", false, 2203)],
		[0.22, -0.1, pc("house").bind(cx, 0.22, -0.1, fz, 0.13, 0.09, 4.0, TARP, "", false, 2204)],
		[0.0, 0.12, pc("house").bind(cx, 0.0, 0.12, fz, 0.1, 0.08, 3.0, TARP, "", false, 2205)],
		[-0.76, 0.0, pc("house").bind(cx, -0.76, 0.0, fz, 0.14, 0.2, 7.0, SUPER, "b", true, 2206)],
		[-0.78, 0.01, pc("house").bind(cx, -0.78, 0.0, fz + 7.0, 0.08, 0.12, 6.0, SUPER, "b", false, 2207, true)],
		[-0.86, 0.13, pc("funnel").bind(cx, -0.86, 0.13, fz, 0.04, 0.04, 17.0, STACK, "b", false, 2208)],
		[-0.72, 0.02, pc("turret").bind(cx, -0.72, 0.0, fz + 13.0, 0.03, 0.03, 2.0, SUPER, 0.0, 0.12, 1.0, 1, 0.0, "b", 2209)],
		[-0.8, -0.1, pennant.bind(cx, -0.8, fz + 13.0, 8.0)],
		[0.93, 0.0, Callable(S, "ramp").bind(cv, o, rot, 0.93, 0.28, 1.0, 0.3, 11.0, st, N.pal(HULL, st), 2210)],
	])
	S.finish(cv, o, rot, sh, st, cx.tips, cx.hot)


# ---------------------------------------------------------------- b_monitor
static func monitor(cv, o: Vector2, rot: float, st: Dictionary) -> void:
	var sh: Dictionary = SHAPE.b_monitor
	var cx := K.ctx(cv, o, rot, st)
	var fz: float = sh.F
	base(cv, o, rot, sh, st, 2301)
	N.draw_parts(rot, [
		[0.45, 0.0, pc("turret").bind(cx, 0.45, 0.0, fz, 0.2, 0.17, 8.0, SUPER, 0.0, 0.45, 3.0, 2, 0.1, "b", 2302, true)],
		[-0.05, 0.0, pc("house").bind(cx, -0.05, 0.0, fz, 0.14, 0.12, 14.0, SUPER, "b", false, 2303, true)],
		[-0.05, 0.01, pc("house").bind(cx, -0.05, 0.0, fz + 14.0, 0.08, 0.08, 4.0, SUPER, "b", false, 2304)],
		[-0.05, 0.02, pc("mast").bind(cx, -0.05, fz + 18.0, 10.0, STACK, "dish")],
		[-0.33, 0.0, pc("funnel").bind(cx, -0.33, 0.0, fz, 0.09, 0.09, 12.0, STACK, "b", false, 2305)],
		[-0.64, 0.0, pc("turret").bind(cx, -0.64, 0.0, fz, 0.15, 0.13, 7.0, SUPER, PI, 0.32, 2.0, 1, 0.0, "b", 2306, true)],
		[-0.9, 0.0, pennant.bind(cx, -0.92, fz, 12.0)],
	])
	S.finish(cv, o, rot, sh, st, cx.tips, cx.hot)

