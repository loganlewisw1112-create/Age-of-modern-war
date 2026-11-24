extends "res://tests/test_base.gd"
## G10 Task 1: Shadow Coalition registry + 61-core fragment seed.

const G10_CORE_IDS := [
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


func test_shadow_coalition_registered() -> void:
	Content.load_all()
	var f: Dictionary = Content.faction("shadow_coalition")
	check(not f.is_empty(), "shadow_coalition faction missing")
	check_eq(String(f.get("archetype", "")), "Coalition", "archetype")
	check(Content.faction_ids().has("shadow_coalition"), "faction_ids includes shadow_coalition")


func test_shadow_roles_and_start_units_resolve() -> void:
	Content.load_all()
	for role in ROLE_KEYS:
		var rid := Content.role("shadow_coalition", role)
		check(rid != "", "role %s empty" % role)
		var is_bld: bool = role in ["hq", "power", "depot", "barracks", "factory", "refinery", "defense"]
		var d: Dictionary = Content.building(rid) if is_bld else Content.unit(rid)
		check(not d.is_empty(), "role %s def %s missing" % [role, rid])
		check_eq(String(d.get("faction", "")), "shadow_coalition", "role %s faction" % role)
	var fac: Dictionary = Content.faction("shadow_coalition")
	var starts: Array = fac.get("start_units", [])
	check(starts.size() > 0, "start_units empty")
	for sid in starts:
		var u: Dictionary = Content.unit(String(sid))
		check(not u.is_empty(), "start unit %s missing" % sid)
	var c := SimWorld.default_config()
	c.sides = [
		{"faction": "shadow_coalition", "stage": 8, "credits": 5000, "ai": false, "name": "X", "team": 0},
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "A", "team": 1},
	]
	var w := SimWorld.new_match(c)
	var hq_def := Content.role("shadow_coalition", "hq")
	check_eq(w.buildings_of(0, hq_def).size(), 1, "Coalition HQ placed")
	check(w.units_of(0).size() >= 1, "Coalition start units spawned")


func test_g10_fragments_load_after_g71() -> void:
	Content.load_all()
	var dirs: Array = Content.FRAGMENT_DIRS
	var i71 := dirs.find("res://content/g71")
	var i10 := dirs.find("res://content/g10")
	check(i71 >= 0 and i10 >= 0, "g71 and g10 fragment dirs present")
	check(i10 > i71, "g10 must merge after g71")
	check(not Content.unit("x_cell_rifle").is_empty(), "x_cell_rifle from g10 fragment")
	check(not Content.building("x_safehouse").is_empty(), "x_safehouse from g10 fragment")
	check(not Content.production("x_cell_rifle").is_empty(), "x_cell_rifle production from g10")


func test_core_manifest_has_at_least_60_gameplay_defs() -> void:
	Content.load_all()
	check_eq(G10_CORE_IDS.size(), 61, "manifest size")
	var seen := {}
	var units_n := 0
	var blds_n := 0
	for id in G10_CORE_IDS:
		check(not seen.has(id), "duplicate core id %s" % id)
		seen[id] = true
		var u: Dictionary = Content.unit(id)
		var b: Dictionary = Content.building(id)
		check(u.is_empty() != b.is_empty(), "id %s must be unit XOR building" % id)
		if not u.is_empty():
			units_n += 1
			check_eq(String(u.get("faction", "")), "shadow_coalition", "%s faction" % id)
			var prod: Dictionary = Content.production(id)
			check(not prod.is_empty(), "%s missing production" % id)
			var fac := String(prod.get("facility", ""))
			check(not Content.building(fac).is_empty(), "%s facility %s missing" % [id, fac])
		else:
			blds_n += 1
			check_eq(String(b.get("faction", "")), "shadow_coalition", "%s faction" % id)
	check(units_n + blds_n >= 60, "core gameplay defs >= 60 (got %d)" % (units_n + blds_n))
	check_eq(units_n, 47, "unit count")
	check_eq(blds_n, 14, "building count")
