extends RefCounted
## G5 (UI5b) airfield / hangar panel + building buttons (CONTRACTS_G5 sections 3.5, 4, 6).
##   Card (own built field):   Buy light hangar [J], Buy heavy hangar [K] (fields that take them),
##                             Add strip [N] (extra_strip; Machine rail: extra_rail)
##   Card (own built hangar):  Upgrade hangar [U] (level 0..3), Hangar to heavy [Y] (light only)
##   Info panel (above the card, any own field or hangar): strips (open / busy / cratered), hangars
##   (class, level, occupant), pads, engineers on the job, extra strips, and a red "No free hangar"
##   line when no aircraft slot is free (the reason production stalls: Airfield.can_produce).
## Reads w.sys_state.airfield via the Airfield helpers from the HUD refresh (no step in flight).

const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")
const Airfield = preload("res://sim/systems/airfield.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")

const PANEL_W := 560.0

var hud
var panel: PanelContainer
var body: VBoxContainer
var title: Label
var warn: Label
var lines: Label
var _recs: Array = []
var _bid := -1           # building shown (field or hangar)
var _sig := ""


func build(root: Control) -> void:
	panel = UiKit.panel("plate")
	panel.name = "AirfieldPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_W * 0.5
	panel.offset_right = PANEL_W * 0.5
	panel.offset_top = -330
	panel.offset_bottom = -226
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	UiKit.fit_register(panel)
	root.add_child(panel)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	panel.add_child(body)
	title = UiKit.label("AIRFIELD", "header")
	title.name = "AirfieldTitle"
	body.add_child(title)
	warn = UiKit.label("", "bad")
	warn.name = "AirfieldWarn"
	warn.visible = false
	body.add_child(warn)
	lines = UiKit.label("", "small")
	lines.name = "AirfieldLines"
	lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.custom_minimum_size = Vector2(PANEL_W - 24.0, 0)
	body.add_child(lines)


func reset() -> void:
	_recs.clear()
	_bid = -1
	_sig = ""
	if panel != null:
		panel.visible = false


static func is_field_def(def_id: String) -> bool:
	return Airfield.FIELD_KINDS.has(Airfield.kind_of(def_id))


static func is_hangar_def(def_id: String) -> bool:
	return Airfield.kind_of(def_id) == "hangar"


## Card buttons for one own building (hud._rebuild_card -> G4bCommands.add_building_buttons).
func add_building_buttons(b: Dictionary) -> void:
	var def_id := String(b.def)
	if not is_field_def(def_id) and not is_hangar_def(def_id):
		return
	_bid = int(b.id)
	var d := Content.building(def_id)
	var bid := int(b.id)
	var kind := Airfield.kind_of(def_id)
	if Airfield.HANGAR_FIELDS.has(kind):
		if String(d.get("hangar_light", "")) != "":
			_btn("hangar_light", _cost(String(d.hangar_light)), "Buy a light hangar in a free slot of this field (helicopters, light aircraft).",
				{"type": "build_hangar", "building_id": bid, "class": "light"})
		if String(d.get("hangar_heavy", "")) != "" and not bool(d.get("light_only", false)):
			_btn("hangar_heavy", _cost(String(d.hangar_heavy)), "Buy a heavy hangar (jets, bombers, heavy lift).",
				{"type": "build_hangar", "building_id": bid, "class": "heavy"})
	if Airfield.STRIP_KINDS.has(kind) and int(d.get("max_extra", 0)) > 0:
		_btn("extra_strip", "", "Add a runway: more hangar slots and faster turnaround (%d max)." % int(d.get("max_extra", 0)),
			{"type": "upgrade_airfield", "building_id": bid, "kind": "extra_rail" if kind == "rail" else "extra_strip"})
	if kind == "hangar":
		_btn("hangar_level", "", "Hangar level: L1 rearm/refuel 40% faster, L2 repairs parked aircraft, L3 armored roof.",
			{"type": "upgrade_hangar", "building_id": bid, "kind": "level"})
		if String(b.get("class", "light")) == "light":
			_btn("hangar_to_heavy", "", "Rebuild this light hangar as a heavy hangar.",
				{"type": "upgrade_hangar", "building_id": bid, "kind": "to_heavy"})


func _cost(hdef: String) -> String:
	var c: Dictionary = Content.building(hdef).get("cost", {})
	var parts: Array = []
	for k in ["credits", "salvage", "ore"]:
		if int(c.get(k, 0)) > 0:
			parts.append("%d %s" % [int(c[k]), k.substr(0, 2) if k != "credits" else "cr"])
	return " ".join(parts)


func _btn(action: String, sub: String, tip: String, cmd: Dictionary) -> void:
	var hk := Hotkeys.key(action)
	var b: Button = hud._card_button(Hotkeys.label(action), sub, hk, "")
	b.name = "G5_" + action
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): hud._issue(cmd.duplicate(true)))
	var rec := {"btn": b, "kind": "g5", "g5": action, "tip": tip, "hk": hk, "cmd": cmd}
	hud._card_buttons.append(rec)
	_recs.append(rec)
	hud._register_hotkey(hk, b)


## Field id the shown building belongs to (itself for a field, the parent for a hangar), or -1.
func _field(w: SimWorld) -> int:
	if _bid < 0 or not w.entities.has(_bid):
		return -1
	return Airfield.field_of(w, _bid)


func update_state(w: SimWorld) -> void:
	var pf: int = hud._pf()
	for rec in _recs:
		var b: Button = rec.btn
		if not is_instance_valid(b):
			continue
		var cmd: Dictionary = (rec.cmd as Dictionary).duplicate(true)
		cmd["issuer"] = pf
		var reason := ""
		if Airfield.fields(w).has(_field(w)):
			reason = w.preview_command(cmd)
		else:
			reason = "The airfield is not ready yet."
		if String(rec.g5) == "hangar_level":
			var hb = w.entities.get(_bid)
			if hb != null:
				b.text = "%s\nL%d -> L%d" % [Hotkeys.label("hangar_level"), int(hb.get("level", 0)), mini(3, int(hb.get("level", 0)) + 1)]
		rec["reason"] = reason
		b.disabled = reason != ""
		b.tooltip_text = "%s   [Hotkey %s]\n%s%s" % [Hotkeys.label(String(rec.g5)), String(rec.hk), String(rec.tip), ("\nUnavailable: " + reason) if reason != "" else ""]
	_update_panel(w)


func _name(w: SimWorld, id: int) -> String:
	var e = w.entities.get(id)
	if e == null:
		return "-"
	return String(Content.unit(String(e.def)).get("name", e.def))


## Text model of the panel (also used by tests): {title, warn, lines: [String]}.
func model(w: SimWorld) -> Dictionary:
	var fb := _field(w)
	var fr := Airfield.field(w, fb)
	if fb < 0 or fr.is_empty():
		return {}
	var fdef := String(w.entities[fb].def)
	var out := {"title": String(Content.building(fdef).get("name", fdef)).to_upper(), "warn": "", "lines": []}
	var ls: Array = out.lines
	var strips: Array = fr.get("strips", [])
	if not strips.is_empty():
		var parts: Array = []
		for i in strips.size():
			var s: Dictionary = strips[i]
			if not bool(s.get("open", true)):
				parts.append("%d: cratered %ds" % [i + 1, ceili(float(s.get("crater_t", 0)))])
			elif int(s.get("busy_id", -1)) >= 0:
				parts.append("%d: busy (%s)" % [i + 1, _name(w, int(s.busy_id))])
			else:
				parts.append("%d: open" % (i + 1))
		ls.append("Strips  " + "   ".join(parts))
	var hs: Array = fr.get("hangars", [])
	var cap := Airfield.slot_cap(w, fb)
	if cap > 0 or not hs.is_empty():
		var hp: Array = []
		for h in hs:
			var occ := int(h.get("occupant", -1))
			hp.append("%s L%d: %s" % [String(h.get("class", "light")).capitalize(), int(h.get("level", 0)), _name(w, occ) if occ >= 0 else "empty"])
		ls.append("Hangars %d/%d  %s" % [hs.size(), cap, "   ".join(hp) if not hp.is_empty() else "(none: buy one)"])
	var pads: Array = fr.get("pads", [])
	if not pads.is_empty():
		var used := 0
		for p in pads:
			if int(p.get("occupant", -1)) >= 0:
				used += 1
		ls.append("Pads %d/%d in use" % [used, pads.size()])
	var b: Dictionary = w.entities[fb]
	var mx := int(Content.building(fdef).get("max_extra", 0))
	if mx > 0:
		ls.append("Extra strips %d/%d" % [int(b.get("extra_strips", 0)), mx])
	ls.append("Engineers on the job: %d" % Airfield.engineers_at(w, fb).size())
	var free: Dictionary = Airfield.free_slots(w, fb)
	var kind := Airfield.kind_of(fdef)
	if Airfield.HANGAR_FIELDS.has(kind) and int(free.get("light", 0)) + int(free.get("heavy", 0)) + int(free.get("bay", 0)) <= 0:
		out.warn = "No free hangar: buy a hangar [%s] or add a strip." % Hotkeys.key("hangar_light")
	elif (kind == "helipad" or kind == "forward_helipad") and int(free.get("pad", 0)) <= 0:
		out.warn = "No free pad."
	return out


func _update_panel(w: SimWorld) -> void:
	if panel == null:
		return
	var m := model(w) if _bid >= 0 else {}
	if m.is_empty():
		panel.visible = false
		return
	var sig := str(m)
	panel.visible = true
	if sig != _sig:
		_sig = sig
		title.text = String(m.title)
		warn.text = String(m.warn)
		warn.visible = String(m.warn) != ""
		lines.text = "\n".join(m.lines)
	_place()


## Sit just above the bottom panel's real top (it grows with the card) and between the right-hand
## stack (RIGHT_W) and its mirror, so nothing overlaps at any resolution or UI scale.
func _place() -> void:
	var root: Control = panel.get_parent()
	var cw: float = root.size.x if root != null and root.size.x > 0.0 else 1600.0
	var rw = hud.get("RIGHT_W")
	var side: float = (float(rw) if rw != null else 306.0) + 20.0
	var wdt := clampf(cw - 2.0 * side, 300.0, PANEL_W)
	lines.custom_minimum_size.x = wdt - 24.0
	var bot := 226.0
	var bp = root.get_node_or_null("BottomPanel") if root != null else null
	if bp != null:
		bot = maxf(bot, (bp as Control).size.y + 6.0)
	panel.offset_left = -wdt * 0.5
	panel.offset_right = wdt * 0.5
	panel.offset_bottom = -bot
	panel.reset_size()
	panel.offset_top = -bot - panel.get_combined_minimum_size().y
