extends SceneTree
## G6 proposal art runner (scratch only). Usage, from the game folder:
##   godot --headless --path . -s <scratch>/g6/gd/g6_gen.gd -- <module> [<module> ...]
## For each module <scratch>/g6/gd/<module>.gd: build(out) with the game's art libraries, then write
##   <scratch>/g6/art/<module>/...      full sheets + masks + manifest.json (same schema as the game)
##   <scratch>/g6/art/show/<id>.png     240x150 showcase plate (terrain + team-tinted sprite, integer zoom)
##   <scratch>/g6/art/show/<module>.json  {id: {zoom, fw, fh, kind}}
## Prints one "G6ART <module> ok n=<sheets> show=<plates>" line, or "G6ART <module> FAIL <reason>".
const H = preload("g6_lib.gd")


func _init() -> void:
	var here: String = (get_script() as Script).resource_path.get_base_dir()
	var root := here.get_base_dir().path_join("art")
	DirAccess.make_dir_recursive_absolute(root.path_join("show"))
	DirAccess.make_dir_recursive_absolute(root.path_join("check"))
	DirAccess.make_dir_recursive_absolute(root.path_join("turn"))
	var mods := OS.get_cmdline_user_args()
	var bad := 0
	for mod in mods:
		var path := here.path_join(mod + ".gd")
		var scr = load(path)
		if scr == null:
			print("G6ART %s FAIL cannot load %s" % [mod, path])
			bad += 1
			continue
		var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": "g6_" + mod}}
		scr.build(out)
		var dir := root.path_join(mod)
		for rel in out.images:
			var p: String = dir.path_join(rel)
			DirAccess.make_dir_recursive_absolute(p.get_base_dir())
			(out.images[rel] as Image).save_png(p)
		var mf := FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
		mf.store_string(JSON.stringify(out.manifest, "\t"))
		mf.close()
		var meta := {}
		var show: Dictionary = scr.SHOW
		for id in show:
			var pick: Dictionary = show[id]
			var spr := _sprite(out, id, pick)
			if spr.is_empty():
				print("G6ART %s FAIL no sheet for %s" % [mod, id])
				bad += 1
				continue
			var pl: Array = H.plate(spr.img, String(pick.get("ground", "grass")), int(pick.get("seed", 1)), 240, 150, int(pick.get("alt", 0)), pick.get("shadow", []), spr.get("pivot", []))
			(pl[0] as Image).save_png(root.path_join("show").path_join(id + ".png"))
			_strip(out, id, pick).save_png(root.path_join("check").path_join(id + "_facings.png"))
			_turn(out, id, pick).save_png(root.path_join("turn").path_join(id + ".png"))
			meta[id] = {"zoom": pl[1], "fw": spr.img.get_width(), "fh": spr.img.get_height(), "kind": spr.kind}
		var jf := FileAccess.open(root.path_join("show").path_join(mod + ".json"), FileAccess.WRITE)
		jf.store_string(JSON.stringify(meta, "\t"))
		jf.close()
		# contact sheet: every plate of this module, 4 per row, in SHOW order (left->right, top->bottom)
		var ids: Array = meta.keys()
		if not ids.is_empty():
			var cols := 4
			var rows := int(ceil(ids.size() / float(cols)))
			var cs := Image.create(cols * 244, rows * 154, false, Image.FORMAT_RGBA8)
			cs.fill(Color.BLACK)
			for i in ids.size():
				var im := Image.load_from_file(root.path_join("show").path_join(String(ids[i]) + ".png"))
				im.convert(Image.FORMAT_RGBA8)
				cs.blit_rect(im, Rect2i(0, 0, 240, 150), Vector2i((i % cols) * 244 + 2, (i / cols) * 154 + 2))
			cs.save_png(root.path_join("check").path_join("_contact_" + mod + ".png"))
		print("G6ART %s ok n=%d show=%d order=%s" % [mod, out.images.size(), meta.size(), ",".join(PackedStringArray(ids))])
	quit(1 if bad > 0 else 0)


## Self-check strip at 2x on grass: vehicles / squads = all 8 facings of every frame (rows = frames),
## buildings = rotations 0 and 1. Written to <scratch>/g6/art/check/<id>_facings.png.
func _strip(out: Dictionary, id: String, pick: Dictionary) -> Image:
	var cells: Array = []   # rows of Images
	for sec in ["vehicles", "infantry"]:
		var man: Dictionary = out.manifest.get(sec, {})
		if man.has(id):
			var e: Dictionary = man[id]
			for col in (e.frames as Array).size():
				var row: Array = []
				for k in 8:
					row.append(H.tint(H.frame(out.images[e.file], e.fw, e.fh, col, k), H.frame(out.images[e.mask], e.fw, e.fh, col, k), H.TEAM))
				cells.append(row)
			var wr: Dictionary = out.manifest.get("vehicle_wrecks", {})
			if wr.has(id):
				var we: Dictionary = wr[id]
				var row2: Array = []
				for k in 8:
					row2.append(H.frame(out.images[we.file], we.fw, we.fh, 0, k))
				cells.append(row2)
	var b: Dictionary = out.manifest.get("buildings", {})
	if b.has(id):
		var row3: Array = []
		for f in ["0", "1"]:
			var r: Dictionary = b[id].rots[f]
			row3.append(H.tint(out.images[r.file], out.images[r.mask], H.TEAM))
		cells.append(row3)
	var cw := 1
	var ch := 1
	var ncol := 1
	for row in cells:
		ncol = maxi(ncol, row.size())
		for im: Image in row:
			cw = maxi(cw, im.get_width())
			ch = maxi(ch, im.get_height())
	var sheet := H.ground(ncol * cw, cells.size() * ch, String(pick.get("ground", "grass")), 3)
	for r in cells.size():
		for c in (cells[r] as Array).size():
			var im: Image = cells[r][c]
			sheet.blend_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(c * cw, r * ch))
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	return sheet


## Turnaround: the SHOW frame at all 8 facings (buildings: rotations 0 and 1), team-tinted, transparent, 1x.
func _turn(out: Dictionary, id: String, pick: Dictionary) -> Image:
	var row: Array = []
	for sec in ["vehicles", "infantry"]:
		var man: Dictionary = out.manifest.get(sec, {})
		if man.has(id):
			var e: Dictionary = man[id]
			var col := maxi(0, (e.frames as Array).find(String(pick.get("frame", "idle"))))
			for k in 8:
				row.append(H.tint(H.frame(out.images[e.file], e.fw, e.fh, col, k), H.frame(out.images[e.mask], e.fw, e.fh, col, k), H.TEAM))
	var b: Dictionary = out.manifest.get("buildings", {})
	if b.has(id):
		for f in ["0", "1"]:
			var r: Dictionary = b[id].rots[f]
			row.append(H.tint(out.images[r.file], out.images[r.mask], H.TEAM))
	var cw := 1
	var ch := 1
	for im: Image in row:
		cw = maxi(cw, im.get_width())
		ch = maxi(ch, im.get_height())
	var img := Image.create(cw * maxi(1, row.size()), ch, false, Image.FORMAT_RGBA8)
	for i in row.size():
		var im: Image = row[i]
		img.blend_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(i * cw + (cw - im.get_width()) / 2, ch - im.get_height()))
	return img


## Pick one frame of a registered sheet and team-tint it.
func _sprite(out: Dictionary, id: String, pick: Dictionary) -> Dictionary:
	var team: Color = H.ENEMY if bool(pick.get("enemy", false)) else H.TEAM
	for sec in ["vehicles", "infantry"]:
		var man: Dictionary = out.manifest.get(sec, {})
		if man.has(id):
			var e: Dictionary = man[id]
			var col := maxi(0, (e.frames as Array).find(String(pick.get("frame", "idle"))))
			var row := int(pick.get("row", 0 if sec == "vehicles" else 1))
			var img: Image = H.frame(out.images[e.file], e.fw, e.fh, col, row)
			var msk: Image = H.frame(out.images[e.mask], e.fw, e.fh, col, row)
			return {"img": H.tint(img, msk, team), "kind": sec, "pivot": e.pivot}
	var b: Dictionary = out.manifest.get("buildings", {})
	if b.has(id):
		var r: Dictionary = b[id].rots[str(int(pick.get("row", 0)))]
		return {"img": H.tint(out.images[r.file], out.images[r.mask], team), "kind": "buildings"}
	return {}
