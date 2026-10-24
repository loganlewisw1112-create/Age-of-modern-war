extends SceneTree
## G4e editor playtest (owner: ED2), driven ONLY by synthetic mouse/keyboard events through the
## real viewport (same path as hardware, like tools/ui_playtest.gd). Run windowed:
##   godot --path game -s res://tools/editor_playtest.gd -- --shots=C:/abs/dir
## Flow: main menu -> Map Editor -> name + New 128 map -> paint terrain -> river -> lake -> scatter
## trees -> symmetry (rotate 180) -> Players (P2 faction, start packages off, starts) -> HQ + units
## for 2 players -> Validate (0 issues) -> Save (file dialog) -> Exit -> skirmish map list ->
## pick the custom map -> START MATCH -> the match runs 30 s.
## Prints "PLAYTEST <step> ok=<bool> <detail>" lines and "PLAYTEST RESULT pass=N fail=M".
## (Code reads state only to find widgets/coordinates and to check results; every action is input.)

const MapIO = preload("res://sim/map_io.gd")
const M = preload("res://presentation/editor/ed2_model.gd")
const MAP_NAME := "ED2 Playtest"
const MAP_FILE := "user://maps/ed2_playtest.rtsmap"

var main: Node
var shot_dir := ""
var passed := 0
var failed := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--shots="):
			shot_dir = String(a).trim_prefix("--shots=")
	if shot_dir == "":
		shot_dir = OS.get_user_data_dir().path_join("editor_playtest")
	DirAccess.make_dir_recursive_absolute(shot_dir)
	main = load("res://presentation/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _log(step: String, ok: bool, detail: String = "") -> bool:
	if ok:
		passed += 1
	else:
		failed += 1
	print("PLAYTEST %s ok=%s %s" % [step, ok, detail])
	return ok


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var t := 0.0
	while t < timeout_sec:
		if cond.call():
			return true
		await create_timer(0.25).timeout
		t += 0.25
	return bool(cond.call())


func _shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var path := shot_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("PLAYTEST_SHOT ", path)


# ------------------------------------------------------------ input injection
func _push(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		# events enter in WINDOW coords; every position here is a root-viewport position
		var me := ev as InputEventMouse
		var wp: Vector2 = root.get_final_transform() * me.position
		me.position = wp
		me.global_position = wp
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _move(p: Vector2, mask: int = 0) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	m.button_mask = mask
	_push(m)
	await process_frame


func _button(p: Vector2, idx: int, pressed: bool) -> void:
	var b := InputEventMouseButton.new()
	b.position = p
	b.global_position = p
	b.button_index = idx
	b.pressed = pressed
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and idx == MOUSE_BUTTON_LEFT else 0
	_push(b)
	await process_frame


func _click(p: Vector2, idx: int = MOUSE_BUTTON_LEFT) -> void:
	await _move(p)
	await _button(p, idx, true)
	await _button(p, idx, false)
	await _frames(2)


func _drag(pts: Array) -> void:
	await _move(pts[0])
	await _button(pts[0], MOUSE_BUTTON_LEFT, true)
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		for k in 4:
			await _move(a.lerp(b, float(k + 1) / 4.0), MOUSE_BUTTON_MASK_LEFT)
	await _button(pts[pts.size() - 1], MOUSE_BUTTON_LEFT, false)
	await _frames(2)


func _wheel(p: Vector2, up: bool, n: int = 1) -> void:
	for i in n:
		await _move(p)
		await _button(p, MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN, true)
		await _button(p, MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN, false)


func _key(code: Key, unicode: int = 0, ctrl: bool = false) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.unicode = unicode if pressed else 0
		k.ctrl_pressed = ctrl
		k.pressed = pressed
		_push(k)
		await process_frame


func _type(text: String) -> void:
	for ch in text:
		var u := ch.unicode_at(0)
		var code: Key = KEY_SPACE if ch == " " else (OS.find_keycode_from_string(ch.to_upper()) as Key)
		await _key(code, u)


# ------------------------------------------------------------ widget finding
## Viewport position of a Control's centre (works inside embedded windows too).
func _center(c: Control) -> Vector2:
	var p := c.get_global_transform_with_canvas() * (c.size * 0.5)
	var w := c.get_window()
	if w != null and w != root:
		p += Vector2(w.position)
	return p


func _find_button(from: Node, needle: String, exact: bool = false) -> Button:
	for c in from.get_children():
		if c is Button and (c as Button).is_visible_in_tree() and not (c as Button).disabled:
			var t := String((c as Button).text)
			if (exact and t == needle) or (not exact and t.contains(needle)):
				return c
		var r := _find_button(c, needle, exact)
		if r != null:
			return r
	return null


func _press(needle: String, from: Node = null, exact: bool = false) -> bool:
	var b := _find_button(from if from != null else root, needle, exact)
	if b == null:
		print("PLAYTEST-DBG no button '%s'" % needle)
		return false
	await _click(_center(b))
	return true


func _pick_option(ob: OptionButton, idx: int) -> bool:
	if ob == null or idx < 0 or idx >= ob.item_count:
		return false
	if ob.selected == idx:
		return true
	await _click(_center(ob))
	await _wait(0.3)
	var pm := ob.get_popup()
	if not pm.visible:
		return false
	var top := 0.0
	var bottom := 0.0
	var sb := pm.get_theme_stylebox("panel")
	if sb != null:
		top = sb.get_margin(SIDE_TOP)
		bottom = sb.get_margin(SIDE_BOTTOM)
	var h := (float(pm.size.y) - top - bottom) / float(pm.item_count)
	await _click(Vector2(pm.position) + Vector2(float(pm.size.x) * 0.5, top + (float(idx) + 0.5) * h))
	await _wait(0.2)
	if pm.visible:
		pm.hide()
	return ob.selected == idx


## Scrolls an ItemList with the wheel until item i is visible, then clicks it.
func _click_item(list: ItemList, i: int) -> bool:
	if list == null or i < 0 or i >= list.item_count:
		return false
	var sb := list.get_v_scroll_bar()
	for n in 60:
		var r := list.get_item_rect(i)
		var y := r.position.y - (sb.value if sb.visible else 0.0)
		if y >= 0.0 and y + r.size.y <= list.size.y:
			var local := Vector2(r.get_center().x, y + r.size.y * 0.5)
			await _click(list.get_global_transform_with_canvas() * local)
			return list.is_selected(i)
		await _wheel(_center(list), y < 0.0)
	return false


func _item_index(list: ItemList, needle: String) -> int:
	for i in list.item_count:
		if list.get_item_text(i).contains(needle):
			return i
	return -1


# ------------------------------------------------------------ editor helpers
func _ed():
	return main._editor


func _cell_vp(c: Vector2i) -> Vector2:
	var v = _ed().view
	return v.get_viewport().get_canvas_transform() * v.world_to_screen(Vector2(c) + Vector2(0.5, 0.5))


## True when p is over the map area (not under the editor panels).
func _on_map(p: Vector2) -> bool:
	var vs := root.get_visible_rect().size
	var s: float = _ed().ui_scale
	return p.x > 310.0 * s and p.x < vs.x - 272.0 * s and p.y > 56.0 * s and p.y < vs.y - 38.0 * s


## Click the minimap so the camera centres on cell c.
func _jump(c: Vector2i) -> void:
	var mm = _ed().minimap
	mm._update_xf()
	await _click(mm.get_global_transform_with_canvas() * (mm._xf * (Vector2(c) + Vector2(0.5, 0.5))))
	await _settle()


## Waits until the camera stops moving (the rig eases and clamps over several frames).
func _settle() -> void:
	var v = _ed().view
	var last: Transform2D = v.get_viewport().get_canvas_transform()
	var still := 0
	for i in 180:
		await process_frame
		var now: Transform2D = v.get_viewport().get_canvas_transform()
		still = still + 1 if now.is_equal_approx(last) else 0
		last = now
		if still >= 6:
			return


func _map_click(c: Vector2i) -> bool:
	var p := _cell_vp(c)
	if not _on_map(p):
		print("PLAYTEST-DBG cell %s off the map area at %s" % [c, p])
		return false
	await _move(p)
	var got: Vector2i = _ed().view.mouse_cell()
	if got != c:
		print("PLAYTEST-DBG map_click target %s mouse_cell %s at %s" % [c, got, p])
	await _click(p)
	return true


func _map_drag(cells: Array) -> bool:
	var pts: Array = []
	for c in cells:
		var p := _cell_vp(c)
		if not _on_map(p):
			print("PLAYTEST-DBG drag cell %s off the map area at %s" % [c, p])
			return false
		pts.append(p)
	await _drag(pts)
	return true


func _tab(title: String) -> bool:
	return await _press(title, _ed()._p.tab_bar, true)


func _count(codes: Array) -> int:
	var n := 0
	for v in _ed().doc.map.terrain:
		if codes.has(int(v)):
			n += 1
	return n


func _code(c: Vector2i) -> int:
	return int(_ed().doc.map.terrain[c.y * int(_ed().doc.map.w) + c.x])


# ------------------------------------------------------------ flow
func _run() -> void:
	await _wait(1.5)
	for f in [MAP_FILE, "user://maps/e_d2_playtest.rtsmap", "user://maps/ed_2_playtest.rtsmap"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	_log("menu_map_editor", await _press("Map Editor"))
	_log("editor_open", await _wait_until(func(): return main._editor != null, 6.0))
	if main._editor == null:
		_finish()
		return
	await _wait(1.0)
	var ed = _ed()
	# --- new 128 map + name
	await _press("New", root, true)
	var mp = ed.tab_panel("map")
	await _press("128", mp, true)
	await _press("Create blank map", mp)
	await _click(_center(mp._name))
	await _key(KEY_A, 0, true)
	await _type(MAP_NAME)
	await _frames(2)
	_log("new_map_128", int(ed.doc.map.w) == 128 and int(ed.doc.map.h) == 128 and String(ed.doc.scenario.name) == MAP_NAME,
		"%dx%d name='%s'" % [int(ed.doc.map.w), int(ed.doc.map.h), String(ed.doc.scenario.name)])
	var mid := Vector2(root.get_visible_rect().size.x * 0.5 + 20.0, root.get_visible_rect().size.y * 0.5)
	await _wheel(mid, false, 3)
	await _settle()
	# --- paint terrain
	await _tab("Terrain")
	await _press("Dirt", ed.tab_panel("terrain"), true)
	await _jump(Vector2i(40, 40))
	var dragged := await _map_drag([Vector2i(36, 40), Vector2i(40, 42), Vector2i(44, 40)])
	_log("paint_terrain", dragged and _code(Vector2i(40, 42)) == 1, "dirt at 40,42 code=%d" % _code(Vector2i(40, 42)))
	# --- river
	await _tab("Water")
	var wp = ed.tab_panel("water")
	await _press("River", wp, true)
	var water0 := _count([4, 6, 9, 10])
	await _jump(Vector2i(64, 62))
	for c in [Vector2i(56, 64), Vector2i(64, 61), Vector2i(72, 64)]:
		await _map_click(c)
	await _press("Build river", wp)
	var water1 := _count([4, 6, 9, 10])
	_log("draw_river", water1 > water0 + 10, "water cells %d -> %d" % [water0, water1])
	# --- lake
	await _press("Lake", wp, true)
	await _jump(Vector2i(40, 90))
	await _map_click(Vector2i(40, 90))
	var water2 := _count([4, 6, 9, 10])
	_log("fill_lake", water2 > water1 + 20 and _code(Vector2i(40, 90)) in [9, 10], "water cells %d -> %d, centre code %d" % [water1, water2, _code(Vector2i(40, 90))])
	await _shot("01_terrain_water")
	# --- scatter trees
	await _tab("Nature & objects")
	var np = ed.tab_panel("nature")
	_log("pick_trees", await _click_item(np._list, _item_index(np._list, "Trees")))
	await _press("Scatter brush", np, true)
	var f0 := _count([3])
	await _jump(Vector2i(90, 40))
	await _map_drag([Vector2i(86, 38), Vector2i(90, 41), Vector2i(94, 42)])
	_log("scatter_trees", _count([3]) > f0 + 5, "forest %d -> %d" % [f0, _count([3])])
	# --- symmetry
	_log("symmetry_rotate180", await _pick_option(ed._p.sym_opt, 4) and String(ed.doc.symmetry) == "rotate_180", String(ed.doc.symmetry))
	await _players(ed)
	await _units(ed)
	await _validate_save(ed)
	await _skirmish()
	_finish()


func _players(ed) -> void:
	await _tab("Players")
	var pt = ed.tab_panel("players")
	var fa := String(ed.doc.scenario.players[0].faction)
	_log("p2_faction", await _pick_option(pt.rows[1].faction, pt._facs.find(fa)) and String(ed.doc.scenario.players[1].faction) == fa,
		"P2 faction %s" % String(ed.doc.scenario.players[1].faction))
	await _click(_center(pt._pk))
	_log("start_packages_off", not bool(ed.doc.map.get("start_packages", true)))
	await _jump(Vector2i(22, 22))
	await _click(_center(pt.rows[0].start_btn))
	await _map_click(Vector2i(20, 20))
	var s0 := MapIO._v2i(ed.doc.scenario.players[0].start)
	var s1 := MapIO._v2i(ed.doc.scenario.players[1].start)
	_log("set_starts", s0 == Vector2i(20, 20) and s1 == Vector2i(107, 107), "P1 %s P2 %s (mirrored)" % [s0, s1])


func _units(ed) -> void:
	await _tab("Units & buildings")
	var ut = ed.tab_panel("units")
	await _click(_center(ut._chips.get_child(0)))
	var fa := String(ed.doc.scenario.players[0].faction)
	var hq := Content.role(fa, "hq")
	var hi := -1
	var foot := -1
	for i in ut.items.size():
		if ut.items[i][1] == hq:
			hi = i
		if foot < 0 and ut.items[i][0] == "unit" and M.cargo_class(String(ut.items[i][1])) == "foot":
			foot = i
	_log("palette_hq", await _click_item(ut.palette_list, hi) and ut.pick_def == hq, "hq=%s" % hq)
	await _press("Place", ut, true)
	await _jump(Vector2i(26, 26))
	await _map_click(Vector2i(25, 25))
	var hqs: Array = ut.ents().filter(func(e): return String(e.def) == hq)
	_log("place_hq_2_players", hqs.size() == 2 and int(hqs[0].owner_slot) != int(hqs[1].owner_slot) if hqs.size() == 2 else false,
		"%d HQs" % hqs.size())
	_log("palette_unit", await _click_item(ut.palette_list, foot), "unit=%s" % ut.pick_def)
	await _key(KEY_E)
	await _press("Formation box", ut, true)
	var n0: int = ut.ents().size()
	await _map_drag([Vector2i(22, 29), Vector2i(24, 30), Vector2i(25, 30)])
	var owners := {}
	for e in ut.ents().slice(n0):
		owners[int(e.owner_slot)] = int(owners.get(int(e.owner_slot), 0)) + 1
	_log("formation_units", ut.ents().size() - n0 == 16 and owners.size() == 2, "added %d, per owner %s" % [ut.ents().size() - n0, owners])
	await _shot("02_units_placed")


func _validate_save(ed) -> void:
	await _press("Validate", root, true)
	var issues: Array = MapIO.validate(ed.doc.map_for_save(), ed.doc.scenario_for_save())
	issues.append_array(load("res://presentation/editor/ed2_scenario.gd").extra_issues(ed.doc.map_for_save(), ed.doc.scenario_for_save()))
	_log("validate_0_issues", issues.is_empty() and _find_button(ed._p.issues_box, "Go") == null, "issues=%s" % str(issues))
	await _shot("03_validate")
	await _press("Save", root, true)
	var dlg: FileDialog = ed._p.dialog
	await _wait_until(func(): return dlg.visible, 3.0)
	await _wait(0.5)
	if dlg.visible:
		await _click(_center(dlg.get_ok_button()))
	var saved := await _wait_until(func(): return String(ed.doc.path) != "" and FileAccess.file_exists(String(ed.doc.path)), 4.0)
	_log("save", saved, "path=%s" % String(ed.doc.path))
	await _press("Exit", root, true)
	_log("back_to_menu", await _wait_until(func(): return main._editor == null and root.find_child("ED2MapList", true, false) != null, 5.0))


func _skirmish() -> void:
	await _wait(0.8)
	var list := root.find_child("ED2MapList", true, false) as ItemList
	if list == null:
		_log("skirmish_list", false)
		return
	var idx := _item_index(list, MAP_NAME)
	_log("custom_map_listed", idx >= 0, list.get_item_text(idx) if idx >= 0 else "")
	_log("pick_custom_map", await _click_item(list, idx))
	var setup = root.find_child("SkirmishSetup", true, false)
	_log("sides_prefilled", setup != null and setup.is_custom() and String(setup.custom_path()).ends_with(".rtsmap"), String(setup.custom_path()) if setup != null else "")
	await _shot("04_skirmish_custom")
	await _press("START MATCH", root, true)
	var started := await _wait_until(func(): return main.match_view != null and main.match_view.get("world") != null, 10.0)
	_log("match_started", started)
	if not started:
		return
	var w: SimWorld = main.match_view.world
	_log("match_from_file", String(w.cfg.get("map_file", "")).ends_with(".rtsmap") and int(w.map.w) == 128,
		"map_file=%s %dx%d" % [String(w.cfg.get("map_file", "")), int(w.map.w), int(w.map.h)])
	var t0 := int(w.tick)
	await _wait(30.0)
	w = main.match_view.world if main.match_view != null else null
	var t1 := int(w.tick) if w != null else -1
	var alive := 0
	if w != null:
		for f in w.factions.values():
			if bool(f.get("alive", false)):
				alive += 1
	_log("match_runs_30s", w != null and t1 - t0 >= 15 * SimWorld.TICK_RATE and alive == 2, "ticks %d -> %d, alive sides %d" % [t0, t1, alive])
	await _shot("05_match_30s")


func _finish() -> void:
	print("PLAYTEST RESULT pass=%d fail=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
