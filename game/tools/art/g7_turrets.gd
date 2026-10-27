extends RefCounted
## DL7 sample turrets (owner: ARTCN7; G7_REFERENCE 7): 2 of the 8 new Human A turrets.
##   g7_a_hmg_nest     Heavy MG nest: twin .50 behind an armoured shield in a sandbagged ring.
##   g7_a_rail_cannon  Rail cannon: armoured casemate, long twin-rail barrel, capacitor banks, power trunk.
## Building schema (g7_cn_lib.bld = g6_lib rot set): rot_<f> (+ _damaged, _build_<0..2>, _fire), plus the head
## traverse states aim_<0..7> (yaw k*45 deg on rotation 0) and aim_<k>_fire; the rail cannon adds charge_0/1.
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")
const V = preload("res://tools/art/g7_cn_vehicles.gd")
const FIG = preload("res://tools/art/g7_cn_fig.gd")
const SO = preload("res://tools/art/g7_cn_soldiers.gd")

const SAND := Color8(166, 148, 108)
const ARMOR := Color8(98, 106, 84)
const CONC := Color8(132, 130, 122)
const COIL := Color8(140, 186, 255)
const COIL_HOT := Color8(230, 244, 255)
const CABLE := Color8(36, 38, 40)


static func _yaw(f: int, opt: Dictionary) -> float:
	return float(opt.aim) * PI / 4.0 if opt.has("aim") else float(f) * PI / 2.0 + PI / 4.0


static func hmg(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var by := float(f) * PI / 2.0
	C.ground_shadow(cv, o + Vector2(3, 2), 30.0, 13.0, 0.28)
	var sand := C.ramp(SAND)
	# back half of the sandbag ring, then the gun, then the front half (depth split)
	for pass_i in 2:
		if pass_i == 1:
			_hmg_gun(cv, o, _yaw(f, opt), bool(opt.get("fire", false)))
		for i in 14:
			var t := TAU * float(i) / 14.0 + by
			var front := C.depth(0.0, cos(t), sin(t)) > 0.0
			if front != (pass_i == 1):
				continue
			for layer in 3:
				var c := V.lp(o, 0.0, cos(t) * 0.40, sin(t) * 0.40, 1.5 + layer * 2.6)
				C.blob(cv, c + Vector2((layer % 2) * 1.0, 0), 2.4, sand)


static func _hmg_gun(cv, o: Vector2, yaw: float, fire: bool) -> void:
	V.vbox(cv, o, yaw, 0.0, 0.0, 0.0, 0.07, 0.07, 9.0, C.ramp(V.DARK))
	var rp := C.ramp(ARMOR)
	var parts: Array = [[C.depth(yaw, 0.12, 0.0), "shield"], [C.depth(yaw, -0.10, 0.0), "gunner"],
		[C.depth(yaw, 0.3, 0.0), "guns"]]
	parts.sort_custom(func(x, y): return x[0] < y[0])
	for q in parts:
		match String(q[1]):
			"shield":
				var rs := V.vbox(cv, o, yaw, 0.12, 0.0, 7.0, 0.035, 0.24, 9.0, rp, 3)
				C.hull_detail(cv, rs, rp, 61, {"seams": 2, "rivets": false, "wear": 0.9})
				var s0 := V.lp(o, yaw, 0.16, -0.05, 13.0)
				cv.px(int(s0.x), int(s0.y), Color8(170, 220, 255))   # vision block
			"gunner":
				# rev2 (ARTCN7-3): a real DL7 operator figure (same drawer and scale as the soldier samples,
				# both armbands) crouched behind the shield, facing along the gun, instead of a blob gunner
				var fk := posmod(int(round(yaw / (PI / 4.0))), 8)
				var gk := SO.kit("op_leader")
				gk["pack"] = "small"     # no radio mast sticking out of the nest
				gk["stripe"] = false
				FIG.draw(cv, gk, fk, "crouch", V.lp(o, yaw, -0.17, 0.0, 1.5))
			"guns":
				for s in [-0.06, 0.06]:
					var p0 := V.lp(o, yaw, 0.05, s, 12.5)
					var p1 := V.lp(o, yaw, 0.62, s, 12.5)
					C.tube(cv, p0, p1, 0.75, C.ramp(GR.GUNM))
					C.blob(cv, V.lp(o, yaw, 0.30, s, 12.5), 1.0, C.ramp(GR.GUNM))
					if fire:
						var d := (p1 - p0).normalized() if p1.distance_to(p0) > 0.5 else Vector2(0, 1)
						C.blob(cv, p1 + d * 2.0, 1.6, [GR.FLASH_O, GR.FLASH_O, GR.FLASH, GR.FLASH, GR.FLASH])
						cv.line_v(p1 + d * 2.0, p1 + d * 6.0, GR.FLASH)
				var box := V.lp(o, yaw, 0.0, 0.16, 11.0)
				C.blob(cv, box, 1.5, C.ramp(ARMOR))   # ammo can


static func rail(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var by := float(f) * PI / 2.0
	var yaw := _yaw(f, opt)
	var fire := bool(opt.get("fire", false))
	var charge := int(opt.get("charge", -1))
	C.ground_shadow(cv, o + Vector2(6, 4), 58.0, 25.0, 0.30)
	var conc := C.ramp(CONC)
	var rpad := V.vbox(cv, o, by, 0.0, 0.0, 0.0, 0.82, 0.82, 6.0, conc, 3)          # concrete pad
	C.hull_detail(cv, rpad, conc, 71 + f, {"seams": 4, "top_seams": 4, "rivets": false, "wear": 0.8, "grime": 0.9})
	var arm := C.ramp(ARMOR)
	var rcas := V.vbox(cv, o, by + PI / 4.0, 0.0, 0.0, 6.0, 0.55, 0.55, 7.0, arm, 3, false, Vector2(0.06, 0.06))   # sloped casemate
	C.hull_detail(cv, rcas, arm, 73 + f, {"seams": 3, "top_seams": 3, "wear": 0.6})
	for s in [-1.0, 1.0]:   # capacitor banks + power trunk
		var cap := C.ramp(Color8(80, 86, 92))
		C.hull_detail(cv, V.vbox(cv, o, by, -0.55, s * 0.55, 6.0, 0.14, 0.14, 10.0, cap, 3), cap, 77, {"seams": 2, "rivets": true})
		var led := V.lp(o, by, -0.55, s * 0.55, 16.5)
		cv.px(int(led.x), int(led.y), COIL_HOT if charge >= 0 or fire else COIL)
		cv.line_v(V.lp(o, by, -0.55, s * 0.55, 7.0), V.lp(o, by, -0.2, s * 0.2, 13.0), CABLE)
	# rotating housing
	var rh := V.vbox(cv, o, yaw, -0.1, 0.0, 13.0, 0.36, 0.3, 9.0, arm, 3, false, Vector2(0.05, 0.04))
	C.hull_detail(cv, rh, arm, 79, {"seams": 3, "top_seams": 2, "wear": 0.6})
	V.vbox(cv, o, yaw, -0.25, 0.0, 22.0, 0.1, 0.1, 0.5, C.ramp(Color8(150, 150, 150)), 3, true)
	var parts: Array = []
	for s in [-1.0, 1.0]:
		parts.append([C.depth(yaw, 0.8, s * 0.11), s])
	parts.sort_custom(func(x, y): return x[0] < y[0])
	for q in parts:
		var s: float = q[1]
		var p0 := V.lp(o, yaw, 0.2, s * 0.11, 18.0)
		var p1 := V.lp(o, yaw, 1.55, s * 0.11, 19.0)
		C.tube(cv, p0, p1, 1.1, C.ramp(Color8(70, 74, 80)))
		for i in 6:   # coil rings along the rail
			var c := p0.lerp(p1, 0.12 + i * 0.15)
			var hot := fire or (charge >= 0 and i <= 2 + charge * 3)
			cv.px(int(c.x), int(c.y) - 1, COIL_HOT if hot else COIL)
	var tip := V.lp(o, yaw, 1.6, 0.0, 19.0)
	var d := (V.lp(o, yaw, 1.6, 0.0, 19.0) - V.lp(o, yaw, 0.2, 0.0, 18.0)).normalized()
	if fire:
		C.blob(cv, tip + d * 2.5, 2.6, [COIL, COIL, COIL_HOT, COIL_HOT, Color(1, 1, 1)])
		cv.line_v(tip + d * 3.0, tip + d * 40.0, COIL_HOT)
		cv.line_v(tip + d * 3.0 + Vector2(0, 1), tip + d * 34.0 + Vector2(0, 1), Color(COIL, 0.6))
	elif charge >= 0:
		for i in 3 + charge * 3:
			var c := tip + d * float(i) * 0.6 + Vector2(sin(i * 2.1) * 2.0, cos(i * 1.7) * 2.0)
			cv.px(int(c.x), int(c.y), COIL_HOT)


static func build(out: Dictionary) -> void:
	var hx: Array = []
	var rx: Array = [["charge_0", {"charge": 0}], ["charge_1", {"charge": 1}]]
	for k in 8:
		hx.append(["aim_%d" % k, {"aim": k}])
		hx.append(["aim_%d_fire" % k, {"aim": k, "fire": true}])
		rx.append(["aim_%d" % k, {"aim": k}])
		rx.append(["aim_%d_fire" % k, {"aim": k, "fire": true}])
	C.bld(out, "g7_a_hmg_nest", 1, 30, "turret", func(cv, o, f, opt): hmg(cv, o, f, opt), hx,
		{"sample": "turret", "key_frames": ["aim_0", "aim_2", "aim_4", "aim_6", "aim_0_fire"],
		"anim_strip": ["aim_0", "aim_1", "aim_2", "aim_2_fire", "aim_3", "aim_4", "aim_4_fire", "aim_5", "aim_6", "aim_7_fire"]})
	C.bld(out, "g7_a_rail_cannon", 2, 40, "turret", func(cv, o, f, opt): rail(cv, o, f, opt), rx,
		{"sample": "turret", "key_frames": ["aim_0", "charge_0", "charge_1", "aim_0_fire"],
		"anim_strip": ["aim_0", "aim_1", "aim_2", "charge_0", "charge_1", "aim_2_fire", "aim_3", "aim_4", "aim_5", "aim_6"]})
