extends RefCounted
## G5 Coastal Front decor, part 2 (agent ART-NAV): beach obstacles, sea stack, cliff rocks, island pines,
## beached hulk, net rack, dune grass, driftwood (poi_decor, drawn for g5_naval_coast.build); small
## terrain-code decor variants manifest.decor.coast_beach / coast_shallow / coast_cliff ({file, pivot});
## and terrain_g5: cliff-to-sea transition atlases in the g4_terrain_trans layout (1024x64, column = mask,
## row 0 edges / row 1 corners) with renderer rules {kind, recv, from}:
##   surf       on WATER / SHALLOW / DEEP cells against CLIFF: broken white surf + spray rocks
##   cliff_wet  on CLIFF cells against water: dark wet rock foot with a weed line and a foam lip
const P = preload("res://tools/art/pix.gd")
const T = preload("res://tools/art/g4_terrain_trans.gd")
const N = preload("res://tools/art/g5_naval_lib.gd")
const D = preload("res://tools/art/vdetail.gd")

const ROCK := Color8(112, 106, 96)
const RUST := Color8(122, 70, 42)
const SAND := Color8(184, 166, 120)
const PINE := Color8(46, 78, 52)
const BARK := Color8(86, 64, 46)
const STEEL := Color8(58, 58, 56)


static func pr(o: Vector2, x: float, y: float, z: float) -> Vector2:
	return P.proj(o, Vector3(x, y, z))


## Translucent foam ellipse with a broken rim (after the outline so it is never rimmed).
static func foam(cv, c: Vector2, rx: float, ry: float) -> void:
	for y in range(int(c.y - ry) - 1, int(c.y + ry) + 2):
		for x in range(int(c.x - rx) - 1, int(c.x + rx) + 2):
			var dx := (x + 0.5 - c.x) / rx
			var dy := (y + 0.5 - c.y) / ry
			var d := dx * dx + dy * dy
			if d <= 1.0 and P.hn(x, y, 731) > 0.35:
				cv.px(x, y, Color(0.93, 0.97, 1.0, 0.55 if d > 0.5 else 0.3))


## Boulders at local points (Vector2 = on the ground, Vector3 = raised z px), sorted far -> near.
static func boulders(cv, o: Vector2, pts: Array, size: float, s: int) -> void:
	var ps: Array = []
	for v in pts:
		ps.append(v if v is Vector3 else Vector3(v.x, v.y, 0.0))
	ps.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x + a.y + a.z * 0.01 < b.x + b.y + b.z * 0.01)
	for i in ps.size():
		var q: Vector3 = ps[i]
		var c := pr(o, q.x, q.y, q.z)
		var r := size * (0.7 + P.hn(i, s, 740) * 0.5)
		var col := P.mul(ROCK, 0.85 + P.hn(i, s, 741) * 0.3)
		cv.ellipse(c.x, c.y - r * 0.45, r, r * 0.62, P.mul(col, 0.72))
		cv.ellipse(c.x - r * 0.2, c.y - r * 0.6, r * 0.72, r * 0.42, col)
		cv.px(int(c.x - r * 0.35), int(c.y - r * 0.8), P.mul(col, 1.3))


static func draw(cv, id: String, o: Vector2, soft: Array) -> void:
	match id:
		"coast_hedgehogs":
			for p in [Vector2(-0.22, -0.18), Vector2(0.2, -0.05), Vector2(-0.05, 0.25)]:
				_hedgehog(cv, pr(o, p.x, p.y, 0.0))
		"coast_sea_stack":
			var b := pr(o, 0.0, 0.0, 0.0)
			var pts := PackedVector2Array([b + Vector2(-11, 0), b + Vector2(-9, -18), b + Vector2(-6, -30),
				b + Vector2(-2, -38), b + Vector2(4, -36), b + Vector2(7, -24), b + Vector2(10, -12), b + Vector2(12, 0)])
			cv.poly(pts, ROCK, func(x: int, y: int, c: Color) -> Color:
				var t := (x + 0.5 - b.x) / 12.0
				var strata := 0.9 if (y / 4) % 2 == 0 else 1.0
				return P.mul(c, (1.12 - 0.4 * (t * 0.5 + 0.5)) * strata * (0.94 + P.hn(x, y, 750) * 0.12)))
			cv.poly(PackedVector2Array([b + Vector2(-5, -37), b + Vector2(3, -37), b + Vector2(0, -35)]), Color8(150, 150, 140))
			soft.append([b + Vector2(0, 1), 15.0, 4.5])
		"coast_cliff_rocks":
			boulders(cv, o, [Vector2(-0.25, -0.15), Vector2(0.15, -0.25), Vector2(0.0, 0.1), Vector2(0.3, 0.2),
				Vector2(-0.3, 0.25)], 7.0, 760)
			for f in [Vector2(-0.2, 0.35), Vector2(0.35, 0.35), Vector2(0.4, -0.1)]:
				soft.append([pr(o, f.x, f.y, 0.0), 6.0, 2.0])
		"coast_island_pines":
			boulders(cv, o, [Vector2(0.25, 0.2), Vector2(-0.3, 0.15)], 5.0, 770)
			for p in [Vector2(-0.12, -0.15), Vector2(0.18, -0.05), Vector2(-0.02, 0.18)]:
				_pine(cv, pr(o, p.x, p.y, 0.0), int(p.x * 100.0))
		"coast_beached_hulk":
			_hulk(cv, o)
		"coast_net_rack":
			var a := pr(o, -0.3, -0.1, 0.0)
			var b2 := pr(o, 0.3, 0.1, 0.0)
			for p in [a, b2]:
				cv.line_v(p, p + Vector2(0, -14), BARK)
			cv.line_v(a + Vector2(0, -14), b2 + Vector2(0, -14), BARK)
			for k in 10:
				var t := k / 9.0
				var top: Vector2 = a.lerp(b2, t) + Vector2(0, -13)
				cv.line_v(top, top + Vector2(0.5, 9), Color(0.3, 0.32, 0.28, 0.75))
			for k in 3:
				cv.line_v(a + Vector2(0, -11 + k * 3), b2 + Vector2(0, -11 + k * 3), Color(0.3, 0.32, 0.28, 0.75))
		"coast_dune_grass":
			for i in 14:
				var p := pr(o, (P.hn(i, 0, 780) - 0.5) * 0.8, (P.hn(i, 1, 781) - 0.5) * 0.8, 0.0)
				for k in 4:
					var col := Color8(150, 158, 86) if k % 2 == 0 else Color8(118, 130, 70)
					cv.line_v(p + Vector2(k - 1.5, 0), p + Vector2(k * 1.2 - 2.0, -3 - P.hn(i, k, 782) * 3.0), col)
		"coast_driftwood":
			for i in 3:
				var p := pr(o, (P.hn(i, 2, 790) - 0.5) * 0.6, (P.hn(i, 3, 791) - 0.5) * 0.6, 0.0)
				var d := Vector2(7 + i * 2, 2 - i * 2)
				cv.line_v(p - d * 0.5, p + d * 0.5, Color8(150, 132, 104))
				cv.line_v(p - d * 0.5 + Vector2(0, 1), p + d * 0.5 + Vector2(0, 1), Color8(102, 86, 66))


static func _hedgehog(cv, b: Vector2) -> void:
	for seg in [[Vector2(-5, -1), Vector2(4, -9)], [Vector2(5, -1), Vector2(-4, -9)], [Vector2(0, 1), Vector2(0, -10)]]:
		cv.line_v(b + seg[0], b + seg[1], STEEL)
		cv.line_v(b + seg[0] + Vector2(1, 0), b + seg[1] + Vector2(1, 0), P.mul(RUST, 0.9))


static func _pine(cv, b: Vector2, s: int) -> void:
	var lean := Vector2(4, -26)
	cv.line_v(b, b + lean, BARK)
	cv.line_v(b + Vector2(1, 0), b + lean + Vector2(1, 0), P.mul(BARK, 0.8))
	for k in 4:
		var c := b + lean * (0.45 + k * 0.17) + Vector2(3 + k, 0)
		var w := 9.0 - k * 1.8
		cv.ellipse(c.x, c.y, w, 2.6, P.mul(PINE, 0.8))
		cv.ellipse(c.x - 1, c.y - 1, w * 0.75, 1.8, P.mul(PINE, 1.05 + P.hn(k, s, 795) * 0.1))


static func _hulk(cv, o: Vector2) -> void:
	var sh := {"L": 0.85, "B": 0.28, "bow": 0.9, "F": 13.0}
	var rot := 0.5
	var h := N.hull(cv, o, rot, sh, RUST, P.mul(RUST, 0.8), 4.0, 800)
	for sd in h.sides:
		var q: PackedVector2Array = sd.quad
		cv.poly(P.sub(q, 0.3, 0.35, 0.42, 0.8), Color8(30, 24, 20))
		for i in range(1, 4):
			cv.line_v(q[0].lerp(q[3], i / 4.0), q[1].lerp(q[2], i / 4.0), P.mul(RUST, 0.72))
		cv.poly(P.sub(q, -0.02, -0.1, 1.02, 0.3), SAND, P.speckle(0.1, 802))
	for i in 6:  # exposed ribs over a torn-open deck
		var f := -0.1 + i * 0.09
		cv.poly(PackedVector2Array([D.sp(o, rot, f, -0.2, 9.0), D.sp(o, rot, f + 0.05, -0.2, 9.0),
			D.sp(o, rot, f + 0.05, 0.2, 9.0), D.sp(o, rot, f, 0.2, 9.0)]), Color8(30, 24, 20))
		cv.line_v(D.sp(o, rot, f, -0.22, 9.0), D.sp(o, rot, f, -0.22, 14.0), P.mul(RUST, 1.2))
	N.zbox(cv, o, rot, -0.5, 0.0, 13.0, 0.14, 0.12, 6.0, P.mul(RUST, 0.9), 4.0, 801)


# ---------------------------------------------------------------- small decor + transitions
const TRANS_RULES := [
	{"kind": "surf", "recv": [4, 9, 10], "from": [12]},
	{"kind": "cliff_wet", "recv": [12], "from": [4, 9, 10]},
]


static func build_small(out: Dictionary) -> void:
	var dec: Dictionary = out.manifest.get("decor", {})
	for kind in ["coast_beach", "coast_shallow", "coast_cliff"]:
		var list: Array = []
		for v in 3:
			var cv = P.Canvas.new(28, 18)
			var o := Vector2(14, 13)
			match kind:
				"coast_beach":
					if v == 0:
						cv.line_v(o + Vector2(-8, 1), o + Vector2(7, -2), Color8(150, 132, 104))
						cv.line_v(o + Vector2(-8, 2), o + Vector2(7, -1), Color8(102, 86, 66))
					elif v == 1:
						for i in 6:
							cv.px(int(o.x + (P.hn(i, v, 810) - 0.5) * 16), int(o.y + (P.hn(i, 9, 811) - 0.5) * 6), Color8(232, 226, 210))
						boulders(cv, o, [Vector2(0.05, 0.0)], 2.5, 812)
					else:
						cv.ellipse(o.x, o.y, 6.0, 2.0, Color8(62, 76, 44))
						cv.ellipse(o.x + 2, o.y - 1, 3.5, 1.2, Color8(84, 98, 52))
				"coast_shallow":
					boulders(cv, o, [Vector2(-0.08, 0.0), Vector2(0.07, 0.03)], 3.0 + v, 820 + v)
				"coast_cliff":
					boulders(cv, o, [Vector2(-0.1, -0.02), Vector2(0.08, 0.0), Vector2(0.0, 0.08)], 3.0 + v * 0.8, 830 + v)
			cv.outline(Color(0.09, 0.085, 0.075, 1))
			if kind == "coast_shallow":
				foam(cv, o, 9.0, 3.0)
			var path := "decor/%s_%d.png" % [kind, v]
			out.images[path] = cv.img
			list.append({"file": path, "pivot": [int(o.x), int(o.y)]})
		dec[kind] = list
	out.manifest["decor"] = dec
	var tr := {}
	for kind in ["surf", "cliff_wet"]:
		var path := "terrain/trans_%s.png" % kind
		out.images[path] = atlas(kind)
		tr[kind] = path
	out.manifest["terrain_g5"] = {"trans": tr, "trans_atlas": T.ATLAS.duplicate(true), "rules": TRANS_RULES.duplicate(true)}


static func atlas(kind: String) -> Image:
	var img := Image.create(1024, 64, false, Image.FORMAT_RGBA8)
	var base := "shelf" if kind == "surf" else "wet"
	var k := 6 if kind == "surf" else 7
	for row in 2:
		for m in range(1, 16):
			for y in 32:
				for x in 64:
					if not P.in_diamond(x, y):
						continue
					var sx := (x + 0.5 - 32.0) / 32.0
					var sy := (y + 0.5) / 16.0
					var t := T._field(base, k, (sy + sx) * 0.5, (sy - sx) * 0.5, m, row == 1)
					t += (P.hn(x, y, 840 + k) - 0.5) * 0.08
					if t >= 1.0:
						continue
					var c := _paint(kind, t, x + m * 64, y + row * 32)
					if c.a > 0.0:
						img.set_pixel(m * 64 + x, row * 32 + y, c)
	return img


static func _paint(kind: String, t: float, x: int, y: int) -> Color:
	var n := P.hn(x, y, 850)
	if kind == "surf":  # crashing white water at the cliff foot, broken spray further out
		if t < 0.22:
			return Color8(236, 242, 244, 240) if n > 0.12 else Color(0.5, 0.56, 0.58, 0.9)
		if t < 0.5:
			return Color(0.9, 0.95, 0.97, 0.62) if n > 0.45 else Color(0.62, 0.72, 0.74, 0.4)
		return Color(0.86, 0.92, 0.95, 0.4) if n > 0.82 else Color(0, 0, 0, 0)
	if t < 0.12:  # cliff_wet: foam lip, weed line, wet dark rock
		return Color(0.88, 0.92, 0.93, 0.7)
	if t < 0.3:
		return Color(0.16, 0.24, 0.12, 0.6) if n > 0.3 else Color(0.08, 0.08, 0.07, 0.5)
	return Color(0.05, 0.05, 0.05, 0.34 * (1.0 - t))
