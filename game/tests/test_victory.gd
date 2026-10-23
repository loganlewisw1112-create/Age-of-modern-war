extends "res://tests/test_base.gd"
## G3a victory, territory, teams, allied vision (agent V3-victory). CONTRACTS_G3a.md section 4.

const Victory = preload("res://sim/systems/victory.gd")
const Territory = preload("res://sim/systems/territory.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SaveSystem = preload("res://sim/save_system.gd")


# ---------------------------------------------------------------- helpers
func _side(faction: String, team: int, credits: int = 2500) -> Dictionary:
	return {"faction": faction, "stage": 8, "credits": credits, "ai": false, "name": faction, "team": team}


func _cfg(sides: Array, victory: String = "hq_elimination", extra: Dictionary = {}) -> Dictionary:
	var c := SimWorld.default_config()
	c.sides = sides
	c.victory = victory
	c.merge(extra, true)
	return c


func _world(sides: Array, victory: String = "hq_elimination", extra: Dictionary = {}) -> SimWorld:
	var c := _cfg(sides, victory, extra)
	var why := SimWorld.validate_config(c)
	check_eq(why, "", "config valid")
	return SimWorld.new_match(c) if why == "" else null


func _hq(w: SimWorld, fid: int):
	for b in w.buildings_of(fid):
		if bool(Content.building(String(b.def)).get("is_hq", false)):
			return b
	return null


func _kill_units(w: SimWorld, fid: int) -> void:
	for u in w.units_of(fid):
		w.destroy(int(u.id), "test")


func _unit(w: SimWorld, fid: int, near: Vector2i, tough: bool = true) -> int:
	var c := Movement.nearest_free_cell(w, near, "foot")
	var id := w.spawn_unit("rifleman", fid, Vector2(c) + Vector2(0.5, 0.5))
	if tough:
		w.entities[id].hp = 100000.0
		w.entities[id].max_hp = 100000.0
	return id


func _bridge(w: SimWorld):
	return Victory.bridge_entity(w)


func _bridge_cell(w: SimWorld) -> Vector2i:
	var b = _bridge(w)
	return w.cell_of(b.pos)


## One fid-unit at the centre of every counted sector whose centre is farther than avoid_r from
## avoid (the enemy HQ). Returns the number of sectors occupied.
func _occupy(w: SimWorld, fid: int, avoid: Vector2, avoid_r: float) -> int:
	var k := 0
	for s in Territory.sector_count(w):
		if not Territory.is_counted(w, s):
			continue
		var r := Territory.sector_rect(w, s)
		var centre := Vector2(r.position) + Vector2(r.size) * 0.5
		if centre.distance_to(avoid) < avoid_r:
			continue
		var c := Movement.nearest_free_cell(w, Vector2i(centre), "foot")
		if Territory.sector_of(w, Vector2(c) + Vector2(0.5, 0.5)) != s:
			continue
		_unit(w, fid, c)
		k += 1
	return k


## Steps until the match ends or max_ticks pass. Returns the MatchEnded events seen.
func _run(w: SimWorld, max_ticks: int) -> Array:
	var ended := []
	for i in max_ticks:
		w.step()
		for ev in w.events:
			if ev.type == "MatchEnded":
				ended.append(ev)
		if w.match_state.ended:
			break
	return ended


func _count(w: SimWorld, n: int, type: String) -> int:
	var k := 0
	for i in n:
		w.step()
		for ev in w.events:
			if ev.type == type:
				k += 1
	return k


# ---------------------------------------------------------------- MATCH-01
func test_match01_three_sides_independent_credits_and_factions() -> void:
	var w := _world([_side("human_a", 0, 2500), _side("human_b", 1, 4000), _side("machine", 2, 1000)])
	if w == null:
		return
	check_eq(w.factions.size(), 3, "three sides")
	var defs := ["human_a", "human_b", "machine"]
	var creds := [2500, 4000, 1000]
	var spawns := {}
	for fid in 3:
		var f: Dictionary = w.factions[fid]
		check_eq(String(f.faction_def), defs[fid], "faction def of side %d" % fid)
		check_eq(int(f.credits), creds[fid], "independent starting credits of side %d" % fid)
		check_eq(int(f.team), fid, "own team")
		var hq = _hq(w, fid)
		check(hq != null and String(hq.def) == Content.role(defs[fid], "hq"), "side %d HQ is its faction's hq role" % fid)
		spawns[f.spawn] = true
		for u in w.units_of(fid):
			check_eq(String(Content.unit(String(u.def)).get("faction", defs[fid])), defs[fid], "start unit faction side %d" % fid)
	check_eq(spawns.size(), 3, "distinct spawns")
	for a in 3:
		for b in 3:
			check_eq(w.is_enemy(a, b), a != b, "FFA enemies %d/%d" % [a, b])
	check(w.spend(1, {"credits": 500}, "test"), "side 1 spends")
	check_eq(int(w.factions[0].credits), 2500, "side 0 untouched by side 1 spend")
	check_eq(int(w.factions[1].credits), 3500, "side 1 paid")
	check_eq(int(w.factions[2].credits), 1000, "side 2 untouched by side 1 spend")
	var ended := _run(w, 200)
	check(ended.is_empty() and not w.match_state.ended, "3-side match keeps running")
	for fid in 3:
		check(bool(w.factions[fid].alive), "side %d alive" % fid)


# ---------------------------------------------------------------- VICT-01
func test_vict01_territory_60_percent_wins() -> void:
	var w := make_world({"victory": "territory", "victory_params": {"percent": 60}})
	_kill_units(w, 1)
	var st := Territory.state(w)
	check(int(st.total) > 30, "most sectors count (total %d)" % int(st.total))
	var occ := _occupy(w, 0, (_hq(w, 1).pos as Vector2), 24.0)
	check(float(occ) >= 0.6 * float(st.total), "occupied enough sectors (%d of %d)" % [occ, int(st.total)])
	var ended := _run(w, 180)
	check(ended.is_empty(), "no win before capture_seconds")
	check(Territory.percent(w, 0) < 60.0, "nothing captured before 9 s")
	ended = _run(w, 300)
	check_eq(ended.size(), 1, "MatchEnded once")
	check(w.match_state.ended, "territory match ended")
	check_eq(int(w.match_state.winner_team), 0, "team 0 won")
	check_eq(int(w.match_state.winner), 0, "winner fid (G1 compat)")
	check_eq(w.match_state.winners, [0], "winners list")
	check_eq(String(w.match_state.reason), "territory", "reason")
	check(Territory.percent(w, 0) >= 60.0, "owns >= 60%% (%.1f)" % Territory.percent(w, 0))
	check(w.tick >= 200 and w.tick <= 260, "won right after capture_seconds (tick %d)" % w.tick)
	if not ended.is_empty():
		check_eq(int(ended[0].winner_team), 0, "event winner_team")
		check_eq(ended[0].winners, [0], "event winners")


func test_vict01_territory_sticky_and_recapture() -> void:
	var w := make_world({"victory": "endless"})
	_kill_units(w, 1)
	var s := Territory.sector_of(w, Vector2(42.5, 30.5))
	var r := Territory.sector_rect(w, s)
	var mid := r.position + r.size / 2
	var mine := _unit(w, 0, mid)
	var caps := []
	for i in 260:
		w.step()
		for ev in w.events:
			if ev.type == "SectorCaptured" and int(ev.sector) == s:
				caps.append(ev)
	check_eq(Territory.sector_owner(w, s), 0, "team 0 captured the sector")
	check(caps.size() == 1 and int(caps[0].team) == 0 and int(caps[0].prev_team) == -1, "SectorCaptured emitted once for the sector")
	w.destroy(mine, "test")
	w.run_ticks(300)
	check_eq(Territory.sector_owner(w, s), 0, "ownership is sticky when the sector empties")
	var foe := _unit(w, 1, mid)
	var other := _unit(w, 0, mid + Vector2i(2, 0))
	w.run_ticks(300)
	check_eq(Territory.sector_owner(w, s), 0, "contested sector never flips")
	check_eq(int(Territory.sector_capture(w, s).team), -1, "contested: no candidate")
	w.destroy(other, "test")
	w.run_ticks(150)
	check_eq(Territory.sector_owner(w, s), 0, "not yet recaptured after 7.5 s")
	w.run_ticks(120)
	check_eq(Territory.sector_owner(w, s), 1, "team 1 recaptured after capture_seconds")
	check(w.entities.has(foe), "capturer alive")


func test_vict01_hold_bridge_300s_wins() -> void:
	var w := make_world({"victory": "hold_bridge", "victory_params": {"seconds": 300}})
	_kill_units(w, 1)
	_unit(w, 0, _bridge_cell(w))
	var ended := _run(w, 3000)
	check(ended.is_empty(), "not won after 150 s")
	var p := Victory.progress(w, 0)
	check_eq(p.terms.size(), 1, "one term")
	if p.terms.size() == 1:
		check_eq(String(p.terms[0].type), "hold_bridge", "term type")
		check(int(p.terms[0].value) >= 145 and int(p.terms[0].value) <= 150, "held ~149 s (%d)" % int(p.terms[0].value))
		check_eq(int(p.terms[0].target), 300, "target 300 s")
		check(not bool(p.terms[0].satisfied), "not satisfied yet")
	ended = _run(w, 3300)
	check_eq(ended.size(), 1, "MatchEnded once")
	check_eq(int(w.match_state.winner_team), 0, "team 0 holds and wins")
	check_eq(String(w.match_state.reason), "hold_bridge", "reason")
	check(w.tick >= 6000 and w.tick <= 6060, "won after 300 s of holding (tick %d)" % w.tick)


func test_vict01_hold_bridge_contested_and_ruined_resets() -> void:
	var w := make_world({"victory": "hold_bridge", "victory_params": {"seconds": 30}})
	_kill_units(w, 1)
	var bc := _bridge_cell(w)
	_unit(w, 0, bc)
	w.run_ticks(400)
	var vs: Dictionary = w.sys_state.victory
	check_eq(int(vs.bridge_holder), 0, "team 0 holds")
	check(int(vs.bridge_secs) >= 18, "counting (%d s)" % int(vs.bridge_secs))
	var foe := _unit(w, 1, bc + Vector2i(1, 1))
	w.run_ticks(21)
	check_eq(int(vs.bridge_holder), -1, "contested: nobody holds")
	check_eq(int(vs.bridge_secs), 0, "contested: counter reset")
	check(Victory.progress(w, 0).terms[0].value == 0, "HUD value reset")
	w.destroy(foe, "test")
	w.run_ticks(21)
	check_eq(int(vs.bridge_holder), 0, "team 0 holds again")
	check(int(vs.bridge_secs) <= 1, "counter restarted from 0")
	w.destroy(int(_bridge(w).id), "test")
	check_eq(String(_bridge(w).state), "ruined", "bridge ruined")
	var ended := _run(w, 800)
	check_eq(int(vs.bridge_holder), -1, "ruined bridge cannot be held")
	check(ended.is_empty() and not w.match_state.ended, "no win on a ruined bridge")
	check_eq(String(Victory.progress(w, 0).terms[0].bridge_state), "ruined", "HUD shows ruined")


func test_vict01_and_needs_both() -> void:
	var rules := {"op": "and", "terms": [{"type": "territory", "percent": 60}, {"type": "hold_bridge", "seconds": 30}]}
	var w := make_world({"victory": "combined", "victory_rules": rules})
	_kill_units(w, 1)
	_occupy(w, 0, (_hq(w, 1).pos as Vector2), 24.0)
	var ended := _run(w, 300)
	check(Territory.percent(w, 0) >= 60.0, "territory term met")
	check(ended.is_empty(), "AND: territory alone does not win")
	var p := Victory.progress(w, 0)
	check_eq(String(p.op), "and", "progress op")
	check(bool(p.terms[0].satisfied) and not bool(p.terms[1].satisfied), "checklist: territory yes, bridge no")
	_unit(w, 0, _bridge_cell(w))
	ended = _run(w, 800)
	check_eq(ended.size(), 1, "AND: both terms win")
	check_eq(String(w.match_state.reason), "combined", "reason combined")
	check_eq(w.match_state.terms, ["territory", "hold_bridge"], "both terms satisfied")


func test_vict01_or_needs_one() -> void:
	var rules := {"op": "or", "terms": [{"type": "territory", "percent": 100}, {"type": "hold_bridge", "seconds": 30}]}
	var w := make_world({"victory": "combined", "victory_rules": rules})
	_kill_units(w, 1)
	_unit(w, 0, _bridge_cell(w))
	var ended := _run(w, 800)
	check_eq(ended.size(), 1, "OR: one term wins")
	check_eq(int(w.match_state.winner_team), 0, "winner")
	check_eq(w.match_state.terms, ["hold_bridge"], "only the bridge term")
	check(Territory.percent(w, 0) < 100.0, "territory not met")


func test_vict01_qa011_endless_never_ends_when_rivals_die() -> void:
	var w := _world([_side("human_a", 0), _side("human_b", 1), _side("machine", 2)], "endless")
	if w == null:
		return
	_unit(w, 0, _bridge_cell(w))
	w.destroy(int(_hq(w, 1).id), "test")
	w.destroy(int(_hq(w, 2).id), "test")
	var side := 0
	var team := 0
	var ended := 0
	for i in 900:
		w.step()
		for ev in w.events:
			match String(ev.type):
				"SideEliminated":
					side += 1
				"TeamEliminated":
					team += 1
				"MatchEnded":
					ended += 1
	check_eq(side, 2, "both rivals eliminated once")
	check_eq(team, 2, "both rival teams out once")
	check_eq(ended, 0, "endless: no MatchEnded")
	check(not w.match_state.ended, "endless not ended")
	check_eq(w.tick, 900, "ticks keep running")
	check(not bool(w.factions[1].alive) and not bool(w.factions[2].alive), "rivals dead")
	check_eq(Victory.progress(w, 0).terms.size(), 0, "endless has no terms")


func test_qa012_combined_expressions() -> void:
	# OR(hq_elimination, territory 100): killing the only enemy HQ wins at once.
	var w := make_world({"victory": "combined", "victory_rules": {"op": "or",
		"terms": [{"type": "hq_elimination"}, {"type": "territory", "percent": 100}]}})
	w.step()
	w.destroy(int(_hq(w, 1).id), "test")
	var ended := _run(w, 2)
	check_eq(ended.size(), 1, "OR hq: ended")
	check_eq(w.match_state.terms, ["hq_elimination"], "OR hq: term")
	check_eq(int(w.match_state.winner), 0, "OR hq: winner")
	# AND(hq_elimination, hold_bridge 30): eliminating the enemy is not enough.
	w = make_world({"victory": "combined", "victory_rules": {"op": "and",
		"terms": [{"type": "hq_elimination"}, {"type": "hold_bridge", "seconds": 30}]}})
	w.destroy(int(_hq(w, 1).id), "test")
	ended = _run(w, 200)
	check(ended.is_empty(), "AND hq+bridge: elimination alone does not win")
	check(not bool(w.factions[1].alive), "enemy eliminated")
	_unit(w, 0, _bridge_cell(w))
	ended = _run(w, 800)
	check_eq(ended.size(), 1, "AND hq+bridge: ends once the bridge is held")
	check_eq(w.match_state.terms, ["hq_elimination", "hold_bridge"], "AND: both terms")
	# Normalisation and defaults.
	var r := Victory.rules_of({"victory": "territory"})
	check_eq(float(r.terms[0].percent), 60.0, "territory default percent")
	r = Victory.rules_of({"victory": "hold_bridge", "victory_params": {"seconds": 45}})
	check_eq(int(r.terms[0].seconds), 45, "hold_bridge params")
	r = Victory.rules_of({"victory": "combined", "victory_rules": {"op": "or", "terms": [{"type": "hold_bridge"}]}})
	check_eq(int(r.terms[0].seconds), 300, "hold_bridge default seconds")
	check_eq(String(r.op), "or", "op kept")


# ---------------------------------------------------------------- validation
func _combined(op: String, terms: Array) -> Dictionary:
	return _cfg([_side("human_a", 0), _side("human_a", 1)], "combined", {"victory_rules": {"op": op, "terms": terms}})


func test_contradictory_sets_rejected_with_distinct_reasons() -> void:
	var two := [_side("human_a", 0), _side("human_a", 1)]
	var cases := {
		"unknown_term": Victory.validate_rules(_combined("and", [{"type": "kill_the_king"}])),
		"percent_low": Victory.validate_rules(_combined("and", [{"type": "territory", "percent": 5}])),
		"seconds_low": Victory.validate_rules(_combined("or", [{"type": "hold_bridge", "seconds": 10}])),
		"endless_mix": Victory.validate_rules(_cfg(two, "endless", {"victory_rules": {"op": "and", "terms": [{"type": "territory"}]}})),
		"empty_terms": Victory.validate_rules(_combined("and", [])),
		"no_bridge": Victory.validate_rules(_combined("and", [{"type": "hold_bridge", "seconds": 60}]), {"bridge_cells": []}),
		"bad_op": Victory.validate_rules(_combined("xor", [{"type": "hq_elimination"}])),
		"duplicate": Victory.validate_rules(_combined("or", [{"type": "territory", "percent": 50}, {"type": "territory", "percent": 70}])),
	}
	var seen := {}
	for k in cases:
		var why := String(cases[k])
		check(why != "", "%s rejected" % k)
		check(not seen.has(why), "%s has a distinct reason (%s)" % [k, why])
		seen[why] = k
	# More of the same categories (and through world.validate_config).
	check(Victory.validate_rules(_combined("and", [{"type": "territory", "percent": 150}])).contains("percent"), "percent > 100")
	check(Victory.validate_rules(_combined("and", [{"type": "hold_bridge", "seconds": 4000}])).contains("seconds"), "seconds > 3600")
	check(Victory.validate_rules(_combined("and", [{"type": "endless"}])).contains("Endless"), "endless as a term")
	check(Victory.validate_rules(_cfg(two, "territory", {"victory_params": {"percent": 101}})) != "", "single-mode percent param")
	check(Victory.validate_rules(_cfg(two, "hold_bridge", {"victory_params": {"seconds": 29}})) != "", "single-mode seconds param")
	check(Victory.validate_rules(_cfg(two, "combined")) != "", "combined without rules")
	check(SimWorld.validate_config(_combined("and", [{"type": "hq_elimination"}, {"type": "hq_elimination"}])).contains("Duplicate"), "world.validate_config uses validate_rules")
	# Valid sets pass.
	check_eq(Victory.validate_rules(_combined("and", [{"type": "hq_elimination"}, {"type": "territory", "percent": 60}, {"type": "hold_bridge", "seconds": 300}])), "", "full AND set valid")
	check_eq(Victory.validate_rules(_combined("or", [{"type": "territory", "percent": 10}, {"type": "hold_bridge", "seconds": 3600}])), "", "bounds inclusive")
	check_eq(Victory.validate_rules(_cfg(two, "territory", {"victory_params": {"percent": 60}})), "", "territory 60 valid")
	check_eq(Victory.validate_rules(_cfg(two, "hold_bridge", {"victory_params": {"seconds": 300}})), "", "river crossing has a bridge")
	check_eq(Victory.validate_rules(_cfg(two, "endless")), "", "plain endless valid")
	check_eq(SimWorld.validate_config(_combined("or", [{"type": "hq_elimination"}, {"type": "territory"}])), "", "world accepts a valid combined set")


# ---------------------------------------------------------------- teams
func test_2v2_team_out_only_when_all_its_hqs_fall() -> void:
	var w := _world([_side("human_a", 0), _side("human_b", 0), _side("machine", 1), _side("human_a", 1)])
	if w == null:
		return
	check(w.is_ally(0, 1) and w.is_ally(2, 3), "teammates are allies")
	check(w.is_enemy(0, 2) and w.is_enemy(1, 3) and not w.is_enemy(0, 1), "cross-team enemies")
	for fid in 4:
		check_eq(w.factions[fid].spawn, w.map.spawns[fid], "side %d uses spawn %d" % [fid, fid])
	w.destroy(int(_hq(w, 2).id), "test")
	var ended := _run(w, 40)
	check(not bool(w.factions[2].alive), "side 2 out")
	check(Victory.team_alive(w, 1), "team 1 still in (side 3 has an HQ)")
	check(ended.is_empty(), "no end while side 3 holds its HQ")
	w.destroy(int(_hq(w, 0).id), "test")
	ended = _run(w, 40)
	check(not bool(w.factions[0].alive), "side 0 out")
	check(Victory.team_alive(w, 0), "team 0 still in via side 1")
	check(ended.is_empty(), "both teams still alive")
	var p := Victory.progress(w, 0)
	check_eq(int(p.terms[0].value), 1, "HUD: one enemy team left")
	check_eq(int(p.terms[0].own_hqs), 1, "HUD: own team HQs")
	check_eq(int(p.terms[0].enemy_hqs), 1, "HUD: enemy HQs")
	w.destroy(int(_hq(w, 3).id), "test")
	var team_out := []
	for i in 5:
		w.step()
		for ev in w.events:
			if ev.type == "TeamEliminated":
				team_out.append(int(ev.team))
			if ev.type == "MatchEnded":
				ended.append(ev)
		if w.match_state.ended:
			break
	check_eq(team_out, [1], "team 1 eliminated together")
	check_eq(ended.size(), 1, "match ended")
	check_eq(int(w.match_state.winner_team), 0, "team 0 won")
	check_eq(w.match_state.winners, [0, 1], "both team-0 sides are winners")
	check_eq(int(w.match_state.winner), 0, "G1 winner = lowest fid of the team")
	check_eq(String(w.match_state.reason), "hq_elimination", "reason")
	if not ended.is_empty():
		check_eq(ended[0].winners, [0, 1], "event winners")


# ---------------------------------------------------------------- allied vision
func _vision_world(teams: Array) -> Array:
	var w := _world([_side("human_a", teams[0]), _side("human_a", teams[1]), _side("human_a", teams[2])], "endless")
	var ally := _unit(w, 1, Vector2i(20, 70))
	var foe := _unit(w, 2, w.cell_of(w.entities[ally].pos) + Vector2i(3, 0))
	var fc := w.cell_of(w.entities[foe].pos) + Vector2i(-1, 3)
	var bld := w.spawn_building("depot", 2, fc, true)
	w.run_ticks(4)
	return [w, ally, foe, bld]


func test_allied_vision_reveals_enemy_to_ally() -> void:
	var r := _vision_world([0, 0, 1])
	var w: SimWorld = r[0]
	var foe: Dictionary = w.entities[r[2]]
	check(w.is_visible(0, foe.pos), "ally sight is visible to fid 0")
	check(Fog.entity_visible(w, 0, foe), "entity_visible via ally")
	check(Fog.entity_visible(w, 0, w.entities[r[1]]), "ally units always visible")
	var ids := []
	for e in w.visible_enemies(0):
		ids.append(int(e.id))
	check(ids.has(int(r[2])), "visible_enemies(0) includes the enemy the ally sees")
	check(not ids.has(int(r[1])), "visible_enemies never lists allies")
	check(Fog.is_explored(w, 0, foe.pos), "explored is shared")
	check(w.memory[0].has(int(r[3])), "ally-seen enemy building is in fid 0 memory")
	check(w.memory[1].has(int(r[3])), "and in the ally memory")
	# Control: the same layout as a 3-way FFA reveals nothing to fid 0.
	r = _vision_world([0, 1, 2])
	w = r[0]
	foe = w.entities[r[2]]
	check(not w.is_visible(0, foe.pos), "FFA: no shared sight")
	check(not Fog.entity_visible(w, 0, foe), "FFA: enemy hidden")
	check(not w.memory[0].has(int(r[3])), "FFA: no shared memory")


# ---------------------------------------------------------------- save
func test_save_round_trip_with_territory_state() -> void:
	var w := make_world({"victory": "territory", "victory_params": {"percent": 100}})
	_kill_units(w, 1)
	_occupy(w, 0, (_hq(w, 1).pos as Vector2), 24.0)
	w.run_ticks(120)
	var st: Dictionary = w.sys_state.territory
	var held := 0
	for h in st.held:
		held = maxi(held, int(h))
	check(held > 0, "mid-capture state exists (held %d)" % held)
	var res := SaveSystem.decode_bytes(SaveSystem.encode_dict(w.to_dict(), "test"))
	check(bool(res.ok), "decode ok: %s" % res.reason)
	var w2 := SimWorld.from_dict(res.dict)
	check_eq(w2.state_hash(), w.state_hash(), "hash equal after load")
	check_eq(w2.sys_state.territory.held, st.held, "capture timers survive")
	w.run_ticks(200)
	w2.run_ticks(200)
	check_eq(w2.state_hash(), w.state_hash(), "identical after 200 more ticks")
	check(Territory.percent(w, 0) > 50.0, "captured after load")
	check_eq(Territory.percent(w2, 0), Territory.percent(w, 0), "same territory percent")
	check(not w.match_state.ended, "100% not reached")
