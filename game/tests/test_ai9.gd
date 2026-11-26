extends "res://tests/test_base.gd"

const Adapt9 = preload("res://sim/ai/adapt9.gd")
const Generals9 = preload("res://sim/ai/generals9.gd")
const Dipl9 = preload("res://sim/ai/dipl9.gd")
const Count9 = preload("res://sim/systems/count9.gd")
const Creep = preload("res://sim/systems/creep.gd")


func _three_side() -> SimWorld:
	var cfg := {
		"seed": 9901,
		"victory": "endless",
		"sides": [
			{"faction": "human_a", "stage": 8, "credits": 2500, "ai": false, "name": "A", "team": 0},
			{"faction": "human_b", "stage": 8, "credits": 2500, "ai": false, "name": "B", "team": 1},
			{"faction": "machine", "stage": 8, "credits": 2500, "ai": false, "name": "M", "team": 2}
		]
	}
	var w := make_world(cfg)
	Creep.enable(w)
	return w


func test_adapt_evidence_changes_composition() -> void:
	var w := make_world({"seed": 9902})
	var before: Array = Adapt9.recommend_comp(w, 0)
	for i in 4:
		Adapt9.observe_kill(w, 0, "m_swarm", "laser")
	var p := Adapt9.pressure(w, 0)
	check_eq(String(p.get("counter_bias", "")), "smoke", "laser evidence shifts counter")
	check(Adapt9.recommend_comp(w, 0) != before, "recommended composition changes")


func test_named_generals_have_distinct_doctrine() -> void:
	var w := make_world({"seed": 9903})
	var drive := {"playstyle": "combined", "stance": "balanced"}
	check_eq(Generals9.attach(w, 1, drive, "iron_wall"), "iron_wall", "preferred persona")
	check_eq(String(drive.persona_name), "Marshal Iron Wall", "readable name")
	check(Generals9.doctrine("iron_wall") != Generals9.doctrine("storm_spear"), "doctrines differ")


func test_diplomacy_forms_and_breaks_machine_truce() -> void:
	var w := _three_side()
	Dipl9.tick(w)
	check(not Count9.coalition_active(w), "opening workers and HQ do not trigger a truce")
	var mfs := Creep.machine_fids(w)
	check(not mfs.is_empty(), "machine faction found")
	for i in 6:
		w.spawn_unit("m_swarm", int(mfs[0]), Vector2(30 + i, 30))
	check(Dipl9.evaluate_machine_threat(w) >= float(Dipl9.R().get("form_at", 5.0)), "machine threat high")
	Dipl9.tick(w)
	check(Count9.coalition_active(w), "human truce formed")
	check(w.is_ally(0, 1), "friendly fire relationship blocked by coalition team")
	for e in w.units_of(int(mfs[0])):
		w.destroy(int(e.id), "ai9_test")
	Dipl9.tick(w)
	check(not Count9.coalition_active(w), "truce breaks when threat drops")
	check(not w.is_ally(0, 1), "original teams restored")


func test_hard_differs_by_intelligence_not_cheats() -> void:
	var d: Dictionary = Content.rules().get("g71_ai9", {}).get("difficulty", {})
	check(int(d.hard.scout_interval) < int(d.easy.scout_interval), "Hard scouts sooner")
	check(int(d.hard.reaction_delay) < int(d.easy.reaction_delay), "Hard reacts sooner")
	for id in ["easy", "normal", "hard"]:
		check(not (d[id] as Dictionary).has("resource_mult"), "%s has no resource cheat" % id)
		check(not (d[id] as Dictionary).has("hp_mult"), "%s has no hp cheat" % id)
		check(not (d[id] as Dictionary).has("damage_mult"), "%s has no damage cheat" % id)


func test_multiphase_operation_contract() -> void:
	var w := make_world({"seed": 9904})
	var op := {"type": "attack", "phase": "", "target": Vector2(40, 40)}
	var got := []
	for i in 4:
		got.append(Generals9.advance_operation(w, 1, op))
	check_eq(got, ["recon", "fix", "assault", "exploit"], "recon-fix-assault-exploit")


func test_adaptation_counts_each_battle_tick_and_limits_observers() -> void:
	var w := _three_side()
	for i in 2:
		w.events.clear()
		w.tick += 1
		w.emit("EntityDestroyed", {"id": 100 + i, "owner": 0, "killer_owner": 2, "def": "rifleman", "weapon_tag": "laser"})
		Adapt9.tick(w)
		Adapt9.tick(w)
	var victim := Adapt9.observed_pressure(w, 0)
	check_eq(victim.get("kill_mix", {}).get("laser", 0), 2, "each tick counts once, including repeated batch sizes")
	check_eq(victim.get("counter_bias", ""), "smoke", "laser losses inform counters")
	check(Adapt9.observed_pressure(w, 1).is_empty(), "third party has no intelligence from an unseen kill")
	check_eq(Adapt9.pressure(w, 2).get("kill_mix", {}).get("laser", 0), 2, "aggressor retains its own evidence")
