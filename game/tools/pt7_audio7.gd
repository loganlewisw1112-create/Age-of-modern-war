extends RefCounted
## G7 playtest flow audio7 (AUDIO7). The harness can't hear, so the flow logs what plays: music mode + layer levels
## at every state, Music / Master bus peaks, voice lines (barks, acks, HQ, PROTOCOL) with subtitles, G7 sound ids,
## and records a short WAV of the Master bus (AudioEffectRecord) into the shot dir.
## States driven: planning -> convoy (tension) -> Last Protocol tension (countdown half used; LP state through the
## director's lp_override, a full 60-90 min run is out of reach for a flow) -> a real firefight (combat drums, sim
## ShotFired) -> operator barks of all 4 personalities -> command ack + PROTOCOL line -> G7 sound effects at the
## camera -> pre-Tide silence (countdown seconds before its final stage) -> TheTide (stinger + Tide theme) ->
## PROTOCOL voice muted -> Settings > Audio shows the Voice slider + PROTOCOL toggle.

const H = preload("res://tests/test_machine_g6.gd")
const Director = preload("res://presentation/audio/audio_director.gd")
const Buses = preload("res://presentation/audio/audio_buses.gd")
const AudioTab = preload("res://presentation/audio/audio_tab.gd")
const Cat7 = preload("res://presentation/audio/audio_catalog7.gd")

var _peak := {"Master": -80.0, "Music": -80.0}
var _sampling := false


func _director(pt):
	var mv = pt._mv()
	var d = mv.get_node_or_null("AudioDirector")
	if d == null:
		d = Director.new()
		mv.add_child(d)
		d.setup(mv)
		pt._log("audio_director_hooked", false, "MatchView did not attach the AudioDirector (the flow attached it)")
	else:
		pt._log("audio_director_hooked", true, "hooked by MatchView")
	return d


func _sample() -> void:
	if not _sampling:
		return
	for b in _peak:
		var i := AudioServer.get_bus_index(String(b))
		if i >= 0:
			_peak[b] = maxf(float(_peak[b]), maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0)))


func _state(d) -> String:
	var m: Dictionary = d.music_state()
	var lv: Dictionary = m.levels
	return "mode %s | amb %.2f ten %.2f pul %.2f drm %.2f tide %.2f | music peak %.1f dB" % [m.mode, float(lv.ambient),
		float(lv.tension), float(lv.pulse), float(lv.drums), float(lv.tide), float(_peak.Music)]


func _lp(over: Dictionary) -> Dictionary:
	var l := {"cd_left": 3000.0, "cd_total": 3600.0, "cd_rate": 1.0, "final_stage": false, "phase": 0, "frac": 0.05,
		"tide": false, "weavers": false}
	l.merge(over, true)
	return l


func run(pt) -> void:
	var mv = pt._mv()
	var d = _director(pt)
	pt._log("audio7_enabled", bool(d.enabled), "driver %s" % AudioServer.get_driver_name())
	mv.get_tree().process_frame.connect(_sample)
	_sampling = true
	var rec := AudioEffectRecord.new()
	var rec_ix := -1
	if d.enabled:
		Buses.ensure()
		AudioServer.add_bus_effect(0, rec)
		rec_ix = AudioServer.get_bus_effect_count(0) - 1
		rec.set_recording_active(true)
	var subs: Array = []
	d.subtitle.connect(func(i: Dictionary) -> void: subs.append(i))
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	var c: Vector2i = h._open(w, 7)
	mv.center_camera_on(Vector2(c))
	# 1. planning
	var ok: bool = await pt._wait_until(func(): return d.music_state().mode == "planning" and float(d.music_state().levels.ambient) > 0.8, 12.0)
	pt._log("audio7_planning", ok, _state(d))
	# 2. convoys roll -> tension (normal match)
	d.handle_events([{"type": "ConvoyFormed", "convoy": 1, "owner": int(d.player_fid), "units": []}])
	ok = await pt._wait_until(func(): return d.music_state().mode == "tension", 8.0)
	pt._log("audio7_convoy_tension", ok, _state(d))
	# 3. Last Protocol countdown half used
	d.g7.lp_override = _lp({"frac": 0.55, "cd_left": 1500.0, "phase": 2})
	await pt._wait(4.0)
	var lt: Dictionary = d.music_state()
	pt._log("audio7_lp_tension", lt.mode == "tension" and float(lt.levels.tension) > 0.6, _state(d))
	# 4. real firefight -> combat drums
	var mine: Array = []
	for i in 3:
		mine.append(int(h._unit(w, "mbt", int(d.player_fid), Vector2(c) + Vector2(-3.5, i - 0.5)).id))
		h._unit(w, "mbt", 1 - int(d.player_fid), Vector2(c) + Vector2(3.5, i - 0.5))
	for i in 4:
		h._unit(w, "rifleman", int(d.player_fid), Vector2(c) + Vector2(-2.5, 2.0 + i * 0.5))
		h._unit(w, "rifleman", 1 - int(d.player_fid), Vector2(c) + Vector2(2.5, 2.0 + i * 0.5))
	ok = await pt._wait_until(func(): return d.music_state().mode == "combat" and float(d.music_state().levels.drums) > 0.5, 25.0)
	pt._log("audio7_combat_drums", ok, _state(d))
	await pt._shot("audio7_combat")
	# 5. operator barks, 4 personalities, one at a time (the queue drops lines older than 10 s, by design)
	var r0: int = d.radio_log.size()
	var all_ok := true
	for k in Cat7.PERS.size():
		var n0: int = d.radio_log.size()
		d.handle_events([{"type": "CnBark", "id": 900 + k, "team": 70 + k, "owner": int(d.player_fid), "call_sign": "Op%d" % k,
			"pers": Cat7.PERS[k], "voice": k % 2, "kind": ["wounded", "kill", "buddy_down", "under_fire"][k]}])
		all_ok = all_ok and await pt._wait_until(func(): return d.radio_log.size() > n0, 12.0)
	var n1: int = d.radio_log.size()
	d.handle_events([{"type": "CnBark", "id": 950, "team": 70, "owner": int(d.player_fid), "call_sign": "Hero", "pers": "hardliner",
		"voice": 0, "kind": "hero"}, {"type": "CnBark", "id": 951, "team": 70, "owner": 1 - int(d.player_fid), "call_sign": "Enemy",
		"pers": "joker", "voice": 0, "kind": "kill"}])
	all_ok = all_ok and await pt._wait_until(func(): return d.radio_log.size() > n1, 12.0)
	await pt._wait(3.0)
	var heard: Array = d.radio_log.slice(r0).map(func(r): return "%s(%s)" % [r.line, r.cat])
	var pers_heard := Cat7.PERS.filter(func(pp): return str(heard).contains("b7_" + pp))
	pt._log("audio7_barks_by_personality", all_ok and pers_heard.size() == 4 and not str(heard).contains("joker_kill"), str(heard))
	var op_subs := subs.filter(func(s): return String(s.channel) == "operator")
	pt._log("audio7_bark_subtitles", op_subs.size() >= 5, str(op_subs.map(func(s): return "%s[t%d]: %s" % [s.speaker, int(s.team), s.text])))
	# 6. command ack + PROTOCOL
	var r1: int = d.radio_log.size()
	d.handle_events([{"type": "CommandApplied", "cmd_type": "cn_deploy", "issuer": int(d.player_fid)}])
	var said: bool = d.protocol_say("seed_exposed", "Seed nest exposed at grid D4")
	ok = await pt._wait_until(func(): return d.radio_log.size() >= r1 + 2, 20.0)
	pt._log("audio7_ack_and_protocol", ok and said, str(d.radio_log.slice(r1).map(func(r): return "%s(%s)" % [r.line, r.cat])) +
		" | " + str(subs.slice(-2).map(func(s): return "%s/%s: %s" % [s.channel, s.speaker, s.text])))
	# 7. G7 sound effects at the camera
	var p := Vector2(c)
	mv.center_camera_on(p)
	await pt._wait(0.3)
	pt._log("audio7_camera_on_sfx", d.dist_norm(p) < 0.5, "camera distance of the effects %.2f" % d.dist_norm(p))
	var tgt: int = mine[0]
	var played: Array = []
	for ev in [{"type": "T7Rail", "from": p + Vector2(-2, 0), "to": p + Vector2(6, 0), "owner": 0}, {"type": "T7Emp", "pos": p, "owner": 0},
			{"type": "T7Burn", "pos": p + Vector2(1, 1), "owner": 0}, {"type": "RocketSalvo", "from": p, "to": p + Vector2(5, 2), "id": tgt},
			{"type": "CnDisruptorShot", "from": p, "to": p + Vector2(3, 0), "id": tgt}, {"type": "CoreHit", "pos": p + Vector2(4, 0), "id": 1},
			{"type": "CorePulse", "pos": p + Vector2(4, 0), "id": 1}, {"type": "CoreUprooted", "pos": p + Vector2(4, 0), "ix": 2},
			{"type": "GrowthRisen", "pos": p + Vector2(-3, 3)}, {"type": "FissuresChanged", "tiles": [Vector2i(c) + Vector2i(2, 2)]},
			{"type": "PackhunterSwipe", "id": tgt, "target": tgt, "hit": true}, {"type": "WebSpit", "from": p + Vector2(2, -2), "to": p, "id": 1},
			{"type": "BurrowerErupt", "pos": p + Vector2(-2, -2), "id": 1}, {"type": "CnHeroDetonation", "id": tgt, "team": 70},
			{"type": "ApcEmp", "pos": p, "id": tgt}, {"type": "DroneTaken", "id": 777, "owner": int(d.player_fid)}]:
		played.append_array(d.g7.event(ev))
		await pt._wait(0.35)
	pt._log("audio7_sfx", played.size() >= 12, "%d played: %s; drone feed %d" % [played.size(), str(played), int(d.g7.drone_feed)])
	d.handle_events([{"type": "DroneReleased", "id": 777, "owner": int(d.player_fid)}])
	pt._log("audio7_drone_feed_stops", int(d.g7.drone_feed) == -1, "feed after release %d" % int(d.g7.drone_feed))
	# 8. pre-Tide silence -> the Tide
	d.g7.lp_override = _lp({"frac": 0.9, "cd_left": 545.0, "phase": 3, "weavers": true})
	ok = await pt._wait_until(func(): return d.music_state().mode == "silence", 6.0)
	await pt._wait(1.0)
	var lv: Dictionary = d.music_state().levels
	var sum := 0.0
	for k in lv:
		sum += float(lv[k])
	pt._log("audio7_pre_tide_silence", ok and sum < 0.05, _state(d))
	d.g7.lp_override = _lp({"frac": 0.9, "cd_left": 540.0, "final_stage": true, "tide": true, "phase": 4})
	d.handle_events([{"type": "TheTide", "why": "countdown", "phase": 4, "walker": -1}])
	ok = await pt._wait_until(func(): return d.music_state().mode == "tide" and float(d.music_state().levels.tide) > 0.8, 10.0)
	pt._log("audio7_tide_theme", ok and d.g7.music.stingers.size() >= 1, _state(d) + " stingers %s" % str(d.g7.music.stingers))
	await pt._shot("audio7_tide")
	# 9. PROTOCOL voice muted
	Buses.set_protocol_mode("muted")
	var r2: int = d.radio_log.size()
	var voiced: bool = d.protocol_say("tide", "Mass movement at the outer ring")
	await pt._wait(3.0)
	pt._log("audio7_protocol_muted", not voiced and d.radio_log.slice(r2).all(func(r): return String(r.cat) != "protocol")
		and String(subs.back().text) == "Mass movement at the outer ring", "voiced %s, last subtitle %s" % [voiced, str(subs.back())])
	Buses.set_protocol_mode("on")
	# 10. mixer: no clipping, music log
	_sampling = false
	pt._log("audio7_no_clipping", float(_peak.Master) <= 0.0, "Master peak %.2f dB, Music peak %.2f dB, mixer peaks %s refused %d" % [
		float(_peak.Master), float(_peak.Music), str(d.mixer.peak), int(d.mixer.refused)])
	pt._log("audio7_music_log", d.g7.music.mlog.size() >= 4, str(d.g7.music.mlog))
	if d.enabled:
		var wav: AudioStreamWAV = rec.get_recording()
		rec.set_recording_active(false)
		AudioServer.remove_bus_effect(0, rec_ix)
		var out: String = pt.shot_dir.path_join("audio7_capture.wav")
		var err := wav.save_to_wav(out) if wav != null else ERR_UNAVAILABLE
		pt._log("audio7_wav_capture", err == OK, "%s (%.1f s)" % [out, wav.get_length() if wav != null else 0.0])
	d.g7.lp_override = null
	mv.get_tree().process_frame.disconnect(_sample)
	await _settings(pt)
	pt._log("audio7_summary", true, "radio lines %d, subtitles %d, barks %d, protocol %s" % [d.radio_log.size(), subs.size(),
		d.g7.bark_log.size(), str(d.g7.protocol_log)])


func _settings(pt) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	pt._mv().get_tree().root.add_child(layer)
	var tab: Control = AudioTab.build()
	var panel := PanelContainer.new()
	panel.position = Vector2(200, 150)
	panel.add_child(tab)
	layer.add_child(panel)
	await pt._wait(0.4)
	var vs: HSlider = tab.get_node("OptVolVoice")
	vs.value = 60.0
	await pt._wait(0.2)
	var vdb := AudioServer.get_bus_volume_db(Buses.bus_index("Voice"))
	pt._log("audio7_settings_voice_protocol", tab.get_node_or_null("OptProtocolVoice") != null and absf(vdb - linear_to_db(0.6)) < 0.05,
		"Voice bus %.1f dB, PROTOCOL toggle present" % vdb)
	await pt._shot("audio7_settings")
	vs.value = 90.0
	layer.queue_free()
	await pt._wait(0.2)
