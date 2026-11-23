extends "res://tests/test_base.gd"
## G7.1 J6 (owner: CNOPS71): the trauma + decon hospital ward machine (sim/systems/hospital71.gd). Triage order, bed
## limits, surgery -> ICU -> recovery -> back to the fight, prosthetics, quarantine lock (test stand-in for J5), unused =
## no state, save / load mid-ward keeps the same future. The ward machine is driven by Hospital71.tick alone here
## (w.tick advanced by hand, no w.step), so other systems cannot heal or hurt the patients.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const H = preload("res://sim/systems/hospital71.gd")

static var _base: Dictionary = {}


func _lp() -> SimWorld:
	if not preload("res://sim/map_gen.gd").has_map("last_protocol"):
		return null
	if _base.is_empty():
		var w0 := SimWorld.new_match(LastProtocol.make_config(77, "last_protocol"))
		if w0 == null:
			return null
		w0.run_ticks(5)
		_base = w0.to_dict().duplicate(true)
	return SimWorld.from_dict(_base.duplicate(true))


func _fid(w: SimWorld) -> int:
	return int(w.sys_state.lp.fid)


## {bid, def}: one of our buildings stands in for the hospital (the 12x6 def lands with the LP base file) + a unit def.
func _setup(w: SimWorld) -> Dictionary:
	var bid := -1
	var udef := ""
	var ks: Array = w.entities.keys()
	ks.sort()
	for k in ks:
		var e: Dictionary = w.entities[k]
		if int(e.get("owner", -1)) != _fid(w):
			continue
		if bid < 0 and String(e.kind) == "building":
			bid = int(k)
		if udef == "" and String(e.kind) == "unit" and float(Content.unit(String(e.def)).get("hp", 0)) >= 80.0:
			udef = String(e.def)
	return {"bid": bid, "def": udef}


func _pat(w: SimWorld, def: String, frac: float, extra: Dictionary = {}) -> Dictionary:
	var id := w.spawn_unit(def, _fid(w), Vector2(w.map.lp.base.center) + Vector2(0, 30))
	var e: Dictionary = w.entities[id]
	e.hp = frac * float(e.max_hp)
	for k in extra:
		e[k] = extra[k]
	return e


func _run(w: SimWorld, secs: float) -> void:
	for i in int(secs * float(SimWorld.TICK_RATE)):
		w.tick += 1
		H.tick(w)


func test_unused_has_no_state() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	check(not w.sys_state.has(H.KEY), "a match without a hospital has no hosp71 state")
	var S := _setup(w)
	check(not H.admit(w, _pat(w, String(S.def), 0.3)), "no hospital: admit refused")
	check(not w.sys_state.has(H.KEY), "and a refused admit creates no state")


func test_triage_order_and_beds() -> void:
	var w := _lp()
	if w == null:
		return
	var S := _setup(w)
	check(int(S.bid) >= 0 and String(S.def) != "", "setup found a building + a soldier def")
	H.register(w, int(S.bid))
	var y := _pat(w, String(S.def), 0.6)            # yellow, admitted first
	var r1 := _pat(w, String(S.def), 0.1)
	var r2 := _pat(w, String(S.def), 0.2, {"wb": 1.0})
	var r3 := _pat(w, String(S.def), 0.3)
	var g := _pat(w, String(S.def), 0.9)
	var c71 := _pat(w, String(S.def), 0.9, {"c71tag": "red"})   # DAMAGE71's tag wins over hp
	for e in [y, r1, r2, r3, g, c71]:
		check(H.admit(w, e), "admitted %d" % int(e.id))
	check(not H.admit(w, y), "a patient is admitted once")
	check_eq(H.ward_of(y), "triage", "everyone starts in triage")
	_run(w, float(H.R().triage_s) + 0.6)
	var c := H.census(w)
	print("  [hospital71] after triage: ", c)
	check_eq(int(c.get("surgery", 0)), int(H.R().beds.surgery), "surgery full (%d beds)" % int(H.R().beds.surgery))
	check_eq(H.ward_of(r1), "surgery", "first red (by admission) in surgery")
	check_eq(H.ward_of(r2), "surgery", "second red in surgery")
	check_eq(H.ward_of(r3), "triage", "third red waits in triage: no bed, never skipped")
	check_eq(H.ward_of(c71), "triage", "the Care71-tagged red waits too (admitted after r3)")
	check_eq(H.ward_of(y), "recovery", "yellow straight to recovery")
	check_eq(H.ward_of(g), "triage", "green treated in triage")
	check(bool(r2.get("wstab", false)), "bleeding stopped on the table")
	_run(w, float(H.R().green_s) + 0.6)
	check_eq(H.ward_of(g), "", "green treated and out")
	check(float(g.hp) >= float(g.max_hp), "green at full hp")


func test_red_path_returns_to_the_fight_with_prosthetic() -> void:
	var w := _lp()
	if w == null:
		return
	var S := _setup(w)
	H.register(w, int(S.bid))
	var e := _pat(w, String(S.def), 0.1, {"wb": 1.0, "g71_limb_lost": true})
	H.admit(w, e)
	var seen := []
	var why := ""
	var t0 := w.tick
	for i in 12000:   # 600 s cap: heal rates are hp/s (PROVISIONAL), so the stay scales with the soldier's max hp
		w.tick += 1
		H.tick(w)
		for ev in w.events:
			if String(ev.get("type", "")) == "HospitalDischarge" and int(ev.get("id", -1)) == int(e.id):
				why = String(ev.get("why", ""))
		w.events.clear()
		var wd := H.ward_of(e)
		if seen.is_empty() or seen[-1] != wd:
			seen.append(wd)
		if wd == "":
			break
	print("  [hospital71] red path: ", seen, " in %.1f s (max hp %.0f)" % [float(w.tick - t0) / 20.0, float(e.max_hp)])
	check_eq(seen, ["triage", "surgery", "icu", "recovery", "prosthetics", ""], "triage -> surgery -> ICU -> recovery -> prosthetics -> out")
	check_eq(why, "recovered", "discharged recovered: back to the fight")
	check(float(e.hp) >= float(e.max_hp), "full hp")
	check(bool(e.get("g71pros", false)), "a cybernetic prosthetic fitted (state for J9)")
	var Status = preload("res://sim/systems/status.gd")
	var mv := Status.move_mult(w, e)
	var ac := Status.accuracy_mult(w, e)
	check(mv > 1.0, "J9 prosthetic move edge")
	check(ac > 1.0, "J9 prosthetic accuracy edge")


func test_quarantine_lock_seals_the_ward() -> void:
	var w := _lp()
	if w == null:
		return
	var S := _setup(w)
	H.register(w, int(S.bid))
	var e := _pat(w, String(S.def), 0.6, {"cn_exp": 0.6})
	H.admit(w, e)
	check_eq(H.ward_of(e), "quarantine", "nanite-exposed patient to the quarantine ward")
	H.turn_test(w, e)
	check(H.locked(w), "a patient turns: quarantine locked (J5 stand-in)")
	_run(w, 0.6 / float(H.R().quar_decon) + 2.0)
	check(float(e.get("cn_exp", 0.0)) <= 0.0, "decon done")
	check_eq(H.ward_of(e), "quarantine", "sealed: nobody leaves while locked")
	check_eq(H.validate_command(w, {"type": "hosp_quarantine", "issuer": _fid(w), "on": false}), "", "unlock order valid")
	H.apply_command(w, {"type": "hosp_quarantine", "issuer": _fid(w), "on": false})
	_run(w, 1.0)
	check_eq(H.ward_of(e), "triage", "unlocked: on to triage")


func test_save_load_mid_ward_same_future() -> void:
	var w := _lp()
	if w == null:
		return
	var S := _setup(w)
	H.register(w, int(S.bid))
	for f in [0.1, 0.15, 0.2, 0.6, 0.9]:
		H.admit(w, _pat(w, String(S.def), f))
	_run(w, 12.0)
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	_run(w, 30.0)
	_run(w2, 30.0)
	check_eq(var_to_str(w2.sys_state[H.KEY]), var_to_str(w.sys_state[H.KEY]), "save / load mid-ward: same ward state")
	var hp1 := []
	var hp2 := []
	var ks: Array = w.sys_state[H.KEY].pats.keys()
	ks.sort()
	for k in ks:
		hp1.append(float(w.entities[int(k)].hp))
		hp2.append(float(w2.entities[int(k)].hp))
	check_eq(hp2, hp1, "same patient hp")


## Steps the LP world until its base hospital registered (LpSetup.build_g71_late places the base after the facility
## fill; Hospital71 looks every 50 ticks), at most 1200 ticks.
func _wait_home(w: SimWorld) -> void:
	for i in 1200:
		if H.home(w, _fid(w)) >= 0:
			return
		w.step()


## CNOPS71-6: the machinery tests below must not depend on where the LP base file manages to place the hospital (since
## build_g71_late runs after the facility fill there is no free 6x6 inside the rings, ORCH CR change_request.lp_site71):
## when the base placed none, one trauma block is built on the nearest free 6x6 site (same def, same registration path:
## Hospital71.tick finds it on its own). test_lp_base_places_the_hospital checks the base itself.
func _hospital(w: SimWorld) -> void:
	while w.tick < 120:   # the LP fill lands by ~tick 30, Hospital71 looks at tick % 50 == 13
		w.step()
	if H.home(w, _fid(w)) >= 0:
		return
	var LpSetup = preload("res://sim/systems/lp_setup.gd")
	var occ: Dictionary = LpSetup._occ(w)
	var c := Vector2i(Vector2(w.map.lp.base.center))
	var best := Vector2i(-1, -1)
	var bd := INF
	for oy in range(-50, 45):
		for ox in range(-50, 45):
			var o := c + Vector2i(ox, oy)
			if Vector2(ox, oy).length() < bd and LpSetup._free(w, occ, o, 6):
				bd = Vector2(ox, oy).length()
				best = o
	if best.x < 0:
		return
	w.spawn_building("a_g71_hospital", _fid(w), best, true)
	_wait_home(w)


## A foot soldier def of the LP side that can be quartered (Garrison.can_enter), "" when none.
func _foot(w: SimWorld) -> String:
	var ks: Array = w.entities.keys()
	ks.sort()
	for k in ks:
		var e: Dictionary = w.entities[k]
		if int(e.get("owner", -1)) == _fid(w) and String(e.kind) == "unit" and SimWorld.Garrison.can_enter(String(e.def)) \
				and float(Content.unit(String(e.def)).get("hp", 0)) >= 80.0:
			return String(e.def)
	return ""


## CNOPS71-5: the LP-base trauma block registers itself + its roof pad (Pads71 kind hospital) at the start; an admitted
## soldier is quartered inside it (inert: no move, no target) and put out idle when discharged.
func test_roof_pad_and_inert_patients() -> void:
	var w := _lp()
	if w == null:
		return
	_hospital(w)
	var fid := _fid(w)
	var hb := H.home(w, fid)
	if not check(hb >= 0, "the hospital registered itself (Hospital71.tick, no admit call)"):
		return
	check(bool(Content.building(String(w.entities[hb].def)).get("roof_pad71", false)), "home = the trauma block")
	var P71 = preload("res://sim/systems/pads71.gd")
	check(P71.has_pad(w, H.pad_key(hb)), "roof pad registered")
	check_eq(String(P71.pad(w, H.pad_key(hb)).get("k", "")), "hospital", "pad kind hospital")
	check(P71.alive(w, H.pad_key(hb)), "pad alive while the building stands")
	var fd := _foot(w)
	if not check(fd != "", "a foot soldier def"):
		return
	var e := _pat(w, fd, 0.6)
	check(H.admit(w, e), "admitted")
	check_eq(int(e.get("garrisoned_in", -1)), hb, "quartered inside the hospital")
	w.step()
	var p0: Vector2 = e.pos
	for i in 40:
		w.step()
	check(Vector2(e.pos).distance_to(p0) < 0.01, "inert: did not move in 2 s (%.3f)" % Vector2(e.pos).distance_to(p0))
	check_eq(int(e.get("target", -1)), -1, "inert: no target")
	check(["rest", "hold"].has(String(e.order.type)), "inert order (%s)" % String(e.order.type))
	check(H.ward_of(e) != "", "still a patient")
	_run(w, 120.0)
	check_eq(H.ward_of(e), "", "discharged")
	check(not e.has("garrisoned_in"), "put out of the hospital")
	check_eq(String(e.order.type), "idle", "idle after discharge")


## CNOPS71-5 / CNOPS71-8: hosp_medevac retasks a REAL fleet medevac heli (CNOPS71-8 design change: the abstract lift
## of CNOPS71-5 is now only the fallback of a side without one, test_medevac_abstract_without_fleet): the nearest free
## heli leaves auto evac, flies out, takes the casualty aboard, flies back to the roof pad, he is admitted and quartered,
## the heli goes back on auto evac. Save / load mid-lift keeps the same future.
func test_medevac_lift() -> void:
	var w := _lp()
	if w == null:
		return
	_hospital(w)
	var fid := _fid(w)
	var hb := H.home(w, fid)
	var fd := _foot(w)
	if not check(hb >= 0 and fd != "", "hospital + foot def"):
		return
	var e := _pat(w, fd, 0.3)
	e.order = {"type": "hold", "target": e.pos}
	check_eq(H.validate_command(w, {"type": "hosp_medevac", "issuer": fid, "ids": []}), "No casualty.", "empty ids refused")
	check(H.validate_command(w, {"type": "hosp_medevac", "issuer": 1 - fid if fid <= 1 else 0, "ids": [int(e.id)]}) != "", "another side's order refused")
	check_eq(H.validate_command(w, {"type": "hosp_medevac", "issuer": fid, "ids": [int(e.id)]}), "", "medevac order valid")
	if not check(not H._helis(w, fid).is_empty(), "the LP base fleet has medevac helis"):
		return
	H.apply_command(w, {"type": "hosp_medevac", "issuer": fid, "ids": [int(e.id)]})
	check_eq(H.ward_of(e), "pad", "booked: waiting for the lift")
	check(H.validate_command(w, {"type": "hosp_medevac", "issuer": fid, "ids": [int(e.id)]}) != "", "booked twice refused")
	var q: Dictionary = w.sys_state[H.KEY].mq[str(int(e.id))]
	var hid := int(q.get("heli", -1))
	if not check(hid >= 0 and w.entities.has(hid) and String(w.entities[hid].def) == "a_g71_medevac_heli", "a fleet medevac heli retasked (#%d)" % hid):
		return
	check_eq(int(w.entities[hid].get("h71mv", -1)), int(e.id), "heli tasked to this casualty")
	check(not (w.sys_state.medical.evac as Dictionary).has(hid), "heli off auto evac while on the lift")
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	var t0 := w.tick
	var aboard := false
	while H.ward_of(e) in ["pad", "air"] and w.tick - t0 < 120 * SimWorld.TICK_RATE:
		w.step()
		if int(e.get("evac_by", -1)) == hid:
			aboard = true
	check(aboard, "the casualty rode aboard the heli")
	check_eq(H.ward_of(e), "triage", "landed after %.1f s: admitted to triage" % (float(w.tick - t0) / SimWorld.TICK_RATE))
	check_eq(int(e.get("garrisoned_in", -1)), hb, "and quartered inside")
	check(not e.has("evac_by"), "off the heli")
	check(not w.entities[hid].has("h71mv") and (w.sys_state.medical.evac as Dictionary).has(hid), "heli back on auto evac")
	while w2.tick < w.tick:
		w2.step()
	check_eq(var_to_str(w2.sys_state[H.KEY]), var_to_str(w.sys_state[H.KEY]), "save / load mid-lift: same future")
	check_eq(str(w2.entities[hid].pos), str(w.entities[hid].pos), "same heli position after save / load")


## CNOPS71-8: a side without a fleet medevac heli keeps the abstract lift (CNOPS71-5): eta = load + both legs.
func test_medevac_abstract_without_fleet() -> void:
	var w := _lp()
	if w == null:
		return
	_hospital(w)
	var fid := _fid(w)
	var hb := H.home(w, fid)
	var fd := _foot(w)
	if not check(hb >= 0 and fd != "", "hospital + foot def"):
		return
	for hid in H._helis(w, fid):
		w.entities[hid].erase("h71fl")   # not tasked by the hospital: not part of its fleet
	check(H._helis(w, fid).is_empty(), "no fleet heli")
	var e := _pat(w, fd, 0.3)
	H.apply_command(w, {"type": "hosp_medevac", "issuer": fid, "ids": [int(e.id)]})
	check_eq(H.ward_of(e), "pad", "booked: waiting for the lift")
	var q: Dictionary = w.sys_state[H.KEY].mq[str(int(e.id))]
	check(not q.has("heli"), "abstract lift")
	var eta := int(q.eta)
	var P71 = preload("res://sim/systems/pads71.gd")
	var d := P71.pos_of(w, H.pad_key(hb)).distance_to(Vector2(e.pos))
	var want := float(H.R().medevac_load_s) + 2.0 * d / float(H.R().medevac_speed)
	check(absf(float(eta - w.tick) / float(SimWorld.TICK_RATE) - want) < 0.1, "eta = load + both legs (%.1f s)" % want)
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	_run(w, float(eta - w.tick) / float(SimWorld.TICK_RATE) + 1.0)
	_run(w2, float(eta - w2.tick) / float(SimWorld.TICK_RATE) + 1.0)
	check_eq(H.ward_of(e), "triage", "landed: admitted to triage")
	check_eq(int(e.get("garrisoned_in", -1)), hb, "and quartered inside")
	check_eq(var_to_str(w2.sys_state[H.KEY]), var_to_str(w.sys_state[H.KEY]), "save / load mid-lift: same future")


## CNOPS71-6: the LP starting base (content/g71_lp/lp_base_cnops.json via LpSetup.build_g71_late) holds the J6 hospital:
## trauma block + ward wing, and the trauma block registers itself at the start. RED while the base has no free site.
func test_lp_base_places_the_hospital() -> void:
	var w := _lp()
	if w == null:
		return
	_wait_home(w)
	var g71: Dictionary = w.sys_state.lp.get("g71", {})
	var bs: Array = g71.get("cnops", {}).get("buildings", [])
	var defs := []
	for b in bs:
		if w.entities.has(int(b)):
			defs.append(String(w.entities[int(b)].def))
	defs.sort()
	check_eq(str(defs), str(["a_g71_hospital", "a_g71_hospital_wing"]), "LP base: trauma block + ward wing placed")
	check(H.home(w, _fid(w)) >= 0, "LP base hospital registered at the start")


## CNOPS71-6: end to end with DAMAGE71's care71 routing (medical.gd _deliver, CR seq 2138): an auto-evac ambulance picks
## up a wounded soldier and carries him to the nearest hospital, here the trauma block (hospital: true + hospital71:
## true): he lands in the Hospital71 triage ward, quartered inside, no longer in Medical's wounded list, carrier empty.
func test_evac_carries_the_casualty_into_the_ward() -> void:
	var w := _lp()
	if w == null:
		return
	_hospital(w)
	var fid := _fid(w)
	var hb := H.home(w, fid)
	var fd := _foot(w)
	if not check(hb >= 0 and fd != "", "hospital + foot def"):
		return
	var M = preload("res://sim/systems/medical.gd")
	var bc := Vector2(w.entities[hb].cell)
	var e := _pat(w, fd, 1.0)
	e.pos = bc + Vector2(-3.5, 3.0)
	M.wound(w, e)
	check(M.is_wounded(e), "wounded")
	var amb := w.spawn_unit("a_ambulance", fid, bc + Vector2(-5.5, 3.0))
	var cmd := {"type": "set_auto_evac", "issuer": fid, "unit_id": amb, "center": [float(e.pos.x), float(e.pos.y)], "radius": 8}
	if not check_eq(M.validate_command(w, cmd), "", "auto evac order valid"):
		return
	M.apply_command(w, cmd)
	var t0 := w.tick
	while H.ward_of(e) == "" and w.tick - t0 < 60 * SimWorld.TICK_RATE and w.entities.has(int(e.id)):
		w.step()
	check_eq(H.ward_of(e), "triage", "carried in: admitted to triage after %.1f s" % (float(w.tick - t0) / SimWorld.TICK_RATE))
	check_eq(int(e.get("garrisoned_in", -1)), hb, "quartered inside the trauma block")
	check(not (w.sys_state.medical.wounded as Dictionary).has(int(e.id)), "out of Medical's wounded list")
	check(M.carrying(w.entities[amb]).is_empty(), "ambulance unloaded")


## CNOPS71-6: the hospital card's summary (presentation/ui71/hospital_card.gd, static, no UI): hidden without the
## hospital selected, the nine wards with their beds, the quarantine state, and the wounded on the ground it can lift.
func test_hospital_card_summary() -> void:
	var w := _lp()
	if w == null:
		return
	_hospital(w)
	var fid := _fid(w)
	var hb := H.home(w, fid)
	var fd := _foot(w)
	if not check(hb >= 0 and fd != "", "hospital + foot def"):
		return
	var Card = preload("res://presentation/ui71/hospital_card.gd")
	check(Card.summary(w, fid, []).is_empty(), "nothing selected: no card")
	check(Card.summary(w, 1 - fid if fid <= 1 else 0, [hb]).is_empty(), "another side: no card")
	var e := _pat(w, fd, 1.0)
	preload("res://sim/systems/medical.gd").wound(w, e)
	var sm: Dictionary = Card.summary(w, fid, [hb])
	check_eq((sm.get("wards", []) as Array).size(), H.WARDS.size(), "every ward listed")
	check_eq(int(sm.wards[1][2]), int(H.R().beds.surgery), "surgery beds from the rules")
	check(not bool(sm.locked), "quarantine open")
	check((sm.lift as Array).has(int(e.id)), "the wounded soldier can be lifted")
	H.quarantine_lock(w, true, "test")
	check(bool(Card.summary(w, fid, [hb]).locked), "sealed shows")
	check_eq(H.validate_command(w, {"type": "hosp_medevac", "issuer": fid, "ids": sm.lift}), "", "the card's lift order is valid")


## CNOPS71-7: the J6 hospital fleet from the LP starting base: 2 medevac helicopters + 2 drone ambulances are put on
## Medical auto evac when the trauma block registers (helis over the roof pad, ambulances at the door), out of the LP
## defence roster; a soldier wounded inside the fleet radius is flown / driven into the Hospital71 wards by the fleet.
func test_fleet_flies_the_wounded_in() -> void:
	var w := _lp()
	if w == null:
		return
	_wait_home(w)
	var fid := _fid(w)
	var hb := H.home(w, fid)
	var fd := _foot(w)
	if not check(hb >= 0 and fd != "", "hospital + foot def"):
		return
	var M = preload("res://sim/systems/medical.gd")
	var P71 = preload("res://sim/systems/pads71.gd")
	var n := {"heli": 0, "ground": 0}
	var fleet := []
	for u in w.units_of(fid):
		var k := String(Content.unit(String(u.def)).get("hosp71_fleet", ""))
		if k == "":
			continue
		fleet.append(int(u.id))
		n[k] = int(n[k]) + 1
		check((w.sys_state.medical.evac as Dictionary).has(int(u.id)), "%s #%d on auto evac" % [u.def, int(u.id)])
		check(not u.has("lp_ring") and not u.has("lp_home"), "%s #%d off the LP defence roster" % [u.def, int(u.id)])
		if k == "heli":
			check_eq(P71.home(w, int(u.id)), H.pad_key(hb), "heli home = the roof pad")
	check_eq(str(n), str({"heli": 2, "ground": 2}), "fleet: 2 medevac helis + 2 drone ambulances")
	var e := _pat(w, fd, 1.0)
	e.pos = Vector2(w.entities[hb].pos) + Vector2(-14.0, 6.0)
	e.order = {"type": "hold", "target": e.pos}
	M.wound(w, e)
	check(M.is_wounded(e), "wounded 15 tiles from the hospital")
	var t0 := w.tick
	var by := -1
	while H.ward_of(e) == "" and w.tick - t0 < 90 * SimWorld.TICK_RATE and w.entities.has(int(e.id)):
		w.step()
		if e.has("evac_by"):
			by = int(e.evac_by)
	check(fleet.has(by), "picked up by the hospital fleet (carrier #%d %s)" % [by, String(w.entities[by].def) if w.entities.has(by) else "-"])
	check(H.ward_of(e) != "", "admitted to the wards after %.1f s (%s)" % [float(w.tick - t0) / SimWorld.TICK_RATE, H.ward_of(e)])


## CNOPS71-9: hosp_medevac is in world.gd COMMANDS: the order goes through w.submit like a player click and books the
## lift on the next tick; a submitted order for an enemy soldier is refused at preview.
func test_hosp_medevac_through_submit() -> void:
	var w := _lp()
	if w == null:
		return
	_hospital(w)
	var fid := _fid(w)
	var fd := _foot(w)
	if not check(H.home(w, fid) >= 0 and fd != "", "hospital + foot def"):
		return
	var e := _pat(w, fd, 0.3)
	e.order = {"type": "hold", "target": e.pos}
	var c := {"type": "hosp_medevac", "issuer": fid, "ids": [int(e.id)]}
	check_eq(w.preview_command(c), "", "preview accepts")
	var r := w.submit(c)
	check(bool(r.ok), "submit accepted")
	check_eq(H.ward_of(e), "", "not booked before the tick")
	w.step()
	w.step()
	check(H.ward_of(e) in ["pad", "air"], "booked by the submitted order (%s)" % H.ward_of(e))
	check(w.preview_command(c) != "", "a second order for the same soldier refused")
