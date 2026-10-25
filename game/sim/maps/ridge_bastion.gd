extends RefCounted
## Ridge Bastion (ridge_bastion_m, 128x128): survival stronghold (owner: MODES6, CONTRACTS_G6 section 15,
## PLAN_G6 D42 "walled ridge, 2 ramps, 4 attack lanes").
## Authored: a 32x32 ridge plateau at the centre (height 3) ringed by a crenellated rock wall and reached
## only through two gates, west and east: a road climbs a level-2 landing onto the ridge (ramps only on
## the road tiles; every other plateau edge is a cliff). Four attack lanes run from the four map edges
## to the gates (west + north lanes -> west gate, east + south lanes -> east gate); map.wave_spawns are
## the lane ends. Two rock outcrops split the lowland; two level-0 hollows have gentle slopes. Spawns 0/1
## sit on the ridge (defenders, co-op), 2/3 in the NW/SE corners (2 sides use [0, 3]: the wave attacker's
## start is stripped by survival). fair_tol is loose on purpose: a defence map, not a mirror duel.
## Seeded: forest clusters and dirt patches in the lowland (roads, ridge, landings, lanes protected).
## Point-symmetric: (x, y) <-> (127-x, 127-y). _height() draws no rng, so terrain bytes stay stable.

const MapUtil = preload("res://sim/maps/map_util.gd")
const MapCheck = preload("res://sim/maps/map_check.gd")
const Elevation = preload("res://sim/systems/elevation.gd")

const ID := "ridge_bastion_m"
const W := 128
const H := 128
const SPAWNS := [Vector2i(57, 57), Vector2i(70, 70), Vector2i(12, 12), Vector2i(115, 115)]
const SPAWN_SETS := {"2": [0, 3], "3": [0, 1, 3], "4": [0, 1, 2, 3]}
const MAX_SIDES := 4
const RIDGE_LO := 48              # plateau rect RIDGE_LO..RIDGE_HI on both axes (level 3)
const RIDGE_HI := 79
const LANDING := [40, 60, 47, 67] # west landing x0, y0, x1, y1 (level 2); mirrored east
const GATE_ROWS := [61, 66]       # wall gap rows at x = RIDGE_LO (mirrored at x = RIDGE_HI)
## Lane ends: west, north, east, south (the wave AI's entry points).
const WAVE_SPAWNS := [Vector2i(2, 63), Vector2i(58, 2), Vector2i(125, 64), Vector2i(69, 125)]
const BASE := [[6, -2, "salvage", 2000], [7, 3, "salvage", 2000], [-6, 3, "salvage", 2000],
	[4, 7, "ore", 3000], [-5, -3, "ore", 3000]]
const FAIR_TOL := 2.5
const MIN_OPEN := 0.6


static func try_gen(seed_value: int, attempt: int) -> Dictionary:
	var rng := SimRng.new(seed_value * 4409 + attempt * 104729 + 53)
	var t := PackedByteArray()
	t.resize(W * H)
	t.fill(Terrain.GRASS)
	# --- crenellated rim wall (3 rock, 2 open), open across the gate rows
	for k in range(RIDGE_LO, RIDGE_HI + 1):
		if (k - RIDGE_LO) % 5 >= 3:
			continue
		MapUtil.sset(t, W, H, Vector2i(k, RIDGE_LO), Terrain.RIDGE)
		if k < GATE_ROWS[0] or k > GATE_ROWS[1]:
			MapUtil.sset(t, W, H, Vector2i(RIDGE_LO, k), Terrain.RIDGE)
	# --- lanes: west lane -> west gate -> into the ridge; north lane joins it (mirrored: east, south)
	var none := []
	MapUtil.road(t, W, H, [Vector2i(0, 63), Vector2i(56, 63)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(58, 0), Vector2i(58, 28), Vector2i(30, 56), Vector2i(30, 63)], 1, -1, none)
	# --- rock outcrops between the lanes
	MapUtil.rect(t, W, H, 74, 12, 77, 34, Terrain.RIDGE)
	MapUtil.rect(t, W, H, 8, 80, 26, 83, Terrain.RIDGE)
	MapUtil.base_pads(t, W, H, SPAWNS, 4.5)
	var pois := [{"type": "bastion", "name": "The Bastion", "cell": Vector2i(63, 63)},
		{"type": "gate", "name": "West Gate", "cell": Vector2i(RIDGE_LO, 63)},
		{"type": "gate", "name": "East Gate", "cell": Vector2i(RIDGE_HI, 64)}]
	for i in WAVE_SPAWNS.size():
		pois.append({"type": "lane", "name": ["West Lane", "North Lane", "East Lane", "South Lane"][i], "cell": WAVE_SPAWNS[i]})
	# --- protection: ridge + landings + a margin, lane ends; then seeded lowland features
	var margin := []
	for y in range(RIDGE_LO - 4, RIDGE_HI + 5):
		for x in range(LANDING[0] - 3, W - LANDING[0] + 3):
			margin.append(Vector2i(x, y))
	for c in WAVE_SPAWNS:
		margin.append(c)
	var prot := MapUtil.protect_mask(t, W, H, SPAWNS, 10.0, margin, 2)
	for k in 10:
		MapUtil.blob(t, prot, W, H, rng, Vector2i(rng.randi_range(4, 123), rng.randi_range(4, 60)), rng.randf_range(1.5, 3.0), Terrain.DIRT)
	for k in 14:
		MapUtil.blob(t, prot, W, H, rng, Vector2i(rng.randi_range(4, 123), rng.randi_range(4, 60)), rng.randf_range(1.5, 3.2), Terrain.FOREST)
	# --- resources: base packages on the ridge and in the corners, contested lowland piles
	var resources := []
	var taken := {}
	for si in [0, 2]:
		var s: Vector2i = SPAWNS[si]
		var sx := 1 if s.x <= W / 2 else -1
		var sy := 1 if s.y <= H / 2 else -1
		for b in BASE:
			MapUtil.add_res(t, W, H, SPAWNS, resources, taken, String(b[2]), int(b[3]), s + Vector2i(int(b[0]) * sx, int(b[1]) * sy))
	for p in [["ore", 3000, Vector2i(30, 44)], ["salvage", 2500, Vector2i(90, 20)], ["salvage", 2000, Vector2i(40, 20)], ["ore", 2500, Vector2i(14, 50)]]:
		MapUtil.add_res(t, W, H, SPAWNS, resources, taken, String(p[0]), int(p[1]), p[2])
	var m := {
		"id": ID, "name": "Ridge Bastion", "size": "m", "w": W, "h": H, "terrain": t,
		"spawns": SPAWNS.duplicate(), "spawn_sets": SPAWN_SETS.duplicate(true), "max_sides": MAX_SIDES,
		"resources": resources, "bridges": [], "hold_bridge": 0, "bridge_cells": [], "decor": [], "pois": pois, "seed": seed_value,
		"fair_tol": FAIR_TOL, "min_open_frac": MIN_OPEN, "wave_spawns": WAVE_SPAWNS.duplicate(), "survival": true,
	}
	_height(m)
	m.bastion_ramps = gates(m, 3)
	m.lanes = lanes(m)
	return m


## Authored height: base plain (1), the ridge plateau (3), two level-2 landings, two level-0 hollows.
## Ramps: every 0<->1 boundary cell (hollows are gentle), only road tiles on 1<->2 and 2<->3 (the gates).
static func _height(m: Dictionary) -> void:
	var t: PackedByteArray = m.terrain
	var hg := MapUtil.new_layer(W, H, 1)
	MapUtil.hrect(hg, W, H, RIDGE_LO, RIDGE_LO, RIDGE_HI, RIDGE_HI, 3)
	MapUtil.hrect(hg, W, H, int(LANDING[0]), int(LANDING[1]), int(LANDING[2]), int(LANDING[3]), 2)
	MapUtil.hdisc(hg, W, H, Vector2i(100, 26), 5.0, 0)
	MapUtil.hdisc(hg, W, H, Vector2i(24, 36), 4.0, 0)
	m.height = hg
	m.ramps = MapUtil.derive_ramps(hg, t, W, H, [1, 0, 0])
	MapUtil.connect_ramps(m, true)


## Walkable exits off `level`: 4-connected groups of foot-passable cells at that level with a passable
## edge (height edge rule) to a lower foot-passable cell. Ridge Bastion has exactly 2 (the gates).
static func gates(m: Dictionary, level: int) -> int:
	var t: PackedByteArray = m.terrain
	var hg: PackedByteArray = m.get("height", PackedByteArray())
	var rp: PackedByteArray = m.get("ramps", PackedByteArray())
	var mw := int(m.w)
	var mh := int(m.h)
	if hg.size() != mw * mh:
		return 0
	var exits := {}
	for i in mw * mh:
		if hg[i] != level or not Terrain.passable(t[i], "foot"):
			continue
		for d in MapUtil.DIRS:
			var x: int = i % mw + d.x
			var y: int = i / mw + d.y
			if x < 0 or y < 0 or x >= mw or y >= mh:
				continue
			var j := y * mw + x
			if hg[j] < level and Terrain.passable(t[j], "foot") and Elevation.edge_ok_raw(hg, rp, i, j):
				exits[i] = true
	var keys := exits.keys()
	keys.sort()
	var seen := {}
	var groups := 0
	for k in keys:
		if seen.has(k):
			continue
		groups += 1
		seen[k] = true
		var stack := [k]
		while not stack.is_empty():
			var c: int = stack.pop_back()
			for d in MapUtil.DIRS:
				var x: int = c % mw + d.x
				var y: int = c / mw + d.y
				var j := y * mw + x
				if x >= 0 and y >= 0 and x < mw and y < mh and exits.has(j) and not seen.has(j):
					seen[j] = true
					stack.append(j)
	return groups


## map.wave_spawns that sit within 3 cells of the map edge and are vehicle-reachable (height edge rule)
## from spawn 0's probe cell.
static func lanes(m: Dictionary) -> int:
	var mw := int(m.w)
	var mh := int(m.h)
	var lay := MapCheck.layers(m)
	var p0: Vector2i = (m.spawns[0] as Vector2i) + Vector2i(0, 3)
	var reach := MapCheck.bfs(MapCheck.passmask(m.terrain, "vehicle"), mw, mh, p0.y * mw + p0.x, lay[0], lay[1])
	var n := 0
	for cv in m.get("wave_spawns", []):
		var c: Vector2i = cv
		var edge := mini(mini(c.x, c.y), mini(mw - 1 - c.x, mh - 1 - c.y)) <= 3
		if edge and c.x >= 0 and c.y >= 0 and c.x < mw and c.y < mh and reach[c.y * mw + c.x] != MapCheck.UNREACHED:
			n += 1
	return n


static func validate(m: Dictionary) -> String:
	if not m.has("terrain"):
		return "Map not generated."
	var base := MapCheck.validate(m)
	if base != "":
		return base
	var g := gates(m, 3)
	if g != 2:
		return "Ridge Bastion needs exactly 2 gates onto the ridge (found %d)." % g
	var ln := lanes(m)
	if ln != 4:
		return "Ridge Bastion needs 4 reachable attack lanes (found %d)." % ln
	for si in [0, 1]:
		if Elevation.map_level(m, SPAWNS[si]) != 3:
			return "Defender start %s is not on the ridge." % [SPAWNS[si]]
	return ""
