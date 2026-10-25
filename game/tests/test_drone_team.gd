extends "res://tests/test_base.gd"
## G5 acceptance (owner: UNITS5). CONTRACTS_G5 sections 4, 5, 9: the Drone Team.
## Launch each drone type, charges 4 -> 0, the switch to tactical mode, the five tactical abilities,
## restock back to drone mode, drones shot down by AA / jammed by EW, the Human B rigged variant,
## save/load mid-flight.

const G5Mech = preload("res://sim/systems/g5_mech.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const NOFIRE := 100000


## Inert 2-side world with a 30x24 GRASS arena in the map centre; returns [w, arena origin].
func _setup() -> Array:
	var w := make_world()
	w.ai_state = {}
	var mw := int(w.map.w)
	var o := Vector2i(mw / 2 - 15, int(w.map.h) / 2 - 12)
	var r := Rect2i(o, Vector2i(30, 24))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if e.kind != "building" and r.grow(3).has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	Movement.rebuild_nav(w)
	return [w, o]


func _p(o: Vector2i, x: float, y: float) -> Vector2:
	return Vector2(o) + Vector2(x, y)


func _spawn(w: SimWorld, def_id: String, fid: int, pos: Vector2, quiet: bool = true) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
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


func _launch(w: SimWorld, team: int, kind: String, target: Dictionary) -> Array:
	var cmd := {"type": "launch_drone", "unit_id": team, "drone": kind}
	cmd.merge(target)
	return do_cmd(w, 0, cmd)


func _first(evs: Array, type: String):
	for ev in evs:
		if String(ev.type) == type:
			return ev
	return null


## A drone team already in tactical mode (charges spent).
func _tactical_team(w: SimWorld, pos: Vector2) -> int:
	var id := _spawn(w, "a_drone_team", 0, pos)
	w.step()
	w.entities[id].drone_charges = 0
	w.entities[id].dmode = "tactical"
	return id


func test_launch_each_drone_type() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var team := _spawn(w, "a_drone_team", 0, _p(o, 4.5, 12.5))
	var tank := _spawn(w, "mbt", 1, _p(o, 11.5, 12.5))
	var inf := [_spawn(w, "rifleman", 1, _p(o, 10.5, 5.5)), _spawn(w, "rifleman", 1, _p(o, 11.0, 5.8))]
	var mach := _spawn(w, "m_tracked", 1, _p(o, 10.5, 19.5))
	w.run_ticks(3)
	var hp0 := float(w.entities[tank].hp)
	var ev = _first(_launch(w, team, "strike", {"target_id": tank}), "DroneLaunched")
	check(ev != null and String(ev.def) == "a_drone_strike", "strike drone launched")
	var evs := _run(w, 60, ["DroneImpact"])
	check(not evs.is_empty() and String(evs[0].type) == "DroneImpact", "strike drone hits")
	check(not w.entities.has(tank) or float(w.entities[tank].hp) < hp0 - 200.0, "strike: big top-attack hit on the tank")
	var ihp0 := float(w.entities[inf[0]].hp) + float(w.entities[inf[1]].hp)
	_launch(w, team, "frag", {"cell": [o.x + 10, o.y + 5]})
	_run(w, 60)
	var ihp1 := 0.0
	for id in inf:
		ihp1 += float(w.entities[id].hp) if w.entities.has(id) else 0.0
	check(ihp1 < ihp0 - 60.0, "frag: area damage on both soldiers (%s -> %s)" % [ihp0, ihp1])
	_launch(w, team, "recon", {"cell": [o.x + 12, o.y + 12]})
	var mk := _run(w, 60, ["TargetsMarked"])
	check(not mk.is_empty(), "recon drone marks targets")
	check(w.entities.has(mach) and int(w.entities[mach].get("marked_until", -1)) > w.tick, "recon mark on an enemy within range")
	var recon_ids := []
	for id in w.sys_state.g5mech.drones:
		recon_ids.append(id)
	check_eq(recon_ids.size(), 1, "recon drone loiters")
	_launch(w, team, "emp", {"target_id": mach})
	var eb := _run(w, 60, ["EmpBurst"])
	check(not eb.is_empty() and int(eb[0].disabled) >= 1, "emp burst disables the machine")
	check(int(w.entities[mach].get("emp_until", -1)) > w.tick, "machine emp_until set")
	check(int(w.entities[mach].cd_ticks) > 20, "disabled machine holds fire")
	check_eq(G5Mech.drone_charges(w.entities[team]), 0, "four launches spent four charges")


func test_charges_decrement_to_zero() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var team := _spawn(w, "a_drone_team", 0, _p(o, 4.5, 12.5))
	w.step()
	check_eq(G5Mech.drone_charges(w.entities[team]), 4, "4 charges at start")
	for i in 4:
		_launch(w, team, "frag", {"cell": [o.x + 10 + i, o.y + 2]})
		check_eq(G5Mech.drone_charges(w.entities[team]), 3 - i, "charge %d spent" % (i + 1))
	var evs := _launch(w, team, "frag", {"cell": [o.x + 10, o.y + 2]})
	check(rejected_reason(evs).begins_with("No drones left"), "5th launch rejected: '%s'" % rejected_reason(evs))
	check_eq(G5Mech.drone_charges(w.entities[team]), 0, "charges stay 0")


func test_switches_to_tactical_at_zero_charges() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var team := _spawn(w, "a_drone_team", 0, _p(o, 4.5, 12.5))
	w.step()
	check_eq(G5Mech.mode(w.entities[team]), "drone", "starts in drone mode")
	var r := do_cmd(w, 0, {"type": "tactical", "unit_id": team, "ability": "infiltrate"})
	check(rejected_reason(r).begins_with("Tactical abilities unlock"), "tactical locked in drone mode")
	var tac = null
	for i in 4:
		var evs := _launch(w, team, "strike", {"cell": [o.x + 20, o.y + 4 + i * 4]})
		if _first(evs, "DroneTeamTactical") != null:
			tac = i
	check_eq(tac, 3, "DroneTeamTactical on the 4th launch")
	check_eq(G5Mech.mode(w.entities[team]), "tactical", "tactical mode at 0 charges")
	r = do_cmd(w, 0, {"type": "tactical", "unit_id": team, "ability": "infiltrate"})
	check_eq(rejected_reason(r), "", "tactical ability accepted")
	check(_first(r, "Infiltrate") != null, "infiltrate applied")


func test_tactical_abilities_infiltrate_takedown_breach_stack_up_armored() -> void:
	# infiltrate: hidden from the enemy beyond spotting range
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var team := _tactical_team(w, _p(o, 4.5, 12.5))
	_spawn(w, "rifleman", 1, _p(o, 12.5, 12.5))
	do_cmd(w, 0, {"type": "tactical", "unit_id": team, "ability": "infiltrate"})
	w.run_ticks(10)
	check(bool(w.entities[team].hid) and G4bMech.hidden_from(w, 1, w.entities[team]), "infiltrated team hidden")
	# takedown: silent close kill of a lone soldier
	var vic := _spawn(w, "rifleman", 1, _p(o, 7.5, 14.5))
	w.entities[team].tact_cd = 0
	var r := do_cmd(w, 0, {"type": "tactical", "unit_id": team, "ability": "takedown", "target_id": vic})
	check_eq(rejected_reason(r), "", "takedown accepted")
	var evs := _run(w, 120, ["Takedown"])
	check(not evs.is_empty(), "takedown happened")
	check(not w.entities.has(vic) or float(w.entities[vic].hp) <= 1.0, "takedown kills the soldier")
	check(bool(w.entities[team].get("hid", false)), "takedown is silent: still infiltrated")
	# breach: fast charge on a wall
	s = _setup()
	w = s[0]
	o = s[1]
	team = _tactical_team(w, _p(o, 4.5, 12.5))
	var wall := w.spawn_building("b_wall", 1, o + Vector2i(9, 12), true)
	var whp := float(w.entities[wall].hp)
	r = do_cmd(w, 0, {"type": "tactical", "unit_id": team, "ability": "breach", "target_id": wall})
	check_eq(rejected_reason(r), "", "breach accepted")
	evs = _run(w, 200, ["Breach"])
	check(not evs.is_empty(), "breach happened")
	check(not w.entities.has(wall) or float(w.entities[wall].hp) < whp - 500.0, "breach wrecks the wall")
	# stack up, then first-strike burst when an enemy comes close
	w.entities[team].tact_cd = 0
	r = do_cmd(w, 0, {"type": "tactical", "unit_id": team, "ability": "stack_up", "cell": [o.x + 6, o.y + 18]})
	check_eq(rejected_reason(r), "", "stack_up accepted")
	evs = _run(w, 200, ["StackedUp"])
	check(not evs.is_empty() and bool(w.entities[team].stacked), "stacked up at the door")
	var foe := _spawn(w, "rifleman", 1, Vector2(w.entities[team].pos) + Vector2(2.0, 0.0))
	var fhp := float(w.entities[foe].hp)
	evs = _run(w, 5, ["FirstStrike"])
	check(not evs.is_empty(), "first-strike burst")
	check(not w.entities.has(foe) or float(w.entities[foe].hp) < fhp - 40.0, "burst damages the enemy")
	# armored attack: short-range AT rockets, one per soldier
	s = _setup()
	w = s[0]
	o = s[1]
	team = _tactical_team(w, _p(o, 4.5, 12.5))
	var ifv := _spawn(w, "ifv", 1, _p(o, 10.5, 12.5))
	var ihp := float(w.entities[ifv].hp)
	r = do_cmd(w, 0, {"type": "tactical", "unit_id": team, "ability": "armored_attack", "target_id": ifv})
	check_eq(rejected_reason(r), "", "armored_attack accepted")
	evs = _run(w, 200, ["ArmoredAttack"])
	check(not evs.is_empty() and int(evs[0].shots) == 3, "3 AT rockets")
	check(not w.entities.has(ifv) or float(w.entities[ifv].hp) < ihp - 200.0, "AT volley hurts the IFV")
	# takedown refuses a vehicle
	w.entities[team].tact_cd = 0
	var tank := _spawn(w, "mbt", 1, _p(o, 8.5, 16.5))
	r = do_cmd(w, 0, {"type": "tactical", "unit_id": team, "ability": "takedown", "target_id": tank})
	check_eq(rejected_reason(r), "Takedown needs an enemy soldier.", "takedown rejects a vehicle")


func test_restock_returns_to_drone_mode() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var team := _tactical_team(w, _p(o, 4.5, 12.5))
	w.run_ticks(120)
	check_eq(G5Mech.mode(w.entities[team]), "tactical", "no supply source: stays tactical")
	_spawn(w, "logistics_truck", 0, _p(o, 5.5, 12.5))
	var evs := _run(w, G5Mech.RESTOCK_TICKS + 40, ["DronesRestocked"])
	check(not evs.is_empty(), "DronesRestocked near a supply truck")
	check_eq(G5Mech.mode(w.entities[team]), "drone", "back to drone mode")
	check_eq(G5Mech.drone_charges(w.entities[team]), 4, "4 charges again")
	var r := _launch(w, team, "recon", {"cell": [o.x + 10, o.y + 12]})
	check_eq(rejected_reason(r), "", "can launch again after restock")
	# public API (Support trucks call it)
	var t2 := _tactical_team(w, _p(o, 4.5, 3.5))
	G5Mech.restock_drones(w, w.entities[t2])
	check_eq(G5Mech.mode(w.entities[t2]), "drone", "restock_drones() sets drone mode")
	check_eq(G5Mech.drone_charges(w.entities[t2]), 4, "restock_drones() refills")


func test_drones_shot_down_by_aa_and_jammed_by_ew() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var team := _spawn(w, "a_drone_team", 0, _p(o, 1.5, 12.5))
	var aa := _spawn(w, "a_spaag", 1, _p(o, 16.5, 12.5), false)
	w.entities[aa].order = {"type": "hold"}
	w.run_ticks(2)
	var lr := _launch(w, team, "strike", {"cell": [o.x + 20, o.y + 12]})
	check_eq(rejected_reason(lr), "", "strike launched over the SPAAG")
	var evs := _run(w, 120, ["DroneLost", "DroneImpact", "ShotFired"])
	var shots := 0
	for ev in evs:
		if String(ev.type) == "ShotFired" and int(ev.shooter) == aa:
			shots += 1
	check(shots > 0, "SPAAG fires at the drone")
	check(_first(evs, "DroneLost") != null and _first(evs, "DroneImpact") == null, "drone shot down before impact")
	check(w.sys_state.g5mech.drones.is_empty(), "flight record cleared")
	# EW: an enemy jammer within range downs the drone
	s = _setup()
	w = s[0]
	o = s[1]
	team = _spawn(w, "a_drone_team", 0, _p(o, 1.5, 12.5))
	var ew := _spawn(w, "b_jammer_truck", 1, _p(o, 16.5, 12.5))
	w.entities[ew].order = {"type": "hold"}
	w.run_ticks(2)
	_launch(w, team, "frag", {"cell": [o.x + 20, o.y + 12]})
	evs = _run(w, 120, ["DroneJammed", "DroneImpact"])
	check(_first(evs, "DroneJammed") != null and _first(evs, "DroneImpact") == null, "drone jammed by EW")
	# EMP drone downs enemy drones in its radius
	s = _setup()
	w = s[0]
	o = s[1]
	var ta := _spawn(w, "a_drone_team", 0, _p(o, 2.5, 12.5))
	var tb := _spawn(w, "b_drone_team", 1, _p(o, 26.5, 12.5))
	w.run_ticks(2)
	do_cmd(w, 1, {"type": "launch_drone", "unit_id": tb, "drone": "recon", "cell": [o.x + 14, o.y + 12]})
	_run(w, 40)
	check_eq(w.sys_state.g5mech.drones.size(), 1, "enemy recon drone loitering")
	_launch(w, ta, "emp", {"cell": [o.x + 14, o.y + 12]})
	evs = _run(w, 60, ["EmpBurst"])
	check(not evs.is_empty() and int(evs[0].drones_downed) == 1, "EMP downs the enemy drone")


func test_human_b_drones_rigged_variant() -> void:
	Content.load_all()
	for k in G5Mech.DRONE_TYPES:
		var a := Content.unit("a_drone_" + k)
		var b := Content.unit("b_drone_" + k)
		check(bool(a.launched_drone) and bool(b.launched_drone), "%s drones defined" % k)
		check_eq(String(b.move_class), "air_low", "b %s is air_low" % k)
		check(int(b.hp) <= int(a.hp), "b %s flimsier" % k)
	check(float(Content.unit("b_drone_strike").spread) > 0.0 and float(Content.unit("a_drone_strike").spread) == 0.0, "B spreads, A does not")
	check(int(Content.production("b_drone_team").cost.credits) < int(Content.production("a_drone_team").cost.credits), "B team cheaper")
	var pts := []
	for run in 2:
		var s := _setup()
		var w: SimWorld = s[0]
		var o: Vector2i = s[1]
		var ta := _spawn(w, "a_drone_team", 0, _p(o, 2.5, 4.5))
		var tb := _spawn(w, "b_drone_team", 0, _p(o, 2.5, 18.5))
		w.entities[tb].owner = 0
		w.step()
		_launch(w, ta, "strike", {"cell": [o.x + 12, o.y + 4]})
		_launch(w, tb, "strike", {"cell": [o.x + 12, o.y + 18]})
		var evs := _run(w, 60, ["DroneImpact"])
		check_eq(evs.size(), 2, "both impacts")
		for ev in evs:
			var off := Vector2(ev.pos).distance_to(Vector2(ev.aim))
			if int(ev.squad) == ta:
				check(off < 0.01, "A drone lands on its aim point")
			else:
				check(off > 0.0 and off <= 1.2 + 0.01, "B drone scatters within spread (%s)" % off)
				pts.append(Vector2(ev.pos))
	check(pts.size() == 2 and pts[0] == pts[1], "B scatter is deterministic (seeded)")


func test_save_load_mid_launch() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var team := _spawn(w, "a_drone_team", 0, _p(o, 2.5, 12.5))
	_spawn(w, "mbt", 1, _p(o, 22.5, 12.5))
	w.run_ticks(2)
	_launch(w, team, "strike", {"cell": [o.x + 22, o.y + 12]})
	_launch(w, team, "recon", {"cell": [o.x + 18, o.y + 8]})
	w.run_ticks(5)
	check_eq(w.sys_state.g5mech.drones.size(), 2, "two drones in flight")
	var d := SaveSystem.decode_bytes(SaveSystem.encode_dict(w.to_dict()))
	check(d.ok, "decode ok: %s" % d.reason)
	var l := SimWorld.from_dict(d.dict)
	check_eq(l.state_hash(), w.state_hash(), "hash equal right after load")
	check_eq(l.sys_state.g5mech.drones.size(), 2, "flights survive the load")
	check_eq(G5Mech.drone_charges(l.entities[team]), 2, "charges survive the load")
	var ea := _run(w, 80, ["DroneImpact", "TargetsMarked"])
	var eb := _run(l, 80, ["DroneImpact", "TargetsMarked"])
	check_eq(eb.size(), ea.size(), "same drone events after load")
	check_eq(l.state_hash(), w.state_hash(), "hash equal 80 ticks after load")
