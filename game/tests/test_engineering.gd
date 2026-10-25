extends "res://tests/test_base.gd"
## G6 MECH6a-2 (CONTRACTS_G6 section 9 "Engineering"): salvage crane / dozer tow wrecks to a scrapyard
## for salvage income; the repair bay repairs parked vehicles at x3; satchel sappers and the breacher
## crawler carry breach charges (G4 charge pattern) that do x2 vs walls and gates.

const Engineering = preload("res://sim/systems/engineering.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const TMP_DIR := "user://test_tmp_engineering"


## Flat open 30x30 grass arena in the map centre (one height level), cleared of neutrals.
func _setup() -> Array:
	var w := make_world()
	w.ai_state = {}
	var mw := int(w.map.w)
	var o := Vector2i(mw / 2 - 15, int(w.map.h) / 2 - 15)
	var r := Rect2i(o, Vector2i(30, 30))
	var t: PackedByteArray = w.map.terrain
	var hgt = w.map.get("height")
	var rmp = w.map.get("ramps")
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
			if hgt != null:
				hgt[y * mw + x] = 1
			if rmp != null:
				rmp[y * mw + x] = 0
	w.map.terrain = t
	if hgt != null:
		w.map.height = hgt
	if rmp != null:
		w.map.ramps = rmp
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" and e.kind != "building" and r.grow(2).has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	Movement.rebuild_nav(w)
	w.factions[0].credits = 5000
	w.factions[0].stock.salvage = 5000
	return [w, o]


func _c(o: Vector2i, x: float, y: float) -> Vector2:
	return Vector2(o) + Vector2(x, y)


func _run(w: SimWorld, n: int, stop_type: String) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			out.append(ev)
			if String(ev.type) == stop_type:
				return out
	return out


func _types(evs: Array) -> Array:
	var out := []
	for ev in evs:
		out.append(String(ev.type))
	return out


## Kill an enemy unit that leaves a wreck; returns the wreck id (-1 if none).
func _make_wreck(w: SimWorld, def_id: String, p: Vector2) -> int:
	var id := w.spawn_unit(def_id, 1, p)
	w.destroy(id, "test", 0)
	for e in w.entities.values():
		if e.kind == "wreck" and String(e.def) == def_id and Vector2(e.pos).distance_to(p) < 0.01:
			return int(e.id)
	return -1


func test_tow_wreck_to_scrapyard_gives_salvage() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var crane := w.spawn_unit("b_salvage_crane", 0, _c(o, 6.5, 6.5))
	var dozer := w.spawn_unit("b_armored_dozer", 0, _c(o, 6.5, 8.5))
	var rif := w.spawn_unit("rifleman", 0, _c(o, 7.5, 6.5))
	var wid := _make_wreck(w, "b_salvage_crane", _c(o, 18.5, 18.5))
	check(wid >= 0, "a destroyed crane leaves a wreck")
	if wid < 0:
		return
	check(Engineering.validate_command(w, {"type": "tow_wreck", "issuer": 0, "unit_id": crane, "wreck_id": wid}) != "", "no scrapyard or salvage yard: nothing to tow to")
	var yard := w.spawn_building("b_scrapyard", 0, o + Vector2i(3, 14), true)
	check(Engineering.validate_command(w, {"type": "tow_wreck", "issuer": 0, "unit_id": rif, "wreck_id": wid}) != "", "a rifleman cannot tow")
	check(Engineering.validate_command(w, {"type": "tow_wreck", "issuer": 0, "unit_id": crane, "wreck_id": yard}) != "", "only wrecks are towed")
	check_eq(Engineering.validate_command(w, {"type": "tow_wreck", "issuer": 0, "unit_id": dozer, "wreck_id": wid}), "", "the armored dozer can tow too")
	var j0: int = (w.factions[0].journal as Array).size()
	var wp0 := Vector2(w.entities[wid].pos)
	do_cmd(w, 0, {"type": "tow_wreck", "unit_id": crane, "wreck_id": wid})
	check_eq(Engineering.validate_command(w, {"type": "tow_wreck", "issuer": 0, "unit_id": dozer, "wreck_id": wid}), "", "not yet hooked: still free")
	var evs := _run(w, 400, "WreckHooked")
	check(_types(evs).has("WreckHooked"), "the crane hooks the wreck")
	check(Engineering.validate_command(w, {"type": "tow_wreck", "issuer": 0, "unit_id": dozer, "wreck_id": wid}) != "", "a hooked wreck is in tow")
	var expect := int(floor(float(Engineering.wreck_value(w, w.entities[wid])) * 1.5))
	evs = _run(w, 2000, "WreckSalvaged")
	check(_types(evs).has("WreckSalvaged"), "the crane delivers the wreck to the scrapyard")
	check(not w.entities.has(wid), "the delivered wreck is gone")
	var got := 0
	var jr: Array = w.factions[0].journal
	for i in range(j0, jr.size()):
		if String(jr[i].cause) == "tow:wreck":
			got += int(jr[i].get("salvage", 0))
	check(got > 0, "towing pays salvage (%d)" % got)
	check_eq(got, expect, "salvage = wreck value x scrapyard salvage_mult 1.5")
	var cp: Vector2 = w.entities[crane].pos
	check(cp.distance_to(wp0) > 6.0, "the crane hauled the wreck away from where it fell (%s)" % str(cp - Vector2(o)))
	check(Engineering._dist_rect(cp, w.entities[yard]) <= 1.6, "the crane ends at the yard")
	check_eq(int(w.sys_state.engineering.towed), 1, "delivery counted in saved state")


func test_repair_bay_repairs_parked_vehicles_x3() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	w.spawn_building("generator", 0, o + Vector2i(22, 3), true)
	var bay := w.spawn_building("a_repair_bay", 0, o + Vector2i(10, 10), true)
	var parked := w.spawn_unit("mbt", 0, _c(o, 14.0, 11.5))
	var far := w.spawn_unit("mbt", 0, _c(o, 24.5, 24.5))
	var foot := w.spawn_unit("rifleman", 0, _c(o, 9.3, 11.5))
	var enemy := w.spawn_unit("logistics_truck", 1, _c(o, 11.5, 14.0))  # weaponless: the parked tank takes no fire
	for id in [parked, far, foot, enemy]:
		HotState.set_hp(w, id, float(w.entities[id].max_hp) * 0.5)
	w.step()
	var f: Dictionary = w.factions[0]
	check(int(f.power_use) <= int(f.power_prod), "precondition: the bay is powered (%d/%d)" % [int(f.power_use), int(f.power_prod)])
	var hp0 := {}
	for id in [parked, far, foot, enemy]:
		hp0[id] = float(w.entities[id].hp)
	for i in 40:
		w.step()
	var gain := float(w.entities[parked].hp) - float(hp0[parked])
	var base := float(Content.rules().repair.hp_per_second) * 40.0 * SimWorld.DT
	check(gain >= base * 3.0 * 0.75 and gain <= base * 3.0 * 1.25, "parked vehicle repaired at x3 the base repair rate (%.1f vs %.1f)" % [gain, base * 3.0])
	check(is_equal_approx(float(w.entities[far].hp), float(hp0[far])), "a vehicle far from the bay is not repaired")
	check(is_equal_approx(float(w.entities[foot].hp), float(hp0[foot])), "infantry is not repaired by a vehicle bay")
	check(not w.entities.has(enemy) or float(w.entities[enemy].hp) <= float(hp0[enemy]), "enemy vehicles are not repaired")
	check(w.entities.has(bay), "bay alive")
	HotState.set_hp(w, parked, float(w.entities[parked].max_hp) - 5.0)
	for i in 20:
		w.step()
	check(is_equal_approx(float(w.entities[parked].hp), float(w.entities[parked].max_hp)), "repair stops at max hp")


func test_breach_charges_x2_vs_walls() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var wall_a := w.spawn_building("a_wall", 1, o + Vector2i(12, 8), true)
	var wall_b := w.spawn_building("a_wall", 1, o + Vector2i(12, 20), true)
	for id in [wall_a, wall_b]:
		w.entities[id].hp = 100000.0
		w.entities[id].max_hp = 100000.0
	var sap := w.spawn_unit("b_satchel_sappers", 0, _c(o, 8.5, 8.5))
	var rif := w.spawn_unit("rifleman", 0, _c(o, 8.5, 9.5))
	var own_wall := w.spawn_building("a_wall", 0, o + Vector2i(3, 3), true)
	check(Engineering.validate_command(w, {"type": "breach", "issuer": 0, "unit_ids": [rif], "target_id": wall_a}) != "", "riflemen carry no breach charge")
	check(Engineering.validate_command(w, {"type": "breach", "issuer": 0, "unit_ids": [sap], "target_id": own_wall}) != "", "no breach on an own wall")
	w.destroy(rif, "test")  # it would shoot the enemy walls
	do_cmd(w, 0, {"type": "breach", "unit_ids": [sap], "target_id": wall_a})
	var evs := _run(w, 300, "ChargePlanted")
	check(_types(evs).has("ChargePlanted"), "the sappers plant a charge on the wall")
	var ch = null
	for e in w.entities.values():
		if e.kind == "charge" and int(e.target) == wall_a:
			ch = e
	check(ch != null and String(ch.get("weapon", "")) == "g6_satchel", "the charge carries the satchel payload")
	check(ch != null and is_equal_approx(float(ch.get("mult", 1.0)), 2.0), "x2 vs walls")
	HotState.set_pos(w, sap, _c(o, 2.5, 27.5))  # out of rifle range: only the charges hurt the walls
	var hpa0 := float(w.entities[wall_a].hp)  # after any rifle fire during the approach
	# the same payload at x1 on an identical wall, planted by a G4-style charge for comparison
	var ref_charge := G4bMech._spawn_charge(w, w.entities[sap], w.entities[wall_b], "g6_satchel", 1.0, G4bMech.FUSE_TICKS)
	check(ref_charge > 0, "reference charge spawned")
	evs = _run(w, G4bMech.FUSE_TICKS + 20, "")
	var da := hpa0 - float(w.entities[wall_a].hp)
	var db := 100000.0 - float(w.entities[wall_b].hp)
	check(db > 0.0, "the x1 charge damages its wall (%.1f)" % db)
	check(is_equal_approx(da, db * 2.0), "the breach charge does x2 vs the wall (%.1f vs %.1f)" % [da, db])
	check_eq(int(w.sys_state.engineering.breached), 1, "breach counted in saved state")
	# breacher crawler: walks up, self-destructs, x2 vs a gate
	var gate := w.spawn_building("a_gate", 1, o + Vector2i(20, 14), true)
	w.entities[gate].hp = 100000.0
	w.entities[gate].max_hp = 100000.0
	var crawler := w.spawn_unit("m_breacher_crawler", 0, _c(o, 16.5, 14.5))
	do_cmd(w, 0, {"type": "breach", "unit_ids": [crawler], "target_id": gate})
	evs = _run(w, 300, "ChargeDetonated")
	check(_types(evs).has("ChargeDetonated"), "the crawler's charge detonates")
	check(not w.entities.has(crawler), "the crawler is spent (self-destruct)")
	var dg := 100000.0 - float(w.entities[gate].hp)
	check(dg > 0.0, "the gate takes the crawler's breach damage (%.1f)" % dg)


func test_engineering_save_load_mid_tow_and_breach() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var crane := w.spawn_unit("b_salvage_crane", 0, _c(o, 6.5, 6.5))
	var wid := _make_wreck(w, "b_salvage_crane", _c(o, 16.5, 16.5))
	w.spawn_building("b_scrapyard", 0, o + Vector2i(3, 22), true)
	var wall := w.spawn_building("a_wall", 1, o + Vector2i(24, 8), true)
	var sap := w.spawn_unit("b_satchel_sappers", 0, _c(o, 21.5, 8.5))
	do_cmd(w, 0, {"type": "tow_wreck", "unit_id": crane, "wreck_id": wid})
	do_cmd(w, 0, {"type": "breach", "unit_ids": [sap], "target_id": wall})
	var evs := _run(w, 400, "WreckHooked")
	check(_types(evs).has("WreckHooked"), "hooked before the save")
	w.run_ticks(10)
	check_eq(String(w.entities[crane].order.get("type", "")), "tow", "mid-haul at the save")
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var path := TMP_DIR + "/mid_tow.sav"
	check_eq(SaveSystem.save(w, path), "", "save ok")
	var l: SimWorld = SaveSystem.load(path)
	check(l != null, "load ok")
	if l == null:
		return
	check_eq(l.state_hash(), w.state_hash(), "hash equal after load")
	check_eq((l.sys_state.engineering.active as Array).size(), (w.sys_state.engineering.active as Array).size(), "engineering state saved")
	w.run_ticks(600)
	l.run_ticks(600)
	check_eq(l.state_hash(), w.state_hash(), "hash equal after 600 more ticks (tow delivery, breach charge)")
	check_eq(int(l.sys_state.engineering.towed), int(w.sys_state.engineering.towed), "same deliveries")
