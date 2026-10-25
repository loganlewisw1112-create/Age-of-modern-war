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
const Airfield = preload("res://sim/systems/airfield.gd")
const MODES := ["place", "select", "formation", "minefield", "company"]   # G6 (ED6): minefield rect, company block
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
var mine_kind := "mixed"          # G6: minefield mode mine kind (M.MINE_KINDS)
var company_tid := ""             # G6: company mode template id
var _company_opt: OptionButton
var _company_ids: Array = []


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
	_mode_btns = W.choice_row(self, ["Place", "Select / move", "Formation box", "Minefield", "Company block"], 0, func(i: int): set_mode(MODES[i]))
	W.option(self, "Mines", ["Mixed", "Anti-tank", "Anti-personnel"], 0, func(i: int): mine_kind = M.MINE_KINDS[i])
	_company_opt = W.option(self, "Company", [""], 0, func(i: int): company_tid = String(_company_ids[i]) if i < _company_ids.size() else "")
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
	fill_companies()


## G6: company templates of the current player's faction (ARMY6 presets).
func fill_companies() -> void:
	if _company_opt == null:
		return
	var players: Array = ed.doc.scenario.get("players", [])
	var fac := String(players[slot_idx].get("faction", "human_a")) if slot_idx < players.size() else "human_a"
	var Companies = load("res://sim/systems/companies.gd")
	_company_ids = Companies.templates_for(fac)
	_company_opt.clear()
	for tid in _company_ids:
		_company_opt.add_item(String(Companies.presets().get(tid, {}).get("name", tid)))
	if not _company_ids.has(company_tid):
		company_tid = String(_company_ids[0]) if not _company_ids.is_empty() else ""
	if company_tid != "":
		_company_opt.select(_company_ids.find(company_tid))


## G6: one minefield over a..b for the current player (one undo step via the caller). Returns 1 or 0.
func place_minefield(a: Vector2i, b: Vector2i) -> int:
	if not ed.view.in_map(a) or not ed.view.in_map(b):
		return 0
	ents().append(M.make_minefield(current_slot(), a, b, mine_kind))
	return 1


## G6: the selected company template as one block at origin. Returns the number of units placed.
func place_company(origin: Vector2i) -> int:
	if company_tid == "":
		ed.status("Pick a company template first.", HT.YELLOW)
		return 0
	var blk: Array = M.company_block(company_tid, current_slot(), origin, ed.doc.map, facing)
	ents().append_array(blk)
	return blk.size()


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
		_edit("Rotate", func():
			ents()[selected]["facing"] = facing
			if is_field("building", String(ents()[selected].get("def", ""))):
				ents()[selected]["facing_i"] = facing_i())


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
		if why == "" and is_field(pick_kind, pick_def):
			why = Airfield.site_ok(ed.view.world, pick_def, o, facing_i())   # G6 airfield v2: apron + runway room
		if why != "":
			ed.status(why, HT.YELLOW)
			continue
		var ent := M.make_entity(pick_kind, pick_def, owner, o, facing, built)
		if is_field(pick_kind, pick_def):
			ent["facing_i"] = facing_i()
		ents().append(ent)
		n += 1
	return n


func place_formation(a: Vector2i, b: Vector2i) -> int:
	var s := _size_of(pick_kind, pick_def)
	var n := 0
	for o in M.formation_cells(a, b, s, int(ed.doc.map.w), int(ed.doc.map.h)):
		n += place_at(o)
	return n


# ------------------------------------------------------------------ map tool
## G6 Live (ED6): placing stays available while Live runs; the unit goes into the Live world only.
func live_ok() -> bool:
	return mode == "place" and pick_def != ""


func tool_begin(c: Vector2i) -> void:
	if ed.has_method("live_on") and ed.live_on():
		if mode == "place" and ed.view.in_map(c) and pick_def != "":
			var why := M.place_reason(ed.doc.map, pick_kind, pick_def, c)
			if why == "" and ed.live_place(M.make_entity(pick_kind, pick_def, current_slot(), c, facing, built)) >= 0:
				ed.status("Live: %s placed for P%d (gone when Live stops)." % [pick_def, current_slot() + 1], HT.GREEN)
			else:
				ed.status("Live: cannot place %s here. %s" % [pick_def, why], HT.YELLOW)
		return
	match mode:
		"place":
			if ed.view.in_map(c):
				_edit("Place %s" % pick_def, func(): place_at(c))
		"formation", "minefield":
			_a = c
		"company":
			if ed.view.in_map(c):
				_edit("Company %s" % company_tid, func(): place_company(c))
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
	elif mode == "minefield" and _a != null:
		var a2: Vector2i = _a
		_a = null
		_edit("Minefield", func(): place_minefield(a2, c))
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


## G6 airfield v2 (ECON-AIRF6 CR): fields have a 2x2 base plus an apron and runways laid out by facing.
static func is_field(kind: String, def: String) -> bool:
	return kind == "building" and not Airfield.layout_for(def, Vector2i.ZERO, 0, 0).is_empty()


## The 4-way field facing (0..3) for the current facing angle.
func facing_i() -> int:
	return posmod(roundi(facing / (PI * 0.5)), 4)


## Apron slot cells and runway lines of a field placed at origin o (preview + selection).
static func field_preview(def: String, o: Vector2i, fi: int, extra: int = 0) -> Dictionary:
	var lo := Airfield.layout_for(def, o, fi, extra)
	var cells: Array = []
	var lines: Array = []
	if lo.is_empty():
		return {"cells": cells, "lines": lines}
	var ss := int(lo.slot_size)
	for sc in lo.slots:
		for y in ss:
			for x in ss:
				cells.append(Vector2i(sc) + Vector2i(x, y))
	for rw in lo.runways:
		var a: Vector2 = rw[0]
		var b: Vector2 = rw[1]
		lines.append([Vector2i(floori(a.x), floori(a.y)), Vector2i(floori(b.x), floori(b.y))])
	return {"cells": cells, "lines": lines}


func tool_preview(c: Vector2i) -> Dictionary:
	var cells: Array = []
	var lines: Array = []
	var col := Color(0.3, 0.9, 1.0, 0.35)
	var note := ""
	if mode == "minefield":
		var mf := M.footprint(M.make_minefield(current_slot(), _a if _a != null else c, c, mine_kind))
		for y in mf.size.y:
			for x in mf.size.x:
				cells.append(mf.position + Vector2i(x, y))
		col = Color(0.9, 0.25, 0.2, 0.4)
	elif mode == "company" and company_tid != "":
		for e in M.company_block(company_tid, current_slot(), c, ed.doc.map):
			cells.append(M.ent_cell(e))
	if mode == "place" and is_field(pick_kind, pick_def):
		var fp := field_preview(pick_def, c, facing_i())
		cells.append_array(fp.cells)
		lines.append_array(fp.lines)
		note = Airfield.site_ok(ed.view.world, pick_def, c, facing_i())
		if note != "":
			col = Color(1.0, 0.35, 0.3, 0.4)
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
	if selected >= 0 and selected < ents().size() and is_field("building", String(ents()[selected].get("def", ""))):
		var se: Dictionary = ents()[selected]
		var sp := field_preview(String(se.def), M.ent_cell(se), int(se.get("facing_i", 0)), int(se.get("extra_strips", 0)))
		cells.append_array(sp.cells)
		lines.append_array(sp.lines)
	var txt := "%s %d°" % [pick_def, roundi(rad_to_deg(facing))] if mode != "select" else ""
	if note != "":
		txt += "  " + note
	return {"cells": cells, "lines": lines, "color": col, "text": txt}


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
