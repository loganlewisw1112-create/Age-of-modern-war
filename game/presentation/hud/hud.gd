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
const G4bCommands = preload("res://presentation/hud/g4b_commands.gd")  # G4b (UI4B)
const G3 = preload("res://presentation/hud/g3_faction.gd")
const G4bAlerts = preload("res://presentation/hud/g4b_alerts.gd")
const G3Score = preload("res://presentation/hud/g3_score.gd")
# G3b (UI4): stage panel, research card, stage/research lock reasons
const G3bStage = preload("res://presentation/hud/g3b_stage.gd")
const G3bData = preload("res://presentation/hud/g3b_data.gd")

const REFRESH_SECS := 0.2
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")      # G5 (UI5a) panel kit
const HudExtras = preload("res://presentation/ui5/kit/hud_extras.gd")
const Ui6aHub = preload("res://presentation/ui6/a/ui6a_hub.gd")          # G6 (UI6a): market, army builder, forces, commanders
const TeamsPanel = preload("res://presentation/ui6/teams_panel.gd")      # G6.1 (SQUAD61): Teams panel (F2)
const CommandLayer = preload("res://presentation/ui6/command_layer/command_layer.gd")  # G6.1 (PLAN61): plans on the map
const CompanyCard = preload("res://presentation/ui6/a/company_card.gd")
const DroneInput = preload("res://presentation/hud/drone_input.gd")  # G7 (DRONE7): player-flown drones + drone cam
const Companies = preload("res://sim/systems/companies.gd")
const RealismInfo = preload("res://presentation/ui6/realism_info.gd")  # G6.1 (REAL61)
const Progression = preload("res://sim/systems/progression.gd")       # G6 (UI6a): research_list (side's faction only)
const Elevation = preload("res://sim/systems/elevation.gd")           # G6 (UI6a, PT6 CR 1193): HIGH GROUND inspector tag
const TOP_H := 34.0        # G5 layout (virtual canvas px; ScaledLayer scales them)
const BOTTOM_H := 220.0    # keep <= 222: UI5b's cargo strip sits right above it (-284..-222)
const EDGE_M := 12.0
const ALERT_W := 500.0
const RIGHT_W := 306.0
const INSP_MIN_W := 270.0
const CARD_MIN_W := 500.0
const BTN_MIN_W := 112.0
const ALERT_LIFE := 9.0
const ALERT_MAX := 6
const ATTACK_ALERT_TICKS := 20 * 10

var mv: Node = null
var layer: Node = null
var objectives := ObjectivesScript.new()
var g2_insp = G2Inspector.new()
var g2_cmd = G2Commands.new()
var g4b_cmd = G4bCommands.new()
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
var _insp_wound: Control  # G7 (WOUND7 CR hud_wound_card): body diagram replaces the infantry hp bar
var _insp_info: Label
var _insp_counts: Container
var _card_cv: VBoxContainer
var _left_scroll: ScrollContainer
var _insp_scroll: ScrollContainer
var _card_pager: Button = null
var _card_page := 0
var _right_scroll: ScrollContainer
var _card_scroll: ScrollContainer
var extras = HudExtras.new()   # G5: control groups, idle button, F1 sheet
var ui6a = Ui6aHub.new()       # G6 (UI6a): the four G6 panels (modal)
var teams = TeamsPanel.new()   # G6.1 (SQUAD61)
var cmd_layer = CommandLayer.new()   # G6.1 (PLAN61)
var ops7 = null   # G7 OPSUI7: operations room hub (presentation/ui7/ops_panel.gd)
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
	var drone_in = DroneInput.new()  # G7 DRONE7 CR hud_drone_input
	drone_in.name = "DroneInput"
	add_child(drone_in)
	drone_in.setup(mv)
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
	# G5 (UI5a): anchored, container-driven layout. Nothing is placed in absolute pixels except
	# margins; the bottom panel has a fixed height and grows upward, never off-screen; the card
	# re-fits its columns/rows to the space it has (_fit_card); long inspector text scrolls.
	var root: Control = layer.root
	# ---- top bar
	var top := UiKit.panel("header")
	top.name = "TopBar"
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, TOP_H)
	root.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	top.add_child(hb)
	# resources sit in a scroll strip (min width 0): on a canvas narrower than the readouts they
	# truncate at the right instead of pushing the buttons off the screen
	var res_strip := ScrollContainer.new()
	res_strip.name = "ResStrip"
	res_strip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	res_strip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	res_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_strip.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(res_strip)
	var rb := HBoxContainer.new()
	rb.add_theme_constant_override("separation", 16)
	res_strip.add_child(rb)
	_credits = _tb_label(rb, HT.AMBER, "Credits: spent on everything")
	_salvage = _tb_label(rb, Color("c9ccc4"), "Salvage: gathered from wrecks and scrap fields")
	_ore = _tb_label(rb, Color("e0944a"), "Ore: mined by gatherers")
	_fuel = _tb_label(rb, Color("d9c05a"), "Fuel stock: vehicles and aircraft burn it")
	_ammo = _tb_label(rb, Color("d08a4a"), "Ammo stock: units restock from it")
	_power = _tb_label(rb, HT.YELLOW, "Power: use / production")
	_pop = _tb_label(rb, HT.BLUE, "Population / supply cap")
	_stage = _tb_label(rb, HT.DIM, "Tech stage")
	_clock = _tb_label(rb, HT.TEXT, "Match time")
	_btn_pause = UiKit.button("Pause", "P", "Pause or resume the match")
	_btn_pause.toggle_mode = true
	_btn_pause.pressed.connect(_on_pause_pressed)
	hb.add_child(_btn_pause)
	for s in [1.0, 2.0, 3.0]:
		var b := Button.new()
		b.text = "%dx" % int(s)
		b.tooltip_text = "Game speed %dx" % int(s)
		b.toggle_mode = true
		b.pressed.connect(_set_speed.bind(s))
		hb.add_child(b)
		_btn_speed.append(b)
	var fb := UiKit.button("Forces", "", "Forces: your armies and companies (cards, refill, form / disband armies)")
	fb.name = "ForcesButton"
	fb.pressed.connect(func(): ui6a.toggle("forces"))
	hb.add_child(fb)
	var cb := UiKit.button("Commanders", "", "AI Commanders: hand a formation or a role to an AI commander")
	cb.name = "CommandersButton"
	cb.pressed.connect(func(): ui6a.toggle("commanders"))
	hb.add_child(cb)
	var mb := UiKit.button("Menu", "Esc", "Pause menu: save, load, settings, quit")
	mb.pressed.connect(func(): menu_requested.emit())
	hb.add_child(mb)

	_paused_banner = UiKit.label("PAUSED", "title")
	_paused_banner.add_theme_font_size_override("font_size", 34)
	_paused_banner.add_theme_constant_override("outline_size", 6)
	_paused_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_paused_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_paused_banner.anchor_top = 0.3
	_paused_banner.anchor_bottom = 0.3
	_paused_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused_banner.visible = false
	root.add_child(_paused_banner)

	# ---- left stack (alerts feed, then the G3b stage panel), top-left under the bar
	_left_scroll = _stack_scroll("LeftScroll")
	_left_scroll.position = Vector2(EDGE_M, TOP_H + 8)
	root.add_child(_left_scroll)
	var left := VBoxContainer.new()
	left.name = "LeftStack"
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 6)
	_left_scroll.add_child(left)
	if preload("res://presentation/ui7/lp_hud.gd").wants(_world()):  # G7 LPMODE7 CR: Last Protocol meters card + end panel
		preload("res://presentation/ui7/lp_hud.gd").attach(left, mv, root)
	_alert_box = VBoxContainer.new()
	_alert_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_box.custom_minimum_size = Vector2(0, 0)   # width comes from the visible lines only
	_alert_box.add_theme_constant_override("separation", 2)
	left.add_child(_alert_box)
	for i in ALERT_MAX:
		var l := HT.make_label("", HT.TEXT, 15)
		l.add_theme_constant_override("outline_size", 4)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size = Vector2(ALERT_W, 0)
		l.visible = false
		_alert_box.add_child(l)

	# ---- right stack (objectives, then the victory panel), top-right under the bar
	_right_scroll = _stack_scroll("RightScroll")
	_right_scroll.anchor_left = 1.0
	_right_scroll.anchor_right = 1.0
	_right_scroll.offset_left = -(RIGHT_W + EDGE_M)
	_right_scroll.offset_right = -EDGE_M
	_right_scroll.offset_top = TOP_H + 8
	_right_scroll.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(_right_scroll)
	var right := VBoxContainer.new()
	right.name = "RightStack"
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.custom_minimum_size = Vector2(RIGHT_W, 0)
	right.add_theme_constant_override("separation", 6)
	_right_scroll.add_child(right)
	_obj_panel = UiKit.panel("frame")
	_obj_panel.name = "ObjectivesPanel"
	_obj_panel.modulate = Color(1, 1, 1, 0.95)
	right.add_child(_obj_panel)
	var ov := VBoxContainer.new()
	_obj_panel.add_child(ov)
	var oh := HBoxContainer.new()
	ov.add_child(oh)
	_obj_title = UiKit.label("OBJECTIVES", "header")
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

	g3_score.build(right, _obj_panel)
	if preload("res://presentation/ui7/lp_hud.gd").wants(_world()):  # G7 LPMODE7 CR seq 939: no skirmish objectives/victory cards in Last Protocol
		preload("res://presentation/ui7/lp_hud.gd").hide_skirmish_cards(self)
	g3b_stage.build(left, self)

	# ---- hover info (just above the bottom panel)
	_hover_lbl = HT.make_label("", HT.TEXT, 14)
	_hover_lbl.anchor_top = 1.0
	_hover_lbl.anchor_bottom = 1.0
	_hover_lbl.offset_left = 220
	_hover_lbl.offset_top = -(BOTTOM_H + 32)
	_hover_lbl.offset_bottom = -(BOTTOM_H + 10)
	_hover_lbl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hover_lbl.add_theme_constant_override("outline_size", 4)
	_hover_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	root.add_child(_hover_lbl)
	_build_bottom(root)
	extras.build(self, root)
	ui6a.build(self, root)   # G6 (UI6a): after everything else, so the modal panels draw on top
	cmd_layer.build(self, root)   # G6.1 (PLAN61)
	teams.build(self, root)       # G6.1 (SQUAD61)
	ops7 = preload("res://presentation/ui7/ops_panel.gd").attach(self, root, left)   # G7 OPSUI7 CR 1401: ops room modal + PROTOCOL card
	preload("res://presentation/ui7/dronebay_card.gd").attach(self, left)   # G7 DRONEBAY7 CR 5737: drone bay card (Drones n/12, LAUNCH / FPV / RECALL / AUTO)
	preload("res://presentation/ui7/lpreserve_card.gd").attach(self, left)   # G7 LPRES7 (13.9c-34): Last Protocol barracks reserve card (In n/100, RELEASE / RECALL / AUTO)
	extras.bar.resized.connect(_cap_stacks)
	left.resized.connect(_cap_stacks)
	right.resized.connect(_cap_stacks)
	layer.root.resized.connect(_cap_stacks)


func _build_bottom(root: Control) -> void:
	var bottom := UiKit.panel("frame")
	bottom.name = "BottomPanel"
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -BOTTOM_H
	bottom.offset_bottom = 0.0
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN   # extra height goes up, never off-screen
	root.add_child(bottom)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	bottom.add_child(bh)
	var mm_frame := UiKit.panel("inset")
	mm_frame.name = "MinimapFrame"
	var mmsb = UiKit.box("inset")
	mmsb.set_content_margin_all(3.0)
	mm_frame.add_theme_stylebox_override("panel", mmsb)
	mm_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(mm_frame)
	_minimap = MinimapScript.new()
	_minimap.setup(mv)
	mm_frame.add_child(_minimap)
	# inspector (scrolls if a selection has more lines than fit)
	var isc := ScrollContainer.new()
	isc.name = "InspectorScroll"
	isc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	isc.custom_minimum_size = Vector2(INSP_MIN_W, 0)
	_insp_scroll = isc
	bh.add_child(isc)
	var iv := VBoxContainer.new()
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iv.add_theme_constant_override("separation", 4)
	isc.add_child(iv)
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
	_insp_name.add_theme_font_override("font", UiKit.font(true))
	_insp_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_insp_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_insp_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ih.add_child(_insp_name)
	_insp_hp = UiKit.bar("hp")
	_insp_hp.custom_minimum_size = Vector2(0, 14)
	iv.add_child(_insp_hp)
	_insp_wound = preload("res://presentation/ui7/wound_card.gd").new()
	iv.add_child(_insp_wound)
	_insp_wound.visible = false
	_insp_info = HT.make_label("", HT.TEXT, 14)
	_insp_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(_insp_info)
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override("h_separation", 4)
	_insp_counts = flow
	iv.add_child(_insp_counts)
	g2_insp.build(iv, _insp_info, root)
	g2_cmd.hud = self
	g4b_cmd.hud = self
	g4b_cmd.build(root)
	# command card: title, button grid (re-fitted to the space; scrolls only as a last resort),
	# production queue, hint
	var cv := VBoxContainer.new()
	cv.name = "CommandCard"
	cv.custom_minimum_size = Vector2(CARD_MIN_W, 0)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.size_flags_stretch_ratio = 1.7
	cv.add_theme_constant_override("separation", 4)
	bh.add_child(cv)
	_card_cv = cv
	_card_title = UiKit.label("", "header")
	_card_title.add_theme_font_size_override("font_size", 14)
	_card_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cv.add_child(_card_title)
	_card_scroll = ScrollContainer.new()
	_card_scroll.name = "CardScroll"
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(_card_scroll)
	_card_grid = GridContainer.new()
	_card_grid.columns = 4
	_card_grid.add_theme_constant_override("h_separation", 4)
	_card_grid.add_theme_constant_override("v_separation", 4)
	_card_scroll.add_child(_card_grid)
	_queue_box = HBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 4)
	cv.add_child(_queue_box)
	_hint = HT.make_label("", HT.YELLOW, 14)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.visible = false
	cv.add_child(_hint)
	cv.resized.connect(_fit_card)


## G5 (UI5a): choose columns / button size so the whole card fits the bottom panel (replaces the
## G3a/G3b per-case shrinking). When even 3-line buttons cannot all fit (G5 build lists run past 24
## structures) the build/train/research buttons are paged ("More" button, hotkeys keep working for
## every page); order buttons (Stop, Hold, ...) stay on every page. The scroll is a last resort.
func _fit_card() -> void:
	if _card_grid == null or _card_cv == null:
		return
	var pageable: Array = []
	for rec in _card_buttons:
		if is_instance_valid(rec.btn) and ["build", "train", "research"].has(String(rec.kind)):
			pageable.append(rec.btn)
	var fixed: Array = []
	for c in _card_grid.get_children():
		if c is Button and c != _card_pager and not pageable.has(c) and (c.visible or c.has_meta("ui5_paged")):
			fixed.append(c)
	var n := pageable.size() + fixed.size()
	if n == 0:
		return
	var w := maxf(_card_cv.size.x, CARD_MIN_W)
	var cols := clampi(int((w + 4.0) / (BTN_MIN_W + 4.0)), 3, 8)
	var avail := BOTTOM_H - 18.0 - _card_title.get_combined_minimum_size().y - 4.0
	if _queue_box.get_child_count() > 0:
		avail -= _queue_box.get_combined_minimum_size().y + 4.0
	if _hint.text != "":
		avail -= _hint.get_combined_minimum_size().y + 4.0
	var f: Font = UiKit.font(false)
	var need3 := _btn_need(f, 11)   # 2-line name + cost line at the smallest card font
	var cap_rows := maxi(1, int((avail + 4.0) / (need3 + 4.0)))
	var shown: Array = pageable
	var pages := 1
	if n > cols * cap_rows and pageable.size() > 1:
		var per := maxi(1, cols * cap_rows - fixed.size() - 1)
		pages = ceili(float(pageable.size()) / float(per))
		_card_page = _card_page % pages
		shown = pageable.slice(_card_page * per, mini(pageable.size(), (_card_page + 1) * per))
	for b in pageable:
		b.visible = shown.has(b)
		b.set_meta("ui5_paged", true)
	if pages > 1:
		if _card_pager == null or not is_instance_valid(_card_pager):
			_card_pager = UiKit.button("More", "", "Show the next page of this card (hotkeys work on every page)")
			_card_pager.pressed.connect(func(): _card_page += 1; _fit_card())
			_card_grid.add_child(_card_pager)
		_card_pager.text = "More  %d/%d" % [_card_page + 1, pages]
		_card_pager.visible = true
		_card_grid.move_child(_card_pager, (shown.back() as Node).get_index() + 1)
	elif _card_pager != null and is_instance_valid(_card_pager):
		_card_pager.visible = false
	var count := shown.size() + fixed.size() + (1 if pages > 1 else 0)
	var rows := ceili(float(count) / float(cols))
	var bh := clampf(floorf((avail - 4.0 * float(rows - 1)) / float(rows)), 34.0, 74.0)
	var bw := clampf(floorf((w - 4.0 * float(cols - 1)) / float(cols)) - 1.0, BTN_MIN_W, 190.0)
	var fs := 11
	for cand in [14, 13, 12]:
		if _btn_need(f, cand) <= bh:
			fs = cand
			break
	var icons := bh >= 60.0   # short buttons give the icon's width to the text
	_card_grid.columns = mini(cols, count)
	for c in _card_grid.get_children():
		if c is Button:
			var b := c as Button
			b.custom_minimum_size = Vector2(bw, bh)
			b.add_theme_font_size_override("font_size", fs)
			b.add_theme_constant_override("icon_max_width", clampi(int(bh * 0.4), 14, 24))
			if b.icon != null and not icons:
				b.set_meta("ui5_icon", b.icon)
				b.icon = null
			elif icons and b.icon == null and b.has_meta("ui5_icon"):
				b.icon = b.get_meta("ui5_icon")


## Height a card button needs for 3 text lines (wrapped name + cost) at font size fs (conservative).
func _btn_need(f: Font, fs: int) -> float:
	return 3.0 * (f.get_height(fs) + 2.0) + 12.0


func _stack_scroll(nm: String) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = nm
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	return sc


## G5 (UI5a): size the left/right stacks to their content, capped above the bottom panel and the
## group bar, so they scroll instead of running into them on short canvases (720p at 150 %).
func _cap_stacks() -> void:
	if _left_scroll == null or layer == null:
		return
	var cs: Vector2 = layer.canvas_size()
	var bar_h := 0.0
	# G6 (UI6a): selecting a platoon / company officer shows the G2 group panel bottom-right, above the
	# bottom panel (-380..-222): lift the group bar above it and end the right stack above both
	var shift := 0.0
	var gp = g2_insp.get("group_panel")
	if gp is Control and (gp as Control).visible:
		shift = maxf(0.0, -(BOTTOM_H + 6.0) - ((gp as Control).offset_top - 6.0))
	if extras.bar != null:
		extras.bar.offset_bottom = -(BOTTOM_H + 6.0) - shift
		extras.bar.offset_top = extras.bar.offset_bottom - 30.0
		bar_h = extras.bar.size.y + 8.0 + shift
	# alert lines never reach the centred PAUSED banner / cargo strip
	var aw := clampf(cs.x * 0.5 - 90.0 - EDGE_M, 260.0, ALERT_W)
	for l in _alert_box.get_children():
		(l as Control).custom_minimum_size.x = aw
	if _insp_scroll != null:
		_insp_scroll.custom_minimum_size.x = clampf(floorf(cs.x * 0.22), INSP_MIN_W, 380.0)
	for sc in [_left_scroll, _right_scroll]:
		var c: Control = sc.get_child(0)
		var need := c.get_combined_minimum_size()
		var avail := cs.y - (TOP_H + 8.0) - BOTTOM_H - 10.0 - (bar_h if sc == _right_scroll else 34.0)
		var h := clampf(need.y, 0.0, maxf(avail, 60.0))
		# fits: no scrolling at all (the container then sizes itself to the content)
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if need.y <= h + 0.5 else ScrollContainer.SCROLL_MODE_AUTO
		var w := need.x + (14.0 if need.y > h + 0.5 else 0.0)
		if sc == _right_scroll:
			sc.offset_left = -(EDGE_M + w)
			sc.offset_right = -EDGE_M
			sc.offset_bottom = sc.offset_top + h
		else:
			sc.size = Vector2(w, h)


func _tb_label(parent: Control, col: Color, tip: String = "") -> Label:
	var l := HT.make_label("", col, UiKit.FS_NUMBER)
	l.add_theme_font_override("font", UiKit.font(true))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS if tip != "" else Control.MOUSE_FILTER_IGNORE
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
	_credits.text = "CR %d" % int(f.credits)
	_salvage.text = "SALV %d" % int(f.stock.get("salvage", 0))
	_ore.text = "ORE %d" % int(f.stock.get("ore", 0))
	var fuel := int(f.stock.get("fuel", 0))
	var ammo := int(f.stock.get("ammo", 0))
	_fuel.text = "FUEL %d%s" % [fuel, " LOW" if fuel < 100 else ""]
	_fuel.add_theme_color_override("font_color", HT.RED if fuel < 100 else Color("d9c05a"))
	_ammo.text = "AMMO %d%s" % [ammo, " LOW" if ammo < 100 else ""]
	_ammo.add_theme_color_override("font_color", HT.RED if ammo < 100 else Color("d08a4a"))
	var pp := int(f.power_prod)
	var pu := int(f.power_use)
	_power.text = "PWR %d/%d%s" % [pu, pp, " LOW" if pu > pp else ""]
	_power.add_theme_color_override("font_color", HT.RED if pu > pp else HT.YELLOW)
	var pop := int(f.pop)
	var cap := int(f.pop_cap)
	if cap >= 1000000:   # G7 owner 13.9d: Last Protocol has no population cap
		_pop.text = "POP %d (NO CAP)" % pop
		_pop.add_theme_color_override("font_color", HT.BLUE)
	else:
		_pop.text = "POP %d/%d" % [pop, cap]
		_pop.add_theme_color_override("font_color", HT.RED if pop >= cap and cap > 0 else HT.BLUE)
	_stage.text = "STAGE %d" % int(f.stage)
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
	extras.update(w, mv)
	ui6a.update(w, _pf())
	cmd_layer.update(w, _pf())   # G6.1 (PLAN61)
	teams.refresh()              # G6.1 (SQUAD61)
	_cap_stacks()


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
		_insp_wound.set_unit({})
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
		var wcard: bool = e.kind == "unit" and preload("res://presentation/ui7/wound_card.gd").wants(e)  # G7 WOUND7
		_insp_hp.visible = not wcard
		_insp_wound.set_unit(e if wcard else {})
		var info := "HP %d / %d" % [int(e.hp), int(e.max_hp)]
		if e.kind == "unit":
			info += "\n" + _order_text(e)
			info += TeamsPanel.inspector_line(e)  # G6.1 SQUAD61: stance + formation
			for rl in RealismInfo.lines(w, e):  # G6.1 REAL61 CR 60: suppression, fatigue, rank, XP, traits
				info += "\n" + String(rl)
			if own:
				for cl in SimWorld.CommandNet.inspector_lines(w, int(e.id)):  # G6.1 CHAIN61 CR: comms + recent reports
					info += "\n" + String(cl)
				var bl := SimWorld.AmmoBearer.load_line(e)  # G6.1 BEARER61 CR seq 331: "Ammo load 2.4 / 3"
				if bl != "":
					info += "\n" + bl
			if String(e.carry.get("res", "")) != "" and int(e.carry.get("amt", 0)) > 0:
				info += "\nCarrying %d %s" % [int(e.carry.amt), e.carry.res]
		elif e.kind == "building":
			if not bool(e.built):
				info += "\nUNDER CONSTRUCTION  %d%%" % int(float(e.progress) * 100.0)
			else:
				var st := String(e.get("status", ""))
				if st != "":
					info += "\nBlocked: " + _status_text(st)
				if own and Companies.is_hq_def(String(e.def)):
					info += _company_training_lines(w, int(e.id))
				var d := Content.building(e.def)
				if int(d.get("power", 0)) != 0:
					info += "\nPower %+d" % int(d.power)
				if int(d.get("pop_cap", 0)) > 0:
					info += "\nSupply +%d" % int(d.pop_cap)
		elif e.kind == "resource":
			info = "%d remaining" % int(e.amount)
			_insp_hp.visible = false
		_insp_info.text = info
		_append_high_ground(w, ents)
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
		_insp_hp.visible = true
		_insp_wound.set_unit({})
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
		_inspect_company(w, ents)
		_append_high_ground(w, ents)
		_set_card_for(ents[0], ents, w)


## G6 (UI6a, PT6 CR 1193): "HIGH GROUND +10% range, +2 sight" when a selected ground unit stands above
## plain (Elevation.height_at >= 2); the highest unit of the selection gives the bonus. "" otherwise.
## Pure; testable headless.
static func high_ground_line(w: SimWorld, ents: Array) -> String:
	if w == null:
		return ""
	var best = null
	var best_lv := Elevation.PLAIN
	for e in ents:
		if typeof(e) != TYPE_DICTIONARY or String(e.get("kind", "")) != "unit" or not e.has("pos") or Elevation.is_air(e):
			continue
		var lv := Elevation.height_at(w, Vector2i(floori(e.pos.x), floori(e.pos.y)))
		if lv > best_lv:
			best_lv = lv
			best = e
	if best == null or best_lv < 2:
		return ""
	var rm := Elevation.range_mult(w, best, Content.unit(String(best.def)))
	var sb := Elevation.sight_bonus(w, best)
	return "HIGH GROUND (height %d)  +%d%% range, +%d sight" % [best_lv, int(round((rm - 1.0) * 100.0)), int(round(sb))]


func _append_high_ground(w: SimWorld, ents: Array) -> void:
	var hg := high_ground_line(w, ents)
	if hg != "":
		_insp_info.text += "\n" + hg


## G6.1: Company HQ training queue lines for the inspector ("" when nothing trains). Owner bug 2026-10-26:
## companies trained invisibly and could wait forever on the supply cap; now progress and the reason show here.
func _company_training_lines(w: SimWorld, hq_id: int) -> String:
	var rows := Companies.training_of(w, hq_id)
	if rows.is_empty():
		return "\nNo company in training"
	var s := ""
	for r in rows:
		var label := String(r.name)
		if String(r.size) != "":
			label += " (%s)" % String(r.size)
		if bool(r.active):
			if String(r.status) != "":
				s += "\nWaiting to deploy: %s - %s" % [label, _status_text(String(r.status))]
			else:
				s += "\nTraining: %s  %d%%  (%ds)" % [label, int(float(r.progress) * 100.0), int(ceil(float(r.seconds_left)))]
		else:
			s += "\nQueued: %s  (%d supply)" % [label, int(r.pop)]
	return s


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
	_card_pager = null
	_card_page = 0
	g4b_cmd.reset()
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
			_card_buttons.append({"btn": btn, "kind": "build", "def": String(bid), "hk": hk})
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
			_card_buttons.append({"btn": btn, "kind": "train", "item": String(item), "building": bid, "hk": String(p.get("hotkey", ""))})
			_register_hotkey(String(p.get("hotkey", "")), btn)
		if bool(d.get("research", false)):
			_add_research_buttons(bid)
		_add_g6_building_buttons(b, d)
		g4b_cmd.add_building_buttons(b)
	elif mode == "construct":
		var b2: Dictionary = ents[0]
		_card_title.text = "UNDER CONSTRUCTION"
		var btn2 := _card_button("Cancel build", "refund", "", "")
		btn2.pressed.connect(_issue.bind({"type": "cancel_building", "building_id": int(b2.id)}))
		_card_buttons.append({"btn": btn2, "kind": "plain"})
	g2_cmd.compact(_card_grid)
	# G5 (UI5a): one fit routine for every card (replaces the G3a/G3b per-case shrinking)
	_fit_card()


## G6 (UI6a): the research projects this side can see, from Progression.research_list (the sim hides
## other factions' projects), in the G3b card order (for_stage, then content order). Pure; testable headless.
static func research_rows(w: SimWorld, fid: int) -> Array:
	if w == null or not w.factions.has(fid):
		return []
	var vis := {}
	for r in Progression.research_list(w, fid):
		vis[String(r.id)] = r
	var out: Array = []
	for pid in G3bData.project_ids_sorted():
		if vis.has(String(pid)):
			out.append(vis[String(pid)])
			vis.erase(String(pid))
	for pid in vis:   # projects only the sim table lists: after the sorted ones, in content order
		out.append(vis[pid])
	return out


## G3b: research projects on a research building (start; cancel while one is active).
func _add_research_buttons(bid: int) -> void:
	_card_title.text = "RESEARCH   (one project at a time; progress is kept if the building is lost)"
	for p in research_rows(_world(), _pf()):
		var pid := String(p.id)
		var btn := _card_button(String(p.name), "%s  %ds" % [HT.cost_text(p.get("cost", {})), int(p.get("time", 0))], "", "")
		btn.name = "Research_" + String(pid)
		btn.pressed.connect(_issue.bind({"type": "research", "project": String(pid), "building_id": bid}))
		_card_buttons.append({"btn": btn, "kind": "research", "project": String(pid), "building": bid})
	var cancel := _card_button("Cancel research", "full refund", "", "")
	cancel.name = "ResearchCancel"
	cancel.pressed.connect(_issue.bind({"type": "research", "project": "", "cancel": true, "building_id": bid}))
	_card_buttons.append({"btn": cancel, "kind": "research_cancel", "building": bid})


## G6 (UI6a): HQ -> Market; Company HQ -> Army Builder, Train Commander, Forces.
func _add_g6_building_buttons(b: Dictionary, d: Dictionary) -> void:
	if not bool(b.get("built", false)) or int(b.owner) != _pf():
		return
	if bool(d.get("is_hq", false)):
		var mk := _card_button("Market", "buy / sell", "", "")
		mk.name = "G6Market"
		mk.pressed.connect(func(): ui6a.open("market"))
		_card_buttons.append({"btn": mk, "kind": "ui6a", "tip": "Marketplace: buy and sell salvage, ore, fuel and ammo for credits"})
	if Companies.is_hq_def(String(b.def)):
		var ab := _card_button("Army Builder", "companies", "", "")
		ab.name = "G6ArmyBuilder"
		ab.pressed.connect(func(): ui6a.open("army"))
		_card_buttons.append({"btn": ab, "kind": "ui6a", "tip": "Army Builder: train preset or custom companies; edit and save your own templates"})
		var cdef := Companies.leader_def(Companies.faction_of(_world(), _pf()), "commander")
		var cm := _card_button("Commander", HT.cost_text(Companies._leader_cost(cdef, "commander")), "", cdef)
		cm.name = "G6TrainCommander"
		var cmd := {"type": "train_commander", "issuer": _pf(), "building_id": int(b.id)}
		cm.pressed.connect(_issue.bind(cmd))
		_card_buttons.append({"btn": cm, "kind": "ui6a", "cmd": cmd, "tip": "Train a Commander: leads an army of 2-4 companies"})
		var fo := _card_button("Forces", "cards", "", "")
		fo.name = "G6Forces"
		fo.pressed.connect(func(): ui6a.open("forces"))
		_card_buttons.append({"btn": fo, "kind": "ui6a", "tip": "Your armies and companies"})


## G6 (UI6a): when the whole selection is one company, the inspector becomes its card (vision 05):
## name, battle-status line and the unit grid. Returns true when it did.
func _inspect_company(w: SimWorld, ents: Array) -> bool:
	if not w.sys_state.has("companies") or ents.is_empty() or int(ents[0].owner) != _pf():
		return false
	var ids: Array = []
	for e in ents:
		ids.append(int(e.id))
	var c := CompanyCard.selection_company(w, ids)
	if c.is_empty():
		return false
	var cm := CompanyCard.model(w, c)
	_insp_name.text = String(cm.title)
	_insp_hp.max_value = maxf(1.0, float(cm.max_hp))
	_insp_hp.value = float(cm.hp)
	_insp_hp.visible = true
	_insp_wound.set_unit({})
	_insp_info.text = "HP %d / %d\n%s" % [int(cm.hp), int(cm.max_hp), String(cm.status)]
	for ch in _insp_counts.get_children():
		_insp_counts.remove_child(ch)
		ch.queue_free()
	var grid := CompanyCard.unit_grid(cm.units, 24.0)
	# the grid is a flow inside the counts flow: let it take the whole line (it was one icon wide)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_insp_counts.add_child(grid)
	_insp_counts.visible = true
	return true


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
	if g2_cmd.add_page(ids):   # G6.1 (SQUAD61): formation / stance sub-card
		return
	var stop := _card_button("Stop", "", "S", "")
	stop.pressed.connect(_issue.bind({"type": "stop", "unit_ids": ids.duplicate()}))
	_card_buttons.append({"btn": stop, "kind": "plain"})
	var hold := _card_button("Hold", "", "H", "")
	hold.pressed.connect(_issue.bind({"type": "hold", "unit_ids": ids.duplicate()}))
	_card_buttons.append({"btn": hold, "kind": "plain"})
	g2_cmd.add_buttons(mode, ids)
	g4b_cmd.add_buttons(mode, ids)


func _card_button(title: String, cost: String, hotkey: String, icon_id: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(138, 74)
	# G5 (UI5a): the hotkey is a corner badge, not part of the text, so names wrap less
	b.text = title + ("\n" + cost if cost != "" else "")
	if hotkey != "":
		var hk := UiKit.label(hotkey, "small")
		hk.name = "HotkeyBadge"
		hk.add_theme_color_override("font_color", UiKit.AMBER)
		hk.add_theme_constant_override("outline_size", 3)
		hk.add_theme_font_override("font", UiKit.font(true))
		hk.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		hk.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		hk.offset_right = -4.0
		hk.offset_top = 1.0
		b.add_child(hk)
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
		elif kind == "ui6a":
			reason = w.preview_command(rec.cmd) if rec.has("cmd") else ""
			tip = String(rec.get("tip", ""))
		elif kind == "research_cancel":
			reason = "" if String(w.factions[pf].get("research", {}).get("active", "")) != "" else "No project is active."
			tip = "Cancel the active project (full refund; its progress is lost)."
		elif kind == "train":
			reason = G3bData.production_lock(String(rec.item), w.factions[pf], G3.faction_def(w, pf))
			if reason == "":
				reason = w.preview_command({"type": "queue_unit", "issuer": pf, "building_id": int(rec.building), "item": String(rec.item)})
			var p: Dictionary = Content.production(String(rec.item))
			tip = "%s\nCost: %s\nTrain time: %ds" % [p.name, HT.cost_text_long(p.cost), int(p.train_time)]
		var hk := String(rec.get("hk", ""))
		if hk != "" and tip != "":
			var nl := tip.find("
")
			tip = (tip + "   [Hotkey %s]" % hk) if nl < 0 else tip.substr(0, nl) + "   [Hotkey %s]" % hk + tip.substr(nl)
		rec["reason"] = reason
		btn.disabled = reason != ""
		if reason != "":
			tip += "\nUnavailable: " + reason
		btn.tooltip_text = tip
	if mode == "engineer" or mode == "units":
		g2_cmd.update_state(w)
	g4b_cmd.update_state(w)
	if _hover_btn != null:
		for rec in _card_buttons:
			if rec.btn == _hover_btn and String(rec.get("reason", "")) != "":
				hint = String(rec.reason)
	if hint == "":
		hint = g2_cmd.hint()
	if hint == "":
		hint = g4b_cmd.hint()
	if hint == "" and mode == "building":
		var st := String(ents[0].get("status", ""))
		if st != "":
			hint = "Production blocked: " + _status_text(st)
	if _hint.text != hint:
		_hint.text = hint
		_hint.visible = hint != ""   # an empty label still takes a line
		_fit_card()
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
		_queue_box.visible = false
		return
	var q: Array = b.queue
	var bid: int = int(b.id)
	for i in q.size():
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(84, 24)
		var p: Dictionary = Content.production(String(q[i].item))
		var qn := String(p.get("name", q[i].item)).get_slice(" (", 0)
		btn.text = "%s %s" % [">" if i == 0 else "#%d" % (i + 1), qn if qn.length() <= 11 else qn.substr(0, 10) + "."]
		btn.add_theme_font_size_override("font_size", 12)
		btn.tooltip_text = "%s
Click to cancel (full refund)" % qn
		btn.pressed.connect(_issue.bind({"type": "cancel_unit", "building_id": bid, "index": i}))
		vb.add_child(btn)
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(84, 6)
		pb.max_value = 1.0
		pb.show_percentage = false
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(pb)
		_queue_box.add_child(vb)
		_queue_bars.append(pb)
	_queue_box.visible = _queue_box.get_child_count() > 0
	_fit_card()


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
	if extras.on_key(k):
		get_viewport().set_input_as_handled()
		return
	if ops7 != null and ops7.on_key(k):   # G7 OPSUI7 CR 1401: ops room toggle (F4) / Esc closes
		get_viewport().set_input_as_handled()
		return
	if teams.on_key(k) or cmd_layer.on_key(k):   # G6.1 (SQUAD61 Teams F2 / PLAN61 command mode)
		get_viewport().set_input_as_handled()
		return
	if ui6a.on_key(k):   # G6 (UI6a): Esc closes an open G6 panel first
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_P:
		_set_paused(not bool(mv.get("paused")))
		get_viewport().set_input_as_handled()
		return
	var key: String = preload("res://presentation/ui5/panels/hotkeys.gd").event_key(k, _hotkeys)  # G7 SQUAD7 CR seq 249: Shift chords (casualty keys)
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
			l.visible = true
		else:
			l.text = ""
			l.visible = false


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
			"CompanyQueued":
				if int(ev.get("owner", -1)) == pf:
					_push_alert("Company training started at the Company HQ (select it to see progress)", HT.GREEN, _ev_pos(w, ev))
			"CompanyTrained":
				if int(ev.get("owner", -1)) == pf:
					_push_alert("Company ready: %d troops deployed at the Company HQ" % (ev.get("unit_ids", []) as Array).size(), HT.GREEN, _ev_pos(w, ev))
			"CommanderTrained":
				if int(ev.get("owner", -1)) == pf:
					_push_alert("Commander ready at the Company HQ", HT.GREEN, _ev_pos(w, ev))
			"CompanyTrainingBlocked":
				if int(ev.get("owner", -1)) == pf:
					_push_alert("Company trained but waiting to deploy: %s" % _status_text(String(ev.get("reason", ""))), HT.YELLOW, _ev_pos(w, ev))
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
			"NetworkAdapted":  # G7 CREEP7: the Machine learned a new reaction
				_push_alert("THE NETWORK HAS ADAPTED", HT.RED)
			_:
				if G4bAlerts.on_event(self, w, pf, ev):
					pass  # G4b mechanics alerts (UI4B)
				elif not g3b_stage.on_event(w, pf, ev):
					g2_alerts.on_event(self, w, pf, ev)


func _ev_pos(w: SimWorld, ev: Dictionary) -> Variant:
	if ev.has("pos"):
		return ev.pos
	for k in ["building_id", "id"]:
		if ev.has(k) and w.entities.has(int(ev[k])):
			return w.entities[int(ev[k])].pos
	return null
