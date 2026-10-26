extends RefCounted
## AI economy (owner: agent G): build order, building placement, construction crews,
## gathering balance and engineer training. Acts only through U.submit (w.submit).
## Fairness: see the convention in ai_util.gd.

const U = preload("res://sim/ai/ai_util.gd")
const Economy = preload("res://sim/systems/economy.gd")  # cap_max_for: 200 with a built Company HQ (ECON-AIRF6-2)
const Construction = preload("res://sim/systems/construction.gd")
const Stage = preload("res://sim/ai/ai_stage.gd")

const PLACE_RADIUS := 13
const PLACE_CHECKS := 50
const SAFE_GATHER_DIST := 22.0
const CREWS_PER_SITE := 2
const AMMO_FLOOR := 400   # G2 faction stock floors (same values as ai_logistics.gd)
const FUEL_FLOOR := 300
const SAL_LOW := 600        # AI7-USE-6: below this, salvage outranks the bank's ore (manage_gather)
const SAL_FIRST_ORE := 0.34 # share of crews left on ore while salvage comes first


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
	var cap_max := Economy.cap_max_for(w, fid)
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
	# G3b: the research building (and the stage plan's other buildings) right after the refinery
	var sw := Stage.want_building(w, fid, w.ai_state[fid], ctx)
	if sw != "" and (refinery == "" or int(have.get(refinery, 0)) > 0 or not fac_built):
		if sw != power and spare < _draw(sw):
			return "" if gen_pending else power
		return sw
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
		# AI5: 400 ore (was 1000): with ore held back for ammo (ai_mil) a saturated smelter shows as
		# ore piling up long before 1000
		if int(stock.get("ammo", 0)) < AMMO_FLOOR and int(stock.get("ore", 0)) >= 400:
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
## G6 (AI7-USE): `at` (>= 0) overrides the anchor (defences by threat at the front arc); default unchanged.
static func find_origin(w: SimWorld, fid: int, st: Dictionary, def_id: String, at: Vector2 = Vector2(-1, -1)) -> Vector2i:
	var size := int(Content.building(def_id).size)
	var base := U.base_pos(w, fid)
	var dir := U.front_dir(w, fid)
	var anchor := base + dir * 3.0
	var n_same := w.buildings_of(fid, def_id).size()
	if at.x >= 0.0:
		anchor = at
	elif def_id == U.role(w, fid, "defense"):
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
	# AI7-USE-6: salvage first while it is the larger shortfall (valley d6 s1: Human A 6 of 8 crews on
	# ore with 733 ore / 70 salvage, the Machine 5 of 6 with 12 ore / 344 salvage; every unit costs
	# salvage, so both armies sat under the launch threshold for the last 60k ticks and the match drew).
	# The refinery / ammo rules below still raise ore crews when the ammo or fuel stock runs short.
	var res4: Dictionary = st.get("g4", {}).get("reserve", {})
	var hold_ore := int(res4.get("ore", 0))
	var sal_first := has_mp and sal < SAL_LOW \
			and int(res4.get("salvage", 0)) + SAL_LOW - sal > hold_ore + 200 - ore
	if sal_first:
		want_ore = mini(want_ore, int(round(float(n_eng) * SAL_FIRST_ORE)))
	# G2: a working refinery eats 20 ore / 6 s; keep crews on ore while fuel/ammo stock is short
	var stock_low := int(f.stock.get("ammo", 0)) < AMMO_FLOOR or int(f.stock.get("fuel", 0)) < FUEL_FLOOR
	if int(ctx.built.get(U.role(w, fid, "refinery"), 0)) > 0 and stock_low and ore < 1500:
		want_ore = maxi(want_ore, int(round(float(n_eng) * 0.5)))
	# AI5: the stock is dry and salvage piles up: ore is the only ammo source, so most crews mine it
	# (heartland a1 s2: Human B ammo 0 for 70k ticks with 5115 salvage idle)
	if int(ctx.built.get(U.role(w, fid, "refinery"), 0)) > 0 and int(f.stock.get("ammo", 0)) < AMMO_FLOOR and sal >= 800:
		want_ore = maxi(want_ore, n_eng - 1)
	# G3b: the stage bank holds ore (8->9 research + advance) while the refinery eats 20 ore / 6 s:
	# put most crews on ore until the bank's ore is on hand (salvage piles up unused late game)
	if hold_ore > 0 and ore < hold_ore + 200 and has_mp and not sal_first:
		want_ore = maxi(want_ore, int(round(float(n_eng) * 0.75)))
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
	var safe_d := SAFE_GATHER_DIST * sqrt(U.map_scale(w))  # G3b: bigger maps, wider expansion
	for pass_i in 2:
		for r in known:
			if String(r.res) != res:
				continue
			var near_drop := INF
			for d in drops:
				near_drop = minf(near_drop, Vector2(r.pos).distance_to(d))
			if pass_i == 0 and near_drop > safe_d:
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


const CREW_CAP_ARMY := 30
const CREW_IDLE_CR := 2500
const LATE_CREW_TICK := 48000  # AI6: late-game crew boost (see crew_cap)
const LATE_CREW_CR := 1500
const LATE_CREW_POP := 15


const SAL_STARVED := 300       # AI7-USE-6: late salvage-starved crew boost (crew_cap)
const SAL_STARVED_LEFT := 5000
const SAL_STARVED_CREWS := 4
const SAL_STARVED_CR := 300


## AI7-USE-6: late game, salvage starved with salvage still on the map and supply to spare, a few
## more crews even when credits are short (valley d6 s1: Human A 8 crews, 70 salvage, 56k salvage
## left, army 29 under a 56 threshold for 60k ticks; heartland / custom d4-d5 ended the same way:
## no unit can be built without salvage, so the credits wait on it anyway).
static func crew_cap(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> int:
	var cap := _crew_cap0(w, fid, st, ctx)
	var f: Dictionary = w.factions[fid]
	if w.tick >= LATE_CREW_TICK and int(f.stock.salvage) < SAL_STARVED and int(f.credits) >= SAL_STARVED_CR \
			and int(st.get("gather_plan", {}).get("salvage_left", 0)) >= SAL_STARVED_LEFT \
			and int(f.pop) <= int(f.pop_cap) - 4:
		cap = maxi(cap, int(U.diff(w, fid).max_engineers) + SAL_STARVED_CREWS)
	return cap


## AI4-3: the difficulty's crew cap, raised while a big army is starved of materials and credits
## pile up (heartland soak1: 100-pop Human B army 56/88 dry of ammo, 9000 credits idle, 8 crews).
static func _crew_cap0(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> int:
	var base := int(U.diff(w, fid).max_engineers)
	# only once the army is out and big (the opening keeps its credits for the first waves)
	var f: Dictionary = w.factions[fid]
	# AI5: credits piling up (CREW_IDLE_CR) while materials starve also counts once the army is out
	# (heartland v3 s1: Human B 3700 cr idle, salvage 51, ore 16, army 22 < 30 -> 8 crews only)
	var idle_cr := int(f.credits) >= CREW_IDLE_CR
	# AI6: only with supply headroom (valley v4: extra crews ate the pop the late waves needed)
	var late := w.tick >= LATE_CREW_TICK and int(f.credits) >= LATE_CREW_CR and int(f.pop) <= int(f.pop_cap) - LATE_CREW_POP
	idle_cr = idle_cr or late
	if int(st.get("launches", 0)) < 1 or (int(ctx.get("army_n", 0)) < CREW_CAP_ARMY and not idle_cr):
		return base
	var starved := int(f.stock.salvage) < 300 or int(f.stock.ore) < 150 or int(f.stock.get("ammo", 0)) < AMMO_FLOOR
	if not starved or int(f.credits) < 1000:
		return base
	# AI6 (valley v1, both seeds): late game both humans sat on 2000-6000 idle credits with salvage
	# 0-200 and ore 0-400 at 8-12 crews (deposits 13k-45k left), so neither could rebuild a wave.
	# From LATE_CREW_TICK idle credits buy up to triple the crews (still capped by credits >= 1000).
	if late:
		return mini(base * 3, base * 2 + int(ctx.get("army_n", 0)) / 6)
	if int(ctx.get("army_n", 0)) < CREW_CAP_ARMY:
		return mini(base * 2, base + 4)
	return mini(base * 3, base + maxi(2, int(ctx.get("army_n", 0)) / 8))


static func manage_engineers(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var hq = ctx.hq
	if hq == null or not hq.built or not hq.queue.is_empty():
		return
	var cap := crew_cap(w, fid, st, ctx)
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
