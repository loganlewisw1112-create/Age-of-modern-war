extends "res://tests/test_base.gd"
## G7 RETURN8 regression (owner: several APCs returning together "can't come back in" to the counter-nanite facility).
## Causes fixed in sim/systems/fac_drive7.gd: (1) a stale route cache (route version restarts at 0 per new controller
## state) snapped a returning APC onto its old garage route; (2) an APC parking in an east garage reverses back up the
## access lane, and a follower that came up behind it stood in that reversing room while the first stood in its way:
## both waited for ever (_rev_claim_stop: the APC that reaches its reverse leg first owns the room).
## Real LP start (768 map): all 8 APCs (crews aboard) and some foot units are sent out with plain player moves, then
## every team is ordered home together (cn_return) and the foot units are ordered back inside (plain move). Every APC
## must end parked in its garage (controller state park at its garage, standing on the garage pose) with its crew still
## aboard, within RET_LIMIT; quiet, and with the Machine at the gate (outer gate hardened: the sally port cycles).

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const FacDrive7 = preload("res://sim/systems/fac_drive7.gd")
const T_EXIT = preload("res://tests/test_facexit8.gd")
const NOFIRE := 100000
const OUT_D := 33          # beyond the outer wall (Chebyshev from the base centre, wall at 30)
const RET_LIMIT := 6000    # 300 s from the return order to the last APC parked
const FOOT_LIMIT := 3600   # 180 s for the foot units to walk back into the compound
const PARK_TOL := 0.5      # tiles from the garage park pose
const HARD_PARK_LIMIT := 3600   # FACFLOW8C (13.9c-50): hardened, all 8 parked within 180 s of the return order


func _run(label: String, enemy_near: bool) -> void:
	var X = T_EXIT.new()
	X.failures = []
	var w: SimWorld = X._lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var fid := int(w.sys_state.lp.fid)
	var facs: Array = CnFacility.facilities(w, fid)
	if not check(not facs.is_empty(), "%s: LP facility raised" % label):
		return
	var F := CnFacility.fac(w, int(facs[0]))
	var cr := CnFacility.compound_rect(F)
	var C := Vector2(w.map.lp.base.center)
	var g: Dictionary = X._groups(w, fid, cr)
	var apcs: Array = g.apcs
	var foot: Array = g.foot
	check_eq(apcs.size(), 8, "%s: 8 APCs parked in the facility" % label)
	var crew := {}
	for id in apcs + foot:
		w.entities[id].cd_ticks = NOFIRE
		crew[id] = (w.entities[id].get("cargo", []) as Array).size()
		for u in w.entities[id].get("cargo", []):
			u.cd_ticks = NOFIRE
	var ncrew := 0
	for id in apcs:
		ncrew += int(crew[id])
	check(ncrew > 0, "%s: the APCs carry their crews (%d aboard)" % [label, ncrew])
	var tids := []
	for k in w.sys_state[CnFacility.KEY].teams:
		var TT: Dictionary = w.sys_state[CnFacility.KEY].teams[k]
		if int(TT.owner) == fid and not (TT.apcs as Array).is_empty():
			tids.append(int(k))
	tids.sort()
	# out: plain player moves (the right-click command)
	check(w.submit({"type": "move", "unit_ids": apcs, "target": C + Vector2(0, 44), "issuer": fid}).ok, "%s: APC move out accepted" % label)
	check(w.submit({"type": "move", "unit_ids": foot, "target": C + Vector2(0, 40), "issuer": fid}).ok, "%s: foot move out accepted" % label)
	# (Sentinels / engineers go back to automatic duty after own_timeout_s, 13.9c-12, so a foot unit counts once it
	# has been past the outer wall)
	var allout := false
	var was_out := {}
	for t in 6000:
		w.step()
		if t % 20 != 0:
			continue
		allout = true
		for tid in tids:
			if String(CnFacility.team(w, tid).phase) != "out":
				allout = false
		for id in apcs + foot:
			var e = w.entities.get(id)
			if e != null and X._cheb(Vector2(e.pos), C) >= OUT_D:
				was_out[id] = true
			if not was_out.has(id) or (apcs.has(id) and (e == null or X._cheb(Vector2(e.pos), C) < OUT_D)):
				allout = false
		if allout:
			break
	if not allout:
		var ph := []
		for tid in tids:
			ph.append([tid, String(CnFacility.team(w, tid).phase)])
		print("  FACRETURN8 %s: not all out: teams %s, out %s of %s" % [label, ph, was_out.keys(), apcs + foot])
	if not check(allout, "%s: every team out and every APC / foot unit past the outer wall before the return" % label):
		return
	w.run_ticks(100)
	# FACFLOW8C (13.9c-50): the Machine keeps coming: a threat by the compound (inside THREAT_PAD, off the road) is
	# respawned whenever the base's guns kill it, so the gate stays hardened for the whole return (T_EXIT.keep_threat)
	var en := -1
	var th_at := cr.end + Vector2(6, 8)
	if enemy_near:
		for i in CnFacility.secs(FacDrive7.GATE_S) + 80:
			en = T_EXIT.keep_threat(w, fid, th_at, en)
			w.step()
		var GT: Dictionary = F.get("gate", {})
		check(not GT.is_empty() and bool(GT.get("hard", false)), "%s: the Machine near: the outer gate is hardened (%s)" % [label, GT])
	# home: every team ordered back together; the foot units walk back inside
	for tid in tids:
		var r := w.submit({"type": "cn_return", "team": tid, "issuer": fid})
		check(r.ok, "%s: cn_return team %d accepted (%s)" % [label, tid, r.reason])
	var r2 := w.submit({"type": "move", "unit_ids": foot, "target": cr.get_center() + Vector2(0, 4), "issuer": fid})
	check(r2.ok, "%s: foot move home accepted (%s)" % [label, r2.reason])
	var c0 := CnFacility.conf()
	var parked_at := {}
	var foot_in := {}
	var both_open := false
	var unhard := 0
	for t in RET_LIMIT:
		if enemy_near:
			en = T_EXIT.keep_threat(w, fid, th_at, en)
		w.step()
		var GT: Dictionary = F.get("gate", {})
		if enemy_near and not bool(GT.get("hard", false)):
			unhard += 1
		if enemy_near and bool(GT.get("hard", false)) and String(GT.get("o", "")) == "open" and String(GT.get("i", "")) == "open":
			both_open = true
		if t % 10 != 0:
			continue
		for id in foot:
			var e = w.entities.get(id)
			if e != null and not foot_in.has(id) and cr.has_point(Vector2(e.pos)) and t < FOOT_LIMIT:
				foot_in[id] = t
		for id in apcs:
			if parked_at.has(id):
				continue
			var V := FacDrive7.vstate(w, id)
			var at := String(V.get("at", ""))
			if String(V.get("st", "")) != "park" or not at.begins_with("g"):
				continue
			var P := FacDrive7.garage_park(c0, int(at.substr(1))) + cr.position
			if Vector2(w.entities[id].pos).distance_to(P) <= PARK_TOL:
				parked_at[id] = t
		if parked_at.size() == apcs.size() and foot_in.size() == foot.size():
			break
	var last := 0
	for id in parked_at:
		last = maxi(last, int(parked_at[id]))
	var stuck := []
	for id in apcs:
		if not parked_at.has(id):
			var e = w.entities.get(id)
			var V := FacDrive7.vstate(w, id)
			stuck.append([id, (Vector2(e.pos) - cr.position).snapped(Vector2(0.1, 0.1)) if e != null else "dead", V.get("st", ""), V.get("at", "")])
	var gars := {}
	for id in parked_at:
		gars[String(FacDrive7.vstate(w, id).at)] = true
	print("  FACRETURN8 %s: APCs parked %d/%d (last +%d ticks = %.1f s), garages %d distinct, foot in %d/%d; stuck %s" % [label, parked_at.size(), apcs.size(), last, last / float(SimWorld.TICK_RATE), gars.size(), foot_in.size(), foot.size(), stuck])
	check_eq(parked_at.size(), apcs.size(), "%s: every APC ordered home parked in its garage within %d s (no deadlock on the approach, wash, inner gate or garage row)" % [label, RET_LIMIT / SimWorld.TICK_RATE])
	check_eq(gars.size(), parked_at.size(), "%s: one APC per garage" % label)
	for tid in tids:
		check_eq(String(CnFacility.team(w, tid).phase), "garage", "%s: team %d back in phase garage" % [label, tid])
	var lost := []
	for id in apcs:
		var e = w.entities.get(id)
		if e == null or (e.get("cargo", []) as Array).size() != int(crew[id]):
			lost.append(id)
	check(lost.is_empty(), "%s: every APC still carries its crew (%s)" % [label, lost])
	check_eq(foot_in.size(), foot.size(), "%s: every foot unit ordered home walked back into the compound within %d s" % [label, FOOT_LIMIT / SimWorld.TICK_RATE])
	if enemy_near:
		check(not both_open, "%s: outer and inner gates never open together while hardened (sally port)" % label)
		check_eq(unhard, 0, "%s: the gate stays hardened through the whole return (threat kept near)" % label)
		check(parked_at.size() == apcs.size() and last <= HARD_PARK_LIMIT, "%s: all 8 APCs parked within %d s of the return order (last %.1f s)" % [label, HARD_PARK_LIMIT / SimWorld.TICK_RATE, last / float(SimWorld.TICK_RATE)])


func test_all_apcs_return_together_quiet() -> void:
	_run("quiet", false)


func test_all_apcs_return_together_machine_at_the_gate() -> void:
	if not FacDrive7.GATES_ON:
		print("  FACRETURN8 hardened case NOT EXECUTED: FacDrive7.GATES_ON is false")
		return
	_run("machine near", true)
