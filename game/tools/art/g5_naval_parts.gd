extends RefCounted
## G5 deck parts shared by every ship drawer (agent ART-NAV). Each part takes the frame context
## cx = {cv, o, rot, st, sink, tips: [], hot: [], plumes: []} first so drawers can queue them as
## bound Callables for N.draw_parts (painter's order). style: "a" modern grey (glazing, lit edges),
## "b" riveted industrial (rivet rows, slit windows, rust streaks, soot), "m" graphite with cyan seams.
## Parts below the water after `sink` are clipped or skipped (sinking frames / wrecks).
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const N = preload("res://tools/art/g5_naval_lib.gd")
const S = preload("res://tools/art/g5_naval_sheet.gd")
const ML = preload("res://tools/art/faction_m_lib.gd")
const FB = preload("res://tools/art/faction_b_veh.gd")
const L4 = preload("res://tools/art/g4_units_lib.gd")

const GLASS := Color8(38, 52, 64)
const SLIT := Color8(26, 26, 24)
const DOME := Color8(214, 216, 210)


static func ctx(cv, o: Vector2, rot: float, st: Dictionary) -> Dictionary:
	return {"cv": cv, "o": o, "rot": rot, "st": st, "sink": float(st.sink), "tips": [], "hot": [], "plumes": []}


static func house(cx: Dictionary, f: float, r: float, z: float, hx: float, hy: float, hz: float, col: Color,
		style: String, team: bool, s: int, hot := false) -> void:
	var cv = cx.cv
	var st: Dictionary = cx.st
	var c := N.pal(col, st)
	var bx := N.zbox(cv, cx.o, cx.rot, f, r, z, hx, hy, hz, c, cx.sink, s)
	if bx.is_empty():
		return
	var fwd := Vector2(cos(cx.rot), sin(cx.rot))
	for sd in bx.sides:
		var q: PackedVector2Array = sd.quad
		var dd: float = (sd.n as Vector2).dot(fwd)
		match style:
			"a":
				if dd > 0.5:
					cv.poly(P.sub(q, 0.08, 0.58, 0.92, 0.84), N.pal(GLASS, st))
				elif absf(dd) < 0.5 and hx > 0.09:
					var nw := maxi(2, int(hx * 14.0))
					for i in nw:
						var u := (i + 0.3) / nw
						cv.poly(P.sub(q, u, 0.62, u + 0.4 / nw, 0.8), N.pal(GLASS, st))
			"b":
				FB.rivets(cv, q, 0.86, maxi(3, int(q[0].distance_to(q[1]) / 3.0)), c)
				FB.rivets(cv, q, 0.12, maxi(3, int(q[0].distance_to(q[1]) / 3.0)), c)
				if dd > 0.5:
					cv.poly(P.sub(q, 0.14, 0.64, 0.86, 0.74), SLIT)
				FB.streaks(cv, q, s + 3, 0.86)
			"m":
				ML.seam(cv, q, 0.62, not N.live(st))
				if dd > 0.5 and hz > 4.0:
					ML.eye(cv, q[0].lerp(q[1], 0.5).lerp(q[3].lerp(q[2], 0.5), 0.45), hx > 0.12, not N.live(st))
		if team and absf(dd) < 0.5:
			S.band(cv, q, 0.05, 0.14 if style != "a" else 0.12, 0.95, 0.4, st, c)
	ML.rims(cv, bx, c)
	if hot:
		cx.hot.append(D.sp(cx.o, cx.rot, f, r, maxf(0.0, z + hz - float(cx.sink))))


## Gun house with nb barrels along yaw (0 = bow, PI = stern), ln tiles long, elevated `elev` px.
static func turret(cx: Dictionary, f: float, r: float, z: float, hx: float, hy: float, hz: float, col: Color,
		yaw: float, ln: float, elev: float, nb: int, gap: float, style: String, s: int, team := false) -> void:
	var cv = cx.cv
	var st: Dictionary = cx.st
	var c := N.pal(col, st)
	var gun := N.pal(Color8(62, 64, 66) if style != "m" else ML.GRAPH_D, st)
	var e := elev if N.live(st) else -1.0
	var front := D.faces_cam(cx.rot, cos(yaw), sin(yaw))
	var tips: Array = []
	if not front:
		tips = _barrels(cx, f, r, z, hx, hz, yaw, ln, e, nb, gap, gun, style == "b")
	var bx := N.zbox(cv, cx.o, cx.rot, f, r, z, hx, hy, hz, c, cx.sink, s, yaw)
	if not bx.is_empty():
		ML.rims(cv, bx, c)
		for sd in bx.sides:
			if style == "b":
				FB.rivets(cv, sd.quad, 0.8, 4, c)
			elif style == "m":
				ML.seam(cv, sd.quad, 0.5, not N.live(st))
			if team:
				S.band(cv, sd.quad, 0.1, 0.2, 0.9, 0.55, st, c)
	if front:
		tips = _barrels(cx, f, r, z, hx, hz, yaw, ln, e, nb, gap, gun, style == "b")
	cx.tips.append_array(tips)


static func _barrels(cx: Dictionary, f: float, r: float, z: float, hx: float, hz: float, yaw: float, ln: float,
		e: float, nb: int, gap: float, gun: Color, thick: bool) -> Array:
	var out: Array = []
	var ax := Vector2(cos(yaw), sin(yaw))
	var pr := Vector2(-ax.y, ax.x)
	for i in nb:
		var off := pr * gap * (i - (nb - 1) * 0.5)
		var b := Vector2(f, r) + ax * hx * 0.7 + off
		var t = N.barrel(cx.cv, cx.o, cx.rot, b.x, b.y, z + hz * 0.55, yaw, ln, e, gun, cx.sink, thick)
		if t != null:
			out.append(t)
	return out


## Stack / funnel with a dark cap; optional team band; adds a hot (smoke) point.
static func funnel(cx: Dictionary, f: float, r: float, z: float, hx: float, hy: float, hz: float, col: Color,
		style: String, team: bool, s: int) -> void:
	var cv = cx.cv
	var st: Dictionary = cx.st
	var c := N.pal(col, st)
	var bx := N.zbox(cv, cx.o, cx.rot, f, r, z, hx, hy, hz, c, cx.sink, s)
	if bx.is_empty():
		return
	for sd in bx.sides:
		if team:
			S.band(cv, sd.quad, 0.0, 0.62, 1.0, 0.84, st, c)
		if style == "b":
			FB.rivets(cv, sd.quad, 0.4, 3, c)
	var top: PackedVector2Array = bx.top
	cv.poly(P.sub(top, 0.2, 0.2, 0.8, 0.8), Color8(22, 22, 22))
	var tc: Vector2 = (top[0] + top[2]) * 0.5
	if style == "b":
		FB.soot(cv, tc + Vector2(0, 1), 3.0, s + 5)
	cx.hot.append(tc)


## Mast up h px from deck height z0 with a yard; radar: "" | "bar" | "array" | "dish".
static func mast(cx: Dictionary, f: float, z0: float, h: float, col: Color, radar: String) -> void:
	var cv = cx.cv
	var st: Dictionary = cx.st
	var c := N.pal(col, st)
	var top = N.mast(cv, cx.o, cx.rot, f, z0, h, c, cx.sink, 0.09)
	if top == null:
		return
	var pr := D.sp(cx.o, cx.rot, f, 0.07, 0.0) - D.sp(cx.o, cx.rot, f, 0.0, 0.0)
	match radar:
		"bar":
			cv.line_v(top - pr + Vector2(0, -1), top + pr + Vector2(0, -1), P.mul(c, 1.25))
		"array":
			cv.rect(int(top.x) - 2, int(top.y) - 3, 5, 3, N.pal(Color8(70, 82, 92), st))
			cv.px(int(top.x), int(top.y) - 4, P.mul(c, 1.3))
		"dish":
			cv.ellipse(top.x, top.y - 1.5, 2.5, 1.4, P.mul(c, 1.2))
	if N.live(st) and radar != "":
		cv.px(int(top.x), int(top.y) - 5 if radar == "array" else int(top.y) - 2, Color8(220, 60, 50))


## Close-in weapon dome on a small base; adds its muzzle to tips.
static func dome(cx: Dictionary, f: float, r: float, z: float, yaw: float, s: int) -> void:
	var cv = cx.cv
	var st: Dictionary = cx.st
	var bx := N.zbox(cv, cx.o, cx.rot, f, r, z, 0.035, 0.035, 2.0, N.pal(Color8(150, 154, 156), st), cx.sink, s)
	if bx.is_empty():
		return
	var p := D.sp(cx.o, cx.rot, f, r, z + 4.0 - float(cx.sink))
	var dc := N.pal(DOME, st)
	cv.ellipse(p.x, p.y, 2.5, 2.6, P.mul(dc, 0.8))
	cv.ellipse(p.x - 0.4, p.y - 0.5, 2.0, 2.0, dc)
	cv.px(int(p.x) - 1, int(p.y) - 1, P.mul(dc, 1.15))
	var t = N.barrel(cv, cx.o, cx.rot, f, r, z + 2.5, yaw, 0.09, 1.0, Color8(56, 58, 60), cx.sink)
	if t != null:
		cx.tips.append(t)


## Missile box / VLS block: dark cells on its top, adds a launch plume point.
static func launcher(cx: Dictionary, f: float, r: float, z: float, hx: float, hy: float, hz: float, col: Color,
		cells: int, s: int) -> void:
	var cv = cx.cv
	var bx := N.zbox(cv, cx.o, cx.rot, f, r, z, hx, hy, hz, N.pal(col, cx.st), cx.sink, s)
	if bx.is_empty():
		return
	var top: PackedVector2Array = bx.top
	for i in cells:
		for j in 2:
			var u := (i + 0.2) / cells
			var v := 0.15 + j * 0.42
			cv.poly(P.sub(top, u, v, u + 0.6 / cells, v + 0.3), Color8(30, 32, 34))
	cx.plumes.append((top[0] + top[2]) * 0.5)


## Missile launch plumes (fire frames): bright exhaust, missile body above, smoke at the base.
static func plumes(cx: Dictionary) -> void:
	var cv = cx.cv
	for i in cx.plumes.size():
		var p: Vector2 = cx.plumes[i]
		L4.flame(cv, p + Vector2(0, -2), Vector2(0.1, -1.0), 8.0, 300 + i)
		cv.line_v(p + Vector2(1, -11), p + Vector2(1, -15), Color8(232, 232, 226))
		L4.puff(cv, p + Vector2(0, 1), 3.0, 0.45)
