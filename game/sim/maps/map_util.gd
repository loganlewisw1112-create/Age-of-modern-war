extends RefCounted
## Shared helpers for the G3b map generators (owner: MAP4, docs/CONTRACTS_G3b.md section 4).
## No class_name: use `const MapUtil = preload("res://sim/maps/map_util.gd")`.
##
## Every G3b map is point-symmetric about its centre: cell index i <-> N-1-i, i.e.
## (x, y) <-> (W-1-x, H-1-y). Spawns come in mirror pairs (2k, 2k+1), so a 2-side match on a
## mirror pair is exactly fair, and the validator only needs BFS from the even spawns.
## Terrain is a PackedByteArray passed by reference (never stored in a Dictionary while painting:
## a Dictionary read hands back a copy-on-write value).

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func mirror(c: Vector2i, w: int, h: int) -> Vector2i:
	return Vector2i(w - 1 - c.x, h - 1 - c.y)


static func inb(c: Vector2i, w: int, h: int) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


## Sets a cell and its mirror.
static func sset(t: PackedByteArray, w: int, h: int, c: Vector2i, code: int) -> void:
	if not inb(c, w, h):
		return
	t[c.y * w + c.x] = code
	t[(h - 1 - c.y) * w + (w - 1 - c.x)] = code


## Sets a cell and its mirror unless the cell is protected (prot[i] != 0) or not plain ground.
static func sset_free(t: PackedByteArray, prot: PackedByteArray, w: int, h: int, c: Vector2i, code: int) -> void:
	if c.x < 1 or c.y < 1 or c.x >= w - 1 or c.y >= h - 1:
		return
	var i := c.y * w + c.x
	if prot[i] != 0:
		return
	var cur := t[i]
	if cur != Terrain.GRASS and cur != Terrain.DIRT and cur != Terrain.FOREST:
		return
	t[i] = code
	t[t.size() - 1 - i] = code


## Inclusive rectangle, symmetric.
static func rect(t: PackedByteArray, w: int, h: int, x0: int, y0: int, x1: int, y1: int, code: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			sset(t, w, h, Vector2i(x, y), code)


## Thick road polyline (axis-aligned or diagonal steps), symmetric. Water cells it crosses become
## `water_code` (BRIDGE for a bridge, ROAD for a dam/causeway, or -1 = leave the water alone) and
## are appended to `crossed`.
static func road(t: PackedByteArray, w: int, h: int, pts: Array, half: int, water_code: int, crossed: Array) -> void:
	for k in range(pts.size() - 1):
		var a: Vector2i = pts[k]
		var b: Vector2i = pts[k + 1]
		var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
		for s in n + 1:
			var p := Vector2(a).lerp(Vector2(b), float(s) / float(maxi(n, 1)))
			var c := Vector2i(roundi(p.x), roundi(p.y))
			for dy in range(-half, half + 1):
				for dx in range(-half, half + 1):
					var q := c + Vector2i(dx, dy)
					if not inb(q, w, h):
						continue
					var code := t[q.y * w + q.x]
					if code == Terrain.WATER or code == Terrain.BRIDGE:
						if water_code >= 0:
							if code == Terrain.WATER and not crossed.has(q):
								crossed.append(q)
							sset(t, w, h, q, water_code)
					elif code != Terrain.FORD:
						sset(t, w, h, q, Terrain.ROAD)


## Protection mask: 1 where seeded features may not paint (authored geography + margins).
static func protect_mask(t: PackedByteArray, w: int, h: int, spawns: Array, spawn_r: float, margin_cells: Array, margin: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(w * h)
	p.fill(0)
	for i in t.size():
		var code := t[i]
		if code != Terrain.GRASS and code != Terrain.DIRT:
			p[i] = 1
	for s in spawns:
		var r := int(ceil(spawn_r))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c: Vector2i = s + Vector2i(dx, dy)
				if inb(c, w, h) and Vector2(dx, dy).length() < spawn_r:
					p[c.y * w + c.x] = 1
	for mc in margin_cells:
		var cc: Vector2i = mc
		for dy in range(-margin, margin + 1):
			for dx in range(-margin, margin + 1):
				var c := cc + Vector2i(dx, dy)
				if inb(c, w, h):
					p[c.y * w + c.x] = 1
	return p


## Seeded blob of `code` (forest/dirt) of radius r around c, mirrored, respecting prot.
static func blob(t: PackedByteArray, prot: PackedByteArray, w: int, h: int, rng: SimRng, c: Vector2i, r: float, code: int) -> void:
	var ri := int(ceil(r)) + 1
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if Vector2(dx, dy).length() <= r + rng.randf_range(-0.8, 0.5):
				sset_free(t, prot, w, h, c + Vector2i(dx, dy), code)


## Seeded short ridge line from p, mirrored, respecting prot.
static func ridge_line(t: PackedByteArray, prot: PackedByteArray, w: int, h: int, rng: SimRng, p: Vector2, ang: float, length: int, thick: float) -> void:
	for s in length:
		var c := Vector2i(roundi(p.x + cos(ang) * s), roundi(p.y + sin(ang) * s))
		sset_free(t, prot, w, h, c, Terrain.RIDGE)
		if rng.chance(thick):
			sset_free(t, prot, w, h, c + Vector2i(1, 0), Terrain.RIDGE)


## Resource legality: plain ground, inside the margin, away from spawn centres and other piles.
static func res_ok(t: PackedByteArray, w: int, h: int, spawns: Array, taken: Dictionary, c: Vector2i) -> bool:
	if c.x < 2 or c.y < 2 or c.x >= w - 2 or c.y >= h - 2:
		return false
	var code := t[c.y * w + c.x]
	if code != Terrain.GRASS and code != Terrain.DIRT:
		return false
	for s in spawns:
		if c.distance_to(s) < 5.0:
			return false
	for o in taken:
		if c.distance_to(o) < 2.5:
			return false
	return true


## Adds a mirrored resource pair at the nearest legal cell to c (deterministic spiral, <= 4 cells).
## Returns false when nothing legal is near.
static func add_res(t: PackedByteArray, w: int, h: int, spawns: Array, resources: Array, taken: Dictionary, res: String, amount: int, c: Vector2i) -> bool:
	for r in 5:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := c + Vector2i(dx, dy)
				var mq := mirror(q, w, h)
				if q == mq or not res_ok(t, w, h, spawns, taken, q):
					continue
				for cc in [q, mq]:
					resources.append({"res": res, "amount": amount, "cell": cc})
					taken[cc] = true
					t[cc.y * w + cc.x] = Terrain.DIRT
				return true
	return false


## Dirt base pad around each spawn (buildable).
static func base_pads(t: PackedByteArray, w: int, h: int, spawns: Array, r: float) -> void:
	for s in spawns:
		var ri := int(ceil(r))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var c: Vector2i = s + Vector2i(dx, dy)
				if inb(c, w, h) and Vector2(dx, dy).length() <= r:
					var i := c.y * w + c.x
					if t[i] == Terrain.GRASS or t[i] == Terrain.FOREST or t[i] == Terrain.RIDGE:
						t[i] = Terrain.DIRT
