extends RefCounted
## G5 art module (owner: ART-U5; CONTRACTS_G5 s3.1): the 16 new human ground units, m_maint_swarm and the
## 8 launched drones. Written by tools/art/g5_units_gen.gd to res://assets/art/g5_units/ (own manifest.json,
## same schema as assets/generated/manifest.json; every path is relative to that directory):
##   infantry        squads: 48x36 frames, pivot (24, 28), 8 facings, `squad_size`, `alive_sheets`
##   vehicles        vehicles, the swarm and the drones (drones carry `air`, `alt_px`, `shadow`)
##   vehicle_wrecks  every vehicle, the swarm and every drone
##   icons           every unit id (production ids == unit ids) and every drone id
##   lod_class       every id: infantry | vehicle_light | air
##   effects         g5 wounded markers, red cross, drone trail / EMP pulse (fx module)
##   specials        {def: {state: frame}}: which column shows deploy / launch / carry / wounded / tactical
## Drawers: g5_units_inf_a/b (squads), g5_units_veh_a/b (vehicles), g5_units_m (swarm), g5_units_drone,
## g5_units_fx; shared code in g5_units_lib / _sq / _fig.
const G = preload("res://tools/art/g3b_lib.gd")
const IA = preload("res://tools/art/g5_units_inf_a.gd")
const IB = preload("res://tools/art/g5_units_inf_b.gd")
const VA = preload("res://tools/art/g5_units_veh_a.gd")
const VB = preload("res://tools/art/g5_units_veh_b.gd")
const MS = preload("res://tools/art/g5_units_m.gd")
const DR = preload("res://tools/art/g5_units_drone.gd")
const FXU = preload("res://tools/art/g5_units_fx.gd")

## def -> [icon facing row, icon accent ("" A, "b" B, "m" Machine), lod class]
const UNITS := {
	"a_medic_team": [1, "", "infantry"], "a_hmg_team": [1, "", "infantry"],
	"a_special_forces": [1, "", "infantry"], "a_drone_team": [1, "", "infantry"],
	"a_airfield_engineers": [1, "", "infantry"],
	"b_grenadiers": [1, "b", "infantry"], "b_shock_troops": [1, "b", "infantry"],
	"b_at_rocket_team": [1, "b", "infantry"], "b_drone_team": [1, "b", "infantry"],
	"b_airfield_engineers": [1, "b", "infantry"],
	"a_spaag": [0, "", "vehicle_light"], "a_recon_car": [0, "", "vehicle_light"], "a_ambulance": [0, "", "vehicle_light"],
	"b_armored_car": [0, "b", "vehicle_light"], "b_field_ambulance": [0, "b", "vehicle_light"],
	"m_maint_swarm": [0, "m", "vehicle_light"],
	"a_drone_strike": [0, "", "air"], "a_drone_frag": [0, "", "air"], "a_drone_recon": [0, "", "air"],
	"a_drone_emp": [0, "", "air"],
	"b_drone_strike": [0, "b", "air"], "b_drone_frag": [0, "b", "air"], "b_drone_recon": [0, "b", "air"],
	"b_drone_emp": [0, "b", "air"],
}
const DRONE_SPECIALS := {"dive": "dive", "trail": "trail", "attack": "fire"}
## Semantic state -> frame column, for the renderer (VIEW5) to opt into.
const SPECIALS := {
	"a_medic_team": {"heal": "heal", "carry": "carry", "wounded": "wounded"},
	"a_hmg_team": {"deploy": "deploy", "deployed": "deployed", "wounded": "wounded"},
	"a_special_forces": {"tactical": "stance", "work": "work", "wounded": "wounded"},
	"a_drone_team": {"launch": "launch", "tactical": "tactical", "wounded": "wounded"},
	"a_airfield_engineers": {"work": "work", "wounded": "wounded"},
	"b_grenadiers": {"wounded": "wounded"},
	"b_shock_troops": {"tactical": "stance", "wounded": "wounded"},
	"b_at_rocket_team": {"deployed": "deployed", "wounded": "wounded"},
	"b_drone_team": {"launch": "launch", "tactical": "tactical", "wounded": "wounded"},
	"b_airfield_engineers": {"work": "work", "wounded": "wounded"},
	"a_ambulance": {"unload": "unload", "load": "unload", "beacon": "fire"},
	"b_field_ambulance": {"unload": "unload", "load": "unload", "beacon": "fire"},
	"m_maint_swarm": {"work": "work"},
}


static func build(out: Dictionary) -> void:
	IA.build(out)
	IB.build(out)
	VA.build(out)
	VB.build(out)
	MS.build(out)
	DR.build(out)
	FXU.build(out)
	var icons: Dictionary = out.manifest.get("icons", {})
	var lod: Dictionary = out.manifest.get("lod_class", {})
	for id in UNITS:
		icons[id] = G.icon_unit(out, id, id, UNITS[id][0], UNITS[id][1])
		lod[id] = UNITS[id][2]
	out.manifest["icons"] = icons
	out.manifest["lod_class"] = lod
	var spec: Dictionary = SPECIALS.duplicate(true)
	for fac in ["a", "b"]:
		for kind in DR.KINDS:
			spec["%s_drone_%s" % [fac, kind]] = DRONE_SPECIALS.duplicate()
	out.manifest["specials"] = spec
