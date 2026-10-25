extends SceneTree
## Composes battle scenes from rendered proposal sprites (<scratch>/g6/art/<module>/manifest.json) and shipped
## game sprites (res://assets/generated, res://assets/art/g5_units, res://assets/art/g5_bld), on game terrain.
## Spec: <scratch>/g6/scenes.json  [{id, w, h, ground, bands:[{tile, from, to}], parts:[[id, frame, row, x, y, enemy?, alt?]]}]
##   bands: iso rows (i + j) from..to painted with another tile (rivers, coasts). x, y = sprite pivot in scene px.
## Output: <scratch>/g6/art/scenes/<id>.png at 2x.
const H = preload("g6_lib.gd")
const P = preload("res://tools/art/pix.gd")

var _srcs: Array = []   # [{base: dir, man: Dictionary}]


func _init() -> void:
	var here: String = (get_script() as Script).resource_path.get_base_dir()
	var root := here.get_base_dir()
	for d in DirAccess.get_directories_at(root.path_join("art")):
		var mf := root.path_join("art").path_join(d).path_join("manifest.json")
		if FileAccess.file_exists(mf) and d != "ex":
			_srcs.append({"base": mf.get_base_dir(), "man": JSON.parse_string(FileAccess.get_file_as_string(mf))})
	for g in ["res://assets/generated/", "res://assets/art/g5_units/", "res://assets/art/g5_bld/"]:
		_srcs.append({"base": ProjectSettings.globalize_path(g), "man": JSON.parse_string(FileAccess.get_file_as_string(g + "manifest.json"))})
	var specs: Array = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("scenes.json")))
	DirAccess.make_dir_recursive_absolute(root.path_join("art/scenes"))
	for sc in specs:
		var w := int(sc.w)
		var h := int(sc.h)
		var img := _ground(w, h, sc)
		var parts: Array = sc.parts.duplicate()
		parts.sort_custom(func(a, b): return float(a[4]) < float(b[4]))
		var miss: Array = []
		for p in parts:
			var spr := _sprite(String(p[0]), String(p[1]), int(p[2]), p.size() > 5 and bool(p[5]))
			if spr.is_empty():
				miss.append(p[0])
				continue
			var alt := int(p[6]) if p.size() > 6 else 0
			var x := int(p[3]) - int(spr.pivot[0])
			var y := int(p[4]) - int(spr.pivot[1]) - alt
			if alt > 0:
				var sc2 = P.Canvas.new(w, h)
				sc2.ellipse(float(p[3]), float(p[4]), spr.img.get_width() * 0.28, spr.img.get_width() * 0.1, Color.BLACK, true)
				sc2.flush_shadow(Color(0.04, 0.05, 0.03, 0.36))
				img.blend_rect(sc2.img, Rect2i(0, 0, w, h), Vector2i.ZERO)
			img.blend_rect(spr.img, Rect2i(Vector2i.ZERO, spr.img.get_size()), Vector2i(x, y))
		img.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
		img.save_png(root.path_join("art/scenes").path_join(String(sc.id) + ".png"))
		print("G6SCENE %s ok parts=%d missing=%s" % [sc.id, parts.size() - miss.size(), ",".join(PackedStringArray(miss))])
	quit(0)


func _img(base: String, rel: String) -> Image:
	var im := Image.load_from_file(base.path_join(rel))
	if im == null:
		return null
	im.convert(Image.FORMAT_RGBA8)
	return im


func _sprite(id: String, frame_name: String, row: int, enemy: bool) -> Dictionary:
	var col: Color = H.ENEMY if enemy else H.TEAM
	for s in _srcs:
		var man: Dictionary = s.man
		for sec in ["vehicles", "infantry"]:
			if man.has(sec) and man[sec].has(id):
				var e: Dictionary = man[sec][id]
				var c := maxi(0, (e.frames as Array).find(frame_name))
				var img := H.frame(_img(s.base, e.file), int(e.fw), int(e.fh), c, row)
				var msk := H.frame(_img(s.base, e.mask), int(e.fw), int(e.fh), c, row)
				return {"img": H.tint(img, msk, col), "pivot": e.pivot}
		if man.has("buildings") and man.buildings.has(id):
			var b: Dictionary = man.buildings[id]
			var r: Dictionary = {}
			if b.has("rots"):
				r = b.rots[str(row % 2)]
			elif b.has("states"):
				r = b.states.get(frame_name, b.states.get("built", {}))
			if r.is_empty():
				continue
			var im := _img(s.base, r.file)
			var mk: Image = _img(s.base, r.mask) if r.has("mask") else null
			return {"img": H.tint(im, mk, col), "pivot": b.pivot}
	return {}


func _ground(w: int, h: int, sc: Dictionary) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color8(70, 76, 50))
	var cx := w / 2
	var cy := h / 2
	var bands: Array = sc.get("bands", [])
	for i in range(-14, 15):
		for j in range(-14, 15):
			var tx := cx + (i - j) * 32 - 32
			var ty := cy + (i + j) * 16 - 16
			if tx < -64 or ty < -32 or tx > w or ty > h:
				continue
			var nm := String(sc.ground)
			for bd in bands:
				var u := i + j if String(bd.get("axis", "ij")) == "ij" else i - j
				if u >= int(bd.from) and u <= int(bd.to):
					nm = String(bd.tile)
			var set: Array = H.tiles(nm)
			if set.is_empty():
				set = H.tiles("grass")
			var t: Image = set[P.hi(i + 40, j + 40, 7, set.size())]
			img.blend_rect(t, Rect2i(0, 0, 64, 32), Vector2i(tx, ty))
	return img
