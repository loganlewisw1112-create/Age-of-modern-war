extends SceneTree
## Renders the art the G5 slice has already produced in the repo (read-only) as team-tinted, cropped PNGs for
## the report's "on the table now" strip: <scratch>/g6/art/now/<id>.png + now.json {id: {kind, w, h}}.
const H = preload("g6_lib.gd")
const U5 := "res://assets/art/g5_units/"
const B5 := "res://assets/art/g5_bld/"


func _init() -> void:
	var here: String = (get_script() as Script).resource_path.get_base_dir()
	var dst := here.get_base_dir().path_join("art/now")
	DirAccess.make_dir_recursive_absolute(dst)
	var meta := {}
	var mu: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(U5 + "manifest.json"))
	for sec in ["infantry", "vehicles"]:
		for id in mu[sec]:
			var e: Dictionary = mu[sec][id]
			var row := 1 if sec == "infantry" else 0
			var img := H.frame(_img(U5 + e.file), int(e.fw), int(e.fh), 0, row)
			var msk := H.frame(_img(U5 + e.mask), int(e.fw), int(e.fh), 0, row)
			meta[id] = _save(dst, id, H.tint(img, msk, H.TEAM), "unit")
	var mb: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(B5 + "manifest.json"))
	for id in mb.buildings:
		var st: Dictionary = mb.buildings[id].states
		var key := "built"
		for k in ["rot_0", "lvl_0", "water_0"]:
			if st.has(k):
				key = k
		var s: Dictionary = st[key]
		meta[id] = _save(dst, id, H.tint(_img(B5 + s.file), _img(B5 + s.mask) if s.has("mask") else null, H.TEAM), "building")
	var f := FileAccess.open(dst.path_join("now.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	print("G6NOW ok n=%d" % meta.size())
	quit(0)


func _img(p: String) -> Image:
	var im := Image.load_from_file(ProjectSettings.globalize_path(p))
	im.convert(Image.FORMAT_RGBA8)
	return im


func _save(dst: String, id: String, img: Image, kind: String) -> Dictionary:
	var r := img.get_used_rect()
	var c := img.get_region(r) if r.size.x > 0 else img
	c.save_png(dst.path_join(id + ".png"))
	return {"kind": kind, "w": c.get_width(), "h": c.get_height()}
