extends RefCounted
## DL7 soldier kit gear (owner: ARTCN7): packs, chest items, head extras, weapons and act-frame effects for
## the counter-nanite strike team and the tactical operators. Pure drawing on a rig state R (g7_cn_lib.fpt).
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")

const METAL := Color8(60, 64, 70)
const GUNM := Color8(44, 47, 52)
const FLASH := Color8(255, 232, 150)
const FLASH_O := Color8(255, 150, 58)
const HAZ := Color8(226, 184, 40)
const HAZ_D := Color8(40, 38, 34)
const LED_G := Color8(120, 255, 150)
const LED_R := Color8(255, 80, 60)
const EMP := Color8(120, 196, 255)
const JAM := Color8(196, 140, 255)
const THERM := Color8(236, 120, 40)
const WHITE := Color8(228, 230, 224)
const MED := Color8(196, 52, 48)
const SCAN := Color8(255, 196, 96)
const NET := Color8(196, 190, 160)
const ANT := Color8(30, 32, 34)


static func pack(cv, R: Dictionary, kit: Dictionary) -> void:
	var lean: float = R.lean
	var hz: float = R.hip
	var rp: Array = C.ramp(kit.plate)
	match String(kit.get("pack", "small")):
		"package":   # strike package: hazard-striped canister with status light
			var a := C.fpt(R, lean * 0.5 - 2.6, 0, hz + 0.4)
			var b := C.fpt(R, lean * 0.5 - 2.6, 0, hz + 6.4)
			C.tube(cv, a, b, 2.3, C.ramp(Color8(150, 146, 120)))
			for i in 3:
				var m := a.lerp(b, 0.2 + 0.3 * i)
				cv.line_v(m + Vector2(-2, 0), m + Vector2(2, 0), HAZ if i % 2 == 0 else HAZ_D)
			cv.px(int(b.x), int(b.y) - 1, LED_G)
		"radio":
			var c := C.fpt(R, lean * 0.5 - 2.2, 0, hz + 3.0)
			C.blob(cv, c, 2.1, rp)
			var t := C.fpt(R, lean * 0.5 - 2.6, -1.2, hz + 13.0)
			cv.line_v(C.fpt(R, lean * 0.5 - 2.4, -1.0, hz + 4.6), t, ANT)
			cv.px(int(t.x), int(t.y), LED_R)
		"sensor":
			C.blob(cv, C.fpt(R, lean * 0.5 - 2.2, 0, hz + 3.2), 2.0, rp)
			var m := C.fpt(R, lean * 0.5 - 2.5, 0.8, hz + 10.0)
			cv.line_v(C.fpt(R, lean * 0.5 - 2.4, 0.8, hz + 5.0), m, ANT)
			C.blob(cv, m, 1.1, C.ramp(SCAN))
		"ew":
			C.blob(cv, C.fpt(R, lean * 0.5 - 2.2, 0, hz + 3.2), 2.2, C.ramp(Color8(70, 74, 80)))
			for s in [-1.0, 1.0]:
				cv.line_v(C.fpt(R, lean * 0.5 - 2.4, s * 1.4, hz + 4.8), C.fpt(R, lean * 0.5 - 3.0, s * 2.2, hz + 12.5), ANT)
			cv.px(int(C.fpt(R, lean * 0.5 - 2.0, 0, hz + 4.6).x), int(C.fpt(R, lean * 0.5 - 2.0, 0, hz + 4.6).y), JAM)
		"medic":
			var c := C.fpt(R, lean * 0.5 - 2.3, 0, hz + 3.0)
			C.blob(cv, c, 2.1, C.ramp(Color8(196, 194, 182)))
			cv.line_v(c + Vector2(-1, 0), c + Vector2(1, 0), MED)
			cv.line_v(c + Vector2(0, -1), c + Vector2(0, 1), MED)
		"demo":
			var c := C.fpt(R, lean * 0.5 - 2.3, 0, hz + 2.8)
			C.blob(cv, c, 2.0, C.ramp(Color8(96, 84, 64)))
			cv.line_v(c + Vector2(-1, -1), c + Vector2(1, -1), THERM)
		"hunter":   # net launcher slung on the back
			C.tube(cv, C.fpt(R, lean * 0.5 - 2.4, -1.0, hz + 1.5), C.fpt(R, lean * 0.5 - 2.4, 1.0, hz + 6.0), 1.4, C.ramp(Color8(84, 88, 76)))
		_:
			C.blob(cv, C.fpt(R, lean * 0.5 - 2.0, 0, hz + 3.2), 1.7, rp)


## Chest rig items on the front plate.
static func chest(cv, R: Dictionary, kit: Dictionary) -> void:
	var lean: float = R.lean
	var hz: float = R.hip
	var c := C.fpt(R, lean * 0.7 + 1.9, 0, hz + 2.6)
	match String(kit.get("chest", "pouches")):
		"emp":
			cv.px(int(c.x) - 1, int(c.y), EMP)
			cv.px(int(c.x) + 1, int(c.y), EMP)
		"thermite":
			cv.px(int(c.x) - 1, int(c.y), THERM)
			cv.px(int(c.x), int(c.y), THERM)
			cv.px(int(c.x) + 1, int(c.y), THERM)
		"medic":
			cv.px(int(c.x), int(c.y), MED)
		_:
			cv.px(int(c.x), int(c.y), C.ramp(kit.plate)[1])


## Head extras after the helmet (sealed hood respirator, NVG tubes, leader stripe on the team mask).
static func head(cv, R: Dictionary, kit: Dictionary, hc: Vector2) -> void:
	var a: float = R.a
	var fwd := C.sdir(a)
	var front := C.depth(a, 1.0, 0.0) > -0.35
	if bool(kit.get("stripe", false)):
		C.blob(cv, hc + Vector2(0, -1.6), 0.8, C.ramp(Color8(150, 150, 150)), true)
	if not front:
		return
	var vz := hc + fwd * 1.5
	if String(kit.get("head", "sealed")) == "nvg":
		C.blob(cv, vz + Vector2(0, -0.6), 0.9, C.ramp(GUNM))
		cv.px(int(vz.x), int(vz.y), kit.visor)
	else:
		var side := C.sdir(a + PI / 2.0)
		var vr: Array = C.ramp(kit.visor)
		cv.line_v(vz - side * 1.4, vz + side * 1.4, vr[2])
		cv.line_v(vz - side * 1.4 + Vector2(0, -1), vz + side * 1.4 + Vector2(0, -1), vr[3])
		cv.px(int(vz.x - side.x), int(vz.y - side.y) - 1, vr[4])
		C.blob(cv, hc + fwd * 1.3 + Vector2(0, 1.4), 0.8, C.ramp(Color8(70, 72, 74)))  # respirator


## Weapon from wb (butt) to wt (muzzle), screen points. kind from kit.weapon.
static func weapon(cv, kit: Dictionary, wb: Vector2, wt: Vector2, flash: bool) -> void:
	var kind := String(kit.get("weapon", "rifle"))
	var rp: Array = C.ramp(METAL)
	var d := (wt - wb).normalized() if wt.distance_to(wb) > 0.1 else Vector2(1, 0)
	match kind:
		"shotgun":
			C.tube(cv, wb, wt, 0.8, rp)
			C.blob(cv, wb.lerp(wt, 0.55), 0.9, C.ramp(Color8(88, 74, 58)))
		"dmr":
			C.tube(cv, wb, wt, 0.6, rp)
			var s := wb.lerp(wt, 0.4) + Vector2(0, -1)
			cv.line_v(s - d * 1.5, s + d * 1.5, GUNM)
			cv.px(int(s.x + d.x * 2), int(s.y + d.y * 2), Color8(160, 220, 255))
		"harpoon":
			C.tube(cv, wb, wt, 0.9, C.ramp(Color8(80, 86, 74)))
			cv.line_v(wt, wt + d * 2.5, Color8(200, 204, 196))
			cv.px(int(wt.x + d.x * 3), int(wt.y + d.y * 3), WHITE)
		"launcher":
			C.tube(cv, wb, wt, 1.0, rp)
			C.blob(cv, wb.lerp(wt, 0.45), 1.4, C.ramp(Color8(78, 84, 70)))
		"jammer":
			C.tube(cv, wb, wt, 0.7, rp)
			var side := Vector2(-d.y, d.x)
			cv.line_v(wt - side * 1.8, wt + side * 1.8, ANT)
			cv.line_v(wt - side * 1.8 - d, wt + side * 1.8 - d, ANT)
		"carbine":
			C.tube(cv, wb, wt, 0.65, rp)
		"none":
			return
		_:
			C.tube(cv, wb, wt, 0.7, rp)
	cv.px(int(wb.x), int(wb.y), C.ramp(METAL)[0])
	if flash:
		var m := wt + d * 1.8
		C.blob(cv, m, 1.3, [FLASH_O, FLASH_O, FLASH, FLASH, FLASH])
		cv.line_v(m, m + d * 2.5, FLASH)


## Hand / weapon placement for the two act frames (overrides the rig defaults). Returns {} for "signal".
static func act_hands(kit: Dictionary, lean: float, hz: float, ph: int, wl: float) -> Dictionary:
	match String(kit.get("act", "signal")):
		"throw":
			if ph == 0:
				return {"rh": Vector3(lean - 2.0, 1.8, hz + 6.6), "lh": Vector3(lean + 3.0, -0.6, hz + 4.8)}
			return {"rh": Vector3(lean + 3.2, 1.0, hz + 6.0), "lh": Vector3(lean - 0.5, -1.4, hz + 2.6)}
		"arm", "treat", "place":
			return {"rh": Vector3(lean + 3.6, 0.8, hz + 0.6 + ph), "lh": Vector3(lean + 3.8, -0.8, hz + 1.0),
				"wb": Vector3(lean - 1.4, 1.6, hz + 4.8), "wt": Vector3(lean + 0.2, 2.4, hz + 0.2)}
		"scan", "jam", "scope", "harpoon", "launch":
			return {"rh": Vector3(lean + 2.2, 0.9, hz + 4.2), "lh": Vector3(lean + 4.6, 0.0, hz + 4.3),
				"wb": Vector3(lean + 0.2, 0.8, hz + 4.8), "wt": Vector3(lean + 0.2 + wl, 0.6, hz + 4.8 + ph * 0.6)}
		"handset":
			return {"rh": Vector3(lean + 0.8, 1.6, hz + 7.0), "lh": Vector3(lean + 3.6, -0.2, hz + 2.9)}
	return {"rh": Vector3(lean + 1.0, 2.8, hz + 9.0 + ph), "lh": Vector3(lean + 3.6, -0.2, hz + 2.9)}
