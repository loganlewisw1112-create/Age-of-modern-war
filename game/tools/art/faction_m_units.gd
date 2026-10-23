extends RefCounted
## Machine legged units (agent ART3-M): repair bot, scout crawler, coordinator node, heavy walker.
## Infantry-style sheets: rows = 8 facings (world angle k * 45 deg), frames idle/walk_a/walk_b/fire.
## The walker also gets a wreck sheet (1 frame x 8 facings).
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const WK = preload("res://tools/art/faction_m_walker.gd")

const FRAMES := ["idle", "walk_a", "walk_b", "fire"]
const SPEC := {
	"m_repair_bot": {"fw": 30, "fh": 30, "pivot": [15, 23]},
	"m_scout_crawler": {"fw": 32, "fh": 28, "pivot": [16, 21]},
	"m_coordinator": {"fw": 28, "fh": 40, "pivot": [14, 33]},
	"m_walker": {"fw": 70, "fh": 70, "pivot": [35, 52]},
}
const WRECKS := ["m_walker"]


static func build(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("infantry", {})
	var wrecks: Dictionary = out.manifest.get("vehicle_wrecks", {})
	for def in SPEC:
		var sp: Dictionary = SPEC[def]
		var fw: int = sp.fw
		var fh: int = sp.fh
		var o := Vector2(sp.pivot[0], sp.pivot[1])
		var img := Image.create(fw * FRAMES.size(), fh * 8, false, Image.FORMAT_RGBA8)
		var msk := Image.create(fw * FRAMES.size(), fh * 8, false, Image.FORMAT_RGBA8)
		var wimg := Image.create(fw, fh * 8, false, Image.FORMAT_RGBA8)
		for k in 8:
			for f in FRAMES.size():
				var cv = P.Canvas.new(fw, fh)
				draw(cv, def, k * PI / 4.0, f, false, o)
				img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
				msk.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
			if def in WRECKS:
				var wc = P.Canvas.new(fw, fh)
				draw(wc, def, k * PI / 4.0, 0, true, o)
				wimg.blit_rect(wc.img, Rect2i(0, 0, fw, fh), Vector2i(0, k * fh))
		out.images["units/%s.png" % def] = img
		out.images["units/%s_mask.png" % def] = msk
		man[def] = {"file": "units/%s.png" % def, "mask": "units/%s_mask.png" % def, "fw": fw, "fh": fh,
			"pivot": sp.pivot, "frames": FRAMES, "facings": 8, "legged": true}
		if def in WRECKS:
			out.images["wrecks/%s_wreck.png" % def] = wimg
			wrecks[def] = {"file": "wrecks/%s_wreck.png" % def, "fw": fw, "fh": fh, "pivot": sp.pivot,
				"frames": ["wreck"], "facings": 8}
	out.manifest["infantry"] = man
	out.manifest["vehicle_wrecks"] = wrecks


## Leg table per def: [hip_fwd, hip_right, foot_fwd, foot_right, gait_group].
static func legs_of(def: String) -> Array:
	match def:
		"m_repair_bot":
			return [[0.08, 0.08, 0.19, 0.2, 0], [-0.08, -0.08, -0.19, -0.2, 0], [0.08, -0.08, 0.19, -0.2, 1], [-0.08, 0.08, -0.19, 0.2, 1]]
		"m_scout_crawler":
			var a: Array = []
			for i in 3:
				for s in [-1, 1]:
					a.append([-0.11 + i * 0.11, 0.07 * s, (-0.22 + i * 0.22), 0.25 * s, (i + (1 if s > 0 else 0)) % 2])
			return a
		"m_coordinator":
			return [[0.0, -0.055, 0.0, -0.085, 0], [0.0, 0.055, 0.0, 0.085, 1]]
		"m_walker":
			return [[0.18, 0.17, 0.4, 0.38, 0], [-0.18, -0.17, -0.4, -0.38, 0], [0.18, -0.17, 0.4, -0.38, 1], [-0.18, 0.17, -0.4, 0.38, 1]]
	return []


static func draw(cv, def: String, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hipz: float = {"m_repair_bot": 7.0, "m_scout_crawler": 5.0, "m_coordinator": 12.0, "m_walker": 19.0}[def]
	var stride: float = {"m_repair_bot": 0.06, "m_scout_crawler": 0.07, "m_coordinator": 0.1, "m_walker": 0.12}[def]
	var th: int = 3 if def == "m_walker" else (2 if def == "m_coordinator" else 1)
	var kup: float = {"m_repair_bot": 3.0, "m_scout_crawler": 4.0, "m_coordinator": 0.0, "m_walker": 9.0}[def]
	var bob := -1.0 if f == 1 or f == 2 else 0.0
	if wreck:
		hipz = 5.0
		kup = 3.0
		bob = 0.0
	var lcol: Color = L.DEAD_D if wreck else L.GRAPH
	# ground shadow
	var sz: Vector2 = {"m_repair_bot": Vector2(7, 3), "m_scout_crawler": Vector2(8, 3.5), "m_coordinator": Vector2(5, 2.4),
		"m_walker": Vector2(19, 9)}[def]
	cv.ellipse(o.x + 2, o.y + 0.5, sz.x, sz.y, Color.BLACK, true)
	cv.flush_shadow()
	var legs := legs_of(def)
	_legs(cv, o, rot, legs, hipz + bob, f, false, lcol, th, kup, stride, wreck, def)
	match def:
		"m_repair_bot":
			_repair_bot(cv, o, rot, f, bob)
		"m_scout_crawler":
			_crawler(cv, o, rot, f, bob)
		"m_coordinator":
			_coordinator(cv, o, rot, f, bob, true)
		"m_walker":
			WK.walker(cv, o, rot, f, bob, wreck)
	_legs(cv, o, rot, legs, hipz + bob, f, true, lcol, th, kup, stride, wreck, def)
	cv.outline(Color(0.07, 0.08, 0.09, 1))
	if def == "m_coordinator":
		_coordinator(cv, o, rot, f, bob, false)  # antenna whips after the outline (stay 1 px)


static func _legs(cv, o: Vector2, rot: float, legs: Array, hipz: float, f: int, near: bool, col: Color,
		th: int, kup: float, stride: float, wreck: bool, def: String) -> void:
	for lg in legs:
		var fv := L.w(rot, lg[2], lg[3])
		if (fv.x + fv.y > 0.0) != near:
			continue
		var ph := 0
		if f == 1:
			ph = 1 if lg[4] == 0 else -1
		elif f == 2:
			ph = -1 if lg[4] == 0 else 1
		var spread := 1.3 if wreck else 1.0
		var ff: float = lg[2] * spread + ph * stride
		var lift := 2.0 if ph > 0 else 0.0
		var hip := L.w(rot, lg[0], lg[1], hipz)
		var foot := L.w(rot, ff, lg[3] * spread, lift)
		var od := Vector2(foot.x - hip.x, foot.y - hip.y)
		if def == "m_coordinator":  # digitigrade: knee forward
			od = Vector2(cos(rot), sin(rot)) * 0.06
		else:
			od = od.normalized() * (0.07 if def == "m_walker" else 0.04)
		L.leg(cv, o, hip, foot, od, kup, col, th, wreck)
		if def == "m_walker" and not wreck:  # armoured thigh plate with a status light
			var mid := P.proj(o, (hip + foot) * 0.5 + Vector3(od.x, od.y, kup * 0.6 + 3))
			cv.rect(int(mid.x) - 1, int(mid.y) - 2, 4, 3, L.PANEL_D)
			cv.px(int(mid.x), int(mid.y) - 2, P.mul(L.PANEL_D, 1.3))


static func _team_hex(cv, o: Vector2, c: Vector3, r: float, rot: float, lum := 0.75) -> void:
	cv.team = true
	L.hexp(cv, o, c, r, 0.0, rot, Color(lum, lum, lum), 3)
	cv.team = false


static func _repair_bot(cv, o: Vector2, rot: float, f: int, bob: float) -> void:
	var front := cos(rot) + sin(rot) > 0.0
	var tip := P.proj(o, L.w(rot, 0.3, 0.05, 5 + (2 if f == 3 else 0) + bob))
	var sh := P.proj(o, L.w(rot, 0.12, 0.05, 10 + bob))
	if not front:
		cv.line_v(sh, tip, L.GRAPH_D)
	L.hexp(cv, o, Vector3(0, 0, 4 + bob), 0.11, 3.0, rot, L.GRAPH_D, 61)
	var r: Dictionary = L.hexp(cv, o, Vector3(0, 0, 7 + bob), 0.16, 5.0, rot, L.PANEL, 63)
	for sd in r.sides:
		L.seam(cv, sd.quad, 0.3)
	_team_hex(cv, o, Vector3(0, 0, 12 + bob), 0.09, rot)
	if front:
		L.eye(cv, P.proj(o, L.w(rot, 0.15, -0.04, 10 + bob)))
		cv.line_v(sh, tip, L.GRAPH_D)
		cv.line_v(sh + Vector2(0, -1), tip + Vector2(0, -1), P.mul(L.GRAPH, 1.2))
	else:  # rear: small mast
		var m := P.proj(o, L.w(rot, -0.08, 0.06, 12 + bob))
		cv.line_v(m, m + Vector2(0, -4), L.GRAPH_D)
		cv.px(int(m.x), int(m.y) - 5, L.CYAN)
	if f == 3:  # welding arc
		cv.ellipse(tip.x + 0.5, tip.y + 0.5, 2.5, 2.0, Color(L.CYAN.r, L.CYAN.g, L.CYAN.b, 0.5))
		cv.px(int(tip.x), int(tip.y), L.CYAN_HOT)
		for i in 3:
			cv.px(int(tip.x) + P.hi(i, 1, 71, 5) - 2, int(tip.y) + P.hi(i, 2, 71, 3) - 1, Color8(255, 240, 190))


static func _crawler(cv, o: Vector2, rot: float, f: int, bob: float) -> void:
	var front := cos(rot) + sin(rot) > 0.0
	var b: Dictionary = P.box(cv, o, Vector3(0, 0, 3 + bob), 0.2, 0.09, 4.0, rot, L.GRAPH, 0.06, 81)
	for sd in b.sides:
		if absf((sd.n as Vector2).dot(Vector2(-sin(rot), cos(rot)))) > 0.7:
			L.team_panel(cv, sd.quad, 0.1, 0.3, 0.9, 0.8)
	var s: Dictionary = L.hexp(cv, o, Vector3(-0.02, 0, 7 + bob), 0.18, 2.0, rot, L.PANEL, 83, null, 0.55)
	for sd in s.sides:
		L.seam(cv, sd.quad, 0.0)
	var gun_a := P.proj(o, L.w(rot, 0.14, 0, 8 + bob))
	var gun_b := P.proj(o, L.w(rot, 0.32, 0, 8 + bob))
	if not front:
		cv.line_v(gun_a, gun_b, L.JOINT)
	L.hexp(cv, o, Vector3(0.04, 0, 9 + bob), 0.07, 2.0, rot, L.GRAPH_D, 85)
	if front:
		L.eye(cv, P.proj(o, L.w(rot, 0.1, 0, 10 + bob)), true)
		cv.line_v(gun_a, gun_b, L.JOINT)
	if f == 3:
		cv.px(int(gun_b.x), int(gun_b.y), Color8(255, 236, 160))
		cv.px(int(gun_b.x) + (1 if gun_b.x > gun_a.x else -1), int(gun_b.y), Color8(255, 200, 120))


static func _coordinator(cv, o: Vector2, rot: float, f: int, bob: float, body: bool) -> void:
	var front := cos(rot) + sin(rot) > 0.0
	if not body:
		for s in [-1, 1]:  # antenna array behind the head
			var a := P.proj(o, L.w(rot, -0.06, 0.04 * s, 24 + bob))
			for i in 9:
				var x: int = int(a.x) + (int(s) * i) / 5
				var y := int(a.y) - i
				if cv.get_px(x, y).a < 0.5:
					cv.px(x, y, L.GRAPH_D if i < 8 else L.CYAN)
		return
	var arm_a := P.proj(o, L.w(rot, 0.02, 0.12, 17 + bob))
	var arm_b := P.proj(o, L.w(rot, 0.2, 0.12, 16 + bob))
	if not L.w(rot, 0, 1).x + L.w(rot, 0, 1).y > 0.0:
		cv.line_v(arm_a, arm_b, L.GRAPH_D)
	L.hexp(cv, o, Vector3(0, 0, 10 + bob), 0.07, 3.0, rot, L.GRAPH_D, 91)
	var t: Dictionary = L.hexp(cv, o, Vector3(0, 0, 13 + bob), 0.11, 8.0, rot, L.PANEL, 93, null, 0.8)
	for sd in t.sides:
		L.team_panel(cv, sd.quad, 0.12, 0.5, 0.88, 0.85)
		L.seam(cv, sd.quad, 0.25)
	L.hexp(cv, o, Vector3(0, 0, 21 + bob), 0.065, 4.0, rot, L.GRAPH, 95)
	if front:
		var v := P.proj(o, L.w(rot, 0.06, 0, 23 + bob))
		cv.px(int(v.x) - 1, int(v.y), L.CYAN)
		L.eye(cv, v)
		cv.px(int(v.x) + 1, int(v.y), L.CYAN)
	if L.w(rot, 0, 1).x + L.w(rot, 0, 1).y > 0.0:
		cv.line_v(arm_a, arm_b, L.GRAPH_D)
	if f == 3:
		var tip := arm_b + (arm_b - arm_a).normalized() * 4.0
		cv.line_v(arm_b, tip, L.CYAN)
		cv.px(int(tip.x), int(tip.y), L.CYAN_HOT)
