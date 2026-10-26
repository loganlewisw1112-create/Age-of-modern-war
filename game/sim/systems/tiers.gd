extends RefCounted
## Fidelity tiers (owner: PERF4, CONTRACTS_G3b section 0). Preload it; no class_name.
##   const Tiers = preload("res://sim/systems/tiers.gd")
## FULL (e.tier absent or 0): near an enemy. Every system runs the unit every tick, as before.
## REDUCED (e.tier == 1): no enemy unit or building anywhere near. Systems run it on a stride:
##   Combat every SCAN_STRIDE ticks (cooldown catches up), Morale every 2nd update with a 2x dt,
##   Supply fuel burn every STRIDE ticks, and Movement may advance it every STRIDE ticks with a
##   STRIDE x step (move_k; CHANGE_REQUEST to N1-core, collision rules unchanged).
## Contact test (conservative, never misses): units and buildings are bucketed in squares of
## bucket_size() = contact radius (largest sight / weapon range in content, >= MIN_CONTACT)
## + half the largest footprint + the closing distance two of the fastest units cover in
## RECOMPUTE_EVERY ticks. A unit is FULL when an enemy team occupies its bucket or one of the 8
## around it. Also FULL: hit within HIT_FULL_TICKS, an explicit `attack` order, newly spawned
## (no tier yet), and promoted at once by Combat.apply_command.
## G6 (PERF6-2, ORCH decision orch.decisions A, 2026-10-25): indirect weapons count at most
## INDIRECT_CONTACT_CAP (18 tiles, the G5 maximum, b_rocket_truck) toward the contact radius, so the
## long G6 artillery (m_mass_driver 34, a_mlrs 22, a_sp_howitzer / a_howitzer_pit 20) does not inflate
## the bucket for every unit; a unit whose own indirect weapon reaches farther than the cap is always
## FULL (long_indirect), so "never misses" still holds for its acquisition. Buildings are not tiered
## (they scan every tick), so a long-range building needs no rule here. With the cap the contact radius
## is 18 again (G5). bucket_size() is floored at G5_BUCKET (36): the largest G6 footprint is 5
## (m_launch_rail) where G5's was 6 (a_airfield / b_aerodrome, shrunk to 2 by the G6 airfield rework), so
## the formula alone gives 35, which changed the flattened 2k_mixed native hash against the G5 GOLD
## (PERF6-2 A/B, 2026-10-25). A larger bucket only makes more units FULL, so the floor keeps "never
## misses" and the G5 results.
## Determinism: tiers are recomputed every RECOMPUTE_EVERY ticks at the start of the tick (first
## system: Economy) from the sim state alone (never the camera) and stored on the entity
## (e.tier, saved with it), so a save loaded mid-period behaves exactly like the original run.
## Switches: Tiers.force_off (process-wide; tests/bench) or w.tiers_enabled = false (if present).

const SimIndex = preload("res://sim/systems/sim_index.gd")

const FULL := 0
const REDUCED := 1
const RECOMPUTE_EVERY := 8          # closing distance over this period is in bucket_size()
## G3b PERF4-3: recompute (and the index rebuild) runs on tick % RECOMPUTE_EVERY == PHASE, a tick
## that carries no other periodic job (Morale: tick % 4 == 0; Fog teams: tick % 4 == 1 / 3), so the
## periodic spikes never stack on one tick (p95).
const PHASE := 6
const STRIDE := 4            # Movement / Supply: REDUCED units every STRIDE ticks
const SCAN_STRIDE := 8       # Combat: REDUCED units every SCAN_STRIDE ticks
const MIN_CONTACT := 14.0    # tiles (brief)
const INDIRECT_CONTACT_CAP := 18.0   # G6: indirect weapon range counted toward contact_radius (G5 max)
const G5_BUCKET := 36.0      # G6: bucket_size() floor = the G5 value (see the header)
const HIT_FULL_TICKS := 100
const KSTRIDE := 4096

static var force_off := false
static var move_stride := false  # OFF until N1 fixes the stride bias (PERF4 A/B, 2026-10-24): true = REDUCED units move every STRIDE ticks
static var _bucket := -1.0
static var _contact := -1.0
static var _long_ind: Dictionary = {}   # unit def -> true when its indirect weapon exceeds the cap


## Largest auto-acquisition radius any unit or building can have, at least MIN_CONTACT.
static func contact_radius() -> float:
	if _contact < 0.0:
		var r := MIN_CONTACT
		for tname in ["units", "buildings"]:
			var t: Dictionary = Content.table(tname)
			for k in t:
				var d = t[k]
				if typeof(d) != TYPE_DICTIONARY:
					continue
				r = maxf(r, float(d.get("sight", 0)))
				var wid := String(d.get("weapon", ""))
				if wid != "":
					var wd: Dictionary = Content.weapon(wid)
					var wr := float(wd.get("range", 0))
					if bool(wd.get("indirect", false)):
						wr = minf(wr, INDIRECT_CONTACT_CAP)   # G6: long indirect units are always FULL
					r = maxf(r, wr)
		_contact = r
	return _contact


## G6: true when unit def `def` carries an indirect weapon longer than INDIRECT_CONTACT_CAP. Such a
## unit is never REDUCED (its acquisition radius is outside the contact bound). Cached per def.
static func long_indirect(def) -> bool:
	var v = _long_ind.get(def)
	if v == null:
		var wid := String(Content.unit(def).get("weapon", ""))
		var wd: Dictionary = Content.weapon(wid) if wid != "" else {}
		v = bool(wd.get("indirect", false)) and float(wd.get("range", 0)) > INDIRECT_CONTACT_CAP
		_long_ind[def] = v
	return bool(v)


static func bucket_size() -> float:
	if _bucket < 0.0:
		var big := 1.0
		var vmax := 0.0
		for k in Content.table("buildings"):
			var d = Content.table("buildings")[k]
			if typeof(d) == TYPE_DICTIONARY:
				big = maxf(big, float(d.get("size", 1)))
		for k in Content.table("units"):
			var d = Content.table("units")[k]
			if typeof(d) == TYPE_DICTIONARY:
				vmax = maxf(vmax, float(d.get("speed", 0)))
		var closing := 2.0 * vmax * 1.5 * float(RECOMPUTE_EVERY) / float(SimWorld.TICK_RATE)  # x1.5: road bonus
		_bucket = maxf(G5_BUCKET, ceilf(contact_radius() + big * 0.75 + closing + 1.0))
	return _bucket


static func enabled(w) -> bool:
	if force_off:
		return false
	var v = w.get("tiers_enabled") if w != null else null
	return v == null or bool(v)


## Called once at the start of every tick (Economy.tick). On recompute ticks it rebuilds the
## shared index and every unit's tier in one pass; otherwise it only refreshes the index.
static func begin_tick(w: SimWorld) -> void:
	if w.tick % RECOMPUTE_EVERY != PHASE:
		SimIndex.get_index(w)
		return
	var t0 := Time.get_ticks_usec() if SimIndex.profiling else 0
	# G3b PERF4-3: the full index rebuild (one pass over every entity, resources included) only runs
	# once destroyed entries pass 1/8 of the lists; otherwise the appended index is kept and the
	# loops below skip destroyed entities, which gives the same lists and tiers as a rebuild.
	var idx := SimIndex.get_index(w)
	if (int(idx.known) - w.entities.size()) * 8 > int(idx.known):
		idx = SimIndex.rebuild(w)
	var ents: Dictionary = w.entities
	if SimIndex.profiling:
		t0 = SimIndex.pt("tiers.idx_rebuild", t0)
	var units: Array = idx.kinds.get("unit", [])
	var full := []
	var rslot := []
	for j in SCAN_STRIDE:
		rslot.append([])
	var newly := []
	idx.full = full
	idx.rslot = rslot
	idx.newly = newly
	if not enabled(w):
		for e in units:
			if e.has("tier"):
				e.erase("tier")
		full.append_array(units)
		return
	if not _recompute_grid(w, idx, units, full, rslot, newly):
		_recompute_dict(w, idx, units, full, rslot, newly)
	if SimIndex.profiling:
		SimIndex.pt("tiers.recompute", t0)




## The G3b recompute with dictionary buckets (any position, also off the map). _recompute_grid
## gives the same tiers and lists whenever every entity lies inside the map.
static func _recompute_dict(w: SimWorld, idx: Dictionary, units: Array, full: Array, rslot: Array, newly: Array) -> void:
	var ents: Dictionary = w.entities
	var bs := bucket_size()
	var team := {}       # owner -> team bit
	for fid in w.factions:
		team[int(fid)] = 1 << posmod(int(w.factions[fid].get("team", fid)), 30)
	var occ := {}        # bucket key -> OR of team bits present
	for b in idx.kinds.get("building", []):
		var bit = team.get(int(b.owner))
		if bit == null or not ents.has(int(b.id)):
			continue
		var o: Vector2i = b.cell
		var c := Vector2(o) + Vector2(float(b.size), float(b.size)) * 0.5
		var key := floori(c.x / bs) + floori(c.y / bs) * KSTRIDE
		occ[key] = int(occ.get(key, 0)) | int(bit)
	var ukey := PackedInt32Array()
	ukey.resize(units.size())
	var ubit := PackedInt32Array()
	ubit.resize(units.size())
	for i in units.size():
		var e: Dictionary = units[i]
		if not ents.has(int(e.id)):
			ubit[i] = -1     # destroyed since the index was built: in no list, no occupancy
			continue
		var bit = team.get(e.owner)
		if bit == null:
			ubit[i] = 0
			continue
		var p: Vector2 = e.pos
		var key := floori(p.x / bs) + floori(p.y / bs) * KSTRIDE
		ukey[i] = key
		var ib: int = bit
		ubit[i] = ib
		var ov = occ.get(key)
		occ[key] = ib if ov == null else (int(ov) | ib)
	var fmult := maxf(w.econ("fuel_use_mult"), 0.0)
	var near := {}       # bucket key -> OR over the 3x3 neighbourhood
	for i in units.size():
		if ubit[i] < 0:
			continue
		var e: Dictionary = units[i]
		var t := FULL
		if ubit[i] != 0:
			var key := ukey[i]
			var m = near.get(key)
			if m == null:
				var mm := 0
				for dy in [-KSTRIDE, 0, KSTRIDE]:
					for dx in [-1, 0, 1]:
						mm |= int(occ.get(key + dy + dx, 0))
				near[key] = mm
				m = mm
			if (int(m) & ~ubit[i]) == 0 and w.tick - int(e.get("last_hit_tick", -100000)) > HIT_FULL_TICKS \
					and String(e.order.get("type", "")) != "attack" and not _fuel_low(e, fmult) and not long_indirect(e.def):
				t = REDUCED
		if t == REDUCED:
			if int(e.get("tier", 0)) != REDUCED:
				e.tier = REDUCED
				newly.append(e)
			rslot[int(e.id) % SCAN_STRIDE].append(e)
		else:
			if e.has("tier"):
				e.erase("tier")
			full.append(e)


## PERF10K: same decisions as _recompute_dict with a padded packed bucket grid (no dictionary per
## bucket, the 3x3 neighbourhood OR computed once per bucket) and fewer dict reads per unit (the
## REDUCED checks run only for units with no enemy team nearby, in the same order). Returns false,
## having changed nothing, when an entity lies outside the map (the caller then uses the dict path).
static func _recompute_grid(w: SimWorld, idx: Dictionary, units: Array, full: Array, rslot: Array, newly: Array) -> bool:
	var ents: Dictionary = w.entities
	var bs := bucket_size()
	var gw := ceili(float(w.map.w) / bs) + 2   # one empty bucket of padding on every side
	var gh := ceili(float(w.map.h) / bs) + 2
	var fw := float(w.map.w)
	var fh := float(w.map.h)
	var team := {}
	for fid in w.factions:
		team[int(fid)] = 1 << posmod(int(w.factions[fid].get("team", fid)), 30)
	var occ := PackedInt32Array()
	occ.resize(gw * gh)
	for b in idx.kinds.get("building", []):
		var bit = team.get(int(b.owner))
		if bit == null or not ents.has(int(b.id)):
			continue
		var o: Vector2i = b.cell
		var c := Vector2(o) + Vector2(float(b.size), float(b.size)) * 0.5
		if c.x < 0.0 or c.y < 0.0 or c.x >= fw or c.y >= fh:
			return false
		var k := (floori(c.y / bs) + 1) * gw + floori(c.x / bs) + 1
		occ[k] = occ[k] | int(bit)
	var nu := units.size()
	var ukey := PackedInt32Array()
	ukey.resize(nu)
	var ubit := PackedInt32Array()
	ubit.resize(nu)
	for i in nu:
		var e: Dictionary = units[i]
		if not ents.has(int(e.id)):
			ubit[i] = -1
			continue
		var bit = team.get(e.owner)
		if bit == null:
			ubit[i] = 0
			continue
		var p: Vector2 = e.pos
		if p.x < 0.0 or p.y < 0.0 or p.x >= fw or p.y >= fh:
			return false
		var k := (floori(p.y / bs) + 1) * gw + floori(p.x / bs) + 1
		ukey[i] = k
		var ib: int = bit
		ubit[i] = ib
		occ[k] = occ[k] | ib
	var near := PackedInt32Array()
	near.resize(gw * gh)
	for y in range(1, gh - 1):
		for x in range(1, gw - 1):
			var k := y * gw + x
			near[k] = occ[k - gw - 1] | occ[k - gw] | occ[k - gw + 1] | occ[k - 1] | occ[k] | occ[k + 1] 					| occ[k + gw - 1] | occ[k + gw] | occ[k + gw + 1]
	var fmult := maxf(w.econ("fuel_use_mult"), 0.0)
	var tick := w.tick
	for i in nu:
		var ib := ubit[i]
		if ib < 0:
			continue
		var e: Dictionary = units[i]
		var t := FULL
		if ib != 0 and (near[ukey[i]] & ~ib) == 0 and tick - int(e.get("last_hit_tick", -100000)) > HIT_FULL_TICKS 				and String(e.order.get("type", "")) != "attack" and not _fuel_low(e, fmult) and not long_indirect(e.def):
			t = REDUCED
		if t == REDUCED:
			if int(e.get("tier", 0)) != REDUCED:
				e.tier = REDUCED
				newly.append(e)
			rslot[int(e.id) % SCAN_STRIDE].append(e)
		else:
			if e.has("tier"):
				e.erase("tier")
			full.append(e)
	return true


## Fuel-starved units stay FULL (orch fix 2026-10-24): a REDUCED vehicle moves STRIDE ticks at
## once, so near empty it would overshoot the point where fuel 0 stops it. A unit is "low" when
## its fuel could run out within one tier period plus one stride at its top speed (x1.5 roads).
static var _burn: Dictionary = {}   # unit def -> max fuel burn per tick (before fuel_use_mult)


static func _fuel_low(e: Dictionary, mult: float) -> bool:
	if not e.has("fuel"):
		return false
	var b = _burn.get(e.def)
	if b == null:
		var d := Content.unit(e.def)
		b = float(d.get("speed", 0)) * 1.5 / float(SimWorld.TICK_RATE) * float(d.get("fuel_per_tile", 0.0)) * maxf(float(Content.rules().get("fuel_burn_scale", 1.0)), 0.0)
		_burn[e.def] = b
	if float(b) <= 0.0 or mult <= 0.0:
		return false
	return float(e.fuel) <= float(b) * mult * float(RECOMPUTE_EVERY + STRIDE)


static func is_reduced(e: Dictionary) -> bool:
	return int(e.get("tier", 0)) == REDUCED


## Promote a unit to FULL now (explicit orders, hits). Safe at any time. With w, the unit also
## joins this period's FULL list (lists(w).full) at once.
static func promote(e: Dictionary, w: SimWorld = null) -> void:
	if e.has("tier"):
		e.erase("tier")
		if w != null:
			var idx = w.cache.get("sim_index")
			if idx != null and idx.has("full"):
				idx.full.append(e)
				idx.full_dirty = true


## The shared index with this period's tier lists (G3b PERF4-2), built at every tier recompute:
##   full:  FULL units (no tier), ascending id; units spawned or promoted since are appended
##          (full_dirty = true when an append broke the id order; units() sorts it).
##   rslot: SCAN_STRIDE arrays, REDUCED units by id % SCAN_STRIDE, ascending id. A REDUCED unit is
##          due for its stride work on the ticks where (tick + id) % stride == 0, i.e. it lives in
##          rslot[(-tick) mod SCAN_STRIDE] (stride 8) or that slot and the one 4 away (stride 4).
##   newly: units that became REDUCED at the last recompute.
## Lists may hold destroyed units (skip with w.entities.has) and units promoted since (skip
## REDUCED-slot entries whose e.tier is gone). After a load (no cache) they are rebuilt from the
## saved e.tier, so a loaded game sees the same lists as the original run.
static func lists(w: SimWorld) -> Dictionary:
	var idx := SimIndex.get_index(w)
	if not idx.has("full"):
		var full := []
		var rslot := []
		for j in SCAN_STRIDE:
			rslot.append([])
		for e in idx.kinds.get("unit", []):
			if int(e.get("tier", 0)) == REDUCED and enabled(w):
				rslot[int(e.id) % SCAN_STRIDE].append(e)
			else:
				full.append(e)
		idx.full = full
		idx.rslot = rslot
		idx.newly = []
	if idx.get("full_dirty", false):
		idx.full.sort_custom(func(a, b): return int(a.id) < int(b.id))
		idx.full_dirty = false
	return idx


## REDUCED units due on this tick for a stride (STRIDE or SCAN_STRIDE): (tick + id) % stride == 0.
static func due_reduced(w: SimWorld, stride: int) -> Array:
	var idx := lists(w)
	var rs: Array = idx.rslot
	var a := posmod(-w.tick, SCAN_STRIDE)
	if stride >= SCAN_STRIDE:
		return rs[a]
	var out := []
	var j := posmod(-w.tick, stride)
	while j < SCAN_STRIDE:
		out.append_array(rs[j])
		j += stride
	return out


## True on 1 tick in `period` for this entity (staggered by id).
static func due(w: SimWorld, e: Dictionary, period: int) -> bool:
	return (w.tick + int(e.id)) % period == 0


## Movement step multiplier for unit e this tick: 1 (FULL), STRIDE on its stride tick, 0 otherwise.
static func move_k(w: SimWorld, e: Dictionary) -> int:
	if int(e.get("tier", 0)) != REDUCED or not move_stride:
		return 1
	return STRIDE if (w.tick + int(e.id)) % STRIDE == 0 else 0


## {full, reduced} live unit counts for the perf report (w.tier_counts() forwards here).
static func counts(w: SimWorld) -> Dictionary:
	var f := 0
	var r := 0
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit":
			if int(e.get("tier", 0)) == REDUCED:
				r += 1
			else:
				f += 1
	return {"full": f, "reduced": r}
