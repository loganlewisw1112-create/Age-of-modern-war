extends RefCounted
## G5 naval art module (owner: ART-NAV; CONTRACTS_G5 s3.3 / s8): the 9 ships, Coastal Front decor and
## naval effects. Written by tools/art/g5_naval_gen.gd to res://assets/art/g5_naval/ (own manifest.json,
## same schema as assets/generated/manifest.json; every path is relative to that directory):
##   vehicles        9 ships, 8 facings; frames idle, move (bow spray), fire [+ ramp_half, unload; crawler
##                   + swim, swim_move]; each entry also carries `naval`, `sink` {sink_0..3 sheet, untinted}
##                   and `wake` {3-frame looping sheet drawn UNDER the ship, same pivot}
##   vehicle_wrecks  every ship: burnt hulk settled in shallow water (crawler: burnt on land)
##   icons           every ship id; lod_class "naval" for all 9; lod_icons {"*": {"naval": hull glyph}}
##   specials        {def: {state: frame}} (ramp / unload / swim) for the renderer (VIEW5) to opt into
##   effects         shell splash (large / small), naval muzzle, ramp splash, sink bubbles, bow spray,
##                   burning-ship smoke (fx module)
##   poi_decor       Coastal Front piers, jetty / breakwater, lighthouse, buoys, boathouse, beach obstacles,
##                   sea stacks, island pines, beached hulk, nets, dune grass (coast module)
##   decor           coast_beach / coast_shallow / coast_cliff variants (terrain-code decor, opt-in)
##   terrain_g5      cliff-to-sea transition atlases (surf, cliff_wet) + neighbour rules (opt-in)
## Drawers: g5_naval_a / _b / _m (ships), g5_naval_fx, g5_naval_coast; shared code in g5_naval_lib /
## _sheet / _parts.
const G = preload("res://tools/art/g3b_lib.gd")
const NA = preload("res://tools/art/g5_naval_a.gd")
const NB = preload("res://tools/art/g5_naval_b.gd")
const NM = preload("res://tools/art/g5_naval_m.gd")
const FXN = preload("res://tools/art/g5_naval_fx.gd")
const CO = preload("res://tools/art/g5_naval_coast.gd")

## def -> [icon facing row, icon accent ("" A, "b" B, "m" Machine)]
const UNITS := {
	"a_patrol_boat": [0, ""], "a_landing_craft": [0, ""], "a_destroyer": [0, ""], "a_aa_frigate": [0, ""],
	"b_river_gunboat": [0, "b"], "b_barge_carrier": [0, "b"], "b_monitor": [0, "b"],
	"m_hydro_skiff": [0, "m"], "m_amphib_crawler": [0, "m"],
}
const SPECIALS := {
	"a_landing_craft": {"ramp": "ramp_half", "unload": "unload", "load": "unload"},
	"b_barge_carrier": {"ramp": "ramp_half", "unload": "unload", "load": "unload"},
	"m_hydro_skiff": {"foil": "move"},
	"m_amphib_crawler": {"ramp": "ramp_half", "unload": "unload", "load": "unload", "swim": "swim",
		"swim_move": "swim_move"},
}


static func build(out: Dictionary) -> void:
	NA.build(out)
	NB.build(out)
	NM.build(out)
	FXN.build(out)
	CO.build(out)
	var icons: Dictionary = out.manifest.get("icons", {})
	var lod: Dictionary = out.manifest.get("lod_class", {})
	for id in UNITS:
		icons[id] = G.icon_unit(out, id, id, UNITS[id][0], UNITS[id][1])
		lod[id] = "naval"
	out.manifest["icons"] = icons
	out.manifest["lod_class"] = lod
	out.manifest["specials"] = SPECIALS.duplicate(true)
