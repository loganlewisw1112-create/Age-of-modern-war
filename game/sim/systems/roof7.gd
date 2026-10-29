extends RefCounted
## Roof7 (owner: ROOF7). G7_REFERENCE 13.9c-39 (owner choice "Yes, out of reach", 2026-10-28): melee, demolition /
## shaped charges and other short-range ground attacks cannot hit roof-mounted guns (the command-centre CIWS and any
## other roof mount). Guns, rockets, artillery and aircraft still can.
##
## Data-driven:
##  - a building def is a ROOF MOUNT when it carries "roof_mount": true (content/g7/defs_g7_ciws.json cn_ciws7 today);
##  - "short-range ground attack" = a hit whose weapon class is in rules roof7.out_of_reach_classes
##    (content/g7/rules_g7_roof.json; default ["melee", "demolition"]) delivered by a non-air shooter.
##    Why classes, not a range number: every ground weapon with a contact reach (range <= 1.5 tiles) is class melee or
##    demolition (g6_claw, the g5 melee table, g4_charge, g6_satchel, g6_shaped_charge); the only other weapons that
##    short are artillery-class mine / warhead blasts (delivered from above or at the ground, never a reach to a roof)
##    and g6_mimic_dive (an air_low drone: aircraft still hit). Flame (3.5-6 tiles) is a projected stream and stays
##    able to reach, like guns; add "flame" to the rule list to change that.
## Applied at three points, all pure functions of content (no state, no rng; nothing saved):
##  - Combat._g5_ok (target pick / keep / attack orders / attack command validation): such a shooter never picks or
##    keeps a roof mount (Combat.stats carries "roof_out" for the shooter and "roof" for the target, cached per def);
##  - Damage.apply_hit: such a hit on a roof mount does nothing (covers charges detonated at the building's foot,
##    demolition splash and any other caller);
##  - G4bMech.charge_target_error: a breach / plant-charge order on a roof mount is refused ("out of reach").

const DEFAULT_CLASSES := ["melee", "demolition"]


static func classes() -> Array:
	var r = Content.rules().get("roof7")
	if r is Dictionary and (r as Dictionary).get("out_of_reach_classes") is Array:
		return r.out_of_reach_classes
	return DEFAULT_CLASSES


## True when a building def is a roof mount.
static func is_roof_def(def_id: String) -> bool:
	return bool(Content.building(def_id).get("roof_mount", false))


## True when entity t is a roof-mounted building.
static func is_roof(t: Dictionary) -> bool:
	return t.kind == "building" and is_roof_def(String(t.def))


## True when a weapon class cannot reach a roof mount from the ground.
static func class_out(cls: String) -> bool:
	return cls != "" and classes().has(cls)


## True when the shooter is airborne (aircraft keep their reach).
static func shooter_air(shooter: Dictionary) -> bool:
	if shooter.get("kind", "") != "unit":
		return false
	var d: Dictionary = Content.unit(String(shooter.def))
	return bool(d.get("is_air", false)) or String(d.get("move_class", "")).begins_with("air")


## True when this hit (shooter, weapon stats s with "cls", target t) cannot touch t because t is on a roof.
static func shielded(shooter: Dictionary, s: Dictionary, t: Dictionary) -> bool:
	return is_roof(t) and class_out(String(s.get("cls", ""))) and not shooter_air(shooter)
