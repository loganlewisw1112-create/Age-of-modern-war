extends RefCounted
## Shared per-tick entity index (owner: PERF4, G3b scale). Preload it; no class_name.
##   const SimIndex = preload("res://sim/systems/sim_index.gd")
##   for e in SimIndex.of(w, "building"):
##       if not SimIndex.alive(w, e): continue
## Why: at 10,000 units one GDScript pass over w.entities costs ~5-9 ms on the owner's PC, and
## every system used to make its own pass (several per tick). The index makes ONE pass and hands
## each system only the kind it needs, in the same order as w.entities (ascending id).
## Rules:
## - Lists are a cache (w.cache.sim_index, never saved); after a load they are rebuilt from state.
## - A full rebuild runs when missing or every REBUILD_EVERY ticks (Tiers drives it, same pass).
## - Between rebuilds, entities spawned since (ids >= built next_id) are appended in id order, so
##   new entities are never missed. Destroyed entities may still be listed: callers skip them with
##   alive(w, e). Entity kind and owner never change after spawn (checked 2026-10-23).

const REBUILD_EVERY := 4

## Sub-phase profiler (bench only; off by default, never touches sim state).
static var profiling := false
static var prof := {}   # label -> [usec total, calls]


static func pt(label: String, t0: int) -> int:
	var t := Time.get_ticks_usec()
	var a = prof.get(label)
	if a == null:
		prof[label] = [t - t0, 1]
	else:
		a[0] += t - t0
		a[1] += 1
	return t


static func _empty(w: SimWorld) -> Dictionary:
	return {"tick": w.tick, "next_id": int(w.next_id), "kinds": {}, "known": w.entities.size(), "uown": {}, "uids": PackedInt32Array()}


## Full rebuild from w.entities (one pass). Returns the index.
static func rebuild(w: SimWorld) -> Dictionary:
	var idx := _empty(w)
	var kinds: Dictionary = idx.kinds
	var uown: Dictionary = idx.uown
	var uids := PackedInt32Array()   # G5 CORE10K: ids parallel to kinds.unit
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		var k: String = e.kind
		var arr = kinds.get(k)
		if arr == null:
			kinds[k] = [e]
		else:
			arr.append(e)
		if k == "unit":
			uids.append(int(id))
			var ua = uown.get(e.owner)
			if ua == null:
				uown[e.owner] = [e]
			else:
				ua.append(e)
	idx.uids = uids
	w.cache["sim_index"] = idx
	return idx


## The index for this tick: appends entities spawned since the last refresh.
static func get_index(w: SimWorld) -> Dictionary:
	var idx = w.cache.get("sim_index")
	if idx == null or w.entities.size() > int(idx.known) + int(w.next_id) - int(idx.next_id):
		return rebuild(w)  # missing, or entities appeared without a new id (tests): full pass
	var nid := int(w.next_id)
	var from := int(idx.next_id)
	if nid > from:
		var kinds: Dictionary = idx.kinds
		for id in range(from, nid):
			var e = w.entities.get(id)
			if e == null:
				continue
			var k: String = e.kind
			var arr = kinds.get(k)
			if arr == null:
				kinds[k] = [e]
			else:
				arr.append(e)
			if k == "unit":
				var uu: PackedInt32Array = idx.uids
				uu.append(id)
				idx.uids = uu
				var ua = idx.uown.get(e.owner)
				if ua == null:
					idx.uown[e.owner] = [e]
				else:
					ua.append(e)
				if idx.has("full"):
					idx.full.append(e)   # Tiers lists: new units are FULL (ascending id kept)
		idx.known = int(idx.known) + nid - from
		idx.next_id = nid
	idx.tick = w.tick
	return idx


## Entities of one kind ("unit", "building", "wreck", "resource", "structure", ...).
static func of(w: SimWorld, kind: String) -> Array:
	var arr = get_index(w).kinds.get(kind)
	return arr if arr != null else []


## G5 CORE10K: entity ids parallel to of(w, "unit") (same order, same liveness rule).
static func unit_ids(w: SimWorld) -> PackedInt32Array:
	return get_index(w).uids


## Units grouped by owner (G3b PERF4-3): {owner -> [unit dicts, ascending id]}, same liveness rule.
static func units_by_owner(w: SimWorld) -> Dictionary:
	return get_index(w).uown


## Still in the world (not destroyed since the index was built)?
static func alive(w: SimWorld, e: Dictionary) -> bool:
	return w.entities.has(int(e.id))


# --- G6 PERF6: G6Hooks gate (CONTRACTS_G6 section 5.1). The call sites (combat, fog, movement,
# morale, damage) call G6Hooks only when the hook's bit is set in this tick's mask. Movement.tick
# refreshes the mask at a fixed point of every tick from G6Hooks.active(w) (a bitmask of hooks
# whose owners report they may be non-neutral) when ORCH's dispatcher has it, else every bit.
# Sites that run before Movement in a tick see a mask from an older tick and call everything
# (g6m returns G6_ALL), so skipping never depends on runtime-only state: deterministic across
# save/load and the sim thread. Runtime cache only (w.cache.g6_mask), never saved.
const G6_DMG := 1
const G6_ACC := 2
const G6_RANGE := 4
const G6_LOS := 8
const G6_SIGHT := 16
const G6_VIS := 32
const G6_SPEED := 64
const G6_PASS := 128
const G6_MORALE := 256
const G6_DESTROY := 512
const G6_SHOT := 1024   # G6 AIRDEF6 (CR 492): Combat._fire asks G6Hooks.shot_blocked (CIWS / jam fields)
const G6_ALL := 2047
## Tests/bench: false = never call a hook (the pre-G6 baseline the A/B proof compares against).
static var g6_hooks_on := true
## Tests/bench: false = ignore the owners' active mask (call every hook every time).
static var g6_skip := true
## Bench/diagnostics: >= 0 forces this mask (per-hook cost breakdown).
static var g6_mask_override := -1


## This tick's hook mask (0 when g6_hooks_on is false).
static func g6m(w: SimWorld) -> int:
	if not g6_hooks_on:
		return 0
	if g6_mask_override >= 0:
		return g6_mask_override
	if not g6_skip:
		return G6_ALL
	var c = w.cache.get("g6_mask")
	if c != null and int(c[0]) == w.tick:
		return int(c[1])
	return G6_ALL


## Called once per tick by Movement.tick with G6Hooks.active(w) (or G6_ALL).
static func g6_set(w: SimWorld, mask: int) -> void:
	w.cache["g6_mask"] = PackedInt32Array([w.tick, mask])
## Tests: an object with the G6Hooks function names (damage_mult, accuracy_mult, range_mult, los_ok,
## sight_bonus, visible_to, speed_mult, passable, morale_delta, on_destroyed) used instead of the
## dispatcher, so test_perf_g6 can prove every call site is live. null in the game.
static var g6_spy = null
static var _g6h = null


## The hook implementation the call sites use: g6_spy when a test set one, else G6Hooks.
static func g6h():
	if g6_spy != null:
		return g6_spy
	if _g6h == null:
		_g6h = load("res://sim/systems/g6_hooks.gd")   # load, not preload: no preload cycle via owners
	return _g6h
