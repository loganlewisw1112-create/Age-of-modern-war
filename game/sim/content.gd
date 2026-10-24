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
	_merge_fragments()
	_loaded = true


## G4 (CONTRACTS_G4 section 2.1): merge content/g4/*.json fragments, sorted by file name.
## Tables gain NEW ids only (an existing id is an error, never overridden). Special keys:
##   armor_mult: {weapon_class: {armor: mult}}  new rows or new armor columns only
##   faction_roles: {faction: {role: id}}       new role keys only
##   faction_stage_roles: {faction: {"7": {role: id}}}  new keys only
const FRAGMENT_DIR := "res://content/g4"


static func _merge_fragments() -> void:
	var files: Array = []
	var dir := DirAccess.open(FRAGMENT_DIR)
	if dir == null:
		return
	for fn in dir.get_files():
		var name := String(fn).trim_suffix(".remap")
		if name.ends_with(".json") and not files.has(name):
			files.append(name)
	files.sort()
	for fn in files:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(FRAGMENT_DIR + "/" + fn))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Content: invalid JSON fragment %s" % fn)
			continue
		var frag: Dictionary = _normalize(parsed)
		for key in frag:
			var k := String(key)
			if k.begins_with("_"):
				continue
			if k == "armor_mult":
				_merge_armor(frag[key], fn)
			elif k == "faction_roles":
				_merge_roles(frag[key], fn, "roles")
			elif k == "faction_stage_roles":
				_merge_stage_roles(frag[key], fn)
			elif _data.has(k):
				var t: Dictionary = _data[k]
				for id in frag[key]:
					if t.has(id):
						push_error("Content: fragment %s redefines %s.%s (not allowed)" % [fn, k, id])
					else:
						t[id] = frag[key][id]
			else:
				push_error("Content: fragment %s has unknown table '%s'" % [fn, k])


static func _merge_armor(add: Dictionary, fn: String) -> void:
	var am: Dictionary = _data.get("weapons", {}).get("armor_mult", {})
	for wc in add:
		if not am.has(wc):
			am[wc] = {}
		for armor in add[wc]:
			if am[wc].has(armor):
				push_error("Content: fragment %s overrides armor_mult %s/%s" % [fn, wc, armor])
			else:
				am[wc][armor] = add[wc][armor]


static func _merge_roles(add: Dictionary, fn: String, field: String) -> void:
	for fid in add:
		var f: Dictionary = _data.get("factions", {}).get(fid, {})
		if f.is_empty():
			push_error("Content: fragment %s names unknown faction %s" % [fn, fid])
			continue
		if not f.has(field):
			f[field] = {}
		for role in add[fid]:
			if f[field].has(role) and String(f[field][role]) != "":
				push_error("Content: fragment %s overrides role %s.%s" % [fn, fid, role])
			else:
				f[field][role] = add[fid][role]


static func _merge_stage_roles(add: Dictionary, fn: String) -> void:
	for fid in add:
		var f: Dictionary = _data.get("factions", {}).get(fid, {})
		if f.is_empty():
			push_error("Content: fragment %s names unknown faction %s" % [fn, fid])
			continue
		if not f.has("stage_roles"):
			f["stage_roles"] = {}
		for st in add[fid]:
			if not f.stage_roles.has(st):
				f.stage_roles[st] = {}
			for role in add[fid][st]:
				if f.stage_roles[st].has(role):
					push_error("Content: fragment %s overrides stage role %s.%s.%s" % [fn, fid, st, role])
				else:
					f.stage_roles[st][role] = add[fid][st][role]


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
