extends RefCounted
## STUB (owner: wave-2 AI agent). Fair autonomous opponent: same commands, fog-filtered knowledge.
## Contract: docs/CONTRACTS.md §AI.

static func new_state(w: SimWorld, fid: int) -> Dictionary:
	return {"phase": "opening", "next_think": 0, "log": []}

static func think(w: SimWorld, fid: int) -> void:
	pass
