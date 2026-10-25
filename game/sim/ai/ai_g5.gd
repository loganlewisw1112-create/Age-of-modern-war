extends RefCounted
## G5 (AI6): the AI uses the G5 ground units: Drone Teams launch by target type (strike vs armour,
## frag vs infantry clusters, EMP vs machines / turrets, recon ahead of a wave), tactical breaching
## (drone teams at 0 charges, special forces) against remembered walls / gates, medics and
## ambulances on auto-evac over the army with a hospital at home, a logistics truck on
## auto-resupply behind every army, and the new ground units in the production plans.
## State lives in st.g6 (serialized AI state; String keys and Arrays only).
## Fairness: reads own entities (ctx), ctx.visible (w.visible_enemies(fid)), st.g5.fort_seen (own
## memory of seen forts) and static content only. G5 system APIs are called only once their owner's
## script exposes them (CONTRACTS_G5 §5: callers use the stub until the fact is posted); a missing
## API or unit def means the module does nothing, so G4 configs behave exactly as before.

const U = preload("res://sim/ai/ai_util.gd")
const Econ = preload("res://sim/ai/ai_econ.gd")
const G5Mech = preload("res://sim/systems/g5_mech.gd")
const Support = preload("res://sim/systems/support.gd")
const Medical = preload("res://sim/systems/medical.gd")
const Fortify = preload("res://sim/systems/fortify.gd")

## Production plan by faction role (content/g5 faction_roles): [role, base count, army pop from
## which it is wanted]. A role a faction lacks resolves to "" and is skipped.
const PLAN_ROLES := [["drone_team", 2, 8], ["hmg", 2, 8], ["grenadier", 2, 8], ["medic", 1, 10],
	["rocket_team", 2, 10], ["recon_car", 1, 12], ["raider", 1, 12], ["ambulance", 1, 14],
	["shock", 2, 16], ["spaag", 1, 16], ["special_forces", 1, 20]]
## Roles whose units breach with the tactical command (charges / stack-up), besides drone teams.
const BREACH_ROLES := ["special_forces", "shock"]

const PROD_FROM_TICK := 9000  # and after the first launch: the G4b opening (mines ~t7700) keeps its credits
const PROD_NO_LAUNCH_TICK := 18000  # ORCH 2026-10-25: a side that has not attacked by ~15 min still fields its G5 units
## launch_drone kinds are not defs; the dictionary form keeps test_g3_no_hardcoded_defs meaningful.
const DRONE_KIND := {"strike": 0, "frag": 1, "recon": 2, "emp": 3}
static var RECON: String = DRONE_KIND.keys()[2]
const PROD_MIN_CREDITS := 200
const DRONE_COOLDOWN := 4 * SimWorld.TICK_RATE
const TEAMS_PER_THINK := 12
const DRONE_RANGE := 19.0  # G5Mech LAUNCH_RANGE 20 less a tile (the team moves before the command applies)
const RECON_EVERY := 45 * SimWorld.TICK_RATE
const TACTICAL_COOLDOWN := 6 * SimWorld.TICK_RATE
const BREACH_NEAR := 12.0
const TAKEDOWN_NEAR := 5.0
const AUTO_REFRESH := 300 * SimWorld.TICK_RATE  # re-sent only when the army moved AUTO_MOVE or this long
const AUTO_MOVE := 16.0
const AUTO_MIN := 30 * SimWorld.TICK_RATE  # a re-send resets the truck claims / evac phase: never more often
const AUTO_RADIUS := 14
const EVAC_RADIUS := 16
const TRUCK_BEHIND := 6.0
const HOSP_FROM_TICK := 9000
const HOSP_MIN_ARMY := 10
const HOSP_HEADROOM := 80


static func new_g6() -> Dictionary:
	return {"drones": {"strike": 0, "frag": 0, "recon": 0, "emp": 0}, "tactical": {}, "auto_set": 0,
		"evac_set": 0, "hosp_builds": 0, "queued": {}, "dt": {}, "tt": {}, "auto": {}, "evac": {},
		"recon_t": -100000, "fielded": {}, "probe": ""}


static func g6(st: Dictionary) -> Dictionary:
	if not st.has("g6"):
		st.g6 = new_g6()  # pre-G5 save
	return st.g6


# ---------------------------------------------------------------- API presence (static content)
## "script path:fn" -> bool. A pure function of the loaded code, so caching never changes outcomes.
static var _api_cache := {}


static func api(s: Script, fn: String) -> bool:
	var key := s.resource_path + ":" + fn
	var c = _api_cache.get(key)
	if c != null:
		return bool(c)
	var ok := false
	for m in s.get_script_method_list():
		if String(m.name) == fn:
			ok = true
			break
	_api_cache[key] = ok
	return ok


static func is_drone_team(def_id: String) -> bool:
	return int(Content.unit(def_id).get("drone_charges", 0)) > 0


static func is_med(def_id: String) -> bool:
	return int(Content.unit(def_id).get("wounded_slots", 0)) > 0


## Unit defs of this side that breach with `tactical` (BREACH_ROLES).
static func breachers(w: SimWorld, fid: int) -> Array:
	var out := []
	for r in BREACH_ROLES:
		var d := U.role_unit(w, fid, String(r))
		if d != "":
			out.append(d)
	return out


## Hospital defs this side can build: full hospitals (flag `hospital`) before field ones.
static func hospital_defs(w: SimWorld, fid: int) -> Array:
	var full := []
	var field := []
	for b in Content.buildable_for(U.fac(w, fid)):
		var bd := Content.building(String(b))
		if bool(bd.get("hospital", false)):
			full.append(String(b))
		elif bool(bd.get("field_hospital", false)):
			field.append(String(b))
	full.sort()
	field.sort()
	return full + field


static func charges(e: Dictionary) -> int:
	if api(G5Mech, "drone_charges"):
		var sc: Object = G5Mech  # dynamic call: the stub has no such function yet
		return int(sc.call("drone_charges", e))
	return int(e.get("drone_charges", 0))


static func mode(e: Dictionary) -> String:
	if api(G5Mech, "mode"):
		var sc: Object = G5Mech
		return String(sc.call("mode", e))
	return "drone" if charges(e) > 0 else "tactical"


static func _wounded(e: Dictionary) -> bool:
	return bool(Medical.is_wounded(e))


# ---------------------------------------------------------------- production
## AI6-2 (ORCH direction, river s1 a2 salvage exhaustion): roles that spend salvage without
## fighting. No salvage goes to them once the map's salvage is scarce, and on small maps their
## salvage value stays within SUPPORT_SHARE of the combat army's until a first side is eliminated.
const SUPPORT_ROLES := ["drone_team", "medic", "ambulance", "recon_car"]
const SUPPORT_SHARE := 0.15


static func support_ok(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, extra_sal: int) -> bool:
	if extra_sal <= 0:
		return true
	if U.salvage_scarce(w, fid, st):
		return false
	if U.map_scale(w) > 1.2 or not (st.g3.eliminated as Array).is_empty():
		return true
	if ctx.has("g6_sal_share"):  # one unit scan per think (ai_bench: 5k units)
		var cached: Array = ctx.g6_sal_share
		return float(int(cached[0]) + extra_sal) <= SUPPORT_SHARE * float(maxi(1, int(cached[1])))
	var sup_defs := {}
	for r in SUPPORT_ROLES + ["supply"]:
		var d := U.role_unit(w, fid, String(r))
		if d != "":
			sup_defs[d] = true
	var sup := 0
	var com := 0
	var fight := {}
	for e in ctx.army + ctx.arty:
		fight[int(e.id)] = true
	for e in ctx.units:
		if sup_defs.has(String(e.def)):
			sup += U.unit_salvage(String(e.def))
		elif fight.has(int(e.id)):
			com += U.unit_salvage(String(e.def))
	ctx.g6_sal_share = [sup, com]
	return float(sup + extra_sal) <= SUPPORT_SHARE * float(maxi(1, com))


## Queues at most one G5 ground unit per think (every other think, after the G4b extras). Same
## affordability / pop / stage-bank rules as ai_g4b (U.submit checks the bank).
static func manage_production(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	# every third think (staggered big armies run the economy on even thinks: 4, 10, 16 ...)
	if String(st.objective) == "defend" or int(st.think_count) % 3 != 1:
		return
	if w.tick < PROD_FROM_TICK or (int(st.get("launches", 0)) < 1 and w.tick < PROD_NO_LAUNCH_TICK) or int(w.factions[fid].credits) < PROD_MIN_CREDITS:
		return
	var ap: int = ctx.army_pop
	var have := {}
	for e in ctx.units:
		have[String(e.def)] = int(have.get(String(e.def), 0)) + 1
	for b in ctx.buildings:
		for q in b.queue:
			for u in Content.production(String(q.item)).get("spawns", []):
				have[String(u)] = int(have.get(String(u), 0)) + 1
	var g: Dictionary = g6(st)
	var air_seen := int(st.get("g4", {}).get("enemy_air_seen", 0)) > 0
	var f: Dictionary = w.factions[fid]
	for row in PLAN_ROLES:
		if ap < int(row[2]):
			continue
		var item := U.role(w, fid, String(row[0]))
		if item == "":
			continue
		var p := Content.production(item)
		if p.is_empty() or not U.available(w, fid, item):
			continue
		var unit_def := String((p.get("spawns", [""]) as Array)[0])
		var cu := Content.unit(unit_def)
		var want := int(row[1]) + ap / 30
		# AI6-2 (valley a1 s2: Human A at 108/120 pop with 6 medic teams + 3 ambulances and a 33-pop
		# army): evacuation roles scale at half the rate of the combat roles
		if String(row[0]) == "medic" or String(row[0]) == "ambulance":
			want = int(row[1]) + ap / 60
		if bool(cu.get("anti_air_low", false)) or bool(cu.get("anti_air_high", false)):
			want = (1 + ap / 25) if air_seen else 0
		if int(have.get(unit_def, 0)) >= want:
			continue
		var fac = null
		for b in ctx.buildings:
			if b.built and String(b.def) == String(p.get("facility", "")) and (b.queue as Array).size() < 2:
				fac = b
				break
		if fac == null:
			continue
		var pop := 0
		for u in p.get("spawns", []):
			pop += U.pop_of(String(u))
		if int(f.pop) + int(ctx.queued_pop) + pop > int(f.pop_cap):
			continue
		if w.can_afford(fid, p.cost) != "":
			continue
		if SUPPORT_ROLES.has(String(row[0])) and not support_ok(w, fid, st, ctx, int(p.cost.get("salvage", 0))):
			continue
		if U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(fac.id), "item": item}, "g6:%s" % item):
			var q: Dictionary = g.queued
			q[item] = int(q.get(item, 0)) + 1
			U.log_line(st, w, "g6: queued %s (have %d, want %d)" % [item, int(have.get(unit_def, 0)), want])
			return


## Builds one hospital (else a field hospital) at home once there is a real army. Never ahead of
## the base economy: only when no other site is open and the credits cover it with headroom.
static func manage_hospital(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	if w.tick < HOSP_FROM_TICK or int(ctx.army_pop) < HOSP_MIN_ARMY or int(ctx.unfinished_total) > 0:
		return
	if int(st.think_count) % 4 != 0 or String(st.objective) == "defend":
		return
	var defs := hospital_defs(w, fid)
	for h in defs:
		if int(ctx.have.get(h, 0)) > 0:
			return
	var want := ""
	for h in defs:
		if U.available(w, fid, h):
			want = h
			break
	if want == "":
		return
	var cost: Dictionary = Content.building(want).get("cost", {})
	if w.can_afford(fid, cost) != "" or int(w.factions[fid].credits) < int(cost.get("credits", 0)) + HOSP_HEADROOM:
		return
	if int(cost.get("salvage", 0)) > 0 and U.salvage_scarce(w, fid, st):
		return  # AI6-2: no hospital salvage once the map's salvage is scarce
	var key := "g6:build:" + want
	if U.blocked(st, w, key):
		return
	var origin := Econ.find_origin(w, fid, st, want)
	if origin.x < 0:
		U.set_backoff(st, w, key, 600)
		return
	var size := int(Content.building(want).get("size", 2))
	var picks := Econ._pick_engineers(ctx, Vector2(origin) + Vector2(size, size) * 0.5, 2)
	if picks.is_empty():
		return
	if U.submit(w, fid, st, {"type": "build", "unit_ids": picks, "def": want, "origin": origin}, key, {"origin": origin}):
		g6(st).hosp_builds = int(g6(st).hosp_builds) + 1
		U.log_line(st, w, "g6: build %s at %s for the wounded" % [want, str(origin)])
		for id in picks:
			ctx.busy[id] = true


# ---------------------------------------------------------------- drone teams
## Each Drone Team with charges launches at the best target in range by type: EMP at turrets and
## machines, strike at armour, frag at infantry clusters; with nothing in range and a wave out it
## sends a recon drone at the attack goal (one per RECON_EVERY). At 0 charges (tactical mode) it
## breaches remembered walls / gates or takes down nearby infantry. Needs units5.api_ready.
static func manage_drones(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	if not api(G5Mech, "drone_charges"):
		return
	var g: Dictionary = g6(st)
	var ag := U.ag_set(st, ctx)
	var brk := breachers(w, fid)
	var teams := []
	for e in ctx.army:
		var d := String(e.def)
		if brk.has(d) or is_drone_team(d):
			teams.append(e)
	if teams.is_empty():
		return
	# think-cost budget (ai_bench 5k: ~800 teams x 300 contacts): a rotating window per think
	var n := teams.size()
	var lim := mini(n, TEAMS_PER_THINK)
	var off := (int(st.think_count) * TEAMS_PER_THINK) % n
	for j in lim:
		var e: Dictionary = teams[(off + j) % n]
		var def_id := String(e.def)
		if brk.has(def_id):
			_tactical(w, fid, st, ctx, e, false)
			continue
		if _wounded(e):
			continue
		if mode(e) != "drone" or charges(e) <= 0:
			_tactical(w, fid, st, ctx, e, true)
			continue
		var k := str(int(e.id))
		if w.tick - int(g.dt.get(k, -100000)) < DRONE_COOLDOWN:
			continue
		var pick := drone_target(e, ctx.visible)
		if pick.is_empty() and ag.has(int(e.id)) and String(st.objective) == "attack" and w.tick - int(g.recon_t) >= RECON_EVERY:
			var tgt := Vector2(st.attack_target)
			var pos := Vector2(e.pos)
			var c := tgt if pos.distance_to(tgt) <= DRONE_RANGE else pos + (tgt - pos).normalized() * DRONE_RANGE
			var cell := w.cell_of(c)
			pick = {"drone": RECON, "cell": [cell.x, cell.y]}
		if pick.is_empty():
			continue
		var cmd := {"type": "launch_drone", "unit_id": int(e.id), "drone": String(pick.drone)}
		if pick.has("target_id"):
			cmd.target_id = int(pick.target_id)
		else:
			cmd.cell = pick.cell
		if U.submit(w, fid, st, cmd, "g6:drone:" + k):
			g.dt[k] = w.tick
			g.drones[String(pick.drone)] = int(g.drones.get(String(pick.drone), 0)) + 1
			if String(pick.drone) == RECON:
				g.recon_t = w.tick


## Best drone + target for this team among visible enemies within DRONE_RANGE ({} = none).
## Scores: turret / machine -> emp, armour -> strike, infantry with >= 2 others within 3 tiles -> frag.
static func drone_target(e: Dictionary, visible: Array) -> Dictionary:
	var pos := Vector2(e.pos)
	var rng := float(Content.unit(String(e.def)).get("drone_range", DRONE_RANGE))
	var inf := []
	var best := {}
	var best_s := 0.0
	for v in visible:
		var vp := Vector2(v.pos)
		var d := pos.distance_to(vp)
		if d > rng:
			continue
		var vd := String(v.def)
		var s := 0.0
		var dr := ""
		if v.kind == "building":
			if String(Content.building(vd).get("weapon", "")) == "":
				continue
			s = 3.0
			dr = "emp"
		elif v.kind == "unit":
			if U.is_air(vd) or _wounded(v):
				continue
			var cu := Content.unit(vd)
			if String(cu.get("faction", "")) == "machine":
				s = 2.5
				dr = "emp"
			elif U.is_armored(vd):
				s = 3.0 + float(cu.get("hp", 0)) / 1000.0
				dr = "strike"
			else:
				inf.append(v)
				continue
		else:
			continue
		s -= d * 0.02
		if s > best_s:
			best_s = s
			best = {"drone": dr, "target_id": int(v.id)}
	for v in inf:
		var n := 0
		var vp := Vector2(v.pos)
		for o in inf:
			if vp.distance_to(Vector2(o.pos)) <= 3.0:
				n += 1
		if n < 3:
			continue
		var s := 1.0 + 0.6 * float(n) - pos.distance_to(vp) * 0.02
		if s > best_s:
			best_s = s
			best = {"drone": "frag", "target_id": int(v.id)}
	return best


## Tactical breach (remembered enemy wall / gate within BREACH_NEAR), else a takedown of visible
## infantry within TAKEDOWN_NEAR (drone teams only).
static func _tactical(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, e: Dictionary, takedown: bool) -> void:
	var g: Dictionary = g6(st)
	var k := str(int(e.id))
	if w.tick - int(g.tt.get(k, -100000)) < TACTICAL_COOLDOWN or _wounded(e):
		return
	var pos := Vector2(e.pos)
	var seen: Dictionary = st.get("g5", {}).get("fort_seen", {})
	var ks := seen.keys()
	ks.sort()
	var tid := -1
	var ab := ""
	var bd := BREACH_NEAR
	for fk in ks:
		var c: Array = seen[fk]
		var d := pos.distance_to(Vector2(float(c[0]) + 0.5, float(c[1]) + 0.5))
		if d < bd:
			bd = d
			tid = int(fk)
			ab = "breach"
	if tid < 0 and takedown:
		bd = TAKEDOWN_NEAR
		for v in ctx.visible:
			if v.kind != "unit" or U.is_armored(String(v.def)) or U.is_air(String(v.def)):
				continue
			var d := pos.distance_to(Vector2(v.pos))
			if d < bd:
				bd = d
				tid = int(v.id)
				ab = "takedown"
	if tid < 0:
		return
	if U.submit(w, fid, st, {"type": "tactical", "unit_id": int(e.id), "ability": ab, "target_id": tid}, "g6:tac:" + k):
		g.tt[k] = w.tick
		g.tactical[ab] = int(g.tactical.get(ab, 0)) + 1
		U.log_line(st, w, "g6: %s %s on #%d" % [String(e.def), ab, tid])


# ---------------------------------------------------------------- auto resupply / auto evac
## Where the army is: the attack wave's centre while attacking, else the rally point; `behind` is
## that point pulled back toward home (trucks / ambulances stay behind the line).
static func army_anchor(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, behind: float) -> Vector2:
	var ag := U.ag_set(st, ctx)
	var c := Vector2.ZERO
	var n := 0
	if String(st.objective) == "attack":
		for e in ctx.army:
			if ag.has(int(e.id)):
				c += Vector2(e.pos)
				n += 1
	if n == 0:
		return Vector2(st.rally)
	c /= float(n)
	var d := Vector2(st.attack_target) - c
	if d.length() > 0.1:
		c -= d.normalized() * behind
	return c.clamp(Vector2(1, 1), Vector2(float(w.map.w) - 2.0, float(w.map.h) - 2.0))


static func _refresh(g: Dictionary, slot: String, k: String, goal: Vector2, tick: int) -> bool:
	var prev = (g[slot] as Dictionary).get(k)
	if prev == null:
		return true
	if tick - int(prev[2]) < AUTO_MIN:
		return false
	return tick - int(prev[2]) >= AUTO_REFRESH or Vector2(float(prev[0]), float(prev[1])).distance_to(goal) >= AUTO_MOVE


## The first logistics truck roams behind the attack wave (or the rally point), every other one
## stations at the rally point: one truck on Auto behind every army. Needs support.api_ready.
static func manage_support(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	if not api(Support, "needs_supply") or (ctx.trucks as Array).is_empty():
		return
	var g: Dictionary = g6(st)
	var i := 0
	for t in ctx.trucks:
		var goal := army_anchor(w, fid, st, ctx, TRUCK_BEHIND) if i == 0 else Vector2(st.rally)
		var md := "roam" if i == 0 else "station"
		i += 1
		var k := str(int(t.id))
		if not _refresh(g, "auto", k, goal, w.tick):
			continue
		var c := w.cell_of(goal)
		var cmd := {"type": "set_auto_resupply", "unit_id": int(t.id), "mode": md, "center": [c.x, c.y], "radius": AUTO_RADIUS}
		if U.submit(w, fid, st, cmd, "g6:auto:" + k):
			g.auto[k] = [goal.x, goal.y, w.tick]
			g.auto_set = int(g.auto_set) + 1
	# a second truck for the home army once the wave is out
	if (ctx.trucks as Array).size() == 1 and String(st.objective) == "attack" and int(ctx.army_pop) >= int(st.attack_pop):
		var item := U.role(w, fid, "supply")
		if item == "" or w.can_afford(fid, Content.production(item).cost) != "":
			return
		if not support_ok(w, fid, st, ctx, int(Content.production(item).cost.get("salvage", 0))):
			return
		for b in ctx.buildings:
			if b.built and String(b.def) == String(Content.production(item).facility) and (b.queue as Array).is_empty():
				U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(b.id), "item": item}, "g6:truck2")
				return


## True when this truck is on Auto (ai_logistics then leaves its movement to Support).
static func auto_on(st: Dictionary, t: Dictionary) -> bool:
	return api(Support, "needs_supply") and (g6(st).auto as Dictionary).has(str(int(t.id)))


## Medics / ambulances evacuate over the army's area (Medical delivers to the nearest hospital).
## They leave the combat army (ctx.army) so the wave never orders them into the fight.
## Needs medical.api_ready.
static func manage_medical(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	if not api(Medical, "carrying"):
		return
	var g: Dictionary = g6(st)
	var goal := army_anchor(w, fid, st, ctx, 2.0)
	var keep := []
	for e in ctx.army:
		if not is_med(String(e.def)):
			keep.append(e)
			continue
		var k := str(int(e.id))
		if not _refresh(g, "evac", k, goal, w.tick) or (g.evac.has(k) and not (Medical.carrying(e) as Array).is_empty()):
			continue  # never re-centre a carrier with wounded aboard (a re-send restarts its collect phase)
		var c := w.cell_of(goal)
		if U.submit(w, fid, st, {"type": "set_auto_evac", "unit_id": int(e.id), "on": true, "center": [c.x, c.y], "radius": EVAC_RADIUS}, "g6:evac:" + k):
			g.evac[k] = [goal.x, goal.y, w.tick]
			g.evac_set = int(g.evac_set) + 1
	if keep.size() != (ctx.army as Array).size():
		ctx.army = keep


# ---------------------------------------------------------------- usage probe
static func probe(w: SimWorld, st: Dictionary, ctx: Dictionary) -> String:
	var g: Dictionary = g6(st)
	if int(st.think_count) % 8 == 0:
		var fl: Dictionary = g.fielded
		var now := {}
		var plan := {}  # ORCH 2026-10-25 (ai_bench 5k): role lookups once per probe, one test per def
		for row in PLAN_ROLES:
			plan[U.role_unit(w, int(st.fid), String(row[0]))] = true
		var keep := {}
		for e in ctx.units:
			var d := String(e.def)
			if not keep.has(d):
				keep[d] = is_drone_team(d) or is_med(d) or plan.has(d)
			if keep[d]:
				now[d] = int(now.get(d, 0)) + 1
		for d in now:
			fl[d] = maxi(int(fl.get(d, 0)), int(now[d]))
	var dr: Dictionary = g.drones
	g.probe = "drones=strike:%d/frag:%d/recon:%d/emp:%d tactical=%s auto=%d evac=%d hosp=%d queued=%s fielded=%s" % [
		int(dr.strike), int(dr.frag), int(dr.recon), int(dr.emp), str(g.tactical), int(g.auto_set),
		int(g.evac_set), int(g.hosp_builds), str(g.queued), str(g.fielded)]
	return g.probe


static func _in_plan(w: SimWorld, fid: int, def_id: String) -> bool:
	for row in PLAN_ROLES:
		if U.role_unit(w, fid, String(row[0])) == def_id:
			return true
	return false
