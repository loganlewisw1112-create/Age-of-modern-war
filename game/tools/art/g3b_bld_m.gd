extends RefCounted
## G3b Machine building (agent ART4-2): m_compute_node, built look + 3 fabrication stages, called by
## g3b_bld.gd. Same printing language as faction_m_bld.gd: raw grey walls printed to the stage height
## with a glowing print line, a cyan hologram lattice of the final volume, team beacon + team panels.
## Built look: a server hall with rows of blinking rack LEDs, a hex compute core with an eye, coolant
## coils with cyan caps and a roof rack module.
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const BD = preload("res://tools/art/faction_m_bdress.gd")


## [kind, cx, cy, z, hx|r, hy|squash, hz, colour, role]; kind = "box" | "hex".
static func parts(def: String) -> Array:
	match def:
		"m_compute_node":
			return [["box", 0.18, 0.16, 2, 0.6, 0.58, 14, L.GRAPH, "main"],
				["hex", -0.5, -0.46, 2, 0.3, 1.0, 26, L.PANEL, "tower"],
				["hex", -0.5, -0.46, 28, 0.17, 1.0, 6, L.GRAPH_D, "crown"],
				["hex", 0.66, -0.62, 2, 0.12, 1.0, 20, L.PANEL, "coil"],
				["hex", -0.66, 0.62, 2, 0.12, 1.0, 17, L.PANEL, "coil"],
				["box", 0.22, 0.18, 16, 0.3, 0.28, 5, L.PANEL_D, "module"]]
	return []


static func draw(cv, def: String, size: int, o: Vector2, st: int) -> void:
	var half := size * 0.5 - 0.05
	var hk: float = [1.0, 0.0, 0.45, 0.85][st]
	var raw := st > 0
	var ps := parts(def)
	ps.sort_custom(func(a, b):
		var la := 1 if a[3] > 4 else 0
		var lb := 1 if b[3] > 4 else 0
		if la != lb:
			return la < lb
		return a[1] + a[2] + a[3] * 0.001 < b[1] + b[2] + b[3] * 0.001)
	if hk > 0.0:
		for p in ps:
			var c := Vector3(p[1], p[2], p[3])
			if p[0] == "hex":
				L.hex_shadow(cv, o, c, p[4], p[6] * hk, 0.0, p[5])
			else:
				P.box_shadow(cv, o, c, p[4], p[5], p[6] * hk, 0.0)
	cv.flush_shadow()
	var slab: Dictionary = P.box(cv, o, Vector3(0, 0, 0), half, half, 2.0, 0.0, L.SLAB if not raw else P.mul(L.SLAB, 0.92), 0.1, 1005)
	BD.slab_pattern(cv, slab.top, size, raw)
	B.edges(cv, slab, L.SLAB)
	for p in ps:
		var hz: float = p[6] * hk
		var c := Vector3(p[1], p[2], p[3])
		if raw and p[3] > 4:
			c.z = p[3] * hk
			if st < 3:
				hz = 0.0
		if hz < 1.0:
			continue
		var col: Color = p[7]
		if raw:
			col = P.mix(col, L.RAW, 0.55)
		var r: Dictionary
		if p[0] == "hex":
			r = L.hexp(cv, o, c, p[4], hz, 0.0, col, 1050 + int(p[4] * 10), null, p[5])
		else:
			r = P.box(cv, o, c, p[4], p[5], hz, 0.0, col, 0.07, 1050 + int(p[4] * 10))
		B.wall_ao(cv, r, 0.3 if p[3] <= 4 else 0.18)
		if raw:
			for sd in r.sides:
				L.seam(cv, sd.quad, 1.0)
			L.rims(cv, r, col)
		else:
			BD.dress(cv, o, def, p, r)
			if p[8] == "main":
				_racks(cv, r)
	if raw:
		BD.printers(cv, o, size, st)
	else:
		_conduits(cv, o)
	BD.beacon(cv, o, half, raw)
	cv.outline(Color(0.07, 0.08, 0.09, 1))
	if raw:
		for p in ps:
			var c := Vector3(p[1], p[2], p[3])
			if p[0] == "hex":
				BD.holo_hex(cv, o, c, p[4], p[6], p[5])
			else:
				L.holo_box(cv, o, c, p[4], p[5], p[6], 0.5)


## Server-rack bays on each wall: dark recess, vertical rack dividers, a deterministic LED pattern.
static func _racks(cv, r: Dictionary) -> void:
	var k := 0
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		var bay := P.sub(q, 0.1, 0.22, 0.9, 0.62)
		cv.poly(bay, Color8(22, 26, 30))
		var n := maxi(3, int(q[0].distance_to(q[1]) / 5.0))
		for i in n + 1:
			var u := float(i) / n
			cv.line_v(bay[0].lerp(bay[1], u), bay[3].lerp(bay[2], u), Color8(58, 64, 70))
		for i in n:
			for j in 3:
				var h := P.hi(i + k * 31, j, 1077, 5)
				if h == 0:
					continue
				var pt: Vector2 = bay[0].lerp(bay[1], (i + 0.5) / n).lerp(bay[3].lerp(bay[2], (i + 0.5) / n), 0.25 + j * 0.25)
				cv.px(int(pt.x), int(pt.y), L.CYAN if h > 2 else (L.TEAL if h == 2 else Color8(255, 176, 70)))
		k += 1


## Coolant conduits from the coils into the hall.
static func _conduits(cv, o: Vector2) -> void:
	B.pipe(cv, o, Vector3(0.66, -0.62, 6), Vector3(0.5, -0.3, 6), Color8(70, 78, 86))
	B.pipe(cv, o, Vector3(-0.66, 0.62, 6), Vector3(-0.3, 0.5, 6), Color8(70, 78, 86))
