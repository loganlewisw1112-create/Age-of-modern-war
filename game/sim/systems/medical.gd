extends RefCounted
## Medical (owner: SUPPORT). CONTRACTS_G5 sections 3.4, 4, 5, 10.
## G5 scaffold (ORCH): compiling stub registered in SYSTEM_ORDER; does nothing until its owner fills it in.
## Commands:
##   set_auto_evac (see CONTRACTS_G5 section 4)


static func tick(_w: SimWorld) -> void:
	pass


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "not_implemented"


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass

## Called by Damage before a unit at 0 HP is destroyed (wired by CORE10K). true = keep it alive (Wounded).
static func on_zero_hp(_w: SimWorld, _e: Dictionary) -> bool:
	return false


static func is_wounded(e: Dictionary) -> bool:
	return bool(e.get("wounded", false))
