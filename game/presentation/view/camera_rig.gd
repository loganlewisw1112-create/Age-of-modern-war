extends Camera2D
## Fixed-isometric RTS camera (owner: agent D). Pan bounded to the map diamond's bounding box,
## zoom 0.5x-2.5x with the point under the cursor kept fixed.
## G3b (UI4): bounds come from map.w/h (96, 160, 256 maps); the zoom-out floor scales with the
## map so a 256x256 map can be viewed whole-ish; edge_pan_speed() scales with map size.

## G6 (ELEV-VIEW): on a map with height the pan bounds reach up by the top level's lift, and pick() /
## pick_canvas() return the world tile position of the ground actually drawn under a viewport / canvas point
## (raised tiles, ramps and cliff faces pick the cell on top; flat maps: the old screen_to_world).
const ViewUtil = preload("res://presentation/view/view_util.gd")
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5

var mv
var _bounds := Rect2()
var zoom_min := ZOOM_MIN
var _map_span := 96.0


func setup(view: Node2D) -> void:
	mv = view
	var w := float(mv.world.map.w)
	var h := float(mv.world.map.h)
	# map diamond: x in [-h*32, w*32], y in [0, (w+h)*16]
	_bounds = Rect2(Vector2(-h * 32.0, 0.0), Vector2((w + h) * 32.0, (w + h) * 16.0))
	if mv.world.map is Dictionary and ViewUtil.has_height(mv.world.map):
		var up := ViewUtil.lift_px(ViewUtil.MAX_LEVEL)
		_bounds = Rect2(_bounds.position - Vector2(0.0, up), _bounds.size + Vector2(0.0, up))
	_map_span = maxf(w, h)
	zoom_min = clampf(ZOOM_MIN * 96.0 / maxf(1.0, _map_span), 0.15, ZOOM_MIN)
	position_smoothing_enabled = false
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	zoom = Vector2.ONE
	make_current()


func tick(_delta: float) -> void:
	_clamp()


func center_on(screen_pos: Vector2) -> void:
	position = screen_pos
	_clamp()


func pan_screen(viewport_delta: Vector2) -> void:
	position += viewport_delta / zoom.x
	_clamp()


## Edge/keyboard pan speed in viewport px/s at zoom 1 (900 on River Crossing, ~1.3x on 160,
## ~1.6x on 256). Callers divide by zoom as before.
func edge_pan_speed() -> float:
	return 900.0 * sqrt(maxf(1.0, _map_span / 96.0))


func set_zoom_level(z: float) -> void:
	z = clampf(z, zoom_min, ZOOM_MAX)
	zoom = Vector2(z, z)
	_clamp()


## Zoom by factor f keeping the canvas point under viewport position vp fixed.
func zoom_at(vp: Vector2, f: float) -> void:
	var vs := get_viewport_rect().size
	var before := position + (vp - vs * 0.5) / zoom.x
	var z := clampf(zoom.x * f, zoom_min, ZOOM_MAX)
	zoom = Vector2(z, z)
	position = before - (vp - vs * 0.5) / z
	_clamp()


## G6: world tile position of the drawn ground under viewport position vp.
func pick(vp: Vector2) -> Vector2:
	return pick_canvas(get_viewport().get_canvas_transform().affine_inverse() * vp)


## G6: world tile position of the drawn ground under canvas position s.
func pick_canvas(s: Vector2) -> Vector2:
	return ViewUtil.pick_world(height_map(), s)


## The drawn map's height layer ({} = flat): the terrain layer's cached copy (safe during a sim step).
func height_map() -> Dictionary:
	var tl = mv.get("terrain_layer") if mv != null else null
	if tl != null and tl.has_method("height_map"):
		return tl.height_map()
	return {}


func _clamp() -> void:
	position.x = clampf(position.x, _bounds.position.x, _bounds.end.x)
	position.y = clampf(position.y, _bounds.position.y, _bounds.end.y)
