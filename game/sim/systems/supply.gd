extends RefCounted
## STUB (owner: agent B2). Ammo/fuel consumption + resupply. Contract: docs/CONTRACTS_G2.md section 3.


static func tick(w: SimWorld) -> void:
	pass


## Called by combat._fire once per shot fired by a unit (consume 1 round).
static func on_shot(w: SimWorld, e: Dictionary) -> void:
	pass
