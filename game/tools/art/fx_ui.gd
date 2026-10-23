extends RefCounted
## Effects (muzzle, explosions, smoke), fog tiles and 32x32 HUD icons.
## build() must run last: icons are made from the sprites already in out.images.
const P = preload("res://tools/art/pix.gd")

const ICON_TEAM := Color(0.36, 0.52, 0.74)
const UNIT_ICONS := ["engineer", "rifleman", "at_gunner", "recon", "ifv", "mbt", "officer", "logistics_truck"]
const VEHICLES := ["ifv", "mbt", "logistics_truck"]
const SQUADS := {"rifle_squad": ["rifleman", 4], "at_team": ["at_gunner", 2]}
const BUILDINGS := ["hq", "generator", "depot", "barracks", "motor_pool", "guard_tower", "refinery"]


static func build(out: Dictionary) -> void:
	var fx := {}
	fx["muzzle"] = _effect(out, "muzzle", 3, 16, 0)
	fx["explosion_small"] = _effect(out, "explosion_small", 6, 32, 1)
	fx["explosion_large"] = _effect(out, "explosion_large", 6, 64, 2)
	fx["smoke"] = _effect(out, "smoke", 5, 32, 3)
	out.manifest["effects"] = fx
	for kind in ["unexplored", "explored"]:
		var cv = P.Canvas.new(64, 32)
		for y in 32:
			for x in 64:
				if P.in_diamond(x, y):
					var n := P.hn(x, y, 5) * 0.012
					if kind == "unexplored":
						cv.img.set_pixel(x, y, Color(0.028 + n, 0.032 + n, 0.04 + n, 1.0))
					else:
						cv.img.set_pixel(x, y, Color(0.10, 0.12, 0.16, 0.55))
		out.images["fog/%s.png" % kind] = cv.img
	out.manifest["fog"] = {"unexplored": "fog/unexplored.png", "explored": "fog/explored.png"}
	var icons := {}
	for id in UNIT_ICONS:
		icons[id] = _icon_unit(out, id, id, 0)
	for id in SQUADS:
		icons[id] = _icon_unit(out, id, SQUADS[id][0], SQUADS[id][1])
	for id in BUILDINGS:
		icons[id] = _icon_sprite(out, id, "buildings/%s_built.png" % id, "buildings/%s_built_mask.png" % id)
	for id in ["salvage", "ore"]:
		icons[id] = _icon_sprite(out, id, "resources/%s.png" % id, "")
	out.manifest["icons"] = icons


static func _effect(out: Dictionary, nm: String, n: int, sz: int, kind: int) -> Dictionary:
	var sheet := Image.create(sz * n, sz, false, Image.FORMAT_RGBA8)
	var c := sz / 2.0
	for f in n:
		var t := float(f) / float(n - 1)
		var cv = P.Canvas.new(sz, sz)
		for y in sz:
			for x in sz:
				var dx := x + 0.5 - c
				var dy := (y + 0.5 - c) / 0.9
				var d := sqrt(dx * dx + dy * dy) / c
				var ang := atan2(dy, dx)
				var nz := P.vnoise(x * 1.0 + f * 9, y * 1.0, 3.0, 50 + kind) - 0.5
				var col := Color(0, 0, 0, 0)
				match kind:
					0:  # muzzle: 4-point star, shrinking
						var star := (0.35 + 0.65 * pow(absf(cos(ang * 2.0)), 6.0)) * (1.0 - t * 0.55)
						if d < star:
							col = P.mix(Color8(255, 250, 220), Color8(255, 170, 60), d / star)
							col.a = 1.0 - t * 0.3
					1, 2:  # explosion: white core -> orange fireball -> dark smoke ring
						var r := (0.35 + 0.6 * sqrt(t)) * (1.0 + nz * 0.5)
						if d < r:
							var k := d / r
							if t < 0.45:
								col = P.mix(Color8(255, 246, 200), Color8(240, 130, 40), k + t)
								if k > 0.75:
									col = P.mix(col, Color8(120, 44, 24), (k - 0.75) * 3.0)
							else:
								var heat := clampf(1.0 - (t - 0.45) * 2.2 - k, 0.0, 1.0)
								col = P.mix(Color8(70, 64, 58), Color8(230, 110, 40), heat)
							col.a = 1.0 if t < 0.7 else 1.0 - (t - 0.7) * 2.5
					3:  # smoke puff
						var r := (0.3 + 0.6 * t) * (1.0 + nz * 0.6)
						if d < r:
							var g := 0.42 + (1.0 - d / r) * 0.12 + nz * 0.1
							col = Color(g, g * 0.98, g * 0.94, (1.0 - t) * 0.8)
				if col.a > 0.02:
					cv.img.set_pixel(x, y, col)
		if kind == 1 or kind == 2:  # debris specks
			for i in 6 + kind * 4:
				var a := P.hn(i, kind, 77) * TAU
				var rr := (0.3 + t * 0.8) * c * (0.6 + P.hn(i, kind, 78) * 0.4)
				var px := Vector2(c + cos(a) * rr, c + sin(a) * rr * 0.9 - t * 2)
				if t < 0.9:
					cv.rect(int(px.x), int(px.y), 1 + kind / 2, 1, Color8(40, 34, 30))
		sheet.blit_rect(cv.img, Rect2i(0, 0, sz, sz), Vector2i(f * sz, 0))
	out.images["fx/%s.png" % nm] = sheet
	return {"file": "fx/%s.png" % nm, "fw": sz, "fh": sz, "frames": n}


static func tint(img: Image, mask: Image, col: Color) -> Image:
	var r: Image = img.duplicate()
	if mask == null:
		return r
	for y in r.get_height():
		for x in r.get_width():
			var m := mask.get_pixel(x, y).a
			if m > 0.0:
				var b := r.get_pixel(x, y)
				var k := 0.45 + b.r * 0.9
				r.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, b.a).clamp())
	return r


static func _panel() -> Image:
	var im := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var g := 0.16 + 0.06 * (1.0 - float(y) / 32.0)
			var c := Color(g * 0.92, g, g * 0.9, 1.0)
			if x == 0 or y == 0:
				c = Color(0.36, 0.38, 0.34, 1)
			elif x == 31 or y == 31:
				c = Color(0.06, 0.06, 0.05, 1)
			im.set_pixel(x, y, c)
	return im


static func _icon_unit(out: Dictionary, id: String, def: String, count: int) -> String:
	var src: Image = out.images["units/%s.png" % def]
	var msk: Image = out.images["units/%s_mask.png" % def]
	var tinted := tint(src, msk, ICON_TEAM)
	var im := _panel()
	var fw := src.get_width() / (4 if def not in VEHICLES else 3)
	var fh := src.get_height() / 8
	var frame := tinted.get_region(Rect2i(0, 0, fw, fh))
	if def in VEHICLES:
		_fit(im, frame, 28)
	else:
		var crop := frame.get_region(Rect2i(4, 3, 16, 16))
		crop.resize(32, 32, Image.INTERPOLATE_NEAREST)
		im.blend_rect(crop, Rect2i(0, 0, 32, 32), Vector2i(0, 2))
	for i in count:  # squad size pips
		for yy in 3:
			im.set_pixel(27 - i * 3, 27 + yy, Color(0.85, 0.82, 0.6))
			im.set_pixel(28 - i * 3, 27 + yy, Color(0.85, 0.82, 0.6))
	var path := "icons/%s.png" % id
	out.images[path] = im
	return path


static func _icon_sprite(out: Dictionary, id: String, file: String, mask: String) -> String:
	var src: Image = out.images[file]
	var tinted := tint(src, out.images.get(mask), ICON_TEAM) if mask != "" else src
	var im := _panel()
	_fit(im, tinted, 29)
	var path := "icons/%s.png" % id
	out.images[path] = im
	return path


static func _fit(dst: Image, src: Image, box: int) -> void:
	var r := src.get_used_rect()
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var crop := src.get_region(r)
	var k := minf(float(box) / r.size.x, float(box) / r.size.y)
	var nw := maxi(1, int(round(r.size.x * k)))
	var nh := maxi(1, int(round(r.size.y * k)))
	crop.resize(nw, nh, Image.INTERPOLATE_LANCZOS if k < 1.0 else Image.INTERPOLATE_NEAREST)
	dst.blend_rect(crop, Rect2i(0, 0, nw, nh), Vector2i((32 - nw) / 2, (32 - nh) / 2))
