extends Node2D
## G7.1 FIRES71 (B4): the hold-key radial fire menu. Key = Hotkeys action "fire_radial71" (rebindable; ORCH seq 1830:
## QUOTELEFT, the backquote / tilde key, PROVISIONAL), never a hard-coded key.
##   hold the key           -> radial at the mouse; move toward a slot
##   release                -> the slot under the mouse is armed (released in the centre = cancel)
##   armed strike kind      -> left click = point; drag = line; Shift + drag = box; Ctrl + drag = creeping
##                             -> one `fire_mission` (StrikeShape.make_cmd)
##   armed "Conductor"      -> press at the orbit centre, drag out the radius (click = default); Ctrl = clockwise
##                             -> `conductor_orbit` (ConductorOrbit.make_cmd)
##   armed "FPF"            -> left click near a wall face = `fpf_fire` on that face; Shift + click = every face
##   "Sectors"              -> opens the kill-zone paint tool (presentation/ui71/killzone_paint.gd)
##   right click / Esc      -> cancel
## Clicks for "a barrage along one wall lane": hold + release on HE (1) + drag the lane (1) = 2 actions.
## Display + input only: writes nothing but MatchView.issue() (the player's own commands).
## Wiring: presentation/view/g71_attach.gd LAYERS (ORCH), at "over_units"; setup(mv) is called once.
const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")
const StrikeShape = preload("res://presentation/ui71/strike_shape.gd")
const ConductorOrbit = preload("res://presentation/ui71/conductor_orbit.gd")
const KillZone71 = preload("res://sim/systems/killzone71.gd")

const ACTION := "fire_radial71"
## [id, label, enabled]. Illumination stays an empty slot until I5 (roster 5A Q6).
const SLOTS := [["he", "HE", true], ["smoke", "Smoke", true], ["illumination", "Illum (I5)", false],
	["thermobaric", "Thermobaric", true], ["incendiary", "Incendiary", true], ["precision", "Precision", true],
	["gunship", "Conductor", true], ["cluster", "Cluster", true], ["smart", "Smart", true], ["fpf", "FPF", true],
	["sectors", "Sectors", true]]
const R_IN := 40.0
const R_OUT := 160.0
const R_LAB := 0.58   # label radius as a fraction of the ring width (11 labels side by side need ~62 px between centres)
const COL_BG := Color(0.06, 0.08, 0.1, 0.78)
const COL_HI := Color(1.0, 0.6, 0.2, 0.92)
const COL_TX := Color(0.92, 0.94, 0.96)
const COL_OFF := Color(0.5, 0.5, 0.52)

var mv: Node = null
var open := false
var centre_w := Vector2.ZERO     # world tile where the radial opened
var hover := -1
var armed := ""                  # slot id while waiting for the strike click / drag
var drag_from = null             # world-tile Vector2 while the button is down
var last_result: Dictionary = {}
var msg := ""
var msg_t := 0.0
var clicks := 0                  # test hook: player actions spent (pick = 1, each click / drag = 1)
## The open ring is screen UI: drawn on its own CanvasLayer so the Last Protocol night tint (world canvas) does not
## darken it (flow fires71 run 2: labels barely readable at night). Strike previews stay in the world.
var _ui: CanvasLayer = null
var _pane: Node2D = null


func _init() -> void:
	name = "FireRadial71"


func setup(view: Node) -> void:
	mv = view
	if _ui == null:
		_ui = CanvasLayer.new()
		_ui.layer = 40
		_pane = Node2D.new()
		_ui.add_child(_pane)
		add_child(_ui)
		_pane.draw.connect(_draw_ring)


func _redraw() -> void:
	queue_redraw()
	if _pane != null:
		_pane.queue_redraw()


static func attach(view: Node) -> Node:
	var r = (load("res://presentation/ui71/fire_radial.gd") as GDScript).new()
	r.z_index = 60
	view.add_child(r)
	r.setup(view)
	return r


## Key event matches the action's current binding (user rebinds included).
static func is_action_key(ev: InputEventKey) -> bool:
	var k := Hotkeys.key(ACTION).to_upper()
	return k != "" and OS.get_keycode_string(ev.keycode).to_upper() == k


## Slot index for an offset (screen pixels) from the radial centre; -1 in the hub.
static func slot_at(off: Vector2) -> int:
	if off.length() < R_IN:
		return -1
	var n := SLOTS.size()
	var a := fposmod(off.angle() + PI * 0.5 + PI / float(n), TAU)   # slot 0 at the top, clockwise
	return int(a / (TAU / float(n))) % n


func _scale() -> float:
	return maxf(get_canvas_transform().get_scale().x, 0.01)


func _mouse_off() -> Vector2:
	return get_viewport().get_mouse_position() - _centre_px()


## Radial centre in screen pixels: where it opened, pushed inside the viewport so the whole ring is on screen
## (flow fires71 run 1: a radial opened near the right edge was cut in half).
func _centre_px() -> Vector2:
	var sp: Vector2 = get_canvas_transform() * mv.world_to_screen(centre_w)
	var vr := get_viewport_rect().size
	var m := R_OUT + 6.0
	return Vector2(clampf(sp.x, m, maxf(m, vr.x - m)), clampf(sp.y, m, maxf(m, vr.y - m)))


func open_at(w: Vector2) -> void:
	open = true
	centre_w = w
	hover = -1
	_redraw()


## Arms slot i (test hook and the key-release path). Returns the armed id ("" = nothing).
func pick(i: int) -> String:
	open = false
	armed = ""
	drag_from = null
	if i < 0 or i >= SLOTS.size() or not bool(SLOTS[i][2]):
		_redraw()
		return ""
	clicks += 1
	var id := String(SLOTS[i][0])
	if id == "sectors":
		var kz = mv.get_node_or_null("KillZonePaint71") if mv != null else null
		if kz != null:
			kz.start()
		return id
	armed = id
	_redraw()
	return id


func cancel() -> void:
	open = false
	armed = ""
	drag_from = null
	_redraw()


## One finished click / drag a -> b for the armed slot. Returns the submit result.
func finish(a: Vector2, b: Vector2, shift: bool, ctrl: bool) -> Dictionary:
	clicks += 1
	var cmd := {}
	match armed:
		"":
			return {}
		"gunship":
			cmd = ConductorOrbit.make_cmd(a, b, ctrl)
		"fpf":
			cmd = {"type": "fpf_fire", "face": -1 if shift else KillZone71.face_of(mv.world, a)}
		_:
			cmd = StrikeShape.make_cmd(armed, StrikeShape.shape_for(a, b, shift, ctrl), a, b)
	last_result = mv.issue(cmd)
	if not bool(last_result.get("ok", false)):
		msg = String(last_result.get("reason", ""))
		msg_t = 2.5
	armed = ""
	drag_from = null
	_redraw()
	return last_result


func _input(ev: InputEvent) -> void:
	if mv == null:
		return
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if k.echo:
			if open and is_action_key(k):
				get_viewport().set_input_as_handled()
			return
		if is_action_key(k):
			if k.pressed and not open:
				armed = ""
				open_at(mv.mouse_world())
			elif not k.pressed and open:
				pick(slot_at(_mouse_off()))
			get_viewport().set_input_as_handled()
		elif k.pressed and k.keycode == KEY_ESCAPE and (open or armed != ""):
			cancel()
			get_viewport().set_input_as_handled()
		return
	if armed == "" or not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			drag_from = mv.mouse_world()
		elif drag_from != null:
			finish(Vector2(drag_from), mv.mouse_world(), mb.shift_pressed, mb.ctrl_pressed)
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		cancel()
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if msg_t > 0.0:
		msg_t -= dt
	if open or armed != "" or msg_t > 0.0:
		if open:
			hover = slot_at(_mouse_off())
		_redraw()


func _draw() -> void:
	if mv == null:
		return
	var s := _scale()
	var font := ThemeDB.fallback_font
	if open:
		return   # the ring is drawn by _draw_ring on the UI layer
	var m: Vector2 = mv.mouse_world()
	if armed != "":
		var col := COL_HI
		if drag_from != null:
			var a := Vector2(drag_from)
			if armed == "gunship":
				var pts := []
				for p in StrikeShape.circle(a, ConductorOrbit.preview_r(a, m), 40):
					pts.append(mv.world_to_screen(p))
				draw_polyline(PackedVector2Array(pts), Color(0.35, 0.85, 1.0, 0.9), 2.0 / s, true)
			elif armed != "fpf":
				var shape := StrikeShape.shape_for(a, m, Input.is_key_pressed(KEY_SHIFT), Input.is_key_pressed(KEY_CTRL))
				for ln in StrikeShape.outline(shape, a, m):
					var pk := PackedVector2Array()
					for p in ln:
						pk.append(mv.world_to_screen(p))
					draw_polyline(pk, col, 2.0 / s, true)
		draw_set_transform(mv.world_to_screen(m), 0.0, Vector2(1.0 / s, 1.0 / s))
		draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 20, col, 2.0)
		draw_string(font, Vector2(12, -8), _armed_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif msg_t > 0.0 and msg != "":
		draw_set_transform(mv.world_to_screen(m), 0.0, Vector2(1.0 / s, 1.0 / s))
		draw_string(font, Vector2(12, -8), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.4, 0.35, clampf(msg_t, 0.0, 1.0)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _armed_label() -> String:
	for sl in SLOTS:
		if String(sl[0]) == armed:
			match armed:
				"gunship":
					return "Conductor orbit: drag radius (Ctrl = clockwise)"
				"fpf":
					return "FPF: click a wall face (Shift = all faces)"
			return "%s: click / drag lane / Shift box / Ctrl creeping" % String(sl[1])
	return ""


## The open ring, screen pixels, on the UI CanvasLayer (see _ui).
func _draw_ring() -> void:
	if mv == null or not open or _pane == null:
		return
	var font := ThemeDB.fallback_font
	_pane.draw_set_transform(_centre_px(), 0.0, Vector2.ONE)
	var n := SLOTS.size()
	var step := TAU / float(n)
	for i in n:
		var a0 := -PI * 0.5 - step * 0.5 + step * float(i)
		var pts := PackedVector2Array()
		for j in 7:
			var t := a0 + step * float(j) / 6.0
			pts.append(Vector2(cos(t), sin(t)) * R_OUT)
		for j in 7:
			var t := a0 + step * float(6 - j) / 6.0
			pts.append(Vector2(cos(t), sin(t)) * R_IN)
		var on := bool(SLOTS[i][2])
		_pane.draw_colored_polygon(pts, COL_HI if (i == hover and on) else COL_BG)
		pts.append(pts[0])
		_pane.draw_polyline(pts, Color(1, 1, 1, 0.25), 1.0, true)
		var mid := a0 + step * 0.5
		var lp := Vector2(cos(mid), sin(mid)) * (R_IN + (R_OUT - R_IN) * R_LAB)
		var lab := String(SLOTS[i][1])
		var wdt := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_pane.draw_string(font, lp + Vector2(-wdt * 0.5, 4), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TX if on else COL_OFF)
	_pane.draw_circle(Vector2.ZERO, R_IN - 4.0, COL_BG)
	var hub := "Fire"
	_pane.draw_string(font, Vector2(-font.get_string_size(hub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x * 0.5, 5), hub,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_TX)
	_pane.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
