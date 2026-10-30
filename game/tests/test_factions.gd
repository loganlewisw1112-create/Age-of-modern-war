extends "res://tests/test_base.gd"
## G3a faction mechanics (agent S3-sim). Contract: docs/CONTRACTS_G3a.md section 3.
## Openings per faction via roles, artillery splash/min_range, air movement and anti-air targeting,
## Machine energy recharge, scrap magnet conservation, recovery-truck repair, economy profiles,
## Machine suppression immunity, faction-checked production.

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Supply = preload("res://sim/systems/supply.gd")
const Damage = preload("res://sim/systems/damage.gd")


# ---------------------------------------------------------------- helpers
## 2 sides, no AI: fid 0 plays `f0`, fid 1 plays `f1` (enemy team).
func _world(f0: String, f1: String = "human_a", economy: String = "standard") -> SimWorld:
	var c := SimWorld.default_config()
	c.economy = economy
	c.sides = [
		{"faction": f0, "stage": 8, "credits": 5000, "ai": false, "name": "A", "team": 0},
		{"faction": f1, "stage": 8, "credits": 5000, "ai": false, "name": "B", "team": 1},
	]
	return SimWorld.new_match(c)


func _hq(w: SimWorld, fid: int) -> Dictionary:
	var hq_def := Content.role(String(w.factions[fid].faction_def), "hq")
	return w.buildings_of(fid, hq_def)[0]


func _free(w: SimWorld, p: Vector2, mc: String = "foot") -> Vector2:
	return Vector2(Movement.nearest_free_cell(w, w.cell_of(p), mc)) + Vector2(0.5, 0.5)


## Unit of `def` for fid at a free spot `off` tiles from fid 0's HQ centre.
func _spawn(w: SimWorld, def: String, fid: int, off: Vector2) -> Dictionary:
	var mc := String(Content.unit(def).get("move_class", "foot"))
	var p := Vector2(_hq(w, 0).pos) + off
	if mc != "air":
		p = _free(w, p, "vehicle" if mc == "vehicle" else "foot")
	return w.entities[w.spawn_unit(def, fid, p)]


func _events_of(w: SimWorld, type: String) -> Array:
	var out := []
	for ev in w.events:
		if ev.type == type:
			out.append(ev)
	return out


func _journal_sum(w: SimWorld, fid: int, key: String, cause: String) -> int:
	var s := 0
	for entry in w.factions[fid].journal:
		if String(entry.cause) == cause:
			s += int(entry.get(key, 0))
	return s


## First origin (spiral around fid's HQ) where def can be placed.
func _site(w: SimWorld, fid: int, def: String) -> Vector2i:
	var c: Vector2i = w.cell_of(Vector2(_hq(w, fid).pos))
	for r in range(4, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var o := c + Vector2i(dx, dy)
				if Construction.placement_error(w, fid, def, o) == "":
					return o
	return Vector2i(-1, -1)


# ---------------------------------------------------------------- openings per faction
func test_each_faction_opening_via_roles() -> void:
	for fac in ["human_a", "human_b", "machine"]:
		var w := _world(fac)
		var hq_def := Content.role(fac, "hq")
		check_eq(w.buildings_of(0, hq_def).size(), 1, fac + ": start HQ placed")
		var hq := _hq(w, 0)
		var trained := {}
		for role in ["builder", "gatherer"]:
			var item := Content.role(fac, role)
			var evs := do_cmd(w, 0, {"type": "queue_unit", "building_id": int(hq.id), "item": item})
			check_eq(rejected_reason(evs), "", "%s: queue %s" % [fac, item])
		for i in 800:
			w.step()
			for ev in _events_of(w, "ProductionCompleted"):
				trained[String(ev.item)] = true
		check(trained.has(Content.role(fac, "builder")), fac + ": builder trained")
		check(trained.has(Content.role(fac, "gatherer")), fac + ": gatherer trained")
		var builders := []
		var gatherers := []
		for u in w.units_of(0):
			var d := Content.unit(u.def)
			if bool(d.get("can_build", false)):
				builders.append(int(u.id))
			if bool(d.get("can_gather", false)):
				gatherers.append(int(u.id))
		check(not builders.is_empty() and not gatherers.is_empty(), fac + ": has builders and gatherers")
		var bdef := Content.role(fac, "barracks")
		var origin := _site(w, 0, bdef)
		check(origin.x >= 0, fac + ": found a barracks site")
		var evs := do_cmd(w, 0, {"type": "build", "unit_ids": builders, "def": bdef, "origin": origin})
		check_eq(rejected_reason(evs), "", fac + ": build " + bdef)
		var done := false
		for i in 2400:
			w.step()
			if not _events_of(w, "ConstructionCompleted").is_empty():
				done = true
				break
		check(done, fac + ": barracks-role building completed")
		# gatherers gather (can_gather), and a pure gatherer cannot build (can_build)
		var pile = null
		for id in w.entities:
			var r: Dictionary = w.entities[id]
			if r.kind == "resource" and int(r.amount) > 0:
				pile = r
				break
		var g_only := -1
		for id in gatherers:
			if not bool(Content.unit(w.entities[id].def).get("can_build", false)):
				g_only = id
		var evg := do_cmd(w, 0, {"type": "gather", "unit_ids": gatherers, "target_id": int(pile.id)})
		check_eq(rejected_reason(evg), "", fac + ": gather accepted")
		if g_only >= 0:
			var o2 := _site(w, 0, Content.role(fac, "power"))
			var evb := do_cmd(w, 0, {"type": "build", "unit_ids": [g_only], "def": Content.role(fac, "power"), "origin": o2})
			check(rejected_reason(evb) != "", fac + ": a gather-only unit cannot build")


func test_production_is_faction_checked() -> void:
	var w := _world("machine")
	var evs := do_cmd(w, 0, {"type": "queue_unit", "building_id": int(_hq(w, 0).id), "item": "engineer"})
	check(rejected_reason(evs).contains("another faction"), "human_a item at a Machine core: " + rejected_reason(evs))


# ---------------------------------------------------------------- artillery
func test_artillery_splash_hits_cluster_and_ally() -> void:
	var w := _world("human_b")
	var art := _spawn(w, "b_artillery_truck", 0, Vector2(-12, 0))
	art.order = {"type": "hold"}
	var t1 := _spawn(w, "logistics_truck", 1, Vector2(-2, 0))
	var p: Vector2 = t1.pos
	var t2: Dictionary = w.entities[w.spawn_unit("logistics_truck", 1, p + Vector2(0, 1.0))]
	var ally: Dictionary = w.entities[w.spawn_unit("logistics_truck", 0, p + Vector2(0, -1.0))]
	for u in [t1, t2, ally]:
		u.order = {"type": "hold"}
	# G7 REG8A (setup only, 13.9c ARTY8): the subject is splash on a cluster incl. an ally, not target choice. Automatic
	# indirect fire now holds danger-close to our own troops (FireHeld), so the shot is an explicit attack order on t1,
	# which still fires (DangerClose event). Assertions unchanged.
	art.order = {"type": "attack", "target_id": int(t1.id), "last_pos": t1.pos, "lost": false}
	art.target = int(t1.id)
	var ids := [int(t1.id), int(t2.id), int(ally.id)]
	var got := false
	for i in 600:
		w.step()
		for ev in _events_of(w, "ShotFired"):
			if int(ev.shooter) != int(art.id):
				continue
			check(bool(ev.get("indirect", false)), "artillery shot is indirect")
			if not bool(ev.hit) or got:
				continue
			var hit := {}
			for d in _events_of(w, "Damage"):
				if int(d.shooter) == int(art.id):
					hit[int(d.target)] = float(d.amount)
			for id in ids:
				check(hit.has(id), "splash damaged %d (hits %s)" % [id, str(hit.keys())])
			got = true
		if got:
			break
	check(got, "artillery landed a direct hit within 600 ticks")


func test_artillery_respects_min_range() -> void:
	var w := _world("human_b")
	var art := _spawn(w, "b_artillery_truck", 0, Vector2(-8, 0))
	art.order = {"type": "hold"}
	var near := _spawn(w, "logistics_truck", 1, Vector2(-5, 0))
	near.order = {"type": "hold"}
	check(Combat.dist_to(art.pos, near) < 5.0, "target is inside min_range (5)")
	for i in 200:
		w.step()
		for ev in _events_of(w, "ShotFired"):
			check(int(ev.shooter) != int(art.id), "artillery fired inside min_range")


# ---------------------------------------------------------------- air
func _find_cell(w: SimWorld, code: int) -> Vector2i:
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	for y in range(8, mh - 8):
		for x in range(8, mw - 8):
			if w.terrain_at(Vector2i(x, y)) == code:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_drone_flies_straight_over_water_and_forest() -> void:
	var w := _world("machine")
	for code in [Terrain.WATER, Terrain.FOREST]:
		var c := _find_cell(w, code)
		check(c.x >= 0, "map has terrain %d" % code)
		var goal := Vector2(c) + Vector2(0.5, 0.5)
		var id := w.spawn_unit("m_drone", 0, goal + Vector2(-6.0, 3.0))
		var d: Dictionary = w.entities[id]
		var evs := do_cmd(w, 0, {"type": "move", "unit_ids": [id], "target": goal})
		check_eq(rejected_reason(evs), "", "drone move accepted")
		check_eq((d.path as Array).size(), 1, "air path is one straight segment")
		var max_off := 0.0
		var start := goal + Vector2(-6.0, 3.0)
		for i in 200:
			w.step()
			var p: Vector2 = d.pos
			# distance from the straight line start->goal
			var dir := (goal - start).normalized()
			var rel := p - start
			max_off = maxf(max_off, absf(rel.x * dir.y - rel.y * dir.x))
			if not d.moving:
				break
		check(Vector2(d.pos).distance_to(goal) < 0.6, "drone reached %s over terrain %d (at %s)" % [str(goal), code, str(d.pos)])
		check(max_off < 0.3, "drone stayed on the straight line (max off %.3f)" % max_off)
		check_eq(w.terrain_at(w.cell_of(d.pos)), code, "drone hovers over the terrain")
		w.entities.erase(id)


func test_drone_ignores_footprints_and_ground_separation() -> void:
	var w := _world("machine")
	var hq := _hq(w, 0)
	var hp: Vector2 = hq.pos
	var id := w.spawn_unit("m_drone", 0, hp + Vector2(-5.0, 0.0))
	var d: Dictionary = w.entities[id]
	do_cmd(w, 0, {"type": "move", "unit_ids": [id], "target": hp + Vector2(5.0, 0.0)})
	var crossed := false
	var rect := Rect2i(hq.cell, Vector2i(int(hq.size), int(hq.size)))
	for i in 120:
		w.step()
		if rect.has_point(w.cell_of(d.pos)):
			crossed = true
	check(crossed, "drone flew over the HQ footprint")
	# a ground unit sharing the drone's spot is not pushed by it
	var g := _spawn(w, "m_scout_crawler", 0, Vector2(8, 4))
	d.pos = g.pos
	preload("res://sim/hot_state.gd").touch(w, int(d.id))  # CORE10K-3: direct pos/path write -> hot state
	var before: Vector2 = g.pos
	w.step()
	check(Vector2(g.pos).distance_to(before) < 0.001, "ground unit not separated from a drone")


func test_only_anti_air_weapons_target_drones() -> void:
	var w := _world("human_a", "machine")
	var rifle := _spawn(w, "rifleman", 0, Vector2(-6, 4))
	var at := _spawn(w, "at_gunner", 0, Vector2(-6, 5))
	var tank := _spawn(w, "mbt", 0, Vector2(-6, 7))
	for u in [rifle, at, tank]:
		u.order = {"type": "hold"}
	var drone: Dictionary = w.entities[w.spawn_unit("m_drone", 1, Vector2(rifle.pos) + Vector2(-3, 1))]
	drone.order = {"type": "hold"}
	w.run_ticks(4)  # fog (recomputed every 4 ticks) sees the new drone
	var ev := do_cmd(w, 0, {"type": "attack", "unit_ids": [int(at.id), int(tank.id)], "target_id": int(drone.id)})
	check_eq(rejected_reason(ev), "Selected units cannot engage aircraft.", "AT/tank attack on a drone rejected")
	var rifle_shots := 0
	for i in 200:
		w.step()
		for s in _events_of(w, "ShotFired"):
			if int(s.target) == int(drone.id):
				check(int(s.shooter) == int(rifle.id), "only the rifle may shoot the drone (shooter %d)" % int(s.shooter))
				if int(s.shooter) == int(rifle.id):
					rifle_shots += 1
		if not w.entities.has(int(drone.id)):
			break
	check(rifle_shots > 0, "the rifle engaged the drone")
	check(Combat.find_target(w, at, 20.0, w.cache.combat_grid, []) == null or not w.entities.has(int(drone.id)), "AT search ignores the drone")


# ---------------------------------------------------------------- energy
func test_machine_charge_refills_only_near_powered_hub() -> void:
	var w := _world("machine")
	var far := _spawn(w, "m_scout_crawler", 0, Vector2(18, 0))
	var near := _spawn(w, "m_scout_crawler", 0, Vector2(4, 0))
	for u in [far, near]:
		u.fuel = 50.0
		u.order = {"type": "hold"}
	var stock_fuel := int(w.factions[0].stock.fuel)
	w.run_ticks(100)
	check_eq(float(far.fuel), 50.0, "no recharge away from a recharge building")
	check(float(near.fuel) >= 90.0, "recharged near the core (fuel %.1f)" % float(near.fuel))
	# power deficit: two Crawler Works (-50 each) against the core's +60
	for k in 2:
		var o := _site(w, 0, "m_crawler_works")
		w.spawn_building("m_crawler_works", 0, o, true)
	w.step()
	check(int(w.factions[0].power_use) > int(w.factions[0].power_prod), "power deficit set up")
	near.fuel = 50.0
	w.run_ticks(100)
	check_eq(float(near.fuel), 50.0, "no recharge while power is short")
	check_eq(int(w.factions[0].stock.fuel), stock_fuel, "fuel stock untouched")
	check_eq(_journal_sum(w, 0, "fuel", "resupply"), 0, "no fuel resupply draws in the journal")


# ---------------------------------------------------------------- scrap magnet
func test_scrap_magnet_conserves() -> void:
	var w := _world("human_b")
	var o := _site(w, 0, "b_salvage_yard")
	var yid := w.spawn_building("b_salvage_yard", 0, o, true)
	var y: Dictionary = w.entities[yid]
	var yc := Vector2(y.pos)
	var near_id := w.spawn_resource("salvage", 5, _free(w, yc + Vector2(0, 3.5)))
	var far_id := w.spawn_resource("salvage", 50, _free(w, yc + Vector2(14, 14)))
	var before := {}
	for id in w.entities:
		var r: Dictionary = w.entities[id]
		if r.kind == "resource" and r.res == "salvage":
			before[id] = int(r.amount)
	w.run_ticks(200)
	var pulled := 0
	for id in before:
		var now := int(w.entities[id].amount) if w.entities.has(id) else 0
		pulled += int(before[id]) - now
	var credited := _journal_sum(w, 0, "salvage", "scrap_magnet")
	check(credited >= 5, "magnet credited salvage (%d)" % credited)
	check_eq(pulled, credited, "pile decrement equals credit")
	check(not w.entities.has(near_id), "the near pile was emptied and removed")
	check_eq(int(w.entities[far_id].amount), 50, "a pile beyond R is untouched")


# ---------------------------------------------------------------- repair
func test_recovery_truck_repairs_vehicles_only() -> void:
	var w := _world("human_b")
	var truck := _spawn(w, "b_recovery_truck", 0, Vector2(6, 4))
	var car := _spawn(w, "b_carrier", 0, Vector2(7, 5))
	car.hp = float(car.max_hp) - 200.0
	var ev := do_cmd(w, 0, {"type": "repair", "unit_ids": [int(truck.id)], "target_id": int(car.id)})
	check_eq(rejected_reason(ev), "", "recovery truck repair accepted")
	w.run_ticks(300)
	check(float(car.hp) > float(car.max_hp) - 200.0 + 50.0, "carrier repaired (hp %.1f)" % float(car.hp))
	var hq := _hq(w, 0)
	hq.hp = float(hq.max_hp) - 100.0
	var ev2 := do_cmd(w, 0, {"type": "repair", "unit_ids": [int(truck.id)], "target_id": int(hq.id)})
	check_eq(rejected_reason(ev2), "Recovery vehicles can only repair vehicles.", "truck cannot repair a building")
	# the Machine repair bot repairs everything, like an engineer
	var wm := _world("machine")
	var bot := _spawn(wm, "m_repair_bot", 0, Vector2(3, 0))
	var core := _hq(wm, 0)
	core.hp = float(core.max_hp) - 100.0
	var ev3 := do_cmd(wm, 0, {"type": "repair", "unit_ids": [int(bot.id)], "target_id": int(core.id)})
	check_eq(rejected_reason(ev3), "", "repair bot repair accepted")
	wm.run_ticks(200)
	check(float(core.hp) > float(core.max_hp) - 100.0, "core repaired by the bot")


# ---------------------------------------------------------------- economy profiles
func _harvest_after(economy: String, ticks: int) -> int:
	var w := _world("human_a", "human_a", economy)
	var e := _spawn(w, "engineer", 0, Vector2(-7, 6))
	var rid := w.spawn_resource("ore", 100, Vector2(e.pos) + Vector2(0.5, 0.0))
	do_cmd(w, 0, {"type": "gather", "unit_ids": [int(e.id)], "target_id": rid})
	w.run_ticks(ticks)
	return 100 - int(w.entities[rid].amount)


func _ammo_after_shots(economy: String, shots: int) -> int:
	var w := _world("human_a", "human_a", economy)
	var r := _spawn(w, "rifleman", 0, Vector2(-7, 6))
	var a0 := int(r.ammo)
	for i in shots:
		Supply.on_shot(w, r)
	return a0 - int(r.ammo)


func test_economy_profiles_change_gather_and_ammo() -> void:
	var std := _harvest_after("standard", 60)
	var arc := _harvest_after("arcade", 60)
	var sim := _harvest_after("simulation", 60)
	check(arc > std and std > sim, "gather arcade %d > standard %d > simulation %d" % [arc, std, sim])
	check_eq(_ammo_after_shots("standard", 4), 4, "standard: 1 round per shot")
	check_eq(_ammo_after_shots("arcade", 4), 0, "arcade: no ammo use")
	check_eq(_ammo_after_shots("simulation", 4), 6, "simulation: 1.5 rounds per shot")


# ---------------------------------------------------------------- Machine morale immunity
func test_machine_unit_never_pinned() -> void:
	var w := _world("machine")
	var walker := _spawn(w, "m_walker", 0, Vector2(-8, 4))
	walker.order = {"type": "hold"}
	check(not walker.has("morale"), "Machine units have no morale field")
	for k in 6:
		var r := _spawn(w, "rifleman", 1, Vector2(-8 - 3, 2 + k))
		r.order = {"type": "hold"}
	Damage.suppress(w, walker, 100.0)
	for i in 200:
		w.step()
		check(not bool(walker.get("pinned", false)), "walker pinned at tick %d" % w.tick)
		if not w.entities.has(int(walker.id)):
			break
	check(float(walker.get("supp", 0.0)) == 0.0, "no suppression on a Machine unit")
