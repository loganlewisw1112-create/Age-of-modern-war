extends RefCounted
## AI economy (owner: agent G): build order, building placement, construction crews,
## gathering balance and engineer training. Acts only through U.submit (w.submit).
## Fairness: see the convention in ai_util.gd.

const U = preload("res://sim/ai/ai_util.gd")
const Construction = preload("res://sim/systems/construction.gd")

const PLACE_RADIUS := 13
const PLACE_CHECKS := 50
const SAFE_GATHER_DIST := 22.0
const CREWS_PER_SITE := 2
const AMMO_FLOOR := 400   # G2 faction stock floors (same values as ai_logistics.gd)
const FUEL_FLOOR := 300


## The next building this side wants, or "". Power is counted for planned (unfinished) buildings too.
## G3a: every def comes from the faction's roles. Human B turtles (TURTLE_DEFENCES bunkers), the
## Machine keeps a second charging hub near the front (recharge radius for its energy units).
static func next_build(w: SimWorld, fid: int, ctx: Dictionary) -> String:
	var f: Dictionary = w.factions[fid]
	var have: Dictionary = ctx.have
	var built: Dictionary = ctx.built
	var spare := int(ctx.power_planned)
	var power := U.role(w, fid, "power")
	var barracks := U.role(w, fid, "barracks")
	var depot := U.role(w, fid, "depot")
	var factory := U.role(w, fid, "factory")
	var refinery := U.role(w, fid, "refinery")
	var defense := U.role(w, fid, "defense")
	if power != "" and int(have.get(power, 0)) == 0:
		return power
	if barracks != "" and int(have.get(barracks, 0)) == 0:
		return barracks
	var cap_max := int(Content.rules().pop_cap_max)
	# planned cap counts unfinished buildings too (f.pop_cap lags a tick behind completion)
	var cap := mini(int(ctx.cap_planned), cap_max)
	var free_pop := cap - int(f.pop) - int(ctx.queued_pop)
	if free_pop <= 6 and cap < cap_max and depot != "" and int(Content.building(depot).get("pop_cap", 0)) > 0:
		return depot
	var gen_pending := power != "" and int(ctx.unfinished.get(power, 0)) > 0
	var turtle := U.fac(w, fid) == "human_b"
	# Human B: the first bunker goes up as soon as the barracks stands (turtle opening)
	if turtle and defense != "" and int(have.get(defense, 0)) == 0 and _reqs_built(defense, built):
		if spare < _draw(defense):
			return "" if gen_pending else power
		return defense
	if factory != "" and int(have.get(factory, 0)) == 0 and _reqs_built(factory, built):
		if spare < _draw(factory):
			return "" if gen_pending else power
		return factory
	var fac_built := factory != "" and int(built.get(factory, 0)) > 0
	# G2: a refinery right after the factory keeps fuel/ammo stock up (ore -> fuel + ammo)
	if refinery != "" and int(have.get(refinery, 0)) == 0 and fac_built and _reqs_built(refinery, built):
		if spare < _draw(refinery):
			return "" if gen_pending else power
		return refinery
	var want_def := TURTLE_DEFENCES if turtle else 1
	if defense != "" and int(have.get(defense, 0)) < want_def and fac_built and _reqs_built(defense, built):
		if spare < _draw(defense):
			return "" if gen_pending else power
		return defense
	# Machine: a forward charging hub (the power role carries `recharge`) once the factory stands
	if power != "" and int(Content.building(power).get("recharge", 0)) > 0 and int(have.get(power, 0)) < 2 and fac_built:
		return power
	if spare < 0 and not gen_pending and power != "":
		return power
	# a second refinery when ammo runs short and ore is piling up
	var stock: Dictionary = f.stock
	if refinery != "" and int(have.get(refinery, 0)) == 1 and int(built.get(refinery, 0)) == 1 and int(have.get(defense, 0)) > 0:
		if int(stock.get("ammo", 0)) < AMMO_FLOOR and int(stock.get("ore", 0)) >= 1000:
			if spare < _draw(refinery):
				return "" if gen_pending else power
			return refinery
	return ""


const TURTLE_DEFENCES := 3


## Power a building draws (positive number; 0 for producers).
static func _draw(def_id: String) -> int:
	return maxi(0, -int(Content.building(def_id).get("power", 0)))


static func _reqs_built(def_id: String, built: Dictionary) -> bool:
	for r in Content.building(def_id).get("requires", []):
		if int(built.get(String(r), 0)) == 0:
			return false
	return true


static func manage_construction(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	# 1. keep crews on every unfinished site
	for b in ctx.buildings:
		if b.built:
			continue
		var crew := 0
		for e in ctx.builders:
			if String(e.order.type) == "build" and int(e.order.get("building_id", -1)) == int(b.id):
				crew += 1
		if crew < CREWS_PER_SITE:
			var picks := _pick_engineers(ctx, Vector2(b.pos), CREWS_PER_SITE - crew)
			if not picks.is_empty():
				U.submit(w, fid, st, {"type": "assist_build", "unit_ids": picks, "target_id": int(b.id)}, "assist:%d" % int(b.id))
	# 2. start the next building when affordable
	var want := next_build(w, fid, ctx)
	st.next_build = want
	st.saving_for = ""
	if want == "":
		return
	var sites := int(ctx.unfinished_total)
	var credits := int(w.factions[fid].credits)
	if sites >= 2 or (sites == 1 and credits < 1500):
		return
	var cost: Dictionary = Content.building(want).cost
	if w.can_afford(fid, cost) != "":
		st.saving_for = want
		return
	var key := "build:" + want
	if U.blocked(st, w, key):
		return
	var origin := find_origin(w, fid, st, want)
	if origin.x < 0:
		U.log_line(st, w, "no legal site found for %s" % want)
		U.set_backoff(st, w, key, 400)
		return
	var size := int(Content.building(want).size)
	var centre := Vector2(origin) + Vector2(size, size) * 0.5
	var picks := _pick_engineers(ctx, centre, CREWS_PER_SITE)
	if picks.is_empty():
		return
	if U.submit(w, fid, st, {"type": "build", "unit_ids": picks, "def": want, "origin": origin}, key, {"origin": origin}):
		U.log_line(st, w, "build %s at %s" % [want, str(origin)])
		for id in picks:
			ctx.busy[id] = true


## Nearest builders to `pos` that are not already constructing (and not reserved this think).
static func _pick_engineers(ctx: Dictionary, pos: Vector2, n: int) -> Array:
	var cands := []
	for e in ctx.builders:
		if String(e.order.type) == "build" or ctx.busy.has(int(e.id)):
			continue
		cands.append([Vector2(e.pos).distance_squared_to(pos), int(e.id)])
	cands.sort()
	var out := []
	for i in mini(n, cands.size()):
		out.append(int(cands[i][1]))
	return out


## Deterministic ring search around an anchor near the HQ. Returns Vector2i(-1, -1) if nothing fits.
static func find_origin(w: SimWorld, fid: int, st: Dictionary, def_id: String) -> Vector2i:
	var size := int(Content.building(def_id).size)
	var base := U.base_pos(w, fid)
	var dir := U.front_dir(w, fid)
	var anchor := base + dir * 3.0
	var n_same := w.buildings_of(fid, def_id).size()
	if def_id == U.role(w, fid, "defense"):
		# defences fan out along the front arc (Human B builds three)
		var ang: float = [0.0, 0.7, -0.7, 1.3, -1.3][n_same % 5]
		anchor = base + dir.rotated(float(ang)) * 8.0
	elif def_id == U.role(w, fid, "power") and n_same >= 1 and int(Content.building(def_id).get("recharge", 0)) > 0:
		anchor = base + dir * 9.0  # Machine forward charging hub: recharge near the front
	elif def_id == U.role(w, fid, "power") or def_id == U.role(w, fid, "depot"):
		anchor = base - dir * 3.0
	var occ := {}
	for b in w.buildings_of(fid):
		var bc: Vector2i = b.cell
		for y in int(b.size):
			for x in int(b.size):
				occ[bc + Vector2i(x, y)] = true
	var res_cells := {}
	for r in U.known_resources(w, fid, st.g2.pub_res):
		res_cells[w.cell_of(r.pos)] = true
	var bad := {}
	for o in st.bad_origins:
		bad[o] = true
	var a0 := Vector2i(floori(anchor.x - size * 0.5), floori(anchor.y - size * 0.5))
	var cands := []
	for dy in range(-PLACE_RADIUS, PLACE_RADIUS + 1):
		for dx in range(-PLACE_RADIUS, PLACE_RADIUS + 1):
			var o := a0 + Vector2i(dx, dy)
			var d := Vector2(dx, dy).length()
			if d <= PLACE_RADIUS:
				cands.append([d, o.y, o.x])
	cands.sort()
	var checks := 0
	for c in cands:
		var o := Vector2i(int(c[2]), int(c[1]))
		if bad.has(o) or not _quick_ok(w, fid, o, size, occ, res_cells):
			continue
		checks += 1
		if Construction.placement_error(w, fid, def_id, o) == "":
			return o
		if checks >= PLACE_CHECKS:
			break
	return Vector2i(-1, -1)


## Cheap pre-filter: footprint buildable + explored, and a 1-cell margin free of own buildings,
## resource deposits and the road so crews and convoys keep a path around every building.
static func _quick_ok(w: SimWorld, fid: int, o: Vector2i, size: int, occ: Dictionary, res_cells: Dictionary) -> bool:
	var ex: PackedByteArray = w.fog[fid].explored
	var mw := int(w.map.w)
	for y in range(o.y - 1, o.y + size + 1):
		for x in range(o.x - 1, o.x + size + 1):
			var c := Vector2i(x, y)
			if not w.in_bounds(c):
				return false
			if occ.has(c) or res_cells.has(c):
				return false
			var inside := x >= o.x and x < o.x + size and y >= o.y and y < o.y + size
			var t := w.terrain_at(c)
			if inside:
				if not Terrain.buildable(t) or ex[y * mw + x] == 0:
					return false
			elif t == Terrain.ROAD or t == Terrain.BRIDGE:
				return false
	return true


## Splits crews between ore and salvage by need. Salvage is finite (per-base deposits), ore is
## plentiful, so salvage is the default; ore crews scale with the motor pool's appetite and the
## current stock balance.
static func manage_gather(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var f: Dictionary = w.factions[fid]
	var ore := int(f.stock.ore)
	var sal := int(f.stock.salvage)
	var n_eng: int = ctx.gatherers.size()
	var has_mp := int(ctx.have.get(U.role(w, fid, "factory"), 0)) > 0
	var want_ore := 0
	if has_mp:
		want_ore = int(round(float(n_eng) * 0.4))
		if ore >= 1500 or ore > sal + 500:
			want_ore = mini(want_ore, 1) if ore < 1500 else 0
		elif sal > ore + 300:
			want_ore = int(round(float(n_eng) * 0.6))
	elif ore < 150:
		want_ore = 1
	# G2: a working refinery eats 20 ore / 6 s; keep crews on ore while fuel/ammo stock is short
	var stock_low := int(f.stock.get("ammo", 0)) < AMMO_FLOOR or int(f.stock.get("fuel", 0)) < FUEL_FLOOR
	if int(ctx.built.get(U.role(w, fid, "refinery"), 0)) > 0 and stock_low and ore < 1500:
		want_ore = maxi(want_ore, int(round(float(n_eng) * 0.5)))
	var known := U.known_resources(w, fid, st.g2.pub_res)
	var left := {"ore": 0, "salvage": 0}
	for r in known:
		# unexplored public deposit: amount unknown, counts only as "something left"
		left[String(r.res)] = int(left[String(r.res)]) + (int(r.amount) if int(r.amount) >= 0 else 1)
	if int(left.salvage) <= 0:
		want_ore = n_eng  # nothing left to salvage that we know of
	elif int(left.ore) <= 0:
		want_ore = 0
	want_ore = clampi(want_ore, 0, n_eng)
	st.gather_plan = {"ore": want_ore, "salvage_left": int(left.salvage), "ore_left": int(left.ore)}
	var on := {"ore": [], "salvage": []}
	var idle := []
	for e in ctx.gatherers:
		var ot := String(e.order.type)
		if ot == "gather":
			on[String(e.order.get("res", "salvage"))].append(e)
		elif ot == "idle" and not ctx.busy.has(int(e.id)):
			idle.append(e)
	var drops := []
	for b in ctx.buildings:
		if b.built and bool(Content.building(b.def).get("deposit", false)):
			drops.append(Vector2(b.pos))
	if drops.is_empty():
		return
	var n_ore: int = on.ore.size()
	for e in idle:
		var res := "ore" if n_ore < want_ore else "salvage"
		if res == "ore":
			n_ore += 1
		_send_gather(w, fid, st, e, res, known, drops)
	# rebalance at most one crew per think
	if idle.is_empty():
		if n_ore > want_ore and not on.ore.is_empty():
			_send_gather(w, fid, st, on.ore[on.ore.size() - 1], "salvage", known, drops)
		elif n_ore < want_ore and not on.salvage.is_empty():
			_send_gather(w, fid, st, on.salvage[on.salvage.size() - 1], "ore", known, drops)


static func _send_gather(w: SimWorld, fid: int, st: Dictionary, e: Dictionary, res: String, known: Array, drops: Array, allow_other: bool = true) -> void:
	var best = null
	var best_d := INF
	for pass_i in 2:
		for r in known:
			if String(r.res) != res:
				continue
			var near_drop := INF
			for d in drops:
				near_drop = minf(near_drop, Vector2(r.pos).distance_to(d))
			if pass_i == 0 and near_drop > SAFE_GATHER_DIST:
				continue
			var dd := near_drop * 2.0 + Vector2(r.pos).distance_to(Vector2(e.pos))
			if dd < best_d:
				best_d = dd
				best = r
		if best != null:
			break
	if best == null:
		if allow_other:
			_send_gather(w, fid, st, e, "ore" if res == "salvage" else "salvage", known, drops, false)
		return
	U.submit(w, fid, st, {"type": "gather", "unit_ids": [int(e.id)], "target_id": int(best.id)}, "gather:%d" % int(e.id))


## Keeps crews up to max_engineers (gathered salvage/ore pay for most of the army), holding back
## credits for an urgent building while one is being saved for. G3a: the builder and gatherer roles
## may differ (Machine: repair bots build, haulers gather): then BUILDERS_SPLIT of the cap build.
const BUILDERS_SPLIT := 2


static func manage_engineers(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var hq = ctx.hq
	if hq == null or not hq.built or not hq.queue.is_empty():
		return
	var cap := int(U.diff(w, fid).max_engineers)
	var b_item := U.role(w, fid, "builder")
	var g_item := U.role(w, fid, "gatherer")
	var item := b_item
	var crews: int = ctx.engineers.size()
	if b_item != g_item:
		if ctx.builders.size() < BUILDERS_SPLIT:
			item = b_item
			crews = ctx.builders.size() + 4  # one missing builder is always urgent
		elif ctx.gatherers.size() < cap - BUILDERS_SPLIT:
			item = g_item
			crews = ctx.gatherers.size()
		else:
			return
	elif crews >= cap:
		return
	if item == "":
		return
	var credits := int(w.factions[fid].credits)
	var reserve := 0
	if String(st.saving_for) != "":
		reserve = int(Content.building(String(st.saving_for)).cost.credits)
	var p := Content.production(item)
	var cost := int(p.cost.credits)
	# below 4 crews the economy itself is at risk: always rebuild
	if crews >= 4 and credits - cost < reserve:
		return
	if w.can_afford(fid, p.cost) != "":
		return
	U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(hq.id), "item": item}, "queue:hq")
