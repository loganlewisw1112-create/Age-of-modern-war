extends Control
## G7 OPSUI7: tablet screen layer. overlay = false paints the screen background (put it first, behind the content);
## overlay = true paints scan lines, the sweep, the vignette, corner brackets and a corner caption ABOVE the content
## (mouse transparent). Display only.

const S = preload("res://presentation/ui7/ops_style.gd")

var overlay := false
var label := ""
var t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if overlay and is_visible_in_tree():
		t += delta
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if not overlay:
		S.screen_bg(self, r)
		return
	S.scanlines(self, r, t)
	S.brackets(self, r.grow(-4.0), Color(S.PHOS, 0.7))
	if label != "":
		S.text(self, Vector2(r.end.x - S.text_w(label, 11) - 12.0, r.end.y - 9.0), label, S.DIM, 11)
