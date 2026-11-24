extends "res://tests/test_base.gd"
## G10 Task 18: Coalition doctrine AI adapter — cunning ops, Adapt9/generals feed, no-cheat difficulty.

const CoalitionAi10 = preload("res://sim/ai/coalition_ai10.gd")
const CoalitionDoctrine10 = preload("res://sim/ai/coalition_doctrine10.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")
const Adapt9 = preload("res://sim/ai/adapt9.gd")
const Generals9 = preload("res://sim/ai/generals9.gd")


func _coalition_world(diff: String = "normal", credits: int = 5000, seed: int = 1818) -> SimWorld:
	var c := SimWorld.default_config()
	c.seed = seed
	c.ai_difficulty = diff
	c.sides = [
		{"faction": "shadow_coalition", "stage": 10, "credits": credits, "ai": false, "name": "X", "team": 0,
			"ai_difficulty": diff, "persona_id": "ghost_knife"},
		{"faction": "human_a", "stage": 8, "credits": credits, "ai": false, "name": "A", "team": 1,
			"ai_difficulty": diff},
	]
	return SimWorld.new_match(c)


func _set_side_field(w: SimWorld, fid: int, key: String, value) -> void:
	## Touch Coalition10 so state exists, then mutate side fields used by observe.
	Coalition10.board(w, fid)
	var factions: Dictionary = w.sys_state.coalition10.factions
	var s: Dictionary = factions[str(fid)]
	s[key] = value


func test_cells_probe_and_bleed() -> void:
	Content.load_all()
	var w := _coalition_world()
	var obs := CoalitionAi10.observe(w, 0)
	check(bool(obs.get("can_probe", false)), "cells can probe")
	check(bool(obs.get("can_bleed", false)), "harry allows bleed path")
	var op := CoalitionAi10.choose_operation(w, 0)
	check_eq(String(op.get("type", "")), "cell_feint", "cell_feint selected")
	check_eq(String(op.get("outcome", "")), "probe_bleed", "probe/bleed outcome")
	check_eq(String(Coalition10.board(w, 0).get("intent", "")), "bleed", "intent bleed after feint")
	var b := CoalitionAi10.board(w, 0)
	check_eq(String(b.get("evidence", "")), "probes", "board evidence probes")
	check_eq(String(b.get("outcome", "")), "probe_bleed", "board outcome")


func test_mercs_fill_detected_gap() -> void:
	Content.load_all()
	var w := _coalition_world()
	_set_side_field(w, 0, "patron_favour", 12)
	Coalition10.note_evidence(w, 0, "gap", 1)
	var obs := CoalitionAi10.observe(w, 0)
	check(bool(obs.get("gap_detected", false)), "gap detected")
	var op := CoalitionAi10.choose_operation(w, 0)
	check_eq(String(op.get("type", "")), "merc_screen", "merc_screen fills gap")
	check_eq(String(op.get("outcome", "")), "gap_filled", "gap filled outcome")
	check_eq(String(Coalition10.board(w, 0).get("intent", "")), "flex", "intent flex")


func test_elites_strike_weak_hvt() -> void:
	Content.load_all()
	var w := _coalition_world()
	Coalition10.note_evidence(w, 0, "weak_point", 1)
	_set_side_field(w, 0, "intel_grade", "fix")
	_set_side_field(w, 0, "ghost_ready", true)
	_set_side_field(w, 0, "layer", "elite")
	var obs := CoalitionAi10.observe(w, 0)
	check(bool(obs.get("weak_hvt", false)), "weak HVT seen")
	check(bool(obs.get("intel_ready", false)), "intel ready")
	var op := CoalitionAi10.choose_operation(w, 0)
	check_eq(String(op.get("type", "")), "death_action", "Death action on weak HVT")
	check_eq(String(op.get("outcome", "")), "hvt_struck", "HVT struck")
	check_eq(String(Coalition10.board(w, 0).get("intent", "")), "strike", "intent strike")


func test_endangered_elites_exfil_not_trade() -> void:
	Content.load_all()
	var w := _coalition_world()
	Coalition10.note_evidence(w, 0, "pressure", 1)
	_set_side_field(w, 0, "ghost_ready", true)
	_set_side_field(w, 0, "layer", "elite")
	## Also plant a weak HVT so exfil must win over strike (no trading elites).
	Coalition10.note_evidence(w, 0, "weak_point", 1)
	_set_side_field(w, 0, "intel_grade", "fix")
	var obs := CoalitionAi10.observe(w, 0)
	check(bool(obs.get("elite_endangered", false)), "elites endangered")
	check(bool(obs.get("weak_hvt", false)), "HVT still visible")
	var op := CoalitionAi10.choose_operation(w, 0)
	check_eq(String(op.get("type", "")), "anchor_exfil", "Anchor exfil over trade")
	check_eq(String(op.get("outcome", "")), "elites_exfiled", "exfil outcome")
	check_eq(String(Coalition10.board(w, 0).get("intent", "")), "exfil", "intent exfil")


func test_combined_play_chain() -> void:
	Content.load_all()
	var w := _coalition_world()
	var got: Array = []
	for i in 4:
		var op := CoalitionAi10.advance_combined(w, 0)
		got.append(String(op.get("type", "")))
	check_eq(got, ["cell_feint", "merc_screen", "death_action", "anchor_exfil"], "combined play chain")
	var b := CoalitionAi10.board(w, 0)
	check_eq((b.get("chain", []) as Array).size(), 4, "chain length 4")
	check(String(b.get("target", "")) != "" or String(b.get("op", "")) == "anchor_exfil", "AAR target/op present")
	check(String(b.get("evidence", "")) != "", "AAR evidence")
	check(String(b.get("outcome", "")) != "", "AAR outcome")


func test_adapt9_and_persona_feed_doctrine() -> void:
	Content.load_all()
	var w := _coalition_world()
	for i in 3:
		Adapt9.observe_kill(w, 0, "a_rifle_squad", "laser")
	var adapt := CoalitionDoctrine10.adapt_bias(w, 0)
	check_eq(String(adapt.get("counter_bias", "")), "smoke", "Adapt9 counter_bias consumed")
	var persona := CoalitionDoctrine10.persona_for(w, 0)
	check_eq(String(persona.get("id", "")), "ghost_knife", "preferred persona")
	check(not Generals9.doctrine("ghost_knife").is_empty(), "persona doctrine present")
	var obs := CoalitionAi10.observe(w, 0)
	check_eq(String(obs.get("counter_bias", "")), "smoke", "observe carries Adapt9 bias")
	check_eq(String(obs.get("persona_id", "")), "ghost_knife", "observe carries persona")
	var op := CoalitionAi10.choose_operation(w, 0)
	check_eq(String(op.get("counter_bias", "")), "smoke", "op carries Adapt9 bias")
	check_eq(String(op.get("persona_id", "")), "ghost_knife", "op carries persona")


func test_difficulty_pressure_decision_quality_only() -> void:
	Content.load_all()
	var easy := CoalitionAi10.pressure_for_difficulty(_coalition_world("easy"), 0)
	var normal := CoalitionAi10.pressure_for_difficulty(_coalition_world("normal"), 0)
	var hard := CoalitionAi10.pressure_for_difficulty(_coalition_world("hard"), 0)
	check(int(hard.scout_interval) < int(normal.scout_interval), "Hard scouts sooner")
	check(int(normal.scout_interval) < int(easy.scout_interval), "Normal scouts sooner than Easy")
	check(int(hard.reaction_delay) < int(easy.reaction_delay), "Hard reacts sooner")
	check(float(hard.intel_confidence) > float(easy.intel_confidence), "Hard higher intel confidence")
	check(int(hard.patience) < int(easy.patience), "Hard less patient")
	check(int(hard.operation_concurrency) > int(easy.operation_concurrency), "Hard more concurrent ops")
	for row in [easy, normal, hard]:
		check_eq(float(row.get("resource_mult", 0)), 1.0, "%s no resource cheat" % row.difficulty)
		check_eq(float(row.get("hp_mult", 0)), 1.0, "%s no hp cheat" % row.difficulty)
		check_eq(float(row.get("damage_mult", 0)), 1.0, "%s no damage cheat" % row.difficulty)
		check(not row.has("stock_bonus"), "%s no stock bonus key" % row.difficulty)


func test_difficulty_stock_income_hp_damage_cost_equal() -> void:
	Content.load_all()
	var snaps: Array = []
	var incomes: Array = []
	for diff in ["easy", "normal", "hard"]:
		var w := _coalition_world(diff, 5000, 1818)
		var before := CoalitionAi10.stock_snapshot(w, 0)
		snaps.append(before)
		for _i in 40:
			w.step()
		var after := CoalitionAi10.stock_snapshot(w, 0)
		incomes.append(int(after.credits) - int(before.credits))
	var a: Dictionary = snaps[0]
	for i in range(1, 3):
		var b: Dictionary = snaps[i]
		check_eq(int(b.credits), int(a.credits), "starting credits equal %d" % i)
		check_eq(int(b.ore), int(a.ore), "starting ore equal %d" % i)
		check_eq(int(b.salvage), int(a.salvage), "starting salvage equal %d" % i)
		check_eq(int(b.hp), int(a.hp), "HP equal %d" % i)
		check_eq(int(b.damage), int(a.damage), "damage equal %d" % i)
		check_eq(int(b.prod_credits), int(a.prod_credits), "prod credits equal %d" % i)
		check_eq(int(b.prod_salvage), int(a.prod_salvage), "prod salvage equal %d" % i)
	check_eq(int(incomes[0]), int(incomes[1]), "income easy==normal")
	check_eq(int(incomes[1]), int(incomes[2]), "income normal==hard")
