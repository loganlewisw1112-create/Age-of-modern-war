extends "res://tests/test_base.gd"
## MAPIO: scenario triggers (every when/then type, once / edge re-fire, save/load) and the G4
## victory presets (survive, destroy_target, reach_stage, hold_point; AND/OR; validation).

const MapIO = preload("res://sim/map_io.gd")
const T = preload("res://tests/test_map_io.gd")
const Triggers = preload("res://sim/systems/triggers.gd")
const Victory = preload("res://sim/systems/victory.gd")
const SaveSystem = preload("res://sim/save_system.gd")


## A file-map world on the flat test map. sc_patch is merged into the scenario.
func _world(sc_patch: Dictionary, name: String, overrides: Dictionary = {}) -> SimWorld:
	var sc := T.scenario()
	sc.merge(sc_patch, true)
	var p := T.write(name, T.flat(), sc)
	var c := MapIO.config_for(p, overrides)
	check(not c.has("error"), "config_for %s" % c.get("error", ""))
	var w := SimWorld.new_match(c)
	check(w != null, "world built for %s" % name)
	return w


func _events(w: SimWorld, ticks: int, type: String) -> Array:
	var out := []
	for i in ticks:
		w.step()
		for ev in w.events:
			if ev.type == type:
				out.append(ev)
		if w.match_state.ended:
			break
	return out


func _region(id: String, r: Rect2i) -> Dictionary:
	return {"id": id, "name": id, "rect": r}


func test_trig_time_message_grant_once() -> void:
	var w := _world({"triggers": [{"name": "brief", "when": {"type": "time_reached", "t": 2},
		"then": [{"type": "message", "text": "Hold the line"}, {"type": "grant", "slot": 1, "res": "ore", "amount": 250}]}]}, "t1.rtsmap")
	var ore0 := int(w.factions[1].stock.ore)
	var msgs := _events(w, 120, "TriggerMessage")
	check_eq(msgs.size(), 1, "message fired exactly once")
	if not msgs.is_empty():
		check_eq(String(msgs[0].text), "Hold the line", "message text")
		check(int(msgs[0].tick) >= 40 and int(msgs[0].tick) <= 45, "fired at ~2 s (tick %d)" % int(msgs[0].tick))
	check_eq(int(w.factions[1].stock.ore), ore0 + 250, "grant went through the ledger")
	check_eq(int(w.factions[1].stock.salvage), 77, "player stock from the file applied")
	T.cleanup()


func test_trig_region_spawn_reveal_ai_target() -> void:
	var w := _world({"regions": [_region("mid", Rect2i(20, 20, 6, 6)), _region("far", Rect2i(36, 2, 6, 6))],
		"entities": [{"kind": "unit", "def": "rifleman", "owner_slot": 0, "cell": Vector2i(14, 20)}],
		"triggers": [{"when": {"type": "unit_in_region", "region": "mid", "owner_slot": 0, "count": 1},
			"then": [{"type": "spawn", "slot": 1, "def": "b_militia", "count": 5, "region": "far"},
				{"type": "reveal", "slot": 0, "region": "far"}, {"type": "ai_target", "slot": 1, "region": "mid"}]}]}, "t2.rtsmap")
	var uid := -1
	for e in w.units_of(0):
		if w.cell_of(e.pos) == Vector2i(14, 20):
			uid = int(e.id)
	check(uid > 0, "placed unit exists")
	check_eq(Triggers.ai_target(w, 1), null, "no AI target yet")
	_events(w, 40, "TriggerFired")
	var n_before := w.units_of(1).size()
	do_cmd(w, 0, {"type": "move", "unit_ids": [uid], "target": Vector2(22.5, 22.5)})
	var fired := _events(w, 400, "TriggerFired")
	check_eq(fired.size(), 1, "region trigger fired once")
	var in_far := 0
	for e in w.units_of(1):
		if e.def == "b_militia" and Rect2i(36, 2, 6, 6).has_point(w.cell_of(e.pos)):
			in_far += 1
	check_eq(in_far, 5, "5 militia spawned inside 'far'")
	check_eq(w.units_of(1).size(), n_before + 5, "exactly 5 new units")
	check(w.is_visible(0, Vector2(38.5, 4.5)), "far region revealed to slot 0")
	w.run_ticks(9)
	check(w.is_visible(0, Vector2(38.5, 4.5)), "reveal persists across fog recompute")
	check_eq(Triggers.ai_target(w, 1), Vector2(23, 23), "AI target = region centre")
	T.cleanup()


func test_trig_destroyed_tag_win_and_edge_refire() -> void:
	var w := _world({"regions": [_region("gate", Rect2i(28, 28, 4, 4))],
		"entities": [{"kind": "building", "def": "b_bunker", "owner_slot": 1, "cell": Vector2i(30, 12), "tag": "radar"}],
		"triggers": [{"when": {"type": "unit_in_region", "region": "gate"}, "once": false, "then": [{"type": "message", "text": "edge"}]},
			{"when": {"type": "entity_destroyed", "tag": "radar"}, "then": [{"type": "win", "slot": 0}]}]}, "t3.rtsmap")
	var u := w.spawn_unit("rifleman", 0, Vector2(29.5, 29.5))
	var edges := _events(w, 20, "TriggerMessage").size()
	w.entities[u].pos = Vector2(10.5, 29.5)
	preload("res://sim/hot_state.gd").touch(w, u)  # CORE10K-3: direct pos/path write -> hot state
	edges += _events(w, 20, "TriggerMessage").size()
	w.entities[u].pos = Vector2(29.5, 29.5)
	preload("res://sim/hot_state.gd").touch(w, u)  # CORE10K-3: direct pos/path write -> hot state
	edges += _events(w, 20, "TriggerMessage").size()
	check_eq(edges, 2, "once=false fires on each false->true edge, not every tick")
	check(not w.match_state.ended, "radar alive: no win")
	var rid := -1
	for e in w.buildings_of(1):
		if String(e.get("tag", "")) == "radar":
			rid = int(e.id)
	check(rid > 0, "tagged bunker placed with its tag")
	w.destroy(rid, "test", 0)
	_events(w, 10, "MatchEnded")
	check(w.match_state.ended, "match ended by trigger")
	check_eq(int(w.match_state.get("winner_team", -1)), 0, "slot 0's team won")
	check_eq(String(w.match_state.reason), "trigger", "reason trigger")
	T.cleanup()


func test_trig_stage_and_units_below_lose_save_load() -> void:
	var w := _world({"triggers": [{"when": {"type": "stage_reached", "slot": 0, "stage": 9}, "then": [{"type": "grant", "slot": 0, "res": "credits", "amount": 1000}]},
		{"when": [{"type": "units_below", "slot": 1, "n": 1}, {"type": "time_reached", "ticks": 30}], "then": [{"type": "lose", "slot": 1}]}]},
		"t4.rtsmap", {"victory": "endless"})
	w.run_ticks(20)
	var sp := T.DIR.path_join("t4.sav")
	check_eq(SaveSystem.save(w, sp), "", "saved mid-scenario")
	var l: SimWorld = SaveSystem.load(sp)
	for x in [w, l]:
		var c0 := int(x.factions[0].credits)
		x.factions[0].stage = 9
		x.run_ticks(10)
		check(int(x.factions[0].credits) >= c0 + 1000, "stage trigger granted")
		for e in x.units_of(1):
			x.destroy(int(e.id), "test")
		x.run_ticks(10)
		check(not bool(x.factions[1].alive), "units_below AND time -> slot 1 lost")
	check_eq(l.state_hash(), w.state_hash(), "loaded world matches uninterrupted")
	T.cleanup()


func test_trig_validate_defs_reports_bad_refs() -> void:
	var sc := T.scenario()
	sc.regions = [_region("a", Rect2i(1, 1, 3, 3))]
	sc.triggers = [{"when": {"type": "nope"}, "then": [{"type": "message", "text": "x"}]},
		{"when": {"type": "unit_in_region", "region": "zzz"}, "then": [{"type": "spawn", "slot": 7, "def": "rifleman"}]},
		{"when": {"type": "entity_destroyed", "tag": "ghost"}, "then": []},
		{"when": {"type": "time_reached", "t": 1}, "then": [{"type": "grant", "slot": 0, "res": "gold", "amount": 1}]}]
	var codes := []
	for i in MapIO.validate(T.flat(), sc):
		codes.append(String(i.code))
	check_eq(codes.count("trigger_bad"), 6, "6 trigger problems (%s)" % str(MapIO.validate(T.flat(), sc)))


# ================================================================ victory presets
func _vic(op: String, terms: Array) -> Dictionary:
	return {"victory": {"victory": "combined", "victory_rules": {"op": op, "terms": terms}}}


func test_vic_survive_slot_or_hq() -> void:
	var w := _world(_vic("or", [{"type": "hq_elimination"}, {"type": "survive", "seconds": 3, "slot": 1}]), "v1.rtsmap")
	var end := _events(w, 100, "MatchEnded")
	check(w.match_state.ended, "survive ended the match")
	check_eq(int(w.match_state.winner_team), 1, "only slot 1's team can win by surviving")
	check_eq(w.match_state.terms, ["survive"], "terms")
	check(int(w.match_state.end_tick) >= 60 and int(w.match_state.end_tick) <= 61, "at 3 s (tick %d)" % int(w.match_state.end_tick))
	T.cleanup()


func test_vic_destroy_target_and_reach_stage_and() -> void:
	var sc := _vic("and", [{"type": "destroy_target", "tag": "depot1"}, {"type": "reach_stage", "stage": 9}])
	sc.entities = [{"kind": "building", "def": "b_bunker", "owner_slot": 1, "cell": Vector2i(30, 12), "tag": "depot1"}]
	var w := _world(sc, "v2.rtsmap")
	w.factions[0].stage = 9
	w.run_ticks(5)
	check(not w.match_state.ended, "AND: stage alone is not enough")
	for e in w.buildings_of(1):
		if String(e.get("tag", "")) == "depot1":
			w.destroy(int(e.id), "test", 0)
	w.run_ticks(2)
	check(w.match_state.ended, "AND satisfied")
	check_eq(int(w.match_state.winner_team), 0, "the target's own team never wins by destroying it")
	var p := Victory.progress(w, 1)
	check_eq(p.terms.size(), 2, "HUD rows for both presets")
	check(String(p.terms[0].label).begins_with("Destroy the target"), "destroy label")
	T.cleanup()


func test_vic_hold_point() -> void:
	var sc := _vic("or", [{"type": "hold_point", "region": "hill", "seconds": 2}])
	sc.regions = [_region("hill", Rect2i(22, 22, 4, 4))]
	sc.entities = [{"kind": "unit", "def": "rifleman", "owner_slot": 0, "cell": Vector2i(23, 23)}]
	var w := _world(sc, "v3.rtsmap")
	_events(w, 120, "MatchEnded")
	check(w.match_state.ended, "hold_point won")
	check_eq(int(w.match_state.winner_team), 0, "the holder's team won")
	check(int(w.match_state.end_tick) > 40, "needed consecutive samples (tick %d)" % int(w.match_state.end_tick))
	T.cleanup()


func test_vic_validation_of_presets() -> void:
	var bad := [[{"type": "destroy_target"}], [{"type": "reach_stage", "stage": 20}], [{"type": "hold_point", "seconds": 30}],
		[{"type": "survive", "seconds": 0}]]
	for terms in bad:
		var c := SimWorld.default_config()
		c.victory = "combined"
		c.victory_rules = {"op": "and", "terms": terms}
		check(Victory.validate_rules(c) != "", "rejected %s" % str(terms))
	var ok := SimWorld.default_config()
	ok.victory = "combined"
	ok.victory_rules = {"op": "or", "terms": [{"type": "survive", "seconds": 600}, {"type": "hq_elimination"}]}
	check_eq(Victory.validate_rules(ok), "", "survive OR hq accepted")
	var sc := T.scenario()
	sc.merge(_vic("or", [{"type": "hold_point", "region": "nowhere", "seconds": 30}]), true)
	var codes := []
	for i in MapIO.validate(T.flat(), sc):
		codes.append(String(i.code))
	check(codes.has("victory_bad"), "unknown victory region reported (%s)" % str(codes))


func test_vic_hqless_scenario_sides() -> void:
	var sc := {"start_packages": false, "entities": [{"kind": "building", "def": "hq", "owner_slot": 0, "cell": Vector2i(6, 6)},
		{"kind": "unit", "def": "b_militia", "owner_slot": 1, "cell": Vector2i(38, 38)}]}
	var w := _world(sc, "v4.rtsmap")
	w.run_ticks(10)
	check(bool(w.factions[1].alive), "HQ-less side with a unit is still in")
	check_eq(w.buildings_of(1).size(), 0, "no start package for slot 1")
	for e in w.units_of(1):
		w.destroy(int(e.id), "test")
	w.run_ticks(3)
	check(not bool(w.factions[1].alive), "HQ-less side out when it has nothing left")
	check(w.match_state.ended and int(w.match_state.winner_team) == 0, "slot 0 wins by elimination")
	T.cleanup()
