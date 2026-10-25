extends RefCounted
## Doctrine (AI doctrine engine entry) (owner: AI7-DOC). CONTRACTS_G6 §16.
## G6 scaffold stub (ORCH): neutral until the owner fills it in. Every API returns a safe default so
## callers never crash and existing results stay identical. Do not preload g6_hooks.gd here (cycle).

## Strategic/operational/tactical layers for an AI side (called by ai_controller).
static func think(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	pass


## Doctrine plan for one formation (used by AI Commanders).
static func plan_for(w: SimWorld, fid: int, formation: Dictionary) -> Dictionary:
	return {}
