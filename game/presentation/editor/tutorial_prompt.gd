extends Node
## Tutorial step prompts (owner: ED5, PLAN_G5 section 9). Shown over any match whose map triggers
## carry `step` + `prompt` (content/scenarios/tutorial.rtsmap, or any editor scenario that uses them).
## The current step = the lowest-numbered step trigger that has not fired; when all have fired, the
## last message of the finish trigger is shown. Pure reader: polls the world 4x a second and never
## while a worker step is in flight (thread rule, CONTRACTS_G5 section 0.6). main.gd adds it.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const ScaledLayer = preload("res://presentation/hud/scaled_layer.gd")
const DONE_TEXT := "Tutorial complete. Well done, Commander."

var match_view: Node
var layer: CanvasLayer
var panel: PanelContainer
var title: Label
var body: Label
var _acc := 0.0
var _last := ""


## {step, total, text, done} for world w (step 0 / total 0 = the map has no tutorial steps).
static func current(w: SimWorld) -> Dictionary:
	var defs: Array = w.map.get("triggers", [])
	var st = w.sys_state.get("triggers")
	var best := -1
	var total := 0
	var text := ""
	var finish := ""
	for i in defs.size():
		var d = defs[i]
		if typeof(d) != TYPE_DICTIONARY:
			continue
		if not d.has("step"):
			for a in (d.get("then", []) if typeof(d.get("then", [])) == TYPE_ARRAY else []):
				if typeof(a) == TYPE_DICTIONARY and String(a.get("type", "")) == "win" and String(finish) == "":
					for b in d.then:
						if typeof(b) == TYPE_DICTIONARY and String(b.get("type", "")) == "message":
							finish = String(b.get("text", ""))
			continue
		total += 1
		var fired := st != null and i < (st.fired as Array).size() and int(st.fired[i]) == 1
		if not fired and (best < 0 or int(d.step) < best):
			best = int(d.step)
			text = String(d.get("prompt", ""))
	if total == 0:
		return {"step": 0, "total": 0, "text": "", "done": false}
	if best < 0:
		return {"step": total, "total": total, "text": finish if finish != "" else DONE_TEXT, "done": true}
	return {"step": best, "total": total, "text": text, "done": false}


static func has_steps(w: SimWorld) -> bool:
	for d in w.map.get("triggers", []):
		if typeof(d) == TYPE_DICTIONARY and d.has("step"):
			return true
	return false


func setup(mv: Node, ui_scale: float = 1.0) -> void:
	match_view = mv
	layer = ScaledLayer.new()
	layer.layer = 12   # above the HUD (10), below menus (20) and overlays (30)
	add_child(layer)
	layer.set_ui_scale(ui_scale)
	layer.root.theme = UiKit.make_theme()
	layer.root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = UiKit.panel("plate")
	panel.name = "TutorialPrompt"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 64
	panel.custom_minimum_size = Vector2(520, 0)
	layer.root.add_child(panel)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	title = UiKit.label("TUTORIAL", "header")
	v.add_child(title)
	body = UiKit.label("", "body")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(500, 0)
	v.add_child(body)
	refresh()


func refresh() -> void:
	if match_view == null or panel == null:
		return
	if match_view.has_method("sim_busy") and match_view.sim_busy():
		return
	var w := match_view.get("world") as SimWorld
	if w == null:
		return
	var c := current(w)
	var key := "%d/%s" % [int(c.step), String(c.text)]
	if key == _last:
		return
	_last = key
	panel.visible = int(c.total) > 0
	title.text = "TUTORIAL  COMPLETE" if bool(c.done) else "TUTORIAL  STEP %d OF %d" % [int(c.step), int(c.total)]
	body.text = String(c.text)


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.25:
		return
	_acc = 0.0
	refresh()
