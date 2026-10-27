extends RefCounted
## DL7 sample vehicles (owner: ARTCN7; G7_REFERENCE 6.5, 6.6, 6.12):
##   g7_cn_strike_apc  strike-team APC, larger than a regular APC: 8 wheels, front + rear shielded manned .50
##                     mounts with gunners, side pop-out panels (interceptors / smoke / drones), shield dome
##                     emitter, rear doors. No main weapon.
##   g7_op_tactical_apc tactical operator APC: 8 seats, roof remote-operated twin .50, same defences.
## 8 facings; frames are the key states. Team mask: roof ID panel + side chevrons.
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")

const HULL_CN := Color8(150, 150, 136)
const HULL_OP := Color8(78, 86, 74)
const DARK := Color8(46, 50, 54)
const TIRE := Color8(34, 35, 36)
const GLASS := Color8(110, 150, 170)
const DOME := Color(0.62, 0.84, 1.0, 0.26)
const DOME_RIM := Color(0.80, 0.94, 1.0, 0.75)
const DUST := Color(0.55, 0.50, 0.40, 0.35)
const STRIKE_FRAMES := ["idle", "move_0", "move_1", "fire_f", "fire_r", "traverse", "panels_open", "launch",
	"dome", "doors_open"]
const TAC_FRAMES := ["idle", "move_0", "move_1", "fire", "traverse", "panels_open", "dome", "doors_open"]


## Local (u forward, v right) tiles -> world tile offset at yaw a.
static func lw(a: float, u: float, v: float) -> Vector2:
	return Vector2(cos(a) * u - sin(a) * v, sin(a) * u + cos(a) * v)


static func lp(o: Vector2, a: float, u: float, v: float, z: float) -> Vector2:
	var w := lw(a, u, v)
	return P.proj(o, Vector3(w.x, w.y, z))


static func vbox(cv, o: Vector2, a: float, u: float, v: float, z: float, hx: float, hy: float, hz: float,
		rp: Array, top_t := 3, team_top := false) -> Dictionary:
	var w := lw(a, u, v)
	return C.box(cv, o, Vector3(w.x, w.y, z), hx, hy, hz, a, rp, top_t, true, team_top)


static func _wheels(cv, o: Vector2, a: float, hx: float, hy: float, n: int, near: bool, spin: int) -> void:
	for s in [-1.0, 1.0]:
		var is_near := C.depth(a, 0.0, s) > 0.0
		if is_near != near:
			continue
		for i in n:
			var u := -hx * 0.78 + (hx * 1.56) * float(i) / float(n - 1)
			var c := lp(o, a, u, s * (hy + 0.02), 4.0)
			cv.ellipse(c.x, c.y, 3.2, 3.4, TIRE)
			var hub := C.ramp(Color8(96, 100, 96))
			cv.px(int(c.x), int(c.y), hub[3])
			cv.px(int(c.x) + (1 if spin == 0 else 0), int(c.y) + (0 if spin == 0 else 1), hub[1])


## A .50 mount at local (u, v, z): ring, gun(s) along yaw a + yaw_off; shielded (with gunner) or remote twin.
static func mount(cv, o: Vector2, a: float, u: float, v: float, z: float, yaw_off: float, shielded: bool,
		team_hull: Color, flash: bool) -> void:
	var b := a + yaw_off
	var base := lp(o, a, u, v, z)
	var w := lw(a, u, v)
	vbox(cv, o, a, u, v, z, 0.14, 0.14, 2.5, C.ramp(DARK))
	var parts: Array = []
	var gun0 := Vector2(w.x, w.y)
	var fwd := Vector2(cos(b), sin(b))
	var side := Vector2(-sin(b), cos(b))
	if shielded:
		parts.append([C.depth(b, 0.06, 0.0), "shield"])
		parts.append([C.depth(b, -0.10, 0.0), "gunner"])
	else:
		parts.append([C.depth(b, 0.0, 0.0), "rws"])
	parts.append([C.depth(b, 0.24, 0.0), "gun"])
	parts.sort_custom(func(x, y): return x[0] < y[0])
	for q in parts:
		match String(q[1]):
			"shield":
				var sc := gun0 + fwd * 0.08
				C.box(cv, o, Vector3(sc.x, sc.y, z + 2.0), 0.035, 0.2, 8.0, b, C.ramp(P.mul(team_hull, 0.9)), 3, true)
			"gunner":
				var g := gun0 - fwd * 0.10
				var gp := P.proj(o, Vector3(g.x, g.y, z + 7.5))
				C.blob(cv, gp + Vector2(0, 2), 2.0, C.ramp(Color8(170, 168, 152)))
				C.blob(cv, gp + Vector2(0, -1), 1.7, C.ramp(Color8(84, 92, 98)))
				cv.px(int(gp.x + C.sdir(b).x * 1.5), int(gp.y - 1 + C.sdir(b).y * 1.5), Color8(246, 178, 60))
			"rws":
				C.box(cv, o, Vector3(gun0.x, gun0.y, z + 2.0), 0.09, 0.08, 4.0, b, C.ramp(Color8(70, 76, 70)), 3, true)
				var sn := P.proj(o, Vector3(gun0.x, gun0.y, z + 6.5))
				cv.px(int(sn.x), int(sn.y), Color8(120, 220, 255))
			"gun":
				for k in ([-0.03, 0.03] if not shielded else [0.0]):
					var g0 := gun0 + side * float(k)
					var g1 := g0 + fwd * 0.46
					var p0 := P.proj(o, Vector3(g0.x, g0.y, z + 4.5))
					var p1 := P.proj(o, Vector3(g1.x, g1.y, z + 4.5))
					C.tube(cv, p0, p1, 0.75, C.ramp(GR.GUNM))
					C.blob(cv, p0, 1.3, C.ramp(GR.METAL))
					if flash:
						var d := (p1 - p0).normalized() if p1.distance_to(p0) > 0.5 else Vector2(0, 1)
						C.blob(cv, p1 + d * 1.8, 1.4, [GR.FLASH_O, GR.FLASH_O, GR.FLASH, GR.FLASH, GR.FLASH])
						cv.line_v(p1 + d * 1.5, p1 + d * 4.0, GR.FLASH)


## Side pop-out panels: closed = flush panel seams; open = flaps hinged up showing launcher tubes.
static func panels(cv, o: Vector2, a: float, hx: float, hy: float, z: float, open: bool, launch: bool) -> void:
	for s in [-1.0, 1.0]:
		if C.depth(a, 0.0, s) <= 0.0:
			continue
		for i in 2:
			var u := -hx * 0.25 + i * hx * 0.42
			if open:
				vbox(cv, o, a, u, s * (hy + 0.06), z + 2.0, 0.16, 0.02, 6.0, C.ramp(Color8(64, 68, 70)))
				for t in 3:
					var tp := lp(o, a, u - 0.1 + t * 0.1, s * (hy + 0.04), z + 5.0)
					cv.px(int(tp.x), int(tp.y), TIRE)
					cv.px(int(tp.x), int(tp.y) - 1, Color8(220, 120, 60) if t == 1 else DARK)
				if launch and i == 0:
					var dp := lp(o, a, u, s * (hy + 0.55), z + 18.0)
					C.blob(cv, dp, 1.6, C.ramp(Color8(70, 74, 78)))
					cv.line_v(dp + Vector2(-3, 0), dp + Vector2(3, 0), DARK)
					cv.ellipse(dp.x, dp.y + 5, 1.2, 2.0, Color(0.85, 0.85, 0.8, 0.35))
			else:
				var a0 := lp(o, a, u - 0.16, s * (hy + 0.005), z + 3.0)
				var a1 := lp(o, a, u + 0.16, s * (hy + 0.005), z + 3.0)
				cv.line_v(a0, a1, C.ramp(DARK)[1])


static func dome(cv, c: Vector2, rx: float, ry: float) -> void:
	cv.ellipse(c.x, c.y, rx, ry, DOME)
	for i in 48:
		var t := TAU * i / 48.0
		if sin(t) < 0.2:
			cv.px(int(c.x + cos(t) * rx), int(c.y + sin(t) * ry), DOME_RIM)
	for i in 3:
		cv.px(int(c.x - rx * 0.4 + i), int(c.y - ry * 0.7 + i), Color(1, 1, 1, 0.8))


## Shared hull for both APCs. big = strike APC.
static func apc(cv, k: int, fname: String, o: Vector2, big: bool) -> void:
	var a := k * PI / 4.0
	var hx := 0.95 if big else 0.74
	var hy := 0.40 if big else 0.34
	var hull: Color = HULL_CN if big else HULL_OP
	var rp := C.ramp(hull)
	var mv := fname.begins_with("move")
	var spin := 1 if fname == "move_1" else 0
	C.ground_shadow(cv, o + Vector2(2, 3), 40.0 if big else 31.0, 15.0 if big else 12.0, 0.32)
	if mv:
		var dp := lp(o, a, -hx - 0.25, 0.0, 2.0)
		cv.ellipse(dp.x, dp.y, 5.0 + spin * 2, 3.0 + spin, DUST)
	_wheels(cv, o, a, hx, hy, 4, false, spin)
	vbox(cv, o, a, 0.0, 0.0, 3.0, hx, hy, 9.0, rp, 2)
	vbox(cv, o, a, -0.04, 0.0, 12.0, hx - 0.10, hy - 0.06, 3.0, rp, 2)
	vbox(cv, o, a, -0.08, 0.0, 15.0, hx - 0.18, hy - 0.11, 4.0 if big else 3.0, rp, 3)
	vbox(cv, o, a, hx - 0.10, 0.0, 12.0, 0.10, hy - 0.08, 3.0, rp, 3)   # sloped glacis lip
	_detail(cv, o, a, hx, hy, big)
	var gl := lp(o, a, hx - 0.05, 0.0, 14.0)
	if C.depth(a, 1.0, 0.0) > -0.2:
		cv.line_v(gl + C.sdir(a + PI / 2) * 4.0, gl - C.sdir(a + PI / 2) * 4.0, GLASS)
	var roof := 19.0 if big else 18.0
	vbox(cv, o, a, -0.15, 0.0, roof, 0.22, 0.14, 0.6, rp, 3, true)    # roof ID panel (team)
	for s in [-1.0, 1.0]:   # side chevrons (team)
		if C.depth(a, 0.0, s) > 0.0:
			var c0 := lp(o, a, hx * 0.55, s * (hy + 0.005), 8.0)
			cv.team = true
			cv.line_v(c0, c0 + Vector2(2, -2), Color8(150, 150, 150))
			cv.line_v(c0 + Vector2(2, -2), c0 + Vector2(4, 0), Color8(150, 150, 150))
			cv.team = false
	if big:   # dome emitter mast + EW pod + low-signature exhaust shroud
		vbox(cv, o, a, 0.12, 0.0, roof, 0.05, 0.05, 5.0, C.ramp(DARK))
		var em := lp(o, a, 0.12, 0.0, roof + 5.5)
		C.blob(cv, em, 1.4, C.ramp(Color8(150, 200, 230)))
	vbox(cv, o, a, -hx + 0.08, hy * 0.5, roof - 1.0, 0.06, 0.07, 1.5, C.ramp(DARK))
	panels(cv, o, a, hx, hy, 4.0, fname == "panels_open" or fname == "launch", fname == "launch")
	if fname == "doors_open":
		vbox(cv, o, a, -hx - 0.22, 0.0, 0.5, 0.2, hy - 0.1, 1.5, C.ramp(Color8(96, 98, 92)), 3)
		var dr := lp(o, a, -hx, 0.0, 9.0)
		cv.rect(int(dr.x) - 2, int(dr.y) - 4, 5, 6, Color8(24, 26, 28))
	_wheels(cv, o, a, hx, hy, 4, true, spin)
	for s in [-1.0, 1.0]:   # armoured skirts over the wheel tops
		if C.depth(a, 0.0, s) > 0.0:
			vbox(cv, o, a, 0.0, s * (hy + 0.03), 5.5, hx - 0.06, 0.025, 4.0, C.ramp(P.mul(hull, 0.82)), 2)
	var trav := 0.9 if fname == "traverse" else 0.0
	var mounts: Array = [[hx * 0.55, -0.0, false]] if not big else [[hx * 0.62, 0.0, false], [-hx * 0.62, 0.0, true]]
	if not big:
		mounts = [[0.2, 0.0, false]]
	mounts.sort_custom(func(x, y): return C.depth(a, x[0], x[1]) < C.depth(a, y[0], y[1]))
	for m in mounts:
		var rear: bool = m[2]
		var yo: float = (PI if rear else 0.0) + (trav if not rear else -trav)
		var fl := (fname == "fire_f" and not rear) or (fname == "fire_r" and rear) or fname == "fire"
		mount(cv, o, a, m[0], m[1], roof, yo, big, hull, fl)
	if fname == "dome":
		dome(cv, o + Vector2(0, -10), 46.0 if big else 38.0, 30.0 if big else 25.0)


static func build(out: Dictionary) -> void:
	C.unit_sheet(out, "g7_cn_strike_apc", "vehicles", "vehicle", 112, 86, Vector2i(56, 56), STRIKE_FRAMES,
		func(cv, k, f, o): apc(cv, k, f, o, true),
		{"sample": "vehicle", "line": "strike_team", "capacity": "10 + packages (PROVISIONAL)",
		"key_frames": STRIKE_FRAMES.duplicate(), "anim_strip": ["idle", "move_0", "move_1", "traverse", "fire_f",
		"fire_r", "panels_open", "launch", "dome", "doors_open"]})
	C.unit_sheet(out, "g7_op_tactical_apc", "vehicles", "vehicle", 104, 84, Vector2i(52, 54), TAC_FRAMES,
		func(cv, k, f, o): apc(cv, k, f, o, false),
		{"sample": "vehicle", "line": "operators", "capacity": 8, "key_frames": TAC_FRAMES.duplicate(),
		"anim_strip": ["idle", "move_0", "move_1", "traverse", "fire", "fire", "panels_open", "dome", "doors_open", "idle"]})


## Panel seams, stowage, front hazard strip, rear light bar on the visible faces.
static func _detail(cv, o: Vector2, a: float, hx: float, hy: float, big: bool) -> void:
	var seam: Color = C.ramp(DARK)[2]
	seam.a = 0.55
	for s in [-1.0, 1.0]:
		if C.depth(a, 0.0, s) <= 0.0:
			continue
		var n := 5 if big else 4
		for i in n + 1:
			var u := -hx + 0.04 + (2.0 * hx - 0.08) * float(i) / float(n)
			cv.line_v(lp(o, a, u, s * (hy + 0.004), 4.0), lp(o, a, u, s * (hy + 0.004), 11.5), seam)
		cv.line_v(lp(o, a, -hx + 0.04, s * (hy + 0.004), 10.5), lp(o, a, hx - 0.04, s * (hy + 0.004), 10.5), seam)
		vbox(cv, o, a, -hx * 0.55, s * (hy - 0.02), 12.0, 0.16, 0.05, 2.5, C.ramp(Color8(96, 98, 86)), 3)
	if C.depth(a, 1.0, 0.0) > 0.0:
		for i in 8:
			var v := -hy + 0.05 + (2.0 * hy - 0.1) * float(i) / 7.0
			cv.px(int(lp(o, a, hx + 0.004, v, 6.0).x), int(lp(o, a, hx + 0.004, v, 6.0).y), GR.HAZ if i % 2 == 0 else GR.HAZ_D)
			cv.px(int(lp(o, a, hx + 0.004, v, 7.0).x), int(lp(o, a, hx + 0.004, v, 7.0).y), GR.HAZ_D if i % 2 == 0 else GR.HAZ)
		for s in [-1.0, 1.0]:
			var hl := lp(o, a, hx + 0.004, s * (hy - 0.08), 9.5)
			cv.px(int(hl.x), int(hl.y), Color8(255, 246, 210))
	if C.depth(a, -1.0, 0.0) > 0.0:
		for s in [-1.0, 1.0]:
			var tl := lp(o, a, -hx - 0.004, s * (hy - 0.08), 9.5)
			cv.px(int(tl.x), int(tl.y), Color8(220, 60, 50))
