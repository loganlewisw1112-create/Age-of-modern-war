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
## Determinism: tiers are recomputed every RECOMPUTE_EVERY ticks at the start of the tick (first
## system: Economy) from the sim state alone (never the camera) and stored on the entity
## (e.tier, saved with it), so a save loaded mid-period behaves exactly like the original run.
## Switches: Tiers.force_off (process-wide; tests/bench) or w.tiers_enabled = false (if present).

const SimIndex = preload("res://sim/systems/sim_index.gd")

const FULL := 0
const REDUCED := 1
const RECOMPUTE_EVERY := 8          # closing distance over this period is in bucket_size()
const STRIDE := 4            # Movement / Supply: REDUCED units every STRIDE ticks
const SCAN_STRIDE := 8       # Combat: REDUCED units every SCAN_STRIDE ticks
const MIN_CONTACT := 14.0    # tiles (brief)
const HIT_FULL_TICKS := 100
const KSTRIDE := 4096

static var force_off := false
static var move_stride := false  # OFF until N1 fixes the stride bias (PERF4 A/B, 2026-10-24): true = REDUCED units move every STRIDE ticks
static var _bucket := -1.0
static var _contact := -1.0


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
					r = maxf(r, float(Content.weapon(wid).get("range", 0)))
		_contact = r
	return _contact


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
		_bucket = ceilf(contact_radius() + big * 0.75 + closing + 1.0)
	return _bucket


static func enabled(w) -> bool:
	if force_off:
		return false
	var v = w.get("tiers_enabled") if w != null else null
	return v == null or bool(v)


## Called once at the start of every tick (Economy.tick). On recompute ticks it rebuilds the
## shared index and every unit's tier in one pass; otherwise it only refreshes the index.
static func begin_tick(w: SimWorld) -> void:
	if w.tick % RECOMPUTE_EVERY != 0:
		SimIndex.get_index(w)
		return
	var idx := SimIndex.rebuild(w)
	var units: Array = idx.kinds.get("unit", [])
	if not enabled(w):
		for e in units:
			if e.has("tier"):
				e.erase("tier")
		return
	var bs := bucket_size()
	var team := {}       # owner -> team bit
	for fid in w.factions:
		team[int(fid)] = 1 << posmod(int(w.factions[fid].get("team", fid)), 30)
	var occ := {}        # bucket key -> OR of team bits present
	for b in idx.kinds.get("building", []):
		var bit = team.get(int(b.owner))
		if bit == null:
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
		var bit = team.get(int(e.owner))
		if bit == null:
			ubit[i] = 0
			continue
		var p: Vector2 = e.pos
		var key := floori(p.x / bs) + floori(p.y / bs) * KSTRIDE
		ukey[i] = key
		ubit[i] = int(bit)
		occ[key] = int(occ.get(key, 0)) | int(bit)
	var near := {}       # bucket key -> OR over the 3x3 neighbourhood
	for i in units.size():
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
					and String(e.order.get("type", "")) != "attack":
				t = REDUCED
		if t == REDUCED:
			if int(e.get("tier", 0)) != REDUCED:
				e.tier = REDUCED
		elif e.has("tier"):
			e.erase("tier")


static func is_reduced(e: Dictionary) -> bool:
	return int(e.get("tier", 0)) == REDUCED


## Promote a unit to FULL now (explicit orders, hits). Safe at any time.
static func promote(e: Dictionary) -> void:
	if e.has("tier"):
		e.erase("tier")


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
