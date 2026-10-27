extends SceneTree
## G7 LPMODE7 soak hook for INTEG7: a headless Last Protocol run (you vs the Machine on "hard") on the last_protocol map
## (lp_test512 when that map is not registered). Side 0 is run by the Last Protocol defence AI Commander (plus the
## normal skirmish AI with --side0-ai); the Machine runs its own AI, escalation phases, Weavers and THE TIDE.
##
## Usage: "$G" --headless --path . -s res://tools/lp_soak7.gd -- [--seed=77] [--map=last_protocol] [--max-s=6000]
##        [--tide-at=<sim s>] [--side0-ai] [--report-every=300] [--wall-max=<s>]
##   --tide-at  forces the countdown to its final stage at that sim time (the rules then start THE TIDE); without it the
##              run plays out by the real countdown / creep rules.
## Prints "LP SOAK t=..." progress lines and one final line:
##   LP SOAK RESULT seed=.. map=.. time_s=.. ticks=.. phase=.. tide=.. tide_at_s=.. ending=.. creep=.. creep_peak=..
##   cd_left_s=.. cores_alive=a/t rings_fallen=.. wall_s=.. ms_per_tick=.. lp_us_per_tick=.. creep_us_per_tick=..
## The tick loop mirrors SimWorld.step() exactly (same order, same calls) and only adds timers around LastProtocol and
## Creep. Grep the log for "SCRIPT ERROR" (must be 0) before trusting the line.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const MapGen = preload("res://sim/map_gen.gd")


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a == "--" + name:
			return "1"
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return def


## SimWorld.step() with timers around LastProtocol and Creep (us accumulated into acc).
func _step(w: SimWorld, acc: Dictionary) -> void:
	if w.match_state.ended:
		w.events = []
		return
	w.tick += 1
	w.events = []
	w._apply_due_commands()
	var live := bool(w.cfg.get("live_mode", false))
	for sys in SimWorld.SYSTEM_ORDER:
		if live and SimWorld.LIVE_SKIPS.has(sys):
			if sys == SimWorld.Progression:
				SimWorld.Progression.Status.ew_tick(w)
			continue
		if sys == LastProtocol or sys == Creep:
			var t0 := Time.get_ticks_usec()
			sys.tick(w)
			var dt := Time.get_ticks_usec() - t0
			acc["lp" if sys == LastProtocol else "creep"] += dt
			if sys == LastProtocol and w.tick > 50:
				acc.lp_steady += dt
		else:
			sys.tick(w)
	SimWorld.Ops.prune(w)
	for fid in w.ai_state:
		if w.factions[fid].alive:
			SimWorld.AiController.think(w, fid)
	var fids: Array = w.factions.keys()
	fids.sort()
	for fid in fids:
		if w.factions[fid].alive and not w.ai_state.has(fid):
			SimWorld.Commanders.think_player(w, fid)
	for ev in w.events:
		w.event_log.append(ev)
	if w.event_log.size() > SimWorld.EVENT_LOG_MAX:
		w.event_log = w.event_log.slice(w.event_log.size() - SimWorld.EVENT_LOG_MAX)


func _init() -> void:
	Content.load_all()
	var seed := int(_arg("seed", "77"))
	var map := _arg("map", "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512")
	var max_s := float(_arg("max-s", "6000"))
	var tide_at := float(_arg("tide-at", "-1"))
	var every_s := float(_arg("report-every", "300"))
	var wall_max := float(_arg("wall-max", "0"))
	var cfg := LastProtocol.make_config(seed, map)
	if _arg("side0-ai", "") != "":
		cfg.sides[0].ai = true
	var wt0 := Time.get_ticks_msec()
	var w := SimWorld.new_match(cfg)
	print("LP SOAK start seed=%d map=%s new_match_ms=%d side0_ai=%s" % [seed, map, Time.get_ticks_msec() - wt0, str(bool(cfg.sides[0].ai))])
	var acc := {"lp": 0, "creep": 0, "lp_steady": 0}
	# calibration overrides (this process only; printed in the result line)
	var lpr: Dictionary = LastProtocol.R()
	if _arg("cd-total", "") != "":
		lpr.countdown.total_s = float(_arg("cd-total", "0"))
	if _arg("critical", "") != "":
		lpr.creep.critical = float(_arg("critical", "0"))
	var max_ticks := int(max_s * SimWorld.TICK_RATE)
	var rep := maxi(int(every_s * SimWorld.TICK_RATE), 1)
	var forced := false
	var tide_tick := -1
	var win_t := Time.get_ticks_msec()
	var win_acc := 0
	var phase_max := 0
	var ending := "none"
	var losses := {}  # own unit losses by "zone/cause" (zone r0/r1/r2 = inside that ring's rect, out = outside)
	var m_lost := 0
	while w.tick < max_ticks and not w.match_state.ended:
		_step(w, acc)
		var s = w.sys_state.get("lp")
		if s == null:
			continue
		phase_max = maxi(phase_max, int(s.phase))
		for ev in w.events:
			if String(ev.type) == "EntityDestroyed" and String(ev.kind) == "unit":
				if int(ev.owner) == int(s.fid):
					var zone := "out"
					var cell := Vector2i(int(floor(ev.pos.x)), int(floor(ev.pos.y)))
					for i in (s.base.rings as Array).size():
						if (s.base.rings[i].rect as Rect2i).has_point(cell):
							zone = "r%d" % i
					var key := "%s/%s" % [zone, String(ev.cause)]
					losses[key] = int(losses.get(key, 0)) + 1
				elif int(ev.owner) == int(s.mfid):
					m_lost += 1
		if tide_tick < 0 and bool(s.tide):
			tide_tick = w.tick
		if tide_at >= 0.0 and not forced and float(w.tick) * SimWorld.DT >= tide_at:
			forced = true
			s.cd_left = minf(float(s.cd_left), float(LastProtocol.R().countdown.final_stage_frac) * float(s.cd_total) - 1.0)
			print("LP SOAK forced the countdown to its final stage at t=%.0f s" % (float(w.tick) * SimWorld.DT))
		if w.tick % rep == 0:
			var now := Time.get_ticks_msec()
			print("LP SOAK t=%5.0f s tick=%d cov=%.3f cd_left=%5.0f rate=%.2f phase=%d tide=%s weavers=%s posture=%s rings_fallen=%d cores=%d/%d machine_units=%d own_units=%d ms/tick=%.1f" % [
				float(w.tick) * SimWorld.DT, w.tick, Creep.coverage(w), float(s.cd_left), float(s.cd_rate), int(s.phase),
				str(bool(s.tide)), str(bool(s.weavers)), String(s.posture), int(s.get("rings_fallen", 0)), Cores.alive_count(w),
				(Cores.list(w) as Array).size(), w.units_of(int(s.mfid)).size(), w.units_of(int(s.fid)).size(),
				float(now - win_t) / float(rep)])
			win_t = now
			print("LP SOAK   losses own %s machine_lost %d" % [str(losses), m_lost])
		if wall_max > 0.0 and float(Time.get_ticks_msec() - wt0) / 1000.0 > wall_max:
			print("LP SOAK wall-clock cap reached")
			break
	var s2 = w.sys_state.get("lp")
	var wall := float(Time.get_ticks_msec() - wt0) / 1000.0
	var res: Dictionary = s2.get("result", {}) if s2 != null else {}
	if s2 != null and bool(s2.ended):
		ending = String(res.get("ending", "?"))
	var n := maxi(w.tick, 1)
	print("LP SOAK RESULT seed=%d map=%s time_s=%.0f ticks=%d phase=%d tide=%s tide_at_s=%.0f ending=%s creep=%.3f creep_peak=%.3f cd_left_s=%.0f cores_alive=%d/%d rings_fallen=%d score=%d medal=%s wall_s=%.0f ms_per_tick=%.2f lp_us_per_tick=%.0f lp_us_steady=%.0f creep_us_per_tick=%.0f cd_total=%.0f critical=%.2f" % [
		seed, map, float(w.tick) * SimWorld.DT, w.tick, phase_max, str(tide_tick >= 0), float(tide_tick) * SimWorld.DT if tide_tick >= 0 else -1.0,
		ending, Creep.coverage(w), float(s2.creep_peak) if s2 != null else 0.0, float(s2.cd_left) if s2 != null else 0.0,
		Cores.alive_count(w), (Cores.list(w) as Array).size(), int(s2.get("rings_fallen", 0)) if s2 != null else 0,
		int(res.get("score", 0)), String(res.get("medal", "")), wall, wall * 1000.0 / float(n),
		float(acc.lp) / float(n), float(acc.lp_steady) / float(maxi(n - 50, 1)), float(acc.creep) / float(n),
		float(lpr.countdown.total_s), float(lpr.creep.critical)])
	quit()
