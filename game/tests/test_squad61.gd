extends "res://tests/test_base.gd"
## G6.1 SQUAD61: squads fight as one unit, smart soldiers, stances, regroup, new formations, paced moves.
## make_world() gives an inert side 1; units are spawned directly and grouped by setting e.squad.

const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")
const SquadAI = preload("res://sim/systems/squad_ai.gd")
const Orders = preload("res://sim/systems/orders.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const C := Vector2(0.5, 0.5)


func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 26):
		for x in range(22, 74):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	return w


func _spawn(w: SimWorld, def: String, fid: int, cell: Vector2i, squad := -1) -> int:
	var mc: String = Movement.udef(def).mc
	var id := w.spawn_unit(def, fid, Vector2(Movement.nearest_free_cell(w, cell, mc)) + C)
	if squad >= 0:
		w.entities[id].squad = squad
	SquadAI.touch(w)
	return id


func _run(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()


func _squad(w: SimWorld, defs: Array, fid: int, at: Vector2i, sq: int) -> Array:
	var ids := []
	for k in defs.size():
		ids.append(_spawn(w, String(defs[k]), fid, at + Vector2i(k, 0), sq))
	return ids


func test_focus_fire_squad_shares_the_leader_target() -> void:
	var w := _world()
	var ids := _squad(w, ["rifleman", "rifleman", "rifleman", "rifleman"], 0, Vector2i(30, 10), 9001)
	_spawn(w, "rifleman", 1, Vector2i(29, 15))
	_spawn(w, "rifleman", 1, Vector2i(35, 15))
	var best := 0
	for i in 60:
		w.step()
		var le: Dictionary = w.entities.get(SquadAI.leader_of(w, SquadAI.squad_members(w, 9001)), {})
		if le.is_empty() or int(le.target) < 0:
			continue
		var n := 0
		for id in ids:
			if w.entities.has(id) and int(w.entities[id].target) == int(le.target):
				n += 1
		best = maxi(best, n)
	check(best >= 3, "at least 3 of 4 squad members fire at the leader's target (best %d)" % best)


func test_return_fire_whole_squad_reacts_within_2s() -> void:
	var w := _world()
	var ids := _squad(w, ["rifleman", "rifleman", "rifleman"], 0, Vector2i(30, 5), 9002)
	var en := _spawn(w, "rifleman", 1, Vector2i(31, 20))
	w.entities[en].order = {"type": "hold_fire"}
	_run(w, 2)
	var hit: Dictionary = w.entities[ids[0]]
	hit.last_attacker = en
	hit.last_hit_tick = w.tick
	var ok := {}
	for i in 40:
		w.step()
		for id in ids:
			var e: Dictionary = w.entities[id]
			if int(e.target) == en or String(e.order.get("sq", "")) == "support" or bool(e.moving):
				ok[id] = true
	check_eq(ok.size(), ids.size(), "every squad member targets the attacker or moves up to support within 2 s")


func test_leash_straggler_rejoins_leader() -> void:
	var w := _world()
	var ids := _squad(w, ["rifleman", "rifleman", "rifleman", "rifleman"], 0, Vector2i(40, 10), 9003)
	var far: Dictionary = w.entities[ids[3]]
	far.pos = Vector2(Movement.nearest_free_cell(w, Vector2i(58, 10), "foot")) + C
	_run(w, 400)
	var lp: Vector2 = w.entities[SquadAI.leader_of(w, SquadAI.squad_members(w, 9003))].pos
	var worst := 0.0
	for id in ids:
		worst = maxf(worst, Vector2(w.entities[id].pos).distance_to(lp))
	check(worst <= SquadAI.LEASH + 0.5, "no member further than the leash from its leader (worst %.2f)" % worst)


func test_leash_after_a_group_move() -> void:
	var w := _world()
	var ids := _squad(w, ["rifleman", "rifleman", "rifleman", "rifleman", "rifleman"], 0, Vector2i(30, 12), 9004)
	do_cmd(w, 0, {"type": "move", "unit_ids": ids, "target": Vector2(55.5, 12.5)})
	_run(w, 500)
	var lp: Vector2 = w.entities[SquadAI.leader_of(w, SquadAI.squad_members(w, 9004))].pos
	for id in ids:
		check(Vector2(w.entities[id].pos).distance_to(lp) <= SquadAI.LEASH, "member %d within the leash after the move" % id)


func test_hold_position_never_moves() -> void:
	var w := _world()
	var ids := _squad(w, ["rifleman", "rifleman"], 0, Vector2i(40, 10), 9005)
	do_cmd(w, 0, {"type": "set_stance", "unit_ids": ids, "stance": "hold_position"})
	var p0: Vector2 = w.entities[ids[0]].pos
	var p1: Vector2 = w.entities[ids[1]].pos
	_spawn(w, "rifleman", 1, Vector2i(40, 18))
	w.entities[ids[0]].hp = 20.0   # low HP would normally fall back
	w.entities[ids[0]].last_hit_tick = w.tick
	_run(w, 200)
	check(not w.entities.has(ids[0]) or Vector2(w.entities[ids[0]].pos).distance_to(p0) < 0.01, "hold position: low-HP member never moved")
	check(not w.entities.has(ids[1]) or Vector2(w.entities[ids[1]].pos).distance_to(p1) < 0.01, "hold position: member never moved")
	do_cmd(w, 0, {"type": "regroup", "unit_ids": ids})
	_run(w, 40)
	check(not w.entities.has(ids[1]) or Vector2(w.entities[ids[1]].pos).distance_to(p1) < 0.01, "regroup does not move a hold-position unit")


func test_hold_fire_does_not_shoot_unprovoked() -> void:
	var w := _world()
	var a := _spawn(w, "rifleman", 0, Vector2i(40, 10), 9006)
	var b := _spawn(w, "rifleman", 0, Vector2i(41, 10), 9006)
	do_cmd(w, 0, {"type": "set_stance", "unit_ids": [a, b], "stance": "hold_fire"})
	var en := _spawn(w, "rifleman", 1, Vector2i(40, 13))
	w.entities[en].order = {"type": "hold_fire"}
	_run(w, 120)
	check_eq(float(w.entities[en].hp), float(w.entities[en].max_hp), "hold fire: the passive enemy in range was never shot")
	check_eq(String(w.entities[a].order.type), "hold_fire", "hold-fire unit carries the hold_fire order")


func test_at_gunner_prefers_vehicles() -> void:
	var w := _world()
	var ids := _squad(w, ["rifleman", "at_gunner", "rifleman"], 0, Vector2i(40, 10), 9007)
	_spawn(w, "rifleman", 1, Vector2i(41, 14))
	_spawn(w, "ifv", 1, Vector2i(44, 15))
	var on_veh := false
	for i in 120:
		w.step()
		if not w.entities.has(ids[1]):
			break
		var t = w.entities.get(int(w.entities[ids[1]].target))
		if t != null and String(Combat.stats(t).armor) != "infantry":
			on_veh = true
			break
	check(on_veh, "the AT gunner switches to the enemy vehicle")


func test_low_hp_member_falls_back() -> void:
	var w := _world()
	var ids := _squad(w, ["rifleman", "rifleman", "rifleman"], 0, Vector2i(40, 10), 9008)
	var en := _spawn(w, "rifleman", 1, Vector2i(40, 15))
	w.entities[en].order = {"type": "hold_fire"}
	var e: Dictionary = w.entities[ids[0]]
	e.hp = float(e.max_hp) * 0.2
	e.last_attacker = en
	e.last_hit_tick = w.tick
	var p0: Vector2 = e.pos
	var fell := false
	for i in 30:
		w.step()
		e.last_hit_tick = w.tick
		if String(e.order.get("sq", "")) == "fallback":
			fell = true
	_run(w, 60)
	check(fell, "the low-HP member got a fallback move")
	check(Vector2(e.pos).distance_to(Vector2(w.entities[en].pos)) > p0.distance_to(Vector2(w.entities[en].pos)), "it moved away from the threat")


func test_new_formations_give_distinct_slots() -> void:
	var w := _world()
	var units := []
	for k in 7:
		units.append(w.entities[_spawn(w, "rifleman", 0, Vector2i(30 + k, 20))])
	var target := Vector2(50.5, 10.5)
	var shapes := {}
	for form in ["line", "wedge", "column", "box", "echelon_left", "echelon_right", "file", "spread"]:
		for u in units:
			u.formation = form
		var slots := Movement.formation_slots(w, units, target)
		var ok := slots.size() == units.size()
		for i in slots.size():
			for j in range(i + 1, slots.size()):
				if Vector2(slots[i]).distance_to(slots[j]) < 0.9:
					ok = false
		check(ok, "%s: %d slots, none closer than 0.9 tiles" % [form, slots.size()])
		shapes[str(slots)] = form
	check_eq(shapes.size(), 8, "the 8 formations give 8 different slot sets")
	# mixed selection: armour in front of the infantry
	var mbt: Dictionary = w.entities[_spawn(w, "mbt", 0, Vector2i(30, 23))]
	var mixed: Array = units.slice(0, 3) + [mbt]
	for u in mixed:
		u.formation = "line"
	var ms := Movement.formation_slots(w, mixed, target)
	var cen := Vector2.ZERO
	for u in mixed:
		cen += Vector2(u.pos)
	var fwd := (target - cen / 4.0).normalized()
	for k in 3:
		check(Vector2(ms[3]).dot(fwd) > Vector2(ms[k]).dot(fwd), "the tank's slot is ahead of infantry slot %d" % k)


func test_player_order_is_not_overridden() -> void:
	var w := _world()
	var ids := _squad(w, ["rifleman", "rifleman", "rifleman"], 0, Vector2i(30, 10), 9009)
	var goal := Vector2(50.5, 20.5)
	do_cmd(w, 0, {"type": "move", "unit_ids": [ids[2]], "target": goal})
	var e: Dictionary = w.entities[ids[2]]
	check(e.has("sq_pt"), "world.gd stamps the player's direct order (SquadAI.on_direct_order)")
	_run(w, 360)
	check(Vector2(e.pos).distance_to(goal) < 2.0, "the member the player sent away stays where the player sent it (%.1f)" % Vector2(e.pos).distance_to(goal))


func test_paced_group_waits_for_the_slowest() -> void:
	var w := _world()
	var fast := _spawn(w, "recon", 0, Vector2i(30, 8))
	var slow := _spawn(w, "rifleman", 0, Vector2i(30, 9))
	do_cmd(w, 0, {"type": "set_formation", "unit_ids": [fast, slow], "pace": true})
	check(w.entities[fast].has("pace_grp"), "pace flag set")
	do_cmd(w, 0, {"type": "move", "unit_ids": [fast, slow], "target": Vector2(60.5, 8.5)})
	var worst := 0.0
	for i in 200:
		w.step()
		var df: float = Vector2(w.entities[fast].pos).distance_to(Vector2(60.5, 8.5))
		var ds: float = Vector2(w.entities[slow].pos).distance_to(Vector2(60.5, 8.5))
		worst = maxf(worst, ds - df)
	check(worst < 6.0, "the faster unit never gets far ahead of the slowest (max lead %.1f)" % worst)


func _brawl() -> SimWorld:
	var w := _world()
	_squad(w, ["rifleman", "rifleman", "at_gunner", "rifleman"], 0, Vector2i(30, 8), 9100)
	_squad(w, ["rifleman", "rifleman", "rifleman"], 0, Vector2i(30, 12), 9101)
	_squad(w, ["b_militia", "b_militia", "b_heavy_rifle"], 1, Vector2i(42, 9), 9200)
	_spawn(w, "b_carrier", 1, Vector2i(46, 11))
	var ids := SquadAI.squad_members(w, 9101)
	SquadAI.set_stance_internal(w, ids, "aggressive")
	return w


func test_determinism_and_save_load() -> void:
	var a := _brawl()
	var b := _brawl()
	_run(a, 300)
	_run(b, 300)
	check_eq(a.state_hash(), b.state_hash(), "same setup, same hash at 300")
	var path := "user://test_squad61/mid.sav"
	DirAccess.make_dir_recursive_absolute("user://test_squad61")
	check_eq(SaveSystem.save(a, path), "", "save ok")
	var l: SimWorld = SaveSystem.load(path)
	if not check(l != null, "loaded"):
		return
	check_eq(l.state_hash(), a.state_hash(), "hash equal after load")
	_run(a, 300)
	_run(l, 300)
	check_eq(l.state_hash(), a.state_hash(), "hash equal at 600 after save/load at 300")
	DirAccess.remove_absolute(path)


func test_squad_state_api() -> void:
	var w := _world()
	var ids := _squad(w, ["rifleman", "rifleman"], 0, Vector2i(30, 10), 9300)
	var st := SquadAI.squad_state(w, 9300)
	check_eq(int(st.get("alive", 0)), 2, "squad_state counts members")
	check_eq(int(st.get("leader", -1)), int(ids[0]), "lowest id leads")
	check(SquadAI.squad_state(w, 777777).is_empty(), "unknown squad -> {}")
	var ev := do_cmd(w, 0, {"type": "set_stance", "unit_ids": ids, "stance": "bogus"})
	check(rejected_reason(ev) != "", "a bad stance is rejected")


func test_echelon_alias_and_formation_spacing() -> void:
	var w := _world()
	var ids := []
	var units := []
	for k in 5:
		ids.append(_spawn(w, "rifleman", 0, Vector2i(30 + k, 20)))
		units.append(w.entities[ids[k]])
	check(Orders.FORMATIONS.has("echelon"), "Orders.FORMATIONS accepts the OFF61 'echelon' alias")
	do_cmd(w, 0, {"type": "set_formation", "unit_ids": ids, "formation": "echelon"})
	check_eq(String(units[0].get("formation", "")), "echelon_right", "'echelon' resolves to echelon_right")
	var target := Vector2(50.5, 10.5)
	var a := Movement.formation_slots(w, units, target)
	do_cmd(w, 0, {"type": "set_formation", "unit_ids": ids, "spacing": 1.8})
	check(absf(float(units[0].get("formation_spacing", 1.0)) - 1.8) < 0.001, "spacing 1.8 stored on e.formation_spacing")
	check_eq(String(units[0].get("formation", "")), "echelon_right", "spacing alone keeps the formation")
	var b := Movement.formation_slots(w, units, target)
	var da := Vector2(a[0]).distance_to(a[4])
	var db := Vector2(b[0]).distance_to(b[4])
	check(db > da * 1.7, "slots widen with the spacing (%.2f -> %.2f)" % [da, db])
	w.submit({"type": "set_formation", "unit_ids": ids, "spacing": 3.5, "issuer": 0})
	w.step()
	check(rejected_reason(w.events) != "", "spacing 3.5 is rejected with a reason")
	check(absf(float(units[0].get("formation_spacing", 1.0)) - 1.8) < 0.001, "out-of-range spacing is rejected")
	do_cmd(w, 0, {"type": "set_formation", "unit_ids": ids, "spacing": 1.0})
	check(not units[0].has("formation_spacing"), "spacing 1.0 restores the default (field erased)")
