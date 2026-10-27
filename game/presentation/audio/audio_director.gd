extends Node2D
## G6.1 audio director (owner: AUDIO61). Presentation only: reads sim events the view already dispatches
## (MatchView.world_events) and never writes to the sim, so the sim hash is untouched.
## Hook (MatchView, once): var ad = AudioDirector.new(); add_child(ad); ad.setup(self)
## - battle sound: ShotFired (per weapon class) + impacts, EntityDestroyed, StrikeImpact; positional 2D
##   (AudioStreamPlayer2D, the camera is the listener), far-variant swap by camera distance, fog-hidden events
##   distant-only, voice limits per category (audio_mixer.gd);
## - radio chatter: CommandNet ReportSent / OrderDelivered / Succession + own-side production, construction,
##   broken units, aircraft, waves; only the player's side is heard (audio_catalog.radio_for_event); one line at
##   a time with a priority queue (radio_queue.gd); the Battle bus ducks under radio;
## - engine loops for selected / nearby moving vehicles (max 4); UI clicks for every Button in the tree.
## Headless / Dummy driver: `enabled` = false. Events are still classified and counted (tests, playtest log), but
## no player node is ever created.

const Cat = preload("res://presentation/audio/audio_catalog.gd")
const Mixer = preload("res://presentation/audio/audio_mixer.gd")
const RadioQueue = preload("res://presentation/audio/radio_queue.gd")
const Buses = preload("res://presentation/audio/audio_buses.gd")
const ViewUtil = preload("res://presentation/view/view_util.gd")
const AudioG7 = preload("res://presentation/audio/audio_g7.gd")   # G7 (AUDIO7): G7 sounds, voices, music

## G7 (AUDIO7): a voice line started (radio chatter, operator bark, command ack, PROTOCOL): {channel radio|operator|
## command|protocol, speaker, text, team, op, cat, line, dur, at, voiced}. OPSUI7's team cam / advisor read it.
signal subtitle(info: Dictionary)

const POOL := 24
const FAR_START := 1.25      # camera-distance (1 = edge of the view) where the far variant takes over
const MAX_DN := 3.5          # beyond this: silent (big booms reach BOOM_DN)
const BOOM_DN := 7.0
const MAX_ENGINES := 4
const META := "audio61_director"

var mv = null
var enabled := false
var player_fid := 0
var kind := "human"
var mixer = Mixer.new()
var radio = RadioQueue.new()
var counts: Dictionary = {}      # sound id -> plays started
var radio_log: Array = []        # [{line, cat, at}]
var players_created := 0
var listener_override: Variant = null   # tests: [center Vector2 (px), half extents Vector2 (px)]
var vis_override: Variant = null        # tests: Callable(Vector2i) -> bool

var _now := 0.0
var _pool: Array = []
var _next := 0
var _radio_player: AudioStreamPlayer = null
var _ui_players: Array = []
var _engines: Dictionary = {}    # uid -> AudioStreamPlayer2D
var _eng_t := 0.0
var _eng_prev: Dictionary = {}
var _duck := 0.0
var _line_rot := 0
var _alert_t: Dictionary = {}
var g7 = null                    # G7 (AUDIO7) layer: audio_g7.gd
var _voice_player: AudioStreamPlayer = null


func _init() -> void:
	g7 = AudioG7.new(self)
	add_to_group("cine7_music")   # G7 CINE7 CR 1546: cinematic music cues


## G7 CINE7 CR 1546: called by the cinematic director (call_group "cine7_music"); "cine_end" resumes adaptive music.
func cine_cue(cue: String) -> void:
	if g7 != null and g7.music != null:
		g7.music.cine_cue(cue)


static func audio_available() -> bool:
	return DisplayServer.get_name() != "headless" and AudioServer.get_driver_name().to_lower() != "dummy"


## The live director (or null), for UI code that wants a one-shot: AudioDirector.current().ui("ui_confirm").
static func current():
	var d = Engine.get_meta(META) if Engine.has_meta(META) else null
	return d if is_instance_valid(d) else null


func setup(view, force_enabled: Variant = null) -> void:
	mv = view
	enabled = audio_available() if force_enabled == null else bool(force_enabled)
	name = "AudioDirector"
	if mv != null:
		player_fid = int(mv.get("player_fid")) if mv.get("player_fid") != null else 0
		var w = mv.get("world")
		if w != null and w.factions.has(player_fid):
			kind = Cat.faction_kind(String(w.factions[player_fid].get("faction_def", w.factions[player_fid].get("faction", ""))))
		if mv.has_signal("world_events") and not mv.world_events.is_connected(handle_events):
			mv.world_events.connect(handle_events)
	Engine.set_meta(META, self)
	g7.setup(enabled)
	if enabled:
		Buses.apply()
		if is_inside_tree():
			_hook_buttons(get_tree().root)
			if not get_tree().node_added.is_connected(_on_node_added):
				get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if Engine.has_meta(META) and Engine.get_meta(META) == self:
		Engine.remove_meta(META)


func _process(delta: float) -> void:
	tick(delta)


# ------------------------------------------------------------------ events
func handle_events(evs: Array) -> void:
	for ev in evs:
		_event(ev)


func _event(ev: Dictionary) -> void:
	g7.event(ev)
	match String(ev.get("type", "")):
		"ShotFired":
			if AudioG7.skip_shot(ev):
				return  # G7 turret special kinds: the T7Rail / T7Emp / T7Burn / T7Cone event plays the sound
			var wid := String(ev.get("weapon", ""))
			var from: Vector2 = ev.get("from", Vector2.ZERO)
			var to: Vector2 = ev.get("to", from)
			_shot_alerts(ev, to)
			var sid := Cat.shot_sound(wid)
			if not mixer.would_accept(sid, "gun", _now) and not mixer.would_accept("impact_bullet", "impact", _now):
				return  # every relevant voice is busy: nothing of this shot could be heard (no radio for shots)
			var vis := _visible(from) or _visible(to)
			play_at(sid, from, vis)
			if bool(ev.get("hit", false)):
				play_at(Cat.impact_sound(wid), to, _visible(to), -5.0)
		"EntityDestroyed":
			var p: Vector2 = ev.get("pos", Vector2.ZERO)
			play_at(Cat.death_sound(ev), p, _visible(p))
		"StrikeImpact":
			var sp: Vector2 = ev.get("pos", Vector2.ZERO)
			play_at("explosion_near", sp, _visible(sp))
		"ProductionCompleted":
			if int(ev.get("owner", -1)) == player_fid:
				ui("alert_ready")
		"ConstructionCompleted":
			if int(ev.get("owner", -1)) == player_fid:
				ui("alert_build")
	var r := Cat.radio_for_event(ev, player_fid)
	if not r.is_empty():
		queue_radio(String(r.cat), r.get("tags", []))


## Incoming fire on the player's side: artillery-inbound radio, base-under-attack alert (rate limited).
func _shot_alerts(ev: Dictionary, to: Vector2) -> void:
	if mv == null or not mv.has_method("world_readable") or not mv.world_readable():
		return
	var t = mv.world.entities.get(int(ev.get("target", -1)))
	if t == null or int(t.owner) != player_fid:
		return
	if bool(ev.get("indirect", false)):
		queue_radio("artillery_inbound", [])
	elif String(t.kind) == "building" and _ready_alert("base", 12.0):
		ui("alert_attack")
		queue_radio("base_attack", [])


func _ready_alert(key: String, gap: float) -> bool:
	if _alert_t.has(key) and _now - float(_alert_t[key]) < gap:
		return false
	_alert_t[key] = _now
	return true


func _visible(tile: Vector2) -> bool:
	var c := Vector2i(floori(tile.x), floori(tile.y))
	if vis_override != null:
		return bool((vis_override as Callable).call(c))
	if mv != null and mv.has_method("cell_visible"):
		return mv.cell_visible(c)
	return true


## Camera distance of a map position: 0 = view centre, 1 = edge of the view.
func dist_norm(tile: Vector2) -> float:
	var px := ViewUtil.iso(tile)
	var center := Vector2.ZERO
	var half := Vector2(960, 540)
	if listener_override != null:
		center = listener_override[0]
		half = listener_override[1]
	elif mv != null and mv.get("camera") != null:
		var cam: Camera2D = mv.camera
		center = cam.get_screen_center_position()
		half = cam.get_viewport_rect().size / cam.zoom / 2.0
	else:
		return 0.5
	return (px - center).length() / maxf(1.0, half.length())


# ------------------------------------------------------------------ battle one-shots
## Plays sound id at a map position (tiles). Hidden (fogged) events play distant-only. Returns the id played.
func play_at(id: String, tile: Vector2, vis: bool = true, gain_db: float = 0.0) -> String:
	if id == "":
		return ""
	if vis and not mixer.would_accept(id, Cat.category(id), _now):
		return ""  # category full: skip the distance math (a far swap could still fit, but full = loud enough)
	var dn := dist_norm(tile)
	if not vis or dn > FAR_START:
		id = Cat.far_of(id)
		gain_db -= 6.0 if not vis else clampf((dn - FAR_START) * 2.5, 0.0, 12.0)
		if id == "":
			return ""
	var boom := id.begins_with("explosion") or id.begins_with("shot_artillery") or id == "shot_cannon" 			or id.begins_with("core_") or id == "shot_rail" or id == "creep_fissure"
	if dn > (BOOM_DN if boom else MAX_DN):
		return ""
	var vars := Cat.variants(id)
	if vars.is_empty():
		return ""
	var path := String(vars[mixer.next_variant(id, vars.size())])
	if not mixer.request(id, Cat.category(id), _now, Cat.duration(path)):
		return ""
	counts[id] = int(counts.get(id, 0)) + 1
	if enabled:
		var p := _free_player()
		p.stream = Cat.stream(path)
		p.position = ViewUtil.iso(tile)
		p.volume_db = gain_db
		p.max_distance = _hear_px()
		p.play()
	return id


func _hear_px() -> float:
	if mv != null and mv.get("camera") != null:
		var cam: Camera2D = mv.camera
		return (cam.get_viewport_rect().size / cam.zoom).length() * 2.0
	return 4000.0


func _free_player() -> AudioStreamPlayer2D:
	if _pool.size() < POOL:
		var p := AudioStreamPlayer2D.new()
		p.bus = "Battle"
		p.attenuation = 1.0
		p.panning_strength = 1.0
		add_child(p)
		_pool.append(p)
		players_created += 1
		return p
	for k in POOL:
		var q: AudioStreamPlayer2D = _pool[(_next + k) % POOL]
		if not q.playing:
			_next = (_next + k + 1) % POOL
			return q
	_next = (_next + 1) % POOL
	return _pool[_next]


# ------------------------------------------------------------------ UI one-shots
## Non-positional one-shot on the UI bus (alerts too). Returns true when it started.
func ui(id: String) -> bool:
	var vars := Cat.variants(id)
	if vars.is_empty():
		return false
	var path := String(vars[mixer.next_variant(id, vars.size())])
	if not mixer.request(id, Cat.category(id), _now, Cat.duration(path)):
		return false
	counts[id] = int(counts.get(id, 0)) + 1
	if enabled:
		var p: AudioStreamPlayer = null
		for q in _ui_players:
			if not (q as AudioStreamPlayer).playing:
				p = q
				break
		if p == null:
			if _ui_players.size() >= 4:
				p = _ui_players[0]
			else:
				p = AudioStreamPlayer.new()
				p.bus = "UI"
				add_child(p)
				_ui_players.append(p)
				players_created += 1
		p.stream = Cat.stream(path)
		p.play()
	return true


func _hook_buttons(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_hook_buttons(c)


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not (n as BaseButton).pressed.is_connected(_on_button):
		(n as BaseButton).pressed.connect(_on_button)


func _on_button() -> void:
	ui("ui_click")


# ------------------------------------------------------------------ radio
## Queues a radio line of category cat (player's side only: callers pass own-side events). True when queued.
func queue_radio(cat: String, tags: Array = []) -> bool:
	var line := Cat.pick_line(cat, kind, tags, _line_rot)
	_line_rot += 1
	return radio.push(line, cat, Cat.priority(cat), _now, Cat.cooldown(cat))


func _radio_dur(line: String) -> float:
	return Cat.duration(Cat.radio_path(line))


## Advances the director clock: starts the next radio line, eases ducking, refreshes engine loops.
func tick(dt: float) -> void:
	_now += dt
	if mv != null and mv.get("player_fid") != null and int(mv.player_fid) != player_fid:
		setup(mv, enabled)  # the view switched sides (spectate / editor): re-read side + faction voice
	var it: Dictionary = radio.poll(_now, _radio_dur)
	if not it.is_empty():
		radio_log.append({"line": it.line, "cat": it.cat, "at": snappedf(_now, 0.01)})
		if radio_log.size() > 200:
			radio_log.pop_front()
		counts["radio:" + String(it.cat)] = int(counts.get("radio:" + String(it.cat), 0)) + 1
		var bus: String = g7.on_line_started(it)   # G7: subtitle + Radio or Voice bus
		if enabled:
			if _radio_player == null:
				_radio_player = AudioStreamPlayer.new()
				_radio_player.bus = "Radio"
				add_child(_radio_player)
				players_created += 1
			if _voice_player == null:
				_voice_player = AudioStreamPlayer.new()
				_voice_player.bus = "Voice"
				add_child(_voice_player)
				players_created += 1
			var vp: AudioStreamPlayer = _voice_player if bus == "Voice" else _radio_player
			vp.stream = Cat.stream(Cat.radio_path(String(it.line)))
			vp.play()
	_duck = move_toward(_duck, 1.0 if radio.busy(_now) else 0.0, dt * (6.0 if radio.busy(_now) else 1.5))
	g7.tick(dt)
	if enabled:
		Buses.set_duck(_duck)
		_eng_t += dt
		if _eng_t >= 0.5:
			_eng_t = 0.0
			_update_engines()
		_follow_engines()


func now() -> float:
	return _now


# ------------------------------------------------------------------ G7 (AUDIO7) public API
## PROTOCOL advisor line (OPSUI7): key in AudioCatalog7.PROTOCOL_KEYS, text = full subtitle. True when voiced.
func protocol_say(key: String, text: String = "") -> bool:
	return g7.protocol_say(key, text)


## The last n subtitles (newest last): same dicts as the `subtitle` signal.
func recent_subtitles(n: int = 8) -> Array:
	var s: Array = g7.subtitles
	return s.slice(maxi(0, s.size() - n))


## Music state for HUD / playtest: {mode, levels {stem: 0..1}, log}.
func music_state() -> Dictionary:
	return {"mode": g7.music.mode, "levels": g7.music.levels.duplicate(), "log": g7.music.mlog.duplicate()}


# ------------------------------------------------------------------ engine loops
## Picks up to MAX_ENGINES vehicles: selected first, then the nearest moving own/visible vehicles on screen.
func engine_candidates() -> Array:
	var out: Array = []
	if mv == null or not mv.has_method("world_readable") or not mv.world_readable():
		return out
	var w = mv.world
	for id in mv.get("selection") if mv.get("selection") != null else []:
		var e = w.entities.get(int(id))
		if e != null and e.kind == "unit" and Cat.engine_sound(String(e.def)) != "" and out.size() < MAX_ENGINES:
			out.append(int(id))
	if out.size() >= MAX_ENGINES or w.entities.size() > 3000:
		return out
	var near: Array = []
	for id in w.entities:
		var e = w.entities[id]
		if e.kind != "unit" or out.has(int(id)):
			continue
		var p: Vector2 = e.pos
		var moved := _eng_prev.has(id) and Vector2(_eng_prev[id]).distance_squared_to(p) > 0.0004
		_eng_prev[id] = p
		if not moved or not _visible(p):
			continue
		var dn := dist_norm(p)
		if dn < 0.7 and Cat.engine_sound(String(e.def)) != "":
			near.append([dn, int(id)])
	near.sort()
	for pr in near:
		if out.size() >= MAX_ENGINES:
			break
		out.append(int(pr[1]))
	return out


func _update_engines() -> void:
	var want := engine_candidates()
	for id in _engines.keys():
		if not want.has(id):
			(_engines[id] as Node).queue_free()
			_engines.erase(id)
	for id in want:
		if _engines.has(id):
			continue
		var e = mv.world.entities.get(id)
		var sid := Cat.engine_sound(String(e.def))
		var vars := Cat.variants(sid)
		if vars.is_empty():
			continue
		var p := AudioStreamPlayer2D.new()
		p.bus = "Battle"
		p.stream = Cat.stream(String(vars[posmod(id, vars.size())]), true)
		p.volume_db = -12.0
		p.max_distance = _hear_px() * 0.5
		p.position = ViewUtil.iso(Vector2(e.pos))
		add_child(p)
		players_created += 1
		p.play()
		_engines[id] = p
		counts[sid] = int(counts.get(sid, 0)) + 1


func _follow_engines() -> void:
	if _engines.is_empty() or mv == null or not mv.world_readable():
		return
	for id in _engines:
		var e = mv.world.entities.get(id)
		if e != null:
			(_engines[id] as AudioStreamPlayer2D).position = ViewUtil.iso(Vector2(e.pos))
