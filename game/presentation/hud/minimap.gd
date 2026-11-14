extends Control
## 192x192 minimap: terrain colours + fog + own/enemy dots + camera rectangle.
## Click or drag moves the camera via MatchView.center_camera_on. Read-only on the sim.

const G3 = preload("res://presentation/hud/g3_faction.gd")
## G7.1 CONTROL71 (A4): bigger (192 -> 208, the most the bottom panel's 220 px holds without moving the cargo strip above
## it; a larger value needs hud.gd BOTTOM_H room, see the change_request). SIZE is an instance var so ORCH can set it
## (before the first draw) without touching this file again.
## G7.1 UIFIX71: _init sized the control from DEFAULT_SIZE, so a SIZE set afterwards (hud.gd) never reached the layout:
## the 208 box made the bottom panel 230 px tall (over the group bar / group panel). Setting SIZE now resizes the box too;
## hud.gd picks the largest square its 220 px panel holds.
const DEFAULT_SIZE := 208
var SIZE := DEFAULT_SIZE:
	set(v):
		SIZE = v
		custom_minimum_size = Vector2(v, v)
		size = Vector2(v, v)
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
	_inc_ensure()   # G7.1 PERFDRAW71 (CR 467): incoming-marker layers, drawn under the camera rectangle
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
	if _inc_on and not inc_old:   # G7.1 PERFDRAW71 (CR 467): the incoming-marker pulse is a shader uniform
		_inc_mat.set_shader_parameter("pulse", _inc_pulse())
	# G4 (THREAD): no live reads while a sim step is in flight; the camera box still follows
	if mv != null and mv.has_method("sim_busy") and mv.sim_busy():
		if _cam_overlay != null:
			_cam_overlay.queue_redraw()
		return
	var w := _world()
	if w != _built_for:
		_build_terrain()
	if not _vis7_off:
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


## G7 LPPERF7B: the sector tints are painted into one SIZE x SIZE image (rebuilt only when the owners change; same pixels
## as the per-sector draw_rect: a pixel belongs to the sector its centre lies in) and the sector outlines go out as one
## draw_multiline. It used to be 2 draw calls per sector: ~1900 a frame on a 512 x 512 map (43 x 43 sectors).
var _terr_img: Image = null
var _terr_tex: ImageTexture = null
var _terr_sig := 0
var _terr_lines := PackedVector2Array()


func _draw_territory(w: SimWorld) -> void:
	var st: Dictionary = w.sys_state.territory
	var owners: Array = st.get("owner", [])
	var counted: Array = st.get("counted", [])
	var size := int(st.get("size", 12))
	var cols := int(st.get("cols", 1))
	var sc := _cell_scale()
	var cols_t: Array = []
	var tm: Dictionary = G3.teams(w)
	var tks: Array = tm.keys()
	tks.sort()
	for t in tks:
		var fids: Array = tm[t]
		cols_t.append([t, G3.side_color(w, int(fids[0])) if not fids.is_empty() else Color.GRAY])
	var sig := hash([owners, counted, size, cols, sc, cols_t])
	if sig != _terr_sig or _terr_tex == null:
		_terr_sig = sig
		var tcol := {}
		for tc in cols_t:
			tcol[tc[0]] = tc[1]
		if _terr_img == null:
			_terr_img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		_terr_img.fill(Color(0, 0, 0, 0))
		_terr_lines = PackedVector2Array()
		for i in owners.size():
			if i >= counted.size() or not bool(counted[i]):
				continue
			var r := Rect2(Vector2((i % cols) * size, (i / cols) * size) * sc, Vector2(size, size) * sc)
			var t := int(owners[i])
			if t >= 0:
				var c: Color = tcol.get(t, Color.GRAY)
				var x0 := clampi(ceili(r.position.x - 0.5), 0, SIZE)
				var y0 := clampi(ceili(r.position.y - 0.5), 0, SIZE)
				var x1 := clampi(ceili(r.end.x - 0.5), 0, SIZE)
				var y1 := clampi(ceili(r.end.y - 0.5), 0, SIZE)
				if x1 > x0 and y1 > y0:
					_terr_img.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), Color(c.r, c.g, c.b, 0.28))
			var a := r.position
			var b := Vector2(r.end.x, r.position.y)
			var c2 := r.end
			var d := Vector2(r.position.x, r.end.y)
			_terr_lines.append_array([a, b, b, c2, c2, d, d, a])
		if _terr_tex == null:
			_terr_tex = ImageTexture.create_from_image(_terr_img)
		else:
			_terr_tex.update(_terr_img)
	draw_texture_rect(_terr_tex, Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), false)
	if not _terr_lines.is_empty():
		draw_multiline(_terr_lines, Color(1, 1, 1, 0.10), 1.0)


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
	_tb_n = SIZE / THREAT_BIN + 1
	if _tbins.size() != _tb_n * _tb_n:
		_tbins.resize(_tb_n * _tb_n)
	_tbins.fill(0)
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
			if k == "unit":   # G7.1 CONTROL71: visible hostile concentrations -> threat bins (the "incoming" markers)
				var bx := clampi(int(mp2.x) / THREAT_BIN, 0, _tb_n - 1)
				var by := clampi(int(mp2.y) / THREAT_BIN, 0, _tb_n - 1)
				_tbins[by * _tb_n + bx] += 1
	if _res_tex == null:
		_res_tex = ImageTexture.create_from_image(_res_img)
		_dot_tex = ImageTexture.create_from_image(_dot_img)
	else:
		_res_tex.update(_res_img)
		_dot_tex.update(_dot_img)
	_dots_tick = int(w.tick)
	_threats = _threat_clusters()
	_waves = _wave_markers(w)
	_rebuild_incoming()   # G7.1 PERFDRAW71 (CR 467)


## G7 VIS7: creep coverage texture from the render snapshot's creep field (snap.creep v / on; cs-tile cells), rebuilt
## every CREEP_EVERY s while the match has creep. Dense creep opaque, thin creep faint.
var _creep_tex: ImageTexture = null
var _creep_t := 0.0
var _creep_bytes := PackedByteArray()
var _creep_rect := Rect2()
var creep_cells := 0
var _vis7_off := OS.get_environment("VIS7_OFF") == "1"   # bench A/B only   # cells drawn as creep at the last rebuild (tests / playtest probe)


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
	if inc_old:   # G7.1 PERFDRAW71 (CR 467): the markers are retained layers now; this is the A/B reference path
		_draw_incoming()
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


# ================================================================ G7.1 CONTROL71 (A4): incoming waves
## Two sources, both read-only:
##  - survival waves (w.sys_state.waves, G6 MODES6): the next wave's spawn point as a pulsing ring with a countdown,
##    and each live wave as a red blob at its units' centroid with a dashed arrow to its target;
##  - any match: concentrations of visible hostile units (>= THREAT_MIN in one THREAT_BIN-px minimap bin) as pulsing red
##    rings with a short arrow towards the player's base (the Last Protocol hive, whose director exposes no wave list
##    yet, shows up this way: rings appear where the player can see the push coming).
## Rebuilt with the dots (same cadence). G7.1 PERFDRAW71 (CR 467): drawn as retained batched layers (end of file);
## _draw_incoming below is kept as the reference path (MINIMAP_INC_OLD=1, A/B and look proofs only).
const THREAT_BIN := 10
const THREAT_MIN := 6
const WAVE_COL := Color(1.0, 0.25, 0.2)
var _tbins := PackedInt32Array()
var _tb_n := 1
var _threats: Array = []     # [{p: Vector2 minimap px, n: int}]
var _waves: Array = []       # [{kind: "spawn"|"live", p, to?: Vector2, n, eta: int s}]
var _base_mini := Vector2(-1, -1)


func _threat_clusters() -> Array:
	var out: Array = []
	var n := _tb_n
	for i in _tbins.size():
		var c := _tbins[i]
		if c >= THREAT_MIN:
			out.append({"p": Vector2((i % n) + 0.5, (i / n) + 0.5) * THREAT_BIN, "n": c})
	if out.size() > 24:
		out.sort_custom(func(a, b): return int(a.n) > int(b.n))
		out.resize(24)
	return out


func _wave_markers(w: SimWorld) -> Array:
	var out: Array = []
	var pf := int(mv.get("player_fid")) if mv != null else 0
	if w.factions.has(pf):
		_base_mini = _to_mini(Vector2(w.factions[pf].spawn) + Vector2(0.5, 0.5))
	var st = w.sys_state.get("waves")
	if typeof(st) != TYPE_DICTIONARY:
		return out
	var spawns: Array = st.get("spawns", [])
	var ni := int(st.get("next_spawn", -1))
	if ni >= 0 and ni < spawns.size() and int(st.get("next_tick", -1)) >= 0:
		var sc: Vector2i = spawns[ni]
		out.append({"kind": "spawn", "p": _to_mini(Vector2(sc) + Vector2(0.5, 0.5)),
			"eta": maxi(0, int(st.next_tick) - int(w.tick)) / SimWorld.TICK_RATE, "n": 0})
	for wv in st.get("waves", []):
		if typeof(wv) != TYPE_DICTIONARY or int(wv.get("alive", 0)) <= 0 or bool(wv.get("destroyed", false)):
			continue
		var sum := Vector2.ZERO
		var cnt := 0
		for uid in wv.get("units", []):
			var u = w.entities.get(int(uid))
			if u != null:
				sum += u.pos
				cnt += 1
				if cnt >= 48:
					break
		if cnt > 0:
			var tgt: Vector2 = wv.get("target", Vector2.ZERO)
			out.append({"kind": "live", "p": _to_mini(sum / float(cnt)), "to": _to_mini(tgt), "n": int(wv.get("alive", cnt)), "eta": 0})
	return out


func _draw_incoming() -> void:
	if _threats.is_empty() and _waves.is_empty():
		return
	var pulse := _inc_pulse()   # G7.1 PERFDRAW71: same formula, frozen when inc_pulse_fixed >= 0 (look proofs)
	var font := ThemeDB.fallback_font
	var cap := Vector2(SIZE, SIZE)
	for th in _threats:
		var p: Vector2 = th.p
		var r := 3.0 + minf(5.0, sqrt(float(th.n)) * 0.7) + pulse * 1.5
		_cam_overlay.draw_arc(p, r, 0.0, TAU, 20, Color(WAVE_COL, 0.55 + 0.4 * pulse), 1.5, true)
		if _base_mini.x >= 0.0 and p.distance_to(_base_mini) > r + 8.0:
			var d := (_base_mini - p).normalized()
			_arrow(p + d * (r + 1.0), p + d * (r + 9.0), Color(WAVE_COL, 0.8))
	for wm in _waves:
		var p2: Vector2 = wm.p
		if String(wm.kind) == "spawn":
			var r2 := 5.0 + pulse * 3.0
			_cam_overlay.draw_arc(p2, r2, 0.0, TAU, 24, Color(1.0, 0.8, 0.2, 0.9), 2.0, true)
			_cam_overlay.draw_circle(p2, 2.0, Color(1.0, 0.8, 0.2))
			var txt := "%d:%02d" % [int(wm.eta) / 60, int(wm.eta) % 60]
			var tp := p2 + Vector2(7, 4)
			tp.x = minf(tp.x, cap.x - 30.0)
			tp.y = clampf(tp.y, 10.0, cap.y - 2.0)
			_cam_overlay.draw_string(font, tp + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.9))
			_cam_overlay.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.9, 0.5))
		else:
			var to: Vector2 = wm.to
			_cam_overlay.draw_dashed_line(p2, to, Color(WAVE_COL, 0.6), 1.0, 4.0)
			_cam_overlay.draw_circle(p2, 3.0 + minf(4.0, sqrt(float(wm.n)) * 0.5), Color(WAVE_COL, 0.55 + 0.4 * pulse))
			_cam_overlay.draw_arc(p2, 5.0 + minf(4.0, sqrt(float(wm.n)) * 0.5), 0.0, TAU, 20, Color(1, 1, 1, 0.8), 1.0, true)


func _arrow(a: Vector2, b: Vector2, col: Color) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	_cam_overlay.draw_line(a, b, col, 1.5, true)
	_cam_overlay.draw_colored_polygon(PackedVector2Array([b + d * 3.0, b - d * 1.0 + n * 3.0, b - d * 1.0 - n * 3.0]), col)


# ================================================================ G7.1 PERFDRAW71 (CR 467): incoming markers, batched
## Same look as _draw_incoming, far fewer canvas commands. The old path re-issued ~70 commands every frame at 24 threat
## clusters (each antialiased draw_arc / draw_line and each draw_colored_polygon is its own command: about +110 draw
## calls at 10k). Now the markers are built only when _threats / _waves / the base change (at the dot rebuild), exactly
## as Godot builds those primitives (draw_arc AA: a core strip offset along the corner bisector with the miter length,
## plus feathers of 1.25 px fading to transparent; draw_line AA: a core quad + 4 edge and 4 corner feather quads;
## draw_circle: a 64-segment fan; draw_colored_polygon: one triangle), in the same draw order, into ONE triangle array
## per layer. The pulse (ring radius, arrow offset, ring / blob alpha) is applied by a vertex shader from a uniform
## set once per frame. Text and dashed lines (survival spawn countdown, live-wave arrows) stay native calls on plain
## layers in their original place in the order. Display only: nothing here reads or writes more of the sim than before.
const INC_FEATHER := 1.25   # Godot RendererCanvasCull FEATHER_SIZE: the AA feather of draw_arc / draw_line
const INC_TB_MAX := 24      # _threat_clusters keeps at most 24 clusters
const INC_SHADER_CODE := """shader_type canvas_item;
// G7.1 PERFDRAW71 minimap incoming markers. UV = d + (8 m, 0): d = vertex offset per unit of pulse;
// m = 0 static, 1 alpha pulses (a *= 0.55 + 0.4 pulse), m >= 2 hidden while pulse >= (m - 2) / 100
// (a threat arrow the old code dropped while its ring had grown to within 8 px of the base).
uniform float pulse = 0.0;
void vertex() {
	float m = floor(UV.x / 8.0 + 0.5);
	VERTEX += vec2(UV.x - 8.0 * m, UV.y) * pulse;
	if (m == 1.0) {
		COLOR.a *= 0.55 + 0.4 * pulse;
	} else if (m >= 2.0 && pulse >= (m - 2.0) * 0.01) {
		VERTEX = vec2(0.0);
	}
}
"""
var inc_old := OS.get_environment("MINIMAP_INC_OLD") == "1"   # A/B + look proofs only: the old per-frame path
var inc_pulse_fixed := float(OS.get_environment("MINIMAP_INC_PULSE")) if OS.has_environment("MINIMAP_INC_PULSE") else -1.0   # >= 0: frozen pulse (look proofs only)
var inc_layers_used := 0    # layers drawn at the last rebuild (probe / tests)
var inc_rebuild_us := 0     # cost of the last geometry rebuild (probe)
var _inc_root: Control = null
var _inc_layers: Array = []   # Control per layer, in draw order (children of _inc_root)
var _inc_data: Array = []     # per layer: {geo: true, p, c, uv, i} or {geo: false, ops: [[kind, ...]]}
var _inc_mat: ShaderMaterial = null
var _inc_on := false          # a geometry layer is shown: the pulse uniform is set every frame
var _inc_key: Array = []
var _inc_tpl := {}            # shape templates
var _inc_tb := {}             # 24 threat blocks: colours, UVs and indices never change
var _g_p := PackedVector2Array()
var _g_c := PackedColorArray()
var _g_uv := PackedVector2Array()
var _g_i := PackedInt32Array()
var _g_n := 0
var _g_ni := 0


func _inc_pulse() -> float:
	if inc_pulse_fixed >= 0.0:
		return inc_pulse_fixed
	return 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * 5.0)


func _inc_ensure() -> void:
	if _inc_root != null:
		return
	_inc_root = Control.new()
	_inc_root.name = "MinimapIncoming"
	_inc_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inc_root.size = Vector2(SIZE, SIZE)
	_inc_root.visible = not inc_old
	add_child(_inc_root)
	var sh := Shader.new()
	sh.code = INC_SHADER_CODE
	_inc_mat = ShaderMaterial.new()
	_inc_mat.shader = sh


## A/B + look proofs only: switch between the old per-frame path and the batched layers at run time.
func inc_set_old(on: bool) -> void:
	inc_old = on
	_inc_ensure()
	_inc_root.visible = not on
	_inc_key = []
	_rebuild_incoming()
	if _cam_overlay != null:
		_cam_overlay.queue_redraw()


func _rebuild_incoming() -> void:
	if _inc_root == null or inc_old:
		return
	var key := [_threats, _waves, _base_mini]
	if key == _inc_key:
		return
	var t0 := Time.get_ticks_usec()
	_inc_key = key
	_inc_data = []
	_inc_flush()
	if not _threats.is_empty():
		_inc_threats()
	var cap := Vector2(SIZE, SIZE)
	for wm in _waves:
		var p2: Vector2 = wm.p
		if String(wm.kind) == "spawn":
			_inc_emit(_inc_shape("ring24w2"), p2, 5.0, Color(1.0, 0.8, 0.2, 0.9), 3.0, 0)   # r 5 + 3 pulse
			_inc_emit(_inc_shape("fan"), p2, 2.0, Color(1.0, 0.8, 0.2), 0.0, 0)
			var txt := "%d:%02d" % [int(wm.eta) / 60, int(wm.eta) % 60]
			var tp := p2 + Vector2(7, 4)
			tp.x = minf(tp.x, cap.x - 30.0)
			tp.y = clampf(tp.y, 10.0, cap.y - 2.0)
			_inc_op(["str", tp + Vector2(1, 1), txt, Color(0, 0, 0, 0.9)])
			_inc_op(["str", tp, txt, Color(1.0, 0.9, 0.5)])
		else:
			_inc_op(["dash", p2, wm.to, Color(WAVE_COL, 0.6)])
			var sz := minf(4.0, sqrt(float(wm.n)) * 0.5)
			_inc_emit(_inc_shape("fan"), p2, 3.0 + sz, Color(WAVE_COL, 1.0), 0.0, 1)        # alpha 0.55 + 0.4 pulse
			_inc_emit(_inc_shape("ring20w1"), p2, 5.0 + sz, Color(1, 1, 1, 0.8), 0.0, 0)
	_inc_flush()
	_inc_apply()
	inc_rebuild_us = Time.get_ticks_usec() - t0


## Threat clusters first (vertex 0 on): every cluster is one fixed block (ring + arrow, the arrow collapsed when the old
## code would not draw it), so colours, UVs of the ring and all indices come from the cached 24-block arrays.
func _inc_threats() -> void:
	var ring: Dictionary = _inc_shape("ring20w15")
	var arw: Dictionary = _inc_shape("arrow")
	var ru: PackedVector2Array = ring.u
	var rk: PackedFloat32Array = ring.k
	var au: PackedVector2Array = arw.u
	var nr := ru.size()
	var na := au.size()
	var nb := nr + na
	var cnt := mini(_threats.size(), INC_TB_MAX)
	if _inc_tb.is_empty():
		for t in INC_TB_MAX:
			_inc_emit(ring, Vector2.ZERO, 0.0, Color(WAVE_COL, 1.0), 1.5, 1)   # r0 + 1.5 pulse, alpha pulses
			_inc_emit(arw, Vector2.ZERO, 0.0, Color(WAVE_COL, 0.8), 0.0, 0)
		_inc_tb = {"c": _g_c.slice(0, _g_n), "uv": _g_uv.slice(0, _g_n), "i": _g_i.slice(0, _g_ni)}
		_g_n = 0
		_g_ni = 0
	_g_c = _inc_tb.c.slice(0, cnt * nb)
	_g_uv = _inc_tb.uv.slice(0, cnt * nb)
	_g_i = _inc_tb.i.slice(0, cnt * (ring.idx.size() + arw.idx.size()))
	_g_p = PackedVector2Array()
	_g_p.resize(cnt * nb)
	for t in cnt:
		var th: Dictionary = _threats[t]
		var p: Vector2 = th.p
		var r0 := 3.0 + minf(5.0, sqrt(float(th.n)) * 0.7)
		var b := t * nb
		for j in nr:
			_g_p[b + j] = p + ru[j] * (r0 + rk[j])
		# old: arrow from r + 1 to r + 9 towards the base, drawn while dist > r + 8 with r = r0 + 1.5 pulse
		var d := Vector2.RIGHT
		var m := 2
		if _base_mini.x >= 0.0:
			m = inc_arrow_m(p.distance_to(_base_mini), r0)
			if m != 2:
				d = (_base_mini - p).normalized()
		var a := p + d * (r0 + 1.0)
		var nn := Vector2(-d.y, d.x)
		var uv := Vector2(8.0 * m, 0.0) + d * 1.5
		for j in na:
			var q: Vector2 = au[j]
			_g_p[b + nr + j] = a + d * q.x + nn * q.y
			_g_uv[b + nr + j] = uv
	_g_n = cnt * nb
	_g_ni = _g_i.size()


## The old code drew a cluster's arrow while dist > r0 + 1.5 pulse + 8. Shader mode for that arrow: 0 = always,
## 2 + round(100 t) = while pulse < t, 2 = never (tests/test_perfdraw71 checks it against the old rule).
static func inc_arrow_m(dist: float, r0: float) -> int:
	var tq := (dist - r0 - 8.0) / 1.5
	if tq <= 0.0:
		return 2
	return 0 if tq >= 1.0 else 2 + int(round(tq * 100.0))


## One shape instance. Radial shapes: vertex = o + u * (r + k), UV = u * amp (+ m). Arrow: vertex = o + d * u.x + n * u.y.
func _inc_emit(tpl: Dictionary, o: Vector2, r: float, col: Color, amp: float, m: int, d := Vector2.RIGHT) -> void:
	var u: PackedVector2Array = tpl.u
	var k: PackedFloat32Array = tpl.k
	var a: PackedFloat32Array = tpl.a
	var idx: PackedInt32Array = tpl.idx
	var radial := bool(tpl.radial)
	var nv := u.size()
	var n0 := _g_n
	var i0 := _g_ni
	if n0 + nv > _g_p.size():
		var s := maxi(n0 + nv, _g_p.size() * 2)
		_g_p.resize(s)
		_g_c.resize(s)
		_g_uv.resize(s)
	if i0 + idx.size() > _g_i.size():
		_g_i.resize(maxi(i0 + idx.size(), _g_i.size() * 2))
	var ct := Color(col, 0.0)
	var uv0 := Vector2(8.0 * m, 0.0)
	var nn := Vector2(-d.y, d.x)
	for j in nv:
		var q: Vector2 = u[j]
		if radial:
			_g_p[n0 + j] = o + q * (r + k[j])
			_g_uv[n0 + j] = uv0 + q * amp
		else:
			_g_p[n0 + j] = o + d * q.x + nn * q.y
			_g_uv[n0 + j] = uv0 + d * amp
		_g_c[n0 + j] = col if a[j] > 0.5 else ct
	for j in idx.size():
		_g_i[i0 + j] = n0 + idx[j]
	_g_n = n0 + nv
	_g_ni = i0 + idx.size()


## Close the current geometry run as a layer.
func _inc_flush() -> void:
	if _g_n > 0:
		_g_p.resize(_g_n)
		_g_c.resize(_g_n)
		_g_uv.resize(_g_n)
		_g_i.resize(_g_ni)
		_inc_data.append({"geo": true, "p": _g_p, "c": _g_c, "uv": _g_uv, "i": _g_i})
	_g_p = PackedVector2Array()
	_g_c = PackedColorArray()
	_g_uv = PackedVector2Array()
	_g_i = PackedInt32Array()
	_g_n = 0
	_g_ni = 0


## A native call on a plain layer, after everything emitted so far.
func _inc_op(op: Array) -> void:
	_inc_flush()
	if _inc_data.is_empty() or bool(_inc_data[-1].geo):
		_inc_data.append({"geo": false, "ops": []})
	_inc_data[-1].ops.append(op)


func _inc_apply() -> void:
	while _inc_layers.size() < _inc_data.size():
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = Vector2(SIZE, SIZE)
		c.draw.connect(_inc_draw_layer.bind(_inc_layers.size()))
		_inc_root.add_child(c)
		_inc_layers.append(c)
	_inc_on = false
	for li in _inc_layers.size():
		var c: Control = _inc_layers[li]
		var used := li < _inc_data.size()
		c.visible = used
		if used:
			var geo := bool(_inc_data[li].geo)
			c.material = _inc_mat if geo else null
			_inc_on = _inc_on or geo
			c.queue_redraw()
	inc_layers_used = _inc_data.size()
	if _inc_on:
		_inc_mat.set_shader_parameter("pulse", _inc_pulse())


func _inc_draw_layer(li: int) -> void:
	if li >= _inc_data.size():
		return
	var L: Dictionary = _inc_data[li]
	var c: Control = _inc_layers[li]
	if bool(L.geo):
		RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), L.i, L.p, L.c, L.uv)
		return
	var font := ThemeDB.fallback_font
	for op in L.ops:
		if String(op[0]) == "str":
			c.draw_string(font, op[1], op[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, op[3])
		else:
			c.draw_dashed_line(op[1], op[2], op[3], 1.0, 4.0)


func _inc_shape(id: String) -> Dictionary:
	if not _inc_tpl.has(id):
		match id:
			"ring20w15":
				_inc_tpl[id] = _inc_tpl_ring(20, 1.5)
			"ring20w1":
				_inc_tpl[id] = _inc_tpl_ring(20, 1.0)
			"ring24w2":
				_inc_tpl[id] = _inc_tpl_ring(24, 2.0)
			"fan":
				_inc_tpl[id] = _inc_tpl_fan()
			_:
				_inc_tpl[id] = _inc_tpl_arrow()
	return _inc_tpl[id]


## draw_arc(c, r, 0, TAU, pts, col, w, true): an antialiased closed polyline through pts points (the last == the first):
## a core strip +-wc/2 (wc = _inc_aa_w(w)), then the left (outer) and right (inner) feathers, each offset along the corner bisector with the
## miter length 1 / cos(half the turn) of the regular (pts - 1)-gon.
func _inc_tpl_ring(pts: int, w: float) -> Dictionary:
	var u := PackedVector2Array()
	var k := PackedFloat32Array()
	var a := PackedFloat32Array()
	var idx := PackedInt32Array()
	var ml := 1.0 / cos(PI / float(pts - 1))
	var wc := _inc_aa_w(w)
	var e := ml * wc * 0.5
	var f := ml * INC_FEATHER * (wc if wc < 1.0 else 1.0)
	var strips := [[e, 1.0, -e, 1.0], [e + f, 0.0, e, 1.0], [-e, 1.0, -e - f, 0.0]]
	for st in strips:
		var base := u.size()
		for i in pts:
			var th := float(i) / float(pts - 1) * TAU
			var ui := Vector2(cos(th), sin(th))
			u.append(ui)
			k.append(st[0])
			a.append(st[1])
			u.append(ui)
			k.append(st[2])
			a.append(st[3])
		for i in pts - 1:
			var v := base + 2 * i
			idx.append_array(PackedInt32Array([v, v + 1, v + 2, v + 1, v + 2, v + 3]))
	return {"u": u, "k": k, "a": a, "idx": idx, "radial": true}


## Godot 4.7 canvas_item_get_compensated_antialiasing_width: an antialiased line / polyline of width w has a core of
## this width (then feathers of INC_FEATHER, times the core width when it is below 1).
func _inc_aa_w(w: float) -> float:
	if w <= INC_FEATHER * 2.0 + 0.00001:
		return w * 0.5
	if w <= INC_FEATHER * 4.0 + 0.00001:
		return remap(w, INC_FEATHER * 2.0, INC_FEATHER * 4.0, w * 0.5, w - INC_FEATHER * 0.5)
	return w - INC_FEATHER * 0.5


## draw_circle(c, r, col): a 64-segment fan (points 0..64 on the rim, the centre last).
func _inc_tpl_fan() -> Dictionary:
	var u := PackedVector2Array()
	var k := PackedFloat32Array()
	var a := PackedFloat32Array()
	var idx := PackedInt32Array()
	for i in 65:
		var th := float(i) * TAU / 64.0
		u.append(Vector2(cos(th), sin(th)))
		k.append(0.0)
		a.append(1.0)
	u.append(Vector2.ZERO)
	k.append(0.0)
	a.append(1.0)
	for i in 64:
		idx.append_array(PackedInt32Array([65, i, i + 1]))
	return {"u": u, "k": k, "a": a, "idx": idx, "radial": true}


## _arrow(a, a + 8 d): draw_line(a, b, col, 1.5, true) = core quad + edge and corner feather quads (each quad as
## triangles 0-1-2, 0-2-3), then draw_colored_polygon of the head. Coordinates: (along d, along n = (-d.y, d.x)).
func _inc_tpl_arrow() -> Dictionary:
	var u := PackedVector2Array()
	var k := PackedFloat32Array()
	var a := PackedFloat32Array()
	var idx := PackedInt32Array()
	var wc := _inc_aa_w(1.5)
	var h := wc * 0.5
	var f := INC_FEATHER * (wc if wc < 1.0 else 1.0)
	var L := 8.0
	var quads := [
		[[0.0, h, 1.0], [0.0, -h, 1.0], [L, -h, 1.0], [L, h, 1.0]],
		[[0.0, h, 1.0], [0.0, h + f, 0.0], [L, h + f, 0.0], [L, h, 1.0]],
		[[0.0, -h, 1.0], [0.0, -h - f, 0.0], [L, -h - f, 0.0], [L, -h, 1.0]],
		[[0.0, h, 1.0], [-f, h, 0.0], [-f, -h, 0.0], [0.0, -h, 1.0]],
		[[L, h, 1.0], [L + f, h, 0.0], [L + f, -h, 0.0], [L, -h, 1.0]],
		[[0.0, h, 1.0], [-f, h, 0.0], [-f, h + f, 0.0], [0.0, h + f, 0.0]],
		[[0.0, -h, 1.0], [-f, -h, 0.0], [-f, -h - f, 0.0], [0.0, -h - f, 0.0]],
		[[L, h, 1.0], [L + f, h, 0.0], [L + f, h + f, 0.0], [L, h + f, 0.0]],
		[[L, -h, 1.0], [L + f, -h, 0.0], [L + f, -h - f, 0.0], [L, -h - f, 0.0]],
	]
	for q in quads:
		var base := u.size()
		for v in q:
			u.append(Vector2(v[0], v[1]))
			k.append(0.0)
			a.append(v[2])
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var hb := u.size()
	for v in [[L + 3.0, 0.0], [L - 1.0, 3.0], [L - 1.0, -3.0]]:
		u.append(Vector2(v[0], v[1]))
		k.append(0.0)
		a.append(1.0)
	idx.append_array(PackedInt32Array([hb, hb + 1, hb + 2]))
	return {"u": u, "k": k, "a": a, "idx": idx, "radial": false}
