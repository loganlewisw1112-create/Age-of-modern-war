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
## G7 (SCALE7): zoom-out floor on maps over 256 a side (512: 0.094, 768: 0.08); <= 256 keep the 0.15 floor.
const ZOOM_MIN_HUGE := 0.08

var mv
var _bounds := Rect2()
var zoom_min := ZOOM_MIN
var _map_span := 96.0


func setup(view: Node2D) -> void:
	mv = view
	var world = mv.get("_world")  # never mv.world: that getter forces a sim join
	var w := float(world.map.w)
	var h := float(world.map.h)
	# map diamond: x in [-h*32, w*32], y in [0, (w+h)*16]
	_bounds = Rect2(Vector2(-h * 32.0, 0.0), Vector2((w + h) * 32.0, (w + h) * 16.0))
	if world.map is Dictionary and ViewUtil.has_height(world.map):
		var up := ViewUtil.lift_px(ViewUtil.MAX_LEVEL)
		_bounds = Rect2(_bounds.position - Vector2(0.0, up), _bounds.size + Vector2(0.0, up))
	_map_span = maxf(w, h)
	zoom_min = clampf(ZOOM_MIN * 96.0 / maxf(1.0, _map_span), 0.15 if _map_span <= 256.0 else ZOOM_MIN_HUGE, ZOOM_MIN)
	position_smoothing_enabled = false
	user_pan_mult = _settings_pan_mult()
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	zoom = Vector2.ONE
	make_current()


## The Settings "Edge-pan speed" option (a fraction, 1.0 = 100%); 1.0 when unreadable.
static func _settings_pan_mult() -> float:
	var St = load("res://presentation/menu/settings.gd")
	if St == null or not St.has_method("get_value"):
		return 1.0
	var v = St.get_value("game", "edge_pan_speed")
	return clampf(float(v), 0.25, 3.0) if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) else 1.0


func tick(_delta: float) -> void:
	_clamp()


func center_on(screen_pos: Vector2) -> void:
	position = screen_pos
	_clamp()


func pan_screen(viewport_delta: Vector2) -> void:
	position += viewport_delta / zoom.x
	_clamp()


## Edge/keyboard pan speed in viewport px/s at zoom 1 (G7.1 CONTROL71: faster, 900 -> 1500 on River Crossing, ~1.3x on
## 160, ~1.6x on 256, times the Settings "Edge-pan speed" option). Callers divide by zoom as before.
const PAN_BASE := 1500.0
const EDGE_MARGIN := 8.0        # px: the cursor this close to a screen edge pans (AoE-style)
const DRAG_MULT := 1.3          # middle-drag pans a little faster than 1:1
const FAST_MULT := 2.0          # Shift held: keys / edge pan twice as fast
var user_pan_mult := 1.0


func edge_pan_speed() -> float:
	return PAN_BASE * sqrt(maxf(1.0, _map_span / 96.0)) * user_pan_mult


## G7.1 CONTROL71: unit pan direction for a cursor at m in a viewport of size vs (zero when not on an edge band).
static func edge_dir(m: Vector2, vs: Vector2, margin: float = EDGE_MARGIN) -> Vector2:
	var d := Vector2.ZERO
	if not Rect2(Vector2.ZERO, vs).has_point(m):
		return d
	if m.x < margin: d.x = -1.0
	elif m.x > vs.x - margin: d.x = 1.0
	if m.y < margin: d.y = -1.0
	elif m.y > vs.y - margin: d.y = 1.0
	return d


## G7.1 CONTROL71: camera position after zooming from z0 to z1 with the canvas point under viewport position vp held
## fixed (the camera is drag-centred: canvas point = position + (vp - vs/2) / zoom).
static func zoom_anchor(pos: Vector2, z0: float, z1: float, vp: Vector2, vs: Vector2) -> Vector2:
	return pos + (vp - vs * 0.5) / z0 - (vp - vs * 0.5) / z1


func set_zoom_level(z: float) -> void:
	z = clampf(z, zoom_min, ZOOM_MAX)
	zoom = Vector2(z, z)
	_clamp()


## Zoom by factor f keeping the canvas point under viewport position vp fixed.
func zoom_at(vp: Vector2, f: float) -> void:
	var vs := get_viewport_rect().size
	var z0 := zoom.x
	var z := clampf(z0 * f, zoom_min, ZOOM_MAX)
	position = zoom_anchor(position, z0, z, vp, vs)
	zoom = Vector2(z, z)
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


## G8 ROT8: pan bounds = union of the map diamond under all four facings so rotate never clamps off-map.
func recompute_bounds() -> void:
	if mv == null:
		return
	var world = mv.get("_world")
	if world == null or not (world.map is Dictionary):
		return
	var w := float(world.map.w)
	var h := float(world.map.h)
	var corners := [Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	var saved := ViewUtil.view_facing
	for f in 4:
		ViewUtil.view_facing = f
		for c in corners:
			var s: Vector2 = ViewUtil.iso(c)
			min_p = min_p.min(s)
			max_p = max_p.max(s)
	ViewUtil.view_facing = saved
	if world.map is Dictionary and ViewUtil.has_height(world.map):
		var up := ViewUtil.lift_px(ViewUtil.MAX_LEVEL)
		min_p.y -= up
	_bounds = Rect2(min_p, max_p - min_p)
	_clamp()


func _clamp() -> void:
	position.x = clampf(position.x, _bounds.position.x, _bounds.end.x)
	position.y = clampf(position.y, _bounds.position.y, _bounds.end.y)
