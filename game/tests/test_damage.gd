extends "res://tests/test_base.gd"
## G2 damage pipeline (agent A2): facing armor, cover, components, suppression/morale, line of
## fire, concealment, determinism + save round trip. Contract: docs/CONTRACTS_G2.md section 2.

const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Status = preload("res://sim/systems/status.gd")
const C := Vector2(0.5, 0.5)


func _world(overrides: Dictionary = {}) -> SimWorld:
	var w := make_world(overrides)
	w.ai_state = {}
	return w


func _paint(w: SimWorld, rect: Rect2i, code: int) -> void:
	var t: PackedByteArray = w.map.terrain
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			t[y * int(w.map.w) + x] = code
	w.map.terrain = t
	Movement.rebuild_nav(w)


## Open grass arena x 22..73, y 0..25 (away from both HQs).
func _arena(w: SimWorld) -> void:
	_paint(w, Rect2i(22, 0, 52, 26), Terrain.GRASS)


func _spawn(w: SimWorld, def: String, fid: int, cell: Vector2i) -> int:
	var mc: String = Movement.udef(def).mc
	return w.spawn_unit(def, fid, Vector2(Movement.nearest_free_cell(w, cell, mc)) + C)


func _count(events: Array, type: String, key: String = "", val = null) -> int:
	var n := 0
	for ev in events:
		if ev.type == type and (key == "" or ev.get(key) == val):
			n += 1
	return n


## One AT hit on an MBT facing `facing`, shooter due west of it. Returns [damage, hit_side].
func _mbt_hit(facing: float) -> Array:
	var w := _world()
	_arena(w)
	var mbt: Dictionary = w.entities[_spawn(w, "mbt", 1, Vector2i(40, 10))]
	var sh: Dictionary = w.entities[_spawn(w, "at_gunner", 0, Vector2i(35, 10))]
	mbt.facing = facing
	var hp0 := float(mbt.hp)
	w.events = []
	Damage.apply_hit(w, sh, mbt, Combat.stats(sh), true)
	var side := ""
	for ev in w.events:
		if ev.type == "Damage":
			side = String(ev.hit_side)
	return [hp0 - float(mbt.hp), side]


# ---------------------------------------------------------------- armor facing
func test_rear_hit_on_mbt_beats_front_hit() -> void:
	var front := _mbt_hit(PI)          # facing west, toward the shooter
	var side := _mbt_hit(PI / 2.0)
	var rear := _mbt_hit(0.0)          # facing east, shooter behind it
	check_eq(front[1], "front", "front arc reported")
	check_eq(side[1], "side", "side arc reported")
	check_eq(rear[1], "rear", "rear arc reported")
	check(float(rear[0]) > float(side[0]) and float(side[0]) > float(front[0]),
		"rear > side > front damage (got %s / %s / %s)" % [rear[0], side[0], front[0]])
	check(absf(float(rear[0]) / float(front[0]) - 1.7) < 0.01, "rear/front ratio = rules.armor_facing.rear (1.7)")


# ---------------------------------------------------------------- cover
func _rifle_hit(w: SimWorld, tcell: Vector2i) -> float:
	var t: Dictionary = w.entities[_spawn(w, "rifleman", 1, tcell)]
	var sh: Dictionary = w.entities[_spawn(w, "rifleman", 0, tcell - Vector2i(4, 0))]
	var hp0 := float(t.hp)
	Damage.apply_hit(w, sh, t, Combat.stats(sh), true)
	return hp0 - float(t.hp)


func test_infantry_in_forest_takes_less_small_arms_damage() -> void:
	var w1 := _world()
	_arena(w1)
	var open := _rifle_hit(w1, Vector2i(40, 10))
	var w2 := _world()
	_arena(w2)
	_paint(w2, Rect2i(39, 9, 3, 3), Terrain.FOREST)
	var forest := _rifle_hit(w2, Vector2i(40, 10))
	check(open > 0.0, "open hit did damage")
	check(forest < open, "forest target takes less small-arms damage (%.3f < %.3f)" % [forest, open])
	check(absf(forest / open - 0.6) < 0.01, "forest/open ratio = rules.cover.small_arms (0.6)")
	# cover next to a wreck: flag refreshed by morale.gd every 4 ticks
	var w3 := _world()
	_arena(w3)
	var v := _spawn(w3, "ifv", 1, Vector2i(50, 10))
	w3.destroy(v, "test")
	var r: Dictionary = w3.entities[_spawn(w3, "rifleman", 0, Vector2i(51, 10))]
	for i in 4:
		w3.step()
	check(bool(r.get("in_cover", false)), "rifleman 1 tile from a wreck is in_cover")
	var far: Dictionary = w3.entities[_spawn(w3, "rifleman", 0, Vector2i(56, 10))]
	for i in 4:
		w3.step()
	check(not bool(far.get("in_cover", true)), "rifleman 6 tiles from the wreck is not in_cover")


# ---------------------------------------------------------------- components (MIL-02 / QA-008)
func test_mil02_mobility_kill_still_fires_and_weapon_kill_never_fires() -> void:
	var w := _world()
	_arena(w)
	var id := _spawn(w, "mbt", 0, Vector2i(30, 10))
	var e: Dictionary = w.entities[id]
	e.comp.mobility = 0.0
	var p0: Vector2 = e.pos
	do_cmd(w, 0, {"type": "move", "unit_ids": [id], "target": Vector2(50.5, 10.5)})
	for i in 100:
		w.step()
	check(e.pos.distance_to(p0) < 0.01, "mobility-disabled MBT stays put over 100 ticks (moved %.3f)" % e.pos.distance_to(p0))
	check_eq(Status.move_mult(w, e), 0.0, "move_mult 0 when mobility is disabled")
	do_cmd(w, 0, {"type": "stop", "unit_ids": [id]})
	var tid := _spawn(w, "rifleman", 1, Vector2i(36, 10))
	var shots := 0
	for i in 800:
		w.step()
		shots += _count(w.events, "ShotFired", "shooter", id)
		if not w.entities.has(tid):
			break
	check(shots > 0, "mobility-disabled MBT still fires")
	check(not w.entities.has(tid), "mobility-disabled MBT kills a target in range")
	# weapon kill
	var w2 := _world()
	_arena(w2)
	var id2 := _spawn(w2, "mbt", 0, Vector2i(30, 10))
	w2.entities[id2].comp.weapon = 0.0
	_spawn(w2, "rifleman", 1, Vector2i(36, 10))
	var mine := 0
	var theirs := 0
	for i in 300:
		w2.step()
		mine += _count(w2.events, "ShotFired", "shooter", id2)
		theirs += _count(w2.events, "ShotFired")
	check_eq(mine, 0, "weapon-disabled MBT never fires")
	check(theirs > 0, "the enemy rifleman did fire (fight was live)")
	check_eq(Status.can_fire(w2, w2.entities[id2]), "WEAPON_DISABLED", "can_fire reason")


func test_component_disabled_fires_once_and_again_after_repair() -> void:
	var w := _world()
	_arena(w)
	var mbt: Dictionary = w.entities[_spawn(w, "mbt", 1, Vector2i(40, 10))]
	var sh: Dictionary = w.entities[_spawn(w, "at_gunner", 0, Vector2i(35, 10))]
	mbt.hp = 1.0e6
	w.events = []
	for i in 200:
		Damage.apply_hit(w, sh, mbt, Combat.stats(sh), true)
	for c in ["mobility", "weapon", "sensors"]:
		check_eq(float(mbt.comp[c]), 0.0, "%s destroyed after 200 AT hits" % c)
		check_eq(_count(w.events, "ComponentDisabled", "component", c), 1, "one ComponentDisabled for %s" % c)
	mbt.comp.mobility = 100.0  # repaired (agent B2 restores components)
	w.events = []
	for i in 200:
		Damage.apply_hit(w, sh, mbt, Combat.stats(sh), true)
	check_eq(_count(w.events, "ComponentDisabled", "component", "mobility"), 1, "repaired mobility can be disabled again")
	check_eq(_count(w.events, "ComponentDisabled", "component", "weapon"), 0, "already-dead weapon emits nothing new")


# ---------------------------------------------------------------- suppression / pinned
## Moves a rifleman east for 40 ticks; if `fire`, an enemy keeps near-missing it. Returns [dist, world, unit].
func _pinned_run(fire: bool) -> Array:
	var w := _world()
	_arena(w)
	var e: Dictionary = w.entities[_spawn(w, "rifleman", 0, Vector2i(30, 10))]
	var sh: Dictionary = w.entities[_spawn(w, "rifleman", 1, Vector2i(30, 21))]
	var s := Combat.stats(sh)
	if fire:
		for i in 8:
			Damage.apply_hit(w, sh, e, s, false)  # near misses
	var p0: Vector2 = e.pos
	do_cmd(w, 0, {"type": "move", "unit_ids": [int(e.id)], "target": Vector2(50.5, 10.5)})
	for i in 40:
		if fire and i % 5 == 0:
			Damage.apply_hit(w, sh, e, s, false)
		w.step()
	return [e.pos.distance_to(p0), w, e]


func test_sustained_fire_pins_then_unit_recovers() -> void:
	var free := _pinned_run(false)
	var pin := _pinned_run(true)
	var e: Dictionary = pin[2]
	var w: SimWorld = pin[1]
	check(bool(e.pinned), "sustained near misses pin the rifleman (supp=%.1f)" % float(e.supp))
	check(float(pin[0]) < 0.7 * float(free[0]), "pinned unit is slower (%.2f vs %.2f tiles)" % [pin[0], free[0]])
	check_eq(Status.accuracy_mult(w, e), 0.5, "pinned accuracy mult")
	for i in 100:
		w.step()
	check(not bool(e.pinned), "unpinned 5 s after fire stops (supp=%.1f)" % float(e.supp))
	for i in 300:
		w.step()
	check_eq(float(e.supp), 0.0, "suppression fully decays")
	check(float(e.morale) > 90.0, "morale recovers after fire stops (%.1f)" % float(e.morale))


# ---------------------------------------------------------------- break / rally
func test_squad_casualties_break_unit_which_retreats_then_rallies() -> void:
	var w := _world()
	_arena(w)
	var hq: Dictionary = w.buildings_of(0, "hq")[0]
	var ids := []
	for i in 7:
		var id := _spawn(w, "rifleman", 0, Vector2i(40 + i, 12))
		w.entities[id].squad = 77
		ids.append(id)
	var other := _spawn(w, "rifleman", 0, Vector2i(41, 14))   # different squad: unaffected
	var sh: Dictionary = w.entities[_spawn(w, "rifleman", 1, Vector2i(43, 23))]
	var big := {"damage": 5000.0, "cls": "at"}
	for i in 6:
		Damage.apply_hit(w, sh, w.entities[ids[i]], big, true)
	var e: Dictionary = w.entities[ids[6]]
	var broke := 0
	for i in 8:
		w.step()
		broke += _count(w.events, "UnitBroken", "id", ids[6])
	check(float(e.morale) < 25.0, "six squadmate deaths drop morale below break_at (%.1f)" % float(e.morale))
	check_eq(float(w.entities[other].morale), 100.0, "a unit of another squad keeps its morale")
	check_eq(broke, 1, "UnitBroken emitted once")
	check(bool(e.broken), "unit is broken")
	check_eq(String(e.order.type), "retreat", "broken unit has a retreat order")
	check_eq(Status.can_fire(w, e), "BROKEN", "broken unit cannot fire")
	var hp: Vector2 = hq.pos
	var d0: float = e.pos.distance_to(hp)
	for i in 100:
		w.step()
	check(e.pos.distance_to(hp) < d0 - 3.0, "broken unit retreats toward its HQ (%.1f -> %.1f)" % [d0, e.pos.distance_to(hp)])
	var rallied := 0
	for i in 900:
		w.step()
		rallied += _count(w.events, "UnitRallied", "id", ids[6])
		if rallied > 0:
			break
	check_eq(rallied, 1, "unit rallies once morale recovers")
	check(not bool(e.broken), "rallied unit is no longer broken")
	check_eq(String(e.order.type), "idle", "rallied unit is idle")
	check(float(e.morale) >= 60.0, "rallied at morale >= rally_at (%.1f)" % float(e.morale))


# ---------------------------------------------------------------- line of fire
func _ridge_shots(ridge: bool) -> int:
	var w := _world()
	_arena(w)
	if ridge:
		_paint(w, Rect2i(40, 0, 1, 26), Terrain.RIDGE)
	var a := _spawn(w, "rifleman", 0, Vector2i(37, 10))
	var b := _spawn(w, "rifleman", 1, Vector2i(43, 10))
	do_cmd(w, 0, {"type": "hold", "unit_ids": [a]})
	do_cmd(w, 1, {"type": "hold", "unit_ids": [b]})
	var n := 0
	for i in 100:
		w.step()
		n += _count(w.events, "ShotFired")
	return n


func test_shot_across_ridge_is_blocked() -> void:
	check_eq(_ridge_shots(true), 0, "no ShotFired across a ridge")
	check(_ridge_shots(false) > 0, "control: the same pair fires without the ridge")
	var w := _world()
	_arena(w)
	_paint(w, Rect2i(40, 0, 1, 26), Terrain.RIDGE)
	check(not Damage.line_clear(w, Vector2(37.5, 10.5), Vector2(43.5, 12.5)), "diagonal line through the ridge blocked")
	check(Damage.line_clear(w, Vector2(37.5, 10.5), Vector2(39.5, 16.5)), "line on the near side is clear")
	check(Damage.line_clear(w, Vector2(43.5, 12.5), Vector2(41.5, 3.5)), "line on the far side is clear")


# ---------------------------------------------------------------- concealment
func _ids(arr: Array) -> Array:
	var out := []
	for e in arr:
		out.append(int(e.id))
	return out


func test_forest_infantry_concealed_until_it_fires() -> void:
	var w := _world()
	_arena(w)
	_paint(w, Rect2i(48, 7, 6, 7), Terrain.FOREST)
	var hid := _spawn(w, "rifleman", 1, Vector2i(50, 10))
	do_cmd(w, 1, {"type": "hold", "unit_ids": [hid]})
	var recon := _spawn(w, "recon", 0, Vector2i(41, 10))    # 9 tiles away, sight 12
	for i in 8:
		w.step()
	var h: Dictionary = w.entities[hid]
	check(Fog.is_visible(w, 0, h.pos), "the forest cell itself is inside fid 0's sight")
	check(not _ids(w.visible_enemies(0)).has(hid), "concealed forest unit not in visible_enemies beyond concealment_range")
	check(not Fog.entity_visible(w, 0, h), "concealed forest unit not entity_visible")
	check_eq(int(w.entities[recon].target), -1, "recon did not acquire the concealed unit")
	# a bait unit outside concealment range (6 tiles) but inside rifle range: the hidden unit fires
	var bait := _spawn(w, "engineer", 0, Vector2i(44, 10))
	var fired := false
	for i in 200:
		w.step()
		if _count(w.events, "ShotFired", "shooter", hid) > 0:
			fired = true
			break
	check(fired, "hidden rifleman fired at the bait (%.2f tiles)" % w.entities[bait].pos.distance_to(h.pos))
	check(_ids(w.visible_enemies(0)).has(hid), "after firing it is in visible_enemies")
	# a spotter inside concealment_range reveals it without firing
	var w2 := _world()
	_arena(w2)
	_paint(w2, Rect2i(48, 7, 6, 7), Terrain.FOREST)
	var hid2 := _spawn(w2, "rifleman", 1, Vector2i(50, 10))
	do_cmd(w2, 1, {"type": "stop", "unit_ids": [hid2]})
	_spawn(w2, "recon", 0, Vector2i(46, 10))   # 4 tiles
	for i in 4:
		w2.step()
	check(Fog.entity_visible(w2, 0, w2.entities[hid2]), "spotter within concealment_range sees the forest unit")


# ---------------------------------------------------------------- determinism / save
## A mixed squad fight across a forest patch, both sides attack-moving at each other.
func _fight() -> SimWorld:
	var w := _world()
	_arena(w)
	_paint(w, Rect2i(45, 4, 4, 8), Terrain.FOREST)
	var sides := [[0, 30, 64.5, 501], [1, 61, 30.5, 502]]
	for sd in sides:
		var fid: int = sd[0]
		var x0: int = sd[1]
		var ids := []
		for i in 8:
			var id := _spawn(w, "rifleman", fid, Vector2i(x0 + i % 3, 6 + i / 3 * 2))
			w.entities[id].squad = int(sd[3])
			ids.append(id)
		ids.append(_spawn(w, "at_gunner", fid, Vector2i(x0, 14)))
		ids.append(_spawn(w, "at_gunner", fid, Vector2i(x0 + 1, 14)))
		ids.append(_spawn(w, "mbt", fid, Vector2i(x0 + 2, 17)))
		ids.append(_spawn(w, "ifv", fid, Vector2i(x0, 20)))
		do_cmd(w, fid, {"type": "attack_move", "unit_ids": ids, "target": Vector2(float(sd[2]), 11.5)})
	return w


func test_determinism_two_identical_fights_hash_equal() -> void:
	var a := _fight()
	var b := _fight()
	var dmg := 0
	var supp_seen := false
	for i in 600:
		a.step()
		b.step()
		dmg += _count(a.events, "Damage")
		for e in a.units_of(0) + a.units_of(1):
			if float(e.get("supp", 0.0)) > 0.0:
				supp_seen = true
	check(dmg > 20, "the fight exercised the damage pipeline (%d Damage events)" % dmg)
	check(supp_seen, "suppression occurred during the fight")
	check_eq(a.state_hash(), b.state_hash(), "identical 600-tick fights give equal state_hash")


func test_save_round_trip_mid_fight() -> void:
	var a := _fight()
	for i in 300:
		a.step()
	var b := SimWorld.from_dict(bytes_to_var(var_to_bytes(a.to_dict())))
	check_eq(b.state_hash(), a.state_hash(), "hash equal right after load")
	for i in 200:
		a.step()
		b.step()
	check_eq(b.state_hash(), a.state_hash(), "hash equal after 200 more ticks")
