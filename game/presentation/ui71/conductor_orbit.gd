extends RefCounted
## G7.1 FIRES71 (B6): placing the CONDUCTOR orbit from the radial fire menu ("gunship" slot, roster 5A Q19).
## Press at the orbit centre and drag out to the radius (a click keeps the default radius); Ctrl = clockwise. One
## `conductor_orbit` command {at, radius?, side} (sim/systems/conductor71.gd clamps the radius to its rules).

const CLICK := 0.75


static func make_cmd(centre: Vector2, edge: Vector2, ctrl: bool) -> Dictionary:
	var cmd := {"type": "conductor_orbit", "at": [snappedf(centre.x, 0.01), snappedf(centre.y, 0.01)], "side": -1 if ctrl else 1}
	var r := centre.distance_to(edge)
	if r >= CLICK:
		cmd["radius"] = snappedf(r, 0.1)
	return cmd


## Preview radius in tiles (the drag, or the rules default for a click).
static func preview_r(centre: Vector2, edge: Vector2) -> float:
	var r := centre.distance_to(edge)
	if r >= CLICK:
		return r
	return float(Content.rules().get("g71_conductor", {}).get("radius", 9.0))
