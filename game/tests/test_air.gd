extends "res://tests/test_base.gd"
## G5 acceptance (owner: AIRSYS). CONTRACTS_G5 sections 3.6, 4, 5, 7: jet sortie cycle, holding pattern,
## air-vs-air, helicopter landing zones, pad service with engineers, low-helicopter return, save mid-flight.

const Airfield = preload("res://sim/systems/airfield.gd")
const Air = preload("res://sim/systems/air.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const Helper = preload("res://tests/test_airfield.gd")
const TMP_DIR := "user://test_air"

var h = Helper.new()


func _w() -> SimWorld:
	return h._w()


func _run(w: SimWorld, n: int, f: Callable) -> int:
	return h._run(w, n, f)


func _evs(w: SimWorld, type: String) -> Array:
	return h._events(w, type)


## A cell near hq + off where a helicopter may land.
func _open_cell(w: SimWorld, off: Vector2i) -> Vector2i:
	var base: Vector2i = (h._hq(w, 0).cell as Vector2i) + off
	for r in range(0, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := base + Vector2i(dx, dy)
				if Air.landing_ok(w, c, Content.unit("a_attack_heli")) and Airfield.service_point_at(w, 0, Vector2(c)) < 0:
					return c
	return base


func test_jet_sortie_strike_return_land_rearm() -> void:
	var w := _w()
	var fb := h._field(w)
	var hid := h._hangar(w, fb)
	var j := h._jet(w, "a_strike_jet", hid)
	var tgt_pos := Vector2(w.entities[fb].pos) + Vector2(10, 30)   # clear of its own strip (bombs crater any strip)
	var t := w.spawn_unit("mbt", 1, tgt_pos)
	w.step()
	var hp0 := float(w.entities[t].hp)
	var ammo0 := int(w.entities[j].ammo)
	check(w.submit({"type": "sortie", "issuer": 0, "unit_ids": [j], "target_id": t}).ok, "sortie accepted")
	var seen := []
	var hit_tick := -1
	var ammo_low := ammo0
	for i in 2400:
		w.step()
		if not w.entities.has(j):
			break
		var ph := Air.phase(w, j)
		if seen.is_empty() or seen[seen.size() - 1] != ph:
			seen.append(ph)
		ammo_low = mini(ammo_low, int(w.entities[j].ammo))
		if hit_tick < 0 and not _evs(w, "AirStrike").is_empty():
			hit_tick = i
		if hit_tick >= 0 and ph == "parked" and int(w.entities[j].ammo) == ammo0:
			break
	for p in ["taxi", "hold", "roll", "sortie", "ret", "approach", "taxi_in", "parked"]:   # holding only when the strip is busy (own test)
		check(seen.has(p), "phase %s seen (%s)" % [p, str(seen)])
	check(hit_tick > 0, "the strike happened")
	check(not w.entities.has(t) or float(w.entities[t].hp) < hp0, "the target took the payload")
	check_eq(ammo_low, ammo0 - 1, "one payload spent")
	check_eq(int(w.entities[j].air_at), hid, "back in its own hangar")
	check_eq(int(w.entities[j].ammo), ammo0, "rearmed after landing")
	check(Air.is_landed(w.entities[j]), "on the ground")


func test_holding_pattern_lowest_fuel_lands_first() -> void:
	var w := _w()
	var fb := h._field(w)
	var ids := []
	for i in 3:
		ids.append(h._jet(w, "a_interceptor", h._hangar(w, fb)))
	w.submit({"type": "take_off", "issuer": 0, "unit_ids": ids})
	check(_run(w, 600, func() -> bool:
		for id in ids:
			if Air.phase(w, id) != "air":
				return false
		return true) > 0, "all three airborne")
	var fmax := float(Content.unit("a_interceptor").fuel_max)
	w.entities[ids[0]].fuel = fmax * 0.9
	w.entities[ids[1]].fuel = fmax * 0.5
	w.entities[ids[2]].fuel = fmax * 0.7
	var strip: Dictionary = Airfield.field(w, fb).strips[0]
	strip.busy_id = int(h._hq(w, 0).id)   # strip busy: arrivals must hold
	w.submit({"type": "rebase", "issuer": 0, "unit_ids": ids, "building_id": fb})
	check(_run(w, 600, func() -> bool: return (w.sys_state.air.holding.get(fb, []) as Array).size() == 3) > 0, "all three circle the field")
	for id in ids:
		check_eq(Air.phase(w, id), "holding", "jet %d holding" % id)
	strip.busy_id = -1
	var order := []
	_run(w, 900, func() -> bool:
		for ev in w.events:
			if String(ev.type) == "AircraftApproach":
				order.append(int(ev.id))
		return order.size() == 3)
	check_eq(order, [ids[1], ids[2], ids[0]], "lowest fuel lands first")


func test_interceptor_engages_enemy_aircraft() -> void:
	var w := _w()
	var p := Vector2(h._hq(w, 0).pos) + Vector2(20, 0)
	var i := w.spawn_unit("a_interceptor", 0, p)
	var g := w.spawn_unit("b_gunship", 1, p + Vector2(12, 0))   # in sight (13), beyond AAM range (9)
	w.step()
	check_eq(Air.phase(w, i), "air", "interceptor airborne (no hangar near)")
	var hp0 := float(w.entities[g].hp)
	var t := _run(w, 600, func() -> bool: return not w.entities.has(g) or float(w.entities[g].hp) < hp0)
	check(t > 0, "the interceptor hits the enemy aircraft")
	check(not _evs(w, "AirEngage").is_empty(), "AirEngage emitted")
	var wd := Content.weapon("aam_missile")
	check(Air.can_target(wd, w.entities.get(g, {"kind": "unit", "def": "b_gunship"})), "AAM can target air_low")
	check(not Air.can_target(Content.weapon("rifle"), {"kind": "unit", "def": "a_strike_jet"}), "rifles cannot hit jets")
	check(Air.can_target(Content.weapon("door_guns"), {"kind": "unit", "def": "b_gunship"}), "anti_air_low hits helicopters")
	check(not Air.can_target(Content.weapon("door_guns"), {"kind": "unit", "def": "a_strike_jet"}), "anti_air_low does not reach air_high")
	check(Air.can_target(Content.weapon("rifle"), {"kind": "unit", "def": "b_gunship", "air_landed": true}), "a landed helicopter is a ground target")


func test_helicopter_lands_on_open_ground_outside_base() -> void:
	var w := _w()
	var pad := h._field(w, "a_helipad", Vector2i(8, 6))
	var hc := h._jet(w, "a_attack_heli", pad)
	check(Air.is_landed(w.entities[hc]), "starts on its pad")
	var cell := _open_cell(w, Vector2i(30, 12))
	check(w.submit({"type": "land_at", "issuer": 0, "unit_ids": [hc], "cell": cell}).ok, "land_at accepted")
	w.step()
	check(not Air.is_landed(w.entities[hc]), "took off")
	var t := _run(w, 800, func() -> bool: return Air.is_landed(w.entities[hc]))
	check(t > 0, "landed")
	check_eq(w.cell_of(w.entities[hc].pos), cell, "on the ordered cell")
	check_eq(Air.phase(w, hc), "landed", "phase landed")
	check_eq(Airfield.service_point_at(w, 0, w.entities[hc].pos), -1, "outside any base service point")
	w.run_ticks(100)
	check_eq(w.cell_of(w.entities[hc].pos), cell, "stays put on the ground")
	check(w.submit({"type": "take_off", "issuer": 0, "unit_ids": [hc]}).ok, "take_off")
	w.step()
	check(not Air.is_landed(w.entities[hc]), "airborne again")


func _set_terrain(w: SimWorld, c: Vector2i, code: int) -> void:
	w.map.terrain[c.y * int(w.map.w) + c.x] = code


func test_helicopter_landing_rejects_water_trees_buildings() -> void:
	var w := _w()
	var d := Content.unit("a_transport_gunship")
	var open := _open_cell(w, Vector2i(20, 8))
	check(Air.landing_ok(w, open, d), "open grass is fine")
	var water := open + Vector2i(2, 0)
	var forest := open + Vector2i(0, 2)
	_set_terrain(w, water, Terrain.WATER)
	_set_terrain(w, forest, Terrain.FOREST)
	check(not Air.landing_ok(w, water, d), "no landing on water")
	check(not Air.landing_ok(w, forest, d), "no landing in trees")
	var hq := h._hq(w, 0)
	check(not Air.landing_ok(w, hq.cell as Vector2i, d), "no landing on a building")
	check(not Air.landing_ok(w, open, Content.unit("a_strike_jet")), "jets never land off-field")
	var hc := w.spawn_unit("a_transport_gunship", 0, Vector2(open) + Vector2(4.5, 4.5))
	w.step()
	check(w.preview_command({"type": "land_at", "issuer": 0, "unit_ids": [hc], "cell": water}).contains("Not enough open ground"), "land_at water refused")
	check(w.preview_command({"type": "land_at", "issuer": 0, "unit_ids": [hc], "cell": forest}).contains("Not enough open ground"), "land_at forest refused")
	check_eq(w.preview_command({"type": "land_at", "issuer": 0, "unit_ids": [hc], "cell": open}), "", "land_at open ok")
	var j := w.spawn_unit("a_strike_jet", 0, Vector2(open) + Vector2(6.5, 0.5))
	w.step()
	check(w.preview_command({"type": "land_at", "issuer": 0, "unit_ids": [j], "cell": open}).contains("Jets"), "jets refused")


func _service_ticks(with_eng: bool) -> int:
	var w := _w()
	var pad := h._field(w, "a_helipad", Vector2i(30, 6))   # away from HQ supply (G2 passive resupply)
	var hc := h._jet(w, "a_attack_heli", pad)
	if with_eng:
		var eng := w.spawn_unit("a_airfield_engineers", 0, Vector2(w.entities[pad].pos) + Vector2(0, 2))
		w.step()
		check(w.submit({"type": "assign_engineers", "issuer": 0, "unit_ids": [eng], "building_id": pad}).ok, "engineers to the pad")
		w.run_ticks(40)
	var e: Dictionary = w.entities[hc]
	e.ammo = 0
	e.fuel = 10.0
	e.hp = float(e.max_hp) * 0.6
	var t := _run(w, 1000, func() -> bool: return int(e.ammo) == int(Content.unit("a_attack_heli").ammo_max))
	check(float(e.hp) == float(e.max_hp), "repaired on the pad")
	check(float(e.fuel) == float(Content.unit("a_attack_heli").fuel_max), "refuelled on the pad")
	return t


func test_helicopter_serviced_at_pad_faster_with_engineers() -> void:
	var t0 := _service_ticks(false)
	var t1 := _service_ticks(true)
	check(t0 > 0 and t1 > 0, "serviced both ways (%d / %d)" % [t0, t1])
	check(t1 < t0, "engineers make it faster (%d < %d)" % [t1, t0])
	check(absf(float(t0) / float(t1) - 1.5) < 0.1, "50%% faster (%d / %d)" % [t0, t1])


func test_low_helicopter_returns_to_nearest_free_pad() -> void:
	var w := _w()
	var home := h._field(w, "a_helipad", Vector2i(-14, 8))
	var near := h._field(w, "a_helipad", Vector2i(30, 6))
	var hc := h._jet(w, "a_attack_heli", home)
	check_eq(int(w.entities[hc].air_home), home, "home pad")
	var goal := Vector2(w.entities[near].pos) + Vector2(4, 0)
	w.submit({"type": "move", "issuer": 0, "unit_ids": [hc], "target": goal})
	check(_run(w, 600, func() -> bool: return Vector2(w.entities[hc].pos).distance_to(goal) < 1.0) > 0, "flew out near the second pad")
	w.entities[hc].ammo = 0
	var t := _run(w, 600, func() -> bool: return Air.is_landed(w.entities[hc]))
	check(t > 0, "the low helicopter landed")
	check_eq(int(w.entities[hc].air_at), near, "at the nearest free pad, not its home")
	check(_run(w, 800, func() -> bool: return int(w.entities[hc].ammo) > 0) > 0, "and was rearmed there")


func test_save_load_mid_flight_and_mid_holding() -> void:
	var w := _w()
	var fb := h._field(w)
	var a := h._jet(w, "a_interceptor", h._hangar(w, fb))
	var b := h._jet(w, "a_strike_jet", h._hangar(w, fb))
	var pad := h._field(w, "a_helipad", Vector2i(8, 8))
	var hc := h._jet(w, "a_attack_heli", pad)
	w.submit({"type": "take_off", "issuer": 0, "unit_ids": [a]})
	_run(w, 400, func() -> bool: return Air.phase(w, a) == "air")
	w.submit({"type": "rebase", "issuer": 0, "unit_ids": [a], "building_id": fb})
	(Airfield.field(w, fb).strips[0] as Dictionary).busy_id = int(h._hq(w, 0).id)
	check(_run(w, 600, func() -> bool: return Air.phase(w, a) == "holding") > 0, "a is holding")
	(Airfield.field(w, fb).strips[0] as Dictionary).busy_id = -1
	var t := w.spawn_unit("mbt", 1, Vector2(w.entities[fb].pos) + Vector2(30, 0))
	w.submit({"type": "sortie", "issuer": 0, "unit_ids": [b], "target_id": t})
	w.submit({"type": "land_at", "issuer": 0, "unit_ids": [hc], "cell": _open_cell(w, Vector2i(26, 14))})
	w.step()
	var phases := [Air.phase(w, a), Air.phase(w, b), Air.phase(w, hc)]
	check(phases[0] == "holding" or phases[0] == "approach", "a mid-holding (%s)" % str(phases))
	check(phases[1] == "taxi", "b mid-taxi (%s)" % str(phases))
	check(phases[2] == "air", "heli mid-flight (%s)" % str(phases))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	for k in 3:
		var path := TMP_DIR + "/air_%d.sav" % k
		check_eq(SaveSystem.save(w, path), "", "save ok")
		var l: SimWorld = SaveSystem.load(path)
		check(l != null, "load ok")
		if l == null:
			return
		check_eq(l.state_hash(), w.state_hash(), "hash equal after load (%d)" % k)
		for i in 120:
			w.step()
			l.step()
		check_eq(l.state_hash(), w.state_hash(), "same future after load (%d)" % k)
		check_eq([Air.phase(l, a), Air.phase(l, b), Air.phase(l, hc)], [Air.phase(w, a), Air.phase(w, b), Air.phase(w, hc)], "phases match (%d)" % k)


## Owner note (CONTRACTS_G5 section 7): the landing zone is a clear square of lz_size around the cell.
func test_landing_zone_size_by_aircraft() -> void:
	var w := _w()
	w.factions[0].stage = 9
	var v := Content.unit("a_vtol_dropship")
	var hd := Content.unit("a_attack_heli")
	check_eq(Air.lz_size(v), 3, "VTOL needs 3x3")
	check_eq(Air.lz_size(Content.unit("b_heavy_lift")), 3, "heavy-lift needs 3x3")
	check_eq(Air.lz_size(hd), 2, "helicopter needs 2x2")
	var c := _open_cell(w, Vector2i(28, 16))
	for y in range(-3, 4):   # a 2-wide N-S gap: forest at x-1 and x+2
		_set_terrain(w, c + Vector2i(-1, y), Terrain.FOREST)
		_set_terrain(w, c + Vector2i(2, y), Terrain.FOREST)
	for x in range(-1, 3):
		for y in range(-3, 4):
			if x == 0 or x == 1:
				_set_terrain(w, c + Vector2i(x, y), Terrain.GRASS)
	check(not Air.landing_ok(w, c, v) and not Air.landing_ok(w, c + Vector2i(1, 0), v), "VTOL refused in the 2-wide gap")
	check(Air.landing_ok(w, c + Vector2i(1, 0), hd), "a helicopter fits the 2x2 clearing")
	var open := _open_cell(w, Vector2i(-20, 20))
	var ok3 := Air.landing_ok(w, open, v)
	if not ok3:
		for y in range(-1, 2):
			for x in range(-1, 2):
				_set_terrain(w, open + Vector2i(x, y), Terrain.GRASS)
		ok3 = Air.landing_ok(w, open, v)
	check(ok3, "VTOL accepted in open ground")
	var vt := w.spawn_unit("a_vtol_dropship", 0, Vector2(c) + Vector2(0.5, -6.5))
	w.step()
	var r := w.preview_command({"type": "land_at", "issuer": 0, "unit_ids": [vt], "cell": c})
	check(r.contains("Not enough open ground to land"), "land_at in the gap refused with the owner's reason (%s)" % r)
	check(w.submit({"type": "land_at", "issuer": 0, "unit_ids": [vt], "cell": open}).ok, "land_at open ground ok")
	check(_run(w, 800, func() -> bool: return Air.is_landed(w.entities[vt])) > 0, "the VTOL lands in the open")
	var hc := w.spawn_unit("a_attack_heli", 0, Vector2(c) + Vector2(1.5, -6.5))
	w.step()
	check(w.submit({"type": "land_at", "issuer": 0, "unit_ids": [hc], "cell": c + Vector2i(1, 0)}).ok, "heli land_at the clearing")
	check(_run(w, 800, func() -> bool: return Air.is_landed(w.entities[hc])) > 0, "the helicopter lands in the clearing")
	var pad := h._field(w, "a_helipad", Vector2i(8, 6))
	var hp: Dictionary = w.entities[pad]
	check_eq(w.preview_command({"type": "land_at", "issuer": 0, "unit_ids": [hc], "cell": hp.cell}), "", "a pad cell is always a valid land_at")
