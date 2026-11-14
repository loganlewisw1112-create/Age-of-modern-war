extends SceneTree
## G7.1 PERFDRAW71-8: same-frame look proof of the per-snapshot record cache at LP peak. Runs the LP peak (perf71_draw_lp
## placement), then freezes the whole scene tree (sim, camera, anim time and every layer stop), redraws the entity layer
## through the full path only and saves a shot, redraws it through the records (build + replay) and saves a second shot,
## and prints the pixel diff (max channel / count over 1/255) plus the record counters.
##   godot --path . -s res://tools/perf71_draw_rcab.gd -- --peak=1000 --lpz=0.5 --ab-out=<abs path prefix> [--ab-at=900]
const LPH = preload("res://tools/perf71_draw_lp.gd")
var _main
var _f := 0
var _at := 900
var _peak := 1000
var _zoom := 0.5
var _out := ""
var _k := -1
var _el = null
var _a: Image


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--peak="):
			_peak = int(a.substr(7))
		elif a.begins_with("--lpz="):
			_zoom = float(a.substr(6))
		elif a.begins_with("--ab-out="):
			_out = a.substr(9)
		elif a.begins_with("--ab-at="):
			_at = int(a.substr(8))
	_main = load("res://presentation/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		print("RCAB start=", _main.start_match(SimWorld.LastProtocol.make_config(7, "last_protocol")))
	var mv = _main.match_view
	if mv == null or mv.get("_world") == null:
		return false
	if _f == 30:
		LPH.new()._spawn_peak(mv, _peak)
	if _f == 40:
		mv.camera.set_zoom_level(_zoom)
		var w = mv.world
		mv.center_camera_on(Vector2(w.factions[mv.player_fid].spawn) + Vector2(0.5, 0.5) + Vector2(-20.0, -20.0))
	if _f == _at:
		_el = mv.entity_layer
		paused = true   # everything with the default process mode stops; rendering goes on
		_k = 0
	if _k < 0:
		return false
	_k += 1
	if _k == 2:
		_el.rc_on = false
		_el.refresh()
	elif _k == 5:
		_a = root.get_viewport().get_texture().get_image()
		_el.rc_on = true
		_el.refresh()   # builds the records for this snapshot
		_el.refresh()   # draws from them
		print("RCAB records: unit hits=%d built=%d fall=%d static hits=%d used=%s/%s drawn=%d units=%d" % [_el.rc_hits, _el.rc_built, _el.rc_fall, _el.rs_hits, str(_el.rc_used), str(_el.rs_used), _el.drawn, _el._units_drawn])
	elif _k == 8:
		var b: Image = root.get_viewport().get_texture().get_image()
		_a.save_png(_out + "_full.png")
		b.save_png(_out + "_cached.png")
		var mx := 0.0
		var nd := 0
		var dimg := Image.create(b.get_width(), b.get_height(), false, Image.FORMAT_RGB8)
		for y in b.get_height():
			for x in b.get_width():
				var p: Color = _a.get_pixel(x, y)
				var q: Color = b.get_pixel(x, y)
				var d := maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), absf(p.b - q.b))
				mx = maxf(mx, d)
				if d > 1.5 / 255.0:
					nd += 1
				dimg.set_pixel(x, y, Color(minf(d * 10.0, 1.0), minf(d * 10.0, 1.0), minf(d * 10.0, 1.0)))
		dimg.save_png(_out + "_diff_x10.png")
		print("RCAB pixel diff: max=%.4f (%d/255) pixels_over_1=%d of %d size=%dx%d" % [mx, roundi(mx * 255.0), nd, b.get_width() * b.get_height(), b.get_width(), b.get_height()])
		quit(0)
	return false
