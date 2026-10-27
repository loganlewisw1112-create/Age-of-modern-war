extends "res://tests/test_base.gd"
## G7 acceptance (owner: DRONE7). G7_REFERENCE master scope section 1: player-flown drones.

const DronePilot = preload("res://sim/systems/drone_pilot.gd")
const Strikes = preload("res://sim/systems/strikes.gd")
const Movement = preload("res://sim/systems/movement.gd")
const NOFIRE := 100000


## Merges content/g7 when ORCH has not added it to Content.FRAGMENT_DIRS yet (CR content_g7_fragments).
func _ensure_g7() -> void:
	if Content.unit("g7_a_fpv").is_empty():
		Content._merge_fragment_dir("res://content/g7")


## Inert 2-side world with a 40x30 GRASS arena; returns [w, arena origin].
func _setup() -> Array:
	var w := make_world()
	_ensure_g7()
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


func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2, quiet: bool = true) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].order = {"type": "hold"}
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


## Side 0's drone team at arena (5.5, 15.5) launches `kind`; returns [team id, drone id].
func _launch(w: SimWorld, o: Vector2i, kind: String) -> Array:
	var team := _unit(w, "a_drone_team", 0, Vector2(o) + Vector2(5.5, 15.5))
	w.entities[team].facing = 0.0   # setup (ORCH ruling on need 2471): spawn_unit now faces the owner's front (need 2223); launches (drone heading = team facing) were built on the old east-facing default
	w.run_ticks(2)
	var evs := do_cmd(w, 0, {"type": "drone_take", "unit_id": team, "launch": kind})
	check_eq(rejected_reason(evs), "", "drone_take launch %s" % kind)
	var ev = _first(evs, "DroneTaken")
	return [team, int(ev.id) if ev != null else -1]


func _steer(w: SimWorld, id: int, hdg: float, fwd: float, h: float, side: float = 0.0) -> void:
	do_cmd(w, 0, {"type": "drone_steer", "unit_id": id, "hdg": hdg, "fwd": fwd, "side": side, "h": h})


func test_take_steer_validate() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var foe := _unit(w, "rifleman", 1, Vector2(o) + Vector2(35.5, 3.5))
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "drone_take", "unit_id": foe})), "Not your drone.", "foe rejected")
	var ids := _launch(w, o, "recon")
	var id: int = ids[1]
	check(id > 0 and DronePilot.is_piloted(w, id), "recon drone launched and flown")
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "drone_take", "unit_id": id})), "Already flown.", "no double take")
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "drone_release", "unit_id": id})), "Only a strike drone drops munitions.", "recon cannot drop")
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "drone_detonate", "unit_id": id})), "Only an FPV drone detonates.", "recon cannot detonate")
	var p0: Vector2 = w.entities[id].pos
	_steer(w, id, 0.0, 1.0, 80.0)   # north, full speed, climb
	w.run_ticks(40)
	var e: Dictionary = w.entities[id]
	check(Vector2(e.pos).y < p0.y - 3.0, "flew north (%s -> %s)" % [p0, e.pos])
	check(absf(Vector2(e.pos).x - p0.x) < 4.0, "turned onto north and held it (x %.2f -> %.2f)" % [p0.x, Vector2(e.pos).x])
	check(float(e.drone_h) > 50.0, "climbed (h %s)" % e.drone_h)
	_steer(w, id, 90.0, 1.0, 80.0)   # turn east
	var p1: Vector2 = w.entities[id].pos
	w.run_ticks(40)
	check(Vector2(w.entities[id].pos).x > p1.x + 2.0, "turned east and flew")
	var evs := do_cmd(w, 0, {"type": "drone_return", "unit_id": id, "to": "ai"})
	check(_first(evs, "DroneReleased") != null, "B hands control back")
	check_eq(String(DronePilot.record(w, id).mode), "ai", "drone hovers under AI")


func test_strike_drop_ballistics() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var ids := _launch(w, o, "strike")
	var id: int = ids[1]
	var r: Dictionary = DronePilot.record(w, id)
	check_eq(String(r.kind), "strike", "strike kind")
	var drops := int(r.drops)
	r.link_range = 200.0   # this test is about ballistics, not link range
	check(drops >= 3, "strike drone carries drops (%d)" % drops)
	_steer(w, id, 90.0, 1.0, 40.0)
	w.run_ticks(60)
	var e: Dictionary = w.entities[id]
	var vel: Vector2 = r.vel
	var h := float(r.h)
	var t := sqrt(2.0 * h / DronePilot.rf("gravity", 9.8))
	var expect: Vector2 = Vector2(e.pos) + vel * t
	var foe := _unit(w, "rifleman", 1, expect)
	var hp0 := float(w.entities[foe].hp)
	var evs := do_cmd(w, 0, {"type": "drone_release", "unit_id": id})
	var away = _first(evs, "DroneMunitionAway")
	check(away != null, "MUNITION AWAY")
	if away == null:
		return
	var drift := DronePilot.rf("drift_per_100m", 0.8) * h / 100.0
	var off: float = Vector2(away.at).distance_to(expect)
	check(vel.length() > 3.0 and off <= drift * 1.5 + 0.2, "lands ahead by velocity x fall time with drift (off %.3f, drift %.3f, vel %s)" % [off, drift, vel])
	check_eq(int(away.eta), maxi(roundi(t * 20.0), 1), "fall time ticks")
	_steer(w, id, 0.0, 1.0, 40.0)   # break away: the bomb keeps the drone's velocity, so it lands under it
	var blasts := _run(w, int(away.eta) + 2, ["DroneBlast"])
	check(not blasts.is_empty(), "munition went off")
	if not blasts.is_empty():
		check_eq(String(blasts[0].surface), "soldier", "blast type soldier")
	check(not w.entities.has(foe) or float(w.entities[foe].hp) < hp0, "soldier hit")
	check_eq(int(DronePilot.record(w, id).drops), drops - 1, "one drop used")
	for i in drops - 1:
		do_cmd(w, 0, {"type": "drone_release", "unit_id": id})
	check_eq(String(DronePilot.record(w, id).mode), "return", "empty strike drone returns")
	var charges := int(w.entities[ids[0]].drone_charges)
	var rec := _run(w, 400, ["DroneRecovered"])
	check(not rec.is_empty(), "recovered at its team")
	check_eq(int(w.entities[ids[0]].drone_charges), charges + 1, "charge back")


func test_fpv_detonation() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var ids := _launch(w, o, "fpv")
	var id: int = ids[1]
	var tank := _unit(w, "mbt", 1, Vector2(o) + Vector2(15.5, 15.5))
	var hp0 := float(w.entities[tank].hp)
	_steer(w, id, 90.0, 0.0, 2.0)   # face east, dive to 2 m
	w.run_ticks(70)
	check(float(DronePilot.record(w, id).h) <= 2.5, "FPV dove low")
	_steer(w, id, 90.0, 0.6, 2.0)
	var evs := _run(w, 120, ["DroneDetonated", "DroneBlast"])
	var det = _first(evs, "DroneDetonated")
	check(det != null and String(det.cause) == "contact", "FPV dove into the tank (%s)" % str(det))
	check(not w.entities.has(id), "FPV is single use")
	check(not w.entities.has(tank) or float(w.entities[tank].hp) < hp0, "tank damaged")
	var ids2 := _launch(w, o, "fpv")
	_steer(w, ids2[1], 0.0, 0.5, 30.0)
	w.run_ticks(20)
	var evs2 := do_cmd(w, 0, {"type": "drone_detonate", "unit_id": ids2[1]})
	var b = _first(evs2, "DroneBlast")
	check(b != null and String(b.surface) == "air", "C detonates: air burst at height")


func test_jam_and_range_cut_link() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var ids := _launch(w, o, "recon")
	var id: int = ids[1]
	DronePilot.record(w, id).link_range = 6.0
	_steer(w, id, 0.0, 1.0, 40.0)
	var evs := _run(w, 80, ["DroneLinkLost"])
	var ll = _first(evs, "DroneLinkLost")
	check(ll != null and String(ll.reason) == "range", "out of range: LINK LOST (%s)" % str(ll))
	check(w.entities.has(id) and String(DronePilot.record(w, id).mode) == "return", "recon flies home on its own")
	var ids2 := _launch(w, o, "fpv")
	_unit(w, "b_jammer_team", 1, Vector2(o) + Vector2(16.5, 15.5))
	w.run_ticks(2)
	_steer(w, ids2[1], 90.0, 0.5, 20.0)
	var evs2 := _run(w, 100, ["DroneLinkLost"])
	var jl = null
	for ev in evs2:
		if int(ev.id) == int(ids2[1]):
			jl = ev
	check(jl != null and String(jl.reason) == "jam", "jammer cuts the link (%s)" % str(jl))
	check(not w.entities.has(ids2[1]), "jammed FPV crashed")


## Plays a scripted flight; returns [hash, command log]. With `log` given, replays those commands instead.
func _flight(log: Array) -> Array:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var team := _unit(w, "a_drone_team", 0, Vector2(o) + Vector2(5.5, 15.5))
	_unit(w, "rifleman", 1, Vector2(o) + Vector2(20.5, 12.5))
	var out := []
	if log.is_empty():
		var script := [[3, {"type": "drone_take", "unit_id": team, "launch": "strike"}],
			[5, {"type": "drone_steer", "unit_id": team + 2, "hdg": 80.0, "fwd": 1.0, "side": 0.0, "h": 50.0}],
			[31, {"type": "drone_steer", "unit_id": team + 2, "hdg": 120.0, "fwd": 0.7, "side": 0.3, "h": 30.0}],
			[47, {"type": "drone_release", "unit_id": team + 2}],
			[60, {"type": "drone_steer", "unit_id": team + 2, "hdg": 300.0, "fwd": 1.0, "side": -0.5, "h": 60.0}],
			[75, {"type": "drone_release", "unit_id": team + 2}]]
		var t0 := w.tick
		for it in script:
			while w.tick < t0 + int(it[0]):
				w.step()
			var c: Dictionary = it[1].duplicate(true)
			c.issuer = 0
			c.tick = w.tick + 1
			out.append(c.duplicate(true))
			w.submit(c)
		while w.tick < t0 + 160:
			w.step()
	else:
		for c in log:
			w.submit(c.duplicate(true))
		while w.tick < int(log[0].tick) - 4 + 160:
			w.step()
	return [w.state_hash(), out, DronePilot.st(w) != null and int(DronePilot.st(w).taken) == 1]


func test_replay_and_determinism() -> void:
	var a := _flight([])
	check(bool(a[2]), "flight happened")
	var b := _flight(a[1])
	check_eq(b[0], a[0], "replayed command log gives the identical hash")
	var c := _flight([])
	check_eq(c[0], a[0], "same seed twice = same hash")


func test_no_piloting_unchanged() -> void:
	var w := make_world()
	_ensure_g7()
	w.run_ticks(60)
	check(not w.sys_state.has("drone_pilot"), "no drone_pilot state without piloting")
	var h0 := w.state_hash()
	DronePilot.tick(w)
	check_eq(w.state_hash(), h0, "DronePilot.tick is a no-op without flown drones")


func test_uav_take_and_player_order() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var uav := _unit(w, "a_uav", 0, Vector2(o) + Vector2(10.5, 10.5))
	var evs := do_cmd(w, 0, {"type": "drone_take", "unit_id": uav})
	check_eq(rejected_reason(evs), "", "UAV flyable")
	check_eq(String(DronePilot.record(w, uav).kind), "recon", "UAV is a recon flyer")
	_steer(w, uav, 180.0, 1.0, 60.0)
	w.run_ticks(20)
	check(Vector2(w.entities[uav].pos).y > float(o.y) + 11.0, "UAV flown south")
	var evs2 := do_cmd(w, 0, {"type": "move", "unit_ids": [uav], "target": Vector2(o) + Vector2(30.5, 5.5)})
	evs2.append_array(_run(w, 3))
	check(_first(evs2, "DroneReleased") != null and not DronePilot.is_piloted(w, uav), "a player move order takes it back")


func test_save_roundtrip_mid_flight() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var ids := _launch(w, o, "strike")
	_steer(w, ids[1], 45.0, 1.0, 70.0)
	w.run_ticks(10)
	do_cmd(w, 0, {"type": "drone_release", "unit_id": ids[1]})
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	w.run_ticks(40)
	w2.run_ticks(40)
	check_eq(w2.state_hash(), w.state_hash(), "save round-trip mid-flight continues identically")
