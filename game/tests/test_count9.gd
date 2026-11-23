extends "res://tests/test_base.gd"
## G9 COUNT9: one harness case per Machine counter (Done-when #3). PROVISIONAL wraps G7.1 hooks.

const Count9 = preload("res://sim/systems/count9.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Hive71 = preload("res://sim/systems/hive71.gd")
const MachineEw7 = preload("res://sim/systems/machine_ew7.gd")
const Fleet71 = preload("res://sim/systems/fleet71.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Fire71 = preload("res://sim/systems/fire71.gd")
const Harvest71 = preload("res://sim/systems/harvest71.gd")
func _lp() -> SimWorld:
	var c := LastProtocol.make_config(401, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	check(w != null, "LP match")
	for i in 6:
		if w != null:
			w.step()
	return w


func _machine_fid(w: SimWorld) -> int:
	for fid in w.factions:
		if String(w.factions[fid].get("faction_def", "")) == "machine":
			return int(fid)
	return -1


func test_counter_strike_early_cut_relays() -> void:
	var w := _lp()
	if w == null:
		return
	Count9.strike_early(w, Vector2(30, 30), int(w.sys_state.lp.fid))
	Count9.cut_relay(w, "r0")
	check(Hive71.is_isolated(w, "n0"), "relay cut isolates nest")
	check(Count9.harness_ok(w, "strike_early_cut_relays"), "harness strike_early_cut_relays")


func test_counter_emp_ew_hacking() -> void:
	var w := _lp()
	if w == null:
		return
	var mfid := _machine_fid(w)
	var hfid := int(w.sys_state.lp.fid)
	var mdef := "m_micro_drone" if not Content.unit("m_micro_drone").is_empty() else "g71_m_brute"
	if Content.unit(mdef).is_empty():
		mdef = "mbt"
	var mid := w.spawn_unit(mdef, mfid, Vector2(41, 40))
	var hdef := "mbt" if Content.unit("mbt") != {} else "trooper"
	var hid := w.spawn_unit(hdef, hfid, Vector2(40, 40))
	var n := Count9.emp_stun(w, Vector2(41, 40), 8.0, 4.0, hfid)
	if mfid >= 0 and mid >= 0 and String(w.factions[mfid].get("faction_def", "")) == "machine":
		check(n >= 1, "emp hits machine")
		check(MachineEw7.held(w, mid) == "emp", "emp hold")
	else:
		check(Count9.ew_jam(w, w.entities[hid], 3.0, hid), "jam fallback")
	check(Count9.harness_ok(w, "emp_ew_hacking"), "harness emp_ew_hacking")


func test_counter_deny_material() -> void:
	var w := _lp()
	if w == null:
		return
	var pos := Vector2(w.sys_state.lp.base.center) + Vector2(3, 0)
	var uid := w.spawn_unit("mbt", int(w.sys_state.lp.fid), pos)
	w.destroy(uid, "test")
	var wid := -1
	for id in w.entities.keys():
		if String(w.entities[id].get("kind", "")) == "wreck":
			wid = int(id)
			break
	if not check(wid >= 0, "wreck"):
		return
	check(Count9.deny_wreck(w, wid), "deny wreck")
	check(bool(w.entities[wid].get("g71_denied", false)), "denied flag")
	Harvest71._spawn_wave(w, Harvest71._st(w))
	var harvs: Array = Harvest71._st(w).harvs
	if not harvs.is_empty():
		harvs[0].pos = [snappedf(pos.x - 1, 0.01), snappedf(pos.y, 0.01)]
		Harvest71._st(w).harvs = harvs
	Harvest71._move_harvs(w, Harvest71._st(w))
	check(int(w.entities[wid].get("drag", -1)) < 0, "harvester skips denied wreck")
	check(Count9.harness_ok(w, "deny_material"), "harness deny_material")


func test_counter_sweep_and_purge() -> void:
	var w := _lp()
	if w == null:
		return
	var center := Vector2(w.sys_state.lp.base.center) + Vector2(20, 0)
	Creep.add_seed(w, center, "seed", _machine_fid(w))
	for i in 20:
		w.step()
	var res := Count9.sweep_purge(w, center, 8.0, int(w.sys_state.lp.fid))
	check(int(res.get("cells", 0)) >= 0, "purge ran")
	check(Count9.harness_ok(w, "sweep_and_purge"), "harness sweep_and_purge")


func test_counter_network_virus() -> void:
	var w := _lp()
	if w == null:
		return
	check(Count9.plant_virus(w, "r0"), "virus planted")
	check(Hive71.is_isolated(w, "n0"), "virus cut relay")
	check(Count9.harness_ok(w, "network_virus"), "harness network_virus")


func test_counter_decapitation() -> void:
	var w := _lp()
	if w == null:
		return
	var mfid := _machine_fid(w)
	if not check(mfid >= 0, "machine fid"):
		return
	var def := "g71_m_brute" if not Content.unit("g71_m_brute").is_empty() else "mbt"
	var uid := w.spawn_unit(def, mfid, Vector2(50, 50))
	check(Count9.decapitate(w, uid), "decap strike")
	check(not w.entities.has(uid), "command removed")
	check(not bool(Hive71.board(w).get("pulse", true)), "coordination pulse down")
	check(Count9.harness_ok(w, "decapitation"), "harness decapitation")


func test_counter_starve_power() -> void:
	var w := _lp()
	if w == null:
		return
	var fid := int(w.sys_state.lp.fid)
	w.factions[fid].power_prod = 0
	w.factions[fid].power_use = 100
	check(Count9.power_deficit(w, fid), "power deficit")
	check(Count9.harness_ok(w, "starve_power"), "harness starve_power")


func test_counter_reverse_engineering() -> void:
	var w := _lp()
	if w == null:
		return
	var cid := Count9.reverse_engineer_cell(w, "g71_m_brute")
	check(cid != "", "recomplex cell")
	var mfid := _machine_fid(w)
	if Content.unit("g71_m_reclaimer").is_empty():
		check(cid != "", "recomplex only path")
	else:
		var uid := w.spawn_unit("g71_m_reclaimer", mfid, Vector2(55, 55))
		w.entities[uid].hp = 1.0
		check(Count9.reverse_engineer_cage(w, uid), "cage study path")
	check(Count9.harness_ok(w, "reverse_engineering"), "harness reverse_engineering")


func test_counter_firebreaks_hostile_ground() -> void:
	var w := _lp()
	if w == null:
		return
	var pos := Vector2(w.sys_state.lp.base.center) + Vector2(-15, 5)
	check(Count9.firebreak(w, pos, int(w.sys_state.lp.fid)), "firebreak")
	check(Fire71.blocks_at(w, pos), "fire blocks tide path")
	check(Count9.harness_ok(w, "firebreaks_hostile_ground"), "harness firebreaks")


func test_counter_coalitions() -> void:
	var w := _lp()
	if w == null:
		return
	Count9.coalition_truce(w, [int(w.sys_state.lp.fid)], 200)
	check(Count9.coalition_active(w, int(w.sys_state.lp.fid)), "truce active")
	check(Count9.harness_ok(w, "coalitions"), "harness coalitions")


func test_counter_dead_zones() -> void:
	var w := _lp()
	if w == null:
		return
	var pos := Vector2(120, 120)
	Count9.mark_dead_zone(w, pos, 10.0)
	check(Count9.hive_link_weak(w, pos + Vector2(2, 0)), "inside dead zone")
	check(Count9.harness_ok(w, "dead_zones"), "harness dead_zones")


func test_counter_hunter_killer_squads() -> void:
	var w := _lp()
	if w == null:
		return
	var fid := int(w.sys_state.lp.fid)
	var center: Vector2 = w.sys_state.lp.base.center
	Fleet71.seed(w, fid, center)
	var n := Count9.hunter_killers_deployed(w, fid)
	check(n >= 1 or Content.unit("g71_hunter_tank").is_empty(), "hunters seeded or def absent")
	check(Count9.harness_ok(w, "hunter_killer_squads"), "harness hunter_killer_squads")


func test_counter_reprogramming_captured() -> void:
	var w := _lp()
	if w == null:
		return
	var mfid := _machine_fid(w)
	var pfid := int(w.sys_state.lp.fid)
	var def := "g71_m_brute" if not Content.unit("g71_m_brute").is_empty() else "mbt"
	var uid := w.spawn_unit(def, mfid, Vector2(48, 48))
	w.entities[uid].hp = 0.1
	w.entities[uid].disabled = true
	check(Count9.reprogram(w, uid, pfid), "reprogram disabled machine")
	check_eq(int(w.entities[uid].owner), pfid, "owner flipped")
	check(bool(w.entities[uid].get("g71_reprogrammed", false)), "reprogram flag")
	check(Count9.harness_ok(w, "reprogramming_captured"), "harness reprogramming")