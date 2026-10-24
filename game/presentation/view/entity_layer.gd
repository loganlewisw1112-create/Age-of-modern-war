extends Node2D
## Batched, y-sorted entity + decor layer (owner: R4-render, G3b; was agent D's one-Sprite2D-
## per-entity layer). Everything draws from ONE CanvasItem: entities and decor resolve to regions
## of a few atlas pages (batch_art.gd / batch_atlas.gd), are culled to the camera view, y-sorted
## with a native PackedInt64Array sort, and drawn with draw_texture_rect_region so the renderer
## batches them. Zoom LOD: close/mid = full sprites; far (zoom < LOD_FAR) = team-tinted icons.
## Fog rules are unchanged: enemy units only on visible cells; enemy buildings while visible,
## then their remembered state (greyed); wrecks once seen; resources once their cell is explored.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const G3View = preload("res://presentation/view/g3_view.gd")
const BatchArt = preload("res://presentation/view/batch_art.gd")
const LodIcons = preload("res://presentation/view/lod_icons.gd")

const LOD_MID := 0.8     # zoom below this: mid LOD (small FX dropped by fx_layer)
const LOD_FAR := 0.45    # zoom below this: far LOD (unit icons)
const CHUNK := 16        # decor bucket size (cells)
const MARGIN := 220.0    # cull margin around the view (world px; tallest sprites)
const IDX_MUL := 4194304          # 2^22 items per frame max
const Y_OFF := 65536
const LAYER_MUL := 17592186044416 # 2^44
const GHOST_MOD := Color(0.75, 0.75, 0.8)
const FACING_INV := 1.0 / (PI / 4.0)  # = 1 / ArtCatalog.FACING_STEP

var mv
var art = BatchArt.new()
var icons = LodIcons.new()
var lod := 0                 # 0 close, 1 mid, 2 far
var decor_count := 0
var drawn := 0               # items drawn last frame (perf evidence)
var _seen_wrecks: Dictionary = {}
var _ghosts: Dictionary = {}       # remembered-building id -> ghost entity dict
var _decor: Dictionary = {}        # Vector2i chunk -> Array [pos, page, src, off, ...]
var _decor_rect: Dictionary = {}   # Vector2i chunk -> Rect2 (screen bounds)
var _team: Dictionary = {}         # fid -> Color (refreshed each frame)
var _ck: Dictionary = {}           # fid -> colour key string
var _fac: Dictionary = {}          # fid -> faction def id
# per-frame item buffers (reused)
var _n := 0
var _keys := PackedInt64Array()
var _page := PackedInt32Array()
var _src := PackedVector2Array()
var _size := PackedVector2Array()
var _dst := PackedVector2Array()
var _dsz := PackedVector2Array()
var _mod := PackedColorArray()
var _sorted := PackedInt64Array()
# G3b (R4-2): per-frame visible lists shared with the overlays (g2_overlay, g3_view,
# overlay_layer) so no other node scans every entity each frame. Rebuilt by refresh():
# entities inside the cull rect that pass the fog rules, with their ground screen position.
var vis_units: Array = []                  # unit entity dicts
var vis_sp := PackedVector2Array()         # ground screen pos (interpolated; not air-lifted)
var vis_air := PackedInt32Array()          # indices into vis_units of air units
var vis_bld: Array = []                    # visible (non-ghost) building dicts
var _air_def: Dictionary = {}              # def -> bool (G3.is_air cache)
var _far_key: Array = []                   # far LOD: last rebuild key (tick, view, fog, n)
var skipped := 0                           # far-LOD frames that reused the last draw list


func setup(view) -> void:
	mv = view
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_decor()


func _build_decor() -> void:
	var w := int(mv.world.map.w)
	var h := int(mv.world.map.h)
	var terrain: PackedByteArray = mv.world.map.terrain
	for y in h:
		for x in w:
			var d: Dictionary = ArtCatalog.decor(int(terrain[y * w + x]), Vector2i(x, y))
			if d.is_empty():
				continue
			var tex = d.get("texture")
			if tex == null or ViewUtil.is_placeholder(tex):
				continue
			var key: String = art.tex_slot(tex)
			var pg: int = art.atlas.page_of(key)
			if pg < 0:
				continue
			var src: Rect2 = art.atlas.rect_of(key)
			var p: Vector2 = mv.world_to_screen(Vector2(x + 0.5, y + 0.5))
			var off: Vector2 = d.get("offset", Vector2.ZERO)
			var ck := Vector2i(x / CHUNK, y / CHUNK)
			if not _decor.has(ck):
				_decor[ck] = []
				_decor_rect[ck] = Rect2(p + off, src.size)
			var arr: Array = _decor[ck]
			arr.append_array([p, pg, src, off])
			_decor_rect[ck] = (_decor_rect[ck] as Rect2).merge(Rect2(p + off, src.size))
			decor_count += 1


func on_destroyed(id: int) -> void:
	art.forget(id)
	_seen_wrecks.erase(id)


func _push(layer: int, y: float, page: int, src: Rect2, dst: Vector2, dsz: Vector2, mod: Color) -> void:
	var i := _n
	if i >= _page.size():
		var cap := maxi(256, _page.size() * 2)
		_keys.resize(cap); _page.resize(cap); _src.resize(cap); _size.resize(cap)
		_dst.resize(cap); _dsz.resize(cap); _mod.resize(cap)
	_keys[i] = layer * LAYER_MUL + (int(y) + Y_OFF) * IDX_MUL + i
	_page[i] = page
	_src[i] = src.position
	_size[i] = src.size
	_dst[i] = dst
	_dsz[i] = dsz
	_mod[i] = mod
	_n = i + 1


func _reserve(n: int) -> void:
	if n <= _page.size():
		return
	var cap := maxi(256, maxi(n, _page.size() * 2))
	_keys.resize(cap); _page.resize(cap); _src.resize(cap); _size.resize(cap)
	_dst.resize(cap); _dsz.resize(cap); _mod.resize(cap)


func mem_size(w, pf: int) -> int:
	return (w.memory.get(pf, {}) as Dictionary).size()


func _view_rect() -> Rect2:
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var vs: Vector2 = get_viewport_rect().size
	var r := Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * vs).expand(inv * Vector2(vs.x, 0)).expand(inv * Vector2(0, vs.y))
	return r.grow(MARGIN)


func refresh() -> void:
	var w = mv.world
	var pf: int = mv.player_fid
	var z: float = mv.camera.zoom.x if mv.camera != null else 1.0
	lod = 2 if z < LOD_FAR else (1 if z < LOD_MID else 0)
	var far := lod == 2
	var t: float = mv.anim_time()
	var alpha: float = mv._alpha
	var prev: Dictionary = mv._prev_pos
	var vr := _view_rect()
	# far LOD draws un-interpolated icons, so the list only changes with the sim tick, the
	# camera, the fog or the selection: reuse the canvas commands from the last rebuild.
	if far:
		var key := [w.tick, get_viewport().get_canvas_transform(), get_viewport_rect().size,
			mv.fog_layer.rebuilds if mv.fog_layer != null else 0, w.entities.size(), mem_size(w, pf)]
		if key == _far_key:
			skipped += 1
			return
		_far_key = key
	else:
		_far_key = []
	vis_units.clear()
	vis_sp.resize(0)
	vis_air.resize(0)
	vis_bld.clear()
	for fid in w.factions:
		var c: Color = mv.team_color(int(fid))
		_team[fid] = c
		_ck[fid] = c.to_html()
		_fac[fid] = String(w.factions[fid].get("faction_def", ""))
	var neutral: Color = mv.team_color(-1)
	var mw := int(w.map.w)
	var fog: Dictionary = w.fog.get(pf, {})
	var vis: PackedByteArray = fog.get("visible", PackedByteArray())
	var ally_vis: Array = []
	for a in mv._ally_fids:
		var af: Dictionary = w.fog.get(a, {})
		if not af.is_empty():
			ally_vis.append(af.visible)
	var mem: Dictionary = w.memory.get(pf, {})
	var inv_z := 1.0 / maxf(z, 0.05)
	var ec: Dictionary = art._ec
	_n = 0
	_reserve(w.entities.size() + decor_count + mem.size() + 16)
	# decor (static, bucketed by chunk)
	var t_sub := Time.get_ticks_usec()
	for ck in _decor:
		if not vr.intersects(_decor_rect[ck]):
			continue
		var arr: Array = _decor[ck]
		for k in range(0, arr.size(), 4):
			var p: Vector2 = arr[k]
			_push(0, p.y, arr[k + 1], arr[k + 2], p + (arr[k + 3] as Vector2), (arr[k + 2] as Rect2).size, Color.WHITE)
	ViewUtil.prof_add("p_e1_decor", t_sub)
	t_sub = Time.get_ticks_usec()
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		var kind: String = e.kind
		if kind == "unit":
			var ow: int = e.owner
			var raw: Vector2 = e.pos
			var pos := raw
			if not far:
				var pp = prev.get(id)
				if pp != null and (pp as Vector2).distance_squared_to(raw) < 4.0:
					pos = (pp as Vector2).lerp(raw, alpha)
			var sp := Vector2((pos.x - pos.y) * 32.0, (pos.x + pos.y) * 16.0)
			if not vr.has_point(sp):
				continue
			if ow != pf:
				var ci := floori(raw.y) * mw + floori(raw.x)
				if not vis.is_empty() and (ci < 0 or ci >= vis.size()):
					continue
				if not vis.is_empty() and vis[ci] == 0:
					var seen := false
					for av in ally_vis:
						if (av as PackedByteArray)[ci] == 1:
							seen = true
							break
					if not seen:
						continue
			var dname: String = e.def
			var is_air = _air_def.get(dname)
			if is_air == null:
				is_air = G3View.is_air_entity(e)
				_air_def[dname] = is_air
			if is_air:
				vis_air.append(vis_units.size())
			vis_units.append(e)
			vis_sp.append(sp)
			if far:
				var ic: Array = icons.icon(art.atlas, String(_fac.get(ow, "")), icons.class_of(String(e.def)))
				var isz: Vector2 = (ic[1] as Vector2) * inv_z
				_push(2, sp.y, art.atlas.page_of(ic[0]), art.atlas.rect_of(ic[0]), sp + (ic[2] as Vector2) * inv_z, isz, _team.get(ow, neutral))
				continue
			# hot path: inline frame choice from the per-id art cache (see BatchArt.resolve_unit)
			var c = ec.get(id)
			if c == null or c[1] != ow or c[0] != dname:
				c = art.cache_unit(e, _team.get(ow, neutral), String(_ck.get(ow, "x")))
			var pg: int = c[2]
			if pg == -2:
				art.resolve_unit(e, _team.get(ow, neutral), String(_ck.get(ow, "x")), t)
				if art.out_page >= 0:
					_push(0, sp.y, art.out_page, art.out_src, sp + art.out_off, art.out_src.size, Color.WHITE)
				continue
			var fi := 0
			if e.firing > 0:
				fi = c[7]
			elif e.moving:
				var ph := int(t * 6.0 + int(id) * 0.37)
				if c[8]:
					fi = c[9] if ph % 2 == 0 else c[10]
				else:
					fi = c[11] if ph % 2 == 0 else 0
			if fi < 0:
				fi = 0
			var row := posmod(int(round(float(e.facing) * FACING_INV)), 8)
			var fsz := Vector2(c[4], c[5])
			var layer := 0
			if c[12]:
				sp.y -= G3View.air_lift(e, t)  # G3a: air units fly above their ground point
				layer = 1
			# inlined _push (capacity reserved above)
			var ii := _n
			_keys[ii] = layer * LAYER_MUL + (int(sp.y) + Y_OFF) * IDX_MUL + ii
			_page[ii] = pg
			_src[ii] = (c[3] as Vector2) + Vector2(fi, row) * fsz
			_size[ii] = fsz
			_dst[ii] = sp + (c[6] as Vector2)
			_dsz[ii] = fsz
			_mod[ii] = Color.WHITE
			_n = ii + 1
			continue
		var ow := int(e.get("owner", -1))
		var gp: Vector2 = e.pos
		var gs := Vector2((gp.x - gp.y) * 32.0, (gp.x + gp.y) * 16.0)
		if not vr.has_point(gs):
			if kind == "wreck" and not _seen_wrecks.has(id) and mv.cell_visible(w.cell_of(e.pos)):
				_seen_wrecks[id] = true
			continue
		var mod := Color.WHITE
		match kind:
			"building":
				if ow != pf and not mv.entity_visible(e):
					if not mem.has(id):
						continue
					mod = GHOST_MOD
				else:
					vis_bld.append(e)
			"resource":
				if not mv.cell_explored(w.cell_of(e.pos)):
					continue
			"wreck":
				if not _seen_wrecks.has(id):
					if not mv.cell_visible(w.cell_of(e.pos)):
						continue
					_seen_wrecks[id] = true
		var col: Color = _team.get(ow if kind != "wreck" else int(e.get("from_owner", -1)), neutral)
		art.resolve_static(e, col, String(_ck.get(ow, "x")))
		if art.out_page >= 0:
			_push(0, gs.y, art.out_page, art.out_src, gs + art.out_off, art.out_src.size, mod)
	ViewUtil.prof_add("p_e2_ents", t_sub)
	t_sub = Time.get_ticks_usec()
	_push_ghosts(w, mem, vr, neutral)
	art.atlas.flush()
	_sorted = _keys.slice(0, _n)
	_sorted.sort()
	ViewUtil.prof_add("p_e3_sort", t_sub)
	drawn = _n
	queue_redraw()


## Remembered enemy buildings that no longer exist (destroyed out of sight): greyed ghosts.
func _push_ghosts(w, mem: Dictionary, vr: Rect2, neutral: Color) -> void:
	for eid in mem:
		if w.entities.has(eid):
			continue
		var m: Dictionary = mem[eid]
		if String(m.get("kind", "building")) != "building":
			continue
		var g = _ghosts.get(eid)
		if g == null:
			var size := int(Content.building(String(m.def)).get("size", 1))
			g = {"id": int(eid), "kind": "building", "def": m.def, "owner": int(m.owner),
				"pos": m.pos, "size": size, "cell": Vector2i(floori(m.pos.x - size * 0.5), floori(m.pos.y - size * 0.5)),
				"built": true, "progress": 1.0, "hp": 1.0, "max_hp": 1.0}
			_ghosts[eid] = g
		var gs: Vector2 = mv.world_to_screen(g.pos)
		if not vr.has_point(gs):
			continue
		var ow := int(g.owner)
		art.resolve_static(g, _team.get(ow, neutral), String(_ck.get(ow, "x")))
		if art.out_page >= 0:
			_push(0, gs.y, art.out_page, art.out_src, gs + art.out_off, art.out_src.size, GHOST_MOD)
	for eid in _ghosts.keys():
		if not mem.has(eid) or w.entities.has(eid):
			_ghosts.erase(eid)
			art.forget(int(eid))


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_body()
	preload("res://presentation/view/view_util.gd").prof_add("d_ent", t0)


func _draw_body() -> void:
	if _sorted.is_empty():
		return
	var texs: Array = []
	for p in art.atlas.pages:
		texs.append(p.tex)
	for k in _sorted:
		var i := k % IDX_MUL
		draw_texture_rect_region(texs[_page[i]], Rect2(_dst[i], _dsz[i]), Rect2(_src[i], _size[i]), _mod[i])
