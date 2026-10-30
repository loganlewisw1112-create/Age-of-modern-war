extends SceneTree
## G8 (ANIM8, G7_REFERENCE 13.9c-52): bakes the blast throw / knock-down / unconscious / wake-up set (g61_anim.gd SET8,
## 31 columns) for every human soldier sheet that has the G7 pose set, as SIDE sheets in assets/art/g8_anim8/ (one
## PNG + team mask per source sheet). The source sheets and their manifests are not touched, so no existing column
## index moves; presentation/art/art_catalog.gd joins a side sheet to its source at load (columns n0.. = SET8) and
## appends SET8 to the def's frames, only while the source file's md5 still matches the one baked from.
## Deterministic: same source pixels -> byte-identical output (run twice and compare manifest.json "files").
##   godot --headless --path . --script res://tools/art/g8_anim8.gd [-- --contact]
## --contact: frame strips per sequence for one rifleman at 2 facings, 3x zoom, into .plan/shots/ANIM8/.
const A = preload("res://tools/art/g61_anim.gd")
const OUT := "res://assets/art/g8_anim8/"
const NEED := ["idle", "walk_a", "walk_b", "unc", "kdown"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	ArtCatalog.anim8_off = true
	ArtCatalog.load_all()
	if args.has("--contact-fast"):   # pose iteration: rifleman strips from an in-memory side sheet, no bake
		contact(true)
		quit(0)
		return
	var n := bake()
	print("ANIM8 baked %d side sheets in %d ms" % [n, Time.get_ticks_msec() - t0])
	if args.has("--contact"):
		contact()
	quit(0)


static func _abs(rel: String) -> String:
	return rel if rel.begins_with("res://") else ArtCatalog.BASE + rel


static func _load(rel: String) -> Image:
	var p := ProjectSettings.globalize_path(_abs(rel))
	if rel == "" or not FileAccess.file_exists(_abs(rel)):
		return null
	var img := Image.load_from_file(p)
	return img


static func _name(rel: String) -> String:
	var s := _abs(rel).trim_prefix("res://assets/").trim_suffix(".png")
	return s.replace("/", "__")


## Eligible defs (sorted) -> their sheets [[file, mask], ...].
static func eligible() -> Dictionary:
	var inf: Dictionary = ArtCatalog.manifest().get("infantry", {})
	var keys: Array = inf.keys()
	keys.sort()
	var out := {}
	for def in keys:
		var spec: Dictionary = inf[def]
		var frames: Array = spec.get("frames", [])
		var ok := A.human(String(def), spec) and int(spec.get("fw", 0)) > 0 and int(spec.get("fh", 0)) > 0
		for nm in NEED:
			ok = ok and frames.has(nm)
		if not ok or frames.has(A.SET8[0]):
			continue
		var sheets: Array = [[String(spec.get("file", "")), String(spec.get("mask", ""))]]
		var al = spec.get("alive_sheets", {})
		if al is Dictionary:
			var ak: Array = (al as Dictionary).keys()
			ak.sort()
			for k in ak:
				if al[k] is Dictionary:
					sheets.append([String(al[k].get("file", "")), String(al[k].get("mask", ""))])
		out[def] = sheets
	return out


static func bake() -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for fn in DirAccess.get_files_at(ProjectSettings.globalize_path(OUT)):   # own folder: drop sheets of a previous bake
		if fn.ends_with(".png"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT + fn))
	var inf: Dictionary = ArtCatalog.manifest().get("infantry", {})
	var el := eligible()
	var sheets := {}
	var files := {}
	var defs: Array = []
	for def in el:
		var spec: Dictionary = inf[def]
		var frames: Array = spec.frames
		var fw := int(spec.fw)
		var fh := int(spec.fh)
		var ok := true
		for sh in el[def]:
			var rel: String = sh[0]
			if sheets.has(rel):
				ok = ok and int(sheets[rel].n0) == frames.size() and int(sheets[rel].fw) == fw
				continue
			var img := _load(rel)
			if img == null or img.get_width() != fw * frames.size() or img.get_height() < fh * 8:
				ok = false
				continue
			# one man per cell only: a squad cell's men overlap, merge into one figure and smear when pitched
			var rg := img.duplicate() as Image
			rg.convert(Image.FORMAT_RGBA8)
			var lc: Array = A._components(rg.get_data(), rg.get_width(), frames.find("idle") * fw, 0, fw, fh)
			if (lc[1] as Array).size() != 1:
				ok = false
				continue
			var msk: Image = _load(String(sh[1])) if String(sh[1]) != "" else null
			var res: Array = A.side8(img, msk, fw, fh, frames)
			var nm := _name(rel)
			var e := {"file": nm + ".png", "mask": "", "mask_of": String(sh[1]), "n0": frames.size(), "fw": fw, "fh": fh,
				"md5": FileAccess.get_md5(_abs(rel))}
			files[nm + ".png"] = _save(res[0], OUT + nm + ".png")
			if res[1] != null:
				e.mask = nm + "_mask.png"
				files[nm + "_mask.png"] = _save(res[1], OUT + nm + "_mask.png")
			sheets[rel] = e
		if ok:
			defs.append(def)
		else:
			for sh in el[def]:
				sheets.erase(sh[0])
	var man := {"version": 1, "group": "g8_anim8", "set": A.SET8, "sheets": sheets, "defs": defs, "files": files}
	var f := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(man, "  ", true))
	f.close()
	return sheets.size()


static func _save(img: Image, path: String) -> String:
	var buf := img.save_png_to_buffer()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(buf)
	f.close()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(buf)
	return ctx.finish().hex_encode()


## Contact sheet: one strip per sequence (launch+tumble, impact+settle, sprawls+loops, buckle, wake) for a rifleman of
## each faction at rows 1 and 4, team colour applied, 3x nearest zoom, on a grass-like ground colour.
static func contact(fast: bool = false) -> void:
	var dir := ProjectSettings.globalize_path("res://.plan/shots/ANIM8B/")
	DirAccess.make_dir_recursive_absolute(dir)
	var seqs := {"launch_tumble": ["k8_launch_0", "k8_launch_1", "k8_tum_0", "k8_tum_1", "k8_tum_2", "k8_tum_3", "k8_tum_4",
		"k8_tum_5", "k8_tum_6", "k8_tum_7"], "impact_settle": ["k8_imp_0", "k8_imp_1", "k8_bk_0", "k8_fd_0", "k8_sd_0"],
		"unconscious": ["k8_bk_0", "k8_bk_1", "k8_bk_t", "k8_fd_0", "k8_fd_1", "k8_fd_t", "k8_sd_0", "k8_sd_1", "k8_sd_t"],
		"buckle": ["idle", "k8_buck_0", "k8_buck_1", "k8_buck_2", "k8_buck_3", "k8_bk_0"],
		"wake": ["k8_bk_0", "k8_wake_0", "k8_wake_1", "k8_wake_2", "k8_wake_3", "k8_wake_4", "k8_wake_5", "idle"]}
	var el := eligible()
	var inf: Dictionary = ArtCatalog.manifest().get("infantry", {})
	var picks: Array = []
	for d in ["rifleman", "b_rifleman", "g7_cn_rifleman", "medic"]:
		if el.has(d):
			picks.append(d)
	if picks.is_empty():
		picks.append(el.keys()[0])
	for def in picks:
		var spec: Dictionary = inf[def]
		var frames: Array = (spec.frames as Array) + A.SET8
		var fw := int(spec.fw)
		var fh := int(spec.fh)
		var base := _load(String(spec.file))
		var mrel := String(spec.get("mask", ""))
		var side: Image
		var mside: Image
		if fast:
			var res: Array = A.side8(base, _load(mrel) if mrel != "" else null, fw, fh, spec.frames)
			side = res[0]
			mside = res[1]
		else:
			side = Image.load_from_file(ProjectSettings.globalize_path(OUT + _name(String(spec.file)) + ".png"))
			if mrel != "":
				mside = Image.load_from_file(ProjectSettings.globalize_path(OUT + _name(String(spec.file)) + "_mask.png"))
		var full := A.join8(base, side, fw, (spec.frames as Array).size())
		_metrics(def, full, frames, fw, fh)
		if mrel != "" and mside != null:
			var mfull := A.join8(_load(mrel), mside, fw, (spec.frames as Array).size())
			_tint(full, mfull, Color(0.25, 0.45, 0.95))
		for sq in seqs:
			var names: Array = seqs[sq]
			var img := Image.create(fw * names.size() * 3, fh * 2 * 3, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.36, 0.42, 0.26))
			var rr := 0
			for row in [1, 4]:
				for k in names.size():
					var col := frames.find(names[k])
					for y in fh:
						for x in fw:
							var c := full.get_pixel(col * fw + x, row * fh + y)
							if c.a <= 0.0:
								continue
							var bg := img.get_pixel((k * fw + x) * 3, (rr * fh + y) * 3)
							var o := bg.lerp(Color(c.r, c.g, c.b, 1.0), c.a)
							for dy in 3:
								for dx in 3:
									img.set_pixel((k * fw + x) * 3 + dx, (rr * fh + y) * 3 + dy, o)
				rr += 1
			img.save_png(dir + "%s_%s.png" % [def, sq])
	print("ANIM8 contact strips in " + dir)


## Body mass per k8 frame vs the idle frame (opaque px ratio, bbox w x h, cut = touches the cell edge), rows 0..7.
static func _metrics(def: String, full: Image, frames: Array, fw: int, fh: int) -> void:
	var lines := PackedStringArray()
	for nm in ["idle"] + A.SET8:
		var col := frames.find(nm)
		var row_s := PackedStringArray()
		var base_n := 0
		for r in 8:
			var n := 0
			var bb := Rect2i(fw, fh, -fw, -fh)
			var x0 := fw
			var x1 := -1
			var y0 := fh
			var y1 := -1
			for y in fh:
				for x in fw:
					if full.get_pixel(col * fw + x, r * fh + y).a8 >= 200:
						n += 1
						x0 = mini(x0, x)
						x1 = maxi(x1, x)
						y0 = mini(y0, y)
						y1 = maxi(y1, y)
			var ic := frames.find("idle")
			var ni := 0
			for y in fh:
				for x in fw:
					if full.get_pixel(ic * fw + x, r * fh + y).a8 >= 200:
						ni += 1
			var cut := "!" if (x0 == 0 or y0 == 0 or x1 == fw - 1 or y1 == fh - 1) else ""
			row_s.append("%.2f/%dx%d%s" % [float(n) / maxf(1.0, ni), x1 - x0 + 1, y1 - y0 + 1, cut])
		lines.append("%-12s %s" % [nm, " ".join(row_s)])
	print("ANIM8M %s fw=%d fh=%d
%s" % [def, fw, fh, "
".join(lines)])


static func _tint(img: Image, m: Image, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if m.get_pixel(x, y).a > 0.0:
				var bc := img.get_pixel(x, y)
				var k := 0.45 + bc.r * 0.9
				img.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, bc.a).clamp())
