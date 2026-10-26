extends RefCounted
## G6.1 command layer (owner: PLAN61). Hub owned by the HUD as `cmd_layer`:
##   build(hud, root)  once, after the other panels;  update(w, fid) each HUD refresh;
##   on_key(k) -> bool (true = handled: the Command mode hotkey, Esc while drawing).
## Command mode: the map dims and shows formations as NATO symbols (cl_overlay.gd). Click a symbol to
## start a plan, draw objectives / an axis / phase lines, pick intent and timing on the plan card, Issue.
## Right-click a symbol for quick officer orders (attack here, hold here, withdraw to, screen a line).
## Plans stay drawn; the card lists them with Go / Withdraw / Cancel. Everything goes out as
## issue_plan / plan_signal / cancel_plan (sim/systems/plans.gd).

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const ClModel = preload("res://presentation/ui6/command_layer/cl_model.gd")
const ClOverlay = preload("res://presentation/ui6/command_layer/cl_overlay.gd")
const Plans = preload("res://sim/systems/plans.gd")

const TOOLS := ["objective", "axis", "phase"]
const QUICK := [["Attack here", "attack"], ["Hold here", "hold"], ["Withdraw to", "withdraw"], ["Screen this line", "screen"]]

var hud = null
var root: Control = null
var active := false
var model = ClModel.new()
var overlay: Control = null
var card: PanelContainer = null
var toggle_btn: Button = null
var tool := "select"            # select | objective | axis | phase | screen (quick screen drag) | quick
var quick := {}                 # {kind, f} armed quick officer order
var hint := ""
var reason := ""                # draft validation ("" = ready)
var issue: Callable = Callable()  # tests / playtest may replace the HUD issue path

var _title: Label
var _intent: OptionButton
var _timing: OptionButton
var _main: CheckBox
var _tool_btns := {}
var _issue_btn: Button
var _reason_lbl: Label
var _list: VBoxContainer
var _list_sig := ""
var _menu: PopupMenu
var _menu_f := {}


func mv():
	return hud.mv if hud != null else null


func build(h, r: Control) -> void:
	hud = h
	root = r
	overlay = ClOverlay.new()
	overlay.hub = self
	overlay.name = "CommandOverlay"
	overlay.visible = false
	root.add_child(overlay)
	root.move_child(overlay, 0)  # under the HUD panels: they stay clickable in Command mode
	toggle_btn = UiKit.button("COMMAND", "Tab", "Command mode: give orders to officers and draw plans on the map")
	toggle_btn.name = "CommandModeButton"
	toggle_btn.toggle_mode = true
	toggle_btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toggle_btn.position = Vector2(-60, 46)
	toggle_btn.custom_minimum_size = Vector2(120, UiKit.BTN_H)
	toggle_btn.toggled.connect(func(on: bool) -> void: set_active(on))
	root.add_child(toggle_btn)
	_build_card()
	_menu = PopupMenu.new()
	_menu.name = "CommandQuickMenu"
	for i in QUICK.size():
		_menu.add_item(QUICK[i][0], i)
	_menu.id_pressed.connect(_on_quick)
	root.add_child(_menu)


func _build_card() -> void:
	card = UiKit.panel("frame")
	card.name = "CommandCard"
	card.visible = false
	card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	card.custom_minimum_size = Vector2(300, 0)
	card.position = Vector2(-312, 84)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiKit.GAP)
	card.add_child(v)
	_title = UiKit.label("COMMAND MODE", "header")
	v.add_child(_title)
	var row := HBoxContainer.new()
	_intent = OptionButton.new()
	for it in ClModel.INTENT_LABELS:
		_intent.add_item(it.capitalize())
	_intent.item_selected.connect(func(i: int) -> void: _set_draft("intent", ClModel.INTENT_LABELS[i]))
	_timing = OptionButton.new()
	for it in ClModel.TIMING_LABELS:
		_timing.add_item(it)
	_timing.item_selected.connect(func(i: int) -> void: _set_draft("timing", i))
	row.add_child(_intent)
	row.add_child(_timing)
	v.add_child(row)
	_main = CheckBox.new()
	_main.text = "Main effort"
	_main.toggled.connect(func(on: bool) -> void: _set_draft("main_effort", on))
	v.add_child(_main)
	var tools := HBoxContainer.new()
	for t in TOOLS:
		var b := UiKit.button({"objective": "Objective", "axis": "Axis", "phase": "Phase line"}[t])
		b.name = "Tool_" + t
		b.toggle_mode = true
		b.pressed.connect(set_tool.bind(t))
		_tool_btns[t] = b
		tools.add_child(b)
	var clr := UiKit.button("Clear")
	clr.name = "ToolClear"
	clr.pressed.connect(func() -> void: model.clear_draft_marks(); _redraw())
	tools.add_child(clr)
	v.add_child(tools)
	_issue_btn = UiKit.button("ISSUE PLAN", "Enter", "Send the plan down the chain of command")
	_issue_btn.name = "IssuePlanButton"
	_issue_btn.pressed.connect(issue_draft)
	v.add_child(_issue_btn)
	_reason_lbl = UiKit.label("Click a formation symbol to plan for it.", "small")
	_reason_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason_lbl.custom_minimum_size = Vector2(280, 0)
	v.add_child(_reason_lbl)
	v.add_child(UiKit.label("PLANS", "header"))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	v.add_child(UiKit.scroll(_list, 260.0))
	root.add_child(card)
	UiKit.fit_register(card)


# ---------------------------------------------------------------- mode
func set_active(on: bool) -> void:
	active = on
	if toggle_btn != null:
		toggle_btn.set_pressed_no_signal(on)
	if overlay != null:
		overlay.visible = on
		card.visible = on
	if not on:
		model.draft = {}
		quick = {}
		tool = "select"
		hint = ""
	else:
		hint = "Click a formation symbol (or right-click it for quick orders)."
		var m = mv()
		if m != null and m.has_method("cancel_point_pick"):
			m.cancel_point_pick()
	_redraw()


func toggle() -> void:
	set_active(not active)


func on_key(k: InputEventKey) -> bool:
	if not k.pressed or k.echo:
		return false
	# G6.1 ORCH (SQUAD61 CR seq 153): Tab is the GLOBAL next-build-page key; command mode is F3 (Hotkeys "command_mode")
	var hot := k.is_action_pressed("command_mode") if InputMap.has_action("command_mode") else k.keycode == KEY_F3
	if hot:
		toggle()
		return true
	if not active:
		return false
	if k.keycode == KEY_ESCAPE:
		if not quick.is_empty():
			quick = {}
		elif model.has_draft():
			model.draft = {}
			tool = "select"
		else:
			set_active(false)
			return true
		hint = "Click a formation symbol."
		_redraw()
		return true
	if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		issue_draft()
		return true
	return false


func set_tool(t: String) -> void:
	tool = t if model.has_draft() else "select"
	hint = {"objective": "Click the map to add objectives.", "axis": "Drag the axis of advance.",
		"phase": "Drag a phase line across the axis."}.get(tool, "Click a formation symbol.")
	_redraw()


func _set_draft(key: String, v) -> void:
	if model.has_draft():
		model.draft[key] = v
	_redraw()


func _redraw() -> void:
	for t in _tool_btns:
		(_tool_btns[t] as Button).set_pressed_no_signal(t == tool)
	if overlay != null:
		overlay.queue_redraw()


# ---------------------------------------------------------------- map input (from cl_overlay)
func on_press(cell: Vector2i, wpos: Vector2) -> void:
	if not quick.is_empty():
		if String(quick.kind) != "screen":
			_send({"type": "issue_plan", "plan": ClModel.quick_plan(quick.f, String(quick.kind), cell)})
			quick = {}
			hint = "Order sent."
		return
	var fm: Dictionary = model.formation_at(wpos)
	if tool == "select" or (not fm.is_empty() and not model.has_draft()):
		if fm.is_empty():
			return
		model.begin_draft(fm.f)
		_intent.select(0)
		_timing.select(0)
		_main.set_pressed_no_signal(false)
		set_tool("axis")
		return
	match tool:
		"objective":
			model.add_objective(cell)
		"axis":
			model.draft.axis = [cell]
	_redraw()


func on_release(a: Vector2i, b: Vector2i) -> void:
	if not quick.is_empty() and String(quick.kind) == "screen":
		if Vector2(a).distance_to(Vector2(b)) >= 2.0:
			_send({"type": "issue_plan", "plan": ClModel.quick_plan(quick.f, "screen", a, b)})
			hint = "Screen order sent."
		quick = {}
	elif tool == "phase" and model.has_draft() and Vector2(a).distance_to(Vector2(b)) >= 2.0:
		model.add_phase_line(a, b)
	elif tool == "axis" and model.has_draft():
		model.add_axis_point(b)
	_redraw()


func on_right(_cell: Vector2i, wpos: Vector2, local: Vector2) -> void:
	var fm: Dictionary = model.formation_at(wpos)
	if not fm.is_empty():
		_menu_f = fm.f
		_menu.position = Vector2i(overlay.get_global_transform_with_canvas() * local)
		_menu.popup()
		return
	quick = {}
	if model.has_draft():
		model.draft = {}
		tool = "select"
		hint = "Plan discarded. Click a formation symbol."
	_redraw()


func _on_quick(i: int) -> void:
	if _menu_f.is_empty():
		return
	quick = {"kind": String(QUICK[i][1]), "f": _menu_f}
	hint = "Drag the line to screen." if quick.kind == "screen" else "Click the map: %s." % String(QUICK[i][0]).to_lower()
	_redraw()


## Arms a quick officer order for formation f (playtest / tests use this instead of the popup).
func arm_quick(f: Dictionary, kind: String) -> void:
	quick = {"kind": kind, "f": f}


# ---------------------------------------------------------------- orders
func _send(cmd: Dictionary) -> void:
	if issue.is_valid():
		issue.call(cmd)
	elif hud != null and hud.has_method("_issue"):
		hud._issue(cmd)


func issue_draft() -> void:
	if not model.has_draft():
		hint = "Click a formation symbol first."
		return
	if reason != "":
		hint = reason
		return
	_send({"type": "issue_plan", "plan": model.draft_plan()})
	hint = "Plan issued to %s." % ClModel.fname(model.draft.formation)
	model.draft = {}
	tool = "select"
	_redraw()


func signal_plan(pid: int, sig: String) -> void:
	_send({"type": "plan_signal", "plan_id": pid, "signal": sig})


func cancel_plan(pid: int) -> void:
	_send({"type": "cancel_plan", "plan_id": pid})


# ---------------------------------------------------------------- refresh
func update(w: SimWorld, fid: int) -> void:
	if not active or w == null:
		return
	model.refresh(w, fid)
	reason = Plans.validate_plan(w, fid, model.draft_plan()) if model.has_draft() else ""
	_refresh_card()
	_redraw()


func _refresh_card() -> void:
	var d: Dictionary = model.draft
	_title.text = "PLAN: " + ClModel.fname(d.formation) if not d.is_empty() else "COMMAND MODE"
	_issue_btn.disabled = d.is_empty() or reason != ""
	if d.is_empty():
		_reason_lbl.text = hint if hint != "" else "Click a formation symbol to plan for it."
	else:
		_reason_lbl.text = reason if reason != "" else "%d objective(s), %d axis point(s), %d phase line(s). Ready." % [
			(d.objectives as Array).size(), (d.axis as Array).size(), (d.phase_lines as Array).size()]
	var sig := ""
	for p in model.plans:
		if bool(p.active):
			sig += "%d:%s|" % [int(p.id), String(p.line)]
	if sig == _list_sig:
		return
	_list_sig = sig
	for c in _list.get_children():
		c.queue_free()
	for p in model.plans:
		if not bool(p.active):
			continue
		var pid := int(p.id)
		var l := UiKit.label(String(p.line), "small")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(270, 0)
		l.add_theme_color_override("font_color", ClModel.col(pid))
		_list.add_child(l)
		var row := HBoxContainer.new()
		for b in [["Go", "go"], ["Withdraw", "withdraw"], ["Cancel", ""]]:
			var btn := UiKit.button(String(b[0]))
			btn.name = "Plan%d_%s" % [pid, String(b[0])]
			if String(b[1]) == "":
				btn.pressed.connect(cancel_plan.bind(pid))
			else:
				btn.pressed.connect(signal_plan.bind(pid, String(b[1])))
			row.add_child(btn)
		_list.add_child(row)
