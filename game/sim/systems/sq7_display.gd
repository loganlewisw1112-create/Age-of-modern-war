extends RefCounted
## G7 PERF7E (orch.ruling on PERF7D need seq 2210, board seq 2322, option A): UNHASHED display table of the SQUAD7
## display fields, so the render snapshot reads one small table instead of five keys on every unit.
##
##   w.cache.sq7d  = {id: [bits, sector_deg, hull_deg, e, id, k]} for every unit with a non-null e.f7_hd, e.gait or e.f7_hb
##                   (and, after a rebuild, units carried in a cargo list). bits = RenderSnap's SQ7_* bits WITHOUT
##                   SQ7_BACK (order.bk changes with every order write, so it is checked live for the few candidates
##                   below); sector / hull = float(e.f7_hd) / float(e.f7_hb), 0.0 when absent; e = the entity dict
##                   (an entry of a unit taken out of w.entities as cargo survives until its reinsert; a dead one is dropped);
##                   k = its index in the last snapshot's ids (a hint RenderSnap checks before it searches).
##   w.cache.sq7bk = {id: 1}: units whose order got bk outside SquadAI.fall_back (that one calls Combat.note_bk, so
##                   w.sys_state.combat_bk already lists it). RenderSnap checks order.bk live for both sets.
##
## Writers call put(w, e) right after they set / erase f7_hd, gait, f7_hb or f7_clr, and note_bk(w, e) after they put
## bk into an order. Both are no-ops while the table does not exist: RenderSnap builds it with a full scan (rebuild)
## on its first snapshot of a world (fresh match, load, dropped cache), so a headless sim never pays for it.
## w.cache is never saved or hashed: nothing here can move a state hash.

## false until every writer calls put / note_bk: RenderSnap then rebuilds the table on every snapshot (correct, slower)
const HOOKED := true
const KEY := "sq7d"
const KEY_BK := "sq7bk"
const KEY_DIRTY := "sq7dirty"   # {id: 1} entries changed since RenderSnap's last snapshot (its incremental path)
const KEY_MEMO := "sq7m"        # RenderSnap: [ids, sq7f, sq7a, sq7h] of its last snapshot, before SQ7_BACK
const KEY_TICK := "sq7t"        # RenderSnap: tick of its last snapshot (a gap of more than one tick rebuilds)
# same values as RenderSnap.SQ7_* (tests/test_sq7disp.gd checks they agree)
const SQ7_ON := 1
const SQ7_SECTOR := 2
const SQ7_STACK := 8
const SQ7_ENTRY := 16
const SQ7_HULL := 32
const SQ7_GAIT_SHIFT := 6
const N_GAITS := 4


## Re-derives unit e's entry (call after any write of f7_hd / gait / f7_hb / f7_clr).
static func put(w, e: Dictionary) -> void:
	var t = w.cache.get(KEY)
	if t != null and _put(t, e):
		var d = w.cache.get(KEY_DIRTY)
		if d != null:
			d[int(e.id)] = 1


## Unit e's order just got bk (outside SquadAI.fall_back): RenderSnap checks it live from now on.
static func note_bk(w, e: Dictionary) -> void:
	var t = w.cache.get(KEY_BK)
	if t != null:
		t[int(e.id)] = 1


## The entry of unit e, from its fields; the same decisions RenderSnap's per-unit loop took before PERF7E.
## Returns true when the entry changed.
static func _put(t: Dictionary, e: Dictionary) -> bool:
	var hd = e.get("f7_hd")
	var gt = e.get("gait")
	var hb = e.get("f7_hb")
	var b := 0
	var sa := 0.0
	var sh := 0.0
	if hd != null:
		b = SQ7_ON | SQ7_SECTOR
		sa = float(hd)
		var clr = e.get("f7_clr")
		if clr != null:
			if int(clr) == 1:
				b |= SQ7_STACK
			elif int(clr) == 2:
				b |= SQ7_ENTRY
	elif gt != null or hb != null:
		b = SQ7_ON
	if b != 0:
		if gt != null:
			var gi := int(gt)
			if gi > 0 and gi < N_GAITS:
				b |= gi << SQ7_GAIT_SHIFT
		if hb != null:
			b |= SQ7_HULL
			sh = float(hb)
	var id := int(e.id)
	if b == 0:
		return t.erase(id)
	var r = t.get(id)
	if r == null:
		t[id] = [b, sa, sh, e, id, 0]
		return true
	if int(r[0]) == b and float(r[1]) == sa and float(r[2]) == sh:
		r[3] = e
		return false
	r[0] = b
	r[1] = sa
	r[2] = sh
	r[3] = e
	return true


## Full scan: every unit in w.entities plus the units inside cargo lists (nested carriers too). Stores and returns
## the table; also seeds w.cache.sq7bk with every unit whose order carries bk.
static func rebuild(w) -> Dictionary:
	var t := {}
	var bk := {}
	for e in w.entities.values():
		if e.kind == "unit":
			_scan(t, bk, e, 0)
	w.cache[KEY] = t
	w.cache[KEY_BK] = bk
	w.cache[KEY_DIRTY] = {}
	w.cache.erase(KEY_MEMO)
	return t


## Re-seeds w.cache.sq7bk with every unit (w.entities) whose order carries bk.
static func rescan_bk(w) -> void:
	var bk = w.cache.get(KEY_BK)
	if bk == null:
		return
	for e in w.entities.values():
		if e.kind == "unit":
			var od = e.get("order")
			if od is Dictionary and (od as Dictionary).has("bk"):
				bk[int(e.id)] = 1


static func _scan(t: Dictionary, bk: Dictionary, e: Dictionary, depth: int) -> void:
	if e.has("f7_hd") or e.has("gait") or e.has("f7_hb"):
		_put(t, e)
	var od = e.get("order")
	if od is Dictionary and (od as Dictionary).has("bk"):
		bk[int(e.id)] = 1
	var cg = e.get("cargo")
	if cg is Array and depth < 4:
		for u in cg:
			if u is Dictionary and String((u as Dictionary).get("kind", "")) == "unit":
				_scan(t, bk, u, depth + 1)


## Index in ids[0..n) of a table id that ids.bsearch did not find: -1 for a unit outside w.entities (cargo: kept;
## dead: appended to `dead` for the caller to drop), else a linear search (only if entity order ever broke ascending ids).
static func index_slow(w, ids: PackedInt32Array, n: int, sid: int, r: Array, dead: Array) -> int:
	var e = w.entities.get(sid)
	if e == null:
		if float((r[3] as Dictionary).get("hp", 0.0)) <= 0.0:
			dead.append(sid)
		return -1
	if not is_same(e, r[3]):   # a different dict under this id (never expected): re-derive from the live one
		_put(w.cache[KEY], e)
		w.cache.erase(KEY_MEMO)
		if not (w.cache[KEY] as Dictionary).has(sid):
			return -1
	var k := ids.find(sid)
	return k if k >= 0 and k < n else -1


## Test / debug: number of units whose table entry differs from a fresh full scan (0 = in sync).
static func verify(w) -> int:
	var t = w.cache.get(KEY)
	if t == null:
		return 0
	var f := {}
	var bk := {}
	for e in w.entities.values():
		if e.kind == "unit":
			_scan(f, bk, e, 0)
	var bad := 0
	for id in f:
		var a = t.get(id)
		var b: Array = f[id]
		if a == null or int(a[0]) != int(b[0]) or float(a[1]) != float(b[1]) or float(a[2]) != float(b[2]):
			bad += 1
	for id in t:
		if not f.has(id) and w.entities.has(id):
			bad += 1
	return bad
