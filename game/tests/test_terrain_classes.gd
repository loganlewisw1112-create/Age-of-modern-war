extends "res://tests/test_base.gd"
## NAT (CONTRACTS_G4 section 3): terrain semantics for codes 0-13, movement classes (incl. the
## naval >= 3-wide channel rule), per-team gates (native + fallback), LOS through cliffs, and the
## same hash threaded vs main thread on a 2k-unit scenario.

const Movement = preload("res://sim/systems/movement.gd")
const NativeCore = preload("res://sim/native_core.gd")
const Damage = preload("res://sim/systems/damage.gd")
const C := Vector2(0.5, 0.5)


func _modes() -> Array:
	return [true, false] if NativeCore.available() else [false]


func _set_native(on: bool) -> void:
	NativeCore.force_off = not on


## Grass x 10..85, y 4..40; RIDGE columns x 47..48 over the WHOLE map height except y = 22.
func _gate_world(native_on: bool) -> SimWorld:
	_set_native(native_on)
	var w := make_world({"seed": 5})
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	for y in int(w.map.h):
		for x in mw:
			if x == 47 or x == 48:
				t[y * mw + x] = Terrain.GRASS if y == 22 else Terrain.RIDGE
			elif x >= 10 and x <= 85 and y >= 4 and y <= 40:
				t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	return w


# ---------------------------------------------------------------- terrain semantics
func test_passability_table_per_class() -> void:
	var T := Terrain
	var exp := {
		"foot": [T.GRASS, T.DIRT, T.ROAD, T.FOREST, T.BRIDGE, T.FORD, T.BEACH, T.HILL, T.SHALLOW],
		"vehicle": [T.GRASS, T.DIRT, T.ROAD, T.BRIDGE, T.FORD, T.BEACH, T.HILL, T.SHALLOW],
		"amphibious": [T.GRASS, T.DIRT, T.ROAD, T.BRIDGE, T.FORD, T.BEACH, T.HILL, T.SHALLOW, T.WATER, T.DEEP],
		"naval_small": [T.WATER, T.SHALLOW, T.DEEP],
		"naval": [T.WATER, T.DEEP],
	}
	for mc in exp:
		for code in 14:
			check_eq(T.passable(code, mc), (exp[mc] as Array).has(code), "%s on %s" % [mc, T.NAMES[code]])
	for mc in ["air", "air_low", "air_high"]:
		check(T.is_air(mc), "%s is air" % mc)
		for code in 14:
			check(T.passable(code, mc), "%s passes %s" % [mc, T.NAMES[code]])
	for mc in ["foot", "vehicle", "amphibious"]:
		for code in [T.RIDGE, T.CLIFF, T.BUILDING]:
			check(not T.passable(code, mc), "ground never passes %s" % T.NAMES[code])
	# speed / build / LOS / sight
	check_eq(T.speed_mult(T.SHALLOW, "foot"), 0.5, "foot shallow 0.5x")
	check_eq(T.speed_mult(T.SHALLOW, "vehicle"), 0.4, "vehicle shallow 0.4x")
	check_eq(T.speed_mult(T.HILL, "vehicle"), 0.8, "vehicle hill 0.8x")
	check_eq(T.speed_mult(T.WATER, "amphibious"), 0.6, "amphibious water 0.6x")
	for code in 14:
		check_eq(T.buildable(code), [T.GRASS, T.DIRT, T.BEACH, T.HILL].has(code), "buildable %s" % T.NAMES[code])
		check_eq(T.blocks_los(code), [T.RIDGE, T.CLIFF, T.BUILDING].has(code), "blocks_los %s" % T.NAMES[code])
	check_eq(T.sight_bonus(T.HILL), 2.0, "hill +2 sight")
	check_eq(T.sight_bonus(T.GRASS), 0.0, "grass no bonus")
	check_eq(T.sight_bonus(T.HILL, "air"), 0.0, "air gets no hill bonus")


func test_codes_0_to_7_unchanged_for_foot_and_vehicle() -> void:
	# G1-G3 values: River Crossing behaviour must stay byte-identical.
	var foot := [1.0, 0.95, 1.25, 0.6, 0.0, 1.25, 0.5, 0.0]
	var veh := [1.0, 0.95, 1.25, 0.0, 0.0, 1.25, 0.5, 0.0]
	var lf: Array = Movement._lut("foot")
	var lv: Array = Movement._lut("vehicle")
	for code in 8:
		check_eq(float(lf[code]), float(foot[code]), "foot lut code %d" % code)
		check_eq(float(lv[code]), float(veh[code]), "vehicle lut code %d" % code)


# ---------------------------------------------------------------- movement classes
func test_naval_channel_rule_and_class_nav() -> void:
	for native_on in _modes():
		_set_native(native_on)
		var w := make_world({"seed": 2})
		w.ai_state = {}
		var t: PackedByteArray = w.map.terrain
		var mw := int(w.map.w)
		for y in range(4, 41):
			for x in range(10, 86):
				var code := Terrain.GRASS
				if y == 10 or y == 11:
					code = Terrain.WATER   # 2-wide channel
				elif y >= 20 and y <= 22:
					code = Terrain.WATER   # 3-wide channel
				elif y == 30:
					code = Terrain.DEEP    # 1-wide deep strip
				t[y * mw + x] = code
		t[34 * mw + 60] = Terrain.SHALLOW
		t[35 * mw + 60] = Terrain.CLIFF
		w.map.terrain = t
		Movement.rebuild_nav(w)
		var tag := "native" if native_on else "fallback"
		check(not Movement.is_passable(w, Vector2i(20, 10), "naval"), "%s: naval refuses a 2-wide channel" % tag)
		check(Movement.is_passable(w, Vector2i(20, 21), "naval"), "%s: naval uses a 3-wide channel" % tag)
		check(Movement.is_passable(w, Vector2i(20, 20), "naval"), "%s: channel edge row is in" % tag)
		check(Movement.is_passable(w, Vector2i(20, 30), "naval"), "%s: DEEP always naval" % tag)
		check(Movement.is_passable(w, Vector2i(20, 10), "naval_small"), "%s: small boats use narrow water" % tag)
		check(not Movement.is_passable(w, Vector2i(20, 10), "foot"), "%s: foot refuses water" % tag)
		check(Movement.is_passable(w, Vector2i(60, 34), "foot"), "%s: foot wades shallow" % tag)
		check(Movement.is_passable(w, Vector2i(60, 34), "naval_small"), "%s: small boats in shallow" % tag)
		check(not Movement.is_passable(w, Vector2i(60, 34), "naval"), "%s: naval not in shallow" % tag)
		check(Movement.is_passable(w, Vector2i(20, 10), "amphibious"), "%s: amphibious swims" % tag)
		check(not Movement.is_passable(w, Vector2i(60, 35), "amphibious"), "%s: cliff solid" % tag)
		check(Movement.is_passable(w, Vector2i(60, 35), "air_high"), "%s: jets over cliffs" % tag)
		var lab := Movement._comp(w, "naval")
		check_eq(lab[10 * mw + 20], -1, "%s: 2-wide channel cell solid in naval components" % tag)
		var p := Movement._compute(w, "naval", Vector2i(12, 21), Vector2i(80, 21), Vector2(80.5, 21.5))
		check(not p.is_empty() and (p[p.size() - 1] as Vector2) == Vector2(80.5, 21.5), "%s: naval path along the channel" % tag)
		for q in p:
			check(Movement.is_passable(w, w.cell_of(q), "naval"), "%s: naval waypoint %s is water" % [tag, q])
	_set_native(true)


# ---------------------------------------------------------------- gates
func test_gate_blocks_enemy_team_lets_owner_through() -> void:
	for native_on in _modes():
		var tag := "native" if native_on else "fallback"
		var w := _gate_world(native_on)
		Movement.set_gate(w, [Vector2i(47, 22), Vector2i(48, 22)], 0, false)
		check_eq(Movement.gate_at(w, Vector2i(47, 22)), {"team": 0, "locked": false}, "%s: gate_at" % tag)
		var a := w.spawn_unit("rifleman", 0, Vector2(40, 22) + C)
		var b := w.spawn_unit("rifleman", 1, Vector2(40, 26) + C)
		var goal := Vector2(56, 22) + C
		check(Movement.can_reach(w, w.entities[a], goal), "%s: owner team reaches through its open gate" % tag)
		check(not Movement.can_reach(w, w.entities[b], goal), "%s: enemy team cannot path through the gate" % tag)
		check(not Movement.is_passable(w, Vector2i(47, 22), "foot"), "%s: team-less query sees the gate solid" % tag)
		check(Movement.is_passable_e(w, w.entities[a], Vector2i(47, 22)), "%s: owner sees it open" % tag)
		do_cmd(w, 0, {"type": "move", "unit_ids": [a], "target": goal})
		w.run_ticks(220)
		check((w.entities[a].pos as Vector2).x > 50.0, "%s: owner unit walked through the gate (x=%.2f)" % [tag, w.entities[a].pos.x])
		Movement.set_gate(w, [Vector2i(47, 22), Vector2i(48, 22)], 0, true)
		check(not Movement.can_reach(w, w.entities[a], Vector2(40, 22) + C), "%s: a locked gate stops its owner too" % tag)
		Movement.set_gate(w, [Vector2i(47, 22), Vector2i(48, 22)], -1, false)
		check(Movement.can_reach(w, w.entities[b], goal), "%s: removed gate opens the gap to everyone" % tag)
		check(not w.sys_state.movement.has("gates"), "%s: no gate state left after removal" % tag)
	_set_native(true)


func test_gate_save_round_trip_and_native_parity() -> void:
	var hashes := {}
	for native_on in _modes():
		var w := _gate_world(native_on)
		Movement.set_gate(w, [Vector2i(47, 22), Vector2i(48, 22)], 0, false)
		var ids := []
		for i in 8:
			ids.append(w.spawn_unit("rifleman", 0, Vector2(30 + i % 4, 20 + i / 4) + C))
		do_cmd(w, 0, {"type": "move", "unit_ids": ids, "target": Vector2(60, 22) + C})
		w.run_ticks(30)
		var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
		w2.ai_state = {}
		check_eq(w2.state_hash(), w.state_hash(), "hash equal right after load (native=%s)" % native_on)
		check_eq(Movement.gate_at(w2, Vector2i(48, 22)), {"team": 0, "locked": false}, "gate restored on load")
		w.run_ticks(150)
		w2.run_ticks(150)
		check_eq(w2.state_hash(), w.state_hash(), "hash equal 150 ticks after load (native=%s)" % native_on)
		var crossed := 0
		for id in ids:
			if (w.entities[id].pos as Vector2).x > 49.0:
				crossed += 1
		check(crossed >= 6, "most of the group crossed through the gate (native=%s, %d/8)" % [native_on, crossed])
		hashes[native_on] = crossed
	_set_native(true)


# ---------------------------------------------------------------- LOS
func test_los_blocked_by_cliff_and_native_parity() -> void:
	_set_native(true)
	var w := make_world({"seed": 3})
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	for y in range(10, 20):
		for x in range(10, 40):
			t[y * mw + x] = Terrain.GRASS
	t[15 * mw + 20] = Terrain.CLIFF
	t[17 * mw + 20] = Terrain.HILL
	t[12 * mw + 20] = Terrain.BUILDING
	w.map.terrain = t
	check(not Damage.line_clear(w, Vector2(15.5, 15.5), Vector2(25.5, 15.5)), "cliff blocks LOS")
	check(Damage.line_clear(w, Vector2(15.5, 17.5), Vector2(25.5, 17.5)), "hill does not block LOS")
	check(not Damage.line_clear(w, Vector2(15.5, 12.5), Vector2(25.5, 12.5)), "building terrain blocks LOS")
	check(Damage.line_clear(w, Vector2(15.5, 18.5), Vector2(25.5, 18.5)), "open grass is clear")
	var lc = NativeCore.new_combat()
	if lc == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var tt: PackedByteArray = w.map.terrain
	for i in tt.size() / 9:
		tt[rng.randi_range(0, tt.size() - 1)] = rng.randi_range(0, 13)
	w.map.terrain = tt
	var mism := 0
	for i in 1500:
		var a := Vector2(rng.randf_range(0, 96), rng.randf_range(0, 96))
		var b := a + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
		if bool(lc.line_clear(mw, int(w.map.h), tt, Damage.RIDGE, a, b)) != Damage.line_clear(w, a, b):
			mism += 1
	check_eq(mism, 0, "native RtsCombat.line_clear == Damage.line_clear on codes 0-13")


# ---------------------------------------------------------------- threads (task 1 proof, kept)
## About n units split over the two sides around their spawns, attack-moving to the centre.
func _big_world(n: int) -> SimWorld:
	var w := make_world({"seed": 11, "victory": "endless"})
	w.ai_state = {}
	var centre := Vector2(float(w.map.w) * 0.5, float(w.map.h) * 0.5)
	for fid in w.factions:
		var sp: Vector2i = w.factions[fid].spawn
		var fdef := String(w.factions[fid].faction_def)
		var inf := "rifleman" if fdef == "human_a" else Content.role(fdef, "infantry")
		var ids := []
		var r := 3
		while ids.size() < n / 2 and r < 40:
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if ids.size() >= n / 2 or (absi(dx) != r and absi(dy) != r):
						continue
					var c := sp + Vector2i(dx, dy)
					if Movement.is_passable(w, c, "foot"):
						ids.append(w.spawn_unit(inf, fid, Vector2(c) + C))
			r += 1
		w.submit({"type": "attack_move", "issuer": fid, "unit_ids": ids, "target": centre})
	return w


func test_threaded_step_same_hash_2k() -> void:
	_set_native(true)
	var ticks := 60
	var a := _big_world(2000)
	check(a.units_of(0).size() + a.units_of(1).size() >= 2000, "2k units spawned")
	for i in ticks:
		a.step()
	var b := _big_world(2000)
	var tid := WorkerThreadPool.add_task(func():
		for i in ticks:
			b.step())
	WorkerThreadPool.wait_for_task_completion(tid)
	check_eq(b.tick, a.tick, "threaded world stepped every tick")
	check_eq(b.state_hash(), a.state_hash(), "same hash threaded vs main (%s)" % NativeCore.path_name(a))
