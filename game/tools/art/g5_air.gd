extends RefCounted
## G5 aircraft art module (agent ART-AIR; CONTRACTS_G5 s3.2 / s7): the 13 aircraft in content/g5/air.json.
## Written by tools/art/g5_air_gen.gd to res://assets/art/g5_air/ (own manifest.json, same schema as
## assets/generated/manifest.json; every path is relative to that directory):
##   vehicles        every aircraft, flagged `air` with altitude / bob / shadow (m_drone schema) plus
##                   shadow_sheet, ground_frames, alt_scale, anim, aircraft class, sling (g5_air_sheet.gd)
##   vehicle_wrecks  every aircraft (crashed airframe on the ground)
##   icons           every aircraft id (production ids == unit ids)
##   lod_class       every id: air
##   specials        {def: {state: frame}}: AIRSYS flight phase (air.gd) / action -> frame column
##   effects         bombs, blasts, missiles + trails, smoke, rotor wash, afterburner, flak (g5_air_fx)
## Drawers: g5_air_a (Human A), g5_air_b (Human B), g5_air_m (Machine); shared: g5_air_parts / _sheet /
## _raster / _mesh.
const G = preload("res://tools/art/g3b_lib.gd")
const A = preload("res://tools/art/g5_air_a.gd")
const B = preload("res://tools/art/g5_air_b.gd")
const M = preload("res://tools/art/g5_air_m.gd")
const FX = preload("res://tools/art/g5_air_fx.gd")

## def -> [icon facing row, icon accent ("" A, "b" B, "m" Machine)]
const UNITS := {
	"a_attack_heli": [1, ""], "a_transport_gunship": [1, ""], "a_strike_jet": [1, ""], "a_interceptor": [1, ""],
	"a_vtol_dropship": [1, ""],
	"b_gunship": [1, "b"], "b_heavy_lift": [1, "b"], "b_bomber": [1, "b"], "b_vtol_dropship": [1, "b"],
	"m_drone_carrier": [1, "m"], "m_lifter_drone": [1, "m"], "m_interceptor_swarm": [1, "m"], "m_micro_drone": [1, "m"],
}
## AIRSYS flight phases (sim/systems/air.gd) and actions -> frame, per aircraft class.
const PHASES := {
	"heli": {"air": "idle", "ret": "move", "move": "move", "fire": "fire", "landed": "landed", "parked": "parked"},
	"lift": {"air": "idle", "ret": "move", "move": "move", "fire": "fire", "landed": "landed", "parked": "parked",
		"sling": "sling", "sling_hook": "sling_hook", "unload": "unload", "load": "unload"},
	"jet": {"air": "idle", "sortie": "move", "ret": "move", "move": "move", "holding": "idle", "fire": "fire",
		"taxi": "taxi", "hold": "taxi", "taxi_in": "taxi", "roll": "roll", "approach": "landing",
		"parked": "parked", "landed": "parked"},
	"vtol": {"air": "idle", "ret": "move", "move": "move", "fire": "fire", "hover": "hover", "approach": "landing",
		"landed": "landed", "parked": "parked", "unload": "unload", "load": "unload", "sling": "sling",
		"sling_hook": "sling_hook"},
	"micro": {"air": "idle", "move": "move", "fire": "fire", "landed": "landed", "parked": "landed"},
}


static func build(out: Dictionary) -> void:
	A.build(out)
	B.build(out)
	M.build(out)
	FX.build(out)
	var icons: Dictionary = out.manifest.get("icons", {})
	var lod: Dictionary = out.manifest.get("lod_class", {})
	var spec: Dictionary = out.manifest.get("specials", {})
	for id in UNITS:
		icons[id] = G.icon_unit(out, id, id, UNITS[id][0], UNITS[id][1])
		lod[id] = "air"
		spec[id] = PHASES[String(out.manifest.vehicles[id].aircraft)].duplicate()
	out.manifest["icons"] = icons
	out.manifest["lod_class"] = lod
	out.manifest["specials"] = spec
