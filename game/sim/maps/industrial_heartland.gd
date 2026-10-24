extends RefCounted
## Industrial Heartland (industrial_heartland_m, 160x160): a medium river basin (owner: MAP4,
## docs/CONTRACTS_G3b.md section 4; design: handoff 11_WORLD_MAPS "factories, train yards,
## scattered towns, road loops").
## Authored (seed never changes these): an east-west river through the centre, two bridges
## (x=39 west = bridge 0 / hold bridge, x=120 east), a centre ford and two flank fords, one road
## loop per bank, factory compounds, a rail siding, a refinery site (rich ore) by the centre ford,
## a ruined plant (salvage-rich), two towns, 6 spawns in mirror pairs. Seeded: river meander
## amplitude, dirt patches, forest clusters, small ridges, contested-pile jitter.
## Point-symmetric: (x, y) <-> (159-x, 159-y). Everything below is written for the north bank
## and mirrored onto the south bank by MapUtil.sset().

const MapUtil = preload("res://sim/maps/map_util.gd")

const ID := "industrial_heartland_m"
const W := 160
const H := 160
## 0 N / 1 S (centre column), 2 NW / 3 SE, 4 NE / 5 SW. Pairs (2k, 2k+1) are mirrors.
const SPAWNS := [Vector2i(79, 13), Vector2i(80, 146), Vector2i(18, 20), Vector2i(141, 139),
	Vector2i(141, 20), Vector2i(18, 139)]
const SPAWN_SETS := {"2": [0, 1], "3": [0, 3, 5], "4": [2, 3, 4, 5]}
const MAX_SIDES := 4
const RIVER_HALF_WIDTH := 2.4
const BRIDGE_X := 39          # bridge 0; its mirror (x = 120) is bridge 1
const FORDS_X := [[77, 82], [8, 11], [148, 151]]   # centre ford (self-mirrored) + flank pair
## Base package offsets (dx, dy, res, amount), reflected so +x/+y point toward the map centre.
const BASE := [[6, -2, "salvage", 2000], [7, 3, "salvage", 2000], [-6, 3, "salvage", 2000],
	[4, 7, "ore", 3000], [-5, -3, "ore", 3000]]
const FAIR_TOL := 1.3
const MIN_OPEN := 0.70



static func try_gen(seed_value: int, attempt: int) -> Dictionary:
	var rng := SimRng.new(seed_value * 6151 + attempt * 104729 + 29)
	var t := PackedByteArray()
	t.resize(W * H)
	t.fill(Terrain.GRASS)
	var n := W * H
	# --- river: |y - 79.5 - off(u)| <= hw with u = x - 79.5 and off odd in u (point symmetry)
	var a1 := rng.randf_range(1.5, 3.5)
	var a2 := rng.randf_range(0.4, 1.2)
	var f1 := rng.randf_range(0.03, 0.05)
	var f2 := rng.randf_range(0.09, 0.13)
	for i in n / 2:
		var x := i % W
		var y := i / W
		var u := float(x) - 79.5
		var off := a1 * sin(u * f1) + a2 * sin(u * f2)
		if absf(float(y) - 79.5 - off) <= RIVER_HALF_WIDTH:
			t[i] = Terrain.WATER
			t[n - 1 - i] = Terrain.WATER
	# --- fords (fixed columns)
	var ford_cells := []
	for i in n:
		if t[i] != Terrain.WATER:
			continue
		var x := i % W
		for f in FORDS_X:
			if x >= int(f[0]) and x <= int(f[1]):
				t[i] = Terrain.FORD
				ford_cells.append(Vector2i(x, i / W))
	# --- roads: north loop (mirrored = south loop), spawn access, crossings
	var crossed := []
	var none := []
	MapUtil.road(t, W, H, [Vector2i(14, 32), Vector2i(145, 32), Vector2i(145, 58), Vector2i(14, 58), Vector2i(14, 32)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(79, 18), Vector2i(79, 32)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(18, 25), Vector2i(18, 32)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(141, 25), Vector2i(141, 32)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(79, 58), Vector2i(79, 70)], 1, -1, none)    # to the centre ford
	MapUtil.road(t, W, H, [Vector2i(14, 58), Vector2i(10, 70)], 1, -1, none)    # to the flank ford
	MapUtil.road(t, W, H, [Vector2i(BRIDGE_X, 58), Vector2i(BRIDGE_X, 101)], 1, Terrain.BRIDGE, crossed)
	var b0 := []
	var b1 := []
	for c in crossed:
		b0.append(c)
		b1.append(MapUtil.mirror(c, W, H))
	# --- industry (north bank; mirrored)
	var decor := []
	var pois := []
	var piles := []   # [res, amount, cell] placed after seeded features
	_compound(t, decor, piles, Vector2i(98, 36), "factory_block", 3, 2000)
	_compound(t, decor, piles, Vector2i(52, 62), "factory_block", 3, 2000)
	pois.append({"type": "factory", "name": "Works Yard", "cell": Vector2i(102, 40)})
	pois.append({"type": "factory", "name": "River Mills", "cell": Vector2i(56, 66)})
	# ruined plant: salvage-rich
	for o in [Vector2i(24, 38), Vector2i(30, 40), Vector2i(25, 44)]:
		_decor(t, decor, "ruined_plant", o, Vector2i(3, 3), true)
	for c in [Vector2i(22, 49), Vector2i(35, 38), Vector2i(34, 46), Vector2i(20, 42)]:
		piles.append(["salvage", 2500, c])
	pois.append({"type": "ruined_plant", "name": "Ruined Plant", "cell": Vector2i(28, 42)})
	# refinery site by the centre ford: rich ore, contested
	_decor(t, decor, "refinery_tanks", Vector2i(72, 61), Vector2i(2, 2), true)
	_decor(t, decor, "refinery_tanks", Vector2i(86, 61), Vector2i(2, 2), true)
	for c in [Vector2i(70, 66), Vector2i(75, 66), Vector2i(84, 66), Vector2i(89, 65)]:
		piles.append(["ore", 4000, c])
	pois.append({"type": "refinery", "name": "Refinery", "cell": Vector2i(79, 64)})
	# rail siding: main line + siding track (road cells: passable, not buildable)
	for x in range(20, 97):
		_decor(t, decor, "rail_ew", Vector2i(x, 50), Vector2i(1, 1), false)
	for x in range(60, 95):
		_decor(t, decor, "rail_ew", Vector2i(x, 52), Vector2i(1, 1), false)
	pois.append({"type": "rail_siding", "name": "Rail Siding", "cell": Vector2i(60, 51)})
	# towns: dirt plaza + four houses
	for o in [Vector2i(52, 36), Vector2i(118, 38)]:
		MapUtil.rect(t, W, H, o.x, o.y, o.x + 6, o.y + 6, Terrain.DIRT)
		for hd in [Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 5), Vector2i(5, 5)]:
			_decor(t, decor, "town_house", o + hd, Vector2i(2, 2), true)
	pois.append({"type": "town", "name": "Ashford", "cell": Vector2i(55, 39)})
	pois.append({"type": "town", "name": "Coldwell", "cell": Vector2i(121, 41)})
	pois.append({"type": "bridge", "name": "West Bridge", "cell": Vector2i(BRIDGE_X, 79)})
	pois.append({"type": "bridge", "name": "East Bridge", "cell": Vector2i(W - 1 - BRIDGE_X, 80)})
	pois.append({"type": "ford", "name": "Centre Ford", "cell": Vector2i(79, 79)})
	# --- base pads, then protection for seeded features
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
	margin.append_array(b1)
	var prot := MapUtil.protect_mask(t, W, H, SPAWNS, 11.0, margin, 3)
	# --- seeded features (north half; mirrored)
	for k in 16:
		MapUtil.blob(t, prot, W, H, rng, Vector2i(rng.randi_range(4, 155), rng.randi_range(4, 74)), rng.randf_range(1.5, 3.5), Terrain.DIRT)
	for k in 20:
		MapUtil.blob(t, prot, W, H, rng, Vector2i(rng.randi_range(4, 155), rng.randi_range(4, 74)), rng.randf_range(2.0, 4.5), Terrain.FOREST)
	for k in 5:
		var p := Vector2(rng.randi_range(8, 150), rng.randi_range(8, 70))
		MapUtil.ridge_line(t, prot, W, H, rng, p, rng.randf_range(0.0, TAU), rng.randi_range(5, 9), 0.4)
	# --- resources: identical base packages, then POI piles, then contested flank piles
	var resources := []
	var taken := {}
	for si in [0, 2, 4]:
		var s: Vector2i = SPAWNS[si]
		var sx := 1 if s.x <= W / 2 else -1
		var sy := 1 if s.y <= H / 2 else -1
		for b in BASE:
			MapUtil.add_res(t, W, H, SPAWNS, resources, taken, String(b[2]), int(b[3]), s + Vector2i(int(b[0]) * sx, int(b[1]) * sy))
	for p in piles:
		MapUtil.add_res(t, W, H, SPAWNS, resources, taken, String(p[0]), int(p[1]), p[2])
	var flank := [["ore", 2500, Vector2i(18, 69)], ["salvage", 2000, Vector2i(24, 66)]]
	for p in flank:
		var c: Vector2i = p[2] + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 1))
		MapUtil.add_res(t, W, H, SPAWNS, resources, taken, String(p[0]), int(p[1]), c)
	return {
		"id": ID, "name": "Industrial Heartland", "size": "m", "w": W, "h": H,
		"terrain": t, "spawns": SPAWNS.duplicate(), "spawn_sets": SPAWN_SETS.duplicate(true),
		"max_sides": MAX_SIDES, "resources": resources,
		"bridges": [{"id": 0, "name": "West Bridge", "cells": b0}, {"id": 1, "name": "East Bridge", "cells": b1}],
		"hold_bridge": 0, "bridge_cells": b0.duplicate(), "ford_cells": ford_cells,
		"decor": decor, "pois": _mirror_pois(pois), "seed": seed_value, "river_params": [a1, a2, f1, f2],
		"fair_tol": FAIR_TOL, "min_open_frac": MIN_OPEN,
	}


## A 2x2 compound of 3x3 blocks with 2-cell alleys and one salvage pile per side.
static func _compound(t: PackedByteArray, decor: Array, piles: Array, o: Vector2i, id: String, s: int, amount: int) -> void:
	for d in [Vector2i(0, 0), Vector2i(s + 2, 0), Vector2i(0, s + 2), Vector2i(s + 2, s + 2)]:
		_decor(t, decor, id, o + d, Vector2i(s, s), true)
	var span := 2 * s + 2
	for c in [o + Vector2i(-2, span / 2), o + Vector2i(span + 1, span / 2), o + Vector2i(span / 2, span + 1)]:
		piles.append(["salvage", amount, c])


## Decor footprint (top-left o, size sz) plus its mirror. Impassable footprints become RIDGE
## until ORCH adds a building-terrain code; passable ones (rail) become ROAD.
static func _decor(t: PackedByteArray, decor: Array, id: String, o: Vector2i, sz: Vector2i, solid: bool) -> void:
	MapUtil.rect(t, W, H, o.x, o.y, o.x + sz.x - 1, o.y + sz.y - 1, Terrain.RIDGE if solid else Terrain.ROAD)
	decor.append({"id": id, "cell": o, "size": sz})
	decor.append({"id": id, "cell": Vector2i(W - sz.x - o.x, H - sz.y - o.y), "size": sz})


static func _mirror_pois(pois: Array) -> Array:
	var out := []
	for p in pois:
		out.append(p)
		if p.type == "factory" or p.type == "ruined_plant" or p.type == "refinery" or p.type == "town" or p.type == "rail_siding":
			var q: Dictionary = p.duplicate()
			q.cell = MapUtil.mirror(p.cell, W, H)
			out.append(q)
	return out
