extends SceneTree
## Longer headless live-siege soak beyond the short Done-when harness.
## Exercises RE full chain (capture -> stages -> prototype, breakout purge, overrun),
## warmind repeated feints + abandon ask, fleet jam no-hack, fire, and H1 raid — in ONE run.
##   godot --headless --path . -s res://tools/g71_live_siege.gd -- --secs=600
var _secs := 600.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = float(a.substr(7))
	var LP = load("res://sim/systems/last_protocol.gd")
	var Hive71 = load("res://sim/systems/hive71.gd")
	var Fire71 = load("res://sim/systems/fire71.gd")
	var Death71 = load("res://sim/systems/death71.gd")
	var Gore71 = load("res://sim/systems/gore71.gd")
	var Re = load("res://sim/systems/recomplex71.gd")
	var Fleet71 = load("res://sim/systems/fleet71.gd")
	var Warmind71 = load("res://sim/systems/warmind71.gd")
	var Director71 = load("res://sim/systems/director71.gd")
	var w = SimWorld.new_match(LP.make_config(201, "industrial_heartland_m"))
	if w == null:
		printerr("SIEGE fail: no world")
		quit(1)
		return
	var ticks := int(ceil(_secs * float(SimWorld.TICK_RATE)))
	print("SIEGE_START secs=%.0f ticks=%d" % [_secs, ticks])
	var t0 := Time.get_ticks_msec()
	var fire_seeded := false
	var re_started := false
	var re_done := false
	var breakout_done := false
	var overrun_done := false
	var feint_n := 0
	var jam_done := false
	var raid_done := false
	# Schedule: fire@5t, jam@10%, first RE capture@15%, warmind every 90s, breakout@55%, overrun@70%, raid@85%.
	var jam_tick := maxi(int(SimWorld.TICK_RATE * 30), ticks / 10)
	var re_tick := maxi(int(SimWorld.TICK_RATE * 60), ticks * 15 / 100)
	var break_tick := maxi(re_tick + int(SimWorld.TICK_RATE * 50), ticks * 55 / 100)
	var overrun_tick := maxi(break_tick + int(SimWorld.TICK_RATE * 30), ticks * 70 / 100)
	var raid_tick := maxi(overrun_tick + int(SimWorld.TICK_RATE * 20), ticks * 85 / 100)
	var feint_every := int(SimWorld.TICK_RATE * 90)
	for i in ticks:
		w.step()
		if not fire_seeded and i == 5 and Fire71.active(w) and w.map != null:
			var base = w.sys_state.lp.get("base", {})
			var center := Vector2(base.get("center", Vector2(w.map.w * 0.5, w.map.h * 0.5)))
			var origin := center + Vector2(10, 2)
			var ox := clampi(floori(origin.x), 0, w.map.w - 1)
			var oy := clampi(floori(origin.y), 0, w.map.h - 1)
			w.map.terrain[oy * w.map.w + ox] = preload("res://sim/terrain.gd").GRASS
			Fire71.ignite_cell(w, Vector2(ox + 0.5, oy + 0.5), 0, 0.85)
			fire_seeded = true
			print("SIEGE_FIRE n=%s" % str(Fire71.board(w).get("n", 0)))
		if not jam_done and i == jam_tick and Fleet71.active(w):
			var fid := int(w.sys_state.lp.fid)
			var mfid := int(w.sys_state.lp.mfid)
			Fleet71.jam_sector(w, 3, 20.0)
			var hacked := 0
			for e in Fleet71.robots_of(w, fid):
				if int(e.get("owner", -1)) == mfid:
					hacked += 1
			print("SIEGE_JAM board_n=%s hacked=%d" % [str(Fleet71.board(w).get("n", 0)), hacked])
			if hacked > 0:
				printerr("SIEGE fail: robots hacked under jam")
				quit(3)
				return
			jam_done = true
		if not re_started and i == re_tick and Re.active(w):
			Re.capture(w, "g71_m_brute", "siege_c0")
			re_started = true
			print("SIEGE_RE_CAPTURE cell=siege_c0")
		# Advance RE stages by natural tick; mark when prototype lands.
		if re_started and not re_done and Re.active(w):
			var protos: Dictionary = Re._st(w).prototypes as Dictionary
			if protos.has("g71_m_brute"):
				re_done = true
				print("SIEGE_RE_PROTOTYPE unlocked=%s" % str(protos.keys()))
		if i > 0 and feint_every > 0 and i % feint_every == 0 and Warmind71.active(w):
			var push: Dictionary = Director71.pick_push([3, 1, 0, 2, 4, 0, 1, 0])
			var face := int(push.get("feint", 4))
			Warmind71.note_feint(w, face, true)
			Warmind71.note_feint(w, face, true)
			Warmind71.ask_abandon(w, int(push.get("main", 0)), "siege_pressure")
			feint_n += 1
			print("SIEGE_FEINT n=%d push=%s fooled=%s ask=%s logistics=%s" % [
				feint_n, str(push), str(Warmind71.fooled(w)),
				str(Warmind71.pending_ask(w).get("kind", "")),
				str(Director71.logistics_ready(0.82)),
			])
			if not Warmind71.fooled(w):
				printerr("SIEGE fail: warmind not fooled")
				quit(4)
				return
		if not breakout_done and i == break_tick and Re.active(w):
			Re.capture(w, "g71_m_glass_stalker", "siege_c1")
			Re.agitate(w, "siege_c1")
			Re.agitate(w, "siege_c1")
			Re.agitate(w, "siege_c1")
			Re.purge(w, "siege_c1")
			var hive_sig := bool(Re._st(w).get("hive_signal", true))
			print("SIEGE_BREAKOUT purged hive_signal=%s" % str(hive_sig))
			if hive_sig:
				printerr("SIEGE fail: hive signal during inside purge")
				quit(6)
				return
			breakout_done = true
		if not overrun_done and i == overrun_tick and Re.active(w):
			Re.capture(w, "g71_m_sapper", "siege_c2")
			Re.start_overrun(w, "retake")
			var need := int(ceil(Re.overrun_s() * float(SimWorld.TICK_RATE))) + 3
			for j in need:
				w.step()
			print("SIEGE_OVERRUN overrun_t=%s" % str(Re._st(w).get("overrun_t", -1)))
			overrun_done = true
		if not raid_done and i == raid_tick and w.sys_state.has("lp"):
			var s: Dictionary = w.sys_state.lp
			s.dread = 0.95
			s.core_raid = {}
			LP._core_raid_tick(w, s)
			var every := int(ceil(float(Director71.rules().get("core_raid_phase_s", 45.0)) * float(SimWorld.TICK_RATE)))
			var phases: Array = []
			for expect in ["soften", "breach", "purge", "failed"]:
				s.core_raid.t0 = w.tick - every - 1
				LP._core_raid_tick(w, s)
				phases.append(String(s.core_raid.get("phase", "")))
			print("SIEGE_RAID phases=%s failed=%s" % [str(phases), str(s.core_raid.get("failed", ""))])
			raid_done = true
		if i > 0 and i % int(SimWorld.TICK_RATE * 60) == 0:
			var bodies_n: int = Gore71.bodies(w).size() if Gore71.on(w) else 0
			print("SIEGE_MARK t=%.0fs hive=%s death=%s gore_bodies=%d re_cells=%d fooled=%s" % [
				float(i) / float(SimWorld.TICK_RATE),
				str(Hive71.board(w).get("beat", 0)),
				str(Death71.board(w)),
				bodies_n,
				(Re._st(w).cells as Dictionary).size() if Re.active(w) else 0,
				str(Warmind71.fooled(w)) if Warmind71.active(w) else "n/a",
			])
	# If RE prototype not yet unlocked (short --secs), force remaining stage ticks.
	if re_started and not re_done and Re.active(w):
		var need2: int = int(ceil(Re.stage_s() * float(SimWorld.TICK_RATE))) * (Re.STAGES.size() + 1) + 5
		for j in need2:
			w.step()
		var protos2: Dictionary = Re._st(w).prototypes as Dictionary
		re_done = protos2.has("g71_m_brute")
		print("SIEGE_RE_FORCE prototype=%s keys=%s" % [str(re_done), str(protos2.keys())])
	if not re_done:
		printerr("SIEGE fail: RE prototype not unlocked")
		quit(7)
		return
	if Fleet71.active(w):
		var fid_e := int(w.sys_state.lp.fid)
		var mfid_e := int(w.sys_state.lp.mfid)
		var hacked_e := 0
		for e2 in Fleet71.robots_of(w, fid_e):
			if int(e2.get("owner", -1)) == mfid_e:
				hacked_e += 1
		print("SIEGE_FLEET_END n=%s hacked=%d" % [str(Fleet71.board(w).get("n", 0)), hacked_e])
		if hacked_e > 0:
			printerr("SIEGE fail: robots hacked by end")
			quit(3)
			return
	var ms := Time.get_ticks_msec() - t0
	var bodies_end: int = Gore71.bodies(w).size() if Gore71.on(w) else 0
	print("SIEGE_DONE ticks=%d wall_ms=%d fire=%s jam=%s re=%s breakout=%s overrun=%s raid=%s feints=%d gore_bodies=%d boards hive=%s death=%s" % [
		ticks, ms, str(fire_seeded), str(jam_done), str(re_done), str(breakout_done),
		str(overrun_done), str(raid_done), feint_n, bodies_end,
		str(Hive71.board(w)), str(Death71.board(w))])
	quit(0)
