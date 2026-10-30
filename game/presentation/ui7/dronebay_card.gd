extends PanelContainer
## G7 DRONEBAY7: the drone bay card (master scope 13.9c-27). One compact HUD card for the player's counter-nanite
## facility drone bay (the workshop's 2nd storey): "DRONE BAY   Drones 9/12", the hive's tasking (13.9c-27a:
## "ALL IN  SCREEN 4  STRIKE 6  REARM 2  RAM 1"), what is ready / aloft / rearming / being rebuilt per kind, and the
## bay's buttons (two rows, so the card stays narrow):
##   LAUNCH  every ready interceptor + gun drone (dronebay_launch kind all; they take the base threats or hold a guard
##           ring over the compound);   FPV  one kamikaze at the heaviest threat (dronebay_launch kind kamikaze);
##   RECALL  every reusable drone back to the launch deck (dronebay_recall);
##   AUTO    automatic release on / off (dronebay_auto; ON by default, owner).
## Reads the world only at the sim hand-over (MatchView.world_events) and at most every REFRESH_S; never writes the
## sim: commands go through MatchView.issue. Shown only while the player has the drone bay selected (13.9c-37: click the workshop).
## Hook (ORCH, presentation/hud/hud.gd, after the OPSUI7 attach line):
##   preload("res://presentation/ui7/dronebay_card.gd").attach(self, left)   # G7 DRONEBAY7 CR: drone bay card

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const S = preload("res://presentation/ui7/ops_style.gd")
const DroneBay7 = preload("res://sim/systems/drone_bay7.gd")

const REFRESH_S := 0.3
const KIND_TEXT := {"interceptor": "AIR", "gun": "GUN", "kamikaze": "FPV"}

var mv = null
var world_override: SimWorld = null    # tests / fit
var fid_override := -1
var force_show := false                 # tests / fit screens: show regardless of the selection
var fac := -1
var _acc := 99.0
var _dirty := true
var _count: Label
var _task: Label
var _line: Label
var _btn_launch: Button
var _btn_fpv: Button
var _btn_recall: Button
var _btn_auto: Button
var last: Dictionary = {}               # last summary shown (tests / playtest log)


static func attach(h, left_stack: Control) -> Control:
	var c = (load("res://presentation/ui7/dronebay_card.gd") as GDScript).new()
	c.mv = h.get("mv") if h != null else null
	if left_stack != null:
		left_stack.add_child(c)
	if c.mv != null and (c.mv as Object).has_signal("world_events"):
		c.mv.world_events.connect(c._on_world_events)
	if c.mv != null and (c.mv as Object).has_signal("selection_changed"):
		c.mv.selection_changed.connect(c._on_selection_changed)   # G7 CARDSEL7 (13.9c-37)
	return c


func _ready() -> void:
	name = "DroneBayCard"
	theme_type_variation = "PlatePanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	UiKit.fit_register(self)
	custom_minimum_size = Vector2(260, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var t := UiKit.label("DRONE BAY", "header")
	t.add_theme_color_override("font_color", S.CYAN)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	_count = UiKit.label("Drones 0/0", "header")
	_count.name = "DroneCount"
	hb.add_child(_count)
	_task = UiKit.label("", "body")
	_task.name = "HiveTasks"
	_task.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	v.add_child(_task)
	_line = UiKit.label("", "body")
	_line.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_line)
	var bb := GridContainer.new()
	bb.columns = 2
	bb.add_theme_constant_override("h_separation", 4)
	bb.add_theme_constant_override("v_separation", 3)
	v.add_child(bb)
	_btn_launch = _mk(bb, "LaunchButton", "LAUNCH", "Launch every ready interceptor and gun drone from the launch deck.", _on_launch)
	_btn_fpv = _mk(bb, "FpvButton", "FPV", "Launch one kamikaze drone at the heaviest attacker.", _on_fpv)
	_btn_recall = _mk(bb, "RecallButton", "RECALL", "Recall every drone to the launch deck (kamikazes in flight are committed).", _on_recall)
	_btn_auto = _mk(bb, "AutoButton", "AUTO ON", "Automatic release when the base is threatened: on / off.", _on_auto)
	visible = false


func _mk(parent: Control, nm: String, text: String, tip: String, cb: Callable) -> Button:
	var b := UiKit.button(text, "", tip)
	b.name = nm
	b.custom_minimum_size = Vector2(0, 24)
	b.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func world() -> SimWorld:
	if world_override != null:
		return world_override
	return mv.get("world") as SimWorld if mv != null else null


func pf() -> int:
	if fid_override >= 0:
		return fid_override
	return int(mv.get("player_fid")) if mv != null and mv.get("player_fid") != null else 0


func _on_selection_changed() -> void:
	if _sim_busy():
		_dirty = true
		_acc = 99.0   # G7 PERFFPS7: refresh at the next frame the world is free (no forced join)
		return
	refresh()


## G7 PERFFPS7: true while a sim step is in flight. Reading mv.world then joins the step on the main thread (a forced
## join: 40 ms on average, up to 110 ms, three times a second in a 2k fight), so the card waits for a free frame.
func _sim_busy() -> bool:
	return world_override == null and mv != null and (mv as Object).has_method("sim_busy") and bool(mv.sim_busy())


## 13.9c-37: shown only while the player has clicked the drone bay (the workshop's 2nd storey) of bay fac.
func _selected(f: int) -> bool:
	if force_show:
		return true
	return mv != null and mv.has_method("part_selected") and bool(mv.part_selected(f, "drone_bay"))


func _on_world_events(_evs = null) -> void:
	_dirty = true


func _process(delta: float) -> void:
	_acc += delta
	if _acc < REFRESH_S or (not _dirty and _acc < REFRESH_S * 4.0):
		return
	if _sim_busy():
		return   # G7 PERFFPS7: try again next frame (the world is free at least every READ_WINDOW_US)
	_acc = 0.0
	_dirty = false
	refresh()


## The hive's tasking line: mode (ALL IN on a breach, ALERT while threatened) and SCREEN / STRIKE / REARM counts
## (+ RAM / GUARD / YOURS when any).
static func tasking(sm: Dictionary) -> String:
	var tk: Dictionary = sm.get("tasks", {})
	var parts := []
	match String(sm.get("mode", "calm")):
		"commit":
			parts.append("ALL IN")
		"alert":
			parts.append("ALERT")
	parts.append("SCREEN %d" % int(tk.get("screen", 0)))
	parts.append("STRIKE %d" % int(tk.get("strike", 0)))
	parts.append("REARM %d" % int(tk.get("rearm", 0)))
	for k in ["ram", "guard", "player"]:
		if int(tk.get(k, 0)) > 0:
			parts.append("%s %d" % [{"ram": "RAM", "guard": "GUARD", "player": "YOURS"}[k], int(tk.get(k, 0))])
	return "  ".join(PackedStringArray(parts))


## Summary line under the count: per kind ready / aloft, rearming, rebuild.
static func detail(sm: Dictionary) -> String:
	var parts := []
	for k in DroneBay7.KINDS:
		var c: Dictionary = sm.kinds.get(k, {})
		var s := "%s %d" % [String(KIND_TEXT.get(k, k)), int(c.get("ready", 0))]
		if int(c.get("aloft", 0)) + int(c.get("queued", 0)) > 0:
			s += " (+%d up)" % (int(c.get("aloft", 0)) + int(c.get("queued", 0)))
		parts.append(s)
	var tail := []
	if int(sm.rearming) > 0:
		tail.append("%d rearming" % int(sm.rearming))
	if String(sm.building) != "":
		tail.append("rebuilding %s %ds" % [String(KIND_TEXT.get(String(sm.building), sm.building)), int(ceil(float(sm.build_left_s)))])
	var s2 := "   ".join(PackedStringArray(parts))
	if not tail.is_empty():
		s2 += "\n" + "   ".join(PackedStringArray(tail))
	return s2


func refresh() -> void:
	var w := world()
	if w == null:
		visible = false
		return
	var l := DroneBay7.bays_of(w, pf())
	if l.is_empty():
		visible = false
		fac = -1
		return
	fac = int(l[0])
	if not _selected(fac):
		visible = false
		return
	var sm := DroneBay7.summary(w, fac)
	last = sm
	visible = true
	_count.text = "Drones %d/%d" % [int(sm.total), int(sm.cap)]
	_count.add_theme_color_override("font_color", S.AMBER if int(sm.total) < int(sm.cap) else S.PHOS)
	_task.text = tasking(sm)
	var md := String(sm.get("mode", "calm"))
	_task.add_theme_color_override("font_color", S.RED if md == "commit" else (S.AMBER if md == "alert" else S.PHOS))
	_line.text = detail(sm)
	var reusable := int(sm.kinds.interceptor.ready) + int(sm.kinds.gun.ready)
	_btn_launch.disabled = reusable <= 0
	_btn_fpv.disabled = int(sm.kinds.kamikaze.ready) <= 0
	_btn_recall.disabled = int(sm.aloft) - int(sm.kinds.kamikaze.aloft) + int(sm.queued) <= 0
	_btn_auto.text = "AUTO ON" if bool(sm.auto) else "AUTO OFF"
	_btn_auto.add_theme_color_override("font_color", S.PHOS if bool(sm.auto) else S.AMBER)


func _issue(cmd: Dictionary) -> void:
	if fac >= 0:
		cmd.building_id = fac
	if mv != null and mv.has_method("issue"):
		mv.issue(cmd)
	_dirty = true
	_acc = REFRESH_S


func _on_launch() -> void:
	_issue({"type": "dronebay_launch", "kind": "all"})


func _on_fpv() -> void:
	_issue({"type": "dronebay_launch", "kind": "kamikaze", "count": 1})


func _on_recall() -> void:
	_issue({"type": "dronebay_recall"})


func _on_auto() -> void:
	_issue({"type": "dronebay_auto", "on": not bool(last.get("auto", true))})

# ---------------------------------------------------------------- G7 CARDBAR8 (13.9c-51): bottom-bar tabs
## [[TAB, [Button...]], ...] for the bottom command card (presentation/ui7/cardbar8.gd); the card itself stays as the
## info strip above the bar with its live read-outs.
func bar_tabs() -> Array:
	return [["GARRISON", [_btn_launch, _btn_fpv, _btn_recall]], ["AUTO", [_btn_auto]]]


func bar_title() -> String:
	return "DRONE BAY"
