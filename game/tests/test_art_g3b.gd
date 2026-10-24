extends "res://tests/test_base.gd"
## G3b art coverage (agent ART4-2, CONTRACTS_G3b s8): the new stage 7-9 units and research/comms
## buildings have complete art, POI decor exists for MAP4, LOD icons exist for R4, and the g3b module
## regenerates byte-identically and matches the shipped files. Reads assets/generated/ via ArtCatalog.

const AC = preload("res://presentation/art/art_catalog.gd")
const GEN = preload("res://tools/gen_art.gd")
const G3B = preload("res://tools/art/g3b.gd")
const DECOR = preload("res://tools/art/g3b_decor.gd")

const BLUE := Color("#4f7db0")
const RED := Color("#b5583a")
## Ids agreed with MAP4 on the board (seq 487/493, + town_house).
const POI := ["rail_ew", "rail_ns", "rail_x", "factory_block", "refinery_tanks", "ruined_plant", "dam_ew",
	"tunnel_portal", "airfield_tarmac", "airfield_tarmac_mark", "hangar", "town_house"]
const LOD_R4 := ["infantry", "vehicle", "air", "building"]


func _real(t, what: String) -> bool:
	return check(t != null and t is Texture2D and t != AC._ph() and t.get_width() > 0, "placeholder/null art: " + what)


## New units: every stage-9 unit in content plus the G3b roster the art module declares.
func _unit_ids() -> Array:
	var a: Array = G3B.UNIT_ICONS.keys()
	for id in Content.ids("units"):
		if int(Content.unit(id).get("stage_min", 0)) >= 9 and not a.has(id):
			a.append(id)
	return a


## New buildings: research/comms structures in content plus the module's declared list.
func _bld_ids() -> Array:
	var a: Array = G3B.BUILDING_ICONS.keys()
	for id in Content.ids("buildings"):
		var b: Dictionary = Content.building(id)
		if (b.get("research", false) or b.get("comms", false)) and not a.has(id):
			a.append(id)
	return a


func test_g3b_units() -> void:
	AC.load_all()
	var man := AC.manifest()
	var ids := _unit_ids()
	check(ids.size() >= 12, "12 G3b units (%d)" % ids.size())
	for def in ids:
		if not check(Content.ids("units").has(def), "art id %s is a content unit" % def):
			continue
		var u: Dictionary = Content.unit(def)
		var spec: Dictionary = man.get("infantry", {}).get(def, man.get("vehicles", {}).get(def, {}))
		if not check(not spec.is_empty(), "sprite sheet for " + def):
			continue
		check_eq(int(spec.facings), 8, "8 facings for " + def)
		var want: Array = ["idle", "walk_a", "walk_b", "fire"] if String(u.get("move_class", "")) == "foot" else ["idle", "move", "fire"]
		check_eq(spec.frames, want, "frame set for " + def)
		var img: Image = AC._image(String(spec.file))
		if check(img != null, "sheet loads for " + def):
			check_eq(img.get_size(), Vector2i(int(spec.fw) * want.size(), int(spec.fh) * 8), "sheet size for " + def)
			check(int(spec.fw) >= 24 and int(spec.fw) <= 128 and int(spec.fh) >= 24 and int(spec.fh) <= 128, "sane frame size " + def)
		check(AC._image(String(spec.get("mask", ""))) != null, "team mask for " + def)
		if u.get("leaves_wreck", false):
			check(man.get("vehicle_wrecks", {}).has(def), "wreck sheet for " + def)
		if String(u.get("move_class", "")) == "air":
			check(spec.get("air", false) and int(spec.get("altitude", 0)) > 0, "air fields for " + def)
			check(AC._image(String(spec.get("shadow", {}).get("file", ""))) != null, "air shadow for " + def)
		var a: Dictionary = AC.entity_sprite({"kind": "unit", "def": def, "facing": 0.0}, BLUE, 0)
		var b: Dictionary = AC.entity_sprite({"kind": "unit", "def": def, "facing": 0.0}, RED, 0)
		if _real(a.texture, "unit " + def) and _real(b.texture, "unit red " + def):
			check(a.texture.get_image().get_data() != b.texture.get_image().get_data(), "team colour changes " + def)
		var t: Texture2D = AC.icon(def)
		if _real(t, "icon " + def):
			check(t.get_width() == 32 and t.get_height() == 32, "icon 32x32 " + def)
	for id in Content.ids("production"):
		if int(Content.production(id).get("stage_min", 0)) >= 9:
			_real(AC.icon(id), "icon for production item " + id)


func test_g3b_buildings() -> void:
	AC.load_all()
	var man := AC.manifest()
	var ids := _bld_ids()
	check(ids.size() >= 5, "5 G3b buildings (%d)" % ids.size())
	for def in ids:
		if not check(Content.ids("buildings").has(def), "art id %s is a content building" % def):
			continue
		var size := int(Content.building(def).size)
		var entry: Dictionary = man.get("buildings", {}).get(def, {})
		if not check(not entry.is_empty(), "building art for " + def):
			continue
		check_eq(int(entry.size), size, "art footprint matches content for " + def)
		var looks := {}
		for st in ["built", "build_0", "build_1", "build_2"]:
			var s: Dictionary = entry.states.get(st, {})
			var img: Image = AC._image(String(s.get("file", "")))
			if check(img != null, "%s state %s" % [def, st]):
				check_eq(img.get_width(), size * 64 + 12, "canvas width %s %s" % [def, st])
				check(img.get_height() > size * 32 and img.get_height() <= 220, "sane height %s %s" % [def, st])
				looks[img.get_data()] = true
			check(AC._image(String(s.get("mask", ""))) != null, "mask %s %s" % [def, st])
		check_eq(looks.size(), 4, "4 distinct looks (built + 3 construction stages) for " + def)
		var blue: Dictionary = AC.entity_sprite({"kind": "building", "def": def, "built": true, "progress": 1.0}, BLUE, 0)
		var red: Dictionary = AC.entity_sprite({"kind": "building", "def": def, "built": true, "progress": 1.0}, RED, 0)
		if _real(blue.texture, "building " + def) and _real(red.texture, "building red " + def):
			check(blue.texture.get_image().get_data() != red.texture.get_image().get_data(), "team colour changes " + def)
		var t: Texture2D = AC.icon(def)
		if _real(t, "icon " + def):
			check(t.get_width() == 32 and t.get_height() == 32, "icon 32x32 " + def)


func test_poi_decor() -> void:
	AC.load_all()
	var man := AC.manifest()
	var poi: Dictionary = man.get("poi_decor", {})
	check(man.has("decor"), "legacy manifest.decor section still present")
	for id in POI:
		var d: Dictionary = poi.get(id, {})
		if not check(not d.is_empty(), "poi_decor entry " + id):
			continue
		var fp: Array = d.footprint
		var n := int(fp[0]) + int(fp[1])
		check(d.flat is bool, "flat flag on " + id)
		var img: Image = AC._image(String(d.file))
		if check(img != null, "poi_decor file loads " + id):
			check_eq(img.get_width(), n * 32 + 12, "decor width " + id)
			check(img.get_height() >= n * 16 + 6 and img.get_height() <= 240, "decor height " + id)
			check(int(d.pivot[0]) == img.get_width() / 2 and int(d.pivot[1]) > 0 and int(d.pivot[1]) < img.get_height(), "pivot inside " + id)
			var opaque := 0
			for y in img.get_height():
				for x in img.get_width():
					if img.get_pixel(x, y).a > 0.5:
						opaque += 1
			check(opaque > n * 120, "decor %s has real content (%d px)" % [id, opaque])


func test_lod_icons() -> void:
	AC.load_all()
	var lod: Dictionary = AC.manifest().get("lod_icons", {}).get("*", {})
	for c in LOD_R4 + ["vehicle_light", "vehicle_heavy", "artillery", "dot"]:
		var e: Dictionary = lod.get(c, {})
		if not check(not e.is_empty(), "lod_icons class " + c):
			continue
		var img: Image = AC._image(String(e.file))
		if not check(img != null, "lod icon loads " + c):
			continue
		check(img.get_width() >= 12 and img.get_width() <= 16 and img.get_height() >= 12 and img.get_height() <= 16, "lod icon size " + c)
		var light := 0
		var dark := 0
		for y in img.get_height():
			for x in img.get_width():
				var p := img.get_pixel(x, y)
				if p.a > 0.5 and absf(p.r - p.g) < 0.02 and absf(p.g - p.b) < 0.02:
					if p.r > 0.55:
						light += 1
					elif p.r < 0.15:
						dark += 1
		check(light >= 12 and dark >= 8, "greyscale glyph + dark outline for %s (%d/%d)" % [c, light, dark])


func test_g3b_deterministic() -> void:
	var a := {"images": {}, "manifest": {}}
	var b := {"images": {}, "manifest": {}}
	G3B.build(a)
	G3B.build(b)
	var files: Dictionary = AC.manifest().get("files", {})
	var diff := 0
	var stale := 0
	for rel in a.images:
		var h := GEN.md5(a.images[rel].save_png_to_buffer())
		if h != GEN.md5(b.images[rel].save_png_to_buffer()):
			diff += 1
		if files.get(rel, "") != h:
			stale += 1
			if stale < 4:
				failures.append("shipped %s differs from regenerated g3b output" % rel)
	check_eq(diff, 0, "g3b regenerates byte-identically")
	check_eq(stale, 0, "shipped G3b files match the generator")
	check(a.images.size() >= 110, "G3b image count (%d)" % a.images.size())
