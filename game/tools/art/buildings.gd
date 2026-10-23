extends RefCounted
## Buildings: built look + 3 construction stages, each with a team mask. Footprint-sized base diamond.
## E2 detail pass: framed/lit windows, doors, roll-up gates, rooftop clutter, props (sandbags, barriers,
## crates, drums, transformer + cables, tower lamps), edge highlights and wall-base AO (bdress.gd /
## bdetail.gd). Canvas sizes and pivots of the G1 buildings are unchanged. New: refinery (3x3).
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const R = preload("res://tools/art/bdress.gd")

const SIZES := {"hq": 3, "generator": 2, "depot": 2, "barracks": 3, "motor_pool": 3, "guard_tower": 1, "refinery": 3}
const TOPS := {"hq": 72, "generator": 52, "depot": 40, "barracks": 40, "motor_pool": 48, "guard_tower": 64, "refinery": 68}
const STATES := ["built", "build_0", "build_1", "build_2"]
const CYLINDERS := ["tank", "column", "drum"]

const CONCRETE := Color8(134, 130, 118)
const SLAB := Color8(112, 110, 102)
const OLIVE := Color8(98, 100, 72)
const STEEL := Color8(92, 96, 98)
const RUST := Color8(128, 82, 52)
const GLASS := Color8(36, 42, 46)
const WOOD := Color8(128, 104, 70)
const SAND := Color8(150, 134, 98)
const JERSEY := Color8(160, 156, 144)
const TANK := Color8(170, 168, 158)
const DRUM_R := Color8(132, 62, 46)
const DRUM_G := Color8(84, 96, 62)


static func build(out: Dictionary) -> void:
	var man := {}
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


## Box list per building: [cx, cy, z, hx, hy, hz, colour, role]. Local tiles centred on the footprint.
## Cylinder roles (tank/column/drum) use hx as the radius.
static func parts(def: String) -> Array:
	match def:
		"hq":
			return [[0.05, 0.05, 2, 1.1, 1.0, 24, CONCRETE, "main"], [-0.25, -0.2, 26, 0.6, 0.55, 14, P.mul(CONCRETE, 0.95), "upper"],
				[0.55, -0.6, 26, 0.05, 0.05, 30, STEEL, "mast"], [1.25, 0.2, 2, 0.12, 0.7, 6, SAND, "sandbag"],
				[-0.55, 1.25, 2, 0.3, 0.1, 5, SAND, "sandbag"], [0.78, 1.25, 2, 0.26, 0.1, 5, SAND, "sandbag"],
				[1.3, -0.75, 2, 0.06, 0.2, 4, JERSEY, "barrier"]]
		"generator":
			return [[-0.3, -0.25, 2, 0.16, 0.16, 30, P.mul(STEEL, 0.9), "stack"], [-0.3, 0.25, 2, 0.16, 0.16, 26, P.mul(STEEL, 0.9), "stack"],
				[0.2, 0.0, 2, 0.45, 0.7, 16, RUST, "main"], [0.75, -0.5, 2, 0.08, 0.08, 18, STEEL, "pole"], [0.75, 0.55, 2, 0.08, 0.08, 18, STEEL, "pole"],
				[0.8, 0.02, 2, 0.1, 0.17, 9, Color8(108, 112, 104), "transformer"]]
		"depot":
			return [[-0.1, -0.05, 2, 0.75, 0.62, 16, Color8(110, 112, 104), "main"], [0.75, 0.55, 2, 0.15, 0.15, 7, WOOD, "crate"],
				[0.55, 0.75, 2, 0.13, 0.13, 6, P.mul(OLIVE, 0.9), "crate"], [0.78, 0.25, 2, 0.12, 0.12, 12, WOOD, "crate"],
				[0.12, 0.8, 2, 0.06, 0.06, 7, DRUM_R, "drum"], [0.27, 0.86, 2, 0.06, 0.06, 7, DRUM_G, "drum"],
				[-0.03, 0.87, 2, 0.06, 0.06, 7, DRUM_G, "drum"], [-0.55, 0.8, 2, 0.12, 0.1, 6, P.mul(OLIVE, 0.85), "crate"]]
		"barracks":
			return [[-0.25, -0.62, 2, 1.1, 0.42, 14, OLIVE, "main"], [-0.25, 0.42, 2, 1.1, 0.42, 14, OLIVE, "main"],
				[1.22, -0.1, 2, 0.1, 0.9, 6, SAND, "sandbag"], [1.15, 1.18, 2, 0.06, 0.2, 4, JERSEY, "barrier"]]
		"motor_pool":
			return [[-0.1, -0.1, 2, 1.15, 1.05, 22, Color8(118, 116, 106), "garage"], [1.2, 0.95, 2, 0.12, 0.12, 30, STEEL, "mast"],
				[1.28, -0.75, 2, 0.06, 0.2, 4, JERSEY, "barrier"], [1.25, 0.35, 2, 0.06, 0.06, 7, DRUM_R, "drum"],
				[1.3, 0.5, 2, 0.06, 0.06, 7, DRUM_G, "drum"]]
		"guard_tower":
			return [[-0.25, -0.25, 2, 0.04, 0.04, 26, WOOD, "leg"], [0.25, -0.25, 2, 0.04, 0.04, 26, WOOD, "leg"],
				[-0.25, 0.25, 2, 0.04, 0.04, 26, WOOD, "leg"], [0.25, 0.25, 2, 0.04, 0.04, 26, WOOD, "leg"],
				[0, 0, 28, 0.36, 0.36, 3, P.mul(WOOD, 0.9), "deck"], [0, 0, 31, 0.3, 0.3, 9, OLIVE, "cabin"],
				[0, 0, 40, 0.38, 0.38, 2, STEEL, "roof"]]
		"refinery":
			return [[-0.6, -0.65, 2, 0.16, 0.16, 58, Color8(150, 148, 140), "column"], [0.5, -0.75, 2, 0.42, 0.42, 20, TANK, "tank"],
				[-0.8, 0.45, 2, 0.38, 0.38, 18, TANK, "tank"], [0.05, -0.1, 2, 0.07, 0.07, 34, P.mul(STEEL, 0.9), "column"],
				[0.45, 0.45, 2, 0.6, 0.55, 14, Color8(116, 112, 100), "main"], [-0.5, 1.2, 2, 0.06, 0.06, 7, DRUM_R, "drum"],
				[-0.35, 1.27, 2, 0.06, 0.06, 7, DRUM_R, "drum"], [1.25, -0.2, 2, 0.06, 0.2, 4, JERSEY, "barrier"]]
	return []


static func draw(cv, def: String, size: int, o: Vector2, st: int) -> void:
	var half := size * 0.5 - 0.05
	# st 0 = built; 1..3 = construction stages
	var hk: float = [1.0, 0.0, 0.45, 0.85][st]
	var raw := st > 0
	var ps := parts(def)
	# ground-level parts back-to-front, then anything standing on another part
	ps.sort_custom(func(a, b):
		var la := 1 if a[2] > 4 else 0
		var lb := 1 if b[2] > 4 else 0
		if la != lb:
			return la < lb
		return a[0] + a[1] + a[2] * 0.001 < b[0] + b[1] + b[2] * 0.001)
	if hk > 0.0:
		for p in ps:
			P.box_shadow(cv, o, Vector3(p[0], p[1], p[2]), p[3] * (0.85 if p[7] in CYLINDERS else 1.0), p[4], p[5] * hk, 0.0)
	cv.flush_shadow()
	# foundation slab
	var slab: Dictionary = P.box(cv, o, Vector3(0, 0, 0), half, half, 2.0, 0.0, SLAB if not raw else P.mul(SLAB, 0.9), 0.12, 5)
	if raw:
		for i in size * 10:
			var u := P.hn(i, size, 41)
			var v := P.hn(i, size, 42)
			var q := P.sub(slab.top, u, v, u + 0.02, v + 0.02)
			cv.px(int(q[0].x), int(q[0].y), Color8(84, 62, 46))  # rebar stubs
	else:
		B.edges(cv, slab, SLAB)
	for p in ps:
		var hz: float = p[5] * hk
		if hz < 1.0:
			continue
		var col: Color = p[6]
		if raw:
			col = P.mix(col, Color8(150, 146, 136), 0.45)
		var role := String(p[7])
		if role in CYLINDERS:
			var band := 0.72 if role == "tank" and not raw else -1.0
			var top := B.cyl(cv, o, Vector3(p[0], p[1], p[2]), p[3], hz, col, 50 + int(p[3] * 100), band, 2 if role == "tank" else 0)
			if role == "column" and not raw:
				cv.ellipse(top.x, top.y, p[3] * 30.0, p[3] * 15.0, Color8(30, 30, 28))
				if p[5] > 40:
					B.plume(cv, top, 707)
			continue
		var r: Dictionary = P.box(cv, o, Vector3(p[0], p[1], p[2]), p[3], p[4], hz, 0.0, col, 0.09, 50 + int(p[3] * 10))
		B.wall_ao(cv, r, 0.3 if p[2] <= 4 else 0.18)
		if not raw:
			R.dress(cv, o, def, p, r, col)
		else:
			_scaffold(cv, r)
	if not raw:
		R.post(cv, o, def)
	# team marking: flag on a pole at the front-left corner (stake when under construction)
	var base := P.proj(o, Vector3(-half + 0.12, half - 0.12, 2))
	var ph := 34 if not raw else 12
	if def == "guard_tower" and not raw:
		base = P.proj(o, Vector3(0, 0, 42))
		ph = 14
	cv.line(int(base.x), int(base.y), int(base.x), int(base.y) - ph, Color8(60, 60, 56))
	cv.team = true
	var fw := 11 if not raw else 5
	for yy in (6 if not raw else 4):
		for xx in fw:
			var wave := int(round(sin(xx * 0.7) * 0.8))
			cv.px(int(base.x) + 1 + xx, int(base.y) - ph + yy + wave, Color(0.85, 0.85, 0.85) if yy > 0 else Color(1, 1, 1))
	cv.team = false
	cv.outline(Color(0.09, 0.09, 0.08, 1))


static func _scaffold(cv, r: Dictionary) -> void:
	var pole := Color8(140, 116, 78)
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		for u in [0.0, 0.33, 0.66, 1.0]:
			var a: Vector2 = q[0].lerp(q[1], u) + Vector2(0, 1)
			var b: Vector2 = q[3].lerp(q[2], u) + Vector2(0, -5)
			cv.line_v(a, b, pole)
		for v in [0.35, 0.75]:
			cv.line_v(q[0].lerp(q[3], v), q[1].lerp(q[2], v), P.mul(pole, 0.85))
