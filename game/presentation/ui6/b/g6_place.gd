extends RefCounted
## G6 (UI6b-3) placement of the frames that sit above the command card (LoadoutPanel, GaragePanel, ResearchG6Panel
## and the G4b cargo strip), so they never run into the HUD at any resolution or UI scale (720p at 150 % is a
## 1067x600 canvas):
##   - bottom: just above the bottom panel's real top (it grows with the card);
##   - top: below the top bar and, while it shows, below the centred PAUSED banner;
##   - sides: between the HUD's LeftScroll / RightScroll columns when they reach into the frame's rows.
## A panel keeps its preferred width when the room allows (centred on the canvas, shifted into the room when a
## column is in the way), else takes the room's width; its body is a ScrollContainer capped to the room's height,
## the way the G5 UiKit panels and the HUD side stacks scroll instead of overlapping.
## All rects are root (canvas) px; the frames are children of the HUD's ScaledLayer root.

const GAP := 6.0          # clearance to the side columns / PAUSED banner
const TOP_MIN := 42.0     # HUD TOP_H 34 + 8: below the top bar
const EDGE := 12.0        # HUD EDGE_M
const BOT_MIN := 226.0    # HUD BOTTOM_H 220 + 6
const MIN_W := 240.0      # never narrower than this (a too-small canvas then overlaps rather than vanishes)
const MIN_H := 40.0


## c's rect in root (canvas) px.
static func rect_in(root: Control, c: Control) -> Rect2:
	var r := c.get_global_rect()
	r.position -= root.get_global_rect().position
	return r


## Lowest y a frame may reach: just above the bottom panel's real top.
static func bottom_y(root: Control) -> float:
	var bot := BOT_MIN
	var bp := root.get_node_or_null("BottomPanel") as Control
	if bp != null and bp.is_visible_in_tree():
		bot = maxf(bot, bp.size.y + 6.0)
	return root.size.y - bot


## Highest y a frame may reach: below the top bar and below the PAUSED banner while it is visible.
static func top_y(hud, root: Control) -> float:
	var t := TOP_MIN
	var pb = hud.get("_paused_banner") if hud != null else null
	if pb is Control and is_instance_valid(pb) and (pb as Control).is_visible_in_tree() and (pb as Control).size.y > 0.5:
		t = maxf(t, rect_in(root, pb).end.y + GAP)
	return t


## Horizontal room (x = left, y = right) for a frame spanning rows y0..y1: between the side columns that reach
## into those rows (2 px vertical clearance counts as reaching), else the screen edges.
static func h_room(root: Control, y0: float, y1: float) -> Vector2:
	var x0 := EDGE
	var x1 := root.size.x - EDGE
	for nm in ["LeftScroll", "RightScroll"]:
		var sc := root.get_node_or_null(nm) as Control
		if sc == null or not sc.is_visible_in_tree() or sc.size.y < 1.0 or sc.size.x < 1.0:
			continue
		var r := rect_in(root, sc)
		if r.position.y >= y1 + 2.0 or r.end.y <= y0 - 2.0:
			continue
		if nm == "LeftScroll":
			x0 = maxf(x0, r.end.x + GAP)
		else:
			x1 = minf(x1, r.position.x - GAP)
	return Vector2(x0, x1)


## Left x for a frame of width w: centred on the canvas when that fits the room, else shifted into it.
static func left_x(root: Control, room: Vector2, w: float) -> float:
	return clampf(root.size.x * 0.5 - w * 0.5, room.x, maxf(room.x, room.y - w))


## Places `panel` (anchors 0.5 / 1.0, grows up; its only child `scroll` wraps the content): width
## min(want_w, room), height the content's capped to the room (the body then scrolls). set_w(inner_w) sets the
## content's wrap / column widths for an inner width. Returns the panel rect (canvas px; empty before layout).
static func place(hud, panel: PanelContainer, scroll: ScrollContainer, want_w: float, set_w: Callable) -> Rect2:
	var root: Control = (panel.get_parent() as Control) if panel != null else null
	if root == null or root.size.x <= 0.0 or scroll == null or scroll.get_child_count() == 0:
		return Rect2()
	var cs := root.size
	var y1 := bottom_y(root)
	var y0 := minf(top_y(hud, root), y1 - MIN_H)
	var room := h_room(root, y0, y1)
	var w := minf(want_w, maxf(room.y - room.x, MIN_W))
	var sb := panel.get_theme_stylebox("panel")
	var pad: Vector2 = sb.get_minimum_size() if sb != null else Vector2(24, 16)
	var content: Control = scroll.get_child(0)
	set_w.call(w - pad.x)
	var need := content.get_combined_minimum_size()
	var avail := maxf(y1 - y0 - pad.y, MIN_H)
	var scrolls := need.y > avail + 0.5
	if scrolls:
		var bar := scroll.get_v_scroll_bar().get_combined_minimum_size().x + 2.0
		set_w.call(w - pad.x - bar)
		need = content.get_combined_minimum_size()
	var h := minf(need.y, avail)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if scrolls else ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, h)
	var x := left_x(root, room, w)
	panel.offset_left = x - cs.x * 0.5
	panel.offset_right = panel.offset_left + w
	panel.offset_bottom = y1 - cs.y
	panel.offset_top = panel.offset_bottom - (h + pad.y)
	return Rect2(Vector2(x, y1 - h - pad.y), Vector2(w, h + pad.y))


## Horizontal placement only, for a frame with fixed rows (the cargo strip, anchors 0.5 / 1.0): width
## min(want_w, room) but never below the frame's own minimum width.
static func place_h(panel: Control, want_w: float) -> void:
	var root: Control = (panel.get_parent() as Control) if panel != null else null
	if root == null or root.size.x <= 0.0:
		return
	var cs := root.size
	var y0 := cs.y + panel.offset_top
	var y1 := cs.y + panel.offset_bottom
	var room := h_room(root, y0, y1)
	var w := maxf(minf(want_w, room.y - room.x), panel.get_combined_minimum_size().x)
	var x := left_x(root, room, w)
	panel.offset_left = x - cs.x * 0.5
	panel.offset_right = panel.offset_left + w
