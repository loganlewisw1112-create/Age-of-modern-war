extends "res://tests/test_base.gd"
## G6.1 AUDIO61 acceptance: sound ids on disk, variant rotation, voice limits under a 2k-unit firefight, radio
## priority + one-at-a-time, CHAIN61 report -> radio line, enemy radio never heard, per-bus volume settings,
## headless creates no players, far/fog swap, sim hash untouched. Runs headless (Dummy driver).

const Cat = preload("res://presentation/audio/audio_catalog.gd")
const Mixer = preload("res://presentation/audio/audio_mixer.gd")
const RadioQueue = preload("res://presentation/audio/radio_queue.gd")
const Buses = preload("res://presentation/audio/audio_buses.gd")
const Director = preload("res://presentation/audio/audio_director.gd")
const AudioTab = preload("res://presentation/audio/audio_tab.gd")
const Settings = preload("res://presentation/menu/settings.gd")
const CommandNet = preload("res://sim/systems/command_net.gd")
const ViewUtil = preload("res://presentation/view/view_util.gd")


func _director(fid: int = 0) -> Node2D:
	var d: Node2D = Director.new()
	d.setup(null)
	d.player_fid = fid
	d.listener_override = [ViewUtil.iso(Vector2(32, 32)), Vector2(960, 540)]
	d.vis_override = func(_c: Vector2i) -> bool: return true
	return d


func _weapon_ids() -> Array:
	var out: Array = []
	Content.weapon("rifle")
	for k in Content._data.get("weapons", {}):
		var d = Content.weapon(String(k))
		if typeof(d) == TYPE_DICTIONARY and d.has("class"):
			out.append(String(k))
	out.sort()
	return out


func _first_unit(w: SimWorld, fid: int) -> int:
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e = w.entities[id]
		if e.kind == "unit" and int(e.owner) == fid:
			return int(id)
	return -1


func test_every_event_maps_to_a_sound_on_disk() -> void:
	check(Cat.sound_ids().size() >= 30, "manifest lists the generated sound ids (%d)" % Cat.sound_ids().size())
	for id in Cat.sound_ids():
		for p in Cat.variants(String(id)):
			check(FileAccess.file_exists(String(p)), "file on disk: %s" % p)
	var wids := _weapon_ids()
	check(wids.size() > 50, "weapon table read (%d)" % wids.size())
	for wid in wids:
		var s := Cat.shot_sound(wid)
		check(s == "" or Cat.has_sound(s), "weapon %s -> shot %s exists" % [wid, s])
		var im := Cat.impact_sound(wid)
		check(im == "" or Cat.has_sound(im), "weapon %s -> impact %s exists" % [wid, im])
		if s != "" and Cat.far_of(s) != "":
			check(Cat.has_sound(Cat.far_of(s)), "far variant of %s exists" % s)
	check_eq(Cat.shot_sound("rifle"), "shot_rifle", "rifle")
	check_eq(Cat.shot_sound("tank_cannon"), "shot_cannon", "tank cannon")
	check_eq(Cat.shot_sound("howitzer"), "shot_artillery", "howitzer")
	check_eq(Cat.shot_sound("laser_mg"), "shot_energy", "Machine laser = energy")
	for id in ["explosion_near", "alert_ready", "alert_build", "alert_attack", "ui_click", "radio_squelch_in",
			"engine_tank", "engine_truck", "engine_jet", "engine_heli", "engine_ship", "foot_step"]:
		check(Cat.has_sound(id), "event sound %s exists" % id)
	check_eq(Cat.death_sound({"kind": "building", "def": "x"}), "explosion_near", "building death explodes")
	for uid in Content._data.get("units", {}):
		var es := Cat.engine_sound(String(uid))
		check(es == "" or Cat.has_sound(es), "unit %s engine %s exists" % [uid, es])
	var cats: Dictionary = Cat.lib().get("categories", {})
	check(cats.size() >= 20, "radio categories (%d)" % cats.size())
	for c in cats:
		check(Cat.pick_line(String(c), "human", [], 0) != "", "human radio line for %s" % c)
		check(Cat.pick_line(String(c), "machine", [], 0) != "", "machine (or fallback) radio line for %s" % c)
	for ln in Cat.lib().get("lines", []):
		check(FileAccess.file_exists(Cat.radio_path(String(ln.id))), "radio file for %s" % ln.id)


func test_variants_rotate() -> void:
	var m = Mixer.new()
	var n := Cat.variants("shot_rifle").size()
	check(n >= 3, "rifle has several variants (%d)" % n)
	var seen := {}
	var last := -1
	for i in n * 3:
		var v: int = m.next_variant("shot_rifle", n)
		check(v != last, "no immediate repeat")
		last = v
		seen[v] = true
	check_eq(seen.size(), n, "every variant used")
	var d = _director()
	var a = d.play_at("shot_rifle", Vector2(32, 32))
	var played: Array = []
	for i in 4:
		d.tick(1.0)
		played.append(d.mixer._rot.get("shot_rifle"))
		d.play_at("shot_rifle", Vector2(32, 32))
	check_eq(a, "shot_rifle", "near rifle plays")
	check(played[0] != played[1], "director rotates variants (%s)" % [played])
	d.free()


func test_voice_limits_2k_firefight() -> void:
	var d = _director()
	var wids := _weapon_ids()
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var max_seen := {}
	for frame in 30:
		var evs: Array = []
		for i in 2000:
			var p := Vector2(32 + rng.randf_range(-6, 6), 32 + rng.randf_range(-6, 6))
			evs.append({"type": "ShotFired", "shooter": i, "target": i + 1, "weapon": wids[rng.randi() % wids.size()],
				"hit": rng.randf() < 0.5, "from": p, "to": p + Vector2(2, 1), "indirect": false})
		if frame % 5 == 0:
			for i in 100:
				evs.append({"type": "EntityDestroyed", "id": i, "kind": "building", "def": "x", "owner": 1, "pos": Vector2(33, 33)})
		d.handle_events(evs)
		for c in Mixer.MAX:
			max_seen[c] = maxi(int(max_seen.get(c, 0)), d.mixer.active(String(c), d.now()))
		check(d.mixer.total(d.now()) <= Mixer.GLOBAL_MAX, "global cap holds")
		d.tick(1.0 / 60.0)
	for c in Mixer.MAX:
		check(int(d.mixer.peak.get(c, 0)) <= int(Mixer.MAX[c]), "category %s peak %d <= %d" % [c, int(d.mixer.peak.get(c, 0)), int(Mixer.MAX[c])])
	check(int(d.counts.get("shot_rifle", 0)) + int(d.counts.get("shot_mg", 0)) > 0, "the firefight is audible")
	check(d.mixer.started < 3000, "a few voices out of ~60k shots (%d started)" % d.mixer.started)
	var t0 := Time.get_ticks_usec()
	var burst: Array = []
	for i in 2000:
		burst.append({"type": "ShotFired", "weapon": "rifle", "hit": true, "from": Vector2(32, 32), "to": Vector2(33, 32)})
	d.handle_events(burst)
	var us := Time.get_ticks_usec() - t0
	check(us < 40000, "2000 shots in one frame handled in %d us" % us)
	check_eq(d.players_created, 0, "headless: no players even under load")
	d.free()


func test_radio_priority_one_at_a_time() -> void:
	var q = RadioQueue.new()
	var dur := func(_l: String) -> float: return 2.0
	q.push("ack_0", "ack", 45, 0.0)
	q.push("contact_0", "contact", 80, 0.0)
	q.push("officer_down_0", "officer_down", 100, 0.0)
	check(not q.push("ack_1", "ack", 45, 0.0), "one pending line per category")
	check_eq(String(q.poll(0.0, dur).get("cat", "")), "officer_down", "officer down first")
	check(q.poll(0.5, dur).is_empty(), "one line at a time (still transmitting)")
	check(q.busy(1.9), "busy during the line")
	check_eq(String(q.poll(2.4, dur).get("cat", "")), "contact", "contact second")
	check_eq(String(q.poll(4.8, dur).get("cat", "")), "ack", "orders last")
	q.push("ack_2", "ack", 45, 5.0, 8.0)
	check(not q.push("ack_3", "ack", 45, 20.0, 30.0), "category cooldown")
	q.push("moving_0", "moving", 40, 30.0)
	check(q.poll(41.0, dur).is_empty(), "a line queued 11 s ago is stale and dropped")
	var d = _director()
	d.queue_radio("ack")
	d.queue_radio("contact", ["armor", "NE"])
	d.queue_radio("officer_down")
	for i in 400:
		d.tick(0.05)
	var order: Array = d.radio_log.map(func(r): return String(r.cat))
	check_eq(order, ["officer_down", "contact", "ack"], "director plays by priority, one at a time")
	for i in d.radio_log.size() - 1:
		var a: Dictionary = d.radio_log[i]
		var gap := float(d.radio_log[i + 1].at) - float(a.at)
		check(gap >= Cat.duration(Cat.radio_path(String(a.line))) - 0.06, "no overlap between radio lines (%.2f)" % gap)
	check(String(d.radio_log[1].line).begins_with("contact_"), "contact line chosen")
	d.free()


func test_chain61_report_plays_matching_line() -> void:
	var w := make_world()
	var uid := _first_unit(w, 0)
	check(uid >= 0, "side 0 has a unit")
	w.events.clear()
	var rid := CommandNet.report(w, 0, uid, "contact", "Alpha: contact, 3 enemy (2 armor), 9 tiles NE", {"count": 3, "armor": 2})
	check(rid > 0, "CommandNet.report accepted")
	var evs: Array = w.events.filter(func(e): return String(e.type) == "ReportSent")
	check_eq(evs.size(), 1, "ReportSent emitted")
	var d = _director(0)
	d.handle_events(evs)
	d.tick(0.05)
	check_eq(d.radio_log.size(), 1, "one radio line")
	if not d.radio_log.is_empty():
		var line := String(d.radio_log[0].line)
		check_eq(String(d.radio_log[0].cat), "contact", "contact report -> contact line")
		var ln: Dictionary = {}
		for l in Cat.lib().lines:
			if String(l.id) == line:
				ln = l
		check(ln.get("tags", []).has("armor") and ln.get("tags", []).has("NE"), "armour NE line picked (%s: %s)" % [line, ln.get("text", "")])
	var map := {"casualty": "casualty", "ammo": "ammo", "objective": "objective"}
	for k in map:
		check_eq(String(Cat.radio_for_event({"type": "ReportSent", "fid": 0, "kind": k, "text": "x"}, 0).get("cat", "")), map[k], "report kind %s" % k)
	check_eq(String(Cat.radio_for_event({"type": "ReportSent", "fid": 0, "kind": "request", "text": "A requests resupply"}, 0).get("cat", "")), "ammo", "resupply request")
	check_eq(String(Cat.radio_for_event({"type": "OrderDelivered", "fid": 0, "order": {"order": {"type": "attack"}}}, 0).get("cat", "")), "ack", "order delivered -> ack")
	check_eq(String(Cat.radio_for_event({"type": "Succession", "fid": 0, "node": "c:1"}, 0).get("cat", "")), "officer_down", "succession -> officer down")
	check(Cat.radio_for_event({"type": "CommandApplied", "issuer": 0, "command_id": 3}, 0).is_empty(), "a CommandApplied without cmd_type is not voiced")
	# G6.1 (INTEG61-2): world.gd CommandApplied now carries cmd_type (CR seq 406): the player's own orders get radio acks
	check_eq(String(Cat.radio_for_event({"type": "CommandApplied", "issuer": 0, "command_id": 4, "cmd_type": "move"}, 0).get("cat", "")), "moving", "player move order -> moving ack")
	check_eq(String(Cat.radio_for_event({"type": "CommandApplied", "issuer": 0, "command_id": 5, "cmd_type": "hold"}, 0).get("cat", "")), "holding", "player hold order -> holding ack")
	check_eq(String(Cat.radio_for_event({"type": "CommandApplied", "issuer": 0, "command_id": 6, "cmd_type": "attack"}, 0).get("cat", "")), "ack", "player attack order -> ack")
	check(Cat.radio_for_event({"type": "CommandApplied", "issuer": 1, "command_id": 7, "cmd_type": "move"}, 0).is_empty(), "the enemy's orders are never voiced to the player")
	d.free()


func test_enemy_radio_never_heard() -> void:
	var w := make_world()
	var eid := _first_unit(w, 1)
	w.events.clear()
	if eid >= 0:
		CommandNet.report(w, 1, eid, "contact", "Enemy: contact, 4 enemy, 5 tiles S", {})
	var d = _director(0)
	var evs: Array = w.events.duplicate()
	evs.append_array([{"type": "ReportSent", "fid": 1, "kind": "casualty", "text": "x"},
		{"type": "OrderDelivered", "fid": 1, "order": {}}, {"type": "Succession", "fid": 1, "node": "c:2"},
		{"type": "ProductionCompleted", "owner": 1, "building_id": 1}, {"type": "UnitBroken", "owner": 1, "id": 3},
		{"type": "WaveIncoming", "owner": 0, "index": 1}])
	d.handle_events(evs)
	for i in 100:
		d.tick(0.1)
	check_eq(d.radio_log.size(), 0, "no enemy radio heard (%s)" % [d.radio_log])
	check_eq(d.radio.size(), 0, "nothing queued")
	d.free()


func test_volume_settings_per_bus() -> void:
	var tmp := "user://_test_audio61_settings.cfg"
	Settings.use_path(tmp)
	Buses.set_duck(0.0)
	Buses.set_setting("radio", 0.5)
	Buses.set_setting("battle", 0.25)
	Buses.set_setting("ui", 0.0)
	check(absf(AudioServer.get_bus_volume_db(Buses.bus_index("Radio")) - linear_to_db(0.5)) < 0.01, "radio bus volume")
	check(absf(AudioServer.get_bus_volume_db(Buses.bus_index("Battle")) - linear_to_db(0.25)) < 0.01, "battle bus volume")
	check(AudioServer.get_bus_volume_db(Buses.bus_index("UI")) <= -79.0, "ui bus at 0 is silent")
	check(absf(AudioServer.get_bus_volume_db(Buses.bus_index("Master")) - linear_to_db(0.8)) < 0.01, "master default 80%")
	var tab: Control = AudioTab.build()
	var s: HSlider = tab.get_node("OptVolBattle")
	s.value = 40.0
	s.value_changed.emit(s.value)  # outside the tree Range does not emit by itself (the test runner has no SceneTree)
	check(absf(float(Settings.get_value("audio", "battle")) - 0.4) < 0.001, "slider stores the setting")
	check(absf(AudioServer.get_bus_volume_db(Buses.bus_index("Battle")) - linear_to_db(0.4)) < 0.01, "slider applies to the bus")
	var mb: CheckButton = tab.get_node("OptMute")
	mb.button_pressed = true
	mb.toggled.emit(true)
	check(AudioServer.is_bus_mute(Buses.bus_index("Master")), "mute applies")
	Buses.set_duck(1.0)
	check(absf(AudioServer.get_bus_volume_db(Buses.bus_index("Battle")) - (linear_to_db(0.4) + Buses.DUCK_DB)) < 0.01, "radio ducks the battle bus")
	Buses.set_duck(0.0)
	Buses.set_setting("mute", false)
	tab.free()
	Settings.use_path(Settings.DEFAULT_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


func test_headless_creates_no_players() -> void:
	check(not Director.audio_available(), "test run is headless / Dummy driver")
	var d = _director()
	check(not d.enabled, "director disabled headless")
	d.handle_events([{"type": "ShotFired", "weapon": "rifle", "hit": true, "from": Vector2(32, 32), "to": Vector2(33, 32)},
		{"type": "EntityDestroyed", "kind": "building", "def": "x", "owner": 1, "pos": Vector2(32, 33)}])
	d.ui("ui_click")
	d.queue_radio("contact")
	for i in 20:
		d.tick(0.1)
	check(int(d.counts.get("shot_rifle", 0)) == 1 and d.radio_log.size() == 1, "logic still runs (%s)" % [d.counts])
	check_eq(d.players_created, 0, "no players created")
	check_eq(d.get_child_count(), 0, "no child nodes")
	d.free()


func test_far_variant_and_fog() -> void:
	var d = _director()
	d.listener_override = [Vector2.ZERO, Vector2(100, 100)]
	check_eq(d.play_at("shot_rifle", Vector2(0, 0)), "shot_rifle", "near = near variant")
	var far_tile := Vector2(12, 0)
	var dn: float = d.dist_norm(far_tile)
	check(dn > Director.FAR_START and dn < Director.MAX_DN, "test tile is in the far band (%.2f)" % dn)
	check_eq(d.play_at("shot_artillery", far_tile), "shot_artillery", "far artillery queues a delayed boom")
	check_eq(int(d.counts.get("shot_artillery_far", 0)), 0, "the distant thump has not played yet")
	d.tick(Director.FLASH_DELAY_MAX)
	check_eq(int(d.counts.get("shot_artillery_far", 0)), 1, "far artillery swaps to the distant thump")
	check_eq(d.play_at("impact_bullet", far_tile), "", "far bullet impacts are silent")
	check_eq(d.play_at("shot_cannon", Vector2(0, 0), false), "explosion_far", "fog-hidden cannon is distant-only")
	check_eq(d.play_at("impact_heavy", Vector2(0, 0), false), "", "fog-hidden impact is silent")
	check_eq(d.play_at("shot_rifle", Vector2(400, 400)), "", "way off-screen small arms are silent")
	d.free()


func test_sim_hash_untouched() -> void:
	var a := make_world()
	var b := make_world()
	var d = _director(0)
	for i in 120:
		a.step()
		b.step()
		d.handle_events(b.events)
		d.tick(0.05)
	check_eq(a.state_hash(), b.state_hash(), "listening to events never changes the sim")
	d.free()
