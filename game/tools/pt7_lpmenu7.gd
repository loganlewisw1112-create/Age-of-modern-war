extends RefCounted
## G7 (ORCH, owner bug 2026-10-28): start Last Protocol through the REAL main-menu button while a custom map is picked in
## the skirmish lobby (what the owner did). Before the fix the skirmish setup's finalize() swapped the custom map into the
## LP config (map_file), so the LP base was built on a 128x128 custom map. The run must be on the 512x512 last_protocol
## map with the base rings in place, whatever the lobby holds.

const MapGen = preload("res://sim/map_gen.gd")
const LPM = preload("res://sim/maps/last_protocol.gd")


func run(pt) -> void:
	pt.main.show_menu()   # the harness starts in a skirmish match: back to the main menu, as a player would
	await pt._wait(1.0)
	var menu = pt.main._menu
	pt._log("lpmenu7_menu", menu != null, "main menu node present")
	if menu == null:
		return
	var setup = menu.get("setup")
	var custom := "res://content/scenarios/tutorial.rtsmap"
	if setup != null and setup.get("browser") != null:
		setup.browser.current = {"kind": "custom", "path": custom, "scenario": {}}
	pt._log("lpmenu7_lobby_custom", setup != null and setup.is_custom(), "skirmish lobby holds custom map %s" % custom)
	var b: Button = pt.get_tree().root.find_child("LastProtocolButton", true, false) as Button
	pt._log("lpmenu7_button", b != null, "LAST PROTOCOL button found")
	if b == null:
		return
	var old_w = pt.main.match_view.world if pt.main.match_view != null else null
	b.pressed.emit()   # the button's own handler: LastProtocol.make_config(seed) -> start_requested -> finalize -> start
	var started: bool = await pt._wait_until(func(): return pt.main.match_view != null and pt.main.match_view.world != null and pt.main.match_view.world != old_w, 30.0)
	pt._log("lpmenu7_started", started, "a new match started from the button")
	if not started:
		return
	var w: SimWorld = pt._w()
	var m: Dictionary = w.map
	pt._log("lpmenu7_mode", String(w.cfg.get("mode", "")) == "last_protocol", "mode %s" % String(w.cfg.get("mode", "")))
	pt._log("lpmenu7_no_custom_map", not w.cfg.has("map_file"), "cfg.map_file %s" % str(w.cfg.get("map_file", "-")))
	pt._log("lpmenu7_map_512", String(m.get("id", "")) == "last_protocol" and int(m.get("w", 0)) == LPM.N and int(m.get("h", 0)) == LPM.N,
		"map %s %dx%d" % [String(m.get("id", "")), int(m.get("w", 0)), int(m.get("h", 0))])
	var ok: bool = await pt._wait_until(func(): return w.sys_state.has("lp") and bool(w.sys_state.lp.get("filled", false)), 60.0)
	pt.main.match_view.join_sim()
	pt._log("lpmenu7_base_built", ok and (w.sys_state.lp.base.rings as Array).size() == 2, "LP base set up with %d rings" % (
		(w.sys_state.lp.base.rings as Array).size() if ok else -1))
	await pt._shot("lpmenu7_start")
