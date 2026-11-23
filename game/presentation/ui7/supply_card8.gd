extends PanelContainer
## G7 SUPPLY8 (13.9c-48): the magazine / ammo + fuel bay card, shown while the facility's magazine (or the carrier
## garage beside it) is selected. Lpreserve-card pattern (one compact HUD card in the hud's left stack):
##   stock levels + low-stock alerts (ammo / fuel of the side, the typed rounds delivered by the mix);
##   ORDER DROP   airdrop retrieval op (sup8_order): pod outside the gate, 2 GO teams + 4 engineers + the carrier;
##   PRIORITY     resupply class first (sup8_prio: walls/turrets -> teams -> vehicles -> aircraft -> balanced);
##   MIX          pick a round type (AP / HE / INC / CN), then +10 / -10 of its share (sup8_mix).
## Every button is pre-checked by the sim (Supply8.order_reason / validate_command): disabled + the reason as tooltip.
## Reads the world only when the sim is free and at most every REFRESH_S; never writes the sim (MatchView.issue).
## Hotkeys (presentation/ui5/panels/hotkeys.gd group sup8): T order, Y priority, C round type, V +10, X -10.
## Hook (presentation/hud/hud.gd, after the barracks reserve card line):
##   preload("res://presentation/ui7/supply_card8.gd").attach(self, left)   # G7 SUPPLY8: magazine / ammo + fuel card

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const S = preload("res://presentation/ui7/ops_style.gd")
const Supply8 = preload("res://sim/systems/supply8.gd")
const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")

const REFRESH_S := 0.3
const CLS := ["walls", "teams", "vehicles", "aircraft", ""]
const CLS_TEXT := {"walls": "WALLS/TURRETS", "teams": "TEAMS", "vehicles": "VEHICLES", "aircraft": "AIRCRAFT", "": "BALANCED"}
const MIX_TEXT := {"ap": "AP", "he": "HE", "inc": "INC", "cn": "CN"}

var mv = null
var world_override: SimWorld = null    # tests / fit
var fid_override := -1
var force_show := false
var fac := -1
var mark := 0                           # round type the +/- buttons change (index in Supply8.MIX_KEYS)
var _acc := 99.0
var _dirty := true
var _stock: Label
var _alert: Label
var _mix: Label
var _op: Label
var _btn_order: Button
var _btn_prio: Button
var _btn_type: Button
var _btn_up: Button
var _btn_down: Button
var last: Dictionary = {}               # last summary shown (tests / playtest log)
var issued: Array = []                  # commands sent (tests)


static func attach(h, left_stack: Control) -> Control:
	var c = (load("res://presentation/ui7/supply_card8.gd") as GDScript).new()
	c.mv = h.get("mv") if h != null else null
	if left_stack != null:
		left_stack.add_child(c)
	if c.mv != null and (c.mv as Object).has_signal("world_events"):
		c.mv.world_events.connect(c._on_world_events)
	if c.mv != null and (c.mv as Object).has_signal("selection_changed"):
		c.mv.selection_changed.connect(c._on_selection_changed)
	return c


func _ready() -> void:
	name = "SupplyCard8"
	theme_type_variation = "PlatePanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	UiKit.fit_register(self)
	custom_minimum_size = Vector2(260, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var t := UiKit.label("MAGAZINE  AMMO + FUEL", "header")
	t.add_theme_color_override("font_color", S.CYAN)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	_stock = _small(v, "SupplyStock")
	_alert = _small(v, "SupplyAlert")
	_mix = _small(v, "SupplyMix")
	_op = _small(v, "SupplyOp")
	var bb := GridContainer.new()
	bb.columns = 3
	bb.add_theme_constant_override("h_separation", 4)
	v.add_child(bb)
	_btn_order = _mk(bb, "OrderButton", "ORDER DROP", _on_order)
	_btn_prio = _mk(bb, "PrioButton", "FIRST", _on_prio)
	_btn_type = _mk(bb, "MixTypeButton", "TYPE", _on_type)
	_btn_up = _mk(bb, "MixUpButton", "+10%", _on_up)
	_btn_down = _mk(bb, "MixDownButton", "-10%", _on_down)
	visible = false


func _small(parent: Control, nm: String) -> Label:
	var l := UiKit.label("", "body")
	l.name = nm
	l.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _mk(parent: Control, nm: String, text: String, cb: Callable) -> Button:
	var b := UiKit.button(text, "", "")
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


func _sim_busy() -> bool:
	return world_override == null and mv != null and (mv as Object).has_method("sim_busy") and bool(mv.sim_busy())


func _on_selection_changed() -> void:
	if _sim_busy():
		_dirty = true
		_acc = 99.0
		return
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


## The facility whose magazine / carrier garage is in the selection (-1 when none).
func _selected_fac(w: SimWorld) -> int:
	var l := Supply8.facs_of(w, pf())
	if l.is_empty():
		return -1
	if force_show:
		return int(l[0])
	if mv == null:
		return -1
	var sel = mv.get("selection")
	if not (sel is Array):
		return -1
	for id in sel:
		var f := Supply8.fac_of_magazine(w, int(id))
		if f >= 0 and l.has(f):
			return f
	return -1


static func mix_text(sm: Dictionary, mk: int) -> String:
	var parts := []
	for i in Supply8.MIX_KEYS.size():
		var k: String = Supply8.MIX_KEYS[i]
		parts.append("%s%s %d%%" % [">" if i == mk else "", MIX_TEXT[k], int(sm.mix.get(k, 0))])
	return "Rounds: " + "  ".join(PackedStringArray(parts))


static func op_text(sm: Dictionary) -> String:
	var s := ""
	if String(sm.ph) != "":
		s = "%s   GO %d  ENG %d" % [String(sm.prog), int(sm.go), int(sm.eng)]
	else:
		s = "Carrier %s  hull %d/%d  shield %d/%d" % [String(sm.car), roundi(float(sm.car_hp)), roundi(float(sm.car_max)), roundi(float(sm.sh)), roundi(float(sm.sh_max))]
		if int(sm.cd_s) > 0:
			s += "\nNext drop in %ds" % int(sm.cd_s)
		if bool(sm.retry):
			s += "   RETRY OWED (free)"
	s += "\nDrops %d delivered, %d lost%s" % [int(sm.n_ok), int(sm.n_fail), ("   last: " + String(sm.last)) if String(sm.last) != "" else ""]
	return s


func refresh() -> void:
	var w := world()
	if w == null:
		visible = false
		return
	fac = _selected_fac(w)
	if fac < 0:
		visible = false
		return
	var sm := Supply8.summary(w, fac)
	if sm.is_empty():
		visible = false
		return
	last = sm
	visible = true
	var low: Dictionary = sm.low
	_stock.text = "AMMO %d   FUEL %d   (AP %d HE %d INC %d CN %d delivered)" % [int(sm.ammo), int(sm.fuel), int(sm.typed.get("ap", 0)), int(sm.typed.get("he", 0)), int(sm.typed.get("inc", 0)), int(sm.typed.get("cn", 0))]
	_stock.add_theme_color_override("font_color", S.AMBER if not low.is_empty() else S.PHOS)
	var al := []
	for r in ["ammo", "fuel"]:
		if bool(low.get(r, false)):
			al.append("LOW %s (< %d)" % [r.to_upper(), int(sm.low_thr.get(r, 0))])
	_alert.text = "  ".join(PackedStringArray(al)) if not al.is_empty() else "Stock OK"
	_alert.add_theme_color_override("font_color", S.RED if not al.is_empty() else S.PHOS)
	_mix.text = mix_text(sm, mark) + "\nResupply first: " + String(CLS_TEXT.get(String(sm.first), "BALANCED"))
	_op.text = op_text(sm)
	var why := String(sm.reason)
	_btn_order.text = "RETRY DROP" if bool(sm.retry) else "ORDER DROP %d" % int(sm.cost)
	_setb(_btn_order, why, "Airdrop retrieval: a pod lands 4-6 tiles outside the gate; 2 Sentinel GO teams secure it, 4 engineers bring it home on the tracked carrier.", "sup8_order")
	_btn_prio.text = "FIRST: " + String(CLS_TEXT.get(String(sm.first), "BALANCED")).split("/")[0]
	_setb(_btn_prio, _why({"type": "sup8_prio", "first": _next_cls(String(sm.first))}), "Resupply priority: which class bearers, lockers and engineers serve first (walls/turrets, teams, vehicles, aircraft, balanced).", "sup8_prio")
	var k: String = Supply8.MIX_KEYS[mark]
	_btn_type.text = "TYPE: " + String(MIX_TEXT[k])
	_setb(_btn_type, "", "Pick the round type the +10% / -10% buttons change.", "sup8_mix_type")
	_setb(_btn_up, _why({"type": "sup8_mix", "key": k, "delta": 10}), "More %s rounds in every delivery (taken from the largest other share)." % String(MIX_TEXT[k]), "sup8_mix_up")
	_setb(_btn_down, _why({"type": "sup8_mix", "key": k, "delta": -10}), "Fewer %s rounds in every delivery (given to the smallest other share)." % String(MIX_TEXT[k]), "sup8_mix_down")


func _setb(b: Button, why: String, tip: String, action: String) -> void:
	b.disabled = why != ""
	var hk := Hotkeys.key(action)
	b.tooltip_text = (why if why != "" else tip) + ("  [%s]" % hk if hk != "" else "")


func _why(cmd: Dictionary) -> String:
	var w := world()
	if w == null:
		return "No world."
	cmd.issuer = pf()
	cmd.building_id = int(last.get("mag", -1))
	return Supply8.validate_command(w, cmd)


static func _next_cls(cur: String) -> String:
	var i := CLS.find(cur)
	return String(CLS[(i + 1) % CLS.size()])


func _issue(cmd: Dictionary) -> void:
	cmd.building_id = int(last.get("mag", -1))
	issued.append(cmd.duplicate())
	if mv != null and mv.has_method("issue"):
		mv.issue(cmd)
	elif world_override != null:   # tests: apply straight to the world
		cmd.issuer = pf()
		if Supply8.validate_command(world_override, cmd) == "":
			Supply8.apply_command(world_override, cmd)
	_dirty = true
	_acc = REFRESH_S


func _on_order() -> void:
	if not _btn_order.disabled:
		_issue({"type": "sup8_order"})


func _on_prio() -> void:
	if not _btn_prio.disabled:
		_issue({"type": "sup8_prio", "first": _next_cls(String(last.get("first", "")))})


func _on_type() -> void:
	mark = (mark + 1) % Supply8.MIX_KEYS.size()
	refresh()


func _on_up() -> void:
	if not _btn_up.disabled:
		_issue({"type": "sup8_mix", "key": Supply8.MIX_KEYS[mark], "delta": 10})


func _on_down() -> void:
	if not _btn_down.disabled:
		_issue({"type": "sup8_mix", "key": Supply8.MIX_KEYS[mark], "delta": -10})


## Card hotkeys (group sup8, rebindable in hotkeys.gd); true when the key was used.
func hotkey(k: String) -> bool:
	if not visible:
		return false
	var map := {"sup8_order": _on_order, "sup8_prio": _on_prio, "sup8_mix_type": _on_type, "sup8_mix_up": _on_up, "sup8_mix_down": _on_down}
	for a in map:
		if k != "" and k == Hotkeys.key(a):
			(map[a] as Callable).call()
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
	return [["STOCK", []], ["PRIORITY", [_btn_prio]], ["AMMO MIX", [_btn_type, _btn_up, _btn_down]], ["AIRDROP", [_btn_order]]]


func bar_title() -> String:
	return "MAGAZINE  AMMO + FUEL"
