extends RefCounted
## STUB (owner: agent A / sim-econ). Build placement, foundations, engineers constructing.
## Commands: build, assist_build, cancel_building. Contract: docs/CONTRACTS.md §Construction.

static func tick(w: SimWorld) -> void:
	pass

static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return "Construction not implemented yet."

static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	pass

## Returns "" if def_id can be placed with top-left cell origin for faction fid.
static func placement_error(w: SimWorld, fid: int, def_id: String, origin: Vector2i) -> String:
	return "Construction not implemented yet."
