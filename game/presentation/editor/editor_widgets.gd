extends RefCounted
## Small UI builders shared by the editor tabs (owner: ED1; ED2 tabs may use them too).

const HT = preload("res://presentation/hud/hud_theme.gd")

const TERRAIN_LABELS := ["Grass", "Dirt", "Road", "Forest", "River water", "Bridge", "Ford", "Ridge",
	"Building (solid)", "Shallow water", "Deep water", "Beach", "Cliff", "Hill"]
const TERRAIN_COLORS := ["5f8a3c", "8a6e4a", "7d7a72", "2f5a26", "3d6fa0", "8a6a3a", "6a8fa8", "6b6358",
	"4a4440", "5a8fb8", "24497a", "d2c08a", "514a43", "86945a"]
const BIOME_LABELS := ["Temperate", "Desert", "Snow", "Wasteland"]
const BIOME_COLORS := ["5f8a3c", "c8b070", "e6eef2", "6d6250"]


static func header(parent: Control, text: String) -> Label:
	var l := HT.make_label(text, HT.AMBER, 16)
	parent.add_child(l)
	return l


static func note(parent: Control, text: String) -> Label:
	var l := HT.make_label(text, HT.DIM, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(220, 0)
	parent.add_child(l)
	return l


static func button(parent: Control, text: String, cb: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## A row of mutually exclusive toggle buttons; cb(index). Returns the buttons.
static func choice_row(parent: Control, labels: Array, selected: int, cb: Callable) -> Array:
	var row := HFlowContainer.new()
	parent.add_child(row)
	var group := ButtonGroup.new()
	var out: Array = []
	for i in labels.size():
		var b := Button.new()
		b.text = String(labels[i])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = i == selected
		b.pressed.connect(cb.bind(i))
		row.add_child(b)
		out.append(b)
	return out


## "Label  [slider]  value" row; cb(value). Returns the HSlider.
static func slider(parent: Control, text: String, lo: float, hi: float, step: float, value: float, cb: Callable) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := HT.make_label(text, HT.TEXT, 14)
	l.custom_minimum_size = Vector2(88, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(110, 20)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var v := HT.make_label(str(int(value)) if step >= 1.0 else str(value), HT.AMBER, 14)
	v.custom_minimum_size = Vector2(44, 0)
	row.add_child(v)
	s.value_changed.connect(func(x: float):
		v.text = str(int(x)) if step >= 1.0 else "%.2f" % x
		cb.call(x))
	return s


static func check(parent: Control, text: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	parent.add_child(c)
	return c


static func option(parent: Control, text: String, items: Array, selected: int, cb: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	if text != "":
		var l := HT.make_label(text, HT.TEXT, 14)
		l.custom_minimum_size = Vector2(88, 0)
		row.add_child(l)
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.select(selected)
	o.focus_mode = Control.FOCUS_NONE
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(cb)
	row.add_child(o)
	return o


static func line(parent: Control, text: String, value: String, cb: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := HT.make_label(text, HT.TEXT, 14)
	l.custom_minimum_size = Vector2(88, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_changed.connect(cb)
	row.add_child(e)
	return e


## Colour-chip palette of terrain codes (two columns); cb(code).
static func terrain_palette(parent: Control, codes: Array, selected: int, cb: Callable) -> Array:
	var grid := GridContainer.new()
	grid.columns = 2
	parent.add_child(grid)
	var group := ButtonGroup.new()
	var out: Array = []
	for code in codes:
		var b := Button.new()
		b.text = TERRAIN_LABELS[code]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = code == selected
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = chip(Color(TERRAIN_COLORS[code]))
		b.custom_minimum_size = Vector2(124, 0)
		b.pressed.connect(cb.bind(code))
		grid.add_child(b)
		out.append(b)
	return out


static var _chips: Dictionary = {}


static func chip(c: Color) -> Texture2D:
	var key := c.to_html()
	if _chips.has(key):
		return _chips[key]
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(c)
	for i in 14:
		for e in [0, 13]:
			img.set_pixel(i, e, Color(0, 0, 0, 0.6))
			img.set_pixel(e, i, Color(0, 0, 0, 0.6))
	var t := ImageTexture.create_from_image(img)
	_chips[key] = t
	return t
