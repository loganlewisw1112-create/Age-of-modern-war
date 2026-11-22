extends "res://tests/test_base.gd"
## G7.1 FIRES71 B6 (docs/G71_SCOPE.md): the CONDUCTOR gunship (sim/systems/conductor71.gd). Orbit through Air's
## air_patrol + Pads71 home pad, side cannon / missile cells on station, wingman hand-off + peel-off strike, laser
## CIWS vs drones, flares (decoy API), kamikaze, home + hot-pit refill, LP-only, determinism + save / load mid orbit.
## Whole-world steps; Conductor71 is ticked by hand only while world.gd does not register it (no double tick after).

const C = preload("res://sim/systems/conductor71.gd")
const Air = preload("res://sim/systems/air.gd")
const Pads71 = preload("res://sim/systems/pads71.gd")
const KZ = preload("res://sim/systems/killzone71.gd")

static var _base: Dictionary = {}


func _ensure() -> void:
	if Content.rules().get("g71_conductor") == null:
		Content._merge_fragment_dir("res://content/g71")


func _lp() -> SimWorld:
	_ensure()
	if _base.is_empty():
		var w0 := SimWorld.new_match(SimWorld.LastProtocol.make_config(4242))
		w0.run_ticks(5)
		_base = w0.to_dict().duplicate(true)
	var w := SimWorld.from_dict(_base.duplicate(true))
	w.ai_state = {}
	return w


func _fid(w: SimWorld) -> int:
	return int(w.sys_state.lp.fid)


func _mfid(w: SimWorld) -> int:
	return int(w.sys_state.lp.get("mfid", -1))


func _hand() -> bool:
	return not SimWorld.SYSTEM_ORDER.has(C)


func _run(w: SimWorld, n: int) -> Array:
	var evs := []
	for i in n:
		w.step()
		if _hand():
			C.tick(w)
		evs.append_array(w.events)
	return evs


func _of(evs: Array, t: String) -> Array:
	var out := []
	for e in evs:
		if String(e.type) == t:
			out.append(e)
	return out


## A landing-ok cell east of the outer ring, plus the gunship and 4 wingmen parked there.
func _flight(w: SimWorld) -> Dictionary:
	var f := _fid(w)
	var rr := KZ.ring_rect(w)
	var base := Vector2i(int(rr.end.x) + 6, int(rr.position.y + rr.size.y / 2))
	var gd := Content.unit("a_g71_conductor")
	var cell := base
	for r in 8:
		var found := false
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if not found and Air.landing_ok(w, base + Vector2i(dx, dy), gd):
					cell = base + Vector2i(dx, dy)
					found = true
		if found:
			break
	var p := Vector2(cell) + Vector2(0.5, 0.5)
	var g := w.spawn_unit("a_g71_conductor", f, p)
	var wing := []
	for i in 4:
		wing.append(w.spawn_unit("a_g71_wingman", f, p + Vector2(1.0 + i, 1.5)))
	return {"g": g, "wing": wing, "home": p}


func test_off_lp_refused() -> void:
	var w := make_world()
	check(C.validate_command(w, {"type": "conductor_orbit", "issuer": 0, "at": [5, 5]}) != "", "orbit refused outside LP")
	C.tick(w)
	check(not w.sys_state.has(C.KEY), "skirmish tick never creates state")


func test_orbit_through_air_patrol() -> void:
	var w := _lp()
	var f := _fid(w)
	var c := KZ.base_centre(w)
	check(C.orbit_reason(w, f, c) != "", "no gunship = refused")
	var F := _flight(w)
	check_eq(C.orbit_reason(w, f, c), "", "gunship present = allowed")
	C.apply_command(w, {"type": "conductor_orbit", "issuer": f, "at": [c.x, c.y], "radius": 8.0, "side": -1})
	var o := C.record(w, f)
	check(bool(o.get("on", false)) and int(o.g) == int(F.g), "orbit record for our gunship")
	check_eq((o.wing as Array).size(), 4, "4 wingmen fly with it")
	check(Pads71.has_pad(w, String(o.pad)) and Pads71.home(w, int(F.g)) == String(o.pad), "own pad registered as its home")
	var pat := 0
	for id in [int(F.g)] + F.wing:
		if Air.flight(w, int(id)).has("pat71"):
			pat += 1
	check_eq(pat, 5, "gunship + wingmen fly the orbit as an air_patrol")
	var best := INF
	for i in 40:
		_run(w, 10)
		if w.entities.has(int(F.g)):
			best = minf(best, absf(Vector2(w.entities[int(F.g)].pos).distance_to(c) - 8.0))
	check(best < 2.5, "gunship reaches the orbit ring (closest %.2f)" % best)


func test_station_fire_and_handoff() -> void:
	var w := _lp()
	var f := _fid(w)
	var mf := _mfid(w)
	var F := _flight(w)
	var c: Vector2 = F.home + Vector2(4, 0)
	C.orbit_at(w, f, c, 6.0)
	w.entities[int(F.g)].pos = c + Vector2(6, 0)
	var t1 := w.spawn_unit("a_mortar", mf, c)
	var t2 := w.spawn_unit("a_sp_howitzer", mf, c + Vector2(1.5, 1))
	var t3 := w.spawn_unit("a_mortar", mf, c + Vector2(-1.5, -1))
	# G7.1 setup (owner-approved 2026-11-22, CR seq 2130): the wave-2 LP-base defenders (rail / HPM / laser / flak turrets,
	# crews) killed the 3 targets within 25 ticks, before a wingman could strike. Clear the player's other armed entities
	# within 40 tiles of the station so the gunship flight is what engages. The checks below are unchanged.
	var keep: Array = [int(F.g)] + C.wingmen(w, f)
	var armed: Array = []
	for e in w.entities.values():
		if int(e.get("owner", -1)) != f or keep.has(int(e.id)) or Vector2(e.pos).distance_to(c) > 40.0:
			continue
		var dd: Dictionary = Content.unit(String(e.def)) if String(e.kind) == "unit" else Content.building(String(e.def))
		if String(dd.get("weapon", "")) != "" or dd.has("weapons") or dd.has("t7") or dd.has("t71"):
			armed.append(int(e.id))
	for id in armed:
		w.destroy(id, "test_setup")
	var hp0 := float(w.entities[t1].hp) + float(w.entities[t2].hp) + float(w.entities[t3].hp)
	var evs := _run(w, 200)
	check(_of(evs, "ConductorCannon").size() >= 1, "side cannon fires on station")
	check(_of(evs, "ConductorMissile").size() >= 1, "missile cells fire at a vehicle")
	check(_of(evs, "WingmanHandoff").size() >= 1, "targets handed to wingmen")
	check(_of(evs, "WingmanStrike").size() >= 1, "wingmen peel off and strike")
	var hp1 := 0.0
	for t in [t1, t2, t3]:
		if w.entities.has(t):
			hp1 += float(w.entities[t].hp)
	check(hp1 < hp0, "the targets are hurt (%.0f -> %.0f)" % [hp0, hp1])
	check(int(C.record(w, f).cells) < int(C.R().cells), "missile cells spent")


func test_ciws_and_flares() -> void:
	var w := _lp()
	var f := _fid(w)
	var mf := _mfid(w)
	var F := _flight(w)
	C.orbit_at(w, f, F.home + Vector2(3, 0), 6.0)
	var gp: Vector2 = w.entities[int(F.g)].pos
	var d := w.spawn_unit("m_micro_drone", mf, gp + Vector2(2, 0))
	check(C.is_drone(w, w.entities[d]), "a machine micro drone counts as a drone")
	var evs := _run(w, 10)
	check(_of(evs, "ConductorCiws").size() >= 1, "laser CIWS engages the drone")
	check(not w.entities.has(d), "drone destroyed")
	var fl := int(C.record(w, f).flares)
	check(C.decoy(w, int(F.g)), "a flare decoys an AA missile")
	check_eq(int(C.record(w, f).flares), fl - 1, "one flare spent")
	check(not C.decoy(w, int(F.g)), "flare cooldown")
	check(not C.decoy(w, int(F.wing[0])), "only the gunship carries flares")


func test_kamikaze() -> void:
	var w := _lp()
	var f := _fid(w)
	var mf := _mfid(w)
	var F := _flight(w)
	C.orbit_at(w, f, F.home + Vector2(3, 0), 6.0)
	var t := w.spawn_unit("a_mortar", mf, F.home + Vector2(5, 3))
	var hp0 := float(w.entities[t].hp)
	var wid := int(F.wing[1])
	check(C.validate_command(w, {"type": "conductor_kamikaze", "issuer": f, "unit_id": int(F.g), "target_id": t}) != "", "the gunship itself cannot kamikaze")
	C.apply_command(w, {"type": "conductor_kamikaze", "issuer": f, "unit_id": wid, "target_id": t})
	check(not (C.record(w, f).wing as Array).has(wid), "wingman spent")
	check(not w.entities.has(wid) or float(w.entities[wid].hp) <= 0.0, "wingman destroyed")
	check(not w.entities.has(t) or float(w.entities[t].hp) < hp0, "target hit")


func test_home_and_hot_pit() -> void:
	var w := _lp()
	var f := _fid(w)
	var F := _flight(w)
	C.orbit_at(w, f, F.home + Vector2(6, 0), 6.0)
	_run(w, 60)
	C.record(w, f).cells = 0
	C.record(w, f).flares = 1
	C.apply_command(w, {"type": "conductor_home", "issuer": f})
	check(not bool(C.record(w, f).on), "orbit ended")
	var done := false
	for i in 120:
		var evs := _run(w, 10)
		if not _of(evs, "ConductorServiced").is_empty():
			done = true
			break
		if OS.has_environment("COND71_DIAG") and i % 10 == 0:
			var gx = w.entities.get(int(F.g))
			print("COND71_DIAG t=%d g=%s %s" % [w.tick, "gone" if gx == null else "%s landed=%s hp=%s" % [str(gx.pos), str(Air.is_landed(gx)), str(gx.hp)], "" if gx == null else str(Air.flight(w, int(F.g))), ])
	var ge = w.entities.get(int(F.g))
	if not done:
		if ge == null:
			print("COND71_DIAG gunship gone")
		else:
			print("COND71_DIAG phase=%s landed=%s pos=%s home=%s fl=%s" % [Air.phase(w, int(F.g)), str(Air.is_landed(ge)), str(ge.pos), str(F.home), str(Air.flight(w, int(F.g)))])
	check(done, "lands on its pad and is hot-pit serviced")
	check_eq(int(C.record(w, f).cells), int(C.R().cells), "cells refilled")
	check_eq(int(C.record(w, f).flares), int(C.R().flares), "flares refilled")


func test_determinism_save_load_mid_orbit() -> void:
	var w := _lp()
	var f := _fid(w)
	var mf := _mfid(w)
	var F := _flight(w)
	var c: Vector2 = F.home + Vector2(4, 0)
	C.orbit_at(w, f, c, 6.0)
	w.spawn_unit("a_mortar", mf, c)
	_run(w, 40)
	var a := SimWorld.from_dict(w.to_dict().duplicate(true))
	var b := SimWorld.from_dict(w.to_dict().duplicate(true))
	check_eq(a.state_hash(), w.state_hash(), "save / load keeps the hash mid orbit")
	_run(a, 80)
	_run(b, 80)
	check_eq(a.state_hash(), b.state_hash(), "same future after load")
