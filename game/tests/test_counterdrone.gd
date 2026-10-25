extends "res://tests/test_base.gd"
## G6 acceptance (owner: AIRDEF6). CONTRACTS_G6 section 12, section 17: Laser CIWS, nets, jamming fields, scrap AA.

const Airdef = preload("res://sim/systems/airdef.gd")
const Counterdrone = preload("res://sim/systems/counterdrone.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const NOFIRE := 100000


## Inert 2-side world with a 40x30 GRASS arena (no units in or near it); returns [w, arena origin].
func _setup() -> Array:
	var w := make_world()
	w.ai_state = {}
	var mw := int(w.map.w)
	var o := Vector2i(mw / 2 - 20, int(w.map.h) / 2 - 15)
	var r := Rect2i(o, Vector2i(40, 30))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.grow(16).has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	Movement.rebuild_nav(w)
	return [w, o]


func _p(o: Vector2i, x: float, y: float) -> Vector2:
	return Vector2(o) + Vector2(x, y)


func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2, quiet: bool = true) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].order = {"type": "hold"}
	if quiet:
		w.entities[id].cd_ticks = NOFIRE
	return id


func _bld(w: SimWorld, def_id: String, fid: int, o: Vector2i, x: int, y: int, quiet: bool = false) -> int:
	var id := w.spawn_building(def_id, fid, o + Vector2i(x, y), true)
	if quiet:
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


func _first(evs: Array, type: String):
	for ev in evs:
		if String(ev.type) == type:
			return ev
	return null


## Side 1's drone team at (1.5, 12.5) launches `kind` at arena cell (cx, cy). Returns the drone id.
func _launch(w: SimWorld, o: Vector2i, kind: String, cx: int, cy: int) -> int:
	var team := _unit(w, "a_drone_team", 1, _p(o, 1.5, 12.5))
	w.run_ticks(2)
	var evs := do_cmd(w, 1, {"type": "launch_drone", "unit_id": team, "drone": kind, "cell": [o.x + cx, o.y + cy]})
	check_eq(rejected_reason(evs), "", "drone launched")
	var ev = _first(evs, "DroneLaunched")
	return int(ev.id) if ev != null else -1


func test_ciws_kills_drones_rockets_shells() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_bld(w, "generator", 0, o, 30, 2)
	var ciws := _bld(w, "a_laser_ciws", 0, o, 18, 12, true)   # centre (18.5, 12.5); weapon silenced: the CIWS layer alone
	var did := _launch(w, o, "strike", 19, 12)
	check(did >= 0, "strike drone in flight")
	var evs := _run(w, 80, ["CiwsKill", "DroneImpact", "DroneLost"])
	var k = _first(evs, "CiwsKill")
	check(k != null and int(k.id) == did and int(k.ciws) == ciws, "CIWS kills the launched drone")
	check(_first(evs, "DroneImpact") == null, "the drone never impacts")
	check(not w.entities.has(did) and w.sys_state.g5mech.drones.is_empty(), "drone gone, flight record cleared")
	# rate limit: the kill spent the CIWS shot (12/min = one per 100 ticks)
	var at := _p(o, 20.0, 13.0)
	check(not Counterdrone.intercept_strike(w, 1, at, "cruise"), "CIWS reloading: no intercept right after a kill")
	_run(w, 100)
	# a cruise strike (MECH6b) landing in radius is intercepted; then the CIWS reloads again
	check(Counterdrone.intercept_strike(w, 1, at, "cruise"), "CIWS intercepts a cruise strike in radius")
	check(not Counterdrone.intercept_strike(w, 1, at, "cruise"), "one intercept per reload")
	_run(w, 100)
	check(not Counterdrone.intercept_strike(w, 1, _p(o, 30.0, 13.0), "cruise"), "no intercept outside radius 6")
	check(not Counterdrone.intercept_strike(w, 0, at, "cruise"), "no intercept of own-side strikes")
	# combat shells and rockets (G6Hooks shot hook): an enemy artillery shot landing in radius is shot down
	var arty := _unit(w, "b_artillery_truck", 1, _p(o, 4.0, 4.0))
	var tgt := _unit(w, "mbt", 0, _p(o, 20.0, 14.0))
	var sa := Combat.stats(w.entities[arty])
	check(bool(sa.indirect), "artillery fires indirect")
	check(Counterdrone.shot_blocked(w, w.entities[arty], sa, w.entities[tgt], w.entities[tgt].pos), "shell intercepted")
	check(not Counterdrone.shot_blocked(w, w.entities[arty], sa, w.entities[tgt], w.entities[tgt].pos), "reloading: the next shell lands")
	_run(w, 100)
	var sr := sa.duplicate()
	sr.salvo = 6
	var evr := []
	check(Counterdrone.shot_blocked(w, w.entities[arty], sr, w.entities[tgt], w.entities[tgt].pos), "rocket intercepted")
	for e2 in w.events:
		if String(e2.type) == "CiwsIntercept":
			evr.append(e2)
	check(not evr.is_empty() and String(evr[-1].kind) == "rocket", "intercept reported as a rocket")
	_run(w, 100)
	var direct := Combat.stats(w.entities[tgt])
	check(not Counterdrone.shot_blocked(w, w.entities[tgt], direct, w.entities[arty], w.entities[arty].pos), "direct fire is never intercepted")
	# unpowered CIWS does nothing
	w.factions[0].power_use = 999
	check(not Counterdrone.intercept_strike(w, 1, at, "cruise"), "unpowered CIWS: no intercept")


func test_net_captures_drone_and_salvage() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var net := _bld(w, "b_net_post", 0, o, 18, 12, true)   # centre (18.5, 12.5); net weapon range 7
	var salv0 := int(w.factions[0].stock.get("salvage", 0))
	var did := _launch(w, o, "strike", 19, 12)
	var evs := _run(w, 80, ["DroneCaptured", "DroneImpact", "EntityDestroyed"])
	var c = _first(evs, "DroneCaptured")
	check(c != null and int(c.id) == did and int(c.net) == net, "net post captures the drone")
	if c != null:
		check_eq(int(c.salvage), 40, "capture pays the net_capture salvage")
		check_eq(int(c.from_owner), 1, "captured from the enemy")
	check(_first(evs, "DroneImpact") == null, "captured drone never impacts")
	var gone = null
	for ev in evs:
		if String(ev.type) == "EntityDestroyed" and int(ev.id) == did:
			gone = ev
	check(gone != null and String(gone.cause) == "captured", "removed intact (cause captured, no wreck)")
	check_eq(int(w.factions[0].stock.get("salvage", 0)) - salv0, 40, "side 0 gains 40 salvage")
	check(w.sys_state.g5mech.drones.is_empty(), "flight record cleared")
	# a drone unit (Machine micro drone) is captured too; own drones never are
	var mine := _unit(w, "m_micro_drone", 0, _p(o, 20.0, 14.0))
	var foe := _unit(w, "m_micro_drone", 1, _p(o, 21.0, 14.0))
	evs = _run(w, 60, ["DroneCaptured"])
	check(_first(evs, "DroneCaptured") != null and int(_first(evs, "DroneCaptured").id) == foe, "enemy micro drone captured")
	check(w.entities.has(mine), "own drone untouched")


func test_jam_field_drops_drones_and_guided_shots() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_bld(w, "generator", 0, o, 30, 2)
	var ob := _bld(w, "m_jammer_obelisk", 0, o, 16, 12)   # centre (16.5, 12.5), radius 7
	var jp := _p(o, 16.5, 12.5)
	check(Counterdrone.jammed(w, jp + Vector2(5, 0), 1), "enemy units inside the field are jammed")
	check(not Counterdrone.jammed(w, jp + Vector2(9, 0), 1), "outside the radius: not jammed")
	check(not Counterdrone.jammed(w, jp, 0), "own units are never jammed")
	var did := _launch(w, o, "frag", 20, 12)
	var evs := _run(w, 100, ["DroneJammed", "DroneImpact"])
	check(_first(evs, "DroneJammed") != null and _first(evs, "DroneImpact") == null, "launched drone drops in the jam field")
	check(not w.entities.has(did), "jammed drone removed")
	# a drone unit inside the field drops too
	var micro := _unit(w, "m_micro_drone", 1, jp + Vector2(2, 1))
	evs = _run(w, 3, ["DroneJammed"])
	check(_first(evs, "DroneJammed") != null and not w.entities.has(micro), "micro drone drops in the field")
	# guided shots aimed into the field drop; unguided and outside shots do not
	var sam := _bld(w, "a_sam_site", 1, o, 2, 2, true)
	var heli := _unit(w, "a_attack_heli", 0, jp + Vector2(3, 0))
	var sg := Combat.stats(w.entities[sam])
	check(bool(sg.guided), "SAM is a guided weapon")
	check(Counterdrone.shot_blocked(w, w.entities[sam], sg, w.entities[heli], w.entities[heli].pos), "guided shot into the field drops")
	var gj = null
	for ev in w.events:
		if String(ev.type) == "GuidedJammed":
			gj = ev
	check(gj != null and int(gj.jammer) == ob, "GuidedJammed names the jammer")
	check(not Counterdrone.shot_blocked(w, w.entities[sam], sg, w.entities[heli], jp + Vector2(12, 0)), "guided shot outside the field flies")
	var ug := sg.duplicate()
	ug.guided = false
	check(not Counterdrone.shot_blocked(w, w.entities[sam], ug, w.entities[heli], w.entities[heli].pos), "unguided shots ignore jamming")
	# Backpack Jammer Team (a unit field, radius 5)
	var jt := _unit(w, "b_jammer_team", 0, _p(o, 30.0, 25.0))
	check(Counterdrone.jammed(w, _p(o, 33.0, 25.0), 1), "jammer team field covers 3 tiles away")
	check(not Counterdrone.jammed(w, _p(o, 36.5, 25.0), 1), "jammer team field ends at 5")
	w.entities.erase(jt)
	# an unpowered obelisk jams nothing
	w.factions[0].power_use = 999
	check(not Counterdrone.jammed(w, jp, 1), "unpowered obelisk: no field")


func test_scrap_aa_anti_drone_bonus() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var scrap := _unit(w, "b_scrap_aa", 0, _p(o, 10.0, 10.0))
	var drone := _unit(w, "a_drone_strike", 1, _p(o, 13.0, 10.0))
	var micro := _unit(w, "m_micro_drone", 1, _p(o, 13.0, 11.0))
	var heli := _unit(w, "a_attack_heli", 1, _p(o, 13.0, 12.0))
	var ss := Combat.stats(w.entities[scrap])
	check(bool(ss.anti_drone), "scrap shotgun is anti_drone")
	check(SimWorld.Air.can_target(Content.weapon(String(ss.weapon)), w.entities[drone]), "scrap AA may engage launched drones")
	check(is_equal_approx(Counterdrone.damage_mult(w, w.entities[scrap], ss, w.entities[drone]), 2.0), "x2 vs a launched drone")
	check(is_equal_approx(Counterdrone.damage_mult(w, w.entities[scrap], ss, w.entities[micro]), 2.0), "x2 vs a micro drone")
	check(is_equal_approx(Counterdrone.damage_mult(w, w.entities[scrap], ss, w.entities[heli]), 1.0), "x1 vs a helicopter")
	var aa := _unit(w, "a_spaag", 0, _p(o, 10.0, 14.0))
	var sa := Combat.stats(w.entities[aa])
	check(is_equal_approx(Counterdrone.damage_mult(w, w.entities[aa], sa, w.entities[drone]), 1.0), "no bonus for weapons without anti_drone_mult")
	# through the G6Hooks dispatcher (ORCH wiring): same shooter + target, anti_drone on vs off = exactly x2
	var plain := ss.duplicate()
	plain.anti_drone = false
	var dm_on := G6Hooks.damage_mult(w, w.entities[scrap], ss, w.entities[drone])
	var dm_off := G6Hooks.damage_mult(w, w.entities[scrap], plain, w.entities[drone])
	check(dm_off > 0.0 and is_equal_approx(dm_on / dm_off, 2.0), "G6Hooks.damage_mult carries the x2 (%s / %s)" % [dm_on, dm_off])
	check(Counterdrone.is_drone(w, w.entities[drone]) and Counterdrone.is_drone(w, w.entities[micro]), "drones classified")
	check(not Counterdrone.is_drone(w, w.entities[heli]), "a helicopter is not a drone")


## No CIWS, jammer, net post or AWACS: every AIRDEF6 delegate is neutral, no state is created, no events fire.
func test_neutral_without_air_defence() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var team := _unit(w, "a_drone_team", 1, _p(o, 1.5, 12.5))
	var arty := _unit(w, "b_artillery_truck", 1, _p(o, 4.0, 4.0))
	var aa := _unit(w, "a_spaag", 0, _p(o, 20.0, 12.0))
	var heli := _unit(w, "a_attack_heli", 1, _p(o, 22.0, 12.0))
	w.run_ticks(2)
	do_cmd(w, 1, {"type": "launch_drone", "unit_id": team, "drone": "strike", "cell": [o.x + 19, o.y + 12]})
	var evs := _run(w, 60, ["CiwsKill", "CiwsIntercept", "DroneCaptured", "GuidedJammed", "RadarContact", "AwacsReveal"])
	check(evs.is_empty(), "no air-defence events without air-defence entities")
	check(not w.sys_state.has("airdef") and not w.sys_state.has("counterdrone"), "no airdef/counterdrone state created")
	check_eq(G6Hooks.active(w) & G6Hooks.G6_SHOT, 0, "shot hook bit clear")
	var sa := Combat.stats(w.entities[aa])
	check(is_equal_approx(Airdef.acc_mult(w, w.entities[aa], sa, w.entities[heli]), 1.0), "acc_mult neutral")
	var st := Combat.stats(w.entities[arty])
	check(not Counterdrone.shot_blocked(w, w.entities[arty], st, w.entities[aa], w.entities[aa].pos), "shell not blocked")
	check(not G6Hooks.shot_blocked(w, w.entities[arty], st, w.entities[aa], w.entities[aa].pos), "G6Hooks.shot_blocked false")
	check(Airdef.radar_covers(w, 0, w.entities[heli].pos) == false and Airdef.air_picture(w, 0).is_empty(), "no radar picture")
	_bld(w, "a_laser_ciws", 0, o, 30, 20, true)
	check(G6Hooks.active(w) & G6Hooks.G6_SHOT != 0, "shot hook bit set once a CIWS exists")


## End to end through Combat._fire (PERF6-2 call site of G6Hooks.shot_blocked under SimIndex.G6_SHOT, CR 492):
## enemy howitzer shells aimed at a tank under a powered Laser CIWS are shot down.
func test_ciws_intercepts_live_artillery() -> void:
	check((SimIndex as Script).get_script_constant_map().has("G6_SHOT"), "combat shot hook bit defined")
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_bld(w, "generator", 0, o, 34, 2)
	_bld(w, "a_laser_ciws", 0, o, 24, 14, true)
	var tank := _unit(w, "mbt", 0, _p(o, 25.0, 16.0))
	_unit(w, "a_spaag", 1, _p(o, 22.0, 18.0))   # spotter for side 1 (silenced)
	var arty := _unit(w, "b_artillery_truck", 1, _p(o, 12.0, 16.0), false)   # 13 from the tank: range 16, min 5
	var evs := _run(w, 400, ["CiwsIntercept", "ShotFired"])
	var shots := 0
	var icp := 0
	for ev in evs:
		if String(ev.type) == "ShotFired" and int(ev.shooter) == arty:
			shots += 1
		elif String(ev.type) == "CiwsIntercept" and int(ev.attacker) == 1:
			icp += 1
	check(shots > 0, "howitzer fires at the tank")
	check(icp > 0, "CIWS intercepts live shells (%d of %d)" % [icp, shots])
	check(w.entities.has(tank), "tank survives")


## End to end: a radar-covered enemy SAM fires at a helicopter inside an own Jammer Obelisk field; every guided
## missile drops (GuidedJammed) and the helicopter takes no damage. Without the field the same SAM hits it.
func test_jam_drops_live_guided_shots() -> void:
	for jam in [true, false]:
		var s := _setup()
		var w: SimWorld = s[0]
		var o: Vector2i = s[1]
		_bld(w, "generator", 0, o, 34, 2)
		_bld(w, "generator", 1, o, 1, 1)
		_bld(w, "a_radar_station", 1, o, 2, 24)
		var sam := _bld(w, "a_sam_site", 1, o, 10, 14)
		if jam:
			_bld(w, "m_jammer_obelisk", 0, o, 22, 14)
		var heli := _unit(w, "a_attack_heli", 0, _p(o, 20.0, 15.0))
		var hp0 := float(w.entities[heli].hp)
		var evs := _run(w, 200, ["ShotFired", "GuidedJammed"])
		var shots := 0
		var dropped := 0
		for ev in evs:
			if String(ev.type) == "ShotFired" and int(ev.shooter) == sam:
				shots += 1
			elif String(ev.type) == "GuidedJammed" and int(ev.shooter) == sam:
				dropped += 1
		check(shots > 0, "SAM fires (jam=%s)" % jam)
		if jam:
			check_eq(dropped, shots, "every guided missile into the field drops")
			check_eq(float(w.entities[heli].hp), hp0, "heli untouched inside the jam field")
		else:
			check_eq(dropped, 0, "no jamming without a field")
			check(not w.entities.has(heli) or float(w.entities[heli].hp) < hp0, "SAM hits the heli without a field")
