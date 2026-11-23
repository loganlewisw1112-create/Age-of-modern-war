extends Node2D
## G7 ATMO7 (13.9c-7): facility atmosphere, wear, signage and damage, plus the display-only time of day. Display only:
## it never writes the sim (state hash identical with it on / off: tests/test_atmo7.gd). The facility is read through
## CnFacility.render_entries (a throttled read, never while a sim step is in flight), the render snapshot (statics hp)
## and events (CnLockdown, CnFacilityLost); never mv.world per frame.
##  1. Alarm (lockdown / breached ONLY, owner 13.9c-17; amber when contested, under fire or on a launch_alert): red rotating beacons on
##     every tower and gate, flashing wall lamps chasing round the ring, tower searchlights sweeping the approaches,
##     blast-door shutters sliding down over the visible garage / building doors, blast shields rising round the
##     helipad, the decon zone flooding with counter-nanite mist.
##  2. Time of day (Settings "Time of day": day / dusk / night; default day, Last Protocol dusk): a multiply tint over
##     the world under the fx, then additive lights above it: tower floodlight pools, lamp pools, door lamps, light
##     spilling from garage doors (LIFE7 door_open when present), pad edge lights blinking, base building lights.
##  3. Generator exhaust, roof / ground vent steam, drifting decon mist, a windsock and flags moving with the wind.
##  4. Ground wear: tyre tracks and wet asphalt after the APC wash, oil stains on pads / bays, hazard stripes round the
##     wash and pads, garage bay numbers and the unit crest on the aprons.
##  5. Signage: building name boards, gate numbers, STOP / SLOW stencils, lane arrows, warning boards.
##  6. Damage: cracks / smoke / fire on towers, walls, checkpoint and core by their snapshot hp, the zone buildings by
##     the core's hp, rubble where a part was destroyed, the whole compound a smouldering ruin after CnFacilityLost.
## Wiring (ORCH change_request): add after baseprops_layer, z_index 0, setup(self); refresh(snap) every frame next to
## baseprops_layer.refresh; on_events(evs) in _on_step_events. Unwired (auto = true) it pulls mv.snap itself.
## A match without a facility at day draws nothing and costs one cheap call per frame.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const ArtCat = preload("res://presentation/art/art_catalog.gd")
const Engineer7 = preload("res://sim/systems/engineer7.gd")   # POLISH7-4: BOWSER_BAY (13.9c-21), a static rect (no sim reads)
const SettingsMenu = preload("res://presentation/menu/settings.gd")
const EntityLayer = preload("res://presentation/view/entity_layer.gd")   # LIGHT7-3: door_side_of (which way a zone building is drawn)

const ART_DIR := "res://assets/art/g7_atmo7/"
const TODS := ["day", "dusk", "night"]
const TOD_AMT := {"day": 0.0, "dusk": 0.5, "night": 1.0}
const DUSK := Color(0.86, 0.70, 0.64)
const NIGHT := Color(0.27, 0.31, 0.50)
## Heights in screen px at zoom 1 above the ground point (calibrated on the ART7F sprites, see pt7_atmo7 shots).
const WALL_Z := 46.0   # LIGHT7-2: battlement panel top 4.66 m = 46 px (WALL7-2 fact wall7.heights, seq 5356)
const TOWER_Z := 110.0   # ATMO7-2: FACB7-2 tower cupola top 11.44 m x 9.8 px/m (was 132: beacons floated ~22 px above)
## POLISH7-2 (13.9c-14, owner: "fix the floating RED LIGHT warning lights ... not hovering at all"): every alarm light
## stands on a real fixture at FACB7's own heights (tools/art/g7_fac7f.gd + fact facb7.zone_heights, 9.8 px per m).
const PX_M := 9.8
const TOWER_ROOF_Z := 10.84 * PX_M   # tower roof slab top (tower_piece: slab z 10.72 + 0.12, half width 2.15 m)
const BEACON_OFF := Vector2(0.475, -0.475)   # on that slab's right (+x, -y, screen-right) corner, clear of the cupola ring
const SEARCH_OFF := Vector2(0.44, 0.36)   # the tower searchlight head (1.75, 1.45, 11.05) m
const SEARCH_Z := 11.05 * PX_M
const MAST_OFF := Vector2(-0.3, -0.3)   # tower obstruction-lamp mast foot on the roof (tiles from the tower centre)
const MAST_TOP_Z := 12.78 * PX_M         # its tip (WALL7-2 art: lamp pixel at 12.78 m): LIFE7's red obstruction lamp sits exactly here
# WALL7-2 rebuilt the wall (fact wall7.heights seq 5356): a 2.9 m rampart with a wall-walk deck at 3.66 m, an armoured parapet on
# the OUTER face (battlement panels 4.66 m = 46 px, 1.2 m panels on the 1.6 m grid, so one is centred on every 8 m section),
# a two-rail guard rail on the INNER edge (4.68 m, posts at 0.8 m + 1.6 m k), walkway lamps under the inner deck edge at
# 3.17 m (art, +-2 m from the section centre, inner face 1.55 m from the axis), a floodlight mast on the outer corner of
# every corner / T junction (head 5.44 m, 1.08 m from the junction centre on both axes).
const WALL_CAP_Z := 46.0                 # battlement panel top: the outer wall floods and alarm strobes stand on it
const RAIL_Z := 4.68 * PX_M              # inner guard-rail top: the apron floods (pad inside the wall) stand on a post
const WALK_LAMP_Z := 3.17 * PX_M         # the art's inner walkway lamps
const CORNER_MAST_Z := 5.41 * PX_M       # junction mast floodlight lens (head 5.44 m)
const PANEL_OFF := 1.25 / 4.0            # outer parapet panel centre from the wall axis (tiles)
const RAIL_OFF := 1.37 / 4.0             # inner guard rail from the wall axis (tiles)
const WALK_OFF := 1.552 / 4.0            # inner face (walkway lamp plate) from the wall axis (tiles)
const GATE_CAP_Z := 5.85 * PX_M      # gate bastion cap top (gate_layer: 5.7 + 0.15), bastion centre ey - 1.3 m across
const CP_PARAPET_Z := 5.6 * PX_M     # checkpoint roof parapet top (gatehouse: 5.42 + 0.18)
const CP_BEACON := Vector2(0.9625, -0.5)   # on the checkpoint's east parapet, (3.85, -2.0) m from its centre
const LAMP_HOUSING := Color(0.16, 0.16, 0.17)
const MAST_COL := Color(0.22, 0.22, 0.24)
const DOOR_Z := 30.0
const BLD_Z := {"planning": 152.0, "lab": 60.0, "workshop": 114.0, "decon_hall": 50.0, "core": 70.0,
	"magazine": 38.0, "armory": 114.0, "aid_station": 46.0, "ready_room": 71.0, "barracks": 114.0}   # ATMO7-2: FACB7-2 facb7.zone_heights x 9.8 px/m
## POLISH7-4: FACB7-5 seq 4783 (13.9c-18): workshop [16,9,4,4] + its drone-bay 2nd storey = one building, deck rail
## 11.6 m (114 px; the drone_bay zone is stacked on it: no height / plaque / box of its own, the art carries its DRONE
## BAY signs); barracks moved to [16,14,4,2] (same key, helideck 11.6 m).
## POLISH7-3: FACB7-4 seq 4583: planning = 4-storey command centre (roof brim 15.5 m), barracks = 3 storeys + roof pad
## (helideck 11.6 m); the range zone's 2-storey training building (zone offset, parapet 8.9 m) occludes lights too.
const RANGE_BLD := Rect2(0.1, 0.25, 3.6, 3.55)
const RANGE_BLD_Z := 87.0
const PART_FOOT := {"cn_tower": 2, "cn_blast_wall": 2, "cn_checkpoint": 2, "a_cn_facility": 4}
const PART_Z := {"cn_tower": 100.0, "cn_blast_wall": 40.0, "cn_checkpoint": 51.0, "a_cn_facility": 70.0}
const FIRE_COL := Color(1.0, 0.55, 0.18)
const MIST_COL := Color(0.78, 0.96, 0.92)

var mv = null
var map: Dictionary = {}
var hm: Dictionary = {}
var off := OS.get_environment("ATMO7_OFF") == "1"
var auto := false                 # true: _process pulls mv.snap / snap.events itself (no match_view wiring yet)
var t := 0.0                      # display clock (s)
var night := 0.0                  # eased 0..1 (0 day, 0.5 dusk, 1 night)
var wind := Vector2(1, 0)         # world-space wind direction (display only, from the map)
var facs: Array = []              # last CnFacility.render_entries
var geo: Array = []               # per facility: derived drawing geometry (see _geom)
var counts: Dictionary = {}       # last frame's draw counters (tests / playtest probes)
var on_screen := false            # some facility (or ruin) is in view this frame

var props: Node2D                 # z 2, under the entities: windsock, flags, back blast shields
var over: Node2D                  # z 3, over the entities: smoke, steam, mist, fire, cracks, beacons, shutters
var dark: Node2D                  # z 3, multiply: the time-of-day tint
var win: Node2D                   # z 3, after the tint, opaque: lit window panes (LIGHT7-3)
var glow: Node2D                  # z 3, additive: every light
var glow_s: Node2D                # LIGHT7-5: z 3, additive: every steady light (redrawn only when _static_sig changes); glow keeps the alarm lights
var fixo: Node2D                  # LIGHT7-5: z 3, the steady fixtures (after `over`, under the night tint)
var winf: Node2D                  # LIGHT7-5: z 3, the flickering screen rooms (10 Hz); win keeps every steady pane
var _gc: CanvasItem = null        # the glow canvas being drawn (glow / glow_s)
var _wc: CanvasItem = null        # the pane canvas being drawn (win / winf)
var _ls := 0                      # lights drawn by the last steady redraw
var _wdyn := false
var _lsig := -1
var _spill: Dictionary = {}       # LIGHT7-5: garage spill polygons cut by the silhouettes, per facility / garage / door step
var _gsig := -1
var _wsig := -1
var _spr: Dictionary = {}         # sprite id -> {tex, pivot, fw, fh, frames}
var _fac_key := ""
var _frame := 0
var _fac_frame := -999
var _tod_override := ""
var _night_drawn := -1.0
var _alarm: Dictionary = {}       # fid -> {lvl, red, t_on, lock_t, lock}
var _alert: Dictionary = {}       # fid -> display time a launch alert ends
var _ruins: Array = []            # [{g (geometry), t0}]
var _parts: Dictionary = {}       # static id -> [def, cell Vector2, size, fid]
var _gone: Array = []             # [{cell, size, def, t0}]
var _dmg: Array = []              # [{p (ground screen), z, size, h, def, seed}]
var _zone_dmg: Dictionary = {}    # fid -> core hp 0..1
var _stat_tick := -1
var _blds: Array = []             # base building lights: [tile pos, size]
var _blds_n := -1
var _ev_tick := -1
var _wired_ev := false
var _snap: Dictionary = {}
var _vr := Rect2()


func setup(view) -> void:
	mv = view
	var ww = view.get("_world") if view != null else null  # never view.world: forces a sim join
	map = ww.map if ww != null else {}
	hm = ViewUtil.height_map_of(map) if not map.is_empty() else {}
	var hs := absi(hash(Vector3i(int(map.get("w", 64)), int(map.get("h", 64)), int(map.get("seed", 7)))))
	wind = Vector2.RIGHT.rotated(float(hs % 6283) / 1000.0)
	_load_art()
	props = _child("Atmo7Props", 2, -1)
	over = _child("Atmo7Over", 3, -1)
	fixo = _child("Atmo7Fix", 3, -1)   # LIGHT7-5: the steady fixtures (under the night tint, like `over`)
	dark = _child("Atmo7Dark", 3, -1)
	var dsh := Shader.new()   # the night tint (multiply) with the outward floods lifting it back toward white on the ground outside
	dsh.code = DARK_SHADER
	var dmat := ShaderMaterial.new()
	dmat.shader = dsh
	dark.material = dmat
	win = _child("Atmo7Win", 3, -1)   # LIGHT7-3: after the multiply tint (self-lit) and before the additive glow
	win.visible = false
	winf = _child("Atmo7WinF", 3, -1)   # LIGHT7-5: the flickering screens only
	winf.visible = false
	glow = _child("Atmo7Glow", 3, CanvasItemMaterial.BLEND_MODE_ADD)
	glow_s = _child("Atmo7GlowS", 3, CanvasItemMaterial.BLEND_MODE_ADD)   # LIGHT7-5: every steady light
	_gc = glow
	_wc = win
	props.draw.connect(func(): _timed("props", _draw_props))
	over.draw.connect(func(): _timed("over", _draw_over))
	dark.draw.connect(_draw_dark)
	glow.draw.connect(func(): _timed("glow", _draw_glow))
	win.draw.connect(func(): _timed("win", _draw_windows))
	winf.draw.connect(func(): _timed("winf", _draw_winf))
	glow_s.draw.connect(func(): _timed("glow_s", _draw_glow_s))
	fixo.draw.connect(func(): _timed("fixo", _draw_fixo))
	set_process(auto)
	visible = not off


## The night / dusk tint (multiply). 13.9c-24b: an outward flood does not just add white (that washes the ground and the units
## standing on it to the same grey): it lifts the tint back toward white inside its pool, so a unit out there shows its own
## colours against the lit ground. Ground outside the walled compound only (hex = the compound's footprint extruded to the wall /
## roof height: nothing inside it is lifted, so no light ever lands on a roof or a wall face). Lights (two vec4 each): a = (centre x,
## centre y, m00, m01), b = (m10, m11, strength already scaled by the night amount, 0), m = the inverse of the ellipse's two
## conjugate semi-diameters (the image of the ground ellipse): an elongated wash along the wall, or a plain circle.
## LIGHT7-5 (13.9c-24d): the compound interior is lifted the same way (ilights: yard floods, lane poles, apron floods, area masts), but
## only on GROUND the camera sees: the pixel's ground point must lie inside the walls (inner, tiles from org = the compound origin on
## screen) and no occluder prism (occ: tile rect + base / top rise) may cover the pixel, so roofs, facades, walls, towers, gantries and
## canopies are never lifted (13.9c-18). A pixel at screen rise z above ground point (x, y) maps back to (x - z/32, y - z/32).
const DARK_SHADER := """
shader_type canvas_item;
render_mode blend_mul;
uniform vec4 lights[128];
uniform int nl = 0;
uniform vec4 bay[12];
uniform int nb = 0;
uniform vec2 hex[6];
uniform float hsign = 1.0;
uniform sampler2D lmask : filter_linear, repeat_disable;
uniform vec4 mrect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float mn = 0.0;
varying vec2 wp;
void vertex() {
	wp = VERTEX;
}
void fragment() {
	float lift = 0.0;
	float bayl = 0.0;
	for (int i = 0; i < 64; i++) {
		if (i >= nl) {
			break;
		}
		vec4 a = lights[2 * i];
		vec4 b = lights[2 * i + 1];
		vec2 dp = wp - a.xy;
		vec2 st = vec2(a.z * dp.x + a.w * dp.y, b.x * dp.x + b.y * dp.y);
		float f = clamp(1.0 - length(st), 0.0, 1.0);
		lift += pow(f, 1.5) * b.z;
	}
	lift = min(lift, 0.66);
	if (lift > 0.0) {
		bool inside = true;
		for (int k = 0; k < 6; k++) {
			vec2 a = hex[k];
			vec2 b = hex[(k + 1) % 6];
			float c = (b.x - a.x) * (wp.y - a.y) - (b.y - a.y) * (wp.x - a.x);
			if (c * hsign < 0.0) {
				inside = false;
			}
		}
		if (inside) {
			lift = 0.0;
		}
	}
	float il = 0.0;
	if (mn > 0.0) {   // LIGHT7-6: the facility's static lift mask (g: outward floods, r: interior lift, both already cut): one lookup
		vec2 uv = (wp - mrect.xy) / mrect.zw;
		if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
			vec2 m = texture(lmask, uv).rg * mn;
			lift = min(lift + m.y, 0.66);
			il = m.x;
		}
	}
	lift = min(lift + min(il, 0.6), 0.66);
	for (int j = 0; j < 4; j++) {
		if (j >= nb) {
			break;
		}
		vec4 qa = bay[3 * j];
		vec4 qb = bay[3 * j + 1];
		vec4 qc = bay[3 * j + 2];
		float c0 = (qa.z - qa.x) * (wp.y - qa.y) - (qa.w - qa.y) * (wp.x - qa.x);
		float c1 = (qb.x - qa.z) * (wp.y - qa.w) - (qb.y - qa.w) * (wp.x - qa.z);
		float c2 = (qb.z - qb.x) * (wp.y - qb.y) - (qb.w - qb.y) * (wp.x - qb.x);
		float c3 = (qa.x - qb.z) * (wp.y - qb.w) - (qa.y - qb.w) * (wp.x - qb.z);
		if ((c0 >= 0.0 && c1 >= 0.0 && c2 >= 0.0 && c3 >= 0.0) || (c0 <= 0.0 && c1 <= 0.0 && c2 <= 0.0 && c3 <= 0.0)) {
			bayl = max(bayl, qc.x);
		}
	}
	vec3 lc = mix(COLOR.rgb, vec3(1.0), lift);
	COLOR = vec4(mix(lc, vec3(1.0, 0.95, 0.85), bayl), 1.0);
}
"""


## CPU cost of each redrawn canvas (smoothed us; playtest / profiling only, no effect on what is drawn).
var prof: Dictionary = {}
func _timed(nm: String, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	f.call()
	prof[nm] = float(prof.get(nm, 0.0)) * 0.9 + float(Time.get_ticks_usec() - t0) * 0.1
	prof["n_" + nm] = int(prof.get("n_" + nm, 0)) + 1   # LIGHT7-5: redraw count (profiling)


func _child(nm: String, z: int, blend: int) -> Node2D:
	var n := Node2D.new()
	n.name = nm
	n.z_index = z
	if blend >= 0:
		var m := CanvasItemMaterial.new()
		m.blend_mode = blend
		n.material = m
	add_child(n)
	return n


func _load_art() -> void:
	var p := ART_DIR + "manifest.json"
	if not FileAccess.file_exists(p):
		return
	var man = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (man is Dictionary):
		return
	var a: Dictionary = (man as Dictionary).get("atmo7", {})
	for k in a:
		var e: Dictionary = a[k]
		var tx := ArtCat._texture(ART_DIR + String(e.file))
		if tx == null:
			continue
		var fw := int(e.get("fw", e.get("w", 1)))
		var fh := int(e.get("fh", e.get("h", 1)))
		_spr[k] = {"tex": tx, "pivot": Vector2(float(e.pivot[0]), float(e.pivot[1])), "fw": fw, "fh": fh, "frames": int(e.get("frames", 1))}
	_build_atlas()


## G7 LPPERF7B: every atmo7 sprite in one runtime atlas (2 px transparent gutters; the project filters nearest, so a
## region samples exactly the texels of its own file), plus a white block for the plain rects. Sprites, pools, dots
## and the fixture shafts drawn one after another then share a texture and batch: each sprite file used to cost its
## own draw call wherever kinds alternated (~1400 draw calls a frame for the Last Protocol fixtures and steady lights).
var _atlas: ImageTexture = null
var _atlas_wr := Rect2()


func _build_atlas() -> void:
	var keys: Array = _spr.keys()
	keys.sort()
	var imgs := {}
	for k in keys:
		var im: Image = (_spr[k].tex as Texture2D).get_image()
		if im == null:
			return
		if im.is_compressed():
			return
		im = im.duplicate()
		im.convert(Image.FORMAT_RGBA8)
		imgs[k] = im
	keys.sort_custom(func(a, b): return (imgs[a] as Image).get_height() > (imgs[b] as Image).get_height() or ((imgs[a] as Image).get_height() == (imgs[b] as Image).get_height() and String(a) < String(b)))
	const AW := 1024
	const PAD := 2
	var x := PAD + 4 + PAD
	var y := PAD
	var row_h := 4
	var place := {}
	for k in keys:
		var im: Image = imgs[k]
		if x + im.get_width() + PAD > AW:
			x = PAD
			y += row_h + PAD
			row_h = 0
		place[k] = Vector2i(x, y)
		x += im.get_width() + PAD
		row_h = maxi(row_h, im.get_height())
	var ah := y + row_h + PAD
	if ah > 4096:
		return
	var at := Image.create(AW, ah, false, Image.FORMAT_RGBA8)
	at.fill(Color(0, 0, 0, 0))
	at.fill_rect(Rect2i(PAD, PAD, 4, 4), Color.WHITE)
	_atlas_wr = Rect2(PAD + 1, PAD + 1, 1, 1)   # the middle of the white block (nearest: any stretch samples that texel)
	for k in keys:
		var im: Image = imgs[k]
		at.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), place[k])
	_atlas = ImageTexture.create_from_image(at)
	for k in keys:
		_spr[k]["atex"] = _atlas
		_spr[k]["ofs"] = Vector2(place[k])
		_spr[k]["tsz"] = Vector2((imgs[k] as Image).get_size())


## G7 LPPERF7B: the light polygons of the two ADDITIVE layers (glow, glow_s) go out as one triangle array on the atlas
## (untextured ones sample its white texel) instead of one draw call each. Additive blending is order-free, so the
## sum is the same; triangles come from Geometry2D.triangulate_polygon, as draw_polygon's own. A polygon that does not
## triangulate, or whose uvs leave 0..1, is drawn directly as before.
var _gb_on := false
var _gb_pts := PackedVector2Array()
var _gb_cols := PackedColorArray()
var _gb_uvs := PackedVector2Array()
var _gb_idx := PackedInt32Array()


func _gpoly(pts: PackedVector2Array, cols: PackedColorArray, uvs := PackedVector2Array(), e = null) -> void:
	var tex: Texture2D = (e.tex if e is Dictionary else null)
	if not _gb_on or _atlas == null or (e is Dictionary and not e.has("atex")) or pts.size() < 3 or (cols.size() != 1 and cols.size() != pts.size()) 			or (tex != null and uvs.size() != pts.size()):
		_gc.draw_polygon(pts, cols, uvs, tex)
		return
	var asz := Vector2(_atlas.get_size())
	var nu := PackedVector2Array()
	nu.resize(pts.size())
	if tex != null:
		var ofs: Vector2 = e.ofs
		var tsz: Vector2 = e.tsz
		var top := Vector2(1.0, 1.0) - Vector2(0.01, 0.01) / tsz
		for i in uvs.size():
			var u: Vector2 = uvs[i]
			if u.x < 0.0 or u.y < 0.0 or u.x > 1.0 or u.y > 1.0:
				_gc.draw_polygon(pts, cols, uvs, tex)
				return
			nu[i] = (ofs + u.min(top) * tsz) / asz
	else:
		nu.fill((_atlas_wr.position + Vector2(0.5, 0.5)) / asz)
	var tri := Geometry2D.triangulate_polygon(pts)
	if tri.is_empty():
		_gc.draw_polygon(pts, cols, uvs, tex)
		return
	var base := _gb_pts.size()
	_gb_pts.append_array(pts)
	_gb_uvs.append_array(nu)
	if cols.size() == 1:
		for i in pts.size():
			_gb_cols.append(cols[0])
	else:
		_gb_cols.append_array(cols)
	for k in tri:
		_gb_idx.append(base + k)


func _gb_flush() -> void:
	_gb_on = false
	if not _gb_idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(_gc.get_canvas_item(), _gb_idx, _gb_pts, _gb_cols, _gb_uvs, PackedInt32Array(), PackedFloat32Array(), _atlas.get_rid())
	_gb_pts = PackedVector2Array()
	_gb_cols = PackedColorArray()
	_gb_uvs = PackedVector2Array()
	_gb_idx = PackedInt32Array()


## G7 LPPERF7C: the ground _draw (wear, marks, bay, signs, pad lights, scorch / rubble, ruins: ~600 draw calls) goes
## out as ONE ordered triangle array on the atlas. Order is kept (alpha blending): every primitive is appended in draw
## order; anything not expressible (a transformed block, a non-atlas sprite, a polygon that does not triangulate, a
## primitive line) flushes the batch and is drawn directly. Same geometry as the engine's own commands: colored
## polygons = Geometry2D.triangulate_polygon triangles on the white texel, width >= 0 lines = the engine's quad
## (from +- the half-width normal, to +- it), atlas sprites = their dst rect with src uvs. GROUND_BATCH off = as before.
static var GROUND_BATCH := true
var _tb_on := false
var _tb_want := false
var _tb_pts := PackedVector2Array()
var _tb_cols := PackedColorArray()
var _tb_uvs := PackedVector2Array()
var _tb_idx := PackedInt32Array()


func _tb_flush() -> void:
	if not _tb_idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _tb_idx, _tb_pts, _tb_cols, _tb_uvs, PackedInt32Array(), PackedFloat32Array(), _atlas.get_rid())
	_tb_pts = PackedVector2Array()
	_tb_cols = PackedColorArray()
	_tb_uvs = PackedVector2Array()
	_tb_idx = PackedInt32Array()


func _tb_white() -> Vector2:
	return (_atlas_wr.position + Vector2(0.5, 0.5)) / Vector2(_atlas.get_size())


func _bpoly(pts: PackedVector2Array, col: Color) -> void:
	if not _tb_on:
		draw_colored_polygon(pts, col)
		return
	var tri := Geometry2D.triangulate_polygon(pts)
	if tri.is_empty():
		_tb_flush()
		draw_colored_polygon(pts, col)
		return
	var base := _tb_pts.size()
	var wu := _tb_white()
	_tb_pts.append_array(pts)
	for i in pts.size():
		_tb_cols.append(col)
		_tb_uvs.append(wu)
	for k in tri:
		_tb_idx.append(base + k)


func _bline(a: Vector2, b: Vector2, col: Color, w := -1.0) -> void:
	if not _tb_on or w < 0.0:
		_tb_flush()
		draw_line(a, b, col, w)
		return
	var t := (a - b).orthogonal().normalized() * w * 0.5
	var base := _tb_pts.size()
	var wu := _tb_white()
	_tb_pts.append_array(PackedVector2Array([a + t, a - t, b - t, b + t]))
	for i in 4:
		_tb_cols.append(col)
		_tb_uvs.append(wu)
	_tb_idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


func _bquad(dst: Rect2, src: Rect2, col: Color) -> void:
	var asz := Vector2(_atlas.get_size())
	var base := _tb_pts.size()
	_tb_pts.append_array(PackedVector2Array([dst.position, Vector2(dst.end.x, dst.position.y), dst.end, Vector2(dst.position.x, dst.end.y)]))
	_tb_uvs.append_array(PackedVector2Array([src.position / asz, Vector2(src.end.x, src.position.y) / asz, src.end / asz, Vector2(src.position.x, src.end.y) / asz]))
	for i in 4:
		_tb_cols.append(col)
	_tb_idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


## A plain rect through the atlas white texel when the atlas exists (same colour: white x modulate), else draw_rect.
func _wrect(o: CanvasItem, r: Rect2, col: Color) -> void:
	if _atlas != null:
		o.draw_texture_rect_region(_atlas, r, _atlas_wr, col)
	else:
		o.draw_rect(r, col)


# =============================================================== public API
## Settings "Time of day" (graphics / time_of_day): day | dusk | night. Unset: day, Last Protocol dusk.
func time_of_day() -> String:
	if _tod_override != "":
		return _tod_override
	var v = null
	if (SettingsMenu.DEFAULTS.graphics as Dictionary).has("time_of_day") or SettingsMenu._c().has_section_key("graphics", "time_of_day"):
		v = SettingsMenu.get_value("graphics", "time_of_day")
	if v != null and TODS.has(String(v)):
		return String(v)
	return "dusk" if map.has("lp") else "day"


func set_time_of_day(s: String) -> void:
	_tod_override = s if TODS.has(s) else ""


func night_amount() -> float:
	return night


## 0 none, 0.5 amber (contested / under fire / launch alert), 1 red (lockdown / breached only: owner 13.9c-17).
func alarm_level(fac_id: int) -> float:
	var a: Dictionary = _alarm.get(fac_id, {})
	return float(a.get("lvl", 0.0))


## SEQ7: amber beacons on fac_id for secs (a launch). Display only.
func launch_alert(fac_id: int, secs: float) -> void:
	_alert[fac_id] = maxf(float(_alert.get(fac_id, 0.0)), t + secs)


# =============================================================== frame
func _process(dt: float) -> void:
	if auto and mv != null:
		var sn = mv.get("snap")
		if sn is Dictionary:
			if not _wired_ev and int((sn as Dictionary).get("tick", -1)) != _ev_tick:
				_ev_tick = int(sn.get("tick", -1))
				on_events(sn.get("events", []), true)
			refresh(sn)


func on_events(evs: Array, from_snap := false) -> void:
	if not from_snap:
		_wired_ev = true
	for ev in evs:
		var ty := String(ev.get("type", ""))
		if ty == "CnLockdown":
			var fid := int(ev.get("fac", -1))
			var a: Dictionary = _alarm.get(fid, {})
			a["lock"] = bool(ev.get("on", false))
			a["ev_t"] = t
			_alarm[fid] = a
			_fac_frame = -999   # re-read the entries next frame
		elif ty == "CnFacilityLost":
			_lose(int(ev.get("id", -1)))
		elif ty == "CnFacilityRaised":
			_fac_frame = -999


func refresh(snap: Dictionary) -> void:
	if mv == null or off:
		return
	var t0 := Time.get_ticks_usec()
	_refresh(snap)
	prof["refresh"] = float(prof.get("refresh", 0.0)) * 0.9 + float(Time.get_ticks_usec() - t0) * 0.1


func _refresh(snap: Dictionary) -> void:
	var dt := clampf(get_process_delta_time(), 0.0, 0.1) if is_inside_tree() else 1.0 / 60.0
	t += dt
	_frame += 1
	_snap = snap
	# facility entries: re-read every 15 frames (a facility changes slowly), never while a sim step is in flight
	if _frame - _fac_frame >= 15 and not (mv.has_method("sim_busy") and mv.sim_busy()):
		_fac_frame = _frame
		var w = mv.get("_world")
		var fe: Array = CnFacility.render_entries(w) if w != null and CnFacility.active(w) else []
		var key := str(fe.size())
		for F in fe:
			key += "|%d,%s,%s,%d,%s" % [int(F.id), str(F.lock), str(F.state), int(F.heli), str(F.compound)]
		if key != _fac_key:
			_fac_key = key
			for F0 in facs:   # a facility that vanished without its event (loaded mid-way, events unwired): ruin it
				var still := false
				for F1 in fe:
					still = still or int(F1.id) == int(F0.id)
				if not still:
					_lose(int(F0.id))
			facs = fe
			_rebuild()
	_alarms()
	var st_tick := int(snap.get("tick", -1))
	if (not geo.is_empty() or not _ruins.is_empty()) and st_tick != _stat_tick and (_frame % 6 == 0 or _stat_tick < 0):
		_stat_tick = st_tick
		_statics(snap.get("statics", {}))
	# time of day
	var target: float = TOD_AMT.get(time_of_day(), 0.0)
	night = move_toward(night, target, dt * 0.5)
	var vp := get_viewport()
	_vr = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect() if vp != null else Rect2()
	if night > 0.004 and int(snap.get("tick", 0)) % 30 == 0:
		_base_lights(snap.get("statics", {}))
	on_screen = false
	for g in geo:
		on_screen = on_screen or _vr.intersects(g.bbox)
	for r in _ruins:
		on_screen = on_screen or _vr.intersects(r.g.bbox)
	var nchg := absf(night - _night_drawn) > 0.01
	if nchg:
		_night_drawn = night
		dark.queue_redraw()
	dark.visible = night > 0.004
	win.visible = night > WIN_ON
	winf.visible = win.visible
	var ssig := _static_sig()   # LIGHT7-5: the steady canvases (lights, fixtures, panes) and the lift uniforms change only with this
	if night > 0.004 and ssig != _lsig:
		_lsig = ssig
		_update_lift()
	if ssig != _gsig:
		_gsig = ssig
		glow_s.queue_redraw()
		fixo.queue_redraw()
	var cuts_dirty := false
	if on_screen and night > WIN_ON and _frame % 3 == 0:   # LIGHT7-4: a unit standing in front of a facade cuts the panes behind its sprite
		cuts_dirty = _unit_cuts()
	if on_screen and night > WIN_ON and (cuts_dirty or ssig != _wsig):   # LIGHT7-5: steady panes on change only; the screens ~10 Hz
		_wsig = ssig
		win.queue_redraw()
	if on_screen and night > WIN_ON and _frame % 6 == 0:
		winf.queue_redraw()
	if on_screen:   # ATMO7-2: animated canvases at 30 Hz, staggered (props + over on even frames, glow on odd)
		if _frame % 2 == 0:
			props.queue_redraw()
			over.queue_redraw()
		else:
			glow.queue_redraw()
	elif nchg or (night > 0.004 and _frame % 30 == 0):
		glow.queue_redraw()
		over.queue_redraw()   # LIGHT7: the base lamp posts (static) follow the camera at 2 Hz


## LIGHT7-5: what the steady canvases depend on (night amount, the facilities in view and their alarm / lock state, the garage doors,
## the base lamps, the view to 256 px; the garage spill follows the doors on the 30 Hz canvas): they redraw only when this changes (the +5 ms LIGHT7-4 measured was mostly these at 30 / 10 Hz).
var _sigdbg := OS.get_environment("LIGHT7_SIGDBG") == "1"
var _sigl: Array = []
func _static_sig() -> int:
	var h := [int(night * 100.0), _blds_n, _fac_key, Vector2i((_vr.position / 256.0).floor()), Vector2i((_vr.size / 64.0).floor())]
	for g in geo:
		if not _vr.intersects(g.bbox):
			continue
		var a: Dictionary = _alarm.get(int(g.id), {})
		h.append([int(g.id), float(a.get("lvl", 0.0)), bool(a.get("red", false)), bool(g.F.lock), g.has("fix")])
	if _sigdbg:
		var parts := [h[0], h[1], h[2], h[3], h[4], h.slice(5)]
		for i in parts.size():
			if _sigl.size() == parts.size() and str(parts[i]) != str(_sigl[i]):
				print("LIGHT7_SIG part %d %s -> %s" % [i, str(_sigl[i]).left(80), str(parts[i]).left(80)])
		_sigl = parts
	return hash(h)


## Feed the dark shader this frame's outward floods (south / east faces, near the view): wash + hot core each.
func _update_lift() -> void:
	var sm = dark.material
	if not (sm is ShaderMaterial):
		return
	var arr := PackedVector4Array()
	var bays := PackedVector4Array()
	var hexg: Dictionary = {}
	var vr := _vr.grow(380.0)
	for g in geo:
		if not g.has("fix") or not _vr.intersects(g.bbox):
			continue
		if hexg.is_empty():
			hexg = g
			_mask_build(g)
		if g.has("bay") and not bool(g.F.lock) and bays.size() < 12:   # LIGHT7-4: the Suit Foundry's open bay: its inside is lit, the night tint lifted in the opening
			var op: PackedVector2Array = g.bay.open
			bays.append(Vector4(op[0].x, op[0].y, op[1].x, op[1].y))
			bays.append(Vector4(op[2].x, op[2].y, op[3].x, op[3].y))
			bays.append(Vector4(BAY_LIFT * night, 0.0, 0.0, 0.0))
		if is_same(g, hexg) and _mask_ok(g):   # LIGHT7-6: its floods and the interior lift are baked into the static mask
			continue
		for F in g.fix:
			if not F.has("core") or not bool(F.lift) or arr.size() > 120:
				continue
			var c: Vector2 = _iso(F.pool)
			if not vr.has_point(c):
				continue
			_lift_ellipse(arr, c, F.wp, F.wq, 0.34 * night)
			_lift_ellipse(arr, _iso(F.core), F.cp, F.cq, 0.30 * night)
	var n := arr.size() / 2
	while arr.size() < 128:
		arr.append(Vector4.ZERO)
	sm.set_shader_parameter("nl", n)
	sm.set_shader_parameter("lights", arr)
	var nb := bays.size() / 3
	while bays.size() < 12:
		bays.append(Vector4.ZERO)
	sm.set_shader_parameter("nb", nb)
	sm.set_shader_parameter("bay", bays)
	var mk: Dictionary = _mask.get(int(hexg.get("id", -1)), {}) if not hexg.is_empty() else {}
	if not hexg.is_empty():
		sm.set_shader_parameter("hex", hexg.hex)
		sm.set_shader_parameter("hsign", float(hexg.hsign))
	if not mk.is_empty() and _mask_ok(hexg):
		var mr: Rect2 = mk.rect
		if not is_same(_mask_bound, mk.vp):
			sm.set_shader_parameter("lmask", (mk.vp as SubViewport).get_texture())
			_mask_bound = mk.vp
		sm.set_shader_parameter("mrect", Vector4(mr.position.x, mr.position.y, mr.size.x, mr.size.y))
		sm.set_shader_parameter("mn", MASK_K * night)
	else:
		sm.set_shader_parameter("mn", 0.0)


## LIGHT7-6: the facility's tint-lift mask, baked once per lighting plan (rebuilt only when the facility layout or its light set changes,
## g.msig) into a world-space SubViewport the dark shader samples once per pixel: g = the outward floods' lift (cut inside the compound
## hex), r = the interior lift (yard floods, wall floods, lane poles, apron floods, masts), cut to the ground inside the walls and off
## every drawn block / wall / tower silhouette (g.lsil). Stored / MASK_K (8 bit); the shader scales by MASK_K x night.
const MASK_K := 2.0
const MASK_MAX := 4096.0
const ELL_SHADER := """
shader_type canvas_item;
render_mode blend_add;
void fragment() {
	float f = clamp(1.0 - length(UV * 2.0 - 1.0), 0.0, 1.0);
	COLOR = vec4(COLOR.rgb * f * sqrt(f), 1.0);
}
"""
var _mask: Dictionary = {}        # facility id -> {vp, rect, sig, nodes}
var _mask_bound = null
var _mask_builds := 0             # playtest / test evidence: how often a mask was (re)baked
var _white: Texture2D = null


var _nomask := OS.get_environment("LIGHT7_NOMASK") == "1"   # diagnosis only: the mask is baked but not applied
func _mask_ok(g: Dictionary) -> bool:
	if _nomask:
		return false
	var mk: Dictionary = _mask.get(int(g.get("id", -1)), {})
	return not mk.is_empty() and int(mk.sig) == int(g.get("msig", 0))


## The mask's ellipses: [[centre, P, Q, strength at full night, channel 0 r / 1 g]].
func _mask_ells(g: Dictionary) -> Array:
	var out := []
	for F in g.get("fix", []):
		for e in _ilv(F):
			out.append([e[0], e[1], e[2], float(e[3]), 0])
		if F.has("core") and bool(F.get("lift", false)):
			out.append([_iso(F.pool), F.wp, F.wq, 0.34, 1])
			out.append([_iso(F.core), F.cp, F.cq, 0.30, 1])
	return out


func _mask_build(g: Dictionary) -> void:
	if not g.has("fix") or not g.has("lsil"):
		return
	var fid := int(g.get("id", -1))
	var ells := _mask_ells(g)
	if not g.has("msig"):
		var h := [g.O, g.cs, (g.lsil as Array).size()]
		for e in ells:
			h.append([e[0], e[3], e[4]])
		g.msig = hash(h)
	var mk: Dictionary = _mask.get(fid, {})
	if not mk.is_empty() and int(mk.sig) == int(g.msig):
		return
	if not mk.is_empty():
		(mk.vp as Node).queue_free()
	var rect := _bb(g.hex)
	for e in ells:
		var P: Vector2 = e[1]
		var Q: Vector2 = e[2]
		var hx := sqrt(P.x * P.x + Q.x * Q.x)
		var hy := sqrt(P.y * P.y + Q.y * Q.y)
		rect = rect.merge(Rect2((e[0] as Vector2) - Vector2(hx, hy), Vector2(hx, hy) * 2.0))
	rect = Rect2(rect.position.floor() - Vector2(2, 2), rect.size.ceil() + Vector2(4, 4))
	var sc := minf(1.0, MASK_MAX / maxf(rect.size.x, rect.size.y))
	if _white == null:
		var im := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		im.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(im)
	var vp := SubViewport.new()
	vp.name = "LiftMask%d" % fid
	vp.size = Vector2i(ceili(rect.size.x * sc), ceili(rect.size.y * sc))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var esh := Shader.new()
	esh.code = ELL_SHADER
	var mul := CanvasItemMaterial.new()
	mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	var cs := float(g.cs)
	var O: Vector2 = g.O
	var a := O + Vector2(1.0 + WALL_HT, 1.0 + WALL_HT)
	var b := O + Vector2(cs - 1.0 - WALL_HT, cs - 1.0 - WALL_HT)
	var T := _iso(a)
	var Rr := _iso(Vector2(b.x, a.y))
	var B := _iso(b)
	var L := _iso(Vector2(a.x, b.y))
	var m0 := rect.position
	var m1 := rect.end
	var outside := [PackedVector2Array([m0, Vector2(m1.x, m0.y), Vector2(m1.x, Rr.y), Rr, T, L, Vector2(m0.x, L.y)]),
		PackedVector2Array([Vector2(m0.x, L.y), L, B, Rr, Vector2(m1.x, Rr.y), m1, Vector2(m0.x, m1.y)])]
	var steps := [[1, null, []], [2, mul, [g.hex]], [0, null, []], [2, mul, outside]]
	var k := 0
	for st in steps:
		var n := Node2D.new()
		n.position = -rect.position * sc
		n.scale = Vector2(sc, sc)
		if st[1] == null:
			var m := ShaderMaterial.new()
			m.shader = esh
			n.material = m
		else:
			n.material = st[1]
		vp.add_child(n)
		n.draw.connect(_mask_draw.bind(n, g, ells, int(st[0]), st[2], k))
		k += 1
	add_child(vp)
	_mask[fid] = {"vp": vp, "rect": rect, "sig": int(g.msig)}
	_mask_bound = null
	_mask_builds += 1


func _mask_draw(n: Node2D, g: Dictionary, ells: Array, ch: int, polys: Array, step: int) -> void:
	if ch < 2:   # additive ellipses into one channel (stored / MASK_K)
		for e in ells:
			if int(e[4]) != ch:
				continue
			var v := float(e[3]) / MASK_K
			n.draw_set_transform_matrix(Transform2D(e[1], e[2], e[0]))
			n.draw_texture_rect(_white, Rect2(-1, -1, 2, 2), false, Color(v, 0, 0) if ch == 0 else Color(0, v, 0))
		n.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	var keep := Color(1, 0, 1) if step == 1 else Color(0, 1, 1)   # multiply: step 1 clears g inside the hex, step 3 clears r
	for poly in polys:
		n.draw_colored_polygon(poly, keep)
	if step == 3:
		for q in g.lsil:
			n.draw_colored_polygon(q[0], keep)


## Append one elliptic lift light (two vec4) for the ground ellipse centre c, conjugate semi-diameters P, Q (screen px).
static func _lift_ellipse(arr: PackedVector4Array, c: Vector2, P: Vector2, Q: Vector2, strength: float) -> void:
	var det := P.x * Q.y - P.y * Q.x
	if absf(det) < 0.001:
		return
	arr.append(Vector4(c.x, c.y, Q.y / det, -Q.x / det))
	arr.append(Vector4(-P.y / det, P.x / det, strength, 0.0))


func _alarms() -> void:
	for g in geo:
		var fid := int(g.id)
		var a: Dictionary = _alarm.get(fid, {})
		var st := String(g.F.state)
		var lock := bool(a.get("lock", g.F.lock)) if t - float(a.get("ev_t", -99.0)) < 1.0 else bool(g.F.lock)
		var red := lock or st == "breached"   # POLISH7-2 (13.9c-17): full lockdown look only on lock / breach
		var amber := st == "contested" or st == "under_fire" or float(_alert.get(fid, 0.0)) > t
		var lvl := 1.0 if red else (0.5 if amber else 0.0)
		if lvl > 0.0 and float(a.get("lvl", 0.0)) <= 0.0:
			a["t_on"] = t
		if lock != bool(a.get("lock_on", false)):
			a["lock_on"] = lock
			a["lock_t"] = t
		a["lvl"] = lvl
		a["red"] = red
		_alarm[fid] = a


# =============================================================== geometry
## ATMO7-2: memoised (the ground-lift lookup was most of the per-frame draw cost; nearly every point drawn is static).
var _isoc: Dictionary = {}
func _iso(p: Vector2) -> Vector2:
	if hm.is_empty():
		return ViewUtil.iso(p)
	var c = _isoc.get(p)
	if c != null:
		return c
	var s := ViewUtil.iso(p)
	s.y -= ViewUtil.ground_lift(hm, p)
	if _isoc.size() >= 8192:
		_isoc.clear()
	_isoc[p] = s
	return s


func _rect(a) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3])) if a is Array and (a as Array).size() == 4 else Rect2()


func _rebuild() -> void:
	geo = []
	var C: Dictionary = CnFacility.conf()
	for F in facs:
		geo.append(_geom(F, C))
	queue_redraw()
	props.queue_redraw()
	over.queue_redraw()
	glow.queue_redraw()
	win.queue_redraw()
	_gsig = -1   # LIGHT7-5: the steady canvases and the lift redraw
	_spill.clear()
	_wsig = -1
	_lsig = -1


## Everything that stays put while the facility stands, in tile space.
func _geom(F: Dictionary, C: Dictionary) -> Dictionary:
	var cr := _rect(F.compound)
	var O := cr.position
	var cs := cr.size.x
	var Z: Dictionary = {}
	for zn in F.zones:
		Z[zn] = _rect(F.zones[zn])
	var ctr := cr.get_center()
	var g := {"id": int(F.id), "F": F, "O": O, "cs": cs, "ctr": ctr, "zones": Z, "owner": int(F.owner)}
	var top := _iso(Vector2(cr.position.x, cr.position.y))
	var bb := Rect2(top, Vector2.ZERO)
	for q in [Vector2(cr.end.x, cr.position.y), cr.end, Vector2(cr.position.x, cr.end.y)]:
		bb = bb.expand(_iso(q))
	g.bbox = bb.grow_individual(80, 200, 80, 60)
	# towers (2x2) and the wall ring lamps (every 2-tile wall section, gates excluded)
	var towers := []
	for tw in C.get("towers", []):
		towers.append(O + Vector2(float(tw[0]) + 1.0, float(tw[1]) + 1.0))
	g.towers = towers
	var lamps := []
	var icsz := int(cs)
	var reserved := [_rect(C.get("gate_outer", [0, 0, 0, 0]))]
	for tw in C.get("towers", []):
		reserved.append(Rect2(float(tw[0]), float(tw[1]), 2, 2))
	var cp: Array = C.get("checkpoint", [0, 0])
	reserved.append(Rect2(float(cp[0]), float(cp[1]), 2, 2))
	var ring := []
	for x in range(0, icsz, 2):
		ring.append(Vector2(x, 0))
	for y in range(2, icsz - 2, 2):
		ring.append(Vector2(icsz - 2, y))
	for x in range(icsz - 2, -1, -2):
		ring.append(Vector2(x, icsz - 2))
	for y in range(icsz - 4, 1, -2):
		ring.append(Vector2(0, y))
	for i in ring.size():
		var r := Rect2(ring[i], Vector2(2, 2))
		var clash := false
		for rs in reserved:
			clash = clash or r.grow(-0.1).intersects(rs)
		if not clash:
			var lq: Vector2 = r.get_center()
			var lout := Vector2(0, -1) if lq.y < 2.0 else (Vector2(0, 1) if lq.y > float(icsz) - 2.0 else (Vector2(-1, 0) if lq.x < 2.0 else Vector2(1, 0)))
			lamps.append([O + lq, i, lout])
	g.lamps = lamps
	g.checkpoint = O + Vector2(float(cp[0]) + 1.0, float(cp[1]) + 1.0)
	# garages: [rect, door face (+x 0 / -x 2), index]
	var gar := []
	var grs: Array = F.get("garage_rects", [])
	for i in grs.size():
		var r := _rect(grs[i])
		gar.append([r, 0 if r.get_center().x < ctr.x else 2, i])
	g.garages = gar
	# doors of the zone buildings on a visible face (+x / +y): [zone, face 0 / 1, centre along the face, face line]
	var doors := []
	var dc: Dictionary = C.get("doors", {})
	var fcs: Dictionary = F.get("faces", {})
	for zn in dc:
		if not Z.has(zn) and zn != "core":
			continue
		if zn in ["planning", "lab"] and Z.has(zn):   # POLISH7: shutters on FACB7's own door geometry
			var zf := int(fcs[zn]) if fcs.has(zn) else -1
			if zf < 0:   # no faces entry: the conf door's face (the side FACB7 draws the door on, like entity_layer)
				for d in dc[zn]:
					var dq := O + Vector2(float(d[0]), float(d[1]))
					if absf(dq.x - (Z[zn] as Rect2).end.x) < 0.01:
						zf = 0
					elif absf(dq.y - (Z[zn] as Rect2).end.y) < 0.01:
						zf = 1
			for fd in _facb7_doors(zn, Z[zn], zf):
				doors.append(fd)
			continue
		var zr: Rect2 = Z.get(zn, Rect2(O + Vector2(float(C.core_offset[0]), float(C.core_offset[1])), Vector2(4, 4)))
		for d in dc[zn]:
			var dp := O + Vector2(float(d[0]), float(d[1]))
			if absf(dp.x - zr.end.x) < 0.01:
				doors.append([zn, 0, dp.y + 0.5, zr.end.x])
			elif absf(dp.y - zr.end.y) < 0.01:
				doors.append([zn, 1, dp.x + 0.5, zr.end.y])
	g.doors = doors
	# smoke / steam emitters: [tile pos, z, kind]
	var em := []
	if Z.has("planning"):
		var r: Rect2 = Z.planning
		em.append([Vector2(r.end.x - 0.6, r.position.y + 0.7), 38.5, "exhaust"])   # TOC generator (ground unit by the vestibule: its old height, not the tower roof)
	if Z.has("workshop"):
		var r: Rect2 = Z.workshop
		# POLISH7-4: the roof is the drone launch deck now: the high bay vents through the stair-core penthouse
		# (FACB7-5: SE corner x 19.2..19.6, y 11.75..12.25, top 12.7 m = 124 px)
		em.append([Vector2(r.position.x + 3.4, r.position.y + 3.0), 128.0, "exhaust"])
	if Z.has("lab"):
		var r: Rect2 = Z.lab
		em.append([Vector2(r.position.x + 1.2, r.position.y + 0.8), BLD_Z.lab + 8.0, "steam"])
	if Z.has("decon_hall"):
		var r: Rect2 = Z.decon_hall
		em.append([Vector2(r.get_center().x, r.position.y + 0.8), BLD_Z.decon_hall + 2.0, "steam"])
	var vents := []
	for zn in ["decon_hall", "lab", "apc_wash"]:   # ground vent grates beside the wet buildings
		if Z.has(zn):
			var r: Rect2 = Z[zn]
			var vp := Vector2(r.end.x + 0.35, r.end.y - 0.5) if zn != "apc_wash" else Vector2(r.position.x - 0.35, r.get_center().y)
			vents.append(vp)
			em.append([vp, 2.0, "vent"])
	g.vents = vents
	for zn2 in ["magazine", "fuel_point", "fuel", "ready_room"]:   # FACB7's new buildings: backup generator exhaust
		if Z.has(zn2):
			var r: Rect2 = Z[zn2]
			em.append([Vector2(r.end.x - 0.5, r.position.y + 0.5), 34.0, "exhaust"])
			break
	g.emit = em
	# decon mist areas
	var mist := []
	for zn in ["apc_wash"]:   # LIGHT7 (13.9c-18): never over the roofed decon hall (it was a see-through bank on its roof)
		if Z.has(zn):
			mist.append(Z[zn])
	g.mist = mist
	g.flood = [Z.get("apc_wash", Rect2()), Z.get("staging", Rect2()), Z.get("gate_inner", Rect2())]
	# windsock and flags
	var hp: Rect2 = Z.get("helipad", Z.get("pad", Rect2(ctr, Vector2(1, 1))))
	g.windsock = Vector2(hp.end.x - 0.3, hp.position.y + 0.35)   # helipad's far corner: nothing stands in front of it
	var core := Rect2(O + Vector2(float(C.core_offset[0]), float(C.core_offset[1])), Vector2(4, 4))   # flags in front of the HQ
	g.core_r = core
	# POLISH7: two poles on the open lane in front of the HQ entrance (door cell core_offset + (1, 4) on the +y face),
	# 0.75 tile out, beside the walkway: clear of LIFE7's ops inset (east) and of the comms mast in the lane; drawn on
	# the over layer (_draw_flags) so the HQ canopy behind them never covers the poles.
	g.flags = [Vector2(core.position.x + 0.9, core.end.y + 0.75), Vector2(core.position.x + 1.45, core.end.y + 0.75)]
	# lights: [pos, kind]: flood pools in front of the towers, door lamps, pad edge lights
	var lt := []
	for tc in towers:
		var inn: Vector2 = (ctr - tc).normalized()
		lt.append([tc + inn * 2.6, "flood"])
	for d in doors:
		var dp := Vector2(float(d[3]) + 0.25, float(d[2])) if int(d[1]) == 0 else Vector2(float(d[2]), float(d[3]) + 0.25)
		lt.append([dp, "door"])
	var edge := []
	for zn in ["pad", "helipad"]:
		if not Z.has(zn):
			continue
		var r: Rect2 = Z[zn]
		var k := 0
		for x in range(0, int(r.size.x) + 1):
			edge.append([Vector2(r.position.x + x, r.position.y), zn, k]); k += 1
		for y in range(1, int(r.size.y) + 1):
			edge.append([Vector2(r.end.x, r.position.y + y), zn, k]); k += 1
		for x in range(int(r.size.x) - 1, -1, -1):
			edge.append([Vector2(r.position.x + x, r.end.y), zn, k]); k += 1
		for y in range(int(r.size.y) - 1, 0, -1):
			edge.append([Vector2(r.position.x, r.position.y + y), zn, k]); k += 1
	g.lights = lt
	g.edge = edge
	_plan_lights(g, C)   # LIGHT7 (13.9c-24 / 24a): fixtures, silhouettes, clipped ground pools
	return g


## Ruin a facility that is gone (its event, or it vanished from the entries).
func _lose(fid: int) -> void:
	for i in range(geo.size() - 1, -1, -1):
		if int(geo[i].id) == fid:
			_ruins.append({"g": geo[i], "t0": t})
			geo.remove_at(i)
	queue_redraw()


## Facility parts' hp from the snapshot statics (towers, walls, checkpoint, core); a part that disappears while its
## facility stands leaves rubble. Throttled (every 6 frames, new ticks only).
func _statics(stats: Dictionary) -> void:
	var seen := {}
	_dmg = []
	_zone_dmg = {}
	for id in stats:
		var s: Dictionary = stats[id]
		var def := String(s.get("def", ""))
		var sz: int = PART_FOOT.get(def, 0)
		if sz == 0:
			continue
		var cell := Vector2(s.get("cell", Vector2i.ZERO))
		var fid := -1
		for g in geo:
			if Rect2(g.O - Vector2(1, 1), Vector2(g.cs + 2.0, g.cs + 2.0)).has_point(cell):
				fid = int(g.id)
				if def == "a_cn_facility":
					_zone_dmg[fid] = float(s.get("hp", 1.0))
		if fid < 0:
			continue
		seen[int(id)] = true
		_parts[int(id)] = [def, cell, sz, fid]
		var h := float(s.get("hp", 1.0))
		if h < 0.72:
			_dmg.append({"c": cell + Vector2(sz, sz) * 0.5, "z": float(PART_Z.get(def, 40.0)), "size": sz, "h": h, "def": def, "seed": int(id)})
	var changed := false
	for pid in _parts.keys():
		if not seen.has(pid):
			var pr: Array = _parts[pid]
			var alive := false
			for g in geo:
				alive = alive or int(g.id) == int(pr[3])
			if alive:
				_gone.append({"cell": pr[1], "size": pr[2], "def": pr[0], "t0": t})
				changed = true
			_parts.erase(pid)
	if changed:
		queue_redraw()


func _base_lights(stats: Dictionary) -> void:
	if stats.size() == _blds_n:
		return
	_blds_n = stats.size()
	_blds = []
	_bfix = []
	for id in stats:
		var s: Dictionary = stats[id]
		if String(s.get("kind", "")) != "building" or not bool(s.get("built", true)) or PART_FOOT.has(String(s.get("def", ""))):
			continue
		var def := String(s.get("def", ""))
		if def.begins_with("cn_") or def.contains("wall") or def.contains("mine"):
			continue
		_blds.append([Vector2(s.get("cell", Vector2i.ZERO)), int(s.get("size", 1))])
		if _blds.size() >= 400:
			break
	_plan_base()   # LIGHT7: lamp posts / masts and their clipped pools


# =============================================================== sprites
func _sp(id: String, at: Vector2, frame := 0, row := 0, mod := Color.WHITE, sc := 1.0, node: CanvasItem = null) -> bool:
	var e: Dictionary = _spr.get(id, {})
	if e.is_empty():
		return false
	var fw := float(e.fw)
	var fh := float(e.fh)
	var src := Rect2(float(frame % maxi(1, int(e.frames))) * fw, float(row) * fh, fw, fh)
	var dst := Rect2(at - Vector2(e.pivot) * sc, Vector2(fw, fh) * sc)
	if e.has("atex"):
		src.position += e.ofs
		if _tb_on and (node == null or node == self):
			_bquad(dst, src, mod)
			return true
		(node if node != null else self).draw_texture_rect_region(e.atex, dst, src, mod)
		return true
	if _tb_on and (node == null or node == self):
		_tb_flush()
	(node if node != null else self).draw_texture_rect_region(e.tex, dst, src, mod)
	return true


func _quad(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([_iso(r.position), _iso(Vector2(r.end.x, r.position.y)), _iso(r.end), _iso(Vector2(r.position.x, r.end.y))])


func _cnt(k: String, n := 1) -> void:
	counts[k] = int(counts.get(k, 0)) + n


# =============================================================== ground (z 0, under everything; redrawn on change)
func _draw() -> void:
	_tb_want = GROUND_BATCH and _atlas != null
	_tb_on = _tb_want
	for k in ["tracks", "wet", "stripes", "oil", "stencils", "arrows", "signs", "vents", "rubble", "scorch", "bay"]:
		counts[k] = 0
	for g in geo:
		_draw_wear(g)
		_draw_marks(g)
		_draw_bowser_bay(g)
		_draw_signs(g)
		_draw_flush(g)   # LIGHT7: pad perimeter light housings
	for gn in _gone:
		var c: Vector2 = gn.cell + Vector2(gn.size, gn.size) * 0.5
		_sp("scorch", _iso(c), 0, 0, Color(1, 1, 1, 0.8), float(gn.size) * 0.5)
		_sp("rubble%d" % (absi(hash(gn.cell)) % 3), _iso(c) + Vector2(0, -8.0 * float(gn.size) * 0.5), 0, 0, Color.WHITE, float(gn.size) * 0.5)
		_cnt("rubble")
	for r in _ruins:
		_draw_ruin(r.g)
	_tb_flush()
	_tb_on = false


const TRACK := Color(0.06, 0.06, 0.06, 0.40)
const WET := Color(0.05, 0.07, 0.09, 0.42)
const SHEEN := Color(0.62, 0.72, 0.80, 0.55)
const HAZ_Y := Color(0.93, 0.74, 0.12, 0.92)
const HAZ_K := Color(0.08, 0.08, 0.08, 0.92)


func _line_t(a: Vector2, b: Vector2, c: Color, w := 1.0) -> void:
	_bline(_iso(a), _iso(b), c, w)


func _draw_wear(g: Dictionary) -> void:
	var Z: Dictionary = g.zones
	var go0: Rect2 = Z.get("gate_outer", Rect2())
	if go0.size.x > 0.0:   # the paved approach outside the gate, under the tyre tracks (ATMO7-2: was drawn over them)
		var go := go0
		var ap := Rect2(go.position.x, go.end.y, go.size.x, 3.2)
		_bpoly(_quad(ap), Color(0.21, 0.22, 0.23, 0.95))
		_line_t(Vector2(ap.position.x + 0.1, ap.position.y), Vector2(ap.position.x + 0.1, ap.end.y), Color(0.9, 0.9, 0.85, 0.7))
		_line_t(Vector2(ap.end.x - 0.1, ap.position.y), Vector2(ap.end.x - 0.1, ap.end.y), Color(0.9, 0.9, 0.85, 0.7))
	var wash: Rect2 = Z.get("apc_wash", Rect2())
	var gin: Rect2 = Z.get("gate_inner", Rect2())
	var gout: Rect2 = Z.get("gate_outer", Rect2())
	var stg: Rect2 = Z.get("staging", Rect2())
	if wash.size.x > 0.0:
		var x0 := wash.position.x
		var xw := wash.size.x
		# wet asphalt: the wash floor, the inner gate and a drying apron into the staging yard (fading strips)
		_bpoly(_quad(wash), WET)
		if gin.size.x > 0.0:
			_bpoly(_quad(gin), Color(WET, WET.a * 0.85))
		var y_top := gin.position.y if gin.size.x > 0.0 else wash.position.y
		for k in 5:
			var a := WET.a * (0.75 - 0.14 * float(k))
			_bpoly(_quad(Rect2(x0 + 0.3 + 0.1 * k, y_top - 0.6 * float(k + 1), xw - 0.6 - 0.2 * k, 0.6)), Color(WET, a))
		_cnt("wet", 7)
		for i in 18:   # sheen streaks on the wet floor
			var hs := absi(hash(Vector2i(int(g.id), i)))
			var p := Vector2(x0 + 0.3 + float(hs % 97) / 97.0 * (xw - 0.6), wash.position.y - 2.5 + float((hs / 97) % 89) / 89.0 * (wash.size.y + 4.0))
			_line_t(p, p + Vector2(0.0, 0.35), Color(SHEEN, SHEEN.a * (0.5 + 0.5 * float((hs / 9973) % 2))))
		# tyre tracks: two lanes (in / out) of paired wheel lines from outside the gate to the staging yard; wet and
		# dark through the wash, fading out on the yard
		var y_end := stg.position.y - 3.0 if stg.size.x > 0.0 else y_top - 5.0   # across the yard into the lane (the inner gate hides the first tiles)
		var y_mud := gout.position.y if gout.size.x > 0.0 else wash.end.y   # outside the outer gate: muddy, not yet washed
		var y_start := (gout.end.y + 1.5) if gout.size.x > 0.0 else wash.end.y + 1.0
		for lane in [-0.62, 0.62]:
			for wheel in [-0.27, 0.27]:
				var x: float = x0 + xw * 0.5 + lane + wheel
				var y := y_start
				var seg := 0
				while y > y_end:
					var y2 := maxf(y - 0.5, y_end)
					var dry := clampf((y_top - y2) / 7.0, 0.0, 1.0)
					var col := Color(TRACK, TRACK.a * (1.0 - dry * 0.7)) if y2 < y_top else Color(0.02, 0.03, 0.04, 0.62)
					if y2 >= y_mud:
						col = Color(0.40, 0.33, 0.23, 0.60)   # ATMO7-2: dark-on-dark was invisible on the apron
					var wob := sin(float(seg) * 0.9 + lane * 3.0) * 0.04
					_line_t(Vector2(x + wob, y), Vector2(x - wob, y2), col, 2.0)   # ATMO7-2: 2 px, read at zoom 1-2.5
					y = y2
					seg += 1
				_cnt("tracks")
		# hazard stripes round the wash bay
		_haz_rect(wash.grow(-0.08))
	for zn in ["pad", "helipad", "fuel_point"]:
		if Z.has(zn):
			_haz_rect(Z[zn].grow(0.22 if zn != "fuel_point" else -0.05), 0.16)
	# oil stains: pads, the staging bays, garage aprons (deterministic per facility)
	var spots := []
	for zn in ["pad", "helipad", "staging"]:
		if Z.has(zn):
			var r: Rect2 = Z[zn]
			for i in int(r.size.x * r.size.y / 5.0):
				var hs := absi(hash(Vector3i(int(g.id), i, zn.length())))
				spots.append(r.position + Vector2(0.5 + float(hs % 101) / 101.0 * (r.size.x - 1.0), 0.5 + float((hs / 101) % 103) / 103.0 * (r.size.y - 1.0)))
	for ga in g.garages:
		var r: Rect2 = ga[0]
		var ap := Vector2(r.end.x + 0.7, r.get_center().y) if int(ga[1]) == 0 else Vector2(r.position.x - 0.7, r.get_center().y)
		spots.append(ap + Vector2(0.15, -0.3))
	for i in spots.size():
		_sp("oil%d" % (i % 3), _iso(spots[i]), 0, 0, Color(1, 1, 1, 0.85), 1.0 + 0.3 * float(i % 2))
	_cnt("oil", spots.size())


## Yellow / black hazard stripes on a band just inside r's edge (diagonal blocks, 0.5 tile each).
func _haz_rect(r: Rect2, band := 0.2) -> void:
	var edges := [[r.position, Vector2(1, 0), r.size.x, Vector2(0, 1)], [Vector2(r.end.x, r.position.y), Vector2(0, 1), r.size.y, Vector2(-1, 0)],
		[r.end, Vector2(-1, 0), r.size.x, Vector2(0, -1)], [Vector2(r.position.x, r.end.y), Vector2(0, -1), r.size.y, Vector2(1, 0)]]
	for e in edges:
		var p0: Vector2 = e[0]
		var d: Vector2 = e[1]
		var n: Vector2 = e[3]
		var L := float(e[2])
		var k := 0
		var s := 0.0
		while s < L - 0.01:
			var s2 := minf(s + 0.35, L)
			var a := p0 + d * s
			var b := p0 + d * s2
			var col := HAZ_Y if k % 2 == 0 else HAZ_K
			_bpoly(PackedVector2Array([_iso(a), _iso(b), _iso(b + n * band + d * 0.12), _iso(a + n * band + d * 0.12)]), col)
			s = s2
			k += 1
		_cnt("stripes")


## POLISH7-4 (owner 13.9c-21): the fuel bowser's ONE marked parking bay (Engineer7.BOWSER_BAY; the sim bowser and the
## LIFE7 display truck always park there unless refuelling): a sealed slab with a yellow box, a white wheel-stop bar at
## the closed end, yellow hatching across the mouth (the lane side, where it drives out nose first), a fuel-drop stencil and a
## NO SMOKING board on its post at the closed end.
func _draw_bowser_bay(g: Dictionary) -> void:
	var b := Rect2(Vector2(g.O) + Engineer7.bay_local().position, Engineer7.bay_local().size)
	g["fuel_bay"] = b
	_bpoly(_quad(b.grow(0.08)), Color(0.20, 0.21, 0.21, 1.0))
	_bpoly(_quad(b), Color(0.27, 0.28, 0.27, 1.0))
	var y := Color(0.95, 0.76, 0.12, 1.0)
	var k := Color(0.07, 0.07, 0.07, 1.0)
	var q := [b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)]
	for i in 4:
		_line_t(q[i], q[(i + 1) % 4], k, 3.0)
		_line_t(q[i], q[(i + 1) % 4], y, 1.6)
	# POLISH7-5 (13.9c-21a): oriented by Engineer7.bay_heading() (the nose points at the mouth on the lane):
	# u = 0 at the closed end .. L at the mouth, v = 0..W across the bay
	var d := Vector2.from_angle(Engineer7.bay_heading()).round()
	var pn := Vector2(-d.y, d.x)
	var L := absf(d.x) * b.size.x + absf(d.y) * b.size.y
	var W := absf(pn.x) * b.size.x + absf(pn.y) * b.size.y
	var c0 := b.get_center() - d * L * 0.5
	var at := func(u: float, v: float) -> Vector2:
		return c0 + d * u + pn * (v - W * 0.5)
	# wheel stop: a white bar across the closed end
	_line_t(at.call(0.3, 0.15), at.call(0.3, W - 0.15), Color(0.94, 0.94, 0.90, 1.0), 2.5)
	# mouth hatching (diagonal yellow / black bands, inside the box)
	var n := 5
	for i in n:
		var v0 := W * float(i) / float(n)
		var v1 := W * (float(i) + 0.5) / float(n)
		_bpoly(PackedVector2Array([_iso(at.call(L - 0.05, v0)), _iso(at.call(L - 0.05, v1)),
			_iso(at.call(L - 0.45, minf(W, v1 + 0.12))), _iso(at.call(L - 0.45, minf(W, v0 + 0.12)))]), y if i % 2 == 0 else k)
	# fuel-drop stencil in the middle of the bay (red drop on a white disc)
	var c := _iso(b.get_center())
	_tb_flush()   # G7 LPPERF7C: transformed block drawn directly (the batch holds untransformed points)
	_tb_on = false
	draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 7.0, Color(0.93, 0.93, 0.89, 1.0))
	draw_circle(Vector2(0, 1.2), 3.4, Color(0.80, 0.12, 0.08, 1.0))
	_bpoly(PackedVector2Array([Vector2(0, -5.0), Vector2(2.9, -0.2), Vector2(-2.9, -0.2)]), Color(0.80, 0.12, 0.08, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_tb_on = _tb_want
	_sp("w_nosmoke", _iso(at.call(0.12, W * 0.5)))
	_cnt("bay")


func _draw_marks(g: Dictionary) -> void:
	var Z: Dictionary = g.zones
	# garage bay numbers + the unit crest on each apron, reading from the door outward
	for ga in g.garages:
		var r: Rect2 = ga[0]
		var i := int(ga[2])
		var ap := Vector2(r.end.x + 0.75, r.get_center().y) if int(ga[1]) == 0 else Vector2(r.position.x - 0.75, r.get_center().y)
		if _sp("st_n%02d" % (i + 1), _iso(ap + Vector2(0, 0.55)), 0, 0, Color(1, 1, 1, 0.9)):
			_cnt("stencils")
		_sp("crest", _iso(ap + Vector2(0, -0.6)), 0, 0, Color(1, 1, 1, 0.85), 0.75)
	# gates: STOP + gate number outside the outer gate, SLOW + G2 on the yard side of the inner gate, CP at the checkpoint
	var go: Rect2 = Z.get("gate_outer", Rect2())
	if go.size.x > 0.0:   # the paved approach outside the gate (gate width: the serpentine baffles start right of it)
		# ATMO7-2: no footpath / jersey barriers here any more: FACB7's fortified foot entry (13.9c-8) draws the
		# blast-walled serpentine (cn_ecp_baffle) on that ground.
		var c := Vector2(go.get_center().x, go.end.y)
		_sp("st_stop", _iso(c + Vector2(0, 0.9)))
		_sp("st_g1", _iso(c + Vector2(0, 1.9)))
		_line_t(Vector2(go.position.x + 0.2, go.end.y + 0.35), Vector2(go.end.x - 0.2, go.end.y + 0.35), Color(0.92, 0.92, 0.86, 0.85), 2.0)
		_cnt("stencils", 2)
	var gi: Rect2 = Z.get("gate_inner", Rect2())
	if gi.size.x > 0.0:
		var c := Vector2(gi.get_center().x, gi.position.y)
		_sp("st_g2", _iso(c + Vector2(0, -0.8)))
		_sp("st_slow", _iso(c + Vector2(0, -1.8)))
		_cnt("stencils", 2)
	_sp("st_cp", _iso(Vector2(g.checkpoint) + Vector2(0, -1.6)))
	# lane arrows: two-way roads, one arrow per lane every ~5 tiles (keep right)
	for l in (g.F.get("lanes", []) as Array):
		var r := _rect(l)
		var horiz := r.size.x >= r.size.y
		var L := maxf(r.size.x, r.size.y)
		var W := minf(r.size.x, r.size.y)
		if L < 5.0 or W < 2.0:
			continue
		var n := int(L / 5.0)
		for k in n:
			var s := (float(k) + 0.5) * L / float(n)
			for side in [-1, 1]:
				var p := r.position + (Vector2(s, r.size.y * 0.5 + float(side) * W * 0.25) if horiz else Vector2(r.size.x * 0.5 + float(side) * W * 0.25, s))
				var rot := (0 if side > 0 else 2) if horiz else (3 if side > 0 else 1)
				if _sp("arrow%d" % rot, _iso(p), 0, 0, Color(1, 1, 1, 0.8), 0.55):
					_cnt("arrows")
	for v in g.vents:
		_sp("vent", _iso(v))
		_cnt("vents")


## Free-standing boards on posts (drawn before the entities): gate / approach warnings outside the walls, the pad and
## helipad boards at their road-side corners. Building names hang on the facades as plaques (_draw_plaques, over).
func _draw_signs(g: Dictionary) -> void:
	var Z: Dictionary = g.zones
	var items := []
	var go: Rect2 = Z.get("gate_outer", Rect2())
	if go.size.x > 0.0:   # outside the walls: the approach warnings and the gate number
		items.append(["board_gate_outer", Vector2(go.position.x - 0.9, go.end.y + 0.6)])
		items.append(["w_nanite", Vector2(go.position.x - 1.1, go.end.y + 2.5)])
		items.append(["w_force", Vector2(go.position.x - 3.0, go.end.y + 1.4)])
		items.append(["w_speed", Vector2(go.position.x - 0.8, go.end.y + 4.6)])   # vehicles' side, clear of the serpentine
	# ATMO7-2: the foot entry's boards stand clear of FACB7's serpentine (baffles at y + 2 / + 3 from the gatehouse,
	# walk-in leg along the wall from the gate side): ID board east of the gatehouse, STOP SHOW ID at the leg's mouth.
	var cp: Vector2 = g.checkpoint
	items.append(["board_checkpoint", cp + Vector2(-3.0, 4.6)])   # before the walk-in leg's mouth, clear of the baffles
	# (the STOP SHOW ID board went: in the open it stood on the gate apron, and the ECP board says the same)
	if Z.has("pad"):
		var r: Rect2 = Z.pad
		items.append(["board_pad", Vector2(r.end.x - 0.9, r.end.y - 0.3)])   # on the pad's front corner band
		items.append(["w_jet", Vector2(r.position.x + 1.2, r.end.y - 0.3)])
	if Z.has("helipad"):
		var r: Rect2 = Z.helipad
		items.append(["board_helipad", Vector2(r.end.x - 0.9, r.end.y - 0.3)])
		items.append(["w_rotor", Vector2(r.position.x + 1.2, r.end.y - 0.3)])
	if Z.has("fuel_point"):   # FACB7 13.9c-6: hot refuel / rearm marking at the pads
		var r: Rect2 = Z.fuel_point
		items.append(["board_fuel_point", Vector2(r.position.x + 0.2, r.end.y + 0.3)])
		items.append(["w_nosmoke", Vector2(r.end.x - 0.3, r.end.y + 0.3)])
	items.sort_custom(func(a, b): return (a[1] as Vector2).x + (a[1] as Vector2).y < (b[1] as Vector2).x + (b[1] as Vector2).y)
	for it in items:
		if _sp(String(it[0]), _iso(it[1])):
			_cnt("signs")


## Plaque spots on the visible facades: [sprite id, face 0 (+x) / 1 (+y), face line, centre along the face, z].
## A zone's name plaque goes over its door when the door is on a visible face, else in the middle of the +y face;
## its hazard plaque (if any) beside it.
const PLAQUE_WARN := {"range": "w_livefire", "magazine": "w_explosive", "fuel_point": "w_nosmoke", "fuel": "w_nosmoke", "decon_hall": "w_suits", "armory": "w_suits"}
const OPEN_ZONES := ["pad", "helipad", "staging", "apc_wash", "gate_outer", "gate_inner", "fuel_point"]
const INSET := 0.42


func _plaques(g: Dictionary) -> Array:
	if g.has("plaques"):
		return g.plaques
	var out := []
	var Z: Dictionary = g.zones
	var dc: Dictionary = CnFacility.conf().get("doors", {})
	for zn in Z:
		if OPEN_ZONES.has(zn) or not _spr.has("board_" + zn) or not _has_art(zn) or _stacked(g, zn):
			continue   # POLISH7-4: a stacked upper storey (drone bay on the workshop) has its signs in the art
		if zn == "armory":
			continue   # LIGHT7-3 (board ask atmo7.foundry_plaque_off_bay): the Suit Foundry signs itself (lit SUIT FOUNDRY lettering, FACB7-7); the board hid its bay opening
		var zr: Rect2 = Z[zn]
		var face := 1
		var along := zr.get_center().x
		var z := 26.0
		for d in dc.get(zn, []):
			var dp: Vector2 = g.O + Vector2(float(d[0]), float(d[1]))
			if absf(dp.x - zr.end.x) < 0.01:
				face = 0
				along = dp.y + 0.5
				z = DOOR_Z * 0.8 + 9.0
				break
			if absf(dp.y - zr.end.y) < 0.01:
				face = 1
				along = dp.x + 0.5
				z = DOOR_Z * 0.8 + 9.0
				break
		var line := (zr.end.x if face == 0 else zr.end.y) - INSET
		var lo := (zr.position.y if face == 0 else zr.position.x) + INSET + 0.5
		var hi := (zr.end.y if face == 0 else zr.end.x) - INSET - 0.5
		along = clampf(along, lo, hi)
		var pat := Vector2(line, along) if face == 0 else Vector2(along, line)
		if _plaque_hidden(g, pat, z, float(_spr["board_" + zn].fw), float(_spr["board_" + zn].fh) - 8.0):
			continue   # POLISH7: a tower / the outer wall stands in front of this face (e.g. the magazine's south end)
		out.append(["board_" + zn, face, line, along, z])
		if PLAQUE_WARN.has(zn) and _spr.has(PLAQUE_WARN[zn]):   # beside the name plaque, never overlapping it
			var gap := (float(_spr["board_" + zn].fw) + float(_spr[PLAQUE_WARN[zn]].fw)) * 0.5 / 32.0 + 0.15
			var lo2 := (zr.position.y if face == 0 else zr.position.x) + INSET + float(_spr[PLAQUE_WARN[zn]].fw) / 64.0
			var hi2 := (zr.end.y if face == 0 else zr.end.x) - INSET - float(_spr[PLAQUE_WARN[zn]].fw) / 64.0
			if along + gap <= hi2:
				out.append([PLAQUE_WARN[zn], face, line, along + gap, z])
			elif along - gap >= lo2:
				out.append([PLAQUE_WARN[zn], face, line, along - gap, z])
	g["plaques"] = out
	return out


## POLISH7: true when a tower (2x2, TOWER_Z) or the compound's front (+x / +y) wall strip stands in front of the
## plaque at world point at (z px up, fw x fh px) and covers its middle or either end on screen: the plaques draw on
## the over layer (above the entities), so a covered one would hang over the tower / wall in front of it.
func _plaque_hidden(g: Dictionary, at: Vector2, z: float, fw: float, fh: float) -> bool:
	var s := _iso(at) - Vector2(0, z + fh * 0.5)
	var pts := [s, s + Vector2(-fw * 0.5, 0), s + Vector2(fw * 0.5, 0)]
	var O: Vector2 = g.O
	var cs := float(g.cs)
	var occ := [[Rect2(O + Vector2(cs - 2.0, 0), Vector2(2, cs)), WALL_Z], [Rect2(O + Vector2(0, cs - 2.0), Vector2(cs, 2)), WALL_Z]]
	for tc in g.towers:
		occ.append([Rect2((tc as Vector2) - Vector2(1, 1), Vector2(2, 2)), TOWER_Z])
	for o in occ:
		var r: Rect2 = o[0]
		if at.x >= r.end.x or at.y >= r.end.y or r.has_point(at):
			continue   # in front of it (or on it)
		var q := [_iso(r.position), _iso(Vector2(r.end.x, r.position.y)), _iso(r.end), _iso(Vector2(r.position.x, r.end.y))]
		var up := Vector2(0, -float(o[1]))
		var poly := PackedVector2Array([q[3], q[3] + up, q[0] + up, q[1] + up, q[1], q[2]])
		for pt in pts:
			if Geometry2D.is_point_in_polygon(pt, poly):
				return true
	return false


func _draw_plaques(g: Dictionary) -> void:
	for p in _plaques(g):
		var e: Dictionary = _spr.get(String(p[0]), {})
		if e.is_empty():
			continue
		var face := int(p[1])
		var at := Vector2(float(p[2]), float(p[3])) if face == 0 else Vector2(float(p[3]), float(p[2]))
		var o := _iso(at) - Vector2(0, float(p[4]))
		var fw := float(e.fw)
		var fh := float(e.fh) - 8.0   # the board without its posts
		over.draw_set_transform_matrix(Transform2D(Vector2(1.0, -0.5 if face == 0 else 0.5), Vector2(0, 1), o))
		if e.has("atex"):
			over.draw_texture_rect_region(e.atex, Rect2(-fw * 0.5, -fh, fw, fh), Rect2(e.ofs, Vector2(fw, fh)))
		else:
			over.draw_texture_rect_region(e.tex, Rect2(-fw * 0.5, -fh, fw, fh), Rect2(0, 0, fw, fh))
		_cnt("plaques")
	over.draw_set_transform_matrix(Transform2D.IDENTITY)


## POLISH7-4 (FACB7-5): zone zn is an upper storey stacked on another zone's building (json "stacked").
func _stacked(g: Dictionary, zn: String) -> bool:
	return (g.F.get("stacked", CnFacility.conf().get("stacked", {})) as Dictionary).has(zn)


## True when the zone's building is drawn (FACB7 art present), so plaques / window light never float over a bare slab.
const ZONE_ART := {"planning": "g7_fac_planning", "drone_bay": "g7_fac_dronebay", "workshop": "g7_fac_workshop", "range": "g7_fac_range",
	"lab": "g7_fac_lab", "decon_hall": "g7_fac_deconhall", "aid_station": "g7_fac_aid"}   # LIGHT7-5: the aid station's art is g7_fac_aid (it had no occluder)
func _has_art(zn: String) -> bool:
	if zn == "core":
		return true
	var b: Dictionary = ArtCat.manifest().get("buildings", {})
	return b.has(ZONE_ART.get(zn, "")) or b.has("g7_fac_" + zn) or b.has("g7_fac_" + zn.replace("_", ""))


## Interior light at dusk / night: a soft warm pool on the GROUND in front of each building's front corner (where its
## door / window light falls). POLISH7-5 (owner 13.9c-18 / 13.9c-24): the old warm wash up the lower half of each facade
## was an additive translucent volume over the building (its walls showed through it): removed; the door lamps
## (g.lights "door") and the art's own windows carry the light on the buildings themselves.
func _facade_light(g: Dictionary, n: float) -> void:
	for P in g.get("fpool", []):   # LIGHT7: cut where a building hides the ground (_plan_lights)
		_draw_pool(P, Color(1.0, 0.8, 0.5, 0.22 * n))


func _draw_ruin(g: Dictionary) -> void:
	# what is left of the roads and pads: cracked, soot-stained asphalt and concrete
	for l in (g.F.get("lanes", []) as Array):
		_bpoly(_quad(_rect(l)), Color(0.15, 0.15, 0.15, 0.9))
	for zn in ["pad", "helipad", "staging", "apc_wash"]:
		if (g.zones as Dictionary).has(zn):
			var r: Rect2 = g.zones[zn]
			_bpoly(_quad(r), Color(0.33, 0.32, 0.30, 0.95))
			for k in int(r.size.x * 2.0):   # cracks across the slab
				var hs := absi(hash(Vector3i(int(g.id), k, zn.length())))
				var p := r.position + Vector2(float(hs % 97) / 97.0 * r.size.x, float((hs / 97) % 89) / 89.0 * r.size.y)
				var q := p + Vector2(float((hs / 8633) % 7) / 7.0 - 0.5, float((hs / 60431) % 5) / 5.0) * 0.9
				_bline(_iso(p), _iso(q), Color(0.1, 0.1, 0.1, 0.8), 1.0)
	var areas := []
	for zn in g.zones:
		if not OPEN_ZONES.has(zn):
			areas.append(g.zones[zn])
	for ga in g.garages:
		areas.append(ga[0])
	areas.append(Rect2(g.O + Vector2(3, 3), Vector2(4, 4)))
	var ai := 0
	for r in areas:
		var rr: Rect2 = (r as Rect2).grow(-0.2)
		_bpoly(_quad(rr), Color(0.22, 0.21, 0.20, 0.95))   # burnt foundation slab
		_sp("scorch", _iso(rr.get_center()), 0, 0, Color(1, 1, 1, 0.9), maxf(rr.size.x, rr.size.y) * 0.45)
		_cnt("scorch")
		# standing stubs of the walls along the back edges, jagged tops
		for side in [0, 1]:
			var a := rr.position
			var b := Vector2(rr.end.x, rr.position.y) if side == 0 else Vector2(rr.position.x, rr.end.y)
			var segs := int(maxf(rr.size.x, rr.size.y) * 2.0)
			for k in segs:
				var hs := absi(hash(Vector3i(ai, side, k)))
				var hz := float(hs % 18) + 2.0
				if hs % 5 == 0:
					continue
				var p0 := _iso(a.lerp(b, float(k) / float(segs)))
				var p1 := _iso(a.lerp(b, float(k + 1) / float(segs)))
				_bpoly(PackedVector2Array([p0, p1, p1 - Vector2(0, hz * 0.8), p0 - Vector2(0, hz)]), Color(0.40, 0.39, 0.37) if side == 0 else Color(0.33, 0.32, 0.30))
				_bline(p0 - Vector2(0, hz), p1 - Vector2(0, hz * 0.8), Color(0.12, 0.11, 0.1), 1.0)
		var nx := maxi(1, int(round(rr.size.x / 1.6)))
		var ny := maxi(1, int(round(rr.size.y / 1.6)))
		for iy in ny:
			for ix in nx:
				var c := rr.position + Vector2((float(ix) + 0.5) * rr.size.x / float(nx), (float(iy) + 0.5) * rr.size.y / float(ny))
				_sp("rubble%d" % ((ix * 7 + iy * 3 + ai) % 3), _iso(c) + Vector2(0, -4), 0, 0, Color.WHITE, 0.95)
				_cnt("rubble")
		ai += 1


# =============================================================== props (z 2, under the entities, animated)
func _wind_strength() -> float:
	return 0.65 + 0.25 * sin(t * 0.37) + 0.1 * sin(t * 1.9)


## POLISH7: the two HQ flag poles stand in front of the HQ (nothing in front of them but the open lane), so they draw
## on the over layer: under props the HQ's own canopy / facade (drawn after props) covered the poles and flags.
func _draw_flags(g: Dictionary) -> void:
	var left := ViewUtil.iso(wind).x < 0.0
	for i in (g.flags as Array).size():
		var fp := _iso(g.flags[i])
		over.draw_line(fp, fp + Vector2(0, -34), Color(0.62, 0.63, 0.65), 1.0)
		over.draw_line(fp + Vector2(1, 0), fp + Vector2(1, -34), Color(0.32, 0.33, 0.35), 1.0)
		over.draw_rect(Rect2(fp + Vector2(-1, -1), Vector2(4, 2)), Color(0.30, 0.31, 0.32))   # footing
		var col: Color = mv.team_color(int(g.owner)) if i == 0 and mv != null and mv.has_method("team_color") else Color.WHITE
		var fr := int(t * (6.0 + 6.0 * _wind_strength()) + float(i) * 2.0) % 6
		over.draw_set_transform(fp + Vector2(1, -34), 0.0, Vector2(-1.0 if left else 1.0, 1.0))
		_sp("flag", Vector2.ZERO, fr, 0 if i == 0 else 1, col, 1.0, over)
		over.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		counts["flags"] += 1


func _draw_props() -> void:
	for g in geo:
		if not _vr.intersects(g.bbox):
			continue
		var ws := _iso(g.windsock)
		var sd := ViewUtil.iso(wind)   # screen direction of the wind
		var d8 := int(round(fposmod(atan2(sd.y / 0.6, sd.x), TAU) / TAU * 8.0)) % 8
		_sp("windsock", ws, int(t * (4.0 + 6.0 * _wind_strength())) % 4, d8, Color.WHITE, 1.0, props)
		# (POLISH7: the HQ flags moved to _draw_flags on the over layer)
		# helipad blast shields, back edges (north / west) rise behind the craft
		var sh := _shield_h(g)
		if sh > 0.5 and g.zones.has("helipad"):
			var r: Rect2 = g.zones.helipad
			_shield(props, Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), sh)
			_shield(props, Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y), sh)


func _shield_h(g: Dictionary) -> float:
	var a: Dictionary = _alarm.get(int(g.id), {})
	if not bool(a.get("lock_on", false)):
		var since := t - float(a.get("lock_t", -99.0))
		return maxf(0.0, 10.0 * (1.0 - since / 1.2)) if since < 1.2 else 0.0
	return 10.0 * clampf((t - float(a.get("lock_t", t - 9.0))) / 1.6, 0.0, 1.0)


func _shield(n: CanvasItem, a: Vector2, b: Vector2, h: float) -> void:
	var L := a.distance_to(b)
	var d := (b - a) / L
	var k := 0
	var s := 0.0
	while s < L - 0.01:
		var s2 := minf(s + 1.0, L)
		var p0 := _iso(a + d * s)
		var p1 := _iso(a + d * s2)
		var up := Vector2(0, -h)
		n.draw_colored_polygon(PackedVector2Array([p0, p1, p1 + up, p0 + up]), Color(0.36, 0.38, 0.40) if k % 2 == 0 else Color(0.31, 0.33, 0.35))
		n.draw_line(p0 + up, p1 + up, Color(0.55, 0.57, 0.58), 1.0)
		n.draw_line(p0 + up * 0.35, p1 + up * 0.35, HAZ_Y, 1.0)
		s = s2
		k += 1


# =============================================================== over (z 3, over the entities)
func _puffs(base: Vector2, n: int, life: float, rise: float, drift: float, size: float, col: Color, seed: int, alpha := 1.0) -> void:
	var sd := ViewUtil.iso(wind).normalized()
	var ws := _wind_strength()
	for i in n:
		var ph := fposmod(t / life + float(i) / float(n) + float(seed % 97) * 0.013, 1.0)
		var jit := float(absi(hash(Vector2i(seed, i))) % 100) / 100.0 - 0.5
		var p := base + sd * drift * ws * ph + Vector2(jit * 6.0 * ph, -rise * ph)
		var a := col.a * alpha * (1.0 - ph) * minf(1.0, ph * 6.0)
		_sp("puff%d" % (i % 3), p, 0, 0, Color(col, a), size * (0.45 + 1.3 * ph), over)
	_cnt("puffs", n)


func _draw_over() -> void:
	for k in ["puffs", "fires", "cracks", "beacons", "shutters", "mist", "plaques", "flags"]:
		counts[k] = 0
	for g in geo:
		if not _vr.intersects(g.bbox):
			continue
		_draw_flags(g)
		_draw_fixtures(g, true)   # LIGHT7-5: only the alarm strobes here (every steady fixture is on fixo, _draw_fixo)
		# POLISH7-2 (13.9c-14): the masts under FACB7's red obstruction lamps (tower (-1.2, -1.2) m to 12.8 m, checkpoint
		# (3.4, -3.3) m to 7.2 m): the art's 3-6 cm masts vanish at every zoom and the lamp hung in the air
		for k in (g.towers as Array).size():
			if not _hid(g, "t%d" % k):
				var mb := _iso(g.towers[k] + MAST_OFF)
				over.draw_line(mb - Vector2(0, TOWER_ROOF_Z), mb - Vector2(0, MAST_TOP_Z), MAST_COL, 1.0)
		var cm := _iso(Vector2(g.checkpoint) + Vector2(0.85, -0.825))
		over.draw_line(cm - Vector2(0, 5.24 * PX_M), cm - Vector2(0, 7.1 * PX_M), MAST_COL, 1.0)
		var a: Dictionary = _alarm.get(int(g.id), {})
		var lvl := float(a.get("lvl", 0.0))
		var lock := bool(a.get("lock_on", false))
		# smoke and steam
		var i := 0
		for e in g.emit:
			var gp := _iso(e[0]) - Vector2(0, float(e[1]))
			match String(e[2]):
				"exhaust":
					_puffs(gp, 6, 3.4, 34.0, 26.0, 0.8, Color(0.30, 0.30, 0.31, 0.55), int(g.id) * 31 + i)
				"steam":
					_puffs(gp, 6, 2.6, 30.0, 16.0, 0.9, Color(0.96, 0.97, 0.98, 0.55), int(g.id) * 31 + i)
				"vent":
					_puffs(gp, 4, 2.2, 16.0, 10.0, 0.6, Color(0.95, 0.96, 0.97, 0.40), int(g.id) * 31 + i)
			i += 1
		# decon mist: drifting low banks over the wash / decon hall; on lockdown the decon zone floods
		var areas: Array = g.flood if lock else g.mist
		var dens := 0.55 if lock else 0.22
		var ai := 0
		for r in areas:
			var rr: Rect2 = (r as Rect2).grow(-0.5)   # LIGHT7 (13.9c-18): banks stay inside the open zone
			if rr.size.x <= 0.0:
				continue
			var nb := int(clampf(rr.size.x * rr.size.y * 0.6, 4.0, 22.0))
			for k in nb:
				var hs := absi(hash(Vector3i(int(g.id), ai, k)))
				var u := fposmod(float(hs % 101) / 101.0 + wind.x * t * 0.018, 1.0)
				var v := fposmod(float((hs / 101) % 103) / 103.0 + wind.y * t * 0.018, 1.0)
				var p := rr.position + Vector2(u * rr.size.x, v * rr.size.y)
				var breathe := 0.75 + 0.25 * sin(t * 0.7 + float(k))
				var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v)) * 4.0
				_sp("puff%d" % (k % 3), _iso(p) - Vector2(0, 4), 0, 0, Color(MIST_COL, dens * breathe * clampf(edge, 0.0, 1.0)), 1.7, over)
				counts["mist"] += 1
			ai += 1
		# blast-door shutters over the visible doors (garages on +x, building doors on +x / +y)
		var sp := clampf((t - float(a.get("lock_t", -99.0))) / 1.6, 0.0, 1.0)
		var shut := sp if lock else (1.0 - sp)
		if shut > 0.01:
			for ga in g.garages:
				if int(ga[1]) == 0:
					var r: Rect2 = ga[0]
					_shutter(0, r.end.x - INSET, r.get_center().y, 0.56, DOOR_Z, shut)   # ATMO7-2: on FACB7-2's inset facade
			for d in g.doors:
				if (d as Array).size() > 4:   # POLISH7: FACB7 door geometry (planning / lab)
					_shutter(int(d[1]), float(d[3]), float(d[2]), float(d[4]), float(d[5]), shut)
				else:
					_shutter(int(d[1]), float(d[3]) - INSET, float(d[2]), 0.42, DOOR_Z * 0.8, shut)
			# front blast shields of the helipad (south / east edges)
			if g.zones.has("helipad"):
				var r2: Rect2 = g.zones.helipad
				var sh := _shield_h(g)
				_shield(over, Vector2(r2.position.x, r2.end.y), r2.end, sh)
				_shield(over, Vector2(r2.end.x, r2.position.y), r2.end, sh)
		_draw_plaques(g)   # POLISH7-2: after the shutters, so a lockdown shutter never covers a building's name
		# LIGHT7-2: the wall alarm strobes are plan fixtures ("alarm", on the battlement top): _draw_fixtures draws them
		# alarm beacons (sprite) on every tower and both gates
		if lvl > 0.0:
			var row := 0 if bool(a.get("red", false)) else 1
			for k in (g.towers as Array).size():
				if _hid(g, "t%d" % k):
					continue   # POLISH7-2: a taller building stands in front of this roof corner
				_sp("beacon", _iso(g.towers[k] + BEACON_OFF) - Vector2(0, TOWER_ROOF_Z), int(t * 12.0 + float(k) * 3.0) % 8, row, Color.WHITE, 1.0, over)
				counts["beacons"] += 1
			var gi := 0
			for q in _gate_posts(g):
				gi += 1
				if _hid(g, "p%d" % (gi - 1)):
					continue
				_sp("beacon", _iso(q[0]) - Vector2(0, float(q[1])), int(t * 12.0 + (q[0] as Vector2).x) % 8, row, Color.WHITE, 1.0, over)
				counts["beacons"] += 1
	# damage: cracks, smoke columns, fires
	for d in _dmg:
		var c: Vector2 = d.c
		var gp := _iso(c)
		if not _vr.has_point(gp):
			continue
		var h := float(d.h)
		var sz := float(d.size)
		var z := float(d.z)
		var sd := int(d.seed)
		_sp("cracks%d" % (sd % 3), gp + Vector2(sz * 8.0, -z * 0.45), 0, 0, Color(1, 1, 1, clampf((0.72 - h) * 3.0, 0.3, 1.0)), 0.6 + sz * 0.25, over)
		counts["cracks"] += 1
		if h < 0.25 and String(d.def) == "cn_tower":
			_sp("cracks%d" % ((sd + 1) % 3), gp + Vector2(-sz * 9.0, -z * 0.7), 0, 0, Color.WHITE, 0.8, over)
		if h < 0.48:
			_puffs(gp - Vector2(0, z * 0.85), 9, 4.5, 110.0, 60.0, 1.8, Color(0.12, 0.11, 0.11, 0.75), sd)
		if h < 0.3:
			for f in (2 if h < 0.15 else 1):
				_sp("fire", gp + Vector2(-6.0 + float(f) * 10.0, -z * (0.8 - 0.25 * float(f))), int(t * 12.0) + f * 2 + sd, 0, Color.WHITE, 1.0 + 0.2 * float(f), over)
				counts["fires"] += 1
	# zone buildings: damage follows the core's hp, each building with its own threshold
	for g in geo:
		var ch := float(_zone_dmg.get(int(g.id), 1.0))
		if ch >= 0.75 or not _vr.intersects(g.bbox):
			continue
		var zi := 0
		for zn in BLD_Z:
			if not (g.zones as Dictionary).has(zn) or not _has_art(zn):   # ATMO7-2: no fire / cracks over a bare slab
				continue
			var r: Rect2 = g.zones[zn]
			var thr := 0.75 - 0.4 * float(absi(hash(zn + str(g.id))) % 100) / 100.0
			if ch < thr:
				var gp := _iso(Vector2(r.end.x - 0.6, r.end.y - 0.6))
				var z := float(BLD_Z[zn])
				_sp("cracks%d" % (zi % 3), gp + Vector2(10, -z * 0.4), 0, 0, Color.WHITE, 1.1, over)
				counts["cracks"] += 1
				if ch < thr - 0.2:
					_puffs(_iso(r.get_center()) - Vector2(0, z), 7, 4.2, 74.0, 44.0, 1.2, Color(0.14, 0.13, 0.13, 0.65), zi * 13 + int(g.id))
					_sp("fire", _iso(r.get_center()) - Vector2(0, z * 0.9), int(t * 12.0) + zi, 0, Color.WHITE, 1.2, over)
					counts["fires"] += 1
			zi += 1
	# ruins: smouldering (fires for the first 90 s, smoke for ever)
	for r in _ruins:
		var g: Dictionary = r.g
		if not _vr.intersects(g.bbox):
			continue
		var age := t - float(r.t0)
		var k := 0
		for zn in g.zones:
			if ["pad", "helipad", "staging", "gate_outer", "gate_inner", "apc_wash"].has(zn):
				continue
			var c: Vector2 = g.zones[zn].get_center()
			_puffs(_iso(c) - Vector2(0, 10), 6, 5.0, 80.0, 50.0, 1.3, Color(0.16, 0.15, 0.15, 0.6), k * 17 + int(g.id))
			if age < 90.0 and k % 2 == 0:
				_sp("fire", _iso(c) - Vector2(0, 6), int(t * 12.0) + k, 0, Color(1, 1, 1, clampf((90.0 - age) / 20.0, 0.0, 1.0)), 1.3, over)
				counts["fires"] += 1
			k += 1


## POLISH7: the blast doors of FACB7's planning / lab art (tools/art/g7_fac7f.gd planning() / lab(): building-local
## metres, pivot = zone centre, local +x = the door side f, rotated by f * 90 deg, 4 m per tile, 9.8 px per m) as
## door entries [zone, face 0 / 1, centre along the face, face line, half width (tiles), height (px)]. Doors on a
## hidden face (f 2 / 3) are skipped. Keep in step with g7_fac7f.gd if FACB7 moves its doors.
static func _facb7_doors(zn: String, zr: Rect2, f: int) -> Array:
	if f != 0 and f != 1:
		return []
	var ex := (zr.size.x if f == 0 else zr.size.y) * 2.0
	var ey := (zr.size.y if f == 0 else zr.size.x) * 2.0
	var ds := []   # [local x, local y, half width, height] in metres
	if zn == "planning":
		var hx := minf((2.0 * ex - 5.0) * 0.5, 7.0)
		var xf := -ex + 1.6 + 2.0 * hx
		ds.append([xf + 2.2, 0.0, 0.9, 2.5])
	elif zn == "lab":
		var hx2 := minf((2.0 * ex - 4.2) * 0.5, 8.0)
		var hy2 := minf(ey - 2.8, 8.0)
		var xf2 := -ex + 0.8 + 2.0 * hx2
		ds.append([xf2, -1.0 - hy2 * 0.45, 1.8, 3.4])
		ds.append([xf2 + 1.8, -1.0 + hy2 * 0.45, 0.7, 2.3])
	var c := zr.get_center()
	var out := []
	for d in ds:
		var lx := float(d[0]) / 4.0
		var ly := float(d[1]) / 4.0
		if f == 0:   # local +x -> +x, local +y -> +y
			out.append([zn, 0, c.y + ly, c.x + lx + 0.03, float(d[2]) / 4.0 + 0.03, float(d[3]) * 9.8])
		else:        # local +x -> +y, local +y -> -x
			out.append([zn, 1, c.x - ly, c.y + lx + 0.03, float(d[2]) / 4.0 + 0.03, float(d[3]) * 9.8])
	return out


## A steel blast shutter on a door: face 0 = on the +x face (line x = X, centred at y = c), 1 = on the +y face.
func _shutter(face: int, X: float, c: float, hw: float, dz: float, p: float) -> void:
	var a := _iso(Vector2(X, c - hw) if face == 0 else Vector2(c - hw, X))
	var b := _iso(Vector2(X, c + hw) if face == 0 else Vector2(c + hw, X))
	var top := Vector2(0, -dz)
	var bot := Vector2(0, -dz * (1.0 - p))
	over.draw_colored_polygon(PackedVector2Array([a + top, b + top, b + bot, a + bot]), Color(0.34, 0.36, 0.38))
	var n := int(dz * p / 4.0)
	for k in n:   # slats
		var y := -dz + 4.0 * float(k + 1)
		over.draw_line(a + Vector2(0, y), b + Vector2(0, y), Color(0.24, 0.25, 0.27), 1.0)
	var hz := 3.0   # hazard bar on the leading edge
	for k in 6:
		var u0 := float(k) / 6.0
		var u1 := float(k + 1) / 6.0
		var q0 := a.lerp(b, u0) + bot
		var q1 := a.lerp(b, u1) + bot
		over.draw_colored_polygon(PackedVector2Array([q0 + Vector2(0, -hz), q1 + Vector2(0, -hz), q1, q0]), HAZ_Y if k % 2 == 0 else HAZ_K)
	over.draw_line(a + top, b + top, Color(0.55, 0.57, 0.6), 1.0)
	counts["shutters"] = int(counts.get("shutters", 0)) + 1


## POLISH7-2: alarm beacon fixtures of the entry: [world point, height px]: the cap of each gate bastion (the art's own
## lamp sits at its centre) and the checkpoint's east roof parapet.
func _gate_posts(g: Dictionary) -> Array:
	if g.has("posts"):
		return g.posts
	var out := []
	for zn in ["gate_outer", "gate_inner"]:
		if (g.zones as Dictionary).has(zn):
			var r: Rect2 = g.zones[zn]
			var c := r.get_center()
			var ax := Vector2(1, 0) if r.size.x >= r.size.y else Vector2(0, 1)   # the across axis (bastions at its ends)
			var py := (maxf(r.size.x, r.size.y) * 2.0 - 1.3) / 4.0
			out.append([c - ax * py, GATE_CAP_Z])
			out.append([c + ax * py, GATE_CAP_Z])
	out.append([Vector2(g.checkpoint) + CP_BEACON, CP_PARAPET_Z])
	g["posts"] = out
	return out


## POLISH7-2: lights behind a zone building (its prism covers the light on screen) are not drawn: the fx layers draw
## above the entities, so a covered beacon / lamp would hang in front of that building. Keys t<i> tower beacon,
## s<i> searchlight, p<i> entry beacon, l<i> wall lamp; computed once per facility.
func _hid(g: Dictionary, key: String) -> bool:
	if not g.has("hid"):
		var hid := {}
		for k in (g.towers as Array).size():
			if _behind_bld(g, g.towers[k] + BEACON_OFF, TOWER_ROOF_Z + 6.0):
				hid["t%d" % k] = true
			if _behind_bld(g, g.towers[k] + SEARCH_OFF, SEARCH_Z):
				hid["s%d" % k] = true
		var i := 0
		for q in _gate_posts(g):
			if _behind_bld(g, q[0], float(q[1]) + 6.0):
				hid["p%d" % i] = true
			i += 1
		for l in g.lamps:
			if _behind_bld(g, l[0], WALL_CAP_Z + 2.0):
				hid["l%d" % int(l[1])] = true
		g["hid"] = hid
	return (g.hid as Dictionary).has(key)


func _behind_bld(g: Dictionary, at: Vector2, z: float) -> bool:
	var s := _iso(at) - Vector2(0, z)
	for o in _bld_boxes(g):   # LIGHT7-6: the drawn blocks (was the whole-zone prisms: a lamp beside a building counted as hidden)
		var r: Rect2 = o[0]
		if at.x >= r.end.x or at.y >= r.end.y or r.has_point(at):
			continue   # in front of it (or on it)
		var sl: Array = _sil(r, float(o[1]), float(o[2]))
		if (sl[1] as Rect2).has_point(s) and Geometry2D.is_point_in_polygon(s, sl[0]):
			return true
	return false


# =============================================================== dark (multiply) and glow (additive)
func _draw_dark() -> void:
	counts["dark"] = 0
	if night <= 0.004:
		return
	var col := _tint()
	var mw := float(map.get("w", 256))
	var mh := float(map.get("h", 256))
	var pad := 400.0
	var pts := PackedVector2Array([ViewUtil.iso(Vector2(-pad, -pad)), ViewUtil.iso(Vector2(mw + pad, -pad)), ViewUtil.iso(Vector2(mw + pad, mh + pad)), ViewUtil.iso(Vector2(-pad, mh + pad))])
	dark.draw_colored_polygon(pts, col)
	counts["dark"] = 1


func _pool(p: Vector2, rx: float, col: Color) -> void:
	var e: Dictionary = _spr.get("glow", {})
	if e.is_empty():
		return
	if e.has("atex"):
		_gc.draw_texture_rect_region(e.atex, Rect2(p - Vector2(rx, rx * 0.5), Vector2(rx * 2.0, rx)), Rect2(e.ofs, e.tsz), col)
	else:
		_gc.draw_texture_rect(e.tex, Rect2(p - Vector2(rx, rx * 0.5), Vector2(rx * 2.0, rx)), false, col)
	counts["lights"] = int(counts.get("lights", 0)) + 1


func _dot(p: Vector2, r: float, col: Color) -> void:
	var e: Dictionary = _spr.get("spot", {})
	if e.is_empty():
		return
	if e.has("atex"):
		_gc.draw_texture_rect_region(e.atex, Rect2(p - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), Rect2(e.ofs, e.tsz), col)
	else:
		_gc.draw_texture_rect(e.tex, Rect2(p - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, col)


# =============================================================== LIGHT7: the lighting plan (owner 13.9c-24 / 13.9c-24a)
## Owner: "fix the lighting / fog lights / facility lights have all proper realistic placement nothing floating" and
## "lighting and light fixtures still need upgrading and more realistic approach / placement / everything". A hardened
## compound's real fixture types, each DRAWN and mounted on a real surface at that surface's drawn height:
##   wall     wall-top flood on the capping beam (every other wall section), angled OUT at the clear zone
##   wall_in  the same fixture where a pad / helipad lies inside the wall: angled IN over the pad (apron flood)
##   tower    the tower searchlight head (tower art) parked as a yard flood at night; it sweeps the approaches in a lockdown
##   pole     6 m area-light poles on the lane verges, an arm over the lane, a downlight
##   door     bulkhead lamp on the facade just above each visible building / garage door, a small wash down the wall
##   obst     steady red obstruction lamps on the command centre's roof brim corners (the tallest roof)
##   deck     green TLOF perimeter lamps on the barracks roof pad, at deck height
## Colour temperature: area / perimeter / pad floods 5000 K LED (cool white), bulkheads 3000 K (warm), obstruction red,
## pad perimeters green (steady, night / dusk only). Light only falls where a fixture points: every ground pool is
## clipped against every building / garage / tower / wall / checkpoint silhouette (once per facility), so no light sits
## on a roof or shows through a building and nothing is see-through (13.9c-18). The base (non-facility) building lamps
## and the Last Protocol street / mast / pad lights get poles and masts the same way.
const CT_AREA := Color(0.84, 0.91, 1.0)
const CT_DOOR := Color(1.0, 0.80, 0.56)
const CT_RED := Color(1.0, 0.14, 0.08)
const CT_PAD := Color(0.32, 1.0, 0.48)
const POLE_Z := 6.0 * PX_M            # area-light pole head (6 m)
const BASE_POLE_Z := 4.0 * PX_M       # base building yard lamp (4 m)
const LP_STREET_Z := 5.0 * PX_M
const LP_MAST_Z := 9.0 * PX_M
const WALL_HT := 1.45 / 4.0           # rampart half width (WALL7-2: 1.45 m) in tiles, for occlusion
const GARAGE_Z := 46.0
const LINK_Z := 5.85 * PX_M
const BRIM_Z := 15.5 * PX_M           # command centre roof brim (FACB7-4 seq 4583)
const PLAN_ROOF := Rect2(0.1, 0.05, 3.2, 2.9)   # its tower block inside the planning zone (x 8.1..11.3, y 9.05..11.95)
const FLOOD_R := 150.0                # 13.9c-24b: outward flood wash radius (px): wide, overlapping along the wall
const CORE_R := 62.0                  # the hot core near each fixture
const WASH_A := 8.0                   # LIGHT7-3 (13.9c-24b): a wall flood's wash is a ground ellipse stretched ALONG the wall (tiles half-length)
const WASH_B := 4.6                   # ... and this deep out from the wall (tiles half-depth): neighbouring floods (4 tiles apart) overlap into one even band
const CORE_A := 4.6                   # the hot core near the wall foot, along the wall
const WASH_ADD := 0.30                # LIGHT7-4: the wash's additive alpha where the tint is not lifted (north / west faces): lower than the 0.52 it
const CORE_ADD := 0.24                # had at WASH_A 6.6 (three floods now overlap at any point: 0.52 + 0.46 blew out to white)
const CORE_B := 2.4                   # ... and out from it
const MAX_POLES := 30                 # LIGHT7-4 (13.9c-24d): was 14: lane poles + the open-zone masts
const LIGHT_CAP := 480                # pools + lamps drawn per glow redraw (fps bound; LIGHT7-4: was 320, the compound interior is lit like the perimeter)
const YARD_A := 6.0                   # LIGHT7-4 (13.9c-24d): an inward yard flood's wash: half-length along the wall (tiles; floods are 4 apart) ...
const YARD_B := 6.0                   # ... and half-depth into the yard
const YARD_CA := 3.4                  # its hot core ...
const YARD_CB := 1.9
const YARD_WASH := 0.34               # additive alphas of the yard wash / core (the ground inside is not tint-lifted: the hex never lifts)
const YARD_CORE := 0.26
const POLE_R := 140.0                 # lane pole / zone mast pool radius (px): was 70
const POLE_A := 0.30                  # its additive alpha (LIGHT7-5: 0.46 -> 0.30, the pool now also lifts the night tint, IL_POLE)
const IY_WASH := 0.46                 # LIGHT7-5 (13.9c-24d): interior tint lift of a yard flood's wash (the perimeter's 0.34 wash + its core's share)
const IL_POLE := 0.46                 # ... of a lane pole / zone mast / apron flood pool
const IL_MAST := 0.50                 # ... of an area mast (9 m, two flood luminaires)
const IL_MIN := 0.12                  # every lane / apron cell the camera sees gets at least this lift (masts are added until it does)
const MAX_MASTS := 12
const FIX_CAP := 140                  # fixtures per facility (fps budget, test_light_count_bounded)
const MAX_WALLF := 6                   # LIGHT7-6: wall-pack floods on building faces (cells no mast verge reaches)
const WALLF_Z := 6.0 * PX_M            # their bracket: under the first roof line (the workshop's shop storey is 6.5 m)
const WF_A := 4.4                      # their wash: half-length along the face (tiles) ...
const WF_B := 3.6                      # ... and half-depth out from it
const WF_CA := 2.0                     # the hot core
const WF_CB := 1.2
const MAST_Z := 9.0 * PX_M            # area mast crossbar (9 m)
const MAST_R := 340.0                 # its pool radius (px; a ground circle of ~4.7 tiles): the perimeter wash's class
const MAST_ADD := 0.18                # its additive alpha
const YARD_ADD := 0.24                # LIGHT7-5: the yard wash / core additive alphas once the tint is lifted too (were YARD_WASH / YARD_CORE)
const YARD_CADD := 0.20


## LIGHT7-5: the ground cells where units work (lanes, pads, staging, wash, inner gate, fuel point) that the camera sees.
func _work_cells(g: Dictionary, C: Dictionary) -> Array:
	var O: Vector2 = g.O
	var rs := []
	for ln in C.get("lanes", []):
		rs.append(Rect2(O + Vector2(float(ln[0]), float(ln[1])), Vector2(float(ln[2]), float(ln[3]))))
	for zn in ["pad", "helipad", "staging", "apc_wash", "gate_inner", "fuel_point"]:
		if (g.zones as Dictionary).has(zn):
			rs.append(g.zones[zn])
	var out := []
	var seen := {}
	for r in rs:
		for y in int((r as Rect2).size.y):
			for x in int((r as Rect2).size.x):
				var p: Vector2 = (r as Rect2).position + Vector2(float(x) + 0.5, float(y) + 0.5)
				if seen.has(p) or _ground_hid(g, p):
					continue
				seen[p] = true
				out.append(p)
	return out


## LIGHT7-5 (13.9c-24d): a fixture's interior tint-lift ellipses [screen centre, P, Q, strength at full night]: a yard flood's wash and hot
## core, a round pool for lane poles, apron floods and area masts. The dark shader lifts the night tint inside them on ground only.
func _ilv(F: Dictionary) -> Array:
	match String(F.k):
		"yard", "wallf":
			return [[_iso(F.pool), F.wp, F.wq, IY_WASH]]
		"pole", "wall_in", "mast":
			var r := float(F.r)
			return [[_iso(F.pool), Vector2(r, 0.0), Vector2(0.0, r * 0.5), IL_MAST if String(F.k) == "mast" else IL_POLE]]
	return []


## LIGHT7-7: the interior tint lift each work cell gets from a fixture list (the sum the planner and the coverage test both use).
func _work_lift(work: Array, fix: Array) -> PackedFloat32Array:
	var lv := PackedFloat32Array()
	lv.resize(work.size())
	var ws := []
	for p in work:
		ws.append(_iso(p))
	for F in fix:
		for e in _ilv(F):
			for k in work.size():
				lv[k] += _ell_f(e, ws[k])
	return lv


## LIGHT7-7: how much a candidate fixture F adds toward IL_MIN across the work cells (lifts already past IL_MIN count for nothing).
func _lift_gain(F: Dictionary, ws: Array, lv: PackedFloat32Array) -> float:
	var gain := 0.0
	for k in ws.size():
		if lv[k] >= IL_MIN:
			continue
		var add := 0.0
		for e in _ilv(F):
			add += _ell_f(e, ws[k])
		gain += minf(add, IL_MIN - lv[k])
	return gain


## The dark shader's falloff of one lift ellipse e (as _ilv) at screen point s (the same formula as the shader).
static func _ell_f(e: Array, s: Vector2) -> float:
	var P: Vector2 = e[1]
	var Q: Vector2 = e[2]
	var det := P.x * Q.y - P.y * Q.x
	if absf(det) < 0.001:
		return 0.0
	var d: Vector2 = s - (e[0] as Vector2)
	var f := clampf(1.0 - Vector2((Q.y * d.x - Q.x * d.y) / det, (-P.y * d.x + P.x * d.y) / det).length(), 0.0, 1.0)
	return f * sqrt(f) * float(e[3])


## Screen silhouette of a prism (ground rect r, height h px): [polygon, bbox].
func _sil(r: Rect2, h: float, z0 := 0.0) -> Array:   # LIGHT7-5: z0 > 0: a raised prism (a gantry beam, a canopy roof)
	var b := Vector2(0, -z0)
	var q := [_iso(r.position) + b, _iso(Vector2(r.end.x, r.position.y)) + b, _iso(r.end) + b, _iso(Vector2(r.position.x, r.end.y)) + b]
	var up := Vector2(0, -h)
	var poly := PackedVector2Array([q[3], q[3] + up, q[0] + up, q[1] + up, q[1], q[2]])
	return [poly, _bb(poly)]


static func _bb(poly: PackedVector2Array) -> Rect2:
	var bb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	return bb


## Every opaque thing of the facility that hides ground behind it: [ground rect, height px].
func _occ_rects(g: Dictionary, C: Dictionary) -> Array:
	var O: Vector2 = g.O
	var cs := float(g.cs)
	var R := []
	for zn in BLD_Z:
		if zn == "core":
			R.append([g.core_r, BLD_Z.core])
		elif (g.zones as Dictionary).has(zn) and _has_art(zn):
			R.append([g.zones[zn], BLD_Z[zn]])
	if (g.zones as Dictionary).has("range") and _has_art("range"):
		R.append([Rect2((g.zones.range as Rect2).position + RANGE_BLD.position, RANGE_BLD.size), RANGE_BLD_Z])
	R.append_array(_occ_rest(g, C))
	return R


## LIGHT7-6: the occluders the LIGHT uses (ground pools, the tint-lift mask, hidden ground / fixtures): the drawn building blocks
## (_bld_boxes, read from the art) instead of whole-zone prisms, + every other opaque part. A zone prism stood up to 2 tiles proud of
## the workshop / command centre art: the ground the camera sees behind them lost its light in a hard-edged block (LIGHT7-5 y4 shot).
func _light_occ(g: Dictionary, C: Dictionary) -> Array:
	var R := (_bld_boxes(g) as Array).duplicate()
	R.append_array(_occ_rest(g, C))
	return R


func _occ_rest(g: Dictionary, C: Dictionary) -> Array:
	var O: Vector2 = g.O
	var cs := float(g.cs)
	var R := []
	for ga in g.garages:
		R.append([(ga[0] as Rect2).grow(-0.1), GARAGE_Z])
	for tc in g.towers:
		R.append([Rect2(tc - Vector2(0.55, 0.55), Vector2(1.1, 1.1)), TOWER_ROOF_Z])
	R.append([Rect2(O + Vector2(0, 1.0 - WALL_HT), Vector2(cs, WALL_HT * 2.0)), WALL_CAP_Z])
	R.append([Rect2(O + Vector2(0, cs - 1.0 - WALL_HT), Vector2(cs, WALL_HT * 2.0)), WALL_CAP_Z])
	R.append([Rect2(O + Vector2(1.0 - WALL_HT, 0), Vector2(WALL_HT * 2.0, cs)), WALL_CAP_Z])
	R.append([Rect2(O + Vector2(cs - 1.0 - WALL_HT, 0), Vector2(WALL_HT * 2.0, cs)), WALL_CAP_Z])
	R.append([Rect2(Vector2(g.checkpoint) - Vector2(0.9, 0.9), Vector2(1.8, 1.8)), CP_PARAPET_Z])
	for lw in C.get("link_walls", []):
		R.append([Rect2(O + Vector2(float(lw[0]), float(lw[1])), Vector2(float(lw[2]), float(lw[3]))).grow(-0.3), LINK_Z])
	R.append_array(_art_occ(g, C))   # LIGHT7-5
	return R


## LIGHT7-6: the drawn building blocks of each zone building, read from tools/art/g7_fac7f.gd (metres from the zone centre, local +x =
## the door side, rotated by it like _art_occ): [ground rect, height px, base px, false]. Block tops include the 0.24 m parapet; a
## cantilevered upper block or a deck gets its own raised prism, so the ground in front of a recessed ground floor stays lit.
## Cached on g (lbld). A zone without a table entry keeps its whole-zone prism.
func _bld_boxes(g: Dictionary) -> Array:
	if g.has("lbld"):
		return g.lbld
	var R := []
	var Z: Dictionary = g.zones
	for zn in BLD_Z:
		if zn == "core":
			if g.has("core_r"):
				R.append([g.core_r, BLD_Z.core, 0.0, false])
			continue
		if not Z.has(zn) or not _has_art(zn):
			continue
		var zr: Rect2 = Z[zn]
		var f := _zone_f(g, zn)
		var ex := (zr.size.x if f % 2 == 0 else zr.size.y) * 2.0
		var ey := (zr.size.y if f % 2 == 0 else zr.size.x) * 2.0
		var c := zr.get_center()
		var bx := []   # [x, y, hx, hy, z0 m, z1 m]
		match zn:
			"planning":   # planning(): ground floor, cantilevered floors 2-3 (+0.5 m), the leaning ops crown to the 15.5 m brim
				var hx := minf(ex - 2.2, 5.8)
				var hy := minf(ey - 1.2, 4.8)
				var ux := hx + 0.5
				var uy := minf(hy + 0.5, ey - 0.6)
				bx = [[-1.2, 0.0, hx, hy, 0.0, 4.2], [-1.2, 0.0, ux, uy, 4.2, 11.4],
					[-1.2, 0.0, minf(ux + 0.7, ex - 1.6), minf(uy + 0.5, ey - 0.3), 11.4, 15.5]]
			"workshop":   # workshop(): the shop block; stacked (FACB7-5): its drone-bay storey to the launch deck (10.4 m + deck plate) + the stair core penthouse
				var hx := minf((2.0 * ex - 8.6) * 0.5, 8.0)
				var cx := -ex + 3.4 + hx
				var hy := minf(ey - 3.0, 9.5)
				if _stacked(g, "drone_bay"):
					bx = [[cx, 0.0, hx + 0.12, hy + 0.12, 0.0, 10.6], [cx - hx - 1.0, -hy + 0.85, 0.95, 0.85, 0.0, 12.7]]
				else:
					bx = [[cx, 0.0, hx, hy, 0.0, 6.74]]
			"barracks":   # barracks(): hardened ground floor, armour-clad floors 2-3 (+0.25 m) to the 11.3 m parapet, the helideck slab on stub columns
				var x0 := -ex + 0.4
				var x1 := ex - 2.0
				var y0 := -ey + 0.3
				var y1 := ey - 0.3
				var cx := (x0 + x1) * 0.5
				var cy := (y0 + y1) * 0.5
				var hx := (x1 - x0) * 0.5
				var hy := (y1 - y0) * 0.5
				if not bool(g.F.get("bar", true)):
					bx = [[cx, cy, hx, hy, 0.0, 3.64]]
				else:
					var lx := ex >= ey
					bx = [[cx, cy, hx, hy, 0.0, 3.6], [cx, cy, hx + 0.25, hy + 0.25, 3.6, 11.3],
						[-0.1, 0.0, minf(ex - 0.3, 7.6 if lx else 3.8), minf(ey - 0.2, 3.8 if lx else 7.6), 11.0, 11.8]]
			"lab":   # lab(): the lab block + the side annex
				var hx := minf((2.0 * ex - 4.2) * 0.5, 8.0)
				var cx := -ex + 0.8 + hx
				var hy := minf(ey - 2.8, 8.0)
				bx = [[cx, -1.0, hx, hy, 0.0, 5.24], [cx + hx + 0.9, -1.0 + hy * 0.45, 0.9, 1.2, 0.0, 3.24]]
			"decon_hall":   # decon_hall(): the hall block (roof plant inside its 5.1 m)
				var hx := minf(ex - 2.2, 9.0)
				var hy := minf(ey - 1.2, 4.5)
				bx = [[-ex + 0.6 + hx, 0.0, hx, hy, 0.0, 5.1]]
			"magazine":   # magazine(): the earth-covered cell + headwall (3.9 m)
				var x0 := -ex + 0.4
				var xh := ex - 3.9
				var hw := minf(ey - 0.4, 3.5)
				bx = [[(x0 + xh + 0.7) * 0.5, 0.0, (xh + 0.7 - x0) * 0.5, hw + 0.3, 0.0, 3.9]]
			"armory":   # armory() (Suit Foundry): hall + bay jambs + header (11.6 m), power annex (7.4 m), issue wing (5.2 m); the test apron stays open
				var x0 := -ex + 0.3
				var xf := ex - 3.4
				var yn := -ey + 0.2
				var yw := ey * 0.375
				var ye := ey - 0.1
				var xa := x0 + 4.6
				bx = [[(x0 + xf) * 0.5, (yn + yw) * 0.5, (xf - x0) * 0.5, (yw - yn) * 0.5, 0.0, 11.84],
					[(x0 + xa) * 0.5, (yw + ye) * 0.5, (xa - x0) * 0.5, (ye - yw) * 0.5, 0.0, 7.64],
					[(xa + xf) * 0.5, (yw + ye) * 0.5, (xf - xa) * 0.5, (ye - yw) * 0.5, 0.0, 5.44]]
			"aid_station":   # aid_station(): the quarantine block (4.4 m) and the ward (3.8 m)
				var x0 := -ex + 0.9
				var xq := x0 + 3.8
				var x1 := ex - 2.0
				var y0 := -ey + 0.05
				var y1 := ey - 0.9
				bx = [[(x0 + xq) * 0.5, (y0 + y1) * 0.5, (xq - x0) * 0.5, (y1 - y0) * 0.5, 0.0, 4.64],
					[(xq + x1) * 0.5, (y0 + y1) * 0.5, (x1 - xq) * 0.5, (y1 - y0) * 0.5, 0.0, 4.04]]
		if bx.is_empty():
			R.append([zr, BLD_Z[zn], 0.0, false])
			continue
		for b in bx:
			var z0 := float(b[4]) * PX_M
			R.append([_zbox(c, f, float(b[0]), float(b[1]), float(b[2]), float(b[3])), float(b[5]) * PX_M - z0, z0, false])
	if Z.has("range") and _has_art("range"):
		R.append([Rect2((Z.range as Rect2).position + RANGE_BLD.position, RANGE_BLD.size), RANGE_BLD_Z, 0.0, false])
	g.lbld = R
	return R


## Art-local box (centre x, y, half sizes hx, hy, metres from the zone centre) -> its world ground rect (rotated by the drawn door side f).
static func _zbox(ctr: Vector2, f: int, x: float, y: float, hx: float, hy: float) -> Rect2:
	var a := ctr + _lrot(f, Vector2(x - hx, y - hy)) / 4.0
	var b := ctr + _lrot(f, Vector2(x + hx, y + hy)) / 4.0
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())


func _zone_f(g: Dictionary, zn: String) -> int:
	var F: Dictionary = g.F
	var fcs: Dictionary = F.get("faces", {})
	return int(fcs[zn]) if fcs.has(zn) else EntityLayer.door_side_of(F.zones[zn], F)


## LIGHT7-5 (13.9c-18 / 13.9c-24d): the raised parts of the open-zone art that a ground pool must not paint over (LIGHT7-4's pale
## see-through patches lay on them): read from tools/art/g7_fac7f.gd (metres from the zone centre, rotated by the drawn door side,
## like the bay and the windows): the APC wash's two spray gantries (posts + beam) and its plant (water tank; pump skid and IBC totes),
## the training range's covered firing line (posts + canopy roof), stop berm, observation bunker and target frames, the bastions of
## both APC gates (5.85 m caps), the ammo lockers. [ground rect, height px, base height px, small (CPU cut only, not the shader)].
func _art_occ(g: Dictionary, C: Dictionary) -> Array:
	var R := []
	var O: Vector2 = g.O
	var Z: Dictionary = g.zones
	var man: Dictionary = ArtCat.manifest().get("buildings", {})
	if Z.has("apc_wash") and man.has("g7_fac_wash"):   # apc_wash()
		var zr: Rect2 = Z.apc_wash
		var f := _zone_f(g, "apc_wash")
		var ex := (zr.size.x if f % 2 == 0 else zr.size.y) * 2.0
		var ey := (zr.size.y if f % 2 == 0 else zr.size.x) * 2.0
		var c := zr.get_center()
		var lw := minf(ey - 2.4, 3.2)
		var ly := -(ey - lw - 2.4) * 0.5 if ey - lw > 3.0 else 0.0
		for gx in [-ex * 0.45, ex * 0.45]:
			for s in [-1.0, 1.0]:
				R.append([_zbox(c, f, gx, ly + s * (lw + 0.25), 0.14, 0.14), 4.4 * PX_M, 0.0, false])
			R.append([_zbox(c, f, gx, ly, 0.16, lw + 0.4), 0.5 * PX_M, 4.31 * PX_M, false])   # beam + agent manifold
		var sy := ly + lw + 1.3
		if sy + 1.0 < ey:
			R.append([_zbox(c, f, -ex * 0.45, sy, 1.0, 1.0), 3.1 * PX_M, 0.0, false])   # water tank
			R.append([_zbox(c, f, ex * 0.1, sy, 0.8, 0.6), 1.15 * PX_M, 0.0, true])     # pump skid
			for k in 2:
				R.append([_zbox(c, f, ex * 0.55 + float(k) * 1.3, sy, 0.55, 0.5), 1.15 * PX_M, 0.0, true])   # IBC totes
	if Z.has("range") and _has_art("range"):   # range_(): the training building itself is RANGE_BLD (already an occluder)
		var zr: Rect2 = Z.range
		var f := _zone_f(g, "range")
		var ex := (zr.size.x if f % 2 == 0 else zr.size.y) * 2.0
		var ey := (zr.size.y if f % 2 == 0 else zr.size.x) * 2.0
		var c := zr.get_center()
		var r0 := 0.2
		var lx0 := -2.4
		var fl := 3.4
		for px in [lx0 + 0.1, ex - 0.7]:
			for py in [r0 + 0.4, fl - 0.1]:
				R.append([_zbox(c, f, px, py, 0.08, 0.08), 2.82 * PX_M, 0.0, false])
		R.append([_zbox(c, f, (lx0 + ex - 0.6) * 0.5, (r0 + fl) * 0.5 + 0.15, (ex - 0.6 - lx0) * 0.5 + 0.2, (fl - r0) * 0.5 + 0.2), 0.16 * PX_M, 2.82 * PX_M, false])   # canopy
		R.append([_zbox(c, f, 0.0, ey - 1.15, ex - 0.3, 1.0), 2.4 * PX_M, 0.0, false])   # stop berm
		R.append([_zbox(c, f, -ex + 1.7, fl - 0.6, 0.9, 0.8), 1.6 * PX_M, 0.0, true])   # observation bunker (sandbag roof)
		var lwn := (ex - 0.6 - lx0) / 4.0
		for i in 4:
			R.append([_zbox(c, f, lx0 + lwn * (float(i) + 0.5), ey - 3.6, 0.4, 0.3), 1.5 * PX_M, 0.0, true])   # target frames
	for zn in ["gate_outer", "gate_inner"]:   # gate_layer(): a bastion at each end of the across axis, cap 5.85 m (the _gate_posts points)
		if Z.has(zn):
			var r: Rect2 = Z[zn]
			var ax := Vector2(1, 0) if r.size.x >= r.size.y else Vector2(0, 1)
			var py := (maxf(r.size.x, r.size.y) * 2.0 - 1.3) / 4.0
			var half := ax * (1.45 / 4.0) + Vector2(ax.y, ax.x) * minf(0.8, minf(r.size.x, r.size.y) * 0.5 - 0.1)
			for s in [-1.0, 1.0]:
				var bc: Vector2 = r.get_center() + ax * py * float(s)
				R.append([Rect2(bc - half, half * 2.0), GATE_CAP_Z, 0.0, false])
	for lc in C.get("lockers", []):   # ammo lockers by the tower bases / wall-walk stairs
		R.append([Rect2(O + Vector2(float(lc[0]), float(lc[1])) + Vector2(0.18, 0.18), Vector2(0.64, 0.64)), 28.0, 0.0, true])
	return R


static func _ellipse(c: Vector2, rx: float, ry: float, n := 18) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		var a := TAU * float(k) / float(n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


static func _orient_mix(res: Array) -> bool:
	var cw := 0
	var ccw := 0
	for r in res:
		if Geometry2D.is_polygon_clockwise(r):
			cw += 1
		else:
			ccw += 1
	return cw > 0 and ccw > 0


static func _band(x0: float, x1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, -1.0e6), Vector2(x1, -1.0e6), Vector2(x1, 1.0e6), Vector2(x0, 1.0e6)])


## poly minus every silhouette it overlaps (a silhouette inside the pool: split the pool at its centre first, so no
## result carries a hole). Only simple polygons that triangulate are kept.
static func _clip(poly: PackedVector2Array, sils: Array) -> Array:
	var bb := _bb(poly)
	var polys: Array = [poly]
	for s in sils:
		if not (s[1] as Rect2).intersects(bb):
			continue
		var nxt: Array = []
		for p in polys:
			var res: Array = Geometry2D.clip_polygons(p, s[0])
			if _orient_mix(res):
				var cx: float = (s[1] as Rect2).get_center().x
				for half in [_band(-1.0e6, cx), _band(cx, 1.0e6)]:
					for hp in Geometry2D.intersect_polygons(p, half):
						var r2: Array = Geometry2D.clip_polygons(hp, s[0])
						if not _orient_mix(r2):
							nxt.append_array(r2)
			else:
				nxt.append_array(res)
		polys = nxt
		if polys.is_empty():
			break
	var out: Array = []
	for p in polys:
		if (p as PackedVector2Array).size() >= 3 and not Geometry2D.triangulate_polygon(p).is_empty():
			out.append(p)
	return out


## A ground light pool (ellipse rx x rx/2 px around screen point c) with what the silhouettes hide cut away; drawn
## with the radial glow texture (UVs over the full ellipse, so the falloff is unchanged by the cut).
static func _mk_pool(c: Vector2, rx: float, sils: Array, sub := PackedVector2Array()) -> Dictionary:
	var ry := rx * 0.5
	var ell := _ellipse(c, rx, ry)
	var base: Array = [ell]
	if sub.size() >= 3:   # an outward flood lights only the ground outside the walls (sub = the walled compound's footprint)
		base = Geometry2D.clip_polygons(ell, sub)
	var polys := []
	for b in base:
		polys.append_array(_clip(b, sils))
	var uvs := []
	var o := c - Vector2(rx, ry)
	for p in polys:
		var uv := PackedVector2Array()
		for v in p:
			uv.append(Vector2((v.x - o.x) / (2.0 * rx), (v.y - o.y) / (2.0 * ry)))
		uvs.append(uv)
	return {"polys": polys, "uvs": uvs, "c": c, "rx": rx}


## Tile-space vector -> screen vector (the iso map is linear).
static func _ivec(v: Vector2) -> Vector2:
	return Vector2((v.x - v.y) * 32.0, (v.x + v.y) * 16.0)


## A ground pool for the ellipse centre c with conjugate semi-diameters P, Q (screen px: the image of a tile ellipse), cut like
## _mk_pool. UVs come from the ellipse's own frame, so the radial falloff runs along the long axis (along the wall).
static func _mk_pool_t(c: Vector2, P: Vector2, Q: Vector2, sils: Array, sub := PackedVector2Array(), inside := false) -> Dictionary:
	var ell := PackedVector2Array()
	for k in 28:
		var a := TAU * float(k) / 28.0
		ell.append(c + P * cos(a) + Q * sin(a))
	var base: Array = [ell]
	if sub.size() >= 3:   # inside: only the ground within sub (an inward yard flood); else only the ground outside it (an outward flood)
		base = Geometry2D.intersect_polygons(ell, sub) if inside else Geometry2D.clip_polygons(ell, sub)
	var polys := []
	for b in base:
		polys.append_array(_clip(b, sils))
	var det := P.x * Q.y - P.y * Q.x
	var uvs := []
	for p in polys:
		var uv := PackedVector2Array()
		for v in p:
			var d: Vector2 = v - c
			uv.append(Vector2(0.5 + 0.5 * (Q.y * d.x - Q.x * d.y) / det, 0.5 + 0.5 * (-P.y * d.x + P.x * d.y) / det))
		uvs.append(uv)
	return {"polys": polys, "uvs": uvs, "c": c, "rx": P.length()}


func _draw_pool(P: Dictionary, col: Color) -> void:
	var e: Dictionary = _spr.get("glow", {})
	if e.is_empty() or col.a <= 0.003 or (P.polys as Array).is_empty() or int(counts.get("lights", 0)) >= LIGHT_CAP:
		return
	var cols := PackedColorArray([col])
	for i in (P.polys as Array).size():
		_gpoly(P.polys[i], cols, P.uvs[i], e)
	counts["lights"] = int(counts.get("lights", 0)) + 1


func _fx(k: String, at: Vector2, z: float, aim: Vector2, pool: Vector2, r: float, head_off := 0.0) -> Dictionary:
	var b := _iso(at)
	var hp := b - Vector2(0, z)
	var head := hp
	if head_off != 0.0:
		head = _iso(at + aim * head_off) - Vector2(0, z)
	return {"k": k, "at": at, "z": z, "aim": aim, "pool": pool, "r": r, "base": b, "hp": hp, "head": head, "lens": head, "i": 0, "hid": false}


## Sprite frame of an aim direction: 0 +x (screen right-down), 1 +y (left-down), 2 -x (left-up), 3 -y (right-up).
static func _aim_frame(aim: Vector2) -> int:
	if absf(aim.x) >= absf(aim.y):
		return 0 if aim.x > 0.0 else 2
	return 1 if aim.y > 0.0 else 3


## Is ground point p free for a pole (on a verge: no building, pad, zone, garage, lane, locker, door front, tower, wall)?
func _verge_ok(g: Dictionary, C: Dictionary, p: Vector2, poles: Array, own := Rect2(), sp := 4.0, hz := POLE_Z, kerb := false, vis := true) -> bool:
	var O: Vector2 = g.O
	var cs := float(g.cs)
	if not Rect2(O + Vector2(2.3, 2.3), Vector2(cs - 4.6, cs - 4.6)).has_point(p):
		return false
	for zn in g.zones:
		var zr: Rect2 = g.zones[zn]
		if zr.grow(0.15).has_point(p):
			if kerb and zn in ["staging", "fuel_point"] and minf(minf(p.x - zr.position.x, zr.end.x - p.x), minf(p.y - zr.position.y, zr.end.y - p.y)) <= 0.3:
				continue   # LIGHT7-5: an area mast on the edge of the staging yard / fuel apron (a footing at the yard's rim)
			return false
	if g.core_r.grow(0.15).has_point(p):
		return false
	for ga in g.garages:
		if (ga[0] as Rect2).grow(0.15).has_point(p):
			return false
	for ln in C.get("lanes", []):
		var lr := Rect2(O + Vector2(float(ln[0]), float(ln[1])), Vector2(float(ln[2]), float(ln[3])))
		if lr.grow(0.05).has_point(p) and not lr.is_equal_approx(own):
			if kerb and minf(lr.size.x, lr.size.y) >= 2.0 and minf(minf(p.x - lr.position.x, lr.end.x - p.x), minf(p.y - lr.position.y, lr.end.y - p.y)) <= 0.3:
				continue   # LIGHT7-5: an area mast on the kerb line of a wide lane
			return false
	for key in ["lockers", "popups"]:
		for c in C.get(key, []):
			if Rect2(O + Vector2(float(c[0]), float(c[1])), Vector2.ONE).grow(0.2).has_point(p):
				return false
	var fb: Array = C.get("fuel_bay", [])
	if fb.size() >= 4 and Rect2(O + Vector2(float(fb[0]), float(fb[1])), Vector2(float(fb[2]), float(fb[3]))).grow(0.3).has_point(p):
		return false
	var dc: Dictionary = C.get("doors", {})
	for zn in dc:
		for d in dc[zn]:
			if (O + Vector2(float(d[0]) + 0.5, float(d[1]) + 0.5)).distance_to(p) < 1.3:
				return false
	for q in poles:
		if (q as Vector2).distance_to(p) < sp:
			return false
	return not vis or (not _behind_bld(g, p, 2.0) and not _behind_bld(g, p, hz + 3.0))


## The facility's lighting plan (static): fixtures g.fix (each with its clipped ground pool), the silhouettes g.sil,
## the facade pools g.fpool and the alarm pulse pools g.apool.
func _plan_lights(g: Dictionary, C: Dictionary) -> void:
	var O: Vector2 = g.O
	var cs := float(g.cs)
	var sil := []
	var occ := _occ_rects(g, C)
	for o in occ:
		sil.append(_sil(o[0], float(o[1]), float(o[2]) if (o as Array).size() > 2 else 0.0))
	g.sil = sil
	g.occ = occ   # LIGHT7-3: [ground rect, height px(, base px, small)] per silhouette (the window panes test what stands in front of them)
	# LIGHT7-6: every light below (pools, the tint-lift mask, hidden ground / fixtures) is cut by the DRAWN blocks (g.lsil), not the
	# whole-zone prisms: the ground the camera sees behind a building keeps its light right up to the building's outline
	var locc := _light_occ(g, C)
	var lsil := []
	for o in locc:
		lsil.append(_sil(o[0], float(o[1]), float(o[2]) if (o as Array).size() > 2 else 0.0))
	g.locc = locc
	g.lsil = lsil
	sil = lsil
	g.erase("hid")
	var hx: PackedVector2Array = _sil(Rect2(O + Vector2(1.0 - WALL_HT, 1.0 - WALL_HT), Vector2(cs - 2.0 + 2.0 * WALL_HT, cs - 2.0 + 2.0 * WALL_HT)), 56.0)[0]
	var harea := 0.0
	for hi in hx.size():
		harea += hx[hi].x * hx[(hi + 1) % hx.size()].y - hx[(hi + 1) % hx.size()].x * hx[hi].y
	g.hex = hx   # the compound's footprint extruded to roof height: the dark shader never lifts the tint inside it
	g.hsign = 1.0 if harea >= 0.0 else -1.0
	# the walled compound's ground footprint out to the rampart's outer faces: outward floods light only what lies outside it
	g.foot = _quad(Rect2(O + Vector2(1.0 - WALL_HT, 1.0 - WALL_HT), Vector2(cs - 2.0 + 2.0 * WALL_HT, cs - 2.0 + 2.0 * WALL_HT)))
	var fix := []
	# the wall ring (WALL7-2 heights). Even sections: a flood on the centre battlement panel (4.66 m), angled OUT at the clear zone;
	# where a pad lies inside the wall, on the inner guard-rail post (4.68 m) angled IN over the pad. Odd sections: the red alarm
	# strobe on the same panel. Corner junctions: the art's mast floodlight (head 5.44 m) on the outer corner, lit diagonally out.
	for l in g.lamps:
		var p: Vector2 = l[0]
		var q := p - O
		var out: Vector2 = l[2]
		var along := Vector2(-out.y, out.x)
		if (q.x < 2.0 or q.x > cs - 2.0) and (q.y < 2.0 or q.y > cs - 2.0):
			var sq := Vector2(signf(q.x - cs * 0.5), signf(q.y - cs * 0.5))
			var cat := p + sq * (1.08 / 4.0)
			var cf := _fx("corner", cat, CORNER_MAST_Z, sq.normalized(), cat + sq.normalized() * 2.8, 80.0)
			cf.i = int(l[1])
			fix.append(cf)
			continue
		# the art's inner walkway lamps (3.17 m, +-2 m from the section centre): lit at night on the walls whose inner face the
		# camera sees (north and west); a small pool at the foot of the wall
		if out.x + out.y < 0.0:
			for sgn in [-1.0, 1.0]:
				var wat: Vector2 = p + along * (0.5 * float(sgn)) - out * WALK_OFF
				if _behind_bld(g, wat, WALK_LAMP_Z + 2.0):   # LIGHT7-6 (ORCH light_fixtures): a lamp no camera view shows (a building stands in front) is not fitted
					g.walk_drop = int(g.get("walk_drop", 0)) + 1
					continue
				var W := _fx("walk", wat, WALK_LAMP_Z, -out, wat - out * 0.9, 34.0)
				W.i = int(l[1])
				fix.append(W)
		var at := p + out * PANEL_OFF
		if int(l[1]) % 2 != 0:
			var sf := _fx("alarm", at, WALL_CAP_Z, out, at, 0.0)
			sf.i = int(l[1])
			sf.head = sf.hp - Vector2(0, 4.0)
			fix.append(sf)
			continue
		var F := _fx("wall", at, WALL_CAP_Z, out, at + out * 3.2, FLOOD_R)   # 13.9c-24b: a wide, bright wash on the clear zone
		F.core = at + out * 1.3
		F.core_r = CORE_R
		F.wp = _ivec(along * WASH_A)   # the wash / core ellipses (conjugate semi-diameters on screen): long axis along the wall
		F.wq = _ivec(out * WASH_B)
		F.cp = _ivec(along * CORE_A)
		F.cq = _ivec(out * CORE_B)
		F.lift = out.x + out.y > 0.0   # the south / east faces (open to the camera): the flood also lifts the night tint
		var inn := p - out * 2.6
		for zn in ["pad", "helipad"]:
			if (g.zones as Dictionary).has(zn) and (g.zones[zn] as Rect2).has_point(inn):
				var rat := p + along * 0.2 - out * RAIL_OFF
				F = _fx("wall_in", rat, RAIL_Z, -out, rat - out * 2.6, 84.0)
		F.head = F.hp - Vector2(0, 5.0)
		F.lens = F.hp + Vector2(1.5 if _aim_frame(F.aim) == 0 else -0.5, -5.5)
		fix.append(F)
		# LIGHT7-4 (13.9c-24d): the same fixture again on the inner guard-rail post, aimed INTO the yard: a wide wash along the wall foot inside
		var yat := p - along * 0.2 - out * RAIL_OFF
		var Y := _fx("yard", yat, RAIL_Z, -out, yat - out * 2.4, 90.0)
		Y.core = yat - out * 1.2
		Y.core_r = CORE_R
		Y.wp = _ivec(along * YARD_A)
		Y.wq = _ivec(-out * YARD_B)
		Y.cp = _ivec(along * YARD_CA)
		Y.cq = _ivec(-out * YARD_CB)
		Y.lift = false
		Y.inside = true
		Y.head = Y.hp - Vector2(0, 5.0)
		Y.lens = Y.hp + Vector2(1.5 if _aim_frame(Y.aim) == 0 else -0.5, -5.5)
		fix.append(Y)
	# the entry control point: a flood on each outer gate bastion cap, angled out over the approach road / STOP line
	if (g.zones as Dictionary).has("gate_outer"):
		var gq: Vector2 = (g.zones.gate_outer as Rect2).get_center() - O
		var dn := [gq.y, cs - gq.y, gq.x, cs - gq.x]   # distance to the N, S, W, E wall
		var side := dn.find(dn.min())
		var gout: Vector2 = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)][side]
		var gi := 0
		for q in _gate_posts(g):
			if gi < 2:
				var F := _fx("gate", q[0], float(q[1]), gout, (q[0] as Vector2) + gout * 3.6, FLOOD_R)
				F.core = (q[0] as Vector2) + gout * 1.5
				F.core_r = CORE_R
				var gal := Vector2(-gout.y, gout.x)
				F.wp = _ivec(gal * WASH_A)
				F.wq = _ivec(gout * WASH_B)
				F.cp = _ivec(gal * CORE_A)
				F.cq = _ivec(gout * CORE_B)
				F.lift = gout.x + gout.y > 0.0
				F.head = F.hp - Vector2(0, 5.0)
				F.lens = F.hp + Vector2(1.5 if _aim_frame(gout) == 0 else -0.5, -5.5)
				fix.append(F)
			gi += 1
	# tower searchlight heads, parked as yard floods (the pool g.lights "flood")
	for k in (g.towers as Array).size():
		var tc: Vector2 = g.towers[k]
		var inn: Vector2 = (tc - g.ctr).normalized()   # 13.9c-24b: the parked searchlight floods the glacis outside, not the yard
		var F := _fx("tower", tc + SEARCH_OFF, SEARCH_Z, inn, tc + inn * 3.6, FLOOD_R + 20.0)
		F.core = tc + inn * 2.0
		F.core_r = CORE_R + 4.0
		F.lift = inn.x + inn.y > -0.01
		F.tw = k
		fix.append(F)
	# area-light poles on the lane verges (an arm over the lane)
	var poles := []
	for ln in C.get("lanes", []):
		var r := Rect2(O + Vector2(float(ln[0]), float(ln[1])), Vector2(float(ln[2]), float(ln[3])))
		var horiz := r.size.x >= r.size.y
		var L := r.size.x if horiz else r.size.y
		if L < 3.0:
			continue
		var n := maxi(1, int(L / 4.0))   # LIGHT7-4: a pole every ~4 tiles (was 5)
		for i in n:
			if poles.size() >= MAX_POLES:
				break
			var u := (float(i) + 0.5) / float(n)
			var wide := (r.size.y if horiz else r.size.x) >= 2.0   # a wide lane: the pole may stand on its kerb line
			for cand in [[-1.0, 0.2], [1.0, 0.2], [-1.0, -0.2], [1.0, -0.2]]:
				var side: float = cand[0]
				var o: float = cand[1]   # + on the verge outside the lane, - on the kerb line just inside a wide lane
				if o < 0.0 and not wide:
					continue
				var p: Vector2
				var arm: Vector2
				if horiz:
					var x := r.position.x + u * r.size.x
					p = Vector2(x, r.position.y - o) if side < 0.0 else Vector2(x, r.end.y + o)
					arm = Vector2(0, -side)
				else:
					var y := r.position.y + u * r.size.y
					p = Vector2(r.position.x - o, y) if side < 0.0 else Vector2(r.end.x + o, y)
					arm = Vector2(-side, 0)
				if _verge_ok(g, C, p, poles, r if o < 0.0 else Rect2()):
					poles.append(p)
					fix.append(_fx("pole", p, POLE_Z, arm, p + arm * 0.6, POLE_R, 0.3))
					break
	# LIGHT7-4 (13.9c-24d): an area-light pole at the verge of each open working zone (pads, staging, the APC wash, the inner gate), the arm
	# reaching over the zone, so the aprons / pads / wash have their own floods (same fixture, same checks as the lane poles)
	for zn in ["pad", "helipad", "staging", "apc_wash", "gate_inner", "fuel_point"]:
		if not (g.zones as Dictionary).has(zn) or poles.size() >= MAX_POLES:
			continue
		var zr: Rect2 = g.zones[zn]
		var zc := zr.get_center()
		var cands := []
		for dd in [0.6, 1.1]:
			var rr := zr.grow(dd)
			for cp in [rr.position, Vector2(rr.get_center().x, rr.position.y), Vector2(rr.end.x, rr.position.y), Vector2(rr.end.x, rr.get_center().y),
					rr.end, Vector2(rr.get_center().x, rr.end.y), Vector2(rr.position.x, rr.end.y), Vector2(rr.position.x, rr.get_center().y)]:
				cands.append(cp)
		for cp in cands:
			var ok := true
			for q in poles:
				ok = ok and (q as Vector2).distance_to(cp) >= 3.5
			if ok and _verge_ok(g, C, cp, poles):
				var dir: Vector2 = (zc - cp).normalized()
				var arm: Vector2 = Vector2(signf(dir.x), 0.0) if absf(dir.x) >= absf(dir.y) else Vector2(0.0, signf(dir.y))
				poles.append(cp)
				fix.append(_fx("pole", cp, POLE_Z, arm, cp + arm * 0.6, POLE_R + 24.0, 0.3))
				break
	# bulkhead lamps above the visible doors (FACB7 doors: the art's own door line and height) and garage doors
	for d in g.doors:
		if String(d[0]) == "armory" and int(d[1]) == 0 and _has_art("armory"):   # LIGHT7-4: the open bay's own lamps (header strip, door-head housing, jamb status lamps) are in the art: a generic bulkhead 1.7 m out on the apron floated
			continue
		var f := int(d[1])
		var c := float(d[2])
		var X := float(d[3]) if (d as Array).size() > 4 else float(d[3]) - INSET
		var z := (float(d[5]) if (d as Array).size() > 4 else DOOR_Z * 0.8) + 4.0
		var at := Vector2(X, c) if f == 0 else Vector2(c, X)
		var nrm := Vector2(1, 0) if f == 0 else Vector2(0, 1)
		var zr0: Rect2 = (g.zones as Dictionary).get(String(d[0]), g.core_r)
		var edge := (zr0.end.x if f == 0 else zr0.end.y) - X   # an inset facade: the pool falls beyond the zone edge
		var F := _fx("door", at, z, nrm, at + nrm * (maxf(edge, 0.0) + 0.6), 62.0)
		F.f = f
		fix.append(F)
	for ga in g.garages:
		var r: Rect2 = ga[0]
		var east := int(ga[1]) == 0
		var at := Vector2(r.end.x - INSET, r.get_center().y) if east else Vector2(r.position.x + INSET, r.get_center().y)
		var nrm := Vector2(1, 0) if east else Vector2(-1, 0)
		var F := _fx("door", at, DOOR_Z + 5.0, nrm, at + nrm * 0.9, 74.0)
		F.f = 0 if east else 2
		fix.append(F)
	# obstruction lamps on the command centre's roof brim corners
	if (g.zones as Dictionary).has("planning") and _has_art("planning"):
		var pr: Rect2 = g.zones.planning
		var rr := Rect2(pr.position + PLAN_ROOF.position, PLAN_ROOF.size).grow(-0.1)
		for cp in [rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]:
			fix.append(_fx("obst", cp, BRIM_Z, Vector2.ZERO, cp, 0.0))
	# barracks roof pad: green TLOF perimeter lamps at deck height
	var rp: Dictionary = C.get("roof_pad", {})
	if rp.has("rect") and (g.zones as Dictionary).has(String(rp.get("zone", "barracks"))):
		var a: Array = rp.rect
		var rr := Rect2(O + Vector2(float(a[0]), float(a[1])), Vector2(float(a[2]), float(a[3])))
		var dz := float(rp.get("deck_z", 11.6)) * PX_M
		for cp in [rr.position, Vector2(rr.get_center().x, rr.position.y), Vector2(rr.end.x, rr.position.y), rr.end,
				Vector2(rr.get_center().x, rr.end.y), Vector2(rr.position.x, rr.end.y)]:
			fix.append(_fx("deck", cp, dz, Vector2.ZERO, cp, 0.0))
	# LIGHT7-5 / LIGHT7-7 (13.9c-24d): 9 m area masts (a crossbar with two of the perimeter's flood luminaires) and wall-pack floods on a building face,
	# placed greedily inside what is left of the FIX_CAP budget once every other fixture stands (the doors, garages, roof lamps above are already in):
	# the darkest work cell the camera sees first, whichever candidate (a mast on the nearest free verge, or a wall-pack flood on the nearest camera-facing
	# face) lifts the most cells toward IL_MIN, until every cell has IL_MIN or the budget is spent. Nothing is trimmed afterwards, so the coverage is real.
	var work := _work_cells(g, C)
	var ws := []
	for p in work:
		ws.append(_iso(p))
	var lv := _work_lift(work, fix)
	var offs := []
	for dy in range(-10, 11):   # quarter-tile steps (a footing on a yard rim / kerb line sits 0.25 tile in), within 2.5 tiles
		for dx in range(-10, 11):
			if dx * dx + dy * dy <= 100:
				offs.append(Vector2(dx, dy) * 0.25)
	offs.sort_custom(func(a, b): return a.length_squared() < b.length_squared())
	var masts := []
	var skip := {}
	var nwf := 0
	for it in (MAX_MASTS + MAX_WALLF) * 4:
		if fix.size() >= FIX_CAP or (masts.size() >= MAX_MASTS and nwf >= MAX_WALLF):
			break
		var wi := -1
		var lo := IL_MIN
		for k in work.size():
			if lv[k] < lo and not skip.has(k):
				lo = lv[k]
				wi = k
		if wi < 0:
			break
		var M := {}
		if masts.size() < MAX_MASTS:
			for off in offs:
				var p: Vector2 = work[wi] + off
				if _verge_ok(g, C, p, poles + masts, Rect2(), 3.0, MAST_Z, true, false) and not _behind_bld(g, p, MAST_Z + 3.0):   # its head in view
					M = _fx("mast", p, MAST_Z, Vector2.ZERO, p, MAST_R)
					M.zv = 0.0   # the height up to which a building in front hides the shaft (0: the foot is in view)
					if _behind_bld(g, p, 2.0):
						var zl := 0.0
						var zh := MAST_Z
						for bi in 8:
							var zm := (zl + zh) * 0.5
							if _behind_bld(g, p, zm):
								zl = zm
							else:
								zh = zm
						M.zv = zh
					break
		var WF := {}
		if nwf < MAX_WALLF:
			WF = _wall_flood(g, work[wi])
		var gm := _lift_gain(M, ws, lv) if not M.is_empty() else -1.0
		var gw := _lift_gain(WF, ws, lv) if not WF.is_empty() else -1.0
		var pick := {}
		if gm >= gw and gm > 0.0:
			pick = M
			masts.append(M.at)
		elif gw > 0.0:
			pick = WF
			nwf += 1
		if pick.is_empty():   # nothing reaches this cell: it and its neighbours are left for the coverage test to report
			for k in work.size():
				if (work[k] as Vector2).distance_to(work[wi]) <= 1.0:
					skip[k] = true
			continue
		fix.append(pick)
		for e in _ilv(pick):
			for k in work.size():
				lv[k] += _ell_f(e, ws[k])
		if lv[wi] < IL_MIN:
			skip[wi] = true
	g.work = work
	g.work_lv = lv
	while fix.size() > FIX_CAP:   # LIGHT7-5: the fixture budget (test_light_count_bounded): drop the last-placed (least needed) masts
		var li := -1
		for i in fix.size():
			if String(fix[i].k) == "mast":
				li = i
		if li < 0:
			break
		fix.remove_at(li)
		g.mast_drop = int(g.get("mast_drop", 0)) + 1
	g.work_lv = _work_lift(work, fix)   # LIGHT7-7: the coverage of the fixtures actually fitted (the in-loop sums still counted masts trimmed above)
	for F in fix:
		F.hid = _behind_bld(g, F.at, float(F.z) + 2.0)
		if String(F.k) == "tower":
			F.hid = _hid(g, "s%d" % int(F.tw))
		if F.has("core"):   # outward floods: the wash and its hot core, both cut to the ground outside the wall
			if not F.has("wp"):   # a round flood (the tower searchlight): a circle on the ground
				F.wp = Vector2(float(F.r), 0.0)
				F.wq = Vector2(0.0, float(F.r) * 0.5)
				F.cp = Vector2(float(F.core_r), 0.0)
				F.cq = Vector2(0.0, float(F.core_r) * 0.5)
			var yin := bool(F.get("inside", false))
			F.P = _mk_pool_t(_iso(F.pool), F.wp, F.wq, sil, g.foot, yin)
			F.P2 = _mk_pool_t(_iso(F.core), F.cp, F.cq, sil, g.foot, yin)
		else:
			F.P = _mk_pool(_iso(F.pool), float(F.r), sil) if float(F.r) > 0.0 else {}
		if String(F.k) == "door" and not F.hid and int(F.f) < 2:   # a short wash down the facade under the lamp
			var at: Vector2 = F.at
			var along := Vector2(0, 1) if int(F.f) == 0 else Vector2(1, 0)
			var z := float(F.z)
			var w := PackedVector2Array([_iso(at) - Vector2(0, z - 0.5)])   # lamp at the top, a scallop down the wall
			for k in 7:
				var u := -1.0 + 2.0 * float(k) / 6.0
				w.append(_iso(at + along * 0.3 * u) - Vector2(0, (z - 0.5) * (0.45 + 0.25 * absf(u))))
			F.wash = w
	g.fix = fix
	# facade (window / door light) pools on the ground in front of each building's front corner
	var fp := []
	for zn in g.zones:
		if OPEN_ZONES.has(zn) or zn == "range" or not _has_art(zn) or _stacked(g, zn):
			continue
		var zr: Rect2 = (g.zones[zn] as Rect2).grow(-INSET)
		fp.append(_mk_pool(_iso(zr.end + Vector2(0.4, 0.4)), 30.0 + 10.0 * zr.size.x, sil))
	g.fpool = fp
	var ap := []
	for tc in g.towers:
		ap.append(_mk_pool(_iso(tc), 64.0, sil))
	g.apool = ap
	# flush pad lights a building / garage / tower / wall stands in front of: not drawn (they used to show on the
	# command centre's facade and the workshop roof as floating green dots)
	var eh := []
	for e in g.edge:
		eh.append(_ground_hid(g, e[0]))
	g.edge_hid = eh
	_plan_windows(g)   # LIGHT7-3: lit window panes on the multi-storey buildings
	_plan_bay(g)   # LIGHT7-4: the Suit Foundry's bay work lights


## LIGHT7-6: a wall-pack flood for work cell cp on the nearest camera-facing face of a drawn block (no deeper than 4 tiles, its bracket
## in view and on open ground in front of the face, not inside another block): {} when none fits.
func _wall_flood(g: Dictionary, cp: Vector2) -> Dictionary:
	var best := {}
	var bd := 1.0e9
	var hosts: Array = (_bld_boxes(g) as Array).duplicate()
	for ga in g.garages:   # a garage shed's face too (4.7 m)
		hosts.append([(ga[0] as Rect2).grow(-0.1), GARAGE_Z, 0.0, false])
	for b in hosts:
		if float(b[2]) > 0.0 or float(b[1]) < 4.0 * PX_M:
			continue
		var r: Rect2 = b[0]
		for nrm: Vector2 in [Vector2(1, 0), Vector2(0, 1)]:
			var ax := nrm.x > 0.0
			var d := (cp.x - r.end.x) if ax else (cp.y - r.end.y)
			var u := cp.y if ax else cp.x
			var u0 := (r.position.y if ax else r.position.x) + 0.35
			var u1 := (r.end.y if ax else r.end.x) - 0.35
			if d < 0.3 or d > 4.0 or u1 <= u0 or u < u0 - 2.0 or u > u1 + 2.0:
				continue
			var uc := clampf(u, u0, u1)
			var at := Vector2.INF
			var sc := 0.0
			for k in 13:   # along the face from the nearest point outward (half-tile steps): a stair core / annex in front moves it along
				var uk := uc + float((k + 1) / 2) * 0.5 * (1.0 if k % 2 == 1 else -1.0)
				if uk < u0 or uk > u1:
					continue
				var ak := Vector2(r.end.x + 0.04, uk) if ax else Vector2(uk, r.end.y + 0.04)
				var z0 := minf(float(b[1]) - 0.6 * PX_M, WALLF_Z)
				if _behind_bld(g, ak, z0 + 2.0) or _ground_hid(g, ak + nrm * 0.3):
					continue
				var inb := false
				for o in hosts:
					inb = inb or (o[0] as Rect2).has_point(ak + nrm * 0.3)
				if inb:
					continue
				at = ak
				sc = d + absf(u - uk)
				break
			if at == Vector2.INF or sc >= bd:
				continue
			var z := minf(float(b[1]) - 0.6 * PX_M, WALLF_Z)
			bd = sc
			var al := Vector2(nrm.y, nrm.x)
			var F := _fx("wallf", at, z, nrm, at + nrm * clampf(d, 1.2, 2.6) + al * clampf(u - (at.y if ax else at.x), -1.5, 1.5), 90.0)
			F.core = at + nrm * 0.9
			F.core_r = CORE_R
			F.wp = _ivec(al * WF_A)
			F.wq = _ivec(nrm * WF_B)
			F.cp = _ivec(al * WF_CA)
			F.cq = _ivec(nrm * WF_CB)
			F.lift = false
			F.inside = true
			F.head = F.hp - Vector2(0, 5.0)
			F.lens = F.hp + Vector2(1.5 if _aim_frame(nrm) == 0 else -0.5, -5.5)
			best = F
	return best


## A ground point is hidden when it falls inside a silhouette on screen (anything opaque in front of it).
func _ground_hid(g: Dictionary, p: Vector2) -> bool:
	var s := _iso(p) - Vector2(0, 1.5)
	for q in g.get("lsil", g.sil):   # LIGHT7-6: the drawn blocks
		if (q[1] as Rect2).has_point(s) and Geometry2D.is_point_in_polygon(s, q[0]):
			return true
	return false


## The fixtures themselves (opaque, over the entities; day and night): the g7_atmo7 luminaire sprites (flood, cobra-head pole
## arm, bulkhead, obstruction lamp, strobe, deck puck) on their mount points; poles get a shaft and a concrete footing.
## The tower searchlight head and the corner junction mast floodlights are in the wall / tower art itself.
## LIGHT7-5: the steady fixtures on fixo (redrawn on change, _static_sig) and every base lamp post / mast.
func _draw_fixo() -> void:
	counts["fixtures"] = 0
	_draw_base_fixtures()   # LIGHT7: base / Last Protocol lamp posts and masts
	for g in geo:
		if _vr.intersects(g.bbox):
			_draw_fixtures(g, false)


func _draw_fixtures(g: Dictionary, dyn := false) -> void:   # dyn: only the alarm strobes (over, 30 Hz); else every other fixture (fixo)
	var lit := false
	var a: Dictionary = _alarm.get(int(g.id), {})
	if float(a.get("lvl", 0.0)) > 0.0 and bool(a.get("red", false)):
		lit = true
	var ph := int(t * 5.0)
	var o: CanvasItem = over if dyn else fixo
	for F in g.get("fix", []):
		if F.hid or (String(F.k) == "alarm") != dyn:
			continue
		var hp: Vector2 = (F.hp as Vector2).round()
		match String(F.k):
			"wall", "wall_in", "gate", "yard", "wallf":   # a flood on its bracket: base plate on the battlement top / rail post / bastion cap / building face
				_sp("fx_flood", hp, _aim_frame(F.aim), 0, Color.WHITE, 1.0, o)
			"alarm":   # the red strobe on the battlement panel: dark lens by day, flashing in a lockdown / breach
				_sp("fx_strobe", hp, 1 if (lit and (int(F.i) + ph) % 4 < 2) else 0, 0, Color.WHITE, 1.0, o)
			"pole":
				var b: Vector2 = (F.base as Vector2).round()
				_sp("fx_plinth", b, 0, 0, Color.WHITE, 1.0, o)
				_wrect(o, Rect2(b.x - 1.0, hp.y, 1.0, b.y - hp.y), Color(0.50, 0.52, 0.53))   # shaft: lit left column
				_wrect(o, Rect2(b.x, hp.y, 1.0, b.y - hp.y), Color(0.15, 0.16, 0.19))         # shaded right column
				_sp("fx_pole", hp, _aim_frame(F.aim), 0, Color.WHITE, 1.0, o)
			"mast":   # LIGHT7-5: a 9 m area mast: footing, shaft, crossbar, two of the perimeter's flood luminaires (as the base masts)
				var mb: Vector2 = (F.base as Vector2).round()
				var zv := float(F.get("zv", 0.0))
				if zv <= 0.0:
					_sp("fx_plinth", mb, 0, 0, Color.WHITE, 1.0, o)
				var sb := mb.y - roundf(zv)   # the shaft only above what hides its foot
				_wrect(o, Rect2(mb.x - 1.0, hp.y, 1.0, sb - hp.y), Color(0.50, 0.52, 0.53))
				_wrect(o, Rect2(mb.x, hp.y, 1.0, sb - hp.y), Color(0.15, 0.16, 0.19))
				_wrect(o, Rect2(hp.x - 5.0, hp.y, 10.0, 1.0), Color(0.33, 0.36, 0.40))
				_sp("fx_flood", hp + Vector2(-4, 0), 1, 0, Color.WHITE, 1.0, o)
				_sp("fx_flood", hp + Vector2(4, 0), 0, 0, Color.WHITE, 1.0, o)
			"door":
				if int(F.f) < 2:
					_sp("fx_bulk", hp, int(F.f), 0, Color.WHITE, 1.0, o)
			"obst":
				_sp("fx_obst", hp, 0, 0, Color.WHITE, 1.0, o)
			"deck":
				_sp("fx_puck", hp + Vector2(0, 1), 0, 0, Color.WHITE, 1.0, o)
	if not dyn:
		counts["fixtures"] = int(counts.get("fixtures", 0)) + (g.get("fix", []) as Array).size()


## Flush pad / helipad perimeter lights: their housings on the ground layer.
func _draw_flush(g: Dictionary) -> void:
	for e in g.edge:
		var gp := _iso(e[0])
		_sp("fx_puck", gp.round() + Vector2(0, 1), 0, 0, Color.WHITE, 1.0, self)


## The lit side of every fixture at night / dusk (lenses, pools, wall washes). red_search: the lockdown searchlights
## are sweeping, so the parked tower floods are off.
func _glow_fixtures(g: Dictionary, n: float, red_search: bool) -> void:
	for F in g.fix:
		var hd: Vector2 = F.head
		var hp: Vector2 = (F.hp as Vector2).round()
		match String(F.k):
			"wall", "wall_in", "gate":
				if F.has("core"):   # 13.9c-24b: a bright wide wash (soft falloff) and a hot core by the wall foot
					_draw_pool(F.P, Color(CT_AREA, (0.26 if F.lift else WASH_ADD) * n))
					_draw_pool(F.P2, Color(CT_AREA, (0.26 if F.lift else CORE_ADD) * n))
				else:
					_draw_pool(F.P, Color(CT_AREA, 0.36 * n))
				if not F.hid and _aim_frame(F.aim) < 2:   # the lens faces the camera: lit lens + a bloom on the housing
					var lp: Vector2 = hp + (F.lens as Vector2) - (F.hp as Vector2)
					_dot(lp, 1.8, Color(CT_AREA, 0.98 * n))
					_dot(lp, 8.0, Color(CT_AREA, 0.30 * n))
			"yard", "wallf":   # LIGHT7-4 (13.9c-24d): the inward flood on the inner rail post (LIGHT7-6: or a building face): a wide wash along the wall foot inside and a hot core
				_draw_pool(F.P, Color(CT_AREA, YARD_ADD * n))   # LIGHT7-5: the tint is lifted under it as well (IY_WASH / IY_CORE)
				_draw_pool(F.P2, Color(CT_AREA, YARD_CADD * n))
				if not F.hid and _aim_frame(F.aim) < 2:
					var yl: Vector2 = hp + (F.lens as Vector2) - (F.hp as Vector2)
					_dot(yl, 1.8, Color(CT_AREA, 0.98 * n))
					_dot(yl, 8.0, Color(CT_AREA, 0.30 * n))
			"corner":   # the junction mast floodlight in the wall art (lens pixels on its +x and +y faces)
				_draw_pool(F.P, Color(CT_AREA, 0.32 * n))
				if not F.hid:
					for lo in [Vector2(0.07, 0.0), Vector2(0.0, 0.05)]:
						var cp := (_iso((F.at as Vector2) + lo) - Vector2(0, float(F.z))).round()
						_dot(cp, 1.6, Color(CT_AREA, 0.95 * n))
						_dot(cp, 5.0, Color(CT_AREA, 0.18 * n))
			"walk":   # the art's walkway lamp under the inner deck edge: a small lit pool at the foot of the wall
				_draw_pool(F.P, Color(CT_AREA, 0.26 * n))
				if not F.hid:
					var wp := (_iso(F.at) - Vector2(0, float(F.z))).round()
					_dot(wp, 1.5, Color(CT_AREA, 0.9 * n))
					_dot(wp, 4.5, Color(CT_AREA, 0.18 * n))
			"tower":
				if red_search:
					continue
				_draw_pool(F.P, Color(CT_AREA, (0.26 if F.lift else WASH_ADD) * n))
				_draw_pool(F.P2, Color(CT_AREA, (0.26 if F.lift else CORE_ADD) * n))
				if not F.hid:
					_dot(hd, 2.4, Color(CT_AREA, 0.95 * n))
					_dot(hd, 9.0, Color(CT_AREA, 0.28 * n))
			"pole":
				_draw_pool(F.P, Color(CT_AREA, POLE_A * n))
				_dot(hd + Vector2(0, 3.0), 1.8, Color(CT_AREA, 0.95 * n))
				_dot(hd + Vector2(0, 3.5), 7.0, Color(CT_AREA, 0.20 * n))
			"mast":   # LIGHT7-5: the area mast's two flood lenses and its wide pool (the tint is lifted under it too, IL_MAST)
				_draw_pool(F.P, Color(CT_AREA, MAST_ADD * n))
				if not F.hid:
					for lo in [Vector2(-4.5, -5.5), Vector2(5.5, -5.5)]:
						_dot(hp + lo, 1.8, Color(CT_AREA, 0.98 * n))
						_dot(hp + lo, 7.0, Color(CT_AREA, 0.28 * n))
			"door":
				_draw_pool(F.P, Color(CT_DOOR, 0.50 * n))
				if not F.hid and int(F.f) < 2:
					_dot(hp + Vector2(0, -2.0), 1.8, Color(CT_DOOR, 0.95 * n))
					_dot(hp + Vector2(0, -1.5), 5.0, Color(CT_DOOR, 0.28 * n))
					if F.has("wash"):
						var wc := PackedColorArray([Color(CT_DOOR, 0.22 * n)])
						for k in 7:
							wc.append(Color(CT_DOOR, 0.0))
						_gpoly(F.wash, wc)
			"obst":
				if not F.hid:
					_dot(hp - Vector2(-1.5, 4.0), 1.6, Color(CT_RED, 0.95 * n))
					_dot(hp - Vector2(1.5, 4.0), 1.6, Color(CT_RED, 0.95 * n))
					_dot(hp - Vector2(0, 4.0), 5.0, Color(CT_RED, 0.30 * n))
			"deck":
				if not F.hid:
					_dot(hp + Vector2(0, 0.5), 1.6, Color(CT_PAD, 0.85 * n))
		counts["lights"] = int(counts.get("lights", 0)) + 1


# =============================================================== LIGHT7-4: Suit Foundry bay work lights (owner 13.9c-24a)
## The Suit Foundry's open bay (the door up) at night: its wall strip / header strip / gantry downlights are drawn in the art (tools/art/
## g7_fac7f.gd armory() / _sf_bay(), read from its code, metres from the zone centre rotated by the drawn door side), the multiply tint
## leaves them as dark as the rest, so this adds what they would throw: a lit back wall washed by its light strip, a lit side wall, the
## epoxy floor pooled under the header strip and the wall strip, the strips and header lamps glowing, and warm pools on the apron and
## under each gantry downlight. Everything is light on the open bay and the ground: the interior surfaces are cut to the opening's own
## screen quad (what the camera can see through the door: no light on the facade, the jambs or the roof) and the ground pools to the
## ground outside the hall's silhouette. No translucent volume over the building (13.9c-18). Off with the bay door down (lockdown).
const BAY_W := Color(1.0, 0.92, 0.76)   # 4000 K work light, a touch warm: never pure white
const BAY_POOL := Color(1.0, 0.85, 0.60)   # the same light on the concrete: a warm pool
const BAY_CELLS := Vector2i(6, 5)
const BAY_LIFT := 0.70                  # how far the night tint is lifted toward white inside the lit bay opening (x night amount)


func _lp(ctr: Vector2, f: int, x: float, y: float, z: float) -> Vector2:
	return _iso(ctr + _lrot(f, Vector2(x, y)) / 4.0) - Vector2(0, z * PX_M)


## armory() / _sf_bay() dimensions (metres, local frame): the opening (dn..ds at x = xf, dhz high), the back wall xb, the gantry's downlights.
static func _bay_dims(ex: float, ey: float) -> Dictionary:
	var xf := ex - 3.4
	var yn := -ey + 0.2
	var yw := ey * 0.375
	var dhw := minf(3.2, (yw - yn) * 0.5 - 1.6)
	var dy0 := -ey * 0.5
	var lx := ex - 0.4
	return {"xf": xf, "xb": xf - 4.4, "dy0": dy0, "dn": dy0 - dhw, "ds": dy0 + dhw, "dhz": 7.2, "hz": 11.6, "zt": 0.13,
		"bx": xf + 0.6 + (lx - xf - 0.6) * 0.6, "gz": 8.6}


## Intensity (0..1) of the back wall at (y, z): a wall-washer glow round its light strip (z 3.2) over a soft fill, darker toward the corners.
static func _bay_back(y: float, z: float, D: Dictionary) -> float:
	var ky := (y - (float(D.dn) + float(D.ds)) * 0.5) / ((float(D.ds) - float(D.dn)) * 0.5)
	var strip := exp(-pow((z - 3.2) / 1.25, 2.0))
	var fill := 0.05 * (1.0 - 0.45 * z / float(D.dhz))
	return clampf((fill + 0.30 * strip) * (1.0 - 0.38 * ky * ky), 0.0, 0.9)


## The side (north) wall at (x, z): lit by the header strip at its door end (high) and by the wall strip at its back end.
static func _bay_side(x: float, z: float, D: Dictionary) -> float:
	var a := 0.03 + 0.20 * exp(-pow((x - (float(D.xf) - 0.3)) / 2.2, 2.0)) * exp(-pow((z - (float(D.dhz) - 0.9)) / 2.8, 2.0))
	a += 0.20 * exp(-pow((x - (float(D.xb) + 0.25)) / 1.3, 2.0)) * exp(-pow((z - 3.2) / 1.7, 2.0))
	return clampf(a, 0.0, 0.9)


## The bay floor at (x, y): pooled under the header strip (door end) and in front of the back-wall strip, fading toward the side walls.
static func _bay_floor(x: float, y: float, D: Dictionary) -> float:
	var ky := (y - (float(D.dn) + float(D.ds)) * 0.5) / ((float(D.ds) - float(D.dn)) * 0.5)
	var a := 0.04 + 0.26 * exp(-pow((x - (float(D.xf) - 1.5)) / 1.9, 2.0)) + 0.16 * exp(-pow((x - (float(D.xb) + 1.3)) / 1.3, 2.0))
	return clampf(a * (1.0 - 0.34 * ky * ky), 0.0, 0.9)


## One lit surface of the bay: the plane's screen frame (origin A, edge vectors U / V for u / v 0..1) cut into cells, each cut to the
## opening quad; per-vertex intensity from fn(u, v). Returns {polys, al}.
func _bay_surface(A: Vector2, U: Vector2, V: Vector2, open: PackedVector2Array, fn: Callable) -> Dictionary:
	var polys := []
	var al := []
	var det := U.x * V.y - U.y * V.x
	if absf(det) < 0.01:
		return {"polys": polys, "al": al}
	for i in BAY_CELLS.x:
		for j in BAY_CELLS.y:
			var u0 := float(i) / float(BAY_CELLS.x)
			var u1 := float(i + 1) / float(BAY_CELLS.x)
			var v0 := float(j) / float(BAY_CELLS.y)
			var v1 := float(j + 1) / float(BAY_CELLS.y)
			var cell := PackedVector2Array([A + U * u0 + V * v0, A + U * u1 + V * v0, A + U * u1 + V * v1, A + U * u0 + V * v1])
			for p in Geometry2D.intersect_polygons(cell, open):
				if (p as PackedVector2Array).size() < 3 or Geometry2D.triangulate_polygon(p).is_empty():
					continue
				var a := PackedFloat32Array()
				for v in p:
					var d: Vector2 = v - A
					a.append(float(fn.call((d.x * V.y - d.y * V.x) / det, (U.x * d.y - U.y * d.x) / det)))
				polys.append(p)
				al.append(a)
	return {"polys": polys, "al": al}


func _plan_bay(g: Dictionary) -> void:
	g.erase("bay")
	if not (g.zones as Dictionary).has("armory") or not _has_art("armory"):
		return
	var F: Dictionary = g.F
	var fcs: Dictionary = F.get("faces", {})
	var arr: Array = F.zones["armory"]
	var zr: Rect2 = g.zones["armory"]
	var f := int(fcs["armory"]) if fcs.has("armory") else EntityLayer.door_side_of(arr, F)
	var dnl := _lrot(f, Vector2(1, 0))
	if dnl.x < 0.5 and dnl.y < 0.5:   # the bay door faces away from the camera
		return
	var ex := (zr.size.x if f % 2 == 0 else zr.size.y) * 2.0
	var ey := (zr.size.y if f % 2 == 0 else zr.size.x) * 2.0
	var ctr := zr.get_center()
	var D := _bay_dims(ex, ey)
	var xf := float(D.xf)
	var xb := float(D.xb)
	var dn := float(D.dn)
	var ds := float(D.ds)
	var dy0 := float(D.dy0)
	var dhz := float(D.dhz)
	var zt := float(D.zt)
	# the hall's own silhouette replaces the whole-zone one (the zone rect includes the open test apron the ground pools fall on)
	var c0 := ctr + _lrot(f, Vector2(-ex, -ey)) / 4.0
	var c1 := ctr + _lrot(f, Vector2(xf, ey)) / 4.0
	var hall := Rect2(Vector2(minf(c0.x, c1.x), minf(c0.y, c1.y)), (c1 - c0).abs())
	var bs: Array = g.get("lsil", [])   # LIGHT7-6: the drawn blocks (the Suit Foundry's own hall / annex / wing leave its test apron open)
	if bs.is_empty():
		for i in (g.occ as Array).size():
			if (g.occ[i][0] as Rect2).is_equal_approx(zr):
				bs.append(_sil(hall, float(g.occ[i][1])))
			else:
				bs.append(g.sil[i])
	var open := PackedVector2Array([_lp(ctr, f, xf, dn, 0.0), _lp(ctr, f, xf, ds, 0.0), _lp(ctr, f, xf, ds, dhz), _lp(ctr, f, xf, dn, dhz)])
	var surf := []
	# back wall (x = xb): u along y dn..ds, v up 0..dhz
	var A := _lp(ctr, f, xb, dn, 0.0)
	var S1 := _bay_surface(A, _lp(ctr, f, xb, ds, 0.0) - A, _lp(ctr, f, xb, dn, dhz) - A, open, func(u: float, v: float) -> float:
		return _bay_back(dn + u * (ds - dn), v * dhz, D))
	S1.col = BAY_W
	surf.append(S1)
	# side wall (y = dn, facing into the bay): u along x xb..xf, v up
	var S2 := _bay_surface(A, _lp(ctr, f, xf, dn, 0.0) - A, _lp(ctr, f, xb, dn, dhz) - A, open, func(u: float, v: float) -> float:
		return _bay_side(xb + u * (xf - xb), v * dhz, D))
	S2.col = BAY_W
	surf.append(S2)
	# floor (z = zt): u along x, v along y
	var A3 := _lp(ctr, f, xb, dn, zt)
	var S3 := _bay_surface(A3, _lp(ctr, f, xf, dn, zt) - A3, _lp(ctr, f, xb, ds, zt) - A3, open, func(u: float, v: float) -> float:
		return _bay_floor(xb + u * (xf - xb), dn + v * (ds - dn), D))
	S3.col = BAY_W
	surf.append(S3)
	# the wall strip (z 3.2 on the back wall: a thin hot line and a soft halo) and the header strip's six lamps
	var strips := []
	var sy0 := dn + 0.2
	var sy1 := ds - 0.2
	for band in [[3.14, 3.26, 1.0, 1.0], [2.4, 3.2, 0.0, 0.22], [3.2, 4.0, 0.22, 0.0]]:
		var q := PackedVector2Array([_lp(ctr, f, xb, sy0, float(band[0])), _lp(ctr, f, xb, sy1, float(band[0])), _lp(ctr, f, xb, sy1, float(band[1])), _lp(ctr, f, xb, sy0, float(band[1]))])
		var ymid := (q[0].y + q[3].y) * 0.5
		for p in Geometry2D.intersect_polygons(q, open):
			if (p as PackedVector2Array).size() >= 3 and not Geometry2D.triangulate_polygon(p).is_empty():
				var a := PackedFloat32Array()
				for v in p:   # vertices on the band's lower edge take its first alpha, on its upper edge the second
					a.append(float(band[3]) if v.y < ymid else float(band[2]))
				strips.append({"poly": p, "al": a})
	var lamps := []
	for k in 6:
		lamps.append(_lp(ctr, f, xf - 0.1, dn + 0.5 + float(k) * (ds - dn - 1.0) / 5.0, dhz - 0.06))
	# the gantry's two downlights (fixtures on its bridge girder, 8.8 m) and the pools they throw on the apron, plus the bay's spill out of the door
	var bx := float(D.bx)
	var gl := []
	var pools := []
	var rx := _lrot(f, Vector2(1, 0)) / 4.0
	var ry := _lrot(f, Vector2(0, 1)) / 4.0
	for s in [-1.0, 1.0]:
		var gy := dy0 + float(s) * 1.9
		gl.append(_lp(ctr, f, bx, gy, float(D.gz) + 0.12))
		pools.append({"P": _mk_pool_t(_lp(ctr, f, bx, gy, 0.0), _ivec(rx * 2.6), _ivec(ry * 2.6), bs), "a": 0.50})
	pools.append({"P": _mk_pool_t(_lp(ctr, f, xf + 1.6, dy0, 0.0), _ivec(rx * 3.4), _ivec(ry * 4.8), bs), "a": 0.42})
	var hid := []   # a gantry lamp a silhouette in front of it hides (the hall itself and every building behind the portal are not counted)
	for k in gl.size():
		var gt := ctr + _lrot(f, Vector2(bx, dy0 + (-1.9 if k == 0 else 1.9))) / 4.0
		var hd := false
		for i in (g.sil as Array).size():
			var q: Array = g.sil[i]
			var r: Rect2 = g.occ[i][0]
			if r.is_equal_approx(zr) or gt.x >= r.end.x or gt.y >= r.end.y:
				continue
			if (q[1] as Rect2).has_point(gl[k]) and Geometry2D.is_point_in_polygon(gl[k], q[0]):
				hd = true
		hid.append(hd)
	g.bay = {"open": open, "surf": surf, "strips": strips, "lamps": lamps, "gl": gl, "gl_hid": hid, "pools": pools}


func _glow_bay(g: Dictionary, n: float) -> void:
	if not g.has("bay") or int(counts.get("lights", 0)) >= LIGHT_CAP:
		return
	var B: Dictionary = g.bay
	if not bool(g.F.lock):   # the bay door is up: its inside is lit
		for S in B.surf:
			for pi in (S.polys as Array).size():
				var cols := PackedColorArray()
				for a in S.al[pi]:
					cols.append(Color(S.col, float(a) * n))
				_gpoly(S.polys[pi], cols)
		for st in B.strips:
			var cs := PackedColorArray()
			for a in st.al:
				cs.append(Color(BAY_W, float(a) * n))
			_gpoly(st.poly, cs)
		for L in B.lamps:
			_dot(L, 1.7, Color(BAY_W, 0.95 * n))
			_dot(L, 5.5, Color(BAY_W, 0.30 * n))
		counts["bay"] = int(counts.get("bay", 0)) + 1
	for i in (B.gl as Array).size():
		if not bool(B.gl_hid[i]):
			_dot(B.gl[i], 1.8, Color(BAY_W, 0.95 * n))
			_dot(B.gl[i], 6.5, Color(BAY_W, 0.30 * n))
	for pl in B.pools:
		_draw_pool(pl.P, Color(BAY_POOL, float(pl.a) * n))
	counts["lights"] = int(counts.get("lights", 0)) + 1


# =============================================================== LIGHT7-3: lit window panes (owner 13.9c-24a)
## The multi-storey buildings' windows light up at night: one OPAQUE pane per drawn window cell, aligned to the window grid
## of the FACB7 art generators (tools/art/g7_fac7f.gd: planning ribbons + ops crown, workshop's drone-bay storey ribbon,
## barracks armour slots, armory clerestory / wing windows), read from their code (metres from the zone centre, rotated by the
## building's drawn door side), only on the faces the camera sees (+x / +y after the rotation). 3000 K warm and 5000 K cool
## panes, some left dark, a few flickering like a screen. Drawn after the multiply tint (so they read self-lit) and cut by
## every silhouette in front of them (wall, tower, neighbouring building): never over another building. Off in a lockdown
## (the art closes its armour shutters).
const WIN_ON := 0.3                   # night amount where the panes start to come on
const WIN_GAP := 0.07                 # mullion between ribbon cells (fraction of a cell, each side)
const WIN_WARM := Color(1.0, 0.74, 0.40)      # 3000 K rooms
const WIN_COOL := Color(0.58, 0.78, 0.96)     # 5000 K rooms (never pure white)
const WIN_SCREEN := Color(0.36, 0.64, 0.94)   # a monitor glow
const WIN_CREAM := Color(1.0, 0.92, 0.78)     # a ceiling strip light tube
const WIN_GLASS := Color(0.133, 0.22, 0.28)   # the art glass (34, 56, 72)
const WIN_FRAME := Color(0.16, 0.18, 0.20)    # frame / mullion steel
const WIN_ZONES := ["planning", "workshop", "barracks", "armory"]
const _NL := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]


## Art-local metres (x, y) -> rotated by the building's drawn door side (f 0 +x, 1 +y, 2 -x, 3 -y), as tools/art M.pose does.
static func _lrot(f: int, p: Vector2) -> Vector2:
	match f:
		1:
			return Vector2(-p.y, p.x)
		2:
			return -p
		3:
			return Vector2(p.y, -p.x)
	return p


static func _h3(a: int, b: int, c: int) -> float:
	return float(absi(hash(Vector3i(a, b, c))) % 10000) / 10000.0


## A flat band of window cells on a face: a -> b along the face (local x, y metres), z0..z1 metres, n cells.
static func _wb(a: Vector2, b: Vector2, z0: float, z1: float, nl: Vector2, n: int, lit: float, cool: float, id: int) -> Dictionary:
	return {"b0": Vector3(a.x, a.y, z0), "b1": Vector3(b.x, b.y, z0), "t0": Vector3(a.x, a.y, z1), "t1": Vector3(b.x, b.y, z1),
		"nl": nl, "n": n, "lit": lit, "cool": cool, "id": id, "v0": 0.0, "v1": 1.0, "dim": 0.42}


## The window grid of a zone building in its art's local frame (zone centre origin, door on local +x), half extents ex / ey (m).
## Each entry mirrors one drawing call in tools/art/g7_fac7f.gd (named in the comment); nothing is guessed.
static func _win_bands(zn: String, ex: float, ey: float) -> Array:
	var out := []
	match zn:
		"planning":   # planning(): floors 2 + 3 ribbons (_ribbon z fz+0.9..fz+2.9 on the cantilevered block) + the ops crown's slanted glass
			var cx := -1.2
			var hx := minf(ex - 2.2, 5.8)
			var hy := minf(ey - 1.2, 4.8)
			var ux := hx + 0.5
			var uy := minf(hy + 0.5, ey - 0.6)
			for fl in 2:
				var z0 := 4.2 + float(fl) * 3.6 + 0.9
				for ni in 4:
					var nl: Vector2 = _NL[ni]
					var xf := absf(nl.x) > 0.5
					var ln := (uy if xf else ux) * 2.0 - 1.0   # _ribbon length: face length - 1.0
					var h := ln * 0.5 - 0.05                    # its glass quad half length
					var a := Vector2(cx + nl.x * ux, -h) if xf else Vector2(cx - h, nl.y * uy)
					var b := Vector2(cx + nl.x * ux, h) if xf else Vector2(cx + h, nl.y * uy)
					out.append(_wb(a, b, z0, z0 + 2.0, nl, maxi(1, int(ln / 1.4)), 0.80 if fl == 1 else 0.66, 0.5, fl * 4 + ni))
			var bh := Vector2(ux - 0.3, uy - 0.3)
			var th := Vector2(minf(ux + 0.7, ex - 1.6), minf(uy + 0.5, ey - 0.3))
			var cr := [Vector2(-bh.x, -bh.y), Vector2(bh.x, -bh.y), Vector2(bh.x, bh.y), Vector2(-bh.x, bh.y)]
			var ct := [Vector2(-th.x, -th.y), Vector2(th.x, -th.y), Vector2(th.x, th.y), Vector2(-th.x, th.y)]
			var cn := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
			for i in 4:   # _slant_glass(c + cr[i], c + cr[k], c + ct[i], c + ct[k]): glass v 0.08..0.9 between the mullions
				var k := (i + 1) % 4
				var cb0: Vector2 = cr[i]
				var cb1: Vector2 = cr[k]
				var ct0: Vector2 = ct[i]
				var ct1: Vector2 = ct[k]
				out.append({"b0": Vector3(cx + cb0.x, cb0.y, 11.4), "b1": Vector3(cx + cb1.x, cb1.y, 11.4),
					"t0": Vector3(cx + ct0.x, ct0.y, 15.2), "t1": Vector3(cx + ct1.x, ct1.y, 15.2),
					"nl": cn[i], "n": maxi(2, int(cb0.distance_to(cb1) / 1.5)), "lit": 0.95, "cool": 0.7, "id": 10 + i, "dim": 0.2, "v0": 0.13, "v1": 0.86})
		"workshop":   # workshop() + _dronebay_storey(): the drone-ops ribbon at z 7.4..8.8 on every face (the stair core clips -x)
			var hx := minf((2.0 * ex - 8.6) * 0.5, 8.0)
			var cx := -ex + 3.4 + hx
			var hy := minf(ey - 3.0, 9.5)
			var z0 := 6.5
			for ni in 4:
				var nl: Vector2 = _NL[ni]
				var xf := absf(nl.x) > 0.5
				var hl := hy if xf else hx
				var u0 := -hl + 0.5
				var u1 := hl - 0.5
				if ni == 2:   # -x: the stair core (centre y -hy + 0.85, half 0.95) stands against this face's -y end
					u0 = maxf(u0, -hy + 0.85 + 0.95)
				var ln := (u1 - u0) - 0.6
				var uc := (u0 + u1) * 0.5
				var h := ln * 0.5 - 0.05
				var a := Vector2(cx + nl.x * hx, uc - h) if xf else Vector2(cx + uc - h, nl.y * hy)
				var b := Vector2(cx + nl.x * hx, uc + h) if xf else Vector2(cx + uc + h, nl.y * hy)
				out.append(_wb(a, b, z0 + 0.9, z0 + 2.3, nl, maxi(1, int(ln / 1.4)), 0.72, 0.55, ni))
		"barracks":   # barracks(): floors 2 + 3, an armoured window slot (0.22 x 1.76 m) every ~1.25 m at z fz + 1.85
			var x0 := -ex + 0.4
			var x1 := ex - 2.0
			var y0 := -ey + 0.3
			var y1 := ey - 0.3
			var cx := (x0 + x1) * 0.5
			var cy := (y0 + y1) * 0.5
			var ux := (x1 - x0) * 0.5 + 0.25
			var uy := (y1 - y0) * 0.5 + 0.25
			for fl in 2:
				var fz := 3.6 + float(fl) * 3.6
				for ni in 4:
					var nl: Vector2 = _NL[ni]
					var xf := absf(nl.x) > 0.5
					var ln := (uy if xf else ux) * 2.0
					var nw := int(ln / 1.25)
					for k in nw:
						var u := -ln * 0.5 + (float(k) + 0.5) * ln / float(nw)
						var a := Vector2(cx + nl.x * ux, cy + u - 0.11) if xf else Vector2(cx + u - 0.11, cy + nl.y * uy)
						var b := Vector2(cx + nl.x * ux, cy + u + 0.11) if xf else Vector2(cx + u + 0.11, cy + nl.y * uy)
						out.append(_wb(a, b, fz + 0.97, fz + 2.73, nl, 1, 0.56, 0.3, (fl * 4 + ni) * 64 + k))
		"armory":   # armory() (FACB7-7 layout): the issue wing's RO.window panes, 0.9 m wide, centred z 2.6: one on the +x face, two on +y
			var x0 := -ex + 0.3
			var xf := ex - 3.4
			var yw := ey * 0.375
			var ye := ey - 0.1
			var xa := x0 + 4.6
			# (the wing's +x window at (xf, yw + 1.1) sits behind the bay's gantry frame in the art: no pane over it)
			for k in 2:
				var wx := xa + 1.4 + float(k) * 2.6
				out.append(_wb(Vector2(wx - 0.45, ye), Vector2(wx + 0.45, ye), 2.25, 2.95, _NL[1], 1, 0.8, 0.2, 1 + k))
	return out


## Plan every pane of a facility (static): screen polygons already cut by what stands in front.
func _plan_windows(g: Dictionary) -> void:
	var F: Dictionary = g.F
	var fcs: Dictionary = F.get("faces", {})
	var panes := []
	var zi := 0
	for zn in WIN_ZONES:
		zi += 1
		if not (g.zones as Dictionary).has(zn) or not _has_art(zn):
			continue
		if zn == "workshop" and not _stacked(g, "drone_bay"):
			continue
		var arr: Array = F.zones[zn]
		var zr: Rect2 = g.zones[zn]
		var f := int(fcs[zn]) if fcs.has(zn) else EntityLayer.door_side_of(arr, F)
		var ex := (zr.size.x if f % 2 == 0 else zr.size.y) * 2.0
		var ey := (zr.size.y if f % 2 == 0 else zr.size.x) * 2.0
		var ctr := zr.get_center()
		for bd in _win_bands(zn, ex, ey):
			var wn := _lrot(f, bd.nl)
			if wn.x < 0.5 and wn.y < 0.5:   # a face turned away from the camera
				continue
			var at: Vector2 = ctr + _lrot(f, Vector2(bd.b0.x, bd.b0.y)) / 4.0
			var sils := []
			for i in (g.occ as Array).size():   # everything in front of this face
				var r: Rect2 = g.occ[i][0]
				if at.x >= r.end.x or at.y >= r.end.y or r.is_equal_approx(zr):   # in front of the face, or the building itself
					continue
				sils.append(g.sil[i])
			var n: int = bd.n
			var gap := WIN_GAP if n > 1 else 0.0
			for k in n:
				var u0 := (float(k) + gap) / float(n)
				var u1 := (float(k + 1) - gap) / float(n)
				var q := PackedVector2Array()
				for uv in [[u0, bd.v0], [u1, bd.v0], [u1, bd.v1], [u0, bd.v1]]:
					var p3: Vector3 = (bd.b0 as Vector3).lerp(bd.b1, uv[0]).lerp((bd.t0 as Vector3).lerp(bd.t1, uv[0]), uv[1])
					q.append(_iso(ctr + _lrot(f, Vector2(p3.x, p3.y)) / 4.0) - Vector2(0, p3.z * PX_M))
				var bb := _bb(q)
				var polys: Array = _clip(q, sils)
				if polys.is_empty():
					continue
				var h := _h3(int(g.id), zi * 4096 + int(bd.id), k)
				var h2 := _h3(int(g.id) + 7, zi * 4096 + int(bd.id), k + 31)
				var h3 := _h3(int(g.id) + 13, zi * 4096 + int(bd.id), k + 57)
				var h4 := _h3(int(g.id) + 19, zi * 4096 + int(bd.id), k + 83)
				var lit: float = bd.lit
				var kind := 0   # 0 dark, 1 dim room, 2 lit room, 3 a screen glowing in a dark room
				if h < lit:
					kind = 3 if h < lit * 0.08 else (1 if h < lit * float(bd.dim) else 2)
				var wpx := absf(q[1].x - q[0].x)
				var hpx := absf(q[3].y - q[0].y)
				var vari := 0 if h3 < 0.38 else (1 if h3 < 0.58 else (2 if h3 < 0.72 else (3 if h3 < 0.9 else 4)))   # plain / half-drawn blinds / partition / desk + monitor / a silhouette
				if wpx < 9.0 or kind == 3:
					vari = 0
				elif kind == 1 and vari > 2:
					vari = 1
				var full := polys.size() == 1 and absf(_poly_area(polys[0]) - _poly_area(q)) < 0.6
				panes.append({"zn": zn, "zr": zr, "polys": polys, "bb": bb, "kind": kind, "vari": vari, "full": full,
					"tone": WIN_COOL if h2 < float(bd.cool) else WIN_WARM, "I": (0.66 + 0.26 * h4) if kind == 2 else (0.28 + 0.16 * h4),
					"ph": h2, "p1": h4, "p2": h3, "bl": q[0], "br": q[1], "tr": q[2], "tl": q[3], "wpx": wpx, "hpx": hpx,
					"y0": bb.position.y, "y1": bb.end.y})
	g.win = panes
	var wb := Rect2()
	for i in panes.size():
		wb = (panes[i].bb as Rect2) if i == 0 else wb.merge(panes[i].bb)
	g.wbb = wb.grow(48.0)   # LIGHT7-4: the pane area (a unit whose sprite reaches it can overdraw / be overdrawn)


## The multiply tint colour at the current night amount (the dark node and the dark panes share it).
func _tint() -> Color:
	return Color.WHITE.lerp(DUSK, clampf(night * 2.0, 0.0, 1.0)) if night <= 0.5 else DUSK.lerp(NIGHT, (night - 0.5) * 2.0)


func _flick(ph: float) -> float:
	var a := 0.5 + 0.5 * sin(t * (4.0 + 5.0 * ph) + ph * 40.0)
	var b := 0.5 + 0.5 * sin(t * 13.0 + ph * 91.0)
	return clampf(0.45 + 0.35 * a + 0.2 * b * b, 0.3, 1.0)


static func _poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].x * p[(i + 1) % p.size()].y - p[(i + 1) % p.size()].x * p[i].y
	return absf(a) * 0.5


## A point of a pane in its own frame: u along the window, v up it (0..1 each).
static func _pq(P: Dictionary, u: float, v: float) -> Vector2:
	return (P.bl as Vector2).lerp(P.br, u).lerp((P.tl as Vector2).lerp(P.tr, u), v)


var _cur_cut: Array = []   # LIGHT7-4: the unit sprite rects [[poly, bbox]] cut out of the pane being drawn (empty: draw it whole)


## A flat or vertically graded sub-rectangle (u0..u1, v0..v1) of a pane (LIGHT7-4: minus the sprites of units standing in front of it).
func _wr(P: Dictionary, u0: float, v0: float, u1: float, v1: float, cb: Color, ct: Color) -> void:
	var q := PackedVector2Array([_pq(P, u0, v0), _pq(P, u1, v0), _pq(P, u1, v1), _pq(P, u0, v1)])
	if _cur_cut.is_empty():
		_wc.draw_polygon(q, PackedColorArray([cb, cb, ct, ct]))
		return
	var U: Vector2 = (P.br as Vector2) - (P.bl as Vector2)
	var V: Vector2 = (P.tl as Vector2) - (P.bl as Vector2)
	var det := U.x * V.y - U.y * V.x
	for pc in _clip(q, _cur_cut):
		var cols := PackedColorArray()
		for v in pc:
			var d: Vector2 = v - (P.bl as Vector2)
			var vv := clampf(((U.x * d.y - U.y * d.x) / det - v0) / maxf(v1 - v0, 0.0001), 0.0, 1.0) if absf(det) > 0.01 else 0.5
			cols.append(cb.lerp(ct, vv))
		_wc.draw_polygon(pc, cols)


## A flat polygon drawn like _wr (clipped by the cut units).
func _wpoly(pts: PackedVector2Array, col: Color) -> void:
	if _cur_cut.is_empty():
		_wc.draw_colored_polygon(pts, col)
		return
	for pc in _clip(pts, _cur_cut):
		_wc.draw_colored_polygon(pc, col)


static func _kc(tone: Color, k: float) -> Color:
	return Color(tone.r * k, tone.g * k, tone.b * k)


## One window at night, opaque: the frame / mullions (the art's, plus a steel rail round each cell), the glass inset inside them,
## and behind the glass a ROOM: a ceiling-lit wall that falls off to a darker floor line, darker side walls, a ceiling strip
## light, and (per window) half-drawn blinds, a partition, a desk with a monitor glowing, or a silhouette. Dark windows are plain
## glass; dim rooms are the same rooms at a third of the light; a screen window is a dark room with a flickering monitor. Narrow
## slots (barracks) are a graded strip. dc: dark glass colour, fc: frame colour (both already under the night tint), amt: how
## lit (0 at dusk's edge .. 1 at night).
func _draw_room(P: Dictionary, dc: Color, fc: Color, amt: float) -> void:
	var w: float = P.wpx
	var h: float = maxf(P.hpx, 1.0)
	var wide := w >= 5.0
	var iu := minf(1.5 / maxf(w, 1.0), 0.2) if wide else 0.0
	var ib := minf(1.6 / h, 0.2) if wide else 0.0
	var it := minf(1.2 / h, 0.2) if wide else 0.0
	if wide:
		_wr(P, 0.0, 0.0, 1.0, 1.0, fc, fc)   # the frame behind the glass: mullions and head / sill rails stay visible
	var u0 := iu
	var u1 := 1.0 - iu
	var v0 := ib
	var v1 := 1.0 - it
	var kind := int(P.kind)
	counts["panes"] = int(counts.get("panes", 0)) + 1
	if kind == 0:   # dark glass: a faint sky reflection toward the head
		_wr(P, u0, v0, u1, v1, dc * 0.85, dc * 1.5)
		return
	counts["panes_lit"] = int(counts.get("panes_lit", 0)) + 1
	var tone: Color = WIN_COOL if kind == 3 else P.tone
	var I: float = P.I
	var sc := WIN_SCREEN
	var du := u1 - u0
	var dv := v1 - v0
	if not wide:   # an armoured slot: the strip lit from its head
		_wr(P, u0, v0, u1, v1, dc.lerp(_kc(tone, I * 0.5), amt), dc.lerp(_kc(tone, I * 0.95), amt))
		return
	# the room: wall (ceiling light falls off downward), floor band, darker side walls
	_wr(P, u0, v0 + dv * 0.16, u1, v1, dc.lerp(_kc(tone, I * 0.60), amt), dc.lerp(_kc(tone, I), amt))
	_wr(P, u0, v0, u1, v0 + dv * 0.16, dc.lerp(_kc(tone, I * 0.28), amt), dc.lerp(_kc(tone, I * 0.44), amt))
	if w >= 9.0:
		_wr(P, u0, v0, u0 + du * 0.09, v1, dc.lerp(_kc(tone, I * 0.34), amt), dc.lerp(_kc(tone, I * 0.62), amt))
		_wr(P, u1 - du * 0.09, v0, u1, v1, dc.lerp(_kc(tone, I * 0.34), amt), dc.lerp(_kc(tone, I * 0.62), amt))
	if kind == 3:   # a screen glowing in a dark room, flickering
		var f := _flick(float(P.ph))
		var mc := u0 + du * (0.3 + 0.4 * float(P.p1))
		var halo := dc.lerp(_kc(sc, 0.34 * f), amt)
		_wr(P, mc - du * 0.3, v0 + dv * 0.16, mc + du * 0.3, v0 + dv * 0.72, halo, halo.lerp(dc, 0.3))
		_wr(P, mc - du * 0.17, v0 + dv * 0.30, mc + du * 0.17, v0 + dv * 0.58, dc.lerp(_kc(sc, 0.9 * f), amt), dc.lerp(_kc(sc, 0.7 * f), amt))
		_wr(P, u0, v0 + dv * 0.16, u1, v0 + dv * 0.27, dc.lerp(_kc(tone, 0.06), amt), dc.lerp(_kc(tone, 0.1), amt))   # the desk
		return
	match int(P.vari):
		1:   # half-drawn blinds: slats down from the head
			var ns := 3 + int(float(P.p1) * 2.0)
			for k in ns:
				var vt := v1 - dv * (0.04 + 0.12 * float(k))
				_wr(P, u0, vt - dv * 0.07, u1, vt, dc.lerp(_kc(tone, I * 0.22), amt), dc.lerp(_kc(tone, I * 0.34), amt))
			var ve := v1 - dv * (0.08 + 0.12 * float(ns))
			_wr(P, u0, ve, u1, ve + dv * 0.04, dc.lerp(_kc(tone, I * 0.5), amt), dc.lerp(_kc(tone, I * 0.5), amt))
		2:   # a partition wall inside the room
			var pu := u0 + du * (0.2 + 0.45 * float(P.p1))
			_wr(P, pu, v0, pu + du * 0.17, v1, dc.lerp(_kc(tone, I * 0.22), amt), dc.lerp(_kc(tone, I * 0.30), amt))
			_wr(P, pu - du * 0.025, v0, pu, v1, dc.lerp(_kc(tone, I * 0.5), amt), dc.lerp(_kc(tone, I * 0.74), amt))
		3:   # a desk with a monitor on it
			var mc2 := u0 + du * (0.3 + 0.4 * float(P.p1))
			var halo2 := dc.lerp(Color(tone.r * I * 0.6 + sc.r * 0.22, tone.g * I * 0.6 + sc.g * 0.22, tone.b * I * 0.6 + sc.b * 0.22), amt)
			_wr(P, mc2 - du * 0.26, v0 + dv * 0.16, mc2 + du * 0.26, v0 + dv * 0.7, halo2.lerp(dc, 0.4), halo2)
			_wr(P, mc2 - du * 0.13, v0 + dv * 0.30, mc2 + du * 0.13, v0 + dv * 0.54, dc.lerp(_kc(sc, 0.92), amt), dc.lerp(_kc(sc, 0.72), amt))
			_wr(P, u0 + du * 0.08, v0 + dv * 0.16, u1 - du * 0.08, v0 + dv * 0.27, dc.lerp(_kc(tone, I * 0.18), amt), dc.lerp(_kc(tone, I * 0.26), amt))
		4:   # someone standing at the window: a dark shape against the lit wall
			var sx := 0.3 + 0.4 * float(P.p1)
			var hc := _pq(P, u0 + du * sx, v0 + dv * 0.55)
			var hr := clampf(minf(w * 0.10, h * 0.12), 1.0, 3.0)
			var pc := dc.lerp(_kc(tone, I * 0.09), amt)
			var head := PackedVector2Array()
			for k in 8:
				head.append(hc + Vector2(cos(TAU * float(k) / 8.0) * hr, sin(TAU * float(k) / 8.0) * hr * 1.15))
			_wpoly(head, pc)
			_wpoly(PackedVector2Array([_pq(P, u0 + du * (sx - 0.17), v0 + dv * 0.16), _pq(P, u0 + du * (sx - 0.15), v0 + dv * 0.34),
				_pq(P, u0 + du * (sx - 0.06), v0 + dv * 0.42), _pq(P, u0 + du * (sx + 0.06), v0 + dv * 0.42), _pq(P, u0 + du * (sx + 0.15), v0 + dv * 0.34),
				_pq(P, u0 + du * (sx + 0.17), v0 + dv * 0.16)]), pc)
	# the ceiling strip light (its tube is a warm cream, never pure white)
	var tc := Color(minf(tone.r * 0.35 + WIN_CREAM.r * 0.6, 0.94), minf(tone.g * 0.35 + WIN_CREAM.g * 0.6, 0.93), minf(tone.b * 0.35 + WIN_CREAM.b * 0.6, 0.88))
	var tube := dc.lerp(_kc(tc, 0.55 + 0.45 * I), amt)
	_wr(P, u0 + du * 0.14, v1 - dv * 0.07, u1 - du * 0.14, v1 - dv * 0.01, tube, tube)


## LIGHT7-4 (pane overdraw): the screen rect of every unit that stands IN FRONT of a facility's windows and whose sprite reaches them, per
## facility id: [[sprite rect (screen px), world position]]. Read from the entity layer's per-frame visible lists (vis_units / vis_sp; the
## drawn anchor after any air lift from drawn7) and its per-unit art cache (frame size, pivot). The panes draw above the entity layer
## (they are self-lit, after the night tint), so without this a tall unit against a facade (a suit, a walker, a hovering craft) was
## painted over by the glass behind it. Returns true when the set of rects changed (the panes then redraw this frame).
var _cuts: Dictionary = {}
var _cut_sig := 0


func _unit_cuts() -> bool:
	var el = mv.get("entity_layer") if mv != null else null
	var nc := {}
	var sig := 0
	if el != null and not geo.is_empty():
		var us: Array = el.vis_units
		var sps: PackedVector2Array = el.vis_sp
		var art = el.get("art")
		var ec = art.get("_ec") if art != null else null
		var d7 = el.get("drawn7")
		for g in geo:
			if not g.has("wbb") or (g.wbb as Rect2).size == Vector2.ZERO or not _vr.intersects(g.bbox):
				continue
			var wb: Rect2 = g.wbb
			var far := wb.grow(150.0)
			var lst := []
			for i in mini(us.size(), sps.size()):
				var sp: Vector2 = sps[i]
				if not far.has_point(sp):
					continue
				var e = us[i]
				var id := int(e.id)
				var a := sp
				var dd = d7.get(id) if d7 is Dictionary else null
				if dd != null:
					a = dd[2]
				var c = ec.get(id) if ec is Dictionary else null
				var r: Rect2
				if c is Array and int(c[4]) > 0:
					r = Rect2(a + (c[6] as Vector2), Vector2(float(c[4]), float(c[5])))
				else:
					r = Rect2(a - Vector2(12.0, 30.0), Vector2(24.0, 32.0))
				var onp := false   # LIGHT7-5: only a sprite that reaches a pane cuts (a unit walking past below the windows no longer redraws them)
				if r.intersects(wb):
					for P in g.win:
						if r.intersects(P.bb):
							onp = true
							break
				if onp:
					lst.append([r.grow(1.0), e.pos])
					sig = sig * 31 + hash(Vector2i(r.position))
			if not lst.is_empty():
				nc[int(g.id)] = lst
	_cuts = nc
	var chg := sig != _cut_sig
	_cut_sig = sig
	return chg


## The cut rects of `cutl` that overdraw pane P: the unit's sprite reaches the pane and the unit stands in front of the pane's building
## (beyond its +x / +y edge: a unit behind it is hidden by the building itself).
static func _pane_hits(P: Dictionary, cutl: Array) -> Array:
	var hits := []
	var zr: Rect2 = P.zr
	for c in cutl:
		var pos: Vector2 = c[1]
		if (c[0] as Rect2).intersects(P.bb) and (pos.x >= zr.end.x - 0.02 or pos.y >= zr.end.y - 0.02):
			hits.append(c)
	return hits


## The panes (night / dusk).
func _draw_winf() -> void:   # LIGHT7-5: only the flickering screen rooms (10 Hz); counted by the steady pass
	if night <= WIN_ON:
		return
	var keep := [counts.get("panes", 0), counts.get("panes_lit", 0), counts.get("panes_cut", 0)]
	_wdyn = true
	_wc = winf
	_draw_panes()
	_wdyn = false
	_wc = win
	counts["panes"] = keep[0]
	counts["panes_lit"] = keep[1]
	counts["panes_cut"] = keep[2]


func _draw_windows() -> void:   # LIGHT7-5: every steady pane of the facilities in view, redrawn only on change (_static_sig / unit cuts)
	counts["panes"] = 0
	counts["panes_lit"] = 0
	counts["panes_cut"] = 0
	if night <= WIN_ON:
		return
	_wc = win
	_draw_panes()


func _draw_panes() -> void:
	var amt := smoothstep(WIN_ON, 0.85, night)
	var tint := _tint()
	var dark_c := Color(WIN_GLASS.r * tint.r, WIN_GLASS.g * tint.g, WIN_GLASS.b * tint.b)
	var frame_c := Color(WIN_FRAME.r * tint.r, WIN_FRAME.g * tint.g, WIN_FRAME.b * tint.b)
	var vr := _vr.grow(40.0)
	for g in geo:
		if not g.has("win") or not _vr.intersects(g.bbox) or bool(g.F.lock):
			continue
		var bar_ok := bool(g.F.get("bar", true))
		var cutl: Array = _cuts.get(int(g.id), [])
		for P in g.win:
			if (_wdyn and not vr.intersects(P.bb)) or (String(P.zn) == "barracks" and not bar_ok):
				continue
			if (bool(P.full) and int(P.kind) == 3) != _wdyn:   # LIGHT7-5: the screens flicker (winf); every other pane is steady (win)
				if not _wdyn:
					counts["panes"] = int(counts.get("panes", 0)) + 1
					counts["panes_lit"] = int(counts.get("panes_lit", 0)) + 1
				continue
			var hits: Array = _pane_hits(P, cutl) if not cutl.is_empty() else []
			_cur_cut = []
			if not hits.is_empty():   # units standing in front of the facade: their sprites are cut out of this pane
				for c in hits:
					var rr: Rect2 = (c[0] as Rect2).grow(-0.06 * minf((c[0] as Rect2).size.x, (c[0] as Rect2).size.y))   # a sprite's rect has a transparent margin
					_cur_cut.append([PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]), rr])
				counts["panes_cut"] = int(counts.get("panes_cut", 0)) + 1
			if bool(P.full):
				_draw_room(P, dark_c, frame_c, amt)
				_cur_cut = []
				continue
			# a pane cut by what stands in front of it (a silhouette): the plain graded glass, cut
			var polys: Array = P.polys
			if not _cur_cut.is_empty():
				polys = []
				for pl in P.polys:
					polys.append_array(_clip(pl, _cur_cut))
			_cur_cut = []
			var top := dark_c * 1.4
			var bot := dark_c * 0.8
			if int(P.kind) != 0:
				var tn: Color = P.tone
				var I: float = P.I
				top = dark_c.lerp(_kc(tn, I), amt)
				bot = dark_c.lerp(_kc(tn, I * 0.5), amt)
				counts["panes_lit"] = int(counts.get("panes_lit", 0)) + 1
			var y0: float = P.y0
			var hh := maxf(float(P.y1) - y0, 1.0)
			for poly in polys:
				var cols := PackedColorArray()
				for v in poly:
					cols.append(top.lerp(bot, clampf((v.y - y0) / hh, 0.0, 1.0)))
				_wc.draw_polygon(poly, cols)
			counts["panes"] = int(counts.get("panes", 0)) + 1


# ---------------------------------------------------------------- base (non-facility) and Last Protocol lights
var _bfix: Array = []   # [{k, base, hp, head, P}]


func _plan_base() -> void:
	_bfix = []
	var sil := []
	var foot := []
	for b in _blds:
		var r := Rect2(Vector2(b[0]), Vector2(float(b[1]), float(b[1])))
		foot.append(r)
		sil.append(_sil(r, 22.0 + 14.0 * float(b[1])))
	var free := func(p: Vector2) -> bool:
		for r in foot:
			if (r as Rect2).grow(0.1).has_point(p):
				return false
		return true
	for b in _blds:   # a yard lamp post at each building's front corner, its head over the apron
		var s := float(b[1])
		var p: Vector2 = Vector2(b[0]) + Vector2(s + 0.35, s + 0.35)
		if not free.call(p):
			continue
		var F := _fx("bpole", p, BASE_POLE_Z, Vector2(-0.7, -0.7), p + Vector2(0.15, 0.15), 30.0 + 12.0 * s, 0.25)
		F.col = CT_DOOR
		_bfix.append(F)
	var lp = map.get("lp")
	if lp is Dictionary and (lp as Dictionary).has("base"):
		var base: Dictionary = lp.base
		var ctr := Vector2.ZERO
		var rings: Array = base.get("rings", [])
		var tw: Array = (rings[0] as Dictionary).get("towers", []) if not rings.is_empty() and rings[0] is Dictionary else []
		for c in tw:
			ctr += Vector2(c) / float(tw.size())
		for l in base.get("lights", []):
			var c := Vector2(l.cell)
			match String(l.get("kind", "")):
				"pad":
					var F := _fx("lpad", c, 0.0, Vector2.ZERO, c, 0.0)
					_bfix.append(F)
				"flood":   # a light mast just inside the tower / gate it serves
					var inn := (ctr - c).normalized() if not tw.is_empty() else Vector2(-0.7, -0.7)
					var p := c + inn * 1.2
					if not free.call(p):
						continue
					var F := _fx("mast", p, LP_MAST_Z, inn, p + inn * 1.5, 100.0, 0.25)
					F.col = CT_AREA
					_bfix.append(F)
				_:
					if not free.call(c):
						continue
					var F := _fx("bpole", c, LP_STREET_Z, Vector2(0.7, 0.7), c + Vector2(0.3, 0.3), 56.0, 0.3)
					F.col = CT_AREA
					_bfix.append(F)
			if _bfix.size() >= 600:
				break
	for F in _bfix:
		F.P = _mk_pool(_iso(F.pool), float(F.r), sil) if float(F.r) > 0.0 else {}


func _draw_base_fixtures() -> void:
	if _bfix.is_empty() or night <= 0.004:
		return
	var vr := _vr.grow(600.0)   # LIGHT7-5: steady canvas, redrawn when the view moves 256 px
	for F in _bfix:
		var b: Vector2 = (F.base as Vector2).round()
		if not vr.has_point(b):
			continue
		var hp: Vector2 = (F.hp as Vector2).round()
		match String(F.k):
			"bpole":   # a street / yard lamp: footing, shaft, cobra-head arm (toward the camera or away)
				_sp("fx_plinth", b, 0, 0, Color.WHITE, 1.0, fixo)
				_wrect(fixo, Rect2(b.x - 1.0, hp.y, 1.0, b.y - hp.y), Color(0.50, 0.52, 0.53))
				_wrect(fixo, Rect2(b.x, hp.y, 1.0, b.y - hp.y), Color(0.15, 0.16, 0.19))
				_sp("fx_pole", hp, 4 if (F.aim as Vector2).x + (F.aim as Vector2).y > 0.0 else 5, 0, Color.WHITE, 1.0, fixo)
			"mast":   # a 9 m mast: footing, shaft, a crossbar with two flood luminaires aimed left and right
				_sp("fx_plinth", b, 0, 0, Color.WHITE, 1.0, fixo)
				_wrect(fixo, Rect2(b.x - 1.0, hp.y, 1.0, b.y - hp.y), Color(0.50, 0.52, 0.53))
				_wrect(fixo, Rect2(b.x, hp.y, 1.0, b.y - hp.y), Color(0.15, 0.16, 0.19))
				_wrect(fixo, Rect2(hp.x - 5.0, hp.y, 10.0, 1.0), Color(0.33, 0.36, 0.40))   # crossbar
				_sp("fx_flood", hp + Vector2(-4, 0), 1, 0, Color.WHITE, 1.0, fixo)
				_sp("fx_flood", hp + Vector2(4, 0), 0, 0, Color.WHITE, 1.0, fixo)
			"lpad":
				_sp("fx_puck", b + Vector2(0, 1), 0, 0, Color.WHITE, 1.0, fixo)


func _glow_base(n: float) -> void:
	var vr := _vr.grow(600.0)   # LIGHT7-5: steady canvas, redrawn when the view moves 256 px
	for F in _bfix:
		var b: Vector2 = F.base
		if not vr.has_point(b):
			continue
		match String(F.k):
			"lpad":
				_dot(b - Vector2(0, 1), 2.5, Color(CT_PAD, 0.9 * n))
			"mast":
				_draw_pool(F.P, Color(CT_AREA, 0.36 * n))
				_dot((F.hp as Vector2).round() + Vector2(-4.5, -5.5), 1.6, Color(CT_AREA, 0.95 * n))
				_dot((F.hp as Vector2).round() + Vector2(5.5, -5.5), 1.6, Color(CT_AREA, 0.95 * n))
			_:
				_draw_pool(F.P, Color(F.col, 0.32 * n))
				_dot(F.head + Vector2(0, 2.4), 1.8, Color(F.col, 0.95 * n))
				_dot(F.head + Vector2(0, 3.0), 5.0, Color(F.col, 0.22 * n))


func _draw_glow() -> void:   # LIGHT7-5: the alarm lights only (beacons, ground pulses, strobes, searchlights), 30 Hz on screen
	_gc = glow
	counts["lights"] = _ls
	counts["searchlights"] = 0
	_gb_on = true
	_draw_glow_any(true)
	_gb_flush()


func _draw_glow_s() -> void:   # LIGHT7-5: every steady light (pools, lenses, bay, garage spill, pad edges): only when _static_sig changes
	_gc = glow_s
	counts["lights"] = 0
	_gb_on = true
	_draw_glow_any(false)
	_gb_flush()
	_ls = int(counts.get("lights", 0))
	_gc = glow


func _draw_glow_any(dyn: bool) -> void:
	var n := night
	if n > 0.004 and not dyn:
		_glow_base(n)
	for g in geo:
		if not _vr.intersects(g.bbox) or not g.has("fix"):
			continue
		var a: Dictionary = _alarm.get(int(g.id), {})
		var lvl := float(a.get("lvl", 0.0))
		var red := bool(a.get("red", false))
		var acol := Color(1.0, 0.12, 0.08) if red else Color(1.0, 0.6, 0.1)
		if n > 0.004 and not dyn:
			_facade_light(g, n)
			_glow_fixtures(g, n, lvl > 0.0 and red)
			_glow_bay(g, n)   # LIGHT7-4
		if n > 0.004 and dyn:   # LIGHT7-5: the garage spill follows the doors (LIFE7 eases them open / shut), so it goes with the 30 Hz lights
			# light from the garages: a spill out of the door (LIFE7 door_open when present, else a leak under the door)
			var life = mv.get("fac_life7") if mv != null else null
			for ga in g.garages:
				var r: Rect2 = ga[0]
				var op := 0.0
				if life != null and life.has_method("door_open"):
					op = clampf(float(life.door_open(int(g.id), "g%d" % int(ga[2]))), 0.0, 1.0)
				op = float(int(op * 24.0)) / 24.0   # LIGHT7-5: quantized, so the cut polygons are cached (_spill)
				var dir := 1.0 if int(ga[1]) == 0 else -1.0
				var X := r.end.x - INSET if int(ga[1]) == 0 else r.position.x + INSET
				var yc := r.get_center().y
				var k := 0.25 + 0.75 * op
				var p0 := _iso(Vector2(X, yc - 0.7))
				var p1 := _iso(Vector2(X, yc + 0.7))
				var q1 := _iso(Vector2(X + dir * (0.6 + 1.8 * op), yc + 1.0 + 0.4 * op))
				var q0 := _iso(Vector2(X + dir * (0.6 + 1.8 * op), yc - 1.0 - 0.4 * op))
				var cw := Color(1.0, 0.86, 0.6, 0.5 * n * k)
				# LIGHT7: cut where the garage itself / a building hides the apron (an east garage's spill used to lie
				# over its own roof as a see-through band); the fade runs from the door line out
				var m0 := (p0 + p1) * 0.5
				var ax := (q0 + q1) * 0.5 - m0
				var l2 := maxf(ax.length_squared(), 1.0)
				var gk := "%d:%d:%d" % [int(g.id), int(ga[2]), int(op * 24.0)]
				if not _spill.has(gk):
					if _spill.size() > 512:
						_spill.clear()
					_spill[gk] = _clip(PackedVector2Array([p0, p1, q1, q0]), g.get("lsil", g.sil))
				for pc in _spill[gk]:
					var cols := PackedColorArray()
					for v in pc:
						cols.append(Color(cw, cw.a * (1.0 - clampf((v - m0).dot(ax) / l2, 0.0, 1.0))))
					_gpoly(pc, cols)
				counts["lights"] += 1
		if n > 0.004 and not dyn:
			# pad / helipad perimeter: steady green flush lights (night / dusk)
			var ei := 0
			for e in g.edge:
				ei += 1
				if bool(g.edge_hid[ei - 1]):
					continue
				_dot(_iso(e[0]) - Vector2(0, 1), 1.8 + 1.0 * n, Color(CT_PAD, 0.9 * n))
				counts["lights"] += 1
		# alarm: rotating beacon flashes + a pulse on the ground round the tower foot, flashing wall lamps, searchlights
		if lvl > 0.0 and dyn:
			var k := 0
			for tc in g.towers:
				if _hid(g, "t%d" % k):
					k += 1
					continue

				_beacon_flash(_iso(tc + BEACON_OFF) - Vector2(0, TOWER_ROOF_Z + 6.0), t * 6.0 + float(k) * 0.8, acol, 0.6 + 0.4 * n)
				_draw_pool(g.apool[k], Color(acol, (0.10 + 0.16 * n) * (0.6 + 0.4 * sin(t * 6.0 + float(k)))))
				k += 1
			var gj := 0
			for q in _gate_posts(g):
				gj += 1
				if not _hid(g, "p%d" % (gj - 1)):
					_beacon_flash(_iso(q[0]) - Vector2(0, float(q[1]) + 6.0), t * 6.0 + (q[0] as Vector2).x, acol, 0.55 + 0.4 * n)
			var ph := int(t * 5.0)
			var red_on := bool(a.get("red", false))   # POLISH7-2 (13.9c-17): amber alert = beacons only
			for F in (g.fix if red_on else []):   # the wall strobes (on their battlement panels), chasing round the ring
				if String(F.k) == "alarm" and not F.hid and (int(F.i) + ph) % 4 < 2:
					var gp := (F.hp as Vector2).round() + Vector2(0, -3.5)
					_dot(gp, 2.0, Color(1.0, 0.25, 0.15, 1.0))
					_dot(gp, 6.0, Color(acol, 0.25 + 0.25 * n))
			# searchlights: one per tower, sweeping its approach outside the wall
			k = 0
			for tc in (g.towers if red_on else []):
				var outv: Vector2 = (tc - g.ctr).normalized()
				var ang := 0.75 * sin(t * 0.55 + float(k) * 1.7)
				var tgt: Vector2 = tc + outv.rotated(ang) * (5.0 + 1.5 * sin(t * 0.31 + float(k)))
				if not _hid(g, "s%d" % k):
					_searchlight(g, _iso(tc + SEARCH_OFF) - Vector2(0, SEARCH_Z), tgt, 0.35 + 0.65 * n)
				k += 1


## A rotating beacon seen from the camera: the reflector faces it once a turn (a flash), the lens glows in between.
## No beam wedge: the light shows on the lens and on the ground (13.9c-18, nothing translucent over buildings).
func _beacon_flash(L: Vector2, ang: float, col: Color, a: float) -> void:
	var face := pow(maxf(0.0, cos(ang)), 6.0)
	_dot(L, 3.0 + 6.0 * face, Color(col, a * (0.22 + 0.6 * face)))
	_dot(L, 1.8, Color(1, 0.9, 0.85, a * (0.5 + 0.5 * face)))
	counts["lights"] = int(counts.get("lights", 0)) + 1


## A tower searchlight: a thin faint beam from the head (outward, over open ground only) and the lit spot on the ground,
## cut where a building / wall hides it.
func _searchlight(g: Dictionary, L: Vector2, tgt: Vector2, a: float) -> void:
	var S := _iso(tgt)
	var d := (S - L)
	var perp := Vector2(-d.y, d.x).normalized()
	var rx := 30.0
	var c := Color(0.92, 0.96, 1.0)
	_gpoly(PackedVector2Array([L - perp * 1.0, L + perp * 1.0, S + perp * rx * 0.3, S - perp * rx * 0.3]),
		PackedColorArray([Color(c, 0.16 * a), Color(c, 0.16 * a), Color(c, 0.02 * a), Color(c, 0.02 * a)]))
	_draw_pool(_mk_pool(S, rx * 1.5, g.get("lsil", g.sil)), Color(c, 0.55 * a))
	_dot(L, 2.5, Color(c, a))
	counts["searchlights"] = int(counts.get("searchlights", 0)) + 1
