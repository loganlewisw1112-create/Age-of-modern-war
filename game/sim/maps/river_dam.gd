extends RefCounted
## River Dam (river_dam_m, 128x128): survival stronghold (owner: MODES6, CONTRACTS_G6 section 15,
## PLAN_G6 D42 "dam and bridges", vision 02-04).
## Authored: an east-west river through the centre that widens into a reservoir at the dam; the DAM is
## a 4-wide causeway (ROAD over water, map.dam_cells, not destructible); a west and an east bridge
## (bridges 0/1, destructible spans; bridge 0 is the hold bridge). The river valley is level 0 (gentle
## slopes); each bank has a level-2 bluff over the dam (spawns 0/1, ramps only where roads climb it), a
## cross road and two lanes to the map edge. The river is a real barrier: without the dam and the
## bridges no foot route links the banks (validate). Survival: the defender holds the south bluff
## (2 sides use spawns [0, 1]; co-op adds the SE corner); map.wave_spawns are the north lane ends.
## Seeded: river meander, forest clusters and dirt patches (roads, bluffs, crossings protected).
## Point-symmetric: (x, y) <-> (127-x, 127-y). _height() draws no rng, so terrain bytes stay stable.

const MapUtil = preload("res://sim/maps/map_util.gd")
const MapCheck = preload("res://sim/maps/map_check.gd")
const Elevation = preload("res://sim/systems/elevation.gd")
const RidgeBastion = preload("res://sim/maps/ridge_bastion.gd")   # shared lanes() check

const ID := "river_dam_m"
const W := 128
const H := 128
## 0 south bluff (defender) / 1 north bluff, 2 NW / 3 SE. Pairs (2k, 2k+1) are mirrors.
const SPAWNS := [Vector2i(63, 104), Vector2i(64, 23), Vector2i(14, 12), Vector2i(113, 115)]
const SPAWN_SETS := {"2": [0, 1], "3": [0, 3, 1], "4": [0, 3, 2, 1]}
const MAX_SIDES := 4
const RIVER_HW := 2.4
const RESERVOIR := 5.0        # extra half width at the dam, fading over RESERVOIR_U cells
const RESERVOIR_U := 18.0
const DAM_X := 63             # dam road centre column (half 1, mirrored: 4 wide)
const BRIDGE_X := 24          # bridge 0 (west); its mirror x = 103 is bridge 1
const BLUFF_R := 9.0
## North lane ends: two north lanes, west and east ends of the north cross road.
const WAVE_SPAWNS := [Vector2i(40, 2), Vector2i(87, 2), Vector2i(2, 30), Vector2i(125, 30)]
const BASE := [[6, -2, "salvage", 2000], [7, 3, "salvage", 2000], [-6, 3, "salvage", 2000],
	[4, 7, "ore", 3000], [-5, -3, "ore", 3000]]
const FAIR_TOL := 2.5
const MIN_OPEN := 0.55


static func try_gen(seed_value: int, attempt: int) -> Dictionary:
	var rng := SimRng.new(seed_value * 5303 + attempt * 104729 + 61)
	var t := PackedByteArray()
	t.resize(W * H)
	t.fill(Terrain.GRASS)
	var n := W * H
	# --- river + reservoir: |y - 63.5 - off(u)| <= hw(u), off odd and hw even in u (point symmetry)
	var a1 := rng.randf_range(1.5, 3.0)
	var a2 := rng.randf_range(0.4, 1.0)
	var f1 := rng.randf_range(0.04, 0.06)
	var f2 := rng.randf_range(0.10, 0.14)
	for i in n / 2:
		var u := float(i % W) - 63.5
		var off := a1 * sin(u * f1) + a2 * sin(u * f2)
		var hw := RIVER_HW + RESERVOIR * maxf(0.0, 1.0 - absf(u) / RESERVOIR_U)
		if absf(float(i / W) - 63.5 - off) <= hw:
			t[i] = Terrain.WATER
			t[n - 1 - i] = Terrain.WATER
	# --- crossings: the dam (causeway) and the west bridge (mirror: east bridge)
	var dam := []
	MapUtil.road(t, W, H, [Vector2i(DAM_X, 31), Vector2i(DAM_X, 96)], 1, Terrain.ROAD, dam)
	var crossed := []
	MapUtil.road(t, W, H, [Vector2i(BRIDGE_X, 31), Vector2i(BRIDGE_X, 96)], 1, Terrain.BRIDGE, crossed)
	var dam_cells := []
	for c in dam:
		for cc in [c, MapUtil.mirror(c, W, H)]:
			if not dam_cells.has(cc):
				dam_cells.append(cc)
	var b0 := []
	var b1 := []
	for c in crossed:
		b0.append(c)
		b1.append(MapUtil.mirror(c, W, H))
	# --- north bank roads (mirrored onto the south bank): cross road + two lanes to the north edge
	var none := []
	MapUtil.road(t, W, H, [Vector2i(0, 30), Vector2i(127, 30)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(40, 0), Vector2i(40, 30)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(87, 0), Vector2i(87, 30)], 1, -1, none)
	MapUtil.base_pads(t, W, H, SPAWNS, 4.5)
	var pois := [{"type": "dam", "name": "The Dam", "cell": Vector2i(DAM_X, 63)},
		{"type": "bridge", "name": "West Bridge", "cell": Vector2i(BRIDGE_X, 63)},
		{"type": "bridge", "name": "East Bridge", "cell": Vector2i(W - 1 - BRIDGE_X, 64)},
		{"type": "bluff", "name": "South Bluff", "cell": SPAWNS[0]},
		{"type": "bluff", "name": "North Bluff", "cell": SPAWNS[1]}]
	# --- protection, then seeded bank features (north half; mirrored)
	var margin := dam_cells.duplicate()
	margin.append_array(b0)
	margin.append_array(b1)
	for s in [SPAWNS[0], SPAWNS[1]]:
		for dy in range(-10, 11):
			for dx in range(-10, 11):
				margin.append((s as Vector2i) + Vector2i(dx, dy))
	for c in WAVE_SPAWNS:
		margin.append(c)
	var prot := MapUtil.protect_mask(t, W, H, SPAWNS, 10.0, margin, 3)
	for k in 10:
		MapUtil.blob(t, prot, W, H, rng, Vector2i(rng.randi_range(4, 123), rng.randi_range(4, 50)), rng.randf_range(1.5, 3.0), Terrain.DIRT)
	for k in 14:
		MapUtil.blob(t, prot, W, H, rng, Vector2i(rng.randi_range(4, 123), rng.randi_range(4, 50)), rng.randf_range(1.5, 3.2), Terrain.FOREST)
	# --- resources: base packages, then contested piles by the crossings
	var resources := []
	var taken := {}
	for si in [0, 2]:
		var s: Vector2i = SPAWNS[si]
		var sx := 1 if s.x <= W / 2 else -1
		var sy := 1 if s.y <= H / 2 else -1
		for b in BASE:
			MapUtil.add_res(t, W, H, SPAWNS, resources, taken, String(b[2]), int(b[3]), s + Vector2i(int(b[0]) * sx, int(b[1]) * sy))
	for p in [["ore", 3000, Vector2i(44, 46)], ["salvage", 2500, Vector2i(84, 44)], ["salvage", 2000, Vector2i(12, 44)]]:
		MapUtil.add_res(t, W, H, SPAWNS, resources, taken, String(p[0]), int(p[1]), p[2])
	var m := {
		"id": ID, "name": "River Dam", "size": "m", "w": W, "h": H, "terrain": t,
		"spawns": SPAWNS.duplicate(), "spawn_sets": SPAWN_SETS.duplicate(true), "max_sides": MAX_SIDES,
		"resources": resources, "bridges": [{"id": 0, "name": "West Bridge", "cells": b0}, {"id": 1, "name": "East Bridge", "cells": b1}],
		"hold_bridge": 0, "bridge_cells": b0.duplicate(), "dam_cells": dam_cells, "decor": [], "pois": pois,
		"seed": seed_value, "river_params": [a1, a2, f1, f2], "fair_tol": FAIR_TOL, "min_open_frac": MIN_OPEN,
		"wave_spawns": WAVE_SPAWNS.duplicate(), "survival": true,
	}
	_height(m)
	return m


## Authored height: the river valley is level 0 (6 cells either side of the water, every edge a ramp),
## banks plain (1), a level-2 bluff over the dam on each bank (ramps only on road tiles).
static func _height(m: Dictionary) -> void:
	var t: PackedByteArray = m.terrain
	var hg := MapUtil.new_layer(W, H, 1)
	MapUtil.basin(hg, t, W, H, 6, 0)
	MapUtil.hdisc(hg, W, H, SPAWNS[1], BLUFF_R, 2, MapUtil.HRAISE)
	m.height = hg
	m.ramps = MapUtil.derive_ramps(hg, t, W, H, [1, 0, 0])
	MapUtil.connect_ramps(m, true)


## True when the banks connect for foot only through the dam / bridge cells (the river is a barrier).
static func barrier_ok(m: Dictionary) -> bool:
	var mw := int(m.w)
	var mh := int(m.h)
	var pm := MapCheck.passmask(m.terrain, "foot")
	for c in m.get("dam_cells", []):
		pm[(c as Vector2i).y * mw + (c as Vector2i).x] = 0
	for b in m.get("bridges", []):
		for c in b.cells:
			pm[(c as Vector2i).y * mw + (c as Vector2i).x] = 0
	var lay := MapCheck.layers(m)
	var p0: Vector2i = (m.spawns[0] as Vector2i) + Vector2i(0, 3)
	var reach := MapCheck.bfs(pm, mw, mh, p0.y * mw + p0.x, lay[0], lay[1])
	var p1: Vector2i = (m.spawns[1] as Vector2i) + Vector2i(0, 3)
	if reach[p1.y * mw + p1.x] != MapCheck.UNREACHED:
		return false
	for cv in m.get("wave_spawns", []):
		if reach[(cv as Vector2i).y * mw + (cv as Vector2i).x] != MapCheck.UNREACHED:
			return false
	return true


static func validate(m: Dictionary) -> String:
	if not m.has("terrain"):
		return "Map not generated."
	var base := MapCheck.validate(m)
	if base != "":
		return base
	if (m.get("dam_cells", []) as Array).is_empty():
		return "River Dam has no dam across the river."
	if (m.get("bridges", []) as Array).size() < 2:
		return "River Dam needs 2 bridges."
	if not barrier_ok(m):
		return "River Dam: the river must only be crossable at the dam and the bridges."
	var ln := RidgeBastion.lanes(m)
	if ln != 4:
		return "River Dam needs 4 reachable attack lanes (found %d)." % ln
	if Elevation.map_level(m, SPAWNS[0]) != 2:
		return "Defender start %s is not on the bluff." % [SPAWNS[0]]
	return ""
