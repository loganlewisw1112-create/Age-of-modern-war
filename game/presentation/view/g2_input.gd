extends RefCounted
## G2 order modes and smart right-click additions (owner: agent D2). Owned by MatchView as `g2`.
## Modes: "patrol" (Q), "guard", "repair", "mission" (officer). Everything reaches the sim only
## through mv.issue(cmd). Contract: CONTRACTS_G2 sections 3-5.

const G2 = preload("res://presentation/view/g2_data.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")
const AB = preload("res://sim/systems/ammo_bearer.gd")   # G6.1 (INTEG61): bearer Join squad

var mv
var mode := ""             # "" | patrol | guard | repair | mission
var unit_ids: Array = []
var points: Array = []     # Vector2 world points collected so far
var mission := ""
var officer_id := -1
var risk := "medium"
var hint_text := ""
var hint_until := 0


func active() -> bool:
	return mode != ""


func arm(m: String, params: Dictionary = {}) -> void:
	mode = m
	points = []
	unit_ids = (params.get("unit_ids", []) as Array).duplicate()
	mission = String(params.get("mission", ""))
	officer_id = int(params.get("officer_id", -1))
	risk = String(params.get("risk", risk))
	mv.attack_move_armed = false
	mv.cancel_placement()


func cancel() -> void:
	mode = ""
	points = []


func flash(text: String, secs: float = 2.5) -> void:
	hint_text = text
	hint_until = Time.get_ticks_msec() + int(secs * 1000.0)


func status_text() -> String:
	match mode:
		"patrol":
			return "PATROL: click waypoints (Shift adds more); right-click/Enter ends; Esc cancels [%d]" % points.size()
		"guard":
			return "GUARD: click a friendly unit or building. Esc cancels."
		"repair":
			return "REPAIR: click a damaged vehicle/building or the ruined bridge. Esc cancels."
		"bearer_join":
			return "JOIN SQUAD: click a member of an own squad. Esc cancels."
		"mission":
			if mission == "patrol_route":
				return "%s (%s risk): Shift+click route points, Enter confirms, Esc cancels [%d]" % [G2.mission_name(mission), risk, points.size()]
			return "%s (%s risk): click the target on the map. Esc cancels." % [G2.mission_name(mission), risk]
	if Time.get_ticks_msec() < hint_until:
		return hint_text
	return ""


# ---------------------------------------------------------------- input hooks (from MatchView)
func on_left(p: Vector2, shift: bool) -> bool:
	if mode == "":
		return false
	match mode:
		"patrol":
			points.append(p)
			if not shift:
				_finish_patrol()
		"guard":
			var t = mv.entity_at(p, true)
			if t != null and t.kind in ["unit", "building"] and int(t.owner) == mv.player_fid and not unit_ids.has(int(t.id)):
				mv.issue({"type": "guard", "unit_ids": _live_ids(), "target_id": int(t.id)})
				mv.fx_layer.add_marker(t.pos, Color(0.45, 0.75, 1.0))
				cancel()
			else:
				flash("Guard needs a friendly unit or building.")
		"repair":
			var rt := _repair_target(p, mv.entity_at(p, true))
			if not rt.is_empty():
				_issue_repair(_live_ids(), rt)
				cancel()
			else:
				flash("Nothing to repair there.")
		"mission":
			points.append(p)
			if mission != "patrol_route" or not shift:
				_finish_mission()
		"bearer_join":
			var sq = mv.entity_at(p, true)
			if _squad_target(sq, unit_ids):
				_issue_join(_live_ids(), sq)
				cancel()
			else:
				flash("Join squad needs a member of an own squad.")
	return true


## G6.1 (INTEG61, BEARER61 CR seq 332): t is an own non-bearer unit in a squad, not one of `ids`.
func _squad_target(t, ids: Array) -> bool:
	return t != null and t.kind == "unit" and int(t.owner) == mv.player_fid and int(t.get("squad", -1)) >= 0 		and not AB.is_bearer(t) and not ids.has(int(t.id))


func _issue_join(ids: Array, t) -> void:
	mv.issue({"type": "join_squad", "unit_ids": ids, "squad_unit_id": int(t.id)})
	mv.fx_layer.add_marker(t.pos, Color(0.95, 0.8, 0.3))


func on_right(_p: Vector2, _shift: bool) -> bool:
	if mode == "":
		return false
	if mode == "patrol" and not points.is_empty():
		_finish_patrol()
	elif mode == "mission" and mission == "patrol_route" and not points.is_empty():
		_finish_mission()
	else:
		cancel()
	return true


func on_key(kc: int) -> bool:
	if mode == "":
		return false
	if kc == KEY_ENTER or kc == KEY_KP_ENTER:
		if mode == "patrol" and not points.is_empty():
			_finish_patrol()
		elif mode == "mission" and not points.is_empty():
			_finish_mission()
		return true
	if kc == KEY_ESCAPE:
		cancel()
		return true
	return false


## Called by MatchView.smart_command before the G1 rules. Returns true when it issued something.
func smart(p: Vector2, shift: bool, t, units: Array, engineers: Array) -> bool:
	var w = mv.world
	var pf: int = mv.player_fid
	if t != null and t.kind in ["unit", "building"] and w.is_enemy(pf, int(t.owner)):
		return false
	# G6.1 (INTEG61): only ammo bearers selected + right-click an own squad member = Join squad
	if not units.is_empty() and _squad_target(t, units) and units.all(func(x): return AB.is_bearer(w.entities.get(int(x)))):
		_issue_join(units, t)
		return true
	var on_bridge: bool = G2.is_bridge_cell(w, Vector2i(floori(p.x), floori(p.y)))
	if not engineers.is_empty():
		var rt := _repair_target(p, t)
		if not rt.is_empty() and not engineers.has(int(rt.id)):
			_issue_repair(engineers, rt)
			var rest := units.filter(func(x): return not engineers.has(x))
			if not rest.is_empty():
				mv.issue({"type": "move", "unit_ids": rest, "target": p})
			return true
	var b: Dictionary = G2.bridge(w)
	if on_bridge and not b.is_empty() and b.kind == "structure" and G2.bridge_state(w) != "ruined":
		var combat := units.filter(func(x): return not engineers.has(x))
		if combat.is_empty():
			return false
		if shift:
			mv.issue({"type": "attack", "unit_ids": combat, "target_id": int(b.id)})
			mv.fx_layer.add_marker(p, Color(1.0, 0.25, 0.2))
			flash("Demolishing the river bridge.")
			return true
		flash("Shift+right-click to demolish the bridge.")
	return false


func _repair_target(p: Vector2, t) -> Dictionary:
	var w = mv.world
	if t != null and t.kind in ["unit", "building"] and G2.repairable(w, mv.player_fid, t):
		return t
	if G2.is_bridge_cell(w, Vector2i(floori(p.x), floori(p.y))):
		var b: Dictionary = G2.bridge(w)
		if not b.is_empty() and G2.repairable(w, mv.player_fid, b):
			return b
	return {}


func _issue_repair(ids: Array, t: Dictionary) -> void:
	mv.issue({"type": "repair", "unit_ids": ids, "target_id": int(t.id)})
	mv.fx_layer.add_marker(t.pos, Color(0.5, 1.0, 0.7))


func _live_ids() -> Array:
	return unit_ids.filter(func(x): return mv.world.entities.has(int(x)))


func _finish_patrol() -> void:
	var ids := _live_ids()
	var pts := points.duplicate()
	if ids.is_empty() or pts.is_empty():
		cancel()
		return
	if pts.size() == 1:
		var c := Vector2.ZERO
		for id in ids:
			c += mv.world.entities[int(id)].pos
		pts.push_front(c / ids.size())
	mv.issue({"type": "patrol", "unit_ids": ids, "points": pts})
	for q in pts:
		mv.fx_layer.add_marker(q, Color(0.4, 0.85, 1.0))
	cancel()


func _finish_mission() -> void:
	if points.is_empty() or not mv.world.entities.has(officer_id):
		cancel()
		return
	var cmd := {"type": "set_mission", "officer_id": officer_id, "mission": mission,
		"target": points[0], "radius": 6.0, "risk": risk}
	if mission == "patrol_route":
		var pts := points.duplicate()
		if pts.size() == 1:
			pts.push_front(mv.world.entities[officer_id].pos)
		cmd.points = pts
	mv.issue(cmd)
	mv.fx_layer.add_marker(points[0], Color(1.0, 0.78, 0.25))
	cancel()


# ---------------------------------------------------------------- preview (drawn by g2_overlay "over")
func draw_preview(ci: CanvasItem) -> void:
	var cur: Vector2 = mv.mouse_world()
	var cs: Vector2 = mv.world_to_screen(cur)
	var col := Color(0.4, 0.85, 1.0) if mode != "mission" else Color(1.0, 0.78, 0.25)
	if mode == "patrol" or (mode == "mission" and mission == "patrol_route"):
		var prev = null
		for i in points.size():
			var s: Vector2 = mv.world_to_screen(points[i])
			if prev != null:
				_dashed(ci, prev, s, col)
			ci.draw_circle(s, 5.0, Color(0, 0, 0, 0.6))
			ci.draw_circle(s, 3.5, col)
			prev = s
		if prev != null:
			_dashed(ci, prev, cs, Color(col.r, col.g, col.b, 0.6))
		ci.draw_circle(cs, 3.0, Color(col.r, col.g, col.b, 0.7))
	elif mode == "mission":
		var poly := PackedVector2Array()
		for i in 41:
			var a := TAU * i / 40.0
			poly.append(mv.world_to_screen(cur + Vector2(cos(a), sin(a)) * 6.0))
		ci.draw_polyline(poly, Color(col.r, col.g, col.b, 0.8), 1.5)
		ci.draw_line(cs + Vector2(-8, 0), cs + Vector2(8, 0), col, 1.5)
		ci.draw_line(cs + Vector2(0, -5), cs + Vector2(0, 5), col, 1.5)
	elif mode == "guard" or mode == "repair":
		ci.draw_arc(cs, 9.0, 0, TAU, 20, col if mode == "guard" else Color(0.5, 1.0, 0.7), 2.0)
	var txt := status_text() if mode != "" else _hover_hint(cur)
	if txt != "":
		_label(ci, cs + Vector2(16, 18), txt)


## Context hint while hovering with no order mode armed (bridge demolition, smart repair).
func _hover_hint(p: Vector2) -> String:
	if Time.get_ticks_msec() < hint_until:
		return hint_text
	var units: Array = mv._own_units_in_selection()
	if units.is_empty():
		return ""
	var w = mv.world
	var on_bridge: bool = G2.is_bridge_cell(w, Vector2i(floori(p.x), floori(p.y)))
	var engineers: Array = mv._own_engineers_in_selection()
	if not engineers.is_empty():
		var rt := _repair_target(p, mv.entity_at(p, true))
		if not rt.is_empty():
			return "Right-click: repair" + (" the bridge" if G3.is_bridge(String(rt.def)) else "")
	if on_bridge and engineers.size() < units.size() and G2.bridge_state(w) != "ruined":
		return "River bridge: Shift+right-click to demolish"
	return ""


func _dashed(ci: CanvasItem, a: Vector2, b: Vector2, col: Color) -> void:
	var segs := maxi(1, int(a.distance_to(b) / 8.0))
	for i in segs:
		if i % 2 == 0:
			ci.draw_line(a.lerp(b, float(i) / segs), a.lerp(b, float(i + 1) / segs), col, 1.5)


func _label(ci: CanvasItem, at: Vector2, txt: String) -> void:
	var z: float = mv.camera.zoom.x
	ci.draw_set_transform(at, 0.0, Vector2.ONE / z)
	var font := ThemeDB.fallback_font
	var fs := 14
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_rect(Rect2(Vector2(-4, -2), Vector2(tw + 8, fs + 7)), Color(0.05, 0.06, 0.05, 0.85))
	ci.draw_string(font, Vector2(0, fs), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.86, 0.45))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
