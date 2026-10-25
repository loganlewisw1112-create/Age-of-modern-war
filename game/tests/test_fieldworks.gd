extends "res://tests/test_base.gd"
## G6 MECH6a (CONTRACTS_G6 section 9): infantry-built sandbags / trench lines, cover multipliers,
## tank traps (foot only), barbed wire (foot slow + clearing), camo nets, decoys.

const Fieldworks = preload("res://sim/systems/fieldworks.gd")
const Fortify = preload("res://sim/systems/fortify.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")
const Fog = preload("res://sim/systems/fog.gd")


## Inert world with a 30x30 GRASS arena (explored by side 0); returns [w, origin].
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
	var ex: PackedByteArray = w.fog[0].explored
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			ex[y * mw + x] = 1
	w.fog[0].explored = ex
	w.factions[0].credits = 5000
	w.factions[0].stock.salvage = 5000
	return [w, o]


func _c(o: Vector2i, x: int, y: int) -> Vector2:
	return Vector2(o) + Vector2(x, y) + Vector2(0.5, 0.5)


func _built_at(w: SimWorld, def_id: String, cell: Vector2i) -> bool:
	for id in w.entities:
		var b: Dictionary = w.entities[id]
		if b.kind == "building" and String(b.def) == def_id and Vector2i(b.cell) == cell:
			return bool(b.built)
	return false


func _finish_line(w: SimWorld, max_ticks: int) -> bool:
	for i in max_ticks:
		w.step()
		for ev in w.events:
			if ev.type == "LineFinished":
				return true
	return false


func test_infantry_build_sandbags_and_trench_by_line() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var r1 := w.spawn_unit("rifleman", 0, _c(o, 8, 8))
	var r2 := w.spawn_unit("rifleman", 0, _c(o, 9, 8))
	check(Fieldworks.is_field_buildable("s_sandbags") and Fieldworks.is_field_buildable("s_trench"), "sandbags and trench are field_buildable")
	check(Fortify.validate_command(w, {"type": "build_line", "issuer": 0, "def": "s_tank_traps", "unit_ids": [r1], "from": [o.x + 8, o.y + 12], "to": [o.x + 9, o.y + 12]}) != "", "riflemen cannot build non-field works (tank traps)")
	do_cmd(w, 0, {"type": "build_line", "def": "s_sandbags", "unit_ids": [r1, r2], "from": [o.x + 8, o.y + 10], "to": [o.x + 11, o.y + 10]})
	check(_finish_line(w, 3000), "the sandbag line finishes")
	for x in range(8, 12):
		check(_built_at(w, "s_sandbags", o + Vector2i(x, 10)), "sandbags built at x=%d" % x)
	do_cmd(w, 0, {"type": "build_line", "def": "s_trench", "unit_ids": [r1], "from": [o.x + 8, o.y + 14], "to": [o.x + 9, o.y + 14]})
	check(_finish_line(w, 3000), "the trench line finishes")
	check(_built_at(w, "s_trench", o + Vector2i(8, 14)) and _built_at(w, "s_trench", o + Vector2i(9, 14)), "trench built by one rifleman")


func test_cover_mult_sandbags_and_trench() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	w.spawn_building("s_sandbags", 0, o + Vector2i(10, 10), true)
	w.spawn_building("s_trench", 0, o + Vector2i(20, 10), true)
	var behind: Dictionary = w.entities[w.spawn_unit("rifleman", 0, _c(o, 10, 11))]
	var dug: Dictionary = w.entities[w.spawn_unit("rifleman", 0, _c(o, 20, 10))]
	var open: Dictionary = w.entities[w.spawn_unit("rifleman", 0, _c(o, 25, 22))]
	var tank: Dictionary = w.entities[w.spawn_unit("mbt", 0, _c(o, 11, 11))]
	var north: Dictionary = w.entities[w.spawn_unit("rifleman", 1, _c(o, 10, 3))]
	var south: Dictionary = w.entities[w.spawn_unit("rifleman", 1, _c(o, 10, 19))]
	var direct := {"weapon": "rifle", "cls": "small_arms", "damage": 10.0, "splash": 0.0}
	var splash := {"weapon": "mortar", "cls": "artillery", "damage": 10.0, "splash": 1.5}
	var bag := float(Fieldworks.info("s_sandbags").get("cover_direct", 0))
	check(is_equal_approx(bag, 0.75), "sandbags cover_mult 0.75 (got %s)" % bag)
	check(is_equal_approx(Fieldworks.cover_mult(w, north, direct, behind), 0.75), "behind sandbags vs fire from the bag side: x0.75")
	check(is_equal_approx(Fieldworks.cover_mult(w, south, direct, behind), 1.0), "no cover from the open side")
	check(is_equal_approx(Fieldworks.cover_mult(w, north, direct, dug), 0.6), "trench vs direct fire: x0.6")
	check(is_equal_approx(Fieldworks.cover_mult(w, north, splash, dug), 0.5), "trench vs splash: x0.5")
	check(is_equal_approx(Fieldworks.cover_mult(w, north, direct, open), 1.0), "open ground: no cover")
	check(is_equal_approx(Fieldworks.cover_mult(w, north, direct, tank), 1.0), "vehicles get no fieldwork cover")
	check(is_equal_approx(G6Hooks.damage_mult(w, north, direct, dug), 0.6), "G6Hooks.damage_mult delegates the trench cover (got %s)" % G6Hooks.damage_mult(w, north, direct, dug))
	check(is_equal_approx(Fieldworks.cover_at(w, o + Vector2i(20, 10)), 0.6) and is_equal_approx(Fieldworks.cover_at(w, o + Vector2i(25, 22)), 1.0), "cover_at for AI")


func test_tank_traps_block_vehicles_not_foot() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var d := Content.building("s_tank_traps")
	check(Fieldworks.passable(d, "foot") and not Fieldworks.passable(d, "vehicle"), "tank traps: passable_for foot only")
	check(G6Hooks.passable(d, "foot") and not G6Hooks.passable(d, "vehicle"), "G6Hooks.passable delegates")
	var c := o + Vector2i(12, 12)
	w.spawn_building("s_tank_traps", 0, c, true)
	check(Movement.is_passable(w, c, "foot"), "infantry can walk through the traps cell (nav)")
	check(not Movement.is_passable(w, c, "vehicle"), "vehicles cannot enter the traps cell (nav)")


func test_wire_slows_foot_and_is_cleared() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var w1 := w.spawn_building("s_barbed_wire", 1, o + Vector2i(10, 10), true)
	var w2 := w.spawn_building("s_barbed_wire", 1, o + Vector2i(20, 10), true)
	var w3 := w.spawn_building("s_barbed_wire", 1, o + Vector2i(15, 20), true)
	var rif := w.spawn_unit("rifleman", 0, _c(o, 10, 10))
	var mult := Fieldworks.wire_mult(w, w.entities[rif])
	check(is_equal_approx(mult, 0.35), "foot on wire: speed x0.35 (got %s)" % mult)
	check(is_equal_approx(G6Hooks.speed_mult(w, w.entities[rif]), 0.35), "G6Hooks.speed_mult delegates the wire")
	var jeep := w.spawn_unit("ifv", 0, _c(o, 4, 4))
	HotState.set_pos(w, jeep, _c(o, 10, 10))
	check(is_equal_approx(Fieldworks.wire_mult(w, w.entities[jeep]), 1.0), "vehicles are not slowed by wire")
	HotState.set_pos(w, jeep, _c(o, 4, 4))
	HotState.set_pos(w, rif, _c(o, 3, 3))
	var tank := w.spawn_unit("mbt", 0, _c(o, 20, 10))
	for i in 6:
		w.step()
	check(not w.entities.has(w2), "a heavy tank crushes the wire")
	var eng := w.spawn_unit("a_combat_engineer", 0, _c(o, 15, 17))
	do_cmd(w, 0, {"type": "sweep", "unit_ids": [eng], "rect": [o.x + 15, o.y + 20, o.x + 15, o.y + 20]})
	for i in 600:
		w.step()
		if not w.entities.has(w3):
			break
	check(not w.entities.has(w3), "engineers clear wire")
	var flamer := {"id": rif, "kind": "unit", "owner": 0, "pos": _c(o, 9, 10)}
	check(Fieldworks.cover_mult(w, flamer, {"weapon": "flamethrower", "cls": "flame"}, w.entities[w1]) > 1.0, "flame burns wire (damage multiplier > 1)")
	check(w.entities.has(w1) and w.entities.has(tank), "wire nobody touched stays")


func test_camo_hides_until_move_or_fire() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	w.spawn_building("s_camo_decoy", 0, o + Vector2i(10, 10), true)
	# weaponless trucks: nobody fires, so only camo decides visibility
	var tank := w.spawn_unit("logistics_truck", 0, _c(o, 12, 11))
	var open := w.spawn_unit("logistics_truck", 0, _c(o, 15, 14))
	var spotter := w.spawn_unit("logistics_truck", 1, _c(o, 15, 11))
	for i in 60:
		w.step()
	var t: Dictionary = w.entities[tank]
	check(t.has("camo_net"), "a parked unit next to its camo net is under it")
	check(not Fieldworks.camo_visible(w, 1, t), "camouflaged from the enemy")
	check(Fieldworks.camo_visible(w, 0, t), "the owner always sees it")
	check(not G6Hooks.visible_to(w, 1, t), "G6Hooks.visible_to delegates camo")
	check(not Fog.entity_visible(w, 1, t), "fog: the enemy spotter 3 tiles away does not see it")
	check(Fieldworks.camo_visible(w, 1, w.entities[open]), "a unit without a net is visible")
	check(Fog.entity_visible(w, 1, w.entities[open]), "fog: the spotter sees an uncovered truck 3 tiles away")
	t.last_fired_tick = w.tick
	check(Fieldworks.camo_visible(w, 1, t), "firing reveals it")
	for i in 100:
		w.step()
	t = w.entities[tank]
	check(not Fieldworks.camo_visible(w, 1, t), "hidden again some time after firing")
	HotState.set_moving(w, tank, true)
	check(Fieldworks.camo_visible(w, 1, w.entities[tank]), "moving reveals it")
	check(w.entities.has(spotter), "spotter alive")


func test_decoy_draws_fire() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var tank: Dictionary = w.entities[w.spawn_unit("mbt", 0, _c(o, 5, 5))]
	var decoy: Dictionary = w.entities[w.spawn_building("s_camo_decoy", 0, o + Vector2i(10, 10), true)]
	check(Fieldworks.is_decoy(decoy), "the camo/decoy building is a decoy")
	check(Fieldworks.target_weight(w, 1, decoy) > Fieldworks.target_weight(w, 1, tank), "the enemy weights the decoy above a real tank")
	check(is_equal_approx(Fieldworks.target_weight(w, 1, tank), 1.0), "real targets weight 1")
	check(is_equal_approx(Fieldworks.target_weight(w, 0, decoy), 1.0), "own decoy is not a priority for its owner")
	check_eq(int(Fieldworks.pick_target(w, 1, [tank, decoy]).get("id", -1)), int(decoy.id), "AI/strike target pick takes the decoy")
