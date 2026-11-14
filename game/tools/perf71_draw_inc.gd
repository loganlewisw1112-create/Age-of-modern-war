extends SceneTree
## G7.1 PERFDRAW71 (CR 467): look proof for the batched minimap incoming markers.
## Draws the same synthetic markers with the old per-frame path (_draw_incoming) and the new batched layers, at fixed
## pulse values, in a 206 px SubViewport (the HUD's minimap size) over a terrain-like background, then prints pixel diffs
## and saves x4 crops side by side (old | new | |diff| x10).
## Markers: 22 threat clusters in adjacent 10 px bins (rings and arrows overlap), 1 cluster whose arrow the old code
## shows only for pulse < 0.5 (ring grows to within 8 px of the base), 1 cluster with no arrow (next to the base),
## a survival spawn countdown and 2 live waves (dashed arrows).
##   godot --path . -s res://tools/perf71_draw_inc.gd -- --out=<abs dir>
const MM = preload("res://presentation/hud/minimap.gd")
const PULSES := [0.0, 0.37, 0.62, 1.0]
var _out := ""
var _sv: SubViewport
var _mm


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	if _out == "":
		_out = OS.get_user_data_dir() + "/perf71_draw_inc"
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


func _bg() -> ImageTexture:
	var img := Image.create(206, 206, false, Image.FORMAT_RGBA8)
	var cols := [Color("5d7d3d"), Color("8b7452"), Color("2f5232"), Color("2c5f8c"), Color("73736f"), Color("6f8a48")]
	for y in 206:
		for x in 206:
			var c: Color = cols[(int(x / 13) * 7 + int(y / 11) * 3 + int((x + y) / 29)) % cols.size()]
			img.set_pixel(x, y, c.darkened(0.25 * float((x * 31 + y * 17) % 5) / 4.0))
	return ImageTexture.create_from_image(img)


func _run() -> void:
	_sv = SubViewport.new()
	_sv.size = Vector2i(206, 206)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_sv)
	_mm = MM.new()
	_mm.SIZE = 206
	_mm.set_process(false)
	_sv.add_child(_mm)
	var bg := TextureRect.new()
	bg.texture = _bg()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mm.add_child(bg)
	_mm._inc_ensure()
	var ov := Control.new()
	ov.size = Vector2(206, 206)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.draw.connect(_mm._draw_camera)
	_mm.add_child(ov)
	_mm._cam_overlay = ov
	# synthetic markers
	var th: Array = []
	for i in 22:
		th.append({"p": Vector2(25 + (i % 6) * 10, 25 + int(i / 6) * 10), "n": 6 + i * i * 2})
	th.append({"p": Vector2(145, 145), "n": 6})     # dist 13.46 to the base: arrow only while pulse < 0.5
	th.append({"p": Vector2(155, 155), "n": 10})    # next to the base: never an arrow
	var wv: Array = [
		{"kind": "spawn", "p": Vector2(30, 180), "eta": 95, "n": 0},
		{"kind": "live", "p": Vector2(100, 120), "to": Vector2(150, 157), "n": 40, "eta": 0},
		{"kind": "live", "p": Vector2(60, 150), "to": Vector2(150, 157), "n": 9, "eta": 0},
	]
	_mm._base_mini = Vector2(150, 157.5)
	for i in 4:
		await process_frame
	var base_img: Image = await _cap()   # no markers
	_mm._threats = th
	_mm._waves = wv
	var imgs := {}
	for old in [true, false]:
		for p in PULSES:
			_mm.inc_pulse_fixed = p
			_mm.inc_set_old(old)
			for i in 3:
				await process_frame
			imgs["%s_%.2f" % ["old" if old else "new", p]] = await _cap()
			if not old:
				print("INCBUILD p=%.2f layers=%d rebuild_us=%d" % [p, _mm.inc_layers_used, _mm.inc_rebuild_us])
	# rebuild cost without the cache warm-up (fresh key each time)
	var us: Array = []
	for i in 20:
		_mm._inc_key = []
		_mm._rebuild_incoming()
		us.append(_mm.inc_rebuild_us)
	us.sort()
	print("INCBUILD warm median_us=%d max_us=%d (24 clusters + 3 waves)" % [us[10], us[19]])
	var worst := 0
	for p in PULSES:
		var a: Image = imgs["old_%.2f" % p]
		var b: Image = imgs["new_%.2f" % p]
		var st := _diff(a, b, base_img)
		worst = maxi(worst, int(st["max"]))
		print("INCDIFF p=%.2f max=%d px_gt1=%d px_gt4=%d px_gt16=%d marker_px=%d" % [p, st["max"], st["n1"], st["n4"], st["n16"], st["marker"]])
		_side(a, b, st["img"]).save_png(_out + "/inc_side_p%03d.png" % int(round(p * 100.0)))
	print("INCDIFF worst_max=%d out=%s" % [worst, _out])
	quit(0)


func _cap() -> Image:
	await RenderingServer.frame_post_draw
	var img := _sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _diff(a: Image, b: Image, base: Image) -> Dictionary:
	var d := Image.create(206, 206, false, Image.FORMAT_RGBA8)
	var mx := 0
	var n1 := 0
	var n4 := 0
	var n16 := 0
	var mk := 0
	for y in 206:
		for x in 206:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var cz := base.get_pixel(x, y)
			var m := int(round(255.0 * maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))))
			if not ca.is_equal_approx(cz) or not cb.is_equal_approx(cz):
				mk += 1
			mx = maxi(mx, m)
			if m > 1:
				n1 += 1
			if m > 4:
				n4 += 1
			if m > 16:
				n16 += 1
			var v := minf(1.0, float(m) * 10.0 / 255.0)
			d.set_pixel(x, y, Color(v, v, v))
	return {"max": mx, "n1": n1, "n4": n4, "n16": n16, "marker": mk, "img": d}


func _side(a: Image, b: Image, d: Image) -> Image:
	var out := Image.create(206 * 3 + 8, 206, false, Image.FORMAT_RGBA8)
	out.fill(Color(1, 1, 1))
	out.blit_rect(a, Rect2i(0, 0, 206, 206), Vector2i(0, 0))
	out.blit_rect(b, Rect2i(0, 0, 206, 206), Vector2i(210, 0))
	out.blit_rect(d, Rect2i(0, 0, 206, 206), Vector2i(420, 0))
	out.resize(out.get_width() * 4, out.get_height() * 4, Image.INTERPOLATE_NEAREST)
	return out
