extends "res://tests/test_base.gd"
## G5 naval art (agent ART-NAV, CONTRACTS_G5 s3.3 / s8 / s11). Every unit id in content/g5/naval.json has a
## full ship sheet in res://assets/art/g5_naval/manifest.json: 8 facings, idle / move / fire first, every
## cell drawn, a team mask with team pixels, a bow-spray move frame that differs from idle, a looping wake
## sheet and a 4-stage sinking sheet that really goes under, a wreck, a build icon, lod_class "naval";
## transports carry ramp frames. Coast decor, cliff-to-sea transitions and the naval effects ship too;
## the shipped files match the manifest md5s and the generator reproduces them byte-identically.

const GEN = preload("res://tools/art/g5_naval_gen.gd")
const BASE := "res://assets/art/g5_naval/"
const FRAG := "res://content/g5/naval.json"
const STD := ["idle", "move", "fire"]
const FX := ["g5_shell_splash", "g5_shell_splash_small", "g5_naval_muzzle", "g5_ramp_splash", "g5_sink_bubbles",
	"g5_bow_spray", "g5_ship_smoke"]
const POI := ["coast_pier_ew", "coast_pier_ns", "coast_pier_end", "coast_jetty_ew", "coast_jetty_ns",
	"coast_lighthouse", "coast_buoy_red", "coast_buoy_green", "coast_boathouse", "coast_hedgehogs",
	"coast_sea_stack", "coast_cliff_rocks", "coast_island_pines", "coast_beached_hulk", "coast_net_rack",
	"coast_dune_grass", "coast_driftwood"]


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


## Opaque pixel count of one cell.
func _solid(img: Image, x: int, y: int, fw: int, fh: int) -> int:
	var n := 0
	for yy in range(y, y + fh):
		for xx in range(x, x + fw):
			if img.get_pixel(xx, yy).a > 0.6:
				n += 1
	return n


## Sheet loads at frames x 8 facings and every cell has pixels (alpha > a_min).
func _cells(def: String, what: String, img: Image, fw: int, fh: int, nf: int) -> bool:
	if not check(img != null, "%s: %s sheet loads" % [def, what]):
		return false
	check_eq(img.get_size(), Vector2i(fw * nf, fh * 8), "%s: %s sheet size" % [def, what])
	var used := 0
	for f in nf:
		for k in 8:
			if img.get_region(Rect2i(f * fw, k * fh, fw, fh)).get_used_rect().size.x > 4:
				used += 1
	check_eq(used, nf * 8, "%s: every %s cell drawn" % [def, what])
	return true


func test_every_ship_has_art_with_wake_and_sinking() -> void:
	var man := _json(BASE + "manifest.json")
	if not check(not man.is_empty(), "assets/art/g5_naval/manifest.json exists (run tools/art/g5_naval_gen.gd)"):
		return
	var units: Dictionary = _json(FRAG).get("units", {})
	check_eq(units.size(), 9, "9 ships in naval.json")
	var ids: Array = units.keys()
	ids.sort()
	var specials: Dictionary = man.get("specials", {})
	for def in ids:
		var u: Dictionary = units[def]
		var spec: Dictionary = man.get("vehicles", {}).get(def, {})
		if not check(not spec.is_empty(), "ship sheet for " + def):
			continue
		check_eq(int(spec.facings), 8, "8 facings " + def)
		check(bool(spec.get("naval", false)), def + " flagged naval")
		var frames: Array = spec.frames
		check(frames.slice(0, 3) == STD, "%s standard frames first %s" % [def, str(frames)])
		var fw := int(spec.fw)
		var fh := int(spec.fh)
		check(fw >= 32 and fw <= 160 and fh >= 32 and fh <= 160, "sane frame size %s %dx%d" % [def, fw, fh])
		check(int(spec.pivot[1]) > 0 and int(spec.pivot[1]) < fh, "pivot inside frame " + def)
		var img := _img(String(spec.file))
		if _cells(def, "unit", img, fw, fh, frames.size()):
			var msk := _img(String(spec.mask))
			check(msk != null and msk.get_size() == img.get_size() and msk.get_used_rect().size.x > 0,
				def + " team mask with team pixels")
			var mi := frames.find("move")
			var diff := 0
			for y in fh:
				for x in fw:
					if img.get_pixel(x, y) != img.get_pixel(mi * fw + x, y):
						diff += 1
			check(diff > 40, "%s move frame shows bow spray / wash (%d px differ from idle)" % [def, diff])
		var wk: Dictionary = spec.get("wake", {})
		if check(not wk.is_empty(), def + " has a wake sheet"):
			check(int(wk.frames) >= 2 and int(wk.facings) == 8, def + " wake loops over >= 2 frames, 8 facings")
			_cells(def, "wake", _img(String(wk.file)), int(wk.fw), int(wk.fh), int(wk.frames))
		var sk: Dictionary = spec.get("sink", {})
		if check(not sk.is_empty(), def + " has a sinking sheet"):
			var sf: Array = sk.frames
			check(sf.size() >= 3, def + " sinking has >= 3 stages")
			var si := _img(String(sk.file))
			if _cells(def, "sinking", si, int(sk.fw), int(sk.fh), sf.size()):
				var first := _solid(si, 0, 0, int(sk.fw), int(sk.fh))
				var last := _solid(si, (sf.size() - 1) * int(sk.fw), 0, int(sk.fw), int(sk.fh))
				check(last * 2 < first, "%s sinks: last stage %d solid px vs first %d" % [def, last, first])
		var wr: Dictionary = man.get("vehicle_wrecks", {}).get(def, {})
		if check(not wr.is_empty(), "wreck sheet " + def):
			var wi := _img(String(wr.file))
			check(wi != null and wi.get_size() == Vector2i(int(wr.fw), int(wr.fh) * 8), "wreck sheet loads, 8 facings " + def)
		if String(u.get("role", "")) == "naval_transport":
			check(frames.has("ramp_half") and frames.has("unload"), def + " has landing-ramp frames")
		for st in specials.get(def, {}):
			check(frames.has(specials[def][st]), "%s special %s -> existing frame" % [def, st])
		check(_img(String(man.get("icons", {}).get(def, ""))) != null, "icon " + def)
		check_eq(String(man.get("lod_class", {}).get(def, "")), "naval", "lod_class " + def)
	check(_img(String(man.get("lod_icons", {}).get("*", {}).get("naval", {}).get("file", ""))) != null, "LOD naval glyph")
	for fx in FX:
		var e: Dictionary = man.get("effects", {}).get(fx, {})
		var fi := _img(String(e.get("file", "")))
		check(fi != null and fi.get_width() == int(e.fw) * int(e.frames) and fi.get_used_rect().size.x > 0, "effect " + fx)
	for id in POI:
		var p: Dictionary = man.get("poi_decor", {}).get(id, {})
		check(not p.is_empty() and _img(String(p.file)) != null and p.footprint is Array, "coast decor " + id)
	for kind in ["coast_beach", "coast_shallow", "coast_cliff"]:
		check(man.get("decor", {}).get(kind, []).size() >= 2, "decor variants " + kind)
	var tg: Dictionary = man.get("terrain_g5", {})
	for kind in ["surf", "cliff_wet"]:
		var ti := _img(String(tg.get("trans", {}).get(kind, "")))
		check(ti != null and ti.get_size() == Vector2i(1024, 64) and ti.get_used_rect().size.x > 0, "cliff-sea transition " + kind)
	check(tg.get("rules", []).size() >= 2, "terrain_g5 rules")
	var files: Dictionary = man.get("files", {})
	check(files.size() > 60, "manifest lists its files (%d)" % files.size())
	var bad := 0
	for rel in files:
		if not FileAccess.file_exists(BASE + rel) or _md5(rel) != String(files[rel]):
			bad += 1
	check_eq(bad, 0, "shipped g5_naval files match manifest md5")


func test_g5_naval_art_regenerates_identically() -> void:
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
	var shipped := man.duplicate(true)
	shipped.erase("files")
	check(JSON.stringify(shipped, "", true) == JSON.stringify(JSON.parse_string(JSON.stringify(out.manifest)), "", true),
		"regenerated manifest sections identical to shipped")
