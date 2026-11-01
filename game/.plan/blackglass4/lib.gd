extends RefCounted
## Site Blackglass v2 art library (mockup). World metres, the G7 faceted renderer (g7_cn_mesh), 4 m / tile,
## 9.8 px per metre of height. g = the generator instance (lamp / pool light layer). Everything is deterministic.

const M = preload("res://tools/art/g7_cn_mesh.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const P = preload("res://tools/art/pix.gd")
const RO = preload("res://tools/art/g7_rollout.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")

# --- palette (grounded military, low saturation; saturated only for lights, hazard, team)
const BRUT := Color8(98, 98, 96)        # brutalist cast concrete
const BRUT_D := Color8(76, 77, 78)
const CONC := Color8(150, 148, 140)
const CONC_L := Color8(178, 176, 168)
const LAB := Color8(208, 212, 214)
const STEEL := Color8(84, 90, 96)
const GUN := Color8(58, 62, 66)
const DARK := Color8(40, 43, 46)
const OLIVE := Color8(92, 100, 82)
const SAND := Color8(150, 136, 104)
const ASPH := Color8(68, 70, 72)
const GRAVEL := Color8(112, 106, 96)
const YEL := Color8(226, 184, 40)
const ORANGE := Color8(232, 122, 40)
const RED := Color8(255, 64, 48)
const TEAM := Color8(79, 125, 176)
const MACH := Color8(196, 64, 52)
const GLASS := Color(0.55, 0.85, 1.0, 0.30)
const GLASS_D := Color8(52, 78, 96)
const LAMP_W := Color8(255, 244, 210)
const L_WARM := Color(1.0, 0.9, 0.7, 0.55)
const L_COLD := Color(0.85, 0.95, 1.0, 0.55)
const L_RED := Color(1.0, 0.2, 0.15, 1.0)
const L_AMB := Color(1.0, 0.68, 0.18, 1.0)
const L_GRN := Color(0.4, 1.0, 0.5, 1.0)
const L_CYAN := Color(0.45, 0.85, 1.0, 1.0)
const X := Vector3(1, 0, 0)
const Y := Vector3(0, 1, 0)
const Z := Vector3(0, 0, 1)

static var _sheets := {}


static func rp(c: Color) -> Array:
	return C.ramp(c)


static func quad(pt: Dictionary, T: Dictionary, c: Vector3, u: Vector3, v: Vector3, col: Color, nl := Z) -> void:
	M.dpoly(pt, T, [c - u - v, c + u - v, c + u + v, c - u + v], col, nl)


static func line(pt: Dictionary, T: Dictionary, a: Vector3, b: Vector3, col: Color, nl := Vector3.ZERO) -> void:
	M.dline(pt, T, a, b, col, nl)


static func hazard(pt: Dictionary, T: Dictionary, a: Vector3, b: Vector3, nl: Vector3, seg := 0.6) -> void:
	var n := maxi(2, int(a.distance_to(b) / seg))
	for i in n:
		M.dline(pt, T, a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), GR.HAZ if i % 2 == 0 else GR.HAZ_D, nl)


static func along(nl: Vector3) -> Vector3:
	return Y if absf(nl.x) > 0.5 else X


## Stencil sign plate: dark plate, accent stripe, light glyph bars (no font, reads as lettering at RTS zoom).
static func plate(pt: Dictionary, T: Dictionary, c: Vector3, nl: Vector3, w: float, h: float, accent: Color, seed := 1) -> void:
	var al := along(nl)
	quad(pt, T, c + nl * 0.02, al * w * 0.5, Z * h * 0.5, Color8(28, 31, 34), nl)
	M.dline(pt, T, c + nl * 0.03 - al * w * 0.46 - Z * h * 0.34, c + nl * 0.03 + al * w * 0.46 - Z * h * 0.34, accent, nl)
	var n := maxi(3, int(w / 0.42))
	for i in n:
		var x := -w * 0.42 + w * 0.84 * float(i) / float(n - 1)
		if P.hn(i, seed, 3) < 0.18:
			continue
		var hh := h * (0.14 + 0.16 * P.hn(i, seed, 5))
		M.dline(pt, T, c + nl * 0.03 + al * x - Z * h * 0.1, c + nl * 0.03 + al * x - Z * h * 0.1 + Z * hh, Color8(228, 228, 216), nl)


static func flood(g, pt: Dictionary, T: Dictionary, p: Vector3, nl: Vector3, reach := 7.0) -> void:
	M.box(pt, T, p + nl * 0.22, Vector3(0.22, 0.22, 0.14), rp(STEEL))
	M.dpx(pt, T, p + nl * 0.46, LAMP_W, nl)
	g.lamp(T, p + nl * 0.5, Color(1, 0.95, 0.82, 0.9), 9.0)
	g.pool(T, Vector3(p.x, p.y, 0.1) + nl * reach, reach * 0.85, reach * 0.85)


static func camera(g, pt: Dictionary, T: Dictionary, p: Vector3, nl: Vector3) -> void:
	M.box(pt, T, p + nl * 0.25, Vector3(0.18, 0.12, 0.12), rp(Color8(200, 200, 194)))
	M.dpx(pt, T, p + nl * 0.45, Color8(30, 30, 30), nl)
	M.dpx(pt, T, p + nl * 0.3 + Z * 0.14, Color8(255, 60, 40), nl)


# =============================================================== BUILDINGS
## Detailed building block. x0..x1, y0..y1 metres, h height, floors n. opt:
##   style: "brut" (dark cast concrete, slit windows) | "panel" (light precast, strip windows) | "lab"
##   doors: [[face "x"|"y", along-offset, width, height, kind "roll"|"open"|"person"|"blast"]]
##   lit: 0..1 fraction of lit windows, roof: true = HVAC/vents/antenna, sign: accent colour or null
static func building(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float, h: float, opt := {}) -> void:
	var style: String = opt.get("style", "brut")
	var base: Color = BRUT if style == "brut" else (CONC_L if style == "panel" else LAB)
	var r: Array = rp(base)
	var floors: int = opt.get("floors", maxi(1, int(h / 3.6)))
	var seed: int = opt.get("seed", int(x0 * 7 + y0 * 13))
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	var hx := (x1 - x0) * 0.5
	var hy := (y1 - y0) * 0.5
	var pm := M.part(S, 0)
	M.box(pm, T, Vector3(cx, cy, 0.45), Vector3(hx + 0.12, hy + 0.12, 0.45), rp(P.mul(base, 0.72)))     # plinth
	M.box(pm, T, Vector3(cx, cy, h * 0.5 + 0.45), Vector3(hx, hy, h * 0.5 - 0.45), r)
	# visible faces: +x and +y. Panel joints, floor bands, windows, grime, conduit, downpipes.
	for nl: Vector3 in [X, Y]:
		var al := along(nl)
		var ln := (y1 - y0) if nl == X else (x1 - x0)
		var fc := Vector3(x1, cy, 0) if nl == X else Vector3(cx, y1, 0)
		var step := 3.0 if style == "brut" else 2.4
		var nj := int(ln / step)
		for i in range(1, nj):
			var a := fc - al * ln * 0.5 + al * step * i + nl * 0.015
			M.dline(pm, T, a + Z * 0.9, a + Z * h, Color(0.15, 0.15, 0.14, 0.32), nl)
		for f in range(1, floors):
			var z := 0.9 + f * (h - 0.9) / floors
			M.dline(pm, T, fc - al * ln * 0.5 + nl * 0.015 + Z * z, fc + al * ln * 0.5 + nl * 0.015 + Z * z, Color(0.12, 0.12, 0.12, 0.35), nl)
		# windows
		for f in floors:
			var zc := 0.9 + (f + 0.62) * (h - 0.9) / floors
			if style == "brut":
				var nw := int(ln / 4.5)
				for k in nw:
					var off := -ln * 0.5 + (k + 0.5) * ln / nw
					var lit := P.hn(k + f * 31, seed + int(nl.x * 3), 11) < float(opt.get("lit", 0.35))
					quad(pm, T, fc + nl * 0.02 + al * off + Z * zc, al * 0.9, Z * 0.14, Color8(255, 222, 160) if lit else Color8(18, 19, 20), nl)
					if lit:
						g.lamp(T, fc + nl * 0.06 + al * off + Z * zc, L_WARM, 6.0)
			else:
				var lit2 := P.hn(f, seed + int(nl.y * 5), 13) < float(opt.get("lit", 0.5))
				quad(pm, T, fc + nl * 0.02 + Z * zc, al * (ln * 0.5 - 1.2), Z * 0.45, Color8(240, 220, 170) if lit2 else GLASS_D, nl)
				var nm := int((ln - 2.4) / 1.6)
				for k in range(1, nm):
					M.dline(pm, T, fc + nl * 0.03 - al * (ln * 0.5 - 1.2) + al * k * 1.6 + Z * (zc - 0.45), fc + nl * 0.03 - al * (ln * 0.5 - 1.2) + al * k * 1.6 + Z * (zc + 0.45), Color8(70, 76, 82), nl)
				M.dline(pm, T, fc + nl * 0.03 - al * (ln * 0.5 - 1.2) + Z * (zc + 0.42), fc + nl * 0.03 + al * (ln * 0.2) + Z * (zc + 0.42), Color(1, 1, 1, 0.45), nl)
				if lit2:
					for k in maxi(1, int(ln / 8.0)):
						g.lamp(T, fc + nl * 0.06 - al * (ln * 0.5 - 4.0) + al * k * 8.0 + Z * zc, L_WARM, 8.0)
		# grime at the base + rain streaks from the parapet
		quad(pm, T, fc + nl * 0.016 + Z * 1.4, al * ln * 0.5, Z * 0.5, Color(0.1, 0.1, 0.08, 0.16), nl)
		for k in int(ln / 5.0):
			var off := -ln * 0.5 + 2.0 + k * 5.0 + 1.6 * P.hn(k, seed, 17)
			M.dline(pm, T, fc + nl * 0.017 + al * off + Z * (h - 0.2), fc + nl * 0.017 + al * off + Z * (h - 2.0 - 2.0 * P.hn(k, seed, 19)), Color(0.1, 0.1, 0.09, 0.22), nl)
		# downpipe + conduit
		M.cyl(pm, T, fc + nl * 0.12 + al * (ln * 0.5 - 0.6) + Z * (h * 0.5), Z, 0.08, h * 0.5, 4, rp(Color8(110, 114, 116)), {"edge": false})
		M.dline(pm, T, fc + nl * 0.05 - al * ln * 0.45 + Z * 3.0, fc + nl * 0.05 + al * ln * 0.2 + Z * 3.0, Color8(60, 64, 68), nl)
		# wall floodlights + camera on the visible faces
		flood(g, pm, T, fc + al * (ln * 0.3) + Z * (h - 1.2), nl, 6.0)
		camera(g, pm, T, fc - al * (ln * 0.42) + Z * (h - 0.8), nl)
	# doors
	for d in opt.get("doors", []):
		_door(S, T, g, d, x0, y0, x1, y1, h)
	# sign
	if opt.has("sign"):
		plate(pm, T, Vector3(x1, cy + hy * 0.35, h - 1.2), X, minf(hy, 6.0), 0.9, opt.sign, seed)
	# roof: parapet, membrane seams, HVAC with fans, vents, hatch, antenna mast + red light
	var pr := M.part(S, 1)
	var rt := h + 0.45
	for e in [[Vector3(cx, y0 + 0.15, rt + 0.35), Vector3(hx, 0.15, 0.35)], [Vector3(cx, y1 - 0.15, rt + 0.35), Vector3(hx, 0.15, 0.35)],
			[Vector3(x0 + 0.15, cy, rt + 0.35), Vector3(0.15, hy, 0.35)], [Vector3(x1 - 0.15, cy, rt + 0.35), Vector3(0.15, hy, 0.35)]]:
		M.box(pr, T, e[0], e[1], rp(P.mul(base, 0.85)))
	var rf := M.part(S, 0.5)
	quad(rf, T, Vector3(cx, cy, rt + 0.01), X * (hx - 0.3), Y * (hy - 0.3), Color8(86, 88, 86))
	for i in range(1, int(hx / 2.0)):
		M.dline(rf, T, Vector3(x0 + i * 4.0, y0 + 0.4, rt + 0.02), Vector3(x0 + i * 4.0, y1 - 0.4, rt + 0.02), Color(0.2, 0.2, 0.2, 0.35), Z)
	if opt.get("roof", true):
		var nh := maxi(1, int(hx * hy / 60.0))
		for k in nh:
			var p := Vector3(x0 + 2.5 + (x1 - x0 - 5.0) * P.hn(k, seed, 23), y0 + 2.5 + (y1 - y0 - 5.0) * P.hn(k, seed, 29), rt)
			M.box(pr, T, p + Z * 0.55, Vector3(1.1, 0.8, 0.55), rp(Color8(150, 154, 156)), Vector3(0.04, 0.04, 0.04))
			for s: float in [-0.45, 0.45]:
				M.cyl(pr, T, p + Vector3(s, 0, 1.12), Z, 0.34, 0.03, 10, rp(DARK), {"cap_t": 0})
		for k in 2:
			M.cyl(pr, T, Vector3(x0 + 1.5 + k * (x1 - x0 - 3.0), y0 + 1.5, rt + 0.6), Z, 0.22, 0.6, 6, rp(STEEL))
		var am := Vector3(x0 + 1.6, y1 - 1.6, rt)
		M.cyl(pr, T, am + Z * 2.4, Z, 0.05, 2.4, 4, rp(STEEL), {"edge": false})
		g.lamp(T, am + Z * 4.9, L_RED, 7.0, true, pr)


static func _door(S: Array, T: Dictionary, g, d: Array, x0: float, y0: float, x1: float, y1: float, h: float) -> void:
	var face: String = d[0]
	var nl := X if face == "x" else Y
	var al := along(nl)
	var c := (Vector3(x1, (y0 + y1) * 0.5 + float(d[1]), 0) if face == "x" else Vector3((x0 + x1) * 0.5 + float(d[1]), y1, 0))
	var w: float = d[2]
	var dh: float = d[3]
	var kind: String = d[4]
	var pd := M.part(S, 1)
	if kind == "person":
		quad(pd, T, c + nl * 0.02 + Z * 1.1, al * 0.55, Z * 1.1, Color8(70, 76, 80), nl)
		M.box(pd, T, c + nl * 0.6 + Z * 2.5, (al * 1.0).abs() + (nl * 0.6).abs() + Vector3(0, 0, 0.08), rp(STEEL))
		g.lamp(T, c + nl * 0.3 + Z * 2.35, L_WARM, 7.0, true, pd)
		g.pool(T, c + nl * 1.5, 1.5, 1.5)
		return
	# frame + jambs
	for s: float in [-1.0, 1.0]:
		hazard(pd, T, c + nl * 0.03 + al * s * (w * 0.5 + 0.15), c + nl * 0.03 + al * s * (w * 0.5 + 0.15) + Z * dh, nl, 0.5)
	M.dline(pd, T, c + nl * 0.03 - al * (w * 0.5 + 0.2) + Z * (dh + 0.1), c + nl * 0.03 + al * (w * 0.5 + 0.2) + Z * (dh + 0.1), Color8(30, 32, 34), nl)
	if kind == "open":
		quad(pd, T, c + nl * 0.02 + Z * dh * 0.5, al * w * 0.5, Z * dh * 0.5, Color8(34, 37, 40), nl)
		quad(pd, T, c + nl * 0.025 + Z * (dh - 0.3), al * w * 0.48, Z * 0.15, Color8(220, 225, 230), nl)
		for k in 3:
			g.lamp(T, c + nl * 0.1 + al * (-w * 0.3 + k * w * 0.3) + Z * (dh - 0.4), L_COLD, 7.0)
		g.pool(T, c + nl * 3.0, w * 0.45, 3.0, Color(0.9, 0.95, 1.0, 0.5))
	elif kind == "blast":
		M.box(pd, T, c + nl * 0.15 + Z * dh * 0.5, (al * w * 0.5).abs() + (nl * 0.15).abs() + Vector3(0, 0, dh * 0.5), rp(GUN))
		for i in int(dh / 0.8):
			for s: float in [-1.0, 1.0]:
				M.dline(pd, T, c + nl * 0.31 + al * s * 0.15 + Z * (0.3 + i * 0.8), c + nl * 0.31 + al * s * w * 0.46 + Z * (0.8 + i * 0.8), GR.HAZ if i % 2 == 0 else GR.HAZ_D, nl)
		M.dline(pd, T, c + nl * 0.31, c + nl * 0.31 + Z * dh, Color8(16, 17, 18), nl)
		g.lamp(T, c + nl * 0.5 + al * (w * 0.5 + 0.6) + Z * (dh + 0.3), L_RED, 8.0, true, pd)
	else:   # roll-up door down
		quad(pd, T, c + nl * 0.03 + Z * dh * 0.5, al * w * 0.5, Z * dh * 0.5, Color8(110, 116, 120), nl)
		for i in int(dh / 0.32):
			M.dline(pd, T, c + nl * 0.035 - al * w * 0.5 + Z * (0.2 + i * 0.32), c + nl * 0.035 + al * w * 0.5 + Z * (0.2 + i * 0.32), Color8(80, 86, 90), nl)
		g.lamp(T, c + nl * 0.4 + al * (w * 0.5 + 0.5) + Z * (dh + 0.2), L_AMB, 6.0, true, pd)


## Hardened aircraft / drone shelter: arched concrete vault (loft), blast door on +x, earth berm at the sides.
static func vault_shelter(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float, h: float, door_open := false) -> void:
	var pt := M.part(S, 0)
	var cy := (y0 + y1) * 0.5
	var hy := (y1 - y0) * 0.5
	var sec := PackedVector2Array()
	var n := 10
	for i in n + 1:
		var a := PI * float(i) / n
		sec.append(Vector2(cy - cos(a) * hy, sin(a) * h))
	M.loft(pt, T, [[x0, sec], [x0 + 0.001, sec], [x1 - 0.001, sec], [x1, sec]], rp(BRUT))
	for k in int((x1 - x0) / 3.0):
		var xx := x0 + 1.5 + k * 3.0
		for i in n:
			var a0 := PI * float(i) / n
			var a1 := PI * float(i + 1) / n
			M.dline(pt, T, Vector3(xx, cy - cos(a0) * hy * 1.002, sin(a0) * h * 1.002), Vector3(xx, cy - cos(a1) * hy * 1.002, sin(a1) * h * 1.002), Color(0.15, 0.15, 0.14, 0.35))
	# front blast door (+x face)
	var pd := M.part(S, 1)
	var dc := Vector3(x1 + 0.02, cy, 0)
	if door_open:
		var pts: Array = []
		for i in n + 1:
			var a := PI * float(i) / n
			pts.append(Vector3(x1 + 0.03, cy - cos(a) * (hy - 0.8), sin(a) * (h - 0.8)))
		M.dpoly(pd, T, pts, Color8(30, 32, 35), X)
		for k in 3:
			g.lamp(T, Vector3(x1 + 0.1, cy - hy * 0.4 + k * hy * 0.4, h * 0.55), L_COLD, 8.0)
		g.pool(T, Vector3(x1 + 4.0, cy, 0), 4.0, hy * 0.8, Color(0.9, 0.95, 1.0, 0.5))
	else:
		var pts2: Array = []
		for i in n + 1:
			var a := PI * float(i) / n
			pts2.append(Vector3(x1 + 0.03, cy - cos(a) * (hy - 0.6), sin(a) * (h - 0.6)))
		M.dpoly(pd, T, pts2, Color8(86, 92, 96), X)
		M.dline(pd, T, dc + Vector3(0.02, 0, 0), dc + Vector3(0.02, 0, h - 0.6), Color8(20, 22, 24), X)
	hazard(pd, T, Vector3(x1 + 0.04, cy - hy + 0.4, 0.3), Vector3(x1 + 0.04, cy + hy - 0.4, 0.3), X)
	g.lamp(T, Vector3(x1 + 0.3, cy + hy * 0.7, h * 0.6), L_AMB, 7.0, true, pd)
	plate(pd, T, Vector3(x1 + 0.03, cy, h * 0.82), X, hy * 0.6, 0.7, YEL)


## Earth-covered ammunition igloo (arched, berm over it, headwall + door on +x).
static func igloo(S: Array, T: Dictionary, g, x0: float, y0: float, x1: float, y1: float) -> void:
	var pt := M.part(S, 0)
	var cy := (y0 + y1) * 0.5
	var hy := (y1 - y0) * 0.5
	var sec := PackedVector2Array()
	for i in 9:
		var a := PI * float(i) / 8.0
		sec.append(Vector2(cy - cos(a) * (hy + 1.6), sin(a) * 3.6))
	M.loft(pt, T, [[x0, sec], [x0 + 0.001, sec], [x1 - 0.5, sec], [x1 - 0.499, sec]], rp(Color8(102, 112, 74)))
	M.box(pt, T, Vector3(x1 - 0.2, cy, 2.0), Vector3(0.3, hy + 0.6, 2.0), rp(BRUT))
	quad(pt, T, Vector3(x1 + 0.11, cy, 1.2), Y * 1.2, Z * 1.2, Color8(90, 96, 100), X)
	plate(pt, T, Vector3(x1 + 0.11, cy, 3.2), X, 2.4, 0.5, RED)
	g.lamp(T, Vector3(x1 + 0.3, cy + 1.8, 2.8), L_RED, 5.0, true, pt)


# =============================================================== TURRETS (new detailed mounts)
## Twin rotary railgun turret on a ring mount. at = ground point of the mount top, yaw (rad, 0 = +x).
static func t_railgun(S: Array, T: Dictionary, g, at: Vector3, yaw: float, s := 1.0, fire := false) -> void:
	var Tt := M.sub(T, at, yaw)
	var pt := M.part(S, 2)
	var hull: Array = rp(Color8(86, 94, 102))
	M.cyl(pt, Tt, Vector3(0, 0, 0.3) * s, Z, 1.7 * s, 0.3 * s, 14, rp(GUN))
	M.box(pt, Tt, Vector3(-0.2, 0, 1.25) * s, Vector3(1.6, 1.25, 0.65) * s, hull, Vector3(0.5, 0.2, 0.25) * s)
	M.box(pt, Tt, Vector3(-1.5, 0, 1.4) * s, Vector3(0.5, 1.0, 0.5) * s, rp(GUN))             # capacitor bank
	for side: float in [-0.55, 0.55]:
		var bc := Vector3(2.2, side, 1.3) * s
		M.cyl(pt, Tt, bc, X, 0.24 * s, 1.9 * s, 8, rp(DARK))
		for k in 4:
			M.cyl(pt, Tt, bc + Vector3(-1.2 + k * 0.7, 0, 0) * s, X, 0.32 * s, 0.07 * s, 8, rp(Color8(110, 180, 255)), {"caps": false})
		M.cyl(pt, Tt, bc + Vector3(1.95, 0, 0) * s, X, 0.3 * s, 0.12 * s, 8, rp(GUN))
		if fire:
			g.lamp(Tt, bc + Vector3(2.4, 0, 0) * s, Color(0.6, 0.85, 1.0, 1.0), 14.0)
	M.box(pt, Tt, Vector3(0.2, 1.35, 1.9) * s, Vector3(0.35, 0.18, 0.25) * s, rp(DARK))    # sensor pod
	M.dpx(pt, Tt, Vector3(0.56, 1.35, 1.9) * s, Color8(255, 60, 40), X)
	g.lamp(Tt, Vector3(-0.6, 0, 2.2) * s, L_CYAN, 5.0, true, pt)


## Laser CIWS: drum turret, big emitter lens, tracking radar panel.
static func t_laser(S: Array, T: Dictionary, g, at: Vector3, yaw: float, s := 1.0, beam_to := Vector3.INF) -> void:
	var Tt := M.sub(T, at, yaw)
	var pt := M.part(S, 2)
	M.cyl(pt, Tt, Vector3(0, 0, 0.25) * s, Z, 1.2 * s, 0.25 * s, 12, rp(GUN))
	M.cyl(pt, Tt, Vector3(0, 0, 1.1) * s, Z, 1.0 * s, 0.6 * s, 12, rp(Color8(176, 182, 186)), {"cap_t": 4})
	M.cyl(pt, Tt, Vector3(0.95, 0, 1.15) * s, X, 0.55 * s, 0.25 * s, 12, rp(DARK))
	M.cyl(pt, Tt, Vector3(1.22, 0, 1.15) * s, X, 0.4 * s, 0.02 * s, 12, rp(Color8(90, 200, 255)), {"cap_t": 4})
	M.box(pt, Tt, Vector3(-0.5, 0, 2.0) * s, Vector3(0.12, 0.7, 0.45) * s, rp(Color8(120, 126, 130)))
	g.lamp(Tt, Vector3(1.3, 0, 1.15) * s, L_CYAN, 8.0, true, pt)
	if beam_to != Vector3.INF:
		M.dline(pt, T, at + M.wdir(Tt, X) * 1.3 * s + Z * 1.15 * s, beam_to, Color(0.6, 0.95, 1.0, 0.95))
		g.lamp(T, beam_to, L_CYAN, 10.0)


## Twin flak cannon on an armoured mount, barrels raised.
static func t_flak(S: Array, T: Dictionary, g, at: Vector3, yaw: float, s := 1.0) -> void:
	var Tt := M.sub(T, at, yaw)
	var pt := M.part(S, 2)
	M.cyl(pt, Tt, Vector3(0, 0, 0.3) * s, Z, 1.4 * s, 0.3 * s, 12, rp(GUN))
	M.box(pt, Tt, Vector3(0, 0, 1.2) * s, Vector3(1.2, 1.1, 0.6) * s, rp(OLIVE), Vector3(0.4, 0.2, 0.2) * s)
	for side: float in [-0.45, 0.45]:
		var d := Vector3(0.8, 0, 0.6).normalized()
		M.cyl(pt, Tt, Vector3(1.2, side, 1.5) * s + d * 1.4 * s, d, 0.13 * s, 1.5 * s, 6, rp(DARK))
		M.cyl(pt, Tt, Vector3(1.2, side, 1.5) * s + d * 2.95 * s, d, 0.2 * s, 0.15 * s, 6, rp(DARK))
	M.box(pt, Tt, Vector3(-0.9, 0.9, 1.6) * s, Vector3(0.35, 0.3, 0.4) * s, rp(GUN))
	g.lamp(Tt, Vector3(-0.9, 0.9, 2.1) * s, L_AMB, 4.0, true, pt)


## SAM box launcher (2 x 4 cells) on a trainable pedestal, raised 35 deg.
static func t_sam(S: Array, T: Dictionary, g, at: Vector3, yaw: float, s := 1.0) -> void:
	var Tt := M.sub(T, at, yaw)
	var pt := M.part(S, 2)
	M.cyl(pt, Tt, Vector3(0, 0, 0.6) * s, Z, 0.7 * s, 0.6 * s, 10, rp(GUN))
	var Tl := M.sub(Tt, Vector3(0, 0, 1.7) * s, 0.0, 0.6)
	M.box(pt, Tl, Vector3.ZERO, Vector3(1.9, 1.2, 0.7) * s, rp(OLIVE), Vector3(0.05, 0.05, 0.05))
	for i in 4:
		for j in 2:
			M.cyl(pt, Tl, Vector3(1.91, -0.85 + i * 0.57, -0.3 + j * 0.6) * s, X, 0.22 * s, 0.02 * s, 8, rp(Color8(200, 60, 50) if (i + j) % 3 != 0 else DARK), {"cap_t": 3})
	g.lamp(Tt, Vector3(0, 0, 1.3) * s, L_GRN, 4.0, true, pt)


## Remote weapon station (MG) for wall parapets: small armoured box, barrel, sensor.
static func t_rws(S: Array, T: Dictionary, g, at: Vector3, yaw: float, s := 1.0) -> void:
	var Tt := M.sub(T, at, yaw)
	var pt := M.part(S, 2)
	M.cyl(pt, Tt, Vector3(0, 0, 0.18) * s, Z, 0.55 * s, 0.18 * s, 8, rp(GUN))
	M.box(pt, Tt, Vector3(0, 0, 0.7) * s, Vector3(0.55, 0.45, 0.35) * s, rp(Color8(96, 104, 110)), Vector3(0.15, 0.05, 0.1) * s)
	M.cyl(pt, Tt, Vector3(1.1, 0.12, 0.72) * s, X, 0.06 * s, 0.6 * s, 5, rp(DARK))
	M.box(pt, Tt, Vector3(0.25, -0.38, 0.95) * s, Vector3(0.18, 0.12, 0.14) * s, rp(DARK))
	M.dpx(pt, Tt, Vector3(0.44, -0.38, 0.95) * s, Color8(255, 70, 50), X)


# =============================================================== PADS + LIFTS
## Landing pad with its own aircraft lift. c = centre (z = deck height), r = half size. lift: "up" (flush, craft on it)
## or "down" (open shaft, guard rails, rotating beacons). letter: pad marking glyph count.
static func pad(S: Array, T: Dictionary, g, c: Vector3, r: float, lift: String, accent: Color, seed := 1) -> void:
	var pg := M.part(S, 0.2)
	var pc: Array = rp(Color8(92, 94, 96))
	M.box(pg, T, c - Z * 0.25, Vector3(r, r, 0.25), pc)
	var oct: Array = []
	for k in 8:
		var a := PI / 8.0 + TAU * k / 8.0
		oct.append(c + Vector3(cos(a), sin(a), 0) * r * 0.96 + Z * 0.012)
	M.dpoly(pg, T, oct, Color8(78, 80, 84), Z)
	for k in 8:
		M.dline(pg, T, oct[k], oct[(k + 1) % 8], Color8(232, 232, 220), Z)
	# touchdown circle
	for k in 24:
		var a0 := TAU * k / 24.0
		var a1 := TAU * (k + 1) / 24.0
		M.dline(pg, T, c + Vector3(cos(a0), sin(a0), 0.02) * r * 0.6, c + Vector3(cos(a1), sin(a1), 0.02) * r * 0.6, YEL, Z)
	# lift platform (square inset)
	var lr := r * 0.52
	if lift == "down":
		quad(pg, T, c + Z * 0.015, X * lr, Y * lr, Color8(10, 11, 12))
		for k in 6:   # shaft wall rings receding
			M.dline(pg, T, c + Vector3(-lr, -lr + k * 0.4, 0.016), c + Vector3(-lr, lr, 0.016), Color(0.3, 0.32, 0.35, 0.4), Z)
		var prl := M.part(S, 1.5)
		for e in [[Vector3(-lr, -lr, 0), Vector3(lr, -lr, 0)], [Vector3(lr, -lr, 0), Vector3(lr, lr, 0)], [Vector3(lr, lr, 0), Vector3(-lr, lr, 0)], [Vector3(-lr, lr, 0), Vector3(-lr, -lr, 0)]]:
			var a: Vector3 = c + e[0]
			var b: Vector3 = c + e[1]
			for i in 7:
				var p := a.lerp(b, i / 6.0)
				M.dline(prl, T, p, p + Z * 1.0, YEL)
			M.dline(prl, T, a + Z * 1.0, b + Z * 1.0, YEL)
			M.dline(prl, T, a + Z * 0.5, b + Z * 0.5, Color8(170, 140, 40))
		for s: Vector2 in [Vector2(-1, -1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1)]:
			var bp := c + Vector3(s.x * (lr + 0.6), s.y * (lr + 0.6), 0)
			M.cyl(prl, T, bp + Z * 0.5, Z, 0.12, 0.5, 6, rp(STEEL))
			g.lamp(T, bp + Z * 1.1, L_AMB, 9.0, true, prl)
	else:
		quad(pg, T, c + Z * 0.015, X * lr, Y * lr, Color8(98, 100, 104))
		for k in 4:
			M.dline(pg, T, c + Vector3(-lr + (k + 1) * lr * 0.4, -lr, 0.02), c + Vector3(-lr + (k + 1) * lr * 0.4, lr, 0.02), Color(0.2, 0.2, 0.22, 0.6), Z)
	hazard(pg, T, c + Vector3(-lr, -lr, 0.02), c + Vector3(lr, -lr, 0.02), Z, 0.7)
	hazard(pg, T, c + Vector3(lr, -lr, 0.02), c + Vector3(lr, lr, 0.02), Z, 0.7)
	hazard(pg, T, c + Vector3(lr, lr, 0.02), c + Vector3(-lr, lr, 0.02), Z, 0.7)
	hazard(pg, T, c + Vector3(-lr, lr, 0.02), c + Vector3(-lr, -lr, 0.02), Z, 0.7)
	# pad ID block at the edge
	quad(pg, T, c + Vector3(r * 0.78, 0, 0.02), X * 0.6, Y * r * 0.18, accent)
	# perimeter lights
	for k in 12:
		var a := TAU * k / 12.0
		g.lamp(T, c + Vector3(cos(a), sin(a), 0.1) * r * 0.97, L_GRN if k % 3 else L_CYAN, 4.5, true, pg)
	g.pool(T, c, r * 0.9, r * 0.9, Color(0.75, 0.9, 1.0, 0.22))


# =============================================================== DETAIL KIT
static func floodmast(S: Array, T: Dictionary, g, p: Vector3, h := 12.0, aim := Vector3(1, 1, 0)) -> void:
	var pm := M.part(S, 1)
	M.cyl(pm, T, p + Z * h * 0.5, Z, 0.16, h * 0.5, 6, rp(Color8(150, 154, 156)))
	M.box(pm, T, p + Z * (h + 0.2), Vector3(1.0, 0.25, 0.25), rp(DARK))
	for k in 3:
		M.box(pm, T, p + Vector3(-0.6 + k * 0.6, 0.15, h + 0.55), Vector3(0.24, 0.12, 0.22), rp(STEEL))
		g.lamp(T, p + Vector3(-0.6 + k * 0.6, 0.3, h + 0.5), Color(1, 0.97, 0.88, 1.0), 10.0, true, pm)
	g.lamp(T, p + Z * (h + 1.0), L_RED, 4.0, true, pm)
	g.pool(T, p + aim.normalized() * h * 0.9, h * 0.9, h * 0.75, Color(1.0, 0.95, 0.85, 0.5))


static func twall(S: Array, T: Dictionary, a: Vector3, b: Vector3, h := 3.6) -> void:
	var d := b - a
	var n := int(d.length() / 1.25)
	var dir := d.normalized()
	for i in n:
		var pt := M.part(S, 0)
		var c := a + dir * (i * 1.25 + 0.62)
		var hh := Vector3(absf(dir.x) * 0.6 + absf(dir.y) * 0.32, absf(dir.y) * 0.6 + absf(dir.x) * 0.32, h * 0.5)
		M.box(pt, T, c + Z * h * 0.5, hh, rp(CONC), Vector3(0, 0, 0.14))
		M.box(pt, T, c + Z * 0.25, hh + Vector3(absf(dir.y) * 0.4, absf(dir.x) * 0.4, -h * 0.5 + 0.25), rp(P.mul(CONC, 0.85)))


static func vehicle(S: Array, T: Dictionary, g, at: Vector3, yaw: float, kind := "truck") -> void:
	var Tv := M.sub(T, at, yaw)
	var pt := M.part(S, 1)
	var hull: Array = rp(Color8(94, 102, 88))
	if kind == "apc":
		M.box(pt, Tv, Vector3(0, 0, 1.4), Vector3(3.6, 1.5, 0.9), hull, Vector3(0.9, 0.2, 0.3))
		M.box(pt, Tv, Vector3(-0.4, 0, 2.5), Vector3(0.8, 0.7, 0.3), rp(GUN))
		M.cyl(pt, Tv, Vector3(0.9, 0, 2.55), X, 0.08, 0.9, 5, rp(DARK))
		for k in 4:
			for s: float in [-1.4, 1.4]:
				M.cyl(pt, Tv, Vector3(-2.4 + k * 1.6, s, 0.55), Y, 0.55, 0.22, 8, rp(Color8(30, 30, 30)), {"cap_t": 1})
	else:
		M.box(pt, Tv, Vector3(2.6, 0, 1.6), Vector3(1.0, 1.2, 1.0), hull, Vector3(0.4, 0.05, 0.15))
		quad(pt, Tv, Vector3(3.62, 0, 2.0), Y * 0.9, Z * 0.35, Color8(70, 110, 130), X)
		M.box(pt, Tv, Vector3(-1.2, 0, 1.6), Vector3(2.6, 1.2, 1.1), rp(Color8(110, 104, 84)))
		for k in 3:
			for s: float in [-1.15, 1.15]:
				M.cyl(pt, Tv, Vector3(-2.8 + k * 2.6 + (0.6 if k == 2 else 0.0), s, 0.5), Y, 0.5, 0.2, 8, rp(Color8(30, 30, 30)), {"cap_t": 1})
	g.lamp(Tv, Vector3(3.7 if kind != "apc" else 3.7, 0.8, 1.2), Color(1, 0.95, 0.8, 0.8), 5.0)


# =============================================================== SPRITES (the game's own sheets)
static func _sheet(group: String, id: String) -> Dictionary:
	var key := group + "/" + id
	if _sheets.has(key):
		return _sheets[key]
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/%s/manifest.json" % group))
	var e: Dictionary = {}
	for sec in ["vehicles", "infantry"]:
		if (man.get(sec, {}) as Dictionary).has(id):
			e = man[sec][id]
	var r := {}
	if not e.is_empty():
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/art/%s/%s" % [group, String(e.file)]))
		img.convert(Image.FORMAT_RGBA8)
		var msk: Image = null
		if e.has("mask"):
			msk = Image.load_from_file(ProjectSettings.globalize_path("res://assets/art/%s/%s" % [group, String(e.mask)]))
			msk.convert(Image.FORMAT_RGBA8)
		r = {"img": img, "mask": msk, "fw": int(e.fw), "fh": int(e.fh), "pivot": Vector2(e.pivot[0], e.pivot[1]), "frames": e.frames}
	_sheets[key] = r
	return r


static func spec(S: Array, T: Dictionary, group: String, id: String, frame: String, k: int, w: Vector3, team: Color, dim := 1.0) -> void:
	var sh := _sheet(group, id)
	if sh.is_empty():
		push_warning("BG2 sheet missing %s/%s" % [group, id])
		return
	var col: int = maxi(0, (sh.frames as Array).find(frame))
	var fw: int = sh.fw
	var fh: int = sh.fh
	var cell: Image = (sh.img as Image).get_region(Rect2i(col * fw, k * fh, fw, fh))
	var mc: Image = (sh.mask as Image).get_region(Rect2i(col * fw, k * fh, fw, fh)) if sh.mask != null else null
	var piv: Vector2 = sh.pivot
	var o: Vector2 = T.o
	var ww := M.wm(T, w)
	M.sprite(S, ww, func(cv):
		var at := M.scr_w(o, ww) - piv
		for y in fh:
			for x in fw:
				var c := cell.get_pixel(x, y)
				if c.a <= 0.0:
					continue
				if mc != null and mc.get_pixel(x, y).a > 0.0:
					var kk := 0.45 + c.r * 0.9
					c = Color(team.r * kk, team.g * kk, team.b * kk, c.a)
				if dim != 1.0:
					c = Color(c.r * dim, c.g * dim, c.b * dim, c.a)
				cv.px(int(at.x) + x, int(at.y) + y, c), 1.0)


static func emp_grid(pt: Dictionary, T: Dictionary, x0: float, y0: float, x1: float, y1: float, z := 0.08) -> void:
	quad(pt, T, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z - 0.01), X * (x1 - x0) * 0.5, Y * (y1 - y0) * 0.5, Color8(40, 48, 60))
	for i in range(0, int((x1 - x0) / 0.8) + 1):
		M.dline(pt, T, Vector3(x0 + i * 0.8, y0, z), Vector3(x0 + i * 0.8, y1, z), Color(0.45, 0.8, 1.0, 0.75), Z)
	for i in range(0, int((y1 - y0) / 0.8) + 1):
		M.dline(pt, T, Vector3(x0, y0 + i * 0.8, z), Vector3(x1, y0 + i * 0.8, z), Color(0.45, 0.8, 1.0, 0.75), Z)


static func clamp_pad(pt: Dictionary, T: Dictionary, p: Vector3) -> void:
	M.box(pt, T, p + Z * 0.3, Vector3(0.45, 0.45, 0.3), rp(YEL), Vector3(0.1, 0.1, 0.1))
	M.box(pt, T, p + Z * 0.75, Vector3(0.25, 0.25, 0.15), rp(DARK))


static func foam(pt: Dictionary, T: Dictionary, p: Vector3, r: float) -> void:
	M.cyl(pt, T, p, Z, r, r * 0.6, 8, rp(Color8(236, 234, 222)), {"cap_t": 4})


static func railing(pt: Dictionary, T: Dictionary, a: Vector3, b: Vector3, h := 1.0, col := Color8(226, 190, 60)) -> void:
	var n := int(a.distance_to(b) / 1.2) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		M.dline(pt, T, p, p + Z * h, P.mul(col, 0.85))
	M.dline(pt, T, a + Z * h, b + Z * h, col)
	M.dline(pt, T, a + Z * h * 0.5, b + Z * h * 0.5, P.mul(col, 0.7))
