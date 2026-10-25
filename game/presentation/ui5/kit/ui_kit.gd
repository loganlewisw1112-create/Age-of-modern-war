extends RefCounted
## UI5a (G5) panel kit and theme. Use with `const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")`.
## API (CONTRACTS_G5 section 5, fact ui5.kit_ready):
##   UiKit.make_theme(accent := AMBER) -> Theme       military theme, faction accent on hover/selected
##   UiKit.panel(kind := "frame") -> PanelContainer   kinds: frame, plate, inset, header, modal, card
##   UiKit.button(text, hotkey := "", tooltip := "") -> Button   shows "[H] text"; tooltip carries the hotkey
##   UiKit.icon_button(icon, hotkey := "", tooltip := "", text := "") -> Button   hotkey badge in a corner
##   UiKit.label(text, role := "body") -> Label        roles: title, header, body, small, number, dim, warn, good
##   UiKit.bar(kind := "hp") -> ProgressBar            kinds: hp, ammo, fuel, drone, build, power
##   UiKit.tooltip(title, hotkey := "", cost := {}, body := "") -> String
##   UiKit.accent(faction_id) -> Color                 human_a / human_b / machine accents
##   UiKit.fit_register(control, modal := false) -> Control   marks a top-level frame for tools/ui_fit_test.gd
##   UiKit.font(bold := false) -> Font                 placeholder until FONT posts font.final
##   UiKit.scroll(child, max_h := 0.0) -> ScrollContainer   long lists scroll instead of clipping
## Theme type variations usable by name: PlatePanel, InsetPanel, HeaderPanel, ModalPanel, CardPanel,
## CardButton, HeaderLabel, TitleLabel, DimLabel, SmallLabel, NumberLabel, HpBar, AmmoBar, FuelBar, DroneBar,
## BuildBar, PowerBar. Constants: colours below, FS_* font sizes, GAP, PAD, BTN_H, ICON_BTN.

const MilBox = preload("res://presentation/ui5/kit/mil_box.gd")

const BG := Color("0f1315")
const PANEL := Color("1b2226")
const PANEL_HI := Color("263036")
const PLATE := Color("2b353b")
const INSET := Color("0c1012")
const EDGE := Color("4a565c")
const EDGE_LO := Color("30393e")
const AMBER := Color("e3a83a")
const OLIVE := Color("8fa24e")
const TEXT := Color("dcdfd2")
const DIM := Color("8e9893")
const RED := Color("e0605a")
const GREEN := Color("86c85e")
const BLUE := Color("6fa8dc")
const YELLOW := Color("e8d25a")
const CYAN := Color("4fc3d9")
const DISABLED_TEXT := Color("68716d")

const ACCENTS := {"human_a": Color("e3a83a"), "human_b": Color("d0603e"), "machine": Color("4fc3d9")}
const BAR_COLS := {"hp": Color("86c85e"), "ammo": Color("d08a4a"), "fuel": Color("d9c05a"),
	"drone": Color("4fc3d9"), "build": Color("8fa24e"), "power": Color("e8d25a")}

const FS_TITLE := 30
const FS_HEADER := 16
const FS_BODY := 15
const FS_SMALL := 13
const FS_NUMBER := 16
const GAP := 6
const PAD := 8.0
const BTN_H := 30.0
const ICON_BTN := Vector2(44, 44)

## Flip to true once FONT posts font.final (owner-approved specimen); until then a system
## placeholder (Bahnschrift, a DIN-style face shipped with Windows) stands in.
const USE_FINAL_FONT := true  # owner approved RTS Mil 2026-10-24
const FONT_REGULAR := "res://assets/fonts/rts_mil_regular.ttf"
const FONT_BOLD := "res://assets/fonts/rts_mil_bold.ttf"

static var _fonts: Dictionary = {}
static var preview_final := false   # tools/ui_fit_test.gd --fit-font=final: measure with FONT's TTFs before approval


static func font(bold: bool = false) -> Font:
	var key := "b" if bold else "r"
	if _fonts.has(key):
		return _fonts[key]
	var f: Font = null
	var path := FONT_BOLD if bold else FONT_REGULAR
	if USE_FINAL_FONT or preview_final:
		if ResourceLoader.exists(path):
			f = load(path)
		elif FileAccess.file_exists(path):
			# not imported yet (no .import file): read the TTF directly
			var ff := FontFile.new()
			if ff.load_dynamic_font(path) == OK:
				ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
				ff.take_over_path(path)
				f = ff
	if f == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Liberation Sans", "sans-serif"])
		sf.font_weight = 700 if bold else 400
		sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f = sf
	_fonts[key] = f
	return f


static func accent(faction_id: String) -> Color:
	return ACCENTS.get(faction_id, AMBER)


## A MilBox plate. kind: frame (rivets, accent stripe), plate, inset, header, modal, card, button states.
static func box(kind: String, acc: Color = AMBER) -> StyleBox:
	var s = MilBox.make(PANEL, EDGE, 6.0, PAD)
	match kind:
		"frame":
			s.rivets = true
			s.stripe = 2
			s.accent = acc.darkened(0.15)
			s.shade = 0.25
			s.content_margin_top = PAD + 2.0
		"plate":
			s.fill = PLATE
			s.shade = 0.2
		"inset":
			s.fill = INSET
			s.edge = EDGE_LO
			s.bevel = false
			s.chamfer = 3.0
			s.set_content_margin_all(5.0)
		"header":
			s.fill = Color("12171a")
			s.edge = EDGE_LO
			s.stripe = 2
			s.accent = acc.darkened(0.25)
			s.chamfer = 0.0
		"modal":
			s.fill = Color("161c1f")
			s.edge = acc.darkened(0.2)
			s.edge_w = 2.0
			s.rivets = true
			s.stripe = 3
			s.accent = acc
			s.shade = 0.3
			s.chamfer = 10.0
			s.set_content_margin_all(16.0)
		"card":
			s.fill = PANEL_HI
			s.chamfer = 4.0
		"btn":
			s.fill = PLATE
			s.chamfer = 4.0
			s.shade = 0.25
		"btn_hover":
			s.fill = PLATE.lightened(0.1)
			s.edge = acc
			s.chamfer = 4.0
			s.shade = 0.25
		"btn_pressed":
			s.fill = acc.darkened(0.62)
			s.edge = acc
			s.edge_w = 2.0
			s.stripe = 2
			s.accent = acc
			s.chamfer = 4.0
		"btn_disabled":
			s.fill = Color("161b1e")
			s.edge = Color("2a3236")
			s.bevel = false
			s.chamfer = 4.0
		"btn_focus":
			s.fill = Color(0, 0, 0, 0)
			s.edge = acc.lightened(0.2)
			s.bevel = false
			s.chamfer = 4.0
	if kind.begins_with("btn"):
		s.content_margin_left = 8.0
		s.content_margin_right = 8.0
		s.content_margin_top = 4.0
		s.content_margin_bottom = 4.0
	return s


static func flat(bg: Color, border: Color, bw: int = 1, margin: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_content_margin_all(margin)
	return sb


static func make_theme(acc: Color = AMBER) -> Theme:
	var t := Theme.new()
	t.default_font = font(false)
	t.default_font_size = FS_BODY
	var bold := font(true)
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", FS_BODY)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	for v in [["HeaderLabel", FS_HEADER, acc, true], ["TitleLabel", FS_TITLE, acc, true], ["DimLabel", FS_SMALL, DIM, false],
			["SmallLabel", FS_SMALL, TEXT, false], ["NumberLabel", FS_NUMBER, TEXT, true]]:
		t.set_type_variation(v[0], "Label")
		t.set_font_size("font_size", v[0], v[1])
		t.set_color("font_color", v[0], v[2])
		if v[3]:
			t.set_font("font", v[0], bold)
	# panels
	t.set_stylebox("panel", "PanelContainer", box("frame", acc))
	t.set_stylebox("panel", "Panel", box("frame", acc))
	for v in [["PlatePanel", "plate"], ["InsetPanel", "inset"], ["HeaderPanel", "header"], ["ModalPanel", "modal"], ["CardPanel", "card"]]:
		t.set_type_variation(v[0], "PanelContainer")
		t.set_stylebox("panel", v[0], box(v[1], acc))
	# buttons: hover / selected / disabled states read clearly at a glance
	for tn in ["Button", "OptionButton", "MenuButton", "CardButton"]:
		t.set_stylebox("normal", tn, box("btn", acc))
		t.set_stylebox("hover", tn, box("btn_hover", acc))
		t.set_stylebox("pressed", tn, box("btn_pressed", acc))
		t.set_stylebox("hover_pressed", tn, box("btn_pressed", acc.lightened(0.15)))
		t.set_stylebox("disabled", tn, box("btn_disabled", acc))
		t.set_stylebox("focus", tn, box("btn_focus", acc))
		t.set_color("font_color", tn, TEXT)
		t.set_color("font_hover_color", tn, Color.WHITE)
		t.set_color("font_pressed_color", tn, acc.lightened(0.25))
		t.set_color("font_hover_pressed_color", tn, Color.WHITE)
		t.set_color("font_focus_color", tn, TEXT)
		t.set_color("font_disabled_color", tn, DISABLED_TEXT)
		t.set_color("icon_disabled_color", tn, Color(1, 1, 1, 0.35))
		t.set_font_size("font_size", tn, FS_BODY)
	t.set_type_variation("CardButton", "Button")
	t.set_font_size("font_size", "CardButton", FS_SMALL + 1)
	for tn in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", tn, TEXT)
		t.set_color("font_hover_color", tn, Color.WHITE)
		t.set_color("font_pressed_color", tn, acc)
	# text entry
	for tn in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", tn, box("inset", acc))
		var fo = box("inset", acc)
		fo.edge = acc
		t.set_stylebox("focus", tn, fo)
		t.set_stylebox("read_only", tn, box("inset", acc))
		t.set_color("font_color", tn, TEXT)
		t.set_color("caret_color", tn, acc)
		t.set_color("selection_color", tn, Color(acc, 0.35))
	# popups and tooltips
	var pm = box("plate", acc)
	pm.edge = acc.darkened(0.2)
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", flat(Color(acc, 0.28), Color(0, 0, 0, 0), 0, 4.0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", Color("5d6661"))
	var tp = box("inset", acc)
	tp.fill = Color("0b0e10")
	tp.edge = acc
	tp.set_content_margin_all(7.0)
	t.set_stylebox("panel", "TooltipPanel", tp)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", FS_SMALL + 1)
	# bars: dark inset trough, coloured fill with a light top edge
	t.set_stylebox("background", "ProgressBar", flat(INSET, EDGE_LO, 1))
	t.set_stylebox("fill", "ProgressBar", _bar_fill(OLIVE))
	t.set_color("font_color", "ProgressBar", Color.WHITE)
	t.set_font_size("font_size", "ProgressBar", 12)
	for k in BAR_COLS:
		var vn := String(k).capitalize() + "Bar"
		t.set_type_variation(vn, "ProgressBar")
		t.set_stylebox("fill", vn, _bar_fill(BAR_COLS[k]))
	# scrolling and tabs
	for tn in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", tn, flat(INSET, Color(0, 0, 0, 0), 0, 3.0))
		t.set_stylebox("grabber", tn, flat(EDGE, Color(0, 0, 0, 0), 0, 3.0))
		t.set_stylebox("grabber_highlight", tn, flat(acc.darkened(0.2), Color(0, 0, 0, 0), 0, 3.0))
		t.set_stylebox("grabber_pressed", tn, flat(acc, Color(0, 0, 0, 0), 0, 3.0))
	for tn in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_selected", tn, box("btn_pressed", acc))
		t.set_stylebox("tab_unselected", tn, box("btn", acc))
		t.set_stylebox("tab_hovered", tn, box("btn_hover", acc))
		t.set_color("font_selected_color", tn, Color.WHITE)
	t.set_stylebox("panel", "TabContainer", box("plate", acc))
	return t


static func _bar_fill(c: Color) -> StyleBoxFlat:
	var sb := flat(c, c.lightened(0.35), 0)
	sb.border_width_top = 1
	return sb


static func panel(kind: String = "frame") -> PanelContainer:
	var p := PanelContainer.new()
	var vn := {"plate": "PlatePanel", "inset": "InsetPanel", "header": "HeaderPanel", "modal": "ModalPanel", "card": "CardPanel"}
	if vn.has(kind):
		p.theme_type_variation = vn[kind]
	if kind == "modal":
		p.set_meta("ui_modal", true)
	return p


static func button(text: String, hotkey: String = "", tip: String = "") -> Button:
	var b := Button.new()
	b.text = text if hotkey == "" else "[%s] %s" % [hotkey, text]
	b.tooltip_text = tooltip(text, hotkey, {}, tip)
	b.custom_minimum_size.y = BTN_H
	return b


static func icon_button(icon: Texture2D, hotkey: String = "", tip: String = "", text: String = "") -> Button:
	var b := Button.new()
	b.icon = icon
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = ICON_BTN
	b.text = text
	b.tooltip_text = tooltip(text if text != "" else tip.get_slice("\n", 0), hotkey, {}, tip if text != "" else "")
	if hotkey != "":
		var hk := label(hotkey, "small")
		hk.add_theme_color_override("font_color", AMBER)
		hk.add_theme_constant_override("outline_size", 3)
		hk.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		hk.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		hk.grow_vertical = Control.GROW_DIRECTION_BEGIN
		hk.offset_right = -3.0
		hk.offset_bottom = 1.0
		b.add_child(hk)
	return b


static func label(text: String, role: String = "body") -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vn := {"title": "TitleLabel", "header": "HeaderLabel", "dim": "DimLabel", "small": "SmallLabel", "number": "NumberLabel"}
	if vn.has(role):
		l.theme_type_variation = vn[role]
	elif role == "warn":
		l.add_theme_color_override("font_color", YELLOW)
	elif role == "good":
		l.add_theme_color_override("font_color", GREEN)
	elif role == "bad":
		l.add_theme_color_override("font_color", RED)
	return l


static func bar(kind: String = "hp") -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.custom_minimum_size = Vector2(0, 12 if kind == "hp" else 8)
	if BAR_COLS.has(kind):
		pb.theme_type_variation = kind.capitalize() + "Bar"
	return pb


## "Title   [Hotkey H]" / "Cost: ..." / body. cost uses the credits/salvage/ore keys of content costs.
static func tooltip(title: String, hotkey: String = "", cost: Dictionary = {}, body: String = "") -> String:
	var lines: Array = []
	var head := title
	if hotkey != "":
		head += "   [Hotkey %s]" % hotkey
	if head != "":
		lines.append(head)
	if not cost.is_empty():
		var parts: Array = []
		for k in ["credits", "salvage", "ore"]:
			if int(cost.get(k, 0)) > 0:
				parts.append("%d %s" % [int(cost[k]), k])
		lines.append("Cost: " + (", ".join(parts) if not parts.is_empty() else "free"))
	if body != "":
		lines.append(body)
	return "\n".join(lines)


static func fit_register(c: Control, modal: bool = false) -> Control:
	c.set_meta("ui_fit", true)
	if modal:
		c.set_meta("ui_modal", true)
	return c


static func scroll(child: Control, max_h: float = 0.0) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	if max_h > 0.0:
		s.custom_minimum_size.y = max_h
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s
