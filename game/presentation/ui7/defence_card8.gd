extends PanelContainer
## G7 CARDS8A (13.9c-48): the DEFENCES card. Shown while the player has own defences selected (wall turrets, Human A
## turrets, hardened towers, CIWS mounts, checkpoint / pop-up guns) or one of the facility's two APC gates (MatchView
## parts "gate_outer" / "gate_inner").
##   FIRE MODE   HOLD / RETURN / AT WILL for the whole selection (def_fire_mode; T cycles);
##   PRIORITY    ANY / INF / VEH / AIR preferred targets (def_priority; Y cycles);
##   REPAIR NOW  the nearest facility engineer repairs / rearms the first defence that needs it (def_repair; X);
##   GATE        OPEN / CLOSE / LOCK by hand until released, AUTO releases (gate_set; U / J / K / N). The airlock
##               holds: never both gates open; a closing gate never shuts on a vehicle; a locked gate still lets a
##               sally already inside the airlock out.
## Buttons are pre-checked by the Cards8a reason functions (disabled + reason tooltip). Reads the world only on frames
## with no sim step running; never writes the sim (MatchView.issue).
## Hook (ORCH, presentation/hud/hud.gd, after the lpreserve_card attach line):
##   preload("res://presentation/ui7/defence_card8.gd").attach(self, left)   # G7 CARDS8A: defences card

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const S = preload("res://presentation/ui7/ops_style.gd")
const Cards8a = preload("res://sim/systems/cards8a.gd")
const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")

const REFRESH_S := 0.3
const MODE_BTN := [["hold", "HOLD"], ["return", "RETURN"], ["will", "AT WILL"]]
const PRIO_BTN := [["", "ANY"], ["infantry", "INF"], ["vehicles", "VEH"], ["air", "AIR"]]
const GATE_BTN := [["open", "OPEN", "gate_open"], ["close", "CLOSE", "gate_close"], ["lock", "LOCK", "gate_lock"], ["auto", "AUTO", "gate_auto"]]

var mv = null
var world_override: SimWorld = null    # tests / fit
var fid_override := -1
var sel_override = null                # tests: [ids]
var part_override := ""                # tests: "gate_outer" / "gate_inner" (with fac_override)
var fac_override := -1
var sent: Array = []
var ids: Array = []                    # selected own defences
var gate := ""                         # "outer" / "inner" while a gate is selected
var fac := -1
var _acc := 99.0
var _dirty := true
var _title: Label
var _line: Label
var _def_box: VBoxContainer
var _gate_box: VBoxContainer
var _mode_btn: Dictionary = {}
var _prio_btn: Dictionary = {}
var _gate_btn: Dictionary = {}
var _btn_repair: Button
var _sections: Array = []             # G7 CARDBAR8: section headers (hidden in the bottom-bar layout)


static func attach(h, left_stack: Control) -> Control:
	var c = (load("res://presentation/ui7/defence_card8.gd") as GDScript).new()
	c.mv = h.get("mv") if h != null else null
	if left_stack != null:
		left_stack.add_child(c)
	if c.mv != null and (c.mv as Object).has_signal("world_events"):
		c.mv.world_events.connect(c._on_world_events)
	if c.mv != null and (c.mv as Object).has_signal("selection_changed"):
		c.mv.selection_changed.connect(c._on_selection_changed)
	return c


func _ready() -> void:
	name = "DefenceCard8"
	theme_type_variation = "PlatePanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	UiKit.fit_register(self)
	custom_minimum_size = Vector2(280, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	_title = UiKit.label("DEFENCES", "header")
	_title.add_theme_color_override("font_color", S.CYAN)
	v.add_child(_title)
	_line = _small("")
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_line)
	_def_box = VBoxContainer.new()
	_def_box.add_theme_constant_override("separation", 2)
	v.add_child(_def_box)
	_def_box.add_child(_section("FIRE MODE"))
	var mb := _row(_def_box)
	for m in MODE_BTN:
		var md := String(m[0])
		_mode_btn[md] = _mk(mb, "Mode_" + md, String(m[1]), "", func(): _on_mode(md))
	_def_box.add_child(_section("PRIORITY TARGETS"))
	var pb := _row(_def_box)
	for p in PRIO_BTN:
		var pr := String(p[0])
		_prio_btn[pr] = _mk(pb, "Prio_" + (pr if pr != "" else "any"), String(p[1]), "", func(): _on_prio(pr))
	_btn_repair = _mk(_row(_def_box), "RepairButton", "REPAIR / REARM NOW", "", _on_repair)
	_gate_box = VBoxContainer.new()
	_gate_box.add_theme_constant_override("separation", 2)
	v.add_child(_gate_box)
	_gate_box.add_child(_section("GATE CONTROL"))
	var gb := _row(_gate_box)
	for g in GATE_BTN:
		var gm := String(g[0])
		_gate_btn[gm] = _mk(gb, "Gate_" + gm, String(g[1]), "", func(): _on_gate(gm))
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


func _row(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	parent.add_child(h)
	return h


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


## Reads the selection: own defences (ids) or a gate part (gate + fac).
func _read_selection(w: SimWorld) -> void:
	ids = []
	gate = ""
	fac = -1
	var part := part_override
	var sel: Array = []
	if sel_override != null:
		sel = sel_override
	elif mv != null and mv.get("selection") != null:
		sel = mv.selection
		part = String(mv.get("sel_part")) if mv.get("sel_part") != null else ""
	if part == "gate_outer" or part == "gate_inner":
		var f := fac_override
		if f < 0 and not sel.is_empty():
			f = int(sel[0])
		if not SimWorld.CnFacility.fac(w, f).is_empty() and int(SimWorld.CnFacility.fac(w, f).owner) == pf():
			fac = f
			gate = "outer" if part == "gate_outer" else "inner"
		return
	for raw in sel:
		var b = w.entities.get(int(raw))
		if b != null and int(b.owner) == pf() and Cards8a.is_defence(b):
			ids.append(int(raw))
	ids.sort()


func _setb(b: Button, reason: String, tip: String, on: bool = false) -> void:
	b.disabled = reason != ""
	b.tooltip_text = reason if reason != "" else tip
	b.add_theme_color_override("font_color", S.CYAN if on else S.PHOS)
	b.add_theme_color_override("font_disabled_color", S.CYAN if on else S.DIM)


func refresh() -> void:
	var w := world()
	if w == null:
		visible = false
		return
	_read_selection(w)
	if gate == "" and ids.is_empty():
		visible = false
		return
	visible = true
	var fid := pf()
	_def_box.visible = gate == ""
	_gate_box.visible = gate != ""
	if gate != "":
		var GT: Dictionary = SimWorld.CnFacility.fac(w, fac).get("gate", {})
		var stv := String(GT.get("o" if gate == "outer" else "i", "open")) if not GT.is_empty() else "open"
		var gm := Cards8a.gate_mode(w, fac, gate)
		_title.text = "%s GATE" % gate.to_upper()
		_line.text = "Gate %s.  Control: %s.%s" % [stv, "automatic" if gm == "auto" else "by hand (" + gm + ")",
			"  Hardened (threat)." if bool(GT.get("hard", false)) else ""]
		for g in GATE_BTN:
			var md := String(g[0])
			var why := Cards8a.gate_reason(w, fid, fac, gate, md)
			_setb(_gate_btn[md], why, "%s (%s)" % [Hotkeys.label(String(g[2])), Hotkeys.key(String(g[2]))], gm == md)
		return
	var b0: Dictionary = w.entities[int(ids[0])]
	_title.text = "DEFENCES  %d" % ids.size() if ids.size() > 1 else String(Content.building(String(b0.def)).get("name", "DEFENCE")).to_upper()
	var hp := 0.0
	var mx := 0.0
	for id in ids:
		var b: Dictionary = w.entities[int(id)]
		hp += float(b.hp)
		mx += float(b.get("max_hp", b.hp))
	var m0 := Cards8a.mode_of(w, int(ids[0]))
	var p0 := Cards8a.prio_of(w, int(ids[0]))
	var txt := "Hull %d%%   %s   targets %s" % [roundi(100.0 * hp / maxf(mx, 1.0)), String(Cards8a.MODE_TEXT[m0]), String(Cards8a.PRIO_TEXT[p0]).to_lower()]
	if SimWorld.Ciws7.is_mount(b0):
		txt += "   drum %d" % SimWorld.Ciws7.ammo(w, int(ids[0]))
	_line.text = txt
	for m in MODE_BTN:
		var md := String(m[0])
		_setb(_mode_btn[md], Cards8a.fire_mode_reason(w, fid, ids, md), "%s (%s cycles)" % [String(Cards8a.MODE_TEXT[md]).capitalize(), Hotkeys.key("def_fire_mode")], m0 == md and _all(w, "m", md))
	for p in PRIO_BTN:
		var pr := String(p[0])
		_setb(_prio_btn[pr], Cards8a.prio_reason(w, fid, ids, pr), "Prefer %s (%s cycles)" % [String(Cards8a.PRIO_TEXT[pr]).to_lower(), Hotkeys.key("def_priority")], p0 == pr and _all(w, "p", pr))
	_setb(_btn_repair, _repair_reason(w), "Send the nearest facility engineer to repair / rearm now (%s)." % Hotkeys.key("def_repair"))


func _all(w: SimWorld, what: String, val: String) -> bool:
	for id in ids:
		if (Cards8a.mode_of(w, int(id)) if what == "m" else Cards8a.prio_of(w, int(id))) != val:
			return false
	return true


## The first selected defence a repair-now order is valid for, or -1.
func repair_target(w: SimWorld) -> int:
	for id in ids:
		if Cards8a.repair_reason(w, pf(), int(id)) == "":
			return int(id)
	return -1


func _repair_reason(w: SimWorld) -> String:
	if repair_target(w) >= 0:
		return ""
	return Cards8a.repair_reason(w, pf(), int(ids[0])) if not ids.is_empty() else "Select a defence."


func _issue(cmd: Dictionary) -> void:
	sent.append(cmd.duplicate(true))
	if mv != null and mv.has_method("issue"):
		mv.issue(cmd)
	_dirty = true
	_acc = REFRESH_S


func _on_mode(md: String) -> void:
	if not ids.is_empty():
		_issue({"type": "def_fire_mode", "building_ids": ids.duplicate(), "mode": md})


func _on_prio(pr: String) -> void:
	if not ids.is_empty():
		_issue({"type": "def_priority", "building_ids": ids.duplicate(), "prio": pr})


func _on_repair() -> void:
	var w := world()
	var bid := repair_target(w) if w != null else -1
	if bid >= 0:
		_issue({"type": "def_repair", "building_id": bid})


func _on_gate(md: String) -> void:
	if gate != "" and fac >= 0:
		_issue({"type": "gate_set", "building_id": fac, "gate": gate, "mode": md})


func _press(b: Button, cb: Callable) -> void:
	if not b.disabled:
		cb.call()


## Card hotkeys (only while shown). Returns true when handled.
func hotkey(k: String) -> bool:
	if not visible:
		return false
	var w := world()
	if gate != "":
		for g in GATE_BTN:
			if k == Hotkeys.key(String(g[2])):
				var md := String(g[0])
				_press(_gate_btn[md], func(): _on_gate(md))
				return true
		return false
	if k == Hotkeys.key("def_fire_mode") and w != null:
		var cur := Cards8a.MODES.find(Cards8a.mode_of(w, int(ids[0])))
		var md := String(Cards8a.MODES[(cur + 1) % Cards8a.MODES.size()])
		_press(_mode_btn[md], func(): _on_mode(md))
		return true
	if k == Hotkeys.key("def_priority") and w != null:
		var cur := Cards8a.PRIOS.find(Cards8a.prio_of(w, int(ids[0])))
		var pr := String(Cards8a.PRIOS[(cur + 1) % Cards8a.PRIOS.size()])
		_press(_prio_btn[pr], func(): _on_prio(pr))
		return true
	if k == Hotkeys.key("def_repair"):
		_press(_btn_repair, _on_repair)
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
## [[TAB, [Button...]], ...] for the bottom command card (presentation/ui7/cardbar8.gd); the card itself stays as the
## info strip above the bar with its live read-outs.
func bar_tabs() -> Array:
	if gate != "":
		var gb: Array = []
		for g in GATE_BTN:
			gb.append(_gate_btn[String(g[0])])
		return [["GATE", gb]]
	var mb: Array = []
	for m in MODE_BTN:
		mb.append(_mode_btn[String(m[0])])
	var pb: Array = []
	for p in PRIO_BTN:
		pb.append(_prio_btn[String(p[0])])
	return [["FIRE MODE", mb], ["TARGETS", pb], ["REPAIR", [_btn_repair]]]


func bar_hide() -> Array:
	return _sections


func bar_title() -> String:
	return _title.text
