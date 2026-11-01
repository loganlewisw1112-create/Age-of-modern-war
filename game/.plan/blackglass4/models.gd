extends RefCounted
## Site Blackglass aircraft models (mockup art, metres, local +x = nose, z = 0 = the surface the gear stands on).
##   attack_heli   stealth attack helicopter, Apache class: 17.2 m over rotor + tail, 14.6 m rotor, tandem cockpit, stub wings
##   hauler        quad-rotor heavy hauler, modernised Russian heavy-lift style: 26 m hull, four 11 m rotors on outriggers
##   medevac_drone medium casualty-evacuation drone: stretcher capsule, four ducted rotors, skids

const M = preload("res://tools/art/g7_cn_mesh.gd")
const L = preload("res://.plan/blackglass4/lib.gd")


static func _blades(pt: Dictionary, T: Dictionary, c: Vector3, r: float, n: int, phase: float, col: Array, chord := 0.32) -> void:
	for k in n:
		var a := phase + TAU * k / n
		var d := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-d.y, d.x, 0)
		M.face(pt, T, [c + side * chord, c + d * r + side * chord * 0.7, c + d * r - side * chord * 0.7, c - side * chord], c - L.Z, col)
	M.cyl(pt, T, c, L.Z, 0.45, 0.25, 8, L.rp(L.DARK))


## Stealth attack helicopter (landed on its wheels).
static func attack_heli(S: Array, T: Dictionary, g, at: Vector3, yaw: float) -> void:
	var Tc := M.sub(T, at, yaw)
	var hull: Array = L.rp(Color8(54, 58, 64))
	var dk: Array = L.rp(Color8(34, 36, 40))
	var pt := M.part(S, 2)
	# gear: two mains + tail wheel (bottoms at z 0)
	for s: float in [-1.25, 1.25]:
		M.cyl(pt, Tc, Vector3(2.4, s, 0.42), L.Y, 0.42, 0.14, 10, L.rp(Color8(28, 28, 28)), {"cap_t": 1})
		M.dline(pt, Tc, Vector3(2.4, s, 0.42), Vector3(2.2, s * 0.6, 1.2), Color8(70, 74, 78))
	M.cyl(pt, Tc, Vector3(-6.9, 0, 0.28), L.Y, 0.28, 0.1, 8, L.rp(Color8(28, 28, 28)), {"cap_t": 1})
	# faceted fuselage + tandem cockpit (gunner low in front, pilot raised behind)
	M.box(pt, Tc, Vector3(1.6, 0, 1.95), Vector3(3.4, 0.95, 0.85), hull, Vector3(0.6, 0.35, 0.35))
	M.box(pt, Tc, Vector3(5.2, 0, 1.75), Vector3(1.0, 0.7, 0.6), hull, Vector3(0.6, 0.3, 0.3))
	M.box(pt, Tc, Vector3(4.4, 0, 2.75), Vector3(0.75, 0.62, 0.35), L.rp(Color8(70, 110, 130)), Vector3(0.4, 0.25, 0.2))
	M.box(pt, Tc, Vector3(2.9, 0, 3.15), Vector3(0.8, 0.62, 0.42), L.rp(Color8(70, 110, 130)), Vector3(0.45, 0.25, 0.2))
	M.cyl(pt, Tc, Vector3(6.3, 0, 1.45), L.X, 0.42, 0.3, 10, L.rp(Color8(40, 44, 48)))   # nose sensor turret
	L.quad(pt, Tc, Vector3(6.62, 0, 1.45), L.Y * 0.22, L.Z * 0.18, Color8(200, 60, 50), L.X)
	M.box(pt, Tc, Vector3(4.6, 0, 0.75), Vector3(0.35, 0.35, 0.3), dk)                     # chin gun
	M.cyl(pt, Tc, Vector3(5.6, 0, 0.7), L.X, 0.07, 1.1, 5, dk, {"edge": false})
	for s: float in [-1.0, 1.0]:                                                            # engines + exhaust shields
		M.cyl(pt, Tc, Vector3(0.6, s * 1.2, 2.75), L.X, 0.48, 1.4, 10, hull)
		M.box(pt, Tc, Vector3(-1.1, s * 1.35, 2.85), Vector3(0.5, 0.25, 0.35), dk)
		M.box(pt, Tc, Vector3(1.3, s * 1.9, 1.85), Vector3(0.7, 0.9, 0.1), hull)            # stub wing
		for k in 2:                                                                          # rocket pod + missile rack
			var wy := s * (1.6 + k * 0.85)
			if k == 0:
				M.cyl(pt, Tc, Vector3(1.4, wy, 1.4), L.X, 0.3, 0.9, 8, L.rp(Color8(80, 86, 80)))
			else:
				for m in 2:
					M.cyl(pt, Tc, Vector3(1.4, wy, 1.35 - m * 0.32), L.X, 0.1, 0.8, 6, L.rp(Color8(200, 200, 196)))
	# tail boom, fin, stabiliser, tail rotor
	M.face(pt, Tc, [Vector3(-1.6, -0.6, 2.4), Vector3(-1.6, 0.6, 2.4), Vector3(-7.0, 0.25, 2.3), Vector3(-7.0, -0.25, 2.3)], Vector3(-4, 0, 4), hull)
	M.face(pt, Tc, [Vector3(-1.6, -0.6, 1.5), Vector3(-1.6, -0.6, 2.4), Vector3(-7.0, -0.25, 2.3), Vector3(-7.0, -0.25, 1.9)], Vector3(-4, -2, 2), hull)
	M.face(pt, Tc, [Vector3(-1.6, 0.6, 1.5), Vector3(-7.0, 0.25, 1.9), Vector3(-7.0, 0.25, 2.3), Vector3(-1.6, 0.6, 2.4)], Vector3(-4, 2, 2), hull)
	M.face(pt, Tc, [Vector3(-6.4, 0, 2.3), Vector3(-7.4, 0, 2.3), Vector3(-7.9, 0, 4.4), Vector3(-7.2, 0, 4.4)], Vector3(-7, -1, 3), hull)
	M.box(pt, Tc, Vector3(-6.6, 0, 2.2), Vector3(0.45, 1.7, 0.06), hull)
	M.cyl(pt, Tc, Vector3(-7.6, 0.35, 3.6), L.Y, 1.35, 0.04, 12, L.rp(Color8(60, 64, 70)), {"caps": false})
	# main rotor: mast + four blades (14.6 m)
	M.cyl(pt, Tc, Vector3(1.0, 0, 3.75), L.Z, 0.22, 0.4, 8, dk)
	_blades(pt, Tc, Vector3(1.0, 0, 4.2), 7.3, 4, 0.4, L.rp(Color8(44, 46, 50)))
	g.lamp(Tc, Vector3(-7.9, 0, 4.5), L.L_RED, 6.0, true, pt)
	g.lamp(Tc, Vector3(1.3, 2.7, 1.9), L.L_GRN, 4.0, true, pt)
	g.lamp(Tc, Vector3(1.3, -2.7, 1.9), L.L_RED, 4.0, true, pt)


## Quad-rotor heavy hauler: slab-sided armoured hull, glazed nose, rear ramp, six-wheel bogie gear, two transverse
## pylons carrying four 11 m eight-blade rotors, engine deck on top.
static func hauler(S: Array, T: Dictionary, g, at: Vector3, yaw: float) -> void:
	var Tc := M.sub(T, at, yaw)
	var hull: Array = L.rp(Color8(92, 98, 88))
	var dk: Array = L.rp(Color8(46, 50, 46))
	var pt := M.part(S, 2)
	for wx: float in [-6.0, 0.0, 6.0]:
		for s: float in [-3.0, 3.0]:
			M.cyl(pt, Tc, Vector3(wx, s, 0.62), L.Y, 0.62, 0.22, 10, L.rp(Color8(28, 28, 28)), {"cap_t": 1})
	M.box(pt, Tc, Vector3(-1.0, 0, 3.8), Vector3(10.0, 2.9, 2.5), hull, Vector3(0.8, 0.6, 0.6))   # hull
	M.box(pt, Tc, Vector3(0.0, 0, 1.6), Vector3(4.5, 3.5, 0.45), dk)                                # sponsons / gear fairings
	M.box(pt, Tc, Vector3(10.4, 0, 3.4), Vector3(1.8, 2.2, 1.9), hull, Vector3(1.0, 0.6, 0.6))     # nose
	for k in 3:
		L.quad(pt, Tc, Vector3(11.6 - k * 0.2, -1.2 + k * 1.2, 4.2), L.Y * 0.5, L.Z * 0.45, Color8(80, 130, 160), L.X)
	M.face(pt, Tc, [Vector3(-11.0, -2.4, 1.6), Vector3(-11.0, 2.4, 1.6), Vector3(-13.6, 2.2, 0.2), Vector3(-13.6, -2.2, 0.2)], Vector3(-12, 0, 3), dk)   # ramp down
	for k in 6:
		L.quad(pt, Tc, Vector3(-6.0 + k * 2.6, 2.92, 4.4), L.X * 0.5, L.Z * 0.35, Color8(60, 80, 96), L.Y)
	M.dline(pt, Tc, Vector3(-10, 2.93, 2.6), Vector3(9, 2.93, 2.6), L.ORANGE, L.Y)
	M.box(pt, Tc, Vector3(-0.5, 0, 6.7), Vector3(4.0, 1.8, 0.6), dk)                               # engine deck
	for s: float in [-1.0, 1.0]:
		M.cyl(pt, Tc, Vector3(-4.8, s * 1.1, 6.8), L.X, 0.5, 0.6, 10, L.rp(Color8(60, 60, 58)))
	for px: float in [-8.5, 8.5]:                                                                   # pylons + rotors
		M.box(pt, Tc, Vector3(px, 0, 6.9), Vector3(0.6, 7.6, 0.35), hull)
		for s: float in [-1.0, 1.0]:
			var c := Vector3(px, s * 7.5, 7.2)
			M.cyl(pt, Tc, c + L.Z * 0.3, L.Z, 0.8, 0.6, 10, dk)
			_blades(pt, Tc, c + L.Z * 1.0, 5.5, 8, 0.2 + px * 0.05, L.rp(Color8(40, 42, 40)), 0.28)
	g.lamp(Tc, Vector3(12.2, 0, 4.0), Color(1, 0.95, 0.8, 0.8), 8.0, true, pt)
	g.lamp(Tc, Vector3(-1.0, 0, 7.5), L.L_RED, 7.0, true, pt)
	L.plate(pt, Tc, Vector3(2.0, 2.93, 3.2), L.Y, 4.0, 0.8, L.YEL, 3)


## Medium medevac drone: white stretcher capsule with red crosses, four ducted rotors, skids.
static func medevac_drone(S: Array, T: Dictionary, g, at: Vector3, yaw: float) -> void:
	var Tc := M.sub(T, at, yaw)
	var pt := M.part(S, 2)
	for s: float in [-1.1, 1.1]:
		M.box(pt, Tc, Vector3(0, s, 0.06), Vector3(2.2, 0.06, 0.06), L.rp(Color8(60, 62, 64)))
		for fx: float in [-1.4, 1.4]:
			M.dline(pt, Tc, Vector3(fx, s, 0.1), Vector3(fx * 0.8, s * 0.7, 0.8), Color8(60, 62, 64))
	M.box(pt, Tc, Vector3(0, 0, 1.35), Vector3(2.2, 0.95, 0.6), L.rp(Color8(232, 234, 236)), Vector3(0.5, 0.3, 0.3))
	L.quad(pt, Tc, Vector3(1.5, 0, 1.4), L.Y * 0.55, L.Z * 0.3, Color8(70, 120, 150), L.X)
	for s: float in [-1.0, 1.0]:
		L.quad(pt, Tc, Vector3(0, s * 0.96, 1.35), L.X * 0.5, L.Z * 0.15, Color8(220, 40, 36), L.Y * s)
		L.quad(pt, Tc, Vector3(0, s * 0.96, 1.35), L.X * 0.15, L.Z * 0.42, Color8(220, 40, 36), L.Y * s)
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var c := Vector3(cos(a), sin(a), 0) * 3.7 + L.Z * 1.6
		M.dline(pt, Tc, Vector3(cos(a), sin(a), 0) * 1.0 + L.Z * 1.6, c, Color8(70, 74, 78))
		M.cyl(pt, Tc, c, L.Z, 1.15, 0.22, 14, L.rp(Color8(200, 202, 204)), {"caps": false})
		_blades(pt, Tc, c, 1.05, 3, k * 0.7, L.rp(Color8(50, 52, 54)), 0.12)
		g.lamp(Tc, c + L.Z * 0.3, L.L_GRN if k % 2 == 0 else L.L_RED, 3.0, true, pt)
	g.lamp(Tc, Vector3(0, 0, 2.1), Color(1.0, 0.2, 0.2, 1.0), 5.0, true, pt)


## The original stealth gunship (Vanta-family airframe, nose cannon, side guns, EMP pod) rebuilt at Apache scale
## (x1.2 -> 17.6 m) with added detail: chin sensor ball, missile rails, spine antennas, panel lines, strobes.
## Built at native size, then every face, decal and light is scaled about the craft's origin so the gear lands
## exactly on the surface (the plan puts the origin 0.36 m above it).
static func gunship(S: Array, T: Dictionary, g, at: Vector3, yaw: float, k := 1.2) -> void:
	var IN = load("res://.plan/blackglass4/interior.gd")
	var S2: Array = []
	var nl0: int = g.lamps.size()
	IN.warden(S2, T, g, at, yaw, false)
	var Tc := M.pose(T.o, yaw, at)
	var pd := M.part(S2, 2.2)
	var dk: Array = L.rp(Color8(34, 36, 40))
	M.cyl(pd, Tc, Vector3(5.2, 0, 0.55), L.Z, 0.34, 0.22, 10, L.rp(Color8(40, 44, 48)), {"cap_t": 4})
	L.quad(pd, Tc, Vector3(5.55, 0, 0.55), L.Y * 0.16, L.Z * 0.12, Color8(200, 60, 50), L.X)
	for s: float in [-1.0, 1.0]:
		M.box(pd, Tc, Vector3(0.4, s * 3.2, 0.95), Vector3(0.9, 0.08, 0.08), dk)
		for m in 2:
			M.cyl(pd, Tc, Vector3(0.4, s * (3.05 + m * 0.3), 0.78), L.X, 0.09, 0.75, 6, L.rp(Color8(206, 206, 200)))
		M.dline(pd, Tc, Vector3(-1.0, s * 0.45, 2.3), Vector3(-1.5, s * 0.45, 3.7), Color8(60, 64, 68))
		M.dline(pd, Tc, Vector3(4.0, s * 0.9, 1.9), Vector3(-5.5, s * 0.6, 1.9), Color(0.1, 0.1, 0.1, 0.5))
		g.lamp(Tc, Vector3(-6.6, s * 0.4, 1.2), Color(1, 1, 1, 0.9), 3.0, true, pd)
	for p in S2:
		for f in p.f:
			var w: PackedVector3Array = f.w
			for i in w.size():
				w[i] = at + (w[i] - at) * k
			f.w = w
			f.c = at + (f.c - at) * k
		var n := float(p.n)
		p.sum = at * n + (p.sum - at * n) * k
		for d in p.dec:
			for key in ["a", "b"]:
				if d.has(key):
					d[key] = at + (d[key] - at) * k
			if d.has("w"):
				var w2: PackedVector3Array = d.w
				for i in w2.size():
					w2[i] = at + (w2[i] - at) * k
				d.w = w2
		S.append(p)
	var sp := M.scr(T, at)
	for i in range(nl0, g.lamps.size()):
		g.lamps[i].p = sp + (g.lamps[i].p - sp) * k
		g.lamps[i].r = float(g.lamps[i].r) * k
