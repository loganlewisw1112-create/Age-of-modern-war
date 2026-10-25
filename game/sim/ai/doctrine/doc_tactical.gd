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
