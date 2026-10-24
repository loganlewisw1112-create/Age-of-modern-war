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
float fog_at(ivec2 c, ivec2 sz) {
	c = clamp(c, ivec2(0), sz - ivec2(1));
	float v = texelFetch(vis_tex, c, 0).r;
	float e = texelFetch(exp_tex, c, 0).r;
	return v > 0.0 ? 0.0 : (e > 0.0 ? explored_a : 1.0);
}
void fragment() {
	ivec2 sz = textureSize(vis_tex, 0);
	vec2 p = UV * vec2(sz) - 0.5;
	ivec2 i = ivec2(floor(p));
	vec2 f = fract(p);
	float a = mix(mix(fog_at(i, sz), fog_at(i + ivec2(1, 0), sz), f.x),
		mix(fog_at(i + ivec2(0, 1), sz), fog_at(i + ivec2(1, 1), sz), f.x), f.y);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""

var mv
var _w := 0
var _h := 0
var _vis_img: Image
var _exp_img: Image
var _vis_tex: ImageTexture
var _exp_tex: ImageTexture
var _last_vis := PackedByteArray()
var _last_exp := PackedByteArray()
var rebuilds := 0


func setup(view) -> void:
	mv = view
	_w = int(mv.world.map.w)
	_h = int(mv.world.map.h)
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
	refresh(true)


func refresh(force: bool = false) -> void:
	var f: Dictionary = mv.world.fog.get(mv.player_fid, {})
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


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_body()
	preload("res://presentation/view/view_util.gd").prof_add("d_fog", t0)


func _draw_body() -> void:
	if _vis_tex == null:
		return
	# texel (x, y) -> cell diamond: screen = x*(32,16) + y*(-32,16)
	draw_set_transform_matrix(Transform2D(Vector2(32, 16), Vector2(-32, 16), Vector2.ZERO))
	draw_texture_rect(_vis_tex, Rect2(Vector2.ZERO, Vector2(_w, _h)), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
