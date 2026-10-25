extends RefCounted
## Editor brushes (owner: ED1, CONTRACTS_G4 section 9). Pure functions on the editable map dict:
##   brush(map, cells, params) -> changed_cells (Array of Vector2i)
## They mutate only `map` (terrain / biome / decor / resources / bridges) and use no global state
## or RNG: scatter is a seeded per-cell hash, so the same inputs always give the same map.
## Cell-set helpers (shape/line/rect/lake/flood) return the cells a tool should touch; symmetry is
## applied by the caller to those cells BEFORE the brush runs.
## Water tools live in brushes_water.gd, decor/resources in brushes_objects.gd (re-exported here).

const Water = preload("res://presentation/editor/brushes_water.gd")
const Objects = preload("res://presentation/editor/brushes_objects.gd")

const GRASS := 0
const DIRT := 1
const ROAD := 2
const FOREST := 3
const WATER := 4
const BRIDGE := 5
const FORD := 6
const RIDGE := 7
const BUILDING := 8
const SHALLOW := 9
const DEEP := 10
const BEACH := 11
const CLIFF := 12
const HILL := 13
const MAX_CODE := 14   # G6 (ED6): 14 = RAIL (Terrain.RAIL)
const WATER_CODES := [WATER, SHALLOW, DEEP, FORD]


## Deterministic per-cell hash in [0, 2^31).
static func hash_cell(x: int, y: int, s: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


## Percent roll in [0, 100) for scatter brushes.
static func roll(c: Vector2i, s: int) -> int:
	return hash_cell(c.x, c.y, s) % 100


static func in_map(map: Dictionary, c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < int(map.w) and c.y < int(map.h)


static func code_at(map: Dictionary, c: Vector2i) -> int:
	return int(map.terrain[c.y * int(map.w) + c.x])


static func is_water(code: int) -> bool:
	return code == WATER or code == SHALLOW or code == DEEP or code == FORD


## Ensures map.biome exists (same size as terrain, 0 = temperate) and returns nothing.
static func ensure_biome(map: Dictionary) -> void:
	var n := int(map.w) * int(map.h)
	if not map.has("biome") or (map.biome as PackedByteArray).size() != n:
		var b := PackedByteArray()
		b.resize(n)
		b.fill(int(map.get("base_biome", 0)))
		map["biome"] = b


# ------------------------------------------------------------------ cell sets
## Brush footprint: shape "circle" or "square", size = diameter 1..15, centred on c.
static func shape_cells(c: Vector2i, size: int, shape: String, w: int, h: int) -> Array:
	var out: Array = []
	size = clampi(size, 1, 15)
	var lo := -(size - 1) / 2
	var hi := lo + size - 1
	var r := size * 0.5
	for dy in range(lo, hi + 1):
		for dx in range(lo, hi + 1):
			if shape == "circle" and size > 2:
				var fx := dx + (0.5 if size % 2 == 0 else 0.0)
				var fy := dy + (0.5 if size % 2 == 0 else 0.0)
				if fx * fx + fy * fy > r * r:
					continue
			var p := Vector2i(c.x + dx, c.y + dy)
			if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h:
				out.append(p)
	return out


## Bresenham line from a to b (inclusive).
static func line_cells(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		out.append(p)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return out


## A line stamped with the brush footprint (line tool).
static func thick_line(a: Vector2i, b: Vector2i, size: int, shape: String, w: int, h: int) -> Array:
	var seen := {}
	var out: Array = []
	for p in line_cells(a, b):
		for q in shape_cells(p, size, shape, w, h):
			if not seen.has(q):
				seen[q] = true
				out.append(q)
	return out


## Rectangle a..b (any corner order); filled or 1-cell outline.
static func rect_cells(a: Vector2i, b: Vector2i, filled: bool, w: int, h: int) -> Array:
	var out: Array = []
	var x0 := clampi(mini(a.x, b.x), 0, w - 1)
	var x1 := clampi(maxi(a.x, b.x), 0, w - 1)
	var y0 := clampi(mini(a.y, b.y), 0, h - 1)
	var y1 := clampi(maxi(a.y, b.y), 0, h - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if filled or x == x0 or x == x1 or y == y0 or y == y1:
				out.append(Vector2i(x, y))
	return out


# ------------------------------------------------------------------ paint
## Terrain / biome paint.
## params: code (int), strength (1..100, % of cells painted; 100 = fill), seed (int),
##         layer ("terrain" default | "biome"), only_on (optional Array of codes it may replace).
static func paint(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	var code := int(params.get("code", GRASS))
	var strength := clampi(int(params.get("strength", 100)), 1, 100)
	var s := int(params.get("seed", 0))
	var biome := String(params.get("layer", "terrain")) == "biome"
	var only_on: Array = params.get("only_on", [])
	if biome:
		ensure_biome(map)
		code = clampi(code, 0, 3)
	else:
		code = clampi(code, 0, MAX_CODE)
	var w := int(map.w)
	var changed: Array = []
	for c in cells:
		if not in_map(map, c):
			continue
		if strength < 100 and roll(c, s) >= strength:
			continue
		var i: int = c.y * w + c.x
		if biome:
			if int(map.biome[i]) != code:
				map.biome[i] = code
				changed.append(c)
		else:
			var old := int(map.terrain[i])
			if old == code or (not only_on.is_empty() and not only_on.has(old)):
				continue
			map.terrain[i] = code
			changed.append(c)
	return changed


## Fills a whole new map with one code (Map tab "New").
static func new_map(w: int, h: int, base_code: int, base_biome: int) -> Dictionary:
	var t := PackedByteArray()
	t.resize(w * h)
	t.fill(base_code)
	var b := PackedByteArray()
	b.resize(w * h)
	b.fill(base_biome)
	return {"w": w, "h": h, "terrain": t, "biome": b, "base_biome": base_biome,
		"decor": [], "resources": [], "bridges": [], "spawns": [], "start_packages": true}


# ------------------------------------------------------------------ re-exports
static func river(map: Dictionary, points: Array, params: Dictionary) -> Array:
	return Water.river(map, points, params)


static func water_body(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	return Water.water_body(map, cells, params)


static func lake_cells(c: Vector2i, radius: int, s: int, w: int, h: int) -> Array:
	return Water.lake_cells(c, radius, s, w, h)


static func flood_region(map: Dictionary, c: Vector2i, max_cells: int = 40000) -> Array:
	return Water.flood_region(map, c, max_cells)


static func bridge_check(map: Dictionary, a: Vector2i, b: Vector2i) -> Dictionary:
	return Water.bridge_check(map, a, b)


static func bridge_place(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	return Water.bridge_place(map, cells, params)


static func decor_place(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	return Objects.decor_place(map, cells, params)


static func decor_scatter(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	return Objects.decor_scatter(map, cells, params)


static func decor_erase(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	return Objects.decor_erase(map, cells, params)


static func resource_place(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	return Objects.resource_place(map, cells, params)


static func resource_scatter(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	return Objects.resource_scatter(map, cells, params)


static func resource_erase(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	return Objects.resource_erase(map, cells, params)
