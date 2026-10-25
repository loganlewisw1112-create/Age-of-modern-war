extends "res://tests/test_base.gd"
## G6 MECH6c (CONTRACTS_G6 section 9, section 17): auras. Command Vehicle and Commanders give friendlies in
## radius +accuracy and +morale; the Propaganda Team / Tower give friendlies +morale and drain enemy morale.
## Checks the delegates, the G6Hooks dispatch + MORALE mask key, the live morale tick, and save/load determinism.

const Auras = preload("res://sim/systems/auras.gd")
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")
const Movement = preload("res://sim/systems/movement.gd")


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


func _steps(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()


func _clear_g6_morale(w: SimWorld) -> bool:
	return (G6Hooks.active(w) & G6Hooks.G6_MORALE) == 0


func test_command_vehicle_and_commander_aura() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var near := w.spawn_unit("rifleman", 0, _c(o, 13, 10))
	var far := w.spawn_unit("rifleman", 0, _c(o, 27, 27))
	var foe := w.spawn_unit("rifleman", 1, _c(o, 11, 13))
	w.step()
	check(not w.sys_state.has("auras"), "no auras state without a source (G5 hashes unchanged)")
	check_eq(Auras.acc_mult(w, w.entities[near]), 1.0, "neutral without a source")
	var cv := w.spawn_unit("a_command_vehicle", 0, _c(o, 10, 10))
	w.step()
	check_eq(w.sys_state.auras.sources, [cv], "the command vehicle is a live source")
	check((G6Hooks.active(w) & G6Hooks.G6_MORALE) != 0, "MORALE hook bit set while a source lives")
	var en: Dictionary = w.entities[near]
	var ef: Dictionary = w.entities[far]
	check(is_equal_approx(Auras.acc_mult(w, en), 1.1), "friendly in radius: accuracy x1.1")
	check_eq(Auras.acc_mult(w, ef), 1.0, "friendly out of radius: x1.0")
	check_eq(Auras.acc_mult(w, w.entities[foe]), 1.0, "enemies get no accuracy")
	check(is_equal_approx(G6Hooks.accuracy_mult(w, en, {}, w.entities[foe]), 1.1), "G6Hooks.accuracy_mult carries x1.1")
	en.morale = 50.0
	ef.morale = 50.0
	check(is_equal_approx(Auras.morale_delta(w, en), 10.0 * 0.2), "friendly in radius: +10 morale/s (2.0 per update)")
	check_eq(Auras.morale_delta(w, ef), 0.0, "out of radius: no morale")
	check_eq(Auras.morale_delta(w, w.entities[foe]), 0.0, "the command vehicle does not drain enemies")
	check(G6Hooks.morale_delta(w, en) >= 2.0 - 0.0001, "G6Hooks.morale_delta carries the aura")
	# the live morale tick: the aura unit recovers faster than the control unit (5 updates in 20 ticks)
	_steps(w, 20)
	var gain_near := float(en.morale) - 50.0
	var gain_far := float(ef.morale) - 50.0
	check(gain_near - gain_far > 2.0 * 3.0, "morale tick applies the aura (near +%s vs far +%s)" % [gain_near, gain_far])
	# the Commander has its own aura; the command vehicle's death leaves it as the only source
	var cmdr := w.spawn_unit("a_commander", 0, _c(o, 25, 24))
	w.step()
	check(is_equal_approx(Auras.acc_mult(w, ef), 1.1), "the Commander's aura covers the far rifleman")
	w.destroy(cv, "test")
	w.step()
	check_eq(w.sys_state.auras.sources, [cmdr], "dead sources leave the list")
	check_eq(Auras.acc_mult(w, en), 1.0, "aura gone with the command vehicle")
	w.destroy(cmdr, "test")
	w.step()
	check((w.sys_state.auras.sources as Array).is_empty(), "sources empty once every source died")
	check(_clear_g6_morale(w) or w.sys_state.has("companies"), "MORALE hook bit clear again with no source")


func test_propaganda_buffs_friends_drains_enemies() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var team := w.spawn_unit("b_propaganda_team", 1, _c(o, 10, 10))
	var friend := w.spawn_unit("b_militia", 1, _c(o, 12, 10))
	var enemy := w.spawn_unit("rifleman", 0, _c(o, 10, 14))
	var control := w.spawn_unit("rifleman", 0, _c(o, 10, 26))
	w.step()
	check_eq(w.sys_state.auras.sources, [team], "the propaganda team is a source")
	var fr: Dictionary = w.entities[friend]
	var en: Dictionary = w.entities[enemy]
	fr.morale = 40.0
	check(is_equal_approx(Auras.morale_delta(w, fr), 8.0 * 0.2), "friendlies +8 morale/s")
	check(is_equal_approx(Auras.morale_delta(w, en), -3.0 * 0.2), "enemies drained 3 morale/s")
	check_eq(Auras.morale_delta(w, w.entities[control]), 0.0, "enemies out of radius are not drained")
	check_eq(Auras.acc_mult(w, fr), 1.0, "propaganda gives no accuracy")
	var tower := w.spawn_building("b_propaganda_tower", 1, Vector2i(o.x + 12, o.y + 15), false)
	w.step()
	check(not (w.sys_state.auras.sources as Array).has(tower), "an unfinished tower is not a source")
	w.entities[tower].built = true
	w.step()
	check((w.sys_state.auras.sources as Array).has(tower), "a built tower is a source")
	check(is_equal_approx(Auras.morale_delta(w, en), -4.0 * 0.2), "the worst drain counts (tower -4/s, no stacking)")
	# the live morale tick drains a full-morale enemy; the control stays full
	var m0 := float(en.morale)
	_steps(w, 40)
	check(float(en.morale) < m0 - 3.0, "the enemy in radius loses morale (%s -> %s)" % [m0, en.morale])
	check(is_equal_approx(float(w.entities[control].morale), m0), "the enemy out of radius keeps full morale")
	# save/load mid-aura: continued runs stay hash-equal (caches rebuild from saved state)
	var l := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(l.state_hash(), w.state_hash(), "round trip hash-equal")
	_steps(w, 30)
	_steps(l, 30)
	check_eq(l.state_hash(), w.state_hash(), "continued runs hash-equal with auras live")
