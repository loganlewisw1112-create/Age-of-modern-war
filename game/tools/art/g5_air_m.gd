extends RefCounted
## G5 Machine aircraft (agent ART-AIR): graphite airframes with cyan seams (raster style "m"), cyan sensor
## glass, ducted fans instead of open rotors.
##   m_drone_carrier      lozenge hull on four ducted fans, underside rack with docked micro drones, nose
##                        bolt gun. fire = a micro drone dropping off the rack + bolt
##   m_lifter_drone       open spine frame, four long-arm ducted fans, troop pod, grapple claw (sling hook)
##   m_interceptor_swarm  five dart drones in a V (one entity). taxi / parked = the darts resting on skids
##   m_micro_drone        tiny quad launched by the carrier (30 s life): landed = perched, props stopped
const MS = preload("res://tools/art/g5_air_mesh.gd")
const PT = preload("res://tools/art/g5_air_parts.gd")
const SH = preload("res://tools/art/g5_air_sheet.gd")

const UP := Vector3(0, 1, 0)


static func build(out: Dictionary) -> void:
	SH.sheet(out, "m_drone_carrier", "heli", carrier, _look({"zc": 9.0, "belly": 4.0, "break_x": -10.0, "shadow_r": 11.0}))
	SH.sheet(out, "m_lifter_drone", "lift", lifter, _look({"zc": 10.0, "belly": 6.0, "break_x": -6.0, "shadow_r": 11.0}))
	SH.sheet(out, "m_interceptor_swarm", "jet", swarm, _look({"zc": 5.0, "belly": 3.0, "break_x": -100.0, "shadow_r": 12.0}))
	SH.sheet(out, "m_micro_drone", "micro", micro, _look({"zc": 4.0, "belly": 3.0, "break_x": -100.0, "shadow_r": 3.5}))


static func _look(d: Dictionary) -> Dictionary:
	var l := {"style": "m", "pal": PT.PAL_M}
	l.merge(d, true)
	return l


static func _fan(m, st: Dictionary, c: Vector3, r: float, k: int) -> void:
	MS.duct(m, c, Vector3(0, 0, 1), r, 2.4, "body2")
	MS.box(m, c, Vector3(0.8, 0.8, 0.5), "dark")
	var mode := "fan_stop" if String(st.spin) == "stop" else "fan_spin"
	m.disc(c + Vector3(0, 0, 0.4), Vector3(0, 0, 1), r - 0.5, 5, SH.blade_ph(st, 5, 0.3 + k * 0.7), mode)
	m.mark(c + Vector3(r * 0.7, 0, 1.3), "cyanpx")


# ---------------------------------------------------------------- m_drone_carrier
static func carrier(m, st: Dictionary) -> void:
	MS.loft(m, [[16, 2, 7, 10], [12, 6, 5, 12], [-8, 7, 5, 12.5], [-14, 4, 6.5, 11.5], [-17, 1.5, 8, 10]], "body", 0.6)
	MS.loft(m, [[16.6, 1.6, 7.6, 9.6], [15, 3.0, 7.2, 10.2]], "glass")
	MS.box(m, Vector3(-1, 0, 12.6), Vector3(5, 3, 0.4), "team")
	var k := 0
	for c: Vector3 in [Vector3(9, 13, 10), Vector3(9, -13, 10), Vector3(-9, 13, 10.5), Vector3(-9, -13, 10.5)]:
		MS.box(m, Vector3(c.x, c.y * 0.68, c.z), Vector3(1.4, absf(c.y) * 0.3, 0.9), "body2")
		_fan(m, st, c, 5.0, k)
		m.line(Vector3(c.x, c.y * 0.7, c.z - 1.0), Vector3(c.x * 1.08, c.y * 0.78, 0.5), "metal")
		MS.box(m, Vector3(c.x * 1.08, c.y * 0.78, 0.4), Vector3(1.2, 0.8, 0.4), "dark")
		k += 1
	MS.box(m, Vector3(0, 0, 4.4), Vector3(7, 3, 0.8), "dark")
	for p: Vector3 in [Vector3(4, 1.8, 3.0), Vector3(4, -1.8, 3.0), Vector3(-3, 1.8, 3.0), Vector3(-3, -1.8, 3.0)]:
		if st.fire and p.x > 0 and p.y > 0:
			continue
		MS.box(m, p, Vector3(1.5, 1.2, 0.7), "body")
		m.mark(p + Vector3(1.5, 0, 0), "cyanpx")
	m.line(Vector3(15, 0, 6), Vector3(21, 0, 5.4), "metal")
	if st.fire:
		m.mark(Vector3(5, 2, -3), "drone", Vector3(1, 0, 0))
		m.mark(Vector3(21.5, 0, 5.3), "bolt", Vector3(1, 0, -0.15), 1.2)


# ---------------------------------------------------------------- m_lifter_drone
static func lifter(m, st: Dictionary) -> void:
	MS.loft(m, [[12, 2.0, 9, 12], [8, 3.5, 8, 13], [-8, 3.5, 8, 13], [-12, 2.0, 9, 12]], "body", 0.5)
	MS.box(m, Vector3(12.4, 0, 10.5), Vector3(0.8, 1.3, 0.9), "glass")
	MS.box(m, Vector3(0, 0, 13.3), Vector3(6, 1.5, 0.3), "team")
	var k := 0
	for c: Vector3 in [Vector3(11, 14, 12), Vector3(11, -14, 12), Vector3(-11, 14, 12), Vector3(-11, -14, 12)]:
		MS.cyl(m, Vector3(c.x * 0.3, signf(c.y) * 2.5, 11), c - Vector3(signf(c.x) * 2.0, signf(c.y) * 3.5, 0), 1.0, "body2", 0.8, 4)
		_fan(m, st, c, 5.5, k)
		k += 1
	for p: Vector3 in [Vector3(6, 3, 8), Vector3(-6, 3, 8), Vector3(6, -3, 8), Vector3(-6, -3, 8)]:
		m.line(p, Vector3(p.x * 1.15, p.y * 2.0, 0.4), "metal")
	var pz := 2.2 if st.open else 6.8
	MS.box(m, Vector3(0, 0, pz), Vector3(6, 3, 1.5), "body")
	if st.open:
		MS.box(m, Vector3(0, 3.05, pz), Vector3(4.5, 0.1, 1.1), "dark")
		m.line(Vector3(0, 0, 8), Vector3(0, 0, pz + 1.5), "cable", true)
	MS.box(m, Vector3(0, 0, 7.6 if not st.open else 7.0), Vector3(2.4, 2.4, 0.7), "dark")
	for s: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		m.line(Vector3(2.2 * s.x, 2.2 * s.y, 7.2), Vector3(3.4 * s.x, 3.4 * s.y, 5.0), "metal", st.sling > 0)
	PT.sling(m, st, 6.0, 3.4)
	if st.fire:
		m.mark(Vector3(0, 0, 4.5), "bolt", Vector3(0, 0, -1), 0.6)
		m.mark(Vector3(12.8, 0, 10.5), "flash", Vector3(1, 0, 0), 0.5)


# ---------------------------------------------------------------- m_interceptor_swarm
static func swarm(m, st: Dictionary) -> void:
	var slots := [Vector3(8, 0, 0), Vector3(2, 7, 0), Vector3(2, -7, 0), Vector3(-4, 14, 0), Vector3(-4, -14, 0)]
	var i := 0
	for p: Vector3 in slots:
		var z := 3.0 if bool(st.gear) else 4.0
		PT.with(m, PT.at(p + Vector3(0, 0, z)), func() -> void: _dart(m, st, i))
		i += 1
	if st.fire:
		m.mark(Vector3(16.5, 0, 4), "bolt", Vector3(1, 0, 0), 1.2)
		m.mark(Vector3(8, 7, 4), "missile", Vector3(1, 0, 0), 1.0)
		m.mark(Vector3(8, -7, 4), "missile", Vector3(1, 0, 0), 1.0)


static func _dart(m, st: Dictionary, i: int) -> void:
	MS.loft(m, [[7.5, 0.4, 0, 0.8], [3, 1.9, -0.8, 1.8], [-4.5, 1.7, -0.6, 1.5], [-6, 1.0, -0.3, 1.0]], "body", 0.8)
	MS.wings(m, 1.5, -4.5, -4.5, -6.5, 1.2, 6.0, 0.3, 0.5, "body2")
	MS.fin(m, [Vector2(-3, 1.2), Vector2(-6, 1.2), Vector2(-6.8, 3.6), Vector2(-5, 3.6)], 0.0, 0.5, "team")
	MS.box(m, Vector3(4.2, 0, 1.4), Vector3(1.4, 0.7, 0.4), "glass")
	var ab: float = st.ab
	if ab > 0.5:
		m.mark(Vector3(-6.3, 0, 0.3), "plasma", Vector3(-1, 0, 0), ab * 0.45)
	elif ab >= 0.0:
		m.mark(Vector3(-6.3, 0, 0.3), "cyanpx")
	if st.gear:
		for s: float in [-1.0, 1.0]:
			m.line(Vector3(2, 1.2 * s, -0.6), Vector3(2, 1.6 * s, -3.0), "metal")
			m.line(Vector3(-3, 1.2 * s, -0.5), Vector3(-3, 1.6 * s, -3.0), "metal")


# ---------------------------------------------------------------- m_micro_drone
static func micro(m, st: Dictionary) -> void:
	MS.box(m, Vector3(0, 0, 4), Vector3(1.8, 1.3, 0.9), "body", "team")
	m.mark(Vector3(1.9, 0, 4), "cyanpx")
	var k := 0
	for s: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var t := Vector3(2.8 * s.x, 2.8 * s.y, 4.6)
		m.line(Vector3(0, 0, 4.2), t, "body2")
		m.disc(t + Vector3(0, 0, 0.4), Vector3(0, 0, 1), 1.9, 2, SH.blade_ph(st, 2, 0.4 + k), st.spin)
		m.line(Vector3(1.6 * s.x, 1.2 * s.y, 3.4), Vector3(1.9 * s.x, 1.5 * s.y, 0.2), "metal")
		k += 1
	m.line(Vector3(1.6, 0, 3.4), Vector3(3.6, 0, 3.0), "metal")
	if st.fire:
		m.mark(Vector3(3.8, 0, 3.0), "bolt", Vector3(1, 0, -0.3), 0.8)
