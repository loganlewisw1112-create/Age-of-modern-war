extends RefCounted
## Height brushes (owner: ED6, CONTRACTS_G6 section 7, PLAN_G6 section 8). Pure functions over the
## editor's map dict (MapIO shape): map.height = PackedByteArray of levels 0..3 (0 valley, 1 plain,
## 2 hill, 3 ridge), map.ramps = PackedByteArray of 0/1 ramp flags (a ramp joins two 4-neighbours whose
## levels differ by exactly 1; any other level change is a cliff). Every brush has the editor brush
## signature fn(map, cells, params) -> Array (changed cells) so editor_doc.apply runs it inside a stroke
## (symmetric copies + one undo step). Validation: issues(map) -> MapGen.validate_height issues.

const MapUtil = preload("res://sim/maps/map_util.gd")
const MapGen = preload("res://sim/map_gen.gd")

const PLAIN := 1
const MAX_LEVEL := 3
const TOOLS := ["raise", "lower", "smooth", "ramp", "level"]
const LEVEL_NAMES := ["Valley", "Plain", "Hill", "Ridge"]
const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Adds plain height + empty ramps layers when the map has none (first height edit).
static func ensure(map: Dictionary) -> void:
	var n := int(map.w) * int(map.h)
	if not map.has("height") or (map.height as PackedByteArray).size() != n:
		var hg := PackedByteArray()
		hg.resize(n)
		hg.fill(PLAIN)
		map["height"] = hg
	if not map.has("ramps") or (map.ramps as PackedByteArray).size() != n:
		var rp := PackedByteArray()
		rp.resize(n)
		rp.fill(0)
		map["ramps"] = rp


static func level_at(map: Dictionary, c: Vector2i) -> int:
	if not map.has("height"):
		return PLAIN
	return int((map.height as PackedByteArray)[c.y * int(map.w) + c.x])


static func _inside(map: Dictionary, c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < int(map.w) and c.y < int(map.h)


static func _set_levels(map: Dictionary, cells: Array, fn: Callable) -> Array:
	ensure(map)
	var w := int(map.w)
	var hg: PackedByteArray = map.height
	var out: Array = []
	var seen := {}
	for c in cells:
		var cc: Vector2i = c
		if not _inside(map, cc) or seen.has(cc):
			continue
		seen[cc] = true
		var i := cc.y * w + cc.x
		var nv := clampi(int(fn.call(cc, int(hg[i]))), 0, MAX_LEVEL)
		if nv != int(hg[i]):
			hg[i] = nv
			out.append(cc)
	map.height = hg
	if not out.is_empty():
		_prune(map, out)
	return out


## Drops ramp flags that no longer join a 1-level step (around the changed cells).
static func _prune(map: Dictionary, cells: Array) -> void:
	var rp: PackedByteArray = map.ramps
	MapUtil.prune_ramps(map.height, rp, int(map.w), int(map.h))
	map.ramps = rp


## +1 level (max 3).
static func raise(map: Dictionary, cells: Array, _p: Dictionary = {}) -> Array:
	return _set_levels(map, cells, func(_c: Vector2i, v: int) -> int: return v + 1)


## -1 level (min 0).
static func lower(map: Dictionary, cells: Array, _p: Dictionary = {}) -> Array:
	return _set_levels(map, cells, func(_c: Vector2i, v: int) -> int: return v - 1)


## Sets params.level (0..3).
static func set_level(map: Dictionary, cells: Array, p: Dictionary = {}) -> Array:
	var lv := clampi(int(p.get("level", PLAIN)), 0, MAX_LEVEL)
	return _set_levels(map, cells, func(_c: Vector2i, _v: int) -> int: return lv)


## Each cell takes the rounded mean of its 3x3 neighbourhood (read from the levels before the stroke
## step, so the result does not depend on cell order).
static func smooth(map: Dictionary, cells: Array, _p: Dictionary = {}) -> Array:
	ensure(map)
	var w := int(map.w)
	var src: PackedByteArray = (map.height as PackedByteArray).duplicate()
	return _set_levels(map, cells, func(c: Vector2i, v: int) -> int:
		var sum := 0
		var n := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := c + Vector2i(dx, dy)
				if _inside(map, q):
					sum += int(src[q.y * w + q.x])
					n += 1
		return roundi(float(sum) / float(maxi(1, n))) if n > 0 else v)


## Flags a ramp on cells next to a 1-level step (params.erase = true clears flags). Cells with no
## such step are left alone (a ramp across 2+ levels is not allowed: that stays a cliff).
static func ramp(map: Dictionary, cells: Array, p: Dictionary = {}) -> Array:
	ensure(map)
	var w := int(map.w)
	var hg: PackedByteArray = map.height
	var rp: PackedByteArray = map.ramps
	var erase := bool(p.get("erase", false))
	var out: Array = []
	for c in cells:
		var cc: Vector2i = c
		if not _inside(map, cc):
			continue
		var i := cc.y * w + cc.x
		var want := 0
		if not erase:
			for d in N4:
				var q: Vector2i = cc + d
				if _inside(map, q) and absi(int(hg[q.y * w + q.x]) - int(hg[i])) == 1:
					want = 1
		if int(rp[i]) != want and (want == 1 or erase):
			rp[i] = want
			out.append(cc)
	map.ramps = rp
	return out


## Runs tool name ("raise" | "lower" | "smooth" | "ramp" | "level") on cells.
static func apply_tool(map: Dictionary, cells: Array, p: Dictionary) -> Array:
	match String(p.get("tool", "raise")):
		"lower":
			return lower(map, cells, p)
		"smooth":
			return smooth(map, cells, p)
		"ramp":
			return ramp(map, cells, p)
		"level":
			return set_level(map, cells, p)
	return raise(map, cells, p)


## Height validation issues for a map dict with spawns (editor map_for_save()):
## [{code, msg, cell?}] with codes height_invalid, spawn_not_flat, spawn_unreachable, resource_unreachable.
static func issues(map: Dictionary) -> Array:
	if not map.has("height"):
		return []
	return MapGen.validate_height(map)


## Auto ramps (ELEV map_util): joins every start and resource through ramps; returns ramps added.
static func auto_ramps(map: Dictionary, symmetric: bool = false) -> int:
	if not map.has("height"):
		return 0
	return MapUtil.connect_ramps(map, symmetric)
