extends "res://tests/test_base.gd"
## G5 building + command icon art (agent ART-BLD, CONTRACTS_G5 s3.4 / s4 / s11). Every building id in
## content/g5/{air,naval,support}.json has a full set in res://assets/art/g5_bld/manifest.json: the
## footprint size of its content def, built + damaged + 3 construction states and every variant state of
## g5_bld.gd state_names (rotations, hangar levels, water sides), each a real image with a same-size
## team mask, damaged != built, team pixels on built / damaged, a 32x32 build icon; strip fields have
## runway segments for all 4 facings, crater, repair and closed overlays; shipped files match their md5s
## and the generator reproduces a def byte-identically. Every new G5 command (SimWorld.COMMANDS handled
## by a G5 system) and every sub-mode has an icon, and every new G5 unit id has a build icon.

const M = preload("res://tools/art/g5_bld.gd")
const IC = preload("res://tools/art/g5_bld_icons.gd")
const GEN = preload("res://tools/gen_art.gd")
const BASE := "res://assets/art/g5_bld/"
const UBASE := "res://assets/art/g5_units/"
const FRAGS := ["res://content/g5/air.json", "res://content/g5/naval.json", "res://content/g5/support.json"]
const UFRAGS := ["res://content/g5/air.json", "res://content/g5/naval.json", "res://content/g5/units_g5.json"]
## CONTRACTS_G5 s3.4, fixed.
const IDS := ["a_airfield", "a_airstrip", "a_hangar_light", "a_hangar_heavy", "a_helipad", "a_air_tower",
	"a_forward_strip", "a_forward_helipad", "b_aerodrome", "b_airstrip", "b_hangar_light", "b_hangar_heavy",
	"b_helipad", "b_air_tower", "b_forward_strip", "b_forward_helipad", "m_launch_rail", "m_drone_bay",
	"a_shipyard", "a_supply_pier", "a_coastal_battery", "b_shipyard", "b_supply_pier", "b_coastal_battery",
	"m_shipyard", "m_supply_pier", "m_coastal_battery", "a_hospital", "a_field_hospital", "b_hospital", "b_field_hospital"]
const G5_SYSTEMS := ["res://sim/systems/airfield.gd", "res://sim/systems/air.gd", "res://sim/systems/naval.gd",
	"res://sim/systems/g5_mech.gd", "res://sim/systems/support.gd", "res://sim/systems/medical.gd",
	"res://sim/systems/transport.gd"]
const G4_TRANSPORT := ["load", "unload", "unload_all"]


func _json(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


func _img(base: String, rel: String) -> Image:
	if rel == "" or not FileAccess.file_exists(base + rel):
		return null
	return Image.load_from_file(base + rel)


func _md5(rel: String) -> String:
	return GEN.md5(FileAccess.get_file_as_bytes(BASE + rel))


func _content_buildings() -> Dictionary:
	var out := {}
	for p in FRAGS:
		var b: Dictionary = _json(p).get("buildings", {})
		for id in b:
			out[id] = b[id]
	return out


func test_every_g5_building_has_art_and_damaged_state() -> void:
	var man := _json(BASE + "manifest.json")
	if not check(not man.is_empty(), "assets/art/g5_bld/manifest.json exists (run tools/art/g5_bld_gen.gd)"):
		return
	var content := _content_buildings()
	var ids: Array = content.keys()
	for id in IDS:
		check(content.has(id), "s3.4 id %s is defined in content/g5" % id)
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	check(ids.size() >= 31, "31 G5 buildings (%d)" % ids.size())
	var bld: Dictionary = man.get("buildings", {})
	var icons: Dictionary = man.get("icons", {})
	for def in ids:
		var e: Dictionary = bld.get(def, {})
		if not check(not e.is_empty() and M.BLD.has(def), "art set for " + def):
			continue
		check_eq(int(e.size), int(content.get(def, {}).get("size", e.size)), "%s footprint size matches content" % def)
		var states: Dictionary = e.states
		var built := _img(BASE, String(states.get("built", {}).get("file", "")))
		for nm in M.state_names(def):
			if not check(states.has(nm), "%s has state %s" % [def, nm]):
				continue
			var im := _img(BASE, String(states[nm].file))
			var mk := _img(BASE, String(states[nm].get("mask", "")))
			if not check(im != null and mk != null, "%s %s image + mask load" % [def, nm]):
				continue
			check_eq(mk.get_size(), im.get_size(), "%s %s mask size" % [def, nm])
			check(im.get_used_rect().size.x > int(e.size) * 40, "%s %s is drawn (%s)" % [def, nm, str(im.get_used_rect())])
			var pv: Array = e.pivot
			check(int(pv[0]) > 0 and int(pv[0]) < im.get_width() and int(pv[1]) > 0 and int(pv[1]) < im.get_height(), "%s pivot inside %s" % [def, nm])
			if not nm.contains("build"):
				check(mk.get_used_rect().size.x > 0, "%s %s has team pixels" % [def, nm])
			if nm.ends_with("damaged") and built != null:
				var base_nm: String = nm.trim_suffix("_damaged") if nm != "damaged" else "built"
				var ref := _img(BASE, String(states[base_nm].file))
				check(ref != null and ref.get_data() != im.get_data(), "%s %s differs from %s" % [def, nm, base_nm])
		var ic := _img(BASE, String(icons.get(def, "")))
		check(ic != null and ic.get_size() == Vector2i(32, 32), "32x32 build icon for " + def)
		if String(e.get("g5", {}).get("variants", "")) == "rot":
			_strips_ok(man, def)
	var files: Dictionary = man.get("files", {})
	var bad := 0
	for rel in files:
		if not FileAccess.file_exists(BASE + rel) or _md5(rel) != String(files[rel]):
			bad += 1
	check(files.size() > 500, "manifest lists its files (%d)" % files.size())
	check_eq(bad, 0, "shipped g5_bld files match the manifest md5s")
	var def := "a_field_hospital"
	var out := {"images": {}, "manifest": {}}
	M.render_def(out, def, M.BLD.keys().find(def))
	var same := 0
	for rel in out.images:
		if GEN.md5((out.images[rel] as Image).save_png_to_buffer()) == String(files.get(rel, "")):
			same += 1
	check_eq(same, out.images.size(), "generator reproduces %s byte-identically" % def)


func _strips_ok(man: Dictionary, def: String) -> void:
	var air: Dictionary = man.get("airfield", {})
	var style := String(air.get("styles", {}).get(def, ""))
	if not check(style != "", "%s has a runway style" % def):
		return
	for f in 4:
		var seg: Dictionary = air.segments.get(style, {}).get(str(f), {})
		for k in ["start", "mid", "end", "link"]:
			var im := _img(BASE, String(seg.get(k, {}).get("file", "")))
			check(im != null and im.get_used_rect().size.x > 20, "%s runway %s f%d %s" % [def, style, f, k])
		check(_img(BASE, String(air.closed.get(str(f), {}).get("file", ""))) != null, "closed overlay f%d" % f)
	check(air.craters.size() >= 2 and air.craters_repair.size() >= 2, "crater + repair overlays")
	for c in air.craters + air.craters_repair:
		check(_img(BASE, String(c.file)) != null, "crater overlay loads " + String(c.file))


func test_every_new_command_has_icon() -> void:
	var man := _json(BASE + "manifest.json")
	if not check(not man.is_empty(), "assets/art/g5_bld/manifest.json exists"):
		return
	var icons: Dictionary = man.get("icons", {})
	var cmds: Array = []
	for k in SimWorld.COMMANDS:
		var s = SimWorld.COMMANDS[k]
		if s is Script and G5_SYSTEMS.has((s as Script).resource_path) and not G4_TRANSPORT.has(k):
			cmds.append(k)
	cmds.sort()
	check(cmds.size() >= 13, "13 G5 commands in SimWorld.COMMANDS (%d)" % cmds.size())
	for k in IC.COMMANDS:
		check(cmds.has(k), "s4 command %s is registered" % k)
	for k in cmds + IC.MODES:
		var im := _img(BASE, String(icons.get(k, "")))
		if not check(im != null and im.get_size() == Vector2i(32, 32), "32x32 icon for command " + k):
			continue
		var ink := 0
		for y in range(4, 28):
			for x in range(4, 28):
				var c := im.get_pixel(x, y)
				if c.r + c.g + c.b > 1.2:
					ink += 1
		check(ink > 12, "%s icon has a visible glyph (%d bright px)" % [k, ink])
	var uicons: Dictionary = _json(UBASE + "manifest.json").get("icons", {})
	for p in UFRAGS:
		var units: Dictionary = _json(p).get("units", {})
		for id in units:
			var ok := (icons.has(id) and _img(BASE, String(icons[id])) != null) or (uicons.has(id) and _img(UBASE, String(uicons[id])) != null)
			check(ok, "build icon for new unit " + id)
