extends SceneTree
## Headless test runner.
##   godot --headless --path game --import            (once, or after adding class_name scripts / assets)
##   godot --headless --path game -s tests/run_tests.gd [-- --only=test_core]
## Discovers res://tests/test_*.gd. Each file extends RefCounted (tests/test_base.gd) and
## defines func test_*() methods. Exits 0 only if every test passed.

func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var files := []
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_base.gd":
			if only == "" or f.get_basename() == only:
				files.append(f)
	files.sort()
	var passed := 0
	var failed := 0
	var failures := []
	var t0 := Time.get_ticks_msec()
	for f in files:
		var script = load("res://tests/" + f)
		if script == null:
			failed += 1
			failures.append("%s: failed to load (parse error?)" % f)
			continue
		var methods := []
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_"):
				methods.append(String(m.name))
		methods.sort()
		for m in methods:
			var inst = script.new()
			inst.failures = []
			var ts := Time.get_ticks_msec()
			print("  RUN  %s::%s" % [f.get_basename(), m])
			inst.call(m)
			var ms := Time.get_ticks_msec() - ts
			if inst.failures.is_empty():
				passed += 1
				print("  PASS %s::%s (%d ms)" % [f.get_basename(), m, ms])
			else:
				failed += 1
				for msg in inst.failures:
					failures.append("%s::%s — %s" % [f.get_basename(), m, msg])
				print("  FAIL %s::%s (%d ms)" % [f.get_basename(), m, ms])
	print("")
	for msg in failures:
		print("FAILURE: " + msg)
	print("RESULT pass=%d fail=%d files=%d time_ms=%d" % [passed, failed, files.size(), Time.get_ticks_msec() - t0])
	quit(0 if failed == 0 and passed > 0 else 1)
