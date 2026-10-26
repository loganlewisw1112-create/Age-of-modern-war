extends "res://tests/test_base.gd"
## G6.1 acceptance (owner: CHAIN61): chain of command, radio and comms, intel and belief.

const CommandNet = preload("res://sim/systems/command_net.gd")
const Intel = preload("res://sim/systems/intel.gd")
const Companies = preload("res://sim/systems/companies.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const Fog = preload("res://sim/systems/fog.gd")
const U = preload("res://sim/ai/ai_util.gd")


func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	return w


## Steps n ticks (ticks CommandNet/Intel by hand while ORCH has not registered them yet); returns events.
func _steps(w: SimWorld, n: int) -> Array:
	var evs := []
	var reg: bool = SimWorld.SYSTEM_ORDER.has(CommandNet)
	for i in n:
		w.step()
		if not reg:
			CommandNet.tick(w)
			Intel.tick(w)
		evs.append_array(w.events)
	return evs


func _hq(w: SimWorld) -> Vector2:
	for b in w.buildings_of(0):
		if CommandNet._is_root_building(String(b.def)):
			return Vector2(b.pos)
	return Vector2(10, 10)


## Point k tiles from side 0's HQ toward the map centre.
func _at(w: SimWorld, k: float, side: float = 0.0) -> Vector2:
	var hq := _hq(w)
	var c := Vector2(float(w.map.w), float(w.map.h)) * 0.5
	var d := (c - hq).normalized()
	return hq + d * k + Vector2(-d.y, d.x) * side


func _place(w: SimWorld, id: int, p: Vector2) -> void:
	HotState.set_pos(w, id, p)
	w.cache.erase("cn_graph")  # tests teleport inside one tick: drop the per-tick radio graph


func _stop(w: SimWorld, ids: Array) -> void:
	Movement.apply_command(w, {"type": "stop", "issuer": 0, "unit_ids": ids})


## A side-0 rifle company (platoon size) parked near the HQ, everyone stopped.
func _co(w: SimWorld) -> Dictionary:
	var cid := Companies.spawn_company_at(w, 0, "a_rifle_co", "platoon", w.cell_of(_at(w, 12)), _at(w, 12))
	var c: Dictionary = w.sys_state.companies.companies[cid]
	var gid := int(c.platoons[0])
	var g: Dictionary = w.sys_state.ops.groups[gid]
	var all: Array = Companies.units_of(w, c)
	_stop(w, all)
	return {"cid": cid, "cap": int(c.captain), "lt": int(g.officer), "gid": gid, "members": (g.members as Array).duplicate(), "all": all}


## Moves the lieutenant and his platoon around p.
func _move_platoon(w: SimWorld, s: Dictionary, p: Vector2) -> void:
	_place(w, s.lt, p)
	var i := 0
	for m in s.members:
		if w.entities.has(int(m)):
			_place(w, int(m), p + Vector2(float(i % 3) - 1.0, float(i / 3) + 1.0))
			i += 1


func _delivered(evs: Array, oid: int) -> int:
	for ev in evs:
		if String(ev.type) == "OrderDelivered" and int(ev.id) == oid:
			return int(ev.order.at)
	return -1


func test_order_delay_grows_with_hops_and_distance() -> void:
	var w := _world()
	var s := _co(w)
	check(w.in_bounds(w.cell_of(_at(w, 75))), "test map is big enough")
	_place(w, s.cap, _at(w, 40))
	_place(w, s.lt, _at(w, 44))
	var near := CommandNet.delay_ticks(w, 0, s.cap, s.lt)
	_place(w, s.lt, _at(w, 62))
	var far := CommandNet.delay_ticks(w, 0, s.cap, s.lt)
	check(near > 0 and far > near, "captain -> lieutenant delay grows with distance (%d -> %d)" % [near, far])
	_place(w, s.lt, _at(w, 45))
	var direct := CommandNet.delay_ticks(w, 0, 0, s.lt)
	_place(w, s.lt, _at(w, 65))
	var relayed := CommandNet.delay_ticks(w, 0, 0, s.lt)
	check(direct > 0 and relayed - direct >= 20, "General -> lt: one more radio hop adds >= 1 s (%d -> %d)" % [direct, relayed])


func test_out_of_comms_order_waits_for_the_link() -> void:
	var w := _world()
	var s := _co(w)
	_place(w, s.cap, _at(w, 20))
	_move_platoon(w, s, _at(w, 85))
	CommandNet.rebuild(w, 0)
	check_eq(CommandNet.comms_state(w, s.lt), "cut", "lieutenant out of every radio range reads cut")
	check_eq(CommandNet.delay_ticks(w, 0, 0, s.lt), -1, "no link -> no delay")
	var oid := CommandNet.issue(w, 0, 0, {"platoon": s.gid}, {"type": "hold", "target": _at(w, 85), "intent": "hold the ford"})
	check(oid > 0, "order queued")
	var evs := _steps(w, 100)
	check_eq(_delivered(evs, oid), -1, "not delivered while cut off")
	var pend := CommandNet.pending_orders(w, 0)
	check(pend.size() == 1 and String(pend[0].status) == "waiting", "order waits for the link")
	_move_platoon(w, s, _at(w, 40))
	var t0 := w.tick
	evs = _steps(w, 120)
	var at := _delivered(evs, oid)
	check(at > t0, "delivered once the link is back (tick %d)" % at)
	CommandNet.rebuild(w, 0)
	check(["linked", "delayed"].has(CommandNet.comms_state(w, s.lt)), "lieutenant back in comms: %s" % CommandNet.comms_state(w, s.lt))
	check_eq(String(CommandNet.intent_of(w, s.lt).get("intent", "")), "hold the ford", "intent reached the platoon")


func test_jammer_increases_delay_and_can_cut() -> void:
	var w := _world()
	var s := _co(w)
	_place(w, s.cap, _at(w, 45))
	_place(w, s.lt, _at(w, 65))
	var d0 := CommandNet.delay_ticks(w, 0, s.cap, s.lt)
	check(d0 > 0, "linked before jamming (%d)" % d0)
	w.entities[s.lt].jammed_until = w.tick + 100000
	w.cache.erase("cn_graph")
	var seen_long := false
	var seen_drop := false
	for i in 4:
		var d := CommandNet.delay_ticks(w, 0, s.cap, s.lt)
		if d < 0:
			seen_drop = true
		elif d >= d0 * 2:
			seen_long = true
		_steps(w, 20)
		_place(w, s.cap, _at(w, 45))
		_place(w, s.lt, _at(w, 65))
	check(seen_long, "jamming multiplies the delay")
	check(seen_drop, "a jammed link drops some net cycles")
	w.entities[s.cap].jammed_until = w.tick + 100000
	w.cache.erase("cn_graph")
	check_eq(CommandNet.delay_ticks(w, 0, s.cap, s.lt), -1, "both ends jammed: ranges shrink, link cut")
	CommandNet.rebuild(w, 0)
	check(["jammed", "cut"].has(CommandNet.comms_state(w, s.lt)), "jammed lt shows jammed/cut: %s" % CommandNet.comms_state(w, s.lt))


func test_reports_reach_the_captain() -> void:
	var w := _world()
	var s := _co(w)
	_place(w, s.cap, _at(w, 20))
	_move_platoon(w, s, _at(w, 32))
	var rid := CommandNet.report(w, 0, s.lt, "contact", "Lt: test contact", {"count": 3})
	check(rid > 0, "report sent")
	check_eq(CommandNet.report(w, 0, s.lt, "contact", "Lt: spam", {}), 0, "same kind within report_min_s is rate-limited")
	check_eq(CommandNet.reports(w, 0, s.cap, 5).size(), 0, "not arrived instantly")
	_steps(w, 60)
	var got := CommandNet.reports(w, 0, s.cap, 5)
	check(got.size() >= 1 and String(got[0].text) == "Lt: test contact" and int(got[0].from) == s.lt, "captain got the lieutenant's report")
	_steps(w, 60)
	check(CommandNet.reports(w, 0, 0, 10).size() >= 1, "report travelled on up to the General")
	var foe := U.role_unit(w, 1, "infantry")
	w.spawn_unit(foe, 1, _at(w, 32, 6.0))
	_steps(w, 100)
	var contact := false
	for r in CommandNet.reports(w, 0, s.cap, 20):
		if String(r.kind) == "contact" and int(r.from) == s.lt and int(r.data.get("count", 0)) >= 1:
			contact = true
	check(contact, "automatic contact report from the lieutenant reached the captain")
	var tr := CommandNet.tree(w, 0)
	check(tr.companies.size() == 1 and int(tr.companies[0].platoons[0].lieutenant) == s.lt, "tree shows company > platoon > lieutenant")
	check_eq(CommandNet.leader_of(w, s.lt), s.cap, "lieutenant reports to the captain")
	var lines: Array = CommandNet.inspector_lines(w, s.cap)
	check(lines.size() >= 3 and String(lines[0]).begins_with("Comms: ") and String(lines[1]) == "Reports to: General", "inspector lines: %s" % str(lines))


func test_cut_off_platoon_continues_last_intent() -> void:
	var w := _world()
	var s := _co(w)
	_place(w, s.cap, _at(w, 45))
	_move_platoon(w, s, _at(w, 70))
	var tgt := _at(w, 30)
	var oid := CommandNet.issue(w, 0, s.cap, {"platoon": s.gid}, {"type": "advance", "target": tgt, "intent": "take the crossroads", "then": "hold"})
	var evs := _steps(w, 60)
	check(_delivered(evs, oid) > 0, "order delivered")
	CommandNet.take_orders(w, s.lt)  # the level's owner consumed it
	_stop(w, s.all)
	_place(w, s.cap, _at(w, 5))
	CommandNet.rebuild(w, 0)
	check_eq(CommandNet.comms_state(w, s.lt), "cut", "platoon cut off")
	var ini := CommandNet.initiative(w, s.lt)
	check(String(ini.act) == "continue" and ini.target is Vector2 and (ini.target as Vector2).distance_to(tgt) < 0.01, "initiative: continue to the last objective (%s)" % String(ini.act))
	evs = _steps(w, 220)
	var acted := false
	for ev in evs:
		if String(ev.type) == "Initiative" and String(ev.node) == "p:%d" % s.gid and String(ev.act) == "continue":
			acted = true
	check(acted, "cut-off platoon acted on its own")
	var moving := 0
	for m in s.members:
		var e = w.entities.get(int(m))
		if e != null and String(e.get("order", {}).get("type", "")) == "attack_move":
			moving += 1
	check(moving > 0, "platoon members advance on the last intent (%d)" % moving)


func test_leader_death_succession_after_confusion() -> void:
	var w := _world()
	var s := _co(w)
	_place(w, s.cap, _at(w, 20))
	_move_platoon(w, s, _at(w, 30))
	_steps(w, 20)
	w.destroy(s.lt, "test")
	var evs := _steps(w, 20)
	var succ := {}
	for ev in evs:
		if String(ev.type) == "Succession" and String(ev.node) == "p:%d" % s.gid:
			succ = ev
	var g: Dictionary = w.sys_state.ops.groups.get(s.gid, {})
	check(not succ.is_empty() and not g.is_empty() and int(succ.new) == int(g.officer), "next senior takes the platoon")
	var until := int(CommandNet.state(w).confused.get("p:%d" % s.gid, -1))
	check(until > w.tick, "confusion delay running (until %d, now %d)" % [until, w.tick])
	var oid := CommandNet.issue(w, 0, s.cap, {"platoon": s.gid}, {"type": "hold", "target": _at(w, 30)})
	evs = _steps(w, 240)
	var at := _delivered(evs, oid)
	check(at >= until, "order reaches the new leader only after the confusion (%d >= %d)" % [at, until])


func test_belief_keeps_last_known_and_decays() -> void:
	var w := _world()
	var obs := w.spawn_unit(U.role_unit(w, 0, "infantry"), 0, _at(w, 30))
	var foe := w.spawn_unit(U.role_unit(w, 1, "infantry"), 1, _at(w, 30, 4.0))
	var p := _at(w, 30, 4.0)
	_stop(w, [obs])
	Fog.recompute(w)
	Intel.refresh(w, 0)
	var c := Intel.known(w, 0, foe)
	check(not c.is_empty() and float(c.conf) > 0.95, "seen contact is believed with full confidence")
	_place(w, foe, _at(w, 80, -10.0))
	_place(w, obs, _hq(w))
	_steps(w, 40)
	Fog.recompute(w)
	Intel.refresh(w, 0)
	c = Intel.known(w, 0, foe)
	check(not c.is_empty() and (c.pos as Vector2).distance_to(p) < 0.01, "lost contact keeps its last-known position")
	var c1 := float(c.get("conf", 0.0))
	_steps(w, 200)
	var c2 := Intel.confidence(w, 0, foe)
	check(c1 < 1.0 and c2 < c1 and c2 > 0.0, "confidence decays with age (%.2f -> %.2f)" % [c1, c2])
	var truth := 0
	for e in w.units_of(1):
		if Vector2(e.pos).distance_to(p) < 3.0:
			truth += 1
	check(truth == 0 and Intel.contacts(w, 0, p, 3.0).size() == 1 and Intel.strength_at(w, 0, p, 3.0) > 0.0,
		"AI query from belief differs from the truth after the enemy moved unseen")
	check(Intel.threats_to(w, 0, p + Vector2(1, 0)).size() == 1, "belief threats_to sees the remembered contact")


func test_decoy_registers_until_identified() -> void:
	var w := _world()
	var obs := w.spawn_unit(U.role_unit(w, 0, "infantry"), 0, _at(w, 30))
	_stop(w, [obs])
	var cell := w.cell_of(_at(w, 30, 6.0))
	var dec := w.spawn_building("s_camo_decoy", 1, cell, true)
	Fog.recompute(w)
	Intel.refresh(w, 0)
	var c := Intel.known(w, 0, dec)
	check(not c.is_empty() and not bool(c.decoy) and float(c.strength) > 0.0, "decoy registers as a real contact from range")
	_place(w, obs, Vector2(w.entities[dec].pos) + Vector2(1.5, 0))
	Fog.recompute(w)
	Intel.refresh(w, 0)
	c = Intel.known(w, 0, dec)
	check(not c.is_empty() and bool(c.decoy) and float(c.strength) == 0.0, "identified up close: decoy, no strength")


func _scenario(w: SimWorld) -> Dictionary:
	var s := _co(w)
	_place(w, s.cap, _at(w, 45))
	_move_platoon(w, s, _at(w, 65))
	w.entities[s.lt].jammed_until = w.tick + 100000
	s["oid"] = CommandNet.issue(w, 0, 0, {"platoon": s.gid}, {"type": "hold", "target": _at(w, 60)})
	CommandNet.report(w, 0, s.lt, "status", "Lt: in position", {})
	return s


func test_determinism_and_save_mid_delivery() -> void:
	var a := _world()
	var b := _world()
	var sa := _scenario(a)
	_scenario(b)
	_steps(a, 5)
	_steps(b, 5)
	var mid: Array = CommandNet.pending_orders(a, 0)
	check(mid.size() == 1, "order in flight at save time")
	var c := SimWorld.from_dict(bytes_to_var(var_to_bytes(a.to_dict())))
	check_eq(c.state_hash(), a.state_hash(), "save round trip keeps the hash mid-delivery")
	var ea := _steps(a, 400)
	_steps(b, 400)
	var ec := _steps(c, 400)
	check_eq(a.state_hash(), b.state_hash(), "same seed + commands = same hash")
	check_eq(c.state_hash(), a.state_hash(), "loaded world matches the uninterrupted one")
	check(_delivered(ea, int(sa.oid)) > 0 and _delivered(ec, int(sa.oid)) == _delivered(ea, int(sa.oid)), "delivered on the same tick after load")
