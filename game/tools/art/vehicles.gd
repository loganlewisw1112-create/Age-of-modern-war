extends RefCounted
## Vehicle sheets (ifv, mbt) and their wrecks, rendered from rotated iso boxes.
## Rows = 8 facings (world angle k * 45 deg). Frames: idle, move, fire. Wrecks: 1 frame.
const P = preload("res://tools/art/pix.gd")

const FRAMES := ["idle", "move", "fire"]
const SPEC := {
	"ifv": {"fw": 60, "fh": 46, "pivot": [30, 30]},
	"mbt": {"fw": 70, "fh": 50, "pivot": [35, 32]},
}
const HULL := Color8(96, 100, 74)
const HULL_D := Color8(78, 82, 60)
const TRACK := Color8(44, 44, 40)
const WHEEL := Color8(34, 34, 32)
const GUNMETAL := Color8(58, 60, 58)
const BURNT := Color8(58, 52, 46)
const RUSTY := Color8(104, 66, 44)


static func build(out: Dictionary) -> void:
	var man := {}
	var wrecks := {}
	for def in SPEC:
		var sp: Dictionary = SPEC[def]
		var fw: int = sp.fw
		var fh: int = sp.fh
		var img := Image.create(fw * FRAMES.size(), fh * 8, false, Image.FORMAT_RGBA8)
		var msk := Image.create(fw * FRAMES.size(), fh * 8, false, Image.FORMAT_RGBA8)
		var wimg := Image.create(fw, fh * 8, false, Image.FORMAT_RGBA8)
		for k in 8:
			for f in FRAMES.size():
				var cv = P.Canvas.new(fw, fh)
				draw(cv, def, k * PI / 4.0, f, false, Vector2(sp.pivot[0], sp.pivot[1]))
				img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
				msk.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
			var wc = P.Canvas.new(fw, fh)
			draw(wc, def, k * PI / 4.0, 0, true, Vector2(sp.pivot[0], sp.pivot[1]))
			wimg.blit_rect(wc.img, Rect2i(0, 0, fw, fh), Vector2i(0, k * fh))
		out.images["units/%s.png" % def] = img
		out.images["units/%s_mask.png" % def] = msk
		out.images["wrecks/%s_wreck.png" % def] = wimg
		man[def] = {"file": "units/%s.png" % def, "mask": "units/%s_mask.png" % def, "fw": fw, "fh": fh,
			"pivot": sp.pivot, "frames": FRAMES, "facings": 8}
		wrecks[def] = {"file": "wrecks/%s_wreck.png" % def, "fw": fw, "fh": fh, "pivot": sp.pivot,
			"frames": ["wreck"], "facings": 8}
	out.manifest["vehicles"] = man
	out.manifest["vehicle_wrecks"] = wrecks


## Local (forward, right) offset in tiles -> world xy for a vehicle at origin facing `rot`.
static func _w(rot: float, fwd: float, right: float) -> Vector3:
	return Vector3(cos(rot) * fwd - sin(rot) * right, sin(rot) * fwd + cos(rot) * right, 0)


static func draw(cv, def: String, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var hull: Color = BURNT if wreck else HULL
	var fwd_screen := (cos(rot) + sin(rot))  # > 0: barrel points toward the camera
	var parts: Array = []  # [center(Vector3), hx, hy, hz, rot, color, kind]
	var trot := rot + (0.6 if wreck else 0.0)
	if def == "mbt":
		for s in [-1, 1]:
			parts.append([_w(rot, 0, 0.245 * s), 0.58, 0.095, 6.0, rot, TRACK if not wreck else Color8(40, 36, 32), "track%d" % s])
		parts.append([_w(rot, -0.01, 0) + Vector3(0, 0, 5), 0.56, 0.34, 6.0, rot, hull, "hull"])
		parts.append([_w(trot, -0.06, 0) + Vector3(0, 0, 11), 0.25, 0.21, 5.0, trot, hull, "turret"])
		var bl := 0.36 if f != 2 else 0.32
		var barrel_z := 13.5 if not wreck else 11.5
		parts.append([_w(trot, 0.19 + bl, 0) + Vector3(0, 0, barrel_z), bl, 0.03, 1.8, trot, GUNMETAL if not wreck else BURNT, "barrel"])
	else:
		parts.append([_w(rot, 0, 0) + Vector3(0, 0, 3), 0.52, 0.27, 6.5, rot, hull, "hull"])
		parts.append([_w(rot, -0.06, 0) + Vector3(0, 0, 9.5), 0.42, 0.22, 2.5, rot, P.mul(hull, 1.04), "deck"])
		parts.append([_w(trot, 0.04, 0) + Vector3(0, 0, 12), 0.15, 0.13, 4.0, trot, hull, "turret"])
		parts.append([_w(trot, 0.33, 0) + Vector3(0, 0, 13.5), 0.17, 0.022, 1.4, trot, GUNMETAL if not wreck else BURNT, "barrel"])
	# shadows first (one composite pass)
	for p in parts:
		P.box_shadow(cv, o, p[0], p[1], p[2], p[3], p[4])
	if def == "ifv":
		P.box_shadow(cv, o, Vector3(0, 0, 0), 0.5, 0.3, 3.0, rot)
	cv.flush_shadow()
	# far-side wheels (ifv)
	if def == "ifv":
		_wheels(cv, o, rot, f, false, wreck)
	for p in parts:
		var kind: String = p[6]
		if kind == "barrel" and fwd_screen <= 0.0:
			continue
		if kind == "turret" and fwd_screen <= 0.0:
			_barrel(cv, o, parts[parts.size() - 1])
		if kind == "barrel":
			_barrel(cv, o, p)
			continue
		var r: Dictionary = P.box(cv, o, p[0], p[1], p[2], p[3], p[4], p[5], 0.10, 31 + kind.length())
		if wreck:
			_scorch(cv, r)
			continue
		if kind == "turret":
			cv.team = true
			cv.poly(P.sub(r.top, 0.0, 0.15, 0.55, 0.85), Color(0.78, 0.78, 0.78))
			for sd in r.sides:
				cv.poly(P.sub(sd.quad, 0.08, 0.35, 0.92, 0.7), Color(0.6, 0.6, 0.6))
			cv.team = false
			cv.poly(P.sub(r.top, 0.55, 0.3, 0.75, 0.7), P.mul(hull, 0.7))  # hatch
		elif kind == "hull" or kind == "deck":
			for sd in r.sides:
				if kind == "hull":
					cv.team = def == "mbt"
					cv.poly(P.sub(sd.quad, 0.05, 0.62, 0.95, 0.85), Color(0.62, 0.62, 0.62) if def == "mbt" else HULL_D)
					cv.team = false
				if def == "ifv" and kind == "hull":
					cv.team = true
					cv.poly(P.sub(sd.quad, 0.08, 0.66, 0.92, 0.9), Color(0.62, 0.62, 0.62))
					cv.team = false
			if kind == "deck" or def == "mbt":
				cv.poly(P.sub(r.top, 0.0, 0.0, 0.18, 1.0), P.mul(hull, 0.82))  # rear engine deck grille
		elif kind.begins_with("track"):
			for sd in r.sides:
				var q: PackedVector2Array = sd.quad
				var n := 9
				for i in n:
					var u := (i + (0.5 if f == 1 else 0.0)) / n
					var a: Vector2 = q[0].lerp(q[1], u)
					var b: Vector2 = q[3].lerp(q[2], u)
					cv.line_v(a, a.lerp(b, 0.75), Color8(30, 30, 28))
				cv.line_v(q[0].lerp(q[3], 0.45), q[1].lerp(q[2], 0.45), Color8(62, 60, 54))
	if def == "ifv":
		_wheels(cv, o, rot, f, true, wreck)
	if f == 2 and not wreck:
		var tip := P.proj(o, _w(trot, 0.19 + 0.72 if def == "mbt" else 0.5, 0) + Vector3(0, 0, 14))
		cv.ellipse(tip.x, tip.y, 2.2, 1.6, Color8(255, 230, 150))
		cv.px(int(tip.x), int(tip.y), Color8(255, 255, 230))
	cv.outline(Color(0.08, 0.08, 0.07, 1))


static func _barrel(cv, o: Vector2, p: Array) -> void:
	P.box(cv, o, p[0], p[1], p[2], p[3], p[4], p[5], 0.04, 77)


static func _wheels(cv, o: Vector2, rot: float, f: int, near: bool, wreck: bool) -> void:
	for s in [-1, 1]:
		var n := _w(rot, 0, s)
		var is_near := n.x + n.y > 0.0
		if is_near != near:
			continue
		for i in 4:
			var c := P.proj(o, _w(rot, -0.36 + i * 0.24, 0.27 * s) + Vector3(0, 0, 3))
			cv.ellipse(c.x, c.y, 3.2, 3.0, WHEEL if not wreck else Color8(30, 26, 24))
			if not wreck:
				var hub := Vector2(0.8, 0) if f == 1 else Vector2(-0.4, -0.4)
				cv.px(int(c.x + hub.x), int(c.y + hub.y), Color8(80, 80, 74))


static func _scorch(cv, r: Dictionary) -> void:
	var q: PackedVector2Array = r.top
	cv.poly(q, BURNT, func(x: int, y: int, c: Color) -> Color:
		var h := P.hn(x, y, 909)
		if h > 0.8:
			return P.mix(c, RUSTY, 0.8)
		if h < 0.25:
			return P.mul(c, 0.55)
		return P.mul(c, 0.8 + h * 0.3))
