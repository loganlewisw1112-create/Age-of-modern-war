extends "res://tests/test_base.gd"
## G6 acceptance (owner: MECH6b). CONTRACTS_G6 section 10, section 17: strikes.

const Strikes = preload("res://sim/systems/strikes.gd")
const HotState = preload("res://sim/hot_state.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const Movement = preload("res://sim/systems/movement.gd")


## fid 0 (faction f0) vs Human A fid 1, no AI.
func _w(f0: String = "human_a") -> SimWorld:
	return make_world({"sides": [
		{"faction": f0, "stage": 8, "credits": 5000, "ai": false, "name": "S", "team": 0},
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "T", "team": 1}]})


## A cell whose r-square is passable for vehicles, scanning outward from `near`.
func _open(w: SimWorld, near: Vector2i, r: int = 3) -> Vector2i:
	for rad in range(0, 60):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var c := near + Vector2i(dx, dy)
				var ok := true
				for y in range(-r, r + 1):
					for x in range(-r, r + 1):
						var cc := c + Vector2i(x, y)
						if ok and (not w.in_bounds(cc) or not Movement.is_passable(w, cc, "vehicle")):
							ok = false
				if ok:
					return c
	return near


func _unit(w: SimWorld, def_id: String, fid: int, p: Vector2) -> Dictionary:
	var id := w.spawn_unit(def_id, fid, p)
	HotState.touch(w, id)
	return w.entities[id]


func _ctr(w: SimWorld) -> Vector2i:
	return Vector2i(int(w.map.w) / 2, int(w.map.h) / 2)


func _count(evs: Array, type: String, kind: String = "") -> int:
	var n := 0
	for ev in evs:
		if ev.type == type and (kind == "" or String(ev.get("kind", "")) == kind):
			n += 1
	return n


## Steps n ticks, collecting every event.
func _run(w: SimWorld, n: int) -> Array:
	var all := []
	for i in n:
		w.step()
		all.append_array(w.events)
	return all


func test_loiter_munitions_6_per_load() -> void:
	var w := _w()
	var c := _open(w, _ctr(w))
	var p := Vector2(c) + Vector2(0.5, 0.5)
	var truck := _unit(w, "a_loiter_truck", 0, p)
	var tc := _open(w, c + Vector2i(14, 0), 1)
	var tank := _unit(w, "a_old_tank", 1, Vector2(tc) + Vector2(0.5, 0.5))
	w.step()
	check_eq(Strikes.kind_of(truck), "loiter", "loiter truck is a loiter striker")
	check_eq(Strikes.munitions_left(w, truck), 6, "6 munitions per load")
	var launched := 0
	for i in 6:
		var ev := do_cmd(w, 0, {"type": "strike", "unit_ids": [int(truck.id)], "cell": [tc.x, tc.y], "target_id": int(tank.id)})
		launched += _count(ev, "StrikeLaunched", "loiter")
	check_eq(launched, 6, "six munitions launched")
	check_eq(Strikes.munitions_left(w, truck), 0, "load spent")
	var ev7 := do_cmd(w, 0, {"type": "strike", "unit_ids": [int(truck.id)], "cell": [tc.x, tc.y]})
	check(rejected_reason(ev7).contains("munitions"), "7th strike rejected: %s" % rejected_reason(ev7))
	var drones := 0
	for id in w.entities:
		if String(w.entities[id].def) == "a_drone_strike":
			drones += 1
	check_eq(drones, 6, "six loitering munition entities in flight")
	var hp0 := float(tank.max_hp)
	var evs := _run(w, 200)
	check(_count(evs, "StrikeImpact", "loiter") >= 1, "munitions dived and hit")
	check(not w.entities.has(int(tank.id)) or float(tank.hp) < hp0, "target damaged or destroyed")
	var done := _count(evs, "StrikeImpact", "loiter") + _count(evs, "LoiterLost")
	evs = _run(w, roundi(60.0 * SimWorld.TICK_RATE))
	done += _count(evs, "StrikeImpact", "loiter") + _count(evs, "LoiterLost")
	check_eq(done, 6, "every munition ended (impact or lost) within its loiter time")
	check(not w.sys_state.strikes.loiter.size() > 0, "no munition left in flight")
	check_eq(Strikes.munitions_left(w, truck), 6, "reloaded to 6 after reload_s")
	var ev8 := do_cmd(w, 0, {"type": "strike", "unit_ids": [int(truck.id)], "cell": [tc.x, tc.y]})
	check_eq(_count(ev8, "StrikeLaunched", "loiter"), 1, "strikes again after the reload")
	var far := do_cmd(w, 0, {"type": "strike", "unit_ids": [int(truck.id)], "cell": [mini(c.x + 45, int(w.map.w) - 1), c.y]})
	if c.x + 45 < int(w.map.w):
		check(rejected_reason(far).contains("range"), "beyond launch range rejected: %s" % rejected_reason(far))


func test_mlrs_salvo_area() -> void:
	var w := _w()
	var c := _open(w, _ctr(w))
	var p := Vector2(c) + Vector2(0.5, 0.5)
	var mlrs := _unit(w, "a_mlrs", 0, p)
	var tc := _open(w, c + Vector2i(15, 0), 3)
	var tp := Vector2(tc) + Vector2(0.5, 0.5)
	var foes := []
	for off in [Vector2(0, 0), Vector2(1.5, 1), Vector2(-1, -1.5)]:
		foes.append(_unit(w, "a_ew_truck", 1, tp + off))
	w.step()
	var hp0 := 0.0
	for f in foes:
		hp0 += float(f.hp)
	var ev := do_cmd(w, 0, {"type": "strike", "unit_ids": [int(mlrs.id)], "cell": [tc.x, tc.y]})
	check_eq(_count(ev, "StrikeLaunched", "rocket"), 12, "12-rocket salvo")
	var again := do_cmd(w, 0, {"type": "strike", "unit_ids": [int(mlrs.id)], "cell": [tc.x, tc.y]})
	check(rejected_reason(again).contains("Reloading"), "long reload after the salvo: %s" % rejected_reason(again))
	var evs := ev + again + _run(w, 120)
	var imp := []
	for e in evs:
		if e.type == "StrikeImpact" and String(e.kind) == "rocket":
			imp.append(e)
	check_eq(imp.size(), 12, "all 12 rockets land")
	var inside := true
	var spread := 0.0
	for e in imp:
		var d := Vector2(e.pos).distance_to(tp)
		spread = maxf(spread, d)
		inside = inside and d <= 3.0 + 0.01
	check(inside and spread > 0.5, "impacts scattered inside the 3-tile area (max %.2f)" % spread)
	var hp1 := 0.0
	for f in foes:
		hp1 += float(f.hp) if w.entities.has(int(f.id)) else 0.0
	check(hp1 < hp0, "salvo damaged the targets (%.0f -> %.0f)" % [hp0, hp1])
	_run(w, roundi(30.0 * SimWorld.TICK_RATE))
	check_eq(Strikes.cooldown_left(w, mlrs), 0, "reloaded after 30 s")
	if c.x + 30 < int(w.map.w):
		var far := do_cmd(w, 0, {"type": "strike", "unit_ids": [int(mlrs.id)], "cell": [c.x + 30, c.y]})
		check(rejected_reason(far).contains("range"), "beyond 22 tiles rejected: %s" % rejected_reason(far))
	var near := do_cmd(w, 0, {"type": "strike", "unit_ids": [int(mlrs.id)], "cell": [c.x + 2, c.y]})
	check(rejected_reason(near).contains("close"), "inside min range rejected: %s" % rejected_reason(near))


func test_mass_driver_long_range() -> void:
	var w := _w("machine")
	var c := _open(w, _ctr(w), 3)
	w.spawn_building("m_charging_hub", 0, c + Vector2i(-4, -4), true)
	var md: Dictionary = w.entities[w.spawn_building("m_mass_driver", 0, c, true)]
	var dir := Vector2(1, 0) if c.x + 34 < int(w.map.w) else Vector2(-1, 0)
	var tc := Vector2i((Vector2(md.pos) + dir * 30.0).floor())
	var tgt: Dictionary = w.entities[w.spawn_building("generator", 1, tc, true)]
	w.step()
	check_eq(Strikes.kind_of(md), "mass_driver", "mass driver is a battery striker")
	check_eq(Strikes.range_of(md), [8.0, 34.0], "slug range 8..34 tiles")
	var d := Vector2(md.pos).distance_to(Vector2(tgt.pos))
	check(d >= 28.0, "target ~30 tiles away (%.1f)" % d)
	var hp0 := float(tgt.hp)
	var ev := do_cmd(w, 0, {"type": "strike", "building_id": int(md.id), "cell": [int(tgt.pos.x), int(tgt.pos.y)], "target_id": int(tgt.id)})
	check_eq(_count(ev, "StrikeLaunched", "shell"), 1, "one slug fired")
	var again := do_cmd(w, 0, {"type": "strike", "building_id": int(md.id), "cell": [int(tgt.pos.x), int(tgt.pos.y)]})
	check(rejected_reason(again).contains("Reloading"), "cooldown after a slug: %s" % rejected_reason(again))
	var evs := _run(w, 40)
	check_eq(_count(evs, "StrikeImpact", "shell"), 1, "slug lands after its flight")
	check(float(tgt.hp) < hp0 - 100.0, "long-range slug damaged the target (%.0f -> %.0f)" % [hp0, float(tgt.hp)])
	_run(w, roundi(14.0 * SimWorld.TICK_RATE))
	var fc := Vector2i((Vector2(md.pos) + dir * 40.0).floor())
	if w.in_bounds(fc):
		var far := do_cmd(w, 0, {"type": "strike", "building_id": int(md.id), "cell": [fc.x, fc.y]})
		check(rejected_reason(far).contains("range"), "beyond 34 tiles rejected: %s" % rejected_reason(far))
	var nc := Vector2i((Vector2(md.pos) + dir * 4.0).floor())
	var near := do_cmd(w, 0, {"type": "strike", "building_id": int(md.id), "cell": [nc.x, nc.y]})
	check(rejected_reason(near).contains("close"), "inside 8 tiles rejected: %s" % rejected_reason(near))


func test_cruise_strike_cooldown_and_ciws_intercept() -> void:
	var w := _w()
	var c := _open(w, _ctr(w), 3)
	w.spawn_building("generator", 0, c + Vector2i(-4, -4), true)
	var bat: Dictionary = w.entities[w.spawn_building("a_cruise_battery", 0, c, true)]
	var far_c := Vector2i(int(w.map.w) - 8, 6) if c.x < int(w.map.w) / 2 else Vector2i(6, 6)
	var t1: Dictionary = w.entities[w.spawn_building("generator", 1, far_c, true)]
	w.step()
	check_eq(Strikes.kind_of(bat), "cruise", "cruise battery is a cruise striker")
	check_eq(Strikes.range_of(bat)[1], -1.0, "global range")
	var hp0 := float(t1.hp)
	var ev := do_cmd(w, 0, {"type": "strike", "building_id": int(bat.id), "cell": [int(t1.pos.x), int(t1.pos.y)]})
	check_eq(_count(ev, "StrikeLaunched", "cruise"), 1, "cruise missile launched at %.0f tiles" % Vector2(bat.pos).distance_to(Vector2(t1.pos)))
	var again := do_cmd(w, 0, {"type": "strike", "building_id": int(bat.id), "cell": [int(t1.pos.x), int(t1.pos.y)]})
	check(rejected_reason(again).contains("Reloading"), "long cooldown: %s" % rejected_reason(again))
	var evs := _run(w, 400)
	check_eq(_count(evs, "StrikeImpact", "cruise"), 1, "undefended target hit")
	check(not w.entities.has(int(t1.id)) or float(t1.hp) <= hp0 - 450.0, "900-damage warhead landed")
	check(Strikes.cooldown_left(w, bat) > 0, "still cooling down after ~20 s")
	_run(w, Strikes.cooldown_left(w, bat))
	check_eq(Strikes.cooldown_left(w, bat), 0, "ready after the 180 s cooldown")
	# defended target: an enemy Laser CIWS (powered) beside it shoots the missile down
	var t2c := Vector2i(far_c.x, far_c.y + 8)
	var t2: Dictionary = w.entities[w.spawn_building("generator", 1, t2c, true)]
	var ciws: Dictionary = w.entities[w.spawn_building("a_laser_ciws", 1, t2c + Vector2i(-2, 0), true)]
	w.step()
	check(int(w.factions[1].power_prod) >= int(w.factions[1].power_use), "defender powered")
	var hp2 := float(t2.hp)
	do_cmd(w, 0, {"type": "strike", "building_id": int(bat.id), "cell": [int(t2.pos.x), int(t2.pos.y)]})
	evs = _run(w, 400)
	check_eq(_count(evs, "StrikeIntercepted", "cruise"), 1, "Laser CIWS intercepted the cruise missile")
	check_eq(_count(evs, "StrikeImpact", "cruise"), 0, "no impact after the intercept")
	var strike_dmg := 0.0
	var other := []
	for e in evs:
		if e.type == "Damage" and int(e.target) == int(t2.id):
			if int(e.shooter) == int(bat.id):
				strike_dmg += float(e.amount)
			else:
				other.append([int(e.shooter), float(e.amount)])
	check_eq(strike_dmg, 0.0, "defended target took no strike damage (other sources: %s, hp %.1f -> %.1f)" % [str(other.slice(0, 4)), hp2, float(t2.hp)])
	check(w.entities.has(int(ciws.id)), "CIWS alive")
	check_eq(int(w.sys_state.strikes.intercepted), 1, "intercept counted in saved state")


## Not a skeleton item: strike state is saved + hashed (load mid-flight = same future), and a match with no
## striker never creates sys_state.strikes (G5 hashes unchanged).
func test_strikes_save_load_and_neutral() -> void:
	var w0 := make_world()
	for i in 60:
		w0.step()
	check(not w0.sys_state.has("strikes") and not w0.sys_state.has("machine_g6"), "no G6 strike/machine state without those units")
	var w := _w()
	var c := _open(w, _ctr(w))
	var p := Vector2(c) + Vector2(0.5, 0.5)
	var truck := _unit(w, "a_loiter_truck", 0, p)
	var mlrs := _unit(w, "a_mlrs", 0, p + Vector2(0, 2))
	var tc := _open(w, c + Vector2i(14, 0), 2)
	_unit(w, "a_ew_truck", 1, Vector2(tc) + Vector2(0.5, 0.5))
	w.step()
	do_cmd(w, 0, {"type": "strike", "unit_ids": [int(truck.id)], "cell": [tc.x, tc.y]})
	do_cmd(w, 0, {"type": "strike", "unit_ids": [int(mlrs.id)], "cell": [tc.x, tc.y]})
	for i in 10:
		w.step()
	check(not (w.sys_state.strikes.shots as Array).is_empty() and not (w.sys_state.strikes.loiter as Dictionary).is_empty(), "rockets and a munition in flight")
	var w2 := SimWorld.from_dict(SaveSystem.decode_bytes(SaveSystem.encode_dict(w.to_dict())).dict)
	check_eq(w2.state_hash(), w.state_hash(), "hash equal right after load")
	for i in 200:
		w.step()
		w2.step()
	check_eq(w2.state_hash(), w.state_hash(), "same hash 200 ticks after a mid-flight load")
