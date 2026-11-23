extends SceneTree
## Done-when soak harness: LP match steps for N seconds of sim time, asserts no script crash
## and key boards stay sane. Mid-run exercises: fire seed, fleet jam (Done-when 6), warmind
## feints + abandon ask (11), director pick_push / logistics (4), optional save/resume (7), RE (12).
##   godot --headless --path . -s res://tools/g71_soak_short.gd -- --secs=120 [--save_at=60]
var _secs := 120.0
var _save_at := -1.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = float(a.substr(7))
		elif a.begins_with("--save_at="):
			_save_at = float(a.substr(10))
	var LP = load("res://sim/systems/last_protocol.gd")
	var Hive71 = load("res://sim/systems/hive71.gd")
	var Fire71 = load("res://sim/systems/fire71.gd")
	var Death71 = load("res://sim/systems/death71.gd")
	var Re = load("res://sim/systems/recomplex71.gd")
	var Fleet71 = load("res://sim/systems/fleet71.gd")
	var Warmind71 = load("res://sim/systems/warmind71.gd")
	var Director71 = load("res://sim/systems/director71.gd")
	var w = SimWorld.new_match(LP.make_config(101, "industrial_heartland_m"))
	if w == null:
		printerr("SOAK fail: no world")
		quit(1)
		return
	var ticks := int(ceil(_secs * float(SimWorld.TICK_RATE)))
	var save_tick := -1
	if _save_at > 0.0:
		save_tick = int(ceil(_save_at * float(SimWorld.TICK_RATE)))
	# Mid-soak siege exercises (~25% and ~50% of run when long enough).
	var jam_tick := maxi(int(SimWorld.TICK_RATE * 20), ticks / 4)
	var feint_tick := maxi(int(SimWorld.TICK_RATE * 40), ticks / 2)
	print("SOAK_START secs=%.0f ticks=%d save_at=%.0f" % [_secs, ticks, _save_at])
	var t0 := Time.get_ticks_msec()
	var saved_hash := ""
	var fire_seeded := false
	var jam_done := false
	var feint_done := false
	for i in ticks:
		w.step()
		# After LP boards exist, seed a grass fire once (I4/I5 live exercise).
		if not fire_seeded and i == 5 and Fire71.active(w) and w.sys_state.has("lp") and w.map != null:
			var base = w.sys_state.lp.get("base", {})
			var center := Vector2(base.get("center", Vector2(w.map.w * 0.5, w.map.h * 0.5)))
			var origin := center + Vector2(8, 0)
			var ox := clampi(floori(origin.x), 0, w.map.w - 1)
			var oy := clampi(floori(origin.y), 0, w.map.h - 1)
			w.map.terrain[oy * w.map.w + ox] = preload("res://sim/terrain.gd").GRASS
			Fire71.ignite_cell(w, Vector2(ox + 0.5, oy + 0.5), 0, 0.9)
			fire_seeded = true
			print("SOAK_FIRE seeded at %s n=%s" % [str(origin), str(Fire71.board(w).get("n", 0))])
		# Done-when 6: jam a sector; robots must stay ours (never owner-flipped to hive).
		if not jam_done and i == jam_tick and Fleet71.active(w):
			var fid := int(w.sys_state.lp.fid)
			var mfid := int(w.sys_state.lp.mfid)
			Fleet71.jam_sector(w, 2, 12.0)
			var fb: Dictionary = Fleet71.board(w)
			var hacked := 0
			for e in Fleet71.robots_of(w, fid):
				if int(e.get("owner", -1)) == mfid:
					hacked += 1
			print("SOAK_JAM board=%s hacked=%d" % [str(fb), hacked])
			if hacked > 0:
				printerr("SOAK fail: robots hacked to hive under jam")
				quit(3)
				return
			jam_done = true
		# Done-when 4/11: director feint pick + warmind fooled + abandon ask.
		if not feint_done and i == feint_tick and Warmind71.active(w):
			var push: Dictionary = Director71.pick_push([2, 1, 0, 0, 3, 0, 0, 0])
			Warmind71.note_feint(w, int(push.get("feint", 4)), true)
			Warmind71.note_feint(w, int(push.get("feint", 4)), true)
			Warmind71.ask_abandon(w, int(push.get("main", 0)), "soak_pressure")
			var dread := 0.8
			print("SOAK_FEINT push=%s fooled=%s logistics=%s ask=%s" % [
				str(push),
				str(Warmind71.fooled(w)),
				str(Director71.logistics_ready(dread)),
				str(Warmind71.pending_ask(w).get("kind", "")),
			])
			if not Warmind71.fooled(w):
				printerr("SOAK fail: warmind not fooled by repeated feint")
				quit(4)
				return
			feint_done = true
		if save_tick > 0 and i == save_tick:
			saved_hash = w.state_hash()
			w = SimWorld.from_dict(w.to_dict().duplicate(true))
			var h2 := w.state_hash()
			print("SOAK_SAVE tick=%d hash_match=%s" % [i, str(h2 == saved_hash)])
			if h2 != saved_hash:
				printerr("SOAK fail: mid-run save hash mismatch")
				quit(2)
				return
		if i > 0 and i % int(SimWorld.TICK_RATE * 30) == 0:
			print("SOAK_MARK t=%.0fs hive=%s fire=%s death=%s re_cells=%d" % [
				float(i) / float(SimWorld.TICK_RATE),
				str(Hive71.board(w)),
				str(Fire71.board(w)),
				str(Death71.board(w)),
				(Re._st(w).cells as Dictionary).size() if Re.active(w) else 0,
			])
	# Done-when 8: drive a multi-phase core raid to a reported failed purge (or done).
	var LP_sys = load("res://sim/systems/last_protocol.gd")
	if w.sys_state.has("lp"):
		var s: Dictionary = w.sys_state.lp
		s.dread = 0.95
		s.core_raid = {}
		LP_sys._core_raid_tick(w, s)
		var every := int(ceil(float(Director71.rules().get("core_raid_phase_s", 45.0)) * float(SimWorld.TICK_RATE)))
		var phases: Array = []
		for expect in ["soften", "breach", "purge", "failed"]:
			s.core_raid.t0 = w.tick - every - 1
			LP_sys._core_raid_tick(w, s)
			phases.append(String(s.core_raid.get("phase", "")))
		print("SOAK_RAID phases=%s failed=%s" % [str(phases), str(s.core_raid.get("failed", ""))])
		if String(s.core_raid.get("phase", "")) != "failed" and String(s.core_raid.get("phase", "")) != "done":
			printerr("SOAK fail: core raid did not reach failed/done")
			quit(5)
			return
	# Kick a short RE study chain near the end so Done-when 12 gets live-siege exercise.
	if Re.active(w):
		Re.capture(w, "g71_m_brute", "soak_c0")
		var need := int(ceil(Re.stage_s() * float(SimWorld.TICK_RATE))) * 2 + 5
		for j in need:
			w.step()
		print("SOAK_RE cells=%d prototypes=%s" % [
			(Re._st(w).cells as Dictionary).size(),
			str((Re._st(w).prototypes as Dictionary).keys()),
		])
	# Final jam integrity check (Done-when 6).
	if Fleet71.active(w):
		var fid_end := int(w.sys_state.lp.fid)
		var mfid_end := int(w.sys_state.lp.mfid)
		var hacked_end := 0
		for e2 in Fleet71.robots_of(w, fid_end):
			if int(e2.get("owner", -1)) == mfid_end:
				hacked_end += 1
		print("SOAK_FLEET board=%s hacked_end=%d" % [str(Fleet71.board(w)), hacked_end])
		if hacked_end > 0:
			printerr("SOAK fail: robots hacked by end")
			quit(3)
			return
	var ms := Time.get_ticks_msec() - t0
	print("SOAK_DONE ticks=%d wall_ms=%d boards hive=%s fire=%s death=%s jam=%s feint=%s" % [
		ticks, ms, str(Hive71.board(w)), str(Fire71.board(w)), str(Death71.board(w)),
		str(jam_done), str(feint_done)])
	quit(0)
