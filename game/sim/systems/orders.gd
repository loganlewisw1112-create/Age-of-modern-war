extends RefCounted
## STUB (owner: agent C2). patrol / guard / set_formation direct orders.
## Contract: docs/CONTRACTS_G2.md section 4.


static func tick(w: SimWorld) -> void:
	pass


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return "Order not implemented yet."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	pass
