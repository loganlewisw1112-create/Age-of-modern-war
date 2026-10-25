extends HBoxContainer
## G6 (UI6b) editor Live toggle + speed widget (CONTRACTS_G6 section 15, D43; ED6 owns the editor and
## sim/editor_live.gd). The editor adds it to its toolbar and hands it a world getter:
##   var bar = preload("res://presentation/ui6/b/live_bar.gd").new()
##   bar.setup(func(): return <SimWorld to run Live, e.g. EditorLive.make_world(...).world>)
##   toolbar.add_child(bar); bar.live_changed.connect(...); bar.speed_changed.connect(...)
##   in the editor's key handler: if bar.handle_key(keycode): consume       (L toggles Live)
##   per frame while bar.live: step bar.world bar.steps_per_frame() times (0 = paused)
## Live on: EditorLive.start(world) snapshots it and sets cfg.live_mode (combat + AI tactics only).
## Live off: EditorLive.stop(world, snap) restores the snapshot exactly (state_hash equals the pre-Live hash).
## Speed buttons: pause / 1x / 2x / 4x (EditorLive.SPEEDS) -> EditorLive.set_speed(n).
## Neutral fallback: with no world getter (or a getter that returns null) the toggle stays disabled with a
## reason; nothing is snapshotted and nothing runs.

const EditorLive = preload("res://sim/editor_live.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")

signal live_changed(on: bool)
signal speed_changed(n: int)

var get_world: Callable = Callable()
var live := false
var world: SimWorld = null
var snap: Dictionary = {}
var speed := 1
var toggle_btn: Button
var speed_btns: Dictionary = {}   # speed -> Button
var status: Label
var last_reason := ""


func _init() -> void:
	name = "LiveBar"
	add_theme_constant_override("separation", 4)
	toggle_btn = UiKit.button("Live", "L", "Live: run the placed units as a battle (combat + AI tactics only). Leaving Live restores the map exactly.")
	toggle_btn.name = "LiveToggle"
	toggle_btn.toggle_mode = true
	toggle_btn.focus_mode = Control.FOCUS_NONE
	toggle_btn.custom_minimum_size = Vector2(84, UiKit.BTN_H)
	toggle_btn.pressed.connect(func(): set_live(toggle_btn.button_pressed))
	add_child(toggle_btn)
	for n in EditorLive.SPEEDS:
		var b := UiKit.button("||" if int(n) == 0 else "%dx" % int(n), "", "Pause" if int(n) == 0 else "Live speed %dx" % int(n))
		b.name = "LiveSpeed_%d" % int(n)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(40, UiKit.BTN_H)
		b.pressed.connect(set_speed.bind(int(n)))
		add_child(b)
		speed_btns[int(n)] = b
	status = UiKit.label("", "small")
	status.name = "LiveStatus"
	add_child(status)
	speed = EditorLive.speed() if EditorLive.SPEEDS.has(EditorLive.speed()) else 1
	_refresh()


func setup(world_getter: Callable) -> void:
	get_world = world_getter
	_refresh()


func available() -> bool:
	return get_world.is_valid()


## Enter / leave Live. Returns true when the state changed.
func set_live(on: bool) -> bool:
	if on == live:
		_refresh()
		return false
	if on:
		var w = get_world.call() if get_world.is_valid() else null
		if not (w is SimWorld):
			last_reason = "Nothing to run: open or place a map first." if get_world.is_valid() else "Live is not connected to the editor."
			_refresh()
			return false
		world = w
		snap = EditorLive.start(world)
		live = true
		EditorLive.set_speed(speed)
		last_reason = ""
	else:
		EditorLive.stop(world, snap)
		snap = {}
		world = null
		live = false
	_refresh()
	live_changed.emit(live)
	return true


func toggle() -> bool:
	return set_live(not live)


func set_speed(n: int) -> void:
	if not EditorLive.SPEEDS.has(n):
		return
	speed = n
	EditorLive.set_speed(n)
	_refresh()
	speed_changed.emit(n)


## Sim steps the editor runs per frame while Live (0 = paused or not live).
func steps_per_frame() -> int:
	return speed if live else 0


## L toggles Live. True = consumed.
func handle_key(kc: int) -> bool:
	if kc == KEY_L:
		toggle()
		return true
	return false


func _refresh() -> void:
	toggle_btn.set_pressed_no_signal(live)
	toggle_btn.text = "LIVE" if live else "Live"
	toggle_btn.disabled = not available() and not live
	toggle_btn.tooltip_text = "Live [L]: run the placed units as a battle (combat + AI tactics only). Leaving Live restores the map exactly." \
		+ ("" if available() else "\nUnavailable: Live is not connected to the editor.")
	for n in speed_btns:
		var b: Button = speed_btns[n]
		b.set_pressed_no_signal(int(n) == speed)
		b.disabled = not live
	if live:
		status.text = "LIVE  %s  tick %d" % ["paused" if speed == 0 else "%dx" % speed, world.tick if world != null else 0]
	else:
		status.text = last_reason
	status.add_theme_color_override("font_color", UiKit.RED if (live or last_reason != "") else UiKit.DIM)
