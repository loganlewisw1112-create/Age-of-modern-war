extends RefCounted
## Machine buildings (agent ART3-M): built look + 3 fabrication stages, each with a team mask.
## Same canvas/pivot convention as buildings.gd (w = size*64+12, pivot = footprint centre).
## Construction is additive printing: a cyan hologram lattice of the final volume, walls printed in raw
## grey up to the stage height with a glowing print line on top.
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const BD = preload("res://tools/art/faction_m_bdress.gd")

const SIZES := {"m_core": 3, "m_charging_hub": 2, "m_reprocessor": 3, "m_assembler": 3, "m_crawler_works": 3,
	"m_sensor_relay": 1, "m_sentry": 1}
const TOPS := {"m_core": 74, "m_charging_hub": 52, "m_reprocessor": 60, "m_assembler": 54, "m_crawler_works": 60,
	"m_sensor_relay": 66, "m_sentry": 40}
const STATES := ["built", "build_0", "build_1", "build_2"]


static func build(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("buildings", {})
	for def in SIZES:
		var size: int = SIZES[def]
		var w := size * 64 + 12
		var top: int = TOPS[def]
		var o := Vector2(w / 2, top + size * 16)
		var hgt := int(o.y) + size * 16 + 6
		var entry := {"size": size, "pivot": [int(o.x), int(o.y)], "states": {}}
		for st in STATES.size():
			var cv = P.Canvas.new(w, hgt)
			draw(cv, def, size, o, st)
			var nm: String = STATES[st]
			out.images["buildings/%s_%s.png" % [def, nm]] = cv.img
			out.images["buildings/%s_%s_mask.png" % [def, nm]] = cv.mask
			entry.states[nm] = {"file": "buildings/%s_%s.png" % [def, nm], "mask": "buildings/%s_%s_mask.png" % [def, nm]}
		man[def] = entry
	out.manifest["buildings"] = man


## Part list: [kind, cx, cy, z, hx|r, hy|squash, hz, colour, role]. kind = "box" | "hex".
static func parts(def: String) -> Array:
	match def:
		"m_core":
			return [["box", 0.1, 0.1, 2, 1.1, 1.0, 16, L.GRAPH, "main"], ["hex", -0.1, -0.1, 18, 0.62, 1.0, 18, L.PANEL, "tower"],
				["hex", -0.1, -0.1, 36, 0.34, 1.0, 8, L.GRAPH_D, "crown"], ["box", 1.22, -0.9, 2, 0.08, 0.08, 24, L.GRAPH_D, "pylon"],
				["box", -0.9, 1.22, 2, 0.08, 0.08, 24, L.GRAPH_D, "pylon"], ["hex", 1.12, 0.62, 2, 0.26, 1.0, 3, L.PANEL_D, "pad"]]
		"m_charging_hub":
			return [["box", 0.12, 0.12, 2, 0.62, 0.62, 5, L.GRAPH, "base"], ["hex", -0.5, -0.5, 2, 0.15, 1.0, 32, L.PANEL, "coil"],
				["hex", 0.52, -0.55, 2, 0.12, 1.0, 24, L.PANEL, "coil"], ["hex", -0.55, 0.52, 2, 0.12, 1.0, 24, L.PANEL, "coil"],
				["hex", 0.14, 0.14, 7, 0.4, 1.0, 2, L.PANEL_D, "pad"]]
		"m_reprocessor":
			return [["box", 0.3, 0.22, 2, 0.75, 0.72, 16, L.GRAPH, "main"], ["box", -0.88, -0.2, 2, 0.34, 0.55, 12, L.PANEL, "hopper"],
				["hex", -0.6, 0.95, 2, 0.32, 1.0, 18, L.PANEL, "tank"], ["hex", 0.95, -0.9, 2, 0.3, 1.0, 22, L.PANEL, "tank"],
				["hex", 0.55, 0.2, 18, 0.14, 1.0, 16, L.GRAPH_D, "vent"], ["box", -0.25, -1.0, 2, 0.5, 0.1, 6, L.GRAPH_D, "belt"]]
		"m_assembler":
			return [["box", -0.05, -0.05, 2, 1.15, 1.05, 18, L.GRAPH, "hall"], ["hex", -0.35, -0.3, 20, 0.5, 1.0, 8, L.PANEL, "roofhex"],
				["box", 0.62, 0.45, 20, 0.32, 0.34, 6, L.PANEL_D, "module"], ["hex", 1.18, -0.85, 2, 0.24, 1.0, 2, L.PANEL_D, "pad"]]
		"m_crawler_works":
			return [["box", -0.15, -0.1, 2, 1.1, 1.05, 22, L.GRAPH, "hangar"], ["box", -0.15, -0.1, 24, 0.94, 0.9, 3, L.PANEL, "roof"],
				["box", 1.22, -0.92, 2, 0.06, 0.06, 30, L.GRAPH_D, "gantry"], ["box", 1.22, 0.92, 2, 0.06, 0.06, 30, L.GRAPH_D, "gantry"],
				["box", 1.22, 0.0, 30, 0.07, 0.98, 3, L.GRAPH_D, "beam"]]
		"m_sensor_relay":
			return [["hex", 0.0, 0.0, 2, 0.38, 1.0, 6, L.GRAPH, "base"], ["box", 0.0, 0.0, 8, 0.06, 0.06, 32, L.GRAPH_D, "mast"],
				["hex", 0.0, 0.0, 40, 0.18, 1.0, 6, L.PANEL, "head"]]
		"m_sentry":
			return [["hex", 0.0, 0.0, 2, 0.4, 1.0, 8, L.GRAPH, "base"], ["hex", 0.0, 0.0, 10, 0.24, 0.85, 6, L.PANEL, "turret"]]
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
	# foundation slab with a hex-tile pattern
	var slab: Dictionary = P.box(cv, o, Vector3(0, 0, 0), half, half, 2.0, 0.0, L.SLAB if not raw else P.mul(L.SLAB, 0.92), 0.1, 5)
	BD.slab_pattern(cv, slab.top, size, raw)
	B.edges(cv, slab, L.SLAB)
	for p in ps:
		var hz: float = p[6] * hk
		var c := Vector3(p[1], p[2], p[3])
		if raw and p[3] > 4:
			c.z = p[3] * hk  # upper modules ride on the partly printed walls; printed last
			if st < 3:
				hz = 0.0
		if hz >= 1.0:
			var col: Color = p[7]
			if raw:
				col = P.mix(col, L.RAW, 0.55)
			var r: Dictionary
			if p[0] == "hex":
				r = L.hexp(cv, o, c, p[4], hz, 0.0, col, 50 + int(p[4] * 10), null, p[5])
			else:
				r = P.box(cv, o, c, p[4], p[5], hz, 0.0, col, 0.07, 50 + int(p[4] * 10))
			B.wall_ao(cv, r, 0.3 if p[3] <= 4 else 0.18)
			if raw:
				for sd in r.sides:
					L.seam(cv, sd.quad, 1.0)  # print line
				L.rims(cv, r, col)
			else:
				BD.dress(cv, o, def, p, r)
	if not raw:
		BD.post(cv, o, def)
	else:
		BD.printers(cv, o, size, st)
	BD.beacon(cv, o, half, raw)
	cv.outline(Color(0.07, 0.08, 0.09, 1))
	if raw:  # hologram lattice of the final volume (after the outline: translucent, no dark ring)
		for p in ps:
			var c := Vector3(p[1], p[2], p[3])
			if p[0] == "hex":
				BD.holo_hex(cv, o, c, p[4], p[6], p[5])
			else:
				L.holo_box(cv, o, c, p[4], p[5], p[6], 0.5)
