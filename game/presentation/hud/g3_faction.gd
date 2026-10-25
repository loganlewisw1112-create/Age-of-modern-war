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


## G5 (UI5b): the build card is split into category pages (Base / Military / Air / Naval / Support,
## Tab cycles them). A def's page is its `build_cat` field when set, else derived from its flags.
const BUILD_CATS := ["base", "military", "air", "naval", "support"]
const BUILD_CAT_NAMES := {"base": "Base", "military": "Military", "air": "Air", "naval": "Naval", "support": "Support"}
## Letters a generated build key avoids (pan W/D, Deploy E, Lay mine M, Plant charge O sit on the
## engineer card too); a data hotkey keeps its letter.
## G6 (UI6b): J / U / X / Z are the engineer-card G6 keys (minefield, sweep, rail, garrison / tow), so a
## generated key avoids them too; they (and E / M / O) are only a last resort on a crowded page.
const AVOID_KEYS := ["W", "D", "E", "M", "O", "J", "U", "X", "Z"]
const LAST_RESORT_KEYS := ["E", "M", "O", "J", "U", "X", "Z"]


static func _flag(d: Dictionary, k: String) -> bool:
	if not d.has(k):
		return false
	var v = d[k]
	if v == null or (typeof(v) == TYPE_BOOL and not v):
		return false
	return not (typeof(v) == TYPE_STRING and String(v) == "")


static func build_category(def_id: String) -> String:
	var d := Content.building(def_id)
	var c := String(d.get("build_cat", ""))
	if BUILD_CATS.has(c):
		return c
	if _flag(d, "air_field"):
		return "air"
	if _flag(d, "shore") or _flag(d, "pier") or _flag(d, "near_water"):
		return "naval"
	if _flag(d, "hospital") or _flag(d, "field_hospital"):
		return "support"
	if not (d.get("produces", []) as Array).is_empty() or _flag(d, "weapon") or _flag(d, "wall") or _flag(d, "gate") or _flag(d, "tower"):
		return "military"
	return "base"


## The non-empty build pages of a faction, in BUILD_CATS order: [{cat, name, defs: [...]}].
static func build_pages(faction_id: String) -> Array:
	var by := {}
	for b in Content.buildable_for(faction_id):
		var c := build_category(String(b))
		if not by.has(c):
			by[c] = []
		by[c].append(String(b))
	var out: Array = []
	for c in BUILD_CATS:
		if by.has(c):
			out.append({"cat": c, "name": BUILD_CAT_NAMES[c], "defs": by[c]})
	return out


## Build-card hotkey for a building def, unique within its category page. `used` holds
## "<cat>:<KEY>" entries (one card = one dict). Order: the data hotkey, then the letters of the
## name, then ALT_KEYS, then A-Z; never a RESERVED_BUILD_KEYS letter (G2 order keys).
static func build_hotkey(def_id: String, used: Dictionary) -> String:
	var d := Content.building(def_id)
	var cat := build_category(def_id)
	var hk := String(d.get("hotkey", "")).to_upper()
	var cand: Array = []
	if hk != "":
		cand.append(hk)
	for ch in String(d.get("name", def_id)).to_upper():
		if ch >= "A" and ch <= "Z" and not AVOID_KEYS.has(ch):
			cand.append(ch)
	for ak in ALT_KEYS:
		if not AVOID_KEYS.has(ak):
			cand.append(ak)
	for i in 26:
		var ch := String.chr(65 + i)
		if not AVOID_KEYS.has(ch):
			cand.append(ch)
	cand.append_array(LAST_RESORT_KEYS)
	for k in cand:
		if RESERVED_BUILD_KEYS.has(k) or used.has(cat + ":" + String(k)):
			continue
		used[cat + ":" + String(k)] = true
		return String(k)
	return ""
