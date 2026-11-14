extends Node2D
## G7.1 AIRFIX71 (A2 auto patrol routes): draw a loop of waypoints for the selected helicopters / VTOLs.
## start(): arms MatchView's point pick; every left click on the map adds a waypoint (and re-arms). Enter, or a right
## click once >= 2 points exist, issues {type: "air_patrol", unit_ids, points: [[x, y], ...]}; Escape cancels.
## The loop is drawn (dashed closing leg back to the first point) while drawing. Display + input only: it writes nothing
## but MatchView.issue() (the player's own command).
##
## Wiring: PatrolDraw71.attach(mv) adds this node to the match view; the hotkey action "air_patrol" (SHIFT+Y, change
## request to ORCH for hotkeys.gd) calls start() on it (mv.get_node("PatrolDraw71").start()).

const COL := Color(0.45, 0.85, 1.0, 0.9)
const COL_PT := Color(1.0, 1.0, 1.0, 0.95)

var mv: Node = null
var points: Array = []       # world-tile Vector2 waypoints
var active := false
var last_result: Dictionary = {}   # test hook: what the last issue() returned


static func attach(view: Node) -> Node:
	var r = (load("res://presentation/ui71/patrol_draw.gd") as GDScript).new()
	r.name = "PatrolDraw71"
	r.z_index = 50
	view.add_child(r)
	r.mv = view
	return r


## Aircraft (not jets / micro drones) among the player's selection.
static func patrol_ids(w: SimWorld, sel: Array) -> Array:
	var out := []
	for raw in sel:
		var e = w.entities.get(int(raw))
		if e == null or String(e.get("kind", "")) != "unit":
			continue
		var d := Content.unit(String(e.def))
		var ac := String(d.get("aircraft", ""))
		if ac != "" and ac != "micro" and ac != "jet":
			out.append(int(raw))
	out.sort()
	return out


## The command this tool issues for ids + pts (pure; tests use it).
static func make_cmd(ids: Array, pts: Array) -> Dictionary:
	var arr := []
	for p in pts:
		arr.append([snappedf(float(p.x), 0.01), snappedf(float(p.y), 0.01)])
	return {"type": "air_patrol", "unit_ids": ids.duplicate(), "points": arr}


func start() -> bool:
	if mv == null or patrol_ids(mv.world, mv.selection).is_empty():
		return false
	points.clear()
	active = true
	_arm()
	queue_redraw()
	return true


func cancel() -> void:
	active = false
	points.clear()
	if mv != null and mv.point_pick_armed():
		mv.cancel_point_pick()
	queue_redraw()


func _arm() -> void:
	mv.begin_point_pick(Callable(self, "_on_point"))


func _on_point(p: Vector2) -> void:
	if not active:
		return
	points.append(Vector2(p))
	_arm()
	queue_redraw()


## Issues the route (>= 2 points) for the selected rotorcraft; returns MatchView.issue()'s result ({} if not issued).
func finish() -> Dictionary:
	var ids: Array = patrol_ids(mv.world, mv.selection) if mv != null else []
	var res := {}
	if active and points.size() >= 2 and not ids.is_empty():
		res = mv.issue(make_cmd(ids, points))
	last_result = res
	cancel()
	return res


func _process(_dt: float) -> void:
	if active and mv != null and not mv.point_pick_armed():
		# MatchView disarmed the pick (right click): finish the route if it has a loop, else cancel
		if points.size() >= 2:
			finish()
		else:
			cancel()


func _unhandled_key_input(ev: InputEvent) -> void:
	if not active or not (ev is InputEventKey) or not ev.pressed:
		return
	match (ev as InputEventKey).keycode:
		KEY_ENTER, KEY_KP_ENTER:
			finish()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if not active or mv == null or points.is_empty():
		return
	var sp := []
	for p in points:
		sp.append(mv.world_to_screen(p))
	for i in range(1, sp.size()):
		draw_line(sp[i - 1], sp[i], COL, 2.0, true)
	if sp.size() >= 2:
		draw_dashed_line(sp[sp.size() - 1], sp[0], COL, 2.0, 8.0)
	for q in sp:
		draw_circle(q, 4.0, COL_PT)
