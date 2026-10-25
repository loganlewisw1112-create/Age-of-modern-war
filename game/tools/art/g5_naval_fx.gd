extends RefCounted
## G5 naval effects (agent ART-NAV): manifest.effects[name] = {file, fw, fh, frames, pivot} strips (frames
## left to right, pivot = water contact point), plus the far-zoom LOD hull glyph lod_icons["*"].naval.
##   g5_shell_splash        6 frames: tall water column rising and collapsing, base ring spreading
##   g5_shell_splash_small  4 frames: light gun / MG hit on water
##   g5_naval_muzzle        4 frames: heavy naval gun flash + smoke ring (pivot = muzzle)
##   g5_ramp_splash         4 frames: flat spray sheet where a landing ramp slaps down into shallows
##   g5_sink_bubbles        4 frames: bubbles + rings over a sunk hull
##   g5_bow_spray           3 frames: generic bow spray puff
##   g5_ship_smoke          4 frames: burning-ship smoke column (pivot = base)
const P = preload("res://tools/art/pix.gd")
const LOD = preload("res://tools/art/g3b_lod.gd")

const WHITE := Color(0.94, 0.97, 1.0)
const PALE := Color(0.72, 0.84, 0.9)


static func build(out: Dictionary) -> void:
	var fx: Dictionary = out.manifest.get("effects", {})
	fx["g5_shell_splash"] = _strip(out, "g5_shell_splash", 28, 46, 6, Vector2i(14, 40), _splash.bind(1.0))
	fx["g5_shell_splash_small"] = _strip(out, "g5_shell_splash_small", 16, 24, 4, Vector2i(8, 20), _splash.bind(0.45))
	fx["g5_naval_muzzle"] = _strip(out, "g5_naval_muzzle", 30, 20, 4, Vector2i(6, 10), _muzzle)
	fx["g5_ramp_splash"] = _strip(out, "g5_ramp_splash", 36, 18, 4, Vector2i(18, 12), _ramp)
	fx["g5_sink_bubbles"] = _strip(out, "g5_sink_bubbles", 24, 16, 4, Vector2i(12, 9), _bubbles)
	fx["g5_bow_spray"] = _strip(out, "g5_bow_spray", 16, 12, 3, Vector2i(8, 9), _spray)
	fx["g5_ship_smoke"] = _strip(out, "g5_ship_smoke", 20, 30, 4, Vector2i(10, 27), _smoke)
	out.manifest["effects"] = fx
	var li: Dictionary = out.manifest.get("lod_icons", {})
	var star: Dictionary = li.get("*", {})
	out.images["icons/lod_naval.png"] = glyph()
	star["naval"] = {"file": "icons/lod_naval.png", "pivot": [LOD.S / 2, LOD.S / 2]}
	li["*"] = star
	out.manifest["lod_icons"] = li


static func _strip(out: Dictionary, name: String, fw: int, fh: int, n: int, piv: Vector2i, draw: Callable) -> Dictionary:
	var img := Image.create(fw * n, fh, false, Image.FORMAT_RGBA8)
	for i in n:
		var cv = P.Canvas.new(fw, fh)
		draw.call(cv, i, n, Vector2(piv))
		img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(i * fw, 0))
	var rel := "fx/%s.png" % name
	out.images[rel] = img
	return {"file": rel, "fw": fw, "fh": fh, "frames": n, "pivot": [piv.x, piv.y]}


static func _a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))


## Water column: height peaks at frame ~2 then collapses; base ring keeps spreading.
static func _splash(cv, i: int, n: int, p: Vector2, s: float) -> void:
	var t := float(i) / float(n - 1)
	var h := s * 34.0 * sin(PI * minf(1.0, t * 1.35 + 0.12))
	var rr := s * (4.0 + t * 9.0)
	cv.ellipse(p.x, p.y, rr, rr * 0.45, _a(PALE, 0.5 * (1.0 - t * 0.6)))
	cv.ellipse(p.x, p.y, rr * 0.7, rr * 0.3, _a(WHITE, 0.0))
	var w := s * (3.0 + t * 3.0)
	for k in int(h):
		var y := p.y - k
		var wk := w * (1.0 - float(k) / maxf(1.0, h) * 0.55) + (P.hn(k, i, 77) - 0.5) * 1.6
		for x in range(int(p.x - wk), int(p.x + wk) + 1):
			if P.hn(x, k + i * 31, 78) > 0.06 + t * 0.35:
				cv.px(x, int(y), _a(WHITE if P.hn(x, k, 79) > 0.3 else PALE, 0.95 - t * 0.45))
	for d in 6 + i * 2:  # falling droplets
		var dx := (P.hn(d, i, 80) - 0.5) * (w * 4.0 + 6.0 * t)
		var dy := -h * (0.4 + P.hn(d, i, 81) * 0.6) + t * 10.0 * s
		cv.px(int(p.x + dx), int(p.y + dy), _a(WHITE, 0.9 - t * 0.4))


static func _muzzle(cv, i: int, _n: int, p: Vector2) -> void:
	if i < 2:
		var r := 4.0 + i * 3.0
		cv.ellipse(p.x + r, p.y, r * 1.4, r * 0.7, Color8(255, 210, 110))
		cv.ellipse(p.x + r * 0.7, p.y, r * 0.8, r * 0.4, Color8(255, 250, 220))
	for k in 3 + i:
		var q := p + Vector2(4.0 + k * 3.5 + i * 2.0, -k * 0.8 - i)
		var r2 := 2.0 + k * 0.6 + i * 0.7
		cv.ellipse(q.x, q.y, r2, r2 * 0.8, Color(0.76, 0.74, 0.7, maxf(0.1, 0.6 - i * 0.12 - k * 0.04)))


static func _ramp(cv, i: int, _n: int, p: Vector2) -> void:
	var t := i / 3.0
	var w := 8.0 + t * 9.0
	cv.ellipse(p.x, p.y, w, w * 0.32, _a(PALE, 0.5 - t * 0.25))
	for d in 22:
		var a := PI + PI * P.hn(d, 0, 90)
		var r := w * (0.4 + P.hn(d, i, 91) * 0.7)
		var lift := (1.0 - t) * 7.0 * P.hn(d, 1, 92) + t * 1.0
		cv.px(int(p.x + cos(a) * r), int(p.y + sin(a) * r * 0.35 - lift), _a(WHITE, 0.95 - t * 0.5))


static func _bubbles(cv, i: int, _n: int, p: Vector2) -> void:
	for b in 5:
		var ph := fposmod(i / 4.0 + b * 0.2, 1.0)
		var q := p + Vector2((P.hn(b, 0, 93) - 0.5) * 16.0, (P.hn(b, 1, 94) - 0.5) * 6.0)
		var r := 1.0 + ph * 3.0
		for k in 12:
			var a := k * TAU / 12.0
			cv.px(int(q.x + cos(a) * r), int(q.y + sin(a) * r * 0.5), _a(WHITE, 0.75 * (1.0 - ph)))
		if ph < 0.4:
			cv.px(int(q.x), int(q.y) - 1, _a(WHITE, 0.9))


static func _spray(cv, i: int, _n: int, p: Vector2) -> void:
	for d in 12:
		var a := -PI * P.hn(d, 2, 95)
		var r := 2.0 + i * 1.5 + P.hn(d, i, 96) * 3.0
		cv.ellipse(p.x + cos(a) * r, p.y + sin(a) * r * 0.8, 1.0, 0.8, _a(WHITE, 0.85 - i * 0.2))


static func _smoke(cv, i: int, _n: int, p: Vector2) -> void:
	for k in 6:
		var ph := fposmod(k / 6.0 + i / 4.0 / 6.0 * 1.5, 1.0)
		var q := p + Vector2(sin(k * 1.7 + i) * 2.0 + ph * 4.0, -ph * 24.0)
		var r := 2.5 + ph * 4.0
		cv.ellipse(q.x, q.y, r, r * 0.85, Color(0.26, 0.25, 0.24, 0.62 * (1.0 - ph * 0.7)))
	cv.ellipse(p.x, p.y - 1, 2.5, 1.6, Color8(255, 170, 60))
	cv.px(int(p.x), int(p.y) - 2, Color8(255, 240, 180))


## 16x16 far-zoom hull glyph (side view): lit hull, superstructure, mast, dark edge.
static func glyph() -> Image:
	var im := Image.create(LOD.S, LOD.S, false, Image.FORMAT_RGBA8)
	for x in range(1, 15):
		var inset := 0 if x > 2 else 3 - x
		LOD._r(im, x, 9, 1, 3 - (1 if x == 1 or x == 14 else 0), LOD.MID)
		LOD._r(im, x, 9 - (1 if x >= 12 else 0), 1, 1, LOD.HI)
		if inset > 0:
			LOD._r(im, x, 11, 1, 1, Color(0, 0, 0, 0))
	LOD._body(im, 5, 6, 6, 3)
	LOD._r(im, 7, 3, 1, 3, LOD.LO)
	LOD._r(im, 6, 4, 3, 1, LOD.LO)
	var src: Image = im.duplicate()
	for y in LOD.S:
		for x in LOD.S:
			if src.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < LOD.S and q.y < LOD.S and src.get_pixel(q.x, q.y).a > 0.5:
					im.set_pixel(x, y, LOD.EDGE)
					break
	return im
