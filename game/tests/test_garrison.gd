extends "res://tests/test_base.gd"
## G6 MECH6a (CONTRACTS_G6 section 9): garrison slots, firing from the building at x0.5 damage,
## hidden until firing, eject/kill on building death, anti_garrison weapons x2.

const Garrison = preload("res://sim/systems/garrison.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Fog = preload("res://sim/systems/fog.gd")


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
	return [w, o]


func _c(o: Vector2i, x: int, y: int) -> Vector2:
	return Vector2(o) + Vector2(x, y) + Vector2(0.5, 0.5)


func _inside(w: SimWorld, uid: int, bid: int) -> bool:
	var b: Dictionary = w.entities[bid]
	var p: Vector2 = w.entities[uid].pos
	return Rect2(Vector2(b.cell), Vector2(b.size, b.size)).has_point(p)


## Garrison units into bid and step until they are inside (or max ticks).
func _enter(w: SimWorld, ids: Array, bid: int, n: int) -> void:
	do_cmd(w, 0, {"type": "garrison", "unit_ids": ids, "building_id": bid})
	for i in 600:
		if Garrison.occupants(w, bid).size() >= n:
			return
		w.step()


func test_garrison_capacity_slots() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var bid := w.spawn_building("s_garrison_bld", 0, o + Vector2i(10, 10), true)
	var slots := Garrison.slots_of("s_garrison_bld")
	check(slots > 0, "the garrisonable building has slots (%d)" % slots)
	check(Garrison.slots_of("b_pillbox") > 0 and Garrison.slots_of("a_fob") > 0, "pillbox and FOB have garrison slots")
	var ids := []
	for i in slots + 1:
		ids.append(w.spawn_unit("rifleman", 0, _c(o, 6 + i, 6)))
	var tank := w.spawn_unit("mbt", 0, _c(o, 4, 14))
	check(Garrison.validate_command(w, {"type": "garrison", "issuer": 0, "unit_ids": [tank], "building_id": bid}) != "", "vehicles cannot garrison")
	check(Garrison.validate_command(w, {"type": "garrison", "issuer": 1, "unit_ids": ids, "building_id": bid}) != "", "not the enemy's building")
	_enter(w, ids, bid, slots)
	for i in 60:
		w.step()
	var occ := Garrison.occupants(w, bid)
	check_eq(occ.size(), slots, "exactly the slot count is inside")
	for uid in occ:
		check(_inside(w, uid, bid) and int(w.entities[uid].garrisoned_in) == bid, "occupant %d sits in the building" % uid)
	var extra := -1
	for uid in ids:
		if not occ.has(uid):
			extra = uid
	check(not w.entities[extra].has("garrisoned_in"), "the extra squad stays outside")
	check(Garrison.validate_command(w, {"type": "garrison", "issuer": 0, "unit_ids": [extra], "building_id": bid}) != "", "a full building refuses more")
	do_cmd(w, 0, {"type": "ungarrison", "building_id": bid})
	check_eq(Garrison.occupants(w, bid).size(), 0, "ungarrison empties it")
	for uid in occ:
		check(not _inside(w, uid, bid) and not w.entities[uid].has("garrisoned_in"), "unit %d is back outside" % uid)


func test_garrisoned_fire_and_take_half_damage() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var bid := w.spawn_building("s_garrison_bld", 0, o + Vector2i(10, 10), true)
	var g := w.spawn_unit("rifleman", 0, _c(o, 8, 10))
	_enter(w, [g], bid, 1)
	check(Garrison.occupants(w, bid).has(g), "squad inside")
	var enemy := w.spawn_unit("rifleman", 1, _c(o, 11, 16))
	var fired := false
	for i in 120:
		w.step()
		if w.entities.has(g) and w.tick - int(w.entities[g].get("last_fired_tick", -1000)) <= 1:
			fired = true
			break
	check(fired, "the garrisoned squad fires from the building")
	check(w.entities.has(g) and _inside(w, g, bid), "it keeps its slot while firing")
	var gd: Dictionary = w.entities[g]
	var src: Dictionary = w.entities[enemy] if w.entities.has(enemy) else {"id": -1, "kind": "unit", "owner": 1, "def": "rifleman", "pos": _c(o, 11, 16)}
	var rifle := {"weapon": "rifle", "cls": "small_arms", "damage": 9.0, "splash": 0.0}
	check(is_equal_approx(Garrison.protect_mult(w, src, rifle, gd), 0.5), "protect_mult 0.5")
	check(is_equal_approx(G6Hooks.damage_mult(w, src, rifle, gd), 0.5), "G6Hooks.damage_mult delegates the garrison x0.5")
	var splash := {"weapon": "mortar", "cls": "artillery", "damage": 9.0, "splash": 1.5}
	check(is_equal_approx(G6Hooks.damage_mult(w, src, splash, gd), 0.5), "splash on the building's occupants x0.5 too")
	var out: Dictionary = w.entities[w.spawn_unit("rifleman", 0, _c(o, 25, 25))]
	check(is_equal_approx(G6Hooks.damage_mult(w, src, rifle, out), 1.0), "an ungarrisoned squad takes full damage")


func test_hidden_until_firing() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var bid := w.spawn_building("s_garrison_bld", 0, o + Vector2i(10, 10), true)
	var g := w.spawn_unit("rifleman", 0, _c(o, 8, 10))
	_enter(w, [g], bid, 1)
	# recon at 8 tiles: inside its sight 12, outside the squad's rifle range 6
	var spot := w.spawn_unit("recon", 1, _c(o, 11, 19))
	for i in 10:
		w.step()
	var gd: Dictionary = w.entities[g]
	check(not Garrison.visible_to(w, 1, gd), "hidden from the enemy while it holds fire")
	check(Garrison.visible_to(w, 0, gd), "the owner sees it")
	check(not G6Hooks.visible_to(w, 1, gd), "G6Hooks.visible_to delegates")
	check(not Fog.entity_visible(w, 1, gd), "fog: the enemy recon does not see it")
	gd.last_fired_tick = w.tick
	check(Garrison.visible_to(w, 1, gd), "firing reveals it")
	for i in int(round(float(Garrison.R().get("reveal_s", 3.0)) / SimWorld.DT)) + 2:
		w.step()
	check(not Garrison.visible_to(w, 1, w.entities[g]), "hidden again after reveal_s")
	check(w.entities.has(spot), "the recon was never shot at")


func test_building_death_ejects_or_kills() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var house := w.spawn_building("s_garrison_bld", 0, o + Vector2i(6, 10), true)
	var pill := w.spawn_building("b_pillbox", 0, o + Vector2i(18, 10), true)
	var a1 := w.spawn_unit("rifleman", 0, _c(o, 5, 8))
	var a2 := w.spawn_unit("rifleman", 0, _c(o, 6, 8))
	var p1 := w.spawn_unit("rifleman", 0, _c(o, 17, 8))
	var p2 := w.spawn_unit("rifleman", 0, _c(o, 18, 8))
	_enter(w, [a1, a2], house, 2)
	_enter(w, [p1, p2], pill, 2)
	check(Garrison.occupants(w, house).size() == 2 and Garrison.occupants(w, pill).size() == 2, "both buildings garrisoned")
	w.destroy(house, "test", 1)
	w.destroy(pill, "test", 1)
	w.step()
	for uid in [a1, a2]:
		check(w.entities.has(uid), "eject rule: unit %d survives" % uid)
		if w.entities.has(uid):
			var e: Dictionary = w.entities[uid]
			check(not e.has("garrisoned_in") and float(e.hp) < float(e.max_hp), "ejected unit %d is out and hurt" % uid)
			check(Movement.is_passable(w, w.cell_of(e.pos), "foot"), "ejected onto a passable cell")
	for uid in [p1, p2]:
		check(not w.entities.has(uid), "kill rule (pillbox): unit %d dies with the building" % uid)


func test_anti_garrison_weapons_double() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var bid := w.spawn_building("s_garrison_bld", 0, o + Vector2i(10, 10), true)
	var g := w.spawn_unit("rifleman", 0, _c(o, 8, 10))
	_enter(w, [g], bid, 1)
	var gd: Dictionary = w.entities[g]
	var src := {"id": -1, "kind": "unit", "owner": 1, "def": "b_flamer", "pos": _c(o, 10, 14)}
	var rifle := Garrison.protect_mult(w, src, {"weapon": "rifle", "cls": "small_arms"}, gd)
	var flame := Garrison.protect_mult(w, src, {"weapon": "flamethrower", "cls": "flame"}, gd)
	var satchel := Garrison.protect_mult(w, {"id": -1, "kind": "unit", "owner": 1, "def": "b_satchel_sappers", "pos": src.pos}, {"weapon": "g6_satchel", "cls": "demolition"}, gd)
	check(is_equal_approx(flame, rifle * 2.0), "flame x2 vs garrisoned squads (%s vs %s)" % [flame, rifle])
	check(is_equal_approx(satchel, rifle * 2.0), "satchel charges x2 vs garrisoned squads (%s)" % satchel)
	var open: Dictionary = w.entities[w.spawn_unit("rifleman", 0, _c(o, 25, 25))]
	check(is_equal_approx(Garrison.protect_mult(w, src, {"weapon": "flamethrower", "cls": "flame"}, open), 1.0), "no garrison bonus outside")
