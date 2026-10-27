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
const H = preload("res://tools/art/g6_lib.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")

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


## Rest heading of rot_<f>: along the building axis (f * 90 deg), so the barrel lies across the screen in a 3/4 view
## (ART7C: the old f * 90 + 45 pointed every barrel straight at the camera and foreshortened it to a stub).
static func _yaw(f: int, opt: Dictionary) -> float:
	return float(opt.aim) * PI / 4.0 if opt.has("aim") else float(f) * PI / 2.0


static func _rc(opt: Dictionary) -> float:
	return 0.18 if bool(opt.get("fire", false)) or bool(opt.get("recoil", false)) else 0.0


static func _fin(cv, S: Array, o: Vector2, seed: int) -> void:
	M.shadow(cv, S, o)
	M.render_z(cv, S, o, seed)


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
	# ART7C: a real twin .50 mount - tripod pintle, a wide angled gun shield with a vision slot, two long barrels
	# with flash hiders, belts from twin ammo cans: reads as "twin MG behind a shield in a sandbag ring" at zoom 1.
	for i in 3:   # tripod legs
		var a := TAU * i / 3.0 + PI
		var foot := Vector3(0.1 + cos(a) * 0.42, sin(a) * 0.42, 0.02)
		var top := Vector3(0.1, 0, 0.62)
		M.cyl(pt, Tg, (foot + top) * 0.5, top - foot, 0.03, (top - foot).length() * 0.5, 4, dk, {"edge": false})
	M.cyl(pt, Tg, Vector3(0.1, 0, 0.75), Vector3(0, 0, 1), 0.06, 0.15, 6, dk)
	var Th := M.sub(Tg, Vector3(0.1, 0, 0.92))
	var rc := _rc(opt) * 0.5
	M.box(pt, Th, Vector3(0.36, 0, 0.14), Vector3(0.035, 0.46, 0.34), arm, Vector3(0.0, 0.0, 0.08))
	for s in [-1.0, 1.0]:   # angled wing plates
		M.box(pt, M.sub(Th, Vector3(0.24, s * 0.58, 0.1), s * 0.55), Vector3.ZERO, Vector3(0.03, 0.16, 0.3), arm)
	team_patch(pt, Th, Vector3(0.36, 0, 0.42), Vector3(0.04, 0.2, 0.03), arm)
	M.dline(pt, Th, Vector3(0.4, -0.16, 0.26), Vector3(0.4, 0.16, 0.26), Color8(20, 22, 22), Vector3(1, 0, 0))
	M.dline(pt, Th, Vector3(0.4, -0.42, -0.18), Vector3(0.4, 0.42, -0.18), C.ca(arm[0], 0.8), Vector3(1, 0, 0))
	for s in [-0.12, 0.12]:
		M.box(pt, Th, Vector3(0.05 - rc, s, 0.16), Vector3(0.3, 0.055, 0.07), dk)   # receiver
		M.box(pt, Th, Vector3(-0.3 - rc, s, 0.2), Vector3(0.05, 0.03, 0.05), dk)   # spade grips
		M.cyl(pt, Th, Vector3(0.62 - rc, s, 0.16), Vector3(1, 0, 0), 0.07, 0.16, 6, dk, {"edge": false})   # barrel jacket
		var mz := barrel(pt, Th, 0.7, 1.75, s, 0.16, 0.048, rc, DARK, false)
		M.cyl(pt, Th, Vector3(1.66 - rc, s, 0.16), Vector3(1, 0, 0), 0.065, 0.07, 6, dk, {"edge": false})   # flash hider
		if bool(opt.get("fire", false)):
			flash(S, Th, mz, 1.2)
	for s in [-1.0, 1.0]:   # ammo cans + belts
		M.box(pt, Th, Vector3(-0.05, s * 0.3, 0.02), Vector3(0.13, 0.07, 0.09), C.ramp(CAN))
		M.dline(pt, Th, Vector3(0.0, s * 0.24, 0.1), Vector3(0.05, s * 0.14, 0.2), Color8(176, 148, 70))
	crew(S, Tg, Vector3(-0.6, 0, 0.0), yaw, "crouch")
	_fin(cv, S, o, 41 + f)


# ------------------------------------------------------------------ 2 Autocannon turret (size 1, remote)
static func autocannon(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	if opt.has("impact"):
		_impact(cv, o, "he" if int(opt.impact) == 1 else "mg", int(opt.impact))
		return
	var yaw := _yaw(f, opt)
	var S: Array = []
	pad(S, M.pose(o, float(f) * PI / 2.0), 1.35, 1.35, 0.22, CONC, 2, true)
	# ART7C: a raised remote turret on an armoured pedestal (tallest silhouette of the size-1 guns), wedge turret with
	# an EO/IR sight head, a long thin 30 mm barrel with a muzzle brake and a side ammo bin.
	var T0 := M.pose(o, float(f) * PI / 2.0)
	var pp := M.part(S, 0)
	var st: Array = C.ramp(STEEL)
	M.cyl(pp, T0, Vector3(0, 0, 0.9), Vector3(0, 0, 1), 0.42, 0.5, 8, st, {"cap_t": 2}, 0.0, 0.34)   # pedestal
	M.dline(pp, T0, Vector3(0.38, -0.12, 0.6), Vector3(0.38, 0.12, 0.6), C.ca(st[0], 0.9), Vector3(1, 0, 0))
	M.dpx(pp, T0, Vector3(0.39, 0, 0.9), GR.LED_G, Vector3(1, 0, 0))
	M.box(pp, T0, Vector3(-0.7, -0.7, 0.75), Vector3(0.25, 0.2, 0.32), st, Vector3(0.02, 0.02, 0.02))   # power box
	M.dline(pp, T0, Vector3(-0.45, -0.7, 0.9), Vector3(-0.45, -0.7, 0.6), HAZ, Vector3(1, 0, 0))
	var Tg := M.pose(o, yaw, Vector3(0, 0, 1.4))
	var pt := M.part(S, 1)
	var arm: Array = C.ramp(ARMOR)
	var dk: Array = C.ramp(DARK)
	M.cyl(pt, Tg, Vector3(0, 0, 0.06), Vector3(0, 0, 1), 0.55, 0.06, 10, dk, {"cap_t": 1})
	M.box(pt, Tg, Vector3(-0.1, 0, 0.42), Vector3(0.75, 0.52, 0.32), arm, Vector3(0.5, 0.1, 0.14))
	team_patch(pt, Tg, Vector3(-0.3, 0, 0.75), Vector3(0.24, 0.24, 0.012), arm)
	M.dline(pt, Tg, Vector3(-0.7, -0.4, 0.74), Vector3(-0.7, 0.4, 0.74), C.ca(arm[0], 0.9), Vector3(0, 0, 1))
	M.box(pt, Tg, Vector3(0.05, -0.36, 0.95), Vector3(0.16, 0.12, 0.13), dk)   # sight head
	M.dpx(pt, Tg, Vector3(0.22, -0.39, 0.97), GLASS, Vector3(1, 0, 0))
	M.dpx(pt, Tg, Vector3(0.22, -0.33, 0.97), C.ramp(GLASS)[4], Vector3(1, 0, 0))
	var rc := _rc(opt)
	M.box(pt, Tg, Vector3(0.7, 0, 0.42), Vector3(0.12, 0.17, 0.15), arm)   # mantlet
	M.cyl(pt, Tg, Vector3(1.15 - rc, 0, 0.42), Vector3(1, 0, 0), 0.085, 0.35, 6, dk, {"edge": false})   # recoil sleeve
	var mz := barrel(pt, Tg, 1.4, 3.6, 0, 0.42, 0.05, rc)
	M.box(pt, Tg, Vector3(-0.35, 0.62, 0.36), Vector3(0.3, 0.1, 0.2), C.ramp(CAN))   # ammo bin
	M.dline(pt, Tg, Vector3(0.0, 0.55, 0.45), Vector3(0.55, 0.15, 0.45), Color8(176, 148, 70))
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
	# ART7C: no more open "sandbox" pit. A round earth mound (sloped frustum, grass and stones) carries a buried
	# octagonal concrete casemate collar; a low wedge tank turret sits in the collar with the longest barrel of the
	# turret line (120 mm, 5.2 m, bore evacuator + muzzle brake): the main-gun silhouette nothing else shares.
	var pb := M.part(S, -1)
	M.cyl(pb, T0, Vector3(0, 0, 0.45), Vector3(0, 0, 1), 3.55, 0.45, 16, dirt, {"cap_t": 2}, PI / 16.0, 2.75)
	for i in 22:   # grass tufts + stones on the mound
		var a := TAU * P.hn(i, f, 3)
		var r := 2.85 + 0.6 * P.hn(i, f, 5)
		var z := 0.9 - (r - 2.75) * 1.1
		M.dpx(pb, T0, Vector3(cos(a) * r, sin(a) * r, z), C.ramp(Color8(96, 110, 60))[1 + i % 3] if i % 4 != 0 else C.ramp(Color8(120, 116, 104))[3])
	var pc := M.part(S, 0)
	M.cyl(pc, T0, Vector3(0, 0, 1.0), Vector3(0, 0, 1), 2.45, 0.12, 8, conc, {"cap_t": 2}, PI / 8.0, 2.25)   # collar
	M.cyl(pc, T0, Vector3(0, 0, 1.13), Vector3(0, 0, 1), 1.85, 0.02, 12, C.ramp(Color8(52, 54, 52)), {"cap_t": 0})
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		M.dpx(pc, T0, Vector3(cos(a) * 2.3, sin(a) * 2.3, 1.12), C.ramp(CONC)[1], Vector3(0, 0, 1))
	var Tg := M.pose(o, yaw, Vector3(0, 0, 1.12))
	var pt := M.part(S, 1)
	var arm: Array = C.ramp(ARMOR)
	M.cyl(pt, Tg, Vector3(0, 0, 0.08), Vector3(0, 0, 1), 1.6, 0.08, 12, C.ramp(ARMOR_D), {"cap_t": 1})   # turret ring
	M.box(pt, Tg, Vector3(-0.15, 0, 0.45), Vector3(1.55, 1.3, 0.35), arm, Vector3(1.0, 0.2, 0.3))
	M.box(pt, Tg, Vector3(-1.55, 0, 0.45), Vector3(0.45, 1.05, 0.28), arm, Vector3(0.0, 0.2, 0.12))   # bustle
	for i in 3:   # bustle rack
		M.dline(pt, Tg, Vector3(-2.02, -0.9 + i * 0.9, 0.2), Vector3(-2.02, -0.9 + i * 0.9, 0.7), C.ca(arm[0], 1.0), Vector3(-1, 0, 0))
	team_patch(pt, Tg, Vector3(-0.7, 0.0, 0.81), Vector3(0.42, 0.42, 0.012), arm)
	M.cyl(pt, Tg, Vector3(-0.3, 0.55, 0.88), Vector3(0, 0, 1), 0.3, 0.08, 8, arm, {"cap_t": 3})   # hatch
	M.box(pt, Tg, Vector3(0.0, -0.62, 0.95), Vector3(0.22, 0.16, 0.16), C.ramp(DARK))   # sight
	M.dpx(pt, Tg, Vector3(0.23, -0.62, 0.97), GLASS, Vector3(1, 0, 0))
	M.dpx(pt, Tg, Vector3(0.23, -0.56, 0.99), C.ramp(GLASS)[4], Vector3(1, 0, 0))
	M.cyl(pt, Tg, Vector3(-1.2, -0.75, 1.3), Vector3(0, 0, 1), 0.02, 0.55, 4, C.ramp(DARK), {"edge": false})   # antenna
	M.box(pt, Tg, Vector3(1.4, 0, 0.45), Vector3(0.2, 0.45, 0.27), arm, Vector3(0.1, 0.0, 0.06))   # mantlet
	var rc := _rc(opt) * 1.5
	var mz := barrel(pt, Tg, 1.5, 6.7, 0, 0.45, 0.1, rc, ARMOR_D)
	M.cyl(pt, Tg, Vector3(3.6 - rc, 0, 0.45), Vector3(1, 0, 0), 0.16, 0.35, 8, arm, {"edge": false})   # bore evacuator
	M.dline(pt, Tg, Vector3(2.0 - rc, 0, 0.56), Vector3(5.8 - rc, 0, 0.56), C.ca(C.ramp(ARMOR_D)[4], 0.5))
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
		var Tt := M.sub(Tg, Vector3(0.1, s, 0.95), 0.0, 1.05)   # ART7C: 60 deg, fatter + longer 120 mm tubes
		var pp := M.part(S, 1)
		M.box(pp, Tt, Vector3(-0.1, 0, 0), Vector3(0.28, 0.22, 0.2), arm)
		M.cyl(pp, Tt, Vector3(1.05 - rc, 0, 0), Vector3(1, 0, 0), 0.13, 1.15, 8, dk, {"edge": false})
		M.cyl(pp, Tt, Vector3(0.55 - rc, 0, 0), Vector3(1, 0, 0), 0.17, 0.12, 8, arm, {"edge": false})   # recoil collar
		M.cyl(pp, Tt, Vector3(2.15 - rc, 0, 0), Vector3(1, 0, 0), 0.16, 0.07, 8, dk)
		if bool(opt.get("fire", false)):
			flash(S, Tt, Vector3(2.3 - rc, 0, 0), 1.8)
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
	var mz := barrel(pt, Tg, 0.6, 2.1, 0, 0.6, 0.08, rc, STEEL)
	M.cyl(pt, Tg, Vector3(1.0 - rc, 0, 0.6), Vector3(1, 0, 0), 0.13, 0.25, 8, dk, {"edge": false})
	M.cyl(pt, Tg, Vector3(2.12 - rc, 0, 0.6), Vector3(1, 0, 0), 0.12, 0.05, 8, dk, {"edge": false})   # nozzle cowl
	M.dpx(pt, Tg, Vector3(2.0 - rc, 0, 0.72), Color8(120, 200, 255))   # pilot light
	if bool(opt.get("fire", false)):
		# ART7C: a long ballistic stream (7 m, was 5.5 m and clipped by the cell) in a true 3D arc: rises off the nozzle,
		# falls onto the approach and splashes into a burning pool; drawn on the widened thermite canvas.
		var pts: Array = []
		for i in 25:
			var t := float(i) / 24.0
			pts.append(M.wm(Tg, mz + Vector3(7.0 * t, 0, 0.55 * sin(t * PI * 0.8) - mz.z * t * t)))
		var end: Vector3 = M.wm(Tg, mz + Vector3(7.1, 0, -mz.z))
		M.sprite(S, end, func(cv2):
			var ep := M.scr_w(o, end)
			for j in 9:   # burning pool + smoke on the impact point
				C.blob(cv2, ep + Vector2(sin(j * 2.1) * 5.0, cos(j * 1.7) * 2.0), 1.6 + 0.3 * (j % 3), [Color8(120, 30, 10), GR.THERM, GR.THERM, GR.FLASH_O, GR.FLASH])
			C.blob(cv2, ep + Vector2(-1, -7), 3.0, C.ramp(Color8(70, 66, 60)))
			C.blob(cv2, ep + Vector2(3, -12), 2.4, C.ramp(Color8(96, 92, 86)))
			for i in pts.size() - 1:   # molten stream, thickening and breaking up as it falls, white-hot core
				var t := float(i) / float(pts.size() - 1)
				var p := M.scr_w(o, pts[i])
				var q := M.scr_w(o, pts[i + 1])
				C.blob(cv2, p, 0.7 + t * 1.3, [Color8(120, 30, 10), GR.THERM, GR.THERM, GR.FLASH_O, GR.FLASH])
				if t < 0.75:
					cv2.line_v(p, q, GR.FLASH)
				if i % 3 == 1:
					cv2.px(int(p.x + sin(i * 2.1) * 3.0), int(p.y - 2.0 - cos(i * 1.3) * 2.0), GR.FLASH)
			C.blob(cv2, M.scr_w(o, pts[0]), 1.8, [GR.THERM, GR.FLASH_O, GR.FLASH, GR.FLASH, Color(1, 1, 0.9)]), 4.0)
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
	# ART7C: a big tilted phased-array face (1.8 x 1.4 m) in a heavy yoke on a turntable, with a back frame and
	# cooling fins: the only "flat panel" silhouette of the line, readable from the back too.
	var Tg := M.pose(o, yaw)
	var pt := M.part(S, 1)
	var arm: Array = C.ramp(ARMOR)
	M.cyl(pt, Tg, Vector3(0.0, 0, 0.45), Vector3(0, 0, 1), 0.55, 0.1, 10, C.ramp(DARK), {"cap_t": 1})   # turntable
	M.cyl(pt, Tg, Vector3(0.0, 0, 0.85), Vector3(0, 0, 1), 0.22, 0.32, 8, C.ramp(DARK))
	for s in [-1.0, 1.0]:
		M.box(pt, Tg, Vector3(0.0, s * 1.02, 1.3), Vector3(0.12, 0.07, 0.5), arm, Vector3(0.04, 0.04, 0.0))
		M.cyl(pt, Tg, Vector3(0.0, s * 0.98, 1.65), Vector3(0, 1, 0), 0.12, 0.06, 8, C.ramp(DARK))
	M.box(pt, Tg, Vector3(0.0, 0, 0.85), Vector3(0.1, 0.95, 0.06), arm)   # yoke cross-beam
	var Tp := M.sub(Tg, Vector3(0.1, 0, 1.65), 0.0, 0.32)
	var pp := M.part(S, 1)
	var pn: Array = C.ramp(Color8(112, 118, 104))
	M.box(pp, Tp, Vector3(0, 0, 0), Vector3(0.12, 0.9, 0.7), pn, Vector3(0.0, 0.0, 0.0))
	M.box(pp, Tp, Vector3(-0.22, 0, 0), Vector3(0.1, 0.55, 0.45), arm)   # back frame / electronics
	for i in 5:   # cooling fins on the back
		M.dline(pp, Tp, Vector3(-0.33, -0.45 + i * 0.22, -0.35), Vector3(-0.33, -0.45 + i * 0.22, 0.35), C.ca(arm[0], 1.0), Vector3(-1, 0, 0))
	for i in 7:   # emitter tile grid on the face
		for j in 5:
			var c := Vector3(0.125, -0.78 + i * 0.26, -0.56 + j * 0.28)
			M.dpx(pp, Tp, c, MW if fire and (i + j) % 2 == 0 else C.ramp(Color8(150, 140, 110))[3 if (i + j) % 2 == 0 else 2], Vector3(1, 0, 0))
	M.dline(pp, Tp, Vector3(0.125, -0.88, 0.68), Vector3(0.125, 0.88, 0.68), C.ca(pn[4], 0.8), Vector3(1, 0, 0))
	M.dline(pp, Tp, Vector3(0.125, -0.88, -0.68), Vector3(0.125, 0.88, -0.68), C.ca(pn[0], 0.9), Vector3(1, 0, 0))
	M.dline(pp, Tp, Vector3(-0.12, -0.88, 0.0), Vector3(-0.12, 0.88, 0.0), HAZ, Vector3(-1, 0, 0))
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
	M.box(pc, T0, Vector3(0, 0, 0.85), Vector3(1.9, 1.9, 0.38), arm, Vector3(0.45, 0.45, 0.45))   # ART7C: axis-aligned glacis
	for i in 3:
		M.dline(pc, T0, Vector3(1.75, -1.2 + i * 1.2, 0.55), Vector3(1.55, -1.2 + i * 1.2, 1.15), C.ca(arm[0], 0.9), Vector3(1, 0, 0.6))
		M.dline(pc, T0, Vector3(-1.2 + i * 1.2, 1.75, 0.55), Vector3(-1.2 + i * 1.2, 1.55, 1.15), C.ca(arm[0], 0.9), Vector3(0, 1, 0.6))
	M.dline(pc, T0, Vector3(1.88, -1.7, 0.52), Vector3(1.88, 1.7, 0.52), HAZ, Vector3(1, 0, 0))
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
## [id, size, top, drawer, extras, [extra px each side, extra px below]] - ART7C: the long-reach guns get a wider
## canvas so a barrel or the thermite stream aimed across the screen is never clipped at the cell edge.
const SPECS := [
	["a_t7_hmg_nest", 1, 30, "hmg", [], [6, 0]],
	["a_t7_autocannon", 1, 36, "autocannon", [], [10, 6]],
	["a_t7_hulldown", 2, 34, "hulldown", [], [18, 10]],
	["a_t7_automortar", 2, 44, "mortar", [], [0, 0]],
	["a_t7_emp", 1, 40, "emp", [["charge_0", {"charge": 0}], ["charge_1", {"charge": 1}]], [0, 0]],
	["a_t7_thermite", 1, 36, "thermite", [], [44, 24]],
	["a_t7_microwave", 1, 40, "microwave", [], [0, 0]],
	["a_t7_railgun", 2, 40, "rail", [["charge_0", {"charge": 0}], ["charge_1", {"charge": 1}]], [6, 4]],
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


## C.bld (same states, rot schema, bytes accounting and DL7 g7 block) on a canvas widened by pad = [px each
## side, px below]; the pivot moves with it and is recorded in the manifest, so the catalog places it unchanged.
static func _cv(size: int, top: int, pad: Array) -> Array:
	var w := size * 64 + 12 + 2 * int(pad[0])
	var o := Vector2(w / 2, top + size * 16)
	return [P.Canvas.new(w, int(o.y) + size * 16 + 6 + int(pad[1])), o]


static func bldx(out: Dictionary, id: String, size: int, top: int, pad: Array, draw: Callable, extra: Array, g7x: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("buildings", {})
	var co0: Array = _cv(size, top, pad)
	var o: Vector2 = co0[1]
	var entry := {"size": size, "pivot": [int(o.x), int(o.y)], "fw": int(co0[0].w), "fh": int(co0[0].h),
		"states": {}, "g6": {"variants": "rot", "faction": id.substr(0, 1)}}
	var seed := 7100 + absi(id.hash()) % 7919
	var bytes := 0
	for f in 4:
		var cv = _cv(size, top, pad)[0]
		draw.call(cv, o, f, {})
		var base = H.copy(cv)
		C.selout(cv)
		bytes += C._bput(out, entry, id, "rot_%d" % f, cv)
		var cf = _cv(size, top, pad)[0]
		draw.call(cf, o, f, {"fire": true})
		C.selout(cf)
		if (cf.img as Image).get_data() != (cv.img as Image).get_data():
			bytes += C._bput(out, entry, id, "rot_%d_fire" % f, cf)
		var dm = H.copy(base)
		K.damage(dm, o, size, seed + f * 13)
		C.selout(dm)
		bytes += C._bput(out, entry, id, "rot_%d_damaged" % f, dm)
		for st in 3:
			bytes += C._bput(out, entry, id, "rot_%d_build_%d" % [f, st], H.stage(base, o, f, size, "a", st, seed + f))
	for e in extra:
		var cx = _cv(size, top, pad)[0]
		draw.call(cx, o, 0, e[1])
		C.selout(cx)
		bytes += C._bput(out, entry, id, String(e[0]), cx)
	for nm in ["built:rot_0", "damaged:rot_0_damaged", "fire:rot_0_fire", "build_0:rot_0_build_0",
			"build_1:rot_0_build_1", "build_2:rot_0_build_2"]:
		var pr: PackedStringArray = nm.split(":")
		if entry.states.has(pr[1]):
			entry.states[pr[0]] = (entry.states[pr[1]] as Dictionary).duplicate()
	var g7 := {"detail_level": C.VERSION, "class": "turret", "bytes": bytes, "budget": int(C.BUDGET.turret)}
	g7.merge(g7x)
	entry["g7"] = g7
	man[id] = entry
	out.manifest["buildings"] = man


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
		bldx(out, String(sp[0]), size, int(sp[2]), sp[5] as Array, _draw(String(sp[3])), ex,
			{"turret7": String(sp[3]), "scale": "4 m/tile, 9.8 px/m (fact art.scale), rev3 DL7-3", "art": "ART7B + ART7C readability pass",
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
