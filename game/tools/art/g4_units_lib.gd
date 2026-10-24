extends RefCounted
## G4b unit art helpers (agent ART-U). Sheet builders with an explicit frame list, so a unit can carry
## extra state columns AFTER the standard ones (the renderer only looks frames up by name):
##   foot     idle, walk_a, walk_b, fire [+ extras such as "deployed" (mortar), "work" (engineer)]
##   vehicle  idle, move, fire [+ "unload" (carriers: ramp / rear doors open)]
##   legged vehicle (scrap mech) idle, walk_a, walk_b, fire, move (move = mid-stride, for frame-set checks)
## Same sheet layout as g3b_lib.sheet / units.gd: rows = 8 facings (world angle k * 45 deg), greyscale
## `_mask.png` twin for team colour, optional 1-column wreck sheet. Deterministic: integer hashes only.
const P = preload("res://tools/art/pix.gd")

const INF_FW := 24
const INF_FH := 26
const INF_PIV := [12, 21]


## draw: Callable(cv, rot: float, frame: int, wreck: bool, o: Vector2). section "infantry" | "vehicles".
static func sheet(out: Dictionary, def: String, sp: Dictionary, draw: Callable, frames: Array, section: String,
		wreck := true, extra := {}) -> void:
	var fw: int = sp.fw
	var fh: int = sp.fh
	var o := Vector2(sp.pivot[0], sp.pivot[1])
	var img := Image.create(fw * frames.size(), fh * 8, false, Image.FORMAT_RGBA8)
	var msk := Image.create(fw * frames.size(), fh * 8, false, Image.FORMAT_RGBA8)
	var wimg := Image.create(fw, fh * 8, false, Image.FORMAT_RGBA8)
	for k in 8:
		for f in frames.size():
			var cv = P.Canvas.new(fw, fh)
			draw.call(cv, k * PI / 4.0, f, false, o)
			img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
			msk.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
		if wreck:
			var wc = P.Canvas.new(fw, fh)
			draw.call(wc, k * PI / 4.0, 0, true, o)
			wimg.blit_rect(wc.img, Rect2i(0, 0, fw, fh), Vector2i(0, k * fh))
	out.images["units/%s.png" % def] = img
	out.images["units/%s_mask.png" % def] = msk
	var man: Dictionary = out.manifest.get(section, {})
	var entry := {"file": "units/%s.png" % def, "mask": "units/%s_mask.png" % def, "fw": fw, "fh": fh,
		"pivot": sp.pivot.duplicate(), "frames": frames.duplicate(), "facings": 8}
	entry.merge(extra, true)
	man[def] = entry
	out.manifest[section] = man
	if wreck:
		var wr: Dictionary = out.manifest.get("vehicle_wrecks", {})
		out.images["wrecks/%s_wreck.png" % def] = wimg
		wr[def] = {"file": "wrecks/%s_wreck.png" % def, "fw": fw, "fh": fh, "pivot": sp.pivot.duplicate(),
			"frames": ["wreck"], "facings": 8}
		out.manifest["vehicle_wrecks"] = wr


## Infantry sheet (24x26, pivot 12,21). draw: Callable(cv, k: int, frame: int).
static func inf_sheet(out: Dictionary, def: String, draw: Callable, frames: Array, extra := {}) -> void:
	var sp := {"fw": INF_FW, "fh": INF_FH, "pivot": INF_PIV}
	sheet(out, def, sp, func(cv, rot: float, f: int, _w: bool, _o: Vector2) -> void:
		draw.call(cv, int(round(rot / (PI / 4.0))), f), frames, "infantry", false, extra)


## World facing k * 45 deg as a screen vector for `tiles` of length (iso: 1 tile = (32, 16) half-diamond).
static func sv(k: int, tiles: float) -> Vector2:
	var a := k * PI / 4.0
	return Vector2((cos(a) - sin(a)) * 32.0, (cos(a) + sin(a)) * 16.0) * tiles


## Unit screen direction of facing k.
static func sd(k: int) -> Vector2:
	return sv(k, 1.0).normalized()


## Hash-mottled colour pick from a palette (camouflage, ghillie tufts, scrap plates).
static func mottle(pal: Array, x: int, y: int, s: int) -> Color:
	return pal[P.hi(x, y, s, pal.size())]


static func flash(cv, p: Vector2, s := 1.0) -> void:
	cv.ellipse(p.x, p.y, 2.2 * s, 1.6 * s, Color8(255, 226, 140))
	cv.px(int(p.x), int(p.y), Color8(255, 255, 230))


## Translucent smoke puff (drawn after outline so it stays soft).
static func puff(cv, p: Vector2, r: float, a := 0.5, col := Color(0.78, 0.76, 0.7)) -> void:
	for y in range(int(p.y - r), int(p.y + r) + 1):
		for x in range(int(p.x - r), int(p.x + r) + 1):
			var dx := (x + 0.5 - p.x) / r
			var dy := (y + 0.5 - p.y) / (r * 0.8)
			var d := dx * dx + dy * dy
			if d <= 1.0:
				cv.px(x, y, Color(col.r, col.g, col.b, a * (1.0 - d * 0.6)))


## Short flame tongue from screen point a toward dir (flamer burst / backblast). n = flicker seed.
static func flame(cv, a: Vector2, dir: Vector2, length: float, n: int) -> void:
	var dn := dir.normalized()
	var pr := Vector2(-dn.y, dn.x)
	var steps := int(length)
	for i in steps:
		var t := float(i) / maxf(1.0, length)
		var wob := (P.hn(i, n, 4417) - 0.5) * 2.0 * t
		var c := a + dn * i + pr * wob
		var r := 0.8 + t * 2.4
		var col := Color8(255, 246, 196) if t < 0.25 else (Color8(255, 196, 80) if t < 0.6 else Color8(226, 104, 40))
		cv.ellipse(c.x, c.y, r, r * 0.8, Color(col.r, col.g, col.b, 1.0 - t * 0.35))
