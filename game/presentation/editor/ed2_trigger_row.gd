extends VBoxContainer
## One trigger in the Victory & triggers tab (owner: ED2): name, once, delete; WHEN type + params;
## THEN actions (type + params, x) and "+ action". All writes go through the tab (undo steps).

const W = preload("res://presentation/editor/editor_widgets.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const M = preload("res://presentation/editor/ed2_model.gd")
const P = preload("res://presentation/editor/ed2_params.gd")

var tab
var idx := 0


func setup(t, i: int) -> void:
	tab = t
	idx = i
	add_theme_constant_override("separation", 2)
	add_child(HSeparator.new())
	var tr: Dictionary = tab.triggers()[i]
	var top := HBoxContainer.new()
	add_child(top)
	top.add_child(HT.make_label(String(tr.get("id", "t%d" % (i + 1))), HT.AMBER, 14))
	var nm := LineEdit.new()
	nm.name = "ED2T%dName" % i
	nm.placeholder_text = "name"
	nm.text = String(tr.get("name", ""))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.text_changed.connect(func(s: String): tab.set_trigger_field(idx, "name", s))
	top.add_child(nm)
	var once := CheckBox.new()
	once.name = "ED2T%dOnce" % i
	once.text = "once"
	once.focus_mode = Control.FOCUS_NONE
	once.button_pressed = bool(tr.get("once", true))
	once.toggled.connect(func(on: bool): tab.set_trigger_field(idx, "once", on))
	top.add_child(once)
	W.button(top, "x", func(): tab.remove_trigger(idx), "Delete this trigger")
	# WHEN
	var w: Dictionary = tab.when_of(i)
	var wr := HBoxContainer.new()
	add_child(wr)
	wr.add_child(HT.make_label("WHEN", HT.GREEN, 13))
	var wo := _type_opt(M.WHEN_TYPES, String(w.get("type", "")), "ED2T%dWhen" % i)
	wo.item_selected.connect(func(k: int): tab.set_when_type(idx, M.WHEN_TYPES[k]))
	wr.add_child(wo)
	if tr.get("when") is Array and (tr.when as Array).size() > 1:
		W.note(self, "(+%d more AND conditions from the file are kept)" % ((tr.when as Array).size() - 1))
	P.build(self, M.WHEN_SPEC.get(String(w.get("type", "")), []), w, tab.ctx, func(k, v): tab.set_when_param(idx, k, v), "ED2T%dW_" % i)
	# THEN
	var acts: Array = tab.actions_of(i)
	for j in acts.size():
		var a: Dictionary = acts[j]
		var ar := HBoxContainer.new()
		add_child(ar)
		ar.add_child(HT.make_label("THEN" if j == 0 else "AND", HT.YELLOW, 13))
		var ao := _type_opt(M.THEN_TYPES, String(a.get("type", "")), "ED2T%dThen%d" % [i, j])
		ao.item_selected.connect(func(k: int): tab.set_action_type(idx, j, M.THEN_TYPES[k]))
		ar.add_child(ao)
		W.button(ar, "x", func(): tab.remove_action(idx, j), "Remove this action")
		P.build(self, M.THEN_SPEC.get(String(a.get("type", "")), []), a, tab.ctx,
			func(k, v): tab.set_action_param(idx, j, k, v), "ED2T%dA%d_" % [i, j])
	var add := W.button(self, "+ action", func(): tab.add_action(idx))
	add.name = "ED2T%dAddAction" % i


func _type_opt(types: Array, cur: String, nm: String) -> OptionButton:
	var o := OptionButton.new()
	o.name = nm
	o.focus_mode = Control.FOCUS_NONE
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in types:
		o.add_item(String(t).replace("_", " "))
	var k := types.find(cur)
	if k < 0 and cur != "":
		o.add_item("%s (unknown)" % cur)
		k = o.item_count - 1
	o.select(maxi(0, k))
	return o
