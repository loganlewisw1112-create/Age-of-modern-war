extends RefCounted
## G7 (CNFAC7): Counter-Nanite facility flows: garages, loading, decontamination, lab, range, lockdown, evacuation (6.2).
## ORCH stub: registered in world.gd SYSTEM_ORDER so callers compile from day one.
## The owner replaces the bodies; keep these three static signatures at all times.


static func tick(_w: SimWorld) -> void:
	pass


static func validate_command(_w: SimWorld, cmd: Dictionary) -> String:
	return "%s: not implemented yet" % String(cmd.get("type", ""))


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
