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
