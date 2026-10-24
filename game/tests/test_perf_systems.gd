extends "res://tests/test_base.gd"
## PERF5 (G3b scale): the per-system full scans of w.entities were replaced by the shared index
## (sim_index.gd), per-def unit subsets (unit_subsets.gd) and the patrol/guard set (orders.gd).
## These tests check the subsets against a reference full scan, through spawns, deaths and a
## save round trip, and that a live AI-vs-AI match stays deterministic and restore-stable.

const Subsets = preload("res://sim/systems/unit_subsets.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Orders = preload("res://sim/systems/orders.gd")
const Movement = preload("res://sim/systems/movement.gd")

const FLAG_OF := {0: "builder", 1: "gatherer", 2: "repairer", 3: "ew", 4: "supply"}


## Reference: the old full scan, filtered by the same def flags, ascending id.
func _ref(w: SimWorld, which: int) -> Array:
	var out := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		var d := Content.unit(e.def)
		var cb := bool(d.get("can_build", false))
		var yes := false
		match which:
			Subsets.BUILDER: yes = cb
			Subsets.GATHERER: yes = bool(d.get("can_gather", false))
			Subsets.REPAIRER: yes = cb or bool(d.get("can_repair", false))
			Subsets.EW: yes = float(d.get("ew_radius", 0)) > 0.0
			Subsets.SUPPLY: yes = bool(d.get("is_supply", false))
		if yes:
			out.append(int(id))
	return out


func _ids(arr: Array) -> Array:
	var out := []
	for e in arr:
		out.append(int(e.id))
	return out


func _check_all(w: SimWorld, when: String) -> void:
	for k in Subsets.COUNT:
		check_eq(_ids(Subsets.units(w, k)), _ref(w, k), "%s subset matches a full scan (%s)" % [FLAG_OF[k], when])


func _place(w: SimWorld, def: String, fid: int, at: Vector2) -> int:
	var mc := String(Content.unit(def).get("move_class", "foot"))
	var c := Movement.nearest_free_cell(w, Vector2i(floori(at.x), floori(at.y)), "vehicle" if mc == "vehicle" else "foot")
	return w.spawn_unit(def, fid, Vector2(c) + Vector2(0.5, 0.5))


func test_subsets_track_spawns_deaths_and_restore() -> void:
	var w := make_world({"seed": 11})
	_check_all(w, "start")
	var spawned := []
	for def in ["engineer", "logistics_truck", "a_ew_truck", "rifleman", "engineer"]:
		spawned.append(_place(w, def, 0, Vector2(20, 20)))
	_check_all(w, "after spawns, before a tick")
	w.run_ticks(3)
	_check_all(w, "after 3 ticks")
	w.destroy(int(spawned[0]), "test")
	w.destroy(int(spawned[2]), "test")
	_check_all(w, "after deaths")
	spawned.append(_place(w, "a_ew_truck", 1, Vector2(70, 70)))
	w.run_ticks(9)   # crosses a SimIndex rebuild (every 4 ticks)
	_check_all(w, "after an index rebuild")
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	_check_all(w2, "restored world (cache rebuilt from state)")
	w2.run_ticks(5)
	_check_all(w2, "restored world after 5 ticks")
	# (every entity comes from SimWorld._new_id(), so no test inserts entities by hand)


func test_patrol_guard_set_follows_orders() -> void:
	var w := make_world({"seed": 12})
	var a := _place(w, "rifleman", 0, Vector2(24, 24))
	var b := _place(w, "rifleman", 0, Vector2(26, 24))
	var c := _place(w, "rifleman", 0, Vector2(28, 24))
	do_cmd(w, 0, {"type": "patrol", "unit_ids": [c, a], "points": [Vector2(30, 30), Vector2(40, 30)]})
	do_cmd(w, 0, {"type": "guard", "unit_ids": [b], "target_id": a})
	w.run_ticks(6)
	check_eq(w.cache.orders_pg.ids, [a, b, c], "patrol/guard set holds the three units in id order")
	var pos_before: Vector2 = w.entities[c].pos
	w.run_ticks(40)
	check(Vector2(w.entities[c].pos).distance_to(pos_before) > 0.5, "the patrolling unit still walks its route")
	do_cmd(w, 0, {"type": "move", "unit_ids": [c], "target": Vector2(20, 20)})   # direct order ends patrol
	w.run_ticks(6)
	check(not w.entities[c].has("patrol"), "a direct move order ends the patrol")
	check_eq(w.cache.orders_pg.ids, [a, b], "the set drops a unit that lost its patrol")
	w.destroy(a, "test")
	w.run_ticks(6)
	check(not (w.cache.orders_pg.ids as Array).has(a), "the set drops a dead unit")
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	w2.run_ticks(1)
	var want := []
	for id in w2.entities:
		var e: Dictionary = w2.entities[id]
		if e.kind == "unit" and (e.has("patrol") or e.has("guard")):
			want.append(int(id))
	check_eq(w2.cache.orders_pg.ids, want, "restored world rebuilds the set from saved patrol/guard keys")


func test_live_ai_determinism_and_restore() -> void:
	var w1 := make_world({"seed": 21}, true)
	var w2 := make_world({"seed": 21}, true)
	w1.run_ticks(700)
	w2.run_ticks(700)
	check_eq(w1.state_hash(), w2.state_hash(), "same seed, live AI: same hash after 700 ticks")
	_check_all(w1, "live AI match at tick 700")
	var w3 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w1.to_dict())))
	check_eq(w3.state_hash(), w1.state_hash(), "hash equal right after restore")
	w1.run_ticks(301)
	w3.run_ticks(301)
	check_eq(w3.state_hash(), w1.state_hash(), "hash equal 301 ticks after a restore (caches rebuilt)")
