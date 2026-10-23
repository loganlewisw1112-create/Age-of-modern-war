extends RefCounted
## Victory (owner: agent V3-victory; G1 agent B). Contract: docs/CONTRACTS_G3a.md section 4.
## - A side with no HQ building (built or unfinished; def flag is_hq) becomes alive=false and
##   SideEliminated {faction} is emitted once. A TEAM is out when all its sides are out
##   (TeamEliminated {team} once).
## - cfg.victory: hq_elimination | territory | hold_bridge | combined | endless.
##   Single modes may carry cfg.victory_params ({"percent": 60} / {"seconds": 300}).
##   combined uses cfg.victory_rules = {"op": "and"|"or", "terms": [{type, percent?, seconds?}]}.
## - Each alive team is evaluated every tick; a team wins when the expression is true for it.
##   If several teams satisfy it on the same tick, the one satisfying more terms wins, then the
##   lowest team id (deterministic). If no team is alive at all the match ends as a draw.
##   There is NO implicit "last team standing" win outside hq_elimination: under territory AND
##   hold_bridge the survivor must still meet the terms (eliminated sides never contest).
## - Endless never ends; eliminations still happen.
## - match_state = {ended, winner (lowest fid of the winning team, G1 compat), winner_team,
##   winners [fids], reason, terms [satisfied term types], end_tick}; MatchEnded carries the same.
## - Hold the bridge: sampled every BRIDGE_EVERY ticks; a team holds it while the bridge is intact
##   and only its (alive) units are within BRIDGE_RADIUS of the bridge entity's pos. Consecutive
##   seconds; reset when contested, emptied or the bridge is ruined.
##   Saved: w.sys_state.victory = {bridge_holder, bridge_secs, out_teams: [team]}.
## - Territory: sim/systems/territory.gd, ticked from here (no SYSTEM_ORDER change needed).

const Territory = preload("res://sim/systems/territory.gd")
const MapGen = preload("res://sim/map_gen.gd")

const MODES := ["hq_elimination", "territory", "hold_bridge", "combined", "endless"]
const TERM_TYPES := ["hq_elimination", "territory", "hold_bridge"]
const BRIDGE_RADIUS := 4.0
const BRIDGE_EVERY := 20
const DEFAULT_SECONDS := 300
const PERCENT_MIN := 10.0
const PERCENT_MAX := 100.0
const SECONDS_MIN := 30
const SECONDS_MAX := 3600

static var _hq_defs: Dictionary = {}
static var _bridge_maps: Dictionary = {}   # "map_id:seed" -> bool (map has bridge cells)


static func _is_hq(def_id: String) -> bool:
	if not _hq_defs.has(def_id):
		_hq_defs[def_id] = bool(Content.building(def_id).get("is_hq", false))
	return _hq_defs[def_id]


static func _vstate(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("victory"):
		w.sys_state["victory"] = {"bridge_holder": -1, "bridge_secs": 0, "out_teams": []}
	return w.sys_state["victory"]


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	if w.match_state.get("ended", false):
		return
	_eliminate(w)
	Territory.tick(w)
	if w.tick % BRIDGE_EVERY == 0:
		_bridge_sample(w)
	var mode := String(w.cfg.get("victory", "hq_elimination"))
	if mode == "endless":
		return
	var teams := alive_teams(w)
	if teams.is_empty():
		_end(w, -1, "all_eliminated", [])
		return
	var rules := rules_of_world(w)
	var best := -1
	var best_terms := []
	for team in teams:
		var sat := []
		var ok := String(rules.op) == "and"
		for t in rules.terms:
			var yes := term_satisfied(w, int(team), t)
			if yes:
				sat.append(String(t.type))
			ok = (ok and yes) if String(rules.op) == "and" else (ok or yes)
		if (rules.terms as Array).is_empty():
			ok = false
		if ok and (best < 0 or sat.size() > best_terms.size()):
			best = int(team)
			best_terms = sat
	if best >= 0:
		_end(w, best, mode, best_terms)


static func _eliminate(w: SimWorld) -> void:
	var has_hq := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building" and _is_hq(String(e.def)):
			has_hq[int(e.owner)] = true
	var changed := false
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		if f.alive and not has_hq.has(int(fid)):
			f.alive = false
			changed = true
			w.emit("SideEliminated", {"faction": int(fid), "team": team_of(w, int(fid))})
	if not changed:
		return
	var vs := _vstate(w)
	var out: Array = vs.out_teams
	for team in all_teams(w):
		if not team_alive(w, int(team)) and not out.has(int(team)):
			out.append(int(team))
			w.emit("TeamEliminated", {"team": int(team)})


static func _end(w: SimWorld, team: int, reason: String, terms: Array) -> void:
	var winners := []
	if team >= 0:
		for fid in w.factions:
			if team_of(w, int(fid)) == team:
				winners.append(int(fid))
	winners.sort()
	var winner: int = winners[0] if not winners.is_empty() else SimWorld.NEUTRAL
	w.match_state.ended = true
	w.match_state.winner = winner
	w.match_state.winner_team = team
	w.match_state.winners = winners.duplicate()
	w.match_state.reason = reason
	w.match_state.terms = terms.duplicate()
	w.match_state.end_tick = w.tick
	w.emit("MatchEnded", {"winner": winner, "winner_team": team, "winners": winners.duplicate(),
		"reason": reason, "terms": terms.duplicate()})


# ================================================================ teams
static func team_of(w: SimWorld, fid: int) -> int:
	if not w.factions.has(fid):
		return -1
	return int(w.factions[fid].get("team", fid))


## Every team id present in the match, ascending.
static func all_teams(w: SimWorld) -> Array:
	var out := []
	for fid in w.factions:
		var t := team_of(w, int(fid))
		if not out.has(t):
			out.append(t)
	out.sort()
	return out


static func team_alive(w: SimWorld, team: int) -> bool:
	for fid in w.factions:
		if team_of(w, int(fid)) == team and bool(w.factions[fid].alive):
			return true
	return false


## Teams with at least one side still holding an HQ, ascending.
static func alive_teams(w: SimWorld) -> Array:
	var out := []
	for t in all_teams(w):
		if team_alive(w, int(t)):
			out.append(t)
	return out


# ================================================================ terms
## The effective rule expression {op, terms:[{type, percent?, seconds?}]} for a config.
## endless -> no terms (never satisfied). Single modes -> one term with params/defaults.
static func rules_of(c: Dictionary) -> Dictionary:
	var mode := String(c.get("victory", "hq_elimination"))
	if mode == "endless":
		return {"op": "or", "terms": []}
	var raw := []
	var op := "and"
	if mode == "combined":
		var vr = c.get("victory_rules", {})
		if typeof(vr) == TYPE_DICTIONARY:
			op = String(vr.get("op", "and"))
			var rt = vr.get("terms", [])
			if typeof(rt) == TYPE_ARRAY:
				raw = rt
	else:
		var t := {"type": mode}
		var p = c.get("victory_params", {})
		if typeof(p) == TYPE_DICTIONARY:
			if mode == "territory" and p.has("percent"):
				t.percent = p.percent
			if mode == "hold_bridge" and p.has("seconds"):
				t.seconds = p.seconds
		raw = [t]
	var terms := []
	for t in raw:
		if typeof(t) == TYPE_DICTIONARY:
			terms.append(_norm_term(t))
	return {"op": op, "terms": terms}


static func _norm_term(t: Dictionary) -> Dictionary:
	var ty := String(t.get("type", ""))
	var out := {"type": ty}
	if ty == "territory":
		out.percent = float(t.get("percent", Content.rules().get("territory", {}).get("default_percent", 60)))
	elif ty == "hold_bridge":
		out.seconds = int(t.get("seconds", Content.rules().get("hold_bridge", {}).get("default_seconds", DEFAULT_SECONDS)))
	return out


## Cached per world (cfg never changes mid-match; w.cache is rebuilt after load).
static func rules_of_world(w: SimWorld) -> Dictionary:
	var r = w.cache.get("victory_rules")
	if r == null:
		r = rules_of(w.cfg)
		w.cache["victory_rules"] = r
	return r


static func term_satisfied(w: SimWorld, team: int, t: Dictionary) -> bool:
	match String(t.get("type", "")):
		"hq_elimination":
			if not team_alive(w, team):
				return false
			for other in alive_teams(w):
				if int(other) != team:
					return false
			return true
		"territory":
			return Territory.percent(w, team) >= float(t.get("percent", 60.0)) - 0.0001
		"hold_bridge":
			var vs := _vstate(w)
			return int(vs.bridge_holder) == team and int(vs.bridge_secs) >= int(t.get("seconds", DEFAULT_SECONDS))
	return false


# ================================================================ hold the bridge
## The neutral bridge structure (kind "structure" with cells), or null when the map has none.
static func bridge_entity(w: SimWorld):
	var bid = w.cache.get("victory_bridge_id")
	if bid != null:
		var b = w.entities.get(int(bid))
		if b != null:
			return b
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "structure" and e.has("cells"):
			w.cache["victory_bridge_id"] = int(id)
			return e
	return null


static func _bridge_sample(w: SimWorld) -> void:
	var vs := _vstate(w)
	var b = bridge_entity(w)
	if b == null or String(b.get("state", "intact")) != "intact":
		vs.bridge_holder = -1
		vs.bridge_secs = 0
		return
	var bp: Vector2 = b.pos
	var r2 := BRIDGE_RADIUS * BRIDGE_RADIUS
	var holder := -1
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		var fid := int(e.owner)
		if not w.factions.has(fid) or not bool(w.factions[fid].alive):
			continue
		if (e.pos as Vector2).distance_squared_to(bp) > r2:
			continue
		var t := team_of(w, fid)
		if holder == -1:
			holder = t
		elif holder != t:
			holder = -2
			break
	if holder < 0:
		vs.bridge_holder = -1
		vs.bridge_secs = 0
	elif int(vs.bridge_holder) != holder:
		vs.bridge_holder = holder
		vs.bridge_secs = 0
	else:
		vs.bridge_secs = int(vs.bridge_secs) + BRIDGE_EVERY / SimWorld.TICK_RATE


# ================================================================ HUD
## Checklist for the HUD: {mode, op, ended, winner_team, team, team_alive,
##   terms: [{type, satisfied, value, target, label, ...type extras}]}.
## hq_elimination: value = enemy teams still alive (target 0), own_hqs, enemy_hqs.
## territory: value = percent owned, target = percent needed, owned, total.
## hold_bridge: value = consecutive seconds held by this team, target = seconds, holder team,
##   contested (another team holds or the span is shared), bridge_state.
static func progress(w: SimWorld, team: int) -> Dictionary:
	var rules := rules_of_world(w)
	var out := {"mode": String(w.cfg.get("victory", "hq_elimination")), "op": String(rules.op),
		"ended": bool(w.match_state.get("ended", false)),
		"winner_team": int(w.match_state.get("winner_team", -1)), "team": team,
		"team_alive": team_alive(w, team), "terms": []}
	for t in rules.terms:
		var row := {"type": String(t.type), "satisfied": term_satisfied(w, team, t)}
		match String(t.type):
			"hq_elimination":
				var enemies := 0
				for other in alive_teams(w):
					if int(other) != team:
						enemies += 1
				var own := 0
				var foe := 0
				for id in w.entities:
					var e: Dictionary = w.entities[id]
					if e.kind == "building" and _is_hq(String(e.def)) and w.factions.has(int(e.owner)):
						if team_of(w, int(e.owner)) == team:
							own += 1
						else:
							foe += 1
				row.merge({"value": enemies, "target": 0, "own_hqs": own, "enemy_hqs": foe,
					"label": "Destroy every enemy HQ (%d enemy team%s left)" % [enemies, "" if enemies == 1 else "s"]})
			"territory":
				var pct := Territory.percent(w, team)
				row.merge({"value": pct, "target": float(t.percent), "owned": Territory.owned_count(w, team),
					"total": int(Territory.state(w).total),
					"label": "Control %d%% of the map (%d%% now)" % [int(t.percent), int(floor(pct))]})
			"hold_bridge":
				var vs := _vstate(w)
				var mine := int(vs.bridge_holder) == team
				var b = bridge_entity(w)
				row.merge({"value": int(vs.bridge_secs) if mine else 0, "target": int(t.seconds),
					"holder": int(vs.bridge_holder), "contested": not mine and int(vs.bridge_holder) != -1,
					"bridge_state": String(b.get("state", "intact")) if b != null else "none",
					"label": "Hold the bridge for %d s (%d s held)" % [int(t.seconds), int(vs.bridge_secs) if mine else 0]})
		out.terms.append(row)
	return out


# ================================================================ validation
## Returns "" or a human-readable reason. `map` (optional) is a generated map dict used for the
## bridge check; when omitted the configured map is generated once per (map, seed) and cached.
static func validate_rules(c: Dictionary, map: Dictionary = {}) -> String:
	var mode := String(c.get("victory", "hq_elimination"))
	if not MODES.has(mode):
		return "Unsupported victory condition '%s'." % mode
	var params = c.get("victory_params", {})
	if typeof(params) != TYPE_DICTIONARY:
		return "Victory parameters must be a dictionary."
	var vr = c.get("victory_rules", null)
	if mode == "endless":
		if typeof(vr) == TYPE_DICTIONARY and typeof(vr.get("terms", [])) == TYPE_ARRAY and not (vr.get("terms", []) as Array).is_empty():
			return "Endless cannot be combined with other victory terms."
		return ""
	var terms := []
	if mode == "combined":
		if typeof(vr) != TYPE_DICTIONARY:
			return "Combined victory needs victory_rules {op, terms}."
		var op := String(vr.get("op", ""))
		if op != "and" and op != "or":
			return "Victory rule operator must be 'and' or 'or' (got '%s')." % op
		var raw = vr.get("terms", [])
		if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
			return "Combined victory needs at least one term."
		terms = raw
	else:
		var t := {"type": mode}
		if mode == "territory" and params.has("percent"):
			t.percent = params.percent
		if mode == "hold_bridge" and params.has("seconds"):
			t.seconds = params.seconds
		terms = [t]
	var seen := {}
	var needs_bridge := false
	for t in terms:
		if typeof(t) != TYPE_DICTIONARY:
			return "Each victory term must be a dictionary."
		var ty := String(t.get("type", ""))
		if ty == "endless":
			return "Endless cannot be combined with other victory terms."
		if not TERM_TYPES.has(ty):
			return "Unknown victory term '%s'." % ty
		if seen.has(ty):
			return "Duplicate victory term '%s'." % ty
		seen[ty] = true
		if ty == "territory" and t.has("percent"):
			var p = t.percent
			if not (typeof(p) == TYPE_INT or typeof(p) == TYPE_FLOAT) or float(p) < PERCENT_MIN or float(p) > PERCENT_MAX:
				return "Territory percent must be between %d and %d (got %s)." % [int(PERCENT_MIN), int(PERCENT_MAX), str(p)]
		if ty == "hold_bridge":
			needs_bridge = true
			if t.has("seconds"):
				var s = t.seconds
				if not (typeof(s) == TYPE_INT or typeof(s) == TYPE_FLOAT) or float(s) < SECONDS_MIN or float(s) > SECONDS_MAX:
					return "Hold-the-bridge time must be between %d and %d seconds (got %s)." % [SECONDS_MIN, SECONDS_MAX, str(s)]
	if needs_bridge and not _map_has_bridge(c, map):
		return "Hold the bridge needs a map with a bridge."
	return ""


static func _map_has_bridge(c: Dictionary, map: Dictionary) -> bool:
	if not map.is_empty():
		return not (map.get("bridge_cells", []) as Array).is_empty()
	var key := "%s:%d" % [String(c.get("map", "river_crossing_s")), int(c.get("seed", 1))]
	if not _bridge_maps.has(key):
		var m := MapGen.generate(int(c.get("seed", 1)), String(c.get("map", "river_crossing_s")))
		_bridge_maps[key] = not (m.get("bridge_cells", []) as Array).is_empty()
	return bool(_bridge_maps[key])
