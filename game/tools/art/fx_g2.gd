extends RefCounted
## G2 effects, markers and command icons (agent E2). Runs after fx_ui.gd (adds to its manifest maps).
##   effects: disabled_smoke (6-frame seamless loop, pivot = smoke base), pinned (2 frames),
##            cover (1 frame shield pip), retreat (2 frames, double chevron pointing screen +x).
##   icons:   repair, patrol, guard, formation_line/wedge/column, mission_secure/hold/attack/patrol,
##            assign_officer (32x32 on the shared HUD panel).
const P = preload("res://tools/art/pix.gd")
const FX = preload("res://tools/art/fx_ui.gd")

const INK := Color8(222, 216, 184)
const INK_D := Color8(150, 146, 120)
const TEAM := Color(0.36, 0.52, 0.74)
const RED := Color8(220, 92, 70)
const GOLD := Color8(232, 196, 92)
const AMBER := Color8(242, 178, 58)


static func build(out: Dictionary) -> void:
	var fx: Dictionary = out.manifest.get("effects", {})
	fx["disabled_smoke"] = _sheet(out, "disabled_smoke", 6, 32, 48, _smoke_frame)
	fx["disabled_smoke"]["pivot"] = [16, 44]
	fx["pinned"] = _sheet(out, "pinned", 2, 16, 12, _pinned_frame)
	fx["cover"] = _sheet(out, "cover", 1, 11, 12, _cover_frame)
	fx["retreat"] = _sheet(out, "retreat", 2, 14, 10, _retreat_frame)
	out.manifest["effects"] = fx
	var icons: Dictionary = out.manifest.get("icons", {})
	for id in ["repair", "patrol", "guard", "formation_line", "formation_wedge", "formation_column",
			"mission_secure", "mission_hold", "mission_attack", "mission_patrol", "assign_officer"]:
		var cv = P.Canvas.new(32, 32)
		_glyph(cv, id)
		cv.outline(Color(0.05, 0.05, 0.04, 1))
		var im: Image = FX._panel()
		im.blend_rect(cv.img, Rect2i(0, 0, 32, 32), Vector2i.ZERO)
		out.images["icons/%s.png" % id] = im
		icons[id] = "icons/%s.png" % id
	out.manifest["icons"] = icons


static func _sheet(out: Dictionary, nm: String, n: int, fw: int, fh: int, fn: Callable) -> Dictionary:
	var sheet := Image.create(fw * n, fh, false, Image.FORMAT_RGBA8)
	for f in n:
		var cv = P.Canvas.new(fw, fh)
		fn.call(cv, f, n)
		sheet.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(f * fw, 0))
	out.images["fx/%s.png" % nm] = sheet
	return {"file": "fx/%s.png" % nm, "fw": fw, "fh": fh, "frames": n}


## Oily smoke column with a flickering fire at the base; puffs wrap phase so frame 5 -> 0 is seamless.
static func _smoke_frame(cv, f: int, n: int) -> void:
	for i in 6:
		var ph := fmod((i + float(f) / n) / 6.0, 1.0)
		var c := Vector2(15.5 + sin(ph * 4.0 + i) * 2.0 + ph * 6.0, 43.0 - ph * 36.0)
		var r := 2.5 + ph * 5.5
		var a := (1.0 - ph * 0.85) * 0.86 * minf(1.0, ph * 6.0 + 0.45)
		for y in range(int(c.y - r), int(c.y + r) + 1):
			for x in range(int(c.x - r), int(c.x + r) + 1):
				var dx := (x + 0.5 - c.x) / r
				var dy := (y + 0.5 - c.y) / r
				var d := dx * dx + dy * dy
				if d > 1.0 or P.vnoise(x, y + i * 7, 2.2, 640 + i) < 0.08 + d * 0.32:
					continue
				var g := 0.13 + ph * 0.2 + (1.0 - d) * 0.06 - dy * 0.04
				cv.px(x, y, Color(g, g * 0.97, g * 0.94, a * (1.0 - d * 0.4)))
	var fl := P.hn(f, 3, 651)
	for k in 3:  # flames
		var fx := 14 + k * 2 + int(P.hn(f, k, 652) * 2.0)
		var hgt := 3 + int(P.hn(f, k + 4, 653) * 4.0 + fl * 2.0)
		for y in hgt:
			var t := float(y) / hgt
			cv.px(fx, 45 - y, P.mix(Color8(255, 236, 150), Color8(232, 96, 30), t))
			if t < 0.5:
				cv.px(fx + 1, 45 - y, Color8(246, 150, 50))
	cv.px(16, 46, Color8(255, 250, 210))


## Suppression marker: amber down-arrow pressing on a bar (bobs 1 px between frames).
static func _pinned_frame(cv, f: int, _n: int) -> void:
	var y0 := 1 + f
	cv.rect(6, y0, 4, 4, AMBER)
	for k in 4:
		cv.rect(4 + k, y0 + 4 + k, 8 - k * 2, 1, AMBER)
	cv.px(7, y0, P.mul(AMBER, 1.2))
	cv.rect(2, 10, 12, 1, RED)
	cv.outline(Color(0.06, 0.05, 0.03, 1))


## In-cover pip: small green shield with a lit rim.
static func _cover_frame(cv, _f: int, _n: int) -> void:
	var g := Color8(96, 176, 112)
	for y in 10:
		var hw := 4 if y < 5 else 4 - (y - 4) * 4 / 5
		for x in range(5 - hw, 6 + hw):
			var c := g if x > 5 - hw else P.mul(g, 1.35)
			cv.px(x, y + 1, P.mul(c, 0.82) if y > 6 else c)
	cv.rect(2, 1, 7, 1, P.mul(g, 1.45))
	cv.px(5, 4, Color8(230, 246, 220))
	cv.outline(Color(0.04, 0.06, 0.04, 1))


## Retreat marker: red double chevron pointing screen +x (rotate to the heading); slides 1 px.
static func _retreat_frame(cv, f: int, _n: int) -> void:
	for k in 2:
		var x0 := 2 + k * 5 + f
		for y in 4:
			cv.rect(x0 + y, 1 + y, 2, 1, RED if k == 0 else P.mul(RED, 1.2))
			cv.rect(x0 + y, 7 - y, 2, 1, RED if k == 0 else P.mul(RED, 1.2))
		cv.rect(x0 + 4, 4, 2, 1, P.mul(RED, 1.3))
	cv.outline(Color(0.07, 0.03, 0.02, 1))


static func _dot(cv, x: int, y: int, c: Color) -> void:
	cv.rect(x - 1, y - 1, 3, 3, c)
	cv.px(x - 1, y - 1, P.mul(c, 1.25))


static func _thick(cv, a: Vector2, b: Vector2, c: Color) -> void:
	cv.line_v(a, b, c)
	cv.line_v(a + Vector2(1, 0), b + Vector2(1, 0), P.mul(c, 0.8))


static func _ring(cv, cx: float, cy: float, rx: float, ry: float, c: Color, dashed := false) -> void:
	for i in 64:
		if dashed and (i / 4) % 2 == 1:
			continue
		var a := i * TAU / 64.0
		cv.px(int(cx + cos(a) * rx), int(cy + sin(a) * ry), c)


static func _arrowhead(cv, tip: Vector2, dir: Vector2, c: Color) -> void:
	var d := dir.normalized()
	var pp := Vector2(-d.y, d.x)
	cv.line_v(tip, tip - d * 4 + pp * 3, c)
	cv.line_v(tip, tip - d * 4 - pp * 3, c)


static func _shield(cv, cx: int, cy: int, s: int, c: Color) -> void:
	for y in s * 2:
		var hw := s if y < s else s - (y - s + 1) * s / s
		for x in range(cx - hw, cx + hw):
			cv.px(x, cy - s + y, c if x > cx - hw else P.mul(c, 1.3))
	cv.rect(cx - s, cy - s, s * 2, 1, P.mul(c, 1.45))


static func _glyph(cv, id: String) -> void:
	match id:
		"repair":
			_thick(cv, Vector2(8, 24), Vector2(19, 13), INK)
			_thick(cv, Vector2(9, 25), Vector2(20, 14), INK_D)
			_ring(cv, 22, 10, 4.5, 4.5, INK)
			for yy in range(5, 9):  # open jaw
				for xx in range(21, 25):
					cv.img.set_pixel(xx, yy, Color(0, 0, 0, 0))
			for k in 3:
				cv.px(23 + k, 6 + k, Color8(40, 44, 40))
			cv.rect(24, 21, 5, 1, GOLD)
			cv.rect(26, 19, 1, 5, GOLD)
		"patrol":
			_dot(cv, 8, 22, TEAM)
			_dot(cv, 24, 9, TEAM)
			cv.line(10, 18, 21, 9, INK)
			_arrowhead(cv, Vector2(21, 9), Vector2(11, -9), INK)
			cv.line(22, 13, 11, 23, INK_D)
			_arrowhead(cv, Vector2(11, 23), Vector2(-11, 10), INK_D)
		"guard":
			_shield(cv, 16, 15, 8, TEAM)
			cv.rect(15, 10, 2, 9, INK)
			cv.rect(12, 13, 8, 2, INK)
		"formation_line":
			for k in 4:
				_dot(cv, 7 + k * 6, 18, INK)
			_arrowhead(cv, Vector2(16, 8), Vector2(0, -1), TEAM)
			cv.line(16, 8, 16, 13, TEAM)
		"formation_wedge":
			for p in [Vector2i(16, 8), Vector2i(11, 14), Vector2i(21, 14), Vector2i(6, 20), Vector2i(26, 20)]:
				_dot(cv, p.x, p.y, INK)
			cv.line(16, 24, 16, 27, TEAM)
		"formation_column":
			for k in 4:
				_dot(cv, 16, 6 + k * 6, INK)
			_arrowhead(cv, Vector2(23, 6), Vector2(0, -1), TEAM)
			cv.line(23, 6, 23, 14, TEAM)
		"mission_secure":
			_ring(cv, 16, 23, 10, 4, INK_D)
			cv.line(13, 6, 13, 23, INK)
			cv.poly(PackedVector2Array([Vector2(14, 6), Vector2(24, 9.5), Vector2(14, 13)]), TEAM)
		"mission_hold":
			_ring(cv, 16, 17, 11, 9, INK, true)
			cv.poly(PackedVector2Array([Vector2(16, 11), Vector2(21, 17), Vector2(16, 23), Vector2(11, 17)]), TEAM)
			cv.px(15, 13, INK)
		"mission_attack":
			_ring(cv, 16, 16, 8, 8, RED)
			_ring(cv, 16, 16, 7, 7, P.mul(RED, 0.75))
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				cv.line(16 + d.x * 5, 16 + d.y * 5, 16 + d.x * 12, 16 + d.y * 12, INK)
			_dot(cv, 16, 16, RED)
		"mission_patrol":
			var pts := [Vector2(7, 9), Vector2(25, 8), Vector2(24, 24), Vector2(8, 23)]
			for i in 4:
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[(i + 1) % 4]
				for t in 8:
					if t % 2 == 0:
						cv.line_v(a.lerp(b, t / 8.0), a.lerp(b, (t + 1) / 8.0), INK)
			for p in pts:
				_dot(cv, int(p.x), int(p.y), TEAM)
			_arrowhead(cv, Vector2(19, 8), Vector2(1, 0), INK)
		"assign_officer":
			for k in 5:  # 5-point star (officer)
				var a := -PI / 2 + k * TAU / 5.0
				cv.line_v(Vector2(10, 11), Vector2(10, 11) + Vector2(cos(a), sin(a)) * 6.0, GOLD)
			cv.rect(9, 10, 3, 3, GOLD)
			cv.line(15, 15, 22, 21, INK)
			_arrowhead(cv, Vector2(22, 21), Vector2(1, 1), INK)
			for p in [Vector2i(25, 25), Vector2i(20, 27), Vector2i(27, 19)]:
				_dot(cv, p.x, p.y, TEAM)
