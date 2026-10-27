extends RefCounted
## G7 SCALE7 playtest: start a match on lp_test512 (512x512), pan to the four corners and the centre, zoom fully
## out and fully in, screenshot each, check the minimap samples the big map (stride 2, 256 texels) and that
## terrain chunks stream in wherever the camera goes. Frame times are logged per stop (windowed; not a gate).

const CORNERS := [["nw", Vector2(14, 14)], ["ne", Vector2(497, 14)], ["sw", Vector2(14, 497)], ["se", Vector2(497, 497)],
	["centre", Vector2(256, 256)]]


func _minimap(root: Node):
	for n in root.find_children("*", "Control", true, false):
		var s = n.get_script()
		if s != null and String(s.resource_path).ends_with("hud/minimap.gd"):
			return n
	return null


## Worst frame time (ms) over `frames` frames.
func _worst(pt, frames: int) -> float:
	var worst := 0.0
	var t := Time.get_ticks_usec()
	for i in frames:
		await pt.get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - t) / 1000.0)
		t = now
	return worst


func run(pt) -> void:
	var cfg := SimWorld.default_config()
	cfg.map = "lp_test512"
	cfg.dev_map = true  # G7: lp_test maps are skirmish:false (owner); dev_map lets this dev/test path start them
	cfg.sides[1].ai = false
	var t0 := Time.get_ticks_msec()
	var started: bool = pt.main.start_match(cfg)
	pt._log("scale7_match_started", started, "start_match took %d ms" % (Time.get_ticks_msec() - t0))
	if not started:
		return
	await pt._wait(2.0)
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	pt._log("scale7_map_512", int(w.map.w) == 512 and int(w.map.h) == 512 and String(w.map.get("id", "")) == "lp_test512",
		"map=%s %dx%d" % [String(w.map.get("id", "?")), int(w.map.w), int(w.map.h)])
	# shots need the ground: mark the whole map explored for the player (grey fog shows the terrain; flows may
	# write the sim, display code may not), and put a small group at every stop so units are drawn there too
	mv.join_sim()
	var ex: PackedByteArray = w.fog[0].explored
	ex.fill(1)
	w.fog[0].explored = ex
	for c in CORNERS:
		for k in 8:
			var cell := Vector2i(c[1]) + Vector2i(k % 4, k / 4)
			w.spawn_unit("mbt" if k == 0 else "rifleman", 0, Vector2(cell) + Vector2(0.5, 0.5))
	await pt._wait(0.5)
	var tl = mv.get("terrain_layer")
	pt._log("scale7_terrain_lazy", tl != null and bool(tl.get("lazy")), "bake_ms=%s" % str(tl.get("bake_ms") if tl != null else "-"))
	var cam = mv.get("camera")
	pt._log("scale7_zoom_floor", cam != null and float(cam.zoom_min) < 0.1, "zoom_min=%.3f" % float(cam.zoom_min if cam != null else 0.0))
	var mm = _minimap(pt.main)
	pt._log("scale7_minimap_stride", mm != null and int(mm.get("_k")) == 2 and int(mm.get("_tw")) == 256,
		"k=%s tex=%sx%s" % [str(mm.get("_k") if mm != null else "-"), str(mm.get("_tw") if mm != null else "-"), str(mm.get("_th") if mm != null else "-")])
	cam.set_zoom_level(1.0)
	for c in CORNERS:
		mv.center_camera_on(c[1])
		var hitch: float = await _worst(pt, 40)
		await pt._wait(0.8)
		var chunks := 0
		var near := 0
		var key := Vector2i(int(c[1].x) / 16 * 16, int(c[1].y) / 16 * 16)
		if tl != null:
			var ch: Dictionary = tl.get("_chunks")
			chunks = ch.size()
			for k in ch:
				if absi(k.x - key.x) <= 32 and absi(k.y - key.y) <= 32:
					near += 1
		pt._log("scale7_pan_%s" % c[0], near > 0, "chunks=%d near=%d worst frame after pan=%.1f ms fps=%d" % [chunks, near, hitch, Engine.get_frames_per_second()])
		await pt._shot("scale7_%s" % c[0])
	mv.center_camera_on(Vector2(256, 256))
	cam.set_zoom_level(0.001)
	var out_worst: float = await _worst(pt, 60)
	pt._log("scale7_zoom_out", absf(float(cam.zoom.x) - float(cam.zoom_min)) < 0.001, "zoom=%.3f worst frame=%.1f ms fps=%d" % [float(cam.zoom.x), out_worst, Engine.get_frames_per_second()])
	await pt._shot("scale7_zoom_out")
	cam.set_zoom_level(99.0)
	var in_worst: float = await _worst(pt, 60)
	pt._log("scale7_zoom_in", absf(float(cam.zoom.x) - 2.5) < 0.001, "zoom=%.2f worst frame=%.1f ms" % [float(cam.zoom.x), in_worst])
	await pt._shot("scale7_zoom_in")
	cam.set_zoom_level(1.0)
	await pt._wait(0.5)
	if mm != null:
		var img: Image = pt.get_viewport().get_texture().get_image()
		var r := Rect2i(Vector2i(mm.get_global_rect().position), Vector2i(mm.get_global_rect().size))
		r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		var ok := r.size.x > 0 and r.size.y > 0
		if ok:
			var crop := img.get_region(r)
			var dir: String = pt.get("shot_dir") if pt.get("shot_dir") != null else ""
			if dir != "":
				crop.save_png(dir.path_join("scale7_minimap.png"))
		pt._log("scale7_minimap_shot", ok, "rect=%s" % str(r))
	await pt._shot("scale7_minimap_full")
