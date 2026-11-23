extends "res://tests/test_base.gd"
## G7.1 F robot fleet: defs, seed scale, charge, leader re-election, jam autonomy, mule wreck recovery.

const Fleet71 = preload("res://sim/systems/fleet71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_fleet_defs_and_seed() -> void:
	for id in ["g71_wall_sentinel", "g71_robot_dog", "g71_ugv_mg", "g71_robot_mule", "g71_hunter_tank"]:
		check(not Content.unit(id).is_empty(), "%s def loads" % id)
		check(Fleet71.is_robot(id), "%s is a fleet robot" % id)
	check(Fleet71.is_mule("g71_robot_mule"), "mule role flagged")
	check(Fleet71.battery_max() > 0.0, "battery max set")
	var c := LastProtocol.make_config(77, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match starts for fleet"):
		return
	for i in 30:
		w.step()
	var s: Dictionary = w.sys_state.lp
	check(int(s.get("fleet_n", 0)) >= 60, "facility fill seeds a large starter fleet (%d)" % int(s.get("fleet_n", 0)))
	var bots: Array = Fleet71.robots_of(w, int(s.fid))
	check(bots.size() >= 60, "robots live on the map (%d)" % bots.size())
	var mules: Array = Fleet71.mules_of(w, int(s.fid))
	check(mules.size() >= 4, "mules in the fleet (%d)" % mules.size())
	var lid := int((w.sys_state.get("fleet71", {}) as Dictionary).get("leaders", {}).get(str(int(s.fid)), -1))
	check(lid >= 0 and w.entities.has(lid), "a swarm leader is elected")
	check(not Fleet71.is_mule(String(w.entities[lid].def)), "leader is not a mule")
	# Kill the leader -> re-elect on the next elect cadence.
	w.destroy(lid, "test", int(s.mfid))
	for i in 50:
		w.step()
	var lid2 := int((w.sys_state.get("fleet71", {}) as Dictionary).get("leaders", {}).get(str(int(s.fid)), -1))
	check(lid2 >= 0 and lid2 != lid and w.entities.has(lid2), "swarm re-elects after leader death")
	Fleet71.jam_sector(w, 2, 5.0)
	check(int((w.sys_state.fleet71.jam as Dictionary).get("2", 0)) > w.tick, "jam sector is timed")
	check(int(LastProtocol.hud(w).get("fleet_n", 0)) >= 1, "HUD exposes fleet count")


func test_fleet_mule_recovers_wreck() -> void:
	var c := LastProtocol.make_config(91, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match for recover"):
		return
	for i in 30:
		w.step()
	var s: Dictionary = w.sys_state.lp
	var fid := int(s.fid)
	var victim := -1
	for e in Fleet71.robots_of(w, fid):
		if String(Content.unit(String(e.def)).get("g71_fleet", "")) == "dog":
			victim = int(e.id)
			break
	if not check(victim >= 0, "have a dog to wreck"):
		return
	var vpos: Vector2 = w.entities[victim].pos
	# Park a mule on the dog so recovery is immediate.
	var mule_id := -1
	for e in Fleet71.mules_of(w, fid):
		mule_id = int(e.id)
		e.pos = vpos
		break
	if not check(mule_id >= 0, "have a mule"):
		return
	w.destroy(victim, "test", int(s.mfid))
	var wrecks_before := 0
	for id in w.entities:
		var x = w.entities[id]
		if x != null and String(x.get("kind", "")) == "wreck" and String(x.get("def", "")) == "g71_robot_dog":
			wrecks_before += 1
	check(wrecks_before >= 1, "dog left a wreck")
	var recovered := false
	for i in 40:
		w.step()
		for ev in w.events:
			if String(ev.get("type", "")) == "Fleet71Recovered":
				recovered = true
				break
		if recovered:
			break
	check(recovered, "mule recovered the wreck")
	var wrecks_after := 0
	for id in w.entities:
		var x = w.entities[id]
		if x != null and String(x.get("kind", "")) == "wreck" and String(x.get("def", "")) == "g71_robot_dog":
			wrecks_after += 1
	check(wrecks_after == 0, "wreck removed so Reclaimer cannot eat it")
