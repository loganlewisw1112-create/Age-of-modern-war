extends RefCounted
## G7 (CNSIM7): advanced APC systems: unhackable, shield dome, active protection, anti-drone emitter, EMP pulse, side panels (6.5-6.6).
## ORCH stub: registered in world.gd SYSTEM_ORDER so callers compile from day one.
## The owner replaces the bodies; keep these three static signatures at all times.


static func tick(_w: SimWorld) -> void:
	pass


static func validate_command(_w: SimWorld, cmd: Dictionary) -> String:
	return "%s: not implemented yet" % String(cmd.get("type", ""))


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
