extends RefCounted
## G4b (UI4B) command-card buttons and the cargo strip, added to the card by hud.gd:
##   mortar (setup_ticks):          Deploy / Pack [E]
##   engineer (can_mine/can_charge): Lay mine [M], Plant charge [O] (targeted, MatchView.g4b modes)
##   carrier (cargo_slots):          Unload at point [I] (click a target), Unload all [L]
##                                   + cargo strip: one icon button per loaded unit (click = unload it)
##   officer alone:                  Transport to point (G2 mission mode, mission transport_to_point)
##   gate building:                  Lock / Unlock [L]
## G5 (UI5b) adds, through this file: the build-card category pages (BuildPages), every G5 unit
## command (G5UnitCmds: aircraft, Drone Team, truck/medic Auto, bombard, engineer assign), the
## airfield/hangar card + info panel (AirfieldPanel), VTOL sling info on the cargo strip and the G5
## rows of the F1 hotkey sheet. Card buttons never take keyboard focus (Space / Tab stay hotkeys).
## The HUD only refreshes with no sim step in flight (hud._process), so reading hud._world() here
## is safe. Every action goes through hud._issue (MatchView.issue) or arms a MatchView.g4b mode.

const HT = preload("res://presentation/hud/hud_theme.gd")
const Fortify = preload("res://sim/systems/fortify.gd")
const Transport = preload("res://sim/systems/transport.gd")
const G2 = preload("res://presentation/view/g2_data.gd")
const BuildPages = preload("res://presentation/ui5/panels/build_pages.gd")
const G5UnitCmds = preload("res://presentation/ui5/panels/g5_unit_cmds.gd")
const AirfieldPanel = preload("res://presentation/ui5/panels/airfield_panel.gd")
const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")
## G6 (UI6b): every G6 command button, the loadout / garage / research panels (presentation/ui6/b/g6_cmds.gd)
const G6Cmds = preload("res://presentation/ui6/b/g6_cmds.gd")

var hud
var strip: PanelContainer        # cargo strip (above the bottom panel)
var strip_box: HBoxContainer
var strip_title: Label
var _recs: Array = []
var _mortars: Array = []
var _carrier := -1
var _gate := -1
var _strip_sig := ""
var pages = BuildPages.new()
var g5u = G5UnitCmds.new()
var afp = AirfieldPanel.new()
var g6c = G6Cmds.new()
var _sheet_done := false


func _mv():
	return hud.mv


func _ent(id: int):
	return hud._world().entities.get(id)


func build(root: Control) -> void:
	strip = PanelContainer.new()
	strip.name = "G4bCargoStrip"
	strip.anchor_left = 0.5
	strip.anchor_right = 0.5
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.offset_left = -300
	strip.offset_right = 300
	strip.offset_top = -284
	strip.offset_bottom = -222
	strip.visible = false
	root.add_child(strip)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	strip.add_child(hb)
	strip_title = HT.make_label("CARGO", HT.AMBER, 13)
	strip_title.custom_minimum_size = Vector2(96, 0)
	hb.add_child(strip_title)
	strip_box = HBoxContainer.new()
	strip_box.add_theme_constant_override("separation", 3)
	hb.add_child(strip_box)
	pages.hud = hud
	g5u.hud = hud
	afp.hud = hud
	afp.build(root)
	g6c.hud = hud
	g6c.build(root)


func reset() -> void:
	_recs.clear()
	if strip != null:
		strip.visible = false
	_strip_sig = ""
	_mortars.clear()
	_carrier = -1
	_gate = -1
	pages.hide_bar()
	g5u.reset()
	afp.reset()
	g6c.reset()


## Called by hud._add_unit_buttons after the G2 buttons. ids are the selected own units.
func add_buttons(_mode: String, ids: Array) -> void:  # _mode: "units" | "engineer"
	var miners: Array = []
	var chargers: Array = []
	var officer := -1
	var others := 0
	for id in ids:
		var e = _ent(int(id))
		if e == null:
			continue
		var d: Dictionary = Content.unit(String(e.def))
		if int(d.get("setup_ticks", 0)) > 0:
			_mortars.append(int(id))
		if bool(d.get("can_mine", false)):
			miners.append(int(id))
		if bool(d.get("can_charge", false)):
			chargers.append(int(id))
		if Transport.is_carrier(e) and _carrier < 0:
			_carrier = int(id)
		if G2.is_officer(e):
			officer = int(id)
		else:
			others += 1
	if not _mortars.is_empty():
		var r = _btn("Deploy", "set up to fire", "E", "deploy", "Mortars must deploy before firing; they pack up to move.")
		r.btn.pressed.connect(_toggle_deploy)
	if not miners.is_empty():
		var m = _btn("Lay mine", "click a cell", "M", "lay_mine", "Engineers walk to the cell and lay an anti-personnel/vehicle mine.")
		m.btn.pressed.connect(func(): _mv().g4b.arm("lay_mine", {"unit_ids": miners}))
	if not chargers.is_empty():
		var c = _btn("Plant charge", "click a target", "O", "plant_charge", "Engineers plant a demolition charge on a wall, building or bridge (100 ticks fuse).")
		c.btn.pressed.connect(func(): _mv().g4b.arm("plant_charge", {"unit_ids": chargers}))
	if _carrier >= 0:
		var cid := _carrier
		var u = _btn("Unload at point", "click a target", "I", "unload_point", "The transport drives to the point and unloads its cargo around it.")
		u.btn.pressed.connect(func(): _mv().g4b.arm("unload_point", {"carrier_id": cid}))
		var ua = _btn("Unload all", "here", "L", "unload_all", "Unload all cargo around the transport now.")
		ua.btn.pressed.connect(func(): hud._issue({"type": "unload_all", "carrier": cid}))
	if officer >= 0 and others == 0:
		var oid := officer
		var t = _btn("Transport to point", "click the target", "", "transport_mission", "The group boards its transports, rides to the point, unloads and secures it.")
		t.btn.pressed.connect(func(): _mv().g2.arm("mission", {"mission": "transport_to_point", "officer_id": oid, "risk": G2.RISKS[hud.g2_cmd.risk_idx]}))
	g5u.add_buttons(ids)
	g6c.add_buttons(ids)
	if _mode == "engineer":
		pages.apply(hud)
	_no_focus()


## Card buttons never take keyboard focus: a focused button would eat Space / Tab / Enter.
func _no_focus() -> void:
	for rec in hud._card_buttons:
		if is_instance_valid(rec.btn):
			(rec.btn as Button).focus_mode = Control.FOCUS_NONE


## Called by hud._rebuild_card for a single own built building.
func add_building_buttons(b: Dictionary) -> void:
	if Fortify.kind_of(String(b.def)) == "gate":
		_gate = int(b.id)
		hud._card_title.text = "GATE   (locked gates stop own units too)"
		var r = _btn("Lock gate", "", "L", "gate_lock", "Lock or unlock the gate. Unlocked gates let own units through.")
		r.btn.name = "G4bGateLock"
		r.btn.pressed.connect(_toggle_gate)
	afp.add_building_buttons(b)
	g6c.add_building_buttons(b)
	_no_focus()


func _btn(title: String, sub: String, hotkey: String, kind: String, tip: String) -> Dictionary:
	var b: Button = hud._card_button(title, sub, hotkey, "")
	var rec := {"btn": b, "kind": "g4b", "g4b": kind, "tip": tip}
	hud._card_buttons.append(rec)
	_recs.append(rec)
	hud._register_hotkey(hotkey, b)
	return rec


func _any_deployed() -> bool:
	for id in _mortars:
		var e = _ent(int(id))
		if e != null and (bool(e.get("deployed", false)) or int(e.get("setup_left", 0)) > 0):
			return true
	return false


func _toggle_deploy() -> void:
	hud._issue({"type": "deploy", "unit_ids": _mortars.duplicate(), "pack": _any_deployed()})


func _gate_locked() -> bool:
	var g = _ent(_gate)
	return g != null and bool(g.get("locked", false))


func _toggle_gate() -> void:
	hud._issue({"type": "set_gate_lock", "building_id": _gate, "locked": not _gate_locked()})


## Labels / disabled state (hud._update_card_state, every refresh) + the cargo strip.
func update_state(w: SimWorld) -> void:
	var pf: int = hud._pf()
	for rec in _recs:
		var b: Button = rec.btn
		if not is_instance_valid(b):
			continue
		var reason := ""
		match String(rec.g4b):
			"deploy":
				var dep := _any_deployed()
				b.text = "[E] %s\n%s" % ["Pack" if dep else "Deploy", "pack up to move" if dep else "set up to fire"]
			"gate_lock":
				var lk := _gate_locked()
				b.text = "[L] %s\n%s" % ["Unlock gate" if lk else "Lock gate", "locked" if lk else "open to own units"]
			"unload_point", "unload_all":
				if Transport.used_slots(_ent(_carrier)) <= 0:
					reason = "The transport is empty."
			"transport_mission":
				var sel: Array = hud._sel_entities(w)
				if not sel.is_empty():
					var pr: String = w.preview_command({"type": "set_mission", "issuer": pf, "officer_id": int(sel[0].id),
						"mission": "transport_to_point", "target": Vector2(sel[0].pos), "radius": 6.0, "risk": "medium"})
					if pr.contains("transport"):
						reason = pr
		rec["reason"] = reason
		b.disabled = reason != ""
		b.tooltip_text = String(rec.tip) + ("\nUnavailable: " + reason if reason != "" else "")
	g5u.update_state(w)
	afp.update_state(w)
	g6c.update_state(w)
	_update_strip()
	_sheet_rows()


## F1 sheet: append the G5 command keys once (the sheet itself is UI5a's hud_extras).
func _sheet_rows() -> void:
	if _sheet_done or hud.get("extras") == null or hud.extras.sheet == null:
		return
	var sc = hud.extras.sheet.find_child("HotkeyScroll", true, false)
	if sc == null or sc.get_child_count() == 0 or not (sc.get_child(0) is GridContainer):
		return
	_sheet_done = true
	var grid: GridContainer = sc.get_child(0)
	var hd := HT.make_label("G5 / G6 COMMANDS", HT.AMBER, 13)
	hd.name = "SheetG5Header"
	grid.add_child(hd)
	grid.add_child(Control.new())
	for row in Hotkeys.sheet_rows():
		var k := HT.make_label(String(row[0]), HT.AMBER, 14)
		grid.add_child(k)
		var d := HT.make_label(String(row[1]), HT.TEXT, 14)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(380, 0)
		grid.add_child(d)
	var k2 := HT.make_label("Tab", HT.AMBER, 14)
	grid.add_child(k2)
	grid.add_child(HT.make_label("Next build category (engineer card)", HT.TEXT, 14))


func _update_strip() -> void:
	var c = _ent(_carrier) if _carrier >= 0 else null
	if c == null or not Transport.is_carrier(c):
		if strip.visible:
			strip.visible = false
			_strip_sig = ""
		return
	strip.visible = true
	var ids: Array = Transport.cargo_ids(c)
	var sig := "%d:%s" % [_carrier, str(ids)]
	strip_title.text = "CARGO %d/%d" % [Transport.used_slots(c), Transport.capacity(String(c.def))]
	var slung: Array = Transport.slung(c)   # G5 VTOL: vehicles carried on the sling
	if not slung.is_empty():
		strip_title.text += "  SLING %d" % slung.size()
	if sig == _strip_sig:
		return
	_strip_sig = sig
	for ch in strip_box.get_children():
		strip_box.remove_child(ch)
		ch.queue_free()
	var cid := _carrier
	for u in c.get("cargo", []):
		var bt := Button.new()
		bt.name = "G4bCargo_%d" % int(u.id)
		bt.custom_minimum_size = Vector2(44, 44)
		bt.icon = ArtCatalog.icon(String(u.def))
		bt.expand_icon = true
		bt.tooltip_text = "%s (%d hp)\nClick: unload this unit next to the transport." % [String(Content.unit(String(u.def)).get("name", u.def)), int(u.get("hp", 0))]
		bt.pressed.connect(func(): hud._issue({"type": "unload", "carrier": cid, "target": c.pos, "cargo_ids": [int(u.id)]}))
		strip_box.add_child(bt)
	var free := Transport.capacity(String(c.def)) - Transport.used_slots(c)
	for i in mini(free, 12):
		var sl := Panel.new()
		sl.custom_minimum_size = Vector2(20, 44)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip_box.add_child(sl)


## Hint line for the command card while a G4b mode is armed or the wall tool is active.
func hint() -> String:
	var mv = _mv()
	if mv == null or mv.get("g4b") == null:
		return ""
	return mv.g4b.status_text()
