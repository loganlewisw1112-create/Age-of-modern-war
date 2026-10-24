extends RefCounted
## Editor symmetry (owner: ED1, CONTRACTS_G4 section 9). Every tool transforms its cells
## through here BEFORE the brush runs, so terrain, water, decor, resources, bridges (and ED2's
## units/buildings/start positions) all mirror the same way.
## Modes: off, mirror_x (left/right), mirror_y (top/bottom), mirror_diag (x<->y, square maps),
## rotate_180, four_way (mirror_x + mirror_y + rotate_180).

const MODES := ["off", "mirror_x", "mirror_y", "mirror_diag", "rotate_180", "four_way"]
const LABELS := ["Off", "Mirror X", "Mirror Y", "Mirror diagonal", "Rotate 180", "4-way"]


static func copy_count(mode: String) -> int:
	match mode:
		"mirror_x", "mirror_y", "mirror_diag", "rotate_180":
			return 2
		"four_way":
			return 4
	return 1


## Image k (0 = identity) of a cell.
static func transform(c: Vector2i, mode: String, k: int, w: int, h: int) -> Vector2i:
	if k == 0:
		return c
	match mode:
		"mirror_x":
			return Vector2i(w - 1 - c.x, c.y)
		"mirror_y":
			return Vector2i(c.x, h - 1 - c.y)
		"mirror_diag":
			return Vector2i(c.y, c.x)
		"rotate_180":
			return Vector2i(w - 1 - c.x, h - 1 - c.y)
		"four_way":
			if k == 1:
				return Vector2i(w - 1 - c.x, c.y)
			if k == 2:
				return Vector2i(c.x, h - 1 - c.y)
			return Vector2i(w - 1 - c.x, h - 1 - c.y)
	return c


## The images of one cell (the cell itself first), deduplicated, inside the map.
static func images(c: Vector2i, mode: String, w: int, h: int) -> Array:
	var out: Array = []
	for k in copy_count(mode):
		var p := transform(c, mode, k, w, h)
		if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and not out.has(p):
			out.append(p)
	return out


## All cells after symmetry, deduplicated, original cells first (stable order).
static func expand(cells: Array, mode: String, w: int, h: int) -> Array:
	var seen := {}
	var out: Array = []
	for c in cells:
		if not seen.has(c):
			seen[c] = true
			out.append(c)
	if copy_count(mode) == 1:
		return out
	for k in range(1, copy_count(mode)):
		for c in cells:
			var p := transform(c, mode, k, w, h)
			if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and not seen.has(p):
				seen[p] = true
				out.append(p)
	return out


## The cell groups per symmetry image: [[cells for image 0], [image 1], ...]. Tools that need
## coherent shapes per copy (river polylines, bridge spans) transform each copy separately.
static func copies(cells: Array, mode: String, w: int, h: int) -> Array:
	var out: Array = []
	for k in copy_count(mode):
		var arr: Array = []
		for c in cells:
			arr.append(transform(c, mode, k, w, h))
		if not out.has(arr):
			out.append(arr)
	return out


## Footprint placements [[origin, size], ...] for an object of `size` at top-left `origin`,
## deduplicated; the first entry is the input.
static func footprints(origin: Vector2i, size: Vector2i, mode: String, w: int, h: int) -> Array:
	var out: Array = []
	var seen := {}
	for k in copy_count(mode):
		var o := origin
		var s := size
		var mx := Vector2i(w - size.x - origin.x, origin.y)
		var my := Vector2i(origin.x, h - size.y - origin.y)
		var r := Vector2i(w - size.x - origin.x, h - size.y - origin.y)
		match mode:
			"mirror_x":
				if k == 1:
					o = mx
			"mirror_y":
				if k == 1:
					o = my
			"mirror_diag":
				if k == 1:
					o = Vector2i(origin.y, origin.x)
					s = Vector2i(size.y, size.x)
			"rotate_180":
				if k == 1:
					o = r
			"four_way":
				if k == 1:
					o = mx
				elif k == 2:
					o = my
				elif k == 3:
					o = r
		var key := Rect2i(o, s)
		if seen.has(key):
			continue
		seen[key] = true
		out.append([o, s])
	return out


## Whether a mode is usable on this map (diagonal mirroring needs a square map).
static func valid_for(mode: String, w: int, h: int) -> bool:
	return mode != "mirror_diag" or w == h
