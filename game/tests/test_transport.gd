extends "res://tests/test_base.gd"
## G4 TRANS (CONTRACTS_G4 section 7): load/unload, capacity, carrier death (ground eject / air kill),
## pop + ledger consistency, Ops prune + victory with cargo, save mid-transport, the officer
## "transport_to_point" mission, determinism (native and fallback).

const Transport = preload("res://sim/systems/transport.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Ops = preload("res://sim/systems/ops.gd")
const NativeCore = preload("res://sim/native_core.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const TMP_DIR := "user://test_transport"


func _world(native_on: bool = true) -> SimWorld:
	NativeCore.force_off = not native_on
	var w := make_world()
	w.ai_state = {}
	for fid in w.factions:
		(w.fog[fid].explored as PackedByteArray).fill(1)
	return w


func _hq(w: SimWorld, fid: int) -> Dictionary:
	for b in w.buildings_of(fid):
		if bool(Content.building(String(b.def)).get("is_hq", false)):
			return b
	return {}


## A free vehicle cell about `off` tiles from fid's HQ.
func _spot(w: SimWorld, fid: int, off: Vector2i) -> Vector2:
	var hq := _hq(w, fid)
	var c := Movement.nearest_free_cell(w, (hq.cell as Vector2i) + off, "vehicle")
	return Vector2(c) + Vector2(0.5, 0.5)


## Carrier + n riflemen next to it. Returns {carrier, units}.
func _setup(w: SimWorld, n: int, off := Vector2i(0, 6)) -> Dictionary:
	var p := _spot(w, 0, off)
	var cid := w.spawn_unit("a_apc", 0, p)
	var ids := []
	for i in n:
		ids.append(w.spawn_unit("rifleman", 0, p + Vector2(1.2 + 0.4 * (i % 4), 0.8 * float(i / 4))))
	w.step()
	return {"carrier": cid, "units": ids}


func _run_until(w: SimWorld, n: int, f: Callable) -> int:
	for i in n:
		w.step()
		if f.call():
			return i + 1
	return -1


func _events(w: SimWorld, type: String) -> Array:
	var out := []
	for ev in w.events:
		if ev.type == type:
			out.append(ev)
	return out


func _pop_recount(w: SimWorld, fid: int) -> int:
	var n := 0
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and int(e.owner) == fid:
			n += int(Content.unit(String(e.def)).get("pop", 1))
		if e.has("cargo"):
			for u in e.cargo:
				if int(u.owner) == fid:
					n += int(Content.unit(String(u.def)).get("pop", 1))
	return n


func _ascending(w: SimWorld) -> bool:
	var last := -1
	for id in w.entities:
		if int(id) <= last:
			return false
		last = int(id)
	return true


func _load_all(w: SimWorld, s: Dictionary) -> int:
	var c: Dictionary = w.entities[s.carrier]
	w.submit({"type": "load", "issuer": 0, "carrier": s.carrier, "unit_ids": s.units})
	return _run_until(w, 300, func(): return (c.get("cargo", []) as Array).size() == (s.units as Array).size())


# ================================================================ tests
func test_content_fields() -> void:
	check_eq(Transport.capacity("a_apc"), 10, "a_apc cargo_slots")
	check_eq(Transport.capacity("b_halftrack"), 8, "b_halftrack cargo_slots")
	check_eq(Transport.cargo_class_of("rifleman"), "foot", "rifleman is foot cargo")
	check_eq(Transport.cargo_size_of("rifleman"), 1, "foot size 1")
	check_eq(Transport.cargo_class_of("mbt"), "vehicle_heavy", "mbt defaults to heavy vehicle")
	check_eq(Transport.cargo_size_of("mbt"), 8, "heavy size 8")
	check_eq(Transport.cargo_class_of("a_apc"), "", "carriers never ride")


func test_load_unload() -> void:
	var w := _world()
	var s := _setup(w, 3)
	var pop0 := int(w.factions[0].pop)
	var c: Dictionary = w.entities[s.carrier]
	w.submit({"type": "load", "issuer": 0, "carrier": s.carrier, "unit_ids": s.units})
	var loaded := []
	var t := _run_until(w, 300, func():
		for ev in _events(w, "UnitLoaded"):
			loaded.append(int(ev.id))
		return loaded.size() == 3)
	check(t > 0, "all three boarded (ticks %d)" % t)
	loaded.sort()
	check_eq(loaded, s.units, "UnitLoaded for every unit")
	check_eq(Transport.cargo_ids(c), s.units, "cargo ascending id")
	for id in s.units:
		check(not w.entities.has(id), "loaded unit %d left w.entities" % id)
		check_eq(int(w.cache.cargo_of.get(id, -1)), int(s.carrier), "cargo_of cache for %d" % id)
	w.step()
	check_eq(int(w.factions[0].pop), pop0, "pop unchanged while units ride")
	check_eq(int(w.factions[0].pop), _pop_recount(w, 0), "pop == recount incl. cargo")
	# unload at a point 8 tiles away: the carrier drives there first
	var cp: Vector2 = c.pos
	var target := _spot(w, 0, Vector2i(6, 10))
	w.submit({"type": "unload", "issuer": 0, "carrier": s.carrier, "target": target})
	var out := []
	t = _run_until(w, 600, func():
		for ev in _events(w, "UnitUnloaded"):
			out.append(ev)
		return out.size() == 3)
	check(t > 0, "unloaded (ticks %d)" % t)
	var cells := {}
	for ev in out:
		var u = w.entities.get(int(ev.id))
		check(u != null, "unit %d back in w.entities with the same id" % int(ev.id))
		if u == null:
			continue
		var q: Vector2 = u.pos
		check(q.distance_to(target) <= 6.0, "unit %d dropped near the target (%.1f)" % [int(ev.id), q.distance_to(target)])
		check(Movement.is_passable_e(w, u, w.cell_of(q)), "drop cell passable")
		cells[w.cell_of(q)] = true
		check_eq(String(ev.cause), "unload", "cause unload")
	check_eq(cells.size(), 3, "distinct drop cells")
	check(cp.distance_to(c.pos) > 3.0, "carrier drove to the target first")
	check(_ascending(w), "w.entities still ascending id after reinsert")
	check(Transport.cargo_ids(c).is_empty(), "carrier empty")
	w.step()
	check_eq(int(w.factions[0].pop), pop0, "pop unchanged after unload")


func test_unload_all_and_validation() -> void:
	var w := _world()
	var s := _setup(w, 2)
	var ev := do_cmd(w, 0, {"type": "unload_all", "carrier": s.carrier})
	check_eq(rejected_reason(ev), "The transport is empty.", "unload_all on empty rejected")
	ev = do_cmd(w, 0, {"type": "load", "carrier": s.units[0], "unit_ids": [s.units[1]]})
	check_eq(rejected_reason(ev), "Select one of your transports.", "rifleman is not a carrier")
	ev = do_cmd(w, 1, {"type": "load", "carrier": s.carrier, "unit_ids": s.units})
	check(rejected_reason(ev) != "", "enemy cannot use my carrier")
	check(_load_all(w, s) > 0, "loaded")
	var c: Dictionary = w.entities[s.carrier]
	ev = do_cmd(w, 0, {"type": "unload", "carrier": s.carrier, "cargo_ids": [999999]})
	check_eq(rejected_reason(ev), "None of those units are aboard.", "unknown cargo id rejected")
	ev = do_cmd(w, 0, {"type": "unload", "carrier": s.carrier, "target": Vector2(-50, -50)})
	check_eq(rejected_reason(ev), "The unload point is outside the map.", "off-map target rejected")
	ev = do_cmd(w, 0, {"type": "unload", "carrier": s.carrier, "cargo_ids": [s.units[1]]})
	check(w.entities.has(s.units[1]) and not w.entities.has(s.units[0]), "partial unload by cargo_ids")
	ev = do_cmd(w, 0, {"type": "unload_all", "carrier": s.carrier})
	check(w.entities.has(s.units[0]), "unload_all drops the rest at the carrier")
	var q: Vector2 = w.entities[s.units[0]].pos
	check(q.distance_to(c.pos) <= 4.0, "dropped around the carrier")
	check(_ascending(w), "ascending ids")


func test_capacity() -> void:
	var w := _world()
	var s := _setup(w, 11)
	var c: Dictionary = w.entities[s.carrier]
	w.submit({"type": "load", "issuer": 0, "carrier": s.carrier, "unit_ids": s.units})
	var fails := []
	_run_until(w, 300, func():
		for ev in _events(w, "LoadFailed"):
			fails.append(ev)
		return fails.size() >= 1 and (c.get("cargo", []) as Array).size() == 10)
	check_eq((c.get("cargo", []) as Array).size(), 10, "10 slots filled")
	check_eq(Transport.free_slots(c), 0, "no free slots")
	check_eq(fails.size(), 1, "11th unit refused")
	if not fails.is_empty():
		check_eq(String(fails[0].reason), "The transport is full.", "full reason")
		check(w.entities.has(int(fails[0].id)), "refused unit stays in the world")
	var ev := do_cmd(w, 0, {"type": "load", "carrier": s.carrier, "unit_ids": [fails[0].id if not fails.is_empty() else s.units[10]]})
	check_eq(rejected_reason(ev), "The transport is full.", "load into a full carrier rejected")
	var tank := w.spawn_unit("mbt", 0, c.pos + Vector2(2, 0))
	ev = do_cmd(w, 0, {"type": "load", "carrier": s.carrier, "unit_ids": [tank]})
	check_eq(rejected_reason(ev), "This transport cannot carry that unit.", "APC refuses a tank (class)")


func test_carrier_destroyed_ground_ejects() -> void:
	var w := _world()
	var s := _setup(w, 4)
	check(_load_all(w, s) > 0, "loaded")
	var c: Dictionary = w.entities[s.carrier]
	var u0: Dictionary = c.cargo[0]
	u0.hp = 10.0  # below the eject cap: keeps its own hp
	var lost0 := int(w.factions[0].stats.lost)
	var killed0 := int(w.factions[1].stats.killed)
	var pop0 := int(w.factions[0].pop)
	w.destroy(s.carrier, "killed", 1)
	w.step()  # Ops.prune at the end of the step sweeps the dead carrier
	for id in s.units:
		var u = w.entities.get(id)
		check(u != null, "cargo %d ejected alive" % id)
		if u != null:
			var cap := float(u.max_hp) * 0.5
			check(float(u.hp) <= cap + 0.001, "ejected at <= 50%% hp (%s)" % str(u.hp))
	check_eq(float(w.entities[s.units[0]].hp), 10.0, "low-hp unit keeps its hp")
	check_eq(int(w.factions[0].stats.lost), lost0 + 1, "only the carrier counts as lost")
	check_eq(int(w.factions[1].stats.killed), killed0 + 1, "killer credited for the carrier only")
	check(_ascending(w), "ascending ids after eject")
	check(not w.cache.cargo_of.has(s.units[0]), "cargo_of cleaned")
	w.step()
	check_eq(int(w.factions[0].pop), pop0 - 3, "pop: carrier (3) gone, cargo still counted")
	check_eq(int(w.factions[0].pop), _pop_recount(w, 0), "pop == recount")


func test_carrier_destroyed_air_kills() -> void:
	var units: Dictionary = Content.table("units")
	units["t_test_heli"] = {"name": "Test Heli", "faction": "human_a", "move_class": "air_low", "hp": 300,
		"speed": 4.0, "sight": 8, "weapon": "", "pop": 2, "radius": 0.6, "cargo_slots": 4, "cargo_accepts": ["foot"]}
	var w := _world()
	var p := _spot(w, 0, Vector2i(0, 6))
	var hid := w.spawn_unit("t_test_heli", 0, p)
	var ids := [w.spawn_unit("rifleman", 0, p + Vector2(0.5, 0)), w.spawn_unit("rifleman", 0, p + Vector2(0, 0.5))]
	var s := {"carrier": hid, "units": ids}
	check(_load_all(w, s) > 0, "heli loaded")
	var lost0 := int(w.factions[0].stats.lost)
	w.entities[hid].last_attacker = w.spawn_unit("rifleman", 1, _spot(w, 1, Vector2i(0, 6)))  # destroyed outside a step: no event this step
	w.destroy(hid, "killed", 1)
	w.step()
	var dead := 0
	for ev in w.events:
		if ev.type == "EntityDestroyed" and String(ev.cause) == "carrier_destroyed":
			dead += 1
			check_eq(int(ev.killer_owner), 1, "cargo death credited to the carrier's killer")
	check_eq(dead, 2, "air: both riders die through w.destroy")
	for id in ids:
		check(not w.entities.has(id), "rider %d gone" % id)
	check_eq(int(w.factions[0].stats.lost), lost0 + 3, "lost = carrier + 2 riders")
	w.step()
	check_eq(int(w.factions[0].pop), _pop_recount(w, 0), "pop == recount after air loss")
	units.erase("t_test_heli")


func test_ops_prune_and_victory_with_cargo() -> void:
	var w := _world()
	var s := _setup(w, 3)
	var p: Vector2 = w.entities[s.carrier].pos
	var oid := w.spawn_unit("officer", 0, p + Vector2(-1, 0))
	w.step()
	do_cmd(w, 0, {"type": "assign_officer", "officer_id": oid, "unit_ids": s.units})
	check(_load_all(w, s) > 0, "loaded")
	for i in 5:
		w.step()
	var g := Ops.group_led_by(w, oid)
	check(not g.is_empty(), "group survives")
	check_eq((g.members as Array).size(), 3, "riders stay group members")
	# officer rides too: the group must not dissolve
	w.submit({"type": "load", "issuer": 0, "carrier": s.carrier, "unit_ids": [oid]})
	_run_until(w, 200, func(): return not w.entities.has(oid))
	w.step()
	check(not Ops.group_led_by(w, oid).is_empty(), "officer in cargo keeps the group")
	# victory: an hq-less scenario side with only a loaded carrier stays alive
	var vs: Dictionary = w.sys_state.get("victory", {})
	vs["hqless"] = [0]
	w.sys_state["victory"] = vs
	for b in w.buildings_of(0):
		w.destroy(int(b.id), "test")
	for e in w.units_of(0):
		if int(e.id) != int(s.carrier):
			w.destroy(int(e.id), "test")
	for i in 5:
		w.step()
	check(bool(w.factions[0].alive), "side with only a loaded carrier is alive")
	check_eq(int(w.factions[0].pop), _pop_recount(w, 0), "pop counts cargo")


func test_save_mid_transport() -> void:
	var w := _world()
	var s := _setup(w, 4)
	var ids: Array = s.units
	# two ride, two are still walking up when we save; then the carrier heads off to unload
	w.submit({"type": "load", "issuer": 0, "carrier": s.carrier, "unit_ids": [ids[0], ids[1]]})
	var c: Dictionary = w.entities[s.carrier]
	_run_until(w, 200, func(): return (c.get("cargo", []) as Array).size() == 2)
	var far := _spot(w, 0, Vector2i(8, 12))
	for id in [ids[2], ids[3]]:
		w.entities[id].pos = c.pos + Vector2(5, 0)
		preload("res://sim/hot_state.gd").touch(w, id)  # CORE10K-3: direct pos/path write -> hot state
	w.submit({"type": "load", "issuer": 0, "carrier": s.carrier, "unit_ids": [ids[2], ids[3]]})
	w.step()
	w.step()
	check(String(w.entities[ids[2]].order.type) == "board", "unit still boarding at save time")
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var path := TMP_DIR + "/mid.sav"
	check_eq(SaveSystem.save(w, path), "", "save ok")
	var l: SimWorld = SaveSystem.load(path)
	check(l != null, "load ok")
	if l == null:
		return
	check_eq(l.state_hash(), w.state_hash(), "hash equal after load")
	var t_unload := w.tick + 60
	for x in [w, l]:
		x.submit({"type": "unload", "issuer": 0, "carrier": s.carrier, "target": far, "tick": t_unload})
		x.run_ticks(400)
	check_eq(l.state_hash(), w.state_hash(), "hash equal after boarding + transit + unload")
	check(w.entities.has(ids[0]) and l.entities.has(ids[0]), "unloaded in both")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")


func _mission_run(native_on: bool) -> Dictionary:
	var w := _world(native_on)
	var s := _setup(w, 4)
	var p: Vector2 = w.entities[s.carrier].pos
	var oid := w.spawn_unit("officer", 0, p + Vector2(-1, 0.5))
	w.step()
	do_cmd(w, 0, {"type": "assign_officer", "officer_id": oid, "unit_ids": s.units + [s.carrier]})
	var target := _spot(w, 0, Vector2i(10, 14))
	var ev := do_cmd(w, 0, {"type": "set_mission", "officer_id": oid, "mission": "transport_to_point", "target": target, "radius": 5.0})
	check_eq(rejected_reason(ev), "", "transport mission accepted")
	var phases := []
	var loaded := 0
	var unloaded := 0
	var max_cargo := 0
	var c: Dictionary = w.entities[s.carrier]
	for i in 1500:
		w.step()
		for e in w.events:
			if e.type == "OfficerReport" and int(e.officer) == oid and (phases.is_empty() or phases[-1] != e.phase):
				phases.append(e.phase)
			elif e.type == "UnitLoaded":
				loaded += 1
			elif e.type == "UnitUnloaded":
				unloaded += 1
		max_cargo = maxi(max_cargo, (c.get("cargo", []) as Array).size())
		if phases.has("hold"):
			break
	var near := 0
	for id in s.units:
		var u = w.entities.get(id)
		if u != null and (u.pos as Vector2).distance_to(target) <= 7.0:
			near += 1
	return {"w": w, "phases": phases, "loaded": loaded, "unloaded": unloaded, "max_cargo": max_cargo, "near": near}


func test_officer_transport_mission() -> void:
	var r := _mission_run(true)
	var ph: Array = r.phases
	check(ph.has("load") and ph.has("transit"), "phases load -> transit (%s)" % str(ph))
	check(ph.has("move") and ph.has("secure"), "then move -> secure (%s)" % str(ph))
	check(ph.has("hold"), "mission reaches hold (%s)" % str(ph))
	check(int(r.loaded) >= 4, "riders boarded (%d)" % int(r.loaded))
	check_eq(int(r.unloaded), int(r.loaded), "everyone who boarded got off")
	check(int(r.max_cargo) >= 4, "carrier carried the squad (%d)" % int(r.max_cargo))
	check(int(r.near) >= 3, "members at the objective (%d)" % int(r.near))
	var w: SimWorld = r.w
	check_eq(int(w.factions[0].pop), _pop_recount(w, 0), "pop == recount after the mission")


func test_officer_transport_mission_needs_carrier() -> void:
	var w := _world()
	var s := _setup(w, 2)
	var oid := w.spawn_unit("officer", 0, (w.entities[s.carrier].pos as Vector2) + Vector2(-1, 0))
	w.step()
	do_cmd(w, 0, {"type": "assign_officer", "officer_id": oid, "unit_ids": s.units})
	var ev := do_cmd(w, 0, {"type": "set_mission", "officer_id": oid, "mission": "transport_to_point", "target": _spot(w, 0, Vector2i(8, 8))})
	check_eq(rejected_reason(ev), "Assign a transport to this officer for a transport mission.", "needs a carrier")


func test_determinism() -> void:
	var modes := [true, false] if NativeCore.available() else [false]
	var hashes := []
	for m in modes:
		var a := _mission_run(m)
		var b := _mission_run(m)
		check_eq((a.w as SimWorld).state_hash(), (b.w as SimWorld).state_hash(), "same run twice, native=%s" % str(m))
		hashes.append((a.w as SimWorld).state_hash())
	if hashes.size() == 2:
		check_eq(hashes[0], hashes[1], "native == fallback hash")
	NativeCore.force_off = false


func test_coalition_stealth_transport_deployment_and_extraction() -> void:
	var cfg := SimWorld.default_config()
	cfg.sides = [
		{"faction": "shadow_coalition", "stage": 10, "ai": false, "team": 0},
		{"faction": "human_a", "stage": 10, "ai": false, "team": 1},
	]
	var w := SimWorld.new_match(cfg)
	var Air = preload("res://sim/systems/air.gd")
	var craft := Content.unit("x_stealth_transport")
	var launch_zones: Array[Vector2i] = []
	for y in range(6, 25):
		for x in range(6, 25):
			var cell := Vector2i(x, y)
			if Air.landing_ok(w, cell, craft) and (launch_zones.is_empty() or cell.distance_to(launch_zones[0]) >= 8.0):
				launch_zones.append(cell)
				if launch_zones.size() == 2:
					break
		if launch_zones.size() == 2:
			break
	check_eq(launch_zones.size(), 2, "two valid open landing zones")
	if launch_zones.size() != 2:
		return
	var start := Vector2(launch_zones[0]) + Vector2(0.5, 0.5)
	var destination := Vector2(launch_zones[1]) + Vector2(0.5, 0.5)
	var cid := w.spawn_unit("x_stealth_transport", 0, start)
	var uid := w.spawn_unit("x_death_strike", 0, start + Vector2.RIGHT)
	w.step()
	var carrier: Dictionary = w.entities[cid]
	check_eq(Transport.capacity(carrier.def), 8, "transport carries eight slots")
	check(w.submit({"type": "land_at", "issuer": 0, "unit_ids": [cid], "cell": [launch_zones[0].x, launch_zones[0].y]}).ok,
		"initial land order accepted")
	check(_run_until(w, 100, func(): return bool(carrier.air_landed)) > 0, "lands for boarding")
	var board := {"type": "load", "issuer": 0, "carrier": cid, "unit_ids": [uid]}
	check(w.submit(board).ok, "Death squad can board")
	check(_run_until(w, 160, func(): return Transport.cargo_ids(carrier) == [uid]) > 0, "squad boards")
	check(w.submit({"type": "unload", "issuer": 0, "carrier": cid, "target": destination}).ok, "deployment order accepted")
	check(_run_until(w, 300, func(): return w.entities.has(uid) and Transport.cargo_ids(carrier).is_empty()) > 0, "squad deploys with the same ID")
	check(Vector2(carrier.pos).distance_to(destination) <= 1.0 and bool(carrier.air_landed), "craft reaches the deployment LZ")
	check(w.submit(board).ok, "extraction boarding accepted")
	check(_run_until(w, 160, func(): return Transport.cargo_ids(carrier) == [uid]) > 0, "squad reboards for extraction")
	check(w.submit({"type": "move", "issuer": 0, "unit_ids": [cid], "target": start}).ok, "transport can depart")
	check(_run_until(w, 300, func(): return not bool(carrier.air_landed) and Vector2(carrier.pos).distance_to(start) <= 1.0) > 0,
		"transport extracts with the squad still aboard")
	check_eq(Transport.cargo_ids(carrier), [uid], "extracted squad stays aboard")
