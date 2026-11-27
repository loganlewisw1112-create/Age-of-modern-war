extends "res://tests/test_base.gd"
## G7.1 BASTION71 acceptance (sim/systems/turrets71.gd, sensors71.gd, content/g71/defs_g71_defences.json):
## rotary spin-up / heat / forced cooldown / pierce, laser dwell + smoke cut, HPM cone + recharge, flak fuse,
## disabled-not-dead + revive (direct + turret_revive command), determinism. Turrets71 / Sensors71 tick inside
## w.step() (SYSTEM_ORDER, ORCH 2026-11-21): no hand tick.

const T = preload("res://sim/systems/turrets71.gd")
const S = preload("res://sim/systems/sensors71.gd")
const LP = preload("res://sim/systems/last_protocol.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const Traverse7 = preload("res://sim/systems/traverse7.gd")
const NOFIRE := 100000
const H := 0
const M := 1
const POWERED := ["a_g71_rotary_rail", "a_g71_laser_ciws", "a_g71_hpm"]


func _setup(lp := false) -> SimWorld:
	var w := make_world({"seed": 7, "victory": "endless", "sides": [
		{"faction": "human_a", "stage": 10, "credits": 50000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": 10, "credits": 50000, "ai": false, "name": "M", "team": 1}]})
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
	if lp:
		w.cfg["mode"] = LP.MODE
	for d in POWERED:
		Content.building(d).requires_power = false
	return w


func _restore() -> void:
	for d in POWERED:
		Content.building(d).requires_power = true


func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].order = {"type": "hold"}
	w.entities[id].cd_ticks = NOFIRE
	return id


func _run(w: SimWorld, n: int) -> Array:
	var out := []
	for i in n:
		w.step()
		out.append_array(w.events)
	return out


func _count(evs: Array, type: String) -> int:
	var n := 0
	for ev in evs:
		if String(ev.type) == type:
			n += 1
	return n


func _shots_by(evs: Array, sid: int) -> int:   # other LP shooters (the LP garrison) may hit the same target
	var n := 0
	for ev in evs:
		if String(ev.type) == "ShotFired" and int(ev.get("shooter", -1)) == sid:
			n += 1
	return n


func test_defs() -> void:
	var ids: Array = T.defs()
	check_eq(ids.size(), 4, "four Turrets71 defs")
	for d in ids:
		var b := Content.building(String(d))
		check(not b.has("weapon") and not b.has("t7"), "%s has no def.weapon / t7 (Turrets71 drives it)" % d)
		check(not T.weapon_of(String(d)).is_empty(), "%s weapon row exists" % d)
	check(Content.building("a_g71_sonic_sensor").has("s71"), "sonic sensor def")


func test_rotary_spinup_heat_cooldown_pierce() -> void:
	var w := _setup()
	var bid := w.spawn_building("a_g71_rotary_rail", H, Vector2i(20, 20), true)
	# a line of swarm units straight east of the turret
	var ids := []
	for i in 6:
		ids.append(_unit(w, "m_scout_crawler", M, Vector2(26.5 + float(i) * 1.5, 21.5)))
		w.entities[ids[i]].hp = 100000.0
		w.entities[ids[i]].max_hp = 100000.0
	var evs := _run(w, 14)
	check_eq(_count(evs, "ShotFired"), 0, "no slug before the barrels spun up (14 ticks)")
	evs = _run(w, 120)
	check(_count(evs, "ShotFired") > 10, "slugs at minigun rate once spun up: %d" % _count(evs, "ShotFired"))
	var pierced := 0
	for ev in evs:
		if String(ev.type) == "T71Rail":
			pierced = maxi(pierced, int(ev.n))
	check(pierced >= 3, "a slug pierces through the line: %d" % pierced)
	check(T.heat_of(w, w.entities[bid]) > 0 or T.cooling(w, w.entities[bid]), "heat built up")
	var cooled := false
	for i in 400:
		var e := _run(w, 5)
		if _count(e, "T71Cool") > 0:
			cooled = true
			break
	check(cooled, "forced cooldown triggered at max heat")
	_restore()


func test_traverse_lays_before_fire() -> void:
	var Tr = load("res://sim/systems/traverse7.gd")
	var w := _setup()
	var bid := w.spawn_building("a_g71_rotary_rail", H, Vector2i(20, 20), true)
	var b: Dictionary = w.entities[bid]
	check_eq(Tr.mode_of(b), Tr.MOUNT_BLD, "the rotary railgun is a traversing building mount")
	var rate := float(Tr.mount(b)[1]) * SimWorld.TICK_RATE
	check(absf(rad_to_deg(rate) - float(T.cfg_of("a_g71_rotary_rail").traverse_deg)) < 0.5, "rate from t71.traverse_deg: %f" % rad_to_deg(rate))
	# target straight west: the mount rests toward the map centre, so it must slew before the first slug
	var u := _unit(w, "m_scout_crawler", M, Vector2(12.5, 21.0))
	w.entities[u].hp = 100000.0
	w.entities[u].max_hp = 100000.0
	var slew0 := int(Tr.counters.slew)
	var evs := _run(w, 200)
	check(int(Tr.counters.slew) > slew0, "the mount slewed onto the target (Traverse7 slew count)")
	check(_count(evs, "ShotFired") > 0, "and fires once laid")
	var tb := float(Tr.bearing(w, w.entities[bid], w.tick))
	check(absf(wrapf(tb - PI, -PI, PI)) < 0.3, "bearing points at the target (west): %f" % tb)
	_restore()


func test_laser_dwell_and_smoke() -> void:
	var w := _setup()
	var bid := w.spawn_building("a_g71_laser_ciws", H, Vector2i(20, 20), true)
	var d := _unit(w, "m_micro_drone", M, Vector2(24.5, 20.5))
	var evs := _run(w, 6)
	check(w.entities.has(d), "the drone survives the first dwell ticks")
	evs.append_array(_run(w, 60))
	check(not w.entities.has(d), "held beam burns the drone down")
	check(_count(evs, "T71BeamKill") >= 1, "beam kill event")
	check_eq(int(w.entities[bid].hp), int(w.entities[bid].max_hp), "turret untouched")
	_restore()


func test_hpm_cone_and_recharge() -> void:
	var w := _setup()
	var bid := w.spawn_building("a_g71_hpm", H, Vector2i(20, 20), true)
	for i in 4:
		_unit(w, "m_swarm", M, Vector2(23.5, 19.5 + float(i) * 0.6))
	var behind := _unit(w, "m_swarm", M, Vector2(15.5, 20.5))
	var evs := _run(w, 40)
	check_eq(_count(evs, "T71Hpm"), 1, "one HPM pulse for the cone")
	var n := 0
	for ev in evs:
		if String(ev.type) == "T71Hpm":
			n = int(ev.n)
	check(n >= 3, "cone fried the swarm: %d" % n)
	check(w.entities.has(behind) and String(w.entities[behind].get("ew7", "")) == "", "unit behind the emitter untouched")
	evs = _run(w, 100)
	check_eq(_count(evs, "T71Hpm"), 0, "long recharge: no second pulse within 5 s")
	_restore()


func test_flak_fuse() -> void:
	var w := _setup()
	w.spawn_building("a_g71_flak", H, Vector2i(20, 20), true)
	var lone := _unit(w, "m_micro_drone", M, Vector2(28.5, 40.5))
	var evs := _run(w, 20)
	check_eq(_count(evs, "T71Flak"), 0, "a lone aircraft does not trip the fuse")
	for i in 4:
		_unit(w, "m_micro_drone", M, Vector2(26.5 + float(i) * 0.5, 22.5))
	evs = _run(w, 20)
	check(_count(evs, "T71Flak") >= 1, "a cloud inside the fuse radius bursts")
	check(w.entities.has(lone), "the lone drone is outside the burst")
	_restore()


func test_disabled_not_dead_and_revive() -> void:
	var w := _setup(true)
	var bid := w.spawn_building("a_g71_hpm", H, Vector2i(20, 20), true)
	var b: Dictionary = w.entities[bid]
	w.step()
	check(T.on_zero_hp(w, b), "a lethal hit disables instead of destroying (LP)")
	check(T.disabled(w, b) and T.blocked(w, b), "disabled and blocked")
	check(float(b.hp) > 0.0, "hp floor above zero: %f" % float(b.hp))
	check(not T.on_zero_hp(w, b), "a second lethal hit while disabled destroys")
	for i in 3:
		_unit(w, "m_swarm", M, Vector2(25.5, 19.5 + float(i) * 0.6))
	var evs := _run(w, 40)
	check_eq(_count(evs, "T71Hpm"), 0, "a disabled turret does not fire")
	check(T.revive(w, b, -1), "revive accepted")
	evs = _run(w, 440)
	check(not T.disabled(w, b), "revived")
	check(_count(evs, "T71Revived") == 1, "revive event")
	check(float(b.hp) >= float(b.max_hp) * 0.5 - 1.0, "revived to half hp")
	_restore()


func test_not_lp_never_disables() -> void:
	var w := _setup(false)
	var bid := w.spawn_building("a_g71_hpm", H, Vector2i(20, 20), true)
	check(not T.on_zero_hp(w, w.entities[bid]), "skirmish: no disabled state")
	check(w.sys_state.get("turrets71") == null, "no state created")
	_restore()


func test_determinism() -> void:
	var hs := []
	for k in 2:
		var w := _setup(true)
		w.spawn_building("a_g71_rotary_rail", H, Vector2i(20, 20), true)
		w.spawn_building("a_g71_hpm", H, Vector2i(20, 26), true)
		for i in 8:
			_unit(w, "m_swarm", M, Vector2(27.5 + float(i), 21.0 + float(i % 3)))
		_run(w, 200)
		hs.append(var_to_str(w.sys_state.get("turrets71")).hash())
		_restore()
	check_eq(hs[0], hs[1], "two runs, same turrets71 state")


func test_sensors() -> void:
	var w := _setup()
	w.spawn_building("a_g71_sonic_sensor", H, Vector2i(20, 20), true)
	var cr := _unit(w, "m_scout_crawler", M, Vector2(25.5, 20.5))
	_run(w, 25)
	check_eq(S.contacts(w, H).size(), 0, "a surface crawler is not a sensor contact")
	w.entities[cr].erase("t7")
	_restore()


func test_combat_tower_disabled_holds_fire() -> void:
	# I2 for towers with a def.weapon (Combat._tower_tick guard, ARMY71 CR 1720 / seq 2157): disabled = holds fire
	var w := _setup(true)
	var objective := w.spawn_building("hq", H, Vector2i(65, 65), true)
	w.spawn_building("m_core", M, Vector2i(80, 80), true)
	w.step()
	LP.st(w).facility = objective
	var extent := Vector2(float(w.map.w), float(w.map.h))
	SimWorld.Creep.purge(w, extent * 0.5, extent.length())
	check(T.is_defence("a_wall_tower"), "Combat towers (def.weapon) count as defences")
	var bid := w.spawn_building("a_wall_tower", H, Vector2i(20, 20), true)
	var b: Dictionary = w.entities[bid]
	var u := _unit(w, "m_scout_crawler", M, Vector2(23.5, 21.5))
	w.entities[u].hp = 100000.0
	w.entities[u].max_hp = 100000.0
	w.step()
	if not w.sys_state.has("discipline71"):   # the guard runs where D4 state exists (LP with soldiers); a bare test world has none
		w.sys_state["discipline71"] = {"ver": 1, "sq": {}}
	check(T.on_zero_hp(w, b), "a lethal hit disables the tower instead of destroying it (LP)")
	check(float(b.hp) > 0.0 and w.entities.has(bid), "the tower stays on the map")
	var evs := _run(w, 60)
	check_eq(_shots_by(evs, bid), 0, "a disabled tower does not fire")
	check_eq(int(b.target), -1, "and holds no target")
	check(T.revive(w, b, -1), "revive accepted")
	_run(w, 520)
	check(not w.match_state.ended, "the isolated arena is still running")
	check(not T.disabled(w, b), "revived")
	# fresh targets (the LP garrison kills the first within ~15 ticks). They stand on the tower's current bearing: a
	# target off that bearing needs ~14 ticks of slew (Traverse7, 0.096 rad/tick) and the garrison killed it first
	# (BASTION71-5 .plan/bastion71/dbg_tower.gd: lay() false every tick until the target died, no shot)
	var brg: float = Traverse7.bearing(w, b, int(w.tick))
	for k in 3:
		var dir := Vector2.from_angle(brg + (k - 1) * 0.04)
		var u2 := _unit(w, "m_scout_crawler", M, Vector2(b.pos) + dir * (2.2 + 0.6 * k))
		w.entities[u2].hp = 100000.0
		w.entities[u2].max_hp = 100000.0
	evs = _run(w, 120)
	check(_shots_by(evs, bid) > 0, "the revived tower fires again: %d shots" % _shots_by(evs, bid))
	_restore()


func test_idle_helpers_come_and_revive() -> void:
	# I2: a disabled defence calls the nearest idle engineer (Repair order) / maintenance drone (walks over); Hold kept
	var w := _setup(true)
	var bid := w.spawn_building("a_g71_hpm", H, Vector2i(20, 20), true)
	var b: Dictionary = w.entities[bid]
	var eng := w.spawn_unit("a_g71_siege_engineer", H, Vector2(36.5, 21.5))
	var held := w.spawn_unit("a_g71_siege_engineer", H, Vector2(34.5, 21.5))
	w.entities[held].order = {"type": "hold"}
	w.step()
	check(T.on_zero_hp(w, b), "disabled (LP)")
	var evs := _run(w, 20)
	check_eq(String(w.entities[eng].order.get("type", "")), "repair", "the idle engineer was called")
	check_eq(String(w.entities[held].order.get("type", "")), "hold", "an engineer on Hold Position is never taken")
	check(_count(evs, "T71Call") >= 1, "call event")
	evs = _run(w, 600)
	var by := -99
	for ev in evs:
		if String(ev.type) == "T71Revived":
			by = int(ev.by)
	check(not T.disabled(w, b), "revived after the engineer walked up")
	# the engineer branch ran: the T71Revived event names the called engineer (a base drone revive would say -1;
	# an engineer on its repair order takes over a slower drone revive, so the engineer finishes first)
	check_eq(by, eng, "by the called engineer")
	_restore()
	# a maintenance drone outside its repair radius walks over and revives
	var w2 := _setup(true)
	var bid2 := w2.spawn_building("a_g71_hpm", H, Vector2i(20, 20), true)
	var b2: Dictionary = w2.entities[bid2]
	var dr := w2.spawn_unit("a_g71_maint_drone", H, Vector2(41.5, 21.5))
	w2.step()
	_hold_engineers(w2)   # the LP base's engineers would take over the slower drone revive: this case proves the drone
	check(T.on_zero_hp(w2, b2), "disabled (LP, drone case)")
	_run(w2, 30)
	_hold_engineers(w2)
	check(bool(w2.entities[dr].get("moving", false)) or Vector2(w2.entities[dr].pos).distance_to(Vector2(41.5, 21.5)) > 1.0, "the drone set off")
	var evs2 := _run(w2, 900)
	check(not T.disabled(w2, b2), "the maintenance drone revived it")
	var by2 := -99
	for ev in evs2:
		if String(ev.type) == "T71Revived" and int(ev.id) == bid2:
			by2 = int(ev.by)
	check_eq(by2, -1, "the drone branch ran (T71Revived by -1)")
	_restore()


## Every engineer (def.can_build, not a drone) of side H on Hold Position: never called by Turrets71._helpers.
func _hold_engineers(w: SimWorld) -> void:
	for e in w.entities.values():
		if e.kind == "unit" and int(e.owner) == H:
			var ud := Content.unit(String(e.def))
			if bool(ud.get("can_build", false)) and not ud.has("maint71"):
				e.order = {"type": "hold"}


func test_turret_obeys_painted_sector() -> void:
	# FIRES71 CR seq 2302 line 1: a Turrets7 turret engages only inside its painted kill-zone sector (LP); unpainted = all
	var T7 = load("res://sim/systems/turrets7.gd")
	var KZ = load("res://sim/systems/killzone71.gd")
	var w := _setup(true)
	var bid := w.spawn_building("a_t7_hmg_nest", H, Vector2i(20, 20), true)
	var b: Dictionary = w.entities[bid]
	var c: Dictionary = T7.cfg_of("a_t7_hmg_nest")
	var wd: Dictionary = T7.weapon_of("a_t7_hmg_nest")
	var bc: Vector2 = T7.center(b)
	var east := _unit(w, "m_scout_crawler", M, bc + Vector2(5.0, 0.0))
	var west := _unit(w, "m_scout_crawler", M, bc + Vector2(-5.0, 0.0))
	w.step()
	check(T7.can_engage(w, b, c, wd, w.entities[east]) and T7.can_engage(w, b, c, wd, w.entities[west]), "no sector: both sides engaged")
	var cmd := {"type": "kz_paint", "issuer": H, "building_ids": [bid], "apex": [bc.x, bc.y], "at": [bc.x + 10.0, bc.y], "arc_deg": 60.0}
	check_eq(KZ.validate_command(w, cmd), "", "kz_paint on a turret valid (LP)")
	KZ.apply_command(w, cmd)
	check(T7.can_engage(w, b, c, wd, w.entities[east]), "inside the painted sector: engaged")
	check(not T7.can_engage(w, b, c, wd, w.entities[west]), "outside the painted sector: not engaged")
	_restore()


func test_wounded_engineer_not_called() -> void:
	# BASTION71-6 (survey_g6_on: 380 engineer calls, 359 dropped at once): a wounded engineer has an idle order and does
	# not move, but Medical resets its order every tick, so a call never sticks. Only a healthy engineer is called.
	var w := _setup(true)
	var bid := w.spawn_building("a_g71_hpm", H, Vector2i(20, 20), true)
	var b: Dictionary = w.entities[bid]
	var hurt := w.spawn_unit("a_g71_siege_engineer", H, Vector2(24.5, 21.5))
	var ok := w.spawn_unit("a_g71_siege_engineer", H, Vector2(36.5, 21.5))
	w.step()
	_hold_engineers(w)
	w.entities[ok].order = {"type": "idle"}
	w.entities[hurt].order = {"type": "idle"}
	SimWorld.Medical.wound(w, w.entities[hurt])
	check(bool(w.entities[hurt].get("wounded", false)), "the near engineer is wounded")
	check(T.on_zero_hp(w, b), "disabled (LP)")
	var evs := _run(w, 20)
	var by_hurt := 0
	var by_ok := 0
	for ev in evs:
		if String(ev.type) == "T71Call":
			if int(ev.by) == hurt: by_hurt += 1
			if int(ev.by) == ok: by_ok += 1
	check_eq(by_hurt, 0, "the wounded engineer is never called")
	check(by_ok >= 1, "the healthy engineer is called instead")
	check_eq(String(w.entities[ok].order.get("type", "")), "repair", "and keeps its repair order")
	_restore()


func test_turret_revive_command() -> void:
	var w := _setup(true)
	var bid := w.spawn_building("a_g71_hpm", H, Vector2i(20, 20), true)
	var b: Dictionary = w.entities[bid]
	var eng := w.spawn_unit("a_g71_siege_engineer", H, Vector2(23.5, 21.5))
	w.step()
	var cmd := {"type": "turret_revive", "issuer": H, "unit_ids": [eng], "target_id": bid}
	check(T.validate_command(w, cmd) != "", "an intact turret cannot be revived")
	check(T.validate_command(w, {"type": "turret_nope", "issuer": H, "unit_ids": [eng], "target_id": bid}) != "", "unknown type rejected")
	check(T.on_zero_hp(w, b), "disabled (LP)")
	check(T.validate_command(w, {"type": "turret_revive", "issuer": M, "unit_ids": [eng], "target_id": bid}) != "", "not the enemy's turret")
	check(T.validate_command(w, {"type": "turret_revive", "issuer": H, "unit_ids": [], "target_id": bid}) != "", "needs engineers")
	check_eq(T.validate_command(w, cmd), "", "engineers may revive their disabled turret")
	T.apply_command(w, cmd)
	check(w.sys_state.turrets71.rev.has(bid) and int(w.sys_state.turrets71.rev[bid].by) == eng, "revive job started by the engineer")
	var evs := _run(w, 400)
	check(not T.disabled(w, b), "the engineer revived it")
	check_eq(_count(evs, "T71Revived"), 1, "one revive event")
	_restore()


func _t7_run(w: SimWorld, T7, n: int) -> Array:   # BASTION71-7: only Turrets7 ticks (no LP garrison / AI noise)
	var out := []
	for i in n:
		w.tick += 1
		w.events = []
		T7.tick(w)
		out.append_array(w.events)
	return out


func test_wall_gun_fires_fpf() -> void:
	# FIRES71 CR seq 2302 line 2: while the player's FPF fires on a face, a ground gun on that face's wall band fires
	# toward the face strip (Fires71.fpf_aim) at max rate with no target; no FPF = it holds fire with no target.
	var T7 = load("res://sim/systems/turrets7.gd")
	var F71 = load("res://sim/systems/fires71.gd")
	var KZ = load("res://sim/systems/killzone71.gd")
	var w := SimWorld.new_match(SimWorld.LastProtocol.make_config(4242))
	w.run_ticks(5)
	w.ai_state = {}
	var f := int(w.sys_state.lp.fid)
	w.credit(f, {"ammo": 100000, "credits": 100000, "fuel": 50000}, "test")
	var s: Dictionary = KZ.fpf_strip(w, 0)
	var mid := (Vector2(float(s.a[0]), float(s.a[1])) + Vector2(float(s.b[0]), float(s.b[1]))) * 0.5
	var wall_x := float(KZ.face_line(w, 0)[0].x)
	var bid := w.spawn_building("a_t7_hmg_nest", f, Vector2i(int(wall_x) - 3, int(mid.y)), true)
	var b: Dictionary = w.entities[bid]
	var wd: Dictionary = T7.weapon_of("a_t7_hmg_nest")
	w.spawn_unit("a_mortar", f, mid + Vector2(-9, 0))
	check_eq(_shots_by(_t7_run(w, T7, 100), bid), 0, "no target, no FPF: the gun holds fire")
	check_eq(F71.validate_command(w, {"type": "fpf_fire", "issuer": f, "face": 0}), "", "fpf_fire valid")
	F71.apply_command(w, {"type": "fpf_fire", "issuer": f, "face": 0})
	check(F71.fpf_aim(w, b) != null, "the gun is on face 0's wall band")
	var evs := _t7_run(w, T7, 200)
	var n := 0
	var ok := 0
	for ev in evs:
		if String(ev.type) == "ShotFired" and int(ev.shooter) == bid:
			n += 1
			var to := Vector2(ev.to)
			if bool(ev.get("fpf", false)) and T7.center(b).distance_to(to) <= float(wd.range) + 0.01 \
					and KZ.out_dist(w, 0, to) > KZ.out_dist(w, 0, T7.center(b)) + 1.0:
				ok += 1
	check(n >= int(10.0 / float(wd.cooldown)) - 6, "FPF: max rate with no target (%d shots in 10 s)" % n)
	check(n > 0 and ok == n, "every FPF round goes out toward the strip, within range (%d of %d)" % [ok, n])
	_t7_run(w, T7, int(F71.R().fpf.duration_s * 20.0))
	check_eq(_shots_by(_t7_run(w, T7, 100), bid), 0, "after the FPF: holds fire again")


func test_save_load_mid_wave() -> void:
	# BASTION71-7 (brief Rules: determinism): a save / load in the middle of a fight keeps the same future: rotary
	# spin / heat, a disabled turret with a revive running, wall tier + fit + choke seal, sensors, a dozer clearing.
	var W71 = load("res://sim/systems/walls71.gd")
	var G = load("res://sim/systems/gore71.gd")
	var w := _setup(true)
	w.spawn_building("a_g71_rotary_rail", H, Vector2i(20, 20), true)
	var hpm := w.spawn_building("a_g71_hpm", H, Vector2i(20, 26), true)
	w.spawn_building("a_g71_sonic_sensor", H, Vector2i(16, 22), true)
	var wall := w.spawn_building("a_wall", H, Vector2i(18, 30), true)
	var dz := w.spawn_unit("a_g71_breacher", H, Vector2(14.5, 24.5))
	for i in 8:
		_unit(w, "m_swarm", M, Vector2(27.5 + float(i), 21.0 + float(i % 3)))
	w.step()
	W71.upgrade(w, w.entities[wall], 1)
	W71.fit(w, w.entities[wall], "choke")
	check(T.on_zero_hp(w, w.entities[hpm]), "hpm disabled")
	T.revive(w, w.entities[hpm], -1)
	G.enable(w)
	G.add_body(w, {"kind": "wreck", "def": "m_scout_crawler", "owner": M, "pos": Vector2(14.5, 30.5), "rot": 0.0, "out": "", "t": 0, "sz": 0.6})
	W71.apply_command(w, {"type": "doze_clear", "issuer": H, "unit_ids": [dz], "at": [14.5, 30.5]})
	_run(w, 60)
	check(w.sys_state.has("turrets71") and w.sys_state.has("walls71") and w.sys_state.walls71.has("doze"), "mid-wave state exists")
	var c := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(c.state_hash(), w.state_hash(), "hash equal right after the load")
	var same := true
	for k in 8:
		_run(w, 25)
		_run(c, 25)
		if c.state_hash() != w.state_hash():
			same = false
			check(false, "hash differs %d ticks after the load" % ((k + 1) * 25))
			break
	check(same, "same future for 200 ticks after the load")
	check_eq(var_to_str(c.sys_state.get("walls71")), var_to_str(w.sys_state.get("walls71")), "walls71 state equal")
	check_eq(var_to_str(c.sys_state.get("turrets71")), var_to_str(w.sys_state.get("turrets71")), "turrets71 state equal")
	_restore()


func test_laser_weather_cuts_range() -> void:
	# BASTION71-7 B1: weather that exists (w.cfg.weather, the Accuracy8 key) cuts the laser CIWS range by the def's
	# t71.weather_range_mult (fog x0.45 PROVISIONAL); clear weather / no weather key = full range.
	var kills := []
	for wt in ["", "fog"]:
		var w := _setup()
		if wt != "":
			w.cfg["weather"] = wt
		var bid := w.spawn_building("a_g71_laser_ciws", H, Vector2i(20, 20), true)
		var bc: Vector2 = load("res://sim/systems/turrets7.gd").center(w.entities[bid])
		var rg := float(T.weapon_of("a_g71_laser_ciws").get("range", 14))
		var d := _unit(w, "m_micro_drone", M, bc + Vector2(rg * 0.7, 0.0))
		_run(w, 120)
		kills.append(not w.entities.has(d))
		_restore()
	check(bool(kills[0]), "clear: the drone at 0.7 x range is burnt down")
	check(not bool(kills[1]), "fog: 0.7 x range is beyond the cut range, the drone lives")
