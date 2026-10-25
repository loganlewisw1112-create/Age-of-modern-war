extends RefCounted
## G5 Machine craft (agent ART-NAV), graphite with cyan seams and sensor eyes, team panels:
##   m_hydro_skiff     sleek wedge hull; `move` rises on two foil struts (hull clear of the water,
##                     spray at the foils), twin pulse guns (cyan muzzle glow)
##   m_amphib_crawler  tracked amphibious carrier: idle / move / fire / ramp_half / unload on land (ground
##                     shadow, tracks), swim / swim_move afloat (tracks under water, wake foam); wreck on land
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const N = preload("res://tools/art/g5_naval_lib.gd")
const S = preload("res://tools/art/g5_naval_sheet.gd")
const K = preload("res://tools/art/g5_naval_parts.gd")
const ML = preload("res://tools/art/faction_m_lib.gd")

const TRACK := Color8(40, 42, 44)
const SHAPE := {
	"m_hydro_skiff": {"L": 0.58, "B": 0.15, "bow": 1.0, "F": 3.5, "H": 20.0, "depth": 12.0},
	"m_amphib_crawler": {"L": 0.75, "B": 0.28, "bow": 0.35, "F": 8.0, "H": 24.0, "depth": 18.0,
		"wreck_sink": -3.0},
}
const LIFT := 4.0     # skiff hull height above the water on its foils (move)
const RAISE := 3.0    # crawler hull bottom above ground (tracks below)
const SWIM := 4.0     # crawler hull depth afloat


static func build(out: Dictionary) -> void:
	S.ship_sheet(out, "m_hydro_skiff", SHAPE.m_hydro_skiff, skiff, ["idle", "move", "fire"])
	S.ship_sheet(out, "m_amphib_crawler", SHAPE.m_amphib_crawler, crawler,
		["idle", "move", "fire", "ramp_half", "unload", "swim", "swim_move"])


static func pc(name: String) -> Callable:
	return Callable(K, name)


## Graphite hull with a cyan seam along every visible side and a team panel amidships.
static func shell(cv, o: Vector2, rot: float, sh: Dictionary, st: Dictionary, sink: float, s: int) -> Dictionary:
	var hc := N.pal(ML.GRAPH, st)
	var h := N.hull(cv, o, rot, sh, hc, N.pal(ML.GRAPH_D, st), sink, s)
	for sd in h.sides:
		var q: PackedVector2Array = sd.quad
		ML.seam(cv, q, 0.55, not N.live(st))
		cv.line_v(q[3], q[2], P.mul(hc, 1.3))
		if absf((sd.n as Vector2).dot(Vector2(cos(rot), sin(rot)))) < 0.5:
			S.band(cv, q, 0.35, 0.65, 0.6, 0.92, st, hc)
	return h


# ---------------------------------------------------------------- m_hydro_skiff
static func skiff(cv, o: Vector2, rot: float, st: Dictionary) -> void:
	var sh: Dictionary = SHAPE.m_hydro_skiff
	var foil := N.live(st) and String(st.f) == "move"
	var st2: Dictionary = st.duplicate()
	if foil:
		st2.sink = -LIFT
	N.water(cv, o, rot, sh, st)
	var cx := K.ctx(cv, o, rot, st2)
	var fz: float = sh.F
	if foil:  # struts + foils, drawn before the hull so the hull overlaps their tops
		for f: float in [0.34, -0.4]:
			for s: float in [-1.0, 1.0]:
				var a := D.sp(o, rot, f, s * 0.08, LIFT)
				var b := D.sp(o, rot, f, s * 0.1, 0.0)
				cv.line_v(a, b, ML.GRAPH_D)
			cv.line_v(D.sp(o, rot, f, -0.13, 0.0), D.sp(o, rot, f, 0.13, 0.0), ML.TEAL)
	shell(cv, o, rot, sh, st2, float(st2.sink), 3101)
	N.draw_parts(rot, [
		[-0.06, 0.0, pc("house").bind(cx, -0.06, 0.0, fz, 0.18, 0.09, 4.0, ML.GRAPH, "m", true, 3102, true)],
		[0.26, 0.0, pc("turret").bind(cx, 0.26, 0.0, fz, 0.05, 0.05, 2.5, ML.GRAPH, 0.0, 0.16, 1.5, 2, 0.04, "m", 3103)],
		[-0.22, 0.0, pc("mast").bind(cx, -0.22, fz + 4.0, 6.0, ML.GRAPH_D, "bar")],
	])
	S.finish(cv, o, rot, sh, st, cx.tips, cx.hot, "cyan")
	if foil:
		for f: float in [0.34, -0.4]:
			for s: float in [-1.0, 1.0]:
				var p := D.sp(o, rot, f - 0.05, s * 0.12, 1.0)
				cv.ellipse(p.x, p.y, 1.6, 1.0, Color(N.FOAM.r, N.FOAM.g, N.FOAM.b, 0.8))


# ---------------------------------------------------------------- m_amphib_crawler
static func crawler(cv, o: Vector2, rot: float, st: Dictionary) -> void:
	var sh: Dictionary = SHAPE.m_amphib_crawler
	var f := String(st.f)
	var afloat := f.begins_with("swim") or int(st.stage) >= 0
	var st2: Dictionary = st.duplicate()
	if afloat:
		st2.sink = maxf(float(st.sink), SWIM)
		N.water(cv, o, rot, sh, st)
	else:
		st2.sink = -RAISE
		P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 0.0), sh.L, sh.B + 0.04, sh.F + RAISE, rot)
		cv.flush_shadow()
	var sink: float = st2.sink
	var cx := K.ctx(cv, o, rot, st2)
	var fz: float = sh.F
	var ax := Vector2(cos(rot), sin(rot))
	for s: float in [-1.0, 1.0]:  # tracks (only the parts above the water show when afloat)
		if D.faces_cam(rot, 0.0, s):
			continue
		var tr := N.zbox(cv, o, rot, 0.0, s * 0.27, 0.0, 0.68, 0.06, 7.0, N.pal(TRACK, st), sink, 3200 + int(s))
		if tr.is_empty() or afloat:
			continue
		for sd in tr.sides:
			if absf((sd.n as Vector2).dot(ax)) < 0.3:
				D.track_side(cv, sd.quad, 1 if f == "move" else 0, not N.live(st), 7)
	shell(cv, o, rot, sh, st2, sink, 3201)
	for s: float in [-1.0, 1.0]:  # near-side track over the hull skirt
		if not D.faces_cam(rot, 0.0, s):
			continue
		var tr := N.zbox(cv, o, rot, 0.0, s * 0.27, 0.0, 0.68, 0.06, 7.0, N.pal(TRACK, st), sink, 3200 + int(s))
		if tr.is_empty() or afloat:
			continue
		for sd in tr.sides:
			if absf((sd.n as Vector2).dot(ax)) < 0.3:
				D.track_side(cv, sd.quad, 1 if f == "move" else 0, not N.live(st), 7)
	N.draw_parts(rot, [
		[0.12, 0.0, pc("house").bind(cx, 0.12, 0.0, fz, 0.42, 0.17, 1.5, ML.PANEL_D, "m", false, 3205)],
		[-0.46, 0.0, pc("house").bind(cx, -0.46, 0.0, fz, 0.16, 0.2, 6.0, ML.GRAPH, "m", true, 3202, true)],
		[-0.44, 0.08, pc("turret").bind(cx, -0.44, 0.08, fz + 6.0, 0.04, 0.04, 2.5, ML.GRAPH, 0.0, 0.16, 1.5, 1, 0.0, "m", 3203)],
		[-0.5, -0.1, pc("mast").bind(cx, -0.5, fz + 6.0, 6.0, ML.GRAPH_D, "bar")],
		[0.73, 0.0, Callable(S, "ramp").bind(cv, o, rot, 0.72, 0.24, 1.0 + (0.0 if afloat else RAISE), 0.28,
			fz - 1.0, st2, N.pal(ML.PANEL_D, st), 3204)],
	])
	S.finish(cv, o, rot, sh, st, cx.tips, cx.hot, "cyan", 0.0, afloat)
	if not afloat and N.live(st) and f == "move":  # track dust
		for s: float in [-1.0, 1.0]:
			var p := D.sp(o, rot, -0.74, s * 0.22, 1.0)
			cv.ellipse(p.x, p.y, 2.2, 1.4, Color(0.62, 0.56, 0.44, 0.45))
