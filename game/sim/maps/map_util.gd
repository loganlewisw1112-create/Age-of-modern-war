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
const MapCheck = preload("res://sim/maps/map_check.gd")   # G6 (ELEV): height-aware BFS
const Elevation = preload("res://sim/systems/elevation.gd")


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


# ================================================================ G6 height (owner ELEV, CONTRACTS_G6 section 7)
## Height layer = PackedByteArray beside terrain: 0 valley, 1 plain, 2 hill, 3 ridge. Ramps = 0/1 bytes.
## Every painter below writes a cell AND its mirror, so a symmetric map stays symmetric. Painting
## modes: HSET overwrites, HRAISE keeps max(level, current), HLOWER keeps min(level, current).
const HSET := 0
const HRAISE := 1
const HLOWER := 2
## Terrain codes whose level-boundary cells always become ramps (roads keep running over height).
const PATH_CODES := [Terrain.ROAD, Terrain.BRIDGE, Terrain.FORD, Terrain.DIRT, Terrain.BEACH, 14]


static func new_layer(w: int, h: int, v: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(w * h)
	p.fill(v)
	return p


static func _hput(hg: PackedByteArray, i: int, level: int, mode: int) -> void:
	var cur := int(hg[i])
	if mode == HRAISE:
		level = maxi(level, cur)
	elif mode == HLOWER:
		level = mini(level, cur)
	hg[i] = level


## Sets cell c (and its mirror) to level under mode.
static func hset(hg: PackedByteArray, w: int, h: int, c: Vector2i, level: int, mode: int = HSET) -> void:
	if not inb(c, w, h):
		return
	_hput(hg, c.y * w + c.x, level, mode)
	_hput(hg, (h - 1 - c.y) * w + (w - 1 - c.x), level, mode)


## Disc of radius r around c (mirrored).
static func hdisc(hg: PackedByteArray, w: int, h: int, c: Vector2i, r: float, level: int, mode: int = HSET) -> void:
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if Vector2(dx, dy).length() <= r:
				hset(hg, w, h, c + Vector2i(dx, dy), level, mode)


## Polyline band of radius r (mirrored).
static func hband(hg: PackedByteArray, w: int, h: int, pts: Array, r: float, level: int, mode: int = HSET) -> void:
	for k in range(pts.size() - 1):
		var a: Vector2i = pts[k]
		var b: Vector2i = pts[k + 1]
		var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
		for s in n + 1:
			var p := Vector2(a).lerp(Vector2(b), float(s) / float(maxi(n, 1)))
			hdisc(hg, w, h, Vector2i(roundi(p.x), roundi(p.y)), r, level, mode)


## Inclusive rectangle (mirrored).
static func hrect(hg: PackedByteArray, w: int, h: int, x0: int, y0: int, x1: int, y1: int, level: int, mode: int = HSET) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			hset(hg, w, h, Vector2i(x, y), level, mode)


## Deterministic cell hash in [0, 2^20).
static func cell_hash(x: int, y: int) -> int:
	return posmod(x * 92821 + y * 68917 + ((x * 31 + 7) * (y * 17 + 3)) % 1009, 1 << 20)


## Symmetric ramp derivation. A cell is a ramp when it has a 4-neighbour exactly one level different
## AND (its terrain is a PATH_CODES tile, or cell_hash % every_by_low[lower level of that pair] == 0).
## every_by_low[k] = 1 makes every k<->k+1 boundary cell a ramp (gentle slope); 0 = only path tiles.
## The hash is taken on the canonical cell min(i, n-1-i), so point-symmetric maps get symmetric ramps
## and any other map gets a plain per-cell decision.
static func derive_ramps(hg: PackedByteArray, t: PackedByteArray, w: int, h: int, every_by_low: Array) -> PackedByteArray:
	var n := w * h
	var rp := new_layer(w, h, 0)
	for i in n:
		var rep := mini(i, n - 1 - i)
		var x := i % w
		var y := i / w
		var lv := int(hg[i])
		var path := PATH_CODES.has(int(t[i]))
		var on := false
		for d in DIRS:
			var q: Vector2i = Vector2i(x, y) + d
			if not inb(q, w, h):
				continue
			var ql := int(hg[q.y * w + q.x])
			if absi(ql - lv) != 1:
				continue
			var every := int(every_by_low[mini(ql, lv)]) if mini(ql, lv) < every_by_low.size() else 0
			if path or (every > 0 and cell_hash(rep % w, rep / w) % every == 0):
				on = true
				break
		if on:
			rp[i] = 1
	return rp


## Clears ramp flags that sit on no exact-one-level boundary (validity after edits).
static func prune_ramps(hg: PackedByteArray, rp: PackedByteArray, w: int, h: int) -> int:
	var cleared := 0
	for i in rp.size():
		if rp[i] == 0:
			continue
		var x := i % w
		var y := i / w
		var ok := false
		for d in DIRS:
			var q: Vector2i = Vector2i(x, y) + d
			if inb(q, w, h) and absi(int(hg[q.y * w + q.x]) - int(hg[i])) == 1:
				ok = true
		if not ok:
			rp[i] = 0
			cleared += 1
	return cleared


## Flattens a disc to the level found at its centre (base sites: buildings never straddle levels).
static func hflat(hg: PackedByteArray, w: int, h: int, c: Vector2i, r: float) -> void:
	if inb(c, w, h):
		hdisc(hg, w, h, c, r, int(hg[c.y * w + c.x]), HSET)


## Ramp placement: every foot-walkable region the height splits off from spawn 0's region gets a ramp
## on its lowest-index cell that touches the reached region across a one-level step (symmetric: the
## mirror cell too). Up to 6 rounds (a joined region can open the way to the next). Returns ramps added.
static func connect_ramps(m: Dictionary, symmetric: bool = false) -> int:
	if not m.has("height") or (m.get("spawns", []) as Array).is_empty():
		return 0
	var w := int(m.w)
	var h := int(m.h)
	var n := w * h
	var hg: PackedByteArray = m.height
	var rp: PackedByteArray = m.get("ramps", new_layer(w, h, 0))
	var pm := MapCheck.passmask(m.terrain, "foot")
	var p0 := probe_cell(pm, w, h, m.spawns[0])
	if p0.x < 0:
		return 0
	var added := 0
	for round in 6:
		var reach := MapCheck.bfs_h(pm, w, h, p0.y * w + p0.x, hg, rp)
		var mark := PackedByteArray()   # 1 = cell of a region already joined this round
		mark.resize(n)
		mark.fill(0)
		var changed := false
		for j in n:
			if pm[j] == 0 or reach[j] >= 0 or mark[j] != 0:
				continue
			var x := j % w
			var touch := false
			for k in [j + 1 if x + 1 < w else -1, j - 1 if x > 0 else -1, j + w if j + w < n else -1, j - w]:
				if k >= 0 and pm[k] != 0 and reach[k] >= 0 and absi(int(hg[k]) - int(hg[j])) == 1:
					touch = true
					break
			if not touch:
				continue
			rp[j] = 1
			added += 1
			if symmetric:
				rp[n - 1 - j] = 1
			changed = true
			_flood_mark(pm, hg, rp, w, h, j, mark)
		if not changed:
			break
	m.ramps = rp
	return added


## Marks (mark[i] = 1) the walkable cells height-connected to start (queue-bounded, no full-map scan).
static func _flood_mark(pm: PackedByteArray, hg: PackedByteArray, rp: PackedByteArray, w: int, h: int, start: int, mark: PackedByteArray) -> void:
	var n := w * h
	var q := PackedInt32Array([start])
	mark[start] = 1
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % w
		for j in [i + 1 if x + 1 < w else -1, i - 1 if x > 0 else -1, i + w if i + w < n else -1, i - w]:
			if j >= 0 and mark[j] == 0 and pm[j] != 0 and Elevation.edge_ok_raw(hg, rp, i, j):
				mark[j] = 1
				q.append(j)


## Nearest walkable cell to c (spawn + (0, 3) first, then rings up to 4), or (-1, -1).
static func probe_cell(pm: PackedByteArray, w: int, h: int, c: Vector2i) -> Vector2i:
	var p := c + Vector2i(0, 3)
	if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and pm[p.y * w + p.x] != 0:
		return p
	for d in 5:
		for dy in range(-d, d + 1):
			for dx in range(-d, d + 1):
				if maxi(absi(dx), absi(dy)) != d:
					continue
				var q := c + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and pm[q.y * w + q.x] != 0:
					return q
	return Vector2i(-1, -1)


## Valley floor: every cell within r (8-connected steps) of river water (WATER, FORD, SHALLOW, DEEP,
## or a BRIDGE span) is lowered to `level` (HLOWER). Symmetric terrain gives a symmetric basin.
static func basin(hg: PackedByteArray, t: PackedByteArray, w: int, h: int, r: int, level: int) -> void:
	var n := w * h
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var q := PackedInt32Array()
	for i in n:
		var c := int(t[i])
		if Terrain.is_water(c) or c == Terrain.FORD or c == Terrain.BRIDGE:
			dist[i] = 0
			q.append(i)
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var d := dist[i]
		_hput(hg, i, level, HLOWER)
		if d >= r:
			continue
		var x := i % w
		var y := i / w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var xx := x + dx
				var yy := y + dy
				if xx < 0 or yy < 0 or xx >= w or yy >= h:
					continue
				var j := yy * w + xx
				if dist[j] < 0:
					dist[j] = d + 1
					q.append(j)
