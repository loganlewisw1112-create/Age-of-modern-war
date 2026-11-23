extends PanelContainer
## G7 CARDS8A (13.9c-48): the COMMAND CENTRE / OPS ROOM card. Shown only while the player has the facility's command
## centre (the planning zone, MatchView part "command") selected. Three sections:
##   MISSIONS     every running team mission (CnMission8 purge / SpecOps8) with its status line and progress;
##                RECALL (cn_extract, or so_cancel + cn_extract for a spec-ops squad) and CANCEL per row;
##                hotkeys T next row, C recall, V cancel the marked row.
##   FIRE SUPPORT ARTY / ROCKETS / AIR from base (cc_fire): ammo n/max and the reload shown; click the button (or
##                B / K / N), then click a target on the map the side can see.
##   EVACUATE     WITHDRAW (cc_withdraw, X): troops outside the walls fall back into the compound;
##                LAST STAND (cc_last_stand, Z): the last-stand reserve and the troops inside hold the core doors.
## Every button is pre-checked by the sim reason functions (Cards8a / CnMission8 / SpecOps8): disabled with the reason
## as its tooltip. Reads the world only on frames with no sim step running; never writes the sim (MatchView.issue).
## Hook (ORCH, presentation/hud/hud.gd, after the lpreserve_card attach line):
##   preload("res://presentation/ui7/ops_card8.gd").attach(self, left)   # G7 CARDS8A: command centre card

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const S = preload("res://presentation/ui7/ops_style.gd")
const Cards8a = preload("res://sim/systems/cards8a.gd")
const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")

const PART := "command"
const REFRESH_S := 0.3
const ROWS := 4
const FIRE := [["artillery", "ARTY", "cc_fire_art"], ["rockets", "ROCKETS", "cc_fire_rockets"], ["air", "AIR", "cc_fire_air"]]

var mv = null
var world_override: SimWorld = null    # tests / fit
var fid_override := -1
var force_show := false
var fac := -1
var mark := 0                          # marked mission row (hotkeys)
var sent: Array = []                   # commands issued (tests / playtest log)
var last_rows: Array = []
var pick_kind := ""                    # fire support waiting for a map click
var _acc := 99.0
var _dirty := true
var _state: Label
var _none: Label
var _rows: Array = []                  # [{box, label, bar, recall, cancel}]
var _fire_btn: Dictionary = {}
var _btn_wd: Button
var _btn_ls: Button
var _sections: Array = []             # G7 CARDBAR8: section headers (hidden in the bottom-bar layout)


static func attach(h, left_stack: Control) -> Control:
	var c = (load("res://presentation/ui7/ops_card8.gd") as GDScript).new()
	c.mv = h.get("mv") if h != null else null
	if left_stack != null:
		left_stack.add_child(c)
	if c.mv != null and (c.mv as Object).has_signal("world_events"):
		c.mv.world_events.connect(c._on_world_events)
	if c.mv != null and (c.mv as Object).has_signal("selection_changed"):
		c.mv.selection_changed.connect(c._on_selection_changed)
	return c


func _ready() -> void:
	name = "OpsCard8"
	theme_type_variation = "PlatePanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	UiKit.fit_register(self)
	custom_minimum_size = Vector2(300, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var t := UiKit.label("COMMAND CENTRE", "header")
	t.add_theme_color_override("font_color", S.CYAN)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	_state = _small("")
	_state.name = "BaseState"
	hb.add_child(_state)
	v.add_child(_section("MISSIONS"))
	_none = _small("No team missions running.")
	_none.name = "NoMissions"
	v.add_child(_none)
	for i in ROWS:
		var row := {}
		var box := VBoxContainer.new()
		box.name = "Mission%d" % i
		box.add_theme_constant_override("separation", 1)
		v.add_child(box)
		var l := _small("")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
		var rb := HBoxContainer.new()
		box.add_child(rb)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(90, 10)
		bar.max_value = 1.0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rb.add_child(bar)
		var ii := i
		row.recall = _mk(rb, "Recall%d" % i, "RECALL %d" % (i + 1), "Bring the team home.", func(): _on_recall(ii))
		row.cancel = _mk(rb, "Cancel%d" % i, "CANCEL %d" % (i + 1), "Cancel the mission.", func(): _on_cancel(ii))
		row.box = box
		row.label = l
		row.bar = bar
		_rows.append(row)
	v.add_child(_section("FIRE SUPPORT"))
	var fb := HBoxContainer.new()
	fb.add_theme_constant_override("separation", 3)
	v.add_child(fb)
	for f in FIRE:
		var kind := String(f[0])
		_fire_btn[kind] = _mk(fb, "Fire_" + kind, String(f[1]), "Fire support from base, then click a target.", func(): _on_fire(kind))
	v.add_child(_section("EVACUATE"))
	var eb := HBoxContainer.new()
	eb.add_theme_constant_override("separation", 3)
	v.add_child(eb)
	_btn_wd = _mk(eb, "WithdrawButton", "WITHDRAW", "Fighting withdrawal: troops outside the walls fall back into the compound.", _on_withdraw)
	_btn_ls = _mk(eb, "LastStandButton", "LAST STAND", "Commit the last-stand reserve and the troops inside to the core doors.", _on_last_stand)
	visible = false


func _small(text: String) -> Label:
	var l := UiKit.label(text, "body")
	l.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	return l


func _section(text: String) -> Label:
	var l := _small(text)
	l.add_theme_color_override("font_color", S.DIM)
	_sections.append(l)
	return l


func _mk(parent: Control, nm: String, text: String, tip: String, cb: Callable) -> Button:
	var b := UiKit.button(text, "", tip)
	b.name = nm
	b.custom_minimum_size = Vector2(0, 22)
	b.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func world() -> SimWorld:
	if world_override != null:
		return world_override
	return mv.get("_world") as SimWorld if mv != null else null


func pf() -> int:
	if fid_override >= 0:
		return fid_override
	return int(mv.get("player_fid")) if mv != null and mv.get("player_fid") != null else 0


func _sim_busy() -> bool:
	return world_override == null and mv != null and (mv as Object).has_method("sim_busy") and bool(mv.sim_busy())


func _on_selection_changed() -> void:
	_dirty = true
	_acc = 99.0
	if not _sim_busy():
		refresh()


func _on_world_events(_evs = null) -> void:
	_dirty = true


func _process(delta: float) -> void:
	_acc += delta
	if _acc < REFRESH_S or (not _dirty and _acc < REFRESH_S * 4.0):
		return
	if _sim_busy():
		return
	_acc = 0.0
	_dirty = false
	refresh()


## The selected own facility (its command centre part), or -1.
func selected_fac() -> int:
	var w := world()
	if w == null:
		return -1
	var cs = w.sys_state.get("cn_facility")
	if cs == null:
		return -1
	var ks: Array = (cs.facs as Dictionary).keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		if int(cs.facs[k].owner) != pf() or not w.entities.has(int(k)):
			continue
		if force_show or (mv != null and mv.has_method("part_selected") and bool(mv.part_selected(int(k), PART))):
			return int(k)
	return -1


func _setb(b: Button, reason: String, tip: String) -> void:
	b.disabled = reason != ""
	b.tooltip_text = reason if reason != "" else tip


func refresh() -> void:
	var w := world()
	fac = selected_fac()
	if w == null or fac < 0:
		visible = false
		if pick_kind != "" and mv != null and mv.has_method("cancel_point_pick"):
			mv.cancel_point_pick()
		pick_kind = ""
		return
	visible = true
	var fid := pf()
	var bs := SimWorld.CnFacility.secure_state(w, fac)
	_state.text = bs.replace("_", " ").to_upper()
	_state.add_theme_color_override("font_color", S.RED if bs == "breached" else (S.AMBER if bs != "secure" else S.PHOS))
	last_rows = Cards8a.mission_rows(w, fid)
	if mark >= last_rows.size():
		mark = 0
	_none.visible = last_rows.is_empty()
	for i in ROWS:
		var row: Dictionary = _rows[i]
		var on: bool = i < last_rows.size()
		(row.box as Control).visible = on
		if not on:
			continue
		var r: Dictionary = last_rows[i]
		(row.label as Label).text = "%s%d %s  [%s]  %s" % ["> " if i == mark else "", i + 1, String(r.name), "SPEC OPS" if r.kind == "specops" else "PURGE", String(r.line)]
		(row.label as Label).add_theme_color_override("font_color", S.CYAN if i == mark else S.PHOS)
		(row.bar as ProgressBar).value = clampf(float(r.progress), 0.0, 1.0)
		_setb(row.recall, String(r.recall_reason), "Bring the team home now.")
		_setb(row.cancel, String(r.cancel_reason), "Cancel the mission (the team stops where it is).")
	for f in FIRE:
		var kind := String(f[0])
		var st := Cards8a.fire_status(w, fac, kind)
		var why := Cards8a.fire_reason(w, fid, fac, kind, null)
		if why == "Pick a target on the map.":
			why = ""
		var b: Button = _fire_btn[kind]
		var txt := "%s %d/%d" % [String(f[1]), int(st.ammo), int(st.max)]
		if float(st.ready_s) > 0.0:
			txt += " %ds" % ceili(float(st.ready_s))
		b.text = txt
		_setb(b, why, "%s from base: click, then click a target you can see (%s)." % [kind.capitalize(), Hotkeys.badge(Hotkeys.key(String(f[2])))])
		b.add_theme_color_override("font_color", S.AMBER if pick_kind == kind else S.PHOS)
	_setb(_btn_wd, Cards8a.withdraw_reason(w, fid, fac), "Fighting withdrawal: troops outside the walls fall back into the compound (%s)." % Hotkeys.key("cc_withdraw"))
	_setb(_btn_ls, Cards8a.last_stand_reason(w, fid, fac), "Commit the last-stand reserve and the troops inside to the core doors (%s)." % Hotkeys.key("cc_last_stand"))


func _issue(cmd: Dictionary) -> void:
	sent.append(cmd.duplicate(true))
	if mv != null and mv.has_method("issue"):
		mv.issue(cmd)
	_dirty = true
	_acc = REFRESH_S


func _on_recall(i: int) -> void:
	if i >= last_rows.size():
		return
	var r: Dictionary = last_rows[i]
	if r.kind == "specops":
		_issue({"type": "so_cancel", "team_id": int(r.tid)})
	_issue({"type": "cn_extract", "team_id": int(r.tid)})


func _on_cancel(i: int) -> void:
	if i >= last_rows.size():
		return
	var r: Dictionary = last_rows[i]
	_issue({"type": String(r.cancel_cmd), "team_id": int(r.tid)})


func _on_fire(kind: String) -> void:
	if fac < 0:
		return
	if pick_kind == kind:
		pick_kind = ""
		if mv != null and mv.has_method("cancel_point_pick"):
			mv.cancel_point_pick()
		return
	pick_kind = kind
	if mv != null and mv.has_method("begin_point_pick"):
		mv.begin_point_pick(func(p: Vector2): fire_at(kind, p))
	_dirty = true
	_acc = REFRESH_S


## The map click of a fire-support pick (also called by tests / the playtest flow).
func fire_at(kind: String, p: Vector2) -> void:
	pick_kind = ""
	if fac >= 0:
		_issue({"type": "cc_fire", "building_id": fac, "kind": kind, "pos": p})


func _on_withdraw() -> void:
	if fac >= 0:
		_issue({"type": "cc_withdraw", "building_id": fac})


func _on_last_stand() -> void:
	if fac >= 0:
		_issue({"type": "cc_last_stand", "building_id": fac})


## Card hotkeys (only while the card is shown). Returns true when handled.
func hotkey(k: String) -> bool:
	if not visible:
		return false
	for f in FIRE:
		if k == Hotkeys.key(String(f[2])):
			var b: Button = _fire_btn[String(f[0])]
			if not b.disabled:
				_on_fire(String(f[0]))
			return true
	if k == Hotkeys.key("cc_withdraw"):
		if not _btn_wd.disabled:
			_on_withdraw()
		return true
	if k == Hotkeys.key("cc_last_stand"):
		if not _btn_ls.disabled:
			_on_last_stand()
		return true
	if k == Hotkeys.key("cc_mission_next"):
		if not last_rows.is_empty():
			mark = (mark + 1) % last_rows.size()
			refresh()
		return true
	if k == Hotkeys.key("cc_mission_recall"):
		if mark < last_rows.size() and not (_rows[mark].recall as Button).disabled:
			_on_recall(mark)
		return true
	if k == Hotkeys.key("cc_mission_cancel"):
		if mark < last_rows.size() and not (_rows[mark].cancel as Button).disabled:
			_on_cancel(mark)
		return true
	return false


func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var k := ev as InputEventKey
	if k.ctrl_pressed or k.alt_pressed or k.shift_pressed:
		return
	if hotkey(Hotkeys.event_key(k)):
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- G7 CARDBAR8 (13.9c-51): bottom-bar tabs
## [[TAB, [Button...]], ...] for the bottom command card (presentation/ui7/cardbar8.gd): MISSIONS (RECALL n / CANCEL n
## per running mission row), FIRE SUPPORT, EVACUATE. The mission rows + progress bars stay in the card (info strip).
func bar_tabs() -> Array:
	var mb: Array = []
	for i in mini(last_rows.size(), ROWS):
		mb.append(_rows[i].recall)
		mb.append(_rows[i].cancel)
	var fb: Array = []
	for f in FIRE:
		fb.append(_fire_btn[String(f[0])])
	return [["MISSIONS", mb], ["FIRE SUPPORT", fb], ["EVACUATE", [_btn_wd, _btn_ls]]]


func bar_hide() -> Array:
	return _sections


func bar_title() -> String:
	return "COMMAND CENTRE"
