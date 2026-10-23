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
		if int(Content.building(def).get("size", 0)) <= 0 or Content.building(def).get("neutral_structure", false):
			continue  # bridge_span: drawn per cell via bridge_overlay (see test_bridge_overlay)
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
	var g2_fx := {"disabled_smoke": 6, "pinned": 2, "cover": 1, "retreat": 2}
	for n in g2_fx:
		var g2: Array = AC.effect_frames(n)
		check_eq(g2.size(), int(g2_fx[n]), "G2 frame count for " + n)
		for t in g2:
			_real(t, "G2 effect " + n)
	var piv = AC.manifest().get("effects", {}).get("disabled_smoke", {}).get("pivot")
	check(piv is Array and piv.size() == 2, "disabled_smoke carries a pivot")
	var sm: Array = AC.effect_frames("disabled_smoke")
	check(sm[0].get_image().get_data() != sm[3].get_image().get_data(), "disabled_smoke frames animate")
	check_eq(AC.effect_frames("nope").size(), 1, "unknown effect gives 1 placeholder frame")
	var ids: Array = Content.ids("production") + Content.ids("units")
	for def in Content.ids("buildings"):
		if Content.building(def).get("buildable", false) or Content.building(def).get("is_hq", false):
			ids.append(def)
	ids += ["officer", "logistics_truck", "refinery", "repair", "patrol", "guard", "formation_line", "formation_wedge",
		"formation_column", "mission_secure", "mission_hold", "mission_attack", "mission_patrol", "assign_officer"]
	var cmd_imgs := {}
	for id in ["repair", "patrol", "guard", "formation_line", "formation_wedge", "formation_column",
			"mission_secure", "mission_hold", "mission_attack", "mission_patrol", "assign_officer"]:
		cmd_imgs[AC.icon(id).get_image().get_data()] = id
	check_eq(cmd_imgs.size(), 11, "11 distinct command icons")
	for id in ids:
		var t: Texture2D = AC.icon(id)
		if _real(t, "icon " + id):
			check(t.get_width() == 32 and t.get_height() == 32, "icon 32x32 " + id)
	check(AC.icon("nonexistent") == AC._ph(), "missing icon is the placeholder")


func test_bridge_overlay() -> void:
	AC.load_all()
	var looks := {}
	for state in ["intact", "damaged", "ruined"]:
		for cell in [Vector2i(5, 4), Vector2i(4, 4), Vector2i(4, 5), Vector2i(9, 9), Vector2i(12, 11)]:
			var d: Dictionary = AC.bridge_overlay(state, cell)
			if _real(d.get("texture"), "bridge %s %s" % [state, cell]):
				check_eq(d.offset, Vector2(-32, -40), "bridge overlay offset (cell-centre anchor) %s" % state)
				check_eq(d.texture.get_width(), 64, "bridge overlay width")
				looks[d.texture.get_image().get_data()] = true
			check(AC.bridge_overlay(state, cell).texture == d.texture, "bridge overlay deterministic per cell")
	check(looks.size() >= 9, "states x sides give distinct bridge overlays (%d)" % looks.size())
	var a: Image = AC.bridge_overlay("intact", Vector2i(4, 4)).texture.get_image()
	var r: Image = AC.bridge_overlay("ruined", Vector2i(4, 4)).texture.get_image()
	check(a.get_data() != r.get_data(), "ruined differs from intact")
	check(AC.bridge_overlay("bogus", Vector2i(1, 1)).texture == AC._ph(), "unknown bridge state -> placeholder")
	var b: Dictionary = AC.manifest().get("bridge", {})
	for st in b.get("states", {}):
		for side in b.states[st]:
			check_eq(b.states[st][side].size(), 3, "3 variants for bridge %s/%s" % [st, side])


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


## G3a (ART3-B): every faction def has complete art: units 8 facings with the right frame set and a
## sheet of the declared size, wrecks for wreck-leaving vehicles, buildings in 4 states, icons for
## every production item and building (HQs included). Uses faction fields, never def names.
func test_faction_coverage() -> void:
	AC.load_all()
	var man := AC.manifest()
	for fid in Content.faction_ids():
		for def in Content.ids("units"):
			var u: Dictionary = Content.unit(def)
			if String(u.get("faction", "")) != fid:
				continue
			var spec: Dictionary = man.get("infantry", {}).get(def, man.get("vehicles", {}).get(def, {}))
			if not check(not spec.is_empty(), "%s: sprite sheet for unit %s" % [fid, def]):
				continue
			check_eq(int(spec.facings), 8, "8 facings for " + def)
			var frames: Array = spec.frames
			var want: Array = ["idle", "walk_a", "walk_b", "fire"] if String(u.get("move_class", "")) == "foot" else ["idle", "move", "fire"]
			for fr in want:
				check(frames.has(fr), "%s has frame %s" % [def, fr])
			var img: Image = AC._image(String(spec.file))
			if check(img != null, "sheet loads for " + def):
				check_eq(img.get_size(), Vector2i(int(spec.fw) * frames.size(), int(spec.fh) * 8), "sheet size for " + def)
			check(AC._image(String(spec.get("mask", ""))) != null, "team mask for " + def)
			if u.get("leaves_wreck", false):
				check(man.get("vehicle_wrecks", {}).has(def), "wreck sheet for " + def)
		for def in Content.ids("buildings"):
			var b: Dictionary = Content.building(def)
			if String(b.get("faction", "")) != fid or b.get("neutral_structure", false):
				continue
			var entry: Dictionary = man.get("buildings", {}).get(def, {})
			if not check(not entry.is_empty(), "%s: building art for %s" % [fid, def]):
				continue
			check_eq(int(entry.size), int(b.size), "art footprint matches content for " + def)
			for st in ["built", "build_0", "build_1", "build_2"]:
				var s: Dictionary = entry.states.get(st, {})
				check(AC._image(String(s.get("file", ""))) != null, "%s state %s" % [def, st])
			_real(AC.icon(def), "%s: icon for building %s" % [fid, def])
		for id in Content.ids("production"):
			if String(Content.production(id).get("faction", "")) == fid:
				_real(AC.icon(id), "%s: icon for production item %s" % [fid, id])


## Mean (r - g) of the opaque pixels of a sheet region: Human B's rust/khaki reads warmer than
## Human A's olive drab at 1x.
func _warmth(rel: String, region: Rect2i) -> float:
	var img: Image = AC._image(rel)
	if img == null:
		return 0.0
	if region.size == Vector2i.ZERO:
		region = Rect2i(Vector2i.ZERO, img.get_size())
	var sum := 0.0
	var n := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var c := img.get_pixel(x, y)
			if c.a > 0.9:
				sum += c.r - c.g
				n += 1
	return sum / maxi(1, n)


func test_human_b_identity() -> void:
	AC.load_all()
	var man := AC.manifest()
	var pairs := []
	for role in ["heavy", "light", "supply"]:
		pairs.append([Content.role("human_a", role), Content.role("human_b", role)])
	for p in pairs:
		var a: Dictionary = man.get("vehicles", {}).get(p[0], {})
		var b: Dictionary = man.get("vehicles", {}).get(p[1], {})
		if not check(not a.is_empty() and not b.is_empty(), "vehicle specs %s / %s" % p):
			continue
		var wa := _warmth(String(a.file), Rect2i(0, int(a.fh), int(a.fw), int(a.fh)))
		var wb := _warmth(String(b.file), Rect2i(0, int(b.fh), int(b.fw), int(b.fh)))
		check(wb > wa + 0.02, "%s reads warmer than %s (%.3f vs %.3f)" % [p[1], p[0], wb, wa])
	for role in ["hq", "barracks"]:
		var a := String(Content.role("human_a", role))
		var b := String(Content.role("human_b", role))
		var wa := _warmth("buildings/%s_built.png" % a, Rect2i())
		var wb := _warmth("buildings/%s_built.png" % b, Rect2i())
		check(wb > wa + 0.02, "%s reads warmer than %s (%.3f vs %.3f)" % [b, a, wb, wa])
	var start_a: String = Content.faction("human_a").start_units[5]
	var start_b: String = Content.faction("human_b").start_units[5]
	var ta: Texture2D = AC.entity_sprite({"kind": "unit", "def": start_a, "facing": 0.0}, Color("#4f7db0"), 0).texture
	var tb: Texture2D = AC.entity_sprite({"kind": "unit", "def": start_b, "facing": 0.0}, Color("#4f7db0"), 0).texture
	check(ta.get_image().get_data() != tb.get_image().get_data(), "%s differs from %s" % [start_b, start_a])
