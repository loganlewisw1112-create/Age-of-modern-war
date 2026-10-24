extends "res://tests/test_base.gd"
## Editor scenario tools (owner: ED2, CONTRACTS_G4 sections 5 + 9): content palette per faction,
## players/starts -> cfg.sides, victory presets and the trigger editor -> exact JSON, Test Play
## cfg build, the ED2 tabs through the real editor scene (off-tree) and the skirmish map browser.

const M = preload("res://presentation/editor/ed2_model.gd")
const S = preload("res://presentation/editor/ed2_scenario.gd")
const MapIO = preload("res://sim/map_io.gd")
const T := preload("res://sim/terrain.gd")
const DIR := "user://test_ed2"


func _editor():
	var ed = load("res://presentation/editor/editor_scene.gd").new()
	ed._ready()
	return ed


func test_palette_from_content() -> void:
	Content.load_all()
	for fid in Content.faction_ids():
		var pal := M.palette(String(fid))
		var want_u := 0
		var want_b := 0
		for id in Content.ids("units"):
			if String(Content.unit(String(id)).get("faction", "")) == String(fid):
				want_u += 1
		for id in Content.ids("buildings"):
			if String(Content.building(String(id)).get("faction", "")) == String(fid):
				want_b += 1
		check_eq((pal.units as Array).size(), want_u, "%s palette lists every unit of the faction" % fid)
		check_eq((pal.buildings as Array).size(), want_b, "%s palette lists every building of the faction" % fid)
		check(want_u > 0 and want_b > 0, "%s has units and buildings" % fid)
		for id in pal.units:
			check_eq(String(Content.unit(String(id)).faction), String(fid), "only %s units" % fid)
	var a := M.palette("human_a")
	check((a.units as Array).has("rifleman"), "base unit present")
	if not Content.building("a_wall").is_empty():
		check((a.buildings as Array).has("a_wall"), "G4 fragment (fort.json) walls appear automatically")
	var all := M.palette("")
	check((all.units as Array).size() >= (a.units as Array).size() * 2, "'All factions' lists every faction")
	var st7 := M.palette("human_a", 7)
	for id in st7.units:
		check(Content.available(Content.unit(String(id)), 7), "stage filter keeps only stage-7 defs")
	# the tab: the palette follows the picked player's faction and the filter
	var ed = _editor()
	check(ed.tabs.has("units") and ed.tabs.has("players") and ed.tabs.has("victory") and ed.tabs.has("regions"), "ED2 tabs registered")
	ed.select_tab("units")
	var ut = ed.tab_panel("units")
	ut.set_player(1)
	var fb: String = String(ed.doc.scenario.players[1].faction)
	check_eq(ut.items.size(), (M.palette(fb).units as Array).size() + (M.palette(fb).buildings as Array).size(), "tab palette = player 2's faction")
	check_eq(ut.palette_list.item_count, ut.items.size(), "ItemList filled")
	ut.fac_filter = Content.faction_ids().size() + 1
	ut.fill_palette()
	check_eq(ut.items.size(), (all.units as Array).size() + (all.buildings as Array).size(), "All factions filter")
	ed.free()


func test_place_rotate_formation_cargo_undo() -> void:
	var ed = _editor()
	ed.select_tab("units")
	var ut = ed.tab_panel("units")
	ut.set_player(0)
	ut.fac_filter = 0
	ut.fill_palette()
	var hq := Content.role("human_a", "hq")
	check(ut.pick(hq), "HQ in the palette")
	ut.set_mode("place")
	ed.view.scripted_stroke([Vector2i(20, 20)])
	check_eq(ut.ents().size(), 1, "click places one building")
	check_eq(String(ut.ents()[0].kind), "building", "kind building")
	check_eq(ut.ents()[0].cell, Vector2i(20, 20), "at the clicked cell")
	check_eq(int(ut.ents()[0].owner_slot), 0, "owned by the picked player")
	check_eq(ed.doc.undo_depth(), 1, "one undo step")
	ed.doc.symmetry = "rotate_180"
	ut.built = false
	ed.view.scripted_stroke([Vector2i(30, 30)])
	check_eq(ut.ents().size(), 3, "symmetric placement adds the mirrored copy")
	var s := int(Content.building(hq).size)
	check_eq(ut.ents()[2].cell, Vector2i(128 - s - 30, 128 - s - 30), "mirrored origin")
	check_eq(int(ut.ents()[2].owner_slot), 1, "mirrored copy goes to the nearest player")
	check_eq(bool(ut.ents()[1].built), false, "foundation toggle")
	ed.doc.symmetry = "off"
	ed.action_undo()
	check_eq(ut.ents().size(), 1, "undo removes both symmetric copies in one step")
	var rifle := ""
	for id in M.palette("human_a").units:
		if M.cargo_class(String(id)) == "foot" and rifle == "":
			rifle = String(id)
	check(ut.pick(rifle), "infantry in the palette")
	ut.rotate_facing(1)
	ut.rotate_facing(1)
	ut.set_mode("formation")
	ed.view.scripted_stroke([Vector2i(40, 40), Vector2i(42, 41), Vector2i(43, 41)])
	check_eq(ut.ents().size(), 1 + 8, "4x2 drag box = 8 units")
	check(is_equal_approx(float(ut.ents()[1].facing), PI / 2.0), "Q/E facing stored (90 deg)")
	# select / move / tag / delete
	ut.set_mode("select")
	ed.view.scripted_stroke([Vector2i(40, 40), Vector2i(45, 44)])
	check_eq(ut.selected, 1, "click selects the unit under the cursor")
	check_eq(ut.ents()[1].cell, Vector2i(45, 44), "drag moves it")
	ut.sel.set_tag("boss")
	check_eq(String(ut.ents()[1].tag), "boss", "tag set from the panel")
	var before: int = ut.ents().size()
	ut.sel.delete_selected()
	check_eq(ut.ents().size(), before - 1, "delete")
	ed.action_undo()
	check_eq(ut.ents().size(), before, "undo delete")
	# cargo into a carrier (if the content has one)
	var carrier := ""
	for id in M.palette("").units:
		if M.is_carrier(String(id)):
			carrier = String(id)
			break
	if carrier == "":
		check(M.cargo_reason("rifleman", [], "rifleman") != "", "non-carrier refuses cargo")
	else:
		var cf: String = String(Content.unit(carrier).faction)
		ed.doc.scenario.players[0].faction = cf
		ut.set_player(0)
		ut.fac_filter = 0
		ut.fill_palette()
		ut.set_mode("place")
		ut.pick(carrier)
		ed.view.scripted_stroke([Vector2i(60, 60)])
		ut.select_index(ut.ents().size() - 1)
		var foot := ""
		for id in M.palette(cf).units:
			if M.cargo_class(String(id)) == "foot":
				foot = String(id)
				break
		ut.pick(foot)
		check_eq(ut.sel.load_picked(), "", "load a foot unit into %s" % carrier)
		check_eq(ut.ents().back().get("cargo", []), [foot], "cargo list in the entity entry")
		var n := 1
		while ut.sel.load_picked() == "" and n < 64:
			n += 1
		check(n < 64, "carrier fills up and then refuses (%d loaded)" % n)
		check_eq(S.extra_issues(ed.doc.map, ed.doc.scenario).size(), 0, "a legal cargo list validates")
	ed.free()


func test_players_and_starts_to_cfg() -> void:
	var ed = _editor()
	ed.select_tab("players")
	var pt = ed.tab_panel("players")
	check_eq(pt.players().size(), 2, "new map has 2 players")
	var r: Dictionary = pt.rows[2]
	r.kind.select(1)
	pt._changed(2, "kind")
	check_eq(pt.players().size(), 3, "opening slot 3 as AI adds a player")
	check_eq(int(pt.players()[2].slot), 2, "slot order kept")
	var facs := Content.faction_ids()
	r.faction.select(facs.size() - 1)
	r.team.select(0)
	r.credits.value = 7500
	r.stock.ore.value = 300
	r.diff.select(maxi(0, pt._diffs.find("hard")))
	pt._changed(2, "faction")
	var p: Dictionary = pt.players()[2]
	check_eq(String(p.faction), String(facs[facs.size() - 1]), "faction written")
	check_eq(int(p.team), 0, "team written")
	check_eq(int(p.credits), 7500, "credits written")
	check_eq(p.stock, {"ore": 300}, "start stock written (non-zero keys only)")
	check(bool(p.ai), "AI kind")
	pt.arm_start(2)
	ed.view.scripted_stroke([Vector2i(100, 20)])
	check_eq(M.MapIO._v2i(pt.players()[2].start), Vector2i(100, 20), "start marker by map click")
	ed.doc.symmetry = "rotate_180"
	pt.arm_start(0)
	ed.view.scripted_stroke([Vector2i(15, 18)])
	check_eq(M.MapIO._v2i(pt.players()[0].start), Vector2i(15, 18), "P1 start")
	check_eq(M.MapIO._v2i(pt.players()[1].start), Vector2i(112, 109), "symmetry puts P2's start on the mirrored cell")
	ed.doc.symmetry = "off"
	pt._pk.button_pressed = false
	check_eq(bool(ed.doc.map.start_packages), false, "start packages toggle")
	r.kind.select(2)
	pt._changed(2, "kind")
	check_eq(pt.players().size(), 2, "closing a slot removes the player")
	ed.action_undo()
	check_eq(pt.players().size(), 3, "undo reopens it")
	var sides := M.sides_for(ed.doc.scenario_for_save())
	check_eq(sides.size(), 3, "3 sides")
	check_eq(int(sides[2].slot), 2, "side carries the file slot")
	check_eq(int(sides[2].credits), 7500, "side credits")
	check_eq(sides[2].stock, {"ore": 300}, "side stock")
	check_eq(String(sides[2].difficulty), "hard", "side difficulty")
	check_eq(bool(sides[0].ai), false, "P1 human")
	ed.free()


func test_victory_and_trigger_json_exact() -> void:
	var ed = _editor()
	ed.select_tab("regions")
	var rg = ed.tab_panel("regions")
	ed.view.scripted_stroke([Vector2i(60, 70), Vector2i(64, 72)])
	check_eq(rg.regions().size(), 1, "drag adds a region")
	check_eq(rg.regions()[0].rect, Rect2i(60, 70, 5, 3), "inclusive rect")
	rg.rename(0, "Ford")
	ed.select_tab("victory")
	var vt = ed.tab_panel("victory")
	vt.add_term("survive")
	check_eq(ed.doc.scenario.victory, {"victory": "combined", "victory_rules": {"op": "and", "terms": [{"type": "hq_elimination"}, {"type": "survive", "seconds": 600}]}},
		"legacy 'hq' + survive -> combined AND")
	vt.set_op("or")
	vt.set_term_param(1, "seconds", 900.0)
	vt.add_term("hold_point")
	check_eq(ed.doc.scenario.victory.victory_rules, {"op": "or", "terms": [{"type": "hq_elimination"}, {"type": "survive", "seconds": 900},
		{"type": "hold_point", "region": "", "seconds": 180}]}, "OR + typed seconds")
	vt.set_term_param(2, "region", "r1")
	vt.remove_term(0)
	vt.remove_term(0)
	check_eq(ed.doc.scenario.victory, {"victory": "hold_point", "victory_params": {"region": "r1", "seconds": 180}}, "one term -> plain preset")
	vt.add_trigger()
	vt.set_trigger_field(0, "name", "Ambush")
	vt.set_when_type(0, "unit_in_region")
	vt.set_when_param(0, "owner_slot", 0)
	vt.set_when_param(0, "count", 3.0)
	vt.set_action_type(0, 0, "spawn")
	vt.set_action_param(0, 0, "slot", 1)
	vt.set_action_param(0, 0, "count", "4")
	vt.add_action(0)
	vt.set_action_type(0, 1, "message")
	vt.set_action_param(0, 1, "text", "Ambush!")
	vt.set_trigger_field(0, "once", false)
	var tr: Dictionary = ed.doc.scenario.triggers[0]
	var def0: String = vt.ctx.units[0]
	var want := {"id": "t1", "name": "Ambush", "when": {"type": "unit_in_region", "region": "r1", "owner_slot": 0, "count": 3},
		"then": [{"type": "spawn", "slot": 1, "def": def0, "count": 4, "region": "r1"}, {"type": "message", "text": "Ambush!"}], "once": false}
	check_eq(tr, want, "trigger editor -> exact dict")
	check_eq(JSON.stringify(tr.when, "", false), '{"type":"unit_in_region","region":"r1","owner_slot":0,"count":3}', "params in spec order, ints stay ints")
	check_eq(typeof(tr.when.count), TYPE_INT, "count is an int")
	vt.add_trigger()
	check_eq(ed.doc.scenario.triggers[1].when, {"type": "time_reached", "t": 60.0}, "new trigger default")
	vt.rebuild()
	check(vt._trig_box.get_child_count() == 2, "two trigger rows drawn")
	check_eq(MapIO.validate(ed.doc.map_for_save(), ed.doc.scenario_for_save()).filter(func(i): return String(i.code) in ["trigger_bad", "victory_bad", "region_bad"]), [],
		"MapIO accepts the editor's triggers, victory and regions")
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join("ed2_trig.rtsmap")
	check_eq(MapIO.save(path, ed.doc.map_for_save(), ed.doc.scenario_for_save()), "", "save")
	var back: Dictionary = MapIO.read(path)
	check_eq(back.scenario.triggers[0], MapIO._intify(want), "trigger round trips through the file")
	check_eq(back.scenario.victory, {"victory": "hold_point", "victory_params": {"region": "r1", "seconds": 180}}, "victory round trips")
	check_eq(String(back.scenario.regions[0].name), "Ford", "region name round trips")
	var n0: int = ed.doc.undo_depth()
	ed.action_undo()
	check_eq((ed.doc.scenario.triggers as Array).size(), 1, "undo the 2nd trigger")
	check_eq(ed.doc.undo_depth(), n0 - 1, "one step")
	ed.free()


## A valid 2-player map made through the tabs: HQs + units for both players, a tag, a trigger.
func _build_valid(ed) -> void:
	ed.select_tab("units")
	var ut = ed.tab_panel("units")
	for i in 2:
		ut.set_player(i)
		ut.fac_filter = 0
		ut.fill_palette()
		var fid: String = String(ed.doc.scenario.players[i].faction)
		var foot := ""
		for id in M.palette(fid).units:
			if M.cargo_class(String(id)) == "foot" and foot == "":
				foot = String(id)
		ut.pick(foot)
		ut.set_mode("formation")
		var st: Vector2i = M.MapIO._v2i(ed.doc.scenario.players[i].start)
		var a := st + Vector2i(6, 6) if i == 0 else st - Vector2i(8, 8)
		ed.view.scripted_stroke([a, a + Vector2i(2, 1)])
	ut.select_index(ut.ents().size() - 1)
	ut.sel.set_tag("leader")
	ed.select_tab("victory")
	ed.tab_panel("victory").add_trigger()


func test_test_play_cfg_and_skirmish_custom() -> void:
	var ed = _editor()
	ed.doc.map["start_packages"] = true
	_build_valid(ed)
	var issues: Array = ed.action_validate()
	check_eq(issues, [], "the tab-built map validates with 0 issues")
	var got: Array = []
	ed.test_play_requested.connect(func(c: Dictionary): got.append(c))
	check_eq(S.run_test_play(ed, 7), "", "Test Play handler accepts the map")
	check_eq(got.size(), 1, "request_test_play emitted once")
	var cfg: Dictionary = got[0] if not got.is_empty() else {}
	check_eq(String(cfg.get("map_file", "")), M.TEMP_PATH, "cfg.map_file = the temp file")
	check_eq((cfg.get("sides", []) as Array).size(), 2, "sides from the scenario players")
	check_eq(int(cfg.sides[1].slot), 1, "side slot")
	check(not bool(cfg.sides[0].ai) and bool(cfg.sides[1].ai), "P1 human, P2 AI")
	check_eq(String(cfg.victory), "hq_elimination", "legacy victory normalized")
	check_eq(int(cfg.seed), 7, "seed passed")
	var w := SimWorld.new_match(cfg)
	check(w != null, "the test-play cfg starts a match")
	if w != null:
		w.run_ticks(40)
		var tagged := 0
		for e in w.entities.values():
			if String(e.get("tag", "")) == "leader":
				tagged += 1
		check_eq(tagged, 1, "placed + tagged entity in the match")
		check_eq((w.sys_state.get("triggers", {}).get("fired", []) as Array).size(), 1, "trigger state from the file")
	# the bad path: an unplaceable entity refuses Test Play and lists the issue
	ed.doc.scenario.entities.append(M.make_entity("unit", "no_such_unit", 0, Vector2i(5, 5)))
	check_eq(S.run_test_play(ed), "issues", "Test Play refuses an invalid map")
	check_eq(got.size(), 1, "no second request")
	ed.doc.scenario.entities.pop_back()
	# skirmish: the custom map appears under Custom and prefills the sides
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join("ed2_custom.rtsmap")
	ed.doc.scenario.name = "ED2 Custom"
	ed.doc.scenario.players[1].faction = String(Content.faction_ids().back())
	ed.doc.scenario.players[1].credits = 4000
	ed.doc.scenario.victory = {"victory": "survive", "victory_params": {"seconds": 420}}
	check_eq(ed.save_to(path), "", "saved")
	ed.free()
	var menu = load("res://presentation/menu/main_menu.gd").new()
	menu._ready()
	var su = menu.setup
	su._ready()
	check(su.menu == menu, "setup found the menu")
	su.browser.maps_dir = DIR
	su.browser.refresh()
	var labels: Array = []
	for i in su.browser.list.item_count:
		labels.append(su.browser.list.get_item_text(i))
	check(labels.has("Built-in") and labels.has("Custom"), "Built-in and Custom groups")
	check(labels.any(func(t): return String(t).contains("ED2 Custom") and String(t).contains("128 x 128")), "custom map listed with size")
	check(su.browser.select_key(path), "pick the custom map")
	check(su.browser.thumb.texture != null, "thumbnail rendered")
	check_eq(int(su.slots[1].faction.selected), Content.faction_ids().size() - 1, "side 2 prefilled from the file")
	check_eq(int(su.slots[1].credits.value), 4000, "credits prefilled")
	var r: Dictionary = menu.build_config()
	check_eq(String(r.error), "", "menu config valid")
	var c2: Dictionary = r.cfg
	check_eq(String(c2.get("map_file", "")), path, "cfg.map_file")
	check_eq(bool(c2.get("scenario_rules", false)), true, "scenario rules by default")
	menu.start_requested.emit(c2)
	check_eq(String(c2.victory), "combined", "start hook applies the file victory")
	check_eq(c2.get("victory_rules", {}).get("terms", []), [{"type": "survive", "seconds": 420}], "survive 420 from the file")
	var w2 := SimWorld.new_match(c2)
	check(w2 != null, "custom map starts from skirmish")
	if w2 != null:
		w2.run_ticks(30)
		check_eq(String(w2.factions[1].faction_def), String(Content.faction_ids().back()), "file faction in the match")
	su.browser.rules_opt.select(1)
	var c3: Dictionary = menu.build_config().cfg
	menu.start_requested.emit(c3)
	check_eq(bool(c3.scenario_rules), false, "skirmish rules only flag")
	check(String(c3.victory) != "combined", "skirmish rules keep the victory builder's choice")
	check(su.browser.select_key(String(menu._map_rows[0].id)), "back to a built-in")
	check(not menu.build_config().cfg.has("map_file"), "built-in pick drops map_file")
	menu.free()
