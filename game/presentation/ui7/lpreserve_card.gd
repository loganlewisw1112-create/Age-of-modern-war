extends PanelContainer
## G7 LPRES7: the barracks reserve card (master scope 13.9c-34, Last Protocol only). One compact HUD card for the
## facility's 100-Sentinel barracks reserve: "BARRACKS RESERVE   In 80/100", the tier the defence is at
## ("QRF   FIELD 12   LAST STAND 20/20 held"), what the tiers have sent (posts / QRF / surge / last stand) and the
## trickle, plus the buttons (copy of the drone bay card pattern, 13.9c-27):
##   RELEASE  one quick-reaction squad to the most pressed face (lpres_release);
##   RECALL   every reserve man out comes back to the barracks; automatic release holds a short while (lpres_recall);
##   AUTO     automatic tiered release on / off (lpres_auto; ON by default, owner).
## Reads the world only at the sim hand-over (MatchView.world_events) and at most every REFRESH_S; never writes the
## sim: commands go through MatchView.issue. Shown only while the player has a barracks reserve.
## Hook (presentation/hud/hud.gd, after the drone bay card line):
##   preload("res://presentation/ui7/lpreserve_card.gd").attach(self, left)   # G7 LPRES7: barracks reserve card

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const S = preload("res://presentation/ui7/ops_style.gd")
const LpReserve7 = preload("res://sim/systems/lp_reserve7.gd")

const REFRESH_S := 0.3
const SEC_TEXT := {"n": "N WALL", "e": "E WALL", "s": "GATE", "w": "W WALL", "in": "INSIDE", "core": "CORE"}

var mv = null
var world_override: SimWorld = null    # tests / fit
var fid_override := -1
var force_show := false                 # tests / fit screens: show regardless of the selection
var fac := -1
var _acc := 99.0
var _dirty := true
var _count: Label
var _tier: Label
var _line: Label
var _btn_release: Button
var _btn_recall: Button
var _btn_auto: Button
var last: Dictionary = {}               # last summary shown (tests / playtest log)


static func attach(h, left_stack: Control) -> Control:
	var c = (load("res://presentation/ui7/lpreserve_card.gd") as GDScript).new()
	c.mv = h.get("mv") if h != null else null
	if left_stack != null:
		left_stack.add_child(c)
	if c.mv != null and (c.mv as Object).has_signal("world_events"):
		c.mv.world_events.connect(c._on_world_events)
	if c.mv != null and (c.mv as Object).has_signal("selection_changed"):
		c.mv.selection_changed.connect(c._on_selection_changed)   # G7 CARDSEL7 (13.9c-37)
	return c


func _ready() -> void:
	name = "LpReserveCard"
	theme_type_variation = "PlatePanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	UiKit.fit_register(self)
	custom_minimum_size = Vector2(260, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var t := UiKit.label("BARRACKS RESERVE", "header")
	t.add_theme_color_override("font_color", S.CYAN)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	_count = UiKit.label("In 0/0", "header")
	_count.name = "ReserveCount"
	hb.add_child(_count)
	_tier = UiKit.label("", "body")
	_tier.name = "ReserveTier"
	_tier.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	_tier.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # never widens the HUD's left column (buttons stay put)
	v.add_child(_tier)
	_line = UiKit.label("", "body")
	_line.name = "ReserveLine"
	_line.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_line)
	var bb := GridContainer.new()
	bb.columns = 3
	bb.add_theme_constant_override("h_separation", 4)
	v.add_child(bb)
	_btn_release = _mk(bb, "ReleaseButton", "RELEASE", "Send one quick-reaction squad of Sentinels from the barracks to the most pressed wall or the gate.", _on_release)
	_btn_recall = _mk(bb, "RecallButton", "RECALL", "Call every reserve Sentinel in the field back to the barracks to rest and refill.", _on_recall)
	_btn_auto = _mk(bb, "AutoButton", "AUTO ON", "Automatic tiered release (post refills, quick-reaction squads, breach surge, last stand): on / off.", _on_auto)
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
	return mv.get("_world") as SimWorld if mv != null else null


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
## join: tens of ms, several times a second in a 2k fight), so the card waits for a free frame.
func _sim_busy() -> bool:
	return world_override == null and mv != null and (mv as Object).has_method("sim_busy") and bool(mv.sim_busy())


## 13.9c-37: shown only while the Sentinel Barracks (reserve record .bar) is in the player's selection.
func _selected(Rr: Dictionary) -> bool:
	if force_show:
		return true
	if mv == null:
		return false
	var sel = mv.get("selection")
	return sel is Array and (sel as Array).has(int(Rr.get("bar", -1)))


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


## "QRF   FIELD 12   LAST STAND 20/20 held" (+ the pressed faces while there is pressure).
static func tier_text(sm: Dictionary) -> String:
	var parts := [String(sm.get("tier_name", "CALM"))]
	parts.append("FIELD %d" % int(sm.get("field", 0)))
	if bool(sm.get("gone", false)):
		parts.append("BARRACKS LOST")
	else:
		parts.append("LAST STAND %d/%d %s" % [int(sm.get("ls_in", 0)), int(sm.get("ls", 0)), "held" if int(sm.get("tier", 0)) < 4 else "COMMITTED"])
	return "   ".join(PackedStringArray(parts))


## Second line: what each tier has sent, where the pressure is, the trickle.
static func detail(sm: Dictionary) -> String:
	var rel: Dictionary = sm.get("rel", {})
	var s := "Posts +%d  QRF %d  Surge %d  Hand %d" % [int(rel.get("post", 0)), int(rel.get("qrf", 0)), int(rel.get("surge", 0)), int(rel.get("man", 0))]
	var p: Dictionary = sm.get("p", {})
	var hot := []
	for k in ["n", "e", "s", "w", "in", "core"]:
		if float(p.get(k, 0.0)) > 0.0:
			hot.append("%s %d" % [String(SEC_TEXT[k]), roundi(float(p[k]))])
	if not hot.is_empty():
		s += "\nPressure: " + "  ".join(PackedStringArray(hot))
	if bool(sm.get("gone", false)):
		s += "\nNo replacements: the barracks is gone"
	elif int(sm.get("total", 0)) < int(sm.get("size", 0)):
		s += "\nReplacement in %ds  (trained %d, lost %d)" % [int(ceil(float(sm.get("next_s", 0.0)))), int(sm.get("trained", 0)), int(sm.get("lost", 0))]
	return s


func refresh() -> void:
	var w := world()
	if w == null:
		visible = false
		return
	var l := LpReserve7.reserves_of(w, pf())
	if l.is_empty():
		visible = false
		fac = -1
		return
	fac = int(l[0])
	var sm := LpReserve7.summary(w, fac)
	last = sm
	if not _selected(sm):
		visible = false
		return
	visible = true
	_count.text = "In %d/%d" % [int(sm["in"]), int(sm.size)]
	_count.add_theme_color_override("font_color", S.PHOS if int(sm.total) >= int(sm.size) else S.AMBER)
	_tier.text = tier_text(sm)
	var t := int(sm.tier)
	_tier.add_theme_color_override("font_color", S.RED if t >= 3 else (S.AMBER if t >= 1 else S.PHOS))
	_line.text = detail(sm)
	var ready := int(sm["in"]) - int(sm.ls_in)
	_btn_release.disabled = ready <= 0 or bool(sm.gone)
	_btn_recall.disabled = int(sm.field) <= 0 or bool(sm.gone)
	_btn_auto.text = "AUTO ON" if bool(sm.auto) else "AUTO OFF"
	_btn_auto.add_theme_color_override("font_color", S.PHOS if bool(sm.auto) else S.AMBER)
	_btn_auto.disabled = bool(sm.gone)


func _issue(cmd: Dictionary) -> void:
	if int(last.get("bar", -1)) >= 0:
		cmd.building_id = int(last.bar)
	if mv != null and mv.has_method("issue"):
		mv.issue(cmd)
	_dirty = true
	_acc = REFRESH_S


func _on_release() -> void:
	_issue({"type": "lpres_release"})


func _on_recall() -> void:
	_issue({"type": "lpres_recall"})


func _on_auto() -> void:
	_issue({"type": "lpres_auto", "on": not bool(last.get("auto", true))})

# ---------------------------------------------------------------- G7 CARDBAR8 (13.9c-51): bottom-bar tabs
## [[TAB, [Button...]], ...] for the bottom command card (presentation/ui7/cardbar8.gd); the card itself stays as the
## info strip above the bar with its live read-outs.
func bar_tabs() -> Array:
	return [["RESERVE", [_btn_release, _btn_recall]], ["AUTO RELEASE", [_btn_auto]]]


func bar_title() -> String:
	return "BARRACKS RESERVE"
