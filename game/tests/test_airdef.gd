extends "res://tests/test_base.gd"
## G6 acceptance (owner: AIRDEF6). CONTRACTS_G6 section 12, section 17: radar-gated SAMs, AWACS, radar warnings.

const Airdef = preload("res://sim/systems/airdef.gd")
const Status = preload("res://sim/systems/status.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")
const NOFIRE := 100000


## Inert 2-side world with a 40x30 GRASS arena (nothing else in or near it); returns [w, arena origin].
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


func _bld(w: SimWorld, def_id: String, fid: int, o: Vector2i, x: int, y: int) -> int:
	return w.spawn_building(def_id, fid, o + Vector2i(x, y), true)


func _run(w: SimWorld, n: int, types: Array = []) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.is_empty() or types.has(String(ev.type)):
				out.append(ev)
	return out


func _shots_by(evs: Array, id: int) -> int:
	var n := 0
	for ev in evs:
		if String(ev.type) == "ShotFired" and int(ev.shooter) == id:
			n += 1
	return n


func test_sam_fires_only_under_radar() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_bld(w, "generator", 0, o, 1, 1)
	_bld(w, "generator", 0, o, 1, 4)
	var sam := _bld(w, "a_sam_site", 0, o, 10, 14)
	var heli := _unit(w, "a_attack_heli", 1, _p(o, 19.0, 15.0))
	var hp0 := float(w.entities[heli].hp)
	check(not Airdef.radar_covers(w, 0, w.entities[heli].pos), "no radar: the heli is not covered")
	var evs := _run(w, 120, ["ShotFired"])
	check_eq(_shots_by(evs, sam), 0, "SAM holds fire with no radar")
	check_eq(float(w.entities[heli].hp), hp0, "heli untouched without radar")
	check_eq(int(w.entities[sam].target), heli, "SAM still tracks the heli (it sees it)")
	check_eq(Status.can_fire(w, w.entities[sam]), "NO_RADAR", "Status.can_fire gates the SAM")
	# an own-only radar (Pulse Spire Mk II) never covers another shooter
	var spire := _bld(w, "m_pulse_spire2", 0, o, 16, 18)
	check(not Airdef.radar_covers(w, 0, w.entities[heli].pos), "own_only radar does not cover for the SAM")
	evs = _run(w, 40, ["ShotFired"])
	check_eq(_shots_by(evs, sam), 0, "SAM still holds fire under an own-only radar")
	w.entities.erase(spire)
	# a radar station covers the heli: the SAM fires and hits
	var radar := _bld(w, "a_radar_station", 0, o, 4, 14)
	check(Airdef.radar_covers(w, 0, w.entities[heli].pos), "radar station covers the heli")
	check(not Airdef.radar_covers(w, 1, w.entities[heli].pos), "the enemy has no radar coverage")
	evs = _run(w, 120, ["ShotFired"])
	check(_shots_by(evs, sam) > 0, "SAM fires under radar")
	check(not w.entities.has(heli) or float(w.entities[heli].hp) < hp0, "SAM damages the heli under radar")
	# radar out of power (power use above production): the SAM is blind again
	check(Airdef.source_active(w, w.entities[radar]), "powered radar active")
	w.factions[0].power_use = 999
	check(not Airdef.source_active(w, w.entities[radar]), "unpowered radar inactive")
	check(not Airdef.radar_covers(w, 0, _p(o, 19.0, 15.0)), "unpowered radar covers nothing")


func test_awacs_reveals_aircraft_and_aa_bonus() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var near := _unit(w, "a_attack_heli", 1, _p(o, 25.0, 15.0))   # 20 from the AWACS: beyond sight 16, inside 24
	var far := _unit(w, "a_attack_heli", 1, _p(o, 36.0, 15.0))    # 31: outside
	var tank := _unit(w, "mbt", 1, _p(o, 22.0, 18.0))
	_run(w, 12)
	check(not Fog.entity_visible(w, 0, w.entities[near]), "heli hidden before the AWACS arrives")
	var aw := _unit(w, "a_awacs", 0, _p(o, 5.0, 15.0))
	var evs := _run(w, 22, ["AwacsReveal"])
	check(not evs.is_empty(), "AwacsReveal emitted")
	check(Fog.entity_visible(w, 0, w.entities[near]), "AWACS reveals the heli at 20 tiles")
	check(not Fog.entity_visible(w, 0, w.entities[far]), "heli at 31 tiles stays hidden")
	var pic := Airdef.air_picture(w, 0)
	check(pic.has(near) and not pic.has(far), "air picture: near heli only (%s)" % str(pic))
	check(not pic.has(tank), "air picture holds aircraft only")
	check(w.sys_state.airdef.picture.get(0, []).has(near), "stored picture for the minimap")
	# AA accuracy bonus inside the AWACS radius
	var aa := _unit(w, "a_spaag", 0, _p(o, 12.0, 15.0))
	var sa := Combat.stats(w.entities[aa])
	check(is_equal_approx(Airdef.acc_mult(w, w.entities[aa], sa, w.entities[near]), 1.2), "AA x1.2 vs aircraft in AWACS radius")
	check(is_equal_approx(Airdef.acc_mult(w, w.entities[aa], sa, w.entities[far]), 1.0), "no bonus outside the radius")
	var hn := G6Hooks.accuracy_mult(w, w.entities[aa], sa, w.entities[near])
	var hf := G6Hooks.accuracy_mult(w, w.entities[aa], sa, w.entities[far])
	check(hf > 0.0 and is_equal_approx(hn / hf, 1.2), "G6Hooks.accuracy_mult carries the AWACS x1.2 (%s / %s)" % [hn, hf])
	check(is_equal_approx(Airdef.acc_mult(w, w.entities[aa], sa, w.entities[tank]), 1.0), "no bonus vs ground targets")
	var enemy_aa := _unit(w, "a_spaag", 1, _p(o, 30.0, 20.0))
	check(is_equal_approx(Airdef.acc_mult(w, w.entities[enemy_aa], Combat.stats(w.entities[enemy_aa]), w.entities[aw]), 1.0),
		"an AWACS does not help the enemy's AA")
	# the AWACS also counts as radar for SAM gating
	check(Airdef.radar_covers(w, 0, w.entities[near].pos), "AWACS radar covers the heli")


func test_radar_warns_incoming_aircraft() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_bld(w, "generator", 0, o, 1, 1)
	_bld(w, "a_radar_station", 0, o, 2, 14)    # centre (3, 15), radius 28
	var out := _unit(w, "a_attack_heli", 1, _p(o, 39.5, 2.0))    # ~38.8 away: outside
	var evs := _run(w, 20, ["RadarContact"])
	check(evs.is_empty(), "no warning while the aircraft is outside radar range")
	var inc := _unit(w, "a_attack_heli", 1, _p(o, 26.0, 15.0))   # 23 away: inside
	evs = _run(w, 20, ["RadarContact"])
	check_eq(evs.size(), 1, "one RadarContact for the incoming aircraft")
	if evs.size() == 1:
		check_eq(int(evs[0].fid), 0, "warning goes to the radar owner")
		check_eq(int(evs[0].id), inc, "warning names the aircraft")
		check(evs[0].has("pos") and evs[0].has("def"), "warning carries pos + def for the minimap")
	check_eq(Airdef.air_picture(w, 0), [inc], "radar picture shows the incoming aircraft only")
	check(not Airdef.air_picture(w, 0).has(out), "aircraft outside range not on the picture")
	evs = _run(w, 60, ["RadarContact"])
	check(evs.is_empty(), "no repeat warning while it stays tracked")
	check(Airdef.air_picture(w, 1).is_empty(), "side without radar sees nothing")
	# saved, hashed, identical after load
	var d := SaveSystem.decode_bytes(SaveSystem.encode_dict(w.to_dict()))
	check(d.ok, "decode ok")
	var l := SimWorld.from_dict(d.dict)
	check_eq(l.state_hash(), w.state_hash(), "hash equal after load")
	var inc2 := _unit(w, "a_attack_heli", 1, _p(o, 20.0, 20.0))
	var inc2l := _unit(l, "a_attack_heli", 1, _p(o, 20.0, 20.0))
	check_eq(inc2l, inc2, "same id after load")
	var ea := _run(w, 30, ["RadarContact"])
	var eb := _run(l, 30, ["RadarContact"])
	check_eq(eb.size(), ea.size(), "same warnings after load")
	check_eq(l.state_hash(), w.state_hash(), "hash equal 30 ticks after load")
