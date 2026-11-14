extends PanelContainer
## G7.1 FLOW71 (G71_SCOPE.md A3): the one-click "fewer steps to battle" bar. Sits in the facility card strip just
## above the bottom bar (CardBar8 mounts it). Presentation only: reads the world on frames with no sim step in
## flight, never writes the sim (commands go through MatchView.issue).
##   Row 1 (own units or a producer selected): FRONT (send to the front), ATTACK HERE (next map click), the auto
##     logistics toggles for the selection's squads (FUEL / AMMO / REINF / TRAIN), AUTO-DEPLOY for a producer.
##   Row 2 (always while the side has packages, or units are selected): a package name box + SAVE PKG (saves the
##     selection as a mission template in the match and as a player preset in user://flow71_presets.json), then one
##     button per package: click it, then click the target (2 clicks).
## Presets: on the first refresh of a match with no packages, the player's saved presets are re-created in the
## match (flow_template_save with parts) so a package is one click away from the first minute.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const S = preload("res://presentation/ui7/ops_style.gd")
const Flow71 = preload("res://sim/systems/flow71.gd")

const REFRESH_S := 0.3
const PRESET_PATH := "user://flow71_presets.json"
const PKG_SHOWN := 5
const TOGGLES := [["refuel", "FUEL", "Auto refuel: low on fuel -> drives to the nearest supply point, refuels, comes back"],
	["rearm", "AMMO", "Auto rearm: low on ammo -> goes to the nearest supply point (or its squad's ammo bearer), comes back"],
	["reinforce", "REINF", "Auto reinforce: lost members are re-trained at your producers and walk back to the squad"],
	["retrain", "TRAIN", "Auto re-train: only lost specialists are replaced"]]

var mv = null
var world_override: SimWorld = null    # tests / fit
var fid_override := -1
var force_show := false
var preset_path := PRESET_PATH         # tests point this at a scratch file
var btns := {}                          # node name -> Button
var issued: Array = []                  # commands issued (tests / playtest click log)
var clicks := 0                         # bar button clicks (playtest click counts)
var last: Dictionary = {}
var _acc := 99.0
var _row1: HFlowContainer   # G7.1 UIFIX71: the rows wrap (CardBar8 can put the strip in the 270 px inspector)
var _row2: HFlowContainer
var _name: LineEdit
var _pkg_sig := ""
var _presets_done := false


static func attach(h, parent: Control) -> Control:
	var c = (load("res://presentation/ui71/flow_bar.gd") as GDScript).new()
	c.mv = h.get("mv") if h != null else null
	if parent != null:
		parent.add_child(c)
	if c.mv != null and (c.mv as Object).has_signal("selection_changed"):
		c.mv.selection_changed.connect(c._on_sel)
	return c


func _ready() -> void:
	name = "FlowBar71"
	theme_type_variation = "PlatePanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	UiKit.fit_register(self)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	_row1 = HFlowContainer.new()
	_row1.add_theme_constant_override("h_separation", 3)
	_row1.add_theme_constant_override("v_separation", 2)
	v.add_child(_row1)
	_row2 = HFlowContainer.new()
	_row2.add_theme_constant_override("h_separation", 3)
	_row2.add_theme_constant_override("v_separation", 2)
	v.add_child(_row2)
	_btn(_row1, "FlowFront", "FRONT", "Send to the front (the most threatened wall face / contact line)", _on_front)
	_btn(_row1, "FlowAttackHere", "ATTACK HERE", "Attack-move: click a point on the map", _on_attack_here)
	for t in TOGGLES:
		var b := _btn(_row1, "FlowAuto_" + String(t[0]), String(t[1]), String(t[2]), _on_toggle.bind(String(t[0])))
		b.toggle_mode = true
	var d := _btn(_row1, "FlowDeploy", "AUTO-DEPLOY", "New units from this building form a squad and go to the front", _on_deploy)
	d.toggle_mode = true
	_name = LineEdit.new()
	_name.name = "FlowPkgName"
	_name.placeholder_text = "name"
	_name.custom_minimum_size = Vector2(96, 0)
	_name.max_length = 24
	_name.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	_row2.add_child(_name)
	_btn(_row2, "FlowSavePkg", "SAVE PKG", "Save the selection as a mission package (this match + your presets)", _on_save)
	visible = false


func _btn(row: HFlowContainer, nm: String, text: String, tip: String, cb: Callable) -> Button:
	var b := UiKit.button(text, "", tip)
	b.name = nm
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	b.pressed.connect(func() -> void:
		clicks += 1
		cb.call())
	row.add_child(b)
	btns[nm] = b
	return b


# ================================================================ world reads
func _w() -> SimWorld:
	if world_override != null:
		return world_override
	return mv.world if mv != null else null


func pf() -> int:
	if fid_override >= 0:
		return fid_override
	return int(mv.get("player_fid")) if mv != null and mv.get("player_fid") != null else 0


func _busy() -> bool:
	return world_override == null and mv != null and (mv as Object).has_method("sim_busy") and bool(mv.sim_busy())


func _sel() -> Array:
	if mv == null:
		return []
	return mv.selection


func _own_units(w: SimWorld) -> Array:
	var out := []
	for id in _sel():
		var e = w.entities.get(int(id))
		if e != null and e.kind == "unit" and int(e.owner) == pf():
			out.append(int(id))
	return out


func _own_producer(w: SimWorld) -> int:
	for id in _sel():
		var e = w.entities.get(int(id))
		if e != null and e.kind == "building" and int(e.owner) == pf() and not (Content.building(String(e.def)).get("produces", []) as Array).is_empty():
			return int(id)
	return -1


func _on_sel() -> void:
	_acc = 99.0


func _process(delta: float) -> void:
	_acc += delta
	if _acc < REFRESH_S or _busy():
		return
	_acc = 0.0
	refresh()


func refresh() -> void:
	var w := _w()
	if w == null:
		visible = false
		return
	if not _presets_done:
		_presets_done = true
		if Flow71.templates(w, pf()).is_empty():
			for p in load_presets():
				_issue({"type": "flow_template_save", "name": String(p.name), "parts": p.parts})
	var units := _own_units(w)
	var bid := _own_producer(w)
	var tpls := Flow71.templates(w, pf())
	visible = force_show or not units.is_empty() or bid >= 0 or not tpls.is_empty()
	if not visible:
		return
	_row1.visible = force_show or not units.is_empty() or bid >= 0
	(btns.FlowFront as Button).disabled = units.is_empty() and bid < 0
	(btns.FlowAttackHere as Button).disabled = units.is_empty() and bid < 0
	var m := Flow71.mask_of(w, w.entities[units[0]]) if not units.is_empty() else 0
	for t in TOGGLES:
		var b: Button = btns["FlowAuto_" + String(t[0])]
		b.visible = not units.is_empty() or force_show
		b.set_pressed_no_signal((m & int(Flow71.BIT[String(t[0])])) != 0)
	var d: Button = btns.FlowDeploy
	d.visible = bid >= 0 or force_show
	d.set_pressed_no_signal(bid >= 0 and Flow71.deploy_on(w, bid))
	(btns.FlowSavePkg as Button).disabled = units.is_empty()
	_name.visible = not units.is_empty() or force_show
	var sig := ""
	for t in tpls:
		sig += "%d:%s;" % [int(t.id), String(t.name)]
	if sig != _pkg_sig:
		_pkg_sig = sig
		_rebuild_pkgs(tpls)
	last = {"units": units.size(), "producer": bid, "mask": m, "packages": tpls.size(), "deploy": d.button_pressed}


func _rebuild_pkgs(tpls: Array) -> void:
	for nm in btns.keys():
		if String(nm).begins_with("FlowPkg_"):
			var b: Button = btns[nm]
			btns.erase(nm)
			b.queue_free()
	var n := 0
	for t in tpls:
		if n >= PKG_SHOWN:
			break
		n += 1
		var parts := []
		for d in t.parts:
			parts.append("%dx %s" % [int(t.parts[d]), String(Content.unit(String(d)).get("name", d))])
		_btn(_row2, "FlowPkg_%d" % int(t.id), "> " + String(t.name), "Launch %s (%s): click, then click the target" % [String(t.name), ", ".join(parts)], _on_pkg.bind(int(t.id)))


# ================================================================ actions
func _issue(cmd: Dictionary) -> void:
	issued.append(cmd.duplicate(true))
	if world_override != null:
		cmd.issuer = pf()
		world_override.submit(cmd)
	elif mv != null:
		mv.issue(cmd)
	_acc = 99.0


func _send_cmd(to) -> Dictionary:
	var w := _w()
	if w == null:
		return {}
	var units := _own_units(w)
	if not units.is_empty():
		return {"type": "flow_send", "unit_ids": units, "to": to, "mode": "attack"}
	var bid := _own_producer(w)
	if bid >= 0:
		return {"type": "flow_send", "building_id": bid, "to": to, "mode": "attack"}
	return {}


func _on_front() -> void:
	var c := _send_cmd("front")
	if not c.is_empty():
		_issue(c)


func _on_attack_here() -> void:
	if mv == null or not (mv as Object).has_method("begin_point_pick"):
		return
	mv.begin_point_pick(func(p: Vector2) -> void:
		clicks += 1   # the map click is part of the count
		var c := _send_cmd(p)
		if not c.is_empty():
			_issue(c))


func _on_toggle(key: String) -> void:
	var w := _w()
	if w == null:
		return
	var units := _own_units(w)
	if units.is_empty():
		return
	var on: bool = (btns["FlowAuto_" + key] as Button).button_pressed
	var scope := "squad" if int(w.entities[units[0]].get("squad", -1)) >= 0 else "unit"
	_issue({"type": "flow_auto", "key": key, "scope": scope, "unit_ids": units, "on": on})


func _on_deploy() -> void:
	var w := _w()
	if w == null:
		return
	var bid := _own_producer(w)
	if bid >= 0:
		_issue({"type": "flow_auto", "key": "deploy", "scope": "producer", "building_id": bid, "on": (btns.FlowDeploy as Button).button_pressed})


func _on_save() -> void:
	var w := _w()
	if w == null:
		return
	var units := _own_units(w)
	if units.is_empty():
		return
	var parts := {}
	for id in units:
		var d := String(w.entities[id].def)
		parts[d] = int(parts.get(d, 0)) + 1
	var nm := _name.text.strip_edges()
	if nm == "":
		nm = "PKG %d" % (Flow71.templates(w, pf()).size() + 1)
	_issue({"type": "flow_template_save", "name": nm, "parts": parts})
	save_preset(nm, parts)
	_name.text = ""


func _on_pkg(tid: int) -> void:
	if mv == null or not (mv as Object).has_method("begin_point_pick"):
		return
	mv.begin_point_pick(func(p: Vector2) -> void:
		clicks += 1
		_issue({"type": "flow_template_launch", "template_id": tid, "target": p}))


# ================================================================ player presets (user file, outside the sim)
func load_presets() -> Array:
	if not FileAccess.file_exists(preset_path):
		return []
	var f := FileAccess.open(preset_path, FileAccess.READ)
	if f == null:
		return []
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK or typeof(j.data) != TYPE_ARRAY:
		return []
	var out := []
	for p in j.data:
		if typeof(p) == TYPE_DICTIONARY and p.has("name") and typeof(p.get("parts")) == TYPE_DICTIONARY:
			var parts := {}
			for d in p.parts:
				parts[String(d)] = int(p.parts[d])
			out.append({"name": String(p.name), "parts": parts})
	return out


func save_preset(nm: String, parts: Dictionary) -> void:
	var all := load_presets()
	for i in range(all.size() - 1, -1, -1):
		if String(all[i].name) == nm:
			all.remove_at(i)
	all.append({"name": nm, "parts": parts})
	while all.size() > 12:
		all.remove_at(0)
	var f := FileAccess.open(preset_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(all, "  "))
