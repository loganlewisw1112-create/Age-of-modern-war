extends Node2D
## Fog-of-war overlay (owner: R4-render, G3b; was agent D). The player's visible/explored byte
## arrays upload straight into two W x H L8 textures (Image.set_data, no per-cell GDScript loop, so
## a 256x256 map costs the same as 96x96). A shader turns them into fog alpha per cell
## (unexplored 255, explored-not-visible 120, visible 0) and filters bilinearly between cell
## centres, which matches the old LA8 + linear-filter look. Drawn through the iso transform so
## each texel covers exactly one cell diamond. Re-uploaded only when the arrays change.

const UNEXPLORED_A := 255
const EXPLORED_A := 120

const SHADER := """
shader_type canvas_item;
uniform sampler2D vis_tex : filter_nearest;
uniform sampler2D exp_tex : filter_nearest;
uniform float explored_a = 0.470588;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float grey_on = 1.0;
uniform float grey_dim = 0.62;
float unexp_at(ivec2 c, ivec2 sz) {
	c = clamp(c, ivec2(0), sz - ivec2(1));
	return texelFetch(exp_tex, c, 0).r > 0.0 ? 0.0 : 1.0;
}
float fog_at(ivec2 c, ivec2 sz) {
	c = clamp(c, ivec2(0), sz - ivec2(1));
	float v = texelFetch(vis_tex, c, 0).r;
	float e = texelFetch(exp_tex, c, 0).r;
	return v > 0.0 ? 0.0 : (e > 0.0 ? explored_a : 1.0);
}
// G7 (LOOK7): grey fog. Seen-before cells show what is under them (the terrain and the remembered buildings
// drawn below) desaturated and dimmed; never-explored cells stay black; visible cells clear. a = old black
// alpha (0 visible .. explored_a .. 1 unexplored), u = unexplored share 0..1. grey_on = 0 restores the dark fog.
vec4 grey_fog(float a, float u, vec2 suv) {
	if (grey_on < 0.5) {
		return vec4(0.0, 0.0, 0.0, a);
	}
	float fogged = clamp(a / explored_a, 0.0, 1.0);
	vec3 bg = texture(screen_tex, suv).rgb;
	float l = dot(bg, vec3(0.299, 0.587, 0.114));
	vec3 g = vec3(l * grey_dim) + vec3(0.015, 0.02, 0.03);
	vec3 col = mix(g, vec3(0.0), u);
	return vec4(col, max(fogged, u));
}
void fragment() {
	ivec2 sz = textureSize(vis_tex, 0);
	vec2 p = UV * vec2(sz) - 0.5;
	ivec2 i = ivec2(floor(p));
	vec2 f = fract(p);
	float a = mix(mix(fog_at(i, sz), fog_at(i + ivec2(1, 0), sz), f.x),
		mix(fog_at(i + ivec2(0, 1), sz), fog_at(i + ivec2(1, 1), sz), f.x), f.y);
	COLOR = grey_fog(a, mix(mix(unexp_at(i, sz), unexp_at(i + ivec2(1, 0), sz), f.x),
		mix(unexp_at(i + ivec2(0, 1), sz), unexp_at(i + ivec2(1, 1), sz), f.x), f.y), SCREEN_UV);
}
"""

## G6 (ELEV-VIEW): on a map with height, fog sits on the raised tiles. HSHADER is drawn over the map's canvas
## box; per pixel it walks the view ray from the top level down (quarter-level steps, lift = ViewUtil.lift_px)
## and takes the fog of the first cell whose level reaches the ray, then filters it bilinearly as before.
## fog_cell_at() is the same walk in GDScript. Flat maps keep the original texel-per-cell draw.
const ViewUtil = preload("res://presentation/view/view_util.gd")
const HSHADER := """
shader_type canvas_item;
uniform sampler2D vis_tex : filter_nearest;
uniform sampler2D exp_tex : filter_nearest;
uniform sampler2D h_tex : filter_nearest;
uniform float explored_a = 0.470588;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float grey_on = 1.0;
uniform float grey_dim = 0.62;
uniform float level_px;   // set from ViewUtil.level_px in _sync_height (no literal lift here)
varying vec2 cpos;
float unexp_at(ivec2 c, ivec2 sz) {
	c = clamp(c, ivec2(0), sz - ivec2(1));
	return texelFetch(exp_tex, c, 0).r > 0.0 ? 0.0 : 1.0;
}
float fog_at(ivec2 c, ivec2 sz) {
	c = clamp(c, ivec2(0), sz - ivec2(1));
	float v = texelFetch(vis_tex, c, 0).r;
	float e = texelFetch(exp_tex, c, 0).r;
	return v > 0.0 ? 0.0 : (e > 0.0 ? explored_a : 1.0);
}
// G7 (LOOK7): grey fog. Seen-before cells show what is under them (the terrain and the remembered buildings
// drawn below) desaturated and dimmed; never-explored cells stay black; visible cells clear. a = old black
// alpha (0 visible .. explored_a .. 1 unexplored), u = unexplored share 0..1. grey_on = 0 restores the dark fog.
vec4 grey_fog(float a, float u, vec2 suv) {
	if (grey_on < 0.5) {
		return vec4(0.0, 0.0, 0.0, a);
	}
	float fogged = clamp(a / explored_a, 0.0, 1.0);
	vec3 bg = texture(screen_tex, suv).rgb;
	float l = dot(bg, vec3(0.299, 0.587, 0.114));
	vec3 g = vec3(l * grey_dim) + vec3(0.015, 0.02, 0.03);
	vec3 col = mix(g, vec3(0.0), u);
	return vec4(col, max(fogged, u));
}
void vertex() {
	cpos = VERTEX;
}
void fragment() {
	ivec2 sz = textureSize(vis_tex, 0);
	vec2 hit = vec2(0.0);
	bool found = false;
	for (int k = 12; k >= 0; k--) {
		float lv = float(k) * 0.25;
		vec2 s = cpos + vec2(0.0, (lv - 1.0) * level_px);
		vec2 wp = vec2((s.x / 32.0 + s.y / 16.0) * 0.5, (s.y / 16.0 - s.x / 32.0) * 0.5);
		ivec2 c = ivec2(floor(wp));
		if (c.x < 0 || c.y < 0 || c.x >= sz.x || c.y >= sz.y) {
			continue;
		}
		if (texelFetch(h_tex, c, 0).r * 255.0 >= lv - 0.01) {
			hit = wp;
			found = true;
			break;
		}
	}
	if (!found) {
		COLOR = vec4(0.0);
	} else {
		vec2 p = hit - 0.5;
		ivec2 i = ivec2(floor(p));
		vec2 f = fract(p);
		float a = mix(mix(fog_at(i, sz), fog_at(i + ivec2(1, 0), sz), f.x),
			mix(fog_at(i + ivec2(0, 1), sz), fog_at(i + ivec2(1, 1), sz), f.x), f.y);
		COLOR = grey_fog(a, mix(mix(unexp_at(i, sz), unexp_at(i + ivec2(1, 0), sz), f.x),
			mix(unexp_at(i + ivec2(0, 1), sz), unexp_at(i + ivec2(1, 1), sz), f.x), f.y), SCREEN_UV);
	}
}
"""

var mv
var _w := 0
var _h := 0
var height_on := false             # G6: drawing through HSHADER
var _hm: Dictionary = {}
var _h_img: Image
var _h_tex: ImageTexture
var _hver := -1
var _vis_img: Image
var _exp_img: Image
var _vis_tex: ImageTexture
var _exp_tex: ImageTexture
var _last_vis := PackedByteArray()
var _last_exp := PackedByteArray()
var rebuilds := 0
# G7 (LOOK7): grey fog (shader reads the screen under it) + fading last-known enemy markers (snap.intel)
const MARK_LIFE := 90.0        # s until a last-known marker has faded out completely
const MARK_MIN_A := 0.06       # markers fainter than this are not drawn
var grey := not OS.get_cmdline_user_args().has("--g7-look-off")   # debug A/B: dark G6.1 fog
var markers: Node2D = null
var markers_drawn := 0
var _mark_tick := -1


class LastKnown:
	extends Node2D
	var fl

	func _draw() -> void:
		if fl != null:
			fl._draw_markers(self)


## Marker alpha from the contact's confidence (0..1) and age (s): fades with both.
static func marker_alpha(conf: float, age: float) -> float:
	return clampf(conf, 0.0, 1.0) * clampf(1.0 - age / MARK_LIFE, 0.0, 1.0)


func set_grey(on: bool) -> void:
	grey = on
	_apply_grey()


func _apply_grey() -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("grey_on", 1.0 if grey else 0.0)


func setup(view) -> void:
	mv = view
	var world = mv.get("_world")  # never mv.world: that getter forces a sim join
	_w = int(world.map.w)
	_h = int(world.map.h)
	_vis_img = Image.create(_w, _h, false, Image.FORMAT_L8)
	_exp_img = Image.create(_w, _h, false, Image.FORMAT_L8)
	_vis_tex = ImageTexture.create_from_image(_vis_img)
	_exp_tex = ImageTexture.create_from_image(_exp_img)
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("vis_tex", _vis_tex)
	m.set_shader_parameter("exp_tex", _exp_tex)
	m.set_shader_parameter("explored_a", float(EXPLORED_A) / 255.0)
	material = m
	_apply_grey()
	markers = LastKnown.new()
	markers.name = "LastKnown"
	markers.fl = self
	markers.use_parent_material = false
	add_child(markers)
	_sync_height()
	refresh(true)


func refresh(force: bool = false) -> void:
	_sync_height()
	var sn = mv.get("snap") if mv != null else null
	if markers != null and sn is Dictionary and int(sn.get("tick", -1)) != _mark_tick:
		_mark_tick = int(sn.get("tick", -1))
		markers.queue_redraw()
	var f: Dictionary = mv.fog_of(mv.player_fid)  # G4: snapshot fog (safe during a step)
	if f.is_empty():
		return
	var vis: PackedByteArray = f.visible
	var expl: PackedByteArray = f.explored
	if vis.size() != _w * _h or expl.size() != _w * _h:
		return
	var vch := force or vis != _last_vis
	var ech := force or expl != _last_exp
	if not vch and not ech:
		return
	if vch:
		_last_vis = vis.duplicate()
		_vis_img.set_data(_w, _h, false, Image.FORMAT_L8, _last_vis)
		_vis_tex.update(_vis_img)
	if ech:
		_last_exp = expl.duplicate()
		_exp_img.set_data(_w, _h, false, Image.FORMAT_L8, _last_exp)
		_exp_tex.update(_exp_img)
	rebuilds += 1
	queue_redraw()


## G6: pick up the terrain layer's height map (also when the editor changed it) and swap the shader to match.
func _sync_height(force: bool = false) -> void:
	var tl = mv.get("terrain_layer") if mv != null else null
	var ver := int(tl.get("height_ver")) if tl != null and tl.get("height_ver") != null else 0
	if not force and ver == _hver:
		return
	_hver = ver
	if tl != null and tl.has_method("height_map"):
		_hm = tl.height_map()
	else:
		var ww = mv.get("_world") if mv != null else null  # never mv.world: that getter forces a sim join
		if ww != null and ww.map is Dictionary:
			_hm = ViewUtil.height_map_of(ww.map)
	var on := ViewUtil.has_height(_hm) and int(_hm.w) == _w and int(_hm.h) == _h
	if on:
		_h_img = Image.create_from_data(_w, _h, false, Image.FORMAT_L8, (_hm.height as PackedByteArray).duplicate())
		if _h_tex == null or _h_tex.get_size() != Vector2(_w, _h):
			_h_tex = ImageTexture.create_from_image(_h_img)
		else:
			_h_tex.update(_h_img)
	if on != height_on or force:
		height_on = on
		var sh := Shader.new()
		sh.code = HSHADER if on else SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("vis_tex", _vis_tex)
		m.set_shader_parameter("exp_tex", _exp_tex)
		m.set_shader_parameter("explored_a", float(EXPLORED_A) / 255.0)
		if on:
			m.set_shader_parameter("h_tex", _h_tex)
			m.set_shader_parameter("level_px", ViewUtil.level_px)
		material = m
		_apply_grey()
	elif on:
		(material as ShaderMaterial).set_shader_parameter("h_tex", _h_tex)
	queue_redraw()


## G6: the cell whose fog shades canvas px s (the HSHADER walk in GDScript; (-1, -1) = off the map).
func fog_cell_at(s: Vector2) -> Vector2i:
	for k in range(ViewUtil.MAX_LEVEL * 4, -1, -1):
		var lv := k * 0.25
		var wp := ViewUtil.iso_inv(s + Vector2(0.0, ViewUtil.lift_px(lv)))
		var c := Vector2i(floori(wp.x), floori(wp.y))
		if c.x < 0 or c.y < 0 or c.x >= _w or c.y >= _h:
			continue
		if float(ViewUtil.cell_level(_hm, c)) >= lv - 0.01:
			return c
	return Vector2i(-1, -1)


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_body()
	preload("res://presentation/view/view_util.gd").prof_add("d_fog", t0)


func _draw_body() -> void:
	if _vis_tex == null:
		return
	if height_on:  # G6: the canvas box of the map incl. the top level's lift; HSHADER finds the cell per pixel
		var up := ViewUtil.lift_px(ViewUtil.MAX_LEVEL) + 32.0
		draw_rect(Rect2(Vector2(-_h * 32.0, -up), Vector2((_w + _h) * 32.0, (_w + _h) * 16.0 + up + ViewUtil.level_px + 32.0)), Color.WHITE)
		return
	# texel (x, y) -> cell diamond: screen = x*(32,16) + y*(-32,16)
	draw_set_transform_matrix(Transform2D(Vector2(32, 16), Vector2(-32, 16), Vector2.ZERO))
	draw_texture_rect(_vis_tex, Rect2(Vector2.ZERO, Vector2(_w, _h)), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)



## G7: last-known enemy markers (believed contacts of the player's side, snap.intel) on cells not visible now; each
## fades with age and confidence. Vehicles a hollow square, infantry / other a cross, buildings a diamond.
func _draw_markers(ci: CanvasItem) -> void:
	markers_drawn = 0
	var sn = mv.get("snap") if mv != null else null
	if not (sn is Dictionary):
		return
	var lst = (sn.get("intel", {}) as Dictionary).get(int(mv.player_fid))
	if not (lst is Array):
		return
	for c in lst:
		var p: Vector2 = c[0]
		var cell := Vector2i(floori(p.x), floori(p.y))
		if cell.x < 0 or cell.y < 0 or cell.x >= _w or cell.y >= _h:
			continue
		if not _last_vis.is_empty() and _last_vis[cell.y * _w + cell.x] != 0:
			continue
		var a := marker_alpha(float(c[1]), float(c[2]))
		if a < MARK_MIN_A:
			continue
		var s := Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)
		if height_on:
			s.y -= ViewUtil.lift_px(float(ViewUtil.cell_level(_hm, cell)))
		var col := Color(0.95, 0.32, 0.25, a)
		var kind := String(c[3])
		if kind == "vehicle" or kind == "air":
			ci.draw_rect(Rect2(s - Vector2(6, 4), Vector2(12, 8)), col, false, 1.5)
		elif kind == "building":
			ci.draw_polyline(PackedVector2Array([s + Vector2(0, -7), s + Vector2(10, 0), s + Vector2(0, 7), s + Vector2(-10, 0), s + Vector2(0, -7)]), col, 1.5)
		else:
			ci.draw_line(s + Vector2(-5, -3), s + Vector2(5, 3), col, 1.5)
			ci.draw_line(s + Vector2(-5, 3), s + Vector2(5, -3), col, 1.5)
		ci.draw_circle(s, 1.5, Color(col.r, col.g, col.b, a * 0.8))
		markers_drawn += 1
