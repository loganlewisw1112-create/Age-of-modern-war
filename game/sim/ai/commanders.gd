extends RefCounted
## Commanders (player-side assist AI) (owner: AI7-CMD). CONTRACTS_G6 §16.
## G6 scaffold stub (ORCH): neutral until the owner fills it in. Every API returns a safe default so
## callers never crash and existing results stay identical. Do not preload g6_hooks.gd here (cycle).

## Run the player's AI-commander slots (called by the world each tick for non-AI sides).
static func think_player(w: SimWorld, fid: int) -> void:
	pass
