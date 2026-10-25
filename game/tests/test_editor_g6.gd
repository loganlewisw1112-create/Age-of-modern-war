extends "res://tests/test_base.gd"
## G6 acceptance (owner: ED6). CONTRACTS_G6 section 15 (editor Live), section 7 (height in the editor),
## section 17; PLAN_G6 section 8. Live: snapshot -> combat + AI tactics only -> exact restore; height
## brushes with validation; G6 placements.

const EditorLive = preload("res://sim/editor_live.gd")
const M = preload("res://presentation/editor/ed2_model.gd")
const MapIO = preload("res://sim/map_io.gd")
const BH = preload("res://presentation/editor/brushes_height.gd")
const Symmetry = preload("res://presentation/editor/symmetry.gd")
const Companies = preload("res://sim/systems/companies.gd")
const Garrison = preload("res://sim/systems/garrison.gd")
const SCENE := "res://presentation/editor/editor_scene.gd"
const N := 40


static func grass_map(n: int = N) -> Dictionary:
	var t := PackedByteArray()
	t.resize(n * n)
	t.fill(Terrain.GRASS)
	return {"w": n, "h": n, "terrain": t, "decor": [], "bridges": [], "hold_bridge": 0, "resources": []}


## Two hostile sides, 4 riflemen each, 4 cells apart in the middle of the map (+ optional extras).
static func clash_scenario(extra: Array = []) -> Dictionary:
	var ents := []
	for i in 4:
		ents.append(M.make_entity("unit", "rifleman", 0, Vector2i(17 + i % 2, 18 + i / 2)))
		ents.append(M.make_entity("unit", "rifleman", 1, Vector2i(22 + i % 2, 18 + i / 2)))
	ents.append_array(extra)
	return {"name": "ED6 Live", "author": "ED6", "description": "test", "start_packages": false,
		"players": [{"slot": 0, "faction": "human_a", "team": 0, "stage": 9, "credits": 3000, "ai": false, "start": Vector2i(4, 4)},
			{"slot": 1, "faction": "human_b", "team": 1, "stage": 9, "credits": 3000, "ai": false, "start": Vector2i(35, 35)}],
		"entities": ents, "victory": {"victory": "hq_elimination"}, "regions": [], "triggers": []}


func _editor(sc: Dictionary = {}):
	var ed = load(SCENE).new()
	ed._ready()
	ed.doc.set_doc(grass_map(), sc if not sc.is_empty() else clash_scenario())
	return ed


static func _unit_hp(w: SimWorld) -> Dictionary:
	var out := {"n": 0, "hp": 0.0}
	for e in w.entities.values():
		if String(e.kind) == "unit" and float(e.get("hp", 0.0)) > 0.0:
			out.n += 1
			out.hp += float(e.hp)
	return out


func test_live_on_units_fight() -> void:
	Content.load_all()
	var ed = _editor()
	EditorLive.set_speed(1)
	check_eq(ed.live_start(), "", "Live starts from the editor doc")
	check(ed.live_on(), "Live is on")
	var w: SimWorld = ed.live_world
	check(w != null and EditorLive.is_live(w), "the Live world carries cfg.live_mode")
	check(ed.view.is_live() and is_same(ed.view._world, w), "the view draws the Live world")
	var before := _unit_hp(w)
	check_eq(int(before.n), 8, "the 8 placed riflemen are in the Live world (no start packages)")
	ed.live_advance(400)   # 20 s
	var after := _unit_hp(w)
	check(float(after.hp) < float(before.hp) - 1.0 or int(after.n) < int(before.n),
		"placed units of hostile sides fight in Live (hp %.0f -> %.0f, units %d -> %d)" % [before.hp, after.hp, before.n, after.n])
	check(not bool(w.match_state.ended), "Live never ends the match (victory endless)")
	check(not ed.live_bar.visible or ed.live_bar.visible, "live bar exists")
	check(ed.live_bar.visible, "Live indicator shown while Live runs")
	# placing while Live: the unit spawns into the Live world, the doc is unchanged
	var ut = ed.tab_panel("units")
	ed.select_tab("units")
	ut.set_player(0)
	check(ut.pick("rifleman"), "rifleman in the palette")
	ut.set_mode("place")
	var n_doc: int = ut.ents().size()
	var n_live := int(_unit_hp(w).n)
	ed.view.scripted_stroke([Vector2i(20, 30)])
	check_eq(int(_unit_hp(w).n), n_live + 1, "placing during Live spawns into the Live world")
	check_eq(ut.ents().size(), n_doc, "placing during Live does not touch the doc")
	ed.live_stop()
	check(not ed.live_on() and not ed.view.is_live(), "Live off")
	check(not ed.live_bar.visible, "Live indicator hidden after Live")
	ed.free()


func test_live_off_restores_pre_live_hash() -> void:
	Content.load_all()
	# the library contract: start -> run -> stop restores the exact state (in place)
	var r: Dictionary = EditorLive.make_world(grass_map(), clash_scenario())
	check_eq(String(r.reason), "", "Live world built")
	var w: SimWorld = r.world
	var h0 := w.state_hash()
	var snap := EditorLive.start(w)
	check_eq(String(snap.hash), h0, "snapshot hash = pre-Live hash")
	check(EditorLive.is_live(w), "live_mode on after start")
	w.run_ticks(300)
	check(w.state_hash() != h0, "Live changed the world")
	EditorLive.stop(w, snap)
	check_eq(w.state_hash(), h0, "stop restores the pre-Live state_hash exactly")
	check(not EditorLive.is_live(w), "live_mode off after stop")
	# the restored world keeps running deterministically (same as a fresh world from the same doc)
	var c: SimWorld = EditorLive.make_world(grass_map(), clash_scenario()).world
	check_eq(c.state_hash(), h0, "a fresh Live world from the same doc has the same hash")
	w.run_ticks(60)
	c.run_ticks(60)
	check_eq(w.state_hash(), c.state_hash(), "restored world steps exactly like a fresh one")
	# the editor: the doc (map + scenario) is byte-identical after Live
	var ed = _editor()
	var m0 := var_to_bytes(ed.doc.map_for_save())
	var s0 := var_to_bytes(ed.doc.scenario_for_save())
	ed.live_start()
	var lw: SimWorld = ed.live_world
	var pre := String(ed.live_snap.hash)
	ed.live_advance(200)
	ed.live_stop()
	check_eq(lw.state_hash(), pre, "editor Live stop restores the Live world's pre-Live hash")
	check(var_to_bytes(ed.doc.map_for_save()) == m0, "doc map unchanged by Live")
	check(var_to_bytes(ed.doc.scenario_for_save()) == s0, "doc scenario unchanged by Live")
	check(not ed.view.is_live() and is_same(ed.view._world, ed.view.world), "the view shows the doc again")
	ed.free()


func test_live_speed_controls() -> void:
	Content.load_all()
	var ed = _editor()
	ed.live_start()
	var w: SimWorld = ed.live_world
	ed.set_live_speed(0)
	check_eq(EditorLive.speed(), 0, "pause")
	var t0 := w.tick
	for i in 5:
		ed._process(0.1)
	check_eq(w.tick, t0, "paused: no ticks")
	var per := {}
	for sp in [1, 2, 4]:
		ed.set_live_speed(sp)
		check_eq(EditorLive.speed(), sp, "speed %d" % sp)
		ed._live_acc = 0.0
		var t1 := w.tick
		for i in 5:
			ed._process(0.1)
		per[sp] = w.tick - t1
	check_eq(int(per[1]), 10, "1x = 20 ticks/s (10 ticks in 0.5 s)")
	check_eq(int(per[2]), 20, "2x = twice as fast")
	check_eq(int(per[4]), 40, "4x = four times as fast")
	EditorLive.set_speed(3)
	check(EditorLive.SPEEDS.has(EditorLive.speed()), "odd speeds snap to pause/1/2/4")
	check_eq(ed._live_speed_btns.size(), 4, "pause / 1 / 2 / 4 buttons")
	ed.set_live_speed(2)
	check((ed._live_speed_btns[2] as Button).button_pressed, "the 2x button shows the speed")
	ed.toggle_live()
	check(not ed.live_on(), "toggle (L) stops Live")
	ed.toggle_live()
	check(ed.live_on(), "toggle (L) starts Live again")
	ed.live_stop()
	EditorLive.set_speed(1)
	ed.free()


func test_live_runs_no_economy_or_production() -> void:
	Content.load_all()
	var hq := Content.role("human_a", "hq")
	var bk := Content.role("human_a", "barracks")
	var extra := [M.make_entity("building", hq, 0, Vector2i(4, 30)), M.make_entity("building", bk, 0, Vector2i(10, 30))]
	var r: Dictionary = EditorLive.make_world(grass_map(), clash_scenario(extra))
	var w: SimWorld = r.world
	check(w != null, "Live world with an HQ and a barracks: %s" % String(r.reason))
	if w == null:
		return
	EditorLive.start(w)
	var f0: Dictionary = w.factions[0].duplicate(true)
	var bid := -1
	for id in w.entities:
		if String(w.entities[id].def) == bk:
			bid = int(id)
	check(bid >= 0, "barracks placed")
	var unit_def := String((Content.building(bk).get("produces", ["rifleman"]) as Array)[0])
	for cmd in [{"type": "queue_unit", "building_id": bid, "item": unit_def},
			{"type": "build", "def": bk, "cell": [14, 30], "builder_ids": []},
			{"type": "research", "project": "g6_infantry_plates_1"},
			{"type": "market_trade", "resource": "ore", "side": "buy", "amount": 10}]:
		var ev := do_cmd(w, 0, cmd)
		check(rejected_reason(ev).contains("Live"), "%s refused in Live: '%s'" % [cmd.type, rejected_reason(ev)])
	w.run_ticks(400)
	check_eq(int(w.factions[0].credits), int(f0.credits), "no income or spending in Live (credits)")
	check_eq(w.factions[0].stock, f0.stock, "no income or spending in Live (stock)")
	check_eq((w.entities[bid].get("queue", []) as Array).size(), 0, "nothing produced or queued in Live")
	check_eq(int(w.factions[0].stage), int(f0.stage), "no progression in Live")
	for s in EditorLive.SKIPPED:
		check(["Economy", "Market", "Construction", "Production", "Progression"].has(s), "skip list: %s" % s)


func _height_tab(ed, tool: String, size: int = 1):
	ed.select_tab("height")
	var ht = ed.tab_panel("height")
	ht.set_tool(tool)
	ht.bsize = size
	ht.shape = "square"
	ht.mode = "brush"
	return ht


static func _lv(ed, c: Vector2i) -> int:
	return BH.level_at(ed.doc.map, c)


func test_height_brushes_raise_lower_smooth_ramp() -> void:
	Content.load_all()
	var ed = _editor()
	check(not ed.doc.map.has("height"), "a new map has no height layer")
	var ht = _height_tab(ed, "raise")
	var d0: int = ed.doc.undo_depth()
	ed.view.scripted_stroke([Vector2i(10, 10)])
	check(ed.doc.map.has("height"), "first height stroke adds the layer")
	check_eq(_lv(ed, Vector2i(10, 10)), 2, "raise: plain -> hill")
	check_eq(_lv(ed, Vector2i(11, 10)), 1, "raise touches only the brush cells")
	check_eq(ed.doc.undo_depth(), d0 + 1, "one undo step per stroke")
	ed.view.scripted_stroke([Vector2i(10, 10)])
	ed.view.scripted_stroke([Vector2i(10, 10)])
	check_eq(_lv(ed, Vector2i(10, 10)), 3, "raise caps at ridge (3)")
	ht.set_tool("lower")
	ed.view.scripted_stroke([Vector2i(10, 10)])
	check_eq(_lv(ed, Vector2i(10, 10)), 2, "lower: -1 level")
	for i in 3:
		ed.view.scripted_stroke([Vector2i(12, 12)])
	check_eq(_lv(ed, Vector2i(12, 12)), 0, "lower floors at valley (0)")
	# smooth: a lone ridge spike in plain ground flattens
	ht.set_tool("level")
	ht.level = 3
	ed.view.scripted_stroke([Vector2i(20, 20)])
	check_eq(_lv(ed, Vector2i(20, 20)), 3, "level tool sets ridge")
	ht.set_tool("smooth")
	ed.view.scripted_stroke([Vector2i(20, 20)])
	check_eq(_lv(ed, Vector2i(20, 20)), 1, "smooth: a lone spike takes its neighbourhood's level")
	# ramp: only on a one-level step
	ht.set_tool("level")
	ht.level = 2
	ht.bsize = 3
	ed.view.scripted_stroke([Vector2i(30, 10)])   # hill block 29..31 x 9..11
	ht.level = 3
	ht.bsize = 1
	ed.view.scripted_stroke([Vector2i(30, 25)])   # ridge cell next to plain: a 2-level cliff
	ht.set_tool("ramp")
	ed.view.scripted_stroke([Vector2i(32, 10)])
	ed.view.scripted_stroke([Vector2i(35, 10)])
	ed.view.scripted_stroke([Vector2i(31, 25)])
	var rp: PackedByteArray = ed.doc.map.ramps
	var w := int(ed.doc.map.w)
	check_eq(int(rp[10 * w + 32]), 1, "ramp painted on a one-level step")
	check_eq(int(rp[10 * w + 35]), 0, "no ramp on flat ground")
	check_eq(int(rp[25 * w + 31]), 0, "no ramp across a two-level cliff")
	# lowering the hill drops the now-invalid ramp
	ht.set_tool("level")
	ht.level = 1
	ht.bsize = 3
	ed.view.scripted_stroke([Vector2i(30, 10)])
	check_eq(int((ed.doc.map.ramps as PackedByteArray)[10 * w + 32]), 0, "ramps that no longer join a step are pruned")
	# symmetry-aware
	var mode := ""
	for m in Symmetry.MODES:
		if String(m) != "off" and Symmetry.valid_for(String(m), N, N):
			mode = String(m)
			break
	ed.set_symmetry(mode)
	ht.set_tool("raise")
	ht.bsize = 1
	var c := Vector2i(5, 8)
	ed.view.scripted_stroke([c])
	var mirrored: Array = Symmetry.expand([c], mode, N, N)
	check(mirrored.size() >= 2, "symmetry %s mirrors the cell" % mode)
	for q in mirrored:
		check_eq(_lv(ed, Vector2i(q)), 2, "symmetric raise at %s" % str(q))
	ed.set_symmetry("off")
	# undo restores exactly, back to no height layer at all
	while ed.doc.undo_depth() > d0:
		ed.action_undo()
	check(not ed.doc.map.has("height") and not ed.doc.map.has("ramps"), "undoing every stroke removes the height layers")
	ed.action_redo()
	check_eq(_lv(ed, Vector2i(10, 10)), 2, "redo re-applies the first raise")
	# the map file keeps height + ramps
	var path := "user://test_ed6/height.rtsmap"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check_eq(MapIO.save(path, ed.doc.map_for_save(), ed.doc.scenario_for_save()), "", "saved with height")
	var r := MapIO.read(path)
	check(r.has("map") and (r.map.get("height", PackedByteArray()) as PackedByteArray) == (ed.doc.map.height as PackedByteArray), "height round-trips through the map file")
	ed.free()


func test_height_validation_reachable() -> void:
	Content.load_all()
	var ed = _editor()
	var ht = _height_tab(ed, "level")
	check(ht.validate().is_empty(), "no height: no height issues")
	# a hill wall across the whole map cuts start 1 (4,4) from start 2 (35,35)
	ht.level = 2
	ht.mode = "rect"
	ed.view.scripted_stroke([Vector2i(20, 0), Vector2i(21, N - 1)])
	var codes := []
	for it in ht.validate():
		codes.append(String(it.code))
	check(codes.has("spawn_unreachable"), "a cliff wall makes a start unreachable: %s" % str(codes))
	check(ht._issues_label.text.contains("spawn_unreachable"), "the Height tab shows the issue")
	# auto ramps join the halves through one-level ramps (one undo step)
	var d: int = ed.doc.undo_depth()
	check(ht.auto_ramps() > 0, "auto ramps adds ramps")
	check_eq(ed.doc.undo_depth(), d + 1, "auto ramps is one undo step")
	codes = []
	for it in ht.validate():
		codes.append(String(it.code))
	check(not codes.has("spawn_unreachable"), "ramps make every start reachable: %s" % str(codes))
	# a start on mixed levels is flagged
	ht.mode = "brush"
	ht.bsize = 1
	ht.level = 3
	ed.view.scripted_stroke([Vector2i(5, 4)])
	codes = []
	for it in ht.validate():
		codes.append(String(it.code))
	check(codes.has("spawn_not_flat"), "a start next to a level change is flagged: %s" % str(codes))
	ed.free()


func test_g6_placements_mines_garrison_rail_naval_hq() -> void:
	Content.load_all()
	var m := grass_map()
	for y in N:
		for x in range(32, N):
			m.terrain[y * N + x] = Terrain.DEEP
	var ed = _editor()
	ed.doc.set_doc(m, clash_scenario())
	ed.select_tab("units")
	var ut = ed.tab_panel("units")
	ut.set_player(0)
	ut.fac_filter = Content.faction_ids().size() + 1
	ut.fill_palette()
	for id in ["a_carrier", "a_submarine", "a_company_hq", "b_company_hq", "m_company_hq", "a_minesweeper", "b_mine_barge"]:
		check(ut.pick(id), "editor palette lists %s" % id)
	# naval: carrier and sub only on water
	check(M.place_reason(ed.doc.map, "unit", "a_submarine", Vector2i(36, 10)) == "", "sub on deep water")
	check(M.place_reason(ed.doc.map, "unit", "a_submarine", Vector2i(10, 30)) != "", "sub refused on land")
	ut.pick("a_carrier")
	ut.set_mode("place")
	var n0: int = ut.ents().size()
	ed.view.scripted_stroke([Vector2i(36, 30)])
	check_eq(ut.ents().size(), n0 + 1, "carrier placed at sea")
	ed.view.scripted_stroke([Vector2i(10, 34)])
	check_eq(ut.ents().size(), n0 + 1, "carrier refused on land")
	ut.pick("a_company_hq")
	ed.view.scripted_stroke([Vector2i(6, 6)])
	check_eq(String(ut.ents().back().def), "a_company_hq", "Company HQ placed")
	# minefield: drag a rect, clamped to 8x8, one undo step
	ut.set_mode("minefield")
	ut.mine_kind = "at"
	var d: int = ed.doc.undo_depth()
	ed.view.scripted_stroke([Vector2i(10, 20), Vector2i(20, 24)])
	var mf: Dictionary = ut.ents().back()
	check_eq(String(mf.kind), "minefield", "minefield entity")
	check_eq(mf.size, [8, 5], "minefield rect clamped to 8 wide")
	check_eq(String(mf.mine), "at", "minefield mine kind")
	check_eq(M.entity_at(ut.ents(), Vector2i(17, 24)), ut.ents().size() - 1, "minefield selectable over its rect")
	check_eq(ed.doc.undo_depth(), d + 1, "minefield is one undo step")
	# company as one block
	ut.set_mode("company")
	var tids: Array = Companies.templates_for("human_a")
	check(tids.size() > 0, "human_a company templates")
	ut.company_tid = String(tids[0])
	var want: int = M.company_units(ut.company_tid).size()
	check(want >= 4, "template %s has units (%d)" % [ut.company_tid, want])
	var before: int = ut.ents().size()
	d = ed.doc.undo_depth()
	ed.view.scripted_stroke([Vector2i(4, 26)])
	var placed: Array = ut.ents().slice(before)
	check_eq(placed.size(), want, "the whole company placed")
	var blocks := {}
	for e in placed:
		blocks[String(e.get("company_block", ""))] = true
		check_eq(String(e.get("company", "")), ut.company_tid, "unit tagged with its company")
	check(blocks.size() == 1 and not blocks.has(""), "one block id for the company")
	check_eq(ed.doc.undo_depth(), d + 1, "a company is one undo step")
	ed.action_undo()
	check_eq(ut.ents().size(), before, "undo removes the whole company")
	# garrison: infantry into a garrisonable building, capped, infantry only
	var gdef := ""
	for id in Content.ids("buildings"):
		if String(Content.building(id).get("faction", "")) == "human_a" and Garrison.slots_of(String(id)) > 0:
			gdef = String(id)
			break
	check(gdef != "", "a garrisonable human_a building exists")
	if gdef != "":
		ut.set_mode("place")
		check(ut.pick(gdef), "garrison building in the palette")
		ed.view.scripted_stroke([Vector2i(24, 4)])
		ut.set_mode("select")
		ed.view.scripted_stroke([Vector2i(24, 4)])
		check(ut.selected >= 0 and String(ut.ents()[ut.selected].def) == gdef, "garrison building selected")
		ut.pick("rifleman")
		var cap: int = Garrison.slots_of(gdef)
		for i in cap:
			check_eq(ut.sel.garrison_picked(), "", "rifleman %d garrisoned" % (i + 1))
		check(ut.sel.garrison_picked().contains("full"), "garrison capped at %d" % cap)
		check_eq((ut.ents()[ut.selected].get("garrison", []) as Array).size(), cap, "garrison stored on the building")
		check(M.garrison_reason(gdef, [], "a_carrier") != "", "ships cannot garrison")
	# rail: terrain code 14 from the Terrain tab
	ed.select_tab("terrain")
	var tt = ed.tab_panel("terrain")
	tt.code = Terrain.RAIL
	tt.layer = "terrain"
	tt.bsize = 1
	tt.mode = "brush"
	ed.view.scripted_stroke([Vector2i(3, 15), Vector2i(8, 15)])
	check_eq(int(ed.doc.map.terrain[15 * N + 5]), Terrain.RAIL, "rail painted")
	ed.free()


func test_undo_history_untouched_by_live() -> void:
	Content.load_all()
	var ed = _editor()
	ed.select_tab("units")
	var ut = ed.tab_panel("units")
	ut.set_player(0)
	check(ut.pick("rifleman"), "rifleman in the palette")
	ut.set_mode("place")
	ed.view.scripted_stroke([Vector2i(10, 10)])
	ed.view.scripted_stroke([Vector2i(11, 10)])
	var depth: int = ed.doc.undo_depth()
	var label: String = ed.doc.undo_label()
	var n: int = ut.ents().size()
	check(depth >= 2, "two placements on the undo stack")
	ed.live_start()
	ed.live_advance(100)
	ed.action_undo()
	check_eq(ed.doc.undo_depth(), depth, "undo is refused while Live runs")
	ed.select_tab("terrain")
	ed.view.scripted_stroke([Vector2i(5, 5), Vector2i(6, 5)])
	check_eq(ed.doc.undo_depth(), depth, "map brushes are blocked while Live runs")
	ed.live_stop()
	check_eq(ed.doc.undo_depth(), depth, "undo depth unchanged by Live")
	check_eq(ed.doc.undo_label(), label, "top undo step unchanged by Live")
	check_eq(ut.ents().size(), n, "doc entities unchanged by Live")
	ed.action_undo()
	check_eq(ut.ents().size(), n - 1, "undo after Live removes the last placement")
	ed.free()
