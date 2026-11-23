extends RefCounted
## G4b (UI4B) player input: wall drag tool, transport load/unload, engineer mine/charge targeting.
## Owned by MatchView as `g4b`. Everything reaches the sim only through mv.issue(cmd).
## Thread safety (THREAD-1 gotchas): the world is read only from click/key handlers (MatchView._input
## joins any in-flight step before those) or when mv.world_readable(); mouse motion never reads it.
## Contract: CONTRACTS_G4 sections 6-8; FORT fort.api_ready, TRANS trans.api_ready.
##   wall drag: build card wall def -> press = line start, drag = preview (8-direction snap,
##              green legal / red illegal, cost total), release = build_line (Shift appends).
##   modes:     "unload_point" (carrier_id), "lay_mine" / "plant_charge" (engineer unit_ids).
## G5 (UI5b) modes (CONTRACTS_G5 section 4), armed by presentation/ui5/panels/g5_unit_cmds.gd:
##   sortie (enemy -> target_id, ground -> area [x,y,r]), rebase (own field), land_at (cell),
##   bombard (cell), launch_drone (enemy -> target_id, else cell), tactical (ability: target or cell),
##   assign_engineers (own field / hangar / helipad; pointing-hand cursor),
##   auto_area (truck / medic: press = centre, drag = radius, release = set_auto_resupply / set_auto_evac).
## G6 (UI6b) modes (CONTRACTS_G6 section 4) live in presentation/ui6/b/g6_modes.gd (`g6`): rect drags
##   (minefield, sweep, sea_mines), the rail line drag (build_rail) and click modes (line_charge, designate,
##   strike, deploy_bridge, airdrop, garrison, breach, assimilate, tow_wreck); armed by ui6/b/g6_cmds.gd.

const Fortify = preload("res://sim/systems/fortify.gd")
const Transport = preload("res://sim/systems/transport.gd")
const Airfield = preload("res://sim/systems/airfield.gd")
const G6Modes = preload("res://presentation/ui6/b/g6_modes.gd")

const G5_MODES := ["sortie", "rebase", "land_at", "bombard", "launch_drone", "tactical", "assign_engineers", "auto_area"]
const SORTIE_R := 4.0
const AREA_MIN_R := 1.5

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
var g5p: Dictionary = {}       # G5 mode parameters (drone, ability, kind, mode)
var area_from: Variant = null  # G5 auto_area drag centre (world Vector2)
var area_to := Vector2.ZERO
var last_cmd: Dictionary = {}  # the last G5 / G6 command issued (tests / playtest)
var g6 = G6Modes.new()         # G6 modes (UI6b)


static func is_wall_def(def_id: String) -> bool:
	return def_id != "" and Fortify.kind_of(def_id) == "wall"


func active() -> bool:
	return mode != ""


func dragging() -> bool:
	return wall_from != null or area_from != null or (g6 != null and g6.dragging())


func arm(m: String, params: Dictionary = {}) -> void:
	mode = m
	unit_ids = (params.get("unit_ids", []) as Array).duplicate()
	carrier_id = int(params.get("carrier_id", -1))
	g5p = params.duplicate(true)
	g5p["_m"] = m
	area_from = null
	g6.g4b = self
	g6.cancel()
	if (G5_MODES.has(m) or G6Modes.has_mode(m)) and DisplayServer.get_name() != "headless":
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if m == "assign_engineers" else Input.CURSOR_CROSS)
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
	if not g5p.is_empty() and DisplayServer.get_name() != "headless":
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	g5p = {}
	area_from = null
	if g6 != null:
		g6.cancel()


func flash(text: String, secs: float = 2.5) -> void:
	hint_text = text
	hint_until = Time.get_ticks_msec() + int(secs * 1000.0)


func status_text() -> String:
	if G6Modes.has_mode(mode):
		return g6.status_text(mode)
	match mode:
		"unload_point":
			return "UNLOAD: click the point where the transport drops its cargo. Esc cancels."
		"lay_mine":
			return "LAY MINE: click a ground cell. Esc cancels."
		"plant_charge":
			return "PLANT CHARGE: click a wall, building or bridge. Esc cancels."
		"sortie":
			return "SORTIE: click an enemy to strike it, or the ground for an area strike. Esc cancels."
		"rebase":
			return "REBASE: click an own airfield, hangar or helipad. Esc cancels."
		"land_at":
			return "LAND: click an open spot (helicopters / VTOL) or an airfield (jets). Esc cancels."
		"bombard":
			return "BOMBARD: click the cell to shell. Esc cancels."
		"launch_drone":
			return "%s DRONE: click an enemy or a cell in range (20). Esc cancels." % String(g5p.get("drone", "")).to_upper()
		"tactical":
			return "%s: click the %s. Esc cancels." % [String(g5p.get("ability", "")).replace("_", " ").to_upper(),
				"spot" if ["infiltrate", "stack_up"].has(String(g5p.get("ability", ""))) else "target"]
		"assign_engineers":
			return "ASSIGN ENGINEERS: click an own airfield, hangar or helipad. Esc cancels."
		"auto_area":
			if area_from != null:
				return "AREA: radius %.0f. Release to set it." % (area_from as Vector2).distance_to(area_to)
			return "AUTO AREA: press and drag a circle for the area (click = default radius). Esc keeps the default."
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
	if g6.dragging():
		g6.motion(p)
		return
	if area_from != null:
		area_to = p
		return
	if wall_from == null:
		return
	wall_to = _cell(p)
	if mv.world_readable():
		_refresh_preview()


## Left release: issue build_line for the dragged line. True = consumed.
func on_release(p: Vector2, shift: bool) -> bool:
	if g6.dragging():
		return g6.release(p)
	if area_from != null:
		area_to = p
		_issue_area()
		cancel()
		return true
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
	preview = Fortify.preview_line(mv.get("_world"), mv.player_fid, wall_def, wall_from, wall_to)


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
	if G6Modes.has_mode(mode):
		g6.g4b = self
		return g6.left(p)
	if G5_MODES.has(mode):
		return _g5_left(p)
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


# ---------------------------------------------------------------- G5 modes (UI5b)
func _send(cmd: Dictionary, at: Vector2, col: Color) -> bool:
	last_cmd = cmd.duplicate(true)
	var r: Dictionary = mv.issue(cmd)
	if not bool(r.get("ok", true)):
		flash(String(r.get("reason", "rejected")))
		return false
	if mv.get("fx_layer") != null:
		mv.fx_layer.add_marker(at, col)
	return true


func _own_field_at(p: Vector2) -> int:
	var t = mv.entity_at(p, true)
	if t == null or String(t.kind) != "building" or int(t.owner) != int(mv.player_fid):
		return -1
	return int(t.id) if Airfield.field_of(mv.get("_world"), int(t.id)) >= 0 else -1


func _enemy_at(p: Vector2):
	var t = mv.entity_at(p, true)
	var ww = mv.get("_world")
	if ww != null and t != null and int(t.owner) != int(mv.player_fid) and ww.is_enemy(int(mv.player_fid), int(t.owner)):
		return t
	return null


## Click while a G5 mode is armed (world readable: MatchView joined the step). True = consumed.
func _g5_left(p: Vector2) -> bool:
	var c := _cell(p)
	var cc := [c.x, c.y]
	var ids: Array = unit_ids.duplicate()
	match mode:
		"sortie":
			var t = _enemy_at(p)
			if t != null:
				_send({"type": "sortie", "unit_ids": ids, "target_id": int(t.id)}, t.pos, Color(1, 0.35, 0.2))
			else:
				_send({"type": "sortie", "unit_ids": ids, "area": [p.x, p.y, SORTIE_R]}, p, Color(1, 0.55, 0.2))
		"rebase", "assign_engineers":
			var bid := _own_field_at(p)
			if bid < 0:
				flash("Click an own airfield, hangar or helipad.")
				return true
			_send({"type": mode, "unit_ids": ids, "building_id": bid}, mv.get("_world").entities[bid].pos, Color(0.45, 0.85, 1.0))
		"land_at":
			_send({"type": "land_at", "unit_ids": ids, "cell": cc}, Vector2(c) + Vector2(0.5, 0.5), Color(0.45, 0.85, 1.0))
		"bombard":
			_send({"type": "bombard", "unit_ids": ids, "cell": cc}, Vector2(c) + Vector2(0.5, 0.5), Color(1, 0.35, 0.2))
		"launch_drone":
			var cmd := {"type": "launch_drone", "unit_id": int(ids[0]) if not ids.is_empty() else -1, "drone": String(g5p.get("drone", "strike"))}
			var t2 = _enemy_at(p)
			if t2 != null:
				cmd["target_id"] = int(t2.id)
			else:
				cmd["cell"] = cc
			_send(cmd, p, Color(1, 0.8, 0.3))
		"tactical":
			var ab := String(g5p.get("ability", ""))
			var cmd2 := {"type": "tactical", "unit_id": int(ids[0]) if not ids.is_empty() else -1, "ability": ab}
			var t3 = mv.entity_at(p, true)
			if ab == "infiltrate" or ab == "stack_up":
				cmd2["cell"] = cc
			elif t3 != null:
				cmd2["target_id"] = int(t3.id)
			else:
				flash("Click a target for %s." % ab.replace("_", " "))
				return true
			_send(cmd2, p, Color(1, 0.8, 0.3))
		"auto_area":
			area_from = p
			area_to = p
			return true
	cancel()
	return true


## auto_area release: centre + radius for every armed truck / medic (a click keeps the default radius).
func _issue_area() -> void:
	var ctr: Vector2 = area_from
	var r := ctr.distance_to(area_to)
	for id in unit_ids:
		var cmd := {"unit_id": int(id), "center": [snappedf(ctr.x, 0.01), snappedf(ctr.y, 0.01)]}
		if String(g5p.get("kind", "")) == "medic":
			cmd["type"] = "set_auto_evac"
			cmd["on"] = true
		else:
			cmd["type"] = "set_auto_resupply"
			cmd["mode"] = String(g5p.get("mode", "station"))
		if r >= AREA_MIN_R:
			cmd["radius"] = snappedf(r, 0.1)
		_send(cmd, ctr, Color(0.4, 1.0, 0.5))


## Overlay: the auto_area circle while dragging, and a mode tag at the mouse (g4b_overlay).
func draw_g5(ci: CanvasItem, mouse_canvas: Vector2) -> void:
	if G6Modes.has_mode(mode):
		g6.draw(ci, mouse_canvas)
		return
	if mode == "" or not G5_MODES.has(mode):
		return
	var f := ThemeDB.fallback_font
	if area_from != null:
		var c: Vector2 = mv.world_to_screen(area_from)
		var e: Vector2 = mv.world_to_screen(area_to)
		var rr := c.distance_to(e)
		ci.draw_arc(c, maxf(rr, 4.0), 0.0, TAU, 48, Color(0.4, 1.0, 0.5, 0.9), 2.0)
		ci.draw_circle(c, maxf(rr, 4.0), Color(0.4, 1.0, 0.5, 0.12))
	var at: Vector2 = mouse_canvas + Vector2(16, 22)
	var tag := mode.replace("_", " ").to_upper()
	if mode == "assign_engineers":
		tag = "ASSIGN"
		ci.draw_arc(at - Vector2(16, 22), 10.0, 0.0, TAU, 24, Color(0.45, 0.85, 1.0), 2.0)
	ci.draw_string_outline(f, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
	ci.draw_string(f, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.7))


func on_right() -> bool:
	if mode != "" or wall_from != null or g6.dragging():
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
	var w = mv.get("_world")  # never mv.world: that getter forces a sim join
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
