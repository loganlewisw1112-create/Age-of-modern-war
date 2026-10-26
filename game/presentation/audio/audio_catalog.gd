extends RefCounted
## G6.1 audio catalog (owner: AUDIO61). Presentation only: never read by the sim, never hashed.
## Data: assets/generated/audio/audio_manifest.json (tools/audio/build_manifest.py) + the radio line library
## content/g6/audio_lines_g61.json (key _audio, skipped by Content's fragment merge).
## Pure, static mapping helpers (tested headless by tests/test_audio61.gd):
##   shot_sound(weapon_id) / impact_sound(weapon_id) / death_sound(ev) / event_sounds(ev, player_fid)
##   radio_for_event(ev, player_fid) -> {cat, tags} | {}     pick_line(cat, kind, tags, n) -> line id | ""
##   stream(res_path, loop) -> AudioStream (cached; imported resource if present, else parsed from the raw .wav)

const MANIFEST := "res://assets/generated/audio/audio_manifest.json"
const LINES := "res://content/g6/audio_lines_g61.json"

## Sound id -> mixer category (voice limits per category live in audio_mixer.gd).
const CATEGORY := {
	"shot_": "gun", "impact_": "impact", "explosion_": "explosion", "engine_": "engine", "ui_": "ui",
	"alert_": "alert", "radio_": "radio", "machine_": "radio", "foot_": "impact", "gear_": "impact",
}
## Far-variant swap: near sound id -> distant sound id.
const FAR := {
	"shot_rifle": "shot_far", "shot_mg": "shot_far", "shot_sniper": "shot_far", "shot_autocannon": "shot_far",
	"shot_cannon": "explosion_far", "shot_rocket": "shot_far", "shot_artillery": "shot_artillery_far",
	"shot_energy": "shot_far", "shot_flame": "", "explosion_near": "explosion_far", "explosion_small": "explosion_far",
	"impact_bullet": "", "impact_heavy": "",
}

static var _man: Dictionary = {}
static var _lib: Dictionary = {}
static var _streams: Dictionary = {}
static var _shot_cache: Dictionary = {}
static var _impact_cache: Dictionary = {}


static func _json(path: String) -> Dictionary:
	var t := FileAccess.get_file_as_string(path)
	var p = JSON.parse_string(t) if t != "" else null
	return p if typeof(p) == TYPE_DICTIONARY else {}


static func manifest() -> Dictionary:
	if _man.is_empty():
		_man = _json(MANIFEST)
	return _man


static func lib() -> Dictionary:
	if _lib.is_empty():
		_lib = _json(LINES).get("_audio", {})
	return _lib


static func sound_ids() -> Array:
	var ids: Array = manifest().get("sfx", {}).keys()
	ids.sort()
	return ids


static func variants(id: String) -> Array:
	return manifest().get("sfx", {}).get(id, [])


static func has_sound(id: String) -> bool:
	return not variants(id).is_empty()


static func radio_path(line_id: String) -> String:
	return String(manifest().get("radio", {}).get(line_id, ""))


static func duration(res_path: String) -> float:
	return float(manifest().get("dur", {}).get(res_path, 0.5))


static func category(id: String) -> String:
	for p in CATEGORY:
		if id.begins_with(String(p)):
			return String(CATEGORY[p])
	return "ui"


static func far_of(id: String) -> String:
	return String(FAR.get(id, id))


# ------------------------------------------------------------------ sim event -> sound id
static func weapon_def(weapon_id: String) -> Dictionary:
	var d = Content.weapon(weapon_id) if weapon_id != "" else {}
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func shot_sound(weapon_id: String) -> String:
	if not _shot_cache.has(weapon_id):
		_shot_cache[weapon_id] = _shot_sound(weapon_id)
	return _shot_cache[weapon_id]


static func _shot_sound(weapon_id: String) -> String:
	var d := weapon_def(weapon_id)
	var cls := String(d.get("class", ""))
	var w := weapon_id.to_lower()
	if bool(d.get("indirect", false)) or cls == "artillery":
		return "shot_rocket" if (w.contains("rocket") or w.contains("mlrs") or w.contains("missile")) else "shot_artillery"
	match cls:
		"energy":
			return "shot_energy"
		"flame":
			return "shot_flame"
		"sniper":
			return "shot_sniper"
		"autocannon":
			return "shot_autocannon"
		"at", "top_attack", "torpedo":
			if w.contains("rocket") or w.contains("missile") or w.contains("atgm") or w.contains("sam") \
					or w.contains("manpads") or bool(d.get("guided", false)) or cls != "at":
				return "shot_rocket"
			return "shot_cannon"
		"grenade", "demolition", "frag":
			return "explosion_small"
		"melee":
			return ""
	if w.contains("mg") or w.contains("burst") or w.contains("rotary") or w.contains("hmg") or int(d.get("salvo", 1)) > 2:
		return "shot_mg"
	return "shot_rifle"


static func impact_sound(weapon_id: String) -> String:
	if not _impact_cache.has(weapon_id):
		_impact_cache[weapon_id] = _impact_sound(weapon_id)
	return _impact_cache[weapon_id]


static func _impact_sound(weapon_id: String) -> String:
	var s := shot_sound(weapon_id)
	if s in ["shot_cannon", "shot_rocket", "shot_autocannon"]:
		return "impact_heavy"
	if s in ["shot_artillery", "explosion_small"]:
		return "explosion_near"
	if s in ["shot_rifle", "shot_mg", "shot_sniper"]:
		return "impact_bullet"
	return ""


static func _is_vehicle_def(def_id: String) -> bool:
	var u := Content.unit(def_id)
	if u.is_empty():
		return false
	var mc := String(u.get("move_class", "")).to_lower()
	return bool(u.get("is_air", false)) or not (mc.contains("foot") or mc.contains("inf") or mc == "")


## Explosion for a destroyed entity ("" = none: infantry fall silently).
static func death_sound(ev: Dictionary) -> String:
	var k := String(ev.get("kind", ""))
	if k == "building":
		return "explosion_near"
	if k == "unit" and _is_vehicle_def(String(ev.get("def", ""))):
		return "explosion_near"
	return ""


## Engine loop id for a unit def ("" = none).
static func engine_sound(def_id: String) -> String:
	var u := Content.unit(def_id)
	if u.is_empty():
		return ""
	var id := def_id.to_lower()
	var mc := String(u.get("move_class", "")).to_lower()
	if bool(u.get("is_air", false)) or mc.contains("air"):
		return "engine_heli" if (id.contains("heli") or id.contains("gunship") or id.contains("rotor")) else "engine_jet"
	if mc.contains("naval") or mc.contains("boat") or mc.contains("ship") or mc.contains("sea"):
		return "engine_ship"
	if mc.contains("track") or String(u.get("armor", "")) == "heavy":
		return "engine_tank"
	if mc.contains("foot") or mc.contains("inf") or mc == "":
		return ""
	return "engine_truck"


# ------------------------------------------------------------------ streams
static func stream(res_path: String, loop: bool = false) -> AudioStream:
	var key := res_path + ("#loop" if loop else "")
	if _streams.has(key):
		return _streams[key]
	var s: AudioStream = null
	if ResourceLoader.exists(res_path):
		s = load(res_path) as AudioStream
		if loop and s is AudioStreamWAV:
			s = (s as AudioStreamWAV).duplicate()
	if s == null:
		s = _parse_wav(res_path)
	if s is AudioStreamWAV and loop:
		var wv := s as AudioStreamWAV
		wv.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wv.loop_begin = 0
		wv.loop_end = wv.data.size() / 2
	_streams[key] = s
	return s


## Minimal RIFF reader for the generator's own files (16-bit PCM mono/stereo).
static func _parse_wav(res_path: String) -> AudioStreamWAV:
	var b := FileAccess.get_file_as_bytes(res_path)
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var i := 12
	var rate := 22050
	var ch := 1
	var pcm := PackedByteArray()
	while i + 8 <= b.size():
		var tag := b.slice(i, i + 4).get_string_from_ascii()
		var sz := b.decode_u32(i + 4)
		if tag == "fmt ":
			ch = b.decode_u16(i + 10)
			rate = b.decode_u32(i + 12)
		elif tag == "data":
			pcm = b.slice(i + 8, mini(b.size(), i + 8 + sz))
		i += 8 + sz + (sz & 1)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = ch == 2
	s.data = pcm
	return s


# ------------------------------------------------------------------ radio
static func priority(cat: String) -> int:
	return int(lib().get("categories", {}).get(cat, {}).get("priority", 10))


static func cooldown(cat: String) -> float:
	return float(lib().get("categories", {}).get(cat, {}).get("cooldown_s", 6.0))


## "human" | "machine" for a faction def id (library table factions; ids containing "machine" default to machine).
static func faction_kind(faction_def: String) -> String:
	var t: Dictionary = lib().get("factions", {})
	if t.has(faction_def):
		return String(t[faction_def])
	return "machine" if faction_def.to_lower().contains("machine") else "human"


static func _dir_tag(text: String) -> String:
	var words := text.replace(")", " ").replace(",", " ").strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	var last := String(words[words.size() - 1])
	return last if last in ["N", "NE", "E", "SE", "S", "SW", "W", "NW"] else ""


## Radio category (+ tags) for a sim event heard on side player_fid; {} = no radio line.
## CHAIN61 events carry fid; other events are voiced only when they concern the player's own side.
static func radio_for_event(ev: Dictionary, player_fid: int) -> Dictionary:
	var t := String(ev.get("type", ""))
	match t:
		"ReportSent":
			if int(ev.get("fid", -1)) != player_fid:
				return {}
			var text := String(ev.get("text", ""))
			match String(ev.get("kind", "")):
				"contact":
					var tags: Array = ["armor" if text.contains("armor") else "infantry"]
					var d := _dir_tag(text)
					if d != "":
						tags.append(d)
					return {"cat": "contact", "tags": tags}
				"casualty":
					return {"cat": "casualty", "tags": []}
				"ammo":
					return {"cat": "ammo", "tags": []}
				"fuel":
					return {"cat": "fuel", "tags": []}
				"objective":
					return {"cat": "objective", "tags": []}
				"status":
					if text.contains("falling back") or text.contains("withdraw"):
						return {"cat": "falling_back", "tags": []}
					return {"cat": "initiative", "tags": []}
				"request":
					var what := text.get_slice("requests ", 1).to_lower()
					if what.contains("resupply") or what.contains("ammo"):
						return {"cat": "ammo", "tags": []}
					if what.contains("medevac") or what.contains("medic") or what.contains("wounded"):
						return {"cat": "request_medevac", "tags": []}
					if what.contains("reinforce") or what.contains("replacement"):
						return {"cat": "request_reinforce", "tags": []}
					return {"cat": "request_support", "tags": []}
			return {}
		"OrderDelivered":
			if int(ev.get("fid", -1)) != player_fid:
				return {}
			var o = ev.get("order", {})
			var inner = o.get("order", o) if typeof(o) == TYPE_DICTIONARY else {}
			var ot := String(inner.get("type", "")) if typeof(inner) == TYPE_DICTIONARY else ""
			if ot in ["hold", "defend", "dig_in", "stop"]:
				return {"cat": "holding", "tags": []}
			if ot in ["withdraw", "retreat", "fall_back"]:
				return {"cat": "falling_back", "tags": []}
			if ot in ["move", "advance", "relocate"]:
				return {"cat": "moving", "tags": []}
			return {"cat": "ack", "tags": []}
		"Succession":
			return {"cat": "officer_down", "tags": []} if int(ev.get("fid", -1)) == player_fid else {}
		"ProductionCompleted":
			return {"cat": "company_ready", "tags": []} if int(ev.get("owner", -1)) == player_fid else {}
		"ConstructionCompleted":
			return {"cat": "building_done", "tags": []} if int(ev.get("owner", -1)) == player_fid else {}
		"UnitBroken":
			return {"cat": "broken", "tags": []} if int(ev.get("owner", ev.get("fid", -1))) == player_fid else {}
		"AircraftTookOff":
			return {"cat": "air_on_station", "tags": []} if int(ev.get("owner", ev.get("fid", -1))) == player_fid else {}
		"WaveIncoming":
			return {"cat": "wave", "tags": []} if int(ev.get("owner", -1)) != player_fid else {}
	return {}


## A line id for cat/kind matching as many tags as possible; n rotates among equally good lines. "" = none.
static func pick_line(cat: String, kind: String, tags: Array, n: int) -> String:
	var best: Array = []
	var best_score := -1
	for ln in lib().get("lines", []):
		if String(ln.cat) != cat or String(ln.get("faction", "human")) != kind:
			continue
		if radio_path(String(ln.id)) == "":
			continue
		var lt: Array = ln.get("tags", [])
		var score := 0
		var bad := false
		for tg in lt:
			if tags.has(tg):
				score += 1
			else:
				bad = true
		if bad:
			continue
		if score > best_score:
			best_score = score
			best = [String(ln.id)]
		elif score == best_score:
			best.append(String(ln.id))
	if best.is_empty():
		return pick_line(cat, "human", tags, n) if kind != "human" else ""
	return String(best[posmod(n, best.size())])
