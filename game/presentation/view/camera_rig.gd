extends Camera2D
## Fixed-isometric RTS camera (owner: agent D). Pan bounded to the map diamond's bounding box,
## zoom 0.5x-2.5x with the point under the cursor kept fixed.

const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5

var mv
var _bounds := Rect2()


func setup(view: Node2D) -> void:
	mv = view
	var w := float(mv.world.map.w)
	var h := float(mv.world.map.h)
	# map diamond: x in [-h*32, w*32], y in [0, (w+h)*16]
	_bounds = Rect2(Vector2(-h * 32.0, 0.0), Vector2((w + h) * 32.0, (w + h) * 16.0))
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


func set_zoom_level(z: float) -> void:
	z = clampf(z, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
	_clamp()


## Zoom by factor f keeping the canvas point under viewport position vp fixed.
func zoom_at(vp: Vector2, f: float) -> void:
	var vs := get_viewport_rect().size
	var before := position + (vp - vs * 0.5) / zoom.x
	var z := clampf(zoom.x * f, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
	position = before - (vp - vs * 0.5) / z
	_clamp()


func _clamp() -> void:
	position.x = clampf(position.x, _bounds.position.x, _bounds.end.x)
	position.y = clampf(position.y, _bounds.position.y, _bounds.end.y)
