extends SceneTree
## G9 HIVE9: blended nanite rim + modular chevrons on every Machine Content.unit def (60+).
## Clones the best existing sheet per def and writes assets/art/g71_hive9/ (manifest wins on merge).
##   godot --headless --path . -s tools/art/g71_hive9.gd
const GEN = preload("res://tools/gen_art.gd")
const GROUP := "g71_hive9"
const SEARCH := ["g71_siege", "g71_special", "g7_threats", "g7_threats2", "g6_units", "g6_new", "g5_air", "g5_naval"]
const NANITE := Color8(60, 220, 210)
const NANITE_D := Color8(24, 96, 88)
const MOD := Color8(190, 72, 210)


func _init() -> void:
	Content.load_all()
	var dir := "res://assets/art/%s/" % GROUP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var t0 := Time.get_ticks_msec()
	var out := build_all()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := GEN.save(out, dir)
	_save_look_samples(out)
	print("G71_HIVE9 content_defs=%d files=%d ms=%d" % [(out.manifest.vehicles as Dictionary).size(), n, Time.get_ticks_msec() - t0])
	quit()


static func build_all() -> Dictionary:
	var man := {"version": 1, "tile": [64, 32], "group": GROUP, "infantry": {}, "vehicles": {}, "vehicle_wrecks": {}, "icons": {}}
	var out := {"images": {}, "manifest": man}
	var manifests: Dictionary = {}
	for grp in SEARCH:
		var p := "res://assets/art/%s/manifest.json" % grp
		if FileAccess.file_exists(p):
			manifests[grp] = JSON.parse_string(FileAccess.get_file_as_string(p))
	var defs: Array = []
	for uid in Content.ids("units"):
		var ud: Dictionary = Content.unit(String(uid))
		if String(ud.get("faction", "")) != "machine":
			continue
		defs.append(String(uid))
	defs.sort()
	for def_id in defs:
		var spec: Dictionary = {}
		var src_dir := ""
		var src_id: String = def_id
		for grp in SEARCH:
			var gm: Dictionary = manifests.get(grp, {})
			if ((gm.get("vehicles", {}) as Dictionary).has(def_id)):
				spec = (gm.vehicles[def_id] as Dictionary).duplicate(true)
				src_dir = "res://assets/art/%s/" % grp
				break
			if ((gm.get("infantry", {}) as Dictionary).has(def_id)):
				spec = (gm.infantry[def_id] as Dictionary).duplicate(true)
				src_dir = "res://assets/art/%s/" % grp
				break
		if spec.is_empty():
			# fallback: same-named base in g6_units vehicles
			var suffix: String = def_id.get_slice("_", def_id.get_slice_count("_") - 1)
			for grp in SEARCH:
				var gm: Dictionary = manifests.get(grp, {})
				for sid in (gm.get("vehicles", {}) as Dictionary).keys():
					if String(sid).ends_with(suffix):
						spec = (gm.vehicles[sid] as Dictionary).duplicate(true)
						src_dir = "res://assets/art/%s/" % grp
						src_id = String(sid)
						break
				if not spec.is_empty():
					break
		if spec.is_empty():
			# New Machine defs often land before bespoke art. Blend the closest existing
			# Machine silhouette so every vehicle remains readable in the hive catalog.
			var target: Dictionary = Content.unit(def_id)
			var target_move := String(target.get("move_class", "vehicle"))
			var target_role := String(target.get("role", "vehicle"))
			for match_pass in 3:
				for grp in SEARCH:
					var gm: Dictionary = manifests.get(grp, {})
					for sec in ["vehicles", "infantry"]:
						for sid in (gm.get(sec, {}) as Dictionary).keys():
							var source: Dictionary = Content.unit(String(sid))
							if source.is_empty() or String(source.get("faction", "")) != "machine":
								continue
							var same_move := String(source.get("move_class", "vehicle")) == target_move
							var same_role := String(source.get("role", "vehicle")) == target_role
							if (match_pass == 0 and not (same_move and same_role)) or (match_pass == 1 and not same_move):
								continue
							spec = ((gm.get(sec, {}) as Dictionary)[sid] as Dictionary).duplicate(true)
							src_dir = "res://assets/art/%s/" % grp
							src_id = String(sid)
							break
						if not spec.is_empty():
							break
					if not spec.is_empty():
						break
				if not spec.is_empty():
					break
		if spec.is_empty() or not spec.has("file"):
			continue
		var fw := int(spec.get("fw", 64))
		var fh := int(spec.get("fh", 32))
		var stem := "units/%s" % def_id
		_blend_sheet(out, spec, stem, fw, fh, src_dir)
		for key in spec:
			if key != "file" and key != "mask":
				spec[key] = _source_paths(spec[key], src_dir)
		spec["g9"] = {"blend": "hive9", "base": src_id, "silhouette": String(Content.unit(def_id).get("role", "vehicle"))}
		man.vehicles[def_id] = spec
		if (manifests.get("g6_units", {}) as Dictionary).get("icons", {}) is Dictionary:
			var icm: Dictionary = (manifests.g6_units as Dictionary).get("icons", {})
			if icm.has(src_id):
				var ic := _load_img(src_dir + String(icm[src_id]))
				_rim_icon(ic)
				out.images["icons/%s.png" % def_id] = ic
				man.icons[def_id] = "icons/%s.png" % def_id
	return out


static func _source_paths(value, source_dir: String):
	if value is Dictionary:
		for key in value:
			value[key] = _source_paths(value[key], source_dir)
	elif value is Array:
		for i in value.size():
			value[i] = _source_paths(value[i], source_dir)
	elif value is String and value.ends_with(".png") and not value.begins_with("res://"):
		return source_dir + value
	return value


static func _save_look_samples(out: Dictionary) -> void:
	var all_ids: Array = (out.manifest.vehicles as Dictionary).keys()
	all_ids.sort()
	var ids: Array = []
	# Review evidence deliberately starts with every new content-backed HIVE9 roster
	# entry, then adds established units for visual comparison.
	for id in all_ids:
		if bool(Content.unit(String(id)).get("hive9_roster", false)):
			ids.append(id)
	for id in all_ids:
		if ids.size() >= 8:
			break
		if not ids.has(id):
			ids.append(id)
	if ids.is_empty():
		return
	var fw := 64
	var fh := 32
	var sample := Image.create(fw * 4, fh * 2, false, Image.FORMAT_RGBA8)
	sample.fill(Color(0.035, 0.045, 0.06, 1.0))
	for i in mini(8, ids.size()):
		var spec: Dictionary = out.manifest.vehicles[ids[i]]
		var img: Image = out.images.get(String(spec.file))
		if img == null:
			continue
		var source_w := int(spec.get("fw", fw))
		var source_h := int(spec.get("fh", fh))
		var frame := img.get_region(Rect2i(0, 0, source_w, source_h))
		var scale := minf(1.0, minf(float(fw) / float(source_w), float(fh) / float(source_h)))
		if scale < 1.0:
			frame.resize(maxi(1, int(source_w * scale)), maxi(1, int(source_h * scale)), Image.INTERPOLATE_NEAREST)
		var cell_origin := Vector2i((i % 4) * fw, (i / 4) * fh)
		var draw_at := cell_origin + Vector2i((fw - frame.get_width()) / 2, fh - frame.get_height())
		sample.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), draw_at)
	var look_dir := ProjectSettings.globalize_path("res://.plan/shots/G71_LOOK")
	DirAccess.make_dir_recursive_absolute(look_dir)
	sample.save_png(look_dir.path_join("strip_g71_hive9_catalog.png"))
	var large := sample.duplicate()
	large.resize(sample.get_width() * 2, sample.get_height() * 2, Image.INTERPOLATE_NEAREST)
	large.save_png(look_dir.path_join("strip_g71_hive9_catalog_2x.png"))


static func _load_img(p: String) -> Image:
	var img := Image.load_from_file(p)
	if img == null:
		var tex = load(p)
		img = tex.get_image() if tex != null else Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _blend_sheet(out: Dictionary, spec: Dictionary, stem: String, fw: int, fh: int, sdir: String) -> void:
	var img := _load_img(sdir + String(spec.file))
	var mask: Image = _load_img(sdir + String(spec.mask)) if spec.has("mask") else null
	for cy in range(0, img.get_height() - fh + 1, fh):
		for cx in range(0, img.get_width() - fw + 1, fw):
			_rim_cell(img, mask, Rect2i(cx, cy, fw, fh))
	out.images[stem + ".png"] = img
	spec.file = stem + ".png"
	if mask != null:
		out.images[stem + "_mask.png"] = mask
		spec.mask = stem + "_mask.png"


static func _rim_cell(img: Image, mask: Image, cell: Rect2i) -> void:
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var edge := false
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var p: Vector2i = Vector2i(x, y) + d
				if p.x < cell.position.x or p.y < cell.position.y or p.x >= cell.end.x or p.y >= cell.end.y:
					edge = true
					break
				if img.get_pixel(p.x, p.y).a < 0.5:
					edge = true
					break
			if edge:
				img.set_pixel(x, y, c.lerp(NANITE, 0.35))
				if mask != null:
					mask.set_pixel(x, y, Color(0, 0, 0, 0))
			elif (x + y * 3) % 17 == 0:
				img.set_pixel(x, y, c.lerp(MOD, 0.12))
	# modular chevron on crown
	var cy := cell.position.y + maxi(2, cell.size.y / 6)
	var cx := cell.position.x + cell.size.x / 2
	for dx in [-2, 0, 2]:
		_put(img, mask, cell, cx + dx, cy, MOD if dx == 0 else NANITE_D)


static func _rim_icon(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(NANITE, 0.25))


static func _put(img: Image, mask: Image, cell: Rect2i, x: int, y: int, c: Color) -> void:
	if x < cell.position.x or y < cell.position.y or x >= cell.end.x or y >= cell.end.y:
		return
	var o: Color = img.get_pixel(x, y)
	if o.a < 0.5:
		return
	img.set_pixel(x, y, c)
	if mask != null:
		mask.set_pixel(x, y, Color(0, 0, 0, 0))
