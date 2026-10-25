extends RefCounted
## G5 naval sheet builder + finishing passes (agent ART-NAV). One call per ship writes:
##   units/<def>.png + _mask.png   frames x 8 facings (idle, move, fire [, ramp_half, unload, swim, swim_move])
##   wrecks/<def>_wreck.png        1 column: burnt hulk settled in shallow water, deck awash (crawler: on land)
##   sink/<def>_sink.png           sink_0..sink_3 x 8 facings, untinted: fire, listing, awash, mast tips
##   wake/<def>_wake.png           3-frame looping wake x 8 facings, translucent, drawn UNDER the ship
## and registers vehicles[def] with "naval", "sink" and "wake" sub-specs (same pivot convention: the
## sub-sheet pivot is the ship's waterline centre).
## draw: Callable(cv, o: Vector2, rot: float, st: {f: frame name, sink: px, wreck: bool, stage: -1|0..3}).
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const N = preload("res://tools/art/g5_naval_lib.gd")
const ML = preload("res://tools/art/faction_m_lib.gd")

const SMOKE := Color(0.34, 0.33, 0.31)


static func ship_sheet(out: Dictionary, def: String, sh: Dictionary, draw: Callable, frames: Array) -> void:
	var sp := N.frame_spec(sh)
	var fw: int = sp.fw
	var fh: int = sp.fh
	var o := Vector2(sp.pivot[0], sp.pivot[1])
	var img := Image.create(fw * frames.size(), fh * 8, false, Image.FORMAT_RGBA8)
	var msk := Image.create(fw * frames.size(), fh * 8, false, Image.FORMAT_RGBA8)
	var wimg := Image.create(fw, fh * 8, false, Image.FORMAT_RGBA8)
	var simg := Image.create(fw * 4, fh * 8, false, Image.FORMAT_RGBA8)
	var wsink: float = float(sh.get("wreck_sink", float(sh.F) + 3.0))
	for k in 8:
		var rot := k * PI / 4.0
		for f in frames.size():
			var cv = P.Canvas.new(fw, fh)
			draw.call(cv, o, rot, {"f": frames[f], "sink": 0.0, "wreck": false, "stage": -1})
			img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
			msk.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
		var wc = P.Canvas.new(fw, fh)
		draw.call(wc, o, rot, {"f": "idle", "sink": wsink, "wreck": true, "stage": -1})
		wimg.blit_rect(wc.img, Rect2i(0, 0, fw, fh), Vector2i(0, k * fh))
		for i in 4:
			var sc = P.Canvas.new(fw, fh)
			draw.call(sc, o, rot, {"f": "idle", "sink": float(sh.depth) * N.SINK_K[i], "wreck": true, "stage": i})
			simg.blit_rect(sc.img, Rect2i(0, 0, fw, fh), Vector2i(i * fw, k * fh))
	out.images["units/%s.png" % def] = img
	out.images["units/%s_mask.png" % def] = msk
	out.images["wrecks/%s_wreck.png" % def] = wimg
	out.images["sink/%s_sink.png" % def] = simg
	var wake := wake_sheet(out, def, sh)
	var man: Dictionary = out.manifest.get("vehicles", {})
	man[def] = {"file": "units/%s.png" % def, "mask": "units/%s_mask.png" % def, "fw": fw, "fh": fh,
		"pivot": sp.pivot.duplicate(), "frames": frames.duplicate(), "facings": 8, "naval": true,
		"waterline_px": int(sh.F), "length_tiles": float(sh.L) * 2.0,
		"sink": {"file": "sink/%s_sink.png" % def, "fw": fw, "fh": fh, "pivot": sp.pivot.duplicate(),
			"frames": N.SINK_FRAMES.duplicate(), "facings": 8},
		"wake": wake}
	out.manifest["vehicles"] = man
	var wr: Dictionary = out.manifest.get("vehicle_wrecks", {})
	wr[def] = {"file": "wrecks/%s_wreck.png" % def, "fw": fw, "fh": fh, "pivot": sp.pivot.duplicate(),
		"frames": ["wreck"], "facings": 8}
	out.manifest["vehicle_wrecks"] = wr


## Looping Kelvin wake: bow wave, two diverging arms (~19.5 deg), chevron crests and stern churn.
static func wake_sheet(out: Dictionary, def: String, sh: Dictionary) -> Dictionary:
	var lh: float = sh.L
	var b: float = sh.B
	var tail := 2.0 * lh + 0.4
	var spread := 0.354
	var wmax := b + spread * (tail + 0.7 * lh)
	var rw := sqrt(tail * tail + wmax * wmax)
	var xh := int(ceil(45.3 * rw)) + 3
	var up := int(ceil(22.7 * rw)) + 3
	var fw := xh * 2
	var fh := up * 2
	var img := Image.create(fw * N.WAKE_FRAMES, fh * 8, false, Image.FORMAT_RGBA8)
	var o := Vector2(xh, up)
	for k in 8:
		var rot := k * PI / 4.0
		for ph in N.WAKE_FRAMES:
			var cv = P.Canvas.new(fw, fh)
			var bb := N.bbox(cv, o, rot, -tail, lh + 0.3, -wmax, wmax)
			for y in range(bb.position.y, bb.end.y):
				for x in range(bb.position.x, bb.end.x):
					var q := N.local(o, rot, x, y)
					var d := N.dist(q.x, q.y, sh)
					if d < 0.0:
						continue
					var a := _wake_a(q.x, absf(q.y), d, lh, b, tail, spread, ph, x, y)
					if a > 0.01:
						cv.px(x, y, N._fa(a))
			img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(ph * fw, k * fh))
	var rel := "wake/%s_wake.png" % def
	out.images[rel] = img
	return {"file": rel, "fw": fw, "fh": fh, "pivot": [xh, up], "frames": N.WAKE_FRAMES, "facings": 8, "under": true,
		"fps": 6}


static func _wake_a(f: float, r: float, d: float, lh: float, b: float, tail: float, spread: float, ph: int,
		x: int, y: int) -> float:
	var n := P.hn(x, y, 610 + ph)
	var a := 0.0
	if f > 0.3 * lh and d < 0.1:
		a = 0.5 * (0.7 + 0.3 * n)
	if f < 0.7 * lh and f > -tail:
		var arm_r := b * 0.75 + (0.7 * lh - f) * spread
		var fade := 1.0 - (0.7 * lh - f) / (0.7 * lh + tail)
		var da := absf(r - arm_r)
		if da < 0.04 + 0.04 * (1.0 - fade) and n > 0.25:
			a = maxf(a, 0.48 * fade)
		var cw := fposmod((f - r * 0.7) / 0.21 + ph / 3.0, 1.0)
		if r < arm_r - 0.03 and f < -lh * 0.4 and cw < 0.16 and n > 0.3:
			a = maxf(a, 0.24 * fade)
	if f < -lh * 0.88:
		var tw := b * 0.8 + (-lh - f) * 0.1
		var fd := 1.0 - (-lh - f) / maxf(0.01, tail - lh)
		if r < tw and fd > 0.0 and P.vnoise(x + ph * 3, y, 2.5, 300 + ph) > 0.36:
			a = maxf(a, 0.55 * fd)
	return a


## Team band (live frames) or a plain darker band (wreck / sinking, which ship without a mask).
static func band(cv, q: PackedVector2Array, u0: float, v0: float, u1: float, v1: float, st: Dictionary, col: Color) -> void:
	if N.live(st):
		cv.team = true
		cv.poly(P.sub(q, u0, v0, u1, v1), Color(0.64, 0.64, 0.64))
		cv.team = false
	else:
		cv.poly(P.sub(q, u0, v0, u1, v1), P.mul(col, 0.78))


## Hinged bow ramp: closed (0 deg) stands up at the bow, ramp_half 45 deg, unload ~86 deg onto the beach.
static func ramp(cv, o: Vector2, rot: float, fh: float, hw: float, zh: float, len_t: float, h_px: float,
		st: Dictionary, col: Color, s: int) -> void:
	var ang := 0.0
	if String(st.f) == "ramp_half":
		ang = PI / 4.0
	elif String(st.f) == "unload":
		ang = deg_to_rad(86.0)
	var sink: float = st.sink
	if zh - sink < 0.0:
		return
	var tf := fh + len_t * sin(ang)
	var tz := maxf(0.0, zh + h_px * cos(ang) - 2.5 * sin(ang) - sink)
	var q := PackedVector2Array([D.sp(o, rot, fh, -hw, zh - sink), D.sp(o, rot, fh, hw, zh - sink),
		D.sp(o, rot, tf, hw, tz), D.sp(o, rot, tf, -hw, tz)])
	var fwd := Vector2(cos(rot), sin(rot))
	var shade := lerpf(P.side_shade(fwd) if fwd.x + fwd.y > 0.0 else 0.62, 1.04, ang / (PI / 2.0))
	cv.poly(q, P.mul(col, shade), P.speckle(0.08, s))
	for i in range(1, 4):
		var t := i / 4.0
		cv.line_v(q[0].lerp(q[3], t), q[1].lerp(q[2], t), P.mul(col, shade * 1.22))
	cv.line_v(q[3], q[2], P.mul(col, 1.3))


## Bow spray fan on both sides of the stem (move frames; drawn after the outline so it stays soft).
static func spray(cv, o: Vector2, rot: float, sh: Dictionary, z0: float) -> void:
	var lh: float = sh.L
	var b: float = sh.B
	for side: float in [-1.0, 1.0]:
		for i in 6:
			var t := 1.0 - i * 0.07
			var hb := b * N.half_beam(t, sh.bow) + 0.03 + i * 0.026
			var p := D.sp(o, rot, t * lh + 0.02, side * hb, z0 + 2.6 - i * 0.35)
			cv.ellipse(p.x, p.y, 1.5 - i * 0.12, 1.0, Color(N.FOAM.r, N.FOAM.g, N.FOAM.b, 0.86 - i * 0.1))
		for j in 4:
			var t2 := 0.94 - j * 0.08
			var p2 := D.sp(o, rot, lh * t2, side * (b * N.half_beam(t2, sh.bow) + 0.1 + j * 0.03),
				z0 + 4.0 + P.hn(j, int(side), 77) * 2.5)
			cv.px(int(p2.x), int(p2.y), Color(N.FOAM.r, N.FOAM.g, N.FOAM.b, 0.8))


## Outline, then the frame's soft effects: bow spray (move), muzzle flashes (fire; fx "cyan" for
## Machine pulse guns, "missile" adds launch plumes), fire + smoke (sinking stages), wisps (wreck).
static func finish(cv, o: Vector2, rot: float, sh: Dictionary, st: Dictionary, tips: Array, hot: Array,
		fx := "", spray_z := 0.0, wet := true) -> void:
	cv.outline(N.OUTL)
	var f := String(st.f)
	var stage := int(st.stage)
	if N.live(st):
		if f.ends_with("move") and wet:
			spray(cv, o, rot, sh, spray_z)
		if f == "fire":
			for i in tips.size():
				var t = tips[i]
				if t == null:
					continue
				if fx == "cyan":
					cv.ellipse(t.x, t.y, 2.6, 1.9, Color(ML.CYAN.r, ML.CYAN.g, ML.CYAN.b, 0.55))
					cv.px(int(t.x), int(t.y), ML.CYAN_HOT)
				else:
					L.flash(cv, t, 1.2 if float(sh.L) > 0.9 else 0.9)
					L.puff(cv, t + Vector2(1, -2), 2.2 if float(sh.L) > 0.9 else 1.6, 0.42)
		return
	var src: Array = []
	for p in hot:
		if p != null:
			src.append(p)
	if src.is_empty():
		src.append(D.sp(o, rot, 0.0, 0.0, 0.0))
	if stage < 0:
		L.puff(cv, src[0] + Vector2(1, -4), 2.0, 0.22, Color(0.5, 0.5, 0.48))
		return
	for i in src.size():
		var p: Vector2 = src[i]
		if stage <= 2:
			L.flame(cv, p, Vector2(0.2, -1.0), 3.0 + stage * 1.6, i + stage * 7)
		for j in 2 + stage:
			L.puff(cv, p + Vector2(j * 1.6 + P.hn(i, j, 55) * 2.0, -4.0 - j * 3.4), 2.2 + j * 0.9, 0.58, SMOKE)
