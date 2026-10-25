extends "res://tests/test_base.gd"
## G6 acceptance (owner: MECH6b). CONTRACTS_G6 section 10, section 17: Machine specials.

const MachineG6 = preload("res://sim/systems/machine_g6.gd")
const HotState = preload("res://sim/hot_state.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const Movement = preload("res://sim/systems/movement.gd")
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")


## Machine (fid 0, team 0) vs Human A (fid 1, team 1), no AI.
func _mw() -> SimWorld:
	return make_world({"sides": [
		{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 0},
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "A", "team": 1}]})


## An open cell (r-cell square passable for vehicles) near the map centre.
func _open(w: SimWorld, r: int = 5) -> Vector2i:
	var near := Vector2i(int(w.map.w) / 2, int(w.map.h) / 2)
	for rad in range(0, 48):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var c := near + Vector2i(dx, dy)
				if _clear(w, c, r):
					return c
	return near


func _clear(w: SimWorld, c: Vector2i, r: int) -> bool:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var cc := c + Vector2i(x, y)
			if not w.in_bounds(cc) or not Movement.is_passable(w, cc, "vehicle"):
				return false
	return true


func _unit(w: SimWorld, def_id: String, fid: int, p: Vector2) -> Dictionary:
	var id := w.spawn_unit(def_id, fid, p)
	HotState.touch(w, id)
	return w.entities[id]


func _hp(w: SimWorld, e: Dictionary, v: float) -> void:
	if e.kind == "unit":
		HotState.set_hp(w, int(e.id), v)
	else:
		e.hp = v


func _run(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()


func _kids(w: SimWorld, pid: int) -> Array:
	var out := []
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and int(e.get("air_parent", -1)) == pid:
			out.append(e)
	return out


func test_nanite_wall_regrows() -> void:
	var w := _mw()
	var c := _open(w)
	var wall: Dictionary = w.entities[w.spawn_building("m_nanite_wall", 0, c, true)]
	w.step()
	check(int(w.factions[0].power_prod) >= int(w.factions[0].power_use), "machine side powered at start")
	_hp(w, wall, 800.0)
	_run(w, 40)
	var hp1 := float(wall.hp)
	check(hp1 >= 812.0 and hp1 <= 820.0, "nanite wall regrew ~8 hp/s over 2 s (hp %.2f)" % hp1)
	_hp(w, wall, 1599.0)
	_run(w, 20)
	check_eq(float(wall.hp), 1600.0, "regrowth stops at max hp")
	# unpowered: no regrowth
	for i in 3:
		w.spawn_building("m_overmind", 0, c + Vector2i(-4 + i * 3, 4), true)
	w.step()
	check(int(w.factions[0].power_use) > int(w.factions[0].power_prod), "machine side now short of power")
	_hp(w, wall, 900.0)
	_run(w, 40)
	check_eq(float(wall.hp), 900.0, "no regrowth while unpowered")


func test_nanite_forge_heals_out_of_combat() -> void:
	var w := _mw()
	var c := _open(w)
	w.spawn_building("m_charging_hub", 0, c + Vector2i(-4, -4), true)
	var forge: Dictionary = w.entities[w.spawn_building("m_nanite_forge", 0, c, true)]
	var calm := _unit(w, "m_tracked", 0, forge.pos + Vector2(3, 0))
	var hot := _unit(w, "m_tracked", 0, forge.pos + Vector2(0, 3))
	var far := _unit(w, "m_tracked", 0, forge.pos + Vector2(14, 0))
	var foe := _unit(w, "a_ew_truck", 1, forge.pos + Vector2(-10, -6))   # in radius, out of weapon range: never healed
	w.step()
	for u in [calm, hot, far, foe]:
		_hp(w, u, 300.0)
	hot.last_hit_tick = w.tick
	_run(w, 40)
	check(float(calm.hp) >= 307.0 and float(calm.hp) <= 309.0, "out-of-combat unit healed ~4 hp/s (hp %.2f)" % float(calm.hp))
	check_eq(float(hot.hp), 300.0, "unit hit within the combat window is not healed")
	check_eq(float(far.hp), 300.0, "unit outside radius 12 is not healed")
	check_eq(float(foe.hp), 300.0, "enemy unit is not healed")


func test_repair_swarm2_heals_in_combat() -> void:
	var w := _mw()
	var c := _open(w)
	var p := Vector2(c) + Vector2(0.5, 0.5)
	var sw := _unit(w, "m_repair_swarm2", 0, p)
	var near := _unit(w, "m_tracked", 0, p + Vector2(3, 0))
	var far := _unit(w, "m_tracked", 0, p + Vector2(8, 0))
	w.step()
	_hp(w, near, 300.0)
	_hp(w, far, 300.0)
	var t0 := w.tick
	for i in 20:
		near.last_hit_tick = w.tick   # under fire the whole time
		w.step()
	check(w.tick - int(near.last_hit_tick) <= 1 and w.tick > t0, "unit stayed in combat")
	check(float(near.hp) >= 309.0 and float(near.hp) <= 311.0, "repair swarm II healed ~10 hp/s in combat (hp %.2f)" % float(near.hp))
	check_eq(float(far.hp), 300.0, "unit outside radius 5 is not healed")
	check(w.entities.has(int(sw.id)), "swarm alive")


func _wreck_of(w: SimWorld, def_id: String) -> Dictionary:
	for r in MachineG6.wrecks(w):
		if String(r.def) == def_id:
			return r
	return {}


func _assimilate(w: SimWorld, aid: int, wid: int) -> Dictionary:
	do_cmd(w, 0, {"type": "assimilate", "unit_id": aid, "wreck_id": wid})
	for i in 600:
		w.step()
		for ev in w.events:
			if ev.type == "WreckAssimilated":
				return ev.data if ev.has("data") else ev
	return {}


func test_assimilate_wreck_spawns_unit() -> void:
	var w := _mw()
	var c := _open(w)
	var p := Vector2(c) + Vector2(0.5, 0.5)
	var light := _unit(w, "a_ew_truck", 1, p + Vector2(5, 0))
	var heavy := _unit(w, "a_old_tank", 1, p + Vector2(0, 5))
	w.step()
	w.destroy(int(light.id), "test")
	w.destroy(int(heavy.id), "test")
	var lw := _wreck_of(w, "a_ew_truck")
	var hw := _wreck_of(w, "a_old_tank")
	check(not lw.is_empty() and String(lw.get("cls", "")) == "light", "light wreck registered (%s)" % str(lw))
	check(not hw.is_empty() and String(hw.get("cls", "")) == "heavy", "heavy wreck registered (%s)" % str(hw))
	var asm := _unit(w, "m_assimilator", 0, p)
	var other := _unit(w, "m_tracked", 0, p + Vector2(-2, 0))
	w.step()
	var bad := do_cmd(w, 0, {"type": "assimilate", "unit_id": int(other.id), "wreck_id": int(lw.id)})
	check(rejected_reason(bad).contains("Assimilator"), "non-assimilator rejected: %s" % rejected_reason(bad))
	var ev := _assimilate(w, int(asm.id), int(lw.id))
	check(not ev.is_empty(), "light wreck assimilated within 30 s")
	if ev.is_empty():
		return
	check(not w.entities.has(int(lw.id)), "light wreck consumed")
	var su = w.entities.get(int(ev.spawned))
	check(su != null and String(su.def) == "m_scout_crawler" and int(su.owner) == 0, "light wreck -> own crawler")
	var ev2 := _assimilate(w, int(asm.id), int(hw.id))
	check(not ev2.is_empty(), "heavy wreck assimilated")
	if not ev2.is_empty():
		var su2 = w.entities.get(int(ev2.spawned))
		check(su2 != null and String(su2.def) == "m_tracked" and int(su2.owner) == 0, "heavy wreck -> own tracked platform")
	check_eq(int(w.sys_state.machine_g6.assimilated), 2, "assimilated count saved")


func test_hive_node_spawns_to_cap() -> void:
	var w := _mw()
	var c := _open(w)
	w.spawn_building("m_charging_hub", 0, c + Vector2i(-4, -4), true)
	var hive: Dictionary = w.entities[w.spawn_building("m_hive_node", 0, c, true)]
	var iv := roundi(12.0 * SimWorld.TICK_RATE)
	_run(w, iv + 2)
	var k := _kids(w, int(hive.id))
	check_eq(k.size(), 1, "one micro drone after one 12 s interval")
	if k.size() > 0:
		check_eq(String(k[0].def), "m_micro_drone", "hive spawns m_micro_drone")
	# keep the drones alive (their own life timer is Air's) to test the cap of 6
	var peak := 0
	for i in iv * 7:
		for e in _kids(w, int(hive.id)):
			e.air_life = 999.0
		w.step()
		peak = maxi(peak, _kids(w, int(hive.id)).size())
	check_eq(peak, 6, "hive node spawns up to its cap of 6 and no further")
	var ks := _kids(w, int(hive.id))
	w.destroy(int(ks[0].id), "test")
	for i in iv + 2:
		for e in _kids(w, int(hive.id)):
			e.air_life = 999.0
		w.step()
	check_eq(_kids(w, int(hive.id)).size(), 6, "a lost drone is replaced after one interval")


func test_swarm_queen_spawns_while_alive() -> void:
	var w := _mw()
	var c := _open(w)
	var q := _unit(w, "m_swarm_queen", 0, Vector2(c) + Vector2(0.5, 0.5))
	_run(w, roundi(6.0 * SimWorld.TICK_RATE) * 2 + 4)
	var n := _kids(w, int(q.id)).size()
	check(n >= 1, "swarm queen spawned micro drones while alive (%d)" % n)
	w.destroy(int(q.id), "test")
	var spawned := 0
	for i in roundi(6.0 * SimWorld.TICK_RATE) * 2:
		w.step()
		for ev in w.events:
			if ev.type == "EntitySpawned" and String(ev.def) == "m_micro_drone":
				spawned += 1
	check_eq(spawned, 0, "no spawns once the queen is gone")


func test_mimic_disguise_until_3_tiles() -> void:
	var w := _mw()
	var c := _open(w)
	var p := Vector2(c) + Vector2(0.5, 0.5)
	var m := _unit(w, "m_mimic_drone", 0, p)
	var obs := _unit(w, "a_ew_truck", 1, p + Vector2(6, 0))
	_run(w, 10)
	check_eq(MachineG6.disguise_for(w, 1, m), "a_drone_recon", "Human A sees a Human A drone at 6 tiles")
	check_eq(MachineG6.disguise_for(w, 0, m), "", "owner sees the real mimic")
	check_eq(MachineG6.disguise_for(w, 0, obs), "", "non-mimic units are never disguised")
	HotState.set_pos(w, int(obs.id), Vector2(m.pos) + Vector2(2.5, 0))
	_run(w, 10)
	check(Vector2(obs.pos).distance_to(Vector2(m.pos)) <= 3.0, "observer within 3 tiles")
	check_eq(MachineG6.disguise_for(w, 1, m), "", "disguise drops within 3 tiles")
	HotState.set_pos(w, int(obs.id), Vector2(m.pos) + Vector2(8, 0))
	_run(w, 10)
	check_eq(MachineG6.disguise_for(w, 1, m), "a_drone_recon", "disguise returns once the observer leaves")


func test_stalker_cloak_when_still() -> void:
	var w := _mw()
	var c := _open(w, 7)
	var p := Vector2(c) + Vector2(0.5, 0.5)
	var s := _unit(w, "m_stalker_synth", 0, p)
	var obs := _unit(w, "a_ew_truck", 1, p + Vector2(12, 0))
	w.step()
	check(MachineG6.cloak_visible(w, 1, s), "visible before cloaking")
	var bad := do_cmd(w, 0, {"type": "cloak", "unit_ids": [int(obs.id)], "on": true})
	check(rejected_reason(bad) != "", "cannot cloak an enemy unit")
	do_cmd(w, 0, {"type": "cloak", "unit_ids": [int(s.id)], "on": true})
	check(bool(s.get("cloaked", false)), "cloak on")
	_run(w, 30)
	check(not MachineG6.cloak_visible(w, 1, s), "cloaked stalker hidden from the enemy when still")
	check(not G6Hooks.visible_to(w, 1, s), "hidden through G6Hooks.visible_to")
	check(MachineG6.cloak_visible(w, 0, s), "always visible to its owner")
	do_cmd(w, 0, {"type": "move", "unit_ids": [int(s.id)], "target": p + Vector2(0, 4)})
	_run(w, 3)
	check(bool(s.moving) and MachineG6.cloak_visible(w, 1, s), "visible while moving")
	_run(w, 80)
	check(not bool(s.moving) and not MachineG6.cloak_visible(w, 1, s), "hidden again once still")
	HotState.set_pos(w, int(obs.id), Vector2(s.pos) + Vector2(1.5, 0))
	_run(w, 2)
	check(MachineG6.cloak_visible(w, 1, s), "detected by an enemy within 2 tiles")
	HotState.set_pos(w, int(obs.id), Vector2(s.pos) + Vector2(14, 0))
	_run(w, 2)
	do_cmd(w, 0, {"type": "cloak", "unit_ids": [int(s.id)], "on": false})
	_run(w, 30)
	check(MachineG6.cloak_visible(w, 1, s), "visible with the cloak off")


func test_shield_drone_halves_small_arms() -> void:
	var w := _mw()
	var c := _open(w)
	var p := Vector2(c) + Vector2(0.5, 0.5)
	var d := _unit(w, "m_shield_drone", 0, p)
	d.facing = 0.0
	var front := _unit(w, "m_tracked", 0, p + Vector2(2, 0))
	var back := _unit(w, "m_tracked", 0, p + Vector2(-2, 0))
	var outr := _unit(w, "m_tracked", 0, p + Vector2(5, 0))
	var foe := _unit(w, "m_tracked", 1, p + Vector2(2, 1))
	var src := _unit(w, "a_old_tank", 1, p + Vector2(9, 0))
	var sa := {"cls": "small_arms", "damage": 10.0}
	var art := {"cls": "artillery", "damage": 10.0}
	check_eq(MachineG6.shield_mult(w, src, sa, front), 0.5, "friendly in the front arc: small arms x0.5")
	check_eq(MachineG6.shield_mult(w, src, art, front), 1.0, "artillery is not shielded")
	check_eq(MachineG6.shield_mult(w, src, sa, back), 1.0, "behind the drone: no shield")
	check_eq(MachineG6.shield_mult(w, src, sa, outr), 1.0, "beyond 4 tiles: no shield")
	check_eq(MachineG6.shield_mult(w, src, sa, foe), 1.0, "enemies are not shielded")
	var with_d := G6Hooks.damage_mult(w, src, sa, front)
	w.destroy(int(d.id), "test")
	w.step()
	var without := G6Hooks.damage_mult(w, src, sa, front)
	check(without > 0.0 and absf(with_d / without - 0.5) < 0.0001, "G6Hooks.damage_mult halves with the drone (%.3f vs %.3f)" % [with_d, without])
	check_eq(MachineG6.shield_mult(w, src, sa, front), 1.0, "no shield once the drone is gone")


func test_relay_lattice_extends_range() -> void:
	var w := _mw()
	var base: Dictionary = w.buildings_of(0)[0]
	var bp: Vector2 = base.pos
	var ctr := Vector2(float(w.map.w) * 0.5, float(w.map.h) * 0.5)
	var dir := (ctr - bp).normalized()
	var a_cell := Vector2i((bp + dir * 18.0).floor())
	var a: Dictionary = w.entities[w.spawn_building("m_relay_lattice", 0, a_cell, true)]
	var b_cell := Vector2i((Vector2(a.pos) + dir * 28.0).floor())
	check(w.in_bounds(b_cell), "relay B in bounds")
	var b: Dictionary = w.entities[w.spawn_building("m_relay_lattice", 0, b_cell, true)]
	w.step()
	var chain := MachineG6.relay_chain(w, 0)
	check(chain.has(int(a.id)) and chain.has(int(b.id)), "A links to the base, B links through A (%s)" % str(chain))
	var x := Vector2(a.pos) + dir * 26.0
	var near_other := false
	for o in w.buildings_of(0):
		if int(o.id) != int(a.id) and int(o.id) != int(b.id) and x.distance_to(Vector2(o.pos)) <= 20.0:
			near_other = true
	check(not near_other, "test point is beyond the 20-tile base rule")
	check(MachineG6.relay_covers(w, 0, Vector2(b.pos) + dir * 27.0), "linked relay B extends build range to 30 tiles")
	check(not MachineG6.relay_covers(w, 0, Vector2(b.pos) + dir * 32.0), "not beyond 30 tiles of a relay")
	check(not MachineG6.relay_covers(w, 1, Vector2(b.pos)), "relays never cover the enemy")
	check(MachineG6.relay_power_covers(w, 0, Vector2(b.pos) + dir * 9.0), "relay power range 10")
	w.destroy(int(a.id), "test")
	w.step()
	check(not MachineG6.relay_chain(w, 0).has(int(b.id)), "B unlinked once A is gone")
	check(not MachineG6.relay_covers(w, 0, Vector2(b.pos) + dir * 27.0), "unlinked relay extends nothing")


func test_phase_gate_team_only() -> void:
	var w := _mw()
	var c := _open(w)
	var g: Dictionary = w.entities[w.spawn_building("m_phase_gate", 0, c, true)]
	w.step()
	var ga := Movement.gate_at(w, c)
	check(not ga.is_empty() and int(ga.team) == 0, "phase gate registered as a team-0 gate (%s)" % str(ga))
	check(Movement.is_passable(w, c, "foot", 0), "own team passes")
	check(Movement.is_passable(w, c, "vehicle", 0), "own vehicles pass")
	check(not Movement.is_passable(w, c, "foot", 1), "enemy team blocked")
	check(MachineG6.phase_gate_open(w, g, 0) and not MachineG6.phase_gate_open(w, g, 1), "phase_gate_open is team-only")


## Not a skeleton item: Machine-special state (entity fields + sys_state.machine_g6) survives save/load.
func test_machine_save_load_continuity() -> void:
	var w := _mw()
	var c := _open(w)
	var p := Vector2(c) + Vector2(0.5, 0.5)
	w.spawn_building("m_charging_hub", 0, c + Vector2i(-4, -4), true)
	w.spawn_building("m_hive_node", 0, c + Vector2i(3, 3), true)
	var st := _unit(w, "m_stalker_synth", 0, p + Vector2(-3, 0))
	var asm := _unit(w, "m_assimilator", 0, p)
	var tr := _unit(w, "a_ew_truck", 1, p + Vector2(4, -2))
	w.step()
	w.destroy(int(tr.id), "test")
	var wr := _wreck_of(w, "a_ew_truck")
	do_cmd(w, 0, {"type": "cloak", "unit_ids": [int(st.id)], "on": true})
	do_cmd(w, 0, {"type": "assimilate", "unit_id": int(asm.id), "wreck_id": int(wr.id)})
	for i in 150:
		w.step()
	check(asm.has("assim") and bool(st.get("cloak_hid", false)), "mid-assimilation, stalker hidden")
	var w2 := SimWorld.from_dict(SaveSystem.decode_bytes(SaveSystem.encode_dict(w.to_dict())).dict)
	check_eq(w2.state_hash(), w.state_hash(), "hash equal right after load")
	for i in 300:
		w.step()
		w2.step()
	check_eq(w2.state_hash(), w.state_hash(), "same hash 300 ticks after a mid-action load")
	check_eq(int(w2.sys_state.machine_g6.assimilated), 1, "assimilation finished after the load")
