extends RefCounted
## G6.1 CHAIN61 playtest flow (--ui-playtest-chain61): a rifle company near the HQ; select its lieutenant and
## show his comms state, orders and reports (CommandNet.inspector_lines, shot); move him out of every radio
## range and show the cut-off state (shot); bring him back and see the waiting order arrive.

const CommandNet = preload("res://sim/systems/command_net.gd")
const Companies = preload("res://sim/systems/companies.gd")
const HotState = preload("res://sim/hot_state.gd")
const Movement = preload("res://sim/systems/movement.gd")


func _toward_centre(w: SimWorld, from: Vector2, k: float) -> Vector2:
	var c := Vector2(float(w.map.w), float(w.map.h)) * 0.5
	return from + (c - from).normalized() * k


func run(pt) -> void:
	var hq: Dictionary = pt._hq()
	pt._log("chain_hq", not hq.is_empty())
	if hq.is_empty():
		return
	pt._mv().join_sim()
	var w: SimWorld = pt._w()
	var hp := Vector2(hq.pos)
	var near := _toward_centre(w, hp, 10.0)
	var cid := Companies.spawn_company_at(w, 0, "a_rifle_co", "platoon", w.cell_of(near), near)
	pt._log("chain_company", cid > 0, "company %d" % cid)
	if cid <= 0:
		return
	var c: Dictionary = w.sys_state.companies.companies[cid]
	var gid := int(c.platoons[0])
	var lt := int(w.sys_state.ops.groups[gid].officer)
	var cap := int(c.captain)
	Movement.apply_command(w, {"type": "stop", "issuer": 0, "unit_ids": Companies.units_of(w, c)})
	var oid := CommandNet.issue(w, 0, cap, {"platoon": gid}, {"type": "hold", "target": near, "intent": "hold the HQ approach"})
	CommandNet.report(w, 0, lt, "status", "Lt #%d: platoon formed, holding" % lt, {})
	pt._log("chain_order_issued", oid > 0, "order %d" % oid)
	await pt._wait(4.0)
	pt._mv().join_sim()
	w = pt._w()
	CommandNet.rebuild(w, 0)
	pt._log("chain_select_lt", await pt._g5_select(lt))
	var st := CommandNet.comms_state(w, lt)
	pt._log("chain_lt_linked", st == "linked" or st == "delayed", st)
	var lines: Array = CommandNet.inspector_lines(w, lt)
	pt._log("chain_lt_lines", lines.size() >= 2 and String(lines[0]).begins_with("Comms: "), str(lines))
	var got := CommandNet.reports(w, 0, cap, 5)
	pt._log("chain_captain_reports", got.size() >= 1, str(got.map(func(r): return String(r.text))))
	pt._log("chain_intent", String(CommandNet.intent_of(w, lt).get("intent", "")) == "hold the HQ approach")
	await pt._shot("chain61_officer_linked")
	# out of every radio range: cut off
	pt._mv().join_sim()
	w = pt._w()
	var far := _toward_centre(w, hp, 75.0)
	# G6.1 ORCH: move the lieutenant's whole platoon (squad AI leashes a lone officer back to its men)
	var plt := int(w.entities[lt].get("platoon", -1))
	var group := [lt]
	if plt >= 0:
		for id in w.entities:
			var o: Dictionary = w.entities[id]
			if o.kind == "unit" and int(o.owner) == 0 and int(o.get("platoon", -2)) == plt and not group.has(int(id)):
				group.append(int(id))
	var k := 0
	for id in group:
		HotState.set_pos(w, int(id), far + Vector2(float(k % 6) * 0.9, float(k / 6) * 0.9))
		k += 1
	Movement.apply_command(w, {"type": "hold", "issuer": 0, "unit_ids": group})
	var oid2 := CommandNet.issue(w, 0, 0, lt, {"type": "move", "target": far, "intent": "recon the ford"})
	await pt._wait(2.0)
	pt._mv().join_sim()
	w = pt._w()
	CommandNet.rebuild(w, 0)
	pt._log("chain_lt_cut", CommandNet.comms_state(w, lt) == "cut", CommandNet.comms_state(w, lt))
	var waiting := false
	for o in CommandNet.pending_orders(w, 0):
		if int(o.id) == oid2 and String(o.status) == "waiting":
			waiting = true
	pt._log("chain_order_waits", waiting)
	await pt._wait(0.8)  # G6.1 ORCH: no double-click with the previous select (double-click = whole squad)
	var sel_ok: bool = await pt._g5_select(lt)
	if not sel_ok:
		await pt._wait(0.8)
		sel_ok = await pt._g5_select(lt)
	pt._log("chain_select_cut", sel_ok)
	lines = CommandNet.inspector_lines(w, lt)
	pt._log("chain_cut_lines", lines.size() >= 1 and String(lines[0]).begins_with("Comms: Cut off"), str(lines))
	await pt._shot("chain61_officer_cut")
	# back in range: the waiting order arrives
	pt._mv().join_sim()
	w = pt._w()
	HotState.set_pos(w, lt, _toward_centre(w, hp, 20.0))
	Movement.apply_command(w, {"type": "stop", "issuer": 0, "unit_ids": [lt]})
	var ok: bool = await pt._wait_until(func(): return String(CommandNet.intent_of(pt._w(), lt).get("intent", "")) == "recon the ford", 10.0)
	pt._log("chain_order_after_link", ok)
	await pt._shot("chain61_officer_relinked")
