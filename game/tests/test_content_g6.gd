extends "res://tests/test_base.gd"
## G6 acceptance (owner: CONTENT6). CONTRACTS_G6 section 3 (ids), 14 (research), section 17.
## Every section 3.1 / 3.2 id is a content def at its contract stage, producible or buildable by
## the right faction at that stage (and not before), shared defs buildable by all, weapons and
## armour rows valid, the 24 research projects present with effect keys, leaders not producible.

const PData = preload("res://sim/systems/progression_data.gd")

## id:stage:kind (B building, U unit), fixed by CONTRACTS_G6 3.1 / 3.2.
const IDS := [
	"a_atgm_bunker:8:B a_sam_site:9:B a_laser_ciws:9:B a_howitzer_pit:8:B a_popup_turret:9:B ",
	"a_drone_cc:9:B a_radar_station:9:B a_fob:8:B a_repair_bay:8:B a_cruise_battery:9:B a_company_hq:8:B ",
	"a_exo_garage:9:B b_pak_nest:7:B b_flak_battery:8:B b_net_post:9:B b_mortar_pit:7:B b_pillbox:7:B ",
	"b_fpv_workshop:8:B b_rail_yard:8:B b_scrapyard:7:B b_propaganda_tower:8:B b_company_hq:8:B ",
	"m_arc_pylon:9:B m_pulse_spire2:9:B m_jammer_obelisk:9:B m_mass_driver:10:B m_sentry_mine:9:B ",
	"m_nanite_wall:9:B m_phase_gate:9:B m_hive_node:9:B m_nanite_forge:9:B m_overmind:10:B ",
	"m_relay_lattice:9:B m_company_hq:8:B s_sandbags:7:B s_trench:7:B s_tank_traps:7:B s_barbed_wire:7:B ",
	"s_minefield:8:B s_garrison_bld:7:B s_camo_decoy:8:B a_aerostat:8:U a_loiter_truck:9:U ",
	"a_sp_howitzer:8:U a_mlrs:8:U a_mine_clearer:8:U a_bridge_layer:8:U a_command_vehicle:8:U a_ugv:9:U ",
	"a_laser_tank:10:U a_marines:8:U a_paratroopers:9:U a_eod:8:U a_jtac:9:U a_manpads:9:U ",
	"a_exo_trooper:10:U a_awacs:9:U a_airlift:9:U a_supply_ship_a:8:U a_minesweeper:8:U a_hovercraft:9:U ",
	"a_carrier:9:U a_submarine:9:U a_exo_rifle:9:U a_exo_missile:9:U a_exo_aa:10:U a_commander:8:U ",
	"a_captain:8:U a_lieutenant:8:U b_jammer_team:9:U b_scrap_aa:8:U b_conscripts:7:U ",
	"b_satchel_sappers:7:U b_marksman:7:U b_propaganda_team:8:U b_landship:9:U b_flak_halftrack:8:U ",
	"b_armored_dozer:8:U b_salvage_crane:8:U b_moto_scouts:7:U b_rhomboid:7:U b_armored_train:8:U ",
	"b_recon_plane:9:U b_supply_ship_b:8:U b_mine_barge:8:U b_aa_barge:9:U b_commander:8:U b_captain:8:U ",
	"b_lieutenant:8:U m_swarm_queen:10:U m_mimic_drone:10:U m_stealth_drone:10:U m_hover_tank:10:U ",
	"m_colossus:10:U m_assimilator:10:U m_spider_layer:9:U m_shield_drone:9:U m_stalker_synth:10:U ",
	"m_repair_swarm2:9:U m_breacher_crawler:9:U m_charge_tender:8:U m_lance_cruiser:9:U m_commander:8:U ",
	"m_captain:8:U m_lieutenant:8:U ",
]
const LEADERS := ["a_captain", "a_lieutenant", "b_captain", "b_lieutenant", "m_captain", "m_lieutenant"]
const COMMANDERS := {"a_commander": "a_company_hq", "b_commander": "b_company_hq", "m_commander": "m_company_hq"}
## Squad sizes fixed by the art kit (docs/g6_art_kit/notes/g6_infantry.md, g6_dronebld.md).
const SQUADS := {"a_marines": 4, "a_paratroopers": 4, "a_eod": 2, "a_jtac": 2, "a_manpads": 2, "b_conscripts": 10,
	"b_satchel_sappers": 3, "b_marksman": 1, "b_propaganda_team": 2, "b_jammer_team": 2, "b_scrap_aa": 3}
const RESEARCH := ["g6_mines_1", "g6_mines_2", "g6_eod_1", "g6_fieldworks_1", "g6_cover_1", "g6_garrison_1",
	"g6_radar_1", "g6_sam_1", "g6_ciws_1", "g6_jamming_1", "g6_sonar_1", "g6_torpedo_1", "g6_carrier_1",
	"g6_rail_1", "g6_armor_kits_1", "g6_infantry_plates_1", "g6_exo_armor_1", "g6_exo_weapons_1",
	"g6_company_drills_1", "g6_command_net_1", "g6_nanite_1", "g6_swarm_1", "g6_automation_doctrine",
	"g6_overmind_protocols"]
const OWNERS := ["MECH6a", "MECH6b", "MECH6c", "AIRDEF6", "NAVAL6", "EXO6", "ARMY6", "CONTENT6"]
const ARMORS := ["infantry", "light", "heavy", "building", "fortification"]
const MOVE := ["foot", "vehicle", "naval", "naval_small", "amphibious", "air", "air_low", "air_high", "hover", "rail"]
const PREFIX := {"a": "human_a", "b": "human_b", "m": "machine", "s": "shared"}


# ---------------------------------------------------------------- helpers
## [{id, stage, kind}] from IDS.
func _ids() -> Array:
	var out := []
	for row in IDS:
		for tok in String(row).strip_edges().split(" ", false):
			var p: PackedStringArray = String(tok).split(":")
			out.append({"id": p[0], "stage": int(p[1]), "kind": p[2]})
	return out


func _def(e: Dictionary) -> Dictionary:
	return Content.building(String(e.id)) if String(e.kind) == "B" else Content.unit(String(e.id))


## One Stage-7 world per faction, the faction on side 0 (stage changed in place by the tests).
var _worlds := {}


func _world_for(fac: String) -> SimWorld:
	if _worlds.has(fac):
		return _worlds[fac]
	var c := SimWorld.default_config()
	c.sides = [{"faction": fac, "stage": 7, "credits": 1000, "ai": false, "name": "S0", "team": 0},
		{"faction": "machine" if fac != "machine" else "human_a", "stage": 7, "credits": 1000, "ai": false, "name": "S1", "team": 1}]
	var w := SimWorld.new_match(c)
	_worlds[fac] = w
	return w


## Production items (ids) that spawn unit def `uid`.
func _items_spawning(uid: String) -> Array:
	var out := []
	for pid in Content.ids("production"):
		if (Content.production(String(pid)).get("spawns", []) as Array).has(uid):
			out.append(String(pid))
	return out


# ---------------------------------------------------------------- tests
func test_every_section3_id_loads() -> void:
	var all := _ids()
	check_eq(all.size(), 105, "89 page assets + 16 section 3.2 ids")
	var seen := {}
	for e in all:
		var id := String(e.id)
		check(not seen.has(id), "id listed once: " + id)
		seen[id] = true
		var d := _def(e)
		if not check(not d.is_empty(), "def loads: " + id):
			continue
		check(String(d.get("name", "")) != "", "%s has a name" % id)
		check_eq(String(d.get("faction", "")), String(PREFIX[id.substr(0, 1)]), "%s faction by prefix" % id)
		check_eq(int(d.get("stage_min", 7)), int(e.stage), "%s stage_min is the contract stage" % id)
		check(bool(d.get("g6", false)), "%s carries the g6 marker" % id)
		check(int(d.get("hp", 0)) > 0, "%s hp > 0" % id)
		check(ARMORS.has(String(d.get("armor", ""))), "%s armour class %s is a known column" % [id, String(d.get("armor", ""))])
		if String(e.kind) == "U":
			check(MOVE.has(String(d.get("move_class", ""))), "%s move class %s" % [id, String(d.get("move_class", ""))])
			check(float(d.get("speed", 0)) > 0.0 and float(d.get("speed", 0)) <= 10.0, "%s speed in (0, 10] (tiers bucket unchanged)" % id)
			check(float(d.get("sight", 0)) > 0.0, "%s sight > 0" % id)
			check(int(d.get("pop", -1)) >= 1, "%s pop >= 1" % id)
		else:
			check(int(d.get("size", 0)) >= 1 and int(d.get("size", 0)) <= 6, "%s size 1..6" % id)
			check(int(d.get("build_time", 0)) > 0 and not (d.get("cost", {}) as Dictionary).is_empty(), "%s cost + build time" % id)
	for uid in SQUADS:
		check_eq(int(Content.unit(String(uid)).get("squad_size", 1)), int(SQUADS[uid]), "art-kit squad size of " + String(uid))
	check_eq(String(Content.unit("b_armored_train").move_class), "rail", "armored train runs on rail")
	check_eq(String(Content.unit("m_hover_tank").move_class), "hover", "hover tank hovers")
	check_eq(String(Content.unit("a_hovercraft").move_class), "hover", "hovercraft hovers")
	for id in Content.ids("units"):
		check(not String(id).begins_with("x_"), "no x_* unit in G6: " + String(id))


func test_every_id_producible_or_buildable_at_its_stage() -> void:
	for e in _ids():
		var id := String(e.id)
		var d := _def(e)
		var st := int(e.stage)
		var facs: Array = ["human_a", "human_b", "machine"] if String(d.faction) == "shared" else [String(d.faction)]
		for fac in facs:
			var w := _world_for(String(fac))
			var f: Dictionary = w.factions[0]
			if String(e.kind) == "B":
				check(Content.buildable_for(String(fac)).has(id), "%s on the %s build list" % [id, fac])
				f.stage = st
				check_eq(PData.unavailable_reason(w, 0, d), "", "%s buildable by %s at Stage %d" % [id, fac, st])
				for r in d.get("requires", []):
					check(Content.building(String(r)).get("faction", "") in [fac, "shared"], "%s prerequisite %s is %s's" % [id, r, fac])
					check(int(Content.building(String(r)).get("stage_min", 7)) <= st, "%s prerequisite %s by Stage %d" % [id, r, st])
				if st > 7:
					f.stage = st - 1
					check(PData.unavailable_reason(w, 0, d).contains("Stage %d" % st), "%s not before Stage %d" % [id, st])
				continue
			if LEADERS.has(id):
				continue
			var items := _items_spawning(id)
			if not check(items.size() == 1, "%s has exactly one production item (%s)" % [id, str(items)]):
				continue
			var p := Content.production(String(items[0]))
			check_eq(String(p.faction), String(fac), "%s production faction" % id)
			if COMMANDERS.has(id):  # ARMY6 train_commander at the Company HQ, never queue_unit
				check(not p.has("facility") and String(p.get("trained_at", "")) == String(COMMANDERS[id]), "%s trained at its Company HQ" % id)
				f.stage = st
				check_eq(PData.production_reason(w, 0, String(items[0])), "", "%s available at Stage %d" % [id, st])
				continue
			var fb := Content.building(String(p.get("facility", "")))
			check(String(fb.get("faction", "")) == fac and (fb.get("produces", []) as Array).has(String(items[0])),
				"%s is on %s's %s production list" % [id, fac, String(p.get("facility", ""))])
			check(int(fb.get("stage_min", 7)) <= st, "%s facility %s is up by Stage %d" % [id, p.facility, st])
			f.stage = st
			check_eq(PData.production_reason(w, 0, String(items[0])), "", "%s producible by %s at Stage %d" % [id, fac, st])
			if st > 7:
				f.stage = st - 1
				check(PData.production_reason(w, 0, String(items[0])).contains("Stage %d" % st), "%s not before Stage %d" % [id, st])
	for fac in _worlds:
		(_worlds[fac] as SimWorld).factions[0].stage = 7


func test_shared_defs_buildable_by_all_factions() -> void:
	var shared := []
	for e in _ids():
		if String(e.id).begins_with("s_"):
			shared.append(String(e.id))
	check_eq(shared.size(), 7, "7 shared defs")
	for id in shared:
		var d := Content.building(String(id))
		check_eq(String(d.faction), "shared", id + " faction shared")
		check(bool(d.get("buildable", false)), id + " buildable")
		for fac in ["human_a", "human_b", "machine"]:
			check(Content.buildable_for(fac).has(id), "%s buildable by %s" % [id, fac])
	check(bool(Content.building("s_sandbags").get("field_buildable", false)) and bool(Content.building("s_trench").get("field_buildable", false)),
		"sandbags and trench are field-buildable by infantry")
	check_eq(Content.building("s_tank_traps").get("passable_for", []), ["foot"], "tank traps pass foot only")
	check(int(Content.building("s_garrison_bld").get("garrison_slots", 0)) > 0, "garrison building has slots")


func test_rhomboid_is_human_b_stage_7() -> void:
	var d := Content.unit("b_rhomboid")
	check_eq(String(d.faction), "human_b", "Rhomboid is Human B")
	check_eq(int(d.stage_min), 7, "Rhomboid is Stage 7 (moved from Stage 6, PROGRESS item 7)")
	var items := _items_spawning("b_rhomboid")
	check_eq(items, ["b_rhomboid"], "one production item")
	check_eq(String(Content.production("b_rhomboid").facility), Content.role("human_b", "factory", 7), "built at the Human B factory")
	var w := _world_for("human_b")
	w.factions[0].stage = 7
	check_eq(PData.production_reason(w, 0, "b_rhomboid"), "", "producible at Stage 7")
	var wa := _world_for("human_a")
	wa.factions[0].stage = 7
	check(not (Content.building(Content.role("human_a", "factory", 7)).get("produces", []) as Array).has("b_rhomboid"), "not on Human A's factory")


func test_research_g6_ids_present_with_effect_keys() -> void:
	check_eq(RESEARCH.size(), 24, "24 G6 research items (CONTRACTS_G6 3.3)")
	for rid in RESEARCH:
		var p := PData.project(String(rid))
		if not check(not p.is_empty(), "research loads: " + String(rid)):
			continue
		check(String(p.get("name", "")) != "", rid + " has a name")
		check(typeof(p.get("effect")) == TYPE_STRING and String(p.effect) != "", rid + " has an effect key")
		check(p.has("value"), rid + " has an effect value")
		check(OWNERS.has(String(p.get("owner", ""))), "%s owner %s reads the effect" % [rid, String(p.get("owner", ""))])
		check(int(p.get("cost", {}).get("credits", 0)) > 0 and float(p.get("time", 0)) > 0.0, rid + " has cost and time")
		check(int(p.get("stage_min", 0)) >= 8, rid + " needs Stage 8+")
		for f in p.get("factions", []):
			check(Content.faction_ids().has(String(f)), "%s faction %s exists" % [rid, f])
		for r in p.get("requires_research", []):
			check(RESEARCH.has(String(r)), "%s prerequisite %s is a G6 project" % [rid, r])
	check_eq(PData.project("g6_automation_doctrine").get("factions", []), ["human_a", "human_b"], "Automation Doctrine is the Human gate")
	check_eq(PData.project("g6_overmind_protocols").get("factions", []), ["machine"], "Overmind Protocols is the Machine gate")
	check_eq(int(PData.project("g6_automation_doctrine").get("for_stage", 0)), 10, "gate research is for Stage 10")
	check_eq(PData.project("g6_exo_armor_1").get("requires_research", []), ["g6_infantry_plates_1"], "plates -> exo armour chain")
	var keys := {}
	for rid in RESEARCH:
		keys[String(PData.project(String(rid)).get("effect", ""))] = true
	check(keys.size() >= 20, "effect keys are distinct per system (%d)" % keys.size())


func test_weapons_and_armor_rows_valid() -> void:
	var am: Dictionary = Content.table("weapons").get("armor_mult", {})
	for e in _ids():
		var d := _def(e)
		var wids := []
		for k in ["weapon", "weapon2", "bombard_weapon"]:
			if String(d.get(k, "")) != "":
				wids.append(String(d[k]))
		if typeof(d.get("breach")) == TYPE_DICTIONARY and String(d.breach.get("charge_weapon", "")) != "":
			wids.append(String(d.breach.charge_weapon))
		check(float(d.get("crush_damage", 0)) == 0.0, "%s has no crush_damage (G5 AI heavy list unchanged)" % e.id)
		for wid in wids:
			var wd := Content.weapon(String(wid))
			if not check(not wd.is_empty(), "%s weapon %s exists" % [e.id, wid]):
				continue
			var cls := String(wd.get("class", ""))
			if check(am.has(cls), "%s weapon %s class %s has an armor_mult row" % [e.id, wid, cls]):
				for a in ARMORS:
					check((am[cls] as Dictionary).has(a), "armor_mult %s has column %s" % [cls, a])
			check(float(wd.get("damage", 0)) > 0.0 and float(wd.get("cooldown", 0)) > 0.0, "%s damage and cooldown > 0" % wid)
			check(float(wd.get("accuracy", 0)) > 0.0 and float(wd.get("accuracy", 0)) <= 1.0, "%s accuracy in (0, 1]" % wid)
			check(float(wd.get("range", -1)) > 0.0, "%s range > 0" % wid)
			if String(e.kind) == "U":
				check(int(wd.get("salvo", 1)) <= 1, "%s unit weapon %s has no salvo (G5 AI heavy list unchanged)" % [e.id, wid])
	check(bool(Content.weapon("g6_torpedo").get("naval_only", false)), "torpedoes hit naval only")
	check(float(Content.armor_mult("torpedo", "infantry")) == 0.0, "torpedo row: no damage to infantry")
	check(bool(Content.weapon("g6_scrap_shotgun").get("anti_drone", false)) and float(Content.weapon("g6_scrap_shotgun").get("anti_drone_mult", 1)) == 2.0,
		"scrap AA: anti_drone x2")


func test_company_leaders_not_producible_alone() -> void:
	for uid in LEADERS:
		var d := Content.unit(String(uid))
		check(not d.is_empty(), uid + " loads")
		check_eq(_items_spawning(String(uid)), [], uid + " has no production item")
		check_eq(bool(d.get("producible", true)), false, uid + " flagged not producible")
		check(String(d.get("rank_role", "")) in ["captain", "lieutenant"], uid + " rank role")
	for cid in COMMANDERS:
		var items := _items_spawning(String(cid))
		check_eq(items.size(), 1, cid + " producible")
		if items.size() == 1:
			check_eq(String(Content.production(String(items[0])).get("trained_at", "")), String(COMMANDERS[cid]), cid + " trains at the Company HQ")
			check(not Content.production(String(items[0])).has("facility"), cid + " is not on any queue_unit list")
		check_eq(String(Content.unit(String(cid)).get("rank_role", "")), "commander", cid + " rank role")
		check(bool(Content.building(String(COMMANDERS[cid])).get("company_hq", false)), String(COMMANDERS[cid]) + " is a Company HQ")
