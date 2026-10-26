extends RefCounted
## G6.1 audio buses + volume settings (owner: AUDIO61). Buses Battle / Radio / UI / Music are created at runtime
## under Master when missing (no bus layout file needed). Volumes persist in the Settings store
## (user://settings.cfg, section "audio": master, battle, radio, ui, music in 0..1, mute bool).
## Settings is loaded lazily (no preload) so settings.gd may preload audio_tab.gd without a cycle.

const BUSES := ["Battle", "Radio", "UI", "Music"]
const KEYS := {"Master": "master", "Battle": "battle", "Radio": "radio", "UI": "ui", "Music": "music"}
const DEFAULTS := {"master": 0.8, "battle": 0.8, "radio": 0.9, "ui": 0.7, "music": 0.6, "mute": false}
const SETTINGS_PATH := "res://presentation/menu/settings.gd"
const DUCK_DB := -9.0

static var _duck := 0.0


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
			db += _duck
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
		AudioServer.set_bus_volume_db(i, lin_db(float(get_setting("battle"))) + _duck)


static func duck_db() -> float:
	return _duck
