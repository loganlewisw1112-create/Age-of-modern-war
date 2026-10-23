extends Node
## UI-01 playtest driven ONLY by synthetic input events pushed into the real viewport
## (the same path as a mouse/keyboard): menu click -> select builders -> build the power role via
## hotkey + world click -> build the barracks role -> select it -> click the infantry-role card
## button -> officer flow -> select the squad -> attack-move toward the bridge.  Run:
##   godot --path game -- --ui-playtest=C:/abs/shot_dir [--ui-playtest-faction=human_b|machine]
## G3a (UI3): every def comes from content/factions.json roles and unit flags (can_build /
## can_gather), never from Human A names. With --ui-playtest-faction the menu is set up by real
## clicks on the OptionButtons (slot 0 faction, slot 2 opened as AI with a third faction).
## Prints "PLAYTEST <step> ok=<bool> <detail>" lines and "PLAYTEST RESULT pass=N fail=M".

const Construction = preload("res://sim/systems/construction.gd")
const MatchViewScript = preload("res://presentation/match_view.gd")
const Ops = preload("res://sim/systems/ops.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")

var main: Node
var shot_dir := ""
var faction := ""     # --ui-playtest-faction ("" = leave the menu defaults: Human A vs Human A)
var passed := 0
var failed := 0


func _ready() -> void:
	_run()


func _log(step: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("PLAYTEST %s ok=%s %s" % [step, ok, detail])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var t := 0.0
	while t < timeout_sec:
		if cond.call():
			return true
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	return bool(cond.call())


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_dir.path_join(name + ".png"))


# ------------------------------------------------------------ input injection
## Input.parse_input_event updates the Input singleton (button/key held state) exactly like real
## hardware, then dispatches to the viewport. (push_input skipped the singleton, so the view's
## "button released?" safety check cancelled synthetic drags.)
func _push(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _move(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	_push(m)
	await get_tree().process_frame


func _button(p: Vector2, idx: int, pressed: bool, dbl: bool = false, shift: bool = false) -> void:
	var b := InputEventMouseButton.new()
	b.shift_pressed = shift
	b.position = p
	b.global_position = p
	b.button_index = idx
	b.pressed = pressed
	b.double_click = dbl
	_push(b)
	await get_tree().process_frame


func _click(p: Vector2, idx: int = MOUSE_BUTTON_LEFT, dbl: bool = false, shift: bool = false) -> void:
	await _move(p)
	await _button(p, idx, true, dbl, shift)
	await _button(p, idx, false, false, shift)


func _drag(a: Vector2, b: Vector2) -> void:
	await _move(a)
	await _button(a, MOUSE_BUTTON_LEFT, true)
	for i in 6:
		await _move(a.lerp(b, float(i + 1) / 6.0))
	await _button(b, MOUSE_BUTTON_LEFT, false)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		_push(k)
		await get_tree().process_frame


func _find_button(root: Node, needle: String) -> Button:
	for c in root.get_children():
		if c is Button and c.is_visible_in_tree() and String(c.text).contains(needle):
			return c
		var r := _find_button(c, needle)
		if r != null:
			return r
	return null


func _click_button(needle: String) -> bool:
	var b := _find_button(get_tree().root, needle)
	if b == null:
		return false
	await _click(b.get_global_rect().get_center())
	return true


# ------------------------------------------------------------ world helpers
func _mv():
	return main.match_view


func _w() -> SimWorld:
	return _mv().world


func _to_screen(p: Vector2) -> Vector2:
	var mv = _mv()
	return mv.get_viewport().get_canvas_transform() * (mv.global_transform * MatchViewScript.world_to_screen(p))



func _own_units(def_id: String) -> Array:
	return _own_units_in([def_id])


func _own_units_in(defs: Array) -> Array:
	var out := []
	for e in _w().units_of(0):
		if defs.has(String(e.def)):
			out.append(e)
	return out


# ------------------------------------------------------------ G3a role lookups
func _fac() -> String:
	return G3.faction_def(_w(), 0)


func _role(r: String) -> String:
	return Content.role(_fac(), r)


## Own unit defs carrying a unit flag (can_build / can_gather), in first-seen order.
func _defs_with(flag: String) -> Array:
	var out := []
	for e in _w().units_of(0):
		var d := String(e.def)
		if not out.has(d) and bool(Content.unit(d).get(flag, false)):
			out.append(d)
	return out


func _hq() -> Dictionary:
	var hs: Array = _w().buildings_of(0, _role("hq"))
	return hs[0] if not hs.is_empty() else {}


## The build hotkey the HUD shows for def (same remap order as hud.gd's build card).
func _hotkey(def_id: String) -> String:
	var used := {}
	for b in Content.buildable_for(_fac()):
		var hk := G3.build_hotkey(String(b), used)
		if String(b) == def_id:
			return hk
	return ""


func _built(def_id: String) -> bool:
	var bs: Array = _w().buildings_of(0, def_id)
	return bs.size() > 0 and bool(bs[0].built)


## The first own building whose def produces item (officer may come from the HQ or barracks).
func _producer_of(item: String) -> Dictionary:
	for b in _w().buildings_of(0):
		if bool(b.get("built", false)) and (Content.building(String(b.def)).get("produces", []) as Array).has(item):
			return b
	return {}


func _site(def_id: String) -> Vector2i:
	var w := _w()
	var hq := _hq()
	if hq.is_empty():
		return Vector2i(-1, -1)
	var c: Vector2i = hq.cell
	for r in range(4, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var o := c + Vector2i(dx, dy)
				if Construction.placement_error(w, 0, def_id, o) == "":
					var size := int(Content.building(def_id).size)
					var centre := Vector2(o) + Vector2(size, size) * 0.5
					var sp := _to_screen(centre)
					if sp.x > 80 and sp.x < 1500 and sp.y > 120 and sp.y < 640:
						return o
	return Vector2i(-1, -1)


## Click then double-click one unit of defs[0] (= select all of that type on screen); returns how
## many selected units have a def in defs.
func _select_units(defs: Array) -> int:
	var us := _own_units_in(defs)
	if us.is_empty():
		return 0
	await _click(_to_screen(us[0].pos), MOUSE_BUTTON_LEFT)
	await _click(_to_screen(us[0].pos), MOUSE_BUTTON_LEFT, true)
	await _wait(0.3)
	var n := 0
	for id in _mv().selection:
		var e = _w().get_e(int(id))
		if e != null and defs.has(String(e.def)):
			n += 1
	return n


func _place(def_id: String) -> bool:
	var o := _site(def_id)
	if o.x < 0:
		_log("site_" + def_id, false, "no legal on-screen site")
		return false
	var hk := _hotkey(def_id)
	var code := OS.find_keycode_from_string(hk)
	if hk == "" or code == KEY_NONE:
		_log("hotkey_" + def_id, false, "no hotkey (%s)" % hk)
		return false
	await _key(code)
	await _wait(0.3)
	var size := int(Content.building(def_id).size)
	var centre := Vector2(o) + Vector2(size, size) * 0.5
	await _move(_to_screen(centre))
	await _wait(0.4)
	await _shot("ui_ghost_" + def_id)
	await _click(_to_screen(centre))
	await _wait(0.5)
	return _w().buildings_of(0, def_id).size() > 0


# ------------------------------------------------------------ menu (G3a skirmish setup)
## Real clicks: open the OptionButton, then click item idx inside its popup.
func _pick_option(node_name: String, idx: int) -> bool:
	var ob := get_tree().root.find_child(node_name, true, false) as OptionButton
	if ob == null or idx < 0 or idx >= ob.item_count:
		return false
	if ob.selected == idx:
		return true
	await _click(ob.get_global_rect().get_center())
	await _wait(0.4)
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
	var p := Vector2(pm.position) + Vector2(float(pm.size.x) * 0.5, top + (float(idx) + 0.5) * h)
	await _click(p)
	await _wait(0.3)
	if pm.visible:
		pm.hide()
	return ob.selected == idx


func _setup_menu() -> void:
	var ids: Array = Content.faction_ids()
	var mine := ids.find(faction)
	_log("menu_faction_known", mine >= 0, faction)
	if mine < 0:
		return
	var third := ""
	for f in ids:
		if String(f) != faction and String(f) != "human_a":
			third = String(f)
			break
	if third == "":
		third = "human_a"
	_log("menu_slot0_faction_click", await _pick_option("Slot0Faction", mine), faction)
	_log("menu_slot2_open_ai_click", await _pick_option("Slot2Kind", 0))
	_log("menu_slot2_faction_click", await _pick_option("Slot2Faction", ids.find(third)), third)
	await _wait(0.3)


# ------------------------------------------------------------ the run
## Select the gatherer units and right-click the nearest visible salvage pile (smart gather).
func _gather_salvage(gatherers: Array, tag: String) -> void:
	var n_gat := _own_units_in(gatherers).size()
	var n := await _select_units(gatherers)
	_log("select_gatherers_" + tag, n >= mini(4, n_gat) and n > 0, "selected=%d of %d" % [n, n_gat])
	var pile = null
	var best := 1e9
	var hqp: Vector2 = _hq().pos
	for e in _w().entities.values():
		if e.kind == "resource" and e.res == "salvage" and _w().is_visible(0, e.pos):
			var dd: float = e.pos.distance_to(hqp)
			if dd < best:
				best = dd
				pile = e
	_log("visible_salvage_pile_" + tag, pile != null)
	if pile == null:
		return
	await _click(_to_screen(pile.pos), MOUSE_BUTTON_RIGHT)
	await _wait(0.5)
	var gathering := 0
	for e in _own_units_in(gatherers):
		if String(e.order.type) == "gather":
			gathering += 1
	_log("right_click_gather_" + tag, gathering >= mini(4, n_gat) and gathering > 0, "gathering=%d" % gathering)
	if tag == "1":
		await _shot("ui_035_gathering")


func _run() -> void:
	await _wait(1.5)
	if faction != "":
		await _setup_menu()
	await _shot("ui_00_menu")
	_log("menu_start_button", await _click_button("START MATCH"))
	var started := await _wait_until(func(): return main.match_view != null and main.match_view.world != null, 10.0)
	_log("match_started", started)
	if not started:
		return _finish()
	await _wait(1.5)
	_log("player_faction", faction == "" or _fac() == faction, "faction=%s sides=%d" % [_fac(), _w().factions.size()])
	await _shot("ui_01_start")

	var pdef := _role("power")
	var bdef := _role("barracks")
	var builders := _defs_with("can_build")
	var gatherers := _defs_with("can_gather")
	var inf_item := _role("infantry")
	var inf_units := G3.item_units(inf_item)
	print("PLAYTEST-DBG roles power=%s barracks=%s builders=%s gatherers=%s infantry=%s->%s" % [pdef, bdef, builders, gatherers, inf_item, inf_units])
	var n_build := _own_units_in(builders).size()
	var want_sel := mini(4, n_build)

	var n := await _select_units(builders)
	_log("select_builders_doubleclick", n >= want_sel and n > 0, "selected=%d of %d" % [n, n_build])
	await _shot("ui_02_engineers_selected")
	_log("place_power_hotkey_" + _hotkey(pdef), await _place(pdef), pdef)
	_log("speed_3x_button", await _click_button("3x"))
	var gen_ok := await _wait_until(func(): return _built(pdef), 60.0)
	_log("power_completed", gen_ok, pdef)

	# economy first (ORCH 2026-10-23): Human B/Machine cannot afford power + barracks from the start stock
	await _gather_salvage(gatherers, "1")
	var bcost: Dictionary = Content.building(bdef).cost
	var afford := await _wait_until(func(): return _w().can_afford(0, bcost) == "", 120.0)
	_log("afford_barracks", afford, "%s cost=%s stock=%s cr=%d" % [bdef, str(bcost), str(_w().factions[0].stock), int(_w().factions[0].credits)])

	n = await _select_units(builders)
	_log("reselect_builders", n >= want_sel and n > 0, "selected=%d" % n)
	_log("place_barracks_hotkey_" + _hotkey(bdef), await _place(bdef), bdef)
	var bar_ok := await _wait_until(func(): return _built(bdef), 60.0)
	_log("barracks_completed", bar_ok, bdef)
	await _shot("ui_03_barracks_built")
	if not bar_ok:
		return _finish()
	# builders that also gather (Human A/B) were pulled off the pile to build: send them back
	await _gather_salvage(gatherers, "2")
	var need := int(Content.production(inf_item).cost.get("salvage", 0))
	var sal_ok := await _wait_until(func(): return int(_w().factions[0].stock.salvage) >= need, 90.0)
	_log("salvage_for_squad", sal_ok, "salvage=%d need=%d" % [int(_w().factions[0].stock.salvage), need])

	var bar: Dictionary = _w().buildings_of(0, bdef)[0]
	await _click(_to_screen(bar.pos))
	await _wait(0.4)
	_log("select_barracks_click", _mv().selection.has(int(bar.id)))
	await _shot("ui_04_barracks_selected")
	var inf_before := _own_units_in(inf_units).size()
	var inf_name := String(Content.production(inf_item).name)
	_log("click_infantry_button", await _click_button(inf_name), inf_name)
	await _wait(0.3)
	_log("queue_has_item", _w().get_e(int(bar.id)) != null and _w().get_e(int(bar.id)).queue.size() > 0)
	var sq_ok := await _wait_until(func(): return _own_units_in(inf_units).size() >= inf_before + inf_units.size(), 60.0)
	_log("infantry_trained", sq_ok, "%s units=%d (before %d, +%d expected)" % [inf_item, _own_units_in(inf_units).size(), inf_before, inf_units.size()])
	await _wait(1.0)
	await _shot("ui_05_squad_trained")

	await _officer_flow(inf_units)
	var rifles := _own_units_in(inf_units)
	if rifles.size() > 0:
		_mv().speed = 0.0  # freeze the sim for the selection gesture (units are moving under the officer)
		var cen := Vector2.ZERO
		for r in rifles:
			cen += Vector2(r.pos)
		_mv().center_camera_on(cen / float(rifles.size()))  # what a player does: scroll to the squad
		await _wait(0.3)
		var lo2 := _to_screen(rifles[0].pos)
		var hi2 := lo2
		for r in rifles:
			var q := _to_screen(r.pos)
			lo2 = Vector2(minf(lo2.x, q.x), minf(lo2.y, q.y))
			hi2 = Vector2(maxf(hi2.x, q.x), maxf(hi2.y, q.y))
		await _drag(lo2 - Vector2(20, 28), hi2 + Vector2(20, 14))
		_mv().speed = 3.0
		await _wait(0.3)
		var sel := 0
		for id in _mv().selection:
			var e = _w().get_e(int(id))
			if e != null and inf_units.has(String(e.def)):
				sel += 1
		var want := mini(4, rifles.size())
		_log("select_squad_boxdrag", sel >= want, "selected=%d of %d" % [sel, rifles.size()])
		await _key(KEY_A)
		# ORCH: aim 8 tiles from the squad toward the map centre so the click stays on screen for every spawn
		var sc := Vector2.ZERO
		for r in rifles:
			sc += Vector2(r.pos)
		sc /= float(rifles.size())
		var goal := sc + (Vector2(48, 48) - sc).normalized() * 12.0
		await _click(_to_screen(goal))
		await _wait(0.2)  # fast units (Machine crawlers at 3x) can finish an 8-tile order within 1 s
		var am := 0
		for e in _own_units_in(inf_units):
			if String(e.order.type) == "attack_move":
				am += 1
		_log("attack_move_issued", am >= want, "attack_move_units=%d" % am)
		await _wait(3.0)
		await _shot("ui_06_attack_move")
	_finish()


## G2: train the faction's officer-role unit, assign the infantry to it, give a Secure point
## mission by map click, and check that the officer's reports reach the group card. Synthetic input.
func _officer_flow(inf_units: Array) -> void:
	var off_item := _role("officer")
	var prod := _producer_of(off_item)
	_log("g2_officer_producer", off_item != "" and not prod.is_empty(), "%s from %s" % [off_item, String(prod.get("def", "?"))])
	if off_item == "" or prod.is_empty():
		return
	var off_units := G3.item_units(off_item)
	await _click(_to_screen(prod.pos))
	await _wait(0.3)
	var need := int(Content.production(off_item).cost.get("salvage", 0))
	await _wait_until(func(): return int(_w().factions[0].stock.salvage) >= need, 60.0)
	var off_name := String(Content.production(off_item).name)
	_log("g2_click_officer_button", await _click_button(off_name), off_name)
	var off_ok := await _wait_until(func(): return _own_units_in(off_units).size() > 0, 60.0)
	_log("g2_officer_trained", off_ok)
	if not off_ok:
		return
	await _wait(1.0)
	var off: Dictionary = _own_units_in(off_units)[0]
	# wait until the officer has walked to the rally point near the squad, then box-select both
	await _wait_until(func(): return not bool(_w().get_e(int(off.id)).get("moving", false)), 20.0)
	var pts := [_to_screen(_w().get_e(int(off.id)).pos)]
	for r in _own_units_in(inf_units):
		pts.append(_to_screen(r.pos))
	var lo: Vector2 = pts[0]
	var hi: Vector2 = pts[0]
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	await _drag(lo - Vector2(24, 30), hi + Vector2(24, 18))
	await _wait(0.3)
	var kinds := {}
	for id in _mv().selection:
		var se = _w().get_e(int(id))
		if se != null:
			kinds[se.def] = int(kinds.get(se.def, 0)) + 1
	print("PLAYTEST-DBG selection ", kinds)
	var want_m := mini(4, _own_units_in(inf_units).size())
	_log("g2_select_squad_plus_officer", _mv().selection.has(int(off.id)) and _mv().selection.size() >= 1 + want_m, "selected=%d" % _mv().selection.size())
	_log("g2_click_assign_button", await _click_button("Assign"))
	await _wait(0.5)
	var g: Dictionary = Ops.group_led_by(_w(), int(off.id))
	_log("g2_group_formed", not g.is_empty() and (g.members as Array).size() >= want_m, "members=%d" % (0 if g.is_empty() else (g.members as Array).size()))
	await _click(_to_screen(_w().get_e(int(off.id)).pos))
	await _wait(0.3)
	_log("g2_click_secure_point", await _click_button("Secure point"))
	await _wait(0.3)
	var goal := Vector2(40.5, 40.5)  # toward the bridge
	await _click(_to_screen(goal))
	await _wait(1.0)
	g = Ops.group_led_by(_w(), int(off.id))
	var mtype := "" if g.is_empty() else String((g.mission as Dictionary).get("type", ""))
	_log("g2_mission_set_by_map_click", mtype == "secure_point", "mission=%s phase=%s" % [mtype, "" if g.is_empty() else String(g.phase)])
	var rep_ok := await _wait_until(func(): return not Ops.group_led_by(_w(), int(off.id)).is_empty() and (Ops.group_led_by(_w(), int(off.id)).history as Array).size() >= 3, 30.0)
	_log("g2_officer_reports", rep_ok, "reports=%d" % (0 if g.is_empty() else (Ops.group_led_by(_w(), int(off.id)).history as Array).size()))
	await _click(_to_screen(_w().get_e(int(off.id)).pos))
	await _wait(1.5)
	await _shot("ui_07_officer_mission")


func _finish() -> void:
	print("PLAYTEST RESULT pass=%d fail=%d" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
