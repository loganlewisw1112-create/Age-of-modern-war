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
	# G7 FIX8 (G7_REFERENCE "Lethality test-setup authority", before 13.9c-48): presence check moved here, right after the
	# first short run; with 13.9c-47 lethality the autocannon kills rf3/rf2 later in the microwave phase.
	check(w.entities.has(wk) and w.entities.has(rf2) and w.entities.has(rf3), "setup units still present")
	check_eq(_aim(w, nest), rf, "MG nest prefers infantry over a nearer walker")
	check_eq(_aim(w, hd), wk2, "hull-down gun prefers the walker over nearer infantry")
	check_eq(_aim(w, ac), lv, "autocannon prefers the light vehicle over nearer infantry")
	check_eq(_aim(w, mw), -1, "microwave ignores infantry")
	var h0 := _hp(w, rf4)
	var sw := _unit(w, "m_swarm", M, Vector2(63.5, 20.5))
	var s0 := _hp(w, sw)
	_run(w, 25 + _lay_ticks(w, mw, Vector2(63.5, 20.5)))   # G7 TURRET7B (13.9c-30): + the head's lay time
	check(_hp(w, sw) < s0, "microwave fries the swarm (%s -> %s)" % [s0, _hp(w, sw)])
	check_eq(_hp(w, rf4), h0, "microwave soft-kill leaves the rifleman in the cone unhurt")
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
	var evs := _run(w, 12 + _lay_ticks(w, rail, Vector2(45.0, 61.0)))   # G7 TURRET7B (13.9c-30): + the head's lay time
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
	w.entities[tg].hp = 100000.0   # FIX8B (Lethality test-setup authority): the guard tower killed the 110-hp crawler (2 hits, t47/63) before the mortar laid; subject = spotting, not toughness
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
		w.entities[id].hp = 100000.0   # FIX8B (Lethality test-setup authority): realistic rounds killed the group in 2 shots (4 shots / 200 ticks); subject = determinism, not toughness
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


# ============================================================ G7 TURRET7B: traverse before fire (13.9c-30)
const Trav = preload("res://sim/systems/traverse7.gd")


func _adiff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


## G7 TURRET7B: worst-case ticks for turret bid's head to traverse from its (scanning) rest onto point p (13.9c-30:
## a turret fires only once laid). Older timing windows add exactly this, nothing more.
func _lay_ticks(w: SimWorld, bid: int, p: Vector2) -> int:
	var b: Dictionary = w.entities[bid]
	var m := Trav.mount(b)
	if float(m[1]) <= 0.0:
		return 0
	var d := _adiff(Trav.bearing(w, b, int(w.tick)), (p - T.center(b)).angle()) + 2.0 * float(m[4])
	return int(ceil(maxf(d - float(m[2]), 0.0) / float(m[1]))) + 1


func _combat_hooked() -> bool:
	return FileAccess.get_file_as_string("res://sim/systems/combat.gd").contains("Traverse7.lay(")


## One Turrets7 turret with a target straight behind its rest bearing. Returns [w, bid, tid].
func _behind(def_id: String, target_def: String, dist: float, seed_v: int = 7) -> Array:
	var w := _setup(10, false, seed_v)
	var bid: int = T.place(w, H, def_id, Vector2i(40, 40))
	var b: Dictionary = w.entities[bid]
	var rest := Trav.bearing(w, b, int(w.tick))
	var tid := _unit(w, target_def, M, T.center(b) + Vector2.from_angle(rest + PI) * dist)
	return [w, bid, tid]


## A target straight behind: the head swings at its rate (no jump), holds fire until laid, and the first shot leaves
## with the head on the target.
func test_traverse_takes_time_and_no_shot_before_laid() -> void:
	var tgt := {"a_t7_autocannon": "m_hauler", "a_t7_hmg_nest": "rifleman", "a_t7_railgun": "m_walker"}
	for d in tgt:
		var r := _behind(String(d), String(tgt[d]), 5.0)
		var w: SimWorld = r[0]
		var bid: int = r[1]
		var b: Dictionary = w.entities[bid]
		var m := Trav.mount(b)
		var c: Vector2 = T.center(b)
		var first := -1
		var prev := Trav.bearing(w, b, int(w.tick))
		var max_step := 0.0
		var swung := 0.0
		var off_at_shot := -1.0
		for i in 240:
			var t0 = w.entities.get(int(r[2]))
			var tp0: Vector2 = T.pos_of(w, t0) if t0 != null else Vector2.ZERO
			var evs := _run(w, 1)
			var bb := Trav.bearing(w, b, int(w.tick))
			max_step = maxf(max_step, _adiff(bb, prev))
			swung += _adiff(bb, prev)
			prev = bb
			for ev in evs:
				if first < 0 and String(ev.type) == "ShotFired" and int(ev.shooter) == bid:
					first = i
					off_at_shot = _adiff(float(b.tf), (tp0 - c).angle())
			if first >= 0:
				break
		var need := (PI * 0.75) / float(m[1])   # at least ~135 deg of slew (scan sweep +-20 deg, tolerance 5 deg)
		check(first >= 0, "%s fires once laid (first shot tick %d)" % [d, first])
		check(float(first) >= need, "%s holds fire while it traverses (first shot %d >= %.1f ticks at %.0f deg/s)" % [d, first, need, rad_to_deg(float(m[1])) * 20.0])
		check(max_step <= float(m[1]) * 10.0 + 0.001, "%s swings at its rate, never a jump (max %.3f rad/tick)" % [d, max_step])
		check(swung >= PI * 0.7, "%s visibly swung %.0f deg onto the target" % [d, rad_to_deg(swung)])
		check(off_at_shot >= 0.0 and off_at_shot <= float(m[2]) + 0.002, "%s head on the target at the shot (%.1f deg off)" % [d, rad_to_deg(off_at_shot)])
	_restore()


func test_traverse_tracks_a_mover() -> void:
	var w := _setup()
	var bid: int = T.place(w, H, "a_t7_hmg_nest", Vector2i(40, 40))
	var b: Dictionary = w.entities[bid]
	var c: Vector2 = T.center(b)
	var tid := _unit(w, "rifleman", M, c + Vector2(-3.0, -4.5))
	w.entities[tid].hp = 1.0e9
	w.entities[tid].max_hp = 1.0e9
	var shots := 0
	var worst := 0.0
	var b0 := -99.0
	var b1 := -99.0
	for i in 160:
		HotState.set_pos(w, tid, c + Vector2(-3.0, -4.5 + 0.07 * float(i)))   # crossing at 1.4 tiles/s
		w.entities[tid].pos = c + Vector2(-3.0, -4.5 + 0.07 * float(i))
		var evs := _run(w, 1)
		var tt = w.entities.get(tid)
		if tt == null:
			break
		for ev in evs:
			if String(ev.type) == "ShotFired" and int(ev.shooter) == bid:
				shots += 1
				worst = maxf(worst, _adiff(float(b.tf), (T.pos_of(w, tt) - c).angle()))
				if b0 < -9.0:
					b0 = float(b.tf)
				b1 = float(b.tf)
	check(shots >= 3, "the MG nest keeps firing at the crossing target (%d shots)" % shots)
	check(worst <= float(Trav.mount(b)[2]) + 0.06, "every shot left with the head on the mover (worst %.1f deg)" % rad_to_deg(worst))
	check(_adiff(b0, b1) >= deg_to_rad(30.0), "the head tracked the mover across %.0f deg" % rad_to_deg(_adiff(b0, b1)))
	_restore()


func test_traverse_idle_returns_to_rest() -> void:
	var r := _behind("a_t7_autocannon", "m_hauler", 5.0)
	var w: SimWorld = r[0]
	w.entities[int(r[2])].hp = 100000.0   # G7 FIX8 (G7_REFERENCE "Lethality test-setup authority", before 13.9c-48): durable m_hauler, so it lives until the scripted destroy
	var bid: int = r[1]
	var b: Dictionary = w.entities[bid]
	var rest0 := Trav.rest_of(w, b, Trav.mount(b), int(w.tick))
	_run(w, 120)
	check(b.has("tf") and _adiff(float(b.tf), rest0) > PI * 0.5, "laid round onto the target behind it")
	w.destroy(int(r[2]), "test", SimWorld.NEUTRAL)
	var tf := float(b.get("tf", 0.0))
	_run(w, 20)
	check_eq(float(b.get("tf", 0.0)), tf, "idle: no per-tick state writes (bearing is lazy)")
	check(_adiff(Trav.bearing(w, b, int(w.tick)), tf) < 0.01, "holds its last lay for hold_s")
	_run(w, 200)
	var now := int(w.tick)
	check(_adiff(Trav.bearing(w, b, now), Trav.rest_of(w, b, Trav.mount(b), now)) < 0.01, "back on its (scanning) rest bearing after the hold")
	var lo := 99.0
	var hi := -99.0
	var far := 0.0
	for k in 16:   # one full scan period (16 s) sampled every second
		var sb := Trav.bearing(w, b, now + k * 20)
		var rel := wrapf(sb - rest0, -PI, PI)
		lo = minf(lo, rel)
		hi = maxf(hi, rel)
		far = maxf(far, absf(rel))
	check(hi - lo >= deg_to_rad(20.0) and far <= deg_to_rad(41.0), "idle head scans slowly around the rest bearing (sweep %.1f deg, max %.1f deg off)" % [rad_to_deg(hi - lo), rad_to_deg(far)])
	_restore()


func test_traverse_deterministic_and_saved() -> void:
	var a := _wall(13)
	var b := _wall(13)
	_run(a, 150)
	_run(b, 150)
	var laid := 0
	var same := true
	for id in a.entities:
		var ea: Dictionary = a.entities[id]
		if ea.has("tf"):
			laid += 1
			var eb = b.entities.get(id)
			same = same and eb != null and float(eb.tf) == float(ea.tf) and int(eb.tft) == int(ea.tft) and int(eb.tfh) == int(ea.tfh)
	check(laid >= 4, "the turret wall laid %d heads" % laid)
	check(same, "same seed: identical turret bearings")
	check_eq(a.state_hash(), b.state_hash(), "same seed: same hash with traverse state")
	var d: Dictionary = a.to_dict()
	var found := false
	var ents = d.get("entities", {})
	for k in ents:
		var ed = ents[k]
		if ed is Dictionary and ed.has("tf"):
			found = true
			break
	check(found, "turret bearing is part of the saved / hashed state")
	_restore()


func test_traverse_no_mount_unchanged() -> void:
	var w := _setup()
	var rf := _unit(w, "rifleman", H, Vector2(30.5, 30.5))
	var e: Dictionary = w.entities[rf]
	check_eq(Trav.mode_of(e), Trav.MOUNT_NONE, "infantry has no mount")
	check(Trav.lay(w, e, Vector2(35.5, 20.5), 1.0), "an unmounted shooter is always laid")
	check(not e.has("tf") and not e.has("tft"), "and gets no traverse state")
	check_eq(Trav.face(e, 1.25), 1.25, "infantry still turns to face its shot")
	var tk := _unit(w, "mbt", H, Vector2(40.5, 30.5))
	var te: Dictionary = w.entities[tk]
	te.facing = 0.0
	check_eq(Trav.mode_of(te), Trav.MOUNT_TURRET, "the MBT has a separate turret")
	check_eq(Trav.face(te, 2.0), 0.0, "a turreted tank never swings its hull to fire")
	check(not Trav.lay(w, te, Vector2(te.pos) + Vector2(-5, 0), 4.0), "MBT: target behind -> not laid on the first tick")
	check(_adiff(float(te.tf), 0.0) <= float(Trav.mount(te)[1]) + 0.001, "MBT turret moved one tick of traverse from hull-forward")
	check_eq(float(te.facing), 0.0, "hull untouched by the turret lay")
	var ac := _unit(w, "b_armored_car", H, Vector2(50.5, 30.5))
	var ae: Dictionary = w.entities[ac]
	ae.facing = 0.0
	ae.moving = false
	check(not Trav.lay(w, ae, Vector2(ae.pos) + Vector2(0, 5), 1.0), "armoured car (no turret art): hull lays over time")
	check(float(ae.facing) > 0.0 and float(ae.facing) < PI * 0.5 - 0.01 and not ae.has("tf"), "its hull turned one step (%.3f), no snap" % float(ae.facing))
	_restore()


## Combat-path turrets (tanks): needs ORCH's combat.gd CR (Traverse7.lay in _fire); until it lands this FAILS on the
## first check (reported, not passed silently).
func test_traverse_combat_tank() -> void:
	if not check(_combat_hooked(), "combat.gd carries the Traverse7 hook (ORCH CR change_request.traverse7_hooks)"):
		return
	var w := _setup()
	var tk := _unit(w, "mbt", H, Vector2(40.5, 40.5))
	var te: Dictionary = w.entities[tk]
	te.facing = 0.0
	te.cd_ticks = 0
	_unit(w, "m_walker", M, Vector2(34.5, 40.5))
	var first := -1
	var hull_moved := false
	for i in 200:
		var evs := _run(w, 1, false)
		hull_moved = hull_moved or float(te.get("facing", 0.0)) != 0.0
		for ev in evs:
			if first < 0 and String(ev.type) == "ShotFired" and int(ev.shooter) == tk:
				first = i
		if first >= 0:
			break
	var m := Trav.mount(te)
	check(first >= int((PI - float(m[2])) / float(m[1])) - 1, "MBT holds fire while its turret swings 180 deg (first shot tick %d)" % first)
	check(not hull_moved, "the MBT hull never swung toward the target")
	check(_adiff(float(te.get("tf", 0.0)), PI) <= float(m[2]) + 0.002, "MBT turret laid on the target behind")
	_restore()


# ---- G7 TURRET7C: CIWS / point-defence lay before they intercept (13.9c-30) ----
const Counterdrone = preload("res://sim/systems/counterdrone.gd")


## A powered-free Laser CIWS (Human A) in the clear. Returns [w, bid, centre].
func _ciws_world() -> Array:
	var w := _setup()
	Content.building("a_laser_ciws").requires_power = false
	var bid := w.spawn_building("a_laser_ciws", H, Vector2i(40, 40), true)
	w.entities[bid].cd_ticks = NOFIRE   # its own Combat weapon silenced: the Counterdrone layer alone
	w.run_ticks(2)
	return [w, bid, Vector2(w.entities[bid].pos)]


func _ciws_restore() -> void:
	Content.building("a_laser_ciws").requires_power = true


## A drone straight behind the resting head, inside the laser radius: it is tracked and the head swings round at its
## rate; the kill comes only once the head is laid on it (never on the first ticks).
func test_ciws_lays_before_it_kills_a_drone() -> void:
	var s := _ciws_world()
	var w: SimWorld = s[0]
	var bid: int = s[1]
	var c: Vector2 = s[2]
	var b: Dictionary = w.entities[bid]
	var rest := Trav.bearing(w, b, int(w.tick))
	var did := _unit(w, "m_micro_drone", M, c + Vector2.from_angle(rest + PI) * 5.0)
	var want := (Vector2(w.entities[did].pos) - c).angle()
	var m := Trav.mount(b)
	var need := _adiff(rest, want)
	var min_ticks := int((need - float(m[2])) / float(m[1])) - 2
	var kill := -1
	var b_at_kill := 99.0
	for i in 120:
		var evs := _run(w, 1, false)
		for ev in evs:
			if String(ev.type) == "CiwsKill" and int(ev.ciws) == bid:
				kill = i
				b_at_kill = _adiff(Trav.bearing(w, b, int(w.tick)), want)
		if kill >= 0:
			break
	check(kill >= 0, "the CIWS kills the drone in the end")
	check(kill >= min_ticks, "no kill before the head could swing round: tick %d, >= %d at %.0f deg/s over %.0f deg" % [kill, min_ticks, rad_to_deg(float(m[1])) * 20.0, rad_to_deg(need)])
	check(b_at_kill <= float(m[2]) + 0.002, "the head was laid on the drone at the kill (%.1f deg off)" % rad_to_deg(b_at_kill))
	_ciws_restore()


## A drone outside the laser radius but inside the tracking radius is followed by the head, not shot.
func test_ciws_tracks_a_drone_before_it_is_in_range() -> void:
	var s := _ciws_world()
	var w: SimWorld = s[0]
	var bid: int = s[1]
	var c: Vector2 = s[2]
	var b: Dictionary = w.entities[bid]
	var rest := Trav.bearing(w, b, int(w.tick))
	var did := _unit(w, "m_micro_drone", M, c + Vector2.from_angle(rest + PI * 0.75) * 11.0)
	var want := (Vector2(w.entities[did].pos) - c).angle()
	var kills := 0
	for i in 80:
		for ev in _run(w, 1, false):
			if String(ev.type) == "CiwsKill":
				kills += 1
	check_eq(kills, 0, "a drone 11 tiles out (radius 6) is tracked, not shot")
	check(_adiff(Trav.bearing(w, b, int(w.tick)), want) <= float(Trav.mount(b)[2]) + 0.002, "the head follows it round (%.1f deg off)" % rad_to_deg(_adiff(Trav.bearing(w, b, int(w.tick)), want)))
	_ciws_restore()


## A strike / shell landing behind the head: out of the engagement window it gets through (the head starts swinging and
## the CIWS stays ready); a landing within the window is intercepted with a lay time and the head swings onto it.
func test_ciws_strike_intercept_needs_a_lay() -> void:
	var s := _ciws_world()
	var w: SimWorld = s[0]
	var bid: int = s[1]
	var c: Vector2 = s[2]
	var b: Dictionary = w.entities[bid]
	var m := Trav.mount(b)
	var cur := Trav.bearing(w, b, int(w.tick))
	var behind := c + Vector2.from_angle(cur + PI) * 4.0
	check(not Counterdrone.intercept_strike(w, M, behind, "cruise"), "a strike straight behind the head gets through (out of the lay window)")
	_run(w, 3, false)
	check(_adiff(Trav.bearing(w, b, int(w.tick)), (behind - c).angle()) < PI - 0.05, "...but the head has started swinging toward it")
	_run(w, 40, false)
	check(_adiff(Trav.bearing(w, b, int(w.tick)), (behind - c).angle()) <= float(m[2]) + 0.002, "...and is laid on that point 40 ticks later")
	check(Counterdrone.intercept_strike(w, M, behind, "cruise"), "the CIWS (never spent) intercepts the next one there: it is laid")
	var ev0: Dictionary = {}
	for ev in w.events:
		if String(ev.type) == "CiwsIntercept":
			ev0 = ev
	check_eq(int(ev0.get("lay_ticks", -1)), 0, "an already-laid head intercepts with no lay time")
	_run(w, 110, false)
	# 60 deg off the head: inside the window: accepted with a lay time, the head then swings onto the point
	cur = Trav.bearing(w, b, int(w.tick))
	var side := c + Vector2.from_angle(cur + deg_to_rad(60.0)) * 4.0
	check(Counterdrone.intercept_strike(w, M, side, "cruise"), "a strike 60 deg off the head is within its lay window")
	var lt := -1
	for ev in w.events:
		if String(ev.type) == "CiwsIntercept":
			lt = int(ev.get("lay_ticks", -1))
	check(lt > 0 and lt <= 15, "CiwsIntercept carries the lay time (%d ticks)" % lt)
	_run(w, lt + 2, false)
	check(_adiff(Trav.bearing(w, b, int(w.tick)), (side - c).angle()) <= float(m[2]) + 0.002, "the head swung onto the point within the lay time (%.1f deg off)" % rad_to_deg(_adiff(Trav.bearing(w, b, int(w.tick)), (side - c).angle())))
	_ciws_restore()


## Same seed, same run: the CIWS lay state is hashed and replays.
func test_ciws_lay_deterministic() -> void:
	var hs := []
	for k in 2:
		var s := _ciws_world()
		var w: SimWorld = s[0]
		var c: Vector2 = s[2]
		_unit(w, "m_micro_drone", M, c + Vector2(-5.0, 1.0))
		Counterdrone.intercept_strike(w, M, c + Vector2(3.0, 3.0), "cruise")
		_run(w, 90, false)
		hs.append(w.state_hash())
		_ciws_restore()
	check_eq(hs[0], hs[1], "two identical CIWS runs hash the same")
