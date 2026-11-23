extends SceneTree
## Short Done-when soak (not 60-min): LP match steps for N seconds of sim time, asserts no script crash
## and key boards stay sane. Optional mid-run save/resume (--save_at=secs).
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
	var w = SimWorld.new_match(LP.make_config(101, "industrial_heartland_m"))
	if w == null:
		printerr("SOAK fail: no world")
		quit(1)
		return
	var ticks := int(ceil(_secs * float(SimWorld.TICK_RATE)))
	var save_tick := -1
	if _save_at > 0.0:
		save_tick = int(ceil(_save_at * float(SimWorld.TICK_RATE)))
	print("SOAK_START secs=%.0f ticks=%d save_at=%.0f" % [_secs, ticks, _save_at])
	var t0 := Time.get_ticks_msec()
	var saved_hash := ""
	for i in ticks:
		w.step()
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
	var ms := Time.get_ticks_msec() - t0
	print("SOAK_DONE ticks=%d wall_ms=%d boards hive=%s fire=%s death=%s" % [
		ticks, ms, str(Hive71.board(w)), str(Fire71.board(w)), str(Death71.board(w))])
	quit(0)
