extends "res://tests/test_base.gd"
## G4 fort art (agent ART-F, CONTRACTS_G4 s6): every wall/gate/tower def has every state
## (conn_0..15, damaged, gate open, build_0..2, built/damaged aliases) with a team mask, the arms
## reach the shared cell edges so runs connect, the 32x32 icons exist, and the module regenerates
## byte-identically and matches the shipped files.

const AC = preload("res://presentation/art/art_catalog.gd")
const GEN = preload("res://tools/gen_art.gd")
const F4 = preload("res://tools/art/g4_fort.gd")

const IDS := ["a_wall", "a_gate", "a_wall_tower", "b_wall", "b_gate", "b_wall_tower",
	"m_barrier", "m_field_gate", "m_spire"]


func _kind(def: String) -> String:
	var b: Dictionary = Content.building(def)
	if b.get("gate", false):
		return "gate"
	if b.get("tower", false):
		return "tower"
	return "wall"


## Opaque pixel count and [min x, max x] of the opaque pixels.
func _stats(img: Image) -> Array:
	var n := 0
	var x0 := img.get_width()
	var x1 := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a >= 0.6:
				n += 1
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
	return [n, x0, x1]


func _mask_px(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				n += 1
	return n


func test_fort_defs_match_content() -> void:
	var content_ids: Array = []
	for def in Content.ids("buildings"):
		var b: Dictionary = Content.building(def)
		if b.get("g6", false):
			continue  # G6 (CONTENT6 CR): nanite wall / phase gate art is G6 (tests/test_art_g6.gd)
		if def == "a_g71_berm":
			var berm: Dictionary = AC.manifest().get("buildings", {}).get(def, {})
			var built: Dictionary = berm.get("states", {}).get("built", {})
			check(AC._image(String(built.get("file", ""))) != null, "G7.1 berm has its own fort art")
			continue
		if b.get("wall", false) or b.get("gate", false) or b.get("tower", false):
			content_ids.append(def)
	content_ids.sort()
	var spec: Array = F4.SPEC.keys()
	spec.sort()
	check_eq(spec, content_ids, "g4_fort covers exactly the fort defs in content")
	for def in IDS:
		check_eq(String(F4.SPEC[def][1]), _kind(def), "art kind matches content flag for " + def)


func test_fort_every_state_with_mask() -> void:
	var man: Dictionary = AC.manifest().get("buildings", {})
	for def in IDS:
		var e: Dictionary = man.get(def, {})
		if not check(not e.is_empty(), "manifest entry for " + def):
			continue
		check_eq(int(e.size), 1, "fort art footprint 1 for " + def)
		check(e.pivot is Array and e.pivot.size() == 2, "pivot for " + def)
		var want: Array = F4.state_names(_kind(def))
		check_eq(want.size(), 53 if _kind(def) == "gate" else 37, "state count for " + def)
		var dims := Vector2i(-1, -1)
		for st in want:
			var s: Dictionary = e.states.get(st, {})
			if not check(not s.is_empty(), "%s has state %s" % [def, st]):
				continue
			var img := AC._image(String(s.get("file", "")))
			var mk := AC._image(String(s.get("mask", "")))
			if not check(img != null and mk != null, "%s %s image + mask load" % [def, st]):
				continue
			check_eq(mk.get_size(), img.get_size(), "%s %s mask size" % [def, st])
			check(_mask_px(mk) > 0, "%s %s team mask not empty" % [def, st])
			if dims.x < 0:
				dims = img.get_size()
			check_eq(img.get_size(), dims, "%s %s same canvas as the other states" % [def, st])
		check(dims.x >= 64, "%s at least footprint wide" % def)
		var icon: Texture2D = AC.icon(def)
		check(icon != AC._ph() and icon.get_width() == 32 and icon.get_height() == 32, "32x32 icon for " + def)


func test_fort_conn_states_connect() -> void:
	var man: Dictionary = AC.manifest().get("buildings", {})
	for def in IDS:
		var e: Dictionary = man.get(def, {})
		if e.is_empty():
			check(false, "manifest entry for " + def)
			continue
		var kind := _kind(def)
		var px := int(e.pivot[0])
		var seen := {}
		var st: Array = []
		for m in 16:
			var img := AC._image(String(e.states["conn_%d" % m].file))
			seen[img.get_data()] = true
			st.append(_stats(img))
			var dmg := AC._image(String(e.states["conn_%d_damaged" % m].file))
			check(dmg.get_data() != img.get_data(), "%s conn_%d damaged differs" % [def, m])
			if kind == "gate":
				var op := AC._image(String(e.states["conn_%d_open" % m].file))
				check(op.get_data() != img.get_data(), "%s conn_%d open differs from closed" % [def, m])
		check_eq(seen.size(), 16, "16 distinct conn looks for " + def)
		# N (1) and E (2) arms run to the right half of the diamond, S (4) and W (8) to the left half;
		# each arm must reach the shared cell edge (+-16 px from the pivot column) so runs join.
		for bit in [1, 2]:
			check(int(st[bit][2]) >= px + 15, "%s conn_%d reaches the cell edge (x1 %d, pivot %d)" % [def, bit, st[bit][2], px])
		for bit in [4, 8]:
			check(int(st[bit][1]) <= px - 15, "%s conn_%d reaches the cell edge (x0 %d, pivot %d)" % [def, bit, st[bit][1], px])
		if kind != "gate":
			# the N/W arms of a tower sit behind its core in isometric view; walls show all four
			for bit in ([2, 4] if kind == "tower" else [1, 2, 4, 8]):
				check(int(st[bit][0]) > int(st[0][0]), "%s conn_%d adds an arm to conn_0" % [def, bit])
			check(int(st[15][0]) > int(st[2][0]), "%s cross bigger than one arm" % def)
		var e0: Dictionary = e.states.built
		check_eq(String(e0.file), String(e.states.conn_0.file), "built aliases conn_0 for " + def)
		var looks := {}
		for s in ["build_0", "build_1", "build_2", "conn_0"]:
			looks[AC._image(String(e.states[s].file)).get_data()] = true
		check_eq(looks.size(), 4, "3 construction stages distinct from the finished look for " + def)


func test_fort_team_colour_and_catalog() -> void:
	for def in IDS:
		var a: Texture2D = AC.entity_sprite({"kind": "building", "def": def, "built": true}, Color("#4f7db0"), 0).texture
		var b: Texture2D = AC.entity_sprite({"kind": "building", "def": def, "built": true}, Color("#b5583a"), 0).texture
		check(a != AC._ph(), "catalog draws " + def)
		check(a.get_image().get_data() != b.get_image().get_data(), "team colour changes " + def)


func test_fort_deterministic() -> void:
	var a := {"images": {}, "manifest": {}}
	var b := {"images": {}, "manifest": {}}
	F4.build(a)
	F4.build(b)
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
				failures.append("shipped %s differs from regenerated g4_fort output" % rel)
	check_eq(diff, 0, "g4_fort regenerates byte-identically")
	check_eq(stale, 0, "shipped fort files match the generator")
	check_eq(a.images.size(), 735, "fort image count (9 defs x states x 2 + 9 icons)")
	for rel in a.images:
		var r := String(rel)
		var ok := r.begins_with("icons/") or r.begins_with("buildings/")
		var mine := false
		for def in IDS:
			if r.get_file().begins_with(def + "_") or r.get_file() == def + ".png":
				mine = true
		check(ok and mine, "g4_fort writes only its own fort entries: " + r)
	check_eq(JSON.stringify(a.manifest), JSON.stringify(b.manifest), "manifest block stable")
	# round-trip through JSON so ints and the loaded floats compare alike
	var regen := JSON.stringify(JSON.parse_string(JSON.stringify(a.manifest.buildings)))
	var shipped := JSON.stringify(JSON.parse_string(JSON.stringify(_shipped(IDS))))
	check_eq(regen, shipped, "shipped manifest entries match")


func _shipped(ids: Array) -> Dictionary:
	var man: Dictionary = AC.manifest().get("buildings", {})
	var out := {}
	for def in ids:
		out[def] = man.get(def, {})
	return out
