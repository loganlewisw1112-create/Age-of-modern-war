extends RefCounted
## G5 Human A aircraft (agent ART-AIR), "modern": blue-grey composite skin, dark glass, team fins / bands.
##   a_attack_heli        tandem-cockpit attack helicopter: stub wings with rocket pods, chin gun, 4-blade
##                        rotor, tail wheel. fire = rocket salvo + chin-gun tracers
##   a_transport_gunship  utility helicopter: cabin with sliding doors + door guns, sling hook. fire = door guns
##   a_strike_jet         single-engine delta strike jet, twin canted fins, underwing bombs. fire = bombs away
##   a_interceptor        twin-engine interceptor: long nose, swept wings, wingtip AAMs. fire = AAM launch
##   a_vtol_dropship      tilt-rotor dropship: high wing, wingtip nacelles that swing up for hover / landing,
##                        H-tail, rear ramp (unload), sponson AA missiles + chin cannon
const MS = preload("res://tools/art/g5_air_mesh.gd")
const PT = preload("res://tools/art/g5_air_parts.gd")
const SH = preload("res://tools/art/g5_air_sheet.gd")

const LOOK := {"style": "a", "pal": PT.PAL_A}
const UP := Vector3(0, 1, 0)


static func build(out: Dictionary) -> void:
	SH.sheet(out, "a_attack_heli", "heli", attack_heli, _look({"zc": 9.0, "belly": 3.5, "break_x": -12.0, "shadow_r": 10.0}))
	SH.sheet(out, "a_transport_gunship", "lift", gunship, _look({"zc": 9.0, "belly": 3.0, "break_x": -13.0, "shadow_r": 11.0}))
	SH.sheet(out, "a_strike_jet", "jet", strike_jet, _look({"zc": 7.0, "belly": 4.5, "break_x": -9.0, "shadow_r": 11.0}))
	SH.sheet(out, "a_interceptor", "jet", interceptor, _look({"zc": 7.0, "belly": 4.5, "break_x": -10.0, "shadow_r": 11.0}))
	SH.sheet(out, "a_vtol_dropship", "vtol", vtol, _look({"zc": 9.0, "belly": 3.5, "break_x": -12.0, "shadow_r": 13.0}))


static func _look(d: Dictionary) -> Dictionary:
	var l := LOOK.duplicate()
	l.merge(d, true)
	return l


# ---------------------------------------------------------------- a_attack_heli
static func attack_heli(m, st: Dictionary) -> void:
	MS.loft(m, [[16, 0.5, 6, 8], [13, 2.4, 4, 10], [6, 3.3, 3.5, 12], [-2, 3.6, 3.5, 12.5], [-8, 2.5, 5, 11],
		[-14, 1.2, 7.5, 10], [-24, 0.9, 8, 10]], "body")
	MS.loft(m, [[13.5, 0.6, 9, 10], [11, 1.8, 9.5, 12.6], [7, 2.0, 10.5, 14.2], [3, 1.9, 11, 14.2], [0, 1.2, 11, 12.6]], "glass")
	MS.loft(m, [[-15, 1.35, 7.3, 10.2], [-17.5, 1.3, 7.4, 10.1]], "team")
	MS.fin(m, [Vector2(-21, 10), Vector2(-25, 10), Vector2(-27, 19), Vector2(-24, 19)], 0.0, 1.0, "team")
	MS.wings(m, -20, -23, -21, -23.5, 0.5, 5.0, 9.0, 0.8, "body2")
	for s: float in [-1.0, 1.0]:
		MS.cyl(m, Vector3(0, 4.0 * s, 11.5), Vector3(-8, 4.0 * s, 11.3), 1.8, "body2", 1.4)
		m.mark(Vector3(-8.5, 4.0 * s, 11.3), "heat", Vector3(-1, 0, 0))
	MS.wings(m, 2, -3, 1.5, -2.5, 3.0, 10.5, 7.0, 1.0, "body2")
	for s: float in [-1.0, 1.0]:
		PT.rocket_pod(m, Vector3(0.5, 8.0 * s, 5.4), 7.0, 1.6, "dark")
		PT.missile(m, Vector3(0, 10.5 * s, 6.0), 5.0, 0.5)
	MS.box(m, Vector3(12.5, 0, 3.4), Vector3(1.3, 1.2, 1.1), "dark")
	m.line(Vector3(13, 0, 3.2), Vector3(18.5, 0, 2.6), "metal")
	PT.wheel(m, 6.0, -3.6, 1.6, 4.0)
	PT.wheel(m, 6.0, 3.6, 1.6, 4.0)
	PT.wheel(m, -21.0, 0.0, 1.1, 8.0)
	PT.main_rotor(m, st, Vector3(0, 0, 16.5), 21.0, 4)
	PT.tail_rotor(m, st, Vector3(-25, 1.4, 15.5), 4.5)
	PT.nav(m, 0, 10.6, 7)
	if st.fire:
		for s: float in [-1.0, 1.0]:
			m.mark(Vector3(5, 8.0 * s, 5.4), "rocket", Vector3(1, 0, -0.12), 1.3)
			m.mark(Vector3(4.5, 8.0 * s, 5.4), "flash", Vector3(1, 0, 0), 0.8)
		m.mark(Vector3(19, 0, 2.5), "tracer", Vector3(1, 0, -0.18))


# ---------------------------------------------------------------- a_transport_gunship
static func gunship(m, st: Dictionary) -> void:
	MS.loft(m, [[17, 1.0, 5, 9], [14, 4.0, 3.5, 12], [8, 5.0, 3, 14], [-4, 5.0, 3, 14], [-9, 3.5, 5, 13],
		[-14, 1.5, 8.5, 11.5], [-27, 1.0, 9, 11]], "body", 0.85)
	MS.loft(m, [[16.2, 2.4, 8.2, 10.8], [13, 4.3, 9, 13], [10.5, 4.4, 9.5, 13.8]], "glass")
	MS.loft(m, [[-15.5, 1.65, 8.3, 11.7], [-18, 1.55, 8.4, 11.6]], "team")
	MS.fin(m, [Vector2(-23, 10.5), Vector2(-28, 10.5), Vector2(-30, 19), Vector2(-27, 19)], 0.0, 1.0, "team")
	MS.wings(m, -24, -27, -24.5, -27, 0.5, 5.5, 10, 0.8, "body2")
	MS.box(m, Vector3(-1, 0, 14.6), Vector3(5.5, 3.0, 1.3), "body2")
	for s: float in [-1.0, 1.0]:
		m.mark(Vector3(-6.5, 2.6 * s, 15), "heat", Vector3(-1, 0, 0))
		# sliding cabin door: open = dark doorway, closed = door panel
		MS.box(m, Vector3(-1 if not st.open else -1, 5.05 * s, 8.5), Vector3(3.2, 0.12, 3.6), "dark" if st.open else "body2")
		if st.open:
			MS.box(m, Vector3(-6.5, 5.2 * s, 8.5), Vector3(2.4, 0.12, 3.4), "body2")
		m.line(Vector3(1.5, 5.4 * s, 9), Vector3(6.5, 7.6 * s, 8.4), "dark")
		MS.wings(m, 0.5, -2.5, 0, -2, 5.0, 8.5, 7.0, 0.7, "body2")
		MS.cyl(m, Vector3(1.5, 8.6 * s, 6.2), Vector3(-5, 8.6 * s, 6.2), 1.3, "body2", 1.0)
	PT.wheel(m, 4.0, -4.6, 1.6, 4.0)
	PT.wheel(m, 4.0, 4.6, 1.6, 4.0)
	PT.wheel(m, -22.0, 0.0, 1.1, 9.0)
	PT.main_rotor(m, st, Vector3(0, 0, 18.5), 23.0, 4, 2.6)
	PT.tail_rotor(m, st, Vector3(-27.5, 1.5, 15.5), 4.5)
	PT.sling(m, st, 3.0, 3.2)
	PT.nav(m, -1, 5.2, 13)
	if st.fire:
		for s: float in [-1.0, 1.0]:
			m.mark(Vector3(6.8, 7.8 * s, 8.3), "tracer", Vector3(1, 0.5 * s, -0.25))
			m.mark(Vector3(6.6, 7.7 * s, 8.4), "flash", Vector3(1, 0, 0), 0.6)


# ---------------------------------------------------------------- a_strike_jet
static func strike_jet(m, st: Dictionary) -> void:
	MS.loft(m, [[22, 0.3, 6.6, 7.0], [18, 1.8, 5.5, 8.5], [12, 3.0, 4.8, 9.6], [4, 4.2, 4.5, 9.6], [-6, 4.6, 4.5, 9.2],
		[-14, 3.6, 5, 8.6], [-17, 2.4, 5.6, 8.0]], "body")
	_canopy(m, st, [[14, 0.5, 9.0, 9.4], [11, 1.6, 9.0, 11.3], [6, 1.6, 9.0, 11.1], [3, 0.5, 9.0, 9.6]], 3.0, 9.0)
	for s: float in [-1.0, 1.0]:
		MS.box(m, Vector3(5, 4.4 * s, 6.6), Vector3(3.0, 1.0, 1.4), "body2")
		MS.box(m, Vector3(8.1, 4.4 * s, 6.6), Vector3(0.2, 0.8, 1.1), "dark")
		MS.fin(m, [Vector2(-10, 8.5), Vector2(-15.5, 8.5), Vector2(-18, 15), Vector2(-15, 15)], 3.0 * s, 0.8, "team")
	MS.wings(m, 4, -10, -9, -14, 3.5, 17, 7, 0.9, "body")
	MS.wings(m, -12, -17, -16, -18.5, 3, 9, 6.8, 0.7, "body2")
	if st.flaps:
		MS.wings(m, -9.5, -12, -12.5, -14, 5, 13, 6.2, 0.5, "body2")
	MS.cyl(m, Vector3(-16.5, 0, 6.8), Vector3(-19.5, 0, 6.8), 2.0, "engine", 1.6)
	_exhaust(m, st, Vector3(-20, 0, 6.8))
	if not st.fire:
		for s: float in [-1.0, 1.0]:
			PT.missile(m, Vector3(-3, 9.0 * s, 5.4), 6.0, 1.0, "dark")
	PT.gear(m, st, 13.0, -4.0, 4.0, 5.0)
	PT.nav(m, -11.5, 17, 7)
	if st.fire:
		for s: float in [-1.0, 1.0]:
			m.mark(Vector3(-4, 9.0 * s, 4.0), "bomb", Vector3(1, 0, 0), 1.0)


# ---------------------------------------------------------------- a_interceptor
static func interceptor(m, st: Dictionary) -> void:
	MS.loft(m, [[26, 0.3, 6.8, 7.2], [21, 1.6, 5.8, 8.6], [14, 2.8, 5.0, 9.4], [6, 3.4, 4.6, 9.4], [-4, 5.2, 4.4, 9.0],
		[-14, 5.0, 4.6, 8.6], [-19, 4.2, 5.0, 8.2]], "body")
	_canopy(m, st, [[17, 0.5, 9.0, 9.4], [14, 1.5, 9.0, 11.0], [9, 1.5, 9.0, 11.0], [6, 0.5, 9.0, 9.5]], 6.0, 9.0)
	MS.wings(m, 4, -12, -11, -15, 4.5, 16, 7, 0.8, "body")
	MS.wings(m, -13, -18, -17, -20, 4, 10, 6.6, 0.7, "body2")
	if st.flaps:
		MS.wings(m, -11, -13, -13.5, -15, 6, 13, 6.2, 0.5, "body2")
	for s: float in [-1.0, 1.0]:
		MS.fin(m, [Vector2(-9, 8.5), Vector2(-16, 8.5), Vector2(-19, 16), Vector2(-15.5, 16)], 4.0 * s, 0.8, "team")
		MS.cyl(m, Vector3(-19, 2.2 * s, 6.6), Vector3(-21.5, 2.2 * s, 6.6), 1.6, "engine", 1.3)
		_exhaust(m, st, Vector3(-22, 2.2 * s, 6.6))
		if not (st.fire and s > 0.0):
			PT.missile(m, Vector3(-10, 16.6 * s, 7.0), 7.0, 0.5)
		PT.missile(m, Vector3(2, 3.2 * s, 4.0), 6.0, 0.5)
	PT.gear(m, st, 15.0, -4.0, 3.5, 5.0)
	PT.nav(m, -12, 16, 7)
	if st.fire:
		m.mark(Vector3(-2, 16.6, 7.0), "missile", Vector3(1, 0, 0), 1.4)


static func _canopy(m, st: Dictionary, rings: Array, hinge_x: float, hinge_z: float) -> void:
	if not st.canopy:
		MS.loft(m, rings, "glass")
		return
	var rel: Array = []
	for r: Array in rings:
		rel.append([r[0] - hinge_x, r[1], r[2] - hinge_z, r[3] - hinge_z])
	PT.with(m, PT.at(Vector3(hinge_x, 0, hinge_z), Basis(UP, -0.5)), func() -> void: MS.loft(m, rel, "glass"))
	MS.loft(m, [[rings[0][0], 0.4, 8.6, 9.0], [rings[1][0], 1.5, 8.6, 9.2], [rings[-1][0], 0.4, 8.6, 9.0]], "dark")


static func _exhaust(m, st: Dictionary, p: Vector3) -> void:
	var ab: float = st.ab
	if ab > 0.5:
		m.mark(p, "exhaust", Vector3(-1, 0, 0), ab * 0.6)
	elif ab >= 0.0:
		m.mark(p, "heat", Vector3(-1, 0, 0))


# ---------------------------------------------------------------- a_vtol_dropship
static func vtol(m, st: Dictionary) -> void:
	MS.loft(m, [[24, 1.0, 7, 10], [20, 4.0, 4.5, 13], [14, 5.4, 3.5, 15], [-8, 5.6, 3.5, 15.5], [-16, 4.2, 6, 15],
		[-22, 2.0, 10, 14.5]], "body", 0.8)
	MS.loft(m, [[22.6, 2.6, 8.5, 11.5], [18.6, 4.6, 10, 14], [16.4, 4.7, 10.5, 14.6]], "glass")
	MS.loft(m, [[1.5, 5.75, 3.4, 15.7], [-1.5, 5.75, 3.4, 15.7]], "team", 0.8)
	MS.wings(m, 4, -4, 4, -4, 0, 20, 16.4, 1.2, "body")
	MS.wings(m, -18, -23, -19, -23, 0, 9, 15.0, 0.9, "body2")
	for s: float in [-1.0, 1.0]:
		MS.fin(m, [Vector2(-18, 13), Vector2(-23, 13), Vector2(-24, 21), Vector2(-20.5, 21)], 9.0 * s, 0.9, "team")
		MS.box(m, Vector3(-2, 6.2 * s, 5), Vector3(6, 1.4, 2), "body2")
		PT.missile(m, Vector3(-2, 7.9 * s, 6.6), 6.0, 0.6)
		var tilt: float = st.tilt
		PT.with(m, PT.at(Vector3(0, 20.5 * s, 16.4), Basis(UP, -tilt * PI * 0.5)), func() -> void:
			MS.cyl(m, Vector3(-5, 0, 0), Vector3(6, 0, 0), 2.4, "body2", 2.0)
			MS.box(m, Vector3(6.8, 0, 0), Vector3(0.8, 0.9, 0.9), "dark")
			m.disc(Vector3(7.6, 0, 0), Vector3(1, 0, 0), 11.0, 3, SH.blade_ph(st, 3, 0.3 + (0.9 if s > 0 else 0.0)), st.spin))
	PT.ramp(m, st, Vector3(-16, 0, 6.0), 8.0, 3.6)
	PT.gear(m, st, 16.0, -4.0, 5.5, 4.0, 1.6)
	MS.box(m, Vector3(20, 0, 4), Vector3(1.2, 1.2, 1.0), "dark")
	m.line(Vector3(20.5, 0, 3.8), Vector3(25, 0, 3.4), "metal")
	PT.sling(m, st, 3.5, 3.4)
	PT.nav(m, 0, 20.5, 18.5)
	if st.fire:
		m.mark(Vector3(2, -7.9, 6.6), "missile", Vector3(1, 0, 0), 1.3)
		m.mark(Vector3(25.5, 0, 3.4), "tracer", Vector3(1, 0, -0.15))
