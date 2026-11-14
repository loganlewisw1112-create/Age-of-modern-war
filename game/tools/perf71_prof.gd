extends SceneTree
## PERFSIM71 (copy of PERF7H perf7l_prof.gd): per-system sim cost of the 2k benchmark (river_crossing_s 2k fight, 600 ticks).
## no CN facility). Same script in the G7 tree and the G6.1 tree (C:/CODING/g7_regress2_wt/game/.plan/). Replicates
## SimWorld.step with a timer per system (bench only, never touches state).
## Run: "$G" --headless --path . -s .plan/perf7g_prof.gd -- [--ticks=600] [--sub] [--min=0.05] [--plain]
##        [--set=res://sim/systems/movement.gd:held_gate_cells=false ...] [--hashes=100]
##   --plain   time w.step() only (exactly sim_ab7) and print SIMAB avg_ms + hash
##   --sub     also print SimIndex / Movement sub-phase labels (profiled run: totals inflate a little)
##   --set     set a static var on a script before the run (A/B toggles); value true/false/int/float
##   --hashes=N print the state hash every N ticks (per-tick compare across toggles)
const Bench = preload("res://tools/scale_bench.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return d


func _val(s: String):
	if s == "true":
		return true
	if s == "false":
		return false
	if s.is_valid_int():
		return int(s)
	if s.is_valid_float():
		return float(s)
	return s


## Same steps as SimWorld._apply_due_commands (both trees), timed per command type (keys "cmd.<type>.<part>").
func _cmds_timed(w, acc: Dictionary) -> void:
	if w.pending.is_empty():
		return
	var due := []
	var later := []
	for c in w.pending:
		if int(c.tick) <= w.tick:
			due.append(c)
		else:
			later.append(c)
	w.pending = later
	due.sort_custom(func(a, b): return int(a.id) < int(b.id))
	for c in due:
		var ty := String(c.type)
		var a := Time.get_ticks_usec()
		var reason: String = w._common_validate(c)
		if reason == "":
			reason = w.COMMANDS[c.type].validate_command(w, c)
		acc["cmd.%s.validate" % ty] = acc.get("cmd.%s.validate" % ty, 0) + Time.get_ticks_usec() - a
		acc["cmd.%s.n" % ty] = acc.get("cmd.%s.n" % ty, 0) + 1000 * 600   # count (prints as n per 600 ticks)
		if reason != "":
			w.emit("CommandRejected", {"command_id": c.id, "type": c.type, "issuer": c.issuer, "reason": reason})
			continue
		a = Time.get_ticks_usec()
		w.COMMANDS[c.type].apply_command(w, c)
		acc["cmd.%s.apply" % ty] = acc.get("cmd.%s.apply" % ty, 0) + Time.get_ticks_usec() - a
		a = Time.get_ticks_usec()
		w.AiCommand.on_applied(w, c)
		if w.DIRECT_ORDERS.has(ty):
			w.Ops.on_direct_order(w, c)
			w.SquadAI.on_direct_order(w, c)
		elif ty == "set_formation":
			w.SquadAI.on_direct_order(w, c)
		acc["cmd.%s.hooks" % ty] = acc.get("cmd.%s.hooks" % ty, 0) + Time.get_ticks_usec() - a
		w.emit("CommandApplied", {"command_id": c.id, "type": c.type, "cmd_type": String(c.type), "issuer": c.issuer})


func _init() -> void:
	var ticks := int(_arg("ticks", "600"))
	var minms := float(_arg("min", "0.05"))
	var every := int(_arg("hashes", "0"))
	var args := OS.get_cmdline_user_args()
	var sub := args.has("--sub")
	var plain := args.has("--plain")
	for a in args:
		if a.begins_with("--set="):
			var spec: String = a.substr(6)
			var colon := spec.rfind(":")
			var path := spec.left(colon)
			var kv := spec.substr(colon + 1).split("=")
			var scr: Script = load(path)
			scr.set(kv[0], _val(kv[1]))
			print("PERF7G set %s %s=%s -> %s" % [path.get_file(), kv[0], kv[1], str(scr.get(kv[0]))])
	var st = Bench.build("river_crossing_s", 2000, ["human_a", "human_b"], "fight")
	var w = st.w
	var cpu := ""
	SimIndex.prof = {}
	SimIndex.profiling = sub
	var Mv = load("res://sim/systems/movement.gd")
	Mv.profile = sub
	Mv.prof = {}
	var acc := {}
	var total := 0
	for i in ticks:
		Bench.pre_tick(st, i)
		if plain:
			var a0 := Time.get_ticks_usec()
			w.step()
			total += Time.get_ticks_usec() - a0
		else:
			var t0 := Time.get_ticks_usec()
			if w.match_state.ended:
				break
			w.tick += 1
			w.events = []
			var a := Time.get_ticks_usec()
			if args.has("--cmds"):
				_cmds_timed(w, acc)
			else:
				w._apply_due_commands()
			acc["_cmds"] = acc.get("_cmds", 0) + Time.get_ticks_usec() - a
			for sys in w.SYSTEM_ORDER:
				a = Time.get_ticks_usec()
				sys.tick(w)
				var k: String = String(sys.resource_path).get_file()
				acc[k] = acc.get(k, 0) + Time.get_ticks_usec() - a
			a = Time.get_ticks_usec()
			w.Ops.prune(w)
			acc["_ops_prune"] = acc.get("_ops_prune", 0) + Time.get_ticks_usec() - a
			a = Time.get_ticks_usec()
			for fid in w.ai_state:
				if w.factions[fid].alive:
					w.AiController.think(w, fid)
			acc["_ai"] = acc.get("_ai", 0) + Time.get_ticks_usec() - a
			a = Time.get_ticks_usec()
			var g6: Array = w.factions.keys(); g6.sort()
			for fid in g6:
				if w.factions[fid].alive and not w.ai_state.has(fid):
					w.Commanders.think_player(w, fid)
			acc["_commanders"] = acc.get("_commanders", 0) + Time.get_ticks_usec() - a
			for ev in w.events:
				w.event_log.append(ev)
			if w.event_log.size() > w.EVENT_LOG_MAX:
				w.event_log = w.event_log.slice(w.event_log.size() - w.EVENT_LOG_MAX)
			if w.snap_enabled:
				a = Time.get_ticks_usec()
				w.HotState.flush(w); w.RenderSnap.build(w)
				acc["_snap"] = acc.get("_snap", 0) + Time.get_ticks_usec() - a
			total += Time.get_ticks_usec() - t0
		if every > 0 and (i + 1) % every == 0:
			print("PERF7G_HASH tick=%d %s" % [w.tick, String(w.state_hash()).left(16)])
	SimIndex.profiling = false
	Mv.profile = false
	var nu := 0
	for id in w.entities:
		if w.entities[id].kind == "unit":
			nu += 1
	print("SIMAB avg_ms=%.2f" % (total / 1000.0 / ticks))
	print("PERF7G total_ms_per_tick=%.2f hash=%s units=%d tick=%d plain=%s" % [total / 1000.0 / ticks, String(w.state_hash()).left(16), nu, w.tick, str(plain)])
	var _cb = load("res://sim/systems/combat.gd")
	print("PERF7L_AB scans=%s diff=%s" % [str(_cb.get("scan_ab_n")), str(_cb.get("scan_ab_diff"))])
	if ResourceLoader.exists("res://sim/systems/senses7.gd"):
		var _s7 = load("res://sim/systems/senses7.gd")
		print("PERF7L_SPOT n=%s diff=%s" % [str(_s7.get("spot_ab_n")), str(_s7.get("spot_ab_diff"))])
	if plain:
		quit(0)
		return
	var ks := acc.keys()
	ks.sort_custom(func(x, y): return acc[x] > acc[y])
	for k in ks:
		if acc[k] / 1000.0 / ticks >= minms:
			print("PERF7G_SYS %-26s %.3f" % [k, acc[k] / 1000.0 / ticks])
	if sub:
		var mp: Dictionary = Mv.prof
		var mk: Array = mp.keys()
		mk.sort_custom(func(x, y): return mp[x] > mp[y])
		for k in mk:
			if mp[k] / 1000.0 / ticks >= minms:
				print("PERF7G_MV %-26s %.3f" % [k, mp[k] / 1000.0 / ticks])
		var ps: Array = SimIndex.prof.keys()
		ps.sort_custom(func(x, y): return SimIndex.prof[x][0] > SimIndex.prof[y][0])
		for k in ps:
			if SimIndex.prof[k][0] / 1000.0 / ticks >= minms:
				print("PERF7G_SUB %-26s %.3f calls=%d" % [k, SimIndex.prof[k][0] / 1000.0 / ticks, SimIndex.prof[k][1]])
	if ResourceLoader.exists("res://sim/systems/senses7.gd"):
		var S7 = load("res://sim/systems/senses7.gd")
		for k in S7.prof:
			print("PERF7H_S7 %-10s %.3f" % [k, float(S7.prof[k]) / 1000.0 / ticks])
	quit(0)
