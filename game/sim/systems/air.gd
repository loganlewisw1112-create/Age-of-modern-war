extends RefCounted
## Air (owner: AIRSYS). CONTRACTS_G5 sections 3.2, 3.6, 4, 5, 7.
## G5 scaffold (ORCH): compiling stub registered in SYSTEM_ORDER; does nothing until its owner fills it in.
## Commands:
##   sortie (see CONTRACTS_G5 section 4)
##   rebase (see CONTRACTS_G5 section 4)
##   land_at (see CONTRACTS_G5 section 4)
##   take_off (see CONTRACTS_G5 section 4)


static func tick(_w: SimWorld) -> void:
	pass


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "not_implemented"


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass

## Targeting rule for air classes (wired into combat by CORE10K). Stub: no change to G4 behaviour.
static func can_target(_weapon: Dictionary, _target: Dictionary) -> bool:
	return true


static func is_landed(_e: Dictionary) -> bool:
	return true
