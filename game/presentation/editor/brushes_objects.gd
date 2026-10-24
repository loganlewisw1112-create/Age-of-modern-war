extends RefCounted
## Editor object brushes (owner: ED1): decor (nature, objects, POI) and resource piles.
## Pure functions on the map dict, see brushes.gd. map.decor entries are
## {id, cell: Vector2i (top-left), size: Vector2i}; map.resources entries {res, amount, cell}.

const Catalog = preload("res://presentation/editor/decor_catalog.gd")

const GRASS := 0
const DIRT := 1
const FOREST := 3
const BRIDGE := 5
const RIDGE := 7
const BUILDING := 8
const HILL := 13
const BEACH := 11
## Codes an object may stand on.
const LAND := [0, 1, 2, 11, 13]


static func _h(c: Vector2i, s: int) -> int:
	var h := (c.x * 73856093) ^ (c.y * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


static func _in(map: Dictionary, c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < int(map.w) and c.y < int(map.h)


static func _code(map: Dictionary, c: Vector2i) -> int:
	return int(map.terrain[c.y * int(map.w) + c.x])


static func _vec(v) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(v)
	return Vector2i(int(v[0]), int(v[1]))


static func entry_size(e: Dictionary) -> Vector2i:
	if e.has("size"):
		return _vec(e.size)
	return Catalog.size_of(String(e.get("id", "")))


## cell -> index into map.decor, for every footprint cell.
static func decor_occupancy(map: Dictionary) -> Dictionary:
	var occ := {}
	var list: Array = map.get("decor", [])
	for i in list.size():
		var e: Dictionary = list[i]
		var o := _vec(e.cell)
		var s := entry_size(e)
		for y in s.y:
			for x in s.x:
				occ[o + Vector2i(x, y)] = i
	return occ


static func resource_occupancy(map: Dictionary) -> Dictionary:
	var occ := {}
	var list: Array = map.get("resources", [])
	for i in list.size():
		occ[_vec(list[i].cell)] = i
	return occ


## Places decor `params.id` with each cell as the top-left origin. Trees paint FOREST.
## A footprint must be fully on open land (LAND codes) and free of decor and resources.
static func decor_place(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	var id := String(params.get("id", "bush"))
	var d := Catalog.get_def(id)
	if d.is_empty():
		return []
	if not map.has("decor"):
		map["decor"] = []
	var size := Catalog.size_of(id)
	if params.has("size"):
		size = _vec(params.size)
	var occ := decor_occupancy(map)
	var rocc := resource_occupancy(map)
	var w := int(map.w)
	var changed: Array = []
	for c0 in cells:
		var c: Vector2i = c0
		if bool(d.get("terrain_only", false)):
			if _in(map, c) and LAND.has(_code(map, c)) and _code(map, c) != 2 and not occ.has(c) and not rocc.has(c):
				map.terrain[c.y * w + c.x] = int(d.cell)
				changed.append(c)
			continue
		var fp: Array = []
		var ok := true
		for y in size.y:
			for x in size.x:
				var p := c + Vector2i(x, y)
				if not _in(map, p) or not LAND.has(_code(map, p)) or occ.has(p) or rocc.has(p):
					ok = false
					break
				fp.append(p)
			if not ok:
				break
		if not ok:
			continue
		var idx: int = (map.decor as Array).size()
		(map.decor as Array).append({"id": id, "cell": c, "size": size})
		for p in fp:
			occ[p] = idx
			if int(d.cell) >= 0:
				map.terrain[p.y * w + p.x] = int(d.cell)
			changed.append(p)
	return changed


## Scatter: each cell gets an object with probability density% (seeded hash); the object is
## picked from params.ids by a second hash (random variation, reproducible).
## params: ids (Array of decor ids), density 1..100, seed.
static func decor_scatter(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	var ids: Array = params.get("ids", [params.get("id", "bush")])
	if ids.is_empty():
		return []
	var density := clampi(int(params.get("density", 30)), 1, 100)
	var s := int(params.get("seed", 0))
	var changed: Array = []
	for c in cells:
		if _h(c, s) % 100 >= density:
			continue
		var id := String(ids[_h(c, s + 101) % ids.size()])
		changed.append_array(decor_place(map, [c], {"id": id}))
	return changed


## Removes every decor entry whose footprint touches `cells` (solid footprints go back to
## GRASS); with params.trees (default true) FOREST cells in `cells` also become GRASS.
static func decor_erase(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	var occ := decor_occupancy(map)
	var kill := {}
	var w := int(map.w)
	var changed: Array = []
	for c in cells:
		if occ.has(c):
			kill[int(occ[c])] = true
	if not kill.is_empty():
		var list: Array = map.decor
		var keep: Array = []
		for i in list.size():
			if not kill.has(i):
				keep.append(list[i])
				continue
			var e: Dictionary = list[i]
			var o := _vec(e.cell)
			var s := entry_size(e)
			for y in s.y:
				for x in s.x:
					var p := o + Vector2i(x, y)
					if _in(map, p):
						if _code(map, p) == BUILDING or _code(map, p) == RIDGE:
							map.terrain[p.y * w + p.x] = GRASS
						changed.append(p)
		map["decor"] = keep
	if bool(params.get("trees", true)):
		for c in cells:
			if _in(map, c) and _code(map, c) == FOREST:
				map.terrain[c.y * w + c.x] = GRASS
				changed.append(c)
	return changed


static func _res_ok(map: Dictionary, c: Vector2i, occ: Dictionary, rocc: Dictionary, gap: int) -> bool:
	if not _in(map, c) or not LAND.has(_code(map, c)) or occ.has(c):
		return false
	for dy in range(-gap, gap + 1):
		for dx in range(-gap, gap + 1):
			if rocc.has(c + Vector2i(dx, dy)):
				return false
	return true


## Whether a pile could go on c (open land, no decor, `gap` free cells to other piles).
static func can_place_resource(map: Dictionary, c: Vector2i, gap: int) -> bool:
	return _res_ok(map, c, decor_occupancy(map), resource_occupancy(map), gap)


## Single resource piles. params: res ("salvage" | "ore"), amount (int), gap (min free cells
## between piles, default 0 = only the same cell is refused).
static func resource_place(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	var res := String(params.get("res", "salvage"))
	var amount := clampi(int(params.get("amount", 1500)), 1, 1000000)
	var gap := maxi(0, int(params.get("gap", 0)))
	if not map.has("resources"):
		map["resources"] = []
	var occ := decor_occupancy(map)
	var rocc := resource_occupancy(map)
	var changed: Array = []
	for c0 in cells:
		var c: Vector2i = c0
		if not _res_ok(map, c, occ, rocc, gap):
			continue
		rocc[c] = (map.resources as Array).size()
		(map.resources as Array).append({"res": res, "amount": amount, "cell": c})
		changed.append(c)
	return changed


## Scatter piles: density% of cells (seeded), at least params.gap (default 2) cells apart.
static func resource_scatter(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	var density := clampi(int(params.get("density", 10)), 1, 100)
	var s := int(params.get("seed", 0))
	var pick: Array = []
	for c in cells:
		if _h(c, s + 7) % 100 < density:
			pick.append(c)
	var p2 := params.duplicate()
	p2["gap"] = int(params.get("gap", 2))
	return resource_place(map, pick, p2)


static func resource_erase(map: Dictionary, cells: Array, _params: Dictionary) -> Array:
	var kill_set := {}
	for c in cells:
		kill_set[c] = true
	var keep: Array = []
	var changed: Array = []
	for r in map.get("resources", []):
		var c := _vec(r.cell)
		if kill_set.has(c):
			changed.append(c)
		else:
			keep.append(r)
	map["resources"] = keep
	return changed
