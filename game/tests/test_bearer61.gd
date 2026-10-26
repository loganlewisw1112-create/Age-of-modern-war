extends "res://tests/test_base.gd"
## G6.1 BEARER61: infantry ammo bearer (sim/systems/ammo_bearer.gd, content/g6/defs_g61_bearer.json).

const AmmoBearer = preload("res://sim/systems/ammo_bearer.gd")
const SquadAI = preload("res://sim/systems/squad_ai.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SaveSystem = preload("res://sim/save_system.gd")

const FAR := Vector2(16, 6)   # well outside the HQ supply radius


# ---------------------------------------------------------------- helpers
func _hq(w: SimWorld, fid: int = 0) -> Dictionary:
	return w.buildings_of(fid, "hq")[0]


func _free(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(Movement.nearest_free_cell(w, w.cell_of(p), "foot")) + Vector2(0.5, 0.5)


func _spawn(w: SimWorld, def: String, fid: int, p: Vector2) -> Dictionary:
	return w.entities[w.spawn_unit(def, fid, _free(w, p))]


func _base(w: SimWorld, fid: int = 0) -> Vector2:
	return Vector2(_hq(w, fid).pos)


func _run(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()


## n riflemen of fid in squad sq around p (ammo set to `ammo`).
func _squad(w: SimWorld, fid: int, p: Vector2, sq: int, n: int, ammo: int) -> Array:
	var offs := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 1)]
	var out := []
	for i in n:
		var e := _spawn(w, "rifleman", fid, p + offs[i % offs.size()])
		e.squad = sq
		e.ammo = ammo
		out.append(e)
	SquadAI.touch(w)
	return out


func _ids(arr: Array) -> Array:
	return arr.map(func(x): return int(x.id))


func _centre(arr: Array) -> Vector2:
	var c := Vector2.ZERO
	for e in arr:
		c += Vector2(e.pos)
	return c / float(arr.size())


# ---------------------------------------------------------------- tests
func test_content() -> void:
	for d in ["a_ammo_bearer", "b_supply_carrier", "m_munitions_drone"]:
		var u := Content.unit(d)
		check(bool(u.get("ammo_bearer", false)), d + " is a bearer")
		check_eq(int(u.get("pop", 0)), 1, d + " pop 1")
		check(not Content.production(d).is_empty(), d + " producible")
	check(Content.building("barracks").produces.has("a_ammo_bearer"), "barracks trains the Ammo Bearer")
	check(Content.building("b_barracks").produces.has("b_supply_carrier"), "b_barracks trains the Supply Carrier")
	check(Content.building("m_assembler").produces.has("m_munitions_drone"), "m_assembler trains the Munitions Drone")


func test_full_restock_exactly_three() -> void:
	var w := make_world()
	var p := _base(w) + FAR
	var b := _spawn(w, "a_ammo_bearer", 0, p)
	var mem := _squad(w, 0, p, 9301, 4, 0)
	do_cmd(w, 0, {"type": "join_squad", "unit_ids": [int(b.id)], "squad_unit_id": int(mem[0].id)})
	check_eq(int(b.squad), 9301, "bearer joined the squad")
	check_eq(AmmoBearer.load_line(b), "Ammo load 3.0 / 3", "inspector line full")
	_run(w, 40)
	var full := 0
	for m in mem:
		if int(m.ammo) == 60:
			full += 1
	check_eq(full, 3, "exactly three units fully restocked")
	check_eq(int(mem[3].ammo), 0, "fourth unit got nothing")
	check_eq(int(b.bearer_load), 0, "bearer empty")
	check_eq(AmmoBearer.load_line(b), "Ammo load 0.0 / 3", "inspector line empty")


func test_partial_restock_fractional() -> void:
	var w := make_world()
	var p := _base(w) + FAR
	var b := _spawn(w, "a_ammo_bearer", 0, p)
	var mem := _squad(w, 0, p, 9302, 2, 15)
	mem[1].ammo = 40   # above the 50% bar: left alone
	do_cmd(w, 0, {"type": "join_squad", "unit_ids": [int(b.id)], "squad_unit_id": int(mem[0].id)})
	_run(w, 30)
	check_eq(int(mem[0].ammo), 60, "25% unit restocked to full")
	check_eq(int(mem[1].ammo), 40, "67% unit untouched")
	check_eq(int(b.bearer_load), 2250, "75% of one restock spent")
	check_eq(AmmoBearer.load_line(b), "Ammo load 2.2 / 3", "inspector line rounds down")


func test_refill_at_depot() -> void:
	var w := make_world()
	var b := _spawn(w, "a_ammo_bearer", 0, _base(w) + Vector2(4, 0))
	b.bearer_load = 0
	var s0 := int(w.factions[0].stock.get("ammo", 0))
	_run(w, 80)
	check_eq(int(b.bearer_load), 3000, "refilled to 3 restocks at the HQ")
	check_eq(s0 - int(w.factions[0].stock.get("ammo", 0)), 180, "180 rounds of faction stock spent (60 per restock)")
	# no stock: nothing refilled, and the bearer gives up the trip
	var n := int(w.factions[0].stock.get("ammo", 0))
	if n > 0:
		w.spend(0, {"ammo": n}, "test_drain")
	b.bearer_load = 0
	_run(w, 40)
	check_eq(int(b.bearer_load), 0, "no stock, no load")
	check(not b.has("bearer_trip"), "no trip while the faction has no ammo")


func test_empty_bearer_walks_back() -> void:
	var w := make_world()
	var b := _spawn(w, "a_ammo_bearer", 0, _base(w) + FAR)
	b.bearer_load = 0
	_run(w, 600)
	check_eq(int(b.bearer_load), 3000, "empty bearer walked to a supply point and refilled")
	check(not b.has("bearer_trip"), "trip over")


func test_join_follows_and_leave() -> void:
	var w := make_world()
	var p := _base(w) + Vector2(6, 10)
	var mem := _squad(w, 0, p, 9303, 3, 60)
	var b := _spawn(w, "a_ammo_bearer", 0, p + Vector2(-8, 0))
	do_cmd(w, 0, {"type": "join_squad", "unit_ids": [int(b.id)], "squad_unit_id": int(mem[1].id)})
	check(SquadAI.squad_members(w, 9303).has(int(b.id)), "bearer is a squad member")
	var goal := _free(w, p + Vector2(14, 0))
	do_cmd(w, 0, {"type": "move", "unit_ids": _ids(mem), "target": goal})
	_run(w, 500)
	var c := _centre(mem)
	var d := Vector2(b.pos).distance_to(c)
	check(d <= 4.5, "bearer follows the squad (%.1f tiles from its centre)" % d)
	check(c.distance_to(goal) <= 3.0, "squad reached its goal")
	do_cmd(w, 0, {"type": "leave_squad", "unit_ids": [int(b.id)]})
	check_eq(int(b.squad), -1, "left the squad")
	check(not SquadAI.squad_members(w, 9303).has(int(b.id)), "no longer a member")


func test_validation() -> void:
	var w := make_world()
	var p := _base(w) + FAR
	var b := _spawn(w, "a_ammo_bearer", 0, p)
	var mem := _squad(w, 0, p, 9304, 2, 60)
	var foe := _squad(w, 1, _base(w, 1) + Vector2(4, 4), 9305, 2, 60)
	var lone := _spawn(w, "rifleman", 0, p + Vector2(3, 3))
	var j := {"type": "join_squad", "issuer": 0, "unit_ids": [int(mem[1].id)], "squad_unit_id": int(mem[0].id)}
	check(w.preview_command(j) != "", "a rifleman cannot join_squad as a bearer")
	j.unit_ids = [int(b.id)]
	check_eq(w.preview_command(j), "", "bearer joining an own squad is valid")
	j.squad_unit_id = int(foe[0].id)
	check(w.preview_command(j) != "", "enemy squad rejected")
	j.squad_unit_id = int(lone.id)
	check(w.preview_command(j) != "", "unit without a squad rejected")
	j.squad_unit_id = int(mem[0].id)
	w.destroy(int(mem[0].id), "test")
	check(w.preview_command(j) != "", "dead target rejected")
	var e1 := _spawn(w, "a_ammo_bearer", 1, _base(w, 1) + Vector2(5, 5))
	check(w.preview_command({"type": "leave_squad", "issuer": 0, "unit_ids": [int(e1.id)]}) != "", "enemy bearer rejected")


func _scenario() -> SimWorld:
	var w := make_world()
	var p := _base(w) + FAR
	var mem := _squad(w, 0, p, 9306, 4, 10)
	var b := _spawn(w, "a_ammo_bearer", 0, p + Vector2(-3, 0))
	w.submit({"type": "join_squad", "issuer": 0, "unit_ids": [int(b.id)], "squad_unit_id": int(mem[0].id)})
	w.submit({"type": "move", "issuer": 0, "unit_ids": _ids(mem), "target": _free(w, p + Vector2(0, 8))})
	return w


func test_save_load_determinism() -> void:
	var a := _scenario()
	var b := _scenario()
	_run(a, 200)
	_run(b, 200)
	check_eq(a.state_hash(), b.state_hash(), "same setup, same hash at 200")
	var path := "user://test_bearer61/mid.sav"
	DirAccess.make_dir_recursive_absolute("user://test_bearer61")
	check_eq(SaveSystem.save(a, path), "", "save ok")
	var l: SimWorld = SaveSystem.load(path)
	if not check(l != null, "loaded"):
		return
	check_eq(l.state_hash(), a.state_hash(), "hash equal after load")
	_run(a, 300)
	_run(l, 300)
	check_eq(l.state_hash(), a.state_hash(), "hash equal at 500 after save/load at 200")
	DirAccess.remove_absolute(path)


func test_ai_helpers() -> void:
	var w := make_world()
	check_eq(AmmoBearer.bearer_def_for(w, 0), "a_ammo_bearer", "human_a bearer def")
	var p := _base(w) + FAR
	_squad(w, 0, p, 9311, 3, 60)
	_squad(w, 0, p + Vector2(0, 5), 9312, 3, 60)
	check_eq(AmmoBearer.ai_wanted(w, 0), 1, "2 squads want 1 bearer")
	var b := _spawn(w, "a_ammo_bearer", 0, p + Vector2(-3, 0))
	_run(w, 1)
	check_eq(AmmoBearer.ai_wanted(w, 0), 0, "covered")
	check_eq(AmmoBearer.ai_attach(w, 0), 1, "one bearer attached")
	check_eq(int(b.squad), 9311, "attached to the nearest squad")
	check_eq(AmmoBearer.ai_attach(w, 0), 0, "nothing left to attach")
