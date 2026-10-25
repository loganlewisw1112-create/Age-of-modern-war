extends "res://tests/test_base.gd"
## G5 acceptance (owner: SUPPORT). CONTRACTS_G5 sections 10 and 11: logistics-truck Auto Resupply
## (station / roam, combat rule, resume order, truck self-refill, no doubling up, ships + helicopters).

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")
const Support = preload("res://sim/systems/support.gd")
const SaveSystem = preload("res://sim/save_system.gd")


# ---------------------------------------------------------------- helpers
func _hq(w: SimWorld, fid: int = 0) -> Dictionary:
	return w.buildings_of(fid, "hq")[0]


func _cell_pos(c: Vector2i) -> Vector2:
	return Vector2(c) + Vector2(0.5, 0.5)


func _free(w: SimWorld, p: Vector2, mc: String = "vehicle") -> Vector2:
	return _cell_pos(Movement.nearest_free_cell(w, w.cell_of(p), mc))


## Distance from p to the nearest own built supply source building (HQ / supply point).
func _src_dist(w: SimWorld, p: Vector2) -> float:
	var best := INF
	for b in w.buildings_of(0):
		var d := Content.building(String(b.def))
		if bool(d.get("is_hq", false)) or bool(d.get("supply_point", false)):
			best = minf(best, Construction.footprint_dist(p, b.cell, int(b.size)))
	return best


## A station site reachable by vehicle from the HQ and well outside every building's supply radius.
func _site(w: SimWorld) -> Vector2:
	var hq := _hq(w)
	var probe: Dictionary = w.entities[w.spawn_unit("logistics_truck", 0, _free(w, Vector2(hq.pos) + Vector2(4, 4)))]
	var out := Vector2.ZERO
	for off in [Vector2(0, 22), Vector2(22, 0), Vector2(-22, 0), Vector2(0, -22), Vector2(16, 16), Vector2(-16, 16), Vector2(16, -16), Vector2(-16, -16)]:
		var p := _free(w, Vector2(hq.pos) + off)
		if w.in_bounds(w.cell_of(p)) and _src_dist(w, p) > 18.0 and Movement.can_reach(w, probe, p):
			out = p
			break
	w.destroy(int(probe.id), "test")
	check(out != Vector2.ZERO, "found a station site")
	return out


func _unit(w: SimWorld, def: String, p: Vector2) -> Dictionary:
	var mc := String(Content.unit(def).get("move_class", "foot"))
	return w.entities[w.spawn_unit(def, 0, _free(w, p, mc))]


func _auto(w: SimWorld, truck: Dictionary, mode: String, radius: float = 16.0) -> void:
	var ev := do_cmd(w, 0, {"type": "set_auto_resupply", "unit_id": int(truck.id), "mode": mode,
		"center": [float(truck.pos.x), float(truck.pos.y)], "radius": radius})
	check_eq(rejected_reason(ev), "", "set_auto_resupply %s accepted" % mode)


func _low(e: Dictionary, frac: float) -> void:
	e.ammo = int(float(Content.unit(String(e.def)).ammo_max) * frac)


## Steps n ticks; returns the events of the given types in order.
func _run(w: SimWorld, n: int, types: Array) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.has(ev.type):
				out.append(ev)
	return out


func _first(evs: Array, type: String, key: String, val: int) -> int:
	for i in evs.size():
		if evs[i].type == type and int(evs[i].get(key, -1)) == val:
			return i
	return -1


# ---------------------------------------------------------------- tests
func test_station_mode_units_come_restock_and_return() -> void:
	var w := make_world()
	var site := _site(w)
	var truck := _unit(w, "logistics_truck", site)
	var u := _unit(w, "ifv", site + Vector2(11, 3))
	w.step()
	_low(u, 0.1)
	var d0 := (Vector2(u.pos) - Vector2(truck.pos)).length()
	check(d0 > 9.0, "unit starts outside the supply radius (%.1f)" % d0)
	_auto(w, truck, "station")
	var closest := INF
	var evs := []
	for i in 1400:
		w.step()
		for ev in w.events:
			if ev.type in ["ResupplyClaimed", "ResupplyResumed"]:
				evs.append(ev)
		closest = minf(closest, (Vector2(u.pos) - Vector2(truck.pos)).length())
		if _first(evs, "ResupplyResumed", "unit", int(u.id)) >= 0:
			break
	check(_first(evs, "ResupplyClaimed", "unit", int(u.id)) >= 0, "unit claimed by the station truck")
	check(closest <= 4.5, "unit came to the truck (closest %.1f)" % closest)
	check_eq(int(u.ammo), int(Content.unit("ifv").ammo_max), "unit fully restocked")
	check(_first(evs, "ResupplyResumed", "unit", int(u.id)) >= 0, "unit released back to its order")
	check(not u.has("resup_by") and not u.has("resume_order"), "claim fields cleared")
	check(Support.truck_state(w, int(truck.id)).queue.is_empty(), "truck queue empty")


func test_roam_mode_truck_visits_neediest_first() -> void:
	var w := make_world()
	var site := _site(w)
	var truck := _unit(w, "logistics_truck", site)
	var a := _unit(w, "ifv", site + Vector2(11, 0))
	var b := _unit(w, "ifv", site + Vector2(-11, 0))
	w.step()
	_low(a, 0.3)
	_low(b, 0.05)
	var bp: Vector2 = b.pos
	_auto(w, truck, "roam", 20.0)
	var evs := _run(w, 1600, ["ResupplyClaimed"])
	var ib := _first(evs, "ResupplyClaimed", "unit", int(b.id))
	var ia := _first(evs, "ResupplyClaimed", "unit", int(a.id))
	check(ib == 0, "the neediest unit (5%% ammo) is visited first (index %d)" % ib)
	check(ia > ib, "the second unit is visited next (index %d)" % ia)
	check_eq(int(b.ammo), int(Content.unit("ifv").ammo_max), "first unit restocked")
	check_eq(int(a.ammo), int(Content.unit("ifv").ammo_max), "second unit restocked")
	check((Vector2(b.pos) - bp).length() < 1.5, "roam: the unit stays put, the truck comes")


func test_in_combat_unit_waits_unless_empty() -> void:
	var w := make_world()
	var site := _site(w)
	var truck := _unit(w, "logistics_truck", site)
	var fighter := _unit(w, "ifv", site + Vector2(10, 2))
	var calm := _unit(w, "ifv", site + Vector2(-10, 2))
	w.step()
	_low(fighter, 0.1)
	_low(calm, 0.1)
	_auto(w, truck, "station")
	for i in 80:
		fighter.last_hit_tick = w.tick   # under fire the whole time
		w.step()
	check(not fighter.has("resup_by"), "a unit in combat with ammo left does not leave")
	check(calm.has("resup_by") or int(calm.ammo) == int(Content.unit("ifv").ammo_max), "the unit out of combat is served")
	fighter.ammo = 0
	var claimed := false
	for i in 80:
		fighter.last_hit_tick = w.tick
		w.step()
		if fighter.has("resup_by"):
			claimed = true
			break
	check(claimed, "an empty unit leaves the fight for supply")


func test_units_resume_saved_order() -> void:
	var w := make_world()
	var site := _site(w)
	var truck := _unit(w, "logistics_truck", site)
	var u := _unit(w, "ifv", site + Vector2(8, 0))
	w.step()
	var goal := _free(w, site + Vector2(-30, 0))
	if not Movement.can_reach(w, u, goal):
		goal = _free(w, site + Vector2(0, -26))
	u.order = {"type": "move", "target": goal}
	Movement.order_path(w, u, goal)
	_low(u, 0.1)
	_auto(w, truck, "station", 24.0)
	var evs := _run(w, 40, ["ResupplyClaimed"])
	check(_first(evs, "ResupplyClaimed", "unit", int(u.id)) >= 0, "moving unit claimed")
	check_eq(String(u.resume_order.get("type", "")) if u.has("resume_order") else "", "move", "its move order is saved")
	var resumed := false
	for i in 1400:
		w.step()
		if not u.has("resup_by"):
			resumed = true
			break
	check(resumed, "released after restocking")
	check_eq(String(u.order.get("type", "")), "move", "order type restored")
	check_eq(u.order.get("target"), goal, "order target restored")
	var d1 := (Vector2(u.pos) - goal).length()
	for i in 200:
		w.step()
	check((Vector2(u.pos) - goal).length() < d1 - 3.0, "unit carries on toward its old goal")


func test_truck_self_refills_at_depot() -> void:
	var w := make_world()
	var site := _site(w)
	var truck := _unit(w, "logistics_truck", site)
	var u := _unit(w, "ifv", site + Vector2(6, 2))
	w.step()
	_low(u, 0.1)
	_auto(w, truck, "station")
	var ts := Support.truck_state(w, int(truck.id))
	ts.load = 8
	var evs := []
	for i in 2400:
		w.step()
		for ev in w.events:
			if ev.type in ["TruckEmpty", "TruckRefilled"]:
				evs.append(ev)
		if _first(evs, "TruckRefilled", "truck", int(truck.id)) >= 0:
			break
	var ie := _first(evs, "TruckEmpty", "truck", int(truck.id))
	var ir := _first(evs, "TruckRefilled", "truck", int(truck.id))
	check(ie >= 0, "truck runs empty")
	check(ir > ie, "then refills at a depot")
	if ir >= 0:
		var b = w.entities.get(int(evs[ir].building))
		check(b != null and (bool(Content.building(String(b.def)).get("is_hq", false)) or bool(Content.building(String(b.def)).get("supply_point", false)) or Content.building(String(b.def)).has("refines")), "refilled at an HQ / depot / refinery")
	check_eq(int(Support.truck_state(w, int(truck.id)).load), int(Support.cfg().truck_load), "load restored")
	check_eq(String(Support.truck_state(w, int(truck.id)).phase), "serve", "back to work")


func test_two_trucks_never_double_up() -> void:
	var w := make_world()
	var site := _site(w)
	var t1 := _unit(w, "logistics_truck", site)
	var t2 := _unit(w, "logistics_truck", site + Vector2(3, 0))
	var units := []
	for i in 9:
		units.append(_unit(w, "ifv", site + Vector2(-8 + 2 * (i % 3), -8 + 3 * (i / 3))))
	w.step()
	for u in units:
		_low(u, 0.1)
	_auto(w, t1, "station")
	_auto(w, t2, "roam", 16.0)
	var both := 0
	var bad := 0
	var by2 := {}
	for i in 600:
		w.step()
		var q1: Array = Support.truck_state(w, int(t1.id)).queue
		var q2: Array = Support.truck_state(w, int(t2.id)).queue
		for id in q1:
			if q2.has(id):
				both += 1
			if int(w.entities[int(id)].get("resup_by", -1)) != int(t1.id):
				bad += 1
		for id in q2:
			by2[int(id)] = true
			if int(w.entities[int(id)].get("resup_by", -1)) != int(t2.id):
				bad += 1
	check_eq(both, 0, "no unit is ever in two trucks' queues")
	check_eq(bad, 0, "every queued unit is claimed by exactly that truck")
	check(by2.size() >= 1, "the second truck served units the first did not hold")


func test_ship_and_helicopter_restock() -> void:
	var w := make_world()
	var hq := _hq(w)
	var water := Movement.nearest_free_cell(w, w.cell_of(hq.pos), "naval_small")
	check(Movement.is_passable(w, water, "naval_small"), "map has water for boats")
	var bank := _free(w, _cell_pos(water), "vehicle")
	var truck := _unit(w, "logistics_truck", bank)
	var heli := _unit(w, "a_attack_heli", Vector2(truck.pos) + Vector2(12, 0))
	var boat: Dictionary = w.entities[w.spawn_unit("a_patrol_boat", 0, _cell_pos(Movement.nearest_free_cell(w, water + Vector2i(10, 0), "naval_small")))]
	w.step()
	_low(heli, 0.1)
	_low(boat, 0.1)
	_auto(w, truck, "station", 20.0)
	var evs := _run(w, 1600, ["ResupplyClaimed", "ResupplyResumed"])
	check(_first(evs, "ResupplyClaimed", "unit", int(heli.id)) >= 0, "helicopter claimed")
	check(_first(evs, "ResupplyClaimed", "unit", int(boat.id)) >= 0, "ship claimed")
	check_eq(int(heli.ammo), int(Content.unit("a_attack_heli").ammo_max), "helicopter restocked by the truck")
	check_eq(int(boat.ammo), int(Content.unit("a_patrol_boat").ammo_max), "ship restocked at the shore")
	check(_first(evs, "ResupplyResumed", "unit", int(heli.id)) >= 0 and _first(evs, "ResupplyResumed", "unit", int(boat.id)) >= 0, "both resume their orders (heli ammo %s fuel %s claim %s / boat ammo %s fuel %s claim %s pos %s truck %s)" % [heli.ammo, heli.get("fuel"), heli.get("resup_by"), boat.ammo, boat.get("fuel"), boat.get("resup_by"), boat.pos, truck.pos])


## PERF (G5): the needy slot-scan set (sys_state.support.needy, saved) and its runtime cell buckets
## survive save/load: same hash right after the load and 600 ticks later, claims included.
func test_save_load_mid_resupply_same_hash() -> void:
	var w := make_world()
	var site := _site(w)
	var t1 := _unit(w, "logistics_truck", site)
	var t2 := _unit(w, "logistics_truck", site + Vector2(4, 0))
	var us := []
	for i in 6:
		us.append(_unit(w, "ifv", site + Vector2(6 + 2 * (i % 3), 3 + 2 * (i / 3))))
	w.step()
	for u in us:
		_low(u, 0.1)
	_auto(w, t1, "station")
	_auto(w, t2, "roam")
	for i in 45:
		w.step()
	check(w.sys_state.support.has("needy"), "needy set saved in sys_state.support")
	check(not (w.sys_state.support.needy as Dictionary).is_empty(), "needy units found by the slot scan")
	var res: Dictionary = SaveSystem.decode_bytes(SaveSystem.encode_dict(w.to_dict()))
	check(bool(res.ok), "save decodes")
	var w2 := SimWorld.from_dict(res.dict)
	check_eq(w2.state_hash(), w.state_hash(), "hash equal after load")
	for i in 600:
		w.step()
		w2.step()
	check_eq(w2.state_hash(), w.state_hash(), "same hash 600 ticks after load")
	check(int(w.entities[int(us[0].id)].ammo) > int(0.1 * float(Content.unit("ifv").ammo_max)) + 1, "resupply happened (ammo above its 10% start)")
