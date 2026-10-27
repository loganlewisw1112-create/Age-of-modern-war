extends Control
## G7 (CINE7): the screen layer of a cinematic: colour grade (screen shader), black / white fades, letterbox bars,
## title cards (big, title, caption, date, stamp, medal), teletype lines, countdown digits, the Remembered roll and the
## skip prompt. Sizes follow the viewport height (720p = 1.0), so 1280x720 and 1920x1080 frame the same.
## Presentation only.

signal skip_pressed

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const D = preload("res://presentation/cine7/cine_data.gd")
const BAR := 0.115           # letterbox bar height (share of the screen height)
const CPS := 40.0            # teletype characters per second
const GRADE_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float sat = 1.0;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform float dark = 0.0;
uniform float scan = 0.0;
uniform float grain = 0.0;
uniform float vig = 0.35;
uniform float bleach = 0.0;
uniform float time_s = 0.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat);
	c = mix(c, (vec3(l) * 0.6 + c * 0.4) * tint.rgb * 1.35, tint.a);
	c = mix(c, vec3(1.0), bleach * (0.35 + 0.65 * l));
	c *= (1.0 - dark);
	float sl = 0.5 + 0.5 * sin(SCREEN_UV.y / SCREEN_PIXEL_SIZE.y * 1.5708);
	c *= 1.0 - scan * 0.32 * sl;
	float n = fract(sin(dot(SCREEN_UV + vec2(time_s * 0.37, time_s * 0.11), vec2(12.9898, 78.233))) * 43758.5453);
	c += (n - 0.5) * grain * 0.3;
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - vig * smoothstep(0.3, 0.9, length(d * vec2(1.25, 1.0)) * 1.2);
	COLOR = vec4(c, 1.0);
}
"""

var grade: ColorRect
var black: ColorRect
var flash: ColorRect
var bar_top: ColorRect
var bar_bot: ColorRect
var card: Control
var card_t: Label
var card_s: Label
var card_rule: ColorRect
var medal: Control
var tele: Label
var count: Label
var count_head: Label
var roll: Control
var roll_box: VBoxContainer
var hint: Button
var _mat: ShaderMaterial
var _sh: Dictionary = {}
var _tele_lines: Array = []
var _hint_t := 0.0
var _bars := 0.0
var _hand := false
var _style := ""
var _black_extra := 0.0
var _wait_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # the match underneath gets no clicks while a cinematic plays
	grade = ColorRect.new()
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRADE_SHADER
	_mat.shader = sh
	grade.material = _mat
	_full(grade)
	black = ColorRect.new()
	black.color = Color.BLACK
	_full(black)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	_full(flash)
	bar_top = ColorRect.new()
	bar_top.color = Color.BLACK
	add_child(bar_top)
	bar_bot = ColorRect.new()
	bar_bot.color = Color.BLACK
	add_child(bar_bot)
	card = Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(card)
	card_rule = ColorRect.new()
	card_rule.color = UiKit.AMBER
	card.add_child(card_rule)
	medal = Control.new()
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal.draw.connect(_draw_medal)
	card.add_child(medal)
	card_t = _lbl(card, true)
	card_s = _lbl(card, false)
	tele = _lbl(self, false)
	count_head = _lbl(self, true)
	count = _lbl(self, true)
	roll = Control.new()
	roll.clip_contents = true
	roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(roll)
	roll_box = VBoxContainer.new()
	roll_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	roll.add_child(roll_box)
	hint = Button.new()
	hint.flat = true
	hint.text = "SPACE  /  ESC   skip"
	hint.focus_mode = Control.FOCUS_NONE
	hint.add_theme_font_override("font", UiKit.font(true))
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	hint.pressed.connect(func(): skip_pressed.emit())
	add_child(hint)
	_hint_t = 3.5
	_layout()


func _full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)


func _lbl(parent: Control, bold: bool) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", UiKit.font(bold))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _vs() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)


func _sc() -> float:
	return _vs().y / 720.0


func _fs(l: Control, px: float) -> void:
	l.add_theme_font_size_override("font_size", int(round(px * _sc())))


func _layout() -> void:
	var v := _vs()
	position = Vector2.ZERO
	size = v   # a Control under a CanvasLayer: size it to the viewport explicitly (full-rect children follow)
	var bh := v.y * BAR * _bars
	bar_top.position = Vector2.ZERO
	bar_top.size = Vector2(v.x, bh)
	bar_bot.position = Vector2(0, v.y - bh)
	bar_bot.size = Vector2(v.x, bh + 1)
	_fs(hint, 13)
	hint.size = hint.get_combined_minimum_size()
	hint.position = Vector2(v.x - hint.size.x - 18.0 * _sc(), v.y - hint.size.y - 10.0 * _sc())


# ---------------------------------------------------------------- shots
func on_shot(sh: Dictionary, data: Dictionary) -> void:
	_sh = sh
	if not is_inside_tree() or grade == null:
		return
	var g: Dictionary = sh.get("grade", {})
	for k in ["sat", "dark", "scan", "grain", "vig", "bleach"]:
		_mat.set_shader_parameter(k, float(g.get(k, 0.0)))
	_mat.set_shader_parameter("tint", g.get("tint", Color(1, 1, 1, 0)))
	grade.visible = not bool(sh.get("black", false))
	_hand = bool(sh.get("hand_over", false))
	_tele_lines = sh.get("tele", [])
	tele.text = "\n".join(PackedStringArray(_tele_lines))
	tele.visible_characters = 0
	_tele_style(String(sh.get("tele_style", "log")))
	var cd: Dictionary = sh.get("card", {})
	_style = String(cd.get("style", ""))
	card_t.text = String(cd.get("t", ""))
	card_s.text = String(cd.get("s", ""))
	_card_style(_style)
	card.modulate.a = 0.0
	count.visible = sh.has("count")
	count_head.visible = sh.has("count")
	_build_roll(sh.get("roll", []), String(sh.get("roll_head", "")), String(sh.get("roll_foot", "")))
	roll.visible = sh.has("roll")
	medal.visible = _style == "medal"


func _tele_style(st: String) -> void:
	var v := _vs()
	var sc := _sc()
	tele.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	match st:
		"flash":
			_fs(tele, 22)
			tele.add_theme_color_override("font_color", UiKit.AMBER)
			tele.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			tele.size = Vector2(minf(720.0 * sc, v.x - 80.0), 300.0 * sc)
			tele.position = Vector2((v.x - tele.size.x) * 0.5, v.y * 0.28)
		"radio":
			_fs(tele, 19)
			tele.add_theme_color_override("font_color", Color(0.92, 0.94, 0.9))
			tele.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tele.size = Vector2(v.x * 0.7, 120.0 * sc)
			tele.position = Vector2(v.x * 0.15, v.y * (1.0 - BAR) - 130.0 * sc)
		_:
			_fs(tele, 16)
			tele.add_theme_color_override("font_color", Color(0.72, 1.0, 0.78))
			tele.size = Vector2(v.x * 0.55, 110.0 * sc)
			tele.position = Vector2(48.0 * sc, v.y * (1.0 - BAR) - 120.0 * sc)


func _card_style(st: String) -> void:
	var v := _vs()
	var sc := _sc()
	card_rule.visible = st in ["caption", "date", "title"]
	card_t.rotation = 0.0
	card_t.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	card_s.add_theme_color_override("font_color", Color(0.85, 0.87, 0.82))
	card_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var w := minf(v.x - 80.0 * sc, 1000.0 * sc)
	match st:
		"big", "medal":
			_fs(card_t, 60)
			_fs(card_s, 19)
			card_t.size = Vector2(w, 90.0 * sc)
			card_t.position = Vector2((v.x - w) * 0.5, v.y * (0.62 if st == "medal" else float(_sh.get("card", {}).get("y", 0.42))) - 45.0 * sc)
			card_s.size = Vector2(w, 60.0 * sc)
			card_s.position = Vector2((v.x - w) * 0.5, card_t.position.y + 88.0 * sc)
			if st == "medal":
				card_t.add_theme_color_override("font_color", Color("f2cf6b"))
				medal.size = Vector2(170, 170) * sc
				medal.position = Vector2((v.x - medal.size.x) * 0.5, v.y * 0.62 - 230.0 * sc)
		"title":
			_fs(card_t, 40)
			_fs(card_s, 18)
			card_t.size = Vector2(w, 64.0 * sc)
			card_t.position = Vector2((v.x - w) * 0.5, v.y * BAR + 34.0 * sc)
			card_s.size = Vector2(w, 50.0 * sc)
			card_s.position = Vector2((v.x - w) * 0.5, card_t.position.y + 62.0 * sc)
			card_rule.size = Vector2(160.0 * sc, 2.0 * sc)
			card_rule.position = Vector2((v.x - card_rule.size.x) * 0.5, card_t.position.y + 58.0 * sc)
		"stamp":
			_fs(card_t, 54)
			_fs(card_s, 22)
			card_t.add_theme_color_override("font_color", Color("e0605a"))
			card_s.add_theme_color_override("font_color", Color("e0605a"))
			card_t.size = Vector2(w, 80.0 * sc)
			card_t.position = Vector2((v.x - w) * 0.5, v.y * 0.72 - 40.0 * sc)
			card_s.size = Vector2(w, 40.0 * sc)
			card_s.position = Vector2((v.x - w) * 0.5, card_t.position.y + 74.0 * sc)
			card_t.pivot_offset = card_t.size * 0.5
			card_t.rotation = deg_to_rad(-3.0)
		_:   # caption (lower left) and date (upper left)
			card_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			card_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_fs(card_t, 30 if st == "caption" else 26)
			_fs(card_s, 16)
			var x := 56.0 * sc
			var y := v.y * (1.0 - BAR) - 120.0 * sc if st == "caption" else v.y * BAR + 26.0 * sc
			card_t.size = Vector2(v.x * 0.6, 46.0 * sc)
			card_t.position = Vector2(x, y)
			card_rule.size = Vector2(120.0 * sc, 2.0 * sc)
			card_rule.position = Vector2(x, y + 44.0 * sc)
			card_s.size = Vector2(v.x * 0.6, 50.0 * sc)
			card_s.position = Vector2(x, y + 52.0 * sc)
			if st == "date":
				card_t.add_theme_color_override("font_color", Color(0.72, 1.0, 0.78))
	card_t.pivot_offset = card_t.size * 0.5


func _build_roll(rows: Array, head: String, foot: String) -> void:
	for c in roll_box.get_children():
		c.queue_free()
	if head == "" and rows.is_empty():
		return
	var v := _vs()
	var sc := _sc()
	roll_box.custom_minimum_size = Vector2(minf(700.0 * sc, v.x - 60.0), 0)
	roll_box.add_theme_constant_override("separation", int(6 * sc))
	var h := _lbl(roll_box, true)
	h.text = head
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_color_override("font_color", UiKit.AMBER)
	_fs(h, 34)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24.0 * sc)
	roll_box.add_child(gap)
	for r in rows:
		var a := _lbl(roll_box, true)
		a.text = String(r.get("cs", ""))
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fs(a, 24)
		var nm := String(r.get("name", ""))
		var sub := D.row_sub(r)
		var b := _lbl(roll_box, false)
		b.text = nm + (("\n" + sub) if sub != "" else "")
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_color_override("font_color", Color(0.75, 0.78, 0.74))
		_fs(b, 15)
		var g2 := Control.new()
		g2.custom_minimum_size = Vector2(0, 14.0 * sc)
		roll_box.add_child(g2)
	var f := _lbl(roll_box, false)
	f.text = foot
	f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	f.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
	_fs(f, 20)


# ---------------------------------------------------------------- frames
func frame(sh: Dictionary, t: float, _elapsed: float) -> void:
	if grade == null:
		return
	var dur := maxf(float(sh.dur), 0.001)
	var sc := _sc()
	var v := _vs()
	_mat.set_shader_parameter("time_s", t)
	# letterbox: in over 1.2 s at the start; the hand-over shot opens it over its last 2 s
	_bars = minf(_bars + get_process_delta_time() / 1.2, 1.0) if not _hand else clampf((dur - t) / 2.0, 0.0, 1.0)
	# fades
	var a := 1.0 if bool(sh.get("black", false)) else 0.0
	var fi := float(sh.get("fade_in", 0.0))
	var fo := float(sh.get("fade_out", 0.0))
	if not bool(sh.get("black", false)):
		if fi > 0.0 and t < fi:
			a = maxf(a, 1.0 - t / fi)
		if fo > 0.0 and t > dur - fo:
			a = maxf(a, (t - (dur - fo)) / fo)
	else:
		if fi > 0.0 and t < fi:
			a = 1.0
	black.color.a = maxf(a, _black_extra)
	flash.color.a = clampf(1.0 - t / maxf(float(sh.get("flash", 0.0)), 0.001), 0.0, 1.0) if sh.has("flash") else 0.0
	# card
	var cd: Dictionary = sh.get("card", {})
	if not cd.is_empty():
		var at := float(cd.get("at", 0.0))
		var out := float(cd.get("out", dur))
		card.modulate.a = clampf(minf((t - at) / 0.7, (out - t) / 0.7), 0.0, 1.0)
		if _style == "stamp":
			var k := clampf((t - at) / 0.25, 0.0, 1.0)
			card_t.scale = Vector2.ONE * lerpf(1.6, 1.0, k)
		else:
			card_t.scale = Vector2.ONE
		medal.queue_redraw()
	else:
		card.modulate.a = 0.0
	# black text shots fade their text out with the shot's fade_out
	var txt_a := 1.0
	if fo > 0.0 and t > dur - fo:
		txt_a = 1.0 - (t - (dur - fo)) / fo
	# teletype
	if not _tele_lines.is_empty():
		var tt := t - float(sh.get("tele_at", 0.6))
		var n := 0
		var lag := 0.0
		for ln in _tele_lines:   # each line types, then a short pause
			var need := float(String(ln).length()) / CPS
			if tt - lag >= need + 0.45:
				n += String(ln).length() + 1
				lag += need + 0.45
			else:
				n += clampi(int((tt - lag) * CPS), 0, String(ln).length())
				break
		tele.visible_characters = n
		tele.modulate.a = txt_a
	# countdown digits
	if sh.has("count"):
		var from := float(sh.count.get("from", 5.0))
		var left := maxf(from - t * from / maxf(dur - 0.8, 0.1), 0.0)
		count.text = "00:00:%02d" % int(ceil(left))
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fs(count, 110)
		count.add_theme_color_override("font_color", Color("e0605a") if fmod(t, 1.0) < 0.6 or left <= 0.0 else Color("7a2a26"))
		count.size = Vector2(v.x, 150.0 * sc)
		count.position = Vector2(0, v.y * 0.4 - 75.0 * sc)
		count_head.text = "PROTOCOL"
		count_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fs(count_head, 20)
		count_head.add_theme_color_override("font_color", UiKit.AMBER)
		count_head.size = Vector2(v.x, 40.0 * sc)
		count_head.position = Vector2(0, count.position.y - 30.0 * sc)
	# Remembered roll: rises from the bottom and ends with the closing line in the middle of the screen
	if sh.has("roll") and roll_box.get_child_count() > 0:
		var ch := roll_box.get_combined_minimum_size().y
		var u := clampf(t / maxf(dur - 1.5, 0.1), 0.0, 1.0)
		roll_box.size = Vector2(roll_box.custom_minimum_size.x, ch)
		roll.position = Vector2(0, v.y * BAR)   # the roll scrolls between the letterbox bars
		roll.size = Vector2(v.x, v.y * (1.0 - 2.0 * BAR))
		roll_box.position = Vector2((v.x - roll_box.size.x) * 0.5, lerpf(roll.size.y, roll.size.y * 0.5 - ch + 30.0 * sc, u))
	# skip hint
	_hint_t = maxf(_hint_t - get_process_delta_time(), 0.0)
	hint.modulate.a = clampf(_hint_t, 0.0, 1.0) * 0.9 + 0.1 * float(not _hand)
	_layout()


func waiting_frame(dt: float) -> void:
	if grade == null:
		return
	_wait_t += dt
	grade.visible = false
	black.color.a = 1.0
	_bars = 1.0
	tele.text = "ESTABLISHING LINK" + ".".repeat(int(_wait_t * 3.0) % 4)
	tele.visible_characters = -1
	_tele_style("flash")
	_layout()


func fade_black(a: float) -> void:
	_black_extra = a
	if black != null:
		black.color.a = maxf(black.color.a, a)


func show_hint() -> void:
	_hint_t = 3.0


func _draw_medal() -> void:
	var s := medal.size
	var c := s * 0.5 + Vector2(0, s.y * 0.06)
	var r := minf(s.x, s.y) * 0.36
	var gold := Color("f2cf6b")
	var deep := Color("a8781e")
	# ribbon
	medal.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.75, -r * 2.2), c + Vector2(-r * 0.15, -r * 2.2), c + Vector2(r * 0.2, -r * 0.6), c + Vector2(-r * 0.4, -r * 0.6)]), Color("2c4a7a"))
	medal.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.15, -r * 2.2), c + Vector2(r * 0.75, -r * 2.2), c + Vector2(r * 0.4, -r * 0.6), c + Vector2(-r * 0.2, -r * 0.6)]), Color("8a2b2b"))
	medal.draw_circle(c, r * 1.08, deep)
	medal.draw_circle(c, r, gold)
	medal.draw_arc(c, r * 0.82, 0, TAU, 48, deep, maxf(2.0, r * 0.05), true)
	var star := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * float(i) / 10.0
		star.append(c + Vector2(cos(a), sin(a)) * (r * 0.58 if i % 2 == 0 else r * 0.24))
	medal.draw_colored_polygon(star, deep)
	var sh := fmod(Time.get_ticks_msec() / 1000.0 * 0.5, 1.0)
	medal.draw_arc(c, r * 0.95, -PI * 0.9 + sh * TAU, -PI * 0.6 + sh * TAU, 16, Color(1, 1, 0.9, 0.7), maxf(2.0, r * 0.06), true)
