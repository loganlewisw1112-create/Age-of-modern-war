extends "res://tests/test_base.gd"
## G6 MECH6a (CONTRACTS_G6 section 9): build_rail lays RAIL tiles from a Rail Yard; the armored
## train moves only on rail; a destroyed (cut) tile stops it until engineers repair the line.

const Rail = preload("res://sim/systems/rail.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")


func _setup() -> Array:
	var w := make_world()
	w.ai_state = {}
	var mw := int(w.map.w)
	var o := Vector2i(mw / 2 - 15, int(w.map.h) / 2 - 15)
	var r := Rect2i(o, Vector2i(30, 30))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" and e.kind != "building" and r.grow(2).has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	Movement.rebuild_nav(w)
	w.factions[0].credits = 5000
	w.factions[0].stock.salvage = 5000
	return [w, o]


func _c(o: Vector2i, x: int, y: int) -> Vector2:
	return Vector2(o) + Vector2(x, y) + Vector2(0.5, 0.5)


## Test fixture: a straight rail on row y from x0..x1 (terrain RAIL + nav rebuild).
func _lay(w: SimWorld, o: Vector2i, x0: int, x1: int, y: int) -> void:
	var mw := int(w.map.w)
	var t: PackedByteArray = w.map.terrain
	for x in range(x0, x1 + 1):
		t[(o.y + y) * mw + o.x + x] = Rail.RAIL
	w.map.terrain = t
	Movement.on_terrain_changed(w)


func _run_until(w: SimWorld, ev_type: String, max_ticks: int) -> Array:
	var seen := []
	for i in max_ticks:
		w.step()
		for ev in w.events:
			seen.append(String(ev.type))
			if ev.type == ev_type:
				return seen
	return seen


## Order the train to goal and step n ticks; returns [always_on_rail, max_x_cell, final_pos].
func _drive(w: SimWorld, tid: int, goal: Vector2, n: int) -> Array:
	var e: Dictionary = w.entities[tid]
	HotState.set_order(w, tid, {"type": "move", "target": goal})
	Movement.order_path(w, e, goal)
	HotState.touch(w, tid)
	var ok := true
	var mx := -1
	for i in n:
		w.step()
		var c := w.cell_of(w.entities[tid].pos)
		ok = ok and Rail.on_rail(w, c)
		mx = maxi(mx, c.x)
	return [ok, mx, Vector2(w.entities[tid].pos)]


func test_build_rail_lays_rail_tiles() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	w.spawn_building("b_rail_yard", 0, o + Vector2i(2, 2), true)
	var eng := w.spawn_unit("engineer", 0, _c(o, 6, 6))
	var rif := w.spawn_unit("rifleman", 0, _c(o, 7, 6))
	check(Rail.validate_command(w, {"type": "build_rail", "issuer": 0, "unit_ids": [rif], "from": [o.x + 6, o.y + 4], "to": [o.x + 9, o.y + 4]}) != "", "only engineers lay rail")
	check(Rail.validate_command(w, {"type": "build_rail", "issuer": 0, "unit_ids": [eng], "from": [o.x + 22, o.y + 22], "to": [o.x + 25, o.y + 22]}) != "", "rail must start at a rail yard or a line")
	var credits0 := int(w.factions[0].credits) + int(w.factions[0].stock.salvage)
	var j0: int = (w.factions[0].journal as Array).size()
	do_cmd(w, 0, {"type": "build_rail", "unit_ids": [eng], "from": [o.x + 6, o.y + 4], "to": [o.x + 20, o.y + 4]})
	var evs := _run_until(w, "RailBuilt", 4000)
	check(evs.has("RailBuilt"), "the rail job finishes")
	check(evs.has("TerrainChanged"), "TerrainChanged emitted for the renderer")
	for x in range(6, 21):
		check(Rail.on_rail(w, o + Vector2i(x, 4)), "RAIL tile at x=%d" % x)
	check(not Rail.on_rail(w, o + Vector2i(21, 4)), "no rail past the end")
	# Passive income over the build outweighs the rail spend, so the cost is read from the ledger:
	# every resource change since the order is journaled; the build:rail entries must cost the
	# yard's per-tile price for all 15 tiles, and the ledger must account for the whole balance.
	var spent := 0
	var other := 0
	var jr: Array = w.factions[0].journal
	for i in range(j0, jr.size()):
		var amt := int(jr[i].get("credits", 0)) + int(jr[i].get("salvage", 0))
		if String(jr[i].cause) == "build:rail":
			spent += amt
		else:
			other += amt
	var per: Dictionary = Rail.tile_cost(w, 0)
	check(spent < 0, "rail costs resources (ledger build:rail %d)" % spent)
	check_eq(spent, -15 * (int(per.get("credits", 0)) + int(per.get("salvage", 0))), "15 tiles at the yard's rail_cost")
	check_eq(int(w.factions[0].credits) + int(w.factions[0].stock.salvage), credits0 + spent + other, "the ledger accounts for the balance")
	check_eq(Rail.validate_command(w, {"type": "build_rail", "issuer": 0, "unit_ids": [eng], "from": [o.x + 20, o.y + 5], "to": [o.x + 20, o.y + 10]}), "", "a line extends from the existing rail")


func test_armored_train_moves_only_on_rail() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_lay(w, o, 5, 25, 10)
	var tid := w.spawn_unit("b_armored_train", 0, _c(o, 6, 10))
	check_eq(String(Content.unit("b_armored_train").get("move_class", "")), "rail", "the armored train has move class rail")
	var r := _drive(w, tid, _c(o, 24, 10), 400)
	check(r[0], "the train stays on rail along the line")
	check(Vector2(r[2]).x >= float(o.x) + 23.0, "the train reaches the far end (%s)" % str(r[2]))
	var r2 := _drive(w, tid, _c(o, 24, 22), 300)
	check(r2[0], "ordered off the line, it never leaves the rail")
	check(w.cell_of(w.entities[tid].pos).y == o.y + 10, "still on the rail row")


func test_cut_rail_stops_train_until_repaired() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_lay(w, o, 5, 25, 10)
	var tid := w.spawn_unit("b_armored_train", 0, _c(o, 6, 10))
	check(not Rail.damage_cell(w, o + Vector2i(15, 10), 10.0), "a light hit does not cut the rail")
	check(Rail.damage_cell(w, o + Vector2i(15, 10), 5000.0), "a heavy hit cuts the tile")
	check(not Rail.on_rail(w, o + Vector2i(15, 10)), "the cut tile is no longer rail")
	var r := _drive(w, tid, _c(o, 24, 10), 400)
	check(r[0] and int(r[1]) < o.x + 15, "the train stops before the cut (max x %d)" % (int(r[1]) - o.x))
	var eng := w.spawn_unit("engineer", 0, _c(o, 14, 12))
	do_cmd(w, 0, {"type": "build_rail", "unit_ids": [eng], "from": [o.x + 14, o.y + 10], "to": [o.x + 16, o.y + 10]})
	var evs := _run_until(w, "RailBuilt", 3000)
	check(evs.has("RailRepaired"), "engineers repair the cut tile")
	check(Rail.on_rail(w, o + Vector2i(15, 10)), "the line is whole again")
	HotState.set_pos(w, eng, _c(o, 14, 20))
	var r2 := _drive(w, tid, _c(o, 24, 10), 400)
	check(r2[0] and Vector2(r2[2]).x >= float(o.x) + 23.0, "after the repair the train runs through (%s)" % str(r2[2]))
