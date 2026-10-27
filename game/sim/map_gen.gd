extends RefCounted
## Map generation entry point (G3b: dispatches by map id to sim/maps/*.gd; owner MAP4).
## River Crossing (river_crossing_s): authored macro geography + seeded legal-zone variation.
## Authored (seed never changes these): diagonal river, central 3-wide bridge on the main
## road, two fords at fixed river positions, spawn sites. Seeded: river meander amplitude,
## forest clusters, ridges, dirt patches, resource placement.
## The map is point-symmetric about its centre: (x, y) <-> (W-1-x, H-1-y), so both sides
## get mirror-identical openings. Every variant must pass validate() or it is re-rolled.

const W := 96
const H := 96
## G3a: 4 spawns. 0/1 are the original diagonal corners; 2/3 (one per bank) mirror each other.
## (The other two corners lie on the river line x + y = 95, so they cannot host a base.)
## 2-side matches use spawns 0 and 1 exactly as before.
const SPAWNS := [Vector2i(14, 14), Vector2i(81, 81), Vector2i(50, 10), Vector2i(45, 85)]
const RIVER_HALF_WIDTH := 1.6
const FORD_U := 40          # fords where (x - y) == +-40 along the river
const MAX_ATTEMPTS := 12


## G3b (MAP4): generator modules by map id (content/maps.json lists the same ids).
const MODULES := {
	"industrial_heartland_m": preload("res://sim/maps/industrial_heartland.gd"),
	"valley_conquest_l": preload("res://sim/maps/valley_conquest.gd"),
	"coastal_front_m": preload("res://sim/maps/coastal_front.gd"),  # G5 (NAVAL)
	"ridge_bastion_m": preload("res://sim/maps/ridge_bastion.gd"),  # G6 (MODES6) survival
	"river_dam_m": preload("res://sim/maps/river_dam.gd"),  # G6 (MODES6) survival
	"lp_test512": preload("res://sim/maps/lp_test512.gd"),  # G7 (SCALE7) Last Protocol scale test map
	"last_protocol": preload("res://sim/maps/last_protocol.gd"),  # G7 (LPMAP7) the Last Protocol map (mode only)
}
## G7 (SCALE7): the same generator at another size (id -> [module, side]); generate() calls module.gen().
const SIZED := {"lp_test768": ["lp_test512", 768]}
const MapCheck = preload("res://sim/maps/map_check.gd")
## G6 (owner ELEV, CONTRACTS_G6 section 7): authored height for River Crossing (_rc_height, its own rng
## stream, so the terrain bytes and re-roll decisions stay exactly as before), height noise + ramp
## placement + validation for generated / editor maps (add_height_noise, connect_ramps,
## validate_height). Every validator walks the height edge rule (cliffs block, ramps join).
const MapUtil = preload("res://sim/maps/map_util.gd")
const Elevation = preload("res://sim/systems/elevation.gd")
const DEFAULT_ID := "river_crossing_s"
## River Crossing spawn sets: identity, so 2/3/4-side matches use spawns 0..n-1 exactly as before.
const RC_SPAWN_SETS := {"2": [0, 1], "3": [0, 1, 2], "4": [0, 1, 2, 3]}

static var _defs: Dictionary = {}


## content/maps.json entries by id (read once; FileAccess so it works in exported builds).
static func defs() -> Dictionary:
	if _defs.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps.json"))
		if typeof(j) == TYPE_DICTIONARY:
			for d in j.get("maps", []):
				_defs[String(d.id)] = d
	return _defs


static func ids() -> Array:
	return [DEFAULT_ID] + MODULES.keys() + SIZED.keys()


static func has_map(map_id: String) -> bool:
	return map_id == DEFAULT_ID or MODULES.has(map_id) or SIZED.has(map_id)


## Spawn cell for side i of n (CONTRACTS_G3b section 4): map.spawns[map.spawn_sets[str(n)][i]].
## Falls back to spawns[i % size] for maps/saves without spawn_sets.
static func spawn_for(m: Dictionary, i: int, n: int) -> Vector2i:
	var spawns: Array = m.spawns
	var sets: Dictionary = m.get("spawn_sets", {})
	var key := str(n)
	if sets.has(key) and i < (sets[key] as Array).size():
		return spawns[int(sets[key][i]) % spawns.size()]
	return spawns[i % spawns.size()]


static func generate(seed_value: int, map_id: String = "river_crossing_s") -> Dictionary:
	var m := {}
	var mod = MODULES.get(map_id)
	var sized: Array = SIZED.get(map_id, [])
	for attempt in MAX_ATTEMPTS:
		if not sized.is_empty():
			m = MODULES[String(sized[0])].gen(seed_value, attempt, int(sized[1]))
		else:
			m = _try(seed_value, attempt) if mod == null else mod.try_gen(seed_value, attempt)
		var reason := validate(m)
		if reason == "":
			m.gen_attempt = attempt
			return m
		m.last_validation_error = reason
	push_error("MapGen: no valid variant after %d attempts: %s" % [MAX_ATTEMPTS, m.get("last_validation_error", "")])
	return m


static func _idx(x: int, y: int) -> int:
	return y * W + x


static func _mirror(c: Vector2i) -> Vector2i:
	return Vector2i(W - 1 - c.x, H - 1 - c.y)


static func _try(seed_value: int, attempt: int) -> Dictionary:
	var rng := SimRng.new(seed_value * 7919 + attempt * 104729 + 17)
	var t := PackedByteArray()
	t.resize(W * H)
	t.fill(Terrain.GRASS)

	# --- river: |x + y - (W-1) - off(u)| <= hw, u = x - y; off is odd so the map stays symmetric
	var a1 := rng.randf_range(1.5, 3.5)
	var a2 := rng.randf_range(0.5, 1.8)
	var f1 := rng.randf_range(0.04, 0.08)
	var f2 := rng.randf_range(0.11, 0.17)
	var river := {}
	for y in H:
		for x in W:
			var u := float(x - y)
			var off := a1 * sin(u * f1) + a2 * sin(u * f2)
			if absf(float(x + y - (W - 1)) - off) <= RIVER_HALF_WIDTH:
				t[_idx(x, y)] = Terrain.WATER
				river[Vector2i(x, y)] = true

	# --- main road (|x - y| <= 1) between spawns; bridge where it crosses the river
	var bridge_cells := []
	for i in range(SPAWNS[0].x + 4, SPAWNS[1].x - 3):
		for d in [-1, 0, 1]:
			var c := Vector2i(i + d, i)
			if c.x < 0 or c.x >= W:
				continue
			if river.has(c):
				t[_idx(c.x, c.y)] = Terrain.BRIDGE
				bridge_cells.append(c)
			else:
				t[_idx(c.x, c.y)] = Terrain.ROAD

	# --- fords at fixed positions along the river
	var ford_cells := []
	for c in river:
		var u: int = c.x - c.y
		if absi(absi(u) - FORD_U) <= 1:
			t[_idx(c.x, c.y)] = Terrain.FORD
			ford_cells.append(c)

	# --- seeded features in the half-plane x + y < W-1, then mirrored (see _set_mirrored)
	# dirt patches (cosmetic + slightly slower)
	for n in 10:
		var cx := rng.randi_range(4, 80)
		var cy := rng.randi_range(4, 80)
		var r := rng.randf_range(1.5, 3.5)
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				if Vector2(dx, dy).length() <= r + rng.randf_range(-0.6, 0.6):
					_set_mirrored(t, ford_cells, Vector2i(cx + dx, cy + dy), Terrain.DIRT)
	# forest clusters
	for n in 11:
		var cx := rng.randi_range(3, 85)
		var cy := rng.randi_range(3, 85)
		var r := rng.randf_range(2.0, 4.5)
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				if Vector2(dx, dy).length() <= r + rng.randf_range(-0.8, 0.5):
					_set_mirrored(t, ford_cells, Vector2i(cx + dx, cy + dy), Terrain.FOREST)
	# ridges (impassable rock lines)
	for n in 3:
		var p := Vector2(rng.randi_range(8, 70), rng.randi_range(8, 70))
		var ang := rng.randf_range(0.0, TAU)
		var length := rng.randi_range(5, 9)
		for s in length:
			var c := Vector2i(roundi(p.x + cos(ang) * s), roundi(p.y + sin(ang) * s))
			_set_mirrored(t, ford_cells, c, Terrain.RIDGE)
			if rng.chance(0.4):
				_set_mirrored(t, ford_cells, c + Vector2i(1, 0), Terrain.RIDGE)

	# base pads: dirt around spawns (buildable)
	for s in SPAWNS:
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				var c: Vector2i = s + Vector2i(dx, dy)
				if Vector2(dx, dy).length() <= 4.5 and t[_idx(c.x, c.y)] == Terrain.GRASS:
					t[_idx(c.x, c.y)] = Terrain.DIRT

	# --- resources: per-base (3 salvage + 2 ore) and contested near fords (1 salvage + 1 ore per side)
	var resources := []
	var taken := {}
	# 2026-10-23 (G2): salvage 1200->2000, ore 2500->3000; G2 sinks (repair, trucks, officers)
	# starved long games (soak seeds 1/4 stalled with every pile mined out). PROVISIONAL.
	var picks := [["salvage", 2000], ["salvage", 2000], ["salvage", 2000], ["ore", 3000], ["ore", 3000]]
	var k := 0
	var guard := 0
	for base in [SPAWNS[0], SPAWNS[2]]:   # each base set is mirrored onto spawns 1 and 3
		k = 0
		guard = 0
		while k < picks.size() and guard < 400:
			guard += 1
			var ang := rng.randf_range(0.0, TAU)
			var dist := rng.randf_range(6.0, 10.0)
			var c: Vector2i = base + Vector2i(roundi(cos(ang) * dist), roundi(sin(ang) * dist))
			if c.x + c.y >= W - 6:
				continue
			if not _resource_ok(t, c, taken):
				continue
			if absi(c.x - c.y) <= 2:
				continue
			_add_resource(resources, taken, t, picks[k][0], picks[k][1], c)
			k += 1
	# contested: near the side-0 ford (u = -40 is x - y = -40 ... use the one in our half)
	var contested := [["ore", 2000], ["salvage", 2000]]
	k = 0
	guard = 0
	var ford_anchor := Vector2i(28, 68) if (28 + 68) < W - 1 else Vector2i(27, 67)
	while k < contested.size() and guard < 400:
		guard += 1
		var c := ford_anchor + Vector2i(rng.randi_range(-6, 4), rng.randi_range(-6, 2))
		if c.x + c.y >= W - 6:
			continue
		if not _resource_ok(t, c, taken):
			continue
		_add_resource(resources, taken, t, contested[k][0], contested[k][1], c)
		k += 1

	var m := {
		"id": "river_crossing_s", "name": "River Crossing", "w": W, "h": H,
		"terrain": t, "spawns": SPAWNS.duplicate(), "resources": resources,
		"bridge_cells": bridge_cells, "ford_cells": ford_cells, "seed": seed_value,
		"river_params": [a1, a2, f1, f2],
		# G3b (MAP4) shared map fields; the terrain/resources above are unchanged.
		"size": "s", "spawn_sets": RC_SPAWN_SETS.duplicate(true), "max_sides": 4,
		"bridges": [{"id": 0, "name": "River Bridge", "cells": bridge_cells.duplicate()}], "hold_bridge": 0,
		"decor": [], "pois": [{"type": "bridge", "name": "River Bridge", "cell": Vector2i(47, 47)},
			{"type": "ford", "name": "North Ford", "cell": Vector2i(27, 67)}, {"type": "ford", "name": "South Ford", "cell": Vector2i(68, 28)}],
	}
	_rc_height(m, seed_value, attempt)
	return m


static func _protected(t: PackedByteArray, ford_cells: Array, c: Vector2i) -> bool:
	if c.x < 1 or c.y < 1 or c.x >= W - 1 or c.y >= H - 1:
		return true
	for s in SPAWNS:
		if c.distance_to(s) < 11.0:
			return true
	if absi(c.x - c.y) <= 3:
		return true  # road corridor
	var code := t[_idx(c.x, c.y)]
	if code == Terrain.WATER or code == Terrain.FORD or code == Terrain.BRIDGE or code == Terrain.ROAD:
		return true
	for fc in ford_cells:
		if c.distance_to(fc) < 4.0:
			return true
	return false


## Writes code at c and its mirror. Only cells strictly in the x + y < W-1 half are seeded.
static func _set_mirrored(t: PackedByteArray, ford_cells: Array, c: Vector2i, code: int) -> void:
	if c.x + c.y >= W - 1:
		return
	if _protected(t, ford_cells, c):
		return
	t[_idx(c.x, c.y)] = code
	var m := _mirror(c)
	t[_idx(m.x, m.y)] = code


static func _resource_ok(t: PackedByteArray, c: Vector2i, taken: Dictionary) -> bool:
	if c.x < 2 or c.y < 2 or c.x >= W - 2 or c.y >= H - 2:
		return false
	var code := t[_idx(c.x, c.y)]
	if code != Terrain.GRASS and code != Terrain.DIRT:
		return false
	for s in SPAWNS:
		if c.distance_to(s) < 5.0:
			return false
	for o in taken:
		if c.distance_to(o) < 2.5:
			return false
	return true


static func _add_resource(resources: Array, taken: Dictionary, t: PackedByteArray, res: String, amount: int, c: Vector2i) -> void:
	for cc in [c, _mirror(c)]:
		resources.append({"res": res, "amount": amount, "cell": cc})
		taken[cc] = true
		t[_idx(cc.x, cc.y)] = Terrain.DIRT


## Returns "" if the map is legal, else a human-readable failure with location.
static func validate(m: Dictionary) -> String:
	if String(m.get("id", "")) == "coastal_front_m":  # G5 (NAVAL): adds the coastal checks
		return MODULES["coastal_front_m"].validate(m)
	if String(m.get("id", "")) in ["ridge_bastion_m", "river_dam_m"]:  # G6 (MODES6): gate / lane / barrier checks
		return MODULES[String(m.id)].validate(m)
	if String(m.get("id", "")) == "last_protocol":  # G7 (LPMAP7): asymmetric 1v1 vs the Machine, its own checks
		return MODULES["last_protocol"].validate(m)
	if String(m.get("id", DEFAULT_ID)) != DEFAULT_ID:
		return MapCheck.validate(m)
	var t: PackedByteArray = m.terrain
	for s in m.spawns:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if not Terrain.buildable(t[_idx(s.x + dx, s.y + dy)]):
					return "Spawn %s footprint not buildable at %s." % [s, s + Vector2i(dx, dy)]
	var hi := MapCheck.height_issue(m, true)   # G6 (ELEV)
	if hi != "":
		return hi
	var lay := MapCheck.layers(m)
	for mc in ["foot", "vehicle"]:
		var reach := _flood(t, m.spawns[0] + Vector2i(0, 3), mc, lay[0], lay[1])
		for si in range(1, m.spawns.size()):
			var other: Vector2i = m.spawns[si] + Vector2i(0, 3)
			if not reach.has(other):
				return "No %s route between spawns %s and %s." % [mc, m.spawns[0], m.spawns[si]]
		for r in m.resources:
			var ok := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if reach.has(r.cell + d):
					ok = true
			if not ok:
				return "Resource %s at %s unreachable by %s." % [r.res, r.cell, mc]
	return ""


static func _flood(t: PackedByteArray, start: Vector2i, mc: String, hg: PackedByteArray = PackedByteArray(), rp: PackedByteArray = PackedByteArray()) -> Dictionary:
	var seen := {start: true}
	var q := [start]
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H or seen.has(n):
				continue
			if Terrain.passable(t[_idx(n.x, n.y)], mc) and (hg.is_empty() or Elevation.edge_ok_raw(hg, rp, _idx(c.x, c.y), _idx(n.x, n.y))):
				seen[n] = true
				q.append(n)
	return seen


## G4 (owner MAPIO, CONTRACTS_G4 section 5): exports a built-in map as a .rtsmap file with one
## player per spawn (slot i = spawn i, own team, human_a, AI for slots > 0) and the default
## scenario (start packages, HQ elimination). Generator output is untouched. Returns "" or an error.
## MapIO is loaded at call time (map_io -> victory -> map_gen preload cycle otherwise).
static func to_file(seed_value: int, map_id: String, path: String) -> String:
	if not has_map(map_id):
		return "Unknown map '%s'." % map_id
	var m := generate(seed_value, map_id)
	var d: Dictionary = Content.rules().get("defaults", {})
	var players := []
	for i in (m.spawns as Array).size():
		players.append({"slot": i, "faction": "human_a", "team": i, "stage": int(d.get("stage", 8)),
			"credits": int(d.get("starting_credits", 2500)), "ai": i > 0,
			"difficulty": String(d.get("ai_difficulty", "normal")), "start": m.spawns[i]})
	var sc := {"name": String(m.get("name", map_id)), "author": "built-in",
		"description": "Built-in map %s exported with seed %d." % [map_id, seed_value],
		"players": players, "entities": [], "victory": {"victory": "hq_elimination"},
		"regions": [], "triggers": [], "start_packages": true}
	return load("res://sim/map_io.gd").save(path, m, sc)


# ================================================================ G6 height (owner ELEV)
## River Crossing authored height: two mirrored hill pairs (level 2, every edge a ramp) with ridge caps
## (level 3, ramps every third edge cell + connect_ramps) overlooking the north ford approach and the
## east flank of spawn 2. Spawns, the road corridor, the river and fords stay plain (level 1).
## Its own rng stream: the terrain bytes and re-roll decisions above are untouched.
static func _rc_height(m: Dictionary, seed_value: int, attempt: int) -> void:
	var rng := SimRng.new(seed_value * 7919 + attempt * 104729 + 9173)
	var t: PackedByteArray = m.terrain
	var hg := MapUtil.new_layer(W, H, 1)
	var ja := Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
	var jb := Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
	MapUtil.hdisc(hg, W, H, Vector2i(22, 46) + ja, 4.5 + rng.randf_range(-0.4, 0.4), 2)
	MapUtil.hdisc(hg, W, H, Vector2i(21, 45) + ja, 1.8, 3)
	MapUtil.hdisc(hg, W, H, Vector2i(56, 20) + jb, 4.0 + rng.randf_range(-0.4, 0.4), 2)
	MapUtil.hdisc(hg, W, H, Vector2i(57, 19) + jb, 1.5, 3)
	m.height = hg
	m.ramps = MapUtil.derive_ramps(hg, t, W, H, [0, 1, 3])
	connect_ramps(m, true)


## Height noise for a generated / editor map (m = w.map shape): bilinear value noise over a coarse
## lattice, cut into levels by quantiles (valley_frac lowest -> 0, ridge_frac highest -> 3, the next
## hill_frac -> 2, the rest 1). Water / shore / crossing tiles stay plain, spawn sites are flattened,
## then ramps are derived (ramp_every) and connect_ramps joins every walkable region.
## opts override rules.g6_elevation.gen (symmetric: true mirrors the map's first half).
static func add_height_noise(m: Dictionary, seed_value: int, opts: Dictionary = {}) -> void:
	var g: Dictionary = (Elevation.rules().get("gen", {}) as Dictionary).duplicate()
	g.merge(opts, true)
	var w := int(m.w)
	var h := int(m.h)
	var n := w * h
	var t: PackedByteArray = m.terrain
	var rng := SimRng.new(seed_value * 2654435 + 977)
	var cell := maxi(2, int(g.get("noise_cells", 12)))
	var lw := w / cell + 2
	var lh := h / cell + 2
	var lat := PackedFloat32Array()
	lat.resize(lw * lh)
	for i in lat.size():
		lat[i] = rng.randf()
	var f := PackedFloat32Array()
	f.resize(n)
	var hist := PackedInt32Array()
	hist.resize(256)
	hist.fill(0)
	for y in h:
		for x in w:
			var gx := float(x) / float(cell)
			var gy := float(y) / float(cell)
			var x0 := int(gx)
			var y0 := int(gy)
			var fx := gx - float(x0)
			var fy := gy - float(y0)
			var top := lerpf(lat[y0 * lw + x0], lat[y0 * lw + x0 + 1], fx)
			var bot := lerpf(lat[(y0 + 1) * lw + x0], lat[(y0 + 1) * lw + x0 + 1], fx)
			var v := clampf(lerpf(top, bot, fy), 0.0, 0.9999)
			f[y * w + x] = v
			hist[int(v * 256.0)] += 1
	var cut_lo := _quantile(hist, n, float(g.get("valley_frac", 0.06)))
	var cut_hill := _quantile(hist, n, 1.0 - float(g.get("hill_frac", 0.16)) - float(g.get("ridge_frac", 0.04)))
	var cut_ridge := _quantile(hist, n, 1.0 - float(g.get("ridge_frac", 0.04)))
	var hg := MapUtil.new_layer(w, h, 1)
	var sym := bool(g.get("symmetric", false))
	for i in n:
		var src := mini(i, n - 1 - i) if sym else i
		var b := int(f[src] * 256.0)
		var lv := 1
		if b < cut_lo:
			lv = 0
		elif b >= cut_ridge:
			lv = 3
		elif b >= cut_hill:
			lv = 2
		var code := int(t[i])
		if Terrain.is_water(code) or code == Terrain.BEACH or code == Terrain.BRIDGE or code == Terrain.FORD:
			lv = 1
		hg[i] = lv
	var flat_r := float(g.get("spawn_flat_r", 9.0))
	for s in m.get("spawns", []):
		var sc: Vector2i = s
		var ri := int(ceil(flat_r))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var c := sc + Vector2i(dx, dy)
				if c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and Vector2(dx, dy).length() <= flat_r:
					hg[c.y * w + c.x] = 1
	var ev := maxi(1, int(g.get("ramp_every", 3)))
	m.height = hg
	m.ramps = MapUtil.derive_ramps(hg, t, w, h, [ev, ev, ev])
	connect_ramps(m, sym)


static func _quantile(hist: PackedInt32Array, n: int, q: float) -> int:
	var want := int(q * float(n))
	var acc := 0
	for b in 256:
		acc += hist[b]
		if acc > want:
			return b
	return 256


## Ramp placement (MapUtil.connect_ramps): joins every foot-walkable region split off by height.
static func connect_ramps(m: Dictionary, symmetric: bool = false) -> int:
	return MapUtil.connect_ramps(m, symmetric)


## Height validation for any map (an SimWorld or a w.map-shaped Dictionary): ED6's brushes call it.
## Returns [{code, msg, cell?}] (empty = valid): height_invalid (sizes, levels, a ramp on no one-level
## step), spawn_not_flat (5x5 start footprint on mixed levels), spawn_unreachable (foot / vehicle from
## the first spawn through ramps), resource_unreachable (foot). Flat maps (no height) return [].
static func validate_height(w) -> Array:
	var m: Dictionary = w.map if w is SimWorld else w
	var out := []
	if not m.has("height"):
		return out
	var hi := MapCheck.height_issue(m, false)
	if hi != "":
		out.append({"code": "height_invalid", "msg": hi})
		return out
	var mw := int(m.w)
	var mh := int(m.h)
	var hg: PackedByteArray = m.height
	var rp: PackedByteArray = m.get("ramps", PackedByteArray())
	var spawns: Array = m.get("spawns", [])
	for s in spawns:
		var sc: Vector2i = s
		var lv := Elevation.map_level(m, sc)
		var flat := true
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if Elevation.map_level(m, sc + Vector2i(dx, dy)) != lv:
					flat = false
		if not flat:
			out.append({"code": "spawn_not_flat", "msg": "Start %s sits on mixed height levels." % [sc], "cell": sc})
	if spawns.is_empty():
		return out
	var foot := PackedInt32Array()
	for mc in ["foot", "vehicle"]:
		var pm := MapCheck.passmask(m.terrain, mc)
		var p0 := MapUtil.probe_cell(pm, mw, mh, spawns[0])
		if p0.x < 0:
			continue
		var reach := MapCheck.bfs_h(pm, mw, mh, p0.y * mw + p0.x, hg, rp)
		if mc == "foot":
			foot = reach
		for k in range(1, spawns.size()):
			var pk := MapUtil.probe_cell(pm, mw, mh, spawns[k])
			if pk.x < 0 or reach[pk.y * mw + pk.x] < 0:
				out.append({"code": "spawn_unreachable", "msg": "Start %s cannot be reached by %s through ramps." % [spawns[k], mc], "cell": spawns[k]})
	for r in m.get("resources", []):
		var c: Vector2i = r.cell
		var ok := foot.is_empty()
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + d
			if not foot.is_empty() and q.x >= 0 and q.y >= 0 and q.x < mw and q.y < mh and foot[q.y * mw + q.x] >= 0:
				ok = true
		if not ok:
			out.append({"code": "resource_unreachable", "msg": "Resource at %s cannot be reached on foot." % [c], "cell": c})
	return out
