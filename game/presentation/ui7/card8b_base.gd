extends PanelContainer
## G7 CARDS8B (13.9c-48): shared base of the Armory + Suit Foundry card and the Garages / workshop / decon wash card.
## Same rules as the drone bay card: shown only while the player has the building (part) selected, reads the world
## only on frames with no sim step in flight (mv.sim_busy) and at most every REFRESH_S, never writes the sim (commands
## go through MatchView.issue), every button pre-checked with the sim reason function Cards8b.reason (disabled + the
## reason as its tooltip). Hotkeys: presentation/ui5/panels/hotkeys.gd actions (page groups arm8b / gar8b) when
## registered, else the same defaults here; handled by the card itself, only while it is visible.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const S = preload("res://presentation/ui7/ops_style.gd")
const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")
const Cards8b = preload("res://sim/systems/cards8b.gd")
const CnFac = preload("res://sim/systems/cn_facility.gd")

const REFRESH_S := 0.3

var mv = null
var world_override: SimWorld = null    # tests / fit
var fid_override := -1
var force_show := false                 # tests / fit screens: show regardless of the selection
var fac := -1
var _acc := 99.0
var _dirty := true
var _v: VBoxContainer
var _grid: GridContainer
var btns := {}                          # action -> Button
var _cbs := {}                          # action -> Callable
var _cmds := {}                         # action -> Callable returning the command the button would issue ({} = none)
var last: Dictionary = {}               # last summary shown (tests / playtest log)
var issued: Array = []                  # commands issued by this card (tests / playtest log)


## action -> [default key, label]; subclasses override.
func defaults() -> Dictionary:
	return {}


func _title() -> String:
	return ""


func _setup(h, left_stack: Control) -> void:
	mv = h.get("mv") if h != null else null
	if left_stack != null:
		left_stack.add_child(self)
	if mv != null and (mv as Object).has_signal("world_events"):
		mv.world_events.connect(_on_world_events)
	if mv != null and (mv as Object).has_signal("selection_changed"):
		mv.selection_changed.connect(_on_selection_changed)


func _base_ready(nm: String) -> void:
	name = nm
	theme_type_variation = "PlatePanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	UiKit.fit_register(self)
	custom_minimum_size = Vector2(270, 0)
	_v = VBoxContainer.new()
	_v.add_theme_constant_override("separation", 2)
	add_child(_v)
	var t := UiKit.label(_title(), "header")
	t.add_theme_color_override("font_color", S.CYAN)
	_v.add_child(t)


func _line(nm: String) -> Label:
	var l := UiKit.label("", "body")
	l.name = nm
	l.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_v.add_child(l)
	return l


func _new_grid() -> GridContainer:
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 3)
	_v.add_child(_grid)
	return _grid


func key_of(action: String) -> String:
	var k := Hotkeys.key(action)
	if k == "":
		k = String(defaults().get(action, ["", ""])[0])
	return k


func _mk(action: String, nm: String, text: String, tip: String, cb: Callable, cmd_fn: Callable = Callable()) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.custom_minimum_size = Vector2(0, 24)
	b.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.set_meta("tip", tip)
	b.pressed.connect(cb)
	_grid.add_child(b)
	btns[action] = b
	_cbs[action] = cb
	if cmd_fn.is_valid():
		_cmds[action] = cmd_fn
	return b


## Sets a button's text, enabled state and tooltip (the sim reason when refused, the hotkey otherwise).
func _set_btn(action: String, text: String, why: String) -> void:
	var b: Button = btns[action]
	b.text = text
	b.disabled = why != ""
	var tip := String(b.get_meta("tip", ""))
	b.tooltip_text = UiKit.tooltip(text, Hotkeys.badge(key_of(action)), {}, tip if why == "" else tip + "\nUnavailable: " + why)


## Refusal of the command a button would issue now ("" = allowed); "No command." when it has none.
func why(action: String) -> String:
	var w := world()
	if w == null or not _cmds.has(action):
		return "No command."
	var c: Dictionary = (_cmds[action] as Callable).call()
	if c.is_empty():
		return "Nothing to do."
	c.issuer = pf()
	c.building_id = fac
	return Cards8b.reason(w, c)


func world() -> SimWorld:
	if world_override != null:
		return world_override
	return mv.get("_world") as SimWorld if mv != null else null


func pf() -> int:
	if fid_override >= 0:
		return fid_override
	return int(mv.get("player_fid")) if mv != null and mv.get("player_fid") != null else 0


func _on_selection_changed() -> void:
	if _sim_busy():
		_dirty = true
		_acc = 99.0
		return
	refresh()


func _sim_busy() -> bool:
	return world_override == null and mv != null and (mv as Object).has_method("sim_busy") and bool(mv.sim_busy())


func _on_world_events(_evs = null) -> void:
	_dirty = true


func _process(delta: float) -> void:
	_acc += delta
	if _acc < REFRESH_S or (not _dirty and _acc < REFRESH_S * 4.0):
		return
	if _sim_busy():
		return
	_acc = 0.0
	_dirty = false
	refresh()


func refresh() -> void:
	var w := world()
	if w == null:
		visible = false
		return
	fac = -1
	for f in CnFac.facilities(w, pf()):
		if force_show or _shown(w, int(f)):
			fac = int(f)
			break
	if fac < 0:
		visible = false
		return
	visible = true
	_fill(w)


func _shown(_w: SimWorld, _f: int) -> bool:
	return false


func _fill(_w: SimWorld) -> void:
	pass


func _issue(cmd: Dictionary) -> void:
	if fac >= 0:
		cmd.building_id = fac
	issued.append(cmd.duplicate())
	if mv != null and mv.has_method("issue"):
		mv.issue(cmd)
	_dirty = true
	_acc = REFRESH_S


func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if handle_key(ev as InputEventKey):
		get_viewport().set_input_as_handled()


## Runs the card action bound to key event k (true when one ran).
func handle_key(k: InputEventKey) -> bool:
	var reg := {}
	for a in _cbs:
		reg[key_of(a)] = a
	var kk := Hotkeys.event_key(k, reg)
	if not reg.has(kk) or not kk.begins_with("SHIFT+"):
		return false
	var b: Button = btns[reg[kk]]
	if b.disabled:
		return true
	(_cbs[reg[kk]] as Callable).call()
	return true


static func pct(a: float, b: float) -> String:
	return "%d%%" % int(round(100.0 * a / maxf(b, 0.001)))


# ---------------------------------------------------------------- G7 CARDBAR8 (13.9c-51): bottom-bar tabs
## Tab of each card action in the bottom command card (presentation/ui7/cardbar8.gd). Actions not listed go on a tab
## named after the card title.
const BAR_TAB := {"arm8b_role": "LOADOUTS", "arm8b_preset": "LOADOUTS",
	"arm8b_suit_role": "SUITS", "arm8b_build": "SUITS", "arm8b_rush": "SUITS", "arm8b_repair": "SUITS",
	"arm8b_up_pick": "UPGRADES", "arm8b_upgrade": "UPGRADES",
	"gar8b_team": "ROSTER", "gar8b_repair": "ROSTER", "gar8b_pick": "CONVOY", "gar8b_convoy": "CONVOY",
	"gar8b_recall": "CONVOY", "gar8b_up_pick": "UPGRADE", "gar8b_upgrade": "UPGRADE",
	"gar8b_decon": "DECON", "gar8b_skip": "DECON",
	"bar8c_post": "WATCH", "bar8c_rotate": "WATCH", "bar8c_role": "TRAIN", "bar8c_train": "TRAIN",
	"bar8c_standto": "REST", "bar8c_plan": "PATROL", "bar8c_adopt": "PATROL",
	"air8c_pick": "ROSTER", "air8c_service": "ROSTER", "air8c_launch": "LAUNCH", "air8c_launch_all": "LAUNCH",
	"air8c_recall": "LAUNCH", "air8c_cap": "PATROL", "air8c_cap_end": "PATROL",
	"aid8c_pick": "CASUALTIES", "aid8c_first": "CASUALTIES", "aid8c_evac": "CASUALTIES", "aid8c_medics": "MEDICS",
	"lab8c_pkg": "RESEARCH", "lab8c_queue": "RESEARCH", "lab8c_tier": "RESEARCH",
	"lab8c_team": "FIELD", "lab8c_path": "FIELD", "lab8c_spec": "FIELD"}


## [[TAB, [Button...]], ...] in button order (cardbar8.gd).
func bar_tabs() -> Array:
	var out: Array = []
	var at := {}
	for a in btns:
		var t := String(BAR_TAB.get(a, _title()))
		if not at.has(t):
			at[t] = out.size()
			out.append([t, []])
		(out[at[t]][1] as Array).append(btns[a])
	return out


func bar_title() -> String:
	return _title()
