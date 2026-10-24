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
const TILE_W := 64
const TILE_H := 32

signal hover_changed(cell: Vector2i)

var doc                      # editor_doc.gd
var world: SimWorld
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
	if not layers_on.units:
		return
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
	world.events.clear()


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


func entity_visible(_e: Dictionary) -> bool:
	return true


func center_camera_on(world_pos: Vector2) -> void:
	camera.center_on(world_to_screen(world_pos))


func mouse_cell() -> Vector2i:
	var p := screen_to_world(get_global_mouse_position())
	return Vector2i(floori(p.x), floori(p.y))


## Viewport position -> map cell (used by the demo/playtest scripts).
func cell_at_viewport(vp: Vector2) -> Vector2i:
	var p := screen_to_world(get_viewport().get_canvas_transform().affine_inverse() * vp)
	return Vector2i(floori(p.x), floori(p.y))


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
				if tool != null and tool.has_method("tool_begin"):
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
	if cells.is_empty() or tool == null:
		return
	if tool.has_method("tool_begin"):
		tool.tool_begin(cells[0])
	for i in range(1, cells.size()):
		if tool.has_method("tool_drag"):
			tool.tool_drag(cells[i])
	if tool.has_method("tool_end"):
		tool.tool_end(cells[cells.size() - 1])
	preview.queue_redraw()
