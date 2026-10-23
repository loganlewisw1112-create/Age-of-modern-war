extends RefCounted
## STUB (owner: agent C2). Destructible / repairable bridge. Contract: docs/CONTRACTS_G2.md section 4.
## world.destroy() delegates kind "structure" here instead of erasing the entity.


static func tick(w: SimWorld) -> void:
	pass


## The bridge structure reached hp <= 0. Stub: indestructible until agent C2 lands.
static func on_destroyed(w: SimWorld, e: Dictionary, killer_owner: int) -> void:
	e.hp = 1.0
