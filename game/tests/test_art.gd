extends "res://tests/test_base.gd"
## ArtCatalog API coverage for every content def + generator determinism (agent C-art).

const AC = preload("res://presentation/art/art_catalog.gd")
const GEN = preload("res://tools/gen_art.gd")


func _real(t, what: String) -> bool:
	return check(t != null and t is Texture2D and t != AC._ph() and t.get_width() > 0, "placeholder/null art: " + what)


func test_terrain_decor_fog_ring() -> void:
	AC.load_all()
	check(not AC.manifest().is_empty(), "manifest.json loaded")
	for code in 8:
		var n := AC.terrain_variants(code)
		check(n >= 1, "variants >= 1 for terrain %d" % code)
		for v in n:
			var t: Texture2D = AC.terrain_texture(code, v)
			if _real(t, "terrain %d/%d" % [code, v]):
				check_eq(t.get_width(), 64, "terrain tile width %d" % code)
				check(t.get_height() >= 32, "terrain tile height %d" % code)
	for code in [0, 1, 3, 7]:
		check(AC.manifest().terrain[str(code)].variants >= 3, "3+ variants for terrain %d" % code)
	var trees := 0
	var rocks := 0
	for i in 40:
		var d: Dictionary = AC.decor(3, Vector2i(i, i * 3))
		if not d.is_empty() and _real(d.texture, "tree decor"):
			trees += 1
			check(d.offset is Vector2, "decor offset is Vector2")
		if not AC.decor(7, Vector2i(i * 5, i)).is_empty():
			rocks += 1
	check_eq(trees, 40, "every forest cell gets a tree")
	check(rocks > 10, "ridge cells get rock outcrops (%d/40)" % rocks)
	check(AC.decor(0, Vector2i(3, 4)).is_empty(), "no decor on grass")
	check_eq(AC.decor(3, Vector2i(5, 9)).texture, AC.decor(3, Vector2i(5, 9)).texture, "decor deterministic per cell")
	_real(AC.fog_tile("unexplored"), "fog unexplored")
	_real(AC.fog_tile("explored"), "fog explored")
	for s in [0.6, 1.0, 2.0, 3.0]:
		_real(AC.selection_ring(s), "selection ring %s" % s)


func test_entities_every_def() -> void:
	AC.load_all()
	var blue := Color("#4f7db0")
	var red := Color("#b5583a")
	for def in Content.ids("units"):
		for k in 8:
			for st in [{}, {"moving": true}, {"firing": 2}]:
				var e := {"kind": "unit", "def": def, "owner": 0, "pos": Vector2(1, 1), "facing": k * PI / 4}
				e.merge(st, true)
				var d: Dictionary = AC.entity_sprite(e, blue, 0.37)
				_real(d.texture, "unit %s facing %d %s" % [def, k, str(st)])
				check(d.offset is Vector2 and d.offset.y < 0, "unit offset above ground point " + def)
		var a: Texture2D = AC.entity_sprite({"kind": "unit", "def": def, "facing": 0.0}, blue, 0).texture
		var b: Texture2D = AC.entity_sprite({"kind": "unit", "def": def, "facing": 0.0}, red, 0).texture
		check(a.get_image().get_data() != b.get_image().get_data(), "team colour visibly changes " + def)
		if Content.unit(def).get("leaves_wreck", false):
			_real(AC.entity_sprite({"kind": "wreck", "def": def, "facing": 1.0, "size": 1}, blue, 0).texture, "wreck " + def)
	for def in Content.ids("buildings"):
		var size := int(Content.building(def).size)
		var built: Dictionary = AC.entity_sprite({"kind": "building", "def": def, "built": true, "progress": 1.0}, blue, 0)
		if _real(built.texture, "building " + def):
			check(built.texture.get_width() >= size * 64, "building %s at least footprint wide" % def)
		var seen := {}
		for p in [0.0, 0.4, 0.8]:
			var t: Texture2D = AC.entity_sprite({"kind": "building", "def": def, "built": false, "progress": p}, blue, 0).texture
			_real(t, "construction %s %.1f" % [def, p])
			seen[t] = true
		check_eq(seen.size(), 3, "3 distinct construction looks for " + def)
		_real(AC.entity_sprite({"kind": "wreck", "def": def, "size": size}, blue, 0).texture, "rubble " + def)
	for res in ["salvage", "ore"]:
		_real(AC.entity_sprite({"kind": "resource", "def": res, "res": res, "amount": 100}, blue, 0).texture, "resource " + res)
	var bad: Dictionary = AC.entity_sprite({"kind": "unit", "def": "no_such_def"}, blue, 0)
	check(bad.texture == AC._ph(), "unknown def falls back to the magenta placeholder")


func test_effects_and_icons() -> void:
	AC.load_all()
	for n in ["muzzle", "explosion_small", "explosion_large", "smoke"]:
		var fr: Array = AC.effect_frames(n)
		check(fr.size() >= (2 if n == "muzzle" else 5), "frame count for " + n)
		for t in fr:
			_real(t, "effect " + n)
	check_eq(AC.effect_frames("nope").size(), 1, "unknown effect gives 1 placeholder frame")
	var ids: Array = Content.ids("production") + Content.ids("units")
	for def in Content.ids("buildings"):
		if Content.building(def).get("buildable", false) or def == "hq":
			ids.append(def)
	for id in ids:
		var t: Texture2D = AC.icon(id)
		if _real(t, "icon " + id):
			check(t.get_width() == 32 and t.get_height() == 32, "icon 32x32 " + id)
	check(AC.icon("nonexistent") == AC._ph(), "missing icon is the placeholder")


func test_generator_deterministic() -> void:
	# Regenerate everything in memory and compare against the shipped files' hashes in manifest.json.
	var out: Dictionary = GEN.generate()
	var man := AC.manifest()
	var files: Dictionary = man.get("files", {})
	check_eq(files.size(), out.images.size(), "manifest lists every generated image")
	var mismatch := 0
	for rel in out.images:
		var h := GEN.md5(out.images[rel].save_png_to_buffer())
		if files.get(rel, "") != h:
			mismatch += 1
			if mismatch < 4:
				failures.append("regenerated %s differs from shipped file" % rel)
	check_eq(mismatch, 0, "byte-identical regeneration")
	var again: Dictionary = GEN.generate([preload("res://tools/art/terrain.gd")])
	for rel in again.images:
		check_eq(GEN.md5(again.images[rel].save_png_to_buffer()), files.get(rel, ""), "terrain rerun " + rel)
