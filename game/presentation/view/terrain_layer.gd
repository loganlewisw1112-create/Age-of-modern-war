extends Node2D
## Terrain renderer (owner: R4-render, G3b; was agent D). Bakes the iso map into 16x16-cell chunk
## textures (Image.blend_rect of ArtCatalog.terrain_texture tiles, or flat-colour fallback
## diamonds while art is a placeholder). One Sprite2D per chunk, so terrain costs nothing per
## frame once baked.
##  - Small maps (<= EAGER_MAX chunks, e.g. 96x96 = 36): every chunk is baked at match start
##    (the original behaviour and look).
##  - Large maps (160x160, 256x256): a low-res base (one texel per cell, iso-transformed) is drawn
##    at once; chunks near the view are baked on WorkerThreadPool threads (no frame hitch) and
##    the least recently seen are evicted past CHUNK_CAP. At far zoom only the base is shown.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const CHUNK := 16
const EAGER_MAX := 64
const CHUNK_CAP := 56
const MAX_PENDING := 3
const FAR_ZOOM := 0.45
const MAX_CODE := 16

var mv
var bake_ms := 0
var lazy := false
var rebakes := 0                   # chunks re-baked after terrain changes (G2 bridge)
var baked_total := 0
var _tile_cache: Dictionary = {}   # "code_variant" -> Image (RGBA8); filled on the main thread
var _variants: PackedInt32Array = PackedInt32Array()
var _chunks: Dictionary = {}       # Vector2i chunk origin -> Sprite2D
var _seen: Dictionary = {}         # Vector2i -> frame last in view
var _pending: Dictionary = {}      # Vector2i -> WorkerThreadPool task id
var _results: Dictionary = {}      # Vector2i -> Image (written by workers under _mutex)
var _mutex := Mutex.new()
var _max_h := 32
var _frame := 0
var _base_img: Image
var _base_tex: ImageTexture
var _show_base := false


func setup(view: Node2D) -> void:
	mv = view
	var t0 := Time.get_ticks_msec()
	_prefill()
	var w := int(mv.world.map.w)
	var h := int(mv.world.map.h)
	var n := ((w + CHUNK - 1) / CHUNK) * ((h + CHUNK - 1) / CHUNK)
	lazy = n > EAGER_MAX
	if lazy:
		_build_base()
		_show_base = true
	else:
		for cy0 in range(0, h, CHUNK):
			for cx0 in range(0, w, CHUNK):
				_install(Vector2i(cx0, cy0), _bake_image(cx0, cy0, mv.world.map.terrain))
	bake_ms = Time.get_ticks_msec() - t0
	print("TERRAIN %s %d chunks (%dx%d) in %d ms" % ["lazy base +" if lazy else "baked", get_child_count(), w, h, bake_ms])


func _exit_tree() -> void:
	for k in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[k])
	_pending.clear()


func _draw() -> void:
	# dark backdrop around the map diamond
	draw_rect(Rect2(Vector2(-16000, -8000), Vector2(32000, 24000)), Color(0.03, 0.035, 0.04))
	if _show_base and _base_tex != null:
		draw_set_transform_matrix(Transform2D(Vector2(32, 16), Vector2(-32, 16), Vector2.ZERO))
		draw_texture_rect(_base_tex, Rect2(Vector2.ZERO, Vector2(_base_img.get_size())), false)
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _tile_image(code: int, variant: int) -> Image:
	var key := "%d_%d" % [code, variant]
	if _tile_cache.has(key):
		return _tile_cache[key]
	var img: Image = null
	var tex: Texture2D = ArtCatalog.terrain_texture(code, variant)
	if not ViewUtil.is_placeholder(tex) and tex.get_width() >= 32:
		img = tex.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			if img.get_width() != 64:
				img.resize(64, int(round(img.get_height() * 64.0 / img.get_width())), Image.INTERPOLATE_NEAREST)
		else:
			img = null
	if img == null:
		img = ViewUtil.terrain_tile_image(code, variant)
	_tile_cache[key] = img
	return img


## Main thread: every tile image the workers may need, so they only ever read _tile_cache.
func _prefill() -> void:
	_variants.resize(MAX_CODE)
	_max_h = 32
	for code in MAX_CODE:
		var nv := maxi(1, int(ArtCatalog.terrain_variants(code)))
		_variants[code] = nv
		for v in nv:
			_max_h = maxi(_max_h, _tile_image(code, v).get_height())


func _variant_for(code: int, x: int, y: int) -> int:
	var n: int = _variants[code] if code < MAX_CODE else 1
	if n <= 1:
		return 0
	var h := (x * 73856093) ^ (y * 19349663) ^ (code * 83492791)
	return absi(h) % n


## Pure function of (chunk, terrain): safe on a worker thread.
func _bake_image(cx0: int, cy0: int, terrain: PackedByteArray) -> Image:
	var w := int(mv.world.map.w)
	var h := int(mv.world.map.h)
	var img_w := CHUNK * 64
	var img_h := (CHUNK - 1) * 32 + _max_h
	var img := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# back-to-front so skirts are overdrawn by nearer tiles
	for s in range(0, 2 * CHUNK - 1):
		for i in range(maxi(0, s - CHUNK + 1), mini(CHUNK, s + 1)):
			var j := s - i
			var x := cx0 + i
			var y := cy0 + j
			if x >= w or y >= h:
				continue
			var code := mini(int(terrain[y * w + x]), MAX_CODE - 1)
			var tile: Image = _tile_cache.get("%d_%d" % [code, _variant_for(code, x, y)], _tile_cache["0_0"])
			var dst := Vector2i(img_w / 2 + (i - j) * 32 - 32, (i + j) * 16)
			img.blend_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), dst)
	return img


func _worker(key: Vector2i, terrain: PackedByteArray) -> void:
	var img := _bake_image(key.x, key.y, terrain)
	_mutex.lock()
	_results[key] = img
	_mutex.unlock()


func _install(key: Vector2i, img: Image) -> void:
	var spr: Sprite2D = _chunks.get(key)
	if spr == null:
		spr = Sprite2D.new()
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.position = mv.world_to_screen(Vector2(key)) + Vector2(-CHUNK * 32, 0)
		add_child(spr)
		_chunks[key] = spr
	spr.texture = ImageTexture.create_from_image(img)
	baked_total += 1


## G2: re-bake only the chunks containing `cells` (bridge destroyed/repaired changes the
## terrain array). Cells may be Vector2i or Vector2.
func rebake_cells(cells: Array) -> void:
	var done := {}
	for c in cells:
		var key := Vector2i((int(c.x) / CHUNK) * CHUNK, (int(c.y) / CHUNK) * CHUNK)
		if lazy:
			_base_cell(int(c.x), int(c.y))
		if done.has(key):
			continue
		done[key] = true
		if not lazy or _chunks.has(key):
			_install(key, _bake_image(key.x, key.y, mv.world.map.terrain))
	if lazy and _base_tex != null:
		_base_tex.update(_base_img)
	rebakes += done.size()


func _build_base() -> void:
	var w := int(mv.world.map.w)
	var h := int(mv.world.map.h)
	_base_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			_base_cell(x, y)
	_base_tex = ImageTexture.create_from_image(_base_img)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


var _avg: Dictionary = {}

func _base_cell(x: int, y: int) -> void:
	var code := mini(int(mv.world.map.terrain[y * int(mv.world.map.w) + x]), MAX_CODE - 1)
	var c = _avg.get(code)
	if c == null:
		var t: Image = _tile_cache.get("%d_0" % code, _tile_cache["0_0"])
		c = t.get_pixel(32, 16)  # diamond centre: representative tile colour
		_avg[code] = c
	_base_img.set_pixel(x, y, c)


## Per frame (MatchView._process): lazy maps bake chunks near the view on worker threads.
func tick() -> void:
	if not lazy:
		return
	_frame += 1
	_mutex.lock()
	var ready: Dictionary = _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for key in ready:
		if _pending.has(key):
			WorkerThreadPool.wait_for_task_completion(_pending[key])
			_pending.erase(key)
		_install(key, ready[key])
	var z: float = mv.camera.zoom.x
	var far := z < FAR_ZOOM
	for key in _chunks:
		(_chunks[key] as Sprite2D).visible = not far
	if far:
		return
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var vs: Vector2 = get_viewport_rect().size
	var corners := [inv * Vector2.ZERO, inv * Vector2(vs.x, 0), inv * vs, inv * Vector2(0, vs.y)]
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for sp in corners:
		var wp: Vector2 = mv.screen_to_world(sp)
		lo = Vector2i(mini(lo.x, floori(wp.x)), mini(lo.y, floori(wp.y)))
		hi = Vector2i(maxi(hi.x, ceili(wp.x)), maxi(hi.y, ceili(wp.y)))
	var w := int(mv.world.map.w)
	var h := int(mv.world.map.h)
	var want: Array = []
	for cy0 in range(maxi(0, (lo.y - 2) / CHUNK) * CHUNK, mini(h, hi.y + 2), CHUNK):
		for cx0 in range(maxi(0, (lo.x - 2) / CHUNK) * CHUNK, mini(w, hi.x + 2), CHUNK):
			var key := Vector2i(cx0, cy0)
			_seen[key] = _frame
			if not _chunks.has(key) and not _pending.has(key):
				want.append(key)
	for key in want:
		if _pending.size() >= MAX_PENDING:
			break
		_pending[key] = WorkerThreadPool.add_task(_worker.bind(key, mv.world.map.terrain), false, "terrain chunk")
	if _chunks.size() > CHUNK_CAP:
		_evict()


func _evict() -> void:
	var keys: Array = _chunks.keys()
	keys.sort_custom(func(a, b): return int(_seen.get(a, 0)) < int(_seen.get(b, 0)))
	var i := 0
	while _chunks.size() > CHUNK_CAP and i < keys.size():
		var k = keys[i]
		i += 1
		if int(_seen.get(k, 0)) >= _frame:
			break
		_chunks[k].queue_free()
		_chunks.erase(k)
