extends Control
## G8 PRES8: director-cam picture-in-picture overlay (presentation only).

var _tag := ""
var _focus := Vector2.ZERO
var _t := 0.0
const HOLD_S := 4.0


static func attach(mv: Node, focus: Vector2, tag: String) -> Control:
	var p: Control = (load("res://presentation/pres8/pres8_pip.gd") as GDScript).new()
	p._focus = focus
	p._tag = tag
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = 96
	layer.name = "Pres8PipLayer"
	layer.add_child(p)
	mv.add_child(layer)
	p.tree_exiting.connect(func(): if is_instance_valid(layer): layer.queue_free())
	return p


func retarget(focus: Vector2, tag: String) -> void:
	_focus = focus
	_tag = tag
	_t = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t >= HOLD_S:
		queue_free()
		get_parent().queue_free()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var w := clampf(vp.x * 0.28, 220.0, 360.0)
	var h := w * 0.56
	var m := 12.0
	var r := Rect2(vp.x - w - m, vp.y - h - m, w, h)
	draw_rect(r, Color(0.02, 0.03, 0.04, 0.92))
	draw_rect(r.grow(-2), Color(0.08, 0.1, 0.12, 0.95))
	draw_rect(r, Color(0.85, 0.55, 0.2, 0.9), false, 2.0)
	var label := "DIRECTOR  %s" % _tag.to_upper()
	if _focus != Vector2.ZERO:
		label += "  @(%.0f,%.0f)" % [_focus.x, _focus.y]
	var font := ThemeDB.fallback_font
	var fs := 14
	draw_string(font, r.position + Vector2(8, 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.8, 0.45))