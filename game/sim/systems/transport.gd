extends RefCounted
## Transport (owner: TRANS): load/unload cargo for every carrier. CONTRACTS_G4 section 7.
## ORCH scaffold stub: the owner replaces the bodies.


static func tick(_w: SimWorld) -> void:
	pass


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "Not implemented yet."


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
