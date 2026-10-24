extends RefCounted
## G3b buildings (agent ART4-2): research + comms structures for Human A and Human B, built look + 3
## construction stages with team masks. Same canvas/pivot conventions as buildings.gd
## (w = size*64+12, pivot = footprint centre, h = pivot.y + size*16 + 6) and the same box dressing
## (bdress.gd for A, faction_b_bdress.gd for B). The Machine compute node lives in g3b_bld_m.gd.
## Extras per building: an instrument dish (research station), lattice masts with whips, guy wires and
## a red aviation lamp (comms tower, signal mast), a north-light skylight (drafting office).
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const BLD = preload("res://tools/art/buildings.gd")
const FBB = preload("res://tools/art/faction_b_bld.gd")
const RA = preload("res://tools/art/bdress.gd")
const RB = preload("res://tools/art/faction_b_bdress.gd")
const G = preload("res://tools/art/g3b_lib.gd")
const BM = preload("res://tools/art/g3b_bld_m.gd")

## def -> [faction key "a" | "b" | "m", footprint size, canvas headroom above the footprint]
const SPEC := {"research_station": ["a", 2, 64], "comms_tower": ["a", 1, 96],
	"b_drafting_office": ["b", 2, 60], "b_signal_mast": ["b", 1, 96], "m_compute_node": ["m", 2, 58]}
const STATES := ["built", "build_0", "build_1", "build_2"]
const CYL_A := ["tank", "column", "drum"]
const CYL_B := ["stack", "boiler", "furnace", "drum"]
const LAMP := Color8(232, 58, 40)


static func build(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("buildings", {})
	for def in SPEC:
		var fk: String = SPEC[def][0]
		var size: int = SPEC[def][1]
		var w := size * 64 + 12
		var o := Vector2(w / 2, int(SPEC[def][2]) + size * 16)
		var hgt := int(o.y) + size * 16 + 6
		var entry := {"size": size, "pivot": [int(o.x), int(o.y)], "states": {}}
		for st in STATES.size():
			var cv = P.Canvas.new(w, hgt)
			if fk == "m":
				BM.draw(cv, def, size, o, st)
			else:
				draw(cv, def, size, o, st, fk == "b")
			var nm: String = STATES[st]
			out.images["buildings/%s_%s.png" % [def, nm]] = cv.img
			out.images["buildings/%s_%s_mask.png" % [def, nm]] = cv.mask
			entry.states[nm] = {"file": "buildings/%s_%s.png" % [def, nm], "mask": "buildings/%s_%s_mask.png" % [def, nm]}
		man[def] = entry
	out.manifest["buildings"] = man


## [cx, cy, z, hx, hy, hz, colour, role] in local tiles centred on the footprint (cylinders: hx = radius).
static func parts(def: String) -> Array:
	match def:
		"research_station":
			return [[0.22, 0.18, 2, 0.6, 0.55, 17, BLD.CONCRETE, "main"],
				[-0.45, -0.4, 2, 0.34, 0.32, 27, P.mul(BLD.CONCRETE, 0.93), "upper"],
				[-0.62, 0.55, 2, 0.17, 0.17, 15, BLD.TANK, "tank"], [-0.32, 0.78, 2, 0.06, 0.06, 7, BLD.DRUM_G, "drum"],
				[0.86, -0.62, 2, 0.06, 0.22, 4, BLD.JERSEY, "barrier"], [0.62, -0.86, 2, 0.12, 0.1, 6, BLD.WOOD, "crate"]]
		"comms_tower":
			return [[0.14, 0.16, 2, 0.27, 0.25, 11, BLD.OLIVE, "main"], [-0.22, -0.22, 2, 0.17, 0.17, 4, BLD.SLAB, "footing"],
				[0.36, -0.3, 2, 0.06, 0.06, 7, BLD.DRUM_R, "drum"]]
		"b_drafting_office":
			return [[0.18, 0.12, 2, 0.62, 0.6, 18, FBB.BRICK, "brick"], [-0.58, -0.42, 2, 0.3, 0.42, 12, FBB.IRON, "shed"],
				[-0.78, 0.6, 2, 0.1, 0.1, 42, FBB.BRICK_D, "stack"], [0.84, -0.74, 2, 0.06, 0.06, 7, FBB.DRUM_R, "drum"],
				[0.84, -0.56, 2, 0.06, 0.06, 7, FBB.DRUM_O, "drum"], [0.26, 0.9, 2, 0.42, 0.07, 5, FBB.SAND, "sandbag"]]
		"b_signal_mast":
			return [[0.14, 0.16, 2, 0.27, 0.25, 12, FBB.BRICK, "brick"], [-0.22, -0.22, 2, 0.17, 0.17, 5, FBB.STEEL, "plate"],
				[0.38, -0.3, 2, 0.06, 0.06, 7, FBB.DRUM_O, "drum"]]
	return []


static func draw(cv, def: String, size: int, o: Vector2, st: int, fb: bool) -> void:
	var half := size * 0.5 - 0.05
	var hk: float = [1.0, 0.0, 0.45, 0.85][st]
	var raw := st > 0
	var cyl: Array = CYL_B if fb else CYL_A
	var ps := parts(def)
	ps.sort_custom(func(a, b):
		var la := 1 if a[2] > 4 else 0
		var lb := 1 if b[2] > 4 else 0
		if la != lb:
			return la < lb
		return a[0] + a[1] + a[2] * 0.001 < b[0] + b[1] + b[2] * 0.001)
	if hk > 0.0:
		for p in ps:
			P.box_shadow(cv, o, Vector3(p[0], p[1], p[2]), p[3] * (0.85 if p[7] in cyl else 1.0), p[4], p[5] * hk, 0.0)
		_mast_shadow(cv, o, def, hk)
	cv.flush_shadow()
	var slab_c: Color = FBB.SLAB if fb else BLD.SLAB
	var slab: Dictionary = P.box(cv, o, Vector3(0, 0, 0), half, half, 2.0, 0.0, slab_c if not raw else P.mul(slab_c, 0.9), 0.13, 905)
	if raw:
		for i in size * 10:
			var u := P.hn(i, size, 941)
			var v := P.hn(i, size, 942)
			var q := P.sub(slab.top, u, v, u + 0.02, v + 0.02)
			cv.px(int(q[0].x), int(q[0].y), Color8(96, 58, 40) if fb else Color8(84, 62, 46))
		if fb:
			FBB._girders(cv, o, half, st)
	else:
		B.edges(cv, slab, slab_c)
		if fb:
			RB.oil_stains(cv, slab.top, 906 + size)
	for p in ps:
		var hz: float = p[5] * hk
		if hz < 1.0:
			continue
		var col: Color = p[6]
		if raw:
			col = P.mix(col, Color8(150, 144, 130), 0.42)
		var role := String(p[7])
		var c := Vector3(p[0], p[1], p[2])
		if role in cyl:
			var top := B.cyl(cv, o, c, p[3], hz, col, 950 + int(p[3] * 100), 0.72 if role == "tank" and not raw else -1.0,
				2 if role == "tank" else 0)
			if fb and not raw:
				RB.cyl_dress(cv, o, def, role, c, p[3], hz, top)
			continue
		var r: Dictionary = P.box(cv, o, c, p[3], p[4], hz, 0.0, col, 0.09, 970 + int(p[3] * 10))
		B.wall_ao(cv, r, 0.3 if p[2] <= 4 else 0.18)
		if raw:
			if role in ["main", "upper", "brick", "shed"]:
				BLD._scaffold(cv, r)
			continue
		if fb:
			RB.dress(cv, o, def, role, p, r, col)
		else:
			RA.dress(cv, o, def, p, r, col)
		_dress(cv, o, def, role, p, r, col)
	if not raw:
		_roof_kit(cv, o, def)
	_flag(cv, o, half, raw, fb)
	cv.outline(Color(0.09, 0.085, 0.075, 1))
	_masts(cv, o, def, hk, raw, fb)


## Per-building wall dressing on top of the faction dressing (windows / doors / skylights).
static func _dress(cv, o: Vector2, def: String, role: String, p: Array, r: Dictionary, col: Color) -> void:
	var s := int(p[0] * 100 + p[1] * 37) + 990
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		var face := RA._face(sd)
		var n := maxi(2, int(q[0].distance_to(q[1]) / 9.0))
		match def + ":" + role:
			"research_station:main":
				B.window_row(cv, q, 0.4, 0.68, n + 1, col, s, 0.55)
				if face == "y":
					B.door(cv, q, 0.66, 0.8, 0.36, col)
			"research_station:upper":
				B.window_row(cv, q, 0.58, 0.74, n, col, s + 1, 0.4)
				cv.poly(P.sub(q, 0.1, 0.18, 0.9, 0.24), Color8(214, 214, 206))  # white instrument band
			"comms_tower:main", "b_signal_mast:brick":
				if face == "y":
					B.door(cv, q, 0.3, 0.62, 0.62, col)
				else:
					B.window_row(cv, q, 0.42, 0.66, 2, col, s + 2, 0.6)
			"b_drafting_office:brick":
				B.window_row(cv, q, 0.22, 0.4, n, Color8(84, 80, 72), s + 3, 0.5)
	if def == "b_drafting_office" and role == "brick":
		# north-light skylight: a glazed ridge strip down the tar roof
		var g := P.sub(r.top, 0.22, 0.3, 0.78, 0.52)
		cv.poly(g, BLD.GLASS)
		for u in [0.2, 0.4, 0.6, 0.8]:
			cv.line_v(g[0].lerp(g[1], u), g[3].lerp(g[2], u), Color8(120, 130, 132))
		cv.line_v(g[3], g[2], B.GLASS_HI)


## Rooftop instruments drawn before the outline: dish and whips.
static func _roof_kit(cv, o: Vector2, def: String) -> void:
	match def:
		"research_station":
			var base := P.proj(o, Vector3(-0.45, -0.4, 29))
			cv.line_v(base, base + Vector2(0, -6), Color8(70, 72, 70))
			G.dish(cv, o, Vector3(-0.45, -0.4, 38), 0.55, 9.0, Color8(206, 206, 198))
			G.whip(cv, P.proj(o, Vector3(0.5, 0.1, 19)), 12, LAMP)
			B.hvac(cv, o, Vector3(0.1, 0.3, 19), 0.16, 0.14, 991)
		"b_drafting_office":
			G.whip(cv, P.proj(o, Vector3(0.6, -0.2, 20)), 10, LAMP)


static func _flag(cv, o: Vector2, half: float, raw: bool, fb: bool) -> void:
	var base := P.proj(o, Vector3(-half + 0.12, half - 0.12, 2))
	var ph := 30 if not raw else 12
	cv.line(int(base.x), int(base.y), int(base.x), int(base.y) - ph, Color8(62, 56, 50) if fb else Color8(60, 60, 56))
	cv.team = true
	var fw := 10 if not raw else 5
	for yy in (6 if not raw else 4):
		for xx in fw:
			var wave := int(round(sin(xx * 0.7) * 0.8))
			cv.px(int(base.x) + 1 + xx, int(base.y) - ph + yy + wave, Color(0.85, 0.85, 0.85) if yy > 0 else Color(1, 1, 1))
	cv.team = false


const MAST_FOOT := Vector2(-0.22, -0.22)
const MAST_H := 76.0


static func _mast_shadow(cv, o: Vector2, def: String, hk: float) -> void:
	if def in ["comms_tower", "b_signal_mast"]:
		P.box_shadow(cv, o, Vector3(MAST_FOOT.x, MAST_FOOT.y, 2), 0.08, 0.08, MAST_H * hk * 0.5, 0.0)


## Lattice mast (after the outline so the bracing stays open), guy wires, whips, dish, red lamp.
static func _masts(cv, o: Vector2, def: String, hk: float, raw: bool, fb: bool) -> void:
	if not def in ["comms_tower", "b_signal_mast"] or hk <= 0.0:
		return
	var z0 := 6.0
	var h := MAST_H * hk
	var a := P.proj(o, Vector3(MAST_FOOT.x, MAST_FOOT.y, z0))
	var b := P.proj(o, Vector3(MAST_FOOT.x, MAST_FOOT.y, z0 + h))
	var steel := Color8(150, 92, 56) if fb else Color8(176, 176, 168)
	var dark := Color8(40, 36, 32)
	# dark backing pass one px right so the light rails read on bright ground
	G.lattice(cv, a + Vector2(1, 0), b + Vector2(1, 0), 3.0, dark)
	G.lattice(cv, a, b, 3.0, steel)
	if fb and not raw:  # riveted joints on the rust mast
		for i in int(h / 8.0):
			var t := P.proj(o, Vector3(MAST_FOOT.x, MAST_FOOT.y, z0 + 4 + i * 8.0))
			cv.px(int(t.x) - 3 + i % 2, int(t.y), Color8(200, 140, 90))
	if raw:
		cv.line_v(b + Vector2(-4, 0), b + Vector2(4, 0), Color8(140, 116, 78))  # build platform
		return
	# guy wires to three ground anchors
	for g in [Vector3(0.42, -0.42, 2), Vector3(-0.42, 0.42, 2), Vector3(-0.44, -0.44, 2)]:
		B.cable(cv, P.proj(o, Vector3(MAST_FOOT.x, MAST_FOOT.y, z0 + h * 0.62)), P.proj(o, g), 1.0, Color8(58, 58, 54))
	if fb:
		# crossarm with insulator pots + two long whips
		var arm := P.proj(o, Vector3(MAST_FOOT.x, MAST_FOOT.y, z0 + h * 0.86))
		cv.line_v(arm + Vector2(-7, 0), arm + Vector2(7, 0), Color8(88, 64, 46))
		for dx in [-6, -2, 2, 6]:
			cv.px(int(arm.x) + dx, int(arm.y) - 1, Color8(222, 218, 200))
		G.whip(cv, b + Vector2(-2, 0), 10, LAMP)
		G.whip(cv, b + Vector2(2, 1), 7, LAMP)
	else:
		var dz := z0 + h * 0.66
		G.dish(cv, o, Vector3(MAST_FOOT.x + 0.1, MAST_FOOT.y + 0.1, dz), 0.8, 5.0, Color8(214, 214, 206))
		var pod := P.proj(o, Vector3(MAST_FOOT.x, MAST_FOOT.y, z0 + h * 0.84))
		cv.rect(int(pod.x) - 4, int(pod.y) - 3, 2, 6, Color8(196, 196, 188))  # panel antennas
		cv.rect(int(pod.x) + 3, int(pod.y) - 3, 2, 6, Color8(176, 176, 168))
		G.whip(cv, b, 9, LAMP)
	cv.px(int(b.x), int(b.y) - 1, LAMP)
	cv.px(int(b.x) + 1, int(b.y) - 1, P.mul(LAMP, 0.8))
	cv.px(int(b.x), int(b.y) - 2, Color(1.0, 0.55, 0.45, 0.6))
