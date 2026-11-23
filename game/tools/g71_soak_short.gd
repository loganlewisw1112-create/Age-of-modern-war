extends SceneTree
## Short Done-when soak (not 60-min): LP match steps for N seconds of sim time, asserts no script crash
## and key boards stay sane. Usage:
##   godot --headless --path . -s res://tools/g71_soak_short.gd -- --secs=120
var _secs := 120.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = float(a.substr(7))
	var LP = load("res://sim/systems/last_protocol.gd")
	var Hive71 = load("res://sim/systems/hive71.gd")
	var Fire71 = load("res://sim/systems/fire71.gd")
	var Death71 = load("res://sim/systems/death71.gd")
	var w = SimWorld.new_match(LP.make_config(101, "industrial_heartland_m"))
	if w == null:
		printerr("SOAK fail: no world")
		quit(1)
		return
	var ticks := int(ceil(_secs * float(SimWorld.TICK_RATE)))
	print("SOAK_START secs=%.0f ticks=%d" % [_secs, ticks])
	var t0 := Time.get_ticks_msec()
	for i in ticks:
		w.step()
		if i > 0 and i % int(SimWorld.TICK_RATE * 30) == 0:
			print("SOAK_MARK t=%.0fs hive=%s fire=%s death=%s" % [
				float(i) / float(SimWorld.TICK_RATE),
				str(Hive71.board(w)),
				str(Fire71.board(w)),
				str(Death71.board(w)),
			])
	var ms := Time.get_ticks_msec() - t0
	print("SOAK_DONE ticks=%d wall_ms=%d boards hive=%s fire=%s death=%s" % [
		ticks, ms, str(Hive71.board(w)), str(Fire71.board(w)), str(Death71.board(w))])
	quit(0)
