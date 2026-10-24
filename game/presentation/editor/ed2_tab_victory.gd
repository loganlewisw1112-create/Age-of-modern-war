extends VBoxContainer
## Victory & triggers tab (owner: ED2, PLAN_G4 section 3.1 tab 8, CONTRACTS_G4 section 5).
## Victory: a list of preset terms (HQ elimination, territory %, hold bridge, survive, destroy
## target, reach stage, hold point) joined by AND/OR -> scenario.victory (one term = that preset,
## several = combined). Triggers: WHEN (one condition) THEN (actions), once; each row is
## ed2_trigger_row.gd. Every edit is one undo step; values are typed exactly (ed2_scenario.clause).

const W = preload("res://presentation/editor/editor_widgets.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const M = preload("res://presentation/editor/ed2_model.gd")
const S = preload("res://presentation/editor/ed2_scenario.gd")
const P = preload("res://presentation/editor/ed2_params.gd")
const TRow = preload("res://presentation/editor/ed2_trigger_row.gd")

var ed
var op := "and"
var ctx: Dictionary = {}
var _op_btns: Array = []
var _terms_box: VBoxContainer
var _trig_box: VBoxContainer
var _add_term: OptionButton


func setup(editor) -> void:
	ed = editor
	add_theme_constant_override("separation", 6)
	W.header(self, "Victory")
	_op_btns = W.choice_row(self, ["All of (AND)", "Any of (OR)"], 0, func(i: int): set_op("and" if i == 0 else "or"))
	_terms_box = VBoxContainer.new()
	add_child(_terms_box)
	var labels: Array = ["+ Add condition"]
	labels.append_array(M.PRESET_LABELS)
	_add_term = W.option(self, "", labels, 0, func(i: int):
		if i > 0:
			add_term(M.PRESETS[i - 1])
		_add_term.select(0))
	_add_term.name = "ED2AddVictory"
	W.header(self, "Triggers")
	_trig_box = VBoxContainer.new()
	add_child(_trig_box)
	var b := W.button(self, "Add trigger", add_trigger)
	b.name = "ED2AddTrigger"
	W.note(self, "Regions for triggers and hold point are drawn in the Regions tab; tags are set on placed entities.")
	ed.doc.changed.connect(_on_doc_changed)
	rebuild()


func tab_activated() -> void:
	rebuild()


func _on_doc_changed(_cells: Array, kind: String) -> void:
	if kind != "terrain" and is_visible_in_tree():
		rebuild()


func _edit(label: String, fn: Callable) -> void:
	ed.doc.begin_stroke(label)
	fn.call()
	ed.stroke_done()


# ------------------------------------------------------------------ victory
func state() -> Dictionary:
	return S.terms_from_victory(ed.doc.scenario.get("victory", {}))


## Takes the AND/OR from the document when it is a combined block (undo, open).
func sync_op() -> void:
	if String(ed.doc.scenario.get("victory", {}).get("victory", "")) == "combined":
		op = String(state().op)


func write_terms(terms: Array) -> void:
	_edit("Victory", func(): ed.doc.scenario["victory"] = S.victory_from_terms(terms, op))


func set_op(o: String) -> void:
	op = o
	write_terms(state().terms)


func add_term(type: String) -> void:
	var t: Array = state().terms
	t.append(S.preset_term(type))
	write_terms(t)
	rebuild()


func remove_term(i: int) -> void:
	var t: Array = state().terms
	if i < t.size():
		t.remove_at(i)
	write_terms(t)
	rebuild()


func set_term_type(i: int, type: String) -> void:
	var t: Array = state().terms
	t[i] = S.preset_term(type)
	write_terms(t)
	rebuild()


func set_term_param(i: int, key: String, v) -> void:
	var t: Array = state().terms
	var kind := "str"
	for s in M.PRESET_PARAMS.get(String(t[i].type), []):
		if s[0] == key:
			kind = String(s[1])
	t[i][key] = S.coerce(kind, v)
	write_terms(t)


# ------------------------------------------------------------------ triggers
func triggers() -> Array:
	if not ed.doc.scenario.has("triggers"):
		ed.doc.scenario["triggers"] = []
	return ed.doc.scenario.triggers


## The editable condition of trigger i (the first one when `when` is an ANDed list).
func when_of(i: int) -> Dictionary:
	var w = triggers()[i].get("when", {})
	if w is Array:
		return w[0] if not (w as Array).is_empty() else {}
	return w


func _set_when(i: int, c: Dictionary) -> void:
	var tr: Dictionary = triggers()[i]
	if tr.get("when") is Array and not (tr.when as Array).is_empty():
		tr.when[0] = c
	else:
		tr["when"] = c


func _spec_kind(table: Dictionary, type: String, key: String) -> String:
	for s in table.get(type, []):
		if s[0] == key:
			return String(s[1])
	return "str"


func add_trigger() -> void:
	_edit("Add trigger", func(): triggers().append(S.new_trigger(triggers())))
	rebuild()


func remove_trigger(i: int) -> void:
	_edit("Delete trigger", func(): triggers().remove_at(i))
	rebuild()


func set_trigger_field(i: int, key: String, v) -> void:
	_edit("Trigger %s" % key, func(): triggers()[i][key] = v)


func set_when_type(i: int, type: String) -> void:
	_edit("Trigger when", func(): _set_when(i, _defaults(S.clause(type, {}, true))))
	rebuild()


func set_when_param(i: int, key: String, v) -> void:
	var kind := _spec_kind(M.WHEN_SPEC, String(when_of(i).get("type", "")), key)
	_edit("Trigger when", func():
		var c := when_of(i).duplicate()
		c[key] = S.coerce(kind, v)
		_set_when(i, c))


func actions_of(i: int) -> Array:
	var th = triggers()[i].get("then", [])
	if th is Dictionary:
		triggers()[i]["then"] = [th]
	return triggers()[i]["then"]


func add_action(i: int) -> void:
	_edit("Trigger action", func(): actions_of(i).append(S.clause("message", {}, false)))
	rebuild()


func remove_action(i: int, j: int) -> void:
	_edit("Trigger action", func(): actions_of(i).remove_at(j))
	rebuild()


func set_action_type(i: int, j: int, type: String) -> void:
	_edit("Trigger action", func(): actions_of(i)[j] = _defaults(S.clause(type, {}, false)))
	rebuild()


func set_action_param(i: int, j: int, key: String, v) -> void:
	var kind := _spec_kind(M.THEN_SPEC, String(actions_of(i)[j].get("type", "")), key)
	_edit("Trigger action", func(): actions_of(i)[j][key] = S.coerce(kind, v))


## Fills picker defaults the UI cannot leave blank: the first unit def and the first region.
func _defaults(c: Dictionary) -> Dictionary:
	ctx = P.ctx_of(ed.doc)
	if c.has("def") and String(c.def) == "" and not (ctx.units as Array).is_empty():
		c.def = String(ctx.units[0])
	if c.has("region") and String(c.region) == "" and not (ctx.regions as Array).is_empty():
		c.region = String(ctx.regions[0])
	return c


# ------------------------------------------------------------------ UI
func rebuild() -> void:
	ctx = P.ctx_of(ed.doc)
	sync_op()
	var st := state()
	(_op_btns[0 if op == "and" else 1] as Button).button_pressed = true
	for box in [_terms_box, _trig_box]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	var terms: Array = st.terms
	if terms.is_empty():
		W.note(_terms_box, "No victory condition: endless match.")
	for i in terms.size():
		var t: Dictionary = terms[i]
		var row := HBoxContainer.new()
		_terms_box.add_child(row)
		var o := OptionButton.new()
		o.name = "ED2Victory%d" % i
		o.focus_mode = Control.FOCUS_NONE
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for l in M.PRESET_LABELS:
			o.add_item(String(l))
		o.select(maxi(0, M.PRESETS.find(String(t.type))))
		o.item_selected.connect(func(k: int): set_term_type(i, M.PRESETS[k]))
		row.add_child(o)
		W.button(row, "x", remove_term.bind(i), "Remove this condition")
		P.build(_terms_box, M.PRESET_PARAMS.get(String(t.type), []), t, ctx, func(k, v): set_term_param(i, k, v), "ED2V%d_" % i)
	for i in triggers().size():
		var r := TRow.new()
		_trig_box.add_child(r)
		r.setup(self, i)
