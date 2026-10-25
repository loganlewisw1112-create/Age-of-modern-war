extends RefCounted
## Rail (owner: MECH6a). CONTRACTS_G6 §4, §9.
## Command: build_rail {issuer, unit_ids, from:[x,y], to:[x,y]}: a 4-connected L path (x first, then
##   y; <= max_line cells). `from` must be within yard_radius of a built friendly rail yard (def
##   rail_yard, else rules.rail.yard_defs) or 4-adjacent to an intact RAIL tile. Cells already RAIL
##   are skipped; cut cells are re-laid (repair). Engineers (can_build) walk the cells in order and
##   work ticks_per_tile per tile (tile_cost: yard def rail_cost, else rules cost_per_tile; ledger
##   "build:rail").
## Laying: tiles are committed to w.map.terrain (RAIL = 14, ELEV's Terrain.RAIL) in groups of up to
##   COMMIT tiles (and at the end of a job): event TerrainChanged{cells, cause:"rail"} +
##   Movement.on_terrain_changed (one nav rebuild per group).
## Damage: damage_cell(w, cell, dmg) / on_splash(w, pos, radius, dmg) (wired by PERF6 via CR); at 0 hp
##   the tile is cut: terrain -> cut_terrain (dirt), event RailCut; build_rail over it repairs it.
## Train guard: a unit whose def move_class is "rail" never moves onto a non-RAIL cell: each tick its
##   path is cut before the first non-rail sample (0.25 tile steps), so it stops at a cut.
## State (saved, hashed; created on first build_rail): w.sys_state.rail = {jobs: [{id, owner,
##   cells: [[x,y]...], next, done, t, builders: [uid]}], next_job, hp: [[cell index, hp]...]
##   ascending, cut: [cell index] ascending, ver}.
## Runtime cache w.cache.rail_units = {cursor, ids} (rail-class unit ids). Determinism: ascending ids.

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const HotState = preload("res://sim/hot_state.gd")

const RAIL := 14
const COMMIT := 4


static func R() -> Dictionary:
	return Content.rules().get("g6_ground", {}).get("rail", {})


static func _state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("rail"):
		w.sys_state["rail"] = {"jobs": [], "next_job": 1, "hp": [], "cut": [], "ver": 1}
	return w.sys_state.rail


## True when the cell is an intact RAIL tile.
static func on_rail(w: SimWorld, cell: Vector2i) -> bool:
	return w.in_bounds(cell) and w.terrain_at(cell) == RAIL


static func is_yard(def_id: String) -> bool:
	return bool(Content.building(def_id).get("rail_yard", false)) or (R().get("yard_defs", []) as Array).has(def_id)


static func _v2i(v) -> Vector2i:
	if typeof(v) == TYPE_VECTOR2I:
		return v
	if typeof(v) == TYPE_VECTOR2:
		return Vector2i(floori(v.x), floori(v.y))
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)


## The L path from -> to (x first, then y), inclusive.
static func path_cells(from: Vector2i, to: Vector2i) -> Array:
	var out := [from]
	var c := from
	while c.x != to.x:
		c.x += signi(to.x - c.x)
		out.append(c)
	while c.y != to.y:
		c.y += signi(to.y - c.y)
		out.append(c)
	return out


## Cost of one rail tile for fid: the def `rail_cost` of its first built rail yard (ascending id),
## else rules.g6_ground.rail.cost_per_tile.
static func tile_cost(w: SimWorld, fid: int) -> Dictionary:
	for b in w.buildings_of(fid):
		if bool(b.get("built", false)) and is_yard(String(b.def)):
			var rc = Content.building(String(b.def)).get("rail_cost")
			if rc is Dictionary and not (rc as Dictionary).is_empty():
				return rc
	return R().get("cost_per_tile", {})


static func _builders(w: SimWorld, cmd: Dictionary) -> Array:
	var out := []
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null and e.kind == "unit" and int(e.owner) == int(cmd.issuer) and bool(Content.unit(String(e.def)).get("can_build", false)):
			out.append(e)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


static func cell_error(w: SimWorld, c: Vector2i) -> String:
	if not w.in_bounds(c):
		return "Outside the map."
	var t := w.terrain_at(c)
	if t == RAIL:
		return ""
	if t == Terrain.WATER or t == Terrain.DEEP or t == Terrain.SHALLOW or t == Terrain.CLIFF or t == Terrain.RIDGE or t == Terrain.BUILDING:
		return "Rail needs open ground."
	if Construction.building_at_cell(w, c):
		return "Blocked by a building."
	return ""


static func _anchor_ok(w: SimWorld, fid: int, c: Vector2i) -> bool:
	var rr := float(R().get("yard_radius", 8))
	for b in w.buildings_of(fid):
		if bool(b.get("built", false)) and is_yard(String(b.def)) and Vector2(c).distance_to(Vector2(b.pos)) <= rr:
			return true
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i.ZERO]:
		if on_rail(w, c + d):
			return true
	return false


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if String(cmd.get("type", "")) != "build_rail":
		return "Unknown rail command."
	var fid := int(cmd.get("issuer", -1))
	if _builders(w, cmd).is_empty():
		return "Only engineers lay rail."
	var a := _v2i(cmd.get("from"))
	var b := _v2i(cmd.get("to"))
	if not w.in_bounds(a) or not w.in_bounds(b):
		return "Outside the map."
	var cells := path_cells(a, b)
	if cells.size() > int(R().get("max_line", 48)):
		return "Rail line too long (max %d tiles)." % int(R().get("max_line", 48))
	if not _anchor_ok(w, fid, a):
		return "Rail must start at a Rail Yard or an existing line."
	for c in cells:
		var why := cell_error(w, c)
		if why != "":
			return why
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var st := _state(w)
	var cells := []
	for c in path_cells(_v2i(cmd.from), _v2i(cmd.to)):
		if not on_rail(w, c):
			cells.append([c.x, c.y])
	if cells.is_empty():
		return
	var job := {"id": int(st.next_job), "owner": int(cmd.issuer), "cells": cells, "next": 0, "done": 0, "t": 0, "builders": []}
	st.next_job = int(st.next_job) + 1
	for e in _builders(w, cmd):
		Construction.make_idle(e)
		e.erase("patrol")
		e.erase("guard")
		e.order = {"type": "rail", "job": int(job.id)}
		HotState.touch(w, int(e.id))
		job.builders.append(int(e.id))
	st.jobs.append(job)
	w.emit("RailPlanned", {"job": int(job.id), "owner": int(job.owner), "cells": cells})


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("rail")
	if st != null and not (st.jobs as Array).is_empty():
		var keep := []
		for job in st.jobs:
			if _job_step(w, st, job):
				keep.append(job)
		st.jobs = keep
	var ru = w.cache.get("rail_units")
	if ru == null or int(ru.cursor) != int(w.next_id):
		ru = _rail_units(w)
	for id in ru.ids:
		var e = w.entities.get(int(id))
		if e != null and e.kind == "unit" and bool(e.get("moving", false)):
			_guard(w, e)
			HotState.touch(w, int(id))


static func _rail_units(w: SimWorld) -> Dictionary:
	var c = w.cache.get("rail_units")
	if c == null:
		c = {"cursor": 0, "ids": []}
		w.cache["rail_units"] = c
	var nid := int(w.next_id)
	for id in range(int(c.cursor), nid):
		var e = w.entities.get(id)
		if e != null and e.kind == "unit" and String(Content.unit(String(e.def)).get("move_class", "")) == "rail":
			c.ids.append(id)
	c.cursor = nid
	return c


## Work one rail job. False when finished or abandoned.
static func _job_step(w: SimWorld, st: Dictionary, job: Dictionary) -> bool:
	var cells: Array = job.cells
	var live := []
	var working := 0
	for uid in job.builders:
		var e = w.entities.get(int(uid))
		if e == null or e.order.type != "rail" or int(e.order.get("job", -1)) != int(job.id):
			continue
		live.append(int(uid))
		if int(job.next) >= cells.size():
			continue
		var s: Array = cells[int(job.next)]
		var goal := Vector2(int(s[0]), int(s[1])) + Vector2(0.5, 0.5)
		if Vector2(e.pos).distance_to(goal) > float(R().get("reach", 1.6)):
			Construction.approach_point(w, e, 4000000 + int(job.id) * 64 + int(job.next), goal)
		else:
			if bool(e.moving):
				Construction.stop_moving(e)
			working += 1
	job.builders = live
	for uid in live:
		HotState.touch(w, int(uid))
	if working > 0 and int(job.next) < cells.size():
		job.t = int(job.t) + working
		if int(job.t) >= int(R().get("ticks_per_tile", 8)):
			var cost := tile_cost(w, int(job.owner))
			if w.spend(int(job.owner), cost, "build:rail"):
				job.t = 0
				job.next = int(job.next) + 1
			else:
				job.t = int(R().get("ticks_per_tile", 8))
	var pending := int(job.next) - int(job.done)
	var finished := int(job.next) >= cells.size()
	if pending > 0 and (pending >= COMMIT or finished or live.is_empty()):
		_commit(w, st, job)
	if finished or live.is_empty():
		for uid in live:
			Construction.make_idle(w.entities[uid])
			HotState.touch(w, int(uid))
		w.emit("RailBuilt" if finished else "RailAbandoned", {"job": int(job.id), "owner": int(job.owner), "laid": int(job.done)})
		return false
	return true


static func _commit(w: SimWorld, st: Dictionary, job: Dictionary) -> void:
	var mw := int(w.map.w)
	var t: PackedByteArray = w.map.terrain
	var out := []
	for i in range(int(job.done), int(job.next)):
		var s: Array = job.cells[i]
		var c := Vector2i(int(s[0]), int(s[1]))
		var k := c.y * mw + c.x
		if t[k] == RAIL or cell_error(w, c) != "":
			continue
		t[k] = RAIL
		out.append(c)
		if (st.cut as Array).has(k):
			st.cut.erase(k)
			w.emit("RailRepaired", {"cell": c, "owner": int(job.owner)})
		_set_hp(st, k, -1.0)
	job.done = int(job.next)
	if out.is_empty():
		return
	w.map.terrain = t
	w.emit("TerrainChanged", {"cells": out, "cause": "rail"})
	Movement.on_terrain_changed(w)


static func _set_hp(st: Dictionary, k: int, hp: float) -> void:
	var arr: Array = st.hp
	for i in arr.size():
		if int(arr[i][0]) == k:
			if hp < 0.0:
				arr.remove_at(i)
			else:
				arr[i][1] = hp
			return
	if hp >= 0.0:
		arr.append([k, hp])
		arr.sort_custom(func(a, b): return int(a[0]) < int(b[0]))


static func _hp_of(st: Dictionary, k: int) -> float:
	for p in st.hp:
		if int(p[0]) == k:
			return float(p[1])
	return float(R().get("tile_hp", 150))


## Damage a rail tile; true when it is cut by this hit.
static func damage_cell(w: SimWorld, cell: Vector2i, dmg: float, by: int = -1) -> bool:
	if not on_rail(w, cell) or dmg <= 0.0:
		return false
	var st := _state(w)
	var k := cell.y * int(w.map.w) + cell.x
	var hp := _hp_of(st, k) - dmg
	if hp > 0.0:
		_set_hp(st, k, hp)
		return false
	_set_hp(st, k, -1.0)
	var t: PackedByteArray = w.map.terrain
	t[k] = int(R().get("cut_terrain", 1))
	w.map.terrain = t
	st.cut.append(k)
	st.cut.sort()
	w.emit("RailCut", {"cell": cell, "by": by})
	w.emit("TerrainChanged", {"cells": [cell], "cause": "rail_cut"})
	Movement.on_terrain_changed(w)
	return true


## Splash damage on the ground (Damage calls this via CR): rail tiles within radius take dmg.
static func on_splash(w: SimWorld, pos: Vector2, radius: float, dmg: float, by: int = -1) -> void:
	var r := maxf(radius, 0.5)
	var c0 := w.cell_of(pos)
	var ri := ceili(r)
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var c := c0 + Vector2i(dx, dy)
			if on_rail(w, c) and (Vector2(c) + Vector2(0.5, 0.5)).distance_to(pos) <= r + 0.5:
				damage_cell(w, c, dmg, by)


## Rail units: cut the path before the first non-rail sample; stop when off rail.
static func _guard(w: SimWorld, e: Dictionary) -> void:
	var p: Vector2 = e.pos
	if not on_rail(w, w.cell_of(p)):
		Movement.stop_path(e)
		return
	var path: Array = e.path
	var last_ok := w.cell_of(p)
	var prev := p
	for k in range(int(e.path_i), path.size()):
		var q: Vector2 = path[k]
		var n := maxi(1, ceili(prev.distance_to(q) / 0.25))
		for j in range(1, n + 1):
			var sp := prev.lerp(q, float(j) / float(n))
			var sc := w.cell_of(sp)
			if not on_rail(w, sc):
				if k == int(e.path_i) and last_ok == w.cell_of(p):
					Movement.stop_path(e)
					return
				var np := path.slice(0, k)
				np.append(Vector2(last_ok) + Vector2(0.5, 0.5))
				e.path = np
				return
			last_ok = sc
		prev = q
