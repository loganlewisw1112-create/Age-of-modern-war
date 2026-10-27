extends RefCounted
## G7 (SCALE7): Last Protocol scale test map (lp_test512, 512x512; lp_test768 = the same layout at 768x768).
## A generated stand-in used by bench/tests and by later agents until LPMAP7's hand-built map exists.
## Layout (all coordinates scale with the map side N; s = N / 512):
##  - two main spawns far apart in the NW and SE corners (spawns 0/1), two extra in NE / SW (spawns 2/3);
##  - a wide east-west river through the middle with three bridges (west, centre, east) and two fords;
##  - a road net: a ring road per bank, spawn access roads, the three bridge roads, a ford road;
##  - towns (dirt plaza + houses) and industrial blocks along the roads;
##  - seeded forest, dirt and small ridge lines; height: a river valley, hills and plateaus, flat spawns.
## Point-symmetric like every generated map: (x, y) <-> (N-1-x, N-1-y) (MapUtil.sset mirrors each write).

const MapUtil = preload("res://sim/maps/map_util.gd")

const ID := "lp_test512"
const ID768 := "lp_test768"
const N512 := 512
const N768 := 768
const MAX_SIDES := 4
const SPAWN_SETS := {"2": [0, 1], "4": [0, 1, 2, 3]}   # no 3-side set: an odd set cannot be fair here
const FAIR_TOL := 1.3
const MIN_OPEN := 0.70
## Base resources per spawn (offset from the spawn, mirrored automatically by add_res).
const BASE := [[7, -2, "salvage", 3000], [7, 4, "salvage", 3000], [-6, 4, "salvage", 3000],
	[3, 8, "ore", 4000], [-5, -4, "ore", 4000]]


static func try_gen(seed_value: int, attempt: int) -> Dictionary:
	return gen(seed_value, attempt, N512)


static func try_gen_768(seed_value: int, attempt: int) -> Dictionary:
	return gen(seed_value, attempt, N768)


## Scaled cell: v is a coordinate on the 512 layout.
static func _s(v: int, n: int) -> int:
	return int(round(float(v) * float(n) / 512.0))


static func _sv(v: Vector2i, n: int) -> Vector2i:
	return Vector2i(_s(v.x, n), _s(v.y, n))


static func spawns_for(n: int) -> Array:
	var a := _sv(Vector2i(48, 48), n)
	var c := Vector2i(n - 1 - _s(56, n), _s(40, n))
	return [a, MapUtil.mirror(a, n, n), c, MapUtil.mirror(c, n, n)]


static func gen(seed_value: int, attempt: int, n: int) -> Dictionary:
	var rng := SimRng.new(seed_value * 6151 + attempt * 104729 + 512 + n)
	var t := PackedByteArray()
	t.resize(n * n)
	t.fill(Terrain.GRASS)
	var spawns := spawns_for(n)
	var half := n / 2
	var mid := float(n - 1) * 0.5
	# --- river: |y - mid - off(u)| <= hw, u = x - mid; off is odd in u, so painting the north half and
	# mirroring keeps the map symmetric (same construction as valley_conquest_l)
	var a1 := rng.randf_range(5.0, 9.0) * float(n) / 512.0
	var a2 := rng.randf_range(2.0, 4.0) * float(n) / 512.0
	var f1 := rng.randf_range(0.010, 0.016) * 512.0 / float(n)
	var f2 := rng.randf_range(0.03, 0.05) * 512.0 / float(n)
	var hw := 3.5 * float(n) / 512.0
	var total := n * n
	for i in total / 2:
		var u := float(i % n) - mid
		var off := a1 * sin(u * f1) + a2 * sin(u * f2)
		if absf(float(i / n) - mid - off) <= hw:
			t[i] = Terrain.WATER
			t[total - 1 - i] = Terrain.WATER
	# --- roads (MapUtil.road mirrors every cell); bridge roads cross the river at three x positions
	var none := []
	var ring := [_sv(Vector2i(48, 96), n), _sv(Vector2i(464, 96), n), _sv(Vector2i(464, 200), n),
		_sv(Vector2i(48, 200), n), _sv(Vector2i(48, 96), n)]
	MapUtil.road(t, n, n, ring, 1, -1, none)
	MapUtil.road(t, n, n, [spawns[0] + Vector2i(0, 6), Vector2i(spawns[0].x, ring[0].y)], 1, -1, none)
	MapUtil.road(t, n, n, [spawns[2] + Vector2i(0, 6), Vector2i(spawns[2].x, ring[0].y)], 1, -1, none)
	var bridges := []
	var bridge_cells := []
	var west := []
	MapUtil.road(t, n, n, [Vector2i(_s(128, n), ring[2].y), Vector2i(_s(128, n), n - 1 - ring[2].y)], 1, Terrain.BRIDGE, west)
	var centre_x := []
	MapUtil.road(t, n, n, [Vector2i(half - 1, ring[2].y), Vector2i(half - 1, n - 1 - ring[2].y)], 1, Terrain.BRIDGE, centre_x)
	var centre := []
	for c in centre_x:
		for q in [c, MapUtil.mirror(c, n, n)]:
			if not centre.has(q):
				centre.append(q)
	var east := []
	for c in west:
		east.append(MapUtil.mirror(c, n, n))
	bridges.append({"id": 0, "name": "West Bridge", "cells": west})
	bridges.append({"id": 1, "name": "Centre Bridge", "cells": centre})
	bridges.append({"id": 2, "name": "East Bridge", "cells": east})
	for b in bridges:
		bridge_cells.append_array(b.cells)
	# --- fords: two columns of river cells become fords (mirrored by symmetry of the river)
	var ford_cells := []
	var fx := [_s(200, n), n - 3 - _s(200, n)]   # columns [f, f+2] mirror onto each other
	for i in total:
		if t[i] == Terrain.WATER:
			var x := i % n
			for f in fx:
				if x >= int(f) and x <= int(f) + 2:
					t[i] = Terrain.FORD
					ford_cells.append(Vector2i(x, i / n))
	MapUtil.road(t, n, n, [Vector2i(fx[0] + 1, ring[2].y), Vector2i(fx[0] + 1, half - _s(12, n))], 1, -1, none)
	# --- towns (plaza + 4 houses) and industrial blocks (north bank; mirrored onto the south bank)
	var decor := []
	var pois := []
	for o in [Vector2i(150, 86), Vector2i(330, 86), Vector2i(250, 150), Vector2i(90, 170), Vector2i(410, 170)]:
		var p := _sv(o, n)
		MapUtil.rect(t, n, n, p.x, p.y, p.x + 6, p.y + 6, Terrain.DIRT)
		for hd in [Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 5), Vector2i(5, 5)]:
			_decor(t, decor, n, "town_house", p + hd, Vector2i(2, 2), true)
		pois.append({"type": "town", "name": "Town", "cell": p + Vector2i(3, 3)})
	for o in [Vector2i(200, 110), Vector2i(380, 120)]:
		var p := _sv(o, n)
		for d in [Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 5), Vector2i(5, 5)]:
			_decor(t, decor, n, "factory_block", p + d, Vector2i(3, 3), true)
		pois.append({"type": "factory", "name": "Industrial Block", "cell": p + Vector2i(4, 4)})
	# --- base pads, protection, seeded features (north half only: the mirror fills the south)
	MapUtil.base_pads(t, n, n, spawns, 5.0)
	var margin := ford_cells.duplicate()
	margin.append_array(bridge_cells)
	for dd in decor:
		for yy in int(dd.size.y):
			for xx in int(dd.size.x):
				margin.append(Vector2i(dd.cell) + Vector2i(xx, yy))
	var prot := MapUtil.protect_mask(t, n, n, spawns, 12.0, margin, 3)
	var area := float(n * n) / float(512 * 512)
	var ymax := half - _s(16, n)
	for k in int(120 * area):
		MapUtil.blob(t, prot, n, n, rng, Vector2i(rng.randi_range(4, n - 5), rng.randi_range(4, ymax)), rng.randf_range(1.5, 4.0), Terrain.DIRT)
	for k in int(150 * area):
		MapUtil.blob(t, prot, n, n, rng, Vector2i(rng.randi_range(4, n - 5), rng.randi_range(4, ymax)), rng.randf_range(2.0, 6.0), Terrain.FOREST)
	for k in int(36 * area):
		var p := Vector2(rng.randi_range(8, n - 9), rng.randi_range(8, ymax - 4))
		MapUtil.ridge_line(t, prot, n, n, rng, p, rng.randf_range(0.0, TAU), rng.randi_range(5, 12), 0.4)
	# --- resources: base sets per north-bank spawn (mirrored to 1/3), contested piles near the towns
	var resources := []
	var taken := {}
	for si in [0, 2]:
		var s: Vector2i = spawns[si]
		var sx := 1 if s.x <= half else -1
		var sy := 1 if s.y <= half else -1
		for b in BASE:
			MapUtil.add_res(t, n, n, spawns, resources, taken, String(b[2]), int(b[3]), s + Vector2i(int(b[0]) * sx, int(b[1]) * sy))
	for o in [Vector2i(160, 100), Vector2i(340, 100), Vector2i(258, 166), Vector2i(100, 184), Vector2i(420, 184), Vector2i(256, 230)]:
		MapUtil.add_res(t, n, n, spawns, resources, taken, "ore" if o.x % 2 == 0 else "salvage", 4000, _sv(o, n))
	var m := {
		"id": ID if n == N512 else (ID768 if n == N768 else "lp_test%d" % n),
		"name": "LP Scale Test %d" % n, "size": "xl", "w": n, "h": n,
		"terrain": t, "spawns": spawns, "spawn_sets": SPAWN_SETS.duplicate(true),
		"max_sides": MAX_SIDES, "resources": resources, "bridges": bridges,
		"hold_bridge": 1, "bridge_cells": (bridges[1].cells as Array).duplicate(), "ford_cells": ford_cells,
		"decor": decor, "pois": _mirror_pois(pois, n), "seed": seed_value, "river_params": [a1, a2, f1, f2],
		"fair_tol": FAIR_TOL, "min_open_frac": MIN_OPEN,
	}
	_height(m, n, spawns)
	return m


static func _decor(t: PackedByteArray, decor: Array, n: int, id: String, o: Vector2i, sz: Vector2i, solid: bool) -> void:
	MapUtil.rect(t, n, n, o.x, o.y, o.x + sz.x - 1, o.y + sz.y - 1, Terrain.RIDGE if solid else Terrain.ROAD)
	decor.append({"id": id, "cell": o, "size": sz})
	decor.append({"id": id, "cell": Vector2i(n - sz.x - o.x, n - sz.y - o.y), "size": sz})


static func _mirror_pois(pois: Array, n: int) -> Array:
	var out := []
	for p in pois:
		out.append(p)
		var q: Dictionary = p.duplicate()
		q.cell = MapUtil.mirror(p.cell, n, n)
		out.append(q)
	return out


## Height: the river sits in a valley floor (level 0, 8 cells either side); two hill massifs per bank
## (level 2) with ridge caps (level 3); spawns flat. Ramps on every 3rd edge cell + roads/fords/bridges,
## then connect_ramps joins anything left (same recipe as valley_conquest_l). No rng draw.
static func _height(m: Dictionary, n: int, spawns: Array) -> void:
	var t: PackedByteArray = m.terrain
	var hg := MapUtil.new_layer(n, n, 1)
	MapUtil.basin(hg, t, n, n, _s(8, n), 0)
	for hc in [[Vector2i(120, 140), 14.0], [Vector2i(300, 60), 12.0], [Vector2i(430, 140), 10.0]]:
		var c := _sv(hc[0], n)
		var r: float = float(hc[1]) * float(n) / 512.0
		MapUtil.hdisc(hg, n, n, c, r, 2, MapUtil.HRAISE)
		MapUtil.hdisc(hg, n, n, c + Vector2i(1, -1), r * 0.45, 3, MapUtil.HRAISE)
	for s in spawns:
		MapUtil.hflat(hg, n, n, s, 10.0)
	m.height = hg
	m.ramps = MapUtil.derive_ramps(hg, t, n, n, [3, 1, 3])
	MapUtil.connect_ramps(m, true)
