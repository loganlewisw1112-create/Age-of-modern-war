extends RefCounted
## UI6a (G6): shared helpers for the G6 panels (owner: UI6a, CONTRACTS_G6 section 1).
## Every G6 panel is a modal frame (exempt from the fit test's OVERLAP rule, never from CLIP /
## OVERFLOW): a header row (title + Close) over a body that scrolls vertically, sized to the canvas
## by fit_modal() so it fits at 1024x576 (ScaledLayer.MIN_CANVAS) and every larger canvas.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")

const SLOT_COLS := [Color("e3a83a"), Color("4fc3d9"), Color("86c85e"), Color("d0603e")]   # AI commander badges C1-C4


## {panel, body: VBoxContainer, scroll, title: Label, close: Button}
static func modal(node_name: String, title: String, close_tip: String) -> Dictionary:
	var p := UiKit.panel("modal")
	p.name = node_name
	UiKit.fit_register(p, true)
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	v.add_child(hb)
	var t := UiKit.label(title, "header")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(t)
	var x := UiKit.button("Close", "Esc", close_tip)
	x.name = "Close"
	hb.add_child(x)
	var body := VBoxContainer.new()
	body.name = "BodyBox"
	body.add_theme_constant_override("separation", 6)
	var sc := UiKit.scroll(body)
	sc.name = "Body"
	v.add_child(sc)
	return {"panel": p, "body": body, "scroll": sc, "title": t, "close": x, "head": hb}


## Width want_w (capped to the canvas), body height = its content (capped), centred on the canvas.
static func fit_modal(m: Dictionary, canvas: Vector2, want_w: float) -> void:
	if m.is_empty() or canvas.x < 1.0:
		return
	var p: PanelContainer = m.panel
	var sc: ScrollContainer = m.scroll
	var body: Control = m.body
	var w := floorf(minf(want_w, canvas.x - 48.0))
	var head_h: float = (m.head as Control).get_combined_minimum_size().y
	var chrome := head_h + 6.0 + 2.0 * UiKit.PAD + 12.0
	var avail := maxf(60.0, canvas.y - 48.0 - chrome)
	var h := clampf(body.get_combined_minimum_size().y, 40.0, avail)
	sc.custom_minimum_size = Vector2(w, h)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if body.get_combined_minimum_size().y > avail + 0.5 else ScrollContainer.SCROLL_MODE_DISABLED
	p.size = Vector2.ZERO
	var sz := p.get_combined_minimum_size()
	p.size = sz
	p.position = ((canvas - sz) * 0.5).floor().max(Vector2.ZERO)


static func row(parent: Control, sep: int = 8) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", sep)
	parent.add_child(hb)
	return hb


static func cell_label(parent: Control, text: String, w: float, role: String = "body") -> Label:
	var l := UiKit.label(text, role)
	l.custom_minimum_size = Vector2(w, 0)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(l)
	return l


static func small_button(parent: Control, text: String, tip: String, w: float = 0.0) -> Button:
	var b := UiKit.button(text, "", tip)
	b.custom_minimum_size = Vector2(w, 28)
	parent.add_child(b)
	return b


static func option(parent: Control, items: Array, w: float = 150.0) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(w, 28)
	o.clip_text = true
	o.fit_to_longest_item = false
	for it in items:
		o.add_item(String(it))
	parent.add_child(o)
	return o


static func pretty(id: String) -> String:
	return id.replace("_", " ").capitalize()


static func slot_color(slot: int) -> Color:
	return SLOT_COLS[clampi(slot, 0, SLOT_COLS.size() - 1)]


## Unit icon (ArtCatalog; the manifest knows every G6 def after VIEW6's group merge).
static func icon_rect(def_id: String, px: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = ArtCatalog.icon(def_id)
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_PASS
	return tr
