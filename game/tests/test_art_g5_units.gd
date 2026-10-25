extends "res://tests/test_base.gd"
## G5 ground-unit + launched-drone art (agent ART-U5, CONTRACTS_G5 s3.1 / s11). Every unit id in
## content/g5/units_g5.json has a full sheet in res://assets/art/g5_units/manifest.json: 8 facings, the
## standard frames first, every cell drawn, a team mask with team pixels, its specials (squads: wounded +
## per-strength alive sheets; vehicles / swarm / drones: wrecks; drones: air, altitude, shadow, dive and
## trail), a build icon and a LOD class; the shipped files match the manifest md5s, and the generator
## reproduces them byte-identically.

const GEN5 = preload("res://tools/art/g5_units_gen.gd")
const BASE := "res://assets/art/g5_units/"
const FRAG := "res://content/g5/units_g5.json"
const LOD_OK := ["infantry", "vehicle_light", "vehicle_heavy", "artillery", "air"]
const FOOT := ["idle", "walk_a", "walk_b", "fire"]
const VEH := ["idle", "move", "fire"]


func _json(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


func _img(rel: String) -> Image:
	var p := BASE + rel
	if rel == "" or not FileAccess.file_exists(p):
		return null
	return Image.load_from_file(p)


func _md5(rel: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(FileAccess.get_file_as_bytes(BASE + rel))
	return ctx.finish().hex_encode()


## Every frame x facing cell has real pixels; the mask has team pixels somewhere.
func _sheet_ok(def: String, file: String, mask: String, fw: int, fh: int, nf: int) -> void:
	var img := _img(file)
	var msk := _img(mask)
	if not check(img != null and msk != null, "%s: sheet + mask load (%s)" % [def, file]):
		return
	check_eq(img.get_size(), Vector2i(fw * nf, fh * 8), "%s: sheet size %s" % [def, file])
	check_eq(msk.get_size(), img.get_size(), "%s: mask size %s" % [def, mask])
	var used := 0
	for f in nf:
		for k in 8:
			if img.get_region(Rect2i(f * fw, k * fh, fw, fh)).get_used_rect().size.x > 4:
				used += 1
	check_eq(used, nf * 8, "%s: every cell drawn in %s" % [def, file])
	check(msk.get_used_rect().size.x > 0, "%s: team mask has team pixels (%s)" % [def, mask])


func test_every_g5_ground_unit_and_drone_has_art() -> void:
	var man := _json(BASE + "manifest.json")
	if not check(not man.is_empty(), "assets/art/g5_units/manifest.json exists (run tools/art/g5_units_gen.gd)"):
		return
	var units: Dictionary = _json(FRAG).get("units", {})
	check(units.size() >= 24, "16 ground units + 8 drones in units_g5.json (%d)" % units.size())
	var ids: Array = units.keys()
	ids.sort()
	var specials: Dictionary = man.get("specials", {})
	for def in ids:
		var u: Dictionary = units[def]
		var mc := String(u.get("move_class", ""))
		var drone := mc == "air_low"
		var squad := int(u.get("squad_size", 0)) > 0
		var spec: Dictionary = man.get("infantry", {}).get(def, man.get("vehicles", {}).get(def, {}))
		if not check(not spec.is_empty(), "sprite sheet for " + def):
			continue
		check_eq(int(spec.facings), 8, "8 facings " + def)
		var frames: Array = spec.frames
		var want: Array = FOOT if squad else VEH
		check(frames.slice(0, want.size()) == want, "%s standard frames first %s" % [def, str(frames)])
		var fw := int(spec.fw)
		var fh := int(spec.fh)
		check(fw >= 24 and fw <= 128 and fh >= 24 and fh <= 128, "sane frame size %s %dx%d" % [def, fw, fh])
		check(spec.pivot is Array and int(spec.pivot[1]) > 0 and int(spec.pivot[1]) < fh, "pivot inside frame " + def)
		_sheet_ok(def, String(spec.file), String(spec.get("mask", "")), fw, fh, frames.size())
		if squad:
			var n := int(u.squad_size)
			check_eq(int(spec.get("squad_size", 0)), n, "squad_size matches content " + def)
			check(frames.has("wounded"), "%s has a wounded pose" % def)
			var al: Dictionary = spec.get("alive_sheets", {})
			for a in range(1, n):
				var s: Dictionary = al.get(str(a), {})
				if check(not s.is_empty(), "%s alive sheet %d/%d" % [def, a, n]):
					_sheet_ok(def, String(s.file), String(s.mask), fw, fh, frames.size())
		else:
			var wr: Dictionary = man.get("vehicle_wrecks", {}).get(def, {})
			if check(not wr.is_empty(), "wreck sheet " + def):
				var wi := _img(String(wr.file))
				check(wi != null and wi.get_size() == Vector2i(int(wr.fw), int(wr.fh) * 8), "wreck sheet loads, 8 facings " + def)
		if drone:
			check(bool(spec.get("air", false)) and int(spec.get("altitude", 0)) > 0, "%s flagged air with altitude" % def)
			check(frames.has("dive") and frames.has("trail"), "%s has dive + trail frames" % def)
			check(_img(String(spec.get("shadow", {}).get("file", ""))) != null, "%s ground shadow" % def)
		for st in specials.get(def, {}):
			check(frames.has(specials[def][st]), "%s special %s -> existing frame" % [def, st])
		check(_img(String(man.get("icons", {}).get(def, ""))) != null, "icon " + def)
		check(LOD_OK.has(String(man.get("lod_class", {}).get(def, ""))), "lod_class " + def)
	for need in ["a_drone_team", "b_drone_team"]:
		check(specials.get(need, {}).has("launch") and specials.get(need, {}).has("tactical"), need + " launch + tactical")
	check(specials.get("a_hmg_team", {}).has("deploy"), "HMG deploy frame")
	check(specials.get("a_medic_team", {}).has("carry"), "medic carry-wounded frame")
	for fx in ["g5_wounded_a", "g5_wounded_b", "g5_wounded_marker", "g5_red_cross", "g5_drone_trail", "g5_emp_pulse"]:
		var e: Dictionary = man.get("effects", {}).get(fx, {})
		check(not e.is_empty() and _img(String(e.file)) != null, "effect " + fx)
	var files: Dictionary = man.get("files", {})
	check(files.size() > 100, "manifest lists its files (%d)" % files.size())
	var bad := 0
	for rel in files:
		if not FileAccess.file_exists(BASE + rel) or _md5(rel) != String(files[rel]):
			bad += 1
	check_eq(bad, 0, "shipped g5_units files match manifest md5")


func test_g5_unit_art_regenerates_identically() -> void:
	var man := _json(BASE + "manifest.json")
	var files: Dictionary = man.get("files", {})
	var out: Dictionary = GEN5.generate()
	check_eq(out.images.size(), files.size(), "generator emits exactly the shipped file set")
	var diff := 0
	for rel in out.images:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		ctx.update((out.images[rel] as Image).save_png_to_buffer())
		if ctx.finish().hex_encode() != String(files.get(rel, "")):
			diff += 1
	check_eq(diff, 0, "regenerated PNGs byte-identical to shipped")
