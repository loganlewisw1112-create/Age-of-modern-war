extends "res://tests/test_base.gd"
## G7.1 C1/C2: dread meter, breaths, face split, one-shot breaking-point. Phase clock untouched.

const Director71 = preload("res://sim/systems/director71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const LpHud = preload("res://presentation/ui7/lp_hud.gd")
const Radio71 = preload("res://sim/systems/radio71.gd")


func test_pressure_is_pure_and_ordered() -> void:
	check(not Director71.rules().is_empty(), "rules.g71_director loaded")
	check_eq(Director71.pressure(0.0, 0, 0.0, 0), 0.0, "a fresh run is 0")
	var mid := Director71.pressure(0.5, 0, 0.0, 0)
	var late := Director71.pressure(1.0, 0, 0.0, 0)
	check(late > mid and mid > 0.0, "time raises dread (%.3f then %.3f)" % [mid, late])
	check(Director71.pressure(0.2, 1, 0.0, 0) > Director71.pressure(0.2, 0, 0.0, 0), "a fallen ring raises dread")
	check(Director71.pressure(0.2, 0, 0.8, 0) > Director71.pressure(0.2, 0, 0.1, 0), "creep raises dread")
	check(Director71.pressure(0.2, 0, 0.0, 4) > Director71.pressure(0.2, 0, 0.0, 0), "losses raise dread")
	check(Director71.pressure(5.0, 9, 5.0, 99) <= 1.0, "dread stays at most 1")
	check_eq(Director71.band(0.1), "probe", "early band")
	check_eq(Director71.band(0.5), "mixed", "middle band")
	check_eq(Director71.band(0.9), "siege", "peak band")
	check(Director71.interval_s(30.0, 0.0) > Director71.interval_s(30.0, 1.0), "early breaths are longer than the peak")
	check_eq(Director71.interval_s(30.0, 1.0), 30.0, "at full dread the gap is the written base")


func test_pick_push_and_breaking_point() -> void:
	var quiet := [0, 0, 0, 0, 0, 0, 0, 0]
	var q: Dictionary = Director71.pick_push(quiet)
	check_eq(int(q.main), 0, "quiet board: main is sector 0")
	check_eq(int(q.feint), 4, "quiet board: feint is opposite")
	var busy := [1, 0, 9, 0, 0, 2, 0, 0]
	var p: Dictionary = Director71.pick_push(busy)
	check_eq(int(p.main), 2, "main is the busiest sector")
	check_eq(int(p.feint), 5, "feint prefers a live face when the opposite is empty")
	var both := [0, 0, 2, 0, 0, 0, 8, 0]
	var b: Dictionary = Director71.pick_push(both)
	check_eq(int(b.main), 6, "main tracks the peak")
	check_eq(int(b.feint), 2, "feint stays opposite when that face has presence")
	check(float(p.feint_frac) > 0.0 and float(p.feint_frac) < 1.0, "feint_frac is a fraction")
	var s := {}
	check(not Director71.note_breaking(s, 0.4), "mixed band is not the climax")
	check(not bool(s.get("break_point", false)), "flag stays clear before siege")
	check(Director71.note_breaking(s, 0.9), "first siege crossing fires once")
	check(bool(s.break_point), "flag sticks")
	check(not Director71.note_breaking(s, 1.0), "second call is quiet")


func test_logistics_and_regrow_rules() -> void:
	check(not Director71.logistics_ready(0.2), "early dread skips logistics peels")
	check(Director71.logistics_ready(0.9), "late dread opens logistics peels")
	check(Director71.is_logistics_def("generator"), "generators are logistics targets")
	check(Director71.is_logistics_def("a_radar_station"), "radar is a logistics target")
	check(not Director71.is_logistics_def("wall"), "plain walls are not logistics")
	var logs: Array = Director71.pick_logistics([
		{"id": 3, "def": "generator", "pos": Vector2(1, 1), "built": true, "hp": 10},
		{"id": 1, "def": "wall", "pos": Vector2(2, 2), "built": true, "hp": 10},
		{"id": 2, "def": "depot", "pos": Vector2(3, 3), "built": true, "hp": 10},
	])
	check_eq(logs.size(), 2, "pick_logistics keeps only rear targets")
	check_eq(int(logs[0].id), 2, "logistics list is sorted by id")
	check(Director71.needs_retreat(0.2), "low hp wants to retreat")
	check(not Director71.needs_retreat(0.9), "healthy machines stay in the fight")
	check(Director71.ready_return(0.85), "healed machines return")
	check(not Director71.ready_return(0.4), "half-healed machines stay at the spawn")
	check(is_equal_approx(Director71.hp_frac({"hp": 50, "hp_max": 100}), 0.5), "hp_frac is hp / max")


func test_siege_roster_stubs() -> void:
	for id in ["g71_m_brute", "g71_m_siege_walker", "g71_m_turret_eater", "g71_m_sapper",
			"g71_m_reclaimer", "g71_m_hive_conductor", "g71_m_glass_stalker"]:
		check(not Content.unit(id).is_empty(), "%s def loads" % id)
	check_eq(String(Content.unit("g71_m_brute").get("g71_siege", "")), "brute", "brute is tagged")
	check_eq(String(Content.unit("g71_m_siege_walker").get("g71_siege", "")), "walker", "walker is tagged")
	check_eq(String(Content.unit("g71_m_turret_eater").get("g71_siege", "")), "turret_eater", "turret-eater is tagged")
	check_eq(String(Content.unit("g71_m_sapper").get("g71_siege", "")), "sapper", "sapper is tagged")
	check_eq(String(Content.unit("g71_m_sapper").get("t7", "")), "burrower", "sapper reuses burrower tunnel AI")
	check_eq(String(Content.unit("g71_m_reclaimer").get("g71_special", "")), "reclaimer", "reclaimer is tagged")
	check_eq(String(Content.unit("g71_m_hive_conductor").get("g71_special", "")), "hive_conductor", "hive Conductor is tagged")
	check_eq(String(Content.unit("g71_m_glass_stalker").get("g71_special", "")), "glass_stalker", "glass stalker is tagged")
	check(bool(Content.unit("g71_m_glass_stalker").get("stealth", {}).get("thermal_visible", false)), "stalkers show on thermal")
	check(String(Content.unit("g71_m_glass_stalker").get("g71_special", "")) == "glass_stalker", "glass stalker special tag")
	check(Director71.siege_roster(0.1).is_empty(), "probe dread spawns no siege stubs")
	check_eq(Director71.siege_roster(0.5).size(), 4, "mixed dread brings brute + eaters + stalker")
	check_eq(Director71.siege_roster(0.9).size(), 10, "siege dread brings C3 + C4 stubs")
	check_eq(Director71.siege_roster(0.9, "armour").size(), 11, "an armour counter adds another brute")
	check_eq(String(Director71.siege_roster(0.9, "armour").back()), "g71_m_brute", "armour bonus is a brute")
	check(Director71.overmind_line("breaking_point") != "", "Overmind has a breaking-point line")
	check(Director71.overmind_line("adapt_armour") != "", "Overmind has an armour-counter line")
	check(Director71.is_hive_conductor("g71_m_hive_conductor"), "hive Conductor id is recognized")
	check(not Director71.is_hive_conductor("g71_m_brute"), "brutes are not the hive Conductor")
	check(Director71.sync_radius() > 0.0, "sync aura has a radius")
	check(float(Director71.rules().get("sync_damage", 0.0)) > 1.0, "synced Machines hit harder")
	check(Director71.is_reclaimer("g71_m_reclaimer"), "reclaimer id is recognized")
	check(Director71.reclaim_radius() > 0.0, "reclaim reach is set")
	check(not Content.unit(Director71.reclaim_print()).is_empty(), "reclaim print def loads")
	check(float(Director71.rules().get("wreck_cover_r", 0.0)) > 0.0, "wreck cover radius is set")
	check(Director71.siege_kind("g71_m_turret_eater") == "turret_eater", "turret-eater kind")
	check(Director71.siege_kind("g71_m_sapper") == "sapper", "sapper kind")
	check(Director71.latch_radius() > 0.0 and Director71.jam_radius() > 0.0, "latch/jam radii set")
	check(Director71.pile_min() >= 2, "body piles need a cluster")
	var fc := Director71.forecast(0.9, "armour", 2)
	check(fc != "" and fc.find("brute") >= 0, "forecast names the next wave (%s)" % fc)
	check(fc.find("N") >= 0 or fc.find("face") >= 0, "forecast names a face")
	Radio71._lines = null  # pick up lines71_lp.json
	check(not Radio71.line("lp71.breaking_point").is_empty(), "LP breaking-point radio line loads")
	check(not Radio71.line("lp71.forecast").is_empty(), "LP forecast radio line loads")
	var RF = load("res://presentation/ui71/radio_feed.gd")
	var feed = RF.new()
	feed.setup(0)
	feed.handle_events([{"type": "LpBreakingPoint", "dread": 0.9, "pos": Vector2(1, 1)}], null)
	feed.tick(0.1)
	check(String(feed.text).find("Breaking point") >= 0, "radio feed speaks the breaking point")
	feed.free()


func test_adapt_buckets_and_counter() -> void:
	check_eq(Director71.kill_bucket("mg"), "armour", "MGs push armour")
	check_eq(Director71.kill_bucket("laser"), "smoke", "lasers push smoke / dispersal")
	check_eq(Director71.kill_bucket("", "anti_drone_pod"), "emp", "drone weapons push EMP")
	check_eq(Director71.kill_bucket("missile"), "disperse", "missiles push disperse")
	var s := {"adapt": {}}
	check_eq(Director71.counter_for(s), "", "no deaths yet")
	Director71.note_kill(s, "mg")
	Director71.note_kill(s, "mg")
	Director71.note_kill(s, "laser")
	check_eq(Director71.counter_for(s), "armour", "the hive counters what killed it most")
	Director71.note_kill(s, "laser")
	Director71.note_kill(s, "laser")
	check_eq(Director71.counter_for(s), "smoke", "a new peak flips the counter")


func test_live_meter_does_not_move_the_phase() -> void:
	var c := LastProtocol.make_config(77, "industrial_heartland_m")
	var a := SimWorld.new_match(c)
	var b := SimWorld.new_match(c)
	if not check(a != null and b != null, "two Last Protocol matches start"):
		return
	for i in 40:
		a.step()
		b.step()
	check_eq(a.state_hash(), b.state_hash(), "two runs share a hash with the meter on")
	var s: Dictionary = a.sys_state.lp
	check(s.has("dread"), "the match stores dread")
	check(float(s.dread) >= 0.0 and float(s.dread) <= 1.0, "dread is in range (%.3f)" % float(s.dread))
	check_eq(int(s.phase), 0, "40 ticks do not advance the phase (still %d)" % int(s.phase))
	var h: Dictionary = LastProtocol.hud(a)
	check(h.has("dread") and String(h.band) == Director71.band(float(h.dread)), "the HUD shows the same band")
	check(h.has("break_point"), "HUD exposes the breaking-point flag")
	check(h.has("objectives") and h.has("intel_n"), "HUD exposes objectives and intel count")
	LastProtocol._push_objective(a, a.sys_state.lp, "hold_fallback", "Hold the fallback", {"ring": 0})
	check((LastProtocol.hud(a).objectives as Array).size() == 1, "an open objective shows on the HUD")
	LastProtocol._complete_objective(a, a.sys_state.lp, "hold_fallback", {"ring": 0})
	check((LastProtocol.hud(a).objectives as Array).is_empty(), "completed objectives leave the HUD")
	# Done-when style: save / load keeps director fields and the same future.
	a.sys_state.lp.dread = 0.91
	a.sys_state.lp.break_point = true
	a.sys_state.lp.adapt = {"armour": 3, "smoke": 1}
	a.sys_state.lp.forecast = "3x brute, N face, ~30s"
	LastProtocol._note_intel(a, a.sys_state.lp, "g71_m_brute", "armour")
	var loaded := SimWorld.from_dict(a.to_dict().duplicate(true))
	var lp: Dictionary = loaded.sys_state.lp
	check(is_equal_approx(float(lp.dread), 0.91), "save keeps dread")
	check(bool(lp.break_point), "save keeps breaking-point")
	check_eq(int(lp.adapt.armour), 3, "save keeps adapt buckets")
	check_eq(String(lp.forecast), "3x brute, N face, ~30s", "save keeps forecast")
	check((lp.intel as Dictionary).has("g71_m_brute"), "save keeps intel codex")
	for i in 40:
		a.step()
		loaded.step()
	check_eq(a.state_hash(), loaded.state_hash(), "save / load mid-siege keeps the same future")
	var shown: Dictionary = LpHud.lines({
		"phase": 0, "posture": "normal", "creep": 0.1, "critical": 0.62, "win_below": 0.12,
		"cd_left": 1000.0, "cd_rate": 1.0, "cores_alive": 3, "cores_total": 3, "walker": false,
		"tide": false, "final_stage": false, "weavers": false, "raid": false, "rings_fallen": 0,
		"dread": 0.9, "band": "siege", "break_point": true, "counter": "armour", "ended": false, "result": {},
	})
	check(String(shown.dread).find("BREAKING POINT") >= 0, "HUD text shows the breaking point")
	check(String(shown.dread).find("armour") >= 0, "HUD text shows the hive counter")


func test_hunt_ops() -> void:
	check(float(Director71.rules().get("hunt_at", 0.0)) > 0.0, "hunt ops open mid-siege")
	Radio71._lines = null
	check(not Radio71.line("lp71.hunt").is_empty(), "hunt radio line loads")
	var c := LastProtocol.make_config(77, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "Last Protocol match starts for hunts"):
		return
	for i in 15:
		w.step()
	var s: Dictionary = w.sys_state.lp
	s.dread = 0.7
	var pos: Vector2 = Vector2(s.base.center) + Vector2(20, 0)
	var cid := w.spawn_unit("g71_m_hive_conductor", int(s.mfid), pos)
	var rid := w.spawn_unit("g71_m_reclaimer", int(s.mfid), pos + Vector2(2, 0))
	check(cid >= 0 and rid >= 0, "Conductor and Reclaimer spawn for hunt stubs")
	LastProtocol._hunt_ops(w, s)
	var kinds := {}
	for o in LastProtocol.hud(w).objectives:
		kinds[String(o.kind)] = true
	check(bool(kinds.get("hunt_conductor", false)), "Conductor hunt objective opens")
	check(bool(kinds.get("hunt_reclaimer", false)), "Reclaimer hunt objective opens")
	LastProtocol._complete_objective(w, s, "hunt_conductor", {})
	var left := false
	for o2 in LastProtocol.hud(w).objectives:
		if String(o2.kind) == "hunt_conductor":
			left = true
	check(not left, "Conductor kill clears the hunt")
	var RF = load("res://presentation/ui71/radio_feed.gd")
	var feed = RF.new()
	feed.setup(0)
	feed.handle_events([{"type": "LpHunt", "kind": "conductor", "pos": Vector2(1, 1)}], null)
	feed.tick(0.1)
	check(String(feed.text).find("Hollow") >= 0 or String(feed.text).to_lower().find("target") >= 0,
		"radio speaks the hunt")
	feed.free()


func test_scuttle_and_core_raid() -> void:
	check(float(Director71.rules().get("scuttle_delay_s", 0.0)) > 0.0, "scuttle delay is set")
	check(float(Director71.rules().get("core_raid_at", 0.0)) > 0.5, "core raid opens late")
	Radio71._lines = null
	check(not Radio71.line("lp71.turret_scuttle").is_empty(), "scuttle radio line loads")
	check(not Radio71.line("lp71.core_raid").is_empty(), "core-raid radio line loads")
	var c := LastProtocol.make_config(77, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "Last Protocol match starts for scuttle/raid"):
		return
	for i in 20:
		w.step()
	var s: Dictionary = w.sys_state.lp
	# Scuttle: invent a fallen-ring turret id still alive, queue, then force the blow.
	var tid := -1
	if (s.base.rings as Array).size() > 0:
		var ts: Array = s.base.rings[0].get("turrets", [])
		if not ts.is_empty() and w.entities.has(int(ts[0])):
			tid = int(ts[0])
	if tid >= 0:
		LastProtocol._queue_scuttle(w, s, 0)
		check((s.scuttle as Array).size() >= 1, "fallen ring queues turret scuttle")
		for row in s.scuttle:
			row.at = w.tick  # due now
		LastProtocol._scuttle_tick(w, s)
		check(not w.entities.has(tid), "scuttle destroys the abandoned turret")
	# Core raid stub advances through phases.
	s.dread = 0.9
	s.core_raid = {}
	LastProtocol._core_raid_tick(w, s)
	check_eq(String(s.core_raid.get("phase", "")), "recon", "late dread opens recon")
	check(String(LastProtocol.hud(w).get("core_raid", "")) == "recon", "HUD shows raid phase")
	s.core_raid.t0 = w.tick - int(SimWorld.TICK_RATE * 50)
	LastProtocol._core_raid_tick(w, s)
	check_eq(String(s.core_raid.get("phase", "")), "soften", "raid advances to soften")
	var RF = load("res://presentation/ui71/radio_feed.gd")
	var feed = RF.new()
	feed.setup(0)
	feed.handle_events([{"type": "LpCoreRaid", "phase": "breach", "pos": Vector2(1, 1)}], null)
	feed.tick(0.1)
	check(String(feed.text).to_lower().find("raid") >= 0 or String(feed.text).find("breach") >= 0,
		"radio speaks core raid phase")
	feed.free()


func test_runners_and_after_action() -> void:
	# D3 wall-walk starve + D6 after-action fields.
	check(int(Director71.rules().get("runner_starve_misses", 0)) >= 2, "runner starve needs a few misses")
	Radio71._lines = null
	check(not Radio71.line("lp71.wall_starve").is_empty(), "wall-starve radio line loads")
	var c := LastProtocol.make_config(77, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "Last Protocol match starts for AAR"):
		return
	for i in 15:
		w.step()
	var s: Dictionary = w.sys_state.lp
	s.dread = 0.77
	s.dread_peak = 0.77
	s.wall_crack = [2, 5]
	s.wall_starve = [2]
	s.obj_done = 3
	s.intel = {"g71_m_brute": {"def": "g71_m_brute", "counter": "armour"}}
	s.adapt = {"armour": 4}
	s.kill_heat = {"10,20": 5, "11,20": 2, "1,1": 9}
	LastProtocol._note_kill_heat(s, {"pos": Vector2(10.2, 20.4)})
	check_eq(int(s.kill_heat["10,20"]), 6, "kill heat stacks on a cell")
	var top: Array = LastProtocol._heat_top(s.kill_heat, 2)
	check_eq(top.size(), 2, "heat top is capped")
	check_eq(String(top[0].cell), "1,1", "hottest cell leads the AAR")
	var r: Dictionary = LastProtocol.result(w, s, "victory")
	check(r.has("dread_peak") and float(r.dread_peak) >= 0.77, "AAR keeps dread peak")
	check_eq(int(r.objectives_done), 3, "AAR counts completed objectives")
	check_eq(int(r.intel_n), 1, "AAR counts intel entries")
	check((r.wall_cracks as Array).has("N"), "AAR names cracked faces")
	check_eq(int(r.wall_starve_n), 1, "AAR counts starved faces")
	check((r.kill_heat_top as Array).size() >= 1, "AAR includes kill heat")
	LastProtocol._push_objective(w, s, "clear_walk", "Clear the N wall-walk", {"sector": 2})
	check((LastProtocol.hud(w).objectives as Array).size() >= 1, "clear_walk objective shows")
	var RF = load("res://presentation/ui71/radio_feed.gd")
	var feed = RF.new()
	feed.setup(0)
	feed.handle_events([{"type": "LpWallStarve", "sector": 2, "name": "N", "pos": Vector2(1, 1)}], null)
	feed.tick(0.1)
	check(String(feed.text).to_lower().find("wall") >= 0 or String(feed.text).find("N") >= 0,
		"radio speaks wall-walk starve")
	feed.free()


func test_supply_wall_life_and_sally() -> void:
	# D2 cadence + D3 wall fatigue / counter-attack stubs.
	check(float(Director71.rules().get("supply_at", 0.0)) > 0.0, "supply_at is set")
	check(float(Director71.rules().get("supply_every_s", 0.0)) >= 30.0, "supply cadence is at least 30 s")
	check_eq(Director71.face_name(2), "N", "face 2 is north")
	check(is_equal_approx(Director71.wall_fatigue_step(0.0, true), float(Director71.rules().get("wall_fatigue_gain", 0.04))),
		"pressure raises wall fatigue")
	check(Director71.wall_fatigue_step(0.5, false) < 0.5, "quiet sectors rest")
	check(Director71.wall_crack_at() > 0.5, "crack threshold is late-hold")
	Radio71._lines = null
	check(not Radio71.line("lp71.supply_drop").is_empty(), "supply-drop radio line loads")
	check(not Radio71.line("lp71.sector_crack").is_empty(), "sector-crack radio line loads")
	check(not Radio71.line("lp71.counter_attack").is_empty(), "counter-attack radio line loads")
	var c := LastProtocol.make_config(77, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "Last Protocol match starts for D2/D3"):
		return
	for i in 20:
		w.step()
	var s: Dictionary = w.sys_state.lp
	check((s.get("wall_fatigue", []) as Array).size() == 8, "wall fatigue tracks 8 faces")
	# Low dread: scheduled supply is a no-op.
	s.dread = 0.1
	LastProtocol._scheduled_supply(w, s)
	var had_drop := false
	for o in LastProtocol.hud(w).get("objectives", []):
		if String(o.get("kind", "")) == "protect_drop":
			had_drop = true
	check(not had_drop, "low dread does not schedule a supply drop")
	# High dread may order if magazine ready; always can open/close protect_drop by hand.
	s.dread = 0.9
	LastProtocol._scheduled_supply(w, s)
	LastProtocol._push_objective(w, s, "protect_drop", "Protect the inbound supply drop", {"fac": 0})
	check((LastProtocol.hud(w).objectives as Array).size() >= 1, "protect_drop shows on the HUD")
	LastProtocol._complete_objective(w, s, "protect_drop", {})
	var left := false
	for o2 in LastProtocol.hud(w).objectives:
		if String(o2.get("kind", "")) == "protect_drop":
			left = true
	check(not left, "delivered drop clears the protect objective")
	var fat := 0.0
	while fat < Director71.wall_crack_at():
		fat = Director71.wall_fatigue_step(fat, true)
	check(fat >= Director71.wall_crack_at(), "sustained pressure reaches crack")
	LastProtocol._push_objective(w, s, "rotate_sector", "Rotate fresh squads onto the N face", {"sector": 2})
	LastProtocol._push_objective(w, s, "sally_sapper", "Sally out — smash the sapper on the N face", {"sector": 2})
	var kinds := {}
	for o3 in LastProtocol.hud(w).objectives:
		kinds[String(o3.kind)] = true
	check(bool(kinds.get("rotate_sector", false)), "rotate-sector objective is open")
	check(bool(kinds.get("sally_sapper", false)), "sally objective is open")
	var RF = load("res://presentation/ui71/radio_feed.gd")
	var feed = RF.new()
	feed.setup(0)
	feed.handle_events([{"type": "LpSupplyDrop", "fac": 0, "dread": 0.9, "pos": Vector2(1, 1)}], null)
	feed.tick(0.1)
	check(String(feed.text).to_lower().find("supply") >= 0 or String(feed.text).find("Inbound") >= 0,
		"radio speaks the supply drop")
	feed.tick(30.0)  # clear the subtitle so the next line can show
	feed.handle_events([{"type": "LpSectorCrack", "sector": 2, "name": "N", "pos": Vector2(10, 10)}], null)
	feed.tick(30.1)
	var crack_ok := String(feed.text).to_lower().find("crack") >= 0 or String(feed.text).find("N") >= 0
	if not crack_ok:
		for line in feed.shown:
			if String(line).to_lower().find("crack") >= 0 or String(line).find("N") >= 0:
				crack_ok = true
				break
	check(crack_ok, "radio speaks a sector crack")
	feed.free()
