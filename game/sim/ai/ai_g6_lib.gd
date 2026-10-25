extends RefCounted
## AiG6 shared helpers (owner: AI7-USE): G6 role -> def lookup, production item lookup, queue / build.
## Defs: Content.role(faction, "g6_<role>") first (CONTENT6 faction_roles), else the CONTRACTS_G6 §3
## id of the role: faction letter + page id (`docs/g6_art_kit/items.json` page_id).

const U = preload("res://sim/ai/ai_util.gd")
const Econ = preload("res://sim/ai/ai_econ.gd")

## role -> page id per faction letter [a, b, m] ("" = the faction has none). "s:" = a shared def.
const PAGE_IDS := {
	"company_hq": ["company_hq", "company_hq", "company_hq"],
	"radar": ["radar_station", "", "pulse_spire2"],
	"sam": ["sam_site", "flak_battery", "pulse_spire2"],
	"cdrone": ["laser_ciws", "net_post", "jammer_obelisk"],
	"at_def": ["atgm_bunker", "pak_nest", "arc_pylon"],
	"inf_def": ["popup_turret", "pillbox", "sentry_mine"],
	"arty_def": ["howitzer_pit", "mortar_pit", "mass_driver"],
	"garrison_bld": ["s:garrison_bld", "s:garrison_bld", "s:garrison_bld"],
	"fob": ["fob", "", ""],
	"sandbags": ["s:sandbags", "s:sandbags", "s:sandbags"],
	"minefield": ["s:minefield", "s:minefield", "s:minefield"],
	"exo_garage": ["exo_garage", "", ""],
	"eod": ["eod", "satchel_sappers", "breacher_crawler"],
	"mine_clearer": ["mine_clearer", "armored_dozer", ""],
	"mine_layer": ["", "", "spider_layer"],
	"sub": ["submarine", "", ""],
	"carrier": ["carrier", "", ""],
	"aa_team": ["manpads", "scrap_aa", "shield_drone"],
	"jammer_team": ["", "jammer_team", ""],
	"drone_cc": ["drone_cc", "", "hive_node"],
	"radar_air": ["awacs", "recon_plane", ""],
}
const LETTER := {"human_a": "a_", "human_b": "b_", "machine": "m_"}
const MIN_CREDITS := 150


static var _any := {}


## Does the faction have any G6 def at all (content loaded)? Cached per faction + content load.
static func any_def(w: SimWorld, fid: int) -> bool:
	var fac := U.fac(w, fid)
	var key := "%s:%d" % [fac, Content.ids("buildings").size() + Content.ids("units").size()]
	if _any.has(key):
		return bool(_any[key])
	var ok := false
	for r in PAGE_IDS:
		if raw_def(fac, String(r)) != "":
			ok = true
			break
	_any[key] = ok
	return ok


## The def id of a G6 role for a faction, whether or not the side may use it yet ("" = none).
static func raw_def(fac: String, r: String) -> String:
	var cr := Content.role(fac, "g6_" + r, 10)
	if cr != "":
		return cr
	var row: Array = PAGE_IDS.get(r, [])
	var i: int = ["human_a", "human_b", "machine"].find(fac)
	if i < 0 or i >= row.size() or String(row[i]) == "":
		return ""
	var pid := String(row[i])
	var id := ("s_" + pid.substr(2)) if pid.begins_with("s:") else String(LETTER.get(fac, "")) + pid
	if not Content.building(id).is_empty() or not Content.unit(id).is_empty() or not Content.production(id).is_empty():
		return id
	return ""


## The def of a G6 role this side may build / produce now (stage, research, faction), else "".
static func rdef(w: SimWorld, fid: int, r: String) -> String:
	var cr := U.role(w, fid, "g6_" + r)
	if cr != "":
		return cr
	var id := raw_def(U.fac(w, fid), r)
	if id == "" or not U.available(w, fid, id):
		return ""
	return id


static var _items := {}


## Production item (this faction's or shared) that spawns unit def `ud`, available now, else "".
static func item_for(w: SimWorld, fid: int, ud: String) -> String:
	if ud == "":
		return ""
	if not Content.production(ud).is_empty():
		return ud if U.available(w, fid, ud) else ""
	var fac := U.fac(w, fid)
	var key := fac + ":" + ud
	if not _items.has(key):
		var found := ""
		for pid in Content.ids("production"):
			var p := Content.production(String(pid))
			var pf := String(p.get("faction", ""))
			if (pf == fac or pf == "shared") and (p.get("spawns", []) as Array).has(ud):
				found = String(pid)
				break
		_items[key] = found
	var it := String(_items[key])
	return it if it != "" and U.available(w, fid, it) else ""


## A built building of this side whose def is `def_id` and whose queue has room, else null.
static func facility(ctx: Dictionary, def_id: String, max_q: int = 2):
	for b in ctx.buildings:
		if b.built and String(b.def) == def_id and (b.queue as Array).size() < max_q:
			return b
	return null


static func count_def(ctx: Dictionary, def_id: String) -> int:
	var n := 0
	for b in ctx.buildings:
		if String(b.def) == def_id:
			n += 1
	for e in ctx.units:
		if String(e.def) == def_id:
			n += 1
	return n


## Queues one production item at its facility (pop, cost, bank respected). True when accepted.
static func queue_item(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, item: String, key: String) -> bool:
	if item == "" or not bool(ctx.get("g6_spend", true)):
		return false
	var p := Content.production(item)
	var fac = facility(ctx, String(p.get("facility", "")))
	if fac == null:
		return false
	var pop := 0
	for u in p.get("spawns", []):
		pop += U.pop_of(String(u))
	var f: Dictionary = w.factions[fid]
	if int(f.pop) + int(ctx.queued_pop) + pop > int(f.pop_cap) or w.can_afford(fid, p.get("cost", {})) != "":
		return false
	if U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(fac.id), "item": item}, key):
		ctx.queued_pop = int(ctx.queued_pop) + pop
		return true
	return false


## Builds `def_id` near `at` (or the default anchor) with up to two free builders. True when accepted.
static func build_at(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, def_id: String, at: Vector2, key: String) -> bool:
	if def_id == "" or not bool(ctx.get("g6_spend", true)) or U.blocked(st, w, key) or int(ctx.unfinished_total) > 1:
		return false
	var cost: Dictionary = Content.building(def_id).get("cost", {})
	if w.can_afford(fid, cost) != "" or int(w.factions[fid].credits) < int(cost.get("credits", 0)) + MIN_CREDITS:
		return false
	var origin := Econ.find_origin(w, fid, st, def_id, at)
	if origin.x < 0:
		U.set_backoff(st, w, key, 600)
		return false
	var size := int(Content.building(def_id).get("size", 2))
	var picks := Econ._pick_engineers(ctx, Vector2(origin) + Vector2(size, size) * 0.5, 2)
	if picks.is_empty():
		return false
	if U.submit(w, fid, st, {"type": "build", "unit_ids": picks, "def": def_id, "origin": origin}, key, {"origin": origin}):
		for id in picks:
			ctx.busy[id] = true
		return true
	return false


static func bump(g: Dictionary, k: String, n: int = 1) -> void:
	g[k] = int(g.get(k, 0)) + n




static var _api := {}


## Owner API present in the loaded script (static or not)? Cached per script path + name.
static func api(s: Script, fn: String) -> bool:
	if s == null:
		return false
	var key := s.resource_path + ":" + fn
	if _api.has(key):
		return bool(_api[key])
	var ok := false
	for m in s.get_script_method_list():
		if String(m.name) == fn:
			ok = true
			break
	_api[key] = ok
	return ok


## Calls an owner's static API by name (decoupled from the owner's file at parse time: an owner's
## in-progress rewrite never breaks the AI's compile); `dflt` when the function is missing.
static func callf(s: Script, fn: String, args: Array, dflt):
	if not api(s, fn):
		return dflt
	return s.callv(fn, args)


static var _sys := {}


## A G6 system script by file name, loaded lazily (never preloaded: an owner's broken in-progress
## file must not break the AI's compile chain). null when missing.
static func sys(name: String) -> Script:
	if not _sys.has(name):
		var path := "res://sim/systems/%s.gd" % name
		_sys[name] = load(path) if ResourceLoader.exists(path) else null
	return _sys[name]
