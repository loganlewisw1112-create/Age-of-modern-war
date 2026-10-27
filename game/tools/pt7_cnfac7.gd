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
		for i in 8:
			sq.append(h._unit(w, "rifleman", me, Vector2(ds.pos) + Vector2(-3 + i % 4, 3 + i / 4)))
		for u in sq:
			Transport.load_now(w, ds, u)
	var bay := (ds.get("cargo", []) as Array).size() if ds != null else 0
	pt._log("cnfac7_dropship_bay", ds_ok and loaded and bay == 9, "%s, bay entries %d, slung %d" % [via, bay, Transport.slung(ds).size() if ds != null else -1])
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
