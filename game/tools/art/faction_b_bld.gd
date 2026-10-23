extends RefCounted
## Human B (Industrial) buildings (agent ART3-B): built look + 3 construction stages, each with a
## team mask, same canvas/pivot conventions as buildings.gd (w = size*64+12, pivot = footprint centre).
## Brick halls, corrugated-iron sheds, sooty brick smokestacks, riveted boilers, a blast furnace,
## scrap piles, sandbags and a concrete bunker. Dressing lives in faction_b_bdress.gd.
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const BLD = preload("res://tools/art/buildings.gd")
const R = preload("res://tools/art/faction_b_bdress.gd")

const SIZES := {"b_works": 3, "b_boiler": 2, "b_salvage_yard": 2, "b_barracks": 3, "b_heavy_plant": 3,
	"b_smelter": 3, "b_bunker": 2}
const TOPS := {"b_works": 84, "b_boiler": 64, "b_salvage_yard": 60, "b_barracks": 48, "b_heavy_plant": 60,
	"b_smelter": 84, "b_bunker": 34}
const STATES := ["built", "build_0", "build_1", "build_2"]
const CYL := ["stack", "boiler", "furnace", "drum"]

const BRICK := Color8(138, 76, 56)
const BRICK_D := Color8(110, 62, 48)
const IRON := Color8(120, 122, 116)
const RUSTY := Color8(134, 78, 46)
const STEEL := Color8(92, 94, 92)
const CONCRETE := Color8(128, 124, 112)
const SLAB := Color8(104, 100, 92)
const SAND := Color8(146, 128, 92)
const SLAG := Color8(78, 72, 66)
const DRUM_R := Color8(132, 62, 46)
const DRUM_O := Color8(98, 92, 60)


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


## [cx, cy, z, hx, hy, hz, colour, role] in local tiles centred on the footprint (cylinders: hx = radius).
static func parts(def: String) -> Array:
	match def:
		"b_works":
			return [[-1.0, -0.95, 2, 0.17, 0.17, 66, BRICK_D, "stack"], [-0.5, -1.1, 2, 0.13, 0.13, 50, BRICK_D, "stack"],
				[0.15, 0.1, 2, 1.05, 0.95, 22, BRICK, "brick"], [-0.45, -0.35, 24, 0.45, 0.42, 11, IRON, "shed"],
				[1.28, -0.7, 2, 0.06, 0.06, 7, DRUM_R, "drum"], [1.3, -0.52, 2, 0.06, 0.06, 7, DRUM_O, "drum"],
				[-0.3, 1.28, 2, 0.55, 0.09, 5, SAND, "sandbag"], [1.25, 0.6, 2, 0.14, 0.3, 5, RUSTY, "scrap"]]
		"b_boiler":
			return [[-0.5, -0.62, 2, 0.12, 0.12, 50, BRICK_D, "stack"], [-0.42, 0.05, 2, 0.3, 0.3, 20, STEEL, "boiler"],
				[0.3, 0.15, 2, 0.48, 0.58, 14, BRICK, "brick"], [0.62, -0.68, 2, 0.06, 0.06, 7, DRUM_R, "drum"]]
		"b_salvage_yard":
			return [[-0.5, -0.5, 2, 0.06, 0.06, 42, STEEL, "magnet"], [0.35, -0.45, 2, 0.32, 0.28, 6, RUSTY, "scrap"],
				[-0.45, 0.35, 2, 0.36, 0.3, 7, RUSTY, "scrap"], [0.38, 0.32, 2, 0.45, 0.42, 13, IRON, "shed"]]
		"b_barracks":
			return [[-1.15, -1.15, 2, 0.09, 0.09, 30, BRICK_D, "stack"], [-0.2, -0.58, 2, 1.05, 0.45, 15, BRICK, "brick"],
				[-0.2, 0.5, 2, 1.05, 0.42, 15, BRICK, "brick"], [1.24, -0.1, 2, 0.1, 0.95, 6, SAND, "sandbag"],
				[-0.25, 1.26, 2, 0.8, 0.08, 5, SAND, "sandbag"]]
		"b_heavy_plant":
			return [[-1.08, -1.05, 2, 0.15, 0.15, 56, BRICK_D, "stack"], [-0.05, -0.05, 2, 1.15, 1.05, 22, IRON, "sawtooth"],
				[1.3, 0.75, 2, 0.06, 0.06, 7, DRUM_R, "drum"], [1.3, 0.92, 2, 0.06, 0.06, 7, DRUM_O, "drum"]]
		"b_smelter":
			return [[-0.5, -0.5, 2, 0.5, 0.5, 42, BRICK_D, "furnace"], [-1.08, 0.6, 2, 0.15, 0.15, 66, BRICK_D, "stack"],
				[0.75, -0.75, 2, 0.32, 0.3, 6, SLAG, "scrap"], [0.55, 0.5, 2, 0.6, 0.55, 14, IRON, "shed"],
				[-0.45, 1.25, 2, 0.06, 0.06, 7, DRUM_R, "drum"]]
		"b_bunker":
			return [[0.0, 0.0, 2, 0.72, 0.68, 10, CONCRETE, "bunker"], [-0.12, -0.12, 12, 0.42, 0.4, 3, STEEL, "plate"],
				[0.95, 0.0, 2, 0.08, 0.62, 5, SAND, "sandbag"], [0.0, 0.95, 2, 0.62, 0.08, 5, SAND, "sandbag"]]
	return []


static func draw(cv, def: String, size: int, o: Vector2, st: int) -> void:
	var half := size * 0.5 - 0.05
	var hk: float = [1.0, 0.0, 0.45, 0.85][st]
	var raw := st > 0
	var ps := parts(def)
	ps.sort_custom(func(a, b):
		var la := 1 if a[2] > 4 else 0
		var lb := 1 if b[2] > 4 else 0
		if la != lb:
			return la < lb
		return a[0] + a[1] + a[2] * 0.001 < b[0] + b[1] + b[2] * 0.001)
	if hk > 0.0:
		for p in ps:
			P.box_shadow(cv, o, Vector3(p[0], p[1], p[2]), p[3] * (0.85 if p[7] in CYL else 1.0), p[4], p[5] * hk, 0.0)
	cv.flush_shadow()
	var slab: Dictionary = P.box(cv, o, Vector3(0, 0, 0), half, half, 2.0, 0.0, SLAB if not raw else P.mul(SLAB, 0.9), 0.14, 805)
	if raw:
		for i in size * 10:
			var u := P.hn(i, size, 841)
			var v := P.hn(i, size, 842)
			var q := P.sub(slab.top, u, v, u + 0.02, v + 0.02)
			cv.px(int(q[0].x), int(q[0].y), Color8(96, 58, 40))  # rusty rebar stubs
		_girders(cv, o, half, st)
	else:
		B.edges(cv, slab, SLAB)
		R.oil_stains(cv, slab.top, 806 + size)
	for p in ps:
		var hz: float = p[5] * hk
		if hz < 1.0:
			continue
		var col: Color = p[6]
		if raw:
			col = P.mix(col, Color8(150, 140, 126), 0.4)
		var role := String(p[7])
		var c := Vector3(p[0], p[1], p[2])
		if role in CYL:
			var band := -1.0
			if not raw and role in ["boiler", "furnace"]:
				band = 0.78
			var seams := 3 if role == "boiler" else (2 if role == "furnace" else 0)
			var top := B.cyl(cv, o, c, p[3], hz, col, 850 + int(p[3] * 100), band, seams)
			if not raw:
				R.cyl_dress(cv, o, def, role, c, p[3], hz, top)
			continue
		if role == "scrap":
			R.scrap_pile(cv, o, c, p[3], p[4], hz, col, 860 + int(p[0] * 10), raw)
			continue
		var r: Dictionary = P.box(cv, o, c, p[3], p[4], hz, 0.0, col, 0.09, 870 + int(p[3] * 10))
		B.wall_ao(cv, r, 0.3 if p[2] <= 4 else 0.18)
		if not raw:
			R.dress(cv, o, def, role, p, r, col)
		elif role != "sandbag":
			BLD._scaffold(cv, r)
	if not raw:
		R.post(cv, o, def)
	# team flag on a pole at the front-left corner (stake while under construction)
	var base := P.proj(o, Vector3(-half + 0.12, half - 0.12, 2))
	var ph := 34 if not raw else 12
	cv.line(int(base.x), int(base.y), int(base.x), int(base.y) - ph, Color8(62, 56, 50))
	cv.team = true
	var fw := 11 if not raw else 5
	for yy in (6 if not raw else 4):
		for xx in fw:
			var wave := int(round(sin(xx * 0.7) * 0.8))
			cv.px(int(base.x) + 1 + xx, int(base.y) - ph + yy + wave, Color(0.85, 0.85, 0.85) if yy > 0 else Color(1, 1, 1))
	cv.team = false
	cv.outline(Color(0.09, 0.08, 0.07, 1))


## Construction site clutter: a stack of rusty I-beams and a stack of bricks on the slab.
static func _girders(cv, o: Vector2, half: float, st: int) -> void:
	var gx := half * 0.55
	var gy := -half * 0.35
	for i in 3 - mini(st - 1, 2):
		var g: Dictionary = P.box(cv, o, Vector3(gx, gy + i * 0.09, 2 + i * 2.0), 0.42, 0.035, 2.0, 0.0, P.mul(RUSTY, 0.9 + i * 0.06), 0.1, 880 + i)
		cv.line_v(g.top[0], g.top[1], P.mul(RUSTY, 1.25))
	var bp: Dictionary = P.box(cv, o, Vector3(-half * 0.45, half * 0.5, 2), 0.16, 0.14, 4.0 + st, 0.0, BRICK, 0.1, 884)
	for sd in bp.sides:
		R.brick_tex(cv, sd.quad, 885)
