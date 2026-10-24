extends RefCounted
## Progression (owner: STG4): research projects + Stage 7->8->9 advancement.
## Contract: docs/CONTRACTS_G3b.md section 3. ORCH scaffold stub: STG4 replaces the bodies.


static func tick(_w: SimWorld) -> void:
	pass


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "Research and stage advancement are not implemented yet."


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass


## Gate checklist for UI and AI: [{key, label, have, need, ok}]. Stub: empty.
static func gate_report(_w: SimWorld, _fid: int) -> Array:
	return []
