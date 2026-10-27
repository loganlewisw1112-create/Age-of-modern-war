extends RefCounted
## DL7-2 soldier kit gear (owner: ARTCN7): packs, chest items, head extras, weapons and act-frame effects for
## the counter-nanite strike team and the tactical operators. Pure drawing on a rig state R (g7_cn_lib.fpt);
## every radius / pixel offset scales with the rig (R.sc = C.FIG_S), so each role keeps its own silhouette.
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")

const METAL := Color8(62, 66, 70)
const GUNM := Color8(42, 45, 50)
const POLY := Color8(78, 74, 62)
const WOOD := Color8(104, 82, 58)
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
const SKIN := Color8(170, 128, 100)


static func _z(R: Dictionary) -> float:
	return float(R.get("sc", 1.0))


static func pack(cv, R: Dictionary, kit: Dictionary) -> void:
	var Z := _z(R)
	var lean: float = R.lean
	var hz: float = R.hip
	var bx: float = lean * 0.5 - 2.2
	var rp: Array = C.ramp(kit.plate)
	match String(kit.get("pack", "small")):
		"package":   # strike package: hazard-striped canister with status light, on a frame
			var a := C.fpt(R, bx - 0.2, 0.9, hz + 0.6)
			var b := C.fpt(R, bx - 0.2, 0.9, hz + 9.0)
			C.tube(cv, a, b, 1.7 * Z, C.ramp(Color8(148, 144, 118)))
			for i in 4:
				var m := a.lerp(b, 0.14 + 0.24 * i)
				cv.line_v(m + Vector2(-1.6 * Z, 0), m + Vector2(1.6 * Z, 0), HAZ if i % 2 == 0 else HAZ_D)
			C.blob(cv, b, 1.2 * Z, C.ramp(Color8(70, 72, 70)))
			cv.px(int(b.x), int(b.y) - 1, LED_G)
		"radio":
			var c := C.fpt(R, bx, 0, hz + 3.0)
			C.tube(cv, C.fpt(R, bx, 0, hz + 1.2), C.fpt(R, bx, 0, hz + 5.0), 1.75 * Z, rp)
			cv.line_v(c + Vector2(-1.2 * Z, -1.0 * Z), c + Vector2(1.2 * Z, -1.0 * Z), C.ramp(kit.plate)[0])
			var t := C.fpt(R, bx - 0.4, -1.2, hz + 14.0)
			cv.line_v(C.fpt(R, bx - 0.2, -1.0, hz + 5.0), t, ANT)
			cv.px(int(t.x), int(t.y), LED_R)
		"sensor":
			C.tube(cv, C.fpt(R, bx, 0, hz + 1.4), C.fpt(R, bx, 0, hz + 5.0), 1.75 * Z, rp)
			var m := C.fpt(R, bx - 0.3, 0.8, hz + 11.0)
			cv.line_v(C.fpt(R, bx - 0.2, 0.8, hz + 5.2), m, ANT)
			C.blob(cv, m, 1.0 * Z, C.ramp(SCAN))
		"ew":
			C.tube(cv, C.fpt(R, bx, 0, hz + 1.4), C.fpt(R, bx, 0, hz + 5.2), 1.85 * Z, C.ramp(Color8(70, 74, 80)))
			for s in [-1.0, 1.0]:
				cv.line_v(C.fpt(R, bx - 0.2, s * 1.4, hz + 5.0), C.fpt(R, bx - 0.8, s * 2.4, hz + 13.0), ANT)
			var l := C.fpt(R, bx + 0.2, 0, hz + 4.6)
			cv.px(int(l.x), int(l.y), JAM)
		"medic":
			var c := C.fpt(R, bx, 0, hz + 3.0)
			C.tube(cv, C.fpt(R, bx, 0, hz + 1.2), C.fpt(R, bx, 0, hz + 5.0), 1.75 * Z, C.ramp(Color8(176, 174, 160)))
			cv.rect(int(c.x) - 1, int(c.y - 2.0 * Z), 3, 1 + int(Z), MED)
			cv.rect(int(c.x), int(c.y - 2.0 * Z) - 1, 1, 3 + int(Z), MED)
		"demo":
			C.tube(cv, C.fpt(R, bx, 0, hz + 1.2), C.fpt(R, bx, 0, hz + 4.8), 1.7 * Z, C.ramp(Color8(96, 84, 64)))
			for s in [-1.0, 1.0]:
				C.blob(cv, C.fpt(R, bx - 0.6, s * 1.3, hz + 2.0), 0.7 * Z, C.ramp(THERM))
		"hunter":   # net launcher slung on the back + cable drum
			C.tube(cv, C.fpt(R, bx, -1.2, hz + 1.2), C.fpt(R, bx, 1.2, hz + 6.6), 1.2 * Z, C.ramp(Color8(84, 88, 76)))
			C.blob(cv, C.fpt(R, bx - 0.2, 0, hz + 3.0), 1.4 * Z, C.ramp(Color8(110, 104, 84)))
		_:
			C.tube(cv, C.fpt(R, bx + 0.2, 0, hz + 1.8), C.fpt(R, bx + 0.2, 0, hz + 4.6), 1.6 * Z, rp)


## Chest rig role markings on the front plate.
static func chest(cv, R: Dictionary, kit: Dictionary) -> void:
	var Z := _z(R)
	var lean: float = R.lean
	var hz: float = R.hip
	if C.depth(float(R.a), 1.0, 0.0) < -0.2:
		return
	var c := C.fpt(R, lean * 0.8 + 2.6, 0, hz + 3.8)
	match String(kit.get("chest", "pouches")):
		"emp":
			for s in [-1.0, 1.0]:
				C.blob(cv, C.fpt(R, lean * 0.8 + 2.6, s * 1.0, hz + 3.6), 0.55 * Z, C.ramp(EMP))
		"thermite":
			for s in [-1.0, 0.0, 1.0]:
				C.blob(cv, C.fpt(R, lean * 0.8 + 2.6, s * 1.0, hz + 3.6), 0.5 * Z, C.ramp(THERM))
		"medic":
			cv.rect(int(c.x) - 1, int(c.y) - 1, 3, 3, WHITE)
			for pp in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				cv.px(int(c.x) + pp.x, int(c.y) + pp.y, MED)
		_:
			cv.px(int(c.x), int(c.y), C.ramp(kit.plate)[4])
	if kit.has("rc"):   # role patch: tells the roles apart at idle at 18 px
		cv.rect(int(c.x) - 1, int(c.y) - 2, 2, 2, kit.rc)


## Head extras after the helmet: sealed visor + respirator, or NVG + face; leader band on the team mask.
static func head(cv, R: Dictionary, kit: Dictionary, hc: Vector2) -> void:
	var Z := _z(R)
	var a: float = R.a
	var fwd := C.sdir(a)
	var side := C.sdir(a + PI / 2.0)
	var front := C.depth(a, 1.0, 0.0) > -0.35
	if bool(kit.get("stripe", false)):   # leader: team band round the helmet
		C.tube(cv, hc - side * 1.7 * Z + Vector2(0, -0.5 * Z), hc + side * 1.7 * Z + Vector2(0, -0.5 * Z), 0.55 * Z,
			C.ramp(Color8(152, 152, 152)), true)
	var sealed := String(kit.get("head", "sealed")) == "sealed"
	if not front:
		if not sealed:   # NVG battery pack on the back of the helmet
			C.blob(cv, hc - fwd * 1.4 * Z + Vector2(0, -0.2 * Z), 0.6 * Z, C.ramp(GUNM))
		else:            # filter hose to the pack
			cv.line_v(hc + Vector2(0, 1.4 * Z), hc - fwd * 1.6 * Z + Vector2(0, 3.0 * Z), C.ramp(Color8(60, 62, 64))[1])
		return
	var vz := hc + fwd * 1.3 * Z
	if not sealed:
		C.blob(cv, vz + fwd * 0.4 * Z + Vector2(0, 1.6 * Z), 0.85 * Z, C.ramp(SKIN))   # face under the NVG
		C.blob(cv, vz + Vector2(0, -0.6 * Z), 0.8 * Z, C.ramp(GUNM))
		cv.px(int(vz.x + fwd.x * Z), int(vz.y - 0.5 * Z), kit.visor)
		cv.px(int(vz.x + fwd.x * Z + side.x * 1.2), int(vz.y - 0.5 * Z), C.ramp(kit.visor)[1])
	else:
		var gl: Array = C.ramp(Color8(44, 50, 54))
		var fp := hc + fwd * 1.0 * Z + Vector2(0, 0.4 * Z)
		C.tube(cv, fp - side * 0.7 * Z, fp + side * 0.7 * Z, 1.05 * Z, gl)      # dark faceplate
		var vr: Array = C.ramp(kit.visor)
		cv.line_v(fp - side * 1.1 * Z + Vector2(0, -0.5 * Z), fp + side * 0.3 * Z + Vector2(0, -0.8 * Z), vr[3])  # amber sheen
		cv.px(int(fp.x - side.x * 1.1 * Z), int(fp.y - side.y * 1.1 * Z - 0.5 * Z), vr[4])
		C.blob(cv, fp + fwd * 0.5 * Z + Vector2(0, 1.4 * Z), 0.7 * Z, C.ramp(Color8(66, 68, 70)))   # respirator
		C.blob(cv, fp + side * 1.2 * Z + Vector2(0, 1.5 * Z), 0.55 * Z, C.ramp(Color8(96, 98, 88)))  # filter can


static func _at(wb: Vector2, wt: Vector2, t: float) -> Vector2:
	return wb.lerp(wt, t)


## Weapon from wb (butt) to wt (muzzle), screen points. kind from kit.weapon. Z = rig scale.
static func weapon(cv, kit: Dictionary, wb: Vector2, wt: Vector2, flash: bool, Z := 1.0) -> void:
	var kind := String(kit.get("weapon", "rifle"))
	if kind == "none":
		return
	var rp: Array = C.ramp(METAL)
	var gp: Array = C.ramp(GUNM)
	var d := (wt - wb).normalized() if wt.distance_to(wb) > 0.1 else Vector2(1, 0)
	var n := Vector2(-d.y, d.x)
	if n.y < 0.0:
		n = -n   # n points down the screen (magazine / grip side)
	match kind:
		"shotgun":
			C.tube(cv, wb, _at(wb, wt, 0.3), 0.55 * Z, C.ramp(POLY))
			C.tube(cv, _at(wb, wt, 0.25), wt, 0.55 * Z, rp)
			C.tube(cv, _at(wb, wt, 0.5) + n * 0.6 * Z, _at(wb, wt, 0.95) + n * 0.6 * Z, 0.35 * Z, gp)
			C.tube(cv, _at(wb, wt, 0.55) + n * 0.7 * Z, _at(wb, wt, 0.72) + n * 0.7 * Z, 0.55 * Z, C.ramp(WOOD))
		"dmr":
			C.tube(cv, wb, _at(wb, wt, 0.25), 0.6 * Z, C.ramp(POLY))
			C.tube(cv, _at(wb, wt, 0.2), _at(wb, wt, 0.7), 0.55 * Z, rp)
			C.tube(cv, _at(wb, wt, 0.7), wt, 0.3 * Z, gp)
			C.tube(cv, _at(wb, wt, 0.28) - n * 0.9 * Z, _at(wb, wt, 0.55) - n * 0.9 * Z, 0.42 * Z, gp)   # scope
			var lens := _at(wb, wt, 0.56) - n * 0.9 * Z
			cv.px(int(lens.x), int(lens.y), Color8(160, 220, 255))
			C.tube(cv, _at(wb, wt, 0.42), _at(wb, wt, 0.42) + n * 1.4 * Z, 0.38 * Z, gp)
			cv.line_v(_at(wb, wt, 0.78), _at(wb, wt, 0.74) + n * 2.2 * Z, ANT)   # bipod
		"harpoon":
			C.tube(cv, wb, _at(wb, wt, 0.8), 0.85 * Z, C.ramp(Color8(80, 86, 74)))
			C.blob(cv, _at(wb, wt, 0.45) + n * 0.8 * Z, 1.0 * Z, C.ramp(Color8(110, 104, 84)))   # cable drum
			cv.line_v(_at(wb, wt, 0.8), wt + d * 2.0 * Z, Color8(200, 204, 196))
			C.blob(cv, wt + d * 2.0 * Z, 0.5 * Z, C.ramp(WHITE))
		"launcher":
			C.tube(cv, wb, wt, 0.8 * Z, C.ramp(Color8(78, 84, 70)))
			C.blob(cv, _at(wb, wt, 0.42) + n * 0.5 * Z, 1.25 * Z, C.ramp(Color8(70, 76, 64)))   # drum
			C.blob(cv, wt, 0.75 * Z, gp)
		"jammer":
			C.tube(cv, wb, _at(wb, wt, 0.75), 0.6 * Z, C.ramp(Color8(66, 70, 76)))
			C.tube(cv, _at(wb, wt, 0.4), _at(wb, wt, 0.4) + n * 1.3 * Z, 0.4 * Z, gp)
			for i in 3:
				var m: Vector2 = wt - d * (i * 1.2 * Z)
				cv.line_v(m - n * (2.0 - i * 0.4) * Z, m + n * (2.0 - i * 0.4) * Z, ANT)
			var led := _at(wb, wt, 0.55)
			cv.px(int(led.x), int(led.y), JAM)
		_:   # carbine / rifle
			C.tube(cv, wb, _at(wb, wt, 0.28), 0.55 * Z, C.ramp(POLY))
			C.tube(cv, _at(wb, wt, 0.22), _at(wb, wt, 0.72), 0.55 * Z, rp)
			C.tube(cv, _at(wb, wt, 0.72), wt, 0.3 * Z, gp)
			C.tube(cv, _at(wb, wt, 0.46), _at(wb, wt, 0.42) + n * 1.5 * Z, 0.38 * Z, gp)   # magazine
			C.blob(cv, _at(wb, wt, 0.4) - n * 0.75 * Z, 0.45 * Z, gp)                     # optic
	cv.px(int(wb.x), int(wb.y), rp[0])
	if flash:
		var m := wt + d * 2.0 * Z
		C.blob(cv, m, 1.2 * Z, [FLASH_O, FLASH_O, FLASH, FLASH, FLASH])
		cv.line_v(m, m + d * 3.0 * Z, FLASH)


## Hand / weapon placement for the two act frames (overrides the rig defaults). Signal pose otherwise.
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
