extends RefCounted
## G7 CARDBAR8 (docs/G7_REFERENCE.md 13.9c-51): the facility building cards (13.9c-48 command centre, defences, magazine,
## armory, garages, barracks, air pads, aid station, lab, plus the barracks reserve 13.9c-34 and the drone bay 13.9c-27)
## live in the bottom bar's command card, with tabs. Presentation only: the cards keep every rule they had (selection,
## sim reason functions, MatchView.issue, their own hotkeys); this host only moves where their parts show.
##   * Buttons: every card button is taken out of its card once (kept in a hidden stash). While a card is shown, the
##     active tab's buttons are moved into hud._card_grid (kind "fac" records: the existing fit + "More" page arrow
##     handle overflow); on a card rebuild they go back to the stash. Tabs come from card.bar_tabs() ->
##     [[TAB NAME, [Button, ...]], ...] (live: e.g. one RECALL / CANCEL pair per running mission).
##   * Tabs: a tab strip in the card title row (the build_pages pattern): click a tab, or Tab / Shift+Tab cycle them.
##     When the selected building also has its regular card buttons (train, garrison, ...), they keep working on
##     every tab (hotkeys) and show on their own last tab.
##   * Read-outs: the card itself (now holding only its live lines: mission rows + progress, ammo + cooldowns, stock,
##     rosters, casualty board, ...) is the info strip just above the bottom bar, centred like the airfield panel.
##     card.bar_hide() names nodes that only made sense in the old left-stack layout (section headers).

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")

const STRIP_W := 520.0
const FlowBar = preload("res://presentation/ui71/flow_bar.gd")   # G7.1 FLOW71: one-click send / auto / packages bar

var hud
var strip: VBoxContainer          # parent of every card (info strip above the bottom bar)
var stash: Control                # hidden: the card buttons not on screen
var cards: Array = []             # attached cards, in hud order
var tab_of_key := {}              # card-set key -> active tab name
var tabs: Array = []              # current [[name, [Button...]]] ("" buttons list = the regular card tab)
var tab_btns: Array = []          # current tab Buttons (strip in the title row)
var cur := ""                     # active tab name
var _key := ""
var _bar: HBoxContainer = null
var _shown: Array = []            # [Button, ...] fac buttons now in the grid
var _regular: Array = []          # regular card buttons hidden while a card tab is open
var _home := {}                   # Button -> card (to find it again)
var flow_bar: Control = null      # G7.1 FLOW71: always the last child of the strip (right above the bottom bar)


func build(h, root: Control) -> void:
	hud = h
	strip = VBoxContainer.new()
	strip.name = "FacCardStrip"
	strip.add_theme_constant_override("separation", 4)
	strip.anchor_left = 0.5
	strip.anchor_right = 0.5
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)
	stash = Control.new()
	stash.name = "FacCardStash"
	stash.visible = false
	stash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stash)
	flow_bar = FlowBar.attach(h, strip)


## hud._build_ui: attach a card script into the strip (replaces `.attach(self, left)`).
func attach(script: GDScript) -> Control:
	var before := strip.get_child_count()
	var first: Control = script.attach(hud, strip)
	for i in range(before, strip.get_child_count()):   # building_card8c attaches four cards (barracks, air, aid, lab)
		var c: Control = strip.get_child(i)
		cards.append(c)
		if c.is_node_ready():
			bind(c)
		else:
			c.ready.connect(bind.bind(c), CONNECT_ONE_SHOT)
	if flow_bar != null and is_instance_valid(flow_bar):
		strip.move_child(flow_bar, -1)
	return first


## One hidden holder per card: buttons keep their own names (two cards share names like RepairButton / RecallButton,
## and a shared parent would rename the later one).
func _stash_of(c) -> Node:
	var nm := "Stash_" + (String(c.name) if c != null and is_instance_valid(c) else "x")
	var n := stash.get_node_or_null(nm)
	if n == null:
		n = Control.new()
		n.name = nm
		stash.add_child(n)
	return n


## Takes every button out of the card (into the stash) and hides the old section headers.
func bind(c: Control) -> void:
	if c.has_meta("cb8_bound"):
		return
	c.set_meta("cb8_bound", true)
	c.custom_minimum_size.x = 0.0
	for b in c.find_children("*", "Button", true, false):
		var btn := b as Button
		btn.get_parent().remove_child(btn)
		_stash_of(c).add_child(btn)
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = false
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.size_flags_horizontal = Control.SIZE_FILL
		_home[btn] = c
	if c.has_method("bar_hide"):
		for n in c.bar_hide():
			if n is CanvasItem:
				(n as CanvasItem).visible = false


func active() -> Array:
	var out: Array = []
	for c in cards:
		if is_instance_valid(c) and c.visible and c.has_meta("cb8_bound") and c.has_method("bar_tabs"):
			out.append(c)
	return out


## Card-set signature for hud._set_card ("" = no facility card: the regular command card).
func sig(mode: String) -> String:
	if mode == "engineer" or mode == "units" or mode == "construct":
		return ""
	var act := active()
	if act.is_empty():
		return ""
	var parts: Array = []
	for c in act:
		parts.append(String(c.name))
		for t in c.bar_tabs():
			parts.append("%s=%d" % [String(t[0]), (t[1] as Array).size()])
	return "|fac:" + ",".join(PackedStringArray(parts)) + "@" + String(tab_of_key.get(_set_key(act), ""))


func _set_key(act: Array) -> String:
	var n: Array = []
	for c in act:
		n.append(String(c.name))
	return ",".join(PackedStringArray(n))


func card_of(btn: Button) -> Control:
	return _home.get(btn)


## hud._clear_card: put the shown card buttons back in the stash before the grid is emptied.
func release() -> void:
	for b in _shown:
		if is_instance_valid(b):
			if b.get_parent() != null:
				b.get_parent().remove_child(b)
			_stash_of(_home.get(b)).add_child(b)
	_shown.clear()
	_regular.clear()
	tabs.clear()
	tab_btns.clear()
	cur = ""
	if _bar != null and is_instance_valid(_bar):
		_bar.visible = false
		if hud != null and hud._card_title != null:
			hud._card_title.custom_minimum_size.y = 0.0


## hud._rebuild_card (after the regular buttons were added): shows the facility cards' tabs when any card is up.
func apply(mode: String) -> void:
	if sig(mode) == "":
		return
	var act := active()
	_key = _set_key(act)
	tabs = []
	for c in act:
		for t in c.bar_tabs():
			tabs.append([String(t[0]), (t[1] as Array).duplicate()])
	var reg: Array = []
	for c in hud._card_grid.get_children():
		if c is Button and (c as Button).visible:
			reg.append(c)
	var reg_name := String(hud._card_title.text)
	if reg_name == "":
		reg_name = "BUILDING"
	for t in tabs:   # a card tab of the same name (barracks TRAIN drills vs the regular TRAIN card) would hide this tab
		if String(t[0]) == reg_name:
			reg_name = "UNITS" if reg_name == "TRAIN" else "BUILDING"
	if not reg.is_empty():
		tabs.append([reg_name, []])
	if tabs.is_empty():
		return
	cur = String(tab_of_key.get(_key, ""))
	var names: Array = []
	for t in tabs:
		names.append(String(t[0]))
	if not names.has(cur):
		cur = String(names[0])
	var i := names.find(cur)
	var is_reg := not reg.is_empty() and i == tabs.size() - 1
	if not is_reg:
		for b in reg:
			(b as Button).visible = false
			_regular.append(b)
		for b in tabs[i][1]:
			var btn := b as Button
			if not is_instance_valid(btn):
				continue
			if btn.get_parent() != null:
				btn.get_parent().remove_child(btn)
			hud._card_grid.add_child(btn)
			btn.visible = true
			_shown.append(btn)
			hud._card_buttons.append({"btn": btn, "kind": "fac", "tab": cur})
	var title := String((act[0] as Node).name)
	if act[0].has_method("bar_title"):
		title = String(act[0].bar_title())
	hud._card_title.text = title
	hud._card_title.tooltip_text = "Facility building options. Click a tab, or Tab / Shift+Tab to cycle the tabs."
	_show_bar(names, i)


func _show_bar(names: Array, i: int) -> void:
	var title: Label = hud._card_title
	if _bar == null or not is_instance_valid(_bar):
		_bar = HBoxContainer.new()
		_bar.name = "FacCardTabs"
		_bar.add_theme_constant_override("separation", 3)
		_bar.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_bar.alignment = BoxContainer.ALIGNMENT_END
		title.add_child(_bar)
	for c in _bar.get_children():
		_bar.remove_child(c)
		c.queue_free()
	tab_btns.clear()
	_bar.visible = true
	title.custom_minimum_size.y = 24.0
	var fs := 12 if names.size() <= 4 else 11
	for k in names.size():
		var nm := String(names[k])
		var b := Button.new()
		b.name = "FacTab_" + nm.replace(" ", "_").replace("/", "_").replace("&", "and")
		b.text = nm
		b.toggle_mode = true
		b.button_pressed = k == i
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 22)
		b.add_theme_font_size_override("font_size", fs)
		b.tooltip_text = UiKit.tooltip(nm, "Tab", {}, "Tab / Shift+Tab cycle this building's tabs.")
		b.pressed.connect(select.bind(nm))
		_bar.add_child(b)
		tab_btns.append(b)
	# Tab = next tab, Shift+Tab = previous (bound to those tab buttons, the HUD's hotkey path presses them)
	if names.size() > 1:
		hud._register_hotkey("Tab", tab_btns[(i + 1) % names.size()])
		hud._register_hotkey("SHIFT+TAB", tab_btns[(i - 1 + names.size()) % names.size()])


## hud._fit_card: regular card buttons hidden while a card tab is open take no page slot (else a barracks' many TRAIN
## buttons pushed the open tab's buttons onto page 2 behind "More", and the tab looked empty).
func hides(b) -> bool:
	return _regular.has(b)


## hud._update_card_state end: keep the regular buttons hidden on a card tab (their own update may show them).
func post_update() -> void:
	for b in _regular:
		if is_instance_valid(b):
			(b as Button).visible = false


## Refusal text of a shown card button (its tooltip's "Unavailable:" part, else the tooltip).
static func reason_of(b: Button) -> String:
	if not b.disabled:
		return ""
	var t := b.tooltip_text
	var k := t.find("Unavailable: ")
	return t.substr(k + 13) if k >= 0 else t


## Switch tab (a click on a tab, Tab / Shift+Tab, or a playtest flow).
func select(nm: String) -> void:
	if _key == "":
		return
	tab_of_key[_key] = nm
	hud._card_sig = ""
	var mv = hud.mv
	if mv == null or not mv.has_method("sim_busy") or not mv.sim_busy():
		hud._refresh()


## Tab name that holds the card button named btn_name right now ("" = none).
func tab_for(card: Control, btn_name: String) -> String:
	if card == null or not card.has_method("bar_tabs"):
		return ""
	for t in card.bar_tabs():
		for b in t[1]:
			if is_instance_valid(b) and String((b as Node).name) == btn_name:
				return String(t[0])
	return ""


## The card's button (or any node) named nm, wherever it is now (card, stash or command grid).
func find(card: Control, nm: String) -> Node:
	if card == null:
		return null
	var n := card.find_child(nm, true, false)
	if n != null:
		return n
	for b in _home:
		if is_instance_valid(b) and _home[b] == card and String((b as Node).name) == nm:
			return b
	return null


## The tab strip's button for tab nm (null when not shown).
func tab_button(nm: String) -> Button:
	for b in tab_btns:
		if is_instance_valid(b) and (b as Button).text == nm:
			return b
	return null


## Info strip: just above the bottom panel's real top, centred between the side stacks (airfield panel rule). When it
## would touch another HUD frame there (small canvas, big UI scale, the PAUSED banner, the side stacks) the strip moves
## into the bottom bar's middle section instead (the inspector by the portrait, which scrolls).
func place() -> void:
	if strip == null or hud == null:
		return
	var root: Control = hud.layer.root if hud.get("layer") != null else null
	if root == null:
		return
	var showing := false
	for c in cards:
		if is_instance_valid(c) and c.visible:
			showing = true
	if flow_bar != null and is_instance_valid(flow_bar) and flow_bar.visible:
		showing = true
	var cw: float = root.size.x if root.size.x > 0.0 else 1600.0
	var rw = hud.get("RIGHT_W")
	var side: float = (float(rw) if rw != null else 306.0) + 20.0
	var wdt := clampf(cw - 2.0 * side, 300.0, STRIP_W)
	var bot := 226.0
	var bp = root.get_node_or_null("BottomPanel")
	if bp != null:
		bot = maxf(bot, (bp as Control).size.y + 6.0)
	for nm in ["GaragePanel", "AirfieldPanel"]:   # other panels that sit right above the bar: stack on top of them
		var pn = root.get_node_or_null(nm)
		if pn != null and (pn as Control).visible and (pn as Control).size.y > 0.0:
			bot = maxf(bot, root.size.y - (pn as Control).position.y + 6.0)
	var h := 0.0
	for c in cards + ([flow_bar] if flow_bar != null else []):
		if is_instance_valid(c) and c.visible:
			h += (c as Control).get_combined_minimum_size().y + 4.0
	var rect := Rect2(cw * 0.5 - wdt * 0.5, root.size.y - bot - h, wdt, h)
	var above := showing and rect.position.y > 0.0 and not _hits(root, rect.grow(2.0))
	var insp: Control = hud._insp_info.get_parent() if hud.get("_insp_info") != null else null
	if above or insp == null:
		if strip.get_parent() != root:
			strip.get_parent().remove_child(strip)
			root.add_child(strip)
			strip.anchor_left = 0.5
			strip.anchor_right = 0.5
			strip.anchor_top = 1.0
			strip.anchor_bottom = 1.0
		strip.offset_left = -wdt * 0.5
		strip.offset_right = wdt * 0.5
		strip.offset_bottom = -bot
		strip.reset_size()
		strip.offset_left = -wdt * 0.5
		strip.offset_right = wdt * 0.5
		strip.offset_top = -bot - strip.get_combined_minimum_size().y
	elif strip.get_parent() != insp:
		strip.get_parent().remove_child(strip)
		insp.add_child(strip)
		strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## True when r touches a visible HUD frame on the root (side stacks, top bar, banners, buttons; not full-screen layers).
func _hits(root: Control, r: Rect2) -> bool:
	var area := root.size.x * root.size.y
	for n in root.get_children():
		if n == strip or n == stash or not (n is Control):
			continue
		var c := n as Control
		if not c.visible or String(c.name) == "BottomPanel":
			continue
		var cr := c.get_global_rect()
		if cr.size.x < 1.0 or cr.size.y < 1.0 or cr.size.x * cr.size.y > area * 0.5:
			continue
		var gr := Rect2(root.get_global_transform() * r.position, r.size * root.get_global_transform().get_scale())
		if cr.intersects(gr):
			return true
	return false


# ---------------------------------------------------------------- fit screens (tools/ui_fit_test.gd via fit_screens.gd)
## screen -> [MatchView part ("" = select an entity), entity kind ("tower" / "magazine" / "armory" / ""), tab to open]
const FIT := {"ui8_bar_ops": ["command", "", "FIRE SUPPORT"], "ui8_bar_def": ["", "tower", "FIRE MODE"],
	"ui8_bar_gate": ["gate_outer", "", "GATE"], "ui8_bar_supply": ["", "magazine", "AMMO MIX"],
	"ui8_bar_armory": ["", "armory", "SUITS"], "ui8_bar_garage": ["garage", "", "CONVOY"],
	"ui8_bar_dronebay": ["drone_bay", "", "GARRISON"], "ui8_bar_barracks": ["barracks", "", "WATCH"],
	"ui8_bar_air": ["air", "", "LAUNCH"], "ui8_bar_aid": ["aid", "", "CASUALTIES"], "ui8_bar_lab": ["lab", "", "RESEARCH"]}
const FIT_NAMES := ["ui8_bar_ops", "ui8_bar_def", "ui8_bar_gate", "ui8_bar_supply", "ui8_bar_armory", "ui8_bar_garage",
	"ui8_bar_dronebay", "ui8_bar_barracks", "ui8_bar_air", "ui8_bar_aid", "ui8_bar_lab"]

static var _fit_w = null      # [world, facility id]: built once, never stepped after (the HUD is paused)


## A default match with the player's counter-nanite facility raised on a cleared site (test_cards8a setup).
static func fit_world() -> Array:
	if _fit_w != null:
		return _fit_w
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w := SimWorld.new_match(SimWorld.default_config())
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(60, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	SimWorld.Movement.rebuild_nav(w)
	var off: Array = SimWorld.CnFacility.conf().core_offset
	var fid := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	for i in 80:
		w.step()
	_fit_w = [w, fid]
	return _fit_w


static func _fit_entity(w: SimWorld, kind: String) -> int:
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if int(e.owner) != 0 or e.kind != "building":
			continue
		var d := String(e.def)
		if kind == "tower" and preload("res://sim/systems/cards8a.gd").is_defence(e):
			return int(id)
		if kind == "magazine" and d == "cn_magazine":
			return int(id)
		if kind == "armory" and d == "cn_armory":
			return int(id)
	return -1


## Async: builds the skirmish HUD over the facility world with one facility building selected and one tab open.
static func fit_build(nm: String, vp: SubViewport, sc: float, tree: SceneTree) -> bool:
	if not FIT.has(nm):
		return false
	var fw := fit_world()
	var w: SimWorld = fw[0]
	var mv = load("res://presentation/match_view.gd").new()
	mv.world = w
	mv.paused = true
	vp.add_child(mv)
	var hud = load("res://presentation/hud/hud.gd").new()
	vp.add_child(hud)
	hud.setup(mv, sc)
	await tree.process_frame
	var spec: Array = FIT[nm]
	if String(spec[0]) != "":
		mv.select_ids([int(fw[1])], String(spec[0]))
	else:
		var id := _fit_entity(w, String(spec[1]))
		if id < 0:
			return false
		mv.select_ids([id])
	for c in hud.cardbar.cards:
		c.refresh()
	hud._refresh()
	await tree.process_frame
	hud.cardbar.select(String(spec[2]))
	await tree.process_frame
	hud._refresh()
	return not hud.cardbar.active().is_empty()
