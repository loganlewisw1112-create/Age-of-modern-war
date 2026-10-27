extends Control
## G7 (WOUND7): wound card for the selection inspector. Replaces the infantry hp bar for hit-zone soldiers
## (SimWorld.Wounds.applies). Display only: reads Wounds.state(e) (a copy), never writes the sim.
##   var card := preload("res://presentation/ui7/wound_card.gd").new()
##   card.set_unit(e)            # e = the selected entity dict from the render side (or {} to clear)
##   WoundCard.wants(e) -> bool  # true when the card replaces the hp bar for e
## Body diagram: head, torso, both arms, both legs; a zone is grey (unhurt), amber (1 hit), red (2+ hits); old
## scars show as a thin outline. Icons row: bleeding (drop + rate), unconscious, stabilised, crawling, being
## treated / dragged / carried, panic state, breached suit.

const Wounds = preload("res://sim/systems/wounds.gd")

const C_OK := Color(0.55, 0.6, 0.55)
const C_ONE := Color(0.95, 0.65, 0.2)
const C_TWO := Color(0.9, 0.2, 0.15)
const C_SCAR := Color(0.85, 0.8, 0.7)
const C_TEXT := Color(0.92, 0.92, 0.88)
const C_BLOOD := Color(0.85, 0.1, 0.1)

var _st: Dictionary = {}


static func wants(e: Dictionary) -> bool:
	return not e.is_empty() and e.get("kind", "") == "unit" and Wounds.applies(e)


func _init() -> void:
	custom_minimum_size = Vector2(150, 84)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_unit(e: Dictionary) -> void:
	_st = Wounds.state(e) if wants(e) else {}
	visible = not _st.is_empty()
	queue_redraw()


func set_state(st: Dictionary) -> void:
	_st = st
	visible = not _st.is_empty()
	queue_redraw()


## Zone rectangles in a 48 x 80 body box (origin top-left).
static func zone_rects() -> Dictionary:
	return {"torso": Rect2(16, 18, 16, 26), "arm_l": Rect2(8, 19, 7, 24), "arm_r": Rect2(33, 19, 7, 24),
		"leg_l": Rect2(16, 46, 7, 30), "leg_r": Rect2(25, 46, 7, 30)}


func _zone_col(n: int) -> Color:
	return C_OK if n <= 0 else (C_ONE if n == 1 else C_TWO)


## Short status words for the icon row (also used by tests / tooltips).
static func status_words(st: Dictionary) -> Array:
	var out: Array = []
	if st.is_empty():
		return out
	if bool(st.get("unconscious", false)):
		out.append("UNCONSCIOUS")
	elif bool(st.get("down", false)):
		out.append("DOWN")
	if float(st.get("bleed", 0.0)) > 0.0:
		out.append("BLEEDING %.1f/s" % float(st.bleed))
	if bool(st.get("stable", false)):
		out.append("STABLE")
	if bool(st.get("crawl", false)):
		out.append("CRAWLING")
	if int(st.get("treated_by", -1)) >= 0:
		out.append("TREATED")
	if int(st.get("dragged_by", -1)) >= 0:
		out.append("DRAGGED")
	if int(st.get("carried_by", -1)) >= 0:
		out.append("EVACUATING")
	var pn := String(st.get("panic", ""))
	if pn != "":
		out.append(pn.to_upper())
	if bool(st.get("punctured", false)):
		out.append("SUIT BREACHED")
	return out


func _draw() -> void:
	if _st.is_empty():
		return
	var zones: Dictionary = _st.get("zones", {})
	var scars: Array = _st.get("scars", [])
	var o := Vector2(2, 2)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	var hc := _zone_col(int(zones.get("head", 0)))
	draw_circle(o + Vector2(24, 9), 7.0, hc)
	if scars.has("head"):
		draw_arc(o + Vector2(24, 9), 8.0, 0.0, TAU, 16, C_SCAR, 1.0)
	var rects := zone_rects()
	for z in rects:
		var r: Rect2 = rects[z]
		r.position += o
		draw_rect(r, _zone_col(int(zones.get(z, 0))))
		if scars.has(z):
			draw_rect(r.grow(1.0), C_SCAR, false, 1.0)
	var f := ThemeDB.fallback_font
	var fs := 10
	var y := 12.0
	var hpw := 90.0
	var hf := clampf(float(_st.get("hp_frac", 1.0)), 0.0, 1.0)
	draw_rect(Rect2(56, 4, hpw, 5), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(56, 4, hpw * hf, 5), C_BLOOD.lerp(C_OK, hf))
	for wd in status_words(_st):
		y += 12.0
		draw_string(f, Vector2(56, y), String(wd), HORIZONTAL_ALIGNMENT_LEFT, 92.0, fs,
			C_BLOOD if String(wd).begins_with("BLEED") else C_TEXT)
	if float(_st.get("bleed", 0.0)) > 0.0:
		draw_circle(o + Vector2(44, 70), 3.0, C_BLOOD)
		draw_colored_polygon(PackedVector2Array([o + Vector2(41.5, 69), o + Vector2(46.5, 69), o + Vector2(44, 63)]), C_BLOOD)
