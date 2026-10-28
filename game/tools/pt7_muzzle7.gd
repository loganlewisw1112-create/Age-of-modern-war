extends RefCounted
## G7 playtest flow muzzle7 (MUZZLE7 / MUZZLE7-2, G7_REFERENCE 13.9c-28: "everything that fires: the muzzle flash
## comes directly from its barrel(s)"; 13.9c-28a: "the mounted gun on the back of the apc ... animated correctly when
## shooting"). A firing line-up in the real game against tough Machine targets: standing infantry, Sentinels, CN
## operators, a CN armoured suit, a squad sprite; suppressed (crouched) / pinned (prone) riflemen; tanks, an IFV, an
## APC, a flak half-track; G6 / G7 turrets and a guard tower; an attack helicopter and a CN gun drone (attack orders);
## then a CN strike team (two strike APCs, gunners aboard) and a tactical APC driving past the targets and away, so
## the rear .50 pod and the RWS must traverse to the flank / rear on their own, and finally the guns' return to travel
## once the fight is over. For every group the camera is centred and set to zoom 2.5 (re-applied after centring) and
## the shot is taken on the very frame a measured barrel-tip flash was spawned for a shooter of that group.
## Checks: every shot used a measured barrel tip (no centre / height-guess fallback), each group produced a flash,
## every flash point lies inside its shooter's drawn sprite box, the APC rear pod fired laid off its travel position
## (independent traverse), both pods and the RWS fired, idle guns went back to travel.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-muzzle7   (ORCH registered "muzzle7")

const H = preload("res://tests/test_machine_g6.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const ApcGun7 = preload("res://presentation/view/apc_gun7.gd")
const Morale = preload("res://sim/systems/morale.gd")
const Z := 2.5


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _zoom_now(mv) -> float:
	return float(mv.camera.zoom.x) if mv.camera != null else -1.0


## Keep the targets alive and the posture actors in their pose (playtest only).
func _hold(w: SimWorld, foes: Array, pinned: Array, supp: Array) -> void:
	for id in foes:
		var e = w.entities.get(id)
		if e != null:
			e.hp = float(Content.unit(String(e.def)).get("hp", 100.0)) * 4.0
	for id in pinned:
		var e = w.entities.get(id)
		if e != null:
			e.pinned = true
			e.supp = 100.0
	for id in supp:
		var e = w.entities.get(id)
		if e != null:
			Morale._ssync()
			e.supp = float(Morale._supp_at) + 2.0   # just suppressed (crouched), still firing back
			e.pinned = false


func _dt(pt) -> float:
	return pt.get_process_delta_time() if pt.has_method("get_process_delta_time") else 0.016


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.unit("g7_cn_strike_apc").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var c: Vector2i = h._open(w, 16)
	var b := Vector2(c)
	var fx = mv.fx_layer
	var el = mv.entity_layer
	var me := int(mv.player_fid)
	var groups := {}   # name -> [ids, centre]
	var pinned: Array = []
	var supp: Array = []
	# infantry line (west), facing east
	var inf := ["rifleman", "rifleman", "rifleman", "g7_sent_warden", "g7_sent_gunner", "g7_cn_team_leader", "a_marines", "g7_cns_bastion"]
	var ids: Array = []
	for i in inf.size():
		var u: Dictionary = h._unit(w, inf[i], me, b + Vector2(-3.0, -5.0 + i * 0.9))
		ids.append(int(u.id))
	supp.append(ids[1])
	pinned.append(ids[2])
	var posed := [ids[1], ids[2]]
	groups["infantry"] = [ids.filter(func(x): return not posed.has(x)), b + Vector2(-2.0, -2.0)]
	groups["poses"] = [posed, b + Vector2(-2.5, -3.5)]
	# vehicles
	ids = []
	for i in 4:
		var u: Dictionary = h._unit(w, ["mbt", "a_apc", "ifv", "b_flak_halftrack"][i], me, b + Vector2(-4.0, 3.0 + i * 1.6))
		ids.append(int(u.id))
	groups["vehicles"] = [ids, b + Vector2(-2.5, 5.5)]
	# turrets / buildings (south-west)
	ids = []
	var bl := ["b_flak_battery", "a_t7_autocannon", "a_t7_hmg_nest", "a_popup_turret", "guard_tower"]
	for i in bl.size():
		var bid: int = w.spawn_building(bl[i], me, c + Vector2i(-5 + i * 3, 10), true)
		if bid >= 0:
			ids.append(bid)
	groups["turrets"] = [ids, b + Vector2(0.0, 10.5)]
	# air: right next to the Machine drones, with attack orders
	ids = []
	for i in 2:
		var u: Dictionary = h._unit(w, ["a_attack_heli", "cn_gun_drone"][i], me, b + Vector2(-0.5, -10.0 + i * 1.5))
		ids.append(int(u.id))
	groups["air"] = [ids, b + Vector2(0.0, -9.5)]
	# tough Machine targets in range
	var foes: Array = []
	for i in 8:
		var u: Dictionary = h._unit(w, "m_tracked", 1, b + Vector2(2.0 + (i % 2) * 1.2, -9.0 + i * 2.6))
		foes.append(int(u.id))
	var drones: Array = []
	for i in 2:
		var u: Dictionary = h._unit(w, "m_drone", 1, b + Vector2(1.0, -10.0 + i * 1.5))
		foes.append(int(u.id))
		drones.append(int(u.id))
	for g in ["infantry", "poses", "vehicles", "air"]:   # our line-up stays alive too (hp topped up like the targets)
		foes.append_array(groups[g][0])
	mv.issue({"type": "attack", "unit_ids": [groups.air[0][0]], "target_id": foes[0]})   # heli: rockets / gun on armour
	mv.issue({"type": "attack", "unit_ids": [groups.air[0][1]], "target_id": drones[0]})  # gun drone: the Machine drone
	pt._log("muzzle7_lineup_spawned", groups.turrets[0].size() == bl.size(), "%d of %d turrets" % [groups.turrets[0].size(), bl.size()])
	var fb0 := int(fx.muzzle7.fallback)
	var t0 := int(fx.muzzle7.tip)
	var shots := []
	var inside := 0
	var flashes := 0
	_zoom(mv, Z)
	await pt._wait_until(func(): return _zoom_now(mv) >= Z - 0.05, 4.0)   # the camera eases its zoom in
	for g in ["infantry", "poses", "vehicles", "turrets", "air"]:
		var gi: Array = groups[g][0]
		mv.center_camera_on(groups[g][1])
		_zoom(mv, Z)   # re-applied after centring (the shots came out at ~zoom 1 before)
		var got := 0
		var waited := 0.0
		var seen := {}
		var want := 2 if g == "poses" else 3
		await pt._wait_until(func(): return _zoom_now(mv) >= Z - 0.05, 2.0)
		while waited < 25.0 and got < want:
			_hold(w, foes, pinned, supp)
			await pt.get_tree().process_frame
			waited += _dt(pt)
			var last: Array = fx.muzzle7_last
			if last.size() >= 3 and gi.has(int(last[0])) and not seen.has(int(last[0])) and int(fx.muzzle7.tip) > t0:
				t0 = int(fx.muzzle7.tip)
				seen[int(last[0])] = true
				flashes += 1
				var d: Vector2 = (last[1] as Vector2) - (last[2] as Vector2)
				if absf(d.x) < 120.0 and d.y < 12.0 and d.y > -140.0:
					inside += 1
				var e = w.entities.get(int(last[0]))
				var pose := ""
				if g == "poses":
					pose = "_" + fx._pose_of_bits(int((el._post as Dictionary).get(int(last[0]), 0)), false)
				var nm := "muzzle7_%s_%d_%s%s" % [g, got, String(e.def) if e != null else "x", pose]
				await pt._shot(nm)
				shots.append(nm)
				got += 1
		pt._log("muzzle7_%s_flash" % g, got >= 1, "%d frame-exact flash shots at zoom %.2f (%s)" % [got, _zoom_now(mv),
			", ".join(seen.keys().map(func(k): return String(w.entities[k].def) if w.entities.has(k) else str(k)))])
	await _apc(pt, mv, w, b, foes, pinned, supp, shots)
	var fb := int(fx.muzzle7.fallback) - fb0
	pt._log("muzzle7_all_measured", fb == 0 and int(fx.muzzle7.tip) > 0, "measured tips %d (APC guns %d), centre/height fallbacks %d %s" % [int(fx.muzzle7.tip), int(fx.muzzle7.get("apc", 0)), fb, str(fx.get("muzzle7_fb"))])
	pt._log("muzzle7_on_sprite", flashes > 0 and inside == flashes, "%d of %d flashes inside the shooter's drawn sprite box" % [inside, flashes])
	pt._log("muzzle7_shots", shots.size() >= 4, ", ".join(shots))


## 13.9c-28a: a CN strike team (2 strike APCs, gunners aboard) and a tactical APC drive past the Machine line and then
## away from it: the pods / RWS traverse to the flank and rear on their own, the pods alternate, the rear pod covers
## the withdrawal; frame-exact shots on the flashes, then the idle return to travel.
func _apc(pt, mv, w: SimWorld, b: Vector2, foes: Array, pinned: Array, supp: Array, shots: Array) -> void:
	var fx = mv.fx_layer
	var el = mv.entity_layer
	var me := int(mv.player_fid)
	var st: Dictionary = CN.spawn_team(w, me, "strike_team", b + Vector2(5.5, -11.0))
	var tt: Dictionary = CN.spawn_team(w, me, "tactical_squad", b + Vector2(7.0, -11.0))
	var apcs: Array = (st.get("apcs", []) as Array) + (tt.get("apcs", []) as Array)
	pt._log("muzzle7_apc_team_spawned", apcs.size() >= 2, "strike APCs %s, tactical %s" % [str(st.get("apcs", [])), str(tt.get("apcs", []))])
	if apcs.is_empty():
		return
	var lead := int(apcs[0])
	var legs := [b + Vector2(5.5, 9.0), b + Vector2(5.5, -9.0), b + Vector2(12.0, -9.0)]   # past the line, back, away east
	var leg := 0
	var leg_t := 0.0
	for i in apcs.size():
		mv.issue({"type": "move", "unit_ids": [int(apcs[i])], "target": legs[0] + Vector2(0.0, -3.5 * i)})
	var got := {}      # "<id>_<gun>" -> shots
	var rear_off := 0.0
	var waited := 0.0
	var a0 := int(fx.muzzle7.get("apc", 0))
	var maxdrawn := 0
	var n_shots := 0
	while waited < 40.0 and n_shots < 5:
		_hold(w, foes, pinned, supp)
		await pt.get_tree().process_frame
		var dt := _dt(pt)
		waited += dt
		leg_t += dt
		var le = w.entities.get(lead)
		if le == null:
			break
		mv.center_camera_on(le.pos)
		_zoom(mv, Z)
		maxdrawn = maxi(maxdrawn, int(el.apc_gun7.counts.drawn))
		if ((le.pos as Vector2).distance_to(legs[leg]) < 1.2 or leg_t > 9.0) and leg < legs.size() - 1:
			leg += 1
			leg_t = 0.0
			for i in apcs.size():
				mv.issue({"type": "move", "unit_ids": [int(apcs[i])], "target": legs[leg] + Vector2(0.0, -3.5 * i)})
		var last: Array = fx.muzzle7_last
		var ls: Array = el.apc_gun7.last_shot
		if int(fx.muzzle7.get("apc", 0)) > a0 and last.size() >= 3 and ls.size() >= 6 and apcs.has(int(last[0])):
			a0 = int(fx.muzzle7.get("apc", 0))
			var sid := int(ls[0])
			var gun := int(ls[1])
			if not w.entities.has(sid):
				continue
			var dn := String(w.entities[sid].def)
			var s: Dictionary = el.apc_gun7._st.get(sid, {})
			var d: Dictionary = el.apc_gun7.def_of(dn)
			var off := 0.0
			if not s.is_empty() and not d.is_empty():
				off = absf(angle_difference(float(s.face) + float(d.m[gun].travel), float(s.y[gun])))
			var key := "%d_%d" % [sid, gun]
			var strike := dn.contains("strike")
			var rear := strike and gun == 1
			if rear:
				rear_off = maxf(rear_off, off)
			got[key] = int(got.get(key, 0)) + 1
			# shoot: the first flash of each gun, and rear-pod flashes laid well off travel
			if got[key] == 1 or (rear and off > 0.6 and got[key] <= 3):
				var gname := ("rear" if rear else "front") if strike else "rws"
				var nm := "muzzle7_apc_%d_%s_%s_off%d" % [n_shots, dn, gname, int(rad_to_deg(off))]
				await pt._shot(nm)
				shots.append(nm)
				n_shots += 1
	var rear_n := 0
	var front_n := 0
	var rws_n := 0
	for k in got:
		var sid := int(String(k).get_slice("_", 0))
		var gun := int(String(k).get_slice("_", 1))
		var strike: bool = w.entities.has(sid) and String(w.entities[sid].def).contains("strike")
		if strike and gun == 1:
			rear_n += int(got[k])
		elif strike:
			front_n += int(got[k])
		else:
			rws_n += int(got[k])
	pt._log("muzzle7_apc_overlays_drawn", maxdrawn >= 3, "up to %d gun overlays drawn in one frame" % maxdrawn)
	pt._log("muzzle7_apc_rear_gun_fires", rear_n >= 1, "rear pod shots %d, front pod %d, RWS %d at zoom %.2f" % [rear_n, front_n, rws_n, _zoom_now(mv)])
	pt._log("muzzle7_apc_rear_gun_traverses", rear_off > 0.6, "rear pod fired laid %.0f deg off its travel position (independent of the hull)" % rad_to_deg(rear_off))
	pt._log("muzzle7_apc_both_guns", front_n >= 1 and rws_n >= 1, "front pod %d, RWS %d" % [front_n, rws_n])
	# fight over: the guns return to travel
	for id in foes:
		if w.entities.has(id) and int(w.entities[id].owner) != me:
			w.destroy(int(id), "playtest")
	for i in apcs.size():
		mv.issue({"type": "stop", "unit_ids": [int(apcs[i])]})
	var back: bool = await pt._wait_until(func():
		mv.join_sim()
		var ww: SimWorld = pt._w()
		var le2 = ww.entities.get(lead)
		if le2 != null:
			mv.center_camera_on(le2.pos)
		var ok := true
		for id in apcs:
			var s2: Dictionary = el.apc_gun7._st.get(int(id), {})
			var e2 = ww.entities.get(int(id))
			if s2.is_empty() or e2 == null:
				continue
			var d2: Dictionary = el.apc_gun7.def_of(String(e2.def))
			for g in (d2.m as Array).size():
				ok = ok and absf(angle_difference(float(s2.face) + float(d2.m[g].travel), float(s2.y[g]))) < 0.1
		return ok, ApcGun7.RETURN_AFTER + 6.0)
	_zoom(mv, Z)
	await pt._shot("muzzle7_apc_idle_travel")
	shots.append("muzzle7_apc_idle_travel")
	pt._log("muzzle7_apc_idle_travel", back, "every pod / RWS back at its travel position once the targets are gone")
