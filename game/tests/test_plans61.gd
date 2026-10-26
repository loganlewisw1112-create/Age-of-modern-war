extends "res://tests/test_base.gd"
## G6.1 PLAN61: the command layer (plans drawn on the map -> chain-of-command orders). sim/systems/plans.gd.

const Plans = preload("res://sim/systems/plans.gd")
const Companies = preload("res://sim/systems/companies.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const BIG := 5000000


# ---------------------------------------------------------------- helpers
## Open grass arena x 22..73, y 0..25 (as test_companies), side 1 inert.
func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 26):
		for x in range(22, 74):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	for fid in [0, 1]:
		var f: Dictionary = w.factions[fid]
		f.stage = 8
		f.credits = BIG
		f.stock.salvage = BIG
		f.stock.ore = BIG
	return w


func _registered() -> bool:
	return SimWorld.COMMANDS.has("issue_plan")


## One world step; ticks Plans by hand until ORCH registers it in SYSTEM_ORDER.
func _step(w: SimWorld) -> void:
	w.step()
	if not SimWorld.SYSTEM_ORDER.has(Plans):
		Plans.tick(w)


func _run(w: SimWorld, n: int) -> void:
	for i in n:
		_step(w)


## Applies a plan command for fid; returns the rejection reason ("" = accepted).
func _cmd(w: SimWorld, fid: int, cmd: Dictionary) -> String:
	cmd.issuer = fid
	if _registered():
		var r := w.submit(cmd)
		if not r.ok:
			return String(r.reason)
		w.step()
		if not SimWorld.SYSTEM_ORDER.has(Plans):
			Plans.tick(w)
		return rejected_reason(w.events)
	var why := Plans.validate_command(w, cmd)
	if why == "":
		Plans.apply_command(w, cmd)
	_step(w)
	return why


func _spawn(w: SimWorld, def: String, fid: int, c: Vector2i) -> int:
	return w.spawn_unit(def, fid, Vector2(c) + Movement.CENTER)


## A G2 platoon: officer + n riflemen at cell c. Returns the group id.
func _platoon(w: SimWorld, fid: int, c: Vector2i, n: int = 4) -> int:
	var off := _spawn(w, "officer", fid, c + Vector2i(0, -2))
	var ids := []
	for i in n:
		ids.append(_spawn(w, "rifleman", fid, c + Vector2i(i % 3 - 1, i / 3)))
	w.submit({"type": "assign_officer", "issuer": fid, "officer_id": off, "unit_ids": ids})
	_step(w)
	return int(w.sys_state.ops.groups.keys().filter(func(g) -> bool: return int(w.sys_state.ops.groups[g].officer) == off)[0])


func _company(w: SimWorld) -> Dictionary:
	var d := String(Companies.leaders(Companies.faction_of(w, 0)).get("hq", ""))
	if not check(not Content.building(d).is_empty(), "Company HQ def exists"):
		return {}
	var hq := w.spawn_building(d, 0, Vector2i(30, 12), true)
	for k in 3:
		w.spawn_building("depot", 0, Vector2i(24 + k * 3, 22), true)
	_step(w)
	w.submit({"type": "train_company", "issuer": 0, "building_id": hq, "size": "platoon",
		"template": {"name": "p61", "slots": [{"def": "rifle_squad", "count": 4}]}})
	for i in 4000:
		_step(w)
		for ev in w.events:
			if ev.type == "CompanyTrained":
				return w.sys_state.companies.companies[int(ev.company_id)]
	check(false, "company trained")
	return {}


func _plan(f: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var p := {"formation": f, "intent": "attack", "objectives": [[64, 13]], "axis": [[34, 13], [64, 13]],
		"phase_lines": [{"points": [[46, 4], [46, 22]]}, {"points": [[55, 4], [55, 22]]}], "timing": {"mode": "now"}}
	p.merge(extra, true)
	return p


func _last_plan(w: SimWorld) -> Dictionary:
	var ids: Array = Plans.all(w).keys()
	ids.sort()
	return Plans.all(w)[ids[ids.size() - 1]] if not ids.is_empty() else {}


func _run_until(w: SimWorld, cond: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		_step(w)
		if cond.call():
			return true
	return false


func _cen(w: SimWorld, f: Dictionary) -> Vector2:
	var s := Vector2.ZERO
	var ids := Plans.formation_units(w, f)
	for id in ids:
		s += w.entities[id].pos
	return s / maxf(1.0, float(ids.size()))


# ---------------------------------------------------------------- tests
func test_issue_plan_validation() -> void:
	var w := _world()
	var gid := _platoon(w, 0, Vector2i(34, 13))
	var foe := _platoon(w, 1, Vector2i(34, 20))
	var f := {"kind": "platoon", "id": gid}
	check_eq(_cmd(w, 0, {"type": "issue_plan", "plan": _plan({"kind": "platoon", "id": foe})}), "Select one of your formations.", "enemy formation rejected")
	check_eq(_cmd(w, 0, {"type": "issue_plan", "plan": _plan({"kind": "company", "id": 999})}), "Select one of your formations.", "unknown company rejected")
	check(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"objectives": [[-5, 3]]})}).begins_with("Objectives must be cells"), "objective off the map rejected")
	check(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"axis": [[34, 13], [9999, 13]]})}).begins_with("The axis of advance"), "axis off the map rejected")
	check(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"phase_lines": [{"points": [[46, 4]]}]})}).begins_with("A phase line needs"), "1-point phase line rejected")
	check(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"intent": "conquer"})}).begins_with("Intent must be"), "bad intent rejected")
	check(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"intent": "screen", "phase_lines": []})}).begins_with("A screen needs"), "screen without a line rejected")
	check(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"timing": {"mode": "at", "t": -3}})}).begins_with("H-hour"), "negative H-hour rejected")
	check(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"fire_support": [{"cell": [50, 13], "kind": "nuke"}]})}).begins_with("Fire support kind"), "bad fire kind rejected")
	check_eq(Plans.all(w).size(), 0, "no plan state after rejections")
	check(not w.sys_state.has("plans"), "rejections never create plan state (hash unchanged)")
	check_eq(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"timing": {"mode": "signal"}})}), "", "valid plan accepted")
	var pl := _last_plan(w)
	check_eq(_cmd(w, 1, {"type": "cancel_plan", "plan_id": int(pl.id)}), "Select one of your plans.", "cancel of another side's plan rejected")
	check(_cmd(w, 0, {"type": "plan_signal", "plan_id": int(pl.id), "signal": "dance"}).begins_with("Signal must be"), "unknown signal rejected")
	# dead formation
	var g: Dictionary = w.sys_state.ops.groups[gid]
	for id in (g.members as Array).duplicate():
		w.destroy(int(id), "killed", 1)
	w.destroy(int(g.officer), "killed", 1)
	_run(w, 12)
	check_eq(String(Plans.get_plan(w, int(pl.id)).status), "destroyed", "plan of a wiped-out platoon ends destroyed")
	check_eq(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f)}), "Select one of your formations.", "dead formation rejected")


func test_company_reaches_pl1_then_pl2_and_halts() -> void:
	var w := _world()
	var c := _company(w)
	if c.is_empty():
		return
	var f := {"kind": "company", "id": int(c.id)}
	check(Plans.platoons(w, f).size() >= 1, "company has platoons")
	check_eq(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f)}), "", "company plan accepted")
	var pl := _last_plan(w)
	var order := []
	var log := func() -> void:
		for ev in w.events:
			if ev.type == "PlanPhaseReached" and int(ev.plan_id) == int(pl.id):
				order.append(String(ev.name))
	var got := _run_until(w, func() -> bool: log.call(); return int(pl.pl_reached) >= 1, 2400)
	if not check(got, "company reaches PL ALPHA (status: %s)" % pl.line):
		return
	_run(w, 12)
	check_eq(String(pl.status), "halted", "halts on PL ALPHA")
	var x1 := _cen(w, f).x
	_run(w, 400)
	check_eq(int(pl.leg), 0, "still on leg 0 after 20 s without a signal")
	check(_cen(w, f).x < 46.0 + Plans.REACH + 2.0, "did not push past PL ALPHA (x %.1f, was %.1f)" % [_cen(w, f).x, x1])
	check_eq(_cmd(w, 0, {"type": "plan_signal", "plan_id": int(pl.id), "signal": "go"}), "", "go signal accepted")
	got = _run_until(w, func() -> bool: log.call(); return int(pl.pl_reached) >= 2, 2400)
	if not check(got, "company reaches PL BRAVO (status: %s)" % pl.line):
		return
	check_eq(order, ["PL ALPHA", "PL BRAVO"], "phase lines reached in order")
	_run(w, 12)
	check_eq(String(pl.status), "halted", "halts on PL BRAVO")
	check_eq(_cmd(w, 0, {"type": "plan_signal", "plan_id": int(pl.id), "signal": "go"}), "", "second go accepted")
	got = _run_until(w, func() -> bool: return String(pl.status) == "holding", 2400)
	check(got, "objective reached -> holding (status: %s)" % pl.line)
	check(pl.obj_held.size() == 1 and bool(pl.obj_held[0]), "objective 1 held")
	check(String(Plans.status_line(pl)).contains("PL 2/2 reached"), "status line counts phase lines: %s" % Plans.status_line(pl))
	var g: Dictionary = w.sys_state.ops.groups[Plans.platoons(w, f)[0]]
	_run_until(w, func() -> bool: return String(g.mission.get("type", "")) == "hold_zone", 600)  # radio delay
	check_eq(String(g.mission.get("type", "")), "hold_zone", "attack consolidates on the objective (hold_zone)")


func test_cancel_plan_stops_it() -> void:
	var w := _world()
	var gid := _platoon(w, 0, Vector2i(34, 13))
	var f := {"kind": "platoon", "id": gid}
	check_eq(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"phase_lines": []})}), "", "plan accepted")
	var pl := _last_plan(w)
	_run(w, 60)
	check_eq(String(pl.status), "advancing", "advancing toward the objective")
	var g: Dictionary = w.sys_state.ops.groups[gid]
	check(not (g.mission as Dictionary).is_empty(), "the lieutenant has a mission from the plan")
	check_eq(_cmd(w, 0, {"type": "cancel_plan", "plan_id": int(pl.id)}), "", "cancel accepted")
	check(not bool(pl.active), "plan inactive")
	check_eq(String(pl.status), "cancelled", "status cancelled")
	check((g.mission as Dictionary).is_empty(), "plan mission withdrawn from the platoon")
	_run(w, 40)
	var c0 := _cen(w, f)
	_run(w, 200)
	check(_cen(w, f).distance_to(c0) < 1.5, "platoon stands after the cancel (moved %.2f)" % _cen(w, f).distance_to(c0))
	check_eq(_cmd(w, 0, {"type": "cancel_plan", "plan_id": int(pl.id)}), "That plan is no longer active.", "second cancel rejected")
	# a new plan for the same formation replaces the old one
	check_eq(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"timing": {"mode": "signal"}})}), "", "plan 2 accepted")
	var p2 := _last_plan(w)
	check_eq(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"timing": {"mode": "signal"}})}), "", "plan 3 accepted")
	check_eq(String(p2.status), "cancelled", "plan 2 replaced by plan 3")
	check_eq(Plans.plans_of(w, 0, true).size(), 1, "one active plan per formation")


func test_signals_timing_and_withdraw() -> void:
	var w := _world()
	var gid := _platoon(w, 0, Vector2i(34, 13))
	var f := {"kind": "platoon", "id": gid}
	check_eq(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"timing": {"mode": "signal"}})}), "", "plan on signal accepted")
	var pl := _last_plan(w)
	var c0 := _cen(w, f)
	_run(w, 200)
	check_eq(int(pl.leg), -1, "waits for the signal")
	check_eq(String(pl.status), "waiting", "status waiting")
	check(_cen(w, f).distance_to(c0) < 1.5, "nobody moved before the signal")
	check_eq(_cmd(w, 0, {"type": "plan_signal", "plan_id": int(pl.id), "signal": "phase 2"}), "", "phase 2 signal accepted")
	check_eq(int(pl.allow), 1, "phase 2 authorises the leg past PL ALPHA")
	var got := _run_until(w, func() -> bool: return int(pl.pl_reached) >= 2, 3000)
	check(got, "phase 2 carried the platoon through PL ALPHA to PL BRAVO (%s)" % pl.line)
	_run(w, 12)
	check_eq(String(pl.status), "halted", "halts on PL BRAVO (phase 3 not given)")
	check_eq(_cmd(w, 0, {"type": "plan_signal", "plan_id": int(pl.id), "signal": "withdraw"}), "", "withdraw accepted")
	check_eq(String(pl.status), "withdrawing", "withdrawing")
	got = _run_until(w, func() -> bool: return String(pl.status) == "withdrawn", 3000)
	check(got, "withdrawn to the start line (%s)" % pl.line)
	check(_cen(w, f).distance_to(pl.origin) < Plans.REACH + 1.0, "back near where the plan started")
	# H-hour
	check_eq(_cmd(w, 0, {"type": "issue_plan", "plan": _plan(f, {"timing": {"mode": "at", "t": 5.0}, "pl_hold_s": 2.0})}), "", "plan at H+5 s accepted")
	var p2 := _last_plan(w)
	_run(w, 80)
	check_eq(int(p2.leg), -1, "not started before H-hour")
	_run(w, 40)
	check_eq(int(p2.leg), 0, "started at H-hour")
	got = _run_until(w, func() -> bool: return int(p2.leg) >= 1, 3000)
	check(got, "pl_hold_s auto-advances past PL ALPHA without a signal (%s)" % p2.line)


func test_save_load_mid_plan_and_determinism() -> void:
	var a := _world()
	var b := _world()
	var ga := _platoon(a, 0, Vector2i(34, 13))
	var gb := _platoon(b, 0, Vector2i(34, 13))
	_platoon(a, 0, Vector2i(34, 17))
	_platoon(b, 0, Vector2i(34, 17))
	check_eq(a.state_hash(), b.state_hash(), "identical setup")
	var fs := [{"cell": [60, 13], "kind": "artillery"}]
	check_eq(_cmd(a, 0, {"type": "issue_plan", "plan": _plan({"kind": "platoon", "id": ga}, {"fire_support": fs, "main_effort": true})}), "", "a accepted")
	check_eq(_cmd(b, 0, {"type": "issue_plan", "plan": _plan({"kind": "platoon", "id": gb}, {"fire_support": fs, "main_effort": true})}), "", "b accepted")
	_run(a, 150)
	_run(b, 150)
	check_eq(a.state_hash(), b.state_hash(), "same commands, same hash mid-plan")
	var d := SaveSystem.decode_bytes(SaveSystem.encode_dict(a.to_dict()))
	if not check(d.ok, "decode ok: %s" % d.reason):
		return
	var l := SimWorld.from_dict(d.dict)
	check_eq(l.state_hash(), a.state_hash(), "hash equal right after load")
	check_eq(Plans.plans_of(l, 0, true).size(), 1, "plan survives load")
	var pa := _last_plan(a)
	var pid := int(pa.id)
	_run(a, 300)
	_run(l, 300)
	check_eq(l.state_hash(), a.state_hash(), "hash equal 300 ticks after load")
	check_eq(int(Plans.get_plan(l, pid).pl_reached), int(pa.pl_reached), "same progress after load")
	_cmd(a, 0, {"type": "plan_signal", "plan_id": pid, "signal": "go"})
	_cmd(l, 0, {"type": "plan_signal", "plan_id": pid, "signal": "go"})
	_run(a, 300)
	_run(l, 300)
	check_eq(l.state_hash(), a.state_hash(), "hash equal after a signal on both")


func test_orders_go_down_the_chain_and_respect_player_orders() -> void:
	var w := _world()
	var gid := _platoon(w, 0, Vector2i(34, 13))
	var f := {"kind": "platoon", "id": gid}
	var cmd := {"type": "issue_plan", "plan": _plan(f, {"phase_lines": []}), "issuer": 0}
	if _registered():
		w.submit(cmd)
		w.step()
	else:
		Plans.apply_command(w, cmd)
	var via_net := false
	for ev in w.events:
		if ev.type == "OrderIssued" and String(ev.get("node", "")) == "p:%d" % gid:
			via_net = true
	var net_loaded := ResourceLoader.exists(Plans.NET_PATH) and Plans._net("issue", 5) != null
	check_eq(via_net, net_loaded, "plan leg sent over the CommandNet radio net when it exists")
	_run(w, 80)
	var g: Dictionary = w.sys_state.ops.groups[gid]
	check_eq(String(g.mission.get("type", "")), "attack_area", "delivered order became the lieutenant's mission")
	# a direct player order wins over the plan for the override window
	var uid := int(g.members[0])
	var away := Vector2(30.5, 22.5)
	w.submit({"type": "move", "issuer": 0, "unit_ids": [uid], "target": away})
	_run(w, 160)
	check(Vector2(w.entities[uid].pos).distance_to(away) < 3.0, "player-ordered unit went where the player said (%.1f away)" % Vector2(w.entities[uid].pos).distance_to(away))
