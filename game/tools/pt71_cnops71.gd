extends RefCounted
## G7.1 CNOPS71 D7 playtest (windowed, Last Protocol): one area-search order, the team handles the rest.
## Starts a Last Protocol run (seed 77), stages a creep patch + Machine nest 46 tiles south of the base centre (Machine
## fire held), then submits ONE cn_search over the area (w.submit, the same path as the card) and follows the team:
##   cnops71_1_enroute.png       the strike APCs on the way (convoy)
##   cnops71_card_enroute.png    F4 ops room team card: the mission line (CnMission71.card_line) en route
##   cnops71_2_dismount.png      at the node: dismounted, posts taken, overwatch gunner sent up (when there is high ground)
##   cnops71_card_purging.png    team card while purging
##   cnops71_3_contact.png       3 Machines spawned beside the team + one member wounded: contact by ROE (standard: fire
##                               support), the casualty walks back to the APC
##   cnops71_card_exfil.png      team card once the team exfils / is home
## Forced by the flow: explored fog, the creep patch, Machine fire held, the contact (3 spawned Machines) and one
## member's health set to 20 %. Everything else (search sweep, purge, chain, overwatch, casevac, exfil) is the sim.
const CN = preload("res://sim/systems/counter_nanite.gd")
const M8 = preload("res://sim/systems/cn_mission8.gd")
const C71 = preload("res://sim/systems/cnmission71.gd")
const Creep = preload("res://sim/systems/creep.gd")
const MapGen = preload("res://sim/map_gen.gd")

var pt
var tid := -1
var fid := 0


func _w() -> SimWorld:
	return pt._w()


func _X() -> Dictionary:
	return C71.rec(_w(), tid)


func _phase() -> String:
	return String(M8.mission_of(_w(), tid).get("phase", ""))


func _apc_pos() -> Vector2:
	var t = CN.team(_w(), tid)
	for aid in t.apcs:
		var a = _w().entities.get(int(aid))
		if a != null:
			return Vector2(a.pos)
	return M8._team_pos(_w(), t)


func _shot_at(p: Vector2, name: String) -> void:
	pt._mv().center_camera_on(p)
	await pt._wait(0.6)
	var sp: float = pt._mv().speed
	pt._mv().speed = 0.0
	await pt._wait(0.3)
	await pt._shot(name)
	pt._mv().speed = sp


func _card_shot(name: String) -> String:
	var card = pt.get_tree().root.find_child("TeamCard", true, false)
	if card == null or card.get("hub") == null:
		pt._log(name, false, "ops room team card not found")
		return ""
	var sp: float = pt._mv().speed
	pt._mv().speed = 0.0
	card.hub.open("teams")
	card.hub.select_team(tid)
	await pt._wait(0.8)
	var ml = card.find_child("MissionLine", true, false)
	var txt := String(ml.text) if ml != null else ""
	pt._log(name, txt != "", "team card mission line: %s" % txt.replace("\n", " | "))
	await pt._shot(name)
	card.hub.close()
	pt._mv().speed = sp
	await pt._wait(0.3)
	return txt


func run(p_) -> void:
	pt = p_
	if not MapGen.has_map("last_protocol"):
		pt._log("cnops71_map", false, "last_protocol map not registered")
		return
	var LP = SimWorld.LastProtocol
	var started: bool = pt.main.start_match(LP.make_config(77, "last_protocol"))
	pt._log("cnops71_match_started", started, "Last Protocol, seed 77")
	if not started:
		return
	var mv = pt._mv()
	var ok: bool = await pt._wait_until(func(): return _w().sys_state.has("lp") and bool(_w().sys_state.lp.get("filled", false)), 60.0)
	pt._log("cnops71_facility_filled", ok, "facility filled at tick %d" % _w().tick)
	if not ok:
		return
	mv.join_sim()
	var w := _w()
	var s: Dictionary = w.sys_state.lp
	fid = int(s.fid)
	var ex: PackedByteArray = w.fog[fid].explored
	ex.fill(1)
	w.fog[fid].explored = ex
	var C := Vector2(s.base.center)
	var site := C + Vector2(-6, 46)
	var cs = Creep.enable(w)
	var v: PackedByteArray = cs.v
	var c0 := w.cell_of(site)
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			if dx * dx + dy * dy <= 25 and w.in_bounds(c0 + Vector2i(dx, dy)):
				v[Creep._k(cs, c0 + Vector2i(dx, dy))] = 200
	cs.v = v
	Creep.add_nest(w, site, 5, 3.0, int(s.mfid))
	w.cfg["creep_spread"] = false
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and w.is_enemy(fid, int(e.owner)):
			e.cd_ticks = 1 << 30
	var tids := []
	for t_id in CN.team_ids(w):
		var t: Dictionary = CN.team(w, int(t_id))
		if String(t.kind) == "strike" and int(t.fid) == fid:
			tids.append(int(t_id))
	tids.sort()
	if tids.is_empty():
		pt._log("cnops71_team", false, "no strike team")
		return
	tid = int(tids[0])
	var rect := [C.x - 14.0, C.y + 40.0, C.x + 2.0, C.y + 54.0]
	var r: Dictionary = w.submit({"type": "cn_search", "issuer": fid, "team_id": tid, "rect": rect, "mode": "drive", "roe": "standard"})
	await pt._wait(0.4)
	mv.join_sim()
	pt._log("cnops71_search_ordered", bool(r.ok) and not _X().is_empty(), "one cn_search over %s (ROE standard): %s" % [str(rect), "ok" if r.ok else String(r.reason)])
	if _X().is_empty():
		return
	mv.speed = 4.0
	ok = await pt._wait_until(func(): return _phase() == "travel" or String(_X().step) not in ["search", "purge"], 240.0)
	pt._log("cnops71_enroute", _phase() == "travel", "%s (tick %d)" % [C71.card_line(_w(), tid), _w().tick])
	await pt._wait(3.0)
	await _shot_at(_apc_pos(), "cnops71_1_enroute")
	await _card_shot("cnops71_card_enroute")
	ok = await pt._wait_until(func(): var t = CN.team(_w(), tid); return t != null and t.get("dep") != null and bool(t.dep.get("dis", false)), 300.0)
	pt._log("cnops71_dismounted", ok, "on foot at the node, posts taken (%s)" % C71.card_line(_w(), tid))
	await pt._wait(2.5)
	var ow: Array = _X().get("ow", [])
	pt._log("cnops71_overwatch", _X().has("ow"), "overwatch %s" % ("gunner #%d up at %.0f,%.0f" % [int(ow[0]), float(ow[1]), float(ow[2])] if ow.size() >= 3 else "none (no cell above the site within ow_r)"))
	var t0 = CN.team(_w(), tid)
	await _shot_at(Vector2(t0.dep.site) if t0 != null and t0.get("dep") != null else site, "cnops71_2_dismount")
	await _card_shot("cnops71_card_purging")
	# ---- contact: 3 Machines beside the team, one member hurt
	w = _w()
	var t = CN.team(w, tid)
	var hurt := -1
	for id in t.members:
		var u = w.entities.get(int(id))
		if u != null and not bool(u.get("cn_hero", false)) and CN.role_of(u) == "gunner":
			u.hp = float(u.get("max_hp", u.hp)) * 0.2
			hurt = int(id)
			break
	var p := M8._team_pos(w, t)
	var mdef := ""
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and int(e.owner) == int(s.mfid):
			mdef = String(e.def)
			break
	var n := 0
	for i in 3:
		var id := w.spawn_unit(mdef, int(s.mfid), p + Vector2(9.0, float(i) * 1.5)) if mdef != "" else -1
		if id >= 0:
			w.entities[id].cd_ticks = 1 << 30
			n += 1
	preload("res://sim/systems/sim_index.gd").rebuild(w)
	ok = await pt._wait_until(func(): return not (_X().get("ct", {}) as Dictionary).is_empty(), 30.0)
	var ct: Dictionary = _X().get("ct", {})
	pt._log("cnops71_contact", ok, "%d Machines spawned; contact n=%d, reaction %s (%s)" % [n, int(ct.get("n", 0)), String(ct.get("react", "")), C71.card_line(_w(), tid)])
	await pt._wait_until(func(): var u = _w().entities.get(hurt); return u == null or String(u.order.get("type", "")) == "board", 10.0)
	var hu = _w().entities.get(hurt)
	pt._log("cnops71_casevac", hurt >= 0 and (hu == null or String(hu.order.get("type", "")) == "board"), "wounded gunner #%d %s" % [hurt, "aboard an APC" if hu == null else "ordered: %s" % String(hu.order.get("type", ""))])
	await _shot_at(p, "cnops71_3_contact")
	ok = await pt._wait_until(func(): return String(_X().step) in ["exfil", "done", "aborted", "failed"], 400.0)
	pt._log("cnops71_exfil", ok and String(_X().step) in ["exfil", "done"], "step %s: %s" % [String(_X().step), String(_X().get("why", ""))])
	var txt := await _card_shot("cnops71_card_exfil")
	pt._log("cnops71_card_area_line", txt.to_upper().contains("AREA") or txt.to_upper().contains("PURGE") or txt.to_upper().contains("EXFIL"), "mission card: %s" % txt.replace("\n", " | "))
	var rep: Array = _X().get("rep", [])
	pt._log("cnops71_radio", rep.size() > 0, "last radio reports: %s" % str(rep))
	mv.speed = 1.0
