extends RefCounted
## G3b POI map decor for MAP4 (agent ART4-2): manifest.poi_decor[id] = {file, pivot, footprint, flat}.
## pivot = ground point of the footprint centre (same convention as buildings); footprint = [w, h]
## cells; flat = ground overlay drawn under units (rails, tarmac, dam deck). Neutral: no team mask.
## Canvas: w = (fw+fh)*32 + 12, pivot.y = headroom + (fw+fh)*8, h = pivot.y + (fw+fh)*8 + 6 + below.
## Ids agreed with MAP4 on the board (seq 487/493). Never touches manifest.decor (rocks/trees).
const P = preload("res://tools/art/pix.gd")
const B = preload("res://tools/art/bdetail.gd")
const RA = preload("res://tools/art/bdress.gd")
const RB = preload("res://tools/art/faction_b_bdress.gd")
const FBB = preload("res://tools/art/faction_b_bld.gd")

## id -> [fw, fh, headroom px, extra px below, flat]
const SPEC := {"rail_ew": [1, 1, 4, 0, true], "rail_ns": [1, 1, 4, 0, true], "rail_x": [1, 1, 4, 0, true],
	"factory_block": [3, 3, 84, 0, false], "refinery_tanks": [2, 2, 56, 0, false], "ruined_plant": [3, 3, 44, 0, false],
	"dam_ew": [1, 1, 8, 18, true], "tunnel_portal": [2, 2, 40, 0, false], "airfield_tarmac": [1, 1, 4, 0, true],
	"airfield_tarmac_mark": [1, 1, 4, 0, true], "hangar": [3, 2, 44, 0, false], "town_house": [2, 2, 46, 0, false]}
const GRAVEL := Color8(104, 98, 88)
const SLEEPER := Color8(84, 64, 46)
const RAIL := Color8(160, 160, 156)
const ASPHALT := Color8(70, 72, 72)
const CONC := Color8(138, 134, 124)
const ROCK := Color8(106, 98, 84)
const PAINT := Color8(222, 220, 206)


static func build(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("poi_decor", {})
	for id in SPEC:
		var sp: Array = SPEC[id]
		var n: int = sp[0] + sp[1]
		var w := n * 32 + 12
		var o := Vector2(w / 2, int(sp[2]) + n * 8)
		var cv = P.Canvas.new(w, int(o.y) + n * 8 + 6 + int(sp[3]))
		draw(cv, id, o, float(sp[0]) * 0.5, float(sp[1]) * 0.5)
		if not sp[4]:
			cv.outline(Color(0.09, 0.085, 0.075, 1))
		var path := "decor/poi_%s.png" % id
		out.images[path] = cv.img
		man[id] = {"file": path, "pivot": [int(o.x), int(o.y)], "footprint": [sp[0], sp[1]], "flat": sp[4]}
	out.manifest["poi_decor"] = man


static func q(o: Vector2, x0: float, y0: float, x1: float, y1: float, z := 0.0) -> PackedVector2Array:
	return PackedVector2Array([P.proj(o, Vector3(x0, y0, z)), P.proj(o, Vector3(x1, y0, z)),
		P.proj(o, Vector3(x1, y1, z)), P.proj(o, Vector3(x0, y1, z))])


static func draw(cv, id: String, o: Vector2, hx: float, hy: float) -> void:
	match id:
		"rail_ew":
			_rail(cv, o, true)
		"rail_ns":
			_rail(cv, o, false)
		"rail_x":
			_rail(cv, o, true)
			_rail(cv, o, false)
		"airfield_tarmac", "airfield_tarmac_mark":
			_tarmac(cv, o, id == "airfield_tarmac_mark")
		"dam_ew":
			_dam(cv, o)
		_:
			_structure(cv, id, o, hx, hy)


## Ballast bed, timber sleepers and two steel rails across the tile (ew = along +x).
static func _rail(cv, o: Vector2, ew: bool) -> void:
	var f := func(a: float, b: float, c: float, d: float) -> PackedVector2Array:
		return q(o, a, b, c, d) if ew else q(o, b, a, d, c)
	cv.poly(f.call(-0.5, -0.24, 0.5, 0.24), GRAVEL, P.speckle(0.16, 1201 if ew else 1202))
	for i in 7:
		var x := -0.5 + (i + 0.5) / 7.0
		cv.poly(f.call(x - 0.03, -0.19, x + 0.03, 0.19), P.mul(SLEEPER, 0.9 + P.hn(i, 1, 1203) * 0.2))
	for r in [-0.09, 0.09]:
		var a: Vector2 = f.call(-0.5, r, 0.5, r)[0]
		var b: Vector2 = f.call(-0.5, r, 0.5, r)[1]
		cv.line_v(a + Vector2(0, 1), b + Vector2(0, 1), Color8(46, 42, 38))
		cv.line_v(a, b, RAIL)


static func _tarmac(cv, o: Vector2, mark: bool) -> void:
	var t := q(o, -0.5, -0.5, 0.5, 0.5)
	cv.poly(t, ASPHALT, P.speckle(0.1, 1211 if mark else 1212))
	cv.line_v(t[0], t[1], P.mul(ASPHALT, 0.8))  # expansion joints
	cv.line_v(t[0], t[3], P.mul(ASPHALT, 0.8))
	for i in 3:
		var u := P.hn(i, 3, 1213 + int(mark)) * 0.7 + 0.15
		var v := P.hn(i, 4, 1213 + int(mark)) * 0.7 + 0.15
		var c: Vector2 = P.sub(t, u, v, u, v)[0]
		cv.ellipse(c.x, c.y, 3.0, 1.5, Color(0.1, 0.1, 0.1, 0.35))
	if mark:  # centreline dashes along +x and a threshold bar block
		for i in 3:
			var x := -0.42 + i * 0.32
			cv.poly(q(o, x, -0.03, x + 0.18, 0.03), PAINT)
		for j in 4:
			var y := -0.4 + j * 0.1
			cv.poly(q(o, 0.32, y, 0.46, y + 0.05), PAINT)


## Dam deck segment along +x: concrete roadway with parapets; the downstream (+y) face drops away
## with spillway streaks (drawn below the ground diamond, hence the extra canvas below).
static func _dam(cv, o: Vector2) -> void:
	var r: Dictionary = P.box(cv, o, Vector3(0, 0.05, -16), 0.5, 0.42, 16.0, 0.0, CONC, 0.12, 1221)
	for sd in r.sides:
		var f: PackedVector2Array = sd.quad
		for i in 6:
			var u := (i + 0.5) / 6.0
			cv.line_v(f[0].lerp(f[1], u), f[3].lerp(f[2], u) + Vector2(0, 2), Color8(98, 108, 112))
	cv.poly(q(o, -0.5, -0.2, 0.5, 0.25), Color8(84, 84, 80), P.speckle(0.08, 1222))
	for y in [-0.33, 0.4]:
		var a := P.proj(o, Vector3(-0.5, y, 0))
		var b := P.proj(o, Vector3(0.5, y, 0))
		cv.line_v(a + Vector2(0, -2), b + Vector2(0, -2), Color8(176, 172, 160))
		cv.line_v(a + Vector2(0, -1), b + Vector2(0, -1), Color8(96, 94, 88))
	for i in 3:
		var x := -0.36 + i * 0.32
		cv.poly(q(o, x, 0.0, x + 0.12, 0.03), Color8(206, 190, 96))


## Box list [cx, cy, z, hx, hy, hz, colour, role] for the standing POIs (local tiles, footprint-centred).
## Roles: brick/shed/sawtooth = Human B dressing, main = Human A dressing, tank/stack = cylinders,
## rubble/scrap = debris piles, rock = ridge mass, portal = tunnel mouth, house = pitched-roof house.
static func parts(id: String) -> Array:
	match id:
		"factory_block":
			return [[-1.05, -1.05, 2, 0.16, 0.16, 70, FBB.BRICK_D, "stack"], [-0.55, -1.1, 2, 0.12, 0.12, 54, FBB.BRICK_D, "stack"],
				[0.1, 0.05, 2, 1.15, 1.0, 24, FBB.IRON, "sawtooth"], [-0.95, 0.95, 2, 0.4, 0.4, 14, FBB.BRICK, "brick"],
				[1.3, -0.9, 2, 0.14, 0.28, 6, FBB.RUSTY, "scrap"]]
		"refinery_tanks":
			return [[-0.42, -0.4, 2, 0.4, 0.4, 22, Color8(176, 174, 164), "tank"], [0.45, -0.38, 2, 0.32, 0.32, 18, Color8(168, 166, 156), "tank"],
				[-0.38, 0.48, 2, 0.32, 0.32, 18, Color8(172, 170, 160), "tank"], [0.5, 0.5, 2, 0.08, 0.08, 40, Color8(150, 148, 140), "stack"]]
		"ruined_plant":
			return [[-0.6, -0.7, 2, 0.75, 0.08, 26, FBB.BRICK, "wall"], [-1.3, -0.1, 2, 0.08, 0.6, 18, FBB.BRICK, "wall"],
				[0.4, -0.75, 2, 0.35, 0.08, 12, P.mul(FBB.BRICK, 0.9), "wall"], [-1.0, 1.0, 2, 0.14, 0.14, 30, FBB.BRICK_D, "stack"],
				[0.3, 0.3, 2, 0.7, 0.55, 7, Color8(118, 112, 104), "rubble"], [-0.5, 0.2, 2, 0.4, 0.3, 5, FBB.RUSTY, "scrap"],
				[1.0, 0.95, 2, 0.3, 0.3, 4, Color8(96, 92, 88), "rubble"]]
		"tunnel_portal":
			return [[0.0, -0.35, 0, 0.98, 0.62, 30, ROCK, "rock"], [0.0, 0.38, 0, 0.5, 0.14, 22, CONC, "portal"]]
		"hangar":
			return [[0.05, -0.2, 2, 1.3, 0.72, 22, Color8(120, 124, 118), "shed"], [1.38, 0.82, 2, 0.06, 0.06, 7, FBB.DRUM_R, "stack"]]
		"town_house":
			return [[0.05, 0.0, 2, 0.62, 0.5, 15, Color8(176, 160, 132), "house"], [0.72, 0.78, 2, 0.12, 0.1, 6, Color8(128, 104, 70), "crate"]]
	return []


static func _structure(cv, id: String, o: Vector2, hx: float, hy: float) -> void:
	var ps := parts(id)
	ps.sort_custom(func(a, b): return a[0] + a[1] < b[0] + b[1])
	for p in ps:
		if p[7] != "rubble" and p[7] != "scrap":
			P.box_shadow(cv, o, Vector3(p[0], p[1], p[2]), p[3] * (0.85 if p[7] in ["tank", "stack"] else 1.0), p[4], p[5], 0.0)
	cv.flush_shadow()
	var ground: Color = ASPHALT if id == "hangar" else (ROCK if id == "tunnel_portal" else Color8(104, 100, 92))
	var slab: Dictionary = P.box(cv, o, Vector3(0, 0, 0), hx - 0.04, hy - 0.04, 2.0, 0.0, ground, 0.14, 1230)
	if id == "tunnel_portal":  # road out of the mouth
		cv.poly(q(o, -0.32, 0.5, 0.32, 0.96, 2), ASPHALT, P.speckle(0.1, 1231))
	elif id == "hangar":
		for i in 4:
			cv.poly(q(o, -1.1 + i * 0.6, 0.72, -0.95 + i * 0.6, 0.76, 2), Color8(206, 190, 96))
	else:
		RB.oil_stains(cv, slab.top, 1232)
	for p in ps:
		var c := Vector3(p[0], p[1], p[2])
		var role: String = p[7]
		var col: Color = p[6]
		match role:
			"tank", "stack":
				var top := B.cyl(cv, o, c, p[3], p[5], col, 1240 + int(p[3] * 100), 0.75 if role == "tank" else -1.0, 2 if role == "tank" else 0)
				if role == "tank":
					cv.ellipse(top.x, top.y, p[3] * 18.0, p[3] * 9.0, P.mul(col, 0.85))
				elif id == "factory_block":
					RB.cyl_dress(cv, o, "b_works", "stack", c, p[3], p[5], top)
			"rubble", "scrap":
				RB.scrap_pile(cv, o, c, p[3], p[4], p[5], col, 1250 + int(p[0] * 10), role == "rubble")
			_:
				var r: Dictionary = P.box(cv, o, c, p[3], p[4], p[5], 0.0, col, 0.1, 1260 + int(p[3] * 10))
				B.wall_ao(cv, r, 0.3)
				_dress(cv, o, id, role, p, r, col)
	if id == "refinery_tanks":
		B.pipe(cv, o, Vector3(-0.42, -0.4, 10), Vector3(0.45, -0.38, 10), Color8(110, 110, 104))
		B.pipe(cv, o, Vector3(-0.38, 0.48, 9), Vector3(0.5, 0.5, 9), Color8(110, 110, 104))


static func _dress(cv, o: Vector2, id: String, role: String, p: Array, r: Dictionary, col: Color) -> void:
	match role:
		"brick", "shed", "sawtooth":
			RB.dress(cv, o, "b_works" if role == "brick" else "b_heavy_plant", role, p, r, col)
		"wall":  # broken brick wall: bricks, jagged top, dark burnt window holes
			for sd in r.sides:
				RB.brick_tex(cv, sd.quad, 1270)
				for i in 2:
					cv.poly(P.sub(sd.quad, 0.2 + i * 0.4, 0.4, 0.34 + i * 0.4, 0.7), Color8(26, 22, 20))
			for i in 9:  # jagged broken top: stepped brick stubs along the wall crest
				var t: Vector2 = P.sub(r.top, i / 9.0 + 0.05, 0.5, i / 9.0 + 0.05, 0.5)[0]
				var dz := P.hi(i, int(p[0] * 10), 1271, 5)
				cv.rect(int(t.x) - 1, int(t.y) - dz, 3, dz + 1, P.mul(col, 0.92))
			cv.poly(r.top, P.mul(col, 0.8))
		"rock":
			for sd in r.sides:
				for i in 6:
					var u := P.hn(i, 1, 1280) * 0.9
					var v := P.hn(i, 2, 1280) * 0.8
					cv.poly(P.sub(sd.quad, u, v, u + 0.1, v + 0.12), P.mul(col, 0.82 + P.hn(i, 3, 1280) * 0.3))
			cv.poly(P.sub(r.top, 0.0, 0.0, 1.0, 1.0), Color8(92, 102, 66), P.speckle(0.2, 1281))  # grassy ridge top
		"portal":
			for sd in r.sides:
				if RA._face(sd) == "y":
					var m := P.sub(sd.quad, 0.22, 0.0, 0.78, 0.72)
					cv.poly(m, Color8(14, 14, 14))
					cv.line_v(m[3], m[2], P.mul(col, 1.25))
					cv.poly(P.sub(sd.quad, 0.0, 0.84, 1.0, 0.92), Color8(206, 190, 96))
		"house":
			for sd in r.sides:
				var face := RA._face(sd)
				B.window_row(cv, sd.quad, 0.4, 0.7, 2, col, 1290, 0.4)
				if face == "y":
					B.door(cv, sd.quad, 0.44, 0.58, 0.6, col)
			_roof(cv, o, p)
		"crate":
			B.edges(cv, r, col)


## Pitched tile roof over a house box, ridge along +x.
static func _roof(cv, o: Vector2, p: Array) -> void:
	var x0: float = p[0] - p[3] - 0.04
	var x1: float = p[0] + p[3] + 0.04
	var zt: float = p[2] + p[5]
	var zr := zt + 12.0
	var tile := Color8(150, 72, 52)
	var e0 := P.proj(o, Vector3(x0, p[1] - p[4] - 0.05, zt))
	var e1 := P.proj(o, Vector3(x1, p[1] - p[4] - 0.05, zt))
	var f0 := P.proj(o, Vector3(x0, p[1] + p[4] + 0.05, zt))
	var f1 := P.proj(o, Vector3(x1, p[1] + p[4] + 0.05, zt))
	var r0 := P.proj(o, Vector3(x0, p[1], zr))
	var r1 := P.proj(o, Vector3(x1, p[1], zr))
	cv.poly(PackedVector2Array([e0, e1, r1, r0]), P.mul(tile, 0.8))
	cv.poly(PackedVector2Array([f0, f1, r1, r0]), tile)
	cv.poly(PackedVector2Array([P.proj(o, Vector3(p[0] + p[3], p[1] - p[4], zt)), P.proj(o, Vector3(p[0] + p[3], p[1] + p[4], zt)),
		P.proj(o, Vector3(p[0] + p[3], p[1], zr - 1))]), P.mul(p[6], 0.86))
	for i in 5:
		var t := (i + 1) / 6.0
		cv.line_v(f0.lerp(r0, t), f1.lerp(r1, t), P.mul(tile, 0.72))
	cv.line_v(r0, r1, P.mul(tile, 1.2))
	var ch := P.proj(o, Vector3(x1 - 0.25, p[1] - 0.12, zr - 3))
	cv.rect(int(ch.x) - 1, int(ch.y) - 6, 3, 6, Color8(120, 70, 54))
