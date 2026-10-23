extends RefCounted
## STUB (owner: agent A / sim-econ). Production queues, rally points, squad spawning.
## Commands: queue_unit, cancel_unit, set_rally. Contract: docs/CONTRACTS.md §Production.

static func tick(w: SimWorld) -> void:
	pass

static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return "Production not implemented yet."

static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	pass
