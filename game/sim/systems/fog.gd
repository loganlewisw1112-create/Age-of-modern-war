extends RefCounted
const Status = preload("res://sim/systems/status.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
## Fog of war (owner: agent B / sim-mil). Per-faction visibility, explored cells, last-seen memory.
## Contract: docs/CONTRACTS.md section 5.
##   w.fog[fid] = {visible: PackedByteArray, explored: PackedByteArray}  (1 = yes, idx y*w+x)
##   w.memory[fid][eid] = {def, kind, owner, pos, tick}  last-seen enemy BUILDINGS
## Visible is recomputed every RECOMPUTE_EVERY ticks (and at init / tick 0) from all own units and
## buildings (built or not), as circles of radius `sight` around their cell centre. Explored is sticky.

const RECOMPUTE_EVERY := 4
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
	var out := [Image.create_from_data(n, n, false, Image.FORMAT_R8, ones),
		Image.create_from_data(n, n, false, Image.FORMAT_LA8, m), r]
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


static func tick(w: SimWorld) -> void:
	if w.tick % RECOMPUTE_EVERY == 0:
		recompute(w)


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


static func _or_bytes(a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	var out := a.duplicate()
	for i in mini(out.size(), b.size()):
		if b[i] != 0:
			out[i] = 1
	return out


static func recompute(w: SimWorld) -> void:
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
	# one pass: stamp sources per team (keyed by the team's first member)
	var root := {}
	for fid in w.factions:
		if not root.has(int(fid)):
			var members := team_members(w, int(fid))
			for m in members:
				root[int(m)] = int(members[0])
	var srcs := {}   # root -> {stamp key: [cell, sight]}
	for fid in w.factions:
		if int(root[int(fid)]) == int(fid):
			srcs[int(fid)] = {}
	for kind in ["unit", "building"]:
		for e in SimIndex.of(w, kind):
			var rt = root.get(int(e.owner))
			if rt == null or not w.entities.has(int(e.id)):
				continue
			var s := sight_of(e)
			if e.has("comp") or e.has("jammed_until"):
				s *= Status.sight_mult(w, e)
			if s <= 0.0:
				continue
			var p: Vector2 = e.pos
			var c := Vector2i(floori(p.x), floori(p.y))
			var key := (c.y * mw + c.x) * 128 + int(s * 4.0)
			var st: Dictionary = srcs[rt]
			if not st.has(key):
				st[key] = [c, s]
	for rt in srcs:
		var members := team_members(w, int(rt))
		var ex_data: PackedByteArray = w.fog[members[0]].explored
		for k in range(1, members.size()):
			var other: PackedByteArray = w.fog[members[k]].explored
			if other != ex_data:
				ex_data = _or_bytes(ex_data, other)
		# Stamping is done with native Image blits (one call per source per layer): a GDScript
		# per-cell loop cost ~100 ms per recompute at 256 units.
		var vis_img := Image.create_empty(mw, mh, false, Image.FORMAT_R8)
		var ex_img := Image.create_from_data(mw, mh, false, Image.FORMAT_R8, ex_data)
		var st: Dictionary = srcs[rt]
		for key in st:
			var c: Vector2i = st[key][0]
			var stp: Array = _stamp(float(st[key][1]))
			var r := int(stp[2])
			var src: Image = stp[0]
			var mask: Image = stp[1]
			var rect := Rect2i(0, 0, 2 * r + 1, 2 * r + 1)
			var dst := c - Vector2i(r, r)
			vis_img.blit_rect_mask(src, mask, rect, dst)
			ex_img.blit_rect_mask(src, mask, rect, dst)
		var vis := vis_img.get_data()
		var ex := ex_img.get_data()
		for m in members:
			w.fog[m].visible = vis
			w.fog[m].explored = ex
			_update_memory(w, int(m), vis, mw)


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
	if e.kind == "building":
		var f = w.fog.get(fid)
		if f == null:
			return false
		return _building_seen(w, e, f.visible, int(w.map.w))
	return is_visible(w, fid, e.pos) and not concealed(w, fid, e)


## Enemy units AND buildings on cells currently visible to fid (the only legal enemy query for AI).
static func visible_enemies(w: SimWorld, fid: int) -> Array:
	var out := []
	var us: Array = SimIndex.of(w, "unit")
	var bs: Array = SimIndex.of(w, "building")
	var bi := 0
	for e in us:
		while bi < bs.size() and int(bs[bi].id) < int(e.id):
			_vis_add(w, fid, bs[bi], out)
			bi += 1
		_vis_add(w, fid, e, out)
	while bi < bs.size():
		_vis_add(w, fid, bs[bi], out)
		bi += 1
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
