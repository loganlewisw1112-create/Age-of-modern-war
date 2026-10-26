extends RefCounted
## G6 art module root (owner: ART-G6; CONTRACTS_G6 s3.1): the 89 page assets of docs/g6_art_kit (minus the
## deferred x_* 4th faction), written by tools/art/g6_art_gen.gd into two groups (own manifest.json each,
## same schema as assets/generated/manifest.json, paths relative to the group folder):
##   assets/art/g6_units/  infantry (squads; 48x36 frames, b_conscripts 64x44, `squad_size`, `alive_sheets`),
##                         vehicles (+ ships / aircraft / drones with their air / naval keys), vehicle_wrecks,
##                         icons (every unit id), lod_class (every unit id), specials {def: {state: frame}}
##   assets/art/g6_bld/    buildings (every building id: rot_<f>, rot_<f>_damaged, rot_<f>_build_<0..2> for
##                         f = 0..3; built / damaged / build_<0..2> = rotation 0; see g6_lib.bld), icons,
##                         g6_bld {defs, state_rules, variants}
## Drawers: g6_turrets, g6_forts, g6_dronebld, g6_vehicles, g6_infantry, g6_seaair, g6_horizon (ported kit);
## g6_new (+ g6_new_units, g6_new_suits): the CONTRACTS_G6 s3.2 pieces (ART-G6b).
const G = preload("res://tools/art/g3b_lib.gd")
const FL = preload("res://tools/art/g4_fort_lib.gd")
const H = preload("res://tools/art/g6_lib.gd")
const MODS := {
	"g6_turrets": preload("res://tools/art/g6_turrets.gd"),
	"g6_forts": preload("res://tools/art/g6_forts.gd"),
	"g6_dronebld": preload("res://tools/art/g6_dronebld.gd"),
	"g6_vehicles": preload("res://tools/art/g6_vehicles.gd"),
	"g6_infantry": preload("res://tools/art/g6_infantry.gd"),
	"g6_seaair": preload("res://tools/art/g6_seaair.gd"),
	"g6_horizon": preload("res://tools/art/g6_horizon.gd"),
	"g6_new": preload("res://tools/art/g6_new.gd"),
	"g6_icons": preload("res://tools/art/g6_icons.gd"),
}

## Unit id -> [icon facing row, lod class]. CONTRACTS_G6 s3.1 U and S ids (52).
const UNITS := {
	"a_aerostat": [0, "vehicle_light"], "a_loiter_truck": [0, "vehicle_light"],
	"b_jammer_team": [1, "infantry"], "b_scrap_aa": [1, "infantry"],
	"m_swarm_queen": [0, "air"], "m_mimic_drone": [0, "air"],
	"a_sp_howitzer": [0, "artillery"], "a_mlrs": [0, "artillery"], "a_mine_clearer": [0, "vehicle_light"],
	"a_bridge_layer": [0, "vehicle_light"], "a_command_vehicle": [0, "vehicle_light"], "a_ugv": [0, "vehicle_light"],
	"b_landship": [0, "vehicle_heavy"], "b_flak_halftrack": [0, "vehicle_light"], "b_armored_dozer": [0, "vehicle_light"],
	"b_salvage_crane": [0, "vehicle_light"], "b_moto_scouts": [0, "vehicle_light"],
	"m_spider_layer": [0, "vehicle_light"], "m_hover_tank": [0, "vehicle_heavy"], "m_colossus": [0, "vehicle_heavy"],
	"m_assimilator": [0, "vehicle_heavy"],
	"a_marines": [1, "infantry"], "a_paratroopers": [1, "infantry"], "a_eod": [1, "infantry"], "a_jtac": [1, "infantry"],
	"a_manpads": [1, "infantry"], "b_conscripts": [1, "infantry"], "b_satchel_sappers": [1, "infantry"],
	"b_marksman": [1, "infantry"], "b_propaganda_team": [1, "infantry"],
	"m_shield_drone": [0, "air"], "m_stalker_synth": [0, "infantry"], "m_repair_swarm2": [0, "vehicle_light"],
	"m_breacher_crawler": [0, "infantry"],
	"a_awacs": [0, "air"], "a_airlift": [0, "air"], "b_recon_plane": [0, "air"], "m_stealth_drone": [0, "air"],
	"a_supply_ship_a": [0, "naval"], "a_minesweeper": [0, "naval"], "a_hovercraft": [0, "naval"], "a_carrier": [0, "naval"],
	"a_submarine": [0, "naval"], "b_supply_ship_b": [0, "naval"], "b_mine_barge": [0, "naval"], "b_aa_barge": [0, "naval"],
	"m_charge_tender": [0, "naval"], "m_lance_cruiser": [0, "naval"],
	"b_armored_train": [0, "vehicle_heavy"],
	"a_laser_tank": [0, "vehicle_heavy"], "a_exo_trooper": [0, "infantry"], "b_rhomboid": [0, "vehicle_heavy"],
	# CONTRACTS_G6 s3.2 (ART-G6b, tools/art/g6_new*.gd): officers, Machine command nodes, exo suits
	"a_commander": [1, "infantry"], "a_captain": [1, "infantry"], "a_lieutenant": [1, "infantry"],
	"b_commander": [1, "infantry"], "b_captain": [1, "infantry"], "b_lieutenant": [1, "infantry"],
	"m_commander": [1, "vehicle_light"], "m_captain": [1, "vehicle_light"], "m_lieutenant": [1, "vehicle_light"],
	"a_exo_rifle": [1, "vehicle_light"], "a_exo_missile": [1, "vehicle_light"], "a_exo_aa": [1, "vehicle_light"],
}
## CONTRACTS_G6 s3.1 B ids (37), all drawn with g6_lib.bld (4 rotations + damaged + build stages).
const BLDS := ["a_atgm_bunker", "a_sam_site", "a_laser_ciws", "a_howitzer_pit", "a_popup_turret",
	"b_pak_nest", "b_flak_battery", "b_net_post", "b_mortar_pit", "b_pillbox",
	"m_arc_pylon", "m_pulse_spire2", "m_jammer_obelisk", "m_mass_driver", "m_sentry_mine",
	"m_nanite_wall", "m_phase_gate", "s_sandbags", "s_trench", "s_tank_traps", "s_barbed_wire", "s_minefield",
	"s_garrison_bld", "s_camo_decoy", "a_drone_cc", "b_fpv_workshop", "m_hive_node",
	"a_radar_station", "a_fob", "a_repair_bay", "a_cruise_battery", "b_rail_yard", "b_scrapyard",
	"b_propaganda_tower", "m_nanite_forge", "m_overmind", "m_relay_lattice",
	"a_company_hq", "b_company_hq", "m_company_hq", "a_exo_garage"]  # s3.2 (ART-G6b)
## Frame names that are plain animation, not a semantic special state.
const PLAIN := ["idle", "move", "walk_a", "walk_b"]


static func accent(id: String) -> String:
	match id.substr(0, 2):
		"b_":
			return "b"
		"m_":
			return "m"
	return ""


static func new_out(group: String) -> Dictionary:
	return {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": group}}


## Runs the drawer modules (all when mods is empty). Returns {"units": out, "bld": out}.
static func generate(mods: Array = []) -> Dictionary:
	var out := new_out("g6_units")
	var bo := new_out("g6_bld")
	out["bld_out"] = bo
	for m in MODS:
		if mods.is_empty() or mods.has(m):
			MODS[m].build(out)
	out.erase("bld_out")
	preload("res://tools/art/g61_anim.gd").build(out)  # G6.1 (ANIMA61): infantry animation set
	preload("res://tools/art/g61_anim_veh.gd").build(out)  # G6.1 (ANIMB61): vehicle/air/naval/walker animation frames
	finish_units(out)
	finish_bld(bo)
	return {"units": out, "bld": bo}


static func finish_units(out: Dictionary) -> void:
	var icons: Dictionary = out.manifest.get("icons", {})
	var lod: Dictionary = out.manifest.get("lod_class", {})
	var spec: Dictionary = out.manifest.get("specials", {})
	for id in UNITS:
		var sp: Dictionary = out.manifest.get("infantry", {}).get(id, out.manifest.get("vehicles", {}).get(id, {}))
		if sp.is_empty():
			continue
		icons[id] = G.icon_unit(out, id, id, UNITS[id][0], accent(id))
		lod[id] = UNITS[id][1]
		var st := {}
		for fr in sp.frames:
			if not PLAIN.has(String(fr)):
				st[String(fr)] = String(fr)
		if not st.is_empty():
			spec[id] = st
	out.manifest["icons"] = icons
	out.manifest["lod_class"] = lod
	out.manifest["specials"] = spec
	out.manifest["g6_units"] = {"defs": UNITS.keys(), "squad_frames": {"b_conscripts": [64, 44]},
		"note": "squads use 48x36 frames except where infantry.<def>.fw/fh says otherwise (b_conscripts 64x44)"}


static func finish_bld(bo: Dictionary) -> void:
	var man: Dictionary = bo.manifest.get("buildings", {})
	var icons: Dictionary = bo.manifest.get("icons", {})
	var v := {}
	for id in BLDS:
		if not man.has(id):
			continue
		var s: Dictionary = man[id].states.built
		icons[id] = FL.icon(bo, id, String(s.file), String(s.mask), accent(id))
		v[id] = "rot"
	bo.manifest["icons"] = icons
	bo.manifest["g6_bld"] = {"defs": BLDS.duplicate(), "variants": v, "state_rules": {
		"rot": "facing_i / rotation f (0..3) -> rot_<f>; under 50% hp rot_<f>_damaged; under construction rot_<f>_build_<0..2>; built / damaged / build_<n> = rotation 0"}}
