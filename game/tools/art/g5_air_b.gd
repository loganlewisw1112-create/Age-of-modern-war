extends RefCounted
## G5 Human B aircraft (agent ART-AIR), "industrial / riveted": olive drab over a pale-blue belly, boxy
## sections, heavy panel seams with rivet rows and rust (raster style "b"), team fins.
##   b_gunship        armoured assault gunship: stepped twin bubble canopies, twin top engines, anhedral
##                    stub wings with four rocket pods, chin HMG, 5-blade rotor. fire = rockets + HMG
##   b_heavy_lift     tandem-rotor heavy-lift helicopter: box fuselage, tall rear pylon, side sponsons,
##                    rear ramp (unload), sling hook. fire = flare dispense (it carries no weapon)
##   b_bomber         heavy swept-wing bomber: glazed nose, two underwing engine pods, tail gun, bomb bay
##                    (fire = doors open, a stick of bombs falling)
##   b_vtol_dropship  boxy lift-fan dropship: four ducted fans on outriggers (tilted forward in cruise,
##                    level for hover / landing), twin fins, rear ramp, top flak turret
const MS = preload("res://tools/art/g5_air_mesh.gd")
const PT = preload("res://tools/art/g5_air_parts.gd")
const SH = preload("res://tools/art/g5_air_sheet.gd")

const UP := Vector3(0, 1, 0)


static func build(out: Dictionary) -> void:
	SH.sheet(out, "b_gunship", "heli", gunship, _look({"zc": 9.0, "belly": 3.0, "break_x": -13.0, "shadow_r": 11.0}))
	SH.sheet(out, "b_heavy_lift", "lift", heavy_lift, _look({"zc": 10.0, "belly": 3.0, "break_x": -12.0, "shadow_r": 13.0}))
	SH.sheet(out, "b_bomber", "jet", bomber, _look({"zc": 8.0, "belly": 5.0, "break_x": -14.0, "shadow_r": 14.0}))
	SH.sheet(out, "b_vtol_dropship", "vtol", vtol, _look({"zc": 9.0, "belly": 3.0, "break_x": -11.0, "shadow_r": 13.0}))


static func _look(d: Dictionary) -> Dictionary:
	var l := {"style": "b", "pal": PT.PAL_B}
	l.merge(d, true)
	return l


# ---------------------------------------------------------------- b_gunship
static func gunship(m, st: Dictionary) -> void:
	MS.loft(m, [[18, 0.8, 5, 8], [15, 3.0, 3.5, 10], [9, 4.0, 3, 12.5], [-3, 4.4, 3, 14], [-9, 3.2, 5, 13],
		[-15, 1.4, 8.5, 11.5], [-28, 1.0, 9, 11]], "body", 0.7)
	MS.loft(m, [[-1, 4.45, 2.9, 3.6], [-7, 3.5, 4.6, 5.4]], "under", 0.7)
	MS.loft(m, [[16.6, 1.0, 7.6, 9.2], [14.2, 2.4, 8.2, 11.6], [12, 2.3, 8.8, 11.6]], "glass")
	MS.loft(m, [[11, 1.4, 11, 12], [9, 2.6, 11.4, 14.2], [6.5, 2.4, 12, 14.2]], "glass")
	MS.loft(m, [[-16, 1.45, 8.4, 11.6], [-18, 1.4, 8.5, 11.5]], "team", 0.7)
	MS.fin(m, [Vector2(-24, 10.5), Vector2(-29, 10.5), Vector2(-31, 20), Vector2(-28, 20)], 0.0, 1.0, "team")
	MS.wings(m, -22, -25, -22.5, -25, 0.5, 6, 10, 0.8, "body2")
	for s: float in [-1.0, 1.0]:
		MS.cyl(m, Vector3(3, 2.6 * s, 14.6), Vector3(-8, 2.6 * s, 14.6), 2.0, "body2", 1.7)
		MS.box(m, Vector3(3.4, 2.6 * s, 14.6), Vector3(0.4, 1.4, 1.4), "dark")
		m.mark(Vector3(-8.6, 3.2 * s, 14.6), "heat", Vector3(-1, s * 0.6, 0))
	MS.wings(m, 2, -4, 1, -3, 4.3, 12, 7.5, 1.0, "body2", -0.15)
	for s: float in [-1.0, 1.0]:
		PT.rocket_pod(m, Vector3(0, 7.5 * s, 5.4), 6.0, 1.6, "dark")
		PT.rocket_pod(m, Vector3(-0.5, 10.5 * s, 4.9), 5.0, 1.3, "dark")
	MS.box(m, Vector3(15.5, 0, 3.0), Vector3(1.3, 1.3, 1.1), "dark")
	m.line(Vector3(16, 0, 2.8), Vector3(21, 0, 2.4), "metal")
	PT.wheel(m, -2.0, -5.0, 1.7, 3.5)
	PT.wheel(m, -2.0, 5.0, 1.7, 3.5)
	PT.wheel(m, 13.0, 0.0, 1.3, 4.0)
	PT.main_rotor(m, st, Vector3(0, 0, 18), 22.0, 5, 2.4)
	PT.tail_rotor(m, st, Vector3(-29, -1.6, 16), 4.5, 3)
	PT.nav(m, -0.5, 12, 6.5)
	if st.fire:
		for s: float in [-1.0, 1.0]:
			m.mark(Vector3(3.5, 7.5 * s, 5.4), "rocket", Vector3(1, 0, -0.12), 1.3)
			m.mark(Vector3(3, 7.5 * s, 5.4), "flash", Vector3(1, 0, 0), 0.8)
		m.mark(Vector3(21.5, 0, 2.3), "tracer", Vector3(1, 0, -0.18))


# ---------------------------------------------------------------- b_heavy_lift
static func heavy_lift(m, st: Dictionary) -> void:
	MS.loft(m, [[24, 2.0, 6, 11], [21, 4.4, 4, 14], [16, 5.0, 3, 15], [-18, 5.0, 3, 15], [-24, 4.2, 5, 16],
		[-27, 2.5, 9, 16]], "body", 0.55)
	MS.loft(m, [[23, 3.4, 8, 12], [20.5, 4.6, 9.5, 14.2], [18.5, 4.8, 10.5, 14.6]], "glass")
	MS.loft(m, [[2, 5.05, 2.9, 15.1], [-1, 5.05, 2.9, 15.1]], "team", 0.55)
	MS.box(m, Vector3(17, 0, 16), Vector3(3, 1.6, 1.6), "body2")
	MS.box(m, Vector3(-21, 0, 18.5), Vector3(5, 2.0, 3.6), "body2")
	MS.fin(m, [Vector2(-17, 14), Vector2(-26, 14), Vector2(-25, 20), Vector2(-19, 20)], 0.0, 1.4, "team")
	for s: float in [-1.0, 1.0]:
		MS.cyl(m, Vector3(-14, 3.6 * s, 16.2), Vector3(-24, 3.6 * s, 16.2), 1.8, "engine", 1.5)
		m.mark(Vector3(-24.5, 3.6 * s, 16.2), "heat", Vector3(-1, 0, 0))
		MS.box(m, Vector3(-1, 5.4 * s, 4.5), Vector3(10, 1.2, 2), "body2")
	PT.wheel(m, 12.0, -4.2, 1.6, 3.5)
	PT.wheel(m, 12.0, 4.2, 1.6, 3.5)
	PT.wheel(m, -12.0, -5.6, 1.6, 3.5)
	PT.wheel(m, -12.0, 5.6, 1.6, 3.5)
	PT.ramp(m, st, Vector3(-24, 0, 5.5), 7.0, 3.8)
	PT.main_rotor(m, st, Vector3(17, 0, 18.5), 19.0, 3, 1.6, 0.4)
	PT.main_rotor(m, st, Vector3(-21, 0, 23.0), 19.0, 3, 1.4, 1.4)
	PT.sling(m, st, 3.0, 3.6)
	PT.nav(m, 0, 5.6, 14)
	if st.fire:
		for s: float in [-1.0, 1.0]:
			m.mark(Vector3(-20, 5.6 * s, 7), "flash", Vector3(-1, s, 0), 0.6)
			m.mark(Vector3(-22, 7.0 * s, 4), "flash", Vector3(-1, s, 0), 0.4)


# ---------------------------------------------------------------- b_bomber
static func bomber(m, st: Dictionary) -> void:
	MS.loft(m, [[28, 0.6, 7, 9], [25, 2.6, 5.5, 11], [18, 3.6, 5, 12], [-10, 3.6, 5, 12], [-22, 2.4, 6.5, 11.5],
		[-30, 1.0, 8, 10.5]], "body", 0.9)
	MS.loft(m, [[12, 3.65, 4.9, 6.2], [-8, 3.65, 4.9, 6.2]], "under", 0.9)
	MS.loft(m, [[28.6, 0.6, 7, 9], [25.6, 2.7, 5.6, 11.1], [23.2, 2.9, 5.6, 11.4]], "glass")
	MS.loft(m, [[19, 1.2, 11.4, 12.3], [16, 2.4, 11.5, 13.6], [12, 2.2, 11.5, 13.2]], "glass")
	MS.wings(m, 8, -4, -10, -16, 3.5, 26, 8, 1.2, "body", 0.03)
	if st.flaps:
		MS.wings(m, -4, -6, -10, -12, 5, 18, 7.6, 0.6, "body2", 0.03)
	MS.fin(m, [Vector2(-20, 11), Vector2(-28, 11), Vector2(-32, 22), Vector2(-26, 22)], 0.0, 1.0, "team")
	MS.wings(m, -22, -28, -27, -31, 2, 11, 10, 0.9, "body2")
	m.line(Vector3(-30, 0, 9.5), Vector3(-34, 0, 9.5), "metal")
	MS.box(m, Vector3(-30.4, 0, 9.5), Vector3(0.9, 1.0, 1.0), "glass")
	for s: float in [-1.0, 1.0]:
		MS.box(m, Vector3(0, 11 * s, 7.0), Vector3(3, 0.5, 1.2), "body2")
		MS.cyl(m, Vector3(6, 11 * s, 5.4), Vector3(-6, 11 * s, 5.4), 2.4, "engine", 2.0)
		MS.box(m, Vector3(6.2, 11 * s, 5.4), Vector3(0.3, 1.6, 1.6), "dark")
		var ab: float = st.ab
		if ab > 0.5:
			m.mark(Vector3(-6.6, 11 * s, 5.4), "exhaust", Vector3(-1, 0, 0), ab * 0.45)
		elif ab >= 0.0:
			m.mark(Vector3(-6.6, 11 * s, 5.4), "heat", Vector3(-1, 0, 0))
	MS.box(m, Vector3(0, 0, 4.9), Vector3(6, 2.2, 0.3), "dark" if st.fire else "body2")
	PT.gear(m, st, 20.0, -2.0, 11.0, 4.5, 1.8)
	PT.nav(m, -13, 26, 8.8)
	if st.fire:
		m.mark(Vector3(3, 0, 2.5), "bomb", Vector3(1, 0, 0), 0.6)
		m.mark(Vector3(-1, 0, 0.5), "bomb", Vector3(1, 0, 0), 1.2)
		m.mark(Vector3(-5, 0, -1.5), "bomb", Vector3(1, 0, 0), 1.8)


# ---------------------------------------------------------------- b_vtol_dropship
static func vtol(m, st: Dictionary) -> void:
	MS.loft(m, [[22, 2.2, 6, 10], [19, 4.6, 4, 13], [14, 5.4, 3, 14.5], [-12, 5.4, 3, 14.5], [-18, 4.2, 5, 14],
		[-22, 2.0, 9, 13]], "body", 0.5)
	MS.loft(m, [[21, 3.4, 7.5, 11], [18.5, 4.8, 9, 13.2], [16.6, 4.9, 9.5, 13.8]], "glass")
	MS.loft(m, [[1, 5.45, 2.9, 14.6], [-2, 5.45, 2.9, 14.6]], "team", 0.5)
	MS.wings(m, 13, 9, 13, 9, 4, 13, 11, 1.2, "body2")
	MS.wings(m, -8, -12, -8, -12, 4, 13, 12, 1.2, "body2")
	var tilt: float = st.tilt
	var mode := "fan_stop" if String(st.spin) == "stop" else "fan_spin"
	for c: Vector3 in [Vector3(11, 15, 11), Vector3(11, -15, 11), Vector3(-10, 15, 12), Vector3(-10, -15, 12)]:
		PT.with(m, PT.at(c, Basis(UP, (1.0 - tilt) * 0.5)), func() -> void:
			MS.duct(m, Vector3.ZERO, Vector3(0, 0, 1), 5.5, 2.6, "body2")
			MS.box(m, Vector3.ZERO, Vector3(0.9, 0.9, 0.6), "dark")
			m.disc(Vector3(0, 0, 0.4), Vector3(0, 0, 1), 5.0, 7, SH.blade_ph(st, 7, 0.2 + c.x * 0.05), mode))
	for s: float in [-1.0, 1.0]:
		MS.fin(m, [Vector2(-16, 13), Vector2(-21, 13), Vector2(-23, 20), Vector2(-19.5, 20)], 4.0 * s, 0.9, "team")
	PT.ramp(m, st, Vector3(-18, 0, 5.5), 7.5, 3.6)
	MS.box(m, Vector3(6, 0, 15.6), Vector3(2.2, 2.0, 1.2), "dark")
	for s: float in [-1.0, 1.0]:
		m.line(Vector3(7.5, 0.8 * s, 16), Vector3(13, 0.8 * s, 17.5), "metal")
	PT.gear(m, st, 15.0, -6.0, 5.0, 3.5, 1.7)
	PT.sling(m, st, 3.0, 3.4)
	PT.nav(m, 11, 20.5, 11)
	if st.fire:
		for s: float in [-1.0, 1.0]:
			m.mark(Vector3(13.5, 0.8 * s, 17.6), "flash", Vector3(1, 0, 0), 0.7)
		m.mark(Vector3(14, 0, 18), "tracer", Vector3(1, 0, 0.35))
