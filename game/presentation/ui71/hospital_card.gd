extends Node
## G7.1 CNOPS71 J6 hospital card (docs/G71_SCOPE.md J6; roster section 2: aid station -> hospital card). With an own
## hospital block selected in Last Protocol (def hospital71 / hospital71_wing) it shows the wards and their beds
## (Hospital71.census vs rules beds), patients waiting at the roof pad for the medevac lift, the quarantine ward state,
## and two orders: SEAL / OPEN QUARANTINE (hosp_quarantine) and MEDEVAC WOUNDED (hosp_medevac for the side's wounded on
## the ground who are not in the hospital's care yet, lowest ids first, at most MAX_LIFT). Hidden otherwise.
## Display + the player's own commands only (MatchView.issue); reads the world between steps.
## Wiring (ORCH, like AmmoPanel71): HospitalCard71.attach(mv) in match_view._init_view; it mounts on the HUD's scaled root.
## Layout: bottom-right above the bottom panel (the ammo panel shows for units, this one for the hospital: never both).
const Hospital71 = preload("res://sim/systems/hospital71.gd")

const BOTTOM_H := 220.0
const PANEL_W := 250.0
const REFRESH_S := 0.4
const MAX_LIFT := 6
const NAMES := {"triage": "Triage bay", "surgery": "Surgery", "icu": "ICU", "recovery": "Recovery ward",
	"decon": "Decon showers", "scan": "Scan gate", "quarantine": "Quarantine", "prosthetics": "Prosthetics bay",
	"pad": "Roof pad (lift)"}

var mv: Node = null
var panel: PanelContainer = null
var _head: Label = null
var _body: Label = null
var _seal: Button = null
var _lift: Button = null
var _acc := 0.0
var _sig := ""
var info: Dictionary = {}     # test hook: the last summary shown ({} = hidden)


static func attach(view: Node) -> Node:
	var r = (load("res://presentation/ui71/hospital_card.gd") as GDScript).new()
	r.name = "HospitalCard71"
	view.add_child(r)
	r.mv = view
	return r


## The selected own hospital building id (-1 = none).
static func picked(w: SimWorld, fid: int, ids: Array) -> int:
	for id in ids:
		var b = w.entities.get(int(id))
		if b == null or String(b.kind) != "building" or int(b.owner) != fid:
			continue
		var d := Content.building(String(b.def))
		if bool(d.get("hospital71", false)) or bool(d.get("hospital71_wing", false)):
			return int(id)
	return -1


## Own wounded on the ground not yet in the hospital's care, ascending id, at most MAX_LIFT.
static func liftable(w: SimWorld, fid: int) -> Array:
	var out := []
	var md = w.sys_state.get("medical")
	if md == null:
		return out
	var ks: Array = (md.get("wounded", {}) as Dictionary).keys()
	ks.sort()
	for k in ks:
		var e = w.entities.get(int(k))
		if e != null and int(e.owner) == fid and float(e.get("hp", 0.0)) > 0.0 and Hospital71.ward_of(e) == "" \
				and not e.has("evac_by"):
			out.append(int(k))
			if out.size() >= MAX_LIFT:
				break
	return out


## {wards: [[ward, n, beds (-1 = no limit)]], locked, reason, lift: [ids], pad: n waiting} for the side, {} = no card.
static func summary(w: SimWorld, fid: int, ids: Array) -> Dictionary:
	if not w.sys_state.has("lp") or Hospital71.st(w) == null or picked(w, fid, ids) < 0:
		return {}
	var c := Hospital71.census(w)
	var beds: Dictionary = Hospital71.R().get("beds", {})
	var rows := []
	for wd in Hospital71.WARDS:
		rows.append([wd, int(c.get(wd, 0)), int(beds.get(wd, -1))])
	var s: Dictionary = Hospital71.st(w)
	return {"wards": rows, "locked": Hospital71.locked(w), "reason": String(s.ql.get("reason", "")),
		"lift": liftable(w, fid), "pad": int(c.get("pad", 0))}


func _process(delta: float) -> void:
	if mv == null:
		return
	if panel == null:
		_try_mount()
		return
	_acc += delta
	if _acc >= REFRESH_S:
		if mv.has_method("sim_busy") and mv.sim_busy():
			return
		_acc = 0.0
		refresh()


func _try_mount() -> void:
	var main = mv.get_parent()
	var hud = main.get("hud") if main != null else null
	if hud == null or hud.get("layer") == null:
		return
	var root = hud.layer.root
	if root == null or root.has_node("HospitalCard71Panel"):
		return
	_build_panel(root)


func _build_panel(root: Control) -> void:
	panel = PanelContainer.new()
	panel.name = "HospitalCard71Panel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -8.0
	panel.offset_bottom = -BOTTOM_H - 8.0
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.visible = false
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	_head = Label.new()
	_head.text = "Trauma hospital"
	v.add_child(_head)
	_body = Label.new()
	v.add_child(_body)
	_seal = Button.new()
	_seal.pressed.connect(seal)
	v.add_child(_seal)
	_lift = Button.new()
	_lift.pressed.connect(lift)
	v.add_child(_lift)


func refresh() -> void:
	if panel == null or mv == null or not mv.has_method("world_readable") or not mv.world_readable():
		return
	var w: SimWorld = mv.world
	info = summary(w, int(mv.player_fid), mv.selection)
	var sig := str(info)
	if sig == _sig:
		return
	_sig = sig
	panel.visible = not info.is_empty()
	if info.is_empty():
		return
	var lines := []
	for r in info.wards:
		lines.append("%-16s %d%s" % [NAMES.get(r[0], r[0]), int(r[1]), (" / %d" % int(r[2])) if int(r[2]) >= 0 else ""])
	_head.text = "Trauma hospital%s" % ("   QUARANTINE SEALED" if bool(info.locked) else "")
	_body.text = "\n".join(PackedStringArray(lines)) + (("\nSealed: " + String(info.reason)) if bool(info.locked) else "")
	_seal.text = "OPEN QUARANTINE" if bool(info.locked) else "SEAL QUARANTINE"
	_lift.text = "MEDEVAC WOUNDED (%d)" % (info.lift as Array).size()
	_lift.disabled = (info.lift as Array).is_empty()
	_lift.tooltip_text = "Book the medevac lift for the wounded on the ground" if not _lift.disabled else "No wounded waiting."


func seal() -> void:
	if mv == null or info.is_empty():
		return
	mv.issue({"type": "hosp_quarantine", "on": not bool(info.locked), "reason": "by order"})
	_sig = ""


func lift() -> void:
	if mv == null or info.is_empty() or (info.lift as Array).is_empty():
		return
	mv.issue({"type": "hosp_medevac", "ids": (info.lift as Array).duplicate()})
	_sig = ""
