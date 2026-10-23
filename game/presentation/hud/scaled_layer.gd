extends CanvasLayer
## CanvasLayer whose `root` Control is sized to the viewport divided by the UI scale,
## so every HUD/menu panel can be scaled 1.0/1.25/1.5 without touching the game world.

var root: Control
var ui_scale: float = 1.0


func _init() -> void:
	root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


func set_ui_scale(s: float) -> void:
	ui_scale = maxf(0.5, s)
	scale = Vector2(ui_scale, ui_scale)
	_fit()


func _fit() -> void:
	if root == null or not is_inside_tree():
		return
	root.position = Vector2.ZERO
	root.size = get_viewport().get_visible_rect().size / ui_scale
