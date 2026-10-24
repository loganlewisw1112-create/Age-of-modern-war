extends RefCounted
## G3b art helpers (agent ART4): one generic sheet builder for vehicle / legged / air units (same
## sheet layout and manifest structures as vehicles.gd, faction_m_units.gd and faction_m_veh.gd),
## icons in fx_ui's 32x32 format, and small shared shapes (dishes, EW pulses, drum stacks).
## Deterministic: integer hashes only, no RNG.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const FX = preload("res://tools/art/fx_ui.gd")
const L = preload("res://tools/art/faction_m_lib.gd")

const VFRAMES := ["idle", "move", "fire"]
const LFRAMES := ["idle", "walk_a", "walk_b", "fire"]
const PULSE := Color8(170, 236, 255)


## Render one unit sheet (+ mask, + optional wreck sheet) and register it in the manifest.
## draw: Callable(cv, rot: float, frame: int, wreck: bool, o: Vector2). Legged units go to the
## "infantry" section with walk frames; everything else to "vehicles" with idle/move/fire.
static func sheet(out: Dictionary, def: String, sp: Dictionary, draw: Callable, legged := false, wreck := true) -> void:
	var frames: Array = LFRAMES if legged else VFRAMES
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
	var sec := "infantry" if legged else "vehicles"
	var man: Dictionary = out.manifest.get(sec, {})
	var entry := {"file": "units/%s.png" % def, "mask": "units/%s_mask.png" % def, "fw": fw, "fh": fh,
		"pivot": sp.pivot, "frames": frames.duplicate(), "facings": 8}
	if legged:
		entry["legged"] = true
	man[def] = entry
	out.manifest[sec] = man
	if wreck:
		var wr: Dictionary = out.manifest.get("vehicle_wrecks", {})
		out.images["wrecks/%s_wreck.png" % def] = wimg
		wr[def] = {"file": "wrecks/%s_wreck.png" % def, "fw": fw, "fh": fh, "pivot": sp.pivot,
			"frames": ["wreck"], "facings": 8}
		out.manifest["vehicle_wrecks"] = wr


## Air fields (board fact art.air_fields): separate translucent ground shadow, altitude, bob.
static func air(out: Dictionary, def: String, altitude: int, bob: int, shadow: Image, spiv: Array) -> void:
	out.images["units/%s_shadow.png" % def] = shadow
	out.manifest.vehicles[def].merge({"air": true, "altitude": altitude, "bob": bob,
		"shadow": {"file": "units/%s_shadow.png" % def, "pivot": spiv}}, true)


## Soft elliptical shadow blobs ([cx, cy, rx, ry] each) composited once: no alpha stacking.
static func shadow_blobs(w: int, h: int, blobs: Array) -> Image:
	var cv = P.Canvas.new(w, h)
	for b in blobs:
		cv.ellipse(b[0], b[1], b[2], b[3], Color.BLACK, true)
	cv.flush_shadow(Color(0.04, 0.05, 0.03, 0.40))
	return cv.img


## 32x32 icon: team-tinted idle frame of `row` fitted on the dark panel (fx_ui look).
## accent "m" adds Machine's cyan status strip (faction_m.gd), "b" a rust strip.
static func icon_unit(out: Dictionary, id: String, def: String, row: int, accent := "") -> String:
	var sp: Dictionary = out.manifest.get("infantry", {}).get(def, out.manifest.get("vehicles", {}).get(def, {}))
	var tinted: Image = FX.tint(out.images[sp.file], out.images[sp.mask], FX.ICON_TEAM)
	var fw: int = sp.fw
	var fh: int = sp.fh
	var im := panel(accent)
	FX._fit(im, tinted.get_region(Rect2i(0, row * fh, fw, fh)), 28 if fw > 32 else 24)
	var path := "icons/%s.png" % id
	out.images[path] = im
	return path


static func icon_building(out: Dictionary, id: String, accent := "") -> String:
	var src: Image = out.images["buildings/%s_built.png" % id]
	var msk: Image = out.images["buildings/%s_built_mask.png" % id]
	var im := panel(accent)
	FX._fit(im, FX.tint(src, msk, FX.ICON_TEAM), 29)
	var path := "icons/%s.png" % id
	out.images[path] = im
	return path


static func panel(accent: String) -> Image:
	var im: Image = FX._panel()
	if accent == "m":
		for x in range(2, 8):
			im.set_pixel(x, 2, L.CYAN if x < 7 else L.TEAL)
	elif accent == "b":
		for x in range(2, 8):
			im.set_pixel(x, 2, Color8(176, 96, 48) if x < 7 else Color8(110, 62, 36))
	return im


# ---------------------------------------------------------------- shapes
## Parabolic dish at world point c (tiles, z px) whose face points along world angle `yaw`.
## Concave face lit when it faces the camera, plain back + strut otherwise. Returns the feed tip.
static func dish(cv, o: Vector2, c: Vector3, yaw: float, r: float, col: Color, wreck := false) -> Vector2:
	var p := P.proj(o, c)
	var n := Vector2(cos(yaw), sin(yaw))
	var nx := (n.x - n.y) / sqrt(2.0)  # normal's screen-horizontal component
	var rx := r * maxf(0.32, sqrt(maxf(0.0, 1.0 - nx * nx)))
	var ry := r * 0.92
	var toward := n.x + n.y > 0.0
	var sd := Vector2(n.x - n.y, (n.x + n.y) * 0.5).normalized()
	cv.ellipse(p.x, p.y, rx, ry, P.mul(col, 0.62))
	if toward and not wreck:
		cv.ellipse(p.x + sd.x * 0.6, p.y + sd.y * 0.4, rx * 0.8, ry * 0.8, P.mul(col, 1.18))
		cv.ellipse(p.x + sd.x * 1.0, p.y + sd.y * 0.6, rx * 0.45, ry * 0.45, P.mul(col, 0.96))
	else:
		cv.ellipse(p.x - sd.x * 0.5, p.y, rx * 0.78, ry * 0.78, P.mul(col, 0.84))
		cv.px(int(p.x), int(p.y), P.mul(col, 0.5))
	var tip := p + sd * (r * 0.9) + Vector2(0, -1)
	if not wreck:
		cv.line_v(p, tip, Color8(40, 40, 38))
		cv.px(int(tip.x), int(tip.y), Color8(210, 206, 190))
	return tip


## Translucent EW pulse rings around a screen point (fire frame of EW units). Drawn after outline.
static func pulse(cv, p: Vector2, r: float, col: Color = PULSE) -> void:
	for k in 2:
		var rr := r * (0.6 + k * 0.55)
		for i in 28:
			var a := i * TAU / 28.0
			var q := p + Vector2(cos(a) * rr, sin(a) * rr * 0.5)
			cv.px(int(q.x), int(q.y), Color(col.r, col.g, col.b, 0.62 - k * 0.24))
	cv.px(int(p.x), int(p.y), Color(1, 1, 1, 0.9))


## Whip antenna with a coloured tip.
static func whip(cv, base: Vector2, length: int, tip: Color, wreck := false) -> void:
	var top := base + Vector2(0 if not wreck else 3, -length)
	cv.line_v(base, top, Color8(34, 34, 32))
	if not wreck:
		cv.px(int(top.x), int(top.y), tip)


## Lattice mast (two rails + cross bracing) between screen points a (bottom) and b (top).
static func lattice(cv, a: Vector2, b: Vector2, wpx: float, col: Color) -> void:
	var d := Vector2(wpx, 0)
	cv.line_v(a - d, b - d * 0.4, col)
	cv.line_v(a + d, b + d * 0.4, col)
	var n := maxi(2, int((a.y - b.y) / 4.0))
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var l0 := (a - d).lerp(b - d * 0.4, t0)
		var r1 := (a + d).lerp(b + d * 0.4, t1)
		cv.line_v(l0, r1, P.mul(col, 0.8))


## Muzzle flash ellipse at screen point.
static func flash(cv, p: Vector2, s := 1.0) -> void:
	cv.ellipse(p.x, p.y, 2.4 * s, 1.7 * s, Color8(255, 226, 140))
	cv.px(int(p.x), int(p.y), Color8(255, 255, 230))
