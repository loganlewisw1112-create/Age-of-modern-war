extends SceneTree
## G10 CORE10 roster audit — Stage 7–10 core gameplay closure.
## Usage: godot --headless --path game -s res://tools/g10_roster_audit.gd
## Prints JSON summary + CORE_GAMEPLAY_DEFS / ORPHANS / ROLE_GAPS lines.

const CORE_IDS := [
	"x_cell_rifle", "x_cell_at", "x_cell_sapper", "x_cell_medic", "x_ambush_cell", "x_sleeper_cell",
	"x_backdoor_hacker", "x_broker", "x_pmc_rifle", "x_pmc_assault", "x_pmc_sniper", "x_pmc_ew", "x_officer",
	"x_ghost_infiltrator",
	"x_technical_mg", "x_technical_rocket", "x_technical_aa", "x_technical_mortar", "x_technical_recoilless",
	"x_captured_tank", "x_refit_ifv", "x_shock_truck", "x_stealth_apc", "x_ghost_runner", "x_exo_mule",
	"x_recovery_truck", "x_ghost_drone_carrier", "x_prototype_walker",
	"x_stealth_drone", "x_shock_drone", "x_recon_drone", "x_silent_rotor", "x_stealth_transport", "x_patron_cas",
	"x_river_ghost", "x_mini_sub", "x_smuggler_boat", "x_patrol_boat",
	"x_death_strike", "x_death_assault", "x_death_recon", "x_shadow_pathfinder", "x_shadow_ew",
	"x_shadow_signal", "x_shadow_decoy", "x_anchor_tech", "x_anchor_medic",
	"x_safehouse", "x_tunnel_entrance", "x_cache", "x_weld_shop", "x_black_market", "x_broker_exchange",
	"x_patron_office", "x_disguised_workshop", "x_bunker_hatch", "x_underground_barracks",
	"x_underground_factory", "x_ghost_complex", "x_forward_repair", "x_vault_core",
]

const ROLE_KEYS := [
	"hq", "power", "depot", "barracks", "factory", "refinery", "defense",
	"builder", "gatherer", "infantry", "antitank", "recon", "light", "heavy",
	"artillery", "officer", "supply", "air",
]

const MOVE_OK := {
	"foot": true, "vehicle": true, "amphibious": true, "naval_small": true, "naval": true,
	"air": true, "air_low": true, "air_high": true,
}


func _initialize() -> void:
	Content.load_all()
	ArtCatalog.load_all()
	var summary := audit()
	print(JSON.stringify(summary))
	print("CORE_GAMEPLAY_DEFS %d" % int(summary.get("core_gameplay_defs", 0)))
	print("ORPHANS %d" % int((summary.get("orphan_defs", []) as Array).size()))
	print("ROLE_GAPS %d" % int((summary.get("role_gaps", []) as Array).size()))
	var code := 0
	if int(summary.get("core_gameplay_defs", 0)) < 60:
		code = 2
	if not (summary.get("orphan_defs", []) as Array).is_empty():
		code = 3
	if not (summary.get("role_gaps", []) as Array).is_empty():
		code = 4
	quit(code)


func audit() -> Dictionary:
	var units: Array = []
	var buildings: Array = []
	var production: Array = []
	var orphan_defs: Array = []
	var orphan_art: Array = []
	var role_gaps: Array = []
	var seen := {}
	var man: Dictionary = ArtCatalog.manifest()
	var icon_sec: Dictionary = man.get("icons", {}) if man.get("icons") is Dictionary else {}
	var unit_secs: Array = []
	for sec in ["infantry", "vehicles", "air", "naval", "units"]:
		if man.get(sec) is Dictionary:
			unit_secs.append(man[sec])

	for id in CORE_IDS:
		if seen.has(id):
			orphan_defs.append("%s:duplicate_id" % id)
			continue
		seen[id] = true
		var u: Dictionary = Content.unit(id)
		var b: Dictionary = Content.building(id)
		if u.is_empty() == b.is_empty():
			orphan_defs.append("%s:not_unit_xor_building" % id)
			continue
		if not u.is_empty():
			units.append(id)
			_audit_unit(id, u, production, orphan_defs)
			if not _art_present(id, icon_sec, unit_secs):
				orphan_art.append(id)
		else:
			buildings.append(id)
			_audit_building(id, b, orphan_defs)
			if not _art_present(id, icon_sec, unit_secs):
				orphan_art.append(id)

	for stage in [7, 8, 9, 10]:
		for role in ROLE_KEYS:
			var rid := Content.role("shadow_coalition", role, stage)
			# Empty mapping (stage_roles override or absent role) is faction policy, not a roster gap.
			if rid == "":
				continue
			var is_bld: bool = role in ["hq", "power", "depot", "barracks", "factory", "refinery", "defense"]
			var d: Dictionary = Content.building(rid) if is_bld else Content.unit(rid)
			if d.is_empty():
				role_gaps.append("%s@%d:missing_def:%s" % [role, stage, rid])
			elif String(d.get("faction", "")) != "shadow_coalition":
				role_gaps.append("%s@%d:cross_faction:%s" % [role, stage, rid])
			elif not Content.available(d, stage):
				role_gaps.append("%s@%d:stage_gate:%s" % [role, stage, rid])

	return {
		"units": units.size(),
		"buildings": buildings.size(),
		"production": production.size(),
		"orphan_defs": orphan_defs,
		"orphan_art": orphan_art,
		"role_gaps": role_gaps,
		"core_gameplay_defs": units.size() + buildings.size(),
		"unit_ids": units,
		"building_ids": buildings,
	}


func _audit_unit(id: String, u: Dictionary, production: Array, orphan_defs: Array) -> void:
	if String(u.get("faction", "")) != "shadow_coalition":
		orphan_defs.append("%s:bad_faction" % id)
	if not u.has("stage_min") or not u.has("stage_max"):
		orphan_defs.append("%s:missing_stage" % id)
	var mc := String(u.get("move_class", ""))
	if not MOVE_OK.has(mc):
		orphan_defs.append("%s:bad_move_class:%s" % [id, mc])
	if int(u.get("pop", 0)) <= 0:
		orphan_defs.append("%s:bad_pop" % id)
	var cost: Dictionary = u.get("cost", {})
	if cost.is_empty() or int(cost.get("credits", -1)) < 0:
		orphan_defs.append("%s:missing_cost" % id)
	var wpn := String(u.get("weapon", ""))
	if wpn == "" or Content.weapon(wpn).is_empty():
		orphan_defs.append("%s:bad_weapon:%s" % [id, wpn])
	var prod: Dictionary = Content.production(id)
	if prod.is_empty():
		orphan_defs.append("%s:missing_production" % id)
		return
	production.append(id)
	if String(prod.get("faction", "")) != "shadow_coalition":
		orphan_defs.append("%s:prod_cross_faction" % id)
	var fac := String(prod.get("facility", ""))
	var fb: Dictionary = Content.building(fac)
	if fb.is_empty() or String(fb.get("faction", "")) != "shadow_coalition":
		orphan_defs.append("%s:orphan_or_cross_facility:%s" % [id, fac])
	var pc: Dictionary = prod.get("cost", {})
	if pc.is_empty() or int(pc.get("credits", -1)) < 0:
		orphan_defs.append("%s:prod_missing_cost" % id)


func _audit_building(id: String, b: Dictionary, orphan_defs: Array) -> void:
	if String(b.get("faction", "")) != "shadow_coalition":
		orphan_defs.append("%s:bad_faction" % id)
	if not b.has("stage_min") or not b.has("stage_max"):
		orphan_defs.append("%s:missing_stage" % id)
	var cost: Dictionary = b.get("cost", {})
	if cost.is_empty():
		orphan_defs.append("%s:missing_cost" % id)
	for req in b.get("requires", []):
		if Content.building(String(req)).is_empty():
			orphan_defs.append("%s:bad_requires:%s" % [id, req])


func _art_present(id: String, icons: Dictionary, unit_secs: Array) -> bool:
	if icons.has(id):
		return true
	for sec in unit_secs:
		if sec.has(id):
			return true
	# ART10 samples / full catalog may land later; also accept on-disk group path.
	var p := "res://assets/art/g10_coalition/manifest.json"
	if FileAccess.file_exists(p):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			for sec_name in parsed:
				var v = parsed[sec_name]
				if v is Dictionary and v.has(id):
					return true
	return false
