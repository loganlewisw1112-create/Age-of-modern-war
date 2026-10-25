extends "res://tests/test_base.gd"
## G6 acceptance (owner: NAVAL6). CONTRACTS_G6 sections 9, 11, 17 (D38 subs/sonar, D39 carriers).
## Test sea = the G5 test_naval sea (River Crossing 96x96 repainted, height removed so it is flat):
##   x <= 27 west land | 28..29 BEACH (y < 50) or CLIFF (y >= 50) | 30..31 SHALLOW (y < 50) or WATER
##   | 32..35 WATER | 36..55 DEEP | 56..59 WATER | 60..63 BEACH | east land; river rows 70..71 (x >= 56).

const Movement = preload("res://sim/systems/movement.gd")
const Naval = preload("res://sim/systems/naval.gd")
const Sonar = preload("res://sim/systems/sonar.gd")
const Support = preload("res://sim/systems/support.gd")
const Transport = preload("res://sim/systems/transport.gd")
const Fog = preload("res://sim/systems/fog.gd")
const HotState = preload("res://sim/hot_state.gd")
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
	w.map.erase("height")
	w.map.erase("ramps")
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
		w.factions[fid].stock.ammo = 5000
		w.factions[fid].stock.fuel = 5000
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


func _teleport(w: SimWorld, id: int, p: Vector2) -> void:
	Movement.stop_path(w.entities[id])
	w.entities[id].pos = p
	HotState.touch(w, id)


## Submits a command through w.submit when it is registered, else validates + applies it directly
## (lay_sea_mines until ORCH registers it in SimWorld.COMMANDS). Returns the rejection reason ("" = ok).
func _cmd(w: SimWorld, fid: int, cmd: Dictionary, sys) -> String:
	cmd.issuer = fid
	if SimWorld.COMMANDS.has(String(cmd.type)):
		return rejected_reason(do_cmd(w, fid, cmd))
	var why: String = sys.validate_command(w, cmd)
	if why == "":
		sys.apply_command(w, cmd)
	w.step()
	return why


func _dive(w: SimWorld, fid: int, ids: Array, on: bool = true) -> String:
	return rejected_reason(do_cmd(w, fid, {"type": "submerge", "unit_ids": ids, "on": on}))


# ---------------------------------------------------------------- D38 submarines and sonar
func test_submerged_sub_invisible() -> void:
	var w := _sea_world()
	var sub := w.spawn_unit("a_submarine", 0, Vector2(45, 20) + C)
	var gb := w.spawn_unit("b_river_gunboat", 1, Vector2(45, 25) + C)   # no sonar, sight 9
	w.entities[sub].ammo = 0   # holds fire: a shot would reveal it for 5 s (covered by test_visible_5s_after_firing)
	check_eq(Sonar.udef("b_river_gunboat").sonar, 0.0, "gunboat has no sonar")
	_run(w, 3)
	check(Fog.entity_visible(w, 1, w.entities[sub]), "surfaced sub inside enemy sight is visible")
	check(not Sonar.submerged(w.entities[sub]), "starts surfaced")
	check_eq(_dive(w, 0, [sub]), "", "submerge accepted")
	check(Sonar.submerged(w.entities[sub]), "e.submerged after the order")
	check_eq(int(w.sys_state.sonar.n_sub), 1, "sys_state.sonar counts the submerged sub")
	_run(w, 2)
	check(not Sonar.visible_to(w, 1, w.entities[sub]), "submerged sub hidden from side 1 (Sonar.visible_to)")
	check(not Fog.entity_visible(w, 1, w.entities[sub]), "submerged sub hidden from side 1 (Fog.entity_visible)")
	check(Fog.entity_visible(w, 0, w.entities[sub]), "owner still sees its sub")
	check(not Sonar.detected_by(w, 1, w.entities[sub]), "no sonar contact")
	var hp := float(w.entities[sub].hp)
	_run(w, 80)
	check(int(w.entities[gb].get("target", -1)) != sub, "the enemy gunboat never targets the hidden sub")
	check_eq(float(w.entities[sub].hp), hp, "hidden sub takes no fire")
	check_eq(_dive(w, 0, [sub]), "Already submerged.", "second dive refused")
	var sh := w.spawn_unit("a_submarine", 0, Vector2(30, 12) + C)   # SHALLOW
	check_eq(_dive(w, 0, [sh]), "Too shallow to dive here.", "no dive on SHALLOW")
	check(_dive(w, 1, [sub]) != "", "cannot order an enemy sub")
	check_eq(_dive(w, 0, [sub], false), "", "surface accepted")
	_run(w, 2)
	check(Fog.entity_visible(w, 1, w.entities[sub]), "surfaced again: visible")
	check_eq(int(w.sys_state.sonar.n_sub), 0, "n_sub back to 0")


func test_sonar_detects_in_range() -> void:
	var w := _sea_world()
	var sub := w.spawn_unit("a_submarine", 0, Vector2(45, 20) + C)
	var mon := w.spawn_unit("b_monitor", 1, Vector2(45, 36) + C)   # warship: sonar 10 (rules sonar_by_role)
	var sw := w.spawn_unit("a_minesweeper", 1, Vector2(40, 34) + C)   # def sonar 6
	w.entities[sub].ammo = 0   # holds fire (a shot reveals it regardless of sonar)
	check_eq(Sonar.udef("a_destroyer").sonar, 10.0, "destroyer sonar 10")
	check_eq(Sonar.udef("a_aa_frigate").sonar, 8.0, "AA frigate sonar 8")
	check_eq(Sonar.udef("a_minesweeper").sonar, 6.0, "minesweeper sonar 6")
	check_eq(Sonar.udef("a_supply_ship_a").sonar, 0.0, "supply ship has no sonar")
	_dive(w, 0, [sub])
	_run(w, 2)
	check(not Sonar.detected_by(w, 1, w.entities[sub]), "16 tiles: outside every sonar")
	_teleport(w, mon, Vector2(45, 29) + C)   # 9 tiles: inside sonar 10
	var evs := _run(w, 20)
	check(Sonar.detected_by(w, 1, w.entities[sub]), "monitor sonar holds contact at 9 tiles")
	check(Sonar.visible_to(w, 1, w.entities[sub]), "detected sub visible to side 1")
	check(Fog.entity_visible(w, 1, w.entities[sub]), "detected sub visible in fog")
	check_eq(_count(evs, "SonarContact", "id", sub), 1, "one SonarContact event")
	check_eq(w.entities[sub].get("sonar_seen", []), [1], "e.sonar_seen = [1]")
	_teleport(w, mon, Vector2(45, 45) + C)
	_teleport(w, sw, Vector2(45, 27) + C)   # 7 tiles: outside sonar 6
	_run(w, 2)
	check(not Sonar.detected_by(w, 1, w.entities[sub]), "minesweeper (6) loses it at 7 tiles")
	check(not w.entities[sub].has("sonar_seen"), "contact list cleared")
	w.factions[1].research.done.append("g6_sonar_1")   # sonar x1.3: 7.8 tiles
	_run(w, 2)
	check(Sonar.detected_by(w, 1, w.entities[sub]), "g6_sonar_1 extends the minesweeper sonar past 7 tiles")
	_teleport(w, sw, Vector2(45, 25) + C)
	w.factions[1].research.done.erase("g6_sonar_1")
	_run(w, 2)
	check(Sonar.detected_by(w, 1, w.entities[sub]), "minesweeper detects at 5 tiles")
	check(Sonar.detected_by(w, 0, w.entities[sub]), "own side always 'detects' its sub")


func test_visible_5s_after_firing() -> void:
	var w := _sea_world()
	var sub := w.spawn_unit("a_submarine", 0, Vector2(45, 20) + C)
	_dive(w, 0, [sub])
	var e: Dictionary = w.entities[sub]
	e.last_fired_tick = w.tick - 100
	check(Sonar.visible_to(w, 1, e), "fired 5.0 s ago: still revealed")
	e.last_fired_tick = w.tick - 101
	check(not Sonar.visible_to(w, 1, e), "fired 5.05 s ago: hidden")
	e.erase("last_fired_tick")
	var gb := w.spawn_unit("b_river_gunboat", 1, Vector2(45, 27) + C)   # 7 tiles: torpedo range 10
	var fired := -1
	for i in 400:
		w.step()
		for ev in w.events:
			if ev.type == "ShotFired" and int(ev.shooter) == sub and fired < 0:
				fired = w.tick
		if fired >= 0:
			break
	check(fired >= 0, "the submerged sub fires its torpedo at the gunboat")
	if fired < 0:
		return
	check(Sonar.visible_to(w, 1, e), "revealed right after firing")
	check(Fog.entity_visible(w, 1, e) or not w.entities.has(gb), "fog shows the firing sub to side 1")
	var last := int(e.get("last_fired_tick", fired))
	while w.tick < last + 100:
		w.step()
		last = int(e.get("last_fired_tick", last))
	check(Sonar.visible_to(w, 1, e), "still revealed 5 s after the last shot")
	var hidden_seen := false
	for i in 30:
		w.step()
		if w.tick - int(e.get("last_fired_tick", 0)) > 100 and not Sonar.visible_to(w, 1, e):
			hidden_seen = true
	check(hidden_seen, "hidden again once 5 s pass without a shot")


func test_surfaced_sub_faster_and_resuppliable() -> void:
	var w := _sea_world()
	var a := w.spawn_unit("a_submarine", 0, Vector2(40, 10) + C)
	var b := w.spawn_unit("a_submarine", 0, Vector2(50, 10) + C)
	_dive(w, 0, [b])
	check_eq(Sonar.speed_mult(w, w.entities[b]), 0.75, "submerged speed x0.75 (def submersible)")
	check_eq(Sonar.speed_mult(w, w.entities[a]), 1.0, "surfaced speed x1")
	do_cmd(w, 0, {"type": "move", "unit_ids": [a], "target": Vector2(40, 45) + C})
	do_cmd(w, 0, {"type": "move", "unit_ids": [b], "target": Vector2(50, 45) + C})
	var a0: Vector2 = w.entities[a].pos
	var b0: Vector2 = w.entities[b].pos
	_run(w, 100)
	var da := Vector2(w.entities[a].pos).distance_to(a0)
	var db := Vector2(w.entities[b].pos).distance_to(b0)
	check(da > 5.0, "surfaced sub sailed (%.2f tiles)" % da)
	check(db < da * 0.85, "submerged sub is slower (%.2f vs %.2f tiles)" % [db, da])
	# resupply: a Supply Pier restocks the surfaced sub only
	var w2 := _sea_world()
	w2.spawn_building("a_supply_pier", 0, Vector2i(29, 8), true)
	var s := w2.spawn_unit("a_submarine", 0, Vector2(33, 9) + C)
	w2.entities[s].ammo = 0
	check_eq(_dive(w2, 0, [s]), "", "dives by the pier")
	check(not Support.needs_supply(w2, w2.entities[s]), "a submerged sub is never needy (Support)")
	var evs := _run(w2, 60)
	check_eq(int(w2.entities[s].ammo), 0, "submerged: the pier does not restock")
	check_eq(_count(evs, "PierRestock", "id", s), 0, "no PierRestock while submerged")
	_dive(w2, 0, [s], false)
	check(Support.needs_supply(w2, w2.entities[s]), "surfaced and empty: needy again")
	evs = _run(w2, 60)
	check(int(w2.entities[s].ammo) > 0, "surfaced: the pier restocks it (%d)" % int(w2.entities[s].ammo))
	check(_count(evs, "PierRestock", "id", s) > 0, "PierRestock once surfaced")


# ---------------------------------------------------------------- D39 carrier
func test_carrier_rebase_sortie_rearm() -> void:
	var w := _sea_world()
	var Airfield = SimWorld.Airfield
	var Air = SimWorld.Air
	var cv := w.spawn_unit("a_carrier", 0, Vector2(44, 30) + C)
	var evs := _run(w, 1)
	check(Airfield.fields(w).has(cv), "the carrier is registered as a mobile air field")
	check_eq(_count(evs, "CarrierDeckReady", "id", cv), 1, "CarrierDeckReady event")
	check_eq(int(Airfield.slot_cap(w, cv)), 4, "4 light hangar slots")
	check_eq(int(Airfield.free_slots(w, cv).light), 4, "4 free light homes")
	var jet := w.spawn_unit("a_strike_jet", 0, Vector2(20, 30) + C)
	var tgt := w.spawn_unit("mbt", 1, Vector2(75, 30) + C)
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "rebase", "unit_ids": [jet], "building_id": cv})), "", "rebase to the carrier accepted")
	var landed := false
	for i in 1500:
		w.step()
		var j: Dictionary = w.entities[jet]
		if int(j.get("air_home", -1)) == cv and Air.is_landed(j) and int(j.get("air_at", -1)) == cv:
			landed = true
			break
	check(landed, "the jet landed on the carrier (home %s phase %s)" % [w.entities[jet].get("air_home"), Air.phase(w, jet)])
	check_eq(int(Airfield.free_slots(w, cv).light), 3, "one carrier slot taken")
	w.entities[jet].ammo = maxi(1, int(w.entities[jet].get("ammo", 1)))
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "sortie", "unit_ids": [jet], "target_id": tgt})), "", "sortie from the carrier accepted")
	var left := false
	var back := false
	var serviced := false
	for i in 2400:
		w.step()
		for ev in w.events:
			if ev.type == "AircraftServiced" and int(ev.id) == jet and int(ev.at) == cv:
				serviced = true
		var j2: Dictionary = w.entities.get(jet, {})
		if j2.is_empty():
			break
		if not Air.is_landed(j2):
			left = true
		elif left and int(j2.get("air_at", -1)) == cv:
			back = true
		if back and serviced:
			break
	check(left, "the jet took off from the carrier")
	check(back, "the jet came back to the carrier")
	check(serviced, "the jet was rearmed on the carrier deck")
	w.factions[0].research.done.append("g6_carrier_1")
	_run(w, 21)
	check_eq(int(Airfield.slot_cap(w, cv)), 6, "g6_carrier_1: +2 carrier slots")
	# the carrier hull rearms at a Supply Ship
	var ss := w.spawn_unit("a_supply_ship_a", 0, Vector2(44, 34) + C)
	w.entities[cv].ammo = 10
	_run(w, 80)
	check(int(w.entities[cv].ammo) > 10, "carrier rearmed by the Supply Ship (%d)" % int(w.entities[cv].ammo))
	# or at a Supply Pier
	var w2 := _sea_world()
	w2.spawn_building("a_supply_pier", 0, Vector2i(29, 8), true)
	var c2 := w2.spawn_unit("a_carrier", 0, Vector2(33, 9) + C)
	w2.entities[c2].ammo = 10
	_run(w2, 60)
	check(int(w2.entities[c2].ammo) > 10, "carrier rearmed at the Supply Pier (%d)" % int(w2.entities[c2].ammo))
	w.destroy(cv, "test")
	_run(w, 2)
	check(not Airfield.fields(w).has(cv), "a sunk carrier drops its field")
	check(w.entities.has(ss), "supply ship unaffected")


# ---------------------------------------------------------------- supply ships
func test_supply_ships_auto_resupply_at_sea() -> void:
	var w := _sea_world()
	var pier := w.spawn_building("a_supply_pier", 0, Vector2i(29, 8), true)
	var ss := w.spawn_unit("a_supply_ship_a", 0, Vector2(42, 24) + C)
	var dd := w.spawn_unit("a_destroyer", 0, Vector2(46, 34) + C)
	var tank := w.spawn_unit("mbt", 0, Vector2(26, 26) + C)   # land, inside the radius: never claimed
	w.step()
	w.entities[dd].ammo = 12
	w.entities[tank].ammo = 1
	var ev := do_cmd(w, 0, {"type": "set_auto_resupply", "unit_id": ss, "mode": "station", "center": [42.5, 24.5], "radius": 18.0})
	check_eq(rejected_reason(ev), "", "a Supply Ship accepts Auto resupply")
	var claimed := false
	var resumed := false
	var tank_claimed := false
	for i in 1600:
		w.step()
		for e2 in w.events:
			if e2.type == "ResupplyClaimed" and int(e2.unit) == tank:
				tank_claimed = true
			if e2.type == "ResupplyClaimed" and int(e2.unit) == dd:
				claimed = true
			if e2.type == "ResupplyResumed" and int(e2.unit) == dd:
				resumed = true
		if resumed:
			break
	check(claimed, "the destroyer was claimed at sea")
	check(not tank_claimed, "the land tank is never claimed by a ship")
	check_eq(int(w.entities[dd].ammo), int(Content.unit("a_destroyer").ammo_max), "destroyer fully restocked at sea")
	check(resumed, "the destroyer resumed its order")
	check(Terrain.is_water(w.terrain_at(w.cell_of(w.entities[ss].pos))), "the Supply Ship stayed on water")
	# empty load: the ship reloads at the Supply Pier
	(Support.truck_state(w, ss) as Dictionary).load = 0
	var empty := false
	var refilled := false
	for i in 1600:
		w.step()
		for e3 in w.events:
			if e3.type == "TruckEmpty" and int(e3.truck) == ss:
				empty = true
			if e3.type == "TruckRefilled" and int(e3.truck) == ss:
				refilled = int(e3.building) == pier
		if refilled:
			break
	check(empty, "TruckEmpty for the Supply Ship")
	check(refilled, "the Supply Ship reloaded at the Supply Pier (pos %s)" % str(w.entities[ss].pos))
	check(int(Support.truck_state(w, ss).load) > 0, "load restored")


# ---------------------------------------------------------------- hover
func test_hover_crosses_land_and_water() -> void:
	var w := _sea_world()
	for code in [Terrain.GRASS, Terrain.BEACH, Terrain.SHALLOW, Terrain.WATER, Terrain.DEEP]:
		check(Terrain.passable(code, "hover"), "hover passes terrain %d" % code)
	check(not Movement.is_passable(w, Vector2i(28, 60), "hover"), "hover stops at a cliff")
	var hc := w.spawn_unit("a_hovercraft", 0, Vector2(20, 20) + C)
	var ht := w.spawn_unit("m_hover_tank", 0, Vector2(20, 24) + C)
	var goal := Vector2(70, 22) + C
	check(Movement.can_reach(w, w.entities[hc], goal), "hovercraft can reach the far shore")
	do_cmd(w, 0, {"type": "move", "unit_ids": [hc, ht], "target": goal})
	var deep := {hc: false, ht: false}
	for i in 900:
		w.step()
		for id in [hc, ht]:
			if w.terrain_at(w.cell_of(w.entities[id].pos)) == Terrain.DEEP:
				deep[id] = true
		if Vector2(w.entities[hc].pos).x > 66.0 and Vector2(w.entities[ht].pos).x > 66.0:
			break
	for id in [hc, ht]:
		var dn := String(w.entities[id].def)
		check(deep[id], "%s crossed deep water" % dn)
		check(Vector2(w.entities[id].pos).x > 64.0, "%s reached the east land (%s)" % [dn, str(w.entities[id].pos)])
		check(not Terrain.is_water(w.terrain_at(w.cell_of(w.entities[id].pos))), "%s is on land again" % dn)


func test_hovercraft_cargo_1_vehicle_8_foot() -> void:
	var w := _sea_world()
	var hc := w.spawn_unit("a_hovercraft", 0, Vector2(20, 30) + C)
	var foot := []
	for i in 9:
		foot.append(w.spawn_unit("rifleman", 0, Vector2(14 + i % 5, 26 + i / 5) + C))
	var tank := w.spawn_unit("mbt", 0, Vector2(16, 34) + C)
	var tank2 := w.spawn_unit("mbt", 0, Vector2(18, 36) + C)
	var ids: Array = foot.slice(0, 8)
	ids.append(tank)
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "load", "carrier": hc, "unit_ids": ids})), "", "load 8 foot + 1 vehicle accepted")
	for i in 600:
		w.step()
		if (w.entities[hc].get("cargo", []) as Array).size() == 9:
			break
	check_eq((w.entities[hc].get("cargo", []) as Array).size(), 9, "8 riflemen + 1 tank aboard")
	check_eq(Transport.group_load(w.entities[hc]), {"foot": 8, "vehicle": 1}, "group load foot 8 / vehicle 1")
	check(not Transport.fits(w.entities[hc], w.entities[foot[8]]), "a 9th soldier does not fit")
	check(not Transport.fits(w.entities[hc], w.entities[tank2]), "a 2nd vehicle does not fit")
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "load", "carrier": hc, "unit_ids": [foot[8], tank2]})), "The transport is full.", "overload refused")
	# across the sea, unload on plain land (not a beach): hover is not beach-bound
	var land := Vector2(72, 30) + C
	check_eq(Naval.unload_error(w, w.entities[hc], land), "", "hover may unload on any land")
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "unload", "carrier": hc, "target": land})), "", "unload order accepted")
	for i in 1200:
		w.step()
		if (w.entities[hc].get("cargo", []) as Array).is_empty():
			break
	check((w.entities[hc].get("cargo", []) as Array).is_empty(), "cargo unloaded on the east land")
	check(w.entities.has(tank) and Vector2(w.entities[tank].pos).x > 63.0, "the tank is ashore in the east")
	var ashore := 0
	for id in ids:
		if w.entities.has(int(id)) and not Terrain.is_water(w.terrain_at(w.cell_of(w.entities[int(id)].pos))):
			ashore += 1
	check_eq(ashore, 9, "all 9 passengers stand on land")


# ---------------------------------------------------------------- sea mines (Mines API, MECH6a)
func test_sea_mines_laid_and_swept() -> void:
	var w := _sea_world()
	var barge := w.spawn_unit("b_mine_barge", 1, Vector2(45, 62) + C)
	var gb := w.spawn_unit("b_river_gunboat", 1, Vector2(40, 62) + C)
	check_eq(_cmd(w, 1, {"type": "lay_sea_mines", "unit_ids": [barge], "rect": [10, 10, 12, 12]}, Naval), "Sea mines go on water.", "no sea mines on land")
	check_eq(_cmd(w, 1, {"type": "lay_sea_mines", "unit_ids": [gb], "rect": [44, 50, 47, 53]}, Naval), "Only mine barges lay sea mines.", "a gunboat cannot lay")
	check_eq(_cmd(w, 1, {"type": "lay_sea_mines", "unit_ids": [barge], "rect": [40, 40, 52, 52]}, Naval), "Rectangle too large (max 8x8).", "rect capped")
	w.destroy(gb, "test")   # no enemy guns near the sweeper's lane later
	check_eq(_cmd(w, 1, {"type": "lay_sea_mines", "unit_ids": [barge], "rect": [44, 50, 47, 53]}, Naval), "", "lay_sea_mines accepted")
	var laid := []
	var done := false
	for i in 900:
		w.step()
		for ev in w.events:
			if ev.type == "MineLaid" and String(ev.get("layer", "")) == "sea":
				laid.append(Vector2i(ev.cell))
			if ev.type == "SeaMinesDone" and int(ev.id) == barge:
				done = true
		if done:
			break
	check(done, "the barge finished its sea minefield")
	check_eq(laid, [Vector2i(44, 50), Vector2i(46, 50), Vector2i(44, 52), Vector2i(46, 52)], "4 sea mines on the spaced pattern")
	check_eq(Naval.sea_charges(w.entities[barge]), 4, "8 charges - 4 laid")
	var mines := []
	for m in w.entities.values():
		if m.kind == "mine" and String(m.get("layer", "")) == "sea":
			mines.append(int(m.id))
	check_eq(mines.size(), 4, "4 sea mine entities")
	# a minesweeper sails the lane x = 45 through them and clears them
	_teleport(w, barge, Vector2(45, 90) + C)   # the barge (armed) leaves the area
	var sw := w.spawn_unit("a_minesweeper", 0, Vector2(45, 40) + C)
	do_cmd(w, 0, {"type": "move", "unit_ids": [sw], "target": Vector2(45, 60) + C})
	var cleared := 0
	var detected := 0
	for i in 600:
		w.step()
		for ev in w.events:
			if ev.type == "MineCleared" and int(ev.get("by", -1)) == sw:
				cleared += 1
			if ev.type == "MineDetected" and int(ev.get("by", -1)) == sw:
				detected += 1
			if ev.type == "MineTriggered":
				check(false, "a sea mine went off near the sweeper (%s)" % str(ev))
		if cleared >= 4 and not bool(w.entities[sw].moving):
			break
	check_eq(detected, 4, "the sweeper's sonar detected all 4 mines")
	check_eq(cleared, 4, "the sweeper cleared the 2-wide lane")
	var left := 0
	for m in w.entities.values():
		if m.kind == "mine" and String(m.get("layer", "")) == "sea":
			left += 1
	check_eq(left, 0, "no sea mines left")
	check_eq(float(w.entities[sw].hp), float(w.entities[sw].max_hp), "the sweeper took no mine damage")
	# restock at a pier
	w.spawn_building("a_supply_pier", 1, Vector2i(29, 8), true)
	_teleport(w, barge, Vector2(33, 9) + C)
	_run(w, 100)
	check(Naval.sea_charges(w.entities[barge]) > 4, "the pier restocks sea mines (%d)" % Naval.sea_charges(w.entities[barge]))


# ---------------------------------------------------------------- determinism (state saved and hashed)
func test_save_load_mid_naval_g6() -> void:
	var w := _sea_world(9)
	var sub := w.spawn_unit("a_submarine", 0, Vector2(45, 20) + C)
	w.spawn_unit("b_monitor", 1, Vector2(45, 27) + C)
	w.spawn_unit("a_carrier", 0, Vector2(44, 40) + C)
	var barge := w.spawn_unit("b_mine_barge", 1, Vector2(45, 62) + C)
	_dive(w, 0, [sub])
	_cmd(w, 1, {"type": "lay_sea_mines", "unit_ids": [barge], "rect": [44, 50, 47, 53]}, Naval)
	do_cmd(w, 0, {"type": "move", "unit_ids": [sub], "target": Vector2(45, 35) + C})
	_run(w, 50)
	check(Sonar.submerged(w.entities[sub]), "sub submerged at save time")
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(w2.state_hash(), w.state_hash(), "same hash right after load")
	check(Sonar.submerged(w2.entities[sub]), "submerged state survives the load")
	for i in 200:
		w.step()
		w2.step()
	check_eq(w2.state_hash(), w.state_hash(), "same hash 200 ticks after load (sonar, carrier, sea mines)")
	check(SimWorld.Airfield.fields(w2).size() == SimWorld.Airfield.fields(w).size(), "carrier field in both")
