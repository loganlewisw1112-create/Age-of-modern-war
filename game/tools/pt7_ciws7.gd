extends RefCounted
## G7 playtest flow ciws7 (CIWS7, G7_REFERENCE 13.9c-32: two rotary CIWS mounts on the command centre roof, air first,
## ground too, a Facility Engineer swaps the empty drum). In the real game: the player's counter-nanite facility rises
## and its two roof mounts come up with it. A Machine micro-drone swarm dives at the compound: the mounts lay onto the
## drones and shred them in short bursts. Machine rockets are fired at the command centre: the mounts intercept them.
## Breacher crawlers rush the yard inside the compound, outside the blind ring: the mounts depress (to the -25 deg limit
## at the ring edge) and cut them down; a crawler standing at the foot of the command centre, INSIDE the ring, is never
## fired on (CIWS7-6, 13.9c-32b). One mount is run
## dry: it goes silent until a Facility Engineer climbs up and swaps the drum. Frame-exact shots (the sim is paused on
## the exact tick the mount shows its burst / drum-swap frame) at zoom 1.75 and 2.5.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-ciws7   (ORCH registered "ciws7")

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const C7 = preload("res://sim/systems/ciws7.gd")
const CD = preload("res://sim/systems/counterdrone.gd")
const E7 = preload("res://sim/systems/engineer7.gd")
const HotState = preload("res://sim/hot_state.gd")

const ROOF_TILES := 4.75   # roof 15.5 m = 152 px up on screen = (4.75, 4.75) tiles back: centres the camera on the roof


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


## Camera centre that puts a roof point (mount point at roof height) mid-screen; toward: optional ground point to frame too.
func _roof_view(p: Vector2, toward = null) -> Vector2:
	var c := p - Vector2(ROOF_TILES, ROOF_TILES)
	if toward != null:
		c = c.lerp(Vector2(toward), 0.35)
	return c


## Shots at zoom 1.75 and 2.5 centred on at (the sim may be paused: the camera still eases).
## bias: tiles (per axis, divided by the zoom) the camera centre is moved down the screen: the window centre sits
## ~90 px below the middle of the visible map (the bottom panel covers the lower part), a wide frame wants it back.
## CIWS7-5: evs (recorded ciws7 ShotFired of the paused burst) + fx: replayed into the fx layer just before each still
## (same seeds -> the same rounds), the fx clock frozen ~0.1 s into their flight so the tracer stream is in the frame.
func _shots(pt, mv, at: Vector2, tag: String, out: Array, zs: Array = [1.75, 2.5], bias: float = 0.0, evs: Array = [], fx = null) -> void:
	for z in zs:
		var cp: Vector2 = at + Vector2(bias, bias) / float(z)
		_zoom(mv, z)
		mv.center_camera_on(cp)
		await pt._wait_until(func(): return absf(_zoom_now(mv) - z) < 0.05, 3.0)
		mv.center_camera_on(cp)
		await pt._wait(0.35)
		var nm := "ciws7_%s_z%d" % [tag, int(z * 100)]
		if fx != null and not evs.is_empty():
			# the PAUSED banner sits mid-screen, right over the roof: hidden for these stills; the clock is frozen once the
			# tracer heads are part-way (a close stream's tracers live ~0.1 s, a far one's ~0.25 s)
			var hud = mv.get_parent().get("hud") if mv.get_parent() != null else null
			if hud != null and "suppress_banner" in hud:
				hud.suppress_banner = true
			var fms := clampi(roundi(20.0 + 9.0 * float(evs[0].get("d", 6.0))), 40, 120)
			for ev in evs:
				fx.on_shot(ev)
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < fms:
				await pt.get_tree().process_frame
			Engine.time_scale = 0.0
			await pt.get_tree().process_frame
			await pt._shot(nm)
			Engine.time_scale = 1.0
			if hud != null and "suppress_banner" in hud:
				hud.suppress_banner = false
		else:
			await pt._shot(nm)
		out.append(nm)


## Waits (per drawn frame) until a mount shows frame phase ph (2 burst, 3 drum swap; el -1 = any band, else that band),
## then pauses the sim on that tick: returns the mount id with the sim paused, or -1 (sim running) on timeout.
## A step already queued for this frame can still run after the pause, so the state is checked again once paused.
func _catch(pt, mv, ms: Array, ph: int, el: int, secs: float) -> int:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await pt.get_tree().process_frame
		mv.join_sim()
		var bid := _showing(pt._w(), ms, ph, el)
		if bid < 0:
			continue
		mv.paused = true
		await pt._wait(0.3)
		mv.join_sim()
		if _showing(pt._w(), [bid], ph, el) == bid:
			return bid
		mv.paused = false
	return -1


func _showing(w: SimWorld, ms: Array, ph: int, el: int) -> int:
	for bid in ms:
		var e = w.entities.get(int(bid))
		if e == null:
			continue
		var fi := int(e.get("facing_i", 0))
		if posmod(fi, 8) == ph and (el < 0 or fi / 8 == el) and (ph != 2 or int(e.get("firing", 0)) > 0):
			return int(bid)
	return -1


## CIWS7-5: lets mount bid fire at tid until >= 8 of its fire ticks are recorded, then pauses the sim on a tick that
## shows its burst frame; replays each recorded ShotFired into the fx layer and reads fx.ciws7_last: every round's
## point at the target's range must lie on the brg ray (along == range, |lateral| <= range x tan(cone half-angle)),
## mean / max spread, on / past / ground counts, the frame shown and its barrel-vs-stream angles. {} = < 3 fire ticks.
## pin: optional point the target is put back on every frame (CIWS7-6: keeps a crawler just outside the blind ring).
func _stream_leg(pt, mv, fx, bid: int, tid: int, secs: float, pin = null) -> Dictionary:
	var evs: Array = []
	var seen := {}
	var t0 := Time.get_ticks_msec()
	var caught := false
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await pt.get_tree().process_frame
		mv.join_sim()
		var w: SimWorld = pt._w()
		if pin != null and w.entities.has(tid):   # CIWS7-6: the crawler is held on its mark (the ring edge is a few tenths of a tile away)
			HotState.set_pos(w, tid, Vector2(pin))
		for ev in w.events:
			if String(ev.type) == "ShotFired" and bool(ev.get("ciws7", false)) and int(ev.get("shooter", -1)) == bid and int(ev.get("target", -1)) == tid:
				var k := int(ev.get("sd", 0))
				if not seen.has(k):
					seen[k] = true
					evs.append((ev as Dictionary).duplicate(true))
		if evs.size() >= 8 and _showing(w, [bid], 2, -1) == bid:
			mv.paused = true
			await pt._wait(0.3)
			mv.join_sim()
			if _showing(pt._w(), [bid], 2, -1) == bid:
				caught = true
				break
			mv.paused = false
	if evs.size() < 3:
		mv.paused = false
		return {}
	_zoom(mv, 1.75)
	var out := {"n": evs.size(), "rounds": 0, "on": 0, "past": 0, "ground": 0, "bad": 0, "mdev": 0.0, "mlat": 0.0, "d": 0.0,
		"sh": 0.0, "state": "", "ang": -1.0, "ang3": -1.0, "evs": evs.slice(maxi(0, evs.size() - 8)), "caught": caught}
	var f0: Dictionary = (fx.ciws7_fx as Dictionary).duplicate()
	var sdev := 0.0
	for ev in evs:
		fx.ciws7_last = {}
		fx.on_shot(ev)
		var L: Dictionary = fx.ciws7_last
		if L.is_empty():
			continue
		var dw := Vector2.from_angle(float(L.brg))
		var pp := Vector2(-dw.y, dw.x)
		var tol := float(L.d) * tan(float(L.sp)) + 0.01
		for rd in L.rounds:
			var rel: Vector2 = Vector2(rd[0]) - Vector2(L.from)
			out.rounds = int(out.rounds) + 1
			if absf(rel.dot(dw) - float(L.d)) > 0.01 or absf(rel.dot(pp)) > tol:
				out.bad = int(out.bad) + 1
			sdev += Vector2(float(rd[1]), float(rd[2])).length()
			out.mlat = maxf(float(out.mlat), absf(float(rd[1])))
		out.d = float(L.d)
		out.sh = float(ev.get("sh", 0.0))
		out.state = String(L.get("state", ""))
		out.ang = float(L.get("ang", -1.0))
		out.ang3 = float(L.get("ang3", -1.0))
	out.on = int(fx.ciws7_fx.on) - int(f0.on)
	out.past = int(fx.ciws7_fx.past) - int(f0.past)
	out.ground = int(fx.ciws7_fx.ground) - int(f0.ground)
	out.mdev = sdev / float(maxi(int(out.rounds), 1))
	return out


## CIWS7-6: a walkable mark for a stream leg: the point at range rr0 (tiles) from the mount point smp along direction sdir,
## else the nearest alternatives (range steps of 0.25, directions turned up to +-45 deg) with lo <= range <= hi and inside
## cr. Vector2(1e9, 1e9) when nothing fits.
func _leg_mark(w: SimWorld, smp: Vector2, sdir: Vector2, rr0: float, lo: float, hi: float, cr: Rect2, foe: int) -> Vector2:
	var best := Vector2(1.0e9, 1.0e9)
	var bscore := 1.0e9
	for da in [0.0, 0.2, -0.2, 0.4, -0.4, 0.6, -0.6, 0.8, -0.8]:
		var dir := sdir.rotated(float(da))
		var rr := lo
		while rr <= hi + 0.001:
			var p := smp + dir * rr
			if cr.has_point(p) and w.cell_of(p) == Movement.nearest_free_cell(w, w.cell_of(p), "foot", foe):
				var sc := absf(rr - rr0) + absf(float(da)) * 2.0
				if sc < bscore:
					bscore = sc
					best = p
			rr += 0.25
	return best


func _def(ids: Array) -> String:
	for d in ids:
		if not Content.unit(String(d)).is_empty():
			return String(d)
	return String(ids[ids.size() - 1])


func run(pt) -> void:
	# The foe must be the real Machine faction: the ground rule (Ciws7._ground_ok) only engages units that carry the
	# "machine" tag (Creep.machine_fids), and the harness' default match is Human A vs Human A (third run: 0 ground fire).
	var cfg := SimWorld.default_config()
	cfg.sides[1].faction = "machine"
	cfg.sides[1].ai = false
	cfg.victory = "endless"
	var started: bool = pt.main.start_match(cfg)
	pt._log("ciws7_match_started", started, "machine vs human_a, endless, no AI")
	if not started:
		return
	await pt._wait(1.5)
	var mv = pt._mv()
	mv.join_sim()
	if Content.building("cn_ciws7").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var foe := 1 if me == 0 else 0
	pt._log("ciws7_foe_is_machine", SimWorld.Creep.machine_fids(w).has(foe), "foe fid %d, machine fids %s" % [foe, str(SimWorld.Creep.machine_fids(w))])
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[me].stock[k] = 50000
	w.factions[me].credits = 50000
	var shots: Array = []
	C7.counters = {"fire": 0, "kill": 0, "icpt": 0, "icpt_hit": 0, "ground_hits": 0, "ring_viol": 0, "watch": -1, "watch_hits": 0, "watch_min_d": 99.0}
	var c: Vector2i = h._open(w, 24)
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(14, 14)
	w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): mv.join_sim(); var ww: SimWorld = pt._w(); return not CnFacility.facilities(ww, me).is_empty() and C7.mounts_of(ww, int(CnFacility.facilities(ww, me)[0])).size() == 2, 10.0)
	mv.join_sim()
	w = pt._w()
	pt._log("ciws7_mounts_raised", raised, "facility + 2 roof mounts (%s)" % str(C7.mounts_of(w, int(CnFacility.facilities(w, me)[0])) if not CnFacility.facilities(w, me).is_empty() else []))
	if not raised:
		return
	var fac := int(CnFacility.facilities(w, me)[0])
	var F: Dictionary = CnFacility.fac(w, fac)
	var ms: Array = C7.mounts_of(w, fac)
	var mp: Array = []
	for bid in ms:
		mp.append(Vector2(w.entities[bid].get("c7m", w.entities[bid].pos)))
	var roof: Vector2 = (mp[0] + mp[1]) * 0.5
	var art_ok := (ArtCatalog.manifest().get("buildings", {}) as Dictionary).has("cn_ciws7")
	pt._log("ciws7_art_registered", art_ok, "cn_ciws7 sprite set in the merged art catalog (group g7_ciws7)")
	await pt._wait(1.0)
	await _shots(pt, mv, _roof_view(roof), "roof_idle", shots)
	# FLOWA7 (G7 final verification, 2026-10-28): isolate the system under test, the way tests/test_wallturret7.gd does.
	# Since 13.9c-38 ("Double the watch": 48 Sentinels, every tower manned, patrols on every wall) and WATCH7-2 (the drone
	# hive 12 -> 24, 4 interceptors + 8 gun drones), the facility's other defenders took 14 of the 18 swarm drones before
	# the mounts could (full G7 flow run: "4 drones downed by the CIWS (0 of 18 left)"; earlier the same day 31/0).
	# Neither the hive nor the Sentinels are the CIWS: the hive's auto-release is switched off (nothing is aloft yet: the
	# bay launches only on a threat) and the seeded Sentinel garrison (seeded once per facility, never re-seeded) is
	# removed. The facility's own structures (hardened towers, wall turrets) stay. Every check below is unchanged.
	mv.join_sim()
	w = pt._w()
	var dcmd := {"type": "dronebay_auto", "on": false, "issuer": me, "building_id": fac}
	var dv: String = SimWorld.DroneBay7.validate_command(w, dcmd)
	if dv == "":
		SimWorld.DroneBay7.apply_command(w, dcmd)
	var sent := 0
	for id in w.entities.keys():
		var se: Dictionary = w.entities[id]
		if se.kind == "unit" and int(se.owner) == me and String(se.def).begins_with("g7_sent_"):
			w.destroy(int(id), "pt_cleanup", SimWorld.NEUTRAL)
			sent += 1
	pt._log("ciws7_isolated", dv == "" and sent > 0, "CIWS isolated: drone hive auto-release off (%s), %d Sentinels of the seeded garrison removed" % ["ok" if dv == "" else dv, sent])

	# ---- 1. drone swarm: 18 Machine micro-drones dive at the command centre from the north-west (the facility's other
	# defences share the kills: 10 drones gave the CIWS 4 of 10 in the first run, so the swarm is bigger, check unchanged)
	mv.join_sim()
	w = pt._w()
	var dd := _def(["m_micro_drone", "m_drone"])
	var drones: Array = []
	for i in 18:
		var p: Vector2 = roof + Vector2(-8.0 + (i % 6) * 1.0, -7.0 + (i / 6) * 1.3)
		drones.append(int(h._unit(w, dd, foe, p).id))
	var bd := await _catch(pt, mv, ms, 2, -1, 30.0)
	if bd >= 0:
		var e: Dictionary = pt._w().entities[bd]
		var tg = pt._w().entities.get(int(C7.state(pt._w()).m[str(bd)].t))
		pt._log("ciws7_drone_burst_caught", true, "mount %d paused on its burst frame (facing_i %d, el %d, target %s)" % [bd, int(e.facing_i), int(e.facing_i) / 8, String(tg.def) if tg != null else "-"])
		await _shots(pt, mv, _roof_view(Vector2(e.c7m), Vector2(tg.pos) if tg != null else null), "drone_burst", shots)
		mv.paused = false
	else:
		pt._log("ciws7_drone_burst_caught", false, "no burst frame within 30 s (fire ticks %d)" % int(C7.counters.fire))
	var downed: bool = await pt._wait_until(func(): return int(C7.counters.kill) >= 5, 30.0)
	mv.join_sim()
	var alive := 0
	for id in drones:
		if pt._w().entities.has(int(id)):
			alive += 1
	pt._log("ciws7_drones_downed", downed, "%d drones downed by the CIWS (%d of 18 left), fire ticks %d" % [int(C7.counters.kill), alive, int(C7.counters.fire)])

	# ---- 2. rockets at the command centre: intercepted by the mounts (Counterdrone intercept path, lay first)
	await pt._wait(2.5)
	var icpt0 := int(C7.counters.icpt)
	var hits0 := int(C7.counters.icpt_hit)
	var through := 0
	for i in 4:
		mv.join_sim()
		var at: Vector2 = roof + Vector2(1.5 - i, -1.0 + i * 0.6)
		if not CD.intercept_strike(pt._w(), foe, at, "rocket"):
			through += 1
		await pt._wait(1.2)
	mv.join_sim()
	var icpts := int(C7.counters.icpt) - icpt0
	pt._log("ciws7_rockets_intercepted", icpts >= 3 and int(C7.counters.icpt_hit) - hits0 >= 2,
		"4 rockets: %d engaged by the CIWS, %d destroyed, %d got through" % [icpts, int(C7.counters.icpt_hit) - hits0, through])

	# ---- 3. crawler rush into the staging yard (inside the compound): the mounts depress onto them. The drones left
	# over from wave 1 are cleared first: the mounts take air first (owner answer), so a straggler drone circling in
	# track range kept them off the crawlers in the second run.
	mv.join_sim()
	w = pt._w()
	for id in drones:
		if w.entities.has(int(id)):
			w.destroy(int(id), "pt_cleanup")
	var st: Rect2 = CnFacility.zone(F, "staging")
	var cd := _def(["m_breacher_crawler", "m_scout_crawler"])
	var crawlers: Array = []
	var g0 := int(C7.counters.ground_hits)
	# CIWS7-6 (13.9c-32b): the mounts cannot depress below -25 deg, so the rush is placed OUTSIDE the blind ring
	# (blind_radius ~8.63 tiles round each mount point): the south end of the yard, 11-13 tiles from the mounts.
	var ring_r := C7.blind_radius(C7.cfg(), false)
	var smp0: Vector2 = Vector2(w.entities[ms[0]].get("c7m", w.entities[ms[0]].pos))
	var yard_dir: Vector2 = (st.get_center() - smp0).normalized()
	var yard_pt: Vector2 = smp0 + yard_dir * 11.5
	for i in 8:
		var q: Vector2 = yard_pt + Vector2(-1.5 + (i % 4) * 1.0, (i / 4) * 1.0)
		var cc: Vector2i = Movement.nearest_free_cell(w, w.cell_of(q), "foot", foe)
		var cu: Dictionary = h._unit(w, cd, foe, Vector2(cc) + Vector2(0.5, 0.5))
		cu.max_hp = float(cu.max_hp) * 5.0   # first run: the yard's other guns killed all 8 before a CIWS ground scan
		cu.hp = cu.max_hp
		crawlers.append(int(cu.id))
	# one more crawler stands at the foot of the command centre, INSIDE the blind ring of both mounts: it must never be fired on
	var pz: Rect2 = CnFacility.zone(F, "planning")
	var foot_q: Vector2 = Vector2(pz.get_center().x, pz.end.y + 1.5)
	var fq: Vector2i = Movement.nearest_free_cell(w, w.cell_of(foot_q), "foot", foe)
	var ring_u: Dictionary = h._unit(w, cd, foe, Vector2(fq) + Vector2(0.5, 0.5))
	ring_u.max_hp = float(ring_u.max_hp) * 60.0   # survives the facility's other guns for the whole flow
	ring_u.hp = ring_u.max_hp
	# FLOWA7: the ring crawler is the "never fired on" dummy, not an attacker. Idle, it hunted the nearest building with
	# its shaped charge (sight 7): once the 13.9c-38 watch left the command-centre foot, that was mount B, and it blew
	# it up in one 2400-damage charge (diagnosis run: Damage target 149 amount 2400 shooter m_breacher_crawler, then
	# EntityDestroyed 149), which crashed the flow (SCRIPT ERROR at the mount read below). On Hold Position it stands
	# on its mark and only engages inside its 1.2-tile weapon range; its distance to the nearest mount footprint is logged.
	ring_u.order = {"type": "hold"}
	var ring_id := int(ring_u.id)
	C7.counters["watch"] = ring_id
	C7.counters["watch_hits"] = 0
	C7.counters["watch_min_d"] = 99.0
	var ring_dists: Array = [smp0.distance_to(Vector2(ring_u.pos)), Vector2(w.entities[ms[1]].get("c7m", w.entities[ms[1]].pos)).distance_to(Vector2(ring_u.pos))]
	var foot_d := minf(SimWorld.Combat.dist_to(Vector2(ring_u.pos), w.entities[ms[0]]), SimWorld.Combat.dist_to(Vector2(ring_u.pos), w.entities[ms[1]]))
	pt._log("ciws7_ring_crawler_placed", float(ring_dists[0]) < ring_r and float(ring_dists[1]) < ring_r, "a crawler at the foot of the command centre: %.2f / %.2f tiles from mounts A / B (blind ring %.2f tiles), on Hold Position %.2f tiles from the nearest mount footprint" % [float(ring_dists[0]), float(ring_dists[1]), ring_r, foot_d])
	var bg := await _catch(pt, mv, ms, 2, -1, 30.0)
	if bg >= 0:
		var e2: Dictionary = pt._w().entities[bg]
		var tg2 = pt._w().entities.get(int(C7.state(pt._w()).m[str(bg)].t))
		# CIWS7-5: ground fire uses the depressed bands 0..3 (C7.EL_REST = 4 is level, 5 is the intercept band)
		pt._log("ciws7_ground_burst_caught", int(e2.facing_i) / 8 < C7.EL_REST, "mount %d paused on a depressed burst frame (facing_i %d, band %d, target %s)" % [bg, int(e2.facing_i), int(e2.facing_i) / 8, String(tg2.def) if tg2 != null else "-"])
		var tp2: Vector2 = Vector2(tg2.pos) if tg2 != null else st.get_center()
		await _shots(pt, mv, _roof_view(Vector2(e2.c7m), tp2), "crawler_burst", shots)
		# wide frame: the mount on the roof AND the crawlers it is cutting down in the yard (the first two frames are
		# close on the roof, the yard is below them)
		await _shots(pt, mv, _roof_view(Vector2(e2.c7m)).lerp(tp2, 0.5), "crawler_wide", shots, [1.4, 1.0], 2.8)
		# CIWS7-6: the building's foot, the crawler INSIDE the blind ring right under the barrels: not fired on
		var rue = pt._w().entities.get(ring_id)
		if rue != null:
			await _shots(pt, mv, _roof_view(Vector2(e2.c7m)).lerp(Vector2(rue.pos), 0.5), "ring_crawler", shots, [1.75, 1.25], 2.0)
		mv.paused = false
	else:
		pt._log("ciws7_ground_burst_caught", false, "no depressed burst frame within 30 s")
	var cut: bool = await pt._wait_until(func(): return int(C7.counters.ground_hits) - g0 >= 10, 25.0)
	mv.join_sim()
	var left := 0
	for id in crawlers:
		if pt._w().entities.has(int(id)):
			left += 1
	pt._log("ciws7_crawlers_engaged", cut, "%d ground fire ticks on the crawlers, %d of 8 crawlers left" % [int(C7.counters.ground_hits) - g0, left])
	# CIWS7-6: the ring crawler. Fired on = 0 hits, or every hit from outside the ring (it may drift out under fire from the
	# rest of the facility); the in-sim tripwire ring_viol counts any ground fire tick at a range inside the ring.
	var rw: SimWorld = pt._w()
	var ring_alive: bool = rw.entities.has(ring_id)
	# FLOWA7: both mounts must still stand here (a lost mount used to crash this read with a SCRIPT ERROR)
	var mounts_up: bool = rw.entities.has(int(ms[0])) and rw.entities.has(int(ms[1]))
	pt._log("ciws7_mounts_intact", mounts_up, "both roof mounts still standing after the crawler rush (%s)" % str(ms.filter(func(b): return rw.entities.has(int(b)))))
	if not mounts_up:
		return
	var rd := 99.0
	if ring_alive:
		var rpos: Vector2 = Vector2(rw.entities[ring_id].pos)
		rd = minf(smp0.distance_to(rpos), Vector2(rw.entities[ms[1]].get("c7m", rw.entities[ms[1]].pos)).distance_to(rpos))
	pt._log("ciws7_ring_crawler_not_fired_on", int(C7.counters.ground_hits) - g0 >= 10 and int(C7.counters.ring_viol) == 0 and (int(C7.counters.watch_hits) == 0 or float(C7.counters.watch_min_d) >= ring_r - 0.001),
		"while the mounts fired %d ground ticks at the yard crawlers: ring crawler %s (nearest mount now %.2f tiles; hits on it %d, nearest fired-on range %s), ground fire ticks inside the ring: %d" % [
		int(C7.counters.ground_hits) - g0, "alive" if ring_alive else "dead (killed by the facility's other guns)", rd, int(C7.counters.watch_hits),
		"-" if int(C7.counters.watch_hits) == 0 else "%.2f" % float(C7.counters.watch_min_d), int(C7.counters.ring_viol)])
	mv.join_sim()
	w = pt._w()
	for id in crawlers:   # clear the yard so the drum swap runs undisturbed
		if w.entities.has(int(id)):
			w.destroy(int(id), "pt_cleanup")

	# ---- 3b. CIWS7-5 (13.9c-32a), CIWS7-6 (13.9c-32b): an edge burst (the crawler just OUTSIDE the blind ring, ~9 tiles:
	# the barrels at their lowest, -25 deg) and a far burst (~14.5 tiles) from ONE mount (the other is held silent), where
	# CIWS7-5 had close (~3 tiles) and far (~11): the mount cannot depress for anything nearer than the ring. The rounds fly
	# straight along the barrel (brg ray, never bent to the target), the group is tight
	# close and wide far (far rounds fly past / strike the ground), the drawn barrel of the frame shown points down the
	# stream, the BRRRT loop starts. Frame-exact stills: the sim is paused on the burst frame, the burst's recorded fire
	# ticks are replayed into the fx layer (same seeds -> the same rounds) and the fx clock is frozen mid-flight.
	var fx = mv.fx_layer
	var sb := int(ms[0])
	var so := int(ms[1])
	mv.join_sim()
	w = pt._w()
	w.entities[so].emp_until = w.tick + 1000000
	var smp: Vector2 = Vector2(w.entities[sb].get("c7m", w.entities[sb].pos))
	var cr: Rect2 = CnFacility.compound_rect(F).grow(-1.5)
	var sdir: Vector2 = (st.get_center() - smp).normalized()
	var res := {}
	for leg in [["close", ring_r + 0.4], ["far", 14.5]]:   # "close" = the ring edge (kept as the leg name of the shots / checks)
		mv.join_sim()
		w = pt._w()
		var mark: Vector2 = _leg_mark(w, smp, sdir, float(leg[1]), ring_r + 0.3, 9.3 if leg[0] == "close" else 14.6, cr, foe)
		if mark.x > 1.0e8:
			pt._log("ciws7_%s_burst" % leg[0], false, "no walkable mark for the %s leg inside the compound" % leg[0])
			continue
		var cu: Dictionary = h._unit(w, cd, foe, mark)
		cu.max_hp = float(cu.max_hp) * 60.0   # survives the whole leg: the burst is measured, not the kill
		cu.hp = cu.max_hp
		var r := await _stream_leg(pt, mv, fx, sb, int(cu.id), 25.0, mark)
		if not r.is_empty():
			r["tid"] = int(cu.id)
		res[leg[0]] = r
		if not r.is_empty():
			pt._log("ciws7_%s_burst" % leg[0], int(r.n) >= 3, "%s: %d fire ticks at %.2f tiles (share %.2f), %d rounds: %d on target, %d past, %d ground; mean spread %.3f tiles, max lateral %.3f tiles; frame %s, drawn barrel vs stream %.1f deg 3D / %.1f deg screen" % [
				leg[0], int(r.n), float(r.d), float(r.sh), int(r.rounds), int(r.on), int(r.past), int(r.ground), float(r.mdev), float(r.mlat), String(r.state), float(r.ang3), float(r.ang)])
			pt._log("ciws7_%s_straight" % leg[0], int(r.bad) == 0 and int(r.rounds) > 0, "%d / %d rounds on the brg ray (along == range, |lateral| <= range x tan(cone)); off-ray %d" % [int(r.rounds) - int(r.bad), int(r.rounds), int(r.bad)])
			pt._log("ciws7_%s_barrel_on_stream" % leg[0], float(r.ang3) >= 0.0 and float(r.ang3) <= 7.0, "frame %s: drawn barrel %.1f deg (3D) off the stream (test_ciws7 bound 7.0 over every bearing / range)" % [String(r.state), float(r.ang3)])
			await _shots(pt, mv, _roof_view(smp).lerp(Vector2(cu.pos), 0.5), "stream_%s" % leg[0], shots, [1.75, 1.4] if leg[0] == "close" else [1.4, 1.0], 2.0 if leg[0] == "close" else 2.8, r.evs, fx)
		else:
			pt._log("ciws7_%s_burst" % leg[0], false, "no burst on the %s crawler within 25 s" % leg[0])
		mv.paused = false
		mv.join_sim()
		if pt._w().entities.has(int(cu.id)):
			pt._w().destroy(int(cu.id), "pt_cleanup")
		await pt._wait(2.6)   # spin down between legs
	if res.has("close") and res.has("far") and not res.close.is_empty() and not res.far.is_empty():
		# CIWS7-6: the range ratio is now at most 15 / 8.6 = 1.7 (was 11 / 4 = 2.6 with a 1.5x bar): the spread must grow with the
		# range in proportion (>= 0.8 x the range ratio, i.e. the cone), instead of by a fixed 1.5x
		var rratio := float(res.far.d) / maxf(float(res.close.d), 0.1)
		pt._log("ciws7_spread_wider_far", float(res.far.mdev) > float(res.close.mdev) * 0.8 * rratio and float(res.far.mlat) > float(res.close.mlat),
			"mean spread edge %.3f -> far %.3f tiles (x%.2f, range ratio x%.2f, bar x%.2f), max lateral %.3f -> %.3f (cone 80 mrad)" % [float(res.close.mdev), float(res.far.mdev), float(res.far.mdev) / maxf(float(res.close.mdev), 0.001), rratio, 0.8 * rratio, float(res.close.mlat), float(res.far.mlat)])
		var ebands: Array = C7.cfg().elev.bands_deg
		var est := String(res.close.state).split("_")
		var eband := int(est[1]) if est.size() >= 2 else -1
		pt._log("ciws7_edge_barrels_at_limit", eband == 0 and float(ebands[0]) >= C7.depress_min(C7.cfg()) - 0.001,
			"burst %.2f tiles out (ring edge %.2f): frame %s = band %d = %.1f deg, the lowest the mount can aim (limit %.1f deg)" % [float(res.close.d), ring_r, String(res.close.state), eband, float(ebands[eband]) if eband >= 0 else 0.0, C7.depress_min(C7.cfg())])
		pt._log("ciws7_far_rounds_miss", int(res.far.past) + int(res.far.ground) > 0 and float(res.far.sh) < float(res.close.sh),
			"far: %d past + %d ground of %d (share %.2f); close: %d of %d on (share %.2f)" % [int(res.far.past), int(res.far.ground), int(res.far.rounds), float(res.far.sh), int(res.close.on), int(res.close.rounds), float(res.close.sh)])
	var dirr = mv.get_node_or_null("AudioDirector")
	if dirr != null and dirr.get("g7") != null and (dirr.g7.get("ciws_log") is Array):
		var starts := 0
		for le in dirr.g7.ciws_log:
			if String(le.get("ev", "")) == "start" and int(le.get("sid", -1)) == sb:   # sid = the mount, id = the loop voice
				starts += 1
		pt._log("ciws7_brrt_loop_started", starts >= 1, "BRRRT loop starts for mount %d: %d (audio log %d entries)" % [sb, starts, (dirr.g7.ciws_log as Array).size()])
	mv.join_sim()
	pt._w().entities[so].emp_until = 0

	# ---- 4. drum runs dry: silent, a Facility Engineer climbs up and swaps it
	var bx := int(ms[0])
	C7.state(w).m[str(bx)].a = 0
	var dry: bool = await pt._wait_until(func(): mv.join_sim(); return posmod(int(pt._w().entities[bx].get("facing_i", 0)), 8) in [3, 4], 5.0)
	pt._log("ciws7_dry_silent", dry, "mount %d dry (frame phase %d)" % [bx, posmod(int(pt._w().entities[bx].get("facing_i", 0)), 8)])
	if dry and posmod(int(pt._w().entities[bx].get("facing_i", 0)), 8) == 4:
		await _shots(pt, mv, _roof_view(mp[0]), "dry", shots)
	var bs := await _catch(pt, mv, [bx], 3, -1, 120.0)
	if bs >= 0:
		var M: Dictionary = C7.state(pt._w()).m[str(bs)]
		pt._log("ciws7_drum_swap_caught", true, "mount %d paused on its drum-swap frame, engineer %d" % [bs, int(M.get("eng", -1))])
		var door: Vector2 = C7.stair_door(pt._w(), bs)
		await _shots(pt, mv, _roof_view(mp[0]), "drum_swap", shots)
		_zoom(mv, 1.75)
		mv.center_camera_on(_roof_view(mp[0]).lerp(door, 0.5))
		await pt._wait(0.6)
		await pt._shot("ciws7_drum_swap_door_z175")
		shots.append("ciws7_drum_swap_door_z175")
		mv.paused = false
	else:
		pt._log("ciws7_drum_swap_caught", false, "no drum-swap frame within 120 s")
	var drum := int(C7.cfg().get("drum", 1200))
	var full: bool = await pt._wait_until(func(): mv.join_sim(); return C7.ammo(pt._w(), bx) >= drum, 60.0)
	pt._log("ciws7_drum_swapped", full, "mount %d ammo %d / %d after the swap" % [bx, C7.ammo(pt._w(), bx), drum])
	await _shots(pt, mv, _roof_view(roof), "roof_after", shots)
	pt._log("ciws7_shots", shots.size() >= 12, ", ".join(shots))

