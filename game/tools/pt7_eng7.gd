extends RefCounted
## G7 playtest flow eng7 (ENG7, G7_REFERENCE 13.9c-11 Facility Engineer, 13.9c-12 staff run themselves).
## In the real game: the player's counter-nanite facility rises with its work crew. Nobody gives an order: a damaged
## blast wall gets repaired, an emptied ready-ammo locker gets refilled from the special ammo magazine (forklift run),
## a parked APC low on fuel and a landed dropship get refuelled (fuel bowser). Then the player right-clicks one engineer
## somewhere else: it obeys, and when the order is done it goes back to work by itself. Shots of each job at zoom
## 1 / 1.75 / 2.5.
## Run: "$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-eng7   (ORCH registered "eng7")

const H = preload("res://tests/test_machine_g6.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const E7 = preload("res://sim/systems/engineer7.gd")
const S7 = preload("res://sim/systems/sentinels7.gd")
const Air = preload("res://sim/systems/air.gd")


func _zoom(mv, z: float) -> void:
	var cam = mv.camera
	if cam == null:
		return
	if cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)
	else:
		cam.zoom = Vector2(z, z)


func _shots(pt, mv, at: Vector2, tag: String, follow: int = -1) -> void:
	for z in [1.0, 1.75, 2.5]:
		_zoom(mv, z)
		if follow >= 0:
			mv.join_sim()
			var fw: SimWorld = pt._w()
			if fw.entities.has(follow):
				at = Vector2(fw.entities[follow].pos)
		mv.center_camera_on(at)
		await pt._wait(0.6)
		await pt._shot("eng7_%s_z%d" % [tag, int(z * 100)])


## Engineer of facility fac doing kind (board record k) and (when drv != "") driving drv; -1 when none.
func _doing(w: SimWorld, fac: int, kind: String, drv: String = "") -> int:
	for uid in E7.engineers_of(w, fac):
		var e = w.entities.get(int(uid))
		if e == null:
			continue
		var run: Dictionary = E7.state(w).run.get(str(uid), {})
		if String(run.get("k", "")) != kind:
			continue
		if drv != "" and String(e.get("eng7_drv", "")) != drv:
			continue
		return int(uid)
	return -1


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.unit("g7_fac_engineer").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[me].stock[k] = 50000
	w.factions[me].credits = 50000
	var c: Vector2i = h._open(w, 24)
	var off: Array = CnFacility.conf().core_offset
	var o := c - Vector2i(14, 14)
	w.spawn_building("a_cn_facility", me, o + Vector2i(int(off[0]), int(off[1])), true)
	var raised: bool = await pt._wait_until(func(): mv.join_sim(); return not CnFacility.facilities(pt._w(), me).is_empty(), 8.0)
	pt._log("eng7_facility_raised", raised, "facility raised")
	if not raised:
		return
	mv.join_sim()
	w = pt._w()
	var fac := int(CnFacility.facilities(w, me)[0])
	var F: Dictionary = CnFacility.fac(w, fac)
	var O := Vector2(CnFacility.origin(F))
	var crew_ok: bool = await pt._wait_until(func(): mv.join_sim(); return E7.engineers_of(pt._w(), fac).size() >= 3, 6.0)
	mv.join_sim()
	pt._log("eng7_crew_mustered", crew_ok, "%d engineers on the facility job board" % E7.engineers_of(w, fac).size())
	await _shots(pt, mv, E7._home(F), "crew_standby")
	# ---- 1. repair: a damaged blast wall, no order given
	var wall := -1
	var best := INF
	var wp := O + Vector2(14.0, 0.0)
	for pid in F.parts:
		var b = w.entities.get(int(pid))
		if b != null and String(b.def) == "cn_blast_wall":
			var d := Vector2(b.cell).distance_to(wp)
			if d < best:
				best = d
				wall = int(pid)
	if wall >= 0:
		# FLOWB7 (suite 2026-10-28): the facility's repair job is open to Menders and engineers alike (Sentinels7 board,
		# roles mender / engineer, one slot, nearest man first). With the 13.9c-38 watch (WATCH7-3: wall_roles adds the
		# mender, a patrol pair on every wall run) a Mender patrolling the north wall is always nearer than the crew in
		# its standby spot, takes the job and mends the wall himself (suite run: wall back at 3000 / 3000, no engineer
		# ever on a repair run). This step tests the Facility Engineer crew, so the facility's Menders are removed
		# first. The checks below are unchanged.
		var mend := 0
		for sid in w.entities.keys():
			var se: Dictionary = w.entities[sid]
			if se.kind == "unit" and int(se.owner) == me and String(se.get("s7", "")) == "mender":
				w.destroy(int(sid), "playtest", SimWorld.NEUTRAL)
				mend += 1
		print("ENG7 removed %d Menders before the wall is damaged" % mend)
		var wb: Dictionary = w.entities[wall]
		wb.hp = float(wb.max_hp) * 0.55
		var at_wall: bool = await pt._wait_until(func():
			mv.join_sim()
			var ww: SimWorld = pt._w()
			var u := _doing(ww, fac, "repair")
			return u >= 0 and String(ww.entities[u].order.get("type", "")) == "repair" and E7._bdist(ww.entities[u].pos, ww.entities[wall]) <= 1.6, 40.0)
		mv.join_sim()
		var ru := _doing(w, fac, "repair")
		var rp: Vector2 = Vector2(w.entities[ru].pos) if ru >= 0 else E7._bpos(w.entities[wall])
		pt._log("eng7_repair_started", at_wall, "an engineer walked to the damaged wall and is repairing it (unit %d at %s, wall cell %s size %d, %.2f tiles from its face)" % [ru, str(rp), str(w.entities[wall].cell), int(w.entities[wall].get("size", 1)), E7._bdist(rp, w.entities[wall])])
		await _shots(pt, mv, rp, "repair_wall")
		var fixed: bool = await pt._wait_until(func(): mv.join_sim(); var ww: SimWorld = pt._w(); return ww.entities.has(wall) and float(ww.entities[wall].hp) >= float(ww.entities[wall].max_hp) - 0.01, 60.0)
		mv.join_sim()
		pt._log("eng7_wall_repaired", fixed, "wall hp %.0f / %.0f" % [float(w.entities[wall].hp), float(w.entities[wall].max_hp)])
	else:
		pt._log("eng7_repair_started", false, "no blast wall found")
	# ---- 2. locker refill from the magazine (forklift)
	mv.join_sim()
	var lks := S7.lockers_of(w, me)
	if not lks.is_empty():
		var lid := int(lks[0])
		S7.locker_add(w, lid, -999)
		var drv: bool = await pt._wait_until(func(): mv.join_sim(); return _doing(pt._w(), fac, "locker", "forklift") >= 0, 60.0)
		mv.join_sim()
		var fu := _doing(w, fac, "locker", "forklift")
		pt._log("eng7_forklift_run", drv, "engineer %d hauls a pallet from the magazine on the forklift" % fu)
		if fu >= 0:
			await pt._wait(2.0)
			mv.join_sim()
			var vf: Array = _vehicle_on(pt, mv, fu, "forklift")
			pt._log("eng7_forklift_drawn", bool(vf[0]) and float(vf[1]) < 0.6, "display forklift on engineer %d: found %s, %.2f tiles off, hidden %s" % [fu, str(vf[0]), float(vf[1]), str(vf[2])])
			await _shots(pt, mv, Vector2(w.entities[fu].pos) if w.entities.has(fu) else E7._bpos(w.entities[lid]), "forklift", fu)
		var cap := int(S7.R().get("locker", {}).get("cap", 14))
		var full: bool = await pt._wait_until(func(): mv.join_sim(); return S7.locker_stock(pt._w(), lid) >= cap, 60.0)
		mv.join_sim()
		pt._log("eng7_locker_refilled", full, "locker %d stock %d / %d" % [lid, S7.locker_stock(w, lid), cap])
	else:
		pt._log("eng7_forklift_run", false, "no ready-ammo lockers")
	# ---- 3. refuel: APC parked in the staging yard and a landed dropship
	mv.join_sim()
	var st: Rect2 = CnFacility.zone(F, "staging")
	var vc: Vector2i = Movement.nearest_free_cell(w, w.cell_of(st.get_center()), "vehicle", me)
	var apc := w.spawn_unit("g7_cn_strike_apc", me, Vector2(vc) + Vector2(0.5, 0.5))
	w.entities[apc].fuel = 70.0
	var ds := w.spawn_unit("a_vtol_dropship", me, O + Vector2(14.5, 20.5))
	Air.land_now(w, w.entities[ds])
	w.entities[ds].fuel = 60.0
	var bow: bool = await pt._wait_until(func():
		mv.join_sim()
		var ww: SimWorld = pt._w()
		var u := _doing(ww, fac, "fuel", "fuel")
		return u >= 0 and String(E7.state(ww).run.get(str(u), {}).get("ph", "")) == "pump", 60.0)
	mv.join_sim()
	var fu2 := _doing(w, fac, "fuel", "fuel")
	pt._log("eng7_bowser_pumping", bow, "engineer %d pumps fuel from the bowser" % fu2)
	if fu2 >= 0:
		var vb: Array = _vehicle_on(pt, mv, fu2, "fuel")
		pt._log("eng7_bowser_drawn", bool(vb[0]) and float(vb[1]) < 0.6, "display fuel bowser on engineer %d: found %s, %.2f tiles off, hidden %s" % [fu2, str(vb[0]), float(vb[1]), str(vb[2])])
		await _shots(pt, mv, Vector2(w.entities[fu2].pos), "refuel")
	var tanked: bool = await pt._wait_until(func():
		mv.join_sim()
		var ww: SimWorld = pt._w()
		return ww.entities.has(apc) and float(ww.entities[apc].fuel) >= 519.0 and (not ww.entities.has(ds) or float(ww.entities[ds].fuel) >= 499.0), 90.0)
	mv.join_sim()
	pt._log("eng7_refuelled", tanked, "APC fuel %.0f, dropship fuel %.0f" % [float(w.entities[apc].fuel), float(w.entities[ds].get("fuel", -1.0)) if w.entities.has(ds) else -1.0])
	# ---- 4. player order, then back on duty
	mv.join_sim()
	var crew := E7.engineers_of(w, fac)
	if crew.is_empty():
		pt._log("eng7_player_order", false, "no engineer left")
		return
	var uid := int(crew[0])
	mv.selection.clear()
	mv.selection.append(uid)
	var tgt := O + Vector2(9.5, 18.5)
	var tc: Vector2i = Movement.nearest_free_cell(w, w.cell_of(tgt), "foot", me)
	tgt = Vector2(tc) + Vector2(0.5, 0.5)
	_zoom(mv, 1.0)
	mv.center_camera_on(tgt)
	await pt._wait(0.4)
	await pt._tut_rclick(tgt)
	var took: bool = await pt._wait_until(func(): mv.join_sim(); return String(S7.job_of(pt._w(), uid).get("k", "")) == "player", 5.0)
	mv.join_sim()
	pt._log("eng7_player_order", took, "right-click: the engineer is the player's (board record %s)" % str(S7.job_of(w, uid)))
	var there: bool = await pt._wait_until(func(): mv.join_sim(); var ww: SimWorld = pt._w(); return ww.entities.has(uid) and Vector2(ww.entities[uid].pos).distance_to(tgt) < 1.5, 30.0)
	mv.join_sim()
	pt._log("eng7_player_order_obeyed", there, "engineer reached the clicked point")
	var wb2 = w.entities.get(wall)
	if wb2 != null:
		wb2.hp = float(wb2.max_hp) * 0.7
	var back: bool = await pt._wait_until(func(): mv.join_sim(); return String(S7.job_of(pt._w(), uid).get("k", "")) != "player", 20.0)
	mv.join_sim()
	pt._log("eng7_back_on_duty", back, "after the order: automatic again (record %s)" % str(S7.job_of(w, uid)))
	await _shots(pt, mv, Vector2(w.entities[uid].pos) if w.entities.has(uid) else tgt, "back_on_duty")


## Display check (13.9c-11 engineer hook): the fac_life7 vehicle of kind ("forklift" / "fuel") driven by unit uid:
## [found, distance in tiles between the drawn vehicle and the unit, hidden].
func _vehicle_on(pt, mv, uid: int, kind: String) -> Array:
	var L = mv.get("fac_life7")
	if L == null or not pt._w().entities.has(uid):
		return [false, -1.0, false]
	L.eval_all()
	var up := Vector2(pt._w().entities[uid].pos)
	for Lf in L.life:
		for a in Lf.actors:
			if String(a.kind) == kind and int(a.get("driver", -1)) == uid:
				return [true, Vector2(a.p).distance_to(up), bool(a.hidden)]
	return [false, -1.0, false]
