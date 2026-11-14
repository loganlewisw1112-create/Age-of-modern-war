extends SceneTree
## G7.1 PERFDRAW71 (CR 467): in-game old/new A/B of the minimap incoming markers in ONE run, same data.
## Starts the normal game (main.tscn reads --autostart / --map / --spawn-test / --zoom itself). Once the minimap shows
## threat markers, freezes the minimap (its data no longer changes), fixes the pulse, shows the old per-frame path,
## then the batched layers, saves both full screenshots + an x3 minimap crop side by side (old | new | |diff| x10),
## and prints the minimap pixel diff and the frame's total draw calls in each mode.
##   godot --path . -s res://tools/perf71_draw_incab.gd -- --autostart --map=valley_conquest_l --spawn-test=10000
##         --zoom=0.15 --ab-out=<abs path prefix> [--ab-pulse=0.6] [--ab-wait=240]
const MM = preload("res://presentation/hud/minimap.gd")
var _main
var _f := 0
var _mm = null
var _found := -1
var _at := -1
var _out := ""
var _pulse := 0.6
var _wait := 240
var _old: Image
var _dc_old := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ab-out="):
			_out = a.substr(9)
		elif a.begins_with("--ab-pulse="):
			_pulse = float(a.substr(11))
		elif a.begins_with("--ab-wait="):
			_wait = int(a.substr(10))
	_main = load("res://presentation/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_f += 1
	if _f > 20000:
		print("INCAB timeout")
		quit(1)
	if _mm == null:
		if _f % 30 == 0:
			for n in root.find_children("*", "Control", true, false):
				if n.get_script() == MM:
					_mm = n
					_found = _f
					break
		return false
	if _at < 0:
		if _f - _found >= _wait and not _mm._threats.is_empty():
			_at = _f
			_mm.set_process(false)   # frozen: the same threats / waves / camera box for both captures
			_mm.inc_pulse_fixed = _pulse
			_mm.inc_set_old(true)
		return false
	var k := _f - _at
	if k == 6:
		_dc_old = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		_old = root.get_viewport().get_texture().get_image()
		_mm.inc_set_old(false)
	elif k == 12:
		var dc_new := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var img := root.get_viewport().get_texture().get_image()
		_old.save_png(_out + "_old.png")
		img.save_png(_out + "_new.png")
		var s: Vector2 = Vector2(img.get_size()) / root.get_visible_rect().size
		var gr: Rect2 = _mm.get_global_rect()
		var r := Rect2i(Vector2i(gr.position * s), Vector2i(gr.size * s))
		var a := _old.get_region(r)
		var b := img.get_region(r)
		a.convert(Image.FORMAT_RGBA8)
		b.convert(Image.FORMAT_RGBA8)
		var d := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
		var mx := 0
		var n1 := 0
		for y in r.size.y:
			for x in r.size.x:
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				var m := int(round(255.0 * maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))))
				mx = maxi(mx, m)
				if m > 1:
					n1 += 1
				var v := minf(1.0, float(m) * 10.0 / 255.0)
				d.set_pixel(x, y, Color(v, v, v))
		var side := Image.create(r.size.x * 3 + 8, r.size.y, false, Image.FORMAT_RGBA8)
		side.fill(Color(1, 1, 1))
		side.blit_rect(a, Rect2i(Vector2i.ZERO, r.size), Vector2i(0, 0))
		side.blit_rect(b, Rect2i(Vector2i.ZERO, r.size), Vector2i(r.size.x + 4, 0))
		side.blit_rect(d, Rect2i(Vector2i.ZERO, r.size), Vector2i(r.size.x * 2 + 8, 0))
		side.resize(side.get_width() * 3, side.get_height() * 3, Image.INTERPOLATE_NEAREST)
		side.save_png(_out + "_minimap_side.png")
		print("INCAB threats=%d waves=%d layers=%d pulse=%.2f minimap_rect=%s max_diff=%d px_gt1=%d draw_calls_old=%d draw_calls_new=%d" % [
			_mm._threats.size(), _mm._waves.size(), _mm.inc_layers_used, _pulse, str(r), mx, n1, _dc_old, dc_new])
		quit(0)
	return false
