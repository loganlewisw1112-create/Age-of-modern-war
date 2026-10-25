extends RefCounted
## G5 (UI5b) build-card category pages. hud.gd adds one build button per buildable def with a
## page-local hotkey (G3.build_hotkey); apply() then keeps only the current page's buttons, re-binds
## their hotkeys and shows a tab strip in the card title row (click a tab, or Tab = next page).
## Owned by G4bCommands (`pages`); the current page survives card rebuilds.

const G3 = preload("res://presentation/hud/g3_faction.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")

var hud
var page := ""                 # current BUILD_CATS id ("" = first non-empty)
var tabs: Dictionary = {}      # cat -> Button (current card)
var _bar: HBoxContainer = null
var _cats: Array = []


func hide_bar() -> void:
	if _bar != null and is_instance_valid(_bar):
		_bar.visible = false
	if hud != null and hud._card_title != null:
		hud._card_title.custom_minimum_size.y = 0.0
	tabs.clear()


## Called by G4bCommands.add_buttons for the engineer card (after hud added every build button).
func apply(h) -> void:
	hud = h
	var pages: Array = G3.build_pages(G3.faction_def(hud._world(), hud._pf()))
	if pages.is_empty():
		hide_bar()
		return
	_cats = []
	for p in pages:
		_cats.append(String(p.cat))
	if not _cats.has(page):
		page = String(_cats[0])
	var keep: Array = []
	for rec in (hud._card_buttons as Array).duplicate():
		if String(rec.kind) != "build":
			continue
		if G3.build_category(String(rec.def)) == page:
			keep.append(rec)
			continue
		hud._card_buttons.erase(rec)
		var hk := String(rec.get("hk", "")).to_upper()
		if hud._hotkeys.get(hk) == rec.btn:
			hud._hotkeys.erase(hk)
		var b: Button = rec.btn
		if b.get_parent() != null:
			b.get_parent().remove_child(b)
		b.queue_free()
	for rec in keep:
		hud._register_hotkey(String(rec.get("hk", "")), rec.btn)
	_show_bar(pages)
	hud._card_title.text = "BUILD  %s" % String(G3.BUILD_CAT_NAMES.get(page, page)).to_upper()
	hud._card_title.tooltip_text = "Click a structure, then click the map to place it. Tab: next category."


func _show_bar(pages: Array) -> void:
	var title: Label = hud._card_title
	if _bar == null or not is_instance_valid(_bar):
		_bar = HBoxContainer.new()
		_bar.name = "BuildTabs"
		_bar.add_theme_constant_override("separation", 3)
		_bar.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_bar.alignment = BoxContainer.ALIGNMENT_END
		title.add_child(_bar)
	for c in _bar.get_children():
		_bar.remove_child(c)
		c.queue_free()
	tabs.clear()
	_bar.visible = true
	title.custom_minimum_size.y = 24.0
	for p in pages:
		var cat := String(p.cat)
		var b := Button.new()
		b.name = "BuildTab_" + cat
		b.text = "%s %d" % [String(p.name), (p.defs as Array).size()]
		b.toggle_mode = true
		b.button_pressed = cat == page
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 22)
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = UiKit.tooltip("%s structures" % String(p.name), "Tab", {}, "Tab cycles the build categories.")
		b.pressed.connect(select.bind(cat))
		_bar.add_child(b)
		tabs[cat] = b
	# Tab = next category: bound to the next tab's button so the HUD's hotkey path presses it
	var nxt := String(_cats[(_cats.find(page) + 1) % _cats.size()])
	hud._register_hotkey("Tab", tabs[nxt])


## Switch page and rebuild the card (next HUD refresh, or now when the world is readable).
func select(cat: String) -> void:
	if not _cats.has(cat):
		return
	page = cat
	hud._card_sig = ""
	var mv = hud.mv
	if mv == null or not mv.has_method("sim_busy") or not mv.sim_busy():
		hud._refresh()


func next_page() -> void:
	if _cats.is_empty():
		return
	select(String(_cats[(_cats.find(page) + 1) % _cats.size()]))
