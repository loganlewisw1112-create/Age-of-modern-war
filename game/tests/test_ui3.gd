extends "res://tests/test_base.gd"
## G3a UI logic that runs headless (owner: UI3): skirmish slot table + victory builder produce
## configs that SimWorld.validate_config accepts/rejects, role-based objectives per faction,
## the build-card hotkey mapping, and the victory/score panel rows.

const Objectives = preload("res://presentation/hud/objectives.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")
const G3Score = preload("res://presentation/hud/g3_score.gd")
const SkirmishSetup = preload("res://presentation/menu/skirmish_setup.gd")
const VictoryBuilder = preload("res://presentation/menu/victory_builder.gd")


func _menu_cfg(slots_fn: Callable, vic_fn: Callable) -> Dictionary:
	var st = SkirmishSetup.new()
	st.build()
	var vb = VictoryBuilder.new()
	vb.build()
	slots_fn.call(st)
	vic_fn.call(vb)
	var cfg := SimWorld.default_config()
	var ui_reason: String = st.apply(cfg, 8)
	vb.apply(cfg)
	st.free()
	vb.free()
	return {"cfg": cfg, "ui": ui_reason, "err": SimWorld.validate_config(cfg)}


func test_skirmish_three_factions_ffa_valid() -> void:
	var r := _menu_cfg(func(st):
		st.set_slot(0, true, "human_b", 0)
		st.set_slot(1, true, "machine", 1)
		st.set_slot(2, true, "human_a", 2), func(_vb): pass)
	var cfg: Dictionary = r.cfg
	check_eq(cfg.sides.size(), 3, "three open slots -> three sides")
	check_eq(String(cfg.sides[0].faction), "human_b", "slot 0 faction")
	check(not bool(cfg.sides[0].ai) and bool(cfg.sides[1].ai), "slot 0 human, others AI")
	check_eq(String(r.err), "", "valid 3-faction FFA")
	check_eq(String(r.ui), "", "no UI reason (distinct colours)")
	var w := SimWorld.new_match(cfg)
	check(w != null and w.factions.size() == 3, "match builds with 3 sides")
	if w != null:
		check_eq(String(w.factions[1].faction_def), "machine", "side 1 is machine")


func test_skirmish_reasons_shown() -> void:
	var same := _menu_cfg(func(st):
		st.set_slot(1, true, "machine", 0), func(_vb): pass)
	check(String(same.err) != "", "same team -> validate_config reason: %s" % same.err)
	var closed := _menu_cfg(func(st):
		st.set_slot(1, false), func(_vb): pass)
	check(String(closed.err) != "", "one side -> reason: %s" % closed.err)
	var col := _menu_cfg(func(st):
		st.set_slot(1, true)
		st.slots[1].color.select(st.slots[0].color.selected), func(_vb): pass)
	check_eq(String(col.ui), "Two sides use the same colour.", "duplicate colour UI reason")


func test_victory_builder_modes() -> void:
	var terr := _menu_cfg(func(_st): pass, func(vb):
		vb.select_mode("territory")
		vb.percent.value = 70)
	check_eq(String(terr.cfg.victory), "territory", "territory mode")
	check_eq(int(terr.cfg.victory_params.percent), 70, "percent param")
	check_eq(String(terr.err), "", "territory valid")
	var comb := _menu_cfg(func(_st): pass, func(vb):
		vb.select_mode("combined")
		vb.op.select(1)
		vb.term_boxes.hold_bridge.button_pressed = true)
	var vr: Dictionary = comb.cfg.victory_rules
	check_eq(String(vr.op), "or", "OR op")
	check_eq((vr.terms as Array).size(), 3, "hq + territory + hold_bridge terms")
	check_eq(String(comb.err), "", "combined valid: %s" % comb.err)
	check(VictoryBuilder.describe(comb.cfg).contains(" OR "), "describe combined")
	var bad := _menu_cfg(func(_st): pass, func(vb):
		vb.select_mode("combined")
		vb.term_boxes.endless.button_pressed = true)
	check(String(bad.err) != "", "endless + terms rejected: %s" % bad.err)
	var low := _menu_cfg(func(_st): pass, func(vb):
		vb.select_mode("territory")
		vb.percent.value = 5)
	check(String(low.err) != "", "percent 5 rejected: %s" % low.err)


func test_objectives_role_based_per_faction() -> void:
	for fac in ["human_b", "machine"]:
		var cfg := SimWorld.default_config()
		cfg.sides[0].faction = fac
		cfg.sides[1].ai = false
		var w := SimWorld.new_match(cfg)
		if not check(w != null, "world " + fac):
			continue
		var o := Objectives.new()
		o.update(w, 0)
		check_eq(String(o.items[1].text), "Build %s" % Objectives._a(String(Content.building(Content.role(fac, "barracks")).name)), fac + " barracks text")
		check(not o.is_done("barracks"), fac + " not done at start")
		# both factions start with one infantry-role unit: that is not a trained squad
		check(not o.is_done("squad"), fac + " starting infantry does not tick the train objective")
		var hq: Dictionary = w.buildings_of(0, Content.role(fac, "hq"))[0]
		var bid := w.spawn_building(Content.role(fac, "barracks"), 0, hq.cell + Vector2i(6, 0), true)
		o.update(w, 0, [{"type": "ConstructionCompleted", "building_id": bid}])
		check(o.is_done("barracks"), fac + " barracks-role ticks")
		o.update(w, 0, [{"type": "ProductionCompleted", "building_id": bid, "item": Content.role(fac, "infantry")}])
		check(o.is_done("squad"), fac + " infantry-role ticks")


func test_article_and_end_info_without_winner() -> void:
	check_eq(Objectives._a("Assembler Cell"), "an Assembler Cell", "an before vowel")
	check_eq(Objectives._a("Barracks"), "a Barracks", "a before consonant")
	var cfg := SimWorld.default_config()
	cfg.sides[1].ai = false
	var w := SimWorld.new_match(cfg)
	if not check(w != null, "world"):
		return
	var info: Dictionary = G3Score.end_info(w, 0)
	for t in info.teams:
		check(String(t.text).contains("in play"), "no winner yet: team is in play, not defeated: " + String(t.text))


func test_build_hotkeys_unique_and_not_reserved() -> void:
	for fac in Content.faction_ids():
		var used := {}
		for b in Content.buildable_for(String(fac)):
			var hk := G3.build_hotkey(String(b), used)
			check(hk != "", "%s %s has a hotkey" % [fac, b])
			check(not G3.RESERVED_BUILD_KEYS.has(hk), "%s %s hotkey %s not reserved" % [fac, b, hk])
		check_eq(used.size(), Content.buildable_for(String(fac)).size(), "%s hotkeys unique" % fac)


func test_score_rows_and_end_info() -> void:
	var cfg := SimWorld.default_config()
	cfg.sides.append(cfg.sides[1].duplicate(true))
	cfg.sides[1].ai = false
	cfg.sides[2].ai = false
	cfg.sides[2].faction = "machine"
	cfg.sides[2].team = 0   # 2v1: you + machine vs side 1
	cfg.victory = "territory"
	cfg.victory_params = {"percent": 60}
	var w := SimWorld.new_match(cfg)
	if not check(w != null, "world"):
		return
	check(G3.is_ally(w, 0, 2) and not G3.is_ally(w, 0, 1), "teams")
	var rows := G3Score.rows(w, 0)
	var txt := ""
	for r in rows:
		txt += String(r.text) + "\n"
	check(txt.contains("Team 1: You,"), "team 1 lists you + ally: " + txt)
	check(txt.contains("Territory"), "territory term row")
	check(txt.contains("HQs left: 2"), "two HQs on team 1")
	w.match_state = {"ended": true, "winner": 0, "winner_team": 0, "reason": "territory", "end_tick": 5}
	var info := G3Score.end_info(w, 0)
	check(bool(info.won), "won via team")
	check_eq((info.teams as Array).size(), 2, "two team rows")
	check(String(info.teams[0].text).contains("WINNER"), "winner first")
