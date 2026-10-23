extends RefCounted
## G3a presentation helpers (owner: UI3): faction roles, side colours, teams, energy/air flags.
## Never hard-code def names in presentation: ask for a role (Content.role) or a flag.

## Command-card keys the G2 order buttons own; a build hotkey from data that collides gets a
## stable substitute (first free letter of ALT_KEYS) so every button keeps a working key.
const RESERVED_BUILD_KEYS := ["F", "Q", "S", "H", "A", "P", "R"]
const ALT_KEYS := ["N", "K", "J", "U", "Y", "X", "Z"]


static func faction_def(w: SimWorld, fid: int) -> String:
	if w != null and w.factions.has(fid):
		return String(w.factions[fid].get("faction_def", "human_a"))
	return "human_a"


static func role_def(w: SimWorld, fid: int, role: String) -> String:
	return Content.role(faction_def(w, fid), role)


## Display name of a role's def (building or production item), e.g. "Fortified Barracks".
static func role_name(faction_id: String, role: String, fallback: String = "") -> String:
	var d := Content.role(faction_id, role)
	if d == "":
		return fallback
	var b := Content.building(d)
	if not b.is_empty():
		return String(b.get("name", d))
	var p := Content.production(d)
	if not p.is_empty():
		return String(p.get("name", d)).get_slice(" (", 0)
	return String(Content.unit(d).get("name", fallback if fallback != "" else d))


## The neutral river bridge (buildings.json `neutral_structure`; the only such def), so
## presentation does not compare def names.
static func is_bridge(def_id: String) -> bool:
	return bool(Content.building(def_id).get("neutral_structure", false))


## First unit def a faction's role item spawns (e.g. role "heavy" -> "mbt"/"b_rebuilt_mbt"/
## "m_walker"); tries the fallback roles in order when the faction has no such role.
static func role_unit(w: SimWorld, fid: int, roles: Array) -> String:
	for r in roles:
		var u := item_units(role_def(w, fid, String(r)))
		if not u.is_empty():
			return String(u[0])
	return ""


## Unit def ids a production item spawns (production.json "spawns").
static func item_units(item: String) -> Array:
	var p := Content.production(item)
	var u = p.get("spawns", [])
	return u if u is Array else []


## Side colour: the menu's per-slot colour (cfg.sides[i].color) when present, else the sim's.
static func side_color(w: SimWorld, fid: int) -> Color:
	if w == null:
		return Color(0.85, 0.85, 0.8)
	var sides: Array = w.cfg.get("sides", [])
	if fid >= 0 and fid < sides.size() and String(sides[fid].get("color", "")) != "":
		return Color.html(String(sides[fid].color))
	if w.factions.has(fid):
		return Color.html(String(w.factions[fid].color))
	return Color(0.85, 0.85, 0.8)


static func team_of(w: SimWorld, fid: int) -> int:
	if w != null and w.factions.has(fid):
		return int(w.factions[fid].get("team", fid))
	return -1


static func is_ally(w: SimWorld, a: int, b: int) -> bool:
	if a == b or not w.factions.has(a) or not w.factions.has(b):
		return false
	return team_of(w, a) == team_of(w, b)


static func allies_of(w: SimWorld, fid: int) -> Array:
	var out: Array = []
	for f in w.factions:
		if int(f) != fid and is_ally(w, fid, int(f)):
			out.append(int(f))
	return out


## Teams in the match: {team: [fids...]} in fid order.
static func teams(w: SimWorld) -> Dictionary:
	var out := {}
	for f in w.factions:
		var t := team_of(w, int(f))
		if not out.has(t):
			out[t] = []
		out[t].append(int(f))
	return out


static func is_energy(def_id: String) -> bool:
	return bool(Content.unit(def_id).get("energy", false))


static func is_air(def_id: String) -> bool:
	var u := Content.unit(def_id)
	return bool(u.get("is_air", false)) or String(u.get("move_class", "")) == "air"


## "Charge" for Machine energy units, "Fuel" otherwise.
static func fuel_word(def_id: String) -> String:
	return "Charge" if is_energy(def_id) else "Fuel"


## Recharge radius of a building def (0 if it has none).
static func recharge_radius(def_id: String) -> float:
	return float(Content.building(def_id).get("recharge", 0))


## Build-card hotkey for a building def: the data hotkey unless it collides with a G2 order key
## or a key already used on this card (`used`), else the first free ALT_KEYS letter.
static func build_hotkey(def_id: String, used: Dictionary) -> String:
	var hk := String(Content.building(def_id).get("hotkey", "")).to_upper()
	if hk != "" and not RESERVED_BUILD_KEYS.has(hk) and not used.has(hk):
		used[hk] = true
		return hk
	for k in ALT_KEYS:
		if not used.has(k):
			used[k] = true
			return k
	return ""
