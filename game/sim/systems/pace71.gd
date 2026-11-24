extends RefCounted
## Pre-G10 PACE71: global vehicle locomotion tempo. Acceleration/turn/deploy systems remain separate.

const Creep = preload("res://sim/systems/creep.gd")


static func R() -> Dictionary:
	var r = Content.rules().get("g71_pace71", {})
	return r if r is Dictionary else {}


static func is_vehicle(e: Dictionary) -> bool:
	var mc := String(Content.unit(String(e.get("def", ""))).get("move_class", "foot"))
	return mc in ["vehicle", "amphibious", "hover"]


## Multiplier applied at the shared movement advance, so native and fallback paths match.
## Terrain.speed_mult already contributes 1.25 on roads; road_correction makes the combined bonus ~1.20.
static func speed_mult(w: SimWorld, e: Dictionary, pos: Vector2) -> float:
	if not is_vehicle(e):
		return 1.0
	var r := R()
	var mult := float(r.get("open_mult", 1.7))
	var cell := w.cell_of(pos)
	var code := w.terrain_at(cell)
	if code == Terrain.ROAD or code == Terrain.BRIDGE or code == Terrain.RAIL:
		mult *= float(r.get("road_correction", 0.96))
	if Creep.on_creep(w, cell) or bool(e.get("g71_mud", false)) or bool(e.get("g71_rubble", false)):
		mult *= float(r.get("hostile_ground_mult", 0.7))
	return mult
