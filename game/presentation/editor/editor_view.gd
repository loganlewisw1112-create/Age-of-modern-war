extends Node2D
## Editor world view (owner: ED1). Reuses the game's terrain_layer / entity_layer / camera_rig
## over a NON-STEPPING SimWorld whose `map` is the document's map dict (same reference, so
## brushes edit what is drawn). Provides the small `mv` interface those layers read
## (world, camera, world_to_screen, team_color, cell_visible, ...). Routes mouse input on the map
## to the active tool:
##   tool.tool_begin(cell: Vector2i)   left press      tool.tool_drag(cell)  left drag
##   tool.tool_end(cell)               left release    tool.tool_cancel()    right click / Esc
##   tool.tool_preview(cell) -> {cells: Array, color: Color, lines: [[Vector2i, Vector2i]], text}
## Any method may be missing. Middle/right drag pans, wheel zooms, WASD/arrows pan.

const TerrainLayer = preload("res://presentation/view/terrain_layer.gd")
const EntityLayer = preload("res://presentation/view/entity_layer.gd")
const CameraRig = preload("res://presentation/view/camera_rig.gd")
const Overlay = preload("res://presentation/editor/editor_overlay.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const ViewUtil = preload("res://presentation/view/view_util.gd")
const TILE_W := 64
const TILE_H := 32

signal hover_changed(cell: Vector2i)
signal live_blocked                  # G6 (ED6): a doc-editing tool was used while Live runs

## G6 (ED6, CONTRACTS_G6 s15): while Live runs, the entity layer draws `live_world` (a stepping
## SimWorld built from the doc by EditorLive) instead of the static display world. The doc and the
## display `world` are untouched; tools that edit the doc are blocked (a tool may opt in with
## live_ok() -> true, e.g. unit placement, which spawns into the Live world only).
var live_world: SimWorld = null

var doc                      # editor_doc.gd
var world: SimWorld
var _world: SimWorld         # mv interface (THREAD G4): entity_layer reads mv._world / mv.snap
var snap: Dictionary = {}
var camera: Camera2D
var terrain_layer: Node2D
var entity_layer: Node2D = null
var overlay: Node2D
var preview: Node2D
var tool: Object = null
var player_fid: int = 0
var fog_layer = null
var _alpha: float = 1.0
var _prev_pos: Dictionary = {}
var _ally_fids: Array = []
var _anim := 0.0
var use_entity_layer := true
var layers_on := {"grid": false, "pass": "", "decor": true, "units": true}
var hover := Vector2i(-1, -1)
var _down := false
var _pan_from = null
var _decor_dirty := false
var _last_cell := Vector2i(-99, -99)
var _mouse_vp := Vector2.ZERO
var _mouse_known := false


func setup(d) -> void:
	doc = d
	doc.changed.connect(_on_doc_changed)
	overlay = Overlay.new()
	overlay.z_index = 6
	overlay.mode = "static"
	preview = Overlay.new()
	preview.z_index = 7
	preview.mode = "preview"
	camera = CameraRig.new()
	add_child(camera)
	rebuild()


## Full rebuild: new world, fresh terrain/entity layers, camera bounds. New/Open/Generate.
func rebuild() -> void:
	world = SimWorld.new()
	world.map = doc.map
	_world = world
	_sync_world()
	for n in [terrain_layer, entity_layer]:
		if n != null:
			remove_child(n)
			n.queue_free()
	terrain_layer = TerrainLayer.new()
	terrain_layer.z_index = 0
	add_child(terrain_layer)
	terrain_layer.setup(self)
	entity_layer = null
	_rebuild_entity_layer()
	for n in [overlay, preview]:
		if n.get_parent() == null:
			add_child(n)
		n.setup(self)
	if camera.is_inside_tree():
		camera.setup(self)
	center_camera_on(Vector2(doc.map.w, doc.map.h) * 0.5)


func _rebuild_entity_layer() -> void:
	if entity_layer != null:
		remove_child(entity_layer)
		entity_layer.queue_free()
		entity_layer = null
	if not use_entity_layer:
		return
	entity_layer = EntityLayer.new()
	entity_layer.z_index = 2
	add_child(entity_layer)
	entity_layer.setup(self)
	_decor_dirty = false


## Factions (for colours) and display entities (resources + ED2's placed units/buildings).
func _sync_world() -> void:
	if live_world != null:
		return   # Live owns the entity layer; the display world is resynced when Live stops
	world.entities.clear()
	world.factions.clear()
	world.next_id = 1
	var colors: Array = Content.rules().get("team_colors", ["#3c78d8", "#cc3333", "#e0b030", "#33aa55"])
	var players: Array = doc.scenario.get("players", [])
	for i in players.size():
		var p: Dictionary = players[i]
		var col := String(p.get("color", ""))
		world.factions[i] = {"id": i, "team": int(p.get("team", i)), "faction_def": String(p.get("faction", "human_a")),
			"color": col if col != "" else String(colors[i % colors.size()]), "alive": true, "stage": int(p.get("stage", 8)),
			"spawn": Vector2i(p.get("start", Vector2i.ZERO))}
	for r in doc.map.get("resources", []):
		world.spawn_resource(String(r.res), int(r.amount), Vector2(r.cell) + Vector2(0.5, 0.5))
	if layers_on.units:
		_sync_placed()
	world.events.clear()
	# the editor world never steps: build the render snapshot here (entity_layer draws only from it)
	RenderSnap.build(world)
	snap = RenderSnap.latest(world)


func _sync_placed() -> void:
	for e in doc.scenario.get("entities", []):
		var owner := int(e.get("owner_slot", 0))
		var def := String(e.get("def", ""))
		if String(e.get("kind", "unit")) == "building":
			var bd := Content.building(def)
			if bd.is_empty():
				continue
			var size := int(bd.get("size", 1))
			var o := Vector2i(e.get("cell", Vector2i.ZERO))
			var id := world._new_id()
			world.entities[id] = {"id": id, "kind": "building", "def": def, "owner": owner, "cell": o, "size": size,
				"pos": Vector2(o) + Vector2(size, size) * 0.5, "hp": float(bd.get("hp", 100)), "max_hp": float(bd.get("hp", 100)),
				"built": bool(e.get("built", true)), "progress": 1.0 if bool(e.get("built", true)) else 0.0,
				"queue": [], "target": -1, "cooldown": 0.0, "status": "", "facing": float(e.get("facing", 0.0))}
		elif not Content.unit(def).is_empty():
			var pos: Vector2 = Vector2(e.pos) if e.has("pos") else Vector2(Vector2i(e.get("cell", Vector2i.ZERO))) + Vector2(0.5, 0.5)
			var uid := world.spawn_unit(def, owner, pos)
			world.entities[uid].facing = float(e.get("facing", 0.0))


## Call after a stroke / undo / redo: re-bake decor (trees, rocks) if terrain changed.
func stroke_finished() -> void:
	if _decor_dirty:
		_rebuild_entity_layer()


func _on_doc_changed(cells: Array, kind: String) -> void:
	if world == null:
		return
	if kind == "all" and (not is_same(world.map, doc.map) or cells.is_empty()):
		rebuild()
		return
	if not cells.is_empty():
		terrain_layer.rebake_cells(cells)
		_decor_dirty = true
	if kind != "terrain" or cells.is_empty():
		_sync_world()
	overlay.on_cells_changed(cells)
	if not doc.in_stroke():
		stroke_finished()


# ------------------------------------------------------------------ mv interface
static func world_to_screen(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * TILE_W * 0.5, (p.x + p.y) * TILE_H * 0.5)


static func screen_to_world(s: Vector2) -> Vector2:
	var a := s.x / (TILE_W * 0.5)
	var b := s.y / (TILE_H * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


func anim_time() -> float:
	return _anim


func team_color(fid: int) -> Color:
	if world != null and world.factions.has(fid):
		return Color(String(world.factions[fid].color))
	return Color(0.85, 0.85, 0.8)


func cell_visible(_c: Vector2i) -> bool:
	return true


func cell_explored(_c: Vector2i) -> bool:
	return true


func world_readable() -> bool:
	return true


func sim_busy() -> bool:
	return false


func fog_of(_fid: int) -> Dictionary:
	return {}


func entity_visible(_e: Dictionary) -> bool:
	return true


func center_camera_on(world_pos: Vector2) -> void:
	camera.center_on(world_to_screen(world_pos))


## The cell under the pointer. Uses the last mouse EVENT position (viewport coords), not the OS
## cursor: Viewport.get_mouse_position() reads the hardware cursor, so synthetic events (playtest,
## demo) would otherwise paint wherever the real cursor sits.
func mouse_cell() -> Vector2i:
	var vp: Vector2 = _mouse_vp if _mouse_known else get_viewport().get_mouse_position()
	return pick_canvas(get_canvas_transform().affine_inverse() * vp)


## Canvas (screen-space world) point -> cell, height-aware (ELEV-VIEW CR: ViewUtil.pick_cell over
## terrain_layer.height_map(); plain maps pick exactly as before).
func pick_canvas(s: Vector2) -> Vector2i:
	if terrain_layer != null and terrain_layer.has_method("height_map"):
		return ViewUtil.pick_cell(terrain_layer.height_map(), s)
	var p := screen_to_world(s)
	return Vector2i(floori(p.x), floori(p.y))


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_vp = (event as InputEventMouse).position
		_mouse_known = true


## Viewport position -> map cell (used by the demo/playtest scripts).
func cell_at_viewport(vp: Vector2) -> Vector2i:
	return pick_canvas(get_viewport().get_canvas_transform().affine_inverse() * vp)


# ------------------------------------------------------------------ G6 Live (ED6)
func is_live() -> bool:
	return live_world != null


## Enter (w = the Live world) or leave (w = null) Live display. Leaving resyncs from the doc.
func set_live_world(w: SimWorld) -> void:
	live_world = w
	if w != null:
		w.snap_enabled = true
		RenderSnap.build(w)
		snap = RenderSnap.latest(w)
		_world = w
	else:
		_world = world
		_sync_world()
	_rebuild_entity_layer()
	if overlay != null:
		overlay.queue_redraw()


## Steps the Live world n ticks (the render snapshot is rebuilt at the end of each step).
func live_step(n: int) -> void:
	if live_world == null or n <= 0:
		return
	for i in n:
		live_world.step()
	snap = RenderSnap.latest(live_world)


func _tool_allowed() -> bool:
	if live_world == null or tool == null:
		return true
	if tool.has_method("live_ok") and bool(tool.live_ok()):
		return true
	live_blocked.emit()
	return false


## After a height brush: the terrain layer re-reads map.height / ramps for these cells.
func height_changed(cells: Array) -> void:
	if terrain_layer != null and not cells.is_empty():
		terrain_layer.rebake_cells(cells)


func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < int(doc.map.w) and c.y < int(doc.map.h)


# ------------------------------------------------------------------ frame + input
func _process(delta: float) -> void:
	_anim += delta
	if world == null:
		return
	var pan := Vector2.ZERO
	if not _typing():
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): pan.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): pan.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): pan.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): pan.y += 1
	if pan != Vector2.ZERO:
		camera.pan_screen(pan * camera.edge_pan_speed() * delta)
	camera.tick(delta)
	terrain_layer.tick()
	if entity_layer != null and layers_on.units:
		entity_layer.visible = true
		entity_layer.refresh()
	elif entity_layer != null:
		entity_layer.visible = false
	var c := mouse_cell()
	if c != hover:
		hover = c
		hover_changed.emit(c)
		preview.queue_redraw()


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is SpinBox


func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			camera.zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			camera.zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_from = mb.position if mb.pressed else null
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if tool != null and tool.has_method("tool_cancel"):
				tool.tool_cancel()
			preview.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			var c := mouse_cell()
			if mb.pressed:
				_down = true
				_last_cell = c
				if not _tool_allowed():
					_down = false
				elif tool != null and tool.has_method("tool_begin"):
					tool.tool_begin(c)
			elif _down:
				_down = false
				if tool != null and tool.has_method("tool_end"):
					tool.tool_end(c)
			preview.queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pan_from != null:
			camera.pan_screen(_pan_from - mm.position)
			_pan_from = mm.position
		elif _down:
			var c2 := mouse_cell()
			if c2 != _last_cell and tool != null and tool.has_method("tool_drag"):
				tool.tool_drag(c2)
				_last_cell = c2


## Scripted input for the demo/playtest: press at a, drag through `path`, release at the end.
func scripted_stroke(cells: Array) -> void:
	if cells.is_empty() or tool == null or not _tool_allowed():
		return
	if tool.has_method("tool_begin"):
		tool.tool_begin(cells[0])
	for i in range(1, cells.size()):
		if tool.has_method("tool_drag"):
			tool.tool_drag(cells[i])
	if tool.has_method("tool_end"):
		tool.tool_end(cells[cells.size() - 1])
	preview.queue_redraw()
