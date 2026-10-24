extends RefCounted
## Generic map validator for the G3b maps (owner: MAP4). No class_name:
##   const MapCheck = preload("res://sim/maps/map_check.gd")
## River Crossing keeps its original validator in map_gen.gd (its re-roll decisions, and therefore
## its bytes, must not change). Checks, in order:
##  1. terrain is point-symmetric and spawns come in mirror pairs (2k, 2k+1);
##  2. every spawn has a buildable 5x5 footprint;
##  3. foot and vehicle: every spawn reachable from spawn 0, every resource has a reachable side;
##  4. every bridge / crossing cell list is non-empty and inside the map;
##  5. open ground: vehicle-reachable cells >= m.min_open_frac of the map (10k-unit capacity);
##  6. fairness: in every spawn_set, each side's mean vehicle path to its rivals is within
##     m.fair_tol (max/min) of the others' (base packages are identical by construction).

const UNREACHED := -1


static func passmask(t: PackedByteArray, mc: String) -> PackedByteArray:
	var lut := PackedByteArray()
	lut.resize(256)
	for code in 256:
		lut[code] = 1 if Terrain.passable(code, mc) else 0
	var p := PackedByteArray()
	p.resize(t.size())
	for i in t.size():
		p[i] = lut[t[i]]
	return p


## Breadth-first step distance from cell index `start` over a pm mask. -1 = unreachable.
static func bfs(pm: PackedByteArray, w: int, h: int, start: int) -> PackedInt32Array:
	var n := w * h
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(UNREACHED)
	if start < 0 or start >= n or pm[start] == 0:
		return dist
	var q := PackedInt32Array()
	q.resize(n)
	var head := 0
	var tail := 0
	q[tail] = start
	tail += 1
	dist[start] = 0
	while head < tail:
		var i := q[head]
		head += 1
		var d := dist[i] + 1
		var x := i % w
		if x + 1 < w and dist[i + 1] == UNREACHED and pm[i + 1] != 0:
			dist[i + 1] = d
			q[tail] = i + 1
			tail += 1
		if x > 0 and dist[i - 1] == UNREACHED and pm[i - 1] != 0:
			dist[i - 1] = d
			q[tail] = i - 1
			tail += 1
		if i + w < n and dist[i + w] == UNREACHED and pm[i + w] != 0:
			dist[i + w] = d
			q[tail] = i + w
			tail += 1
		if i - w >= 0 and dist[i - w] == UNREACHED and pm[i - w] != 0:
			dist[i - w] = d
			q[tail] = i - w
			tail += 1
	return dist


static func _probe(s: Vector2i) -> Vector2i:
	return s + Vector2i(0, 3)   # same probe cell as River Crossing's validator (south of the HQ)


static func validate(m: Dictionary) -> String:
	var t: PackedByteArray = m.terrain
	var w := int(m.w)
	var h := int(m.h)
	var n := w * h
	if t.size() != n:
		return "Terrain size %d != %dx%d." % [t.size(), w, h]
	for i in n / 2:
		if t[i] != t[n - 1 - i]:
			return "Terrain not point-symmetric at %s." % [Vector2i(i % w, i / w)]
	var spawns: Array = m.spawns
	if spawns.size() % 2 != 0:
		return "Spawn count must be even (mirror pairs)."
	for k in spawns.size() / 2:
		var a: Vector2i = spawns[2 * k]
		if spawns[2 * k + 1] != Vector2i(w - 1 - a.x, h - 1 - a.y):
			return "Spawns %d/%d are not a mirror pair." % [2 * k, 2 * k + 1]
	for s in spawns:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var c: Vector2i = s + Vector2i(dx, dy)
				if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h or not Terrain.buildable(t[c.y * w + c.x]):
					return "Spawn %s footprint not buildable at %s." % [s, c]
	for mc in ["foot", "vehicle"]:
		var pm := passmask(t, mc)
		var p0 := _probe(spawns[0])
		var reach := bfs(pm, w, h, p0.y * w + p0.x)
		for si in range(1, spawns.size()):
			var o := _probe(spawns[si])
			if reach[o.y * w + o.x] == UNREACHED:
				return "No %s route between spawns %s and %s." % [mc, spawns[0], spawns[si]]
		for r in m.resources:
			var ok := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var c: Vector2i = r.cell + d
				if c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and reach[c.y * w + c.x] != UNREACHED:
					ok = true
			if not ok:
				return "Resource %s at %s unreachable by %s." % [r.res, r.cell, mc]
		if mc == "vehicle":
			var open := 0
			for i in n:
				if reach[i] != UNREACHED:
					open += 1
			var frac := float(open) / float(n)
			if frac < float(m.get("min_open_frac", 0.0)):
				return "Only %.1f%% of the map is open vehicle ground (need %.1f%%)." % [frac * 100.0, float(m.min_open_frac) * 100.0]
			m["open_cells"] = open
	for b in m.get("bridges", []):
		if (b.cells as Array).is_empty():
			return "Bridge %s has no cells." % [b.get("id", "?")]
	return _fairness(m, {})


## Vehicle path steps between spawn centres a and b. Mirror symmetry means only even spawns need a
## BFS: d(2k+1 -> b) = d(2k -> mirror(b)), because spawn 2k+1 is exactly the mirror of spawn 2k.
static func _pair_dist(m: Dictionary, cache: Dictionary, a: int, b: int) -> int:
	var w := int(m.w)
	var h := int(m.h)
	var src := a - (a % 2)
	var target: Vector2i = m.spawns[b]
	if a % 2 == 1:
		target = Vector2i(w - 1 - target.x, h - 1 - target.y)
	if not cache.has(src):
		var s: Vector2i = m.spawns[src]
		cache[src] = bfs(passmask(m.terrain, "vehicle"), w, h, s.y * w + s.x)
	var dist: PackedInt32Array = cache[src]
	return dist[target.y * w + target.x]


## Fairness metric per spawn set: each side's MEAN vehicle path to its rivals in that set
## (for 2 sides this is simply the path between them). max/min must stay within m.fair_tol.
## The nearest-rival path is recorded too (m["near_<n>"]) so reports can show both: with one
## river splitting the map, a 3-side set always puts two sides on one bank (nearest-rival skew).
static func _fairness(m: Dictionary, cache: Dictionary) -> String:
	var tol := float(m.get("fair_tol", 0.0))
	var sets: Dictionary = m.get("spawn_sets", {})
	for key in sets:
		var ids: Array = sets[key]
		if ids.size() != int(key):
			return "spawn_sets[%s] has %d entries." % [key, ids.size()]
		var mean := []
		var near := []
		for a in ids:
			var best := 1 << 30
			var total := 0
			for b in ids:
				if a == b:
					continue
				var d := _pair_dist(m, cache, int(a), int(b))
				if d < 0:
					return "spawn_sets[%s]: spawns %d and %d not connected." % [key, a, b]
				best = mini(best, d)
				total += d
			near.append(best)
			mean.append(roundi(float(total) / float(ids.size() - 1)))
		if tol > 0.0:
			var lo: int = mean.min()
			var hi: int = mean.max()
			if float(hi) > tol * float(lo):
				return "spawn_sets[%s] unfair: mean rival path %d..%d steps (tol %.2f)." % [key, lo, hi, tol]
		m["fair_%s" % key] = mean
		m["near_%s" % key] = near
	return ""
