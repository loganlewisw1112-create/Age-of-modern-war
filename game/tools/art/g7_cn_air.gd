extends RefCounted
## DL7 sample dropships (owner: ARTCN7; G7_REFERENCE 6.9, 6.12):
##   g7_cn_stealth_dropship  counter-nanite stealth strike dropship: faceted blended wedge, no rotors, buried
##                           stealth engines with flat exhaust slits, 4 VTOL nozzles; internal bay (one APC).
##   g7_a_vtol_dropship_xl   the enlarged regular Human A VTOL dropship (4 ducted fans), same internal bay.
## Frames: hover, fly, descend, landed, ramp_open (empty bay), apc_in (strike APC parked inside), takeoff (dust
## ring), drones (5 defence drones launching). The ground shadow is drawn in-frame under the craft.
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")
const V = preload("res://tools/art/g7_cn_vehicles.gd")

const FRAMES := ["hover", "fly", "descend", "landed", "ramp_open", "apc_in", "takeoff", "drones"]
const STEALTH := Color8(62, 68, 76)
const VTOL := Color8(104, 112, 84)
const NOZ := Color8(255, 170, 90)
const NOZ_HOT := Color8(255, 236, 190)
const BAY := Color8(30, 32, 34)
const BAY_LIT := Color8(250, 214, 140)
const DUST := Color(0.58, 0.52, 0.42, 0.30)
const ALT := {"hover": 16.0, "fly": 20.0, "descend": 8.0, "landed": 0.0, "ramp_open": 0.0, "apc_in": 0.0,
	"takeoff": 5.0, "drones": 18.0}


## Prism from a local outline (u, v tiles, counter-clockwise from the nose) between z0 and z1, faceted top.
static func prism(cv, o: Vector2, a: float, pts: Array, z0: float, z1: float, rp: Array, ridge := 2.0) -> void:
	var n := pts.size()
	var cen := Vector2.ZERO
	for p in pts:
		cen += p / float(n)
	for i in n:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % n]
		var e := p1 - p0
		var nloc := Vector2(e.y, -e.x)
		if nloc.dot((p0 + p1) * 0.5 - cen) < 0.0:
			nloc = -nloc
		var nl := V.lw(a, nloc.x, nloc.y)
		if nl.x + nl.y <= 0.001:
			continue
		var q := PackedVector2Array([V.lp(o, a, p0.x, p0.y, z0), V.lp(o, a, p1.x, p1.y, z0),
			V.lp(o, a, p1.x, p1.y, z1), V.lp(o, a, p0.x, p0.y, z1)])
		var sn := Vector2(nl.x - nl.y, (nl.x + nl.y) * 0.5)
		C.face(cv, q, rp, clampi(C.lit_index(sn), 1, 2))
	# faceted top: one facet per outline edge, fanned to a raised centre ridge; each facet shaded by its slope
	var top := PackedVector2Array()
	for p in pts:
		top.append(V.lp(o, a, p.x, p.y, z1))
	C.face(cv, top, rp, 2)
	for i in n:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % n]
		var rc := Vector2((p0.x + p1.x) * 0.5, 0.0)
		var tri := PackedVector2Array([V.lp(o, a, p0.x, p0.y, z1), V.lp(o, a, p1.x, p1.y, z1),
			V.lp(o, a, rc.x * 0.6, 0.0, z1 + ridge)])
		var mid := (p0 + p1) * 0.5
		var nw := V.lw(a, mid.x - rc.x * 0.6, mid.y)
		var sn := Vector2(nw.x - nw.y, (nw.x + nw.y) * 0.5 - 1.2)
		var t := 3 if sn.normalized().dot(Vector2(-0.78, -0.62)) > 0.15 else 2
		if sn.normalized().dot(Vector2(-0.78, -0.62)) < -0.55:
			t = 1
		C.face(cv, tri, rp, t, t == 3)
		cv.line_v(tri[0], tri[2], rp[1])


static func craft(cv, k: int, fname: String, o: Vector2, stealth: bool) -> void:
	var a := k * PI / 4.0
	var alt: float = ALT[fname]
	var hull: Color = STEALTH if stealth else VTOL
	var rp := C.ramp(hull)
	var sh := o + Vector2(alt * 0.5, 0)
	cv.ellipse(sh.x, sh.y + 2, 46.0, 18.0, Color(0.03, 0.04, 0.03, 0.30))
	if fname == "takeoff" or fname == "descend":
		for i in 18:
			var t := TAU * i / 18.0
			cv.ellipse(o.x + cos(t) * 50.0, o.y + sin(t) * 20.0, 3.5, 2.0, DUST)
	var b := o + Vector2(0, -alt)
	var z0 := 4.0
	var outline: Array
	if stealth:
		outline = [Vector2(1.45, 0), Vector2(0.6, -0.5), Vector2(-0.2, -1.0), Vector2(-1.05, -0.62),
			Vector2(-0.85, -0.3), Vector2(-1.2, 0), Vector2(-0.85, 0.3), Vector2(-1.05, 0.62), Vector2(-0.2, 1.0),
			Vector2(0.6, 0.5)]
	else:
		outline = [Vector2(1.35, 0), Vector2(1.1, -0.36), Vector2(-1.15, -0.4), Vector2(-1.3, -0.2),
			Vector2(-1.3, 0.2), Vector2(-1.15, 0.4), Vector2(1.1, 0.36)]
	var on_ground := alt == 0.0
	if on_ground:   # landing gear struts
		for g in [Vector2(0.7, 0), Vector2(-0.6, -0.35), Vector2(-0.6, 0.35)]:
			cv.line_v(V.lp(b, a, g.x, g.y, 0.0), V.lp(b, a, g.x, g.y, z0), V.DARK)
	var ramp_on := fname == "ramp_open" or fname == "apc_in"
	var tail_near := C.depth(a, -1.0, 0.0) > 0.0
	if ramp_on and not tail_near:
		_ramp(cv, b, a, z0, fname == "apc_in", stealth)
	var top := z0 + (13.0 if stealth else 15.0)
	if stealth:
		prism(cv, b, a, outline, z0 + 4.0, z0 + 8.0, rp, 2.0)
		var fus := [Vector2(1.45, 0), Vector2(0.7, -0.3), Vector2(-0.95, -0.36), Vector2(-1.1, 0), Vector2(-0.95, 0.36),
			Vector2(0.7, 0.3)]
		var near_s := 1.0 if C.depth(a, 0.0, 1.0) > 0.0 else -1.0
		for sd in [-near_s, 0.0, near_s]:   # far engine hump, fuselage, near engine hump
			if sd == 0.0:
				prism(cv, b, a, fus, z0, top, rp, 3.0)
				continue
			var hump := [Vector2(0.1, sd * 0.38), Vector2(-0.3, sd * 0.62), Vector2(-0.9, sd * 0.6), Vector2(-0.9, sd * 0.36)]
			prism(cv, b, a, hump, z0 + 8.0, top - 2.0, C.ramp(P.mul(hull, 0.92)), 1.5)
	else:
		prism(cv, b, a, outline, z0, top, rp, 1.5)
		for u in [0.55, -0.6]:   # high fan wings carrying the 4 ducted fans
			V.vbox(cv, b, a, u, 0.0, top - 3.0, 0.11, 0.8, 3.0, C.ramp(P.mul(hull, 0.9)), 3)
		for sd in [-1.0, 1.0]:   # side door frames + hazard band
			if C.depth(a, 0.0, sd) > 0.0:
				var d0 := V.lp(b, a, 0.15, sd * 0.4, z0 + 2.0)
				var d1 := V.lp(b, a, -0.35, sd * 0.4, z0 + 2.0)
				cv.line_v(d0, d0 + Vector2(0, -9), V.DARK)
				cv.line_v(d1, d1 + Vector2(0, -9), V.DARK)
				cv.line_v(V.lp(b, a, 1.0, sd * 0.36, z0 + 11.0), V.lp(b, a, -1.1, sd * 0.4, z0 + 11.0), Color8(176, 168, 120))
	if ramp_on and tail_near:
		_ramp(cv, b, a, z0, fname == "apc_in", stealth)
	if stealth:
		var ck := V.lp(b, a, 0.95, 0.0, top + 1.0)
		cv.line_v(ck + C.sdir(a + PI / 2) * 2.5, ck - C.sdir(a + PI / 2) * 2.5, Color8(40, 60, 70))
		cv.line_v(ck + C.sdir(a + PI / 2) * 2.0 + Vector2(0, -1), ck - C.sdir(a + PI / 2) * 2.0 + Vector2(0, -1), Color8(150, 190, 200))
		for s in [-1.0, 1.0]:   # buried engines: flat exhaust slits near the tail
			var e0 := V.lp(b, a, -0.95, s * 0.28, top - 1.0)
			var e1 := V.lp(b, a, -0.95, s * 0.52, top - 1.0)
			cv.line_v(e0, e1, BAY)
			if not on_ground:
				cv.line_v(e0 + Vector2(0, 1), e1 + Vector2(0, 1), Color(NOZ, 0.6))
	else:
		var ck := V.lp(b, a, 1.12, 0.0, top - 4.0)
		cv.line_v(ck + C.sdir(a + PI / 2) * 3.0, ck - C.sdir(a + PI / 2) * 3.0, Color8(140, 186, 200))
	# team ID panel on the spine
	var w := V.lw(a, -0.2, 0.0)
	C.box(cv, b, Vector3(w.x, w.y, top + 1.0), 0.18, 0.12, 0.5, a, C.ramp(Color8(150, 150, 150)), 3, false, true)
	# VTOL nozzles (stealth) or ducted fans (regular)
	var lift: Array = [Vector2(0.55, -0.62), Vector2(0.55, 0.62), Vector2(-0.6, -0.72), Vector2(-0.6, 0.72)]
	for q in lift:
		var c := V.lp(b, a, q.x * (1.0 if stealth else 1.0), q.y * (1.0 if stealth else 1.12), top - (2.0 if stealth else -0.5))
		if stealth:
			C.blob(cv, c, 2.2, C.ramp(Color8(50, 54, 60)))
			if not on_ground:
				C.blob(cv, c + Vector2(0, 1), 1.2, [NOZ, NOZ, NOZ_HOT, NOZ_HOT, NOZ_HOT])
		else:
			cv.ellipse(c.x, c.y + 1, 7.5, 4.0, C.ramp(Color8(60, 64, 56))[0])
			cv.ellipse(c.x, c.y, 7.0, 3.6, C.ramp(Color8(60, 64, 56))[2])
			var spin := Color(0.85, 0.85, 0.80, 0.35 if not on_ground else 0.0)
			cv.ellipse(c.x, c.y, 5.6, 2.6, spin if not on_ground else C.ramp(Color8(60, 64, 56))[0])
			cv.line_v(c + Vector2(-5, 0), c + Vector2(5, 0), Color(0.2, 0.2, 0.2, 0.7) if on_ground else Color(1, 1, 1, 0.25))
	if fname == "drones":
		for i in 5:
			var dp := b + Vector2(-34 + i * 17, -20 - (i % 2) * 7)
			C.blob(cv, dp, 1.8, C.ramp(Color8(70, 74, 78) if i < 3 else Color8(96, 100, 84)))
			cv.line_v(dp + Vector2(-3, -1), dp + Vector2(3, -1), V.DARK)
			if i >= 3:
				cv.px(int(dp.x) + 2, int(dp.y) + 1, GR.FLASH)


## Rear ramp lowered to the ground with the lit bay; apc_in shows the strike APC's nose inside.
static func _ramp(cv, b: Vector2, a: float, z0: float, apc: bool, stealth: bool) -> void:
	var tail := -1.2 if stealth else -1.3
	var r := PackedVector2Array([V.lp(b, a, tail + 0.05, -0.28, z0 + 1.0), V.lp(b, a, tail + 0.05, 0.28, z0 + 1.0),
		V.lp(b, a, tail - 0.55, 0.28, 0.0), V.lp(b, a, tail - 0.55, -0.28, 0.0)])
	C.face(cv, r, C.ramp(Color8(96, 98, 92)), 3, true)
	for i in 4:
		var t := 0.2 + i * 0.2
		cv.line_v(r[0].lerp(r[3], t), r[1].lerp(r[2], t), C.ramp(Color8(96, 98, 92))[1])
	if C.depth(a, -1.0, 0.0) > 0.0:
		var m := V.lp(b, a, tail, 0.0, z0 + 6.0)
		cv.rect(int(m.x) - 6, int(m.y) - 6, 13, 10, BAY)
		cv.rect(int(m.x) - 5, int(m.y) - 6, 11, 1, BAY_LIT)
		if apc:
			cv.rect(int(m.x) - 5, int(m.y) - 3, 11, 7, C.ramp(V.HULL_CN)[1])
			cv.px(int(m.x) - 3, int(m.y), Color8(255, 246, 210))
			cv.px(int(m.x) + 3, int(m.y), Color8(255, 246, 210))
			for i in 4:
				cv.px(int(m.x) - 3 + i * 2, int(m.y) + 2, GR.HAZ if i % 2 == 0 else GR.HAZ_D)


static func build(out: Dictionary) -> void:
	var strip := ["hover", "fly", "descend", "landed", "ramp_open", "apc_in", "takeoff", "hover", "fly", "drones"]
	C.unit_sheet(out, "g7_cn_stealth_dropship", "vehicles", "air", 144, 108, Vector2i(72, 82), FRAMES,
		func(cv, k, f, o): craft(cv, k, f, o, true),
		{"sample": "air", "line": "strike_team", "bay": "1 vehicle <= strike APC + occupants + 1 squad",
		"key_frames": FRAMES.duplicate(), "anim_strip": strip, "altitude_px": ALT})
	C.unit_sheet(out, "g7_a_vtol_dropship_xl", "vehicles", "air", 144, 108, Vector2i(72, 82), FRAMES,
		func(cv, k, f, o): craft(cv, k, f, o, false),
		{"sample": "air", "line": "human_a", "upgrades": "a_vtol_dropship", "bay": "1 vehicle + occupants + 1 squad",
		"key_frames": FRAMES.duplicate(), "anim_strip": strip, "altitude_px": ALT})
