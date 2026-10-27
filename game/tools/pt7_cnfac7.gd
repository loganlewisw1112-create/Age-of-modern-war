extends RefCounted
## G7 playtest flow cnfac7 (CNFAC7): the Counter-Nanite facility rises complete with its defences; a strike team is
## trained into its garages; the APCs pull onto the loading pad, load and roll out through the gate; the stealth
## dropship on the helipad takes an APC (with its crew) and a squad into its bay; a breach triggers lockdown
## (pop-up turrets, sealed garages). Screenshots of each.
## Facility commands go through w.submit when ORCH has registered them (CR world_commands_cnfac7), else straight
## through CnFacility (same validate/apply), logged as such.

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Transport = preload("res://sim/systems/transport.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Air = preload("res://sim/systems/air.gd")

var evs: Array = []


func _on_events(e: Array) -> void:
	for ev in e:
		var t := String(ev.get("type", ""))
		if t.begins_with("Cn") or t == "BaseStateChanged" or t == "UnitLoaded":
			evs.append(ev)


func _has(t: String) -> bool:
	for ev in evs:
		if String(ev.type) == t:
			return true
	return false


func _cmd(pt, cmd: Dictionary) -> String:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	cmd.issuer = int(mv.player_fid)
	if SimWorld.COMMANDS.has(String(cmd.type)):
		var r: Dictionary = w.submit(cmd)
		return String(r.reason)
	var why := CnFacility.validate_command(w, cmd)
	if why == "":
		CnFacility.apply_command(w, cmd)
	return why


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var foe := 1 if me == 0 else 0
	var c: Vector2i = h._open(w, 18)
	w.factions[me].credits = int(w.factions[me].credits) + 100000
	for k in ["salvage", "ore"]:
		w.factions[me].stock[k] = int(w.factions[me].stock.get(k, 0)) + 100000
	mv.world_events.connect(_on_events)
	if OS.get_environment("CNFAC7_RAMP_ONLY") == "1":  # iteration aid: only the ramp scenes
		await _ramp_scenes(pt, w, h, me, c)
		return
	# 1. the facility: core completes, the compound rises with every defence
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(16, 16)
	var fid := w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): return _has("CnFacilityRaised"), 6.0)
	mv.join_sim()
	var F := CnFacility.fac(w, fid)
	pt._log("cnfac7_facility_raised", raised and (F.get("parts", []) as Array).size() >= 45,
		"parts %d" % (F.get("parts", []) as Array).size())
	if not raised:
		return
	var center := CnFacility.compound_rect(F).get_center()
	mv.center_camera_on(center)
	await pt._wait(1.0)
	pt._shot("cnfac7_facility")
	var fd := int(mv.entity_layer.fac_drawn) if mv.entity_layer != null else 0
	pt._log("cnfac7_floors_drawn", fd >= 20, "facility floor / zone sprites drawn %d (pad tiles, helipad, garages, decon, gate)" % fd)
	# 2. train a strike team: it appears inside its APCs in the garages
	var why := _cmd(pt, {"type": "cn_train", "building_id": fid, "kind": "strike_team"})
	await pt._wait(0.3)
	mv.join_sim()
	if not (F.queue as Array).is_empty():
		F.queue[0].left = 2.0
	var ready: bool = await pt._wait_until(func(): return _has("CnTeamReady"), 6.0)
	mv.join_sim()
	var tid := 0
	for ev in evs:
		if String(ev.type) == "CnTeamReady":
			tid = int(ev.team)
	var T := CnFacility.team(w, tid)
	var crew := 0
	for aid in T.get("apcs", []):
		var a = w.entities.get(int(aid))
		if a != null:
			crew += (a.get("cargo", []) as Array).size()
	pt._log("cnfac7_team_in_garages", ready and (T.get("apcs", []) as Array).size() == 2 and crew == 20,
		"cmd '%s' team %d apcs %d crew %d" % [why, tid, (T.get("apcs", []) as Array).size(), crew])
	mv.center_camera_on(CnFacility.garage_spots(F)[0] + Vector2(6, 2))
	await pt._wait(0.8)
	pt._shot("cnfac7_garages")
	# 3. roll out: garages -> loading pad -> gate
	_cmd(pt, {"type": "cn_rollout", "team": tid, "target": center + Vector2(0, 26)})
	var loading: bool = await pt._wait_until(func(): return _has("CnLoading"), 40.0)
	mv.center_camera_on(CnFacility.zone(F, "pad").get_center())
	await pt._wait(0.5)
	pt._shot("cnfac7_loading_pad")
	pt._log("cnfac7_loading", loading)
	var rolled: bool = await pt._wait_until(func(): return _has("CnRollout"), 20.0)
	mv.center_camera_on(CnFacility.zone(F, "gate").get_center())
	await pt._wait(2.0)
	pt._shot("cnfac7_rollout_gate")
	var out: bool = await pt._wait_until(func(): return _has("CnTeamOut"), 40.0)
	pt._log("cnfac7_rollout", rolled and out)
	await pt._wait(1.0)
	pt._shot("cnfac7_team_out")
	# 4. the stealth dropship on the helipad takes an APC (crew aboard) and a squad into its bay
	_cmd(pt, {"type": "cn_train", "building_id": fid, "kind": "stealth_dropship"})
	await pt._wait(0.3)
	mv.join_sim()
	if not (F.queue as Array).is_empty():
		F.queue[0].left = 2.0
	var ds_ok: bool = await pt._wait_until(func(): return _has("CnDropshipReady"), 6.0)
	mv.join_sim()
	var ds = w.entities.get(int(F.heli))
	var apc = w.entities.get(int(T.apcs[0])) if not (T.get("apcs", []) as Array).is_empty() else null
	var loaded := false
	var via := "load command"
	if ds != null and apc != null:
		w.submit({"type": "load", "issuer": me, "carrier": int(ds.id), "unit_ids": [int(apc.id)]})
		mv.center_camera_on(Vector2(ds.pos))
		loaded = await pt._wait_until(func(): return Transport.carrier_of(w, int(apc.id)) == int(ds.id), 30.0)
		mv.join_sim()
		if not loaded and w.entities.has(int(apc.id)):
			via = "load_now (the load command did not complete in 30 s)"
			loaded = Transport.load_now(w, ds, apc)
		var sq := []
		var foot := Transport.ramp_pt(Vector2(ds.pos), float(ds.facing), -5.0, 3.0)
		for i in 8:
			sq.append(int(h._unit(w, "rifleman", me, foot + Vector2(i % 4, i / 4) * 0.7).id))
		w.submit({"type": "load", "issuer": me, "carrier": int(ds.id), "unit_ids": sq})
		await pt._wait_until(func(): return (ds.get("cargo", []) as Array).size() >= 9 and not ds.has("bay_seq"), 45.0)
		mv.join_sim()
	var bay := (ds.get("cargo", []) as Array).size() if ds != null else 0
	pt._log("cnfac7_dropship_bay", ds_ok and loaded and bay == 9, "%s (rear ramp), bay entries %d, slung %d" % [via, bay, Transport.slung(ds).size() if ds != null else -1])
	await pt._wait(0.6)
	pt._shot("cnfac7_dropship_loaded")
	# 5. breach -> lockdown
	mv.join_sim()
	for i in 3:
		h._unit(w, "rifleman", foe, CnFacility.zone(F, "pad").get_center() + Vector2(i, 0))
	var locked: bool = await pt._wait_until(func(): return _has("CnLockdown"), 10.0)
	mv.join_sim()
	pt._log("cnfac7_lockdown", locked and bool(F.lock) and (F.popups as Array).size() > 0,
		"state %s popups %d" % [CnFacility.secure_state(w, fid), (F.popups as Array).size()])
	mv.center_camera_on(center)
	await pt._wait(1.0)
	pt._shot("cnfac7_lockdown")
	await _ramp_scenes(pt, w, h, me, c)


# ---------------------------------------------------------------- CNFAC7-2: C-17-style rear-ramp loading, 5 facings
const SCENE := [["cn_stealth_dropship", 0], ["a_vtol_dropship", 1], ["cn_stealth_dropship", 2], ["a_vtol_dropship", 3],
	["a_vtol_dropship", 4], ["cn_stealth_dropship", 5], ["cn_stealth_dropship", 6], ["a_vtol_dropship", 7]]  # CNFAC7-3: all 8 facings
## CNFAC7-3: bystanders on every side of each craft (u along the nose, v across); the rear lane stays open for the ramp
const RING := [[3.4, 0.0], [2.6, 2.6], [2.6, -2.6], [0.0, 3.0], [0.0, -3.0], [-1.6, 3.0], [-1.6, -3.0], [-2.9, 2.4], [-2.9, -2.4], [-3.4, 1.7], [-3.4, -1.7], [1.4, 2.8]]
const SLOTS := [Vector2(-15, -8), Vector2(0, -8), Vector2(15, -8), Vector2(-8, 9), Vector2(8, 9)]


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


## An open 19 x 19 patch (vehicle-passable) at least 24 tiles from the facility and 20 from the others, or (-1, -1).
func _open_patch(w: SimWorld, from: Vector2i, taken: Array) -> Vector2i:
	for rad in range(24, 140, 3):
		for k in 24:
			var a := TAU * float(k) / 24.0
			var cc := from + Vector2i(int(cos(a) * rad), int(sin(a) * rad))
			var ok := true
			for t in taken:
				if Vector2(cc).distance_to(Vector2(t)) < 20.0:
					ok = false
			for y in range(cc.y - 9, cc.y + 10):
				if not ok:
					break
				for x in range(cc.x - 9, cc.x + 10):
					if not w.in_bounds(Vector2i(x, y)) or not Movement.is_passable(w, Vector2i(x, y), "vehicle"):
						ok = false
						break
				if not ok:
					break
			if ok:
				return cc
	return Vector2i(-1, -1)


func _ph(w: SimWorld, id: int) -> String:
	var e = w.entities.get(id)
	return String((e.get("bay_seq", {}) as Dictionary).get("ph", "")) if e != null else ""


## Pauses, frames every craft at zoom 2 (even slots also at zoom 1 and 3), unpauses.
func _shoot_all(pt, mv, w: SimWorld, crafts: Array, stage: String, facs: Array = []) -> int:
	mv.paused = true
	var drawn := 0
	for i in crafts.size():
		var e = w.entities.get(int(crafts[i]))
		if e == null:
			continue
		var zs := [1.0, 2.0, 3.0]  # CNFAC7-3: every facing at zoom 1, 2, 3
		for z in zs:
			_zoom(mv, z)
			mv.center_camera_on(Vector2(e.pos) + Vector2(-0.5, -0.5))
			await pt._wait(0.35)
			drawn += int(mv.entity_layer.bay_drawn) if mv.entity_layer != null else 0
			_hide_check(pt, mv, "%s_f%d_z%d" % [stage, int(facs[i]), int(z)])
			await pt._shot("cnfac7_ramp_%s_f%d_z%d" % [stage, int(facs[i]), int(z)])
	_zoom(mv, 1.0)
	mv.paused = false
	return drawn


func _all_done(w: SimWorld, crafts: Array, want_vehicle: int) -> bool:
	for id in crafts:
		var e = w.entities.get(int(id))
		if e == null or e.has("bay_seq") or int(Transport.group_load(e).vehicle) != want_vehicle:
			return false
	return true


func _ramp_scenes(pt, w: SimWorld, h, me: int, from: Vector2i) -> void:
	var mv = pt._mv()
	mv.join_sim()
	var sites := []
	for i in SCENE.size():
		var p := _open_patch(w, from, sites)
		if p.x < 0:
			break
		sites.append(p)
	pt._log("cnfac7_ramp_site", sites.size() >= 2, "open patches %s" % str(sites))
	if sites.size() < 2:
		return
	var at0 := 0
	while at0 < SCENE.size():
		var idx := []
		for k in range(at0, mini(at0 + sites.size(), SCENE.size())):
			idx.append(k)
		await _ramp_wave(pt, w, h, me, sites, idx)
		at0 += idx.size()


func _ramp_wave(pt, w: SimWorld, h, me: int, sites: Array, idx: Array) -> void:
	var mv = pt._mv()
	mv.join_sim()
	var facs := []
	for k in idx:
		facs.append(int(SCENE[k][1]))
	var crafts := []
	var apcs := []
	var all_ids := []
	var ops := ["g7_op_leader", "g7_op_marksman", "g7_op_hunter", "g7_op_medic"]
	for i in idx.size():
		var at: Vector2 = Vector2(sites[i]) + Vector2(0.5, 0.5)
		var f := PI / 4.0 * float(facs[i])
		var ds: Dictionary = h._unit(w, String(SCENE[int(idx[i])][0]), me, at)
		ds.facing = f
		ds.order = {"type": "idle"}
		Air.land_now(w, ds)
		var apc: Dictionary = h._unit(w, "g7_cn_strike_apc", me, Transport.ramp_pt(at, f, -8.5, 0.0))
		apc.facing = f
		for j in 4:
			Transport.load_now(w, apc, h._unit(w, "g7_cn_gunner", me, Vector2(apc.pos)))
		var ids := [int(apc.id)]
		for j in 8:
			ids.append(int(h._unit(w, ops[j % 4], me, Transport.ramp_pt(at, f, -7.0 - float(j / 4), 2.4 + float(j % 4) * 0.6)).id))
		crafts.append(int(ds.id))
		for rv in RING:   # bystanders standing around the craft (hold), not part of the load
			var b: Dictionary = h._unit(w, "rifleman", me, Transport.ramp_pt(at, f, float(rv[0]), float(rv[1])))
			b.order = {"type": "hold"}
			ids.append(-int(b.id))
		apcs.append(int(apc.id))
		all_ids.append(ids)
	for i in crafts.size():
		w.submit({"type": "load", "issuer": me, "carrier": int(crafts[i]), "unit_ids": all_ids[i].filter(func(x): return int(x) > 0)})
	var c0 := int(crafts[0])
	var got: bool = await pt._wait_until(func(): return _ph(w, c0) == "apc_in" and int(w.entities[c0].bay_seq.t1) - w.tick <= 60, 40.0)
	var d1: int = await _shoot_all(pt, mv, w, crafts, "apcin", facs)
	var tag := "_f" + "_".join(facs.map(func(x): return str(x)))
	pt._log("cnfac7_ramp_apc_drives_in" + tag, got and d1 > 0, "bay frames drawn %d" % d1)
	got = await pt._wait_until(func(): return _ph(w, c0) == "squad_in", 30.0)
	await pt._wait(1.0)
	var d2: int = await _shoot_all(pt, mv, w, crafts, "squadin", facs)
	pt._log("cnfac7_ramp_squad_walks_in" + tag, got and d2 > 0, "bay frames drawn %d" % d2)
	got = await pt._wait_until(func(): return _all_done(w, crafts, 1), 60.0)
	mv.join_sim()
	var full := 0
	for id in crafts:
		var g: Dictionary = Transport.group_load(w.entities[int(id)])
		full += 1 if int(g.vehicle) == 1 and int(g.foot) == 8 else 0
	pt._log("cnfac7_ramp_all_loaded" + tag, got and full == crafts.size(), "%d of %d craft hold APC + crew + 8 operators" % [full, crafts.size()])
	await _shoot_all(pt, mv, w, crafts, "closed", facs)
	for id in crafts:
		w.submit({"type": "unload_all", "issuer": me, "carrier": int(id)})
	got = await pt._wait_until(func(): return _ph(w, c0) == "squad_out", 20.0)
	await pt._wait(0.6)
	var d3: int = await _shoot_all(pt, mv, w, crafts, "squadout", facs)
	var got2: bool = await pt._wait_until(func(): return _ph(w, c0) == "apc_out" and int(w.entities[c0].bay_seq.t1) - w.tick <= 70, 40.0)
	var d4: int = await _shoot_all(pt, mv, w, crafts, "apcout", facs)
	pt._log("cnfac7_ramp_unload_reverse" + tag, got and got2 and d3 > 0 and d4 > 0, "bay frames drawn %d / %d" % [d3, d4])
	got = await pt._wait_until(func(): return _all_done(w, crafts, 0), 60.0)
	mv.join_sim()
	var behind := 0
	for i in crafts.size():
		var e: Dictionary = w.entities[int(crafts[i])]
		var a = w.entities.get(int(apcs[i]))
		if a != null and (Vector2(a.pos) - Vector2(e.pos)).dot(Vector2(cos(float(e.facing)), sin(float(e.facing)))) < -2.5:
			behind += 1
	pt._log("cnfac7_ramp_unloaded" + tag, got and behind == crafts.size(), "%d APCs out behind the tail" % behind)
	await pt._wait(1.5)
	await _shoot_all(pt, mv, w, crafts, "out", facs)
	mv.join_sim()
	for i in crafts.size():   # clear the patch for the next wave
		for id in [int(crafts[i])] + all_ids[i]:
			var e = w.entities.get(absi(int(id)))
			if e != null:
				for x in e.get("cargo", []):
					w.entities.erase(int(x.id))
				w.entities.erase(absi(int(id)))
	w.cache.clear()


## CNFAC7-3: owner "dont show a person thats behind the dropship(s)": after the frame is built, every soldier the layer
## sorted behind a landed craft whose body the hull pixels touch must have been dropped (zero-size push). Logs a fail
## with the count otherwise; the hidden count is evidence that the rule ran.
func _hide_check(pt, mv, tag: String) -> void:
	var el = mv.entity_layer
	if el == null:
		return
	var bad := 0
	for hc in el._bay_hide:
		for cid in el._bay_fr:
			var fr: Array = el._bay_fr[cid]
			if int(hc[3]) < int(fr[4]) and el.bay_feet_covered(fr[0], fr[1], fr[2], fr[3], hc[2]) and (el._dsz[int(hc[0])] as Vector2) != Vector2.ZERO:
				bad += 1
	pt._log("cnfac7_nobody_behind_hull_" + tag, bad == 0, "hidden %d, near-craft infantry %d, still drawn behind the hull %d" % [int(el.bay_hidden), el._bay_hide.size(), bad])
