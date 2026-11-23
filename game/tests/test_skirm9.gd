extends "res://tests/test_base.gd"
## G9 SKIRM9 Done-when #6: fair-capped Tide siege spawns + optional director_adapt flag.

const Skirm9 = preload("res://sim/systems/skirm9.gd")
const Director71 = preload("res://sim/systems/director71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Creep = preload("res://sim/systems/creep.gd")
const H := 0
const M := 1


func _machine_world(extra: Dictionary = {}) -> SimWorld:
	var c := {
		"victory": "endless",
		"sides": [
			{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "H", "team": 0},
			{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 1},
		],
	}
	c.merge(extra, true)
	var w := make_world(c)
	w.ai_state = {}
	Creep.enable(w)
	for i in 4:
		w.step()
	return w


func test_inactive_in_last_protocol() -> void:
	var w := LastProtocol.make_config(319, "industrial_heartland_m")
	var ws := SimWorld.new_match(w)
	for i in 8:
		if ws != null:
			ws.step()
	check(ws != null, "LP match")
	check(not Skirm9.active(ws), "skirmish siege off in LP")
	check(Skirm9.board(ws).is_empty(), "no skirm9 board in LP")


func test_director_adapt_flag_default_off() -> void:
	var w := _machine_world()
	check(Skirm9.active(w), "active on machine skirmish")
	check(not Skirm9.director_adapt(w), "rules default director_adapt false")
	var w2 := _machine_world({"skirm9": {"director_adapt": true}})
	check(Skirm9.director_adapt(w2), "cfg.skirm9.director_adapt overrides rules")


func test_spawn_wave_fair_caps() -> void:
	var w := _machine_world()
	var s := Skirm9._st(w)
	s.dread = 0.92
	var roster: Array = Skirm9.capped_roster(w)
	check(not roster.is_empty(), "mixed/siege roster non-empty at high dread")
	check(roster.size() <= int(Skirm9.R().get("max_per_wave", 2)), "per-wave cap")
	for def_id in roster:
		check(String(Content.unit(String(def_id)).get("g71_siege", "")) != "", "siege-tagged def")
	var spawned: Array = Skirm9.spawn_wave(w, M)
	check(not spawned.is_empty(), "spawned siege units")
	check(Skirm9.harness_ok(w), "harness marked")
	check_eq(Skirm9._siege_alive(w, M), spawned.size(), "alive siege count")
	var more: Array = Skirm9.spawn_wave(w, M)
	var cap := int(Skirm9.R().get("max_siege_alive", 6))
	check(Skirm9._siege_alive(w, M) <= cap, "total siege alive respects cap")
	check(more.size() <= maxi(cap - spawned.size(), 0), "second wave respects remaining cap")


func test_adapt_changes_roster_when_enabled() -> void:
	var w := _machine_world({"skirm9": {"director_adapt": true}})
	var s := Skirm9._st(w)
	s.dread = 0.92
	Director71.note_kill(s, "laser")
	Director71.note_kill(s, "laser")
	Director71.note_kill(s, "beam")
	check_eq(Director71.counter_for(s), "smoke", "adapt counter smoke")
	var with_bonus: Array = Skirm9.capped_roster(w)
	s.adapt = {}
	s.adapt_counter = ""
	var plain: Array = Skirm9.capped_roster(w)
	check(with_bonus.size() >= plain.size(), "adapt roster at least plain size")
	check(
		Director71.siege_roster(0.92, "smoke").size() > Director71.siege_roster(0.92, "").size(),
		"director bonus expands raw siege roster"
	)