extends SceneTree
## G7 eight Human A turrets (owner: TURRET7; G7_REFERENCE section 7), drawn on ARTCN7-2's detail level through
## tools/art/g7_cn_lib.gd (C.DL / C.bld: rot_<f> + _fire + _damaged + _build_<0..2> per rotation, team masks).
## Ids match content/g7/defs_g7_turrets.json (a_t7_*), so the building art group maps 1:1 to the defs.
## Extra states per turret: aim_<0..7> (head traverse, yaw k*45 deg), aim_<k>_fire (recoil + muzzle/beam; every k for
## size-1 turrets, even k for size-2 to stay inside the turret budget), recoil (aim_0, barrel back, no flash),
## impact_0/impact_1 (the turret's own impact effect: tracer hits, HE burst, EMP ring, thermite splash, microwave
## shimmer, rail strike), and per-kind extras (rail charge_0/1, EMP charge_0/1).
## Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g7_turrets2.gd [-- --out=<abs dir>]   (default assets/art/g7_turrets2/)
## Prints "G7_ART <id> bytes=<n> budget=<n> ok|OVER" per turret and "G7_ART group=g7_turrets2 files=<n> over=<n>".
const GEN = preload("res://tools/gen_art.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")
const V = preload("res://tools/art/g7_cn_vehicles.gd")

const SAND := Color8(166, 148, 108)
const ARMOR := Color8(98, 106, 84)
const ARMOR_D := Color8(74, 80, 66)
const CONC := Color8(132, 130, 122)
const STEEL := Color8(84, 90, 96)
const DIRT := Color8(110, 92, 70)
const COIL := Color8(140, 186, 255)
const COIL_HOT := Color8(230, 244, 255)
const CABLE := Color8(36, 38, 40)
const MW := Color8(255, 236, 160)
const HAZ := Color8(226, 184, 40)


static func _yaw(f: int, opt: Dictionary) -> float:
	return float(opt.aim) * PI / 4.0 if opt.has("aim") else float(f) * PI / 2.0 + PI / 4.0


static func _rc(opt: Dictionary) -> float:
	return 0.08 if bool(opt.get("fire", false)) or bool(opt.get("recoil", false)) else 0.0


static func _dir(o: Vector2, yaw: float, z: float) -> Vector2:
	var d := V.lp(o, yaw, 1.0, 0.0, z) - V.lp(o, yaw, 0.0, 0.0, z)
	return d.normalized() if d.length() > 0.5 else Vector2(0, 1)


static func _flash(cv, tip: Vector2, d: Vector2, s: float) -> void:
	C.blob(cv, tip + d * 2.0 * s, 1.6 * s, [GR.FLASH_O, GR.FLASH_O, GR.FLASH, GR.FLASH, GR.FLASH])
	cv.line_v(tip + d * 2.0 * s, tip + d * 6.0 * s, GR.FLASH)
	cv.px(int(tip.x + d.y * 2.0), int(tip.y - d.x * 2.0), GR.FLASH_O)
	cv.px(int(tip.x - d.y * 2.0), int(tip.y + d.x * 2.0), GR.FLASH_O)


## Barrel from u0 to u1 (tiles, along yaw) at side offset v and height z, pulled back by rc; flash at the tip on fire.
static func _barrel(cv, o: Vector2, yaw: float, u0: float, u1: float, v: float, z: float, r: float, rc: float,
		fire: bool, fs := 1.0) -> Vector2:
	var p0 := V.lp(o, yaw, u0 - rc, v, z)
	var p1 := V.lp(o, yaw, u1 - rc, v, z)
	C.tube(cv, p0, p1, r, C.ramp(GR.GUNM))
	if fire:
		_flash(cv, p1, _dir(o, yaw, z), fs)
	return p1


static func _sandbags(cv, o: Vector2, by: float, rad: float, layers: int, front: bool) -> void:
	var sand := C.ramp(SAND)
	for i in 16:
		var t := TAU * float(i) / 16.0 + by
		if (C.depth(0.0, cos(t), sin(t)) > 0.0) != front:
			continue
		for layer in layers:
			var c := V.lp(o, 0.0, cos(t) * rad, sin(t) * rad, 1.5 + layer * 2.6)
			C.blob(cv, c + Vector2((layer % 2) * 1.0, 0), 2.4, sand)


static func _impact(cv, o: Vector2, kind: String, ph: int) -> void:
	var c := o + Vector2(0, -4)
	match kind:
		"emp":
			for i in 24:
				var a := TAU * float(i) / 24.0
				var r := 10.0 + ph * 8.0
				cv.px(int(c.x + cos(a) * r), int(c.y + sin(a) * r * 0.5), GR.EMP if i % 3 != 0 else COIL_HOT)
		"flame":
			C.blob(cv, c, 4.0 + ph * 2.0, [Color8(120, 30, 10), GR.THERM, GR.THERM, GR.FLASH_O, GR.FLASH])
			C.blob(cv, c + Vector2(0, -5 - ph * 3), 2.5, C.ramp(Color8(60, 58, 54)))
		"cone":
			for i in 10:
				cv.px(int(c.x + sin(i * 2.3 + ph) * 6.0), int(c.y + cos(i * 1.7) * 3.0 - i * 0.6), MW)
		"rail":
			C.blob(cv, c, 3.0 + ph * 3.0, [COIL, COIL, COIL_HOT, COIL_HOT, Color(1, 1, 1)])
			for i in 8:
				var a := TAU * float(i) / 8.0 + ph * 0.4
				cv.line_v(c, c + Vector2(cos(a), sin(a) * 0.5) * (6.0 + ph * 4.0), COIL_HOT)
		"he":
			C.blob(cv, c, 3.5 + ph * 2.5, [Color8(90, 70, 50), GR.FLASH_O, GR.FLASH_O, GR.FLASH, GR.FLASH])
			C.blob(cv, c + Vector2(0, -4 - ph * 3), 3.0 + ph, C.ramp(Color8(80, 76, 70)))
		_:
			for i in 5:
				var p := c + Vector2(sin(i * 2.7 + ph) * 4.0, cos(i * 1.9) * 2.0)
				cv.px(int(p.x), int(p.y), GR.FLASH if (i + ph) % 2 == 0 else GR.FLASH_O)


# ------------------------------------------------------------------ 1 Heavy MG nest (size 1)
static func hmg(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "mg", int(opt.impact))
		return
	var by := float(f) * PI / 2.0
	var yaw := _yaw(f, opt)
	var fire := bool(opt.get("fire", false))
	C.ground_shadow(cv, o + Vector2(3, 2), 30.0, 13.0, 0.28)
	_sandbags(cv, o, by, 0.42, 3, false)
	V.vbox(cv, o, yaw, 0.0, 0.0, 0.0, 0.07, 0.07, 9.0, C.ramp(GR.METAL))   # pintle
	V.vbox(cv, o, yaw, 0.13, 0.0, 7.0, 0.035, 0.25, 9.0, C.ramp(ARMOR), 3, true)   # gun shield (team top)
	var g := V.lp(o, yaw, -0.14, 0.0, 15.0)
	C.blob(cv, g + Vector2(0, 2), 2.0, C.ramp(Color8(108, 112, 86)))
	C.blob(cv, g + Vector2(0, -1), 1.7, C.ramp(Color8(86, 92, 70)))
	for s in [-0.06, 0.06]:
		_barrel(cv, o, yaw, 0.05, 0.66, s, 12.5, 0.75, _rc(opt) * 0.5, fire)
	C.blob(cv, V.lp(o, yaw, 0.0, 0.17, 11.0), 1.5, C.ramp(ARMOR_D))   # ammo can
	_sandbags(cv, o, by, 0.42, 3, true)


# ------------------------------------------------------------------ 2 Autocannon turret (size 1)
static func autocannon(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "he" if int(opt.impact) == 1 else "mg", int(opt.impact))
		return
	var by := float(f) * PI / 2.0
	var yaw := _yaw(f, opt)
	var fire := bool(opt.get("fire", false))
	C.ground_shadow(cv, o + Vector2(3, 2), 28.0, 12.0, 0.28)
	V.vbox(cv, o, by, 0.0, 0.0, 0.0, 0.40, 0.40, 5.0, C.ramp(CONC), 3)   # plinth
	V.vbox(cv, o, yaw, 0.0, 0.0, 5.0, 0.10, 0.10, 4.0, C.ramp(GR.METAL))   # ring mount
	V.vbox(cv, o, yaw, -0.04, 0.0, 9.0, 0.24, 0.20, 7.0, C.ramp(ARMOR), 3, true)   # turret head
	V.vbox(cv, o, yaw, -0.18, 0.12, 16.0, 0.05, 0.05, 2.0, C.ramp(STEEL))   # optic
	var tip := _barrel(cv, o, yaw, 0.18, 0.80, 0.0, 12.5, 1.0, _rc(opt), fire, 1.2)
	C.blob(cv, V.lp(o, yaw, 0.74 - _rc(opt), 0.0, 12.5), 1.2, C.ramp(GR.GUNM))   # muzzle brake
	if fire:
		cv.px(int(tip.x), int(tip.y), Color(1, 1, 1))
	V.vbox(cv, o, yaw, -0.06, -0.24, 9.0, 0.08, 0.05, 5.0, C.ramp(ARMOR_D))   # ammo box


# ------------------------------------------------------------------ 3 Hull-down tank turret (size 2)
static func hulldown(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "he", int(opt.impact))
		return
	var by := float(f) * PI / 2.0
	var yaw := _yaw(f, opt)
	var fire := bool(opt.get("fire", false))
	C.ground_shadow(cv, o + Vector2(6, 4), 54.0, 23.0, 0.30)
	V.vbox(cv, o, by, 0.0, 0.0, 0.0, 0.90, 0.90, 3.0, C.ramp(DIRT), 3)   # berm
	V.vbox(cv, o, by, 0.0, 0.0, 3.0, 0.62, 0.62, 5.0, C.ramp(CONC), 3)    # buried casemate roof
	for s in [-1.0, 1.0]:
		V.vbox(cv, o, by, s * 0.62, 0.0, 3.0, 0.06, 0.62, 3.0, C.ramp(Color8(150, 146, 136)), 3)   # chamfers
	V.vbox(cv, o, yaw, -0.08, 0.0, 8.0, 0.48, 0.40, 7.0, C.ramp(ARMOR), 3, true)   # tank turret, team roof
	V.vbox(cv, o, yaw, 0.30, 0.0, 9.0, 0.10, 0.34, 5.0, C.ramp(ARMOR_D))   # mantlet
	V.vbox(cv, o, yaw, -0.30, 0.18, 15.0, 0.08, 0.08, 2.0, C.ramp(STEEL))   # commander cupola
	var tip := _barrel(cv, o, yaw, 0.36, 1.55, 0.0, 12.0, 1.4, _rc(opt) * 2.0, fire, 1.8)
	C.blob(cv, V.lp(o, yaw, 1.1 - _rc(opt) * 2.0, 0.0, 12.0), 1.7, C.ramp(GR.GUNM))   # fume extractor
	if fire:
		C.blob(cv, tip + _dir(o, yaw, 12.0) * 7.0, 3.0, C.ramp(Color8(150, 146, 138)))   # muzzle smoke


# ------------------------------------------------------------------ 4 Auto-mortar pit (size 2)
static func mortar(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "he", int(opt.impact))
		return
	var by := float(f) * PI / 2.0
	var yaw := _yaw(f, opt)
	var fire := bool(opt.get("fire", false))
	C.ground_shadow(cv, o + Vector2(5, 3), 50.0, 21.0, 0.30)
	V.vbox(cv, o, by, 0.0, 0.0, 0.0, 0.85, 0.85, 4.0, C.ramp(CONC), 3)   # pit wall
	V.vbox(cv, o, by, 0.0, 0.0, 1.0, 0.66, 0.66, 3.0, C.ramp(Color8(70, 68, 62)), 3)   # pit floor
	for s in [-1.0, 1.0]:
		V.vbox(cv, o, by, 0.55, s * 0.55, 4.0, 0.12, 0.12, 4.0, C.ramp(ARMOR_D))   # ready-round racks
	V.vbox(cv, o, yaw, 0.0, 0.0, 4.0, 0.30, 0.30, 4.0, C.ramp(ARMOR), 3, true)   # auto-loader turntable (team)
	var rc := _rc(opt) * 1.5
	var p0 := V.lp(o, yaw, -0.1, 0.0, 9.0)
	var p1 := V.lp(o, yaw, 0.30, 0.0, 30.0 - rc * 30.0)   # steep tube: lobs over the walls
	C.tube(cv, p0, p1, 1.6, C.ramp(GR.GUNM))
	C.blob(cv, p0, 2.0, C.ramp(STEEL))
	if fire:
		C.blob(cv, p1 + Vector2(0, -3), 2.6, [GR.FLASH_O, GR.FLASH_O, GR.FLASH, GR.FLASH, GR.FLASH])
		C.blob(cv, p1 + Vector2(1, -9), 3.2, C.ramp(Color8(160, 156, 148)))
	var ant := V.lp(o, yaw, -0.3, -0.25, 8.0)
	cv.line_v(ant, ant + Vector2(0, -14), GR.ANT)   # spotter data-link mast
	cv.px(int(ant.x), int(ant.y) - 15, GR.LED_G)


# ------------------------------------------------------------------ 5 EMP projector (size 1)
static func emp(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "emp", int(opt.impact))
		return
	var by := float(f) * PI / 2.0
	var yaw := _yaw(f, opt)
	var fire := bool(opt.get("fire", false))
	var charge := int(opt.get("charge", -1))
	C.ground_shadow(cv, o + Vector2(3, 2), 28.0, 12.0, 0.28)
	V.vbox(cv, o, by, 0.0, 0.0, 0.0, 0.38, 0.38, 6.0, C.ramp(CONC), 3)
	for s in [-1.0, 1.0]:   # capacitor drums
		V.vbox(cv, o, by, -0.24, s * 0.24, 6.0, 0.09, 0.09, 8.0, C.ramp(STEEL), 3)
		var led := V.lp(o, by, -0.24, s * 0.24, 14.5)
		cv.px(int(led.x), int(led.y), COIL_HOT if fire or charge >= 0 else GR.EMP)
	V.vbox(cv, o, yaw, 0.0, 0.0, 6.0, 0.08, 0.08, 10.0, C.ramp(GR.METAL))   # mast
	var dish := V.lp(o, yaw, 0.06, 0.0, 22.0)
	C.blob(cv, dish, 4.2, C.ramp(Color8(150, 156, 160)), true)   # emitter dish (team rim)
	C.blob(cv, dish + _dir(o, yaw, 22.0) * 1.5, 2.2, C.ramp(Color8(60, 66, 74)))
	if charge >= 0:
		for i in 4 + charge * 4:
			var a := float(i) * 1.7
			cv.px(int(dish.x + cos(a) * 5.0), int(dish.y + sin(a) * 3.0), GR.EMP)
	if fire:
		for i in 28:
			var a := TAU * float(i) / 28.0
			cv.px(int(dish.x + cos(a) * 9.0), int(dish.y + sin(a) * 5.0), GR.EMP if i % 2 == 0 else COIL_HOT)
		C.blob(cv, dish, 2.6, [GR.EMP, GR.EMP, COIL_HOT, COIL_HOT, Color(1, 1, 1)])


# ------------------------------------------------------------------ 6 Thermite flame turret (size 1)
static func thermite(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "flame", int(opt.impact))
		return
	var by := float(f) * PI / 2.0
	var yaw := _yaw(f, opt)
	var fire := bool(opt.get("fire", false))
	C.ground_shadow(cv, o + Vector2(3, 2), 28.0, 12.0, 0.28)
	V.vbox(cv, o, by, 0.0, 0.0, 0.0, 0.40, 0.40, 4.0, C.ramp(CONC), 3)
	for s in [-1.0, 1.0]:   # thermite tanks with hazard bands
		var t0 := V.lp(o, by, -0.22, s * 0.22, 4.0)
		C.tube(cv, t0, t0 + Vector2(0, -10), 2.6, C.ramp(Color8(150, 120, 60)))
		cv.line_v(t0 + Vector2(-2, -5), t0 + Vector2(2, -5), HAZ)
	V.vbox(cv, o, yaw, 0.02, 0.0, 4.0, 0.18, 0.16, 7.0, C.ramp(ARMOR), 3, true)   # armoured projector head
	var tip := _barrel(cv, o, yaw, 0.12, 0.58, 0.0, 9.0, 1.1, 0.0, false)
	cv.px(int(tip.x), int(tip.y), GR.THERM)   # pilot light
	if fire:
		var d := _dir(o, yaw, 9.0)
		for i in 9:
			var c := tip + d * (2.0 + i * 2.6) + Vector2(sin(i * 1.9) * 1.2, -i * 0.4)
			C.blob(cv, c, 1.2 + i * 0.28, [Color8(120, 30, 10), GR.THERM, GR.THERM, GR.FLASH_O, GR.FLASH])


# ------------------------------------------------------------------ 7 Microwave anti-swarm turret (size 1)
static func microwave(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "cone", int(opt.impact))
		return
	var by := float(f) * PI / 2.0
	var yaw := _yaw(f, opt)
	var fire := bool(opt.get("fire", false))
	C.ground_shadow(cv, o + Vector2(3, 2), 28.0, 12.0, 0.28)
	V.vbox(cv, o, by, 0.0, 0.0, 0.0, 0.36, 0.36, 5.0, C.ramp(CONC), 3)
	V.vbox(cv, o, by, -0.2, 0.2, 5.0, 0.10, 0.10, 6.0, C.ramp(STEEL), 3)   # power converter
	V.vbox(cv, o, yaw, 0.0, 0.0, 5.0, 0.07, 0.07, 6.0, C.ramp(GR.METAL))   # yoke
	var q := PackedVector2Array([V.lp(o, yaw, 0.10, -0.22, 10.0), V.lp(o, yaw, 0.10, 0.22, 10.0),
		V.lp(o, yaw, 0.10, 0.22, 22.0), V.lp(o, yaw, 0.10, -0.22, 22.0)])   # flat phased-array panel
	C.face(cv, q, C.ramp(Color8(96, 102, 92)), 2, false, true)
	for i in 3:
		for j in 3:
			var p := C.bil(q, 0.2 + i * 0.3, 0.2 + j * 0.3)
			cv.px(int(p.x), int(p.y), MW if fire else Color8(150, 140, 100))
	if fire:
		var d := _dir(o, yaw, 16.0)
		var m := (q[0] + q[2]) * 0.5
		var n := Vector2(-d.y, d.x)
		for i in 7:
			for k in [-1.0, 0.0, 1.0]:
				var p: Vector2 = m + d * (3.0 + i * 3.2) + n * float(k) * (2.0 + i * 1.4)
				cv.px(int(p.x), int(p.y), Color(MW, 0.85 - i * 0.09))


# ------------------------------------------------------------------ 8 Rail cannon (size 2)
static func rail(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "rail", int(opt.impact))
		return
	var by := float(f) * PI / 2.0
	var yaw := _yaw(f, opt)
	var fire := bool(opt.get("fire", false))
	var charge := int(opt.get("charge", -1))
	C.ground_shadow(cv, o + Vector2(6, 4), 58.0, 25.0, 0.30)
	V.vbox(cv, o, by, 0.0, 0.0, 0.0, 0.84, 0.84, 6.0, C.ramp(CONC), 3)
	V.vbox(cv, o, by + PI / 4.0, 0.0, 0.0, 6.0, 0.55, 0.55, 7.0, C.ramp(ARMOR), 3)
	for s in [-1.0, 1.0]:   # capacitor banks + power trunk
		V.vbox(cv, o, by, -0.58, s * 0.58, 6.0, 0.14, 0.14, 10.0, C.ramp(Color8(80, 86, 92)), 3)
		var led := V.lp(o, by, -0.58, s * 0.58, 16.5)
		cv.px(int(led.x), int(led.y), COIL_HOT if charge >= 0 or fire else COIL)
		cv.line_v(V.lp(o, by, -0.58, s * 0.58, 7.0), V.lp(o, by, -0.2, s * 0.2, 13.0), CABLE)
	V.vbox(cv, o, yaw, -0.1, 0.0, 13.0, 0.36, 0.30, 9.0, C.ramp(ARMOR), 3, true)
	var rc := _rc(opt) * 1.5
	for s in [-1.0, 1.0]:
		var p0 := V.lp(o, yaw, 0.2 - rc, s * 0.11, 18.0)
		var p1 := V.lp(o, yaw, 1.6 - rc, s * 0.11, 19.0)
		C.tube(cv, p0, p1, 1.1, C.ramp(Color8(70, 74, 80)))
		for i in 6:
			var c := p0.lerp(p1, 0.12 + i * 0.15)
			var hot := fire or (charge >= 0 and i <= 2 + charge * 3)
			cv.px(int(c.x), int(c.y) - 1, COIL_HOT if hot else COIL)
	var tip := V.lp(o, yaw, 1.65 - rc, 0.0, 19.0)
	var d := _dir(o, yaw, 19.0)
	if fire:
		C.blob(cv, tip + d * 2.5, 2.6, [COIL, COIL, COIL_HOT, COIL_HOT, Color(1, 1, 1)])
		cv.line_v(tip + d * 3.0, tip + d * 40.0, COIL_HOT)
		cv.line_v(tip + d * 3.0 + Vector2(0, 1), tip + d * 34.0 + Vector2(0, 1), Color(COIL, 0.6))


# ------------------------------------------------------------------ build + generator
const SPECS := [
	["a_t7_hmg_nest", 1, 30, "hmg", []],
	["a_t7_autocannon", 1, 30, "autocannon", []],
	["a_t7_hulldown", 2, 34, "hulldown", []],
	["a_t7_automortar", 2, 40, "mortar", []],
	["a_t7_emp", 1, 40, "emp", [["charge_0", {"charge": 0}], ["charge_1", {"charge": 1}]]],
	["a_t7_thermite", 1, 30, "thermite", []],
	["a_t7_microwave", 1, 36, "microwave", []],
	["a_t7_railgun", 2, 40, "rail", [["charge_0", {"charge": 0}], ["charge_1", {"charge": 1}]]],
]


static func _draw(nm: String) -> Callable:
	match nm:
		"hmg":
			return func(cv, o, f, opt): hmg(cv, o, f, opt)
		"autocannon":
			return func(cv, o, f, opt): autocannon(cv, o, f, opt)
		"hulldown":
			return func(cv, o, f, opt): hulldown(cv, o, f, opt)
		"mortar":
			return func(cv, o, f, opt): mortar(cv, o, f, opt)
		"emp":
			return func(cv, o, f, opt): emp(cv, o, f, opt)
		"thermite":
			return func(cv, o, f, opt): thermite(cv, o, f, opt)
		"microwave":
			return func(cv, o, f, opt): microwave(cv, o, f, opt)
	return func(cv, o, f, opt): rail(cv, o, f, opt)


static func build(out: Dictionary) -> void:
	for sp in SPECS:
		var size := int(sp[1])
		var ex: Array = (sp[4] as Array).duplicate()
		for k in 8:
			ex.append(["aim_%d" % k, {"aim": k}])
			if size == 1 or k % 2 == 0:
				ex.append(["aim_%d_fire" % k, {"aim": k, "fire": true}])
		ex.append(["recoil", {"aim": 0, "recoil": true}])
		ex.append(["impact_0", {"impact": 0}])
		ex.append(["impact_1", {"impact": 1}])
		C.bld(out, String(sp[0]), size, int(sp[2]), "turret", _draw(String(sp[3])), ex,
			{"turret7": String(sp[3]), "key_frames": ["aim_0", "aim_2", "aim_0_fire", "impact_1"],
			"anim_strip": ["aim_0", "aim_1", "aim_2", "aim_2_fire", "aim_3", "aim_4", "aim_4_fire", "recoil", "impact_0", "impact_1"]})


static func generate() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": "g7_turrets2",
		"g7_detail_level": C.DL.duplicate(true)}}
	build(out)
	return out


func _init() -> void:
	var out_dir := "res://assets/art/g7_turrets2/"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6).path_join("g7_turrets2") + "/"
	var r := generate()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var bd := DirAccess.open(ProjectSettings.globalize_path(out_dir).path_join("buildings"))
	if bd != null:
		for fn in bd.get_files():
			if fn.ends_with(".png"):
				bd.remove(fn)
	var files := int(GEN.save(r, out_dir))
	var over := 0
	var man: Dictionary = r.manifest.get("buildings", {})
	var ids: Array = man.keys()
	ids.sort()
	for id in ids:
		var g7: Dictionary = man[id].g7
		var ok := int(g7.bytes) <= int(g7.budget)
		if not ok:
			over += 1
		print("G7_ART %s bytes=%d budget=%d states=%d %s" % [id, int(g7.bytes), int(g7.budget), (man[id].states as Dictionary).size(), "ok" if ok else "OVER"])
	print("G7_ART group=g7_turrets2 files=%d over=%d" % [files, over])
	quit(0)
