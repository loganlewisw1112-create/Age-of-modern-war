extends RefCounted
## G3b stage panel + research status (owner: UI4). Contract: docs/CONTRACTS_G3b.md sections 3.2, 7.
## Left-side panel under the alerts feed: current stage, the gate checklist from
## Progression.gate_report (have/need with ticks), an Advance button (enabled only when every
## gate is ok and the sim's dry run agrees), the 60 s transition countdown, and the active
## research project with a progress bar. A centred toast fires on StageAdvanced.
## Reads the world; the only mutation path is hud._issue(cmd).

const HT = preload("res://presentation/hud/hud_theme.gd")
const G3bData = preload("res://presentation/hud/g3b_data.gd")
const Progression = preload("res://sim/systems/progression.gd")
const TOAST_LIFE := 4.5

var hud: Node = null
var panel: PanelContainer
var title: Label
var body: VBoxContainer
var next_lbl: Label
var gate_box: VBoxContainer
var cost_lbl: Label
var advance_btn: Button
var adv_bar: ProgressBar
var research_lbl: Label
var research_bar: ProgressBar
var collapse_btn: Button
var toast: Label
var _toast_born := -1.0
var _collapsed := false
var _gate_sig := "?"
var last_report: Array = []   # last gate_report rows shown (playtest reads this)
var _last_gate_ms: int = -1000
var _last_gate_stage: int = -1


func build(root: Control, hud_node: Node) -> void:
	hud = hud_node
	panel = PanelContainer.new()
	panel.name = "StagePanel"
	panel.position = Vector2(14, 196)
	panel.custom_minimum_size = Vector2(300, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN   # G5 (UI5a): keep 300 px inside the left stack
	panel.modulate = Color(1, 1, 1, 0.94)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	title = HT.make_label("STAGE", HT.AMBER, 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(title)
	collapse_btn = Button.new()
	collapse_btn.text = "-"
	collapse_btn.tooltip_text = "Collapse / expand the stage panel"
	collapse_btn.custom_minimum_size = Vector2(26, 22)
	collapse_btn.pressed.connect(_toggle)
	h.add_child(collapse_btn)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 1)
	v.add_child(body)
	next_lbl = HT.make_label("", HT.TEXT, 13)
	next_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(next_lbl)
	gate_box = VBoxContainer.new()
	gate_box.name = "GateList"
	gate_box.add_theme_constant_override("separation", 0)
	body.add_child(gate_box)
	cost_lbl = HT.make_label("", HT.DIM, 12)
	cost_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(cost_lbl)
	advance_btn = Button.new()
	advance_btn.name = "AdvanceStageButton"
	advance_btn.text = "Advance"
	advance_btn.custom_minimum_size = Vector2(0, 30)
	advance_btn.pressed.connect(_on_advance)
	body.add_child(advance_btn)
	adv_bar = ProgressBar.new()
	adv_bar.custom_minimum_size = Vector2(0, 10)
	adv_bar.max_value = 1.0
	adv_bar.show_percentage = false
	adv_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	adv_bar.visible = false
	body.add_child(adv_bar)
	research_lbl = HT.make_label("", HT.BLUE, 13)
	research_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(research_lbl)
	research_bar = ProgressBar.new()
	research_bar.name = "ResearchProgress"
	research_bar.custom_minimum_size = Vector2(0, 8)
	research_bar.max_value = 1.0
	research_bar.show_percentage = false
	research_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(research_bar)
	# toast (centre, under the PAUSED banner position)
	toast = HT.make_label("", HT.AMBER, 30)
	toast.name = "StageToast"
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast.offset_left = -400.0
	toast.offset_right = 400.0
	toast.offset_top = 130.0
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_constant_override("outline_size", 6)
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.visible = false
	root.add_child(toast)


func _toggle() -> void:
	_collapsed = not _collapsed
	body.visible = not _collapsed
	collapse_btn.text = "+" if _collapsed else "-"


## Next stage this side can advance to (0 = none in this slice).
static func next_stage(w: SimWorld, f: Dictionary) -> int:
	var nxt := int(f.get("stage", 8)) + 1
	var gates: Dictionary = Content.rules().get("advancement", {}).get("gates", {})
	return nxt if gates.has(str(nxt)) else 0


static func advance_cost(w: SimWorld, stage_to: int) -> Dictionary:
	var adv: Dictionary = Content.rules().get("advancement", {})
	var base: Dictionary = adv.get("gates", {}).get(str(stage_to), {}).get("cost", {})
	var mode := String(w.cfg.get("advancement", "standard"))
	var mult := float(adv.get("rules", {}).get(mode, {}).get("cost_mult", 1.0))
	var out := {}
	for k in base:
		out[k] = int(round(float(base[k]) * mult))
	return out


## Seconds left in the transition (0 when not advancing).
static func transition_left(f: Dictionary) -> float:
	var a: Dictionary = f.get("advancing", {})
	return float(int(a.get("ticks_left", 0))) / float(SimWorld.TICK_RATE) if int(a.get("ticks_left", 0)) > 0 else 0.0


static func research_text(f: Dictionary, faction_id: String) -> String:
	var r: Dictionary = f.get("research", {})
	var active := String(r.get("active", ""))
	var done: Array = r.get("done", [])
	if active != "":
		var t := "Research: %s  %d%%" % [G3bData.project_name(active, faction_id), int(round(_frac(r) * 100.0))]
		if int(r.get("facility", -1)) < 0:
			t += "  (paused: no research building)"
		return t
	return "Research: idle (%d done). Select a %s to start a project." % [done.size(), "research building"]


## Research progress as 0..1 whether the sim stores seconds or a fraction.
static func _frac(r: Dictionary) -> float:
	var p := float(r.get("progress", 0.0))
	if p <= 1.0:
		return clampf(p, 0.0, 1.0)
	var t := float(G3bData.research_projects().get(String(r.get("active", "")), {}).get("time", 0))
	return clampf(p / t, 0.0, 1.0) if t > 0.0 else 0.0


static func gate_text(g: Dictionary) -> String:
	var have = g.get("have", "")
	var need = g.get("need", "")
	var hv := str(snappedf(float(have), 0.01)) if (have is float) else str(have)
	var nd := str(snappedf(float(need), 0.01)) if (need is float) else str(need)
	return "%s %s  %s / %s" % ["[x]" if bool(g.get("ok", false)) else "[ ]", String(g.get("label", g.get("key", "?"))), hv, nd]


func update(w: SimWorld, pf: int) -> void:
	if w == null or not w.factions.has(pf):
		return
	var f: Dictionary = w.factions[pf]
	var fid := String(f.get("faction_def", ""))
	var stage := int(f.get("stage", 8))
	title.text = "STAGE %d  %s" % [stage, G3bData.stage_name(stage).to_upper()]
	var nxt := next_stage(w, f)
	var left := transition_left(f)
	var report: Array = []
	if nxt > 0:
		# Perf (UI4-2): gate_report scans the world; on big worlds refresh it at most 4 Hz.
		var now_ms := Time.get_ticks_msec()
		if w.entities.size() > 400 and not last_report.is_empty() and now_ms - _last_gate_ms < 250 and nxt == _last_gate_stage:
			report = last_report
		else:
			report = Progression.gate_report(w, pf)
			_last_gate_ms = now_ms
			_last_gate_stage = nxt
	last_report = report
	var all_ok := not report.is_empty()
	var rows: Array = []
	for g in report:
		rows.append(gate_text(g))
		if not bool(g.get("ok", false)):
			all_ok = false
	if nxt == 0:
		next_lbl.text = "Highest stage in this slice."
	elif left > 0.0:
		next_lbl.text = "Advancing to Stage %d %s: %s" % [int(f.advancing.get("to", nxt)), G3bData.stage_name(int(f.advancing.get("to", nxt))), HT.clock_text(int(ceil(left)) * SimWorld.TICK_RATE)]
	else:
		next_lbl.text = "Next: Stage %d %s" % [nxt, G3bData.stage_name(nxt)]
	var sig := "\n".join(rows)
	if sig != _gate_sig:
		_gate_sig = sig
		for c in gate_box.get_children():
			gate_box.remove_child(c)
			c.queue_free()
		if nxt > 0 and report.is_empty():
			gate_box.add_child(HT.make_label("No gates reported yet.", HT.DIM, 12))
		for i in report.size():
			var l := HT.make_label(rows[i], HT.GREEN if bool(report[i].get("ok", false)) else HT.TEXT, 12)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			gate_box.add_child(l)
	var cost := advance_cost(w, nxt) if nxt > 0 else {}
	cost_lbl.text = ("Cost: %s (%s rules)" % [HT.cost_text_long(cost) if not cost.is_empty() else "free", String(w.cfg.get("advancement", "standard"))]) if nxt > 0 else ""
	var reason := ""
	if nxt == 0:
		reason = "No further stage in this slice."
	elif left > 0.0:
		reason = "Transition in progress."
	elif report.is_empty():
		reason = "No gates reported yet."
	elif not all_ok:
		reason = "Every gate must be met first."
	else:
		reason = w.preview_command({"type": "advance_stage", "issuer": pf})
	advance_btn.visible = nxt > 0
	advance_btn.disabled = reason != ""
	advance_btn.text = ("Advancing... %ds" % int(ceil(left))) if left > 0.0 else "Advance to Stage %d" % nxt
	advance_btn.tooltip_text = reason if reason != "" else "Start the 60 s transition to Stage %d." % nxt
	var tsec := float(Content.rules().get("advancement", {}).get("transition_seconds", 60))
	adv_bar.visible = left > 0.0
	adv_bar.value = 1.0 - left / maxf(1.0, tsec)
	research_lbl.text = research_text(f, fid)
	var r: Dictionary = f.get("research", {})
	research_bar.visible = String(r.get("active", "")) != ""
	research_bar.value = _frac(r)
	_update_toast()


func _on_advance() -> void:
	if hud != null and hud.has_method("_issue"):
		hud._issue({"type": "advance_stage"})


func show_toast(text: String, color: Color = HT.AMBER) -> void:
	toast.text = text
	toast.add_theme_color_override("font_color", color)
	toast.visible = true
	toast.modulate = Color.WHITE
	_toast_born = Time.get_ticks_msec() / 1000.0


func _update_toast() -> void:
	if _toast_born < 0.0:
		return
	var age := Time.get_ticks_msec() / 1000.0 - _toast_born
	if age > TOAST_LIFE:
		toast.visible = false
		_toast_born = -1.0
	else:
		toast.modulate = Color(1, 1, 1, clampf((TOAST_LIFE - age) / 1.0, 0.0, 1.0))


## hud._on_events forwards StageAdvanced / research events here. Returns true if handled.
func on_event(w: SimWorld, pf: int, ev: Dictionary) -> bool:
	var t := String(ev.get("type", ""))
	if t == "StageAdvanced":
		var fid := int(ev.get("fid", ev.get("faction", -1)))
		var st := int(ev.get("stage", 0))
		if fid == pf:
			show_toast("STAGE %d REACHED: %s" % [st, G3bData.stage_name(st).to_upper()])
			hud.notify("Stage %d reached: new units and buildings unlocked." % st, HT.GREEN)
		elif w.factions.has(fid):
			hud.notify("%s reached Stage %d." % [String(w.factions[fid].name), st], HT.AMBER)
		return true
	if t == "ResearchCompleted" and int(ev.get("fid", ev.get("faction", -1))) == pf:
		var f: Dictionary = w.factions[pf]
		hud.notify("Research complete: %s" % G3bData.project_name(String(ev.get("project", "")), String(f.get("faction_def", ""))), HT.GREEN)
		return true
	return false
