extends RefCounted
## G7 playtest flow seq7 (SEQ7, 13.9c-7): the counter-nanite facility's mission sequences (presentation/view/fac_seq7.gd)
## in a real windowed match. Raises a facility, trains a strike team, then shots at zoom 1 / 1.75 / 2.5 (match paused
## for each set, so all three zooms show the same instant) of:
##   launch: scramble beacons, crews running from the ready room to their APC's rear door, ammo rigs at the APCs;
##   return: the APCs stopped in the enclosed wash (spray, runoff), the crews dismounting dirty through the wash-wall
##   door, walking the mantrap / scan / decon hall line and coming out clean; a stretcher team carrying a wounded crewman
##   to the aid station; the quarantine-bay lights for an exposed soldier;
##   dropship sortie: an APC driving up the ramp (marshaller, ramp strobes, lit bay), ramp shut + lift-fan spool-up,
##   take-off dust.
## Uses match_view.fac_seq7 (ORCH wired it, CR 3721: setup after fac_atmo7, refresh every frame after fac_life7).
## Facility commands go through w.submit when registered, else straight through CnFacility (same validate / apply).

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Transport = preload("res://sim/systems/transport.gd")
const Air = preload("res://sim/systems/air.gd")
const ZL := {1: 1.0, 2: 1.75, 3: 2.5}

var evs: Array = []
var _hidden: Array = []


func _on_events(e: Array) -> void:
	for ev in e:
		var t := String(ev.get("type", ""))
		if t.begins_with("Cn") or t == "BayRamp" or t == "UnitLoaded":
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
		return String(w.submit(cmd).reason)
	var why := CnFacility.validate_command(w, cmd)
	if why == "":
		CnFacility.apply_command(w, cmd)
	return why


func _clean_view(mv, on: bool) -> void:
	if on:
		_hidden.clear()
		var hud = mv.get_parent().get("hud") if mv.get_parent() != null else null
		var cands: Array = []
		if hud is Node:
			cands.append(hud)
			cands.append_array((hud as Node).get_children())
		for n in cands:
			if (n is CanvasItem or n is CanvasLayer) and bool(n.visible):
				n.visible = false
				_hidden.append(n)
		var fl = mv.get("fog_layer")
		if fl is CanvasItem and (fl as CanvasItem).visible:
			(fl as CanvasItem).visible = false
			_hidden.append(fl)
	else:
		for n in _hidden:
			n.visible = true
		_hidden.clear()


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


## SEQ7-3: match_view's own layer only (the old auto-mode insertion is gone now that ORCH wires it).
func _layer(mv):
	return mv.get("fac_seq7")


## Three zooms of one paused instant; logs the layer's counters.
func _shots(pt, mv, L, name: String, at: Vector2) -> void:
	var was := bool(mv.paused)
	mv.paused = true
	for z in [1, 2, 3]:
		_zoom(mv, float(ZL[z]))
		mv.center_camera_on(at)
		await pt._wait(0.45)
		await pt._shot("seq7_%s_z%d" % [name, z])
	mv.paused = was
	print("SEQ7_COUNTS %s launch=%d runners=%d boarded=%d carts=%d loads=%d spray=%d decon=%d clean=%d quar=%d stretcher=%d dust=%d marshal=%d drawn=%d hidden=%d actors=%d" % [
		name, L.n_launch, L.n_runners, L.n_boarded, L.n_carts, L.n_loads, L.n_spray, L.n_decon, L.n_clean, L.n_quar,
		L.n_stretcher, L.n_dust, L.n_marshal, L.drawn, L.hidden_occ, (L.actors as Array).size()])
	_dump(L, name)


## Waits n SIM ticks (the harness plays at 3x: wall-clock waits overshoot the short sequences).
func _ticks(pt, w: SimWorld, n: int) -> void:
	var t0 := w.tick
	await pt._wait_until(func(): return w.tick - t0 >= n, 30.0)


func _dump(L, name: String) -> void:
	var out := []
	for A in L.actors:
		if A.has("p"):
			out.append("%s/%s/%s(%.1f,%.1f)%s" % [String(A.kind), String(A.get("end", "")), String(A.get("st", "")), A.p.x, A.p.y, "D" if bool(A.get("dirty", false)) else ""])
	print("SEQ7_ACTORS %s %s" % [name, " ".join(out)])


func _count(L, kind: String, st: String = "") -> int:
	var n := 0
	for A in L.actors:
		if String(A.kind) == kind and (st == "" or String(A.get("st", "")) == st):
			n += 1
	return n


func _mean_pos(L, kind: String, fallback: Vector2) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for A in L.actors:
		if String(A.kind) == kind and A.has("p") and not bool(A.get("hidden", false)):
			s += A.p
			n += 1
	return s / float(n) if n > 0 else fallback


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var c: Vector2i = h._open(w, 18)
	w.factions[me].credits = int(w.factions[me].credits) + 100000
	for k in ["salvage", "ore"]:
		w.factions[me].stock[k] = int(w.factions[me].stock.get(k, 0)) + 100000
	mv.world_events.connect(_on_events)
	var L = _layer(mv)
	pt._log("seq7_layer_wired", L != null and not bool(L.auto), "match_view.fac_seq7 %s" % ("present" if L != null else "MISSING"))
	if L == null:
		return
	_clean_view(mv, true)
	# 1. facility + strike team in the garages
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(16, 16)
	var fid := w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): return _has("CnFacilityRaised"), 8.0)
	mv.join_sim()
	var F := CnFacility.fac(w, fid)
	pt._log("seq7_facility_raised", raised, "facility %d" % fid)
	if not raised:
		_clean_view(mv, false)
		return
	_cmd(pt, {"type": "cn_train", "building_id": fid, "kind": "strike_team"})
	await pt._wait(0.3)
	mv.join_sim()
	if not (F.queue as Array).is_empty():
		F.queue[0].left = 2.0
	var ready: bool = await pt._wait_until(func(): return _has("CnTeamReady"), 8.0)
	mv.join_sim()
	var tid := 0
	for ev in evs:
		if String(ev.type) == "CnTeamReady":
			tid = int(ev.team)
	var T := CnFacility.team(w, tid)
	pt._log("seq7_team_ready", ready and tid != 0, "team %d apcs %d" % [tid, (T.get("apcs", []) as Array).size()])
	await pt._wait(1.0)   # the layer reads the team (every 15 frames)
	if OS.get_cmdline_user_args().has("--seq7-fps"):
		await _fps(pt, mv, w, L, F, tid)
		_clean_view(mv, false)
		return
	var pad := CnFacility.zone(F, "pad").get_center()
	# 2. launch: scramble, runners, ammo rigs
	var center := CnFacility.compound_rect(F).get_center()
	_cmd(pt, {"type": "cn_rollout", "team": tid, "target": center + Vector2(0, 26)})
	var ran: bool = await pt._wait_until(func(): return int(L.n_runners) >= 10 and _count(L, "crew") >= 6, 12.0)
	await _ticks(pt, w, 40)
	pt._log("seq7_launch_runners", ran, "runners %d carts %d scramble %s" % [L.n_runners, L.n_carts, str((L.scramble as Dictionary).has(fid))])
	await _shots(pt, mv, L, "launch_run", _mean_pos(L, "crew", pad))
	var loading: bool = await pt._wait_until(func(): return _has("CnLoading"), 40.0)
	await _ticks(pt, w, 30)
	await _shots(pt, mv, L, "launch_pad", pad)
	var rolled: bool = await pt._wait_until(func(): return _has("CnRollout"), 20.0)
	pt._log("seq7_launch_boarded", loading and rolled and int(L.n_boarded) >= int(L.n_runners) * 8 / 10,
		"boarded %d of %d, rigs loaded %d" % [L.n_boarded, L.n_runners, L.n_loads])
	pt._log("seq7_resupply", int(L.n_carts) >= 2 and int(L.n_loads) >= 1, "rigs %d loaded %d" % [L.n_carts, L.n_loads])
	var out: bool = await pt._wait_until(func(): return _has("CnTeamOut"), 40.0)
	pt._log("seq7_team_out", out)
	await pt._wait(2.0)
	# 3. return: a wounded and an exposed crewman, through the wash and the decon hall
	mv.join_sim()
	T = CnFacility.team(w, tid)
	var crew := []
	for aid in T.get("apcs", []):
		var a = w.entities.get(int(aid))
		if a != null:
			for u in a.get("cargo", []):
				crew.append(int(u.id))
	if crew.size() >= 2:
		var gv = w.sys_state.get("g7v")
		if gv == null:
			gv = {}
			w.sys_state["g7v"] = gv
		gv[int(crew[0])] = {"unc": true, "bleed": true}
		gv[int(crew[1])] = {"ex": 0.5}
	_cmd(pt, {"type": "cn_return", "team": tid})
	mv.join_sim()
	CnFacility._order_slots(w, CnFacility.team(w, tid), "decon")
	var sprayed: bool = await pt._wait_until(func(): return int(L.n_spray) >= 1, 60.0)
	var wash := CnFacility.zone(F, "apc_wash").get_center()
	await _ticks(pt, w, 12)
	await _shots(pt, mv, L, "wash_spray", wash)
	pt._log("seq7_wash_spray", sprayed, "spray %d dismounts %d" % [L.n_spray, L.n_decon])
	await _ticks(pt, w, 36)
	await _shots(pt, mv, L, "decon_dirty_walk", _mean_pos(L, "crew", wash))
	var litter: bool = await pt._wait_until(func(): return _count(L, "litter", "carry") >= 1, 20.0)
	await _shots(pt, mv, L, "stretcher", _mean_pos(L, "litter", wash))
	pt._log("seq7_stretcher", litter or int(L.n_stretcher) >= 1, "stretcher teams %d" % L.n_stretcher)
	var clean: bool = await pt._wait_until(func(): return int(L.n_clean) >= 3, 30.0)
	await _ticks(pt, w, 10)
	var hd: Array = CnFacility.conf().get("doors", {}).get("decon_hall", [])
	var hall_exit := Vector2(CnFacility.origin(F)) + (Vector2(float(hd[-1][0]), float(hd[-1][1])) if not hd.is_empty() else Vector2(16, 16))
	await _shots(pt, mv, L, "decon_clean_out", hall_exit)
	pt._log("seq7_decon_clean", clean, "clean %d" % L.n_clean)
	var quar: bool = await pt._wait_until(func(): return int(L.n_quar) >= 1, 40.0)
	await _ticks(pt, w, 20)
	var qz := ""
	for k in L.lay:
		qz = String((L.lay[k].keys as Dictionary).get("quarantine", "")) if String((L.lay[k].keys as Dictionary).get("quarantine", "")) != "" else String((L.lay[k].keys as Dictionary).get("aid", ""))
	var qat: Vector2 = CnFacility.zone(F, qz).get_center() if qz != "" else center
	await _shots(pt, mv, L, "quarantine", qat)
	pt._log("seq7_quarantine", quar, "quarantine lights %d (zone %s)" % [L.n_quar, qz])
	var parked: bool = await pt._wait_until(func(): return String(CnFacility.team(w, tid).get("phase", "")) == "garage", 60.0)
	pt._log("seq7_parked", parked)
	# 4. dropship sortie from the helipad: APC up the ramp, ramp shut + spool-up, take-off
	_cmd(pt, {"type": "cn_train", "building_id": fid, "kind": "stealth_dropship"})
	await pt._wait(0.3)
	mv.join_sim()
	if not (F.queue as Array).is_empty():
		F.queue[0].left = 2.0
	var ds_ok: bool = await pt._wait_until(func(): return _has("CnDropshipReady"), 8.0)
	mv.join_sim()
	var ds = w.entities.get(int(F.heli))
	pt._log("seq7_dropship_ready", ds_ok and ds != null)
	if ds == null:
		_clean_view(mv, false)
		return
	var f := float(ds.facing)
	var apc: Dictionary = h._unit(w, "g7_cn_strike_apc", me, Transport.ramp_pt(Vector2(ds.pos), f, -8.5, 0.0))
	apc.facing = f
	for j in 4:
		Transport.load_now(w, apc, h._unit(w, "g7_cn_gunner", me, Vector2(apc.pos)))
	await pt._wait(1.0)
	w.submit({"type": "load", "issuer": me, "carrier": int(ds.id), "unit_ids": [int(apc.id)]})
	# SEQ7-3: also true once aboard (run e: on a loaded shared PC the APC was in before a poll saw it inside 5.5 tiles)
	var ramp: bool = await pt._wait_until(func(): return Transport.carrier_of(w, int(apc.id)) == int(ds.id) or (w.entities.has(int(apc.id)) and Vector2(w.entities[int(apc.id)].pos).distance_to(Vector2(ds.pos)) < 6.0), 30.0)
	await _ticks(pt, w, 4)
	await _shots(pt, mv, L, "dropship_ramp", Vector2(ds.pos))
	pt._log("seq7_dropship_ramp", ramp and int(L.n_marshal) >= 1, "marshaller frames %d" % L.n_marshal)
	var loaded: bool = await pt._wait_until(func(): return Transport.carrier_of(w, int(apc.id)) == int(ds.id), 40.0)
	# SEQ7-3: the craft keeps the ramp down a while for more passengers: wait until it is up, then the fans wind up
	await pt._wait_until(func(): return not L._ramp_down(L.crafts.get(int(ds.id), {})), 25.0)
	await _ticks(pt, w, 60)
	await _shots(pt, mv, L, "dropship_spool", Vector2(ds.pos))
	pt._log("seq7_dropship_loaded", loaded)
	var d0 := int(L.n_dust)
	mv.issue({"type": "move", "unit_ids": [int(ds.id)], "target": Vector2(ds.pos) + Vector2(-30, -30)})
	var lifted: bool = await pt._wait_until(func(): return int(L.n_dust) > d0, 20.0)
	await _ticks(pt, w, 6)
	await _shots(pt, mv, L, "dropship_takeoff", Vector2(w.entities[int(ds.id)].pos) if w.entities.has(int(ds.id)) else center)
	pt._log("seq7_dropship_takeoff", lifted, "dust bursts %d" % L.n_dust)
	_zoom(mv, 1.0)
	mv.center_camera_on(center)
	await pt._wait(0.5)
	await pt._shot("seq7_overview")
	_clean_view(mv, false)


# ================================================================ SEQ7-3: fps with the layer on / off
## `--seq7-fps` (after the flow arg): the bench's 2k-on-screen load (tools/bench.gd MIX: 60 % rifleman, 15 % at_gunner,
## 15 % ifv, 10 % mbt; 1000 per side) fighting across the facility, camera on the facility at zoom 1, 1x speed, vsync
## off; a launch then a return + decon run while 5 s windows alternate layer ON / OFF (OFF = the layer detached:
## refresh returns at once, nothing drawn). Prints SEQ7_FPS lines (avg and p10 fps per window, pooled per state).
const MIX7 := [["rifleman", 0.60], ["at_gunner", 0.15], ["ifv", 0.15], ["mbt", 0.10]]


func _fps(pt, mv, w: SimWorld, L, F: Dictionary, tid: int) -> void:
	mv.speed = 1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var center := CnFacility.compound_rect(F).get_center()
	var fids: Array = w.factions.keys()
	mv.join_sim()
	var Terr = load("res://sim/terrain.gd")
	var placed_all := 0
	for side in 2:
		var fid: int = fids[side]
		var base := center + Vector2(-26.0 if side == 0 else 26.0, 6.0)
		var ids := []
		var ring := 0
		while ids.size() < 1000 and ring < 60:
			var cnt := maxi(1, ring * 6)
			for k in cnt:
				if ids.size() >= 1000:
					break
				var pos := base + Vector2.from_angle(float(k) / float(cnt) * TAU) * float(ring) * 0.9
				var cc := Vector2i(floori(pos.x), floori(pos.y))
				var i := ids.size()
				var def: String = "rifleman"
				var acc := 0.0
				for m in MIX7:
					acc += float(m[1])
					if float(i % 20) / 20.0 < acc:
						def = String(m[0])
						break
				var mc := String(Content.unit(def).get("move_class", "foot"))
				if not w.in_bounds(cc) or not Terr.passable(w.terrain_at(cc), mc):
					continue
				ids.append(w.spawn_unit(def, fid, pos))
			ring += 1
		w.submit({"type": "attack_move", "issuer": fid, "unit_ids": ids, "target": center + Vector2(26.0 if side == 0 else -26.0, 6.0)})
		placed_all += ids.size()
	pt._log("seq7_fps_spawn", placed_all >= 1800, "units %d" % placed_all)
	_zoom(mv, 1.0)
	mv.center_camera_on(center)
	await pt._wait(3.0)
	var res := {"on": [], "off": []}
	_cmd(pt, {"type": "cn_rollout", "team": tid, "target": center + Vector2(0, 26)})
	await _windows(pt, mv, L, res, "launch")
	await pt._wait_until(func(): return _has("CnTeamOut"), 40.0)
	mv.join_sim()
	_cmd(pt, {"type": "cn_return", "team": tid})
	mv.join_sim()
	CnFacility._order_slots(w, CnFacility.team(w, tid), "decon")
	mv.center_camera_on(CnFacility.zone(F, "apc_wash").get_center())
	await pt._wait_until(func(): return int(L.n_spray) >= 1, 60.0)
	await _windows(pt, mv, L, res, "decon")
	L.mv = mv
	for st in ["on", "off"]:
		var a: Array = res[st]
		var fr := 0.0
		var tt := 0.0
		for d in a:
			fr += 1.0
			tt += float(d)
		a.sort()
		var p10 := 1.0 / float(a[int(a.size() * 0.9)]) if not a.is_empty() else 0.0
		print("SEQ7_FPS pooled %s frames=%d avg=%.1f p10=%.1f" % [st, int(fr), fr / maxf(tt, 0.0001), p10])
	pt._log("seq7_fps_measured", not (res.on as Array).is_empty() and not (res.off as Array).is_empty())


## Four 5 s windows ON / OFF / ON / OFF; frame durations into res.
func _windows(pt, mv, L, res: Dictionary, tag: String) -> void:
	for k in 4:
		var st := "on" if k % 2 == 0 else "off"
		L.mv = mv if st == "on" else null
		if st == "off":
			L.visible = false
		await pt._wait(0.3)
		var ds := []
		var tree: SceneTree = mv.get_tree()
		var t0 := Time.get_ticks_usec()
		var last := t0
		while Time.get_ticks_usec() - t0 < 5000000:
			await tree.process_frame
			var now := Time.get_ticks_usec()
			ds.append(float(now - last) / 1000000.0)
			last = now
		(res[st] as Array).append_array(ds)
		var tot := 0.0
		for d in ds:
			tot += float(d)
		var sd := ds.duplicate()
		sd.sort()
		print("SEQ7_FPS %s %s frames=%d avg=%.1f p10=%.1f actors=%d drawn=%d units=%d" % [tag, st, ds.size(), float(ds.size()) / maxf(tot, 0.0001),
			1.0 / float(sd[int(sd.size() * 0.9)]), (L.actors as Array).size(), int(L.drawn), mv.world.entities.size()])
