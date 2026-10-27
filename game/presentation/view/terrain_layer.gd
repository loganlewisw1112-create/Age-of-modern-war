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
## G6 (ELEV-VIEW, CONTRACTS_G6 s7, PLAN_G6 A1): true elevation, cached per chunk (nothing per frame).
##  - A map with a height layer (map.height / map.ramps, ViewUtil.height_map_of) still bakes the flat chunk
##    image as above (plus ramp treads, cliff scree on the low side, crest rims on the high side, and the face
##    atlas copied under it), but each chunk is drawn as a MeshInstance2D: one quad per cell whose vertices are
##    lifted ViewUtil.lift_px(level) px (ViewUtil.level_px per level above plain; ramps slope per ViewUtil.vtx), plus face
##    quads under every front edge that drops (SW face lit, SE face dark, darker at the foot), textured from
##    assets/art/g6_terrain faces.png in the cliff style of the top tile (earth / rock / sand / wall) and biome.
##    Quads go back-to-front (x + y diagonals) with each cell's faces right after it, and chunks stay row-major,
##    so higher tiles overdraw what is behind them and lower ones show the faces above them.
##  - Vertex colours tint each level (valley darker, ridge brighter) and shade slopes; the far-zoom base image
##    gets the same level tint and darkens cells over a front cliff edge.
##  - RAIL (code 14): ballast tile per biome + rails/sleepers towards connected rail neighbours (any map).
##  - Maps without height bake and draw exactly as before (Sprite2D chunks).

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
var g5_rules := 0                  # G5 (VIEW5-2): terrain_g5 transition rules loaded (surf, cliff_wet)
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

# G6 terrain height (ELEV-VIEW)
const LEVEL_TINT := [0.6, 1.0, 1.26, 1.52]    # top-surface brightness per level (grey; far-zoom fallback)
## G6 owner pass: per biome (0 temperate 1 desert 2 snow 3 wasteland), per level (0 valley .. 3 ridge) RGB
## multiplier of the top surface: valleys darker and cooler, high ground lighter and warmer. Snow (already near
## white) gets a deep blue valley and a cream ridge instead of more white; desert a tan lift that does not clip.
const LEVEL_TINT_B := [
	[Color(0.56, 0.62, 0.76), Color(1, 1, 1), Color(1.3, 1.24, 1.06), Color(1.62, 1.48, 1.12)],
	[Color(0.6, 0.6, 0.72), Color(1, 1, 1), Color(1.18, 1.12, 1.0), Color(1.36, 1.24, 1.02)],
	[Color(0.5, 0.58, 0.8), Color(0.94, 0.96, 1.0), Color(1.06, 1.03, 0.95), Color(1.14, 1.07, 0.9)],
	[Color(0.56, 0.58, 0.68), Color(1, 1, 1), Color(1.26, 1.2, 1.04), Color(1.55, 1.4, 1.1)]]
const SLOPE_X := 0.34                         # ramp shading per level of rise towards +x (faces the light)
const SLOPE_Y := -0.2                         # ... towards +y
const BRIGHT := 1.8                           # height-chunk shader scales vertex colours by this (tints > 1)
const FACE_H := 96                            # rows of the face atlas under every height chunk image
const FACE_TOP := [1.3, 0.5]                  # SW (lit wall) / SE (shadow side) face brightness at the lip
const FACE_FOOT := 0.56                       # times that at the foot (ambient occlusion at the base)
## Baked cliff shadows (cached chunk images, nothing per frame). The light comes from -x / +y (screen left: the
## SW faces are lit), so a cliff casts its shadow onto the lower ground towards +x / -y: at the foot of every SE
## (shadow-side) face, SH_LEN cells per level of drop, soft edged; plus an ambient-occlusion band along the base
## of every cliff on the low cell.
const SH_LEN := 0.7
const SH_A := 0.55
const SH_SOFT := 0.16
const SH_COL := Color(0.04, 0.05, 0.12)
const AO_A := 0.42
const AO_W := 0.3
static var _sh_tab: Array = []      # (lw * 5 + ls) -> 64x32 shadow overlay (lw / ls quarters of a cell from W / S edge)
static var _sh_diag: Array = []     # ld (1..4) -> corner shadow from the SW diagonal only
static var _ao_tab: Array = []      # 4-bit N E S W cliff-base mask -> 64x32 AO overlay
## The one height constant, mirrored for layers that read it off the terrain layer (VIEW6 entity_layer fallback).
var level_px: float:
	get:
		return ViewUtil.level_px
const STYLE_OF_CODE := [0, 0, 3, 0, 1, 3, 1, 1, 3, 1, 1, 2, 1, 0, 3, 0]  # earth rock sand wall
const G6_DIR := "res://assets/art/g6_terrain/"
const HSHADER := """
shader_type canvas_item;
uniform float bright = 1.25;
// Godot 4: COLOR in fragment() already is vertex colour x TEXTURE (sampling TEXTURE again squared the texture,
// which darkened every height map); only the tint headroom is applied here.
void fragment() {
	COLOR = vec4(COLOR.rgb * bright, COLOR.a);
}
"""
var hmap: Dictionary = {}          # {w, h, height, ramps} of the drawn map; empty = flat map (G5 path)
var height_ver := 0                # bumped whenever the height layer is (re)read; fog_layer re-uploads
var g6_art := false                # assets/art/g6_terrain loaded (else procedural face fallback)
var meshes_built := 0
var _faces_img: Image
var _ramp_ov: Array = []           # biome * 4 + rise dir (N E S W) -> 64x32 overlay (null = none)
var _hscree: Array = []            # biome -> [edge[16], corner[16]] or []
var _hrim: Array = []              # [edge[16], corner[16]] or []
var _rail_tracks: Array = []       # 4-bit neighbour mask -> 64x32 overlay
var _hmat: ShaderMaterial
## G6 (VIEW6 CR 712): screen lift (px) of the drawn ground at every cell centre, index y * w + x: exactly the mesh
## height there, (level - 1) * level_px on plain cells and the slope's centre value on ramps. Empty on flat maps.
## Exact at any point (mid-ramp): ViewUtil.ground_lift(height_map(), p).
var lift_px := PackedFloat32Array()


func setup(view: Node2D) -> void:
	mv = view
	var t0 := Time.get_ticks_msec()
	_w = int(mv.world.map.w)
	_h = int(mv.world.map.h)
	_prefill()
	_load_g6()
	_read_height()
	_update_lift()
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
				_install(Vector2i(cx0, cy0), _bake(cx0, cy0, mv.world.map.terrain, biome, _hg(), _rp()))
	bake_ms = Time.get_ticks_msec() - t0
	print("TERRAIN %s %d chunks (%dx%d)%s in %d ms" % ["lazy base +" if lazy else "baked", _chunks.size(), _w, _h,
		" height" if not hmap.is_empty() else "", bake_ms])


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
	# G7 (SCALE7): sized from the map (the old fixed +-16000 px rect ended inside a 512 map's diamond)
	var bw := maxf(16000.0, float(maxi(_w, _h)) * 32.0 + 4000.0)
	var bh := maxf(16000.0, float(_w + _h) * 16.0 + 4000.0)
	draw_rect(Rect2(Vector2(-bw, -8000), Vector2(2.0 * bw, bh + 8000.0)), Color(0.03, 0.035, 0.04))
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
	# G5 (VIEW5-2, ART-NAV): terrain_g5 rules (surf: cliff edge onto water, cliff_wet: water onto
	# cliff) follow the G4 rules with their own trans table; same 1024x64 edge/corner atlas layout.
	var g5: Dictionary = ArtCatalog.manifest().get("terrain_g5", {})
	var all_rules: Array = []
	for r in g4.get("rules", []):
		all_rules.append([r, g4.get("trans", {})])
	for r in g5.get("rules", []):
		all_rules.append([r, g5.get("trans", {})])
	g5_rules = 0
	for pair in all_rules:
		var r: Dictionary = pair[0]
		var trans: Dictionary = pair[1]
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
		if g5.get("rules", []).has(r):
			g5_rules += 1
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
## G6: with a height layer (hg, rp) the cells also get ramp / scree / rim overlays and the face atlas is copied
## under the flat image (rows img_h .. img_h + FACE_H) for the chunk mesh's face quads.
func _bake_image(cx0: int, cy0: int, terrain: PackedByteArray, biome: PackedByteArray = PackedByteArray(), hg: PackedByteArray = PackedByteArray(), rp: PackedByteArray = PackedByteArray()) -> Image:
	var w := _w
	var h := _h
	var img_w := CHUNK * 64
	var img_h := pad + (CHUNK - 1) * 32 + _below
	var has_h := not hg.is_empty() and hg.size() == w * h
	var img := Image.create(img_w, img_h + (FACE_H if has_h else 0), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if has_h and _faces_img != null:
		img.blit_rect(_faces_img, Rect2i(0, 0, mini(img_w, _faces_img.get_width()), FACE_H), Vector2i(0, img_h))
	var rail_ok := _rail_tracks.size() == 16
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
			if rail_ok and code == Terrain.RAIL:
				_rail_overlay(img, terrain, x, y, dst)
			if has_h:
				_height_overlays(img, hg, rp, x, y, b, dst)
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


# ---------------------------------------------------------------- G6 terrain height (ELEV-VIEW)
## Height-map dict of the drawn map ({} = flat). Pickers and VIEW6 pass it to ViewUtil (thread-safe: arrays only).
func height_map() -> Dictionary:
	return hmap


## Refresh lift_px: every cell when `cells` is empty or the size changed, else the given cells and their
## 4-neighbours (a ramp's slope depends on its neighbours' levels). Plain cells: (level - 1) * level_px.
func _update_lift(cells: Array = []) -> void:
	if hmap.is_empty():
		lift_px = PackedFloat32Array()
		return
	var hg: PackedByteArray = hmap.height
	var rp: PackedByteArray = hmap.ramps
	var n := _w * _h
	var todo: Array = []
	if cells.is_empty() or lift_px.size() != n:
		lift_px.resize(n)
		for i in n:
			lift_px[i] = (float(hg[i]) - 1.0) * ViewUtil.level_px
		if rp.size() == n:  # ramps and their 4-neighbours (plain corners bending with a ramp pair)
			for i in n:
				if rp[i] != 0:
					var c := Vector2i(i % _w, i / _w)
					todo.append_array([c, c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)])
	else:
		for c in cells:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					todo.append(Vector2i(int(c.x) + dx, int(c.y) + dy))
	for c in todo:
		var q: Vector2i = c
		if q.x >= 0 and q.y >= 0 and q.x < _w and q.y < _h:
			lift_px[q.y * _w + q.x] = ViewUtil.ground_lift(hmap, Vector2(q) + Vector2(0.5, 0.5))


func _hg() -> PackedByteArray:
	return hmap.get("height", PackedByteArray())


func _rp() -> PackedByteArray:
	return hmap.get("ramps", PackedByteArray())


## Main thread: (re)read the height layer while no sim step is in flight (height only changes in the editor).
func _read_height() -> void:
	if _busy_snap().is_empty() and mv.world.map is Dictionary:
		hmap = ViewUtil.height_map_of(mv.world.map)
	height_ver += 1
	if not hmap.is_empty() and _hmat == null:
		var sh := Shader.new()
		sh.code = HSHADER
		_hmat = ShaderMaterial.new()
		_hmat.shader = sh
		_hmat.set_shader_parameter("bright", BRIGHT)


## Main thread, at setup: the G6 terrain art (faces, ramp treads, scree, rims, rail). Missing art: a flat-colour
## face atlas and no overlays (the height still draws).
func _load_g6() -> void:
	var man: Dictionary = {}
	var p := G6_DIR + "manifest.json"
	if FileAccess.file_exists(p):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			man = parsed
	g6_art = not man.is_empty()
	_build_shadow_tabs()
	_faces_img = _g6_img(String(man.get("faces", {}).get("file", "")), Vector2i(1024, FACE_H))
	if _faces_img == null:
		_faces_img = _fallback_faces()
	var ramp := _g6_img(String(man.get("ramp", {}).get("file", "")), Vector2i(1024, 32))
	_ramp_ov.clear()
	for k in 16:
		_ramp_ov.append(ramp.get_region(Rect2i(k * 64, 0, 64, 32)) if ramp != null else null)
	var scree: Array = man.get("scree", [])
	_hscree.clear()
	for b in 4:
		_hscree.append(_rows(_g6_img(String(scree[b]) if b < scree.size() else "", Vector2i(1024, 64))))
	_hrim = _rows(_g6_img(String(man.get("rim", "")), Vector2i(1024, 64)))
	var rail: Dictionary = man.get("rail", {})
	var tracks := _g6_img(String(rail.get("tracks", "")), Vector2i(1024, 32))
	_rail_tracks.clear()
	if tracks != null:
		for m in 16:
			_rail_tracks.append(tracks.get_region(Rect2i(m * 64, 0, 64, 32)))
	var base: Array = rail.get("base", [])
	for b in mini(4, base.size()):
		var t := _g6_img(String(base[b]), Vector2i(64, 32))
		if t == null:
			continue
		if b == 0:
			_tile_cache["%d_0" % Terrain.RAIL] = t
			_variants[Terrain.RAIL] = 1
		else:
			_tile_cache["%d_0_b%d" % [Terrain.RAIL, b]] = t
			_bvar[Terrain.RAIL * 4 + b] = 1


func _g6_img(rel: String, size: Vector2i) -> Image:
	if rel == "":
		return null
	var img: Image = ArtCatalog._image(G6_DIR + rel)
	if img == null or img.get_size() != size:
		return null
	return img


## G4 transition atlas (1024x64) -> [edge[16], corner[16]] tiles; [] when missing.
func _rows(atlas: Image) -> Array:
	if atlas == null:
		return []
	var rows := [[], []]
	for row in 2:
		for m in 16:
			rows[row].append(atlas.get_region(Rect2i(m * 64, row * 32, 64, 32)))
	return rows


func _fallback_faces() -> Image:
	var img := Image.create(1024, FACE_H, false, Image.FORMAT_RGBA8)
	var cols := [Color(0.42, 0.36, 0.28), Color(0.45, 0.43, 0.4), Color(0.7, 0.62, 0.45), Color(0.55, 0.55, 0.53)]
	for blk in 16:
		var c: Color = cols[blk % 4]
		img.fill_rect(Rect2i(blk * 64, 0, 64, FACE_H), c)
		img.fill_rect(Rect2i(blk * 64, 0, 64, 2), c.lightened(0.3))
	return img


func _flat_h() -> int:
	return pad + (CHUNK - 1) * 32 + _below


## Pure function of (chunk, arrays): the chunk image, plus mesh arrays when the map has height. Worker-safe.
func _bake(cx0: int, cy0: int, terrain: PackedByteArray, biome: PackedByteArray, hg: PackedByteArray, rp: PackedByteArray) -> Variant:
	var img := _bake_image(cx0, cy0, terrain, biome, hg, rp)
	if hg.size() != _w * _h or hg.is_empty():
		return img
	return [img, _mesh_arrays(cx0, cy0, terrain, biome, hg, rp, Vector2(img.get_size()))]


## Mesh of a height chunk in chunk-local px (the flat image's frame): per cell, back-to-front, the top quad
## (hexagon for raised codes) lifted per vertex, then its SW and SE faces where the front neighbour is lower.
## Returns [verts, uvs, colors, indices]. Pure (worker-safe).
func _mesh_arrays(cx0: int, cy0: int, terrain: PackedByteArray, biome: PackedByteArray, hg: PackedByteArray, rp: PackedByteArray, tex: Vector2) -> Array:
	var vs := PackedVector2Array()
	var uv := PackedVector2Array()
	var cl := PackedColorArray()
	var ix := PackedInt32Array()
	var w := _w
	var h := _h
	var lp: float = ViewUtil.level_px
	var inv := Vector2(1.0 / tex.x, 1.0 / tex.y)
	var fy := float(_flat_h())
	var has_b := biome.size() == w * h
	for s in range(0, 2 * CHUNK - 1):
		for i in range(maxi(0, s - CHUNK + 1), mini(CHUNK, s + 1)):
			var j := s - i
			var x := cx0 + i
			var y := cy0 + j
			if x >= w or y >= h:
				continue
			var code := mini(int(terrain[y * w + x]), MAX_CODE - 1)
			var pv := ViewUtil.vtx(hg, rp, w, h, x, y)
			var lv := PackedFloat32Array([pv & 3, (pv >> 2) & 3, (pv >> 4) & 3, (pv >> 6) & 3])  # top right bottom left
			var tp := Vector2(CHUNK * 32 + (i - j) * 32, (i + j) * 16 + pad)
			var flat := [tp, tp + Vector2(32, 16), tp + Vector2(0, 32), tp + Vector2(-32, 16)]
			var gx := (lv[1] + lv[2] - lv[0] - lv[3]) * 0.5
			var gy := (lv[2] + lv[3] - lv[0] - lv[1]) * 0.5
			var shade := (1.0 + SLOPE_X * gx + SLOPE_Y * gy) / BRIGHT
			var b := mini(int(biome[y * w + x]), 3) if has_b else 0
			var tints: Array = LEVEL_TINT_B[b]
			var base := vs.size()
			var r: int = _raise[code]
			var order := [0, 1, 2, 3] if r == 0 else [0, 1, 1, 2, 3, 3]
			for k in order.size():
				var v: int = order[k]
				var f: Vector2 = flat[v]
				if r > 0 and (k == 0 or k == 1 or k == 5):
					f.y -= r
				vs.append(f - Vector2(0.0, (lv[v] - 1.0) * lp))
				uv.append(f * inv)
				var tc: Color = tints[int(lv[v])]
				cl.append(Color(tc.r * shade, tc.g * shade, tc.b * shade, 1.0))
			if r == 0:
				ix.append_array([base, base + 1, base + 3, base + 1, base + 2, base + 3])
			else:
				ix.append_array([base, base + 1, base + 2, base, base + 2, base + 3, base, base + 3, base + 4, base, base + 4, base + 5])
			var ux := float((b * 4 + STYLE_OF_CODE[code]) * 64 + ((x + y) & 1) * 32)
			if y + 1 < h:  # SW face: our left/bottom vertices over S's top/right vertices
				var ps := ViewUtil.vtx(hg, rp, w, h, x, y + 1)
				var fl := maxf(0.0, lv[3] - float(ps & 3)) * lp
				var fb := maxf(0.0, lv[2] - float((ps >> 2) & 3)) * lp
				if fl > 0.0 or fb > 0.0:
					_face_quad(vs, uv, cl, ix, flat[3], flat[2], (lv[3] - 1.0) * lp, (lv[2] - 1.0) * lp, fl, fb, ux, fy, inv, FACE_TOP[0])
			if x + 1 < w:  # SE face: our bottom/right vertices over E's left/top vertices
				var pe := ViewUtil.vtx(hg, rp, w, h, x + 1, y)
				var fb2 := maxf(0.0, lv[2] - float((pe >> 6) & 3)) * lp
				var fr := maxf(0.0, lv[1] - float(pe & 3)) * lp
				if fb2 > 0.0 or fr > 0.0:
					_face_quad(vs, uv, cl, ix, flat[2], flat[1], (lv[2] - 1.0) * lp, (lv[1] - 1.0) * lp, fb2, fr, ux, fy, inv, FACE_TOP[1])
	return [vs, uv, cl, ix]


## RAIL: sleepers and rails towards the 4-neighbours that are rail too (isolated: straight N-S).
func _rail_overlay(img: Image, terrain: PackedByteArray, x: int, y: int, dst: Vector2i) -> void:
	var m := 0
	for k in 4:
		if _code_at(terrain, x + NBR[k].x, y + NBR[k].y, -1) == Terrain.RAIL:
			m |= 1 << k
	img.blend_rect(_rail_tracks[m], Rect2i(0, 0, 64, 32), dst)


## Height overlays on the flat image: the ramp tread in the rise direction; scree on a low cell along cliff edges
## to higher cells; a lit rim on a high cell along cliff edges to lower cells (ramp-connected steps get neither).
func _height_overlays(img: Image, hg: PackedByteArray, rp: PackedByteArray, x: int, y: int, b: int, dst: Vector2i) -> void:
	var w := _w
	var i := y * w + x
	var lv := int(hg[i])
	var has_rp := rp.size() == hg.size()
	if has_rp and rp[i] != 0 and _ramp_ov.size() == 16:
		var dir := _rise_dir(ViewUtil.vtx(hg, rp, w, _h, x, y))
		if dir >= 0 and _ramp_ov[b * 4 + dir] != null:
			img.blend_rect(_ramp_ov[b * 4 + dir], Rect2i(0, 0, 64, 32), dst)
	var up := 0
	var down := 0
	var cu := 0
	var cd := 0
	for k in 8:
		var nx: int = x + NBR[k].x
		var ny: int = y + NBR[k].y
		if nx < 0 or ny < 0 or nx >= w or ny >= _h:
			continue
		var j := ny * w + nx
		var d := int(hg[j]) - lv
		if d == 0 or (absi(d) == 1 and has_rp and (rp[i] != 0 or rp[j] != 0)):
			continue
		# a diagonal step between two ramps is smooth (the corners bend with the ramps, ViewUtil._corner_fill)
		if k >= 4 and absi(d) == 1 and has_rp and rp[y * w + nx] != 0 and rp[ny * w + x] != 0:
			continue
		if k < 4:
			if d > 0:
				up |= 1 << k
			else:
				down |= 1 << k
		elif d > 0 and (up & CORNER_EDGES[k - 4]) == 0:
			cu |= 1 << (k - 4)
		elif d < 0 and (down & CORNER_EDGES[k - 4]) == 0:
			cd |= 1 << (k - 4)
	var sc: Array = _hscree[b] if b < _hscree.size() else []
	if not sc.is_empty():
		if up != 0:
			img.blend_rect(sc[0][up], Rect2i(0, 0, 64, 32), dst)
		if cu != 0:
			img.blend_rect(sc[1][cu], Rect2i(0, 0, 64, 32), dst)
	if not _sh_tab.is_empty():
		_shadow_overlay(img, hg, rp, x, y, lv, dst)
	if not _hrim.is_empty():
		if down != 0:
			img.blend_rect(_hrim[0][down], Rect2i(0, 0, 64, 32), dst)
		if cd != 0:
			img.blend_rect(_hrim[1][cd], Rect2i(0, 0, 64, 32), dst)


## Baked-shadow overlays in the 64x32 diamond frame, built once per process on the main thread (before any
## worker bakes): the W/S cast-shadow table, the SW-diagonal corner shadows and the cliff-base AO bands.
static func _build_shadow_tabs() -> void:
	if not _sh_tab.is_empty():
		return
	var uvs := PackedVector2Array()
	uvs.resize(64 * 32)
	for py in 32:
		var hw := (py + 1) * 2 if py < 16 else (32 - py) * 2   # same diamond as ViewUtil.terrain_tile_image
		for px in 64:
			if px < 32 - hw or px >= 32 + hw:
				uvs[py * 64 + px] = Vector2(-1.0, -1.0)
				continue
			var sx := (px + 0.5 - 32.0) / 32.0
			var sy := (py + 0.5) / 16.0
			uvs[py * 64 + px] = Vector2(clampf((sx + sy) * 0.5, 0.0, 1.0), clampf((sy - sx) * 0.5, 0.0, 1.0))
	var tab: Array = []
	for lw in 5:
		for ls in 5:
			tab.append(null if lw == 0 and ls == 0 else _sh_img(uvs, lw, ls, 0))
	var dg: Array = [null]
	for ld in range(1, 5):
		dg.append(_sh_img(uvs, 0, 0, ld))
	var ao: Array = [null]
	for m in range(1, 16):
		ao.append(_ao_img(uvs, m))
	_sh_diag = dg
	_ao_tab = ao
	_sh_tab = tab   # last: it is the "built" flag


## Shadow cover (0..1) at distance d (cells) from the casting edge for a shadow q quarters of a cell long
## (q = 4: the whole cell, soft edge beyond it).
static func _sh_cov(d: float, q: int) -> float:
	if q <= 0:
		return 0.0
	var l := 1.25 if q >= 4 else q * 0.25
	return clampf((l - d) / SH_SOFT + 0.5, 0.0, 1.0)


static func _sh_img(uvs: PackedVector2Array, lw: int, ls: int, ld: int) -> Image:
	var data := PackedByteArray()
	data.resize(64 * 32 * 4)
	for i in 64 * 32:
		var q: Vector2 = uvs[i]
		if q.x < 0.0:
			continue
		var a := maxf(_sh_cov(q.x, lw), _sh_cov(1.0 - q.y, ls))
		if ld > 0:
			a = maxf(a, _sh_cov(maxf(q.x, 1.0 - q.y), ld))
		if a <= 0.0:
			continue
		data[i * 4] = SH_COL.r8
		data[i * 4 + 1] = SH_COL.g8
		data[i * 4 + 2] = SH_COL.b8
		data[i * 4 + 3] = int(a * SH_A * 255.0)
	return Image.create_from_data(64, 32, false, Image.FORMAT_RGBA8, data)


## AO band along the cliff bases in mask m (1 N: v = 0, 2 E: u = 1, 4 S: v = 1, 8 W: u = 0).
static func _ao_img(uvs: PackedVector2Array, m: int) -> Image:
	var data := PackedByteArray()
	data.resize(64 * 32 * 4)
	for i in 64 * 32:
		var q: Vector2 = uvs[i]
		if q.x < 0.0:
			continue
		var d := 9.0
		if m & 1:
			d = minf(d, q.y)
		if m & 2:
			d = minf(d, 1.0 - q.x)
		if m & 4:
			d = minf(d, 1.0 - q.y)
		if m & 8:
			d = minf(d, q.x)
		if d >= AO_W:
			continue
		var t := 1.0 - d / AO_W
		data[i * 4 + 3] = int(AO_A * t * t * 255.0)
	return Image.create_from_data(64, 32, false, Image.FORMAT_RGBA8, data)


## Baked cast shadow + cliff-base AO on cell (x, y) (level lv) from higher ground, by edge vertex levels
## (ViewUtil.vtx), so a smooth ramp step casts nothing. Casters on the light side: W (x - k), S (y + k) and the
## SW diagonal, SH_LEN cells per level of drop minus the distance; AO along every edge with a cliff above it.
func _shadow_overlay(img: Image, hg: PackedByteArray, rp: PackedByteArray, x: int, y: int, lv: int, dst: Vector2i) -> void:
	var w := _w
	var h := _h
	var near := (y > 0 and int(hg[(y - 1) * w + x]) > lv) or (x + 1 < w and int(hg[y * w + x + 1]) > lv)
	if not near:
		for k in range(1, 4):
			if (x - k >= 0 and int(hg[y * w + x - k]) > lv) or (y + k < h and int(hg[(y + k) * w + x]) > lv) \
					or (x - k >= 0 and y + k < h and int(hg[(y + k) * w + x - k]) > lv):
				near = true
				break
	if not near:
		return
	var pv := ViewUtil.vtx(hg, rp, w, h, x, y)
	var r_t := float(pv & 3)
	var r_r := float((pv >> 2) & 3)
	var r_b := float((pv >> 4) & 3)
	var r_l := float((pv >> 6) & 3)
	var lw := 0.0
	var ls := 0.0
	var ld := 0.0
	var ao := 0
	for k in range(1, 4):
		if x - k >= 0 and int(hg[y * w + x - k]) > lv - 1:
			var c := ViewUtil.vtx(hg, rp, w, h, x - k, y)   # its E edge (right, bottom) over our W edge (top, left)
			var d := (float((c >> 2) & 3) + float((c >> 4) & 3) - r_t - r_l) * 0.5
			lw = maxf(lw, SH_LEN * d - (k - 1))
			if k == 1 and d > 0.4:
				ao |= 8
		if y + k < h and int(hg[(y + k) * w + x]) > lv - 1:
			var c2 := ViewUtil.vtx(hg, rp, w, h, x, y + k)  # its N edge (top, right) over our S edge (left, bottom)
			var d2 := (float(c2 & 3) + float((c2 >> 2) & 3) - r_l - r_b) * 0.5
			ls = maxf(ls, SH_LEN * d2 - (k - 1))
			if k == 1 and d2 > 0.4:
				ao |= 4
		if x - k >= 0 and y + k < h and int(hg[(y + k) * w + x - k]) > lv:
			var c3 := ViewUtil.vtx(hg, rp, w, h, x - k, y + k)  # its right vertex over our left vertex
			ld = maxf(ld, SH_LEN * (float((c3 >> 2) & 3) - r_l) - (k - 1))
	if y > 0:
		var cn := ViewUtil.vtx(hg, rp, w, h, x, y - 1)  # its S edge (left, bottom) over our N edge (top, right)
		if (float((cn >> 6) & 3) + float((cn >> 4) & 3) - r_t - r_r) * 0.5 > 0.4:
			ao |= 1
	if x + 1 < w:
		var ce := ViewUtil.vtx(hg, rp, w, h, x + 1, y)  # its W edge (top, left) over our E edge (right, bottom)
		if (float(ce & 3) + float((ce >> 6) & 3) - r_r - r_b) * 0.5 > 0.4:
			ao |= 2
	var qw := clampi(roundi(lw * 4.0), 0, 4)
	var qs := clampi(roundi(ls * 4.0), 0, 4)
	var qd := clampi(roundi(ld * 4.0), 0, 4)
	if qw > 0 or qs > 0:
		img.blend_rect(_sh_tab[qw * 5 + qs], Rect2i(0, 0, 64, 32), dst)
	elif qd > 0:
		img.blend_rect(_sh_diag[qd], Rect2i(0, 0, 64, 32), dst)
	if ao != 0:
		img.blend_rect(_ao_tab[ao], Rect2i(0, 0, 64, 32), dst)


## Rise direction of a ramp from its packed vertex levels: 0 N, 1 E, 2 S, 3 W; -1 = flat.
func _rise_dir(pv: int) -> int:
	var t := pv & 3
	var r := (pv >> 2) & 3
	var bt := (pv >> 4) & 3
	var l := (pv >> 6) & 3
	var gx := r + bt - t - l
	var gy := bt + l - t - r
	if gx == 0 and gy == 0:
		return -1
	if absi(gx) >= absi(gy):
		return 1 if gx > 0 else 3
	return 2 if gy > 0 else 0


## Face under the flat edge a -> b (a = left end on screen) whose top ends are lifted la / lb px and which hangs
## ha / hb px; textured from the face atlas column ux (32 px along the edge, rows = depth below the lip).
func _face_quad(vs: PackedVector2Array, uv: PackedVector2Array, cl: PackedColorArray, ix: PackedInt32Array, a: Vector2, b: Vector2, la: float, lb: float, ha: float, hb: float, ux: float, fy: float, inv: Vector2, top: float) -> void:
	var base := vs.size()
	var ta := a - Vector2(0.0, la)
	var tb := b - Vector2(0.0, lb)
	vs.append_array([ta, tb, ta + Vector2(0.0, ha), tb + Vector2(0.0, hb)])
	uv.append_array([Vector2(ux, fy) * inv, Vector2(ux + 32.0, fy) * inv,
		Vector2(ux, fy + minf(ha, FACE_H - 1.0)) * inv, Vector2(ux + 32.0, fy + minf(hb, FACE_H - 1.0)) * inv])
	var t := top / BRIGHT
	var f := t * FACE_FOOT
	cl.append_array([Color(t, t, t, 1.0), Color(t, t, t, 1.0), Color(f, f, f, 1.0), Color(f, f, f, 1.0)])
	ix.append_array([base, base + 1, base + 3, base, base + 3, base + 2])


func _worker(key: Vector2i, terrain: PackedByteArray, biome: PackedByteArray, hg: PackedByteArray = PackedByteArray(), rp: PackedByteArray = PackedByteArray()) -> void:
	var img = _bake(key.x, key.y, terrain, biome, hg, rp)
	_mutex.lock()
	_results[key] = img
	_mutex.unlock()


## res = Image (flat map: a Sprite2D chunk) or [Image, mesh arrays] (height map: a MeshInstance2D chunk).
func _install(key: Vector2i, res) -> void:
	var img: Image = res if res is Image else res[0]
	var arrays: Array = [] if res is Image else res[1]
	var spr: Node2D = _chunks.get(key)
	if spr != null and (spr is MeshInstance2D) != (not arrays.is_empty()):
		spr.queue_free()
		_chunks.erase(key)
		spr = null
	if spr == null:
		if arrays.is_empty():
			var sp := Sprite2D.new()
			sp.centered = false
			spr = sp
		else:
			spr = MeshInstance2D.new()
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.position = mv.world_to_screen(Vector2(key)) + Vector2(-CHUNK * 32, -pad)
		spr.set_meta("k", key)
		add_child(spr)
		_order(spr, key)
		_chunks[key] = spr
	spr.set("texture", ImageTexture.create_from_image(img))
	if not arrays.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = arrays[0]
		arr[Mesh.ARRAY_TEX_UV] = arrays[1]
		arr[Mesh.ARRAY_COLOR] = arrays[2]
		arr[Mesh.ARRAY_INDEX] = arrays[3]
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		(spr as MeshInstance2D).mesh = am
		spr.material = _hmat
		meshes_built += 1
	baked_total += 1


## Chunk sprites stay in row-major (back-to-front) order so a raised tile's overhang into the
## chunk behind it is drawn on top of that chunk.
func _order(spr: Node2D, key: Vector2i) -> void:
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
## G6: also re-reads the height layer (editor height brushes); with height the reach is two cells (ramp slopes
## and faces depend on neighbours' vertices). Height appearing or vanishing rebuilds everything.
func rebake_cells(cells: Array) -> void:
	var was_h := not hmap.is_empty()
	_read_height()
	if was_h != (not hmap.is_empty()):
		rebuild()
		return
	_update_lift(cells)
	var biome := _biome_arr()
	var terrain := _terrain()
	if not _biomes_loaded and _any_biome(biome):
		_load_biomes()
	var rad := 1 if hmap.is_empty() else 2
	var done := {}
	for c in cells:
		var cx := int(c.x)
		var cy := int(c.y)
		if cx < 0 or cy < 0 or cx >= _w or cy >= _h:
			continue
		if lazy and _base_img != null:
			_base_cell(cx, cy, biome, terrain)
			if rad == 2:  # base cliff shading looks at the E / S neighbours
				if cx > 0:
					_base_cell(cx - 1, cy, biome, terrain)
				if cy > 0:
					_base_cell(cx, cy - 1, biome, terrain)
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var nx := cx + dx
				var ny := cy + dy
				if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
					continue
				done[Vector2i((nx / CHUNK) * CHUNK, (ny / CHUNK) * CHUNK)] = true
	var keys: Array = done.keys()
	keys.sort()
	for key in keys:
		if not lazy or _chunks.has(key):
			_install(key, _bake(key.x, key.y, terrain, biome, _hg(), _rp()))
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
	if not hmap.is_empty():
		c = _base_height_col(c, x, y, b)
	_base_img.set_pixel(x, y, c)


## G6 far-zoom base: biome level tint (LEVEL_TINT_B), the dark of a cliff face where the E or S neighbour sits
## lower (no ramp), and the baked cast shadow where the W or S neighbour sits higher (no ramp).
func _base_height_col(c: Color, x: int, y: int, b: int = 0) -> Color:
	var hg: PackedByteArray = hmap.height
	var rp: PackedByteArray = hmap.ramps
	var i := y * _w + x
	var lv := int(hg[i])
	var tc: Color = LEVEL_TINT_B[clampi(b, 0, 3)][lv]
	var k := 1.0
	var has_rp := rp.size() == hg.size()
	for j in [i + 1 if x + 1 < _w else -1, i + _w if y + 1 < _h else -1]:
		if j < 0:
			continue
		var d := lv - int(hg[j])
		if d >= 2 or (d == 1 and (not has_rp or (rp[i] == 0 and rp[j] == 0))):
			k = 0.55
			break
	if k == 1.0:
		for j in [i - 1 if x > 0 else -1, i + _w if y + 1 < _h else -1]:
			if j < 0:
				continue
			var d := int(hg[j]) - lv
			if d >= 2 or (d == 1 and (not has_rp or (rp[i] == 0 and rp[j] == 0))):
				k = 1.0 - SH_A * 0.9
				break
	return Color(clampf(c.r * tc.r * k, 0.0, 1.0), clampf(c.g * tc.g * k, 0.0, 1.0), clampf(c.b * tc.b * k, 0.0, 1.0), c.a)


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
		(_chunks[key] as Node2D).visible = not far
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
	# G6: raised tiles reach into view from below the screen edge, valleys from above (16 px per cell step)
	var mg := 2 if hmap.is_empty() else 2 + ceili(ViewUtil.lift_px(ViewUtil.MAX_LEVEL) / 16.0)
	var mt := 2 if hmap.is_empty() else 2 + ceili(ViewUtil.level_px / 16.0)
	for cy0 in range(maxi(0, (lo.y - mt) / CHUNK) * CHUNK, mini(_h, hi.y + mg), CHUNK):
		for cx0 in range(maxi(0, (lo.x - mt) / CHUNK) * CHUNK, mini(_w, hi.x + mg), CHUNK):
			var key := Vector2i(cx0, cy0)
			_seen[key] = _frame
			if not _chunks.has(key) and not _pending.has(key):
				want.append(key)
	var biome := _biome_arr()
	for key in want:
		if _pending.size() >= MAX_PENDING:
			break
		_pending[key] = WorkerThreadPool.add_task(_worker.bind(key, _terrain(), biome, _hg(), _rp()), false, "terrain chunk")
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
