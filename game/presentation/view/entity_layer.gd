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
const ApcGun7 = preload("res://presentation/view/apc_gun7.gd")          # G7 MUZZLE7-2 CR 5911 (13.9c-28a) CN APC roof-gun overlays
const MOTION_CAP := 700      # G6.1: motion layer (smooth facing, ease, bob, reactions) only while <= this many units drew
const RUN_SPEED := 2.3       # G6.1: drawn speed (tiles/s) above which infantry use the run cycle

const LOD_MID := 0.8     # zoom below this: mid LOD (small FX dropped by fx_layer)
const LOD_FAR := 0.55    # zoom below this: far LOD (unit icons). Raised 0.45->0.55: at 0.5 peak zoom sprite detail is already sub-readable (E2 allows LOD where invisible).
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
const CnFacility = preload("res://sim/systems/cn_facility.gd")  # G7 (CNFAC7-3): facility floors (read-only)
const FacGate7 = preload("res://presentation/view/fac_gate7.gd")  # G7 GATE7 CR 5743: blast-door frames from the sim gate state (13.9c-26)
const ArtCat = preload("res://presentation/art/art_catalog.gd")
const BAY_HIDE_A := 0.6     # hull pixel alpha above this covers a soldier's feet (the sheet's ground shadow is ~0.36)
const BAY_PROBE := [Vector2(0, -2), Vector2(-4, -2), Vector2(4, -2), Vector2(0, 1), Vector2(0, 4), Vector2(0, 7), Vector2(0, -5),
	Vector2(0, -8), Vector2(0, -11), Vector2(0, -14), Vector2(0, -17), Vector2(0, -20)]  # a man's feet (+-4), body to 20 px, 7 px under him
# FACB7-5 (owner 13.9c-18 "NO transparent anything - no see through"): the LOOK7 roof cut-away (building drawn at alpha
# 0.34 while our troops clear it) is gone: buildings always draw solid; our men inside are hidden and the building gets
# an opaque "troops inside" badge (_badges, drawn after the sprites).
const BADGE_EDGE := Color(0.07, 0.08, 0.09)
const BADGE_FIG := Color(0.96, 0.96, 0.9)
var _roof_n: Dictionary = {}                # building id -> own / allied men inside it (this frame)
var _badges: Array = []                     # [screen point, men inside, team colour] (this frame)
var bld_see_through := 0                    # building / wreck sprites pushed with alpha < 1 this frame (must stay 0)
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
const FAR_PAN_PAD := 0.3                   # G7.1 PERFDRAW71: far list built this much wider per side while panning
var _far_rect := Rect2()                   # G7.1 PERFDRAW71: canvas rect the far list was built for
var _far_origin := Vector2(INF, INF)       # G7.1 PERFDRAW71: canvas origin at that build (moved = panning)
# G4b (UI4B-3): burnt-out forest cells (TerrainChanged cause "fire"): cell index -> true. Their
# tree decor is skipped and a burnt_ground variant (cell hash) is drawn flat. Presentation-only:
# the sim keeps no burnt set, so a loaded save shows plain dirt there (KNOWN GAP).
var burnt: Dictionary = {}
# G7 (BASE7-3): cells a counter-nanite compound paved over (TerrainChanged cause "cn_facility"): their terrain decor
# (rocks, bushes, trees) is skipped. Presentation-only; the sim cell is ROAD, so a rebuilt view draws no decor there.
var cleared: Dictionary = {}
var fires_drawn := 0                       # last frame's counts (playtest / debug)
var burnt_drawn := 0
var g4b_fx_drawn := 0                      # mines + charges drawn from effect art
# G5 (VIEW5): last frame's counts (headless probe / playtests) and the sim burnt-set sync
var g5_counts: Dictionary = {}             # shadows, lifted, wounded, markers, red_cross, trails, slung, strips, sinking
var _burnt_src := PackedByteArray()        # last snap.burnt merged into `burnt`
var _lift := 0.0                           # last _g5_lift result (px)
var x7: Dictionary = {}  # G7 (VIS7): id -> [sheet spec ({} = hide), column, row (-1 = unit row), offset Vector2]; filled by vis7_layer before refresh()
var _bay_fr: Dictionary = {}               # G7 (CNFAC7-3): craft id -> [sheet Image, frame origin, dst, frame size, sort depth]
var _bay_hide: Array = []                  # G7 (CNFAC7-3): infantry near a landed craft [first push, end push, feet, depth]
var _hc := -1
var _inf_cache: Dictionary = {}
var bay_hidden := 0                        # infantry hidden behind a landed dropship this frame (playtest evidence)
var fac_drawn := 0                         # facility floor / zone sprites drawn this frame (playtest evidence)
# ART7F: facility draw cache (flicker fix), interior buildings, wall autotile
const FAC7F_ZONES := [["planning", "g7_fac_planning", 0.0], ["drone_bay", "g7_fac_dronebay", 0.0],
	["workshop", "g7_fac_workshop", 0.0], ["range", "g7_fac_range", 0.0], ["lab", "g7_fac_lab", 0.0],
	# ART7F-2 (13.9c-2): two-layer APC entry (outer gate -> wash zone -> inner gate) and the infantry decon hall;
	# drawn when CnFacility carries these zones (BASE7 successor), closed / sprays off on lockdown
	["gate_outer", "g7_fac_gate_outer", 0.0], ["apc_wash", "g7_fac_wash", 0.0], ["gate_inner", "g7_fac_gate_inner", 0.0],
	["decon_hall", "g7_fac_deconhall", 0.0],
	# FACB7-2 (13.9c-6): special ammo magazine (ruin once its armoured cell cooked off), armory + suit bay, aid station +
	# quarantine bay, Sentinel barracks (ruin once SENT7's barracks entity is gone), wash runoff tank; the fuel / rearm
	# apron is flat (drawn under everything, FAC7F_FLAT)
	["magazine", "g7_fac_magazine", 0.0], ["armory", "g7_fac_armory", 0.0], ["aid_station", "g7_fac_aid", 0.0],
	["barracks", "g7_fac_barracks", 0.0], ["runoff", "g7_fac_runoff", 0.0]]
const FAC7F_FLAT := [["fuel_point", "g7_fac_fuel"]]
## FACB7-2: facility parts drawn by their zone art (their own sprite is skipped).
const FAC_ZONE_PARTS := {"cn_magazine": true, "cn_sentinel_barracks": true, "cn_armory": true}  # + EXO7 CR 4866
var _lb_cells: Dictionary = {}             # FACB7-2: Vector2i -> "link" / "baffle" (cn_link_wall / cn_ecp_baffle cells)
const WALL_LINK := {"cn_blast_wall": true, "cn_tower": true, "cn_checkpoint": true}
var fac_cache_off := false                 # ART7F playtest A/B: true = the old per-frame read (skips busy frames)
var fac_busy := 0                          # ART7F: refreshes that ran with a sim step in flight (evidence)
var fac_sig := 0                           # ART7F: hash of this frame's facility draw list (flicker capture)
var walls_linked := 0                      # ART7F: wall segments drawn with the conn sheet this frame
var _fac_e: Array = []                     # last CnFacility.render_entries (reused while the sim step is in flight)
var _fac_e_tick := -2
var _wall_cells: Dictionary = {}           # Vector2i cell -> true (walls, towers, checkpoint, gate zones)
var _ww_cells: Dictionary = {}             # G7 (WALL7): wall-walk cell -> Motion.wall_walk_cells value (soldiers on the wall top)
var ww_drawn := 0                          # G7 (WALL7): soldiers drawn on a wall top last frame (probe / playtest)
var ww_crouch := 0                         # G7 (WALL7-2): of those, drawn crouched behind the parapet (probe / playtest)
var ww_front := 0                          # G7 (WALL7-2): parapet occluder strips drawn over wall-walkers last frame
var _ww_occ: Dictionary = {}               # G7 (WALL7-2): piece centre (Vector2) -> true while a soldier stands on it
var _ww_centres: Array = []                # G7 (WALL7-2): facility compound centres (outer quadrant of a ring piece)
var _wall_dirty := true
var _wall_nfac := -1
var _wall_nstat := -1
var _pad_key := ""
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
var gone7: Dictionary = {}    # G7 REGFIX7-3: id -> its last drawn7 record, for shots drawn after the shooter was removed
var drawn7: Dictionary = {}   # G7 MUZZLE7 CR 5592: id -> [sheet column, facing row, drawn anchor (after air lift), anim time] (fx_layer barrel-tip flashes)
var apc_gun7 = ApcGun7.new()   # G7 MUZZLE7-2 CR 5911: CN APC pods / RWS drawn over the hull (traverse, recoil, flash); fx_layer reads it
var _fat: Dictionary = {}     # id -> REAL61 Fatigue level 0..1
var _chev: Dictionary = {}    # id -> rank chevron 0..4 (REAL61 realism_info.chevron)
var _pips: Dictionary = {}    # id -> 1 + filled ammo pips (BEARER61 bearers), absent = not a bearer
var g61_counts: Dictionary = {}
var g61_off := OS.get_environment("ANIM61_OFF") == "1"   # perf A/B: G6.1 motion + anim61 frame choice off
var _no61: Dictionary = {}

# ---------------------------------------------------------------- G7.1 PERFDRAW71-8 per-snapshot unit record cache
## Owner "cache now, native later" (board seq 599). On frames without the motion layer (> MOTION_CAP units drawn: LP
## peak, 2k on screen) and not at far LOD, a unit whose draw depends only on its snapshot fields and the anim time (no
## G6 / bay / air-data / G7 / SQUAD7 / k8 / ship / sling / wounded / evac / amphibian / APC-gun state) keeps a record of
## its snapshot-only choices (art cache entry, facing row, frame mode, fixed frame src) for the life of that snapshot.
## Later frames of the same snapshot only re-interpolate its position, redo the terrain / height lift, pick the
## anim-time frame and push: the same items, values and order as the full path (PD71_RC_VERIFY=1 compares every
## refresh item for item). A wall-walk cell, a VIS7 swap or a landed craft sends the unit through the full path that
## frame. PD71_RC=0 = full path only (the reference).
const RC_FIX := 1    # modes: fixed frame (push fields precomputed)
const RC_PER := 2    # Motion.inf_col on a motion-off posture: cols[int(t * r1 * r2 + ph) % n]
const RC_WALK := 3   # 2-frame walk: int(t * 6.0 + id * 0.37) % 2
const RC_OFFA := 4   # idle officer with the anim61 set: command pose 2 s in 8, else RC_PER idle
const RC_OFF := 5    # idle officer without it: command pose 2 s in 8, else column 0
const CB_SQ := 1     # counter bits: gc5.squads, gc5.tactical, gc5.ramp, gc61.a61, gc61.flipped (fixed), air lift
const CB_TAC := 2
const CB_RAMP := 4
const CB_A61 := 8
const CB_FLIP := 16
const CB_AIR := 32
var rc_on := OS.get_environment("PD71_RC") == "1"  # off by default: rc8 verify found 2 diffs at 2k and no measured gain (ORCH 2026-11-09)
var rc_verify := OS.get_environment("PD71_RC_VERIFY") == "1"
## G7.1 SWARMNAT71-2: the static records alone (unit records stay as rc_on says). ON by default (PD71_RS=0 = off): the
## statics-only verify (PD71_RC_VERIFY=1, no PD71_RC) found 0 item diffs on LP peak / LP wide / LP pan / 2k (rsv_r2, seq
## swarmnat71.statics_verify); its one counter diff (g5.apron, frame 36) shows in the null control as well (harness).
var rs_on := OS.get_environment("PD71_RS") != "0"
var rv_null := OS.get_environment("PD71_VERIFY_NULL") == "1"
## G7.1 SWARMNAT71: native unit kernel (rts_core 0.6.4 RtsSwarmDraw, docs/SWARM_NATIVE71.md sections 3-4) for plain units
## on motion-layer frames. OFF by default (SWARMNAT71=1 on) until SWARMNAT71_VERIFY=1 shows 0 diffs: that mode runs every
## refresh twice (GDScript path, then the kernel, from the same motion / drawn7 state) and compares every item, counter,
## vis list, drawn7 row and motion state.
var sw_on := OS.get_environment("SWARMNAT71") == "1"
var sw_verify := OS.get_environment("SWARMNAT71_VERIFY") == "1"
var _sw = null
var _sw65 := false       # SWARMNAT71-5: rts_core >= 0.6.5 kernel (anim61 infantry / Machines, fatigue mirror, bay-hide out)
var _sw_reg := {}        # id -> the BatchArt cache entry registered natively
var _sw_force := -1      # verify: -1 = sw_on decides, 0 off, 1 on
var _sw_ww_src = null    # wall-walk mask source (_ww_cells) and mask
var _sw_ww := PackedByteArray()
var sw_used := false     # the last refresh ran the kernel
var sw_units := 0        # units the kernel drew in the last refresh
var sw_calls := 0        # kernel calls in the last refresh
var sw_why := ""         # SWARMNAT71-3 diag: why the kernel did not run in the last refresh
var swv_frames := 0
var swv_diffs := 0
var swv_skip := 0
var swv_units := 0
var swv_log := 0
const SW_ABS := -999999   # SWARMNAT71-2 control: second run = the full path again (harness diffs)
var rc_hits := 0     # units pushed from a record in the last refresh
var rc_built := 0    # records made in the last refresh
var rc_fall := 0     # recorded units sent through the full path in the last refresh (wall walk / VIS7 / crafts)
var rv_frames := 0   # PD71_RC_VERIFY: refreshes compared / with any difference / record pushes compared
var rv_diffs := 0
var rv_hits := 0
var rv_log := 0
var rv_skip := 0     # PD71_RC_VERIFY: refreshes not compared (record path off: same code both times)
var rc_used := false # the last refresh ran with the record path on
var _rc_sn = null
var _rc_key: Array = []
var _rc_k := PackedInt32Array()     # per snapshot index: 0 not tried, -1 full path for this snapshot, else the mode
var _rc_c: Array = []               # BatchArt cache entry
var _rc_row := PackedInt32Array()
var _rc_cb := PackedInt32Array()    # CB_* bits
var _rc_fa := PackedInt32Array()    # fixed column / walk col A / officer col
var _rc_fb := PackedInt32Array()    # walk col B / periodic modulus
var _rc_cols: Array = []            # periodic: the anim61 column array
var _rc_r := PackedFloat64Array()   # periodic: r1, r2, ph (3 per index); air: alt, bob (indices 3, 4)
var _rc_pg := PackedInt32Array()    # fixed: page, src, dst offset, dsz, size
var _rc_src := PackedVector2Array()
var _rc_off := PackedVector2Array()
var _rc_dsz := PackedVector2Array()
var _rc_sz := PackedVector2Array()
## Statics (plain buildings, resources, wrecks: no facility part, roof badge or sinking wreck) keep one record per
## snapshot too: their single item is fixed for the snapshot, so later frames only cull it against the view and push it.
var rs_hits := 0     # statics pushed from a record in the last refresh
var rs_used := false
var _rs_sn = null
var _rs_key: Array = []
var _rs_k := PackedInt32Array()     # per statics iteration index: 0 not tried, -1 full path, else 1 | 2 vis_bld | 4 see-through
var _rs_wk := PackedByteArray()     # 1 = wreck (its seen flag is re-checked every frame)
var _rs_gs := PackedVector2Array()  # ground screen point (the cull test)
var _rs_ky := PackedInt64Array()    # (int(depth) + Y_OFF) * IDX_MUL
var _rs_pg := PackedInt32Array()
var _rs_src := PackedVector2Array()
var _rs_sz := PackedVector2Array()
var _rs_dst := PackedVector2Array()
var _rs_mod := PackedColorArray()
var _rs_gp := PackedVector2Array()  # ground point (wall pieces: soldier-on-top check)


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
	var ww = mv.get("_world")
	if ww == null:
		return
	var w := int(ww.map.w)
	var h := int(ww.map.h)
	var terrain: PackedByteArray = ww.map.terrain
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
	var ww = mv.get("_world")
	if ww == null:
		return
	var pois: Dictionary = ArtCatalog.manifest().get("poi_decor", {})
	var lists: Dictionary = ArtCatalog.manifest().get("decor", {})
	for d in ww.map.get("decor", []):
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


## G7 BLAST8 (13.9c-47): the body of a man the blast killed flies the event's arc before it settles (corpse entry
## [5] = [screen delta, peak px, flight s, turns, def]).
func on_blast_corpse(ev: Dictionary) -> void:
	var id := int(ev.get("id", -1))
	for k in range(motion.corpses.size() - 1, -1, -1):
		var cp: Array = motion.corpses[k]
		if int(cp[0]) == id and cp.size() == 5:
			var d: Vector2 = Vector2(ev.to) - Vector2(ev.from)
			cp.append([Vector2((d.x - d.y) * 32.0, (d.x + d.y) * 16.0), float(ev.peak_m) * B8_PX_PER_M,
				maxf(float(ev.ticks) / 20.0, 0.1), float(ev.turns), String(ev.get("def", ""))])
			return


func on_destroyed(id: int, def_name: String = "") -> void:
	# G6.1: an infantry unit with the anim61 set leaves a corpse (die_0..2, lingers, fades)
	var dc = art._ec.get(id)
	# G7.1 ANIM71 E4-2.6: Machine / walker wreck break-up cue (presentation only; no FX / gore fight)
	var dname := def_name
	if dname.is_empty() and dc is Array and (dc as Array).size() > 0:
		dname = String(dc[0])
	var dk := Motion.death_kind_for(dname) if not dname.is_empty() else Motion.DK_NONE
	if dk != Motion.DK_NONE and mv != null:
		motion.kill_machine(id, mv.anim_time(), dk)
	# EXO7-3 CR 6360: a CN armoured suit (the only infantry-sheet unit with a 12-frame swalk and a sim wreck entity) leaves
	# its wreck only, never a second infantry corpse beside it
	elif dc is Array and (dc as Array).size() > 37 and not (dc[31] as Dictionary).is_empty() and mv != null 			and not (dc[31] as Dictionary).has("swalk"):
		motion.kill(id, dc, mv.anim_time())
	else:
		motion.forget(id)
	_post.erase(id)
	if drawn7.has(id):   # REGFIX7-3: a shooter killed in the step it fired: its last flash still leaves its drawn barrel
		gone7[id] = drawn7[id]
		if gone7.size() > 256:
			gone7.clear()
	drawn7.erase(id)
	_wall_dirty = true   # ART7F: a wall-line part may be gone (re-pick its neighbours' joins)
	_fat.erase(id)
	_k8.erase(id)   # G8 ANIM8
	_chev.erase(id)
	_pips.erase(id)
	if _sw != null:   # G7.1 SWARMNAT71
		_sw.forget(id)
	_sw_reg.erase(id)
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
	if _sw != null:   # G7.1 SWARMNAT71: the kernel's posture / marks mirror
		_sw.set_post(id, p, int(_chev.get(id, 0)) > 0 or int(_pips.get(id, 0)) > 0)
		if _sw65:
			_sw.set_fat(id, float(_fat[id]))


## G7 PERFFPS7: false when Motion.g7_col_sq(a61, b, posture, ...) can only return -1 (no back-off / throw / entry / gait /
## stack state that picks a G7 column), so the per-soldier call is skipped; true otherwise (the call decides).
var _dfl_names := PackedStringArray()   # names _dfl was built from (reset check)
var _dfl := PackedInt32Array()   # G7 PERFFPS7: _def_flags per snap defs index (extended in refresh as the table grows)
static func _def_flags(nm: String) -> int:
	return (1 if BAY_ART.has(nm) else 0) | (2 if nm == "a_vtol_dropship" else 0)


static func _sq_col_may(b: int, posture: int) -> bool:
	var moving := (posture & Motion.P_MOVING) != 0
	if moving and b & 4:   # _SQ_BACK
		return true
	if posture & Motion.P_FIRING:
		return (posture & Motion.P_THROW) != 0
	var gi := (b >> 6) & 3
	if moving:
		return (b & 16) != 0 or gi != 0   # _SQ_ENTRY, any gait
	return (b & 8) != 0 or gi == 1 or gi == 2   # _SQ_STACK, crouch / duck


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


const B8_PX_PER_M := 10.0   # G7 BLAST8: screen px per metre of height (an 18 px soldier is ~1.8 m, rev3 scale)
var _b8z: Array = []         # G7 BLAST8: [atlas page, src rect] of the "z" glyph (built once)

# ---------------------------------------------------------------- G8 ANIM8 (G7_REFERENCE 13.9c-52)
## Thrown / knocked-down / unconscious / coming-round soldiers drawn with the baked k8_* columns (BatchArt.k8_cols).
## View-only record per soldier (never read by the sim): [kind 0 thrown / 1 knocked down, start tick, flight ticks,
## turns, row facing the blast, sprawl 0 on back / 1 face down / 2 on side, landing tick, wake start tick (-1),
## throw direction on screen]. Times are interpolated sim ticks (tick - 1 + alpha), so every offset moves per frame.
var _k8: Dictionary = {}
var _k8_fi := -1
var _k8_row := 0
var _k8_off := Vector2.ZERO
const K8_IMPACT := 6.0    # ticks of impact frames after landing
const K8_SKID := 7.0      # px skid along the throw line
const K8_DUST := 14.0     # ticks the landing dust puff lasts
const K8_BUCK := 14.0     # ticks of the knees-buckle fall
const K8_WAKE := 30.0     # ticks of the coming-round sequence (6 frames)
const K8_KD := 30         # = Motion.KD_SHOW: a knocked-down man lies this long


## Row of a man facing grid direction gdir (toward the blast).
static func k8_row_of(gdir: Vector2) -> int:
	return posmod(int(round(atan2(gdir.y, gdir.x) * FACING_INV)), 8)


## Sprawl variant: face down when the tumble ended half a turn over, else on his back / side by id (deterministic).
static func k8_variant(id: int, turns: float) -> int:
	var fr := absf(turns) - floorf(absf(turns))
	if absf(turns) >= 0.25 and fr >= 0.25 and fr < 0.75:
		return 1
	return 2 if posmod(id * 7919 + 13, 3) == 0 else 0


## Flight column at fraction k: launch, then the tumble at the throw's spin rate and direction, impact pose at the end.
static func k8_flight_col(a61: Dictionary, k: float, turns: float) -> int:
	if k < 0.1:
		return int(a61.k8_launch[0 if k < 0.05 else 1])
	if k >= 0.93:
		return int(a61.k8_imp[0])
	var i := int(floor((k - 0.1) / 0.83 * maxf(absf(turns), 0.35) * 8.0))
	return int(a61.k8_tum[posmod(i if turns >= 0.0 else -i, 8)])


## Lying column: still in the sprawl, or (unconscious) a slow breathing loop with the odd twitch.
static func k8_lie_col(a61: Dictionary, v: int, t: float, id: int, unc: bool) -> int:
	var cols: Array = a61[["k8_bk", "k8_fd", "k8_sd"][clampi(v, 0, 2)]]
	if not unc:
		return int(cols[0])
	var s := float(posmod(id, 97)) * 0.37
	var tw := t * 0.7 + s
	if posmod(int(tw) * 31 + id, 23) == 0 and fmod(tw, 1.0) < 0.3:
		return int(cols[2])
	return int(cols[1]) if sin(t * TAU * 0.3 + s) > 0.2 else int(cols[0])


## Landing dust: the generic smoke puff, small and earth-tinted, at ground point gp, dt ticks after the landing.
func _k8_dust(gp: Vector2, dt: float) -> void:
	if dt < 0.0 or dt >= K8_DUST:
		return
	var u := dt / K8_DUST
	if art.resolve_fx("smoke", Color.WHITE, "-", clampi(int(u * 5.0), 0, 4)):
		var sz: Vector2 = art.out_src.size * (0.45 + 0.35 * u)
		_push(0, gp.y + 1.0, art.out_page, art.out_src, gp - Vector2(sz.x * 0.5, sz.y * 0.8), sz,
			Color(0.80, 0.70, 0.52, 0.75 * (1.0 - u)))


## Drives one live soldier from the k8 set. true = _k8_fi / _k8_row / _k8_off are set for this frame.
func _k8_live(id: int, gv, a61: Dictionary, tt: float, stick: int, t: float, row: int, sp: Vector2, far: bool) -> bool:
	var rec = _k8.get(id)
	var unc := false
	var kd := -100000
	if gv != null:
		if gv.has("bt"):
			var b8: Array = gv.bt
			if rec == null or float(rec[1]) != float(b8[5]):
				var gd := Vector2(float(b8[0]) - float(b8[2]), float(b8[1]) - float(b8[3]))   # landing -> blast side
				var sdir := Vector2(-(gd.x - gd.y) * 32.0, -(gd.x + gd.y) * 16.0).normalized()
				var dur := maxf(float(b8[6]), 1.0)
				rec = [0, float(b8[5]), dur, float(b8[7]), k8_row_of(gd) if gd.length() > 0.01 else row,
					k8_variant(id, float(b8[7])), float(b8[5]) + dur, -1.0, sdir]
				_k8[id] = rec
			_k8_fi = k8_flight_col(a61, clampf((tt - float(rec[1])) / float(rec[2]), 0.0, 1.0), float(rec[3]))
			_k8_row = int(rec[4])
			_k8_off = Vector2.ZERO
			return true
		var cared := String(gv.get("cared", ""))
		if cared == "drag" or cared == "carry":   # carried / dragged: the G7 limp pose at his sim position
			_k8.erase(id)
			return false
		unc = gv.has("b8u") or bool(gv.get("unc", false))
		kd = int(gv.get("kd", -100000))
	if rec == null:
		if not unc and stick - kd >= 3:
			return false
		# knocked off his feet without a flight (concussed / knocked down): knees buckle, fall back
		rec = [1, tt, K8_BUCK, 0.0, row, 2 if posmod(id * 7919 + 13, 3) == 0 else 0, tt + K8_BUCK, -1.0, Vector2.ZERO]
		_k8[id] = rec
	_k8_row = int(rec[4])
	var dt := tt - float(rec[6])
	if dt < 0.0:
		_k8_fi = int(a61.k8_buck[clampi(int((tt - float(rec[1])) / K8_BUCK * 4.0), 0, 3)])
		_k8_off = Vector2.ZERO
		return true
	var lying := unc or stick - kd < K8_KD or dt < float(K8_KD)
	var wk := 0.0
	if not lying:
		if float(rec[7]) < 0.0:
			if dt > 600.0:   # came back into view long after: no wake-up replay
				_k8.erase(id)
				return false
			rec[7] = tt
		wk = (tt - float(rec[7])) / K8_WAKE
		if wk >= 1.0:
			_k8.erase(id)
			return false
	var skid := 0.0
	if int(rec[0]) == 0:
		var u := clampf(dt / (K8_IMPACT + 2.0), 0.0, 1.0)
		skid = K8_SKID * (1.0 - (1.0 - u) * (1.0 - u))
	_k8_off = (rec[8] as Vector2) * skid * (1.0 - clampf(wk * 1.5, 0.0, 1.0))
	if int(rec[0]) == 0 and not far:
		_k8_dust(sp + _k8_off, dt)
	if int(rec[0]) == 0 and dt < K8_IMPACT:
		_k8_fi = int(a61.k8_imp[0 if dt < 2.5 else 1])
		_k8_off.y -= 2.5 * sin(PI * clampf((dt - 1.0) / 4.0, 0.0, 1.0))   # small bounce
		return true
	if wk > 0.0:
		_k8_fi = int(a61.k8_wake[clampi(int(wk * 6.0), 0, 5)])
		return true
	_k8_fi = k8_lie_col(a61, int(rec[5]), t, id, unc)
	return true


## G7 BLAST8 (13.9c-47): three "z" glyphs rising and fading over a soldier knocked unconscious by a blast.
func _b8_zzz(sp: Vector2, t: float, id: int) -> void:
	if _b8z.is_empty():
		var img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var on := {}
		for x in range(1, 6):
			on[Vector2i(x, 1)] = true
			on[Vector2i(x, 5)] = true
		for k in range(1, 4):
			on[Vector2i(5 - k, 1 + k)] = true
		for q in on:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n: Vector2i = q + Vector2i(dx, dy)
					if not on.has(n) and n.x >= 0 and n.y >= 0 and n.x < 7 and n.y < 7:
						img.set_pixelv(n, Color(0.05, 0.05, 0.12, 0.9))
		for q in on:
			img.set_pixelv(q, Color(1.0, 1.0, 0.82, 1.0))
		var pg: int = art.atlas.add("b8_zzz", img)
		_b8z = [pg, art.atlas.rect_of("b8_zzz") if pg >= 0 else Rect2()]
	if int(_b8z[0]) < 0:
		return
	var r: Rect2 = _b8z[1]
	for k in 3:
		var ph := fposmod(t * 0.7 + float(k) / 3.0 + float(id % 7) * 0.13, 1.0)
		var sc := 0.7 + 0.6 * ph
		_push(1, sp.y + 2.0, int(_b8z[0]), r, sp + Vector2(3.0 + ph * 7.0 + float(k), -22.0 - ph * 14.0), r.size * sc, Color(1, 1, 1, 1.0 - ph * 0.75))


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
	if sw_verify:
		_sw_verify_refresh()
		return
	if not rc_verify:
		_refresh(rc_on, rc_on or rs_on)
		return
	# G7.1 PERFDRAW71-8 PD71_RC_VERIFY=1: full path, then the record path on the same inputs, compared item for item.
	# The motion layer (per-unit smoothing state) and the k8 records advance once per refresh: both runs start from the
	# same copy, so the second run sees exactly the state the first one saw.
	var mvs := {}
	for q in motion.vs:
		mvs[q] = (motion.vs[q] as PackedFloat32Array).duplicate()
	var k8s := {}
	for q in _k8:
		k8s[q] = (_k8[q] as Array).duplicate()
	var mcorp: Array = motion.corpses.duplicate()
	var ud0 := _units_drawn   # SWARMNAT71-2: motion_on follows the last refresh's count: both runs must see the same one
	_refresh(false, false)
	var a := _rc_capture()
	motion.vs = mvs
	_k8 = k8s
	motion.corpses = mcorp
	_units_drawn = ud0
	if rv_null:
		_refresh(false, false)
	else:
		_refresh(rc_on or not rs_on, true)
	var b := _rc_capture()
	if (rv_frames + rv_skip) % 120 == 0:
		print("PD71_RC_VERIFY frames=%d diffs=%d rec_pushes=%d skipped=%d rejects=%d last: used=%s/%s hits=%d st_hits=%d built=%d fall=%d drawn=%d units=%d lod=%d" % [rv_frames, rv_diffs, rv_hits, rv_skip, rc_reject, str(rc_used), str(rs_used), rc_hits, rs_hits, rc_built, rc_fall, drawn, _units_drawn, lod])
	if not rc_used and not rs_used and not rv_null:
		rv_skip += 1   # the record path was off for this refresh (motion layer / far LOD): both ran the same code
		return
	rv_frames += 1
	rv_hits += rc_hits
	var bad: Array = []
	for k in a:
		if typeof(a[k]) == TYPE_ARRAY:   # vis_units / vis_bld: the same live dicts, by identity
			var x: Array = a[k]
			var y: Array = b[k]
			if x.size() != y.size():
				bad.append("%s size %d/%d" % [k, x.size(), y.size()])
			else:
				for q in x.size():
					if not is_same(x[q], y[q]):
						bad.append("%s[%d]" % [k, q])
						break
		elif a[k] != b[k]:
			var s := "%s" % k
			if a[k] is PackedInt64Array or a[k] is PackedInt32Array or a[k] is PackedVector2Array or a[k] is PackedColorArray:
				var m: int = mini(a[k].size(), b[k].size())
				var j := 0
				while j < m and a[k][j] == b[k][j]:
					j += 1
				s += " at %d/%d: %s / %s" % [j, a[k].size(), str(a[k][j]) if j < a[k].size() else "-", str(b[k][j]) if j < b[k].size() else "-"]
			else:
				s += ": %s / %s" % [str(a[k]), str(b[k])]
			bad.append(s)
	if not bad.is_empty():
		rv_diffs += 1
		if rv_log < 12:
			rv_log += 1
			print("PD71_RC_DIFF frame=%d tick=%d hits=%d %s" % [rv_frames, int(mv.snap.get("tick", -1)), rc_hits, "; ".join(bad.slice(0, 6))])


## PD71_RC_VERIFY: everything one refresh hands to _draw / the overlays / the playtest counters.
func _rc_capture() -> Dictionary:
	return {"n": _n, "keys": _keys.slice(0, _n), "page": _page.slice(0, _n), "src": _src.slice(0, _n),
		"size": _size.slice(0, _n), "dst": _dst.slice(0, _n), "dsz": _dsz.slice(0, _n), "mod": _mod.slice(0, _n),
		"sorted": _sorted.duplicate(), "vis_units": vis_units.duplicate(), "vis_sp": vis_sp.duplicate(),
		"vis_air": vis_air.duplicate(), "vis_bld": vis_bld.duplicate(), "g5": g5_counts.duplicate(),
		"g6": g6_counts.duplicate(), "g61": g61_counts.duplicate(), "units_drawn": _units_drawn, "ww": [ww_drawn, ww_crouch, ww_front],
		"bay": [bay_hidden, bay_drawn, fac_drawn], "misc": [walls_linked, bld_see_through, g4b_fx_drawn, lod, motion_on],
		"badges": str(_badges), "roof": str(_roof_n), "drawn7": drawn7.size()}


## G7.1 PERFDRAW71-8: the record for snapshot index i, whose full draw just ended at push ii with column fi; -1 when its
## draw is not a pure function of its snapshot fields + the anim time (it keeps the full path for this snapshot). The
## mode re-derives the full path's frame choice for a motion-off unit; it is only kept when it gives this frame's fi.
var rc_reject := 0   # records refused because the derived frame differed from the full path's (should stay 0)
func _rc_put(i: int, id: int, c: Array, fl: int, a61: Dictionary, row: int, fi: int, ii: int, dname: String, d0: String,
		sq: bool, ok: bool, t: float) -> int:
	if not ok or dname != d0 or (_def_flags(d0) & 3) != 0 or int(c[2]) < 0 or int(c[27]) >= 0 \
			or (fl & (RenderSnap.FLAG_WOUNDED | RenderSnap.FLAG_EVAC | RenderSnap.FLAG_SLUNG | RenderSnap.FLAG_SHIP | RenderSnap.FLAG_ABOARD)) != 0 \
			or (a61.has("k8_tum") and _k8.has(id)):
		return -1
	var moving := (fl & RenderSnap.FLAG_MOVING) != 0
	var sd := (id % 61) * 0.0164   # = the motion-off Motion.inf_col seed
	var m := RC_FIX
	var cb := CB_SQ if sq else 0
	var fa := 0
	var fb := 0
	var cols = null
	var r1 := 1.0
	var r2 := 1.0
	var ph := 0.0
	if fl & RenderSnap.FLAG_FIRING:
		fa = c[20] if (fl & RenderSnap.FLAG_DRONE and c[20] >= 0) else c[7]
		if not a61.is_empty():   # Motion.inf_col: firing, not pinned: cosmetic reload 0.8 s in 5 s, else fire_s
			cb |= CB_A61
			if fposmod(0.0 + sd * 5.0, 5.0) > 4.2:
				m = RC_PER
				cols = a61.reload
				r1 = 3.0
				fb = 2
			else:
				fa = int(a61.fire_s)
	elif fl & RenderSnap.FLAG_TACTICAL and c[18] >= 0 and not moving:
		fa = c[18]
		cb |= CB_TAC
	else:
		var pz := -1
		if fl & POSE_MASK:
			pz = c[13] if fl & RenderSnap.FLAG_DEPLOYED else (c[14] if fl & RenderSnap.FLAG_WORK else c[15])
			if fl & RenderSnap.FLAG_UNLOAD and c[29] >= 0 and ((fl >> 8) & 0xFF) > 0:
				pz = c[29]
				cb |= CB_RAMP
		if pz >= 0:
			fa = pz
		elif not a61.is_empty():   # Motion.inf_col walk / swalk / idle (no run, crawl, crouch: motion off)
			m = RC_OFFA if (c[30] >= 0 and not moving) else RC_PER
			if m == RC_PER:
				cb |= CB_A61
			fa = c[30]
			if moving and a61.has("swalk"):
				cols = a61.swalk
				r1 = float(a61.get("swalk_hz", 2.5))
				r2 = 12.0
				ph = sd * 12.0
				fb = 12
			elif moving:
				cols = a61.walk
				r1 = 10.0
				ph = sd * 6.0
				fb = 6
			else:
				cols = a61.idle
				r1 = 0.9 + 0.0 * 1.6
				ph = sd * 2.0
				fb = 2
		elif moving:
			m = RC_WALK
			if c[8]:
				fa = c[9]
				fb = c[10]
			else:
				fa = c[11]
				fb = 0
		elif c[30] >= 0:
			m = RC_OFF
			fa = c[30]
	# guard: the derived frame must be this frame's
	var pf := fa
	if m == RC_PER or (m == RC_OFFA and int(t * 0.5 + id * 0.61) % 4 != 0):
		pf = int(cols[int(t * r1 * r2 + ph) % fb])
	elif m == RC_WALK:
		pf = fa if int(t * 6.0 + id * 0.37) % 2 == 0 else fb
	elif m == RC_OFF and int(t * 0.5 + id * 0.61) % 4 != 0:
		pf = 0
	if pf < 0:
		pf = 0
	if pf != fi:
		rc_reject += 1
		return -1
	_rc_c[i] = c
	_rc_row[i] = row
	_rc_fa[i] = fa
	_rc_fb[i] = fb
	_rc_cols[i] = cols
	var q := i * 5
	_rc_r[q] = r1
	_rc_r[q + 1] = r2
	_rc_r[q + 2] = ph
	if c[12]:
		cb |= CB_AIR
		var s: Dictionary = G3View._spec(dname)
		_rc_r[q + 3] = float(s.alt)
		_rc_r[q + 4] = float(s.bob)
	if m == RC_FIX:
		_rc_pg[i] = _page[ii]
		_rc_src[i] = _src[ii]
		_rc_dsz[i] = _dsz[ii]
		_rc_sz[i] = _size[ii]
		var tb: bool = fi >= int(c[35]) and (c[38] as PackedVector2Array)[fi * 8 + row].x >= 0.0
		_rc_off[i] = (c[40] as PackedVector2Array)[fi * 8 + row] if tb else (c[6] as Vector2)
		if tb and _dsz[ii].x < 0.0:
			cb |= CB_FLIP
	_rc_cb[i] = cb
	rc_built += 1
	return m


## G7.1 PERFDRAW71-8: record of static e (statics iteration index j) whose generic draw just ended at push _n - 1; -1 for
## the ones with per-frame parts (roof badge, sinking wreck).
func _rs_put(j: int, id, e: Dictionary, kind: String, ow: int, pf: int, gs: Vector2, sn: Dictionary, xf: int) -> int:
	if kind == "building" and roof_open_for(e.get("roof_open"), pf, mv._ally_fids) and not WALL_LINK.has(String(e.get("def", ""))):
		return -1
	if kind == "wreck" and (sn.get("sinking", {}) as Dictionary).get(id) != null:
		return -1
	if kind != "building" and kind != "wreck" and kind != "resource":
		return -1
	var ii := _n - 1
	var f := 1 | xf
	if kind == "building" and (ow == pf or mv.entity_visible(e)):
		f |= 2
	if (kind == "building" or kind == "wreck") and _mod[ii].a < 1.0:
		f |= 4
	_rs_wk[j] = 1 if kind == "wreck" else 0
	_rs_gs[j] = gs
	_rs_ky[j] = _keys[ii] - ii
	_rs_pg[j] = _page[ii]
	_rs_src[j] = _src[ii]
	_rs_sz[j] = _size[ii]
	_rs_dst[j] = _dst[ii]
	_rs_mod[j] = _mod[ii]
	_rs_gp[j] = e.pos
	return f


func _refresh(rc: bool, rs: bool) -> void:
	rc_used = false
	rs_used = false
	var sn: Dictionary = mv.snap
	if sn.is_empty():
		return
	var live: bool = mv.world_readable()
	var ents: Dictionary = mv._world.entities if live else {}
	var pf: int = mv.player_fid
	var z: float = mv.camera.zoom.x if mv.camera != null else 1.0
	lod = 2 if z < LOD_FAR else (1 if z < LOD_MID else 0)
	var far: bool = lod == 2
	var t: float = mv.anim_time()
	if _atlas_at > 0.0 and t >= _atlas_at:  # G6.1 (ANIMC61): env ANIM61_ATLAS_AT=<s> prints the live atlas once
		_atlas_at = -1.0
		var st: Dictionary = art.atlas.stats()
		print("ANIM61_ATLAS pages=%d MB=%.1f units_drawn=%d t=%.1f" % [int(st.pages), float(st.bytes) / 1e6, _units_drawn, t])
		# G7.1 PERFDRAW71 diag (same env gate): uploads so far, page sizes, page switches in last frame's sorted list
		var psz: Array = []
		for pgd in art.atlas.pages:
			psz.append("%dx%d" % [(pgd.img as Image).get_width(), (pgd.img as Image).get_height()])
		var sw := 0
		var lastp := -9
		var used := {}
		for k in _sorted:
			var pi: int = _page[k % IDX_MUL]
			used[pi] = int(used.get(pi, 0)) + 1
			if pi != lastp:
				sw += 1
				lastp = pi
		print("PD71_ATLAS uploads=%d items=%d switches=%d used=%s sizes=%s" % [art.atlas.uploads, _sorted.size(), sw, str(used), ",".join(psz)])
	var alpha: float = mv._alpha
	var vr := _view_rect()
	var mem: Dictionary = (sn.get("memory", {}) as Dictionary).get(pf, {})
	var statics: Dictionary = sn.statics
	# far LOD draws un-interpolated icons, so the list only changes with the sim tick, the
	# camera, the fog or the selection: reuse the canvas commands from the last rebuild.
	# G7.1 PERFDRAW71: far icons are drawn in canvas space, so a pan alone (same zoom) never changes them: the key
	# holds the zoom (canvas scale), not the whole transform, and the list is reused while the view stays inside the
	# rect it was built for. While the camera moves, the list is built for the view grown by FAR_PAN_PAD per side
	# (everything in the view is drawn exactly as before; the extra ring is off screen until the pan reaches it).
	if far:
		var ct: Transform2D = get_viewport().get_canvas_transform()
		var key := [int(sn.tick), ct.get_scale(), get_viewport_rect().size,
			mv.fog_layer.rebuilds if mv.fog_layer != null else 0, int(sn.entity_count), mem.size(), live]
		if key == _far_key and _far_rect.encloses(vr):
			skipped += 1
			return
		if ct.origin != _far_origin:
			vr = vr.grow_individual(vr.size.x * FAR_PAN_PAD, vr.size.y * FAR_PAN_PAD, vr.size.x * FAR_PAN_PAD, vr.size.y * FAR_PAN_PAD)
		_far_origin = ct.origin
		_far_key = key
		_far_rect = vr
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
	var s7v: Dictionary = sn.get("s7v", {})   # G7 PERF7D: Senses7 spot sets of this tick (FLAG_S7 soldiers)
	var has_s7 := not s7v.is_empty()
	var s7ot: Dictionary = s7v.get("ot", {})
	var allies: Array = mv._ally_fids   # G7 PERF7C: hoisted (a node property read per unit; Senses7 marks most enemy soldiers FLAG_HID)
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
			if not cleared.is_empty() and cleared.has(arr[k + 4]):
				continue  # G7 BASE7-3: paved over by a counter-nanite compound
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
	motion.gore_hand = (sn.get("g71", {}) as Dictionary).get("gore71") != null   # G7.1 DAMAGE71 CR 1897 (LP: Gore71 draws the body)
	_roof_n.clear()
	_badges.clear()
	bld_see_through = 0
	var gc61 := {"motion": 0, "a61": 0, "flipped": 0, "corpses": 0, "chevrons": 0, "pips": 0, "veh": 0, "turret": 0, "track": 0, "bank": 0, "recoil": 0, "g7": 0, "roof": 0, "roof_in": 0}
	g61_counts = gc61
	# G7 (LOOK7): sparse per-unit display states (render_snap g7u: wounds, care, panic, gait, sectors, herringbone)
	var g7u: Dictionary = sn.get("g7u", {})
	var has_g7 := not g7u.is_empty()
	# G7 PERF7D (orch.ruling CR 2047): SQUAD7 fields as arrays aligned with ids (RenderSnap.SQ7_* bits, sector, hull)
	var sq7f: PackedByteArray = sn.get("sq7f", PackedByteArray())
	var sq7a: PackedFloat64Array = sn.get("sq7a", PackedFloat64Array())
	var sq7h: PackedFloat64Array = sn.get("sq7h", PackedFloat64Array())
	var sq7_n := sq7f.size()
	var has_x7 := not x7.is_empty()
	var stick := int(sn.get("tick", 0))
	var units_drawn := 0
	# G7 PERFFPS7: the snap defs table only appends within one world, but a new world (new match / playtest scene)
	# builds its own table from scratch: drop the flags when the cached names are no longer its prefix (ORCH fix).
	if _dfl_names.size() > defs.size() or (_dfl_names.size() > 0 and defs.slice(0, _dfl_names.size()) != _dfl_names):
		_dfl.clear()
		_dfl_names.clear()
		if _sw != null:   # G7.1 SWARMNAT71: def indices restart with the new world
			_sw.reset()
		_sw_reg.clear()
	while _dfl.size() < defs.size():
		_dfl.append(_def_flags(defs[_dfl.size()]))
		_dfl_names.append(defs[_dfl_names.size()])
	walls_linked = 0
	var pframe := Engine.get_process_frames()
	_bay_crafts(n_u, far, defs, def_a, flg_a, pos_a, fac_a, ids)
	var has_cr := not _crafts.is_empty()
	bay_drawn = 0
	bay_hidden = 0
	_bay_fr.clear()
	_bay_hide.clear()
	_hc = -1
	if not far:   # ART7F flicker fix: the facility draws from its cached entries on frames the sim step is in flight
		_push_fac(mv._world if live else null, vr, stick)
	# G7 (WALL7): soldiers on the facility wall top are lifted onto it and sorted in front of it
	if not _fac_e.is_empty() and (_wall_dirty or int((sn.get("statics", {}) as Dictionary).size()) != _wall_nstat):
		_wall_rebuild()
	var has_ww := not _ww_cells.is_empty() and not far
	ww_drawn = 0
	ww_crouch = 0
	ww_front = 0
	if not _ww_occ.is_empty():
		_ww_occ.clear()
	# G7.1 PERFDRAW71-8: per-snapshot unit records (see RC_*): motion-off, non-far frames only
	var use_rc := rc and not far and not motion_on
	rc_used = use_rc
	rc_hits = 0
	rc_built = 0
	rc_fall = 0
	if use_rc:
		var rkey := [pf, allies.hash(), g61_off, n_u]
		if not is_same(sn, _rc_sn) or rkey != _rc_key:
			_rc_sn = sn
			_rc_key = rkey
			_rc_k.resize(n_u)
			_rc_k.fill(0)
			if _rc_c.size() < n_u:
				_rc_c.resize(n_u); _rc_cols.resize(n_u); _rc_row.resize(n_u); _rc_cb.resize(n_u); _rc_fa.resize(n_u)
				_rc_fb.resize(n_u); _rc_r.resize(n_u * 5); _rc_pg.resize(n_u); _rc_src.resize(n_u); _rc_off.resize(n_u)
				_rc_dsz.resize(n_u); _rc_sz.resize(n_u)
	# G7.1 SWARMNAT71: the native kernel draws runs of plain units; it stops at the first unit it cannot draw exactly and
	# this loop draws that one (sw_stop), so push order, keys and counters are the GDScript path's.
	var use_sw := (sw_on if _sw_force < 0 else _sw_force == 1) and motion_on and not far and not use_rc and _sw_init()
	sw_used = false
	sw_units = 0
	sw_calls = 0
	sw_why = "" if use_sw else "m%d f%d cr%d rc%d" % [int(motion_on), int(far), int(has_cr), int(use_rc)]
	if use_sw:
		sw_why = "begin"
		use_sw = _sw_begin(sn, alpha, t, vr, mw, pf, live, pframe, ids, raise, hl_t, rp6_n, rp6, vis, ally_vis, has_g6,
			has_ww, squad, g7u, g5air, sling)
	var sw_next := 0
	var sw_stop := -1
	var t_u := Time.get_ticks_usec()
	for i in n_u:
		if _hc >= 0:   # SWARMNAT71-4: close the hidden soldier's item range before the kernel pushes (else it swallowed them)
			_bay_hide[_hc][1] = _n
			_hc = -1
		if use_sw:
			if i < sw_next:
				continue
			if i != sw_stop:
				sw_stop = _sw_run(i, ents, ids, live)
				sw_next = sw_stop
				if sw_stop > i:
					continue
			if sw_verify and _sw_force == 1:
				_sw_fb_note(i, ids, flg_a, pframe, live)
		if use_rc and _rc_k[i] > 0:
			# G7.1 PERFDRAW71-8 record replay: the full path's arithmetic for this unit's per-frame part, in its order
			var r_raw: Vector2 = pos_a[i]
			var r_pos := r_raw
			var r_pp: Vector2 = prev_a[i]
			if r_pp.distance_squared_to(r_raw) < 4.0:
				r_pos = r_pp.lerp(r_raw, alpha)
			var r_sp := Vector2((r_pos.x - r_pos.y) * 32.0, (r_pos.x + r_pos.y) * 16.0)
			if not vr.has_point(r_sp):
				continue
			var r_fl: int = flg_a[i]
			if not terr.is_empty() and (r_fl & RenderSnap.FLAG_AIR) == 0:
				var r_ti := floori(r_pos.y) * mw + floori(r_pos.x)
				if r_ti >= 0 and r_ti < terr.size():
					r_sp.y -= float(raise.get(int(terr[r_ti]), 0))
			var r_hl := 0.0
			if hl_n > 0:
				var r_hci := floori(r_pos.y) * mw + floori(r_pos.x)
				if r_hci >= 0 and r_hci < hl_n:
					r_hl = hl_t[r_hci]
					if rp6_n > 0 and rp6[r_hci] != 0:
						r_hl = ViewUtil.ground_lift(hm6, r_pos)
					r_sp.y -= r_hl
			var r_id: int = ids[i]
			if has_cr or (has_x7 and x7.get(r_id) != null) or (has_ww and (r_fl & RenderSnap.FLAG_AIR) == 0 \
					and _ww_cells.get(Vector2i(floori(r_pos.x), floori(r_pos.y))) != null):
				rc_fall += 1   # this frame through the full path below (nothing above wrote any state)
			else:
				if r_hl != 0.0:
					gc6.lifted += 1
				if live:
					var r_le = ents.get(r_id)
					if r_le != null:
						if r_fl & RenderSnap.FLAG_AIR:
							vis_air.append(vis_units.size())
						vis_units.append(r_le)
						vis_sp.append(r_sp)
				var r_cb: int = _rc_cb[i]
				if r_cb & CB_SQ:
					gc5.squads += 1
				units_drawn += 1
				var r_c: Array = _rc_c[i]
				var r_m: int = _rc_k[i]
				var r_fi := 0
				if r_m == RC_PER:
					var r_q := i * 5
					r_fi = int(_rc_cols[i][int(t * _rc_r[r_q] * _rc_r[r_q + 1] + _rc_r[r_q + 2]) % _rc_fb[i]])
				elif r_m == RC_WALK:
					r_fi = _rc_fa[i] if int(t * 6.0 + r_id * 0.37) % 2 == 0 else _rc_fb[i]
				elif r_m == RC_OFFA or r_m == RC_OFF:
					if int(t * 0.5 + r_id * 0.61) % 4 == 0:
						r_fi = _rc_fa[i]
						gc6.command += 1
					elif r_m == RC_OFFA:
						var r_q := i * 5
						r_fi = int(_rc_cols[i][int(t * _rc_r[r_q] * _rc_r[r_q + 1] + _rc_r[r_q + 2]) % _rc_fb[i]])
						gc61.a61 += 1
				if r_cb & CB_A61:
					gc61.a61 += 1
				if r_cb & CB_TAC:
					gc5.tactical += 1
				if r_cb & CB_RAMP:
					gc5.ramp += 1
				var r_layer := 0
				if r_cb & CB_AIR:
					r_sp.y -= _rc_r[i * 5 + 3] + sin(t * 3.0 + float(r_id)) * _rc_r[i * 5 + 4]   # = G3View.air_lift
					r_layer = 1
				var r_ii := _n
				if r_ii >= _page.size():
					_reserve(r_ii * 2 + 16)
				_keys[r_ii] = r_layer * LAYER_MUL + (int(r_sp.y + r_hl) + Y_OFF) * IDX_MUL + r_ii
				if r_m == RC_FIX:
					_page[r_ii] = _rc_pg[i]
					_src[r_ii] = _rc_src[i]
					_dst[r_ii] = r_sp + _rc_off[i]
					_dsz[r_ii] = _rc_dsz[i]
					_size[r_ii] = _rc_sz[i]
					if r_cb & CB_FLIP:
						gc61.flipped += 1
				else:
					if r_fi < 0:
						r_fi = 0
					var r_row: int = _rc_row[i]
					var r_tb: Vector2 = Vector2(-1, -1) if r_fi < int(r_c[35]) else (r_c[38] as PackedVector2Array)[r_fi * 8 + r_row]
					if r_tb.x >= 0.0:
						var r_k61 := r_fi * 8 + r_row
						var r_dz: Vector2 = (r_c[39] as PackedVector2Array)[r_k61]
						_page[r_ii] = r_c[33]
						_src[r_ii] = r_tb
						_dst[r_ii] = r_sp + (r_c[40] as PackedVector2Array)[r_k61]
						_dsz[r_ii] = r_dz
						_size[r_ii] = Vector2(absf(r_dz.x), r_dz.y)
						if r_dz.x < 0.0:
							gc61.flipped += 1
					else:
						var r_fsz := Vector2(r_c[4], r_c[5])
						_page[r_ii] = r_c[2]
						_src[r_ii] = (r_c[3] as Vector2) + Vector2(r_fi if r_fi < int(r_c[35]) else 0, r_row) * r_fsz
						_dst[r_ii] = r_sp + (r_c[6] as Vector2)
						_dsz[r_ii] = r_fsz
						_size[r_ii] = r_fsz
				_mod[r_ii] = Color.WHITE
				_n = r_ii + 1
				rc_hits += 1
				continue
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
		var ww_ky := -1
		var wwv = null
		if has_ww and (flg_a[i] & RenderSnap.FLAG_AIR) == 0:
			wwv = _ww_cells.get(Vector2i(floori(pos.x), floori(pos.y)))
			if wwv != null:   # G7 (WALL7): only the owner's soldiers can stand on a wall-walk cell
				sp += Motion.wall_top_offset(wwv, pos)
				ww_ky = Motion.wall_top_depth(wwv)
				ww_drawn += 1
				_ww_occ[Vector2(wwv[0], wwv[1])] = true   # WALL7-2: this piece draws its parapet strip over him
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
		if fl & RenderSnap.FLAG_HID and ow != pf and not allies.has(ow):
			var hsp = hid_spot.get(id)   # G7 PERF7C: no default [] allocated per hidden unit
			if hsp == null or not (hsp as Array).has(my_team):
				continue
		elif fl & RenderSnap.FLAG_S7 and has_s7 and ow != pf and not allies.has(ow) 				and not RenderSnap.s7_sees(s7v, id, int(s7ot.get(ow, -1)), my_team):
			continue   # G7 PERF7D: hidden by Senses7 from this team (= the old FLAG_HID + hid_spot rule)
		var dname: String = defs[def_a[i]]
		var dfl := -1   # G7 PERFFPS7: per-def flags (1 BAY_ART, 2 the XL-remapped dropship) from the append-only snap defs table
		if def_a[i] < _dfl.size():
			dfl = _dfl[def_a[i]]
		var mod6 := Color.WHITE
		if fl & RenderSnap.FLAG_G6 and has_g6:
			# G6 (VIEW6): garrisoned units ride inside (pips on the building); art override (e.art_def) and
			# the mimic disguise for this viewer; own cloaked / submerged units translucent
			var g6e = g6u.get(id)
			# WATCH7-3 (13.9c-38 "every tower manned", owner: the walls read empty): a man garrisoned in a facility watch
			# tower stands on its open deck (the tower's wall-walk piece, wwv[5]) and is drawn there, not hidden inside.
			if G6Vis.hidden_inside(g6e) and not (wwv != null and (wwv as Array).size() > 5 and bool(wwv[5])):
				# G7 (LOOK7): roof cut away (own / allied troops clearing inside): the men inside are drawn
				var gb = statics.get(int(g6e.get("gar", -1))) if g6e is Dictionary else null
				if gb is Dictionary and roof_open_for(gb.get("roof_open"), pf, allies) and (ow == pf or allies.has(ow)):
					# FACB7-5 (13.9c-18): hidden inside the solid building; counted on its opaque badge
					var gbi := int(g6e.get("gar", -1))
					_roof_n[gbi] = int(_roof_n.get(gbi, 0)) + 1
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
				dfl = _def_flags(dname)   # G7 PERFFPS7
			mod6 = G6Vis.modulate(g6e, ow == pf or allies.has(ow))
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
		if dfl < 0:
			dfl = _def_flags(dname)   # a def the table has not seen yet
		if XL_REMAP and dfl & 2:
			dname = "g7_a_vtol_dropship_xl"  # G7 (CNFAC7-2): the upgraded, enlarged VTOL dropship
			dfl = _def_flags(dname)
		if dfl & 1:   # = BAY_ART.has(dname) (flags follow dname through the G6 override and the XL remap)
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
		var sqb: int = sq7f[i] if i < sq7_n else 0
		if sqb != 0 and gv != null:
			gv = RenderSnap.sq7_merge(gv, sqb, sq7a[i], sq7h[i])   # rare: a formation soldier with other G7 states
			sqb = 0
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
			var mfac: float = fac_a[i]
			if gv != null:
				mfac = Motion.g7_facing(gv, mfac, (fl & RenderSnap.FLAG_MOVING) != 0)
			elif sqb & 34:   # G7 PERFFPS7: only the hull (32) / sector (2) bits change the facing (Motion.g7_facing_sq)
				mfac = Motion.g7_facing_sq(sqb, sq7a[i], sq7h[i], mfac, (fl & RenderSnap.FLAG_MOVING) != 0)
			# G7.1 ANIM71 E4-2.4/2.5: companion + Machine/walker weight; hp + terrain raise for damage/terrain gait
			var hpf0: float = hp_a[i] if i < hp_a.size() else 1.0
			var raise_px := 0.0
			if not terr.is_empty() and (fl & RenderSnap.FLAG_AIR) == 0:
				var ti_m := floori(pos.y) * mw + floori(pos.x)
				if ti_m >= 0 and ti_m < terr.size():
					raise_px = float(raise.get(int(terr[ti_m]), 0))
			if ww_ky >= 0:
				raise_px = maxf(raise_px, 36.0)  # E4-2.5: wall-walk = scramble terrain cue
			motion.step(id, mcls, pos, mfac, bits, t, Motion.weight_for(dname), hpf0, raise_px)
			var mo: Vector2 = motion.out_off
			if ww_ky >= 0:
				mo = Motion.wall_motion_off(wwv, mo)   # WALL7-2: spread along the walk only, never off the firing step
			var mpx: Vector2 = motion.out_px
			if c[30] >= 0 and fl & RenderSnap.FLAG_MOVING:
				# G6.1: officers / leaders walk slightly ahead of their men
				var of: float = motion.out_face
				mpx += Vector2(cos(of) - sin(of), (cos(of) + sin(of)) * 0.5).normalized() * 2.0
			sp += Vector2((mo.x - mo.y) * 32.0, (mo.x + mo.y) * 16.0) + mpx
			var ms: PackedFloat32Array = motion.out_s   # G7 PERFFPS7: = motion.mark_screen(id, sp) on the state step() just ran
			ms[Motion.S_SX] = sp.x
			ms[Motion.S_SY] = sp.y
			if motion.out_flash > 0.0:
				var fk: float = motion.out_flash
				mod6 = Color(mod6.r * (1.0 + 0.9 * fk), mod6.g * (1.0 + 0.6 * fk), mod6.b * (1.0 + 0.5 * fk), mod6.a)
			gc61.motion += 1
		var g7c := -1
		if gv != null and not a61.is_empty():
			g7c = Motion.g7_col(a61, gv, bits, t, Motion.seed_of(id), stick)
		elif sqb != 0 and not a61.is_empty() and _sq_col_may(sqb, bits):   # G7 PERFFPS7: skip the call when it can only return -1
			g7c = Motion.g7_col_sq(a61, sqb, bits, t, Motion.seed_of(id))   # G7 PERF7D: no dict per formation soldier
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
				fi = Motion.inf_col(a61, bits, t, Motion.seed_of(id), float(motion.out_s[Motion.S_FIRE]), float(_fat.get(id, 0.0))) if mcls >= 0 else Motion.inf_col(a61, bits, t, (id % 61) * 0.0164)
				gc61.a61 += 1
		elif ad != null and c[21] >= 0 and fl & RenderSnap.FLAG_LANDED and not (bool(ad.get("hot", false)) and not (c[24] as Array).is_empty()):
			# G5 (ART-AIR ground_frames): parked in a hangar / on a pad, else landed in the open
			fi = c[21] if String(ad.ph) == "parked" or (c[22] < 0) else c[22]
		elif ad != null and (not (fl & RenderSnap.FLAG_LANDED) or bool(ad.get("hot", false))) and not (c[24] as Array).is_empty():
			# G5 (ART-AIR anim): rotor / prop frames cycle at anim_fps while airborne
			# G7.1 (CR seq 148): and while landed hot-pit serviced (e.air_hot): rotors / fans keep turning on the pad
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
		if ww_ky >= 0 and not a61.is_empty():   # G7 (WALL7-2, 13.9c-23): crouch behind the parapet / rise to fire
			var wc := Motion.wall_col(a61, int(gv.get("s7", 0)) if gv != null else 0, bits, t, Motion.seed_of(id), fi)
			if wc >= 0:
				fi = wc
			if fi == int(a61.get("crouch", -2)) or fi == int(a61.get("fire_c", -2)):
				ww_crouch += 1
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
					var hrow: int = motion.out_row   # PATH7-2 CR 6994: hysteresis (= motion.row_h(id, motion.out_face); G7 PERFFPS7)
					motion.out_s[Motion.S_ROW] = float(hrow + 1)
					var tcol := 2 if motion.recoil(id) > VehAnim61.RECOIL else (1 if vfire else 0)
					var tsz := Vector2(ts[2], ts[3])
					var tb7 = (g7u.get(id) as Dictionary).get("tb") if has_g7 and g7u.has(id) else null   # G7 TURRET7B CR 6354 (13.9c-30): drawn on the SIMULATED turret bearing
					var trow: int = posmod(int(round(float(tb7) * FACING_INV)), 8) if tb7 != null else hrow   # never laid: hull-forward
					tur = [ts[0], (ts[1] as Vector2) + Vector2(tcol, trow) * tsz, ts[4], tsz]
		var row := posmod(int(round(fac_a[i] * FACING_INV)), 8)
		if mcls >= 0:   # PATH7-2 CR 6994: hysteresis row (= motion.row_h(id, motion.out_face) from the state step() just ran; G7 PERFFPS7)
			row = motion.out_row
			motion.out_s[Motion.S_ROW] = float(row + 1)
		var fsz := Vector2(c[4], c[5])
		var layer := 0
		var lift_now := 0.0
		if ad != null:
			layer = _g5_lift(dname, id, ad, fl, fac_a[i], t, gc5, sp)  # G5: altitude by flight phase + shadow
			sp.y -= _lift
			lift_now = _lift
		elif c[12]:
			lift_now = G3View.air_lift({"def": dname, "id": id}, t)
			sp.y -= lift_now  # G3a: air units fly above their ground point
			layer = 1
		if gv != null and gv.has("bz") and float(gv.bz) > lift_now:   # G7 DRONEBAY7 CR 5833: bay drone on / rising from the workshop launch deck
			sp.y -= float(gv.bz) - lift_now
			layer = 1
		if gv != null and gv.has("bt"):   # G7 BLAST8 (13.9c-47): thrown by a blast: arc with height, ground shadow, tumble
			var b8: Array = gv.bt
			var b8k := clampf((float(stick) - 1.0 + alpha - float(b8[5])) / maxf(float(b8[6]), 1.0), 0.0, 1.0)
			var b8h := 4.0 * float(b8[4]) * b8k * (1.0 - b8k) * B8_PX_PER_M
			if art.resolve_shadow(dname, 0):
				_push(0, 1 - Y_OFF, art.out_page, art.out_src, sp + art.out_off, art.out_src.size, Color(1, 1, 1, clampf(1.0 - b8h / 90.0, 0.35, 1.0)))
			if not a61.has("k8_tum"):   # sheets without the G8 set: BLAST8's spin through four G7 poses
				var spin := b8k * float(b8[7])
				row = posmod(row + int(floor(spin * 8.0)), 8)
				if a61.has("g7_unc"):
					fi = int(a61.g7_kdown) if b8k >= 0.85 else int([a61.g7_knock, a61.g7_stumble, a61.g7_kdown, a61.g7_unc][posmod(int(floor(absf(spin) * 4.0)), 4)])
			sp.y -= b8h
			layer = 1
		if a61.has("k8_tum") and (_k8.has(id) or (gv != null and ("bt" in gv or "b8u" in gv or "unc" in gv or "kd" in gv))) \
				and _k8_live(id, gv, a61, float(stick) - 1.0 + alpha, stick, t, row, sp, far):
			fi = _k8_fi   # G8 ANIM8 (13.9c-52): launch / tumble / impact / sprawl / breathing / buckle / wake
			row = _k8_row
			sp += _k8_off
		if mcls >= 0:
			drawn7[id] = [fi, row, sp, t, dname]   # G7 MUZZLE7 CR 5592: what the muzzle flash is matched to (+ art name: REGFIX7-3)
		if fl & RenderSnap.FLAG_SHIP and fl & RenderSnap.FLAG_MOVING and not (c[26] as Dictionary).is_empty() and (c[27] < 0 or G5Art.on_water(terr_w, pos, mw)):
			# G5 (VIEW5-2, ART-NAV): wake sheet under the hull (fx_layer skips its line wake for these defs)
			var wk: Dictionary = c[26]
			if art.resolve_sheet(wk, int(t * float(wk.get("fps", 6)) + id * 0.37) % maxi(1, int(wk.get("frames", 3))), row):
				_push(layer, sp.y - 3.0, art.out_page, art.out_src, sp + art.out_off, art.out_src.size, Color(1, 1, 1, 0.85))
				gc5.wake_sheets += 1
		if has_x7:   # G7 (VIS7): frame swap / hide from vis7_layer (no-op while x7 is empty)
			var xv = x7.get(id)
			if xv != null:
				if (xv[0] as Dictionary).is_empty():
					continue
				elif art.resolve_sheet(xv[0], int(xv[1]), row if int(xv[2]) < 0 else int(xv[2])):
					_push(layer, sp.y + hl, art.out_page, art.out_src, sp + art.out_off + (xv[3] as Vector2), art.out_src.size, mod6)
					if not v61.is_empty() and ApcGun7.DEFS.has(dname):   # G7 MUZZLE7-2 CR 5911: the roof guns stay on over VIS7's frame swaps
						for gs in apc_gun7.sprites(self, id, dname, row if int(xv[2]) < 0 else int(xv[2]), motion.out_face if mcls >= 0 else fac_a[i], t, _team.get(ow, neutral), String(_ck.get(ow, "x")), sp + (xv[3] as Vector2)):
							_push(layer, sp.y + hl, gs[0], gs[1], sp + (xv[3] as Vector2) + (gs[2] as Vector2), gs[3], mod6)
					continue
		# inlined _push (capacity reserved above; G5 extras per unit - shadow, trail, markers, sling - may outgrow it)
		var ii := _n
		if ii >= _page.size():
			_reserve(ii * 2 + 16)
		# G6: sort by ground depth (sp.y + height lift) so units on a ridge order correctly against the valley
		var ky := int(sp.y + hl)
		if ww_ky >= 0:
			ky = ww_ky   # G7 (WALL7): in front of the wall piece it stands on
		if has_cr and layer == 0:
			ky = _craft_y(id, ky) if BAY_ART.has(dname) else bay_sort_y(pos, ky, _crafts)  # G7 (CNFAC7-2, CR seq 1193)
			if not BAY_ART.has(dname) and _is_inf(dname):
				_hc = _bay_hide.size()   # G7 (CNFAC7-3): checked against the hull pixels once the craft is drawn
				_bay_hide.append([ii, ii + 1, sp, ky])
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
		if use_sw and (mcls > 0 or (mcls == 0 and _sw65)) and not is_same(_sw_reg.get(id), c):   # G7.1 SWARMNAT71: plain from the next frame on?
			_sw_reg_unit(id, c, def_a[i], ow, mcls, v61, dname, defs[def_a[i]])
		if use_rc and _rc_k[i] == 0:   # G7.1 PERFDRAW71-8: first full draw of this unit in this snapshot: record it?
			_rc_k[i] = _rc_put(i, id, c, fl, a61, row, fi, ii, dname, defs[def_a[i]], sq_al > 0, gv == null and sqb == 0 and ad == null \
				and ww_ky < 0 and not has_cr and tur.is_empty() and mcls < 0 and not (has_g6 and (fl & RenderSnap.FLAG_G6) != 0) \
				and not (has_x7 and x7.get(id) != null) and not (not v61.is_empty() and ApcGun7.DEFS.has(dname)) and layer == (1 if c[12] else 0), t)
		if not tur.is_empty():  # G6.1 (ANIMC61): turret over its hull (same depth, later index sorts after)
			_push(layer, sp.y + hl, tur[0], Rect2(tur[1], tur[3]), sp + (tur[2] as Vector2), tur[3], mod6)
			gc61.turret += 1
		if not v61.is_empty() and ApcGun7.DEFS.has(dname):   # G7 MUZZLE7-2 CR 5911 (13.9c-28a): APC pods / RWS over the hull, same depth key
			for gs in apc_gun7.sprites(self, id, dname, row, motion.out_face if mcls >= 0 else fac_a[i], t, _team.get(ow, neutral), String(_ck.get(ow, "x")), sp):
				_push(layer, float(ky), gs[0], gs[1], sp + (gs[2] as Vector2), gs[3], mod6)
		if lod == 0 and motion_on and (int(_chev.get(id, 0)) > 0 or int(_pips.get(id, 0)) > 0):   # G7 PERFFPS7: no call for unmarked men
			_push_marks(id, sp, c, layer, hl, gc61)
		if fl & RenderSnap.FLAG_SLUNG:
			_g5_slung(sling.get(id, []), id, ow, fac_a[i], sp, t, gc5)
		if fl & (RenderSnap.FLAG_WOUNDED | RenderSnap.FLAG_EVAC):
			_g5_markers(sp, fl, id, t, neutral, gc5)
		if gv != null and gv.has("b8u") and not far:   # G7 BLAST8: knocked out by a blast: "zzz" over him until he wakes
			_b8_zzz(sp, t, id)
	if use_sw:
		var swr: Array = _sw.scatter(_keys, _page, _src, _size, _dst, _dsz, _mod)
		_keys = swr[0]; _page = swr[1]; _src = swr[2]; _size = swr[3]; _dst = swr[4]; _dsz = swr[5]; _mod = swr[6]
		var cn: PackedInt64Array = _sw.counts()
		gc5.aboard += cn[0]; gc6.lifted += cn[1]; gc61.motion += cn[2]; gc5.tactical += cn[3]; gc5.ramp += cn[4]
		gc6.command += cn[5]; gc61.veh += cn[6]; gc61.bank += cn[7]; gc61.recoil += cn[8]; gc61.track += cn[9]
		gc61.flipped += cn[10]
		if cn.size() > 14:   # rts_core 0.6.5: anim61 infantry frames
			gc61.a61 += cn[14]
		if _sw65 and has_cr:   # 0.6.5: bay-hide entries of the native infantry items (_apply_bay_hide is order-free)
			var bo: Array = _sw.bay_out()
			var bii: PackedInt32Array = bo[0]
			var bsp: PackedVector2Array = bo[1]
			var bky: PackedInt32Array = bo[2]
			for k in bii.size():
				_bay_hide.append([bii[k], bii[k] + 1, bsp[k], bky[k]])
		units_drawn += cn[11]
		sw_units = cn[12]
		sw_calls = cn[13]
		sw_used = true
		if cn[2] > 0:
			motion._now = t   # = what motion.step sets
	ViewUtil.prof_add("p_e2u_units", t_u)   # G7.1 PERFDRAW71-8: the unit loop alone (part of p_e2_ents)
	_units_drawn = units_drawn
	if _hc >= 0:
		_bay_hide[_hc][1] = _n
		_hc = -1
	if not _bay_hide.is_empty() and not _bay_fr.is_empty():
		_apply_bay_hide()
	if not far:
		_push_corpses(vr, t, gc61)
	elif not motion.breaks.is_empty():
		motion.prune(t)  # G7.1 ANIM71 E4-2.6: still expire wreck break-up cues when zoomed far
	# buildings, resources, wrecks, mines, charges (light dict copies in the snapshot)
	var use_rs := rs and not far   # G7.1 PERFDRAW71-8: per-snapshot static records
	rs_used = use_rs
	rs_hits = 0
	var n_st := statics.size()
	if use_rs:
		var skey := [pf, allies.hash(), _fac_e.is_empty(), n_st, _fac_e_tick, _wall_gen, _wall_dirty, _wall_nstat]
		if not is_same(sn, _rs_sn) or skey != _rs_key:
			_rs_sn = sn
			_rs_key = skey
			_rs_k.resize(n_st)
			_rs_k.fill(0)
			if _rs_gs.size() < n_st:
				_rs_wk.resize(n_st); _rs_gs.resize(n_st); _rs_ky.resize(n_st); _rs_pg.resize(n_st); _rs_src.resize(n_st)
				_rs_sz.resize(n_st); _rs_dst.resize(n_st); _rs_mod.resize(n_st); _rs_gp.resize(n_st)
	var sj := -1
	for id in statics:
		sj += 1
		if use_rs and _rs_k[sj] > 0 and not (_rs_wk[sj] != 0 and not _seen_wrecks.has(id)) \
				and not (_rs_k[sj] & 16 and not _ww_occ.is_empty() and _ww_occ.has(_rs_gp[sj])):
			if not vr.has_point(_rs_gs[sj]):
				continue
			var s_f: int = _rs_k[sj]
			if s_f & 2 and live:
				var s_le = ents.get(id)
				if s_le != null:
					vis_bld.append(s_le)
			if s_f & 4:
				bld_see_through += 1
			if s_f & 8:
				walls_linked += 1
			var s_ii := _n
			if s_ii >= _page.size():
				_reserve(s_ii * 2 + 16)
			_keys[s_ii] = _rs_ky[sj] + s_ii
			_page[s_ii] = _rs_pg[sj]
			_src[s_ii] = _rs_src[sj]
			_size[s_ii] = _rs_sz[sj]
			var s_dst: Vector2 = _rs_dst[sj]
			if _rs_wk[sj] != 0:  # G7.1 ANIM71 E4-2.6: wreck break-up still animates on cached draws
				var s_bo: Vector2 = motion.break_at(_rs_gs[sj], t)
				if s_bo != Vector2.ZERO:
					s_dst += s_bo
			_dst[s_ii] = s_dst
			_dsz[s_ii] = _rs_sz[sj]
			_mod[s_ii] = _rs_mod[sj]
			_n = s_ii + 1
			rs_hits += 1
			continue
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
					mod = bld_mod(true)
				elif live:
					var le = ents.get(id)
					if le != null:
						vis_bld.append(le)
				# FACB7-3: the facility's hardened posts (gatehouse bunker, towers, walls) hold a standing Sentinel garrison
				# (13.9c-10): they stay solid instead of see-through (the in-game shot showed the gatehouse as a ghost).
				if roof_open_for(e.get("roof_open"), pf, mv._ally_fids) and not WALL_LINK.has(String(e.get("def", ""))):
					# FACB7-5 (13.9c-18): the building stays solid while our troops clear it; an opaque badge over it shows
					# them inside (was LOOK7's see-through roof cut-away)
					var bsz := float(Content.building(String(e.get("def", ""))).get("size", 1))
					_badges.append([gd - Vector2(0.0, 18.0 + 16.0 * bsz), int(_roof_n.get(int(id), 0)), _team.get(pf, neutral)])
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
					mod = bld_mod(false, kk)   # FACB7-5 (13.9c-18): settles and darkens, never fades see-through
					sdy = (1.0 - kk) * 10.0  # (water is never lifted, so this replaces the height term)
					gc5.sinking += 1
					# G5 (VIEW5-2, ART-NAV): vehicles[def].sink columns sink_0..3 from the timer (1 - k)
					var sks = G5Art.unit_spec(String(e.get("def", ""))).get("sink")
					if sks is Dictionary and art.resolve_sheet(sks, G5Art.sink_col(kk, (sks.get("frames", []) as Array).size()),
							posmod(int(round(float(e.get("facing", 0.0)) * FACING_INV)), 8)):
						_push(0, gs.y, art.out_page, art.out_src, gs + art.out_off, art.out_src.size, mod)
						gc5.sink_sheets += 1
						continue
				# G7.1 ANIM71 E4-2.6: Machine wreck break-up offset (presentation; no FX/gore edit)
				var boff: Vector2 = motion.break_at(gd, t)
				if boff != Vector2.ZERO:
					gd += boff
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
		if (kind == "building" or kind == "wreck") and mod.a < 1.0:
			bld_see_through += 1
		if kind == "building" and _vpad_px(e):   # ART7F: dropship landing site, flat under everything that stands on it
			_push(0, 1.0 - float(Y_OFF), art.out_page, art.out_src, gd + art.out_off, art.out_src.size, mod)
			if use_rs and _rs_k[sj] == 0:
				_rs_k[sj] = _rs_put(sj, id, e, kind, ow, pf, gs, sn, 0)
			continue
		if kind == "building" and FAC_ZONE_PARTS.has(String(e.get("def", ""))) and not _fac_e.is_empty():
			continue   # FACB7-2: the magazine cell / Sentinel barracks are drawn by their zone art
		if kind == "building" and _facb_px(e):   # FACB7-2: gatehouse (ECP), wash link walls, ECP baffles
			_push(0, gs.y, art.out_page, art.out_src, gd + art.out_off + Vector2(0, sdy), art.out_src.size, mod)
			if use_rs and _rs_k[sj] == 0:
				_rs_k[sj] = _rs_put(sj, id, e, kind, ow, pf, gs, sn, 0)
			continue
		if kind == "building" and _wall_px(e):   # ART7F: facility wall autotile
			_push(0, gs.y, art.out_page, art.out_src, gd + art.out_off + Vector2(0, sdy), art.out_src.size, mod)
			walls_linked += 1
			if use_rs and _rs_k[sj] == 0:
				_rs_k[sj] = _rs_put(sj, id, e, kind, ow, pf, gs, sn, 8 | 16)
			if not _ww_occ.is_empty() and _ww_occ.has(e.pos) and _wall_front_px(e):   # WALL7-2: parapet over its soldiers
				_push(0, float(int((e.pos.x + e.pos.y) * 16.0) + Motion.WALL_DEPTH_PAD + 1), art.out_page, art.out_src, gd + art.out_off + Vector2(0, sdy), art.out_src.size, mod)
				ww_front += 1
			continue
		var col: Color = _team.get(ow if kind != "wreck" else int(e.get("from_owner", -1)), neutral)
		art.resolve_static(e, col, String(_ck.get(ow, "x")))
		if art.out_page >= 0:
			# LPFIN7: a helipad is a flat deck: drawn under everything standing on it like the dropship pad (it sorted
			# by its centre, so a helicopter parked on it sorted behind and only its tail showed past the pad's corner)
			var fdep: float = 1.0 - float(Y_OFF) if kind == "building" and _flat_pad(String(e.get("def", ""))) else gs.y
			_push(0, fdep, art.out_page, art.out_src, gd + art.out_off + Vector2(0, sdy), art.out_src.size, mod)
			if use_rs and _rs_k[sj] == 0:   # G7.1 PERFDRAW71-8: first full draw of this static in this snapshot
				_rs_k[sj] = _rs_put(sj, id, e, kind, ow, pf, gs, sn, 0)
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
		var crow := int(cp[3])
		var fly := false
		var cfi := -1
		if cp.size() > 5:   # G7 BLAST8: thrown body: arc + shadow + tumble, then the death frames from the landing
			var th: Array = cp[5]
			var k8 := clampf(age / float(th[2]), 0.0, 1.0)
			var gnd: Vector2 = csp + (th[0] as Vector2) * k8
			var a8: Dictionary = cc[31]
			var has8 := a8.has("k8_tum")
			var d8: Vector2 = th[0]
			if has8 and d8.length() > 0.5:   # G8 ANIM8: face the blast, tumble along the throw line
				crow = k8_row_of(Vector2(d8.x / 32.0 + d8.y / 16.0, d8.y / 16.0 - d8.x / 32.0) * -0.5)
			if k8 < 1.0:
				fly = true
				if art.resolve_shadow(String(th[4]), 0):
					_push(0, 1 - Y_OFF, art.out_page, art.out_src, gnd + art.out_off, art.out_src.size, Color(1, 1, 1, 0.6))
				if has8:
					cfi = k8_flight_col(a8, k8, float(th[3]))
				else:
					crow = posmod(crow + int(floor(k8 * float(th[3]) * 8.0)), 8)
			csp = gnd - Vector2(0.0, 4.0 * float(th[1]) * k8 * (1.0 - k8))
			age = 0.0 if fly else maxf(age - float(th[2]), 0.0)
			if has8 and not fly:   # G8 ANIM8: impact, bounce, skid with dust, then he lies still in his sprawl
				var dtl := age * 20.0
				var u := clampf(dtl / (K8_IMPACT + 2.0), 0.0, 1.0)
				var gp := csp + d8.normalized() * K8_SKID * (1.0 - (1.0 - u) * (1.0 - u))
				_k8_dust(gp, dtl)
				csp = gp
				if dtl < K8_IMPACT:
					cfi = int(a8.k8_imp[0 if dtl < 2.5 else 1])
					csp.y -= 2.5 * sin(PI * clampf((dtl - 1.0) / 4.0, 0.0, 1.0))
				else:
					cfi = k8_lie_col(a8, k8_variant(int(cp[0]), float(th[3])), t, int(cp[0]), false)
		art.frame_src(cc, cfi if cfi >= 0 else int(dcols[Motion.corpse_frame(age)]), crow)
		if art.out_page < 0:
			continue
		var dst: Vector2 = csp + art.out_doff  # G6.1 (ANIMC61): cropped cell offset / signed size from frame_src
		var dsz: Vector2 = art.out_dsz
		_push(1 if fly else 0, csp.y - 1.0, art.out_page, art.out_src, dst, dsz, Color(1, 1, 1, Motion.corpse_alpha(t - float(cp[4]))))
		gc61.corpses += 1


## Minimal unit dict for the art cache / fallback sprite (built only on a cache miss).
func _proxy(id: int, dname: String, ow: int, facing: float, fl: int, sq_al: int = 0) -> Dictionary:
	return {"id": id, "kind": "unit", "def": dname, "owner": ow, "facing": facing, "squad_alive": sq_al,
		"moving": (fl & RenderSnap.FLAG_MOVING) != 0, "firing": 1 if (fl & RenderSnap.FLAG_FIRING) != 0 else 0,
		"deployed": (fl & RenderSnap.FLAG_DEPLOYED) != 0, "working": (fl & RenderSnap.FLAG_WORK) != 0,
		"unloading": (fl & RenderSnap.FLAG_UNLOAD) != 0}


## G7 (BASE7-3): match_view calls this for TerrainChanged{cause:"cn_facility"} (the compound paved its footprint).
func on_cleared(cells: Array, mw: int) -> void:
	for c in cells:
		var v := Vector2i(c)
		cleared[v.y * mw + v.x] = true
	_far_key = []


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
			_push(0, gs.y, art.out_page, art.out_src, gs + art.out_off, art.out_src.size, bld_mod(true))
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
	for b in _badges:
		_draw_badge(b[0], int(b[1]), b[2])


## FACB7-5 (13.9c-18): opaque "troops inside" badge over a building our troops are clearing (no see-through walls):
## a dark-edged plate in the team colour with one white figure per man inside (up to 4, then a "+").
func _draw_badge(p: Vector2, n: int, col: Color) -> void:
	var w := 8.0 + 5.0 * float(clampi(n, 1, 4)) + (4.0 if n > 4 else 0.0)
	var r := Rect2(p - Vector2(w * 0.5, 6.0), Vector2(w, 12.0))
	draw_rect(r.grow(1.0), BADGE_EDGE)
	draw_rect(r, Color(col.r, col.g, col.b, 1.0))
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(w - 2.0, 2.0)), Color(minf(col.r + 0.25, 1.0), minf(col.g + 0.25, 1.0), minf(col.b + 0.25, 1.0), 1.0))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-3, 6), p + Vector2(3, 6), p + Vector2(0, 10)]), BADGE_EDGE)
	for k in clampi(n, 1, 4):
		var x := r.position.x + 5.0 + 5.0 * float(k)
		draw_rect(Rect2(Vector2(x - 1.0, r.position.y + 3.0), Vector2(2.0, 2.0)), BADGE_FIG)   # head
		draw_rect(Rect2(Vector2(x - 1.5, r.position.y + 5.5), Vector2(3.0, 4.0)), BADGE_FIG)   # body
	if n > 4:
		draw_rect(Rect2(Vector2(r.end.x - 6.0, r.position.y + 5.5), Vector2(3.0, 1.0)), BADGE_FIG)
		draw_rect(Rect2(Vector2(r.end.x - 5.0, r.position.y + 4.5), Vector2(1.0, 3.0)), BADGE_FIG)


## FACB7-5 (owner 13.9c-18 "NO transparent anything"): the modulate of a building / wreck sprite, always opaque: a
## remembered enemy building out of sight is greyed (GHOST_MOD, alpha 1); a sinking wreck darkens as it settles (sink_k
## 1 -> 0) instead of fading; a building our troops are clearing stays solid (they show on an opaque badge).
static func bld_mod(remembered: bool, sink_k: float = 1.0) -> Color:
	if remembered:
		return Color(GHOST_MOD.r, GHOST_MOD.g, GHOST_MOD.b, 1.0)
	var k := clampf(sink_k, 0.0, 1.0)
	return Color(0.5 + 0.5 * k, 0.5 + 0.5 * k, 0.54 + 0.46 * k, 1.0)


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
	var cy := _craft_y(id, int(sp.y + hl))
	_push(0, float(cy), int(c[2]), Rect2((c[3] as Vector2) + Vector2(col, row) * fsz, fsz), sp + (c[6] as Vector2), fsz, mod6)
	bay_drawn += 1
	if not _crafts.is_empty():
		var img: Image = ArtCat._image(String(art._unit_spec(sheet).get("file", "")))
		if img != null:
			_bay_fr[id] = [img, Vector2(col, row) * fsz, sp + (c[6] as Vector2), fsz, cy]
	return true


# ================================================================ G7 (CNFAC7-3): nobody shows from behind a dropship
## Owner (look checkpoint rev3): "dont show a person thats behind the dropship(s)". A soldier sorted behind a landed
## craft whose feet the hull's drawn pixels cover is not drawn at all (otherwise his head and chest stick out above the
## tail and he reads as standing on the hull). Soldiers in front, or behind but clear of the silhouette, are untouched.
func _is_inf(dname: String) -> bool:
	var v = _inf_cache.get(dname)
	if v == null:
		v = (ArtCat.manifest().get("infantry", {}) as Dictionary).has(dname)
		_inf_cache[dname] = v
	return v


func _apply_bay_hide() -> void:
	for hc in _bay_hide:
		var feet: Vector2 = hc[2]
		for cid in _bay_fr:
			var fr: Array = _bay_fr[cid]
			if int(hc[3]) < int(fr[4]) and bay_feet_covered(fr[0], fr[1], fr[2], fr[3], feet):
				for k in range(int(hc[0]), int(hc[1])):
					_dsz[k] = Vector2.ZERO
				bay_hidden += 1
				break


## True when the craft frame (sheet img, frame origin in the sheet, drawn top-left dst, frame size) has an opaque hull
## pixel on a soldier standing at screen point g (world px): at his feet (+-4 px), his lower body, or right under his
## feet (feet resting on the hull's outline read as "standing on the dropship").
static func bay_feet_covered(img: Image, origin: Vector2, dst: Vector2, fsz: Vector2, g: Vector2) -> bool:
	for o in BAY_PROBE:
		var lp: Vector2 = g + (o as Vector2) - dst
		if lp.x < 0.0 or lp.y < 0.0 or lp.x >= fsz.x or lp.y >= fsz.y:
			continue
		var px := Vector2i(origin + lp)
		if px.x < img.get_width() and px.y < img.get_height() and img.get_pixel(px.x, px.y).a > BAY_HIDE_A:
			return true
	return false


# ================================================================ G7 (CNFAC7-3): facility floors and zone buildings
## The compound interior from CnFacility.render_entries (display only): concrete loading pad (placeholder tile),
## ARTCN7 helipad (lit while a dropship sits on it), garages (lockdown art while sealed), decontamination line, gate.
## ART7F (13.9c "buildings inside counter nanite facility are flickering"): the old code read the world only on
## frames where mv.world_readable() (no threaded sim step in flight) and drew NOTHING of the compound on the others,
## so pad, helipad, garages, decon and gate blinked out on every busy frame. Now the entries are re-read once per
## new snapshot tick while the world is readable and reused on every other frame. fac_cache_off = old behaviour
## (playtest A/B only); fac_sig = hash of this frame's facility draw list (frame-by-frame flicker capture).
func _push_fac(w, vr: Rect2, stick: int = -1) -> void:
	fac_drawn = 0
	fac_sig = 0
	if w == null:
		fac_busy += 1   # this frame's refresh ran while a sim step was in flight (world not readable)
	if fac_cache_off:
		if w == null or not CnFacility.active(w):
			return
		_fac_e = CnFacility.render_entries(w)
		FacGate7.sync(w, _fac_e, stick)
	elif w != null and (stick != _fac_e_tick or stick < 0):
		_fac_e_tick = stick
		_fac_e = CnFacility.render_entries(w) if CnFacility.active(w) else []
		FacGate7.sync(w, _fac_e, stick)
		_wall_dirty = _wall_dirty or _fac_e.size() != _wall_nfac
	var man: Dictionary = ArtCat.manifest().get("buildings", {})
	for F in _fac_e:
		var zs: Dictionary = F.zones
		var hp: Array = zs.get("helipad", [0, 0, 0, 0])
		var ctr := Vector2(float(hp[0]) + float(hp[2]) * 0.5, float(hp[1]) + float(hp[3]) * 0.5)
		if not mv.cell_explored(Vector2i(ctr)):
			continue
		var lock := bool(F.get("lock", false))
		var pad: Array = zs.get("pad", [])
		if pad.size() == 4:
			_push_pad(Rect2(float(pad[0]), float(pad[1]), float(pad[2]), float(pad[3])), vr, lock)
		_push_zone(man, "g7_cn_helipad", "lit" if int(F.get("heli", 0)) != 0 and not lock else "built", hp, vr, true)
		var gts: Array = F.get("garage_team", [])
		var grs: Array = F.get("garage_rects", [])
		var gt: Array = zs.get("gate_outer", zs.get("gate", [0, 0, 0, 0]))   # BASE7-3: "gate" retired (two-layer entry)
		var gmx := float(gt[0]) + float(gt[2]) * 0.5
		for gi in grs.size():   # a closed shed: it sorts at its door face, so an APC parked inside is hidden by it
			var occ := gi < gts.size() and int(gts[gi]) != 0
			var gst := "lockdown" if lock else ("open" if occ else "built")
			if float(grs[gi][0]) + float(grs[gi][2]) * 0.5 > gmx:   # ART7E: east-side garages face west (door on -x = rot_2 art)
				gst = "rot_2" if gst == "built" else "rot_2_" + gst
			_push_zone(man, "g7_cn_garage", gst, grs[gi], vr, false, float(grs[gi][2]) * 8.0)
		# BASE7-3 (ORCH): the old single gate + blue spray box (g7_cn_gate / g7_cn_decon) are retired; the two-layer
		# entry (gate_outer, apc_wash, gate_inner) and the decon_hall draw from FAC7F_ZONES below.
		var faces: Dictionary = F.get("faces", {})
		var stk: Dictionary = F.get("stacked", {})   # FACB7-5 (13.9c-18): an upper storey is drawn by its host's art
		for zi in FAC7F_ZONES:   # ART7F: finished interior buildings (planning room, drone bay, workshop, range, lab)
			var zr: Array = zs.get(zi[0], [])
			if zr.size() == 4 and not stk.has(zi[0]):
				# FACB7-2 (13.9c-8/-9): the layout's own door sides win (the inner APC gate opens on the APC axis
				# like the outer gate instead of facing the y20 lane sideways)
				var zf := int(faces[zi[0]]) if faces.has(zi[0]) else _door_side(zr, F)
				var sfx := "_lockdown" if lock else ""
				if zi[0] == "gate_outer" or zi[0] == "gate_inner":   # GATE7 CR 5743 (13.9c-26): blast-door travel / lock-bar frames from the sim gate state
					sfx = FacGate7.suffix(F, zi[0], lock, stick)
				if (zi[0] == "magazine" and not bool(F.get("mag", true))) or (zi[0] == "barracks" and not bool(F.get("bar", true))):
					sfx = "_ruin"
				_push_zone(man, zi[1], "rot_%d%s" % [zf, sfx], zr, vr, false, float(zi[2]) * (float(zr[2]) + float(zr[3])) * 4.0)
		for zi in FAC7F_FLAT:
			var zr: Array = zs.get(zi[0], [])
			if zr.size() == 4:
				var zf := int(faces[zi[0]]) if faces.has(zi[0]) else _door_side(zr, F)
				_push_zone(man, zi[1], "rot_%d%s" % [zf, "_lockdown" if lock else ""], zr, vr, true)


## ART7F: door side of an interior building (0 +x, 1 +y, 2 -x, 3 -y): the side whose outside strip touches the most
## lane cells x lane width (the road it is served from); no lane -> toward the compound centre. Cached per zone rect.
var _door_f: Dictionary = {}
func _door_side(r: Array, F: Dictionary) -> int:
	var k := str(r)
	if not _door_f.has(k):
		_door_f[k] = door_side_of(r, F)
	return int(_door_f[k])


static func door_side_of(r: Array, F: Dictionary) -> int:
	var x0 := int(r[0])
	var y0 := int(r[1])
	var x1 := x0 + int(r[2])
	var y1 := y0 + int(r[3])
	var strips := [Rect2i(x1, y0, 1, y1 - y0), Rect2i(x0, y1, x1 - x0, 1), Rect2i(x0 - 1, y0, 1, y1 - y0), Rect2i(x0, y0 - 1, x1 - x0, 1)]
	var best := -1
	var bn := 0
	for f in 4:
		var n := 0
		for l in F.get("lanes", []):
			var li := Rect2i(int(l[0]), int(l[1]), int(l[2]), int(l[3])).intersection(strips[f])
			n += li.get_area() * mini(int(l[2]), int(l[3]))   # weighted by lane width: the main road wins a tie
		if n > bn:
			bn = n
			best = f
	if best < 0:
		var cp: Array = F.get("compound", [0, 0, 0, 0])
		var d := Vector2(float(cp[0]) + float(cp[2]) * 0.5 - (float(x0 + x1) * 0.5), float(cp[1]) + float(cp[3]) * 0.5 - (float(y0 + y1) * 0.5))
		best = (0 if d.x > 0.0 else 2) if absf(d.x) > absf(d.y) else (1 if d.y > 0.0 else 3)
	return best


# ================================================================ ART7F: facility wall autotile
## Facility blast walls (2x2 segments) pick conn_<m> (N1 E2 S4 W8) from their neighbours: other wall segments, the
## hardened towers, the gate checkpoint and the gate zone, so the ring reads as one continuous wall with corners,
## T-joins, ends and gate pieces. Display only (the sim keeps one cn_blast_wall def). Falls back to the old art when
## the g7_fac_wall sheet is missing.
## ART7F-2 (13.9c-3): hardened towers use the g7_fac_tower sheet the same way (bastion + wall arms on linked sides).
const WALL_SHEET := {"cn_blast_wall": "g7_fac_wall", "cn_tower": "g7_fac_tower"}


func _wall_px(e: Dictionary) -> bool:
	var sk: String = WALL_SHEET.get(String(e.get("def", "")), "")
	if sk == "":
		return false
	var b: Dictionary = ArtCat.manifest().get("buildings", {}).get(sk, {})
	if b.is_empty():
		return false
	if _wall_dirty or int((mv.snap.get("statics", {}) as Dictionary).size()) != _wall_nstat:
		_wall_rebuild()
	var m := wall_mask(_wall_cells, e.pos)
	var spec := {"file": String(b.states.built.file), "fw": int(b.fw), "fh": int(b.fh), "pivot": b.pivot}
	return art.resolve_sheet(spec, m, _wall_row(b, e))


## WALL7-2: sheet row of a ring piece: outer quadrant * 2 + damaged on the 8-row WALL7-2 sheets, damaged alone on
## the older 2-row sheets.
func _wall_row(b: Dictionary, e: Dictionary) -> int:
	var dmg := 1 if float(e.get("hp", 1.0)) < 0.5 else 0
	if not (b.states as Dictionary).has("front"):
		return dmg
	return Motion.wall_quadrant(e.pos, _ww_centres) * 2 + dmg


## WALL7-2 (13.9c-23): the camera-side parapet / rail strip of ring piece e (sheet state "front"), resolved into art.out_*.
func _wall_front_px(e: Dictionary) -> bool:
	var b: Dictionary = ArtCat.manifest().get("buildings", {}).get(WALL_SHEET.get(String(e.get("def", "")), ""), {})
	var fs: Dictionary = (b.get("states", {}) as Dictionary).get("front", {})
	if fs.is_empty():
		return false
	var spec := {"file": String(fs.file), "fw": int(b.fw), "fh": int(b.fh), "pivot": b.pivot}
	return art.resolve_sheet(spec, wall_mask(_wall_cells, e.pos), _wall_row(b, e))


## FACB7-2 (13.9c-8/-9): facility parts with their own g7_fac7f art. cn_checkpoint -> g7_fac_gatehouse (state from the
## facility's mantrap display state: open_out / open_in / lockdown / built, _damaged under 50% hp); cn_link_wall ->
## g7_fac_linkwall sheet column side * 4 + N1 + S2 (side 0 when the outer gate's centre lies east of the cell);
## cn_ecp_baffle -> g7_fac_baffle sheet column = conn mask over baffles + wall-line cells. false = not handled.
func _facb_px(e: Dictionary) -> bool:
	var d := String(e.get("def", ""))
	if d != "cn_checkpoint" and d != "cn_link_wall" and d != "cn_ecp_baffle":
		return false
	var man: Dictionary = ArtCat.manifest().get("buildings", {})
	var dmg := 1 if float(e.get("hp", 1.0)) < 0.5 else 0
	if d == "cn_checkpoint":
		var b: Dictionary = man.get("g7_fac_gatehouse", {})
		if b.is_empty():
			return false
		var st := "built"
		for F in _fac_e:
			if int(F.get("cp", 0)) == int(e.get("id", -1)):
				var mt: Array = F.get("mantrap", [])
				if bool(F.get("lock", false)) or (mt.size() == 3 and bool(mt[2])):
					st = "lockdown"
				elif mt.size() == 3 and bool(mt[0]):
					st = "open_out"
				elif mt.size() == 3 and bool(mt[1]):
					st = "open_in"
		var s: Dictionary = (b.states as Dictionary).get(st + ("_damaged" if dmg == 1 else ""), b.states.get("built", {}))
		return not s.is_empty() and art.resolve_sheet({"file": String(s.file), "fw": int(b.fw), "fh": int(b.fh), "pivot": b.pivot}, 0, 0)
	var sk := "g7_fac_linkwall" if d == "cn_link_wall" else "g7_fac_baffle"
	var b2: Dictionary = man.get(sk, {})
	if b2.is_empty():
		return false
	if _wall_dirty or int((mv.snap.get("statics", {}) as Dictionary).size()) != _wall_nstat:
		_wall_rebuild()
	var p: Vector2 = e.pos
	var c := Vector2i(floori(p.x), floori(p.y))
	var col := 0
	if d == "cn_link_wall":
		var side := 0
		for F in _fac_e:
			var cp: Array = F.get("compound", [0, 0, 0, 0])
			if Rect2(float(cp[0]), float(cp[1]), float(cp[2]), float(cp[3])).has_point(p):
				var gt: Array = (F.zones as Dictionary).get("gate_outer", [0, 0, 0, 0])
				side = 0 if float(gt[0]) + float(gt[2]) * 0.5 > p.x else 1
		col = side * 4 + (1 if _lb_cells.get(c + Vector2i(0, -1), "") == "link" else 0) + (2 if _lb_cells.get(c + Vector2i(0, 1), "") == "link" else 0)
	else:
		var nb := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
		for k in 4:
			var q: Vector2i = c + nb[k]
			if _lb_cells.get(q, "") == "baffle" or _wall_cells.has(q):
				col |= 1 << k
	return art.resolve_sheet({"file": String(b2.states.built.file), "fw": int(b2.fw), "fh": int(b2.fh), "pivot": b2.pivot}, col, dmg)


## LPFIN7: flat helicopter decks (building defs with air_field "helipad"), cached per def.
var _fpad: Dictionary = {}
func _flat_pad(def: String) -> bool:
	var v = _fpad.get(def)
	if v == null:
		# G7.1 PERFDRAW71-6: the FARP (air_field "forward_helipad", AIRFIX71 A2) is a flat pad too, else its body sorts
		# in front of the helicopters landed on it (pt71_perfdraw71 hot-pit shots showed the block hiding the heli)
		var bd: Dictionary = Content.building(def)
		v = String(bd.get("air_field", "")) in ["helipad", "forward_helipad"] or bool(bd.get("farp", false))
		_fpad[def] = v
	return v


## ART7F: a_g7_vtol_pad art (rot_<facing_i> = approach side; _damaged under 50% hp; build stages).
func _vpad_px(e: Dictionary) -> bool:
	if String(e.get("def", "")) != "a_g7_vtol_pad":
		return false
	var b: Dictionary = ArtCat.manifest().get("buildings", {}).get("a_g7_vtol_pad", {})
	if b.is_empty():
		return false
	# G8 ART8: pad approach side vs camera facing.
	var VF = load("res://presentation/view/view_facing.gd")
	var VU = load("res://presentation/view/view_util.gd")
	var authored := posmod(int(e.get("facing_i", 0)), 4)
	var cam := int(VU.view_facing) if VU != null else 0
	var st := "rot_%d" % (VF.art_side(authored, cam) if VF != null else authored)
	if not bool(e.get("built", true)):
		st += "_build_%d" % clampi(int(float(e.get("progress", 0.0)) * 3.0), 0, 2)
	elif float(e.get("hp", 1.0)) < 0.5:
		st += "_damaged"
	var s: Dictionary = (b.states as Dictionary).get(st, b.states.get("built", {}))
	return not s.is_empty() and art.resolve_sheet({"file": String(s.file), "fw": int(b.fw), "fh": int(b.fh), "pivot": b.pivot}, 0, 0)


## Conn mask (N1 E2 S4 W8) of a 2x2 wall segment centred at p, from the wall-line cell set.
static func wall_mask(cells: Dictionary, p: Vector2) -> int:
	var o := Vector2i(floori(p.x - 1.0 + 0.01), floori(p.y - 1.0 + 0.01))
	var m := 0
	if cells.has(o + Vector2i(0, -1)):
		m |= 1
	if cells.has(o + Vector2i(2, 0)):
		m |= 2
	if cells.has(o + Vector2i(0, 2)):
		m |= 4
	if cells.has(o + Vector2i(-1, 0)):
		m |= 8
	return m


## Cells covered by facility wall-line parts (walls, towers, checkpoint: 2x2, keyed by centre pos) and gate zones.
static func wall_cells_of(statics: Dictionary, facs: Array) -> Dictionary:
	var cells := {}
	for id in statics:
		var e: Dictionary = statics[id]
		if not WALL_LINK.has(String(e.get("def", ""))) or String(e.get("kind", "building")) != "building":
			continue
		var p: Vector2 = e.pos
		var o := Vector2i(floori(p.x - 1.0 + 0.01), floori(p.y - 1.0 + 0.01))
		for dy in 2:
			for dx in 2:
				cells[o + Vector2i(dx, dy)] = true
	for F in facs:
		for gk in ["gate", "gate_outer", "gate_inner"]:   # ART7F-2: either gate layer ends the wall run on it
			var g: Array = (F.zones as Dictionary).get(gk, [])
			if g.size() == 4:
				for y in range(int(g[1]), int(g[1]) + int(g[3])):
					for x in range(int(g[0]), int(g[0]) + int(g[2])):
						cells[Vector2i(x, y)] = true
	return cells


var _wall_gen := 0   # G7.1 PERFDRAW71-8: bumps on every wall-line rebuild (static records key)
func _wall_rebuild() -> void:
	_wall_gen += 1
	_wall_dirty = false
	_wall_nfac = _fac_e.size()
	var sn: Dictionary = mv.snap if mv != null else {}
	var statics: Dictionary = sn.get("statics", {})
	_wall_nstat = statics.size()
	_wall_cells = wall_cells_of(statics, _fac_e)
	_ww_centres = []   # WALL7-2: compound centres -> each ring piece's outer side (parapet side / inset)
	for F in _fac_e:
		var cp: Array = F.get("compound", [])
		if cp.size() == 4:
			_ww_centres.append(Vector2(float(cp[0]) + float(cp[2]) * 0.5, float(cp[1]) + float(cp[3]) * 0.5))
	_ww_cells = Motion.wall_walk_cells(statics, _ww_centres) if not _fac_e.is_empty() else {}   # G7 (WALL7)
	_lb_cells = {}
	for id in statics:   # FACB7-2: link wall + baffle cells (1x1) for their piece / mask choice
		var d := String(statics[id].get("def", ""))
		if d == "cn_link_wall" or d == "cn_ecp_baffle":
			var p: Vector2 = statics[id].pos
			_lb_cells[Vector2i(floori(p.x), floori(p.y))] = "link" if d == "cn_link_wall" else "baffle"


## One zone sprite at the centre of rect r [x, y, w, h] (tiles). Flat art sorts under everything; the rest by depth.
func _push_zone(man: Dictionary, key: String, st: String, r: Array, vr: Rect2, flat: bool, dk: float = 0.0) -> void:
	var b: Dictionary = man.get(key, {})
	if b.is_empty() or r.size() < 4:
		return
	var sts: Dictionary = b.get("states", {})
	var s: Dictionary = sts.get(st, sts.get("built", {}))
	if s.is_empty():
		return
	var g := Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)
	var gs := Vector2((g.x - g.y) * 32.0, (g.x + g.y) * 16.0)
	if not vr.grow(256.0).has_point(gs):
		return
	var spec := {"file": String(s.file), "fw": int(b.get("fw", 0)), "fh": int(b.get("fh", 0)), "pivot": b.get("pivot", [0, 0])}
	if art.resolve_sheet(spec, 0, 0):
		_push(0, (1.0 - float(Y_OFF)) if flat else gs.y + dk, art.out_page, art.out_src, gs + art.out_off, art.out_src.size, Color.WHITE)
		fac_drawn += 1
		fac_sig = (fac_sig * 31 + (key + st).hash() + int(gs.x) * 7 + int(gs.y + dk) * 13 + art.out_page) & 0x3fffffff


## ART7E loading pad: one flat tile per cell from the g7_cn_pad tile sheet (fw 64, fh 44, pivot = cell centre).
## Column = _pad_col (same rule as tools/art/g7_cn_facility.gd pad_frame); row 1 = lockdown (red lamps).
func _push_pad(r: Rect2, vr: Rect2, lock: bool) -> void:
	var b: Dictionary = ArtCat.manifest().get("buildings", {}).get("g7_cn_pad", {})
	var s: Dictionary = (b.get("states", {}) as Dictionary).get("built", {})
	if s.is_empty():
		return
	var spec := {"file": String(s.file), "fw": int(b.get("fw", 64)), "fh": int(b.get("fh", 44)), "pivot": b.get("pivot", [32, 24])}
	var x0 := int(r.position.x)
	var y0 := int(r.position.y)
	var x1 := int(r.end.x) - 1
	var y1 := int(r.end.y) - 1
	var g := vr.grow(64.0)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var gs := Vector2(float(x - y) * 32.0, float(x + y + 1) * 16.0)
			if g.has_point(gs) and art.resolve_sheet(spec, _pad_col(x, y, x0, y0, x1, y1), 1 if lock else 0):
				_push(0, -float(Y_OFF), art.out_page, art.out_src, gs + art.out_off, art.out_src.size, Color.WHITE)
				fac_drawn += 1
				fac_sig = (fac_sig * 31 + int(art.out_src.position.x) + int(gs.x) * 7 + int(gs.y) * 13) & 0x3fffffff


## Pad tile column: corners 9..12 (NW NE SE SW), edges 5..8 (N E S W), bay dividers 4 (west edge) / 13 (centre)
## on the 3-tile loading-slot boundaries around the pad centre, tie-downs 3, plain slab 0..2.
static func _pad_col(x: int, y: int, x0: int, y0: int, x1: int, y1: int) -> int:
	var w := x == x0
	var e := x == x1
	var n := y == y0
	var s := y == y1
	if n and w:
		return 9
	if n and e:
		return 10
	if s and e:
		return 11
	if s and w:
		return 12
	if n:
		return 5
	if e:
		return 6
	if s:
		return 7
	if w:
		return 8
	var sm := x0 + x1 + 1
	if posmod(2 * x - sm, 6) == 0:
		return 4
	if posmod(2 * x + 1 - sm, 6) == 0:
		return 13
	if posmod(x - x0, 3) == 2 and (y - y0) % 2 == 1:
		return 3
	return posmod(x * 7 + y * 13, 3)


## ---- G7.1 SWARMNAT71: native unit kernel glue (rts_core RtsSwarmDraw; docs/SWARM_NATIVE71.md) ----
func _sw_init() -> bool:
	if _sw == null and ClassDB.class_exists("RtsSwarmDraw"):
		_sw = ClassDB.instantiate("RtsSwarmDraw")
		_sw65 = _sw != null and _sw.has_method("set_fat")
	return _sw != null


## Hands the kernel this frame's snapshot arrays and tables; false = it cannot run this frame (GDScript path only).
func _sw_begin(sn: Dictionary, alpha: float, t: float, vr: Rect2, mw: int, pf: int, live: bool, pframe: int,
		ids: PackedInt32Array, raise: Dictionary, hl_t: PackedFloat32Array, rp6_n: int, rp6: PackedByteArray,
		vis: PackedByteArray, ally_vis: Array, has_g6: bool, has_ww: bool, squad: Dictionary, g7u: Dictionary,
		g5air: Dictionary, sling: Dictionary) -> bool:
	var rz := PackedInt32Array()
	rz.resize(256)
	for code in raise:
		var ci := int(code)
		if ci < 0 or ci >= 256 or float(raise[code]) != float(int(raise[code])):
			return false
		rz[ci] = int(raise[code])
	var terr_all: PackedByteArray = sn.get("terrain", PackedByteArray())
	var terr: PackedByteArray = terr_all if not raise.is_empty() else PackedByteArray()
	var ally := PackedByteArray()
	for av in ally_vis:
		if (av as PackedByteArray).size() != vis.size():
			return false
		ally.append_array(av)
	var ww := PackedByteArray()
	if has_ww:   # wall-walk cells: those units take the GDScript path
		var n_c: int = terr_all.size() if terr_all.size() > 0 else mw * mw
		if _sw_ww.size() != n_c:
			_sw_ww.resize(n_c)
		_sw_ww.fill(0)
		for k in _ww_cells:
			var kc: Vector2i = k
			var j := kc.y * mw + kc.x
			if kc.x >= 0 and kc.x < mw and j >= 0 and j < n_c:
				_sw_ww[j] = 1
		ww = _sw_ww
	var keys := PackedInt32Array()
	for d in [squad, g7u, g5air, sling, x7]:
		if not (d as Dictionary).is_empty():
			keys.append_array(PackedInt32Array((d as Dictionary).keys()))
	if not _crafts.is_empty():   # SWARMNAT71-3: units near a landed dropship sort by bay_sort_y: GDScript path
		var pa: PackedVector2Array = sn.pos   # raw pos; 10.5 > 7.5 (bay_sort_y reach) + the interpolation step (< 3)
		for j in ids.size():
			var q: Vector2 = pa[j]
			for cr in _crafts:
				var cp: Vector2 = cr[0]
				if absf(q.x - cp.x) + absf(q.y - cp.y) <= 10.5:
					keys.append(ids[j])
					break
	var sc :=PackedFloat64Array([alpha, t, vr.position.x, vr.position.y, vr.size.x, vr.size.y, mw, pf, 1.0 if live else 0.0,
		pframe, lod, 1.0 if has_g6 else 0.0, 1.0 if has_ww else 0.0, 0.0 if _crafts.is_empty() else 1.0])
	var inp := [ids, sn.pos, sn.prev, sn.facing, sn.def, sn.owner, sn.flags, sn.get("hp", PackedFloat32Array()),
		sn.get("sq7f", PackedByteArray()), terr, rz, hl_t, rp6 if rp6_n > 0 else PackedByteArray(), vis, ally, ally_vis.size(),
		ww, _dfl, keys, sc]
	return bool(_sw.begin(inp, motion.vs, drawn7))


## Kernel from unit index i; returns the index it stopped at (that unit is drawn by the GDScript loop).
func _sw_run(i: int, ents: Dictionary, ids: PackedInt32Array, live: bool) -> int:
	var s: int = _sw.run(i, _n, motion._cdt, motion._ck, motion._cb)
	_n = _sw.n_now()
	if _n + 16 >= _page.size():
		_reserve(_n * 2 + 16)
	if _sw.cache_changed():
		motion._cdt = _sw.cdt()
		motion._ck = _sw.ck()
		motion._cb = _sw.cb()
	if live:
		var vi: PackedInt32Array = _sw.vis_idx()
		if not vi.is_empty():
			var vp: PackedVector2Array = _sw.vis_pts()
			for k in vi.size():
				var le = ents.get(ids[vi[k]])
				if le != null:
					vis_units.append(le)
					vis_sp.append(vp[k])
	return s


static func _sw_v(v: Dictionary, k: String) -> int:
	return int(v[k]) if v.has(k) else SW_ABS


## The unit the GDScript path just drew: registers its art record when its draw is one the kernel reproduces.
func _sw_reg_unit(id: int, c: Array, dx: int, ow: int, mcls: int, v61: Dictionary, dname: String, d0: String) -> void:
	_sw_reg[id] = c
	var a61f := _sw_a61_flat(c[31] as Dictionary) if _sw65 else PackedInt32Array()
	var a61_ok: bool = (c[31] as Dictionary).is_empty() or (_sw65 and a61f.size() == 26)
	if dname != d0 or not a61_ok or bool(c[12]) or int(c[27]) >= 0 or int(c[16]) != 0 \
			or int(c[2]) < 0 or v61.has("turret") or ApcGun7.DEFS.has(dname) or dx >= _dfl.size() or _dfl[dx] != 0 \
			or (mcls == Motion.CLS_INF and not _sw65):
		if sw_verify:   # SWARMNAT71-3 diag: first reason
			var why := "dname" if dname != d0 else "a61" if not a61_ok else "c12" if bool(c[12]) \
				else "c27" if int(c[27]) >= 0 else "c16" if int(c[16]) != 0 else "nopage" if int(c[2]) < 0 \
				else "turret" if v61.has("turret") else "apcgun" if ApcGun7.DEFS.has(dname) else "dfl" if (dx >= _dfl.size() or _dfl[dx] != 0) else "inf"
			sw_fg[why + ":" + dname] = int(sw_fg.get(why + ":" + dname, 0)) + 1
		_sw.forget(id)
		return
	var mvv: PackedInt32Array = PackedInt32Array(v61.move) if v61.get("move") is Array else PackedInt32Array()
	var trk: PackedInt32Array = PackedInt32Array(v61.track) if v61.get("track") is Array else PackedInt32Array()
	_sw.reg(id, [dx, ow, c[2], c[3], c[4], c[5], c[6], c[7], 1 if bool(c[8]) else 0, c[9], c[10], c[11], c[13], c[14], c[15],
		c[18], c[20], c[29], c[30], c[35], c[33], c[38], c[39], c[40], mcls, 0 if v61.is_empty() else 1,
		_sw_v(v61, "recoil"), _sw_v(v61, "bank_l"), _sw_v(v61, "bank_r"), mvv, trk, _sw_v(v61, "burner"),
		_sw_v(v61, "damaged"), _sw_v(v61, "pulse"), 1 if (v61.has("track") or v61.has("move")) else 0, dname,
		a61f, 1 if _is_inf(dname) else 0])
	if _post.has(id) or _chev.has(id) or _pips.has(id):
		_sw.set_post(id, int(_post.get(id, 0)), int(_chev.get(id, 0)) > 0 or int(_pips.get(id, 0)) > 0)


## rts_core 0.6.5 record of an anim61 set: walk6 run6 crawl2 reload2 throw2 idle2 crouch prone fire_s fire_c fire_p wounded
## (26 ints); empty when the set has keys some path reads for an unmarked unit that the kernel does not port (k8_tum: G8
## ANIM8 state; swalk: EXO7-3 suits) or a column list of another length.
static func _sw_a61_flat(a: Dictionary) -> PackedInt32Array:
	var r := PackedInt32Array()
	if a.is_empty() or a.has("k8_tum") or a.has("swalk"):
		return r
	for k in [["walk", 6], ["run", 6], ["crawl", 2], ["reload", 2], ["throw", 2], ["idle", 2]]:
		var v = a.get(k[0])
		if not (v is Array or v is PackedInt32Array) or v.size() != int(k[1]):
			return PackedInt32Array()
		for x in v:
			r.append(int(x))
	for k in ["crouch", "prone", "fire_s", "fire_c", "fire_p", "wounded"]:
		if not a.has(k):
			return PackedInt32Array()
		r.append(int(a[k]))
	return r


static func _sw_vs_copy(d: Dictionary) -> Dictionary:
	var r := {}
	for q in d:
		r[q] = (d[q] as PackedFloat32Array).duplicate()
	return r


## SWARMNAT71_VERIFY=1: GDScript path, then the kernel from the same state, compared item for item.
func _sw_verify_refresh() -> void:
	var mvs := _sw_vs_copy(motion.vs)
	var k8s := {}
	for q in _k8:
		k8s[q] = (_k8[q] as Array).duplicate()
	var mcorp: Array = motion.corpses.duplicate()
	var d7: Dictionary = drawn7.duplicate(true)
	var ud0 := _units_drawn
	var c0 := [motion._cdt, (motion._ck as PackedFloat64Array).duplicate(), motion._cb, motion._now, motion._gc_t]   # SWARMNAT71-3: + prune's 5 s GC clock
	_sw_force = 0
	_refresh(rc_on, rc_on or rs_on)
	var a := _rc_capture()
	var va := _sw_vs_copy(motion.vs)
	var da: Dictionary = drawn7.duplicate(true)
	motion.vs = mvs
	_k8 = k8s
	motion.corpses = mcorp
	drawn7 = d7
	_units_drawn = ud0
	motion._cdt = c0[0]
	motion._ck = c0[1]
	motion._cb = c0[2]
	motion._now = c0[3]
	motion._gc_t = c0[4]
	_sw_force = 1
	_refresh(rc_on, rc_on or rs_on)
	_sw_force = -1
	var b := _rc_capture()
	if (swv_frames + swv_skip) % 120 == 0:
		print("SWARMNAT71_VERIFY frames=%d diffs=%d skipped=%d native_units=%d last: used=%s units=%d calls=%d drawn=%d units_drawn=%d motion=%s why=%s" % [swv_frames, swv_diffs, swv_skip, swv_units, str(sw_used), sw_units, sw_calls, drawn, _units_drawn, str(motion_on), sw_why])
		print("SWARMNAT71_FB ", sw_fb, " FORGET ", sw_fg)
	if not sw_used:
		swv_skip += 1
		return
	swv_frames += 1
	swv_units += sw_units
	var bad: Array = []
	for k in a:
		if typeof(a[k]) == TYPE_ARRAY:
			var x: Array = a[k]
			var y: Array = b[k]
			if x.size() != y.size():
				bad.append("%s size %d/%d" % [k, x.size(), y.size()])
			else:
				for q in x.size():
					if not is_same(x[q], y[q]):
						bad.append("%s[%d]" % [k, q])
						break
		elif a[k] != b[k]:
			var s := "%s" % k
			if a[k] is PackedInt64Array or a[k] is PackedInt32Array or a[k] is PackedVector2Array or a[k] is PackedColorArray:
				var m: int = mini(a[k].size(), b[k].size())
				var j := 0
				while j < m and a[k][j] == b[k][j]:
					j += 1
				s += " at %d/%d: %s / %s" % [j, a[k].size(), str(a[k][j]) if j < a[k].size() else "-", str(b[k][j]) if j < b[k].size() else "-"]
			else:
				s += ": %s / %s" % [str(a[k]), str(b[k])]
			bad.append(s)
	if va.size() != motion.vs.size():
		bad.append("vs size %d/%d" % [va.size(), motion.vs.size()])
	else:
		for q in va:
			if not motion.vs.has(q) or va[q] != motion.vs[q]:
				bad.append("vs[%d] %s / %s" % [q, str(va[q]), str(motion.vs.get(q))])
				break
	if da.size() != drawn7.size():
		bad.append("drawn7 size %d/%d" % [da.size(), drawn7.size()])
	else:
		for q in da:
			if not drawn7.has(q) or da[q] != drawn7[q]:
				bad.append("drawn7[%d] %s / %s" % [q, str(da[q]), str(drawn7.get(q))])
				break
	if not bad.is_empty():
		swv_diffs += 1
		if swv_log < 12:
			swv_log += 1
			print("SWARMNAT71_DIFF frame=%d tick=%d units=%d %s" % [swv_frames, int(mv.snap.get("tick", -1)), sw_units, "; ".join(bad.slice(0, 6))])


## SWARMNAT71-3 diag (SWARMNAT71_VERIFY only): why the GDScript loop drew a unit the kernel handed back.
var sw_fb := {}
var sw_fg := {}
func _sw_fb_note(i: int, ids: PackedInt32Array, flg_a: PackedInt32Array, pframe: int, live: bool) -> void:
	var id := ids[i]
	var fl := flg_a[i]
	var k := "other"
	if fl & (4 | 16 | 128 | (1 << 18) | (1 << 20) | (1 << 21) | (1 << 23) | (1 << 27)):
		k = "flag:%x" % (fl & (4 | 16 | 128 | (1 << 18) | (1 << 20) | (1 << 21) | (1 << 23) | (1 << 27)))
	elif fl & 64:
		k = "g6"
	elif not _sw_reg.has(id):
		var sdx: int = (mv.snap.def as PackedInt32Array)[i] if mv != null and mv.snap.has("def") else -1
		var dnm: String = String(_dfl_names[sdx]) if sdx >= 0 and sdx < _dfl_names.size() else "?"
		var sns: Dictionary = mv.snap if mv != null else {}
		var ce = art._ec.get(id)   # SWARMNAT71-5 diag: why the GDScript draw never reached the reg
		k = "noreg:" + ("x7" if x7.has(id) else "") + ("g" if (sns.get("g7u", {}) as Dictionary).has(id) else "") \
			+ ("s" if (sns.get("squad", {}) as Dictionary).has(id) else "") + ("a" if (sns.get("air", {}) as Dictionary).has(id) else "") \
			+ ("P" if ce != null and int(ce[2]) == -2 else "") + ("N" if ce == null else "") + ":" + dnm
	elif not _sw.has_rec(id):
		k = "forgot"
	elif live and (pframe + id) % 8 == 0:
		k = "post8"
	sw_fb[k] = int(sw_fb.get(k, 0)) + 1
