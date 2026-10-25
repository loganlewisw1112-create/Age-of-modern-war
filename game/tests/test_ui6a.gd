extends "res://tests/test_base.gd"
## G6 acceptance (owner: UI6a). CONTRACTS_G6 sections 4, 8, 13, 16, 17.
## The panels are built headless (no tree needed) and driven through their own buttons / handlers;
## every command they issue goes through SimWorld.submit + step, so the checks are on real sim state.
## The fit check runs tools/ui_fit_test.gd in a child Godot (like tests/test_ui_fit.gd).

const MarketPanel = preload("res://presentation/ui6/a/market_panel.gd")
const ArmyBuilder = preload("res://presentation/ui6/a/army_builder.gd")
const AM = preload("res://presentation/ui6/a/army_model.gd")
const Card = preload("res://presentation/ui6/a/company_card.gd")
const ForcesPanel = preload("res://presentation/ui6/a/forces_panel.gd")
const CommandersPanel = preload("res://presentation/ui6/a/commanders_panel.gd")
const Hub = preload("res://presentation/ui6/a/ui6a_hub.gd")
const Fx = preload("res://presentation/ui6/a/fit_ui6a.gd")
const Companies = preload("res://sim/systems/companies.gd")
const AiCommand = preload("res://sim/systems/ai_command.gd")
const Market = preload("res://sim/systems/market.gd")
const TEST_PROFILE := "_test_ui6a"
const RES7 := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3440x1440", "3840x2160"]


## issue callable: submit + one step (the command applies on the next tick); records rejections.
func _issuer(w: SimWorld, log: Array) -> Callable:
	return func(cmd: Dictionary) -> void:
		var r := w.submit(cmd)
		if not bool(r.ok):
			log.append(String(r.reason))
		w.step()
		var why := rejected_reason(w.events)
		if why != "":
			log.append(why)


func _fresh_g6() -> SimWorld:
	Fx._w = null
	var w := Fx.g6_world()
	Fx._w = null
	return w


func test_market_panel_buy_sell() -> void:
	var w := make_world()
	var log: Array = []
	var p = MarketPanel.new()
	var root := Control.new()
	p.build(root)
	p.issue = _issuer(w, log)
	p.update(w, 0)
	var model: Array = MarketPanel.model(w, 0)
	check_eq(model.size(), Market.resources().size(), "one row per market resource")
	check_eq(p.rows.size(), Market.resources().size(), "panel rows")
	var buy: Button = p.rows.salvage.btns[10]
	check(not buy.disabled, "Buy 10 salvage enabled with an HQ and credits (%s)" % buy.tooltip_text)
	var cr0 := int(w.factions[0].credits)
	var st0 := int(w.factions[0].stock.get("salvage", 0))
	var price0 := Market.price_milli(w, "salvage", "buy")
	var quote := Market.quote(w, "salvage", 10)
	buy.pressed.emit()
	check(log.is_empty(), "buy accepted: %s" % str(log))
	check_eq(int(w.factions[0].stock.get("salvage", 0)), st0 + 10, "bought 10 salvage")
	check_eq(int(w.factions[0].credits), cr0 - quote, "paid the quoted credits")
	check(Market.price_milli(w, "salvage", "buy") > price0, "buying raised the shared price")
	p.update(w, 0)
	check_eq((p.rows.salvage.limit as Label).text, str(Market.limit_left(w, 0, "salvage")), "limit column shows limit_left")
	var sell: Button = p.rows.salvage.btns[-10]
	check(not sell.disabled, "Sell 10 salvage enabled")
	var cr1 := int(w.factions[0].credits)
	var squote := Market.quote(w, "salvage", -10)
	sell.pressed.emit()
	check(log.is_empty(), "sell accepted: %s" % str(log))
	check_eq(int(w.factions[0].stock.get("salvage", 0)), st0, "sold 10 salvage")
	check_eq(int(w.factions[0].credits), cr1 + squote, "received the quoted credits")
	# no HQ: every trade button is disabled with the sim's reason, and the panel says why
	for hq in w.buildings_of(0):
		if bool(Content.building(String(hq.def)).get("is_hq", false)):
			w.destroy(int(hq.id), "test")
	p.update(w, 0)
	check((p.rows.ore.btns[10] as Button).disabled, "no HQ: Buy disabled")
	check(p.note.visible and p.note.text.contains("HQ"), "no HQ: the panel says the market needs an HQ (%s)" % p.note.text)
	root.free()


func test_army_builder_create_save_validate() -> void:
	AM.profile = TEST_PROFILE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AM.path()))
	var w := _fresh_g6()
	if not check(w != null and not Companies.hq_of(w, 0).is_empty(), "fixture world with a Company HQ"):
		return
	var fac := Companies.faction_of(w, 0)
	var log: Array = []
	var ab = ArmyBuilder.new()
	var root := Control.new()
	ab.build(root)
	ab.issue = _issuer(w, log)
	ab.update(w, 0)
	check(ab.source.item_count >= Companies.templates_for(fac).size(), "presets listed (%d)" % ab.source.item_count)
	check(not ab._cands.is_empty() and ab._cands.has("rifle_squad"), "unit candidates include rifle_squad")
	# empty template: invalid, cannot save
	ab.set_editing(AM.new_template("Test Assault", fac))
	ab.update(w, 0)
	check(ab.save_btn.disabled and ab.reason_lbl.text != "", "empty template: Save disabled with a reason (%s)" % ab.reason_lbl.text)
	ab.add_item("rifle_squad", 3)
	ab.add_item("at_team", 2)
	ab.update(w, 0)
	check_eq(String(AM.summary(w, 0, ab.editing).reason), "", "3 rifle + 2 AT squads is a legal company")
	check(not ab.save_btn.disabled, "valid template: Save enabled")
	check(ab.summary_lbl.text.contains("Elements 5 /"), "summary counts elements (%s)" % ab.summary_lbl.text)
	# over the element cap: the sim's own reason
	ab.add_item("rifle_squad", 60)
	ab.update(w, 0)
	check(ab.reason_lbl.text.contains("at most"), "over the cap: %s" % ab.reason_lbl.text)
	check(ab.train_custom_btn.disabled, "over the cap: Train custom disabled")
	AM.set_count(ab.editing, 0, 3)
	ab.update(w, 0)
	check_eq(ab.save_editing(), "", "saved to the profile")
	check(AM.names(fac, TEST_PROFILE).has("Test Assault"), "profile lists the template")
	var back := AM.get_template(fac, "Test Assault", TEST_PROFILE)
	check_eq(AM.elements(back), 5, "saved template round-trips (5 elements)")
	check(ab.select_source("custom", "Test Assault"), "saved template appears in the source list")
	# train the custom at the Company HQ (exact counts) and a preset at a size
	ab.update(w, 0)
	check(not ab.train_custom_btn.disabled, "Train custom enabled: %s" % ab.train_custom_btn.tooltip_text)
	var before := Companies.companies_of(w, 0).size()
	ab.train_editing()
	check(log.is_empty(), "train custom accepted: %s" % str(log))
	var queued := false
	for t in w.sys_state.companies.training:
		if String(t.template) == "custom:Test Assault":
			queued = true
	check(queued, "custom template queued at the Company HQ")
	ab.select_source("preset", String(Companies.templates_for(fac)[0]))
	ab.size_opt.select(0)
	ab.update(w, 0)
	ab.train_selected()
	check(log.is_empty(), "train preset accepted: %s" % str(log))
	Fx.finish_training(w)
	check_eq(Companies.companies_of(w, 0).size(), before + 2, "both companies trained")
	check(w.sys_state.companies.custom.get(0, {}).has("Test Assault"), "the match recorded the custom template")
	check_eq(ab.delete_editing(), "", "deleted from the profile")
	check(not AM.names(fac, TEST_PROFILE).has("Test Assault"), "profile no longer lists it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AM.path()))
	AM.profile = AM.DEFAULT_PROFILE
	root.free()


func test_company_and_army_cards() -> void:
	var w := _fresh_g6()
	var cs := Companies.companies_of(w, 0)
	if not check(cs.size() == 2 and Companies.armies_of(w, 0).size() == 1, "fixture: 2 companies in 1 army (got %d, %d)" % [cs.size(), Companies.armies_of(w, 0).size()]):
		return
	for i in 60:
		w.step()   # let the AI commander (slot C1) take its company
	var c: Dictionary = Companies.companies_of(w, 0)[0]
	var ids := Companies.units_of(w, c)
	var cm := Card.model(w, c)
	check_eq(int(cm.count), ids.size(), "card counts the company's units")
	check(String(cm.title).contains("Company %d" % int(c.id)), "card title names the company (%s)" % cm.title)
	check(String(cm.status).contains("%d units" % ids.size()) and String(cm.status).contains("refill"), "battle-status line (%s)" % cm.status)
	var roles := {}
	for u in cm.units:
		roles[String(u.role)] = true
	check(roles.has("captain") and roles.has("lieutenant"), "grid includes the captain and a lieutenant")
	check_eq(int(cm.ai_slot), 0, "AI Commander badge C1 on the commanded company")
	check(String(cm.status).contains("AI commander C1"), "status line shows the AI commander")
	var cd := Card.card(cm, true)
	var grid: Node = cd.box.find_child("UnitGrid", true, false)
	check(grid != null and grid.get_child_count() == mini(ids.size(), Card.GRID_MAX), "unit grid: one cell per unit")
	check(cd.box.find_child("AiBadge", true, false) != null, "card shows the AI badge")
	cd.box.free()
	check_eq(int(Card.selection_company(w, ids).get("id", -1)), int(c.id), "the whole company selected -> its card")
	check(Card.selection_company(w, ids + [int(Companies.units_of(w, Companies.companies_of(w, 0)[1])[0])]).is_empty(), "two companies selected -> no single card")
	var am := Card.army_model(w, Companies.armies_of(w, 0)[0])
	check_eq((am.companies as Array).size(), 2, "army card lists both companies")
	# forces panel actions: refill toggle, disband, form army
	var log: Array = []
	var fp = ForcesPanel.new()
	var root := Control.new()
	fp.build(root)
	fp.issue = _issuer(w, log)
	fp.update(w, 0)
	check_eq(fp.cards.size(), 2, "forces panel: a card per company")
	check_eq(fp.army_btns.size(), 1, "forces panel: a Disband per army")
	var cid := int(c.id)
	(fp.cards[cid].refill as Button).pressed.emit()
	check(bool(Companies.companies_of(w, 0)[0].refill), "Refill button turned refill on")
	(fp.army_btns.values()[0] as Button).pressed.emit()
	check(Companies.armies_of(w, 0).is_empty(), "Disband dissolved the army")
	fp.update(w, 0)
	check(fp.form_btn.disabled, "Form army disabled with no companies picked")
	for k in fp.cards:
		(fp.cards[k].pick as CheckBox).button_pressed = true
	fp.update(w, 0)
	check(not fp.form_btn.disabled, "Form army enabled: %s" % fp.form_note.text)
	fp.form_btn.pressed.emit()
	check(log.is_empty(), "army actions accepted: %s" % str(log))
	check_eq(Companies.armies_of(w, 0).size(), 1, "Form army made an army of the picked companies")
	root.free()


func test_commanders_panel_assign_recall() -> void:
	var w := _fresh_g6()
	var cs := Companies.companies_of(w, 0)
	if not check(cs.size() == 2, "fixture: 2 companies"):
		return
	var log: Array = []
	var cp = CommandersPanel.new()
	var root := Control.new()
	cp.build(root)
	cp.issue = _issuer(w, log)
	cp.get_selection = func() -> Array: return []
	cp.update(w, 0)
	check_eq(cp.rows.size(), 4, "four commander slots")
	check((cp.rows[0].status as Label).text.contains("Formation"), "slot C1 shows the fixture's formation (%s)" % (cp.rows[0].status as Label).text)
	check_eq((cp.rows[1].status as Label).text, "Unassigned", "slot C2 unassigned")
	check((cp.rows[1].recall as Button).disabled, "Recall disabled on an empty slot")
	# C2: role base_defence, defensive, hold
	var ti := -1
	for i in cp._targets.size():
		if (cp._targets[i].value as Dictionary).get("role", "") == "base_defence":
			ti = i
	check(ti >= 0, "roles are offered as targets")
	cp.select_option(1, "target", ti)
	cp.select_option(1, "play", AiCommand.PLAYSTYLES.find("defensive"))
	cp.update(w, 0)
	check(not (cp.rows[1].assign as Button).disabled, "Assign enabled: %s" % (cp.rows[1].assign as Button).tooltip_text)
	(cp.rows[1].assign as Button).pressed.emit()
	var live := {}
	for s in AiCommand.slots(w, 0):
		live[int(s.slot)] = s
	check(live.has(1) and String(live[1].role) == "base_defence" and String(live[1].playstyle) == "defensive", "C2 runs base defence, defensive")
	# C3: company 2, objective take -> needs a map cell (picked through the hub's map-click path)
	var c2 := -1
	for i in cp._targets.size():
		if String((cp._targets[i].value as Dictionary).get("formation", "")) == "co:%d" % int(cs[1].id):
			c2 = i
	cp.select_option(2, "target", c2)
	cp.select_option(2, "obj", AiCommand.OBJECTIVES.find("take"))
	cp.update(w, 0)
	check((cp.rows[2].assign as Button).disabled, "take without a cell: Assign disabled")
	var hub = Hub.new()
	var hroot := Control.new()
	hub.build(null, hroot)
	hub.panels.commanders = cp
	hub._pick_slot = 2
	hub._on_picked(Vector2(40.6, 52.2))
	check_eq(cp.pending[2].cell, Vector2i(40, 52), "map pick sets the objective cell")
	check_eq(hub.open_name, "commanders", "the panel reopens after the pick")
	cp.update(w, 0)
	check(not (cp.rows[2].assign as Button).disabled, "take with a cell: Assign enabled (%s)" % (cp.rows[2].assign as Button).tooltip_text)
	(cp.rows[2].assign as Button).pressed.emit()
	live.clear()
	for s in AiCommand.slots(w, 0):
		live[int(s.slot)] = s
	check(live.has(2) and String(live[2].objective.type) == "take", "C3 takes the picked cell")
	cp.update(w, 0)
	check(not (cp.rows[1].recall as Button).disabled, "Recall enabled on C2")
	(cp.rows[1].recall as Button).pressed.emit()
	live.clear()
	for s in AiCommand.slots(w, 0):
		live[int(s.slot)] = s
	check(not live.has(1), "Recall freed C2")
	check(log.is_empty(), "commands accepted: %s" % str(log))
	root.free()
	hroot.free()


## Runs the fit tool on the G6 screens; returns {screens, issues, skips, lines, errors}.
func _fit(res: Array, scales: String) -> Dictionary:
	var out: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/ui_fit_test.gd",
		"--", "--fit-res=" + ",".join(PackedStringArray(res)), "--fit-scales=" + scales, "--fit-screens=" + ",".join(PackedStringArray(Fx.NAMES))])
	OS.execute(OS.get_executable_path(), args, out, true)
	var r := {"screens": -1, "issues": -1, "skips": 0, "lines": [], "errors": []}
	for ln in "\n".join(PackedStringArray(out)).split("\n"):
		var l := String(ln)
		if l.begins_with("FIT RESULT"):
			for part in l.split(" "):
				if part.begins_with("screens="):
					r.screens = int(part.get_slice("=", 1))
				elif part.begins_with("issues="):
					r.issues = int(part.get_slice("=", 1))
		elif l.begins_with("FIT ") and l.contains(" SKIP "):
			r.skips += 1
		elif l.begins_with("FIT ") and not l.begins_with("FIT SUMMARY") and r.lines.size() < 8:
			r.lines.append(l.substr(0, 200))
		elif l.contains("SCRIPT ERROR") and r.errors.size() < 4:
			r.errors.append(l.substr(0, 200))
	return r


func test_new_panels_fit_7_resolutions() -> void:
	var r := _fit(RES7, "1")
	check_eq(r.screens, RES7.size() * Fx.NAMES.size(), "G6 screens ran at 7 resolutions (errors %s)" % str(r.errors))
	check_eq(r.skips, 0, "no G6 screen skipped")
	check(r.issues == 0, "%d fit issues at 100%%: %s" % [r.issues, "\n    ".join(PackedStringArray(r.lines))])
	check(r.errors.is_empty(), "no script errors: %s" % str(r.errors))
	var res3 := ["1280x720", "2560x1440", "3440x1440"]
	var r2 := _fit(res3, "0.75,1.5")
	check_eq(r2.screens, res3.size() * 2 * Fx.NAMES.size(), "G6 screens at UI scale 75% and 150%")
	check(r2.issues == 0, "%d fit issues at 75/150%%: %s" % [r2.issues, "\n    ".join(PackedStringArray(r2.lines))])
