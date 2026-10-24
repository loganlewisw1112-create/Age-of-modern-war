extends "res://tests/test_base.gd"
## Editor core (owner: ED1, CONTRACTS_G4 section 9): brushes, symmetry transforms, undo/redo
## exactness, river/lake shapes, bridge validation, 256x256 brush speed, editor scene smoke.

const Brushes = preload("res://presentation/editor/brushes.gd")
const Symmetry = preload("res://presentation/editor/symmetry.gd")
const Doc = preload("res://presentation/editor/editor_doc.gd")
const T := preload("res://sim/terrain.gd")


func _map(w: int = 32, h: int = 32, code: int = 0) -> Dictionary:
	return Brushes.new_map(w, h, code, 0)


func _count(m: Dictionary, code: int) -> int:
	var n := 0
	for v in m.terrain:
		if int(v) == code:
			n += 1
	return n


func test_shapes_and_paint() -> void:
	var w := 32
	check_eq(Brushes.shape_cells(Vector2i(10, 10), 1, "circle", w, w).size(), 1, "size 1 = one cell")
	check_eq(Brushes.shape_cells(Vector2i(10, 10), 5, "square", w, w).size(), 25, "square 5 = 25 cells")
	var circ := Brushes.shape_cells(Vector2i(10, 10), 5, "circle", w, w).size()
	check(circ > 9 and circ < 25, "circle 5 is rounder than the square (%d)" % circ)
	check_eq(Brushes.shape_cells(Vector2i(0, 0), 5, "square", w, w).size(), 9, "square clipped at the corner")
	check_eq(Brushes.shape_cells(Vector2i(16, 16), 15, "square", w, w).size(), 225, "size 15 max")
	var m := _map()
	var ch := Brushes.paint(m, Brushes.shape_cells(Vector2i(8, 8), 3, "square", w, w), {"code": T.DIRT})
	check_eq(ch.size(), 9, "fill paints every cell")
	check_eq(_count(m, T.DIRT), 9, "terrain written")
	check_eq(Brushes.paint(m, ch, {"code": T.DIRT}).size(), 0, "repainting the same code changes nothing")
	var cells := Brushes.rect_cells(Vector2i(0, 0), Vector2i(31, 31), true, w, w)
	var m2 := _map()
	var sc := Brushes.paint(m2, cells, {"code": T.FOREST, "strength": 30, "seed": 5})
	check(sc.size() > 200 and sc.size() < 420, "scatter 30%% paints about 30%% (%d of 1024)" % sc.size())
	var m3 := _map()
	check_eq(Brushes.paint(m3, cells, {"code": T.FOREST, "strength": 30, "seed": 5}), sc, "scatter is seeded (same seed = same cells)")
	var m4 := _map()
	Brushes.paint(m4, cells, {"code": 2, "layer": "biome"})
	check_eq(int(m4.biome[100]), 2, "biome paint writes the cosmetic layer")
	check_eq(_count(m4, 0), 1024, "biome paint leaves terrain alone")
	var only := Brushes.paint(m, cells, {"code": T.HILL, "only_on": [T.DIRT]})
	check_eq(only.size(), 9, "only_on restricts the codes replaced")


func test_line_and_rect() -> void:
	var l := Brushes.line_cells(Vector2i(0, 0), Vector2i(9, 3))
	check_eq(l.size(), 10, "bresenham length = max(dx,dy)+1")
	check_eq(l[0], Vector2i(0, 0), "line starts at a")
	check_eq(l[l.size() - 1], Vector2i(9, 3), "line ends at b")
	check_eq(Brushes.rect_cells(Vector2i(5, 5), Vector2i(2, 2), true, 32, 32).size(), 16, "filled rect any corner order")
	check_eq(Brushes.rect_cells(Vector2i(2, 2), Vector2i(5, 5), false, 32, 32).size(), 12, "outline rect")
	check(Brushes.thick_line(Vector2i(2, 2), Vector2i(20, 2), 3, "square", 32, 32).size() == 21 * 3, "thick line = 3 rows (stamped 3x3 brush)")


func test_symmetry_transforms() -> void:
	var w := 32
	var h := 20
	var c := Vector2i(3, 4)
	check_eq(Symmetry.images(c, "off", w, h), [c], "off")
	check_eq(Symmetry.images(c, "mirror_x", w, h), [c, Vector2i(28, 4)], "mirror x")
	check_eq(Symmetry.images(c, "mirror_y", w, h), [c, Vector2i(3, 15)], "mirror y")
	check_eq(Symmetry.images(c, "rotate_180", w, h), [c, Vector2i(28, 15)], "rotate 180")
	check_eq(Symmetry.images(c, "four_way", w, h).size(), 4, "4-way has 4 images")
	check_eq(Symmetry.images(Vector2i(5, 9), "mirror_diag", 32, 32), [Vector2i(5, 9), Vector2i(9, 5)], "diagonal")
	check(not Symmetry.valid_for("mirror_diag", 32, 20), "diagonal needs a square map")
	check_eq(Symmetry.images(Vector2i(15, 4), "mirror_x", 31, h), [Vector2i(15, 4)], "the axis cell maps to itself")
	for mode in Symmetry.MODES:
		for k in Symmetry.copy_count(mode):
			var p := Symmetry.transform(Symmetry.transform(c, mode, k, 32, 32), mode, k, 32, 32)
			check_eq(p, c, "%s image %d is an involution" % [mode, k])
	check_eq(Symmetry.expand([c, c], "mirror_x", w, h).size(), 2, "expand dedups")
	var fp := Symmetry.footprints(Vector2i(2, 3), Vector2i(3, 2), "rotate_180", w, h)
	check_eq(fp[1][0], Vector2i(27, 15), "footprint mirrored by its size")
	var fd := Symmetry.footprints(Vector2i(2, 3), Vector2i(3, 2), "mirror_diag", 32, 32)
	check_eq(fd[1], [Vector2i(3, 2), Vector2i(2, 3)], "diagonal footprint swaps size")
	# symmetric paint through the document
	var d := Doc.new()
	d.new_map(32, 32, 0, 0, "t", "", "")
	d.symmetry = "four_way"
	d.apply(Brushes.paint, [Vector2i(1, 1)], {"code": T.CLIFF})
	for p in [Vector2i(1, 1), Vector2i(30, 1), Vector2i(1, 30), Vector2i(30, 30)]:
		check_eq(int(d.map.terrain[p.y * 32 + p.x]), T.CLIFF, "4-way paint reached %s" % p)
	check_eq(_count(d.map, T.CLIFF), 4, "exactly 4 cells")


func test_undo_redo_exact() -> void:
	var d := Doc.new()
	d.new_map(48, 48, 0, 0, "t", "", "")
	var t0: PackedByteArray = d.map.terrain.duplicate()
	var b0: PackedByteArray = d.map.biome.duplicate()
	# one stroke = many brush calls = one step
	d.begin_stroke("paint")
	for x in range(5, 30):
		d.apply(Brushes.paint, Brushes.shape_cells(Vector2i(x, 10), 3, "circle", 48, 48), {"code": T.DIRT})
	d.end_stroke()
	check_eq(d.undo_depth(), 1, "a stroke is one undo step")
	var t1: PackedByteArray = d.map.terrain.duplicate()
	d.apply(Brushes.paint, Brushes.shape_cells(Vector2i(20, 20), 5, "square", 48, 48), {"code": 2, "layer": "biome"})
	d.apply(Brushes.decor_place, [Vector2i(30, 30)], {"id": "factory_block"})
	d.apply(Brushes.resource_place, [Vector2i(40, 40)], {"res": "ore", "amount": 900})
	var full_t: PackedByteArray = d.map.terrain.duplicate()
	var full_decor: Array = d.map.decor.duplicate(true)
	check_eq(d.undo_depth(), 4, "4 steps")
	check_eq(int(d.map.terrain[31 * 48 + 31]), T.BUILDING, "factory footprint is BUILDING")
	d.undo()
	check_eq((d.map.resources as Array).size(), 0, "undo resource")
	d.undo()
	check_eq((d.map.decor as Array).size(), 0, "undo decor")
	check_eq(d.map.terrain, t1, "undo decor restores the BUILDING cells exactly")
	d.undo()
	check_eq(d.map.biome, b0, "undo biome exact")
	d.undo()
	check_eq(d.map.terrain, t0, "undo paint exact")
	check(not d.undo(), "nothing more to undo")
	for i in 4:
		d.redo()
	check_eq(d.map.terrain, full_t, "redo all = same terrain bytes")
	check_eq(d.map.decor, full_decor, "redo all = same decor")
	check_eq((d.map.resources as Array).size(), 1, "redo resource")
	d.undo()
	d.apply(Brushes.paint, [Vector2i(1, 1)], {"code": T.HILL})
	check(not d.can_redo(), "a new edit clears redo")
	# 200-step cap
	for i in 230:
		d.apply(Brushes.paint, [Vector2i(i % 48, 47)], {"code": 1 + (i / 48) % 2})
	check_eq(d.undo_depth(), 200, "stack capped at 200")
	# scenario edits are undoable too (ED2 path)
	d.begin_stroke("move start")
	d.scenario.players[0].start = Vector2i(9, 9)
	d.end_stroke()
	d.undo()
	check(d.scenario.players[0].start != Vector2i(9, 9), "scenario change undone")
	var flag := [0]
	d.push_command({"label": "custom", "undo": func(): flag[0] -= 1, "redo": func(): flag[0] += 1})
	d.undo()
	d.redo()
	check_eq(flag[0], 0, "custom command undo/redo callables ran")


func test_river_shapes() -> void:
	var m := _map(64, 64)
	var ch := Brushes.river(m, [Vector2i(0, 32), Vector2i(63, 32)], {"width": 3, "shallow_edges": true, "ford_every": 0})
	check(ch.size() > 0, "river changed cells")
	for x in [5, 30, 60]:
		check_eq(int(m.terrain[32 * 64 + x]), T.WATER, "river core at x=%d" % x)
		check_eq(int(m.terrain[31 * 64 + x]), T.WATER, "width 3 covers y=31")
		check_eq(int(m.terrain[30 * 64 + x]), T.SHALLOW, "shallow bank at y=30")
		check_eq(int(m.terrain[29 * 64 + x]), T.GRASS, "land beyond the bank")
	var m2 := _map(64, 64)
	Brushes.river(m2, [Vector2i(0, 32), Vector2i(63, 32)], {"width": 1, "shallow_edges": false, "ford_every": 16})
	var fords := _count(m2, T.FORD)
	check(fords >= 3, "auto fords every 16 cells (%d ford cells)" % fords)
	check_eq(_count(m2, T.SHALLOW), 0, "no banks when shallow_edges is off")
	check(_count(m2, T.WATER) >= 50, "width-1 river is a continuous line")
	var m3 := _map(64, 64)
	m3.terrain[32 * 64 + 20] = T.BRIDGE
	Brushes.river(m3, [Vector2i(0, 32), Vector2i(63, 32)], {"width": 3})
	check_eq(int(m3.terrain[32 * 64 + 20]), T.BRIDGE, "river keeps existing bridge cells")


func test_lake_and_ocean() -> void:
	var m := _map(64, 64)
	var cells := Brushes.lake_cells(Vector2i(32, 32), 10, 3, 64, 64)
	check(cells.size() > 200 and cells.size() < 520, "lake radius 10 ~ pi r^2 (%d)" % cells.size())
	check_eq(Brushes.lake_cells(Vector2i(32, 32), 10, 3, 64, 64), cells, "lake shape is seeded")
	Brushes.water_body(m, cells, {"falloff": 2, "beach": 1})
	check_eq(int(m.terrain[32 * 64 + 32]), T.DEEP, "lake centre is DEEP")
	check(_count(m, T.SHALLOW) > 0 and _count(m, T.BEACH) > 0, "shallow rim and beach ring exist")
	var w := 64
	var bad_deep := 0
	var bad_shore := 0
	for y in range(1, 63):
		for x in range(1, 63):
			var c := int(m.terrain[y * w + x])
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := int(m.terrain[(y + d.y) * w + x + d.x])
				if c == T.DEEP and (n == T.GRASS or n == T.BEACH):
					bad_deep += 1
				if c == T.GRASS and (n == T.SHALLOW or n == T.DEEP):
					bad_shore += 1
	check_eq(bad_deep, 0, "DEEP never touches land (depth falloff)")
	check_eq(bad_shore, 0, "every shore cell is BEACH")
	var o := _map(40, 40)
	Brushes.paint(o, Brushes.rect_cells(Vector2i(20, 0), Vector2i(20, 39), true, 40, 40), {"code": T.CLIFF})
	var reg := Brushes.flood_region(o, Vector2i(2, 2))
	check_eq(reg.size(), 20 * 40, "flood region stops at the cliff")
	Brushes.water_body(o, reg, {"falloff": 3, "beach": 0})
	check_eq(int(o.terrain[20 * 40 + 0]), T.DEEP, "map edge counts as open water (deep)")
	check_eq(int(o.terrain[20 * 40 + 19]), T.SHALLOW, "shallow next to the cliff shore")
	check_eq(int(o.terrain[20 * 40 + 25]), T.GRASS, "the other side is untouched")


func test_bridge_validation() -> void:
	var m := _map(40, 40)
	Brushes.river(m, [Vector2i(0, 20), Vector2i(39, 20)], {"width": 3, "shallow_edges": true})
	var ok := Brushes.bridge_check(m, Vector2i(10, 17), Vector2i(10, 23))
	check(bool(ok.ok), "vertical span across the river is valid: %s" % ok.error)
	check_eq((ok.cells as Array).size(), 5, "span covers the 5 water cells")
	check(not bool(Brushes.bridge_check(m, Vector2i(10, 17), Vector2i(12, 23)).ok), "bent span refused")
	check(not bool(Brushes.bridge_check(m, Vector2i(10, 18), Vector2i(10, 23)).ok), "an end in water refused")
	check(not bool(Brushes.bridge_check(m, Vector2i(10, 10), Vector2i(10, 23)).ok), "land inside the span refused")
	check(not bool(Brushes.bridge_check(m, Vector2i(10, 5), Vector2i(10, 8)).ok), "span over no water refused")
	var ch := Brushes.bridge_place(m, ok.cells, {})
	check_eq(ch.size(), 5, "bridge cells written")
	check_eq(int(m.terrain[20 * 40 + 10]), T.BRIDGE, "BRIDGE code on the river")
	check_eq((m.bridges as Array).size(), 1, "map.bridges entry added")
	check(not bool(Brushes.bridge_check(m, Vector2i(10, 17), Vector2i(10, 23)).ok), "cannot cross an existing bridge")


func test_decor_and_resources() -> void:
	var m := _map(40, 40)
	var ch := Brushes.decor_place(m, [Vector2i(5, 5)], {"id": "factory_block"})
	check_eq(ch.size(), 9, "3x3 POI footprint")
	check_eq(int(m.terrain[6 * 40 + 6]), T.BUILDING, "impassable POI writes BUILDING")
	check_eq(Brushes.decor_place(m, [Vector2i(6, 6)], {"id": "bush"}).size(), 0, "no overlap on a footprint")
	Brushes.decor_place(m, [Vector2i(20, 20)], {"id": "bush"})
	check_eq(int(m.terrain[20 * 40 + 20]), T.GRASS, "bushes leave terrain passable")
	Brushes.decor_place(m, [Vector2i(22, 22)], {"id": "tree"})
	check_eq(int(m.terrain[22 * 40 + 22]), T.FOREST, "trees are FOREST cells")
	check_eq((m.decor as Array).size(), 2, "trees add no decor entry")
	var area := Brushes.rect_cells(Vector2i(0, 25), Vector2i(39, 39), true, 40, 40)
	var sc := Brushes.decor_scatter(m, area, {"ids": ["bush", "rocks", "plant"], "density": 20, "seed": 9})
	check(sc.size() > 60 and sc.size() < 180, "scatter density 20 percent (%d of 600)" % sc.size())
	var kinds := {}
	for e in m.decor:
		kinds[String(e.id)] = true
	check(kinds.size() >= 3, "scatter varies the object (%s)" % str(kinds.keys()))
	var er := Brushes.decor_erase(m, [Vector2i(7, 7), Vector2i(22, 22)], {})
	check(er.size() >= 10, "eraser removes the POI and the tree")
	check_eq(int(m.terrain[6 * 40 + 6]), T.GRASS, "erased POI frees its cells")
	check_eq(int(m.terrain[22 * 40 + 22]), T.GRASS, "erased tree")
	var r := _map(40, 40)
	check_eq(Brushes.resource_place(r, [Vector2i(3, 3)], {"res": "ore", "amount": 1200}).size(), 1, "single pile")
	check_eq(Brushes.resource_place(r, [Vector2i(3, 3)], {"res": "ore"}).size(), 0, "no two piles on a cell")
	check_eq(int(r.resources[0].amount), 1200, "amount stored")
	r.terrain[10 * 40 + 10] = T.WATER
	check_eq(Brushes.resource_place(r, [Vector2i(10, 10)], {}).size(), 0, "no piles in water")
	var rs := Brushes.resource_scatter(r, Brushes.rect_cells(Vector2i(0, 15), Vector2i(39, 39), true, 40, 40), {"res": "salvage", "amount": 800, "density": 30, "seed": 2})
	check(rs.size() > 10, "resource scatter placed %d" % rs.size())
	var piles: Array = r.resources
	var close := 0
	for i in piles.size():
		for j in range(i + 1, piles.size()):
			var a: Vector2i = piles[i].cell
			var b: Vector2i = piles[j].cell
			if maxi(absi(a.x - b.x), absi(a.y - b.y)) <= 2 and a.y >= 15 and b.y >= 15:
				close += 1
	check_eq(close, 0, "scattered piles keep a 2-cell gap")
	check_eq(Brushes.resource_erase(r, [Vector2i(3, 3)], {}).size(), 1, "resource eraser")


func test_editor_scene_smoke() -> void:
	# the runner executes before the SceneTree loop starts, so build the editor off-tree
	var ed = load("res://presentation/editor/editor_scene.gd").new()
	ed._ready()
	for id in ["map", "terrain", "water", "nature", "resources"]:
		check(ed.tabs.has(id), "tab %s registered" % id)
		ed.select_tab(id)
		check(ed.view.tool == ed.tab_panel(id), "tab %s is the active tool" % id)
	ed.select_tab("terrain")
	var tp = ed.tab_panel("terrain")
	tp.code = T.HILL
	tp.bsize = 3
	tp.mode = "brush"
	ed.view.scripted_stroke([Vector2i(10, 10), Vector2i(14, 10), Vector2i(18, 12)])
	check_eq(ed.doc.undo_depth(), 1, "a scripted drag stroke is one undo step")
	check_eq(int(ed.doc.map.terrain[10 * int(ed.doc.map.w) + 14]), T.HILL, "the stroke painted along the drag")
	ed.action_undo()
	check_eq(int(ed.doc.map.terrain[10 * int(ed.doc.map.w) + 14]), T.GRASS, "undo button path")
	ed.action_redo()
	ed.select_tab("water")
	var wp = ed.tab_panel("water")
	wp._on_tool(0)
	wp.points = [Vector2i(0, 60), Vector2i(127, 60)]
	wp.finish_river()
	check_eq(int(ed.doc.map.terrain[60 * 128 + 64]), T.WATER, "river tool through the tab")
	wp._on_tool(3)
	check(wp.place_bridge(Vector2i(64, 57), Vector2i(64, 63)), "bridge tool through the tab")
	ed.select_tab("nature")
	var np = ed.tab_panel("nature")
	np._on_tool(1)
	np.selected = ["town_house"]
	ed.view.scripted_stroke([Vector2i(30, 30)])
	check_eq((ed.doc.map.decor as Array).size(), 1, "single POI placed")
	ed.select_tab("resources")
	ed.view.scripted_stroke([Vector2i(40, 40)])
	check_eq((ed.doc.map.resources as Array).size(), 1, "single resource placed")
	ed.view._sync_world()
	var nres := 0
	for e in ed.view.world.entities.values():
		if String(e.kind) == "resource":
			nres += 1
	check_eq(nres, 1, "display world mirrors the resources")
	ed.select_tab("map")
	var mp = ed.tab_panel("map")
	mp.generate()
	check(int(ed.doc.map.w) >= 96 and (ed.doc.scenario.players as Array).size() >= 2, "generate base map from MapGen")
	check_eq(ed.doc.undo_depth(), 0, "generate starts a fresh history")
	var issues: Array = ed.action_validate()
	check(issues is Array, "validate runs (%d issues)" % issues.size())
	ed.free()


func test_brush_speed_256() -> void:
	var d := Doc.new()
	d.new_map(256, 256, 0, 0, "big", "", "")
	d.symmetry = "four_way"
	var t0 := Time.get_ticks_usec()
	d.begin_stroke("big stroke")
	for i in 60:
		d.apply(Brushes.paint, Brushes.shape_cells(Vector2i(20 + i, 40 + i / 2), 15, "circle", 256, 256), {"code": T.DIRT})
	d.end_stroke()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("EDITOR_BRUSH_256 60 dabs size 15 x4 symmetry + undo commit: %.1f ms" % ms)
	check(ms < 1500.0, "60 size-15 4-way dabs + commit on 256x256 under 1.5 s (%.1f ms)" % ms)
	var t1 := Time.get_ticks_usec()
	d.undo()
	var ums := (Time.get_ticks_usec() - t1) / 1000.0
	print("EDITOR_UNDO_256 %.1f ms" % ums)
	check(ums < 300.0, "undo of a big stroke under 300 ms (%.1f ms)" % ums)
	check_eq(_count(d.map, T.DIRT), 0, "undo exact on 256")
