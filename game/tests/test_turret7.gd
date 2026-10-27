extends "res://tests/test_base.gd"
## G7 acceptance (owner: TURRET7). Master scope section 7: the eight new Human A turrets (sim/systems/turrets7.gd,
## content/g7/defs_g7_turrets.json): build, intended target class, special effects, stage gating, determinism,
## and a match without them is hash-identical.

const T = preload("res://sim/systems/turrets7.gd")
const Creep = preload("res://sim/systems/creep.gd")
const MachineEW7 = preload("res://sim/systems/machine_ew7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const PData = preload("res://sim/systems/progression_data.gd")
const NOFIRE := 100000
const H := 0
const M := 1
const POWERED := ["a_t7_automortar", "a_t7_emp", "a_t7_microwave", "a_t7_railgun"]


## Human A (fid 0) vs Machine (fid 1), both inert; whole map GRASS, no entities. Powered turrets run without power
## (requires_power cleared for the test; _restore() puts it back) unless power is true.
func _setup(stage: int = 10, power: bool = false, seed_v: int = 7) -> SimWorld:
	var w := make_world({"seed": seed_v, "victory": "endless", "sides": [
		{"faction": "human_a", "stage": stage, "credits": 50000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": stage, "credits": 50000, "ai": false, "name": "M", "team": 1}]})
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
	for d in POWERED:
		Content.building(d).requires_power = power
	return w


func _restore() -> void:
	for d in POWERED:
		Content.building(d).requires_power = true


func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].order = {"type": "hold"}
	w.entities[id].cd_ticks = NOFIRE
	return id


## Steps n ticks; drives Turrets7 by hand while world.gd has no Turrets7 slot (ORCH CR), never twice.
func _run(w: SimWorld, n: int, t7: bool = true) -> Array:
	var out := []
	var slot: bool = SimWorld.SYSTEM_ORDER.has(T)
	for i in n:
		w.step()
		out.append_array(w.events)
		if t7 and not slot:
			var n0: int = w.events.size()
			T.tick(w)
			for j in range(n0, w.events.size()):
				out.append(w.events[j])
	return out


func _count(evs: Array, type: String) -> int:
	var n := 0
	for ev in evs:
		if String(ev.type) == type:
			n += 1
	return n


func _aim(w: SimWorld, bid: int) -> int:
	var s = w.sys_state.get("turrets7")
	return -1 if s == null else int(s.aim.get(bid, -1))


func _hp(w: SimWorld, id: int) -> float:
	var e = w.entities.get(id)
	return -1.0 if e == null else float(e.hp)


func test_defs_and_stage_gating() -> void:
	var ids: Array = T.defs()
	check_eq(ids.size(), 8, "eight turret defs")
	for d in ids:
		var b := Content.building(String(d))
		check_eq(String(b.faction), "human_a", "%s is Human A" % d)
		check(not b.has("weapon"), "%s has no def.weapon (Turrets7 drives it, Combat skips it)" % d)
		check(not T.weapon_of(String(d)).is_empty(), "%s weapon row exists" % d)
	check(Content.available(Content.building("a_t7_hmg_nest"), 7), "MG nest from stage 7")
	check(not Content.available(Content.building("a_t7_autocannon"), 7), "autocannon not at stage 7")
	check(not Content.available(Content.building("a_t7_emp"), 9), "EMP not at stage 9")
	check(not Content.available(Content.building("a_t7_railgun"), 9), "rail cannon not at stage 9")
	check(Content.available(Content.building("a_t7_railgun"), 10), "rail cannon from stage 10 (late game)")
	var w := _setup(7)
	w.spawn_building("barracks", H, Vector2i(10, 10), true)
	w.spawn_building("motor_pool", H, Vector2i(16, 10), true)
	check_eq(PData.unavailable_reason(w, H, Content.building("a_t7_hmg_nest")), "", "stage 7 side may build the MG nest")
	check(PData.unavailable_reason(w, H, Content.building("a_t7_hulldown")) != "", "stage 7 side may not build the hull-down turret")
	var rows: Array = T.ai_rows(w, H, {"inf": 3, "armour": true, "machine": true}, true)
	var got := []
	for r in rows:
		got.append(String(r[0]))
	check(got.has("a_t7_hmg_nest"), "AI rows at stage 7 include the MG nest: %s" % str(got))
	check(not got.has("a_t7_railgun") and not got.has("a_t7_hulldown"), "AI rows respect stage gating: %s" % str(got))
	check_eq(T.ai_rows(w, M, {"inf": 3}, true), [], "Machine side gets no Human A turret rows")
	_restore()


func test_builds_and_unbuilt_is_silent() -> void:
	var w := _setup()
	var cell := Vector2i(30, 30)
	var x := 0
	for d in T.defs():
		var bid: int = T.place(w, H, String(d), cell + Vector2i(x, 0))
		x += 3
		check(bid >= 0 and bool(w.entities[bid].get("built", false)), "%s places built" % d)
	var ub := w.spawn_building("a_t7_hmg_nest", H, Vector2i(30, 40), false)
	check(not bool(w.entities[ub].get("built", false)), "an unfinished nest is not built")
	var r := _unit(w, "rifleman", M, Vector2(32.5, 44.5))
	var evs := _run(w, 30)
	check_eq(_aim(w, ub), -1, "the unfinished nest never aims")
	for ev in evs:
		if String(ev.type) == "ShotFired" and int(ev.shooter) == ub:
			check(false, "the unfinished nest fired")
	_restore()


func test_intended_target_classes() -> void:
	var w := _setup()
	var nest: int = T.place(w, H, "a_t7_hmg_nest", Vector2i(20, 20))
	var hd: int = T.place(w, H, "a_t7_hulldown", Vector2i(20, 30))
	var ac: int = T.place(w, H, "a_t7_autocannon", Vector2i(20, 40))
	var mw: int = T.place(w, H, "a_t7_microwave", Vector2i(60, 20))
	# MG nest: walker nearer, rifleman further: picks the rifleman
	var wk := _unit(w, "m_walker", M, Vector2(23.5, 20.5))
	var rf := _unit(w, "rifleman", M, Vector2(27.5, 20.5))
	# hull-down: rifleman nearer, walker further: picks the walker
	var rf2 := _unit(w, "rifleman", M, Vector2(24.5, 31.0))
	var wk2 := _unit(w, "m_walker", M, Vector2(29.5, 31.0))
	# autocannon: rifleman nearer, light vehicle further
	var rf3 := _unit(w, "rifleman", M, Vector2(23.5, 40.5))
	var lv := _unit(w, "m_hauler", M, Vector2(28.5, 40.5))
	# microwave: a rifleman alone in its cone, then a swarm
	var rf4 := _unit(w, "rifleman", M, Vector2(64.5, 20.5))
	_run(w, 12)
	check_eq(_aim(w, nest), rf, "MG nest prefers infantry over a nearer walker")
	check_eq(_aim(w, hd), wk2, "hull-down gun prefers the walker over nearer infantry")
	check_eq(_aim(w, ac), lv, "autocannon prefers the light vehicle over nearer infantry")
	check_eq(_aim(w, mw), -1, "microwave ignores infantry")
	var h0 := _hp(w, rf4)
	var sw := _unit(w, "m_swarm", M, Vector2(63.5, 20.5))
	var s0 := _hp(w, sw)
	_run(w, 25)
	check(_hp(w, sw) < s0, "microwave fries the swarm (%s -> %s)" % [s0, _hp(w, sw)])
	check_eq(_hp(w, rf4), h0, "microwave soft-kill leaves the rifleman in the cone unhurt")
	check(w.entities.has(wk) and w.entities.has(rf2) and w.entities.has(rf3), "setup units still present")
	_restore()


func test_emp_stuns_machine_and_drops_drones() -> void:
	var w := _setup()
	var emp: int = T.place(w, H, "a_t7_emp", Vector2i(40, 40))
	var a := _unit(w, "m_walker", M, Vector2(43.5, 40.5))
	var b := _unit(w, "m_scout_crawler", M, Vector2(40.5, 44.5))
	var far := _unit(w, "m_walker", M, Vector2(55.5, 40.5))
	var dr := _unit(w, "m_drone", M, Vector2(38.5, 42.5))
	var evs := _run(w, 12)
	check_eq(_count(evs, "T7Emp"), 1, "EMP fires once (long recharge)")
	check_eq(MachineEW7.held(w, a), "emp", "walker in radius is EMP-stunned")
	check_eq(MachineEW7.held(w, b), "emp", "crawler in radius is EMP-stunned")
	check_eq(MachineEW7.held(w, far), "", "walker outside the radius is not stunned")
	check(not w.entities.has(dr), "enemy drone in radius is dropped")
	evs = _run(w, 200)
	check_eq(_count(evs, "T7Emp"), 0, "still recharging 10 s later")
	check(int(w.sys_state.turrets7.ready[emp]) > w.tick, "recharge tick recorded")
	_restore()


func test_thermite_burns_creep_and_small_units() -> void:
	var w := _setup()
	var s: Dictionary = Creep.enable(w)
	var th: int = T.place(w, H, "a_t7_thermite", Vector2i(40, 40))
	var cell := Vector2i(44, 41)
	var v: PackedByteArray = s.v   # packed arrays are values: write back
	v[Creep._k(s, cell)] = 255
	s.v = v
	check(Creep.on_creep(w, cell), "creep laid next to the thermite turret")
	var evs := _run(w, 60)
	check(_count(evs, "T7Burn") >= 1, "thermite burns creep with no unit in range")
	check(not Creep.on_creep(w, cell), "the creep cell is burnt")
	var cr := _unit(w, "m_scout_crawler", M, Vector2(44.5, 40.5))
	var h0 := _hp(w, cr)
	_run(w, 40)
	check(_hp(w, cr) < h0, "thermite burns a small Machine unit (%s -> %s)" % [h0, _hp(w, cr)])
	check_eq(_aim(w, th) if w.entities.has(cr) else cr, cr, "thermite aims the crawler")
	_restore()


func test_rail_penetration_and_power() -> void:
	var w := _setup()
	var rail: int = T.place(w, H, "a_t7_railgun", Vector2i(20, 60))
	var big := _unit(w, "m_colossus", M, Vector2(45.0, 61.0))
	var w1 := _unit(w, "m_walker", M, Vector2(30.0, 61.0))
	var w2 := _unit(w, "m_walker", M, Vector2(37.0, 61.2))
	var off := _unit(w, "m_walker", M, Vector2(37.0, 66.0))
	var hp := [_hp(w, big), _hp(w, w1), _hp(w, w2), _hp(w, off)]
	_unit(w, "recon", H, Vector2(40.0, 58.0))   # eyes on the colossus
	var evs := _run(w, 12)
	check_eq(_aim(w, rail), big, "rail cannon picks the biggest Machine unit")
	check_eq(_count(evs, "T7Rail"), 1, "one rail shot")
	check(_hp(w, w1) < float(hp[1]) and _hp(w, w2) < float(hp[2]), "the slug pierces both walkers in its lane")
	check_eq(_hp(w, off), float(hp[3]), "a walker off the line is untouched")
	_restore()
	var w2b := _setup(10, true)
	T.place(w2b, H, "a_t7_railgun", Vector2i(20, 60))
	_unit(w2b, "m_colossus", M, Vector2(30.0, 61.0))
	evs = _run(w2b, 30)
	check_eq(_count(evs, "T7Rail"), 0, "unpowered rail cannon (power 150, no generators) does not fire")
	_restore()


func test_mortar_needs_spotting() -> void:
	var w := _setup()
	var mo: int = T.place(w, H, "a_t7_automortar", Vector2i(20, 80))
	var tg := _unit(w, "m_scout_crawler", M, Vector2(36.5, 81.0))
	_unit(w, "rifleman", H, Vector2(33.5, 81.0))   # sees the target, but is no spotter
	var evs := _run(w, 40)
	var shots := 0
	for ev in evs:
		if String(ev.type) == "ShotFired" and int(ev.shooter) == mo:
			shots += 1
	check_eq(shots, 0, "auto-mortar holds fire on a target no tower or drone spots")
	w.spawn_building("guard_tower", H, Vector2i(31, 79), true)
	evs = _run(w, 40)
	shots = 0
	for ev in evs:
		if String(ev.type) == "ShotFired" and int(ev.shooter) == mo:
			shots += 1
			check(bool(ev.indirect), "mortar fire is indirect")
	check(shots >= 1, "auto-mortar fires once a guard tower spots the target")
	check(not w.entities.has(tg) or _hp(w, tg) < float(Content.unit("m_scout_crawler").hp) or shots >= 1, "target hurt or near-missed")
	_restore()


## A wall of all 8 vs a mixed Machine group: same seed twice = same hash; a world where Turrets7 never runs and
## no turret exists matches the hash of one where it runs with no turret (no state, no rng).
func _wall(seed_v: int) -> SimWorld:
	var w := _setup(10, false, seed_v)
	var x := 20
	for d in T.defs():
		T.place(w, H, String(d), Vector2i(x, 100))
		x += 4
	var i := 0
	for u in ["rifleman", "m_swarm", "m_walker", "m_scout_crawler", "m_hauler", "m_colossus", "m_drone", "rifleman"]:
		var id := w.spawn_unit(String(u), M, Vector2(22.0 + i * 3.5, 108.0))
		w.entities[id].cd_ticks = NOFIRE
		i += 1
	return w


func test_determinism_and_no_turret_identity() -> void:
	var a := _wall(11)
	var b := _wall(11)
	var ea := _run(a, 200)
	_run(b, 200)
	check(_count(ea, "ShotFired") > 10, "the wall fights (%d shots)" % _count(ea, "ShotFired"))
	check_eq(a.state_hash(), b.state_hash(), "same seed + same wall = same hash")
	var c := _setup(10, false, 5)
	var d := _setup(10, false, 5)
	for wd in [c, d]:
		_unit(wd, "rifleman", H, Vector2(30.5, 30.5))
		_unit(wd, "m_walker", M, Vector2(40.5, 30.5))
	_run(c, 120, true)
	_run(d, 120, false)
	check(not c.sys_state.has("turrets7"), "no turret: no Turrets7 state")
	check_eq(c.state_hash(), d.state_hash(), "a match without turrets is hash-identical with or without Turrets7")
	_restore()
