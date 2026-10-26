extends RefCounted
const Status = preload("res://sim/systems/status.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Tiers = preload("res://sim/systems/tiers.gd")
## Fog of war (owner: agent B / sim-mil). Per-faction visibility, explored cells, last-seen memory.
## Contract: docs/CONTRACTS.md section 5.
##   w.fog[fid] = {visible: PackedByteArray, explored: PackedByteArray}  (1 = yes, idx y*w+x)
##   w.memory[fid][eid] = {def, kind, owner, pos, tick}  last-seen enemy BUILDINGS
## Visible is recomputed every RECOMPUTE_EVERY ticks (and at init / tick 0) from all own units and
## buildings (built or not), as circles of radius `sight` around their cell centre. Explored is sticky.

const RECOMPUTE_EVERY := 4
const NativeCore = preload("res://sim/native_core.gd")
## G6 PERF6 (CONTRACTS_G6 section 5.1): reveal radius + G6Hooks.sight_bonus (source gather, both the native
## stamp and the Image fallback read the same sight), entity_visible ANDs G6Hooks.visible_to for enemies.
## Each hook is called only when its bit is set in SimIndex.g6m(w).
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")
## PERF6-2 sight split: with the SIGHT bit clear on a height map, the height term of G6Hooks.sight_bonus
## (Elevation.sight_bonus: +sight_per_level per level above plain, ground units / buildings) is still
## applied, but only sources standing above plain (one packed byte read each) call it; with the bit set the
## full hook runs as before (hash-exact: the callin term is +0.0 when no aerostat exists). g6_hooks_on =
## false turns it off too. ORCH can then drop height from the SIGHT rule in G6Hooks.active.
const Elevation = preload("res://sim/systems/elevation.gd")
static var sight_split := true   # tests: false = the pre-split path (bonus only with the SIGHT bit)
## G3b PERF4-3: with the native core live, stamping uses RtsFog.stamp/explored_out (same circle rule:
## r = floor(sight), dx*dx + dy*dy <= sight*sight, clipped); the Image-blit path below is the
## fallback. native_off forces the fallback (parity tests).
static var native_off := false
## G3b PERF4: recompute makes ONE pass over the SimIndex units + buildings for all teams (it used
## to make one full pass per team plus one per side for memory), with per-def sight caches; memory
## only walks buildings. Every source is still stamped on every recompute (vision is player-visible),
## but sources sharing a cell and sight are stamped once (unchanged dedupe).

static var _circles: Dictionary = {}   # sight (float) -> [src Image, mask Image, r]
static var _sights: Dictionary = {}    # "kind:def" -> float sight


static var _usight: Dictionary = {}   # unit def -> sight
static var _bsight: Dictionary = {}   # building def -> sight


static func sight_of(e: Dictionary) -> float:
	var unit: bool = e.kind == "unit"
	var cache: Dictionary = _usight if unit else _bsight
	var v = cache.get(e.def)
	if v != null:
		return v
	var d: Dictionary = Content.unit(e.def) if unit else Content.building(e.def)
	var s := float(d.get("sight", 0))
	cache[e.def] = s
	return s


## [src R8 image of 1s, LA8 mask image (alpha 255 inside the circle), r] for a sight radius.
## Cells whose centre is within `sight` of the source cell centre are visible.
static func _stamp(sight: float) -> Array:
	if _circles.has(sight):
		return _circles[sight]
	var r := int(floor(sight))
	var n := 2 * r + 1
	var ones := PackedByteArray()
	ones.resize(n * n)
	ones.fill(1)
	var m := PackedByteArray()
	m.resize(n * n * 2)
	m.fill(0)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if float(dx * dx + dy * dy) <= sight * sight:
				var i := ((dy + r) * n + (dx + r)) * 2
				m[i] = 255
				m[i + 1] = 255
	var la := PackedByteArray()
	la.resize(n * n * 2)
	for i in n * n:
		la[2 * i] = 1
		la[2 * i + 1] = 255
	var out := [Image.create_from_data(n, n, false, Image.FORMAT_R8, ones),
		Image.create_from_data(n, n, false, Image.FORMAT_LA8, m), r,
		Image.create_from_data(n, n, false, Image.FORMAT_LA8, la)]   # [3] LA8 source of (1, 255)
	_circles[sight] = out
	return out


static func init_faction_fog(w: SimWorld) -> void:
	var n := int(w.map.w) * int(w.map.h)
	for fid in w.factions:
		var vis := PackedByteArray()
		vis.resize(n)
		vis.fill(0)
		var ex := PackedByteArray()
		ex.resize(n)
		ex.fill(0)
		w.fog[fid] = {"visible": vis, "explored": ex}
		if not w.memory.has(fid):
			w.memory[fid] = {}
	recompute(w)


## G3b PERF4-2: teams are recomputed on alternating half-periods (team ordinal 0, 2, .. on
## tick % RECOMPUTE_EVERY == 0; ordinal 1, 3, .. on tick % RECOMPUTE_EVERY == RECOMPUTE_EVERY / 2),
## so each team's vision still refreshes every RECOMPUTE_EVERY ticks but the cost is split in two.
## G3b PERF4-3: the two phases moved to tick % RECOMPUTE_EVERY == 1 and == 3, off Morale's update
## tick (tick % 4 == 0) and the Tiers recompute (tick % 8 == 6), so periodic jobs never stack.
static func tick(w: SimWorld) -> void:
	var ph := w.tick % RECOMPUTE_EVERY
	if ph == 1:
		recompute(w, 0)
	elif ph == 3:
		recompute(w, 1)


## G3a allied vision (agent V3): sides are grouped by team. Every member of a team gets the SAME
## visible array (stamped from all the team's units and buildings) and a shared explored array, so
## is_visible / entity_visible / visible_enemies and the renderer all see allied vision for free and
## the cost is one stamping pass per TEAM (cheaper than per side). Memory stays per side
## (w.memory[fid]) but is updated from the team's merged vision, i.e. it is the merged view.
static func team_members(w: SimWorld, fid: int) -> Array:
	var tm = w.cache.get("fog_teams")
	if tm == null or int(tm.get("_n", -1)) != w.factions.size():
		tm = {"_n": w.factions.size()}
		for a in w.factions:
			var lst := []
			for b in w.factions:
				if int(a) == int(b) or w.is_ally(int(a), int(b)):
					lst.append(int(b))
			tm[int(a)] = lst
		w.cache["fog_teams"] = tm
	return tm.get(fid, [fid])


## True when a unit of fid or of an ally (the sides that share fid's vision) is within r of p. Used by the AI
## general's danger-close check before it calls a strike; lives here so AI code never walks other sides' units.
static func team_unit_near(w: SimWorld, fid: int, p: Vector2, r: float) -> bool:
	for f in team_members(w, fid):
		for e in w.units_of(int(f)):
			if (e.pos as Vector2).distance_to(p) <= r:
				return true
	return false


static func _or_bytes(a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	var out := a.duplicate()
	for i in mini(out.size(), b.size()):
		if b[i] != 0:
			out[i] = 1
	return out


## G6 PERF6-4: tests / bench toggle for the native source gather (RtsCombat.fog_gather, rts_core >= 0.5.1).
static var native_gather := true
static var _uair: Dictionary = {}   # unit def -> Elevation.is_air (fog_gather input)


## The recompute source gather as RtsCombat.fog_gather (no G6 SIGHT hook; hb = the packed height term or
## empty): fills nsrc[root] = [cells, sights] in the GDScript gather's first-wins key order. False (nothing
## computed) when the batch is unavailable or the stamp step would not take arrays: the GDScript loop runs.
static func _native_gather(w: SimWorld, lists: Array, root: Dictionary, srcs: Dictionary, hb: PackedByteArray, mw: int, mh: int, nsrc: Dictionary) -> bool:
	if NativeCore.new_fog(w) == null:
		return false
	var lc = w.cache.get("combat_lc")   # the shared RtsCombat (combat.gd _combat_obj, same cache key)
	if lc == null:
		lc = NativeCore.new_combat(w)
		w.cache["combat_lc"] = lc if lc != null else false
	var cobj = lc if lc is Object else null
	if cobj == null or not cobj.has_method("fog_gather"):
		return false
	var slots := []
	for rt in srcs:
		slots.append(int(rt))
	var top := 0
	for fid in w.factions:
		top = maxi(top, int(fid))
	var rmap := PackedInt32Array()
	rmap.resize(top + 1)
	rmap.fill(-1)
	var jm := PackedFloat64Array()
	jm.resize(top + 1)
	jm.fill(1.0)
	for fid in w.factions:
		var f := int(fid)
		if f < 0:
			continue
		var rt = root.get(f)
		if rt != null:
			rmap[f] = slots.find(int(rt))
		jm[f] = Status.jam_mult(w, f)
	if not Elevation._loaded:
		Elevation._load()
	var prm := PackedFloat64Array([float(mw), float(mh), float(Elevation.PLAIN), float(Elevation._sight), float(w.tick)])
	var r: Array = cobj.fog_gather(lists, w.entities, rmap, slots.size(), _usight, _bsight, _uair, jm, hb, prm)
	if r.size() == 1:
		for e in r[0]:
			sight_of(e)
			if e.kind == "unit":
				_uair[e.def] = Elevation.is_air(e)
		r = cobj.fog_gather(lists, w.entities, rmap, slots.size(), _usight, _bsight, _uair, jm, hb, prm)
	if r.size() != 2 * slots.size():
		return false
	for k in slots.size():
		nsrc[slots[k]] = [r[2 * k], r[2 * k + 1]]
	return true


## phase -1: every team (init, load, tests); 0 / 1: only teams whose ordinal % 2 == phase.
static func recompute(w: SimWorld, phase := -1) -> void:
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mw * mh
	for fid in w.factions:
		if not w.fog.has(fid):
			var e0 := PackedByteArray()
			e0.resize(n)
			e0.fill(0)
			w.fog[fid] = {"visible": e0.duplicate(), "explored": e0}
		if not w.memory.has(fid):
			w.memory[fid] = {}
	var t0 := Time.get_ticks_usec() if SimIndex.profiling else 0
	# one pass: stamp sources per team (keyed by the team's first member)
	var root := {}
	for fid in w.factions:
		if not root.has(int(fid)):
			var members := team_members(w, int(fid))
			for m in members:
				root[int(m)] = int(members[0])
	var srcs := {}   # root -> {stamp key: [cell, sight]}
	var ordinal := 0
	for fid in w.factions:
		if int(root[int(fid)]) == int(fid):
			if phase < 0 or ordinal % 2 == phase:
				srcs[int(fid)] = {}
			ordinal += 1
	var ents: Dictionary = w.entities
	var usight := _usight
	var bsight := _bsight
	# G3b PERF4-3: units come from the index's per-owner lists, so an off-phase team's units are
	# never walked (ascending id within each owner, owners in first-seen order)
	var lists := []
	var uown: Dictionary = SimIndex.units_by_owner(w)
	for o in uown:
		var rto = root.get(o)
		if rto != null and srcs.has(rto):
			lists.append(uown[o])
	lists.append(SimIndex.of(w, "building"))
	var g6s: bool = SimIndex.g6m(w) & SimIndex.G6_SIGHT != 0
	# sight split: the owners' own SIGHT rule decides whether the full hook runs (G6Hooks.sight_bonus returns
	# 0.0 without it, height included), so with the bit forced on (G6_ALL) only the packed height term applies
	if g6s and sight_split and SimIndex.g6_spy == null and (int(SimIndex.g6h().active(w)) & SimIndex.G6_SIGHT) == 0:
		g6s = false
	var hb := PackedByteArray()
	if sight_split and not g6s and SimIndex.g6_spy == null and SimIndex.g6_hooks_on and w.map.has("height"):
		hb = w.map.height
	var has_hb := not hb.is_empty()
	# G6 PERF6-4: the same gather as one native batch when the SIGHT hook does not run (exact port)
	var nsrc := {}   # root -> [cells, sights] (first-wins order) from the native gather
	var nat := native_gather and not g6s and not native_off and _native_gather(w, lists, root, srcs, hb, mw, mh, nsrc)
	for li in (0 if nat else lists.size()):
		var cache: Dictionary = usight if li < lists.size() - 1 else bsight
		for e: Dictionary in lists[li]:
			var rt = root.get(e.owner)
			if rt == null or not srcs.has(rt) or not ents.has(e.id):
				continue
			var sv = cache.get(e.def)
			var s: float = sv if sv != null else sight_of(e)
			if e.has("comp") or e.has("jammed_until"):
				s *= Status.sight_mult(w, e)
			if g6s and s > 0.0:
				s += SimIndex.g6h().sight_bonus(w, e)  # G6: height / spotter bonus (+0.0 when neutral)
			elif has_hb and s > 0.0:
				var q: Vector2 = e.pos
				var qx := floori(q.x)
				var qy := floori(q.y)
				if qx >= 0 and qy >= 0 and qx < mw and qy < mh and hb[qy * mw + qx] > Elevation.PLAIN:
					s += Elevation.sight_bonus(w, e)   # sight split: height term only (SIGHT bit clear)
			if s <= 0.0:
				continue
			var p: Vector2 = e.pos
			var key := (floori(p.y) * mw + floori(p.x)) * 128 + int(s * 4.0)
			var st: Dictionary = srcs[rt]
			if not st.has(key):
				st[key] = s
	if SimIndex.profiling:
		t0 = SimIndex.pt("fog.gather", t0)
	var ones := _ones(mw, mh)
	var full := Rect2i(0, 0, mw, mh)
	for rt in srcs:
		var members := team_members(w, int(rt))
		var ex_data: PackedByteArray = w.fog[members[0]].explored
		for k in range(1, members.size()):
			var other: PackedByteArray = w.fog[members[k]].explored
			if other != ex_data:
				ex_data = _or_bytes(ex_data, other)
		# Stamping is done with native Image blits (one call per unique source): visible is an
		# LA8 image (L = 1, A = 255 where seen) so that it is also the mask that ORs it into
		# explored in ONE blit (PERF4-2; it used to be a second blit per source).
		var st: Dictionary = srcs[rt]
		var rf = null if native_off else NativeCore.new_fog(w)
		if rf != null:
			var cells := PackedInt32Array()
			var sights := PackedFloat64Array()
			if nsrc.has(rt):
				cells = nsrc[rt][0]
				sights = nsrc[rt][1]
			else:
				cells.resize(st.size())
				sights.resize(st.size())
				var q := 0
				for key in st:
					cells[q] = key >> 7
					sights[q] = float(st[key])
					q += 1
			var nvis: PackedByteArray = rf.stamp(mw, mh, cells, sights, ex_data)
			var nex: PackedByteArray = rf.explored_out()
			if SimIndex.profiling:
				t0 = SimIndex.pt("fog.blit", t0)
			for m in members:
				w.fog[m].visible = nvis
				w.fog[m].explored = nex
				_update_memory(w, int(m), nvis, mw)
			if SimIndex.profiling:
				t0 = SimIndex.pt("fog.memory", t0)
			continue
		var vis_img := Image.create_empty(mw, mh, false, Image.FORMAT_LA8)
		for key in st:
			var ci: int = key >> 7
			var cy := floori(float(ci) / float(mw))
			var c := Vector2i(ci - cy * mw, cy)
			var stp: Array = _stamp(float(st[key]))
			var r := int(stp[2])
			vis_img.blit_rect_mask(stp[3], stp[1], Rect2i(0, 0, 2 * r + 1, 2 * r + 1), c - Vector2i(r, r))
		var ex_img := Image.create_from_data(mw, mh, false, Image.FORMAT_R8, ex_data)
		ex_img.blit_rect_mask(ones, vis_img, full, Vector2i.ZERO)
		vis_img.convert(Image.FORMAT_R8)
		if SimIndex.profiling:
			t0 = SimIndex.pt("fog.blit", t0)
		var vis := vis_img.get_data()
		var ex := ex_img.get_data()
		for m in members:
			w.fog[m].visible = vis
			w.fog[m].explored = ex
			_update_memory(w, int(m), vis, mw)
		if SimIndex.profiling:
			t0 = SimIndex.pt("fog.memory", t0)


static var _ones_img: Image = null


## Map-sized R8 image of 1s (source for the explored OR-blit).
static func _ones(mw: int, mh: int) -> Image:
	if _ones_img == null or _ones_img.get_width() != mw or _ones_img.get_height() != mh:
		var b := PackedByteArray()
		b.resize(mw * mh)
		b.fill(1)
		_ones_img = Image.create_from_data(mw, mh, false, Image.FORMAT_R8, b)
	return _ones_img


static func _update_memory(w: SimWorld, fid: int, vis: PackedByteArray, mw: int) -> void:
	var mem: Dictionary = w.memory[fid]
	for e in SimIndex.of(w, "building"):
		if not w.is_enemy(fid, int(e.owner)) or not w.entities.has(int(e.id)):
			continue
		var id := int(e.id)
		if _building_seen(w, e, vis, mw):
			mem[int(id)] = {"def": e.def, "kind": e.kind, "owner": int(e.owner), "pos": e.pos, "tick": w.tick}
	var drop := []
	for eid in mem:
		var m: Dictionary = mem[eid]
		var still = w.entities.get(int(eid))
		if still != null and still.kind == "building":
			continue
		var c := w.cell_of(m.pos)
		if w.in_bounds(c) and vis[c.y * mw + c.x] == 1:
			drop.append(eid)
	for eid in drop:
		mem.erase(eid)


static func _building_seen(w: SimWorld, b: Dictionary, vis: PackedByteArray, mw: int) -> bool:
	var o: Vector2i = b.cell
	var s := int(b.size)
	for y in range(o.y, o.y + s):
		for x in range(o.x, o.x + s):
			if w.in_bounds(Vector2i(x, y)) and vis[y * mw + x] == 1:
				return true
	return false


static func is_visible(w: SimWorld, fid: int, pos: Vector2) -> bool:
	var f = w.fog.get(fid)
	if f == null:
		return false
	var c := w.cell_of(pos)
	if not w.in_bounds(c):
		return false
	var vis: PackedByteArray = f.visible
	return vis[c.y * int(w.map.w) + c.x] == 1


static func is_explored(w: SimWorld, fid: int, pos: Vector2) -> bool:
	var f = w.fog.get(fid)
	if f == null:
		return false
	var c := w.cell_of(pos)
	if not w.in_bounds(c):
		return false
	var ex: PackedByteArray = f.explored
	return ex[c.y * int(w.map.w) + c.x] == 1


## Is entity e currently visible to fid? Buildings count as visible if any footprint cell is.
static func entity_visible(w: SimWorld, fid: int, e: Dictionary) -> bool:
	if int(e.owner) == fid or w.is_ally(fid, int(e.owner)):
		return true
	if not _entity_visible0(w, fid, e):
		return false
	# G6: submerged / camouflaged / cloaked / garrisoned (G6Hooks.visible_to)
	return SimIndex.g6m(w) & SimIndex.G6_VIS == 0 or SimIndex.g6h().visible_to(w, fid, e)


## entity_visible before the G6 visible_to rule (an enemy or neutral e).
static func _entity_visible0(w: SimWorld, fid: int, e: Dictionary) -> bool:
	if e.kind == "building":
		var f = w.fog.get(fid)
		if f == null:
			return false
		return _building_seen(w, e, f.visible, int(w.map.w))
	# G5 (UNITS5 CR 2845): a recon-drone mark (G5Mech) reveals the unit to the marking team
	if e.has("marked_until") and int(e.marked_until) > w.tick and w.factions.has(fid) 			and int(e.get("marked_team", -999)) == int(w.factions[fid].get("team", fid)):
		return true
	return is_visible(w, fid, e.pos) and not concealed(w, fid, e)


## Enemy units AND buildings on cells currently visible to fid (the only legal enemy query for AI).
## G3b PERF4-2: (1) REDUCED-tier units are skipped: by the Tiers contact bound no unit or
## building of another team is within contact radius (>= every sight) of them, so they are never
## on a cell fid sees; the candidates are the FULL list plus buildings. (2) The result is cached
## per (tick, fid, entity count, next_id): repeated calls in one tick (AI think, ops) reuse it,
## and any spawn or death in between invalidates it. Callers get a copy (safe to mutate).
static func visible_enemies(w: SimWorld, fid: int) -> Array:
	return _vis_cached(w, fid).duplicate()


## G6.1 PERF61-2 (ORCH-approved): the same list as visible_enemies(w, fid) WITHOUT the copy. READ-ONLY: never
## sort, append, erase or keep it past the call (it is the per-tick cache). For hot read-only callers
## (Intel.refresh, CommandNet, Doctrine intel); everything else keeps visible_enemies().
static func visible_enemies_ro(w: SimWorld, fid: int) -> Array:
	return _vis_cached(w, fid)


static func _vis_cached(w: SimWorld, fid: int) -> Array:
	var vc = w.cache.get("vis_enemies")
	var stamp := [w.tick, w.entities.size(), int(w.next_id)]
	if vc == null or vc.stamp != stamp:
		vc = {"stamp": stamp, "by": {}}
		w.cache["vis_enemies"] = vc
	var hit = vc.by.get(fid)
	if hit != null:
		return hit
	# G3b PERF4-3: only ENEMY owners' units are walked (per-owner index lists), REDUCED ones skipped
	# (never visible to another team: Tiers contact bound >= every sight), then enemy buildings;
	# the result is sorted by id, i.e. the same list in the same order as the old full scan.
	var out := []
	var tiers_on := Tiers.enabled(w)
	var uown: Dictionary = SimIndex.units_by_owner(w)
	var parts := 0
	for o in uown:
		if not w.is_enemy(fid, int(o)):
			continue
		parts += 1
		for e: Dictionary in uown[o]:
			if tiers_on and e.has("tier") and int(e.tier) == Tiers.REDUCED:
				continue
			if w.entities.has(int(e.id)) and entity_visible(w, fid, e):
				out.append(e)
	var nb := out.size()
	for e in SimIndex.of(w, "building"):
		_vis_add(w, fid, e, out)
	if out.size() > nb:
		parts += 1
	if parts > 1:
		out.sort_custom(func(x, y): return int(x.id) < int(y.id))
	vc.by[fid] = out
	return out


static func _vis_add(w: SimWorld, fid: int, e: Dictionary, out: Array) -> void:
	if w.is_enemy(fid, int(e.owner)) and w.entities.has(int(e.id)) and entity_visible(w, fid, e):
		out.append(e)


# ================================================================ G2 concealment (agent A2)
## CONTRACTS_G2 section 2: enemy infantry (units with `morale`) standing on FOREST is hidden from fid
## unless some fid unit/building is within rules.concealment_range of it, or it fired in the last
## REVEAL_TICKS ticks (e.last_fired_tick, set by combat._fire). Checked in the query, not the stamp.
## Spotter positions are indexed once per tick, lazily, in w.cache (never saved: rebuilt per tick).
const REVEAL_TICKS := 60
const FOREST_CODE := 3   # Terrain.FOREST


static func concealed(w: SimWorld, fid: int, e: Dictionary) -> bool:
	if e.kind != "unit" or not e.has("morale") or int(e.owner) == fid or w.is_ally(fid, int(e.owner)):
		return false
	if bool(e.get("hid", false)):  # G4b UNITS sniper conceal_still (CONTRACTS_G4 8): hidden beyond 3 tiles
		var f = w.factions.get(fid)
		return not (e.get("spot", []) as Array).has(int(f.get("team", fid)) if f != null else fid)
	if w.tick - int(e.get("last_fired_tick", -9999)) < REVEAL_TICKS:
		return false
	var p: Vector2 = e.pos
	if w.terrain_at(Vector2i(floori(p.x), floori(p.y))) != FOREST_CODE:
		return false
	return not _spotted(w, fid, p)


## Is any unit or building of fid or an ally within concealment_range of p?
static func _spotted(w: SimWorld, fid: int, p: Vector2) -> bool:
	var idx = w.cache.get("conceal_idx")
	if idx == null or int(idx.tick) != w.tick:
		idx = _build_conceal_idx(w)
		w.cache["conceal_idx"] = idx
	for m in team_members(w, fid):   # G3a: an ally's unit or building spots too
		if _spotted_by(idx, int(m), p):
			return true
	return false


static func _spotted_by(idx: Dictionary, fid: int, p: Vector2) -> bool:
	var r: float = idx.r
	var f = idx.fids.get(fid)
	if f == null:
		return false
	var r2 := r * r
	var bx := floori(p.x / r)
	var by := floori(p.y / r)
	var units: Dictionary = f.units
	for yy in range(by - 1, by + 2):
		for xx in range(bx - 1, bx + 2):
			var arr = units.get(xx + yy * 4096)
			if arr == null:
				continue
			for q in arr:
				if p.distance_squared_to(q) <= r2:
					return true
	for rect in f.blds:
		var rr: Rect2 = rect
		var c := Vector2(clampf(p.x, rr.position.x, rr.end.x), clampf(p.y, rr.position.y, rr.end.y))
		if p.distance_squared_to(c) <= r2:
			return true
	return false


static func _build_conceal_idx(w: SimWorld) -> Dictionary:
	var r := maxf(float(Content.rules().get("concealment_range", 5)), 1.0)
	var fids := {}
	for e in SimIndex.of(w, "unit") + SimIndex.of(w, "building"):
		if not w.entities.has(int(e.id)):
			continue
		var o := int(e.owner)
		if not fids.has(o):
			fids[o] = {"units": {}, "blds": []}
		if e.kind == "unit":
			var p: Vector2 = e.pos
			var k := floori(p.x / r) + floori(p.y / r) * 4096
			var u: Dictionary = fids[o].units
			if u.has(k):
				u[k].append(p)
			else:
				u[k] = [p]
		else:
			var c: Vector2i = e.cell
			fids[o].blds.append(Rect2(Vector2(c), Vector2(float(e.size), float(e.size))))
	return {"tick": w.tick, "r": r, "fids": fids}
