extends "res://tests/test_base.gd"
## G4 terrain art + renderer (agent ART-T, CONTRACTS_G4 s2.2): every terrain code and biome has a
## tile, transition atlases are complete, sizes are sane, the module regenerates byte-identically
## and matches the shipped files, and terrain_layer applies biomes/transitions/raise and rebakes.

const AC = preload("res://presentation/art/art_catalog.gd")
const GEN = preload("res://tools/gen_art.gd")
const G4T = preload("res://tools/art/g4_terrain.gd")
const TL = preload("res://tools/art/g4_terrain_tiles.gd")
const TR = preload("res://tools/art/g4_terrain_trans.gd")
const LAYER = preload("res://presentation/view/terrain_layer.gd")
const CONTACT = preload("res://tools/art/g4_terrain_contact.gd")
const BIOME_NEUTRAL := [4, 5, 6]   # river water, bridge deck, ford: one look in every biome

class FakeView:
	extends Node2D
	var world: RefCounted
	func world_to_screen(p: Vector2) -> Vector2:
		return Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)

class FakeWorld:
	extends RefCounted
	var map: Dictionary


func _g4() -> Dictionary:
	return AC.manifest().get("terrain_g4", {})


func test_g4_terrain_every_code_and_biome() -> void:
	var man := AC.manifest()
	var terr: Dictionary = man.get("terrain", {})
	var g4 := _g4()
	check(not g4.is_empty(), "manifest terrain_g4 present")
	var raise: Dictionary = g4.get("raise", {})
	var bv: Dictionary = g4.get("biome_variants", {})
	check_eq(g4.get("biomes", []), ["temperate", "desert", "snow", "wasteland"], "biome order = map.biome values")
	for code in 14:
		var t: Dictionary = terr.get(str(code), {})
		if not check(not t.is_empty(), "terrain code %d in manifest" % code):
			continue
		check_eq(String(t.name), String(Terrain.NAMES[code]), "name of code %d" % code)
		var want_h := 32 + int(raise.get(str(code), 0))
		for v in int(t.variants):
			var img: Image = AC._image("terrain/%s_%d.png" % [t.name, v])
			if check(img != null, "tile %s_%d loads" % [t.name, v]):
				check_eq(img.get_size(), Vector2i(64, want_h), "size of %s_%d" % [t.name, v])
		if BIOME_NEUTRAL.has(code):
			continue
		if not check(bv.has(str(code)), "biome looks for code %d" % code):
			continue
		for b in range(1, 4):
			for v in int(bv[str(code)]):
				var rel := "terrain/%s_b%d_%d.png" % [t.name, b, v]
				var img: Image = AC._image(rel)
				if check(img != null, rel + " loads"):
					check_eq(img.get_size(), Vector2i(64, want_h), "size of " + rel)
	check_eq(int(raise.get("12", 0)), 16, "cliff raise")
	check(int(raise.get("13", 0)) > 0 and int(raise.get("13", 0)) < 16, "hill raise below cliff")


func test_g4_terrain_tiles_sane() -> void:
	for code in [8, 9, 10, 11, 12, 13]:
		for b in 4:
			var img := TL.tile(code, b, 0)
			var r: int = TL.RAISE.get(code, 0)
			check_eq(img.get_pixel(0, 0).a, 0.0, "tile %d/b%d transparent outside the diamond" % [code, b])
			check_eq(img.get_pixel(63, 31 + r).a, 0.0, "tile %d/b%d transparent bottom-right" % [code, b])
			check_eq(img.get_pixel(32, 16).a, 1.0, "tile %d/b%d opaque centre" % [code, b])
			var c := img.get_pixel(32, 16)
			check(not (c.r > 0.95 and c.b > 0.95 and c.g < 0.05), "tile %d/b%d not magenta" % [code, b])
			if r > 0:
				check_eq(img.get_pixel(32, 31 + r).a, 1.0, "raised tile %d/b%d has a face down to the ground" % [code, b])


func test_g4_terrain_transition_sets_complete() -> void:
	var g4 := _g4()
	var trans: Dictionary = g4.get("trans", {})
	for k in TR.KINDS:
		var img: Image = AC._image(String(trans.get(k, "")))
		if not check(img != null, "atlas %s loads" % k):
			continue
		check_eq(img.get_size(), Vector2i(1024, 64), "atlas %s size" % k)
		for row in 2:
			check(_alpha(img, 0, row) == 0, "atlas %s row %d mask 0 empty" % [k, row])
			for m in range(1, 16):
				check(_alpha(img, m, row) > 0, "atlas %s row %d mask %d drawn" % [k, row, m])
	# an edge bit draws at its own edge only: N (bit 1) is the upper-right edge of the diamond
	var foam: Image = AC._image(String(trans.get("foam", "")))
	if foam != null:
		check(foam.get_pixel(64 + 48, 9).a > 0.0, "foam N edge drawn at the upper-right edge")
		check_eq(foam.get_pixel(64 + 16, 23).a, 0.0, "foam N edge leaves the lower-left edge clear")
		check(foam.get_pixel(4 * 64 + 16, 23).a > 0.0, "foam S edge drawn at the lower-left edge")
	var rules: Array = g4.get("rules", [])
	check(rules.size() >= 6, "transition rules (%d)" % rules.size())
	for r in rules:
		check(trans.has(String(r.get("art", r.kind))), "rule %s has an atlas" % r.kind)


func _alpha(img: Image, m: int, row: int) -> int:
	var n := 0
	for y in 32:
		for x in 64:
			if img.get_pixel(m * 64 + x, row * 32 + y).a > 0.0:
				n += 1
	return n


func test_g4_terrain_deterministic() -> void:
	var a := {"images": {}, "manifest": {}}
	var b := {"images": {}, "manifest": {}}
	G4T.build(a)
	G4T.build(b)
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
				failures.append("shipped %s differs from regenerated g4_terrain output" % rel)
	check_eq(diff, 0, "g4_terrain regenerates byte-identically")
	check_eq(stale, 0, "shipped G4 terrain files match the generator")
	check_eq(a.images.size(), 104, "G4 terrain image count")
	for rel in a.images:
		check(String(rel).begins_with("terrain/"), "g4_terrain writes only terrain entries: " + rel)
	check_eq(JSON.stringify(a.manifest.terrain_g4), JSON.stringify(b.manifest.terrain_g4), "manifest block stable")


func _layer(map: Dictionary) -> Array:
	var fw := FakeWorld.new()
	fw.map = map
	var view := FakeView.new()
	view.world = fw
	var layer = LAYER.new()
	view.add_child(layer)
	layer.setup(view)
	return [view, layer]


## Pixel at the centre of cell (x, y) in the baked chunk (top face; raised tiles are lifted).
func _cell_px(layer, x: int, y: int, lift: int = 0) -> Color:
	var key := Vector2i((x / 16) * 16, (y / 16) * 16)
	var img: Image = layer._chunks[key].texture.get_image()
	var i := x - key.x
	var j := y - key.y
	return img.get_pixel(512 + (i - j) * 32, (i + j) * 16 + layer.pad - lift + 16)


func test_g4_terrain_renderer() -> void:
	var temperate: Dictionary = CONTACT.demo_map(0)
	var a := _layer(temperate)
	var layer = a[1]
	check_eq(layer.pad, 16, "chunk top margin = cliff raise")
	check_eq(layer._chunks.size(), 4, "20x20 demo map -> 4 chunks")
	check(layer._rules.size() >= 6, "transition rules loaded (%d)" % layer._rules.size())
	# shore: a SHALLOW cell next to BEACH gets foam, a SHALLOW cell in open water does not
	var t: PackedByteArray = temperate.terrain
	var shore := Vector2i(-1, -1)
	var open := Vector2i(-1, -1)
	for y in 20:
		for x in 20:
			if t[y * 20 + x] != Terrain.SHALLOW or x == 0 or y == 0 or x == 19 or y == 19:
				continue
			var land := false
			var all_water := true
			for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
				var c := int(t[(y + d.y) * 20 + x + d.x])
				land = land or (c == Terrain.BEACH and absi(d.x) + absi(d.y) == 1)
				all_water = all_water and (c == Terrain.SHALLOW)
			if land and shore.x < 0:
				shore = Vector2i(x, y)
			if all_water and open.x < 0:
				open = Vector2i(x, y)
	check(shore.x >= 0 and open.x >= 0, "demo map has shore and open shallow cells")
	var ov := 0
	var plain: Image = layer._tile_cache["9_0"]
	for k in layer._rules.size():
		if layer._rules[k].kind == "foam":
			ov += 1
	check_eq(ov, 1, "one foam rule")
	# the overlay changes the shore cell's pixels relative to the bare shallow tile somewhere on it
	check(_differs_from_tile(layer, shore, plain), "shore cell carries a transition overlay")
	check(not _differs_from_tile(layer, open, plain), "open-water cell is the bare tile")
	# raised cliff: its top face is drawn 16 px above its ground diamond
	var cliff: Image = layer._tile_for(12, 0, 5, 4)
	check_eq(_cell_px(layer, 5, 4, 16), cliff.get_pixel(32, 16), "cliff top face lifted by its raise")
	# biome: the same cell renders the snow tile on the snow map
	var b := _layer(CONTACT.demo_map(2))
	check(_cell_px(b[1], 1, 1) != _cell_px(layer, 1, 1), "snow biome changes the grass")
	check(b[1]._bvar.get(0 * 4 + 2, 0) > 0, "snow grass variants loaded")
	b[0].free()
	# rebake_cells: paint a cliff into open grass; only that chunk (and none else) is rebaked
	var before := _cell_px(layer, 2, 15)
	temperate.terrain[15 * 20 + 2] = Terrain.CLIFF
	layer.rebake_cells([Vector2i(2, 15)])
	check_eq(layer.rebakes, 2, "cell on a chunk border rebakes its own and the neighbour chunk")
	check(_cell_px(layer, 2, 15, 16) != before, "rebaked cell shows the new code")
	a[0].free()


func _differs_from_tile(layer, c: Vector2i, tile: Image) -> bool:
	var key := Vector2i((c.x / 16) * 16, (c.y / 16) * 16)
	var img: Image = layer._chunks[key].texture.get_image()
	var i := c.x - key.x
	var j := c.y - key.y
	var ox := 512 + (i - j) * 32 - 32
	var oy: int = (i + j) * 16 + int(layer.pad)
	for y in range(4, 28):
		for x in range(16, 48):
			if tile.get_pixel(x, y).a > 0.0 and img.get_pixel(ox + x, oy + y) != tile.get_pixel(x, y):
				return true
	return false
