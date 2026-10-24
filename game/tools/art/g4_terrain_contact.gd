extends SceneTree
## G4 terrain contact sheet (ART-T): renders a small demo map per biome through the real
## presentation/view/terrain_layer.gd (tiles + transitions + raised cliffs/hills) and tiles the
## four renders 2x2, plus a 2x crop for close inspection.
##   godot --headless --path . -s tools/art/g4_terrain_contact.gd [-- --out=ABS.png]
## Default output: res://.plan/shots/ART-T/terrain.png (+ terrain_zoom.png).

const TL = preload("res://presentation/view/terrain_layer.gd")
const N := 20

class FakeView:
	extends Node2D
	var world: RefCounted
	func world_to_screen(p: Vector2) -> Vector2:
		return Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)

class FakeWorld:
	extends RefCounted
	var map: Dictionary


## Demo layout (same for every biome): sea in the south corner with beach, a cliff plateau and
## a cliff wall, a hill, a concrete slab, forest, a road, a river with a ford running to the sea.
static func demo_map(biome: int) -> Dictionary:
	var t := PackedByteArray()
	t.resize(N * N)
	var b := PackedByteArray()
	b.resize(N * N)
	b.fill(biome)
	for y in N:
		for x in N:
			var c := Terrain.GRASS
			var d := x + y + (1 if x % 6 == 2 else 0) - (1 if y % 7 == 3 else 0)
			if (x * 7 + y * 13) % 11 == 0:
				c = Terrain.DIRT
			if x >= 3 and x <= 7 and y >= 3 and y <= 6 and not (x == 7 and y == 3):
				c = Terrain.CLIFF
			if x == 10 and y >= 1 and y <= 8:
				c = Terrain.CLIFF
			if x >= 12 and x <= 16 and y >= 2 and y <= 6 and not (x == 14 and y == 4):
				c = Terrain.HILL
			if x >= 2 and x <= 5 and y >= 9 and y <= 12:
				c = Terrain.BUILDING
			if x >= 7 and x <= 10 and y >= 11 and y <= 14:
				c = Terrain.FOREST
			if x == 8 and y <= 9:
				c = Terrain.ROAD
			if (x == 15 or x == 16) and y >= 7 and y <= 11:
				c = Terrain.FORD if y == 9 else Terrain.WATER
			if d >= 24:
				c = Terrain.BEACH
			if d >= 26:
				c = Terrain.SHALLOW
			if d >= 30:
				c = Terrain.DEEP
			if (x == 4 or x == 5) and y == 15:
				c = Terrain.SHALLOW  # a pond: shore on every side
			t[y * N + x] = c
	return {"w": N, "h": N, "terrain": t, "biome": b}


static func render(map: Dictionary, host: Node) -> Image:
	var fw := FakeWorld.new()
	fw.map = map
	var view := FakeView.new()
	view.world = fw
	host.add_child(view)
	var layer = TL.new()
	view.add_child(layer)
	layer.setup(view)
	var w := int(map.w)
	var h := int(map.h)
	var ox := h * 32
	var img := Image.create((w + h) * 32, (w + h) * 16 + layer.pad + 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.03, 0.035, 0.04))
	for k in layer._chunks:
		var spr: Sprite2D = layer._chunks[k]
		var src: Image = spr.texture.get_image()
		img.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i(spr.position) + Vector2i(ox, layer.pad))
	view.queue_free()
	return img


func _init() -> void:
	var out := ProjectSettings.globalize_path("res://.plan/shots/ART-T/terrain.png")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var parts: Array = []
	for b in 4:
		parts.append(render(demo_map(b), root))
	var pw: int = parts[0].get_width()
	var ph: int = parts[0].get_height()
	var sheet := Image.create(pw * 2, ph * 2, false, Image.FORMAT_RGBA8)
	for b in 4:
		sheet.blit_rect(parts[b], Rect2i(0, 0, pw, ph), Vector2i((b % 2) * pw, (b / 2) * ph))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	sheet.save_png(out)
	var zoom: Image = parts[0].get_region(Rect2i(pw / 2 - 160, ph / 2 - 40, 480, 300))
	zoom.resize(960, 600, Image.INTERPOLATE_NEAREST)
	zoom.save_png(out.get_basename() + "_zoom.png")
	print("CONTACT %s (%dx%d)" % [out, sheet.get_width(), sheet.get_height()])
	quit(0)
