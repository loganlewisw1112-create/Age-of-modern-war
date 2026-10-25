extends RefCounted
## G5 Machine m_maint_swarm (agent ART-U5): a printed carrier node (low hex, cyan seams, team cap) with four
## hovering maintenance bots around it (graphite pods, rotor discs, a cyan sensor eye, a manipulator arm).
## Frames idle / move (bots pulled into a trailing V, carrier tilted) / fire (cutting arc at the front) /
## work (repair beams from every bot to the work point ahead, sparks). Wreck = dead node + downed bots.
const P = preload("res://tools/art/pix.gd")
const M = preload("res://tools/art/faction_m_lib.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")

const SPEC := {"fw": 54, "fh": 46, "pivot": [27, 31]}
const OUTL := Color(0.07, 0.08, 0.09, 1)
## Bot positions (fwd, right) in tiles per frame family: hover ring / trailing V.
const RING := [Vector2(0.3, 0.0), Vector2(0.0, 0.32), Vector2(-0.3, 0.0), Vector2(0.0, -0.32)]
const VEE := [Vector2(0.34, 0.0), Vector2(0.06, 0.26), Vector2(-0.22, 0.0), Vector2(0.06, -0.26)]


static func build(out: Dictionary) -> void:
	SL.veh_sheet(out, "m_maint_swarm", SPEC, swarm, ["idle", "move", "fire", "work"])


static func swarm(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var pts: Array = VEE if f == 1 else RING
	M.hex_shadow(cv, o, M.w(rot, 0.0, 0.0, 0), 0.16, 4.0, rot)
	for i in 4:
		var p: Vector2 = pts[i]
		var gp := P.proj(o, M.w(rot, p.x, p.y, 0))
		if wreck:
			cv.ellipse(gp.x + 1, gp.y + 1, 2.6, 1.2, Color.BLACK, true)
		else:
			cv.ellipse(gp.x + 2, gp.y + 1, 2.4, 1.0, Color.BLACK, true)
	cv.flush_shadow()
	var items: Array = []  # back-to-front: bots behind the node, the node, bots in front
	for i in 4:
		var p: Vector2 = pts[i]
		var wv := M.w(rot, p.x, p.y, 0)
		items.append([wv.x + wv.y, i])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var node_done := false
	for it in items:
		if not node_done and it[0] > 0.0:
			_node(cv, o, rot, f, wreck)
			node_done = true
		_bot(cv, o, rot, pts[it[1]], f, it[1], wreck)
	if not node_done:
		_node(cv, o, rot, f, wreck)
	cv.outline(OUTL)
	if wreck:
		return
	var front: Vector2 = pts[0]
	var fb := P.proj(o, M.w(rot, front.x, front.y, _alt(f, 0)))
	if f == 2:  # cutting arc
		var t := P.proj(o, M.w(rot, front.x + 0.22, front.y, 4))
		cv.line_v(fb, t, M.CYAN_HOT)
		L.flash(cv, t, 0.7)
	elif f == 3:  # repair beams converging on the work point ahead, sparks
		var wp := P.proj(o, M.w(rot, 0.5, 0.0, 1))
		for i in 4:
			var p: Vector2 = pts[i]
			var b := P.proj(o, M.w(rot, p.x, p.y, _alt(f, i) - 2))
			cv.line_v(b, wp, Color(M.CYAN.r, M.CYAN.g, M.CYAN.b, 0.7))
		cv.ellipse(wp.x, wp.y, 2.0, 1.0, M.CYAN_HOT)
		for i in 5:
			cv.px(int(wp.x) - 3 + P.hi(i, 1, 9301, 7), int(wp.y) - 3 + P.hi(i, 2, 9302, 4), Color8(255, 236, 170))


static func _alt(f: int, i: int) -> float:
	return 9.0 + float((i + f) % 2) * 2.0


## Carrier node: low hex prism with glowing seams and a team-coloured cap.
static func _node(cv, o: Vector2, rot: float, f: int, wreck: bool) -> void:
	var col: Color = M.DEAD if wreck else M.GRAPH
	var r: Dictionary = M.hexp(cv, o, M.w(rot, 0.0, 0.0, 0), 0.15, 5.0, rot, col, 931)
	for sd in r.sides:
		M.seam(cv, sd.quad, 0.5, wreck)
	if wreck:
		return
	var cap: Dictionary = M.hexp(cv, o, M.w(rot, 0.0, 0.0, 5), 0.09, 2.0, rot, M.PANEL, 932)
	cv.team = true
	cv.poly(cap.top, Color(0.7, 0.7, 0.7))
	cv.team = false
	var e := P.proj(o, M.w(rot, 0.12, 0.0, 4))
	if M.w(rot, 1.0, 0.0).x + M.w(rot, 1.0, 0.0).y > 0.0:
		cv.px(int(e.x), int(e.y), M.CYAN_HOT)


## One hover bot: rotor disc, pod, eye, arm; on the ground and dark when wrecked.
static func _bot(cv, o: Vector2, rot: float, p: Vector2, f: int, i: int, wreck: bool) -> void:
	var z := 0.0 if wreck else _alt(f, i)
	var c := P.proj(o, M.w(rot, p.x, p.y, z))
	var body: Color = M.DEAD if wreck else M.GRAPH
	if not wreck:
		cv.ellipse(c.x, c.y - 3, 3.6, 1.2, Color(0.82, 0.86, 0.86, 0.35))  # rotor disc
		cv.line_v(c + Vector2(0, -1), c + Vector2(0, -3), M.JOINT)
	cv.ellipse(c.x, c.y, 2.4, 1.8, body)
	cv.rect(int(c.x) - 2, int(c.y) - 1, 4, 1, P.mul(body, 1.35))
	if wreck:
		cv.px(int(c.x) + 2, int(c.y) + 1, M.DEAD_SEAM)
		return
	var fwd := P.proj(o, M.w(rot, p.x + 0.08, p.y, z)) - c
	cv.px(int(c.x + fwd.x * 0.6), int(c.y + fwd.y * 0.6), M.CYAN_HOT)
	cv.team = true
	cv.px(int(c.x - fwd.x * 0.6), int(c.y - fwd.y * 0.6) - 1, Color(0.75, 0.75, 0.75))
	cv.team = false
	var arm := c + fwd * 1.2 + Vector2(0, 2)
	cv.line_v(c + Vector2(0, 1), arm, M.PANEL_D)
	cv.px(int(arm.x), int(arm.y), M.CYAN if f == 3 else M.PANEL)
