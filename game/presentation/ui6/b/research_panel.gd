extends RefCounted
## G6 (UI6b) research additions + Stage 10 panel (CONTRACTS_G6 sections 3.3, 14; PLAN_G6 D35-D36).
## Shown above the card while an own built research building is selected (G4bCommands.add_building_buttons):
##   - the G6 projects this faction can see (Progression.research_list hides other factions' projects):
##     done / in progress (percent) / ready / locked with the sim's reason (stage, chain "requires_research");
##   - the Stage 10 block: gate research (for_stage 10) and its state, the stage gate checklist
##     (Progression.gate_report), the advance cost and the sim's advance reason, and the Stage 10 unlock list
##     (factions.json stage_roles "10").
## The card's research buttons for other factions' projects are removed (filter_card) so a Machine player never
## sees Human-only projects. Reads the world from the HUD refresh only (no step in flight).

const Progression = preload("res://sim/systems/progression.gd")
const PData = preload("res://sim/systems/progression_data.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const G6Place = preload("res://presentation/ui6/b/g6_place.gd")

const PANEL_W := 640.0
const MARK := {"done": "[x]", "active": "[>]", "ready": "[ ]", "locked": "[-]"}
const COL_SEP := 12.0

var hud
var panel: PanelContainer
var scroll: ScrollContainer    # body scroller, capped to the room above the card (G6Place; UI6b-3)
var title: Label
var grid: GridContainer
var stage_lines: Label
var rows: Dictionary = {}      # project id -> {state, reason, text} (last refresh; tests read it)
var stage10: Dictionary = {}   # {stage, gate_ids, gate_done, unlocks: [names], reason, cost}
var _bid := -1


func build(root: Control) -> void:
	panel = UiKit.panel("plate")
	panel.name = "ResearchG6Panel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_W * 0.5
	panel.offset_right = PANEL_W * 0.5
	panel.offset_top = -330
	panel.offset_bottom = -226
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	UiKit.fit_register(panel)
	root.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	scroll = UiKit.scroll(body)
	scroll.name = "ResearchG6Scroll"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(scroll)
	title = UiKit.label("G6 RESEARCH", "header")
	title.name = "ResearchG6Title"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(PANEL_W - 24.0, 0)
	body.add_child(title)
	grid = GridContainer.new()
	grid.name = "ResearchG6Grid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(COL_SEP))
	grid.add_theme_constant_override("v_separation", 0)
	body.add_child(grid)
	stage_lines = UiKit.label("", "small")
	stage_lines.name = "Stage10Lines"
	stage_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stage_lines.custom_minimum_size = Vector2(PANEL_W - 24.0, 0)
	body.add_child(stage_lines)


## Project label width (one of two grid columns) for an inner width.
static func col_w(inner: float) -> float:
	return floorf((inner - COL_SEP) * 0.5) - 2.0


## Content widths for an inner width (G6Place.place callback).
func _set_w(inner: float) -> void:
	title.custom_minimum_size.x = inner
	stage_lines.custom_minimum_size.x = inner
	for l in grid.get_children():
		(l as Control).custom_minimum_size.x = col_w(inner)


## Size and place the panel in the room above the card (between the HUD side columns, below PAUSED); the body
## takes the mouse (wheel scrolling) only while it scrolls.
func place() -> void:
	if panel == null or not panel.visible:
		return
	G6Place.place(hud, panel, scroll, PANEL_W, _set_w)
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED \
		else Control.MOUSE_FILTER_IGNORE


func reset() -> void:
	_bid = -1
	if panel != null:
		panel.visible = false


static func is_research_def(def_id: String) -> bool:
	return bool(Content.building(def_id).get("research", false))


## Called for a single own building card. Shows the panel for a built research building.
func add_building_buttons(b: Dictionary) -> void:
	if not is_research_def(String(b.def)) or not bool(b.get("built", false)):
		return
	_bid = int(b.id)
	filter_card()
	panel.visible = true
	_sig = ""


var _sig := ""


## Removes the card's research buttons for projects this faction cannot see.
func filter_card() -> void:
	var w: SimWorld = hud._world()
	var vis := {}
	for r in Progression.research_list(w, hud._pf()):
		vis[String(r.id)] = true
	for rec in (hud._card_buttons as Array).duplicate():
		if String(rec.get("kind", "")) != "research" or vis.has(String(rec.get("project", ""))):
			continue
		hud._card_buttons.erase(rec)
		var bt: Button = rec.btn
		if is_instance_valid(bt):
			if bt.get_parent() != null:
				bt.get_parent().remove_child(bt)
			bt.queue_free()


static func state_of(r: Dictionary) -> String:
	if bool(r.done):
		return "done"
	if bool(r.active):
		return "active"
	return "ready" if String(r.reason) == "" else "locked"


## Stage 10 unlock names and role highlights for a faction, sorted.
static func stage10_unlocks(faction_id: String) -> Array:
	var f: Dictionary = Content.table("factions").get(faction_id, {})
	var sr: Dictionary = (f.get("stage_roles", {}) as Dictionary).get("10", {})
	var out: Array = []
	var ids := PData.stage_unlock_ids(faction_id, 10)
	ids.append_array(f.get("stage_unlocks", {}).get("10", []))
	ids.append_array(sr.values())
	for id in ids:
		var d := String(id)
		if d == "":
			continue
		var nm := String(Content.unit(d).get("name", Content.production(d).get("name", Content.building(d).get("name", d))))
		if not out.has(nm):
			out.append(nm)
	out.sort()
	return out


func update_state(w: SimWorld) -> void:
	if _bid < 0 or panel == null or not panel.visible:
		return
	var pf: int = hud._pf()
	var f: Dictionary = w.factions[pf]
	var fdef := G3.faction_def(w, pf)
	rows.clear()
	var gate_ids: Array = []
	var gate_done := true
	var texts: Array = []
	for r in Progression.research_list(w, pf):
		var id := String(r.id)
		if int(r.for_stage) == 10:
			gate_ids.append(id)
			gate_done = gate_done and bool(r.done)
		if not id.begins_with("g6_"):
			continue
		var st := state_of(r)
		var t := "%s %s" % [MARK[st], String(r.name)]
		if st == "active":
			t += " %d%%" % int(round(float(r.progress) * 100.0)) if float(r.progress) <= 1.0 else " %d%%" % int(r.progress)
		elif st == "locked":
			t += " (%s)" % String(r.reason).replace("Requires research: ", "needs ").replace("Requires ", "needs ")
		rows[id] = {"state": st, "reason": String(r.reason), "text": t}
		texts.append(t)
	var stage := int(f.get("stage", 8))
	var sig := "%s|%d|%s" % [str(texts), stage, Progression.can_advance(w, pf)]
	if sig == _sig:
		place()
		return
	_sig = sig
	title.text = "G6 RESEARCH   %d projects  ([x] done  [>] active  [ ] ready  [-] locked)" % rows.size()
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for t2 in texts:
		var l := UiKit.label(String(t2), "small")
		l.custom_minimum_size = Vector2((PANEL_W - 40.0) * 0.5, 0)
		l.clip_text = true
		l.tooltip_text = String(t2)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(l)
	_stage10(w, pf, fdef, stage, gate_ids, gate_done)
	place()
	place.call_deferred()   # again once the new widths are laid out (wrapped label heights)


func _stage10(w: SimWorld, pf: int, fdef: String, stage: int, gate_ids: Array, gate_done: bool) -> void:
	var names: Array = []
	for g in gate_ids:
		names.append(PData.project_name(String(g), fdef))
	var unlocks := stage10_unlocks(fdef)
	var reason := "" if stage >= 10 else Progression.can_advance(w, pf)
	var cost: Dictionary = PData.advance_cost(w, 10)
	stage10 = {"stage": stage, "gate_ids": gate_ids, "gate_done": gate_done, "unlocks": unlocks, "reason": reason, "cost": cost}
	var ln: Array = []
	if stage >= 10:
		ln.append("STAGE 10 reached. Unlocked: %s." % ", ".join(unlocks))
	else:
		ln.append("STAGE 10 gate research: %s %s.   Advance cost: %s." % [", ".join(names),
			"(done)" if gate_done else "(not yet)", PData.cost_label(cost)])
		if stage == 9:
			var miss: Array = []
			for g in Progression.gate_report(w, pf):
				if not bool(g.get("ok", false)):
					miss.append(String(g.get("label", g.get("key", ""))))
			ln.append("Advance: %s" % ("ready" if reason == "" else reason) + ("" if miss.is_empty() else "   Missing: " + ", ".join(miss)))
		else:
			ln.append("Reach Stage 9 first.")
		ln.append("Stage 10 unlocks: %s." % ", ".join(unlocks))
	stage_lines.text = "\n".join(ln)
