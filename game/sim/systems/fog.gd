extends RefCounted
const Status = preload("res://sim/systems/status.gd")
## Fog of war (owner: agent B / sim-mil). Per-faction visibility, explored cells, last-seen memory.
## Contract: docs/CONTRACTS.md section 5.
##   w.fog[fid] = {visible: PackedByteArray, explored: PackedByteArray}  (1 = yes, idx y*w+x)
##   w.memory[fid][eid] = {def, kind, owner, pos, tick}  last-seen enemy BUILDINGS
## Visible is recomputed every RECOMPUTE_EVERY ticks (and at init / tick 0) from all own units and
## buildings (built or not), as circles of radius `sight` around their cell centre. Explored is sticky.

const RECOMPUTE_EVERY := 4

static var _circles: Dictionary = {}   # sight (float) -> [src Image, mask Image, r]
static var _sights: Dictionary = {}    # "kind:def" -> float sight


static func sight_of(e: Dictionary) -> float:
	var key := String(e.kind) + ":" + String(e.def)
	if _sights.has(key):
		return _sights[key]
	var d: Dictionary = Content.unit(e.def) if e.kind == "unit" else Content.building(e.def)
	var s := float(d.get("sight", 0))
	_sights[key] = s
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
	var done := {}
	for fid in w.factions:
		if not w.fog.has(fid):
			var e0 := PackedByteArray()
			e0.resize(n)
			e0.fill(0)
			w.fog[fid] = {"visible": e0.duplicate(), "explored": e0}
		if not w.memory.has(fid):
			w.memory[fid] = {}
	for fid in w.factions:
		if done.has(int(fid)):
			continue
		var members := team_members(w, int(fid))
		var mset := {}
		for m in members:
			mset[int(m)] = true
			done[int(m)] = true
		var ex_data: PackedByteArray = w.fog[members[0]].explored
		for k in range(1, members.size()):
			var other: PackedByteArray = w.fog[members[k]].explored
			if other != ex_data:
				ex_data = _or_bytes(ex_data, other)
		# Stamping is done with native Image blits (one call per source per layer): a GDScript
		# per-cell loop cost ~100 ms per recompute at 256 units.
		var vis_img := Image.create_empty(mw, mh, false, Image.FORMAT_R8)
		var ex_img := Image.create_from_data(mw, mh, false, Image.FORMAT_R8, ex_data)
		var stamped := {}
		for id in w.entities:
			var e: Dictionary = w.entities[id]
			if (e.kind != "unit" and e.kind != "building") or not mset.has(int(e.owner)):
				continue
			var s := sight_of(e) * Status.sight_mult(w, e)
			if s <= 0.0:
				continue
			var c := w.cell_of(e.pos)
			var key := (c.y * mw + c.x) * 128 + int(s * 4.0)
			if stamped.has(key):
				continue
			stamped[key] = true
			var st: Array = _stamp(s)
			var r := int(st[2])
			var src: Image = st[0]
			var mask: Image = st[1]
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
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "building" or not w.is_enemy(fid, int(e.owner)):
			continue
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
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if (e.kind == "unit" or e.kind == "building") and w.is_enemy(fid, int(e.owner)) and entity_visible(w, fid, e):
			out.append(e)
	return out


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
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" and e.kind != "building":
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
