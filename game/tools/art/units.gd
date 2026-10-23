extends RefCounted
## Infantry sprite sheets. Rows = 8 facings (world angle k * 45 deg), columns = frames.
## Every sheet has a greyscale twin `_mask.png` marking team-colour pixels.
const P = preload("res://tools/art/pix.gd")

const FRAMES := ["idle", "walk_a", "walk_b", "fire"]
const FW := 24
const FH := 26
const PIV := Vector2i(12, 21)

const UNIFORM := Color8(96, 98, 66)
const TROUSER := Color8(74, 76, 54)
const BOOT := Color8(40, 36, 30)
const SKIN := Color8(170, 134, 104)
const HELMET := Color8(84, 88, 60)
const GUN := Color8(44, 44, 42)
const GEAR := Color8(66, 62, 46)


static func build(out: Dictionary) -> void:
	var man := {}
	for def in ["engineer", "rifleman", "at_gunner", "recon", "officer"]:
		var img := Image.create(FW * FRAMES.size(), FH * 8, false, Image.FORMAT_RGBA8)
		var msk := Image.create(FW * FRAMES.size(), FH * 8, false, Image.FORMAT_RGBA8)
		for k in 8:
			for f in FRAMES.size():
				var cv = P.Canvas.new(FW, FH)
				soldier(cv, def, screen_dir(k), f)
				img.blit_rect(cv.img, Rect2i(0, 0, FW, FH), Vector2i(f * FW, k * FH))
				msk.blit_rect(cv.mask, Rect2i(0, 0, FW, FH), Vector2i(f * FW, k * FH))
		out.images["units/%s.png" % def] = img
		out.images["units/%s_mask.png" % def] = msk
		man[def] = {"file": "units/%s.png" % def, "mask": "units/%s_mask.png" % def, "fw": FW, "fh": FH,
			"pivot": [PIV.x, PIV.y], "frames": FRAMES, "facings": 8}
	out.manifest["infantry"] = man


## Screen-space unit direction of world facing k * 45 degrees under the iso projection.
static func screen_dir(k: int) -> Vector2:
	var a := k * PI / 4.0
	var w := Vector2(cos(a), sin(a))
	return Vector2((w.x - w.y) * 32.0, (w.x + w.y) * 16.0).normalized()


static func soldier(cv, def: String, d: Vector2, f: int) -> void:
	var cx := PIV.x
	var fy := PIV.y
	var away := d.y < -0.2          # back to the camera
	var side := absf(d.x) > 0.75     # profile
	var stride := 0.0
	if f == 1:
		stride = 2.0
	elif f == 2:
		stride = -2.0
	var bob := 0 if f == 0 or f == 3 else -1 if f == 1 else 0
	cv.ellipse(cx + 2, fy + 0.5, 5.5, 2.2, Color.BLACK, true)
	cv.flush_shadow()
	# legs: separated across the facing, stride along it
	var perp := Vector2(-d.y, d.x)
	var sep := 1.0 + absf(perp.x) * 0.6
	for leg in [-1, 1]:
		var hip := Vector2(cx + leg * sep * 0.8, fy - 6 + bob)
		var foot := Vector2(cx + leg * sep + d.x * stride * leg, fy - 1 + d.y * stride * 0.5 * leg)
		cv.line_v(hip, foot, TROUSER)
		cv.line_v(hip + Vector2(1, 0), foot + Vector2(1, 0), P.mul(TROUSER, 0.85))
		cv.rect(int(foot.x), int(foot.y), 2, 1, BOOT)
	var tw := 4 if side else 5
	var tx := cx - tw / 2
	var ty := fy - 11 + bob
	var heavy := def == "at_gunner"
	if not away:
		_weapon(cv, def, d, f, cx, ty, true)
	# backpack (visible from behind / side)
	if def != "recon" and (away or side):
		var bpx := int(cx - d.x * 3) - 2
		cv.rect(bpx, ty + 1, 4, 4 if not heavy else 5, GEAR)
		if def == "engineer":
			cv.line(bpx + 1, ty - 2, bpx + 1, ty + 1, Color8(110, 104, 94))  # shovel handle
		elif def == "officer":
			cv.rect(bpx, ty + 1, 4, 1, Color8(92, 90, 70))     # radio pack lid
			cv.px(bpx + 2, ty + 3, Color8(150, 160, 120))      # dial
	# torso with left-lit shading
	for yy in range(ty, ty + 6):
		for xx in range(tx, tx + tw):
			var k := 1.12 if xx == tx else 0.82 if xx == tx + tw - 1 else 1.0
			cv.px(xx, yy, P.mul(UNIFORM if def != "recon" else Color8(104, 100, 72), k))
	cv.rect(tx, ty + 3, tw, 1, GEAR)  # webbing belt
	if def == "officer":  # leather map case at the hip
		var mcx := tx + tw if d.x >= 0 else tx - 2
		cv.rect(mcx, ty + 3, 2, 3, Color8(128, 102, 66))
		cv.px(mcx, ty + 3, Color8(156, 128, 86))
	if not side:  # arms
		cv.rect(tx - 1, ty + 1, 1, 3, P.mul(UNIFORM, 1.08))
		cv.rect(tx + tw, ty + 1, 1, 3, P.mul(UNIFORM, 0.78))
	# team armband / shoulder patch
	cv.team = true
	var arm_x := tx if d.x >= 0 else tx + tw - 1
	cv.rect(arm_x, ty + 1, 1, 2, Color(0.75, 0.75, 0.75))
	if def == "engineer":
		cv.rect(tx + 1, ty + 1, tw - 2, 1, Color(0.8, 0.8, 0.8))   # hi-vis team vest band
	cv.team = false
	# head + headgear
	var hx := cx - 1
	var hy := ty - 4
	cv.rect(hx, hy, 3, 3, SKIN if not away else P.mul(SKIN, 0.75))
	if not away:
		cv.px(hx + (2 if d.x > 0 else 0), hy + 1, P.mul(SKIN, 0.6))
	match def:
		"engineer":
			cv.rect(hx - 1, hy - 1, 5, 2, Color8(178, 150, 68))  # hard hat
			cv.px(hx - 1, hy - 1, Color8(206, 180, 96))
			cv.rect(hx - 2 if d.x < 0 else hx + 3, hy + 1, 1, 1, Color8(178, 150, 68))
		"officer":
			cv.rect(hx - 1, hy - 2, 5, 1, Color8(92, 96, 66))   # peaked cap crown
			cv.px(hx - 1, hy - 2, Color8(116, 120, 84))
			cv.team = true
			cv.rect(hx - 1, hy - 1, 5, 1, Color(0.7, 0.7, 0.7))  # team cap band
			cv.team = false
			if not away:
				var vx := hx + (2 if d.x > 0.3 else (-1 if d.x < -0.3 else 0))
				cv.rect(vx, hy, 2 if absf(d.x) > 0.3 else 3, 1, Color8(36, 34, 28))  # visor
		"recon":
			cv.rect(hx - 1, hy - 1, 5, 1, Color8(88, 92, 62))   # boonie hat brim
			cv.team = true
			cv.rect(hx, hy - 2, 3, 1, Color(0.62, 0.62, 0.62))  # team hat band
			cv.team = false
		_:
			cv.team = true
			cv.rect(hx - 1, hy - 2, 5, 2, Color(0.6, 0.6, 0.6))   # team-painted helmet cover
			cv.px(hx - 1, hy - 2, Color(0.85, 0.85, 0.85))
			cv.team = false
			cv.rect(hx - 1, hy, 5, 1, P.mul(HELMET, 0.8))       # helmet rim
	if away:
		_weapon(cv, def, d, f, cx, ty, false)
	cv.outline(Color(0.09, 0.09, 0.07, 1))
	if def == "officer":  # radio whip antenna: after the outline so it stays 1 px, only behind the figure
		var abx := int(cx - d.x * 2.5) + (-2 if d.x >= 0 else 2)
		var tipx := abx + (1 if d.x < 0 else -1)
		for i in 11:
			var x := abx + (tipx - abx) * i / 10
			var y := ty + 1 - i
			if cv.get_px(x, y).a < 0.5:
				cv.px(x, y, Color8(44, 44, 40) if i < 10 else Color8(156, 156, 140))


static func _weapon(cv, def: String, d: Vector2, f: int, cx: int, ty: int, front: bool) -> void:
	var fire := f == 3
	var sh := Vector2(cx + d.x * 1.5, ty + 2 - (1 if fire else 0))
	match def:
		"at_gunner":
			# launcher tube on the shoulder, longer and thicker
			var a := Vector2(cx - d.x * 5, ty + d.y * -2.5)
			var b := Vector2(cx + d.x * 6, ty + d.y * 3.0)
			cv.line_v(a, b, Color8(86, 92, 62))
			cv.line_v(a + Vector2(0, 1), b + Vector2(0, 1), Color8(64, 68, 46))
			cv.px(int(b.x), int(b.y), Color8(40, 40, 36))
			if fire:
				var bb := a - d * 3.0
				cv.ellipse(bb.x, bb.y, 2.5, 2.0, Color(0.72, 0.70, 0.64, 0.85))
		"engineer":
			var tip := sh + Vector2(d.x * 4, d.y * 2.5 + 2)
			cv.line_v(sh + Vector2(0, 2), tip, Color8(120, 112, 98))  # wrench / pistol hand
			if fire:
				cv.line_v(sh, sh + Vector2(d.x * 5, d.y * 2.5), GUN)
		_:
			var ln := 7.0 if def == "rifleman" else 5.5
			var tip := sh + Vector2(d.x * ln, d.y * ln * 0.5 + (0 if fire else 1.5))
			cv.line_v(sh, tip, GUN)
			if def == "rifleman":
				cv.px(int(sh.x + d.x * 3), int(sh.y + d.y * 1.5 + 1), Color8(72, 58, 40))  # stock/mag
	if fire and def != "at_gunner":
		var t := sh + Vector2(d.x * 8, d.y * 4)
		cv.px(int(t.x), int(t.y), Color8(255, 226, 140))
