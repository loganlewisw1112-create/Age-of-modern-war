extends RefCounted
## UI6a (G6): Forces panel: every army card, then every company card of the side (company_card.gd),
## with the army actions (CONTRACTS_G6 section 4): form_army (a Commander + 2-4 picked companies),
## disband_army, set_company_refill, and Select (selects the formation in the world). Rebuilt only
## when the forces change (signature), so picks survive refreshes.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const U = preload("res://presentation/ui6/a/ui6a_util.gd")
const Card = preload("res://presentation/ui6/a/company_card.gd")
const Companies = preload("res://sim/systems/companies.gd")

const WANT_W := 720.0

var m: Dictionary = {}
var panel: PanelContainer = null
var issue: Callable = Callable()
var on_close: Callable = Callable()
var on_select: Callable = Callable()   # on_select(ids: Array)
var list_box: VBoxContainer
var cmd_opt: OptionButton
var form_btn: Button
var form_note: Label
var picked: Dictionary = {}            # cid -> true
var cards: Dictionary = {}             # cid -> card dict
var army_btns: Dictionary = {}         # aid -> disband Button
var _commanders: Array = []
var _sig := ""
var _fid := 0


func build(root: Control) -> PanelContainer:
	m = U.modal("ForcesPanel", "FORCES: ARMIES AND COMPANIES", "Close the forces panel")
	panel = m.panel
	(m.close as Button).pressed.connect(func(): if on_close.is_valid(): on_close.call())
	var body: VBoxContainer = m.body
	var fr := U.row(body)
	fr.add_child(UiKit.label("Form army:", "dim"))
	cmd_opt = U.option(fr, [], 270)
	cmd_opt.name = "CommanderOption"
	form_btn = U.small_button(fr, "Form army", "Form an army: the chosen Commander leads the picked companies (2-4)", 120)
	form_btn.name = "FormArmy"
	form_btn.pressed.connect(form_army)
	form_note = UiKit.label("", "dim")
	form_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_note.custom_minimum_size = Vector2(300, 0)
	body.add_child(form_note)
	list_box = VBoxContainer.new()
	list_box.name = "Forces"
	list_box.add_theme_constant_override("separation", 6)
	body.add_child(list_box)
	root.add_child(panel)
	return panel


func fit(canvas: Vector2) -> void:
	U.fit_modal(m, canvas, WANT_W)


func _signature(w: SimWorld, fid: int) -> String:
	var parts: Array = []
	for a in Companies.armies_of(w, fid):
		parts.append("a%d:%s" % [int(a.id), str(a.companies)])
	for c in Companies.companies_of(w, fid):
		var cm := Card.model(w, c)
		parts.append("c%d:%d:%s" % [int(c.id), int(cm.count), String(cm.status)])
	parts.append("k" + str(Companies.commanders_of(w, fid)))
	return "|".join(PackedStringArray(parts))


func update(w: SimWorld, fid: int) -> void:
	if panel == null or w == null:
		return
	_fid = fid
	var sig := _signature(w, fid)
	if sig != _sig:
		_sig = sig
		_rebuild(w, fid)
	var why := form_reason(w, fid)
	form_btn.disabled = why != ""
	form_note.text = why if why != "" else "Ready: %d companies picked." % picked_ids().size()


func _rebuild(w: SimWorld, fid: int) -> void:
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	cards.clear()
	army_btns.clear()
	_commanders = Companies.commanders_of(w, fid)
	var keep := cmd_opt.selected
	cmd_opt.clear()
	for cid in _commanders:
		var e: Dictionary = w.entities[int(cid)]
		var busy := not Companies.army_of(w, int(cid)).is_empty()
		cmd_opt.add_item("Commander #%d%s" % [int(cid), " (in army)" if busy else ""])
		cmd_opt.set_item_tooltip(cmd_opt.item_count - 1, String(Content.unit(String(e.def)).get("name", "Commander")))
	if cmd_opt.item_count > 0:
		cmd_opt.select(clampi(keep, 0, cmd_opt.item_count - 1))
	var armies := Companies.armies_of(w, fid)
	var comps := Companies.companies_of(w, fid)
	if armies.is_empty() and comps.is_empty():
		var l := UiKit.label("No companies yet. Train one at your Company HQ (Army Builder).", "dim")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
		list_box.add_child(l)
	for a in armies:
		var am := Card.army_model(w, a)
		var hb := U.row(list_box)
		var t := UiKit.label(String(am.title), "header")
		hb.add_child(t)
		var st := UiKit.label(String(am.status), "small")
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.custom_minimum_size = Vector2(200, 0)
		hb.add_child(st)
		var db := U.small_button(hb, "Disband", "Disband this army (its companies stay)", 90)
		db.name = "Disband_%d" % int(a.id)
		db.pressed.connect(disband.bind(int(a.id)))
		army_btns[int(a.id)] = db
	for c in comps:
		var cm := Card.model(w, c)
		var cd := Card.card(cm, true)
		list_box.add_child(cd.box)
		var cid := int(c.id)
		(cd.refill as Button).pressed.connect(set_refill.bind(cid, not bool(cm.refill)))
		var ids: Array = []
		for u in cm.units:
			ids.append(int(u.id))
		(cd.select as Button).pressed.connect(func(): if on_select.is_valid(): on_select.call(ids))
		var pick: CheckBox = cd.pick
		pick.button_pressed = picked.has(cid) and not pick.disabled
		pick.toggled.connect(set_pick.bind(cid))
		cards[cid] = cd


func set_pick(on: bool, cid: int) -> void:
	if on:
		picked[cid] = true
	else:
		picked.erase(cid)


func picked_ids() -> Array:
	var out := []
	for cid in picked:
		out.append(int(cid))
	out.sort()
	return out


func selected_commander() -> int:
	if cmd_opt.selected < 0 or cmd_opt.selected >= _commanders.size():
		return -1
	return int(_commanders[cmd_opt.selected])


func form_cmd(fid: int) -> Dictionary:
	return {"type": "form_army", "issuer": fid, "commander_id": selected_commander(), "company_ids": picked_ids()}


func form_reason(w: SimWorld, fid: int) -> String:
	if _commanders.is_empty():
		return "Train a Commander at the Company HQ to form an army."
	return w.preview_command(form_cmd(fid))


func form_army() -> void:
	if issue.is_valid():
		issue.call(form_cmd(_fid))
		picked.clear()
		_sig = "?"


func disband(aid: int) -> void:
	if issue.is_valid():
		issue.call({"type": "disband_army", "issuer": _fid, "army_id": aid})


func set_refill(cid: int, on: bool) -> void:
	if issue.is_valid():
		issue.call({"type": "set_company_refill", "issuer": _fid, "company_id": cid, "on": on})
