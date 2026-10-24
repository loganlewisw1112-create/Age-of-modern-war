extends VBoxContainer
## Players tab (owner: ED2, PLAN_G4 section 3.1 tab 7): 4 slots (Human / AI / Closed, faction,
## team, colour, start stage, credits, start stock, AI difficulty), a start-position marker per
## player ("Set start", then click the map; with symmetry on, the mirrored images become the other
## players' starts) and the "start packages" toggle. A closed slot is absent from
## scenario.players. Each change is one undo step.

const W = preload("res://presentation/editor/editor_widgets.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const M = preload("res://presentation/editor/ed2_model.gd")
const Symmetry = preload("res://presentation/editor/symmetry.gd")
const G3bData = preload("res://presentation/hud/g3b_data.gd")
const KINDS := ["Human", "AI", "Closed"]
const STOCK_KEYS := ["salvage", "ore", "fuel", "ammo"]

var ed
var rows: Array = []              # per slot: {kind, faction, team, color, stage, credits, diff, stock{}, start, chip}
var arm_slot := -1                # slot waiting for a start click
var _quiet := false
var _pk: CheckBox
var _facs: Array = []
var _stages: Array = []
var _diffs: Array = []
var _cols: Array = []


func setup(editor) -> void:
	ed = editor
	add_theme_constant_override("separation", 6)
	_facs = Content.faction_ids()
	_stages = G3bData.playable_stages()
	_diffs = Array(Content.rules().get("ai_difficulties", {}).keys())
	if _diffs.is_empty():
		_diffs = ["normal"]
	_cols = M.colors()
	W.header(self, "Players (2-4)")
	_pk = W.check(self, "Start packages on (HQ + starting units)", true, _on_pk)
	_pk.name = "ED2StartPackages"
	for s in M.MAX_PLAYERS:
		rows.append(_make_row(s))
	W.note(self, "Set start, then click the map. With symmetry on, mirrored starts go to the other players.")
	ed.doc.changed.connect(_on_doc_changed)
	refresh()


func _opt(parent: Control, items: Array, nm: String, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.name = nm
	o.focus_mode = Control.FOCUS_NONE
	for it in items:
		o.add_item(String(it))
	o.item_selected.connect(func(_i): _fire(cb))
	parent.add_child(o)
	return o


func _spin(parent: Control, lo: float, hi: float, step: float, nm: String, tip: String, cb: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.name = nm
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.tooltip_text = tip
	s.custom_minimum_size = Vector2(84, 0)
	s.value_changed.connect(func(_v): _fire(cb))
	parent.add_child(s)
	return s


func _make_row(s: int) -> Dictionary:
	var box := VBoxContainer.new()
	add_child(box)
	box.add_child(HSeparator.new())
	var r := {"box": box}
	var l1 := HFlowContainer.new()
	box.add_child(l1)
	r.chip = TextureRect.new()
	l1.add_child(r.chip)
	l1.add_child(HT.make_label("P%d" % (s + 1), HT.AMBER, 15))
	r.kind = _opt(l1, KINDS, "ED2P%dKind" % s, _changed.bind(s, "kind"))
	var fnames: Array = []
	for f in _facs:
		fnames.append(String(Content.faction(String(f)).get("name", f)))
	r.faction = _opt(l1, fnames, "ED2P%dFaction" % s, _changed.bind(s, "faction"))
	var l2 := HFlowContainer.new()
	box.add_child(l2)
	var teams: Array = []
	for t in M.MAX_PLAYERS:
		teams.append("Team %d" % (t + 1))
	r.team = _opt(l2, teams, "ED2P%dTeam" % s, _changed.bind(s, "team"))
	r.color = OptionButton.new()
	r.color.name = "ED2P%dColor" % s
	r.color.focus_mode = Control.FOCUS_NONE
	for c in _cols:
		r.color.add_icon_item(W.chip(Color(String(c))), "")
	r.color.item_selected.connect(func(_i): _fire(_changed.bind(s, "color")))
	l2.add_child(r.color)
	var snames: Array = []
	for st in _stages:
		snames.append("Stage %d" % int(st))
	r.stage = _opt(l2, snames, "ED2P%dStage" % s, _changed.bind(s, "stage"))
	var l3 := HFlowContainer.new()
	box.add_child(l3)
	r.credits = _spin(l3, 0, 50000, 250, "ED2P%dCredits" % s, "Starting credits", _changed.bind(s, "credits"))
	var dn: Array = []
	for d in _diffs:
		dn.append(String(d).capitalize())
	r.diff = _opt(l3, dn, "ED2P%dDiff" % s, _changed.bind(s, "diff"))
	r.start_btn = W.button(l3, "Set start", arm_start.bind(s), "Then click the map")
	r.start_btn.name = "ED2P%dStart" % s
	var l4 := GridContainer.new()   # label + spin pairs stay together (a flow row split them)
	l4.columns = 4
	box.add_child(l4)
	r.stock = {}
	for k in STOCK_KEYS:
		l4.add_child(HT.make_label(k.capitalize(), HT.DIM, 12))
		r.stock[k] = _spin(l4, 0, 20000, 50, "ED2P%dStock_%s" % [s, k], "Start stock: %s" % k, _changed.bind(s, "stock"))
	r.start_lbl = HT.make_label("", HT.DIM, 12)
	box.add_child(r.start_lbl)
	return r


func _fire(cb: Callable) -> void:
	if not _quiet:
		cb.call()


func _on_doc_changed(_cells: Array, kind: String) -> void:
	if kind != "terrain":
		refresh()


func players() -> Array:
	return ed.doc.scenario.get("players", [])


func player_index(slot: int) -> int:
	var ps := players()
	for i in ps.size():
		if int(ps[i].slot) == slot:
			return i
	return -1


func refresh() -> void:
	_quiet = true
	_pk.button_pressed = bool(ed.doc.map.get("start_packages", true))
	for s in rows.size():
		var r: Dictionary = rows[s]
		var i := player_index(s)
		var open := i >= 0
		var p: Dictionary = players()[i] if open else {}
		(r.kind as OptionButton).select(2 if not open else (1 if bool(p.get("ai", false)) else 0))
		for k in ["faction", "team", "color", "stage", "diff", "start_btn"]:
			r[k].disabled = not open
		(r.credits as SpinBox).editable = open
		for k in STOCK_KEYS:
			(r.stock[k] as SpinBox).editable = open
		(r.box as Control).modulate = Color.WHITE if open else Color(1, 1, 1, 0.5)
		if not open:
			r.start_lbl.text = "(closed)"
			(r.chip as TextureRect).texture = W.chip(Color(0.25, 0.25, 0.25))
			continue
		(r.faction as OptionButton).select(maxi(0, _facs.find(String(p.get("faction", "human_a")))))
		(r.team as OptionButton).select(clampi(int(p.get("team", s)), 0, M.MAX_PLAYERS - 1))
		var ci := _cols.find(String(p.get("color", "")))
		(r.color as OptionButton).select(ci if ci >= 0 else s % _cols.size())
		(r.stage as OptionButton).select(maxi(0, _stages.find(int(p.get("stage", 8)))))
		(r.diff as OptionButton).select(maxi(0, _diffs.find(String(p.get("difficulty", "normal")))))
		(r.diff as OptionButton).disabled = not bool(p.get("ai", false))
		(r.credits as SpinBox).value = int(p.get("credits", 2500))
		var st: Dictionary = p.get("stock", {})
		for k in STOCK_KEYS:
			(r.stock[k] as SpinBox).value = int(st.get(k, 0))
		var c: Vector2i = M.MapIO._v2i(p.get("start", Vector2i.ZERO))
		r.start_lbl.text = "Start %d, %d%s" % [c.x, c.y, "   (click the map)" if arm_slot == s else ""]
		(r.chip as TextureRect).texture = W.chip(Color(String(_cols[(r.color as OptionButton).selected])))
	_quiet = false


## Reads row `s` back into scenario.players (one undo step). field "kind" may open/close the slot.
func _changed(s: int, field: String) -> void:
	var r: Dictionary = rows[s]
	var i := player_index(s)
	var kind: int = (r.kind as OptionButton).selected
	if field == "kind" and kind == 2:
		if i >= 0 and players().size() <= 2:
			ed.status("A map needs at least 2 players.", HT.YELLOW)
			refresh()
			return
		if i >= 0:
			_edit("Close P%d" % (s + 1), func(): players().remove_at(i))
		return
	if i < 0:
		_edit("Open P%d" % (s + 1), func():
			var p := M.default_player(s, M.corner_start(s, int(ed.doc.map.w), int(ed.doc.map.h)))
			p.ai = kind == 1
			var ps := players()
			var at := 0
			while at < ps.size() and int(ps[at].slot) < s:
				at += 1
			ps.insert(at, p))
		return
	_edit("P%d %s" % [s + 1, field], func():
		var p: Dictionary = players()[i]
		p.ai = kind == 1
		p.faction = String(_facs[maxi(0, (r.faction as OptionButton).selected)])
		p.team = (r.team as OptionButton).selected
		p.color = String(_cols[maxi(0, (r.color as OptionButton).selected)])
		p.stage = int(_stages[maxi(0, (r.stage as OptionButton).selected)]) if not _stages.is_empty() else 8
		p.credits = int((r.credits as SpinBox).value)
		p.difficulty = String(_diffs[maxi(0, (r.diff as OptionButton).selected)])
		var st := {}
		for k in STOCK_KEYS:
			if int((r.stock[k] as SpinBox).value) > 0:
				st[k] = int((r.stock[k] as SpinBox).value)
		p.stock = st)


func _edit(label: String, fn: Callable) -> void:
	ed.doc.begin_stroke(label)
	fn.call()
	ed.stroke_done()
	ed.view._sync_world()
	ed.view.overlay.queue_redraw()
	refresh()


func _on_pk(on: bool) -> void:
	if _quiet:
		return
	_edit("Start packages", func(): ed.doc.map["start_packages"] = on)


func arm_start(s: int) -> void:
	arm_slot = s
	ed.status("Click the map to place P%d's start." % (s + 1), HT.AMBER)
	refresh()


## Sets slot's start at c; symmetric images go to the following players (slot order, wrapping).
func set_start(s: int, c: Vector2i) -> void:
	var i := player_index(s)
	if i < 0:
		return
	var imgs: Array = Symmetry.images(c, ed.doc.symmetry, int(ed.doc.map.w), int(ed.doc.map.h))
	_edit("Start P%d" % (s + 1), func():
		var ps := players()
		for k in imgs.size():
			if k >= ps.size():
				break
			ps[(i + k) % ps.size()]["start"] = imgs[k])


func tool_begin(c: Vector2i) -> void:
	if arm_slot >= 0 and ed.view.in_map(c):
		var s := arm_slot
		arm_slot = -1
		set_start(s, c)


func tool_cancel() -> void:
	if arm_slot >= 0:
		arm_slot = -1
		refresh()


func tool_preview(c: Vector2i) -> Dictionary:
	if arm_slot < 0:
		return {"cells": [], "color": Color(1, 1, 1, 0)}
	return {"cells": Symmetry.images(c, ed.doc.symmetry, int(ed.doc.map.w), int(ed.doc.map.h)), "color": Color(1, 0.85, 0.2, 0.6),
		"text": "P%d start" % (arm_slot + 1)}
