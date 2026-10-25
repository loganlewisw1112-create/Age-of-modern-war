extends RefCounted
## HotState (owner: CORE10K). CONTRACTS_G5 section 5: packed per-id hot unit state (pos, target, moving,
## order kind, hp, cooldown) with one write API, flushed into entity dicts before hash / save / snapshot.
## G5 scaffold (ORCH): stub. Until CORE10K fills it in, entity dicts remain the only state.


static func flush(_w: SimWorld) -> void:
	pass
