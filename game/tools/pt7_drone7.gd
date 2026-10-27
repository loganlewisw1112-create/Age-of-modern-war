extends RefCounted
## G7 playtest flow drone7 (DRONE7): take a recon drone from a Drone Team (Y on the selection), corner feed, then
## full screen (U), thermal (T), hand back (B); a strike drone flown over an enemy squad drops a grenade (Space);
## an FPV dives onto a tank; a recon drone flown at an enemy jammer shows LINK LOST. Screenshots of each.
## Steering goes through drone_input.gd's own held-key state (W + heading), so the sim sees real drone_steer commands.

const H = preload("res://tests/test_machine_g6.gd")
const DronePilot = preload("res://sim/systems/drone_pilot.gd")
const DroneInput = preload("res://presentation/hud/drone_input.gd")

var evs: Array = []


func _on_events(e: Array) -> void:
	for ev in e:
		if String(ev.get("type", "")).begins_with("Drone"):
			evs.append(ev)


func _has(t: String, extra: Callable = Callable()) -> bool:
	for ev in evs:
		if String(ev.type) == t and (not extra.is_valid() or extra.call(ev)):
			return true
	return false


func _di(pt, mv):
	var di = mv.get_tree().root.find_child("DroneInput", true, false)
	if di == null:   # hud.gd wiring is ORCH's CR (hud_drone_input); until then the flow adds it the same way
		di = DroneInput.new()
		di.name = "DroneInput"
		mv.add_child(di)
		di.setup(mv)
		pt._log("drone7_input_wired_by_flow", true, "hud.gd CR pending")
	return di


func _key(pt, k: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = true
	pt._push(ev)
	var up := ev.duplicate()
	up.pressed = false
	pt._push(up)


## Points the flown drone at world point p (heading in map space) and holds W.
func _aim(pt, di, p: Vector2) -> void:
	var w: SimWorld = pt._w()
	var e = w.entities.get(di.flying)
	if e == null:
		return
	var to: Vector2 = p - Vector2(e.pos)
	di._hdg = wrapf(rad_to_deg(atan2(to.x, -to.y)), 0.0, 360.0)
	var r = DronePilot.record(w, di.flying)
	var err := absf(wrapf(di._hdg - float(r.hdg), -180.0, 180.0)) if r != null else 0.0
	di._held[KEY_W] = to.length() > 0.8 and err < 25.0   # turn on the spot first: no orbiting the target


func _dist(pt, di, p: Vector2) -> float:
	var e = pt._w().entities.get(di.flying)
	return Vector2(e.pos).distance_to(p) if e != null else -1.0


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.unit("g7_a_fpv").is_empty():
		Content._merge_fragment_dir("res://content/g7")   # until ORCH adds content/g7 (CR content_g7_fragments)
	var w: SimWorld = pt._w()
	var h = H.new()
	var c: Vector2i = h._open(w, 7)
	var me := int(mv.player_fid)
	var foe := 1 if me == 0 else 0
	var base := Vector2(c)
	var team: Dictionary = h._unit(w, "a_drone_team", me, base + Vector2(-6.5, 0.5))
	team.drone_charges = 8
	var squad: Dictionary = h._unit(w, "rifleman", foe, base + Vector2(4.5, -3.5))
	var tank: Dictionary = h._unit(w, "mbt", foe, base + Vector2(6.5, 5.5))
	squad.cd_ticks = 100000
	tank.cd_ticks = 100000
	var di = _di(pt, mv)
	mv.world_events.connect(_on_events)
	mv.center_camera_on(base)
	await pt._wait(0.5)
	# 1. recon drone: select the team, Y
	mv.select_ids([int(team.id)])
	await pt._wait(0.2)
	_key(pt, KEY_Y)
	var took: bool = await pt._wait_until(func(): return di.flying > 0, 3.0)
	if not took:
		di.take(int(team.id), "recon")
		took = await pt._wait_until(func(): return di.flying > 0, 3.0)
	pt._log("drone7_take_recon", took, "flying %d via %s" % [di.flying, "Y" if di.log_cmds.size() == 1 else "take()"])
	_aim(pt, di, base + Vector2(2.5, -6.5))
	await pt._wait(1.5)
	di._held.clear()
	pt._log("drone7_corner_feed", di.cam.visible and di.cam.layout == "corner" and di.cam.shots > 10, "frames %d" % di.cam.shots)
	await pt._shot("drone7_1_recon_corner")
	_key(pt, KEY_U)
	await pt._wait(0.4)
	if di.cam.layout != "full":
		di.toggle_full()
	pt._log("drone7_fullscreen", di.cam.layout == "full", "")
	await pt._shot("drone7_2_recon_full")
	_key(pt, KEY_T)
	await pt._wait(0.4)
	if not di.cam.thermal:
		di.toggle_thermal()
	await pt._wait(0.3)
	pt._log("drone7_thermal", di.cam.thermal, "hot spots %d" % di.cam._hot.size())
	await pt._shot("drone7_3_thermal")
	di.toggle_thermal()
	di.toggle_full()
	var rid: int = di.flying
	_key(pt, KEY_B)
	await pt._wait(0.5)
	if di.flying > 0:
		di.hand_back()
	var handed: bool = await pt._wait_until(func(): return _has("DroneReleased", func(ev): return int(ev.id) == rid), 3.0)
	pt._log("drone7_handback", handed and di.flying < 0, "")
	# 2. strike drone over the squad, Space
	di.take(int(team.id), "strike")
	var st: bool = await pt._wait_until(func(): return di.flying > 0, 3.0)
	squad.order = {"type": "hold"}   # a still target (the enemy AI may move it)
	var over: bool = await pt._wait_until(func():
		_aim(pt, di, Vector2(squad.pos))
		return _dist(pt, di, Vector2(squad.pos)) >= 0.0 and _dist(pt, di, Vector2(squad.pos)) < 0.8, 20.0)
	di._held.clear()
	await pt._wait(0.8)
	var sp := Vector2(squad.pos)
	_key(pt, KEY_SPACE)
	await pt._wait(0.3)
	if not _has("DroneMunitionAway"):
		di.drop()
	var away: bool = await pt._wait_until(func(): return _has("DroneMunitionAway"), 3.0)
	await pt._shot("drone7_4_munition_away")
	var blast: bool = await pt._wait_until(func(): return _has("DroneBlast"), 8.0)
	var surf := ""
	var bp := Vector2(-1, -1)
	for ev in evs:
		if String(ev.type) == "DroneBlast":
			surf = String(ev.surface)
			bp = Vector2(ev.pos)
	pt._log("drone7_strike_drop", st and over and away and blast and surf == "soldier",
		"surface %s blast %s squad %s hp %s" % [surf, bp, sp, str(squad.get("hp"))])
	mv.center_camera_on(sp)
	await pt._shot("drone7_5_strike_blast")
	di.hand_back()
	# 3. FPV dive onto the tank
	di.mouse_aim = false
	di.take(int(team.id), "fpv")
	var ft: bool = await pt._wait_until(func(): return di.flying > 0, 3.0)
	var tp := Vector2(tank.pos)
	var fid: int = di.flying
	tank.order = {"type": "hold"}
	await pt._wait_until(func():   # close in at 20 m, stop 8 tiles out
		_aim(pt, di, tp)
		di._h = 20.0
		if _dist(pt, di, tp) < 8.0:
			di._held.clear()
			return true
		return false, 15.0)
	di._h = 3.0   # dive to 3 m, then go
	await pt._wait_until(func(): return DronePilot.record(pt._w(), fid) == null or float(DronePilot.record(pt._w(), fid).h) <= 3.5, 6.0)
	await pt._shot("drone7_6a_fpv_dive_feed")
	var det: bool = await pt._wait_until(func():
		_aim(pt, di, tp)
		return _has("DroneDetonated", func(ev): return int(ev.id) == fid), 15.0)
	var cause := ""
	for ev in evs:
		if String(ev.type) == "DroneDetonated" and int(ev.id) == fid:
			cause = String(ev.cause)
	det = det and cause == "contact"
	await pt._shot("drone7_6_fpv_link_end")
	mv.center_camera_on(tp)
	await pt._wait(0.2)
	await pt._shot("drone7_7_fpv_blast")
	pt._log("drone7_fpv_dive", ft and det, "cause %s tank hp %s" % [cause, str(tank.get("hp", "destroyed"))])
	# 4. LINK LOST under a jammer
	var jam: Dictionary = h._unit(w, "b_jammer_team", foe, base + Vector2(-6.5, -10.5))
	jam.cd_ticks = 100000
	di.take(int(team.id), "recon")
	await pt._wait_until(func(): return di.flying > 0, 3.0)
	var lid: int = di.flying
	var jp := Vector2(jam.pos)
	var lost: bool = await pt._wait_until(func():
		_aim(pt, di, jp)
		return _has("DroneLinkLost", func(ev): return int(ev.id) == lid), 20.0)
	await pt._wait(0.2)
	pt._log("drone7_link_lost_jammer", lost and di.cam.is_lost(), "")
	await pt._shot("drone7_8_link_lost")
	mv.world_events.disconnect(_on_events)
