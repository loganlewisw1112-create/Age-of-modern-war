extends RefCounted
## G3b Human B (Industrial) units (agent ART4), riveted khaki-rust look of faction_b_veh / faction_b_trk:
##   b_field_gun      towed field gun: split trail, gun shield, two crew (move = trail closed, crew pushing)
##   b_radar_aa       truck: rotating radar dish at the rear + twin AA cannon mount (dish turns per frame)
##   b_jammer_truck   truck: riveted box body, welded antenna farm and a jammer horn (fire = EW pulse)
##   b_guided_battery truck: elevated rocket-rail pod with a datalink mast (fire = launch)
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const T = preload("res://tools/art/truck.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const TRK = preload("res://tools/art/faction_b_trk.gd")
const G = preload("res://tools/art/g3b_lib.gd")

const SPEC := {
	"b_field_gun": {"fw": 58, "fh": 46, "pivot": [29, 31]},
	"b_radar_aa": {"fw": 66, "fh": 64, "pivot": [33, 44]},
	"b_jammer_truck": {"fw": 66, "fh": 64, "pivot": [33, 44]},
	"b_guided_battery": {"fw": 68, "fh": 58, "pivot": [34, 40]},
}
const JACKET := Color8(122, 104, 72)
const HELMET := Color8(84, 80, 64)
const SKIN := Color8(190, 152, 116)
const OUTL := Color(0.08, 0.07, 0.06, 1)


static func build(out: Dictionary) -> void:
	G.sheet(out, "b_field_gun", SPEC.b_field_gun, field_gun)
	G.sheet(out, "b_radar_aa", SPEC.b_radar_aa, radar_aa)
	G.sheet(out, "b_jammer_truck", SPEC.b_jammer_truck, jammer)
	G.sheet(out, "b_guided_battery", SPEC.b_guided_battery, guided_battery)


# ---------------------------------------------------------------- b_field_gun
static func field_gun(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var col: Color = V.BURNT if wreck else V.HULL
	var spread := 0.05 if f == 1 else 0.19
	var bl := 0.3 if f != 2 else 0.25
	P.box_shadow(cv, o, D.w(rot, 0.06, 0, 2), 0.1, 0.18, 9.0, rot)
	P.box_shadow(cv, o, D.w(rot, -0.25, 0, 0), 0.25, spread, 3.0, rot)
	cv.flush_shadow()
	var items: Array = []  # [depth, kind, side]
	for s in [-1, 1]:
		items.append([D.w(rot, -0.3, spread * s).x + D.w(rot, -0.3, spread * s).y, "trail", s])
		items.append([D.w(rot, 0.02, 0.19 * s).x + D.w(rot, 0.02, 0.19 * s).y, "wheel", s])
		if not wreck:
			var cp := D.w(rot, -0.18 if f != 1 else -0.36, 0.3 * s)
			items.append([cp.x + cp.y, "crew", s])
	items.append([0.0, "gun", 0])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		var s: int = it[2]
		match it[1]:
			"trail":
				var a := D.sp(o, rot, 0.0, 0.05 * s, 4)
				var b := D.sp(o, rot, -0.52, spread * s, 0.5)
				cv.line_v(a + Vector2(0, 1), b + Vector2(0, 1), P.mul(col, 0.55))
				cv.line_v(a, b, P.mul(col, 0.9))
				cv.rect(int(b.x) - 1, int(b.y) - 1, 3, 2, Color8(52, 50, 46))  # spade
			"wheel":
				D.road_wheel(cv, D.sp(o, rot, 0.02, 0.19 * s, 4), 3.4, 3.6, f, wreck)
			"crew":
				_crew(cv, D.sp(o, rot, -0.18 if f != 1 else -0.36, 0.3 * s, 0), f, s)
			"gun":
				_gun(cv, o, rot, f, wreck, col, bl)
	cv.outline(OUTL)
	if f == 2 and not wreck:
		var tip := D.sp(o, rot, 0.14 + bl * 2.0 + 0.05, 0, 9)
		G.flash(cv, tip, 1.2)
		cv.ellipse(tip.x + 2, tip.y - 2, 2.5, 1.6, Color(0.8, 0.78, 0.72, 0.45))


static func _gun(cv, o: Vector2, rot: float, f: int, wreck: bool, col: Color, bl: float) -> void:
	var grot := rot + (0.5 if wreck else 0.0)
	var toward := cos(grot) + sin(grot) > 0.0
	var bz := 8.0 if not wreck else 5.0
	var barrel := func() -> void:
		P.box(cv, o, D.w(grot, 0.14 + bl, 0, bz), bl, 0.022, 1.6, grot, V.GUNMETAL if not wreck else V.BURNT, 0.04, 961)
		P.box(cv, o, D.w(grot, 0.14 + bl * 2.0, 0, bz - 0.5), 0.035, 0.045, 2.6, grot, P.mul(V.GUNMETAL, 1.2), 0.04, 962)
	P.box(cv, o, D.w(rot, -0.02, 0, 3), 0.12, 0.08, 4.0, rot, P.mul(col, 0.85), 0.06, 963)  # cradle / axle
	if not toward:
		barrel.call()
	var sh: Dictionary = P.box(cv, o, D.w(grot, 0.06, 0, 4), 0.02, 0.17, 8.0, grot, col, 0.08, 964)
	for sd in sh.sides:
		var q: PackedVector2Array = sd.quad
		if wreck:
			V.scorch(cv, q)
			continue
		if absf((sd.n as Vector2).dot(Vector2(cos(grot), sin(grot)))) > 0.7:
			cv.team = true
			cv.poly(P.sub(q, 0.12, 0.45, 0.88, 0.8), Color(0.62, 0.62, 0.62))
			cv.team = false
			V.rivets(cv, q, 0.9, 6, col)
			V.patch(cv, q, 0.62, 0.12, 0.86, 0.38, V.RUST, 965)
		V.streaks(cv, q, 966)
	if toward:
		barrel.call()


## Tiny gunner: legs, khaki jacket, helmet; leaning forward while pushing, crouched when firing.
static func _crew(cv, p: Vector2, f: int, s: int) -> void:
	var h := 7 if f != 2 else 5
	var lean := 1 if f == 1 else 0
	cv.rect(int(p.x) - 1, int(p.y) - 2, 1, 2, Color8(64, 58, 46))
	cv.rect(int(p.x) + 1, int(p.y) - 2, 1, 2, Color8(64, 58, 46))
	cv.rect(int(p.x) - 1 + lean, int(p.y) - h, 3, h - 2, JACKET)
	cv.team = true
	cv.px(int(p.x) + lean + (1 if s > 0 else -1), int(p.y) - h + 1, Color(0.7, 0.7, 0.7))
	cv.team = false
	cv.px(int(p.x) + lean, int(p.y) - h - 1, SKIN)
	cv.rect(int(p.x) - 1 + lean, int(p.y) - h - 2, 3, 1, HELMET)


# ---------------------------------------------------------------- trucks
## Shared B truck: wheels, chassis, cab and a bed (`bed` Callable(body) drawn in depth order).
static func _truck(cv, o: Vector2, rot: float, f: int, wreck: bool, bed_hz: float, bed: Callable) -> void:
	var body: Color = V.BURNT if wreck else TRK.BODY
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 0), 0.52, 0.22, 4.0, rot)
	P.box_shadow(cv, o, D.w(rot, 0.36, 0.0, 4.5), 0.16, 0.22, 9.5, rot)
	P.box_shadow(cv, o, D.w(rot, -0.2, 0.0, 4.5), 0.34, 0.23, bed_hz, rot)
	cv.flush_shadow()
	T._wheels(cv, o, rot, f, wreck, false)
	var ch: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 2.0), 0.52, 0.16, 2.5, rot, TRK.CHASSIS if not wreck else T.CHAR, 0.08, 971)
	for sd in ch.sides:
		if absf((sd.n as Vector2).dot(Vector2(cos(rot), sin(rot)))) > 0.7:
			D.tow_hooks(cv, sd.quad)
	T._wheels(cv, o, rot, f, wreck, true)
	if D.faces_cam(rot, 1.0, 0.0):
		bed.call(body)
		T._exhaust(cv, o, rot, wreck)
		TRK._cab(cv, o, rot, body, wreck)
	else:
		TRK._cab(cv, o, rot, body, wreck)
		T._exhaust(cv, o, rot, wreck)
		bed.call(body)


static func radar_aa(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	_truck(cv, o, rot, f, wreck, 12.0, func(body: Color) -> void:
		TRK._bed_box(cv, o, rot, body, wreck, 3.0, 972))
	var grot := rot + (0.9 if wreck else 0.35)
	var toward := cos(grot) + sin(grot) > 0.0
	var mount := D.w(rot, -0.12, 0, 7.5)
	var guns := func() -> void:
		for s in [-1, 1]:
			var a := D.sp(o, grot, 0.0, 0.07 * s, 12) + Vector2(0, 0)
			var b := D.sp(o, grot, 0.36 if f != 2 else 0.3, 0.07 * s, 22 if not wreck else 13)
			cv.line_v(a, b, V.GUNMETAL if not wreck else V.BURNT)
			cv.line_v(a + Vector2(1, 0), b + Vector2(1, 0), P.mul(V.GUNMETAL, 0.7))
			if f == 2 and not wreck:
				G.flash(cv, b + Vector2(0, -1), 0.9)
	var mast_first := D.faces_cam(rot, 1.0, 0.0)
	if mast_first:
		_radar(cv, o, rot, f, wreck)
	if not toward:
		guns.call()
	var tt: Dictionary = P.box(cv, o, mount, 0.13, 0.13, 3.5, rot, P.mul(V.GUNMETAL, 1.1) if not wreck else V.BURNT, 0.06, 973)
	var gb: Dictionary = P.box(cv, o, D.w(grot, -0.12 * cos(grot - rot), 0, 11), 0.1, 0.12, 4.5, grot,
		V.HULL if not wreck else V.BURNT, 0.08, 974)
	if not wreck:
		D.box_edges(cv, tt, V.GUNMETAL, 975, 0.3)
		for sd in gb.sides:
			cv.team = true
			cv.poly(P.sub(sd.quad, 0.15, 0.3, 0.85, 0.7), Color(0.62, 0.62, 0.62))
			cv.team = false
			V.rivets(cv, sd.quad, 0.88, 4, V.HULL)
	if toward:
		guns.call()
	if not mast_first:
		_radar(cv, o, rot, f, wreck)
	cv.outline(OUTL)


static func _radar(cv, o: Vector2, rot: float, f: int, wreck: bool) -> void:
	var mb := D.sp(o, rot, -0.44, 0, 7.5)
	var h := 13.0 if not wreck else 5.0
	cv.line_v(mb, mb + Vector2(0, -h), Color8(58, 56, 50))
	cv.line_v(mb + Vector2(1, 0), mb + Vector2(1, -h), Color8(40, 38, 34))
	G.dish(cv, o, D.w(rot, -0.44, 0, 7.5 + h + 4), rot + PI + f * 1.3, 6.0, Color8(170, 160, 132), wreck)


static func jammer(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	_truck(cv, o, rot, f, wreck, 10.0, func(body: Color) -> void:
		var r := TRK._bed_box(cv, o, rot, P.mul(body, 0.95), wreck, 9.0, 976)
		if not wreck:
			for sd in r.sides:
				V.patch(cv, sd.quad, 0.55, 0.1, 0.8, 0.4, V.PRIMER, 977)
				V.streaks(cv, sd.quad, 978)
			D.grille(cv, r.top, 0.1, 0.15, 0.35, 0.45, body, 3))
	var heights := [16, 11, 19, 9, 14]
	for i in heights.size():
		var u := -0.06 - i * 0.1
		var side := 0.15 if i % 2 == 0 else -0.15
		var bp := D.sp(o, rot, u, side, 14)
		G.whip(cv, bp, heights[i] if not wreck else 3, Color8(214, 120, 50), wreck)
		if i % 2 == 1 and not wreck:  # welded cross-arm
			cv.line_v(bp + Vector2(-3, -heights[i] + 3), bp + Vector2(3, -heights[i] + 3), Color8(60, 56, 50))
	var hb := D.sp(o, rot, -0.42, 0, 14)  # jammer horn on a stub
	cv.line_v(hb, hb + Vector2(0, -5), Color8(58, 56, 50))
	var hp := G.dish(cv, o, D.w(rot, -0.42, 0, 23), rot + 0.4, 4.0, Color8(150, 132, 100), wreck)
	if not wreck:
		V.soot(cv, D.sp(o, rot, -0.3, 0.1, 14), 3.0, 979)
	cv.outline(OUTL)
	if f == 2 and not wreck:
		G.pulse(cv, hp, 10.0, Color8(255, 196, 120))


static func guided_battery(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	_truck(cv, o, rot, f, wreck, 14.0, func(body: Color) -> void:
		var r := TRK._bed_box(cv, o, rot, body, wreck, 2.5, 980)
		cv.poly(P.sub(r.top, 0.04, 0.06, 0.96, 0.94), P.mul(body, 0.62) if not wreck else T.CHAR))
	var lr := rot + (0.4 if wreck else 0.0)
	var lift := 0.0 if f == 1 or wreck else 4.0  # pod raised to fire, lowered on the move
	P.box(cv, o, D.w(rot, -0.3, 0, 7), 0.08, 0.1, 3.0 + lift, rot, V.GUNMETAL if not wreck else V.BURNT, 0.06, 981)
	var pod: Dictionary = P.box(cv, o, D.w(lr, -0.18, 0, 9 + lift), 0.32, 0.17, 6.0, lr, V.HULL if not wreck else V.BURNT, 0.08, 982)
	var ax := Vector2(cos(lr), sin(lr))
	for sd in pod.sides:
		var q: PackedVector2Array = sd.quad
		var d: float = (sd.n as Vector2).dot(ax)
		if wreck:
			V.scorch(cv, q)
		elif d > 0.7:  # front: 2x4 rocket tube mouths
			for yy in 2:
				for xx in 4:
					var c := P.sub(q, 0.1 + xx * 0.21, 0.2 + yy * 0.4, 0.26 + xx * 0.21, 0.5 + yy * 0.4)
					cv.poly(c, Color8(28, 26, 24))
		elif absf(d) < 0.3:
			cv.team = true
			cv.poly(P.sub(q, 0.06, 0.35, 0.94, 0.68), Color(0.62, 0.62, 0.62))
			cv.team = false
			V.rivets(cv, q, 0.9, 7, V.HULL)
			V.streaks(cv, q, 983)
	if not wreck:
		D.box_edges(cv, pod, V.HULL, 984)
		for v in [0.3, 0.7]:  # rails on the pod top
			cv.line_v(P.sub(pod.top, 0.0, v, 1.0, v)[0], P.sub(pod.top, 0.0, v, 1.0, v)[1], P.mul(V.HULL, 0.7))
		var mb := D.sp(o, rot, 0.16, -0.17, 14)
		cv.line_v(mb, mb + Vector2(0, -9), Color8(50, 48, 44))
		cv.ellipse(mb.x, mb.y - 10, 2.0, 1.4, Color8(196, 190, 170))  # datalink pod
	cv.outline(OUTL)
	if f == 2 and not wreck:
		var tip := D.sp(o, lr, 0.16, 0.06, 15 + lift)
		G.flash(cv, tip, 1.2)
		cv.line_v(tip, tip + (D.sp(o, lr, 0.6, 0, 30) - D.sp(o, lr, 0.0, 0, 15)), Color(0.86, 0.84, 0.78, 0.55))
