extends "res://tests/test_base.gd"
## G5 acceptance (owner: AIRSYS). CONTRACTS_G5 sections 4, 7: air transport (troops, sling vehicles, VTOL
## 2 vehicles + 8 troops, heavy-lift), landing-zone validation for unload, save/load with air cargo.

const Air = preload("res://sim/systems/air.gd")
const Transport = preload("res://sim/systems/transport.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const Helper = preload("res://tests/test_air.gd")
const TMP_DIR := "user://test_air_transport"
const JEEP := "a_recon_car"   # shipped light vehicle (cargo_class vehicle_light); was a leaked test-only fixture

var ha = Helper.new()


func _w() -> SimWorld:
	return ha._w()


func _run(w: SimWorld, n: int, f: Callable) -> int:
	return ha._run(w, n, f)


## Carrier def landed on an open cell far from the base, plus the cell.
func _landed(w: SimWorld, def: String, off: Vector2i = Vector2i(26, 10)) -> Dictionary:
	var cell: Vector2i = ha._open_cell(w, off)
	var id := w.spawn_unit(def, 0, Vector2(cell) + Vector2(0.5, 0.5))
	w.step()
	w.submit({"type": "land_at", "issuer": 0, "unit_ids": [id], "cell": cell})
	_run(w, 200, func() -> bool: return Air.is_landed(w.entities[id]))
	return {"id": id, "cell": cell}


func _spawn_near(w: SimWorld, def: String, cell: Vector2i, n: int) -> Array:
	var ids := []
	for i in n:
		var c := Movement.nearest_free_cell(w, cell + Vector2i(2 + i % 4, 1 + i / 4), String(Content.unit(def).get("move_class", "foot")))
		ids.append(w.spawn_unit(def, 0, Vector2(c) + Vector2(0.5, 0.5)))
	w.step()
	return ids


func _load(w: SimWorld, cid: int, ids: Array, want: int) -> int:
	w.submit({"type": "load", "issuer": 0, "carrier": cid, "unit_ids": ids})
	return _run(w, 600, func() -> bool: return (w.entities[cid].get("cargo", []) as Array).size() >= want)


func _cargo(w: SimWorld, cid: int) -> Array:
	return Transport.cargo_ids(w.entities[cid])


func test_gunship_carries_8_troops() -> void:
	var w := _w()
	var s := _landed(w, "a_transport_gunship")
	var g: int = s.id
	check(Air.is_landed(w.entities[g]), "gunship landed")
	var troops := _spawn_near(w, "rifleman", s.cell, 9)
	check(_load(w, g, troops.slice(0, 8), 8) > 0, "8 troops board")
	check_eq(_cargo(w, g).size(), 8, "8 aboard")
	var r := w.preview_command({"type": "load", "issuer": 0, "carrier": g, "unit_ids": [troops[8]]})
	check(r.contains("full"), "the 9th is refused (%s)" % r)
	# airborne gunship: boarders wait until it lands
	var w2 := _w()
	var cell: Vector2i = ha._open_cell(w2, Vector2i(26, 10))
	var g2 := w2.spawn_unit("a_transport_gunship", 0, Vector2(cell) + Vector2(0.5, 0.5))
	var t2 := _spawn_near(w2, "rifleman", cell, 2)
	w2.submit({"type": "load", "issuer": 0, "carrier": g2, "unit_ids": t2})
	w2.run_ticks(200)
	check_eq(_cargo(w2, g2).size(), 0, "no boarding while airborne")
	w2.submit({"type": "land_at", "issuer": 0, "unit_ids": [g2], "cell": cell})
	check(_run(w2, 300, func() -> bool: return _cargo(w2, g2).size() == 2) > 0, "they board once it lands")


func test_gunship_slings_one_light_vehicle() -> void:
	var w := _w()
	var s := _landed(w, "a_transport_gunship")
	var g: int = s.id
	var jeeps := _spawn_near(w, JEEP, s.cell, 2)
	check(_load(w, g, [jeeps[0]], 1) > 0, "a light vehicle is slung")
	check_eq(Transport.slung(w.entities[g]), [jeeps[0]], "slung() lists it")
	check(w.preview_command({"type": "load", "issuer": 0, "carrier": g, "unit_ids": [jeeps[1]]}).contains("full"), "only one vehicle")
	var inf := _spawn_near(w, "rifleman", s.cell, 1)
	check(w.preview_command({"type": "load", "issuer": 0, "carrier": g, "unit_ids": inf}).contains("full"), "troops OR a vehicle, not both")
	var tank := _spawn_near(w, "mbt", s.cell, 1)
	check(w.preview_command({"type": "load", "issuer": 0, "carrier": g, "unit_ids": tank}).contains("cannot carry"), "no heavy vehicles")


## G7 (owner-ordered spec change, docs/G7_REFERENCE.md B18): the VTOL dropship carries ONE vehicle + its occupants + one
## squad INSIDE its cargo bay (nothing slung), replacing the G5 rule of 2 slung vehicles + 8 troops. Same checks, new rule.
func test_vtol_bay_carries_one_vehicle_and_a_squad() -> void:
	var w := _w()
	w.factions[0].stage = 9
	var s := _landed(w, "a_vtol_dropship")
	var v: int = s.id
	var veh := _spawn_near(w, "mbt", s.cell, 1) + _spawn_near(w, JEEP, s.cell, 1)
	var troops := _spawn_near(w, "rifleman", s.cell, 11)
	check(_load(w, v, [veh[0]] + troops.slice(0, 10), 11) > 0, "1 vehicle + 10 troops board")
	var load := Transport.group_load(w.entities[v])
	check_eq(load, {"foot": 10, "vehicle": 1}, "mixed cargo counts")
	check(Transport.slung(w.entities[v]).is_empty(), "nothing slung: the vehicle rides inside the bay")
	check(w.preview_command({"type": "load", "issuer": 0, "carrier": v, "unit_ids": [veh[1]]}).contains("full"), "2nd vehicle refused")
	check(w.preview_command({"type": "load", "issuer": 0, "carrier": v, "unit_ids": [troops[10]]}).contains("full"), "11th trooper refused")


func test_landing_zone_validation_for_unload() -> void:
	var w := _w()
	var s := _landed(w, "a_transport_gunship")
	var g: int = s.id
	var troops := _spawn_near(w, "rifleman", s.cell, 4)
	_load(w, g, troops, 4)
	var water: Vector2i = s.cell + Vector2i(8, 0)
	ha._set_terrain(w, water, Terrain.WATER)
	var r := w.preview_command({"type": "unload", "issuer": 0, "carrier": g, "target": Vector2(water) + Vector2(0.5, 0.5)})
	check(r.contains("Not enough open ground"), "unload over water refused (%s)" % r)
	var dest: Vector2i = ha._open_cell(w, Vector2i(26, 22))
	check(w.submit({"type": "unload", "issuer": 0, "carrier": g, "target": Vector2(dest) + Vector2(0.5, 0.5)}).ok, "unload at an open spot")
	var t := _run(w, 800, func() -> bool: return _cargo(w, g).is_empty())
	check(t > 0, "unloaded")
	check(Air.is_landed(w.entities[g]), "landed to unload")
	check(Vector2(w.entities[g].pos).distance_to(Vector2(dest) + Vector2(0.5, 0.5)) < 1.0, "at the ordered landing zone")
	for id in troops:
		check(w.entities.has(id), "trooper %d back on the map" % id)


func test_heavy_lift_carries_heavy_vehicle() -> void:
	var w := _w()
	var s := _landed(w, "b_heavy_lift")
	var hl: int = s.id
	var tank := _spawn_near(w, "mbt", s.cell, 1)
	check(_load(w, hl, tank, 1) > 0, "the heavy-lift slings a tank")
	check_eq(Transport.slung(w.entities[hl]), tank, "slung")
	var inf := _spawn_near(w, "rifleman", s.cell, 1)
	check(w.preview_command({"type": "load", "issuer": 0, "carrier": hl, "unit_ids": inf}).contains("full"), "no troops with a slung vehicle")
	var w2 := _w()
	var s2 := _landed(w2, "b_heavy_lift")
	var t2 := _spawn_near(w2, "rifleman", s2.cell, 12)
	check(_load(w2, int(s2.id), t2, 12) > 0, "or 12 troops")


func test_save_load_with_air_cargo() -> void:
	var w := _w()
	w.factions[0].stage = 9
	var s := _landed(w, "a_vtol_dropship")
	var v: int = s.id
	var cargo := _spawn_near(w, "mbt", s.cell, 1) + _spawn_near(w, "rifleman", s.cell, 3)
	_load(w, v, cargo, 4)
	var dest: Vector2i = ha._open_cell(w, Vector2i(10, 30))
	w.submit({"type": "unload", "issuer": 0, "carrier": v, "target": Vector2(dest) + Vector2(0.5, 0.5)})
	w.run_ticks(20)
	check(not Air.is_landed(w.entities[v]), "in flight with cargo")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var path := TMP_DIR + "/cargo.sav"
	check_eq(SaveSystem.save(w, path), "", "save ok")
	var l: SimWorld = SaveSystem.load(path)
	check(l != null, "load ok")
	if l == null:
		return
	check_eq(l.state_hash(), w.state_hash(), "hash equal after load")
	check_eq(Transport.cargo_ids(l.entities[v]), Transport.cargo_ids(w.entities[v]), "cargo preserved")
	for i in 600:
		w.step()
		l.step()
	check_eq(l.state_hash(), w.state_hash(), "same future after load")
	check(_cargo(l, v).is_empty(), "the loaded game unloads at the landing zone too")


## PT5-2 regression: a landed VTOL clicked "Unload at point" on (or right beside) its own landing spot was
## refused with "Not enough open ground to land." because its own landed body blocked the LZ check.
func test_vtol_unload_at_its_own_landed_spot() -> void:
	var w := _w()
	w.factions[0].stage = 9
	var s := _landed(w, "a_vtol_dropship")
	var v: int = s.id
	var veh := _spawn_near(w, "mbt", s.cell, 1)  # G7 B18: one vehicle + a squad inside the bay
	var troops := _spawn_near(w, "rifleman", s.cell, 10)
	check(_load(w, v, veh + troops, 11) > 0, "1 vehicle + 10 troops board")
	var here: Vector2 = w.entities[v].pos
	var r := w.preview_command({"type": "unload", "issuer": 0, "carrier": v, "target": here})
	check_eq(r, "", "unload at its own landed spot is allowed")
	check(w.submit({"type": "unload", "issuer": 0, "carrier": v, "target": here}).ok, "unload submitted")
	check(_run(w, 600, func() -> bool: return _cargo(w, v).is_empty()) > 0, "all 11 unloaded at the landed spot")
	check(Air.is_landed(w.entities[v]), "still landed")
	for id in veh + troops:
		check(w.entities.has(id) and Vector2(w.entities[id].pos).distance_to(here) < 7.0, "unit %d unloaded beside the VTOL" % id)
	# another landed aircraft still blocks the LZ
	var o := _landed(w, "a_vtol_dropship", Vector2i(26, 22))
	var g := _landed(w, "a_transport_gunship", Vector2i(10, 22))
	var t2 := _spawn_near(w, "rifleman", g.cell, 2)
	_load(w, int(g.id), t2, 2)
	var r2 := w.preview_command({"type": "unload", "issuer": 0, "carrier": int(g.id), "target": w.entities[int(o.id)].pos})
	check(r2.contains("Not enough open ground"), "unload onto another landed aircraft refused (%s)" % r2)
