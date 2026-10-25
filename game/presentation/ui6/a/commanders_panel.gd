extends RefCounted
## UI6a (G6): AI Commanders panel (CONTRACTS_G6 sections 3.6, 4, 16 / D41; AI7-CMD's AiCommand API).
## Up to 4 slots (C1-C4, badge colours from ui6a_util). Each slot: a formation (company, army, the
## current selection) or a role, a playstyle, a stance, an objective (take / hold / raid / escort; the
## cell is picked with a map click, escort guards the first selected unit), Assign and Recall. The live
## state of each slot comes from AiCommand.slots(w, fid); with no ai_cmd state it reads as unassigned.
## Issues set_ai_commander / recall_ai_commander only; reasons come from the sim's validation.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const U = preload("res://presentation/ui6/a/ui6a_util.gd")
const Companies = preload("res://sim/systems/companies.gd")
const AiCommand = preload("res://sim/systems/ai_command.gd")

const WANT_W := 760.0
const SLOTS := 4
const PLAYSTYLE_NAMES := {"defensive": "Defensive (fortifier)", "aggressive": "Aggressive (breakthrough)",
	"specops": "Special ops (raider)", "combined": "Combined arms"}

var m: Dictionary = {}
var panel: PanelContainer = null
var issue: Callable = Callable()
var on_close: Callable = Callable()
var on_pick: Callable = Callable()        # on_pick(slot): the hub arms a map click, then calls set_cell
var get_selection: Callable = Callable()  # -> Array of selected unit ids
var rows: Array = []                      # per slot: {status, badge, target, play, stance, obj, pick, assign, recall, note}
var pending: Array = []                   # per slot: {cell: Variant(Vector2i|null)}
var _targets: Array = []                  # [{label, value: {formation|role|units}}]
var _tsig := ""
var _fid := 0


func build(root: Control) -> PanelContainer:
	m = U.modal("CommandersPanel", "AI COMMANDERS", "Close the AI Commanders panel")
	panel = m.panel
	(m.close as Button).pressed.connect(func(): if on_close.is_valid(): on_close.call())
	var body: VBoxContainer = m.body
	var help := UiKit.label("An AI Commander runs a formation or a role for you. It never overrides an order you gave a unit in the last 20 s; Recall returns control at once.", "dim")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(300, 0)
	body.add_child(help)
	for sl in SLOTS:
		pending.append({"cell": null})
		var box := UiKit.panel("card")
		box.name = "Slot%d" % (sl + 1)
		body.add_child(box)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		box.add_child(v)
		var r := {}
		var h := U.row(v)
		r.badge = UiKit.label("C%d" % (sl + 1), "header")
		(r.badge as Label).add_theme_color_override("font_color", U.slot_color(sl))
		h.add_child(r.badge)
		r.status = UiKit.label("Unassigned", "small")
		(r.status as Label).name = "SlotStatus"
		(r.status as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(r.status as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		(r.status as Label).custom_minimum_size = Vector2(200, 0)
		h.add_child(r.status)
		var r1 := U.row(v, 6)
		r.target = U.option(r1, [], 230)
		(r.target as OptionButton).name = "Target"
		var plays: Array = []
		for p in AiCommand.PLAYSTYLES:
			plays.append(String(PLAYSTYLE_NAMES.get(p, U.pretty(p))))
		r.play = U.option(r1, plays, 200)
		(r.play as OptionButton).name = "Playstyle"
		var stances: Array = []
		for s in AiCommand.STANCES:
			stances.append(U.pretty(String(s)))
		r.stance = U.option(r1, stances, 130)
		(r.stance as OptionButton).name = "Stance"
		(r.stance as OptionButton).select(maxi(0, AiCommand.STANCES.find("balanced")))
		var r2 := U.row(v, 6)
		var objs: Array = []
		for o in AiCommand.OBJECTIVES:
			objs.append("Objective: " + U.pretty(String(o)))
		r.obj = U.option(r2, objs, 170)
		(r.obj as OptionButton).name = "Objective"
		(r.obj as OptionButton).select(maxi(0, AiCommand.OBJECTIVES.find("hold")))
		r.pick = U.small_button(r2, "Pick on map", "Click the map to set this slot's objective cell", 130)
		(r.pick as Button).pressed.connect(func(): if on_pick.is_valid(): on_pick.call(sl))
		r.assign = U.small_button(r2, "Assign", "Hand this formation or role to the AI Commander", 90)
		(r.assign as Button).name = "Assign"
		(r.assign as Button).pressed.connect(assign.bind(sl))
		r.recall = U.small_button(r2, "Recall", "Take back control at once", 90)
		(r.recall as Button).name = "Recall"
		(r.recall as Button).pressed.connect(recall.bind(sl))
		r.note = UiKit.label("", "warn")
		(r.note as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		(r.note as Label).custom_minimum_size = Vector2(200, 0)
		v.add_child(r.note)
		rows.append(r)
	root.add_child(panel)
	return panel


func fit(canvas: Vector2) -> void:
	U.fit_modal(m, canvas, WANT_W)


## Target choices for side fid: the selection, each company, each army, each role.
static func targets(w: SimWorld, fid: int) -> Array:
	var out: Array = [{"label": "Selected units", "value": {"units": []}}]
	for c in Companies.companies_of(w, fid):
		var nm := String(c.get("name", ""))
		if nm == "":
			nm = String(Companies.template(w, fid, String(c.get("template", ""))).get("name", "Company"))
		out.append({"label": "Company %d: %s" % [int(c.id), nm], "value": {"formation": "co:%d" % int(c.id)}})
	for a in Companies.armies_of(w, fid):
		out.append({"label": "Army %d (%d companies)" % [int(a.id), (a.companies as Array).size()], "value": {"formation": "army:%d" % int(a.id)}})
	for r in AiCommand.ROLES:
		out.append({"label": "Role: " + U.pretty(String(r)), "value": {"role": String(r)}})
	return out


func set_cell(sl: int, cell: Vector2i) -> void:
	if sl >= 0 and sl < pending.size():
		pending[sl].cell = cell


func select_option(sl: int, field: String, idx: int) -> void:
	var o: OptionButton = rows[sl][field]
	o.select(clampi(idx, 0, o.item_count - 1))


## The set_ai_commander command the slot's controls describe now.
func assign_cmd(sl: int, fid: int) -> Dictionary:
	var r: Dictionary = rows[sl]
	var ti := (r.target as OptionButton).selected
	var tv: Dictionary = (_targets[ti].value as Dictionary).duplicate(true) if ti >= 0 and ti < _targets.size() else {}
	var sel: Array = get_selection.call() if get_selection.is_valid() else []
	if tv.has("units"):
		tv.units = sel.duplicate()
	var ot := String(AiCommand.OBJECTIVES[clampi((r.obj as OptionButton).selected, 0, AiCommand.OBJECTIVES.size() - 1)])
	var ob := {"type": ot}
	var cell = pending[sl].cell
	if cell != null:
		ob.cell = [int(cell.x), int(cell.y)]
	if ot == "escort" and not sel.is_empty():
		ob.target_id = int(sel[0])
	return {"type": "set_ai_commander", "issuer": fid, "slot": sl, "target": tv,
		"playstyle": String(AiCommand.PLAYSTYLES[clampi((r.play as OptionButton).selected, 0, AiCommand.PLAYSTYLES.size() - 1)]),
		"stance": String(AiCommand.STANCES[clampi((r.stance as OptionButton).selected, 0, AiCommand.STANCES.size() - 1)]),
		"objective": ob}


func assign(sl: int) -> void:
	if issue.is_valid():
		issue.call(assign_cmd(sl, _fid))


func recall(sl: int) -> void:
	if issue.is_valid():
		issue.call({"type": "recall_ai_commander", "issuer": _fid, "slot": sl})


## "Formation: Company 3 | Aggressive | balanced | take (40, 52) | assault | 24 units" or "Unassigned".
static func slot_text(s: Dictionary) -> String:
	if s.is_empty():
		return "Unassigned"
	var what := "Role: " + U.pretty(String(s.role)) if String(s.kind) == "role" else "Formation: " + str(s.get("formation", "selected units"))
	var ob: Dictionary = s.get("objective", {})
	var ot := String(ob.get("type", "hold"))
	if ob.has("cell"):
		var c = ob.cell
		ot += " (%d, %d)" % [int(c.x), int(c.y)] if (c is Vector2 or c is Vector2i) else ""
	var parts: Array = [what, String(PLAYSTYLE_NAMES.get(String(s.playstyle), s.playstyle)), String(s.stance), ot]
	if String(s.get("phase", "")) != "":
		parts.append(String(s.phase))
	parts.append("%d units" % (s.get("units", []) as Array).size())
	return "  |  ".join(PackedStringArray(parts))


func update(w: SimWorld, fid: int) -> void:
	if panel == null or w == null:
		return
	_fid = fid
	var tl := targets(w, fid)
	var sig := JSON.stringify(tl)
	if sig != _tsig:
		_tsig = sig
		_targets = tl
		for r in rows:
			var o: OptionButton = r.target
			var keep := o.selected
			o.clear()
			for t in _targets:
				o.add_item(String(t.label))
			o.select(clampi(keep, 0, o.item_count - 1))
	var live := {}
	for s in AiCommand.slots(w, fid):
		live[int(s.slot)] = s
	for sl in rows.size():
		var r: Dictionary = rows[sl]
		var s: Dictionary = live.get(sl, {})
		(r.status as Label).text = slot_text(s)
		var cell = pending[sl].cell
		(r.pick as Button).text = "Cell %d, %d" % [cell.x, cell.y] if cell != null else "Pick on map"
		var why := w.preview_command(assign_cmd(sl, fid))
		(r.assign as Button).disabled = why != ""
		(r.assign as Button).tooltip_text = "Hand this formation or role to the AI Commander" + ("\nUnavailable: " + why if why != "" else "")
		(r.note as Label).text = why if not s.is_empty() or why.contains("map") or why.contains("escort") else ""
		(r.note as Label).visible = (r.note as Label).text != ""
		(r.recall as Button).disabled = s.is_empty()
