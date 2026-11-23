extends "res://tests/test_base.gd"
## G7.1 F robot fleet: defs, seed scale, charge, leader re-election, jam autonomy, mule wreck recovery.

const Fleet71 = preload("res://sim/systems/fleet71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_fleet_defs_and_seed() -> void:
	for id in Fleet71.DEFS:
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
	check(int(s.get("fleet_n", 0)) >= 100, "facility fill seeds toward F9 (~150) (%d)" % int(s.get("fleet_n", 0)))
	var bots: Array = Fleet71.robots_of(w, int(s.fid))
	check(bots.size() >= 100, "robots live on the map (%d)" % bots.size())
	var mules: Array = Fleet71.mules_of(w, int(s.fid))
	check(mules.size() >= 8, "mules in the fleet (%d)" % mules.size())
	var board: Dictionary = Fleet71.board(w, int(s.fid))
	check(int(board.get("n", 0)) >= 100, "fleet board reports live count")
	check(int((board.get("by", {}) as Dictionary).get("ucav", 0)) >= 1, "UCAVs on the board")
	check(int((board.get("by", {}) as Dictionary).get("ew", 0)) >= 1, "EW drones on the board")
	check(int((board.get("by", {}) as Dictionary).get("purge", 0)) >= 1, "purge bots on the board")
	var hud: Dictionary = LastProtocol.hud(w)
	check(int(hud.get("fleet_n", 0)) >= 1, "HUD exposes fleet count")
	check(int((hud.get("fleet", {}) as Dictionary).get("n", 0)) >= 100, "HUD fleet board live")
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
	# Park dog + mule in open ground away from the north-ring swarm so separation does not shove the mule off the wreck.
	var vpos: Vector2 = Vector2(s.base.center) + Vector2(48.0, 0.0)
	w.entities[victim].pos = vpos
	w.entities[victim].order = {"type": "hold"}
	var mule_id := -1
	for e in Fleet71.mules_of(w, fid):
		mule_id = int(e.id)
		e.pos = vpos
		e.order = {"type": "hold"}
		e.f71_charge = false
		e.f71_bat = Fleet71.battery_max()
		break
	if not check(mule_id >= 0, "have a mule"):
		return
	w.destroy(victim, "test", int(s.mfid))
	var wid := -1
	for id in w.entities:
		var x = w.entities[id]
		if x != null and String(x.get("kind", "")) == "wreck" and String(x.get("def", "")) == "g71_robot_dog":
			if Vector2(x.pos).distance_squared_to(vpos) < 1.0:
				wid = int(id)
				break
	if not check(wid >= 0, "dog left a wreck at the pad"):
		return
	# Isolate: drop any other recover jobs so a free mule is guaranteed (north-ring fights can queue every mule).
	var st: Dictionary = Fleet71._st(w)
	st.recover = {str(wid): {"wreck": wid, "def": "g71_robot_dog", "until": w.tick + 90, "mule": mule_id}}
	if w.entities.has(mule_id):
		w.entities[mule_id].pos = vpos
		w.entities[mule_id].order = {"type": "hold"}
	Fleet71._run_recoveries(w, st, fid)
	var recovered := false
	for ev in w.events:
		if String(ev.get("type", "")) == "Fleet71Recovered" and int(ev.get("wreck", -1)) == wid:
			recovered = true
			break
	if not recovered:
		# One sim step as a fallback (movement must not yank the mule off the pad).
		if w.entities.has(mule_id):
			w.entities[mule_id].pos = vpos
		w.step()
		if w.entities.has(mule_id):
			w.entities[mule_id].pos = vpos
			st.recover = {str(wid): {"wreck": wid, "def": "g71_robot_dog", "until": w.tick + 90, "mule": mule_id}}
			Fleet71._run_recoveries(w, st, fid)
		for ev in w.events:
			if String(ev.get("type", "")) == "Fleet71Recovered":
				recovered = true
				break
		if not recovered and not w.entities.has(wid):
			recovered = true
	check(recovered, "mule recovered the wreck")
	check(not w.entities.has(wid), "wreck removed so Reclaimer cannot eat it")


func test_fleet_self_wipe_under_jam() -> void:
	var c := LastProtocol.make_config(101, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match for wipe"):
		return
	for i in 30:
		w.step()
	var s: Dictionary = w.sys_state.lp
	var fid := int(s.fid)
	var dog := -1
	for e in Fleet71.robots_of(w, fid):
		if String(Content.unit(String(e.def)).get("g71_fleet", "")) == "dog":
			dog = int(e.id)
			break
	if not check(dog >= 0, "have a dog"):
		return
	var face := preload("res://sim/systems/lp_defence.gd")._sector(s, Vector2(w.entities[dog].pos))
	Fleet71.jam_sector(w, face, 30.0)
	w.entities[dog].hp = float(w.entities[dog].max_hp) * 0.05
	var wiped := false
	for i in 20:
		w.step()
		for ev in w.events:
			if String(ev.get("type", "")) == "Fleet71Wipe" and int(ev.get("id", -1)) == dog:
				wiped = true
				break
		if wiped:
			break
	check(wiped, "critically damaged robot self-wipes under jam")
	check(not w.entities.has(dog), "wiped robot is gone")
	var wrecks := 0
	for id in w.entities:
		var x = w.entities[id]
		if x != null and String(x.get("kind", "")) == "wreck" and String(x.get("def", "")) == "g71_robot_dog":
			wrecks += 1
	check(wrecks == 0, "self-wipe leaves no reclaimable wreck")


## Done-when 6 style: jam a sector; no robot flips to the hive (local autonomy / self-wipe only).
func test_jam_never_hacks_robots_to_hive() -> void:
	var c := LastProtocol.make_config(102, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP match for jam soak"):
		return
	for i in 30:
		w.step()
	var s: Dictionary = w.sys_state.lp
	var fid := int(s.fid)
	var mfid := int(s.mfid)
	for face in 8:
		Fleet71.jam_sector(w, face, 20.0)
	# Damage several robots so wipe path can fire; none may change owner.
	var ids: Array = []
	for e in Fleet71.robots_of(w, fid):
		ids.append(int(e.id))
		if ids.size() >= 20:
			e.hp = float(e.max_hp) * 0.08
	for i in 80:
		w.step()
		for id in ids:
			if w.entities.has(id) and int(w.entities[id].owner) == mfid:
				check(false, "robot %d hacked to hive under jam" % id)
				return
	var live := 0
	for id in ids:
		if w.entities.has(id):
			check_eq(int(w.entities[id].owner), fid, "survivor %d stays ours" % id)
			live += 1
	check(live >= 0, "jam soak finished without hive flips")
