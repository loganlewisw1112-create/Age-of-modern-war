extends RefCounted
## Fortify (owner: FORT): walls, gates, towers, build_line, gate locks, conn masks. CONTRACTS_G4 section 6.
## ORCH scaffold stub: the owner replaces the bodies.


static func tick(_w: SimWorld) -> void:
	pass


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "Not implemented yet."


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
