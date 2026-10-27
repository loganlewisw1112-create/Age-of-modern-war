extends "res://tests/test_base.gd"
## G7 acceptance (owner: CREEP7). Master scope sections 8, 6.3, 10: creep, seeds, purges, Machine EW, living cores,
## escalation, learned reactions.

const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const MachineEW7 = preload("res://sim/systems/machine_ew7.gd")
const MachineReact7 = preload("res://sim/ai/machine_react7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const NOFIRE := 100000
const H := 0   # human side
const M := 1   # machine side

var _saved := {}


## Human A (fid 0) vs Machine (fid 1), both inert; whole map GRASS, no entities. Returns w.
func _setup(creep: bool = true) -> SimWorld:
	var w := make_world({"victory": "endless", "sides": [
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 1}]})
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	t.fill(Terrain.GRASS)
	w.map.terrain = t
	w.map.erase("burnt")
	for id in w.entities.keys():
		w.entities.erase(id)
	w.cache.clear()
	if w.hot != null:
		HotState.sync(w)
	Movement.rebuild_nav(w)
	if creep:
		Creep.enable(w)
	return w


## Temporarily overrides a rules.g7_machine value (path like "creep.regrow.regrow_s"); _restore() puts it back.
func _rule(path: String, v) -> void:
	var parts := path.split(".")
	var d: Dictionary = Content.rules().g7_machine
	for i in parts.size() - 1:
		d = d[parts[i]]
	if not _saved.has(path):
		_saved[path] = d[parts[-1]]
	d[parts[-1]] = v


func _restore() -> void:
	for path in _saved:
		var parts := String(path).split(".")
		var d: Dictionary = Content.rules().g7_machine
		for i in parts.size() - 1:
			d = d[parts[i]]
		d[parts[-1]] = _saved[path]
	_saved = {}


func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].order = {"type": "hold"}
	w.entities[id].cd_ticks = NOFIRE
	return id


func _run(w: SimWorld, n: int, types: Array = []) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.is_empty() or types.has(String(ev.type)):
				out.append(ev)
	return out


func _count(evs: Array, type: String) -> int:
	var n := 0
	for ev in evs:
		if String(ev.type) == type:
			n += 1
	return n


func _mid(w: SimWorld) -> Vector2i:
	return Vector2i(int(w.map.w) / 2, int(w.map.h) / 2)


# ================================================================ creep field
func test_spread_over_time_and_firebreaks() -> void:
	var w := _setup()
	var c := _mid(w)
	var mw := int(w.map.w)
	# a water column 16 tiles east of the source, full map height
	var t: PackedByteArray = w.map.terrain
	for y in int(w.map.h):
		t[y * mw + c.x + 16] = Terrain.WATER
		t[y * mw + c.x + 17] = Terrain.WATER
	w.map.terrain = t
	w.sys_state.erase("creep")
	Creep.enable(w)
	w.spawn_building("m_hive_node", M, c, true)
	_run(w, 200)
	var cov1 := Creep.coverage(w)
	_run(w, 1000)
	var cov2 := Creep.coverage(w)
	check(cov1 > 0.0 and cov2 > cov1, "creep spreads over time (%.4f -> %.4f)" % [cov1, cov2])
	check(Creep.on_creep(w, c), "creep under its Machine source")
	check(Creep.on_creep(w, c + Vector2i(-12, 0)), "creep reached 12 tiles west")
	check(not Creep.on_creep(w, c + Vector2i(22, 0)) and Creep.at(w, c + Vector2i(22, 0)) == 0.0,
		"creep never crosses the water firebreak")
	# burnt ground (thermite) and craters are firebreaks too
	var w2 := _setup()
	w2.spawn_building("m_hive_node", M, c, true)
	for y in range(-40, 41, 2):
		Creep.burn(w2, Vector2(c.x - 14, c.y + y), 2.0)
		Creep.crater(w2, Vector2(c.x + 14, c.y + y), 2.0)
	_run(w2, 1200)
	check(Creep.on_creep(w2, c + Vector2i(-6, 0)), "creep inside the burnt ring")
	check(Creep.at(w2, c + Vector2i(-22, 0)) == 0.0, "burnt line blocks creep")
	check(Creep.at(w2, c + Vector2i(22, 0)) == 0.0, "crater line blocks creep")


func test_repair_on_creep() -> void:
	var w := _setup()
	var c := _mid(w)
	w.spawn_building("m_hive_node", M, c, true)
	_run(w, 600)
	var id := _unit(w, "m_walker", M, Vector2(c) + Vector2(3.5, 0.5))
	var off := _unit(w, "m_walker", M, Vector2(2.5, 2.5))
	var e: Dictionary = w.entities[id]
	HotState.set_hp(w, id, float(e.max_hp) * 0.5)
	HotState.set_hp(w, off, float(w.entities[off].max_hp) * 0.5)
	_run(w, 200)
	check(HotState.get_hp(w, id) > float(e.max_hp) * 0.5, "Machine unit on creep repairs")
	check_eq(HotState.get_hp(w, off), float(w.entities[off].max_hp) * 0.5, "Machine unit off creep does not")
	check(Creep.powered(w, e), "unit on creep is powered by the network")


func test_purge_kinds_and_sterile() -> void:
	var w := _setup()
	var c := _mid(w)
	w.spawn_building("m_hive_node", M, c, true)
	w.spawn_building("m_hive_node", M, c + Vector2i(26, 0), true)
	_run(w, 900)
	check(Creep.on_creep(w, c + Vector2i(4, 0)), "creep before purge")
	var evs := []
	var r := Creep.purge(w, Vector2(c), 8.0, "standard", H)
	check(int(r.lost) > 0, "standard purge clears creep cells")
	check(Creep.is_sterile(w, c) and Creep.at(w, c + Vector2i(4, 0)) == 0.0, "purged ground is sterile and clear")
	evs = _run(w, 1200)
	check(Creep.at(w, c) == 0.0 and Creep.at(w, c + Vector2i(4, 0)) == 0.0,
		"sterile ground never regrows, even with the Machine source still standing on it")
	check(Creep.on_creep(w, c + Vector2i(20, 0)), "creep outside the purge stays")
	check(Creep.coverage(w) > 0.0, "coverage still reports the rest")
	# seeds: standard kills only within radius; seed-hunter kills dormant seeds and burrowed cores 3x wider
	var w2 := _setup()
	var far := Creep.add_seed(w2, Vector2(c) + Vector2(15, 0), "seed", M)
	var core := Creep.add_seed(w2, Vector2(c) + Vector2(2, 0), "core", M)
	var near := Creep.add_seed(w2, Vector2(c) + Vector2(3, 0), "seed", M)
	Creep.purge(w2, Vector2(c), 6.0, "standard", H)
	var ids := []
	for sd in Creep.seeds(w2):
		ids.append(int(sd.id))
	check(not ids.has(near) and ids.has(far) and ids.has(core),
		"standard purge kills the surface seed in radius only (left %s)" % str(ids))
	Creep.purge(w2, Vector2(c), 6.0, "seed_hunter", H)
	check(Creep.seeds(w2).is_empty(), "seed-hunter kills the far dormant seed and the burrowed core")
	# barrier line: creep can't cross it
	var w3 := _setup()
	w3.spawn_building("m_hive_node", M, c, true)
	Creep.purge(w3, Vector2(c.x + 10, c.y), 200.0, "barrier", H, Vector2(0, 1))
	check(Creep.is_barrier(w3, Vector2i(c.x + 10, c.y)), "barrier cells flagged")
	_run(w3, 1200)
	check(Creep.on_creep(w3, c + Vector2i(4, 0)), "creep on the near side of the barrier")
	check(Creep.at(w3, c + Vector2i(18, 0)) == 0.0, "creep never crosses a barrier line")


# ================================================================ seeds
func test_seeds_regrow_after_wipe_unless_purged() -> void:
	_rule("creep.regrow.regrow_s", 3.0)
	var w := _setup()
	var c := _mid(w)
	var bid := w.spawn_building("m_hive_node", M, c, true)
	Creep.add_seed(w, Vector2(c) + Vector2(6, 0), "seed", M)
	_run(w, 200)
	check(_count(_run(w, 100, ["SeedRegrown"]), "SeedRegrown") == 0, "no regrowth while the base stands")
	w.destroy(bid, "test_wipe")
	var evs := _run(w, 140, ["SeedRegrown"])
	check_eq(_count(evs, "SeedRegrown"), 1, "dormant seed regrows a structure after the base is wiped")
	if not evs.is_empty():
		var nb = w.entities.get(int(evs[0].building))
		check(nb != null and int(nb.owner) == M and String(nb.def) == "m_hive_node", "regrown structure is Machine-owned")
	# found (scanner reveal) and purged: no regrowth
	var w2 := _setup()
	var b2 := w2.spawn_building("m_hive_node", M, c, true)
	var sid := Creep.add_seed(w2, Vector2(c) + Vector2(6, 0), "seed", M)
	var nest := Creep.add_nest(w2, Vector2(c) + Vector2(-14, 14), 5, 2.0, M)
	check_eq(nest.size(), 5, "a nest is a dense cluster of seeds")
	check_eq(Creep.reveal(w2, Vector2(c), 10.0, H), 1, "scanner reveals the seed in range only")
	check(Creep.snap(w2).seeds.size() == 1, "revealed seed reaches the view snapshot")
	w2.destroy(b2, "test_wipe")
	Creep.purge(w2, Vector2(c) + Vector2(6, 0), 3.0, "standard", H)
	Creep.purge(w2, Vector2(c) + Vector2(-14, 14), 4.0, "standard", H)
	var still := false
	for sd in Creep.seeds(w2):
		still = still or int(sd.id) == sid
	check(not still and Creep.seeds(w2).is_empty(), "purged seeds are gone")
	check_eq(_count(_run(w2, 200, ["SeedRegrown"]), "SeedRegrown"), 0, "purged seeds never regrow")
	_restore()


# ================================================================ EW
func test_emp_stun_and_hack_rules() -> void:
	var w := _setup()
	var c := _mid(w)
	var m := _unit(w, "m_walker", M, Vector2(c) + Vector2(0.5, 0.5))
	do_cmd(w, M, {"type": "move", "unit_ids": [m], "target": Vector2(c) + Vector2(20.5, 0.5)})
	_run(w, 10)
	var n := MachineEW7.stun(w, HotState.get_pos(w, m), 3.0, 2.0, H)
	check_eq(n, 1, "EMP catches the Machine unit")
	var p0 := HotState.get_pos(w, m)
	_run(w, 20)
	check(HotState.get_pos(w, m).distance_to(p0) < 0.01, "EMP-stunned Machine unit does not move")
	check_eq(MachineEW7.held(w, m), "emp", "held state reported")
	_run(w, 60)
	check(HotState.get_pos(w, m).distance_to(p0) > 0.5, "moves again once the stun ends")
	check_eq(MachineEW7.held(w, m), "", "hold cleared")
	# hack rules
	var tank := _unit(w, "mbt", H, Vector2(c) + Vector2(4.5, 8.5))
	check(MachineEW7.can_hack(w.entities[tank], w), "a human vehicle is hackable")
	check(not MachineEW7.can_hack(w.entities[m], w), "Machine units are not")
	if not Content.unit("rifle_squad").is_empty():
		var soldier := _unit(w, "rifle_squad", H, Vector2(c) + Vector2(3.5, 8.5))
		check(not MachineEW7.can_hack(w.entities[soldier], w), "foot soldiers are not hackable")
	w.entities[tank].unhackable = true
	check(not MachineEW7.can_hack(w.entities[tank], w), "unhackable (CNSIM7 flag) is immune")
	w.entities[tank].erase("unhackable")
	w.spawn_building("m_jammer_obelisk", M, c + Vector2i(4, 4), true)
	var evs := _run(w, 90, ["MachineHack"])
	check(_count(evs, "MachineHack") >= 1 and int(evs[0].target) == tank and String(evs[0].kind) == "jam",
		"jammer obelisk jams the nearest human vehicle (%s)" % str(evs))
	# unhackable vehicles are never picked; drones are taken over
	var w2 := _setup()
	var t2 := _unit(w2, "mbt", H, Vector2(c) + Vector2(2.5, 2.5))
	w2.entities[t2].unhackable = true
	var dr := -1
	if not Content.unit("g7_a_fpv").is_empty():
		dr = _unit(w2, "g7_a_fpv", H, Vector2(c) + Vector2(6.5, 6.5))
	w2.spawn_building("m_jammer_obelisk", M, c, true)
	var e2 := _run(w2, 90, ["MachineHack"])
	for ev in e2:
		check(int(ev.target) != t2, "unhackable vehicle never hacked")
	if dr >= 0:
		check(_count(e2, "MachineHack") >= 1 and String(e2[0].kind) == "take", "a drone in range is taken over (%s)" % str(e2))


# ================================================================ cores
func test_core_plating_hits_phase2_walk() -> void:
	_rule("cores.plate_every_s", 1.0)
	var w := _setup()
	var c := _mid(w)
	var hq := String(Content.faction("human_a").get("roles", {}).get("hq", ""))
	w.spawn_building(hq, H, c + Vector2i(30, 0), true)
	var bid := Cores.place(w, M, c)
	var b: Dictionary = w.entities[bid]
	var hp0 := float(b.max_hp)
	var evs := _run(w, 70, ["CorePulse", "CorePlated"])
	check(_count(evs, "CorePulse") >= 1, "living core pulses")
	check(int(Cores.list(w)[0].plate) >= 3 and float(b.max_hp) > hp0, "core grows armour plating over time")
	b.hp = float(b.hp) - 100.0
	evs = _run(w, 1, ["CoreHit"])
	check(_count(evs, "CoreHit") == 1 and absf(float(evs[0].dmg) - 100.0) < 0.5 and float(evs[0].intensity) > 0.0,
		"CoreHit with intensity on damage (%s)" % str(evs))
	b.hp = float(b.max_hp) * 0.25
	evs = _run(w, 1, ["CoreUprooted"])
	check_eq(_count(evs, "CoreUprooted"), 1, "the last core tears out of the ground at low hp")
	var wk := Cores.walker(w)
	check(wk >= 0 and w.entities.has(wk) and not w.entities.has(bid), "walker replaces the core building")
	check_eq(Cores.alive_count(w), 1, "the walking core still counts as alive")
	var p0 := HotState.get_pos(w, wk)
	_run(w, 100)
	var p1 := HotState.get_pos(w, wk)
	check(p1.x > p0.x + 1.0, "walking core heads for the enemy (%s -> %s)" % [str(p0), str(p1)])
	MachineEW7.stun(w, p1, 2.0, 2.0, H)
	_run(w, 30)
	check(HotState.get_pos(w, wk).distance_to(p1) < 0.01, "EMP holds the walking core")
	_run(w, 20)
	Creep.purge(w, HotState.get_pos(w, wk) + Vector2(3, 0), 100.0, "barrier", H, Vector2(0, 1))
	evs = _run(w, 120, ["CoreWalkerBlocked"])
	check(_count(evs, "CoreWalkerBlocked") == 1, "barrier line stops the walking core")
	var before := Cores.countdown_rate(w)
	check(Cores.finish(w, 0, H), "core-breaker finishes the walker")
	_run(w, 1)
	check_eq(Cores.alive_count(w), 0, "no cores left")
	check(Cores.countdown_rate(w) < before, "a destroyed core slows the countdown")
	_restore()


func test_reactions_learned_in_order() -> void:
	_rule("react.lost_cells", 1)
	var w := _setup()
	var c := _mid(w)
	w.spawn_building("m_hive_node", M, c, true)
	Cores.place(w, M, c + Vector2i(20, 0))
	Cores.place(w, M, c + Vector2i(-20, 0))
	_run(w, 600)
	Cores.finish(w, 0, H)   # trigger 3 first: must wait for 1 and 2
	var evs := _run(w, 5, ["NetworkAdapted"])
	check_eq(_count(evs, "NetworkAdapted"), 0, "a core falling first teaches nothing yet (order)")
	Creep.purge(w, Vector2(c), 6.0, "standard", H)   # first deployment + creep lost
	evs = _run(w, 5, ["NetworkAdapted"])
	var ns := []
	for ev in evs:
		ns.append(int(ev.n))
		check_eq(String(ev.text), "THE NETWORK HAS ADAPTED", "HUD alert text")
	check_eq(ns, [1, 2, 3], "reactions 1, 2, 3 learned in order, one per tick")
	Cores.set_phase(w, 3)
	evs = _run(w, 2, ["NetworkAdapted"])
	check(_count(evs, "NetworkAdapted") == 1 and int(evs[0].n) == 4, "reaction 4 learned late (phase 3)")
	check_eq(MachineReact7.learned(w), [1, 2, 3, 4], "learned list")
	_restore()


func test_reactions_act_for_ai() -> void:
	var w := _setup()
	var c := _mid(w)
	w.spawn_building("m_hive_node", M, c, true)
	for i in 6:
		w.spawn_unit("m_walker", M, Vector2(c) + Vector2(2.5 + i, 3.5))
	_run(w, 50)
	Creep.purge(w, Vector2(c) + Vector2(12, 0), 3.0, "standard", H)
	var evs := []
	for i in 220:   # the AI hook (Cores.tick -> MachineReact7.think for AI-run Machine sides), driven by hand here
		w.step()
		MachineReact7.think(w, M)
		for ev in w.events:
			if ["NetworkReaction", "NetworkAdapted"].has(String(ev.type)):
				evs.append(ev)
	check(_count(evs, "NetworkAdapted") >= 1, "reaction 1 learned")
	var sent := false
	for ev in evs:
		sent = sent or (String(ev.type) == "NetworkReaction" and String(ev.kind) == "defend_site")
	check(sent, "AI Machine sends units to defend the deployment site (%s)" % str(evs))


# ================================================================ determinism, saves, no-creep, cost
func _scenario(w: SimWorld) -> void:
	var c := _mid(w)
	w.spawn_building("m_hive_node", M, c, true)
	Cores.place(w, M, c + Vector2i(-16, 6))
	Creep.add_nest(w, Vector2(c) + Vector2(10, -10), 4, 2.0, M)
	_unit(w, "mbt", H, Vector2(c) + Vector2(5.5, 5.5))
	w.spawn_building("m_jammer_obelisk", M, c + Vector2i(3, 3), true)


func test_same_seed_same_hash_and_save_roundtrip() -> void:
	var a := _setup()
	var b := _setup()
	_scenario(a)
	_scenario(b)
	_run(a, 300)
	_run(b, 300)
	Creep.purge(a, Vector2(_mid(a)) + Vector2(8, 0), 5.0, "seed_hunter", H)
	Creep.purge(b, Vector2(_mid(b)) + Vector2(8, 0), 5.0, "seed_hunter", H)
	_run(a, 200)
	_run(b, 200)
	check_eq(a.state_hash(), b.state_hash(), "same seed + same actions = same hash with creep, cores and EW")
	check(a.sys_state.has("creep") and a.sys_state.has("cores"), "creep and core state saved in sys_state")
	var c2 := SimWorld.from_dict(a.to_dict().duplicate(true))
	check_eq(c2.state_hash(), a.state_hash(), "save round-trip keeps the hash")
	_run(a, 100)
	_run(c2, 100)
	check_eq(c2.state_hash(), a.state_hash(), "a loaded match continues identically")


func test_match_without_creep_untouched() -> void:
	var w := make_world()
	_run(w, 200)
	check(not w.sys_state.has("creep") and not w.sys_state.has("cores") and not w.sys_state.has("machine_ew7"),
		"default match never creates creep / core / EW state")
	var wm := _setup(false)
	var c := _mid(wm)
	wm.spawn_building("m_hive_node", M, c, true)
	wm.spawn_building("m_jammer_obelisk", M, c + Vector2i(3, 3), true)
	_unit(wm, "mbt", H, Vector2(c) + Vector2(5.5, 5.5))
	var evs := _run(wm, 200, ["MachineHack"])
	check(not wm.sys_state.has("creep") and not wm.sys_state.has("cores") and not wm.sys_state.has("machine_ew7"),
		"a Machine match without creep keeps no G7 Machine state (its hash is the pre-G7 one)")
	check_eq(evs.size(), 0, "no automatic hacking outside creep matches")


## Cost of a fully crept 512 x 512 map: Creep.tick alone (field + sources + repair), reported as CREEP7_COST.
func test_cost_512_full_creep() -> void:
	_rule("creep.regrow.nest_regrow_s", 1000000.0)  # no structure spawns on the stand-in 512 map
	var w := _setup(false)
	var mp: Dictionary = w.map.duplicate()
	mp.w = 512
	mp.h = 512
	var t := PackedByteArray()
	t.resize(512 * 512)
	t.fill(Terrain.GRASS)
	mp.terrain = t
	mp.erase("burnt")
	w.map = mp
	Creep.enable(w)
	for y in 8:
		for x in 8:
			Creep.add_seed(w, Vector2(32 + x * 64, 32 + y * 64), "nest", M)
	for i in 3000:
		w.tick += 1
		Creep.tick(w)
	var cov := Creep.coverage(w)
	check(cov > 0.9, "512 map fully crept for the cost check (coverage %.3f)" % cov)
	var t0 := Time.get_ticks_usec()
	for i in 400:
		w.tick += 1
		Creep.tick(w)
	var us := float(Time.get_ticks_usec() - t0) / 400.0
	print("CREEP7_COST map=512x512 coverage=%.3f creep_tick_us_avg=%.1f (400 ticks, grid %dx%d)" % [cov, us,
		int(w.sys_state.creep.cw), int(w.sys_state.creep.ch)])
	check(us < 2000.0, "creep tick on a fully crept 512 map stays under 2 ms (%.1f us)" % us)
	_restore()


# ================================================================ CNSIM7 hooks
func test_jam_link_and_leeches() -> void:
	var w := _setup()
	var c := _mid(w)
	w.spawn_building("m_hive_node", M, c, true)
	Creep.jam_link(w, Vector2(c), 40.0, w.tick + 400, H)
	check(Creep.is_jammed(w, Vector2(c)), "jam zone active")
	_run(w, 300)
	check_eq(Creep.coverage(w), 0.0, "no creep grows inside a jammed hive link")
	_run(w, 600)
	check(Creep.coverage(w) > 0.0 and not Creep.is_jammed(w, Vector2(c)), "creep grows again once the jam ends")
	var apc := _unit(w, "mbt", H, Vector2(c) + Vector2(6.5, 6.5))
	var l1 := _unit(w, "m_walker", M, Vector2(c) + Vector2(6.5, 7.5))
	var l2 := _unit(w, "m_walker", M, Vector2(c) + Vector2(7.5, 6.5))
	w.entities[l1].leech_on = apc
	w.entities[l2].leech_on = apc
	check_eq(Creep.detach_leeches(w, apc), 2, "detach_leeches knocks both leeches off")
	w.entities[l1].leech_on = apc
	MachineEW7.stun(w, Vector2(c) + Vector2(6.5, 7.5), 2.0, 1.0, H)
	check(not w.entities[l1].has("leech_on"), "EMP shakes a latched leech off")
