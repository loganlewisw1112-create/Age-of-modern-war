extends RefCounted
## Per-def-flag unit subsets (owner: PERF5, G3b scale). Preload it; no class_name.
##   const Subsets = preload("res://sim/systems/unit_subsets.gd")
##   for e in Subsets.units(w, Subsets.GATHERER): ...
## Why: construction / gather / repair / status used to scan all of w.entities every tick to find
## the few units whose order they own. Only units whose DEF has the flag can ever hold that order
## (build/assist_build -> can_build, gather -> can_gather, repair -> can_build or can_repair, the
## command validators enforce it), so each system now walks only its own subset.
## Rules (same contract as sim_index.gd):
## - Lists hold entity ids in ascending id order (= w.entities order), so iteration order and
##   therefore state_hash are unchanged. A cache (w.cache.unit_subsets), never saved.
## - New entities (ids >= the stored next_id) are appended incrementally; destroyed ones are
##   dropped when the list is next read. A full rebuild runs when the cache is missing or when
##   entities appeared without a new id (tests that insert entities by hand).
## - Entity kind and def never change after spawn (checked 2026-10-23: no code assigns e.def).

const SimIndex = preload("res://sim/systems/sim_index.gd")

const BUILDER := 0    # can_build
const GATHERER := 1   # can_gather
const REPAIRER := 2   # can_build or can_repair
const EW := 3         # ew_radius > 0
const SUPPLY := 4     # is_supply (logistics trucks)
const COUNT := 5


## Bit mask of the subsets a unit def belongs to (cached per world: content can differ per test).
static func _mask(st: Dictionary, def_id: String) -> int:
	var m = st.defs.get(def_id)
	if m != null:
		return int(m)
	var d := Content.unit(def_id)
	var v := 0
	var cb := bool(d.get("can_build", false))
	if cb:
		v |= 1 << BUILDER
	if bool(d.get("can_gather", false)):
		v |= 1 << GATHERER
	if cb or bool(d.get("can_repair", false)):
		v |= 1 << REPAIRER
	if float(d.get("ew_radius", 0)) > 0.0:
		v |= 1 << EW
	if bool(d.get("is_supply", false)):
		v |= 1 << SUPPLY
	st.defs[def_id] = v
	return v


static func _add(st: Dictionary, e: Dictionary) -> void:
	var m := _mask(st, String(e.def))
	if m == 0:
		return
	var lists: Array = st.lists
	for k in COUNT:
		if m & (1 << k):
			(lists[k] as Array).append(int(e.id))


static func _state(w: SimWorld) -> Dictionary:
	var st = w.cache.get("unit_subsets")
	var nid := int(w.next_id)
	if st == null or w.entities.size() > int(st.known) + nid - int(st.next_id):
		var defs: Dictionary = st.defs if st != null else {}
		st = {"next_id": nid, "known": w.entities.size(), "defs": defs, "lists": []}
		for k in COUNT:
			st.lists.append([])
		for e in SimIndex.of(w, "unit"):
			if SimIndex.alive(w, e):
				_add(st, e)
		w.cache["unit_subsets"] = st
		return st
	var from := int(st.next_id)
	if nid > from:
		for id in range(from, nid):
			var e = w.entities.get(id)
			if e != null and e.kind == "unit":
				_add(st, e)
		st.known = int(st.known) + nid - from
		st.next_id = nid
	return st


## Live units of one subset, ascending id. The returned array is fresh (safe to iterate while
## the world changes); callers that destroy or spawn mid-loop still re-check w.entities.has().
## PERF10K (cargo fix): an id missing from w.entities is skipped, not dropped at once: a unit
## loaded into a transport leaves w.entities and comes back with the same id, and must still be
## listed then (same rule as sim_index.gd). Missing ids are dropped only when they pass 1/4 of
## the list; st.known is then reset to the live count, so a unit that returns after that is
## seen by the size check in _state() and triggers a full rebuild.
static func units(w: SimWorld, which: int) -> Array:
	var st := _state(w)
	var ids: Array = st.lists[which]
	var ents: Dictionary = w.entities
	var out := []
	for id in ids:
		var e = ents.get(id)
		if e != null:
			out.append(e)
	var gone := ids.size() - out.size()
	if gone > 0 and gone * 4 > ids.size():
		var keep := []
		for e in out:
			keep.append(int(e.id))
		st.lists[which] = keep
		st.known = ents.size()
	return out


## Def-level membership test without touching the lists (e.g. for a unit dict in hand).
static func def_has(w: SimWorld, def_id: String, which: int) -> bool:
	return (_mask(_state(w), def_id) & (1 << which)) != 0
