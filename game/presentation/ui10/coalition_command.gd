extends PanelContainer
## G10 Coalition Command — EaW-simple: build bar + intent cards. Advanced drawer closed by default.

const Coalition10 = preload("res://sim/systems/coalition10.gd")
const INTENTS := [
	["harry", "HARRY", "Bleed and distract with cells"],
	["bleed", "BLEED", "Probe until a gap shows"],
	["flex", "FLEX", "Mercenaries fill the gap"],
	["strike", "STRIKE", "Elite / Ghost strike"],
	["exfil", "EXFIL", "Break contact and recover"],
]

var world_override: SimWorld = null
var fid_override := 0
var advanced_open := false
var sent: Array = []
var _built := false
var _intent_btns: Dictionary = {}
var _layer_lbl: Label
var _board_lbl: Label
var _adv_box: VBoxContainer


static func attach(parent: Control) -> Control:
	var c = (load("res://presentation/ui10/coalition_command.gd") as GDScript).new()
	if parent != null:
		parent.add_child(c)
	return c


func _ready() -> void:
	_ensure_ui()


func _ensure_ui() -> void:
	if _built:
		return
	_built = true
	name = "CoalitionCommand"
	visible = false
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var title := Label.new()
	title.text = "COALITION COMMAND"
	root.add_child(title)
	_layer_lbl = Label.new()
	_layer_lbl.text = "Layer: cells"
	root.add_child(_layer_lbl)
	var intents := HBoxContainer.new()
	intents.add_theme_constant_override("separation", 4)
	root.add_child(intents)
	for row in INTENTS:
		var b := Button.new()
		b.text = String(row[1])
		b.tooltip_text = String(row[2])
		var intent_id := String(row[0])
		b.pressed.connect(func() -> void: _set_intent(intent_id))
		intents.add_child(b)
		_intent_btns[intent_id] = b
	_board_lbl = Label.new()
	_board_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_board_lbl)
	var adv_btn := Button.new()
	adv_btn.text = "Advanced ▸"
	adv_btn.pressed.connect(_toggle_advanced)
	root.add_child(adv_btn)
	_adv_box = VBoxContainer.new()
	_adv_box.visible = false
	var adv_note := Label.new()
	adv_note.text = "Advanced doctrine, contracts and Ghost boards open here later."
	_adv_box.add_child(adv_note)
	root.add_child(_adv_box)


func _toggle_advanced() -> void:
	advanced_open = not advanced_open
	_adv_box.visible = advanced_open


func _world() -> SimWorld:
	return world_override


func _fid() -> int:
	return fid_override


func refresh() -> void:
	_ensure_ui()
	var w := _world()
	var fid := _fid()
	if w == null or not Coalition10.active(w, fid):
		visible = false
		return
	visible = true
	var b: Dictionary = Coalition10.board(w, fid)
	_layer_lbl.text = "Layer: %s · Intent: %s" % [String(b.get("layer", "cells")), String(b.get("intent", "harry"))]
	_board_lbl.text = "cells=%s  contracts=%s  favour=%s  intel=%s  ghost=%s  tech=%s" % [
		str(b.get("cells", 0)),
		str((b.get("contracts", []) as Array).size()),
		str(b.get("patron_favour", 0)),
		String(b.get("intel_grade", "")),
		str(b.get("ghost_ready", false)),
		str((b.get("tech_sources", []) as Array).size()),
	]
	var cur := String(b.get("intent", "harry"))
	for k in _intent_btns:
		(_intent_btns[k] as Button).disabled = false
		(_intent_btns[k] as Button).modulate = Color(1.2, 1.2, 0.8) if String(k) == cur else Color.WHITE


func _set_intent(intent_id: String) -> void:
	var w := _world()
	if w == null:
		return
	Coalition10.set_intent(w, _fid(), intent_id)
	sent.append({"type": "coalition_intent", "intent": intent_id})
	refresh()
