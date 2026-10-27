extends SceneTree
## Per-system sim cost, 2k fight 600t native river_crossing_s (same script in G7 and G6.1 trees). Replicates SimWorld.step.
const Bench = preload("res://tools/scale_bench.gd")
func _init() -> void:
	var st = Bench.build("river_crossing_s", 2000, ["human_a", "human_b"], "fight")
	var w = st.w
	var acc := {}
	var total := 0
	for i in 600:
		Bench.pre_tick(st, i)
		var t0 := Time.get_ticks_usec()
		if w.match_state.ended:
			break
		w.tick += 1
		w.events = []
		var a := Time.get_ticks_usec()
		w._apply_due_commands()
		acc["_cmds"] = acc.get("_cmds", 0) + Time.get_ticks_usec() - a
		for sys in w.SYSTEM_ORDER:
			a = Time.get_ticks_usec()
			sys.tick(w)
			var k: String = String(sys.resource_path).get_file()
			acc[k] = acc.get(k, 0) + Time.get_ticks_usec() - a
		a = Time.get_ticks_usec()
		w.Ops.prune(w)
		for fid in w.ai_state:
			if w.factions[fid].alive:
				w.AiController.think(w, fid)
		var g6: Array = w.factions.keys(); g6.sort()
		for fid in g6:
			if w.factions[fid].alive and not w.ai_state.has(fid):
				w.Commanders.think_player(w, fid)
		for ev in w.events:
			w.event_log.append(ev)
		if w.event_log.size() > w.EVENT_LOG_MAX:
			w.event_log = w.event_log.slice(w.event_log.size() - w.EVENT_LOG_MAX)
		acc["_ai+post"] = acc.get("_ai+post", 0) + Time.get_ticks_usec() - a
		if w.snap_enabled:
			a = Time.get_ticks_usec()
			w.HotState.flush(w); w.RenderSnap.build(w)
			acc["_snap"] = acc.get("_snap", 0) + Time.get_ticks_usec() - a
		total += Time.get_ticks_usec() - t0
	var ks := acc.keys()
	ks.sort_custom(func(x, y): return acc[x] > acc[y])
	print("PROF7 total_ms_per_tick=%.2f hash=%s" % [total / 600000.0, String(w.state_hash()).left(16)])
	for k in ks:
		if acc[k] > 6000:
			print("PROF7 %-28s %.3f" % [k, acc[k] / 600000.0])
	quit(0)
