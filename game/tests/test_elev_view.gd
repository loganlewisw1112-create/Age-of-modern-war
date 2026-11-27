extends "res://tests/test_base.gd"
## G6 acceptance (owner: ELEV-VIEW). CONTRACTS_G6 section 7, section 17; PLAN_G6 A1 (render).
## Terrain height is drawn as cached chunk meshes (vertices lifted ViewUtil.level_px per level, cliff faces, sloped ramps) in
## every terrain style, back-to-front across levels, with fog and picking on the raised tiles.
## Fixture: tools/art/g6_terrain_probe.gd demo_map (24x24: plateau level 3, ramp-ringed hill 2, sand dune 2,
## valley 0 with a ramp, rail line).

const VU = preload("res://presentation/view/view_util.gd")
const LAYER = preload("res://presentation/view/terrain_layer.gd")
const FOG = preload("res://presentation/view/fog_layer.gd")
const CAM = preload("res://presentation/view/camera_rig.gd")
const PROBE = preload("res://tools/art/g6_terrain_probe.gd")
const ART = preload("res://tools/art/g6_terrain.gd")
const GEN = preload("res://tools/gen_art.gd")
const DIR := "res://assets/art/g6_terrain/"


func _view(map: Dictionary):
	var pw = PROBE.ProbeWorld.new()
	pw.map = map
	var v = PROBE.ProbeView.new()
	v._world = pw
	v.fog = PROBE.demo_fog()
	var layer = LAYER.new()
	v.terrain_layer = layer
	v.add_child(layer)
	layer.setup(v)
	return v


func _flat_map() -> Dictionary:
	var m: Dictionary = PROBE.demo_map(0)
	m.erase("height")
	m.erase("ramps")
	return m


func _arrays(layer, key: Vector2i) -> Array:
	var m: Dictionary = layer.mv._world.map
	return layer._mesh_arrays(key.x, key.y, m.terrain, m.biome, layer._hg(), layer._rp(),
		Vector2(1024, layer._flat_h() + layer.FACE_H))


func _has_vert(vs: PackedVector2Array, p: Vector2) -> bool:
	for v in vs:
		if v.distance_to(p) < 0.01:
			return true
	return false


## Flat (unlifted) top vertex of cell c in its chunk's local px.
func _flat_top(layer, c: Vector2i) -> Vector2:
	var i := c.x % 16
	var j := c.y % 16
	return Vector2(512 + (i - j) * 32, (i + j) * 16 + layer.pad)


## Index of the last triangle (= drawn on top) containing chunk-local point p; -1 = none. Zero-area triangles
## (a face with one flush end) draw nothing and are skipped. Geometry2D.point_is_inside_triangle excludes the
## edges, so probe points must sit strictly inside a triangle (not on a quad's diagonal).
func _top_tri(arr: Array, p: Vector2) -> int:
	var vs: PackedVector2Array = arr[0]
	var ix: PackedInt32Array = arr[3]
	var hit := -1
	for t in ix.size() / 3:
		var a := vs[ix[t * 3]]
		var b := vs[ix[t * 3 + 1]]
		var c := vs[ix[t * 3 + 2]]
		if absf((b - a).cross(c - a)) < 0.001:
			continue
		if Geometry2D.point_is_inside_triangle(p, a, b, c):
			hit = t
	return hit


## Every cliff face the height data calls for in chunk `key`, derived from the height rule (VU.vtx), not from
## the mesh: "lip left|lip right|foot left|foot right" (chunk-local px) -> Vector3i(cell x, cell y, 1).
## SW face: our left -> bottom vertices over S's top / right; SE face: our bottom -> right over E's left / top.
func _expected_faces(layer, key: Vector2i) -> Dictionary:
	var m: Dictionary = layer.mv._world.map
	var hg: PackedByteArray = layer._hg()
	var rp: PackedByteArray = layer._rp()
	var w := int(m.w)
	var h := int(m.h)
	var lp: float = VU.level_px
	var out := {}
	for j in 16:
		for i in 16:
			var x := key.x + i
			var y := key.y + j
			if x >= w or y >= h:
				continue
			var pv := VU.vtx(hg, rp, w, h, x, y)
			var tp := _flat_top(layer, Vector2i(x, y))
			var sides := []
			if y + 1 < h:
				var ps := VU.vtx(hg, rp, w, h, x, y + 1)
				sides.append([tp + Vector2(-32, 16), tp + Vector2(0, 32), VU.vtx_at(pv, 3), VU.vtx_at(pv, 2), VU.vtx_at(ps, 0), VU.vtx_at(ps, 1)])
			if x + 1 < w:
				var pe := VU.vtx(hg, rp, w, h, x + 1, y)
				sides.append([tp + Vector2(0, 32), tp + Vector2(32, 16), VU.vtx_at(pv, 2), VU.vtx_at(pv, 1), VU.vtx_at(pe, 3), VU.vtx_at(pe, 0)])
			for sd in sides:
				var la: int = sd[2]
				var lb: int = sd[3]
				var na: int = sd[4]
				var nb: int = sd[5]
				if la <= na and lb <= nb:
					continue
				var ta: Vector2 = sd[0] - Vector2(0.0, (la - 1) * lp)
				var tb: Vector2 = sd[1] - Vector2(0.0, (lb - 1) * lp)
				var fa := ta + Vector2(0.0, maxi(0, la - na) * lp)
				var fb := tb + Vector2(0.0, maxi(0, lb - nb) * lp)
				out["%s|%s|%s|%s" % [ta, tb, fa, fb]] = Vector3i(x, y, 1)
	return out


## What triangle t draws: Vector3i(cell x, cell y, 0) for a top quad (decoded from its UVs = flat position), or
## (cell x, cell y, 1) for a face (its quad's 4 corners looked up in _expected_faces; (-2, -2, 1) = a face the
## height data does not call for). t < 0 (nothing drawn there) -> (-1, -1, -1).
func _tri_cell(layer, arr: Array, key: Vector2i, t: int, faces: Dictionary = {}) -> Vector3i:
	if t < 0:
		return Vector3i(-1, -1, -1)
	var uv: PackedVector2Array = arr[1]
	var ix: PackedInt32Array = arr[3]
	var vs: PackedVector2Array = arr[0]
	var size := Vector2(1024, layer._flat_h() + layer.FACE_H)
	var cu := Vector2.ZERO
	for k in 3:
		cu += uv[ix[t * 3 + k]] * size
	cu /= 3.0
	if cu.y >= float(layer._flat_h()):
		var fx: Dictionary = faces if not faces.is_empty() else _expected_faces(layer, key)
		var q := ix[t * 3]  # both face triangles start at the quad's first corner (lip left)
		var fk := "%s|%s|%s|%s" % [vs[q], vs[q + 1], vs[q + 2], vs[q + 3]]
		return fx.get(fk, Vector3i(-2, -2, 1))
	var a := (cu.x - 512.0) / 32.0
	var b := (cu.y - float(layer.pad)) / 16.0
	return Vector3i(key.x + floori((a + b) * 0.5), key.y + floori((b - a) * 0.5), 0)


func test_height_offset_draw() -> void:
	check_eq(VU.lift_px(1.0), 0.0, "plain draws unlifted")
	var lp: float = VU.level_px
	check_eq(VU.level_px, VU.LEVEL_PX_DEFAULT, "one tunable lift constant")
	check(lp >= 24.0, "cliff faces read at normal zoom: level_px %.0f >= 24" % lp)
	check_eq(VU.lift_px(3.0), 2.0 * lp, "ridge lifted 2 x level_px")
	check_eq(VU.lift_px(0.0), -lp, "valley sunk level_px")
	var v = _view(PROBE.demo_map(0))
	var layer = v.terrain_layer
	check(not layer.hmap.is_empty(), "height map read from map.height / map.ramps")
	check_eq(layer._chunks.size(), 4, "24x24 -> 4 chunks")
	var meshes := 0
	for k in layer._chunks:
		var ch = layer._chunks[k]
		if ch is MeshInstance2D and ch.mesh != null and ch.material != null and ch.texture != null:
			meshes += 1
	check_eq(meshes, 4, "every height chunk is a cached textured mesh")
	check_eq(layer.meshes_built, 4, "meshes built once at setup (nothing per frame)")
	var a0 := _arrays(layer, Vector2i(0, 0))
	var pt := _flat_top(layer, PROBE.PLATEAU)
	check(_has_vert(a0[0], pt - Vector2(0, 2.0 * lp)), "level-3 cell top vertex lifted 2 x level_px")
	# every vertex of the level-3 cell's top triangles sits exactly 2 x level_px above its flat (UV) position
	# (a bare "no vertex at the flat top" test is wrong: cell (7,7) is level 3 too and its lifted top vertex
	# lands exactly on (6,6)'s flat top)
	var size := Vector2(1024, layer._flat_h() + layer.FACE_H)
	var ix0: PackedInt32Array = a0[3]
	var vs0: PackedVector2Array = a0[0]
	var uv0: PackedVector2Array = a0[1]
	var lifted := 0
	var unlifted := 0
	for t in ix0.size() / 3:
		if _tri_cell(layer, a0, Vector2i(0, 0), t) != Vector3i(PROBE.PLATEAU.x, PROBE.PLATEAU.y, 0):
			continue
		for k in 3:
			var vi := ix0[t * 3 + k]
			if vs0[vi].distance_to(uv0[vi] * size - Vector2(0, 2.0 * lp)) < 0.01:
				lifted += 1
			else:
				unlifted += 1
	check(lifted >= 6 and unlifted == 0, "every vertex of the level-3 cell's top is lifted 2 x level_px (%d lifted, %d not)" % [lifted, unlifted])
	check(_has_vert(a0[0], _flat_top(layer, Vector2i(2, 2))), "plain cell unlifted")
	var a16 := _arrays(layer, Vector2i(0, 16))
	check(_has_vert(a16[0], _flat_top(layer, PROBE.VALLEY) + Vector2(0, lp)), "valley cell sunk level_px")
	var hm: Dictionary = layer.height_map()
	check_eq(VU.ground_level(hm, Vector2(PROBE.RAMP) + Vector2(0.5, 0.5)), 1.5, "ramp centre halfway up")
	check_eq(VU.world_to_screen_h(hm, Vector2(6.5, 6.5)), VU.iso(Vector2(6.5, 6.5)) - Vector2(0, 2.0 * lp), "entity offset rule on a ridge")
	# published per-cell lift (entity_layer reads terrain_layer.lift_px): the mesh height at every cell centre
	var lt: PackedFloat32Array = layer.lift_px
	check_eq(lt.size(), 24 * 24, "lift_px has one entry per cell")
	var lift_bad := 0
	for y in 24:
		for x in 24:
			if absf(lt[y * 24 + x] - VU.ground_lift(hm, Vector2(x + 0.5, y + 0.5))) > 0.001:
				lift_bad += 1
	check_eq(lift_bad, 0, "lift_px = drawn ground height at each cell centre")
	check_eq(lt[PROBE.PLATEAU.y * 24 + PROBE.PLATEAU.x], 2.0 * lp, "lift_px plateau 2 x level_px")
	check_eq(lt[PROBE.VALLEY.y * 24 + PROBE.VALLEY.x], -lp, "lift_px valley -level_px")
	check_eq(lt[PROBE.RAMP.y * 24 + PROBE.RAMP.x], 0.5 * lp, "lift_px ramp centre half a level up")
	# baked cliff shadow (owner pass): the low cell east of the plateau's SE face, (10,6), sits in the cast
	# shadow in the cached chunk image: clearly darker than the same chunk baked without height
	check(layer._sh_tab.size() == 25 and layer._ao_tab.size() == 16, "shadow + AO overlays built")
	var img_h: Image = layer._bake_image(0, 0, layer._terrain(), layer._biome_arr(), layer._hg(), layer._rp())
	var img_f: Image = layer._bake_image(0, 0, layer._terrain(), layer._biome_arr())
	var sc := _flat_top(layer, Vector2i(10, 6)) + Vector2(0, 16)
	var lum_h := 0.0
	var lum_f := 0.0
	for dy in range(-4, 4):
		for dx in range(-8, 8):
			lum_h += img_h.get_pixel(int(sc.x) + dx, int(sc.y) + dy).get_luminance()
			lum_f += img_f.get_pixel(int(sc.x) + dx, int(sc.y) + dy).get_luminance()
	check(lum_f > 0.0 and lum_h < lum_f * 0.8, "cast shadow baked at the foot of the SE cliff (%.1f vs %.1f unshadowed)" % [lum_h, lum_f])
	v.free()
	# a map without height bakes and draws exactly as before: sprites, no face strip
	var f = _view(_flat_map())
	var fl = f.terrain_layer
	check(fl.hmap.is_empty(), "flat map: no height map")
	check(fl.lift_px.is_empty(), "flat map: no lift table")
	var sprites := 0
	for k in fl._chunks:
		if fl._chunks[k] is Sprite2D:
			sprites += 1
	check_eq(sprites, 4, "flat map keeps Sprite2D chunks")
	var img: Image = fl._chunks[Vector2i(0, 0)].texture.get_image()
	check_eq(img.get_height(), fl._flat_h(), "flat chunk image has no face strip")
	check_eq(VU.world_to_screen_h({}, Vector2(3.5, 7.25)), VU.iso(Vector2(3.5, 7.25)), "flat: offset rule is the old iso")
	f.free()


func test_cliff_and_ramp_tiles_every_style() -> void:
	var p := DIR + "manifest.json"
	if not check(FileAccess.file_exists(p), "g6_terrain manifest shipped"):
		return
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p))
	var out := {"images": {}, "manifest": {}}
	ART.build(out)
	var files: Dictionary = man.get("files", {})
	check_eq(files.size(), out.images.size(), "manifest lists every generated file")
	for rel in out.images:
		check_eq(String(files.get(rel, "")), GEN.md5((out.images[rel] as Image).save_png_to_buffer()), "%s regenerates byte-identically" % rel)
	var faces: Image = out.images["faces.png"]
	for b in 4:
		var means := []
		for s in 4:
			var sum := Color(0, 0, 0, 0)
			for y in range(0, 96, 4):
				for x in range(0, 64, 4):
					sum += faces.get_pixel((b * 4 + s) * 64 + x, y)
			check(sum.a > 0.0, "face style %s biome %d drawn" % [ART.STYLES[s], b])
			means.append(sum)
		for s in range(1, 4):
			check(not means[s].is_equal_approx(means[0]), "biome %d: style %s differs from earth" % [b, ART.STYLES[s]])
		var ramp: Image = out.images["ramp.png"]
		for d in 4:
			check(not ramp.get_region(Rect2i((b * 4 + d) * 64, 0, 64, 32)).is_invisible(), "ramp tread biome %d dir %s" % [b, ART.DIRS[d]])
	# every biome's demo map draws faces in all four styles (earth, rock, sand, wall) of that biome
	for b in 4:
		var v = _view(PROBE.demo_map(b))
		var layer = v.terrain_layer
		check(layer.g6_art, "biome %d: g6 terrain art loaded" % b)
		var blocks := {}
		var faces_n := 0
		for key in layer._chunks:
			var arr := _arrays(layer, key)
			var uv: PackedVector2Array = arr[1]
			var tix: PackedInt32Array = arr[3]
			var th := float(layer._flat_h() + layer.FACE_H)
			# per face triangle: its UV centroid lies strictly inside the 32-px column it samples (a corner UV
			# at a column's right end sits exactly on the next block's boundary)
			for t in tix.size() / 3:
				var q: Vector2 = (uv[tix[t * 3]] + uv[tix[t * 3 + 1]] + uv[tix[t * 3 + 2]]) / 3.0
				if q.y * th >= float(layer._flat_h()):
					blocks[floori(q.x * 1024.0 / 64.0)] = true
					faces_n += 1
		check(faces_n > 0, "biome %d: cliff face quads present" % b)
		for s in 4:
			check(blocks.has(b * 4 + s), "biome %d: %s cliff faces drawn" % [b, ART.STYLES[s]])
		check_eq(blocks.size(), 4, "biome %d: faces only from its own biome row" % b)
		var hg: PackedByteArray = layer._hg()
		var rp: PackedByteArray = layer._rp()
		check_eq(layer._rise_dir(VU.vtx(hg, rp, 24, 24, PROBE.RAMP.x, PROBE.RAMP.y)), 1, "biome %d: ramp west of the hill rises east" % b)
		check(layer._ramp_ov[b * 4 + 1] != null, "biome %d: ramp tread overlay loaded" % b)
		var rail: Image = layer._tile_cache.get("14_0")
		check(rail != null and rail.get_size() == Vector2i(64, 32) and layer._rail_tracks.size() == 16, "biome %d: RAIL tile + tracks" % b)
		v.free()


func test_draw_order_across_levels() -> void:
	var v = _view(PROBE.demo_map(0))
	var layer = v.terrain_layer
	var key := Vector2i(0, 0)
	var arr := _arrays(layer, key)
	var faces := _expected_faces(layer, key)
	check(faces.size() > 0, "fixture has cliff faces in chunk (0,0)")
	# 1. the lifted plateau top is drawn over the plain cells behind it: the back corner (4,4) lifted 2 x level_px
	# covers the flat diamond of the plain cell n = lift / 32 diagonal steps behind it exactly; probe 4 px above its centre (inside its back
	# triangle, off the quad diagonal) is covered by both, and the raised top is the one drawn last
	var lift3: float = VU.lift_px(3.0)
	var nb := int(lift3 / 32.0)
	var back := Vector2i(4, 4)
	var plain := back - Vector2i(nb, nb)
	check(nb >= 1 and is_equal_approx(lift3, nb * 32.0), "ridge lift is whole diagonal steps (%.0f px)" % lift3)
	check_eq(VU.cell_level(layer.height_map(), plain), 1, "%s is plain ground" % plain)
	var p1 := _flat_top(layer, back) + Vector2(0, 16) - Vector2(0, lift3) - Vector2(0, 4)
	var covers_plain := false
	var vs: PackedVector2Array = arr[0]
	var ix: PackedInt32Array = arr[3]
	for k in ix.size() / 3:
		if _tri_cell(layer, arr, key, k, faces) == Vector3i(plain.x, plain.y, 0) and Geometry2D.point_is_inside_triangle(p1, vs[ix[k * 3]], vs[ix[k * 3 + 1]], vs[ix[k * 3 + 2]]):
			covers_plain = true
	check(covers_plain, "the plain cell behind is drawn under the probe point too")
	var t := _top_tri(arr, p1)
	check_eq(_tri_cell(layer, arr, key, t, faces), Vector3i(back.x, back.y, 0), "raised top wins over the plain cell behind")
	t = _top_tri(arr, _flat_top(layer, PROBE.PLATEAU) + Vector2(0, 16) - Vector2(0, lift3) + Vector2(0, 4))
	check_eq(_tri_cell(layer, arr, key, t, faces), Vector3i(PROBE.PLATEAU.x, PROBE.PLATEAU.y, 0), "plateau centre shows its own lifted top")
	# 2. under the plateau's SE edge the cliff face is visible (drawn after the plain behind, not covered in front):
	# probe the middle of (9,6)'s SE face column, 12 px below its lifted lip
	var e := Vector2i(9, 6)
	var se_mid := _flat_top(layer, e) + Vector2(16, 24) - Vector2(0, lift3)
	t = _top_tri(arr, se_mid + Vector2(0, 12))
	check_eq(_tri_cell(layer, arr, key, t, faces), Vector3i(e.x, e.y, 1), "cliff face below the raised edge is on top")
	# 3. top quads go back to front (x + y); each face is one the height data calls for and directly follows its
	# own cell's top; every expected face is drawn
	var last_s := -1
	var last_cell := Vector3i(-1, -1, 0)
	var ok := true
	var drawn := {}
	for k in ix.size() / 3:
		var c := _tri_cell(layer, arr, key, k, faces)
		if c.z == 0:
			if c.x + c.y < last_s:
				ok = false
			last_s = maxi(last_s, c.x + c.y)
			last_cell = c
		elif Vector2i(c.x, c.y) != Vector2i(last_cell.x, last_cell.y):
			ok = false
		else:
			drawn[ix[k * 3]] = true
	check(ok, "mesh triangles back-to-front, faces right after their own cell")
	check_eq(drawn.size(), faces.size(), "every cliff face the height data calls for is drawn once")
	# 4. chunks stay row-major so a chunk in front draws over the one behind
	var order: Array = []
	for ch in layer.get_children():
		if ch.has_meta("k"):
			order.append(ch.get_meta("k"))
	check_eq(order, [Vector2i(0, 0), Vector2i(16, 0), Vector2i(0, 16), Vector2i(16, 16)], "chunk draw order row-major")
	v.free()


func test_fog_on_raised_tiles() -> void:
	var v = _view(PROBE.demo_map(0))
	var fog = FOG.new()
	v.add_child(fog)
	fog.setup(v)
	check(fog.height_on, "fog switches to the height shader on a height map")
	var code := String((fog.material as ShaderMaterial).shader.code)
	check(code.contains("h_tex") and code.contains("level_px"), "height shader walks the view ray")
	check(fog._h_tex != null and fog._h_tex.get_size() == Vector2(24, 24), "height texture uploaded (one texel per cell)")
	var hm: Dictionary = v.terrain_layer.height_map()
	var top := VU.world_to_screen_h(hm, Vector2(PROBE.PLATEAU) + Vector2(0.5, 0.5))
	check_eq(fog.fog_cell_at(top), PROBE.PLATEAU, "fog of a raised tile lands on the raised tile")
	check(Vector2i(VU.iso_inv(top).floor()) != PROBE.PLATEAU, "(the flat projection would pick a cell behind it)")
	var low := VU.world_to_screen_h(hm, Vector2(PROBE.VALLEY) + Vector2(0.5, 0.5))
	check_eq(fog.fog_cell_at(low), PROBE.VALLEY, "fog of a sunk valley tile lands on it")
	var miss := 0
	var rp: PackedByteArray = hm.ramps
	for y in 24:
		for x in 24:
			if rp[y * 24 + x] != 0:
				continue
			var s := VU.world_to_screen_h(hm, Vector2(x + 0.5, y + 0.5))
			if fog.fog_cell_at(s) != VU.pick_cell(hm, s):
				miss += 1
	check(miss <= 24, "fog walk agrees with picking off the ramps (%d misses)" % miss)
	v.free()
	var f = _view(_flat_map())
	var ff = FOG.new()
	f.add_child(ff)
	ff.setup(f)
	check(not ff.height_on, "flat map keeps the original fog draw")
	check(not String((ff.material as ShaderMaterial).shader.code).contains("h_tex"), "flat map: original fog shader")
	f.free()


func test_picking_on_raised_tiles() -> void:
	var v = _view(PROBE.demo_map(0))
	var hm: Dictionary = v.terrain_layer.height_map()
	var exact := 0
	var wrong := 0
	for y in 24:
		for x in 24:
			var c := Vector2i(x, y)
			var s := VU.world_to_screen_h(hm, Vector2(x + 0.5, y + 0.5))
			var p := VU.pick_world(hm, s)
			var q := Vector2i(p.floor())
			if q == c:
				exact += 1
			elif not (q.x + q.y > c.x + c.y and VU.ground_level(hm, p) > VU.ground_level(hm, Vector2(x + 0.5, y + 0.5))):
				wrong += 1  # only a higher cell in front may hide a cell
	check_eq(wrong, 0, "a click never lands behind what is drawn")
	check(exact >= 24 * 24 * 85 / 100, "clicks on cell centres pick that cell (%d / 576)" % exact)
	for y in range(4, 10):
		for x in range(4, 10):
			var s2 := VU.world_to_screen_h(hm, Vector2(x + 0.5, y + 0.5))
			if VU.pick_cell(hm, s2) != Vector2i(x, y):
				wrong += 1
	check_eq(wrong, 0, "every plateau top cell picks itself")
	var cam = CAM.new()
	cam.mv = v
	var top := VU.world_to_screen_h(hm, Vector2(6.5, 6.5))
	check_eq(Vector2i(cam.pick_canvas(top).floor()), Vector2i(6, 6), "camera_rig.pick_canvas uses the terrain height map")
	cam.free()
	v.free()
	for s3 in [Vector2(0, 100), Vector2(-120.5, 333.25), Vector2(400, 410)]:
		check_eq(VU.pick_world({}, s3), VU.iso_inv(s3), "flat map: picking is the old screen_to_world")
