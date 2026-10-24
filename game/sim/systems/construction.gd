extends RefCounted
## Construction (owner: agent A / sim-econ). Placement rules, foundations, engineers constructing.
## Commands: build, assist_build, cancel_building. Contract: docs/CONTRACTS.md section 4.
## Also hosts small geometry helpers shared with gather.gd / production.gd.
## G3a: builders are units with `can_build`; build time is scaled by w.econ("build_time_mult");
## placement rejects another faction's buildings.

const Movement = preload("res://sim/systems/movement.gd")
const PData = preload("res://sim/systems/progression_data.gd")  # G3b stage/research gating (STG4)
const SimIndex = preload("res://sim/systems/sim_index.gd")  # G3b scale (PERF5): per-kind lists
const Subsets = preload("res://sim/systems/unit_subsets.gd")  # G3b scale (PERF5): builder units

const MAX_BUILD_RANGE := 20.0
const BUILD_REACH := 1.0   # engineer must be within this distance of the footprint edge
const REFUND_FULL_BELOW := 0.05


# ================================================================ geometry helpers
## Distance from a world position to the edge of a square footprint (0 if inside).
static func footprint_dist(pos: Vector2, cell: Vector2i, size: int) -> float:
	var dx := maxf(maxf(float(cell.x) - pos.x, pos.x - float(cell.x + size)), 0.0)
	var dy := maxf(maxf(float(cell.y) - pos.y, pos.y - float(cell.y + size)), 0.0)
	return Vector2(dx, dy).length()


static func building_at_cell(w: SimWorld, cell: Vector2i) -> bool:
	for b in SimIndex.of(w, "building"):
		if not SimIndex.alive(w, b):
			continue
		var bc: Vector2i = b.cell
		var s := int(b.size)
		if cell.x >= bc.x and cell.x < bc.x + s and cell.y >= bc.y and cell.y < bc.y + s:
			return true
	return false


## Cells forming the square ring `margin` cells outside the footprint (row-major order).
static func ring_cells(cell: Vector2i, size: int, margin: int = 1) -> Array:
	var out := []
	for y in range(cell.y - margin, cell.y + size + margin):
		for x in range(cell.x - margin, cell.x + size + margin):
			var inside := x >= cell.x and x < cell.x + size and y >= cell.y and y < cell.y + size
			if inside:
				continue
			# only the outermost ring of this margin (margin 2 skips the margin-1 ring)
			var ring_x := x == cell.x - margin or x == cell.x + size + margin - 1
			var ring_y := y == cell.y - margin or y == cell.y + size + margin - 1
			if ring_x or ring_y:
				out.append(Vector2i(x, y))
	return out


## World position an engineer should walk to in order to touch building b.
static func approach_goal(w: SimWorld, e: Dictionary, b: Dictionary) -> Vector2:
	var mc: String = String(Content.unit(e.def).get("move_class", "foot"))
	var best := Vector2(b.pos)
	var best_d := INF
	for c in ring_cells(b.cell, int(b.size), 1):
		if not w.in_bounds(c) or building_at_cell(w, c):
			continue
		if not Movement.is_passable(w, c, mc):
			continue
		var p := Vector2(c) + Vector2(0.5, 0.5)
		var d: float = (p - Vector2(e.pos)).length_squared()
		if d < best_d:
			best_d = d
			best = p
	if best_d == INF:
		return best
	var free: Vector2i = Movement.nearest_free_cell(w, w.cell_of(best), mc)
	return Vector2(free) + Vector2(0.5, 0.5)


## Keep a unit walking toward a footprint-adjacent goal for building b. Re-paths at most every 10 ticks.
static func approach(w: SimWorld, e: Dictionary, b: Dictionary) -> void:
	var wait := int(e.get("nav_wait", 0))
	var need: bool = int(e.get("nav_for", -1)) != int(b.id) or (not e.moving and wait <= 0)
	if need:
		Movement.order_path(w, e, approach_goal(w, e, b))
		e.nav_for = int(b.id)
		e.nav_wait = 10
	elif wait > 0:
		e.nav_wait = wait - 1


## Keep a unit walking toward an arbitrary point keyed by an entity id. Re-paths at most every 10 ticks.
static func approach_point(w: SimWorld, e: Dictionary, key: int, goal: Vector2) -> void:
	var wait := int(e.get("nav_wait", 0))
	var need: bool = int(e.get("nav_for", -1)) != key or (not e.moving and wait <= 0)
	if need:
		Movement.order_path(w, e, goal)
		e.nav_for = key
		e.nav_wait = 10
	elif wait > 0:
		e.nav_wait = wait - 1


static func make_idle(e: Dictionary) -> void:
	e.order = {"type": "idle"}
	e.moving = false
	e.path = []
	e.path_i = 0
	e.nav_for = -1


static func stop_moving(e: Dictionary) -> void:
	e.moving = false
	e.path = []
	e.path_i = 0


# ================================================================ placement
## Returns "" if def_id can be placed with top-left cell `origin` for faction fid, else a sentence.
static func placement_error(w: SimWorld, fid: int, def_id: String, origin: Vector2i) -> String:
	var d := Content.building(def_id)
	if d.is_empty():
		return "Unknown building '%s'." % def_id
	var nm := String(d.get("name", def_id))
	if not bool(d.get("buildable", false)):
		return "%s cannot be constructed." % nm
	if w.factions.has(fid) and d.has("faction") and String(d.faction) != String(w.factions[fid].faction_def):
		return "%s belongs to another faction." % nm
	var gate := PData.unavailable_reason(w, fid, d)  # G3b: "Requires Stage 8" / "Requires research: X"
	if gate != "":
		return "%s: %s." % [nm, gate]
	for req in d.get("requires", []):
		var ok := false
		for b in w.buildings_of(fid, String(req)):
			if b.built:
				ok = true
				break
		if not ok:
			return "Requires a completed %s first." % String(Content.building(String(req)).get("name", req))
	var size := int(d.size)
	for dy in size:
		for dx in size:
			var c := origin + Vector2i(dx, dy)
			if not w.in_bounds(c):
				return "Outside the map."
	for dy in size:
		for dx in size:
			var c := origin + Vector2i(dx, dy)
			var t := w.terrain_at(c)
			if not Terrain.buildable(t):
				match t:
					Terrain.WATER:
						return "Cannot build on water."
					Terrain.RIDGE:
						return "Cannot build on a ridge."
					Terrain.FOREST:
						return "Cannot build in dense forest."
					Terrain.ROAD, Terrain.BRIDGE, Terrain.FORD:
						return "Cannot build on a road, bridge or ford."
					_:
						return "Terrain is not buildable here."
	for b in SimIndex.of(w, "building"):
		if not SimIndex.alive(w, b):
			continue
		var bc: Vector2i = b.cell
		var bs := int(b.size)
		if origin.x < bc.x + bs and origin.x + size > bc.x and origin.y < bc.y + bs and origin.y + size > bc.y:
			return "Blocked by another building."
	for r in SimIndex.of(w, "resource"):
		if not SimIndex.alive(w, r):
			continue
		var rc := w.cell_of(r.pos)
		if rc.x >= origin.x and rc.x < origin.x + size and rc.y >= origin.y and rc.y < origin.y + size:
			return "Blocked by a resource deposit."
	var fg = w.fog.get(fid)
	if fg != null:
		var ex: PackedByteArray = fg.explored
		var mw := int(w.map.w)
		for dy in size:
			for dx in size:
				var c := origin + Vector2i(dx, dy)
				if ex[c.y * mw + c.x] == 0:
					return "That area has not been explored yet."
	var center := Vector2(origin) + Vector2(size, size) * 0.5
	var near := false
	for b in w.buildings_of(fid):
		if center.distance_to(Vector2(b.pos)) <= MAX_BUILD_RANGE:
			near = true
			break
	if not near:
		return "Too far from your base (build within %d tiles of a friendly building)." % int(MAX_BUILD_RANGE)
	return ""


# ================================================================ commands
static func _builders(w: SimWorld, cmd: Dictionary) -> Array:
	var out := []
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null and e.kind == "unit" and bool(Content.unit(e.def).get("can_build", false)):
			out.append(int(raw))
	return out


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.issuer)
	match String(cmd.type):
		"build":
			if _builders(w, cmd).is_empty():
				return "Only work crews (engineers) can construct buildings."
			var def_id := String(cmd.get("def", ""))
			var origin := Vector2i(cmd.get("origin", Vector2i(-1, -1)))
			var err := placement_error(w, fid, def_id, origin)
			if err != "":
				return err
			return w.can_afford(fid, Content.building(def_id).cost)
		"assist_build":
			if _builders(w, cmd).is_empty():
				return "Only work crews (engineers) can assist construction."
			var b = w.entities.get(int(cmd.get("target_id", -1)))
			if b == null or b.kind != "building" or int(b.owner) != fid:
				return "That is not one of your buildings."
			if b.built:
				return "That building is already complete."
			return ""
		"cancel_building":
			var b = w.entities.get(int(cmd.building_id))
			if b.built:
				return "That building is already complete."
			return ""
	return "Unknown construction command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	match String(cmd.type):
		"build":
			var def_id := String(cmd.def)
			var origin := Vector2i(cmd.origin)
			var cost: Dictionary = Content.building(def_id).cost
			if not w.spend(fid, cost, "build:" + def_id):
				return
			var bid := w.spawn_building(def_id, fid, origin, false)
			var b: Dictionary = w.entities[bid]
			b.paid = {"credits": int(cost.get("credits", 0)), "salvage": int(cost.get("salvage", 0)), "ore": int(cost.get("ore", 0))}
			w.emit("ConstructionStarted", {"building_id": bid, "def": def_id, "owner": fid})
			_order_builders(w, cmd, bid)
		"assist_build":
			_order_builders(w, cmd, int(cmd.target_id))
		"cancel_building":
			var b: Dictionary = w.entities[int(cmd.building_id)]
			var paid: Dictionary = b.get("paid", Content.building(b.def).cost)
			var frac_full: bool = float(b.progress) < REFUND_FULL_BELOW
			var refund := {}
			for k in SimWorld.LEDGER_KEYS:
				var amt := int(paid.get(k, 0))
				refund[k] = amt if frac_full else amt / 2
			w.credit(fid, refund, "cancel_building")
			var bid := int(b.id)
			w.destroy(bid, "cancelled", SimWorld.NEUTRAL)
			# destroy() leaves a wreck; a cancelled foundation never existed, so drop it.
			var wreck = w.entities.get(w.next_id - 1)
			if wreck != null and wreck.kind == "wreck" and int(wreck.tick) == w.tick:
				w.entities.erase(w.next_id - 1)


static func _order_builders(w: SimWorld, cmd: Dictionary, building_id: int) -> void:
	var b: Dictionary = w.entities[building_id]
	for id in _builders(w, cmd):
		var e: Dictionary = w.entities[id]
		e.order = {"type": "build", "building_id": building_id}
		e.nav_for = -1
		e.nav_wait = 0
		if footprint_dist(e.pos, b.cell, int(b.size)) <= BUILD_REACH:
			stop_moving(e)
		else:
			approach(w, e, b)


# ================================================================ tick
## Only can_build units ever hold a "build" order (validate_command), so walk that subset (PERF5).
static func tick(w: SimWorld) -> void:
	for e in Subsets.units(w, Subsets.BUILDER):
		var o: Dictionary = e.order
		if o.type != "build":
			continue
		var b = w.entities.get(int(o.get("building_id", -1)))
		if b == null or b.kind != "building" or b.built:
			make_idle(e)
			continue
		if footprint_dist(e.pos, b.cell, int(b.size)) <= BUILD_REACH:
			if e.moving:
				stop_moving(e)
			var bp := float(Content.unit(e.def).get("build_power", 1.0))
			var bt := maxf(float(Content.building(b.def).get("build_time", 1)) * w.econ("build_time_mult"), 0.001)  # G3a profile
			var before := float(b.progress)
			var after := minf(1.0, before + bp * SimWorld.DT / bt)
			b.progress = after
			b.hp = minf(float(b.max_hp), float(b.hp) + (after - before) * float(b.max_hp) * 0.9)
			if after >= 1.0 - 0.000001:
				b.progress = 1.0
				b.built = true
				if float(b.hp) > float(b.max_hp) - 0.01:
					b.hp = float(b.max_hp)   # absorb float rounding when undamaged
				w.factions[int(b.owner)].stats.built += 1
				w.emit("ConstructionCompleted", {"building_id": int(b.id), "def": b.def, "owner": int(b.owner)})
		else:
			approach(w, e, b)
