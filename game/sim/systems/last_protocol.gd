extends RefCounted
## G7 (LPMODE7): the Last Protocol mode rules: creep meter, countdown, phases, the Tide, endings, set pieces, secrets, score (section 10, 13).
## ORCH stub: registered in world.gd SYSTEM_ORDER so callers compile from day one.
## The owner replaces the bodies; keep these three static signatures at all times.


static func tick(_w: SimWorld) -> void:
	pass


static func validate_command(_w: SimWorld, cmd: Dictionary) -> String:
	return "%s: not implemented yet" % String(cmd.get("type", ""))


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
