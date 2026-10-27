extends RefCounted
## G6.1 audio buses + volume settings (owner: AUDIO61). Buses Battle / Radio / UI / Music are created at runtime
## under Master when missing (no bus layout file needed). Volumes persist in the Settings store
## (user://settings.cfg, section "audio": master, battle, radio, ui, music in 0..1, mute bool).
## Settings is loaded lazily (no preload) so settings.gd may preload audio_tab.gd without a cycle.

const BUSES := ["Battle", "Radio", "UI", "Music", "Voice"]
const KEYS := {"Master": "master", "Battle": "battle", "Radio": "radio", "UI": "ui", "Music": "music", "Voice": "voice"}
## G7 (AUDIO7): Voice bus (command voice + PROTOCOL advisor), protocol_voice = PROTOCOL voice on/off.
const DEFAULTS := {"master": 0.8, "battle": 0.8, "radio": 0.9, "ui": 0.7, "music": 0.6, "voice": 0.9, "mute": false}
## PROTOCOL advisor mode lives in OPSUI7's Settings key protocol.advisor: on (voiced) | muted (text only) | off.
const SETTINGS_PATH := "res://presentation/menu/settings.gd"
const DUCK_DB := -9.0
const MUSIC_DUCK_DB := -7.0   # G7 (AUDIO7): voice ducks the music too

static var _duck := 0.0
static var _hush := 0.0   # G7 (AUDIO7): pre-Tide silence pulls the battle down too
const HUSH_DB := -24.0


static func _settings():
	return load(SETTINGS_PATH)


static func get_setting(key: String):
	var S = _settings()
	if S == null or not S._c().has_section_key("audio", key):
		return DEFAULTS.get(key)
	var v = S.get_value("audio", key)
	return DEFAULTS.get(key) if v == null else v


static func set_setting(key: String, v) -> void:
	var S = _settings()
	if S != null:
		S.set_value("audio", key, v)
	apply()


## G7 (AUDIO7): PROTOCOL advisor mode (OPSUI7's key, shared so the Audio tab toggle and the advisor card agree).
static func protocol_mode() -> String:
	var S = _settings()
	if S == null or not S._c().has_section_key("protocol", "advisor"):
		return "on"
	var v = S.get_value("protocol", "advisor")
	return "on" if v == null else String(v)


static func set_protocol_mode(m: String) -> void:
	var S = _settings()
	if S != null:
		S.set_value("protocol", "advisor", m)


static func save() -> void:
	var S = _settings()
	if S != null:
		S.save()


static func ensure() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	# G7 (AUDIO7) mixer budget: a hard limiter at the end of Master, so music + battle + voice never clip.
	var has_lim := false
	for k in AudioServer.get_bus_effect_count(0):
		has_lim = has_lim or AudioServer.get_bus_effect(0, k) is AudioEffectHardLimiter
	if not has_lim:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.3
		AudioServer.add_bus_effect(0, lim)


static func bus_index(b: String) -> int:
	return AudioServer.get_bus_index(b)


static func lin_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)


## Applies every stored volume (+ mute, + current radio ducking of Battle) to the buses.
static func apply() -> void:
	ensure()
	for b in KEYS:
		var i := bus_index(String(b))
		if i < 0:
			continue
		var db := lin_db(float(get_setting(String(KEYS[b]))))
		if String(b) == "Battle":
			db += _duck + _hush
		elif String(b) == "Music":
			db += _duck * MUSIC_DUCK_DB / DUCK_DB
		AudioServer.set_bus_volume_db(i, db)
	AudioServer.set_bus_mute(bus_index("Master"), bool(get_setting("mute")))


## Radio ducking: amount 0..1 of DUCK_DB on the Battle bus (the director eases it in and out).
static func set_duck(amount: float) -> void:
	var d := DUCK_DB * clampf(amount, 0.0, 1.0)
	if absf(d - _duck) < 0.05:
		return
	_duck = d
	var i := bus_index("Battle")
	if i >= 0:
		AudioServer.set_bus_volume_db(i, lin_db(float(get_setting("battle"))) + _duck + _hush)
	var m := bus_index("Music")
	if m >= 0:
		AudioServer.set_bus_volume_db(m, lin_db(float(get_setting("music"))) + _duck * MUSIC_DUCK_DB / DUCK_DB)


## G7 (AUDIO7): 0..1 of HUSH_DB on the Battle bus (the music director's pre-Tide silence window).
static func set_hush(amount: float) -> void:
	var h := HUSH_DB * clampf(amount, 0.0, 1.0)
	if absf(h - _hush) < 0.05:
		return
	_hush = h
	var i := bus_index("Battle")
	if i >= 0:
		AudioServer.set_bus_volume_db(i, lin_db(float(get_setting("battle"))) + _duck + _hush)


static func hush_db() -> float:
	return _hush


static func duck_db() -> float:
	return _duck
