extends RefCounted
## Airfield (owner: AIRSYS). CONTRACTS_G5 sections 3.4, 3.5, 4, 5, 7.
## G5 scaffold (ORCH): compiling stub registered in SYSTEM_ORDER; does nothing until its owner fills it in.
## Commands:
##   build_hangar (see CONTRACTS_G5 section 4)
##   upgrade_hangar (see CONTRACTS_G5 section 4)
##   upgrade_airfield (see CONTRACTS_G5 section 4)
##   assign_engineers (see CONTRACTS_G5 section 4)


static func tick(_w: SimWorld) -> void:
	pass


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "not_implemented"


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass

## Production gate (called by production.gd). "" = allowed, else a reason such as "no_free_hangar".
static func can_produce(_w: SimWorld, _fid: int, _def_id: String) -> String:
	return ""
