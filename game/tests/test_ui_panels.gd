extends "res://tests/test_base.gd"
## G5 acceptance (owner: UI5b). CONTRACTS_G5 section 11.
## HUD-level checks run presentation/ui5/panels/panel_probe.gd in a headless child Godot (tests run
## inside SceneTree._init, where no HUD can be built) and parse its PROBE lines; the probe runs once
## per test run (static cache). Static checks (hotkey table, build pages, settings store) run here.

const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")
const Settings = preload("res://presentation/menu/settings.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")

static var _probe: Dictionary = {}


func _run_probe() -> Dictionary:
	if not _probe.is_empty():
		return _probe
	var out: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "presentation/ui5/panels/panel_probe.gd"])
	var rc := OS.execute(OS.get_executable_path(), args, out, true)
	var r := {"rc": rc, "ok": [], "fail": [], "end": false, "errors": []}
	for ln in "\n".join(PackedStringArray(out)).split("\n"):
		var l := String(ln).strip_edges()
		if l.begins_with("PROBE OK "):
			r.ok.append(l.substr(9))
		elif l.begins_with("PROBE FAIL "):
			r.fail.append(l.substr(11, 220))
		elif l.begins_with("PROBE END"):
			r.end = true
		elif (l.contains("SCRIPT ERROR") or l.contains("Parse Error")) and r.errors.size() < 6:
			r.errors.append(l.substr(0, 200))
	_probe = r
	return r


func _probe_ok(what: String) -> bool:
	var r := _run_probe()
	for l in r.ok:
		if String(l).begins_with(what):
			return true
	return false


func _probe_ran() -> bool:
	var r := _run_probe()
	return check(bool(r.end) and r.errors.is_empty(), "panel probe ran to the end (rc %d, errors %s)" % [int(r.rc), str(r.errors)])


func test_every_new_command_has_button_and_hotkey() -> void:
	if not _probe_ran():
		return
	var cmds := {}
	for a in Hotkeys.ACTIONS:
		var a_s := String(a)
		cmds[String(Hotkeys.ACTIONS[a][3])] = true
		check(_probe_ok("button " + a_s), "%s has a card button" % a_s)
		check(_probe_ok("hotkey %s=%s" % [a_s, Hotkeys.key(a_s)]), "%s hotkey %s presses its button" % [a_s, Hotkeys.key(a_s)])
	# every CONTRACTS_G5 section 4 command is covered by at least one action
	for c in ["build_hangar", "upgrade_hangar", "upgrade_airfield", "assign_engineers", "sortie", "rebase", "land_at",
			"take_off", "bombard", "launch_drone", "tactical", "set_auto_resupply", "set_auto_evac"]:
		check(cmds.has(c), "command %s has a button" % c)
	for l in ["key T arms sortie", "key N arms land_at", "key Y arms bombard", "key Z arms launch_drone",
			"key Z arms tactical", "key K arms auto_area", "key J arms auto_area", "key N arms assign_engineers",
			"take_off enabled", "click issues land_at", "click issues bombard", "click issues launch_drone",
			"click issues sortie", "click issues tactical", "truck station drag", "sim accepted the G5 commands",
			"F1 sheet has the G5 rows"]:
		check(_probe_ok(l), "probe: " + l)
	check((_run_probe().fail as Array).is_empty(), "probe failures: " + "\n    ".join(PackedStringArray(_run_probe().fail.slice(0, 10))))


func test_hotkeys_have_no_collisions() -> void:
	var col := Hotkeys.collisions()
	check(col.is_empty(), "card hotkey collisions: " + str(col))
	# every faction's build card: unique, non-reserved keys within each category page
	for fac in Content.faction_ids():
		var used := {}
		var n := 0
		for p in G3.build_pages(String(fac)):
			var keys := {}
			for d in p.defs:
				var hk := G3.build_hotkey(String(d), used)
				n += 1
				check(hk != "" and not G3.RESERVED_BUILD_KEYS.has(hk), "%s %s key %s" % [fac, d, hk])
				check(not keys.has(hk), "%s page %s key %s unique" % [fac, p.cat, hk])
				keys[hk] = true
				check(not Hotkeys.GLOBAL.has(hk) or hk == "D", "%s %s key %s is not a global key" % [fac, d, hk])
		check_eq(n, Content.buildable_for(String(fac)).size(), "%s every buildable is on a page" % fac)
	if _probe_ran():
		check(_probe_ok("Tab visits all"), "Tab cycles every build page in the HUD")


func test_settings_persist() -> void:
	var path := "user://ui5b_test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Settings.use_path(path)
	check_eq(Settings.current_path(), path, "store uses the test file")
	check_eq(String(Settings.get_value("game", "health_bars")), "damaged", "default health bars")
	check_eq(bool(Settings.get_value("game", "edge_pan")), true, "default edge-pan")
	Settings.set_value("game", "speed", 2.0)
	Settings.set_value("game", "edge_pan", false)
	Settings.set_value("game", "health_bars", "selected")
	Settings.set_value("graphics", "max_fps", 60)
	check_eq(Settings.save(), OK, "settings saved")
	Settings.reload()   # as a new game start would
	check_eq(float(Settings.get_value("game", "speed")), 2.0, "speed persisted")
	check_eq(bool(Settings.get_value("game", "edge_pan")), false, "edge-pan persisted")
	check_eq(Settings.health_bars(), "selected", "health bars persisted")
	check_eq(int(Settings.get_value("graphics", "max_fps")), 60, "frame cap persisted")
	var fake = _FakeMV.new()
	Settings.apply_to_match(fake)
	check(is_equal_approx(fake.speed, 2.0) and not fake._edge_pan_enabled, "apply_to_match sets speed and edge-pan")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Settings.use_path(Settings.DEFAULT_PATH)


class _FakeMV:
	var speed := 1.0
	var _edge_pan_enabled := true


func test_key_rebinding_round_trip() -> void:
	var path := "user://ui5b_test_keys.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Settings.use_path(path)
	check_eq(Settings.current_path(), path, "store uses the test file")
	check_eq(Hotkeys.key("sortie"), "T", "default sortie key")
	check(Settings.set_binding("sortie", "B") != "", "B collides with Rebase on the aircraft card: refused")
	check(Settings.set_binding("sortie", "P") != "", "P is the global pause key: refused")
	check(Settings.set_binding("stop", "X") != "", "fixed G1 key cannot be rebound")
	check_eq(Settings.set_binding("sortie", "x"), "", "sortie -> X accepted")
	check_eq(Hotkeys.key("sortie"), "X", "sortie now X")
	check_eq(Settings.save(), OK, "keys saved")
	Settings.reload()
	check_eq(Hotkeys.key("sortie"), "X", "rebinding survives a reload")
	check(Hotkeys.collisions().is_empty(), "still no collisions: " + str(Hotkeys.collisions()))
	Settings.reset_bindings()
	check_eq(Hotkeys.key("sortie"), "T", "reset restores the default")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Settings.use_path(Settings.DEFAULT_PATH)
	if _probe_ran():
		for l in ["rebind refuses a colliding key", "rebind bombard to Z", "rebind persisted", "card uses the rebound key"]:
			check(_probe_ok(l), "settings menu: " + l)


func test_airfield_panel_shows_no_free_hangar() -> void:
	if not _probe_ran():
		return
	for l in ["airfield spawned", "panel shows No free hangar", "Buy light hangar enabled", "warning clears once a hangar is ready",
			"button hangar_light", "button extra_strip"]:
		check(_probe_ok(l), "probe: " + l)
