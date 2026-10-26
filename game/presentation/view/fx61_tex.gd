extends RefCounted
## G6.1 VFX61: procedural effect sprites, generated once at runtime (deterministic hash noise, no import step).
## glow (soft additive light), puff (smoke), spark, chunk (debris), flame (teardrop), crater + scorch (iso decals),
## vignette (screen edge darkening).

const NAMES := ["glow", "puff", "spark", "chunk", "flame", "crater", "scorch", "vignette"]
static var _cache: Dictionary = {}


static func tex(name: String) -> Texture2D:
	var t = _cache.get(name)
	if t != null:
		return t
	var img: Image = image(name)
	var it := ImageTexture.create_from_image(img)
	_cache[name] = it
	return it


static func _h(x: int, y: int, s: int) -> float:
	var n := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n & 0xffff) / 65535.0


## Smooth value noise in [0,1] at (x, y) with cell size c.
static func _noise(x: float, y: float, c: float, s: int) -> float:
	var gx := floori(x / c)
	var gy := floori(y / c)
	var fx := x / c - gx
	var fy := y / c - gy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := lerpf(_h(gx, gy, s), _h(gx + 1, gy, s), fx)
	var b := lerpf(_h(gx, gy + 1, s), _h(gx + 1, gy + 1, s), fx)
	return lerpf(a, b, fy)


static func image(name: String) -> Image:
	match name:
		"glow":
			return _radial(64, 64, func(d: float, _x: int, _y: int): return Color(1, 1, 1, pow(maxf(0.0, 1.0 - d), 2.2)))
		"puff":
			return _radial(64, 64, func(d: float, x: int, y: int):
				var n := 0.6 * _noise(x, y, 9.0, 3) + 0.4 * _noise(x, y, 4.0, 5)
				var a := clampf((1.0 - d * (0.75 + 0.5 * n)) * 1.6, 0.0, 1.0)
				var v := 0.8 + 0.2 * n
				return Color(v, v, v, pow(a, 1.3)))
		"spark":
			return _radial(8, 8, func(d: float, _x: int, _y: int): return Color(1, 1, 0.9, clampf(1.2 - d * 1.2, 0.0, 1.0)))
		"chunk":
			return _radial(8, 8, func(d: float, x: int, y: int):
				var a := 1.0 if d < 0.55 + 0.35 * _h(x, y, 7) else 0.0
				var v := 0.55 + 0.45 * _h(x, y, 9)
				return Color(v, v, v, a))
		"flame":
			var img := Image.create(32, 48, false, Image.FORMAT_RGBA8)
			for y in 48:
				for x in 32:
					var u := (x - 15.5) / 16.0
					var v := y / 47.0  # 0 top (tip) .. 1 base
					var wdt := 0.15 + 0.85 * sqrt(v) * (1.0 - 0.6 * maxf(0.0, v - 0.75) / 0.25)
					var d := absf(u) / maxf(0.05, wdt)
					var n := _noise(x, y, 5.0, 11)
					var a := clampf((1.0 - d) * 1.8 * (0.7 + 0.3 * n) * minf(1.0, v * 3.0), 0.0, 1.0)
					var heat := clampf(1.0 - d + v * 0.4, 0.0, 1.0)
					img.set_pixel(x, y, Color(1.0, 0.35 + 0.6 * heat, 0.1 + 0.5 * heat * heat, a))
			return img
		"crater":
			return _radial(64, 32, func(d: float, x: int, y: int):
				var n := _noise(x, y, 6.0, 13)
				var rim := clampf(1.0 - absf(d - 0.72) / 0.18, 0.0, 1.0)
				var hole := clampf((0.7 - d) / 0.7, 0.0, 1.0)
				var a := clampf(hole * 0.9 + rim * 0.6, 0.0, 1.0) * (0.75 + 0.25 * n)
				var v := 0.10 + 0.18 * rim + 0.06 * n
				return Color(v, v * 0.92, v * 0.8, a))
		"scorch":
			return _radial(64, 32, func(d: float, x: int, y: int):
				var n := 0.65 * _noise(x, y, 7.0, 17) + 0.35 * _noise(x, y, 3.0, 19)
				var a := clampf((1.0 - d * (0.8 + 0.5 * n)) * 1.4, 0.0, 1.0) * 0.85
				return Color(0.06, 0.055, 0.05, a))
		"vignette":
			return _radial(128, 128, func(d: float, _x: int, _y: int): return Color(0, 0, 0, clampf((d - 0.55) / 0.45, 0.0, 1.0) ** 1.6))
	return _radial(8, 8, func(d: float, _x: int, _y: int): return Color(1, 1, 1, 1.0 - d))


## w x h image; f(d, x, y) -> Color with d = elliptical distance from the centre (0 centre, 1 edge, >1 outside).
static func _radial(w: int, h: int, f: Callable) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	for y in h:
		for x in w:
			var d := Vector2((x - cx) / (w * 0.5), (y - cy) / (h * 0.5)).length()
			var c: Color = f.call(d, x, y) if d <= 1.0 else Color(0, 0, 0, 0)
			img.set_pixel(x, y, c)
	return img
