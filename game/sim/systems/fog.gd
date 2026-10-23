extends RefCounted
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
		# Stamping is done with native Image blits (one call per source per layer): a GDScript
		# per-cell loop cost ~100 ms per recompute at 256 units.
		var vis_img := Image.create_empty(mw, mh, false, Image.FORMAT_R8)
		var ex_img := Image.create_from_data(mw, mh, false, Image.FORMAT_R8, w.fog[fid].explored)
		var stamped := {}
		for id in w.entities:
			var e: Dictionary = w.entities[id]
			if int(e.owner) != int(fid) or (e.kind != "unit" and e.kind != "building"):
				continue
			var s := sight_of(e)
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
		w.fog[fid].visible = vis
		w.fog[fid].explored = ex
		_update_memory(w, fid, vis, mw)


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
	if int(e.owner) == fid:
		return true
	if e.kind == "building":
		var f = w.fog.get(fid)
		if f == null:
			return false
		return _building_seen(w, e, f.visible, int(w.map.w))
	return is_visible(w, fid, e.pos)


## Enemy units AND buildings on cells currently visible to fid (the only legal enemy query for AI).
static func visible_enemies(w: SimWorld, fid: int) -> Array:
	var out := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if (e.kind == "unit" or e.kind == "building") and w.is_enemy(fid, int(e.owner)) and entity_visible(w, fid, e):
			out.append(e)
	return out
