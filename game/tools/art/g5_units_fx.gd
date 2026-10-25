extends RefCounted
## G5 unit effects (agent ART-U5), manifest `effects` (same schema as G4: file, fw, fh, frames, pivot,
## optional team mask):
##   g5_wounded_a / g5_wounded_b  4 frames, 24x26, pivot (12, 21), team mask: the wounded pose for ANY
##                                 Human A / B infantry (G1-G4 units have no own column; G5 squads do)
##   g5_wounded_marker            2 frames, 11x12: pulsing red-cross pip floated over a wounded unit
##   g5_red_cross                 1 frame, 9x9: plain red-cross marker (evac area / med unit carrying)
##   g5_drone_trail               4 frames, 10x8: fading exhaust puff left behind a drone
##   g5_emp_pulse                 4 frames, 40x22: expanding EMP / jammer ring
const P = preload("res://tools/art/pix.gd")
const FIG = preload("res://tools/art/g5_units_fig.gd")
const IA = preload("res://tools/art/g5_units_inf_a.gd")
const IB = preload("res://tools/art/g5_units_inf_b.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")


static func build(out: Dictionary) -> void:
	var fx: Dictionary = out.manifest.get("effects", {})
	fx["g5_wounded_a"] = _strip(out, "g5_wounded_a", 24, 26, [12, 21], 4, func(cv, i: int) -> void:
		FIG.draw(cv, i * 2 + 1, "lie", IA.A), true)
	fx["g5_wounded_b"] = _strip(out, "g5_wounded_b", 24, 26, [12, 21], 4, func(cv, i: int) -> void:
		FIG.draw(cv, i * 2 + 1, "lie", IB.BS), true)
	fx["g5_wounded_marker"] = _strip(out, "g5_wounded_marker", 11, 12, [5, 11], 2, func(cv, i: int) -> void:
		cv.ellipse(5.5, 5.0, 5.0, 4.6, Color8(236, 234, 226) if i == 0 else Color8(255, 255, 250))
		var red := Color8(196, 38, 34) if i == 0 else Color8(232, 48, 40)
		cv.rect(4, 2, 3, 7, red)
		cv.rect(2, 4, 7, 3, red)
		cv.px(5, 10, Color8(236, 234, 226))
		cv.outline(Color8(60, 20, 18) if i == 0 else Color8(140, 30, 26)))
	fx["g5_red_cross"] = _strip(out, "g5_red_cross", 9, 9, [4, 8], 1, func(cv, _i: int) -> void:
		SL.red_cross(cv, 1, 1, 2)
		cv.outline(Color8(40, 30, 28)))
	fx["g5_drone_trail"] = _strip(out, "g5_drone_trail", 10, 8, [5, 4], 4, func(cv, i: int) -> void:
		var r := 1.6 + i * 0.9
		cv.ellipse(5.0, 4.0, r, r * 0.75, Color(0.82, 0.82, 0.78, 0.55 - i * 0.12)))
	fx["g5_emp_pulse"] = _strip(out, "g5_emp_pulse", 40, 22, [20, 11], 4, func(cv, i: int) -> void:
		var rr := 4.0 + i * 5.0
		for j in 48:
			var a := j * TAU / 48.0
			var p := Vector2(20 + cos(a) * rr, 11 + sin(a) * rr * 0.5)
			cv.px(int(p.x), int(p.y), Color(0.45, 0.7, 1.0, 0.95 - i * 0.2))
			if i < 2:
				cv.px(int(p.x), int(p.y) + 1, Color(0.8, 0.9, 1.0, 0.4)))
	out.manifest["effects"] = fx


## Horizontal strip of `n` frames; draw: Callable(cv, i). team = also write a mask strip.
static func _strip(out: Dictionary, name: String, fw: int, fh: int, piv: Array, n: int, draw: Callable, team := false) -> Dictionary:
	var img := Image.create(fw * n, fh, false, Image.FORMAT_RGBA8)
	var msk := Image.create(fw * n, fh, false, Image.FORMAT_RGBA8)
	for i in n:
		var cv = P.Canvas.new(fw, fh)
		draw.call(cv, i)
		img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(i * fw, 0))
		msk.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i(i * fw, 0))
	var e := {"file": "fx/%s.png" % name, "fw": fw, "fh": fh, "frames": n, "pivot": piv.duplicate()}
	out.images[e.file] = img
	if team:
		e["mask"] = "fx/%s_mask.png" % name
		out.images[e.mask] = msk
	return e
