extends RefCounted
## DL7 facility sample (owner: ARTCN7; G7_REFERENCE 6.2, 6.12): enough of the Counter-Nanite facility to judge
## the look. Buildings (g7_cn_lib.bld = g6_lib rot set + extra states on rotation 0):
##   g7_cn_gate     fortified outer gate + checkpoint: blast walls, armoured gate leaves, anti-vehicle wedges,
##                  hardened tower with remote weapon station + counter-drone emitter      (+ open)
##   g7_cn_decon    decontamination zone: APC wash-down bay + soldier walkway with scan arches (+ active)
##   g7_cn_garage   APC garage bay with armoured roll-up door                          (+ open, lockdown)
##   g7_cn_helipad  helipad fitted to the stealth strike dropship, blast deflectors      (+ lit)
const P = preload("res://tools/art/pix.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")

const CONC := Color8(150, 148, 138)
const CONC_D := Color8(112, 112, 106)
const STEEL := Color8(84, 90, 96)
const WALL := Color8(128, 126, 114)
const PAD := Color8(96, 98, 96)
const WATER := Color(0.55, 0.75, 0.95, 0.45)
const MIST := Color(0.85, 0.92, 1.0, 0.35)
const SCANB := Color(1.0, 0.75, 0.35, 0.55)
const LAMP_G := Color8(150, 255, 170)
const LAMP_R := Color8(255, 70, 50)
const LAMP_W := Color8(255, 244, 210)


## Boxes are collected then drawn far to near: [u, v, z, hx, hy, hz, ramp, top_t, team].
static func draw_boxes(cv, o: Vector2, f: int, boxes: Array) -> void:
	var w0 := K.wp(f, 0.0, 0.0)
	var wx := K.wp(f, 1.0, 0.0) - w0
	var yaw := atan2(wx.y, wx.x)
	var items: Array = []
	for b in boxes:
		var w := K.wp(f, b[0], b[1])
		items.append([w.x + w.y + float(b[2]) * 0.1, w, b])
	items.sort_custom(func(x, y): return x[0] < y[0])
	for it in items:
		var b: Array = it[2]
		var w: Vector2 = it[1]
		var res := C.box(cv, o, Vector3(w.x, w.y, b[2]), b[3], b[4], b[5], yaw, b[6], b[7], true, b[8])
		if float(b[5]) >= 10.0:   # panel seams on walls and towers
			var rp: Array = b[6]
			for sd in res.sides:
				var q: PackedVector2Array = sd.quad
				var n := maxi(1, int(q[0].distance_to(q[1]) / 9.0))
				for i in range(1, n):
					var t := float(i) / n
					cv.line_v(q[0].lerp(q[1], t), q[3].lerp(q[2], t), rp[1])
				cv.line_v(q[0].lerp(q[3], 0.85), q[1].lerp(q[2], 0.85), rp[3])


static func _stripes(cv, o: Vector2, f: int, u0: float, v0: float, u1: float, v1: float, z: float, n: int) -> void:
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		cv.line_v(K.pt(o, f, lerpf(u0, u1, t0), lerpf(v0, v1, t0), z), K.pt(o, f, lerpf(u0, u1, t1), lerpf(v0, v1, t1), z),
			GR.HAZ if i % 2 == 0 else GR.HAZ_D)


static func gate(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	K.gquad(cv, o, f, -1.45, -1.45, 1.45, 1.45, 0.0, C.ramp(CONC_D)[2])
	_stripes(cv, o, f, 1.2, -0.6, 1.2, 0.6, 0.0, 8)
	var wl := C.ramp(WALL)
	var st := C.ramp(STEEL)
	var open := bool(opt.get("open", false))
	var bx: Array = [[0.0, -1.1, 0.0, 0.32, 0.3, 26.0, wl, 3, false], [0.0, 1.1, 0.0, 0.32, 0.3, 26.0, wl, 3, false],
		[-0.9, -1.1, 0.0, 0.55, 0.22, 18.0, wl, 3, false], [-0.9, 1.1, 0.0, 0.55, 0.22, 18.0, wl, 3, false],
		[0.0, -1.1, 26.0, 0.36, 0.34, 3.0, st, 3, false], [0.0, -1.1, 29.0, 0.1, 0.1, 0.5, C.ramp(Color8(150, 150, 150)), 3, true], [0.0, 1.1, 26.0, 0.36, 0.34, 3.0, st, 3, false]]
	if open:
		bx.append([0.0, -0.66, 0.0, 0.05, 0.15, 16.0, st, 3, false])
		bx.append([0.0, 0.66, 0.0, 0.05, 0.15, 16.0, st, 3, false])
	else:
		bx.append([0.0, -0.4, 0.0, 0.07, 0.4, 16.0, st, 3, false])
		bx.append([0.0, 0.4, 0.0, 0.07, 0.4, 16.0, st, 3, false])
	for v in [-0.6, 0.0, 0.6]:   # anti-vehicle wedges
		bx.append([1.05, v, 0.0, 0.1, 0.1, 5.0, C.ramp(CONC), 3, false])
	draw_boxes(cv, o, f, bx)
	# remote weapon station + counter-drone emitter on the towers
	var rws := K.pt(o, f, 0.0, -1.1, 31.0)
	C.blob(cv, rws, 2.2, C.ramp(Color8(70, 76, 70)))
	var mz := K.pt(o, f, 0.45, -1.1, 31.0)
	C.tube(cv, rws, mz, 0.6, C.ramp(GR.GUNM))
	if bool(opt.get("fire", false)):
		C.blob(cv, mz + (mz - rws).normalized() * 2.0, 1.5, [GR.FLASH_O, GR.FLASH_O, GR.FLASH, GR.FLASH, GR.FLASH])
	var em := K.pt(o, f, 0.0, 1.1, 32.0)
	cv.ellipse(em.x, em.y, 3.5, 2.0, C.ramp(Color8(170, 180, 190))[3])
	cv.px(int(em.x), int(em.y), Color8(150, 200, 255))
	for s in [-1.0, 1.0]:
		var lp := K.pt(o, f, 0.33, s * 0.8, 12.0)
		cv.px(int(lp.x), int(lp.y), LAMP_G if open else LAMP_R)


static func decon(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var on := bool(opt.get("active", false))
	K.gquad(cv, o, f, -1.45, -1.45, 1.45, 1.45, 0.0, C.ramp(CONC)[2])
	K.gquad(cv, o, f, -1.3, -1.3, 1.3, 0.05, 0.0, C.ramp(PAD)[1])        # wash bay
	K.gquad(cv, o, f, -1.3, 0.45, 1.3, 1.15, 0.0, C.ramp(Color8(176, 176, 168))[2])   # walkway
	_stripes(cv, o, f, -1.3, 0.45, 1.3, 0.45, 0.0, 12)
	if on:
		K.gquad(cv, o, f, -1.2, -1.2, 1.2, -0.05, 0.3, WATER)
	var st := C.ramp(STEEL)
	var bx: Array = []
	for u in [-1.0, 1.0]:   # wash gantry posts
		bx.append([u, -1.25, 0.0, 0.06, 0.06, 22.0, st, 3, false])
		bx.append([u, 0.15, 0.0, 0.06, 0.06, 22.0, st, 3, false])
		bx.append([u, -0.55, 22.0, 0.07, 0.76, 3.0, st, 3, false])
	bx.append([1.0, -0.55, 25.0, 0.06, 0.22, 0.5, C.ramp(Color8(150, 150, 150)), 3, true])   # team sign
	for u in [-0.8, 0.0, 0.8]:   # scan arches over the walkway
		bx.append([u, 0.42, 0.0, 0.05, 0.05, 14.0, C.ramp(Color8(196, 196, 186)), 3, false])
		bx.append([u, 1.18, 0.0, 0.05, 0.05, 14.0, C.ramp(Color8(196, 196, 186)), 3, false])
		bx.append([u, 0.8, 14.0, 0.06, 0.43, 2.0, C.ramp(Color8(196, 196, 186)), 3, false])
	draw_boxes(cv, o, f, bx)
	for u in [-0.8, 0.0, 0.8]:
		var a := K.pt(o, f, u, 0.8, 14.0)
		cv.px(int(a.x), int(a.y) + 1, LAMP_G if not on else Color8(255, 196, 96))
		if on:
			cv.line_v(a + Vector2(0, 2), K.pt(o, f, u, 0.8, 0.5), SCANB)
	if on:
		for i in 10:
			var p := K.pt(o, f, -0.9 + i * 0.2, -0.55 + sin(i * 1.7) * 0.4, 18.0 - (i % 3) * 4.0)
			cv.ellipse(p.x, p.y, 4.0, 2.5, MIST)


static func garage(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	# DL7-3 scale (fact art.scale): a 12 m x 6.4 m x 4.9 m bay on a 3 x 3 tile lot, door 3.8 m wide x 3.9 m high,
	# so the 8 m x 2.9 m strike APC (3.3 m over its gunner pods) drives in.
	K.gquad(cv, o, f, -1.45, -1.45, 1.45, 1.45, 0.0, C.ramp(CONC_D)[2])
	var lock := bool(opt.get("lockdown", false))
	var bx: Array = [[-0.15, 0.0, 0.0, 1.2, 0.8, 44.0, C.ramp(WALL), 3, false],
		[-0.15, 0.0, 44.0, 1.1, 0.7, 4.0, C.ramp(STEEL), 3, false], [-0.7, 0.3, 48.0, 0.2, 0.16, 0.6, C.ramp(Color8(150, 150, 150)), 3, true],
		[0.2, -0.3, 48.0, 0.25, 0.2, 5.0, C.ramp(STEEL), 3, true]]
	draw_boxes(cv, o, f, bx)
	var d0 := K.pt(o, f, 1.06, -0.48, 0.0)
	var d1 := K.pt(o, f, 1.06, 0.48, 0.0)
	var top := 38.0 if not bool(opt.get("open", false)) else 4.0
	var door := PackedVector2Array([d0, d1, d1 + Vector2(0, -38), d0 + Vector2(0, -38)])
	if K.wp(f, 1.0, 0.0).x + K.wp(f, 1.0, 0.0).y > 0.0:
		C.face(cv, door, C.ramp(Color8(24, 26, 28)), 2)
		if bool(opt.get("open", false)):
			var m := (d0 + d1) * 0.5 + Vector2(0, -12)
			cv.rect(int(m.x) - 9, int(m.y) - 4, 19, 14, C.ramp(Color8(150, 150, 136))[1])
			for q in [-6, 6]:
				cv.px(int(m.x) + q, int(m.y) + 6, LAMP_W)
		var dr := PackedVector2Array([d0 + Vector2(0, -38), d1 + Vector2(0, -38), d1 + Vector2(0, -top), d0 + Vector2(0, -top)])
		if top > 4.0:
			C.face(cv, dr, C.ramp(Color8(164, 66, 50) if lock else STEEL), 2)
			for i in 12:
				var y := -top + 3.0 * i
				cv.line_v(d0 + Vector2(0, y), d1 + Vector2(0, y), C.ramp(STEEL)[0])
		_stripes(cv, o, f, 1.07, -0.48, 1.07, 0.48, 39.0, 10)
	for s in [-1.0, 1.0]:
		var lp := K.pt(o, f, 1.07, s * 0.6, 41.0)
		cv.px(int(lp.x), int(lp.y), LAMP_R if lock else LAMP_W)


## Helipad sized to the DL7-2 dropships (6 x 6 tiles): the craft (nose +2.6 .. ramp foot -2.6 along u, span
## +-2.35) sits on the painted outline with the ramp lowered; edge lights, centre cross, corner blast shields.
## Drawn rotation-symmetric (rot_1..3 alias rot_0).
static func helipad(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var lit := bool(opt.get("lit", false))
	K.gquad(cv, o, f, -2.95, -2.95, 2.95, 2.95, 0.0, C.ramp(CONC_D)[1])
	K.gquad(cv, o, f, -2.75, -2.75, 2.75, 2.75, 0.5, C.ramp(PAD)[2])
	for i in 9:   # expansion joints
		var t := -2.75 + i * 0.6875
		cv.line_v(K.pt(o, f, t, -2.75, 0.55), K.pt(o, f, t, 2.75, 0.55), C.ramp(PAD)[1])
		cv.line_v(K.pt(o, f, -2.75, t, 0.55), K.pt(o, f, 2.75, t, 0.55), C.ramp(PAD)[1])
	for i in 40:   # perimeter edge lights
		var t := float(i) / 40.0 * 4.0
		var e: Vector2
		if t < 1.0:
			e = Vector2(-2.75 + t * 5.5, -2.75)
		elif t < 2.0:
			e = Vector2(2.75, -2.75 + (t - 1.0) * 5.5)
		elif t < 3.0:
			e = Vector2(2.75 - (t - 2.0) * 5.5, 2.75)
		else:
			e = Vector2(-2.75, 2.75 - (t - 3.0) * 5.5)
		var p := K.pt(o, f, e.x, e.y, 1.0)
		cv.px(int(p.x), int(p.y), LAMP_W if lit else Color8(140, 120, 70))
	var yel := Color8(226, 184, 40)
	var shape := [Vector2(2.45, 0), Vector2(1.55, -0.62), Vector2(1.15, -0.75), Vector2(0.75, -0.75), Vector2(-0.33, -1.46),
		Vector2(-0.88, -1.46), Vector2(-1.4, -0.75), Vector2(-1.5, -0.75), Vector2(-1.5, -0.45), Vector2(-2.45, -0.45),
		Vector2(-2.45, 0.45), Vector2(-1.5, 0.45), Vector2(-1.5, 0.75), Vector2(-1.4, 0.75), Vector2(-0.88, 1.46),
		Vector2(-0.33, 1.46), Vector2(0.75, 0.75), Vector2(1.15, 0.75), Vector2(1.55, 0.62)]
	for i in shape.size():   # DL7-3 dropship + lowered-ramp outline (craft centred on the pad)
		var a: Vector2 = shape[i]
		var b: Vector2 = shape[(i + 1) % shape.size()]
		cv.line_v(K.pt(o, f, a.x, a.y, 0.6), K.pt(o, f, b.x, b.y, 0.6), yel)
	for fc in [Vector3(1.32, -1.11, 0.25), Vector3(1.32, 1.11, 0.25), Vector3(-0.6, -1.78, 0.31), Vector3(-0.6, 1.78, 0.31)]:
		for i in 10:   # lift-fan blast circles
			var t0 := TAU * i / 10.0
			var t1 := TAU * (i + 1) / 10.0
			cv.line_v(K.pt(o, f, fc.x + cos(t0) * fc.z, fc.y + sin(t0) * fc.z, 0.6), K.pt(o, f, fc.x + cos(t1) * fc.z, fc.y + sin(t1) * fc.z, 0.6), yel)
	for i in 5:   # ramp chevrons
		var u := -1.65 - i * 0.17
		cv.line_v(K.pt(o, f, u + 0.1, -0.35, 0.6), K.pt(o, f, u, 0.0, 0.6), yel)
		cv.line_v(K.pt(o, f, u, 0.0, 0.6), K.pt(o, f, u + 0.1, 0.35, 0.6), yel)
	cv.line_v(K.pt(o, f, -0.4, 0.0, 0.6), K.pt(o, f, 0.4, 0.0, 0.6), Color8(232, 230, 222))
	cv.line_v(K.pt(o, f, 0.0, -0.4, 0.6), K.pt(o, f, 0.0, 0.4, 0.6), Color8(232, 230, 222))
	var bx: Array = []
	for c in [Vector2(-2.85, -2.85), Vector2(2.85, -2.85), Vector2(2.85, 2.85), Vector2(-2.85, 2.85)]:
		bx.append([c.x, c.y, 0.0, 0.1, 0.1, 6.0, C.ramp(Color8(196, 150, 60)), 3, true])
	draw_boxes(cv, o, f, bx)


static func build(out: Dictionary) -> void:
	var g := {"sample": "facility"}
	C.bld(out, "g7_cn_gate", 3, 44, "building", func(cv, o, f, opt): gate(cv, o, f, opt), [["open", {"open": true}]],
		g.merged({"key_frames": ["built", "open", "fire", "damaged"], "anim_strip": ["build_0", "build_1", "build_2", "built", "open", "fire", "rot_1", "rot_2", "rot_3", "damaged"]}))
	C.bld(out, "g7_cn_decon", 3, 34, "building", func(cv, o, f, opt): decon(cv, o, f, opt), [["active", {"active": true}]],
		g.merged({"key_frames": ["built", "active"], "anim_strip": ["build_0", "build_1", "build_2", "built", "active", "built", "active", "rot_1", "rot_2", "damaged"]}))
	C.bld(out, "g7_cn_garage", 3, 64, "building", func(cv, o, f, opt): garage(cv, o, f, opt),
		[["open", {"open": true}], ["lockdown", {"lockdown": true}]], g.merged({"key_frames": ["built", "open", "lockdown"], "anim_strip": ["build_0", "build_1", "build_2", "built", "open", "built", "lockdown", "rot_1", "rot_3", "damaged"]}))
	C.bld(out, "g7_cn_helipad", 6, 20, "building", func(cv, o, f, opt): helipad(cv, o, f, opt), [["lit", {"lit": true}]],
		g.merged({"key_frames": ["built", "lit"], "anim_strip": ["build_0", "build_1", "build_2", "built", "lit", "built", "lit", "rot_1", "rot_2", "damaged"],
		"fits": "g7_cn_stealth_dropship / g7_a_vtol_dropship_xl, craft centre (sprite pivot) at the pad centre (0, 0), nose +u to +2.45, ramp foot at -2.45, fans at (+1.32, +-1.11) and (-0.6, +-1.78) tiles (DL7-3)"}), true)
