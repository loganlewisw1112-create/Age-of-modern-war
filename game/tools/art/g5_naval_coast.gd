extends RefCounted
## G5 Coastal Front decor (agent ART-NAV), neutral (no team mask), same convention as g3b_decor:
## manifest.poi_decor[id] = {file, pivot, footprint, flat}; pivot = ground / water-level point of the
## footprint centre; canvas w = (fw+fh)*32 + 12, pivot.y = headroom + (fw+fh)*8. Piers and jetties are
## 1x1 and tile along their axis (an entry larger than the footprint is tiled by the renderer).
## Ids (map authors / ED5 place them in map.decor): coast_pier_ew, coast_pier_ns, coast_pier_end,
## coast_jetty_ew, coast_jetty_ns, coast_lighthouse, coast_buoy_red, coast_buoy_green, coast_boathouse,
## plus the coast2 set (hedgehogs, sea stack, cliff rocks, island pines, beached hulk, net rack, dune
## grass, driftwood). Also writes manifest.decor coast_* variants and terrain_g5 (coast2).
const P = preload("res://tools/art/pix.gd")
const C2 = preload("res://tools/art/g5_naval_coast2.gd")

## id -> [fw, fh, headroom px, extra px below, flat]
const SPEC := {
	"coast_pier_ew": [1, 1, 10, 10, false], "coast_pier_ns": [1, 1, 10, 10, false],
	"coast_pier_end": [1, 1, 24, 10, false], "coast_jetty_ew": [1, 1, 12, 6, false],
	"coast_jetty_ns": [1, 1, 12, 6, false], "coast_lighthouse": [1, 1, 76, 4, false],
	"coast_buoy_red": [1, 1, 16, 2, false], "coast_buoy_green": [1, 1, 16, 2, false],
	"coast_boathouse": [2, 1, 34, 4, false],
	"coast_hedgehogs": [1, 1, 12, 0, false], "coast_sea_stack": [1, 1, 46, 6, false],
	"coast_cliff_rocks": [1, 1, 16, 6, false], "coast_island_pines": [1, 1, 44, 0, false],
	"coast_beached_hulk": [2, 2, 30, 0, false], "coast_net_rack": [1, 1, 18, 0, false],
	"coast_dune_grass": [1, 1, 6, 0, true], "coast_driftwood": [1, 1, 4, 0, true],
}
const WOOD := Color8(124, 98, 66)
const WOOD_D := Color8(84, 64, 44)
const ROPE := Color8(176, 156, 112)
const WHITE := Color8(226, 224, 216)
const RED := Color8(184, 44, 38)
const GREEN := Color8(46, 132, 70)
const FOAM := Color(0.93, 0.97, 1.0, 0.5)


static func build(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("poi_decor", {})
	for id in SPEC:
		var sp: Array = SPEC[id]
		var n: int = sp[0] + sp[1]
		var w := n * 32 + 12
		var o := Vector2(w / 2, int(sp[2]) + n * 8)
		var cv = P.Canvas.new(w, int(o.y) + n * 8 + 6 + int(sp[3]))
		var soft: Array = []   # [center, rx, ry] foam ellipses drawn after the outline
		if not draw(cv, id, o, soft):
			C2.draw(cv, id, o, soft)
		if not sp[4]:
			cv.outline(Color(0.09, 0.085, 0.075, 1))
		for f: Array in soft:
			C2.foam(cv, f[0], f[1], f[2])
		var path := "decor/poi_%s.png" % id
		out.images[path] = cv.img
		man[id] = {"file": path, "pivot": [int(o.x), int(o.y)], "footprint": [sp[0], sp[1]], "flat": sp[4]}
	out.manifest["poi_decor"] = man
	C2.build_small(out)


static func pr(o: Vector2, x: float, y: float, z: float) -> Vector2:
	return P.proj(o, Vector3(x, y, z))


static func draw(cv, id: String, o: Vector2, soft: Array) -> bool:
	match id:
		"coast_pier_ew":
			_pier(cv, o, 0.0, 0.5, 0.17)
		"coast_pier_ns":
			_pier(cv, o, PI / 2.0, 0.5, 0.17)
		"coast_pier_end":
			_pier(cv, o, 0.0, 0.42, 0.4)
			var b := pr(o, 0.25, -0.25, 6.0)
			cv.line_v(b, b + Vector2(0, -16), Color8(52, 54, 52))
			cv.rect(int(b.x) - 1, int(b.y) - 19, 3, 3, Color8(250, 226, 140))
			P.box(cv, o, Vector3(-0.15, 0.15, 5.5), 0.08, 0.08, 4.0, 0.0, Color8(130, 108, 70), 0.1, 7)
		"coast_jetty_ew", "coast_jetty_ns":
			var ns := id.ends_with("ns")
			var stones: Array = []
			for i in 9:
				var a := -0.5 + (i + 0.5) / 9.0
				var j := (P.hn(i, 3, 700) - 0.5) * 0.18
				stones.append(Vector2(j, a) if ns else Vector2(a, j))
			for i in 5:
				var a2 := -0.4 + i * 0.2
				var j2 := (P.hn(i, 4, 701) - 0.5) * 0.1
				stones.append(Vector3(j2, a2, 4.0) if ns else Vector3(a2, j2, 4.0))
			C2.boulders(cv, o, stones, 6.5, 702)
			for i in 6:
				var a3 := -0.45 + i * 0.18
				soft.append([pr(o, 0.2, a3, 0.0) if ns else pr(o, a3, 0.2, 0.0), 4.0, 1.4])
		"coast_lighthouse":
			_lighthouse(cv, o, soft)
		"coast_buoy_red":
			_buoy(cv, o, RED, true, soft)
		"coast_buoy_green":
			_buoy(cv, o, GREEN, false, soft)
		"coast_boathouse":
			_boathouse(cv, o)
		_:
			return false
	return true


## Plank pier on posts along rot (0 = world x), half length hl, half width hw (tiles), deck at z 4..5.5.
static func _pier(cv, o: Vector2, rot: float, hl: float, hw: float) -> void:
	var ax := Vector2(cos(rot), sin(rot))
	var ay := Vector2(-ax.y, ax.x)
	for i in 3:
		for s: float in [-1.0, 1.0]:
			var g := ax * (-hl * 0.8 + i * hl * 0.8) + ay * hw * 0.85 * s
			cv.line_v(pr(o, g.x, g.y, 4.0), pr(o, g.x, g.y, -5.0), WOOD_D)
			cv.line_v(pr(o, g.x, g.y, 4.0) + Vector2(1, 0), pr(o, g.x, g.y, -5.0) + Vector2(1, 0), P.mul(WOOD_D, 0.8))
	var r: Dictionary = P.box(cv, o, Vector3(0, 0, 4.0), hl, hw, 1.5, rot, WOOD, 0.12, 703)
	var top: PackedVector2Array = r.top
	var n := int(hl * 20.0)
	for i in range(1, n):
		var u := float(i) / n
		cv.line_v(top[0].lerp(top[1], u), top[3].lerp(top[2], u), P.mul(WOOD, 0.78))
	for s: float in [-1.0, 1.0]:  # bollards and a rope coil
		var b := ax * hl * 0.55 + ay * hw * 0.75 * s
		P.box(cv, o, Vector3(b.x, b.y, 5.5), 0.025, 0.025, 2.5, 0.0, Color8(40, 40, 40), 0.05, 704)
	var c := pr(o, -ax.x * hl * 0.3, -ax.y * hl * 0.3, 5.5)
	cv.ellipse(c.x, c.y, 2.0, 1.0, ROPE)
	cv.px(int(c.x), int(c.y), P.mul(ROPE, 0.6))


static func _lighthouse(cv, o: Vector2, soft: Array) -> void:
	C2.boulders(cv, o, [Vector2(-0.3, -0.1), Vector2(0.2, -0.3), Vector2(-0.1, 0.3), Vector2(0.3, 0.2),
		Vector3(0.0, 0.0, 3.0)], 8.0, 710)
	var base := pr(o, 0.0, 0.0, 6.0)
	var h := 52
	for k in h:
		var r := 7.0 - 2.4 * k / h
		var y := int(base.y) - k
		var band := (k / 9) % 2 == 1
		for x in range(int(base.x - r), int(base.x + r) + 1):
			var t := (x + 0.5 - base.x) / r
			var col := RED if band else WHITE
			cv.px(x, y, P.mul(col, 1.08 - 0.42 * (t * 0.5 + 0.5)))
	var top := base + Vector2(0, -h)
	cv.ellipse(top.x, top.y, 6.5, 2.4, Color8(48, 50, 52))
	cv.rect(int(top.x) - 3, int(top.y) - 7, 7, 6, Color8(250, 222, 120))
	cv.line_v(top + Vector2(-3, -7), top + Vector2(-3, -2), Color8(40, 40, 40))
	cv.line_v(top + Vector2(3, -7), top + Vector2(3, -2), Color8(40, 40, 40))
	cv.poly(PackedVector2Array([top + Vector2(-4, -7), top + Vector2(4, -7), top + Vector2(0, -12)]), RED)
	cv.rect(int(base.x) - 1, int(base.y) - h / 2 - 2, 2, 3, Color8(40, 46, 54))
	for f in [Vector2(-0.45, 0.3), Vector2(0.4, 0.4), Vector2(0.45, -0.2)]:
		soft.append([pr(o, f.x, f.y, 0.0), 5.0, 1.6])


static func _buoy(cv, o: Vector2, col: Color, cone: bool, soft: Array) -> void:
	var p := pr(o, 0.0, 0.0, 0.0)
	cv.ellipse(p.x, p.y - 2, 3.5, 2.6, P.mul(col, 0.8))
	cv.ellipse(p.x - 0.5, p.y - 3, 2.8, 2.0, col)
	if cone:
		cv.poly(PackedVector2Array([p + Vector2(-3, -5), p + Vector2(3, -5), p + Vector2(0, -11)]), col)
	else:
		cv.rect(int(p.x) - 2, int(p.y) - 10, 5, 6, col)
	cv.line_v(p + Vector2(0, -11), p + Vector2(0, -14), Color8(50, 50, 50))
	cv.px(int(p.x), int(p.y) - 15, Color8(255, 240, 170))
	soft.append([p, 6.0, 2.2])


static func _boathouse(cv, o: Vector2) -> void:
	var r: Dictionary = P.box(cv, o, Vector3(0, 0, 0), 0.95, 0.42, 14.0, 0.0, WOOD, 0.12, 720)
	for sd in r.sides:
		var q: PackedVector2Array = sd.quad
		for i in range(1, 9):
			var u := i / 9.0
			cv.line_v(q[0].lerp(q[1], u), q[3].lerp(q[2], u), P.mul(WOOD, 0.8))
		if (sd.n as Vector2).x > 0.5:  # open water door on the +x end
			cv.poly(P.sub(q, 0.15, 0.0, 0.85, 0.75), Color8(26, 30, 34))
	var roof := Color8(92, 96, 100)
	var e := [pr(o, -1.0, -0.47, 14.0), pr(o, 1.0, -0.47, 14.0), pr(o, 1.0, 0.47, 14.0), pr(o, -1.0, 0.47, 14.0)]
	var ridge := [pr(o, -1.0, 0.0, 23.0), pr(o, 1.0, 0.0, 23.0)]
	cv.poly(PackedVector2Array([e[0], e[1], ridge[1], ridge[0]]), P.mul(roof, 0.82), P.speckle(0.06, 721))
	cv.poly(PackedVector2Array([ridge[0], ridge[1], e[2], e[3]]), roof, P.speckle(0.06, 722))
	cv.poly(PackedVector2Array([e[1], e[2], ridge[1]]), P.mul(WOOD, 0.9))
	cv.line_v(ridge[0], ridge[1], P.mul(roof, 1.25))
