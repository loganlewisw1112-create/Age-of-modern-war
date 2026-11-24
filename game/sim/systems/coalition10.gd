class_name Coalition10
extends RefCounted
## G10 Shadow Coalition facade. Task 2 seeds stage openers; Task 3 deepens doctrine/telemetry.

const FACTION_ID := "shadow_coalition"

## Authoritative Stage 7–10 core gameplay IDs (61). Roster tasks must not rename these.
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


static func _rules() -> Dictionary:
	return Content.rules().get("coalition10", {})


## Legal opener for a Coalition stage: base + builder/gatherer + combat unit defs resolve.
static func validate_stage_opener(stage: int) -> Dictionary:
	var openers: Dictionary = _rules().get("stage_openers", {})
	var row: Dictionary = openers.get(str(stage), {})
	if row.is_empty():
		return {"ok": false, "reason": "missing opener for stage %d" % stage, "stage": stage}
	var base := String(row.get("base", ""))
	var builder := String(row.get("builder", ""))
	var gatherer := String(row.get("gatherer", builder))
	var combat := String(row.get("combat", ""))
	var missing: Array = []
	if Content.building(base).is_empty():
		missing.append("base:%s" % base)
	if Content.unit(builder).is_empty():
		missing.append("builder:%s" % builder)
	if Content.unit(gatherer).is_empty():
		missing.append("gatherer:%s" % gatherer)
	if Content.unit(combat).is_empty():
		missing.append("combat:%s" % combat)
	if not missing.is_empty():
		return {"ok": false, "reason": "unresolved %s" % ",".join(missing), "stage": stage, "opener": row}
	return {
		"ok": true,
		"stage": stage,
		"profile": String(row.get("profile", "")),
		"base": base,
		"builder": builder,
		"gatherer": gatherer,
		"combat": combat,
		"opener": row,
	}
