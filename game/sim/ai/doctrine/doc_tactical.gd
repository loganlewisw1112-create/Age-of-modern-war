extends RefCounted
## Doctrine tactical layer (owner: AI7-DOC). CONTRACTS_G6 section 16: per platoon / element, height and
## cover seeking (Elevation + Fieldworks APIs), bounding overwatch geometry, flanks, garrisons and mine
## awareness. Pure functions of the map, own buildings and the mines this side knows (fair: Mines.known_to
## is the player-visible set). Ties break by scan order (y, then x), so every pick is deterministic.

const D = preload("res://sim/ai/doctrine/doc_util.gd")
const Elevation = preload("res://sim/systems/elevation.gd")
const Fieldworks = preload("res://sim/systems/fieldworks.gd")
const Mines = preload("res://sim/systems/mines.gd")
const Garrison = preload("res://sim/systems/garrison.gd")


static func cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


static func clamp_map(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 1.5, float(w.map.w) - 1.5), clampf(p.y, 1.5, float(w.map.h) - 1.5))


static func level(w: SimWorld, p: Vector2) -> int:
	return Elevation.height_at(w, cell(p)) if Elevation.has_height(w) else 1


static func walkable(w: SimWorld, c: Vector2i, mc: String = "foot") -> bool:
	if not w.in_bounds(c):
		return false
	return Terrain.passable(int(w.map.terrain[c.y * int(w.map.w) + c.x]), mc)


## Enemy mines this side has spotted: {Vector2i cell: true}.
static func known_mines(w: SimWorld, fid: int) -> Dictionary:
	var out := {}
	for mid in Mines.known_to(w, fid):
		var m = w.entities.get(int(mid))  # AI-FAIR: a mine this side can see (Mines.known_to)
		if m != null and int(m.owner) != fid:
			out[m.get("cell", cell(m.pos))] = true
	return out


static func mine_near(mines: Dictionary, c: Vector2i, r: int) -> bool:
	if mines.is_empty():
		return false
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if mines.has(c + Vector2i(dx, dy)):
				return true
	return false


## Known mine cells within `width` tiles of the segment a -> b (one sample per tile), ascending scan order.
static func mines_on_leg(mines: Dictionary, a: Vector2, b: Vector2, width: int) -> Array:
	var out := []
	if mines.is_empty():
		return out
	var n := maxi(int(ceil(a.distance_to(b))), 1)
	var seen := {}
	for i in n + 1:
		var c := cell(a.lerp(b, float(i) / float(n)))
		for dy in range(-width, width + 1):
			for dx in range(-width, width + 1):
				var q := c + Vector2i(dx, dy)
				if mines.has(q) and not seen.has(q):
					seen[q] = true
					out.append(q)
	return out


## Best firing position within radius of center: height first, then cover, LOS to `toward` (when it is not
## Vector2.INF), a short walk, and never next to a known mine. min_dist > 0 keeps the pick at least that far
## from `toward` (a base of fire / overwatch stays at stand-off instead of climbing into the objective).
static func best_position(w: SimWorld, center: Vector2, radius: float, toward: Vector2, mines: Dictionary,
		mc: String = "foot", min_dist: float = 0.0) -> Vector2:
	var r := int(ceil(radius))
	var c0 := cell(center)
	var has_h := Elevation.has_height(w)
	var sh := D.num("score_height")
	var sc := D.num("score_cover")
	var sl := D.num("score_los")
	var sd := D.num("score_dist")
	var sm := D.num("score_mine")
	var avoid := int(D.num("mine_avoid"))
	var best := center
	var bs := -INF
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var c := c0 + Vector2i(dx, dy)
			if not walkable(w, c, mc):
				continue
			var p := Vector2(c) + Vector2(0.5, 0.5)
			var s := -p.distance_to(center) * sd
			if min_dist > 0.0 and toward != Vector2.INF and p.distance_to(toward) < min_dist:
				s -= sm * 2.0
			if has_h:
				s += float(Elevation.height_at(w, c)) * sh
				if toward != Vector2.INF and Elevation.los(w, p, toward):
					s += sl
			var cov := Fieldworks.cover_at(w, c)
			if cov < 1.0:
				s += (1.0 - cov) * sc * 4.0
			if mine_near(mines, c, avoid):
				s -= sm
			if s > bs:
				bs = s
				best = p
	return best


## Key terrain: the highest walkable cell within radius of center (ties: closest to `from`). {pos, level}.
static func key_terrain(w: SimWorld, center: Vector2, radius: float, from: Vector2) -> Dictionary:
	if not Elevation.has_height(w):
		return {"pos": center, "level": 1}
	var r := int(ceil(radius))
	var c0 := cell(center)
	var best := center
	var bl := -1
	var bd := INF
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var c := c0 + Vector2i(dx, dy)
			if not walkable(w, c):
				continue
			var lv := Elevation.height_at(w, c)
			var p := Vector2(c) + Vector2(0.5, 0.5)
			var d := p.distance_to(from)
			if lv > bl or (lv == bl and d < bd):
				bl = lv
				bd = d
				best = p
	return {"pos": best, "level": bl}


## Flank point: the objective seen from `from`, swung `side` (+1 / -1) by flank_angle_deg, flank_dist out.
static func flank_point(w: SimWorld, obj: Vector2, from: Vector2, side: int) -> Vector2:
	var dir := (from - obj).normalized() if from.distance_to(obj) > 0.1 else Vector2.LEFT
	var p := obj + dir.rotated(deg_to_rad(D.num("flank_angle_deg")) * float(side)) * D.num("flank_dist")
	return clamp_map(w, p)


## The flank side (+1 / -1) with the better ground: higher, walkable, no known mines on the way.
static func flank_side(w: SimWorld, obj: Vector2, from: Vector2, mines: Dictionary) -> int:
	var best := 1
	var bs := -INF
	for side in [1, -1]:
		var p := flank_point(w, obj, from, side)
		var s := float(level(w, p)) * 2.0 - float(mines_on_leg(mines, from, p, 1).size()) * 3.0
		if not walkable(w, cell(p)):
			s -= 5.0
		if s > bs:
			bs = s
			best = side
	return best


## Point at distance `back` from b toward a (a phase line / the attack position before an objective).
static func short_of(a: Vector2, b: Vector2, back: float) -> Vector2:
	var d := a.distance_to(b)
	if d <= back:
		return a
	return b + (a - b) / d * back


## Phase lines from `a` to `b`, every phase_line_spacing tiles, b included.
static func phase_lines(w: SimWorld, a: Vector2, b: Vector2) -> Array:
	var sp := maxf(D.num("phase_line_spacing"), 2.0)
	var n := maxi(int(ceil(a.distance_to(b) / sp)), 1)
	var out := []
	for i in range(1, n + 1):
		out.append(clamp_map(w, a.lerp(b, float(i) / float(n))))
	return out


## Lateral slot for element i of n across the axis direction (line abreast, 4 tiles apart).
static func slot(p: Vector2, dir: Vector2, i: int, n: int) -> Vector2:
	var side := Vector2(-dir.y, dir.x)
	return p + side * (float(i) - float(n - 1) * 0.5) * 4.0


## Own building with free garrison slots within r of p, or null (infantry hold strongpoints).
static func garrison_pick(w: SimWorld, fid: int, buildings: Array, p: Vector2, r: float):
	var best = null
	var bd := INF
	for b in buildings:
		if int(b.owner) != fid or not bool(b.get("built", false)) or Garrison.slots_of(String(b.def)) <= 0:
			continue
		var q: Vector2 = b.pos
		var d := q.distance_to(p)
		if d <= r and d < bd and Garrison.free_slots(w, b) > 0:
			bd = d
			best = b
	return best


# ================================================================ G6.1 OFF61: movement across a battlefield
## Route from a to b on a coarse grid (route_cell tiles): A* whose cell cost adds known mines (never
## crossed when avoidable), open ground exposed to observed enemy fire (`threats`: [{pos, range}]) and
## rewards cover and height. Bounded to the a-b box + 16 tiles, so it stays cheap. Returns waypoints
## (cell centres, b last). [b] when a and b share a cell.
static func route(w: SimWorld, a: Vector2, b: Vector2, mines: Dictionary, threats: Array) -> Array:
	var rc := maxi(int(D.num("route_cell")), 2)
	var gw := int(ceil(float(w.map.w) / float(rc)))
	var gh := int(ceil(float(w.map.h) / float(rc)))
	var ca := Vector2i(clampi(floori(a.x / rc), 0, gw - 1), clampi(floori(a.y / rc), 0, gh - 1))
	var cb := Vector2i(clampi(floori(b.x / rc), 0, gw - 1), clampi(floori(b.y / rc), 0, gh - 1))
	if ca == cb:
		return [b]
	var pad := int(ceil(16.0 / float(rc)))
	var x0 := maxi(mini(ca.x, cb.x) - pad, 0)
	var y0 := maxi(mini(ca.y, cb.y) - pad, 0)
	var x1 := mini(maxi(ca.x, cb.x) + pad, gw - 1)
	var y1 := mini(maxi(ca.y, cb.y) + pad, gh - 1)
	var bw := x1 - x0 + 1
	var mined := {}
	for mc in mines:
		var q := Vector2i(floori(float(mc.x) / rc), floori(float(mc.y) / rc))
		mined[q] = true
		# a field near a cell edge also taints the neighbour it is within a tile of
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var edge: Vector2i = Vector2i(mc.x, mc.y) + d
			mined[Vector2i(floori(float(edge.x) / rc), floori(float(edge.y) / rc))] = true
	var cost_m := D.num("route_mine_cost")
	var cost_x := D.num("route_exposure_cost")
	var bon_c := D.num("route_cover_bonus")
	var bon_h := D.num("route_height_bonus")
	var has_h := Elevation.has_height(w)
	var g := {}
	var came := {}
	var heap := [[0.0, 0, ca]]
	var seq := 1
	g[ca] = 0.0
	var found := false
	while not heap.is_empty():
		var top: Array = _hpop(heap)
		var c: Vector2i = top[2]
		if c == cb:
			found = true
			break
		if float(top[0]) > float(g.get(c, INF)) + Vector2(c).distance_to(Vector2(cb)) * rc + 0.001:
			continue
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var n := c + Vector2i(dx, dy)
				if n.x < x0 or n.y < y0 or n.x > x1 or n.y > y1:
					continue
				var p := Vector2(n) * rc + Vector2(rc, rc) * 0.5
				p = clamp_map(w, p)
				if not walkable(w, cell(p)) and n != cb:
					continue
				var step := Vector2(dx, dy).length() * rc
				var k := step
				if mined.has(n):
					k += cost_m
				for t in threats:
					var tp: Vector2 = t.pos
					if tp.distance_to(p) <= float(t.get("range", 8.0)) + 1.0:
						var cov := Fieldworks.cover_at(w, cell(p))
						var open := 1.0 if cov >= 1.0 else 0.4
						if not has_h or Elevation.los(w, tp, p):
							k += cost_x * open
				if has_h:
					k -= float(Elevation.height_at(w, cell(p)) - 1) * bon_h
				if Fieldworks.cover_at(w, cell(p)) < 1.0:
					k -= bon_c
				var tcell := int(w.map.terrain[cell(p).y * int(w.map.w) + cell(p).x])
				if tcell == Terrain.FOREST:
					k -= bon_c
				k = maxf(k, step * 0.3)
				var ng := float(g[c]) + k
				if ng < float(g.get(n, INF)):
					g[n] = ng
					came[n] = c
					_hpush(heap, [ng + Vector2(n).distance_to(Vector2(cb)) * rc * 0.3, seq, n])
					seq += 1
	if not found:
		return [b]
	var cells := []
	var cur := cb
	while cur != ca:
		cells.push_front(cur)
		cur = came[cur]
	var out := []
	for i in cells.size() - 1:
		out.append(clamp_map(w, Vector2(cells[i]) * rc + Vector2(rc, rc) * 0.5))
	out.append(b)
	return out


static func _hless(x: Array, y: Array) -> bool:
	return float(x[0]) < float(y[0]) or (float(x[0]) == float(y[0]) and int(x[1]) < int(y[1]))


static func _hpush(h: Array, it: Array) -> void:
	h.append(it)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if not _hless(h[i], h[p]):
			break
		var t = h[i]
		h[i] = h[p]
		h[p] = t
		i = p


static func _hpop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	h[0] = last
	var i := 0
	var n := h.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and _hless(h[l], h[m]):
			m = l
		if r < n and _hless(h[r], h[m]):
			m = r
		if m == i:
			break
		var t = h[i]
		h[i] = h[m]
		h[m] = t
		i = m
	return top


## Phase lines along a route: every phase_line_spacing tiles of path length, b last.
static func route_lines(w: SimWorld, a: Vector2, b: Vector2, mines: Dictionary, threats: Array) -> Array:
	var pts := route(w, a, b, mines, threats)
	var sp := maxf(D.num("phase_line_spacing"), 2.0)
	var out := []
	var acc := 0.0
	var prev := a
	for i in pts.size():
		var p: Vector2 = pts[i]
		acc += prev.distance_to(p)
		prev = p
		# a mine-free leg needs its turning points: keep every waypoint next to a known field
		var bend := mine_near(mines, cell(p), int(D.num("route_cell")) + 1)
		if acc >= sp or i == pts.size() - 1 or bend:
			out.append(p)
			acc = 0.0
	return out


## Observed enemy fire threats from the visible list: [{pos, range}] (fair: visible enemies only).
static func threats_of(vis: Array) -> Array:
	var out := []
	for e in vis:
		if String(e.get("kind", "unit")) != "unit":
			continue
		var d: Dictionary = Content.unit(String(e.def))
		out.append({"pos": e.pos, "range": float(d.get("range", 6.0))})
	return out


# ================================================================ G6.1 OFF61: drill geometry
## Formation for ground at p heading dir: column on a road or in forest, file in a gap narrower than
## narrow_width, else `dflt`.
static func ground_formation(w: SimWorld, p: Vector2, dir: Vector2, dflt: String) -> String:
	var c := cell(p)
	if not w.in_bounds(c):
		return dflt
	var t := int(w.map.terrain[c.y * int(w.map.w) + c.x])
	var side := Vector2(-dir.y, dir.x)
	var wide := 0
	for k in range(-3, 4):
		if walkable(w, cell(p + side * float(k))):
			wide += 1
	if wide < int(D.num("narrow_width")):
		return "file"
	if t == Terrain.ROAD or t == Terrain.FOREST or t == Terrain.BRIDGE:
		return "column"
	return dflt


## Stack point for an assault on a strongpoint at bp approached from `from`: stack_dist short of it on
## the approach side, on covered walkable ground, never next to a known mine.
static func stack_point(w: SimWorld, bp: Vector2, from: Vector2, mines: Dictionary) -> Vector2:
	var p := short_of(from, bp, D.num("stack_dist") + 1.0)
	return best_position(w, p, 1.5, Vector2.INF, mines)


## Angle (degrees) between the axis from->obj and the approach p->obj (fix-and-flank geometry).
static func off_axis_deg(from: Vector2, obj: Vector2, p: Vector2) -> float:
	var a := (from - obj)
	var b := (p - obj)
	if a.length() < 0.01 or b.length() < 0.01:
		return 0.0
	return rad_to_deg(absf(a.angle_to(b)))


## Flank point at an explicit angle (L-shape = 90, pincer = both sides).
static func flank_at(w: SimWorld, obj: Vector2, from: Vector2, side: int, deg: float, dist: float) -> Vector2:
	var dir := (from - obj).normalized() if from.distance_to(obj) > 0.1 else Vector2.LEFT
	return clamp_map(w, obj + dir.rotated(deg_to_rad(deg) * float(side)) * dist)
