extends RefCounted
## General <-> chain of command (owner: GEN61; G6.1 GEN61-2). An auto general's operation intent goes DOWN
## the CHAIN61 CommandNet (CommandNet.issue(w, fid, 0, {company: cid}, order), from_id 0 = the General) at
## every phase change, one order per company of the slot, so it travels with radio delay / range / jamming.
## A company acts on the general's phase orders only once its captain has the order: the general consumes
## it (CommandNet.take_orders, the double-control rule: the net's default executor and Doctrine.consume_net
## then leave it alone) and until then the company's units are HELD (General.order skips them). No link
## for net_wait ticks: a runner gets through (the hold is released) and the log says so.
## Order types are CommandNet mission types outside Doctrine.ORDER_TYPES (assault, advance, infil, dig_in,
## flank, reposition, fall_back), so OFF61's drills never execute the general's intent a second time.
## Reports coming UP (CommandNet.reports(w, fid, 0)) from the slot's own units re-plan the general: contact /
## casualty -> re-plan now; request fire_support -> fire missions now; resupply / medevac -> logistics now;
## reinforcement -> war effort now.
## State (saved and hashed with the slot): S.gen.net {cid: {oid, op, sent, since, got}} (got -1 = in transit,
##   -2 = released without a delivery, else the delivery tick); S.gen.rep_seen (last report id handled).
## Events: AiGeneralOrder {fid, slot, cid, oid, delay, by: "radio" | "runner"}.

const L = preload("res://sim/ai/ai_g6_lib.gd")
const NET_TYPE := {"strike": "assault", "attack": "advance", "infil": "infil", "raid_supply": "infil",
	"defend": "dig_in", "counter": "flank", "recon_force": "reposition", "screen": "dig_in", "refit": "fall_back"}
const RULES := {"net_wait": 600, "report_lines": 2}


static func NR(key: String):
	var ac = Content.rules().get("ai_cmd", null)
	var src = ac.get("net", null) if ac is Dictionary else null
	if src is Dictionary and src.has(key):
		return src[key]
	return RULES.get(key)


static var _gs: Script = null


static func Gen() -> Script:
	if _gs == null:
		_gs = load("res://sim/ai/general.gd")
	return _gs


static func Net() -> Script:
	var n := L.sys("command_net")
	return n if n != null and L.api(n, "issue") and L.api(n, "take_orders") else null


static func _companies(w: SimWorld, fid: int, s: Dictionary) -> Array:
	var out := []
	var cs: Dictionary = w.sys_state.get("companies", {}).get("companies", {})
	for cid in (s.spec as Dictionary).get("companies", []):
		var c = cs.get(int(cid))
		if c is Dictionary and int(c.get("owner", -1)) == fid and not out.has(int(cid)):
			out.append(int(cid))
	out.sort()
	return out


## Sends the current op + phase as intent to every company of the slot (called from General.phase).
static func send_intent(w: SimWorld, fid: int, s: Dictionary) -> void:
	var g: Dictionary = s.gen
	var op: Dictionary = g.op
	if op.is_empty() or ["done", "failed"].has(String(op.phase)):
		return
	var cids := _companies(w, fid, s)
	if cids.is_empty():
		return
	var net := Net()
	if net == null:
		return
	var t := String(op.type)
	var tgt: Vector2 = Vector2(op.rally) if t == "refit" else Vector2(op.tgt)
	var main_ids := {}
	for id in (op.get("els", {}) as Dictionary).get("main", []):
		main_ids[int(id)] = true
	var cs: Dictionary = w.sys_state.get("companies", {}).get("companies", {})
	var nets: Dictionary = g.get("net", {})
	for cid in cids:
		var main: bool = main_ids.is_empty() and cid == int(cids[0])
		if not main_ids.is_empty():
			for id in Gen().C().company_units(w, fid, cs[cid]):
				if main_ids.has(int(id)):
					main = true
					break
		var order := {"type": String(NET_TYPE.get(t, "advance")), "target": [snappedf(tgt.x, 0.01), snappedf(tgt.y, 0.01)],
			"intent": "Op %s: %s" % [String(Gen().OP_LABEL.get(t, t)), String(op.phase)], "source": "general",
			"gen_op": t, "gen_phase": String(op.phase), "op_id": int(op.id), "slot": int(s.get("slot", -1)), "main_effort": main}
		var oid := int(net.issue(w, fid, 0, {"company": cid}, order))
		if oid > 0:
			var since := w.tick
			if nets.has(cid) and int(nets[cid].got) == -1:
				since = int(nets[cid].get("since", nets[cid].sent))  # still no link: the hold keeps its start
			nets[cid] = {"oid": oid, "op": int(op.id), "sent": w.tick, "since": since, "got": -1}
	g.net = nets


## Consumes the general's own delivered orders (take_orders) and releases the hold on each company that has
## its order (or after net_wait without a link).
static func consume(w: SimWorld, fid: int, s: Dictionary) -> void:
	var g: Dictionary = s.gen
	var nets: Dictionary = g.get("net", {})
	if nets.is_empty():
		return
	var net := Net()
	var keys := nets.keys()
	keys.sort()
	for cid in keys:
		var r: Dictionary = nets[cid]
		if int(r.got) != -1:
			continue
		if net == null:
			r.got = -2
			continue
		var leader := int(net.node_leader(w, fid, "c:%d" % int(cid)))
		var box: Array = net.orders_for(w, leader) if leader != 0 else []
		var has_mine := false
		var any_mine := false
		var only_general := true
		for rec in box:
			if String(rec.get("source", "")) != "general" or int(rec.get("slot", -99)) != int(s.get("slot", -1)):
				only_general = false
			else:
				any_mine = true
				if int(rec.get("id", 0)) == int(r.oid):
					has_mine = true
		if any_mine and only_general and not has_mine:
			net.take_orders(w, leader)  # an earlier phase's order arrived late: superseded, swallowed (no net replay)
		elif has_mine and only_general:
			for rec in net.take_orders(w, leader):
				if int(rec.get("id", 0)) == int(r.oid):
					r.got = maxi(int(rec.get("at", w.tick)), int(r.sent))
			_delivered(w, fid, s, int(cid), r, "radio")
		elif has_mine:
			r.got = -2  # another order is in the captain's inbox too: the net / Doctrine owns that inbox
			_delivered(w, fid, s, int(cid), r, "radio")
		elif w.tick - int(r.get("since", r.sent)) >= int(NR("net_wait")):
			r.got = -2
			_delivered(w, fid, s, int(cid), r, "runner")
			Gen().log_line(w, s, "Radio: no link to company %d, a runner carries the order." % int(cid))


static func _delivered(w: SimWorld, fid: int, s: Dictionary, cid: int, r: Dictionary, by: String) -> void:
	var at := int(r.got) if int(r.got) >= 0 else w.tick
	w.emit("AiGeneralOrder", {"fid": fid, "slot": int(s.get("slot", -1)), "cid": cid, "oid": int(r.oid),
		"delay": at - int(r.sent), "by": by})


## Unit ids the general may not order yet: their company's current order is still on the radio.
static func held(w: SimWorld, fid: int, s: Dictionary) -> Dictionary:
	var nets: Dictionary = s.gen.get("net", {})
	if nets.is_empty():
		return {}
	var k := "gen61_held_%d_%d" % [fid, int(s.get("slot", -1))]
	var c = w.cache.get(k)
	if c is Array and int(c[0]) == w.tick and int(c[1]) == nets.hash():
		return c[2]
	var out := {}
	var cs: Dictionary = w.sys_state.get("companies", {}).get("companies", {})
	var keys := nets.keys()
	keys.sort()
	for cid in keys:
		if int(nets[cid].got) == -1 and cs.get(int(cid)) is Dictionary:
			for id in Gen().C().company_units(w, fid, cs[int(cid)]):
				out[int(id)] = true
	w.cache[k] = [w.tick, nets.hash(), out]
	return out


## Reports from the slot's own units that reached the General re-plan it.
static func read_reports(w: SimWorld, fid: int, s: Dictionary, us: Array) -> void:
	var n := L.sys("command_net")
	if n == null or not L.api(n, "reports"):
		return
	var g: Dictionary = s.gen
	var seen := int(g.get("rep_seen", 0))
	var lst: Array = n.reports(w, fid, 0, 10)
	if lst.is_empty() or int(lst[0].id) <= seen:
		return
	var mine := {}
	for e in us:
		mine[int(e.id)] = true
	var lines := 0
	var i := lst.size() - 1
	while i >= 0:
		var r: Dictionary = lst[i]
		i -= 1
		if int(r.id) <= seen:
			continue
		g.rep_seen = maxi(int(g.get("rep_seen", 0)), int(r.id))
		if not mine.has(int(r.from)):
			continue
		var kind := String(r.kind)
		var req := String((r.data as Dictionary).get("request", ""))
		match kind:
			"contact", "casualty":
				g.next_plan = mini(int(g.next_plan), w.tick)
			"request":
				match req:
					"fire_support":
						g.fire_tick = w.tick
						g.w2_fire = w.tick
					"resupply", "medevac":
						g.w2_log = w.tick
					"reinforcement":
						g.war_tick = w.tick
						g.w2_prod = w.tick
		if lines < int(NR("report_lines")) and (kind == "request" or kind == "contact" or kind == "casualty"):
			lines += 1
			Gen().log_line(w, s, "Report: %s" % String(r.text))
