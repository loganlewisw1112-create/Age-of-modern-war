extends RefCounted
## G3b (agent AI4): stage-aware plan. Research + Stage 7->8->9 advancement, Stage 9 unit roles
## (EW behind the front, guided artillery behind the line via ai_g3_units, AA when air is seen),
## recon for the 8->9 people gate, and big-map crossing routes. State in st.g4 (serializable).
## Every gate fact comes from Progression.gate_report(w, fid) (the single source, CONTRACTS_G3b 3.2).
## Fairness: see the convention in ai_util.gd (own side, public map, own fog only).

const U = preload("res://sim/ai/ai_util.gd")
const Progression = preload("res://sim/systems/progression.gd")
const PData = preload("res://sim/systems/progression_data.gd")

## Research building goes up once the factory stands, or by this tick anyway (early-mid game).
const RESEARCH_BY_TICK := 7200
## Credits kept back for defence when starting research / advancing (never bank the last ones).
const DEFENCE_FLOOR := 250
## Spare power wanted while working on the stable-power gate (a shortfall resets the 60 s clock).
const POWER_HEADROOM := 15
const EW_BEHIND := 3.0


static func new_g4(w: SimWorld, fid: int) -> Dictionary:
	return {"crossings": U.crossings(w), "advanced": [], "researched": 0, "adv_orders": 0,
		"reserve": {}, "plan": "", "bridge_seen": {}, "recon_wp": {}, "probe": "", "enemy_air_seen": 0}


## Building the stage plan wants next ("" = none). Called at the end of Econ.next_build.
static func want_building(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> String:
	if not plan_open(w, fid, st):
		return ""  # the opening (first waves, first officer wave) comes first
	var gates := gates_of(w, fid, st)
	if gates.is_empty():
		return ""  # top playable stage: nothing left to unlock
	var have: Dictionary = ctx.have
	var built: Dictionary = ctx.built
	var rs := U.role(w, fid, "research")
	var fac_built := int(built.get(U.role(w, fid, "factory"), 0)) > 0
	if rs != "" and int(have.get(rs, 0)) == 0 and _reqs_built(rs, built) and (fac_built or w.tick >= RESEARCH_BY_TICK):
		return rs
	for g in gates:
		if String(g.key) == "comms" and not bool(g.ok):
			var cm := U.role(w, fid, "comms")
			if cm != "" and int(have.get(cm, 0)) < int(g.need) and _reqs_built(cm, built):
				return cm
		elif String(g.key) == "power" and not bool(g.ok) and rs != "" and int(have.get(rs, 0)) > 0:
			var pw := U.role(w, fid, "power")
			if pw != "" and int(ctx.power_planned) < POWER_HEADROOM and int(ctx.unfinished.get(pw, 0)) == 0:
				return pw
	return ""


## The stage plan (lab, comms, power headroom) opens once the first attack wave went out, or a
## while after the difficulty's first-attack tick anyway (a side that never attacks still advances).
static func plan_open(w: SimWorld, fid: int, st: Dictionary) -> bool:
	if int(st.get("launches", 0)) >= 1:
		return true
	var grace := int(U.diff(w, fid).get("first_attack_tick", 0))
	return w.tick >= (grace + 1200 if grace > 0 else RESEARCH_BY_TICK)


## Progression.gate_report cached in st.g4 (serialized with the state, so save/load replays the
## same decisions) for GATE_CACHE_TICKS: it walks every own unit, and the plan only needs a fresh
## view a few times a minute. Refreshed at once on a stage / advancement / active-research change.
const GATE_CACHE_TICKS := 100


static func gates_of(w: SimWorld, fid: int, st: Dictionary) -> Array:
	var g4: Dictionary = st.g4
	var f: Dictionary = w.factions[fid]
	var stamp := "%d|%d|%s|%d" % [int(f.stage), int(int(f.advancing.ticks_left) > 0), String(f.research.active),
		(f.research.done as Array).size()]
	var t := int(g4.get("gates_tick", -100000))
	if g4.has("gates") and String(g4.get("gates_stamp", "")) == stamp and w.tick >= t and w.tick - t < GATE_CACHE_TICKS:
		return g4.gates
	g4.gates = Progression.gate_report(w, fid)
	g4.gates_tick = w.tick
	g4.gates_stamp = stamp
	return g4.gates


static func _reqs_built(def_id: String, built: Dictionary) -> bool:
	for r in Content.building(def_id).get("requires", []):
		if int(built.get(String(r), 0)) == 0:
			return false
	return true


## Research, recon, officers, advancement. Sets st.g4.reserve: what the side banks for next (credits
## only come from the HQ stipend, so without banking research and the jump never happen). U.submit
## holds it back from every queue_unit / build except power and the stage-plan buildings. Banking
## waits for the first attack wave (G1/G2 openings intact), then
## starts only while a defensive core stands (army pop >= a third of the attack threshold) and never
## while defending (the bank is released at once), so defence is never starved. Once the research
## building stands the bank is everything still to pay for the next stage: the remaining projects
## plus the advancement cost (research purchases themselves are not held back).
static func manage(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, army_pop: int) -> void:
	var g4: Dictionary = st.g4
	g4.reserve = {}
	var gates := gates_of(w, fid, st)
	var f: Dictionary = w.factions[fid]
	if gates.is_empty() or int(f.advancing.ticks_left) > 0:
		g4.plan = "top" if gates.is_empty() else "advancing"
		_probe(w, fid, st, gates)
		return
	var defending := String(st.objective) == "defend"
	var core_ok := army_pop * 3 >= int(st.attack_pop) and not defending
	var lab = _research_building(w, fid, ctx)
	var unmet := []
	var rest_ok := true
	var cost_e := {}
	for g in gates:
		if not bool(g.ok):
			unmet.append(String(g.key))
		if String(g.key) == "cost":
			cost_e = g
		elif not bool(g.ok) and String(g.key) != "research":
			rest_ok = false
	var want := {}
	var r: Dictionary = f.research
	# 1. research the next stage's projects, one at a time
	for g in gates:
		if String(g.key) != "research" or bool(g.ok):
			continue
		var missing: Array = g.missing
		if String(r.active) == "":
			if lab == null:
				break
			var pid := String(missing[0])
			var cost: Dictionary = PData.project(pid).get("cost", {})
			var floor_cr := 0 if core_ok else DEFENCE_FLOOR
			if w.can_afford(fid, cost) == "" and int(f.credits) - int(cost.get("credits", 0)) >= floor_cr and not defending:
				if U.submit(w, fid, st, {"type": "research", "project": pid}, "research"):
					g4.researched = int(g4.researched) + 1
					U.log_line(st, w, "research %s" % PData.project_name(pid, U.fac(w, fid)))
		for pid in missing:
			if String(pid) != String(r.active):
				want = _add(want, PData.project(String(pid)).get("cost", {}))
	# 2. people gates: recon pickets (8->9) and an officer (7->8) once the lab stands
	if unmet.has("people"):
		_queue_role(w, fid, st, ctx, "recon", "infantry", "stage:recon")
	if unmet.has("officers") and lab != null:
		_queue_role(w, fid, st, ctx, "officer", "", "stage:officer")
	if unmet.has("line") and lab != null:
		_queue_role(w, fid, st, ctx, "infantry", "antitank", "stage:line")
	# 3. advance once every other gate is met: bank the cost, then pay it when it is safe
	g4.plan = "gates:" + ",".join(unmet)
	if rest_ok and not unmet.has("research") and not cost_e.is_empty():
		var safe := not defending or army_pop >= int(st.attack_pop)
		if bool(cost_e.ok) and safe and Progression.can_advance(w, fid) == "":
			if U.submit(w, fid, st, {"type": "advance_stage"}, "advance"):
				g4.adv_orders = int(g4.adv_orders) + 1
				U.log_line(st, w, "advancing to stage %d" % (int(f.stage) + 1))
	if not cost_e.is_empty() and not bool(cost_e.ok):
		want = _add(want, cost_e.cost)
	# bank only after the first wave went out (G1/G2 openings and the first officer wave stay intact)
	if core_ok and lab != null and not want.is_empty() and int(st.launches) >= 1:
		# AI4-3: never bank for a jump the side cannot finish: no ore left that we know of while the
		# bank still needs ore (the credits would sit idle for the rest of the match). A timed bank
		# release was tried and dropped: heartland soak2 Human A released 6200 cr + 597 ore at
		# t=72000, 200 ore short of 8->9, and never advanced.
		var ore_short := int(want.get("ore", 0)) > int(f.stock.get("ore", 0))
		var ore_left := int(st.get("gather_plan", {}).get("ore_left", 1))
		if ore_short and ore_left <= 0:
			g4.plan += " no-ore"
		else:
			g4.reserve = (want as Dictionary).duplicate()
			g4.plan += " saving:" + PData.cost_label(want)
	_probe(w, fid, st, gates)


static func _add(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = int(out.get(k, 0)) + int(b[k])
	return out


static func _probe(w: SimWorld, fid: int, st: Dictionary, gates: Array) -> void:
	var g4: Dictionary = st.g4
	var ok := 0
	for g in gates:
		if bool(g.ok):
			ok += 1
	g4.probe = "stage=%d plan=%s gates=%d/%d res=%d adv=%s" % [U.stage(w, fid), String(g4.plan), ok, gates.size(),
		int(g4.researched), str(g4.advanced)]


static func _research_building(w: SimWorld, fid: int, ctx: Dictionary):
	for b in ctx.buildings:
		if b.built and U.bflag(String(b.def), "research"):
			return b
	return null


## Queues one unit of `role_name` (else `fallback`) at its least-loaded facility (one in queue max).
static func _queue_role(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, role_name: String, fallback: String, key: String) -> void:
	var item := U.role(w, fid, role_name)
	if item == "" and fallback != "":
		item = U.role(w, fid, fallback)
	if item == "":
		return
	var fac_def := String(Content.production(item).get("facility", ""))
	var best = null
	for b in ctx.buildings:
		if String(b.def) != fac_def or not b.built:
			continue
		for q in b.queue:
			if String(q.item) == item:
				return
		if best == null or b.queue.size() < best.queue.size():
			best = b
	if best == null or best.queue.size() >= 2:
		return
	if w.can_afford(fid, Content.production(item).cost) != "":
		return
	U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(best.id), "item": item}, key)


## Resources Mil.manage_production keeps back this think ({} = none).
static func reserve(st: Dictionary) -> Dictionary:
	return st.get("g4", {}).get("reserve", {})


## Recon units (not the scout): explore a grid of waypoints around our half (explored share +
## a living recon picket for the 8->9 gate). Kept out of the main army by ai_controller._context.
static func manage_recon(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var wps: Dictionary = st.g4.recon_wp
	if not st.g4.has("explore_pts"):
		st.g4.explore_pts = _explore_points(w, fid)
	var pts: Array = st.g4.explore_pts
	if pts.is_empty():
		return
	for e in ctx.recon:
		var id := int(e.id)
		var i := int(wps.get(id, id % pts.size()))
		var wp: Vector2 = pts[i % pts.size()]
		if Vector2(e.pos).distance_to(wp) < 3.0 or (String(e.order.type) == "idle" and not e.moving):
			i = (i + 1) % pts.size()
			wps[id] = i
			U.submit(w, fid, st, {"type": "move", "unit_ids": [id], "target": Vector2(pts[i])}, "recon:%d" % id)
	if w.tick % 600 == 0:
		var drop := []
		for id in wps:
			if U.own(w, fid, int(id)) == null:
				drop.append(id)
		for id in drop:
			wps.erase(id)


## Waypoints every ~24 cells, nearer our start than any enemy start, nearest first.
static func _explore_points(w: SimWorld, fid: int) -> Array:
	var mine := U.spawn_of(w, fid)
	var step := 24
	var out := []
	for y in range(step / 2, int(w.map.h), step):
		for x in range(step / 2, int(w.map.w), step):
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var ours := true
			for s in U.enemy_side_ids(w, fid):
				if p.distance_to(U.spawn_of(w, s)) < p.distance_to(mine):
					ours = false
					break
			if ours:
				out.append([p.distance_to(mine), p])
	out.sort()
	var pts := []
	for o in out:
		pts.append(o[1])
	return pts


# ================================================================ Stage 9 roles
## Production shares for the Stage 9 roles on top of Mil._shares (relative weights): guided
## artillery behind the line, EW near the front, AA once enemy air is seen, air for factions that
## gain it at Stage 9. Roles a faction lacks resolve to "" and are skipped by Mil.
static func stage_shares(w: SimWorld, fid: int, st: Dictionary, shares: Dictionary, has_factory: bool) -> Dictionary:
	if U.stage(w, fid) < 9 or not has_factory:
		return shares
	var out := shares.duplicate()
	var air_seen := int(st.g4.get("enemy_air_seen", 0)) >= 1
	out["precision"] = 0.12
	out["ew"] = 0.06
	out["anti_air"] = 0.15 if air_seen else 0.04
	if not out.has("air"):
		out["air"] = 0.08
	return out


## EW units (ew_radius, no weapon): hold EW_BEHIND cells behind the attack group's centroid (their
## jamming radius reaches the front), else stay at the rally point.
static func manage_ew(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	if ctx.ew.is_empty():
		return
	var group := []
	for id in st.attack_group:
		var e = U.own(w, fid, int(id))
		if e != null:
			group.append(e)
	var tgt := Vector2(st.rally)
	if not group.is_empty() and String(st.objective) == "attack":
		var c := Vector2.ZERO
		for e in group:
			c += Vector2(e.pos)
		c /= float(group.size())
		var back := (U.base_pos(w, fid) - c)
		tgt = c + (back.normalized() * EW_BEHIND if back.length() > 0.1 else Vector2.ZERO)
	var send := []
	for e in ctx.ew:
		if Vector2(e.pos).distance_to(tgt) > 4.0 and (String(e.order.type) != "move" or Vector2(e.order.get("target", e.pos)).distance_to(tgt) > 4.0):
			send.append(int(e.id))
	if not send.is_empty():
		tgt = tgt.clamp(Vector2(1, 1), Vector2(float(w.map.w) - 2.0, float(w.map.h) - 2.0))
		U.submit(w, fid, st, {"type": "move", "unit_ids": send, "target": tgt}, "ew")


# ================================================================ big-map routing
## True on maps with more than one bridge (G3b maps): crossing-aware patrols and attack routes.
## River Crossing keeps its G2 bridge/ford personality routes (tests rely on them).
static func multi_crossing(w: SimWorld) -> bool:
	return (w.map.get("bridges", []) as Array).size() > 1


## Scout patrol for multi-crossing maps: the crossings nearest our start (up to 4), nearest first.
static func patrol_points(w: SimWorld, fid: int) -> Array:
	var mine := U.spawn_of(w, fid)
	var arr := []
	for c in U.crossings(w):
		arr.append([Vector2(c.pos).distance_to(mine), Vector2(c.pos)])
	arr.sort()
	var out := []
	for i in mini(4, arr.size()):
		out.append(arr[i][1])
	return out


## Notes bridge states this side can see now (a ruined span seen once is avoided until seen intact).
static func note_bridges(w: SimWorld, fid: int, st: Dictionary) -> void:
	var seen: Dictionary = st.g4.bridge_seen
	var brs: Array = w.map.get("bridges", [])
	for c in st.g4.crossings:
		var bi := int(c.bridge)
		if bi < 0 or bi >= brs.size() or not w.is_visible(fid, Vector2(c.pos)):
			continue
		seen[bi] = String(brs[bi].get("state", "intact"))  # public map state of a span we can see


## Via-point for an attack from `from` to `tgt` on multi-crossing maps, Vector2(-1, -1) for direct.
## Candidates: crossings not seen ruined, ranked by detour from + to; the side's route personality
## picks the best or a near-equal second. Same-bank targets (no crossing within 1.3x direct) go direct.
static func route_via(w: SimWorld, fid: int, st: Dictionary, from: Vector2, tgt: Vector2) -> Vector2:
	var seen: Dictionary = st.g4.bridge_seen
	var direct := from.distance_to(tgt)
	var cands := []
	for c in st.g4.crossings:
		var bi := int(c.bridge)
		if bi >= 0 and String(seen.get(bi, "intact")) == "ruined":
			continue
		var p := Vector2(c.pos)
		cands.append([from.distance_to(p) + p.distance_to(tgt), p])
	if cands.is_empty():
		return Vector2(-1, -1)
	cands.sort()
	var best: float = cands[0][0]
	if best > direct * 1.3:
		return Vector2(-1, -1)
	var near := 1
	while near < mini(3, cands.size()) and float(cands[near][0]) <= best * 1.2:
		near += 1
	return Vector2(cands[int(st.route) % near][1])
