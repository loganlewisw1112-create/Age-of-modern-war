extends Node2D
## Fog-of-war overlay (owner: agent D). A 96x96 LA8 image (alpha = fog density) drawn through
## the iso transform so each texel covers exactly one cell diamond; linear filtering softens
## the edges. Rebuilt only when the player's visible/explored arrays change.

const UNEXPLORED_A := 255
const EXPLORED_A := 120

var mv
var _img: Image
var _tex: ImageTexture
var _last_vis := PackedByteArray()
var _last_exp := PackedByteArray()
var rebuilds := 0


func setup(view) -> void:
	mv = view
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var w := int(mv.world.map.w)
	var h := int(mv.world.map.h)
	_img = Image.create(w, h, false, Image.FORMAT_LA8)
	_tex = ImageTexture.create_from_image(_img)
	refresh(true)


func refresh(force: bool = false) -> void:
	var f: Dictionary = mv.world.fog.get(mv.player_fid, {})
	if f.is_empty():
		return
	var vis: PackedByteArray = f.visible
	var expl: PackedByteArray = f.explored
	if not force and vis == _last_vis and expl == _last_exp:
		return
	_last_vis = vis.duplicate()
	_last_exp = expl.duplicate()
	var n := vis.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var a := 0
		if vis[i] == 0:
			a = EXPLORED_A if expl[i] == 1 else UNEXPLORED_A
		data[i * 2] = 0
		data[i * 2 + 1] = a
	_img.set_data(int(mv.world.map.w), int(mv.world.map.h), false, Image.FORMAT_LA8, data)
	_tex.update(_img)
	rebuilds += 1
	queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	# texel (x, y) -> cell diamond: screen = x*(32,16) + y*(-32,16)
	draw_set_transform_matrix(Transform2D(Vector2(32, 16), Vector2(-32, 16), Vector2.ZERO))
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(_img.get_width(), _img.get_height())), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
