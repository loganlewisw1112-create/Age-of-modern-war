extends RefCounted
## STUB (owner: agent B2). `repair` command: engineers restore hp/components or a ruined bridge
## for salvage. Contract: docs/CONTRACTS_G2.md section 3.


static func tick(w: SimWorld) -> void:
	pass


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return "Repair not implemented yet."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	pass
