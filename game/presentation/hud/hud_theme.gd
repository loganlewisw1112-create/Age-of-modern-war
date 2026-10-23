extends RefCounted
## Dark military UI theme, built in code (no external fonts). Gunmetal panels, amber/olive accents.

const BG := Color("14181b")
const PANEL := Color("23292d")
const PANEL_HI := Color("2f373c")
const EDGE := Color("4b555b")
const AMBER := Color("e3a83a")
const OLIVE := Color("8fa24e")
const TEXT := Color("dcdfd2")
const DIM := Color("8e9893")
const RED := Color("e0605a")
const GREEN := Color("86c85e")
const BLUE := Color("6fa8dc")
const YELLOW := Color("e8d25a")


static func box(bg: Color, border: Color = EDGE, bw: int = 1, radius: int = 2, margin: float = 6.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.7
	sb.content_margin_bottom = margin * 0.7
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 15)
	# Panels
	t.set_stylebox("panel", "PanelContainer", box(PANEL, EDGE, 1, 2, 8))
	t.set_stylebox("panel", "Panel", box(PANEL, EDGE, 1, 2, 8))
	# Buttons
	for type_name in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type_name, box(PANEL_HI, EDGE, 1, 2, 8))
		t.set_stylebox("hover", type_name, box(Color("3b454b"), AMBER, 1, 2, 8))
		t.set_stylebox("pressed", type_name, box(Color("5a4a22"), AMBER, 1, 2, 8))
		t.set_stylebox("focus", type_name, box(Color(0, 0, 0, 0), AMBER, 1, 2, 8))
		t.set_stylebox("disabled", type_name, box(Color("1c2124"), Color("30383c"), 1, 2, 8))
		t.set_color("font_color", type_name, TEXT)
		t.set_color("font_hover_color", type_name, Color.WHITE)
		t.set_color("font_pressed_color", type_name, AMBER)
		t.set_color("font_disabled_color", type_name, Color("68716d"))
		t.set_font_size("font_size", type_name, 15)
	# Check box
	t.set_color("font_color", "CheckBox", TEXT)
	# Line edits / spin boxes
	t.set_stylebox("normal", "LineEdit", box(BG, EDGE, 1, 2, 6))
	t.set_stylebox("focus", "LineEdit", box(BG, AMBER, 1, 2, 6))
	t.set_color("font_color", "LineEdit", TEXT)
	# Popups (OptionButton lists)
	t.set_stylebox("panel", "PopupMenu", box(PANEL, AMBER, 1, 2, 6))
	t.set_stylebox("hover", "PopupMenu", box(Color("4a4226"), AMBER, 0, 0, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_disabled_color", "PopupMenu", Color("5d6661"))
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	# Progress bars
	var bg := box(BG, EDGE, 1, 1, 0)
	var fill := box(OLIVE, OLIVE, 0, 1, 0)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_color("font_color", "ProgressBar", Color.WHITE)
	t.set_font_size("font_size", "ProgressBar", 12)
	# Tooltips
	t.set_stylebox("panel", "TooltipPanel", box(Color("0e1114"), AMBER, 1, 2, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)
	return t


static func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	if int(cost.get("credits", 0)) > 0:
		parts.append("%dcr" % int(cost.credits))
	if int(cost.get("salvage", 0)) > 0:
		parts.append("%dsv" % int(cost.salvage))
	if int(cost.get("ore", 0)) > 0:
		parts.append("%dor" % int(cost.ore))
	return " ".join(parts) if not parts.is_empty() else "free"


static func cost_text_long(cost: Dictionary) -> String:
	var parts: Array = []
	if int(cost.get("credits", 0)) > 0:
		parts.append("%d credits" % int(cost.credits))
	if int(cost.get("salvage", 0)) > 0:
		parts.append("%d salvage" % int(cost.salvage))
	if int(cost.get("ore", 0)) > 0:
		parts.append("%d ore" % int(cost.ore))
	return ", ".join(parts) if not parts.is_empty() else "free"


static func clock_text(tick: int) -> String:
	var secs := tick / SimWorld.TICK_RATE
	return "%02d:%02d" % [secs / 60, secs % 60]


static func make_label(text: String, color: Color = TEXT, size: int = 15) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
