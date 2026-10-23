extends RefCounted
## Human B (Industrial) trucks (agent ART3-B): b_artillery_truck (howitzer on a flatbed, barrel
## elevated over the cab, rear spades, shell crates) and b_recovery_truck (wrecker boom, hook,
## spare tyre, gas bottles, toolboxes). Chassis, wheels, cab and exhaust come from truck.gd's helpers
## in a rust-brown body colour; the bed loads are drawn here. Team colour: cab roof + bed stripe.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const T = preload("res://tools/art/truck.gd")
const V = preload("res://tools/art/faction_b_veh.gd")

const BODY := Color8(118, 90, 60)
const CHASSIS := Color8(50, 46, 40)
const GUNMETAL := Color8(64, 62, 56)
const HAZARD := Color8(196, 150, 50)
const BOOM := Color8(164, 96, 46)
const WOOD := Color8(128, 98, 62)
const BOTTLE := Color8(70, 96, 74)


static func draw(cv, def: String, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var body: Color = V.BURNT if wreck else BODY
	P.box_shadow(cv, o, D.w(rot, 0.0, 0.0, 0), 0.52, 0.22, 4.0, rot)
	P.box_shadow(cv, o, D.w(rot, 0.36, 0.0, 4.5), 0.16, 0.22, 9.5, rot)
	if def == "b_artillery_truck":
		P.box_shadow(cv, o, D.w(rot, -0.05, 0.0, 6), 0.45, 0.06, 12.0, rot)
	else:
		P.box_shadow(cv, o, D.w(rot, -0.5, 0.0, 6), 0.18, 0.05, 18.0, rot)
	cv.flush_shadow()
	T._wheels(cv, o, rot, f, wreck, false)
	var ch: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 2.0), 0.52, 0.16, 2.5, rot, CHASSIS if not wreck else T.CHAR, 0.08, 701)
	for sd in ch.sides:
		if absf((sd.n as Vector2).dot(Vector2(cos(rot), sin(rot)))) > 0.7:
			D.tow_hooks(cv, sd.quad)
	T._wheels(cv, o, rot, f, wreck, true)
	var front := D.faces_cam(rot, 1.0, 0.0)
	if def == "b_artillery_truck":
		if front:
			_flatbed(cv, o, rot, body, wreck)
			T._exhaust(cv, o, rot, wreck)
			_cab(cv, o, rot, body, wreck)
		else:
			_cab(cv, o, rot, body, wreck)
			T._exhaust(cv, o, rot, wreck)
			_flatbed(cv, o, rot, body, wreck)
		_howitzer(cv, o, rot, f, wreck)
	else:
		if front:
			_wrecker_bed(cv, o, rot, body, wreck)
			_boom(cv, o, rot, wreck)
			T._exhaust(cv, o, rot, wreck)
			_cab(cv, o, rot, body, wreck)
		else:
			_cab(cv, o, rot, body, wreck)
			T._exhaust(cv, o, rot, wreck)
			_wrecker_bed(cv, o, rot, body, wreck)
			_boom(cv, o, rot, wreck)
	cv.outline(Color(0.08, 0.07, 0.06, 1))


static func _cab(cv, o: Vector2, rot: float, body: Color, wreck: bool) -> void:
	T._cab(cv, o, rot, body, wreck)
	if wreck:
		return
	# industrial touches: brush guard bars across the front, a rust patch on each door
	var a := D.sp(o, rot, 0.53, -0.2, 6)
	var b := D.sp(o, rot, 0.53, 0.2, 6)
	cv.line_v(a, b, Color8(70, 66, 58))
	cv.line_v(a + Vector2(0, 3), b + Vector2(0, 3), Color8(58, 54, 48))
	var sp := D.sp(o, rot, 0.36, 0.0, 15)
	V.soot(cv, D.sp(o, rot, 0.18, 0.19, 16.5), 2.5, 702)
	cv.px(int(sp.x), int(sp.y), Color8(210, 120, 50))  # amber roof beacon


static func _bed_box(cv, o: Vector2, rot: float, body: Color, wreck: bool, hz: float, s: int) -> Dictionary:
	var r: Dictionary = P.box(cv, o, D.w(rot, -0.2, 0.0, 4.5), 0.34, 0.23, hz, rot, body, 0.09, s)
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		if not wreck:
			if absf((sd.n as Vector2).dot(Vector2(cos(rot), sin(rot)))) < 0.3:
				cv.team = true
				cv.poly(P.sub(q, 0.04, 0.5, 0.96, 0.85), Color(0.64, 0.64, 0.64))
				cv.team = false
			V.rivets(cv, q, 0.3, 6, body)
			D.mud(cv, q, 710 + int(q[0].x), 0.3)
	D.contact_ao(cv, r)
	if wreck:
		V.scorch(cv, r.top)
	else:
		D.box_edges(cv, r, body, 711)
	return r


static func _flatbed(cv, o: Vector2, rot: float, body: Color, wreck: bool) -> void:
	var r := _bed_box(cv, o, rot, body, wreck, 2.5, 712)
	cv.poly(P.sub(r.top, 0.04, 0.06, 0.96, 0.94), P.mul(body, 0.62) if not wreck else T.CHAR)
	# rear stabiliser spades (down to the ground behind the rear axle)
	for s in [-1, 1]:
		var top := D.sp(o, rot, -0.52, 0.2 * s, 6)
		var bot := D.sp(o, rot, -0.62, 0.24 * s, 0)
		cv.line_v(top, bot, Color8(58, 56, 50))
		cv.rect(int(bot.x) - 1, int(bot.y), 3, 1, Color8(46, 44, 40))
	# shell crates at the back of the bed
	var cr: Dictionary = P.box(cv, o, D.w(rot, -0.44, 0.0, 7), 0.08, 0.17, 3.5, rot, WOOD if not wreck else T.CHAR, 0.07, 713)
	for sd in cr.sides:
		cv.line_v(sd.quad[0].lerp(sd.quad[1], 0.5), sd.quad[3].lerp(sd.quad[2], 0.5), P.mul(WOOD, 0.7))
	# gun cradle / turntable
	var g: Dictionary = P.box(cv, o, D.w(rot, -0.18, 0.0, 7), 0.15, 0.15, 4.0, rot, GUNMETAL if not wreck else V.BURNT, 0.06, 714)
	if not wreck:
		D.box_edges(cv, g, GUNMETAL, 715, 0.3)
		for sd in g.sides:
			V.rivets(cv, sd.quad, 0.7, 3, GUNMETAL)


static func _howitzer(cv, o: Vector2, rot: float, f: int, wreck: bool) -> void:
	var col: Color = GUNMETAL if not wreck else V.BURNT
	var rec := 0.08 if f == 2 else 0.0
	var elev := 12.0 if not wreck else 2.0
	var a := D.w(rot, -0.3 - rec, 0.0, 12.0)
	var b := D.w(rot, 0.58 - rec, 0.0, 12.0 + elev)
	var pa := P.proj(o, a)
	var pb := P.proj(o, b)
	# trunnion side plates
	for s in [-1, 1]:
		var t := D.sp(o, rot, -0.18, 0.11 * s, 11)
		cv.rect(int(t.x) - 1, int(t.y) - 2, 3, 4, P.mul(col, 0.85))
	# recuperator under the tube, then the tube itself (3 px thick, lit top edge)
	cv.line_v(pa + Vector2(0, 2), pa.lerp(pb, 0.55) + Vector2(0, 2), P.mul(col, 0.7))
	cv.line_v(pa + Vector2(0, 1), pb + Vector2(0, 1), P.mul(col, 0.8))
	cv.line_v(pa, pb, col)
	cv.line_v(pa + Vector2(0, -1), pb + Vector2(0, -1), P.mul(col, 1.3))
	# muzzle brake
	cv.rect(int(pb.x) - 1, int(pb.y) - 2, 3, 4, P.mul(col, 1.1))
	cv.px(int(pb.x), int(pb.y) - 1, D.DARK)
	if not wreck:
		cv.team = true
		var m := pa.lerp(pb, 0.3)
		cv.rect(int(m.x) - 1, int(m.y) - 1, 3, 2, Color(0.7, 0.7, 0.7))  # painted cradle band
		cv.team = false
	if f == 2 and not wreck:
		var tip := pb + (pb - pa).normalized() * 3.0
		cv.ellipse(tip.x, tip.y, 3.2, 2.4, Color8(255, 226, 140))
		cv.ellipse(tip.x, tip.y, 1.6, 1.2, Color8(255, 255, 230))
		cv.ellipse(pa.x, pa.y + 4, 3.0, 1.6, Color(0.75, 0.72, 0.66, 0.6))  # breech smoke


static func _wrecker_bed(cv, o: Vector2, rot: float, body: Color, wreck: bool) -> void:
	var r := _bed_box(cv, o, rot, body, wreck, 3.5, 720)
	cv.poly(P.sub(r.top, 0.04, 0.06, 0.96, 0.94), P.mul(body, 0.55) if not wreck else T.CHAR)
	# spare tyre lying flat, toolbox, two gas bottles; back-to-front by screen depth
	var items := [[-0.05, -0.1, "tyre"], [-0.08, 0.12, "box"], [-0.36, 0.15, "bottle"], [-0.3, 0.17, "bottle"]]
	items.sort_custom(func(p, q):
		var wp := D.w(rot, p[0], p[1])
		var wq := D.w(rot, q[0], q[1])
		return wp.x + wp.y < wq.x + wq.y)
	for it in items:
		var c := D.sp(o, rot, it[0], it[1], 8)
		match String(it[2]):
			"tyre":
				cv.ellipse(c.x, c.y, 4.5, 2.4, D.RUBBER if not wreck else T.CHAR)
				cv.ellipse(c.x, c.y, 2.0, 1.0, D.RIM if not wreck else V.BURNT)
			"box":
				var bx: Dictionary = P.box(cv, o, D.w(rot, it[0], it[1], 8), 0.08, 0.06, 3.0, rot, Color8(150, 60, 40) if not wreck else T.CHAR, 0.06, 721)
				if not wreck:
					D.box_edges(cv, bx, Color8(150, 60, 40), 722, 0.3)
			_:
				var top := D.sp(o, rot, it[0], it[1], 15)
				cv.rect(int(c.x) - 1, int(top.y), 2, int(c.y - top.y), BOTTLE if not wreck else T.CHAR)
				cv.px(int(top.x) - 1, int(top.y), Color8(150, 150, 140))


static func _boom(cv, o: Vector2, rot: float, wreck: bool) -> void:
	var col: Color = BOOM if not wreck else V.BURNT
	var base := D.w(rot, -0.2, 0.0, 9.0)
	var tip := D.w(rot, -0.62, 0.0, 26.0) if not wreck else D.w(rot, -0.55, 0.15, 11.0)
	var pb := P.proj(o, base)
	var pt := P.proj(o, tip)
	# A-frame legs from the bed corners to the boom head
	for s in [-1, 1]:
		var leg := D.sp(o, rot, -0.42, 0.18 * s, 8)
		cv.line_v(leg, pt, P.mul(col, 0.8))
	cv.line_v(pb + Vector2(0, 1), pt + Vector2(0, 1), P.mul(col, 0.7))
	cv.line_v(pb, pt, col)
	if not wreck:  # hazard chevrons along the boom
		for i in 4:
			var p := pb.lerp(pt, 0.2 + i * 0.2)
			cv.px(int(p.x), int(p.y), HAZARD if i % 2 == 0 else Color8(40, 38, 34))
		var hook := pt + Vector2(0, 10)
		cv.line_v(pt + Vector2(0, 1), hook, Color8(40, 40, 36))   # cable
		cv.rect(int(hook.x) - 1, int(hook.y), 3, 1, Color8(80, 80, 76))
		cv.px(int(hook.x) + 1, int(hook.y) + 1, Color8(80, 80, 76))
		cv.px(int(pt.x), int(pt.y) - 1, Color8(220, 140, 60))     # boom-head lamp
