extends RefCounted
## AiNaval (owner: AI6-AN). PLAN_G5 section 8, CONTRACTS_G5 sections 4, 5, 8.
## The AI's navy, called every mil think by ai_controller (after G4b), through player commands only:
##  1. On a map with water near its base: a shipyard on the nearest valid shore site (Naval.shore_error +
##     Construction.placement_error), then ships by role (fast boats, a transport, warships, an AA ship
##     once enemy aircraft are seen) and a supply pier beside the yard.
##  2. Contest the water: combat ships attack-move to the enemy coast (the water cell of their class /
##     component nearest the target).
##  3. Bombard: ships with bombard_range fire (bombard command) at visible enemy buildings / clusters
##     on land, else at remembered buildings (own w.memory) in range.
##  4. Amphibious landings when the land route is blocked (different foot components) or long: a
##     transport loads riders at the yard, sails with the escort to a beach near the target
##     (Naval.beach_ok + water of its class beside it), unloads, and the troops attack-move the target.
## Ships leave ctx.army / ctx.carriers (Army never orders a ship over land).
## State: st.g6an.naval (String keys, Arrays, ints; positions as [x, y]).
## Runtime caches (w.cache, never saved; pure functions of the map): water flag, coast sites per side.
## Fairness: own entities, ctx.visible, w.memory[fid], static content and the public map.

const U = preload("res://sim/ai/ai_util.gd")
const Econ = preload("res://sim/ai/ai_econ.gd")
const Naval = preload("res://sim/systems/naval.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")
const Transport = preload("res://sim/systems/transport.gd")
const G3 = preload("res://sim/ai/ai_g3.gd")
const AiAir = preload("res://sim/ai/ai_air.gd")

const FROM_TICK := 9000
const MIN_ARMY := 6
const HEADROOM := 150
const SHORE_R := 40
const SITE_CHECKS := 40
const MIN_WATER := 400            # naval_small cells on the map before the AI builds a navy
const LONG_ROUTE := 70.0          # base -> target straight distance at which a landing beats the walk

## Ship plan: [role, count, from stage]. naval_aa only once enemy aircraft are seen.
const PLAN := [["naval_fast", 2, 7], ["naval_transport", 1, 7], ["naval_warship", 2, 8], ["naval_aa", 1, 8], ["naval_fast", 1, 8]]


static func S(st: Dictionary) -> Dictionary:
	if not st.has("g6an"):
		st.g6an = {}
	var g: Dictionary = st.g6an
	if not g.has("naval"):
		g.naval = {"builds": 0, "queued": 0, "patrols": 0, "bombards": 0, "landings": 0, "landed": 0,
			"jobs": {}, "cd": {}, "probe": ""}
	return g.naval


# ---------------------------------------------------------------- static content
static var _fd := {}


## Faction -> {yard, pier, items: {role: [production items]}}.
static func fdefs(fac: String) -> Dictionary:
	var c = _fd.get(fac)
	if c != null:
		return c
	var out := {"yard": "", "pier": "", "items": {}}
	for pid in Content.ids("production"):
		var p := Content.production(String(pid))
		if String(p.get("faction", "")) != fac:
			continue
		var sp: Array = p.get("spawns", [])
		if sp.is_empty():
			continue
		var role := String(Content.unit(String(sp[0])).get("role", ""))
		if not role.begins_with("naval_"):
			continue
		if not out.items.has(role):
			out.items[role] = []
		(out.items[role] as Array).append(String(pid))
		if String(out.yard) == "":
			out.yard = String(p.get("facility", ""))
	for bid in Content.ids("buildings"):
		var b := Content.building(String(bid))
		if String(b.get("faction", "")) == fac and bool(b.get("pier", false)):
			out.pier = String(bid)
	_fd[fac] = out
	return out


static var _ship := {}


static func is_ship_def(def_id: String) -> bool:
	var v = _ship.get(def_id)
	if v == null:
		v = String(Content.unit(def_id).get("role", "")).begins_with("naval_")
		_ship[def_id] = v
	return bool(v)


# ---------------------------------------------------------------- map caches (w.cache, pure)
static func water_map(w: SimWorld) -> bool:
	var v = w.cache.get("ai_nv_water")
	if v == null:
		var n := 0
		var t: PackedByteArray = w.map.terrain
		for i in t.size():
			if Terrain.is_water(int(t[i])):
				n += 1
		v = n >= MIN_WATER
		w.cache["ai_nv_water"] = v
	return bool(v)


## Shore origins for def near side fid's base, nearest first (shore rules only; placement checked later).
static func coast_sites(w: SimWorld, fid: int, def_id: String) -> Array:
	var key := "ai_nv_coast_%d_%s" % [fid, def_id]
	var v = w.cache.get(key)
	if v != null:
		return v
	var base := U.base_pos(w, fid)
	var b0 := w.cell_of(base)
	var size := int(Content.building(def_id).get("size", 3))
	var cands := []
	for dy in range(-SHORE_R, SHORE_R + 1):
		for dx in range(-SHORE_R, SHORE_R + 1):
			var o := b0 + Vector2i(dx, dy)
			if dx * dx + dy * dy > SHORE_R * SHORE_R or not w.in_bounds(o):
				continue
			var mid := o + Vector2i(size / 2, size / 2)
			if not w.in_bounds(mid):
				continue
			var wet := false
			var dry := false
			for yy in size:
				for xx in size:
					var c := o + Vector2i(xx, yy)
					if not w.in_bounds(c):
						continue
					if Terrain.is_water(w.terrain_at(c)):
						wet = true
					else:
						dry = true
			if wet and dry and Naval.shore_error(w, def_id, o) == "":
				cands.append([dx * dx + dy * dy, o.y, o.x])
	cands.sort()
	var out := []
	for c in cands:
		out.append(Vector2i(int(c[2]), int(c[1])))
	w.cache[key] = out
	return out


# ---------------------------------------------------------------- entry
static func manage(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary = {}) -> void:
	if ctx.is_empty() or not ctx.has("army"):
		return
	var fd := fdefs(U.fac(w, fid))
	if String(fd.yard) == "" or not water_map(w):
		return
	var g := S(st)
	var ships := _take_ships(w, fid, st, ctx, g, int(ctx.have.get(String(fd.yard), 0)) > 0)
	if w.tick >= FROM_TICK:
		_econ(w, fid, st, ctx, g, fd, ships)
	if not (ships.all as Array).is_empty():
		_fleet(w, fid, st, ctx, g, ships)
		_landings(w, fid, st, ctx, g, ships)
	g.probe = "naval: yard=%d ships=%d q=%d patrols=%d bombards=%d landings=%d landed=%d" % [int(ctx.have.get(String(fd.yard), 0)),
		(ships.all as Array).size(), int(g.queued), int(g.patrols), int(g.bombards), int(g.landings), int(g.landed)]


## Own ships out of ctx.army / ctx.carriers, by role (ascending id). Only with a shipyard. Think cost: the
## army (thousands at 5k units) is scanned every 16th think; in between, the known ship ids (g.ship_ids)
## are pulled out by binary search.
static func _take_ships(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, have_yard: bool) -> Dictionary:
	var out := {"all": [], "combat": [], "transport": [], "bombard": []}
	if not have_yard:
		return out
	var found := {}
	var carriers: Array = ctx.get("carriers", [])
	var keep := []
	for e in carriers:
		if is_ship_def(String(e.def)):
			found[int(e.id)] = e
		else:
			keep.append(e)
	if keep.size() != carriers.size():
		ctx.carriers = keep
	if int(st.think_count) % 16 == 0 or not g.has("ship_ids"):
		var army: Array = ctx.army
		var rest := []
		var took := false
		for e in army:
			if is_ship_def(String(e.def)):
				found[int(e.id)] = e
				took = true
			else:
				rest.append(e)
		if took:
			ctx.army = rest
	else:
		var ids := []
		for id in g.ship_ids:
			if not found.has(int(id)):
				var e = U.own(w, fid, int(id))
				if e != null:
					found[int(id)] = e
					ids.append(int(id))
		_pull(ctx, ids)
	var all_ids := found.keys()
	all_ids.sort()
	g.ship_ids = all_ids
	for id in all_ids:
		var e: Dictionary = found[id]
		var d := String(e.def)
		(out.all as Array).append(e)
		if String(Content.unit(d).get("role", "")) == "naval_transport":
			(out.transport as Array).append(e)
		else:
			(out.combat as Array).append(e)
		if not Naval.bombard_stats(d).is_empty():
			(out.bombard as Array).append(e)
	return out


static func afford(w: SimWorld, fid: int, cost: Dictionary, headroom: int) -> bool:
	return w.can_afford(fid, cost) == "" and int(w.factions[fid].credits) >= int(cost.get("credits", 0)) + headroom


static func _econ(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, fd: Dictionary, ships: Dictionary) -> void:
	if int(ctx.army_pop) < MIN_ARMY or String(st.objective) == "defend":
		return
	var yard := String(fd.yard)
	if int(ctx.have.get(yard, 0)) == 0:
		if int(ctx.unfinished_total) > 0 or not U.available(w, fid, yard):
			return
		for req in Content.building(yard).get("requires", []):
			if int(ctx.built.get(String(req), 0)) == 0:
				return
		if afford(w, fid, Content.building(yard).get("cost", {}), HEADROOM):
			_build_shore(w, fid, st, ctx, g, yard, "shipyard on the coast")
		else:
			AiAir.hold(st, Content.building(yard).get("cost", {}), HEADROOM)
		return
	if int(ctx.built.get(yard, 0)) == 0:
		return
	if _produce(w, fid, st, ctx, g, fd, ships):
		return
	var pier := String(fd.pier)
	if pier != "" and int(ctx.have.get(pier, 0)) == 0 and (ships.all as Array).size() >= 2 and int(ctx.unfinished_total) == 0:
		if U.available(w, fid, pier) and afford(w, fid, Content.building(pier).get("cost", {}), HEADROOM):
			_build_shore(w, fid, st, ctx, g, pier, "supply pier for the fleet")


## Builds def at the nearest coast site that passes placement now. True when submitted.
static func _build_shore(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, def_id: String, why: String) -> bool:
	var key := "naval:build:" + def_id
	if U.blocked(st, w, key):
		return false
	var checks := 0
	var origin := Vector2i(-1, -1)
	for o in coast_sites(w, fid, def_id):
		checks += 1
		if Construction.placement_error(w, fid, def_id, o) == "":
			origin = o
			break
		if checks >= SITE_CHECKS:
			break
	if origin.x < 0:
		if not _outpost(w, fid, st, ctx, g, coast_sites(w, fid, def_id)):
			U.set_backoff(st, w, key, 900)
		return false
	var size := int(Content.building(def_id).get("size", 3))
	var picks := Econ._pick_engineers(ctx, Vector2(origin) + Vector2(size, size) * 0.5, 2)
	if picks.is_empty():
		return false
	if U.submit(w, fid, st, {"type": "build", "unit_ids": picks, "def": def_id, "origin": origin}, key, {"origin": origin}):
		g.builds = int(g.builds) + 1
		U.log_line(st, w, "naval: build %s at %s (%s)" % [def_id, str(origin), why])
		for id in picks:
			ctx.busy[id] = true
		return true
	return false


static func _queued(ctx: Dictionary, item: String) -> int:
	var n := 0
	for b in ctx.buildings:
		for q in b.queue:
			if String(q.item) == item:
				n += 1
	return n


## The shore is beyond the build radius (20 tiles of a friendly building): a cheap defence (else power)
## goes up OUTPOST_STEP tiles from the nearest own building toward the nearest shore site. True = ordered.
const OUTPOST_STEP := 15.0
const OUTPOST_ROLES := ["defense", "power", "depot"]  # faction roles, in preference order


static func _outpost(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, sites: Array) -> bool:
	if sites.is_empty() or int(ctx.unfinished_total) > 0:
		return false
	var goal := Vector2(sites[0]) + Vector2(1.5, 1.5)
	var from := U.base_pos(w, fid)
	var bd := INF
	for b in ctx.buildings:
		var d := Vector2(b.pos).distance_to(goal)
		if d < bd:
			bd = d
			from = Vector2(b.pos)
	if bd <= 18.0:
		return false   # in range: the yard waits on something else (terrain, units in the way)
	var def_id := ""
	for r in OUTPOST_ROLES:
		var d := U.role(w, fid, r)
		if d == "":
			continue
		var ok := true
		for req in Content.building(d).get("requires", []):
			if int(ctx.built.get(String(req), 0)) == 0:
				ok = false
		if ok:
			def_id = d
			break
	if def_id == "" or not afford(w, fid, Content.building(def_id).get("cost", {}), HEADROOM):
		return false
	var anchor := from + (goal - from).normalized() * OUTPOST_STEP
	return AiAir.build_near(w, fid, st, ctx, def_id, anchor, 0, "outpost toward the coast", "naval")


static func _produce(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, fd: Dictionary, ships: Dictionary) -> bool:
	var yardb = null
	for b in ctx.buildings:
		if String(b.def) == String(fd.yard) and bool(b.built) and (b.queue as Array).is_empty():
			yardb = b
			break
	if yardb == null:
		return false
	var counts := {}
	for e in ships.all:
		var r := String(Content.unit(String(e.def)).get("role", ""))
		counts[r] = int(counts.get(r, 0)) + 1
	var air_seen := int(st.get("g4", {}).get("enemy_air_seen", 0)) > 0 or int(st.get("g6an", {}).get("air", {}).get("air_seen", 0)) > 0
	var want := {}
	for p in PLAN:
		if U.stage(w, fid) < int(p[2]) or (String(p[0]) == "naval_aa" and not air_seen):
			continue
		want[String(p[0])] = int(want.get(String(p[0]), 0)) + int(p[1])
	for role in want:
		for it in fd.items.get(role, []):
			var item := String(it)
			if not U.available(w, fid, item):
				continue
			if int(counts.get(role, 0)) + _queued(ctx, item) >= int(want[role]):
				break
			var prod := Content.production(item)
			if not afford(w, fid, prod.get("cost", {}), HEADROOM):
				AiAir.hold(st, prod.get("cost", {}), HEADROOM)
				break
			if U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(yardb.id), "item": item}, "naval:q:" + item):
				g.queued = int(g.queued) + 1
				U.log_line(st, w, "naval: queued %s at shipyard %d" % [item, int(yardb.id)])
				return true
			break
	return false


# ---------------------------------------------------------------- water helpers
static func _comp_at(w: SimWorld, mc: String, c: Vector2i) -> int:
	var lab := Movement._comp(w, mc)
	return int(lab[c.y * int(w.nav.w) + c.x])


static func _cell_of_ship(w: SimWorld, e: Dictionary) -> Vector2i:
	var mc := String(Content.unit(String(e.def)).get("move_class", "naval_small"))
	var c := w.cell_of(e.pos)
	if not Movement.is_passable(w, c, mc):
		c = Movement.nearest_free_cell(w, c, mc)
	return c


## Nearest cell (rings around `around`, r0..r1, ring order dy, dx) passable for mc in the same component
## as `from`, for which `extra` (when valid) also holds. Vector2i(-1, -1) when none.
static func _ring_find(w: SimWorld, mc: String, from: Vector2i, around: Vector2i, r0: int, r1: int, extra: Callable = Callable()) -> Vector2i:
	if not w.in_bounds(from) or not Movement.is_passable(w, from, mc):
		return Vector2i(-1, -1)
	var lab := Movement._comp(w, mc)
	var mw := int(w.nav.w)
	var want := int(lab[from.y * mw + from.x])
	for rad in range(r0, r1 + 1):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var c := around + Vector2i(dx, dy)
				if not w.in_bounds(c) or int(lab[c.y * mw + c.x]) != want:
					continue
				if extra.is_valid() and not bool(extra.call(c)):
					continue
				return c
	return Vector2i(-1, -1)


static func _land_next(w: SimWorld, c: Vector2i) -> bool:
	for d in Naval.N4:
		var q: Vector2i = c + d
		if w.in_bounds(q) and Terrain.passable(w.terrain_at(q), "foot") and not Terrain.is_water(w.terrain_at(q)):
			return true
	return false


# ---------------------------------------------------------------- fleet: bombard + contest the water
const BOMB_GAP := 10 * SimWorld.TICK_RATE
const PATROL_GAP := 20 * SimWorld.TICK_RATE


static func _fleet(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, ships: Dictionary) -> void:
	var cd: Dictionary = g.cd
	var busy := {}
	for k in g.jobs:
		for id in g.jobs[k].get("escort", []):
			busy[int(id)] = true
	for e in ships.bombard:
		var id := int(e.id)
		if int(cd.get("b%d" % id, -1)) > w.tick:
			if String(e.order.type) == "bombard":
				busy[id] = true
			continue
		var bt := bombard_target(w, fid, ctx, e)
		if bt.x < 0:
			continue
		if U.submit(w, fid, st, {"type": "bombard", "unit_ids": [id], "cell": [bt.x, bt.y]}, "naval:bomb:%d" % id):
			g.bombards = int(g.bombards) + 1
			cd["b%d" % id] = w.tick + BOMB_GAP
			busy[id] = true
			U.log_line(st, w, "naval: %s %d bombards the shore at %s" % [String(e.def), id, str(bt)])
	if int(cd.get("patrol", -1)) > w.tick:
		return
	var tgt := G3.hq_target(w, fid, st)
	var by_mc := {}
	for e in ships.combat:
		if busy.has(int(e.id)):
			continue
		var mc := String(Content.unit(String(e.def)).get("move_class", "naval_small"))
		if not by_mc.has(mc):
			by_mc[mc] = []
		(by_mc[mc] as Array).append(e)
	var sent := 0
	for mc in by_mc:
		var grp: Array = by_mc[mc]
		if grp.size() < 2 and mc == "naval_small":
			continue
		var p := sea_point(w, g, mc, _cell_of_ship(w, grp[0]), tgt)
		if p.x < 0:
			continue
		var goal := Vector2(p) + Vector2(0.5, 0.5)
		var ids := []
		for e in grp:
			var o: Dictionary = e.order
			if not (String(o.type) == "attack_move" and Vector2(o.get("target", Vector2.ZERO)).distance_to(goal) < 4.0):
				ids.append(int(e.id))
		if not ids.is_empty() and U.submit(w, fid, st, {"type": "attack_move", "unit_ids": ids, "target": goal}, "naval:patrol:" + String(mc)):
			sent += ids.size()
	if sent > 0:
		g.patrols = int(g.patrols) + 1
		U.log_line(st, w, "naval: %d ships contest the water off %s" % [sent, str(tgt.round())])
	cd["patrol"] = w.tick + PATROL_GAP


## Water cell of class mc (same component as `from`) nearest the target, cached per target.
static func sea_point(w: SimWorld, g: Dictionary, mc: String, from: Vector2i, tgt: Vector2) -> Vector2i:
	var sea: Dictionary = g.get("sea", {})
	g.sea = sea
	var key := "%s@%d,%d" % [mc, int(tgt.x), int(tgt.y)]
	if sea.has(key):
		var a: Array = sea[key]
		return Vector2i(int(a[0]), int(a[1]))
	var c := _ring_find(w, mc, from, w.cell_of(tgt), 0, 60)
	if sea.size() > 16:
		sea.clear()
	sea[key] = [c.x, c.y]
	return c


## Land cell in bombard range of ship e: a visible enemy building (nearest), else a visible enemy ground
## unit, else a remembered enemy building. Vector2i(-1, -1) when none.
static func bombard_target(w: SimWorld, fid: int, ctx: Dictionary, e: Dictionary) -> Vector2i:
	var s := Naval.bombard_stats(String(e.def))
	if s.is_empty():
		return Vector2i(-1, -1)
	var at := Vector2(e.pos)
	var rng := float(s.range) - 0.5
	var lo := float(s.min_range)
	var best := Vector2i(-1, -1)
	var bd := INF
	for pass_n in 2:
		for v in ctx.visible:
			if (pass_n == 0) != (v.kind == "building"):
				continue
			if v.kind == "unit" and U.is_air(String(v.def)):
				continue
			var d := at.distance_to(Vector2(v.pos))
			var c := w.cell_of(v.pos)
			if d <= rng and d >= lo and d < bd and not Terrain.is_water(w.terrain_at(c)):
				bd = d
				best = c
		if best.x >= 0:
			return best
	var mem: Dictionary = w.memory[fid]
	var mk := mem.keys()
	mk.sort()
	for eid in mk:
		var m: Dictionary = mem[eid]
		if String(m.get("kind", "")) != "building" or not w.is_enemy(fid, int(m.get("owner", -1))):
			continue
		var mp := Vector2(m.pos)
		var d2 := at.distance_to(mp)
		if d2 <= rng and d2 >= lo and d2 < bd and not Terrain.is_water(w.terrain_at(w.cell_of(mp))):
			bd = d2
			best = w.cell_of(mp)
	return best


# ---------------------------------------------------------------- amphibious landings
const LAND_FROM := 12000
const LAND_GAP := 120 * SimWorld.TICK_RATE
const PICK_R := 30.0
const LOAD_WAIT := 45 * SimWorld.TICK_RATE
const SAIL_MAX := 150 * SimWorld.TICK_RATE
const BEACH_R0 := 6
const BEACH_R1 := 36
const MIN_RIDERS := 3


## True when the walk to tgt is blocked (base and target in different foot components) or long.
static func sea_route_wanted(w: SimWorld, fid: int, g: Dictionary, tgt: Vector2) -> bool:
	var key := "%d,%d" % [int(tgt.x), int(tgt.y)]
	var r: Dictionary = g.get("route", {})
	if r.has(key):
		return bool(r[key])
	var base := U.base_pos(w, fid)
	var a := Movement.nearest_free_cell(w, w.cell_of(base), "foot")
	var b := Movement.nearest_free_cell(w, w.cell_of(tgt), "foot")
	var blocked := not w.in_bounds(a) or not w.in_bounds(b) or _comp_at(w, "foot", a) != _comp_at(w, "foot", b)
	var v := blocked or base.distance_to(tgt) > LONG_ROUTE
	if r.size() > 8:
		r.clear()
	r[key] = v
	g.route = r
	return v


## [beach cell, water cell beside it] near tgt reachable by carrier c (water of its class, same
## component), at least BEACH_R0 from the target. [] when none.
static func landing_beach(w: SimWorld, c: Dictionary, tgt: Vector2) -> Array:
	var mc := String(Content.unit(String(c.def)).get("move_class", "naval_small"))
	var from := _cell_of_ship(w, c)
	if not w.in_bounds(from):
		return []
	var lab := Movement._comp(w, mc)
	var mw := int(w.nav.w)
	var want := int(lab[from.y * mw + from.x])
	var t0 := w.cell_of(tgt)
	for rad in range(BEACH_R0, BEACH_R1 + 1):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var bc := t0 + Vector2i(dx, dy)
				if not w.in_bounds(bc) or Terrain.is_water(w.terrain_at(bc)) or not Naval.beach_ok(w, bc):
					continue
				for d in Naval.N4:
					var q: Vector2i = bc + d
					if w.in_bounds(q) and Terrain.is_water(w.terrain_at(q)) and int(lab[q.y * mw + q.x]) == want:
						return [bc, q]
	return []


static func _landings(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, ships: Dictionary) -> void:
	var jobs: Dictionary = g.jobs
	var live := {}
	for c in ships.transport:
		var k := str(int(c.id))
		live[k] = true
		var j = jobs.get(k)
		if j == null:
			_land_start(w, fid, st, ctx, g, ships, c)
		else:
			_land_step(w, fid, st, ctx, g, ships, c, j)
	var gone := []
	for k in jobs:
		if not live.has(k):
			gone.append(k)
	for k in gone:
		jobs.erase(k)


static func _cargo_n(c: Dictionary) -> int:
	return (c.get("cargo", []) as Array).size()


static func _land_start(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, ships: Dictionary, c: Dictionary) -> void:
	var cid := int(c.id)
	if w.tick < LAND_FROM or String(st.objective) == "defend" or int((g.cd as Dictionary).get("l%d" % cid, -1)) > w.tick:
		return
	var tgt := G3.hq_target(w, fid, st)
	if not sea_route_wanted(w, fid, g, tgt):
		return
	var bkey := "%s@%d,%d" % [String(Content.unit(String(c.def)).get("move_class", "")), int(tgt.x), int(tgt.y)]
	var bc: Dictionary = g.get("beach", {})
	if not bc.has(bkey):
		if bc.size() > 8:
			bc.clear()
		var found := landing_beach(w, c, tgt)
		bc[bkey] = [] if found.is_empty() else [found[0].x, found[0].y, found[1].x, found[1].y]
		g.beach = bc
	var ba: Array = bc[bkey]
	var beach := [] if ba.is_empty() else [Vector2i(int(ba[0]), int(ba[1])), Vector2i(int(ba[2]), int(ba[3]))]
	if beach.is_empty():
		g.cd["l%d" % cid] = w.tick + LAND_GAP
		return
	var mc := String(Content.unit(String(c.def)).get("move_class", "naval_small"))
	var here := _cell_of_ship(w, c)
	var dock := _ring_find(w, mc, here, here, 0, 8, func(q: Vector2i) -> bool: return Terrain.is_water(w.terrain_at(q)) and _land_next(w, q))
	if dock.x < 0:
		dock = here
	var riders := []
	if _cargo_n(c) == 0:
		var room := Transport.free_slots(c)
		var cands := []
		for e in ctx.army:
			if ctx.busy.has(int(e.id)) or not (String(e.order.type) in ["idle", "move", "hold"]):
				continue
			var d: float = Vector2(e.pos).distance_to(Vector2(c.pos))
			if d <= PICK_R and Transport.can_carry(c, e) == "":
				cands.append([d, int(e.id), String(e.def)])
				if cands.size() >= 32:
					break   # think cost: the first 32 in range are plenty
		cands.sort()
		for cd in cands:
			var sz := Transport.cargo_size_of(String(cd[2]))
			if sz <= room:
				room -= sz
				riders.append(int(cd[1]))
		if riders.size() < MIN_RIDERS:
			g.cd["l%d" % cid] = w.tick + 15 * SimWorld.TICK_RATE   # think cost: no rescan every think
			return
		if not U.submit(w, fid, st, {"type": "move", "unit_ids": [cid], "target": Vector2(dock) + Vector2(0.5, 0.5)}, "naval:dock:%d" % cid):
			return
		if not U.submit(w, fid, st, {"type": "load", "carrier": cid, "unit_ids": riders}, "naval:load:%d" % cid):
			return
		_pull(ctx, riders)
		for id in riders:
			ctx.busy[int(id)] = true
	else:
		riders = Transport.cargo_ids(c)
	g.jobs[str(cid)] = {"phase": "load", "t": w.tick, "riders": riders, "beach": [beach[0].x, beach[0].y],
		"water": [beach[1].x, beach[1].y], "tgt": [snappedf(tgt.x, 0.01), snappedf(tgt.y, 0.01)], "dock": [dock.x, dock.y], "escort": []}
	U.log_line(st, w, "naval: craft %d docks at %s to embark %d troops for a landing at %s" % [cid, str(dock), riders.size(), str(beach[0])])


static func _land_step(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary, ships: Dictionary, c: Dictionary, j: Dictionary) -> void:
	var cid := int(c.id)
	var age := w.tick - int(j.t)
	var water := Vector2(int(j.water[0]), int(j.water[1])) + Vector2(0.5, 0.5)
	match String(j.phase):
		"load":
			var waiting := []
			for id in j.riders:
				var u = U.own(w, fid, int(id))
				if u != null and String(u.order.get("type", "")) == "board":
					waiting.append(int(id))
			_pull(ctx, waiting)
			var n := _cargo_n(c)
			if n > 0 and (waiting.is_empty() or age > LOAD_WAIT):
				if not U.submit(w, fid, st, {"type": "move", "unit_ids": [cid], "target": water}, "naval:sail:%d" % cid):
					return
				var esc := []
				for e in ships.combat:
					if esc.size() < 3 and String(e.order.type) != "bombard":
						esc.append(int(e.id))
				if not esc.is_empty() and U.submit(w, fid, st, {"type": "attack_move", "unit_ids": esc, "target": water}, "naval:escort:%d" % cid):
					j.escort = esc
				j.phase = "sail"
				j.t = w.tick
				j.n = n
				g.sails = int(g.get("sails", 0)) + 1
				U.log_line(st, w, "naval: craft %d sails %d troops to beach %s (escort %d)" % [cid, n, str(Vector2i(int(j.beach[0]), int(j.beach[1]))), (j.escort as Array).size()])
			elif n == 0 and ((waiting.is_empty() and age > 5 * SimWorld.TICK_RATE) or age > LOAD_WAIT * 2):
				_end(w, g, cid, LAND_GAP / 2)
		"sail":
			if Vector2(c.pos).distance_to(water) <= 2.0:
				var beach := Vector2(int(j.beach[0]), int(j.beach[1])) + Vector2(0.5, 0.5)
				if U.submit(w, fid, st, {"type": "unload", "carrier": cid, "target": beach}, "naval:unload:%d" % cid):
					j.phase = "land"
					j.t = w.tick
			elif age > SAIL_MAX:
				_end(w, g, cid, LAND_GAP)
			elif not bool(c.moving) and int(w.tick + cid) % 50 == 0:
				U.submit(w, fid, st, {"type": "move", "unit_ids": [cid], "target": water}, "naval:sail2:%d" % cid)
		"land":
			if _cargo_n(c) == 0:
				var troops := []
				for id in j.riders:
					if U.own(w, fid, int(id)) != null:
						troops.append(int(id))
				var tgt := Vector2(float(j.tgt[0]), float(j.tgt[1]))
				if not troops.is_empty():
					U.submit(w, fid, st, {"type": "attack_move", "unit_ids": troops, "target": tgt}, "naval:ashore:%d" % cid)
				g.landings = int(g.landings) + 1
				g.landed = int(g.landed) + troops.size()
				U.log_line(st, w, "naval: amphibious landing %d: %d troops ashore at %s, attacking %s" % [int(g.landings), troops.size(),
					str(Vector2i(int(j.beach[0]), int(j.beach[1]))), str(tgt.round())])
				U.submit(w, fid, st, {"type": "move", "unit_ids": [cid], "target": Vector2(int(j.dock[0]), int(j.dock[1])) + Vector2(0.5, 0.5)}, "naval:back:%d" % cid)
				_end(w, g, cid, LAND_GAP)
			elif age > 20 * SimWorld.TICK_RATE:
				j.phase = "sail"   # unload refused / failed: sail closer and retry
				j.t = w.tick - SAIL_MAX / 2


static func _end(w: SimWorld, g: Dictionary, cid: int, gap: int) -> void:
	(g.jobs as Dictionary).erase(str(cid))
	g.cd["l%d" % cid] = w.tick + gap


## Removes ids from ctx.army (ascending id order: binary search, then remove_at).
static func _pull(ctx: Dictionary, ids: Array) -> void:
	var army: Array = ctx.army
	for id in ids:
		var lo := 0
		var hi := army.size() - 1
		while lo <= hi:
			var mid := (lo + hi) >> 1
			var mv := int(army[mid].id)
			if mv == int(id):
				army.remove_at(mid)
				break
			elif mv < int(id):
				lo = mid + 1
			else:
				hi = mid - 1
