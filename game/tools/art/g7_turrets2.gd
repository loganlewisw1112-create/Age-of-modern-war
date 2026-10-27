extends SceneTree
## G7 eight Human A turrets (art: ART7B roll-out of the owner-approved rev3 look, DL7-3; defs: TURRET7,
## G7_REFERENCE section 7). Every turret is modelled in real metres and rasterised by ARTCN7's faceted renderer
## (tools/art/g7_cn_mesh.gd) at the ONE real-world scale (fact art.scale: 4 m per 64x32 tile, 9.8 px per metre of
## height), with crews drawn by the approved soldier figure (g7_cn_fig.gd, 18 px = 1.8 m).
## States per turret through C.bld (g6_lib rot schema): rot_<f> + _fire + _damaged + _build_<0..2>, plus
## aim_<0..7> (head traverse, yaw k*45 deg), aim_<k>_fire (recoil + muzzle / beam; every k for size-1 turrets,
## even k for size-2 to stay inside the turret budget), recoil (aim_0, barrel back, no flash), impact_0/impact_1
## (the turret's own impact effect) and per-kind extras (rail / EMP charge_0/1).
## Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g7_turrets2.gd [-- --out=<abs dir>]   (default assets/art/g7_turrets2/)
## Prints "G7_ART <id> bytes=<n> budget=<n> ok|OVER" per turret and "G7_ART group=g7_turrets2 files=<n> over=<n>".

const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")
const V = preload("res://tools/art/g7_cn_vehicles.gd")
const FIG = preload("res://tools/art/g7_cn_fig.gd")
const SO = preload("res://tools/art/g7_cn_soldiers.gd")

const SAND := Color8(160, 142, 104)
const ARMOR := Color8(98, 106, 84)
const ARMOR_D := Color8(74, 80, 66)
const CONC := Color8(138, 136, 126)
const STEEL := Color8(84, 90, 96)
const DIRT := Color8(110, 92, 70)
const DARK := Color8(46, 50, 52)
const COIL := Color8(140, 186, 255)
const COIL_HOT := Color8(230, 244, 255)
const CABLE := Color8(36, 38, 40)
const MW := Color8(255, 236, 160)
const HAZ := Color8(226, 184, 40)
const TANK := Color8(176, 96, 44)
const CAN := Color8(92, 98, 64)
const GLASS := Color8(70, 120, 140)


static func _yaw(f: int, opt: Dictionary) -> float:
	return float(opt.aim) * PI / 4.0 if opt.has("aim") else float(f) * PI / 2.0 + PI / 4.0


static func _rc(opt: Dictionary) -> float:
	return 0.18 if bool(opt.get("fire", false)) or bool(opt.get("recoil", false)) else 0.0


static func _fin(cv, S: Array, o: Vector2, seed: int) -> void:
	M.shadow(cv, S, o)
	M.render(cv, S, o, seed)


## Team ID marking (mask pixels): the thin plate as geometry + a flat team decal on its outer face, painted after
## the part's faces so larger faces sorted later can never cover it (box faces are painter-sorted per centroid).
static func team_patch(pt: Dictionary, T: Dictionary, c: Vector3, h: Vector3, rp: Array) -> void:
	M.box(pt, T, c, h, rp)
	var ax := 2
	if h.x <= h.y and h.x <= h.z:
		ax = 0
	elif h.y <= h.x and h.y <= h.z:
		ax = 1
	var n := Vector3.ZERO
	n[ax] = 1.0
	var u := Vector3.ZERO
	var v := Vector3.ZERO
	u[(ax + 1) % 3] = h[(ax + 1) % 3]
	v[(ax + 2) % 3] = h[(ax + 2) % 3]
	for s in [1.0, -1.0]:
		var cc: Vector3 = c + n * (h[ax] + 0.004) * s
		M.dpoly(pt, T, [cc - u - v, cc + u - v, cc + u + v, cc - u + v], Color8(152, 152, 152), n * s, true)


## Crew member: the approved DL7 figure (Human A army kit, both armbands) as a depth-sorted sprite at local point
## p of pose T, facing yaw.
static func crew(S: Array, T: Dictionary, p: Vector3, yaw: float, fname: String, kid := "op_marksman") -> void:
	var w := M.wm(T, p)
	var fk := posmod(int(round(yaw / (PI / 4.0))), 8)
	var kit := SO.kit(kid)
	kit["pack"] = "small"
	kit["stripe"] = false
	var o: Vector2 = T.o
	M.sprite(S, w, func(cv): FIG.draw(cv, kit, fk, fname, M.scr_w(o, w)), 0.0, 0.0)


## Ring of sandbags (each bag its own part so crews and guns sort between the back and front halves).
## gap: half-angle (rad) of the opening at the local back (-f).
static func sandbags(S: Array, T: Dictionary, rad: float, layers: int, gap: float, seed: int) -> void:
	var sand: Array = C.ramp(SAND)
	var n := int(ceil(TAU * rad / 0.6))
	for layer in layers:
		for i in n:
			var t := TAU * (float(i) + 0.5 * float(layer % 2)) / float(n)
			if absf(wrapf(t - PI, -PI, PI)) < gap:
				continue
			var pt := M.part(S, 0)
			var Tb := M.sub(T, Vector3(cos(t) * rad, sin(t) * rad, 0.12 + layer * 0.22), t + PI / 2.0)
			var sk := 0.9 + 0.2 * P.hn(i, layer, seed)
			M.box(pt, Tb, Vector3.ZERO, Vector3(0.29 * sk, 0.16, 0.11), sand, Vector3(0.06, 0.06, 0.05))
			M.dline(pt, Tb, Vector3(-0.29 * sk, -0.12, 0.0), Vector3(0.29 * sk, -0.12, 0.0), Color(0.3, 0.25, 0.17, 0.35), Vector3(0, -1, 0))


## Flat slab (concrete pad / plinth) with panel seams and an optional hazard edge.
static func pad(S: Array, T: Dictionary, hx: float, hy: float, hz: float, col: Color, seams := 2, haz := false) -> void:
	var pt := M.part(S, -1)
	var rp: Array = C.ramp(col)
	M.box(pt, T, Vector3(0, 0, hz), Vector3(hx, hy, hz), rp, Vector3(0.05, 0.05, 0.05))
	for j in range(1, seams):
		var u := -hx + 2.0 * hx * float(j) / float(seams)
		M.dline(pt, T, Vector3(u, -hy + 0.1, hz * 2.0), Vector3(u, hy - 0.1, hz * 2.0), C.ca(rp[1], 0.8), Vector3(0, 0, 1))
		M.dline(pt, T, Vector3(-hx + 0.1, u * hy / hx, hz * 2.0), Vector3(hx - 0.1, u * hy / hx, hz * 2.0), C.ca(rp[1], 0.8), Vector3(0, 0, 1))
	if haz:
		for i in 6:
			var u := -hx + (float(i) + 0.5) * 2.0 * hx / 6.0
			M.dline(pt, T, Vector3(u - 0.15, -hy - 0.01, hz * 1.6), Vector3(u + 0.15, -hy - 0.01, hz * 0.4), HAZ if i % 2 == 0 else GR.HAZ_D, Vector3(0, -1, 0))
			M.dline(pt, T, Vector3(u - 0.15, hy + 0.01, hz * 1.6), Vector3(u + 0.15, hy + 0.01, hz * 0.4), HAZ if i % 2 == 0 else GR.HAZ_D, Vector3(0, 1, 0))


## Muzzle flash decal (+ a fireball and smoke puff when big > 1) at local m of pose Tp, drawn on top.
static func flash(S: Array, Tp: Dictionary, m: Vector3, big := 1.0) -> void:
	var pt := M.part(S, 3)
	V._flash(pt, Tp, m)
	if big > 1.0:
		var w := M.wm(Tp, m + Vector3(0.25, 0, 0))
		var o: Vector2 = Tp.o
		M.sprite(S, w, func(cv):
			var c := M.scr_w(o, w)
			C.blob(cv, c, 1.6 * big, [GR.FLASH_O, GR.FLASH_O, GR.FLASH, GR.FLASH, Color(1, 1, 0.9)])
			C.blob(cv, c + Vector2(2, -3) * big, 1.4 * big, C.ramp(Color8(150, 146, 136))), 4.0)


## Barrel along local +f of pose Tg from f0 to f1 at (r, z), pulled back by rc; returns the muzzle local point.
static func barrel(pt: Dictionary, Tg: Dictionary, f0: float, f1: float, r: float, z: float, rad: float, rc: float,
		col := DARK, brake := true) -> Vector3:
	var dk: Array = C.ramp(col)
	M.cyl(pt, Tg, Vector3((f0 + f1) * 0.5 - rc, r, z), Vector3(1, 0, 0), rad, (f1 - f0) * 0.5, 6, dk, {"edge": false})
	if brake:
		M.box(pt, Tg, Vector3(f1 - rc - 0.08, r, z), Vector3(0.1, rad * 1.7, rad * 1.5), dk)
	return Vector3(f1 - rc + 0.05, r, z)


static func _impact(cv, o: Vector2, kind: String, ph: int) -> void:
	var c := o + Vector2(0, -4)
	match kind:
		"emp":
			for i in 28:
				var a := TAU * float(i) / 28.0
				var r := 10.0 + ph * 8.0
				cv.px(int(c.x + cos(a) * r), int(c.y + sin(a) * r * 0.5), GR.EMP if i % 3 != 0 else COIL_HOT)
		"flame":
			C.blob(cv, c, 3.5 + ph * 2.0, [Color8(120, 30, 10), GR.THERM, GR.THERM, GR.FLASH_O, GR.FLASH])
			C.blob(cv, c + Vector2(0, -5 - ph * 3), 2.5, C.ramp(Color8(60, 58, 54)))
			for i in 6:
				cv.px(int(c.x + sin(i * 2.3 + ph) * 7.0), int(c.y + cos(i * 1.3) * 3.0), GR.FLASH)
		"cone":
			for i in 12:
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
			for i in 6:
				var p := c + Vector2(sin(i * 2.7 + ph) * 4.0, cos(i * 1.9) * 2.0)
				cv.px(int(p.x), int(p.y), GR.FLASH if (i + ph) % 2 == 0 else GR.FLASH_O)
				cv.px(int(p.x), int(p.y) - 1, Color(0.6, 0.55, 0.45, 0.6))


# ------------------------------------------------------------------ 1 Heavy MG nest (size 1, 4 m)
static func hmg(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "mg", int(opt.impact))
		return
	var yaw := _yaw(f, opt)
	var S: Array = []
	var T0 := M.pose(o, float(f) * PI / 2.0)
	sandbags(S, T0, 1.45, 3, 0.55, 11)
	var Tg := M.pose(o, yaw)
	var pt := M.part(S, 0)
	var dk: Array = C.ramp(DARK)
	var arm: Array = C.ramp(ARMOR)
	M.cyl(pt, Tg, Vector3(0.1, 0, 0.45), Vector3(0, 0, 1), 0.06, 0.45, 6, dk)
	var Th := M.sub(Tg, Vector3(0.1, 0, 0.92))
	var rc := _rc(opt) * 0.5
	M.box(pt, Th, Vector3(0.32, 0, 0.12), Vector3(0.03, 0.4, 0.3), arm)
	for s in [-1.0, 1.0]:
		M.box(pt, M.sub(Th, Vector3(0.22, s * 0.5, 0.1), s * 0.6), Vector3.ZERO, Vector3(0.03, 0.14, 0.26), arm)
	team_patch(pt, Th, Vector3(0.32, 0, 0.44), Vector3(0.035, 0.22, 0.025), arm)
	M.dline(pt, Th, Vector3(0.36, -0.1, 0.22), Vector3(0.36, 0.1, 0.22), Color8(24, 26, 26), Vector3(1, 0, 0))
	for s in [-0.08, 0.08]:
		M.box(pt, Th, Vector3(0.0 - rc, s, 0.18), Vector3(0.26, 0.05, 0.06), dk)
		var mz := barrel(pt, Th, 0.25, 1.15, s, 0.18, 0.03, rc, DARK, false)
		if bool(opt.get("fire", false)):
			flash(S, Th, mz)
	M.box(pt, Th, Vector3(-0.05, 0.22, 0.08), Vector3(0.12, 0.07, 0.08), C.ramp(CAN))
	crew(S, Tg, Vector3(-0.55, 0, 0.0), yaw, "crouch")
	_fin(cv, S, o, 41 + f)


# ------------------------------------------------------------------ 2 Autocannon turret (size 1, remote)
static func autocannon(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "he" if int(opt.impact) == 1 else "mg", int(opt.impact))
		return
	var yaw := _yaw(f, opt)
	var S: Array = []
	pad(S, M.pose(o, float(f) * PI / 2.0), 1.35, 1.35, 0.22, CONC, 2, true)
	var Tg := M.pose(o, yaw, Vector3(0, 0, 0.44))
	var pt := M.part(S, 0)
	var arm: Array = C.ramp(ARMOR)
	var dk: Array = C.ramp(DARK)
	M.cyl(pt, Tg, Vector3(0, 0, 0.12), Vector3(0, 0, 1), 0.75, 0.12, 12, dk, {"cap_t": 1})
	M.box(pt, Tg, Vector3(-0.05, 0, 0.62), Vector3(0.85, 0.68, 0.38), arm, Vector3(0.45, 0.12, 0.16))
	team_patch(pt, Tg, Vector3(-0.15, 0, 1.01), Vector3(0.3, 0.3, 0.012), arm)
	M.dline(pt, Tg, Vector3(-0.6, -0.5, 1.0), Vector3(-0.6, 0.5, 1.0), C.ca(arm[0], 0.9), Vector3(0, 0, 1))
	M.box(pt, Tg, Vector3(0.1, -0.78, 0.82), Vector3(0.18, 0.1, 0.13), dk)
	M.dpx(pt, Tg, Vector3(0.29, -0.78, 0.84), GLASS, Vector3(1, 0, 0))
	M.dpx(pt, Tg, Vector3(0.29, -0.74, 0.86), C.ramp(GLASS)[4], Vector3(1, 0, 0))
	var rc := _rc(opt)
	M.box(pt, Tg, Vector3(0.82, 0, 0.62), Vector3(0.14, 0.2, 0.17), arm)
	var mz := barrel(pt, Tg, 0.9, 2.9, 0, 0.62, 0.06, rc)
	M.box(pt, Tg, Vector3(-0.55, 0.62, 0.45), Vector3(0.25, 0.08, 0.16), C.ramp(CAN))
	if bool(opt.get("fire", false)):
		flash(S, Tg, mz, 1.4)
	_fin(cv, S, o, 43 + f)


# ------------------------------------------------------------------ 3 Hull-down tank turret in a berm (size 2, 8 m)
static func hulldown(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "he", int(opt.impact))
		return
	var by := float(f) * PI / 2.0
	var yaw := _yaw(f, opt)
	var S: Array = []
	var T0 := M.pose(o, by)
	var dirt: Array = C.ramp(DIRT)
	var conc: Array = C.ramp(CONC)
	for s in [-1.0, 1.0]:   # side berms
		var pb := M.part(S, -1)
		M.box(pb, T0, Vector3(-0.2, s * 2.85, 0.5), Vector3(2.4, 0.8, 0.5), dirt, Vector3(0.5, 0.5, 0.55))
	var pf := M.part(S, 0)   # front berm (the hull hides behind it)
	M.box(pf, T0, Vector3(2.75, 0, 0.6), Vector3(0.8, 3.4, 0.6), dirt, Vector3(0.6, 0.25, 0.25))
	for i in 7:
		M.dpx(pf, T0, Vector3(2.4 + 0.3 * P.hn(i, f, 3), -3.0 + i, 1.05), C.ramp(Color8(96, 110, 60))[2 + i % 2], Vector3(0, 0, 1))
	var pr := M.part(S, -1)   # rear revetment + hull deck
	M.box(pr, T0, Vector3(-2.9, 0, 0.45), Vector3(0.18, 2.4, 0.45), conc)
	M.box(pr, T0, Vector3(0, 0, 0.35), Vector3(2.6, 1.7, 0.35), C.ramp(ARMOR_D), Vector3(0.3, 0.2, 0.1))
	var Tg := M.pose(o, yaw, Vector3(0, 0, 0.7))
	var pt := M.part(S, 1)
	var arm: Array = C.ramp(ARMOR)
	M.box(pt, Tg, Vector3(-0.2, 0, 0.42), Vector3(1.6, 1.25, 0.42), arm, Vector3(0.9, 0.25, 0.25))
	M.box(pt, Tg, Vector3(-1.35, 0, 0.45), Vector3(0.45, 1.0, 0.32), arm, Vector3(0, 0.15, 0.1))   # bustle
	team_patch(pt, Tg, Vector3(-0.6, 0.0, 0.85), Vector3(0.45, 0.45, 0.012), arm)
	M.cyl(pt, Tg, Vector3(-0.35, 0.5, 0.95), Vector3(0, 0, 1), 0.28, 0.12, 8, arm, {"cap_t": 3})
	M.box(pt, Tg, Vector3(-0.1, -0.6, 0.95), Vector3(0.2, 0.14, 0.14), C.ramp(DARK))
	M.dpx(pt, Tg, Vector3(0.1, -0.6, 0.97), GLASS, Vector3(1, 0, 0))
	M.box(pt, Tg, Vector3(1.35, 0, 0.45), Vector3(0.18, 0.4, 0.25), arm)   # mantlet
	var rc := _rc(opt) * 1.5
	var mz := barrel(pt, Tg, 1.5, 6.0, 0, 0.45, 0.1, rc, ARMOR_D)
	M.cyl(pt, Tg, Vector3(3.2 - rc, 0, 0.45), Vector3(1, 0, 0), 0.16, 0.35, 8, arm, {"edge": false})   # fume extractor
	if bool(opt.get("fire", false)):
		flash(S, Tg, mz, 2.2)
	_fin(cv, S, o, 47 + f)


# ------------------------------------------------------------------ 4 Auto-mortar pit (size 2): twin 120 mm, loader
static func mortar(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "he", int(opt.impact))
		return
	var by := float(f) * PI / 2.0
	var yaw := _yaw(f, opt)
	var S: Array = []
	var T0 := M.pose(o, by)
	pad(S, T0, 2.4, 2.4, 0.06, Color8(104, 96, 80), 3)
	sandbags(S, T0, 2.75, 2, 0.4, 17)
	var Tg := M.pose(o, yaw)
	var pt := M.part(S, 0)
	var arm: Array = C.ramp(ARMOR)
	var dk: Array = C.ramp(DARK)
	M.cyl(pt, Tg, Vector3(0, 0, 0.18), Vector3(0, 0, 1), 1.0, 0.18, 12, dk, {"cap_t": 1})
	M.box(pt, Tg, Vector3(-0.2, 0, 0.62), Vector3(0.9, 0.8, 0.28), arm, Vector3(0.2, 0.2, 0.1))
	team_patch(pt, Tg, Vector3(-0.5, 0, 0.91), Vector3(0.35, 0.35, 0.012), arm)
	var rc := _rc(opt)
	for s in [-0.38, 0.38]:
		var Tt := M.sub(Tg, Vector3(0.1, s, 0.95), 0.0, 0.95)
		var pp := M.part(S, 1)
		M.box(pp, Tt, Vector3(-0.1, 0, 0), Vector3(0.25, 0.2, 0.18), arm)
		M.cyl(pp, Tt, Vector3(1.0 - rc, 0, 0), Vector3(1, 0, 0), 0.11, 1.1, 8, dk, {"edge": false})
		M.cyl(pp, Tt, Vector3(2.05 - rc, 0, 0), Vector3(1, 0, 0), 0.13, 0.06, 8, dk)
		if bool(opt.get("fire", false)):
			flash(S, Tt, Vector3(2.15 - rc, 0, 0), 1.8)
	for i in 3:   # ammo crates
		var pc := M.part(S, 0)
		M.box(pc, T0, Vector3(-1.6 + i * 0.1, -1.4 + i * 0.6, 0.15), Vector3(0.3, 0.22, 0.15), C.ramp(CAN))
		M.dpx(pc, T0, Vector3(-1.3 + i * 0.1, -1.4 + i * 0.6, 0.2), HAZ, Vector3(1, 0, 0))
	crew(S, T0, Vector3(-1.55, 1.2, 0.0), float(f) * PI / 2.0, "act_0" if bool(opt.get("fire", false)) else "idle")
	_fin(cv, S, o, 53 + f)


# ------------------------------------------------------------------ 5 EMP pylon (size 1): coil emitter on a mast
static func emp(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "emp", int(opt.impact))
		return
	var yaw := _yaw(f, opt)
	var fire := bool(opt.get("fire", false))
	var charge := int(opt.get("charge", -1))
	var hot := fire or charge >= 0
	var S: Array = []
	var T0 := M.pose(o, float(f) * PI / 2.0)
	pad(S, T0, 1.4, 1.4, 0.18, CONC, 2, true)
	var st: Array = C.ramp(STEEL)
	for s in [-1.0, 1.0]:   # capacitor cabinets with status LEDs
		var pc := M.part(S, 0)
		M.box(pc, T0, Vector3(-0.75, s * 0.75, 0.75), Vector3(0.32, 0.28, 0.4), st, Vector3(0.02, 0.02, 0.02))
		team_patch(pc, T0, Vector3(-0.75, s * 0.75, 1.16), Vector3(0.2, 0.18, 0.012), st)
		for i in 3:
			M.dpx(pc, T0, Vector3(-0.42, s * 0.75 + (i - 1) * 0.1, 0.9), COIL_HOT if hot and i <= charge + 1 else GR.LED_G, Vector3(1, 0, 0))
		M.dline(pc, T0, Vector3(-0.42, s * 0.75 - 0.2, 0.5), Vector3(-0.42, s * 0.75 + 0.2, 0.5), HAZ, Vector3(1, 0, 0))
	var Tg := M.pose(o, yaw)
	var pt := M.part(S, 1)
	M.cyl(pt, Tg, Vector3(0, 0, 1.6), Vector3(0, 0, 1), 0.16, 1.25, 8, st)
	for i in 3:   # lattice braces
		var a := TAU * i / 3.0
		M.cyl(pt, Tg, Vector3(cos(a) * 0.35, sin(a) * 0.35, 0.75), Vector3(-cos(a) * 0.35, -sin(a) * 0.35, 0.9).normalized(), 0.04, 0.55, 4, C.ramp(DARK), {"edge": false})
	var cl: Array = C.ramp(COIL_HOT if hot else COIL)
	for z in [2.35, 2.75]:   # emitter rings
		M.cyl(pt, Tg, Vector3(0, 0, z), Vector3(0, 0, 1), 0.62, 0.07, 12, C.ramp(DARK), {"cap_t": 1}, 0.0)
		for i in 12:
			var a := TAU * i / 12.0
			M.dpx(pt, Tg, Vector3(cos(a) * 0.63, sin(a) * 0.63, z), cl[3 if i % 2 == 0 else 2], Vector3(cos(a), sin(a), 0))
	M.cyl(pt, Tg, Vector3(0, 0, 3.05), Vector3(0, 0, 1), 0.28, 0.18, 8, cl, {"cap_t": 4})
	for s in [-1.0, 1.0]:   # directional fins (traverse)
		M.box(pt, Tg, Vector3(0.2, s * 0.45, 2.55), Vector3(0.35, 0.03, 0.3), C.ramp(ARMOR), Vector3(0.2, 0.0, 0.0))
	if fire or charge >= 0:
		var w := M.wm(Tg, Vector3(0, 0, 2.6))
		var r := 6.0 if fire else 3.0 + charge * 2.0
		M.sprite(S, w, func(cv2):
			var c := M.scr_w(o, w)
			for i in 32:
				var a := TAU * float(i) / 32.0
				cv2.px(int(c.x + cos(a) * r * 2.0), int(c.y + sin(a) * r), GR.EMP if i % 3 != 0 else COIL_HOT)
			if fire:
				for i in 40:
					var a := TAU * float(i) / 40.0
					cv2.px(int(c.x + cos(a) * 26.0), int(c.y + 12.0 + sin(a) * 12.0), Color(GR.EMP, 0.8))
			C.blob(cv2, c, 2.0 + (1.5 if fire else 0.0), [COIL, COIL, COIL_HOT, COIL_HOT, Color(1, 1, 1)]), 4.0)
	_fin(cv, S, o, 59 + f)


# ------------------------------------------------------------------ 6 Thermite projector (size 1)
static func thermite(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "flame", int(opt.impact))
		return
	var yaw := _yaw(f, opt)
	var S: Array = []
	sandbags(S, M.pose(o, float(f) * PI / 2.0), 1.5, 2, 0.7, 23)
	var Tg := M.pose(o, yaw)
	var pt := M.part(S, 0)
	var arm: Array = C.ramp(ARMOR)
	var dk: Array = C.ramp(DARK)
	var tk: Array = C.ramp(TANK)
	M.cyl(pt, Tg, Vector3(0, 0, 0.15), Vector3(0, 0, 1), 0.7, 0.15, 10, dk, {"cap_t": 1})
	M.box(pt, Tg, Vector3(0.05, 0, 0.62), Vector3(0.6, 0.5, 0.32), arm, Vector3(0.3, 0.1, 0.12))
	team_patch(pt, Tg, Vector3(-0.05, 0, 0.95), Vector3(0.25, 0.25, 0.012), arm)
	for s in [-1.0, 1.0]:   # thermite tanks on the back
		M.cyl(pt, Tg, Vector3(-0.75, s * 0.28, 0.62), Vector3(0, 0, 1), 0.22, 0.38, 8, tk, {"cap_t": 3})
		M.dline(pt, Tg, Vector3(-0.97, s * 0.28, 0.5), Vector3(-0.97, s * 0.28, 0.8), HAZ, Vector3(-1, 0, 0))
	M.cyl(pt, Tg, Vector3(-0.3, 0, 0.98), Vector3(1, 0, 0), 0.04, 0.45, 4, C.ramp(CABLE), {"edge": false})
	var rc := _rc(opt) * 0.5
	var mz := barrel(pt, Tg, 0.6, 1.75, 0, 0.6, 0.09, rc, STEEL)
	M.cyl(pt, Tg, Vector3(1.0 - rc, 0, 0.6), Vector3(1, 0, 0), 0.13, 0.25, 8, dk, {"edge": false})
	if bool(opt.get("fire", false)):
		var a := M.wm(Tg, mz)
		var b := M.wm(Tg, mz + Vector3(5.5, 0, -0.6))
		M.sprite(S, b, func(cv2):
			var p0 := M.scr_w(o, a)
			var p1 := M.scr_w(o, b)
			for i in 18:   # molten stream arcing down, white-hot core, sparks
				var t := float(i) / 17.0
				var p := p0.lerp(p1, t) + Vector2(0, -sin(t * PI) * 5.0)
				C.blob(cv2, p, 0.9 + t * 1.4, [Color8(120, 30, 10), GR.THERM, GR.THERM, GR.FLASH_O, GR.FLASH])
				if i % 3 == 0:
					cv2.px(int(p.x + sin(i * 2.1) * 3.0), int(p.y - 2.0 - cos(i * 1.3) * 2.0), GR.FLASH)
			C.blob(cv2, p1, 3.0, [Color8(120, 30, 10), GR.THERM, GR.FLASH_O, GR.FLASH, Color(1, 1, 0.9)]), 4.0)
	crew(S, Tg, Vector3(-0.7, 0.75, 0.0), yaw, "crouch")
	_fin(cv, S, o, 61 + f)


# ------------------------------------------------------------------ 7 Microwave emitter (size 1): panel array on a yoke
static func microwave(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "cone", int(opt.impact))
		return
	var yaw := _yaw(f, opt)
	var fire := bool(opt.get("fire", false))
	var S: Array = []
	var T0 := M.pose(o, float(f) * PI / 2.0)
	pad(S, T0, 1.35, 1.35, 0.18, CONC, 2, true)
	var pg := M.part(S, 0)   # generator with exhaust
	M.box(pg, T0, Vector3(-0.8, 0.6, 0.65), Vector3(0.38, 0.5, 0.3), C.ramp(STEEL), Vector3(0.03, 0.03, 0.03))
	M.cyl(pg, T0, Vector3(-0.95, 0.85, 1.15), Vector3(0, 0, 1), 0.07, 0.25, 6, C.ramp(DARK))
	team_patch(pg, T0, Vector3(-0.8, 0.6, 0.96), Vector3(0.2, 0.25, 0.012), C.ramp(STEEL))
	var Tg := M.pose(o, yaw)
	var pt := M.part(S, 1)
	var arm: Array = C.ramp(ARMOR)
	M.cyl(pt, Tg, Vector3(0.1, 0, 0.75), Vector3(0, 0, 1), 0.2, 0.4, 8, C.ramp(DARK))
	for s in [-1.0, 1.0]:
		M.box(pt, Tg, Vector3(0.1, s * 0.8, 1.35), Vector3(0.1, 0.06, 0.35), arm)
	var Tp := M.sub(Tg, Vector3(0.25, 0, 1.5), 0.0, 0.25)
	var pp := M.part(S, 1)
	var pn: Array = C.ramp(Color8(112, 118, 104))
	M.box(pp, Tp, Vector3(0, 0, 0), Vector3(0.1, 0.75, 0.6), pn)
	for i in 5:   # emitter tiles on the face
		for j in 4:
			var c := Vector3(0.11, -0.6 + i * 0.3, -0.45 + j * 0.3)
			M.dpx(pp, Tp, c, MW if fire and (i + j) % 2 == 0 else C.ramp(Color8(150, 140, 110))[3], Vector3(1, 0, 0))
	M.dline(pp, Tp, Vector3(0.11, -0.74, 0.0), Vector3(0.11, 0.74, 0.0), C.ca(pn[0], 0.9), Vector3(1, 0, 0))
	if fire:
		var a := M.wm(Tp, Vector3(0.2, 0, 0))
		var d := M.wdir(Tp, Vector3(1, 0, 0))
		M.sprite(S, a + d * 4.0, func(cv2):
			var p0 := M.scr_w(o, a)
			for i in 26:   # heat-shimmer cone
				var t := float(i % 13) / 12.0
				var sd := (float(i / 13) * 2.0 - 1.0) * (0.5 + t * 2.0)
				var p := M.scr_w(o, a + d * (0.4 + t * 9.0) + Vector3(-d.y, d.x, 0) * sd)
				cv2.line_v(p0.lerp(p, 0.6), p, Color(MW, 0.35 * (1.0 - t * 0.6))), 4.0)
	_fin(cv, S, o, 67 + f)


# ------------------------------------------------------------------ 8 Rail cannon (size 2): ARTCN7's sample design in metres
static func rail(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "rail", int(opt.impact))
		return
	var by := float(f) * PI / 2.0
	var yaw := _yaw(f, opt)
	var fire := bool(opt.get("fire", false))
	var charge := int(opt.get("charge", -1))
	var S: Array = []
	var T0 := M.pose(o, by)
	pad(S, T0, 3.3, 3.3, 0.24, CONC, 4, true)
	var arm: Array = C.ramp(ARMOR)
	var pc := M.part(S, 0)   # sloped casemate
	M.box(pc, M.sub(T0, Vector3.ZERO, PI / 4.0), Vector3(0, 0, 0.85), Vector3(1.9, 1.9, 0.38), arm, Vector3(0.35, 0.35, 0.35))
	for s in [-1.0, 1.0]:   # capacitor banks + power trunk
		var pk := M.part(S, 0)
		var cap: Array = C.ramp(Color8(80, 86, 92))
		M.box(pk, T0, Vector3(-2.3, s * 2.1, 0.95), Vector3(0.55, 0.5, 0.7), cap, Vector3(0.04, 0.04, 0.04))
		team_patch(pk, T0, Vector3(-2.3, s * 2.1, 1.66), Vector3(0.3, 0.3, 0.012), cap)
		for i in 4:
			M.dpx(pk, T0, Vector3(-1.74, s * 2.1 - 0.3 + i * 0.2, 1.3), COIL_HOT if fire or (charge >= 0 and i <= charge * 2 + 1) else COIL, Vector3(1, 0, 0))
		M.dline(pk, T0, Vector3(-1.74, s * 2.1, 0.6), Vector3(-0.9, s * 0.9, 1.3), CABLE)
	var Tg := M.pose(o, yaw, Vector3(0, 0, 1.25))
	var pt := M.part(S, 1)
	M.cyl(pt, Tg, Vector3(0, 0, 0.1), Vector3(0, 0, 1), 1.1, 0.1, 12, C.ramp(DARK), {"cap_t": 1})
	M.box(pt, Tg, Vector3(-0.4, 0, 0.6), Vector3(1.4, 1.1, 0.42), arm, Vector3(0.5, 0.2, 0.18))
	team_patch(pt, Tg, Vector3(-1.0, 0, 1.03), Vector3(0.35, 0.5, 0.012), arm)
	M.box(pt, Tg, Vector3(-0.6, -0.95, 1.05), Vector3(0.25, 0.14, 0.14), C.ramp(DARK))
	M.dpx(pt, Tg, Vector3(-0.34, -0.95, 1.07), GLASS, Vector3(1, 0, 0))
	var rc := _rc(opt)
	var rl: Array = C.ramp(Color8(70, 74, 80))
	for s in [-0.42, 0.42]:
		M.box(pt, Tg, Vector3(3.0 - rc, s, 0.75), Vector3(2.6, 0.1, 0.16), rl)
		for i in 7:
			var hot := fire or (charge >= 0 and i <= 2 + charge * 3)
			M.dpx(pt, Tg, Vector3(0.9 + i * 0.7 - rc, s, 0.92), COIL_HOT if hot else COIL, Vector3(0, 0, 1))
	for i in 4:   # rail spacers
		M.box(pt, Tg, Vector3(1.0 + i * 1.4 - rc, 0, 0.75), Vector3(0.08, 0.5, 0.08), C.ramp(DARK))
	var tipl := Vector3(5.7 - rc, 0, 0.75)
	var a := M.wm(Tg, tipl)
	var d := M.wdir(Tg, Vector3(1, 0, 0))
	if fire:
		M.sprite(S, a + d * 4.0, func(cv2):
			var p0 := M.scr_w(o, a)
			var p1 := M.scr_w(o, a + d * 22.0)
			C.blob(cv2, p0, 2.6, [COIL, COIL, COIL_HOT, COIL_HOT, Color(1, 1, 1)])
			cv2.line_v(p0, p1, COIL_HOT)
			cv2.line_v(p0 + Vector2(0, 1), p1 + Vector2(0, 1), Color(COIL, 0.6))
			cv2.line_v(p0 - Vector2(0, 1), p0.lerp(p1, 0.7) - Vector2(0, 1), Color(COIL, 0.4)), 4.0)
	elif charge >= 0:
		M.sprite(S, a, func(cv2):
			var p0 := M.scr_w(o, a)
			for i in 3 + charge * 3:
				cv2.px(int(p0.x + sin(i * 2.1) * 3.0), int(p0.y + cos(i * 1.7) * 2.0), COIL_HOT), 4.0)
	_fin(cv, S, o, 71 + f)


# ------------------------------------------------------------------ build + generator
const SPECS := [
	["a_t7_hmg_nest", 1, 30, "hmg", []],
	["a_t7_autocannon", 1, 30, "autocannon", []],
	["a_t7_hulldown", 2, 34, "hulldown", []],
	["a_t7_automortar", 2, 40, "mortar", []],
	["a_t7_emp", 1, 40, "emp", [["charge_0", {"charge": 0}], ["charge_1", {"charge": 1}]]],
	["a_t7_thermite", 1, 30, "thermite", []],
	["a_t7_microwave", 1, 34, "microwave", []],
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
			{"turret7": String(sp[3]), "scale": "4 m/tile, 9.8 px/m (fact art.scale), rev3 DL7-3", "art": "ART7B",
			"key_frames": ["aim_0", "aim_2", "aim_0_fire", "impact_1"],
			"anim_strip": ["aim_0", "aim_1", "aim_2", "aim_2_fire", "aim_3", "aim_4", "aim_4_fire", "recoil", "impact_0", "impact_1"]})
		var man: Dictionary = out.manifest.buildings
		var img: Image = out.images[String(man[sp[0]].states.built.file)]
		C.icon(out, String(sp[0]), img, img.get_width(), img.get_height(), 0)


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
	for sub in ["buildings", "icons"]:
		var bd := DirAccess.open(ProjectSettings.globalize_path(out_dir).path_join(sub))
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
