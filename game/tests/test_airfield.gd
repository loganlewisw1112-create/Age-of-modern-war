extends "res://tests/test_base.gd"
## G5 acceptance (owner: AIRSYS). CONTRACTS_G5 sections 3.4, 3.5, 4, 5, 7: hangar / pad gating, hangar
## levels, extra strips, one movement per strip, craters + engineer repair, diverts / crashes, destroyed
## hangars, engineer upkeep, the Airstrip variant.

const Airfield = preload("res://sim/systems/airfield.gd")
const Air = preload("res://sim/systems/air.gd")


func _w() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	for fid in w.factions:
		(w.fog[fid].explored as PackedByteArray).fill(1)
	w.credit(0, {"credits": 50000, "salvage": 20000, "ore": 20000, "fuel": 5000, "ammo": 5000}, "test")
	return w


func _hq(w: SimWorld, fid: int) -> Dictionary:
	for b in w.buildings_of(fid):
		if bool(Content.building(String(b.def)).get("is_hq", false)):
			return b
	return {}


## Free square origin of `size` nearest hq.cell + off (ring search).
func _origin(w: SimWorld, size: int, off: Vector2i, fid: int = 0) -> Vector2i:
	var base: Vector2i = (_hq(w, fid).cell as Vector2i) + off
	for r in range(0, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := base + Vector2i(dx, dy)
				var ok := true
				for y in range(-1, size + 1):
					for x in range(-1, size + 1):
						if not Airfield._square_free(w, c + Vector2i(x, y), 1):
							ok = false
				if ok:
					return c
	return base


func _field(w: SimWorld, def: String = "a_airfield", off: Vector2i = Vector2i(12, 0), fid: int = 0) -> int:
	var id := w.spawn_building(def, fid, _origin(w, int(Content.building(def).size), off, fid), true)
	w.step()
	return id


func _hangar(w: SimWorld, fb: int, cls: String = "light", level: int = 0) -> int:
	var b: Dictionary = w.entities[fb]
	var hdef := Airfield._hangar_def(b, cls)
	var hid := w.spawn_building(hdef, int(b.owner), Airfield._hangar_cell(w, b, 2), true)
	w.step()
	w.entities[hid].level = level
	for h in Airfield.field(w, fb).hangars:
		if int(h.bid) == hid:
			h.level = level
	return hid


func _tower(w: SimWorld, fb: int) -> int:
	var b: Dictionary = w.entities[fb]
	var t := w.spawn_building("a_air_tower", int(b.owner), Airfield._hangar_cell(w, b, 2), true)
	w.step()
	return t


func _jet(w: SimWorld, def: String, at_bid: int, fid: int = 0) -> int:
	var id := w.spawn_unit(def, fid, Vector2(w.entities[at_bid].pos))
	w.step()
	return id


func _run(w: SimWorld, n: int, f: Callable) -> int:
	for i in n:
		w.step()
		if f.call():
			return i + 1
	return -1


func _events(w: SimWorld, type: String) -> Array:
	var out := []
	for ev in w.event_log:
		if String(ev.type) == type:
			out.append(ev)
	return out


# ---------------------------------------------------------------- gating
func test_no_free_hangar_blocks_aircraft_purchase() -> void:
	var w := _w()
	var fb := _field(w)
	_tower(w, fb)
	check_eq(Airfield.can_produce(w, 0, "a_strike_jet"), "no_free_hangar", "no hangar -> no_free_hangar")
	var r := w.preview_command({"type": "queue_unit", "issuer": 0, "building_id": fb, "item": "a_strike_jet"})
	check(r.contains("no_free_hangar"), "production refuses with no_free_hangar (got '%s')" % r)
	var hid := _hangar(w, fb, "light")
	check_eq(Airfield.can_produce(w, 0, "a_strike_jet"), "", "a free light hangar allows the jet")
	check_eq(w.preview_command({"type": "queue_unit", "issuer": 0, "building_id": fb, "item": "a_strike_jet"}), "", "queue accepted")
	check(w.submit({"type": "queue_unit", "issuer": 0, "building_id": fb, "item": "a_strike_jet"}).ok, "queued")
	w.step()
	check_eq(Airfield.can_produce(w, 0, "a_interceptor"), "no_free_hangar", "the queued jet reserves the only hangar")
	var done := _run(w, 900, func() -> bool: return not _events(w, "ProductionCompleted").is_empty())
	check(done > 0, "the jet is produced")
	w.step()
	var jets := w.units_of(0).filter(func(u) -> bool: return String(u.def) == "a_strike_jet")
	check_eq(jets.size(), 1, "one jet")
	if jets.size() == 1:
		check_eq(int(jets[0].air_home), hid, "the jet lives in the hangar")
		check(Air.is_landed(jets[0]), "parked on the ground")
		check_eq(Air.phase(w, int(jets[0].id)), "parked", "phase parked")
	check_eq(Airfield.can_produce(w, 0, "a_strike_jet"), "no_free_hangar", "hangar occupied -> no_free_hangar")
	var w2 := _w()
	var fb2 := _field(w2)
	_hangar(w2, fb2, "light")
	check_eq(Airfield.can_produce(w2, 0, "a_strike_jet"), "no_air_tower", "air_high needs an air tower")


func test_no_free_pad_blocks_helicopter_purchase() -> void:
	var w := _w()
	check_eq(Airfield.can_produce(w, 0, "a_attack_heli"), "no_free_pad", "no pad -> no_free_pad")
	var pad := _field(w, "a_helipad", Vector2i(8, 6))
	check_eq(Airfield.free_slots(w, pad).pad, 2, "a helipad has 2 home pads")
	check_eq(Airfield.can_produce(w, 0, "a_attack_heli"), "", "free pad allows a helicopter")
	var h1 := _jet(w, "a_attack_heli", pad)
	var h2 := _jet(w, "a_transport_gunship", pad)
	check_eq(int(w.entities[h1].air_home), pad, "heli 1 home pad")
	check_eq(int(w.entities[h2].air_home), pad, "heli 2 home pad")
	check_eq(Airfield.can_produce(w, 0, "a_attack_heli"), "no_free_pad", "both pads taken -> no_free_pad")
	var r := w.preview_command({"type": "queue_unit", "issuer": 0, "building_id": pad, "item": "a_attack_heli"})
	check(r.contains("no_free_pad"), "production refuses with no_free_pad (got '%s')" % r)
	w.destroy(h1, "test")
	w.step()
	check_eq(Airfield.can_produce(w, 0, "a_attack_heli"), "", "a dead helicopter frees its pad")


func test_heavy_aircraft_needs_heavy_hangar() -> void:
	var w := _w()
	w.factions[0].stage = 9
	var fb := _field(w)
	_hangar(w, fb, "light")
	check_eq(Airfield.can_produce(w, 0, "a_vtol_dropship"), "no_free_hangar", "VTOL needs a heavy hangar")
	var hv := _hangar(w, fb, "heavy")
	check_eq(Airfield.can_produce(w, 0, "a_vtol_dropship"), "", "heavy hangar allows the VTOL")
	var v := _jet(w, "a_vtol_dropship", hv)
	check_eq(int(w.entities[v].air_home), hv, "VTOL bound to the heavy hangar")
	check_eq(Airfield.can_produce(w, 0, "a_vtol_dropship"), "no_free_hangar", "heavy taken")
	_tower(w, fb)
	check_eq(Airfield.can_produce(w, 0, "a_strike_jet"), "", "the light hangar still takes a light jet")
	# light -> heavy upgrade
	var lh := -1
	for h in Airfield.field(w, fb).hangars:
		if String(h["class"]) == "light":
			lh = int(h.bid)
	check(w.submit({"type": "upgrade_hangar", "issuer": 0, "building_id": lh, "kind": "to_heavy"}).ok, "to_heavy accepted")
	var t := _run(w, 800, func() -> bool: return String(w.entities[lh].get("class", "")) == "heavy")
	check(t > 0, "light hangar becomes heavy")
	check_eq(Airfield.can_produce(w, 0, "a_vtol_dropship"), "", "the upgraded hangar takes a VTOL")


func test_hangar_levels_rearm_repair_roof() -> void:
	var times := []
	for lvl in [0, 1]:
		var w := _w()
		var fb := _field(w)
		var hid := _hangar(w, fb, "light", lvl)
		var j := _jet(w, "a_strike_jet", hid)
		w.entities[j].ammo = 0
		times.append(_run(w, 1200, func() -> bool: return int(w.entities[j].ammo) == int(Content.unit("a_strike_jet").ammo_max)))
	check(int(times[0]) > 0 and int(times[1]) > 0, "rearmed in both hangars (%s)" % str(times))
	check(int(times[1]) < int(times[0]), "L1 rearms faster (%s)" % str(times))
	check(absf(float(times[1]) / float(times[0]) - 0.6) < 0.05, "L1 = -40%% time (%s)" % str(times))
	# level upgrade through the command, then L2 repairs a parked aircraft
	var w2 := _w()
	var fb2 := _field(w2)
	var h2 := _hangar(w2, fb2, "light", 1)
	check(w2.submit({"type": "upgrade_hangar", "issuer": 0, "building_id": h2, "kind": "level"}).ok, "level upgrade accepted")
	check(_run(w2, 800, func() -> bool: return int(w2.entities[h2].level) == 2) > 0, "hangar reaches L2")
	var j2 := _jet(w2, "a_strike_jet", h2)
	var e2: Dictionary = w2.entities[j2]
	e2.hp = float(e2.max_hp) * 0.5
	w2.run_ticks(100)
	check(float(e2.hp) > float(e2.max_hp) * 0.5 + 1.0, "L2 repairs while parked")
	var w3 := _w()
	var fb3 := _field(w3)
	var h3 := _hangar(w3, fb3, "light", 0)
	var j3 := _jet(w3, "a_strike_jet", h3)
	var e3: Dictionary = w3.entities[j3]
	e3.hp = float(e3.max_hp) * 0.5
	w3.run_ticks(100)
	check_eq(float(e3.hp), float(e3.max_hp) * 0.5, "L0 does not repair")


func test_extra_strip_upgrade_adds_strip_and_two_slots() -> void:
	var w := _w()
	var fb := _field(w)
	check_eq((Airfield.field(w, fb).strips as Array).size(), 1, "base 1 strip")
	check_eq(Airfield.slot_cap(w, fb), 4, "base 4 hangar slots")
	for i in 4:
		check(w.submit({"type": "build_hangar", "issuer": 0, "building_id": fb, "class": "light"}).ok, "hangar %d accepted" % i)
		w.step()
	check(w.preview_command({"type": "build_hangar", "issuer": 0, "building_id": fb, "class": "light"}).contains("No free hangar slot"), "5th hangar refused")
	check(w.submit({"type": "upgrade_airfield", "issuer": 0, "building_id": fb, "kind": "extra_strip"}).ok, "extra strip accepted")
	var t := _run(w, 1200, func() -> bool: return int(w.entities[fb].get("extra_strips", 0)) == 1)
	check(t > 0, "upgrade completes")
	check_eq((Airfield.field(w, fb).strips as Array).size(), 2, "2 strips")
	check_eq(Airfield.slot_cap(w, fb), 6, "6 hangar slots")
	check_eq(w.preview_command({"type": "build_hangar", "issuer": 0, "building_id": fb, "class": "light"}), "", "5th hangar now allowed")
	var built := _run(w, 800, func() -> bool:
		for h in Airfield.field(w, fb).hangars:
			if not bool(w.entities[int(h.bid)].built):
				return false
		return true)
	check(built > 0, "bought hangars finish building")
	w.entities[fb].extra_strips = 3
	check(w.preview_command({"type": "upgrade_airfield", "issuer": 0, "building_id": fb, "kind": "extra_strip"}).contains("No more strips"), "max +3 strips")


func test_one_aircraft_per_strip_at_a_time() -> void:
	var w := _w()
	var fb := _field(w)
	var a := _jet(w, "a_strike_jet", _hangar(w, fb))
	var b := _jet(w, "a_interceptor", _hangar(w, fb))
	check(w.submit({"type": "take_off", "issuer": 0, "unit_ids": [a, b]}).ok, "take_off accepted")
	var max_busy := 0
	var saw_wait := false
	for i in 400:
		w.step()
		var on := 0
		for id in [a, b]:
			var ph := Air.phase(w, id)
			if ph == "roll" or ph == "approach":
				on += 1
			if ph == "hold" and (Air.phase(w, a) == "roll" or Air.phase(w, b) == "roll"):
				saw_wait = true
		max_busy = maxi(max_busy, on)
	check_eq(max_busy, 1, "never two aircraft on the single strip")
	check(saw_wait, "the second jet held short while the first rolled")
	check(not Air.is_landed(w.entities[a]) and not Air.is_landed(w.entities[b]), "both airborne in the end")


func _strip_mid(w: SimWorld, fb: int, k: int = 0) -> Vector2:
	var p := Airfield.strip_points(w, fb, k)
	return ((p[0] as Vector2) + (p[1] as Vector2)) * 0.5


func test_crater_closes_strip_and_engineers_repair_it() -> void:
	var w := _w()
	var fb := _field(w)
	var j := _jet(w, "a_strike_jet", _hangar(w, fb))
	Airfield.on_impact(w, Content.unit("a_strike_jet").payload, _strip_mid(w, fb))
	check_eq(Airfield.open_strips(w, fb), 0, "a cratering hit closes the strip")
	check(w.submit({"type": "take_off", "issuer": 0, "unit_ids": [j]}).ok, "take_off submitted")
	w.run_ticks(60)
	check_eq(Air.phase(w, j), "parked", "no take-off from a cratered strip")
	w.run_ticks(400)
	check_eq(Airfield.open_strips(w, fb), 0, "craters stay without engineers")
	var eng := w.spawn_unit("a_airfield_engineers", 0, Vector2(w.entities[fb].pos) + Vector2(0, 4))
	w.step()
	check(w.submit({"type": "assign_engineers", "issuer": 0, "unit_ids": [eng], "building_id": fb}).ok, "assign accepted")
	var t := _run(w, 1500, func() -> bool: return Airfield.open_strips(w, fb) == 1)
	check(t > 0, "engineers fill the crater")
	check(t >= int(Airfield.rf("crater_repair_s", 15.0) * 20.0) - 1, "repair takes crater_repair_s (%d ticks)" % t)
	check(w.submit({"type": "take_off", "issuer": 0, "unit_ids": [j]}).ok, "take_off again")
	check(_run(w, 300, func() -> bool: return not Air.is_landed(w.entities[j])) > 0, "the jet takes off from the repaired strip")


func test_airborne_jets_divert_or_crash_without_field() -> void:
	var w := _w()
	var fa := _field(w, "a_airfield", Vector2i(12, 0))
	var fb := _field(w, "a_airfield", Vector2i(12, 18))
	_hangar(w, fb)
	var j := _jet(w, "a_interceptor", _hangar(w, fa))
	check(w.submit({"type": "take_off", "issuer": 0, "unit_ids": [j]}).ok, "take_off")
	check(_run(w, 300, func() -> bool: return Air.phase(w, j) == "air") > 0, "airborne")
	w.destroy(fa, "test")
	w.entities[j].fuel = float(Content.unit("a_interceptor").fuel_max) * 0.2   # low: heads home
	var t := _run(w, 2000, func() -> bool: return Air.phase(w, j) == "parked" or Air.phase(w, j) == "landed")
	check(t > 0, "the jet landed somewhere")
	check(not _events(w, "AircraftDiverted").is_empty(), "AircraftDiverted emitted")
	check_eq(int(w.entities[j].air_at), int(w.entities[j].get("air_home", -2)), "re-homed into the other field's free hangar")
	check_eq(Airfield.field_of(w, int(w.entities[j].air_at)), fb, "landed at the surviving field")
	# no field at all: crash when the fuel runs out
	var w2 := _w()
	var f2 := _field(w2)
	var j2 := _jet(w2, "a_strike_jet", _hangar(w2, f2))
	w2.submit({"type": "take_off", "issuer": 0, "unit_ids": [j2]})
	_run(w2, 300, func() -> bool: return Air.phase(w2, j2) == "air")
	w2.destroy(f2, "test")
	w2.entities[j2].fuel = 10.0
	var c := _run(w2, 400, func() -> bool: return not w2.entities.has(j2))
	check(c > 0, "the jet crashes when out of fuel with no field")
	check(not _events(w2, "AircraftCrashed").is_empty(), "AircraftCrashed emitted")


func test_destroyed_hangar_kills_parked_aircraft_unless_roof() -> void:
	var w := _w()
	var fb := _field(w)
	var h0 := _hangar(w, fb, "light", 0)
	var h3 := _hangar(w, fb, "light", 3)
	var j0 := _jet(w, "a_strike_jet", h0)
	var j3 := _jet(w, "a_strike_jet", h3)
	check_eq(int(w.entities[j0].air_at), h0, "jet 0 parked in hangar 0")
	check_eq(int(w.entities[j3].air_at), h3, "jet 3 parked in hangar 3")
	w.destroy(h0, "test")
	w.destroy(h3, "test")
	w.step()
	check(not w.entities.has(j0), "the aircraft in the destroyed L0 hangar dies")
	check(w.entities.has(j3), "the L3 roof saves its aircraft")
	if w.entities.has(j3):
		var e: Dictionary = w.entities[j3]
		check_eq(float(e.hp), float(e.max_hp) * 0.5, "... with 50% damage")


func test_assign_engineers_auto_upkeep() -> void:
	var w := _w()
	var fb := _field(w)
	var hid := _hangar(w, fb)
	var b: Dictionary = w.entities[fb]
	var h: Dictionary = w.entities[hid]
	b.hp = float(b.max_hp) * 0.5
	h.hp = float(h.max_hp) * 0.5
	var eng := w.spawn_unit("b_airfield_engineers" if false else "a_airfield_engineers", 0, Vector2(b.pos) + Vector2(0, 5))
	w.step()
	check(w.preview_command({"type": "assign_engineers", "issuer": 0, "unit_ids": [eng], "building_id": hid}) == "", "assign to a hangar ok")
	check(w.submit({"type": "assign_engineers", "issuer": 0, "unit_ids": [eng], "building_id": hid}).ok, "assigned")
	w.step()
	check((Airfield.field(w, fb).engineers as Array).has(eng), "the airfield lists the engineers")
	check_eq(int(w.entities[eng].air_assign), hid, "assigned to the hangar")
	w.run_ticks(200)
	check(float(h.hp) > float(h.max_hp) * 0.5, "the assigned hangar is repaired first")
	check_eq(float(b.hp), float(b.max_hp) * 0.5, "... before the field")
	_run(w, 3000, func() -> bool: return float(b.hp) >= float(b.max_hp))
	check_eq(float(b.hp), float(b.max_hp), "then the field itself")
	# faster hangar construction with engineers
	var t_eng := _hangar_build_ticks(w, fb)
	var w2 := _w()
	var fb2 := _field(w2)
	var t_none := _hangar_build_ticks(w2, fb2)
	check(t_eng > 0 and t_none > 0 and t_eng < t_none, "engineers build hangars faster (%d vs %d)" % [t_eng, t_none])
	w.submit({"type": "move", "issuer": 0, "unit_ids": [eng], "target": Vector2(w.entities[eng].pos) + Vector2(0, 3)})
	w.run_ticks(3)
	check(not (Airfield.field(w, fb).engineers as Array).has(eng), "another order unassigns them")


func _hangar_build_ticks(w: SimWorld, fb: int) -> int:
	w.submit({"type": "build_hangar", "issuer": 0, "building_id": fb, "class": "light"})
	w.step()
	var n := (Airfield.field(w, fb).hangars as Array).size()
	var hid := int(Airfield.field(w, fb).hangars[n - 1].bid)
	return _run(w, 1000, func() -> bool: return bool(w.entities[hid].built))


func test_airstrip_variant_light_only() -> void:
	var w := _w()
	w.factions[0].stage = 9
	var fs := _field(w, "a_airstrip")
	check_eq(Airfield.slot_cap(w, fs), 2, "2 hangar slots")
	check(w.preview_command({"type": "build_hangar", "issuer": 0, "building_id": fs, "class": "heavy"}).contains("light hangars only"), "no heavy hangars")
	check_eq(w.preview_command({"type": "build_hangar", "issuer": 0, "building_id": fs, "class": "light"}), "", "light hangar ok")
	check(w.preview_command({"type": "upgrade_airfield", "issuer": 0, "building_id": fs, "kind": "extra_strip"}).contains("No more strips"), "no extra strips")
	var prod: Array = Content.building("a_airstrip").get("produces", [])
	check(prod.has("a_strike_jet") and prod.has("a_interceptor"), "airstrip builds light jets")
	check(not prod.has("a_vtol_dropship"), "airstrip does not build the VTOL")
	var hid := _hangar(w, fs, "light")
	check(w.preview_command({"type": "upgrade_hangar", "issuer": 0, "building_id": hid, "kind": "to_heavy"}).contains("light hangars only"), "no light->heavy on an airstrip")
	check_eq(Airfield.can_produce(w, 0, "a_vtol_dropship"), "no_free_hangar", "no heavy slot for a VTOL")


# ---------------------------------------------------------------- extra (Machine rail, determinism)
func test_machine_rail_bays_and_extra_rail() -> void:
	var w := _w()
	var rail := _field(w, "m_launch_rail")
	check_eq(Airfield.can_produce(w, 0, "m_interceptor_swarm"), "no_free_hangar", "no bay -> no_free_hangar")
	check(w.submit({"type": "build_hangar", "issuer": 0, "building_id": rail, "class": "light"}).ok, "buy a drone bay")
	w.step()
	var bay := int(Airfield.field(w, rail).hangars[0].bid)
	check_eq(String(w.entities[bay].def), "m_drone_bay", "the rail's hangar is a Drone Bay")
	check(_run(w, 800, func() -> bool: return bool(w.entities[bay].built)) > 0, "bay built")
	check_eq(Airfield.can_produce(w, 0, "m_interceptor_swarm"), "", "a bay allows the swarm (no tower for Machine)")
	var s := _jet(w, "m_interceptor_swarm", bay)
	check_eq(int(w.entities[s].air_home), bay, "swarm lives in the bay")
	check(w.submit({"type": "upgrade_airfield", "issuer": 0, "building_id": rail, "kind": "extra_rail"}).ok, "extra rail")
	check(_run(w, 1200, func() -> bool: return int(w.entities[rail].get("extra_rails", 0)) == 1) > 0, "extra_rails = 1")
	check_eq(Airfield.slot_cap(w, rail), 6, "+2 bays")


func _air_run(native_on: bool) -> String:
	const NativeCore = preload("res://sim/native_core.gd")
	NativeCore.force_off = not native_on
	var w := _w()
	var fb := _field(w)
	var j := _jet(w, "a_strike_jet", _hangar(w, fb))
	var i := _jet(w, "a_interceptor", _hangar(w, fb))
	var pad := _field(w, "a_helipad", Vector2i(8, 8))
	var hc := _jet(w, "a_attack_heli", pad)
	var t := w.spawn_unit("mbt", 1, Vector2(w.entities[fb].pos) + Vector2(10, 30))
	w.submit({"type": "sortie", "issuer": 0, "unit_ids": [j], "target_id": t})
	w.submit({"type": "take_off", "issuer": 0, "unit_ids": [i]})
	w.submit({"type": "move", "issuer": 0, "unit_ids": [hc], "target": Vector2(w.entities[pad].pos) + Vector2(15, 5)})
	w.run_ticks(900)
	NativeCore.force_off = false
	return w.state_hash()


func test_air_determinism_native_on_off() -> void:
	var a := _air_run(true)
	check_eq(_air_run(true), a, "same seed + commands = same hash")
	check_eq(_air_run(false), a, "native off = native on")
