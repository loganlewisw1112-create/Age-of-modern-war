extends "res://tests/test_base.gd"
## G10 Task 17: Human A Counter-Ghost full corps (owner addendum 171).

const CG = preload("res://sim/systems/counter_ghost10.gd")
const GhostExo10 = preload("res://sim/systems/ghost_exo10.gd")
const Exo = preload("res://sim/systems/exo.gd")
func _human_world(stage: int = 10) -> SimWorld:
	Content.load_all()
	var boot := clampi(stage, 7, 9)
	var c := SimWorld.default_config()
	c.sides = [
		{"faction": "human_a", "stage": boot, "credits": 8000, "ai": false, "name": "A", "team": 0},
		{"faction": "shadow_coalition", "stage": boot, "credits": 8000, "ai": false, "name": "X", "team": 1},
	]
	var w: SimWorld = SimWorld.new_match(c)
	if w != null:
		w.factions[0].stage = stage
		w.factions[1].stage = stage
	return w


func _coalition_world(stage: int = 10) -> SimWorld:
	Content.load_all()
	var boot := clampi(stage, 7, 9)
	var c := SimWorld.default_config()
	c.sides = [
		{"faction": "shadow_coalition", "stage": boot, "credits": 8000, "ai": false, "name": "X", "team": 0},
		{"faction": "human_a", "stage": boot, "credits": 8000, "ai": false, "name": "A", "team": 1},
	]
	var w: SimWorld = SimWorld.new_match(c)
	if w != null:
		w.factions[0].stage = stage
		w.factions[1].stage = stage
	return w


func test_rules_ownership_weaker_no_coalition() -> void:
	Content.load_all()
	var r: Dictionary = Content.rules().get("g10_counterghost", {})
	check(not r.is_empty(), "g10_counterghost rules")
	check_eq(String(r.get("faction", "")), "human_a", "Human A ownership")
	check_eq(int(r.get("stage_min", 0)), 10, "Stage 10")
	check(bool(r.get("no_coalition_production", false)), "no coalition production")
	check(bool(r.get("no_cn", false)), "no CN")
	check(bool(r.get("no_blackglass", false)), "no Blackglass")
	for lo in ["interceptor", "bulwark", "seeker", "ward"]:
		check(CG.weaker_than_death(lo), "weaker than Death: %s" % lo)
		var stats: Dictionary = CG.loadout_stats(lo)
		check(float(stats.get("camo", 1.0)) < 0.9, "camo < Death %s" % lo)
	check(not Content.unit("a_cg_intercept").is_empty(), "a_cg_intercept def")
	check(not Content.unit("a_cg_breach").is_empty(), "a_cg_breach Bulwark def")
	check(not Content.unit("a_cg_recon").is_empty(), "a_cg_recon Seeker def")
	check(not Content.unit("a_cg_ward_prime").is_empty(), "ward prime")
	check_eq(String(Content.unit("a_cg_intercept").get("faction", "")), "human_a", "CG unit human_a")
	check(CG.no_coalition_production("a_cg_intercept"), "CG not coalition prod")
	check(Exo.is_counter_ghost_def("a_cg_intercept"), "exo CG hook")
	check(not Exo.is_ghost_suit_def("a_cg_intercept"), "CG not ghost regiment")
	check(not Exo.is_suit_def("a_cg_intercept"), "CG not Pre-G10 exo_suit")


func test_org_formations_specialties_wards() -> void:
	var w := _human_world(10)
	var four := CG.form_squad(w, 0, "4op", "interceptor")
	var six := CG.form_squad(w, 0, "6op", "bulwark")
	var ward := CG.form_squad(w, 0, "ward_pair")
	check(four > 0 and six > 0 and ward > 0, "form squads")
	check_eq(CG.squad_state(w, four).ops.size(), 4, "4op")
	check_eq(CG.squad_state(w, six).ops.size(), 6, "6op")
	check_eq(CG.squad_state(w, ward).ops.size(), 2, "ward pair")
	check_eq(String(CG.squad_state(w, four).loadout), "interceptor", "interceptor loadout")
	check_eq(String(CG.squad_state(w, six).loadout), "bulwark", "bulwark loadout")
	check_eq(String(CG.squad_state(w, ward).loadout), "ward", "ward loadout")
	var roles: Array = CG.squad_state(w, four).roles
	for need in ["lead", "sensor", "gunner", "specialist"]:
		check(roles.has(need), "role %s" % need)
	check_eq(CG.assign_specialty(w, int(CG.squad_state(w, four).ops[0]), "hound"), "", "specialty hound")
	check_eq(CG.assign_specialty(w, int(CG.squad_state(w, four).ops[1]), "netman"), "", "specialty netman")
	check_eq(CG.mark_legend(w, four, true), "", "legend")
	check(bool(CG.squad_state(w, four).legend), "legend flag")
	check_eq(CG.bind_vip(w, ward, 99), "", "bind VIP")
	check_eq(int(CG.squad_state(w, ward).vip_id), 99, "vip stored")
	check(CG.validate_intent(w, 0, ward, "cg_hunt_ghosts") != "", "wards refuse hunt peel")
	check_eq(CG.assign_intent(w, 0, four, "cg_escort_vip"), "", "escort intent")
	# Coalition cannot form CG
	var wx := _coalition_world(10)
	check_eq(CG.form_squad(wx, 0, "4op", "seeker"), -1, "coalition cannot form CG")
	# Stage gate
	var wlow := _human_world(8)
	check_eq(CG.form_squad(wlow, 0, "4op", "seeker"), -1, "stage 8 blocked")


func test_vehicle_homes_shade_dart() -> void:
	Content.load_all()
	var homes: Dictionary = Content.rules().get("g10_counterghost", {}).get("vehicle_homes", {})
	check_eq(homes.size(), 13, "13 dedicated vehicle homes")
	for veh in homes.keys():
		var home := String(homes[veh])
		check(not Content.unit(String(veh)).is_empty(), "vehicle def %s" % veh)
		check(not Content.building(home).is_empty(), "home building %s" % home)
		check(CG.can_service_at(String(veh), home), "service match %s@%s" % [veh, home])
		check_eq(Exo.cg_home_for(String(veh)), home, "exo home hook %s" % veh)
		# No shared blob: wrong home fails
		var wrong := "a_cg_watch_helipad" if home != "a_cg_watch_helipad" else "a_cg_medevac_helipad"
		check(not CG.can_service_at(String(veh), wrong), "reject wrong home %s" % veh)
		check_eq(String(Content.unit(String(veh)).get("cg_home", "")), home, "unit cg_home field")
		check_eq(String(Content.production(String(veh)).get("facility", "")), home, "prod facility = home")
	check_eq(CG.shade_dart_board(4), "", "shade dart 4-op ok")
	check(CG.shade_dart_board(6) != "", "shade dart rejects 6-op")
	var sd: Dictionary = Content.unit("a_cg_shade_dart")
	check(bool(sd.get("lift_fan", false)), "lift-fan")
	check(bool(sd.get("no_traditional_rotor", false)), "no traditional rotor")
	check(bool(sd.get("detectable", false)), "still detectable")
	check(bool(sd.get("not_silent_rotor", false)), "not silent rotor")
	# Corps buildings present; kennel is not a vehicle garage
	for b in ["a_cg_garage", "a_cg_kennel_annex", "a_cg_suit_cage", "a_cg_command", "a_cg_workshop"]:
		check(not Content.building(b).is_empty(), "corps bld %s" % b)
	check(not bool(Content.building("a_cg_kennel_annex").get("cg_home", false)), "kennel not vehicle home")


func test_sweep_disable_strip_recover_scenario() -> void:
	var w := _human_world(10)
	# Ghost target on coalition side
	var sid := GhostExo10.form_squad(w, 1, "4op", "death")
	check(sid > 0, "ghost squad")
	var gop := int(GhostExo10.squad_state(w, sid).ops[0])
	check_eq(CG.cg_sweep(w, 0), "", "sweep")
	var v0 := GhostExo10.visibility(w, gop, 0)
	check(v0 > 0.0, "sweep raises visibility path")
	check_eq(CG.cg_intercept(w, 0, gop), "", "intercept")
	check_eq(CG.cg_disable(w, 0, gop, "emp"), "", "emp disable")
	check_eq(CG.cg_disable(w, 0, gop, "net"), "", "net disable")
	var eng := w.spawn_unit("a_cg_killswitch_tech", 0, Vector2(5.5, 5.5))
	check_eq(CG.cg_strip_killswitch(w, 0, gop, eng, true), "", "strip under fire")
	for i in 20:
		w.tick += 1
		CG.tick(w)
	var track := CG.track_feed(w, 0)
	check(int(track.get("strips", 0)) >= 1, "strip feeds CG track")
	check(not bool(track.get("research9", true)), "not Research9")
	check(not bool(track.get("coalition_tech", true)), "not Coalition tech")
	check_eq(CG.cg_recover_suit(w, 0, gop, false), "", "recover")
	for i in 12:
		w.tick += 1
		CG.tick(w)
	track = CG.track_feed(w, 0)
	check(int(track.get("suits", 0)) >= 1, "suit recovery on CG track")
	# Happy path scenario
	var w2 := _human_world(10)
	var gs := GhostExo10.form_squad(w2, 1, "4op", "death")
	var g2 := int(GhostExo10.squad_state(w2, gs).ops[0])
	var sc := CG.run_scenario(w2, 0, g2, 1, {})
	check(bool(sc.get("success", false)), "scenario success")
	check(bool(sc.get("done", false)), "scenario done")
	for p in ["detect", "intercept", "disable", "strip", "recover"]:
		check((sc.get("history", []) as Array).has(p), "phase %s" % p)
	# Late strip failure
	var w3 := _human_world(10)
	var gs3 := GhostExo10.form_squad(w3, 1, "4op", "death")
	var g3 := int(GhostExo10.squad_state(w3, gs3).ops[0])
	var sc3 := CG.run_scenario(w3, 0, g3, 1, {"late_strip": true})
	check(bool(sc3.get("failed", false)), "late strip fail")
	check_eq(String(sc3.get("fail_reason", "")), "late_strip", "late_strip reason")
	# Lost recovery race
	var w4 := _human_world(10)
	var gs4 := GhostExo10.form_squad(w4, 1, "4op", "death")
	var g4 := int(GhostExo10.squad_state(w4, gs4).ops[0])
	var sc4 := CG.run_scenario(w4, 0, g4, 1, {"lose_race": true})
	check(bool(sc4.get("failed", false)), "lost race fail")
	check_eq(String(sc4.get("fail_reason", "")), "lost_recovery_race", "race reason")


func test_spider_foam_ghost_counters_exo_hook() -> void:
	var w := _human_world(10)
	var bot := w.spawn_unit("a_cg_spider_killer", 0, Vector2(8.5, 8.5))
	check_eq(CG.spider_clear(w, 0, bot, "flechette", "spider"), "", "flechette clear")
	check_eq(CG.spider_clear(w, 0, bot, "sticky_foam", "nest_approach"), "", "foam nest")
	check_eq(CG.spider_clear(w, 0, bot, "ultrasonic_peel", "spider"), "", "ultrasonic")
	check(CG.spider_cleared(w, 0, "spider"), "spider cleared")
	var d := Content.unit("a_cg_spider_killer")
	check(bool(d.get("no_coalition_camo", false)), "no coalition camo")
	check(bool(d.get("no_reaper", false)), "no reaper")
	check(bool(d.get("bright", false)), "bright readable")
	var foam_exo := CG.apply_foam(w, "exo", true)
	check(float(foam_exo.get("duration_mult", 1.0)) < 1.0, "hardened joints shorten foam")
	check(not bool(foam_exo.get("immune", true)), "no foam immunity")
	var foam_drone := CG.apply_foam(w, "drone", true)
	check_eq(float(foam_drone.get("duration_mult", 0.0)), 1.0, "drones full foam")
	check_eq(CG.counter_to_ghost("judge_backdoor"), "detect_and_jam", "judge counter")
	check_eq(CG.counter_to_ghost("warden_corridor"), "bulwark_hold", "warden counter")
	check_eq(CG.counter_to_ghost("shade_designate"), "sensor_sweep", "shade counter")
	check_eq(CG.counter_to_ghost("sergeant_loss"), "squad_degrade_readable", "sergeant counter")
	check_eq(CG.counter_to_ghost("guardian_mule_denial"), "contest_suit_before_overcharge", "mule counter")
	check_eq(CG.counter_to_ghost("ace_mk_recover"), "strip_then_recover", "ace counter")
	# exo.gd preserves Pre-G10 + forwards CG tick
	check(Exo.is_suit_def("a_exo_rifle"), "Pre-G10 suit preserved")
	var before := int(Exo._st(w).get("ejected", 0))
	Exo.tick(w)
	check_eq(int(Exo._st(w).get("ejected", 0)), before, "tick no invent ejects")
	check(CG.active(w), "CG state active after ops")
	for intent in CG.intents():
		check(intent.begins_with("cg_"), "intent %s" % intent)
