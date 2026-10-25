extends RefCounted
## Dark military UI theme, built in code. Gunmetal panels, amber/olive accents.
## G5 (UI5a): make_theme() delegates to the panel kit; colours match UiKit.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")

const BG := Color("0f1315")
const PANEL := Color("1b2226")
const PANEL_HI := Color("263036")
const EDGE := Color("4a565c")
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


static func make_theme(accent: Color = AMBER) -> Theme:
	# G5 (UI5a): the military panel kit (presentation/ui5/kit/ui_kit.gd) is the one theme.
	return UiKit.make_theme(accent)


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
