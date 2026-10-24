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
const G3bData = preload("res://presentation/hud/g3b_data.gd")
const Fortify = preload("res://sim/systems/fortify.gd")  # G4b (UI4B) flow
const Transport = preload("res://sim/systems/transport.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const RenderSnapScript = preload("res://sim/render_snap.gd")

var main: Node
var shot_dir := ""
var stages_flow := false  # G3b: --ui-playtest-stages
var faction := ""     # --ui-playtest-faction ("" = leave the menu defaults: Human A vs Human A)
var g4b_flow := false  # G4b (UI4B): --ui-playtest-g4b (walls/gate, APC load/unload, mortar deploy)
var passed := 0
var failed := 0


func _ready() -> void:
	g4b_flow = OS.get_cmdline_user_args().has("--ui-playtest-g4b")
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
	if ob.selected != idx:
		print("PLAYTEST-DBG pick_option_miss %s idx=%d sel=%d click=%s pm_pos=%s pm_size=%s margins=%.0f/%.0f" % [node_name, idx, ob.selected, p, pm.position, pm.size, top, bottom])
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
## True when a click on e's screen point picks e itself (not a building sprite drawn over it).
func _pickable(e) -> bool:
	var hit = _mv().entity_at(Vector2(e.pos), true)
	return hit != null and int(hit.id) == int(e.id)


## A screen point the player can click on the map: inside the window, clear of the top bar and the
## bottom HUD panel (command card / minimap), so a synthetic click reaches the match view.
func _on_map(sp: Vector2) -> bool:
	var vs := get_viewport().get_visible_rect().size
	return sp.x > 40.0 and sp.x < vs.x - 40.0 and sp.y > 80.0 and sp.y < vs.y * 0.72


func _gather_salvage(gatherers: Array, tag: String) -> void:
	var n_gat := _own_units_in(gatherers).size()
	var n := await _select_units(gatherers)
	_log("select_gatherers_" + tag, n >= mini(4, n_gat) and n > 0, "selected=%d of %d" % [n, n_gat])
	var pile = null
	var best := 1e9
	var hqp: Vector2 = _hq().pos
	for e in _w().entities.values():
		if e.kind == "resource" and e.res == "salvage" and _w().is_visible(0, e.pos) and _pickable(e):
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
	if gathering == 0:
		var types := []
		for e in _own_units_in(gatherers):
			types.append(String(e.order.type))
		var hov = get_viewport().gui_get_hovered_control()
		print("PLAYTEST-DBG gather_miss pile=%s amt=%s screen=%s vp=%s hovered=%s orders=%s sel=%d" % [
			str(pile.pos), str(pile.get("amount")), str(_to_screen(pile.pos)), str(get_viewport().get_visible_rect().size),
			str(hov.get_path()) if hov != null else "none", str(types), _mv().selection.size()])
		print("PLAYTEST-DBG gather_miss2 placing=%s am_armed=%s" % [str(_mv().placing_def), str(_mv().attack_move_armed)])
	_log("right_click_gather_" + tag, gathering >= mini(4, n_gat) and gathering > 0, "gathering=%d" % gathering)
	if tag == "1":
		await _shot("ui_035_gathering")


func _run() -> void:
	await _wait(1.5)
	if faction != "":
		await _setup_menu()
	if stages_flow:
		await _setup_stages_menu()
	await _shot("ui_00_menu")
	_log("menu_start_button", await _click_button("START MATCH"))
	var started := await _wait_until(func(): return main.match_view != null and main.match_view.world != null, 10.0)
	_log("match_started", started)
	if not started:
		return _finish()
	await _wait(1.5)
	_log("player_faction", faction == "" or _fac() == faction, "faction=%s sides=%d" % [_fac(), _w().factions.size()])
	await _shot("ui_01_start")
	if g4b_flow:
		await _g4b_flow()
		return _finish()

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
	if stages_flow:
		await _stages_flow(builders)
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
		_mv().speed = 1.0  # issue + check at 1x: Machine crawlers at 3x can finish the order before the check
		await _key(KEY_A)
		# ORCH: aim 8 tiles from the squad toward the map centre so the click stays on screen for every spawn
		var sc := Vector2.ZERO
		for r in rifles:
			sc += Vector2(r.pos)
		sc /= float(rifles.size())
		var mc := Vector2(float(_w().map.w), float(_w().map.h)) * 0.5  # G3b: any map size (48,48 on River Crossing)
		var dir := (mc - sc).normalized()
		var goal := sc + dir * 12.0
		# keep the click on the map, not under the bottom HUD: shorter / rotated aims toward the centre
		for dist in [12.0, 9.0, 6.0]:
			var found := false
			for ang in [0.0, 0.6, -0.6, 1.2, -1.2]:
				var g: Vector2 = sc + dir.rotated(ang) * float(dist)
				if _on_map(_to_screen(g)):
					goal = g
					found = true
					break
			if found:
				break
		await _click(_to_screen(goal))
		await _wait(0.2)  # fast units (Machine crawlers at 3x) can finish an 8-tile order within 1 s
		var am := 0
		for e in _own_units_in(inf_units):
			if String(e.order.type) == "attack_move":
				am += 1
		if am < want:
			var dbg := []
			for e in _own_units_in(inf_units):
				dbg.append("%s pos=%s order=%s moving=%s" % [e.def, str(e.pos), str(e.order), str(e.get("moving"))])
			print("PLAYTEST-DBG am_miss goal=%s screen=%s units=%s" % [str(goal), str(_to_screen(goal)), str(dbg)])
		_log("attack_move_issued", am >= want, "attack_move_units=%d" % am)
		_mv().speed = 3.0
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
	var ab := _find_button(get_tree().root, "Assign")
	if ab != null:
		print("PLAYTEST-DBG assign_btn text=%s disabled=%s rect=%s tip=%s" % [ab.text, ab.disabled, ab.get_global_rect(), ab.tooltip_text.get_slice("\n", 0)])
	_log("g2_click_assign_button", await _click_button("Assign"))
	await _wait(0.5)
	if ab != null:
		var hov := get_viewport().gui_get_hovered_control()
		print("PLAYTEST-DBG after_assign hovered=%s groups=%d" % ["null" if hov == null else String(hov.get_path()), (Ops.state(_w()).groups as Dictionary).size()])
	var g: Dictionary = Ops.group_led_by(_w(), int(off.id))
	_log("g2_group_formed", not g.is_empty() and (g.members as Array).size() >= want_m, "members=%d" % (0 if g.is_empty() else (g.members as Array).size()))
	await _click(_to_screen(_w().get_e(int(off.id)).pos))
	await _wait(0.3)
	_log("g2_click_secure_point", await _click_button("Secure point"))
	await _wait(0.3)
	var goal := Vector2(40.5, 40.5)  # toward the bridge
	if _w().map.w != 96:  # G3b: bigger maps: 10 tiles from the officer toward the map centre (stays on screen)
		var op: Vector2 = _w().get_e(int(off.id)).pos
		goal = op + (Vector2(float(_w().map.w), float(_w().map.h)) * 0.5 - op).normalized() * 10.0
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


# ------------------------------------------------------------ G3b stages flow (UI4)
## Menu by real clicks: Industrial Heartland (River Crossing if it is missing), slot 2 opened as
## AI, stages 7 / 8 / 9 for slots 0 / 1 / 2, Standard advancement.
func _setup_stages_menu() -> void:
	var menu = get_tree().root.find_child("MapOption", true, false) as OptionButton
	var want := -1
	var fallback := 0
	if menu != null:
		for i in menu.item_count:
			var t := menu.get_item_text(i)
			if t.begins_with("Industrial Heartland") and not menu.is_item_disabled(i):
				want = i
			if t.begins_with("River Crossing"):
				fallback = i
	var picked := want if want >= 0 else fallback
	_log("g3b_map_pick_click", menu != null and await _pick_option("MapOption", picked),
		"%s%s" % ["" if menu == null else menu.get_item_text(picked), "" if want >= 0 else " (Industrial Heartland missing: fallback)"])
	_log("g3b_slot2_open_ai_click", await _pick_option("Slot2Kind", 0))
	for i in 3:
		var ob = get_tree().root.find_child("Slot%dStage" % i, true, false) as OptionButton
		var idx := -1
		if ob != null:
			for k in ob.item_count:
				if ob.get_item_text(k).begins_with("Stage %d " % (7 + i)):
					idx = k
		_log("g3b_slot%d_stage%d_click" % [i, 7 + i], idx >= 0 and await _pick_option("Slot%dStage" % i, idx),
			"items=%d" % (0 if ob == null else ob.item_count))
	await _wait(0.3)
	var summary := ""
	for l in get_tree().root.find_children("*", "Label", true, false):
		if String(l.text).contains("Stages "):
			summary = String(l.text)
	_log("g3b_summary_shows_stages", summary.contains("Stages 7/8/9"), summary.get_slice("
", 0))


func _stages_flow(builders: Array) -> void:
	var w := _w()
	_log("g3b_match_stages", int(w.factions[0].stage) == 7 and w.factions.size() >= 3 and int(w.factions[2].stage) == 9,
		"map=%s stages=%s" % [String(w.map.get("id", "?")), str(w.factions.values().map(func(f): return int(f.stage)))])
	var hud = main.get("hud")
	var sp = hud.g3b_stage if hud != null else null
	_log("g3b_stage_panel_visible", sp != null and sp.panel.is_visible_in_tree(), "" if sp == null else sp.title.text)
	var rdef := ""
	for b in Content.buildable_for(_fac()):
		if bool(Content.building(String(b)).get("research", false)):
			rdef = String(b)
			break
	_log("g3b_research_building_def", rdef != "", rdef)
	if rdef == "":
		return
	var cost: Dictionary = Content.building(rdef).cost
	_log("g3b_afford_research_building", await _wait_until(func(): return _w().can_afford(0, cost) == "", 120.0), str(cost))
	var n := await _select_units(builders)
	_log("g3b_select_builders", n > 0, "selected=%d" % n)
	_log("g3b_place_research_hotkey_" + _hotkey(rdef), await _place(rdef), rdef)
	var built := await _wait_until(func(): return _built(rdef), 90.0)
	_log("g3b_research_building_completed", built, rdef)
	if not built:
		return
	var rb: Dictionary = _w().buildings_of(0, rdef)[0]
	await _click(_to_screen(rb.pos))
	await _wait(0.5)
	_log("g3b_select_research_building", _mv().selection.has(int(rb.id)))
	# first project the side can start now (Stage 7: a 7->8 project)
	var pid := ""
	for p in G3bData.project_ids_sorted():
		var pd: Dictionary = G3bData.research_projects()[p]
		if int(pd.get("stage_min", 7)) <= int(_w().factions[0].stage):
			pid = String(p)
			break
	_log("g3b_research_project_known", pid != "", pid)
	if pid == "":
		return
	var pcost: Dictionary = G3bData.research_projects()[pid].get("cost", {})
	await _wait_until(func(): return _w().can_afford(0, pcost) == "", 90.0)
	var btn = get_tree().root.find_child("Research_" + pid, true, false) as Button
	_log("g3b_research_button_enabled", btn != null and not btn.disabled, "" if btn == null else btn.tooltip_text.replace("
", " | "))
	await _shot("ui_g3b_research_card")
	if btn != null:
		await _click(btn.get_global_rect().get_center())
	var started := await _wait_until(func(): return String(_w().factions[0].research.get("active", "")) == pid, 3.0)
	_log("g3b_research_started_by_click", started, "active=%s" % String(_w().factions[0].research.get("active", "")))
	var prog := await _wait_until(func(): return float(_w().factions[0].research.get("progress", 0.0)) > 0.0, 10.0)
	_log("g3b_research_progress", prog, "progress=%s" % str(_w().factions[0].research.get("progress", 0.0)))
	await _wait(0.5)
	_log("g3b_stage_panel_gates", sp != null and sp.last_report.size() > 0 and sp.gate_box.get_child_count() == sp.last_report.size(),
		"" if sp == null else "gates=%d rows=%d advance_disabled=%s" % [sp.last_report.size(), sp.gate_box.get_child_count(), str(sp.advance_btn.disabled)])
	_log("g3b_advance_disabled_until_gates", sp != null and sp.advance_btn.disabled)
	await _shot("ui_g3b_stage_panel")


func _finish() -> void:
	print("PLAYTEST RESULT pass=%d fail=%d" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


# ------------------------------------------------------------ G4b flow (UI4B): --ui-playtest-g4b
## Human A (menu defaults, Stage 8). A harness grant tops up the stock once (the flow tests the
## G4b UI, not the economy). Then, all by synthetic input: build barracks + motor pool, drag a
## 6-segment wall, place a gate at its end, lock + unlock it from the gate panel, train an APC and
## a squad, right-click the APC with the squad (load), unload one rider from the cargo strip,
## Unload at point for the rest, train a mortar and press Deploy.
func _g4b_flow() -> void:
	_mv().join_sim()
	var f: Dictionary = _w().factions[0]
	f.credits = int(f.credits) + 8000
	for r in ["salvage", "ore"]:
		f.stock[r] = int(f.stock.get(r, 0)) + 5000
	_log("g4b_harness_grant", true, "credits=%d stock=%s" % [int(f.credits), str(f.stock)])
	# ORCH CR (UI4B, content.gd): G4 production "facility" is not merged into the building's
	# produces list yet; patch the loaded content in memory only while that merge is missing.
	for item in ["a_apc", "a_mortar", "a_combat_engineer"]:
		var fac := String(Content.production(item).get("facility", ""))
		var pl: Array = Content.building(fac).get("produces", [])
		if fac != "" and not pl.has(item):
			pl.append(item)
			print("PLAYTEST-DBG facility_patch %s -> %s (content.gd merge missing)" % [item, fac])
	_log("speed_3x_button", await _click_button("3x"))
	var builders := _defs_with("can_build")
	for role in ["power", "barracks", "factory"]:
		var d := _role(role)
		var n := await _select_units(builders)
		_log("g4b_select_builders_" + role, n > 0, "selected=%d" % n)
		_log("g4b_place_" + role, await _place(d), d)
		_log("g4b_built_" + role, await _wait_until(func(): return _built(d), 90.0), d)
	await _g4b_walls(builders)
	await _g4b_transport()
	await _g4b_mortar()
	await _g4b_mine()


## A legal on-screen 6-cell line near the HQ for def (pure preview on the joined world).
func _g4b_line(def_id: String) -> Array:
	var c: Vector2i = _hq().cell
	for r in range(5, 14):
		for dir in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			for off in [Vector2i(0, r), Vector2i(r, 0), Vector2i(0, -r), Vector2i(-r, 0), Vector2i(r, r), Vector2i(-r, -r)]:
				var a: Vector2i = c + off
				var b: Vector2i = a + dir * 5
				var gate: Vector2i = b + dir
				var pv: Dictionary = Fortify.preview_line(_w(), 0, def_id, a, b)
				if (pv.legal as Array).size() != 6 or Construction.placement_error(_w(), 0, _role("gate"), gate) != "":
					continue
				var ok := true
				for q in [a, b, gate]:
					if not _on_map(_to_screen(Vector2(q) + Vector2(0.5, 0.5))):
						ok = false
				if ok:
					return [a, b, gate]
	return []


func _g4b_walls(builders: Array) -> void:
	var wdef := _role("wall")
	var gdef := _role("gate")
	_log("g4b_wall_roles", wdef != "" and gdef != "", "wall=%s gate=%s" % [wdef, gdef])
	var n := await _select_units(builders)
	_log("g4b_wall_select_builders", n > 0, "selected=%d" % n)
	var line := _g4b_line(wdef)
	_log("g4b_wall_line_found", not line.is_empty(), str(line))
	if line.is_empty():
		return
	var a: Vector2i = line[0]
	var b: Vector2i = line[1]
	var before := _w().buildings_of(0, wdef).size()
	var hk := _hotkey(wdef)
	await _key(OS.find_keycode_from_string(hk))
	await _wait(0.3)
	_log("g4b_wall_tool_armed_hotkey_" + hk, _mv().placing_def == wdef, _mv().placing_def)
	var sa := _to_screen(Vector2(a) + Vector2(0.5, 0.5))
	var sb := _to_screen(Vector2(b) + Vector2(0.5, 0.5))
	await _move(sa)
	await _button(sa, MOUSE_BUTTON_LEFT, true)
	for i in 6:
		await _move(sa.lerp(sb, float(i + 1) / 6.0))
	await _wait(0.4)
	var pv: Dictionary = _mv().g4b.preview
	_log("g4b_wall_drag_preview", (pv.get("legal", []) as Array).size() == 6, "legal=%d cells=%d" % [(pv.get("legal", []) as Array).size(), (pv.get("cells", []) as Array).size()])
	await _shot("ui_g4b_01_wall_drag")
	await _button(sb, MOUSE_BUTTON_LEFT, false)
	await _wait(0.5)
	_log("g4b_build_line_issued", String(_mv().g4b.last_line.get("type", "")) == "build_line", str(_mv().g4b.last_line))
	var walls_ok := await _wait_until(func(): return _built_count(wdef) >= before + 6, 120.0)
	_log("g4b_six_walls_built", walls_ok, "walls=%d" % _w().buildings_of(0, wdef).size())
	# gate at the end of the line (single-building placement)
	var gc: Vector2i = line[2]
	await _select_units(builders)
	await _key(OS.find_keycode_from_string(_hotkey(gdef)))
	await _wait(0.3)
	await _move(_to_screen(Vector2(gc) + Vector2(0.5, 0.5)))
	await _click(_to_screen(Vector2(gc) + Vector2(0.5, 0.5)))
	await _wait(0.5)
	_log("g4b_gate_placed", _w().buildings_of(0, gdef).size() > 0, gdef)
	var gate_ok := await _wait_until(func(): return _built(gdef), 90.0)
	_log("g4b_gate_built", gate_ok)
	if not gate_ok:
		return
	var g: Dictionary = _w().buildings_of(0, gdef)[0]
	await _wait(1.0)
	await _shot("ui_g4b_02_wall_gate")
	await _click(_to_screen(g.pos))
	await _wait(0.5)
	_log("g4b_select_gate", _mv().selection.has(int(g.id)))
	_log("g4b_click_lock", await _click_button("Lock gate"))
	_log("g4b_gate_locked", await _wait_until(func(): return bool(_w().get_e(int(g.id)).get("locked", false)), 5.0))
	await _wait(0.4)
	_log("g4b_gate_art_closed", await _wait_until(func(): return not _g4b_gate_art(int(g.id), gdef).ends_with("_open"), 3.0), _g4b_gate_art(int(g.id), gdef))
	await _shot("ui_g4b_03_gate_locked")
	_log("g4b_click_unlock", await _click_button("Unlock gate"))
	_log("g4b_gate_unlocked", await _wait_until(func(): return not bool(_w().get_e(int(g.id)).get("locked", true)), 5.0))
	# UI4B-2: an unlocked gate draws its conn_<m>_open art (batch_art fort state, ART-F manifest)
	_log("g4b_gate_art_open", await _wait_until(func(): return _g4b_gate_art(int(g.id), gdef).ends_with("_open"), 3.0), _g4b_gate_art(int(g.id), gdef))
	await _wait(0.4)
	await _shot("ui_g4b_03b_gate_open")


## Fort art state the entity layer resolves for building id from the render snapshot ("" = none).
func _g4b_gate_art(id: int, def_id: String) -> String:
	var st = (_mv().snap.get("statics", {}) as Dictionary).get(id)
	var b: Dictionary = ArtCatalog.manifest().get("buildings", {}).get(def_id, {})
	if st == null or b.is_empty():
		return ""
	return String(_mv().entity_layer.art._fort_state(b.states, st))


func _g4b_alert(sub: String) -> bool:
	var hud = main.get("hud")
	if hud == null:
		return false
	for a in hud._alerts:
		if String(a.text).contains(sub):
			return true
	return false


func _g4b_snap_flag(id: int, flag: int) -> bool:
	var sn: Dictionary = _mv().snap
	var i := (sn.get("ids", PackedInt32Array()) as PackedInt32Array).find(id)
	return i >= 0 and ((sn.flags as PackedInt32Array)[i] & flag) != 0


func _built_count(def_id: String) -> int:
	var k := 0
	for e in _w().buildings_of(0, def_id):
		if bool(e.built):
			k += 1
	return k


## Select a producer building by click and press the production card button for item.
func _train(item: String) -> Array:
	var prod := _producer_of(item)
	var units := G3.item_units(item)
	if prod.is_empty():
		_log("g4b_producer_" + item, false)
		return []
	var before := _own_units_in(units).size()
	await _click(_to_screen(prod.pos))
	await _wait(0.4)
	var nm := String(Content.production(item).name)
	_log("g4b_click_train_" + item, await _click_button(nm), nm)
	var ok := await _wait_until(func(): return _own_units_in(units).size() > before, 90.0)
	_log("g4b_trained_" + item, ok, "%s=%d" % [item, _own_units_in(units).size()])
	return _own_units_in(units) if ok else []


func _g4b_transport() -> void:
	var tdef := _role("transport")
	var apcs := await _train(tdef)
	var inf_units := G3.item_units(_role("infantry"))
	var squad := await _train(_role("infantry"))
	if apcs.is_empty() or squad.is_empty():
		return
	await _wait(2.0)
	var apc: Dictionary = apcs[0]
	_mv().center_camera_on(apc.pos)
	await _wait(0.4)
	var n := await _select_units(inf_units)
	_log("g4b_select_squad", n > 0, "selected=%d" % n)
	await _click(_to_screen(_w().get_e(int(apc.id)).pos), MOUSE_BUTTON_RIGHT)
	await _wait(0.3)
	var loaded := await _wait_until(func(): return Transport.used_slots(_w().get_e(int(apc.id))) >= mini(n, 4), 40.0)
	var cargo: Array = Transport.cargo_ids(_w().get_e(int(apc.id)))
	_log("g4b_right_click_load", loaded, "cargo=%s" % str(cargo))
	if not loaded:
		return
	await _wait_until(func(): return Transport.cargo_ids(_w().get_e(int(apc.id))).size() >= n, 10.0)
	cargo = Transport.cargo_ids(_w().get_e(int(apc.id)))
	await _click(_to_screen(_w().get_e(int(apc.id)).pos))
	await _wait(0.6)
	_log("g4b_select_apc", _mv().selection.has(int(apc.id)))
	var hud = main.get("hud")
	var strip = hud.g4b_cmd.strip if hud != null else null
	_log("g4b_cargo_strip_visible", strip != null and strip.is_visible_in_tree() and hud.g4b_cmd.strip_box.get_child_count() >= cargo.size(),
		"" if strip == null else hud.g4b_cmd.strip_title.text)
	await _shot("ui_g4b_04_apc_loaded")
	_log("g4b_cargo_badge_drawn", _mv().g4b_over.badges_drawn > 0, "badges=%d" % _mv().g4b_over.badges_drawn)
	var first := int(cargo[0])
	var cb = get_tree().root.find_child("G4bCargo_%d" % first, true, false) as Button
	_log("g4b_click_cargo_slot", cb != null)
	if cb != null:
		await _click(cb.get_global_rect().get_center())
	_log("g4b_slot_unloaded_one", await _wait_until(func(): return _w().entities.has(first), 15.0), "id=%d" % first)
	await _wait(0.5)
	_log("g4b_click_unload_at_point", await _click_button("Unload at point"))
	await _wait(0.3)
	var ap: Vector2 = _w().get_e(int(apc.id)).pos
	var mc := Vector2(float(_w().map.w), float(_w().map.h)) * 0.5
	var goal := ap + (mc - ap).normalized() * 6.0
	for ang in [0.0, 0.8, -0.8, 1.6, -1.6, 3.14]:
		var g2p: Vector2 = ap + (mc - ap).normalized().rotated(ang) * 6.0
		if _on_map(_to_screen(g2p)) and _mv().entity_at(g2p, true) == null:
			goal = g2p
			break
	await _click(_to_screen(goal))
	await _wait(0.3)
	var unl := await _wait_until(func(): return Transport.used_slots(_w().get_e(int(apc.id))) == 0, 60.0)
	var near := 0
	for id in cargo:
		var u = _w().get_e(int(id))
		if u != null and Vector2(u.pos).distance_to(goal) < 4.0:
			near += 1
	_log("g4b_unload_at_point", unl and near >= cargo.size() - 1, "empty=%s near_goal=%d of %d goal=%s" % [str(unl), near, cargo.size() - 1, str(goal)])
	await _wait(1.0)
	await _shot("ui_g4b_05_unloaded")


func _g4b_mortar() -> void:
	var mdef := _role("mortar")
	_log("g4b_mortar_role", mdef != "", mdef)
	if mdef == "":
		return
	var ms := await _train(mdef)
	if ms.is_empty():
		return
	await _wait(1.5)
	var m: Dictionary = ms[0]
	_mv().center_camera_on(_w().get_e(int(m.id)).pos)
	await _wait(0.4)
	await _click(_to_screen(_w().get_e(int(m.id)).pos))
	await _wait(0.5)
	_log("g4b_select_mortar", _mv().selection.has(int(m.id)))
	_log("g4b_click_deploy", await _click_button("Deploy"))
	var dep := await _wait_until(func(): return int(_w().get_e(int(m.id)).get("setup_left", 0)) > 0 or bool(_w().get_e(int(m.id)).get("deployed", false)), 5.0)
	_log("g4b_mortar_deploying", dep, "setup_left=%s deployed=%s" % [str(_w().get_e(int(m.id)).get("setup_left")), str(_w().get_e(int(m.id)).get("deployed"))])
	var done := await _wait_until(func(): return bool(_w().get_e(int(m.id)).get("deployed", false)), 20.0)
	_log("g4b_mortar_deployed", done)
	await _wait(0.6)
	# UI4B-2: render snapshot carries the deployed flag (mortar set-up frame) + the HUD alert
	_log("g4b_snap_flag_deployed", await _wait_until(func(): return _g4b_snap_flag(int(m.id), RenderSnapScript.FLAG_DEPLOYED), 3.0))
	_log("g4b_alert_deployed", _g4b_alert("deployed"))
	_log("g4b_pack_button_shown", _find_button(get_tree().root, "Pack") != null)
	await _shot("ui_g4b_06_mortar_deployed")


## Combat engineer: Lay mine button -> click a cell -> own mine marker drawn by g4b_overlay.
func _g4b_mine() -> void:
	var edef := _role("engineer_combat")
	if edef == "":
		_log("g4b_engineer_role", false)
		return
	var es := await _train(edef)
	if es.is_empty():
		return
	await _wait(1.5)
	var e: Dictionary = _w().get_e(int(es[0].id))
	_mv().center_camera_on(e.pos)
	await _wait(0.4)
	await _click(_to_screen(_w().get_e(int(e.id)).pos))
	await _wait(0.5)
	_log("g4b_select_engineer", _mv().selection.has(int(e.id)))
	var c0 := Vector2i(Vector2(_w().get_e(int(e.id)).pos).floor())
	var cell := Vector2i(-1, -1)
	for off in [Vector2i(3, 0), Vector2i(0, 3), Vector2i(-3, 0), Vector2i(0, -3), Vector2i(3, 3), Vector2i(-3, -3)]:
		var q: Vector2i = c0 + off
		if _w().in_bounds(q):
			if _on_map(_to_screen(Vector2(q) + Vector2(0.5, 0.5))) and G4bMech.mine_error(_w(), 0, q) == "":
				cell = q
				break
	_log("g4b_mine_cell_found", cell.x >= 0, str(cell))
	if cell.x < 0:
		return
	_log("g4b_click_lay_mine", await _click_button("Lay mine"))
	await _wait(0.3)
	await _click(_to_screen(Vector2(cell) + Vector2(0.5, 0.5)))
	var laid := await _wait_until(func(): return _own_mines() > 0, 30.0)
	_log("g4b_mine_laid", laid, "mines=%d" % _own_mines())
	await _wait(0.8)
	_log("g4b_alert_mine_laid", _g4b_alert("Mine laid"))
	_log("g4b_mine_marker_drawn", _mv().g4b_over.mines_drawn > 0, "markers=%d" % _mv().g4b_over.mines_drawn)
	await _shot("ui_g4b_07_mine")


func _own_mines() -> int:
	var k := 0
	for x in _w().entities.values():
		if String(x.kind) == "mine" and int(x.owner) == 0:
			k += 1
	return k
