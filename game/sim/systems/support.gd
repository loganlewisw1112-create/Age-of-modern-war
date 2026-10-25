extends RefCounted
## Support (owner: SUPPORT). CONTRACTS_G5 sections 4, 5, 10.
## G5 scaffold (ORCH): compiling stub registered in SYSTEM_ORDER; does nothing until its owner fills it in.
## Commands:
##   set_auto_resupply (see CONTRACTS_G5 section 4)


static func tick(_w: SimWorld) -> void:
	pass


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "not_implemented"


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
