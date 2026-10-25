extends "res://tests/test_base.gd"
## G5 acceptance (owner: AI6). CONTRACTS_G5 sections 9-11: the AI uses Drone Teams by target type,
## puts a logistics truck on auto-resupply behind its army, evacuates with medics / ambulances to a
## hospital it builds, fields the new ground units, and thinks in < 2 ms per side at 5k units.

const AiCtl = preload("res://sim/ai/ai_controller.gd")
const G5 = preload("res://sim/ai/ai_g5.gd")
const U = preload("res://sim/ai/ai_util.gd")
const Support = preload("res://sim/systems/support.gd")
const Medical = preload("res://sim/systems/medical.gd")
const Bench = preload("res://sim/ai/tools/ai_bench.gd")
const MatchCfg = preload("res://sim/ai/tools/match_cfg.gd")

const FIELD_TICKS := 24000
const BENCH_UNITS := 5000
const BENCH_TICKS := 600


## Side 1 is an AI (stage 9) whose own think is parked, so only the module under test acts.
func _world(fac1: String = "human_a", fac0: String = "human_a") -> SimWorld:
	var c := SimWorld.default_config()
	c.seed = 1
	c.sides[0].faction = fac0
	c.sides[1].faction = fac1
	for s in c.sides:
		s.stage = 9
	var w := SimWorld.new_match(c)
	w.ai_state[1].next_think_tick = 1 << 30
	return w


## A point `d` tiles from side fid's spawn toward the map centre.
func _out(w: SimWorld, fid: int, d: float) -> Vector2:
	var s := Vector2(w.factions[fid].spawn) + Vector2(0.5, 0.5)
	return s + (U.map_center(w) - s).normalized() * d


func _ctx(w: SimWorld, st: Dictionary) -> Dictionary:
	var ctx := AiCtl._context(w, 1, st)
	ctx.visible = w.visible_enemies(1)
	return ctx


func test_ai_uses_drone_team_by_target_type() -> void:
	var w := _world()
	var team_def := U.role_unit(w, 1, "drone_team")
	if not check(team_def != "", "human_a has a drone_team role"):
		return
	var p := _out(w, 1, 16.0)
	var team: Dictionary = w.entities[w.spawn_unit(team_def, 1, p)]
	var tank: Dictionary = w.entities[w.spawn_unit(U.role_unit(w, 0, "heavy"), 0, p + Vector2(6, 0))]
	check_eq(String(G5.drone_target(team, [tank]).get("drone", "")), "strike", "armour -> strike")
	var inf := []
	for i in 4:
		inf.append(w.entities[w.spawn_unit(U.role_unit(w, 0, "infantry"), 0, p + Vector2(5, 0.5 * i))])
	check_eq(String(G5.drone_target(team, inf).get("drone", "")), "frag", "infantry cluster -> frag")
	check(G5.drone_target(team, [inf[0]]).is_empty(), "a lone rifleman is not worth a drone")
	var crawler: Dictionary = w.entities[w.spawn_unit(Content.role("machine", "infantry"), 0, p + Vector2(4, -3))]
	check_eq(String(G5.drone_target(team, [crawler]).get("drone", "")), "emp", "machine -> emp")
	var far: Dictionary = w.entities[w.spawn_unit(U.role_unit(w, 0, "heavy"), 0, p + Vector2(60, 0))]
	check(G5.drone_target(team, [far]).is_empty(), "nothing beyond drone range")
	# end to end: the AI launches a strike drone at the tank through the launch_drone command
	var w2 := _world()
	var q := _out(w2, 1, 16.0)
	var tid := w2.spawn_unit(team_def, 1, q)
	w2.spawn_unit(U.role_unit(w2, 0, "heavy"), 0, q + Vector2(5, 0))
	w2.step()
	var st: Dictionary = w2.ai_state[1]
	var ctx := _ctx(w2, st)
	G5.manage_drones(w2, 1, st, ctx)
	w2.step()
	var g: Dictionary = G5.g6(st)
	print("    drone team #%d charges=%d mode=%s drones=%s last=%s" % [tid, G5.charges(w2.entities[tid]), G5.mode(w2.entities[tid]),
		str(g.drones), String(st.get("last_result", ""))])
	check(int(g.drones.strike) >= 1, "AI launched a strike drone at the tank (%s, %s)" % [str(g.drones), String(st.get("last_result", ""))])
	check(G5.charges(w2.entities[tid]) < int(Content.unit(team_def).drone_charges), "the launch spent a charge")


func test_ai_puts_truck_on_auto_behind_army() -> void:
	var w := _world()
	var truck_def := U.role_unit(w, 1, "supply")
	var home := _out(w, 1, 0.0)
	var front := _out(w, 1, 40.0)
	var ids := []
	for i in 6:
		ids.append(w.spawn_unit(U.role_unit(w, 1, "infantry"), 1, front + Vector2(0.6 * i, 0)))
	var tr := w.spawn_unit(truck_def, 1, _out(w, 1, 20.0))
	var st: Dictionary = w.ai_state[1]
	st.objective = "attack"
	st.attack_target = _out(w, 1, 90.0)
	st.attack_group = ids
	var ctx := _ctx(w, st)
	G5.manage_support(w, 1, st, ctx)
	w.step()
	var ts := Support.truck_state(w, tr)
	check_eq(String(ts.get("mode", "")), "roam", "the truck roams on auto-resupply (%s)" % String(st.get("last_result", "")))
	if ts.is_empty():
		return
	var cen := Vector2.ZERO
	for id in ids:
		cen += Vector2(w.entities[id].pos)
	cen /= float(ids.size())
	var c := Vector2(float(ts.center[0]), float(ts.center[1]))
	check(c.distance_to(cen) <= G5.TRUCK_BEHIND + 2.5, "truck area centred near the army (%s vs %s)" % [str(c), str(cen)])
	check(c.distance_to(home) < cen.distance_to(home), "truck area is behind the army, toward home")
	check(G5.auto_on(st, w.entities[tr]), "logistics leaves an auto truck to Support")


func test_ai_uses_medics_and_hospitals() -> void:
	var w := _world()
	var front := _out(w, 1, 30.0)
	var ids := []
	for i in 10:
		ids.append(w.spawn_unit(U.role_unit(w, 1, "infantry"), 1, front + Vector2(0.6 * (i % 5), float(i / 5))))
	var med := w.spawn_unit(U.role_unit(w, 1, "medic"), 1, front - Vector2(2, 0))
	var amb := w.spawn_unit(U.role_unit(w, 1, "ambulance"), 1, front - Vector2(4, 0))
	var st: Dictionary = w.ai_state[1]
	st.objective = "attack"
	st.attack_target = _out(w, 1, 90.0)
	st.attack_group = ids + [med]
	var ctx := _ctx(w, st)
	G5.manage_medical(w, 1, st, ctx)
	w.step()
	var ev: Dictionary = w.sys_state.get("medical", {}).get("evac", {})
	check(ev.has(med) and ev.has(amb), "medic team and ambulance on auto-evac (%s, %s)" % [str(ev.keys()), String(st.get("last_result", ""))])
	var left := true
	for e in ctx.army:
		if int(e.id) == med or int(e.id) == amb:
			left = false
	check(left, "evac units leave the combat army")
	# the hospital at home
	w.tick = G5.HOSP_FROM_TICK + 1
	w.factions[1].credits = 6000
	for k in ["salvage", "ore"]:
		w.factions[1].stock[k] = 3000
	st.think_count = 4
	ctx = _ctx(w, st)
	G5.manage_hospital(w, 1, st, ctx)
	w.step()
	var hosp := ""
	for b in w.buildings_of(1):
		if bool(Content.building(String(b.def)).get("hospital", false)) or bool(Content.building(String(b.def)).get("field_hospital", false)):
			hosp = String(b.def)
	check(hosp != "", "AI started a hospital at home (%s, %s)" % [str(G5.hospital_defs(w, 1)), String(st.get("last_result", ""))])


func test_ai_fields_new_ground_units() -> void:
	var c := SimWorld.default_config()
	c.seed = 2
	c.ai_difficulty = "normal"
	c.sides[0].ai = true
	c.sides[1].faction = "human_b"
	for s in c.sides:
		s.stage = 9
	var w := SimWorld.new_match(c)
	while w.tick < FIELD_TICKS and not w.match_state.ended:
		w.step()
	for fid in [0, 1]:
		var g: Dictionary = w.ai_state[fid].get("g6", {})
		print("    G5 f%d t=%d %s" % [fid, w.tick, String(g.get("probe", ""))])
		check(not (g.get("queued", {}) as Dictionary).is_empty(), "side %d queued G5 ground units" % fid)
		var fielded := 0
		for d in g.get("fielded", {}):
			fielded += int(g.fielded[d])
		check(fielded >= 1, "side %d fielded G5 ground units (%s)" % [fid, str(g.get("fielded", {}))])


func test_ai_bench_under_2ms_per_side_5k() -> void:
	var c := MatchCfg.from_args(["--map=valley_conquest_l"], 1)
	var w := SimWorld.new_match(c)
	Bench._fill(w, 0, BENCH_UNITS)
	Bench._fill(w, 1, 300)
	var tot := {}
	var n := {}
	for i in BENCH_TICKS:
		var st := w.ai_state
		w.ai_state = {}
		w.step()
		w.ai_state = st
		for fid in st:
			if not w.factions[fid].alive:
				continue
			var t := Time.get_ticks_usec()
			AiCtl.think(w, fid)
			tot[fid] = int(tot.get(fid, 0)) + Time.get_ticks_usec() - t
			n[fid] = int(n.get(fid, 0)) + 1
	for fid in tot:
		var avg := float(tot[fid]) / 1000.0 / maxf(1.0, float(n[fid]))
		print("    bench f%d units=%d avg_ms=%.3f (cpu load not controlled; ORCH re-measures on a quiet PC)" % [fid, w.units_of(fid).size(), avg])
		check(avg < 2.0, "AI think avg %.3f ms < 2 ms per side (f%d, %d units)" % [avg, fid, w.units_of(fid).size()])
