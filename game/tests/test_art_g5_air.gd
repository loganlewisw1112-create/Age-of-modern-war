extends "res://tests/test_base.gd"
## G5 aircraft art (agent ART-AIR, CONTRACTS_G5 s3.2 / s7 / s11). Every unit id in content/g5/air.json has
## a full sheet in res://assets/art/g5_air/manifest.json: 8 facings, the standard vehicle frames first,
## every cell drawn, a team mask with team pixels, flagged air with altitude / bob / shadow + a per-facing
## shadow sheet, at least one flying frame and one landed (ground) frame, the class-specific frames
## (jets: taxi / roll / landing / parked; rotorcraft: landed / parked; VTOLs: hover / landing; sling
## carriers: sling + sling_hook), animated rotor / exhaust frames that actually differ, a wreck, an icon
## and lod_class "air"; the effects exist; shipped files match the manifest md5s, and the generator
## reproduces them byte-identically.

const GEN = preload("res://tools/art/g5_air_gen.gd")
const BASE := "res://assets/art/g5_air/"
const FRAG := "res://content/g5/air.json"
const VEH := ["idle", "move", "fire"]
const FLYING := ["idle", "move", "fire", "idle_b", "move_b", "hover", "hover_b", "landing", "sling", "sling_b", "sling_hook"]
const CLASS_NEED := {
	"jet": ["taxi", "roll", "landing", "parked"],
	"heli": ["landed", "parked"],
	"lift": ["landed", "parked", "unload"],
	"vtol": ["hover", "landing", "landed", "parked", "unload"],
	"micro": ["landed"],
}
const EFFECTS := ["g5_air_bomb", "g5_bomb_blast", "g5_missile", "g5_missile_trail", "g5_air_smoke", "g5_rotor_wash",
	"g5_afterburner", "g5_flak_burst", "g5_air_crash"]


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


func _cell(img: Image, fw: int, fh: int, f: int, k: int) -> Image:
	return img.get_region(Rect2i(f * fw, k * fh, fw, fh))


func test_every_air_unit_has_art_with_landed_and_flying_frames() -> void:
	var man := _json(BASE + "manifest.json")
	if not check(not man.is_empty(), "assets/art/g5_air/manifest.json exists (run tools/art/g5_air_gen.gd)"):
		return
	var units: Dictionary = _json(FRAG).get("units", {})
	check_eq(units.size(), 13, "13 aircraft in air.json")
	var ids: Array = units.keys()
	ids.sort()
	var specials: Dictionary = man.get("specials", {})
	for def in ids:
		var u: Dictionary = units[def]
		var spec: Dictionary = man.get("vehicles", {}).get(def, {})
		if not check(not spec.is_empty(), "sprite sheet for " + def):
			continue
		check_eq(int(spec.get("facings", 0)), 8, "8 facings " + def)
		var frames: Array = spec.frames
		check(frames.slice(0, 3) == VEH, "%s standard frames first %s" % [def, str(frames)])
		var fw := int(spec.fw)
		var fh := int(spec.fh)
		check(fw >= 24 and fw <= 128 and fh >= 24 and fh <= 128, "sane frame size %s %dx%d" % [def, fw, fh])
		check(spec.pivot is Array and int(spec.pivot[1]) > 0 and int(spec.pivot[1]) < fh, "pivot inside frame " + def)
		var img := _img(String(spec.file))
		var msk := _img(String(spec.get("mask", "")))
		if not check(img != null and msk != null, "%s: sheet + mask load" % def):
			continue
		check_eq(img.get_size(), Vector2i(fw * frames.size(), fh * 8), "%s: sheet size" % def)
		check_eq(msk.get_size(), img.get_size(), "%s: mask size" % def)
		var used := 0
		for f in frames.size():
			for k in 8:
				if _cell(img, fw, fh, f, k).get_used_rect().size.x > 4:
					used += 1
		check_eq(used, frames.size() * 8, "%s: every cell drawn" % def)
		check(msk.get_used_rect().size.x > 0, "%s: team mask has team pixels" % def)
		# air flags, altitude offset and ground shadow
		check(bool(spec.get("air", false)) and int(spec.get("altitude", 0)) > 0, "%s flagged air with altitude" % def)
		check(spec.has("bob"), "%s has a hover bob" % def)
		check(_img(String(spec.get("shadow", {}).get("file", ""))) != null, "%s ground shadow blob" % def)
		var ss: Dictionary = spec.get("shadow_sheet", {})
		var si := _img(String(ss.get("file", "")))
		check(si != null and si.get_size() == Vector2i(fw, fh * 8) and int(ss.get("facings", 0)) == 8,
			"%s per-facing shadow sheet" % def)
		# landed + flying frames
		var ground: Array = spec.get("ground_frames", [])
		var n_fly := 0
		for fr in frames:
			if FLYING.has(fr):
				n_fly += 1
		check(n_fly >= 3, "%s has flying frames (%d)" % [def, n_fly])
		check(not ground.is_empty() and (ground.has("landed") or ground.has("parked")), "%s has a landed frame %s" % [def, str(ground)])
		for g in ground:
			check(frames.has(g) and not FLYING.has(g), "%s ground frame %s exists and is not a flying frame" % [def, g])
		var cls := String(spec.get("aircraft", ""))
		var ac := String(u.get("aircraft", ""))
		check(cls == ac or (cls == "lift" and ac == "heli"), "%s aircraft class %s matches content %s" % [def, cls, ac])
		for need in CLASS_NEED.get(cls, ["landed"]):
			check(frames.has(need), "%s (%s) has %s frame" % [def, cls, need])
		if bool(u.get("sling", false)):
			check(frames.has("sling") and frames.has("sling_hook"), "%s sling-load pose" % def)
			check(spec.get("sling", {}).has("load_dy"), "%s sling metadata" % def)
		# animation: the second phase of each loop must change pixels (rotor blur / exhaust flicker)
		var anim: Dictionary = spec.get("anim", {})
		check(anim.has("air") and anim.has("move"), "%s air + move animation loops" % def)
		for st in anim:
			var pair: Array = anim[st]
			if check(pair.size() == 2 and frames.has(pair[0]) and frames.has(pair[1]), "%s anim %s frames exist" % [def, st]):
				var a := _cell(img, fw, fh, frames.find(pair[0]), 2)
				var b := _cell(img, fw, fh, frames.find(pair[1]), 2)
				check(a.get_data() != b.get_data(), "%s anim %s actually animates" % [def, st])
		var land := frames.find(ground[0]) if not ground.is_empty() else -1
		if land >= 0:
			check(_cell(img, fw, fh, land, 3).get_data() != _cell(img, fw, fh, 0, 3).get_data(), "%s landed differs from flying" % def)
		for key in specials.get(def, {}):
			check(frames.has(specials[def][key]), "%s special %s -> existing frame" % [def, key])
		check(specials.get(def, {}).has("air") and specials.get(def, {}).has("landed"), "%s phase map air + landed" % def)
		var wr: Dictionary = man.get("vehicle_wrecks", {}).get(def, {})
		if check(not wr.is_empty(), "wreck sheet " + def):
			var wi := _img(String(wr.file))
			check(wi != null and wi.get_size() == Vector2i(int(wr.fw), int(wr.fh) * 8), "wreck sheet loads, 8 facings " + def)
		check(_img(String(man.get("icons", {}).get(def, ""))) != null, "icon " + def)
		check_eq(String(man.get("lod_class", {}).get(def, "")), "air", "lod_class " + def)
	for fx in EFFECTS:
		var e: Dictionary = man.get("effects", {}).get(fx, {})
		check(not e.is_empty() and _img(String(e.get("file", ""))) != null, "effect " + fx)
	var files: Dictionary = man.get("files", {})
	check(files.size() > 50, "manifest lists its files (%d)" % files.size())
	var bad := 0
	for rel in files:
		if not FileAccess.file_exists(BASE + rel) or _md5(rel) != String(files[rel]):
			bad += 1
	check_eq(bad, 0, "shipped g5_air files match manifest md5")


func test_g5_air_art_regenerates_identically() -> void:
	var man := _json(BASE + "manifest.json")
	var files: Dictionary = man.get("files", {})
	var out: Dictionary = GEN.generate()
	check_eq(out.images.size(), files.size(), "generator emits exactly the shipped file set")
	var diff := 0
	for rel in out.images:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		ctx.update((out.images[rel] as Image).save_png_to_buffer())
		if ctx.finish().hex_encode() != String(files.get(rel, "")):
			diff += 1
	check_eq(diff, 0, "regenerated PNGs byte-identical to shipped")
	var m2: Dictionary = out.manifest.duplicate(true)
	m2["files"] = files
	check(JSON.stringify(JSON.parse_string(JSON.stringify(m2)), "  ", true) == JSON.stringify(man, "  ", true),
		"regenerated manifest identical")
