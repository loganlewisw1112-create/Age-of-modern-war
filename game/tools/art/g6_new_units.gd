extends RefCounted
## G6 company leaders and commanders (agent ART-G6b, CONTRACTS_G6 s3.2).
##   Human A / B officers: G5 figure kit, 1-man squad sheets (48x36, foot at the squad pivot), frames idle /
##   walk_a / walk_b / fire / command (pointing) / wounded. Rank reads at game scale:
##     commander  peaked officer cap with a gold badge, gold shoulder boards, greatcoat skirt, pistol
##     captain    A: helmet with two silver bars + radio pack; B: field cap with red band + Sam Browne, pistol
##     lieutenant A: helmet with one silver bar; B: steel helmet with a red stripe, SMG
##   Machine command nodes (vehicle sheets + wreck): hovering one-eyed hex core, team ring on top; rank =
##   antenna crossbars and orbiting relay shards (commander 3, captain 2, lieutenant 1), larger with rank.
##   Frames idle / move / fire (eye beam) / command (relay pulse ring).
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const SQ = preload("res://tools/art/g5_units_sq.gd")
const FIG = preload("res://tools/art/g5_units_fig.gd")
const U = preload("res://tools/art/units.gd")
const BI = preload("res://tools/art/faction_b_inf.gd")
const M = preload("res://tools/art/faction_m_lib.gd")
const SU = preload("res://tools/art/g6_new_suits.gd")

const OUTL := Color(0.09, 0.09, 0.07, 1)
const MOUTL := Color(0.07, 0.08, 0.09, 1)
const GOLD := Color8(232, 196, 92)
const SILVER := Color8(214, 216, 210)
const RED_BAND := Color8(166, 46, 38)
const LEADERS := ["a_commander", "a_captain", "a_lieutenant", "b_commander", "b_captain", "b_lieutenant"]
const LEAD_FR := ["idle", "walk_a", "walk_b", "fire", "command", "wounded"]
const NODES := {"m_commander": 3, "m_captain": 2, "m_lieutenant": 1}
const NODE_FR := ["idle", "move", "fire", "command"]


static func build(out: Dictionary) -> void:
	for id in LEADERS:
		SL.squad_sheet(out, id, 1, leader.bind(String(id)), LEAD_FR)
	for id in NODES:
		SL.veh_sheet(out, id, {"fw": 48, "fh": 56, "pivot": [24, 42]}, node.bind(int(NODES[id])), NODE_FR)
	SU.build(out)


static func style(id: String) -> Dictionary:
	match id:
		"a_commander":
			return {"coat": Color8(84, 88, 62), "trouser": U.TROUSER, "boot": U.BOOT, "skin": U.SKIN, "head": "officer", "weapon": "pistol"}
		"a_captain":
			return {"coat": U.UNIFORM, "trouser": U.TROUSER, "boot": U.BOOT, "skin": U.SKIN, "head": "helm_a", "weapon": "carbine", "back": "radio"}
		"a_lieutenant":
			return {"coat": U.UNIFORM, "trouser": U.TROUSER, "boot": U.BOOT, "skin": U.SKIN, "head": "helm_a", "weapon": "carbine", "back": "pack"}
		"b_commander":
			return {"coat": Color8(86, 78, 62), "trouser": BI.TROUSER, "boot": BI.BOOT, "skin": BI.SKIN, "head": "officer", "weapon": "pistol", "belt": BI.LEATHER}
		"b_captain":
			return {"coat": BI.DRILL, "trouser": BI.TROUSER, "boot": BI.BOOT, "skin": BI.SKIN, "head": "cap_b", "weapon": "pistol", "belt": BI.LEATHER}
	return {"coat": BI.DRILL, "trouser": BI.TROUSER, "boot": BI.BOOT, "skin": BI.SKIN, "head": "helm_b", "weapon": "smg", "back": "pack", "belt": BI.LEATHER}


static func leader(cv, k: int, f: int, alive: int, id: String) -> void:
	var st := style(id)
	var fn: String = LEAD_FR[f]
	if fn == "wounded":
		SL.place(cv, Vector2i(SQ.PIV), func(c) -> void: FIG.draw(c, k, "lie", st))
		return
	var pose: String = {"idle": "stand", "walk_a": "walk_a", "walk_b": "walk_b", "fire": "aim", "command": "stand"}[fn]
	SL.formation(cv, k, 0, 1, alive, func(c, kk: int, _f: int, _i: int) -> void:
		FIG.draw(c, kk, pose, SQ.m(st, {"fire": true}) if fn == "fire" else st)
		insignia(c, kk, pose, id, st)
		if fn == "command":
			_point(c, kk, pose, st))


## Rank marks on an outlined 24x26 figure (foot (12, 21); torso / head as g5_units_fig _stand).
static func insignia(c, k: int, pose: String, id: String, st: Dictionary) -> void:
	var d := L.sd(k)
	var away := d.y < -0.2
	var ty := 10 - (1 if pose == "walk_a" else 0)
	var tx := 10
	var hx := tx + 1
	var hy := ty - 4
	var rank := id.substr(2)
	match rank:
		"commander":
			c.rect(tx, ty + 6, 5, 2, P.mul(st.coat, 0.92))  # greatcoat skirt
			c.rect(hx - 1, hy - 4, 5, 1, OUTL)
			c.px(hx - 2, hy - 3, OUTL)
			c.px(hx - 2, hy - 2, OUTL)
			c.px(hx + 4, hy - 3, OUTL)
			c.px(hx + 4, hy - 2, OUTL)
			var crown: Color = Color8(80, 86, 60) if id.begins_with("a") else Color8(92, 82, 62)
			c.rect(hx - 1, hy - 3, 5, 2, crown)
			c.rect(hx - 1, hy - 1, 5, 1, Color8(52, 46, 34) if id.begins_with("a") else RED_BAND)
			if not away:
				c.px(hx + 1, hy - 2, GOLD)
				c.px(hx + (3 if d.x >= 0 else -1), hy, Color8(30, 30, 28))  # visor
			c.px(tx, ty, GOLD)
			c.px(tx + 4, ty, GOLD)
			c.px(tx + 1, ty, P.mul(GOLD, 0.8))
			c.px(tx + 3, ty, P.mul(GOLD, 0.8))
		"captain":
			if id.begins_with("a"):
				if not away:
					c.px(hx, hy - 1, SILVER)
					c.px(hx + 2, hy - 1, SILVER)
			else:
				c.rect(hx - 1, hy - 1, 5, 1, RED_BAND)
				for i in 3:
					c.px(tx + 1 + i, ty + 1 + i, BI.LEATHER)
			c.px(tx, ty, SILVER)
			c.px(tx + 4, ty, SILVER)
		"lieutenant":
			if not away:
				c.px(hx + 1, hy - 1 if id.begins_with("a") else hy - 2, SILVER if id.begins_with("a") else RED_BAND)


## Command frame: the free arm thrown out along the facing, hand open.
static func _point(c, k: int, pose: String, st: Dictionary) -> void:
	var d := L.sd(k)
	var ty := 10 - (1 if pose == "walk_a" else 0)
	var sh := Vector2(12.0 + d.x * 2.0, ty + 1)
	var hand := sh + Vector2(d.x * 6.0 + (1.0 if d.x >= 0 else -1.0), d.y * 2.0 - 3.0)
	c.line_v(sh, hand, P.mul(st.coat, 1.08))
	c.px(int(hand.x), int(hand.y), st.skin)
	c.px(int(hand.x), int(hand.y) - 1, OUTL)


# ---------------------------------------------------------------- Machine command nodes
static func node(cv, rot: float, f: int, wreck: bool, o: Vector2, rk: int) -> void:
	var s := 0.8 + 0.15 * rk
	if wreck:
		_node_wreck(cv, rot, o, s, rk)
		return
	var hov := 6.0 + rk * 1.5 + (1.0 if f == 1 else 0.0)
	var lean := 0.03 if f == 1 else 0.0
	cv.ellipse(o.x + 1, o.y + 0.5, 7.0 * s, 3.0 * s, Color.BLACK, true)
	cv.flush_shadow()
	cv.ellipse(o.x, o.y - 0.5, 3.5 * s, 1.5 * s, Color(M.CYAN.r, M.CYAN.g, M.CYAN.b, 0.3))  # hover wash
	var r := 0.12 * s
	var hz := 9.0 * s
	var shards: Array = []
	for i in rk:
		var a := rot + i * TAU / rk + f * 0.5 + 0.4
		shards.append(Vector3(cos(a) * 0.22 * s, sin(a) * 0.22 * s, hov + hz * 0.55))
	for c3: Vector3 in shards:
		if c3.x + c3.y < 0.0:
			_shard(cv, o, c3, s, rot)
	var core: Dictionary = M.hexp(cv, o, M.w(rot, lean, 0.0, hov), r, hz, rot, M.GRAPH, 600 + rk)
	for sd in core.sides:
		M.seam(cv, sd.quad, 0.5)
	var t: PackedVector2Array = core.top
	var cc := (t[0] + t[3]) * 0.5
	var ring := PackedVector2Array()
	for i in 6:
		ring.append(t[i].lerp(cc, 0.35))
	cv.team = true
	cv.poly(ring, Color(0.72, 0.72, 0.72))
	cv.team = false
	M.hexp(cv, o, M.w(rot, lean, 0.0, hov + hz), r * 0.55, 3.0 * s, rot, M.PANEL, 610 + rk)
	var front := D.faces_cam(rot, 1.0, 0.0)
	var eye := M.sp(o, rot, r * 0.9 + lean, 0.0, hov + hz * 0.5)
	var m0 := M.sp(o, rot, lean, 0.0, hov + hz + 3.0 * s)
	var m1 := m0 + Vector2(0, -(8 + rk * 2))
	cv.line_v(m0, m1, M.PANEL)
	for i in rk:  # rank crossbars
		var y := int(m1.y) + 2 + i * 2
		var w := 2 if i == 0 and rk == 3 else 1
		cv.line(int(m1.x) - w, y, int(m1.x) + w, y, M.PANEL_D)
	for c3: Vector3 in shards:
		if c3.x + c3.y >= 0.0:
			_shard(cv, o, c3, s, rot)
	cv.outline(MOUTL)
	cv.px(int(m1.x), int(m1.y) - 1, M.CYAN_HOT)
	if front:
		M.eye(cv, eye, rk >= 2)
	var dir := M.sp(o, rot, 1.0, 0.0, 0.0) - M.sp(o, rot, 0.0, 0.0, 0.0)
	dir = dir.normalized() if dir.length() > 0.1 else Vector2(1, 0)
	if f == 2:  # laser from the eye along the facing
		var e0 := eye + dir * 2.0
		cv.line_v(e0, e0 + dir * 16.0, Color(M.CYAN.r, M.CYAN.g, M.CYAN.b, 0.55))
		cv.line_v(e0, e0 + dir * 14.0, M.CYAN_HOT)
		cv.ellipse(e0.x, e0.y, 2.2, 1.8, Color(M.CYAN.r, M.CYAN.g, M.CYAN.b, 0.45))
	elif f == 3:  # relay pulse ring on the ground + uplink from the mast
		for i in 36:
			var a := i * TAU / 36.0
			var q := P.proj(o, Vector3(cos(a) * 0.5 * s, sin(a) * 0.5 * s, 1.0))
			cv.px(int(q.x), int(q.y), Color(M.CYAN.r, M.CYAN.g, M.CYAN.b, 0.85 if i % 3 != 0 else 0.4))
		for i in 4:
			cv.px(int(m1.x), int(m1.y) - 3 - i * 2, Color(M.CYAN_HOT.r, M.CYAN_HOT.g, M.CYAN_HOT.b, 0.9 - i * 0.18))


static func _shard(cv, o: Vector2, c3: Vector3, s: float, rot: float) -> void:
	var h: Dictionary = M.hexp(cv, o, c3, 0.035 * s, 3.0, rot, M.PANEL_D, 620)
	var t: PackedVector2Array = h.top
	var c := (t[0] + t[3]) * 0.5
	cv.px(int(c.x), int(c.y), M.CYAN)


static func _node_wreck(cv, rot: float, o: Vector2, s: float, rk: int) -> void:
	cv.ellipse(o.x + 1, o.y + 1, 8.0 * s, 3.2 * s, Color8(40, 38, 36))
	var core: Dictionary = M.hexp(cv, o, M.w(rot, 0.0, 0.0, 0.0), 0.12 * s, 6.0 * s, rot + 0.3, M.DEAD, 630)
	for sd in core.sides:
		M.seam(cv, sd.quad, 0.5, true)
	M.hexp(cv, o, M.w(rot, 0.12 * s, 0.14 * s, 0.0), 0.06 * s, 2.5, rot, M.DEAD_D, 631)
	var m0 := M.sp(o, rot, -0.05, -0.05, 6.0 * s)
	cv.line_v(m0, m0 + Vector2(-7, 2), M.DEAD)
	for i in rk:
		M.hexp(cv, o, M.w(rot, -0.18 + i * 0.12, 0.2, 0.0), 0.03 * s, 2.0, rot, M.DEAD_D, 632 + i)
	cv.outline(MOUTL)
	M.eye(cv, M.sp(o, rot, 0.1 * s, 0.0, 3.0 * s), false, true)
	V.soot(cv, M.sp(o, rot, 0.0, 0.0, 6.0), 5.0, 635)
