extends Node2D
## Terrain renderer (owner: agent D). Bakes the 96x96 iso map into 16x16-cell chunk textures
## once at match start (Image.blend_rect from ArtCatalog.terrain_texture, or flat-colour
## fallback diamonds when the art is still a placeholder). One Sprite2D per chunk.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const CHUNK := 16

var mv
var bake_ms := 0
var _tile_cache: Dictionary = {}   # "code_variant" -> Image (RGBA8)
var _chunks: Dictionary = {}       # Vector2i chunk origin -> Sprite2D
var _max_h := 32
var rebakes := 0                   # chunks re-baked after terrain changes (G2 bridge)


func setup(view: Node2D) -> void:
	mv = view
	var t0 := Time.get_ticks_msec()
	_bake()
	bake_ms = Time.get_ticks_msec() - t0
	print("TERRAIN baked %d chunks in %d ms" % [get_child_count(), bake_ms])


func _draw() -> void:
	# dark backdrop around the map diamond
	draw_rect(Rect2(Vector2(-8000, -4000), Vector2(16000, 12000)), Color(0.03, 0.035, 0.04))


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


func _variant_for(code: int, x: int, y: int) -> int:
	var n := maxi(1, int(ArtCatalog.terrain_variants(code)))
	if n <= 1:
		return 0
	var h := (x * 73856093) ^ (y * 19349663) ^ (code * 83492791)
	return absi(h) % n


func _bake() -> void:
	var w := int(mv.world.map.w)
	var h := int(mv.world.map.h)
	# max tile image height (diamond + skirt) across codes in use
	_max_h = 32
	for code in 8:
		for v in maxi(1, int(ArtCatalog.terrain_variants(code))):
			_max_h = maxi(_max_h, _tile_image(code, v).get_height())
	for cy0 in range(0, h, CHUNK):
		for cx0 in range(0, w, CHUNK):
			_bake_chunk(cx0, cy0)


## G2: re-bake only the chunks containing `cells` (bridge destroyed/repaired changes the
## terrain array). Cells may be Vector2i or Vector2.
func rebake_cells(cells: Array) -> void:
	var done := {}
	for c in cells:
		var cx0 := (int(c.x) / CHUNK) * CHUNK
		var cy0 := (int(c.y) / CHUNK) * CHUNK
		var key := Vector2i(cx0, cy0)
		if done.has(key):
			continue
		done[key] = true
		_bake_chunk(cx0, cy0)
	rebakes += done.size()


func _bake_chunk(cx0: int, cy0: int) -> void:
	var w := int(mv.world.map.w)
	var h := int(mv.world.map.h)
	var terrain: PackedByteArray = mv.world.map.terrain
	var img_w := CHUNK * 64
	var img_h := (CHUNK - 1) * 32 + _max_h
	var img := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var any := false
	# back-to-front so skirts are overdrawn by nearer tiles
	for s in range(0, 2 * CHUNK - 1):
		for i in range(maxi(0, s - CHUNK + 1), mini(CHUNK, s + 1)):
			var j := s - i
			var x := cx0 + i
			var y := cy0 + j
			if x >= w or y >= h:
				continue
			var code := int(terrain[y * w + x])
			var tile := _tile_image(code, _variant_for(code, x, y))
			var dst := Vector2i(img_w / 2 + (i - j) * 32 - 32, (i + j) * 16)
			img.blend_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), dst)
			any = true
	if not any:
		return
	var key := Vector2i(cx0, cy0)
	var spr: Sprite2D = _chunks.get(key)
	if spr == null:
		spr = Sprite2D.new()
		spr.centered = false
		spr.position = mv.world_to_screen(Vector2(cx0, cy0)) + Vector2(-img_w / 2, 0)
		add_child(spr)
		_chunks[key] = spr
	spr.texture = ImageTexture.create_from_image(img)
