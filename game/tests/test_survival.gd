extends "res://tests/test_base.gd"
## G6 survival (owner: MODES6). CONTRACTS_G6 section 15, section 17: survive / repel_waves victory types,
## the wave spawner (90 s cadence, escalation, company templates, edge spawns) and the two stronghold maps.

const Waves = preload("res://sim/systems/waves.gd")
const Victory = preload("res://sim/systems/victory.gd")
const Companies = preload("res://sim/systems/companies.gd")
const MapGen = preload("res://sim/map_gen.gd")
const MapCheck = preload("res://sim/maps/map_check.gd")
const RidgeBastion = preload("res://sim/maps/ridge_bastion.gd")
const RiverDam = preload("res://sim/maps/river_dam.gd")
const SaveSystem = preload("res://sim/save_system.gd")


## Survival config on map_id; the attacker (side 1) stays inert (no AI controller): these tests drive
## the spawner and the victory terms, not the wave AI.
func _cfg(kind: String, amount: int, map_id: String = "river_crossing_s") -> Dictionary:
	var c := Waves.survival_config(SimWorld.default_config(), kind, amount)
	c.map = map_id
	c.sides[1].ai = false
	return c


func _run(w: SimWorld, n: int) -> void:
	for i in n:
		if bool(w.match_state.ended):
			return
		w.step()


func _elements(plan: Array) -> int:
	var n := 0
	for p in plan:
		n += (p.items as Array).size()
	return n


func test_survive_seconds_defender_wins() -> void:
	# a G4 scenario "survive" without cfg.survival keeps its old meaning: no waves, no state
	var g4 := make_world({"victory": "survive", "victory_params": {"seconds": 60}})
	check(not Waves.active(g4), "plain survive is not a wave match")
	_run(g4, 40)
	check(not g4.sys_state.has("waves"), "no wave state without cfg.survival")
	var c := _cfg("survive", 100)
	check_eq(SimWorld.validate_config(c), "", "survival config validates")
	var w := SimWorld.new_match(c)
	if not check(w != null, "survival match created"):
		return
	check(Waves.active(w) and Waves.attacker(w) == 1, "attacker is side 1")
	check_eq(Waves.defenders(w), [0], "defenders")
	w.step()
	check(w.units_of(1).is_empty() and w.buildings_of(1).is_empty(), "attacker start package removed")
	_run(w, 100 * SimWorld.TICK_RATE - 2)
	check(not bool(w.match_state.ended), "not over before 100 s (tick %d)" % w.tick)
	check(bool(w.factions[1].alive), "the baseless attacker is never eliminated")
	check(int(w.sys_state.waves.spawned) >= 1, "wave 1 spawned at 90 s")
	_run(w, 40)
	check(bool(w.match_state.ended), "ended at 100 s")
	check_eq(int(w.match_state.winner_team), 0, "defender team wins")
	check_eq(String(w.match_state.reason), "survive", "reason survive")
	check_eq(int(w.match_state.end_tick), 100 * SimWorld.TICK_RATE, "won exactly at 100 s")
	# overrun: every defender HQ lost -> the attacker team wins
	var w2 := SimWorld.new_match(_cfg("survive", 600))
	w2.step()
	for b in w2.buildings_of(0):
		w2.destroy(int(b.id), "test")
	_run(w2, 5)
	check(bool(w2.match_state.ended), "overrun ends the match")
	check_eq(int(w2.match_state.winner_team), int(w2.factions[1].team), "attacker team wins on overrun")
	check_eq(String(w2.match_state.reason), "overrun", "reason overrun")


func test_repel_waves_count_defender_wins() -> void:
	var c := _cfg("repel_waves", 2)
	check_eq(SimWorld.validate_config(c), "", "repel config validates")
	check(SimWorld.validate_config(_cfg("repel_waves", 0)) != "", "count 0 rejected")
	var same := _cfg("repel_waves", 2)
	same.sides[1].team = 0
	check(SimWorld.validate_config(same) != "", "attacker sharing the defender team rejected")
	var w := SimWorld.new_match(c)
	if not check(w != null, "repel match created"):
		return
	w.step()
	check_eq(Waves.total_waves(w), 2, "two waves")
	for k in 2:
		var st: Dictionary = w.sys_state.waves
		st.next_tick = w.tick + 1   # fast-forward the clock to the next wave
		_run(w, 2)
		check_eq(int(st.spawned), k + 1, "wave %d spawned" % (k + 1))
		var ids := Waves.wave_units(w, k + 1)
		check(ids.size() > 0, "wave %d has units" % (k + 1))
		check(not bool(w.match_state.ended), "not won while wave %d lives" % (k + 1))
		for uid in ids:
			w.destroy(int(uid), "test", 0)
		_run(w, 21)
		check_eq(Waves.destroyed_count(w), k + 1, "wave %d destroyed" % (k + 1))
	check(bool(w.match_state.ended), "defender wins after 2 waves are destroyed")
	check_eq(int(w.match_state.winner_team), 0, "defender team wins")
	check_eq(String(w.match_state.reason), "repel_waves", "reason repel_waves")
	check(bool(Waves.next_wave(w).done), "no third wave")
	var p := Victory.progress(w, 0)
	check_eq(int(p.terms[0].value), 2, "progress: 2 destroyed")
	check_eq(int(p.terms[0].target), 2, "progress: target 2")


func test_waves_escalate_every_90s() -> void:
	var r: Dictionary = Content.rules().g6_survival
	var old = r.get("fallback_orders", true)
	r["fallback_orders"] = false   # waves wait at the edge: this test measures the schedule only
	var w := SimWorld.new_match(_cfg("survive", 3600))
	var spawned := []
	var warned := 0
	for i in 3601:
		w.step()
		for ev in w.events:
			if String(ev.type) == "WaveSpawned":
				spawned.append(ev)
			elif String(ev.type) == "WaveIncoming":
				warned += 1
	r["fallback_orders"] = old
	check_eq(spawned.size(), 2, "two waves in 180 s")
	check_eq(warned, 2, "a warning before each wave")
	if spawned.size() == 2:
		var t1 := int(w.sys_state.waves.waves[0].tick)
		var t2 := int(w.sys_state.waves.waves[1].tick)
		check_eq(t1, 90 * SimWorld.TICK_RATE, "wave 1 at 90 s")
		check_eq(t2 - t1, 90 * SimWorld.TICK_RATE, "90 s between waves")
		check(int(spawned[1].size) >= int(spawned[0].size), "wave 2 not smaller than wave 1")
		var avail := Companies.templates_for(1, w)
		for ev in spawned:
			check(not (ev.company_ids as Array).is_empty(), "wave %d is made of companies" % int(ev.index))
			for cid in ev.company_ids:
				var co: Dictionary = Companies.state(w).companies.get(int(cid), {})
				check(avail.has(String(co.get("template", ""))), "company template %s belongs to the attacker" % str(co.get("template")))
			for uid in ev.unit_ids:
				var e = w.entities.get(int(uid))
				if e != null:
					check(int(e.owner) == 1 and e.has("company"), "wave unit %d is an attacker company member" % int(uid))
	var n1 := _elements(Waves.wave_plan(w, 1))
	var n5 := _elements(Waves.wave_plan(w, 5))
	var n11 := _elements(Waves.wave_plan(w, 11))
	check(n1 > 0 and n1 < n5 and n5 < n11, "escalation grows (%d < %d < %d elements)" % [n1, n5, n11])
	check(Waves.wave_plan(w, 1).size() == 1 and Waves.wave_plan(w, 11).size() >= 3, "later tiers add company roles")
	# dynamic: a second defending side scales the waves up
	var c3 := SimWorld.default_config()
	c3.sides.append({"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "Ally", "team": 0})
	c3 = Waves.survival_config(c3, "survive", 600, 1)
	c3.sides[1].ai = false
	var w3 := SimWorld.new_match(c3)
	if check(w3 != null, "3-side survival match"):
		check_eq(Waves.defenders(w3), [0, 2], "two defenders")
		check(Waves.dynamic_mult(w3) > Waves.dynamic_mult(w), "two defenders -> bigger waves (%.2f > %.2f)" % [Waves.dynamic_mult(w3), Waves.dynamic_mult(w)])


func test_edge_spawns_on_any_map() -> void:
	var inset := int(Waves.rules().get("spawn_edge_inset", 2))
	for mid in ["river_crossing_s", "industrial_heartland_m", "valley_conquest_l", "coastal_front_m"]:
		if not MapGen.has_map(mid):
			continue
		var w := SimWorld.new_match(_cfg("repel_waves", 3, mid))
		if not check(w != null, "%s: survival match" % mid):
			continue
		w.step()
		var sp: Array = w.sys_state.waves.spawns
		check(sp.size() >= 2, "%s: edge spawn points (%d)" % [mid, sp.size()])
		var mw := int(w.map.w)
		var mh := int(w.map.h)
		var pm := MapCheck.passmask(w.map.terrain, "vehicle")
		var lay := MapCheck.layers(w.map)
		var home: Vector2i = w.factions[0].spawn
		var dist := MapCheck.bfs(pm, mw, mh, Waves._open_cell(pm, mw, mh, home), lay[0], lay[1])
		var mind := float(Waves.rules().get("spawn_min_dist_frac", 0.3)) * Vector2(mw, mh).length()
		for cv in sp:
			var c: Vector2i = cv
			check(c.x == inset or c.y == inset or c.x == mw - 1 - inset or c.y == mh - 1 - inset, "%s: %s on the map edge" % [mid, c])
			check(dist[c.y * mw + c.x] >= 0, "%s: %s reachable by vehicle from the defender" % [mid, c])
			check(Vector2(c - home).length() >= mind, "%s: %s far from the defender" % [mid, c])
		w.sys_state.waves.next_tick = w.tick + 1
		_run(w, 2)
		var wv: Array = Waves.waves_of(w)
		check(wv.size() == 1 and sp.has(wv[0].cell) and not Waves.wave_units(w, 1).is_empty(), "%s: wave 1 spawned at an edge point" % mid)


## Wave state is saved and hashed; same seed + commands = same hash; a load continues identically.
func test_survival_save_and_determinism() -> void:
	var a := SimWorld.new_match(_cfg("repel_waves", 5))
	var b := SimWorld.new_match(_cfg("repel_waves", 5))
	for w in [a, b]:
		w.step()
		w.sys_state.waves.next_tick = w.tick + 1
		w.run_ticks(120)
	check(int(a.sys_state.waves.spawned) == 1 and not Waves.wave_units(a, 1).is_empty(), "wave 1 in the field")
	check_eq(a.state_hash(), b.state_hash(), "same seed -> same hash with waves")
	var res := SaveSystem.decode_bytes(SaveSystem.encode_dict(a.to_dict(), "test"))
	check(bool(res.ok), "decode ok: %s" % res.get("reason", ""))
	var c := SimWorld.from_dict(res.dict)
	check_eq(c.state_hash(), a.state_hash(), "hash equal after load")
	check(Waves.active(c) and Waves.attacker(c) == 1, "survival still active after load")
	a.run_ticks(300)
	c.run_ticks(300)
	check_eq(c.state_hash(), a.state_hash(), "identical after 300 more ticks")
	check_eq(Waves.next_wave(c), Waves.next_wave(a), "same next wave after load")


## Same attempt loop as MapGen.generate (12 re-rolls); returns the first valid variant (or the last try).
func _gen(mod, sd: int) -> Dictionary:
	var m: Dictionary = {}
	for attempt in 12:
		m = mod.try_gen(sd, attempt)
		if mod.validate(m) == "":
			return m
	return m


func test_ridge_bastion_and_river_dam_validate() -> void:
	for mod in [RidgeBastion, RiverDam]:
		for sd in [1, 2, 7]:
			var m: Dictionary = _gen(mod, sd)
			check_eq(mod.validate(m), "", "%s seed %d validates" % [mod.ID, sd])
			if not m.has("terrain"):
				continue
			check(m.has("height") and m.has("ramps"), "%s: authored height" % mod.ID)
			var hv := MapGen.validate_height(m)
			check(hv.is_empty(), "%s: height valid %s" % [mod.ID, str(hv)])
			check((m.get("wave_spawns", []) as Array).size() >= 2, "%s: wave spawns" % mod.ID)
		var m1: Dictionary = mod.try_gen(1, 0)
		check(m1.get("terrain") == mod.try_gen(1, 0).get("terrain") and m1.get("height") == mod.try_gen(1, 0).get("height"), "%s: deterministic" % mod.ID)
		if MapGen.has_map(mod.ID):   # registered by ORCH (map.survival_ready)
			var w := SimWorld.new_match(_cfg("survive", 600, mod.ID))
			if check(w != null, "%s: survival match" % mod.ID):
				w.step()
				check_eq((w.sys_state.waves.spawns as Array).size(), (w.map.wave_spawns as Array).size(), "%s: map wave spawns used" % mod.ID)
	var rd: Dictionary = RiverDam.try_gen(1, 0)
	check((rd.get("bridges", []) as Array).size() >= 2 and not (rd.get("dam_cells", []) as Array).is_empty(), "River Dam: a dam and bridges")
	var rb: Dictionary = RidgeBastion.try_gen(1, 0)
	check_eq(int(rb.get("bastion_ramps", 0)), 2, "Ridge Bastion: 2 ramps onto the walled ridge")
	check_eq(int(rb.get("lanes", 0)), 4, "Ridge Bastion: 4 attack lanes")
