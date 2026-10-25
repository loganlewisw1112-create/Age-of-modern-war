extends VBoxContainer
## Units & buildings tab (owner: ED2, PLAN_G4 section 3.1 tab 6). Pick a player (colour chip) and a
## faction filter; the palette is filled from Content (every unit/building of that faction,
## including content/g4 fragments). Modes: Place (click; symmetric copies go to the nearest
## player), Select / move (click picks, drag moves, Delete removes; tag + cargo in the panel),
## Formation box (drag a box, fills it with the picked def). Q/E rotate the facing.
## Every edit is one undo step (doc.begin_stroke / editor.stroke_done).

const W = preload("res://presentation/editor/editor_widgets.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const M = preload("res://presentation/editor/ed2_model.gd")
const Symmetry = preload("res://presentation/editor/symmetry.gd")
const UnitsSel = preload("res://presentation/editor/ed2_units_sel.gd")
const MODES := ["place", "select", "formation"]
const FACING_STEP := PI / 4.0

var ed
var slot_idx := 0                 # index into scenario.players
var fac_filter := 0               # 0 = the player's faction, 1..n = faction_ids[i-1], n+1 = all
var items: Array = []             # [[kind, def]] parallel to the palette ItemList
var pick_kind := "unit"
var pick_def := ""
var mode := "place"
var facing := 0.0
var built := true
var selected := -1                # index into scenario.entities
var _a = null                     # formation anchor
var _move_from = null
var _chips: HFlowContainer
var _fac_opt: OptionButton
var palette_list: ItemList
var _facing_label: Label
var _mode_btns: Array = []
var sel: Control                  # ed2_units_sel.gd: tag / cargo / delete for the selection


func setup(editor) -> void:
	ed = editor
	add_theme_constant_override("separation", 6)
	W.header(self, "Player")
	_chips = HFlowContainer.new()
	add_child(_chips)
	var names: Array = ["Player's faction"]
	for fid in Content.faction_ids():
		names.append(String(Content.faction(String(fid)).get("name", fid)))
	names.append("All factions")
	_fac_opt = W.option(self, "Faction", names, 0, func(i: int):
		fac_filter = i
		fill_palette())
	W.header(self, "Palette")
	palette_list = ItemList.new()
	palette_list.name = "ED2Palette"
	palette_list.custom_minimum_size = Vector2(0, 230)
	palette_list.focus_mode = Control.FOCUS_NONE
	palette_list.item_selected.connect(_on_pick)
	add_child(palette_list)
	_mode_btns = W.choice_row(self, ["Place", "Select / move", "Formation box"], 0, func(i: int): set_mode(MODES[i]))
	var fr := HBoxContainer.new()
	add_child(fr)
	W.button(fr, "Q  ⟲", func(): rotate_facing(-1), "Rotate facing left (Q)")
	W.button(fr, "E  ⟳", func(): rotate_facing(1), "Rotate facing right (E)")
	_facing_label = HT.make_label("", HT.TEXT, 14)
	fr.add_child(_facing_label)
	W.check(self, "Built (off = foundation)", built, func(on: bool): built = on)
	W.note(self, "Click to place. Symmetry copies go to the nearest player's side. Right-click cancels.")
	sel = UnitsSel.new()
	add_child(sel)
	sel.setup(self)
	ed.doc.changed.connect(_on_doc_changed)
	refresh()


func tab_activated() -> void:
	refresh()


func refresh() -> void:
	var players: Array = ed.doc.scenario.get("players", [])
	slot_idx = clampi(slot_idx, 0, maxi(0, players.size() - 1))
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	var group := ButtonGroup.new()
	for i in players.size():
		var p: Dictionary = players[i]
		var b := Button.new()
		b.name = "ED2Player%d" % i
		b.text = "P%d" % (int(p.slot) + 1)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.icon = W.chip(ed.view.team_color(i))
		b.button_pressed = i == slot_idx
		b.pressed.connect(set_player.bind(i))
		_chips.add_child(b)
	_facing_label.text = "Facing %d°" % roundi(rad_to_deg(facing))
	fill_palette()
	sel.refresh()


func set_player(i: int) -> void:
	slot_idx = i
	fill_palette()


func current_slot() -> int:
	var players: Array = ed.doc.scenario.get("players", [])
	return int(players[slot_idx].slot) if slot_idx < players.size() else 0


func filter_faction() -> String:
	var facs := Content.faction_ids()
	if fac_filter == 0:
		var players: Array = ed.doc.scenario.get("players", [])
		return String(players[slot_idx].get("faction", "human_a")) if slot_idx < players.size() else ""
	if fac_filter <= facs.size():
		return String(facs[fac_filter - 1])
	return ""


func fill_palette() -> void:
	var pal := M.palette(filter_faction())
	items.clear()
	palette_list.clear()
	for kind in ["units", "buildings"]:
		var k := "unit" if kind == "units" else "building"
		for id in pal[kind]:
			items.append([k, String(id)])
			palette_list.add_item(("◆ " if k == "building" else "• ") + M.def_label(k, String(id)))
	var idx := -1
	for i in items.size():
		if items[i][1] == pick_def:
			idx = i
	if idx < 0 and not items.is_empty():
		idx = 0
	if idx >= 0:
		palette_list.select(idx)
		_on_pick(idx)


func _on_pick(i: int) -> void:
	if i < 0 or i >= items.size():
		return
	pick_kind = String(items[i][0])
	pick_def = String(items[i][1])
	ed.status("Picked %s" % M.def_label(pick_kind, pick_def), HT.DIM)


## Programmatic pick by def id (tests / playtest after a real click).
func pick(def: String) -> bool:
	for i in items.size():
		if items[i][1] == def:
			palette_list.select(i)
			_on_pick(i)
			return true
	return false


func set_mode(m: String) -> void:
	mode = m
	_a = null
	if _mode_btns.size() == MODES.size():
		(_mode_btns[MODES.find(m)] as Button).button_pressed = true


func rotate_facing(dir: int) -> void:
	facing = wrapf(facing + FACING_STEP * dir, 0.0, TAU)
	_facing_label.text = "Facing %d°" % roundi(rad_to_deg(facing))
	if selected >= 0 and selected < ents().size():
		_edit("Rotate", func(): ents()[selected]["facing"] = facing)


func ents() -> Array:
	if not ed.doc.scenario.has("entities"):
		ed.doc.scenario["entities"] = []
	return ed.doc.scenario.entities


func _size_of(kind: String, def: String) -> int:
	return int(Content.building(def).get("size", 1)) if kind == "building" else 1


## One undo step around `fn` (which mutates doc.scenario), then refresh the views.
func _edit(label: String, fn: Callable) -> void:
	ed.doc.begin_stroke(label)
	fn.call()
	ed.stroke_done()
	after_edit()


func after_edit() -> void:
	ed.view._sync_world()
	ed.view.overlay.queue_redraw()
	sel.refresh()


## Places the picked def at `origin` for the current player plus its symmetric copies.
## Returns the number of entities added.
func place_at(origin: Vector2i) -> int:
	if pick_def == "":
		return 0
	var s := _size_of(pick_kind, pick_def)
	var fps: Array = Symmetry.footprints(origin, Vector2i(s, s), ed.doc.symmetry, int(ed.doc.map.w), int(ed.doc.map.h))
	var players: Array = ed.doc.scenario.get("players", [])
	var n := 0
	for k in fps.size():
		var o: Vector2i = fps[k][0]
		if o.x < 0 or o.y < 0 or o.x + s > int(ed.doc.map.w) or o.y + s > int(ed.doc.map.h):
			continue
		var owner := current_slot() if k == 0 else M.nearest_slot(players, o)
		var why := M.place_reason(ed.doc.map, pick_kind, pick_def, o)   # G5 (ED5): ships on water, shore rules
		if why != "":
			ed.status(why, HT.YELLOW)
			continue
		ents().append(M.make_entity(pick_kind, pick_def, owner, o, facing, built))
		n += 1
	return n


func place_formation(a: Vector2i, b: Vector2i) -> int:
	var s := _size_of(pick_kind, pick_def)
	var n := 0
	for o in M.formation_cells(a, b, s, int(ed.doc.map.w), int(ed.doc.map.h)):
		n += place_at(o)
	return n


# ------------------------------------------------------------------ map tool
func tool_begin(c: Vector2i) -> void:
	match mode:
		"place":
			if ed.view.in_map(c):
				_edit("Place %s" % pick_def, func(): place_at(c))
		"formation":
			_a = c
		"select":
			select_index(M.entity_at(ents(), c))
			if selected >= 0:
				_move_from = c
				ed.doc.begin_stroke("Move")


func tool_drag(c: Vector2i) -> void:
	if mode != "select" or _move_from == null or selected < 0:
		return
	var d: Vector2i = c - Vector2i(_move_from)
	if d == Vector2i.ZERO:
		return
	var e: Dictionary = ents()[selected]
	e["cell"] = M.ent_cell(e) + d
	e.erase("pos")
	_move_from = c
	ed.view._sync_world()


func tool_end(c: Vector2i) -> void:
	if mode == "formation" and _a != null:
		var a: Vector2i = _a
		_a = null
		_edit("Formation", func(): place_formation(a, c))
	elif mode == "select" and _move_from != null:
		_move_from = null
		ed.stroke_done()
		after_edit()


func tool_cancel() -> void:
	_a = null
	if _move_from != null:
		_move_from = null
		ed.stroke_done()
		after_edit()


func tool_preview(c: Vector2i) -> Dictionary:
	var cells: Array = []
	var col := Color(0.3, 0.9, 1.0, 0.35)
	if mode == "formation" and _a != null:
		for o in M.formation_cells(_a, c, _size_of(pick_kind, pick_def), int(ed.doc.map.w), int(ed.doc.map.h)):
			cells.append(o)
	elif mode == "place":
		var s := _size_of(pick_kind, pick_def)
		for fp in Symmetry.footprints(c, Vector2i(s, s), ed.doc.symmetry, int(ed.doc.map.w), int(ed.doc.map.h)):
			for y in s:
				for x in s:
					cells.append(Vector2i(fp[0]) + Vector2i(x, y))
	if selected >= 0 and selected < ents().size():
		var r := M.footprint(ents()[selected])
		for y in r.size.y:
			for x in r.size.x:
				cells.append(r.position + Vector2i(x, y))
	return {"cells": cells, "color": col, "text": "%s %d°" % [pick_def, roundi(rad_to_deg(facing))] if mode != "select" else ""}


func select_index(i: int) -> void:
	selected = i
	sel.refresh()


func _on_doc_changed(_cells: Array, kind: String) -> void:
	if kind == "terrain":
		return
	if selected >= ents().size():
		selected = -1
	if is_visible_in_tree():
		refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not is_visible_in_tree() or ed.view._typing():
		return
	if k.keycode == KEY_Q:
		rotate_facing(-1)
	elif k.keycode == KEY_E:
		rotate_facing(1)
	elif k.keycode == KEY_DELETE and selected >= 0:
		sel.delete_selected()
	else:
		return
	get_viewport().set_input_as_handled()
