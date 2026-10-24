extends RefCounted
## Editor water brushes (owner: ED1): river, lake/ocean fill with depth falloff + beach ring,
## bridge validation/placement. Pure functions on the map dict, see brushes.gd.

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
const BRIDGE_MAX := 16   # longest bridge span (water cells)
const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func _water(code: int) -> bool:
	return code == WATER or code == SHALLOW or code == DEEP or code == FORD


static func _in(map: Dictionary, c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < int(map.w) and c.y < int(map.h)


static func _put(map: Dictionary, c: Vector2i, code: int, changed: Dictionary) -> void:
	var i: int = c.y * int(map.w) + c.x
	if int(map.terrain[i]) != code:
		map.terrain[i] = code
		changed[c] = true


static func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## River along a polyline of clicked cells.
## params: width 1..9 (core WATER), shallow_edges (bool: a 1-cell SHALLOW bank each side),
##         ford_every (int, 0 = none: a FORD crossing every N cells along the river).
## Bridges already on the path are kept. Returns changed cells.
static func river(map: Dictionary, points: Array, params: Dictionary) -> Array:
	var width := clampi(int(params.get("width", 3)), 1, 9)
	var shallow := bool(params.get("shallow_edges", true))
	var ford_every := maxi(0, int(params.get("ford_every", 0)))
	var r := width * 0.5
	var rr := r + (1.0 if shallow else 0.0)
	var changed := {}
	if points.is_empty():
		return []
	var pts: Array = points.duplicate()
	if pts.size() == 1:
		pts.append(pts[0])
	var core := {}
	var bank := {}
	for k in pts.size() - 1:
		var a := Vector2(pts[k]) + Vector2(0.5, 0.5)
		var b := Vector2(pts[k + 1]) + Vector2(0.5, 0.5)
		var x0 := int(floor(minf(a.x, b.x) - rr - 1))
		var x1 := int(ceil(maxf(a.x, b.x) + rr + 1))
		var y0 := int(floor(minf(a.y, b.y) - rr - 1))
		var y1 := int(ceil(maxf(a.y, b.y) + rr + 1))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var c := Vector2i(x, y)
				if not _in(map, c):
					continue
				var d := _dist_seg(Vector2(x, y) + Vector2(0.5, 0.5), a, b)
				if d <= r:
					core[c] = true
				elif d <= rr:
					bank[c] = true
	for c in bank:
		if core.has(c):
			continue
		var old := int(map.terrain[c.y * int(map.w) + c.x])
		if old == BRIDGE or _water(old):
			continue
		_put(map, c, SHALLOW, changed)
	for c in core:
		if int(map.terrain[c.y * int(map.w) + c.x]) == BRIDGE:
			continue
		_put(map, c, WATER, changed)
	if ford_every > 0:
		var acc := 0.0
		var next := float(ford_every)
		for k in pts.size() - 1:
			var a2 := Vector2(pts[k]) + Vector2(0.5, 0.5)
			var b2 := Vector2(pts[k + 1]) + Vector2(0.5, 0.5)
			var seg := a2.distance_to(b2)
			while acc + seg >= next and seg > 0.0:
				var p := a2.lerp(b2, (next - acc) / seg)
				for c in core.keys() + bank.keys():
					if Vector2(c).distance_to(p - Vector2(0.5, 0.5)) <= rr + 0.5 and int(map.terrain[c.y * int(map.w) + c.x]) != BRIDGE:
						_put(map, c, FORD, changed)
				next += float(ford_every)
			acc += seg
	return changed.keys()


## Organic lake footprint: a circle of `radius` whose edge wobbles by a seeded angular noise.
static func lake_cells(c: Vector2i, radius: int, s: int, w: int, h: int) -> Array:
	radius = clampi(radius, 1, 64)
	var rng := RandomNumberGenerator.new()
	rng.seed = s * 7919 + 13
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var out: Array = []
	var lim := int(ceil(radius * 1.3)) + 1
	for dy in range(-lim, lim + 1):
		for dx in range(-lim, lim + 1):
			var p := Vector2i(c.x + dx, c.y + dy)
			if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
				continue
			var ang := atan2(float(dy), float(dx))
			var wob := 1.0 + 0.14 * sin(ang * 2.0 + ph[0]) + 0.09 * sin(ang * 3.0 + ph[1]) + 0.05 * sin(ang * 5.0 + ph[2])
			if Vector2(dx, dy).length() <= radius * wob:
				out.append(p)
	return out


## Connected (4-neighbour) region of cells with the same terrain code as c ("ocean fill").
## Returns [] when the region exceeds max_cells.
static func flood_region(map: Dictionary, c: Vector2i, max_cells: int = 40000) -> Array:
	if not _in(map, c):
		return []
	var w := int(map.w)
	var code := int(map.terrain[c.y * w + c.x])
	var seen := {c: true}
	var q: Array = [c]
	var head := 0
	while head < q.size():
		var p: Vector2i = q[head]
		head += 1
		for d in N4:
			var n: Vector2i = p + d
			if _in(map, n) and not seen.has(n) and int(map.terrain[n.y * w + n.x]) == code:
				seen[n] = true
				q.append(n)
				if q.size() > max_cells:
					return []
	return q


## Turns `cells` into a body of water: SHALLOW within `falloff` cells of the shore, DEEP beyond,
## plus a BEACH ring `beach` cells wide on the surrounding land (grass/dirt/forest/hill/road
## only). The map edge counts as open water, so ocean fills stay deep at the border.
## params: falloff (1..8, default 2), beach (0..3, default 1).
static func water_body(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	var falloff := clampi(int(params.get("falloff", 2)), 1, 8)
	var beach := clampi(int(params.get("beach", 1)), 0, 3)
	var w := int(map.w)
	var inside := {}
	for c in cells:
		if _in(map, c) and int(map.terrain[c.y * w + c.x]) != BRIDGE:
			inside[c] = true
	var dist := {}
	var q: Array = []
	for c in inside:
		for d in N4:
			var n: Vector2i = c + d
			if _in(map, n) and not inside.has(n) and not _water(int(map.terrain[n.y * w + n.x])):
				dist[c] = 0
				q.append(c)
				break
	var head := 0
	while head < q.size():
		var p: Vector2i = q[head]
		head += 1
		for d in N4:
			var n: Vector2i = p + d
			if inside.has(n) and not dist.has(n):
				dist[n] = int(dist[p]) + 1
				q.append(n)
	var changed := {}
	for c in inside:
		var dd: int = dist.get(c, 1 << 20)
		_put(map, c, DEEP if dd >= falloff else SHALLOW, changed)
	if beach > 0:
		var ring := {}
		var frontier: Array = inside.keys()
		for _step in beach:
			var nxt: Array = []
			for p in frontier:
				for d in N4:
					var n: Vector2i = p + d
					if _in(map, n) and not inside.has(n) and not ring.has(n):
						var code := int(map.terrain[n.y * w + n.x])
						if code == GRASS or code == DIRT or code == FOREST or code == HILL or code == ROAD:
							ring[n] = true
							nxt.append(n)
			frontier = nxt
		for c in ring:
			_put(map, c, BEACH, changed)
	return changed.keys()


## Validates a bridge from land cell a to land cell b (straight: orthogonal or 45 degrees).
## Returns {ok, cells (the water cells the span covers), error}.
static func bridge_check(map: Dictionary, a: Vector2i, b: Vector2i) -> Dictionary:
	var bad := {"ok": false, "cells": [], "error": ""}
	if not _in(map, a) or not _in(map, b):
		bad.error = "Bridge ends must be on the map."
		return bad
	var d := b - a
	if d == Vector2i.ZERO or not (d.x == 0 or d.y == 0 or absi(d.x) == absi(d.y)):
		bad.error = "Bridges must be straight (along a row, a column or a 45-degree diagonal)."
		return bad
	var step := Vector2i(signi(d.x), signi(d.y))
	var w := int(map.w)
	for e in [a, b]:
		var ec := int(map.terrain[e.y * w + e.x])
		if _water(ec) or ec == BRIDGE or ec == CLIFF or ec == RIDGE or ec == BUILDING:
			bad.error = "Both bridge ends must be on open land."
			return bad
	var cells: Array = []
	var p := a + step
	while p != b:
		var code := int(map.terrain[p.y * w + p.x])
		if code == BRIDGE:
			bad.error = "The span crosses an existing bridge."
			return bad
		if not _water(code):
			bad.error = "Every cell between the ends must be water (land at %d,%d)." % [p.x, p.y]
			return bad
		cells.append(p)
		p += step
	if cells.is_empty():
		bad.error = "The span crosses no water."
		return bad
	if cells.size() > BRIDGE_MAX:
		bad.error = "The span is too long (%d cells, max %d)." % [cells.size(), BRIDGE_MAX]
		return bad
	return {"ok": true, "cells": cells, "error": ""}


## Writes BRIDGE over the span cells and appends {id, name, cells} to map.bridges.
## params: name (optional). Returns changed cells.
static func bridge_place(map: Dictionary, cells: Array, params: Dictionary) -> Array:
	if cells.is_empty():
		return []
	if not map.has("bridges"):
		map["bridges"] = []
	var list: Array = map.bridges
	var nid := 0
	for br in list:
		nid = maxi(nid, int(br.get("id", 0)) + 1)
	var changed := {}
	var typed: Array = []
	for c in cells:
		_put(map, c, BRIDGE, changed)
		typed.append(Vector2i(c))
	list.append({"id": nid, "name": String(params.get("name", "Bridge %d" % (nid + 1))), "cells": typed})
	return changed.keys()
