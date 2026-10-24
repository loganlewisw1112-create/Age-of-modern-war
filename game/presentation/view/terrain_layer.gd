extends Node2D
## Terrain renderer (owner: ART-T, G4; was R4-render / agent D). Bakes the iso map into 16x16-cell
## chunk textures (Image.blend_rect of ArtCatalog.terrain_texture tiles, or flat-colour fallback
## diamonds while art is a placeholder). One Sprite2D per chunk, so terrain costs nothing per
## frame once baked.
##  - Small maps (<= EAGER_MAX chunks, e.g. 96x96 = 36): every chunk is baked at match start.
##  - Large maps (160x160, 256x256): a low-res base (one texel per cell, iso-transformed) is drawn
##    at once; chunks near the view are baked on WorkerThreadPool threads (no frame hitch) and
##    the least recently seen are evicted past CHUNK_CAP. At far zoom only the base is shown.
## G4 (CONTRACTS_G4 s2.2, manifest "terrain_g4" written by tools/art/g4_terrain.gd):
##  - codes 8-13; raised codes (CLIFF, HILL) are lifted by their `raise` (chunk images get a top
##    margin `pad` for them, and chunk sprites stay in back-to-front order);
##  - map.biome (optional PackedByteArray, 0 temperate 1 desert 2 snow 3 wasteland) picks the
##    biome tile when one exists, else the temperate one;
##  - transitions: per rule, a 4-edge + 4-corner neighbour bitmask overlay (shore foam, deep shelf,
##    wet sand, beach sand, cliff scree, crest rim) blended after the cell's tile;
##  - rebake_cells(cells) re-bakes the chunks of the cells and of their 8 neighbours (editor
##    brushes, fire, bridges); rebuild() re-does everything (new map / size).
## Codes 0-7 on a map without biome or G4 codes bake exactly as before (River Crossing identical).

const ViewUtil = preload("res://presentation/view/view_util.gd")
const CHUNK := 16
const EAGER_MAX := 64
const CHUNK_CAP := 56
const MAX_PENDING := 3
const FAR_ZOOM := 0.45
const MAX_CODE := 16
const NBR := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
const CORNER_EDGES := [9, 3, 6, 12]   # NW: N|W, NE: N|E, SE: E|S, SW: S|W

var mv
var bake_ms := 0
var lazy := false
var rebakes := 0                   # chunks re-baked after terrain changes (G2 bridge, G4 editor)
var baked_total := 0
var pad := 0                       # G4: top margin of every chunk image (largest tile raise)
var _tile_cache: Dictionary = {}   # "code_variant[_bB]" -> Image (RGBA8); filled on the main thread
var _variants: PackedInt32Array = PackedInt32Array()
var _raise: PackedInt32Array = PackedInt32Array()
var _bvar: Dictionary = {}         # code * 4 + biome -> loaded biome variants
var _biomes_loaded := false
var _rules: Array = []             # {kind, recv, from: PackedByteArray flags, img: [biome] -> [edge[16], corner[16]]}
var _recv: PackedByteArray = PackedByteArray()
var _masks: Dictionary = {}        # art -> [edge[16], corner[16]] (mask atlases, for per-biome composites)
var _w := 0
var _h := 0
var _below := 32
var _chunks: Dictionary = {}       # Vector2i chunk origin -> Sprite2D
var _seen: Dictionary = {}         # Vector2i -> frame last in view
var _pending: Dictionary = {}      # Vector2i -> WorkerThreadPool task id
var _results: Dictionary = {}      # Vector2i -> Image (written by workers under _mutex)
var _mutex := Mutex.new()
var _frame := 0
var _base_img: Image
var _base_tex: ImageTexture
var _show_base := false
var _avg: Dictionary = {}


func setup(view: Node2D) -> void:
	mv = view
	var t0 := Time.get_ticks_msec()
	_w = int(mv.world.map.w)
	_h = int(mv.world.map.h)
	_prefill()
	var biome := _biome_arr()
	if _any_biome(biome):
		_load_biomes()
	var n := ((_w + CHUNK - 1) / CHUNK) * ((_h + CHUNK - 1) / CHUNK)
	lazy = n > EAGER_MAX
	if lazy:
		_build_base()
		_show_base = true
	else:
		for cy0 in range(0, _h, CHUNK):
			for cx0 in range(0, _w, CHUNK):
				_install(Vector2i(cx0, cy0), _bake_image(cx0, cy0, mv.world.map.terrain, biome))
	bake_ms = Time.get_ticks_msec() - t0
	print("TERRAIN %s %d chunks (%dx%d) in %d ms" % ["lazy base +" if lazy else "baked", _chunks.size(), _w, _h, bake_ms])


## G4 editor: the map was replaced or resized; drop every chunk and bake again.
func rebuild() -> void:
	_exit_tree()
	_results.clear()
	for k in _chunks:
		(_chunks[k] as Node).queue_free()
	_chunks.clear()
	_seen.clear()
	_avg.clear()
	_base_img = null
	_base_tex = null
	_show_base = false
	setup(mv)
	queue_redraw()


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
	var g4: Dictionary = ArtCatalog.manifest().get("terrain_g4", {})
	var anim: Dictionary = g4.get("anim", {})
	var rz: Dictionary = g4.get("raise", {})
	_variants.resize(MAX_CODE)
	_raise.resize(MAX_CODE)
	_raise.fill(0)
	_below = 32
	pad = 0
	for code in MAX_CODE:
		var nv := maxi(1, int(ArtCatalog.terrain_variants(code)))
		if anim.has(str(code)):
			nv = 1  # animation phases: a static bake uses phase 0 (lattice-periodic, seamless)
		_variants[code] = nv
		var r := int(rz.get(str(code), 0))
		if r > 0 and _tile_image(code, 0).get_height() == 32 + r:
			_raise[code] = r
		pad = maxi(pad, _raise[code])
		for v in nv:
			_below = maxi(_below, _tile_image(code, v).get_height() - _raise[code])
	_load_rules(g4)


func _variant_for(code: int, x: int, y: int) -> int:
	var n: int = _variants[code] if code < MAX_CODE else 1
	if n <= 1:
		return 0
	var h := (x * 73856093) ^ (y * 19349663) ^ (code * 83492791)
	return absi(h) % n


func _tile_for(code: int, b: int, x: int, y: int) -> Image:
	if b > 0:
		var n: int = _bvar.get(code * 4 + b, 0)
		if n > 0:
			var hh := (x * 73856093) ^ (y * 19349663) ^ (code * 83492791)
			var t = _tile_cache.get("%d_%d_b%d" % [code, absi(hh) % n, b])
			if t != null:
				return t
	return _tile_cache.get("%d_%d" % [code, _variant_for(code, x, y)], _tile_cache["0_0"])


## Transition rules + overlay atlases from the manifest (missing art: no rule, old look).
func _load_rules(g4: Dictionary) -> void:
	_rules.clear()
	_masks.clear()
	_recv.resize(MAX_CODE)
	_recv.fill(0)
	var trans: Dictionary = g4.get("trans", {})
	for r in g4.get("rules", []):
		var art := String(r.get("art", r.get("kind", "")))
		var atlas: Image = ArtCatalog._image(String(trans.get(art, ""))) if trans.has(art) else null
		if atlas == null or atlas.get_size() != Vector2i(1024, 64):
			continue
		var rows := [[], []]
		for row in 2:
			for m in 16:
				rows[row].append(atlas.get_region(Rect2i(m * 64, row * 32, 64, 32)))
		var rule := {"kind": String(r.get("kind", art)), "src": int(r.get("src", -1)),
			"recv": _flags(r.get("recv", [])), "from": _flags(r.get("from", [])), "img": [null, null, null, null]}
		if rule.src >= 0:
			_masks[rule.kind] = rows
			rule.img[0] = _cut(rows, rule.src, 0)
		else:
			rule.img = [rows, rows, rows, rows]
		_rules.append(rule)
		for c in r.get("recv", []):
			if int(c) < MAX_CODE:
				_recv[int(c)] = 1


func _flags(codes: Array) -> PackedByteArray:
	var f := PackedByteArray()
	f.resize(MAX_CODE)
	f.fill(0)
	for c in codes:
		if int(c) >= 0 and int(c) < MAX_CODE:
			f[int(c)] = 1
	return f


## Masked transition: the source code's tile (biome b) cut through the mask atlas.
func _cut(rows: Array, src: int, b: int) -> Array:
	var tile: Image = _tile_for(src, b, 0, 0)
	var out := [[], []]
	for row in 2:
		for m in 16:
			var o := Image.create(64, 32, false, Image.FORMAT_RGBA8)
			o.fill(Color(0, 0, 0, 0))
			var mask: Image = rows[row][m]
			if tile.get_size() == Vector2i(64, 32):
				o.blit_rect_mask(tile, mask, Rect2i(0, 0, 64, 32), Vector2i.ZERO)
			out[row].append(o)
	return out


## Main thread, once: desert/snow/wasteland tiles (only when the map uses a biome).
func _load_biomes() -> void:
	if _biomes_loaded:
		return
	_exit_tree()  # no worker may be reading the caches while they grow
	_biomes_loaded = true
	var man := ArtCatalog.manifest()
	var g4: Dictionary = man.get("terrain_g4", {})
	var terr: Dictionary = man.get("terrain", {})
	var anim: Dictionary = g4.get("anim", {})
	var bv: Dictionary = g4.get("biome_variants", {})
	for cs in bv:
		var code := int(cs)
		if code >= MAX_CODE or not terr.has(cs):
			continue
		var n := 1 if anim.has(cs) else int(bv[cs])
		for b in range(1, 4):
			var got := 0
			for v in n:
				var img := ArtCatalog._image("terrain/%s_b%d_%d.png" % [String(terr[cs].name), b, v])
				if img == null or img.get_width() != 64 or img.get_height() != 32 + _raise[code]:
					break
				_tile_cache["%d_%d_b%d" % [code, v, b]] = img
				got += 1
			_bvar[code * 4 + b] = got
	for rule in _rules:
		if int(rule.src) >= 0:
			for b in range(1, 4):
				rule.img[b] = _cut(_masks[rule.kind], int(rule.src), b)


func _biome_arr() -> PackedByteArray:
	var s := _busy_snap()
	var b = s.get("biome") if not s.is_empty() else null
	if s.is_empty():
		var m = mv.world.map
		b = m.get("biome") if m is Dictionary else null
	if b is PackedByteArray and b.size() == _w * _h:
		return b
	return PackedByteArray()


## G4 THREAD: while a sim step is in flight, read the terrain/biome refs from the last render
## snapshot (copy-on-write, same data as of the last join) instead of mv.world, which would join
## the step and stall the frame. Idle (or editor / probe views without a sim): read the map.
func _busy_snap() -> Dictionary:
	if mv.has_method("sim_busy") and mv.sim_busy():
		var s = mv.get("snap")
		if s is Dictionary and s.get("terrain") is PackedByteArray and (s.terrain as PackedByteArray).size() == _w * _h:
			return s
	return {}


func _terrain() -> PackedByteArray:
	var s := _busy_snap()
	if not s.is_empty():
		return s.terrain
	return mv.world.map.terrain


func _any_biome(b: PackedByteArray) -> bool:
	for v in b:
		if v != 0:
			return true
	return false


## Pure function of (chunk, terrain, biome): safe on a worker thread.
func _bake_image(cx0: int, cy0: int, terrain: PackedByteArray, biome: PackedByteArray = PackedByteArray()) -> Image:
	var w := _w
	var h := _h
	var img_w := CHUNK * 64
	var img_h := pad + (CHUNK - 1) * 32 + _below
	var img := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var has_b := biome.size() == w * h
	# back-to-front so raised tiles overdraw the cells behind them
	for s in range(0, 2 * CHUNK - 1):
		for i in range(maxi(0, s - CHUNK + 1), mini(CHUNK, s + 1)):
			var j := s - i
			var x := cx0 + i
			var y := cy0 + j
			if x >= w or y >= h:
				continue
			var code := mini(int(terrain[y * w + x]), MAX_CODE - 1)
			var b := mini(int(biome[y * w + x]), 3) if has_b else 0
			var tile: Image = _tile_for(code, b, x, y)
			var dst := Vector2i(img_w / 2 + (i - j) * 32 - 32, (i + j) * 16 + pad - _raise[code])
			img.blend_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), dst)
			if _recv[code] == 1:
				_overlays(img, terrain, x, y, code, b, dst)
	return img


func _code_at(terrain: PackedByteArray, x: int, y: int, own: int) -> int:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return own  # no transition against the map edge
	return mini(int(terrain[y * _w + x]), MAX_CODE - 1)


func _overlays(img: Image, terrain: PackedByteArray, x: int, y: int, code: int, b: int, dst: Vector2i) -> void:
	var nb := PackedInt32Array()
	nb.resize(8)
	for k in 8:
		nb[k] = _code_at(terrain, x + NBR[k].x, y + NBR[k].y, code)
	for rule in _rules:
		if rule.recv[code] == 0:
			continue
		var from: PackedByteArray = rule.from
		var em := 0
		for k in 4:
			if from[nb[k]] == 1:
				em |= 1 << k
		var cm := 0
		for k in 4:
			if from[nb[4 + k]] == 1 and (em & CORNER_EDGES[k]) == 0:
				cm |= 1 << k
		if em == 0 and cm == 0:
			continue
		var ov: Array = rule.img[b] if rule.img[b] != null else rule.img[0]
		if em != 0:
			img.blend_rect(ov[0][em], Rect2i(0, 0, 64, 32), dst)
		if cm != 0:
			img.blend_rect(ov[1][cm], Rect2i(0, 0, 64, 32), dst)


func _worker(key: Vector2i, terrain: PackedByteArray, biome: PackedByteArray) -> void:
	var img := _bake_image(key.x, key.y, terrain, biome)
	_mutex.lock()
	_results[key] = img
	_mutex.unlock()


func _install(key: Vector2i, img: Image) -> void:
	var spr: Sprite2D = _chunks.get(key)
	if spr == null:
		spr = Sprite2D.new()
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.position = mv.world_to_screen(Vector2(key)) + Vector2(-CHUNK * 32, -pad)
		spr.set_meta("k", key)
		add_child(spr)
		_order(spr, key)
		_chunks[key] = spr
	spr.texture = ImageTexture.create_from_image(img)
	baked_total += 1


## Chunk sprites stay in row-major (back-to-front) order so a raised tile's overhang into the
## chunk behind it is drawn on top of that chunk.
func _order(spr: Sprite2D, key: Vector2i) -> void:
	var i := 0
	for ch in get_children():
		if ch != spr and ch.has_meta("k"):
			var k: Vector2i = ch.get_meta("k")
			if k.y > key.y or (k.y == key.y and k.x > key.x):
				move_child(spr, i)
				return
		i += 1


## Re-bake the chunks holding `cells` and their 8 neighbours (transitions and raised overhangs
## reach one cell out). Cells may be Vector2i or Vector2. Used by the G2 bridge, G4 editor
## brushes (terrain or map.biome edits) and fire (FOREST -> DIRT).
func rebake_cells(cells: Array) -> void:
	var biome := _biome_arr()
	var terrain := _terrain()
	if not _biomes_loaded and _any_biome(biome):
		_load_biomes()
	var done := {}
	for c in cells:
		var cx := int(c.x)
		var cy := int(c.y)
		if cx < 0 or cy < 0 or cx >= _w or cy >= _h:
			continue
		if lazy and _base_img != null:
			_base_cell(cx, cy, biome, terrain)
		for k in 9:
			var nx := cx + k % 3 - 1
			var ny := cy + k / 3 - 1
			if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
				continue
			done[Vector2i((nx / CHUNK) * CHUNK, (ny / CHUNK) * CHUNK)] = true
	var keys: Array = done.keys()
	keys.sort()
	for key in keys:
		if not lazy or _chunks.has(key):
			_install(key, _bake_image(key.x, key.y, terrain, biome))
	if lazy and _base_tex != null:
		_base_tex.update(_base_img)
	rebakes += keys.size()


func _build_base() -> void:
	var biome := _biome_arr()
	var terrain := _terrain()
	_base_img = Image.create(_w, _h, false, Image.FORMAT_RGBA8)
	for y in _h:
		for x in _w:
			_base_cell(x, y, biome, terrain)
	_base_tex = ImageTexture.create_from_image(_base_img)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _base_cell(x: int, y: int, biome: PackedByteArray, terrain: PackedByteArray) -> void:
	var code := mini(int(terrain[y * _w + x]), MAX_CODE - 1)
	var b := mini(int(biome[y * _w + x]), 3) if biome.size() == _w * _h else 0
	var c = _avg.get(code * 4 + b)
	if c == null:
		var t: Image = _tile_for(code, b, 0, 0) if b > 0 else _tile_cache.get("%d_0" % code, _tile_cache["0_0"])
		c = t.get_pixel(32, 16)  # diamond centre (top face of a raised tile): representative colour
		_avg[code * 4 + b] = c
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
	var want: Array = []
	for cy0 in range(maxi(0, (lo.y - 2) / CHUNK) * CHUNK, mini(_h, hi.y + 2), CHUNK):
		for cx0 in range(maxi(0, (lo.x - 2) / CHUNK) * CHUNK, mini(_w, hi.x + 2), CHUNK):
			var key := Vector2i(cx0, cy0)
			_seen[key] = _frame
			if not _chunks.has(key) and not _pending.has(key):
				want.append(key)
	var biome := _biome_arr()
	for key in want:
		if _pending.size() >= MAX_PENDING:
			break
		_pending[key] = WorkerThreadPool.add_task(_worker.bind(key, _terrain(), biome), false, "terrain chunk")
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
