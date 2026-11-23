extends "res://tests/test_base.gd"
## G7.1 F robot fleet stubs: defs, seed, charge, leader re-election, jam autonomy.

const Fleet71 = preload("res://sim/systems/fleet71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_fleet_defs_and_seed() -> void:
	for id in ["g71_wall_sentinel", "g71_robot_dog", "g71_ugv_mg"]:
		check(not Content.unit(id).is_empty(), "%s def loads" % id)
		check(Fleet71.is_robot(id), "%s is a fleet robot" % id)
	check(Fleet71.battery_max() > 0.0, "battery max set")
	var c := LastProtocol.make_config(77, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match starts for fleet"):
		return
	for i in 30:
		w.step()
	var s: Dictionary = w.sys_state.lp
	check(int(s.get("fleet_n", 0)) >= 10, "facility fill seeds a starter fleet (%d)" % int(s.get("fleet_n", 0)))
	var bots: Array = Fleet71.robots_of(w, int(s.fid))
	check(bots.size() >= 10, "robots live on the map (%d)" % bots.size())
	var lid := int((w.sys_state.get("fleet71", {}) as Dictionary).get("leaders", {}).get(str(int(s.fid)), -1))
	check(lid >= 0 and w.entities.has(lid), "a swarm leader is elected")
	# Kill the leader -> re-elect on the next elect cadence.
	w.destroy(lid, "test", int(s.mfid))
	for i in 50:
		w.step()
	var lid2 := int((w.sys_state.get("fleet71", {}) as Dictionary).get("leaders", {}).get(str(int(s.fid)), -1))
	check(lid2 >= 0 and lid2 != lid and w.entities.has(lid2), "swarm re-elects after leader death")
	Fleet71.jam_sector(w, 2, 5.0)
	check(int((w.sys_state.fleet71.jam as Dictionary).get("2", 0)) > w.tick, "jam sector is timed")
	check(int(LastProtocol.hud(w).get("fleet_n", 0)) >= 1, "HUD exposes fleet count")
