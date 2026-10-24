extends RefCounted
## AI G2 logistics (owner: agent G2-ai). Contract: docs/CONTRACTS_G2.md sections 3, 4 and 6.
## - Resupply pull-back: army units below AMMO_LOW ammo (or vehicles below FUEL_LOW fuel) leave the
##   fight for the nearest supply point (the escorting truck when close, else an own HQ/depot) and
##   are held out of army orders until refilled (or RESUPPLY_TIMEOUT), then re-commit.
## - Logistics truck: one per attack group, trailing TRUCK_BEHIND tiles behind the group centroid.
## - Repair: idle engineers (or one gatherer) repair damaged own vehicles/buildings near the base.
## - Bridge: the span is a neutral public-map structure. Its ruin is learned only while one of its
##   cells is visible to this side. A ruined span on our route -> reroute via a ford, and send two
##   engineers to repair it when no visible enemy is within BRIDGE_SAFE tiles.
## All state lives in st.g2 (serializable). Fairness: see the convention in ai_util.gd.

const U = preload("res://sim/ai/ai_util.gd")
const Repair = preload("res://sim/systems/repair.gd")

const AMMO_LOW := 0.3
const AMMO_DONE := 0.9
const FUEL_LOW := 0.25
const FUEL_DONE := 0.8
const RESUPPLY_TIMEOUT := 1200
const NEAR_TRUCK := 14.0
const IN_SUPPLY := 6.5
const TRUCK_BEHIND := 6.0
const REPAIR_RADIUS := 16.0
const MAX_REPAIRERS := 2
const REPAIR_SALVAGE_MIN := 250
const BRIDGE_SAFE := 10.0
const AMMO_FLOOR := 400
const FUEL_FLOOR := 300


static func new_g2() -> Dictionary:
	return {"resupply": {}, "flank": {}, "flank_next": 0, "officer_id": -1, "stage": "", "stage_tick": 0,
		"truck_id": -1, "bridge_id": -1, "bridge_ruined": false, "bridge_crew": [], "reroute": -1,
		"pub_res": [], "refills": 0, "pullbacks": 0, "repairs": 0, "flanks": 0, "officer_waves": 0,
		"withdrawals": 0, "bridge_repairs": 0, "probe": ""}


static func ammo_frac(e: Dictionary) -> float:
	var amax: float = U.ud(String(e.def)).amax
	if amax <= 0.0 or not e.has("ammo"):
		return 1.0
	return float(e.ammo) / amax


static func fuel_frac(e: Dictionary) -> float:
	var fmax: float = U.ud(String(e.def)).fmax
	if fmax <= 0.0 or not e.has("fuel"):
		return 1.0
	return float(e.fuel) / fmax


static func truck(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary):
	var t = U.own(w, fid, int(st.g2.truck_id))
	if t == null and not ctx.trucks.is_empty():
		t = ctx.trucks[0]
		st.g2.truck_id = int(t.id)
	return t


## Nearest supply point for unit e: [pos, label] or [] when this side has none.
## G3a: ammo comes from buildings flagged is_hq / supply_point; an energy unit low on charge goes to
## the nearest building with `recharge` instead (Machine core / charging hubs).
static func _supply_point(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, e: Dictionary, charge: bool = false) -> Array:
	var p := Vector2(e.pos)
	var t = truck(w, fid, st, ctx)
	if not charge and t != null and Vector2(t.pos).distance_to(p) <= NEAR_TRUCK:
		var dt := p - Vector2(t.pos)
		return [Vector2(t.pos) + (dt.normalized() * 2.0 if dt.length() > 0.1 else Vector2.ZERO), "truck"]
	var best = null
	var best_d := INF
	for b in ctx.buildings:
		var bd: Dictionary = Content.building(String(b.def))
		if not b.built:
			continue
		if charge:
			if int(bd.get("recharge", 0)) <= 0:
				continue
		elif not (bool(bd.get("is_hq", false)) or bool(bd.get("supply_point", false))):
			continue
		var d := Vector2(b.pos).distance_to(p)
		if d < best_d:
			best_d = d
			best = b
	if best == null:
		return []
	var away := p - Vector2(best.pos)
	var off := away.normalized() * 3.0 if away.length() > 0.1 else U.front_dir(w, fid) * 3.0
	return [Vector2(best.pos) + off, String(best.def)]


## Moves starving army units to supply and holds them (ctx.held) until refilled. Runs before the army.
static func manage_resupply(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var g2: Dictionary = st.g2
	var rs: Dictionary = g2.resupply
	var stock: Dictionary = w.factions[fid].stock
	for id in rs.keys():
		var e = U.own(w, fid, int(id))
		if e == null:
			rs.erase(id)
			continue
		var done := ammo_frac(e) >= AMMO_DONE and fuel_frac(e) >= FUEL_DONE
		if done or w.tick - int(rs[id].tick) > RESUPPLY_TIMEOUT:
			rs.erase(id)
			if done:
				g2.refills = int(g2.refills) + 1
				U.log_line(st, w, "%s #%d resupplied (ammo %d%%); re-committing" % [String(e.def), int(e.id), roundi(ammo_frac(e) * 100.0)])
	var moves := {}
	var ammo_ok := int(stock.get("ammo", 0)) >= 20
	var fuel_ok := int(stock.get("fuel", 0)) >= 20
	for e in ctx.army:
		var id := int(e.id)
		if rs.has(id):
			continue
		var u := U.ud(String(e.def))  # G3b think cost: one cached per-def lookup per unit
		var amax: float = u.amax
		var af := float(e.ammo) / amax if amax > 0.0 and e.has("ammo") else 1.0
		var dry := af <= 0.0
		var low_ammo := af < AMMO_LOW and (dry or ammo_ok)
		var energy: bool = u.energy
		var low_fuel := false
		if bool(u.veh) or energy:
			var fmax: float = u.fmax
			var ff := float(e.fuel) / fmax if fmax > 0.0 and e.has("fuel") else 1.0
			low_fuel = ff < FUEL_LOW and (energy or fuel_ok)
		if not low_ammo and not low_fuel:
			continue
		var sp := _supply_point(w, fid, st, ctx, e, energy and low_fuel and not low_ammo)
		if sp.is_empty():
			continue
		rs[id] = {"tick": w.tick}
		g2.pullbacks = int(g2.pullbacks) + 1
		if Vector2(e.pos).distance_to(Vector2(sp[0])) <= IN_SUPPLY:
			continue  # already in range of the point: just keep it out of the push until refilled
		var key := "%s|%d|%d" % [String(sp[1]), roundi(sp[0].x), roundi(sp[0].y)]
		if not moves.has(key):
			moves[key] = {"to": sp[0], "ids": [], "what": String(sp[1])}
		moves[key].ids.append(id)
	for key in moves:
		var mv: Dictionary = moves[key]
		U.submit(w, fid, st, {"type": "move", "unit_ids": mv.ids, "target": mv.to}, "resupply:" + String(key))
		U.log_line(st, w, "%d unit(s) low on ammo/fuel -> resupply at the %s" % [mv.ids.size(), String(mv.what)])
	# held units leave the army list for this think (their attack-group membership is kept)
	var army := []
	for e in ctx.army:
		if rs.has(int(e.id)):
			ctx.held.append(e)
		else:
			army.append(e)
	ctx.army = army


## Keeps the truck ~TRUCK_BEHIND tiles behind the attack group, else parked behind the rally point.
static func manage_truck(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var t = truck(w, fid, st, ctx)
	if t == null:
		return
	var goal := Vector2(st.rally) - U.front_dir(w, fid) * 2.0
	var group := []
	var ag := U.ag_set(st, ctx)
	for e in ctx.army:
		if ag.has(int(e.id)):
			group.append(e)
	if String(st.objective) == "attack" and not group.is_empty():
		var c := Vector2.ZERO
		for e in group:
			c += Vector2(e.pos)
		c /= float(group.size())
		var d := Vector2(st.attack_target) - c
		goal = c - (d.normalized() * TRUCK_BEHIND if d.length() > 0.1 else Vector2.ZERO)
	goal = goal.clamp(Vector2(1, 1), Vector2(float(w.map.w) - 2.0, float(w.map.h) - 2.0))
	# ORCH (G3a, FFA seed 2 grind): while a wave is attacking, the supply truck stays with it
	# instead of detouring to repair; otherwise low-ammo units commute home to resupply.
	var escorting := String(st.objective) == "attack" and not group.is_empty()
	if not escorting and _truck_repair(w, fid, st, ctx, t):
		return
	if Vector2(t.pos).distance_to(goal) <= 3.0:
		return
	var cur = t.order.get("target")
	if t.moving and typeof(cur) == TYPE_VECTOR2 and (cur as Vector2).distance_to(goal) <= 3.0:
		return
	U.submit(w, fid, st, {"type": "move", "unit_ids": [int(t.id)], "target": goal}, "truck")


## Trains one logistics truck per attack group (the motor pool, when the army is nearly ready).
static func manage_truck_production(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, army_pop: int) -> void:
	if truck(w, fid, st, ctx) != null:
		return
	var item := U.role(w, fid, "supply")
	if item == "":
		return
	var fac_def := String(Content.production(item).facility)
	var motor = null
	for b in ctx.buildings:
		if String(b.def) == fac_def and b.built:
			for q in b.queue:
				if String(q.item) == item:
					return
			if motor == null or b.queue.size() < motor.queue.size():
				motor = b
	if motor == null or motor.queue.size() >= 2:
		return
	if army_pop * 4 < int(st.attack_pop) * 3 and String(st.objective) != "attack":
		return
	var p := Content.production(item)
	if w.can_afford(fid, p.cost) != "":
		return
	if U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(motor.id), "item": item}, "queue:truck"):
		U.log_line(st, w, "training a logistics truck for the attack group")


## Idle engineers (else one gatherer) repair damaged own vehicles / buildings near the base.
static func manage_repair(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	# salvage is finite and also buys the army: repair only from a healthy stock
	if int(w.factions[fid].stock.salvage) < REPAIR_SALVAGE_MIN:
		return
	var base := U.base_pos(w, fid)
	var taken := {}
	var crews := 0
	for e in ctx.builders:
		if String(e.order.type) == "repair":
			crews += 1
			taken[int(e.order.get("target_id", -1))] = true
	if crews >= MAX_REPAIRERS:
		return
	var best = null
	var best_f := 1.0
	for b in ctx.buildings:
		if b.built and not taken.has(int(b.id)) and Vector2(b.pos).distance_to(base) <= REPAIR_RADIUS:
			var f := float(b.hp) / maxf(1.0, float(b.max_hp))
			if f < 0.75 and f < best_f:
				best_f = f
				best = b
	for u in ctx.units:
		if not U.is_vehicle(String(u.def)) or taken.has(int(u.id)) or u.moving:
			continue
		if Vector2(u.pos).distance_to(base) > REPAIR_RADIUS or Repair.job_for(u).is_empty():
			continue
		var f := float(u.hp) / maxf(1.0, float(u.max_hp))
		for k in u.get("comp", {}):
			if float(u.comp[k]) <= 0.0:
				f = minf(f, 0.3)
		if f < 0.85 and f < best_f:
			best_f = f
			best = u
	if best == null:
		return
	var pick = null
	var pick_d := INF
	for pass_i in 2:
		for e in ctx.builders:
			var ot := String(e.order.type)
			if ctx.busy.has(int(e.id)) or (ot != "idle" if pass_i == 0 else ot != "gather"):
				continue
			var d := Vector2(e.pos).distance_to(Vector2(best.pos))
			if d < pick_d:
				pick_d = d
				pick = e
		if pick != null:
			break
	if pick == null:
		return
	if U.submit(w, fid, st, {"type": "repair", "unit_ids": [int(pick.id)], "target_id": int(best.id)}, "repair:%d" % int(best.id)):
		ctx.busy[int(pick.id)] = true
		st.g2.repairs = int(st.g2.repairs) + 1
		U.log_line(st, w, "engineer #%d repairs %s #%d (%d%%)" % [int(pick.id), String(best.def), int(best.id), roundi(best_f * 100.0)])


## G3a: a supply vehicle that can_repair (Human B recovery truck) fixes a damaged own vehicle within
## TRUCK_REPAIR_RANGE (not moving) before it goes back to trailing the wave. True while busy.
const TRUCK_REPAIR_RANGE := 9.0


static func _truck_repair(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, t: Dictionary) -> bool:
	if not U.uflag(String(t.def), "can_repair"):
		return false
	if String(t.order.type) == "repair":
		return true
	if int(w.factions[fid].stock.salvage) < REPAIR_SALVAGE_MIN / 2:
		return false
	var best = null
	var best_f := 0.7
	for u in ctx.units:
		if int(u.id) == int(t.id) or u.moving or not U.is_vehicle(String(u.def)):
			continue
		if Vector2(u.pos).distance_to(Vector2(t.pos)) > TRUCK_REPAIR_RANGE:
			continue
		var f := float(u.hp) / maxf(1.0, float(u.max_hp))
		if f < best_f:
			best_f = f
			best = u
	if best == null:
		return false
	if U.submit(w, fid, st, {"type": "repair", "unit_ids": [int(t.id)], "target_id": int(best.id)}, "truck_repair"):
		st.g2.repairs = int(st.g2.repairs) + 1
		U.log_line(st, w, "%s #%d repairs %s #%d (%d%%)" % [String(t.def), int(t.id), String(best.def), int(best.id), roundi(best_f * 100.0)])
		return true
	return false
