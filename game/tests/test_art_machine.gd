extends "res://tests/test_base.gd"
## Machine (Autonomous Network) art coverage through the public ArtCatalog API (agent ART3-M, G3a s7).
## Reads the shipped assets/generated/ files; regenerates the faction_m module in memory for determinism.

const AC = preload("res://presentation/art/art_catalog.gd")


## G5 scope (ORCH, 2026-10-25, authority fact `authority.g3g4_art_test_scope`): units whose art comes from a
## G5 manifest (res://assets/art/g5_*) have a different frame layout and are fully checked by
## tests/test_art_g5_units.gd / test_art_g5_air.gd / test_art_g5_naval.gd, so this G3/G4 test skips them.
static func _g5_art(def: String) -> bool:
	var m: Dictionary = AC.manifest()
	for sec in ["infantry", "vehicles"]:
		var s = m.get(sec, {}).get(def)
		if s is Dictionary and String(s.get("file", "")).begins_with("res://assets/art/g5_"):
			return true
	return false
const GEN = preload("res://tools/gen_art.gd")
const FM = preload("res://tools/art/faction_m.gd")


func _real(t, what: String) -> bool:
	return check(t != null and t is Texture2D and t != AC._ph() and t.get_width() > 0, "placeholder/null art: " + what)


func _ids(table: String) -> Array:
	var a: Array = []
	for id in Content.ids(table):
		if String(Content.table(table)[id].get("faction", "")) == "machine" and not (table == "units" and _g5_art(id)):
			a.append(id)
	return a


## Count emissive cyan pixels (the faction's identity cue) in an image.
func _cyan(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.g > 0.62 and c.b > 0.6 and c.r < c.g - 0.2:
				n += 1
	return n


func test_machine_units() -> void:
	AC.load_all()
	var units := _ids("units")
	check(units.size() >= 8, "8 machine unit defs (%d)" % units.size())
	var blue := Color("#4f7db0")
	var red := Color("#b5583a")
	for def in units:
		var looks := {}
		for k in 8:
			for st in [{}, {"moving": true}, {"firing": 2}]:
				var e := {"kind": "unit", "def": def, "owner": 0, "pos": Vector2(1, 1), "facing": k * PI / 4, "id": 0}
				e.merge(st, true)
				var d: Dictionary = AC.entity_sprite(e, blue, 0.0)
				if _real(d.texture, "unit %s facing %d %s" % [def, k, str(st)]):
					looks[d.texture.get_image().get_data()] = true
				check(d.offset is Vector2 and d.offset.y < 0, "unit offset above ground point " + def)
		check(looks.size() >= 16, "%s: facings and frames look distinct (%d)" % [def, looks.size()])
		var a: Texture2D = AC.entity_sprite({"kind": "unit", "def": def, "facing": 0.0}, blue, 0).texture
		var b: Texture2D = AC.entity_sprite({"kind": "unit", "def": def, "facing": 0.0}, red, 0).texture
		check(a.get_image().get_data() != b.get_image().get_data(), "team colour visibly changes " + def)
		var spec: Dictionary = AC.manifest().get("infantry", {}).get(def, AC.manifest().get("vehicles", {}).get(def, {}))
		check_eq(int(spec.get("facings", 0)), 8, "8 facings " + def)
		if String(Content.unit(def).get("move_class", "")) == "foot":
			check(spec.get("frames", []) == ["idle", "walk_a", "walk_b", "fire"], "legged %s has walk frames" % def)
			var w0: Texture2D = AC.entity_sprite({"kind": "unit", "def": def, "facing": 0.0, "moving": true, "id": 0}, blue, 0.0).texture
			var w1: Texture2D = AC.entity_sprite({"kind": "unit", "def": def, "facing": 0.0, "moving": true, "id": 0}, blue, 1.0 / 6.0).texture
			check(w0.get_image().get_data() != w1.get_image().get_data(), "walk frames alternate " + def)
		else:
			check(spec.get("frames", []) == ["idle", "move", "fire"], "vehicle frames " + def)
		check(_cyan(a.get_image()) + _cyan(AC.entity_sprite({"kind": "unit", "def": def, "facing": PI / 4}, blue, 0).texture.get_image()) >= 2,
			"cyan emissive cue on " + def)
		if Content.unit(def).get("leaves_wreck", false):
			var wr: Texture2D = AC.entity_sprite({"kind": "wreck", "def": def, "facing": 1.0, "size": 1}, blue, 0).texture
			if _real(wr, "wreck " + def):
				check(_cyan(wr.get_image()) == 0, "wreck %s is cold (no glow)" % def)


func test_drone_air_fields() -> void:
	AC.load_all()
	for def in _ids("units"):
		if not Content.unit(def).get("is_air", false):
			continue
		var spec: Dictionary = AC.manifest().get("vehicles", {}).get(def, {})
		check(spec.get("air", false) == true, "air flag in manifest " + def)
		check(int(spec.get("altitude", 0)) >= 8, "altitude offset " + def)
		check(spec.has("bob"), "bob amplitude " + def)
		var sh: Dictionary = spec.get("shadow", {})
		check(sh.get("pivot") is Array and sh.pivot.size() == 2, "shadow pivot " + def)
		var img: Image = AC._image(String(sh.get("file", "")))
		check(img != null and img.get_used_rect().size.x > 10, "separate shadow image " + def)
		if img != null:
			var c := img.get_pixel(int(sh.pivot[0]), int(sh.pivot[1]))
			check(c.a > 0.2 and c.a < 0.8 and c.r < 0.2, "shadow is a translucent dark blob " + def)
		# no shadow baked into the hover frame: the bottom rows under the body stay mostly empty
		var fr: Image = AC.entity_sprite({"kind": "unit", "def": def, "facing": 0.0}, Color.WHITE, 0).texture.get_image()
		var dark := 0
		for x in fr.get_width():
			var p := fr.get_pixel(x, fr.get_height() - 2)
			if p.a > 0.3:
				dark += 1
		check(dark == 0, "drone frame has no baked ground shadow " + def)


func test_machine_buildings_and_icons() -> void:
	AC.load_all()
	var blue := Color("#4f7db0")
	var blds := _ids("buildings")
	check(blds.size() >= 7, "7 machine building defs (%d)" % blds.size())
	for def in blds:
		var size := int(Content.building(def).size)
		var built: Dictionary = AC.entity_sprite({"kind": "building", "def": def, "built": true, "progress": 1.0}, blue, 0)
		if _real(built.texture, "building " + def):
			check(built.texture.get_width() >= size * 64, "building %s at least footprint wide" % def)
			check(_cyan(built.texture.get_image()) >= 3, "cyan emissive cue on " + def)
		var seen := {}
		for p in [0.0, 0.4, 0.8]:
			var t: Texture2D = AC.entity_sprite({"kind": "building", "def": def, "built": false, "progress": p}, blue, 0).texture
			_real(t, "construction %s %.1f" % [def, p])
			seen[t.get_image().get_data()] = true
		check_eq(seen.size(), 3, "3 distinct construction looks for " + def)
		var r: Texture2D = AC.entity_sprite({"kind": "building", "def": def, "built": true}, Color("#b5583a"), 0).texture
		check(r.get_image().get_data() != built.texture.get_image().get_data(), "team colour changes building " + def)
	var ids: Array = _ids("production") + _ids("units") + blds
	for id in ids:
		var t: Texture2D = AC.icon(id)
		if _real(t, "icon " + id):
			check(t.get_width() == 32 and t.get_height() == 32, "icon 32x32 " + id)


func test_machine_deterministic() -> void:
	var a := {"images": {}, "manifest": {}}
	var b := {"images": {}, "manifest": {}}
	FM.build(a)
	FM.build(b)
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
				failures.append("shipped %s differs from regenerated faction_m output" % rel)
	check_eq(diff, 0, "faction_m regenerates byte-identically")
	check_eq(stale, 0, "shipped Machine files match the generator")
	check(a.images.size() >= 80, "Machine image count (%d)" % a.images.size())
