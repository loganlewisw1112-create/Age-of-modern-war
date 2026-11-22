extends Node2D
## G7.1 FIRES71 (D5 kill zones + B4 FPF strips): paint fire sectors on the map. Started from the radial fire menu
## ("Sectors" slot) or start(). While active:
##   left drag            -> kz_paint for the selection {unit_ids, building_ids, apex = drag start, at = drag end}
##                           (the sim splits the arc across a group; one member = the whole sector)
##   Shift + left drag    -> fpf_paint: repaints the FPF strip of the wall face nearest the drag start (a -> b)
##   right click          -> kz_clear for the selection (auto zones apply again), then the tool closes
##   Esc                  -> close
## Clicks for "give one turret / one squad a sector": select (1) + radial pick (1) + drag (1) = 3.
## Display + input only: writes nothing but MatchView.issue() (the player's own commands).

const KillZone71 = preload("res://sim/systems/killzone71.gd")
const COL := Color(1.0, 0.85, 0.25, 0.9)
const COL_FPF := Color(1.0, 0.4, 0.15, 0.9)

var mv: Node = null
var active := false
var drag_from = null      # world-tile Vector2 while the button is down
var last_result: Dictionary = {}
var clicks := 0           # test hook: player actions spent in this tool


func _init() -> void:
	name = "KillZonePaint71"


## g71_attach.gd entry point (ORCH LAYERS, "over_units").
func setup(view: Node) -> void:
	mv = view
	z_index = 5   # FIRES71-6: the drag preview draws over the LP night tint (FacAtmo7 dark, z 3) + fog (z 4), like the order overlay


static func attach(view: Node) -> Node:
	var r = (load("res://presentation/ui71/killzone_paint.gd") as GDScript).new()
	r.name = "KillZonePaint71"
	r.z_index = 55
	view.add_child(r)
	r.mv = view
	return r


## Splits the selection into unit / building ids (own side only) for the kill-zone commands.
static func members(w: SimWorld, fid: int, sel: Array) -> Dictionary:
	var u := []
	var b := []
	for raw in sel:
		var e = w.entities.get(int(raw))
		if e == null or int(e.owner) != fid:
			continue
		if String(e.kind) == "building":
			b.append(int(raw))
		elif String(e.kind) == "unit":
			u.append(int(raw))
	u.sort()
	b.sort()
	return {"unit_ids": u, "building_ids": b}


static func paint_cmd(mem: Dictionary, apex: Vector2, at: Vector2) -> Dictionary:
	return {"type": "kz_paint", "unit_ids": mem.unit_ids, "building_ids": mem.building_ids,
		"apex": [snappedf(apex.x, 0.01), snappedf(apex.y, 0.01)], "at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01)]}


static func fpf_cmd(face: int, a: Vector2, b: Vector2) -> Dictionary:
	return {"type": "fpf_paint", "face": face, "a": [snappedf(a.x, 0.01), snappedf(a.y, 0.01)], "b": [snappedf(b.x, 0.01), snappedf(b.y, 0.01)]}


func start() -> bool:
	if mv == null:
		return false
	active = true
	drag_from = null
	queue_redraw()
	return true


func stop() -> void:
	active = false
	drag_from = null
	queue_redraw()


func _input(ev: InputEvent) -> void:
	if not active or mv == null:
		return
	if ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		stop()
		get_viewport().set_input_as_handled()
		return
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			drag_from = mv.mouse_world()
		elif drag_from != null:
			finish_drag(Vector2(drag_from), mv.mouse_world(), mb.shift_pressed)
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		var mem := members(mv.world, int(mv.player_fid), mv.selection)
		if not (mem.unit_ids as Array).is_empty() or not (mem.building_ids as Array).is_empty():
			clicks += 1
			last_result = mv.issue({"type": "kz_clear", "unit_ids": mem.unit_ids, "building_ids": mem.building_ids})
		stop()
		get_viewport().set_input_as_handled()


## One drag (a -> b): a sector for the selection, or (shift) the FPF strip of the face nearest a.
func finish_drag(a: Vector2, b: Vector2, shift: bool) -> Dictionary:
	drag_from = null
	clicks += 1
	var res := {}
	if shift:
		var face := KillZone71.face_of(mv.world, a)
		if face >= 0 and a.distance_to(b) >= 1.0:
			res = mv.issue(fpf_cmd(face, a, b))
	else:
		var mem := members(mv.world, int(mv.player_fid), mv.selection)
		if not (mem.unit_ids as Array).is_empty() or not (mem.building_ids as Array).is_empty():
			res = mv.issue(paint_cmd(mem, a, b))
	last_result = res
	queue_redraw()
	return res


func _process(_dt: float) -> void:
	if active:
		queue_redraw()


func _draw() -> void:
	if not active or mv == null:
		return
	var s: float = maxf(get_canvas_transform().get_scale().x, 0.01)
	var m: Vector2 = mv.mouse_world()
	draw_circle(mv.world_to_screen(m), 4.0 / s, COL)
	if drag_from == null:
		return
	var a := Vector2(drag_from)
	var col := COL_FPF if Input.is_key_pressed(KEY_SHIFT) else COL
	draw_line(mv.world_to_screen(a), mv.world_to_screen(m), col, 2.0 / s, true)
	if not Input.is_key_pressed(KEY_SHIFT):
		# preview wedge: default arc around the drag direction, out to the drag length
		var arc := deg_to_rad(float(Content.rules().get("g71_killzone", {}).get("arc_deg_default", 60.0)))
		var c := (m - a).angle()
		var r := a.distance_to(m)
		var pts := PackedVector2Array([mv.world_to_screen(a)])
		for i in 13:
			var t := c - arc * 0.5 + arc * float(i) / 12.0
			pts.append(mv.world_to_screen(a + Vector2(cos(t), sin(t)) * r))
		pts.append(mv.world_to_screen(a))
		draw_polyline(pts, col, 1.5 / s, true)
