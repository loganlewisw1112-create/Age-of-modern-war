extends "res://tests/test_base.gd"
## G10 Task 7: Coalition buildings + hidden-state + Ghost campus shell (Armory shell only).

const Bld = preload("res://sim/systems/coalition_buildings10.gd")
const SaveSystem = preload("res://sim/save_system.gd")

const CORE_BUILDINGS := [
	"x_safehouse", "x_tunnel_entrance", "x_cache", "x_weld_shop", "x_black_market", "x_broker_exchange",
	"x_patron_office", "x_disguised_workshop", "x_bunker_hatch", "x_underground_barracks",
	"x_underground_factory", "x_ghost_complex", "x_forward_repair", "x_vault_core",
]


func _coalition_world(stage: int = 8) -> SimWorld:
	var c := SimWorld.default_config()
	c.sides = [
		{"faction": "shadow_coalition", "stage": stage, "credits": 8000, "ai": false, "name": "X", "team": 0},
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "A", "team": 1},
	]
	return SimWorld.new_match(c)


func _spawn(w: SimWorld, def_id: String, fid: int, cell: Vector2i) -> int:
	var bid := w.spawn_building(def_id, fid, cell, true)
	var err := Bld.track(w, bid)
	check(err == "" or err == "vault_unique", "track %s: %s" % [def_id, err])
	return bid


func test_fourteen_buildings_and_power_producer_closure() -> void:
	Content.load_all()
	check_eq(CORE_BUILDINGS.size(), 14, "14 core buildings")
	check_eq(Bld.building_ids().size(), 14, "rules building_ids == 14")
	for id in CORE_BUILDINGS:
		check(Bld.building_ids().has(id), "rules missing %s" % id)
		var b: Dictionary = Content.building(id)
		check(not b.is_empty(), "def missing %s" % id)
		check_eq(String(b.get("faction", "")), "shadow_coalition", "%s faction" % id)
		check(b.has("power"), "%s power field" % id)
	var closure: Dictionary = Bld.power_and_producer_closure()
	check_eq(int(closure.get("building_count", 0)), 14, "closure count")
	check_eq((closure.get("missing_power", []) as Array).size(), 0, "all have power")
	check_eq((closure.get("orphan_defs", []) as Array).size(), 0, "no orphan defs")
	check_eq((closure.get("bad_facilities", []) as Array).size(), 0, "producer facilities resolve")


func test_disguised_until_scouted_and_detector_reveal() -> void:
	Content.load_all()
	var w := _coalition_world()
	var shop := _spawn(w, "x_disguised_workshop", 0, Vector2i(12, 12))
	check(Bld.is_hidden_from(w, shop, 1), "hidden from enemy before scout")
	check_eq(Bld.render_state(w, shop, 1), "hidden", "render hidden")
	check(not Bld.is_hidden_from(w, shop, 0), "owner sees own building")
	Bld.reveal(w, shop, 1, "scout")
	check(not Bld.is_hidden_from(w, shop, 1), "revealed after scout")
	check_eq(Bld.render_state(w, shop, 1), "revealed", "render revealed")
	var market := _spawn(w, "x_black_market", 0, Vector2i(14, 12))
	Bld.reveal(w, market, 1, "detector")
	var row: Dictionary = w.sys_state["coalition_buildings10"]["buildings"][str(market)]
	check_eq(String(row.revealed_to.get("1", "")), "detector", "detector cause stored")
	Bld.reveal(w, market, 1, "recent_action")
	check_eq(String(row.revealed_to.get("1", "")), "recent_action", "recent_action overwrites cause")


func test_hatch_damage_vs_underground_alive() -> void:
	Content.load_all()
	var w := _coalition_world()
	var hatch := _spawn(w, "x_bunker_hatch", 0, Vector2i(16, 12))
	check(Bld.hatch_alive(w, hatch), "hatch starts alive")
	check(Bld.underground_alive(w, hatch), "underground starts alive")
	check_eq(Bld.production_reason(w, hatch), "", "prod ok with hatch")
	Bld.damage_hatch(w, hatch, 9999, 1)
	check(not Bld.hatch_alive(w, hatch), "hatch destroyed")
	check(Bld.underground_alive(w, hatch), "underground survives hatch loss")
	check(w.entities.has(hatch), "entity still present after hatch kill")
	check_eq(Bld.production_reason(w, hatch), "hatch_access", "hatch penalty blocks production")
	Bld.damage_underground(w, hatch, 99999, 1)
	check(not Bld.underground_alive(w, hatch), "underground dead after direct damage")
	check(not w.entities.has(hatch), "entity removed only by underground destroy")


func test_vault_uniqueness_and_no_understrike_floor() -> void:
	Content.load_all()
	var w := _coalition_world()
	# Ghost complex required by vault def chain; place campus first.
	var campus := _spawn(w, "x_ghost_complex", 0, Vector2i(18, 14))
	check(campus > 0, "ghost complex spawned")
	var v1 := w.spawn_building("x_vault_core", 0, Vector2i(20, 14), true)
	check_eq(Bld.track(w, v1), "", "first vault ok")
	check(Bld.can_place_vault(w, 0) == false, "second vault blocked while first live")
	var v2 := w.spawn_building("x_vault_core", 0, Vector2i(22, 14), true)
	check_eq(Bld.track(w, v2), "vault_unique", "track rejects second vault")
	check(not Bld.has_understrike_floor(w, v1), "no understrike floor on vault")
	check(not Bld.has_understrike_floor(w, campus), "no understrike floor on campus")
	var row: Dictionary = w.sys_state["coalition_buildings10"]["buildings"][str(v1)]
	check_eq(String(row.get("floor_id", "")), "", "floor_id empty")
	check(not bool(row.get("understrike_floor", true)), "understrike_floor false")


func test_ghost_campus_modules_24_27() -> void:
	Content.load_all()
	var w := _coalition_world(8)
	var campus := _spawn(w, "x_ghost_complex", 0, Vector2i(10, 20))
	var mods: Dictionary = Bld.ghost_modules(w, campus)
	check(mods.has("wing_vault_bay"), "wing module")
	check_eq(String(mods.wing_vault_bay.get("surface", "")), "hatch_only", "wing hatch-only")
	check(mods.has("kill_house"), "kill-house")
	check(mods.has("briefing_crypt"), "briefing crypt")
	check(mods.has("reliquary"), "reliquary")
	Bld.set_kill_house_failure(w, campus, "quiet_decap_fail")
	var kh: Dictionary = Bld.campus(w, campus).kill_house
	check_eq(String(kh.get("last_failed_op", "")), "quiet_decap_fail", "failed-op recorded")
	check_eq(String(kh.get("layout", "")), "adapted_quiet_decap_fail", "layout adapted")
	check_eq(Bld.commit_doctrine(w, campus, "harry"), "", "first doctrine commit")
	check_eq(Bld.commit_doctrine(w, campus, "strike"), "doctrine_locked", "second doctrine locked")
	check_eq(String(Bld.campus(w, campus).briefing_crypt.get("doctrine", "")), "harry", "doctrine held")
	check_eq(Bld.deposit_reliquary_part(w, campus, "sensor_tap"), "", "deposit part")
	check_eq(Bld.consume_reliquary(w, campus, "sensor_tap"), "", "consume allow-listed")
	check_eq(String(Bld.campus(w, campus).reliquary.get("active_upgrade", "")), "sensor_tap", "upgrade active")
	check_eq(Bld.consume_reliquary(w, campus, "breach_wedge"), "non_stacking", "non-stacking")
	check_eq(Bld.deposit_reliquary_part(w, campus, "not_a_real_part"), "not_allow_listed", "deny unknown")


func test_armory_shell_stage_bands_and_bay_flags() -> void:
	Content.load_all()
	check_eq(Bld.armory_band_for_stage(3), "locker", "stage3 locker")
	check_eq(Bld.armory_bay_cap_for_band("locker"), 1, "locker 1 bay")
	check_eq(Bld.armory_band_for_stage(8), "full", "stage8 full")
	check_eq(Bld.armory_bay_cap_for_band("full"), 3, "full 3 bays")
	check_eq(Bld.armory_band_for_stage(12), "black", "stage12 black")
	check_eq(Bld.armory_bay_cap_for_band("black"), 6, "black 6 bays")
	var w := _coalition_world(8)
	var campus := _spawn(w, "x_ghost_complex", 0, Vector2i(8, 22))
	var arm: Dictionary = Bld.armory_shell(w, campus)
	check(bool(arm.get("shell", false)), "armory is shell (ARMORY10 owns full sim)")
	check(bool(arm.get("hatch_only", false)), "armory hatch-only surface")
	check_eq(String(arm.get("band", "")), "full", "campus armory band")
	check_eq(Bld.armory_bay_count(w, campus), 3, "bay count")
	check_eq(Bld.set_bay_occupied(w, campus, 0, true, 42), "", "occupy bay0")
	var bay0: Dictionary = Bld.armory_shell(w, campus).bays[0]
	check(bool(bay0.get("occupied", false)), "bay occupied flag")
	check_eq(int(bay0.get("squad_id", -1)), 42, "squad on bay")
	check_eq(Bld.set_bay_occupied(w, campus, 9, true), "bay_oob", "oob bay")


func test_hatch_vent_discovery_and_contrast_readability() -> void:
	Content.load_all()
	var w := _coalition_world()
	var hatch := _spawn(w, "x_bunker_hatch", 0, Vector2i(6, 10))
	check_eq(Bld.render_state(w, hatch, 1), "hidden", "hatch hidden until discovery")
	Bld.reveal(w, hatch, 1, "hatch_vent")
	check_eq(Bld.render_state(w, hatch, 1), "hatch_only", "vent discovery shows hatch-only")
	check_eq(Bld.contrast_profile("x_black_market"), "neon_under_tarp", "market neon contrast")
	check_eq(Bld.contrast_profile("x_ghost_complex"), "dark_ghost", "ghost dark contrast")
	check(Bld.contrast_profile("x_black_market") != Bld.contrast_profile("x_ghost_complex"), "market vs ghost distinct")


func test_save_load_preserves_revealed_and_underground_hp() -> void:
	Content.load_all()
	var w := _coalition_world()
	var ug := _spawn(w, "x_underground_barracks", 0, Vector2i(24, 10))
	Bld.reveal(w, ug, 1, "scout")
	Bld.damage_hatch(w, ug, 50, 1)
	Bld.damage_underground(w, ug, 100, 1)
	var before_hatch := int(w.sys_state[Bld.KEY]["buildings"][str(ug)]["hatch_hp"])
	var before_ug := int(w.sys_state[Bld.KEY]["buildings"][str(ug)]["underground_hp"])
	var cause := String(w.sys_state[Bld.KEY]["buildings"][str(ug)]["revealed_to"]["1"])
	var path := "user://test_g10_buildings_save.json"
	check_eq(SaveSystem.save(w, path), "", "save ok")
	var loaded: SimWorld = SaveSystem.load(path)
	check(loaded != null, "load ok")
	var row: Dictionary = loaded.sys_state[Bld.KEY]["buildings"][str(ug)]
	check_eq(String(row.revealed_to.get("1", "")), cause, "revealed observer preserved")
	check_eq(int(row.hatch_hp), before_hatch, "hatch hp preserved")
	check_eq(int(row.underground_hp), before_ug, "underground hp preserved")
	check(Bld.underground_alive(loaded, ug), "underground still alive after load")
	check_eq(Bld.production_reason(loaded, ug), "", "prod still ok (hatch not fully destroyed)")
