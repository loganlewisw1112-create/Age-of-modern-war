extends RefCounted
## Valley Conquest (valley_conquest_l, 256x256): a large valley (owner: MAP4,
## docs/CONTRACTS_G3b.md section 4; design: handoff 11_WORLD_MAPS "multiple industrial pockets,
## foothills, river branches, complex roads; dam, tunnel portal as scenery, airfield").
## Authored: an east-west main river with a reservoir at the centre, the DAM (bridge 0 = the hold
## bridge, a destructible span, centre so it is equidistant), west/east bridges (bridges 1/2), two
## main fords, a tributary branch per bank ending in a source lake (roads cross it on fords),
## foothill massifs on the north/south edges with a tunnel portal, an airfield per bank, four
## industrial pockets per bank, a road loop per bank, 8 spawns in mirror pairs.
## Seeded: meander amplitude, dirt, forest, small ridges, contested-pile jitter.
## Built to hold 10,000 units: validate() requires >= 72% of the map as open vehicle ground.
## Point-symmetric: (x, y) <-> (255-x, 255-y); north-bank features are mirrored by MapUtil.sset().

const MapUtil = preload("res://sim/maps/map_util.gd")

const ID := "valley_conquest_l"
const W := 256
const H := 256
## 0 N / 1 S, 2 NW / 3 SE, 4 NE / 5 SW, 6 W / 7 E. Pairs (2k, 2k+1) are mirrors.
const SPAWNS := [Vector2i(127, 14), Vector2i(128, 241), Vector2i(22, 24), Vector2i(233, 231),
	Vector2i(233, 24), Vector2i(22, 231), Vector2i(14, 72), Vector2i(241, 183)]
const SPAWN_SETS := {"2": [0, 1], "3": [0, 3, 5], "4": [2, 3, 4, 5]}
const MAX_SIDES := 4
const BRIDGE_X := 52                 # bridge 1 (west); its mirror x = 203 is bridge 2
const FORDS_X := [[70, 73], [182, 185]]
const BRANCH := [Vector2i(101, 124), Vector2i(100, 118), Vector2i(96, 100), Vector2i(88, 84), Vector2i(80, 74)]
const BASE := [[6, -2, "salvage", 2000], [7, 3, "salvage", 2000], [-6, 3, "salvage", 2000],
	[4, 7, "ore", 3000], [-5, -3, "ore", 3000]]
const FAIR_TOL := 1.3
const MIN_OPEN := 0.72


static func try_gen(seed_value: int, attempt: int) -> Dictionary:
	var rng := SimRng.new(seed_value * 3571 + attempt * 104729 + 41)
	var t := PackedByteArray()
	t.resize(W * H)
	t.fill(Terrain.GRASS)
	var n := W * H
	# --- main river with a reservoir widening around the dam (hw even in u, off odd in u)
	var a1 := rng.randf_range(3.0, 6.0)
	var a2 := rng.randf_range(1.0, 2.0)
	var f1 := rng.randf_range(0.02, 0.035)
	var f2 := rng.randf_range(0.06, 0.09)
	for i in n / 2:
		var u := float(i % W) - 127.5
		var off := a1 * sin(u * f1) + a2 * sin(u * f2)
		var hw := 3.0 + 4.0 * maxf(0.0, 1.0 - absf(u) / 28.0)
		if absf(float(i / W) - 127.5 - off) <= hw:
			t[i] = Terrain.WATER
			t[n - 1 - i] = Terrain.WATER
	var ford_cells := []
	for i in n:
		if t[i] == Terrain.WATER:
			var x := i % W
			for f in FORDS_X:
				if x >= int(f[0]) and x <= int(f[1]):
					t[i] = Terrain.FORD
					ford_cells.append(Vector2i(x, i / W))
	# --- foothill massifs + tunnel portal (north edge; mirrored to the south edge)
	var decor := []
	var pois := []
	_massif(t, Vector2i(60, 6), Vector2i(100, 10), 7.0)
	_massif(t, Vector2i(158, 5), Vector2i(196, 8), 5.5)
	MapUtil.rect(t, W, H, 75, 14, 84, 21, Terrain.RIDGE)
	# --- roads: loop per bank, spawn access, crossings
	var none := []
	MapUtil.road(t, W, H, [Vector2i(30, 44), Vector2i(225, 44), Vector2i(225, 100), Vector2i(30, 100), Vector2i(30, 44)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(127, 19), Vector2i(127, 44)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(22, 29), Vector2i(22, 44), Vector2i(30, 44)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(233, 29), Vector2i(233, 44), Vector2i(225, 44)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(19, 72), Vector2i(30, 72)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(80, 44), Vector2i(80, 24)], 1, -1, none)          # tunnel road
	MapUtil.road(t, W, H, [Vector2i(71, 100), Vector2i(71, 112)], 1, -1, none)        # west ford
	MapUtil.road(t, W, H, [Vector2i(160, 44), Vector2i(160, 56)], 1, -1, none)        # airfield
	_decor(t, decor, "tunnel_portal", Vector2i(79, 22), Vector2i(2, 2), true)
	pois.append({"type": "tunnel_portal", "name": "Tunnel Portal", "cell": Vector2i(80, 23)})
	var dam := []
	MapUtil.road(t, W, H, [Vector2i(127, 100), Vector2i(127, 155)], 2, Terrain.BRIDGE, dam)
	var b0 := []
	for c in dam:
		for q in [c, MapUtil.mirror(c, W, H)]:
			if not b0.has(q):
				b0.append(q)
	var crossed := []
	MapUtil.road(t, W, H, [Vector2i(BRIDGE_X, 100), Vector2i(BRIDGE_X, 155)], 1, Terrain.BRIDGE, crossed)
	var b2 := []
	for c in crossed:
		b2.append(MapUtil.mirror(c, W, H))
	pois.append({"type": "dam", "name": "Valley Dam", "cell": Vector2i(127, 127)})
	for c in b0:
		decor.append({"id": "dam_ns", "cell": c, "size": Vector2i(1, 1)})
	# --- tributary branch + source lake; roads it meets become fords
	_water_line(t, ford_cells, BRANCH, 1.6)
	_water_disc(t, ford_cells, Vector2i(78, 70), 5.0)
	pois.append({"type": "river_branch", "name": "North Branch", "cell": Vector2i(90, 90)})
	# --- airfield (north bank, east; mirrored)
	MapUtil.rect(t, W, H, 150, 50, 215, 68, Terrain.DIRT)
	for x in range(154, 212):
		for y in range(57, 61):
			_decor(t, decor, "airfield_tarmac_mark" if (x % 8 == 0 and y == 58) else "airfield_tarmac", Vector2i(x, y), Vector2i(1, 1), false)
	for hx in [160, 168, 176]:
		_decor(t, decor, "hangar", Vector2i(hx, 64), Vector2i(3, 2), true)
	pois.append({"type": "airfield", "name": "Airfield", "cell": Vector2i(182, 59)})
	# --- industrial pockets
	var piles := []
	for o in [Vector2i(40, 52), Vector2i(110, 60), Vector2i(190, 76), Vector2i(58, 104)]:
		_compound(t, decor, piles, o)
		pois.append({"type": "factory", "name": "Industrial Pocket", "cell": o + Vector2i(4, 4)})
	for c in [Vector2i(110, 106), Vector2i(117, 104), Vector2i(137, 104)]:
		piles.append(["ore", 4000, c])
	# --- base pads, protection, seeded features
	MapUtil.base_pads(t, W, H, SPAWNS, 4.5)
	var margin := ford_cells.duplicate()
	for dd in decor:   # keep industry / POIs reachable: no seeded forest or ridge next to them
		for yy in int(dd.size.y):
			for xx in int(dd.size.x):
				margin.append(Vector2i(dd.cell) + Vector2i(xx, yy))
	for pl in piles:
		margin.append(pl[2])
		margin.append(MapUtil.mirror(pl[2], W, H))
	margin.append_array(b0)
	margin.append_array(crossed)
	margin.append_array(b2)
	var prot := MapUtil.protect_mask(t, W, H, SPAWNS, 11.0, margin, 3)
	for k in 30:
		MapUtil.blob(t, prot, W, H, rng, Vector2i(rng.randi_range(4, 251), rng.randi_range(4, 110)), rng.randf_range(1.5, 4.0), Terrain.DIRT)
	for k in 34:
		MapUtil.blob(t, prot, W, H, rng, Vector2i(rng.randi_range(4, 251), rng.randi_range(4, 110)), rng.randf_range(2.0, 5.0), Terrain.FOREST)
	for k in 10:
		var p := Vector2(rng.randi_range(8, 247), rng.randi_range(8, 106))
		MapUtil.ridge_line(t, prot, W, H, rng, p, rng.randf_range(0.0, TAU), rng.randi_range(5, 10), 0.4)
	# --- resources
	var resources := []
	var taken := {}
	for si in [0, 2, 4, 6]:
		var s: Vector2i = SPAWNS[si]
		var sx := 1 if s.x <= W / 2 else -1
		var sy := 1 if s.y <= H / 2 else -1
		for b in BASE:
			MapUtil.add_res(t, W, H, SPAWNS, resources, taken, String(b[2]), int(b[3]), s + Vector2i(int(b[0]) * sx, int(b[1]) * sy))
	for p in piles:
		MapUtil.add_res(t, W, H, SPAWNS, resources, taken, String(p[0]), int(p[1]), p[2])
	for p in [["ore", 2500, Vector2i(66, 108)], ["salvage", 2000, Vector2i(178, 110)]]:
		var c: Vector2i = p[2] + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 1))
		MapUtil.add_res(t, W, H, SPAWNS, resources, taken, String(p[0]), int(p[1]), c)
	var m := {
		"id": ID, "name": "Valley Conquest", "size": "l", "w": W, "h": H,
		"terrain": t, "spawns": SPAWNS.duplicate(), "spawn_sets": SPAWN_SETS.duplicate(true),
		"max_sides": MAX_SIDES, "resources": resources,
		"bridges": [{"id": 0, "name": "Valley Dam", "cells": b0}, {"id": 1, "name": "West Bridge", "cells": crossed},
			{"id": 2, "name": "East Bridge", "cells": b2}],
		"hold_bridge": 0, "bridge_cells": b0.duplicate(), "ford_cells": ford_cells,
		"decor": decor, "pois": _mirror_pois(pois), "seed": seed_value, "river_params": [a1, a2, f1, f2],
		"fair_tol": FAIR_TOL, "min_open_frac": MIN_OPEN,
	}
	_height(m, seed_value, attempt)
	return m


static func _massif(t: PackedByteArray, a: Vector2i, b: Vector2i, r: float) -> void:
	var steps := int(Vector2(b - a).length())
	for s in steps + 1:
		var p := Vector2(a).lerp(Vector2(b), float(s) / float(maxi(steps, 1)))
		var rr := r * (0.75 + 0.25 * sin(float(s) * 0.5))
		var ri := int(ceil(rr))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				if Vector2(dx, dy).length() <= rr:
					MapUtil.sset(t, W, H, Vector2i(roundi(p.x) + dx, roundi(p.y) + dy), Terrain.RIDGE)


## Water polyline; a road it crosses becomes a ford (roads stay open across the branch).
static func _water_line(t: PackedByteArray, ford_cells: Array, pts: Array, r: float) -> void:
	for k in range(pts.size() - 1):
		var a: Vector2i = pts[k]
		var b: Vector2i = pts[k + 1]
		var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
		for s in steps + 1:
			_water_disc(t, ford_cells, Vector2i(Vector2(a).lerp(Vector2(b), float(s) / float(maxi(steps, 1))).round()), r)


static func _water_disc(t: PackedByteArray, ford_cells: Array, c: Vector2i, r: float) -> void:
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var q := c + Vector2i(dx, dy)
			if not MapUtil.inb(q, W, H) or Vector2(dx, dy).length() > r:
				continue
			var code := t[q.y * W + q.x]
			if code == Terrain.ROAD:
				if not ford_cells.has(q):
					ford_cells.append(q)
					ford_cells.append(MapUtil.mirror(q, W, H))
				MapUtil.sset(t, W, H, q, Terrain.FORD)
			elif code != Terrain.FORD and code != Terrain.BRIDGE:
				MapUtil.sset(t, W, H, q, Terrain.WATER)


static func _compound(t: PackedByteArray, decor: Array, piles: Array, o: Vector2i) -> void:
	for d in [Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 5), Vector2i(5, 5)]:
		_decor(t, decor, "factory_block", o + d, Vector2i(3, 3), true)
	for c in [o + Vector2i(-2, 4), o + Vector2i(9, 4), o + Vector2i(4, 9)]:
		piles.append(["salvage", 2000, c])


static func _decor(t: PackedByteArray, decor: Array, id: String, o: Vector2i, sz: Vector2i, solid: bool) -> void:
	MapUtil.rect(t, W, H, o.x, o.y, o.x + sz.x - 1, o.y + sz.y - 1, Terrain.RIDGE if solid else Terrain.ROAD)
	decor.append({"id": id, "cell": o, "size": sz})
	decor.append({"id": id, "cell": Vector2i(W - sz.x - o.x, H - sz.y - o.y), "size": sz})


static func _mirror_pois(pois: Array) -> Array:
	var out := []
	for p in pois:
		out.append(p)
		if p.type != "dam":
			var q: Dictionary = p.duplicate()
			q.cell = MapUtil.mirror(p.cell, W, H)
			out.append(q)
	return out


# ================================================================ G6 height (owner ELEV, CONTRACTS_G6 section 7.5)
## Real valleys and ridges: the river, reservoir and north branch sit in a valley floor (level 0, 6 cells
## either side of the water); the north massifs rise out of foothills (level 2, 12 cells) onto ridge
## plateaus (level 3, 9 cells); two interior hills (level 2) carry ridge caps (level 3). Everything is
## mirrored onto the south bank. Floor / plateau edges get a ramp every third cell plus every road,
## bridge approach, ford and dirt tile; hill edges are all ramps; connect_ramps joins anything left.
## Spawn sites are flat. No rng draw: the terrain stream above is untouched.
static func _height(m: Dictionary, _seed_value: int, _attempt: int) -> void:
	var t: PackedByteArray = m.terrain
	var hg := MapUtil.new_layer(W, H, 1)
	MapUtil.basin(hg, t, W, H, 6, 0)
	MapUtil.hband(hg, W, H, [Vector2i(60, 6), Vector2i(100, 10)], 12.0, 2, MapUtil.HRAISE)
	MapUtil.hband(hg, W, H, [Vector2i(60, 6), Vector2i(100, 10)], 9.0, 3, MapUtil.HRAISE)
	MapUtil.hband(hg, W, H, [Vector2i(158, 5), Vector2i(196, 8)], 10.0, 2, MapUtil.HRAISE)
	MapUtil.hband(hg, W, H, [Vector2i(158, 5), Vector2i(196, 8)], 7.5, 3, MapUtil.HRAISE)
	MapUtil.hdisc(hg, W, H, Vector2i(140, 82), 7.0, 2, MapUtil.HRAISE)
	MapUtil.hdisc(hg, W, H, Vector2i(141, 81), 3.0, 3, MapUtil.HRAISE)
	MapUtil.hdisc(hg, W, H, Vector2i(60, 75), 6.0, 2, MapUtil.HRAISE)
	MapUtil.hdisc(hg, W, H, Vector2i(61, 74), 2.5, 3, MapUtil.HRAISE)
	for s in SPAWNS:
		MapUtil.hflat(hg, W, H, s, 9.0)
	m.height = hg
	m.ramps = MapUtil.derive_ramps(hg, t, W, H, [3, 1, 3])
	MapUtil.connect_ramps(m, true)
