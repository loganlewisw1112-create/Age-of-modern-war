extends Node2D
## G7 (FISSURE7) creep fissures, canyons and growths on screen. PRESENTATION ONLY: reads snap.creep.fis
## (Fissures7.snap(w), carried inside Creep.snap) and never touches the sim.
##   openings: one quad over the map; the tile stage map (ts, one byte per tile) is uploaded as an L8 texture only when
##     fis.dv changes. The shader rebuilds smooth depth from the stages (crack 0.25, fissure 0.6, canyon 1.0):
##     spidering crack lines around every opening, crumbling noisy rims, dark strata walls lit on the far side
##     (the wall facing the camera), a pulsing glowing nanite floor at the canyon bottom, haze rising out of it;
##     purged (scar) openings turn grey and dead; spans draw as a steel deck.
##   growths: display-only scenery derived from the snap (vein points and creep age, hashed per tile so they never
##     flicker): 10 kinds from assets/art/g7_growths/growths.png, larger and denser in canyons, rising slowly out of
##     the ground (sim time), swaying, glow layer pulsing (additive child). Culled to the screen through 16 x 16 tile
##     buckets; zoomed out (< SCENERY_MIN_ZOOM) only canyon growths, below FAR_ZOOM none (the quad still shows).
##   big growths (Machine buildings drawn by the entity layer): a pulsing aura while alive, a shatter (shards +
##     flash) when one disappears; span jobs: a progress line between the banks.
## Wiring: world7_layer.setup() adds this node to the match view right after the creep layer (same z) and
## world7_layer.refresh() calls refresh(snap) every frame. Hidden and free when the match has no fissures.

const ATLAS := "res://assets/art/g7_growths/growths.png"
const CELL := Vector2(48, 96)
const FOOT := Vector2(24, 92)
const KINDS := 10
const BUCKET := 16
const SCENERY_MIN_ZOOM := 0.32
const FAR_ZOOM := 0.16
const RISE_S := 25.0
const SHATTER_S := 1.4

const SHADER := """
shader_type canvas_item;
uniform sampler2D ts_tex : filter_nearest;
uniform vec2 size = vec2(512.0, 512.0);

float h1(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 h2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h1(i), h1(i + vec2(1, 0)), f.x), mix(h1(i + vec2(0, 1)), h1(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return vn(p) * 0.55 + vn(p * 2.1 + 3.1) * 0.3 + vn(p * 4.3 + 7.7) * 0.15; }
float net(vec2 x) {
	vec2 n = floor(x); vec2 f = fract(x);
	float d1 = 8.0; float d2 = 8.0;
	for (int j = -1; j <= 1; j++) { for (int i = -1; i <= 1; i++) {
		vec2 g = vec2(float(i), float(j)); vec2 r = g + h2(n + g) - f; float d = dot(r, r);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	} }
	return sqrt(d2) - sqrt(d1);
}
int code(vec2 t) { return int(texture(ts_tex, (floor(t) + 0.5) / size).r * 255.0 + 0.5); }
float dep(vec2 t) {
	int c = code(t); int s = c & 7;
	return s == 1 ? 0.25 : (s == 2 ? 0.62 : (s == 3 ? 1.0 : 0.0));
}
float D(vec2 t) {
	vec2 p = t - 0.5; vec2 i = floor(p); vec2 f = fract(p);
	return mix(mix(dep(i + 0.5), dep(i + vec2(1.5, 0.5)), f.x), mix(dep(i + vec2(0.5, 1.5)), dep(i + 1.5), f.x), f.y);
}

void fragment() {
	vec2 t = UV * size;
	int c0 = code(t);
	float d = D(t);
	float d2 = (D(t + vec2(1.3, 0.0)) + D(t - vec2(1.3, 0.0)) + D(t + vec2(0.0, 1.3)) + D(t - vec2(0.0, 1.3))) * 0.25;
	if (d < 0.01 && d2 < 0.01 && (c0 & 7) == 0) { discard; }
	bool scar = (c0 & 16) != 0;
	vec4 col = vec4(0.0);
	// spidering cracks: rim zone around every opening and the crack tiles themselves
	float zone = smoothstep(0.02, 0.2, max(d, d2 * 0.9));
	float ln = 1.0 - smoothstep(0.0, 0.05 + 0.06 * zone, net(t * 1.25 + 4.0));
	float ln2 = (1.0 - smoothstep(0.0, 0.035, net(t * 3.1 + 9.0))) * 0.6;
	float crk = clamp(max(ln, ln2 * step(0.3, d)), 0.0, 1.0) * zone;
	col = vec4(vec3(0.05, 0.04, 0.06), crk * 0.85);
	float cg = crk * smoothstep(0.18, 0.35, d) * (0.55 + 0.45 * sin(TIME * 2.0 + t.x * 0.3 + t.y * 0.2));
	col.rgb = mix(col.rgb, vec3(0.30, 0.90, 0.95), cg * 0.7);
	// opening: crumbling rim, strata walls, glowing floor
	float dsm = mix(d, d2, 0.5);
	float e = dsm + (fbm(t * 1.3) - 0.5) * 0.30 + (h1(floor(t * 3.0)) - 0.5) * 0.05;
	float open = smoothstep(0.38, 0.43, e);
	if (open > 0.0) {
		// depth illusion: the far (north-west) wall is seen as a band below the far rim; the floor only past it
		float f1 = D(t - vec2(0.8, 0.8));
		float f2 = D(t - vec2(1.6, 1.6));
		float f3 = D(t - vec2(2.4, 2.4));
		float farv = min(min(f1, f2), f3);
		float wallband = 1.0 - smoothstep(0.62, 0.95, farv);
		float strata = 0.80 + 0.20 * step(0.5, fract((t.x + t.y) * 1.1 + farv * 5.0 + fbm(t * 0.7) * 1.8));
		vec3 wtop = vec3(0.40, 0.35, 0.31);
		vec3 wbot = vec3(0.07, 0.06, 0.08);
		vec3 wall = mix(wtop, wbot, clamp(farv * 1.15, 0.0, 1.0)) * strata;
		float fl = smoothstep(0.80, 0.97, d2) * (1.0 - wallband);
		float pulse = 0.55 + 0.45 * sin(TIME * 1.7 - (t.x + t.y) * 0.12);
		float vein = 1.0 - smoothstep(0.0, 0.10, net(t * 0.9 + vec2(TIME * 0.05, 0.0)));
		vec3 deep = vec3(0.045, 0.03, 0.08);
		vec3 flo = mix(deep, vec3(0.30, 0.95, 1.0), clamp(0.10 + vein * 0.85 * pulse, 0.0, 1.0));
		vec3 oc = mix(deep, wall, wallband);
		oc = mix(oc, flo, fl);
		// near (south-east) lip: a dark shadow edge where the ground drops away from the camera
		float nearv = D(t + vec2(0.7, 0.7));
		oc *= 1.0 - 0.55 * (1.0 - smoothstep(0.35, 0.6, nearv)) * (1.0 - wallband);
		// fissure slot: a thin glow seam deep in the crack
		float seam = smoothstep(0.56, 0.62, d) * (1.0 - smoothstep(0.7, 0.85, d2));
		oc = mix(oc, vec3(0.25, 0.85, 0.9), seam * 0.5 * pulse);
		if (scar) {
			float g = dot(oc, vec3(0.3, 0.5, 0.2));
			oc = mix(vec3(g) * vec3(0.9, 0.88, 0.84), vec3(0.40, 0.38, 0.34), 0.45);
		}
		col = mix(col, vec4(oc, 1.0), open);
		// haze rising out of the canyon
		if (!scar) {
			float hz = smoothstep(0.45, 1.0, d2) * fbm(t * 0.45 + vec2(TIME * 0.04, TIME * 0.16));
			col.rgb = mix(col.rgb, vec3(0.40, 0.70, 0.95), hz * 0.30);
		}
	}
	// haze drifting over the rim
	if (!scar) {
		float hz2 = smoothstep(0.2, 0.9, d2) * (1.0 - open) * fbm(t * 0.35 + vec2(-TIME * 0.05, TIME * 0.11));
		col = mix(col, vec4(0.45, 0.72, 0.95, 1.0), hz2 * 0.22);
		col.a = max(col.a, hz2 * 0.22);
	}
	if (scar && open <= 0.0) { col.rgb = mix(col.rgb, vec3(0.5, 0.48, 0.42), 0.6); }
	// span: steel deck with hazard edges
	if ((c0 & 7) == 5) {
		vec2 f = fract(t);
		float plank = step(0.5, fract((t.x - t.y) * 1.5));
		vec3 deck = mix(vec3(0.34, 0.36, 0.38), vec3(0.26, 0.28, 0.30), plank);
		if (f.x < 0.08 || f.y < 0.08) { deck = vec3(0.85, 0.65, 0.12); }
		col = vec4(deck, 1.0);
	}
	COLOR = col;
}
"""

var _dv := -1
var _w := 0
var _h := 0
var _tex: ImageTexture
var _atlas: Texture2D
var growths: Node2D   # base sprites (normal blend)
var glows: Node2D     # glow layer + auras + shatter (additive)
var _inst := {}       # bucket key -> Array of [canvas pos, kind, size, t0_s, phase, big_scale, canyon]
var _key := -1
var _now_s := 0.0      # sim seconds of the last snap
var _big := {}         # id -> canvas pos
var _shatter: Array = []   # [pos, t_start(real s)]
var _jobs: Array = []
var _f_last = null     # SWN9: the fissure snapshot dict refresh() last used
var uploads := 0
var drawn := 0         # growth sprites drawn last frame (tests / playtest)
var instances := 0
var shatters := 0


func _init() -> void:
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	material = m
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	growths = Node2D.new()
	growths.use_parent_material = false
	growths.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(growths)
	growths.draw.connect(_draw_growths)
	glows = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glows.material = add
	glows.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(glows)
	glows.draw.connect(_draw_glows)
	if ResourceLoader.exists(ATLAS):
		_atlas = load(ATLAS)


static func _real() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


static func iso(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)


static func _hh(a: int, b: int) -> int:
	var x := (a * 73856093) ^ (b * 19349663)
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return x ^ (x >> 16)


## snap: the render snapshot (reads snap.creep.fis). Cheap when nothing changed.
func refresh(snap: Dictionary) -> void:
	var c: Dictionary = snap.get("creep", {})
	var f: Dictionary = c.get("fis", {}) if not c.is_empty() else {}
	if f.is_empty():
		visible = false
		return
	visible = true
	_now_s = float(f.get("tick", 0)) / 20.0
	# SWN9: same snapshot object as last frame -> upload / build / big-track would redo the same work on the same input
	if is_same(f, _f_last):
		growths.queue_redraw()
		glows.queue_redraw()
		return
	_f_last = f
	if int(f.get("dv", 0)) != _dv or int(f.w) != _w:
		_upload(f)
	var key := int(f.get("dv", 0)) * 1000003 + (f.pts as PackedInt32Array).size() * 7 + int(f.get("tick", 0)) / 200
	if key != _key or _inst.is_empty():
		_key = key
		_build(f)
	_track_big(f)
	_jobs = f.get("jobs", [])
	growths.queue_redraw()
	glows.queue_redraw()


func _upload(f: Dictionary) -> void:
	var w := int(f.w)
	var h := int(f.h)
	var ts: PackedByteArray = f.ts
	if ts.size() != w * h:
		return
	var img := Image.create_from_data(w, h, false, Image.FORMAT_L8, ts)
	if _tex == null or w != _w or h != _h:
		_tex = ImageTexture.create_from_image(img)
	else:
		_tex.update(img)
	_w = w
	_h = h
	_dv = int(f.get("dv", 0))
	var m := material as ShaderMaterial
	m.set_shader_parameter("ts_tex", _tex)
	m.set_shader_parameter("size", Vector2(w, h))
	uploads += 1
	queue_redraw()


## Scenery instances from the snap (pure function of it: hashed per tile, so a rebuild never moves a growth).
func _build(f: Dictionary) -> void:
	_inst = {}
	instances = 0
	var w := int(f.w)
	var pts: PackedInt32Array = f.pts
	var sd := int(f.get("seed", 1))
	var r: Dictionary = Content.rules().get("g7_fissures", {})
	var fa := float(r.get("fissure_after_s", 60))
	var ca := float(r.get("canyon_after_s", 180))
	var every := maxi(int(r.get("scenery", {}).get("point_every", 2)), 1)
	var j := 0
	while j + 2 < pts.size():
		var tile := pts[j]
		var birth := float(pts[j + 1]) / 20.0
		var fl := pts[j + 2]
		j += 3
		var stg := fl & 7
		if fl & 64 != 0 or stg == 0:
			continue
		var h := _hh(tile, sd)
		if h % every != 0 and stg < 3:
			continue
		var p := Vector2(tile % w, tile / w) + Vector2(0.5, 0.5) + Vector2(float(h % 97) / 97.0 - 0.5, float((h / 97) % 89) / 89.0 - 0.5) * 0.7
		var kind := (h / 7) % KINDS
		match stg:
			1:
				if h % 3 != 0:
					continue
				_add(p, kind, 0, birth, h, 0.8, false)
			2:
				_add(p, kind, 1, birth + fa, h, 0.9, false)
			3:
				_add(p, kind, 2, birth + ca, h, 1.25, true)
				var q := p + Vector2(float((h / 11) % 7) - 3.0, float((h / 77) % 7) - 3.0) * 0.45
				_add(q, (kind + 3) % KINDS, 1 + (h / 13) % 2, birth + ca + 6.0, h / 3, 1.0, true)
	# old creep away from the openings sprouts small growths
	var age: PackedByteArray = f.get("age", PackedByteArray())
	var cw := int(f.get("cw", 0))
	var cs := int(f.get("cs", 4))
	var sc: Dictionary = r.get("scenery", {})
	var amin := int(sc.get("creep_age", 30))
	var chance := int(float(sc.get("creep_chance", 0.4)) * 1000.0)
	if cw > 0:
		for k in age.size():
			var a := age[k]
			if a < amin:
				continue
			var h := _hh(k + 7919, sd)
			if h % 1000 >= chance:
				continue
			var p := Vector2((k % cw) * cs, (k / cw) * cs) + Vector2(float(h % cs) + 0.5, float((h / cs) % cs) + 0.5)
			var sz := 0 if a < amin + 40 else 1
			_add(p, (h / 5) % KINDS, sz, -1000.0 + clampf(float(a - amin) / 40.0, 0.0, 1.0) * 0.0, h, 0.7 + 0.3 * clampf(float(a - amin) / 80.0, 0.0, 1.0), false)


func _add(p: Vector2, kind: int, size: int, t0: float, h: int, sc: float, canyon: bool) -> void:
	var bk := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
	var key := bk.y * 4096 + bk.x
	if not _inst.has(key):
		_inst[key] = []
	(_inst[key] as Array).append([iso(p), kind, size, t0, float(h % 628) / 100.0, sc, canyon])
	instances += 1


func _track_big(f: Dictionary) -> void:
	var now := {}
	for g in f.get("big", []):
		now[int(g[0])] = [iso(Vector2(int(g[1]), int(g[2])) + Vector2(0.5, 0.5)), float(g[4]) / 20.0]
	for id in _big:
		if not now.has(id):
			_shatter.append([_big[id][0], _real()])
			shatters += 1
	_big = now


func _draw() -> void:
	if _tex == null:
		return
	# texture pixel (u, v) = tile (u, v) -> iso canvas ((x - y) * 32, (x + y) * 16)
	draw_set_transform_matrix(Transform2D(Vector2(32.0, 16.0), Vector2(-32.0, 16.0), Vector2.ZERO))
	draw_texture_rect(_tex, Rect2(0, 0, _w, _h), false)


func _zoom() -> float:
	return get_canvas_transform().get_scale().x


## Visible tile buckets (iso inverse of the screen corners, padded for tall sprites).
func _visible_keys() -> Array:
	if _inst.is_empty():   # SWN9: nothing to find (the loop below only collects keys of _inst)
		return []
	var inv := get_canvas_transform().affine_inverse()
	var vr := get_viewport_rect()
	var xs := []
	var ys := []
	for c in [vr.position, vr.position + Vector2(vr.size.x, 0), vr.position + vr.size, vr.position + Vector2(0, vr.size.y)]:
		var q: Vector2 = inv * c
		# iso inverse: x = (qx / 32 + qy / 16) / 2, y = (qy / 16 - qx / 32) / 2
		xs.append((q.x / 32.0 + q.y / 16.0) * 0.5)
		ys.append((q.y / 16.0 - q.x / 32.0) * 0.5)
	var x0 := floori((xs.min() - 4.0) / BUCKET)
	var x1 := floori((xs.max() + 8.0) / BUCKET)
	var y0 := floori((ys.min() - 4.0) / BUCKET)
	var y1 := floori((ys.max() + 8.0) / BUCKET)
	var out := []
	for by in range(maxi(y0, 0), mini(y1, 4095) + 1):
		for bx in range(maxi(x0, 0), mini(x1, 4095) + 1):
			var k := by * 4096 + bx
			if _inst.has(k):
				out.append(k)
	return out


func _rise(t0: float) -> float:
	var r := clampf((_now_s - t0) / RISE_S, 0.0, 1.0)
	return 1.0 - (1.0 - r) * (1.0 - r)


func _draw_growths() -> void:
	drawn = 0
	if _atlas == null or not visible:
		return
	var z := _zoom()
	if z < FAR_ZOOM:
		return
	var only_canyon := z < SCENERY_MIN_ZOOM
	var tr := _real()
	for k in _visible_keys():
		for g in _inst[k]:
			if only_canyon and not g[6]:
				continue
			var rise := _rise(g[3])
			if rise <= 0.02:
				continue
			var sway: float = sin(tr * 0.9 + g[4]) * 0.035 * (1.0 if g[1] != 0 and g[1] != 7 else 0.3)
			var s: float = g[5]
			growths.draw_set_transform(g[0] + Vector2(0, 4), sway, Vector2(s, s * rise))
			var src := Rect2(Vector2(g[2] * 2 * CELL.x, g[1] * CELL.y), CELL)
			growths.draw_texture_rect_region(_atlas, Rect2(-FOOT, CELL), src)
			drawn += 1
	growths.draw_set_transform(Vector2.ZERO)


func _draw_glows() -> void:
	var tr := _real()
	var z := _zoom()
	if _atlas != null and z >= SCENERY_MIN_ZOOM:
		for k in _visible_keys():
			for g in _inst[k]:
				var rise := _rise(g[3])
				if rise <= 0.02:
					continue
				var pulse: float = 0.45 + 0.55 * (0.5 + 0.5 * sin(tr * 2.2 + g[4] * 3.0))
				var sway: float = sin(tr * 0.9 + g[4]) * 0.035 * (1.0 if g[1] != 0 and g[1] != 7 else 0.3)
				var s: float = g[5]
				glows.draw_set_transform(g[0] + Vector2(0, 4), sway, Vector2(s, s * rise))
				var src := Rect2(Vector2((g[2] * 2 + 1) * CELL.x, g[1] * CELL.y), CELL)
				glows.draw_texture_rect_region(_atlas, Rect2(-FOOT, CELL), src, Color(1, 1, 1, pulse))
		glows.draw_set_transform(Vector2.ZERO)
	# big growth auras (the sprite itself is the entity layer's)
	for id in _big:
		var p: Vector2 = _big[id][0]
		var age: float = _now_s - float(_big[id][1])
		var pl := 0.5 + 0.5 * sin(tr * 1.6 + float(id))
		glows.draw_circle(p + Vector2(0, -6), 26.0 + 6.0 * pl, Color(0.15, 0.55, 0.65, 0.18 + 0.12 * pl))
		if age < 8.0:   # rising out of the ground: a glow column and dust ring
			var a := 1.0 - age / 8.0
			glows.draw_rect(Rect2(p + Vector2(-6, -120 * (1.0 - a) - 20), Vector2(12, 120 * (1.0 - a) + 20)), Color(0.3, 0.9, 1.0, 0.35 * a))
			glows.draw_arc(p, 30.0 + 40.0 * (1.0 - a), 0, TAU, 28, Color(0.6, 0.5, 0.45, 0.5 * a), 3.0)
	# shatter: shards flying out, flash
	var keep := []
	for sh in _shatter:
		var age2 := tr - float(sh[1])
		if age2 > SHATTER_S:
			continue
		keep.append(sh)
		var a2 := 1.0 - age2 / SHATTER_S
		var p2: Vector2 = sh[0]
		glows.draw_circle(p2 + Vector2(0, -30), 50.0 * (1.0 - a2) + 10.0, Color(0.5, 0.95, 1.0, 0.45 * a2))
		for i in 14:
			var ang := TAU * float(i) / 14.0 + float(i % 3) * 0.3
			var d := (40.0 + 25.0 * float(i % 4)) * (1.0 - a2)
			var q := p2 + Vector2(cos(ang) * d, sin(ang) * d * 0.5 - 60.0 * (1.0 - a2) + 90.0 * pow(1.0 - a2, 2.0) - 30.0)
			glows.draw_line(q, q + Vector2(cos(ang), sin(ang) * 0.5) * 7.0, Color(0.35, 0.9, 1.0, a2), 2.0)
	_shatter = keep
	# span jobs: progress line between the banks
	for jb in _jobs:
		var a3 := iso(Vector2(float(jb[0]) + 0.5, float(jb[1]) + 0.5))
		var b3 := iso(Vector2(float(jb[2]) + 0.5, float(jb[3]) + 0.5))
		glows.draw_line(a3, b3, Color(0.9, 0.7, 0.2, 0.35), 3.0)
		glows.draw_line(a3, a3.lerp(b3, clampf(float(jb[4]), 0.0, 1.0)), Color(1.0, 0.8, 0.25, 0.9), 4.0)
