extends RefCounted
## G7 playtest flow sent7 (SENT7-2; G7_REFERENCE 13.9c-10 .. 13.9c-13: Sentinels, the facility's guard force).
## In the real game: the player's counter-nanite facility rises with its starting Sentinel garrison, which runs itself
## (13.9c-12): pairs on the wall-walk, pairs in the towers, the entry booth manned, interior patrols. Then an assault by
## human infantry on the north face (alarm: pairs bound to the face, off-duty men to their stand-to positions, the
## quick reaction force turns out, everyone fights from cover with sectors), an assault by Machine crawlers on the
## east face, a reload run (both weapons dry -> ready-ammo locker -> back to the job) and a casualty drill (a man goes
## down, his buddy drags him to cover, the Mender comes forward). Shots at zoom 1 / 1.75 / 2.5.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-sent7   (ORCH registered "sent7")

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const S7 = preload("res://sim/systems/sentinels7.gd")
const Wounds = preload("res://sim/systems/wounds.gd")
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _shots(pt, mv, at: Vector2, tag: String, zooms: Array = [1.0, 1.75, 2.5]) -> void:
	for z in zooms:
		_zoom(mv, z)
		mv.center_camera_on(at)
		await pt._wait(0.8)
		await pt._shot("sent7_%s_z%d" % [tag, int(z * 100)])


## Counts over side me's Sentinels: on the wall top, garrisoned, holding in cover with a sector, rushing, crouched,
## reloading, with a target.
func _tally(w: SimWorld, me: int) -> Dictionary:
	var out := {"n": 0, "wall": 0, "in": 0, "hold": 0, "rush": 0, "crouch": 0, "reload": 0, "target": 0, "standto": 0}
	var S = S7.state(w)
	if S == null:
		return out
	for id in S7.sentinels_of(w, me):
		var e: Dictionary = w.entities[int(id)]
		var j: Dictionary = S.jobs.get(str(id), {})
		out.n += 1
		if WallWalk7.on_wall(w, e):
			out.wall += 1
		if e.has("garrisoned_in"):
			out["in"] += 1
		if bool(j.get("hold", false)) and e.has("f7_hd"):
			out.hold += 1
		if int(e.get("gait", 0)) >= 2 and bool(e.get("moving", false)):
			out.rush += 1
		if int(e.get("gait", 0)) == 1:
			out.crouch += 1
		if int(e.get("s7_rl", 0)) > w.tick:
			out.reload += 1
		if int(e.get("target", -1)) >= 0:
			out.target += 1
		if String(j.get("k", "")) == "standto":
			out.standto += 1
	return out


func _merge(acc: Dictionary, t: Dictionary) -> void:
	for k in t:
		acc[k] = maxi(int(acc.get(k, 0)), int(t[k]))


var _drills: Array = []


## WATCH7-3: side me's Sentinels on the wall-walk or a tower deck, per compound face [N, E, S, W] (nearest edge).
func _faces(w: SimWorld, me: int, cr: Rect2) -> Array:
	var nf := [0, 0, 0, 0]
	for id in S7.sentinels_of(w, me):
		var e: Dictionary = w.entities[int(id)]
		var gb = w.entities.get(int(e.get("garrisoned_in", -1)))
		if not (SimWorld.WallWalk7.on_wall(w, e) or (gb != null and String(gb.def) == "cn_tower")):
			continue
		var p: Vector2 = Vector2(e.pos)
		var dd := [absf(p.y - cr.position.y), absf(cr.end.x - p.x), absf(cr.end.y - p.y), absf(p.x - cr.position.x)]
		var bi := 0
		for q in 4:
			if float(dd[q]) < float(dd[bi]):
				bi = q
		nf[bi] += 1
	return nf


func _on_ev7(evs: Array) -> void:
	for ev in evs:
		if ev is Dictionary and String(ev.get("type", "")) == "SentinelCasualtyDrill":
			_drills.append(ev.duplicate())


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	mv.world_events.connect(_on_ev7)
	if Content.building("a_cn_facility").is_empty() or Content.unit("g7_sent_warden").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var foe := -1
	for f in w.factions:
		if int(f) != me and w.is_enemy(me, int(f)):
			foe = int(f)
			break
	var c: Vector2i = h._open(w, 30)
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(14, 14)
	var fid := w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): mv.join_sim(); return S7.sentinels_of(pt._w(), me).size() >= 20, 12.0)
	mv.join_sim()
	pt._log("sent7_garrison_mustered", raised, "facility %d, %d Sentinels" % [fid, S7.sentinels_of(w, me).size()])
	if not raised:
		return
	var F: Dictionary = CnFacility.fac(w, CnFacility.facilities(w, me)[0])
	var O: Vector2 = Vector2(CnFacility.origin(F))
	var cs := float(CnFacility.conf().get("compound", 28))
	await pt._wait(6.0)   # posts taken, patrols walking
	mv.join_sim()
	var t0 := _tally(w, me)
	pt._log("sent7_posts_manned", t0["in"] >= 8 and t0.wall >= 2, "garrisoned %d, on the wall top %d of %d" % [t0["in"], t0.wall, t0.n])
	await _shots(pt, mv, O + Vector2(cs * 0.5, 1.5), "walls")
	# WATCH7-3 (13.9c-38 "heavier sentinel patrol force on the walls"): Sentinels on the wall-walk / tower decks per face
	# counted once the quiet watch has settled (the beats are walked from the barracks first): up to 40 s
	var cr: Rect2 = CnFacility.compound_rect(F)
	var nf := [0, 0, 0, 0]   # N, E, S, W
	# WATCH7-4: the flow map keeps a hostile rifleman inside alarm_r (the alarm stays latched, the beats merge and the
	# men shift to the threatened faces), so the per-face count is only meaningful in a TRUE quiet watch: the fixture
	# removes hostile units inside the alarm zone, waits for the stand-down (S7.threat clear), then counts.
	var zr: Rect2 = cr.grow(float(S7._tac().get("alarm_r", 22.0)) + 6.0)
	var quiet := false
	var nquiet := 0
	for tries in 60:
		for e in w.entities.values():
			if int(e.owner) != me and w.is_enemy(me, int(e.owner)) and zr.has_point(Vector2(e.pos)) and String(e.get("kind", "unit")) != "building":
				w.destroy(int(e.id), "sent7 quiet-watch fixture")
		await pt._wait(2.0)
		mv.join_sim()
		quiet = S7.threat(w, int(F.id)) == null
		nquiet = nquiet + 1 if quiet else 0
		nf = _faces(w, me, cr)
		print("PLAYTEST sent7 faces try %d quiet %s N %d E %d S %d W %d" % [tries, str(quiet), nf[0], nf[1], nf[2], nf[3]])
		if nquiet >= 8 and int(nf[0]) >= 6 and int(nf[1]) >= 6 and int(nf[3]) >= 6:
			break   # 8 quiet samples (16 s) in a row, all three long faces manned
	print("PLAYTEST sent7 wall_faces N %d E %d S %d W %d quiet_samples %d" % [nf[0], nf[1], nf[2], nf[3], nquiet])
	pt._log("sent7_wall_faces_heavy", nquiet >= 8 and int(nf[0]) >= 6 and int(nf[1]) >= 6 and int(nf[3]) >= 6, "quiet watch (%d samples), Sentinels on the wall-walk / tower decks: N %d, E %d, S %d, W %d" % [nquiet, nf[0], nf[1], nf[2], nf[3]])
	await _shots(pt, mv, O + Vector2(cs * 0.5, 1.0), "walls_north", [1.75, 2.5])
	await _shots(pt, mv, O + Vector2(cs - 1.0, cs * 0.5), "walls_east", [1.75, 2.5])
	await _shots(pt, mv, O + Vector2(1.0, cs * 0.5), "walls_west", [1.75, 2.5])
	var tower = null
	for pid in F.get("parts", []):
		var b = w.entities.get(int(pid))
		if b != null and String(b.def) == "cn_tower" and not SimWorld.Garrison.occupants(w, int(pid)).is_empty():
			tower = b
			break
	pt._log("sent7_tower_manned", tower != null, "tower %s" % (str(int(tower.id)) if tower != null else "none"))
	if tower != null:
		await _shots(pt, mv, Vector2(tower.cell) + Vector2(1.0, 1.0), "tower")
	var cp = w.entities.get(int(F.get("cp", 0)))
	var at_cp := SimWorld.Garrison.occupants(w, int(cp.id)).size() if cp != null else 0
	pt._log("sent7_entry_manned", at_cp >= 2, "entry checkpoint holds %d Sentinels" % at_cp)
	if cp != null:
		await _shots(pt, mv, Vector2(cp.cell) + Vector2(1.0, 1.0), "entry")
	# ---- assault 1: human infantry on the north face
	var foes := []
	if foe >= 0:
		for i in 14:
			var en: Dictionary = h._unit(w, "rifleman", foe, O + Vector2(6.5 + float(i), -9.5 - float(i % 3)))
			en.order = {"type": "attack_move", "target": O + Vector2(cs * 0.5, cs * 0.5)}
			SimWorld.Movement.order_path(w, en, en.order.target)
			foes.append(int(en.id))
	var acc := {}
	var alarm := false
	var bshot := false
	var cas := -1
	var dshot := false
	for k in 120:
		await pt._wait(0.1)
		mv.join_sim()
		alarm = alarm or S7.threat(w, int(F.id)) != null
		_merge(acc, _tally(w, me))
		if k == 40:
			await _shots(pt, mv, O + Vector2(cs * 0.5, 0.0), "human_assault", [1.0, 1.75])
			mv.join_sim()
		if not bshot and k >= 10 and alarm:   # SENT7-5: one of a pair rushes while his buddy covers
			var bp = _bounding_pair(w, me)
			if bp != null:
				bshot = true
				pt._log("sent7_bounding_seen", true, "pair %d (rushing, gait %d) / %d (covering)" % [int(bp[1]), int(w.entities[int(bp[1])].gait), int(bp[2])])
				await _shots(pt, mv, bp[0], "bounding", [1.75, 2.5])
				mv.join_sim()
		if cas < 0 and k >= 20 and alarm:   # SENT7-5 casualty drill: a man is hit rushing in the open beside his buddy
			cas = _rush_casualty(w, me)
			if cas >= 0:
				var ce0: Dictionary = w.entities[cas]
				pt._log("sent7_man_down_on_rush", true, "Sentinel %d hit in the open (buddy %d)" % [cas, int(S7.job_of(w, cas).get("bud", -1))])
				SimWorld.HotState.set_hp(w, cas, Wounds.unc_hp(ce0) * 0.9)
				Wounds.go_down(w, ce0)
		if cas >= 0 and not dshot and w.entities.has(cas) and (w.entities[cas].has("wdby") or w.entities[cas].has("s7_dg")):
			dshot = true
			await pt._wait(0.6)
			mv.join_sim()
			if w.entities.has(cas):
				await _shots(pt, mv, Vector2(w.entities[cas].pos), "casualty_drag", [1.75, 2.5])
				mv.join_sim()
	await _shots(pt, mv, O + Vector2(cs * 0.5, 2.0), "human_assault_late", [2.5])
	pt._log("sent7_alarm_raised", alarm, "facility not secure during the assault")
	pt._log("sent7_tactics_seen", int(acc.get("hold", 0)) > 0 and int(acc.get("crouch", 0)) > 0, "max at once: holding in cover %d, rushing %d, crouched %d, reloading %d, with targets %d, at stand-to %d" % [
		int(acc.get("hold", 0)), int(acc.get("rush", 0)), int(acc.get("crouch", 0)), int(acc.get("reload", 0)), int(acc.get("target", 0)), int(acc.get("standto", 0))])
	# WATCH7-3: the oracle counts attackers still FIGHTING (on the map and not down): a downed man (Wounds.is_down,
	# bleeding out / unconscious) is out of the fight. This corrects what the check measures (WATCH7-2 found it counted
	# downed men as "left"); the bar (at most half left) is unchanged.
	var left := 0
	var downed := 0
	for id in foes:
		var fe = w.entities.get(int(id))
		if fe == null:
			continue
		if Wounds.is_down(fe):
			downed += 1
		else:
			left += 1
	pt._log("sent7_human_assault_held", left <= foes.size() / 2, "attackers still fighting %d of %d (%d more down), Sentinels %d" % [left, foes.size(), downed, S7.sentinels_of(w, me).size()])
	# ---- assault 2: the Machine on the east face
	var mfoes := []
	if foe >= 0:
		for i in 10:
			var en: Dictionary = h._unit(w, "m_scout_crawler", foe, O + Vector2(cs + 9.5 + float(i % 2), 5.5 + float(i) * 1.6))
			en.order = {"type": "attack_move", "target": O + Vector2(cs * 0.5, cs * 0.5)}
			SimWorld.Movement.order_path(w, en, en.order.target)
			mfoes.append(int(en.id))
	for k in 100:
		await pt._wait(0.1)
		if k == 35:
			mv.join_sim()
			await _shots(pt, mv, O + Vector2(cs - 1.0, cs * 0.4), "machine_assault", [1.0, 1.75, 2.5])
	mv.join_sim()
	var mleft := 0
	for id in mfoes:
		if w.entities.has(int(id)):
			mleft += 1
	pt._log("sent7_machine_assault_held", mleft <= mfoes.size() / 2, "crawlers left %d of %d, Sentinels %d" % [mleft, mfoes.size(), S7.sentinels_of(w, me).size()])
	# ---- reload run: a wall man's primary and sidearm both dry -> nearest ready-ammo locker -> back on the job
	var S = S7.state(w)
	var runner := -1
	for id in S7.sentinels_of(w, me):
		var e: Dictionary = w.entities[int(id)]
		var k := String(S.jobs.get(str(id), {}).get("k", ""))
		# WATCH7-3: a fighting wall man (not down: the rush casualty keeps his wall job while he lies there; not a
		# Mender, who now also walks the wall-walk)
		if not e.has("garrisoned_in") and (k == "wall" or k == "int") and String(e.s7) != "bearer" and String(e.s7) != "mender" 				and not Wounds.is_down(e):
			runner = int(id)
			break
	pt._log("sent7_reload_runner", runner >= 0, "Sentinel %d" % runner)
	if runner >= 0:
		var re: Dictionary = w.entities[runner]
		re.s7_sa = true
		re.ammo = 0
		var went: bool = await pt._wait_until(func(): mv.join_sim(); return String(S7.job_of(pt._w(), runner).get("k", "")) == "ammo", 6.0)
		pt._log("sent7_reload_run_started", went, "job %s" % str(S7.job_of(w, runner).get("k", "")))
		if went:
			await pt._wait(1.0)
			mv.join_sim()
			await _shots(pt, mv, Vector2(w.entities[runner].pos), "reload_run", [1.75])
		var done: bool = await pt._wait_until(func(): mv.join_sim(); var e = pt._w().entities.get(runner); return e != null and not bool(e.get("s7_sa", false)) and int(e.get("ammo", 0)) > 0, 25.0)
		pt._log("sent7_rearmed_at_locker", done, "ammo %d, back on job %s" % [int(w.entities[runner].get("ammo", 0)) if w.entities.has(runner) else -1, str(S7.job_of(w, runner).get("k", ""))])
	# ---- casualty drill: one of a field pair goes down (SENT7-5: normally already hit on a rush during the assault;
	# this after-the-fight pick is the fallback)
	var on_rush := cas >= 0 and w.entities.has(cas)
	if not on_rush:
		cas = -1
	for id in (S7.sentinels_of(w, me) if not on_rush else []):
		var e: Dictionary = w.entities[int(id)]
		var j: Dictionary = S.jobs.get(str(id), {})
		var bd := int(j.get("bud", -1))
		if not e.has("garrisoned_in") and bd >= 0 and String(e.s7) != "mender" and w.entities.has(bd) \
				and not w.entities[bd].has("garrisoned_in") and not Wounds.is_down(w.entities[bd]):
			cas = int(id)
			break
	pt._log("sent7_casualty_pair", cas >= 0, "casualty %d" % cas)
	if cas >= 0:
		var ce: Dictionary = w.entities[cas]
		var dragged := dshot
		if not on_rush:
			SimWorld.HotState.set_hp(w, cas, Wounds.unc_hp(ce) * 0.9)
			Wounds.go_down(w, ce)
		if not dragged:
			dragged = await pt._wait_until(func(): mv.join_sim(); var e = pt._w().entities.get(cas); return e != null and (e.has("wdby") or e.has("s7_dg")), 10.0)
			mv.join_sim()
			if dragged:
				await _shots(pt, mv, Vector2(ce.pos), "casualty_drag", [1.75, 2.5])
		print("PLAYTEST sent7 drag_events %s" % str(_drills))
		if dragged:   # REGFIX7-3: cover is read where the drag ENDS (s7_dg is set when the drag is ordered, before the
			# dragger reached him; FACINT7's 0.30 was read mid-drag): wait for the Wounds drag job on him to finish
			await pt._wait_until(func(): mv.join_sim(); return not _drag_on(pt._w(), cas), 20.0)
			mv.join_sim()
		var cbd := int(S.jobs.get(str(cas), {}).get("bud", -1))
		var cb = w.entities.get(cbd)
		var wst = w.sys_state.get("wounds")
		pt._log("sent7_drill_state", true, "casualty %d at %s cover %.2f s7_dg %s; buddy %d alive %s down %s job %s caring %s; threat %s" % [cas, str(ce.pos),
			S7._cover_v(w, w.cell_of(ce.pos), S7._team(w, me)), str(ce.has("s7_dg")), cbd, str(cb != null), str(cb != null and Wounds.is_down(cb)),
			str(S.jobs.get(str(cbd), {}).get("k", "")) + "/" + str(S.jobs.get(str(cbd), {}).get("drg", -1)), str(wst != null and (wst.care as Dictionary).has(cbd)), str(S7.threat(w, int(F.id)) != null)])
		var cov := S7._cover_v(w, w.cell_of(ce.pos), S7._team(w, me))
		for dv in _drills:   # REGFIX7-3 diagnostic: cover at every ordered drag spot, and where he lies now
			print("PLAYTEST sent7 drag_spot id %d by %d to %s cover %.2f; now at %s cover %.2f wdby %s" % [int(dv.id), int(dv.by), str(dv.to), S7._cover_v(w, w.cell_of(Vector2(dv.to)), S7._team(w, me)), str(ce.pos), cov, str(ce.get("wdby", -1))])
		pt._log("sent7_casualty_in_cover", not dragged or cov >= float(S7._tac().get("open_v", 0.35)), "cover %.2f where he was dragged" % cov)
		pt._log("sent7_buddy_drags", dragged, "casualty %d (hit on a rush: %s) down %s, dragged by %s" % [cas, str(on_rush), str(Wounds.is_down(ce)), str(ce.get("wdby", -1))])
		var mender: bool = await pt._wait_until(func(): mv.join_sim(); return _mender_near(pt._w(), cas, me), 30.0)
		mv.join_sim()
		pt._log("sent7_mender_forward", mender, "Mender at the casualty")
		if mender:
			await _shots(pt, mv, Vector2(ce.pos), "mender_treats", [2.5])


## A pair under alarm with one man rushing (moving, gait >= 2) and his buddy stationary: [midpoint, rusher, buddy].
func _bounding_pair(w: SimWorld, me: int):
	var S = S7.state(w)
	for id in S7.sentinels_of(w, me):
		var e: Dictionary = w.entities[int(id)]
		var bd := int(S.jobs.get(str(id), {}).get("bud", -1))
		var b = w.entities.get(bd)
		if b == null or e.has("garrisoned_in") or b.has("garrisoned_in") or Wounds.is_down(b):
			continue
		if bool(e.get("moving", false)) and int(e.get("gait", 0)) >= 2 and not bool(b.get("moving", false)) 				and Vector2(b.pos).distance_to(e.pos) <= 12.0:
			return [(Vector2(e.pos) + Vector2(b.pos)) * 0.5, int(id), bd]
	return null


## A field-pair man rushing in the open (gait >= 2, cover below open_v) with his buddy within two bounds, else -1.
func _rush_casualty(w: SimWorld, me: int) -> int:
	var S = S7.state(w)
	var ov := float(S7._tac().get("open_v", 0.35))
	var r := 2.0 * float(S7._tac().get("bound_len", 5.0)) + 1.0
	for id in S7.sentinels_of(w, me):
		var e: Dictionary = w.entities[int(id)]
		if e.has("garrisoned_in") or String(e.s7) == "mender" or Wounds.is_down(e):
			continue
		if not bool(e.get("moving", false)) or int(e.get("gait", 0)) < 2:
			continue
		if S7._cover_v(w, w.cell_of(e.pos), S7._team(w, me)) >= ov:
			continue
		var b = w.entities.get(int(S.jobs.get(str(id), {}).get("bud", -1)))
		if b == null or b.has("garrisoned_in") or Wounds.is_down(b) or Vector2(b.pos).distance_to(e.pos) > r:
			continue
		return int(id)
	return -1


func _mender_near(w: SimWorld, cas: int, me: int) -> bool:
	var e = w.entities.get(cas)
	if e == null:
		return false
	for id in S7.sentinels_of(w, me):
		var m: Dictionary = w.entities[int(id)]
		if String(m.s7) == "mender" and Vector2(m.pos).distance_to(e.pos) <= 1.6:
			return true
	return false


## REGFIX7-3: a Wounds care job is dragging casualty cid (walking to him or pulling him to the drag spot).
func _drag_on(w: SimWorld, cid: int) -> bool:
	var st = w.sys_state.get("wounds")
	if st == null:
		return false
	for k in st.care:
		var cv = st.care[k]
		if cv is Dictionary and String(cv.get("k", "")) == "drag" and int(cv.get("c", -1)) == cid:
			return true
	return false
