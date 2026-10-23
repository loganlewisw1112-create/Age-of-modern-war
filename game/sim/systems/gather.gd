extends RefCounted
## STUB (owner: agent A / sim-econ). Engineers harvest salvage/ore and deliver to HQ/depot.
## Commands: gather. Contract: docs/CONTRACTS.md §Gather.

static func tick(w: SimWorld) -> void:
	pass

static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return "Gathering not implemented yet."

static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	pass
