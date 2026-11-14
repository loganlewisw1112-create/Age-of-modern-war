extends Node2D
## G7.1 CONTROL71 (A4): a crisp outline in team colour on whatever a click would select right now (the entity the
## cursor is over: unit / vehicle / wall-walk trooper = a ring at the feet plus corner brackets round the body,
## building = its footprint box). Presentation only: reads MatchView.hover_entity() (the HUD's per-frame hover pick,
## reused, so it adds no pick of its own), draws one small polyline set, redraws only while something is hovered.
const ViewUtil = preload("res://presentation/view/view_util.gd")

var mv: Node = null
var _tgt = null   # copy of the hovered entity, refreshed only when the sim is idle
var _shown_id := -1        # entity id outlined last frame (so one clearing redraw happens when it goes away)
var _last_hit := {}        # test hook: {id, kind, rect} of the last outline drawn


func setup(view: Node) -> void:
	mv = view
	z_index = 6
	set_process(true)


func _process(_delta: float) -> void:
	# Never read the world while a sim step is in flight (forced join; PERFDRAW71 seq 64): keep the last outline.
	if mv != null and mv.has_method("sim_busy") and mv.sim_busy():
		return
	var e = _target()
	_tgt = null if e == null else (e as Dictionary).duplicate()
	var id := -1 if e == null else int(e.id)
	if id >= 0 or _shown_id >= 0:
		queue_redraw()
	_shown_id = id


## The entity to outline, or null (no hover, over the HUD, in a drag, placing a building, hidden entity).
func _target():
	if mv == null or mv.get("_world") == null or not mv.has_method("hover_entity"):
		return null
	if mv.has_method("marquee_rect") and mv.marquee_rect() != null:
		return null
	if String(mv.get("placing_def")) != "":
		return null
	var vp := get_viewport()
	if vp == null or vp.gui_get_hovered_control() != null:
		return null
	return mv.hover_entity()


func _draw() -> void:
	var e = _tgt   # picked in _process on a frame with no step in flight (a copy: safe to read mid-step)
	_last_hit = {}
	if e == null:
		return
	var z: float = 1.0
	var cam = mv.get("camera")
	if cam != null:
		z = maxf(float(cam.zoom.x), 0.05)
	var col: Color = _color_of(e)
	var w := 2.0 / z           # constant ~2 screen px at every zoom (crisp)
	var under := Color(0, 0, 0, 0.65)
	if String(e.kind) == "unit":
		var r := float(Content.unit(e.def).get("radius", 0.3))
		var feet: Vector2 = mv.entity_canvas_pos(e)
		var rx := 12.0 + r * 26.0
		var ring := _ellipse(feet, rx, rx * 0.5)
		draw_polyline(ring, under, w + 2.0 / z, true)
		draw_polyline(ring, col, w, true)
		var body := feet + Vector2(0.0, -10.0 - r * 12.0)
		var hw := 7.0 + r * 14.0
		var hh := 12.0 + r * 14.0
		var rect := Rect2(body - Vector2(hw, hh), Vector2(hw, hh) * 2.0)
		_brackets(rect, under, w + 2.0 / z, min(hw, hh) * 0.55)
		_brackets(rect, col, w, min(hw, hh) * 0.55)
		_last_hit = {"id": int(e.id), "kind": "unit", "rect": rect}
	elif String(e.kind) == "building":
		var o: Vector2i = e.cell
		var s := int(e.size)
		var hm: Dictionary = cam.height_map() if cam != null and cam.has_method("height_map") else {}
		var g := PackedVector2Array()
		for c in [Vector2(o), Vector2(o.x + s, o.y), Vector2(o.x + s, o.y + s), Vector2(o.x, o.y + s)]:
			g.append(ViewUtil.world_to_screen_h(hm, c))
		var lift := Vector2(0.0, -ViewUtil.PICK_BLD_LIFT * s)
		var top := PackedVector2Array()
		for q in g:
			top.append(q + lift)
		var gc := g.duplicate()
		gc.append(g[0])
		var tc := top.duplicate()
		tc.append(top[0])
		draw_polyline(gc, under, w + 2.0 / z, true)
		draw_polyline(gc, col, w, true)
		draw_polyline(tc, col, w, true)
		for i in 4:
			draw_line(g[i], top[i], col, w, true)
		_last_hit = {"id": int(e.id), "kind": "building", "rect": Rect2(g[3], Vector2.ZERO).expand(g[1]).expand(top[0]).expand(top[2])}
	else:
		var p: Vector2 = mv.entity_canvas_pos(e)
		var ring2 := _ellipse(p, 22.0, 11.0)
		draw_polyline(ring2, under, w + 2.0 / z, true)
		draw_polyline(ring2, col, w, true)
		_last_hit = {"id": int(e.id), "kind": "other", "rect": Rect2(p - Vector2(22, 11), Vector2(44, 22))}


func _color_of(e: Dictionary) -> Color:
	var c := Color(0.9, 0.9, 0.9)
	if mv != null and mv.has_method("team_color") and int(e.get("owner", -1)) >= 0:
		c = mv.team_color(int(e.owner))
	return c.lightened(0.25)


static func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 25:
		var a := TAU * float(i) / 24.0
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


func _brackets(r: Rect2, col: Color, w: float, ln: float) -> void:
	var tl := r.position
	var tr := Vector2(r.end.x, r.position.y)
	var br := r.end
	var bl := Vector2(r.position.x, r.end.y)
	draw_polyline(PackedVector2Array([tl + Vector2(0, ln), tl, tl + Vector2(ln, 0)]), col, w, true)
	draw_polyline(PackedVector2Array([tr - Vector2(ln, 0), tr, tr + Vector2(0, ln)]), col, w, true)
	draw_polyline(PackedVector2Array([br - Vector2(0, ln), br, br - Vector2(ln, 0)]), col, w, true)
	draw_polyline(PackedVector2Array([bl + Vector2(ln, 0), bl, bl - Vector2(0, ln)]), col, w, true)
