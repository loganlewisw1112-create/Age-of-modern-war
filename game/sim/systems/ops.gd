extends RefCounted
## STUB (owner: agent C2). Officers, groups, delegated missions. Contract: docs/CONTRACTS_G2.md section 4.
## Commands: assign_officer, set_mission, cancel_mission.


static func tick(w: SimWorld) -> void:
	pass


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return "Officer operations not implemented yet."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	pass


## Called by the world for any direct order (move/attack_move/attack/stop/hold) so a member is
## detached from mission control for rules.ops.override_ticks. Stub: no-op.
static func on_direct_order(w: SimWorld, cmd: Dictionary) -> void:
	pass
