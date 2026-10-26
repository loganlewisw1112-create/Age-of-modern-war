extends RefCounted
## G6.1 playtest flow audio61 (AUDIO61). The harness can't hear, so the flow logs what the audio director started:
## a real firefight (tanks + riflemen; sim ShotFired / EntityDestroyed) -> battle sound ids + counts + voice peaks;
## CHAIN61 reports from the player's side (real CommandNet.report) and an enemy report -> radio lines played (enemy
## must stay silent); engine loops for selected tanks; then Settings > Audio: sliders moved, buses checked, shot.
## If ORCH's MatchView / Settings hook lines are not in yet, the flow attaches the director / tab itself and says so.

const H = preload("res://tests/test_machine_g6.gd")
const Director = preload("res://presentation/audio/audio_director.gd")
const Buses = preload("res://presentation/audio/audio_buses.gd")
const AudioTab = preload("res://presentation/audio/audio_tab.gd")
const SettingsMenu = preload("res://presentation/menu/settings.gd")
const CommandNet = preload("res://sim/systems/command_net.gd")


func _director(pt):
	var mv = pt._mv()
	var d = mv.get_node_or_null("AudioDirector")
	if d == null:
		d = Director.new()
		mv.add_child(d)
		d.setup(mv)
		pt._log("audio_director_attached_by_flow", true, "MatchView hook (change_request to ORCH) not in yet")
	else:
		pt._log("audio_director_present", true, "hooked by MatchView")
	return d


func run(pt) -> void:
	var mv = pt._mv()
	var d = _director(pt)
	pt._log("audio_enabled", bool(d.enabled), "driver %s, players so far %d" % [AudioServer.get_driver_name(), int(d.players_created)])
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	var c: Vector2i = h._open(w, 7)
	var mine: Array = []
	for i in 3:
		mine.append(int(h._unit(w, "mbt", 0, Vector2(c) + Vector2(-3.5, i - 0.5)).id))
		h._unit(w, "mbt", 1, Vector2(c) + Vector2(3.5, i - 0.5))
	for i in 4:
		h._unit(w, "rifleman", 0, Vector2(c) + Vector2(-2.5, 2.0 + i * 0.5))
		h._unit(w, "rifleman", 1, Vector2(c) + Vector2(2.5, 2.0 + i * 0.5))
	mv.center_camera_on(Vector2(c))
	mv.selection.assign(mine)
	mv.selection_changed.emit()
	# 1. firefight: battle sounds
	var loud: bool = await pt._wait_until(func(): return int(d.counts.get("shot_cannon", 0)) >= 2 and int(d.counts.get("shot_rifle", 0)) + int(d.counts.get("shot_mg", 0)) >= 2, 30.0)
	pt._log("audio_firefight_sounds", loud, _counts(d))
	await pt._shot("audio61_firefight")
	await pt._wait(6.0)
	pt._log("audio_voice_limits", _limits_ok(d), "peaks %s, refused %d" % [str(d.mixer.peak), int(d.mixer.refused)])
	pt._log("audio_engine_loops", int(d._engines.size()) > 0 or not d.enabled, "engines %d (selected tanks)" % d._engines.size())
	# 2. radio chatter from CHAIN61 reports (player side) + an enemy report that must stay silent
	mv.join_sim()
	var before := int(d.radio_log.size())
	# reports made between steps land in w.events, which the next step clears: hand them to the director directly
	var n0 := int(w.events.size())
	var enemy_unit := int(h._unit(w, "rifleman", 1, Vector2(c) + Vector2(6, 6)).id)
	CommandNet.report(w, 1, enemy_unit, "casualty", "Enemy: 2 casualties (total 2)", {})
	var q0 := int(d.radio.size()) + int(d.radio_log.size())
	d.handle_events(w.events.slice(n0))
	pt._log("audio_enemy_radio_silent", int(d.radio.size()) + int(d.radio_log.size()) == q0, "enemy ReportSent queued nothing")
	n0 = int(w.events.size())
	CommandNet.report(w, 0, mine[0], "contact", "Tank 1: contact, 3 enemy (3 armor), 7 tiles E", {"count": 3, "armor": 3})
	CommandNet.request(w, 0, mine[1], "resupply", {"what": "ammo"})
	var own: Array = w.events.slice(n0)
	d.handle_events(own)
	var heard: bool = await pt._wait_until(func(): return d.radio_log.size() >= before + 1, 20.0)
	var lines: Array = d.radio_log.slice(before).map(func(r): return "%s(%s)" % [r.line, r.cat])
	pt._log("audio_radio_lines", heard, "%d own reports -> %s" % [own.size(), ", ".join(lines)])
	var has_contact := false
	for l in d.radio_log.map(func(r): return "(%s)" % r.cat):
		has_contact = has_contact or String(l).contains("(contact)")
	pt._log("audio_radio_contact_heard", has_contact, str(lines))
	await pt._wait(4.0)
	pt._log("audio_radio_total", d.radio_log.size() > 0, "all radio so far: %s" % str(d.radio_log.map(func(r): return String(r.line))))
	# 3. Settings > Audio: move the sliders
	await _settings_flow(pt)
	pt._log("audio_summary", true, _counts(d))


func _counts(d) -> String:
	var ks: Array = d.counts.keys()
	ks.sort()
	return ", ".join(ks.map(func(k): return "%s=%d" % [k, int(d.counts[k])]))


func _limits_ok(d) -> bool:
	for c in d.mixer.peak:
		if int(d.mixer.peak[c]) > d.mixer.cap(String(c)):
			return false
	return true


func _settings_flow(pt) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120  # above the HUD canvas layers, like the pause menu
	pt._mv().get_tree().root.add_child(layer)
	var menu = SettingsMenu.new()
	layer.add_child(menu)
	await pt._wait(0.3)
	var tabs: TabContainer = menu.find_child("SettingsTabs", true, false)
	var tab = tabs.get_node_or_null("Audio") if tabs != null else null
	if tab == null and tabs != null:
		tab = AudioTab.build()
		tabs.add_child(tab)
		pt._log("audio_tab_added_by_flow", true, "Settings hook (change_request to ORCH) not in yet")
	if tabs != null:
		tabs.current_tab = tab.get_index()
	await pt._wait(0.3)
	var old_b := float(Buses.get_setting("battle"))
	var old_r := float(Buses.get_setting("radio"))
	(tab.get_node("OptVolBattle") as HSlider).value = 35.0
	(tab.get_node("OptVolRadio") as HSlider).value = 100.0
	await pt._wait(0.3)
	var bdb := AudioServer.get_bus_volume_db(Buses.bus_index("Battle")) - Buses.duck_db()
	var rdb := AudioServer.get_bus_volume_db(Buses.bus_index("Radio"))
	pt._log("audio_sliders_apply", absf(bdb - linear_to_db(0.35)) < 0.05 and absf(rdb) < 0.05,
		"battle %.1f dB, radio %.1f dB" % [bdb, rdb])
	await pt._shot("audio61_settings")
	(tab.get_node("OptVolBattle") as HSlider).value = old_b * 100.0
	(tab.get_node("OptVolRadio") as HSlider).value = old_r * 100.0
	layer.queue_free()
	await pt._wait(0.2)
