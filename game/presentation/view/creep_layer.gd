extends Node2D
## G7 (CREEP7) creep on the ground. PRESENTATION ONLY: reads snap.creep (Creep.snap(w), copied into the render
## snapshot by render_snap.gd, CR to LOOK7) and never touches the sim.
## One quad for the whole map: the creep grid (cw x ch cells of cs tiles) is uploaded as an L8 texture straight from
## the snapshot bytes (no per-cell loop), flags as a second L8 texture, and a canvas shader draws
##   - creep: a dark nanite slick with a pulsing vein network (Machine style), fading in at the creep edge;
##   - purged (sterile) ground: pale salted ground that recovers slowly toward a faint tint (purge_tex holds the view
##     time each cell turned sterile; updated only when the flags change, i.e. on a purge);
##   - barrier lines: an amber band; burnt / cratered firebreaks: left to the terrain and decal layers.
## Revealed seeds get a small pulsing marker. Cost: one draw call; textures re-upload only when snap.creep.dv changes.
## Ground height is not applied (the quad is flat); creep on raised ground is drawn at ground level 0.
## Wiring (ORCH, match_view.gd): creep_layer = CreepLayer.new(); z_index 0, added right after terrain_layer;
##   each frame creep_layer.refresh(snap).

const SHADER := """
shader_type canvas_item;
uniform sampler2D flags_tex : filter_nearest;
uniform sampler2D purge_tex : filter_nearest;
uniform vec2 grid = vec2(128.0, 128.0);
uniform float on_level = 0.25;
uniform float now = 0.0;
uniform float recover_s = 120.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// distance between the two nearest jittered points: ~0 on the cell walls of a Voronoi net (organic veins)
float net(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return sqrt(d2) - sqrt(d1);
}

void fragment() {
	float v = texture(TEXTURE, UV).r;
	int fi = int(texture(flags_tex, UV).r * 255.0 + 0.5);
	vec2 cell = UV * grid;
	vec4 col = vec4(0.0);
	if (v > 0.01) {
		float grain = hash2(floor(cell * 6.0)).x;
		float a = smoothstep(on_level * (0.4 + 0.5 * grain), on_level * 1.2, v);
		float big = smoothstep(0.10, 0.0, net(cell * 0.9));
		float fine = smoothstep(0.06, 0.0, net(cell * 2.6 + 7.0)) * 0.5;
		float pulse = 0.5 + 0.5 * sin(TIME * 2.2 - length(cell) * 0.35);
		vec3 slick = mix(vec3(0.10, 0.07, 0.13), vec3(0.16, 0.10, 0.20), grain);
		vec3 glow = vec3(0.35, 0.95, 1.00);
		float lit = clamp(big * (0.45 + 0.55 * pulse) + fine * 0.6, 0.0, 1.0) * clamp(v * 1.4, 0.0, 1.0);
		col = vec4(mix(slick, glow, lit), mix(0.42, 0.85, lit) * a);
	}
	if ((fi & 1) != 0) {
		float rec = clamp((now - texture(purge_tex, UV).r) / recover_s, 0.0, 1.0);
		col = vec4(mix(vec3(0.86, 0.84, 0.74), vec3(0.52, 0.50, 0.42), rec), mix(0.42, 0.12, rec));
		if ((fi & 8) != 0) {
			col = vec4(0.98, 0.72, 0.18, 0.72);
		}
	}
	COLOR = col;
}
"""

var _dv := -1
var _fl_last := PackedByteArray()
var _cs := 4
var _cw := 0
var _ch := 0
var _tex: ImageTexture
var _ftex: ImageTexture
var _ptex: ImageTexture
var _pimg: Image
var _seeds: Array = []
var uploads := 0
var markers: Node2D   # revealed seeds (own canvas item: the creep shader must not touch them)


func _init() -> void:
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	material = m
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visible = false
	markers = Node2D.new()
	add_child(markers)
	markers.draw.connect(_draw_markers)


static func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## snap: the render snapshot (reads snap.creep). Cheap when nothing changed.
func refresh(snap: Dictionary) -> void:
	var c: Dictionary = snap.get("creep", {})
	if c.is_empty():
		visible = false
		return
	visible = true
	(material as ShaderMaterial).set_shader_parameter("now", _now())
	if int(c.get("dv", 0)) == _dv and int(c.cw) == _cw:
		return
	_dv = int(c.get("dv", 0))
	_upload(c)
	queue_redraw()
	markers.queue_redraw()


func _upload(c: Dictionary) -> void:
	var cw := int(c.cw)
	var ch := int(c.ch)
	var v: PackedByteArray = c.v
	var fl: PackedByteArray = c.fl
	if v.size() != cw * ch or fl.size() != cw * ch:
		return
	var resized := cw != _cw or ch != _ch
	_cw = cw
	_ch = ch
	_cs = int(c.cs)
	var img := Image.create_from_data(cw, ch, false, Image.FORMAT_L8, v)
	var fimg := Image.create_from_data(cw, ch, false, Image.FORMAT_L8, fl)
	if resized or _tex == null:
		_tex = ImageTexture.create_from_image(img)
		_ftex = ImageTexture.create_from_image(fimg)
		_pimg = Image.create(cw, ch, false, Image.FORMAT_RF)
		_pimg.fill(Color(-1000.0, 0, 0))
		_ptex = ImageTexture.create_from_image(_pimg)
		_fl_last = PackedByteArray()
		_fl_last.resize(cw * ch)
		_fl_last.fill(0)
	else:
		_tex.update(img)
		_ftex.update(fimg)
	if fl != _fl_last:
		var now := _now()
		for k in fl.size():
			if fl[k] & 1 != 0 and _fl_last[k] & 1 == 0:
				_pimg.set_pixel(k % cw, k / cw, Color(now, 0, 0))
		_ptex.update(_pimg)
		_fl_last = fl.duplicate()
	var m := material as ShaderMaterial
	m.set_shader_parameter("flags_tex", _ftex)
	m.set_shader_parameter("purge_tex", _ptex)
	m.set_shader_parameter("grid", Vector2(cw, ch))
	m.set_shader_parameter("on_level", float(c.get("on", 64)) / 255.0)
	_seeds = c.get("seeds", [])
	uploads += 1


func _draw() -> void:
	if _tex == null:
		return
	var cs := float(_cs)
	# texture pixel (u, v) -> tile (u * cs, v * cs) -> iso canvas ((x - y) * 32, (x + y) * 16)
	draw_set_transform_matrix(Transform2D(Vector2(32.0 * cs, 16.0 * cs), Vector2(-32.0 * cs, 16.0 * cs), Vector2.ZERO))
	draw_texture_rect(_tex, Rect2(0, 0, _cw, _ch), false)


func _draw_markers() -> void:
	for sd in _seeds:
		var p: Vector2 = sd.pos
		var iso := Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)
		var col := Color(1.0, 0.35, 0.25, 0.9) if String(sd.kind) == "core" else Color(0.95, 0.25, 0.85, 0.9)
		markers.draw_arc(iso, 14.0, 0.0, TAU, 20, col, 2.0)
		markers.draw_circle(iso, 4.0, col)
