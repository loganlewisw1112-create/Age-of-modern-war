extends Node2D
## MatchView (owner: agent D / presentation-core). Hosts a SimWorld, ticks it at 20 Hz,
## renders terrain/entities/fog/fx/overlays, owns the camera and all in-world input.
## Contract: docs/CONTRACTS.md section 7. The HUD (agent E) is a sibling CanvasLayer that
## talks to this node only through the public members below.
##
## Debug args (after `--` on the godot command line):
##   --spawn-test=N        spawn N extra combat units (half per side) and send them at each other
##   --demo-script=NAME    scripted camera/selection/placement for autoshots:
##                         start | zoomout | select | ghost | ghost_ok | combat
##   --fps-log             print FPS once per second (also on with --spawn-test)
##   --no-vsync            disable vsync (for perf headroom measurement)
##   --sim-paused          start with the sim paused (render-only perf measurement)

const TILE_W := 64
const TILE_H := 32

const Construction = preload("res://sim/systems/construction.gd")
const TerrainLayer = preload("res://presentation/view/terrain_layer.gd")
const EntityLayer = preload("res://presentation/view/entity_layer.gd")
const FogLayer = preload("res://presentation/view/fog_layer.gd")
const FxLayer = preload("res://presentation/view/fx_layer.gd")
const OverlayLayer = preload("res://presentation/view/overlay_layer.gd")
const CameraRig = preload("res://presentation/view/camera_rig.gd")
# G2 (agent D2): order modes, overlays, demo scripts
const G2Input = preload("res://presentation/view/g2_input.gd")
const G2Overlay = preload("res://presentation/view/g2_overlay.gd")
const G2Demo = preload("res://presentation/view/g2_demo.gd")

signal selection_changed
signal world_events(events: Array)
## Emitted when the build ghost is entered/left (def_id is "" when placement ends).
signal placement_changed(def_id: String)

# ------------------------------------------------------------ public API (CONTRACTS section 7)
var world: SimWorld
var player_fid: int = 0
var selection: Array[int] = []
var speed: float = 1.0
var paused: bool = false
var control_groups: Dictionary = {}     # int 1..9 -> Array[int] of entity ids
var placing_def: String = ""             # build ghost def id ("" = not placing)
var attack_move_armed: bool = false      # after pressing A, next left click = attack-move
var last_alert_pos: Variant = null       # Vector2 world pos of the last alert (Space jumps there)

# ------------------------------------------------------------ internals
var camera: Camera2D
var terrain_layer: Node2D
var entity_layer: Node2D
var fog_layer: Node2D
var fx_layer: Node2D
var ring_layer: Node2D
var overlay_layer: Node2D
var g2 = G2Input.new()                   # G2 order modes (patrol/guard/repair/mission)
var g2_ground: Node2D
var g2_over: Node2D

var _acc: float = 0.0
var _alpha: float = 0.0
var _prev_pos: Dictionary = {}           # unit id -> Vector2 pos before the latest step
var _anim_time: float = 0.0
var _initialized := false

# input state
var _drag_start_screen: Variant = null   # Vector2 viewport pos where left button went down
var _drag_now_screen: Vector2 = Vector2.ZERO
var _dragging := false
var _skip_click_release := false
var _mid_drag := false
var _mid_last := Vector2.ZERO
var _pan_keys := {}                      # Key -> true while held (set from unhandled input)
var _group_last_tap := {}                # group -> msec of last recall
var _edge_pan_enabled := true
var demo_mouse_world: Variant = null     # Vector2 world pos override for the cursor (demo scripts)
var demo_marquee: Variant = null         # Rect2 viewport rect to keep drawn (demo scripts)

# debug
var _fps_log := false
var _fps_t := 0.0
var _fps_frames := 0
var _fps_samples: Array = []
var _t_sim := 0
var _t_view := 0


# ================================================================ lifecycle
func _ready() -> void:
	if world == null:
		push_warning("MatchView: no world assigned")
		return
	_init_view()


func _init_view() -> void:
	_initialized = true
	ArtCatalog.load_all()
	var args := OS.get_cmdline_user_args()
	var spawn_test := 0
	var demo := ""
	for a in args:
		if a.begins_with("--spawn-test="):
			spawn_test = int(a.substr(13))
		elif a.begins_with("--demo-script="):
			demo = a.substr(14)
		elif a == "--fps-log":
			_fps_log = true
		elif a == "--sim-paused":
			paused = true  # render-only perf measurement
		elif a == "--no-vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		elif a.begins_with("--autoshot="):
			_edge_pan_enabled = false
	if spawn_test > 0:
		_fps_log = true

	terrain_layer = TerrainLayer.new()
	terrain_layer.z_index = 0
	add_child(terrain_layer)
	ring_layer = OverlayLayer.new()
	ring_layer.mode = "under"
	ring_layer.z_index = 1
	add_child(ring_layer)
	entity_layer = EntityLayer.new()
	entity_layer.z_index = 2
	add_child(entity_layer)
	fx_layer = FxLayer.new()
	fx_layer.z_index = 3
	add_child(fx_layer)
	fog_layer = FogLayer.new()
	fog_layer.z_index = 4
	add_child(fog_layer)
	overlay_layer = OverlayLayer.new()
	overlay_layer.mode = "over"
	overlay_layer.z_index = 5
	add_child(overlay_layer)
	g2.mv = self
	g2_ground = G2Overlay.new()
	g2_ground.mode = "ground"
	g2_ground.z_index = 1
	add_child(g2_ground)
	g2_over = G2Overlay.new()
	g2_over.mode = "over"
	g2_over.z_index = 5
	add_child(g2_over)
	camera = CameraRig.new()
	add_child(camera)

	for layer in [terrain_layer, ring_layer, entity_layer, fx_layer, fog_layer, overlay_layer, g2_ground, g2_over]:
		layer.setup(self)
	camera.setup(self)
	_snapshot_positions()

	# start centred on the player's HQ (or spawn)
	var hq = _player_hq()
	if hq != null:
		center_camera_on(hq.pos)
	elif world.factions.has(player_fid):
		center_camera_on(Vector2(world.factions[player_fid].spawn) + Vector2(0.5, 0.5))

	if spawn_test > 0:
		_debug_spawn_test(spawn_test)
	if demo != "":
		_run_demo(demo)


# ================================================================ sim ticking
func _process(delta: float) -> void:
	if world == null:
		return
	if not _initialized:
		_init_view()
	if camera == null:
		return
	_anim_time += delta
	if not paused:
		_acc += delta * speed
		var steps := 0
		while _acc >= SimWorld.DT and steps < 5:
			_acc -= SimWorld.DT
			_snapshot_positions()
			var ts := Time.get_ticks_usec()
			world.step()
			_t_sim += Time.get_ticks_usec() - ts
			steps += 1
			_on_step_events(world.events)
			world_events.emit(world.events)
		if _acc >= SimWorld.DT:
			_acc = 0.0  # drop backlog instead of spiralling
	_alpha = clampf(_acc / SimWorld.DT, 0.0, 1.0) if not paused else 1.0
	var tv := Time.get_ticks_usec()
	_process_input_state(delta)
	camera.tick(delta)
	fog_layer.refresh()
	entity_layer.refresh()
	fx_layer.tick(delta)
	ring_layer.queue_redraw()
	overlay_layer.queue_redraw()
	g2_ground.queue_redraw()
	g2_over.queue_redraw()
	_t_view += Time.get_ticks_usec() - tv
	if _fps_log:
		_fps_frames += 1
		_fps_t += delta
		if _fps_t >= 1.0:
			var fps := float(_fps_frames) / _fps_t
			_fps_samples.append(fps)
			var units := 0
			for id in world.entities:
				if world.entities[id].kind == "unit":
					units += 1
			print("FPS fps=%.1f engine_fps=%.0f units=%d entities=%d tick=%d sim_ms_per_s=%.0f view_ms_per_s=%.0f" % [fps, Engine.get_frames_per_second(), units, world.entities.size(), world.tick, _t_sim / 1000.0 / _fps_t, _t_view / 1000.0 / _fps_t])
			_t_sim = 0
			_t_view = 0
			_fps_t = 0.0
			_fps_frames = 0


func _snapshot_positions() -> void:
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if e.kind == "unit":
			_prev_pos[id] = e.pos


## Interpolated render position (screen-independent world tile coords).
func render_pos(e: Dictionary) -> Vector2:
	if e.kind == "unit":
		var p = _prev_pos.get(e.id)
		if p != null:
			var cur: Vector2 = e.pos
			if (p as Vector2).distance_squared_to(cur) < 4.0:
				return (p as Vector2).lerp(cur, _alpha)
	return e.pos


func anim_time() -> float:
	return _anim_time


func _on_step_events(evs: Array) -> void:
	for ev in evs:
		match String(ev.type):
			"EntityDestroyed":
				var id := int(ev.id)
				_prev_pos.erase(id)
				entity_layer.on_destroyed(id)
				fx_layer.on_destroyed(ev)
				if selection.has(id):
					selection.erase(id)
					selection_changed.emit()
				if int(ev.owner) == player_fid:
					last_alert_pos = ev.pos
			"ShotFired":
				fx_layer.on_shot(ev)
				var t = world.entities.get(int(ev.get("target", -1)))
				if t != null and int(t.owner) == player_fid:
					last_alert_pos = t.pos
			"BridgeDestroyed", "BridgeRepaired":
				# G2: the terrain array changed under the bridge; re-bake those chunks
				var cells: Array = ev.get("cells", world.map.get("bridge_cells", []))
				terrain_layer.rebake_cells(cells)
				if not cells.is_empty():
					last_alert_pos = Vector2(cells[0].x, cells[0].y) + Vector2(0.5, 0.5)
			"ConstructionCompleted", "ProductionCompleted":
				var b = world.entities.get(int(ev.get("building_id", ev.get("id", -1))))
				if b != null and int(b.owner) == player_fid:
					last_alert_pos = b.pos


# ================================================================ public API
func issue(cmd: Dictionary) -> Dictionary:
	cmd.issuer = player_fid
	return world.submit(cmd)


func begin_build_placement(def_id: String) -> void:
	if Content.building(def_id).is_empty():
		push_warning("MatchView.begin_build_placement: unknown building '%s'" % def_id)
		return
	placing_def = def_id
	attack_move_armed = false
	placement_changed.emit(def_id)


## True while a build ghost is active (used by the HUD/pause Esc handling).
func is_placing() -> bool:
	return placing_def != ""


func cancel_placement() -> void:
	if placing_def == "":
		return
	placing_def = ""
	placement_changed.emit("")


func center_camera_on(world_pos: Vector2) -> void:
	if camera != null:
		camera.center_on(world_to_screen(world_pos))


func select_ids(ids: Array) -> void:
	var out: Array[int] = []
	for raw in ids:
		var id := int(raw)
		if world.entities.has(id) and not out.has(id):
			out.append(id)
	selection = out
	selection_changed.emit()


static func world_to_screen(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * TILE_W * 0.5, (p.x + p.y) * TILE_H * 0.5)


static func screen_to_world(s: Vector2) -> Vector2:
	var a := s.x / (TILE_W * 0.5)
	var b := s.y / (TILE_H * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


## World-tile position under the mouse cursor (or the demo override).
func mouse_world() -> Vector2:
	if demo_mouse_world != null:
		return demo_mouse_world
	return screen_to_world(get_global_mouse_position())


## Four world-tile corners of the current camera view (TL, TR, BR, BL), for the minimap.
func get_view_corners_world() -> PackedVector2Array:
	var out := PackedVector2Array()
	if camera == null:
		return out
	var vs := get_viewport_rect().size
	for sp in [Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]:
		out.append(screen_to_world(_viewport_to_canvas(sp)))
	return out


## Placement origin (top-left cell) for the ghost of def_id centred under world pos p.
func placement_origin(def_id: String, p: Vector2) -> Vector2i:
	var size := int(Content.building(def_id).get("size", 1))
	var c := Vector2i(floori(p.x - size * 0.5 + 0.5), floori(p.y - size * 0.5 + 0.5))
	return c


## For the HUD: what is under the cursor, plus the build-ghost state.
## {world_pos, cell, entity_id (-1), entity (Dictionary or null), placing_def, placement_origin,
##  placement_error, placement_cost, attack_move_armed}
func get_hover_info() -> Dictionary:
	var p := mouse_world()
	var info := {
		"world_pos": p,
		"cell": Vector2i(floori(p.x), floori(p.y)),
		"entity_id": -1,
		"entity": null,
		"placing_def": placing_def,
		"placement_origin": Vector2i.ZERO,
		"placement_error": "",
		"placement_cost": {},
		"attack_move_armed": attack_move_armed,
	}
	if world == null:
		return info
	var e = entity_at(p, false)
	if e != null:
		info.entity_id = int(e.id)
		info.entity = e
	if placing_def != "":
		var o := placement_origin(placing_def, p)
		info.placement_origin = o
		info.placement_error = Construction.placement_error(world, player_fid, placing_def, o)
		info.placement_cost = Content.building(placing_def).get("cost", {})
	return info


# ================================================================ visibility helpers
func _fog_arrays() -> Dictionary:
	return world.fog.get(player_fid, {})


func cell_visible(c: Vector2i) -> bool:
	if not world.in_bounds(c):
		return false
	var f := _fog_arrays()
	if f.is_empty():
		return true
	return int(f.visible[c.y * int(world.map.w) + c.x]) == 1


func cell_explored(c: Vector2i) -> bool:
	if not world.in_bounds(c):
		return false
	var f := _fog_arrays()
	if f.is_empty():
		return true
	return int(f.explored[c.y * int(world.map.w) + c.x]) == 1


## Whether the player may currently see entity e (own entities are always visible).
func entity_visible(e: Dictionary) -> bool:
	var o := int(e.owner)
	if o == player_fid:
		return true
	if e.kind == "building":
		var c: Vector2i = e.cell
		var s := int(e.size)
		for dy in s:
			for dx in s:
				if cell_visible(c + Vector2i(dx, dy)):
					return true
		return false
	return cell_visible(Vector2i(floori(e.pos.x), floori(e.pos.y)))


func team_color(fid: int) -> Color:
	if world != null and world.factions.has(fid):
		return Color.html(String(world.factions[fid].color))
	return Color(0.85, 0.85, 0.8)


func _player_hq():
	for b in world.buildings_of(player_fid):
		if Content.building(b.def).get("is_hq", false):
			return b
	return null


# ================================================================ picking
## Entity under world point p. Units pick by screen proximity; buildings by footprint.
## only_actionable=true skips entities the player cannot currently see.
func entity_at(p: Vector2, only_actionable: bool = true):
	var sp := world_to_screen(p)
	var best = null
	var best_d := 1e9
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if e.kind != "unit":
			continue
		if not entity_visible(e):
			continue
		var r := float(Content.unit(e.def).get("radius", 0.3))
		var es := world_to_screen(render_pos(e)) + Vector2(0, -10 - r * 12.0)
		var d := es.distance_to(sp)
		var lim := 14.0 + r * 16.0
		if d < lim and d < best_d:
			best = e
			best_d = d
	if best != null:
		return best
	var c := Vector2i(floori(p.x), floori(p.y))
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if e.kind != "building":
			continue
		var o: Vector2i = e.cell
		var s := int(e.size)
		if c.x >= o.x and c.y >= o.y and c.x < o.x + s and c.y < o.y + s:
			if entity_visible(e) or (not only_actionable and _remembered(int(e.id))):
				return e
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if e.kind == "resource" and (e.pos as Vector2).distance_to(p) < 0.8 and cell_explored(world.cell_of(e.pos)):
			return e
	return null


func _remembered(eid: int) -> bool:
	return world.memory.get(player_fid, {}).has(eid)


func _own_units_in_selection() -> Array:
	var out := []
	for id in selection:
		var e = world.entities.get(id)
		if e != null and e.kind == "unit" and int(e.owner) == player_fid:
			out.append(id)
	return out


func _own_engineers_in_selection() -> Array:
	var out := []
	for id in _own_units_in_selection():
		if Content.unit(world.entities[id].def).get("can_build", false):
			out.append(id)
	return out


# ================================================================ input
func _viewport_to_canvas(vp: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * vp


func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_LEFT:
					_on_left_press(mb)
				MOUSE_BUTTON_RIGHT:
					_on_right_press(mb)
				MOUSE_BUTTON_MIDDLE:
					_mid_drag = true
					_mid_last = mb.position
				MOUSE_BUTTON_WHEEL_UP:
					camera.zoom_at(mb.position, 1.15)
				MOUSE_BUTTON_WHEEL_DOWN:
					camera.zoom_at(mb.position, 1.0 / 1.15)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.echo:
			return
		if k.pressed:
			if _on_key(k):
				get_viewport().set_input_as_handled()


## Releases and drags are tracked in _input so a release over a HUD panel still ends the drag.
func _input(event: InputEvent) -> void:
	if world == null:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_start_screen != null:
			_drag_now_screen = mm.position
			if (_drag_now_screen - (_drag_start_screen as Vector2)).length() > 6.0:
				_dragging = true
		if _mid_drag:
			camera.pan_screen(_mid_last - mm.position)
			_mid_last = mm.position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT and _drag_start_screen != null:
				_finish_left(mb.position, mb.shift_pressed)
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				_mid_drag = false


func _on_left_press(mb: InputEventMouseButton) -> void:
	var p := screen_to_world(_viewport_to_canvas(mb.position))
	if placing_def != "":
		_try_place(p, mb.shift_pressed)
		return
	if attack_move_armed:
		attack_move_armed = false
		_command_attack_move(p)
		return
	if g2.on_left(p, mb.shift_pressed):
		return
	if mb.double_click:
		_select_same_def_on_screen(p, mb.shift_pressed)
		_skip_click_release = true
	_drag_start_screen = mb.position
	_drag_now_screen = mb.position
	_dragging = false


func _finish_left(pos: Vector2, shift: bool) -> void:
	var start: Vector2 = _drag_start_screen
	_drag_start_screen = null
	if _skip_click_release:
		_skip_click_release = false
		_dragging = false
		return
	if _dragging:
		_dragging = false
		_marquee_select(Rect2(start, pos - start).abs(), shift)
	else:
		_click_select(screen_to_world(_viewport_to_canvas(pos)), shift)


func _click_select(p: Vector2, shift: bool) -> void:
	var e = entity_at(p, false)
	if e == null:
		if not shift:
			select_ids([])
		return
	var id := int(e.id)
	if shift and int(e.owner) == player_fid:
		var cur: Array = selection.duplicate()
		if cur.has(id):
			cur.erase(id)
		else:
			# do not mix own units with other things
			cur = cur.filter(func(x): return world.entities.has(x) and int(world.entities[x].owner) == player_fid)
			cur.append(id)
		select_ids(cur)
	else:
		select_ids([id])


func _marquee_select(r: Rect2, shift: bool) -> void:
	var units := []
	var buildings := []
	var ct := get_viewport().get_canvas_transform()
	for id in world.entities:
		var e: Dictionary = world.entities[id]
		if int(e.owner) != player_fid:
			continue
		var sp: Vector2 = ct * world_to_screen(render_pos(e))
		if e.kind == "unit" and r.grow(6).has_point(sp + Vector2(0, -8)):
			units.append(id)
		elif e.kind == "building" and r.has_point(sp):
			buildings.append(id)
	var picked := units if not units.is_empty() else buildings
	if shift:
		var cur: Array = _own_units_in_selection() if not units.is_empty() else selection.duplicate()
		for id in picked:
			if not cur.has(id):
				cur.append(id)
		select_ids(cur)
	else:
		select_ids(picked)


func _select_same_def_on_screen(p: Vector2, shift: bool) -> void:
	var e = entity_at(p, false)
	if e == null or int(e.owner) != player_fid:
		return
	var vr := get_viewport_rect()
	var ct := get_viewport().get_canvas_transform()
	var out: Array = selection.duplicate() if shift else []
	for id in world.entities:
		var o: Dictionary = world.entities[id]
		if o.def == e.def and o.kind == e.kind and int(o.owner) == player_fid:
			if vr.has_point(ct * world_to_screen(render_pos(o))) and not out.has(id):
				out.append(id)
	select_ids(out)


func _on_right_press(mb: InputEventMouseButton) -> void:
	if placing_def != "":
		cancel_placement()
		return
	if attack_move_armed:
		attack_move_armed = false
		return
	var p := screen_to_world(_viewport_to_canvas(mb.position))
	if g2.on_right(p, mb.shift_pressed):
		return
	smart_command(p, mb.shift_pressed)


## Smart right-click command at world point p for the current selection.
## G2: engineers repair own damaged targets / the ruined bridge; Shift+right-click on the bridge
## with combat units demolishes it (plain right-click there only moves, with a hint).
func smart_command(p: Vector2, shift: bool = false) -> void:
	var units := _own_units_in_selection()
	if units.is_empty():
		# own production buildings selected: set rally
		for id in selection:
			var b = world.entities.get(id)
			if b != null and b.kind == "building" and int(b.owner) == player_fid and not Content.building(b.def).get("produces", []).is_empty():
				issue({"type": "set_rally", "building_id": id, "target": p})
				fx_layer.add_marker(p, Color(0.4, 0.8, 1.0))
		return
	var t = entity_at(p, true)
	var engineers := _own_engineers_in_selection()
	if g2.smart(p, shift, t, units, engineers):
		return
	if t != null:
		if t.kind in ["unit", "building"] and world.is_enemy(player_fid, int(t.owner)):
			issue({"type": "attack", "unit_ids": units, "target_id": int(t.id)})
			fx_layer.add_marker(t.pos, Color(1.0, 0.25, 0.2))
			return
		if t.kind == "resource" and not engineers.is_empty():
			issue({"type": "gather", "unit_ids": engineers, "target_id": int(t.id)})
			var rest := units.filter(func(x): return not engineers.has(x))
			if not rest.is_empty():
				issue({"type": "move", "unit_ids": rest, "target": p})
			fx_layer.add_marker(t.pos, Color(1.0, 0.85, 0.3))
			return
		if t.kind == "building" and int(t.owner) == player_fid and not t.get("built", true) and not engineers.is_empty():
			issue({"type": "assist_build", "unit_ids": engineers, "target_id": int(t.id)})
			fx_layer.add_marker(t.pos, Color(1.0, 0.85, 0.3))
			return
	issue({"type": "move", "unit_ids": units, "target": p})
	fx_layer.add_marker(p, Color(0.4, 1.0, 0.4))


func _command_attack_move(p: Vector2) -> void:
	var units := _own_units_in_selection()
	if units.is_empty():
		return
	var t = entity_at(p, true)
	if t != null and t.kind in ["unit", "building"] and world.is_enemy(player_fid, int(t.owner)):
		issue({"type": "attack", "unit_ids": units, "target_id": int(t.id)})
		fx_layer.add_marker(t.pos, Color(1.0, 0.25, 0.2))
	else:
		issue({"type": "attack_move", "unit_ids": units, "target": p})
		fx_layer.add_marker(p, Color(1.0, 0.45, 0.2))


func _try_place(p: Vector2, shift: bool) -> void:
	var o := placement_origin(placing_def, p)
	var err := Construction.placement_error(world, player_fid, placing_def, o)
	# Always submit: the sim is authoritative and its CommandRejected reason reaches the HUD alerts.
	issue({"type": "build", "unit_ids": _own_engineers_in_selection(), "def": placing_def, "origin": o})
	if err == "" and not shift:
		cancel_placement()


func _on_key(k: InputEventKey) -> bool:
	var kc := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	var has_units := not _own_units_in_selection().is_empty()
	# control groups
	if kc >= KEY_1 and kc <= KEY_9:
		var g := int(kc - KEY_0)
		if k.ctrl_pressed:
			control_groups[g] = _own_units_in_selection() if has_units else selection.duplicate()
		else:
			_recall_group(g, k.shift_pressed)
		return true
	if g2.on_key(kc):
		return true
	match kc:
		KEY_ESCAPE:
			if placing_def != "":
				cancel_placement()
				return true
			if attack_move_armed:
				attack_move_armed = false
				return true
			if not selection.is_empty():
				select_ids([])
				return true
			return false  # let the HUD open the pause menu
		KEY_A:
			if has_units and not k.ctrl_pressed:
				attack_move_armed = true
				return true
		KEY_S:
			if has_units and not k.ctrl_pressed:
				issue({"type": "stop", "unit_ids": _own_units_in_selection()})
				return true
		KEY_H:
			if has_units:
				issue({"type": "hold", "unit_ids": _own_units_in_selection()})
				return true
		KEY_SPACE:
			if last_alert_pos != null:
				center_camera_on(last_alert_pos)
				return true
	# panning keys (A/S only pan when no own units are selected)
	if kc in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] and not k.ctrl_pressed:
		_pan_keys[kc] = true
		return true
	return false


func _recall_group(g: int, shift: bool) -> void:
	var ids: Array = control_groups.get(g, [])
	ids = ids.filter(func(x): return world.entities.has(x))
	control_groups[g] = ids
	if ids.is_empty():
		return
	var now := Time.get_ticks_msec()
	if not shift and int(_group_last_tap.get(g, -100000)) > now - 400 and _same_selection(ids):
		var c := Vector2.ZERO
		for id in ids:
			c += world.entities[id].pos
		center_camera_on(c / ids.size())
	_group_last_tap[g] = now
	if shift:
		var cur: Array = selection.duplicate()
		for id in ids:
			if not cur.has(id):
				cur.append(id)
		select_ids(cur)
	else:
		select_ids(ids)


func _same_selection(ids: Array) -> bool:
	if ids.size() != selection.size():
		return false
	for id in ids:
		if not selection.has(id):
			return false
	return true


func _process_input_state(delta: float) -> void:
	# held pan keys (verified against physical state so a swallowed release never sticks)
	var dir := Vector2.ZERO
	for kc in _pan_keys.keys():
		if not Input.is_physical_key_pressed(kc):
			_pan_keys.erase(kc)
			continue
		match kc:
			KEY_W, KEY_UP: dir.y -= 1
			KEY_S, KEY_DOWN: dir.y += 1
			KEY_A, KEY_LEFT: dir.x -= 1
			KEY_D, KEY_RIGHT: dir.x += 1
	# edge pan
	if _edge_pan_enabled and demo_mouse_world == null and get_window().has_focus():
		var vp := get_viewport()
		var m := vp.get_mouse_position()
		var vs := get_viewport_rect().size
		if Rect2(Vector2.ZERO, vs).has_point(m):
			if m.x < 6: dir.x -= 1
			elif m.x > vs.x - 6: dir.x += 1
			if m.y < 6: dir.y -= 1
			elif m.y > vs.y - 6: dir.y += 1
	if dir != Vector2.ZERO:
		camera.pan_screen(dir.normalized() * 900.0 * delta / camera.zoom.x)
	# a drag whose release we never saw (window lost focus etc.)
	if _drag_start_screen != null and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and demo_marquee == null:
		_finish_left(_drag_now_screen, Input.is_key_pressed(KEY_SHIFT))
	if _mid_drag and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_mid_drag = false


## Marquee rect in viewport coords while dragging (or the demo override), else null.
func marquee_rect():
	if demo_marquee != null:
		return demo_marquee
	if _drag_start_screen != null and _dragging:
		return Rect2(_drag_start_screen, _drag_now_screen - (_drag_start_screen as Vector2)).abs()
	return null


# ================================================================ debug: spawn test + demo scripts
func _debug_spawn_test(n: int) -> void:
	var defs := ["rifleman", "rifleman", "at_gunner", "recon", "ifv", "mbt"]
	var fids: Array = world.factions.keys()
	if fids.size() < 2:
		return
	var per := n / 2
	for side in 2:
		var fid: int = fids[side]
		var other: int = fids[1 - side]
		var spawn := Vector2(world.factions[fid].spawn) + Vector2(0.5, 0.5)
		var toward := (Vector2(world.factions[other].spawn) - spawn).normalized()
		var base := spawn + toward * 9.0
		var ids := []
		var placed := 0
		var ring := 0
		while placed < per and ring < 40:
			var cnt := maxi(1, ring * 6)
			for k in cnt:
				if placed >= per:
					break
				var ang := float(k) / float(cnt) * TAU
				var pos := base + Vector2(cos(ang), sin(ang)) * float(ring) * 0.9
				var c := Vector2i(floori(pos.x), floori(pos.y))
				var def: String = defs[placed % defs.size()]
				var mc := String(Content.unit(def).get("move_class", "foot"))
				if not world.in_bounds(c) or not Terrain.passable(world.terrain_at(c), mc):
					continue
				ids.append(world.spawn_unit(def, fid, pos))
				placed += 1
			ring += 1
		var target := Vector2(world.factions[other].spawn) + Vector2(0.5, 0.5)
		if not ids.is_empty():
			world.submit({"type": "attack_move", "issuer": fid, "unit_ids": ids, "target": target})
	print("SPAWN_TEST spawned %d extra units" % n)


func _run_demo(demo: String) -> void:
	await get_tree().process_frame
	var hq = _player_hq()
	var base: Vector2 = hq.pos if hq != null else Vector2(world.factions[player_fid].spawn)
	match demo:
		"zoomout":
			camera.set_zoom_level(0.5)
			center_camera_on(base)
		"select":
			await get_tree().create_timer(1.0).timeout
			var ct := get_viewport().get_canvas_transform()
			var pts := []
			for u in world.units_of(player_fid):
				pts.append(ct * world_to_screen(u.pos))
			if pts.is_empty():
				return
			var r := Rect2(pts[0], Vector2.ZERO)
			for p in pts:
				r = r.expand(p)
			r = r.grow_individual(30, 50, 30, 20)
			_marquee_select(r, false)
			demo_marquee = r
			# give part of the selection a move order so the rings move
			var units := _own_units_in_selection()
			if units.size() > 2:
				issue({"type": "move", "unit_ids": units.slice(0, 3), "target": base + Vector2(5, 3)})
		"ghost", "ghost_ok":
			await get_tree().create_timer(0.5).timeout
			select_ids(_engineer_ids())
			begin_build_placement("barracks")
			demo_mouse_world = base + Vector2(6.5, 1.5) if demo == "ghost_ok" else base + Vector2(1.0, 0.5)
		"combat":
			# follow the centroid of units far from the player's base (the spawn-test fight)
			camera.set_zoom_level(1.0)
			for i in 40:
				var c := Vector2.ZERO
				var n := 0
				for id in world.entities:
					var e: Dictionary = world.entities[id]
					if e.kind == "unit" and (e.pos as Vector2).distance_to(base) > 7.0:
						c += e.pos
						n += 1
				if n > 0:
					center_camera_on(c / n)
				await get_tree().create_timer(0.5).timeout
		_:
			if demo.begins_with("g2_"):
				var d = G2Demo.new()
				add_child(d)
				d.run(self, demo)


func _engineer_ids() -> Array:
	var out := []
	for u in world.units_of(player_fid):
		if Content.unit(u.def).get("can_build", false):
			out.append(int(u.id))
	return out
