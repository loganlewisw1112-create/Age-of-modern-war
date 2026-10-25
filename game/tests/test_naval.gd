extends "res://tests/test_base.gd"
## G5 acceptance (owner: NAVAL). CONTRACTS_G5 sections 3.3, 3.4, 8, 11.
## Test sea (River Crossing 96x96 repainted; both HQs stay on land):
##   x <= 27 west land | 28..29 BEACH (y < 50) or CLIFF (y >= 50) | 30..31 SHALLOW (y < 50) or WATER
##   | 32..35 WATER | 36..55 DEEP | 56..59 WATER | 60..63 BEACH | east land; a 2-wide river
##   (WATER, rows 70..71) runs from the sea east to x = 95 (naval_small only).

const Movement = preload("res://sim/systems/movement.gd")
const Naval = preload("res://sim/systems/naval.gd")
const Construction = preload("res://sim/systems/construction.gd")
const Production = preload("res://sim/systems/production.gd")
const NativeCore = preload("res://sim/native_core.gd")
const C := Vector2(0.5, 0.5)


func _code(x: int, y: int) -> int:
	if y >= 70 and y <= 71 and x >= 56:
		return Terrain.WATER
	if x <= 27:
		return Terrain.GRASS
	if x <= 29:
		return Terrain.BEACH if y < 50 else Terrain.CLIFF
	if x <= 31:
		return Terrain.SHALLOW if y < 50 else Terrain.WATER
	if x <= 35:
		return Terrain.WATER
	if x <= 55:
		return Terrain.DEEP
	if x <= 59:
		return Terrain.WATER
	if x <= 63:
		return Terrain.BEACH
	return Terrain.GRASS


func _sea_world(seed_value: int = 3) -> SimWorld:
	var w := make_world({"seed": seed_value})
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	for y in int(w.map.h):
		for x in mw:
			t[y * mw + x] = _code(x, y)
	w.map.terrain = t
	Movement.rebuild_nav(w)
	for fid in w.factions:
		var ex: PackedByteArray = w.fog[fid].explored
		ex.fill(1)
		w.fog[fid].explored = ex
	return w


func _run(w: SimWorld, n: int) -> Array:
	var evs := []
	for i in n:
		w.step()
		evs.append_array(w.events)
	return evs


func _count(evs: Array, type: String, key: String = "", val = null) -> int:
	var n := 0
	for ev in evs:
		if ev.type == type and (key == "" or ev.get(key) == val):
			n += 1
	return n


func test_naval_needs_channel_naval_small_uses_rivers() -> void:
	var w := _sea_world()
	var dd := w.spawn_unit("a_destroyer", 0, Vector2(45, 20) + C)
	var pb := w.spawn_unit("a_patrol_boat", 0, Vector2(45, 24) + C)
	var river := Vector2(80, 70) + C
	check(not Movement.is_passable(w, Vector2i(80, 70), "naval"), "naval refuses the 2-wide river")
	check(Movement.is_passable(w, Vector2i(80, 70), "naval_small"), "naval_small uses the river")
	check(not Movement.is_passable(w, Vector2i(30, 20), "naval"), "naval refuses SHALLOW")
	check(not Movement.can_reach(w, w.entities[dd], river), "destroyer cannot reach the river")
	check(Movement.can_reach(w, w.entities[pb], river), "patrol boat can reach the river")
	check(Movement.can_reach(w, w.entities[dd], Vector2(45, 80) + C), "destroyer can cross the open sea")
	do_cmd(w, 0, {"type": "move", "unit_ids": [pb], "target": river})
	do_cmd(w, 0, {"type": "move", "unit_ids": [dd], "target": Vector2(45, 80) + C})
	_run(w, 500)
	var p: Vector2 = w.entities[pb].pos
	check(p.distance_to(river) < 2.0, "patrol boat sailed up the river (at %s)" % p)
	var q: Vector2 = w.entities[dd].pos
	check(q.distance_to(Vector2(45, 80) + C) < 2.5, "destroyer crossed the sea (at %s)" % q)
	for id in [dd, pb]:
		check(Terrain.is_water(w.terrain_at(w.cell_of(w.entities[id].pos))), "ship %d still on water" % id)


func test_shipyard_shore_placement() -> void:
	var w := _sea_world()
	w.spawn_building("motor_pool", 0, Vector2i(18, 22), true)
	check_eq(Naval.shore_error(w, "a_shipyard", Vector2i(28, 14)), "", "shipyard on beach + shallow is legal")
	check(Naval.shore_error(w, "a_shipyard", Vector2i(22, 14)) != "", "all-land shipyard rejected")
	check(Naval.shore_error(w, "a_shipyard", Vector2i(40, 14)) != "", "all-water shipyard rejected")
	check(Naval.shore_error(w, "a_shipyard", Vector2i(27, 52)) != "", "cliff shore rejected")
	check_eq(Naval.shore_error(w, "a_coastal_battery", Vector2i(26, 30)), "", "battery 3 tiles from water legal")
	check(Naval.shore_error(w, "a_coastal_battery", Vector2i(18, 8)) != "", "battery far inland rejected")
	check_eq(Naval.shore_error(w, "motor_pool", Vector2i(20, 30)), "", "ordinary buildings untouched")
	# the real build path (Construction.placement_error, ORCH wiring)
	check_eq(Construction.placement_error(w, 0, "a_shipyard", Vector2i(28, 14)), "", "placement_error accepts the shore site")
	check(Construction.placement_error(w, 0, "a_shipyard", Vector2i(22, 14)) != "", "placement_error rejects all-land")
	check(Construction.placement_error(w, 0, "a_shipyard", Vector2i(40, 14)) != "", "placement_error rejects open water")
	check(Construction.placement_error(w, 0, "a_coastal_battery", Vector2i(18, 8)) != "", "placement_error rejects inland battery")
	# units spawn on the water side
	var sy := w.spawn_building("a_shipyard", 0, Vector2i(28, 14), true)
	var cells: Array = Production._spawn_cells(w, w.entities[sy], "naval_small", 2, Vector2(26, 26))
	check(not cells.is_empty(), "shipyard has spawn cells")
	for c in cells:
		check(Terrain.is_water(w.terrain_at(c)), "boat spawn cell %s is water" % c)
	var mid := w.spawn_unit("a_patrol_boat", 0, Vector2(cells[0]) + C)
	check(Movement.can_reach(w, w.entities[mid], Vector2(45, 40) + C), "spawned boat can reach the sea")
	var big: Array = Production._spawn_cells(w, w.entities[sy], "naval", 1, Vector2(26, 26))
	check(not big.is_empty() and Movement.is_passable(w, big[0], "naval"), "destroyer spawn cell is deep-draft water")


## Rifleman boards a landing craft lying in the shallows off the beach. Returns [craft, rifleman].
func _loaded_craft(w: SimWorld) -> Array:
	var lc := w.spawn_unit("a_landing_craft", 0, Vector2(31, 20) + C)
	var rf := w.spawn_unit("rifleman", 0, Vector2(28, 20) + C)
	w.submit({"type": "load", "issuer": 0, "carrier": lc, "unit_ids": [rf]})
	for i in 200:
		w.step()
		if not w.entities.has(rf):
			break
	check(not w.entities.has(rf) and (w.entities[lc].get("cargo", []) as Array).size() == 1, "rifleman boarded the landing craft")
	return [lc, rf]


func _teleport(w: SimWorld, id: int, p: Vector2) -> void:
	Movement.stop_path(w.entities[id])
	w.entities[id].pos = p


func test_landing_craft_unloads_only_at_beach() -> void:
	var w := _sea_world()
	check(Naval.beach_ok(w, Vector2i(28, 20)), "BEACH is a landing cell")
	check(Naval.beach_ok(w, Vector2i(30, 20)), "SHALLOW is a landing cell")
	check(not Naval.beach_ok(w, Vector2i(26, 70)), "land behind a cliff is not a landing cell")
	check(not Naval.beach_ok(w, Vector2i(45, 20)), "deep water is not a landing cell")
	var s := _loaded_craft(w)
	var lc: int = s[0]
	var rf: int = s[1]
	_teleport(w, lc, Vector2(31, 70) + C)   # off the cliff coast: grass 3 tiles away, no beach
	var evs := do_cmd(w, 0, {"type": "unload_all", "carrier": lc})
	check(rejected_reason(evs).to_lower().contains("beach"), "unload refused off a cliff coast (%s)" % rejected_reason(evs))
	check_eq((w.entities[lc].get("cargo", []) as Array).size(), 1, "cargo stays aboard off the cliffs")
	evs = do_cmd(w, 0, {"type": "unload", "carrier": lc, "target": Vector2(24, 70) + C})
	_run(w, 60)
	check(not w.entities.has(rf), "targeted unload behind the cliffs never lands the rifleman")
	_teleport(w, lc, Vector2(33, 20) + C)   # off the beach
	evs = do_cmd(w, 0, {"type": "unload_all", "carrier": lc})
	check_eq(rejected_reason(evs), "", "unload accepted at the beach")
	check(w.entities.has(rf), "rifleman is ashore")
	if w.entities.has(rf):
		var c := w.cell_of(w.entities[rf].pos)
		check(Naval.beach_ok(w, c), "rifleman landed on a beach/shallow cell %s" % c)
	# a non-beach carrier (the amphibious crawler drives ashore) is unrestricted
	var cr := w.spawn_unit("m_amphib_crawler", 0, Vector2(31, 70) + C)
	check_eq(Naval.unload_error(w, w.entities[cr], Vector2(31, 70) + C), "", "crawler may unload anywhere")


func test_amphibious_crawler_drives_ashore() -> void:
	var w := _sea_world()
	var cr := w.spawn_unit("m_amphib_crawler", 0, Vector2(45, 30) + C)
	var tank := w.spawn_unit("mbt", 0, Vector2(20, 30) + C)
	var goal := Vector2(20, 34) + C
	check(Terrain.is_water(w.terrain_at(Vector2i(45, 30))), "crawler starts in deep water")
	check(Movement.can_reach(w, w.entities[cr], goal), "crawler can reach the shore from the sea")
	check(not Movement.can_reach(w, w.entities[tank], Vector2(70, 30) + C), "a tank cannot cross the sea")
	do_cmd(w, 0, {"type": "move", "unit_ids": [cr], "target": goal})
	var wet := 0
	for i in 400:
		w.step()
		if Terrain.is_water(w.terrain_at(w.cell_of(w.entities[cr].pos))):
			wet += 1
	var p: Vector2 = w.entities[cr].pos
	check(p.distance_to(goal) < 1.5, "crawler drove ashore (at %s)" % p)
	check(not Terrain.is_water(w.terrain_at(w.cell_of(p))), "crawler ended on dry land")
	check(wet > 10, "crawler swam first (%d wet ticks)" % wet)


func test_bombard_hits_land_cell_in_range() -> void:
	var w := _sea_world()
	var dd := w.spawn_unit("a_destroyer", 0, Vector2(38, 40) + C)
	var pb := w.spawn_unit("a_patrol_boat", 0, Vector2(38, 44) + C)
	var tgt := w.spawn_unit("mbt", 1, Vector2(25, 40) + C)
	var hp0 := float(w.entities[tgt].hp)
	var ammo0 := int(w.entities[dd].ammo)
	var evs := do_cmd(w, 0, {"type": "bombard", "unit_ids": [dd], "cell": [40, 20]})
	check(rejected_reason(evs).contains("land"), "water target refused (%s)" % rejected_reason(evs))
	evs = do_cmd(w, 0, {"type": "bombard", "unit_ids": [dd], "cell": [5, 40]})
	check(rejected_reason(evs).contains("range"), "out-of-range target refused (%s)" % rejected_reason(evs))
	evs = do_cmd(w, 0, {"type": "bombard", "unit_ids": [pb], "cell": [25, 40]})
	check(rejected_reason(evs) != "", "patrol boat cannot bombard")
	evs = do_cmd(w, 0, {"type": "bombard", "unit_ids": [dd], "cell": [25, 40]})
	check_eq(rejected_reason(evs), "", "destroyer bombard accepted")
	evs.append_array(_run(w, 420))
	var shots := 0
	for ev in evs:
		if ev.type == "ShotFired" and bool(ev.get("bombard", false)):
			shots += 1
			check(bool(ev.indirect), "bombard shots are indirect")
	check(shots >= 4, "destroyer fired >= 4 bombard shells (%d)" % shots)
	var hp1: float = float(w.entities[tgt].hp) if w.entities.has(tgt) else 0.0
	check(hp1 < hp0, "target on land took damage (%.1f -> %.1f)" % [hp0, hp1])
	check(int(w.entities[dd].ammo) < ammo0, "bombard spends ammo")
	check(Vector2(w.entities[dd].pos).distance_to(Vector2(38, 40) + C) < 0.6, "destroyer held station while firing")
	do_cmd(w, 0, {"type": "stop", "unit_ids": [dd]})
	var after := _count(_run(w, 200), "ShotFired", "bombard", true)
	check_eq(after, 0, "a new order ends the fire mission")


func test_wreck_sinks_to_shallow_obstruction() -> void:
	var modes := [true, false] if NativeCore.available() else [false]
	for native_on in modes:
		NativeCore.force_off = not native_on
		_wreck_case()
	NativeCore.force_off = false


func _wreck_case() -> void:
	var w := _sea_world()
	var dd := w.spawn_unit("a_destroyer", 0, Vector2(45, 60) + C)
	var cell := Vector2i(45, 60)
	check(Movement.is_passable(w, cell, "naval"), "deep cell open to naval before")
	w.destroy(dd, "killed", 1)
	var sink := int(Content.rules().naval.sink_ticks)
	_run(w, 2)
	check_eq((w.sys_state.naval.wrecks as Array).size(), 1, "wreck registered as sinking")
	check_eq(w.terrain_at(cell), Terrain.DEEP, "still deep while sinking")
	var evs := _run(w, sink + 2)
	check_eq(w.terrain_at(cell), Terrain.SHALLOW, "wreck cell became SHALLOW")
	check(not Movement.is_passable(w, cell, "naval"), "wreck blocks naval")
	check(Movement.is_passable(w, cell, "naval_small"), "naval_small passes the wreck")
	check_eq((w.sys_state.naval.wrecks as Array).size(), 0, "sinking list drained")
	check(_count(evs, "TerrainChanged", "cause", "wreck") == 1, "TerrainChanged(wreck) emitted once")
	var wrecks := 0
	for id in w.entities:
		if w.entities[id].kind == "wreck" and w.entities[id].def == "a_destroyer":
			wrecks += 1
	check_eq(wrecks, 0, "sunk wreck entity removed")


func test_supply_pier_restocks_ships() -> void:
	var w := _sea_world()
	var pier := w.spawn_building("a_supply_pier", 0, Vector2i(29, 8), true)
	var near := w.spawn_unit("a_patrol_boat", 0, Vector2(32, 9) + C)
	var far := w.spawn_unit("a_patrol_boat", 0, Vector2(45, 30) + C)
	for id in [near, far]:
		w.entities[id].ammo = 0
		w.entities[id].fuel = 100.0
	w.factions[0].stock.ammo = 1000
	w.factions[0].stock.fuel = 1000
	var evs := _run(w, 120)
	var e: Dictionary = w.entities[near]
	check(int(e.ammo) > 0, "pier refilled ammo (%d)" % int(e.ammo))
	check(float(e.fuel) > 100.0, "pier refilled fuel (%.1f)" % float(e.fuel))
	check_eq(int(w.factions[0].stock.ammo), 1000 - int(e.ammo), "ammo came from the faction stock")
	check_eq(int(w.entities[far].ammo), 0, "ship out of range not restocked")
	check(_count(evs, "PierRestock") > 0, "PierRestock events")
	check_eq(Naval.pier_at(w, 0, e.pos), pier, "pier_at finds the pier")
	check_eq(Naval.pier_at(w, 0, w.entities[far].pos), -1, "pier_at -1 far away")
	check_eq(Naval.pier_at(w, 1, e.pos), -1, "pier_at ignores other sides")


func test_save_load_mid_sea() -> void:
	var w := _sea_world(7)
	var dd := w.spawn_unit("a_destroyer", 0, Vector2(38, 40) + C)
	var mon := w.spawn_unit("b_monitor", 1, Vector2(50, 20) + C)
	w.spawn_unit("mbt", 1, Vector2(25, 40) + C)
	var s := _loaded_craft(w)
	do_cmd(w, 0, {"type": "bombard", "unit_ids": [dd], "cell": [25, 40]})
	do_cmd(w, 0, {"type": "unload", "carrier": s[0], "target": Vector2(28, 30) + C})
	do_cmd(w, 1, {"type": "move", "unit_ids": [mon], "target": Vector2(50, 85) + C})
	var pb := w.spawn_unit("a_patrol_boat", 0, Vector2(46, 62) + C)
	_run(w, 30)
	w.destroy(pb, "killed", 1)
	_run(w, 5)
	check(bool(w.entities[mon].moving), "monitor under way at save time")
	check_eq((w.sys_state.naval.wrecks as Array).size(), 1, "a wreck is sinking at save time")
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(w2.state_hash(), w.state_hash(), "same hash right after load")
	for i in 150:
		w.step()
		w2.step()
	check_eq(w2.state_hash(), w.state_hash(), "same hash 150 ticks after load (bombard, sinking, unload, sailing)")
	check_eq(w2.terrain_at(Vector2i(46, 62)), Terrain.SHALLOW, "wreck finished sinking after load")
