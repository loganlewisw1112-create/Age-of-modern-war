extends PanelContainer
## G10 Ghost Command — mission card + target + ROE + Execute. Advanced: stance/abort/Legend/habits.

const GhostConductor10 = preload("res://sim/systems/ghost_conductor10.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")

const TEMPLATES := [
	["QuietDecap", "QUIET DECAP", "Officer silent removal"],
	["SensorBlind", "SENSOR BLIND", "Blind nets then strike"],
	["WorkshopStrike", "WORKSHOP", "Ground their suits"],
	["FeintStorm", "FEINT STORM", "Decoy then real Death"],
]
const ROES := [
	["stealth", "STEALTH"],
	["standard", "STANDARD"],
	["aggressive", "PUSH"],
]

var match_view
var world_override: SimWorld = null
var fid_override := 0
var advanced_open := false
var selected_template := "QuietDecap"
var selected_roe := "stealth"
var selected_target := "officer"
var last_result: Dictionary = {}
var _built := false
var _status: Label
var _adv_box: VBoxContainer
var _go: Button


static func attach(parent: Control) -> Control:
	var c = (load("res://presentation/ui10/ghost_command.gd") as GDScript).new()
	if parent != null:
		parent.add_child(c)
	return c


func _ready() -> void:
	_ensure_ui()


func _ensure_ui() -> void:
	if _built:
		return
	_built = true
	name = "GhostCommand"
	visible = false
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var title := Label.new()
	title.text = "GHOST COMMAND"
	root.add_child(title)
	var cards := HBoxContainer.new()
	root.add_child(cards)
	for row in TEMPLATES:
		var b := Button.new()
		b.text = String(row[1])
		b.tooltip_text = String(row[2])
		var tid := String(row[0])
		b.pressed.connect(func() -> void: selected_template = tid; refresh())
		cards.add_child(b)
	var roes := HBoxContainer.new()
	root.add_child(roes)
	for row in ROES:
		var b2 := Button.new()
		b2.text = String(row[1])
		var rid := String(row[0])
		b2.pressed.connect(func() -> void: selected_roe = rid; refresh())
		roes.add_child(b2)
	_go = Button.new()
	_go.text = "Execute mission"
	_go.pressed.connect(_execute)
	root.add_child(_go)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	var adv_btn := Button.new()
	adv_btn.text = "Advanced ▸"
	adv_btn.pressed.connect(_toggle_advanced)
	root.add_child(adv_btn)
	_adv_box = VBoxContainer.new()
	_adv_box.visible = false
	var adv_note := Label.new()
	adv_note.text = "Scout an enemy structure, build a Ghost Complex and field four healthy Ghost operators."
	_adv_box.add_child(adv_note)
	root.add_child(_adv_box)


func _toggle_advanced() -> void:
	advanced_open = not advanced_open
	_adv_box.visible = advanced_open


func _world() -> SimWorld:
	return world_override


func _fid() -> int:
	return fid_override


func _execute() -> void:
	var w := _world()
	if w == null:
		return
	if match_view != null:
		last_result = match_view.issue({"type": "ghost_card", "template": selected_template, "roe": selected_roe})
		return
	last_result = GhostConductor10.submit_card(w, _fid(), {
		"template": selected_template,
		"target": selected_target,
		"roe": selected_roe,
	})
	refresh()


func refresh() -> void:
	_ensure_ui()
	var w := _world()
	var fid := _fid()
	if w == null or not Coalition10.active(w, fid):
		visible = false
		return
	visible = true
	var b: Dictionary = GhostConductor10.board(w, fid, match_view == null)
	var bits := "Card %s · ROE %s · target %s · intel %s" % [
		selected_template, selected_roe, selected_target, String(b.get("intel_grade", "?")),
	]
	if match_view != null:
		var cmd := {"issuer": fid, "template": selected_template, "roe": selected_roe}
		var gate := GhostConductor10.validate_command(w, cmd)
		_go.disabled = gate != ""
		_go.tooltip_text = gate
		var mission := GhostConductor10.latest_player_mission(w, fid)
		if not mission.is_empty():
			var status := "Complete" if bool(mission.get("done", false)) else String(mission.get("phase", "")).capitalize()
			bits += "\n%s · %s" % [String(mission.get("template", "")), status]
			bits += "\nTarget: %s" % String(mission.get("field", {}).get("name", "enemy structure"))
		if gate != "":
			bits += "\n" + gate
	elif not last_result.is_empty():
		bits += "\nLast: ok=%s mission=%s phase=%s" % [
			str(bool(last_result.get("ok", false))),
			str(last_result.get("mission_id", -1)),
			String(last_result.get("phase", "")),
		]
		if String(last_result.get("reason", "")) != "":
			bits += " · %s" % String(last_result.reason)
	_status.text = bits
	_adv_box.visible = advanced_open
