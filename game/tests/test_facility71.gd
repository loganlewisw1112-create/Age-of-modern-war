extends "res://tests/test_base.gd"
## G7.1 H8 (owner: CNOPS71): the CN facility turnaround. Done-when 8 (roster Q8 PROVISIONAL): a CN team cycle through
## the airlock (return -> heal -> rearm -> redeploy) in <= 70 s, timed from the team's first APC entering the airlock
## to the last one leaving it, redeployed. Same setup as the Step-1 repro (.plan/cnops71/repro71.gd --part=cycle:
## G7.1 before this work measured 102.1 s with the riders NOT healed). sim/systems/cn_facility.gd rules.g71_cn.turn.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")

const GATE_S := 70.0

static var _base: Dictionary = {}   # seed -> world dict after 25 ticks


func _lp(seed: int = 77) -> SimWorld:
	if not preload("res://sim/map_gen.gd").has_map("last_protocol"):
		return null
	if not _base.has(seed):
		var w0 := SimWorld.new_match(LastProtocol.make_config(seed, "last_protocol"))
		if w0 == null:
			return null
		w0.run_ticks(25)
		_base[seed] = w0.to_dict().duplicate(true)
	var w := SimWorld.from_dict((_base[seed] as Dictionary).duplicate(true))
	w.ai_state = {}
	return w


func _fid(w: SimWorld) -> int:
	return int(w.sys_state.lp.fid)


func _sub(w: SimWorld, c: Dictionary) -> String:
	c.issuer = _fid(w)
	var why := w.preview_command(c)
	if why != "":
		return why
	var r := w.submit(c)
	return "" if r.ok else String(r.reason)


func _members(w: SimWorld, t: Dictionary) -> Array:
	var out := []
	for id in t.members:
		var u = w.entities.get(int(id))
		if u == null:
			for aid in t.apcs:
				var a = w.entities.get(int(aid))
				if a != null:
					for c in a.get("cargo", []):
						if int(c.id) == int(id):
							u = c
		if u != null:
			out.append(u)
	return out


func _hp_frac(w: SimWorld, t: Dictionary) -> float:
	var s := 0.0
	var m := 0.0
	for u in _members(w, t):
		s += float(u.hp)
		m += float(u.get("max_hp", Content.unit(String(u.def)).get("hp", 100)))
	return 0.0 if m <= 0.0 else s / m


func _min_aps(w: SimWorld, t: Dictionary) -> int:
	var n := 1 << 20
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null and a.has("a7"):
			n = mini(n, int(a.a7.get("aps", -1)))
	return n


## Rolls a strike team out to the field, damages it (soldiers 40% hp, APC active-protection rounds 0) and returns it.
## Returns {w, T, t, F, lock, out}.
func _out_and_back(w: SimWorld) -> Dictionary:
	var T := {}
	var ks: Array = CnFacility.st(w).teams.keys()
	ks.sort()
	for k in ks:
		var X: Dictionary = CnFacility.st(w).teams[k]
		var t0 = CN.team(w, int(X.get("ext", -1)))
		if t0 != null and String(t0.kind) == "strike" and String(X.phase) == "garage":
			T = X
			break
	var t: Dictionary = CN.team(w, int(T.ext))
	var F := CnFacility.fac(w, int(T.fac))
	var lock: Rect2 = CnFacility.zone(F, "gate_outer").merge(CnFacility.zone(F, "apc_wash")).merge(CnFacility.zone(F, "gate_inner"))
	var out := Vector2(w.map.lp.base.center) + Vector2(0, 44)
	check_eq(_sub(w, {"type": "cn_rollout", "team": int(T.id), "target": [out.x, out.y]}), "", "rollout accepted")
	for i in 4000:
		w.step()
		if String(T.phase) == "out":
			break
	for u in _members(w, t):
		u.hp = 0.4 * float(u.get("max_hp", Content.unit(String(u.def)).get("hp", 100)))
	for aid in T.apcs:
		var a = w.entities.get(int(aid))
		if a != null and a.has("a7"):
			a.a7.aps = 0
	check_eq(_sub(w, {"type": "cn_return", "team": int(T.id)}), "", "return accepted")
	return {"T": T, "t": t, "F": F, "lock": lock, "out": out}


func test_turnaround_cycle_under_70s() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	_cycle(w)


## One Done-when 8 cycle on w (all checks as before). Returns {cyc, hp0, hp_out, aps, garage} (the seed probe
## .plan/cnops71/seeds71.gd runs it on several LP seeds).
func _cycle(w: SimWorld) -> Dictionary:
	var R := _out_and_back(w)
	var T: Dictionary = R.T
	var t: Dictionary = R.t
	var lock: Rect2 = R.lock
	var comp := CnFacility.compound_rect(R.F)
	var out: Vector2 = R.out
	# Commands wait in w.pending for their tick: the cn_return must apply (phase 'returning') before the redeploy is
	# validated, as when a player clicks Redeploy after Return (CNOPS71-3: the gen-2 run validated it while still 'out').
	for i in 5:
		if String(T.phase) == "returning":
			break
		w.step()
	check_eq(String(T.phase), "returning", "the return applied")
	var why := _sub(w, {"type": "cn_rollout", "team": int(T.id), "target": [out.x, out.y]})
	check_eq(why, "", "redeploy ordered during the return (queued turnaround)")
	var hp0 := _hp_frac(w, t)
	var t_ret := w.tick
	var t_in := -1
	var t_out := -1
	var seen := {}
	var left := {}
	var marks := []
	var ph := ""
	var hp_out := -1.0
	var garage := false
	for i in 6000:
		w.step()
		if String(T.phase) != ph:
			ph = String(T.phase)
			marks.append("%s@%.1f" % [ph, float(w.tick - t_ret) / 20.0])
			garage = garage or ph == "garage"
		for aid in T.apcs:
			var a = w.entities.get(int(aid))
			if a == null:
				continue
			var p := Vector2(a.pos)
			if lock.has_point(p):
				seen[int(aid)] = true
				if t_in < 0:
					t_in = w.tick
			elif seen.has(int(aid)) and not left.has(int(aid)) and not comp.has_point(p) and ["to_gate", "out"].has(ph):
				left[int(aid)] = w.tick
		if t_in >= 0 and left.size() >= (T.apcs as Array).size():
			t_out = w.tick
			hp_out = _hp_frac(w, t)
			break
	var cyc := float(t_out - t_in) / 20.0 if t_out > 0 else -1.0
	print("  [facility71] phases from cn_return: ", " ".join(marks))
	print("  [facility71] RESULT cycle first_in=%.1f s after return; first_in -> last_out %.1f s (gate %.0f; G7.1 before: 102.1); hp %.2f -> %.2f; aps min %d" % [
		float(t_in - t_ret) / 20.0, cyc, GATE_S, hp0, hp_out, _min_aps(w, t)])
	check(t_out > 0, "every APC left the airlock again, redeployed")
	check(cyc > 0.0 and cyc <= GATE_S, "airlock cycle %.1f s <= %.0f s (Done-when 8)" % [cyc, GATE_S])
	check(not garage, "no garage stop on a queued turnaround")
	check(hp_out >= 0.95, "the soldiers were healed in the cycle (%.2f -> %.2f)" % [hp0, hp_out])
	check(_min_aps(w, t) > 0, "the APCs were rearmed in the cycle (aps %d)" % _min_aps(w, t))
	return {"cyc": cyc, "hp0": hp0, "hp_out": hp_out, "aps": _min_aps(w, t), "garage": garage, "first_in": float(t_in - t_ret) / 20.0}


func test_plain_return_still_parks_healed_and_rearmed() -> void:
	var w := _lp()
	if w == null:
		return
	var R := _out_and_back(w)
	var T: Dictionary = R.T
	var t: Dictionary = R.t
	var heal_ev := false
	for i in 6000:
		w.step()
		for ev in w.events:
			if String(ev.get("type", "")) == "CnTurnHeal" and int(ev.get("team", -1)) == int(T.id):
				heal_ev = true
		if String(T.phase) == "garage":
			break
	check_eq(String(T.phase), "garage", "no redeploy queued: the team parks in its garage as before")
	check(heal_ev, "CnTurnHeal: riders treated in the airlock")
	check(_hp_frac(w, t) >= 0.95, "riders healed (%.2f)" % _hp_frac(w, t))
	check(_min_aps(w, t) > 0, "APCs rearmed")
	check(_sub(w, {"type": "cn_rollout", "team": int(T.id), "target": [R.out.x, R.out.y]}) == "", "a rollout from the garage works as before")


## CNOPS71-8 H8 facility upgrades (roster Q5: API + order now, progression with H7): fac_upgrade pays the tier, the
## bays tier scales the airlock turnaround heal; unknown kind / fully upgraded refused; unused = no field.
func test_facility_upgrade_bays_heal_faster() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var FAC = preload("res://sim/systems/cn_facility.gd")
	var fid := _fid(w)
	var fl: Array = FAC.facilities(w, fid)
	if not check(not fl.is_empty(), "the LP facility"):
		return
	var F: Dictionary = FAC.fac(w, int(fl[0]))
	check(not F.has("g71up"), "unused: no upgrade field")
	check_eq(FAC.validate_command(w, {"type": "fac_upgrade", "issuer": fid, "building_id": int(fl[0]), "kind": "moon"}), "Unknown facility upgrade.", "unknown kind refused")
	check_eq(FAC.validate_command(w, {"type": "fac_upgrade", "issuer": fid, "building_id": int(fl[0]), "kind": "bays"}), "", "bays upgrade valid")
	var heal := func(F2: Dictionary) -> float:
		var u := {"def": "rifleman", "hp": 10.0, "max_hp": 1000.0}
		FAC._turn_service(w, F2, {"id": 0, "fac": int(fl[0]), "owner": fid, "t": -5}, [{"cargo": [u], "cn_turn_rs": -5}])
		return float(u.hp) - 10.0
	var h0: float = heal.call(F)
	FAC.apply_command(w, {"type": "fac_upgrade", "issuer": fid, "building_id": int(fl[0]), "kind": "bays"})
	check(F.has("g71upq") and FAC.up_tier(F, "bays") == 0, "CNOPS71-9: the order builds first (build_s)")
	check(FAC.validate_command(w, {"type": "fac_upgrade", "issuer": fid, "building_id": int(fl[0]), "kind": "foundry"}) != "", "one upgrade at a time")
	check(_built(w, F) > 0.0, "built")
	check_eq(FAC.up_tier(F, "bays"), 1, "bays at tier 1 after the build")
	var h1: float = heal.call(F)
	var want := FAC.up_val(F, "bays", "heal_mult", 1.0)
	check(want > 1.0 and absf(h1 / h0 - want) < 0.01, "turnaround heal x%.2f (%.1f -> %.1f hp per service step)" % [want, h0, h1])
	check(FAC.upgrade(w, F, "bays"), "API upgrade to tier 2")
	check(FAC.validate_command(w, {"type": "fac_upgrade", "issuer": fid, "building_id": int(fl[0]), "kind": "bays"}) != "", "fully upgraded refused")
	check(FAC.upgrade(w, F, "foundry") and FAC.up_val(F, "foundry", "build_mult", 1.0) < 1.0, "foundry tier stored (build_mult %.2f)" % FAC.up_val(F, "foundry", "build_mult", 1.0))


## CNOPS71-9: fac_upgrade is in world.gd COMMANDS (CR seq 3459): the order goes through w.submit like a player click,
## pays the tier cost and lands on the next tick; same future after save / load.
func test_fac_upgrade_through_submit() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var FAC = preload("res://sim/systems/cn_facility.gd")
	var fid := _fid(w)
	var fl: Array = FAC.facilities(w, fid)
	if not check(not fl.is_empty(), "the LP facility"):
		return
	var F: Dictionary = FAC.fac(w, int(fl[0]))
	var before := var_to_str(w.factions[fid].get("res", w.factions[fid]))
	check_eq(_sub(w, {"type": "fac_upgrade", "building_id": int(fl[0]), "kind": "bays"}), "", "submit accepted")
	check_eq(_sub(w, {"type": "fac_upgrade", "building_id": int(fl[0]), "kind": "moon"}), "Unknown facility upgrade.", "submit of an unknown kind refused by preview")
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	w.step()
	w.step()
	w2.step()
	w2.step()
	F = FAC.fac(w, int(fl[0]))
	check(F.has("g71upq"), "the submitted order is building")
	var secs := _built(w, F)
	check(secs > 0.0, "built after %.1f s" % secs)
	_built(w2, FAC.fac(w2, int(fl[0])))
	check_eq(FAC.up_tier(F, "bays"), 1, "bays at tier 1 after the submitted order")
	check(var_to_str(w.factions[fid].get("res", w.factions[fid])) != before, "the tier cost was paid")
	check_eq(FAC.up_tier(FAC.fac(w2, int(fl[0])), "bays"), 1, "save / load before the tick: same result")
	check_eq(w2.state_hash(), w.state_hash(), "same hash after save / load")


## Steps w until the facility's queued upgrade is in (max 180 s); returns the seconds it took (-1 = never).
func _built(w: SimWorld, F: Dictionary) -> float:
	var t0 := w.tick
	while F.has("g71upq") and w.tick - t0 < 180 * SimWorld.TICK_RATE:
		w.step()
	return -1.0 if F.has("g71upq") else float(w.tick - t0) / float(SimWorld.TICK_RATE)


## CNOPS71-9 H8 facility under siege (roster Q20 test trigger): alert (defences up, doors open) -> lockdown (core below
## lock_frac) -> last-ditch evacuation (core below evac_frac); ends after end_quiet_s secure; unused = no field;
## save / load mid-siege keeps the same future.
func test_facility_under_siege_staged() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var FAC = preload("res://sim/systems/cn_facility.gd")
	var fid := _fid(w)
	var fl: Array = FAC.facilities(w, fid)
	if not check(not fl.is_empty(), "the LP facility"):
		return
	var F: Dictionary = FAC.fac(w, int(fl[0]))
	check(not F.has("g71sg") and FAC.siege_stage(F) == "", "unused: no siege field")
	check(FAC.validate_command(w, {"type": "fac_siege", "issuer": 1 - fid if fid <= 1 else 0, "building_id": int(fl[0])}) != "", "another side refused")
	check_eq(FAC.validate_command(w, {"type": "fac_siege", "issuer": fid, "building_id": int(fl[0])}), "", "test trigger valid")
	var lock0 := bool(F.lock)
	FAC.apply_command(w, {"type": "fac_siege", "issuer": fid, "building_id": int(fl[0]), "on": true, "reason": "test"})
	check_eq(FAC.siege_stage(F), "alert", "stage alert")
	check(bool(F.lock) and not (F.popups as Array).is_empty(), "defences up: %d pop-up turrets (was locked: %s)" % [(F.popups as Array).size(), lock0])
	var core: Dictionary = w.entities[int(F.id)]
	for i in 5:
		w.step()
	check_eq(FAC.siege_stage(F), "alert", "still alert while the core holds")
	check(bool(F.lock), "the contested auto-unlock is held during the siege")
	core.hp = float(core.max_hp) * 0.6
	for i in 3:
		w.step()
	check_eq(FAC.siege_stage(F), "lockdown", "core at 60%: lockdown")
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	core.hp = float(core.max_hp) * 0.3
	w2.entities[int(F.id)].hp = float(core.max_hp) * 0.3
	var evac := false
	for i in 3:
		w.step()
		w2.step()
		for ev in w.events:
			if String(ev.type) == "CnEvacuation":
				evac = true
	check_eq(FAC.siege_stage(F), "evac", "core at 30%: last-ditch evacuation")
	check(bool(F.evac) and evac, "evacuate ran (CnEvacuation)")
	check_eq(w2.state_hash(), w.state_hash(), "save / load mid-siege: same future")
	core.hp = float(core.max_hp)
	var t0 := w.tick
	while FAC.siege_stage(F) != "" and w.tick - t0 < 120 * SimWorld.TICK_RATE:
		w.step()
	check_eq(FAC.siege_stage(F), "", "siege over after %.1f s quiet" % (float(w.tick - t0) / SimWorld.TICK_RATE))
	check(not bool(F.lock) and (F.popups as Array).is_empty(), "lockdown lifted, pop-ups gone")


## CNOPS71-9 H8 foundry hook: with the foundry upgraded (build_mult m) the head suit of the Suit Foundry queue gains
## (1/m - 1) x the progress Production gave it, so it builds in m of the time; never upgraded = no field.
func test_foundry_upgrade_speeds_the_suit_queue() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var FAC = preload("res://sim/systems/cn_facility.gd")
	var C8B = preload("res://sim/systems/cards8b.gd")
	var fl: Array = FAC.facilities(w, _fid(w))
	if not check(not fl.is_empty(), "the LP facility"):
		return
	var F: Dictionary = FAC.fac(w, int(fl[0]))
	var ap = C8B.armory_part(w, F)
	if not check(ap != null, "the Suit Foundry part"):
		return
	ap["queue"] = [{"item": "test_suit", "progress": 0.1, "paid": true}]
	var S := {}
	C8B._foundry_boost(w, F, S)
	check(not S.has("fb"), "not upgraded: no boost field")
	check(FAC.upgrade(w, F, "foundry"), "foundry tier 1")
	var m := FAC.up_val(F, "foundry", "build_mult", 1.0)
	C8B._foundry_boost(w, F, S)
	ap.queue[0].progress = 0.2   # Production advanced it by 0.1
	C8B._foundry_boost(w, F, S)
	var want := 0.2 + 0.1 * (1.0 / m - 1.0)
	check(absf(float(ap.queue[0].progress) - want) < 1e-6, "progress %.4f = 0.2 + 0.1 x (1/%.2f - 1)" % [float(ap.queue[0].progress), m])
	ap.queue[0] = {"item": "test_suit", "progress": 0.0, "paid": true}   # next suit of the same kind
	C8B._foundry_boost(w, F, S)
	check_eq(float(ap.queue[0].progress), 0.0, "a new head suit is not boosted by the old one's progress")
	ap.queue.clear()
	C8B._foundry_boost(w, F, S)
	check(not S.has("fb"), "empty queue: field gone")
