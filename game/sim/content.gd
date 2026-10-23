class_name Content
extends RefCounted
## Read-only access to versioned content definitions in res://content/*.json.
## Whole-number JSON values are normalized to int so ledger math stays integral.

const FILES := ["units", "production", "buildings", "weapons", "rules", "stages"]

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
