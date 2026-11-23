extends RefCounted
## G6 (UI6b) targeted command modes, owned by G4bInput as `g6` (presentation/view/g4b_input.gd) and armed
## through MatchView.g4b.arm(mode, params) by presentation/ui6/b/g6_cmds.gd (CONTRACTS_G6 section 4).
##   rect  (press = first corner, drag = preview, release = issue; clamped to the rules max rect):
##         minefield -> lay_minefield {unit_ids, rect, kind}, sweep -> sweep {unit_ids, rect},
##         sea_mines -> lay_sea_mines {unit_ids, rect}
##   line  (press = start, drag = preview along Rail.path_cells, release = issue): build_rail {unit_ids, from, to}
##   click line_charge {unit_id, cell}; designate {unit_id, target_id | cell}; strike {unit_ids | building_id,
##         cell, target_id?}; deploy_bridge {unit_id, cell (the layer's bank cell), dir toward the click};
##         airdrop {carrier_id, cell}; garrison {unit_ids, building_id (own, garrison slots)};
##         breach {unit_ids, target_id}; assimilate / tow_wreck {unit_id, wreck_id (nearest wreck)}
## Positions come from MatchView (its pick goes through the camera's height-aware pick once UI6a wires it),
## so drags on raised ground use the drawn cell. World reads happen only in click / release handlers
## (MatchView joins any step first) or when mv.world_readable().

const Mines = preload("res://sim/systems/mines.gd")
const Rail = preload("res://sim/systems/rail.gd")
const Garrison = preload("res://sim/systems/garrison.gd")

const MODES := {"minefield": "rect", "sweep": "rect", "sea_mines": "rect", "build_rail": "line",
	"line_charge": "click", "designate": "click", "strike": "click", "deploy_bridge": "click", "airdrop": "click",
	"garrison": "click", "breach": "click", "assimilate": "click", "tow_wreck": "click"}
const COL_OK := Color(0.3, 1.0, 0.35)
const COL_BAD := Color(1.0, 0.3, 0.2)
const WRECK_PICK := 1.6

var g4b                        # G4bInput (mode, unit_ids, g5p, _send, flash, cancel)
var from: Variant = null       # Vector2i drag start (rect / line modes)
var to := Vector2i.ZERO


static func has_mode(m: String) -> bool:
	return MODES.has(m)


static func kind(m: String) -> String:
	return String(MODES.get(m, ""))


func dragging() -> bool:
	return from != null


func cancel() -> void:
	from = null


func _mv():
	return g4b.mv


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


static func max_rect() -> int:
	return int(Mines.field_rule("max_rect", 8))


## [x0, y0, x1, y1] for the dragged corners, clamped to max_rect() cells per side from the first corner.
static func rect_of(a: Vector2i, b: Vector2i) -> Array:
	var mx := max_rect() - 1
	var bx := clampi(b.x, a.x - mx, a.x + mx)
	var by := clampi(b.y, a.y - mx, a.y + mx)
	return [mini(a.x, bx), mini(a.y, by), maxi(a.x, bx), maxi(a.y, by)]


func status_text(m: String) -> String:
	var p: Dictionary = g4b.g5p
	match m:
		"minefield", "sweep", "sea_mines":
			var what := {"minefield": "MINEFIELD (%s)" % String(p.get("kind", "mixed")).to_upper(), "sweep": "SWEEP",
				"sea_mines": "SEA MINES"}
			if from != null:
				var r := rect_of(from, to)
				return "%s: %d x %d. Release to order (max %d x %d)." % [what[m], int(r[2]) - int(r[0]) + 1,
					int(r[3]) - int(r[1]) + 1, max_rect(), max_rect()]
			return "%s: press and drag a rectangle on the map (max %d x %d). Esc cancels." % [what[m], max_rect(), max_rect()]
		"build_rail":
			if from != null:
				return "RAIL: %d tiles. Release to lay (start at a Rail Yard or a line)." % Rail.path_cells(from, to).size()
			return "RAIL: press at a Rail Yard or rail end and drag the line. Esc cancels."
		"line_charge":
			return "LINE CHARGE: click the cell to clear a lane toward. Esc cancels."
		"designate":
			return "DESIGNATE: click an enemy (or a cell) for friendly strikes. Esc cancels."
		"strike":
			return "STRIKE: click an enemy or the target cell. Esc cancels."
		"deploy_bridge":
			return "BRIDGE: click across the water from the bridge layer. Esc cancels."
		"airdrop":
			return "AIRDROP: click the drop zone (3x3). Esc cancels."
		"garrison":
			return "GARRISON: click an own bunker, pillbox, FOB or garrison building. Esc cancels."
		"breach":
			return "BREACH: click a wall, gate or building. Esc cancels."
		"assimilate":
			return "ASSIMILATE: click a wreck. Esc cancels."
		"tow_wreck":
			return "TOW: click a wreck to haul to your scrapyard. Esc cancels."
	return ""


# ---------------------------------------------------------------- input (from G4bInput)
## Left press with a G6 mode armed. True = consumed.
func left(p: Vector2) -> bool:
	var m := String(g4b.mode)
	match kind(m):
		"rect", "line":
			from = _cell(p)
			to = from
			return true
		"click":
			if _click(m, p):
				g4b.cancel()
			return true
	return false


func motion(p: Vector2) -> void:
	if from != null:
		to = _cell(p)


## Left release ending a rect / line drag. True = consumed.
func release(p: Vector2) -> bool:
	if from == null:
		return false
	to = _cell(p)
	var a: Vector2i = from
	var m := String(g4b.mode)
	var ids: Array = (g4b.unit_ids as Array).duplicate()
	var ctr := (Vector2(a) + Vector2(to)) * 0.5 + Vector2(0.5, 0.5)
	match m:
		"minefield":
			g4b._send({"type": "lay_minefield", "unit_ids": ids, "rect": rect_of(a, to),
				"kind": String(g4b.g5p.get("kind", "mixed"))}, ctr, Color(1, 0.8, 0.3))
		"sweep":
			g4b._send({"type": "sweep", "unit_ids": ids, "rect": rect_of(a, to)}, ctr, Color(0.45, 0.85, 1.0))
		"sea_mines":
			g4b._send({"type": "lay_sea_mines", "unit_ids": ids, "rect": rect_of(a, to)}, ctr, Color(1, 0.8, 0.3))
		"build_rail":
			g4b._send({"type": "build_rail", "unit_ids": ids, "from": [a.x, a.y], "to": [to.x, to.y]}, ctr, Color(0.8, 0.7, 0.5))
	from = null
	g4b.cancel()
	return true


func _enemy_at(p: Vector2):
	var mv = _mv()
	var t = mv.entity_at(p, true)
	var ww = mv.get("_world")  # never mv.world: that getter forces a sim join
	if t != null and ww != null and int(t.owner) != int(mv.player_fid) and ww.is_enemy(int(mv.player_fid), int(t.owner)):
		return t
	return null


## Nearest wreck entity within WRECK_PICK of p (ascending id on ties), or null.
func wreck_at(p: Vector2):
	var best = null
	var bd := WRECK_PICK
	var w: SimWorld = _mv().get("_world")  # never .world: forces a sim join
	if w == null:
		return null
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e = w.entities[id]
		if String(e.kind) != "wreck":
			continue
		var d := Vector2(e.pos).distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best


## Dominant axis direction from a toward b ("" when a == b).
static func dir_name(a: Vector2, b: Vector2) -> String:
	var d := b - a
	if d.length() < 0.01:
		return ""
	if absf(d.x) >= absf(d.y):
		return "e" if d.x > 0.0 else "w"
	return "s" if d.y > 0.0 else "n"


## Overlay (G4bOverlay, no step in flight): the dragged rect / rail line and a mode tag at the mouse.
func draw(ci: CanvasItem, mouse_canvas: Vector2) -> void:
	var m := String(g4b.mode)
	if not has_mode(m):
		return
	var mv = _mv()
	var cells: Array = []
	var col := COL_OK
	if from != null and kind(m) == "rect":
		var r := rect_of(from, to)
		for y in range(int(r[1]), int(r[3]) + 1):
			for x in range(int(r[0]), int(r[2]) + 1):
				cells.append(Vector2i(x, y))
		col = Color(1, 0.8, 0.3) if m != "sweep" else Color(0.45, 0.85, 1.0)
	elif from != null and kind(m) == "line":
		cells = Rail.path_cells(from, to)
		if cells.size() > int(Rail.R().get("max_line", 48)):
			col = COL_BAD
	for c in cells:
		var p := Vector2(c)
		var pts := PackedVector2Array()
		for q in [p, p + Vector2(1, 0), p + Vector2(1, 1), p + Vector2(0, 1)]:
			pts.append(mv.world_to_screen(q))
		ci.draw_colored_polygon(pts, Color(col, 0.3))
		pts.append(pts[0])
		ci.draw_polyline(pts, Color(col, 0.9), 1.2)
	var f := ThemeDB.fallback_font
	var at: Vector2 = mouse_canvas + Vector2(16, 22)
	var tag := m.replace("_", " ").to_upper()
	if from != null and kind(m) == "rect":
		var rr := rect_of(from, to)
		tag += "  %dx%d" % [int(rr[2]) - int(rr[0]) + 1, int(rr[3]) - int(rr[1]) + 1]
	elif from != null:
		tag += "  %d" % cells.size()
	ci.draw_string_outline(f, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
	ci.draw_string(f, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.7))


## One click in a click mode; false keeps the mode armed (a hint was flashed).
func _click(m: String, p: Vector2) -> bool:
	var mv = _mv()
	var w: SimWorld = mv.get("_world")  # never mv.world: that getter forces a sim join
	if w == null:
		return false
	var c := _cell(p)
	var cc := [c.x, c.y]
	var ids: Array = (g4b.unit_ids as Array).duplicate()
	var uid := int(ids[0]) if not ids.is_empty() else -1
	var at := Vector2(c) + Vector2(0.5, 0.5)
	match m:
		"line_charge":
			g4b._send({"type": "line_charge", "unit_id": uid, "cell": cc}, at, Color(1, 0.55, 0.2))
		"designate":
			var t = _enemy_at(p)
			var cmd := {"type": "designate", "unit_id": uid}
			if t != null:
				cmd["target_id"] = int(t.id)
			else:
				cmd["cell"] = cc
			g4b._send(cmd, p, Color(1, 0.3, 0.3))
		"strike":
			var t2 = _enemy_at(p)
			var cmd2 := {"type": "strike", "cell": [w.cell_of(t2.pos).x, w.cell_of(t2.pos).y] if t2 != null else cc}
			if t2 != null:
				cmd2["target_id"] = int(t2.id)
			if int(g4b.g5p.get("building_id", -1)) >= 0:
				cmd2["building_id"] = int(g4b.g5p.building_id)
			else:
				cmd2["unit_ids"] = ids
			g4b._send(cmd2, p, Color(1, 0.35, 0.2))
		"deploy_bridge":
			var u = w.entities.get(uid)
			if u == null:
				return true
			var dn := dir_name(Vector2(u.pos), p)
			if dn == "":
				g4b.flash("Click across the water, away from the bridge layer.")
				return false
			var uc: Vector2i = w.cell_of(u.pos)
			g4b._send({"type": "deploy_bridge", "unit_id": uid, "cell": [uc.x, uc.y], "dir": dn}, p, Color(0.45, 0.85, 1.0))
		"airdrop":
			g4b._send({"type": "airdrop", "carrier_id": uid, "cell": cc}, at, Color(0.45, 0.85, 1.0))
		"garrison":
			var b = mv.entity_at(p, true)
			if b == null or String(b.kind) != "building" or int(b.owner) != int(mv.player_fid) or Garrison.slots_of(String(b.def)) <= 0:
				g4b.flash("Click an own building with garrison slots.")
				return false
			g4b._send({"type": "garrison", "unit_ids": ids, "building_id": int(b.id)}, b.pos, Color(0.45, 0.85, 1.0))
		"breach":
			var t3 = mv.entity_at(p, true)
			if t3 == null or not (String(t3.kind) in ["building", "bridge"]):
				g4b.flash("Breach needs a wall, gate or building.")
				return false
			g4b._send({"type": "breach", "unit_ids": ids, "target_id": int(t3.id)}, t3.pos, Color(1, 0.35, 0.2))
		"assimilate", "tow_wreck":
			var wr = wreck_at(p)
			if wr == null:
				g4b.flash("Click a wreck.")
				return false
			g4b._send({"type": m, "unit_id": uid, "wreck_id": int(wr.id)}, wr.pos, Color(0.4, 1.0, 0.8))
	return true
