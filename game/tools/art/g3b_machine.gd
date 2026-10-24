extends RefCounted
## G3b Machine (Autonomous Network) units (agent ART4), graphite + off-white panels, cyan emissive seams:
##   m_siege_crawler heavy tracked siege platform: armoured prow, big hex turret, coil siege mortar
##   m_swarm         drone swarm (air): six micro-drones in a loose formation that shifts per frame
##   m_ew_node       small tracked EW platform: hex body, mast with stacked emitter rings (fire = pulse)
##   m_lancer        precision rail walker (foot): two digitigrade legs, slim hex torso, long rail lance
## Wrecks are cold (no cyan), matching test_art_machine.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const MV = preload("res://tools/art/faction_m_veh.gd")
const MU = preload("res://tools/art/faction_m_units.gd")
const WK = preload("res://tools/art/faction_m_walker.gd")
const G = preload("res://tools/art/g3b_lib.gd")

const SPEC := {
	"m_siege_crawler": {"fw": 86, "fh": 62, "pivot": [43, 38]},
	"m_swarm": {"fw": 50, "fh": 40, "pivot": [25, 26]},
	"m_ew_node": {"fw": 48, "fh": 60, "pivot": [24, 42]},
	"m_lancer": {"fw": 72, "fh": 66, "pivot": [36, 50]},
}
## swarm drones: [fwd, right, z]
const SWARM := [[0.18, 0.0, 9.0], [0.02, -0.17, 6.0], [0.02, 0.17, 11.0], [-0.16, -0.07, 8.0], [-0.14, 0.13, 4.0], [-0.3, 0.0, 10.0]]
const OUTL := Color(0.07, 0.08, 0.09, 1)


static func build(out: Dictionary) -> void:
	G.sheet(out, "m_siege_crawler", SPEC.m_siege_crawler, siege_crawler)
	G.sheet(out, "m_swarm", SPEC.m_swarm, swarm, false, false)
	G.air(out, "m_swarm", 20, 2, G.shadow_blobs(40, 20, [[20, 10, 5.0, 2.6], [13, 8, 4.0, 2.0], [22, 6, 4.0, 2.0], [28, 11, 4.0, 2.0],
		[18, 13, 4.0, 2.0], [10, 13, 3.5, 1.8], [26, 15, 3.5, 1.8]]), [20, 10])
	G.sheet(out, "m_ew_node", SPEC.m_ew_node, ew_node)
	G.sheet(out, "m_lancer", SPEC.m_lancer, lancer, true)


static func _panels(cv, r: Dictionary, rot: float, hull: Color, wreck: bool, team: bool) -> void:
	for sd in r.sides:
		var long := absf((sd.n as Vector2).dot(Vector2(-sin(rot), cos(rot)))) > 0.7
		if long and team and not wreck:
			L.team_panel(cv, sd.quad, 0.1, 0.18, 0.62, 0.48)
		L.seam(cv, sd.quad, 0.72, wreck, 0.04, 0.96)
		L.joints(cv, sd.quad, [0.3, 0.65] if long else [0.5], hull)
	D.contact_ao(cv, r)
	L.rims(cv, r, hull)


# ---------------------------------------------------------------- m_siege_crawler
static func siege_crawler(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = L.DEAD if wreck else L.GRAPH
	var shell: Color = P.mul(L.DEAD, 1.15) if wreck else L.PANEL
	var trk: Color = Color8(36, 32, 30) if wreck else Color8(40, 43, 46)
	var trot := rot + (0.6 if wreck else 0.0)
	var t := [0.62, 0.3, 7.0]
	for s in [-1, 1]:
		P.box_shadow(cv, o, L.w(rot, 0, t[1] * s), t[0], 0.1, t[2], rot)
	P.box_shadow(cv, o, Vector3(0, 0, 5), 0.6, 0.38, 14.0, rot)
	cv.flush_shadow()
	var near_s := 1 if L.w(rot, 0, 1).x + L.w(rot, 0, 1).y > 0.0 else -1
	MV._track(cv, o, rot, t, -near_s, f, trk, wreck)
	MV._track(cv, o, rot, t, near_s, f, trk, wreck)
	var h: Dictionary = P.box(cv, o, Vector3(0, 0, 6), 0.58, 0.36, 7.0, rot, hull, 0.08, 1001)
	_panels(cv, h, rot, hull, wreck, true)
	var prow: Dictionary = P.box(cv, o, L.w(rot, 0.5, 0, 6), 0.12, 0.3, 4.0, rot, P.mul(hull, 0.85), 0.06, 1002)
	L.rims(cv, prow, hull)
	for s in [-1, 1]:  # rear reactor vents
		L.hex_plate(cv, h.top, 0.16, 0.5 + 0.28 * s, 3.0, L.GRAPH_D, not wreck)
	var toward := cos(trot) + sin(trot) > 0.0
	var tc := L.w(trot, 0.02, 0, 13)
	if not toward:
		_mortar(cv, o, trot, f, wreck)
	var tt: Dictionary = L.hexp(cv, o, tc, 0.27, 7.0, trot, shell, 1003, null, 0.85)
	for sd in tt.sides:
		if not wreck:
			L.team_panel(cv, sd.quad, 0.12, 0.35, 0.88, 0.78)
		L.seam(cv, sd.quad, 0.12, wreck)
	L.hex_plate(cv, tt.top, 0.6, 0.5, 3.5, L.GRAPH_D, not wreck)
	if wreck:
		WK._scorch(cv, tt.top)
	if toward:
		L.eye(cv, P.proj(o, L.w(trot, 0.24, -0.12, 17)), true, wreck)
		_mortar(cv, o, trot, f, wreck)
	else:
		var a := P.proj(o, L.w(trot, -0.15, 0.1, 20))
		cv.line_v(a, a + Vector2(0, -7), L.JOINT)
		if not wreck:
			cv.px(int(a.x), int(a.y) - 8, L.CYAN)
	cv.outline(OUTL)
	if f == 2 and not wreck:
		var tip := P.proj(o, L.w(trot, 0.62, 0, 21))
		cv.ellipse(tip.x, tip.y, 4.0, 3.0, Color(L.CYAN.r, L.CYAN.g, L.CYAN.b, 0.5))
		cv.ellipse(tip.x, tip.y, 2.0, 1.5, L.CYAN_HOT)


## Short, fat siege mortar with coil rings, angled up from the turret front.
static func _mortar(cv, o: Vector2, trot: float, f: int, wreck: bool) -> void:
	var col: Color = L.DEAD_D if wreck else L.GRAPH_D
	var back := 0.05 if f == 2 else 0.0
	for k in 4:
		var c := L.w(trot, 0.26 + k * 0.1 - back, 0, 15.5 + k * 1.6 - (6.0 if wreck else 0.0))
		P.box(cv, o, c, 0.06, 0.08, 3.4, trot, col, 0.04, 1005 + k)
		if not wreck and k < 3:
			var p := P.proj(o, c + Vector3(0, 0, 3.6))
			cv.px(int(p.x), int(p.y), L.CYAN)


# ---------------------------------------------------------------- m_swarm
static func swarm(cv, rot: float, f: int, _wreck: bool, o: Vector2) -> void:
	var ds: Array = []
	for i in SWARM.size():
		var d: Array = SWARM[i]
		var jx := (P.hn(i, f, 1011) - 0.5) * 0.08
		var jy := (P.hn(i, f, 1012) - 0.5) * 0.08
		var jz := (P.hn(i, f, 1013) - 0.5) * 3.0
		var c := L.w(rot, d[0] + jx, d[1] + jy, d[2] + jz)
		ds.append([c.x + c.y, c, i])
	ds.sort_custom(func(a, b): return a[0] < b[0])
	for it in ds:
		_micro(cv, o, rot, it[1], f, it[2])
	cv.outline(OUTL)
	for it in ds:  # rotor shimmer after the outline
		var p := P.proj(o, it[1] + Vector3(0, 0, 2.5))
		cv.ellipse(p.x, p.y, 3.4, 1.4, Color(0.78, 0.82, 0.84, 0.22))
	for it in ds:  # team-painted canopies last: the shimmer blend above clears mask pixels under it
		var tp := P.proj(o, it[1] + Vector3(0, 0, 2.0))
		cv.team = true
		cv.px(int(tp.x), int(tp.y), Color(0.82, 0.82, 0.82))
		cv.px(int(tp.x) - 1, int(tp.y), Color(0.7, 0.7, 0.7))
		cv.team = false
	if f == 2:
		var lead := P.proj(o, L.w(rot, 0.3, 0, 9))
		cv.ellipse(lead.x, lead.y, 1.8, 1.2, Color(1.0, 0.9, 0.6, 0.8))


static func _micro(cv, o: Vector2, rot: float, c: Vector3, f: int, i: int) -> void:
	L.hexp(cv, o, c, 0.055, 2.0, rot, L.GRAPH, 1015 + i, null, 0.8)
	cv.team = true
	L.hexp(cv, o, c + Vector3(0, 0, 2.0), 0.035, 0.0, rot, Color(0.78, 0.78, 0.78), 1017)
	cv.team = false
	var e := P.proj(o, c + L.w(rot, 0.05, 0, 1))
	cv.px(int(e.x), int(e.y), L.CYAN if (i + f) % 3 != 0 else L.CYAN_HOT)
	for s in [-1, 1]:
		var a := P.proj(o, c + L.w(rot, 0, 0.09 * s, 2))
		cv.px(int(a.x), int(a.y), L.JOINT)


# ---------------------------------------------------------------- m_ew_node
static func ew_node(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = L.DEAD if wreck else L.GRAPH
	var shell: Color = P.mul(L.DEAD, 1.15) if wreck else L.PANEL
	var trk: Color = Color8(36, 32, 30) if wreck else Color8(40, 43, 46)
	var t := [0.32, 0.17, 4.0]
	for s in [-1, 1]:
		P.box_shadow(cv, o, L.w(rot, 0, t[1] * s), t[0], 0.08, t[2], rot)
	L.hex_shadow(cv, o, Vector3(0, 0, 4), 0.22, 8.0, rot, 0.85)
	cv.flush_shadow()
	var near_s := 1 if L.w(rot, 0, 1).x + L.w(rot, 0, 1).y > 0.0 else -1
	MV._track(cv, o, rot, t, -near_s, f, trk, wreck)
	MV._track(cv, o, rot, t, near_s, f, trk, wreck)
	var b: Dictionary = L.hexp(cv, o, Vector3(0, 0, 4), 0.22, 7.0, rot, hull, 1021, null, 0.85)
	for sd in b.sides:
		if not wreck:
			L.team_panel(cv, sd.quad, 0.15, 0.25, 0.85, 0.6)
		L.seam(cv, sd.quad, 0.85, wreck)
	L.rims(cv, b, hull)
	var mh := 10.0 if f == 1 else 18.0
	if wreck:
		mh = 6.0
	var mb := P.proj(o, Vector3(0, 0, 11))
	var mt := mb + Vector2(0, -mh)
	cv.rect(int(mb.x) - 1, int(mt.y), 3, int(mh), L.GRAPH_D)
	cv.line_v(mb + Vector2(-1, 0), mt + Vector2(-1, 0), P.mul(L.GRAPH_D, 1.3))
	for k in 3:  # stacked emitter rings
		var ry := mb.y - mh * (0.3 + k * 0.3)
		cv.ellipse(mb.x, ry, 4.5 - k, 1.6, shell)
		cv.ellipse(mb.x, ry + 0.6, 3.5 - k, 1.0, L.DEAD_SEAM if wreck or f == 1 else L.CYAN)
	var head: Dictionary = L.hexp(cv, o, Vector3(0, 0, 11 + mh), 0.08, 3.0, rot, shell, 1023, null, 0.85)
	if not wreck:
		L.eye(cv, P.proj(o, Vector3(0, 0, 13 + mh)) + Vector2(0, -1), false)
	cv.outline(OUTL)
	if f == 2 and not wreck:
		G.pulse(cv, P.proj(o, Vector3(0, 0, 13 + mh)), 11.0, L.CYAN)


# ---------------------------------------------------------------- m_lancer
static func lancer(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hipz := 17.0 if not wreck else 4.0
	var bob := -1.0 if (f == 1 or f == 2) and not wreck else 0.0
	var lcol: Color = L.DEAD_D if wreck else L.GRAPH
	var legs := [[0.0, -0.09, 0.02, -0.14, 0], [0.0, 0.09, 0.02, 0.14, 1]]
	cv.ellipse(o.x + 2, o.y + 0.5, 10.0, 4.5, Color.BLACK, true)
	cv.flush_shadow()
	MU._legs(cv, o, rot, legs, hipz + bob, f, false, lcol, 2, 0.0 if wreck else 5.0, 0.13, wreck, "m_coordinator")
	var trot := rot + (0.8 if wreck else 0.0)
	var toward := cos(trot) + sin(trot) > 0.0
	var z0 := hipz + bob
	var rl := 0.26 if not wreck else 0.2
	var rail_c := L.w(trot, 0.12 + rl, 0, z0 + 8.0)
	if not toward:
		WK._rail(cv, o, trot, rail_c, rl, f, wreck)
	var hull: Color = L.DEAD if wreck else L.GRAPH
	var shell: Color = P.mul(L.DEAD, 1.15) if wreck else L.PANEL
	var pel: Dictionary = P.box(cv, o, Vector3(0, 0, z0 - 1), 0.1, 0.13, 4.0, rot, hull, 0.06, 1031)
	L.rims(cv, pel, hull)
	var tor: Dictionary = L.hexp(cv, o, Vector3(-0.03 * cos(trot), -0.03 * sin(trot), z0 + 3), 0.15, 8.0, trot, shell, 1033, null, 0.8)
	for sd in tor.sides:
		if not wreck:
			L.team_panel(cv, sd.quad, 0.14, 0.25, 0.86, 0.6)
		L.seam(cv, sd.quad, 0.88, wreck)
	if wreck:
		WK._scorch(cv, tor.top)
	else:
		L.hex_plate(cv, tor.top, 0.4, 0.5, 2.0, L.GRAPH_D, true)
		var ant := P.proj(o, L.w(trot, -0.1, -0.08, z0 + 11))
		cv.line_v(ant, ant + Vector2(0, -6), L.JOINT)
		cv.px(int(ant.x), int(ant.y) - 7, L.CYAN)
		if toward:
			L.eye(cv, P.proj(o, L.w(trot, 0.13, 0.05, z0 + 8)), false)
	if toward:
		WK._rail(cv, o, trot, rail_c, rl, f, wreck)
	MU._legs(cv, o, rot, legs, hipz + bob, f, true, lcol, 2, 0.0 if wreck else 5.0, 0.13, wreck, "m_coordinator")
	cv.outline(OUTL)
