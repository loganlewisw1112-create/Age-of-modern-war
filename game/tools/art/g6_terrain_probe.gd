extends SceneTree
## G6 terrain-height probe (ELEV-VIEW): renders a demo height map per biome through the real
## presentation/view/terrain_layer.gd (height mesh, cliff faces, ramps, rims/scree, rail) and fog_layer (fog on
## raised tiles over the right-hand third), in a real window, and saves one screenshot per biome plus a 2x crop.
##   godot --path . -s tools/art/g6_terrain_probe.gd [-- --out=<abs dir>] [--frames=N]
## Default output dir: res://.plan/shots/ELEV-VIEW/ (probe_<biome>.png, probe_<biome>_zoom.png).
## demo_map(biome) is also the fixture of tests/test_elev_view.gd.

const TL = preload("res://presentation/view/terrain_layer.gd")
const FL = preload("res://presentation/view/fog_layer.gd")
const N := 24
const BIOMES := ["temperate", "desert", "snow", "wasteland"]
## Fixture cells (tests): plateau top (level 3), the plain cell in front of its SE face, a hill ramp, valley floor.
const PLATEAU := Vector2i(6, 6)
const BELOW_SE := Vector2i(10, 6)
const RAMP := Vector2i(12, 6)
const VALLEY := Vector2i(7, 17)

class ProbeView:
	extends Node2D
	var world: RefCounted
	var terrain_layer: Node2D
	var player_fid := 0
	var fog: Dictionary = {}
	func world_to_screen(p: Vector2) -> Vector2:
		return Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)
	func fog_of(_fid: int) -> Dictionary:
		return fog

class ProbeWorld:
	extends RefCounted
	var map: Dictionary


## Demo layout: rock/grass plateau (level 3, cliffs, concrete slab on its front edge), a grass hill (level 2) ringed
## by ramps with a road climbing it, a sand dune (level 2, cliffs), a valley (level 0) with a pond and one ramp,
## a straight rail line with a branch.
static func demo_map(biome: int) -> Dictionary:
	var n := N * N
	var t := PackedByteArray()
	t.resize(n)
	var hg := PackedByteArray()
	hg.resize(n)
	hg.fill(1)
	var rp := PackedByteArray()
	rp.resize(n)
	var b := PackedByteArray()
	b.resize(n)
	b.fill(biome)
	for y in N:
		for x in N:
			var i := y * N + x
			var c := Terrain.GRASS if (x * 7 + y * 13) % 11 != 0 else Terrain.DIRT
			if x >= 4 and x <= 9 and y >= 4 and y <= 9:
				hg[i] = 3
				if x <= 5:
					c = Terrain.RIDGE
				elif y <= 5 and x >= 8:
					c = Terrain.FOREST
				elif x >= 8 and y >= 8:
					c = Terrain.BUILDING
			if x >= 13 and x <= 19 and y >= 3 and y <= 9:
				hg[i] = 2
			if x >= 14 and x <= 17 and y >= 15 and y <= 18:
				hg[i] = 2
				c = Terrain.BEACH
			if x >= 4 and x <= 10 and y >= 14 and y <= 20:
				hg[i] = 0
				if x >= 6 and x <= 8 and y >= 16 and y <= 18 and not (x == 7 and y == 17):
					c = Terrain.SHALLOW
			if y == 6 and x >= 10 and x <= 19:
				c = Terrain.ROAD
			if x == 21 or (y == 12 and x >= 17 and x <= 21):
				c = Terrain.RAIL
			t[i] = c
	# ramps: every plain cell touching the hill, and one valley entry (the lower cell carries the slope)
	for y in N:
		for x in N:
			var i := y * N + x
			if hg[i] != 1:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 13 and q.x <= 19 and q.y >= 3 and q.y <= 9:
					rp[i] = 1
	rp[14 * N + 7] = 1
	return {"w": N, "h": N, "terrain": t, "biome": b, "height": hg, "ramps": rp}


## Fog fixture: visible for x < 20 except a strip behind the plateau (x + y < 9), explored up to x = 21,
## unexplored beyond (so the fog edge runs over the raised hill and the rail line).
static func demo_fog() -> Dictionary:
	var vis := PackedByteArray()
	vis.resize(N * N)
	var ex := PackedByteArray()
	ex.resize(N * N)
	for y in N:
		for x in N:
			if x < 20 and x + y >= 9:
				vis[y * N + x] = 1
			if x < 22:
				ex[y * N + x] = 1
	return {"visible": vis, "explored": ex}


var _out := ""
var _frames := 20
var _biome := 0
var _tick := 0
var _view: ProbeView


func _initialize() -> void:
	_out = ProjectSettings.globalize_path("res://.plan/shots/ELEV-VIEW/")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_tick = -1  # build on the first frame (the root is in the tree by then)


func _build() -> void:
	if _view != null:
		_view.queue_free()
	var pw := ProbeWorld.new()
	pw.map = demo_map(_biome)
	_view = ProbeView.new()
	_view.world = pw
	_view.fog = demo_fog()
	root.add_child(_view)
	var layer = TL.new()
	_view.terrain_layer = layer
	_view.add_child(layer)
	layer.setup(_view)
	var fog = FL.new()
	fog.z_index = 4
	_view.add_child(fog)
	fog.setup(_view)
	var cam := Camera2D.new()
	_view.add_child(cam)
	cam.position = Vector2(0, N * 16.0 - 8.0)
	cam.zoom = Vector2(1.0, 1.0)
	cam.make_current()
	_tick = 0


func _process(_delta: float) -> bool:
	if _tick < 0:
		_build()
		return false
	_tick += 1
	if _tick < _frames:
		return false
	var img := root.get_texture().get_image()
	var bname: String = BIOMES[_biome]
	img.save_png(_out.path_join("probe_%s.png" % bname))
	var crop := img.get_region(Rect2i(img.get_width() / 2 - 420, img.get_height() / 2 - 300, 560, 330))
	crop.resize(1120, 660, Image.INTERPOLATE_NEAREST)
	crop.save_png(_out.path_join("probe_%s_zoom.png" % bname))
	print("PROBE %s %s" % [bname, _out.path_join("probe_%s.png" % bname)])
	_biome += 1
	if _biome >= BIOMES.size():
		return true
	_build()
	return false
