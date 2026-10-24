extends VBoxContainer
## Selected placed entity (owner: ED2): properties panel lines, tag, built toggle, delete, and the
## carrier cargo list ("Load picked unit" adds the palette's unit def, x removes one).
## Part of the Units & buildings tab (ed2_tab_units.gd).

const W = preload("res://presentation/editor/editor_widgets.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const M = preload("res://presentation/editor/ed2_model.gd")

var tab                       # ed2_tab_units.gd
var _title: Label
var tag_edit: LineEdit
var _built: CheckBox
var _cargo_box: VBoxContainer
var _load_btn: Button
var _quiet := false


func setup(t) -> void:
	tab = t
	add_theme_constant_override("separation", 4)
	W.header(self, "Selected")
	_title = HT.make_label("Nothing selected (Select / move mode, click an entity).", HT.DIM, 13)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)
	tag_edit = W.line(self, "Tag", "", _on_tag)
	tag_edit.name = "ED2Tag"
	tag_edit.placeholder_text = "for triggers / destroy target"
	_built = W.check(self, "Built", true, _on_built)
	var row := HBoxContainer.new()
	add_child(row)
	W.button(row, "Delete (Del)", delete_selected)
	W.button(row, "Deselect", func(): tab.select_index(-1))
	W.header(self, "Cargo")
	_cargo_box = VBoxContainer.new()
	add_child(_cargo_box)
	_load_btn = W.button(self, "Load picked unit", load_picked, "Adds the palette's unit to this carrier's cargo")


func _ent():
	var i: int = tab.selected
	var ents: Array = tab.ents()
	return ents[i] if i >= 0 and i < ents.size() else null


func refresh() -> void:
	var e = _ent()
	_quiet = true
	for c in _cargo_box.get_children():
		_cargo_box.remove_child(c)
		c.queue_free()
	if e == null:
		_title.text = "Nothing selected (Select / move mode, click an entity)."
		tag_edit.text = ""
		tag_edit.editable = false
		_built.disabled = true
		_load_btn.disabled = true
		_quiet = false
		return
	var kind := String(e.get("kind", "unit"))
	var def := String(e.get("def", ""))
	var cell := M.ent_cell(e)
	_title.text = "#%d %s  P%d  at %d,%d  facing %d°" % [tab.selected, M.def_label(kind, def), int(e.get("owner_slot", 0)) + 1,
		cell.x, cell.y, roundi(rad_to_deg(float(e.get("facing", 0.0))))]
	if tag_edit.text != String(e.get("tag", "")):
		tag_edit.text = String(e.get("tag", ""))
	tag_edit.editable = true
	_built.disabled = kind != "building"
	_built.button_pressed = bool(e.get("built", true))
	var carrier := kind == "unit" and M.is_carrier(def)
	_load_btn.disabled = not carrier
	var cargo: Array = e.get("cargo", [])
	if not carrier:
		W.note(_cargo_box, "Not a carrier.")
	elif cargo.is_empty():
		W.note(_cargo_box, "Empty (%d slots)." % int(Content.unit(def).cargo_slots))
	for i in cargo.size():
		var r := HBoxContainer.new()
		_cargo_box.add_child(r)
		r.add_child(HT.make_label(M.def_label("unit", String(cargo[i])), HT.TEXT, 13))
		W.button(r, "x", remove_cargo.bind(i), "Remove from cargo")
	var lines: Array = ["Owner: P%d" % (int(e.get("owner_slot", 0)) + 1), "Cell: %d, %d" % [cell.x, cell.y]]
	if String(e.get("tag", "")) != "":
		lines.append("Tag: %s" % e.tag)
	if not cargo.is_empty():
		lines.append("Cargo: %s" % ", ".join(PackedStringArray(cargo)))
	tab.ed.set_properties(M.def_label(kind, def), lines)
	_quiet = false


func _on_tag(t: String) -> void:
	if _quiet or _ent() == null:
		return
	set_tag(t.strip_edges())


func set_tag(t: String) -> void:
	var i: int = tab.selected
	tab.ed.doc.begin_stroke("Tag")
	if t == "":
		tab.ents()[i].erase("tag")
	else:
		tab.ents()[i]["tag"] = t
	tab.ed.stroke_done()
	tab.ed.view.overlay.queue_redraw()


func _on_built(on: bool) -> void:
	if _quiet or _ent() == null:
		return
	var i: int = tab.selected
	tab._edit("Built", func(): tab.ents()[i]["built"] = on)


func delete_selected() -> void:
	var i: int = tab.selected
	if _ent() == null:
		return
	tab.selected = -1
	tab._edit("Delete", func(): tab.ents().remove_at(i))


## Adds the palette's picked unit to the selected carrier. Returns "" or the refusal reason.
func load_picked() -> String:
	var e = _ent()
	if e == null:
		return "nothing selected"
	if tab.pick_kind != "unit":
		tab.ed.status("Pick a unit in the palette to load it.", HT.YELLOW)
		return "pick a unit"
	var cargo: Array = e.get("cargo", [])
	var why := M.cargo_reason(String(e.def), cargo, String(tab.pick_def))
	if why != "":
		tab.ed.status(why, HT.YELLOW)
		return why
	var i: int = tab.selected
	var def: String = tab.pick_def
	tab._edit("Load %s" % def, func():
		var ent: Dictionary = tab.ents()[i]
		var cg: Array = ent.get("cargo", [])
		cg.append(def)
		ent["cargo"] = cg)
	return ""


func remove_cargo(k: int) -> void:
	var i: int = tab.selected
	tab._edit("Unload", func():
		var ent: Dictionary = tab.ents()[i]
		var cg: Array = ent.get("cargo", [])
		cg.remove_at(k)
		if cg.is_empty():
			ent.erase("cargo")
		else:
			ent["cargo"] = cg)
