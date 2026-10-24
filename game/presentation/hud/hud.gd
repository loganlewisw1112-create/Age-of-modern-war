extends Node
## In-match HUD (owner: agent E). Top bar, minimap, selection inspector, command card,
## alerts feed, objectives checklist. Reads sim state from match_view.world; the only way it
## changes the game is match_view.issue(cmd) / begin_build_placement().

signal menu_requested

const HT = preload("res://presentation/hud/hud_theme.gd")
const ScaledLayer = preload("res://presentation/hud/scaled_layer.gd")
const MinimapScript = preload("res://presentation/hud/minimap.gd")
const ObjectivesScript = preload("res://presentation/hud/objectives.gd")
# G2 (agent D2): inspector bars/chips/tags + group card, command buttons, alerts
const G2Inspector = preload("res://presentation/hud/g2_inspector.gd")
const G2Commands = preload("res://presentation/hud/g2_commands.gd")
const G2Alerts = preload("res://presentation/hud/g2_alerts.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")
const G3Score = preload("res://presentation/hud/g3_score.gd")
# G3b (UI4): stage panel, research card, stage/research lock reasons
const G3bStage = preload("res://presentation/hud/g3b_stage.gd")
const G3bData = preload("res://presentation/hud/g3b_data.gd")

const REFRESH_SECS := 0.2
const ALERT_LIFE := 9.0
const ALERT_MAX := 6
const ATTACK_ALERT_TICKS := 20 * 10

var mv: Node = null
var layer: Node = null
var objectives := ObjectivesScript.new()
var g2_insp = G2Inspector.new()
var g2_cmd = G2Commands.new()
var g2_alerts = G2Alerts.new()
var g3_score = G3Score.new()
var g3b_stage = G3bStage.new()

# Top bar
var _credits: Label
var _salvage: Label
var _ore: Label
var _fuel: Label
var _ammo: Label
var _power: Label
var _pop: Label
var _stage: Label
var _clock: Label
var _btn_pause: Button
var _btn_speed: Array = []
var _paused_banner: Label
# Panels
var _hover_lbl: Label
var _minimap: Control
var _insp_icon: TextureRect
var _insp_name: Label
var _insp_hp: ProgressBar
var _insp_info: Label
var _insp_counts: GridContainer
var _card_title: Label
var _card_grid: GridContainer
var _queue_box: HBoxContainer
var _hint: Label
var _alert_box: VBoxContainer
var _obj_panel: PanelContainer
var _obj_title: Label
var _obj_labels: Array = []

var _alerts: Array = []   # {text, color, born}
var _alert_throttle: Dictionary = {}
var _acc: float = 0.0
var _card_sig: String = ""
var _queue_sig: String = ""
var _card_buttons: Array = []   # {btn, kind, ...}
var _queue_bars: Array = []
var _hotkeys: Dictionary = {}
var _hover_btn: Button = null
var _connected: bool = false
var _last_poll_tick: int = -1
var last_alert_pos: Vector2 = Vector2.ZERO
var has_alert_pos: bool = false
var suppress_banner: bool = false


func setup(match_view: Node, ui_scale: float = 1.0) -> void:
	mv = match_view
	layer = ScaledLayer.new()
	layer.layer = 10
	add_child(layer)
	layer.root.theme = HT.make_theme()
	layer.set_ui_scale(ui_scale)
	_build_ui()
	if mv.has_signal("world_events"):
		mv.world_events.connect(_on_events)
		_connected = true
	if mv.has_signal("selection_changed"):
		mv.selection_changed.connect(_on_selection_changed)
	_refresh()


## Public: show a message in the alerts feed (used by main.gd for save/load feedback).
func notify(text: String, color: Color) -> void:
	_push_alert(text, color)


func _on_selection_changed() -> void:
	_card_sig = "?"
	_refresh()


func set_ui_scale(s: float) -> void:
	if layer != null:
		layer.set_ui_scale(s)


func _world() -> SimWorld:
	return mv.get("world") as SimWorld if mv != null else null


func _pf() -> int:
	return int(mv.get("player_fid")) if mv != null else 0


# ------------------------------------------------------------------ construction
func _build_ui() -> void:
	var root: Control = layer.root
	# ---- top bar
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, 36)
	top.add_theme_stylebox_override("panel", HT.box(Color("101417"), HT.EDGE, 1, 0, 8))
	root.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	top.add_child(hb)
	_credits = _tb_label(hb, HT.AMBER)
	_salvage = _tb_label(hb, Color("c9ccc4"))
	_ore = _tb_label(hb, Color("e0944a"))
	_fuel = _tb_label(hb, Color("d9c05a"))
	_ammo = _tb_label(hb, Color("d08a4a"))
	_power = _tb_label(hb, HT.YELLOW)
	_pop = _tb_label(hb, HT.BLUE)
	_stage = _tb_label(hb, HT.DIM)
	_clock = _tb_label(hb, HT.TEXT)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sp)
	_btn_pause = Button.new()
	_btn_pause.text = "Pause (P)"
	_btn_pause.toggle_mode = true
	_btn_pause.pressed.connect(_on_pause_pressed)
	hb.add_child(_btn_pause)
	for s in [1.0, 2.0, 3.0]:
		var b := Button.new()
		b.text = "%dx" % int(s)
		b.toggle_mode = true
		b.pressed.connect(_set_speed.bind(s))
		hb.add_child(b)
		_btn_speed.append(b)
	var mb := Button.new()
	mb.text = "Menu (Esc)"
	mb.pressed.connect(func(): menu_requested.emit())
	hb.add_child(mb)

	_paused_banner = HT.make_label("PAUSED", HT.AMBER, 34)
	_paused_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_paused_banner.offset_left = -80.0
	_paused_banner.offset_right = 80.0
	_paused_banner.offset_top = 80.0
	_paused_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused_banner.visible = false
	root.add_child(_paused_banner)

	# ---- alerts feed (top-left under the bar)
	_alert_box = VBoxContainer.new()
	_alert_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_box.position = Vector2(14, 48)
	_alert_box.custom_minimum_size = Vector2(520, 0)
	_alert_box.add_theme_constant_override("separation", 2)
	root.add_child(_alert_box)
	for i in ALERT_MAX:
		var l := HT.make_label("", HT.TEXT, 15)
		l.add_theme_constant_override("outline_size", 4)
		_alert_box.add_child(l)

	# ---- objectives (top-right)
	_obj_panel = PanelContainer.new()
	_obj_panel.anchor_left = 1.0
	_obj_panel.anchor_right = 1.0
	_obj_panel.anchor_top = 0.0
	_obj_panel.anchor_bottom = 0.0
	_obj_panel.offset_left = -320
	_obj_panel.offset_right = -14
	_obj_panel.offset_top = 46
	_obj_panel.modulate = Color(1, 1, 1, 0.95)
	root.add_child(_obj_panel)
	var ov := VBoxContainer.new()
	_obj_panel.add_child(ov)
	var oh := HBoxContainer.new()
	ov.add_child(oh)
	_obj_title = HT.make_label("OBJECTIVES", HT.AMBER, 14)
	_obj_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oh.add_child(_obj_title)
	var ox := Button.new()
	ox.text = "x"
	ox.tooltip_text = "Dismiss objectives"
	ox.custom_minimum_size = Vector2(26, 22)
	ox.pressed.connect(_on_objectives_dismiss)
	oh.add_child(ox)
	objectives.update(_world(), _pf())
	for it in objectives.items:
		var l := HT.make_label("", HT.TEXT, 14)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # G3a: long role names must not widen the panel
		ov.add_child(l)
		_obj_labels.append(l)

	g3_score.build(root, _obj_panel)
	g3b_stage.build(root, self)

	# ---- hover info
	_hover_lbl = HT.make_label("", HT.TEXT, 14)
	_hover_lbl.anchor_top = 1.0
	_hover_lbl.anchor_bottom = 1.0
	_hover_lbl.offset_left = 220
	_hover_lbl.offset_top = -246
	_hover_lbl.add_theme_constant_override("outline_size", 4)
	_hover_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	root.add_child(_hover_lbl)

	# ---- bottom panel
	var bottom := PanelContainer.new()
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -214
	bottom.add_theme_stylebox_override("panel", HT.box(Color("101417"), HT.EDGE, 1, 0, 8))
	root.add_child(bottom)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 12)
	bottom.add_child(bh)
	_minimap = MinimapScript.new()
	_minimap.setup(mv)
	bh.add_child(_minimap)
	# inspector
	var iv := VBoxContainer.new()
	iv.custom_minimum_size = Vector2(340, 0)
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iv.add_theme_constant_override("separation", 4)
	bh.add_child(iv)
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 8)
	iv.add_child(ih)
	_insp_icon = TextureRect.new()
	_insp_icon.custom_minimum_size = Vector2(40, 40)
	_insp_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_insp_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_insp_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ih.add_child(_insp_icon)
	_insp_name = HT.make_label("No selection", HT.AMBER, 18)
	_insp_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ih.add_child(_insp_name)
	_insp_hp = ProgressBar.new()
	_insp_hp.custom_minimum_size = Vector2(0, 16)
	_insp_hp.show_percentage = false
	_insp_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(_insp_hp)
	_insp_info = HT.make_label("", HT.TEXT, 14)
	_insp_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(_insp_info)
	_insp_counts = GridContainer.new()
	_insp_counts.columns = 4
	_insp_counts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(_insp_counts)
	g2_insp.build(iv, _insp_info, root)
	g2_cmd.hud = self
	# command card
	var cv := VBoxContainer.new()
	cv.custom_minimum_size = Vector2(580, 0)
	cv.add_theme_constant_override("separation", 4)
	bh.add_child(cv)
	_card_title = HT.make_label("", HT.AMBER, 14)
	cv.add_child(_card_title)
	_card_grid = GridContainer.new()
	_card_grid.columns = 4
	_card_grid.add_theme_constant_override("h_separation", 4)
	_card_grid.add_theme_constant_override("v_separation", 4)
	cv.add_child(_card_grid)
	_queue_box = HBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 4)
	cv.add_child(_queue_box)
	_hint = HT.make_label("", HT.YELLOW, 14)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_hint)


func _tb_label(parent: Control, col: Color) -> Label:
	var l := HT.make_label("", col, 16)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(l)
	return l


func _on_objectives_dismiss() -> void:
	objectives.dismissed = true
	_obj_panel.visible = false


func _on_pause_pressed() -> void:
	_set_paused(not bool(mv.get("paused")))


# ------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	# G4 (THREAD): while a sim step is in flight the HUD keeps its last state (it reads live
	# dicts); it refreshes on the next frame after the hand-over.
	if mv != null and mv.has_method("sim_busy") and mv.sim_busy():
		return
	var w := _world()
	if w == null:
		return
	if not _connected and w.tick != _last_poll_tick:
		_last_poll_tick = w.tick
		_on_events(w.events)
	_update_alerts()
	_acc += delta
	if _acc >= REFRESH_SECS:
		_acc = 0.0
		_refresh()


func _refresh() -> void:
	var w := _world()
	if w == null or not w.factions.has(_pf()):
		return
	var f: Dictionary = w.factions[_pf()]
	_credits.text = "Credits %d" % int(f.credits)
	_salvage.text = "Salvage %d" % int(f.stock.get("salvage", 0))
	_ore.text = "Ore %d" % int(f.stock.get("ore", 0))
	var fuel := int(f.stock.get("fuel", 0))
	var ammo := int(f.stock.get("ammo", 0))
	_fuel.text = "Fuel %d%s" % [fuel, "  LOW" if fuel < 100 else ""]
	_fuel.add_theme_color_override("font_color", HT.RED if fuel < 100 else Color("d9c05a"))
	_ammo.text = "Ammo %d%s" % [ammo, "  LOW" if ammo < 100 else ""]
	_ammo.add_theme_color_override("font_color", HT.RED if ammo < 100 else Color("d08a4a"))
	var pp := int(f.power_prod)
	var pu := int(f.power_use)
	_power.text = "Power %d use / %d prod%s" % [pu, pp, "  LOW" if pu > pp else ""]
	_power.add_theme_color_override("font_color", HT.RED if pu > pp else HT.YELLOW)
	var pop := int(f.pop)
	var cap := int(f.pop_cap)
	_pop.text = "Pop %d / %d" % [pop, cap]
	_pop.add_theme_color_override("font_color", HT.RED if pop >= cap and cap > 0 else HT.BLUE)
	_stage.text = "Stage %d" % int(f.stage)
	_clock.text = HT.clock_text(w.tick)
	var paused: bool = bool(mv.get("paused"))
	var spd: float = float(mv.get("speed"))
	_btn_pause.set_pressed_no_signal(paused)
	_paused_banner.visible = paused and not suppress_banner
	for i in _btn_speed.size():
		(_btn_speed[i] as Button).set_pressed_no_signal(is_equal_approx(spd, float(i + 1)))
	objectives.update(w, _pf())
	_refresh_objectives()
	g3_score.update(w, _pf())
	g3b_stage.update(w, _pf())
	_refresh_selection(w)
	_refresh_hover()


func _refresh_objectives() -> void:
	_obj_panel.visible = not objectives.dismissed
	_obj_title.text = "OBJECTIVES  %d/%d" % [objectives.count_done(), objectives.items.size()]
	for i in mini(objectives.items.size(), _obj_labels.size()):
		var it: Dictionary = objectives.items[i]
		var ok: bool = objectives.is_done(String(it.id))
		var l: Label = _obj_labels[i]
		l.text = ("[x] " if ok else "[ ] ") + String(it.text)
		l.add_theme_color_override("font_color", HT.GREEN if ok else HT.TEXT)


func _refresh_hover() -> void:
	_hover_lbl.text = ""
	if mv != null and mv.has_method("get_hover_info"):
		var h = mv.get_hover_info()
		if typeof(h) == TYPE_STRING:
			_hover_lbl.text = h
		elif typeof(h) == TYPE_DICTIONARY:
			_hover_lbl.text = String(h.get("text", ""))


# ------------------------------------------------------------------ selection
func _sel_entities(w: SimWorld) -> Array:
	var out: Array = []
	var sel = mv.get("selection")
	if sel == null:
		return out
	for id in sel:
		var e = w.entities.get(int(id))
		if e != null:
			out.append(e)
	return out


func _def_name(e: Dictionary) -> String:
	if e.kind == "resource":
		return "Salvage cache" if e.def == "salvage" else "Ore deposit"
	if e.kind == "wreck":
		return "Wreck"
	var d: Dictionary = Content.unit(e.def) if e.kind == "unit" else Content.building(e.def)
	return String(d.get("name", e.def))


func _order_text(e: Dictionary) -> String:
	var o: Dictionary = e.get("order", {"type": "idle"})
	match String(o.get("type", "idle")):
		"idle": return "Idle"
		"move": return "Moving"
		"attack_move": return "Attack-moving"
		"attack": return "Attacking"
		"hold": return "Holding position"
		"gather": return "Gathering (%s)" % String(o.get("phase", "")).replace("_", " ")
		"build": return "Building"
		"patrol": return "Patrolling"
		"guard": return "Guarding"
		"retreat": return "Retreating"
		"repair": return "Repairing"
	return String(o.get("type", "idle"))


func _refresh_selection(w: SimWorld) -> void:
	var ents := _sel_entities(w)
	var pf := _pf()
	g2_insp.update(w, ents)
	_insp_counts.visible = false
	for c in _insp_counts.get_children():
		_insp_counts.remove_child(c)
		c.queue_free()
	if ents.is_empty():
		_insp_icon.texture = null
		_insp_name.text = "No selection"
		_insp_hp.visible = false
		var fac := G3.faction_def(w, _pf())
		_insp_info.text = "Click or drag to select. %s units build; the %s and %s train units." % [
			G3.role_name(fac, "builder", "Engineer"), G3.role_name(fac, "hq", "HQ"), G3.role_name(fac, "barracks", "Barracks")]
		_set_card("none", [], w)
		return
	_insp_hp.visible = true
	if ents.size() == 1:
		var e: Dictionary = ents[0]
		_insp_icon.texture = ArtCatalog.icon(String(e.def))
		var own: bool = int(e.owner) == pf
		var oname := "Neutral"
		if w.factions.has(int(e.owner)):
			oname = "You" if own else String(w.factions[int(e.owner)].name)
		_insp_name.text = "%s  (%s)" % [_def_name(e), oname]
		_insp_hp.max_value = maxf(1.0, float(e.max_hp))
		_insp_hp.value = float(e.hp)
		var info := "HP %d / %d" % [int(e.hp), int(e.max_hp)]
		if e.kind == "unit":
			info += "\n" + _order_text(e)
			if String(e.carry.get("res", "")) != "" and int(e.carry.get("amt", 0)) > 0:
				info += "\nCarrying %d %s" % [int(e.carry.amt), e.carry.res]
		elif e.kind == "building":
			if not bool(e.built):
				info += "\nUNDER CONSTRUCTION  %d%%" % int(float(e.progress) * 100.0)
			else:
				var st := String(e.get("status", ""))
				if st != "":
					info += "\nBlocked: " + _status_text(st)
				var d := Content.building(e.def)
				if int(d.get("power", 0)) != 0:
					info += "\nPower %+d" % int(d.power)
				if int(d.get("pop_cap", 0)) > 0:
					info += "\nSupply +%d" % int(d.pop_cap)
		elif e.kind == "resource":
			info = "%d remaining" % int(e.amount)
			_insp_hp.visible = false
		_insp_info.text = info
		_set_card_for(e, ents, w)
	else:
		var counts: Dictionary = {}
		var hp := 0.0
		var mhp := 0.0
		for e in ents:
			counts[e.def] = int(counts.get(e.def, 0)) + 1
			hp += float(e.hp)
			mhp += float(e.max_hp)
		_insp_icon.texture = ArtCatalog.icon(String(ents[0].def))
		_insp_name.text = "%d selected" % ents.size()
		_insp_hp.max_value = maxf(1.0, mhp)
		_insp_hp.value = hp
		_insp_info.text = "Total HP %d / %d" % [int(hp), int(mhp)]
		_insp_counts.visible = true
		for d in counts:
			var tr := TextureRect.new()
			tr.texture = ArtCatalog.icon(String(d))
			tr.custom_minimum_size = Vector2(28, 28)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_insp_counts.add_child(tr)
			var nm: Dictionary = Content.unit(String(d))
			if nm.is_empty():
				nm = Content.building(String(d))
			_insp_counts.add_child(HT.make_label("%s x%d   " % [String(nm.get("name", d)), int(counts[d])], HT.TEXT, 14))
		_set_card_for(ents[0], ents, w)


func _status_text(st: String) -> String:
	match st:
		"LOW_POWER": return "low power (build a %s)" % G3.role_name(G3.faction_def(_world(), _pf()), "power", "power plant")
		"SUPPLY_CAP": return "supply cap reached (build a %s)" % G3.role_name(G3.faction_def(_world(), _pf()), "depot", "depot")
	return st.replace("_", " ").to_lower()


# ------------------------------------------------------------------ command card
func _set_card_for(first: Dictionary, ents: Array, w: SimWorld) -> void:
	var pf := _pf()
	var all_own := true
	var any_builder := false
	var all_units := true
	for e in ents:
		if int(e.owner) != pf:
			all_own = false
		if e.kind != "unit":
			all_units = false
		elif bool(Content.unit(e.def).get("can_build", false)):
			any_builder = true
	if not all_own:
		_set_card("none", [], w)
	elif all_units and any_builder:
		_set_card("engineer", ents, w)
	elif all_units:
		_set_card("units", ents, w)
	elif ents.size() == 1 and first.kind == "building":
		_set_card("building" if bool(first.built) else "construct", ents, w)
	else:
		_set_card("none", [], w)


func _set_card(mode: String, ents: Array, w: SimWorld) -> void:
	var id_strs: Array = []
	for e in ents:
		id_strs.append(str(int(e.id)))
	var sig := mode + ":" + ",".join(id_strs)
	var qsig := ""
	if mode == "building":
		var items: Array = []
		for q in ents[0].queue:
			items.append(String(q.item))
		qsig = ",".join(items)
	if sig != _card_sig:
		_card_sig = sig
		_rebuild_card(mode, ents)
		_queue_sig = "?"
	if mode == "building":
		if qsig != _queue_sig:
			_queue_sig = qsig
			_rebuild_queue(ents[0])
	elif _queue_sig != "":
		_queue_sig = ""
		_rebuild_queue({})
	_update_card_state(mode, ents, w)


func _clear_card() -> void:
	_card_buttons.clear()
	_hotkeys.clear()
	_hover_btn = null
	for c in _card_grid.get_children():
		_card_grid.remove_child(c)
		c.queue_free()


func _rebuild_card(mode: String, ents: Array) -> void:
	_clear_card()
	_card_title.text = ""
	var ids: Array = []
	for e in ents:
		ids.append(int(e.id))
	if mode == "engineer":
		_card_title.text = "BUILD   (click a structure, then click the map to place it; hotkeys in brackets)"
		# G3a: the player's faction's buildable defs; hotkeys from data (G3.build_hotkey remaps a
		# key that collides with an order button, e.g. F = Formation, R = Repair)
		var used := {}
		for bid in Content.buildable_for(G3.faction_def(_world(), _pf())):
			var d: Dictionary = Content.building(String(bid))
			var hk := G3.build_hotkey(String(bid), used)
			var btn := _card_button(String(d.name), HT.cost_text(d.cost), hk, String(bid))
			btn.pressed.connect(_on_build_pressed.bind(String(bid)))
			_card_buttons.append({"btn": btn, "kind": "build", "def": String(bid)})
			_register_hotkey(hk, btn)
		_add_unit_buttons(ids, mode)
	elif mode == "units":
		_card_title.text = "ORDERS"
		_add_unit_buttons(ids, mode)
	elif mode == "building":
		var b: Dictionary = ents[0]
		var d: Dictionary = Content.building(b.def)
		var produces: Array = d.get("produces", [])
		_card_title.text = "TRAIN" if not produces.is_empty() else String(d.name).to_upper()
		var bid: int = int(b.id)
		for item in produces:
			var p: Dictionary = Content.production(String(item))
			var btn := _card_button(String(p.name), HT.cost_text(p.cost), String(p.get("hotkey", "")), String(item))
			btn.pressed.connect(_on_train_pressed.bind(bid, String(item)))
			_card_buttons.append({"btn": btn, "kind": "train", "item": String(item), "building": bid})
			_register_hotkey(String(p.get("hotkey", "")), btn)
		if bool(d.get("research", false)):
			_add_research_buttons(bid)
	elif mode == "construct":
		var b2: Dictionary = ents[0]
		_card_title.text = "UNDER CONSTRUCTION"
		var btn2 := _card_button("Cancel build", "refund", "", "")
		btn2.pressed.connect(_issue.bind({"type": "cancel_building", "building_id": int(b2.id)}))
		_card_buttons.append({"btn": btn2, "kind": "plain"})
	g2_cmd.compact(_card_grid)
	# G3a: a 5-column card has 2 rows; smaller text keeps long names + 3-resource costs inside
	# the bottom panel (Human B / Machine build cards).
	if _card_grid.columns >= 5:
		for c in _card_grid.get_children():
			if c is Button:
				c.add_theme_font_size_override("font_size", 12)
	# G3b (UI4-3): a card with 3+ rows (Machine repair-bot build list + Repair + Assign) ran off
	# the bottom of the screen (Assign at y 882..956 on a 900 px window); shorter buttons keep
	# every row inside the 214 px bottom panel.
	var rows := ceili(float(_card_grid.get_child_count()) / float(maxi(1, _card_grid.columns)))
	if rows >= 3:
		var bh := floorf((150.0 - 4.0 * float(rows - 1)) / float(rows))
		for c in _card_grid.get_children():
			if c is Button:
				c.custom_minimum_size = Vector2(138, bh)
				c.add_theme_font_size_override("font_size", 11)
				c.add_theme_constant_override("icon_max_width", 20)


## G3b: research projects on a research building (start; cancel while one is active).
func _add_research_buttons(bid: int) -> void:
	_card_title.text = "RESEARCH   (one project at a time; progress is kept if the building is lost)"
	var fdef := G3.faction_def(_world(), _pf())
	var ps: Dictionary = G3bData.research_projects()
	for pid in G3bData.project_ids_sorted():
		var p: Dictionary = ps[pid]
		var btn := _card_button(G3bData.project_name(String(pid), fdef), "%s  %ds" % [HT.cost_text(p.get("cost", {})), int(p.get("time", 0))], "", "")
		btn.name = "Research_" + String(pid)
		btn.pressed.connect(_issue.bind({"type": "research", "project": String(pid), "building_id": bid}))
		_card_buttons.append({"btn": btn, "kind": "research", "project": String(pid), "building": bid})
	var cancel := _card_button("Cancel research", "full refund", "", "")
	cancel.name = "ResearchCancel"
	cancel.pressed.connect(_issue.bind({"type": "research", "project": "", "cancel": true, "building_id": bid}))
	_card_buttons.append({"btn": cancel, "kind": "research_cancel", "building": bid})


func _research_reason(w: SimWorld, rec: Dictionary) -> String:
	var pf := _pf()
	var f: Dictionary = w.factions[pf]
	var r: Dictionary = f.get("research", {})
	var pid := String(rec.project)
	if (r.get("done", []) as Array).has(pid):
		return "Already researched."
	if String(r.get("active", "")) == pid:
		return "In progress (%d%%)." % int(round(G3bStage._frac(r) * 100.0))
	var lock := G3bData.lock_reason(G3bData.research_projects().get(pid, {}), f, G3.faction_def(w, pf))
	if lock != "":
		return lock
	return w.preview_command({"type": "research", "issuer": pf, "project": pid, "building_id": int(rec.building)})


func _on_train_pressed(bid: int, item: String) -> void:
	_issue({"type": "queue_unit", "building_id": bid, "item": item})


func _add_unit_buttons(ids: Array, mode: String = "units") -> void:
	var stop := _card_button("Stop", "", "S", "")
	stop.pressed.connect(_issue.bind({"type": "stop", "unit_ids": ids.duplicate()}))
	_card_buttons.append({"btn": stop, "kind": "plain"})
	var hold := _card_button("Hold", "", "H", "")
	hold.pressed.connect(_issue.bind({"type": "hold", "unit_ids": ids.duplicate()}))
	_card_buttons.append({"btn": hold, "kind": "plain"})
	g2_cmd.add_buttons(mode, ids)


func _card_button(title: String, cost: String, hotkey: String, icon_id: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(138, 74)
	var t := title
	if hotkey != "":
		t = "[%s] %s" % [hotkey, title]
	b.text = t + ("\n" + cost if cost != "" else "")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = false
	if icon_id != "":
		b.icon = ArtCatalog.icon(icon_id)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 30)
	b.mouse_entered.connect(_on_card_hover.bind(b, true))
	b.mouse_exited.connect(_on_card_hover.bind(b, false))
	_card_grid.add_child(b)
	return b


func _on_card_hover(b: Button, inside: bool) -> void:
	if inside:
		_hover_btn = b
	elif _hover_btn == b:
		_hover_btn = null


func _register_hotkey(key: String, btn: Button) -> void:
	if key != "":
		_hotkeys[key.to_upper()] = btn


func _update_card_state(mode: String, ents: Array, w: SimWorld) -> void:
	var pf := _pf()
	var hint := ""
	for rec in _card_buttons:
		var btn: Button = rec.btn
		var reason := ""
		var kind := String(rec.kind)
		var tip := ""
		if kind == "build":
			reason = _build_reason(w, String(rec.def))
			var d: Dictionary = Content.building(String(rec.def))
			tip = "%s\nCost: %s\nBuild time: %ds" % [d.name, HT.cost_text_long(d.cost), int(d.build_time)]
		elif kind == "research":
			reason = _research_reason(w, rec)
			var rp: Dictionary = G3bData.research_projects().get(String(rec.project), {})
			tip = "%s
Cost: %s
Research time: %ds
For Stage %d" % [G3bData.project_name(String(rec.project), G3.faction_def(w, pf)), HT.cost_text_long(rp.get("cost", {})), int(rp.get("time", 0)), int(rp.get("for_stage", 8))]
			if reason == "Already researched.":
				btn.text = "[done] " + G3bData.project_name(String(rec.project), G3.faction_def(w, pf))
		elif kind == "research_cancel":
			reason = "" if String(w.factions[pf].get("research", {}).get("active", "")) != "" else "No project is active."
			tip = "Cancel the active project (full refund; its progress is lost)."
		elif kind == "train":
			reason = G3bData.production_lock(String(rec.item), w.factions[pf], G3.faction_def(w, pf))
			if reason == "":
				reason = w.preview_command({"type": "queue_unit", "issuer": pf, "building_id": int(rec.building), "item": String(rec.item)})
			var p: Dictionary = Content.production(String(rec.item))
			tip = "%s\nCost: %s\nTrain time: %ds" % [p.name, HT.cost_text_long(p.cost), int(p.train_time)]
		rec["reason"] = reason
		btn.disabled = reason != ""
		if reason != "":
			tip += "\nUnavailable: " + reason
		btn.tooltip_text = tip
	if mode == "engineer" or mode == "units":
		g2_cmd.update_state(w)
	if _hover_btn != null:
		for rec in _card_buttons:
			if rec.btn == _hover_btn and String(rec.get("reason", "")) != "":
				hint = String(rec.reason)
	if hint == "":
		hint = g2_cmd.hint()
	if hint == "" and mode == "building":
		var st := String(ents[0].get("status", ""))
		if st != "":
			hint = "Production blocked: " + _status_text(st)
	_hint.text = hint
	if mode == "building":
		var q: Array = ents[0].queue
		for i in _queue_bars.size():
			if i < q.size():
				(_queue_bars[i] as ProgressBar).value = float(q[i].progress)


func _build_reason(w: SimWorld, def_id: String) -> String:
	var d: Dictionary = Content.building(def_id)
	var pf := _pf()
	var lock := G3bData.lock_reason(d, w.factions[pf], G3.faction_def(w, pf))  # G3b stage / research
	if lock != "":
		return lock
	for req in d.get("requires", []):
		var have := false
		for b in w.buildings_of(pf, String(req)):
			if bool(b.built):
				have = true
		if not have:
			return "Requires %s." % String(Content.building(String(req)).get("name", req))
	return w.can_afford(pf, d.cost)


func _rebuild_queue(b: Dictionary) -> void:
	for c in _queue_box.get_children():
		_queue_box.remove_child(c)
		c.queue_free()
	_queue_bars.clear()
	if b.is_empty():
		return
	var q: Array = b.queue
	var bid: int = int(b.id)
	for i in q.size():
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(108, 26)
		var p: Dictionary = Content.production(String(q[i].item))
		btn.text = "%s %s" % [">" if i == 0 else "#%d" % (i + 1), String(p.get("name", q[i].item)).get_slice(" (", 0)]
		btn.clip_text = true
		btn.tooltip_text = "Click to cancel (full refund)"
		btn.pressed.connect(_issue.bind({"type": "cancel_unit", "building_id": bid, "index": i}))
		vb.add_child(btn)
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(108, 8)
		pb.max_value = 1.0
		pb.show_percentage = false
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(pb)
		_queue_box.add_child(vb)
		_queue_bars.append(pb)


func _on_build_pressed(def_id: String) -> void:
	if mv.has_method("begin_build_placement"):
		mv.begin_build_placement(def_id)


func _issue(cmd: Dictionary) -> void:
	if mv != null and mv.has_method("issue"):
		mv.issue(cmd.duplicate(true))


func _set_paused(p: bool) -> void:
	mv.set("paused", p)
	_refresh()


func _set_speed(s: float) -> void:
	mv.set("speed", s)
	_refresh()


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: InputEventKey = event
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	if k.keycode == KEY_P:
		_set_paused(not bool(mv.get("paused")))
		get_viewport().set_input_as_handled()
		return
	var key := OS.get_keycode_string(k.keycode).to_upper()
	if _hotkeys.has(key):
		var btn: Button = _hotkeys[key]
		if is_instance_valid(btn):
			if btn.disabled:
				for rec in _card_buttons:
					if rec.btn == btn and String(rec.get("reason", "")) != "":
						_push_alert(String(rec.reason), HT.RED)
			else:
				btn.pressed.emit()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ alerts
func _push_alert(text: String, color: Color, pos: Variant = null) -> void:
	_alerts.append({"text": text, "color": color, "born": Time.get_ticks_msec() / 1000.0})
	if _alerts.size() > 12:
		_alerts.pop_front()
	if pos is Vector2:
		last_alert_pos = pos
		has_alert_pos = true


func _throttled(key: String, ticks: int, w: SimWorld) -> bool:
	var last := int(_alert_throttle.get(key, -100000))
	if w.tick - last < ticks:
		return true
	_alert_throttle[key] = w.tick
	return false


func _update_alerts() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while not _alerts.is_empty() and now - float(_alerts[0].born) > ALERT_LIFE:
		_alerts.pop_front()
	var shown := _alerts.slice(maxi(0, _alerts.size() - ALERT_MAX))
	for i in ALERT_MAX:
		var l: Label = _alert_box.get_child(i)
		if i < shown.size():
			var a: Dictionary = shown[i]
			l.text = String(a.text)
			var age := now - float(a.born)
			var alpha := clampf((ALERT_LIFE - age) / 2.0, 0.0, 1.0)
			var c: Color = a.color
			l.add_theme_color_override("font_color", Color(c.r, c.g, c.b, alpha))
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9 * alpha))
		else:
			l.text = ""


func _owner_of(w: SimWorld, ev: Dictionary) -> int:
	if ev.has("owner"):
		return int(ev.owner)
	if ev.has("faction"):
		return int(ev.faction)
	for k in ["building_id", "id", "entity"]:
		if ev.has(k):
			var e = w.entities.get(int(ev[k]))
			if e != null:
				return int(e.owner)
	return SimWorld.NEUTRAL


func _name_of(w: SimWorld, ev: Dictionary) -> String:
	var d := String(ev.get("def", ""))
	if d == "":
		for k in ["building_id", "id", "entity"]:
			if ev.has(k) and w.entities.has(int(ev[k])):
				d = String(w.entities[int(ev[k])].def)
				break
	if d == "":
		return "Structure"
	var b := Content.building(d)
	if b.is_empty():
		b = Content.unit(d)
	return String(b.get("name", d))


func _on_events(events: Array) -> void:
	var w := _world()
	if w == null:
		return
	var pf := _pf()
	objectives.update(w, pf, events)
	for ev in events:
		match String(ev.get("type", "")):
			"CommandRejected":
				if int(ev.get("issuer", -1)) == pf:
					_push_alert(String(ev.get("reason", "Command rejected.")), HT.RED)
			"ConstructionCompleted":
				if _owner_of(w, ev) == pf:
					_push_alert("Construction complete: %s" % _name_of(w, ev), HT.GREEN, _ev_pos(w, ev))
			"ProductionCompleted":
				if _owner_of(w, ev) == pf:
					var p := Content.production(String(ev.get("item", "")))
					_push_alert("Trained: %s" % String(p.get("name", ev.get("item", "unit"))), HT.GREEN, _ev_pos(w, ev))
			"ProductionBlocked":
				if _owner_of(w, ev) == pf:
					var reason := String(ev.get("reason", ev.get("status", "blocked")))
					if not _throttled("pb:" + reason, 20 * 6, w):
						_push_alert("%s production blocked: %s" % [_name_of(w, ev), _status_text(reason)], HT.YELLOW, _ev_pos(w, ev))
			"ShotFired":
				var tgt = w.entities.get(int(ev.get("target", -1)))
				var shooter = w.entities.get(int(ev.get("shooter", -1)))
				if tgt != null and int(tgt.owner) == pf and (shooter == null or int(shooter.owner) != pf):
					if not _throttled("attack", ATTACK_ALERT_TICKS, w):
						_push_alert("Base under attack!" if tgt.kind == "building" else "Our units are under attack!", HT.RED, tgt.pos)
				elif tgt != null and G3.is_ally(w, pf, int(tgt.owner)) and (shooter == null or not G3.is_ally(w, int(tgt.owner), int(shooter.owner))):
					# G3a: an ally (same team) is being shot by a non-ally
					if not _throttled("ally_attack:%d" % int(tgt.owner), ATTACK_ALERT_TICKS, w):
						_push_alert("Ally under attack: %s" % String(w.factions[int(tgt.owner)].name), G3.side_color(w, int(tgt.owner)).lightened(0.3), tgt.pos)
			"EntityDestroyed":
				if int(ev.get("owner", -2)) == pf and String(ev.get("kind", "")) != "resource":
					var ko := int(ev.get("killer_owner", -1))
					if ko != pf and ko != SimWorld.NEUTRAL and not _throttled("lost", 20 * 4, w):
						_push_alert("Lost: %s" % _name_of(w, ev), HT.RED, ev.get("pos", null))
			"SideEliminated":
				var fid := int(ev.get("faction", ev.get("fid", ev.get("owner", -1))))
				var nm := String(w.factions[fid].name) if w.factions.has(fid) else "A side"
				var rel := "Ally " if G3.is_ally(w, pf, fid) else ("" if fid == pf else "Enemy ")
				_push_alert("%s%s has been eliminated." % [rel, nm], HT.RED if rel == "Ally " or fid == pf else HT.AMBER)
			"MatchEnded":
				var wt := int(ev.get("winner_team", G3.team_of(w, int(ev.get("winner", -1)))))
				_push_alert("Match ended: Team %d wins." % (wt + 1) if wt >= 0 else "Match ended.", HT.AMBER)
			_:
				if not g3b_stage.on_event(w, pf, ev):
					g2_alerts.on_event(self, w, pf, ev)


func _ev_pos(w: SimWorld, ev: Dictionary) -> Variant:
	if ev.has("pos"):
		return ev.pos
	for k in ["building_id", "id"]:
		if ev.has(k) and w.entities.has(int(ev[k])):
			return w.entities[int(ev[k])].pos
	return null
