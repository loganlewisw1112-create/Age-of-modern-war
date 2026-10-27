extends Node2D
## G7 (LPMAP7) a world that reacts to the spread (master scope 13.9). PRESENTATION ONLY: reads the render snapshot
## (snap.creep from Creep.snap, snap.events, snap.tick) and the static map dict (map.terrain, map.lp.world); never
## writes the sim (the view-on/off hash check holds).
##  1. Creep-warped terrain: the view keeps, per creep cell, how long creep has sat there (sim seconds, from snap.tick).
##     One quad + one shader over the whole map: forest calcifies into a silver metal lattice, water darkens to an oily
##     black, buildings / urban blocks sprout cyan nanite growths, open ground greys out with metal flecks. Purged
##     (sterile) cells lose their warp slowly (RECOVER_S), so the ground recovers its colour over minutes.
##  2. Sky and light: a CanvasModulate on the world canvas turns darker and colder and a drifting haze (CanvasLayer 1,
##     below drone input 9 / HUD 10) thickens as the creep meter (snap.creep.coverage) climbs; purging pushes it back.
##     Eased over time so it never jumps.
##  3. Wildlife and civilian traces (map.lp.world): herds that graze, flee from fighting (any snapshot event with a pos
##     nearby) and move out of creep; abandoned vehicles and empty camps that get overgrown by creep; distress beacons
##     that blink (the lost-squad beacon faint and irregular).
## Cost: the warp shader is one draw call; the age update is striped (a quarter of the 128x128 grid every few ticks);
## traces are culled to the screen and skipped when zoomed far out. A match without creep and without map.lp keeps
## the layer hidden and does nothing (no CanvasModulate is created).
## Wiring (ORCH, match_view.gd, CR change_request.world7_layer): world7_layer = World7Layer.new(); z_index 0;
##   add_child right after terrain_layer (before creep_layer); world7_layer.setup(self) with the other layers;
##   each frame world7_layer.refresh(snap).

const ViewUtil = preload("res://presentation/view/view_util.gd")
const FissureLayer = preload("res://presentation/view/fissure_layer.gd")  # G7 FISSURE7

const TICK_RATE := 20.0
const WARP_FULL_S := 180.0       # seconds of creep until a cell is fully warped (PROVISIONAL)
const RECOVER_S := 240.0         # purged cell: full warp -> clean (PROVISIONAL)
const FADE_S := 600.0            # creep receded without a purge: slow fade
const STRIPES := 4
const STRIPE_EVERY := 3          # ticks between stripe passes

const SHADER := """
shader_type canvas_item;
uniform sampler2D terr_tex : filter_nearest;
uniform vec2 map_size = vec2(512.0, 512.0);

float h1(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	float a = smoothstep(0.03, 1.0, texture(TEXTURE, UV).r);
	vec2 tile = UV * map_size;
	int code = int(texture(terr_tex, UV).r * 255.0 + 0.5);
	vec4 col = vec4(0.0);
	if (a > 0.0) {
		if (code == 3) {
			vec2 f = fract(tile * 3.0);
			float line = step(min(min(f.x, f.y), abs(f.x - f.y)), 0.10);
			col = mix(vec4(0.20, 0.22, 0.28, 0.50 * a), vec4(0.66, 0.70, 0.78, 0.90 * a), line);
		} else if (code == 4 || code == 9 || code == 10) {
			float sheen = 0.5 + 0.5 * sin(tile.x * 0.7 + tile.y * 0.4 + TIME * 0.6);
			col = vec4(mix(vec3(0.03, 0.04, 0.06), vec3(0.18, 0.08, 0.26), sheen * 0.35), 0.68 * a);
		} else if (code == 8) {
			float n = h1(floor(tile * 4.0));
			col = n > 0.62 ? vec4(0.30, 0.90, 1.00, 0.75 * a) : vec4(0.14, 0.09, 0.20, 0.55 * a);
		} else {
			float fleck = step(0.93, h1(floor(tile * 5.0)));
			col = mix(vec4(0.30, 0.29, 0.34, 0.40 * a), vec4(0.72, 0.76, 0.84, 0.55 * a), fleck);
		}
	}
	COLOR = col;
}
"""

const HAZE := """
shader_type canvas_item;
uniform float amount = 0.0;
float h1(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h1(i), h1(i + vec2(1, 0)), f.x), mix(h1(i + vec2(0, 1)), h1(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 p = UV * vec2(6.0, 3.5) + vec2(TIME * 0.025, TIME * 0.01);
	float n = noise(p) * 0.6 + noise(p * 2.3) * 0.4;
	float edge = smoothstep(0.15, 0.95, distance(UV, vec2(0.5)) * 1.3);
	COLOR = vec4(0.46, 0.50, 0.58, amount * (0.55 + 0.45 * n) * (0.6 + 0.4 * edge));
}
"""

var mv = null
var map: Dictionary = {}
var hm: Dictionary = {}
var active := false
var _cw := 0
var _ch := 0
var _cs := 4
var _age := PackedFloat32Array()
var _age8 := PackedByteArray()
var _v := PackedByteArray()
var _on := 64
var _stripe_tick := PackedInt32Array()
var _last_tick := -1
var _tex: ImageTexture
var _terr: ImageTexture
var _modulate: CanvasModulate
var _haze_layer: CanvasLayer
var _haze: ColorRect
var gloom := 0.0                 # eased 0..1 (sky darkness / haze)
var coverage := 0.0
var passes := 0
var fissures: Node2D             # G7 FISSURE7: openings + growths (added to the match view after the creep layer)
var traces: Node2D               # wildlife / civilian traces (own canvas item: the warp shader must not touch them)


func _init() -> void:
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	material = m
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visible = false


func setup(view) -> void:
	mv = view
	map = view.world.map
	hm = ViewUtil.height_map_of(map)
	_setup_traces()
	# G7 FISSURE7: openings draw over the creep, under everything after it (same z, next in tree order)
	fissures = FissureLayer.new()
	fissures.name = "FissureLayer"
	fissures.z_index = 0
	var parent: Node = view if view is Node else self
	if get_parent() == parent:
		parent.add_child(fissures)
		var cl = view.get("creep_layer")
		var at: int = (cl as Node).get_index() + 1 if cl is Node and (cl as Node).get_parent() == parent else get_index() + 1
		parent.move_child(fissures, at)
	else:
		add_child(fissures)


## Warp age of a tile cell 0..1 (tests / playtest probes).
func warp_at(cell: Vector2i) -> float:
	if _cw == 0:
		return 0.0
	var k := (cell.y / _cs) * _cw + cell.x / _cs
	return clampf(_age[k] / WARP_FULL_S, 0.0, 1.0) if k >= 0 and k < _age.size() else 0.0


func refresh(snap: Dictionary) -> void:
	if fissures != null:
		fissures.refresh(snap)  # G7 FISSURE7
	var c: Dictionary = snap.get("creep", {})
	if c.is_empty() and not map.has("lp"):
		visible = false
		return
	if not active:
		_activate()
	visible = true
	var tick := int(snap.get("tick", 0))
	if not c.is_empty():
		_ingest(c, tick)
		coverage = float(c.get("coverage", 0.0))
	_sky(get_process_delta_time())
	_traces_frame(snap)


func _activate() -> void:
	active = true
	_modulate = CanvasModulate.new()
	add_child(_modulate)
	_haze_layer = CanvasLayer.new()
	_haze_layer.layer = 1
	add_child(_haze_layer)
	_haze = ColorRect.new()
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_haze.set_anchors_preset(Control.PRESET_FULL_RECT)
	var hs := Shader.new()
	hs.code = HAZE
	var hmat := ShaderMaterial.new()
	hmat.shader = hs
	_haze.material = hmat
	_haze_layer.add_child(_haze)
	var mw := int(map.get("w", 0))
	var mh := int(map.get("h", 0))
	if mw > 0 and (map.terrain as PackedByteArray).size() == mw * mh:
		_terr = ImageTexture.create_from_image(Image.create_from_data(mw, mh, false, Image.FORMAT_L8, map.terrain))
		(material as ShaderMaterial).set_shader_parameter("terr_tex", _terr)
		(material as ShaderMaterial).set_shader_parameter("map_size", Vector2(mw, mh))


## Accumulates creep age on one stripe of rows per pass (sim time from snap.tick, so pause / speed-up are honoured).
func _ingest(c: Dictionary, tick: int) -> void:
	var cw := int(c.cw)
	var ch := int(c.ch)
	if cw != _cw or ch != _ch:
		_cw = cw
		_ch = ch
		_cs = int(c.cs)
		_age = PackedFloat32Array()
		_age.resize(cw * ch)
		_age.fill(0.0)
		_age8 = PackedByteArray()
		_age8.resize(cw * ch)
		_age8.fill(0)
		_stripe_tick = PackedInt32Array()
		_stripe_tick.resize(STRIPES)
		_stripe_tick.fill(tick)
		_tex = ImageTexture.create_from_image(Image.create_from_data(cw, ch, false, Image.FORMAT_L8, _age8))
		_last_tick = tick
	if tick == _last_tick or tick % STRIPE_EVERY != 0:
		return
	_last_tick = tick
	var s := (tick / STRIPE_EVERY) % STRIPES
	var secs := float(maxi(tick - _stripe_tick[s], 0)) / TICK_RATE
	_stripe_tick[s] = tick
	var v: PackedByteArray = c.v
	var fl: PackedByteArray = c.fl
	if v.size() != cw * ch or fl.size() != cw * ch:
		return
	_on = int(c.get("on", 64))
	_v = v
	var grow := secs
	var rec := secs * WARP_FULL_S / RECOVER_S
	var fade := secs * WARP_FULL_S / FADE_S
	for r in range(s, ch, STRIPES):
		var base := r * cw
		for x in cw:
			var k := base + x
			var a := _age[k]
			if v[k] >= _on:
				a = minf(a + grow, WARP_FULL_S)
			elif a > 0.0:
				a = maxf(a - (rec if fl[k] & 1 != 0 else fade), 0.0)
			else:
				continue
			_age[k] = a
			_age8[k] = int(a / WARP_FULL_S * 255.0)
	_tex.update(Image.create_from_data(cw, ch, false, Image.FORMAT_L8, _age8))
	passes += 1
	queue_redraw()


## Sky darkens / cools and haze thickens with the creep meter (eased: ~0.15 per second at most).
func _sky(dt: float) -> void:
	var target := smoothstep(0.12, 0.80, coverage)
	gloom = move_toward(gloom, target, 0.15 * maxf(dt, 0.0))
	if _modulate != null:
		_modulate.color = Color(1.0, 1.0, 1.0).lerp(Color(0.60, 0.65, 0.80), gloom)
	if _haze != null:
		(_haze.material as ShaderMaterial).set_shader_parameter("amount", 0.30 * gloom)
		_haze.visible = gloom > 0.01


func _draw() -> void:
	if _tex == null:
		return
	var mw := float(map.get("w", _cw * _cs))
	var mh := float(map.get("h", _ch * _cs))
	draw_set_transform_matrix(Transform2D(Vector2(32.0, 16.0), Vector2(-32.0, 16.0), Vector2.ZERO))
	draw_texture_rect(_tex, Rect2(0, 0, float(_cw * _cs) if _cw * _cs > 0 else mw, float(_ch * _cs) if _ch * _cs > 0 else mh), false)


# ================================================================ traces
const FLEE_R := 16.0             # tiles: fighting this close scares a herd
const FLEE_SPEED := 3.5          # tiles / s
const FLEE_S := 4.0
const ANIMAL_MIN_ZOOM := 0.22    # canvas scale below which herds / camps are not drawn (beacons always are)
const ANIMAL_COL := {"deer": Color(0.56, 0.41, 0.26), "boar": Color(0.30, 0.24, 0.20), "birds": Color(0.12, 0.12, 0.14),
	"dogs": Color(0.52, 0.52, 0.50)}

var herds: Array = []            # {pos, kind, n, flee: Vector2, flee_t, scared}
var _vehicles: Array = []
var _camps: Array = []
var _beacons: Array = []
var scares := 0                  # herds sent running (tests / playtest)


func _setup_traces() -> void:
	var lp: Dictionary = map.get("lp", {})
	var wd: Dictionary = lp.get("world", {})
	herds = []
	for a in wd.get("animals", []):
		herds.append({"pos": Vector2(a.pos), "kind": String(a.kind), "n": int(a.n), "flee": Vector2.ZERO, "flee_t": 0.0, "scared": 0})
	_vehicles = wd.get("vehicles", [])
	_camps = wd.get("camps", [])
	_beacons = wd.get("beacons", [])
	if traces == null:
		traces = Node2D.new()
		traces.z_index = 1
		add_child(traces)
		traces.draw.connect(_draw_traces)


## Creep value 0..255 at a tile position (from the last ingested snapshot), 0 when unknown.
func _creep_v(p: Vector2) -> int:
	if _cw == 0 or _v.size() != _cw * _ch:
		return 0
	var cx := clampi(int(p.x) / _cs, 0, _cw - 1)
	var cy := clampi(int(p.y) / _cs, 0, _ch - 1)
	return int(_v[cy * _cw + cx])


## Herds flee from fighting (any snapshot event with a pos within FLEE_R) and walk out of creep (down the gradient).
func _traces_frame(snap: Dictionary) -> void:
	if traces == null or herds.is_empty() and _beacons.is_empty():
		return
	var dt := clampf(get_process_delta_time(), 0.0, 0.1)
	step_herds(snap.get("events", []), dt)
	traces.queue_redraw()


func step_herds(events: Array, dt: float) -> void:
	var mw := float(map.get("w", 512))
	var mh := float(map.get("h", 512))
	var n_ev := mini(events.size(), 200)
	for hd in herds:
		var p: Vector2 = hd.pos
		for i in n_ev:
			var ev = events[i]
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			var ep = ev.get("pos", ev.get("data", {}).get("pos") if typeof(ev.get("data")) == TYPE_DICTIONARY else null)
			if ep is Vector2 and p.distance_to(ep) < FLEE_R:
				var away: Vector2 = (p - ep)
				hd.flee = away.normalized() if away.length() > 0.01 else Vector2.RIGHT
				if float(hd.flee_t) <= 0.0:
					scares += 1
				hd.flee_t = FLEE_S
				hd.scared = int(hd.scared) + 1
				break
		if float(hd.flee_t) <= 0.0 and _creep_v(p) >= _on:
			var best := Vector2.ZERO
			var bv := _creep_v(p)
			for d in [Vector2(_cs, 0), Vector2(-_cs, 0), Vector2(0, _cs), Vector2(0, -_cs)]:
				var cv := _creep_v(p + d * 2.0)
				if cv < bv:
					bv = cv
					best = d.normalized()
			if best != Vector2.ZERO:
				hd.flee = best
				hd.flee_t = 1.5
		if float(hd.flee_t) > 0.0:
			p += (hd.flee as Vector2) * FLEE_SPEED * dt
			hd.flee_t = float(hd.flee_t) - dt
			hd.pos = Vector2(clampf(p.x, 2.0, mw - 3.0), clampf(p.y, 2.0, mh - 3.0))


func _iso(p: Vector2) -> Vector2:
	var s := ViewUtil.iso(p)
	if not hm.is_empty():
		s.y -= ViewUtil.ground_lift(hm, p)
	return s


func _draw_traces() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var xf := vp.get_canvas_transform()
	var inv := xf.affine_inverse()
	var vr := Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * vp.get_visible_rect().size).grow(64.0)
	var z := absf(xf.get_scale().x)
	var t := float(Time.get_ticks_msec()) / 1000.0
	for b in _beacons:
		var p := _iso(Vector2(b.cell) + Vector2(0.5, 0.5))
		if not vr.has_point(p):
			continue
		var on := false
		var ph := fmod(t + float(Vector2i(b.cell).x % 7) * 0.13, 1.2)
		if bool(b.get("lost_squad", false)):
			on = sin(t * 1.7) + sin(t * 4.3) > 1.1
		else:
			on = ph < 0.18
		var k := 1.0 / maxf(z, 0.15)
		traces.draw_circle(p, 2.5 * k, Color(1.0, 0.15, 0.1, 0.95 if on else 0.25))
		if on or ph < 0.6:
			traces.draw_arc(p, (4.0 + ph * 26.0) * k, 0.0, TAU, 18, Color(1.0, 0.2, 0.15, maxf(0.0, 0.5 - ph * 0.8)), 1.5 * k)
	if z < ANIMAL_MIN_ZOOM:
		return
	for vh in _vehicles:
		var c := Vector2(vh.cell) + Vector2(0.5, 0.5)
		var p := _iso(c)
		if not vr.has_point(p):
			continue
		var vlen := {"car": 9.0, "van": 10.0, "truck": 14.0, "bus": 18.0}.get(String(vh.kind), 10.0) as float
		var col := Color(0.44, 0.31, 0.22) if _creep_v(c) < _on else Color(0.24, 0.19, 0.31)
		traces.draw_set_transform(p, float(vh.rot), Vector2(1.0, 0.5))
		traces.draw_rect(Rect2(-vlen * 0.5, -3.0, vlen, 6.0), col)
		traces.draw_rect(Rect2(-vlen * 0.5 + 1.0, -2.0, vlen * 0.35, 4.0), col.darkened(0.35))
		traces.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if _creep_v(c) >= _on:
			traces.draw_circle(p + Vector2(3.0, -3.0), 1.5, Color(0.35, 0.95, 1.0, 0.8))
	for cp in _camps:
		var c := Vector2(cp.cell) + Vector2(0.5, 0.5)
		var p := _iso(c)
		if not vr.has_point(p):
			continue
		var cloth := Color(0.46, 0.47, 0.33) if _creep_v(c) < _on else Color(0.27, 0.22, 0.33)
		for i in int(cp.tents):
			var o := p + Vector2(cos(float(i) * 2.2) * 14.0, sin(float(i) * 2.2) * 7.0)
			traces.draw_colored_polygon(PackedVector2Array([o + Vector2(-6, 2), o + Vector2(6, 2), o + Vector2(0, -7)]), cloth)
		traces.draw_circle(p, 3.0, Color(0.10, 0.09, 0.08))
	for hd in herds:
		var c: Vector2 = hd.pos
		var p := _iso(c)
		if not vr.has_point(p):
			continue
		var col: Color = ANIMAL_COL.get(String(hd.kind), Color(0.5, 0.4, 0.3))
		var run := float(hd.flee_t) > 0.0
		for i in int(hd.n):
			var o := Vector2(cos(float(i) * 2.4), sin(float(i) * 2.4)) * (0.6 + 0.25 * float(i))
			o += Vector2(sin(t * (1.6 if run else 0.3) + float(i)), cos(t * 0.27 + float(i) * 1.3)) * 0.3
			var q := _iso(c + o)
			if String(hd.kind) == "birds":
				var lift := 18.0 + (10.0 * sin(t * 3.0 + float(i)) if run else 0.0)
				traces.draw_polyline(PackedVector2Array([q + Vector2(-3, -lift - 2), q + Vector2(0, -lift), q + Vector2(3, -lift - 2)]), col, 1.0)
			else:
				traces.draw_circle(q, 2.0, col)
