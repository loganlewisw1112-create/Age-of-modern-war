extends RefCounted
## Elevation (library, no tick) (owner: ELEV). CONTRACTS_G6 section 5.2 and section 7 (D23, D24).
## No class_name: const Elevation = preload("res://sim/systems/elevation.gd"). Never preload g6_hooks.gd (cycle).
##
## Data (saved and hashed with w.map):
##   w.map.height  PackedByteArray, one byte per cell (index y * w + x): 0 valley, 1 plain, 2 hill, 3 ridge.
##   w.map.ramps   PackedByteArray, 1 = ramp cell. Absent with height present = no ramps.
## ABSENT height = every cell plain and every function here neutral (1.0 / 0 / true), so maps and saves
## without height keep their G5 results byte-for-byte.
##
## Rules (numbers in content/g6/rules_elevation.json -> Content.rules().g6_elevation):
##   - Edge between two 4-adjacent cells: same level = open; levels differ by exactly 1 = open when either
##     cell is a ramp; anything else = cliff (closed for every Terrain.HEIGHT_CLASSES class). A diagonal
##     step is open only when all four orthogonal edges around it are open (no corner cutting).
##   - Per level of advantage: sight +sight_per_level, weapon range x range_mult_per_level, damage taken
##     from a lower attacker x defence_mult_per_level. Sight and the contract range hook measure the
##     advantage over plain ground (level 1, the hooks have no target); range_mult_vs / defence_mult
##     measure it against the actual target / attacker.
##   - LOS: blocked when any cell strictly between the two endpoint cells is higher than the higher
##     endpoint level (cells walked with an exact grid DDA, deterministic).
##   - Ramp cell: speed x ramp_speed_mult for ground classes (up or down: the ramp cell is the slope).
##   - Air units (def is_air) ignore height entirely; indirect fire ignores LOS but keeps the range bonus.

const PLAIN := 1
const MAX_LEVEL := 3
const DEFAULTS := {"sight_per_level": 2.0, "range_mult_per_level": 1.10, "defence_mult_per_level": 0.85,
	"ramp_speed_mult": 0.7, "hill_level": 2}

static var _loaded := false
static var _sight := 2.0
static var _range := 1.10
static var _def := 0.85
static var _ramp := 0.7


## Rules block with defaults filled in (read once; numbers are PROVISIONAL balance fixtures).
static func rules() -> Dictionary:
	var r: Dictionary = DEFAULTS.duplicate()
	var c: Dictionary = Content.rules().get("g6_elevation", {})
	for k in c:
		r[k] = c[k]
	return r


static func _load() -> void:
	var r := rules()
	_sight = float(r.sight_per_level)
	_range = float(r.range_mult_per_level)
	_def = float(r.defence_mult_per_level)
	_ramp = float(r.ramp_speed_mult)
	_loaded = true


## True when the world's map carries a height layer.
static func has_height(w: SimWorld) -> bool:
	return w.map.has("height")


# ------------------------------------------------------------------ map-level helpers (also MapGen/MapIO)
## Level of cell c on map dict m (1 when m has no height or c is outside).
static func map_level(m: Dictionary, c: Vector2i) -> int:
	if not m.has("height"):
		return PLAIN
	var mw := int(m.w)
	if c.x < 0 or c.y < 0 or c.x >= mw or c.y >= int(m.h):
		return PLAIN
	var hg: PackedByteArray = m.height
	return hg[c.y * mw + c.x]


static func map_ramp(m: Dictionary, c: Vector2i) -> bool:
	if not m.has("ramps"):
		return false
	var mw := int(m.w)
	if c.x < 0 or c.y < 0 or c.x >= mw or c.y >= int(m.h):
		return false
	var rp: PackedByteArray = m.ramps
	return rp[c.y * mw + c.x] != 0


## Edge rule between two 4-adjacent cell indices on raw arrays (rp may be empty = no ramps).
static func edge_ok_raw(hg: PackedByteArray, rp: PackedByteArray, i: int, j: int) -> bool:
	var d := absi(int(hg[i]) - int(hg[j]))
	if d == 0:
		return true
	if d > 1 or rp.is_empty():
		return false
	return rp[i] != 0 or rp[j] != 0


## Edge rule on a map dict for adjacent cells a, b (4- or 8-adjacent). Non-adjacent or outside = false.
static func edge_ok_map(m: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	if not m.has("height"):
		return true
	var mw := int(m.w)
	var mh := int(m.h)
	if a.x < 0 or a.y < 0 or a.x >= mw or a.y >= mh or b.x < 0 or b.y < 0 or b.x >= mw or b.y >= mh:
		return false
	var dx := b.x - a.x
	var dy := b.y - a.y
	if absi(dx) > 1 or absi(dy) > 1:
		return false
	var hg: PackedByteArray = m.height
	var rp: PackedByteArray = m.get("ramps", PackedByteArray())
	var ia := a.y * mw + a.x
	var ib := b.y * mw + b.x
	if dx == 0 or dy == 0:
		return ia == ib or edge_ok_raw(hg, rp, ia, ib)
	var c1 := a.y * mw + b.x   # (b.x, a.y)
	var c2 := b.y * mw + a.x   # (a.x, b.y)
	return edge_ok_raw(hg, rp, ia, c1) and edge_ok_raw(hg, rp, c1, ib) \
		and edge_ok_raw(hg, rp, ia, c2) and edge_ok_raw(hg, rp, c2, ib)


# ------------------------------------------------------------------ contract API (section 5.2)
## Height level 0..3 of a cell (1 = plain; also 1 outside the map or without a height layer).
static func height_at(w: SimWorld, cell: Vector2i) -> int:
	return map_level(w.map, cell)


## True for a ramp cell.
static func ramp_at(w: SimWorld, cell: Vector2i) -> bool:
	return map_ramp(w.map, cell)


## False when moving between adjacent cells a and b crosses a cliff edge (nav; PERF6 wires it).
## Applies to Terrain.HEIGHT_CLASSES only; callers skip it for air and naval classes.
static func edge_ok(w: SimWorld, a: Vector2i, b: Vector2i) -> bool:
	return edge_ok_map(w.map, a, b)


## Levels point a stands above point b (negative = below).
static func adv(w: SimWorld, a: Vector2, b: Vector2) -> int:
	var m: Dictionary = w.map
	if not m.has("height"):
		return 0
	return map_level(m, Vector2i(floori(a.x), floori(a.y))) - map_level(m, Vector2i(floori(b.x), floori(b.y)))


## Height line of sight between two points: false when a cell strictly between the endpoint cells is
## higher than the higher endpoint. (Terrain LOS - RIDGE / CLIFF / BUILDING - is checked separately.)
static func los(w: SimWorld, a: Vector2, b: Vector2) -> bool:
	var m: Dictionary = w.map
	if not m.has("height"):
		return true
	return los_map(m, a, b)


static func los_map(m: Dictionary, a: Vector2, b: Vector2) -> bool:
	if not m.has("height"):
		return true
	var c := Vector2i(floori(a.x), floori(a.y))
	var end := Vector2i(floori(b.x), floori(b.y))
	var top := maxi(map_level(m, c), map_level(m, end))
	if top >= MAX_LEVEL or c == end:
		return true
	var hg: PackedByteArray = m.height
	var mw := int(m.w)
	var mh := int(m.h)
	var d := b - a
	var sx := 1 if d.x > 0.0 else -1
	var sy := 1 if d.y > 0.0 else -1
	var tdx := INF if d.x == 0.0 else absf(1.0 / d.x)
	var tdy := INF if d.y == 0.0 else absf(1.0 / d.y)
	var tmx := INF
	if d.x > 0.0:
		tmx = (float(c.x + 1) - a.x) * tdx
	elif d.x < 0.0:
		tmx = (a.x - float(c.x)) * tdx
	var tmy := INF
	if d.y > 0.0:
		tmy = (float(c.y + 1) - a.y) * tdy
	elif d.y < 0.0:
		tmy = (a.y - float(c.y)) * tdy
	var n := absi(end.x - c.x) + absi(end.y - c.y)
	while n > 0:
		if tmx < tmy:
			c.x += sx
			tmx += tdx
		else:
			c.y += sy
			tmy += tdy
		n -= 1
		if c == end:
			break
		if c.x >= 0 and c.y >= 0 and c.x < mw and c.y < mh and int(hg[c.y * mw + c.x]) > top:
			return false
	return true


## Combat-ready LOS: air shooters / air targets and indirect weapons ignore height LOS (s = Combat stats).
static func los_for(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> bool:
	if not w.map.has("height"):
		return true
	if bool(s.get("indirect", false)) or bool(s.get("is_air", false)) or is_air(src) or is_air(t):
		return true
	return los_map(w.map, src.pos, t.pos)


## True for a unit whose def is_air (aircraft ignore height).
static func is_air(e: Dictionary) -> bool:
	return String(e.get("kind", "")) == "unit" and bool(Content.unit(String(e.get("def", ""))).get("is_air", false))


## Weapon range factor for the shooter's height over plain ground (contract hook, no target known).
## Indirect fire keeps it; aircraft get 1.0.
static func range_mult(w: SimWorld, src: Dictionary, s: Dictionary) -> float:
	if not w.map.has("height") or bool(s.get("is_air", false)):
		return 1.0
	var lv := map_level(w.map, Vector2i(floori(src.pos.x), floori(src.pos.y))) - PLAIN
	if lv <= 0:
		return 1.0
	if not _loaded:
		_load()
	return pow(_range, lv)


## Exact per-target range factor: levels src stands above t (>= 0). Optional for PERF6 (fire time).
static func range_mult_vs(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	if not w.map.has("height") or bool(s.get("is_air", false)) or is_air(t):
		return 1.0
	var lv := adv(w, src.pos, t.pos)
	if lv <= 0:
		return 1.0
	if not _loaded:
		_load()
	return pow(_range, lv)


## Damage factor for a target standing above its attacker (x defence_mult_per_level per level).
static func defence_mult(w: SimWorld, src: Dictionary, t: Dictionary) -> float:
	if not w.map.has("height") or not src.has("pos") or not t.has("pos"):
		return 1.0
	var lv := adv(w, t.pos, src.pos)
	if lv <= 0 or is_air(src) or is_air(t):
		return 1.0
	if not _loaded:
		_load()
	return pow(_def, lv)


## Sight bonus (tiles) from height over plain ground. Aircraft get none.
static func sight_bonus(w: SimWorld, e: Dictionary) -> float:
	if not w.map.has("height") or not e.has("pos"):
		return 0.0
	var lv := map_level(w.map, Vector2i(floori(e.pos.x), floori(e.pos.y))) - PLAIN
	if lv <= 0 or is_air(e):
		return 0.0
	if not _loaded:
		_load()
	return _sight * float(lv)


## Speed factor: ground units on a ramp cell move at ramp_speed_mult. Aircraft and ships 1.0.
static func slope_mult(w: SimWorld, e: Dictionary) -> float:
	if not w.map.has("ramps") or not e.has("pos"):
		return 1.0
	if not map_ramp(w.map, Vector2i(floori(e.pos.x), floori(e.pos.y))) or is_air(e):
		return 1.0
	if not _loaded:
		_load()
	return _ramp


## Public ramp speed factor (rules g6_elevation.ramp_speed_mult) for packed / native ports of
## slope_mult (PERF6 CR; added by ORCH after ELEV finished). Same value slope_mult returns on a ramp.
static func ramp_mult() -> float:
	if not _loaded:
		_load()
	return _ramp


# ------------------------------------------------------------------ old-format migration (MapIO v1)
## Version-1 maps: HILL (13) tiles become height level `hill_level` (2) on GRASS, since the height rule
## replaces HILL's old sight / cover / speed bonuses. Every migrated cell next to a one-level step is
## a ramp, so ground that was walkable stays walkable. Maps without HILL are left untouched (no height
## layer: flat, G5 results unchanged). CLIFF (12) stays a terrain code (impassable, blocks LOS).
## Returns the number of migrated cells.
static func migrate_hill(m: Dictionary) -> int:
	var t: PackedByteArray = m.terrain
	var count := 0
	for i in t.size():
		if t[i] == Terrain.HILL:
			count += 1
	if count == 0:
		return 0
	var lvl := clampi(int(rules().hill_level), 0, MAX_LEVEL)
	var mw := int(m.w)
	var n := t.size()
	var hg: PackedByteArray = m.get("height", PackedByteArray())
	if hg.size() != n:
		hg = PackedByteArray()
		hg.resize(n)
		hg.fill(PLAIN)
	for i in n:
		if t[i] == Terrain.HILL:
			hg[i] = lvl
			t[i] = Terrain.GRASS
	var rp: PackedByteArray = m.get("ramps", PackedByteArray())
	if rp.size() != n:
		rp = PackedByteArray()
		rp.resize(n)
		rp.fill(0)
	for i in n:
		if int(hg[i]) != lvl:
			continue
		var x := i % mw
		for j in [i + 1 if x + 1 < mw else -1, i - 1 if x > 0 else -1, i + mw if i + mw < n else -1, i - mw]:
			if j >= 0 and absi(int(hg[j]) - lvl) == 1:
				rp[i] = 1
	m.terrain = t
	m.height = hg
	m.ramps = rp
	return count
