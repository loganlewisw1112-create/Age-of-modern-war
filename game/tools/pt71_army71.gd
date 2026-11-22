extends RefCounted
## G7.1 ARMY71 playtest (windowed): start a Last Protocol run, push a Machine assault onto one outer wall face where
## the LP base's B3 crews stand (lp_base_army71.json: MG nests, AT / .50 / grenadier teams), and shoot what the
## owner should see: MG beaten zones, AT backblast, the .50 spotter's mark, the squad hand signals (CONTACT / SHIFT
## FIRE) and the radio subtitle feed, plus the ammo panel with a crew selected. The flow writes the sim only between
## steps (match_view.join_sim) and says what it forces (the Machines it spawns, the map explored).
## Registration: ORCH (change_request flow name army71).

const MapGen = preload("res://sim/map_gen.gd")
const Crew71 = preload("res://sim/systems/crew71.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const D71 = preload("res://sim/systems/discipline71.gd")
const CREWS := ["a_g71_mg_crew", "a_g71_at_team", "a_g71_am_team", "a_g71_grenadier"]


func _layer(pt):
	for c in pt._mv().get_children():
		var sc = c.get_script()
		if sc != null and String(sc.resource_path).ends_with("signals71_layer.gd"):
			return c
	return null


## B3 crew marks only (gen 10: the same snapshot dict also carries the D4 cover poses "po" and G1 gear "nv")
static func _marks(c) -> bool:
	if not (c is Dictionary):
		return false
	return not ((c.get("bz", []) as Array).is_empty() and (c.get("bb", []) as Array).is_empty() and (c.get("mk", []) as Array).is_empty())


func run(pt) -> void:
	var LP = SimWorld.LastProtocol
	var map := "last_protocol" if MapGen.has_map("last_protocol") else "lp_test512"
	var started: bool = pt.main.start_match(LP.make_config(71, map))
	pt._log("army71_match_started", started, "map %s" % map)
	if not started:
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return pt._w().sys_state.has("lp") and bool(pt._w().sys_state.lp.get("filled", false)), 60.0)
	mv.join_sim()
	var w: SimWorld = pt._w()
	pt._log("army71_setup", ok, "LP filled at tick %d" % w.tick)
	if not ok:
		return
	var s: Dictionary = w.sys_state.lp
	var ex: PackedByteArray = w.fog[0].explored
	ex.fill(1)
	w.fog[0].explored = ex
	# our crews from the LP base file
	var cnt := {}
	var mg = null
	for e in w.units_of(int(s.fid)):
		var d := String(e.def)
		if CREWS.has(d):
			cnt[d] = int(cnt.get(d, 0)) + 1
			if d == "a_g71_mg_crew" and (mg == null or int(e.id) < int(mg.id)):
				mg = e
	pt._log("army71_crews_placed", cnt.size() == CREWS.size(), "crews in the LP base: %s" % [cnt])
	if mg == null:
		return
	# A Machine group assaulting the outer wall (forced by the flow): 24 units 10 tiles OUTSIDE the first MG nest,
	# attack-moving onto it. The crews stand at the inside wall stations and fire out through the firing port fitted
	# beside them (lp_base "port": true, ORCH seq 2516; ARMY71-7 probe: WallFire7.blocked false 4 / 8 / 14 tiles out).
	var C := Vector2(s.base.center) + Vector2(0.5, 0.5)
	var out := (Vector2(mg.pos) - C).normalized()
	var side := Vector2(-out.y, out.x)
	var p := Vector2(mg.pos) + out * 10.0
	# 18 crawlers (the MG's targets: small arms barely hurt a walker, so an all-walker group drew 1 MG burst in 600
	# ticks) + 6 walkers for the AT / .50 teams
	var mids := []
	for i in 24:
		mids.append(w.spawn_unit("m_walker" if i % 4 == 3 else "m_scout_crawler", int(s.mfid), p + side * (float(i % 6) - 2.5) * 0.7 + out * float(i / 6) * 0.7))
	w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": mids, "target": Vector2(mg.pos)})
	# ARMY71-8: the crews are not squads and the rifle squads stand behind the wall (no line of fire, so no contact
	# call and no hand signal in run 1 of gen 8). A second, small infiltration group of 6 crawlers comes at the rifle
	# squad nearest the MG from the inside, 7 tiles toward the base centre, so a squad gets a real contact.
	var CmbS = load("res://sim/systems/combat.gd")
	var rq = null
	var rq_d := INF
	for e in w.units_of(int(s.fid)):
		if int(e.get("squad", -1)) < 0 or CREWS.has(String(e.def)) or String(CmbS.stats(e).cls) != "small_arms":
			continue
		var dd := Vector2(e.pos).distance_to(Vector2(mg.pos))
		if dd < rq_d:
			rq_d = dd
			rq = e
	if rq != null:
		var inw := (C - Vector2(rq.pos)).normalized()
		var ip := Vector2(rq.pos) + inw * 7.0
		var iids := []
		for i in 6:
			iids.append(w.spawn_unit("m_scout_crawler", int(s.mfid), ip + side * (float(i % 3) - 1.0) * 0.7 + inw * float(i / 3) * 0.7))
		w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": iids, "target": Vector2(rq.pos)})
	mv.center_camera_on(Vector2(mg.pos) - out * 4.0)
	var L = _layer(pt)
	pt._log("army71_layer_attached", L != null, "signals71_layer under MatchView (g71_attach)")
	# one 30 s watch for both: the first contact calls come seconds after the spawn and a hand signal lives SIG_S
	# (2.5 s), so a signal wait that starts after the crew-mark wait misses them (run 2 of ARMY71-6)
	var got := {"crew": {}, "sig": 0}
	await pt._wait_until(func():
		if L == null:
			return false
		if _marks(L.crew):
			got.crew = (L.crew as Dictionary).duplicate(true)
		got.sig = maxi(int(got.sig), (L.sigs as Array).size())
		return not (got.crew as Dictionary).is_empty() and int(got.sig) > 0, 30.0)
	mv.join_sim()
	var w2: SimWorld = pt._w()
	var shots := []
	for e in w2.units_of(int(s.fid)):
		if e.has("c71"):
			shots.append("%s n=%d z=%s" % [e.def, int(e.c71.get("n", 0)), e.c71.has("z")])
	pt._log("army71_crew_marks", not (got.crew as Dictionary).is_empty(), "crew marks in the snapshot: %s | providers %s | crews that fired %s" % [str(got.crew).left(160), RenderSnap.g71_keys(), shots])
	await pt._shot("army71_crews_firing")
	pt._log("army71_hand_signal", int(got.sig) > 0, "hand signals live (max seen) %d" % int(got.sig))
	var feed = pt.get_tree().root.find_child("RadioFeed71", true, false)
	var said: bool = await pt._wait_until(func(): return feed != null and not (feed.shown as Array).is_empty(), 20.0)
	pt._log("army71_radio_feed", said, "radio lines: %s" % [str(feed.shown if feed != null else []).left(200)])
	await pt._shot("army71_signals_radio")
	# ARMY71-9: a close shot of one hand signal + a live radio line (the wide shot above left the signal glyph unreadable
	# and the feed line had faded). A fresh group of 6 crawlers comes at the same rifle squad, the camera zooms onto it,
	# and the shot is taken on the first frame where a signal is live AND the feed shows a line.
	mv.join_sim()
	var w3: SimWorld = pt._w()
	var sq_at := Vector2(mg.pos)
	# a squad that has had no contact yet (run 2 of gen 9: the first squad was still in contact, so no new call):
	# the rifle squad nearest the MG that stands > 15 tiles from the first one
	var rq2 = null
	var rq2_d := INF
	if rq != null:
		for e in w3.units_of(int(s.fid)):
			if int(e.get("squad", -1)) < 0 or int(e.get("squad", -1)) == int(rq.get("squad", -1)) or CREWS.has(String(e.def)) or String(CmbS.stats(e).cls) != "small_arms":
				continue
			if Vector2(e.pos).distance_to(Vector2(rq.pos)) <= 15.0:
				continue
			# ARMY71-10 (gen 10 runs 2-3: no fresh call in 45 s): skip a squad that called contact in the last 12 s
			# (Discipline71 contact_quiet_s 8: it would stay silent)
			var rec2 = D71._rec(w3, int(e.squad))
			if rec2 != null and w3.tick - int(rec2.last_t) < D71._ticks(12.0):
				continue
			var dd2 := Vector2(e.pos).distance_to(Vector2(mg.pos))
			if dd2 < rq2_d:
				rq2_d = dd2
				rq2 = e
	if rq2 == null:
		rq2 = rq
	print("PLAYTEST-DBG army71 close: rq2 %s squad %s" % [str(rq2.id) if rq2 != null else "-", str(rq2.get("squad", -1)) if rq2 != null else "-"])
	if rq2 != null and w3.entities.has(int(rq2.id)):
		sq_at = Vector2(w3.entities[int(rq2.id)].pos)
		var inw3 := (C - sq_at).normalized()
		var iids3 := []
		for i in 6:
			iids3.append(w3.spawn_unit("m_scout_crawler", int(s.mfid), sq_at + inw3 * 3.5 + side * (float(i % 3) - 1.0) * 0.7 + inw3 * float(i / 3) * 0.7))
		# gen 10 run 5: at 6 tiles the base turrets killed all 6 before the squad had them in its pool (no call): 3.5 tiles
		w3.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": iids3, "target": sq_at})
		var ex3 := iids3.filter(func(i): return w3.entities.has(int(i)))
		print("PLAYTEST-DBG army71 close spawn: at %s squad pos %s garrisoned %s ids %s alive %d tick %d" % [str(sq_at + inw3 * 3.5), str(sq_at), str(rq2.get("garrisoned_in", -1)), str(iids3), ex3.size(), w3.tick])
	mv.center_camera_on(sq_at)
	mv.camera.set_zoom_level(2.5)
	var close := {"sig": null}
	# a fresh signal only (it fades over SIG_S: run 1 of gen 9 caught one at ~2 s, nearly invisible)
	# first 25 s: a fresh signal while the feed shows a line; then 20 s: a fresh signal alone (the feed is checked by
	# army71_radio_feed above; run 5 of gen 9 had no frame with both inside 40 s)
	# gen 10 run 7: the squad called contact 4 s after the spawn but the feed was quiet (one voice per cluster), so
	# the signal-with-feed phase threw away the only fresh signal: a fresh signal alone (army71_radio_feed checks the feed)
	var both := {"need": false}
	var fresh := func():
		if L == null or (L.sigs as Array).is_empty():
			return false
		if bool(both.need) and (feed == null or String(feed.text) == ""):
			return false
		var g = (L.sigs as Array).back()
		if float(L._t) - float(g.t0) > 0.5:
			return false
		close.sig = g
		return true
	var live: bool = await pt._wait_until(fresh, 25.0)
	if not live:
		both.need = false
		live = await pt._wait_until(fresh, 20.0)
	if not live and rq2 != null:
		mv.join_sim()
		var wd: SimWorld = pt._w()
		var sqn := 0
		var tg := 0
		for e in wd.units_of(int(s.fid)):
			if int(e.get("squad", -1)) == int(rq2.get("squad", -1)):
				sqn += 1
				if int(e.get("target", -1)) >= 0:
					tg += 1
		var cr := 0
		var crd := INF
		for e in wd.units_of(int(s.mfid)):
			var dd := Vector2(e.pos).distance_to(sq_at)
			if dd < 12.0:
				cr += 1
				crd = minf(crd, dd)
		var rc = D71._rec(wd, int(rq2.get("squad", -1)))
		print("PLAYTEST-DBG army71 close miss: tick %d squad %d alive %d with target %d | machines < 12 t %d nearest %.1f | rec %s | sigs %d" % [wd.tick, int(rq2.get("squad", -1)), sqn, tg, cr, crd, str(rc), (L.sigs as Array).size()])
	if live:
		mv.center_camera_on(Vector2(close.sig.pos))
		await pt._wait(0.1)
	pt._log("army71_signal_close", live, "close shot: signal %s at %s, feed line '%s'" % [String(close.sig.word) if close.sig != null else "-", str(close.sig.pos) if close.sig != null else "-", String(feed.text) if feed != null else "-"])
	await pt._shot("army71_signals_close")
	mv.camera.set_zoom_level(1.0)
	mv.join_sim()
	mv.selection.clear()
	mv.selection.append(int(mg.id))
	await pt._wait(1.0)
	var panel = pt.get_tree().root.find_child("AmmoPanel71Panel", true, false)
	pt._log("army71_ammo_panel", panel != null, "ammo panel %s" % ("shown" if panel != null and panel.visible else "present, hidden (no tier for this weapon)" if panel != null else "missing"))
	await pt._shot("army71_ammo_panel")
	await _g10_steps(pt, L, s, mg, C, out, side)


## ARMY71-10: what the owner could not see yet. Each step says what the flow forces.
##   1. cover poses: a rifle squad set to bounding overwatch and ordered 10 tiles along the wall (forced order): the
##      moving team's arrows vs the halted team's covering arcs; then any squad hugging / peeking from cover.
##   2. night: Senses7 light forced to 0.2: our squad soldiers' NVG glints and look wedges.
##   3. wall-walk melee: 3 riflemen spawned on the wall-walk cells nearest the MG nest, 2 crawlers 1 tile outside each.
##   4. the flame tank: one a_g71_flame_tank spawned inside the base, 8 crawlers 4 tiles from it.
func _g10_steps(pt, L, s: Dictionary, mg, C: Vector2, _out: Vector2, side: Vector2) -> void:
	const Senses7 = preload("res://sim/systems/senses7.gd")
	const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
	const CnFacility = preload("res://sim/systems/cn_facility.gd")
	var mv = pt._mv()
	var CmbS = load("res://sim/systems/combat.gd")
	# ---- 1. cover poses
	mv.join_sim()
	var w: SimWorld = pt._w()
	var sq := {}
	for e in w.units_of(int(s.fid)):
		var sid := int(e.get("squad", -1))
		if sid < 0 or CREWS.has(String(e.def)) or String(CmbS.stats(e).cls) != "small_arms":
			continue
		if not sq.has(sid):
			sq[sid] = []
		sq[sid].append(int(e.id))
	var pick := -1
	var pick_d := INF
	for sid in sq:
		if (sq[sid] as Array).size() < 4:
			continue
		var d0 := Vector2(w.entities[sq[sid][0]].pos).distance_to(Vector2(mg.pos))
		if d0 < pick_d:
			pick_d = d0
			pick = sid
	var seen := {}
	if pick >= 0:
		var ids: Array = sq[pick]
		var at := Vector2(w.entities[ids[0]].pos)
		var dest := at + side * 10.0
		w.submit({"type": "set_technique", "issuer": int(s.fid), "unit_ids": ids, "technique": "bounding_overwatch"})
		w.submit({"type": "move", "issuer": int(s.fid), "unit_ids": ids, "target": dest})
		mv.center_camera_on(at + side * 3.0)
		mv.camera.set_zoom_level(2.5)
	var bound := func():
		var po: Array = (L.crew if L.crew is Dictionary else {}).get("po", [])
		var k := {}
		for q in po:
			k[int(q[2])] = true
			seen[int(q[2])] = int(seen.get(int(q[2]), 0)) + 1
			if q.size() > 4 and int(q[4]) == 1:
				seen["ow"] = int(seen.get("ow", 0)) + 1
		# the moving team shows (3); the halted team is overwatch (po[4]; it hugs / peeks when it has cover: run 2)
		if k.has(3):
			for q in po:
				if int(q[2]) == 3:
					mv.center_camera_on(Vector2(q[0], q[1]))
					break
			return true
		return false
	var bok: bool = await pt._wait_until(bound, 25.0)
	await pt._wait(0.1)
	pt._log("army71_pose_bound", bok, "squad %d bounding: poses seen %s (3 = moving team arrow, 4 = overwatch in the open, ow = overwatch arcs)" % [pick, seen])
	await pt._shot("army71_pose_bounding")
	var cover := func():
		var po: Array = (L.crew if L.crew is Dictionary else {}).get("po", [])
		var best = null
		for q in po:
			if int(q[2]) == 1 or int(q[2]) == 2:
				seen[int(q[2])] = int(seen.get(int(q[2]), 0)) + 1
				if best == null:
					best = q
		if best != null:
			mv.center_camera_on(Vector2(best[0], best[1]))
			return true
		return false
	var cok: bool = await pt._wait_until(cover, 25.0)
	await pt._wait(0.1)
	pt._log("army71_pose_cover", cok, "hug / peek from cover: poses seen %s (1 hug, 2 peek)" % [seen])
	await pt._shot("army71_pose_cover")
	# ---- 2. night: NVG
	mv.join_sim()
	w = pt._w()
	Senses7.set_light(w, 0.2)
	var nvq := {"q": null}
	var nok: bool = await pt._wait_until(func():
		var nv: Array = (L.crew if L.crew is Dictionary else {}).get("nv", [])
		if nv.is_empty():
			return false
		nvq.q = nv[0]
		return true, 15.0)
	if nok:
		mv.center_camera_on(Vector2(nvq.q[0], nvq.q[1]))
		mv.camera.set_zoom_level(2.5)
		await pt._wait(0.4)
	var nn: int = ((L.crew if L.crew is Dictionary else {}).get("nv", []) as Array).size()
	pt._log("army71_nvg_night", nok, "light forced 0.2: %d soldiers show NVG / thermal gear" % nn)
	await pt._shot("army71_nvg_night")
	mv.join_sim()
	w = pt._w()
	Senses7.set_light(w, 1.0)
	# ---- 3. wall-walk melee
	var fac := -1
	for id in w.entities:
		var b: Dictionary = w.entities[id]
		if b.kind == "building" and String(b.def) == "a_cn_facility" and int(b.owner) == int(s.fid):
			fac = int(id)
			break
	var cells: Array = []
	if fac >= 0:
		var F := CnFacility.fac(w, fac)
		if not F.is_empty():
			cells = WallWalk7.ring_cells(w, F)
	var mp := Vector2(mg.pos)
	cells.sort_custom(func(a, b): return Vector2(a).distance_squared_to(mp) < Vector2(b).distance_squared_to(mp))
	var tops := []
	for i in mini(3, cells.size()):
		var c := Vector2(cells[i]) + Vector2(0.5, 0.5)
		var tid := w.spawn_unit("rifleman", int(s.fid), c)
		tops.append(tid)
		var oo := (c - C).normalized()
		var cids := []
		for j in 2:
			cids.append(w.spawn_unit("m_scout_crawler", int(s.mfid), c + oo * 1.0 + Vector2(-oo.y, oo.x) * (float(j) - 0.5) * 0.6))
		w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": cids, "target": c})
	var on_w := 0
	for tid in tops:
		if w.entities.has(tid) and WallWalk7.on_wall(w, w.entities[tid]):
			on_w += 1
	if not tops.is_empty():
		mv.center_camera_on(Vector2(w.entities[tops[0]].pos))
	mv.camera.set_zoom_level(2.5)
	var mc := {"g": null}
	var mok: bool = await pt._wait_until(func():
		if (L.clashes as Array).is_empty():
			return false
		mc.g = (L.clashes as Array).back()
		return float(L._t) - float(mc.g.t0) < 0.3, 25.0)
	if mok:
		mv.center_camera_on(Vector2(mc.g.pos))
		await pt._wait(0.05)
	pt._log("army71_wall_melee", mok, "facility %d, %d wall-walk cells, %d/%d riflemen on the wall, clash %s" % [fac, cells.size(), on_w, tops.size(), String(mc.g.kind) if mc.g != null else "-"])
	await pt._shot("army71_wall_melee")
	# ---- 4. flame tank
	mv.join_sim()
	w = pt._w()
	var fx = mv.get("fx_layer")
	var f0: int = int(fx.get("flames")) if fx != null and fx.get("flames") != null else 0
	var tp := mp + (C - mp) * 0.35
	var tk := w.spawn_unit("a_g71_flame_tank", int(s.fid), tp)
	var inn := (C - tp).normalized()
	var fids := []
	for i in 8:
		fids.append(w.spawn_unit("m_scout_crawler", int(s.mfid), tp + inn * (4.0 + float(i / 4) * 0.7) + Vector2(-inn.y, inn.x) * (float(i % 4) - 1.5) * 0.7))
	w.submit({"type": "attack_move", "issuer": int(s.mfid), "unit_ids": fids, "target": tp})
	mv.center_camera_on(tp + inn * 2.0)
	mv.camera.set_zoom_level(2.0)
	var fok: bool = await pt._wait_until(func():
		var f1: int = int(fx.get("flames")) if fx != null and fx.get("flames") != null else 0
		return f1 > f0, 20.0)
	await pt._wait(0.02)   # gen 10 run 8: after 0.15 s the jet had already faded from the shot
	var f2: int = int(fx.get("flames")) if fx != null and fx.get("flames") != null else 0
	pt._log("army71_flame_tank", fok, "flame tank %d: flame jets %d -> %d" % [tk, f0, f2])
	await pt._shot("army71_flame_tank")
	mv.camera.set_zoom_level(1.0)
