extends RefCounted
## Support (owner: SUPPORT). Logistics-truck Auto Resupply. CONTRACTS_G5 sections 4, 5, 6, 10.
## Command: set_auto_resupply {issuer, unit_id, mode: off|station|roam, center?: [x,y], radius?, ammo_pct?, fuel_pct?}
## - station: the truck holds `center`; needy own units inside `radius` are claimed (at most
##   rules.auto_resupply.max_claims at a time), drive to a slot by the truck, are refilled there by the
##   ordinary Supply system (faction stock, CORE10K) and then resume the order they had (e.resume_order).
##   Ships go to the nearest navigable cell by the truck (or an own supply pier inside the radius);
##   helicopters fly over and land (Air land_at / take_off when AIRSYS implements them).
## - roam: the truck visits the neediest claimable unit in its area one by one (lowest supply
##   fraction first, ties by id); the unit keeps its order; the truck follows it while it moves.
## - combat rule: a unit in combat (has a target, or was hit in the last RETURN_FIRE ticks) is never
##   claimed unless its ammo is 0.
## - trucks carry an abstract load (rules.auto_resupply.truck_load). Serving drains it by what Supply
##   hands out per second; at 0 the truck releases its claims, drives to the nearest own built HQ /
##   supply point / refinery, reloads (refill_s) and goes back to work.
## - no doubling up: a claimed unit carries e.resup_by = truck id and no other truck may claim it.
## State (saved, hashed): w.sys_state.support = {trucks: {id: {mode, center: [x,y], radius,
##   thr: {ammo, fuel}, queue: [unit ids], phase: "serve"|"refill", load, t, goal?, tp?, rt?}}, ver,
##   needy?: {unit id: grid cell key}}
## PERF (G5): `needy` is refreshed by a slot scan (ids with id % NEEDY_SLOTS == tick % NEEDY_SLOTS, so
##   every unit once per 2 s) while trucks exist, against the loosest thresholds of the unit's
##   side; claim rounds filter only needy units in the GRID cells near the truck's area, with the same
##   live checks as before (a unit can join up to NEEDY_SLOTS ticks after it became needy). The cell
##   buckets are a runtime cache (w.cache.sup_needy) rebuilt from `needy` after a load.
##   New path orders (claims, retries, roam targets) are capped at MAX_ORDERS per tick (ascending truck
##   id); the rest wait for their truck's next round.
## G5 entity fields: unit e.resup_by (int truck id while claimed), e.resume_order (Dictionary, station
##   mode only), e.resup_t (claim tick); truck e.supply_load (int, mirror of the state for UI).
## Aircraft (def `aircraft`): Supply skips them (AIRSYS CR), so a truck restocks its claimed aircraft
##   itself within rules.supply.radius at the Supply per-second rates, drawn from the faction stock
##   (cause "resupply"). AIRSYS is reached only through SimWorld.COMMANDS / SimWorld.Air at run time,
##   so this file never fails to compile on an AIRSYS signature change.

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const HotState = preload("res://sim/hot_state.gd")   # direct dict writes are followed by HotState.touch

const STEP := 10                 # ticks between one truck's decisions (0.5 s), bucketed by (tick + id)
const REPATH := 40               # min ticks between path orders toward the same goal (PERF CR)
const RETURN_FIRE := 60          # = Combat.RETURN_FIRE_TICKS: "in combat" window after a hit
const NAVAL := ["naval", "naval_small"]
const AIRLOW := ["air", "air_low"]
const NEEDY_SLOTS := 40
const GRID := 16.0
const SLACK := 6.0               # tiles a unit may have moved since its last needy scan
const MAX_ORDERS := 8


static func cfg() -> Dictionary:
	return Content.rules().get("auto_resupply", {})


static func _state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("support"):
		w.sys_state["support"] = {"trucks": {}, "ver": 1}
	return w.sys_state["support"]


static func _mc(e: Dictionary) -> String:
	return String(Content.unit(String(e.def)).get("move_class", "foot"))


# ================================================================ public API (support.api_ready)
## True when e is below its thresholds (defaults: ammo < 40%, fuel < 30%, drone_charges == 0).
static func needs_supply(w: SimWorld, e: Dictionary, thr: Dictionary = {}) -> bool:
	if e.kind != "unit" or bool(e.get("wounded", false)):
		return false
	var d := Content.unit(String(e.def))
	if bool(d.get("is_supply", false)):
		return false
	var c := cfg()
	var at := float(thr.get("ammo", c.get("ammo_pct", 40))) / 100.0
	var ft := float(thr.get("fuel", c.get("fuel_pct", 30))) / 100.0
	var am := int(d.get("ammo_max", 0))
	if am > 0 and e.has("ammo") and float(e.ammo) < at * float(am):
		return true
	var fm := float(d.get("fuel_max", 0))
	if fm > 0.0 and e.has("fuel") and not bool(d.get("energy", false)) and float(e.fuel) < ft * fm:
		return true
	if e.has("drone_charges") and int(e.drone_charges) == 0:
		return true
	return false


## Fraction of supply left (min over ammo / fuel / drone charges), 1.0 = full. Lower = needier.
static func supply_frac(e: Dictionary) -> float:
	var d := Content.unit(String(e.def))
	var f := 1.0
	var am := int(d.get("ammo_max", 0))
	if am > 0 and e.has("ammo"):
		f = minf(f, float(e.ammo) / float(am))
	var fm := float(d.get("fuel_max", 0))
	if fm > 0.0 and e.has("fuel") and not bool(d.get("energy", false)):
		f = minf(f, float(e.fuel) / fm)
	if e.has("drone_charges") and int(e.drone_charges) == 0:
		f = 0.0
	return f


static func is_full(e: Dictionary) -> bool:
	var d := Content.unit(String(e.def))
	if e.has("ammo") and int(e.ammo) < int(d.get("ammo_max", 0)):
		return false
	var fm := float(d.get("fuel_max", 0))
	# fuel tolerance: aircraft burn fuel while hovering between Supply rounds (2% or 1 unit)
	if e.has("fuel") and not bool(d.get("energy", false)) and float(e.fuel) < fm - maxf(1.0, fm * 0.02):
		return false
	if e.has("drone_charges") and int(e.drone_charges) == 0:
		return false
	return true


static func in_combat(w: SimWorld, e: Dictionary) -> bool:
	return int(e.get("target", -1)) >= 0 or w.tick - int(e.get("last_hit_tick", -100000)) <= RETURN_FIRE


## The truck state for id, or {} when the truck has no auto mode.
static func truck_state(w: SimWorld, id: int) -> Dictionary:
	return (_state(w).trucks as Dictionary).get(id, {})


# ================================================================ command
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if String(cmd.get("type", "")) != "set_auto_resupply":
		return "Unknown command."
	var e = w.entities.get(int(cmd.get("unit_id", -1)))
	if e == null or e.kind != "unit" or int(e.owner) != int(cmd.get("issuer", -1)):
		return "Not your unit."
	if not bool(Content.unit(String(e.def)).get("is_supply", false)):
		return "Only supply trucks can auto-resupply."
	var mode := String(cmd.get("mode", ""))
	if not ["off", "station", "roam"].has(mode):
		return "Unknown resupply mode '%s'." % mode
	if cmd.has("center"):
		var c = cmd.center
		if typeof(c) != TYPE_ARRAY or (c as Array).size() != 2:
			return "Bad center."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var tid := int(cmd.unit_id)
	var e: Dictionary = w.entities[tid]
	var st := _state(w)
	if st.trucks.has(tid):
		_release_all(w, st.trucks[tid])
	if String(cmd.mode) == "off":
		st.trucks.erase(tid)
		e.erase("supply_load")
		return
	var c := cfg()
	var center: Array = [float(e.pos.x), float(e.pos.y)]
	if cmd.has("center"):
		center = [float(cmd.center[0]), float(cmd.center[1])]
	var thr := {"ammo": _pct(cmd.get("ammo_pct", c.get("ammo_pct", 40))),
		"fuel": _pct(cmd.get("fuel_pct", c.get("fuel_pct", 30)))}
	var load := int(c.get("truck_load", 600))
	var prev: Dictionary = st.trucks.get(tid, {})
	if not prev.is_empty():
		load = int(prev.load)
	st.trucks[tid] = {"mode": String(cmd.mode), "center": center,
		"radius": clampf(float(cmd.get("radius", c.get("radius", 12))), 2.0, 48.0),
		"thr": thr, "queue": [], "phase": "serve", "load": load, "t": w.tick}
	e.supply_load = load


static func _pct(v) -> float:
	var f := float(v)
	return clampf(f * 100.0 if f <= 1.0 else f, 0.0, 100.0)


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("support")
	if st == null or (st.trucks as Dictionary).is_empty():
		return
	var ids := []
	for tid in st.trucks:
		if (w.tick + int(tid)) % STEP == 0:   # PERF: each truck on its own tick bucket
			ids.append(tid)
	ids.sort()
	_scan_needy(w, st)
	var bud := {"n": 0}
	for tid in ids:
		var e = w.entities.get(int(tid))
		var ts: Dictionary = st.trucks[tid]
		if e == null or e.kind != "unit":
			_release_all(w, ts)
			st.trucks.erase(tid)
			continue
		_drop_dead_claims(w, ts)
		if String(ts.phase) == "refill":
			_refill_step(w, e, ts)
		elif int(ts.load) <= 0 and int(cfg().get("truck_load", 600)) > 0:
			_start_refill(w, e, ts)
		elif String(ts.mode) == "station":
			_station_step(w, e, ts, bud)
		else:
			_roam_step(w, e, ts, bud)
		e.supply_load = int(ts.load)
		HotState.touch(w, int(tid))


# ================================================================ station / roam
static func _station_step(w: SimWorld, e: Dictionary, ts: Dictionary, bud: Dictionary) -> void:
	var tid := int(e.id)
	var c := cfg()
	var center := Vector2(float(ts.center[0]), float(ts.center[1]))
	if (Vector2(e.pos) - center).length() > 3.0 and not bool(e.moving) and w.tick - int(ts.get("tp", -100000)) >= REPATH:
		Movement.order_move(w, e, center)
		ts["tp"] = w.tick
	var serve_r := float(c.get("serve_radius", 4.0))
	var wait := int(float(c.get("max_wait_s", 90)) * 20.0)
	for uid in (ts.queue as Array).duplicate():
		var u: Dictionary = w.entities[int(uid)]
		var o: Dictionary = u.order
		if String(o.get("type", "idle")) != "idle" and int(o.get("resup", -1)) != tid:
			u.erase("resume_order")   # the player gave a new order: drop the claim, keep that order
			_release(w, u, ts)
			continue
		if is_full(u) or w.tick - int(u.get("resup_t", w.tick)) > wait:
			_release(w, u, ts)
			continue
		var d := (Vector2(u.pos) - Vector2(e.pos)).length()
		if d <= serve_r:
			if AIRLOW.has(_mc(u)) and not bool(u.moving) and not _landed(u):
				_air_cmd(w, u, "land_at", w.cell_of(u.pos))
		elif not bool(u.moving) and String(o.get("type", "idle")) == "idle" and (w.tick - int(u.get("resup_t", 0))) % 100 < STEP and int(bud.n) < MAX_ORDERS:
			bud.n = int(bud.n) + 1
			_send(w, u, e, (ts.queue as Array).find(int(uid)))   # stuck short of the truck: retry every 5 s
	_drain(w, e, ts)
	var maxc := int(c.get("max_claims", 6))
	if (ts.queue as Array).size() >= maxc or not _round(w, tid) or int(bud.n) >= MAX_ORDERS:
		return
	# top-k batches (k = free claim slots) walk the same neediest-first order as one full sort: a
	# processed unit is claimed (resup_by) or skipped (resup_skip), so the next batch excludes it.
	while (ts.queue as Array).size() < maxc and int(bud.n) < MAX_ORDERS:
		var batch := _candidates(w, e, ts, maxc - (ts.queue as Array).size())
		if batch.is_empty():
			break
		for u in batch:
			if (ts.queue as Array).size() >= maxc or int(bud.n) >= MAX_ORDERS:
				break
			bud.n = int(bud.n) + 1
			_claim(w, u, ts, tid, true)
			if not _send(w, u, e, (ts.queue as Array).size() - 1):
				u.resup_skip = w.tick + 400   # unreachable: do not retry for 20 s
				_release(w, u, ts)


static func _roam_step(w: SimWorld, e: Dictionary, ts: Dictionary, bud: Dictionary) -> void:
	var tid := int(e.id)
	var c := cfg()
	var serve_r := float(c.get("serve_radius", 4.0))
	var wait := int(float(c.get("max_wait_s", 90)) * 20.0)
	var q: Array = ts.queue
	if not q.is_empty():
		var u: Dictionary = w.entities[int(q[0])]
		if is_full(u) or w.tick - int(u.get("resup_t", w.tick)) > wait or in_combat(w, u) and int(u.get("ammo", 0)) > 0:
			_release(w, u, ts)
		else:
			var d := (Vector2(u.pos) - Vector2(e.pos)).length()
			if d > serve_r:
				var g = ts.get("goal")
				if g == null or (Vector2(float(g[0]), float(g[1])) - Vector2(u.pos)).length() > 3.0 or (not bool(e.moving) and w.tick - int(ts.get("tp", -100000)) >= REPATH):
					Movement.order_move(w, e, u.pos)
					ts["goal"] = [float(u.pos.x), float(u.pos.y)]
					ts["tp"] = w.tick
			elif bool(e.moving):
				Movement.stop_path(e)
				e.order = {"type": "idle"}
	_drain(w, e, ts)
	if not q.is_empty():
		return
	if int(bud.n) >= MAX_ORDERS:
		return   # capped: look again on the next round
	var cands := _candidates(w, e, ts, 1)
	if not cands.is_empty():
		bud.n = int(bud.n) + 1
		var u: Dictionary = cands[0]
		_claim(w, u, ts, tid, false)
		Movement.order_move(w, e, u.pos)
		ts["goal"] = [float(u.pos.x), float(u.pos.y)]
		return
	ts.erase("goal")
	var center := Vector2(float(ts.center[0]), float(ts.center[1]))
	if (Vector2(e.pos) - center).length() > 3.0 and not bool(e.moving) and w.tick - int(ts.get("tp", -100000)) >= REPATH:
		Movement.order_move(w, e, center)
		ts["tp"] = w.tick


## The k neediest unclaimed own units inside the truck's area (lowest supply_frac first, ties by id).
static func _candidates(w: SimWorld, e: Dictionary, ts: Dictionary, k: int) -> Array:
	var out := []
	var keys := []   # [frac, id] parallel to out, ascending
	var tid := int(e.id)
	var fid := int(e.owner)
	var center := Vector2(float(ts.center[0]), float(ts.center[1]))
	var r2 := float(ts.radius) * float(ts.radius)
	var bk := _buckets(w, _state(w))
	var rr := float(ts.radius) + SLACK
	var x0 := int(floorf((center.x - rr) / GRID))
	var x1 := int(floorf((center.x + rr) / GRID))
	var y0 := int(floorf((center.y - rr) / GRID))
	var y1 := int(floorf((center.y + rr) / GRID))
	var pool := []
	for gx in range(x0, x1 + 1):
		for gy in range(y0, y1 + 1):
			var cell = bk.get(gx * 65536 + gy)
			if cell != null:
				for id in cell:
					pool.append(id)
	for id in pool:
		var u = w.entities.get(id)
		if u == null or u.kind != "unit" or int(u.owner) != fid:
			continue
		if int(u.id) == tid or u.has("resup_by") or u.has("evac_by"):
			continue
		if (Vector2(u.pos) - center).length_squared() > r2 or int(u.get("resup_skip", -1)) > w.tick:
			continue
		if _mc(u) == "air_high" or not needs_supply(w, u, ts.thr):
			continue
		if in_combat(w, u) and not (u.has("ammo") and int(u.ammo) <= 0):
			continue   # combat rule: only an empty unit leaves a fight
		var f := supply_frac(u)
		var uid := int(u.id)
		var n := out.size()
		if n >= k:
			var lk: Array = keys[n - 1]
			if not (f < float(lk[0]) or (f == float(lk[0]) and uid < int(lk[1]))):
				continue
		var i := n
		while i > 0:
			var pk: Array = keys[i - 1]
			if f < float(pk[0]) or (f == float(pk[0]) and uid < int(pk[1])):
				i -= 1
			else:
				break
		out.insert(i, u)
		keys.insert(i, [f, uid])
		if out.size() > k:
			out.pop_back()
			keys.pop_back()
	return out


## Slot scan (see header): ids id % NEEDY_SLOTS == tick % NEEDY_SLOTS against the loosest
## thresholds of the side's trucks; keeps sys_state.support.needy and the runtime buckets in step.
static func _scan_needy(w: SimWorld, st: Dictionary) -> void:
	if not st.has("needy"):
		st["needy"] = {}
	var nd: Dictionary = st.needy
	var lo := {}   # owner -> loosest thresholds of its trucks
	for tid in st.trucks:
		var te = w.entities.get(int(tid))
		if te == null:
			continue
		var th: Dictionary = st.trucks[tid].thr
		var o := int(te.owner)
		var cur = lo.get(o)
		if cur == null:
			lo[o] = {"ammo": float(th.ammo), "fuel": float(th.fuel)}
		else:
			cur.ammo = maxf(float(cur.ammo), float(th.ammo))
			cur.fuel = maxf(float(cur.fuel), float(th.fuel))
	var cache = w.cache.get("sup_needy")
	var bk = cache.b if cache != null and is_same(cache.src, nd) else null
	var nid := int(w.next_id)
	var id := posmod(w.tick, NEEDY_SLOTS)
	var dc := {}   # def -> [skip (supply / air_high), ammo_max, fuel_max (0 = energy or none)]
	while id < nid:
		var u = w.entities.get(id)
		var k := -1
		if u != null and u.kind == "unit" and lo.has(int(u.owner)) and not u.get("wounded", false):
			var di = dc.get(u.def)
			if di == null:
				var d := Content.unit(String(u.def))
				var fm := float(d.get("fuel_max", 0))
				di = [bool(d.get("is_supply", false)) or String(d.get("move_class", "foot")) == "air_high",
					int(d.get("ammo_max", 0)), 0.0 if bool(d.get("energy", false)) else fm]
				dc[u.def] = di
			if not di[0]:
				var th: Dictionary = lo[int(u.owner)]
				# = needs_supply(w, u, th) for a non-supply, non-air_high, non-wounded unit
				var need: bool = (di[1] > 0 and u.has("ammo") and float(u.ammo) < float(th.ammo) / 100.0 * float(di[1])) 					or (di[2] > 0.0 and u.has("fuel") and float(u.fuel) < float(th.fuel) / 100.0 * float(di[2])) 					or (u.has("drone_charges") and int(u.drone_charges) == 0)
				if need:
					k = _gkey(Vector2(u.pos))
		var old = nd.get(id)
		if old != null and int(old) != k:
			nd.erase(id)
			if bk != null and bk.has(int(old)):
				(bk[int(old)] as Dictionary).erase(id)
		if k >= 0 and (old == null or int(old) != k):
			nd[id] = k
			if bk != null:
				if not bk.has(k):
					bk[k] = {}
				bk[k][id] = 1
		id += NEEDY_SLOTS


static func _gkey(p: Vector2) -> int:
	return int(floorf(p.x / GRID)) * 65536 + int(floorf(p.y / GRID))


## Runtime cell buckets of sys_state.support.needy (rebuilt when the saved dict object changes).
static func _buckets(w: SimWorld, st: Dictionary) -> Dictionary:
	var nd: Dictionary = st.get("needy", {})
	var cache = w.cache.get("sup_needy")
	if cache != null and is_same(cache.src, nd):
		return cache.b
	var b := {}
	for id in nd:
		var k := int(nd[id])
		if not b.has(k):
			b[k] = {}
		b[k][int(id)] = 1
	w.cache["sup_needy"] = {"src": nd, "b": b}
	return b


static func _claim(w: SimWorld, u: Dictionary, ts: Dictionary, tid: int, station: bool) -> void:
	u.resup_by = tid
	u.resup_t = w.tick
	if station:
		u.resume_order = (u.order as Dictionary).duplicate(true)
	(ts.queue as Array).append(int(u.id))
	w.emit("ResupplyClaimed", {"truck": tid, "unit": int(u.id), "mode": "station" if station else "roam"})


const SLOTS := [Vector2(2, 0), Vector2(0, 2), Vector2(-2, 0), Vector2(0, -2), Vector2(2, 2), Vector2(-2, 2), Vector2(-2, -2), Vector2(2, -2)]

## Orders u to its slot by the truck (ships: an own supply pier in range, else the nearest water).
static func _send(w: SimWorld, u: Dictionary, truck: Dictionary, i: int) -> bool:
	var mc := _mc(u)
	var goal: Vector2 = Vector2(truck.pos) + Vector2(SLOTS[posmod(i, SLOTS.size())])
	if NAVAL.has(mc):
		var p = _pier_near(w, truck)
		if p != null:
			goal = Vector2(p.cell) + Vector2(float(p.size), float(p.size)) * 0.5
	if not AIRLOW.has(mc) and not Movement.is_air(mc):
		var cell := Movement.nearest_free_cell(w, w.cell_of(goal), mc, Movement.team_of(w, u))
		goal = Vector2(cell) + Vector2(0.5, 0.5)
	u.order = {"type": "move", "target": goal, "resup": int(truck.id)}
	var ok := Movement.order_path(w, u, goal)
	if not ok:
		u.order = {"type": "idle"}
	HotState.touch(w, int(u.id))
	return ok


static func _pier_near(w: SimWorld, truck: Dictionary):
	var best = null
	var bd := INF
	var r := float(Content.rules().get("supply", {}).get("radius", 8)) + 4.0
	for b in SimIndex.of(w, "building"):
		if int(b.owner) != int(truck.owner) or not bool(b.built) or not w.entities.has(int(b.id)):
			continue
		if not (String(b.def).ends_with("_supply_pier") or bool(Content.building(String(b.def)).get("pier", false))):
			continue
		var d := Construction.footprint_dist(truck.pos, b.cell, int(b.size))
		if d <= r and d < bd:
			bd = d
			best = b
	return best


# ================================================================ claims
## Ends u's claim. Station units go back to their saved order (unless the player replaced it).
static func _release(w: SimWorld, u: Dictionary, ts: Dictionary) -> void:
	(ts.queue as Array).erase(int(u.id))
	var tid := int(u.get("resup_by", -1))
	u.erase("resup_by")
	u.erase("resup_t")
	if not u.has("resume_order"):
		return
	var o: Dictionary = u.resume_order
	u.erase("resume_order")
	if AIRLOW.has(_mc(u)) and _landed(u):
		_air_cmd(w, u, "take_off", Vector2i(-1, -1))
	u.order = o
	var tg = o.get("target")
	if typeof(tg) == TYPE_VECTOR2 and String(o.get("type", "idle")) != "idle":
		if not Movement.order_path(w, u, tg) and String(o.type) == "move":
			u.order = {"type": "idle"}
	else:
		Movement.stop_path(u)
	HotState.touch(w, int(u.id))
	w.emit("ResupplyResumed", {"truck": tid, "unit": int(u.id), "order": String(o.get("type", "idle"))})


static func _release_all(w: SimWorld, ts: Dictionary) -> void:
	for uid in (ts.queue as Array).duplicate():
		var u = w.entities.get(int(uid))
		if u != null:
			_release(w, u, ts)
	ts.queue = []


static func _drop_dead_claims(w: SimWorld, ts: Dictionary) -> void:
	var keep := []
	for uid in ts.queue:
		var u = w.entities.get(int(uid))
		if u != null and u.has("resup_by"):
			keep.append(int(uid))
	ts.queue = keep


## Drains the truck load once per second by what Supply hands its served units (same per-round caps).
static func _drain(w: SimWorld, e: Dictionary, ts: Dictionary) -> void:
	if not _round(w, int(e.id)):
		return
	var sc: Dictionary = Content.rules().get("supply", {})
	var r := float(sc.get("radius", 8))
	var rate: Dictionary = sc.get("refill_per_second", {})
	var used := 0
	for uid in ts.queue:
		var u: Dictionary = w.entities[int(uid)]
		if (Vector2(u.pos) - Vector2(e.pos)).length() > r:
			continue
		var d := Content.unit(String(u.def))
		var wa := 0
		var wf := 0
		if u.has("ammo"):
			wa = mini(maxi(0, int(d.get("ammo_max", 0)) - int(u.ammo)), int(rate.get("ammo", 0)))
		if u.has("fuel") and not bool(d.get("energy", false)):
			wf = mini(maxi(0, int(ceil(float(d.get("fuel_max", 0)) - float(u.fuel)))), int(rate.get("fuel", 0)))
		used += wa + wf
		if d.has("aircraft"):
			_serve_aircraft(w, u, d, wa, wf)
	ts.load = maxi(0, int(ts.load) - used)


## Restock one claimed aircraft from the faction stock (Supply skips aircraft).
static func _serve_aircraft(w: SimWorld, u: Dictionary, d: Dictionary, wa: int, wf: int) -> void:
	var fid := int(u.owner)
	if not w.factions.has(fid):
		return
	var stock: Dictionary = w.factions[fid].stock
	var na := mini(wa, int(stock.get("ammo", 0)))
	var nf := mini(wf, int(stock.get("fuel", 0)))
	if na > 0 and w.spend(fid, {"ammo": na}, "resupply"):
		u.ammo = mini(int(d.get("ammo_max", 0)), int(u.ammo) + na)
	if nf > 0 and w.spend(fid, {"fuel": nf}, "resupply"):
		u.fuel = minf(float(d.get("fuel_max", 0)), float(u.fuel) + float(nf))


# ================================================================ truck self-refill
static func _start_refill(w: SimWorld, e: Dictionary, ts: Dictionary) -> void:
	_release_all(w, ts)
	ts.phase = "refill"
	ts.erase("rt")
	ts.erase("goal")
	w.emit("TruckEmpty", {"truck": int(e.id), "owner": int(e.owner)})
	var b = _nearest_depot(w, e)
	if b != null:
		Movement.order_move(w, e, _bcenter(b))


static func _refill_step(w: SimWorld, e: Dictionary, ts: Dictionary) -> void:
	var b = _nearest_depot(w, e)
	if b == null:
		return   # nothing to reload from: wait
	if Construction.footprint_dist(e.pos, b.cell, int(b.size)) <= 3.0:
		if bool(e.moving):
			Movement.stop_path(e)
			e.order = {"type": "idle"}
		if not ts.has("rt"):
			ts["rt"] = w.tick
		elif w.tick - int(ts.rt) >= int(float(cfg().get("refill_s", 5)) * 20.0):
			ts.load = int(cfg().get("truck_load", 600))
			ts.phase = "serve"
			ts.erase("rt")
			w.emit("TruckRefilled", {"truck": int(e.id), "building": int(b.id)})
	elif not bool(e.moving) and w.tick - int(ts.get("tp", -100000)) >= REPATH:
		Movement.order_move(w, e, _bcenter(b))
		ts["tp"] = w.tick


## Nearest own built HQ / supply point / refinery (footprint distance, ties by id).
static func _nearest_depot(w: SimWorld, e: Dictionary):
	var best = null
	var bd := INF
	for b in SimIndex.of(w, "building"):
		if int(b.owner) != int(e.owner) or not bool(b.built) or not w.entities.has(int(b.id)):
			continue
		var d := Content.building(String(b.def))
		if not (bool(d.get("is_hq", false)) or bool(d.get("supply_point", false)) or d.has("refines")):
			continue
		var dist := Construction.footprint_dist(e.pos, b.cell, int(b.size))
		if dist < bd:
			bd = dist
			best = b
	return best


## Every other decision of a truck (= once per second per truck, on its own bucket): the Supply
## round cadence used for load drain, aircraft restock and new claims.
static func _round(w: SimWorld, tid: int) -> bool:
	return ((w.tick + tid) / STEP) % 2 == 0


static func _bcenter(b: Dictionary) -> Vector2:
	return Vector2(b.cell) + Vector2(float(b.size), float(b.size)) * 0.5


## Issues an AIRSYS command for u when AIRSYS accepts it (the G5 stub refuses: then nothing happens).
static func _air_cmd(w: SimWorld, u: Dictionary, type: String, cell: Vector2i) -> void:
	var cmd := {"type": type, "issuer": int(u.owner), "unit_ids": [int(u.id)]}
	if cell.x >= 0:
		cmd["cell"] = [cell.x, cell.y]
	var h = SimWorld.COMMANDS.get(type)
	if h != null and String(h.validate_command(w, cmd)) == "":
		h.apply_command(w, cmd)


static func _landed(u: Dictionary) -> bool:
	var air = SimWorld.Air
	return air != null and bool(air.is_landed(u))
