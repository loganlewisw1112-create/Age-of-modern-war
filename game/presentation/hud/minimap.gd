extends Control
## 192x192 minimap: terrain colours + fog + own/enemy dots + camera rectangle.
## Click or drag moves the camera via MatchView.center_camera_on. Read-only on the sim.

const G3 = preload("res://presentation/hud/g3_faction.gd")
const SIZE := 192
const TERRAIN_COLORS := [
	Color("5d7d3d"), # grass
	Color("8b7452"), # dirt
	Color("73736f"), # road
	Color("2f5232"), # forest
	Color("2c5f8c"), # water
	Color("8c6b46"), # bridge
	Color("5d90a8"), # ford
	Color("57534d"), # ridge
]

var mv: Node = null
var _terrain_tex: ImageTexture = null
var _fog_tex: ImageTexture = null
var _fog_img: Image = null
var _map_w: int = 96
var _map_h: int = 96
var _fog_timer: float = 0.0
var _dragging: bool = false
var _built_for: SimWorld = null


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(match_view: Node) -> void:
	mv = match_view
	_build_terrain()


func _world() -> SimWorld:
	if mv == null:
		return null
	return mv.get("world") as SimWorld


func _build_terrain() -> void:
	var w := _world()
	if w == null or w.map.is_empty():
		return
	_built_for = w
	_map_w = int(w.map.w)
	_map_h = int(w.map.h)
	var img := Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	var ter: PackedByteArray = w.map.terrain
	for y in _map_h:
		for x in _map_w:
			var code: int = ter[y * _map_w + x]
			img.set_pixel(x, y, TERRAIN_COLORS[clampi(code, 0, TERRAIN_COLORS.size() - 1)])
	_terrain_tex = ImageTexture.create_from_image(img)
	_fog_img = Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	_fog_img.fill(Color(0, 0, 0, 0.92))
	_fog_tex = ImageTexture.create_from_image(_fog_img)


func _fog_arrays() -> Dictionary:
	var w := _world()
	if w == null:
		return {}
	var fid: int = int(mv.get("player_fid"))
	var f = w.fog.get(fid)
	if f == null:
		return {}
	return f


func _update_fog() -> void:
	if _fog_img == null:
		return
	var f := _fog_arrays()
	var vis: PackedByteArray = f.get("visible", PackedByteArray())
	var exp: PackedByteArray = f.get("explored", PackedByteArray())
	var n := _map_w * _map_h
	if vis.size() < n or exp.size() < n:
		return
	for y in _map_h:
		for x in _map_w:
			var i := y * _map_w + x
			var a := 0.0
			if vis[i] == 0:
				a = 0.5 if exp[i] != 0 else 0.93
			_fog_img.set_pixel(x, y, Color(0, 0, 0, a))
	_fog_tex.update(_fog_img)


func _process(delta: float) -> void:
	var w := _world()
	if w != _built_for:
		_build_terrain()
	_fog_timer += delta
	if _fog_timer >= 0.3:
		_fog_timer = 0.0
		_update_fog()
	queue_redraw()


func _cell_scale() -> Vector2:
	return Vector2(float(SIZE) / _map_w, float(SIZE) / _map_h)


func _to_mini(p: Vector2) -> Vector2:
	# World tile coords -> minimap pixels. Map coordinates are plain tile units here.
	return p * _cell_scale()


func _to_world(m: Vector2) -> Vector2:
	var s := _cell_scale()
	return Vector2(m.x / s.x, m.y / s.y)


## Visible to the player or (G3a allied vision) to an ally: asks the MatchView when it can.
func _seen(w: SimWorld, f: Dictionary, p: Vector2) -> bool:
	if mv != null and mv.has_method("cell_visible"):
		return bool(mv.cell_visible(w.cell_of(p)))
	return _cell_visible(f, p)


func _draw_territory(w: SimWorld) -> void:
	var st: Dictionary = w.sys_state.territory
	var owners: Array = st.get("owner", [])
	var counted: Array = st.get("counted", [])
	var size := int(st.get("size", 12))
	var cols := int(st.get("cols", 1))
	var sc := _cell_scale()
	for i in owners.size():
		if i >= counted.size() or not bool(counted[i]):
			continue
		var r := Rect2(Vector2((i % cols) * size, (i / cols) * size) * sc, Vector2(size, size) * sc)
		var t := int(owners[i])
		if t >= 0:
			var fids: Array = G3.teams(w).get(t, [])
			var c: Color = G3.side_color(w, int(fids[0])) if not fids.is_empty() else Color.GRAY
			draw_rect(r, Color(c.r, c.g, c.b, 0.28))
		draw_rect(r, Color(1, 1, 1, 0.10), false, 1.0)


func _cell_visible(f: Dictionary, p: Vector2) -> bool:
	var vis: PackedByteArray = f.get("visible", PackedByteArray())
	var cx := floori(p.x)
	var cy := floori(p.y)
	if cx < 0 or cy < 0 or cx >= _map_w or cy >= _map_h:
		return false
	var i := cy * _map_w + cx
	return i < vis.size() and vis[i] != 0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color("0c0f10"))
	var w := _world()
	if w == null or _terrain_tex == null:
		return
	draw_texture_rect(_terrain_tex, Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), false)
	var pf: int = int(mv.get("player_fid"))
	var f := _fog_arrays()
	var s := _cell_scale()
	# Resources (only where explored).
	var exp: PackedByteArray = f.get("explored", PackedByteArray())
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "resource":
			var c := w.cell_of(e.pos)
			var idx := c.y * _map_w + c.x
			if idx >= 0 and idx < exp.size() and exp[idx] != 0:
				var col := Color("c9c9c9") if e.res == "salvage" else Color("d98a3d")
				draw_rect(Rect2(_to_mini(e.pos) - Vector2(1, 1), Vector2(2, 2)), col)
	# G3a: territory sectors tinted by owning team (only when the sim tracks territory).
	if w.sys_state.has("territory"):
		_draw_territory(w)
	# Fog overlay.
	if _fog_tex != null:
		draw_texture_rect(_fog_tex, Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), false)
	# Remembered enemy buildings.
	var mem: Dictionary = w.memory.get(pf, {})
	for eid in mem:
		var m: Dictionary = mem[eid]
		if w.entities.has(int(eid)) and _cell_visible(f, m.pos):
			continue  # drawn live below
		var ocol := G3.side_color(w, int(m.owner)) if w.factions.has(int(m.owner)) else Color.RED
		draw_rect(Rect2(_to_mini(m.pos) - Vector2(2.5, 2.5), Vector2(5, 5)), ocol.darkened(0.25))
	# Live entities.
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" and e.kind != "building":
			continue
		var owner := int(e.owner)
		var own := owner == pf
		# G3a: allies always show in their own colour (white outline); enemies only where the
		# player (or an ally, via mv.cell_visible) can see, outlined black.
		var ally := G3.is_ally(w, pf, owner)
		if not own and not ally and not _seen(w, f, e.pos):
			continue
		var col := G3.side_color(w, owner) if w.factions.has(owner) else Color.WHITE
		if not own and not ally:
			col = col.lightened(0.15) if w.factions.has(owner) else Color.RED
		var edge := Color(1, 1, 1, 0.85) if ally else Color(0, 0, 0, 0.8)
		if e.kind == "building":
			var sz: float = float(e.size) * s.x
			draw_rect(Rect2(_to_mini(e.pos) - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col)
			draw_rect(Rect2(_to_mini(e.pos) - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), edge, false, 1.0)
		else:
			draw_rect(Rect2(_to_mini(e.pos) - Vector2(1.5, 1.5), Vector2(3, 3)), col)
			if ally:
				draw_rect(Rect2(_to_mini(e.pos) - Vector2(2, 2), Vector2(4, 4)), edge, false, 1.0)
	# Camera rectangle.
	var poly := _camera_poly()
	if poly.size() == 4:
		var closed := PackedVector2Array(poly)
		closed.append(poly[0])
		draw_polyline(closed, Color(1, 1, 1, 0.9), 1.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color("4b555b"), false, 1.0)


## Visible screen area as 4 minimap points. Works whether MatchView uses a Camera2D or moves itself.
func _camera_poly() -> PackedVector2Array:
	var out := PackedVector2Array()
	if mv == null or not (mv is CanvasItem):
		return out
	var vp := get_viewport()
	if vp == null:
		return out
	var vsize := vp.get_visible_rect().size
	var to_screen_local: Transform2D = (vp.get_canvas_transform() * (mv as CanvasItem).get_global_transform()).affine_inverse()
	for corner in [Vector2(0, 0), Vector2(vsize.x, 0), vsize, Vector2(0, vsize.y)]:
		var sp: Vector2 = to_screen_local * corner
		var a := sp.x / 32.0
		var b := sp.y / 16.0
		var wp := Vector2((a + b) * 0.5, (b - a) * 0.5)
		out.append(_to_mini(wp).clamp(Vector2.ZERO, Vector2(SIZE, SIZE)))
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_jump(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_jump(event.position)
		accept_event()


func _jump(local: Vector2) -> void:
	if mv != null and mv.has_method("center_camera_on"):
		mv.center_camera_on(_to_world(local.clamp(Vector2.ZERO, Vector2(SIZE, SIZE))))
