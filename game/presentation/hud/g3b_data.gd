extends RefCounted
## G3b UI data helpers (owner: UI4). Contract: docs/CONTRACTS_G3b.md sections 3, 4 and 7.
## Maps (content/maps.json), research projects (content/research.json), playable stages,
## advancement rules, and the stage/research availability reasons the HUD shows on locked
## buttons. Pure reads: never mutates the world. Missing data degrades gracefully (River
## Crossing only, no research, "no gates").

const MAP_ORDER := ["river_crossing_s", "industrial_heartland_m", "valley_conquest_l", "ridge_bastion_m", "river_dam_m"]  # G6 (UI6a): survival maps
## Shown (disabled) when maps.json does not list them yet.
const MAP_FALLBACK := {
	"river_crossing_s": {"id": "river_crossing_s", "name": "River Crossing", "size": "s", "w": 96, "h": 96, "max_sides": 4},
	"industrial_heartland_m": {"id": "industrial_heartland_m", "name": "Industrial Heartland", "size": "m", "w": 160, "h": 160, "max_sides": 6},
	"valley_conquest_l": {"id": "valley_conquest_l", "name": "Valley Conquest", "size": "l", "w": 256, "h": 256, "max_sides": 8},
	"ridge_bastion_m": {"id": "ridge_bastion_m", "name": "Ridge Bastion (survival)", "size": "m", "w": 128, "h": 128, "max_sides": 4, "survival": true},
	"river_dam_m": {"id": "river_dam_m", "name": "River Dam (survival)", "size": "m", "w": 128, "h": 128, "max_sides": 4, "survival": true},
}
const SIZE_NAMES := {"s": "Small", "m": "Medium", "l": "Large"}

static var _cache: Dictionary = {}


## Content.table(name) when ORCH has added it to Content.FILES, else res://content/<name>.json.
static func _table(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var t: Dictionary = Content.table(name)
	if t.is_empty():
		var path := "res://content/%s.json" % name
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				t = Content._normalize(parsed)
	_cache[name] = t
	return t


## Every map listed in maps.json, keyed by id. Accepts {"maps": [...]} or {id: {...}}.
static func maps() -> Dictionary:
	var t := _table("maps")
	var out := {}
	if t.get("maps") is Array:
		for m in t.maps:
			if m is Dictionary and m.has("id"):
				out[String(m.id)] = m
	elif t.get("maps") is Dictionary:
		for k in t.maps:
			var m2: Dictionary = (t.maps[k] as Dictionary).duplicate()
			m2["id"] = String(k)
			out[String(k)] = m2
	else:
		for k in t:
			if not String(k).begins_with("_") and t[k] is Dictionary:
				var m3: Dictionary = (t[k] as Dictionary).duplicate()
				m3["id"] = String(k)
				out[String(k)] = m3
	return out


## Ordered picker rows: [{id, name, w, h, size, max_sides, present}]. River Crossing is always
## present (MapGen generates it with or without maps.json).
static func map_rows() -> Array:
	var listed := maps()
	var ids: Array = MAP_ORDER.duplicate()
	for k in listed:
		if not ids.has(k):
			ids.append(k)
	var rows: Array = []
	for id in ids:
		if listed.has(id) and not bool(listed[id].get("skirmish", true)):
			continue  # G7 (owner): mode-only maps (Last Protocol, SCALE7 test maps) never appear in skirmish
		var base: Dictionary = MAP_FALLBACK.get(id, {"id": id, "name": String(id).capitalize(), "size": "s", "w": 96, "h": 96, "max_sides": 4}).duplicate()
		var present: bool = listed.has(id) or id == "river_crossing_s"
		if listed.has(id):
			base.merge(listed[id], true)
		base["present"] = present
		rows.append(base)
	return rows


static func map_label(m: Dictionary) -> String:
	var t := "%s  (%s, %d x %d, up to %d sides)" % [String(m.get("name", m.get("id", "?"))),
		String(SIZE_NAMES.get(String(m.get("size", "s")), "?")), int(m.get("w", 0)), int(m.get("h", 0)), int(m.get("max_sides", 4))]
	if not bool(m.get("present", true)):
		t += "   (not built yet)"
	return t


static func map_row(id: String) -> Dictionary:
	for m in map_rows():
		if String(m.id) == id:
			return m
	return MAP_FALLBACK.river_crossing_s


## Stage ids marked playable_now in stages.json (ascending).
static func playable_stages() -> Array:
	var out: Array = []
	for st in Content.stages():
		if bool(st.get("playable_now", false)):
			out.append(int(st.id))
	out.sort()
	if out.is_empty():
		out.append(8)
	return out


## G10: faction-specific playable stages. Shadow Coalition unlocks 1–13 without flipping
## deferred stages' global playable_now (other factions keep shipped 7–10).
static func playable_stages_for(faction_id: String) -> Array:
	if String(faction_id) == "shadow_coalition":
		var coal: Array = []
		for st in Content.stages():
			coal.append(int(st.id))
		coal.sort()
		if coal.is_empty():
			for i in range(1, 14):
				coal.append(i)
		return coal
	return playable_stages()


static func stage_name(stage: int) -> String:
	for st in Content.stages():
		if int(st.id) == stage:
			return String(st.get("working_name", ""))
	return ""


## ["free", "standard", "simulation"] in that order when present.
static func advancement_ids() -> Array:
	var rules: Dictionary = Content.rules().get("advancement", {}).get("rules", {})
	var out: Array = []
	for k in ["free", "standard", "simulation"]:
		if rules.has(k):
			out.append(k)
	for k in rules:
		if not out.has(k) and not String(k).begins_with("_"):
			out.append(String(k))
	if out.is_empty():
		out.append("standard")
	return out


static func advancement_label(id: String) -> String:
	var r: Dictionary = Content.rules().get("advancement", {}).get("rules", {}).get(id, {})
	var mult := float(r.get("cost_mult", 1.0))
	return "%s  (advance cost x%s)" % [id.capitalize(), str(snappedf(mult, 0.01))]


# ------------------------------------------------------------------ research
## {project_id: def} from research.json; accepts {"projects": {...}} or a flat dict.
static func research_projects() -> Dictionary:
	var t := _table("research")
	var src: Dictionary = t.get("projects", t) if t.get("projects") is Dictionary else t
	var out := {}
	for k in src:
		if not String(k).begins_with("_") and src[k] is Dictionary:
			out[String(k)] = src[k]
	return out


static func project_name(pid: String, faction_id: String = "") -> String:
	var p: Dictionary = research_projects().get(pid, {})
	var names: Dictionary = p.get("names", {})
	if faction_id != "" and names.has(faction_id):
		return String(names[faction_id])
	return String(p.get("name", pid.capitalize()))


static func is_research_building(def_id: String) -> bool:
	return bool(Content.building(def_id).get("research", false))


## Ordered by for_stage, then content order.
static func project_ids_sorted() -> Array:
	var ps := research_projects()
	var ids: Array = ps.keys()
	var order := {}
	for i in ids.size():
		order[ids[i]] = i
	ids.sort_custom(func(a, b):
		var sa := int(ps[a].get("for_stage", 8))
		var sb := int(ps[b].get("for_stage", 8))
		return sa < sb if sa != sb else int(order[a]) < int(order[b]))
	return ids


## Stage / research lock reason for a unit, building or production def ("" = available).
## Mirrors the sim's reason strings ("Requires Stage 8", "Requires research: Digital Networks").
static func lock_reason(d: Dictionary, faction: Dictionary, faction_id: String) -> String:
	var stage := int(faction.get("stage", 8))
	if stage < int(d.get("stage_min", 7)):
		return "Requires Stage %d" % int(d.get("stage_min", 7))
	if d.has("stage_max") and stage > int(d.stage_max):
		return "Not available after Stage %d" % int(d.stage_max)
	var done: Array = faction.get("research", {}).get("done", [])
	for r in d.get("requires_research", []):
		if not done.has(String(r)):
			return "Requires research: %s" % project_name(String(r), faction_id)
	return ""


## Production item lock: the item's own gates, then every unit def it spawns.
static func production_lock(item: String, faction: Dictionary, faction_id: String) -> String:
	var p: Dictionary = Content.production(item)
	var r := lock_reason(p, faction, faction_id)
	if r != "":
		return r
	for u in p.get("spawns", []):
		r = lock_reason(Content.unit(String(u)), faction, faction_id)
		if r != "":
			return r
	return ""
