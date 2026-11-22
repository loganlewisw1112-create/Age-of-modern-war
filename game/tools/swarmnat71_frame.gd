extends "res://tools/perf71_draw_lp.gd"
## G7.1 SWARMNAT71: where the LP-peak frame goes (diagnostic only; same scene/placement as perf71_draw_lp.gd).
##   godot --path . -s res://tools/swarmnat71_frame.gd -- --fps-log --fps-quit=45 --no-vsync --lpz=0.5 --peak=1000 --prof
## Per frame it timestamps the start of the process step (this MainLoop's _process runs first in SceneTree.process),
## RenderingServer.frame_pre_draw and frame_post_draw, and samples Godot's own timers (TIME_PROCESS, TIME_PHYSICS_PROCESS,
## the root viewport's measured render time CPU / GPU, frame setup CPU). Windows (seconds after the camera is placed):
##   A  8-16  normal                 B 16-20 entity layer hidden (its _draw + canvas cost gone; refresh still runs)
##   C 20-24  normal again (drift)   D 24-28 sim paused (no sim worker)   E 28-32 sim paused + entity layer hidden
##   F 32-36  sim paused, entity layer shown again (paused drift check)
##   G 36-40  sim paused, every CanvasItem child of MatchView hidden (world layers + overlays: HUD / engine floor)
## NATWIN lines: one per window, ms per frame averages.
var _t0 := -1
var _tp := 0          # usec at the start of this frame's process step
var _tpre := 0
var _tpost := 0
var _win := ""
var _acc := {}
var _rid: RID
var _el = null
var _orig_refresh = null


func _initialize() -> void:
	super()
	RenderingServer.frame_pre_draw.connect(func(): _tpre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): _tpost = Time.get_ticks_usec())


func _process(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _tp > 0 and _win != "" and _tpre > _tp and _tpost > _tpre:
		var a: Dictionary = _acc.get(_win, {"n": 0, "frame": 0.0, "proc": 0.0, "render": 0.0, "rest": 0.0, "tproc": 0.0,
			"tphys": 0.0, "rcpu": 0.0, "rgpu": 0.0, "setup": 0.0, "dc": 0.0, "drawn": 0.0, "items": 0.0})
		a.n += 1
		a.frame += (now - _tp) / 1000.0
		a.proc += (_tpre - _tp) / 1000.0
		a.render += (_tpost - _tpre) / 1000.0
		a.rest += (now - _tpost) / 1000.0
		a.tproc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		a.tphys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		a.rcpu += RenderingServer.viewport_get_measured_render_time_cpu(_rid)
		a.rgpu += RenderingServer.viewport_get_measured_render_time_gpu(_rid)
		a.setup += RenderingServer.get_frame_setup_time_cpu()
		a.dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		if _el != null:
			a.drawn += float(_el.drawn)
			a.items += float(_el.get("_n_items") if _el.get("_n_items") != null else 0)
		_acc[_win] = a
	_tp = Time.get_ticks_usec()
	var r: bool = super(delta)
	var mv = _main.match_view if _main != null else null
	if mv == null or mv.get("_world") == null:
		return r
	if _f == 41:
		_t0 = Time.get_ticks_msec()
		_rid = root.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_rid, true)
		_el = mv.entity_layer
	if _t0 < 0:
		return r
	var s := (Time.get_ticks_msec() - _t0) / 1000.0
	var w := ""
	if s >= 8.0 and s < 16.0:
		w = "A_normal"
	elif s >= 16.0 and s < 20.0:
		w = "B_ent_hidden"
	elif s >= 20.0 and s < 24.0:
		w = "C_normal"
	elif s >= 24.0 and s < 28.0:
		w = "D_sim_paused"
	elif s >= 28.0 and s < 32.0:
		w = "E_paused_ent_hidden"
	elif s >= 32.0 and s < 36.0:
		w = "F_paused_normal"
	elif s >= 36.0 and s < 40.0:
		w = "G_paused_world_hidden"
	elif s >= 40.0 and s < 44.0:
		w = "H_paused_nothing_ours"
	if w != _win:
		if _win != "":
			_print_win(_win)
		_win = w
		match w:
			"B_ent_hidden":
				_el.visible = false
			"C_normal":
				_el.visible = true
			"D_sim_paused":
				mv.paused = true
			"E_paused_ent_hidden":
				_el.visible = false
			"F_paused_normal":
				_el.visible = true
			"G_paused_world_hidden":
				var hid := []
				for c in mv.get_children():
					if c is CanvasItem and (c as CanvasItem).visible:
						(c as CanvasItem).visible = false
						hid.append(String(c.name))
				print("NATWIN G hid ", ",".join(hid))
			"H_paused_nothing_ours":   # SWARMNAT71-3 GPU / engine floor probe: also every CanvasLayer (HUD) and MatchView
				var hid2 := []
				for n in root.find_children("*", "CanvasLayer", true, false):
					if (n as CanvasLayer).visible:
						(n as CanvasLayer).visible = false
						hid2.append(String(n.name))
				for n in root.find_children("*", "CanvasItem", true, false):
					if (n as CanvasItem).visible and (n as CanvasItem).get_parent() == root:
						(n as CanvasItem).visible = false
						hid2.append(String(n.name))
				print("NATWIN H hid ", ",".join(hid2))
	if s >= 44.5:
		print("NATWIN end")
		return true
	return r


func _print_win(w: String) -> void:
	var a: Dictionary = _acc.get(w, {})
	if a.is_empty() or int(a.n) == 0:
		print("NATWIN %s n=0" % w)
		return
	var n := float(a.n)
	print("NATWIN %s n=%d fps=%.1f frame=%.2f proc=%.2f render=%.2f rest=%.2f | godot TIME_PROCESS=%.2f TIME_PHYSICS=%.2f vp_render_cpu=%.2f vp_render_gpu=%.2f frame_setup_cpu=%.2f draw_calls=%.0f drawn=%.0f" % [
		w, a.n, 1000.0 * n / maxf(0.001, a.frame), a.frame / n, a.proc / n, a.render / n, a.rest / n, a.tproc / n, a.tphys / n,
		a.rcpu / n, a.rgpu / n, a.setup / n, a.dc / n, a.drawn / n])
