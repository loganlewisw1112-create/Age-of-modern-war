extends "res://tests/test_base.gd"
## G7.1 C1/C2: dread meter, breaths, face split, one-shot breaking-point. Phase clock untouched.

const Director71 = preload("res://sim/systems/director71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


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
	check(not Content.unit("g71_m_brute").is_empty(), "gorilla brute def loads")
	check(not Content.unit("g71_m_siege_walker").is_empty(), "siege walker def loads")
	check_eq(String(Content.unit("g71_m_brute").get("g71_siege", "")), "brute", "brute is tagged")
	check_eq(String(Content.unit("g71_m_siege_walker").get("g71_siege", "")), "walker", "walker is tagged")
	check(Director71.siege_roster(0.1).is_empty(), "probe dread spawns no siege stubs")
	check_eq(Director71.siege_roster(0.5).size(), 1, "mixed dread brings the brute")
	check_eq(Director71.siege_roster(0.9).size(), 2, "siege dread brings brute + walker")


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
