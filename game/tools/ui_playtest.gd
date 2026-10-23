extends Node
## UI-01 playtest driven ONLY by synthetic input events pushed into the real viewport
## (the same path as a mouse/keyboard): menu click -> select engineers -> build generator via
## hotkey + world click -> build barracks -> select barracks -> click "Rifle Squad" button ->
## select the squad -> attack-move toward the bridge.  Run:
##   godot --path game -- --ui-playtest=C:/abs/shot_dir
## Prints "PLAYTEST <step> ok=<bool> <detail>" lines and "PLAYTEST RESULT pass=N fail=M".

const Construction = preload("res://sim/systems/construction.gd")
const MatchViewScript = preload("res://presentation/match_view.gd")

var main: Node
var shot_dir := ""
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
func _push(ev: InputEvent) -> void:
	get_viewport().push_input(ev)


func _move(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	_push(m)
	await get_tree().process_frame


func _button(p: Vector2, idx: int, pressed: bool, dbl: bool = false) -> void:
	var b := InputEventMouseButton.new()
	b.position = p
	b.global_position = p
	b.button_index = idx
	b.pressed = pressed
	b.double_click = dbl
	_push(b)
	await get_tree().process_frame


func _click(p: Vector2, idx: int = MOUSE_BUTTON_LEFT, dbl: bool = false) -> void:
	await _move(p)
	await _button(p, idx, true, dbl)
	await _button(p, idx, false)


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
	var out := []
	for e in _w().units_of(0):
		if e.def == def_id:
			out.append(e)
	return out


func _site(def_id: String) -> Vector2i:
	var w := _w()
	var hq: Dictionary = w.buildings_of(0, "hq")[0]
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


func _select_engineers() -> int:
	var engs := _own_units("engineer")
	if engs.is_empty():
		return 0
	# double-click one engineer = select all engineers on screen
	await _click(_to_screen(engs[0].pos), MOUSE_BUTTON_LEFT)
	await _click(_to_screen(engs[0].pos), MOUSE_BUTTON_LEFT, true)
	await _wait(0.3)
	var n := 0
	for id in _mv().selection:
		var e = _w().get_e(int(id))
		if e != null and e.def == "engineer":
			n += 1
	return n


func _place(def_id: String, hotkey: Key) -> bool:
	var o := _site(def_id)
	if o.x < 0:
		_log("site_" + def_id, false, "no legal on-screen site")
		return false
	await _key(hotkey)
	await _wait(0.3)
	var size := int(Content.building(def_id).size)
	var centre := Vector2(o) + Vector2(size, size) * 0.5
	await _move(_to_screen(centre))
	await _wait(0.4)
	await _shot("ui_ghost_" + def_id)
	await _click(_to_screen(centre))
	await _wait(0.5)
	return _w().buildings_of(0, def_id).size() > 0


# ------------------------------------------------------------ the run
func _run() -> void:
	await _wait(1.5)
	await _shot("ui_00_menu")
	_log("menu_start_button", await _click_button("START MATCH"))
	var started := await _wait_until(func(): return main.match_view != null and main.match_view.world != null, 10.0)
	_log("match_started", started)
	if not started:
		return _finish()
	await _wait(1.5)
	await _shot("ui_01_start")

	var n := await _select_engineers()
	_log("select_engineers_doubleclick", n >= 4, "selected=%d" % n)
	await _shot("ui_02_engineers_selected")
	_log("place_generator_hotkey_G", await _place("generator", KEY_G))
	_log("speed_3x_button", await _click_button("3x"))
	var gen_ok := await _wait_until(func(): return _w().buildings_of(0, "generator").size() > 0 and _w().buildings_of(0, "generator")[0].built, 60.0)
	_log("generator_completed", gen_ok)

	n = await _select_engineers()
	_log("reselect_engineers", n >= 4, "selected=%d" % n)
	_log("place_barracks_hotkey_B", await _place("barracks", KEY_B))
	var bar_ok := await _wait_until(func(): return _w().buildings_of(0, "barracks").size() > 0 and _w().buildings_of(0, "barracks")[0].built, 60.0)
	_log("barracks_completed", bar_ok)
	await _shot("ui_03_barracks_built")
	if not bar_ok:
		return _finish()

	# economy: right-click a salvage pile with engineers selected (smart gather), wait for salvage
	n = await _select_engineers()
	var pile = null
	var best := 1e9
	var hqp: Vector2 = _w().buildings_of(0, "hq")[0].pos
	for e in _w().entities.values():
		if e.kind == "resource" and e.res == "salvage" and _w().is_visible(0, e.pos):
			var dd: float = e.pos.distance_to(hqp)
			if dd < best:
				best = dd
				pile = e
	_log("visible_salvage_pile", pile != null)
	if pile != null:
		await _click(_to_screen(pile.pos), MOUSE_BUTTON_RIGHT)
		await _wait(0.5)
		var gathering := 0
		for e in _own_units("engineer"):
			if String(e.order.type) == "gather":
				gathering += 1
		_log("right_click_gather", gathering >= 4, "gathering=%d" % gathering)
		await _shot("ui_035_gathering")
	var need := int(Content.production("rifle_squad").cost.salvage)
	var sal_ok := await _wait_until(func(): return int(_w().factions[0].stock.salvage) >= need, 90.0)
	_log("salvage_for_squad", sal_ok, "salvage=%d need=%d" % [int(_w().factions[0].stock.salvage), need])

	var bar: Dictionary = _w().buildings_of(0, "barracks")[0]
	await _click(_to_screen(bar.pos))
	await _wait(0.4)
	_log("select_barracks_click", _mv().selection.has(int(bar.id)))
	await _shot("ui_04_barracks_selected")
	var riflemen_before := _own_units("rifleman").size()
	_log("click_rifle_squad_button", await _click_button("Rifle Squad"))
	await _wait(0.3)
	_log("queue_has_item", _w().get_e(int(bar.id)) != null and _w().get_e(int(bar.id)).queue.size() > 0)
	var sq_ok := await _wait_until(func(): return _own_units("rifleman").size() >= riflemen_before + 4, 60.0)
	_log("rifle_squad_trained", sq_ok, "riflemen=%d" % _own_units("rifleman").size())
	await _wait(1.0)
	await _shot("ui_05_squad_trained")

	var rifles := _own_units("rifleman")
	if rifles.size() > 0:
		await _click(_to_screen(rifles[0].pos))
		await _click(_to_screen(rifles[0].pos), MOUSE_BUTTON_LEFT, true)
		await _wait(0.3)
		var sel := 0
		for id in _mv().selection:
			var e = _w().get_e(int(id))
			if e != null and e.def == "rifleman":
				sel += 1
		_log("select_squad_doubleclick", sel >= 4, "selected=%d" % sel)
		await _key(KEY_A)
		var goal := Vector2(42.5, 42.5)  # toward the central bridge
		await _click(_to_screen(goal))
		await _wait(1.0)
		var am := 0
		for e in _own_units("rifleman"):
			if String(e.order.type) == "attack_move":
				am += 1
		_log("attack_move_issued", am >= 4, "attack_move_units=%d" % am)
		await _wait(3.0)
		await _shot("ui_06_attack_move")
	_finish()


func _finish() -> void:
	print("PLAYTEST RESULT pass=%d fail=%d" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
