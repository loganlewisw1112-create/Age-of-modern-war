extends RefCounted
## G4b effect sprites (agent ART-U) -> manifest.effects[name] = {file, fw, fh, frames, pivot[, mask, variants]}
## in the same 1-row strip format as fx_g2.gd (ArtCatalog.effect_frames cuts frames by fw):
##   fire_forest    3-frame flame loop over a burning forest tile (64x56, pivot = tile centre)
##   burnt_ground   3 variants (not an animation) of a charred 64x32 diamond overlay, pivot [32, 16]
##   mine           2-frame own-side mine marker (LED blink); `mask` = team ring
##   mine_detected  2-frame red/yellow warning pulse for an enemy mine revealed by a detector
##   charge         2-frame demolition charge (LED blink); `mask` = team strap
##   flame_jet      4-frame flamethrower jet pointing screen +x from pivot [2, 8] (renderer rotates/scales)
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/g4_units_lib.gd")

const NAMES := ["fire_forest", "burnt_ground", "mine", "mine_detected", "charge", "flame_jet"]


static func build(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("effects", {})
	man["fire_forest"] = _sheet(out, "fire_forest", 3, 64, 56, [32, 44], _fire, false)
	man["burnt_ground"] = _sheet(out, "burnt_ground", 3, 64, 32, [32, 16], _burnt, false)
	man["burnt_ground"]["variants"] = 3
	man["mine"] = _sheet(out, "mine", 2, 12, 8, [6, 5], _mine, true)
	man["mine_detected"] = _sheet(out, "mine_detected", 2, 16, 12, [8, 7], _mine_detected, false)
	man["charge"] = _sheet(out, "charge", 2, 12, 12, [6, 9], _charge, true)
	man["flame_jet"] = _sheet(out, "flame_jet", 4, 48, 16, [2, 8], _jet, false)
	out.manifest["effects"] = man


static func _sheet(out: Dictionary, nm: String, n: int, fw: int, fh: int, piv: Array, fn: Callable, mask: bool) -> Dictionary:
	var img := Image.create(fw * n, fh, false, Image.FORMAT_RGBA8)
	var msk := Image.create(fw * n, fh, false, Image.FORMAT_RGBA8)
	for i in n:
		var cv = P.Canvas.new(fw, fh)
		fn.call(cv, i)
		img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(i * fw, 0))
		msk.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i(i * fw, 0))
	var e := {"file": "fx/%s.png" % nm, "fw": fw, "fh": fh, "frames": n, "pivot": piv.duplicate()}
	out.images[e.file] = img
	if mask:
		e["mask"] = "fx/%s_mask.png" % nm
		out.images[e.mask] = msk
	return e


# ---------------------------------------------------------------- fire on forest
static func _fire(cv, i: int) -> void:
	cv.ellipse(32, 44, 26, 10, Color(1.0, 0.45, 0.1, 0.18))
	cv.ellipse(32, 44, 16, 6, Color(1.0, 0.55, 0.15, 0.18))
	var order: Array = []
	for j in 8:
		var bx := 8.0 + j * 6.8 + (P.hn(j, 0, 901) - 0.5) * 4.0
		var lim := 16.0 * (1.0 - absf(bx - 32.0) / 32.0) * 0.6
		var by := 44.0 + (P.hn(j, 1, 902) - 0.5) * 2.0 * lim
		order.append([by, j, bx])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for it in order:
		var j: int = it[1]
		var h := 9.0 + P.hn(j, i + 3, 903) * 14.0
		var lean := (P.hn(j, i + 7, 904) - 0.5) * 5.0
		_tongue(cv, Vector2(it[2], it[0]), h, lean, 2.4 + P.hn(j, 2, 905) * 1.4)
	for j in 3:  # smoke drifting off the canopy
		var sp := Vector2(18 + j * 13 + i * 2, 9 + P.hn(j, i, 906) * 6.0)
		L.puff(cv, sp, 4.0 + P.hn(j, 5, 907) * 2.0, 0.32, Color(0.24, 0.23, 0.21))
	for j in 7:  # embers
		var ex := 10 + P.hi(j, i, 908, 44)
		var ey := 14 + P.hi(j, i, 909, 22)
		cv.px(ex, ey, Color8(255, 200, 90) if j % 2 == 0 else Color8(255, 130, 50))


static func _tongue(cv, b: Vector2, h: float, lean: float, w: float) -> void:
	var n := int(h)
	for k in n:
		var t := float(k) / h
		var c := b + Vector2(lean * t * t, -k)
		var r := w * (1.0 - t * 0.85)
		var col: Color = Color8(255, 236, 160) if t < 0.3 else (Color8(255, 170, 60) if t < 0.65 else Color8(214, 80, 30))
		cv.ellipse(c.x, c.y, r, r * 0.9, Color(col.r, col.g, col.b, 0.92 - t * 0.4))
	for k in int(h * 0.45):
		cv.px(int(b.x + lean * 0.05), int(b.y) - k, Color8(255, 250, 214))


# ---------------------------------------------------------------- burnt ground
static func _burnt(cv, i: int) -> void:
	for y in 32:
		for x in 64:
			if not P.in_diamond(x, y, 64, 32):
				continue
			var e := absf(x + 0.5 - 32.0) / 32.0 + absf(y + 0.5 - 16.0) / 16.0
			var n := P.vnoise(x, y * 2.0, 7.0, 910 + i * 17) * 0.6 + P.vnoise(x, y * 2.0, 3.0, 911 + i) * 0.4
			var v := n + 0.25 - e * 0.6
			if v < 0.3:
				continue
			var a := clampf((v - 0.3) * 3.5, 0.0, 0.82)
			var col := Color8(34, 30, 26)
			var hh := P.hn(x, y, 912 + i)
			if hh > 0.93:
				col = Color8(118, 114, 106)  # ash flecks
			elif hh < 0.05:
				col = Color8(62, 44, 30)  # charred stubble
			cv.px(x, y, Color(col.r, col.g, col.b, a))


# ---------------------------------------------------------------- mine / charge
static func _mine(cv, i: int) -> void:
	cv.ellipse(6.5, 5.0, 4.6, 2.2, Color.BLACK, true)
	cv.flush_shadow()
	cv.team = true
	cv.ellipse(6, 4.5, 4.2, 2.3, Color(0.7, 0.7, 0.7))
	cv.team = false
	cv.ellipse(6, 4.3, 3.0, 1.6, Color8(58, 62, 48))
	cv.ellipse(5.5, 3.8, 1.2, 0.6, Color8(88, 92, 72))
	cv.px(6, 4, Color8(36, 38, 30))
	cv.outline()
	cv.px(8, 3, Color8(255, 70, 50) if i == 0 else Color8(96, 32, 26))


static func _mine_detected(cv, i: int) -> void:
	var r := 6.5 if i == 0 else 5.0
	for y in 12:
		for x in 16:
			var dx := (x + 0.5 - 8.0) / r
			var dy := (y + 0.5 - 6.5) / (r * 0.6)
			var d := dx * dx + dy * dy
			if d <= 1.0 and d >= 0.62:
				cv.px(x, y, Color8(255, 210, 60) if (x + y) % 3 != 0 else Color8(230, 60, 40))
	cv.ellipse(8, 6.5, 3.0, 1.6, Color8(70, 66, 56))
	cv.px(8, 6, Color8(230, 60, 40))
	cv.outline()


static func _charge(cv, i: int) -> void:
	cv.ellipse(6.5, 9.0, 4.5, 1.8, Color.BLACK, true)
	cv.flush_shadow()
	cv.rect(3, 5, 6, 4, Color8(150, 128, 78))
	cv.rect(3, 5, 6, 1, Color8(186, 164, 104))
	cv.rect(8, 6, 1, 3, Color8(116, 98, 60))
	cv.team = true
	cv.rect(3, 7, 6, 1, Color(0.72, 0.72, 0.72))
	cv.team = false
	cv.rect(4, 3, 3, 2, Color8(50, 52, 46))
	cv.line(7, 4, 10, 2, Color8(200, 60, 40))
	cv.outline()
	cv.px(5, 3, Color8(255, 60, 40) if i == 0 else Color8(80, 28, 24))


# ---------------------------------------------------------------- flame jet
static func _jet(cv, i: int) -> void:
	var n := 40 + i * 2
	for k in n:
		var t := float(k) / 44.0
		var wob := (P.hn(k, i, 921) - 0.5) * 2.0 * t * 3.0 + sin(k * 0.4 + i * 1.6) * t * 1.5
		var r := 1.0 + t * 5.0
		var col: Color = Color8(255, 246, 196) if t < 0.2 else (Color8(255, 190, 70) if t < 0.55 else Color8(220, 96, 36))
		cv.ellipse(2.0 + k, 8.0 + wob, r * 0.8, r * 0.75, Color(col.r, col.g, col.b, 0.95 - t * 0.5))
	cv.line(2, 8, 13 + i, 8, Color8(255, 255, 230))
	L.puff(cv, Vector2(41 + i, 6), 3.0, 0.3, Color(0.26, 0.24, 0.22))
