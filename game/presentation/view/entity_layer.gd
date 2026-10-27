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
const RenderSnap = preload("res://sim/render_snap.gd")
const G5Art = preload("res://presentation/art/g5_art.gd")
const G6Vis = preload("res://presentation/art/g6_vis.gd")
const Motion = preload("res://presentation/view/motion.gd")               # G6.1 (ANIMA61) render motion layer
const Morale = preload("res://sim/systems/morale.gd")                     # G6.1 REAL61 (read-only, postures)
const Fatigue = preload("res://sim/systems/fatigue.gd")
const RealInfo = preload("res://presentation/ui6/realism_info.gd")
const AmmoBearer = preload("res://sim/systems/ammo_bearer.gd")            # G6.1 BEARER61 load pips
const VehAnim61 = preload("res://presentation/view/veh_anim61.gd")        # G6.1 (ANIMC61) vehicle frame selection
const MOTION_CAP := 700      # G6.1: motion layer (smooth facing, ease, bob, reactions) only while <= this many units drew
const RUN_SPEED := 2.3       # G6.1: drawn speed (tiles/s) above which infantry use the run cycle

const LOD_MID := 0.8     # zoom below this: mid LOD (small FX dropped by fx_layer)
const LOD_FAR := 0.45    # zoom below this: far LOD (unit icons)
const CHUNK := 16        # decor bucket size (cells)
const MARGIN := 220.0    # cull margin around the view (world px; tallest sprites)
const IDX_MUL := 4194304          # 2^22 items per frame max
const Y_OFF := 65536
const LAYER_MUL := 17592186044416 # 2^44
const GHOST_MOD := Color(0.75, 0.75, 0.8)
const FACING_INV := 1.0 / (PI / 4.0)  # = 1 / ArtCatalog.FACING_STEP
const POSE_MASK := RenderSnap.FLAG_DEPLOYED | RenderSnap.FLAG_WORK | RenderSnap.FLAG_UNLOAD
const DSTRIDE := 5                    # decor item: [pos, page, src, off, cell index (-1 = POI)]
const G5_POSE := RenderSnap.FLAG_TACTICAL | RenderSnap.FLAG_EVAC

var mv
var art = BatchArt.new()
var icons = LodIcons.new()
var lod := 0                 # 0 close, 1 mid, 2 far
var decor_count := 0
var drawn := 0               # items drawn last frame (perf evidence)
var _seen_wrecks: Dictionary = {}
# G7 (CNFAC7-2): C-17-style ramp loading playback (fact art.dropship_sizes rev4) + footprint y-sort (ARTCN7-5 CR seq 1193)
const BAY_ART := {"cn_stealth_dropship": "g7_cn_stealth_dropship", "a_vtol_dropship": "g7_a_vtol_dropship_xl",
	"g7_cn_stealth_dropship": "g7_cn_stealth_dropship", "g7_a_vtol_dropship_xl": "g7_a_vtol_dropship_xl"}
const XL_REMAP := true      # a_vtol_dropship draws as the enlarged g7_a_vtol_dropship_xl (scope 6.9 "upgraded, enlarged")
const BAY_LANDED := 3       # main-sheet columns: hover flight transition landed ramp_down apc_ramp bay_open squad_in drones
const BAY_RAMP := 4
const BAY_OPEN := 6
const BAY_FILE_FPS := 4.7   # boarding file: one 1.2 m spacing per 4-frame loop at ~1.4 m/s
const FOOT_U := 2.45        # landed craft footprint half extents (tiles): nose..ramp foot, span incl. fans
const FOOT_V := 2.1
const ROOF_CUT_MOD := Color(1.0, 0.96, 0.9, 0.34)  # G7 (LOOK7): building drawn see-through, troops inside shown
var _ghosts: Dictionary = {}       # remembered-building id -> ghost entity dict
var _decor: Dictionary = {}        # Vector2i chunk -> Array [pos, page, src, off, ...]
var _decor_rect: Dictionary = {}   # Vector2i chunk -> Rect2 (screen bounds)
var _flat: Dictionary = {}         # G4: flat map POI decor (rails, tarmac, dam): drawn under everything
var _flat_rect: Dictionary = {}
var poi_count := 0
var coast_count := 0  # G5 (VIEW5-2): coast_* decor sprites placed from map.decor
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
# G4b (UI4B-3): burnt-out forest cells (TerrainChanged cause "fire"): cell index -> true. Their
# tree decor is skipped and a burnt_ground variant (cell hash) is drawn flat. Presentation-only:
# the sim keeps no burnt set, so a loaded save shows plain dirt there (KNOWN GAP).
var burnt: Dictionary = {}
var fires_drawn := 0                       # last frame's counts (playtest / debug)
var burnt_drawn := 0
var g4b_fx_drawn := 0                      # mines + charges drawn from effect art
# G5 (VIEW5): last frame's counts (headless probe / playtests) and the sim burnt-set sync
var g5_counts: Dictionary = {}             # shadows, lifted, wounded, markers, red_cross, trails, slung, strips, sinking
var _burnt_src := PackedByteArray()        # last snap.burnt merged into `burnt`
var _lift := 0.0                           # last _g5_lift result (px)
var _crafts: Array = []                    # G7 (CNFAC7-2): landed large dropships this frame [pos, facing, depth, id]
var bay_drawn := 0                         # G7 (CNFAC7-2): ramp-sequence frames drawn last refresh (playtest probe)
# G6 (VIEW6): height lift table (terrain_layer.lift_px when ELEV-VIEW publishes it, else built from
# snap.height x terrain_layer.level_px) and last frame's counts (probe / tests)
var _hlift := PackedFloat32Array()
var _hlift_src := PackedByteArray()
var _hlift_px := -1.0
var g6_counts: Dictionary = {}
# G6.1 (ANIMA61): render motion layer + per-id cosmetic state (view only; never written back to the sim)
var motion = Motion.new()
var motion_on := true         # last frame's decision (MOTION_CAP)
var _atlas_at: float = float(OS.get_environment("ANIM61_ATLAS_AT")) if OS.has_environment("ANIM61_ATLAS_AT") else -1.0
var _units_drawn := 0
var _mcls: Dictionary = {}    # def -> Motion class
var _post: Dictionary = {}    # id -> Motion posture bits from REAL61 Morale (pinned / suppressed / broken)
var _fat: Dictionary = {}     # id -> REAL61 Fatigue level 0..1
var _chev: Dictionary = {}    # id -> rank chevron 0..4 (REAL61 realism_info.chevron)
var _pips: Dictionary = {}    # id -> 1 + filled ammo pips (BEARER61 bearers), absent = not a bearer
var g61_counts: Dictionary = {}
var g61_off := OS.get_environment("ANIM61_OFF") == "1"   # perf A/B: G6.1 motion + anim61 frame choice off
var _no61: Dictionary = {}


## Per-cell lift (px) for this frame: ELEV-VIEW's own table wins (exactly what the terrain bake used).
func _height_lift(sn: Dictionary) -> PackedFloat32Array:
	var tl = mv.terrain_layer if mv != null else null
	if tl != null:
		var lt = tl.get("lift_px")
		if lt is PackedFloat32Array and not (lt as PackedFloat32Array).is_empty():
			return lt
	var lp = tl.get("level_px") if tl != null else null
	var px: float = float(lp) if lp != null else G6Vis.DEFAULT_LEVEL_PX
	var h: PackedByteArray = sn.get("height", PackedByteArray())
	if px != _hlift_px or h.size() != _hlift_src.size() or h != _hlift_src:
		_hlift_px = px
		_hlift_src = h
		_hlift = G6Vis.lift_table(h, sn.get("ramps", PackedByteArray()), px)
	return _hlift


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
			arr.append_array([p, pg, src, off, y * w + x])
			_decor_rect[ck] = (_decor_rect[ck] as Rect2).merge(Rect2(p + off, src.size))
			decor_count += 1
	_build_poi_decor()


## G4 (ED1 / ART4 gap): map.decor POI footprints (factory blocks, refinery, dam, hangar, houses,
## rail...) drawn from manifest poi_decor[id] = {file, pivot, footprint, flat}. Static, bucketed
## like terrain decor; an entry larger than its sprite's footprint is tiled with it.
func _build_poi_decor() -> void:
	var pois: Dictionary = ArtCatalog.manifest().get("poi_decor", {})
	var lists: Dictionary = ArtCatalog.manifest().get("decor", {})
	for d in mv.world.map.get("decor", []):
		var spec: Dictionary = pois.get(String(d.get("id", "")), {})
		if spec.is_empty():
			if String(d.get("id", "")).begins_with("coast_") and lists.get(String(d.id)) is Array:
				_build_coast_decor(d, lists[String(d.id)])
			continue
		var img: Image = ArtCatalog._image(String(spec.file))
		art._whole("poi|" + String(spec.file), img, spec.pivot)
		if art.out_page < 0:
			continue
		var fp := Vector2i(int(spec.footprint[0]), int(spec.footprint[1]))
		var c0 := Vector2i(d.cell)
		var sz := Vector2i(d.get("size", fp))
		var flat := bool(spec.get("flat", false))
		for oy in range(0, maxi(1, sz.y), maxi(1, fp.y)):
			for ox in range(0, maxi(1, sz.x), maxi(1, fp.x)):
				var g := Vector2(c0 + Vector2i(ox, oy)) + Vector2(fp) * 0.5
				var p: Vector2 = mv.world_to_screen(g)
				var ck := Vector2i(int(g.x) / CHUNK, int(g.y) / CHUNK)
				var bk: Dictionary = _flat if flat else _decor
				var rk: Dictionary = _flat_rect if flat else _decor_rect
				var r := Rect2(p + art.out_off, art.out_src.size)
				if not bk.has(ck):
					bk[ck] = []
					rk[ck] = r
				(bk[ck] as Array).append_array([p, art.out_page, art.out_src, art.out_off, -1])
				rk[ck] = (rk[ck] as Rect2).merge(r)
				decor_count += 1
				poi_count += 1


## G5 (VIEW5-2, ART-NAV): a map.decor entry naming a manifest decor list (coast_beach / coast_cliff /
## coast_shallow) scatters one variant (cell hash) per footprint cell, y-sorted like terrain decor.
func _build_coast_decor(d: Dictionary, list: Array) -> void:
	if list.is_empty():
		return
	var c0 := Vector2i(d.get("cell", Vector2i.ZERO))
	var sz := Vector2i(d.get("size", Vector2i.ONE))
	for oy in maxi(1, sz.y):
		for ox in maxi(1, sz.x):
			var cell := c0 + Vector2i(ox, oy)
			var v: Dictionary = list[absi((cell.x * 73856093) ^ (cell.y * 19349663)) % list.size()]
			art._whole("decor|" + String(v.file), ArtCatalog._image(String(v.file)), v.get("pivot", [0, 0]))
			if art.out_page < 0:
				continue
			var p: Vector2 = mv.world_to_screen(Vector2(cell) + Vector2(0.5, 0.5))
			var ck := Vector2i(cell.x / CHUNK, cell.y / CHUNK)
			var r := Rect2(p + art.out_off, art.out_src.size)
			if not _decor.has(ck):
				_decor[ck] = []
				_decor_rect[ck] = r
			(_decor[ck] as Array).append_array([p, art.out_page, art.out_src, art.out_off, -1])
			_decor_rect[ck] = (_decor_rect[ck] as Rect2).merge(r)
			decor_count += 1
			coast_count += 1


func on_destroyed(id: int) -> void:
	# G6.1: an infantry unit with the anim61 set leaves a corpse (die_0..2, lingers, fades)
	var dc = art._ec.get(id)
	if dc is Array and (dc as Array).size() > 37 and not (dc[31] as Dictionary).is_empty() and mv != null:
		motion.kill(id, dc, mv.anim_time())
	else:
		motion.forget(id)
	_post.erase(id)
	_fat.erase(id)
	_chev.erase(id)
	_pips.erase(id)
	art.forget(id)
	art.forget(-1 - id)  # G5: its sling-load sprite cache
	_seen_wrecks.erase(id)


## G6.1: ShotFired view event (match_view): shooter recoil kick, target hit flinch.
func on_shot(ev: Dictionary) -> void:
	motion.on_shot(int(ev.get("shooter", -1)), int(ev.get("target", -1)))


## G6.1: cosmetic posture / fatigue / rank / bearer pips of a live entity (read-only REAL61 / BEARER61 calls).
func _refresh_post(id: int, e: Dictionary) -> void:
	var w = mv._world
	var p := 0
	match Morale.state(w, e):
		"pinned": p = Motion.P_PINNED
		"suppressed": p = Motion.P_SUPPRESSED
		"broken": p = Motion.P_BROKEN
	_post[id] = p
	_fat[id] = Fatigue.level(w, e)
	_chev[id] = RealInfo.chevron(e)
	if AmmoBearer.is_bearer(e):
		_pips[id] = 1 + clampi(ceili(AmmoBearer.load_frac(e) * 3.0), 0, 3)


## G6.1: small procedural marks in the atlas: rank chevrons chev:1..4 (gold), bearer pips pip:0 / pip:1.
func _mark(key: String) -> int:
	if art.atlas.has(key):
		return art.atlas.page_of(key)
	var img: Image
	if key.begins_with("chev:"):
		var r := int(key.substr(5))
		img = Image.create(7, 2 + r * 2, false, Image.FORMAT_RGBA8)
		for k in r:
			for x in 7:
				var y := k * 2 + absi(x - 3) / 2
				img.set_pixel(x, mini(y, img.get_height() - 1), Color(0.95, 0.78, 0.25))
				if y + 1 < img.get_height():
					img.set_pixel(x, y + 1, Color(0.35, 0.25, 0.05))
	else:
		img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.95, 0.85, 0.3) if key == "pip:1" else Color(0.15, 0.15, 0.15, 0.85))
	return art.atlas.add(key, img)


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


## G4 (THREAD): reads ONLY mv.snap (sim/render_snap.gd) + immutable content, so it runs every
## frame even while the next sim step is in flight on the worker. The vis_* lists handed to the
## overlays hold live entity dicts, so they are rebuilt only when no step is in flight (the
## overlays redraw only then, too).
func refresh() -> void:
	var sn: Dictionary = mv.snap
	if sn.is_empty():
		return
	var live: bool = mv.world_readable()
	var ents: Dictionary = mv._world.entities if live else {}
	var pf: int = mv.player_fid
	var z: float = mv.camera.zoom.x if mv.camera != null else 1.0
	lod = 2 if z < LOD_FAR else (1 if z < LOD_MID else 0)
	var far := lod == 2
	var t: float = mv.anim_time()
	if _atlas_at > 0.0 and t >= _atlas_at:  # G6.1 (ANIMC61): env ANIM61_ATLAS_AT=<s> prints the live atlas once
		_atlas_at = -1.0
		var st: Dictionary = art.atlas.stats()
		print("ANIM61_ATLAS pages=%d MB=%.1f units_drawn=%d t=%.1f" % [int(st.pages), float(st.bytes) / 1e6, _units_drawn, t])
	var alpha: float = mv._alpha
	var vr := _view_rect()
	var mem: Dictionary = (sn.get("memory", {}) as Dictionary).get(pf, {})
	var statics: Dictionary = sn.statics
	# far LOD draws un-interpolated icons, so the list only changes with the sim tick, the
	# camera, the fog or the selection: reuse the canvas commands from the last rebuild.
	if far:
		var key := [int(sn.tick), get_viewport().get_canvas_transform(), get_viewport_rect().size,
			mv.fog_layer.rebuilds if mv.fog_layer != null else 0, int(sn.entity_count), mem.size(), live]
		if key == _far_key:
			skipped += 1
			return
		_far_key = key
	else:
		_far_key = []
	if live:
		vis_units.clear()
		vis_sp.resize(0)
		vis_air.resize(0)
		vis_bld.clear()
	var facs: Dictionary = sn.factions
	for fid in facs:
		var c: Color = mv.team_color(int(fid))
		_team[fid] = c
		_ck[fid] = c.to_html()
		_fac[fid] = String(facs[fid].get("faction_def", ""))
	var neutral: Color = mv.team_color(-1)
	var my_team := int((facs.get(pf, {}) as Dictionary).get("team", pf))
	var hid_spot: Dictionary = sn.get("hid_spot", {})
	var mw := int(sn.map_w)
	var fog: Dictionary = mv.fog_of(pf)
	var vis: PackedByteArray = fog.get("visible", PackedByteArray())
	var ally_vis: Array = []
	for a in mv._ally_fids:
		var af: Dictionary = mv.fog_of(a)
		if not af.is_empty():
			ally_vis.append(af.visible)
	var inv_z := 1.0 / maxf(z, 0.05)
	var ec: Dictionary = art._ec
	var n_u: int = int(sn.n)
	_n = 0
	g4b_fx_drawn = 0
	_reserve(n_u + statics.size() + decor_count + mem.size() + 16)
	# decor (static, bucketed by chunk)
	var t_sub := Time.get_ticks_usec()
	_sync_burnt(sn.get("burnt", PackedByteArray()))
	var any_burnt := not burnt.is_empty()
	# G6 (VIEW6): height lift per cell (empty on flat maps / before ELEV-VIEW publishes level_px)
	var hl_t := _height_lift(sn)
	var hl_n := hl_t.size()
	# CR 822: ramp cells slope, so a unit on a ramp takes the exact ViewUtil.ground_lift at its point (plain
	# cells are flat: the per-cell table is exact there and cheaper)
	var hm6: Dictionary = mv.terrain_layer.height_map() if hl_n > 0 and mv.terrain_layer != null and mv.terrain_layer.has_method("height_map") else {}
	var rp6: PackedByteArray = hm6.get("ramps", PackedByteArray())
	var rp6_n := rp6.size() if rp6.size() == hl_n else 0
	var g6u: Dictionary = sn.get("g6u", {})
	var has_g6 := not g6u.is_empty()
	var gc6 := {"art_override": 0, "disguised": 0, "cloaked": 0, "submerged": 0, "garrisoned": 0, "lifted": 0, "command": 0}
	g6_counts = gc6
	for ck in _decor:
		if not vr.intersects(_decor_rect[ck]):
			continue
		var arr: Array = _decor[ck]
		for k in range(0, arr.size(), DSTRIDE):
			if any_burnt and burnt.has(arr[k + 4]):
				continue  # G4b: the tree on this cell burnt down
			var p: Vector2 = arr[k]
			var dl := 0.0
			if hl_n > 0:
				var dci: int = arr[k + 4]
				if dci >= 0 and dci < hl_n:
					dl = hl_t[dci]
			_push(0, p.y, arr[k + 1], arr[k + 2], p + (arr[k + 3] as Vector2) - Vector2(0, dl), (arr[k + 2] as Rect2).size, Color.WHITE)
	for ck in _flat:
		if not vr.intersects(_flat_rect[ck]):
			continue
		var arr: Array = _flat[ck]
		for k in range(0, arr.size(), DSTRIDE):
			var p: Vector2 = arr[k]
			# y = -Y_OFF: sort key 0 -> under every unit, building and standing decor
			_push(0, -Y_OFF, arr[k + 1], arr[k + 2], p + (arr[k + 3] as Vector2), (arr[k + 2] as Rect2).size, Color.WHITE)
	ViewUtil.prof_add("p_e1_decor", t_sub)
	t_sub = Time.get_ticks_usec()
	var ids: PackedInt32Array = sn.ids
	var pos_a: PackedVector2Array = sn.pos
	var prev_a: PackedVector2Array = sn.prev
	var fac_a: PackedFloat32Array = sn.facing
	var def_a: PackedInt32Array = sn.def
	var defs: PackedStringArray = sn.defs
	var own_a: PackedInt32Array = sn.owner
	var flg_a: PackedInt32Array = sn.flags
	var hp_a: PackedFloat32Array = sn.get("hp", PackedFloat32Array())  # G6.1 (ANIMC61): damaged frames
	# ART-T CR: HILL / CLIFF tiles are drawn raised (terrain_layer._raise[code] px): lift ground units
	var raise_v = mv.terrain_layer.get("_raise") if mv.terrain_layer != null else null
	var raise: Dictionary = raise_v if raise_v is Dictionary else {}
	if raise_v is PackedInt32Array:  # G6: terrain_layer keeps _raise as a per-code PackedInt32Array now
		for code in (raise_v as PackedInt32Array).size():
			if raise_v[code] != 0:
				raise[code] = raise_v[code]
	var terr: PackedByteArray = sn.get("terrain", PackedByteArray()) if not raise.is_empty() else PackedByteArray()
	var terr_w: PackedByteArray = sn.get("terrain", PackedByteArray())  # G5 (VIEW5-2): amphibians swim on water
	# G5 (VIEW5) side tables (sparse; empty dicts in a G4 match)
	var g5air: Dictionary = sn.get("air", {})
	var has_air := not g5air.is_empty()
	var squad: Dictionary = sn.get("squad", {})
	var has_sq := not squad.is_empty()
	var sling: Dictionary = sn.get("sling", {})
	var gc5 := {"shadows": 0, "lifted": 0, "wounded": 0, "markers": 0, "red_cross": 0, "trails": 0, "slung": 0,
		"strips": 0, "sinking": 0, "tactical": 0, "squads": 0, "aboard": 0,
		"wake_sheets": 0, "sink_sheets": 0, "swim": 0, "ramp": 0}
	g5_counts = gc5
	# G6.1 (ANIMA61): motion layer on while the last frame drew <= MOTION_CAP units (2k-on-screen stays cheap)
	motion_on = not far and not g61_off and _units_drawn <= MOTION_CAP
	var gc61 := {"motion": 0, "a61": 0, "flipped": 0, "corpses": 0, "chevrons": 0, "pips": 0, "veh": 0, "turret": 0, "track": 0, "bank": 0, "recoil": 0, "g7": 0, "roof": 0, "roof_in": 0}
	g61_counts = gc61
	# G7 (LOOK7): sparse per-unit display states (render_snap g7u: wounds, care, panic, gait, sectors, herringbone)
	var g7u: Dictionary = sn.get("g7u", {})
	var has_g7 := not g7u.is_empty()
	var stick := int(sn.get("tick", 0))
	var units_drawn := 0
	var pframe := Engine.get_process_frames()
	_bay_crafts(n_u, far, defs, def_a, flg_a, pos_a, fac_a, ids)
	var has_cr := not _crafts.is_empty()
	bay_drawn = 0
	for i in n_u:
		var id: int = ids[i]
		if flg_a[i] & RenderSnap.FLAG_ABOARD:
			gc5.aboard += 1
			continue  # G5: wounded aboard an evac carrier ride inside it (hidden)
		var ow: int = own_a[i]
		var raw: Vector2 = pos_a[i]
		var pos := raw
		if not far:
			var pp: Vector2 = prev_a[i]
			if pp.distance_squared_to(raw) < 4.0:
				pos = pp.lerp(raw, alpha)
		var sp := Vector2((pos.x - pos.y) * 32.0, (pos.x + pos.y) * 16.0)
		if not vr.has_point(sp):
			continue
		if not terr.is_empty() and (flg_a[i] & RenderSnap.FLAG_AIR) == 0:
			var ti := floori(pos.y) * mw + floori(pos.x)
			if ti >= 0 and ti < terr.size():
				sp.y -= float(raise.get(int(terr[ti]), 0))
		var hl := 0.0
		if hl_n > 0:
			var hci := floori(pos.y) * mw + floori(pos.x)
			if hci >= 0 and hci < hl_n:
				hl = hl_t[hci]
				if rp6_n > 0 and rp6[hci] != 0:
					hl = ViewUtil.ground_lift(hm6, pos)
				sp.y -= hl
				if hl != 0.0:
					gc6.lifted += 1
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
		var fl: int = flg_a[i]
		# G4b: a concealed sniper is drawn for enemies only while their team spots it
		if fl & RenderSnap.FLAG_HID and ow != pf and not mv._ally_fids.has(ow) and not (hid_spot.get(id, []) as Array).has(my_team):
			continue
		var dname: String = defs[def_a[i]]
		var mod6 := Color.WHITE
		if fl & RenderSnap.FLAG_G6 and has_g6:
			# G6 (VIEW6): garrisoned units ride inside (pips on the building); art override (e.art_def) and
			# the mimic disguise for this viewer; own cloaked / submerged units translucent
			var g6e = g6u.get(id)
			if G6Vis.hidden_inside(g6e):
				# G7 (LOOK7): roof cut away (own / allied troops clearing inside): the men inside are drawn
				var gb = statics.get(int(g6e.get("gar", -1))) if g6e is Dictionary else null
				if gb is Dictionary and roof_open_for(gb.get("roof_open"), pf, mv._ally_fids) and (ow == pf or mv._ally_fids.has(ow)):
					sp += Vector2(float((id * 37) % 25) - 12.0, float((id * 53) % 13) - 6.0)
					gc61.roof_in += 1
				else:
					gc6.garrisoned += 1
					continue
			var an := G6Vis.art_def(g6e, pf, dname)
			if an != dname:
				if g6e.has("dis") and (g6e.dis as Dictionary).has(pf):
					gc6.disguised += 1
				else:
					gc6.art_override += 1
				dname = an
			mod6 = G6Vis.modulate(g6e, ow == pf or mv._ally_fids.has(ow))
			if g6e != null and int(g6e.get("cloak", 0)) > 0:
				gc6.cloaked += 1
			elif g6e != null and g6e.has("sub"):
				gc6.submerged += 1
		if live:
			var le = ents.get(id)
			if le != null:
				if fl & RenderSnap.FLAG_AIR:
					vis_air.append(vis_units.size())
				vis_units.append(le)
				vis_sp.append(sp)
		if far:
			var ic: Array = icons.icon(art.atlas, String(_fac.get(ow, "")), icons.class_of(dname))
			var isz: Vector2 = (ic[1] as Vector2) * inv_z
			_push(2, sp.y, art.atlas.page_of(ic[0]), art.atlas.rect_of(ic[0]), sp + (ic[2] as Vector2) * inv_z, isz, _team.get(ow, neutral))
			continue
		if XL_REMAP and dname == "a_vtol_dropship":
			dname = "g7_a_vtol_dropship_xl"  # G7 (CNFAC7-2): the upgraded, enlarged VTOL dropship
		if BAY_ART.has(dname):
			var gb = g7u.get(id) if has_g7 else null
			if not (gb is Dictionary and (gb as Dictionary).has("bay")):
				gb = {"bay": "closed"} if (fl & RenderSnap.FLAG_LANDED) != 0 else null   # landed, ramp up
			if gb != null and _push_bay(id, dname, ow, fac_a[i], gb, sp, hl, float(stick) + alpha, t, mod6, neutral):
				continue
		# hot path: inline frame choice from the per-id art cache (see BatchArt.resolve_unit)
		var sq_al: int = int(squad.get(id, 0)) if has_sq else 0
		var c = ec.get(id)
		if c == null or c[1] != ow or c[0] != dname or c[16] != sq_al:
			c = art.cache_unit(_proxy(id, dname, ow, fac_a[i], fl, sq_al), _team.get(ow, neutral), String(_ck.get(ow, "x")))
		if sq_al > 0:
			gc5.squads += 1
		units_drawn += 1
		var a61: Dictionary = c[31] if not g61_off else _no61
		var bits := 0
		var gv = g7u.get(id) if has_g7 else null
		if fl & RenderSnap.FLAG_MOVING:
			bits |= Motion.P_MOVING
		if fl & RenderSnap.FLAG_FIRING:
			bits |= Motion.P_FIRING
		var mcls := -1
		if motion_on and c[2] != -2:
			if live and (pframe + id) % 8 == 0:
				var pe = ents.get(id)
				if pe != null:
					_refresh_post(id, pe)
			bits |= int(_post.get(id, 0))
			mcls = int(_mcls.get(dname, -1))
			if mcls < 0:
				mcls = Motion.class_for(not a61.is_empty() or (ArtCatalog.manifest().get("infantry", {}) as Dictionary).has(dname),
					bool(c[12]), (fl & RenderSnap.FLAG_SHIP) != 0, dname)
				_mcls[dname] = mcls
			if mcls == Motion.CLS_INF and motion.speed(id) >= RUN_SPEED:
				bits |= Motion.P_RUN
			motion.step(id, mcls, pos, fac_a[i] if gv == null else Motion.g7_facing(gv, fac_a[i], (fl & RenderSnap.FLAG_MOVING) != 0), bits, t)
			var mo: Vector2 = motion.out_off
			var mpx: Vector2 = motion.out_px
			if c[30] >= 0 and fl & RenderSnap.FLAG_MOVING:
				# G6.1: officers / leaders walk slightly ahead of their men
				var of: float = motion.out_face
				mpx += Vector2(cos(of) - sin(of), (cos(of) + sin(of)) * 0.5).normalized() * 2.0
			sp += Vector2((mo.x - mo.y) * 32.0, (mo.x + mo.y) * 16.0) + mpx
			motion.mark_screen(id, sp)
			if motion.out_flash > 0.0:
				var fk: float = motion.out_flash
				mod6 = Color(mod6.r * (1.0 + 0.9 * fk), mod6.g * (1.0 + 0.6 * fk), mod6.b * (1.0 + 0.5 * fk), mod6.a)
			gc61.motion += 1
		var g7c := -1
		if gv != null and not a61.is_empty():
			g7c = Motion.g7_col(a61, gv, bits, t, Motion.seed_of(id), stick)
		var pg: int = c[2]
		var ad = g5air.get(id) if has_air else null
		if pg == -2:
			# no sheet yet: ArtCatalog.placeholder_for silhouette (G5 scaffold), lifted like the art would be
			var lz := 0
			if ad != null:
				lz = _g5_lift(dname, id, ad, fl, fac_a[i], t, gc5, sp)
				sp.y -= _lift
			art.resolve_unit(_proxy(id, dname, ow, fac_a[i], fl, sq_al), _team.get(ow, neutral), String(_ck.get(ow, "x")), t)
			if art.out_page >= 0:
				_push(lz, sp.y, art.out_page, art.out_src, sp + art.out_off, art.out_src.size, Color.WHITE)
			if fl & (RenderSnap.FLAG_WOUNDED | RenderSnap.FLAG_EVAC):
				_g5_markers(sp, fl, id, t, neutral, gc5)
			continue
		if fl & RenderSnap.FLAG_WOUNDED and c[17] < 0 and g7c < 0:
			# G1-G4 human infantry: the wounded pose comes from effects g5_wounded_a/b (team mask)
			if art.resolve_fx(G5Art.wounded_fx(String(_fac.get(ow, ""))), _team.get(ow, neutral), String(_ck.get(ow, "x")), int(t * 3.0 + id * 0.3)):
				_push(0, sp.y, art.out_page, art.out_src, sp + art.out_off, art.out_src.size, Color.WHITE)
				gc5.wounded += 1
			_g5_markers(sp, fl, id, t, neutral, gc5)
			continue
		var fi := 0
		if g7c >= 0:
			fi = g7c   # G7 (LOOK7): wound / care / panic / gait / back-off / peek pose
			gc61.g7 += 1
		elif fl & RenderSnap.FLAG_WOUNDED:
			fi = c[17]
			gc5.wounded += 1
		elif fl & RenderSnap.FLAG_FIRING:
			fi = c[20] if (fl & RenderSnap.FLAG_DRONE and c[20] >= 0) else c[7]
			if not a61.is_empty():  # G6.1: fire standing / crouched (suppressed) / prone (pinned), cosmetic reload
				fi = Motion.inf_col(a61, bits, t, Motion.seed_of(id), motion.firing_for(id), float(_fat.get(id, 0.0))) if mcls >= 0 else Motion.inf_col(a61, bits, t, (id % 61) * 0.0164)
				gc61.a61 += 1
		elif ad != null and c[21] >= 0 and fl & RenderSnap.FLAG_LANDED:
			# G5 (ART-AIR ground_frames): parked in a hangar / on a pad, else landed in the open
			fi = c[21] if String(ad.ph) == "parked" or (c[22] < 0) else c[22]
		elif ad != null and not (fl & RenderSnap.FLAG_LANDED) and not (c[24] as Array).is_empty():
			# G5 (ART-AIR anim): rotor / prop frames cycle at anim_fps while airborne
			var an: Array = c[24] if (fl & RenderSnap.FLAG_MOVING) or (c[23] as Array).is_empty() else c[23]
			fi = an[int(t * float(c[25]) + id * 0.37) % an.size()]
		elif c[27] >= 0 and G5Art.on_water(terr_w, pos, mw):
			# G5 (VIEW5-2, ART-NAV specials): amphibian afloat, swim / swim_move frames
			fi = c[28] if (fl & RenderSnap.FLAG_MOVING and c[28] >= 0) else c[27]
			gc5.swim += 1
		elif fl & RenderSnap.FLAG_EVAC and c[19] >= 0:
			fi = c[19]  # G5: medic team carrying / ambulance loading
		elif fl & RenderSnap.FLAG_TACTICAL and c[18] >= 0 and not (fl & RenderSnap.FLAG_MOVING):
			fi = c[18]
			gc5.tactical += 1
		else:
			# G4b poses (ART-U-3): mortar "deployed", engineer "work", carrier "unload"; -1 = no column
			var pz := -1
			if fl & POSE_MASK:
				pz = c[13] if fl & RenderSnap.FLAG_DEPLOYED else (c[14] if fl & RenderSnap.FLAG_WORK else c[15])
				if fl & RenderSnap.FLAG_UNLOAD and c[29] >= 0 and ((fl >> 8) & 0xFF) > 0:
					pz = c[29]  # G5 (VIEW5-2, ART-NAV specials): ramp half down while cargo is still aboard
					gc5.ramp += 1
			if pz >= 0:
				fi = pz
			elif not a61.is_empty() and not (c[30] >= 0 and not (fl & RenderSnap.FLAG_MOVING) and (bits & (Motion.P_PINNED | Motion.P_SUPPRESSED)) == 0 and int(t * 0.5 + id * 0.61) % 4 == 0):
				# G6.1: walk / run / crawl cycles (phase-offset per soldier), prone / crouch, idle breathing
				fi = Motion.inf_col(a61, bits, t, Motion.seed_of(id), 0.0, float(_fat.get(id, 0.0))) if mcls >= 0 else Motion.inf_col(a61, bits, t, (id % 61) * 0.0164)
				gc61.a61 += 1
			elif fl & RenderSnap.FLAG_MOVING:
				var ph := int(t * 6.0 + id * 0.37)
				if c[8]:
					fi = c[9] if ph % 2 == 0 else c[10]
				else:
					fi = c[11] if ph % 2 == 0 else 0
			elif c[30] >= 0 and int(t * 0.5 + id * 0.61) % 4 == 0:
				fi = c[30]  # G6 (ART-G6b s3.2): an idle officer / command node gives orders 2 s in every 8
				gc6.command += 1
		if fi < 0:
			fi = 0
		# G6.1 (ANIMC61): vehicle anim61 frames (track cycle, recoil, bank, burner, pulse, damaged) and the separate
		# mbt / ifv turret aimed at the last shot target. Only while the motion layer runs (<= MOTION_CAP drawn).
		var tur: Array = []
		var v61: Dictionary = c[32]
		if mcls >= 0 and not v61.is_empty():
			var vmv: bool = (fl & RenderSnap.FLAG_MOVING) != 0 and (fi == c[11] or fi == 0 or (ad != null and (c[24] as Array).has(fi)))
			var vid: bool = not vmv and fi == 0
			var hpf: float = hp_a[i] if i < hp_a.size() else 1.0
			var vfire: bool = fi == c[7] and (fl & RenderSnap.FLAG_FIRING) != 0
			var fb := fi
			fi = VehAnim61.pick(v61, fi, vid, vmv, motion, id, hpf, t)
			gc61.veh += 1
			if fi != fb:
				if fi == int(v61.get("bank_l", -2)) or fi == int(v61.get("bank_r", -2)):
					gc61.bank += 1
				elif fi == int(v61.get("recoil", -2)):
					gc61.recoil += 1
				elif v61.has("track") or v61.has("move"):
					gc61.track += 1
			if v61.has("turret") and (vid or vmv or vfire) and fi != int(v61.get("damaged", -2)):
				var hc: int = int(v61.get("hull_move" if vmv else "hull_idle", -1))
				var ts: Array = art.turret_src(v61.turret, _team.get(ow, neutral), String(_ck.get(ow, "x")))
				if hc >= 0 and not ts.is_empty():
					fi = hc
					var hrow := posmod(int(round(motion.out_face * FACING_INV)), 8)
					var tcol := 2 if motion.recoil(id) > VehAnim61.RECOIL else (1 if vfire else 0)
					var tsz := Vector2(ts[2], ts[3])
					tur = [ts[0], (ts[1] as Vector2) + Vector2(tcol, motion.aim_row(id, sp, hrow)) * tsz, ts[4], tsz]
		var row := posmod(int(round((motion.out_face if mcls >= 0 else fac_a[i]) * FACING_INV)), 8)
		var fsz := Vector2(c[4], c[5])
		var layer := 0
		if ad != null:
			layer = _g5_lift(dname, id, ad, fl, fac_a[i], t, gc5, sp)  # G5: altitude by flight phase + shadow
			sp.y -= _lift
		elif c[12]:
			sp.y -= G3View.air_lift({"def": dname, "id": id}, t)  # G3a: air units fly above their ground point
			layer = 1
		if fl & RenderSnap.FLAG_SHIP and fl & RenderSnap.FLAG_MOVING and not (c[26] as Dictionary).is_empty() and (c[27] < 0 or G5Art.on_water(terr_w, pos, mw)):
			# G5 (VIEW5-2, ART-NAV): wake sheet under the hull (fx_layer skips its line wake for these defs)
			var wk: Dictionary = c[26]
			if art.resolve_sheet(wk, int(t * float(wk.get("fps", 6)) + id * 0.37) % maxi(1, int(wk.get("frames", 3))), row):
				_push(layer, sp.y - 3.0, art.out_page, art.out_src, sp + art.out_off, art.out_src.size, Color(1, 1, 1, 0.85))
				gc5.wake_sheets += 1
		# inlined _push (capacity reserved above; G5 extras per unit - shadow, trail, markers, sling - may outgrow it)
		var ii := _n
		if ii >= _page.size():
			_reserve(ii * 2 + 16)
		# G6: sort by ground depth (sp.y + height lift) so units on a ridge order correctly against the valley
		var ky := int(sp.y + hl)
		if has_cr and layer == 0:
			ky = _craft_y(id, ky) if BAY_ART.has(dname) else bay_sort_y(pos, ky, _crafts)  # G7 (CNFAC7-2, CR seq 1193)
		_keys[ii] = layer * LAYER_MUL + (ky + Y_OFF) * IDX_MUL + ii
		var tb61: Vector2 = Vector2(-1, -1) if fi < int(c[35]) else (c[38] as PackedVector2Array)[fi * 8 + row]
		if tb61.x >= 0.0:
			# G6.1: anim61 column in the split block B: cropped cell (ANIMC61), mirrored rows drawn with a negative width
			var k61 := fi * 8 + row
			var dz: Vector2 = (c[39] as PackedVector2Array)[k61]
			_page[ii] = c[33]
			_src[ii] = tb61
			_dst[ii] = sp + (c[40] as PackedVector2Array)[k61]
			_dsz[ii] = dz
			_size[ii] = Vector2(absf(dz.x), dz.y)
			if dz.x < 0.0:
				gc61.flipped += 1
		else:
			_page[ii] = pg
			_src[ii] = (c[3] as Vector2) + Vector2(fi if fi < int(c[35]) else 0, row) * fsz
			_dst[ii] = sp + (c[6] as Vector2)
			_dsz[ii] = fsz
			_size[ii] = fsz
		_mod[ii] = mod6
		_n = ii + 1
		if not tur.is_empty():  # G6.1 (ANIMC61): turret over its hull (same depth, later index sorts after)
			_push(layer, sp.y + hl, tur[0], Rect2(tur[1], tur[3]), sp + (tur[2] as Vector2), tur[3], mod6)
			gc61.turret += 1
		if lod == 0 and motion_on:
			_push_marks(id, sp, c, layer, hl, gc61)
		if fl & RenderSnap.FLAG_SLUNG:
			_g5_slung(sling.get(id, []), id, ow, fac_a[i], sp, t, gc5)
		if fl & (RenderSnap.FLAG_WOUNDED | RenderSnap.FLAG_EVAC):
			_g5_markers(sp, fl, id, t, neutral, gc5)
	_units_drawn = units_drawn
	if not far:
		_push_corpses(vr, t, gc61)
	# buildings, resources, wrecks, mines, charges (light dict copies in the snapshot)
	for id in statics:
		var e: Dictionary = statics[id]
		var kind: String = e.kind
		var ow := int(e.owner)
		var gp: Vector2 = e.pos
		var gs := Vector2((gp.x - gp.y) * 32.0, (gp.x + gp.y) * 16.0)
		var gc := Vector2i(floori(gp.x), floori(gp.y))
		if not vr.has_point(gs):
			if kind == "wreck" and not _seen_wrecks.has(id) and mv.cell_visible(gc):
				_seen_wrecks[id] = true
			continue
		var mod := Color.WHITE
		var sdy := 0.0
		var gd := gs  # G6: draw origin = ground point raised by the cell's height lift (gs.y stays the sort depth)
		if hl_n > 0:
			var sci := gc.y * mw + gc.x
			if sci >= 0 and sci < hl_n:
				gd.y -= hl_t[sci]
		match kind:
			"building":
				if ow != pf and not mv.entity_visible(e):
					if not mem.has(id):
						continue
					mod = GHOST_MOD
				elif live:
					var le = ents.get(id)
					if le != null:
						vis_bld.append(le)
				if roof_open_for(e.get("roof_open"), pf, mv._ally_fids):
					mod = ROOF_CUT_MOD   # G7 (LOOK7): roof cut away while our troops clear it (they draw inside)
					gc61.roof += 1
			"resource":
				if not mv.cell_explored(gc):
					continue
			"wreck":
				if not _seen_wrecks.has(id):
					if not mv.cell_visible(gc):
						continue
					_seen_wrecks[id] = true
				var sk = (sn.get("sinking", {}) as Dictionary).get(id)
				if sk != null:
					# G5 (NAVAL): a sinking ship wreck settles and fades as its sink timer runs out
					var kk: float = sk.k
					mod = Color(1, 1, 1, 0.3 + 0.7 * kk)
					sdy = (1.0 - kk) * 10.0  # (water is never lifted, so this replaces the height term)
					gc5.sinking += 1
					# G5 (VIEW5-2, ART-NAV): vehicles[def].sink columns sink_0..3 from the timer (1 - k)
					var sks = G5Art.unit_spec(String(e.get("def", ""))).get("sink")
					if sks is Dictionary and art.resolve_sheet(sks, G5Art.sink_col(kk, (sks.get("frames", []) as Array).size()),
							posmod(int(round(float(e.get("facing", 0.0)) * FACING_INV)), 8)):
						_push(0, gs.y, art.out_page, art.out_src, gs + art.out_off, art.out_src.size, Color(1, 1, 1, 0.55 + 0.45 * kk))
						gc5.sink_sheets += 1
						continue
			"mine", "charge":
				# G4b: hidden from enemies unless detected (mines) or planted on our side's target (charges)
				if not g4b_static_visible(e, statics, pf, my_team, mv._ally_fids):
					continue
				# ART-U-3 effects: own/allied mine + every charge tinted by the owner (mask), 2-frame
				# blink; an enemy mine we only see because it was detected uses mine_detected (untinted)
				var nm := kind
				if kind == "mine" and ow != pf and not mv._ally_fids.has(ow):
					nm = "mine_detected"
				if art.resolve_fx(nm, _team.get(ow, neutral), String(_ck.get(ow, "x")), int(t * 2.0 + id * 0.31)):
					_push(0, gs.y, art.out_page, art.out_src, gd + art.out_off, art.out_src.size, Color.WHITE)
					g4b_fx_drawn += 1
					continue
		var col: Color = _team.get(ow if kind != "wreck" else int(e.get("from_owner", -1)), neutral)
		art.resolve_static(e, col, String(_ck.get(ow, "x")))
		if art.out_page >= 0:
			_push(0, gs.y, art.out_page, art.out_src, gd + art.out_off + Vector2(0, sdy), art.out_src.size, mod)
	_push_strips(sn, vr, pf, mem, statics, gc5)
	ViewUtil.prof_add("p_e2_ents", t_sub)
	t_sub = Time.get_ticks_usec()
	_push_fire(sn, vr, mw, vis, ally_vis, t, neutral)
	_push_ghosts(statics, mem, vr, neutral)
	art.atlas.flush()
	_sorted = _keys.slice(0, _n)
	_sorted.sort()
	ViewUtil.prof_add("p_e3_sort", t_sub)
	drawn = _n
	queue_redraw()


## G6.1: rank chevron (REAL61) and bearer ammo pips (BEARER61) above a drawn unit (close zoom only).
func _push_marks(id: int, sp: Vector2, c: Array, layer: int, hl: float, gc61: Dictionary) -> void:
	var top := sp.y + (c[6] as Vector2).y
	var r := int(_chev.get(id, 0))
	if r > 0:
		var ck := "chev:%d" % clampi(r, 1, 4)
		var pgc := _mark(ck)
		var rc: Rect2 = art.atlas.rect_of(ck)
		_push(layer, sp.y + hl + 1.0, pgc, rc, Vector2(sp.x - 3.0, top - 2.0), rc.size, Color.WHITE)
		gc61.chevrons += 1
	var pp := int(_pips.get(id, 0))
	if pp > 0:
		for k in 3:
			var pk := "pip:1" if k < pp - 1 else "pip:0"
			var pgp := _mark(pk)
			_push(layer, sp.y + hl + 1.0, pgp, art.atlas.rect_of(pk), Vector2(sp.x - 4.0 + k * 3.0, top - 5.0), Vector2(2, 2), Color.WHITE)
		gc61.pips += 1


## G6.1: corpses (Motion.kill): die_0..die_2, then lie and fade; drawn just under living units at the same depth.
func _push_corpses(vr: Rect2, t: float, gc61: Dictionary) -> void:
	motion.prune(t)
	for cp in motion.corpses:
		var csp: Vector2 = cp[2]
		if not vr.has_point(csp):
			continue
		var cc: Array = cp[1]
		var age := t - float(cp[4])
		var dcols: Array = (cc[31] as Dictionary).get("die", [])
		if dcols.is_empty():
			continue
		art.frame_src(cc, int(dcols[Motion.corpse_frame(age)]), int(cp[3]))
		if art.out_page < 0:
			continue
		var dst: Vector2 = csp + art.out_doff  # G6.1 (ANIMC61): cropped cell offset / signed size from frame_src
		var dsz: Vector2 = art.out_dsz
		_push(0, csp.y - 1.0, art.out_page, art.out_src, dst, dsz, Color(1, 1, 1, Motion.corpse_alpha(age)))
		gc61.corpses += 1


## Minimal unit dict for the art cache / fallback sprite (built only on a cache miss).
func _proxy(id: int, dname: String, ow: int, facing: float, fl: int, sq_al: int = 0) -> Dictionary:
	return {"id": id, "kind": "unit", "def": dname, "owner": ow, "facing": facing, "squad_alive": sq_al,
		"moving": (fl & RenderSnap.FLAG_MOVING) != 0, "firing": 1 if (fl & RenderSnap.FLAG_FIRING) != 0 else 0,
		"deployed": (fl & RenderSnap.FLAG_DEPLOYED) != 0, "working": (fl & RenderSnap.FLAG_WORK) != 0,
		"unloading": (fl & RenderSnap.FLAG_UNLOAD) != 0}


## G4b (UI4B-3): match_view calls this for TerrainChanged{cause:"fire"} (burnt-out forest -> DIRT).
func on_burnt(cells: Array, mw: int) -> void:
	for c in cells:
		var v := Vector2i(c)
		burnt[v.y * mw + v.x] = true
	_far_key = []


## G4b (UI4B-3): burnt_ground variants (flat, under everything) on burnt cells we have explored,
## and the fire_forest loop on burning cells (snap.fires) we or an ally can see right now.
func _push_fire(sn: Dictionary, vr: Rect2, mw: int, vis: PackedByteArray, ally_vis: Array, t: float, neutral: Color) -> void:
	fires_drawn = 0
	burnt_drawn = 0
	if mw <= 0:
		return
	for k in burnt:
		var ci: int = k
		var x := ci % mw
		var y := ci / mw
		var sp := Vector2((x - y) * 32.0, (x + y + 1) * 16.0)  # cell centre
		if not vr.has_point(sp) or not mv.cell_explored(Vector2i(x, y)):
			continue
		if art.resolve_fx("burnt_ground", neutral, "-", ArtCatalog._ihash(x, y, 53) % 3):
			_push(0, -Y_OFF, art.out_page, art.out_src, sp + art.out_off, art.out_src.size, Color.WHITE)
			burnt_drawn += 1
	var fires: PackedInt32Array = sn.get("fires", PackedInt32Array())
	for ci in fires:
		var x := ci % mw
		var y := ci / mw
		var sp := Vector2((x - y) * 32.0, (x + y + 1) * 16.0)
		if not vr.has_point(sp):
			continue
		if not vis.is_empty() and ci < vis.size() and vis[ci] == 0:
			var seen := false
			for av in ally_vis:
				if ci < (av as PackedByteArray).size() and (av as PackedByteArray)[ci] == 1:
					seen = true
					break
			if not seen:
				continue
		if art.resolve_fx("fire_forest", neutral, "-", int(t * 8.0) + ArtCatalog._ihash(x, y, 59) % 3):
			# y + 2: in front of this cell's tree, still behind units further south
			_push(0, sp.y + 2.0, art.out_page, art.out_src, sp + art.out_off, art.out_src.size, Color.WHITE)
			fires_drawn += 1


## G4b mine / charge visibility for the local side (entity layer + g4b_overlay share it):
## own or allied always; an enemy mine once our team detected it (mine.seen); an enemy charge
## when its target belongs to us or an ally (the defender sees the charge on his own wall).
static func g4b_static_visible(e: Dictionary, statics: Dictionary, pf: int, team: int, allies: Array) -> bool:
	var ow := int(e.owner)
	if ow == pf or allies.has(ow):
		return true
	if String(e.kind) == "charge":
		var t = statics.get(int(e.get("target", -1)))
		if t != null:
			var to := int(t.owner)
			if to == pf or allies.has(to):
				return true
	return _detected(e, pf, team)


static func _detected(e: Dictionary, pf: int, team: int = -1) -> bool:
	var d = e.get("detected")
	if d is Dictionary or d is Array:
		return d.has(pf)
	var s = e.get("seen")  # G4b (UNITS g4b_mech): team ids that detected this mine (UI4B)
	if (s is Array or s is Dictionary) and team >= 0 and s.has(team):
		return true
	return d is bool and d


## Remembered enemy buildings that no longer exist (destroyed out of sight): greyed ghosts.
func _push_ghosts(statics: Dictionary, mem: Dictionary, vr: Rect2, neutral: Color) -> void:
	for eid in mem:
		if statics.has(eid):
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
		if not mem.has(eid) or statics.has(eid):
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


# ---------------------------------------------------------------- G5 (VIEW5)
var _strip_cache: Dictionary = {}   # field id -> [signature, [[screen pos, page, src, off], ...]]


## w.map.burnt (UNITS5, saved + hashed) reaches us through the snapshot: merge it into `burnt`, so a
## loaded save shows its burnt ground too (closes the G4b presentation-only KNOWN GAP).
func _sync_burnt(arr: PackedByteArray) -> void:
	if arr.is_empty() or arr == _burnt_src:
		return
	_burnt_src = arr
	for k in G5Art.burnt_cells(arr):
		burnt[k] = true
	_far_key = []


## Altitude (snap.air[id].alt via G5Art.lift_px) for a G5 aircraft / drone: pushes its ground shadow
## (manifest shadow or a procedural ellipse) and, for a moving drone, the trail effect. Stores the lift
## in _lift (the caller raises the sprite by it) and returns the draw layer (1 = above ground items).
func _g5_lift(dname: String, id: int, ad: Dictionary, fl: int, facing: float, t: float, gc5: Dictionary, sp: Vector2) -> int:
	_lift = G5Art.lift_px(dname, float(ad.get("alt", 1.0)), id, t)
	if _lift <= 0.5:
		_lift = 0.0
		return 0
	gc5.lifted += 1
	if art.resolve_shadow(dname, posmod(int(round(facing * FACING_INV)), 8)):
		var a := clampf(1.1 - _lift / 80.0, 0.45, 1.0)
		_push(0, 1 - Y_OFF, art.out_page, art.out_src, sp + art.out_off, art.out_src.size, Color(1, 1, 1, a))  # over runways / burnt ground
		gc5.shadows += 1
	_g5_air_fx(dname, ad, fl, facing, t, gc5, sp)
	if fl & RenderSnap.FLAG_DRONE and fl & RenderSnap.FLAG_MOVING:
		var d := Vector2(cos(facing), sin(facing))
		var sd := Vector2((d.x - d.y) * 32.0, (d.x + d.y) * 16.0).normalized()
		if art.resolve_fx("g5_drone_trail", Color.WHITE, "-", int(t * 8.0) + id):
			var tp := sp - sd * 12.0 - Vector2(0, _lift)
			_push(1, sp.y - _lift - 1.0, art.out_page, art.out_src, tp + art.out_off, art.out_src.size, Color.WHITE)
			gc5.trails += 1
	return 1


## Wounded marker (blinking) over a wounded unit; red cross over a carrier with wounded aboard.
func _g5_markers(sp: Vector2, fl: int, id: int, t: float, neutral: Color, gc5: Dictionary) -> void:
	if fl & RenderSnap.FLAG_WOUNDED and art.resolve_fx("g5_wounded_marker", neutral, "-", int(t * 2.0 + id * 0.5)):
		_push(1, sp.y, art.out_page, art.out_src, sp + Vector2(0, -26) + art.out_off, art.out_src.size, Color.WHITE)
		gc5.markers += 1
	if fl & RenderSnap.FLAG_EVAC and art.resolve_fx("g5_red_cross", neutral, "-", 0):
		_push(1, sp.y, art.out_page, art.out_src, sp + Vector2(0, -34) + art.out_off, art.out_src.size, Color.WHITE)
		gc5.red_cross += 1


## Sling load: the first slung vehicle hangs under its (lifted) carrier, drawn just behind it.
func _g5_slung(defs: Array, id: int, ow: int, facing: float, sp: Vector2, t: float, gc5: Dictionary) -> void:
	if defs.is_empty():
		return
	art.resolve_unit(_proxy(-1 - id, String(defs[0]), ow, facing, 0), _team.get(ow, mv.team_color(-1)), String(_ck.get(ow, "x")), t)
	if art.out_page >= 0:
		_push(1, sp.y - 2.0, art.out_page, art.out_src, sp + Vector2(0, 18) + art.out_off, art.out_src.size, Color.WHITE)
		gc5.slung += 1


## Runway strips of every visible airfield (snap.airfields, ART-BLD airfield tiles), flat under
## everything; closed strips get the crater (or crater_repair while engineers are past half way)
## and the closed markers. Tile regions are cached per field until a strip opens / closes.
func _push_strips(sn: Dictionary, vr: Rect2, pf: int, mem: Dictionary, statics: Dictionary, gc5: Dictionary) -> void:
	var afs: Dictionary = sn.get("airfields", {})
	if afs.is_empty():
		return
	var rep_s := float(Content.rules().get("g5_air", {}).get("crater_repair_s", 15.0))
	for bid in afs:
		var af: Dictionary = afs[bid]
		var ow := int(af.owner)
		if ow != pf and not mv._ally_fids.has(ow):
			var st = statics.get(bid)
			if st == null or (not mv.entity_visible(st) and not mem.has(bid)):
				continue
		var sig := "%d|%d" % [int(af.get("facing_i", 0)), (af.strips as Array).size()]
		for s in af.strips:
			sig += "|%d%d" % [1 if bool(s.open) else 0, 1 if float(s.crater_t) < rep_s * 0.5 else 0]
		var c = _strip_cache.get(bid)
		if c == null or c[0] != sig:
			var lst: Array = []
			# G6 (VIEW6, airfield v2): apron pads under the slot squares first, then the runway tiles
			var tiles: Array = G6Vis.apron_tiles(af)
			gc5["apron"] = int(gc5.get("apron", 0)) + tiles.size()
			tiles.append_array(G5Art.strip_tiles(int(bid), af))
			# CR 822: runway / apron tiles sit on the drawn (raised) ground
			var hmS: Dictionary = mv.terrain_layer.height_map() if mv.terrain_layer != null and mv.terrain_layer.has_method("height_map") else {}
			for tl in tiles:
				var f: String = tl[1]
				var pv: Vector2 = tl[2]
				art._whole("strip|" + f, ArtCatalog._image(f), [pv.x, pv.y])
				if art.out_page >= 0:
					lst.append([ViewUtil.world_to_screen_h(hmS, tl[0]), art.out_page, art.out_src, art.out_off])
			c = [sig, lst]
			_strip_cache[bid] = c
		for it in c[1]:
			var p: Vector2 = it[0]
			if not vr.has_point(p):
				continue
			_push(0, -Y_OFF, it[1], it[2], p + (it[3] as Vector2), (it[2] as Rect2).size, Color.WHITE)
			gc5.strips += 1
	for bid in _strip_cache.keys():
		if not afs.has(bid):
			_strip_cache.erase(bid)



## ART-AIR effects tied to flight state: rotor wash on the ground under a hovering / low rotorcraft,
## afterburner behind a jet on its take-off roll or climbing out.
func _g5_air_fx(dname: String, ad: Dictionary, fl: int, facing: float, t: float, gc5: Dictionary, sp: Vector2) -> void:
	var ac := String(Content.unit(dname).get("aircraft", ""))
	if ac == "heli" or ac == "vtol":
		if (fl & RenderSnap.FLAG_MOVING) == 0 or float(ad.get("alt", 1.0)) < 1.0:
			if art.resolve_fx("g5_rotor_wash", Color.WHITE, "-", int(t * 10.0)):
				_push(0, 2 - Y_OFF, art.out_page, art.out_src, sp + art.out_off, art.out_src.size, Color(1, 1, 1, 0.7))
				gc5["wash"] = int(gc5.get("wash", 0)) + 1
	elif ac == "jet" and String(ad.get("ph", "")) in ["roll", "sortie"]:
		var d := Vector2(cos(facing), sin(facing))
		var sd := Vector2((d.x - d.y) * 32.0, (d.x + d.y) * 16.0).normalized()
		if art.resolve_fx("g5_afterburner", Color.WHITE, "-", int(t * 12.0)):
			var tp := sp - sd * 20.0 - Vector2(0, _lift)
			_push(1, sp.y - _lift - 1.0, art.out_page, art.out_src, tp + art.out_off, art.out_src.size, Color.WHITE)
			gc5["burner"] = int(gc5.get("burner", 0)) + 1



## G7 (LOOK7): is a building's roof cut away for viewer pf? roof_open = the faction id whose troops are inside
## (SQUAD7 garrison clearing; bool true also accepted); cut away for that side and its allies only.
static func roof_open_for(ro, pf: int, allies: Array) -> bool:
	if ro == null or (ro is bool and not ro):
		return false
	if ro is bool:
		return true
	var f := int(ro)
	return f >= 0 and (f == pf or allies.has(f))


# ================================================================ G7 (CNFAC7-2): dropship rear-ramp loading
## Landed large dropships this frame (for the footprint y-sort). Nothing to do in a match without them.
func _bay_crafts(n_u: int, far: bool, defs: PackedStringArray, def_a: PackedInt32Array, flg_a: PackedInt32Array,
		pos_a: PackedVector2Array, fac_a: PackedFloat32Array, ids: PackedInt32Array) -> void:
	_crafts.clear()
	if far:
		return
	var ldi := PackedInt32Array()
	for di in defs.size():
		if BAY_ART.has(defs[di]):
			ldi.append(di)
	if ldi.is_empty():
		return
	for j in n_u:
		if (flg_a[j] & RenderSnap.FLAG_LANDED) != 0 and ldi.has(def_a[j]):
			var cp: Vector2 = pos_a[j]
			_crafts.append([cp, snappedf(fac_a[j], PI / 4.0), int((cp.x + cp.y) * 16.0), ids[j]])


func _craft_y(id: int, ky: int) -> int:
	for cr in _crafts:
		if int(cr[3]) == id:
			return int(cr[2])
	return ky


## Sort depth of a ground unit at tile point g (depth ky) against landed large dropships (ARTCN7-5 CR seq 1193).
## The screen column through g is the ground line g + t (1, 1); if it crosses a craft's footprint anywhere in front of
## (or at) g, that hull stands between the unit and the camera: the unit is drawn first (hidden by the hull). If the
## footprint lies only behind g, the unit is drawn after the craft. Units whose column misses the footprint keep ky.
static func bay_sort_y(g: Vector2, ky: int, crafts: Array) -> int:
	for cr in crafts:
		var d: Vector2 = g - (cr[0] as Vector2)
		if absf(d.x) + absf(d.y) > 7.5:
			continue
		var f: float = cr[1]
		var n := Vector2(cos(f), sin(f))
		var p := [d.dot(n), d.y * n.x - d.x * n.y]   # u along the nose, v across
		var dp := [n.x + n.y, n.x - n.y]              # (1, 1) in the craft frame
		var lim := [FOOT_U, FOOT_V]
		var t0 := -INF
		var t1 := INF
		for ax in 2:
			if absf(float(dp[ax])) < 0.0001:
				if absf(float(p[ax])) > float(lim[ax]):
					t0 = INF
				continue
			var a := (-float(lim[ax]) - float(p[ax])) / float(dp[ax])
			var b := (float(lim[ax]) - float(p[ax])) / float(dp[ax])
			t0 = maxf(t0, minf(a, b))
			t1 = minf(t1, maxf(a, b))
		if t0 > t1:
			continue
		var cy: int = cr[2]
		ky = mini(ky, cy - 1) if t1 > 0.0 else maxi(ky, cy + 1)
	return ky


## Draws a dropship in a ramp sequence from the rev4 sheets: main (landed / ramp_down / bay_open), <id>_apcload
## (APC drives up the ramp: apc_load_0..5, unload = reverse), <id>_squadload / _squadunload (boarding file loop, only
## with a vehicle aboard: those sheets show it parked in the bay). False = no sheet (normal drawing goes on).
func _push_bay(id: int, dname: String, ow: int, facing: float, gb: Dictionary, sp: Vector2, hl: float, tt: float,
		t: float, mod6: Color, neutral: Color) -> bool:
	var base: String = BAY_ART[dname]
	var ph := String(gb.get("bay", ""))
	var b0 := float(gb.get("b0", 0))
	var b1 := float(gb.get("b1", 0))
	var k := clampf((tt - b0) / maxf(b1 - b0, 1.0), 0.0, 0.999)
	var bv := int(gb.get("bv", 0)) > 0
	var open_col := BAY_OPEN if bv else BAY_RAMP
	var sk := 0
	var col := open_col
	match ph:
		"closed":
			col = BAY_LANDED
		"ramp_down":
			col = BAY_LANDED if k < 0.5 else open_col
		"ramp_up":
			col = open_col if k < 0.5 else BAY_LANDED
		"apc_in":
			sk = 1
			col = int(k * 6.0)
		"apc_out":
			sk = 1
			col = 5 - int(k * 6.0)
		"squad_in", "squad_out":
			if bv:
				sk = 2 if ph == "squad_in" else 3
				col = int(t * BAY_FILE_FPS + float(id) * 0.37) % 4
	var sheet: String = base + ["", "_apcload", "_squadload", "_squadunload"][sk]
	var pid := -3000000 - id * 4 - sk
	var c = art._ec.get(pid)
	if c == null or c[1] != ow or c[0] != sheet:
		c = art.cache_unit(_proxy(pid, sheet, ow, facing, 0), _team.get(ow, neutral), String(_ck.get(ow, "x")))
	if int(c[2]) < 0 or col >= int(c[35]):
		return false
	var row := posmod(int(round(facing * FACING_INV)), 8)
	var fsz := Vector2(c[4], c[5])
	_push(0, float(_craft_y(id, int(sp.y + hl))), int(c[2]), Rect2((c[3] as Vector2) + Vector2(col, row) * fsz, fsz), sp + (c[6] as Vector2), fsz, mod6)
	bay_drawn += 1
	return true
