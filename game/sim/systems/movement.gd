extends RefCounted
## STUB (owner: agent B / sim-mil). Nav grids (foot/vehicle), pathing, steering, formations.
## Commands: move, attack_move, stop, hold. Contract: docs/CONTRACTS.md §Movement.

static func tick(w: SimWorld) -> void:
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" or e.order.type != "move":
			continue
		var goal: Vector2 = e.order.target
		var d: Vector2 = goal - e.pos
		var step := float(Content.unit(e.def).speed) * SimWorld.DT
		if d.length() <= step:
			e.pos = goal
			e.order = {"type": "idle"}
		else:
			e.pos += d.normalized() * step

static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return ""

static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	for id in cmd.get("unit_ids", []):
		var e: Dictionary = w.entities[id]
		match cmd.type:
			"move", "attack_move":
				e.order = {"type": "move", "target": cmd.target}
			_:
				e.order = {"type": "idle"}

## Rebuild runtime nav caches from map + buildings. Called on new match and load.
static func rebuild_nav(w: SimWorld) -> void:
	pass

## Called when a building footprint is added (solid=true) or removed. Must no-op if nav not built yet.
static func on_footprint_changed(w: SimWorld, origin: Vector2i, size: int, solid: bool) -> void:
	pass

## Order a single unit to path to goal (used by gather/construction/production/AI-free helpers).
static func order_move(w: SimWorld, e: Dictionary, goal: Vector2) -> void:
	e.order = {"type": "move", "target": goal}

## Contract helper: path e toward goal without changing e.order. STUB: straight line.
static func order_path(w: SimWorld, e: Dictionary, goal: Vector2) -> bool:
	e.path = [goal]
	e.path_i = 0
	e.moving = true
	return true

static func is_passable(w: SimWorld, cell: Vector2i, move_class: String) -> bool:
	return Terrain.passable(w.terrain_at(cell), move_class)

static func nearest_free_cell(w: SimWorld, cell: Vector2i, move_class: String) -> Vector2i:
	return cell
