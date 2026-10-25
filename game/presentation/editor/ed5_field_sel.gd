extends VBoxContainer
## G5 air-field extras for the selected placed building (owner: ED5, PLAN_G5 section 9). Part of the
## Units & buildings tab (ed2_units_sel.gd). An airfield / airstrip / launch rail takes bought hangars
## (light / heavy), extra strips and aircraft that start parked; helipads take parked helicopters.
## Every change is one undo step and is checked with MapIO.field_reason before it is committed, so
## the map never holds an invalid field (Validate reports hand-edited files as field_bad).

const W = preload("res://presentation/editor/editor_widgets.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const M = preload("res://presentation/editor/ed2_model.gd")
const MapIO = preload("res://sim/map_io.gd")
const Airfield = preload("res://sim/systems/airfield.gd")

var tab                       # ed2_tab_units.gd
var _info: Label
var _btns: Array = []         # [light, heavy, strip, park, clear]


func setup(t) -> void:
	tab = t
	add_theme_constant_override("separation", 4)
	W.header(self, "Air field")
	_info = HT.make_label("", HT.DIM, 13)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	var r1 := HFlowContainer.new()
	add_child(r1)
	_btns.append(W.button(r1, "+ Light hangar", func(): add_hangar("light"), "Buy a light hangar into this field"))
	_btns.append(W.button(r1, "+ Heavy hangar", func(): add_hangar("heavy"), "Buy a heavy hangar into this field"))
	_btns.append(W.button(r1, "+ Strip", add_strip, "Add an extra strip (0..3)"))
	var r2 := HFlowContainer.new()
	add_child(r2)
	_btns.append(W.button(r2, "Park picked aircraft", park_picked, "The palette's aircraft starts parked here"))
	_btns.append(W.button(r2, "Clear", clear_field, "Remove hangars, strips and parked aircraft"))
	refresh()


func _ent():
	var i: int = tab.selected
	var ents: Array = tab.ents()
	return ents[i] if i >= 0 and i < ents.size() else null


static func is_field(e) -> bool:
	return e != null and String(e.get("kind", "unit")) == "building" \
		and Airfield.FIELD_KINDS.has(String(Content.building(String(e.get("def", ""))).get("air_field", "")))


func refresh() -> void:
	var e = _ent()
	var on := is_field(e)
	visible = on
	for b in _btns:
		(b as Button).disabled = not on
	if not on:
		return
	var parts: Array = []
	var hg: Array = e.get("hangars", [])
	parts.append("Hangars: %s" % (", ".join(PackedStringArray(hg)) if not hg.is_empty() else "none"))
	parts.append("Extra strips: %d" % int(e.get("extra_strips", 0)))
	var pk: Array = e.get("parked", [])
	parts.append("Parked: %s" % (", ".join(PackedStringArray(pk)) if not pk.is_empty() else "none"))
	_info.text = "\n".join(PackedStringArray(parts))


## Applies `fn` to a copy of the selected field; commits (one undo step) only when the result is a
## valid field. Returns "" or the reason it was refused.
func _try(label: String, fn: Callable) -> String:
	var e = _ent()
	if not is_field(e):
		return "select an air field"
	var cand: Dictionary = (e as Dictionary).duplicate(true)
	fn.call(cand)
	var why := MapIO.field_reason(cand)
	if why != "":
		tab.ed.status(why, HT.YELLOW)
		return why
	var i: int = tab.selected
	tab._edit(label, func():
		var ent: Dictionary = tab.ents()[i]
		for k in ["hangars", "parked", "extra_strips"]:
			if cand.has(k):
				ent[k] = cand[k]
			else:
				ent.erase(k))
	refresh()
	return ""


func add_hangar(cls: String) -> String:
	return _try("Add %s hangar" % cls, func(c: Dictionary):
		var hg: Array = c.get("hangars", [])
		hg.append(cls)
		c["hangars"] = hg)


func add_strip() -> String:
	return _try("Add strip", func(c: Dictionary): c["extra_strips"] = int(c.get("extra_strips", 0)) + 1)


## Parks the palette's picked unit (an aircraft) at the selected field.
func park_picked() -> String:
	if tab.pick_kind != "unit":
		tab.ed.status("Pick an aircraft in the palette to park it.", HT.YELLOW)
		return "pick an aircraft"
	var def: String = tab.pick_def
	return _try("Park %s" % def, func(c: Dictionary):
		var pk: Array = c.get("parked", [])
		pk.append(def)
		c["parked"] = pk)


func clear_field() -> String:
	return _try("Clear air field", func(c: Dictionary):
		for k in ["hangars", "parked", "extra_strips"]:
			c.erase(k))
