extends SceneTree
## G9 HIVE9: blended nanite rim + modular chevrons on all Machine vehicle defs (60+).
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
	print("G71_HIVE9 defs=%d files=%d ms=%d" % [(out.manifest.vehicles as Dictionary).size(), n, Time.get_ticks_msec() - t0])
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
		if bool(ud.get("is_air", false)) and not ((manifests.get("g5_air", {}) as Dictionary).get("vehicles", {}) as Dictionary).has(uid):
			continue
		defs.append(String(uid))
	defs.sort()
	var n := 0
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
			for grp in SEARCH:
				var gm: Dictionary = manifests.get(grp, {})
				for sid in (gm.get("vehicles", {}) as Dictionary).keys():
					if String(sid).ends_with(String(def_id).get_slice("_", -1)):
						spec = (gm.vehicles[sid] as Dictionary).duplicate(true)
						src_dir = "res://assets/art/%s/" % grp
						src_id = String(sid)
						break
				if not spec.is_empty():
					break
		if spec.is_empty() or not spec.has("file"):
			continue
		var fw := int(spec.get("fw", 64))
		var fh := int(spec.get("fh", 32))
		var stem := "units/%s" % def_id
		_blend_sheet(out, spec, stem, fw, fh, src_dir)
		spec["g9"] = {"blend": "hive9", "base": src_id, "silhouette": String(Content.unit(def_id).get("role", "vehicle"))}
		man.vehicles[def_id] = spec
		if (manifests.get("g6_units", {}) as Dictionary).get("icons", {}) is Dictionary:
			var icm: Dictionary = (manifests.g6_units as Dictionary).get("icons", {})
			if icm.has(src_id):
				var ic := _load_img(src_dir + String(icm[src_id]))
				_rim_icon(ic)
				out.images["icons/%s.png" % def_id] = ic
				man.icons[def_id] = "icons/%s.png" % def_id
		n += 1
	return out


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