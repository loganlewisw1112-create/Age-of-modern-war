extends RefCounted
## G4b (UI4B) player input: wall drag tool, transport load/unload, engineer mine/charge targeting.
## Owned by MatchView as `g4b`. Everything reaches the sim only through mv.issue(cmd).
## Thread safety (THREAD-1 gotchas): the world is read only from click/key handlers (MatchView._input
## joins any in-flight step before those) or when mv.world_readable(); mouse motion never reads it.
## Contract: CONTRACTS_G4 sections 6-8; FORT fort.api_ready, TRANS trans.api_ready.
##   wall drag: build card wall def -> press = line start, drag = preview (8-direction snap,
##              green legal / red illegal, cost total), release = build_line (Shift appends).
##   modes:     "unload_point" (carrier_id), "lay_mine" / "plant_charge" (engineer unit_ids).

const Fortify = preload("res://sim/systems/fortify.gd")
const Transport = preload("res://sim/systems/transport.gd")

var mv
var mode := ""                 # "" | unload_point | lay_mine | plant_charge
var unit_ids: Array = []
var carrier_id := -1
var hint_text := ""
var hint_until := 0
# wall drag
var wall_from: Variant = null  # Vector2i start cell while dragging
var wall_to := Vector2i.ZERO
var wall_def := ""
var preview: Dictionary = {}   # Fortify.preview_line result for (wall_from, wall_to)
var _preview_key := ""
var last_line: Dictionary = {} # the last build_line command issued (playtest / debug)


static func is_wall_def(def_id: String) -> bool:
	return def_id != "" and Fortify.kind_of(def_id) == "wall"


func active() -> bool:
	return mode != ""


func dragging() -> bool:
	return wall_from != null


func arm(m: String, params: Dictionary = {}) -> void:
	mode = m
	unit_ids = (params.get("unit_ids", []) as Array).duplicate()
	carrier_id = int(params.get("carrier_id", -1))
	mv.attack_move_armed = false
	mv.cancel_placement()
	if mv.g2 != null:
		mv.g2.cancel()


func cancel() -> void:
	mode = ""
	unit_ids = []
	carrier_id = -1
	wall_from = null
	preview = {}
	_preview_key = ""


func flash(text: String, secs: float = 2.5) -> void:
	hint_text = text
	hint_until = Time.get_ticks_msec() + int(secs * 1000.0)


func status_text() -> String:
	match mode:
		"unload_point":
			return "UNLOAD: click the point where the transport drops its cargo. Esc cancels."
		"lay_mine":
			return "LAY MINE: click a ground cell. Esc cancels."
		"plant_charge":
			return "PLANT CHARGE: click a wall, building or bridge. Esc cancels."
	if wall_from != null:
		var n := (preview.get("legal", []) as Array).size()
		return "WALL: %d segments, %s. Release to build (Shift appends to the queue)." % [n, _cost_text(n)]
	if is_wall_def(String(mv.placing_def)):
		return "WALL: press on the map and drag a line (8 directions). Right-click or Esc cancels."
	if Time.get_ticks_msec() < hint_until:
		return hint_text
	return ""


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


# ---------------------------------------------------------------- wall drag (from MatchView)
## Left press while a wall def is being placed: starts the line. True = consumed.
func on_place_press(p: Vector2) -> bool:
	if not is_wall_def(String(mv.placing_def)):
		return false
	wall_def = String(mv.placing_def)
	wall_from = _cell(p)
	wall_to = wall_from
	_refresh_preview()
	return true


func on_motion(p: Vector2) -> void:
	if wall_from == null:
		return
	wall_to = _cell(p)
	if mv.world_readable():
		_refresh_preview()


## Left release: issue build_line for the dragged line. True = consumed.
func on_release(p: Vector2, shift: bool) -> bool:
	if wall_from == null:
		return false
	wall_to = _cell(p)
	_refresh_preview()
	var from: Vector2i = wall_from
	var cmd := {"type": "build_line", "def": wall_def, "from": [from.x, from.y], "to": [wall_to.x, wall_to.y],
		"unit_ids": mv._own_engineers_in_selection()}
	if shift:
		cmd["append"] = true
	last_line = cmd.duplicate(true)
	var r: Dictionary = mv.issue(cmd)
	if not bool(r.get("ok", true)):
		flash("Wall: " + String(r.get("reason", "rejected")))
	wall_from = null
	preview = {}
	_preview_key = ""
	if not shift:
		mv.cancel_placement()
	return true


## World read: only from handlers that run with no step in flight (see header).
func _refresh_preview() -> void:
	if wall_from == null or not mv.world_readable():
		return
	var key := "%s|%s|%s" % [wall_def, str(wall_from), str(wall_to)]
	if key == _preview_key:
		return
	_preview_key = key
	preview = Fortify.preview_line(mv.world, mv.player_fid, wall_def, wall_from, wall_to)


func _cost_text(n: int) -> String:
	var each: Dictionary = preview.get("cost_each", Content.building(wall_def).get("cost", {}))
	var parts: Array = []
	for k in ["credits", "salvage", "ore"]:
		var v := int(each.get(k, 0)) * n
		if v > 0:
			parts.append("%d %s" % [v, k])
	return "free" if parts.is_empty() else ", ".join(parts)


# ---------------------------------------------------------------- order modes (from MatchView)
func on_left(p: Vector2, _shift: bool) -> bool:
	if mode == "":
		return false
	match mode:
		"unload_point":
			mv.issue({"type": "unload", "carrier": carrier_id, "target": p})
			mv.fx_layer.add_marker(p, Color(0.45, 0.85, 1.0))
		"lay_mine":
			var c := _cell(p)
			mv.issue({"type": "lay_mine", "unit_ids": unit_ids.duplicate(), "cell": [c.x, c.y]})
			mv.fx_layer.add_marker(Vector2(c) + Vector2(0.5, 0.5), Color(1.0, 0.8, 0.3))
		"plant_charge":
			var t = mv.entity_at(p, true)
			if t == null or not (String(t.kind) in ["building", "bridge"]):
				flash("Plant charge needs a wall, building or bridge.")
				return true
			mv.issue({"type": "plant_charge", "unit_ids": unit_ids.duplicate(), "target_id": int(t.id)})
			mv.fx_layer.add_marker(t.pos, Color(1.0, 0.35, 0.2))
	cancel()
	return true


func on_right() -> bool:
	if mode != "" or wall_from != null:
		cancel()
		return true
	return false


func on_key(kc: int) -> bool:
	if kc == KEY_ESCAPE and (mode != "" or wall_from != null):
		cancel()
		return true
	return false


## Smart right-click: selected units on an own transport -> load. True = consumed.
func smart(p: Vector2, t, units: Array) -> bool:
	if t == null or String(t.kind) != "unit" or int(t.owner) != mv.player_fid or not Transport.is_carrier(t):
		return false
	var w = mv.world
	var riders: Array = []
	for id in units:
		var u = w.entities.get(int(id))
		if u != null and int(u.id) != int(t.id) and Transport.can_carry(t, u) == "":
			riders.append(int(id))
	if riders.is_empty():
		flash(Transport.can_carry(t, w.entities.get(int(units[0]))) if not units.is_empty() else "")
		return false
	mv.issue({"type": "load", "carrier": int(t.id), "unit_ids": riders})
	mv.fx_layer.add_marker(t.pos, Color(0.45, 0.85, 1.0))
	return true


# ---------------------------------------------------------------- preview (drawn by g4b_overlay)
func draw_preview(ci: CanvasItem) -> void:
	if wall_from == null:
		return
	_refresh_preview()  # the overlay draws only with no step in flight (re-checked inside)
	var legal := {}
	for c in preview.get("legal", []):
		legal[Vector2i(c)] = true
	var cells: Array = preview.get("cells", Fortify.line_cells(wall_from, wall_to))
	for c in cells:
		var cc := Vector2i(c)
		var ok := legal.has(cc)
		var col := Color(0.3, 1.0, 0.35, 0.45) if ok else Color(1.0, 0.25, 0.2, 0.45)
		var p := Vector2(cc)
		var pts := PackedVector2Array()
		for q in [p, p + Vector2(1, 0), p + Vector2(1, 1), p + Vector2(0, 1)]:
			pts.append(mv.world_to_screen(q))
		ci.draw_colored_polygon(pts, col)
		pts.append(pts[0])
		ci.draw_polyline(pts, Color(col, 0.95), 1.5)
	var n := legal.size()
	var at: Vector2 = mv.world_to_screen(Vector2(wall_to) + Vector2(0.5, 0.5)) + Vector2(14, -18)
	var f := ThemeDB.fallback_font
	var txt := "%d / %d  %s" % [n, cells.size(), _cost_text(n)]
	ci.draw_string_outline(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.85))
	ci.draw_string(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.95, 0.7))
