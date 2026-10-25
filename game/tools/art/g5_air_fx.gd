extends RefCounted
## G5 air effects (agent ART-AIR), manifest `effects` (G4 schema: file, fw, fh, frames, pivot):
##   g5_air_bomb        4 frames 9x16: a falling bomb, nose down, fins wobbling, speed streak
##   g5_bomb_blast      6 frames 48x36, pivot (24, 30): flash -> fireball -> dust and smoke column
##   g5_missile         8 frames 18x18: missile with motor flame, frame k = facing k (world k * 45 deg)
##   g5_missile_trail   4 frames 10x8: fading white trail puff left behind a missile / rocket
##   g5_air_smoke       4 frames 16x22, pivot (8, 20): dark smoke trailing a damaged aircraft
##   g5_rotor_wash      4 frames 64x30, pivot (32, 15): dust ring blown out under a hovering / landing
##                      rotorcraft or VTOL (drawn at the ground point)
##   g5_afterburner     2 frames 12x12: round jet-blast glow behind a jet on its take-off roll
##   g5_flak_burst      4 frames 20x18: black flak puff with a flash core (b_vtol_flak / AA)
##   g5_air_crash       4 frames 40x30, pivot (20, 24): impact fireball + debris when an aircraft goes down
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/g4_units_lib.gd")


static func build(out: Dictionary) -> void:
	var fx: Dictionary = out.manifest.get("effects", {})
	fx["g5_air_bomb"] = _strip(out, "g5_air_bomb", 9, 16, [4, 8], 4, func(cv, i: int) -> void:
		for j in 4:
			cv.px(4, 1 + j, Color(1, 1, 1, 0.12 + j * 0.05))
		var w := (i % 2) * 2 - 1
		cv.ellipse(4.5, 9.5, 1.8, 3.4, Color8(62, 66, 54))
		cv.px(4, 7, Color8(120, 124, 110))
		cv.rect(3 + w, 5, 1, 2, Color8(40, 42, 36))
		cv.rect(5 - w, 5, 1, 2, Color8(40, 42, 36))
		cv.px(4, 13, Color8(36, 36, 30))
		cv.outline(Color8(20, 20, 18)))
	fx["g5_bomb_blast"] = _strip(out, "g5_bomb_blast", 48, 36, [24, 30], 6, func(cv, i: int) -> void:
		var c := Vector2(24, 30)
		if i < 3:
			cv.ellipse(c.x, c.y - 2, 6.0 + i * 5.0, 3.5 + i * 2.6, Color(1.0, 0.8, 0.35, 0.85 - i * 0.2))
			cv.ellipse(c.x, c.y - 3 - i, 3.0 + i * 3.0, 2.4 + i * 2.0, Color(1.0, 0.97, 0.8, 0.9 - i * 0.25))
		for j in 6:
			var a := float(j) * TAU / 6.0 + 0.4
			var rr := 4.0 + i * 3.4
			L.puff(cv, c + Vector2(cos(a) * rr * 1.6, sin(a) * rr * 0.6 - 1.0), 2.0 + i * 0.6,
				0.2 + 0.08 * mini(i, 3), Color(0.55, 0.5, 0.42))
		if i >= 1:
			for j in i:
				L.puff(cv, c + Vector2(0.5 * j, -6.0 - j * 4.0), 3.0 + j * 0.9, 0.55 - j * 0.06,
					Color(0.3, 0.28, 0.26) if i > 2 else Color(0.55, 0.42, 0.32)))
	fx["g5_missile"] = _strip(out, "g5_missile", 18, 18, [9, 9], 8, func(cv, i: int) -> void:
		var d := L.sd(i)
		var c := Vector2(9, 9)
		L.flame(cv, c - d * 3.5, -d, 3.5, i)
		cv.line_v(c - d * 3.0, c + d * 3.5, Color8(234, 234, 226))
		cv.line_v(c - d * 3.0 + Vector2(0, 1), c + d * 2.5 + Vector2(0, 1), Color8(170, 170, 164))
		cv.px(int(c.x + d.x * 4.0), int(c.y + d.y * 4.0), Color8(60, 60, 60)))
	fx["g5_missile_trail"] = _strip(out, "g5_missile_trail", 10, 8, [5, 4], 4, func(cv, i: int) -> void:
		var r := 1.5 + i * 0.8
		cv.ellipse(5.0, 4.0, r, r * 0.75, Color(0.95, 0.95, 0.92, 0.6 - i * 0.13)))
	fx["g5_air_smoke"] = _strip(out, "g5_air_smoke", 16, 22, [8, 20], 4, func(cv, i: int) -> void:
		for j in 4:
			var t := float(j) + float(i) * 0.25
			L.puff(cv, Vector2(8.0 + sin(t * 1.7) * 1.5, 18.0 - t * 4.0), 2.0 + t * 0.7, 0.62 - t * 0.12,
				Color(0.2, 0.19, 0.18))
		if i % 2 == 0:
			cv.px(8, 19, Color8(255, 150, 60)))
	fx["g5_rotor_wash"] = _strip(out, "g5_rotor_wash", 64, 30, [32, 15], 4, func(cv, i: int) -> void:
		var rr := 10.0 + i * 5.0
		for j in 22:
			var a := float(j) * TAU / 22.0 + i * 0.13
			var p := Vector2(32 + cos(a) * rr * 1.9, 15 + sin(a) * rr * 0.75)
			L.puff(cv, p, 1.6 + (j % 3) * 0.4, 0.42 - i * 0.08, Color(0.66, 0.6, 0.48))
		for j in 10:
			var a := float(j) * TAU / 10.0 + 0.3
			cv.line_v(Vector2(32 + cos(a) * rr, 15 + sin(a) * rr * 0.4),
				Vector2(32 + cos(a) * (rr + 6.0), 15 + sin(a) * (rr + 6.0) * 0.4), Color(0.8, 0.75, 0.62, 0.3)))
	fx["g5_afterburner"] = _strip(out, "g5_afterburner", 12, 12, [6, 6], 2, func(cv, i: int) -> void:
		cv.ellipse(6, 6, 5.0 - i, 4.0 - i * 0.6, Color(1.0, 0.55, 0.2, 0.45))
		cv.ellipse(6, 6, 3.0, 2.4, Color(1.0, 0.85, 0.5, 0.8))
		cv.ellipse(6, 6, 1.4, 1.2, Color(1, 1, 0.92, 0.95)))
	fx["g5_flak_burst"] = _strip(out, "g5_flak_burst", 20, 18, [10, 9], 4, func(cv, i: int) -> void:
		if i == 0:
			L.flash(cv, Vector2(10, 9), 1.4)
		for j in 5:
			var a := float(j) * TAU / 5.0 + 0.5
			var rr := 1.0 + i * 1.6
			L.puff(cv, Vector2(10 + cos(a) * rr, 9 + sin(a) * rr * 0.8), 2.4 + i * 0.5, 0.75 - i * 0.15,
				Color(0.12, 0.12, 0.12)))
	fx["g5_air_crash"] = _strip(out, "g5_air_crash", 40, 30, [20, 24], 4, func(cv, i: int) -> void:
		var c := Vector2(20, 24)
		cv.ellipse(c.x, c.y, 8.0 + i * 2.0, 3.0 + i, Color(0.16, 0.13, 0.1, 0.6))
		if i < 3:
			cv.ellipse(c.x, c.y - 4 - i * 2, 5.0 + i * 2.5, 4.0 + i * 1.8, Color(1.0, 0.62, 0.22, 0.85 - i * 0.2))
			cv.ellipse(c.x, c.y - 5 - i * 2, 2.6 + i, 2.0 + i, Color(1.0, 0.95, 0.7, 0.9 - i * 0.25))
		for j in 5:
			var a := float(j) * 1.3 + 0.2
			var rr := 3.0 + i * 3.5
			cv.rect(int(c.x + cos(a) * rr * 1.5), int(c.y - 2 + sin(a) * rr * 0.6 - (3 - i) * 0.8), 2, 1, Color8(40, 38, 34))
		if i > 0:
			L.puff(cv, c + Vector2(1, -10 - i * 2), 4.0 + i, 0.5, Color(0.22, 0.21, 0.2)))
	out.manifest["effects"] = fx


## Horizontal strip of `n` frames; draw: Callable(cv, i).
static func _strip(out: Dictionary, name: String, fw: int, fh: int, piv: Array, n: int, draw: Callable) -> Dictionary:
	var img := Image.create(fw * n, fh, false, Image.FORMAT_RGBA8)
	for i in n:
		var cv = P.Canvas.new(fw, fh)
		draw.call(cv, i)
		img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(i * fw, 0))
	var e := {"file": "fx/%s.png" % name, "fw": fw, "fh": fh, "frames": n, "pivot": piv.duplicate()}
	out.images[e.file] = img
	return e
