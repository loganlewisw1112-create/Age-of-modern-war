extends RefCounted
const Status = preload("res://sim/systems/status.gd")
## Movement (owner: agent B / sim-mil). Nav grids (foot/vehicle), A* pathing with a per-tick
## budget and a deterministic, saved request queue, steering with separation, formations.
## Commands: move, attack_move, stop, hold. Contract: docs/CONTRACTS.md section 5.
##
## Runtime-only (never saved, rebuilt by rebuild_nav): w.nav = {w, h, blocked (footprint counts),
##   foot: AStarGrid2D, vehicle: AStarGrid2D, comp: {mc: PackedInt32Array}, comp_dirty}.
## Saved: w.sys_state.movement = {queue: [{id, req, goal}], req_seq, budget_tick, budget_used}.
## Entity fields added lazily: path_req (int, -1 = none pending), stuck (int ticks).
## G3a (S3-sim): move_class "air" (drones) has no AStarGrid: every in-bounds cell is passable,
##   paths are one straight segment to the map-clamped goal, terrain never slows it, footprints
##   never block it, and separation only pushes air units against other air units.

const CLASSES := ["foot", "vehicle"]
const PATH_BUDGET := 40          # new A* computations per tick (rest are queued, FIFO)
const QUEUE_MIN_DRAIN := 8       # queued requests always drained per tick, even if over budget
const SNAP_RADIUS := 6           # goal snaps to the nearest reachable cell within this many tiles
const OFFSET_RADIUS := 16        # precomputed search offsets
const HALF_NB := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
const SEP_BUCKET := 1.5          # >= largest unit diameter (MBT 1.4)
const LOS_MAX := 14.0            # straight-line paths (no A*) up to this length when clear
const Q := 1.0 / 1024.0          # quantum for saved floats (exact in var_to_str text)
const SEP_STRENGTH := 0.5
const SEP_MAX_PUSH := 0.15
const STUCK_REPATH_TICKS := 40
const SLOT_FOOT := 1.1
const SLOT_VEHICLE := 1.8
const CENTER := Vector2(0.5, 0.5)
const AIR := "air"
const AIR_LAYER := 262144        # separation hash offset: air units only separate among themselves

static var _udefs: Dictionary = {}
static var _offsets: Array = []


# ================================================================ content helpers
static func udef(def_id) -> Dictionary:
	if _udefs.has(def_id):
		return _udefs[def_id]
	var d := Content.unit(def_id)
	var r := {
		"speed": float(d.get("speed", 1.0)),
		"radius": float(d.get("radius", 0.3)),
		"mc": String(d.get("move_class", "foot")),
	}
	_udefs[def_id] = r
	return r


static func move_class(e: Dictionary) -> String:
	return udef(String(e.def)).mc


## Offsets (Vector2i) within OFFSET_RADIUS sorted by (distance^2, y, x): deterministic search order.
static func _search_offsets() -> Array:
	if not _offsets.is_empty():
		return _offsets
	var arr := []
	for dy in range(-OFFSET_RADIUS, OFFSET_RADIUS + 1):
		for dx in range(-OFFSET_RADIUS, OFFSET_RADIUS + 1):
			if dx * dx + dy * dy <= OFFSET_RADIUS * OFFSET_RADIUS:
				arr.append(Vector2i(dx, dy))
	arr.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := a.x * a.x + a.y * a.y
		var db := b.x * b.x + b.y * b.y
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	_offsets = arr
	return _offsets


static func _state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("movement"):
		w.sys_state["movement"] = {"queue": [], "req_seq": 0, "budget_tick": -1, "budget_used": 0}
	return w.sys_state["movement"]


# ================================================================ nav
static func _nav_ready(w: SimWorld) -> bool:
	return w.nav.has("foot")


static func _ensure_nav(w: SimWorld) -> void:
	if not _nav_ready(w):
		rebuild_nav(w)


## Rebuild runtime nav caches from map + building entities. Called on new match and after load.
static func rebuild_nav(w: SimWorld) -> void:
	_state(w)
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var blocked := PackedByteArray()
	blocked.resize(mw * mh)
	blocked.fill(0)
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "building":
			continue
		var o: Vector2i = e.cell
		var s := int(e.size)
		for y in range(o.y, o.y + s):
			for x in range(o.x, o.x + s):
				if x >= 0 and y >= 0 and x < mw and y < mh:
					blocked[y * mw + x] = mini(blocked[y * mw + x] + 1, 255)
	w.nav = {"w": mw, "h": mh, "blocked": blocked, "comp": {}, "comp_dirty": true}
	var terrain: PackedByteArray = w.map.terrain
	for mc in CLASSES:
		var g := AStarGrid2D.new()
		g.region = Rect2i(0, 0, mw, mh)
		g.cell_size = Vector2(1, 1)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.update()
		for y in mh:
			for x in mw:
				var i := y * mw + x
				_apply_cell(g, terrain[i], blocked[i], mc, Vector2i(x, y))
		w.nav[mc] = g


static func _apply_cell(g: AStarGrid2D, code: int, blocked_count: int, mc: String, c: Vector2i) -> void:
	var solid := blocked_count > 0 or not Terrain.passable(code, mc)
	g.set_point_solid(c, solid)
	if not solid:
		g.set_point_weight_scale(c, 1.0 / Terrain.speed_mult(code, mc))


## Called when a building footprint is added (solid=true) or removed. No-op if nav is not built.
## Units standing inside a newly solid footprint are nudged to nearest_free_cell.
static func on_footprint_changed(w: SimWorld, origin: Vector2i, size: int, solid: bool) -> void:
	if not _nav_ready(w):
		return
	var mw := int(w.nav.w)
	var blocked: PackedByteArray = w.nav.blocked
	var terrain: PackedByteArray = w.map.terrain
	for y in range(origin.y, origin.y + size):
		for x in range(origin.x, origin.x + size):
			var c := Vector2i(x, y)
			if not w.in_bounds(c):
				continue
			var i := y * mw + x
			if solid:
				blocked[i] = mini(blocked[i] + 1, 255)
			else:
				blocked[i] = maxi(blocked[i] - 1, 0)
			for mc in CLASSES:
				_apply_cell(w.nav[mc], terrain[i], blocked[i], mc, c)
	w.nav.blocked = blocked
	w.nav.comp_dirty = true
	if solid:
		var rect := Rect2i(origin, Vector2i(size, size))
		for id in w.entities:
			var e: Dictionary = w.entities[id]
			if e.kind != "unit" or move_class(e) == AIR:
				continue
			var cell := w.cell_of(e.pos)
			if rect.has_point(cell):
				var free := nearest_free_cell(w, cell, move_class(e))
				e.pos = Vector2(free) + CENTER


## Connected-component labels (4-connected; diagonals never connect what orthogonals cannot).
static func _comp(w: SimWorld, mc: String) -> PackedInt32Array:
	if w.nav.comp_dirty:
		var mw := int(w.nav.w)
		var mh := int(w.nav.h)
		var comps := {}
		for k in CLASSES:
			var g: AStarGrid2D = w.nav[k]
			var lab := PackedInt32Array()
			lab.resize(mw * mh)
			lab.fill(-2)
			for y in mh:
				for x in mw:
					if g.is_point_solid(Vector2i(x, y)):
						lab[y * mw + x] = -1
			var next := 0
			var q := PackedInt32Array()
			for s in mw * mh:
				if lab[s] != -2:
					continue
				lab[s] = next
				q.clear()
				q.append(s)
				var qi := 0
				while qi < q.size():
					var i := q[qi]
					qi += 1
					var x := i % mw
					var y := i / mw
					if x > 0 and lab[i - 1] == -2:
						lab[i - 1] = next
						q.append(i - 1)
					if x < mw - 1 and lab[i + 1] == -2:
						lab[i + 1] = next
						q.append(i + 1)
					if y > 0 and lab[i - mw] == -2:
						lab[i - mw] = next
						q.append(i - mw)
					if y < mh - 1 and lab[i + mw] == -2:
						lab[i + mw] = next
						q.append(i + mw)
				next += 1
			comps[k] = lab
		w.nav.comp = comps
		w.nav.comp_dirty = false
	return w.nav.comp[mc]


# ================================================================ public helpers
static func is_passable(w: SimWorld, cell: Vector2i, mc: String) -> bool:
	if not w.in_bounds(cell):
		return false
	if mc == AIR:
		return true  # G3a: air ignores terrain and footprints
	if _nav_ready(w) and w.nav.has(mc):
		var g: AStarGrid2D = w.nav[mc]
		return not g.is_point_solid(cell)
	if not Terrain.passable(w.terrain_at(cell), mc):
		return false
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building" and Rect2i(e.cell, Vector2i(int(e.size), int(e.size))).has_point(cell):
			return false
	return true


## Nearest passable cell to `cell` (itself if passable). Deterministic order: distance, then y, then x.
static func nearest_free_cell(w: SimWorld, cell: Vector2i, mc: String) -> Vector2i:
	if is_passable(w, cell, mc):
		return cell
	for off in _search_offsets():
		var c: Vector2i = cell + off
		if is_passable(w, c, mc):
			return c
	for r in range(OFFSET_RADIUS + 1, 64):
		for dy in range(-r, r + 1):
			for dx in [-r, r]:
				var c := cell + Vector2i(dx, dy)
				if is_passable(w, c, mc):
					return c
		for dx in range(-r + 1, r):
			for dy in [-r, r]:
				var c := cell + Vector2i(dx, dy)
				if is_passable(w, c, mc):
					return c
	return cell


## Resolves start/goal for e. Returns {ok, start, cell, pos}. The goal snaps to the nearest cell
## reachable from the unit's start cell within SNAP_RADIUS tiles.
static func _resolve(w: SimWorld, e: Dictionary, goal: Vector2) -> Dictionary:
	_ensure_nav(w)
	var mc := move_class(e)
	if mc == AIR:
		var gp := Vector2(clampf(goal.x, 0.5, float(w.map.w) - 0.5), clampf(goal.y, 0.5, float(w.map.h) - 0.5))
		var sc := w.cell_of(e.pos)
		return {"ok": true, "start": sc, "cell": w.cell_of(gp), "pos": gp}
	var mw := int(w.nav.w)
	var start := w.cell_of(e.pos)
	if not is_passable(w, start, mc):
		start = nearest_free_cell(w, start, mc)
	if not is_passable(w, start, mc):
		return {"ok": false}
	var lab := _comp(w, mc)
	var label := lab[start.y * mw + start.x]
	var gc := w.cell_of(goal)
	if w.in_bounds(gc) and lab[gc.y * mw + gc.x] == label:
		return {"ok": true, "start": start, "cell": gc, "pos": goal}
	for off in _search_offsets():
		var o: Vector2i = off
		if o.x * o.x + o.y * o.y > SNAP_RADIUS * SNAP_RADIUS:
			break
		var c := gc + o
		if w.in_bounds(c) and lab[c.y * mw + c.x] == label:
			return {"ok": true, "start": start, "cell": c, "pos": Vector2(c) + CENTER}
	return {"ok": false}


static func can_reach(w: SimWorld, e: Dictionary, goal: Vector2) -> bool:
	return _resolve(w, e, goal).ok


static func _take_budget(w: SimWorld) -> bool:
	var st := _state(w)
	if int(st.budget_tick) != w.tick:
		st.budget_tick = w.tick
		st.budget_used = 0
	if int(st.budget_used) < PATH_BUDGET:
		st.budget_used = int(st.budget_used) + 1
		return true
	return false


## Clears any path and pending request; the unit stops.
static func stop_path(e: Dictionary) -> void:
	e.path = []
	e.path_i = 0
	e.moving = false
	e.path_req = -1
	e.stuck = 0


## Contract helper: path e toward goal without changing e.order. Sets e.path, e.path_i, e.moving.
## Returns false if unreachable (goal snapped within 6 tiles). When this tick's A* budget is
## spent the request is queued (FIFO, saved in sys_state) and e.path stays empty until served.
static func order_path(w: SimWorld, e: Dictionary, goal: Vector2) -> bool:
	var r := _resolve(w, e, goal)
	if not r.ok:
		stop_path(e)
		return false
	var st := _state(w)
	e.path_i = 0
	e.moving = true
	e.stuck = 0
	if r.cell == r.start or move_class(e) == AIR or _line_clear(w, move_class(e), e.pos, r.pos):
		e.path = [r.pos]
		e.path_req = -1
		return true
	if st.queue.is_empty() and _take_budget(w):
		e.path = _compute(w, move_class(e), r.start, r.cell, r.pos)
		e.path_req = -1
	else:
		st.req_seq = int(st.req_seq) + 1
		e.path = []
		e.path_req = int(st.req_seq)
		st.queue.append({"id": int(e.id), "req": int(st.req_seq), "goal": r.pos})
	return true


## Legacy helper kept for callers: sets a move order and paths to goal.
static func order_move(w: SimWorld, e: Dictionary, goal: Vector2) -> void:
	e.order = {"type": "move", "target": goal}
	if not order_path(w, e, goal):
		e.order = {"type": "idle"}


static func _compute(w: SimWorld, mc: String, start: Vector2i, dest: Vector2i, dest_pos: Vector2) -> Array:
	var g: AStarGrid2D = w.nav[mc]
	var ids: Array[Vector2i] = g.get_id_path(start, dest)
	var out := []
	var n := ids.size()
	for i in range(1, n):
		# drop collinear intermediate waypoints (straight runs)
		if i < n - 1 and ids[i] - ids[i - 1] == ids[i + 1] - ids[i]:
			continue
		out.append(Vector2(ids[i]) + CENTER)
	if out.is_empty():
		out.append(dest_pos)
	else:
		out[out.size() - 1] = dest_pos
	return out


## Straight segment a->b is walkable (sampled every 0.3 tiles, diagonal cell changes need both
## orthogonal cells). Short open-ground moves (chases, formation slots) skip A* entirely.
static func _line_clear(w: SimWorld, mc: String, a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var l := d.length()
	if l > LOS_MAX:
		return false
	var n := int(ceil(l / 0.3))
	var prev := a
	for i in range(1, n + 1):
		var q := a + d * (float(i) / float(n))
		if not _step_ok(w, mc, prev, q):
			return false
		prev = q
	return true


## Quantize a position to Q (exact through var_to_str) without changing its cell.
static func _qpos(w: SimWorld, p: Vector2) -> Vector2:
	var s := p.snapped(Vector2(Q, Q))
	return s if w.cell_of(s) == w.cell_of(p) else p


static func _drain_queue(w: SimWorld) -> void:
	var st := _state(w)
	var q: Array = st.queue
	if q.is_empty():
		return
	if int(st.budget_tick) != w.tick:
		st.budget_tick = w.tick
		st.budget_used = 0
	var allowed := maxi(PATH_BUDGET - int(st.budget_used), QUEUE_MIN_DRAIN)
	var served := 0
	var i := 0
	while i < q.size() and served < allowed:
		var req: Dictionary = q[i]
		i += 1
		var e = w.entities.get(int(req.id))
		if e == null or e.kind != "unit" or not e.moving or int(e.get("path_req", -1)) != int(req.req):
			continue
		served += 1
		st.budget_used = int(st.budget_used) + 1
		var r := _resolve(w, e, req.goal)
		if not r.ok:
			stop_path(e)
			if e.order.type == "move":
				e.order = {"type": "idle"}
			continue
		if r.cell == r.start or move_class(e) == AIR or _line_clear(w, move_class(e), e.pos, r.pos):
			e.path = [r.pos]
		else:
			e.path = _compute(w, move_class(e), r.start, r.cell, r.pos)
		e.path_i = 0
		e.path_req = -1
	st.queue = q.slice(i)


# ================================================================ tick
## Advances every unit with e.moving == true along e.path, whatever its order type.
static func tick(w: SimWorld) -> void:
	_ensure_nav(w)
	_drain_queue(w)
	var grids := {"foot": w.nav.foot, "vehicle": w.nav.vehicle}
	var bounds := Rect2i(0, 0, int(w.nav.w), int(w.nav.h))
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		var mc := move_class(e)
		var p: Vector2 = e.pos
		var cell := Vector2i(floori(p.x), floori(p.y))
		var g = grids.get(mc)
		if mc == AIR:
			if not bounds.has_point(cell):
				e.pos = Vector2(clampi(cell.x, 0, bounds.size.x - 1), clampi(cell.y, 0, bounds.size.y - 1)) + CENTER
		elif g == null or not bounds.has_point(cell) or g.is_point_solid(cell):
			# safety invariant: never leave a unit inside an impassable cell
			e.pos = Vector2(nearest_free_cell(w, cell, mc)) + CENTER
		if e.moving:
			_advance(w, e, mc)
	_separate(w)


static func _arrive(e: Dictionary) -> void:
	stop_path(e)
	if e.order.type == "move":
		e.order = {"type": "idle"}


static func _advance(w: SimWorld, e: Dictionary, mc: String) -> void:
	var path: Array = e.path
	if path.is_empty():
		if int(e.get("path_req", -1)) < 0:
			_arrive(e)  # moving without a path and nothing pending
		return  # else: waiting for a queued path
	var pi := int(e.path_i)
	if pi >= path.size():
		_arrive(e)
		return
	var next_cell := w.cell_of(path[pi])
	if not is_passable(w, next_cell, mc):
		# the way became blocked (new footprint): repath to the final goal
		var goal: Vector2 = path[path.size() - 1]
		if not order_path(w, e, goal) and e.order.type == "move":
			e.order = {"type": "idle"}
		return
	var u := udef(String(e.def))
	var pos: Vector2 = e.pos
	var start_pos := pos
	var tmult := 1.0 if mc == AIR else Terrain.speed_mult(w.terrain_at(w.cell_of(pos)), mc)
	var spd: float = float(u.speed) * tmult * SimWorld.DT * Status.move_mult(w, e)
	if spd <= 0.0:
		return  # immobile (mobility kill / no fuel): keep the path, do not move
	var remaining := spd
	var guard := 0
	var blocked := false
	while remaining > 0.0001 and pi < path.size() and guard < 4:
		guard += 1
		var wp: Vector2 = path[pi]
		var d := wp - pos
		var dist := d.length()
		if dist > 0.0001:
			e.facing = snappedf(d.angle(), Q)
		var want := wp if dist <= remaining else pos + d / dist * remaining
		var got := _try_move(w, mc, pos, want)
		if got != want:
			blocked = true
			pos = got
			break
		pos = want
		if dist <= remaining:
			remaining -= dist
			pi += 1
		else:
			remaining = 0.0
	e.pos = _qpos(w, pos)
	e.path_i = pi
	if pi >= path.size():
		_arrive(e)
		return
	var moved := pos.distance_to(start_pos)
	if moved < spd * 0.25 or blocked:
		e.stuck = int(e.get("stuck", 0)) + 1
	else:
		e.stuck = maxi(int(e.get("stuck", 0)) - 1, 0)
	var st_ticks := int(e.stuck)
	var final_pos: Vector2 = path[path.size() - 1]
	var to_final := pos.distance_to(final_pos)
	# crowding at the destination: accept arrival when close and not making progress
	if pi == path.size() - 1 and ((to_final < 0.8 and st_ticks >= 6) or (to_final < 2.0 and st_ticks >= 20)):
		_arrive(e)
		return
	if st_ticks >= STUCK_REPATH_TICKS:
		if not order_path(w, e, final_pos) and e.order.type == "move":
			e.order = {"type": "idle"}


## Moves from -> to if the destination cell is passable (and, on a diagonal cell change, both
## orthogonal cells are too); otherwise slides along one axis; otherwise stays.
static func _try_move(w: SimWorld, mc: String, from: Vector2, to: Vector2) -> Vector2:
	if _step_ok(w, mc, from, to):
		return to
	var sx := Vector2(to.x, from.y)
	if _step_ok(w, mc, from, sx):
		return sx
	var sy := Vector2(from.x, to.y)
	if _step_ok(w, mc, from, sy):
		return sy
	return from


static func _step_ok(w: SimWorld, mc: String, from: Vector2, to: Vector2) -> bool:
	var a := w.cell_of(from)
	var b := w.cell_of(to)
	if a == b:
		return true
	if not is_passable(w, b, mc):
		return false
	if a.x != b.x and a.y != b.y:
		return is_passable(w, Vector2i(b.x, a.y), mc) and is_passable(w, Vector2i(a.x, b.y), mc)
	return true


## Light separation between overlapping friendly units, via a spatial hash in w.cache.
## Idle units yield more than moving ones. Pushes never enter impassable cells.
static func _separate(w: SimWorld) -> void:
	# Flat per-tick arrays (index = unit order in w.entities); buckets hold indices.
	var units := []
	var pos := PackedVector2Array()
	var rad := PackedFloat32Array()
	var mov := PackedByteArray()
	var okeys := PackedInt32Array()
	var grid := {}
	var n := 0
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		var p: Vector2 = e.pos
		var ok := (int(e.owner) + 1) * 1048576 + (AIR_LAYER if move_class(e) == AIR else 0)
		units.append(e)
		pos.append(p)
		rad.append(float(udef(e.def).radius))
		mov.append(1 if e.moving else 0)
		okeys.append(ok)
		var key := int(floor(p.x / SEP_BUCKET)) + int(floor(p.y / SEP_BUCKET)) * 1024 + ok
		var arr = grid.get(key)
		if arr == null:
			grid[key] = [n]
		else:
			arr.append(n)
		n += 1
	w.cache["movement_hash"] = grid
	var push := PackedVector2Array()
	push.resize(n)
	push.fill(Vector2.ZERO)
	var any := false
	for i in n:
		var pa := pos[i]
		var ra := rad[i]
		var bx := int(floor(pa.x / SEP_BUCKET))
		var by := int(floor(pa.y / SEP_BUCKET))
		var ok := okeys[i]
		# half neighbourhood: own bucket (j > i) + 4 forward buckets, so each pair is visited once
		for nb in 5:
			var arr = grid.get(bx + HALF_NB[nb].x + (by + HALF_NB[nb].y) * 1024 + ok)
			if arr == null:
				continue
			for j in arr:
				if nb == 0 and j <= i:
					continue
				var d := pa - pos[j]
				var min_d := ra + rad[j]
				var dist2 := d.length_squared()
				if dist2 >= min_d * min_d:
					continue
				var dist := sqrt(dist2)
				var dir: Vector2
				if dist < 0.0001:
					var ida := int(units[i].id)
					var idb := int(units[j].id)
					dir = Vector2.RIGHT.rotated(float((ida * 37 + idb * 17) % 360) * PI / 180.0)
				else:
					dir = d / dist
				var overlap := (min_d - dist) * SEP_STRENGTH
				var wa := 0.5
				if mov[i] != mov[j]:
					wa = 0.25 if mov[i] == 1 else 0.75
				push[i] += dir * overlap * wa
				push[j] -= dir * overlap * (1.0 - wa)
				any = true
	if not any:
		return
	var mw := float(w.map.w) - 0.01
	var mh := float(w.map.h) - 0.01
	for i in n:
		var v := push[i]
		var l := v.length()
		if l < 0.002:
			continue
		if l > SEP_MAX_PUSH:
			v = v / l * SEP_MAX_PUSH
		var e: Dictionary = units[i]
		var p := pos[i]
		var to := p + v
		to.x = clampf(to.x, 0.01, mw)
		to.y = clampf(to.y, 0.01, mh)
		e.pos = _qpos(w, _try_move(w, move_class(e), p, to))


# ================================================================ commands
static func _cmd_target(cmd: Dictionary):
	var t = cmd.get("target")
	if typeof(t) == TYPE_VECTOR2:
		return t
	if typeof(t) == TYPE_VECTOR2I:
		return Vector2(t) + CENTER
	return null


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	match String(cmd.type):
		"move", "attack_move":
			var t = _cmd_target(cmd)
			if t == null:
				return "Move target is missing or invalid."
			var tv: Vector2 = t
			if not w.in_bounds(w.cell_of(tv)):
				return "Target is outside the map."
			for id in cmd.get("unit_ids", []):
				var e = w.entities.get(int(id))
				if e != null and can_reach(w, e, tv):
					return ""
			return "No selected unit can reach that location."
		"stop", "hold":
			return ""
	return "Unknown movement command."


## Formation slots around target: a grid with ~1.1 tile spacing (1.8 if any vehicle), clamped to the map.
static func formation_slots(w: SimWorld, units: Array, target: Vector2) -> Array:
	var n := units.size()
	if n <= 1:
		return [target]
	var sp := SLOT_FOOT
	for e in units:
		if move_class(e) == "vehicle":
			sp = SLOT_VEHICLE
	# G2 (agent C2): the first unit's e.formation ("line"|"wedge"|"column") shapes the group,
	# oriented along centroid -> target. No formation keeps the G1 grid below.
	var form := String(units[0].get("formation", ""))
	if form == "line" or form == "wedge" or form == "column":
		var cen := Vector2.ZERO
		for e in units:
			cen += e.pos
		cen /= float(n)
		var fwd := target - cen
		fwd = fwd / fwd.length() if fwd.length() > 0.01 else Vector2(0, -1)
		var side := Vector2(-fwd.y, fwd.x)
		var slots := []
		for k in n:
			var p := target
			match form:
				"line":
					p = target + side * (float(k) - float(n - 1) * 0.5) * sp
				"column":
					p = target - fwd * float(k) * sp
				"wedge":
					var rank := (k + 1) / 2
					var sgn := -1.0 if k % 2 == 1 else 1.0
					p = target - fwd * float(rank) * sp + side * sgn * float(rank) * sp
			p.x = clampf(p.x, 0.5, float(w.map.w) - 0.5)
			p.y = clampf(p.y, 0.5, float(w.map.h) - 0.5)
			slots.append(p)
		return slots
	var cols := int(ceil(sqrt(float(n))))
	var rows := int(ceil(float(n) / float(cols)))
	var out := []
	for k in n:
		var r := k / cols
		var c := k % cols
		var p := target + Vector2((float(c) - float(cols - 1) * 0.5) * sp, (float(r) - float(rows - 1) * 0.5) * sp)
		p.x = clampf(p.x, 0.5, float(w.map.w) - 0.5)
		p.y = clampf(p.y, 0.5, float(w.map.h) - 0.5)
		out.append(p)
	return out


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var units := []
	for id in cmd.get("unit_ids", []):
		var e = w.entities.get(int(id))
		if e != null and e.kind == "unit":
			units.append(e)
	match String(cmd.type):
		"move", "attack_move":
			var target: Vector2 = _cmd_target(cmd)
			# deterministic slot assignment: units sorted by (y, x, id), slots row-major
			units.sort_custom(func(a, b) -> bool:
				var pa: Vector2 = a.pos
				var pb: Vector2 = b.pos
				if pa.y != pb.y:
					return pa.y < pb.y
				if pa.x != pb.x:
					return pa.x < pb.x
				return int(a.id) < int(b.id))
			var slots := formation_slots(w, units, target)
			for i in units.size():
				var e: Dictionary = units[i]
				var slot: Vector2 = slots[i]
				e.target = -1
				if cmd.type == "move":
					e.order = {"type": "move", "target": slot}
				else:
					e.order = {"type": "attack_move", "target": slot, "engaged": false}
				if not order_path(w, e, slot):
					e.order = {"type": "idle"}
		"stop":
			for e in units:
				e.order = {"type": "idle"}
				e.target = -1
				stop_path(e)
		"hold":
			for e in units:
				e.order = {"type": "hold"}
				e.target = -1
				stop_path(e)


## G2 (ORCH hook): terrain cells changed (bridge destroyed/repaired). Rebuild nav from the map and
## re-request every active path so nobody walks through a dead cell (QA-007).
static func on_terrain_changed(w: SimWorld) -> void:
	rebuild_nav(w)
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and bool(e.get("moving", false)) and not (e.path as Array).is_empty():
			var goal: Vector2 = e.path[e.path.size() - 1]
			if not order_path(w, e, goal):
				stop_path(e)
