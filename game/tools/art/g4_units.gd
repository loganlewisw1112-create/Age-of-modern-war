extends RefCounted
## G4 art module (owner: ART-U; CONTRACTS_G4 s8): the 8 G4b human units, their effects and the G4e editor
## tool icons. Registered last in tools/gen_art.gd MODULES by ORCH. Only ADDS keys to existing manifest
## sections (infantry, vehicles, vehicle_wrecks, effects, icons) plus two new sections:
##   lod_class     {def: lod_icons class} (far-zoom class per unit; renderer CR to prefer it)
##   editor_icons  {tool id: icon path}
## Frame columns (renderer looks frames up by name; extras sit AFTER the standard ones):
##   a_sniper, b_flamer          idle, walk_a, walk_b, fire
##   a_mortar                    idle, walk_a, walk_b, fire, deployed   (deployed = set up on its bipod)
##   a_combat_engineer           idle, walk_a, walk_b, fire, work       (work = kneeling, laying a mine)
##   a_apc, b_halftrack          idle, move, fire, unload               (unload = rear ramp/doors open)
##   b_rocket_truck              idle, move, fire                       (fire = rocket salvo)
##   b_scrap_mech                idle, walk_a, walk_b, fire, move       (legged: true)
## Drawers: g4_units_inf.gd (foot), g4_units_a.gd (APC), g4_units_b.gd (halftrack, rocket truck),
## g4_units_mech.gd (scrap mech), g4_units_fx.gd (effects), g4_editor.gd (editor icons).
const G = preload("res://tools/art/g3b_lib.gd")
const INF = preload("res://tools/art/g4_units_inf.gd")
const VA = preload("res://tools/art/g4_units_a.gd")
const VB = preload("res://tools/art/g4_units_b.gd")
const MECH = preload("res://tools/art/g4_units_mech.gd")
const FXU = preload("res://tools/art/g4_units_fx.gd")
const ED = preload("res://tools/art/g4_editor.gd")

## def -> [icon facing row, icon panel accent ("" Human A, "b" Human B), lod class]
const UNITS := {
	"a_apc": [1, "", "vehicle_light"],
	"a_sniper": [1, "", "infantry"],
	"a_mortar": [1, "", "infantry"],
	"a_combat_engineer": [1, "", "infantry"],
	"b_flamer": [1, "b", "infantry"],
	"b_halftrack": [1, "b", "vehicle_light"],
	"b_scrap_mech": [1, "b", "vehicle_heavy"],
	"b_rocket_truck": [1, "b", "artillery"],
}


static func build(out: Dictionary) -> void:
	INF.build(out)
	VA.build(out)
	VB.build(out)
	MECH.build(out)
	FXU.build(out)
	var icons: Dictionary = out.manifest.get("icons", {})
	var lod: Dictionary = out.manifest.get("lod_class", {})
	for id in UNITS:  # production ids == unit ids for all 8
		icons[id] = G.icon_unit(out, id, id, UNITS[id][0], UNITS[id][1])
		lod[id] = UNITS[id][2]
	out.manifest["icons"] = icons
	out.manifest["lod_class"] = lod
	ED.build(out)
