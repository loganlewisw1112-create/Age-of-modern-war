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
	Color("6e6a66"), # building (G7 VIS7: codes 8-15 were all drawn in ridge colour)
	Color("3f7a9c"), # shallow
	Color("1f466b"), # deep
	Color("c2b27c"), # beach
	Color("3d3934"), # cliff
	Color("6f8a48"), # hill
	Color("5c5148"), # rail
	Color("120c18"), # chasm (G7 FISSURE7 canyons: a dark rift, not a ridge)
]
const CREEP_COL := Color(0.62, 0.24, 0.86)   # G7 VIS7: Machine creep on the minimap (under the fog, over the terrain)
const CREEP_EVERY := 1.5

var mv: Node = null
var _terrain_tex: ImageTexture = null
var _fog_tex: ImageTexture = null
var _fog_img: Image = null
var _map_w: int = 96
var _map_h: int = 96
var _fog_timer: float = 0.0
var _dragging: bool = false
var _built_for: SimWorld = null
# G3b (UI4): big maps (160/256) and big armies. Fog is rebuilt in row chunks into an LA8 byte
# buffer, the full minimap redraws at ~6 Hz when the world is large, and the camera rectangle
# lives on a child overlay that redraws every frame.
const BIG_WORLD_ENTITIES := 400  # UI4-2: above this the minimap redraws at ~6 Hz instead of every frame
const FOG_CHUNKS := 4
var _fog_bytes := PackedByteArray()
var _fog_row := 0
var _redraw_acc := 0.0
var _cam_overlay: Control = null
## G7 (SCALE7): on maps over TEX_MAX a side, the terrain and fog textures sample every _k-th cell
## (texture _tw x _th <= TEX_MAX), so the per-frame fog rebuild costs the same as on a 256 map (a 768
## map was 147k GDScript cell writes per frame while the fog refreshed). Maps <= 256: _k = 1, as before.
const TEX_MAX := 256
var _k := 1
var _tw := 96
var _th := 96


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(match_view: Node) -> void:
	mv = match_view
	_build_terrain()
	if _cam_overlay == null:
		_cam_overlay = Control.new()
		_cam_overlay.name = "MinimapCamera"
		_cam_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cam_overlay.size = Vector2(SIZE, SIZE)
		_cam_overlay.draw.connect(_draw_camera)
		add_child(_cam_overlay)


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
	_k = maxi(1, ceili(float(maxi(_map_w, _map_h)) / float(TEX_MAX)))
	_tw = ceili(float(_map_w) / float(_k))
	_th = ceili(float(_map_h) / float(_k))
	var img := Image.create(_tw, _th, false, Image.FORMAT_RGBA8)
	var ter: PackedByteArray = w.map.terrain
	for y in _th:
		for x in _tw:
			var code: int = ter[mini(y * _k, _map_h - 1) * _map_w + mini(x * _k, _map_w - 1)]
			img.set_pixel(x, y, TERRAIN_COLORS[clampi(code, 0, TERRAIN_COLORS.size() - 1)])
	_terrain_tex = ImageTexture.create_from_image(img)
	_fog_bytes = PackedByteArray()
	_fog_bytes.resize(_tw * _th * 2)
	for i in _tw * _th:
		_fog_bytes[i * 2 + 1] = 235
	_fog_img = Image.create_from_data(_tw, _th, false, Image.FORMAT_LA8, _fog_bytes)
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	_fog_row = 0


func _fog_arrays() -> Dictionary:
	var w := _world()
	if w == null:
		return {}
	var fid: int = int(mv.get("player_fid"))
	var f = w.fog.get(fid)
	if f == null:
		return {}
	return f


## Rebuilds FOG_CHUNKS-th of the fog rows per call; uploads the texture after the last chunk.
func _update_fog() -> bool:
	if _fog_img == null:
		return true
	var f := _fog_arrays()
	var vis: PackedByteArray = f.get("visible", PackedByteArray())
	var exp: PackedByteArray = f.get("explored", PackedByteArray())
	var n := _map_w * _map_h
	if vis.size() < n or exp.size() < n:
		return true
	var rows := int(ceil(float(_th) / FOG_CHUNKS))
	var y1 := mini(_th, _fog_row + rows)
	if _k == 1:
		for i in range(_fog_row * _map_w, y1 * _map_w):
			_fog_bytes[i * 2 + 1] = 0 if vis[i] != 0 else (128 if exp[i] != 0 else 237)
	else:
		for ty in range(_fog_row, y1):
			var row := mini(ty * _k, _map_h - 1) * _map_w
			var o := ty * _tw
			for tx in _tw:
				var i := row + mini(tx * _k, _map_w - 1)
				_fog_bytes[(o + tx) * 2 + 1] = 0 if vis[i] != 0 else (128 if exp[i] != 0 else 237)
	_fog_row = y1
	if _fog_row < _th:
		return false
	_fog_row = 0
	_fog_img.set_data(_tw, _th, false, Image.FORMAT_LA8, _fog_bytes)
	_fog_tex.update(_fog_img)
	return true


func _process(delta: float) -> void:
	# G4 (THREAD): no live reads while a sim step is in flight; the camera box still follows
	if mv != null and mv.has_method("sim_busy") and mv.sim_busy():
		if _cam_overlay != null:
			_cam_overlay.queue_redraw()
		return
	var w := _world()
	if w != _built_for:
		_build_terrain()
	_update_creep(delta)   # G7 VIS7
	_fog_timer += delta
	if _fog_timer >= 0.3 or _fog_row > 0:
		_fog_timer = 0.0
		_update_fog()
	_redraw_acc += delta
	var big := w != null and w.entities.size() > BIG_WORLD_ENTITIES
	if w != null and not w.map.is_empty() and (not big or _redraw_acc >= 0.16):
		_redraw_acc = 0.0
		if int(w.tick) != _dots_tick or _dot_tex == null:
			_rebuild_dots(w)
		queue_redraw()
	if _cam_overlay != null:
		_cam_overlay.queue_redraw()


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


## R4 CR (board seq 645): entity dots are painted into two SIZE x SIZE images only when w.tick
## changes (throttled to ~6 Hz on big worlds); _draw is then a handful of texture blits.
## _res_img sits under the fog (explored resources), _dot_img above it (memory + live entities).
var _res_img: Image = null
var _dot_img: Image = null
var _res_tex: ImageTexture = null
var _dot_tex: ImageTexture = null
var _dots_tick: int = -1


func _dot(img: Image, p: Vector2, half: float, col: Color) -> void:
	var r := Rect2i(Vector2i(roundi(p.x - half), roundi(p.y - half)), Vector2i(maxi(1, roundi(half * 2.0)), maxi(1, roundi(half * 2.0))))
	r = r.intersection(Rect2i(0, 0, SIZE, SIZE))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, col)


## Visible arrays the player sees through: own fog plus allied fog (G3a allied vision). Empty = no fog.
func _vis_arrays(w: SimWorld, pf: int) -> Array:
	var out := []
	var f: Dictionary = w.fog.get(pf, {})
	if f.is_empty():
		return out
	out.append(f.get("visible", PackedByteArray()))
	for fid in w.factions:
		if int(fid) != pf and G3.is_ally(w, pf, int(fid)):
			var af: Dictionary = w.fog.get(int(fid), {})
			if not af.is_empty():
				out.append(af.get("visible", PackedByteArray()))
	return out


func _seen_idx(vis: Array, x: int, y: int) -> bool:
	if vis.is_empty():
		return true
	if x < 0 or y < 0 or x >= _map_w or y >= _map_h:
		return false
	var i := y * _map_w + x
	for v in vis:
		if i < v.size() and int(v[i]) == 1:
			return true
	return false


func _rebuild_dots(w: SimWorld) -> void:
	if _dot_img == null:
		_res_img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		_dot_img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	_res_img.fill(Color(0, 0, 0, 0))
	_dot_img.fill(Color(0, 0, 0, 0))
	var pf: int = int(mv.get("player_fid"))
	var f := _fog_arrays()
	var exp: PackedByteArray = f.get("explored", PackedByteArray())
	var vis := _vis_arrays(w, pf)
	var own_vis: Array = [] if vis.is_empty() else [vis[0]]
	var s := _cell_scale()
	var colors := {}  # owner -> [fill, is_ally, own]
	# Remembered enemy buildings (under the live dots).
	var mem: Dictionary = w.memory.get(pf, {})
	for eid in mem:
		var m: Dictionary = mem[eid]
		var mp: Vector2 = m.pos
		if w.entities.has(int(eid)) and _seen_idx(own_vis, floori(mp.x), floori(mp.y)):
			continue  # drawn live below
		var ocol := G3.side_color(w, int(m.owner)) if w.factions.has(int(m.owner)) else Color.RED
		_dot(_dot_img, _to_mini(mp), 2.5, ocol.darkened(0.25))
	# One pass over every entity.
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		var k: String = e.kind
		var p: Vector2 = e.pos
		if k == "resource":
			var idx := floori(p.y) * _map_w + floori(p.x)
			if idx >= 0 and idx < exp.size() and exp[idx] != 0:
				_dot(_res_img, _to_mini(p), 1.0, Color("c9c9c9") if e.res == "salvage" else Color("d98a3d"))
			continue
		if k != "unit" and k != "building":
			continue
		var owner := int(e.owner)
		if not colors.has(owner):
			var ally0 := G3.is_ally(w, pf, owner)
			var c0 := G3.side_color(w, owner) if w.factions.has(owner) else Color.WHITE
			if owner != pf and not ally0:
				c0 = c0.lightened(0.15) if w.factions.has(owner) else Color.RED
			colors[owner] = [c0, ally0, owner == pf]
		var cc: Array = colors[owner]
		var col: Color = cc[0]
		var ally: bool = cc[1]
		# Enemies only where the player (or an ally) can see.
		if not cc[2] and not ally and not _seen_idx(vis, floori(p.x), floori(p.y)):
			continue
		# G4b: concealed enemy snipers stay off the minimap unless our team spots them
		if not cc[2] and not ally and k == "unit" and e.get("hid", false) and not (e.get("spot", []) as Array).has(G3.team_of(w, pf)):
			continue
		var edge := Color(1, 1, 1, 0.85) if ally else Color(0, 0, 0, 0.8)
		var mp2 := _to_mini(p)
		if k == "building":
			var half: float = float(e.size) * s.x * 0.5
			_dot(_dot_img, mp2, half + 0.5, edge)
			_dot(_dot_img, mp2, maxf(0.5, half - 0.5), col)
		elif ally:
			_dot(_dot_img, mp2, 2.0, edge)
			_dot(_dot_img, mp2, 1.0, col)
		else:
			_dot(_dot_img, mp2, 1.5, col)
	if _res_tex == null:
		_res_tex = ImageTexture.create_from_image(_res_img)
		_dot_tex = ImageTexture.create_from_image(_dot_img)
	else:
		_res_tex.update(_res_img)
		_dot_tex.update(_dot_img)
	_dots_tick = int(w.tick)


## G7 VIS7: creep coverage texture from the render snapshot's creep field (snap.creep v / on; cs-tile cells), rebuilt
## every CREEP_EVERY s while the match has creep. Dense creep opaque, thin creep faint.
var _creep_tex: ImageTexture = null
var _creep_t := 0.0
var _creep_bytes := PackedByteArray()
var _creep_rect := Rect2()
var creep_cells := 0   # cells drawn as creep at the last rebuild (tests / playtest probe)


func _update_creep(delta: float) -> void:
	_creep_t -= delta
	if _creep_t > 0.0:
		return
	_creep_t = CREEP_EVERY
	var sn = mv.get("snap") if mv != null else null
	var c = sn.get("creep") if sn is Dictionary else null
	if not (c is Dictionary) or (c as Dictionary).is_empty():
		_creep_tex = null
		creep_cells = 0
		return
	var cw := int(c.cw)
	var ch := int(c.ch)
	var v: PackedByteArray = c.v
	if cw <= 0 or ch <= 0 or v.size() != cw * ch:
		return
	var on := int(c.get("on", 64))
	var half := on / 2
	if _creep_bytes.size() != cw * ch * 2:
		_creep_bytes.resize(cw * ch * 2)
	var n := 0
	for k in cw * ch:
		var x := v[k]
		var a := 0
		if x >= on:
			a = 200
			n += 1
		elif x >= half:
			a = 90
		_creep_bytes[k * 2] = 255 if x >= on else 190
		_creep_bytes[k * 2 + 1] = a
	creep_cells = n
	var img := Image.create_from_data(cw, ch, false, Image.FORMAT_LA8, _creep_bytes)
	if _creep_tex == null or _creep_tex.get_size() != Vector2(cw, ch):
		_creep_tex = ImageTexture.create_from_image(img)
	else:
		_creep_tex.update(img)
	var cs := float(c.get("cs", 4))
	var sc := _cell_scale()
	_creep_rect = Rect2(Vector2.ZERO, Vector2(cw * cs, ch * cs) * sc)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color("0c0f10"))
	var w := _world()
	if w == null or _terrain_tex == null:
		return
	var full := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	draw_texture_rect(_terrain_tex, full, false)
	if _res_tex != null:
		draw_texture_rect(_res_tex, full, false)
	if _creep_tex != null:   # G7 VIS7: creep under the fog (unexplored creep stays hidden)
		draw_texture_rect(_creep_tex, _creep_rect, false, CREEP_COL)
	# G3a: territory sectors tinted by owning team (only when the sim tracks territory).
	if w.sys_state.has("territory"):
		_draw_territory(w)
	if _fog_tex != null:
		draw_texture_rect(_fog_tex, full, false)
	if _dot_tex != null:
		draw_texture_rect(_dot_tex, full, false)
	draw_rect(full, Color("4b555b"), false, 1.0)


## Camera rectangle (child overlay, every frame).
func _draw_camera() -> void:
	var poly := _camera_poly()
	if poly.size() == 4:
		var closed := PackedVector2Array(poly)
		closed.append(poly[0])
		_cam_overlay.draw_polyline(closed, Color(1, 1, 1, 0.9), 1.0)


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
