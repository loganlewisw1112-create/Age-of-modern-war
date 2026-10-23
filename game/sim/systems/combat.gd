extends RefCounted
## STUB (owner: agent B / sim-mil). Target acquisition, firing, damage, death.
## Commands: attack. Contract: docs/CONTRACTS.md §Combat.

static func tick(w: SimWorld) -> void:
	pass

static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return "Combat not implemented yet."

static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	pass
