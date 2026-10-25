extends RefCounted
## UI6a (G6): Army Builder screen (CONTRACTS_G6 sections 3.5, 4 train_company, 8). Opened from the
## Company HQ's card or the hub. Top: pick a preset or a saved custom template + a size, and train it
## at the Company HQ. Below: the editor for custom templates (name, unit slots with counts, add unit),
## a live summary (elements / cap, platoons, cost, supply, time) with ARMY6's validation reason, and
## Save / Delete (per profile, army_model.gd) / Train custom. Model in army_model.gd.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const U = preload("res://presentation/ui6/a/ui6a_util.gd")
const AM = preload("res://presentation/ui6/a/army_model.gd")
const Companies = preload("res://sim/systems/companies.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")

const WANT_W := 820.0

var m: Dictionary = {}
var panel: PanelContainer = null
var issue: Callable = Callable()
var on_close: Callable = Callable()
var source: OptionButton            # presets then "Custom: <name>"
var size_opt: OptionButton
var train_btn: Button
var train_note: Label
var name_edit: LineEdit
var slots_box: VBoxContainer
var add_opt: OptionButton
var summary_lbl: Label
var reason_lbl: Label
var save_btn: Button
var delete_btn: Button
var train_custom_btn: Button
var status_lbl: Label
var editing: Dictionary = {}        # the custom template being edited
var _sources: Array = []            # [{kind: preset|custom, id}]
var _cands: Array = []
var _faction := ""
var _fid := 0
var _w: SimWorld = null
var _slots_sig := ""


func build(root: Control) -> PanelContainer:
	m = U.modal("ArmyBuilder", "ARMY BUILDER", "Close the Army Builder")
	panel = m.panel
	(m.close as Button).pressed.connect(func(): if on_close.is_valid(): on_close.call())
	var body: VBoxContainer = m.body
	body.add_child(UiKit.label("TRAIN A COMPANY AT THE COMPANY HQ", "header"))
	var r1 := U.row(body)
	source = U.option(r1, [], 280)
	source.name = "TemplateSource"
	size_opt = U.option(r1, [], 130)
	size_opt.name = "TemplateSize"
	for s in Companies.rules().get("sizes", ["platoon", "company", "battalion"]):
		size_opt.add_item(String(s).capitalize())
	size_opt.select(mini(1, size_opt.item_count - 1))
	train_btn = U.small_button(r1, "Train", "Train the selected template at your Company HQ", 90)
	train_btn.name = "TrainTemplate"
	train_btn.pressed.connect(train_selected)
	var edit_btn := U.small_button(r1, "Edit copy", "Load the selected template into the editor below", 100)
	edit_btn.name = "EditCopy"
	edit_btn.pressed.connect(load_selected)
	train_note = UiKit.label("", "dim")
	train_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	train_note.custom_minimum_size = Vector2(300, 0)
	body.add_child(train_note)
	body.add_child(HSeparator.new())
	body.add_child(UiKit.label("CUSTOM TEMPLATE", "header"))
	var r2 := U.row(body)
	r2.add_child(UiKit.label("Name", "dim"))
	name_edit = LineEdit.new()
	name_edit.name = "TemplateName"
	name_edit.custom_minimum_size = Vector2(220, 28)
	name_edit.max_length = AM.NAME_MAX
	name_edit.placeholder_text = "e.g. Assault Company"
	name_edit.text_changed.connect(func(t: String): editing.name = t)
	r2.add_child(name_edit)
	var new_btn := U.small_button(r2, "New", "Start an empty custom template", 70)
	new_btn.pressed.connect(func(): set_editing(AM.new_template("", _faction)))
	slots_box = VBoxContainer.new()
	slots_box.name = "Slots"
	slots_box.add_theme_constant_override("separation", 3)
	body.add_child(slots_box)
	var r3 := U.row(body)
	add_opt = U.option(r3, [], 300)
	add_opt.name = "AddUnitOption"
	var add_btn := U.small_button(r3, "Add unit", "Add one element of this unit (a squad counts once)", 100)
	add_btn.name = "AddUnit"
	add_btn.pressed.connect(func(): add_selected(1))
	var add5 := U.small_button(r3, "+5", "Add five elements of this unit", 50)
	add5.pressed.connect(func(): add_selected(5))
	summary_lbl = UiKit.label("", "body")
	summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_lbl.custom_minimum_size = Vector2(300, 0)
	body.add_child(summary_lbl)
	reason_lbl = UiKit.label("", "warn")
	reason_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_lbl.custom_minimum_size = Vector2(300, 0)
	body.add_child(reason_lbl)
	var r4 := U.row(body)
	save_btn = U.small_button(r4, "Save template", "Save to your profile (available in every match)", 140)
	save_btn.name = "SaveTemplate"
	save_btn.pressed.connect(save_editing)
	delete_btn = U.small_button(r4, "Delete", "Delete the saved template with this name from your profile", 90)
	delete_btn.name = "DeleteTemplate"
	delete_btn.pressed.connect(delete_editing)
	train_custom_btn = U.small_button(r4, "Train custom", "Train this template (exact counts) at your Company HQ", 130)
	train_custom_btn.name = "TrainCustom"
	train_custom_btn.pressed.connect(train_editing)
	status_lbl = UiKit.label("", "good")
	status_lbl.custom_minimum_size = Vector2(200, 0)
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status_lbl)
	root.add_child(panel)
	return panel


func fit(canvas: Vector2) -> void:
	U.fit_modal(m, canvas, WANT_W)


## (Re)binds the side: source list and unit candidates. Called on open and when the side changes.
func bind(w: SimWorld, fid: int) -> void:
	_w = w
	_fid = fid
	var fac := Companies.faction_of(w, fid)
	if fac == _faction and not _sources.is_empty():
		return
	_faction = fac
	refresh_sources()
	_cands = AM.candidates(_faction)
	add_opt.clear()
	for id in _cands:
		add_opt.add_item(String(Content.production(String(id)).get("name", id)))
	if editing.is_empty() or String(editing.get("faction", "")) != _faction:
		set_editing(AM.new_template("", _faction))


func refresh_sources() -> void:
	_sources.clear()
	source.clear()
	for tid in Companies.templates_for(_faction):
		_sources.append({"kind": "preset", "id": String(tid)})
		source.add_item("Preset: " + String(Companies.presets()[tid].get("name", tid)))
	for n in AM.names(_faction):
		_sources.append({"kind": "custom", "id": String(n)})
		source.add_item("Custom: " + String(n))
	if source.item_count > 0:
		source.select(0)


func current_size() -> String:
	var sizes: Array = Companies.rules().get("sizes", ["platoon", "company", "battalion"])
	return String(sizes[clampi(size_opt.selected, 0, sizes.size() - 1)])


## The selected source as a train_company template value: preset id or the custom dict.
func selected_template():
	if source.selected < 0 or source.selected >= _sources.size():
		return null
	var s: Dictionary = _sources[source.selected]
	if String(s.kind) == "preset":
		return String(s.id)
	return AM.get_template(_faction, String(s.id))


func select_source(kind: String, id: String) -> bool:
	for i in _sources.size():
		if String(_sources[i].kind) == kind and String(_sources[i].id) == id:
			source.select(i)
			return true
	return false


func set_editing(t: Dictionary) -> void:
	editing = AM.normalize(t, _faction)
	name_edit.text = String(editing.name)
	_slots_sig = "?"
	_rebuild_slots()


func load_selected() -> void:
	if source.selected < 0 or source.selected >= _sources.size() or _w == null:
		return
	var s: Dictionary = _sources[source.selected]
	if String(s.kind) == "preset":
		var t := AM.from_preset(_w, _fid, String(s.id), current_size())
		t.name = (String(t.name) + " (custom)").substr(0, AM.NAME_MAX)
		set_editing(t)
	else:
		set_editing(AM.get_template(_faction, String(s.id)))


func add_selected(n: int) -> void:
	if add_opt.selected < 0 or add_opt.selected >= _cands.size():
		return
	add_item(String(_cands[add_opt.selected]), n)


func add_item(item: String, n: int) -> void:
	AM.add_slot(editing, item, n)
	_rebuild_slots()


func _rebuild_slots() -> void:
	var sig := JSON.stringify(editing.get("slots", []))
	if sig == _slots_sig:
		return
	_slots_sig = sig
	for c in slots_box.get_children():
		slots_box.remove_child(c)
		c.queue_free()
	if (editing.slots as Array).is_empty():
		slots_box.add_child(UiKit.label("No units yet: pick a unit below and press Add unit.", "dim"))
	for i in editing.slots.size():
		var s: Dictionary = editing.slots[i]
		var hb := U.row(slots_box, 6)
		hb.add_child(U.icon_rect(String(Content.production(String(s.def)).get("spawns", [s.def])[0]), 24))
		U.cell_label(hb, String(Content.production(String(s.def)).get("name", s.def)), 260)
		var minus := U.small_button(hb, "-", "One fewer", 34)
		minus.pressed.connect(func(): AM.set_count(editing, i, int(editing.slots[i].count) - 1); _rebuild_slots())
		var cnt := U.cell_label(hb, "x%d" % int(s.count), 50, "number")
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var plus := U.small_button(hb, "+", "One more", 34)
		plus.pressed.connect(func(): AM.set_count(editing, i, int(editing.slots[i].count) + 1); _rebuild_slots())
		var rm := U.small_button(hb, "Remove", "Remove this slot", 84)
		rm.pressed.connect(func(): AM.remove_slot(editing, i); _rebuild_slots())


func save_editing() -> String:
	var r := AM.save_template(_faction, editing)
	status_lbl.text = "Saved %s to your profile." % String(editing.name) if r == "" else r
	if r == "":
		refresh_sources()
		select_source("custom", String(editing.name).strip_edges())
	return r


func delete_editing() -> String:
	var r := AM.remove_template(_faction, String(editing.get("name", "")).strip_edges())
	status_lbl.text = "Deleted %s." % String(editing.name) if r == "" else r
	if r == "":
		refresh_sources()
	return r


func _hq_id() -> int:
	if _w == null:
		return -1
	var hq := Companies.hq_of(_w, _fid)
	return int(hq.id) if not hq.is_empty() else -1


func train_selected() -> void:
	var t = selected_template()
	if t != null and issue.is_valid():
		issue.call(AM.train_cmd(_fid, _hq_id(), t, current_size()))


func train_editing() -> void:
	if issue.is_valid():
		var t := editing.duplicate(true)
		t.name = String(t.name).strip_edges()
		issue.call(AM.train_cmd(_fid, _hq_id(), t, "company"))


func update(w: SimWorld, fid: int) -> void:
	if panel == null or w == null:
		return
	bind(w, fid)
	var t = selected_template()
	var why := "Pick a template." if t == null else w.preview_command(AM.train_cmd(fid, _hq_id(), t, current_size()))
	train_btn.disabled = why != ""
	var pl_text := ""
	if t != null:
		var td: Dictionary = Companies.template(w, fid, String(t)) if typeof(t) == TYPE_STRING else t
		var pl := Companies.plan(w, fid, td, current_size(), typeof(t) == TYPE_STRING)
		pl_text = "%d elements in %d platoons + leaders  |  %s  |  supply %d  |  %ds" % [(pl.elements as Array).size(),
			int(pl.platoons), HT.cost_text(pl.cost), int(pl.pop), int(pl.time)]
	train_note.text = pl_text + ("\nUnavailable: " + why if why != "" else "")
	_rebuild_slots()
	var su := AM.summary(w, fid, editing)
	summary_lbl.text = "Elements %d / %d  |  platoons %d  |  cost %s  |  supply %d  |  train %ds" % [int(su.elements),
		int(su.cap), int(su.platoons), HT.cost_text(su.cost), int(su.pop), int(su.time)]
	var nr := AM.name_reason(String(editing.get("name", "")))
	var vr := String(su.reason)
	reason_lbl.text = vr if vr != "" else nr
	reason_lbl.visible = reason_lbl.text != ""
	save_btn.disabled = nr != "" or (editing.slots as Array).is_empty()
	delete_btn.disabled = not AM.names(_faction).has(String(editing.get("name", "")).strip_edges())
	var tw := "" if vr == "" and nr == "" else (vr if vr != "" else nr)
	if tw == "":
		var ed := editing.duplicate(true)
		ed.name = String(ed.name).strip_edges()
		tw = w.preview_command(AM.train_cmd(fid, _hq_id(), ed, "company"))
	train_custom_btn.disabled = tw != ""
	train_custom_btn.tooltip_text = "Train this template at your Company HQ" + ("\nUnavailable: " + tw if tw != "" else "")
