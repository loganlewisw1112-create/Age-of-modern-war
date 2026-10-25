extends RefCounted
## Coastal Front (coastal_front_m, 192x192), owner NAVAL (CONTRACTS_G5 section 8, PLAN_G5 section 4).
## A mainland between two seas (west sea / east sea), each sea with an island tied to the coast by a
## SHALLOW sandbar, beaches broken by seeded cliff stretches, and an estuary river that crosses the
## mainland from sea to sea with SHALLOW fords (passable on foot / by vehicle, and by naval_small:
## small boats can run the estuary between the seas; deep-draft `naval` ships stay at sea).
## 4 spawns in mirror pairs, every one on a coast (land- and sea-reachable).
## Point-symmetric: (x, y) <-> (191-x, 191-y); the west half is painted and MapUtil.sset mirrors it.
## Seeded: coastline shape, cliff stretches, island position, estuary meander, forest/dirt/ridges.
## validate(): MapCheck.validate (symmetry, footprints, foot/vehicle reach, open ground, fairness)
## plus the coastal checks (both seas joined for naval_small, each spawn near reachable water,
## >= 2 islands, beaches near every spawn, deep-water room for `naval`, SHALLOW fords).

const MapUtil = preload("res://sim/maps/map_util.gd")
const MapCheck = preload("res://sim/maps/map_check.gd")

const ID := "coastal_front_m"
const W := 192
const H := 192
## 0 W-north / 1 E-south, 2 W-south / 3 E-north (coastal), 4 centre-north / 5 centre-south (estuary
## banks). Pairs (2k, 2k+1) are mirrors. Grid paths are 4-connected, so any 3 corners of the coastal
## rectangle are a right triangle with mean-path skew ~1.5; the 3-side set uses the near-equilateral
## north triangle 0 / 3 / 4 instead (MapCheck fairness, tol 1.3).
const SPAWNS := [Vector2i(66, 34), Vector2i(125, 157), Vector2i(66, 150), Vector2i(125, 41), Vector2i(100, 70), Vector2i(91, 121)]
const SPAWN_SETS := {"2": [0, 1], "3": [0, 3, 4], "4": [0, 1, 2, 3]}
const COASTAL_SPAWNS := 4
const MAX_SIDES := 4
const COAST_X := 44.0          # mean west coastline x
const FORDS_X := [[68, 71], [94, 97]]   # west ford (mirrored to 120..123) and the centre ford
const RIVER_Y := 95.5
const BASE := [[6, -2, "salvage", 2000], [7, 3, "salvage", 2000], [-5, 4, "salvage", 2000],
	[4, 7, "ore", 3000], [3, -6, "ore", 3000]]
const FAIR_TOL := 1.3
const MIN_OPEN := 0.40
const MAX_ATTEMPTS := 12


static func generate(seed_value: int) -> Dictionary:
	var m := {}
	for attempt in MAX_ATTEMPTS:
		m = try_gen(seed_value, attempt)
		var why := validate(m)
		if why == "":
			m.gen_attempt = attempt
			return m
		m.last_validation_error = why
	return m


static func try_gen(seed_value: int, attempt: int) -> Dictionary:
	var rng := SimRng.new(seed_value * 7919 + attempt * 104723 + 59)
	var t := PackedByteArray()
	t.resize(W * H)
	t.fill(Terrain.GRASS)
	# --- west coastline (seeded) and cliff stretches (never near spawns, the estuary or the sandbar)
	var a1 := rng.randf_range(3.0, 6.0)
	var a2 := rng.randf_range(1.0, 2.5)
	var f1 := rng.randf_range(0.025, 0.045)
	var f2 := rng.randf_range(0.08, 0.12)
	var ph := rng.randf_range(0.0, TAU)
	var coast := PackedFloat32Array()
	coast.resize(H)
	for y in H:
		coast[y] = COAST_X + a1 * sin(float(y) * f1 + ph) + a2 * sin(float(y) * f2)
	var isle := Vector2i(18, 128 + rng.randi_range(-6, 6))
	var isle_r := rng.randf_range(7.0, 8.5)
	var cliff := PackedByteArray()
	cliff.resize(H)
	cliff.fill(0)
	for k in H / 12:
		var y0 := k * 12
		var yc := y0 + 6
		var near := absf(float(yc) - RIVER_Y) < 16.0 or absi(yc - isle.y) < 12
		for s in [SPAWNS[0], SPAWNS[2]]:
			var sv: Vector2i = s
			if absi(yc - sv.y) < 20:
				near = true
		if not near and rng.chance(0.45):
			for y in range(y0, y0 + 12):
				cliff[y] = 1
	for y in H:
		var cx: float = coast[y]
		for x in range(0, mini(int(cx) + 4, W / 2)):
			var dd := cx - float(x)
			var code := Terrain.GRASS
			if dd > 0.0:
				if dd > 11.0:
					code = Terrain.DEEP
				elif dd > 2.0 or cliff[y] != 0:
					code = Terrain.WATER
				else:
					code = Terrain.SHALLOW
			elif cliff[y] != 0:
				code = Terrain.CLIFF if dd > -1.6 else Terrain.GRASS
			else:
				code = Terrain.BEACH if dd > -2.6 else Terrain.GRASS
			MapUtil.sset(t, W, H, Vector2i(x, y), code)
	# --- island + sandbar to the coast (west sea; mirrored into the east sea)
	var ri := int(ceil(isle_r + 2.0))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var c := isle + Vector2i(dx, dy)
			if not MapUtil.inb(c, W, H):
				continue
			var d := Vector2(dx, dy).length()
			if d <= isle_r - 2.0:
				MapUtil.sset(t, W, H, c, Terrain.GRASS)
			elif d <= isle_r:
				MapUtil.sset(t, W, H, c, Terrain.BEACH)
			elif d <= isle_r + 1.5 and t[c.y * W + c.x] != Terrain.GRASS:
				MapUtil.sset(t, W, H, c, Terrain.SHALLOW)
	for y in range(isle.y - 1, isle.y + 2):
		for x in range(isle.x + int(isle_r), int(coast[y]) + 1):
			if Terrain.is_water(t[y * W + x]):
				MapUtil.sset(t, W, H, Vector2i(x, y), Terrain.SHALLOW)
	# --- roads (mainland interior; they reach the river at the fords)
	var none := []
	MapUtil.road(t, W, H, [SPAWNS[0] + Vector2i(0, 4), Vector2i(70, 58), Vector2i(70, 132), SPAWNS[2] + Vector2i(0, -4)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(70, 60), Vector2i(121, 60)], 1, -1, none)
	MapUtil.road(t, W, H, [Vector2i(95, 18), Vector2i(95, 173)], 1, -1, none)
	# --- estuary: meandering river from the west mouth to the centre (mirrored to the east mouth)
	var am := rng.randf_range(4.0, 8.0)
	var km := rng.randf_range(0.035, 0.06)
	var mouth: float = coast[96]
	var ford_cells := []
	var river_cells := 0
	for x in range(int(mouth) - 4, W / 2):
		var yc := RIVER_Y + am * sin((float(x) - 95.5) * km)
		var hw := 1.6 + 3.5 * clampf(1.0 - (float(x) - mouth) / 26.0, 0.0, 1.0)
		var ford := false
		for f in FORDS_X:
			if x >= int(f[0]) and x <= int(f[1]):
				ford = true
		for y in range(int(floor(yc - hw)) - 1, int(ceil(yc + hw)) + 2):
			if absf(float(y) + 0.5 - yc) > hw or not MapUtil.inb(Vector2i(x, y), W, H):
				continue
			var cur := t[y * W + x]
			if Terrain.is_water(cur) and not ford:
				continue
			MapUtil.sset(t, W, H, Vector2i(x, y), Terrain.SHALLOW if ford else Terrain.WATER)
			river_cells += 1
			if ford:
				var c := Vector2i(x, y)
				if not ford_cells.has(c):
					ford_cells.append(c)
					var mc := MapUtil.mirror(c, W, H)
					if not ford_cells.has(mc):
						ford_cells.append(mc)
	return _finish(t, rng, seed_value, ford_cells, isle, isle_r, mouth, [a1, a2, f1, f2, ph, am, km])


static func _finish(t: PackedByteArray, rng: SimRng, seed_value: int, ford_cells: Array, isle: Vector2i, isle_r: float, mouth: float, params: Array) -> Dictionary:
	MapUtil.base_pads(t, W, H, SPAWNS, 4.5)
	var margin := ford_cells.duplicate()
	var prot := MapUtil.protect_mask(t, W, H, SPAWNS, 11.0, margin, 3)
	for k in 22:
		MapUtil.blob(t, prot, W, H, rng, Vector2i(rng.randi_range(56, 136), rng.randi_range(6, 88)), rng.randf_range(1.5, 3.5), Terrain.DIRT)
	for k in 26:
		MapUtil.blob(t, prot, W, H, rng, Vector2i(rng.randi_range(56, 136), rng.randi_range(6, 88)), rng.randf_range(2.0, 4.5), Terrain.FOREST)
	for k in 7:
		var p := Vector2(rng.randi_range(60, 132), rng.randi_range(10, 84))
		MapUtil.ridge_line(t, prot, W, H, rng, p, rng.randf_range(0.0, TAU), rng.randi_range(4, 8), 0.4)
	# --- resources: identical base packages (mirror pairs), contested mainland piles, island piles
	var resources := []
	var taken := {}
	for si in [0, 2, 4]:
		var s: Vector2i = SPAWNS[si]
		var sy := 1 if s.y <= H / 2 else -1
		for b in BASE:
			MapUtil.add_res(t, W, H, SPAWNS, resources, taken, String(b[2]), int(b[3]), s + Vector2i(int(b[0]), int(b[1]) * sy))
	for p in [["ore", 3000, Vector2i(84, 74)], ["salvage", 2500, Vector2i(120, 80)], ["ore", 2500, Vector2i(82, 112)]]:
		var c: Vector2i = p[2] + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
		MapUtil.add_res(t, W, H, SPAWNS, resources, taken, String(p[0]), int(p[1]), c)
	MapUtil.add_res(t, W, H, SPAWNS, resources, taken, "ore", 4000, isle + Vector2i(-1, -1))
	MapUtil.add_res(t, W, H, SPAWNS, resources, taken, "salvage", 3000, isle + Vector2i(2, 2))
	var isle2 := MapUtil.mirror(isle, W, H)
	var mouth_c := Vector2i(int(mouth), 96)
	var pois := [
		{"type": "island", "name": "West Isle", "cell": isle}, {"type": "island", "name": "East Isle", "cell": isle2},
		{"type": "estuary", "name": "Estuary Mouth", "cell": mouth_c}, {"type": "estuary", "name": "Estuary Mouth", "cell": MapUtil.mirror(mouth_c, W, H)},
		{"type": "ford", "name": "Centre Ford", "cell": Vector2i(95, 95)},
		{"type": "ford", "name": "West Ford", "cell": Vector2i(69, 96)}, {"type": "ford", "name": "East Ford", "cell": Vector2i(122, 95)},
		{"type": "beach", "name": "North Beach", "cell": Vector2i(int(COAST_X), 34)}, {"type": "beach", "name": "South Beach", "cell": Vector2i(191 - int(COAST_X), 157)},
	]
	var m := {
		"id": ID, "name": "Coastal Front", "size": "m", "w": W, "h": H,
		"terrain": t, "spawns": SPAWNS.duplicate(), "spawn_sets": SPAWN_SETS.duplicate(true),
		"max_sides": MAX_SIDES, "resources": resources,
		"bridges": [], "hold_bridge": 0, "bridge_cells": [], "ford_cells": ford_cells,
		"decor": [], "pois": pois, "seed": seed_value, "coast_params": params,
		"islands": [isle, isle2], "island_r": isle_r,
		"fair_tol": FAIR_TOL, "min_open_frac": MIN_OPEN,
	}
	_height(m)
	return m


# ================================================================ validation
## Mask of cells passable for move class mc (Terrain.passable; naval also needs the >= 3 channel).
static func class_mask(t: PackedByteArray, mc: String) -> PackedByteArray:
	var pm := MapCheck.passmask(t, mc)
	if mc == "naval":
		var ch := Terrain.naval_channel_mask(t, W, H)
		for i in pm.size():
			if pm[i] != 0 and t[i] == Terrain.WATER and ch[i] == 0:
				pm[i] = 0
	return pm


## Index of the first reached cell (dist >= 0) within r tiles of c, or -1.
static func _near_reached(dist: PackedInt32Array, c: Vector2i, r: int) -> int:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := c + Vector2i(dx, dy)
			if MapUtil.inb(q, W, H) and dist[q.y * W + q.x] >= 0:
				return q.y * W + q.x
	return -1


## Per spawn: {land: vehicle-reachable from spawn 0, sea: a cell within 24 tiles is in the
## naval_small water body that joins both seas}.
static func reach_report(m: Dictionary) -> Array:
	var t: PackedByteArray = m.terrain
	var s0: Vector2i = SPAWNS[0]
	var veh := MapCheck.bfs(MapCheck.passmask(t, "vehicle"), W, H, (s0.y + 3) * W + s0.x)
	var sea := MapCheck.bfs(class_mask(t, "naval_small"), W, H, 96 * W + 1)
	var out := []
	for s in m.spawns:
		var sv: Vector2i = s
		var p := sv + Vector2i(0, 3)
		out.append({"spawn": sv, "land": veh[p.y * W + p.x] >= 0, "sea": _near_reached(sea, sv, 24) >= 0})
	return out


## Sizes of the dry-land components (not water, SHALLOW or CLIFF) that hold no spawn: the islands.
static func island_sizes(t: PackedByteArray) -> Array:
	var dry := PackedByteArray()
	dry.resize(W * H)
	for i in t.size():
		dry[i] = 0 if (Terrain.is_water(t[i]) or t[i] == Terrain.CLIFF) else 1
	var seen := PackedByteArray()
	seen.resize(W * H)
	seen.fill(0)
	for s in SPAWNS:
		var d := MapCheck.bfs(dry, W, H, s.y * W + s.x)
		for i in d.size():
			if d[i] >= 0:
				seen[i] = 1
	var out := []
	for i in t.size():
		if dry[i] == 0 or seen[i] != 0:
			continue
		var d := MapCheck.bfs(dry, W, H, i)
		var n := 0
		for j in d.size():
			if d[j] >= 0:
				seen[j] = 1
				n += 1
		out.append(n)
	return out


static func validate(m: Dictionary) -> String:
	var why := MapCheck.validate(m)
	if why != "":
		return why
	var t: PackedByteArray = m.terrain
	var sea := MapCheck.bfs(class_mask(t, "naval_small"), W, H, 96 * W + 1)
	if sea[95 * W + (W - 2)] < 0:
		return "The estuary does not join the two seas for small boats."
	for r in reach_report(m):
		if not bool(r.land) and not bool(r.sea):
			return "Spawn %s is reachable neither by land nor by sea." % [r.spawn]
		if not bool(r.sea):
			return "Spawn %s has no sea access within 24 tiles." % [r.spawn]
	var big := 0
	for n in island_sizes(t):
		if int(n) >= 40:
			big += 1
	if big < 2:
		return "Expected 2 islands, found %d." % big
	var beach := 0
	for i in t.size():
		if t[i] == Terrain.BEACH:
			beach += 1
	if beach < 300:
		return "Only %d beach cells." % beach
	for si in COASTAL_SPAWNS:
		var s: Vector2i = m.spawns[si]
		var ok := false
		for dy in range(-26, 27):
			for dx in range(-26, 27):
				var q: Vector2i = s + Vector2i(dx, dy)
				if MapUtil.inb(q, W, H) and t[q.y * W + q.x] == Terrain.BEACH:
					ok = true
		if not ok:
			return "Spawn %s has no beach within 26 tiles." % [s]
	var naval := class_mask(t, "naval")
	var nn := 0
	for i in naval.size():
		nn += naval[i]
	if nn < 3000:
		return "Only %d deep-water cells for naval ships." % nn
	if (m.ford_cells as Array).is_empty():
		return "The estuary has no fords."
	for c in m.ford_cells:
		if t[c.y * W + c.x] != Terrain.SHALLOW:
			return "Ford cell %s is not SHALLOW." % [c]
	m["beach_cells"] = beach
	m["naval_cells"] = nn
	m["island_count"] = big
	return ""


# ================================================================ G6 height (owner ELEV, CONTRACTS_G6 section 7.5)
## Authored height: two mainland uplands per half (level 2, every edge a ramp) with ridge caps (level 3,
## ramps every third edge cell + connect_ramps), mirrored. Seas, estuary, beaches and fords stay plain
## (level 1), so landings and the small-boat channel are unchanged. Spawn sites are flat. No rng draw.
static func _height(m: Dictionary) -> void:
	var t: PackedByteArray = m.terrain
	var hg := MapUtil.new_layer(W, H, 1)
	MapUtil.hdisc(hg, W, H, Vector2i(88, 40), 7.0, 2, MapUtil.HRAISE)
	MapUtil.hdisc(hg, W, H, Vector2i(88, 40), 3.0, 3, MapUtil.HRAISE)
	MapUtil.hdisc(hg, W, H, Vector2i(70, 70), 6.0, 2, MapUtil.HRAISE)
	MapUtil.hdisc(hg, W, H, Vector2i(71, 69), 2.5, 3, MapUtil.HRAISE)
	for i in hg.size():
		var c := int(t[i])
		if Terrain.is_water(c) or c == Terrain.BEACH:
			hg[i] = 1
	for s in SPAWNS:
		MapUtil.hflat(hg, W, H, s, 9.0)
	m.height = hg
	m.ramps = MapUtil.derive_ramps(hg, t, W, H, [3, 1, 3])
	MapUtil.connect_ramps(m, true)
