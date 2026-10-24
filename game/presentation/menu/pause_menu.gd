extends Control
## Pause menu overlay (owner: agent E): resume, save, load, UI scale, quit to menu.

signal resume_requested
signal save_requested(path: String)
signal load_requested(path: String)
signal menu_requested
signal ui_scale_changed(s: float)

const HT = preload("res://presentation/hud/hud_theme.gd")

var _status: Label
var _save_btn: Button
var _load_btn: Button
var _scale_opt: OptionButton
var _save_ok: bool = false
var editor_test := false   # set by main.gd before add_child: an editor test play -> "Back to editor"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(HT.make_label("PAUSED", HT.AMBER, 26))
	var resume := _btn("Resume", v)
	resume.pressed.connect(func(): resume_requested.emit())
	_save_btn = _btn("Save game (slot 1)", v)
	_save_btn.pressed.connect(func(): save_requested.emit("user://saves/slot_1.sav"))
	_load_btn = _btn("Load game (slot 1)", v)
	_load_btn.pressed.connect(func(): load_requested.emit("user://saves/slot_1.sav"))
	var sc := HBoxContainer.new()
	v.add_child(sc)
	sc.add_child(HT.make_label("UI scale  ", HT.DIM, 14))
	_scale_opt = OptionButton.new()
	for s in ["1.0", "1.25", "1.5"]:
		_scale_opt.add_item(s)
	_scale_opt.item_selected.connect(_on_scale)
	sc.add_child(_scale_opt)
	var quit := _btn("Back to editor" if editor_test else "Quit to main menu", v)
	quit.pressed.connect(func(): menu_requested.emit())
	_status = HT.make_label("", HT.YELLOW, 14)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	v.add_child(HT.make_label("F5 quick save   F9 quick load", HT.DIM, 13))
	refresh()


func _btn(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	parent.add_child(b)
	return b


func _on_scale(i: int) -> void:
	var vals := [1.0, 1.25, 1.5]
	ui_scale_changed.emit(vals[i])


func set_scale_index(s: float) -> void:
	var vals := [1.0, 1.25, 1.5]
	for i in vals.size():
		if is_equal_approx(vals[i], s):
			_scale_opt.select(i)


func set_save_system_available(ok: bool) -> void:
	_save_ok = ok
	refresh()


func refresh() -> void:
	if _save_btn == null:
		return
	_save_btn.disabled = not _save_ok
	_load_btn.disabled = (not _save_ok) or (not FileAccess.file_exists("user://saves/slot_1.sav"))
	if not _save_ok:
		_status.text = "Save system pending: save and load are disabled."


func set_status(msg: String, ok: bool = true) -> void:
	_status.text = msg
	_status.add_theme_color_override("font_color", HT.GREEN if ok else HT.RED)
	refresh()
