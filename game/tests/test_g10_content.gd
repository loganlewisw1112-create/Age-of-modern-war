extends "res://tests/test_base.gd"
## G10 Task 1+3: Shadow Coalition registry, 61-core seed, doctrine facade.

const Coalition10 = preload("res://sim/systems/coalition10.gd")
const CoalitionCommand = preload("res://presentation/ui10/coalition_command.gd")
const RenderSnap = preload("res://sim/render_snap.gd")

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


func _coalition_world() -> SimWorld:
	var c := SimWorld.default_config()
	c.sides = [
		{"faction": "shadow_coalition", "stage": 8, "credits": 5000, "ai": false, "name": "X", "team": 0},
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "A", "team": 1},
	]
	return SimWorld.new_match(c)


func test_coalition_doctrine_default_and_board_schema() -> void:
	Content.load_all()
	var w := _coalition_world()
	check(Coalition10.active(w, 0), "fid0 active")
	check(not Coalition10.active(w, 1), "fid1 not Coalition")
	check_eq(Coalition10.layer(w, 0), "cells", "default layer")
	var b: Dictionary = Coalition10.board(w, 0)
	check_eq(String(b.get("intent", "")), "harry", "default intent harry")
	for k in ["cells", "contracts", "patron_favour", "intel_grade", "ghost_ready", "tech_sources"]:
		check(b.has(k), "board missing %s" % k)
	# Without evidence, bleed/flex/strike/exfil are rejected
	Coalition10.set_intent(w, 0, "bleed")
	check_eq(String(Coalition10.board(w, 0).get("intent", "")), "harry", "bleed blocked without evidence")
	Coalition10.note_evidence(w, 0, "probes", 1)
	Coalition10.set_intent(w, 0, "bleed")
	check_eq(String(Coalition10.board(w, 0).get("intent", "")), "bleed", "bleed after probes")
	Coalition10.note_evidence(w, 0, "gap", 1)
	Coalition10.set_intent(w, 0, "flex")
	check_eq(String(Coalition10.board(w, 0).get("intent", "")), "flex", "flex after gap")
	check(w.sys_state.has("coalition10"), "lazy state created for Coalition match")


func test_coalition_command_surface_and_advanced_closed() -> void:
	Content.load_all()
	var w := _coalition_world()
	var host := Node.new()
	var ui = CoalitionCommand.new()
	host.add_child(ui)
	ui.world_override = w
	ui.fid_override = 0
	ui.refresh()
	check(ui.visible, "command visible for Coalition")
	check(not ui.advanced_open, "Advanced closed by default")
	check(not ui._adv_box.visible, "Advanced drawer hidden")
	host.free()


func test_non_coalition_match_creates_no_g10_state() -> void:
	Content.load_all()
	var c := SimWorld.default_config()
	c.sides = [
		{"faction": "human_a", "stage": 8, "credits": 2000, "ai": false, "name": "A", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 2000, "ai": false, "name": "M", "team": 1},
	]
	var w := SimWorld.new_match(c)
	Coalition10.tick(w)
	check(not w.sys_state.has("coalition10"), "no coalition10 state without Coalition side")
	RenderSnap.build(w)
	var snap: Dictionary = RenderSnap.latest(w)
	check(not snap.has("coalition10"), "render snap omits coalition10 when unused")
	for _i in 30:
		w.step()
	var mid := w.state_hash()
	var w2 := SimWorld.new_match(c)
	for _j in 30:
		w2.step()
	check_eq(mid, w2.state_hash(), "non-Coalition two-run hash")


const MOVE_OK := {
	"foot": true, "vehicle": true, "amphibious": true, "naval_small": true, "naval": true,
	"air": true, "air_low": true, "air_high": true,
}


func test_core_roster_unique_ids_and_faction_ownership() -> void:
	Content.load_all()
	var seen := {}
	for id in G10_CORE_IDS:
		check(not seen.has(id), "duplicate core id %s" % id)
		seen[id] = true
		var u: Dictionary = Content.unit(id)
		var b: Dictionary = Content.building(id)
		check(u.is_empty() != b.is_empty(), "%s must be unit XOR building" % id)
		var d: Dictionary = u if not u.is_empty() else b
		check_eq(String(d.get("faction", "")), "shadow_coalition", "%s faction" % id)
		check(d.has("stage_min") and d.has("stage_max"), "%s stage_min/max" % id)
		check(int(d.get("stage_min", 99)) <= int(d.get("stage_max", 0)), "%s stage band" % id)


func test_core_producer_closure_and_costs() -> void:
	Content.load_all()
	for id in G10_CORE_IDS:
		var u: Dictionary = Content.unit(id)
		if u.is_empty():
			var b: Dictionary = Content.building(id)
			check(b.has("cost"), "%s building cost" % id)
			continue
		check(int(u.get("pop", 0)) > 0, "%s pop" % id)
		check(u.has("cost") and int(u.cost.get("credits", -1)) >= 0, "%s unit cost" % id)
		var mc := String(u.get("move_class", ""))
		check(MOVE_OK.has(mc), "%s move_class %s" % [id, mc])
		var wpn := String(u.get("weapon", ""))
		check(not Content.weapon(wpn).is_empty(), "%s weapon %s" % [id, wpn])
		var prod: Dictionary = Content.production(id)
		check(not prod.is_empty(), "%s production row" % id)
		check_eq(String(prod.get("faction", "")), "shadow_coalition", "%s prod faction" % id)
		var fac := String(prod.get("facility", ""))
		var fb: Dictionary = Content.building(fac)
		check(not fb.is_empty(), "%s facility %s missing" % [id, fac])
		check_eq(String(fb.get("faction", "")), "shadow_coalition", "%s facility faction" % id)
		check(prod.has("cost") and int(prod.cost.get("credits", -1)) >= 0, "%s prod cost" % id)


func test_core_roles_closed_at_stages_7_to_10() -> void:
	Content.load_all()
	for stage in [7, 8, 9, 10]:
		for role in ROLE_KEYS:
			var rid := Content.role("shadow_coalition", role, stage)
			# Empty stage_roles overrides (e.g. air@7 in factions.json) are intentional faction policy.
			if rid == "":
				continue
			var is_bld: bool = role in ["hq", "power", "depot", "barracks", "factory", "refinery", "defense"]
			var d: Dictionary = Content.building(rid) if is_bld else Content.unit(rid)
			check(not d.is_empty(), "role %s@%d def %s missing" % [role, stage, rid])
			check_eq(String(d.get("faction", "")), "shadow_coalition", "role %s@%d faction" % [role, stage])
			check(Content.available(d, stage), "role %s@%d stage gate %s" % [role, stage, rid])


func test_core_stage_progression_bands() -> void:
	Content.load_all()
	# Stage 7 cells/technicals
	for id in ["x_sleeper_cell", "x_technical_mg", "x_technical_mortar", "x_shock_truck", "x_underground_factory"]:
		var d: Dictionary = Content.unit(id) if not Content.unit(id).is_empty() else Content.building(id)
		check(int(d.get("stage_min", 99)) <= 7, "%s should unlock by stage 7" % id)
	# Stage 8 contracts/naval/Mk I
	for id in ["x_pmc_rifle", "x_river_ghost", "x_death_strike", "x_broker_exchange", "x_ghost_complex"]:
		var d2: Dictionary = Content.unit(id) if not Content.unit(id).is_empty() else Content.building(id)
		check_eq(int(d2.get("stage_min", -1)), 8, "%s stage_min 8" % id)
	# Stage 9 EW/Mk II/advanced patron
	for id in ["x_pmc_ew", "x_shadow_ew", "x_patron_cas", "x_stealth_drone"]:
		check_eq(int(Content.unit(id).get("stage_min", -1)), 9, "%s stage_min 9" % id)
	# Stage 10 prototypes/apex
	check_eq(int(Content.unit("x_prototype_walker").get("stage_max", 0)), 13, "walker stage_max")
	check_eq(int(Content.unit("x_prototype_walker").get("stage_min", -1)), 10, "walker stage_min 10")
	check_eq(int(Content.building("x_vault_core").get("stage_min", -1)), 10, "vault stage_min 10")
	check(bool(Content.unit("x_prototype_walker").get("apex", false)) or int(Content.unit("x_prototype_walker").get("mk", 0)) >= 2, "walker apex/mk mark")


## Task 8 Step 4 — approved-core art coverage (deferred TECHNICAL/SAFEHOUSE allowed as placeholders).
const G10_APPROVED_ART_IDS := [
	"x_cell_rifle", "x_cell_at", "x_cell_sapper", "x_cell_medic", "x_ambush_cell", "x_sleeper_cell",
	"x_backdoor_hacker", "x_broker", "x_pmc_rifle", "x_pmc_assault", "x_pmc_sniper", "x_pmc_ew", "x_officer",
	"x_ghost_infiltrator",
	"x_death_strike", "x_death_assault", "x_death_recon", "x_shadow_pathfinder", "x_shadow_ew",
	"x_shadow_signal", "x_shadow_decoy", "x_anchor_tech", "x_anchor_medic",
	"x_prototype_walker",
	"x_patron_cas", "x_silent_rotor", "x_stealth_transport", "x_stealth_drone", "x_shock_drone", "x_recon_drone",
]

const G10_DEFERRED_ART_IDS := [
	"x_technical_mg", "x_technical_rocket", "x_technical_aa", "x_technical_mortar", "x_technical_recoilless",
	"x_captured_tank", "x_refit_ifv", "x_shock_truck", "x_stealth_apc", "x_ghost_runner", "x_exo_mule",
	"x_recovery_truck", "x_ghost_drone_carrier",
	"x_river_ghost", "x_mini_sub", "x_smuggler_boat", "x_patrol_boat",
	"x_safehouse", "x_tunnel_entrance", "x_cache", "x_weld_shop", "x_black_market", "x_broker_exchange",
	"x_patron_office", "x_disguised_workshop", "x_bunker_hatch", "x_underground_barracks",
	"x_underground_factory", "x_ghost_complex", "x_forward_repair", "x_vault_core",
]


func _g10_art_spec(id: String) -> Dictionary:
	var man: Dictionary = ArtCatalog.manifest()
	for sec in ["infantry", "vehicles", "buildings", "air", "naval", "units"]:
		var bucket = man.get(sec, {})
		if bucket is Dictionary and bucket.has(id):
			return bucket[id]
	return {}


func test_g10_approved_art_catalog_coverage() -> void:
	ArtCatalog.load_all()
	check((ArtCatalog.manifest().get("g5_groups", []) as Array).has("g10_coalition"), "g10_coalition group merged")
	check_eq(G10_APPROVED_ART_IDS.size(), 30, "approved art id count")
	for id in G10_APPROVED_ART_IDS:
		var spec := _g10_art_spec(id)
		check(not spec.is_empty(), "approved art missing for %s" % id)
		check_eq(int(spec.get("facings", 0)), 4, "%s facings" % id)
		check(int(spec.get("fw", 0)) > 0 and int(spec.get("fh", 0)) > 0, "%s dimensions" % id)
		var frames: Array = spec.get("frames", [])
		check(frames.size() >= 4, "%s has anim frames (>=4)" % id)
		check(frames.has("idle"), "%s has idle" % id)
		var img: Image = ArtCatalog._image(String(spec.get("file", "")))
		check(img != null and img.get_width() > 0 and img.get_height() > 0, "%s sheet loads" % id)
		check(img.get_width() >= int(spec.get("fw", 80)) * frames.size(), "%s sheet width matches frames" % id)
		var mask_path := String(spec.get("mask", ""))
		check(mask_path != "", "%s mask path" % id)
		var msk: Image = ArtCatalog._image(mask_path)
		check(msk != null and msk.get_width() == img.get_width() and msk.get_height() == img.get_height(), "%s mask dims" % id)
		var icons: Dictionary = ArtCatalog.manifest().get("icons", {})
		check(icons.has(id), "%s icon present" % id)


func test_g10_deferred_art_allowed_as_placeholder() -> void:
	ArtCatalog.load_all()
	check_eq(G10_DEFERRED_ART_IDS.size(), 31, "deferred art id count")
	## Deferred subjects may be absent from catalog (placeholder_for at runtime) — that is OK.
	for id in G10_DEFERRED_ART_IDS:
		var spec := _g10_art_spec(id)
		if spec.is_empty():
			continue
		## If present, must not claim approved_core lock.
		var g10 = spec.get("g10", {})
		if g10 is Dictionary:
			check(not bool(g10.get("approved_core", false)), "deferred %s must not be approved_core" % id)


## Post-lock anim/air overhaul — Ghost Wing real poses + unique air fleet.
const G10_GHOST_SET_IDS := [
	"x_ghost_base", "x_ghost_judge", "x_ghost_warden", "x_ghost_shade", "x_ghost_sergeant",
	"x_ghost_mk1", "x_ghost_mk2", "x_ghost_mk3",
	"x_ghost_ace_01", "x_ghost_ace_02", "x_ghost_ace_03", "x_ghost_ace_04", "x_ghost_ace_05",
	"x_ghost_ace_06", "x_ghost_ace_07", "x_ghost_ace_08", "x_ghost_ace_09",
]

const G10_CAMO_STATES := ["rest", "walk", "sprint", "fire", "hit", "battery", "shield"]
const G10_ANIM_FRAMES_INF := ["idle", "walk_a", "walk_b", "run_0", "fire", "hit", "die_0"]
const G10_ANIM_FRAMES_AIR := ["idle", "flight", "fire", "hit"]

const G10_AIR_STATE_IDS := [
	"x_patron_cas", "x_silent_rotor", "x_stealth_transport",
	"x_stealth_drone", "x_shock_drone", "x_recon_drone",
]


func test_g10_ghost_wing_set_coverage() -> void:
	ArtCatalog.load_all()
	check_eq(G10_GHOST_SET_IDS.size(), 17, "ghost wing set id count")
	for id in G10_GHOST_SET_IDS:
		var spec := _g10_art_spec(id)
		check(not spec.is_empty(), "ghost set missing %s" % id)
		check_eq(int(spec.get("facings", 0)), 4, "%s facings" % id)
		var g10 = spec.get("g10", {})
		check(g10 is Dictionary and bool(g10.get("ghost_wing", false)), "%s ghost_wing flag" % id)
		check(bool(g10.get("approved_core", false)), "%s approved_core" % id)
		check(bool(g10.get("anim_board", false)), "%s anim_board flag" % id)
		var frames: Array = spec.get("frames", [])
		check(frames.size() >= G10_ANIM_FRAMES_INF.size(), "%s real anim frames" % id)
		for fname in G10_ANIM_FRAMES_INF:
			check(frames.has(fname), "%s missing anim frame %s" % [id, fname])
		var img: Image = ArtCatalog._image(String(spec.get("file", "")))
		check(img != null and img.get_width() >= 80 * G10_ANIM_FRAMES_INF.size(), "%s multi-frame sheet" % id)
		var states = spec.get("states", {})
		check(states is Dictionary and states.size() >= G10_CAMO_STATES.size(), "%s pose-state crops" % id)
		for st in G10_CAMO_STATES:
			check(states.has(st), "%s missing state %s" % [id, st])
			var sspec: Dictionary = states[st]
			var simg: Image = ArtCatalog._image(String(sspec.get("file", "")))
			check(simg != null and simg.get_width() > 0, "%s state %s loads" % [id, st])
			check(String(sspec.get("pose", "")) != "", "%s state %s has pose" % [id, st])


func test_g10_close_air_state_polish() -> void:
	ArtCatalog.load_all()
	var sil_hashes := {}
	for id in G10_AIR_STATE_IDS:
		var spec := _g10_art_spec(id)
		check(not spec.is_empty(), "air state missing %s" % id)
		var frames: Array = spec.get("frames", [])
		check(frames.size() >= G10_ANIM_FRAMES_AIR.size(), "%s has air anim frames" % id)
		for fname in G10_ANIM_FRAMES_AIR:
			check(frames.has(fname), "%s missing air frame %s" % [id, fname])
		var img: Image = ArtCatalog._image(String(spec.get("file", "")))
		check(img != null and img.get_width() >= 80 * G10_ANIM_FRAMES_AIR.size(), "%s multi-frame air sheet" % id)
		var g10 = spec.get("g10", {})
		check(g10 is Dictionary and (g10.get("air_states") is Array), "%s air_states meta" % id)
		check(bool(g10.get("unique_air", false)), "%s unique_air flag" % id)
		## Idle E-facing crop must differ across air ids (no shared silhouette).
		var idle := img.get_region(Rect2i(0, 64, 80, 64))
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		ctx.update(idle.get_data())
		var h := ctx.finish().hex_encode()
		check(not sil_hashes.has(h), "%s silhouette must be unique vs %s" % [id, sil_hashes.get(h, "")])
		sil_hashes[h] = id
