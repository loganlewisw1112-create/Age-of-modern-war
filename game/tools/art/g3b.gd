extends RefCounted
## G3b + Scale art module (agent ART4): the 12 new units (CONTRACTS_G3b s3.1), the 5 new research /
## comms buildings, their 32x32 icons, POI map decor for MAP4 (manifest.poi_decor) and far-zoom LOD
## icons for R4 (manifest.lod_icons). Appended last to gen_art.gd MODULES; only adds keys, never replaces a
## section built by an earlier module. Sub-modules: g3b_lib, g3b_human_a/_human_b/_machine, g3b_bld,
## g3b_decor, g3b_lod.
const G = preload("res://tools/art/g3b_lib.gd")
const HA = preload("res://tools/art/g3b_human_a.gd")
const HB = preload("res://tools/art/g3b_human_b.gd")
const MA = preload("res://tools/art/g3b_machine.gd")
const BL = preload("res://tools/art/g3b_bld.gd")
const DC = preload("res://tools/art/g3b_decor.gd")
const LOD = preload("res://tools/art/g3b_lod.gd")

## unit id -> [icon facing row, panel accent]
const UNIT_ICONS := {
	"a_old_tank": [0, ""], "a_uav": [0, ""], "a_ew_truck": [0, ""], "a_guided_arty": [0, ""],
	"b_field_gun": [0, "b"], "b_radar_aa": [0, "b"], "b_jammer_truck": [0, "b"], "b_guided_battery": [0, "b"],
	"m_siege_crawler": [1, "m"], "m_swarm": [1, "m"], "m_ew_node": [1, "m"], "m_lancer": [1, "m"],
}
const BUILDING_ICONS := {"research_station": "", "comms_tower": "", "b_drafting_office": "b", "b_signal_mast": "b",
	"m_compute_node": "m"}


static func build(out: Dictionary) -> void:
	HA.build(out)
	HB.build(out)
	MA.build(out)
	BL.build(out)
	DC.build(out)
	LOD.build(out)
	var icons: Dictionary = out.manifest.get("icons", {})
	for id in UNIT_ICONS:
		icons[id] = G.icon_unit(out, id, id, UNIT_ICONS[id][0], UNIT_ICONS[id][1])
	for id in BUILDING_ICONS:
		icons[id] = G.icon_building(out, id, BUILDING_ICONS[id])
	out.manifest["icons"] = icons
