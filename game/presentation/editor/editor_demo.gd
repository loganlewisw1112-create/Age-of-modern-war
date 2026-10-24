extends Node
## Scripted editor tour (owner: ED1) for screenshots and the 60 fps check:
##   godot --path . -- --editor-demo=C:/abs/dir
## Drives every ED1 tab through its real tool methods (tool_begin/drag/end via
## editor_view.scripted_stroke), saves one PNG per tab, a 256x256 fps sample, then quits.

const Brushes = preload("res://presentation/editor/brushes.gd")
const MapIO = preload("res://sim/map_io.gd")

var editor
var shot_dir := ""


func _ready() -> void:
	_run()


func _shot(name: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := shot_dir.path_join(name)
	get_viewport().get_texture().get_image().save_png(path)
	print("EDITOR_SHOT ", path)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _view(c: Vector2, z: float) -> void:
	editor.view.camera.set_zoom_level(z)
	editor.view.center_camera_on(c)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(shot_dir)
	await _wait(10)
	var v = editor.view
	# ---- Map tab: blank 128 map, name it
	editor.select_tab("map")
	var mp = editor.tab_panel("map")
	mp.new_size = 128
	mp.fill = 0
	editor.doc.scenario.name = "ED1 Demo Valley"
	mp.create_new()
	editor.doc.scenario.author = "ED1"
	mp.tab_activated()
	_view(Vector2(64, 64), 0.42)
	await _shot("01_map_tab.png")
	# ---- Terrain tab with rotate-180 symmetry
	editor.doc.symmetry = "rotate_180"
	editor._p.sync_symmetry()
	editor.select_tab("terrain")
	var tp = editor.tab_panel("terrain")
	tp.code = Brushes.DIRT
	tp.bsize = 9
	tp.mode = "brush"
	v.scripted_stroke([Vector2i(22, 22), Vector2i(26, 24), Vector2i(30, 26)])
	tp.code = Brushes.ROAD
	tp.bsize = 2
	tp.mode = "line"
	v.scripted_stroke([Vector2i(22, 22), Vector2i(64, 64)])
	tp.code = Brushes.HILL
	tp.bsize = 7
	tp.mode = "brush"
	v.scripted_stroke([Vector2i(40, 20), Vector2i(48, 18)])
	tp.code = Brushes.CLIFF
	tp.bsize = 2
	tp.mode = "line"
	v.scripted_stroke([Vector2i(30, 44), Vector2i(44, 52)])
	tp.code = Brushes.FOREST
	tp.bsize = 11
	tp.mode = "brush"
	tp.strength = 45
	v.scripted_stroke([Vector2i(16, 50), Vector2i(20, 56), Vector2i(26, 60)])
	tp.strength = 100
	_view(Vector2(40, 40), 0.55)
	await _shot("02_terrain_tab.png")
	# ---- Water tab: river with fords + banks, a lake, a bridge
	editor.select_tab("water")
	var wp = editor.tab_panel("water")
	wp._on_tool(0)
	wp.width = 3
	wp.shallow = true
	wp.ford_every = 24
	wp.points = [Vector2i(0, 70), Vector2i(30, 60), Vector2i(60, 66), Vector2i(90, 54), Vector2i(127, 58)]
	wp.finish_river()
	wp._on_tool(1)
	wp.radius = 9
	wp.tool_begin(Vector2i(28, 96))
	wp._on_tool(3)
	var ok: bool = _bridge_somewhere(wp)
	print("EDITOR_DEMO bridge placed=", ok)
	_view(Vector2(40, 72), 0.5)
	await _shot("03_water_tab.png")
	# ---- Nature & objects: scatter mixed bushes/rocks, single POIs
	editor.select_tab("nature")
	var np = editor.tab_panel("nature")
	np.selected = ["bush", "plant", "rocks", "boulder"]
	np._on_tool(0)
	np.density = 18
	np.bsize = 11
	v.scripted_stroke([Vector2i(44, 30), Vector2i(50, 34), Vector2i(56, 36)])
	np._on_tool(1)
	for pair in [["factory_block", Vector2i(36, 30)], ["town_house", Vector2i(46, 40)], ["ruins", Vector2i(52, 26)], ["hangar", Vector2i(30, 36)]]:
		np.selected = [pair[0]]
		v.scripted_stroke([pair[1]])
	np.selected = ["tree"]
	np._on_tool(0)
	np.density = 60
	v.scripted_stroke([Vector2i(56, 44), Vector2i(60, 48)])
	_view(Vector2(44, 36), 0.75)
	await _shot("04_nature_tab.png")
	# ---- Resources: single + scatter
	editor.select_tab("resources")
	var rp = editor.tab_panel("resources")
	rp.res = "ore"
	rp.amount = 2500
	rp._on_tool(0)
	for c in [Vector2i(26, 18), Vector2i(28, 17), Vector2i(30, 18)]:
		v.scripted_stroke([c])
	rp.res = "salvage"
	rp._on_tool(1)
	rp.density = 12
	rp.bsize = 9
	v.scripted_stroke([Vector2i(18, 30), Vector2i(22, 34)])
	_view(Vector2(26, 26), 0.8)
	await _shot("05_resources_tab.png")
	# ---- overlays + validate + undo/redo
	v.layers_on["grid"] = true
	v.layers_on["pass"] = "vehicle"
	v.overlay.queue_redraw()
	var issues: Array = editor.action_validate()
	print("EDITOR_DEMO validate issues=%d undo_depth=%d decor=%d resources=%d bridges=%d" % [issues.size(),
		editor.doc.undo_depth(), editor.doc.map.decor.size(), editor.doc.map.resources.size(), editor.doc.map.bridges.size()])
	print("EDITOR_DEMO issue codes=%s" % str(issues.map(func(i): return String(i.get("code", "")))))
	_view(Vector2(40, 60), 0.45)
	await _shot("06_overlay_validate.png")
	var err: String = editor.save_to("user://maps/ed1_demo.rtsmap")
	print("EDITOR_DEMO save err='%s'" % err)
	_roundtrip("user://maps/ed1_demo.rtsmap")
	v.layers_on["grid"] = false
	v.layers_on["pass"] = ""
	# ---- ED2 tabs (layout check): units, players, victory & triggers, regions
	_view(Vector2(40, 60), 0.8)
	var shot_i := 8
	for t in ["units", "players", "victory", "regions"]:
		if editor.tab_panel(t) == null:
			continue
		editor.select_tab(t)
		await _wait(4)
		var tb: Control = editor._p.tool_box
		print("EDITOR_DEMO tab %s left_edge=%.0f tool_box_min_w=%.0f" % [t, tb.get_global_rect().end.x, tb.get_combined_minimum_size().x])
		await _shot("%02d_%s_tab.png" % [shot_i, t])
		shot_i += 1
	# ---- 256x256 fps sample while panning
	editor.select_tab("map")
	mp.new_size = 256
	mp.create_new()
	editor.doc.symmetry = "four_way"
	editor._p.sync_symmetry()
	editor.select_tab("terrain")
	tp.code = Brushes.FOREST
	tp.bsize = 15
	tp.strength = 40
	tp.mode = "brush"
	for k in 12:
		v.scripted_stroke([Vector2i(10 + k * 9, 20), Vector2i(14 + k * 9, 60)])
	tp.strength = 100
	_view(Vector2(128, 128), 0.3)
	await _wait(30)
	# per-frame wall time while panning (Engine.get_frames_per_second() averages the last second,
	# which still contains the stroke work above; vsync caps the result at the display rate)
	var samples: Array = []
	var t_last := Time.get_ticks_usec()
	for i in 240:
		v.camera.pan_screen(Vector2(6, 3) * (1.0 if (i / 60) % 2 == 0 else -1.0))   # stay over the map
		await get_tree().process_frame
		var t_now := Time.get_ticks_usec()
		samples.append(1000000.0 / maxf(1.0, float(t_now - t_last)))
		t_last = t_now
	samples.sort()
	var n := samples.size()
	print("EDITOR_FPS_256 min=%.0f p5=%.0f median=%.0f max=%.0f frames=%d" % [samples[0], samples[n / 20],
		samples[n / 2], samples[n - 1], n])
	await _shot("07_map256.png")
	get_tree().quit()


func _bridge_somewhere(wp) -> bool:
	var m: Dictionary = editor.doc.map
	for x in range(36, 56):
		for y0 in range(50, 66):
			for y1 in range(y0 + 2, y0 + 14):
				if Brushes.bridge_check(m, Vector2i(x, y0), Vector2i(x, y1)).ok:
					wp.tool_begin(Vector2i(x, y0))
					wp.tool_begin(Vector2i(x, y1))
					return (m.bridges as Array).size() > 0
	return false


## MapIO save -> read -> editor open round trip: the reopened document must equal what was saved.
func _roundtrip(path: String) -> void:
	var m0: Dictionary = editor.doc.map_for_save()
	var s0: Dictionary = editor.doc.scenario_for_save()
	var r: Dictionary = MapIO.read(path)
	if r.has("error"):
		print("EDITOR_DEMO roundtrip ok=false read error=%s" % String(r.error))
		return
	var m1: Dictionary = r.map
	var s1: Dictionary = r.get("scenario", {})
	var bad: Array = []
	if int(m1.w) != int(m0.w) or int(m1.h) != int(m0.h):
		bad.append("size")
	if PackedByteArray(m1.terrain) != PackedByteArray(m0.terrain):
		bad.append("terrain")
	for k in ["decor", "resources", "bridges"]:
		if (m1.get(k, []) as Array).size() != (m0.get(k, []) as Array).size():
			bad.append(k)
	for k in ["players", "entities", "regions", "triggers"]:
		if (s1.get(k, []) as Array).size() != (s0.get(k, []) as Array).size():
			bad.append(k)
	if String(s1.get("name", "")) != String(s0.get("name", "")):
		bad.append("name")
	var oerr: String = editor.open_path(path)
	if oerr != "" or PackedByteArray(editor.doc.map.terrain) != PackedByteArray(m0.terrain):
		bad.append("open_path")
	print("EDITOR_DEMO roundtrip ok=%s cells=%d decor=%d resources=%d bridges=%d players=%d mismatches=%s" % [
		bad.is_empty(), PackedByteArray(m1.terrain).size(), (m1.get("decor", []) as Array).size(),
		(m1.get("resources", []) as Array).size(), (m1.get("bridges", []) as Array).size(),
		(s1.get("players", []) as Array).size(), str(bad)])
