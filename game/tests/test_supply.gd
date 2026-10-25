extends "res://tests/test_base.gd"
## G2 supply (agent B2): ammo/fuel consumption + resupply, refinery, repair command, save round trip.

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")


# ---------------------------------------------------------------- helpers
func _hq(w: SimWorld, fid: int = 0) -> Dictionary:
	return w.buildings_of(fid, "hq")[0]


func _free(w: SimWorld, p: Vector2, mc: String = "foot") -> Vector2:
	return Vector2(Movement.nearest_free_cell(w, w.cell_of(p), mc)) + Vector2(0.5, 0.5)


## A unit of `def` for fid placed at a free spot `off` tiles from the player HQ centre.
func _spawn(w: SimWorld, def: String, fid: int, off: Vector2) -> Dictionary:
	var mc := String(Content.unit(def).get("move_class", "foot"))
	var id := w.spawn_unit(def, fid, _free(w, Vector2(_hq(w).pos) + off, mc))
	return w.entities[id]


func _engineer(w: SimWorld) -> Dictionary:
	for e in w.units_of(0):
		if e.def == "engineer":
			return e
	return {}


func _empty_stock(w: SimWorld, fid: int, key: String) -> void:
	var n := int(w.factions[fid].stock.get(key, 0))
	if n > 0:
		check(w.spend(fid, {key: n}, "test_drain"), "drain " + key)


func _journal_sum(w: SimWorld, fid: int, key: String, cause: String) -> int:
	var s := 0
	for entry in w.factions[fid].journal:
		if String(entry.cause) == cause:
			s += int(entry.get(key, 0))
	return s


func _total(w: SimWorld, fid: int, key: String) -> int:
	var s := 0
	for e in w.units_of(fid):
		s += int(e.get(key, 0))
	return s


func _run(w: SimWorld, n: int, log: Dictionary = {}) -> void:
	for i in n:
		w.step()
		for ev in w.events:
			if not log.has(ev.type):
				log[ev.type] = []
			log[ev.type].append(ev)


# ---------------------------------------------------------------- ammo
func test_shots_consume_ammo_and_empty_cannot_fire() -> void:
	var w := make_world()
	_empty_stock(w, 0, "ammo")   # no resupply interference near the HQ
	var shooter := _spawn(w, "rifleman", 0, Vector2(0, 5))
	var target := _spawn(w, "rifleman", 1, Vector2(0, 8))
	target.max_hp = 100000.0
	target.hp = 100000.0
	target.ammo = 0
	shooter.ammo = 5
	var log := {}
	_run(w, 300, log)
	var shots := 0
	for ev in log.get("ShotFired", []):
		if int(ev.shooter) == int(shooter.id):
			shots += 1
	check_eq(shots, 5, "exactly 5 rounds fired from 5 ammo")
	check_eq(int(shooter.ammo), 0, "ammo is 0 and never negative")
	log.clear()
	_run(w, 200, log)
	shots = 0
	for ev in log.get("ShotFired", []):
		if int(ev.shooter) == int(shooter.id):
			shots += 1
	check_eq(shots, 0, "no shots from the unit at 0 ammo")


func test_resupply_refills_and_journal_conserves() -> void:
	var w := make_world()
	var u := _spawn(w, "rifleman", 0, Vector2(0, 4))
	u.ammo = 10
	var stock0 := int(w.factions[0].stock.ammo)
	var held0 := _total(w, 0, "ammo")
	_run(w, 21)
	check_eq(int(u.ammo), 16, "first pass refills refill_per_second (6) rounds")
	_run(w, 200)
	check_eq(int(u.ammo), 60, "refilled to ammo_max")
	var spent := _journal_sum(w, 0, "ammo", "resupply")
	check_eq(spent, -50, "journal records exactly the 50 rounds drawn")
	check_eq(int(w.factions[0].stock.ammo), stock0 - 50, "stock fell by exactly what units gained")
	check_eq(_total(w, 0, "ammo") - held0, 50, "units gained exactly the journal amount")


func test_resupply_short_stock_gives_remainder_and_warns() -> void:
	var w := make_world()
	var u := _spawn(w, "rifleman", 0, Vector2(0, 4))
	u.ammo = 10
	_empty_stock(w, 0, "ammo")
	w.credit(0, {"ammo": 4}, "test")
	var log := {}
	_run(w, 41, log)
	check_eq(int(u.ammo), 14, "took exactly the 4 left")
	check_eq(int(w.factions[0].stock.ammo), 0, "stock empty, not negative")
	check_eq(String(w.factions[0].status_supply), "NO_AMMO_STOCK", "status_supply flags the shortage")
	check_eq(log.get("SupplyShortage", []).size(), 1, "one SupplyShortage inside the cooldown")


# ---------------------------------------------------------------- fuel
func test_vehicle_burns_fuel_stops_at_zero_and_resupply_restarts_it() -> void:
	var w := make_world()
	_empty_stock(w, 0, "fuel")
	var m := _spawn(w, "mbt", 0, Vector2(0, 5))
	m.fuel = 6.0
	var start: Vector2 = m.pos
	var mid := Vector2(w.map.w, w.map.h) * 0.5
	do_cmd(w, 0, {"type": "move", "unit_ids": [int(m.id)], "target": mid})
	_run(w, 120)
	check(float(m.fuel) <= 0.0, "fuel burned down to 0 (is %s)" % str(m.fuel))
	var dist := (Vector2(m.pos) - start).length()
	check(dist > 3.0 and dist < 4.6, "drove about fuel/fuel_per_tile = 4 tiles (drove %.2f)" % dist)
	var stopped_at: Vector2 = m.pos
	_run(w, 60)
	check((Vector2(m.pos) - stopped_at).length() < 0.001, "vehicle with no fuel does not move")
	w.credit(0, {"fuel": 300}, "test")
	_run(w, 100)
	check(float(m.fuel) > 0.0, "resupply refuels the tank")
	check((Vector2(m.pos) - stopped_at).length() > 0.5, "refuelled vehicle moves again")


# ---------------------------------------------------------------- refinery
func _refinery_site(w: SimWorld) -> Vector2i:
	# refinery needs a motor_pool prerequisite for placement_error; the test spawns it directly
	var c := Vector2i(_hq(w).pos)
	for r in range(4, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var o := c + Vector2i(dx, dy)
				var ok := true
				for yy in 3:
					for xx in 3:
						var cell := o + Vector2i(xx, yy)
						if not w.in_bounds(cell) or not Terrain.buildable(w.terrain_at(cell)) or Construction.building_at_cell(w, cell):
							ok = false
				if ok:
					return o
	return Vector2i(-1, -1)


func test_refinery_converts_ore_then_reports_no_ore_and_low_power() -> void:
	var w := make_world()
	var o := _refinery_site(w)
	if not check(o != Vector2i(-1, -1), "no refinery site"):
		return
	var r: Dictionary = w.entities[w.spawn_building("refinery", 0, o, true)]
	var f: Dictionary = w.factions[0]
	# G3b PERF4-3 (orch directive): the refinery now produces only the outputs below
	# rules.refinery.stock_cap; the start ammo stock sits at the cap, so drop both below it first
	var cap := int((Content.rules().refinery as Dictionary).get("stock_cap", 0))
	for k in ["fuel", "ammo"]:
		if cap > 0 and int(f.stock[k]) >= cap:
			w.spend(0, {k: int(f.stock[k]) - (cap - 100)}, "test")
	var ore0 := int(f.stock.ore)
	var fuel0 := int(f.stock.fuel)
	var ammo0 := int(f.stock.ammo)
	_run(w, 125)
	var cfg: Dictionary = Content.rules().refinery
	check_eq(int(f.stock.ore), ore0 - int(cfg.ore_in), "one cycle spent ore_in ore")
	check_eq(int(f.stock.fuel), fuel0 + int(cfg.fuel_out), "and credited fuel_out fuel")
	check_eq(int(f.stock.ammo), ammo0 + int(cfg.ammo_out), "and ammo_out ammo")
	check_eq(String(r.status), "", "working refinery has empty status")
	check_eq(_journal_sum(w, 0, "ore", "refinery"), -int(cfg.ore_in), "journal: ore spend, cause refinery")
	check_eq(_journal_sum(w, 0, "fuel", "refinery"), int(cfg.fuel_out), "journal: fuel credit, cause refinery")
	_empty_stock(w, 0, "ore")
	var fuel1 := int(f.stock.fuel)
	_run(w, 200)
	check_eq(String(r.status), "NO_ORE", "no ore -> NO_ORE")
	check_eq(int(f.stock.fuel), fuel1, "nothing produced without ore")
	w.credit(0, {"ore": 100}, "test")
	var o2 := _refinery_site(w)
	if check(o2 != Vector2i(-1, -1), "no second refinery site"):
		w.spawn_building("refinery", 0, o2, true)
		_run(w, 5)
		check_eq(String(r.status), "LOW_POWER", "two refineries overdraw the power -> LOW_POWER")


# ---------------------------------------------------------------- repair
func _damaged_mbt(w: SimWorld) -> Dictionary:
	var m := _spawn(w, "mbt", 0, Vector2(0, 5))
	m.hp = 700.0
	m.comp.mobility = 0.0
	return m


func test_repair_restores_mobility_then_hp_and_charges_salvage() -> void:
	var w := make_world()
	var m := _damaged_mbt(w)
	var eng := _engineer(w)
	var salv0 := int(w.factions[0].stock.salvage)
	do_cmd(w, 0, {"type": "repair", "unit_ids": [int(eng.id)], "target_id": int(m.id)})
	check_eq(String(eng.order.type), "repair", "engineer has a repair order")
	var mob_first := false
	for i in 900:
		w.step()
		if float(m.comp.mobility) >= 50.0 and float(m.hp) < 701.0:
			mob_first = true
		if String(eng.order.type) != "repair":
			break
	check(mob_first, "mobility restored to 50 before hp work starts")
	check_eq(float(m.hp), 1000.0, "hp fully restored")
	check_eq(float(m.comp.mobility), 100.0, "mobility fully restored")
	check_eq(String(eng.order.type), "idle", "engineer idle when the target is whole")
	# mobility 0->50 (10) + 300 hp (60) + mobility 50->100 (10) = 80 salvage
	check_eq(_journal_sum(w, 0, "salvage", "repair"), -80, "charged salvage_per_100hp per chunk")
	check_eq(int(w.factions[0].stock.salvage), salv0 - 80, "stock matches the journal")


func test_repair_validation_reasons() -> void:
	var w := make_world()
	var m := _damaged_mbt(w)
	var rifle := _spawn(w, "rifleman", 0, Vector2(2, 5))
	var eng := _engineer(w)
	var foe := _spawn(w, "mbt", 1, Vector2(0, 7))
	foe.hp = 500.0
	check_eq(rejected_reason(do_cmd_loose(w, {"type": "repair", "unit_ids": [int(rifle.id)], "target_id": int(m.id)})), "Only engineers can repair.", "non-engineer")
	check_eq(rejected_reason(do_cmd_loose(w, {"type": "repair", "unit_ids": [int(eng.id)], "target_id": int(foe.id)})), "Not your unit.", "enemy target")
	check_eq(rejected_reason(do_cmd_loose(w, {"type": "repair", "unit_ids": [int(eng.id)], "target_id": int(rifle.id)})), "Nothing to repair.", "undamaged unit")
	check_eq(rejected_reason(do_cmd_loose(w, {"type": "repair", "unit_ids": [int(eng.id)], "target_id": 999999})), "Nothing to repair.", "no such target")


## Like do_cmd but does not require the submit to be accepted (rejection happens at apply time).
func do_cmd_loose(w: SimWorld, cmd: Dictionary) -> Array:
	cmd.issuer = 0
	w.submit(cmd)
	w.step()
	return w.events


func test_repair_blocked_without_salvage() -> void:
	var w := make_world()
	var m := _damaged_mbt(w)
	var eng := _engineer(w)
	_empty_stock(w, 0, "salvage")
	var log := {}
	do_cmd(w, 0, {"type": "repair", "unit_ids": [int(eng.id)], "target_id": int(m.id)})
	_run(w, 400, log)
	var blocked: Array = log.get("RepairBlocked", [])
	check_eq(blocked.size(), 1, "RepairBlocked emitted once")
	if blocked.size() > 0:
		check(String(blocked[0].reason) != "", "blocked event carries a reason")
		check_eq(int(blocked[0].target_id), int(m.id), "names the target")
	check_eq(String(eng.order.type), "idle", "engineer goes idle")
	check_eq(float(m.hp), 700.0, "nothing repaired for free")


func test_bridge_repair_charges_repair_salvage_and_calls_hook() -> void:
	var w := make_world()
	var br: Dictionary = {}
	for id in w.entities:
		if String(w.entities[id].def) == "bridge_span":
			br = w.entities[id]
	if not check(not br.is_empty(), "bridge exists"):
		return
	br.state = "ruined"
	var engs := []
	for e in w.units_of(0):
		if e.def == "engineer" and engs.size() < 2:
			e.pos = Vector2(br.pos)
			preload("res://sim/hot_state.gd").touch(w, int(e.id))  # CORE10K-3: direct pos/path write -> hot state
			engs.append(int(e.id))
	_run(w, 8)   # fog catches up so the bridge is visible to the player
	var log := {}
	do_cmd(w, 0, {"type": "repair", "unit_ids": engs, "target_id": int(br.id)})
	for i in 700:
		_run(w, 1, log)
		if String(w.entities[engs[0]].order.type) != "repair":
			break
	var want := int(Content.building("bridge_span").repair_salvage)
	check_eq(_journal_sum(w, 0, "salvage", "repair"), -want, "bridge cost repair_salvage in total")
	check_eq(String(w.entities[engs[0]].order.type), "idle", "engineers idle after the repair completes")
	check_eq(float(br.get("repair_progress", 0.0)), 0.0, "progress reset after on_repaired")
	if String(br.state) != "ruined":
		check(log.get("BridgeRepaired", []).size() >= 1, "BridgeRepaired emitted by Bridges.on_repaired")


# ---------------------------------------------------------------- save round trip
func test_save_round_trip_mid_resupply_hash_equal() -> void:
	var w := make_world()
	var u := _spawn(w, "rifleman", 0, Vector2(0, 4))
	u.ammo = 3
	var m := _spawn(w, "mbt", 0, Vector2(0, 5))
	m.fuel = 150.0
	do_cmd(w, 0, {"type": "move", "unit_ids": [int(m.id)], "target": Vector2(w.map.w, w.map.h) * 0.5})
	_run(w, 25)   # mid-resupply: the refill pass has run once, fuel is burning
	var l: SimWorld = SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(l.state_hash(), w.state_hash(), "hash equal right after the round trip")
	_run(w, 200)
	for i in 200:
		l.step()
	check_eq(l.state_hash(), w.state_hash(), "hash equal after 200 more ticks")
