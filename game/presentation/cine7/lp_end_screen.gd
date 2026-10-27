extends Control
## G7 (CINE7): Last Protocol end-of-run screen (master scope section 10, 13.5, 6.4 / 13.4). Replaces LPMODE7's small
## end panel: the ending's title and epitaph, the medal (bronze / silver / gold, drawn), the score, every section-10
## stat (time, creep purged, cores destroyed, teams lost, extractions, rings lost, secrets, countdown left) with
## NEW BEST tags, the personal bests from the records file, and the Remembered list (call sign, name, role, team).
## Buttons: Watch the ending again, Continue (the match summary is underneath). Presentation only.

signal continue_pressed
signal replay_pressed

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const LpMenu = preload("res://presentation/ui7/lp_menu.gd")
const D = preload("res://presentation/cine7/cine_data.gd")
const TITLES := {"total_purge": "TOTAL PURGE", "capture_core": "THE CAPTURED CORE", "pyrrhic": "PYRRHIC VICTORY",
	"victory": "VICTORY", "defeat_creep": "THE CREEP TOOK EVERYTHING", "defeat_countdown": "THE PROTOCOL FIRED",
	"defeat_facility": "THE FACILITY FELL"}
const EPITAPHS := {"total_purge": "Every core destroyed, every nest burned. The world endures.",
	"capture_core": "The last core is ours, alive and contained. Now we can ask it what it is.",
	"pyrrhic": "The world was saved. Not all of it was saved by the living.",
	"victory": "The cores are dead and the creep is held below the line.",
	"defeat_creep": "Defeat: the creep meter reached critical.",
	"defeat_countdown": "Defeat: the doomsday countdown reached zero.",
	"defeat_facility": "Defeat: the facility fell with no team left in the field."}
const MEDAL_COLS := {"gold": [Color("f2cf6b"), Color("a8781e")], "silver": [Color("d9dee2"), Color("7d878e")],
	"bronze": [Color("d39a62"), Color("8a5a2e")], "": [Color("4a565c"), Color("30393e")]}

var result: Dictionary = {}
var new_bests: Array = []
var records: Dictionary = {}
var rows: Array = []          # Remembered rows (cine_data.remembered_rows)
var panel: PanelContainer
var remembered_box: VBoxContainer
var medal_view: Control
var continue_btn: Button
var replay_btn: Button


static func build(parent: Node, res: Dictionary, saved: Dictionary, remembered_rows: Array, can_replay: bool = true) -> Control:
	var s = (load("res://presentation/cine7/lp_end_screen.gd") as GDScript).new()
	s.result = res
	s.new_bests = saved.get("new_bests", [])
	s.records = saved.get("records", LpMenu.empty_records())
	s.rows = remembered_rows if not remembered_rows.is_empty() else D.remembered_rows(null, res.get("remembered", []))
	s.set_meta("can_replay", can_replay)
	parent.add_child(s)
	return s


func _ready() -> void:
	name = "LpEnd"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.035, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	panel = UiKit.panel("modal")
	panel.name = "LpEndPanel"
	UiKit.fit_register(panel, true)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var won := bool(result.get("won", false))
	var ending := String(result.get("ending", ""))
	var kicker := UiKit.label("LAST PROTOCOL  -  %s" % ("RUN WON" if won else "RUN LOST"), "small")
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(kicker)
	var tl := UiKit.label(String(TITLES.get(ending, ending.to_upper())), "title")
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_color_override("font_color", UiKit.AMBER if won else UiKit.RED)
	tl.add_theme_font_size_override("font_size", 30)
	v.add_child(tl)
	var ep := UiKit.label(String(EPITAPHS.get(ending, "")), "body")
	ep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ep.add_theme_color_override("font_color", UiKit.DIM)
	v.add_child(ep)
	v.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	v.add_child(body)
	body.add_child(_medal_col())
	body.add_child(_stats_col())
	body.add_child(_side_col())
	v.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	replay_btn = UiKit.button("Watch the ending again", "", "Replay this run's ending cinematic")
	replay_btn.name = "LpReplay"
	replay_btn.visible = bool(get_meta("can_replay", true))
	replay_btn.pressed.connect(func(): replay_pressed.emit())
	foot.add_child(replay_btn)
	continue_btn = UiKit.button("Continue", "", "Close the Last Protocol report (the match summary is underneath)")
	continue_btn.name = "LpContinue"
	continue_btn.pressed.connect(func():
		hide()
		continue_pressed.emit())
	foot.add_child(continue_btn)


func _head(t: String) -> Label:
	var l := UiKit.label(t, "header")
	l.add_theme_color_override("font_color", UiKit.AMBER)
	return l


func _medal_col() -> Control:
	var c := VBoxContainer.new()
	c.custom_minimum_size = Vector2(190, 0)
	c.add_theme_constant_override("separation", 4)
	medal_view = Control.new()
	medal_view.name = "LpMedal"
	medal_view.custom_minimum_size = Vector2(190, 150)
	medal_view.draw.connect(_draw_medal)
	c.add_child(medal_view)
	var md := String(result.get("medal", ""))
	var ml := UiKit.label(("%s MEDAL" % md.to_upper()) if md != "" else "NO MEDAL", "header")
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.add_theme_color_override("font_color", (MEDAL_COLS.get(md, MEDAL_COLS[""]) as Array)[0] if md != "" else UiKit.DIM)
	c.add_child(ml)
	if new_bests.has("medal"):
		c.add_child(_nb_label(true))
	var sl := UiKit.label("SCORE", "small")
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(sl)
	var sv := UiKit.label(_thousands(int(result.get("score", 0))), "title")
	sv.name = "LpScore"
	sv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_theme_font_size_override("font_size", 28)
	c.add_child(sv)
	if new_bests.has("score"):
		c.add_child(_nb_label(true))
	return c


func _nb_label(center: bool = false) -> Label:
	var l := UiKit.label("NEW BEST", "good")
	l.add_theme_color_override("font_color", UiKit.GREEN)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## The section-10 stat rows: [label, value, best key or ""].
static func stat_rows(r: Dictionary) -> Array:
	var out := [["Time", LpMenu.fmt_time(float(r.get("time_s", 0.0))), "time"],
		["Creep purged", "%.1f points" % float(r.get("creep_purged", 0.0)), "creep_purged"],
		["Creep at the end", "%.1f%%" % (float(r.get("creep_final", 0.0)) * 100.0), ""],
		["Cores destroyed", "%d / %d" % [int(r.get("cores_destroyed", 0)), int(r.get("cores_total", 3))], "cores_destroyed"],
		["Teams lost", "%d of %d" % [int(r.get("teams_lost", 0)), maxi(int(r.get("teams_total", 0)), int(r.get("teams_lost", 0)))], "teams_lost"],
		["Extractions", str(int(r.get("extractions", 0))), "extractions"],
		["Rings lost", str(int(r.get("rings_fallen", 0))), ""]]
	if bool(r.get("won", false)):
		out.append(["Countdown left", LpMenu.fmt_time(float(r.get("countdown_left_s", 0.0))), ""])
	var sec: Array = r.get("secrets", [])
	out.append(["Secrets found", ("%d  (%s)" % [sec.size(), ", ".join(PackedStringArray(sec))]) if not sec.is_empty() else "0", ""])
	return out


func _stats_col() -> Control:
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(300, 0)
	c.add_child(_head("THE RUN"))
	var g := GridContainer.new()
	g.name = "LpStats"
	g.columns = 3
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 3)
	c.add_child(g)
	for row in stat_rows(result):
		var k := UiKit.label(String(row[0]), "body")
		k.add_theme_color_override("font_color", UiKit.DIM)
		g.add_child(k)
		var val := UiKit.label(String(row[1]), "body")
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(val)
		g.add_child(_nb_label() if String(row[2]) != "" and new_bests.has(String(row[2])) else Control.new())
	return c


func _side_col() -> Control:
	var c := VBoxContainer.new()
	c.custom_minimum_size = Vector2(300, 0)
	c.add_child(_head("PERSONAL BESTS"))
	var g := GridContainer.new()
	g.name = "LpBests"
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	c.add_child(g)
	for row in LpMenu.bests_rows(records):
		var k := UiKit.label(String(row[0]), "small")
		k.add_theme_color_override("font_color", UiKit.DIM)
		g.add_child(k)
		g.add_child(UiKit.label(String(row[1]), "small"))
	c.add_child(HSeparator.new())
	c.add_child(_head("REMEMBERED  (%d)" % rows.size()))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(300, 120)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c.add_child(sc)
	remembered_box = VBoxContainer.new()
	remembered_box.name = "LpRemembered"
	remembered_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(remembered_box)
	if rows.is_empty():
		var l := UiKit.label("No named operator was lost.", "small")
		l.add_theme_color_override("font_color", UiKit.DIM)
		remembered_box.add_child(l)
	for r in rows:
		var a := UiKit.label(D.row_text(r), "body")
		a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		remembered_box.add_child(a)
		var sub := D.row_sub(r)
		if sub != "":
			var b := UiKit.label(sub, "small")
			b.add_theme_color_override("font_color", UiKit.DIM)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			remembered_box.add_child(b)
	return c


## Call signs shown in the Remembered list (tests).
func remembered_call_signs() -> Array:
	var out := []
	for r in rows:
		out.append(String(r.get("cs", "")))
	return out


func _draw_medal() -> void:
	var s := medal_view.size
	var c := s * 0.5 + Vector2(0, 10)
	var r := minf(s.x, s.y) * 0.33
	var md := String(result.get("medal", ""))
	var col: Array = MEDAL_COLS.get(md, MEDAL_COLS[""])
	var face: Color = col[0]
	var deep: Color = col[1]
	medal_view.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.8, -r * 1.75), c + Vector2(-r * 0.2, -r * 1.75), c + Vector2(r * 0.2, -r * 0.5), c + Vector2(-r * 0.4, -r * 0.5)]), Color("2c4a7a") if md != "" else Color("2b353b"))
	medal_view.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.2, -r * 1.75), c + Vector2(r * 0.8, -r * 1.75), c + Vector2(r * 0.4, -r * 0.5), c + Vector2(-r * 0.2, -r * 0.5)]), Color("8a2b2b") if md != "" else Color("30393e"))
	medal_view.draw_circle(c, r * 1.1, deep)
	medal_view.draw_circle(c, r, face)
	medal_view.draw_arc(c, r * 0.8, 0, TAU, 48, deep, 2.5, true)
	var star := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * float(i) / 10.0
		star.append(c + Vector2(cos(a), sin(a)) * (r * 0.56 if i % 2 == 0 else r * 0.23))
	medal_view.draw_colored_polygon(star, deep)
	if md == "":
		medal_view.draw_line(c + Vector2(-r * 0.7, r * 0.7), c + Vector2(r * 0.7, -r * 0.7), Color(0, 0, 0, 0.35), 4.0, true)
