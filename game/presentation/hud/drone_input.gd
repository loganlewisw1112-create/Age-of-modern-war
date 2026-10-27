extends Node
## G7 DRONE7 drone controls (display + input only; the sim changes only through mv.issue(cmd)).
## G7_REFERENCE master scope section 1. ORCH adds it to hud.gd: di.setup(mv) (CR hud_drone_input).
## Not flying: Y flies the selected flyable drone (pilotable def) in the corner feed; on a Drone Team Y launches a
##   recon drone, Shift+Y a strike drone, Ctrl+Y an FPV.
## Flying: U corner <-> full screen, T thermal / greyscale, B or Esc hands control back to the AI (drone_return ai).
##   Recon / strike: W/S forward/back, A/D strafe, Q/E turn, mouse wheel height, Space drops (strike).
##   FPV: the mouse aims (heading toward the cursor in the feed), W/S speed, wheel height (dive), C detonates.
## Steering goes out as drone_steer setpoints when they change, at most every rules.steer_every ticks, so the
## command log replays the flight exactly. The battle keeps running; the HUD layer (10) stays above the feed (9).

const DroneCamScript = preload("res://presentation/view/drone_cam.gd")
const DronePilot = preload("res://sim/systems/drone_pilot.gd")
const ViewUtil = preload("res://presentation/view/view_util.gd")

const KEYS := {"take": KEY_Y, "full": KEY_U, "thermal": KEY_T, "back": KEY_B, "drop": KEY_SPACE, "detonate": KEY_C}
const FLY_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E]

var mv: Node = null
var cam: Control = null
var layer: CanvasLayer = null
var flying := -1
var _kind := ""
var _hdg := 0.0
var _h := 40.0
var _sent := {}
var _sent_tick := -100
var _held := {}
var _pending_take := false
var log_cmds: Array = []        # every command this node issued (playtest evidence)
var mouse_aim := true           # FPV heading follows the mouse in the feed (playtests drive _hdg directly)


func setup(match_view: Node) -> void:
	mv = match_view
	layer = CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	cam = DroneCamScript.new()
	cam.name = "DroneCam"
	layer.add_child(cam)
	cam.setup(mv)
	if mv.has_signal("world_events"):
		mv.world_events.connect(_on_events)


func _key(action: String) -> int:
	return int(KEYS.get(action, KEY_NONE))


## Fly drone `id` (or launch from a team with `launch`); returns the issue() result.
func take(id: int, launch: String = "") -> Dictionary:
	var c := {"type": "drone_take", "unit_id": id}
	if launch != "":
		c["launch"] = launch
	_pending_take = true
	return _issue(c)


func hand_back() -> void:
	if flying > 0:
		_issue({"type": "drone_return", "unit_id": flying, "to": "ai"})
	_stop()


func toggle_full() -> void:
	if cam != null:
		cam.set_layout("corner" if cam.layout == "full" else "full")


func toggle_thermal() -> void:
	if cam != null:
		cam.set_thermal(not cam.thermal)


func drop() -> void:
	if flying > 0:
		_issue({"type": "drone_release", "unit_id": flying})


func detonate() -> void:
	if flying > 0:
		_issue({"type": "drone_detonate", "unit_id": flying})


func _issue(c: Dictionary) -> Dictionary:
	log_cmds.append(c.duplicate(true))
	return mv.issue(c) if mv != null else {"ok": false}


func _stop() -> void:
	flying = -1
	_held.clear()
	_sent.clear()
	if cam != null and not cam.is_lost():
		cam.show_drone(-1)


func _fly(id: int, kind: String) -> void:
	flying = id
	_kind = kind
	_sent.clear()
	var w: SimWorld = mv.world
	var r = DronePilot.record(w, id) if w != null and mv.world_readable() else null
	_hdg = float(r.hdg) if r != null else 0.0
	_h = float(r.h) if r != null else DronePilot.rf("height_start", 40.0)
	cam.show_drone(id)


func _on_events(evs: Array) -> void:
	var fid := int(mv.player_fid)
	for ev in evs:
		var t := String(ev.get("type", ""))
		if int(ev.get("owner", -99)) != fid and t != "DroneLinkLost":
			continue
		match t:
			"DroneTaken":
				if _pending_take:
					_pending_take = false
					_fly(int(ev.id), String(ev.kind))
			"DroneMunitionAway":
				if int(ev.id) == flying:
					cam.flash("MUNITION AWAY")
			"DroneEmpty":
				if int(ev.id) == flying:
					cam.flash("EMPTY - RETURNING", 2.5)
			"DroneLinkLost", "DroneDetonated":
				if int(ev.id) == flying:
					cam.link_lost()
					flying = -1
					_held.clear()
			"DroneReleased":
				if int(ev.id) == flying and String(ev.get("reason", "")) != "handback":
					_stop()


func _unhandled_input(event: InputEvent) -> void:
	if mv == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if flying < 0:
			if k == _key("take"):
				if _try_take(event.shift_pressed, event.ctrl_pressed):
					get_viewport().set_input_as_handled()
			return
		if k == KEY_ESCAPE or k == _key("back"):
			hand_back()
		elif k == _key("full"):
			toggle_full()
		elif k == _key("thermal"):
			toggle_thermal()
		elif k == _key("drop"):
			drop()
		elif k == _key("detonate"):
			detonate()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if flying < 0 or mv == null:
		return
	if event is InputEventKey and FLY_KEYS.has(int(event.keycode)):
		_held[int(event.keycode)] = event.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and \
			(event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_h = clampf(_h + (5.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -5.0),
			0.0 if _kind == "fpv" else DronePilot.rf("height_min", 8.0), DronePilot.rf("height_max", 120.0))
		get_viewport().set_input_as_handled()


func _try_take(shift: bool, ctrl: bool) -> bool:
	var w: SimWorld = mv.world
	if w == null or not mv.world_readable():
		return false
	for id in mv.selection:
		var e = w.entities.get(int(id))
		if e == null or int(e.owner) != int(mv.player_fid):
			continue
		if bool(Content.unit(String(e.def)).get("drone_team", false)):
			take(int(id), "fpv" if ctrl else ("strike" if shift else "recon"))
			return true
		if DronePilot.pilot_kind(String(e.def)) != "":
			take(int(id))
			return true
	return false


func _down(k: int) -> bool:
	return bool(_held.get(k, false))


func _process(delta: float) -> void:
	if flying < 0 or mv == null:
		return
	var w: SimWorld = mv.world
	if w == null:
		return
	var fwd := (1.0 if _down(KEY_W) else 0.0) - (1.0 if _down(KEY_S) else 0.0)
	var side := (1.0 if _down(KEY_D) else 0.0) - (1.0 if _down(KEY_A) else 0.0)
	if _kind == "fpv":
		side = 0.0
		if mouse_aim and cam != null and cam.visible:
			var m := cam.get_local_mouse_position() - cam.size * 0.5
			if m.length() > 12.0:
				var wd: Vector2 = ViewUtil.iso_inv(m) - ViewUtil.iso_inv(Vector2.ZERO)   # feed is isometric
				_hdg = wrapf(rad_to_deg(atan2(wd.x, -wd.y)) + _hdg_view(), 0.0, 360.0)
	else:
		var turn := (1.0 if _down(KEY_E) else 0.0) - (1.0 if _down(KEY_Q) else 0.0)
		_hdg = wrapf(_hdg + turn * 90.0 * delta, 0.0, 360.0)
	var want := {"hdg": snappedf(_hdg, 1.0), "fwd": fwd, "side": side, "h": snappedf(_h, 1.0)}
	var every := int(DronePilot.R().get("steer_every", 2))
	if want != _sent and int(w.tick) - _sent_tick >= every:
		_sent = want
		_sent_tick = int(w.tick)
		var c := want.duplicate()
		c["type"] = "drone_steer"
		c["unit_id"] = flying
		_issue(c)


## Extra rotation of the FPV aim (0: the feed shares the main view's isometric orientation).
func _hdg_view() -> float:
	return 0.0
