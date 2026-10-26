extends RefCounted
## Plans (G6.1, owner: PLAN61): the player's command layer. A plan drawn on the map (objectives, axis of
## advance, phase lines, timing) is turned into chain-of-command orders for a formation's platoons.
## Commands: issue_plan {issuer, plan}, cancel_plan {issuer, plan_id}, plan_signal {issuer, plan_id, signal}.
##
## plan (command input) = {formation: {kind: "company"|"army"|"platoon", id}, intent (INTENTS),
##   objectives: [cell], axis: [cell], phase_lines: [{name?, points: [cell]}], timing: {mode: "now"|"signal"|
##   "at", t: seconds (mode at)}, main_effort: bool, fire_support: [{cell, kind}], halt_at_pl: bool (true),
##   pl_hold_s: float (0 = wait for a signal at each phase line)}. A cell is Vector2i, Vector2 or [x, y].
##
## Saved state (hashed; created by the first issue_plan, so a match without plans hashes as before):
##   w.sys_state.plans = {plans: {pid: plan}, next_id}
##   plan = {id, owner, formation, intent, objectives: [Vector2i], axis: [Vector2i], phase_lines:
##     [{name, points: [Vector2i]}], timing, main_effort, fire_support, halt_at_pl, pl_hold_s,
##     legs: [{kind: "pl"|"obj"|"screen"|"withdraw", idx, pos: Vector2, name}], leg (-1 = not started),
##     allow (highest authorised leg, -1 = none), sent: {gid: leg}, sent_tick: {gid: tick}, reached_tick
##     (-1 = moving), status, line, pl_reached, obj_held: [bool], start_units, losses, origin: Vector2,
##     active, issued, at_tick}
## Statuses: waiting, advancing, halted, on_objective, holding, withdrawing, withdrawn, cancelled, destroyed.
## Orders go down the radio net through CHAIN61's CommandNet.issue(w, fid, 0, {platoon: gid}, order) (comms delay,
## the lieutenant's intent for initiative); PLAN61 applies each as an Ops set_mission once it has left the net
## (order.source == "plan": other consumers treat it as intent only). Without a net it goes straight to Ops. Ops keeps every player-
## override / Hold Position rule, so a plan never fights a direct order.

const Ops = preload("res://sim/systems/ops.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Companies = preload("res://sim/systems/companies.gd")

const INTENTS := ["attack", "defend", "raid", "screen", "withdraw"]
const TIMINGS := ["now", "signal", "at"]
const KINDS := ["company", "army", "platoon"]
const FIRE_KINDS := ["artillery", "air", "mortar", "smoke"]
const PL_NAMES := ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO", "FOXTROT", "GOLF", "HOTEL"]
const EVAL_EVERY := 10
const MAX_ACTIVE := 12
const MAX_OBJ := 6
const MAX_AXIS := 16
const MAX_PL := 6
const MAX_PL_PTS := 8
const MAX_FIRE := 4
const KEEP_DONE := 8
const REACH := 5.0          # tiles: a platoon centroid this close to its point has reached it
const OBJ_R := 6.0          # tiles: own units this close hold an objective
const SPACING := 4.0        # tiles between platoons abreast
const RAID_HOLD_S := 20.0   # raid: seconds on the objective before pulling back
const RESEND_TICKS := 400   # an order that never became a mission is sent again after this
const NET_PATH := "res://sim/systems/command_net.gd"


# ================================================================ state
static func state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("plans"):
		w.sys_state["plans"] = {"plans": {}, "next_id": 1}
	return w.sys_state["plans"]


## Read-only plans dict (no state creation).
static func all(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("plans"):
		return {}
	return w.sys_state.plans.plans


static func get_plan(w: SimWorld, pid: int) -> Dictionary:
	return all(w).get(pid, {})


## Plans of a side, ascending id (active first when only_active).
static func plans_of(w: SimWorld, fid: int, only_active: bool = false) -> Array:
	var out := []
	var d := all(w)
	var ids := d.keys()
	ids.sort()
	for pid in ids:
		var p: Dictionary = d[pid]
		if int(p.owner) == fid and (not only_active or bool(p.active)):
			out.append(p)
	return out


# ================================================================ geometry
## Cell from Vector2i / Vector2 / [x, y], or null.
static func to_cell(v):
	match typeof(v):
		TYPE_VECTOR2I:
			return v
		TYPE_VECTOR2:
			return Vector2i(floori(v.x), floori(v.y))
		TYPE_ARRAY:
			var a: Array = v
			if a.size() == 2 and typeof(a[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(a[1]) in [TYPE_INT, TYPE_FLOAT]:
				return Vector2i(int(a[0]), int(a[1]))
	return null


static func cell_pos(c: Vector2i) -> Vector2:
	return Vector2(c) + Movement.CENTER


## Cells of a list (null when any entry is not an in-bounds cell or the list is too long).
static func _cells(w: SimWorld, raw, max_n: int):
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() > max_n:
		return null
	var out := []
	for v in raw:
		var c = to_cell(v)
		if c == null or not w.in_bounds(c):
			return null
		out.append(c)
	return out


static func _seg_hit(a: Vector2, b: Vector2, c: Vector2, d: Vector2):
	var r := b - a
	var s := d - c
	var den := r.cross(s)
	if absf(den) < 0.000001:
		return null
	var t := (c - a).cross(s) / den
	var u := (c - a).cross(r) / den
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return null
	return a + r * t


static func _closest_on_seg(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)


## Closest point to p on a polyline of world points.
static func closest_on_line(p: Vector2, line: Array) -> Vector2:
	if line.size() == 1:
		return line[0]
	var best: Vector2 = line[0]
	var bd := INF
	for i in line.size() - 1:
		var q := _closest_on_seg(p, line[i], line[i + 1])
		var d := q.distance_squared_to(p)
		if d < bd:
			bd = d
			best = q
	return best


## Where the axis (world points) crosses a phase line (world points); else the line's point nearest `from`.
static func cross_point(axis: Array, pl: Array, from: Vector2) -> Vector2:
	for i in axis.size() - 1:
		for j in pl.size() - 1:
			var h = _seg_hit(axis[i], axis[i + 1], pl[j], pl[j + 1])
			if h != null:
				return h
	return closest_on_line(from, pl)


## Point at fraction f (0..1) of a polyline's length.
static func along(line: Array, f: float) -> Vector2:
	if line.size() == 1:
		return line[0]
	var total := 0.0
	for i in line.size() - 1:
		total += (line[i + 1] as Vector2).distance_to(line[i])
	var want := total * clampf(f, 0.0, 1.0)
	for i in line.size() - 1:
		var seg := (line[i + 1] as Vector2).distance_to(line[i])
		if want <= seg or i == line.size() - 2:
			return (line[i] as Vector2).lerp(line[i + 1], 0.0 if seg <= 0.0 else clampf(want / seg, 0.0, 1.0))
		want -= seg
	return line[line.size() - 1]


static func _pts(cells: Array) -> Array:
	var out := []
	for c in cells:
		out.append(cell_pos(c))
	return out


# ================================================================ formations
## Platoon group ids of a formation (existing groups only, ascending order of the formation's list).
static func platoons(w: SimWorld, f: Dictionary) -> Array:
	var groups: Dictionary = w.sys_state.ops.groups if w.sys_state.has("ops") else {}
	var gids := []
	match String(f.get("kind", "")):
		"platoon":
			gids = [int(f.get("id", -1))]
		"company":
			gids = (_company(w, int(f.get("id", -1))).get("platoons", []) as Array).duplicate()
		"army":
			for cid in _army(w, int(f.get("id", -1))).get("companies", []):
				gids.append_array(_company(w, int(cid)).get("platoons", []))
	var out := []
	for gid in gids:
		if groups.has(int(gid)) and not out.has(int(gid)):
			out.append(int(gid))
	return out


static func _company(w: SimWorld, cid: int) -> Dictionary:
	if not w.sys_state.has("companies"):
		return {}
	return w.sys_state.companies.get("companies", {}).get(cid, {})


static func _army(w: SimWorld, aid: int) -> Dictionary:
	if not w.sys_state.has("companies"):
		return {}
	return w.sys_state.companies.get("armies", {}).get(aid, {})


## Owner of a formation (-1 when it does not exist).
static func formation_owner(w: SimWorld, f: Dictionary) -> int:
	match String(f.get("kind", "")):
		"company":
			return int(_company(w, int(f.get("id", -1))).get("owner", -1))
		"army":
			return int(_army(w, int(f.get("id", -1))).get("owner", -1))
		"platoon":
			if w.sys_state.has("ops"):
				return int(w.sys_state.ops.groups.get(int(f.get("id", -1)), {}).get("owner", -1))
	return -1


## Live units of a formation: officers, leaders and members (ascending id).
static func formation_units(w: SimWorld, f: Dictionary) -> Array:
	var ids := []
	var groups: Dictionary = w.sys_state.ops.groups if w.sys_state.has("ops") else {}
	for gid in platoons(w, f):
		var g: Dictionary = groups[gid]
		ids.append(int(g.officer))
		ids.append_array(g.members)
	for lid in leaders(w, f):
		ids.append(lid)
	var out := []
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null and e.kind == "unit" and not out.has(int(id)):
			out.append(int(id))
	out.sort()
	return out


## Captains (company/army) that move with the formation but lead no platoon.
static func leaders(w: SimWorld, f: Dictionary) -> Array:
	var cids := []
	match String(f.get("kind", "")):
		"company":
			cids = [int(f.get("id", -1))]
		"army":
			cids = (_army(w, int(f.get("id", -1))).get("companies", []) as Array).duplicate()
	var out := []
	for cid in cids:
		var cap := int(_company(w, int(cid)).get("captain", -1))
		var e = w.entities.get(cap)
		if e != null and e.kind == "unit":
			out.append(cap)
	return out


## The formation an officer commands ({} when none): Commander -> army, captain -> company,
## lieutenant / G2 officer -> platoon (UI quick orders).
static func formation_of_officer(w: SimWorld, uid: int) -> Dictionary:
	var e = w.entities.get(uid)
	if e == null or e.kind != "unit":
		return {}
	var role := String(e.get("rank_role", ""))
	if role == "commander":
		var a := Companies.army_of(w, uid)
		if not a.is_empty():
			return {"kind": "army", "id": int(a.id)}
	if role == "captain":
		var c := Companies.company_of(w, uid)
		if not c.is_empty():
			return {"kind": "company", "id": int(c.id)}
	var g := Ops.group_led_by(w, uid)
	if not g.is_empty():
		return {"kind": "platoon", "id": int(g.id)}
	return {}


static func _centroid(w: SimWorld, ids: Array) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null and e.kind == "unit":
			s += e.pos
			n += 1
	return s / float(n) if n > 0 else Vector2.ZERO


static func _platoon_ids(w: SimWorld, gid: int) -> Array:
	var g: Dictionary = w.sys_state.ops.groups.get(gid, {})
	if g.is_empty():
		return []
	var ids := [int(g.officer)]
	ids.append_array(g.members)
	return ids


## Platoons of the formation that still have someone in them.
static func _live_platoons(w: SimWorld, f: Dictionary) -> Array:
	var out := []
	for gid in platoons(w, f):
		var off = w.entities.get(int(w.sys_state.ops.groups[gid].officer))
		if off != null and off.kind == "unit":
			out.append(gid)
	return out


# ================================================================ legs and orders
## Legs: phase lines in drawing order, then the objectives (or the axis end); screen = the first phase line.
static func build_legs(plan: Dictionary, origin: Vector2) -> Array:
	var legs := []
	var objs := _pts(plan.objectives)
	var axis := _pts(plan.axis)
	if axis.size() < 2:
		var head: Vector2 = objs[0] if not objs.is_empty() else origin
		if objs.is_empty() and not (plan.phase_lines as Array).is_empty():
			head = along(_pts(plan.phase_lines[plan.phase_lines.size() - 1].points), 0.5)
		axis = [origin, head]
	if String(plan.intent) == "screen":
		var pl0 = plan.phase_lines[0]
		return [{"kind": "screen", "idx": 0, "pos": along(_pts(pl0.points), 0.5), "name": String(pl0.name)}]
	var prev: Vector2 = origin
	var i := 0
	for pl in plan.phase_lines:
		var p := cross_point(axis, _pts(pl.points), prev)
		legs.append({"kind": "pl", "idx": i, "pos": p, "name": String(pl.name)})
		prev = p
		i += 1
	if objs.is_empty():
		legs.append({"kind": "obj", "idx": -1, "pos": axis[axis.size() - 1], "name": "the end of the axis"})
	for k in objs.size():
		legs.append({"kind": "obj", "idx": k, "pos": objs[k], "name": "OBJ %d" % (k + 1)})
	return legs


static func _clamp_pos(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 0.5, float(w.map.w) - 0.5), clampf(p.y, 0.5, float(w.map.h) - 0.5))


## Platoon i of n's point on leg li: abreast across the direction of travel (spread along a screen line).
static func leg_target(w: SimWorld, plan: Dictionary, li: int, i: int, n: int) -> Vector2:
	var leg: Dictionary = plan.legs[li]
	if String(leg.kind) == "screen":
		return _clamp_pos(w, along(_pts(plan.phase_lines[0].points), (float(i) + 0.5) / float(maxi(n, 1))))
	var prev: Vector2 = plan.origin if li == 0 or String(leg.kind) == "withdraw" else plan.legs[li - 1].pos
	var dir: Vector2 = leg.pos - prev
	if String(leg.kind) == "withdraw":
		dir = plan.legs[maxi(li - 1, 0)].pos - leg.pos
	var perp := dir.orthogonal().normalized() if dir.length() > 0.01 else Vector2.RIGHT
	return _clamp_pos(w, leg.pos + perp * ((float(i) - float(n - 1) * 0.5) * SPACING))


## [ops mission type, radius] for leg li.
static func leg_mission(plan: Dictionary, li: int) -> Array:
	var leg: Dictionary = plan.legs[li]
	var last: bool = li == (plan.legs as Array).size() - 1
	match String(leg.kind):
		"screen":
			return ["hold_zone", 4.0]
		"pl", "withdraw":
			return ["secure_point", 3.0]
	if bool(plan.get("hold_final", false)):
		return ["hold_zone", 5.0]
	match String(plan.intent):
		"attack", "raid":
			return ["attack_area", 5.0]
	return ["hold_zone" if last else "secure_point", 5.0]


static func _risk(plan: Dictionary, li: int) -> String:
	if String(plan.intent) == "withdraw" or String(plan.legs[li].kind) == "withdraw":
		return "low"
	return "high" if bool(plan.main_effort) else "medium"


## CHAIN61 CommandNet (has_method-free guard: only when the function exists with the expected arity).
static func _net(fn: String, argc: int) -> Script:
	if not ResourceLoader.exists(NET_PATH):
		return null
	var s: Script = load(NET_PATH)
	if s == null:
		return null
	for m in s.get_script_method_list():
		if String(m.name) == fn and (m.args as Array).size() == argc:
			return s
	return null


## Sends the order down the radio net from the General (node 0): CommandNet.issue(w, fid, 0,
## {platoon: gid}, order) -> order id (> 0 = in transit). 0 when there is no net (deliver at once).
static func _net_issue(w: SimWorld, plan: Dictionary, gid: int, cmd: Dictionary) -> int:
	var s := _net("issue", 5)
	if s == null:
		return 0
	var order := {"type": cmd.mission, "kind": "mission", "mission": cmd.mission, "target": cmd.target, "radius": cmd.radius,
		"risk": cmd.risk, "intent": String(plan.intent), "main_effort": bool(plan.main_effort), "source": "plan",
		"plan_id": int(plan.id)}
	var r = s.callv("issue", [w, int(plan.owner), 0, {"platoon": gid}, order])
	return int(r) if typeof(r) in [TYPE_INT, TYPE_FLOAT] else 0


## Orders still on the radio net (ids), or [] without a net.
static func _net_pending(w: SimWorld, fid: int) -> Array:
	var s := _net("pending_orders", 2)
	if s == null:
		return []
	var out := []
	for o in s.callv("pending_orders", [w, fid]):
		if typeof(o) == TYPE_DICTIONARY:
			out.append(int(o.get("id", -1)))
	return out


## PLAN61 executes its own delivered orders: take them out of the lieutenant's inbox so the net's default
## executor does not act on them a second time. CommandNet.consume(w, uid, oid) when it exists; else
## take_orders(w, uid) only when every waiting order of that officer is a plan order (never eats others).
static func _net_consume(w: SimWorld, uid: int) -> void:
	var s := _net("orders_for", 2)
	if s == null:
		return
	var box: Array = s.callv("orders_for", [w, uid])
	if box.is_empty():
		return
	for o in box:
		if typeof(o) != TYPE_DICTIONARY or String(o.get("source", "")) != "plan":
			return
	if _net("take_orders", 2) != null:
		s.callv("take_orders", [w, uid])


static func _apply_ops(w: SimWorld, cmd: Dictionary) -> bool:
	if Ops.validate_command(w, cmd) != "":
		return false
	Ops.apply_command(w, cmd)
	return true


## Orders that left the net since the last evaluation reach their lieutenant now.
static func _deliver(w: SimWorld, plan: Dictionary) -> void:
	if (plan.pending as Dictionary).is_empty():
		return
	var still := _net_pending(w, int(plan.owner))
	var gids: Array = plan.pending.keys()
	gids.sort()
	for gid in gids:
		var p: Dictionary = plan.pending[gid]
		if not still.has(int(p.oid)):
			_apply_ops(w, p.cmd)
			_net_consume(w, int(p.cmd.officer_id))
			plan.pending.erase(gid)


## Cancel over the radio: the platoon's standing intent becomes "hold where you are", so the net's
## initiative (mission command when idle) does not carry on with the cancelled plan.
static func _net_halt(w: SimWorld, plan: Dictionary, gid: int) -> void:
	var s := _net("issue", 5)
	if s == null:
		return
	var c := _centroid(w, _platoon_ids(w, gid))
	s.callv("issue", [w, int(plan.owner), 0, {"platoon": gid}, {"type": "hold", "target": c, "source": "plan",
		"plan_id": int(plan.id), "intent": "hold"}])


static func _order_code(plan: Dictionary, li: int) -> int:
	return li * 2 + (1 if bool(plan.get("hold_final", false)) else 0)


## Sends leg li to platoon gid (index i of n) through the chain. True when the order is on its way.
static func _send(w: SimWorld, plan: Dictionary, gid: int, li: int, i: int, n: int) -> bool:
	var g: Dictionary = w.sys_state.ops.groups.get(gid, {})
	if g.is_empty():
		return false
	var mr := leg_mission(plan, li)
	var cmd := {"type": "set_mission", "issuer": int(plan.owner), "officer_id": int(g.officer), "mission": mr[0],
		"target": leg_target(w, plan, li, i, n), "radius": float(mr[1]), "risk": _risk(plan, li)}
	plan.sent[gid] = _order_code(plan, li)
	plan.sent_tick[gid] = w.tick
	plan.pending.erase(gid)
	var oid := _net_issue(w, plan, gid, cmd)
	if oid > 0:
		plan.pending[gid] = {"oid": oid, "cmd": cmd}
		return true
	return _apply_ops(w, cmd)


## Captains follow their platoons a little behind the line (never against a player order or Hold).
static func _move_leaders(w: SimWorld, plan: Dictionary, li: int) -> void:
	var leg: Dictionary = plan.legs[li]
	var prev: Vector2 = plan.origin if li == 0 else plan.legs[li - 1].pos
	var back: Vector2 = (prev - leg.pos).normalized() * 3.0 if prev.distance_to(leg.pos) > 0.01 else Vector2.ZERO
	var ids := []
	for lid in leaders(w, plan.formation):
		var e: Dictionary = w.entities[lid]
		if int(e.get("ops_override_until", -1)) > w.tick or String(e.order.get("type", "")) in ["hold", "retreat"]:
			continue
		ids.append(lid)
	if not ids.is_empty():
		Movement.apply_command(w, {"type": "move", "issuer": int(plan.owner), "unit_ids": ids,
			"target": _clamp_pos(w, leg.pos + back)})


static func _start_leg(w: SimWorld, plan: Dictionary, li: int, gids: Array) -> void:
	if li == 0 and int(plan.leg) < 0:
		plan.origin = _centroid(w, formation_units(w, plan.formation))
		plan.legs = build_legs(plan, plan.origin)
		for fs in plan.fire_support:
			w.emit("PlanFireSupport", {"plan_id": int(plan.id), "owner": int(plan.owner), "cell": fs.cell, "kind": fs.kind})
	plan.leg = li
	plan.reached_tick = -1
	plan.allow = maxi(int(plan.allow), li)
	plan.sent = {}
	plan.sent_tick = {}
	plan.pending = {}
	for i in gids.size():
		_send(w, plan, int(gids[i]), li, i, gids.size())
	_move_leaders(w, plan, li)
	var leg: Dictionary = plan.legs[li]
	plan.status = "withdrawing" if String(leg.kind) == "withdraw" else "advancing"
	w.emit("PlanLegStarted", {"plan_id": int(plan.id), "owner": int(plan.owner), "leg": li, "name": String(leg.name)})


## True when at least 2/3 of the live platoons stand within REACH of their point on the current leg.
static func _reached(w: SimWorld, plan: Dictionary, gids: Array) -> bool:
	var n := gids.size()
	var ok := 0
	for i in n:
		var c := _centroid(w, _platoon_ids(w, int(gids[i])))
		if c.distance_to(leg_target(w, plan, int(plan.leg), i, n)) <= REACH:
			ok += 1
	return n > 0 and ok * 3 >= n * 2


static func _update_objectives(w: SimWorld, plan: Dictionary, units: Array) -> void:
	var held := []
	for c in plan.objectives:
		var p := cell_pos(c)
		var h := false
		for id in units:
			if (w.entities[id].pos as Vector2).distance_to(p) <= OBJ_R:
				h = true
				break
		held.append(h)
	plan.obj_held = held


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	if not w.sys_state.has("plans"):
		return
	var d: Dictionary = w.sys_state.plans.plans
	if d.is_empty():
		return
	var ids := d.keys()
	ids.sort()
	for pid in ids:
		var p: Dictionary = d[pid]
		if bool(p.active) and (w.tick + int(pid)) % EVAL_EVERY == 0:
			step_plan(w, p)


## One evaluation of an active plan: losses, objectives, timing, leg progress, halts at phase lines.
static func step_plan(w: SimWorld, plan: Dictionary) -> void:
	var units := formation_units(w, plan.formation)
	var gids := _live_platoons(w, plan.formation)
	if units.is_empty() or gids.is_empty():
		end_plan(w, plan, "destroyed", "The formation has been destroyed.", false)
		return
	plan.losses = maxi(0, int(plan.start_units) - units.size())
	_deliver(w, plan)
	_update_objectives(w, plan, units)
	if String(plan.timing.mode) == "at" and int(plan.allow) < 0 and w.tick >= int(plan.at_tick):
		plan.allow = 0
	var li := int(plan.leg)
	if li < 0:
		if int(plan.allow) >= 0:
			_start_leg(w, plan, 0, gids)
		else:
			plan.status = "waiting"
		_line(plan)
		return
	var code := _order_code(plan, li)
	for i in gids.size():  # new or reformed platoons, and orders that never became a mission
		var gid := int(gids[i])
		var g: Dictionary = w.sys_state.ops.groups[gid]
		if int(plan.sent.get(gid, -1)) != code or ((g.mission as Dictionary).is_empty() and int(plan.reached_tick) < 0
				and w.tick - int(plan.sent_tick.get(gid, w.tick)) >= RESEND_TICKS):
			_send(w, plan, gid, li, i, gids.size())
	var leg: Dictionary = plan.legs[li]
	if int(plan.reached_tick) < 0:
		if not _reached(w, plan, gids):
			_line(plan)
			return
		plan.reached_tick = w.tick
		if String(leg.kind) == "pl":
			plan.pl_reached = maxi(int(plan.pl_reached), int(leg.idx) + 1)
		w.emit("PlanPhaseReached", {"plan_id": int(plan.id), "owner": int(plan.owner), "leg": li, "kind": String(leg.kind),
			"name": String(leg.name)})
	if String(leg.kind) == "withdraw":
		end_plan(w, plan, "withdrawn", "Withdrawn to the start line.", false)
		return
	if li == (plan.legs as Array).size() - 1:
		_on_final(w, plan, gids)
		_line(plan)
		return
	var halts: bool = String(leg.kind) == "pl" and bool(plan.halt_at_pl) and String(plan.intent) != "withdraw"
	if not halts or (float(plan.pl_hold_s) > 0.0 and w.tick - int(plan.reached_tick) >= int(float(plan.pl_hold_s) * SimWorld.TICK_RATE)):
		plan.allow = maxi(int(plan.allow), li + 1)
	if int(plan.allow) > li:
		_start_leg(w, plan, li + 1, gids)
	else:
		plan.status = "halted"
	_line(plan)


## On the last leg: attack consolidates (hold_zone), raid pulls back after RAID_HOLD_S, others hold.
static func _on_final(w: SimWorld, plan: Dictionary, gids: Array) -> void:
	var leg: Dictionary = plan.legs[int(plan.leg)]
	plan.status = "holding" if String(leg.kind) == "screen" or String(plan.intent) in ["defend", "withdraw"] else "on_objective"
	match String(plan.intent):
		"attack":
			if not bool(plan.get("hold_final", false)):
				plan["hold_final"] = true
				for i in gids.size():
					_send(w, plan, int(gids[i]), int(plan.leg), i, gids.size())
			plan.status = "holding"
		"raid":
			if w.tick - int(plan.reached_tick) >= int(RAID_HOLD_S * SimWorld.TICK_RATE):
				withdraw(w, plan)


## Pull back to where the plan started (signal "withdraw", or a raid's end).
static func withdraw(w: SimWorld, plan: Dictionary) -> void:
	var gids := _live_platoons(w, plan.formation)
	if gids.is_empty():
		return
	if int(plan.leg) >= 0 and String(plan.legs[int(plan.leg)].kind) == "withdraw":
		return
	if int(plan.leg) < 0:
		plan.origin = _centroid(w, formation_units(w, plan.formation))
		plan.leg = 0
	plan.legs.append({"kind": "withdraw", "idx": 0, "pos": plan.origin, "name": "the start line"})
	_start_leg(w, plan, (plan.legs as Array).size() - 1, gids)
	_line(plan)


## Ends a plan (stop_units: the platoons drop their plan missions and stand).
static func end_plan(w: SimWorld, plan: Dictionary, status: String, why: String, stop_units: bool) -> void:
	plan.active = false
	plan.status = status
	if stop_units and w.sys_state.has("ops"):
		for gid in platoons(w, plan.formation):
			var g: Dictionary = w.sys_state.ops.groups[gid]
			if plan.sent.has(gid) and not (g.mission as Dictionary).is_empty():
				var cmd := {"type": "cancel_mission", "issuer": int(plan.owner), "officer_id": int(g.officer)}
				if Ops.validate_command(w, cmd) == "":
					Ops.apply_command(w, cmd)
			if plan.sent.has(gid):
				_net_halt(w, plan, int(gid))
		plan.pending = {}
	plan.line = "Plan %d %s: %s" % [int(plan.id), status, why]
	w.emit("PlanEnded", {"plan_id": int(plan.id), "owner": int(plan.owner), "status": status})


static func _formation_name(f: Dictionary) -> String:
	return "%s %d" % [String(f.kind).capitalize(), int(f.id)]


static func _line(plan: Dictionary) -> void:
	plan.line = status_line(plan)


## Readable one-line status of a plan (HUD plan card, reports up the chain).
static func status_line(plan: Dictionary) -> String:
	if not bool(plan.active):
		return String(plan.line)
	var head := "Plan %d, %s %s" % [int(plan.id), String(plan.intent), _formation_name(plan.formation)]
	var what := ""
	var li := int(plan.leg)
	var legs: Array = plan.legs
	match String(plan.status):
		"waiting":
			what = "waiting for the signal" if String(plan.timing.mode) == "signal" else "waiting for H-hour"
		"advancing":
			what = "advancing to %s" % String(legs[li].name)
		"halted":
			what = "halted on %s, waiting for the signal" % String(legs[li].name)
		"on_objective":
			what = "on %s" % String(legs[li].name)
		"holding":
			what = "holding %s" % String(legs[li].name)
		"withdrawing":
			what = "withdrawing to the start line"
		_:
			what = String(plan.status)
	var held := 0
	for h in plan.obj_held:
		if h:
			held += 1
	return "%s: %s. PL %d/%d reached, objectives %d/%d held, losses %d." % [head, what, int(plan.pl_reached),
		(plan.phase_lines as Array).size(), held, (plan.objectives as Array).size(), int(plan.losses)]


# ================================================================ commands
## "" when plan p (command input form) is legal for side fid, else the reason (UI preview uses it too).
static func validate_plan(w: SimWorld, fid: int, p: Dictionary) -> String:
	var f = p.get("formation")
	if typeof(f) != TYPE_DICTIONARY or not KINDS.has(String(f.get("kind", ""))):
		return "Pick a company, army or platoon for the plan."
	if formation_owner(w, f) != fid:
		return "Select one of your formations."
	if formation_units(w, f).is_empty() or _live_platoons(w, f).is_empty():
		return "That formation has no platoons left."
	var intent := String(p.get("intent", ""))
	if not INTENTS.has(intent):
		return "Intent must be attack, defend, raid, screen or withdraw."
	var objs = _cells(w, p.get("objectives", []), MAX_OBJ)
	if objs == null:
		return "Objectives must be cells on the map (at most %d)." % MAX_OBJ
	var axis = _cells(w, p.get("axis", []), MAX_AXIS)
	if axis == null:
		return "The axis of advance must be cells on the map (at most %d points)." % MAX_AXIS
	var pls = p.get("phase_lines", [])
	if typeof(pls) != TYPE_ARRAY or (pls as Array).size() > MAX_PL:
		return "A plan takes at most %d phase lines." % MAX_PL
	for pl in pls:
		if typeof(pl) != TYPE_DICTIONARY:
			return "A phase line needs at least 2 points on the map."
		var pts = _cells(w, pl.get("points", []), MAX_PL_PTS)
		if pts == null or (pts as Array).size() < 2:
			return "A phase line needs 2 to %d points on the map." % MAX_PL_PTS
		if String(pl.get("name", "")).length() > 24:
			return "Phase line names are at most 24 characters."
	if intent == "screen" and (pls as Array).is_empty():
		return "A screen needs a phase line to screen."
	if (objs as Array).is_empty() and (axis as Array).size() < 2 and (pls as Array).is_empty():
		return "Give the plan an objective, an axis of advance or a phase line."
	var tm = p.get("timing", {"mode": "now"})
	if typeof(tm) != TYPE_DICTIONARY or not TIMINGS.has(String(tm.get("mode", ""))):
		return "Timing must be now, on signal or at a time."
	if String(tm.mode) == "at" and (float(tm.get("t", -1.0)) < 0.0 or float(tm.get("t", -1.0)) > 3600.0):
		return "H-hour must be 0 to 3600 seconds from now."
	var fs = p.get("fire_support", [])
	if typeof(fs) != TYPE_ARRAY or (fs as Array).size() > MAX_FIRE:
		return "A plan takes at most %d fire support requests." % MAX_FIRE
	for r in fs:
		if typeof(r) != TYPE_DICTIONARY or not FIRE_KINDS.has(String(r.get("kind", ""))):
			return "Fire support kind must be artillery, air, mortar or smoke."
		var c = to_cell(r.get("cell"))
		if c == null or not w.in_bounds(c):
			return "Fire support targets must be on the map."
	var hold := float(p.get("pl_hold_s", 0.0))
	if hold < 0.0 or hold > 600.0:
		return "Phase line pause must be 0 to 600 seconds."
	var n := 0
	for q in plans_of(w, fid, true):
		if not overlaps(w, q.formation, f):
			n += 1
	if n >= MAX_ACTIVE:
		return "At most %d plans can run at once." % MAX_ACTIVE
	return ""


## True when two formations share a platoon (or are the same formation).
static func overlaps(w: SimWorld, a: Dictionary, b: Dictionary) -> bool:
	if _same_formation(a, b):
		return true
	var pa := platoons(w, a)
	for gid in platoons(w, b):
		if pa.has(gid):
			return true
	return false


static func _same_formation(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("kind", "")) == String(b.get("kind", "")) and int(a.get("id", -1)) == int(b.get("id", -1))


## Leg index a signal authorises up to, or -2 when the signal is unknown. "phase N" = start phase N.
static func signal_allow(plan: Dictionary, sig: String) -> int:
	var li := int(plan.leg)
	match sig:
		"go", "next":
			return 0 if li < 0 else li + 1
		"hold":
			return maxi(li, -1)
		"withdraw":
			return li
	if sig.begins_with("phase "):
		var n := sig.substr(6).strip_edges()
		if n.is_valid_int() and int(n) >= 1 and int(n) <= MAX_PL + MAX_OBJ + 1:
			return int(n) - 1
	return -2


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	var t := String(cmd.get("type", ""))
	if t == "issue_plan":
		var p = cmd.get("plan")
		if typeof(p) != TYPE_DICTIONARY:
			return "A plan is required."
		return validate_plan(w, fid, p)
	if t != "cancel_plan" and t != "plan_signal":
		return "Unknown plan command."
	var pl := get_plan(w, int(cmd.get("plan_id", -1)))
	if pl.is_empty() or int(pl.owner) != fid:
		return "Select one of your plans."
	if not bool(pl.active):
		return "That plan is no longer active."
	if t == "plan_signal" and signal_allow(pl, String(cmd.get("signal", ""))) == -2:
		return "Signal must be go, next, hold, withdraw or phase N."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	match String(cmd.type):
		"issue_plan":
			issue(w, fid, cmd.plan)
		"cancel_plan":
			end_plan(w, get_plan(w, int(cmd.plan_id)), "cancelled", "Cancelled by order.", true)
		"plan_signal":
			var pl := get_plan(w, int(cmd.plan_id))
			var sig := String(cmd.signal)
			w.emit("PlanSignal", {"plan_id": int(pl.id), "owner": fid, "signal": sig})
			if sig == "withdraw":
				withdraw(w, pl)
				return
			if sig == "hold":
				pl.allow = mini(int(pl.allow), maxi(int(pl.leg), -1))
			else:
				pl.allow = maxi(int(pl.allow), signal_allow(pl, sig))
			step_plan(w, pl)


## Creates the plan (validated input) and starts it when its timing allows. Returns the plan id.
static func issue(w: SimWorld, fid: int, p: Dictionary) -> int:
	var st := state(w)
	var f := {"kind": String(p.formation.kind), "id": int(p.formation.id)}
	for q in plans_of(w, fid, true):
		if overlaps(w, q.formation, f):  # an army plan replaces its companies' plans and vice versa
			end_plan(w, q, "cancelled", "Replaced by a new plan.", false)
	var pid := int(st.next_id)
	st.next_id = pid + 1
	var pls := []
	var i := 0
	for pl in p.get("phase_lines", []):
		var nm := String(pl.get("name", ""))
		pls.append({"name": nm if nm != "" else "PL " + PL_NAMES[i % PL_NAMES.size()], "points": _cells(w, pl.points, MAX_PL_PTS)})
		i += 1
	var fs := []
	for r in p.get("fire_support", []):
		fs.append({"cell": to_cell(r.cell), "kind": String(r.kind)})
	var tm: Dictionary = p.get("timing", {"mode": "now"})
	var mode := String(tm.get("mode", "now"))
	var plan := {"id": pid, "owner": fid, "formation": f, "intent": String(p.intent),
		"objectives": _cells(w, p.get("objectives", []), MAX_OBJ), "axis": _cells(w, p.get("axis", []), MAX_AXIS),
		"phase_lines": pls, "timing": {"mode": mode, "t": float(tm.get("t", 0.0))}, "main_effort": bool(p.get("main_effort", false)),
		"fire_support": fs, "halt_at_pl": bool(p.get("halt_at_pl", true)), "pl_hold_s": float(p.get("pl_hold_s", 0.0)),
		"legs": [], "leg": -1, "allow": 0 if mode == "now" else -1, "sent": {}, "sent_tick": {}, "pending": {},
		"reached_tick": -1, "status": "waiting", "line": "", "pl_reached": 0, "obj_held": [],
		"start_units": formation_units(w, f).size(), "losses": 0, "origin": Vector2.ZERO, "active": true,
		"issued": w.tick, "at_tick": w.tick + int(float(tm.get("t", 0.0)) * SimWorld.TICK_RATE)}
	plan.origin = _centroid(w, formation_units(w, f))
	plan.legs = build_legs(plan, plan.origin)
	st.plans[pid] = plan
	_prune_done(st)
	w.emit("PlanIssued", {"plan_id": pid, "owner": fid, "intent": plan.intent, "formation": f})
	step_plan(w, plan)
	return pid


## Keeps the newest KEEP_DONE finished plans per state (UI history), drops older ones.
static func _prune_done(st: Dictionary) -> void:
	var done := []
	for pid in st.plans:
		if not bool(st.plans[pid].active):
			done.append(int(pid))
	done.sort()
	while done.size() > KEEP_DONE:
		st.plans.erase(done.pop_front())
