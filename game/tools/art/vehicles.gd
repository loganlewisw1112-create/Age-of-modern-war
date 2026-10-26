extends RefCounted
## Vehicle sheets (ifv, mbt, logistics_truck) and their wrecks, rendered from rotated iso boxes.
## Rows = 8 facings (world angle k * 45 deg). Frames: idle, move, fire. Wrecks: 1 frame.
## E2 detail pass: running gear, hatches, cupolas, antennas, stowage, launchers, grilles, tow hooks,
## mud, chipped edges and AO (helpers in vdetail.gd). Silhouettes, frame sizes and pivots unchanged.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const T = preload("res://tools/art/truck.gd")

const FRAMES := ["idle", "move", "fire"]
## G6.1 (ANIMB61): 0 = whole vehicle, 1 = hull only (no turret / barrel), 2 = turret + barrel only (no shadow).
## Set by tools/art/g61_anim_veh.gd around its own draw() calls; always reset to 0.
static var layer := 0


static func _in_layer(kind: String) -> bool:
	if layer == 0:
		return true
	var top := kind == "turret" or kind == "barrel"
	return top if layer == 2 else not top
const SPEC := {
	"ifv": {"fw": 60, "fh": 46, "pivot": [30, 30]},
	"mbt": {"fw": 70, "fh": 50, "pivot": [35, 32]},
	"logistics_truck": {"fw": 64, "fh": 48, "pivot": [32, 32]},
}
const HULL := Color8(96, 100, 74)
const HULL_D := Color8(78, 82, 60)
const TRACK := Color8(44, 44, 40)
const WHEEL := Color8(34, 34, 32)
const GUNMETAL := Color8(58, 60, 58)
const BURNT := Color8(58, 52, 46)
const RUSTY := Color8(104, 66, 44)
# Hull-top extras: [kind, fwd, right, z, hx, hy, hz, turret_rot]. Drawn before or after the turret
# depending on whether they sit in front of it from the camera's point of view.
const EXTRAS := {
	"mbt": [["box", -0.30, 0.27, 11, 0.10, 0.055, 2.5, false], ["box", -0.30, -0.27, 11, 0.10, 0.055, 2.5, false],
		["can", -0.49, 0.26, 11, 0.035, 0.045, 3.5, false], ["can", -0.49, -0.26, 11, 0.035, 0.045, 3.5, false],
		["box", -0.35, 0.0, 11.5, 0.04, 0.16, 3.0, true]],
	"ifv": [["can", -0.44, 0.17, 12, 0.035, 0.045, 3.2, false], ["can", -0.44, -0.17, 12, 0.035, 0.045, 3.2, false],
		["box", -0.17, 0.17, 12, 0.08, 0.045, 2.2, false], ["cupola", -0.22, -0.12, 12, 0, 0, 0, false]],
}


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
	if def == "logistics_truck":
		T.draw(cv, rot, f, wreck, o)
		return
	var hull: Color = BURNT if wreck else HULL
	var fwd_screen := (cos(rot) + sin(rot))  # > 0: barrel points toward the camera
	var parts: Array = []  # [center(Vector3), hx, hy, hz, rot, color, kind]
	var trot := rot + (0.6 if wreck else 0.0)
	var tf := -0.06 if def == "mbt" else 0.04  # turret centre (forward offset)
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
	for p in (parts if layer != 2 else []):  # G6.1 (ANIMB61): no ground shadow on a turret-only sprite
		P.box_shadow(cv, o, p[0], p[1], p[2], p[3], p[4])
	if def == "ifv" and layer != 2:
		P.box_shadow(cv, o, Vector3(0, 0, 0), 0.5, 0.3, 3.0, rot)
	cv.flush_shadow()
	if def == "ifv":
		if layer != 2:
			_wheels(cv, o, rot, f, false, wreck)
	for p in parts:
		if not _in_layer(String(p[6])):
			continue
		var kind: String = p[6]
		if kind == "barrel" and fwd_screen <= 0.0:
			continue
		if kind == "turret":
			D.ao(cv, o, p[0], p[1], p[2], p[4], 0.42 if not wreck else 0.3)
			_extras(cv, o, def, rot, trot, tf, wreck, false)
			if fwd_screen <= 0.0:
				_barrel(cv, o, parts[parts.size() - 1], def, wreck)
		if kind == "barrel":
			_barrel(cv, o, p, def, wreck)
			continue
		var r: Dictionary = P.box(cv, o, p[0], p[1], p[2], p[3], p[4], p[5], 0.10, 31 + kind.length())
		if kind.begins_with("track"):
			for sd in r.sides:
				if absf(sd.n.dot(Vector2(-sin(rot), cos(rot)))) > 0.7:
					if not wreck:
						D.mud(cv, sd.quad, 300 + int(p[0].x * 50), 0.55)
					D.track_side(cv, sd.quad, f, wreck)
			continue
		if wreck:
			_scorch(cv, r)
			if kind == "turret":
				_turret_detail(cv, o, def, trot, r, hull, true)
				_extras(cv, o, def, rot, trot, tf, wreck, true)
			continue
		if kind == "turret":
			cv.team = true
			cv.poly(P.sub(r.top, 0.0, 0.15, 0.55, 0.85), Color(0.78, 0.78, 0.78))
			for sd in r.sides:
				cv.poly(P.sub(sd.quad, 0.08, 0.35, 0.92, 0.7), Color(0.6, 0.6, 0.6))
			cv.team = false
			_turret_detail(cv, o, def, trot, r, hull, false)
			_extras(cv, o, def, rot, trot, tf, wreck, true)
		elif kind == "hull" or kind == "deck":
			_hull_detail(cv, def, kind, rot, r, hull)
	if def == "ifv":
		if layer != 2:
			_wheels(cv, o, rot, f, true, wreck)
	if f == 2 and not wreck and layer != 1:
		var tip := P.proj(o, _w(trot, 0.19 + 0.72 if def == "mbt" else 0.5, 0) + Vector3(0, 0, 14))
		cv.ellipse(tip.x, tip.y, 2.2, 1.6, Color8(255, 230, 150))
		cv.px(int(tip.x), int(tip.y), Color8(255, 255, 230))
	cv.outline(Color(0.08, 0.08, 0.07, 1))


static func _hull_detail(cv, def: String, kind: String, rot: float, r: Dictionary, hull: Color) -> void:
	var ax := Vector2(cos(rot), sin(rot))
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		var end := absf((sd.n as Vector2).dot(ax)) > 0.7
		if kind == "hull":
			cv.team = def == "mbt"
			cv.poly(P.sub(q, 0.05, 0.62, 0.95, 0.85), Color(0.62, 0.62, 0.62) if def == "mbt" else HULL_D)
			cv.team = false
			if def == "ifv":
				cv.team = true
				cv.poly(P.sub(q, 0.08, 0.66, 0.92, 0.9), Color(0.62, 0.62, 0.62))
				cv.team = false
			D.mud(cv, q, 410 + int(q[0].x), 0.42)
			if end:
				D.tow_hooks(cv, q)
				if def == "ifv" and (sd.n as Vector2).dot(ax) < 0.0:  # rear troop ramp
					var rq := P.sub(q, 0.24, 0.1, 0.76, 0.6)
					cv.line_v(rq[0], rq[3], P.mul(hull, 0.6))
					cv.line_v(rq[1], rq[2], P.mul(hull, 0.6))
					cv.line_v(rq[3], rq[2], P.mul(hull, 1.2))
	if kind == "hull":
		D.contact_ao(cv, r)
	D.box_edges(cv, r, hull, 91 + kind.length())
	if def == "mbt":
		D.grille(cv, r.top, 0.0, 0.24, 0.17, 0.76, hull, 4)  # rear engine deck / exhaust
		D.hatch(cv, r.top, 0.82, 0.4, 0.93, 0.6, hull)      # driver's hatch
	elif kind == "deck":
		D.hatch(cv, r.top, 0.04, 0.12, 0.22, 0.42, hull)
		D.hatch(cv, r.top, 0.04, 0.58, 0.22, 0.88, hull)
		D.grille(cv, r.top, 0.76, 0.62, 0.95, 0.92, hull, 3)  # engine exhaust, front right


static func _turret_detail(cv, o: Vector2, def: String, trot: float, r: Dictionary, hull: Color, wreck: bool) -> void:
	if not wreck:
		D.box_edges(cv, r, hull, 97)
	if def == "mbt":
		if not wreck:
			D.hatch(cv, r.top, 0.28, 0.62, 0.5, 0.86, hull)  # loader's hatch
		D.cupola(cv, o, trot, -0.12, -0.09, 16, hull, wreck)
		for s in [-1, 1]:
			D.smoke_launchers(cv, D.sp(o, trot, 0.16, 0.19 * s, 15), wreck)
		D.antenna(cv, D.sp(o, trot, -0.27, -0.15, 16), 13, wreck)
		D.antenna(cv, D.sp(o, trot, -0.27, 0.15, 16), 8, wreck)
	else:
		for s in [-1, 1]:
			D.smoke_launchers(cv, D.sp(o, trot, 0.14, 0.12 * s, 15.5), wreck)
		var t: PackedVector2Array = r.top
		var m: Vector2 = t[1].lerp(t[2], 0.5).lerp((t[0] + t[2]) * 0.5, 0.4)
		cv.px(int(m.x), int(m.y), D.VISION if not wreck else D.DARK)  # gunner's sight
		D.antenna(cv, D.sp(o, trot, -0.5, 0.17, 12), 12, wreck)


static func _extras(cv, o: Vector2, def: String, rot: float, trot: float, tf: float, wreck: bool, front: bool) -> void:
	for e in EXTRAS.get(def, []):
		var er: float = trot if e[7] else rot
		var rel_f: float = e[1] - (tf if not e[7] else -0.06)
		if D.faces_cam(er, rel_f, e[2]) != front:
			continue
		if e[0] == "cupola":
			D.cupola(cv, o, er, e[1], e[2], e[3], BURNT if wreck else HULL, wreck)
		else:
			D.stowage(cv, o, er, e[1], e[2], e[3], e[4], e[5], e[6], e[0] == "can", wreck)


## Barrel plus (MBT) mantlet and bore evacuator. Draw order depends on whether it points at the camera.
static func _barrel(cv, o: Vector2, p: Array, def: String, wreck: bool) -> void:
	var trot: float = p[4]
	var bl: float = p[1]
	var toward := cos(trot) + sin(trot) > 0.0
	var col: Color = p[5]
	if def != "mbt":
		P.box(cv, o, p[0], p[1], p[2], p[3], p[4], p[5], 0.04, 77)
		return
	var mz: float = p[0].z - 2.0
	var man_c: Vector3 = _w(trot, 0.2, 0) + Vector3(0, 0, mz) + Vector3(p[0].x, p[0].y, 0) - _w(trot, 0.19 + bl, 0)
	var ev_c: Vector3 = p[0] + _w(trot, bl * 0.3, 0) + Vector3(0, 0, -0.4)
	if toward:
		P.box(cv, o, man_c, 0.04, 0.1, 4.0, trot, P.mul(BURNT if wreck else HULL, 0.9), 0.05, 79)
	P.box(cv, o, p[0], p[1], p[2], p[3], p[4], col, 0.04, 77)
	P.box(cv, o, ev_c, 0.07, 0.045, 2.6, trot, P.mul(col, 1.12), 0.04, 78)
	var tip := P.proj(o, p[0] + _w(trot, bl, 0) + Vector3(0, 0, 1))
	cv.px(int(tip.x), int(tip.y), P.mul(col, 0.5))
	if not toward:
		P.box(cv, o, man_c, 0.04, 0.1, 4.0, trot, P.mul(BURNT if wreck else HULL, 0.9), 0.05, 79)


static func _wheels(cv, o: Vector2, rot: float, f: int, near: bool, wreck: bool) -> void:
	for s in [-1, 1]:
		var n := _w(rot, 0, s)
		var is_near := n.x + n.y > 0.0
		if is_near != near:
			continue
		for i in 4:
			var c := P.proj(o, _w(rot, -0.36 + i * 0.24, 0.27 * s) + Vector3(0, 0, 3))
			D.road_wheel(cv, c, 3.2, 3.0, f, wreck)
			if near and not wreck and P.hn(i, s, 17) > 0.4:  # mud on the tyre's lower edge
				cv.px(int(c.x) - 1, int(c.y) + 2, Color(D.MUD.r, D.MUD.g, D.MUD.b, 0.8))
				cv.px(int(c.x) + 1, int(c.y) + 2, Color(D.MUD_D.r, D.MUD_D.g, D.MUD_D.b, 0.7))


static func _scorch(cv, r: Dictionary) -> void:
	var q: PackedVector2Array = r.top
	cv.poly(q, BURNT, func(x: int, y: int, c: Color) -> Color:
		var h := P.hn(x, y, 909)
		if h > 0.8:
			return P.mix(c, RUSTY, 0.8)
		if h < 0.25:
			return P.mul(c, 0.55)
		return P.mul(c, 0.8 + h * 0.3))
