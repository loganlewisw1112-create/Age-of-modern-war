extends RefCounted
## AiCommand (owner: AI7-CMD). CONTRACTS_G6 §4, §16.
## G6 scaffold stub (ORCH): neutral until the owner fills it in. Every API returns a safe default so
## callers never crash and existing results stay identical. Do not preload g6_hooks.gd here (cycle).

static func tick(w: SimWorld) -> void:
	pass


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return "not_implemented"


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	pass


## Player AI-commander slots [{slot, target, playstyle, objective, stance}].
static func slots(w: SimWorld, fid: int) -> Array:
	return []
