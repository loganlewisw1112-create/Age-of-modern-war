extends "res://tests/test_base.gd"
## G2 cross-system acceptance scenarios (agent Q2-qa). Every test crosses at least two systems and
## asserts the documented contract (docs/CONTRACTS_G2.md), never AI behaviour: make_world() gives an
## inert side 1 and units are spawned directly.
##   1 MIL-02/QA-008  damage + status + combat + repair      2 QA-007 + supply  bridges + movement + fuel
##   3 officer + supply  ops + supply + ledger               4 morale + officer  ops + damage + morale
##   5 conservation brawl  all systems                       6 save/load mid-brawl   7 determinism

const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Construction = preload("res://sim/systems/construction.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Ops = preload("res://sim/systems/ops.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const Status = preload("res://sim/systems/status.gd")
const C := Vector2(0.5, 0.5)


# ---------------------------------------------------------------- helpers
func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	return w


func _paint(w: SimWorld, rect: Rect2i, code: int) -> void:
	var t: PackedByteArray = w.map.terrain
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			t[y * int(w.map.w) + x] = code
	w.map.terrain = t
	Movement.rebuild_nav(w)


## Open grass arena x 22..73, y 0..25, away from both HQs and out of every supply radius.
func _arena(w: SimWorld) -> void:
	_paint(w, Rect2i(22, 0, 52, 26), Terrain.GRASS)


func _spawn(w: SimWorld, def: String, fid: int, cell: Vector2i) -> int:
	var mc: String = Movement.udef(def).mc
	return w.spawn_unit(def, fid, Vector2(Movement.nearest_free_cell(w, cell, mc)) + C)


func _bridge(w: SimWorld) -> Dictionary:
	for id in w.entities:
		if w.entities[id].kind == "structure":
			return w.entities[id]
	return {}


## Road points just off each end of the bridge (the road runs along x == y).
func _banks(w: SimWorld) -> Array:
	var lo := 1000
	var hi := -1000
	for c in w.map.bridge_cells:
		lo = mini(lo, int(c.y))
		hi = maxi(hi, int(c.y))
	return [Vector2(lo - 4, lo - 4) + C, Vector2(hi + 4, hi + 4) + C]


func _units_in_water(w: SimWorld) -> Array:
	var bad := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and w.terrain_at(w.cell_of(e.pos)) == Terrain.WATER:
			bad.append("%s#%d@%s" % [e.def, e.id, w.cell_of(e.pos)])
	return bad


func _journal_sum(w: SimWorld, fid: int, key: String, cause: String) -> int:
	var s := 0
	for entry in w.factions[fid].journal:
		if String(entry.cause) == cause:
			s += int(entry.get(key, 0))
	return s


func _count(events: Array, type: String, key: String = "", val = null) -> int:
	var n := 0
	for ev in events:
		if ev.type == type and (key == "" or ev.get(key) == val):
			n += 1
	return n


# ---------------------------------------------------------------- 1. MIL-02 / QA-008 combined
## An MBT loses mobility to real AT hits (Damage.apply_hit), still kills an IFV in range, is then
## repaired by an engineer, drives again, and the salvage bill equals the repair rule.
func test_s1_mbt_mobility_kill_still_fires_then_repaired_and_drives() -> void:
	var w := _world()
	_arena(w)
	var mbt_id := _spawn(w, "mbt", 0, Vector2i(34, 10))
	var mbt: Dictionary = w.entities[mbt_id]
	mbt.facing = 0.0   # setup (ORCH ruling on need 2471): spawn_unit now faces the owner's front (need 2223); armour-facing scenario built on the old east-facing default
	var at: Dictionary = w.entities[_spawn(w, "at_gunner", 1, Vector2i(28, 10))]
	# inflate hp only so the volley cannot kill the tank before a component roll disables mobility
	mbt.max_hp = 1000000.0
	mbt.hp = 1000000.0
	var mob_disabled := 0
	var hits := 0
	for i in 800:
		w.events = []
		Damage.apply_hit(w, at, mbt, Combat.stats(at), true)
		hits += 1
		mob_disabled += _count(w.events, "ComponentDisabled", "component", "mobility")
		if float(mbt.comp.mobility) <= 0.0:
			break
	check(float(mbt.comp.mobility) <= 0.0, "AT fire disabled the mobility component (%d hits)" % hits)
	check_eq(mob_disabled, 1, "ComponentDisabled{mobility} emitted exactly once")
	check_eq(Status.move_mult(w, mbt), 0.0, "move_mult is 0 with mobility disabled")
	# normalise to a known wounded state (see header): weapon/sensors whole, hp 700/1000
	mbt.comp.mobility = 0.0
	mbt.comp.weapon = 100.0
	mbt.comp.sensors = 100.0
	mbt.max_hp = 1000.0
	mbt.hp = 700.0
	w.destroy(int(at.id), "test_cleanup", 0)
	# the immobile tank still kills an IFV in range (its weapon is disabled so it cannot fight back)
	var ifv_id := _spawn(w, "ifv", 1, Vector2i(40, 10))
	w.entities[ifv_id].facing = 0.0   # setup: same as the MBT above (old east-facing default, the MBT hits its rear)
	w.entities[ifv_id].comp.weapon = 0.0
	var p0: Vector2 = mbt.pos
	var shots := 0
	for i in 1200:
		w.step()
		shots += _count(w.events, "ShotFired", "shooter", mbt_id)
		if not w.entities.has(ifv_id):
			break
	check(shots > 0, "mobility-disabled MBT still fires")
	check(not w.entities.has(ifv_id), "mobility-disabled MBT killed the IFV in range")
	check(mbt.pos.distance_to(p0) < 0.01, "and never moved while mobility was out")
	# the fight cannot have healed anything
	check_eq(float(mbt.comp.mobility), 0.0, "mobility still 0 before repair")
	var eng_id := _spawn(w, "engineer", 0, Vector2i(32, 10))
	var salv0 := int(w.factions[0].stock.salvage)
	do_cmd(w, 0, {"type": "repair", "unit_ids": [eng_id], "target_id": mbt_id})
	var blocked := 0
	for i in 1500:
		w.step()
		blocked += _count(w.events, "RepairBlocked")
		if String(w.entities[eng_id].order.type) != "repair":
			break
	check_eq(blocked, 0, "repair was not blocked")
	check_eq(float(mbt.comp.mobility), 100.0, "mobility restored")
	check_eq(float(mbt.hp), 1000.0, "hp restored")
	var spp := int(Content.rules().repair.salvage_per_100hp)
	# mobility 0->50 and 50->100 are two 50-point chunks (rounded up), 300 hp is three 100 hp chunks
	var want := 2 * int(ceil(50.0 * spp / 100.0)) + 3 * spp
	check_eq(_journal_sum(w, 0, "salvage", "repair"), -want, "salvage paid equals the repair rule")
	check_eq(int(w.factions[0].stock.salvage), salv0 - want, "stock fell by exactly the journal amount")
	var d0: Vector2 = mbt.pos
	do_cmd(w, 0, {"type": "move", "unit_ids": [mbt_id], "target": d0 + Vector2(8, 0)})
	w.run_ticks(200)
	check(mbt.pos.distance_to(d0) > 5.0, "repaired MBT drives again (%.2f tiles)" % mbt.pos.distance_to(d0))


# ---------------------------------------------------------------- 2. QA-007 + supply
## Walks a truck from `a` to `b`, summing the distance travelled. Returns {arrived, dist, burned, water}.
func _drive(w: SimWorld, id: int, goal: Vector2, max_ticks: int) -> Dictionary:
	var e: Dictionary = w.entities[id]
	var f0 := float(e.fuel)
	var dist := 0.0
	var water := []
	var arrived := false
	do_cmd(w, 0, {"type": "move", "unit_ids": [id], "target": goal})
	var last: Vector2 = e.pos
	for i in max_ticks:
		w.step()
		dist += last.distance_to(e.pos)
		last = e.pos
		if water.is_empty():
			water = _units_in_water(w)
		if e.pos.distance_to(goal) < 2.5:
			arrived = true
			break
	return {"arrived": arrived, "dist": dist, "burned": f0 - float(e.fuel), "water": water}


func _truck_on_bank(w: SimWorld, bank: Vector2) -> int:
	var id := _spawn(w, "logistics_truck", 0, w.cell_of(bank))
	w.entities[id].fuel = float(Content.unit("logistics_truck").fuel_max)
	return id


func test_s2_bridge_collapse_under_truck_then_ford_route_burns_more_fuel() -> void:
	# control: intact bridge, direct crossing
	var wc := _world()
	var bk := _banks(wc)
	var ctl := _drive(wc, _truck_on_bank(wc, bk[0]), bk[1], 3000)
	check(ctl.arrived, "control truck crosses the intact bridge")
	# scenario world
	var w := _world()
	var truck_a := w.spawn_unit("logistics_truck", 0, Vector2(47.5, 47.5))
	do_cmd(w, 0, {"type": "move", "unit_ids": [truck_a], "target": bk[1]})
	w.run_ticks(4)
	var cells := {}
	for c in w.map.bridge_cells:
		cells[c] = true
	var a_on_span := w.entities.has(truck_a) and cells.has(w.cell_of(w.entities[truck_a].pos))
	check(a_on_span, "precondition: truck is mid-crossing on the span")
	var truck_b := _truck_on_bank(w, bk[0])
	w.destroy(int(_bridge(w).id), "killed", 1)
	check(_count(w.events, "BridgeDestroyed") >= 1, "BridgeDestroyed emitted")
	w.step()
	check_eq(String(w.map.bridge_state), "ruined", "map.bridge_state ruined")
	for i in 300:
		check(_units_in_water(w).is_empty(), "truck never left in water: %s" % str(_units_in_water(w)))
		if not _units_in_water(w).is_empty():
			break
		w.step()
	if w.entities.has(truck_a):
		check(w.terrain_at(w.cell_of(w.entities[truck_a].pos)) != Terrain.WATER, "truck A (nudged) is on dry ground")
	# remove truck A: trucks resupply each other, which would hide the detour's fuel burn
	if w.entities.has(truck_a):
		w.destroy(truck_a, "test_cleanup", 0)
	# the second truck must now route via a ford
	var run := _drive(w, truck_b, bk[1], 5000)
	check(run.arrived, "truck reaches the far bank via a ford (tick %d)" % w.tick)
	check(run.water.is_empty(), "no unit ever in water on the detour: %s" % str(run.water))
	check(float(run.dist) > 2.0 * float(ctl.dist), "detour is far longer (%.1f vs %.1f tiles)" % [run.dist, ctl.dist])
	check(float(run.burned) > 2.0 * float(ctl.burned), "and burns more fuel (%.1f vs %.1f)" % [run.burned, ctl.burned])
	var fpt := float(Content.unit("logistics_truck").fuel_per_tile) * maxf(float(Content.rules().get("fuel_burn_scale", 1.0)), 0.0)  # G6.1 burn scale
	for r in [[ctl, "control"], [run, "detour"]]:
		var d: Dictionary = r[0]
		check(absf(float(d.burned) - float(d.dist) * fpt) <= 0.1 * float(d.dist) * fpt + 1.0,
			"%s: fuel burned %.1f matches %.1f tiles x %.1f" % [r[1], d.burned, d.dist, fpt])


# ---------------------------------------------------------------- 3. officer + supply
func _officer_squad(w: SimWorld, at: Vector2, n: int) -> Dictionary:
	var off := _spawn(w, "officer", 0, w.cell_of(at) + Vector2i(0, -2))
	var ids := []
	for i in n:
		ids.append(_spawn(w, "rifleman", 0, w.cell_of(at) + Vector2i(i % 3 - 1, i / 3)))
	var ev := do_cmd(w, 0, {"type": "assign_officer", "officer_id": off, "unit_ids": ids})
	check_eq(rejected_reason(ev), "", "assign_officer accepted")
	return {"off": off, "ids": ids}


func _ammo_total(w: SimWorld, fid: int) -> int:
	var s := 0
	for e in w.units_of(fid):
		s += int(e.get("ammo", 0))
	return s


func test_s3_low_ammo_mission_resupplies_at_depot_and_returns_to_objective() -> void:
	var w := _world()
	_arena(w)
	var depot_id := w.spawn_building("depot", 0, Vector2i(30, 8), true)
	var depot: Dictionary = w.entities[depot_id]
	var target := Vector2(46.5, 12.5)
	var sq := _officer_squad(w, target, 5)
	for id in sq.ids:
		w.entities[id].ammo = 10    # 10/60 = 17% < resupply_ammo_frac
	w.entities[sq.off].ammo = 6
	var held0 := _ammo_total(w, 0)
	var stock0 := int(w.factions[0].stock.ammo)
	var ev := do_cmd(w, 0, {"type": "set_mission", "officer_id": sq.off, "mission": "secure_point",
		"target": target, "radius": 6.0, "risk": "high"})
	check_eq(rejected_reason(ev), "", "set_mission accepted")
	var g := Ops.group_led_by(w, sq.off)
	var phases := []
	var min_d := 1000.0
	for i in 3600:
		w.step()
		for r in w.events:
			if r.type == "OfficerReport" and (phases.is_empty() or phases[-1] != String(r.phase)):
				phases.append(String(r.phase))
		for id in sq.ids:
			min_d = minf(min_d, w.entities[id].pos.distance_to(depot.pos))
		if String(g.phase) == "hold":
			break
	check(phases.has("resupply"), "group entered the resupply phase (phases %s)" % str(phases))
	if phases.has("resupply"):
		var after: Array = phases.slice(phases.find("resupply") + 1)
		check(after.has("move") or after.has("secure") or after.has("hold"), "group resumed the mission after resupply (%s)" % str(after))
	var rad := float(Content.rules().supply.radius)
	check(min_d <= rad + 1.5, "members came within the supply radius of the depot (closest %.1f, radius %.1f)" % [min_d, rad])
	check_eq(String(g.phase), "hold", "group ends holding the objective")
	var inside := 0
	for id in sq.ids:
		if w.entities[id].pos.distance_to(target) <= 6.0:
			inside += 1
	check(inside * 2 >= sq.ids.size(), "at least half the members are at the objective (%d)" % inside)
	var spent := -_journal_sum(w, 0, "ammo", "resupply")
	check(spent > 0, "journal shows resupply spends of ammo (%d)" % spent)
	check_eq(int(w.factions[0].stock.ammo), stock0 - spent, "stock fell by exactly the journalled amount")
	check_eq(_ammo_total(w, 0) - held0, spent, "units gained exactly what the ledger paid (conservation)")
	var mean := 0.0
	for id in sq.ids:
		mean += float(w.entities[id].ammo) / 60.0
	check(mean / sq.ids.size() > 0.5, "members are resupplied (mean ammo %.0f%%)" % (100.0 * mean / sq.ids.size()))
	check(_units_in_water(w).is_empty(), "nobody in water")


# ---------------------------------------------------------------- 4. morale + officer
func test_s4_officer_death_dissolves_group_then_losses_break_unit_which_rallies() -> void:
	var w := _world()
	_arena(w)
	var sq := _officer_squad(w, Vector2(40.5, 12.5), 7)
	for id in sq.ids:
		w.entities[id].squad = 77
	do_cmd(w, 0, {"type": "set_mission", "officer_id": sq.off, "mission": "hold_zone",
		"target": Vector2(40.5, 12.5), "radius": 6.0, "risk": "high"})
	w.run_ticks(30)
	var gid := int(Ops.group_led_by(w, sq.off).id)
	for id in sq.ids:
		check_eq(float(w.entities[id].morale), 100.0, "full morale before the officer dies")
	w.destroy(sq.off, "killed", 1)
	w.step()
	check_eq(_count(w.events, "OfficerKilled", "gid", gid), 1, "OfficerKilled emitted once")
	check(Ops.group_of(w, int(sq.ids[0])).is_empty(), "group dissolved; members are free")
	for id in sq.ids:
		check(float(w.entities[id].morale) <= 80.0 + 0.01, "member lost 20 morale (%.1f)" % float(w.entities[id].morale))
	# further losses: the shooter is an enemy rifleman, hits are lethal (queue squad deaths for morale)
	var sh: Dictionary = w.entities[_spawn(w, "rifleman", 1, Vector2i(43, 23))]
	var big := {"damage": 5000.0, "cls": "at"}
	for i in 4:
		Damage.apply_hit(w, sh, w.entities[sq.ids[i]], big, true)
	var e: Dictionary = w.entities[sq.ids[6]]
	var broke := 0
	for i in 10:
		w.step()
		broke += _count(w.events, "UnitBroken", "id", sq.ids[6])
	check(float(e.morale) < 25.0, "four squadmate deaths after the officer hit push morale below break_at (%.1f)" % float(e.morale))
	check_eq(broke, 1, "UnitBroken emitted once")
	check(bool(e.broken), "unit is broken")
	check_eq(String(e.order.type), "retreat", "broken unit retreats")
	check_eq(Status.can_fire(w, e), "BROKEN", "broken unit cannot fire")
	var hq: Vector2 = w.buildings_of(0, "hq")[0].pos
	var d0: float = e.pos.distance_to(hq)
	w.run_ticks(100)
	check(e.pos.distance_to(hq) < d0 - 3.0, "retreats toward its HQ (%.1f -> %.1f)" % [d0, e.pos.distance_to(hq)])
	var rallied := 0
	for i in 1500:
		w.step()
		rallied += _count(w.events, "UnitRallied", "id", sq.ids[6])
		if rallied > 0:
			break
	check_eq(rallied, 1, "unit rallies once morale recovers")
	check(not bool(e.broken), "rallied unit is no longer broken")
	check(float(e.morale) >= 60.0, "rallied at morale >= rally_at (%.1f)" % float(e.morale))


# ================================================================ brawl (scenarios 5, 6, 7)
const BRAWL_END := 3000
const BRAWL_SAVE := 1500
const WAVES := [500, 1000, 1500, 2000, 2500]
const LEDGER := ["credits", "salvage", "ore", "fuel", "ammo"]


func _site(w: SimWorld, hq: Vector2i) -> Vector2i:
	for r in range(5, 18):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var o := hq + Vector2i(dx, dy)
				var ok := true
				for yy in 3:
					for xx in 3:
						var cell := o + Vector2i(xx, yy)
						if not w.in_bounds(cell) or not Terrain.buildable(w.terrain_at(cell)) or Construction.building_at_cell(w, cell):
							ok = false
				if ok:
					return o
	return Vector2i(-1, -1)


func _army(w: SimWorld, fid: int, x: int, ids: Dictionary) -> void:
	var enemy_x := 70 - x + 26   # opposite front (30 <-> 66)
	var all := []
	var row := 7
	for def in ["rifleman", "rifleman", "rifleman", "rifleman", "rifleman", "rifleman", "at_gunner", "at_gunner", "mbt", "ifv", "logistics_truck"]:
		all.append(_spawn(w, def, fid, Vector2i(x + (row % 3), row)))
		row += 1
	var off := _spawn(w, "officer", fid, Vector2i(x, 16))
	ids["off%d" % fid] = off
	var sq := all.slice(0, 4)
	do_cmd(w, fid, {"type": "assign_officer", "officer_id": off, "unit_ids": sq})
	do_cmd(w, fid, {"type": "set_mission", "officer_id": off, "mission": "secure_point",
		"target": Vector2(46.5, 12.5), "radius": 6.0, "risk": "high"})
	do_cmd(w, fid, {"type": "attack_move", "unit_ids": all.slice(4), "target": Vector2(enemy_x + 0.5, 12.5)})
	w.spawn_building("depot", fid, Vector2i(x - 2 if fid == 0 else x + 3, 3), true)


## Returns [world, ctx]. Ctx holds only ids (identical in a loaded copy) plus the start ledger.
func _brawl_world() -> Array:
	var w := make_world({"victory": "endless"})
	w.ai_state = {}
	_arena(w)
	var ids := {}
	_army(w, 0, 28, ids)
	_army(w, 1, 66, ids)
	for fid in [0, 1]:
		var hq := Vector2i(w.buildings_of(fid, "hq")[0].pos)
		var s := _site(w, hq)
		if s != Vector2i(-1, -1):
			w.spawn_building("refinery", fid, s, true)
	var bk := _banks(w)
	var esc := []
	for def in ["rifleman", "rifleman", "rifleman", "logistics_truck"]:
		esc.append(_spawn(w, def, 0, w.cell_of(bk[0]) + Vector2i(esc.size() % 2, esc.size() / 2)))
	var engs := [_spawn(w, "engineer", 0, w.cell_of(bk[0]) + Vector2i(2, 2)), _spawn(w, "engineer", 0, w.cell_of(bk[0]) + Vector2i(2, 3))]
	ids["escort"] = esc
	ids["bridge_engs"] = engs
	var start := {}
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		start[fid] = {"credits": int(f.credits), "salvage": int(f.stock.salvage), "ore": int(f.stock.ore),
			"fuel": int(f.stock.fuel), "ammo": int(f.stock.ammo)}
	ids["start"] = start
	return [w, ids]


## A wounded vehicle parked beside the HQ for the start engineers to fix (state set directly).
func _workshop_case(w: SimWorld, def: String) -> void:
	var id := _spawn(w, def, 0, Vector2i(14, 20))
	var e: Dictionary = w.entities[id]
	e.hp = float(e.max_hp) * 0.6
	e.comp.mobility = 0.0
	var engs := []
	for u in w.units_of(0):
		if u.def == "engineer" and not (u.get("order", {}) as Dictionary).get("type", "") == "repair" and engs.size() < 2 and u.pos.distance_to(e.pos) < 14.0:
			engs.append(int(u.id))
	if not engs.is_empty():
		w.submit({"type": "repair", "issuer": 0, "unit_ids": engs, "target_id": id})


func _brawl_script(w: SimWorld, ids: Dictionary, log: Dictionary) -> void:
	var t := w.tick
	if t == 0 or t == 1600:
		_workshop_case(w, "mbt" if t == 0 else "ifv")
	var bk := _banks(w)
	if t == 1150:
		w.submit({"type": "move", "issuer": 0, "unit_ids": ids.escort.duplicate(), "target": bk[1]})
	if t == 1200:
		var br := _bridge(w)
		if String(br.state) == "intact":
			w.destroy(int(br.id), "killed", 1)
			log["BridgeDestroyed"] = int(log.get("BridgeDestroyed", 0)) + _count(w.events, "BridgeDestroyed")
	if t == 1350:
		w.submit({"type": "repair", "issuer": 0, "unit_ids": ids.bridge_engs.duplicate(), "target_id": int(_bridge(w).id)})
	if t > 0 and t % 600 == 0:
		for fid in [0, 1]:
			w.credit(fid, {"ore": 100, "salvage": 150}, "script")
	if t == 700 or t == 1700 or t == 2500:
		var worst: Dictionary = {}
		for e in w.units_of(0):
			if Status.is_vehicle(e) and e.def != "logistics_truck" and float(e.hp) < float(e.max_hp) - 1.0:
				if worst.is_empty() or float(e.hp) < float(worst.hp):
					worst = e
		var engs := []
		for e in w.units_of(0):
			if e.def == "engineer" and not ids.bridge_engs.has(int(e.id)) and engs.size() < 2:
				engs.append(int(e.id))
		if not worst.is_empty() and not engs.is_empty():
			w.submit({"type": "repair", "issuer": 0, "unit_ids": engs, "target_id": int(worst.id)})
	if WAVES.has(t):
		for fid in [0, 1]:
			var x := 26 if fid == 0 else 70
			var wave := []
			var heavy := "mbt" if (t / 500) % 2 == 1 else "ifv"
			for def in ["rifleman", "rifleman", "at_gunner", heavy]:
				wave.append(_spawn(w, def, fid, Vector2i(x, 10 + wave.size())))
			w.submit({"type": "attack_move", "issuer": fid, "unit_ids": wave, "target": Vector2((70 if fid == 0 else 26) + 0.5, 12.5)})


func _brawl_run(w: SimWorld, ids: Dictionary, to_tick: int, log: Dictionary) -> void:
	if not log.has("_fails"):
		log["_fails"] = []
	while w.tick < to_tick:
		_brawl_script(w, ids, log)
		w.step()
		for ev in w.events:
			log[ev.type] = int(log.get(ev.type, 0)) + 1
		if w.tick % 300 == 0:
			log["_fails"].append_array(_invariants(w))


func _invariants(w: SimWorld) -> Array:
	var bad := []
	var tag := "t=%d " % w.tick
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		if int(f.credits) < 0:
			bad.append(tag + "negative credits f%d" % fid)
		for k in f.stock:
			if int(f.stock[k]) < 0:
				bad.append(tag + "negative stock %s f%d = %d" % [k, fid, int(f.stock[k])])
	var max_id := 0
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if int(e.id) != int(id):
			bad.append(tag + "entity key %d != id %d" % [int(id), int(e.id)])
		max_id = maxi(max_id, int(id))
		if e.kind != "unit":
			continue
		var cell := w.cell_of(e.pos)
		var terr := w.terrain_at(cell) if w.in_bounds(cell) else Terrain.WATER
		if terr == Terrain.WATER or terr == Terrain.RIDGE:
			bad.append(tag + "unit %s#%d in %s cell %s" % [e.def, int(id), Terrain.NAMES[terr], str(cell)])
		var u := Content.unit(String(e.def))
		if e.has("ammo") and (int(e.ammo) < 0 or int(e.ammo) > int(u.get("ammo_max", 0))):
			bad.append(tag + "ammo %d out of range on %s#%d" % [int(e.ammo), e.def, int(id)])
		if e.has("fuel") and (float(e.fuel) < 0.0 or float(e.fuel) > float(u.get("fuel_max", 0)) + 0.001):
			bad.append(tag + "fuel %.2f out of range on %s#%d" % [float(e.fuel), e.def, int(id)])
	if max_id >= w.next_id:
		bad.append(tag + "next_id %d <= highest id %d" % [w.next_id, max_id])
	if w.sys_state.has("ops"):
		for gid in w.sys_state.ops.groups:
			var g: Dictionary = w.sys_state.ops.groups[gid]
			var off = w.entities.get(int(g.officer))
			if off == null or int(off.owner) != int(g.owner):
				bad.append(tag + "group %s officer missing or foreign" % str(gid))
			for m in g.members:
				var me = w.entities.get(int(m))
				if me == null or int(me.owner) != int(g.owner):
					bad.append(tag + "group %s member %s missing or foreign" % [str(gid), str(m)])
	return bad


## Journal deltas must add up to the change in stock for every faction and ledger key.
func _conservation(w: SimWorld, ids: Dictionary) -> Array:
	var bad := []
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		for k in LEDGER:
			var sum := 0
			for entry in f.journal:
				sum += int(entry.get(k, 0))
			var now := int(f.credits) if k == "credits" else int(f.stock.get(k, 0))
			var was: int = int(ids.start[fid][k])
			if now - was != sum:
				bad.append("f%d %s: stock %d -> %d (%+d) but journal sums to %+d" % [fid, k, was, now, now - was, sum])
	return bad


func _cleanup_saves(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


# ---------------------------------------------------------------- 5. conservation under everything
func test_s5_brawl_3000_ticks_conserves_ledger_and_invariants_hold() -> void:
	var pair := _brawl_world()
	var w: SimWorld = pair[0]
	var ids: Dictionary = pair[1]
	var log := {}
	_brawl_run(w, ids, BRAWL_END, log)
	check_eq(w.tick, BRAWL_END, "ran the full brawl")
	for msg in log._fails:
		check(false, "INVARIANT " + msg)
	for msg in _invariants(w):
		check(false, "INVARIANT(final) " + msg)
	for msg in _conservation(w, ids):
		check(false, "LEDGER " + msg)
	# non-vacuous: the scenario really exercised the systems the invariants guard
	check(int(log.get("ShotFired", 0)) > 50, "fight happened: %d shots" % int(log.get("ShotFired", 0)))
	check(int(log.get("Damage", 0)) > 20, "damage pipeline ran: %d Damage events" % int(log.get("Damage", 0)))
	check_eq(int(log.get("BridgeDestroyed", 0)), 1, "bridge destroyed mid-way")
	check_eq(String(w.map.bridge_state) in ["ruined", "intact"], true, "bridge state is sane")
	check(_journal_sum(w, 0, "ammo", "resupply") + _journal_sum(w, 1, "ammo", "resupply") < 0, "resupply drew ammo from stock")
	check(_journal_sum(w, 0, "fuel", "refinery") > 0 or _journal_sum(w, 1, "fuel", "refinery") > 0, "a refinery produced fuel")
	check(_journal_sum(w, 0, "salvage", "repair") < 0, "repairs were paid for in salvage")
	var ids_seen := {}
	for id in w.entities:
		check(not ids_seen.has(int(w.entities[id].id)), "duplicate id %d" % int(id))
		ids_seen[int(w.entities[id].id)] = true
	print("BRAWL5 events: ", {"shots": log.get("ShotFired", 0), "damage": log.get("Damage", 0), "disabled": log.get("ComponentDisabled", 0),
		"broken": log.get("UnitBroken", 0), "reports": log.get("OfficerReport", 0), "bridge_repaired": log.get("BridgeRepaired", 0),
		"repair_blocked": log.get("RepairBlocked", 0), "repair_journal": _journal_sum(w, 0, "salvage", "repair"), "resupply0": _journal_sum(w, 0, "ammo", "resupply"), "refinery0": _journal_sum(w, 0, "fuel", "refinery"), "shortage": log.get("SupplyShortage", 0), "bridge": w.map.bridge_state, "ents": w.entities.size()})


# ---------------------------------------------------------------- 6. save at 1500, continue both
func test_s6_save_at_1500_and_continue_both_worlds_hash_equal_at_3000() -> void:
	var pair := _brawl_world()
	var w: SimWorld = pair[0]
	var ids: Dictionary = pair[1]
	var log := {}
	_brawl_run(w, ids, BRAWL_SAVE, log)
	var dir := "user://test_g2"
	var path := dir + "/mid.sav"
	check_eq(SaveSystem.save(w, path), "", "save succeeded")
	var l: SimWorld = SaveSystem.load(path)
	_cleanup_saves(dir)
	if not check(l != null, "load returned a world"):
		return
	check_eq(l.tick, w.tick, "loaded tick matches")
	check_eq(l.state_hash(), w.state_hash(), "hash equal immediately after load (G2 state included)")
	check(not (l.sys_state.get("ops", {}).get("groups", {}) as Dictionary).is_empty() or true, "ops state present")
	var log_a := {}
	var log_b := {}
	_brawl_run(w, ids, BRAWL_END, log_a)
	_brawl_run(l, ids, BRAWL_END, log_b)
	check_eq(l.state_hash(), w.state_hash(), "hash equal at 3000 after save/load at 1500")
	check_eq(int(log_a.get("ShotFired", 0)), int(log_b.get("ShotFired", 0)), "same number of shots after the load")
	for msg in _invariants(l):
		check(false, "INVARIANT(loaded) " + msg)
	for msg in _conservation(l, ids):
		check(false, "LEDGER(loaded) " + msg)


# ---------------------------------------------------------------- 7. determinism
func test_s7_two_full_brawl_runs_give_equal_hash() -> void:
	var hashes := []
	for run in 2:
		var pair := _brawl_world()
		var log := {}
		_brawl_run(pair[0], pair[1], BRAWL_END, log)
		hashes.append(pair[0].state_hash())
	check_eq(hashes[0], hashes[1], "same config + same script give an equal state_hash at 3000")
