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
const SimIndex = preload("res://sim/systems/sim_index.gd")  # G3b scale (PERF5): per-kind lists
const MapGen = preload("res://sim/map_gen.gd")

## G4 (MAPIO, CONTRACTS_G4 section 5): scenario presets, combinable with AND/OR like the others.
## survive{seconds, slot?}: the team is alive when the clock reaches `seconds`.
## destroy_target{tag, slot?}: every placed entity carrying `tag` is gone (teams owning one never win by it).
## reach_stage{stage, slot?}: a side of the team is at `stage` or later.
## hold_point{region, seconds, slot?}: only this team's units stand in the region for `seconds` in a row
##   (sampled with the bridge; state w.sys_state.victory.points, created only when used).
## slot (optional, a map-file player slot) restricts which team can satisfy the term.
const SCENARIO_TERMS := ["survive", "destroy_target", "reach_stage", "hold_point"]
const MODES := ["hq_elimination", "territory", "hold_bridge", "combined", "endless", "survive", "destroy_target", "reach_stage", "hold_point"]
const TERM_TYPES := ["hq_elimination", "territory", "hold_bridge", "survive", "destroy_target", "reach_stage", "hold_point"]
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
	if w.tick % BRIDGE_EVERY == 7:  # G3b perf: off the shared tick%20==0 spike
		_bridge_sample(w)
		_points_sample(w)
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
	for e in SimIndex.of(w, "building"):
		if _is_hq(String(e.def)) and SimIndex.alive(w, e):
			has_hq[int(e.owner)] = true
	var hqless: Array = _vstate(w).get("hqless", [])
	if not hqless.is_empty():
		for e in SimIndex.of(w, "unit"):
			if SimIndex.alive(w, e):
				has_hq[int(e.owner)] = true if hqless.has(int(e.owner)) else has_hq.get(int(e.owner), false)
		for e in SimIndex.of(w, "building"):
			if hqless.has(int(e.owner)) and SimIndex.alive(w, e):
				has_hq[int(e.owner)] = true
	var changed := false
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		if f.alive and not bool(has_hq.get(int(fid), false)):
			f.alive = false
			changed = true
			w.emit("SideEliminated", {"faction": int(fid), "team": team_of(w, int(fid))})
	if changed:
		_teams_out(w)


static func _teams_out(w: SimWorld) -> void:
	var vs := _vstate(w)
	var out: Array = vs.out_teams
	for team in all_teams(w):
		if not team_alive(w, int(team)) and not out.has(int(team)):
			out.append(int(team))
			w.emit("TeamEliminated", {"team": int(team)})


## G4 scenario sides placed without an HQ (map file, start_packages false): they are out when
## they have no units and no buildings left instead. Called by MapIO.place_entities.
static func note_hqless(w: SimWorld) -> void:
	var has := {}
	for e in w.entities.values():
		if e.kind == "building" and _is_hq(String(e.def)):
			has[int(e.owner)] = true
	var lst := []
	for fid in w.factions:
		if not has.has(int(fid)):
			lst.append(int(fid))
	lst.sort()
	if not lst.is_empty():
		_vstate(w)["hqless"] = lst


## G4 triggers: lose{slot}.
static func eliminate_side(w: SimWorld, fid: int) -> void:
	if not w.factions.has(fid) or not bool(w.factions[fid].alive):
		return
	w.factions[fid].alive = false
	w.emit("SideEliminated", {"faction": fid, "team": team_of(w, fid)})
	_teams_out(w)


## G4 triggers: win{slot}. Ends the match for that side's team (reason "trigger").
static func force_win(w: SimWorld, fid: int) -> void:
	if w.match_state.get("ended", false) or not w.factions.has(fid):
		return
	_end(w, team_of(w, fid), "trigger", ["trigger"])


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
			if SCENARIO_TERMS.has(mode):
				t.merge(p)
				t.type = mode
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
	elif SCENARIO_TERMS.has(ty):
		if ty == "survive" or ty == "hold_point":
			out.seconds = int(t.get("seconds", DEFAULT_SECONDS))
		if ty == "destroy_target":
			out.tag = String(t.get("tag", ""))
		if ty == "reach_stage":
			out.stage = int(t.get("stage", 9))
		if ty == "hold_point":
			out.region = String(t.get("region", ""))
		if t.has("slot"):
			out.slot = int(t.slot)
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
		"survive", "destroy_target", "reach_stage", "hold_point":
			return _scenario_term(w, team, t)
	return false


## Team allowed by the optional term slot (map-file player slot -> side via cfg.sides).
static func _slot_ok(w: SimWorld, team: int, t: Dictionary) -> bool:
	if not t.has("slot"):
		return true
	var sides: Array = w.cfg.get("sides", [])
	for i in sides.size():
		if int(sides[i].get("slot", i)) == int(t.slot):
			return team_of(w, i) == team
	return false


static func _scenario_term(w: SimWorld, team: int, t: Dictionary) -> bool:
	if not team_alive(w, team) or not _slot_ok(w, team, t):
		return false
	match String(t.type):
		"survive":
			return w.tick >= int(t.get("seconds", DEFAULT_SECONDS)) * SimWorld.TICK_RATE
		"destroy_target":
			var tg: Dictionary = w.sys_state.get("triggers", {}).get("tags", {}).get(String(t.get("tag", "")), {})
			if tg.is_empty():
				return false
			for fid in tg.get("owners", []):
				if team_of(w, int(fid)) == team:
					return false
			for id in tg.get("ids", []):
				if _tag_alive(w, int(id)):
					return false
			return true
		"reach_stage":
			for fid in w.factions:
				if team_of(w, int(fid)) == team and bool(w.factions[fid].alive) and int(w.factions[fid].stage) >= int(t.get("stage", 9)):
					return true
			return false
		"hold_point":
			var ps: Dictionary = _vstate(w).get("points", {}).get(String(t.get("region", "")), {})
			return int(ps.get("holder", -1)) == team and int(ps.get("secs", 0)) >= int(t.get("seconds", DEFAULT_SECONDS))
	return false


## A tagged entity still exists (in the world, or carried as cargo inside a carrier's dict).
## The cargo scan reads the authoritative carrier dicts, not w.cache.cargo_of (rebuilt lazily after load).
static func _tag_alive(w: SimWorld, id: int) -> bool:
	if w.entities.has(id):
		var e: Dictionary = w.entities[id]
		return e.kind != "structure" or String(e.get("state", "intact")) == "intact"
	for c in SimIndex.of(w, "unit"):
		if c.has("cargo") and SimIndex.alive(w, c):
			for u in c.cargo:
				if int(u.id) == id:
					return true
	return false


## Region rect by id from w.map.regions (cached).
static func region_rect(w: SimWorld, rid: String):
	var rc = w.cache.get("victory_regions")
	if rc == null:
		rc = {}
		for r in w.map.get("regions", []):
			rc[String(r.id)] = r.rect if typeof(r.rect) == TYPE_RECT2I else Rect2i(int(r.rect[0]), int(r.rect[1]), int(r.rect[2]), int(r.rect[3]))
		w.cache["victory_regions"] = rc
	return rc.get(rid)


## hold_point sampling (same cadence and rules as the bridge).
static func _points_sample(w: SimWorld) -> void:
	var rules := rules_of_world(w)
	var done := {}
	for t in rules.terms:
		if String(t.type) != "hold_point" or done.has(String(t.region)):
			continue
		done[String(t.region)] = true
		var vs := _vstate(w)
		if not vs.has("points"):
			vs["points"] = {}
		var rid := String(t.region)
		if not vs.points.has(rid):
			vs.points[rid] = {"holder": -1, "secs": 0}
		var ps: Dictionary = vs.points[rid]
		var rect = region_rect(w, rid)
		var holder := -1
		if rect != null:
			for e in SimIndex.of(w, "unit"):
				var fid := int(e.owner)
				if not w.factions.has(fid) or not bool(w.factions[fid].alive) or not SimIndex.alive(w, e):
					continue
				if not (rect as Rect2i).has_point(w.cell_of(e.pos)):
					continue
				var tm := team_of(w, fid)
				if holder == -1:
					holder = tm
				elif holder != tm:
					holder = -2
					break
		if holder < 0:
			ps.holder = -1
			ps.secs = 0
		elif int(ps.holder) != holder:
			ps.holder = holder
			ps.secs = 0
		else:
			ps.secs = int(ps.secs) + BRIDGE_EVERY / SimWorld.TICK_RATE


# ================================================================ hold the bridge
## The neutral bridge structure (kind "structure" with cells), or null when the map has none.
static func bridge_entity(w: SimWorld):
	var bid = w.cache.get("victory_bridge_id")
	if bid != null:
		var b = w.entities.get(int(bid))
		if b != null:
			return b
	for e in SimIndex.of(w, "structure"):
		if e.has("cells") and SimIndex.alive(w, e):
			w.cache["victory_bridge_id"] = int(e.id)
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
	for e in SimIndex.of(w, "unit"):
		var fid := int(e.owner)
		if not w.factions.has(fid) or not bool(w.factions[fid].alive):
			continue
		if (e.pos as Vector2).distance_squared_to(bp) > r2 or not SimIndex.alive(w, e):
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
				for e in SimIndex.of(w, "building"):
					if _is_hq(String(e.def)) and w.factions.has(int(e.owner)) and SimIndex.alive(w, e):
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
			"survive":
				var secs := w.tick / SimWorld.TICK_RATE
				row.merge({"value": secs, "target": int(t.seconds),
					"label": "Survive for %d s (%d s left)" % [int(t.seconds), maxi(0, int(t.seconds) - secs)]})
			"destroy_target":
				var tg: Dictionary = w.sys_state.get("triggers", {}).get("tags", {}).get(String(t.tag), {})
				var left := 0
				for id in tg.get("ids", []):
					if _tag_alive(w, int(id)):
						left += 1
				row.merge({"value": left, "target": 0, "tag": String(t.tag),
					"label": "Destroy the target '%s' (%d left)" % [String(t.tag), left]})
			"reach_stage":
				var best := 0
				for fid in w.factions:
					if team_of(w, int(fid)) == team:
						best = maxi(best, int(w.factions[fid].stage))
				row.merge({"value": best, "target": int(t.stage),
					"label": "Reach Stage %d (Stage %d now)" % [int(t.stage), best]})
			"hold_point":
				var ps: Dictionary = _vstate(w).get("points", {}).get(String(t.region), {})
				var mine2 := int(ps.get("holder", -1)) == team
				row.merge({"value": int(ps.get("secs", 0)) if mine2 else 0, "target": int(t.seconds), "region": String(t.region),
					"holder": int(ps.get("holder", -1)), "contested": not mine2 and int(ps.get("holder", -1)) != -1,
					"label": "Hold %s for %d s (%d s held)" % [String(t.region), int(t.seconds), int(ps.get("secs", 0)) if mine2 else 0]})
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
		if seen.has(ty) and not SCENARIO_TERMS.has(ty):
			return "Duplicate victory term '%s'." % ty
		seen[ty] = true
		if ty == "territory" and t.has("percent"):
			var p = t.percent
			if not (typeof(p) == TYPE_INT or typeof(p) == TYPE_FLOAT) or float(p) < PERCENT_MIN or float(p) > PERCENT_MAX:
				return "Territory percent must be between %d and %d (got %s)." % [int(PERCENT_MIN), int(PERCENT_MAX), str(p)]
		var sm := _scenario_param_error(ty, t)
		if sm != "":
			return sm
		if ty == "hold_bridge":
			needs_bridge = true
			if t.has("seconds"):
				var s = t.seconds
				if not (typeof(s) == TYPE_INT or typeof(s) == TYPE_FLOAT) or float(s) < SECONDS_MIN or float(s) > SECONDS_MAX:
					return "Hold-the-bridge time must be between %d and %d seconds (got %s)." % [SECONDS_MIN, SECONDS_MAX, str(s)]
	if needs_bridge and not _map_has_bridge(c, map):
		return "Hold the bridge needs a map with a bridge."
	return ""


static func _num_in(v, lo: float, hi: float) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) >= lo and float(v) <= hi


static func _scenario_param_error(ty: String, t: Dictionary) -> String:
	if not SCENARIO_TERMS.has(ty):
		return ""
	if (ty == "survive" or ty == "hold_point") and t.has("seconds") and not _num_in(t.seconds, 1, 36000):
		return "%s time must be between 1 and 36000 seconds (got %s)." % [ty, str(t.seconds)]
	if ty == "destroy_target" and String(t.get("tag", "")) == "":
		return "destroy_target needs a tag."
	if ty == "reach_stage" and not _num_in(t.get("stage", 9), 1, 13):
		return "reach_stage stage must be 1-13 (got %s)." % str(t.get("stage"))
	if ty == "hold_point" and String(t.get("region", "")) == "":
		return "hold_point needs a region."
	if t.has("slot") and not _num_in(t.slot, 0, 15):
		return "Victory term slot must be 0-15 (got %s)." % str(t.slot)
	return ""


static func _map_has_bridge(c: Dictionary, map: Dictionary) -> bool:
	if not map.is_empty():
		return not (map.get("bridge_cells", []) as Array).is_empty()
	if c.has("map_file"):   # G4: read the file's bridge list (no MapIO preload: it preloads us)
		var j = JSON.parse_string(FileAccess.get_file_as_string(String(c.map_file))) if FileAccess.file_exists(String(c.map_file)) else null
		return typeof(j) == TYPE_DICTIONARY and typeof(j.get("bridges")) == TYPE_ARRAY and not (j.bridges as Array).is_empty()
	var key := "%s:%d" % [String(c.get("map", "river_crossing_s")), int(c.get("seed", 1))]
	if not _bridge_maps.has(key):
		var m := MapGen.generate(int(c.get("seed", 1)), String(c.get("map", "river_crossing_s")))
		_bridge_maps[key] = not (m.get("bridge_cells", []) as Array).is_empty()
	return bool(_bridge_maps[key])
