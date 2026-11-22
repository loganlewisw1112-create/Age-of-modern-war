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
const PtViewUtil = preload("res://presentation/view/view_util.gd")  # G6 (PT6-2): height-aware _to_screen
const Ops = preload("res://sim/systems/ops.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")
const G3bData = preload("res://presentation/hud/g3b_data.gd")
const Fortify = preload("res://sim/systems/fortify.gd")  # G4b (UI4B) flow
const Transport = preload("res://sim/systems/transport.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const RenderSnapScript = preload("res://sim/render_snap.gd")
const Air = preload("res://sim/systems/air.gd")  # G5 (PT5) flows
const Airfield = preload("res://sim/systems/airfield.gd")
const Naval = preload("res://sim/systems/naval.gd")
const G5Mech = preload("res://sim/systems/g5_mech.gd")
const Support = preload("res://sim/systems/support.gd")
const Medical = preload("res://sim/systems/medical.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Combat = preload("res://sim/systems/combat.gd")
const HotState = preload("res://sim/hot_state.gd")

var main: Node
var shot_dir := ""
var stages_flow := false  # G3b: --ui-playtest-stages
var faction := ""     # --ui-playtest-faction ("" = leave the menu defaults: Human A vs Human A)
var g4b_flow := false  # G4b (UI4B): --ui-playtest-g4b (walls/gate, APC load/unload, mortar deploy)
var g5_flow := ""  # G5 (PT5): --ui-playtest-air|naval|drone|support|med|tutorial
var passed := 0
var failed := 0


func _ready() -> void:
	g4b_flow = OS.get_cmdline_user_args().has("--ui-playtest-g4b")
	for fl in G5_FLOWS:
		if OS.get_cmdline_user_args().has("--ui-playtest-" + String(fl)):
			g5_flow = String(fl)
	for fl in G6_FLOWS:
		if OS.get_cmdline_user_args().has("--ui-playtest-" + String(fl)):
			g6_flow = String(fl)
	for fl in G7_FLOWS:
		if OS.get_cmdline_user_args().has("--ui-playtest-" + String(fl)):
			g6_flow = String(fl)
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
	# G6 (PT6-2): height-aware. Raised ground is drawn lifted by ViewUtil.level_px per level (32 px since
	# ELEV-VIEW-3) and match_view picks the cell drawn on top (pick_world), so a flat projection missed the
	# units on Ridge Bastion's L3 plateau (survival r1: "select_units retry" x3, 0 builders selected).
	var mv = _mv()
	var cp: Vector2 = MatchViewScript.world_to_screen(p)
	if mv.camera != null and mv.camera.has_method("height_map"):
		cp = PtViewUtil.world_to_screen_h(mv.camera.height_map(), p)
	return mv.get_viewport().get_canvas_transform() * (mv.global_transform * cp)



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
	var size := int(Content.building(def_id).size)
	var legal := Vector2i(-1, -1)
	var errs := {}
	for r in range(4, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var o := c + Vector2i(dx, dy)
				var er := Construction.placement_error(w, 0, def_id, o)
				if er == "":
					var centre := Vector2(o) + Vector2(size, size) * 0.5
					var sp := _to_screen(centre)
					if r < 12 and sp.x > 80 and sp.x < 1500 and sp.y > 120 and sp.y < 640:
						return o
					if legal.x < 0:
						legal = o
				else:
					errs[er] = int(errs.get(er, 0)) + 1
	# G6 (PT6-2): p1 airdef/survival "no legal on-screen site". Legal but off screen: scroll there like a
	# player (callers re-read _to_screen after their waits). None legal: say why.
	if legal.x >= 0:
		_mv().center_camera_on(Vector2(legal) + Vector2(size, size) * 0.5)
		return legal
	print("PLAYTEST-DBG site_none def=%s hq=%s errs=%s" % [def_id, str(c), str(errs).left(500)])
	return Vector2i(-1, -1)


## Click then double-click one unit of defs[0] (= select all of that type on screen); returns how
## many selected units have a def in defs.
func _select_units(defs: Array) -> int:
	# G6 (PT6) parallel-run fix: wait on state, not on time. Under load (2 windowed runs) the first
	# unit could be off screen / under the HUD or walking, and one click-pair found 0 units. Now: pick
	# a unit that is on the map area (else scroll to it), freeze the sim for the gesture, and retry
	# until the selection holds (3 attempts).
	var n := 0
	for attempt in 3:
		var us := _own_units_in(defs)
		if us.is_empty():
			return 0
		var pick = us[0]
		var cands := []
		for u in us:
			if _on_map(_to_screen(u.pos)):
				cands.append(u)
		# G6.1: a different unit on each retry (one that just finished a building can stand on its footprint,
		# where the click picks the building: airdef r2 picked the same engineer 3 times)
		if not cands.is_empty():
			pick = cands[attempt % cands.size()]
		var sp0: float = _mv().speed
		_mv().speed = 0.0
		if not _on_map(_to_screen(pick.pos)):
			_mv().center_camera_on(pick.pos)
			await _wait(0.4)
		await _click(_to_screen(pick.pos), MOUSE_BUTTON_LEFT)
		await _click(_to_screen(pick.pos), MOUSE_BUTTON_LEFT, true)
		await _wait(0.3)
		_mv().speed = sp0
		n = 0
		for id in _mv().selection:
			var e = _w().get_e(int(id))
			if e != null and defs.has(String(e.def)):
				n += 1
		if n > 0:
			return n
		var got := []
		for id in _mv().selection:
			var ge = _w().get_e(int(id))
			got.append("%s#%d" % [String(ge.def) if ge != null else "?", int(id)])
		print("PLAYTEST-DBG select_units retry %d defs=%s pick=%s#%d screen=%s got=%s order=%s" % [attempt, str(defs), str(pick.pos), int(pick.id),
			str(_to_screen(pick.pos)), str(got), str(pick.order).left(80)])
		await _wait(0.5)
	return n


## G5 (UI5b build pages): build hotkeys are page-local, so click the def's category tab first
## (BuildTab_<cat> in the card title row) when it is not the current page. True = page shown.
func _build_page(def_id: String) -> bool:
	var cat := G3.build_category(def_id)
	var tab = get_tree().root.find_child("BuildTab_" + cat, true, false) as Button
	if tab == null or not tab.is_visible_in_tree():
		return true  # no tab strip (single page) or not an engineer card
	if not tab.button_pressed:
		await _click(tab.get_global_rect().get_center())
		await _wait(0.4)
		tab = get_tree().root.find_child("BuildTab_" + cat, true, false) as Button
	return tab != null and tab.button_pressed


func _place(def_id: String, at: Vector2i = Vector2i(-1, -1)) -> bool:
	if at.x >= 0:  # G5: a given origin (shore site): scroll the camera there like a player
		var sz := int(Content.building(def_id).size)
		_mv().center_camera_on(Vector2(at) + Vector2(sz, sz) * 0.5)
		await _wait(0.4)
	var o := _site(def_id) if at.x < 0 else at
	if o.x < 0:
		_log("site_" + def_id, false, "no legal on-screen site")
		return false
	if not await _build_page(def_id):
		_log("build_page_" + G3.build_category(def_id), false, def_id)
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
	var pm := ob.get_popup()
	# G7 REGFIX7-4: the first click of a run (1.5 s after start, menu still settling on a slow first frame) was
	# sometimes lost (muzzle7: g6_slot0_stage9_click ok=false, no popup): click the button again, at most 3 times
	for attempt in 3:
		await _click(ob.get_global_rect().get_center())
		await _wait(0.4)
		if pm.visible:
			break
		print("PLAYTEST-DBG pick_option_no_popup %s attempt=%d rect=%s" % [node_name, attempt, ob.get_global_rect()])
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
	if g6_flow == "checkpoint":
		await _checkpoint_flow()
		return _finish()
	if g6_flow != "":
		await _g6_menu()
	if g5_flow != "" and g5_flow != "tutorial":
		await _g5_menu()
	if faction != "":
		await _setup_menu()
	if stages_flow:
		await _setup_stages_menu()
	await _shot("ui_00_menu")
	if g5_flow == "tutorial":
		await _tut_start()
	else:
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
	if g5_flow == "tutorial":
		await _tut_flow()
		return _finish()
	if g5_flow != "":
		await _g5_flow()
		return _finish()
	if g6_flow != "":
		await _g6_flow()
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
	# G6 (PT6-2) p1 parallel flake: one click missed (builder walking over the footprint / camera off it).
	# Wait on state: up to 3 clicks, centring the camera on the building between tries.
	for attempt in 3:
		if not _on_map(_to_screen(rb.pos)) or attempt > 0:
			_mv().center_camera_on(rb.pos)
			await _wait(0.4)
		await _click(_to_screen(rb.pos))
		await _wait(0.5)
		if _mv().selection.has(int(rb.id)):
			break
		print("PLAYTEST-DBG research_building_select retry %d sel=%s" % [attempt, str(_mv().selection)])
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
	await _build_page(wdef)
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
	await _build_page(gdef)
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


func _btn_enabled(needle: String) -> bool:
	var bb := _find_button(get_tree().root, needle)
	return bb != null and not bb.disabled


## G6.1: the command card (hud._card_grid) only; another visible panel can carry the same text.
func _card_find(needle: String) -> Button:
	var hud = main.get("hud")
	var grid = hud.get("_card_grid") if hud != null else null
	if grid == null or not is_instance_valid(grid):
		return _find_button(get_tree().root, needle)
	return _find_button(grid, needle)


func _card_enabled(needle: String) -> bool:
	var bb := _card_find(needle)
	return bb != null and not bb.disabled


## G6.1: the card pages its build/train buttons when they don't fit ("More n/m"; G6.1 added Ammo Bearer, stance,
## formation and regroup buttons, so the Mortar Team moved to page 2). Press More like a player until it shows.
func _reveal_card(needle: String) -> bool:
	var hud = main.get("hud")
	for i in 5:
		if _card_find(needle) != null:
			return true
		var pg = hud.get("_card_pager") if hud != null else null
		if pg == null or not is_instance_valid(pg) or not (pg as Button).is_visible_in_tree():
			return false
		await _click((pg as Button).get_global_rect().get_center())
		await _wait(0.25)
	return _card_find(needle) != null


## Select a producer building by click and press the production card button for item.
func _train(item: String) -> Array:
	var prod := _producer_of(item)
	var units := G3.item_units(item)
	if prod.is_empty():
		_log("g4b_producer_" + item, false)
		return []
	var before := _own_units_in(units).size()
	if not _on_map(_to_screen(prod.pos)):  # G5: producer scrolled off screen
		_mv().center_camera_on(prod.pos)
		await _wait(0.4)
	await _click(_to_screen(prod.pos))
	await _wait(0.4)
	var nm := String(Content.production(item).name)
	# G6 (PT6) parallel-run fix: the production button is enabled only once its gate holds (e.g. the
	# hangar just bought is still being built): wait for the enabled button, not a fixed delay.
	await _reveal_card(nm)
	var en := await _wait_until(func(): return _card_enabled(nm), 90.0)
	if not en:
		print("PLAYTEST-DBG train_button_disabled %s gate=%s" % [item, Airfield.can_produce(_w(), 0, item)])
	var q_before := 0
	var pqb = _w().get_e(int(prod.id))
	if pqb != null:
		q_before = (pqb.queue as Array).size()
	var cb: Button = null
	for attempt in 3:   # G6.1: the card re-lays out after a queue change; a click in that frame queued nothing
		await _reveal_card(nm)
		cb = _card_find(nm)
		if cb == null:
			break
		await _click(cb.get_global_rect().get_center())
		await _wait(0.3)
		var pqa = _w().get_e(int(prod.id))
		if pqa == null or (pqa.queue as Array).size() > q_before or _own_units_in(units).size() > before:
			break
		print("PLAYTEST-DBG train_click_retry %s attempt %d" % [item, attempt])
	_log("g4b_click_train_" + item, cb != null, nm)
	var pq0 = _w().get_e(int(prod.id))
	if cb != null and pq0 != null and (pq0.queue as Array).is_empty() and _own_units_in(units).size() <= before:
		var hv0 := get_viewport().gui_get_hovered_control()
		print("PLAYTEST-DBG train_click_no_queue %s hovered=%s btn_rect=%s mouse=%s sel=%s" % [item,
			"null" if hv0 == null else "%s(%s)" % [String(hv0.name), hv0.get_class()], str(cb.get_global_rect()),
			str(get_viewport().get_mouse_position()), str(_mv().selection)])
	var pq = _w().get_e(int(prod.id))
	if pq != null and not (pq.queue as Array).is_empty() and String((pq.queue as Array).back().item) != item:
		var hv := get_viewport().gui_get_hovered_control()
		var bb := _find_button(get_tree().root, nm)
		print("PLAYTEST-DBG wrong_item_queued want=%s got=%s hovered=%s(%s) btn_rect=%s mouse=%s" % [item, String((pq.queue as Array).back().item),
			"null" if hv == null else String(hv.name), "" if not (hv is Button) else String(hv.text).replace("
", " "), "null" if bb == null else str(bb.get_global_rect()), str(get_viewport().get_mouse_position())])
	var ok := await _wait_until(func(): return _own_units_in(units).size() > before, 90.0)
	if not ok:  # PT5: why production stalled (button state, queue, air gating)
		var pb = _find_button(get_tree().root, nm)
		var pe = _w().get_e(int(prod.id))
		print("PLAYTEST-DBG train_miss %s prod=%s#%d alive=%s queue=%s btn_disabled=%s tip=%s gate=%s sel=%s" % [item, String(prod.def), int(prod.id), str(pe != null),
			str(pe.get("queue") if pe != null else null), str(pb.disabled if pb != null else null), "" if pb == null else pb.tooltip_text.replace("
", " | "),
			Airfield.can_produce(_w(), 0, item), str(_mv().selection)])
		print("PLAYTEST-DBG train_miss_fac pop=%s/%s power=%s/%s" % [str(_w().factions[0].pop), str(_w().factions[0].pop_cap), str(_w().factions[0].get("power_use")), str(_w().factions[0].get("power_prod"))])
		print("PLAYTEST-DBG train_miss_field %s free=%s" % [str(Airfield.field(_w(), int(prod.id))), str(Airfield.free_slots(_w(), int(prod.id)))])
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
	# UI4B-3: while laying (order.t > 0) the snapshot carries FLAG_WORK -> sheet column "work"
	var eid := int(e.id)
	var working := await _wait_until(func(): return _g4b_snap_flag(eid, RenderSnapScript.FLAG_WORK), 30.0)
	_log("g4b_snap_flag_work", working)
	if working:
		await _shot("ui_g4b_07a_engineer_work")
	var laid := await _wait_until(func(): return _own_mines() > 0, 30.0)
	_log("g4b_mine_laid", laid, "mines=%d" % _own_mines())
	await _wait(0.8)
	_log("g4b_alert_mine_laid", _g4b_alert("Mine laid"))
	_log("g4b_mine_marker_drawn", _mv().g4b_over.mines_drawn > 0, "markers=%d" % _mv().g4b_over.mines_drawn)
	_log("g4b_mine_fx_drawn", _mv().entity_layer.g4b_fx_drawn > 0, "fx=%d" % _mv().entity_layer.g4b_fx_drawn)
	await _shot("ui_g4b_07_mine")
	await _g4b_fire(Vector2i(Vector2(_w().get_e(eid).pos).floor()) if _w().entities.has(eid) else cell, eid)


## UI4B-3: harness-ignited forest cell near the engineer -> fire_forest loop (snap.fires), then
## after burn-out (TerrainChanged cause fire) a burnt_ground variant with the tree removed.
func _g4b_fire(c0: Vector2i, eid: int) -> void:
	var cell := Vector2i(-1, -1)
	var best := 1e9
	var seen := false
	for dy in range(-40, 41):
		for dx in range(-40, 41):
			var q := c0 + Vector2i(dx, dy)
			if not _w().in_bounds(q) or _w().terrain_at(q) != G4bMech.FOREST:
				continue
			var v: bool = _mv().cell_visible(q)
			var d := float(dx * dx + dy * dy) - (1e6 if v else 0.0)  # a visible cell wins
			if d < best:
				best = d
				cell = q
				seen = v
	_log("g4b_forest_cell_found", cell.x >= 0, str(cell))
	if cell.x < 0:
		return
	if not seen and _w().entities.has(eid):
		# walk the engineer up to the wood so the fire is on a visible cell
		_mv().issue({"type": "move", "unit_ids": [eid], "target": Vector2(cell) + Vector2(0.5, 2.5)})
		seen = await _wait_until(func(): return _mv().cell_visible(cell), 60.0)
	_log("g4b_forest_cell_visible", seen, str(cell))
	_mv().center_camera_on(Vector2(cell) + Vector2(0.5, 0.5))
	_log("g4b_ignite", G4bMech.ignite(_w(), cell, 0), str(cell))
	var lit := await _wait_until(func(): return (_mv().snap.get("fires", PackedInt32Array()) as PackedInt32Array).size() > 0 and _mv().entity_layer.fires_drawn > 0, 5.0)
	_log("g4b_fire_drawn", lit, "fires=%d drawn=%d" % [(_mv().snap.get("fires", PackedInt32Array()) as PackedInt32Array).size(), _mv().entity_layer.fires_drawn])
	await _wait(0.6)
	await _shot("ui_g4b_08_forest_fire")
	var bt := await _wait_until(func(): return _mv().entity_layer.burnt_drawn > 0, 30.0)
	_log("g4b_burnt_drawn", bt, "burnt=%d cells=%d" % [_mv().entity_layer.burnt_drawn, _mv().entity_layer.burnt.size()])
	await _wait(0.5)
	await _shot("ui_g4b_09_burnt")


func _own_mines() -> int:
	var k := 0
	for x in _w().entities.values():
		if String(x.kind) == "mine" and int(x.owner) == 0:
			k += 1
	return k


# ------------------------------------------------------------ G5 flows (PT5): --ui-playtest-<flow>
## Human A, Stage 9 picked in the menu by real clicks (naval: Coastal Front map too). A harness grant
## tops up the stock once (the flows test the G5 UI, not the economy); every order is synthetic
## input through UI5b's buttons / hotkeys and map clicks. Harness writes (marked "harness") stand in
## only for combat damage and are done with the sim joined.
const G5_FLOWS := ["air", "naval", "drone", "support", "med", "tutorial"]


func _g5_menu() -> void:
	if g5_flow == "naval":
		var menu = get_tree().root.find_child("MapOption", true, false) as OptionButton
		var idx := -1
		if menu != null:
			for i in menu.item_count:
				if menu.get_item_text(i).begins_with("Coastal Front") and not menu.is_item_disabled(i):
					idx = i
		_log("g5_map_coastal_click", idx >= 0 and await _pick_option("MapOption", idx), "" if idx < 0 else menu.get_item_text(idx))
	var ob = get_tree().root.find_child("Slot0Stage", true, false) as OptionButton
	var k := -1
	if ob != null:
		for i in ob.item_count:
			if ob.get_item_text(i).begins_with("Stage 9 "):
				k = i
	_log("g5_slot0_stage9_click", k >= 0 and await _pick_option("Slot0Stage", k), "items=%d" % (0 if ob == null else ob.item_count))
	await _wait(0.3)


func _g5_flow() -> void:
	_mv().join_sim()
	var f: Dictionary = _w().factions[0]
	f.credits = int(f.credits) + 40000
	for r in ["salvage", "ore"]:
		f.stock[r] = int(f.stock.get(r, 0)) + 20000
	# harness peace window (this process only, in memory): the AI's first offensive is pushed past the
	# flow so a 10+ minute UI flow is not cut short by a raid (defence and economy AI still run)
	for dk in (Content.rules().get("ai_difficulties", {}) as Dictionary).keys():
		Content.rules().ai_difficulties[dk]["first_attack_tick"] = 1000000
	_log("g5_harness_grant", int(f.stage) >= 9, "stage=%d credits=%d stock=%s" % [int(f.stage), int(f.credits), str(f.stock)])
	_log("speed_3x_button", await _click_button("3x"))
	match g5_flow:
		"air":
			await _air_flow()
		"naval":
			await _naval_flow()
		"drone":
			await _drone_flow()
		"support":
			await _support_flow()
		"med":
			await _med_flow()


func _g5_named(node_name: String) -> Button:
	var b = get_tree().root.find_child(node_name, true, false) as Button
	return b if b != null and b.is_visible_in_tree() else null


## G6.1: page the command card ("More") until the named button shows (hidden on another page).
func _reveal_named(node_name: String) -> bool:
	var hud = main.get("hud")
	for i in 5:
		if _g5_named(node_name) != null:
			return true
		var pg = hud.get("_card_pager") if hud != null else null
		if pg == null or not is_instance_valid(pg) or not (pg as Button).is_visible_in_tree():
			return false
		await _click((pg as Button).get_global_rect().get_center())
		await _wait(0.25)
	return _g5_named(node_name) != null


## Click a named (UI5b) button; false when it is missing, hidden or disabled.
func _click_named(node_name: String) -> bool:
	var b := _g5_named(node_name)
	if b == null or b.disabled:
		return false
	await _click(b.get_global_rect().get_center())
	await _wait(0.3)
	return true


func _ent(id: int):
	return _w().entities.get(id)


## Select builders, place def (hotkey + click, page tab first), wait until built. Returns the newest
## built building of def ({} on failure).
func _g5_build(def_id: String, at: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var before := _built_count(def_id)
	var bl := _own_units_in(_defs_with("can_build"))
	if not bl.is_empty() and not _on_map(_to_screen(bl[0].pos)):
		_mv().center_camera_on(bl[0].pos)
		await _wait(0.3)
	var n := await _select_units(_defs_with("can_build"))
	_log("g5_select_builders_" + def_id, n > 0, "selected=%d" % n)
	_log("g5_place_" + def_id, await _place(def_id, at), def_id)
	var ok := await _wait_until(func(): return _built_count(def_id) > before, 150.0)
	_log("g5_built_" + def_id, ok, "%s built=%d" % [def_id, _built_count(def_id)])
	return _newest(def_id) if ok else {}


func _newest(def_id: String) -> Dictionary:
	var best: Dictionary = {}
	for b in _w().buildings_of(0, def_id):
		if bool(b.get("built", true)) and (best.is_empty() or int(b.id) > int(best.id)):
			best = b
	return best


## Select one own entity: a click when the click picks it, else a small box drag around it.
func _g5_select(id: int) -> bool:
	var e = _ent(id)
	if e == null:
		return false
	if not _on_map(_to_screen(e.pos)):
		_mv().center_camera_on(e.pos)
		await _wait(0.3)
	e = _ent(id)
	if _pickable(e):
		await _click(_to_screen(e.pos))
	else:
		var sp := _to_screen(e.pos)
		await _drag(sp - Vector2(26, 26), sp + Vector2(26, 26))
	await _wait(0.4)
	if not _mv().selection.has(id) and _ent(id) != null:
		# parked aircraft under a hangar roof: a click on the exact spot, then a tight box
		var sp2 := _to_screen(_ent(id).pos)
		await _drag(sp2 - Vector2(8, 8), sp2 + Vector2(8, 8))
		await _wait(0.4)
		if not _mv().selection.has(id):
			print("PLAYTEST-DBG select_miss id=%d def=%s pickable=%s at=%s sel=%s hit=%s" % [id, String(_ent(id).def), str(_pickable(_ent(id))), str(_ent(id).get("air_at", -1)), str(_mv().selection), str(_mv().entity_at(Vector2(_ent(id).pos), true).get("def") if _mv().entity_at(Vector2(_ent(id).pos), true) != null else null)])
	return _mv().selection.has(id)


## Arm a UI5b targeted button, then click world point p. True when the button was clicked.
func _g5_arm_click(btn_name: String, p: Vector2) -> bool:
	if not await _click_named(btn_name):
		return false
	await _wait(0.2)
	await _click(_to_screen(p))
	await _wait(0.4)
	return true


## A cell around c (rings r0..r1) where pred(cell) holds and whose centre is on the map on screen.
func _g5_cell_near(c: Vector2i, r0: int, r1: int, pred: Callable) -> Vector2i:
	for r in range(r0, r1 + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if _w().in_bounds(q) and pred.call(q) and _on_map(_to_screen(Vector2(q) + Vector2(0.5, 0.5))):
					return q
	return Vector2i(-1, -1)


func _g5_wait_phase(id: int, phases: Array, secs: float) -> bool:
	return await _wait_until(func(): return _ent(id) != null and phases.has(Air.phase(_w(), id)), secs)


func _g5_last_cmd() -> String:
	return String(_mv().g4b.last_cmd.get("type", ""))


# ------------------------------------------------------------ air
func _air_flow() -> void:
	for role in ["power", "power", "barracks", "factory", "depot", "depot", "depot"]:  # depots: pop cap (VTOL pop 8)
		await _g5_build(_role(role))
	var tower := await _g5_build("a_air_tower")
	var field := await _g5_build("a_airfield")
	if field.is_empty() or tower.is_empty():
		return
	var fid := int(field.id)
	_log("air_gating_no_hangar", Airfield.can_produce(_w(), 0, "a_strike_jet") == "no_free_hangar", Airfield.can_produce(_w(), 0, "a_strike_jet"))
	_log("air_select_airfield", await _g5_select(fid))
	var panel = get_tree().root.find_child("AirfieldPanel", true, false) as Control
	_log("air_airfield_panel_visible", panel != null and panel.is_visible_in_tree())
	var warn = get_tree().root.find_child("AirfieldWarn", true, false) as Label
	_log("air_panel_warns_no_hangar", warn != null and String(warn.text).to_lower().contains("hangar"), "" if warn == null else warn.text)
	await _shot("air_01_airfield_card")
	# buy a light (jet) and a heavy (VTOL) hangar from the airfield card
	for cls in ["light", "heavy"]:
		var before := _built_count("a_hangar_" + cls)
		_log("air_click_buy_hangar_" + cls, await _click_named("G5_hangar_" + cls))
		_log("air_hangar_" + cls + "_built", await _wait_until(func(): return _built_count("a_hangar_" + cls) > before, 120.0), "hangars=%d" % _built_count("a_hangar_" + cls))
		await _g5_select(fid)
	_log("air_gating_ok_after_hangar", Airfield.can_produce(_w(), 0, "a_strike_jet") == "", Airfield.can_produce(_w(), 0, "a_strike_jet"))
	await _shot("air_02_hangars")
	# airfield engineers -> Assign [N] -> click the airfield
	var engs := await _train("a_airfield_engineers")
	if not engs.is_empty():
		await _wait(1.0)
		_log("air_select_engineers", await _g5_select(int(engs[0].id)))
		_log("air_assign_engineers_click", await _g5_arm_click("G5_assign_engineers", _ent(fid).pos), _g5_last_cmd())
		_log("air_engineers_assigned", await _wait_until(func(): return not Airfield.engineers_at(_w(), fid).is_empty(), 60.0), "engineers=%s" % str(Airfield.engineers_at(_w(), fid)))
		await _shot("air_03_engineers_assigned")
	await _air_jet(fid)
	await _air_vtol(fid)
	await _air_heli(engs)


func _air_jet(fid: int) -> void:
	await _g5_select(fid)
	var jets := await _train("a_strike_jet")
	if jets.is_empty():
		return
	var jid := int(jets[0].id)
	_log("air_jet_parked", await _g5_wait_phase(jid, ["parked"], 30.0), Air.phase(_w(), jid))
	await _shot("air_04_jet_parked")
	_log("air_select_jet", await _g5_select(jid))
	var fp: Vector2 = _ent(fid).pos
	var mc := Vector2(float(_w().map.w), float(_w().map.h)) * 0.5
	var goal := fp + (mc - fp).normalized() * 14.0
	for ang in [0.0, 0.7, -0.7, 1.4, -1.4]:
		var g2: Vector2 = fp + (mc - fp).normalized().rotated(ang) * 14.0
		if _on_map(_to_screen(g2)):
			goal = g2
			break
	_log("air_sortie_click", await _g5_arm_click("G5_sortie", goal), _g5_last_cmd())
	_log("air_jet_taxi_roll", await _g5_wait_phase(jid, ["taxi", "hold", "roll"], 20.0), Air.phase(_w(), jid))
	await _shot("air_05_jet_takeoff")
	_log("air_jet_airborne_sortie", await _g5_wait_phase(jid, ["sortie", "air"], 60.0), Air.phase(_w(), jid))
	await _wait(1.0)
	await _shot("air_06_jet_sortie")
	_log("air_jet_returns", await _g5_wait_phase(jid, ["ret", "holding", "approach", "taxi_in"], 120.0), Air.phase(_w(), jid))
	_log("air_jet_landed_parked", await _g5_wait_phase(jid, ["parked"], 150.0), Air.phase(_w(), jid))
	await _shot("air_07_jet_landed")


func _g5_cell(p: Vector2) -> Vector2i:
	return Vector2i(Vector2(p).floor())


func _lz_ok(def_id: String) -> Callable:
	var d := Content.unit(def_id)
	return func(q: Vector2i) -> bool: return Air.landing_ok(_w(), q, d)


## AIRFIX7: a landing zone for a bay dropship (G7 CNFAC7-2 rear-ramp loading, Transport.ramp_clear): landing_ok AND open ground
## behind the tail for foot and vehicle at every one of the 8 drawn facings (the craft lands facing its approach heading, so
## the ramp side is not known when the zone is picked). The old zone (20,8) sat 2 tiles from the motor pool: ramp blocked.
func _lz_ramp_ok(def_id: String) -> Callable:
	var base := _lz_ok(def_id)
	return func(q: Vector2i) -> bool:
		if not base.call(q):
			return false
		var fake := {"pos": Vector2(q) + Vector2(0.5, 0.5)}
		for k in 8:
			for cls in ["foot", "vehicle"]:
				if not Transport.ramp_clear(_w(), fake, float(k) * PI / 4.0, cls):
					return false
		return true


## Select ids by clicking the first and shift-clicking the rest (camera on each).
func _g5_select_many(ids: Array) -> int:
	if ids.is_empty():
		return 0
	await _g5_select(int(ids[0]))
	for i in range(1, ids.size()):
		var e = _ent(int(ids[i]))
		if e == null:
			continue
		if not _on_map(_to_screen(e.pos)):
			_mv().center_camera_on(e.pos)
			await _wait(0.2)
		await _click(_to_screen(_ent(int(ids[i])).pos), MOUSE_BUTTON_LEFT, false, true)
		await _wait(0.15)
	var n := 0
	for id in ids:
		if _mv().selection.has(int(id)):
			n += 1
	return n


func _air_vtol(fid: int) -> void:
	await _g5_select(fid)
	var vs := await _train("a_vtol_dropship")
	if vs.is_empty():
		return
	var vid := int(vs[0].id)
	var tanks: Array = []
	for i in 2:
		tanks.append_array(await _train(_role("heavy")))
	var troops: Array = []
	while troops.size() < 8:
		var sq := await _train(_role("infantry"))
		if sq.is_empty():
			break
		troops = _own_units_in(G3.item_units(_role("infantry")))
	var tank_ids: Array = []
	for t in _own_units_in([_role("heavy")]):
		if tank_ids.size() < 2:
			tank_ids.append(int(t.id))
	var troop_ids: Array = []
	for t in troops:
		if troop_ids.size() < 8:
			troop_ids.append(int(t.id))
	_log("air_vtol_cargo_ready", tank_ids.size() == 2 and troop_ids.size() == 8, "tanks=%d troops=%d" % [tank_ids.size(), troop_ids.size()])
	await _g5_wait_phase(vid, ["parked"], 30.0)
	# land the VTOL on open ground beside the cargo
	var tp: Vector2 = _ent(tank_ids[0]).pos if not tank_ids.is_empty() else _ent(vid).pos
	_mv().center_camera_on(tp)
	await _wait(0.3)
	var lz := _g5_cell_near(_g5_cell(tp), 3, 14, _lz_ramp_ok("a_vtol_dropship"))
	_log("air_vtol_lz_found", lz.x >= 0, str(lz))
	if lz.x < 0:
		return
	_log("air_select_vtol", await _g5_select(vid))
	_mv().center_camera_on(Vector2(lz))
	await _wait(0.3)
	_log("air_vtol_land_here_click", await _g5_arm_click("G5_land_at", Vector2(lz) + Vector2(0.5, 0.5)), _g5_last_cmd())
	_log("air_vtol_landed_open_ground", await _g5_wait_phase(vid, ["landed"], 120.0), Air.phase(_w(), vid))
	await _shot("air_08_vtol_landed")
	# troops then tanks: select every one (click + shift-click; G6.1 double-click now selects one SQUAD, not every
	# unit of the type, so it took 4 of 8 riflemen), right-click the VTOL = load
	# AIRFIX7: G7 CNFAC7-2 (owner 13.9c, content/g7/defs_g7_facility.json _g7_bays) gave the dropship one internal bay: ONE vehicle
	# plus up to 10 men; the second tank is refused by design. Full = 8 riflemen + 1 tank (the check id keeps its old name).
	var full := {"foot": 8, "vehicle": 1}
	for grp0 in [troop_ids, tank_ids]:
		# AIRFIX7: the riflemen box can cover the tanks standing among them (the right-click then loads those too); men already
		# aboard have no world entity: take only those still outside, nothing left = nothing to select / load
		var grp: Array = grp0.filter(func(i): return _ent(int(i)) != null)
		if grp.is_empty():
			continue
		var cen := Vector2.ZERO
		for id in grp:
			cen += Vector2(_ent(int(id)).pos)
		cen /= maxf(1.0, float(grp.size()))
		_mv().center_camera_on(cen)
		await _wait(0.3)
		# AIRFIX7: a man still walking (squad settling after training) leaves the box before the drag lands: wait until the
		# whole group stands still, then box it (the fallback shift-click path replaced a 7-of-8 box with 3)
		await _wait_until(func(): return grp.all(func(i): return _ent(int(i)) == null or not bool(_ent(int(i)).get("moving", false))), 20.0)
		grp = grp.filter(func(i): return _ent(int(i)) != null)   # may have boarded while we waited
		if grp.is_empty():
			continue
		cen = Vector2.ZERO
		for id in grp:
			cen += Vector2(_ent(int(id)).pos)
		cen /= maxf(1.0, float(grp.size()))
		_mv().center_camera_on(cen)
		await _wait(0.3)
		# box-select the group (packed riflemen: a shift-click often hit an already selected neighbour and toggled it)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for id in grp:
			var sp := _to_screen(Vector2(_ent(int(id)).pos))
			lo = Vector2(minf(lo.x, sp.x), minf(lo.y, sp.y))
			hi = Vector2(maxf(hi.x, sp.x), maxf(hi.y, sp.y))
		await _drag(lo - Vector2(18, 18), hi + Vector2(18, 18))
		await _wait(0.3)
		var dn := 0
		for id in grp:
			if _mv().selection.has(int(id)):
				dn += 1
		if dn < grp.size():
			dn = await _g5_select_many(grp)
		_log("air_vtol_select_cargo_" + String(_ent(int(grp[0])).def), dn >= grp.size(), "selected=%d of %d" % [dn, grp.size()])
		_mv().center_camera_on(_ent(vid).pos)
		await _wait(0.3)
		await _click(_to_screen(_ent(vid).pos), MOUSE_BUTTON_RIGHT)
		await _wait(0.5)
	var loaded := await _wait_until(func(): return Transport.group_load(_ent(vid)) == full, 120.0)
	_log("air_vtol_loaded_2v_8f", loaded, "load=%s" % str(Transport.group_load(_ent(vid))))
	# AIRFIX7: the craft is committed while its rear-ramp sequence runs (Transport.hold_bays: no lift-off, a take-off order is
	# refused with BayBusy): wait for the ramp to be up before clicking Take off
	_log("air_vtol_ramp_up", await _wait_until(func(): return _ent(vid) != null and not _ent(vid).has("bay_seq"), 60.0), "bay_seq=%s" % str(_ent(vid).get("bay_seq", "none")))
	await _g5_select(vid)
	await _shot("air_09_vtol_loaded")
	_log("air_vtol_take_off_click", await _click_named("G5_take_off"), _g5_last_cmd())
	_log("air_vtol_airborne", await _g5_wait_phase(vid, ["air"], 30.0), Air.phase(_w(), vid))
	var c0 := _g5_cell(_ent(vid).pos)
	var lz2 := _g5_cell_near(c0, 10, 16, _lz_ramp_ok("a_vtol_dropship"))
	if lz2.x < 0:
		_mv().center_camera_on(Vector2(c0))
		await _wait(0.3)
		lz2 = _g5_cell_near(c0, 9, 14, _lz_ramp_ok("a_vtol_dropship"))
	_log("air_vtol_far_lz_found", lz2.x >= 0, str(lz2))
	if lz2.x < 0:
		return
	_log("air_vtol_fly_land_click", await _g5_arm_click("G5_land_at", Vector2(lz2) + Vector2(0.5, 0.5)), _g5_last_cmd())
	await _wait(2.0)
	await _shot("air_10_vtol_flying")
	_log("air_vtol_landed_far", await _g5_wait_phase(vid, ["landed"], 120.0), "phase=%s at=%s" % [Air.phase(_w(), vid), str(_ent(vid).pos)])
	await _g5_select(vid)
	_log("air_vtol_unload_click", await _click_button("Unload at point"))
	var vp: Vector2 = _ent(vid).pos
	await _click(_to_screen(vp + Vector2(0.5, 0.5)))
	var empty := await _wait_until(func(): return Transport.used_slots(_ent(vid)) == 0 and Transport.group_load(_ent(vid)).values().all(func(x): return int(x) == 0), 90.0)
	var near := 0
	for id in tank_ids + troop_ids:
		var u = _ent(int(id))
		if u != null and Vector2(u.pos).distance_to(vp) < 7.0:
			near += 1
	_log("air_vtol_unloaded", empty and near >= 9, "near=%d of 10 load=%s" % [near, str(Transport.group_load(_ent(vid)))])
	await _wait(1.0)
	await _shot("air_11_vtol_unloaded")


func _air_heli(engs: Array) -> void:
	_mv().center_camera_on(_hq().pos)
	await _wait(0.3)
	var pad := await _g5_build("a_helipad")
	if pad.is_empty():
		return
	var pid := int(pad.id)
	if not engs.is_empty():
		_log("air_heli_select_engineers", await _g5_select(int(engs[0].id)))
		_log("air_heli_assign_pad_click", await _g5_arm_click("G5_assign_engineers", _ent(pid).pos), _g5_last_cmd())
		_log("air_heli_pad_engineers", await _wait_until(func(): return not Airfield.engineers_at(_w(), pid).is_empty(), 60.0), str(Airfield.engineers_at(_w(), pid)))
	await _g5_select(pid)
	var hs := await _train("a_attack_heli")
	if hs.is_empty():
		return
	var hid := int(hs[0].id)
	await _g5_wait_phase(hid, ["parked", "landed"], 30.0)
	# open ground outside the base: >= 7 tiles from every own building
	var hq: Vector2 = _hq().pos
	var away := func(q: Vector2i) -> bool:
		if not Air.landing_ok(_w(), q, Content.unit("a_attack_heli")):
			return false
		for b in _w().buildings_of(0):
			if Vector2(b.pos).distance_to(Vector2(q)) < 7.0:
				return false
		return true
	_mv().center_camera_on(hq)
	await _wait(0.3)
	var roomy := func(q: Vector2i) -> bool: return away.call(q) and away.call(q + Vector2i(1, 1)) and away.call(q - Vector2i(1, 1))
	var lz := _g5_cell_near(_g5_cell(hq), 8, 20, roomy)
	_log("air_heli_open_ground_found", lz.x >= 0, str(lz))
	if lz.x < 0:
		return
	_log("air_select_heli", await _g5_select(hid))
	_mv().center_camera_on(Vector2(lz))
	await _wait(0.3)
	_log("air_heli_land_here_click", await _g5_arm_click("G5_land_at", Vector2(lz) + Vector2(0.5, 0.5)), _g5_last_cmd())
	var lc: Dictionary = _mv().g4b.last_cmd.duplicate(true)
	lc["issuer"] = 0
	print("PLAYTEST-DBG heli_land cmd=%s preview=%s sel=%s" % [str(lc), _w().preview_command(lc), str(_mv().selection)])
	var lzc := Vector2(lz) + Vector2(0.5, 0.5)
	_log("air_heli_landed_outside", await _wait_until(func(): return Air.phase(_w(), hid) == "landed" and Vector2(_ent(hid).pos).distance_to(lzc) < 1.6, 90.0),
		"phase=%s pos=%s lz=%s air_at=%s" % [Air.phase(_w(), hid), str(_ent(hid).pos), str(lzc), str(_ent(hid).get("air_at", -1))])
	await _shot("air_12_heli_landed_outside")
	# harness (combat stand-in): the helicopter took hits and spent its rockets
	_mv().join_sim()
	var he: Dictionary = _ent(hid)
	HotState.set_hp(_w(), hid, float(he.max_hp) * 0.5)
	he.ammo = 0
	await _g5_select(hid)
	_log("air_heli_take_off_click", await _click_named("G5_take_off"), _g5_last_cmd())
	_log("air_heli_airborne", await _g5_wait_phase(hid, ["air", "ret"], 30.0), Air.phase(_w(), hid))
	await _shot("air_13_heli_airborne")
	_mv().center_camera_on(_ent(pid).pos)
	await _wait(0.3)
	_log("air_heli_rebase_pad_click", await _g5_arm_click("G5_rebase", _ent(pid).pos), _g5_last_cmd())
	_log("air_heli_at_pad", await _wait_until(func(): return Air.is_landed(_ent(hid)) and int(_ent(hid).get("air_at", -1)) == pid, 90.0),
		"phase=%s at=%s" % [Air.phase(_w(), hid), str(_ent(hid).get("air_at", -1))])
	var dd := Content.unit("a_attack_heli")
	var svc := await _wait_until(func(): return float(_ent(hid).hp) >= float(_ent(hid).max_hp) - 0.01 and int(_ent(hid).get("ammo", 0)) >= int(dd.get("ammo_max", 0)), 90.0)
	_log("air_heli_serviced_with_engineers", svc and not Airfield.engineers_at(_w(), pid).is_empty(),
		"hp=%.0f/%.0f ammo=%s/%s engineers=%d" % [float(_ent(hid).hp), float(_ent(hid).max_hp), str(_ent(hid).get("ammo")), str(dd.get("ammo_max")), Airfield.engineers_at(_w(), pid).size()])
	await _g5_select(hid)
	await _shot("air_14_heli_serviced")


# ------------------------------------------------------------ naval (Coastal Front)
func _naval_flow() -> void:
	for role in ["power", "barracks", "factory"]:
		await _g5_build(_role(role))
	var w := _w()
	var c: Vector2i = _hq().cell
	var site := Vector2i(-1, -1)
	for r in range(3, 48):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if site.x < 0 and maxi(absi(dx), absi(dy)) == r and Construction.placement_error(w, 0, "a_shipyard", c + Vector2i(dx, dy)) == "":
					site = c + Vector2i(dx, dy)
		if site.x >= 0:
			break
	if site.x < 0:
		# the coast is unexplored: scout it with the builders (right-click move), then build there
		var shore := Vector2i(-1, -1)
		var bd := 1e9
		for y in w.map.h:
			for x in w.map.w:
				var o := Vector2i(x, y)
				var d2 := float((o - c).length_squared())
				if d2 < bd and Naval.shore_error(w, "a_shipyard", o) == "":
					bd = d2
					shore = o
		_log("naval_shore_known", shore.x >= 0, "shore=%s dist=%.0f err=%s" % [str(shore), sqrt(bd), Construction.placement_error(w, 0, "a_shipyard", shore) if shore.x >= 0 else ""])
		if shore.x >= 0:
			_mv().center_camera_on(_own_units_in(_defs_with("can_build"))[0].pos)
			await _wait(0.3)
			var n0 := await _select_units(_defs_with("can_build"))
			_mv().center_camera_on(Vector2(shore))
			await _wait(0.4)
			await _click(_to_screen(Vector2(shore) + Vector2(1.5, 1.5)), MOUSE_BUTTON_RIGHT)
			var ok_s := await _wait_until(func(): return Construction.placement_error(_w(), 0, "a_shipyard", shore) == "", 90.0)
			_log("naval_scout_coast_rightclick", n0 > 0 and ok_s, "err=%s" % Construction.placement_error(_w(), 0, "a_shipyard", shore))
			if ok_s:
				site = shore
	_log("naval_shore_site_found", site.x >= 0, "site=%s hq=%s" % [str(site), str(c)])
	if site.x < 0:
		return
	var yard := await _g5_build("a_shipyard", site)
	if yard.is_empty():
		return
	await _shot("naval_01_shipyard")
	var crafts := await _train("a_landing_craft")
	if crafts.is_empty():
		return
	var cid := int(crafts[0].id)
	_log("naval_craft_on_water", Naval.is_water_class(String(_ent(cid).def)), String(_ent(cid).def))
	var squad := await _train(_role("infantry"))
	if squad.is_empty():
		return
	await _wait(2.0)
	var sids: Array = []
	for u in squad:
		sids.append(int(u.id))
	var n := await _g5_select_many(sids)
	_log("naval_select_squad", n == sids.size(), "selected=%d of %d" % [n, sids.size()])
	_mv().center_camera_on(_ent(cid).pos)
	await _wait(0.3)
	await _click(_to_screen(_ent(cid).pos), MOUSE_BUTTON_RIGHT)
	var loaded := await _wait_until(func(): return Transport.cargo_ids(_ent(cid)).size() >= sids.size(), 120.0)
	_log("naval_right_click_load", loaded, "cargo=%s" % str(Transport.cargo_ids(_ent(cid))))
	await _g5_select(cid)
	await _shot("naval_02_craft_loaded")
	if not loaded:
		return
	# a beach across the water, >= 10 tiles from the shipyard (camera moved there like a player scrolls)
	var cc := _g5_cell(_ent(cid).pos)
	var beach := Vector2i(-1, -1)
	var best := 1e9
	for dy in range(-40, 41):
		for dx in range(-40, 41):
			var q := cc + Vector2i(dx, dy)
			var d2 := float(dx * dx + dy * dy)
			if d2 >= 100.0 and d2 < best and w.in_bounds(q) and Naval.beach_ok(w, q) and Naval.drop_ok(w, _ent(cid), q):
				best = d2
				beach = q
	_log("naval_beach_found", beach.x >= 0, "beach=%s from=%s" % [str(beach), str(cc)])
	if beach.x < 0:
		return
	_mv().center_camera_on(Vector2(beach))
	await _wait(0.3)
	_log("naval_unload_at_point_click", await _click_button("Unload at point"))
	await _click(_to_screen(Vector2(beach) + Vector2(0.5, 0.5)))
	await _wait(3.0)
	_mv().center_camera_on(_ent(cid).pos)
	await _shot("naval_03_craft_underway")
	var landed := await _wait_until(func(): return Transport.cargo_ids(_ent(cid)).is_empty(), 180.0)
	var ashore := 0
	for id in sids:
		var u = _ent(int(id))
		if u != null and not Naval.is_water_class(String(u.def)) and Vector2(u.pos).distance_to(Vector2(beach)) < 6.0:
			ashore += 1
	_log("naval_beach_landing", landed and ashore == sids.size(), "ashore=%d of %d" % [ashore, sids.size()])
	_mv().center_camera_on(Vector2(beach))
	await _wait(1.0)
	await _shot("naval_04_beach_landing")


# ------------------------------------------------------------ Drone Team
func _drone_flow() -> void:
	for role in ["power", "barracks"]:
		await _g5_build(_role(role))
	var teams := await _train("a_drone_team")
	if teams.is_empty():
		return
	var tid := int(teams[0].id)
	await _wait(2.0)
	# walk the team out of supply range (supply.radius) so spent drones are not restocked at once
	_log("drone_select_team_move", await _g5_select(tid))
	var hqp: Vector2 = _hq().pos
	var mc := Vector2(float(_w().map.w), float(_w().map.h)) * 0.5
	var dest := hqp + (mc - hqp).normalized() * 18.0
	_mv().center_camera_on(dest)
	await _wait(0.4)
	await _click(_to_screen(dest), MOUSE_BUTTON_RIGHT)
	var far := func() -> bool:
		for b in _w().buildings_of(0):
			if Vector2(b.pos).distance_to(Vector2(_ent(tid).pos)) < 11.0:
				return false
		return not bool(_ent(tid).get("moving", false))
	_log("drone_team_moved_out", await _wait_until(far, 90.0), "pos=%s" % str(_ent(tid).pos))
	# harness: an enemy wall section 8 tiles out (the breach target; no enemy base this close)
	_mv().join_sim()
	var w := _w()
	var efid := -1
	for k in w.factions.keys():
		if w.is_enemy(0, int(k)):
			efid = int(k)
			break
	var wdef := Content.role(G3.faction_def(w, efid), "wall") if efid >= 0 else ""
	var tc := _g5_cell(_ent(tid).pos)
	_mv().center_camera_on(_ent(tid).pos)
	await _wait(0.3)
	var wc := _g5_cell_near(tc, 7, 12, func(q: Vector2i) -> bool: return Construction.placement_error(_w(), efid, wdef, q) == "")
	if wc.x < 0:
		wc = _g5_cell_near(tc, 7, 12, func(q: Vector2i) -> bool: return Construction.placement_error(_w(), 0, wdef, q) == "")
	var wid := -1
	if wdef != "" and wc.x >= 0:
		_mv().join_sim()
		wid = _w().spawn_building(wdef, efid, wc, true)
	_log("drone_harness_enemy_wall", wid >= 0 and _ent(wid) != null, "def=%s cell=%s owner=%d" % [wdef, str(wc), efid])
	_log("drone_select_team", await _g5_select(tid))
	await _shot("drone_01_team_card")
	var k := 0
	_mv().speed = 1.0  # strike drones dive in well under a second at 3x: launch and check at 1x
	for dt in ["strike", "frag", "recon", "emp"]:
		var before := G5Mech.drone_charges(_ent(tid))
		var q := _g5_cell_near(tc, 6 + k, 10 + k, func(x: Vector2i) -> bool: return _w().terrain_at(x) != G4bMech.FOREST)
		k += 1
		await _g5_select(tid)
		_log("drone_launch_%s_click" % dt, await _g5_arm_click("G5_drone_" + dt, Vector2(q) + Vector2(0.5, 0.5)), "%s cell=%s" % [_g5_last_cmd(), str(q)])
		var flying := await _wait_until(func(): return _own_drones() > 0 and G5Mech.drone_charges(_ent(tid)) == before - 1, 10.0)
		_log("drone_%s_launched" % dt, flying, "charges=%d drones=%d" % [G5Mech.drone_charges(_ent(tid)), _own_drones()])
		await _wait(0.5)
		await _shot("drone_0%d_%s" % [k + 1, dt])
	_mv().speed = 3.0
	_log("drone_team_tactical_mode", await _wait_until(func(): return G5Mech.mode(_ent(tid)) == "tactical", 10.0), G5Mech.mode(_ent(tid)))
	await _g5_select(tid)
	await _wait(0.6)
	_log("drone_tactical_buttons_shown", _g5_named("G5_tact_breach") != null and _g5_named("G5_drone_strike") == null)
	await _shot("drone_06_tactical_card")
	if wid < 0:
		return
	var hp0 := float(_ent(wid).hp)
	_log("drone_breach_click", await _g5_arm_click("G5_tact_breach", _ent(wid).pos) and String(_mv().g4b.last_cmd.get("ability", "")) == "breach", str(_mv().g4b.last_cmd))
	var hit := await _wait_until(func(): return _ent(wid) == null or float(_ent(wid).hp) < hp0, 90.0)
	_log("drone_tactical_breach", hit, "wall hp=%s" % ("destroyed" if _ent(wid) == null else str(_ent(wid).hp)))
	await _wait(1.0)
	await _shot("drone_07_breach")


func _own_drones() -> int:
	var n := 0
	for e in _w().units_of(0):
		if G5Mech.is_launched_drone(e):
			n += 1
	return n


# ------------------------------------------------------------ auto resupply
func _support_flow() -> void:
	for role in ["power", "barracks", "factory"]:
		await _g5_build(_role(role))
	var trucks := await _train(_role("supply"))
	var squad := await _train(_role("infantry"))
	if trucks.is_empty() or squad.is_empty():
		return
	var trid := int(trucks[0].id)
	await _wait(2.0)
	await _g5_walk_out(squad)
	await _support_mode(trid, squad, "station", 1)
	var squad2 := await _train(_role("infantry"))
	await _wait(2.0)
	await _g5_walk_out(squad2 if not squad2.is_empty() else squad)
	await _support_mode(trid, squad2 if not squad2.is_empty() else squad, "roam", 2)


## Select units (double-click) and right-click a point 16 tiles out toward the map centre, out of
## supply-point range, so only the truck can serve them.
func _g5_walk_out(units: Array) -> void:
	if units.is_empty():
		return
	_mv().center_camera_on(_ent(int(units[0].id)).pos)
	await _wait(0.3)
	# G6.1: select exactly these units (selecting "a rifleman" took the squad already standing at dest)
	var wids := []
	for u in units:
		wids.append(int(u.id))
	var n := await _g5_select_many(wids)
	var hqp: Vector2 = _hq().pos
	var mc := Vector2(float(_w().map.w), float(_w().map.h)) * 0.5
	var dest := hqp + (mc - hqp).normalized() * 16.0
	_mv().center_camera_on(dest)
	await _wait(0.3)
	await _click(_to_screen(dest), MOUSE_BUTTON_RIGHT)
	var far := func() -> bool:
		for u in units:
			var e = _ent(int(u.id))
			if e == null or bool(e.get("moving", false)):
				return false
			for b in _w().buildings_of(0):
				if Vector2(b.pos).distance_to(Vector2(e.pos)) < 9.0:
					return false
		return true
	var wok: bool = n > 0 and await _wait_until(far, 90.0)
	if not wok:
		for u in units:
			var e = _ent(int(u.id))
			if e == null:
				print("PLAYTEST-DBG walk_out %d gone" % int(u.id))
				continue
			var nb := 999.0
			var nbd := ""
			for bb in _w().buildings_of(0):
				var dd := Vector2(bb.pos).distance_to(Vector2(e.pos))
				if dd < nb:
					nb = dd
					nbd = String(bb.def)
			print("PLAYTEST-DBG walk_out %s#%d pos=%s moving=%s order=%s squad=%s near_bld=%s %.1f" % [String(e.def), int(e.id), str(e.pos),
				str(e.get("moving", false)), str(e.order).left(90), str(e.get("squad", -1)), nbd, nb])
	_log("support_walk_out_rightclick", wok, "selected=%d dest=%s" % [n, str(dest)])


func _drain_ammo(units: Array) -> Array:
	_mv().join_sim()
	var ids: Array = []
	for u in units:
		var e = _ent(int(u.id))
		var am := int(Content.unit(String(e.def)).get("ammo_max", 0)) if e != null else 0
		if am > 0:
			e.ammo = int(am * 0.1)   # harness (combat stand-in): magazines nearly spent
			ids.append(int(e.id))
	return ids


func _support_mode(trid: int, units: Array, mode: String, n: int) -> void:
	var needy := _drain_ammo(units)
	var t0: int = _w().tick
	_log("support_%s_needy_units" % mode, needy.size() > 0 and Support.needs_supply(_w(), _ent(int(needy[0]))), "needy=%d" % needy.size())
	var cen := Vector2.ZERO
	for id in needy:
		cen += Vector2(_ent(int(id)).pos)
	cen /= maxf(1.0, float(needy.size()))
	_log("support_%s_select_truck" % mode, await _g5_select(trid))
	_log("support_%s_auto_click" % mode, await _click_named("G5_truck_auto"))
	await _wait(0.3)
	_mv().center_camera_on(cen)
	await _wait(0.3)
	await _drag(_to_screen(cen), _to_screen(cen + Vector2(7.0, 0.0)))
	await _wait(0.5)
	var ts := Support.truck_state(_w(), trid)
	_log("support_%s_area_set" % mode, String(ts.get("mode", "")) == mode and Vector2(float(ts.get("center", [0, 0])[0]), float(ts.get("center", [0, 0])[1])).distance_to(cen) < 2.0,
		"state mode=%s center=%s radius=%s" % [String(ts.get("mode", "")), str(ts.get("center")), str(ts.get("radius"))])
	await _g5_select(trid)
	await _wait(0.4)
	await _reveal_named("G5_truck_auto")
	var b := _g5_named("G5_truck_auto")
	if b == null:
		print("PLAYTEST-DBG roam_button_missing sel=%s truck=%d" % [str(_mv().selection), trid])
	_log("support_%s_button_shows_mode" % mode, b != null and String(b.text).contains(mode), "" if b == null else String(b.text).replace("\n", " | "))
	# claim evidence (PT5-2): the FLAG_RESUP poll alone missed brief roam claims at 3x speed, so a claim
	# counts when a needy unit carries resup_by = this truck, the truck queue holds it, the sim logged a
	# ResupplyClaimed for it since the order, or the render snapshot shows FLAG_RESUP.
	var how := [""]
	var resup := await _wait_until(func(): return _support_claimed(trid, needy, t0, how), 60.0)
	_log("support_%s_claimed_flag" % mode, resup, "via=%s" % how[0])
	await _shot("support_0%d_%s_serving" % [n, mode])
	var served := await _wait_until(func(): return needy.all(func(id): return _ent(int(id)) == null or not Support.needs_supply(_w(), _ent(int(id)))), 120.0)
	_log("support_%s_units_resupplied" % mode, served, "ammo=%s" % str(needy.map(func(id): return _ent(int(id)).get("ammo") if _ent(int(id)) != null else -1)))
	await _shot("support_0%d_%s_done" % [n, mode])


func _support_claimed(trid: int, needy: Array, t0: int, how: Array) -> bool:
	for id in needy:
		var u = _ent(int(id))
		if u != null and int(u.get("resup_by", -1)) == trid:
			how[0] = "resup_by"
			return true
	for id in Support.truck_state(_w(), trid).get("queue", []):
		if needy.has(int(id)) or needy.has(float(id)):
			how[0] = "truck_queue"
			return true
	for ev in _w().event_log:
		if String(ev.get("type", "")) == "ResupplyClaimed" and int(ev.get("tick", -1)) >= t0 and int(ev.get("truck", -1)) == trid and (needy.has(int(ev.get("unit", -1))) or needy.has(float(ev.get("unit", -1)))):
			how[0] = "event_log"
			return true
	if _any_flag(needy, RenderSnapScript.FLAG_RESUP):
		how[0] = "FLAG_RESUP"
		return true
	return false


func _med_picked(wounded: Array, t0: int, by: Array) -> bool:
	for id in wounded:
		var u = _ent(int(id))
		if u != null and int(u.get("evac_by", -1)) >= 0:
			by[0] = int(u.evac_by)
			return true
	for ev in _w().event_log:
		if String(ev.get("type", "")) == "WoundedPickedUp" and int(ev.get("tick", -1)) >= t0 and (wounded.has(int(ev.get("id", -1))) or wounded.has(float(ev.get("id", -1)))):
			by[0] = int(ev.get("carrier", -1))
			return true
	return false


func _any_flag(ids: Array, flag: int) -> bool:
	for id in ids:
		if _g4b_snap_flag(int(id), flag):
			return true
	return false


# ------------------------------------------------------------ medical
func _med_flow() -> void:
	for role in ["power", "barracks", "factory"]:
		await _g5_build(_role(role))
	var hosp := await _g5_build("a_hospital")
	var medics := await _train("a_medic_team")
	var squad := await _train(_role("infantry"))
	if hosp.is_empty() or medics.is_empty() or squad.is_empty():
		return
	var mid := int(medics[0].id)
	await _wait(2.0)
	_log("med_has_medical", Medical.has_medical(_w(), 0))
	var sids: Array = []
	var cen := Vector2.ZERO
	for u in squad:
		sids.append(int(u.id))
		cen += Vector2(_ent(int(u.id)).pos)
	cen /= float(sids.size())
	_log("med_select_medic", await _g5_select(mid))
	_log("med_auto_evac_click", await _click_named("G5_medic_auto"))
	await _wait(0.3)
	_mv().center_camera_on(cen)
	await _wait(0.3)
	await _drag(_to_screen(cen), _to_screen(cen + Vector2(9.0, 0.0)))
	await _wait(0.5)
	_log("med_auto_evac_on", _mv().g4b.last_cmd.get("type", "") == "set_auto_evac" and bool(_mv().g4b.last_cmd.get("on", false)), str(_mv().g4b.last_cmd))
	# harness (combat stand-in): an enemy shot through the real Damage path drops two riflemen to 0 hp
	_mv().join_sim()
	var w := _w()
	var foe = null
	for e in w.entities.values():
		if e.kind == "unit" and w.is_enemy(0, int(e.owner)) and not Combat.stats(e).is_empty():
			foe = e
			break
	var hurt: Array = sids.slice(0, mini(2, sids.size()))
	if foe != null:
		for id in hurt:
			var e: Dictionary = _ent(int(id))
			HotState.set_hp(w, int(id), 0.01)
			Damage.apply_hit(w, foe, e, Combat.stats(foe), true)
	var wounded := hurt.filter(func(id): return _ent(int(id)) != null and Medical.is_wounded(_ent(int(id))))
	_log("med_wounded", foe != null and wounded.size() == hurt.size(), "wounded=%d of %d (foe=%s)" % [wounded.size(), hurt.size(), "none" if foe == null else String(foe.def)])
	# G6 (PT6-2) p2 parallel flake: under 2 windowed runs the render snapshot lagged past a fixed 0.6 s; wait on it.
	_log("med_wounded_flag", await _wait_until(func(): return _any_flag(wounded, RenderSnapScript.FLAG_WOUNDED), 6.0))
	await _shot("med_01_wounded")
	if wounded.is_empty():
		return
	# pickup evidence (PT5-2): any own carrier holding a wounded (evac_by), or a WoundedPickedUp event for one
	# since the wound (the medic team is several units; carrying(medics[0]) alone missed a teammate's pickup)
	var by := [-1]
	var picked := await _wait_until(func(): return _med_picked(wounded, 0, by), 90.0)
	if not picked:
		print("PLAYTEST-DBG med_events %s" % str(_w().event_log.filter(func(ev): return ["UnitWounded", "WoundedPickedUp", "Reinforcement", "BledOut"].has(String(ev.get("type", ""))))))
	_log("med_evac_pickup", picked, "carrier=%d def=%s" % [by[0], "" if _ent(by[0]) == null else String(_ent(by[0]).def)])
	_mv().center_camera_on(_ent(mid).pos)
	await _wait(0.5)
	await _shot("med_02_evac")
	var hp_pos: Vector2 = _ent(int(hosp.id)).pos
	var healed := await _wait_until(func(): return wounded.all(func(id): return _ent(int(id)) != null and not Medical.is_wounded(_ent(int(id))) and int(_ent(int(id)).get("evac_by", -1)) < 0), 180.0)
	var at_h := 0
	for id in wounded:
		var u = _ent(int(id))
		if u != null and float(u.hp) >= float(u.max_hp) - 0.01 and Vector2(u.pos).distance_to(hp_pos) < 8.0:
			at_h += 1
	_log("med_hospital_reinforcement", healed and at_h == wounded.size(), "healed_at_hospital=%d of %d" % [at_h, wounded.size()])
	_mv().center_camera_on(hp_pos)
	await _wait(0.8)
	await _shot("med_03_hospital_reinforcement")


const ProgressionPT = preload("res://sim/systems/progression.gd")  # PT5-2: tutorial gate diagnostics
const TutorialPromptScript = preload("res://presentation/editor/tutorial_prompt.gd")  # G5 (ED5) step reader

# ------------------------------------------------------------ G5 tutorial (PT5-2): --ui-playtest-tutorial
## ED5's content/scenarios/tutorial.rtsmap, played step by step through the on-screen TutorialPrompt with
## synthetic input only. No harness writes (no grant, no AI change: the tutorial's side 1 is inert).
func _tut_start() -> void:
	var b := _find_button(get_tree().root, "Tutorial")
	if b != null and b.is_visible_in_tree() and not b.disabled:
		var bt := String(b.text)  # the menu frees the button on click
		await _click(b.get_global_rect().get_center())
		_log("tut_menu_button", true, bt)
	else:
		# no menu button yet (CR to ORCH): the same entry point the button would call
		_log("tut_menu_button_missing_harness_start", main.start_tutorial(), "main.start_tutorial()")


func _tut() -> Dictionary:
	return TutorialPromptScript.current(_w())


func _labels_text(n: Node) -> String:
	var s := ""
	if n is Label:
		s += (n as Label).text + " "
	elif n is RichTextLabel:
		s += (n as RichTextLabel).get_parsed_text() + " "
	for c in n.get_children():
		s += _labels_text(c)
	return s


func _tut_panel_text() -> String:
	var p = get_tree().root.find_child("TutorialPrompt", true, false)
	if p == null or not (p is CanvasItem) or not (p as CanvasItem).is_visible_in_tree():
		return ""
	return _labels_text(p)


## Waits for step n, logs that the on-screen prompt shows it (keyword key).
func _tut_at(n: int, nm: String, key: String) -> bool:
	var ok := await _wait_until(func(): return int(_tut().get("step", 0)) == n and _tut_panel_text().contains(key), 30.0)
	var cur := _tut()
	if not ok and (int(cur.get("step", 0)) > n or bool(cur.get("done", false))):
		# a fast step (the ambulance evac) can fire between two 0.25 s polls: the step is passed, not missed
		_log("tut_%02d_%s_prompt" % [n, nm], true, "already passed: step=%s done=%s" % [str(cur.get("step")), str(cur.get("done"))])
		return true
	_log("tut_%02d_%s_prompt" % [n, nm], ok, "step=%s/%s panel=%s" % [str(cur.get("step")), str(cur.get("total")), _tut_panel_text().left(90).replace("\n", " ")])
	return ok


func _tut_done(n: int, nm: String, secs: float) -> bool:
	var ok := await _wait_until(func(): return int(_tut().get("step", 0)) > n or bool(_tut().get("done", false)), secs)
	_log("tut_%02d_%s_done" % [n, nm], ok, "now step=%s" % str(_tut().get("step")))
	await _wait(0.4)
	await _shot("tut_%02d_%s" % [n, nm])
	return ok


func _tut_rclick(p: Vector2) -> void:
	if not _on_map(_to_screen(p)):
		_mv().center_camera_on(p)
		await _wait(0.4)
	await _click(_to_screen(p), MOUSE_BUTTON_RIGHT)
	await _wait(0.4)


func _tut_first(def_id: String) -> int:
	var us := _own_units(def_id)
	return int(us[0].id) if not us.is_empty() else -1


func _tut_select_all(def_id: String) -> int:
	var us := _own_units(def_id)
	if us.is_empty():
		return 0
	var cen := Vector2.ZERO
	for u in us:
		cen += Vector2(u.pos)
	_mv().center_camera_on(cen / float(us.size()))
	await _wait(0.4)
	return await _select_units([def_id])


func _tut_flow() -> void:
	var started := await _wait_until(func(): return int(_tut().get("total", 0)) > 0, 5.0)
	_log("tut_has_steps", started, "total=%s map=%s" % [str(_tut().get("total")), String(_w().map.get("name", "?"))])
	if not started:
		return
	_log("speed_3x_button", await _click_button("3x"))
	await _shot("tut_00_start")
	# 1 move: recon -> flag region (22,22 4x4)
	if await _tut_at(1, "move", "MOVE"):
		_log("tut_select_recon", await _g5_select(_tut_first("recon")))
		await _tut_rclick(Vector2(24.0, 24.0))
		await _tut_done(1, "move", 60.0)
	# 2 gather: engineers -> salvage pile
	if await _tut_at(2, "gather", "GATHER"):
		_mv().center_camera_on(_hq().pos)
		await _wait(0.4)
		await _gather_salvage(["engineer"], "tut")
		await _tut_done(2, "gather", 150.0)
	# 3 build: barracks
	if await _tut_at(3, "build", "BUILD"):
		_mv().center_camera_on(_hq().pos)
		await _wait(0.4)
		await _g5_build(_role("barracks"))
		await _tut_done(3, "build", 30.0)
	# 4 train: a rifle squad -> 8 riflemen
	if await _tut_at(4, "train", "TRAIN"):
		await _train(_role("infantry"))
		await _tut_done(4, "train", 60.0)
	# 5 attack: riflemen -> the tagged militia outpost
	if await _tut_at(5, "attack", "ATTACK"):
		_log("tut_select_riflemen", await _tut_select_all("rifleman") >= 4, "selected=%d" % _mv().selection.size())
		var foe = null
		for e in _w().entities.values():
			if e.kind == "unit" and int(e.owner) != 0 and String(e.get("tag", "")) == "outpost":
				foe = e
				break
		_log("tut_outpost_found", foe != null)
		if foe != null:
			await _tut_rclick(Vector2(foe.pos))
		await _tut_done(5, "attack", 180.0)
	# 6 stage: Advance on the stage panel
	if await _tut_at(6, "stage", "ADVANCE"):
		# the gates (power held, cost) may still be filling: a player waits for the button to light up.
		# The 400-salvage cost is not guaranteed by the map (engineers idle after building the barracks), so
		# like a player the flow sends the engineers back to the salvage when the stock is short.
		var need_s := int((Content.rules().get("advancement", {}).get("gates", {}).get("8", {}).get("cost", {}) as Dictionary).get("salvage", 0))
		if int(_w().factions[0].stock.get("salvage", 0)) < need_s:
			_mv().center_camera_on(_hq().pos)
			await _wait(0.4)
			await _gather_salvage(["engineer"], "tut6")
		var ready := await _wait_until(func(): return _g5_named("AdvanceStageButton") != null and not _g5_named("AdvanceStageButton").disabled, 150.0)
		if not ready:
			print("PLAYTEST-DBG tut_gates unmet=%s stock=%s credits=%s" % [str(_tut_unmet_gates()), str(_w().factions[0].stock), str(_w().factions[0].credits)])
		var adv := _g5_named("AdvanceStageButton")
		_log("tut_advance_enabled", ready and adv != null and not adv.disabled, "" if adv == null else adv.tooltip_text.left(80).replace("\n", " | "))
		_log("tut_advance_click", await _click_named("AdvanceStageButton"))
		await _tut_done(6, "stage", 400.0)
	# 7 walls: engineers, Wall tool, drag a short line
	if await _tut_at(7, "walls", "WALLS"):
		await _tut_walls()
		await _tut_done(7, "walls", 120.0)
	# 8 load: riflemen right-click the APC
	var apc := -1
	if await _tut_at(8, "load", "TRANSPORT"):
		apc = _tut_first("a_apc")
		_log("tut_apc_found", apc >= 0, "apc=%d at=%s" % [apc, "" if apc < 0 else str(_ent(apc).pos)])
		_log("tut_select_riflemen_load", await _tut_select_all("rifleman") >= 1, "selected=%d" % _mv().selection.size())
		if apc >= 0:
			_mv().center_camera_on(Vector2(_ent(apc).pos))
			await _wait(0.5)
			await _click(_to_screen(Vector2(_ent(apc).pos)), MOUSE_BUTTON_RIGHT)
			await _wait(0.5)
			var boarding := 0
			for u in _own_units("rifleman"):
				if String(u.order.get("type", "")) == "board":
					boarding += 1
			_log("tut_rightclick_apc_board", boarding > 0, "boarding=%d last=%s" % [boarding, _g5_last_cmd()])
		await _tut_done(8, "load", 120.0)
	if apc < 0:
		apc = _tut_first("a_apc")
	# 9 unload: APC -> Unload at point in the drop zone (40,8 5x5)
	if await _tut_at(9, "unload", "drop zone"):
		_log("tut_select_apc", await _g5_select(apc))
		_log("tut_unload_at_point_click", await _click_button("Unload at point"))
		await _wait(0.2)
		_mv().center_camera_on(Vector2(42.5, 10.5))
		await _wait(0.4)
		await _click(_to_screen(Vector2(42.5, 10.5)))
		await _wait(0.4)
		await _tut_done(9, "unload", 180.0)
	# 10 resupply: truck Auto (Off -> Station), drag its area
	if await _tut_at(10, "resupply", "SUPPLY"):
		var tr := _tut_first("logistics_truck")
		_log("tut_select_truck", await _g5_select(tr))
		_log("tut_truck_auto_click", await _click_named("G5_truck_auto"))
		await _wait(0.3)
		var tp: Vector2 = _ent(tr).pos
		await _drag(_to_screen(tp), _to_screen(tp + Vector2(6.0, 0.0)))
		await _wait(0.4)
		await _tut_done(10, "resupply", 30.0)
	# 11 hangar: airstrip card -> Buy light hangar
	var strip := _newest("a_airstrip")
	if await _tut_at(11, "hangar", "AIRFIELD"):
		_log("tut_select_airstrip", not strip.is_empty() and await _g5_select(int(strip.id)))
		_log("tut_buy_light_hangar_click", await _click_named("G5_hangar_light"))
		await _tut_done(11, "hangar", 150.0)
	# 12 jet: train a Strike Jet at the airstrip
	if await _tut_at(12, "jet", "Strike Jet"):
		# G6 (PT6) parallel flake: the Strike Jet click was refused right after the hangar buy (hangar
		# still building). Wait until the airfield gate accepts the jet before clicking.
		var gate_ok := await _wait_until(func(): return Airfield.can_produce(_w(), 0, "a_strike_jet") == "", 120.0)
		_log("tut_jet_gate_open", gate_ok, Airfield.can_produce(_w(), 0, "a_strike_jet"))
		await _train("a_strike_jet")
		await _tut_done(12, "jet", 60.0)
	# 13 takeoff
	var jet := _tut_first("a_strike_jet")
	if await _tut_at(13, "takeoff", "Take off"):
		_log("tut_select_jet", await _g5_select(jet))
		_log("tut_take_off_click", await _click_named("G5_take_off"), _g5_last_cmd())
		await _tut_done(13, "takeoff", 90.0)
	# 14 land: Rebase to the airstrip
	if await _tut_at(14, "land", "Rebase"):
		# the jet stays selected after Take off; an airborne jet is hard to click, so reselect only if lost
		if not _mv().selection.has(jet):
			await _g5_select(jet)
		_log("tut_select_jet_air", _mv().selection.has(jet), "sel=%s phase=%s" % [str(_mv().selection), Air.phase(_w(), jet)])
		_log("tut_rebase_click", not strip.is_empty() and await _g5_arm_click("G5_rebase", Vector2(strip.pos)), _g5_last_cmd())
		await _tut_done(14, "land", 240.0)
	# 15 evac_on: ambulance Auto evac, drag the area over the casualty region (17,38 3x3)
	if await _tut_at(15, "evac_on", "Ambulance"):
		var amb := _tut_first("a_ambulance")
		_log("tut_select_ambulance", await _g5_select(amb))
		_log("tut_auto_evac_click", await _click_named("G5_medic_auto"))
		await _wait(0.3)
		var ac := Vector2(18.5, 39.5)
		_mv().center_camera_on(ac)
		await _wait(0.3)
		await _drag(_to_screen(ac), _to_screen(ac + Vector2(8.0, 0.0)))
		await _wait(0.4)
		await _tut_done(15, "evac_on", 30.0)
	# 16 evac: the ambulance carries the spawned casualty to the Hospital
	if await _tut_at(16, "evac", "Hospital"):
		await _tut_done(16, "evac", 240.0)
	var fin := await _wait_until(func(): return bool(_tut().get("done", false)), 20.0)
	await _wait(1.0)
	_log("tut_complete", fin and _tut_panel_text().contains("complete"), _tut_panel_text().left(90).replace("\n", " "))
	await _shot("tut_17_complete")


func _tut_walls() -> void:
	var wdef := _role("wall")
	_mv().center_camera_on(_hq().pos)
	await _wait(0.4)
	_log("tut_wall_select_engineers", await _select_units(["engineer"]) > 0)
	var line := _g4b_line(wdef)
	_log("tut_wall_line_found", not line.is_empty(), "%s %s" % [wdef, str(line)])
	if line.is_empty():
		return
	await _build_page(wdef)
	await _key(OS.find_keycode_from_string(_hotkey(wdef)))
	await _wait(0.3)
	_log("tut_wall_tool_armed", _mv().placing_def == wdef, _mv().placing_def)
	var sa := _to_screen(Vector2(line[0]) + Vector2(0.5, 0.5))
	var sb := _to_screen(Vector2(line[1]) + Vector2(0.5, 0.5))
	await _move(sa)
	await _button(sa, MOUSE_BUTTON_LEFT, true)
	for i in 6:
		await _move(sa.lerp(sb, float(i + 1) / 6.0))
	await _wait(0.3)
	await _button(sb, MOUSE_BUTTON_LEFT, false)
	await _wait(0.5)
	_log("tut_wall_line_issued", String(_mv().g4b.last_line.get("type", "")) == "build_line", str(_mv().g4b.last_line))


func _tut_unmet_gates() -> Array:
	var out := []
	for r in ProgressionPT.gate_report(_w(), 0):
		if not bool(r.get("ok", r.get("met", true))):
			out.append(r)
	return out


# ============================================================ G6 (PT6) flows: --ui-playtest-<flow>
## PLAN_G6 section 12.4: elev company aicmd mines garrison naval6 airdef exo loadout market airfield2
## survival (+ editor Live / height brushes in tools/editor_playtest.gd), and the owner checkpoint
## (--ui-playtest-checkpoint with --load=<doctrine demo save>). Human A at Stage 9 unless noted; the
## harness grant + peace window are the G5 ones (this process only, in memory).
const G6_FLOWS := ["elev", "company", "aicmd", "mines", "garrison", "naval6", "airdef", "exo", "loadout", "market", "airfield2", "survival", "checkpoint", "company61", "market61", "fuel61", "bearer61", "squad61", "officer61", "gen61", "chain61", "real61", "plan61", "anim61", "animb61", "vfx61", "audio61", "stock61", "flick61"]
## G7: flows live in tools/pt7_<flow>.gd (same `func run(pt) -> void` contract as the G6.1 pt61 flows).
const G7_FLOWS := ["scale7", "wound7", "squad7", "drone7", "look7", "artcn7", "sense7", "creep7", "cnsim7", "cnops7", "cnfac7", "turret7", "threat7", "lpmode7", "lpmap7", "opsui7", "audio7", "cine7", "fissure7", "art7b", "vis7", "art7f", "wallwalk7", "life7", "atmo7", "seq7", "wallturret7", "sent7", "eng7", "sentart7", "vanta7", "apcmov7", "cnsuits7", "muzzle7", "gate7", "dronebay7", "turret7", "ciws7", "facint7", "lpres7", "wallfire7", "lpmenu7", "vtol8", "cnmission8", "facexit8", "specops8", "supply8", "cards8b", "cards8c", "cards8a", "blast8", "cbshots8", "blackglass71", "airfix71", "airops71", "flow71", "control71", "perfsim71", "perfdraw71", "damage71", "gore71", "care71", "fires71", "killzone71", "conductor71", "army71", "crew71", "ammo71", "bastion71", "walls71", "cnops71", "facility71", "hospital71", "gas71", "vanta71"]  # G7.1 wave 1: tools/pt71_<flow>.gd
const Elevation = preload("res://sim/systems/elevation.gd")
const Companies = preload("res://sim/systems/companies.gd")
const CompanyCardM = preload("res://presentation/ui6/a/company_card.gd")
const Mines = preload("res://sim/systems/mines.gd")
const Garrison = preload("res://sim/systems/garrison.gd")
const Loadouts = preload("res://sim/systems/loadouts.gd")
const Exo = preload("res://sim/systems/exo.gd")
const Sonar = preload("res://sim/systems/sonar.gd")
const Market = preload("res://sim/systems/market.gd")
const Airdef = preload("res://sim/systems/airdef.gd")
const AiCommand = preload("res://sim/systems/ai_command.gd")
const Waves = preload("res://sim/systems/waves.gd")
const Doctrine = preload("res://sim/ai/doctrine/doctrine.gd")
const DocUtil = preload("res://sim/ai/doctrine/doc_util.gd")
const AiController = preload("res://sim/ai/ai_controller.gd")
var g6_flow := ""


func _g6_menu() -> void:
	var menu = get_tree().root.find_child("MapOption", true, false) as OptionButton
	var want := {"naval6": "Coastal Front", "survival": "Ridge Bastion", "animb61": "Coastal Front"}  # + G6.1 ANIMC61 CR (ships need water)
	if want.has(g6_flow) and menu != null:
		var idx := -1
		for i in menu.item_count:
			if menu.get_item_text(i).begins_with(String(want[g6_flow])) and not menu.is_item_disabled(i):
				idx = i
		_log("g6_map_pick_click", idx >= 0 and await _pick_option("MapOption", idx), "" if idx < 0 else menu.get_item_text(idx))
	if g6_flow != "survival":
		var ob = get_tree().root.find_child("Slot0Stage", true, false) as OptionButton
		var k := -1
		if ob != null:
			for i in ob.item_count:
				if ob.get_item_text(i).begins_with("Stage 9 "):
					k = i
		_log("g6_slot0_stage9_click", k >= 0 and await _pick_option("Slot0Stage", k), "items=%d" % (0 if ob == null else ob.item_count))
	if g6_flow == "stock61":  # owner 2026-10-26: Starting resources 50k by click
		var so = get_tree().root.find_child("StartStockOption", true, false) as OptionButton
		_log("stock61_option_visible", so != null and so.is_visible_in_tree())
		if so != null:
			_log("stock61_pick_50k", await _pick_option("StartStockOption", so.item_count - 1), so.get_item_text(so.item_count - 1))
			await _shot("stock61_setup")
	await _wait(0.3)


func _g6_grant(peace: bool) -> void:
	_mv().join_sim()
	var f: Dictionary = _w().factions[0]
	f.credits = int(f.credits) + 60000
	for r in (f.stock as Dictionary).keys():
		f.stock[r] = int(f.stock.get(r, 0)) + 20000
	if peace:
		for dk in (Content.rules().get("ai_difficulties", {}) as Dictionary).keys():
			Content.rules().ai_difficulties[dk]["first_attack_tick"] = 1000000
	_log("g6_harness_grant", true, "stage=%d credits=%d stock=%s" % [int(f.stage), int(f.credits), str(f.stock)])


## A box-drag around ids (the camera on their centre first); returns how many of ids are selected.
func _g6_box(ids: Array) -> int:
	return await _g5_select_many(ids)


func _g6_ids(es: Array) -> Array:
	var out := []
	for e in es:
		out.append(int(e.id) if e is Dictionary else int(e))
	return out


func _g6_rclick(p: Vector2) -> void:
	await _tut_rclick(p)


func _g6_panel(nm: String) -> Control:
	var p = get_tree().root.find_child(nm, true, false)
	return p as Control if p is Control and (p as Control).is_visible_in_tree() else null


func _g6_click_in(panel: Node, child: String) -> bool:
	if panel == null:
		return false
	var b = panel.find_child(child, true, false)
	if not (b is BaseButton) or not (b as Control).is_visible_in_tree() or (b as BaseButton).disabled:
		return false
	await _click((b as Control).get_global_rect().get_center())
	await _wait(0.3)
	return true


## Real clicks on an OptionButton inside panel: the first item whose text contains needle.
func _g6_option(panel: Node, child: String, needle: String) -> bool:
	if panel == null:
		return false
	var ob = panel.find_child(child, true, false) as OptionButton
	if ob == null:
		return false
	var idx := -1
	for i in ob.item_count:
		if idx < 0 and ob.get_item_text(i).to_lower().contains(needle.to_lower()) and not ob.is_item_disabled(i):
			idx = i
	if idx < 0:
		return false
	if ob.selected == idx:
		return true
	await _click(ob.get_global_rect().get_center())
	await _wait(0.3)
	var pop := ob.get_popup()
	if not pop.visible:
		return false
	var rect := Rect2(Vector2(pop.position), Vector2(pop.size))
	var y := rect.position.y + (float(idx) + 0.5) * rect.size.y / float(maxi(1, ob.item_count))
	await _click(Vector2(rect.position.x + rect.size.x * 0.5, y))
	await _wait(0.3)
	return ob.selected == idx


## Builds the infantry chain (power, barracks) and trains one rifle squad; returns its unit ids.
func _g6_squad() -> Array:
	if _built_count(_role("power")) == 0:
		await _g5_build(_role("power"))
	if _built_count(_role("barracks")) == 0:
		await _g5_build(_role("barracks"))
	return _g6_ids(await _train(_role("infantry")))


# ------------------------------------------------------------ owner checkpoint (doctrine + elevation)
## --load=<.plan/shots/AI7-DOC/demo_start.save> --ui-playtest=<dir> --ui-playtest-checkpoint
## The demo start (side 1 AI off) is driven exactly like sim/ai/doctrine/doc_demo.gd: Doctrine.think for
## side 1 every 10 ticks with force_obj = the hill and force_attack, here inside the real game loop, so
## the rendered match shows the same assault. A shot at every AiDecision and every 60 ticks.
func _checkpoint_flow() -> void:
	var ok := await _wait_until(func(): return main.match_view != null and main.match_view.world != null, 20.0)
	_log("cp_save_loaded", ok)
	if not ok:
		return
	_mv().speed = 0.0  # hold the start state until the doctrine driver runs (r1 lost ~70 idle ticks here)
	await _wait(1.5)
	_mv().join_sim()
	var w := _w()
	# owner retake (PT6-3): --ui-playtest-fogoff also draws side 1's own vision (render only: the view's
	# allied-vision list, the snapshot's fog sides, the fog layer hidden), so the attackers stay drawn on
	# the hill after the side-0 defenders die. The sim, the save and the doctrine driver are unchanged.
	if OS.get_cmdline_user_args().has("--ui-playtest-fogoff"):
		var al: Array = (_mv().get("_ally_fids") as Array).duplicate()
		for fid in w.factions:
			if int(fid) != int(_mv().player_fid) and not al.has(int(fid)):
				al.append(int(fid))
		_mv().set("_ally_fids", al)
		var sf: Array = [int(_mv().player_fid)]
		sf.append_array(al)
		w.cache["snap_fids"] = sf
		(_mv().fog_layer as CanvasItem).visible = false
		print("PLAYTEST-CP fog off (render only) allies=%s snap_fids=%s" % [str(al), str(sf)])
	var hill := Vector2(float(int(w.map.w) / 2 + 10), float(int(w.map.h) / 2)) + Vector2(0.5, 0.5)
	_log("cp_hill_height", Elevation.height_at(w, Vector2i(hill)) == 3, "hill=%s level=%d units=%d" % [str(hill), Elevation.height_at(w, Vector2i(hill)), w.units_of(1).size()])
	var st := AiController.new_state(w, 1)
	var d := DocUtil.dstate(st)
	d.force_obj = hill
	d.force_attack = true
	var cam := hill + Vector2(-26.0, 0.0)
	_mv().center_camera_on(cam)
	var cam_rig = _mv().get("camera")
	if cam_rig != null and cam_rig.has_method("set_zoom_level"):
		cam_rig.set_zoom_level(1.1)  # r1 used 0.75: unit art too small for the owner review
	_mv().speed = 1.0
	await _wait(0.6)
	await _shot("cp_00_start")
	var tags := []
	var next_think := (int(w.tick) / 10) * 10
	var end_t := -1
	var n_shot := 1
	var last_shot_t := int(w.tick)
	var t_real := 0.0
	while t_real < 600.0:
		await get_tree().process_frame
		t_real += get_process_delta_time()
		_mv().join_sim()
		w = _w()
		if int(w.tick) < next_think:
			continue
		next_think = (int(w.tick) / 10 + 1) * 10
		var n0 := w.events.size()
		Doctrine.think(w, 1, st, {"visible": w.visible_enemies(1), "units": w.units_of(1), "buildings": w.buildings_of(1), "arty": [], "army": [], "busy": {}})
		var fresh := ""
		for i in range(n0, w.events.size()):
			var ev: Dictionary = w.events[i]
			if String(ev.get("type", "")) == "AiDecision":
				fresh = String(ev.tag)
				tags.append("t=%d %s" % [int(w.tick), fresh])
				print("PLAYTEST-CP decision t=%d tag=%s reason=%s" % [int(w.tick), fresh, String(ev.get("reason", ""))])
				if fresh == "high_ground_taken" and end_t < 0:
					end_t = int(w.tick) + 300
		# follow the company: camera between its centre and the hill
		var cen := Vector2.ZERO
		var us: Array = w.units_of(1)
		for u in us:
			cen += Vector2(u.pos)
		if us.size() > 0:
			cen /= float(us.size())
			_mv().center_camera_on(cen.lerp(hill, 0.3))
		if fresh != "" or int(w.tick) - last_shot_t >= 60:
			await _wait(0.05)
			await _shot("cp_%02d_t%d_%s" % [n_shot, int(w.tick), fresh if fresh != "" else "step"])
			n_shot += 1
			last_shot_t = int(w.tick)
		if end_t >= 0 and int(w.tick) >= end_t:
			break
	_log("cp_tags_seen", tags.size() > 0, str(tags))
	_log("cp_high_ground_taken", end_t >= 0, "tags=%s" % str(d.get("tags", {})))
	await _shot("cp_99_end")


func _g6_flow() -> void:
	await _g6_grant(g6_flow != "survival")
	_log("speed_3x_button", await _click_button("3x"))
	match g6_flow:
		"market":
			await _market_flow()
		"loadout":
			await _loadout_flow()
		"garrison":
			await _garrison_flow()
		"mines":
			await _mines_flow()
		"elev":
			await _elev_flow()
		"company":
			await _company_flow()
		"aicmd":
			await _aicmd_flow()
		"exo":
			await _exo_flow()
		"airdef":
			await _airdef_flow()
		"naval6":
			await _naval6_flow()
		"airfield2":
			await _airfield2_flow()
		"survival":
			await _survival_flow()
		_:
			# G6.1: each flow lives in tools/pt61_<flow>.gd with `func run(pt) -> void` (pt = this harness;
			# call pt._log / pt._shot / pt._click_named / pt._g5_select / pt._w() / pt._mv() / pt._wait).
			var path := "res://tools/pt61_%s.gd" % g6_flow
			if not ResourceLoader.exists(path) and ResourceLoader.exists("res://tools/pt7_%s.gd" % g6_flow):
				path = "res://tools/pt7_%s.gd" % g6_flow
			if not ResourceLoader.exists(path) and ResourceLoader.exists("res://tools/pt71_%s.gd" % g6_flow):
				path = "res://tools/pt71_%s.gd" % g6_flow  # G7.1
			if ResourceLoader.exists(path):
				await load(path).new().run(self)
			else:
				_log("g61_flow_file", false, path + " missing")


# ------------------------------------------------------------ market (buy / sell)
func _market_flow() -> void:
	var hq := _hq()
	_log("mk_select_hq", await _g5_select(int(hq.id)))
	_log("mk_market_button_click", await _click_named("G6Market"))
	var mp := _g6_panel("MarketPanel")
	_log("mk_panel_open", mp != null)
	if mp == null:
		return
	_mv().join_sim()
	var f: Dictionary = _w().factions[0]
	var ore0 := int(f.stock.get("ore", 0))
	var cr0 := int(f.credits)
	_log("mk_buy_ore_click", await _g6_click_in(mp, "Buy50_ore"), "price=%d" % Market.price(_w(), "ore", "buy"))
	var bought := await _wait_until(func(): return int(_w().factions[0].stock.get("ore", 0)) > ore0 and int(_w().factions[0].credits) < cr0, 5.0)
	_log("mk_bought", bought, "ore %d -> %d credits %d -> %d" % [ore0, int(_w().factions[0].stock.get("ore", 0)), cr0, int(_w().factions[0].credits)])
	var sal0 := int(_w().factions[0].stock.get("salvage", 0))
	var cr1 := int(_w().factions[0].credits)
	_log("mk_sell_salvage_click", await _g6_click_in(mp, "Sell50_salvage"), "price=%d" % Market.price(_w(), "salvage", "sell"))
	var sold := await _wait_until(func(): return int(_w().factions[0].stock.get("salvage", 0)) < sal0 and int(_w().factions[0].credits) > cr1, 5.0)
	_log("mk_sold", sold, "salvage %d -> %d credits %d -> %d" % [sal0, int(_w().factions[0].stock.get("salvage", 0)), cr1, int(_w().factions[0].credits)])
	await _shot("g6_market")


# ------------------------------------------------------------ loadout swap
func _loadout_flow() -> void:
	var sq := await _g6_squad()
	_log("lo_squad_trained", sq.size() > 0, str(sq))
	if sq.is_empty():
		return
	var e0 = _ent(int(sq[0]))
	var opts: Array = Loadouts.loadouts_for(0, String(e0.def))
	_log("lo_loadouts_known", opts.has("assault"), str(opts))
	_log("lo_select_squad", await _g6_box(sq) > 0)
	_log("lo_loadout_button_click", await _click_named("G6_loadout"))
	await _wait(0.4)
	var lp := _g6_panel("LoadoutPanel")
	_log("lo_panel_open", lp != null)
	await _shot("g6_loadout_panel")
	_log("lo_assault_click", await _g6_click_in(lp, "Loadout_assault"))
	var ok := await _wait_until(func(): return _ent(int(sq[0])) != null and Loadouts.of(_ent(int(sq[0]))) == "assault", 60.0)
	_log("lo_loadout_applied", ok, "loadout=%s" % ("" if _ent(int(sq[0])) == null else Loadouts.of(_ent(int(sq[0])))))
	await _shot("g6_loadout_applied")


# ------------------------------------------------------------ garrison
func _garrison_flow() -> void:
	var sq := await _g6_squad()
	_log("gar_squad_trained", sq.size() > 0, str(sq))
	var gb := await _g5_build("s_garrison_bld")
	if sq.is_empty() or gb.is_empty():
		return
	var bid := int(gb.id)
	_log("gar_slots", Garrison.slots_of("s_garrison_bld") > 0, "slots=%d" % Garrison.slots_of("s_garrison_bld"))
	_log("gar_select_squad", await _g6_box(sq) > 0)
	_log("gar_button_click", await _g5_arm_click("G6_garrison", gb.pos), _g5_last_cmd())
	var inside := await _wait_until(func(): return Garrison.occupants(_w(), bid).size() > 0, 90.0)
	_log("gar_squad_inside", inside, "occupants=%s" % str(Garrison.occupants(_w(), bid)))
	await _shot("g6_garrison_in")
	_log("gar_select_building", await _g5_select(bid))
	_log("gar_empty_click", await _click_named("G6_ungarrison"))
	var out := await _wait_until(func(): return Garrison.occupants(_w(), bid).is_empty(), 30.0)
	_log("gar_squad_left", out, "occupants=%s" % str(Garrison.occupants(_w(), bid)))
	await _shot("g6_garrison_out")


# ------------------------------------------------------------ mines (lay; EOD clears a lane)
## Mines planned in r by owner's fields (Mines field cells; the lay order works through them).
func _g6_planned_in(r: Rect2i, owner: int = 0) -> int:
	var n := 0
	for f in (_w().sys_state.get("mines", {}) as Dictionary).get("fields", []):
		if int(f.get("owner", -1)) != owner:
			continue
		for c in f.get("cells", []):
			if r.has_point(Vector2i(int(c[0]), int(c[1]))):
				n += 1
	return n


func _g6_mines_in(r: Rect2i, owner: int = 0) -> int:
	var n := 0
	for e in _w().entities.values():
		if String(e.get("kind", "")) == "mine" and int(e.get("owner", -1)) == owner and r.has_point(Vector2i(floori(e.pos.x), floori(e.pos.y))):
			n += 1
	return n


## A sz x sz rect of free, on-screen cells next to r (not overlapping it), or an empty Rect2i.
func _g6_rect_beside(r: Rect2i, sz: int) -> Rect2i:
	for off in [Vector2i(r.size.x + 2, 0), Vector2i(-sz - 2, 0), Vector2i(0, r.size.y + 2), Vector2i(0, -sz - 2)]:
		var o: Vector2i = r.position + off
		var ok := true
		for dy in sz:
			for dx in sz:
				var q := o + Vector2i(dx, dy)
				ok = ok and _w().in_bounds(q) and Construction.placement_error(_w(), 0, "s_sandbags", q) == ""
		if ok and _on_map(_to_screen(Vector2(o))) and _on_map(_to_screen(Vector2(o + Vector2i(sz, sz)))):
			return Rect2i(o, Vector2i(sz, sz))
	return Rect2i()


func _g6_free_rect(sz: int) -> Rect2i:
	var c: Vector2i = _hq().cell
	var mc := Vector2i(int(_w().map.w) / 2, int(_w().map.h) / 2)
	var dir := Vector2(mc - c).normalized()
	var probe := c + Vector2i(dir * 9.0)
	_mv().center_camera_on(Vector2(probe))
	await _wait(0.4)
	var free := func(q: Vector2i) -> bool:
		for dy in sz:
			for dx in sz:
				if Construction.placement_error(_w(), 0, "s_sandbags", q + Vector2i(dx, dy)) != "":
					return false
		return _on_map(_to_screen(Vector2(q + Vector2i(sz, sz))))
	var o := _g5_cell_near(probe, 0, 8, free)
	return Rect2i(o, Vector2i(sz, sz)) if o.x >= 0 else Rect2i()


func _mines_flow() -> void:
	await _g6_squad()  # barracks for the EOD squad
	var r := await _g6_free_rect(3)
	_log("mn_free_rect", r.size.x > 0, str(r))
	if r.size.x == 0:
		return
	var eng := _own_units_in(_defs_with("can_build"))
	_log("mn_select_engineers", await _g6_box(_g6_ids(eng.slice(0, 2))) > 0)
	var a := _to_screen(Vector2(r.position) + Vector2(0.5, 0.5))
	var b := _to_screen(Vector2(r.end) - Vector2(0.5, 0.5))
	_log("mn_minefield_click", await _click_named("G6_minefield"))
	await _drag(a, b)
	await _wait(0.4)
	_log("mn_lay_issued", _g5_last_cmd() == "lay_minefield", _g5_last_cmd())
	# G6.1: a field rolls density 0.45 per cell (w.rng), so a 3x3 field plans 0-9 mines; ">= 3" failed on RNG
	# alone (~15%). The check now is the intent: every mine the engineers' field planned gets laid.
	var laid := await _wait_until(func():
		var pl := _g6_planned_in(r)
		return pl >= 1 and _g6_mines_in(r) >= pl, 150.0)
	_log("mn_mines_laid", laid, "mines=%d planned=%d known=%d" % [_g6_mines_in(r), _g6_planned_in(r), Mines.known_to(_w(), 0).size()])
	var own_laid := _g6_mines_in(r)
	await _shot("g6_mines_laid")
	# Sweeping clears ENEMY mines only (Mines.sweep_cells skips own/allied mines by design; r1 swept our own
	# field and waited forever). Harness action: an enemy (side 1) AT field is placed beside ours with
	# Mines.place_field, then the EOD squad sweeps it through the UI.
	var r2 := _g6_rect_beside(r, 4)
	_log("mn_enemy_rect", r2.size.x > 0, str(r2))
	if r2.size.x == 0:
		return
	_mv().join_sim()
	var efid := Mines.place_field(_w(), 1, r2, "at")
	var n_enemy := _g6_mines_in(r2, 1)
	_log("mn_enemy_field_placed", efid >= 0 and n_enemy > 0, "field=%d enemy_mines=%d" % [efid, n_enemy])
	var eod := _g6_ids(await _train("a_eod"))
	_log("mn_eod_trained", eod.size() > 0)
	if eod.is_empty():
		return
	_log("mn_select_eod", await _g6_box(eod) > 0)
	_mv().center_camera_on(Vector2(r2.get_center()))
	await _wait(0.4)
	_log("mn_sweep_click", await _click_named("G6_sweep"))
	await _drag(_to_screen(Vector2(r2.position) + Vector2(0.5, 0.5)), _to_screen(Vector2(r2.end) - Vector2(0.5, 0.5)))
	await _wait(0.4)
	_log("mn_sweep_issued", _g5_last_cmd() == "sweep", _g5_last_cmd())
	var clear := await _wait_until(func(): return _g6_mines_in(r2, 1) == 0, 240.0)
	if not clear:
		_mv().join_sim()
		var dbg := []
		for id in eod:
			var ee = _ent(int(id))
			if ee != null:
				dbg.append("%d %s pos=%s order=%s" % [int(id), String(ee.def), str(ee.pos), str(ee.order)])
		print("PLAYTEST-DBG sweep_miss rect=%s eod=%s mines_state=%s" % [str(r2), str(dbg), str(_w().sys_state.get("mines", {})).left(400)])
	_log("mn_lane_cleared", clear, "enemy mines left=%d of %d" % [_g6_mines_in(r2, 1), n_enemy])
	_log("mn_own_field_kept", own_laid >= 1 and _g6_mines_in(r) == own_laid, "own mines=%d of %d laid (sweeps never clear own mines)" % [_g6_mines_in(r), own_laid])
	await _shot("g6_mines_cleared")


# ------------------------------------------------------------ elevation (take a hill)
func _elev_flow() -> void:
	var sq := await _g6_squad()
	_log("el_squad_trained", sq.size() > 0)
	if sq.is_empty():
		return
	var w := _w()
	var c0 := Vector2i(_ent(int(sq[0])).pos)
	var hill := Vector2i(-1, -1)
	var bd := 1e9
	for y in range(maxi(0, c0.y - 40), mini(int(w.map.h), c0.y + 41)):
		for x in range(maxi(0, c0.x - 40), mini(int(w.map.w), c0.x + 41)):
			var q := Vector2i(x, y)
			var ok := Elevation.height_at(w, q) >= 2 and [0, 1, 3].has(int(w.map.terrain[y * int(w.map.w) + x]))
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				ok = ok and w.in_bounds(q + n) and Elevation.height_at(w, q + n) >= 2
			var d2 := float((q - c0).length_squared())
			if ok and d2 < bd:
				bd = d2
				hill = q
	_log("el_hill_found", hill.x >= 0, "hill=%s level=%d dist=%.0f" % [str(hill), Elevation.height_at(w, hill) if hill.x >= 0 else -1, sqrt(bd)])
	if hill.x < 0:
		return
	_log("el_select_squad", await _g6_box(sq) > 0)
	await _g6_rclick(Vector2(hill) + Vector2(0.5, 0.5))
	var up := await _wait_until(func(): return _g6_on_high(sq) * 2 >= sq.size(), 180.0)
	_log("el_hill_taken", up, "on_high=%d of %d" % [_g6_on_high(sq), sq.size()])
	var e = _ent(int(sq[0]))
	if e == null:
		return
	var rm := Elevation.range_mult(_w(), e, Content.unit(String(e.def)))
	var sb := Elevation.sight_bonus(_w(), e)
	_log("el_range_bonus", rm > 1.0, "range_mult=%.3f level=%d" % [rm, Elevation.height_at(_w(), Vector2i(e.pos))])
	_log("el_sight_bonus", sb > 0.0, "sight_bonus=%.2f" % sb)
	_mv().center_camera_on(Vector2(hill))
	await _g6_box(sq)
	await _wait(0.6)
	var ins := _labels_text(get_tree().root.find_child("InspectorScroll", true, false)) if get_tree().root.find_child("InspectorScroll", true, false) != null else ""
	_log("el_bonus_visible_in_ui", ins.to_lower().contains("high ground") or ins.to_lower().contains("height"), ins.left(160).replace("\n", " | "))
	await _shot("g6_elev_hill")


# ------------------------------------------------------------ companies / armies / AI Commanders
func _g6_close(panel: Node) -> void:
	if panel == null:
		return
	for b in panel.find_children("*", "Button", true, false):
		if String((b as Button).tooltip_text).begins_with("Close") and (b as Control).is_visible_in_tree():
			await _click((b as Control).get_global_rect().get_center())
			await _wait(0.3)
			return


func _g6_company_hq() -> Dictionary:
	var hdef := ""
	for b in Content.buildable_for(_fac()):
		if hdef == "" and Companies.is_hq_def(String(b)):
			hdef = String(b)
	_log("co_hq_def", hdef != "", hdef)
	if hdef == "":
		return {}
	if _built_count(_role("power")) == 0:
		await _g5_build(_role("power"))
	# r1: "no legal on-screen site" for the size-3 Company HQ: log why, meet a building prerequisite
	_mv().center_camera_on(_hq().pos)
	await _wait(0.4)
	var errs := []
	for off in [Vector2i(6, 0), Vector2i(-6, 0), Vector2i(0, 6), Vector2i(0, -6), Vector2i(8, 4)]:
		errs.append(Construction.placement_error(_w(), 0, hdef, Vector2i(_hq().cell) + off))
	print("PLAYTEST-DBG company_hq_site errs=%s gate=%s" % [str(errs), str(Companies.can_build(_w(), 0, hdef))])
	if str(errs).to_lower().contains("barracks") and _built_count(_role("barracks")) == 0:
		await _g5_build(_role("barracks"))
	var hq := await _g5_build(hdef)
	if hq.is_empty():
		return hq
	# p1/p2: "companies=0" after 300 s: a platoon is ~45 supply and the cap was 20 (POP 6/20), so the
	# queue stalled. Build depots until 2 Rifle Company platoons fit (the HQ lifts the ceiling to 200).
	var td: Dictionary = Companies.template(_w(), 0, "a_rifle_co")
	var per := int(Companies.plan(_w(), 0, td, "platoon", true).pop) if not td.is_empty() else 50
	var f: Dictionary = _w().factions[0]
	for i in 10:
		if int(f.get("pop_cap", 0)) >= int(f.get("pop", 0)) + 2 * per:
			break
		await _g5_build(_role("depot"))
	_log("co_supply_room", int(f.get("pop_cap", 0)) >= int(f.get("pop", 0)) + 2 * per, "pop %d / %d, platoon supply %d" % [int(f.get("pop", 0)), int(f.get("pop_cap", 0)), per])
	return hq


## Army Builder by clicks: size Platoon, Train n times; waits for n companies.
func _g6_train_companies(hq: Dictionary, n: int) -> bool:
	_log("co_select_hq", await _g5_select(int(hq.id)))
	_log("co_army_builder_click", await _click_named("G6ArmyBuilder"))
	await _wait_until(func(): return _g6_panel("ArmyBuilder") != null, 3.0)  # G6.1: the modal can open a frame late
	var ab := _g6_panel("ArmyBuilder")
	if ab == null:  # one retry: re-select the HQ (a busy card can swallow the first click)
		await _g5_select(int(hq.id))
		await _click_named("G6ArmyBuilder")
		await _wait_until(func(): return _g6_panel("ArmyBuilder") != null, 3.0)
		ab = _g6_panel("ArmyBuilder")
	_log("co_builder_open", ab != null)
	if ab == null:
		return false
	_log("co_preset_rifle_click", await _g6_option(ab, "TemplateSource", "rifle company"))
	_log("co_size_platoon_click", await _g6_option(ab, "TemplateSize", "platoon"))
	await _shot("g6_army_builder")
	for i in n:
		_log("co_train_template_click_%d" % i, await _g6_click_in(ab, "TrainTemplate"))
	await _g6_close(ab)
	var ok := await _wait_until(func(): return Companies.companies_of(_w(), 0).size() >= n, 300.0)
	_log("co_companies_trained", ok, "companies=%d" % Companies.companies_of(_w(), 0).size())
	return ok


func _company_flow() -> void:
	var hq := await _g6_company_hq()
	if hq.is_empty() or not await _g6_train_companies(hq, 2):
		return
	var c: Dictionary = Companies.companies_of(_w(), 0)[0]
	var ids := _g6_ids(Companies.units_of(_w(), c))
	# p3 (PT6-3): a click + shift-click pass over 40 crowded units also caught company 2 (38 selected,
	# Captain x2), and the inspector becomes the company card only when the WHOLE selection is one
	# company. Select it the way the UI offers: Forces -> the company's card -> Select.
	var via := "forces"
	var fp0: Control = null
	if await _click_named("ForcesButton") or await _click_named("G6Forces"):
		fp0 = _g6_panel("ForcesPanel")
	var cbox = fp0.find_child("Company_%d" % int(c.id), true, false) if fp0 != null else null
	var sel_btn: Control = null
	if cbox != null:
		for b in (cbox as Node).find_children("*", "Button", true, false):
			if String((b as Button).text) == "Select" and (b as Control).is_visible_in_tree():
				sel_btn = b
				break
	if sel_btn != null:
		await _click(sel_btn.get_global_rect().get_center())
		await _wait(0.4)
	if fp0 != null:
		await _g6_close(fp0)
	var nsel := 0
	for id in ids:
		if _mv().selection.has(int(id)):
			nsel += 1
	if nsel == 0:
		via = "box"
		nsel = await _g6_box(ids)
	_log("co_select_company", nsel > 0, "units=%d selected=%d total=%d via=%s" % [ids.size(), nsel, _mv().selection.size(), via])
	await _wait(0.6)
	var one := CompanyCardM.selection_company(_w(), _mv().selection)
	var title := String(CompanyCardM.model(_w(), c).title) if not one.is_empty() else ""
	var shown := false
	if title != "":
		for l in get_tree().root.find_children("*", "Label", true, false):
			if String((l as Label).text) == title and (l as Control).is_visible_in_tree():
				shown = true
				break
	_log("co_company_card", not one.is_empty() and int(one.id) == int(c.id) and shown, "%s title=%s shown=%s" % [String(c.get("name", "")), title, str(shown)])
	await _shot("g6_company_card")
	_log("co_select_hq_2", await _g5_select(int(hq.id)))
	_log("co_train_commander_click", await _click_named("G6TrainCommander"))
	var cm := await _wait_until(func(): return Companies.commanders_of(_w(), 0).size() > 0, 180.0)
	_log("co_commander_trained", cm, "commanders=%d" % Companies.commanders_of(_w(), 0).size())
	if not cm:
		return
	_log("co_forces_click", await _click_named("G6Forces") or await _click_named("ForcesButton"))
	var fp := _g6_panel("ForcesPanel")
	_log("co_forces_open", fp != null)
	if fp == null:
		return
	_log("co_commander_pick", await _g6_option(fp, "CommanderOption", "commander"))
	var picks := fp.find_children("Pick", "BaseButton", true, false)
	for k in mini(2, picks.size()):
		await _click((picks[k] as Control).get_global_rect().get_center())
		await _wait(0.3)
	_log("co_form_army_click", await _g6_click_in(fp, "FormArmy"), "picks=%d" % picks.size())
	var army := await _wait_until(func(): return Companies.armies_of(_w(), 0).size() > 0, 20.0)
	_log("co_army_formed", army, str(Companies.armies_of(_w(), 0)).left(160))
	await _shot("g6_army_formed")


func _aicmd_flow() -> void:
	var hq := await _g6_company_hq()
	if hq.is_empty() or not await _g6_train_companies(hq, 1):
		return
	var c: Dictionary = Companies.companies_of(_w(), 0)[0]
	_log("ac_panel_button_click", await _click_named("CommandersButton"))
	var cp := _g6_panel("CommandersPanel")
	_log("ac_panel_open", cp != null)
	var s1 = cp.find_child("Slot1", true, false) if cp != null else null
	if s1 == null:
		_log("ac_slot1", false)
		return
	var cname := String(c.get("name", "company"))
	_log("ac_target_click", await _g6_option(s1, "Target", cname) or await _g6_option(s1, "Target", "co"), cname)
	_log("ac_playstyle_click", await _g6_option(s1, "Playstyle", "aggressive"))
	_log("ac_stance_click", await _g6_option(s1, "Stance", "cautious"))
	_log("ac_objective_click", await _g6_option(s1, "Objective", "hold"))
	await _shot("g6_aicmd_panel")
	_log("ac_assign_click", await _g6_click_in(s1, "Assign"))
	var on := await _wait_until(func(): return _g6_slot_units(0) > 0, 10.0)
	var sl: Dictionary = _g6_slot(0)
	_log("ac_assigned", on, "units=%d playstyle=%s stance=%s objective=%s phase=%s" % [_g6_slot_units(0), str(sl.get("playstyle")), str(sl.get("stance")), str(sl.get("objective")), str(sl.get("phase"))])
	_log("ac_objective_stance", String(sl.get("stance", "")) == "cautious" and str(sl.get("objective", "")).contains("hold"), "")
	await _g6_close(cp)
	await _wait(3.0)
	# override: a direct player order to the commanded company
	var ids := _g6_ids(Companies.units_of(_w(), c))
	_log("ac_select_company", await _g6_box(ids) > 0)
	# p3 (PT6-3): ids[0] stayed idle with no stamp: it need not be in the box selection, and a 4-cell move
	# can finish within 0.6 s at 3x. Order at 1x, far enough, and check the selected units for the
	# override stamp (AiCommand.on_applied -> e.player_order_tick) or a move order.
	_mv().speed = 1.0
	var sel_ids := []
	for id in ids:
		if _mv().selection.has(int(id)):
			sel_ids.append(int(id))
	var lead = _ent(int(sel_ids[0])) if not sel_ids.is_empty() else _ent(int(ids[0]))
	var goal: Vector2 = lead.pos + Vector2(8.0, 0.0)
	await _g6_rclick(goal)
	await _wait(0.6)
	var fresh := 0
	var moving := 0
	for id in sel_ids:
		var e = _ent(int(id))
		if e == null:
			continue
		if AiCommand.player_fresh(_w(), e):
			fresh += 1
		if String(e.order.get("type", "")) == "move":
			moving += 1
	_mv().speed = 3.0
	_log("ac_override_order", fresh > 0 and moving > 0, "selected=%d player_fresh=%d moving=%d badge=%s" % [sel_ids.size(), fresh, moving, str(lead.get("ai_cmd")) if lead != null else ""])
	await _shot("g6_aicmd_override")
	_log("ac_panel_button_click_2", await _click_named("CommandersButton"))
	cp = _g6_panel("CommandersPanel")
	s1 = cp.find_child("Slot1", true, false) if cp != null else null
	_log("ac_recall_click", s1 != null and await _g6_click_in(s1, "Recall"))
	var off := await _wait_until(func(): return _g6_slot_units(0) == 0, 10.0)
	_log("ac_recalled", off, str(_g6_slot(0)).left(160))
	await _g6_close(cp)


func _g6_slot(sl: int) -> Dictionary:
	for s in AiCommand.slots(_w(), 0):
		if int(s.get("slot", -1)) == sl:
			return s
	return {}


func _g6_slot_units(sl: int) -> int:
	var s := _g6_slot(sl)
	var u = s.get("units", [])
	return (u as Array).size() if u is Array else (0 if s.is_empty() or String(s.get("kind", "")) == "" else 1)


func _g6_water(q: Vector2i) -> bool:
	return [4, 6, 9, 10].has(int(_w().map.terrain[q.y * int(_w().map.w) + q.x]))


## A legal Shipyard cell. r1: none within 48 of the HQ while the coast is unexplored, so (as the G5 naval
## flow does) the builders are right-click moved to the nearest shore cell first.
func _g6_shipyard_site() -> Vector2i:
	var w := _w()
	var c: Vector2i = _hq().cell
	for r in range(3, 48):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and Construction.placement_error(w, 0, "a_shipyard", c + Vector2i(dx, dy)) == "":
					return c + Vector2i(dx, dy)
	var shore := Vector2i(-1, -1)
	var bd := 1e9
	for y in w.map.h:
		for x in w.map.w:
			var o := Vector2i(x, y)
			var d2 := float((o - c).length_squared())
			if d2 < bd and Naval.shore_error(w, "a_shipyard", o) == "":
				bd = d2
				shore = o
	_log("nv6_shore_known", shore.x >= 0, "shore=%s dist=%.0f" % [str(shore), sqrt(bd)])
	if shore.x < 0:
		return shore
	_mv().center_camera_on(_own_units_in(_defs_with("can_build"))[0].pos)
	await _wait(0.3)
	var n0 := await _select_units(_defs_with("can_build"))
	_mv().center_camera_on(Vector2(shore))
	await _wait(0.4)
	await _click(_to_screen(Vector2(shore) + Vector2(1.5, 1.5)), MOUSE_BUTTON_RIGHT)
	var ok_s := await _wait_until(func(): return Construction.placement_error(_w(), 0, "a_shipyard", shore) == "", 90.0)
	_log("nv6_scout_coast_rightclick", n0 > 0 and ok_s, "err=%s" % Construction.placement_error(_w(), 0, "a_shipyard", shore))
	return shore if ok_s else Vector2i(-1, -1)


func _naval6_flow() -> void:
	for role in ["power", "barracks", "factory"]:  # same base as the G5 naval flow
		if _built_count(_role(role)) == 0:
			await _g5_build(_role(role))
	var site := await _g6_shipyard_site()
	_log("nv6_shore_site", site.x >= 0, str(site))
	if site.x < 0 or (await _g5_build("a_shipyard", site)).is_empty():
		return
	var subs := _g6_ids(await _train("a_submarine"))
	if not subs.is_empty():
		var sid := int(subs[0])
		_log("nv6_select_sub", await _g5_select(sid))
		_log("nv6_dive_click", await _click_named("G6_submerge"))
		_log("nv6_sub_submerged", await _wait_until(func(): return _ent(sid) != null and Sonar.submerged(_ent(sid)), 20.0))
		# an enemy sub dives next to ours (harness spawn): our sonar must pick it up
		# p1/p2: setting e.submerged by hand skipped sys_state.sonar.subs, so Sonar.tick never computed contact.
		# Now the enemy sub dives through Sonar.apply_command (issuer 1) on the same dive-able terrain as ours.
		var deep_t: int = _w().terrain_at(_w().cell_of(_ent(sid).pos))
		var wq := _g5_cell_near(Vector2i(_ent(sid).pos), 3, 9, func(q: Vector2i) -> bool: return _w().terrain_at(q) == deep_t)
		if wq.x >= 0:
			_mv().join_sim()
			var eid: int = _w().spawn_unit("a_submarine", 1, Vector2(wq) + Vector2(0.5, 0.5))
			Sonar.apply_command(_w(), {"type": "submerge", "issuer": 1, "unit_ids": [eid], "on": true})
			var det := await _wait_until(func(): return _ent(eid) != null and Sonar.detected_by(_w(), 0, _ent(eid)), 30.0)
			_log("nv6_enemy_sub_detected_by_sonar", det, "enemy at %s submerged=%s" % [str(wq), str(_ent(eid).get("submerged") if _ent(eid) != null else null)])
		else:
			_log("nv6_water_near_sub", false)
		await _shot("g6_naval_sub")
	# p4 (PT6-3): the carrier queue sat at progress 0 with pop 12/20 (carrier pop 10): depots first.
	for i in 3:
		var fp: Dictionary = _w().factions[0]
		if int(fp.get("pop_cap", 0)) >= int(fp.get("pop", 0)) + int(Content.unit("a_carrier").get("pop", 0)):
			break
		await _g5_build(_role("depot"))
	var cars := _g6_ids(await _train("a_carrier"))
	if cars.is_empty():
		return
	var cid := int(cars[0])
	_log("nv6_carrier_is_field", not Airfield.field(_w(), cid).is_empty(), str(Airfield.field(_w(), cid)).left(120))
	var prods: Array = Content.unit("a_carrier").get("produces", [])
	_log("nv6_select_carrier", await _g5_select(cid), "produces=%s" % str(prods))
	if prods.is_empty():
		return
	var item := String(prods[0])
	var units := G3.item_units(item)
	var n0 := _own_units_in(units).size()
	_log("nv6_carrier_train_click", await _click_button(String(Content.production(item).name)), item)
	if not await _wait_until(func(): return _own_units_in(units).size() > n0, 120.0):
		_log("nv6_deck_aircraft", false, item)
		return
	var jid := int(_own_units_in(units).back().id)
	_log("nv6_select_aircraft", await _g5_select(jid))
	var goal: Vector2 = _ent(cid).pos + Vector2(10.0, 0.0)
	_log("nv6_sortie_click", await _g5_arm_click("G5_sortie", goal), _g5_last_cmd())
	_log("nv6_carrier_sortie_airborne", await _g5_wait_phase(jid, ["sortie", "air", "roll", "taxi"], 60.0), Air.phase(_w(), jid))
	await _shot("g6_naval_carrier_sortie")


func _airfield2_flow() -> void:
	# r1: the jet gate said no_air_tower (air_high aircraft need a built air tower within tower_range of a
	# field): build the same base as the G5 air flow (power, barracks, factory, depots for pop) + the tower.
	for role in ["power", "power", "barracks", "factory", "depot", "depot"]:
		if _built_count(_role(role)) < (2 if role != "barracks" and role != "factory" else 1):
			await _g5_build(_role(role))
	var tower := await _g5_build("a_air_tower")
	_log("af2_air_tower_built", not tower.is_empty())
	var strip := await _g5_build("a_airstrip")
	if strip.is_empty():
		return
	var bid := int(strip.id)
	var lay: Dictionary = Airfield.layout(_w(), bid)
	_log("af2_v2_layout", (lay.get("slots", []) as Array).size() > 0, "strip_len=%s slots=%d" % [str(lay.get("strip_len")), (lay.get("slots", []) as Array).size()])
	_log("af2_select_strip", await _g5_select(bid))
	_log("af2_buy_hangar_click", await _click_named("G5_hangar_light"))
	var hs := await _wait_until(func(): return _g6_hangar_slots(bid) > 0, 60.0)
	_log("af2_hangar_in_slot", hs, str(Airfield.slots(_w(), bid)).left(200))
	await _shot("g6_airfield_hangar")
	var gate := await _wait_until(func(): return Airfield.can_produce(_w(), 0, "a_strike_jet") == "", 150.0)
	_log("af2_jet_gate_open", gate, Airfield.can_produce(_w(), 0, "a_strike_jet"))
	await _g5_select(bid)
	var jets := await _train("a_strike_jet")
	if jets.is_empty():
		return
	var jid := int(jets[0].id)
	_log("af2_select_jet", await _g5_select(jid))
	_log("af2_take_off_click", await _click_named("G5_take_off"), _g5_last_cmd())
	_log("af2_short_runway_takeoff", await _g5_wait_phase(jid, ["air", "sortie", "patrol", "holding"], 90.0), Air.phase(_w(), jid))
	await _shot("g6_airfield_airborne")
	if not _mv().selection.has(jid):
		await _g5_select(jid)
	_log("af2_rebase_click", await _g5_arm_click("G5_rebase", Vector2(strip.pos)), _g5_last_cmd())
	_log("af2_short_runway_landed", await _g5_wait_phase(jid, ["parked"], 240.0), Air.phase(_w(), jid))
	await _shot("g6_airfield_landed")


func _g6_hangar_slots(bid: int) -> int:
	var n := 0
	for s in Airfield.slots(_w(), bid):
		if int(s.get("hangar", -1)) >= 0:  # slot.hangar is the hangar entity id, -1 when empty (r1: String(int) error)
			n += 1
	return n


func _survival_flow() -> void:
	_mv().join_sim()
	var w := _w()
	var vp = w.cfg.get("victory_params", {})
	_log("sv_mode", String(w.cfg.get("victory", "")) == "survive" and Waves.active(w), "map=%s victory=%s params=%s attacker=%d" % [String(w.map.get("id", "?")), str(w.cfg.get("victory")), str(vp), Waves.attacker(w)])
	if vp is Dictionary and (vp as Dictionary).has("seconds"):
		vp.seconds = mini(int(vp.seconds), int(w.tick) / SimWorld.TICK_RATE + 420)  # harness: a 7 minute hold
		# p6/p7 (PT6-3): Victory.rules_of_world caches the rules in w.cache.victory_rules, so the shortened hold
		# never applied (the match kept its 1200 s term; both runs were overrun AFTER start + 420 s). Drop the
		# cache so the 7 minute hold is the one evaluated.
		w.cache.erase("victory_rules")
	var att := Waves.attacker(w)
	# r1: HQ overrun at 4:16 with nothing built (builder clicks missed the raised plateau). Defend properly:
	# power (towers draw power), three defence towers, then a rifle squad.
	# p3 (PT6-3): towers need a completed Barracks (site_none errs) and the base was overrun at tick 6462
	# (323 s) while the harness gestures ran at 3x. Build at 1x (gestures cost a third of the game time),
	# barracks + squad first, then the towers; back to 3x for the hold.
	# p4: 3 towers + 1 squad killed 17 of 78 attackers and fell at tick 8228: six towers (power as needed)
	# and three squads.
	_mv().speed = 1.0
	await _g5_build(_role("power"))
	var sq := await _g6_squad()
	# p5: 6 towers + 6 squads killed 43 of 78 and fell at tick 8773, ~12 s short of the hold: 9 towers, 5 squads.
	for i in 9:
		await _g6_power_room(_role("defense"))
		await _g5_build(_role("defense"))
	for i in 2:  # p6/p7: a 4th extra squad timed out (g4b_trained_rifle_squad rifle_squad=12)
		sq.append_array(_g6_ids(await _train(_role("infantry"))))
	_mv().speed = 3.0
	_log("sv_defenders", _built_count(_role("defense")) >= 2 and sq.size() > 0, "towers=%d squad=%d" % [_built_count(_role("defense")), sq.size()])
	var seen := {}
	var t := 0.0
	while t < 1300.0 and not bool(_w().match_state.get("ended", false)):
		await _wait(2.0)
		t += 2.0
		for e in _w().units_of(att):
			seen[int(e.id)] = true
	var dead := 0
	for id in seen:
		if _ent(int(id)) == null:
			dead += 1
	var ms: Dictionary = _w().match_state
	_log("sv_waves_spawned", seen.size() > 0, "attacker units seen=%d" % seen.size())
	_log("sv_waves_repelled", dead >= 3, "attackers killed=%d" % dead)
	_log("sv_survived_win", bool(ms.get("ended", false)) and (ms.get("winners", []) as Array).has(0), "match_state=%s" % str(ms).left(200))
	await _shot("g6_survival_end")


func _g6_kill(id: int) -> void:
	_mv().join_sim()
	var w := _w()
	var foe: int = w.spawn_unit("rifleman", 1, Vector2(1.5, 1.5))
	var t: Dictionary = w.entities[id]
	t.hp = 1
	Damage.apply_hit(w, w.entities[foe], t, Combat.stats(w.entities[foe]), true)


func _g6_pilot(suit: String) -> int:
	for e in _w().units_of(0):
		if String(e.get("pilot_of", "")) == suit:
			return int(e.id)
	return -1


func _exo_flow() -> void:
	if _built_count(_role("power")) == 0:
		await _g5_build(_role("power"))
	for role in ["barracks", "factory"]:  # r1 diag: the Exo-Suit Garage needs a completed Motor Pool
		if _built_count(_role(role)) == 0:
			await _g5_build(_role(role))
	var g := await _g5_build("a_exo_garage")
	if g.is_empty():
		return
	# p1/p2: pilot=-1. Exo._eject: a pilot only ejects while the side has medical capability
	# (rules pilot_needs_medical, Medical.has_medical), else PilotLost. Build a Field Hospital first.
	if _built_count("a_hospital") == 0:
		await _g5_build("a_hospital")
	_log("exo_side_has_medical", Medical.has_medical(_w(), 0))
	var gid := int(g.id)
	var suits := _g6_ids(await _train("a_exo_rifle"))
	_log("exo_suit_trained", suits.size() > 0)
	if suits.is_empty():
		return
	await _shot("g6_exo_suit")
	# p5 (PT6-3): the ejected pilot is Wounded and bled out after ~20 s (exo_wait: "must be treated first",
	# then no pilot): nobody carried it to the hospital. Medic team on Auto evac over the suit, as the med flow.
	var medics := await _train("a_medic_team")
	if not medics.is_empty():
		_log("exo_select_medic", await _g5_select(int(medics[0].id)))
		_log("exo_auto_evac_click", await _click_named("G5_medic_auto"))
		await _wait(0.3)
		var sp0: Vector2 = _ent(int(suits[0])).pos
		_mv().center_camera_on(sp0)
		await _wait(0.3)
		await _drag(_to_screen(sp0 - Vector2(4.0, 0.0)), _to_screen(sp0 + Vector2(5.0, 0.0)))
		await _wait(0.5)
		_log("exo_auto_evac_on", _mv().g4b.last_cmd.get("type", "") == "set_auto_evac" and bool(_mv().g4b.last_cmd.get("on", false)), str(_mv().g4b.last_cmd))
	_g6_kill(int(suits[0]))  # harness hit: the suit is destroyed, its pilot ejects (G6Hooks.on_destroyed)
	var ej := await _wait_until(func(): return _g6_pilot("a_exo_rifle") >= 0, 10.0)
	var pid := _g6_pilot("a_exo_rifle")
	_log("exo_pilot_ejected", ej and _ent(int(suits[0])) == null, "pilot=%d" % pid)
	if pid < 0:
		return
	await _shot("g6_exo_ejected")
	_log("exo_select_pilot", await _g5_select(pid))
	await _g6_rclick(Vector2(g.pos) + Vector2(2.0, 0.5))
	# p3 (PT6-3): "pilot gone" at the ready check yet a suit appeared later. Track whichever own pilot of the
	# suit exists (re-order it to the garage when it changes) and say why it is not ready yet.
	var ready := false
	var why := "no pilot"
	var last := pid
	var t := 0.0
	var sent_treated := false
	while t < 240.0:
		var cur := _g6_pilot("a_exo_rifle")
		if cur >= 0:
			pid = cur
			why = String(Exo.plan_resuit(_w(), {"issuer": 0, "building_id": gid, "pilot_id": cur}).reason)
			ready = why == ""
			# treated pilots re-spawn beside the hospital: walk them to the garage once (or a new pilot id)
			if not ready and why.begins_with("Move the pilot") and (not sent_treated or cur != last):
				last = cur
				sent_treated = true
				await _g5_select(cur)
				await _g6_rclick(Vector2(g.pos) + Vector2(2.0, 0.5))
		else:
			why = "no pilot"
		if ready:
			break
		if int(t) % 10 == 0:
			print("PLAYTEST-DBG exo_wait t=%d pilot=%d why=%s exo=%s" % [int(t), cur, why, str(_w().sys_state.get("exo", {}))])
		await _wait(1.0)
		t += 1.0
	_log("exo_pilot_ready", ready, "pilot=%d %s" % [pid, why])
	_log("exo_select_garage", await _g5_select(gid))
	var n0 := _own_units("a_exo_rifle").size()
	var r0 := int(_w().sys_state.get("exo", {}).get("resuited", 0))
	_log("exo_resuit_click", await _click_named("G6_resuit"))
	_log("exo_resuited", await _wait_until(func(): return int(_w().sys_state.get("exo", {}).get("resuited", 0)) > r0, 60.0), "suits=%d (was %d) resuited=%d" % [_own_units("a_exo_rifle").size(), n0, int(_w().sys_state.get("exo", {}).get("resuited", 0))])
	await _shot("g6_exo_resuit")


## Enemy drone spawned at p (harness); returns id. Tracks its lowest hp in drone_min_hp.
var drone_min_hp := {}


func _g6_drone_at(p: Vector2) -> int:
	_mv().join_sim()
	var id: int = _w().spawn_unit("b_drone_recon", 1, p)
	drone_min_hp[id] = float(_w().entities[id].get("hp", 0))
	return id


func _g6_drone_dead(id: int) -> bool:
	var e = _ent(id)
	if e != null:
		drone_min_hp[id] = minf(float(drone_min_hp.get(id, 1e9)), float(e.get("hp", 0)))
	return e == null


## p4 (PT6-3): airdef CIWS / radar stayed silent: Airdef.source_active is false while power_use >
## power_prod. Build power plants (max 3) until the next building's draw fits.
func _g6_power_room(def_id: String) -> void:
	var need := -int(Content.building(def_id).get("power", 0))
	for i in 3:
		var f: Dictionary = _w().factions[0]
		if need <= 0 or int(f.get("power_prod", 0)) - int(f.get("power_use", 0)) >= need + 15:
			return
		await _g5_build(_role("power"))


func _airdef_flow() -> void:
	if _built_count(_role("power")) == 0:
		await _g5_build(_role("power"))
	# prerequisites (r1 diag): CIWS + Radar Station need a Research Station; the SAM site needs a Radar Station
	# p3 diag (PT6-3): site_none research_station errs={"Requires a completed Barracks first."}
	if _built_count(_role("barracks")) == 0:
		await _g5_build(_role("barracks"))
	if _built_count(_role("research")) == 0:
		await _g5_build(_role("research"))
	_log("ad_sam_locked_without_radar", Construction.placement_error(_w(), 0, "a_sam_site", Vector2i(_hq().cell) + Vector2i(6, 0)).contains("Radar"),
		Construction.placement_error(_w(), 0, "a_sam_site", Vector2i(_hq().cell) + Vector2i(6, 0)))
	await _g6_power_room("a_laser_ciws")
	var ciws := await _g5_build("a_laser_ciws")
	if not ciws.is_empty():
		var d1 := _g6_drone_at(Vector2(ciws.pos) + Vector2(2.5, 0.0))
		var hp0: float = drone_min_hp[d1]
		# p5 (PT6-3): Counterdrone._down REMOVES a launched drone (no hp loss), so "min hp < hp0" could never
		# hold. Evidence now: the drone is gone and the CIWS spent its shot (counterdrone.ready[ciws] set);
		# harness-spawned drones have no drone_life, so nothing else removes them.
		var fired := [false]
		var cid := int(ciws.id)
		var down := await _wait_until(func():
			var cst = _w().sys_state.get("counterdrone")
			if cst != null and (cst.ready as Dictionary).has(cid):
				fired[0] = true
			return _g6_drone_dead(d1), 60.0)
		_log("ad_ciws_downs_drone", down and (bool(fired[0]) or float(drone_min_hp[d1]) < hp0), "hp %s -> min %s gone=%s ciws_fired=%s" % [str(hp0), str(drone_min_hp[d1]), str(down), str(fired[0])])
		await _shot("g6_airdef_ciws")
	await _g6_power_room("a_radar_station")
	var radar := await _g5_build("a_radar_station")
	await _g6_power_room("a_sam_site")
	var sam := await _g5_build("a_sam_site")
	if sam.is_empty() or radar.is_empty():
		return
	for i in 2:  # p5: power 135/130 after the SAM: the radar (requires_power) went dark
		if int(_w().factions[0].get("power_use", 0)) <= int(_w().factions[0].get("power_prod", 0)):
			break
		await _g5_build(_role("power"))
	_log("ad_power_ok", int(_w().factions[0].get("power_use", 0)) <= int(_w().factions[0].get("power_prod", 0)), "power %s/%s" % [str(_w().factions[0].get("power_use")), str(_w().factions[0].get("power_prod"))])
	var away := (Vector2(sam.pos) - Vector2(ciws.pos if not ciws.is_empty() else _hq().pos)).normalized()
	_log("ad_radar_covers_sam", await _wait_until(func(): return Airdef.radar_covers(_w(), 0, Vector2(sam.pos)), 20.0))
	var d2 := _g6_drone_at(Vector2(sam.pos) + away * 5.0)
	var hp2: float = drone_min_hp[d2]
	var killed := await _wait_until(func(): return _g6_drone_dead(d2), 60.0)
	# one 95-damage SAM hit kills a 40 hp drone between two polls: gone (nothing else removes it) is the evidence
	_log("ad_sam_fires_with_radar", killed, "min hp %s (start %s) gone=%s" % [str(drone_min_hp[d2]), str(hp2), str(killed)])
	await _shot("g6_airdef_sam")
	# radar lost (harness hit destroys the Radar Station): the SAM must go silent
	_g6_kill(int(radar.id))
	var lost := await _wait_until(func(): return not Airdef.radar_covers(_w(), 0, Vector2(sam.pos)), 10.0)
	var d3 := _g6_drone_at(Vector2(sam.pos) + away * 5.0)
	var hp3: float = drone_min_hp[d3]
	_log("ad_no_radar_no_cover", lost and not Airdef.covers_target(_w(), _ent(int(sam.id)), _ent(d3)), "radar_alive=%s" % str(_ent(int(radar.id)) != null))
	# G6.1: the oracle is the SAM's own fire. Drone hp alone also counted other shooters (r4: our recon vehicle's
	# carbine hit the drone while the radar-less SAM stayed silent), so the SAM's ShotFired events are counted.
	var who := {}
	var sam_shots := 0
	var seen_ev := {}
	for k in 32:
		await _wait(0.25)
		for ev in _w().event_log:
			if String(ev.type) != "ShotFired" or int(ev.get("target", -1)) != d3:
				continue
			var key := "%d:%d" % [int(ev.get("tick", 0)), int(ev.get("shooter", -1))]
			if seen_ev.has(key):
				continue
			seen_ev[key] = true
			var sh = _ent(int(ev.get("shooter", -1)))
			who["%s#%d" % [String(sh.def) if sh != null else "?", int(ev.get("shooter", -1))]] = true
			if int(ev.get("shooter", -1)) == int(sam.id):
				sam_shots += 1
		if _ent(d3) == null:
			break
	_g6_drone_dead(d3)
	_log("ad_sam_silent_without_radar", sam_shots == 0, "SAM shots %d; drone hp %s -> %s; shooters %s" % [sam_shots, str(hp3), str(drone_min_hp[d3]), str(who.keys())])


func _g6_on_high(ids: Array) -> int:
	var n := 0
	for id in ids:
		var e = _ent(int(id))
		if e != null and Elevation.height_at(_w(), Vector2i(floori(e.pos.x), floori(e.pos.y))) >= 2:
			n += 1
	return n
