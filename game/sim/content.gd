class_name Content
extends RefCounted
## Read-only access to versioned content definitions in res://content/*.json.
## Whole-number JSON values are normalized to int so ledger math stays integral.

const FILES := ["units", "production", "buildings", "weapons", "rules", "stages", "factions", "research"]

static var _data: Dictionary = {}
static var _loaded: bool = false


static func load_all() -> void:
	if _loaded:
		return
	for f in FILES:
		var path := "res://content/%s.json" % f
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			push_error("Content: missing or empty %s" % path)
			_data[f] = {}
			continue
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Content: invalid JSON in %s" % path)
			_data[f] = {}
			continue
		_data[f] = _normalize(parsed)
	_loaded = true


static func _normalize(v):
	match typeof(v):
		TYPE_FLOAT:
			if is_equal_approx(v, roundf(v)) and absf(v) < 1e15:
				return int(roundf(v))
			return v
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = _normalize(v[k])
			return out
		TYPE_ARRAY:
			var arr := []
			for x in v:
				arr.append(_normalize(x))
			return arr
		_:
			return v


static func table(name: String) -> Dictionary:
	load_all()
	return _data.get(name, {})


static func ids(name: String) -> Array:
	var out := []
	for k in table(name):
		if not String(k).begins_with("_"):
			out.append(k)
	return out


static func unit(id: String) -> Dictionary:
	return table("units").get(id, {})


static func production(id: String) -> Dictionary:
	return table("production").get(id, {})


## G3b research project def (content/research.json); {} when unknown.
static func research(id: String) -> Dictionary:
	return table("research").get(id, {})


static func building(id: String) -> Dictionary:
	return table("buildings").get(id, {})


static func weapon(id: String) -> Dictionary:
	return table("weapons").get(id, {})


static func armor_mult(weapon_class: String, armor: String) -> float:
	return float(table("weapons").get("armor_mult", {}).get(weapon_class, {}).get(armor, 1.0))


static func rules() -> Dictionary:
	return table("rules")


static func stages() -> Array:
	return table("stages").get("stages", [])


## G3a: faction registry (content/factions.json).
static func faction(id: String) -> Dictionary:
	return table("factions").get(id, {})


static func faction_ids() -> Array:
	return ids("factions")


## Def id this faction uses for a generic role ("" if the faction has none).
## Building roles: hq power depot barracks factory refinery defense extra.
## Production roles: builder gatherer infantry antitank recon light heavy artillery officer supply air.
static func role(faction_id: String, role_name: String, stage: int = 8) -> String:
	var f := faction(faction_id)
	# G3b: per-stage overrides (factions.json stage_roles {"7": {...}, "9": {...}})
	var over: Dictionary = f.get("stage_roles", {}).get(str(stage), {})
	if over.has(role_name):
		return String(over[role_name])
	return String(f.get("roles", {}).get(role_name, ""))


## G3b: is a unit/building/production def available at this stage? (stage_min default 7, stage_max optional)
static func available(d: Dictionary, stage: int) -> bool:
	if stage < int(d.get("stage_min", 7)):
		return false
	if d.has("stage_max") and stage > int(d.stage_max):
		return false
	return true


## Buildable building defs for a faction (content order).
static func buildable_for(faction_id: String) -> Array:
	var out := []
	for id in ids("buildings"):
		var d: Dictionary = building(id)
		if String(d.get("faction", "")) == faction_id and bool(d.get("buildable", false)):
			out.append(id)
	return out


## Economy profile multiplier (rules.economy_profiles[profile][key]); 1.0 when absent.
static func econ(profile: String, key: String) -> float:
	var p: Dictionary = rules().get("economy_profiles", {}).get(profile, {})
	return float(p.get(key, 1.0))
