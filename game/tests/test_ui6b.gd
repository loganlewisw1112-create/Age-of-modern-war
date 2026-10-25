extends "res://tests/test_base.gd"
## G6 acceptance (owner: UI6b). CONTRACTS_G6 section 14, 15, 9, section 17.
## HUD-level checks run presentation/ui6/b/g6_probe.gd in a headless child Godot (tests run inside
## SceneTree._init, where no HUD can be built) and parse its PROBE lines; the probe runs once per test run
## (static cache). Static checks (hotkey table, yield / fallback keys, rect clamp, Stage 10 data) run here.

const Hotkeys = preload("res://presentation/ui5/panels/hotkeys.gd")
const G6Modes = preload("res://presentation/ui6/b/g6_modes.gd")
const G6Cmds = preload("res://presentation/ui6/b/g6_cmds.gd")
const LoadoutPanel = preload("res://presentation/ui6/b/loadout_panel.gd")
const ResearchPanel = preload("res://presentation/ui6/b/research_panel.gd")
const EditorLive = preload("res://sim/editor_live.gd")
const Loadouts = preload("res://sim/systems/loadouts.gd")

static var _probe: Dictionary = {}


func _run_probe() -> Dictionary:
	if not _probe.is_empty():
		return _probe
	var out: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "presentation/ui6/b/g6_probe.gd"])
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
	return check(bool(r.end) and r.errors.is_empty(), "g6 probe ran to the end (rc %d, errors %s)" % [int(r.rc), str(r.errors)])


func _expect(lines: Array, ctx: String) -> void:
	for l in lines:
		check(_probe_ok(String(l)), "%s: probe line '%s'" % [ctx, l])


## Button, hotkey, badge and icon lines for every action of a Hotkeys group.
func _action_lines(g: String) -> Array:
	var out: Array = []
	for a in Hotkeys.ACTIONS:
		if Hotkeys.group(String(a)) == g:
			var k := Hotkeys.key(String(a))
			out.append_array(["button %s" % a, "hotkey %s=%s" % [a, k], "badge %s" % a, "icon %s" % a])
	return out


func test_loadout_panel() -> void:
	# static: every rifleman loadout has a display name and stat line
	var lids: Array = Loadouts.loadouts_for(0, "rifleman")
	check(not lids.is_empty(), "human_a rifleman has loadouts")
	for lid in lids:
		check(LoadoutPanel.loadout_name(String(lid)) != "" and LoadoutPanel.stat_text(String(lid)) != "", "loadout %s has a name and stats" % lid)
	if not _probe_ran():
		return
	var lines := _action_lines("loadout6")
	lines.append_array(["key %s opens the loadout panel" % Hotkeys.key("loadout"), "barracks spawned next to the squad",
		"loadout panel lists %d loadouts" % lids.size(), "loadout panel uses the nearby barracks", "a loadout is available",
		"sim accepts set_loadout"])
	_expect(lines, "loadout")


func test_garage_panel() -> void:
	if not _probe_ran():
		return
	var lines := _action_lines("garage6")
	lines.append_array(["garage and pilots spawned", "garage panel shows 2 pilots", "garage: treated pilot can re-suit",
		"garage: wounded pilot cannot re-suit", "Re-suit card button enabled", "sim accepts resuit"])
	_expect(lines, "garage")


func test_live_toggle_and_speed() -> void:
	check(EditorLive.SPEEDS.has(1) and EditorLive.SPEEDS.has(2) and EditorLive.SPEEDS.has(4), "Live speeds 1 / 2 / 4: " + str(EditorLive.SPEEDS))
	if not _probe_ran():
		return
	_expect(["live toggle disabled without a world", "live toggle enabled with a world", "Live on: world in live mode",
		"Live off restores the pre-Live state", "speed 2 set", "L starts Live at speed 2", "L stops Live and restores"], "live")


func test_mine_garrison_rail_tools() -> void:
	# static: no card key collides (G6 included), the yield pairs are declared and have a fallback
	var col := Hotkeys.collisions()
	check(col.is_empty(), "card hotkey collisions: " + str(col))
	check_eq(Hotkeys.fallback_key({}), "J", "first fallback key")
	check_eq(Hotkeys.fallback_key({"J": 1, "U": 1}), "X", "fallback skips taken keys")
	var all := {}
	for k in Hotkeys.G6_FALLBACK:
		all[k] = 1
	check_eq(Hotkeys.fallback_key(all), "", "no fallback when every key is taken")
	check(Hotkeys.yields("drone", "garrison6") and Hotkeys.yields("loadout6", "tactical"), "Drone Team yield pairs declared")
	# static: rect drags clamp to the Mines max rect from the first corner
	var mx := G6Modes.max_rect()
	check_eq(G6Modes.rect_of(Vector2i(10, 10), Vector2i(40, -20)), [10, 10 - (mx - 1), 10 + (mx - 1), 10], "rect clamps to %d x %d" % [mx, mx])
	check_eq(G6Modes.rect_of(Vector2i(5, 5), Vector2i(3, 6)), [3, 5, 5, 6], "small rect kept as dragged")
	check_eq(G6Modes.dir_name(Vector2(0, 0), Vector2(5, 1)), "e", "bridge direction from the drag")
	if not _probe_ran():
		return
	var lines: Array = []
	for g in Hotkeys.G6_UNIT_GROUPS:
		lines.append("spawn %s" % g)
		lines.append_array(_action_lines(String(g)))
	for g in ["garrison_bld6", "battery6"]:
		lines.append_array(_action_lines(g))
	for a in G6Cmds.UNIT_ACTIONS:
		var m := String(G6Cmds.UNIT_ACTIONS[a][0])
		if m != "":
			lines.append("key %s arms %s" % [Hotkeys.key(String(a)), m])
	lines.append_array(["single-def cards: no undeclared key overlap",
		"drag issues lay_minefield", "sim accepts lay_minefield", "minefield rect clamps to %d" % mx, "drag issues sweep", "sim accepts sweep",
		"click issues line_charge", "sim accepts line_charge", "click issues designate", "sim accepts designate",
		"click issues strike", "sim accepts strike", "garrison building spawned", "click issues garrison", "sim accepts garrison",
		"click issues breach", "rail yard spawned", "line drag issues build_rail", "sim accepts build_rail",
		"click issues deploy_bridge dir e", "click issues airdrop", "drag issues lay_sea_mines", "sim accepts cloak", "sim accepts aerostat",
		"aerostat rising after Raise", "key %s arms a battery strike" % Hotkeys.key("battery_strike"), "click issues a battery strike",
		"sim accepts battery strike", "engineer card page 1 build_rail", "engineer card page 1 garrison", "engineer card page 2 build_rail",
		"engineer card page 2 garrison", "drone card keeps drone_strike", "drone card garrison yields to", "drone card loadout yields to"])
	_expect(lines, "G6 tools")
	check((_run_probe().fail as Array).is_empty(), "probe failures: " + "\n    ".join(PackedStringArray(_run_probe().fail.slice(0, 10))))


func test_research_and_stage10_entries() -> void:
	check(not ResearchPanel.stage10_unlocks("human_a").is_empty(), "human_a has Stage 10 unlocks")
	if not _probe_ran():
		return
	_expect(["research building spawned", "research panel lists", "Stage 10 gate is g6_automation_doctrine", "Stage 10 block lists its unlocks",
		"card has no other-faction research"], "research")
