extends CanvasLayer
## CanvasLayer whose `root` Control is sized to the viewport divided by the effective UI scale,
## so every HUD/menu panel scales without touching the game world.
## G5 (UI5a): effective scale = user UI Scale (75-150 %) x resolution factor (viewport height / 900,
## so 1600x900 = 1.0, 1920x1080 = 1.2, 2560x1440 = 1.6, 3840x2160 = 2.4), then clamped so the virtual
## canvas never drops below MIN_CANVAS (panels shrink before anything clips). At the default
## 1600x900 window the effective scale equals the user scale, as before.

const BASE_H := 900.0
const MIN_AUTO := 0.75
const MAX_AUTO := 3.0
const MIN_CANVAS := Vector2(1024, 576)
const SCALE_STEPS := [0.75, 0.9, 1.0, 1.1, 1.25, 1.5]

var root: Control
var ui_scale: float = 1.0        # the user setting
var effective: float = 1.0       # what is applied (read-only for callers)
var auto_res := true             # scale with resolution (off = user scale only, still clamped)


func _init() -> void:
	root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


func set_ui_scale(s: float) -> void:
	ui_scale = clampf(s, 0.5, 2.0)
	_fit()


static func effective_scale(vsize: Vector2, user: float, by_res: bool = true) -> float:
	var s := user
	if by_res:
		s *= clampf(vsize.y / BASE_H, MIN_AUTO, MAX_AUTO)
	return maxf(0.25, minf(s, minf(vsize.x / MIN_CANVAS.x, vsize.y / MIN_CANVAS.y)))


## The virtual canvas size the panels lay out in.
func canvas_size() -> Vector2:
	return root.size if root != null else Vector2.ZERO


func _fit() -> void:
	if root == null or not is_inside_tree():
		return
	var vs := get_viewport().get_visible_rect().size
	effective = effective_scale(vs, ui_scale, auto_res)
	scale = Vector2(effective, effective)
	root.position = Vector2.ZERO
	root.size = vs / effective
