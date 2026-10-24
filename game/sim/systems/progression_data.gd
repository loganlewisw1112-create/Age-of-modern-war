extends RefCounted
## Progression data helpers (owner: STG4, CONTRACTS_G3b section 3). Preload, no class_name:
##   const PData = preload("res://sim/systems/progression_data.gd")
## Research table access, stage/research availability reasons, stage-aware roles, advancement
## rules (rules.json `advancement`) and the gate checklist. Pure reads: never mutates the world.

static var _research: Dictionary = {}
static var _research_loaded: bool = false


# ================================================================ research table
## content/research.json (via Content once ORCH adds "research" to Content.FILES; read directly until then).
static func research_table() -> Dictionary:
	var t: Dictionary = Content.table("research")
	if not t.is_empty():
		return t
	if not _research_loaded:
		_research_loaded = true
		var text := FileAccess.get_file_as_string("res://content/research.json")
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			_research = Content._normalize(parsed)
		else:
			push_error("Progression: missing or invalid content/research.json")
	return _research


static func project(id: String) -> Dictionary:
	return research_table().get(id, {})


## Project ids in content order (keys starting with "_" are metadata).
static func project_ids() -> Array:
	var out := []
	for k in research_table():
		if not String(k).begins_with("_"):
			out.append(String(k))
	return out


## Display name for a project, honouring per-faction `names`.
static func project_name(id: String, faction_def: String = "") -> String:
	var p := project(id)
	if p.is_empty():
		return id
	var names: Dictionary = p.get("names", {})
	if faction_def != "" and names.has(faction_def):
		return String(names[faction_def])
	return String(p.get("name", id))


static func has_research(w: SimWorld, fid: int, id: String) -> bool:
	return w.factions.has(fid) and (w.factions[fid].research.done as Array).has(id)


# ================================================================ availability
## "" when def `d` (unit, building or production) is usable by side fid now, else the reason
## shown to the player: "Requires Stage 8", "Not available after Stage 8", "Requires research: X".
static func unavailable_reason(w: SimWorld, fid: int, d: Dictionary) -> String:
	if not w.factions.has(fid):
		return ""
	var f: Dictionary = w.factions[fid]
	var stage := int(f.stage)
	if stage < int(d.get("stage_min", 7)):
		return "Requires Stage %d" % int(d.get("stage_min", 7))
	if d.has("stage_max") and stage > int(d.stage_max):
		return "Not available after Stage %d" % int(d.stage_max)
	for rid in d.get("requires_research", []):
		if not (f.research.done as Array).has(String(rid)):
			return "Requires research: %s" % project_name(String(rid), String(f.faction_def))
	return ""


## Production item check: the item itself plus every unit def it spawns.
static func production_reason(w: SimWorld, fid: int, item: String) -> String:
	var p := Content.production(item)
	var r := unavailable_reason(w, fid, p)
	if r != "":
		return r
	for u in p.get("spawns", []):
		r = unavailable_reason(w, fid, Content.unit(String(u)))
		if r != "":
			return r
	return ""


## Stage-aware role lookup for a side (Content.role with the side's current stage).
static func role(w: SimWorld, fid: int, role_name: String) -> String:
	var f: Dictionary = w.factions[fid]
	return Content.role(String(f.faction_def), role_name, int(f.stage))


# ================================================================ advancement rules
static func advancement() -> Dictionary:
	return Content.rules().get("advancement", {})


static func gates_for(to_stage: int) -> Dictionary:
	return advancement().get("gates", {}).get(str(to_stage), {})


static func transition_ticks() -> int:
	return maxi(1, int(round(float(advancement().get("transition_seconds", 60)) * SimWorld.TICK_RATE)))


static func cost_mult(w: SimWorld) -> float:
	var mode := String(w.cfg.get("advancement", "standard"))
	return float(advancement().get("rules", {}).get(mode, {}).get("cost_mult", 1.0))


## Advancement cost to reach `to_stage` for this match (base cost x rules multiplier, rounded).
static func advance_cost(w: SimWorld, to_stage: int) -> Dictionary:
	var base: Dictionary = gates_for(to_stage).get("cost", {})
	var m := cost_mult(w)
	var out := {}
	for k in SimWorld.LEDGER_KEYS:
		if base.has(k):
			out[k] = int(round(float(base[k]) * m))
	return out


static func cost_label(cost: Dictionary) -> String:
	var parts := []
	for k in SimWorld.LEDGER_KEYS:
		if int(cost.get(k, 0)) > 0:
			parts.append("%d %s" % [int(cost[k]), k])
	return "free" if parts.is_empty() else " + ".join(parts)
