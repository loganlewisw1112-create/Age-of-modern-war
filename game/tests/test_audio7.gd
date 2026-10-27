extends "res://tests/test_base.gd"
## G7 AUDIO7 acceptance: adaptive music layer selection (planning / tension / combat / Tide / pre-Tide silence) and
## smooth crossfades; operator barks by personality + throttling; PROTOCOL voice mute; command acks + subtitles;
## every G7 event maps to a sound / line that exists (and the event names are real sim events); no clipping, voice
## ducks music; sim hash unchanged with audio on/off. Runs headless (Dummy driver: logic only, no players).

const Cat = preload("res://presentation/audio/audio_catalog.gd")
const Cat7 = preload("res://presentation/audio/audio_catalog7.gd")
const Music = preload("res://presentation/audio/music_director.gd")
const Buses = preload("res://presentation/audio/audio_buses.gd")
const Director = preload("res://presentation/audio/audio_director.gd")
const AudioTab = preload("res://presentation/audio/audio_tab.gd")
const Settings = preload("res://presentation/menu/settings.gd")
const ViewUtil = preload("res://presentation/view/view_util.gd")

const LP_BASE := {"cd_left": 3000.0, "cd_total": 3600.0, "cd_rate": 1.0, "final_stage": false, "phase": 0, "frac": 0.05,
	"tide": false, "weavers": false}


class FakeView extends RefCounted:
	var world = null
	var player_fid := 0

	func world_readable() -> bool:
		return world != null

	func cell_visible(_c: Vector2i) -> bool:
		return true


func _director(fid: int = 0, mv = null) -> Node2D:
	var d: Node2D = Director.new()
	d.setup(mv)
	d.player_fid = fid
	d.listener_override = [ViewUtil.iso(Vector2(32, 32)), Vector2(960, 540)]
	d.vis_override = func(_c: Vector2i) -> bool: return true
	return d


func _lp(over: Dictionary) -> Dictionary:
	var l := LP_BASE.duplicate()
	l.merge(over, true)
	return l


func test_music_layer_selection() -> void:
	var s: Dictionary = Music.select({})
	check_eq(s.mode, "planning", "normal match, nothing happening = planning")
	check(float(s.levels.ambient) > 0.9 and float(s.levels.drums) == 0.0, "calm ambient only (%s)" % [s.levels])
	s = Music.select({"lp": _lp({})})
	check_eq(s.mode, "planning", "Last Protocol early = planning")
	var t1: Dictionary = Music.select({"lp": _lp({"frac": 0.5, "cd_left": 1800.0, "phase": 1})})
	check_eq(t1.mode, "tension", "countdown half used = tension")
	var t2: Dictionary = Music.select({"lp": _lp({"frac": 0.8, "cd_left": 700.0, "phase": 2, "weavers": true})})
	check(float(t2.levels.tension) >= float(t1.levels.tension) and float(t2.levels.pulse) > float(t1.levels.pulse),
		"tension layers rise as the countdown advances (%s -> %s)" % [t1.levels, t2.levels])
	var cv: Dictionary = Music.select({"convoy": true})
	check_eq(cv.mode, "tension", "convoys rolling = tension, normal match too")
	check_eq(Music.select({"contact": true}).mode, "tension", "recent contact = tension")
	var c: Dictionary = Music.select({"combat": 0.8})
	check_eq(c.mode, "combat", "firefight = combat")
	check(float(c.levels.drums) > 0.9 and float(c.levels.ambient) < 0.5, "combat drums up, ambient down (%s)" % [c.levels])
	var td: Dictionary = Music.select({"tide": true, "combat": 1.0})
	check_eq(td.mode, "tide", "Tide theme")
	check(float(td.levels.tide) == 1.0 and float(td.levels.drums) == 0.0 and float(td.levels.ambient) == 0.0, "Tide theme alone")
	var sl: Dictionary = Music.select({"silence": true, "combat": 1.0, "lp": _lp({"final_stage": true})})
	check_eq(sl.mode, "silence", "silence window beats everything")
	var sum := 0.0
	for k in sl.levels:
		sum += float(sl.levels[k])
	check_eq(sum, 0.0, "silence = every layer at 0")


func test_pre_tide_silence_countdown_and_walker() -> void:
	# countdown trigger: final stage at 15% of 3600 s = 540 s left; cd_rate 1 -> eta = cd_left - 540
	var m = Music.new()
	var now := 0.0
	m.update(now, 0.25, {"lp": _lp({"frac": 0.85, "cd_left": 560.0, "phase": 3})})
	check(m.mode != "silence", "20 s before the final stage: still playing (%s)" % m.mode)
	now = 15.0
	m.update(now, 0.25, {"lp": _lp({"frac": 0.86, "cd_left": 545.0, "phase": 3})})
	check_eq(m.mode, "silence", "5 s before the Tide: sudden silence")
	var lv := 0.0
	for i in 4:
		now += 0.25
		m.update(now, 0.25, {"lp": _lp({"frac": 0.86, "cd_left": 545.0 - i, "phase": 3}), "combat": 1.0})
	for k in m.levels:
		lv += float(m.levels[k])
	check(lv < 0.05, "silence is sudden: every layer near 0 within 1 s (%.3f)" % lv)
	now += 1.0
	m.on_tide(now)
	m.update(now, 0.25, {"lp": _lp({"final_stage": true, "tide": true, "cd_left": 540.0})})
	check(m.tide_hit, "TheTide after >= MIN_SILENCE_S of silence: the theme hits now")
	check_eq(m.mode, "tide", "Tide theme mode")
	check(m.stingers.size() == 1 and String(m.stingers[0].id) == "sting_tide", "Tide stinger (%s)" % [m.stingers])
	var prev := float(m.levels.tide)
	now += 0.25
	m.update(now, 0.25, {"lp": _lp({"tide": true})})
	check(float(m.levels.tide) > prev and float(m.levels.tide) - prev <= Music.RATE.tide * 0.25 + 0.001,
		"Tide theme fades in smoothly (%.3f -> %.3f)" % [prev, float(m.levels.tide)])
	# walking-core trigger: no warning in the sim -> TheTide opens a TIDE_SILENCE_S window, then the hit
	var w = Music.new()
	w.update(0.0, 0.25, {"lp": _lp({"frac": 0.6, "cd_left": 1500.0}), "combat": 0.9})
	w.on_tide(1.0)
	w.update(1.0, 0.25, {"lp": _lp({"tide": true})})
	check(w.mode == "silence" and not w.tide_hit, "walker Tide: silence first (%s)" % w.mode)
	w.update(1.0 + Music.TIDE_SILENCE_S - 0.5, 0.25, {"lp": _lp({"tide": true})})
	check(not w.tide_hit, "still silent inside the window")
	w.update(1.0 + Music.TIDE_SILENCE_S + 0.01, 0.25, {"lp": _lp({"tide": true})})
	check(w.tide_hit and w.mode == "tide", "then the Tide theme hits")
	# smooth crossfades in normal play: no step bigger than the rate allows
	var n = Music.new()
	var t := 0.0
	var worst := 0.0
	for i in 80:
		var before: Dictionary = n.levels.duplicate()
		t += 0.25
		n.update(t, 0.25, {"combat": 1.0 if i > 20 and i < 50 else 0.0, "convoy": i > 10})
		for k in n.levels:
			worst = maxf(worst, absf(float(n.levels[k]) - float(before[k])))
	check(worst <= Music.RATE.combat_in * 0.25 + 0.001, "crossfades never jump (max step %.3f)" % worst)
	check(n.mlog.size() >= 3, "mode changes logged (%s)" % [n.mlog])


func test_bark_selection_by_personality() -> void:
	var texts := {}
	for p in Cat7.PERS:
		for k in Cat7.BARK_KINDS:
			for v in 2:
				var id := Cat7.bark_line(p, k, v, 0)
				check(id != "" and id.contains(p) and id.ends_with("_v%d" % v), "bark %s/%s/v%d -> %s" % [p, k, v, id])
				check(Cat.radio_path(id) != "", "bark file exists: %s" % id)
		texts[p] = Cat7.text_of(Cat7.bark_line(p, "wounded", 0, 0))
	check_eq(texts.size(), 4, "4 personalities")
	var uniq := {}
	for p in texts:
		uniq[texts[p]] = true
	check_eq(uniq.size(), 4, "each personality has its own wounded line (%s)" % [texts])
	check(Cat7.bark_line("calm_veteran", "kill", 0, 0) != Cat7.bark_line("calm_veteran", "kill", 0, 1), "n rotates the texts")
	check_eq(Cat7.bark_line("unknown_pers", "kill", 0, 0).begins_with("b7_calm_veteran"), true, "unknown personality falls back")
	check_eq(Cat7.bark_line("joker", "no_such_kind", 0, 0), "", "unknown kind = no line")


func test_bark_throttling_one_voice_at_a_time() -> void:
	var d = _director(0)
	var evs: Array = []
	for i in 12:
		evs.append({"type": "CnBark", "id": 100 + i, "team": 1, "owner": 0, "call_sign": "Hawk", "pers": "joker", "voice": 1,
			"kind": "kill"})
	evs.append({"type": "CnBark", "id": 300, "team": 1, "owner": 1, "call_sign": "X", "pers": "hardliner", "voice": 0, "kind": "kill"})
	d.handle_events(evs)
	check_eq(d.g7.bark_log.size(), 1, "12 kill barks of one team in one frame -> one queued (%d)" % d.g7.bark_log.size())
	check(String(d.g7.bark_log[0].line).begins_with("b7_joker_kill_") and String(d.g7.bark_log[0].line).ends_with("_v1"),
		"joker voice 1 line (%s)" % [d.g7.bark_log[0]])
	d.handle_events([{"type": "CnBark", "id": 101, "team": 1, "owner": 0, "call_sign": "Hawk", "pers": "joker", "voice": 1,
		"kind": "hero"}, {"type": "CnBark", "id": 201, "team": 2, "owner": 0, "call_sign": "Moth", "pers": "nervous_rookie",
		"voice": 0, "kind": "wounded"}])
	check_eq(d.g7.bark_log.size(), 3, "hero bypasses the team gap; another team may speak")
	var started := 0
	var overlaps := 0
	var busy_until := 0.0
	for i in 400:
		var before: int = d.radio_log.size()
		d.tick(0.05)
		if d.radio_log.size() > before:
			started += 1
			if d.now() < busy_until:
				overlaps += 1
			busy_until = d.now() + Cat.duration(Cat.radio_path(String(d.radio_log.back().line)))
	check_eq(started, 3, "all three play, one after another")
	check_eq(overlaps, 0, "never two voices at once")
	check_eq(String(d.radio_log[0].cat), "bark_hero", "hero detonation line first (priority)")
	for i in 3:
		d.handle_events([{"type": "CnBark", "id": 100, "team": 1, "owner": 0, "pers": "joker", "voice": 1, "kind": "kill"}])
		d.tick(1.0)
	check(d.g7.bark_log.size() <= 4, "kill cooldown + team gap throttle repeats (%d)" % d.g7.bark_log.size())
	d.free()


func test_under_fire_bark_from_shots_at_operators() -> void:
	var w := make_world()
	var op_id := -1
	for id in w.entities:
		if int(w.entities[id].owner) == 0 and String(w.entities[id].kind) == "unit":
			op_id = int(id)
			break
	check(op_id >= 0, "a player unit to stand in for an operator")
	w.sys_state["cnprog7"] = {"ops": {str(op_id): {"id": op_id, "team": 4, "pers": "nervous_rookie", "voice": 1, "cs": "Moth"}}}
	var mv := FakeView.new()
	mv.world = w
	var d = _director(0, mv)
	d.mv = mv
	var shot := {"type": "ShotFired", "weapon": "rifle", "target": op_id, "from": Vector2(30, 30), "to": Vector2(31, 30), "hit": false}
	d.handle_events([shot, shot, shot])
	check_eq(d.g7.bark_log.size(), 1, "shots at a named operator -> one under-fire bark (%s)" % [d.g7.bark_log])
	check(String(d.g7.bark_log[0].line).begins_with("b7_nervous_rookie_under_fire_") and String(d.g7.bark_log[0].line).ends_with("_v1"),
		"in the operator's personality + voice")
	d.tick(5.0)
	d.handle_events([shot])
	check_eq(d.g7.bark_log.size(), 1, "per-team under-fire gap (%.0f s)" % d.g7.UNDER_FIRE_GAP_S)
	w.sys_state.erase("cnprog7")
	d.free()


func test_protocol_voice_mute_and_subtitles() -> void:
	var tmp := "user://_test_audio7_settings.cfg"
	Settings.use_path(tmp)
	var d = _director(0)
	var subs: Array = []
	d.subtitle.connect(func(i: Dictionary) -> void: subs.append(i))
	check(d.protocol_say("seed_exposed", "Seed nest exposed at grid D4"), "PROTOCOL voiced by default")
	for i in 20:
		d.tick(0.1)
	check(subs.size() == 1 and String(subs[0].channel) == "protocol" and bool(subs[0].voiced), "subtitle on start (%s)" % [subs])
	check_eq(String(subs[0].text), "Seed nest exposed at grid D4", "subtitle carries the advisor's full text")
	check_eq(String(subs[0].speaker), "PROTOCOL", "speaker")
	var tab: Control = AudioTab.build()
	var pv: CheckButton = tab.get_node("OptProtocolVoice")
	pv.button_pressed = false
	pv.toggled.emit(false)
	check_eq(Buses.protocol_mode(), "muted", "Audio tab toggle stores protocol.advisor = muted (OPSUI7's key)")
	var n0: int = d.radio_log.size()
	check(not d.protocol_say("core_plating", "Core 2 plating at 60%"), "muted: not voiced")
	for i in 40:
		d.tick(0.1)
	check_eq(d.radio_log.size(), n0, "muted: nothing played")
	check(String(subs.back().text) == "Core 2 plating at 60%" and not bool(subs.back().voiced), "muted: subtitle still emitted")
	check_eq(d.recent_subtitles(1)[0].text, "Core 2 plating at 60%", "recent_subtitles pull API")
	check(d.protocol_say("no_such_key", "x") == false, "still muted for unknown keys")
	var vs: HSlider = tab.get_node("OptVolVoice")
	vs.value = 50.0
	vs.value_changed.emit(50.0)
	check(absf(AudioServer.get_bus_volume_db(Buses.bus_index("Voice")) - linear_to_db(0.5)) < 0.01, "Voice bus slider")
	Buses.set_protocol_mode("on")
	for i in 70:
		d.tick(0.1)   # past the protocol category cooldown
	check(d.protocol_say("no_such_key", "x"), "unknown key -> generic line, voiced again")
	# OPSUI7's advisor card: advisory(line) -> voiced when line.voice, mapped key, full text as subtitle
	var adv := FakeAdvisor.new()
	d.g7.hook_advisor(adv)
	for i in 70:
		d.tick(0.1)
	var n1: int = d.radio_log.size()
	adv.advisory.emit({"key": "nest:D4", "kind": "opportunity", "text": "Seed nest exposed at grid D4.", "pos": Vector2.ZERO, "tick": 1, "voice": true})
	for i in 20:
		d.tick(0.1)
	check(d.radio_log.size() == n1 + 1 and String(d.radio_log.back().line) == "p7_seed_exposed", "advisor line voiced (%s)" % [d.radio_log.back()])
	check_eq(String(subs.back().text), "Seed nest exposed at grid D4.", "advisor full text subtitled")
	adv.advisory.emit({"key": "inc:3", "kind": "danger", "text": "Machine forces closing", "voice": false})
	for i in 70:
		d.tick(0.1)
	check_eq(d.radio_log.size(), n1 + 1, "advisor muted on the card (voice false) -> silent")
	tab.free()
	d.free()
	Settings.use_path(Settings.DEFAULT_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


class FakeAdvisor extends RefCounted:
	signal advisory(line: Dictionary)


func test_command_acks_hq_and_enemy_silence() -> void:
	var d = _director(0)
	var subs: Array = []
	d.subtitle.connect(func(i: Dictionary) -> void: subs.append(i))
	d.handle_events([{"type": "CommandApplied", "cmd_type": "cn_deploy", "issuer": 0},
		{"type": "CommandApplied", "cmd_type": "cn_move", "issuer": 1},
		{"type": "CnTeamLost", "team": 3, "owner": 1}])
	for i in 60:
		d.tick(0.1)
	check_eq(d.radio_log.size(), 1, "own counter-nanite order acked, enemy order and enemy team loss silent (%s)" % [d.radio_log])
	check(String(subs[0].channel) == "command" and String(subs[0].text).contains("charge"), "command voice subtitle (%s)" % [subs])
	d.handle_events([{"type": "TheTide", "why": "walker", "phase": 4, "walker": 5}])
	for i in 60:
		d.tick(0.1)
	check(String(d.radio_log.back().cat) == "lp_hq" and String(subs.back().text).contains("Tide"), "HQ Tide call (%s)" % [d.radio_log])
	d.free()


func _sim_text() -> String:
	var out := ""
	for dir in ["res://sim/systems/", "res://sim/ai/"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				out += FileAccess.get_file_as_string(dir + f)
	return out


func test_every_g7_event_maps_to_a_sound_that_exists() -> void:
	var src := _sim_text()
	for t in Cat7.SFX:
		check(src.contains("emit(\"%s\"" % t), "SFX event is a real sim event: %s" % t)
		for s in Cat7.event_sfx({"type": t, "on": true}):
			check(Cat.has_sound(String(s.id)), "%s -> %s exists" % [t, s.id])
	for t in Cat7.HQ:
		check(src.contains("emit(\"%s\"" % t), "HQ event is a real sim event: %s" % t)
		var ln := Cat7.line_for("lp_hq", String(Cat7.HQ[t]))
		check(ln != "" and Cat7.text_of(ln) != "" and Cat.radio_path(ln) != "", "HQ %s -> %s" % [t, ln])
	for c in Cat7.ACK:
		var ln := Cat7.line_for("cn_ack", String(Cat7.ACK[c]))
		check(Cat.radio_path(ln) != "", "ack %s -> %s" % [c, ln])
	for k in Cat7.PROTOCOL_KEYS:
		var ln := Cat7.line_for("protocol", k)
		check(ln == "p7_" + k and Cat.radio_path(ln) != "", "PROTOCOL %s -> %s" % [k, ln])
	for s in Cat7.STEMS + ["sting_tide", "sting_core"]:
		check(Cat7.music_path(s) != "" and ResourceLoader.exists(Cat7.music_path(s)), "music stem %s" % s)
	for wid in Cat.G7_SHOT:
		check(Content.weapon(String(wid)) != null and not (Content.weapon(String(wid)) as Dictionary).is_empty(), "G7 weapon exists: %s" % wid)
		check(Cat.has_sound(Cat.shot_sound(String(wid))), "%s -> %s exists" % [wid, Cat.shot_sound(String(wid))])
	for sid in ["engine_dropship", "engine_drone", "ui_drone_feed"]:
		check(Cat.has_sound(sid), "loop %s exists" % sid)
	for sid in Cat.sound_ids():
		check(Cat.CATEGORY.keys().any(func(p): return sid.begins_with(String(p))), "%s has a mixer category" % sid)
		check(Cat.category(sid) == "ui" or Cat.category(sid) in ["gun", "impact", "explosion", "engine", "alert", "radio", "creep", "threat", "core"] , "known category %s" % sid)


func test_positional_and_culled() -> void:
	var d = _director(0)
	d.listener_override = [Vector2.ZERO, Vector2(100, 100)]
	var near: Array = d.g7.event({"type": "T7Rail", "from": Vector2(0, 0), "to": Vector2(3, 0), "owner": 0})
	check_eq(near, ["shot_rail"], "rail cannon near")
	var far: Array = d.g7.event({"type": "T7Rail", "from": Vector2(12, 0), "to": Vector2(20, 0), "owner": 0})
	check_eq(far, ["explosion_far"], "rail cannon far = distant boom")
	check_eq(d.g7.event({"type": "PackhunterSwipe", "id": 9, "target": 3, "hit": true}), [], "no entity position -> nothing")
	check_eq(d.g7.event({"type": "WebSpit", "from": Vector2(12, 0), "to": Vector2(13, 0), "kind": "x", "id": 1, "target": 2}), [],
		"far Weaver spit is silent")
	check_eq(d.g7.event({"type": "DroneLowBattery", "id": 4, "owner": 1}), [], "enemy drone alerts never heard")
	check_eq(d.g7.event({"type": "DroneLowBattery", "id": 4, "owner": 0}), ["alert_lowbat"], "own drone alert")
	check(AudioG7Skip.call({"type": "ShotFired", "t7": "rail"}) and not AudioG7Skip.call({"type": "ShotFired", "t7": "gun"}),
		"turret special shots defer to their T7 event")
	d.free()


var AudioG7Skip := func(ev: Dictionary) -> bool: return preload("res://presentation/audio/audio_g7.gd").skip_shot(ev)


func test_no_clipping_and_voice_ducks_music() -> void:
	var t := FileAccess.get_file_as_string("res://assets/generated/audio7/audio7_manifest.json")
	var m: Dictionary = JSON.parse_string(t)
	check(m.peak.size() >= 240, "G7 manifest lists peaks (%d files)" % m.peak.size())
	var worst := 0.0
	for p in m.peak:
		worst = maxf(worst, float(m.peak[p]))
	check(worst <= 0.98, "no generated G7 file clips (max peak %.3f)" % worst)
	var silent := 0
	for p in m.rms:
		if float(m.rms[p]) < 0.005:
			silent += 1
	check_eq(silent, 0, "no silent file")
	var tmp := "user://_test_audio7_duck.cfg"
	Settings.use_path(tmp)
	Buses.apply()
	Buses.set_duck(0.0)
	var base := AudioServer.get_bus_volume_db(Buses.bus_index("Music"))
	Buses.set_duck(1.0)
	check(absf(AudioServer.get_bus_volume_db(Buses.bus_index("Music")) - (base + Buses.MUSIC_DUCK_DB)) < 0.01, "voice ducks the music bus")
	Buses.set_duck(0.0)
	var bb := AudioServer.get_bus_volume_db(Buses.bus_index("Battle"))
	Buses.set_hush(1.0)
	check(absf(AudioServer.get_bus_volume_db(Buses.bus_index("Battle")) - (bb + Buses.HUSH_DB)) < 0.01, "pre-Tide silence hushes the battle")
	Buses.set_hush(0.0)
	Settings.use_path(Settings.DEFAULT_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


func test_sim_hash_unchanged_audio_on_off() -> void:
	var a := make_world()
	var b := make_world()
	var mv := FakeView.new()
	mv.world = b
	var d = _director(0, mv)
	d.mv = mv
	var g7evs: Array = [{"type": "CnBark", "id": 1, "team": 1, "owner": 0, "pers": "joker", "voice": 0, "kind": "kill"},
		{"type": "TheTide", "why": "walker"}, {"type": "CoreHit", "pos": Vector2(30, 30), "id": 1}, {"type": "DroneTaken", "id": 5, "owner": 0},
		{"type": "CommandApplied", "cmd_type": "cn_move", "issuer": 0}]
	for i in 120:
		a.step()
		b.step()
		d.handle_events(b.events)
		if i % 30 == 0:
			d.handle_events(g7evs)
			d.protocol_say("tide", "Tide")
		d.tick(0.05)
	check_eq(a.state_hash(), b.state_hash(), "G7 audio (music, barks, PROTOCOL, sfx) never changes the sim")
	check(d.g7.music.mlog.size() >= 1 and d.g7.subtitles.size() >= 1, "and it did run (%s / %d subtitles)" % [d.g7.music.mode, d.g7.subtitles.size()])
	d.free()
