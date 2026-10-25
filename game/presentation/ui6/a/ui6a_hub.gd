extends RefCounted
## UI6a (G6): the HUD's hub for the G6 panels: Marketplace, Army Builder, Forces (company / army
## cards) and AI Commanders. hud.gd builds it once (build), opens a panel from a card or top-bar
## button (open / toggle), refreshes the open one with the HUD (update) and closes it on Esc (on_key).
## One panel is open at a time; each is a modal frame sized to the canvas (ui6a_util.fit_modal).
## Commands go through the HUD's issue path (MatchView.issue -> runner/world submit).

const MarketPanel = preload("res://presentation/ui6/a/market_panel.gd")
const ArmyBuilder = preload("res://presentation/ui6/a/army_builder.gd")
const ForcesPanel = preload("res://presentation/ui6/a/forces_panel.gd")
const CommandersPanel = preload("res://presentation/ui6/a/commanders_panel.gd")

const NAMES := ["market", "army", "forces", "commanders"]

var hud = null                 # presentation/hud/hud.gd (or null in tests)
var root: Control = null
var panels: Dictionary = {}    # name -> panel object
var open_name := ""
var issue: Callable = Callable()
var _pick_slot := -1


func build(h, r: Control) -> void:
	hud = h
	root = r
	panels = {"market": MarketPanel.new(), "army": ArmyBuilder.new(), "forces": ForcesPanel.new(),
		"commanders": CommandersPanel.new()}
	for nm in NAMES:
		var p = panels[nm]
		p.build(root)
		p.issue = _issue
		p.on_close = close
		(p.panel as Control).visible = false
	panels.forces.on_select = _select
	panels.commanders.on_pick = _begin_pick
	panels.commanders.get_selection = _selection
	root.resized.connect(_fit_open)


func _mv():
	return hud.mv if hud != null else null


func _issue(cmd: Dictionary) -> void:
	if issue.is_valid():
		issue.call(cmd)
	elif hud != null and hud.has_method("_issue"):
		hud._issue(cmd)


func _select(ids: Array) -> void:
	var mv = _mv()
	if mv != null and mv.has_method("select_ids"):
		mv.select_ids(ids)


func _selection() -> Array:
	var mv = _mv()
	var out: Array = []
	if mv != null:
		var sel = mv.get("selection")
		if sel != null:
			for id in sel:
				out.append(int(id))
	return out


func is_open(nm: String = "") -> bool:
	return open_name != "" and (nm == "" or nm == open_name)


func open(nm: String) -> void:
	if not panels.has(nm):
		return
	close()
	open_name = nm
	(panels[nm].panel as Control).visible = true
	refresh()
	_fit_open()
	_fit_open.call_deferred()


func toggle(nm: String) -> void:
	if open_name == nm:
		close()
	else:
		open(nm)


func close() -> void:
	if open_name != "" and panels.has(open_name):
		(panels[open_name].panel as Control).visible = false
	open_name = ""


func _fit_open() -> void:
	if open_name == "" or root == null:
		return
	var cs: Vector2 = root.size
	if hud != null and hud.get("layer") != null and hud.layer.has_method("canvas_size"):
		cs = hud.layer.canvas_size()
	panels[open_name].fit(cs)


## Refresh the open panel from the world (the HUD calls this only while the sim is not stepping).
func refresh() -> void:
	if open_name == "" or hud == null:
		return
	var w: SimWorld = hud._world()
	if w == null:
		return
	panels[open_name].update(w, hud._pf())


func update(_w: SimWorld, _fid: int) -> void:
	if open_name == "":
		return
	refresh()
	_fit_open()


## AI Commanders: hide the panel, arm a map click on the MatchView, reopen with the picked cell.
func _begin_pick(slot: int) -> void:
	var mv = _mv()
	if mv == null or not mv.has_method("begin_point_pick"):
		return
	_pick_slot = slot
	close()
	mv.begin_point_pick(_on_picked)


func _on_picked(p: Vector2) -> void:
	if _pick_slot >= 0:
		panels.commanders.set_cell(_pick_slot, Vector2i(floori(p.x), floori(p.y)))
	_pick_slot = -1
	open("commanders")


## Esc closes the open panel. Returns true when the key was used.
func on_key(k: InputEventKey) -> bool:
	if k.keycode == KEY_ESCAPE and open_name != "":
		close()
		return true
	return false
