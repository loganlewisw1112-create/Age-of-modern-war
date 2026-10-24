extends RefCounted
## Combat (owner: agent B / sim-mil). Target acquisition, chasing, firing, damage, death.
## Commands: attack. Contract: docs/CONTRACTS.md section 5.
##
## Target choice is deterministic: nearest visible enemy (unit or building; distance to a building
## is measured to its footprint), ties go to the lower id. Scans are staggered: each shooter rescans
## every SCAN_EVERY ticks ((tick + id) % SCAN_EVERY == 0) and keeps a still-valid target in between.
## Stances by order type:
##   idle         aggressive: engage the nearest enemy within sight, chase it while it stays in sight.
##   attack_move  as idle, then resume the path to order.target; idle on arrival.
##   attack       chase target_id while visible; if it becomes non-visible go to its last-known
##                position, then idle. Destroyed target -> idle.
##   hold         fire at enemies within weapon range only, never move.
##   move/other   no auto-engage (forced move), but return fire (see engineers).
## ENGINEERS (units with can_build) ONLY RETURN FIRE: they never auto-acquire, whatever their order;
## they shoot back at the unit that hit them within the last RETURN_FIRE_TICKS if it is visible and
## in range, without moving. An explicit `attack` order is still obeyed.
## Buildings with a weapon (guard_tower) fire only when built, within weapon range.
## Randomness (hit roll, miss dispersion of the tracer end point) uses w.rng only.
## G3a (S3-sim, CONTRACTS_G3a section 3):
##   AIR: only weapons with `anti_air` may target units whose def has `is_air` (search, kept
##   targets, explicit attack orders and command validation all filter this).
##   ARTILLERY (`indirect` weapons): engages any visible enemy within range and beyond min_range
##   (search radius = max(sight, range)), ignores Damage.line_clear, and on firing applies splash to
##   every ground unit/building within `splash` of the impact point (allies too) with linear falloff
##   to 50% at the edge: one ShotFired {indirect:true} plus one Damage event per entity hit.
##   An explicit attack on a target inside min_range backs the shooter away.

const Movement = preload("res://sim/systems/movement.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Status = preload("res://sim/systems/status.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Supply = preload("res://sim/systems/supply.gd")
const NativeCore = preload("res://sim/native_core.gd")
const Tiers = preload("res://sim/systems/tiers.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")

const BUCKET := 2.0
const GRID_STRIDE := 1024
const SCAN_EVERY := 4
const SCAN_EVERY_ENGAGED := 32
const CHASE_REPATH_TICKS := 10
const RETURN_FIRE_TICKS := 60
const FIRING_HINT_TICKS := 3
const Q := 1.0 / 1024.0          # quantum for saved floats (exact in decimal text)

static var _stats: Dictionary = {}
static var _no_search := false   # REDUCED pass: searches return null (Tiers contact bound)


## Cached combat stats for an entity def.
static func stats(e: Dictionary) -> Dictionary:
	var key = e.def   # unit and building def ids are disjoint
	if _stats.has(key):
		return _stats[key]
	var d: Dictionary = Content.unit(e.def) if e.kind == "unit" else Content.building(e.def)
	var wid := String(d.get("weapon", ""))
	var wd: Dictionary = Content.weapon(wid) if wid != "" else {}
	var s := {
		"weapon": wid if not wd.is_empty() else "",
		"range": float(wd.get("range", 0)),
		"cooldown": float(wd.get("cooldown", 1)),
		"accuracy": float(wd.get("accuracy", 0)),
		"damage": float(wd.get("damage", 0)),
		"cls": String(wd.get("class", "")),
		"armor": String(d.get("armor", "infantry")),
		"sight": float(d.get("sight", 0)),
		"builder": bool(d.get("can_build", false)),
		"aa": bool(wd.get("anti_air", false)),
		"indirect": bool(wd.get("indirect", false)),
		"min_range": 0.0 if bool(wd.get("guided", false)) else float(wd.get("min_range", 0)),  # G3b STG4: guided
		"guided": bool(wd.get("guided", false)),  # G3b STG4: indirect, no friendly splash, no scatter
		"splash": float(wd.get("splash", 0)),
		"is_air": bool(d.get("is_air", false)),
	}
	_stats[key] = s
	return s


## Damage one hit from shooter e would do to target t (weapon damage x armor table).
static func shot_damage(e: Dictionary, t: Dictionary) -> float:
	var s := stats(e)
	return s.damage * Content.armor_mult(s.cls, stats(t).armor)


## Distance from p to target t (footprint rectangle for buildings, centre for units).
static func dist_to(p: Vector2, t: Dictionary) -> float:
	if t.kind == "building":
		var o: Vector2i = t.cell
		var sz := float(t.size)
		var q := Vector2(clampf(p.x, float(o.x), float(o.x) + sz), clampf(p.y, float(o.y), float(o.y) + sz))
		return p.distance_to(q)
	var tp: Vector2 = t.pos
	return p.distance_to(tp)


# ================================================================ tick
## Cooldown is authoritative in whole ticks (e.cd_ticks); e.cooldown (seconds) mirrors it as
## cd_ticks / 20. Integer state keeps the var_to_str save round trip exact.
static func _cd(e: Dictionary) -> int:
	if e.has("cd_ticks"):
		return int(e.cd_ticks)
	return maxi(ceili(float(e.get("cooldown", 0.0)) * SimWorld.TICK_RATE - 1e-6), 0)


## G3b PERF4/PERF4-2 (fidelity tiers + native search). FULL units come from the Tiers lists
## (Tiers.lists(w).full: one shared index, no per-tick pass over every unit) and run every tick.
## A REDUCED unit (Tiers: no enemy unit or building anywhere near) runs only on its stride tick
## ((tick + id) % Tiers.SCAN_STRIDE == 0), after the FULL units, with its cooldown and firing hint
## caught up by SCAN_STRIDE. It never searches: by the Tiers contact bound no enemy can be inside
## any search radius of it (and it is inside none), so the search result is null by construction
## and REDUCED units are left out of the per-tick grids altogether.
## With the native core live, target search asks RtsGrid.nearest_enemy_batch for the nearest
## enemy candidate (one batched call for every FULL unit on its scan slot, single calls otherwise)
## and verifies it (visible, not concealed, min_range); if it fails the check, an exact scan of
## RtsGrid.query_radius runs instead, so the result equals find_target().
static func tick(w: SimWorld) -> void:
	var t0 := Time.get_ticks_usec() if SimIndex.profiling else 0
	var tiers_on := Tiers.enabled(w)
	var idx := Tiers.lists(w)
	var units: Array = idx.full if tiers_on else idx.kinds.get("unit", [])
	var all_blds: Array = idx.kinds.get("building", [])
	var native := NativeCore.enabled(w)
	var ents: Dictionary = w.entities
	var grid := {}   # owner -> {bucket key -> [unit dicts]} (GDScript search, splash, Damage.near_miss)
	var blds := []
	var act := []    # FULL units that act this tick, ascending id
	var nids := PackedInt32Array()
	var npos := PackedVector2Array()
	var nteam := PackedInt32Array()
	var nflags := PackedInt32Array()
	var nidx := {}
	var teams := {}
	for fid in w.factions:
		teams[int(fid)] = int(w.factions[fid].get("team", fid))
	var scan_src := PackedInt32Array()   # native pre-batch: FULL units on their scan slot
	var scan_r := PackedFloat32Array()
	var scan_need := PackedInt32Array()
	var scan_ids := PackedInt32Array()
	var tick := w.tick
	# the GDScript grid serves the non-native search/splash and Damage.near_miss; with native live
	# it is skipped once damage.gd declares NEAR_MISS_NG (near_miss reads w.cache.combat_ng then)
	var need_grid := not native or not _dmg_uses_ng()
	for e: Dictionary in units:
		var id: int = e.id
		if not ents.has(id):
			continue
		var p: Vector2 = e.pos
		var o: int = e.owner
		if need_grid:
			var g = grid.get(o)
			if g == null:
				g = {}
				grid[o] = g
			var key := floori(p.x / BUCKET) + floori(p.y / BUCKET) * GRID_STRIDE
			var cell = g.get(key)
			if cell == null:
				g[key] = [e]
			else:
				cell.append(e)
		if native and teams.has(o):
			var sv = _stats.get(e.def)
			var s: Dictionary = sv if sv != null else stats(e)
			var si := nids.size()
			nidx[id] = si
			nids.append(id)
			npos.append(p)
			nteam.append(int(teams[o]))
			nflags.append(2 if s.is_air else 1)
			if (tick + id) % SCAN_EVERY == 0 and s.weapon != "" and not s.builder:
				var ot = e.order.get("type", "idle")
				if ot == "idle" or ot == "attack_move" or ot == "hold":
					scan_src.append(si)
					scan_r.append(float(s.range) if ot == "hold" else _search_r(s))
					scan_need.append(0 if s.aa else 1)
					scan_ids.append(id)
		if int(e.firing) > 0:
			e.firing = int(e.firing) - 1
		var cdv = e.get("cd_ticks")
		var cd: int = int(cdv) if cdv != null else _cd(e)
		if cd > 0:
			cd -= 1
			e.cd_ticks = cd
			e.cooldown = float(cd) / SimWorld.TICK_RATE
		act.append(e)
	var red := []    # REDUCED units on their stride tick
	if tiers_on:
		var dec := Tiers.SCAN_STRIDE
		for e: Dictionary in Tiers.due_reduced(w, Tiers.SCAN_STRIDE):
			if not ents.has(int(e.id)) or int(e.get("tier", 0)) != Tiers.REDUCED:
				continue
			if int(e.firing) > 0:
				e.firing = maxi(int(e.firing) - dec, 0)
			var cd := _cd(e)
			if cd > 0:
				cd = maxi(cd - dec, 0)
				e.cd_ticks = cd
				e.cooldown = float(cd) / SimWorld.TICK_RATE
			red.append(e)
	for b in all_blds:
		if not ents.has(int(b.id)):
			continue
		blds.append(b)
		var cd := _cd(b)
		if cd > 0:
			cd -= 1
			b.cd_ticks = cd
			b.cooldown = float(cd) / SimWorld.TICK_RATE
	if SimIndex.profiling:
		t0 = SimIndex.pt("cmb.prep", t0)
	w.cache["combat_grid"] = grid
	w.cache["combat_blds"] = blds
	if native:
		var ng = w.cache.get("combat_rgrid")
		if ng == null:
			ng = NativeCore.make_grid(w)
			ng.setup(int(w.map.w), int(w.map.h), 4.0)
			w.cache["combat_rgrid"] = ng
		var zr := PackedFloat32Array()
		zr.resize(nids.size())
		zr.fill(0.0)
		ng.rebuild(nids, npos, nteam, zr)
		ng.set_flags(nflags)
		var pre := {}
		if not scan_src.is_empty():
			var res: PackedInt32Array = ng.nearest_enemy_batch(scan_src, scan_r, scan_need)
			for i in scan_ids.size():
				pre[scan_ids[i]] = Vector2(float(res[i]), scan_r[i])
		w.cache["combat_ng"] = {"grid": ng, "idx": nidx, "pre": pre, "eb": {}}
	else:
		w.cache.erase("combat_ng")
	if SimIndex.profiling:
		t0 = SimIndex.pt("cmb.ngrid", t0)
	# act in ascending id order, FULL units and buildings interleaved as in w.entities
	var bi := 0
	for e in act:
		while bi < blds.size() and int(blds[bi].id) < int(e.id):
			_bld_act(w, blds[bi], grid, blds)
			bi += 1
		if ents.has(int(e.id)):  # destroyed earlier this tick: dead entities never act
			_unit_tick(w, e, grid, blds)
	while bi < blds.size():
		_bld_act(w, blds[bi], grid, blds)
		bi += 1
	if SimIndex.profiling:
		t0 = SimIndex.pt("cmb.act", t0)
	_no_search = true
	for e in red:
		if ents.has(int(e.id)):
			_unit_tick(w, e, grid, blds)
	_no_search = false
	if SimIndex.profiling:
		SimIndex.pt("cmb.reduced", t0)


static var _dmg_ng := -1


static func _dmg_uses_ng() -> bool:
	if _dmg_ng < 0:
		_dmg_ng = 1 if (Damage as Script).get_script_constant_map().has("NEAR_MISS_NG") else 0
	return _dmg_ng == 1


static func _bld_act(w: SimWorld, b: Dictionary, grid: Dictionary, blds: Array) -> void:
	if w.entities.has(int(b.id)) and b.get("built", false):
		_tower_tick(w, b, grid, blds)


## True if a shooter with stats s may engage t at all (air targets need an anti_air weapon).
static func can_target(s: Dictionary, t: Dictionary) -> bool:
	return bool(s.aa) or t.kind != "unit" or not bool(stats(t).is_air)


## Search radius for auto-acquisition: sight, or the full range for indirect fire.
static func _search_r(s: Dictionary) -> float:
	return maxf(float(s.sight), float(s.range)) if bool(s.indirect) else float(s.sight)


static func _valid_target(w: SimWorld, fid: int, tid: int, s = null):
	if tid < 0:
		return null
	var t = w.entities.get(tid)
	if t != null and t.kind == "structure":
		return t if String(t.get("state", "")) != "ruined" and Fog.is_visible(w, fid, t.pos) else null  # explicit attack on the bridge only (C2: a ruin is never a target)
	if t == null or (t.kind != "unit" and t.kind != "building") or not w.is_enemy(fid, int(t.owner)):
		return null
	if not Fog.entity_visible(w, fid, t):
		return null
	if s != null and not can_target(s, t):
		return null
	return t


## Nearest visible enemy within radius of e (ties -> lower id). Returns the entity dict or null.
## Searches enemy-owner buckets in rings around e and stops once no closer bucket can exist.
static func find_target(w: SimWorld, e: Dictionary, radius: float, grid: Dictionary, blds: Array):
	var fid := int(e.owner)
	var p: Vector2 = e.pos
	var r2 := radius * radius
	var best = null
	var best_d := INF
	var best_id := 0
	var s := stats(e)
	var aa: bool = s.aa
	var mr: float = s.min_range
	var mr2 := mr * mr
	var vis := PackedByteArray()
	if w.fog.has(fid):
		vis = w.fog[fid].visible
	var mw := int(w.map.w)
	var nvis := vis.size()
	var enemy_grids := []
	for o in grid:
		if w.is_enemy(fid, int(o)):
			enemy_grids.append(grid[o])
	if not enemy_grids.is_empty():
		var bx := int(floor(p.x / BUCKET))
		var by := int(floor(p.y / BUCKET))
		var kmax := int(ceil(radius / BUCKET)) + 1
		for k in range(0, kmax + 1):
			if k >= 2:
				var lim := float(k - 1) * BUCKET
				if lim * lim > best_d or lim * lim > r2:
					break
			for yy in range(by - k, by + k + 1):
				var edge_row := yy == by - k or yy == by + k
				var step := 1 if edge_row else 2 * k
				var xx := bx - k
				while xx <= bx + k:
					var key := xx + yy * GRID_STRIDE
					for g in enemy_grids:
						var arr = g.get(key)
						if arr == null:
							continue
						for c in arr:
							var cp: Vector2 = c.pos
							var d2 := p.distance_squared_to(cp)
							if d2 > r2:
								continue
							var cid := int(c.id)
							if d2 > best_d or (d2 == best_d and cid > best_id):
								continue
							var vi := floori(cp.y) * mw + floori(cp.x)
							if vi < 0 or vi >= nvis or vis[vi] != 1 or not w.entities.has(cid):
								continue
							if Fog.concealed(w, fid, c):
								continue  # G2: infantry hidden in forest (A2)
							if (not aa and bool(stats(c).is_air)) or d2 < mr2:
								continue  # G3a: air needs anti_air; artillery min_range
							best = c
							best_d = d2
							best_id = cid
					if k == 0:
						break
					xx += step
	for b in blds:
		if not w.is_enemy(fid, int(b.owner)):
			continue
		var d := dist_to(p, b)
		var d2 := d * d
		if d2 > r2 or d2 < mr2:
			continue
		var bid := int(b.id)
		if d2 > best_d or (d2 == best_d and bid > best_id):
			continue
		if not w.entities.has(bid) or not Fog.entity_visible(w, fid, b):
			continue
		best = b
		best_d = d2
		best_id = bid
	return best


## Target search dispatch: native-backed when this tick's RtsGrid holds e, else find_target().
static func _find(w: SimWorld, e: Dictionary, radius: float, grid: Dictionary, blds: Array):
	var ng = w.cache.get("combat_ng")
	if ng == null:
		return find_target(w, e, radius, grid, blds)
	var si = ng.idx.get(int(e.id))   # null for shooters outside the grid (towers): exact scan below
	var s := stats(e)
	var aa: bool = s.aa
	var fid := int(e.owner)
	var p: Vector2 = e.pos
	var r2 := radius * radius
	var mr: float = s.min_range
	var mr2 := mr * mr
	var vis := PackedByteArray()
	if w.fog.has(fid):
		vis = w.fog[fid].visible
	var mw := int(w.map.w)
	var best = null
	var best_d := INF
	var best_id := 0
	var rg = ng.grid
	var cand := -1
	var pv = ng.pre.get(int(e.id))
	if si == null:
		cand = -2          # not in the grid: no nearest query, go straight to the exact scan
	elif pv != null and is_equal_approx(float(pv.y), radius):
		cand = int(pv.x)   # this tick's batched answer (same grid, same query)
	else:
		var res: PackedInt32Array = rg.nearest_enemy_batch(PackedInt32Array([int(si)]), PackedFloat32Array([radius]), PackedInt32Array([0 if aa else 1]))
		cand = res[0]
	if cand >= 0 or cand == -2:
		var c = w.entities.get(cand) if cand >= 0 else null
		var d2 := INF
		if c != null:
			d2 = p.distance_squared_to(Vector2(c.pos))
		if c != null and _cand_ok(w, fid, c, d2, r2, mr2, aa, vis, mw):
			best = c
			best_d = d2
			best_id = cand
		else:
			# the nearest raw candidate is not a legal target: exact scan of everything in range
			for cid in rg.query_radius(p, radius):
				var c2 = w.entities.get(cid)
				if c2 == null or not w.is_enemy(fid, int(c2.owner)):
					continue
				var dd := p.distance_squared_to(Vector2(c2.pos))
				if dd > best_d or (dd == best_d and cid > best_id):
					continue
				if _cand_ok(w, fid, c2, dd, r2, mr2, aa, vis, mw):
					best = c2
					best_d = dd
					best_id = cid
	# enemy buildings of fid, filtered once per tick (PERF4-2): [b, x0, y0, x1, y1]
	var ebs: Dictionary = ng.eb
	var eb = ebs.get(fid)
	if eb == null:
		eb = []
		for b in blds:
			if w.is_enemy(fid, int(b.owner)):
				var o: Vector2i = b.cell
				var sz := float(b.size)
				eb.append([b, float(o.x), float(o.y), float(o.x) + sz, float(o.y) + sz])
		ebs[fid] = eb
	for q in eb:
		var b: Dictionary = q[0]
		var qx := clampf(p.x, q[1], q[3])
		var qy := clampf(p.y, q[2], q[4])
		var d := p.distance_to(Vector2(qx, qy))
		var d2b := d * d
		if d2b > r2 or d2b < mr2:
			continue
		var bid := int(b.id)
		if d2b > best_d or (d2b == best_d and bid > best_id):
			continue
		if not w.entities.has(bid) or not Fog.entity_visible(w, fid, b):
			continue
		best = b
		best_d = d2b
		best_id = bid
	return best


## The per-candidate filters of find_target (range, visible cell, alive, concealment, air, min_range).
static func _cand_ok(w: SimWorld, fid: int, c: Dictionary, d2: float, r2: float, mr2: float, aa: bool, vis: PackedByteArray, mw: int) -> bool:
	if d2 > r2 or d2 < mr2:
		return false
	var cp: Vector2 = c.pos
	var vi := floori(cp.y) * mw + floori(cp.x)
	if vi < 0 or vi >= vis.size() or vis[vi] != 1 or not w.entities.has(int(c.id)):
		return false
	if Fog.concealed(w, fid, c):
		return false
	return aa or not bool(stats(c).is_air)


static func _scan_due(w: SimWorld, e: Dictionary, period: int) -> bool:
	return (w.tick + int(e.id)) % period == 0


## Keeps the current target if still valid within radius. Rescans on this shooter's stagger slot
## (every SCAN_EVERY ticks; every SCAN_EVERY_ENGAGED while the target is already in weapon range),
## or immediately when the tracked target just became invalid.
static func _pick(w: SimWorld, e: Dictionary, radius: float, grid: Dictionary, blds: Array):
	if _no_search:
		return null  # REDUCED unit: no enemy can be within radius (Tiers contact bound)
	var s := stats(e)
	var cur = _valid_target(w, int(e.owner), int(e.target), s)
	if cur != null:
		var d := dist_to(e.pos, cur)
		if d > radius or d < float(s.min_range):
			cur = null
		elif d <= float(stats(e).range):
			if not _scan_due(w, e, SCAN_EVERY_ENGAGED):
				return cur
		elif not _scan_due(w, e, SCAN_EVERY):
			return cur
	elif int(e.target) < 0 and not _scan_due(w, e, SCAN_EVERY):
		return null  # nothing tracked: wait for this shooter's scan slot
	if SimIndex.profiling:
		var t0 := Time.get_ticks_usec()
		var r = _find(w, e, radius, grid, blds)
		SimIndex.pt("cmb.find", t0)
		return r
	return _find(w, e, radius, grid, blds)


static func _unit_tick(w: SimWorld, e: Dictionary, grid: Dictionary, blds: Array) -> void:
	if e.get("broken", false):
		e.target = -1  # G2 (A2): broken units never acquire, chase or fire (morale.gd rallies them)
		return
	var tgt := int(e.target)
	# fast paths (perf): a stationary shooter that is reloading at a live target has nothing to
	# decide until its reload is nearly done; an untargeted idle/hold unit waits for its scan slot.
	if tgt >= 0:
		if not e.moving and int(e.get("cd_ticks", 0)) > 1 and w.entities.has(tgt):
			return
	elif not e.moving and (w.tick + int(e.id)) % SCAN_EVERY != 0:
		var ot0 = e.order.type
		if ot0 == "idle" or ot0 == "hold":
			return
	var sv = _stats.get(e.def)
	var s: Dictionary = sv if sv != null else stats(e)
	if s.weapon == "":
		return
	var ot := String(e.order.get("type", "idle"))
	# PERF4-2 fast paths (exact: they skip only calls that cannot change anything)
	if tgt < 0 and ot != "attack" and ot != "idle" and ot != "hold" and ot != "attack_move" 			and w.tick - int(e.get("last_hit_tick", -100000)) > RETURN_FIRE_TICKS:
		return  # move/other orders only return fire, and nothing hit it recently
	if tgt < 0 and ot == "attack_move" and e.moving and not s.builder and (w.tick + int(e.id)) % SCAN_EVERY != 0 			and not e.order.get("engaged", false):
		return  # marching, nothing tracked, not its scan slot: _pick would return null and change nothing
	if ot == "attack":
		_attack_order(w, e, s)
		return
	if s.builder:
		_return_fire(w, e, s)
		if ot == "attack_move" and not e.moving:
			e.order = {"type": "idle"}
		return
	match ot:
		"idle":
			var t = _pick(w, e, _search_r(s), grid, blds)
			if t == null:
				if int(e.target) >= 0:
					e.target = -1
					if e.moving:
						Movement.stop_path(e)  # was chasing, lost it
				return
			_engage(w, e, s, t, true)
		"hold":
			var t = _pick(w, e, s.range, grid, blds)
			if t == null:
				e.target = -1
				return
			e.target = int(t.id)
			_fire(w, e, s, t)
		"attack_move":
			var t = _pick(w, e, _search_r(s), grid, blds)
			if t != null:
				e.order.engaged = true
				_engage(w, e, s, t, true)
				return
			e.target = -1
			if e.order.get("engaged", false):
				e.order.engaged = false
				if not Movement.order_path(w, e, e.order.target):
					e.order = {"type": "idle"}
			elif not e.moving:
				e.order = {"type": "idle"}  # arrived
		_:
			_return_fire(w, e, s)


static func _return_fire(w: SimWorld, e: Dictionary, s: Dictionary) -> void:
	var att := int(e.get("last_attacker", -1))
	if att < 0 or w.tick - int(e.get("last_hit_tick", -100000)) > RETURN_FIRE_TICKS:
		return
	var t = _valid_target(w, int(e.owner), att, s)
	if t == null or dist_to(e.pos, t) > s.range:
		return
	_fire(w, e, s, t)


static func _attack_order(w: SimWorld, e: Dictionary, s: Dictionary) -> void:
	var tid := int(e.order.get("target_id", -1))
	var t = w.entities.get(tid)
	if t == null:
		e.order = {"type": "idle"}
		e.target = -1
		Movement.stop_path(e)
		return
	if not can_target(s, t):
		e.order = {"type": "idle"}  # G3a: e.g. an AT team ordered onto a drone
		e.target = -1
		Movement.stop_path(e)
		return
	if Fog.entity_visible(w, int(e.owner), t):
		e.order.last_pos = t.pos
		e.order.lost = false
		_engage(w, e, s, t, true)
		return
	e.target = -1
	if not e.order.get("lost", false):
		e.order.lost = true
		var lp: Vector2 = e.order.get("last_pos", e.pos)
		if not Movement.order_path(w, e, lp):
			e.order = {"type": "idle"}
	elif not e.moving:
		e.order = {"type": "idle"}


static func _engage(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary, can_chase: bool) -> void:
	e.target = int(t.id)
	var d := dist_to(e.pos, t)
	var mr: float = s.min_range
	# G2 (A2): in range but the line of fire crosses a ridge -> keep closing (chase) instead.
	# G3a: indirect fire ignores the ridge check but needs d >= min_range.
	if d <= s.range and d >= mr and (bool(s.indirect) or Damage.line_clear(w, e.pos, t.pos)):
		if e.moving:
			Movement.stop_path(e)
		_fire(w, e, s, t, true)  # line of fire just checked (positions unchanged since)
	elif can_chase:
		var tp: Vector2 = t.pos
		if d < mr:
			# too close for indirect fire: back away along target -> shooter
			var away: Vector2 = Vector2(e.pos) - tp
			if away.length() < 0.01:
				away = Vector2(1, 0)
			tp = tp + away.normalized() * (mr + 1.0)
		var last_goal: Vector2 = e.get("chase_goal", Vector2(-1000, -1000))
		var need: bool = not e.moving or (w.tick - int(e.get("chase_tick", -100000)) >= CHASE_REPATH_TICKS and tp.distance_to(last_goal) > 1.0)
		if need:
			e.chase_tick = w.tick
			e.chase_goal = tp
			Movement.order_path(w, e, tp)


static func _tower_tick(w: SimWorld, b: Dictionary, grid: Dictionary, blds: Array) -> void:
	var s := stats(b)
	if s.weapon == "":
		return
	var t = _pick(w, b, s.range, grid, blds)
	if t == null:
		b.target = -1
		return
	b.target = int(t.id)
	_fire(w, b, s, t)


static func _fire(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary, los_ok := false) -> void:
	if _cd(e) > 0:
		return
	if Status.can_fire(w, e) != "":
		return
	var indirect: bool = s.indirect
	if not indirect and not los_ok and not Damage.line_clear(w, e.pos, t.pos):
		return
	if float(s.min_range) > 0.0 and dist_to(e.pos, t) < float(s.min_range):
		return
	# --- G3b STG4 EW hook: jammed shooters deal Status.damage_mult x damage (s is a shared cache: copy)
	var dm := Status.damage_mult(w, e)
	if dm != 1.0:
		s = s.duplicate()
		s.damage = float(s.damage) * dm
	# --- end G3b STG4 hook
	var cd := maxi(roundi(float(s.cooldown) * SimWorld.TICK_RATE), 1)
	e.cd_ticks = cd
	e.cooldown = float(cd) / SimWorld.TICK_RATE
	var hit := w.rng.chance(float(s.accuracy) * Status.accuracy_mult(w, e))
	var from: Vector2 = e.pos
	var to: Vector2 = t.pos
	if not hit and not bool(s.get("guided", false)):  # G3b STG4: guided fire never scatters
		var disp := 1.5 if indirect else 0.6
		to += Vector2(w.rng.randf_range(-disp, disp), w.rng.randf_range(-disp, disp))
	if e.kind == "unit":
		e.firing = FIRING_HINT_TICKS
		e.facing = snappedf((to - from).angle(), Q)
	w.emit("ShotFired", {"shooter": int(e.id), "target": int(t.id), "weapon": s.weapon, "hit": hit, "from": from, "to": to, "indirect": indirect})
	if e.kind == "unit":
		e.last_fired_tick = w.tick  # G2 (A2): firing reveals forest-concealed infantry for 60 ticks
		Supply.on_shot(w, e)
	if indirect:
		_splash(w, e, s, to)
		return
	Damage.apply_hit(w, e, t, s, hit)  # G2 pipeline: armor facing, cover, components, suppression


## G3a artillery impact: every ground unit and building within s.splash of `at` (any owner, the
## shooter's allies included) takes damage x (1 - 0.5 * d / splash) through the G2 pipeline, in id
## order. Nothing in the radius: near-miss suppression only.
static func _splash(w: SimWorld, e: Dictionary, s: Dictionary, at: Vector2) -> void:
	var rad: float = maxf(float(s.splash), 0.01)
	var hits := {}   # id -> distance
	var ng = w.cache.get("combat_ng")
	if ng != null:
		for cid in ng.grid.query_radius(at, rad):
			var c = w.entities.get(cid)
			if c == null or bool(stats(c).is_air):
				continue
			if bool(s.get("guided", false)) and w.is_ally(int(e.owner), int(c.owner)):
				continue  # G3b STG4: guided splash spares friendlies
			hits[int(cid)] = at.distance_to(Vector2(c.pos))
	var grid: Dictionary = {} if ng != null else w.cache.get("combat_grid", {})
	var x0 := floori((at.x - rad) / BUCKET)
	var x1 := floori((at.x + rad) / BUCKET)
	var y0 := floori((at.y - rad) / BUCKET)
	var y1 := floori((at.y + rad) / BUCKET)
	for o in grid:
		var g: Dictionary = grid[o]
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				var arr = g.get(xx + yy * GRID_STRIDE)
				if arr == null:
					continue
				for c in arr:
					if bool(stats(c).is_air):
						continue
					if bool(s.get("guided", false)) and w.is_ally(int(e.owner), int(c.owner)):
						continue  # G3b STG4: guided splash spares friendlies
					var d := at.distance_to(Vector2(c.pos))
					if d <= rad:
						hits[int(c.id)] = d
	for b in w.cache.get("combat_blds", []):
		if bool(s.get("guided", false)) and w.is_ally(int(e.owner), int(b.owner)):
			continue  # G3b STG4: guided splash spares friendlies
		var d := dist_to(at, b)
		if d <= rad:
			hits[int(b.id)] = d
	if hits.is_empty():
		var sup: Dictionary = Content.rules().get("suppression", {})
		Damage.near_miss(w, int(e.owner), at, float(sup.get("per_near_miss", 8)))
		return
	var ids := hits.keys()
	ids.sort()
	for id in ids:
		var v = w.entities.get(id)
		if v == null:
			continue
		var s2 := s.duplicate()
		s2.damage = float(s.damage) * (1.0 - 0.5 * float(hits[id]) / rad)
		Damage.apply_hit(w, e, v, s2, true)


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if String(cmd.type) != "attack":
		return "Unknown combat command."
	var fid := int(cmd.issuer)
	var t = w.entities.get(int(cmd.get("target_id", -1)))
	if t == null:
		return "Target not visible."
	if t.kind == "structure":
		if String(t.get("state", "")) == "ruined":
			return "The bridge is already destroyed."
		return "" if Fog.is_visible(w, fid, t.pos) else "Target not visible."
	if t.kind != "unit" and t.kind != "building":
		return "That is not a valid attack target."
	if int(t.owner) == fid:
		return "Cannot attack your own forces."
	if not w.is_enemy(fid, int(t.owner)):
		return "That is not a valid attack target."
	if not Fog.entity_visible(w, fid, t):
		return "Target not visible."
	var armed := false
	for id in cmd.get("unit_ids", []):
		var e = w.entities.get(int(id))
		if e != null and stats(e).weapon != "":
			armed = true
			if can_target(stats(e), t):
				return ""
	return "Selected units cannot engage aircraft." if armed else "Selected units have no weapons."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var tid := int(cmd.target_id)
	var t: Dictionary = w.entities[tid]
	for id in cmd.get("unit_ids", []):
		var e = w.entities.get(int(id))
		if e == null or stats(e).weapon == "" or not can_target(stats(e), t):
			continue
		Tiers.promote(e, w)  # G3b PERF4: an explicit attack order is always FULL tier (joins the FULL list now)
		e.order = {"type": "attack", "target_id": tid, "last_pos": t.pos, "lost": false}
		e.target = tid
		e.chase_tick = -100000
