extends "res://tests/test_base.gd"
## G10 Task 7B: Exo Armory full sim (bay caps, outfit, field kits, unlocks, harsh destroy, CN denial).

const Armory = preload("res://sim/systems/exo_armory10.gd")
const Bld = preload("res://sim/systems/coalition_buildings10.gd")
const GhostExo10 = preload("res://sim/systems/ghost_exo10.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")


func _coalition_world(stage: int = 8) -> SimWorld:
	Content.load_all()
	var boot := clampi(stage, 7, 9)
	var c := SimWorld.default_config()
	c.sides = [
		{"faction": "shadow_coalition", "stage": boot, "credits": 8000, "ai": false, "name": "X", "team": 0},
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "A", "team": 1},
	]
	var w: SimWorld = SimWorld.new_match(c)
	# Armory bands span 1–13; match boot is 7–9 only — stamp desired stage after create.
	if w != null:
		w.factions[0].stage = stage
	return w


func _human_world() -> SimWorld:
	Content.load_all()
	var c := SimWorld.default_config()
	c.sides = [
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "A", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 1},
	]
	return SimWorld.new_match(c)


func _campus(w: SimWorld, fid: int = 0, cell: Vector2i = Vector2i(10, 10)) -> int:
	var bid := w.spawn_building("x_ghost_complex", fid, cell, true)
	Bld.track(w, bid)
	check_eq(Armory.bind(w, bid), "", "bind armory")
	return bid


func test_stage_bay_caps_locker_full_black() -> void:
	check_eq(Armory.band_for_stage(3), "locker", "stage3 locker")
	check_eq(Armory.bay_cap_for_band("locker"), 1, "locker cap 1")
	check_eq(Armory.band_for_stage(8), "full", "stage8 full")
	check_eq(Armory.bay_cap_for_band("full"), 3, "full cap 3")
	check_eq(Armory.band_for_stage(12), "black", "stage12 black")
	check_eq(Armory.bay_cap_for_band("black"), 6, "black cap 6")
	var w1 := _coalition_world(4)
	var c1 := _campus(w1, 0, Vector2i(8, 8))
	check_eq(Armory.bay_count(w1, c1), 1, "locker bay_count")
	var w2 := _coalition_world(8)
	var c2 := _campus(w2, 0, Vector2i(8, 8))
	check_eq(Armory.bay_count(w2, c2), 3, "full default 3")
	check_eq(Armory.choose_start_bays(w2, c2, 2), "", "owner start 2")
	check_eq(Armory.bay_count(w2, c2), 2, "full start 2")
	check_eq(Armory.upgrade_bay(w2, c2), "", "upgrade to 3")
	check_eq(Armory.bay_count(w2, c2), 3, "full at cap")
	check_eq(Armory.upgrade_bay(w2, c2), "bay_cap", "full blocked at 3")
	check_eq(Armory.unlock_bay_cap_boost(w2, c2, "contract"), "", "contract boost")
	check_eq(Armory.upgrade_bay(w2, c2), "", "interim bay 4")
	check_eq(Armory.bay_count(w2, c2), 4, "boosted to 4")
	var w3 := _coalition_world(12)
	var c3 := _campus(w3, 0, Vector2i(8, 8))
	check_eq(Armory.bay_count(w3, c3), 6, "black 6 bays")
	check(Armory.bay_count(w3, c3) <= 6, "never above 6")


func test_coalition_only_and_cn_denial() -> void:
	var w := _coalition_world(8)
	var campus := _campus(w)
	var sid := GhostExo10.form_squad(w, 0, "4op", "death")
	check(sid > 0, "ghost squad")
	check_eq(Armory.outfit_preset(w, {"building_id": campus, "index": 0}, sid, "strike_mk1"), "", "coalition outfit")
	# CN preset always denied
	check_eq(Armory.unlock_preset(w, campus, "cn_denied_kit", "contract"), "cn_denied", "CN unlock denied")
	check_eq(Armory.outfit_preset(w, {"building_id": campus, "index": 1}, sid, "cn_denied_kit"), "cn_denied", "CN outfit denied")
	# Human A cannot bind / outfit
	var wh := _human_world()
	var hb := wh.spawn_building("x_ghost_complex", 0, Vector2i(10, 10), true)
	Bld.track(wh, hb)
	check_eq(Armory.bind(wh, hb), "coalition_only", "human cannot bind")
	check(not Coalition10.active(wh, 0), "human_a not coalition")


func test_four_op_per_bay_and_parallel_outfit() -> void:
	var w := _coalition_world(8)
	var campus := _campus(w)
	var s1 := GhostExo10.form_squad(w, 0, "4op", "death")
	var s2 := GhostExo10.form_squad(w, 0, "4op", "death")
	var s3 := GhostExo10.form_squad(w, 0, "6op", "death")
	check_eq(Armory.outfit_preset(w, {"building_id": campus, "index": 0}, s1, "strike_mk1"), "", "bay0 strike")
	check_eq(Armory.outfit_preset(w, {"building_id": campus, "index": 1}, s2, "assault_mk1"), "", "bay1 assault parallel")
	check_eq(Armory.outfit_preset(w, {"building_id": campus, "index": 0}, s2, "recon_mk1"), "bay_busy", "occupied bay")
	check_eq(Armory.outfit_preset(w, {"building_id": campus, "index": 2}, s3, "recon_mk1"), "need_4op", "6op rejected")
	var st := Armory.armory_state(w, campus)
	check_eq(String(st.bays[0].preset), "strike_mk1", "bay0 preset stored")
	check_eq((st.bays[0].suit_ids as Array).size(), 4, "4 suits in bay")
	check_eq(Bld.armory_shell(w, campus).bays[0].occupied, true, "shell occupancy synced")


func test_unlock_economy_and_gates() -> void:
	var w := _coalition_world(8)
	var campus := _campus(w)
	check(Armory.is_unlocked(w, campus, "strike_mk1"), "starter unlocked")
	check(not Armory.is_unlocked(w, campus, "strike_mk2"), "mk2 locked")
	check_eq(Armory.unlock_preset(w, campus, "strike_mk2", "contract"), "", "contract unlock")
	check(Armory.is_unlocked(w, campus, "strike_mk2"), "mk2 unlocked")
	check(Armory.unlock_preset(w, campus, "assault_mk2", "steal").begins_with("steal"), "steal needs evidence")
	check_eq(Armory.unlock_preset(w, campus, "assault_mk2", "steal", {"captured_gear": 1}), "", "steal with gear")
	check_eq(Armory.unlock_tier(w, campus), "preset", "tier starts preset")
	check_eq(Armory.advance_unlock_tier(w, campus, "contract"), "", "preset→mix")
	check_eq(Armory.unlock_tier(w, campus), "mix", "mix tier")
	check_eq(Armory.advance_unlock_tier(w, campus, "reliquary"), "", "mix→per_op")
	check_eq(Armory.unlock_tier(w, campus), "per_op", "per_op tier")
	# Reliquary elite path (unlock ok; outfit blocked on full-band catalog)
	Bld.deposit_reliquary_part(w, campus, "camo_weave")
	check_eq(Armory.unlock_preset(w, campus, "shade_cloak", "reliquary", {"tech_tag": "camo_weave"}), "", "reliquary unlock")
	var s_shade := GhostExo10.form_squad(w, 0, "4op", "death")
	check_eq(Armory.outfit_preset(w, {"building_id": campus, "index": 0}, s_shade, "shade_cloak"), "catalog_locked", "mk3 blocked on full")
	check_eq(Armory.unlock_preset(w, campus, "judge_backdoor", "steal", {"raid": 1}), "", "judge via steal")


func test_field_kit_mule_apc_limits_and_scale() -> void:
	var w := _coalition_world(8)
	_campus(w)
	var mule := w.spawn_unit("x_exo_mule", 0, Vector2(12.5, 12.5))
	var apc := w.spawn_unit("x_stealth_apc", 0, Vector2(13.5, 12.5))
	var rifle := w.spawn_unit("x_cell_rifle", 0, Vector2(14.5, 12.5))
	var exo := w.spawn_unit("x_ghost_infiltrator", 0, Vector2(15.5, 12.5))
	w.entities[exo].ammo = 10.0
	w.entities[exo].battery = 40.0
	w.entities[mule].mission_importance = "critical"
	check_eq(Armory.field_kit(w, mule, exo, "ammo_topup"), "", "mule ammo")
	var fk := Armory.field_kit_state(w, exo)
	check(float(fk.ammo.amount) > 20.0, "critical scales ammo above base 20")
	check_eq(Armory.field_kit(w, apc, exo, "battery_cell"), "", "apc battery")
	check_eq(Armory.field_kit(w, apc, exo, "optic_swap"), "", "attachment swap")
	check_eq(Armory.field_kit(w, rifle, exo, "ammo_topup"), "carrier_not_field", "rifle not carrier")
	check_eq(Armory.field_kit(w, mule, exo, "full_refit_denied"), "field_kit_limited", "no full refit")
	# Persist after armory destroy checked in harsh test; kit state remains here
	check(fk.has("ammo"), "field kit recorded")


func test_harsh_destroy_and_rebuild() -> void:
	var w := _coalition_world(8)
	var campus := _campus(w)
	var s1 := GhostExo10.form_squad(w, 0, "4op", "death")
	var s2 := GhostExo10.form_squad(w, 0, "4op", "death")
	check_eq(Armory.outfit_preset(w, {"building_id": campus, "index": 0}, s1, "strike_mk1"), "", "outfit bay0")
	check_eq(Armory.outfit_preset(w, {"building_id": campus, "index": 1}, s2, "recon_mk1"), "", "outfit bay1")
	# Deploy bay1 to field — those kits persist
	check_eq(Armory.deploy_bay(w, campus, 1), "", "deploy field")
	var field_suits: Array = []
	for k in w.sys_state[Armory.KEY]["suits"].keys():
		if Armory.suit_status(w, String(k)) == "field":
			field_suits.append(k)
	check_eq(field_suits.size(), 4, "4 field suits")
	# Field kit on a unit persists across destroy
	var mule := w.spawn_unit("x_exo_mule", 0, Vector2(11.5, 11.5))
	var exo := w.spawn_unit("x_ghost_infiltrator", 0, Vector2(11.7, 11.5))
	check_eq(Armory.field_kit(w, mule, exo, "battery_cell"), "", "pre-destroy field kit")
	Armory.on_armory_destroyed(w, campus)
	check_eq(Armory.bay_count(w, campus), 0, "destroyed bay_count 0")
	check_eq(Armory.outfit_preset(w, {"building_id": campus, "index": 0}, s1, "assault_mk1"), "armory_destroyed", "outfit blocked")
	var lost := 0
	var field_ok := 0
	for k in w.sys_state[Armory.KEY]["suits"].keys():
		var st := Armory.suit_status(w, String(k))
		if st == "destroyed" or st == "captured":
			lost += 1
		elif st == "field":
			field_ok += 1
	check_eq(lost, 4, "in-bay suits destroyed/captured")
	check_eq(field_ok, 4, "field suits persist")
	check(Armory.field_kit_state(w, exo).has("battery"), "field kit persists")
	check_eq(Armory.rebuild(w, campus), "", "rebuild")
	check_eq(Armory.bay_count(w, campus), 3, "bays restored")
	check_eq(Armory.outfit_preset(w, {"building_id": campus, "index": 0}, s1, "strike_mk1"), "", "outfit after rebuild")


func test_enemy_raid_intel_only_no_outfit_rights() -> void:
	var w := _coalition_world(8)
	var campus := _campus(w)
	var raid: Dictionary = Armory.raid(w, campus, 1)
	check(bool(raid.get("ok", false)), "raid ok")
	check_eq(bool(raid.get("outfit_rights", true)), false, "no outfit rights")
	check((raid.get("yields", []) as Array).has("intel_fragment"), "intel yield")
	check((raid.get("yields", []) as Array).has("parts"), "parts yield")
	# Raider cannot outfit
	var sid := GhostExo10.form_squad(w, 0, "4op", "death")
	# Human side has no coalition armory bind
	check(not Coalition10.active(w, 1), "raider not coalition")
	var friendly := Armory.raid(w, campus, 0)
	check(not bool(friendly.get("ok", true)), "friendly raid rejected")
	check_eq(Armory.outfit_preset(w, {"building_id": campus, "index": 0}, sid, "strike_mk1"), "", "owner still outfits")
