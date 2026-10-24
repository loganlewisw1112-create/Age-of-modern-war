extends RefCounted
## AI G3a (owner: agent AI3). Contract: docs/CONTRACTS_G3a.md section 5.
## - Multi-enemy targeting: the side picks ONE enemy side to attack, by the distance from our TEAM's
##   start centroid (public lobby + map data, identical for every ally, so 2v2 allies converge on
##   the same enemy without any shared AI state) to that side's known HQ (own memory) or public
##   start, plus a small weakness term from our own memory (fewer known defences = softer).
##   Hysteresis (RETARGET_MARGIN) keeps the choice stable; a SideEliminated announcement (public)
##   drops that side and retargets. Allies are never targets: every enemy query is
##   w.visible_enemies(fid) / w.memory[fid], which only hold other TEAMS' entities.
## - Victory awareness (cfg.victory / victory_rules, public): territory -> the wave sweeps
##   uncaptured sectors (Territory.sector_owner, public HUD data) nearest our base first;
##   hold_bridge -> the wave holds the bridge. With an AND hq term the side switches to the HQ
##   once the other term is met (territory % from the HUD API, bridge hold from our own clock).
## - Drone raids (is_air units) and artillery kept behind the line: ai_g3_units.gd.
## All state lives in st.g3 (serializable). Fairness: see the convention in ai_util.gd.

const U = preload("res://sim/ai/ai_util.gd")
const Territory = preload("res://sim/systems/territory.gd")

const RETARGET_MARGIN := 8.0
const DEFENCE_WEIGHT := 2.0
const HOLD_RADIUS := 4.0
const SECTOR_REACHED := 4.0
const SECTOR_TIMEOUT := 1600


static func new_g3(w: SimWorld, fid: int) -> Dictionary:
	return {"target_side": -1, "eliminated": [], "retargets": 0, "target_why": "",
		"obj_kind": "base", "obj_pos": Vector2(-1, -1), "sector": -1, "sector_tick": 0, "skip": [],
		"sec_pts": [], "captures": 0, "hold_ticks": 0, "hold_tick": -1,
		"raid": {}, "raid_next": 0, "raids": 0, "raid_kills": 0, "arty_moves": 0,
		"terms": victory_terms(w)}


## Victory terms of this match (public config): {hq, territory (percent, 0 = none), bridge
## (seconds, 0 = none), op, endless}. Endless still eliminates sides, so hq stays the default goal.
static func victory_terms(w: SimWorld) -> Dictionary:
	var t := {"elim": false, "territory": 0.0, "bridge": 0, "op": "or", "endless": false}
	var v := String(w.cfg.get("victory", "hq_elimination"))
	var params: Dictionary = w.cfg.get("victory_params", {})
	var def_pct := float(Content.rules().get("territory", {}).get("default_percent", 60))
	match v:
		"territory":
			t.territory = float(params.get("percent", def_pct))
		"hold_bridge":
			t.bridge = int(params.get("seconds", 300))
		"endless":
			t.endless = true
			t.elim = true
		"combined":
			var rules: Dictionary = w.cfg.get("victory_rules", {})
			t.op = String(rules.get("op", "or"))
			for term in rules.get("terms", []):
				match String(term.get("type", "")):
					"hq_elimination":
						t.elim = true
					"territory":
						t.territory = float(term.get("percent", def_pct))
					"hold_bridge":
						t.bridge = int(term.get("seconds", 300))
		_:
			t.elim = true
	if float(t.territory) <= 0.0 and int(t.bridge) <= 0:
		t.elim = true
	if w.map.get("bridge_cells", []).is_empty():
		t.bridge = 0
	return t


static func _team_anchor(w: SimWorld, fid: int) -> Vector2:
	var c := Vector2.ZERO
	var team := U.team_side_ids(w, fid)
	for s in team:
		c += U.spawn_of(w, s)
	return c / maxf(1.0, float(team.size()))


## Known (remembered) HQ position of enemy side s, else Vector2(-1, -1).
static func known_hq(w: SimWorld, fid: int, s: int) -> Vector2:
	var mem: Dictionary = w.memory[fid]
	for eid in mem:
		var m: Dictionary = mem[eid]
		if int(m.get("owner", -1)) == s and U.is_hq_def(String(m.def)):
			return Vector2(m.pos)
	return Vector2(-1, -1)


static func live_enemies(w: SimWorld, fid: int, st: Dictionary) -> Array:
	var out := []
	var gone: Array = st.g3.eliminated
	for s in U.enemy_side_ids(w, fid):
		if not gone.has(s):
			out.append(s)
	return out


## Picks / keeps the enemy side this AI attacks. Returns the side id or -1.
static func choose_target(w: SimWorld, fid: int, st: Dictionary) -> int:
	var g3: Dictionary = st.g3
	var live := live_enemies(w, fid, st)
	var cur := int(g3.target_side)
	if live.is_empty():
		g3.target_side = -1
		return -1
	var anchor := _team_anchor(w, fid)
	var defences := {}
	var mem: Dictionary = w.memory[fid]
	for eid in mem:
		var m: Dictionary = mem[eid]
		if String(Content.building(String(m.def)).get("weapon", "")) != "":
			var o := int(m.get("owner", -1))
			defences[o] = int(defences.get(o, 0)) + 1
	var best := -1
	var best_score := INF
	var cur_score := INF
	for s in live:
		var p := known_hq(w, fid, s)
		if p.x < 0.0:
			p = U.spawn_of(w, s)
		var score := p.distance_to(anchor) + DEFENCE_WEIGHT * float(int(defences.get(s, 0)))
		if s == cur:
			cur_score = score
		if score < best_score - 0.001:
			best_score = score
			best = s
	if cur >= 0 and live.has(cur) and cur_score <= best_score + RETARGET_MARGIN:
		return cur
	g3.target_side = best
	g3.target_why = "side %d: %.0f tiles from our team, %d known defences" % [best, best_score - DEFENCE_WEIGHT * float(int(defences.get(best, 0))), int(defences.get(best, 0))]
	if cur >= 0:
		g3.retargets = int(g3.retargets) + 1
		U.log_line(st, w, "retarget -> %s%s" % [String(g3.target_why), " (side %d eliminated)" % cur if not live.has(cur) else ""])
	else:
		U.log_line(st, w, "target -> %s" % String(g3.target_why))
	return best


## Last known HQ of the target side, else another of its remembered buildings, else its start.
static func hq_target(w: SimWorld, fid: int, st: Dictionary) -> Vector2:
	var s := int(st.g3.target_side)
	if s < 0:
		s = choose_target(w, fid, st)
	if s < 0:
		return U.enemy_spawn(w, fid)
	var p := known_hq(w, fid, s)
	if p.x >= 0.0:
		return p
	var mem: Dictionary = w.memory[fid]
	for eid in mem:
		if int(mem[eid].get("owner", -1)) == s:
			return Vector2(mem[eid].pos)
	return U.spawn_of(w, s)


static func my_team(w: SimWorld, fid: int) -> int:
	return int(w.factions[fid].get("team", fid))


static func bridge_point(w: SimWorld) -> Vector2:
	var cells: Array = w.map.get("bridge_cells", [])
	var c := Vector2.ZERO
	for cell in cells:
		c += Vector2(Vector2i(cell)) + Vector2(0.5, 0.5)
	return c / maxf(1.0, float(cells.size()))


## The attack wave's goal: {"kind": "base"|"bridge"|"sector", "pos"}. `from` = wave centroid.
static func objective(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, from: Vector2) -> Dictionary:
	var g3: Dictionary = st.g3
	var t: Dictionary = g3.terms
	var kind := "base"
	var pos := Vector2(-1, -1)
	if int(t.bridge) > 0:
		var met := int(g3.hold_ticks) >= int(t.bridge) * SimWorld.TICK_RATE
		if not (met and bool(t.elim) and String(t.op) == "and"):
			kind = "bridge"
			pos = bridge_point(w)
	if kind == "base" and float(t.territory) > 0.0:
		var pct := Territory.percent(w, my_team(w, fid))
		var met := pct >= float(t.territory)
		if not (met and bool(t.elim) and String(t.op) == "and"):
			var s := _sector_goal(w, fid, st, from)
			if s >= 0:
				kind = "sector"
				pos = Vector2(g3.sec_pts[s])
	if kind == "base":
		pos = hq_target(w, fid, st)
	if kind != String(g3.obj_kind):
		U.log_line(st, w, "objective now %s at %s" % [kind, str(pos.round())])
	g3.obj_kind = kind
	g3.obj_pos = pos
	return {"kind": kind, "pos": pos}


## Own clock of the bridge hold: the wave sits within HOLD_RADIUS and no visible enemy unit does.
static func note_bridge(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, wave_c: Vector2) -> void:
	var g3: Dictionary = st.g3
	var bp := bridge_point(w)
	var ok := wave_c.distance_to(bp) <= HOLD_RADIUS + 1.0 and not bool(st.g2.get("bridge_ruined", false))
	for v in ctx.visible:
		if v.kind == "unit" and Vector2(v.pos).distance_to(bp) <= HOLD_RADIUS:
			ok = false
	var last := int(g3.hold_tick)
	if ok and last >= 0:
		g3.hold_ticks = int(g3.hold_ticks) + (w.tick - last)
	elif not ok:
		g3.hold_ticks = 0
	g3.hold_tick = w.tick if ok else -1


## Sector points: a foot-passable cell near each counted sector's centre (computed once).
static func _sector_points(w: SimWorld, st: Dictionary) -> Array:
	var pts: Array = st.g3.sec_pts
	if not pts.is_empty():
		return pts
	for s in Territory.sector_count(w):
		var p := Vector2(-1, -1)
		if Territory.is_counted(w, s):
			var r := Territory.sector_rect(w, s)
			var ctr := Vector2(r.position) + Vector2(r.size) * 0.5
			var best_d := INF
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var c := Vector2i(x, y)
					if w.in_bounds(c) and Terrain.passable(w.terrain_at(c), "foot") and w.terrain_at(c) != Terrain.BRIDGE:
						var cp := Vector2(c) + Vector2(0.5, 0.5)
						var d := cp.distance_squared_to(ctr)
						if d < best_d:
							best_d = d
							p = cp
		pts.append(p)
	return pts


## Current sector goal (id) for the territory sweep, or -1 when every counted sector is ours.
static func _sector_goal(w: SimWorld, fid: int, st: Dictionary, from: Vector2) -> int:
	var g3: Dictionary = st.g3
	var pts := _sector_points(w, st)
	var team := my_team(w, fid)
	var cur := int(g3.sector)
	if cur >= 0 and Territory.sector_owner(w, cur) == team:
		g3.captures = int(g3.captures) + 1
		U.log_line(st, w, "sector %d captured" % cur)
		cur = -1
	if cur >= 0 and w.tick - int(g3.sector_tick) > SECTOR_TIMEOUT:
		(g3.skip as Array).append(cur)  # contested too long: try another one first
		while (g3.skip as Array).size() > 6:
			(g3.skip as Array).pop_front()
		cur = -1
	if cur >= 0:
		return cur
	var base := U.base_pos(w, fid)
	var best := -1
	var best_d := INF
	for s in pts.size():
		var p: Vector2 = pts[s]
		if p.x < 0.0 or Territory.sector_owner(w, s) == team or (g3.skip as Array).has(s):
			continue
		var d := p.distance_to(base) + 0.5 * p.distance_to(from)
		if d < best_d:
			best_d = d
			best = s
	if best < 0 and not (g3.skip as Array).is_empty():
		g3.skip = []
		return _sector_goal(w, fid, st, from)
	g3.sector = best
	g3.sector_tick = w.tick
	return best
