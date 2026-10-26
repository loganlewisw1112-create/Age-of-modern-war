extends RefCounted
## Doctrine (AI doctrine engine entry) (owner: AI7-DOC). CONTRACTS_G6 section 16 (D40), section 3.6 tags.
## Every AI side (enemy included) fights its formations with one doctrine, in three layers:
##   strategic   (doc_strategic.gd)   front + key terrain, main effort vs fixing force, reserve, timing,
##                                     reserve commitment, retreat and regroup
##   operational (doc_operational.gd) per company: axis, phase lines, formation; advance by bounding
##                                     overwatch -> recon -> suppress (+ artillery prep) -> assault + flank
##                                     -> consolidate; hold in depth; breaching known minefields
##   tactical    (doc_tactical.gd)    per platoon: height and cover seeking, flank geometry, garrisons,
##                                     mine awareness
## plus special operations (doc_specops.gd -> ops_missions.gd: raid, sabotage, recon, officer_hunt, exfil).
## Formations = the side's companies (ARMY6): one element per platoon (a single platoon is split into two
## sections so it can still fire and manoeuvre). The doctrine takes its formation units out of ctx.army /
## ctx.officers / ctx.recon before ai_army runs, so the G5 army logic never orders them.
## Every decision emits AiDecision {fid, tag, unit_ids, reason} (doc_util.decide).
## State: w.ai_state[fid].doctrine (CONTRACTS_G6 section 6), created only once the side fields a company:
## a side without companies is untouched (G5 results and hashes unchanged).

const D = preload("res://sim/ai/doctrine/doc_util.gd")
const T = preload("res://sim/ai/doctrine/doc_tactical.gd")
const Op = preload("res://sim/ai/doctrine/doc_operational.gd")
const S = preload("res://sim/ai/doctrine/doc_strategic.gd")
const Spec = preload("res://sim/ai/doctrine/doc_specops.gd")
const Companies = preload("res://sim/systems/companies.gd")
const U = preload("res://sim/ai/ai_util.gd")
const Ops = preload("res://sim/systems/ops.gd")
const Fog = preload("res://sim/systems/fog.gd")


## Strategic/operational/tactical layers for an AI side (called by ai_controller in the mil turn).
static func think(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var cos := Companies.companies_of(w, fid)
	if cos.is_empty() and not st.has("doctrine"):
		return
	var d := D.dstate(st)
	var forms := formations(w, fid, d, cos)
	_sync(w, fid, d, forms)
	if forms.is_empty() and (d.missions as Dictionary).is_empty():
		return
	var intel := _intel(w, fid, st, ctx, d, forms)
	_release(ctx, intel.in_form)
	if not forms.is_empty():
		S.plan(w, fid, st, d, forms, intel)
		intel.safe = d.front.get("hold", intel.base)
		for form in forms:
			if not bool(form.confused) and not ordered(w, fid, String(form.key)):
				Op.step(w, fid, st, d.forms[String(form.key)], form, intel, null)
	Spec.manage(w, fid, st, d, forms, intel)
	d.probe = probe(d)


## Doctrine plan for one formation (used by AI Commanders, AI7-CMD). formation = {unit_ids: [ids],
## task: "attack" | "hold" | "retreat", objective: Vector2, rally: Vector2, doc: {} (the caller keeps the
## returned doc and passes it back next time)}. Pure: nothing is submitted or emitted. Returns
## {phase, task, objective, phase_lines, orders: [{unit_ids, type, target, ...}], tags: [{tag, unit_ids,
## reason}], doc}. The caller submits the orders it wants (skip one equal to the last it sent) and emits
## the tags with Doctrine.emit. {} when no unit of the formation can move.
static func plan_for(w: SimWorld, fid: int, formation: Dictionary) -> Dictionary:
	var ids: Array = formation.get("unit_ids", [])
	var us := D.movers(w, fid, ids)
	if us.is_empty():
		return {}
	var cen := D.centroid(us)
	var fs: Dictionary = formation.get("doc", {})
	if fs.is_empty():
		fs = Op.new_fs(String(formation.get("key", "cmd")), -1, cen)
	var task := String(formation.get("task", fs.task))
	var obj = formation.get("objective", null)
	if typeof(obj) == TYPE_VECTOR2 and (obj as Vector2).distance_to(fs.obj) > 0.5:
		fs.obj = obj
		fs.phase = ""
	if task != String(fs.task):
		fs.task = task
		fs.phase = ""
	if typeof(formation.get("rally", null)) == TYPE_VECTOR2:
		fs.rally = formation.rally
	var base := U.base_pos(w, fid)
	var dir: Vector2 = ((fs.obj as Vector2) - cen).normalized() if (fs.obj as Vector2).distance_to(cen) > 1.0 else U.front_dir(w, fid)
	var intel := {"vis": Fog.visible_enemies_ro(w, fid), "mines": T.known_mines(w, fid), "buildings": w.buildings_of(fid),
		"arty": [], "enemy_dir": dir, "base": base, "units": [], "in_form": {}, "safe": base}
	var out := {"orders": [], "tags": []}
	Op.step(w, fid, {}, fs, {"key": fs.key, "elems": split(w, fid, ids), "recon": [], "gids": []}, intel, out)
	return {"phase": String(fs.phase), "task": String(fs.task), "objective": fs.obj, "phase_lines": fs.lines,
		"orders": out.orders, "tags": out.tags, "doc": fs}


## AiDecision for a decision taken outside an AI side's think (AI Commanders emitting plan_for tags).
static func emit(w: SimWorld, fid: int, tag: String, ids: Array, reason: String) -> void:
	var idl := ids.duplicate()
	idl.sort()
	w.emit("AiDecision", {"fid": fid, "tag": tag, "unit_ids": idl, "reason": reason})


## Elements of a loose unit set: by platoon when the units carry one, else 2-3 sections by id.
static func split(w: SimWorld, fid: int, ids: Array) -> Array:
	var by := {}
	var order := []
	var loose := []
	for id in ids:
		var e = D.unit(w, fid, int(id))
		if e == null:
			continue
		var p := int(e.get("platoon", -1))
		if p < 0:
			loose.append(int(id))
			continue
		if not by.has(p):
			by[p] = []
			order.append(p)
		by[p].append(int(id))
	order.sort()
	var out := []
	for p in order:
		out.append(by[p])
	if out.size() >= 2:
		if not loose.is_empty():
			out[0].append_array(loose)
		return out
	var all: Array = (out[0] if not out.is_empty() else []) + loose
	all.sort()
	var n := 3 if all.size() >= 9 else (2 if all.size() >= 2 else 1)
	var secs := []
	for i in n:
		secs.append([])
	for i in all.size():
		secs[i * n / all.size()].append(all[i])
	return secs


## The side's companies as formations: {key, cid, name, gids, elems, units, alive, power, recon, confused}.
## G6 (AI7-CMD CR aicmd_skip_commanded_units, applied by ORCH): units AI7-CMD drives (e.ai_cmd = ally | wave)
## are not ordered by this side's doctrine. The field never exists without ally requests or waves.
static func _cmd_held(w: SimWorld, id: int) -> bool:
	var e = w.entities.get(id)  # AI-FAIR: own formation members only (ids from this side's ops groups)
	return e != null and e.has("ai_cmd")


static func formations(w: SimWorld, fid: int, d: Dictionary, cos: Array, skip_cmd: bool = true) -> Array:
	var groups: Dictionary = w.sys_state.get("ops", {}).get("groups", {})
	var det: Dictionary = d.detached
	var out := []
	for c in cos:
		var gids := []
		var elems := []
		for gid in c.get("platoons", []):
			var g: Dictionary = groups.get(int(gid), {})
			if g.is_empty() or det.has("g%d" % int(gid)):
				continue
			var ids: Array = ([int(g.officer)] + (g.members as Array)).filter(func(x): return not skip_cmd or not _cmd_held(w, int(x)))
			if ids.is_empty():
				continue
			gids.append(int(gid))
			elems.append(ids)
		if elems.size() == 1:
			var all: Array = elems[0]
			var half := (all.size() + 1) / 2
			elems = [all.slice(0, half), all.slice(half)] if all.size() >= 2 else elems
		var cap := int(c.get("captain", -1))
		if cap >= 0 and skip_cmd and _cmd_held(w, cap):
			cap = -1
		if elems.is_empty():
			if D.unit(w, fid, cap) == null:
				continue
			elems = [[cap]]
		elif D.unit(w, fid, cap) != null:
			elems[0] = [cap] + elems[0]
		var units := []
		for el in elems:
			units.append_array(el)
		var us := D.movers(w, fid, units)
		if us.is_empty():
			continue
		var recon := []
		if us.size() >= 6:
			var fast = null
			for e in us:
				if String(e.get("rank_role", "")) == "" and (fast == null or float(Content.unit(String(e.def)).get("speed", 0.0)) > float(Content.unit(String(fast.def)).get("speed", 0.0))):
					fast = e
			if fast != null:
				recon.append(int(fast.id))
		out.append({"key": "c%d" % int(c.id), "cid": int(c.id), "name": String(c.get("name", "Company %d" % int(c.id))),
			"gids": gids, "elems": elems, "units": units, "alive": us.size(), "power": D.power(us), "recon": recon,
			"confused": int(c.get("confused_until", 0)) > w.tick, "strength": 1.0})
	return out


static func _sync(w: SimWorld, fid: int, d: Dictionary, forms: Array) -> void:
	var fsd: Dictionary = d.forms
	var live := {}
	for form in forms:
		var k := String(form.key)
		live[k] = true
		if not fsd.has(k):
			fsd[k] = Op.new_fs(k, int(form.cid), D.centroid(D.movers(w, fid, form.units)))
		var fs: Dictionary = fsd[k]
		fs.start = maxi(int(fs.start), int(form.alive))
		form.strength = float(form.alive) / float(maxi(int(fs.start), 1))
	var keys := fsd.keys()
	keys.sort()
	for k in keys:
		if not live.has(k):
			fsd.erase(k)


static func _intel(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, d: Dictionary, forms: Array) -> Dictionary:
	var in_form := {}
	for form in forms:
		for id in form.units:
			in_form[int(id)] = true
	var base := U.base_pos(w, fid)
	var tgt: Vector2 = d.front.get("target", U.enemy_spawn(w, fid))
	var arty := []
	for e in ctx.get("arty", []):
		if not in_form.has(int(e.id)):
			arty.append(e)
	return {"vis": D.visible(w, fid, ctx), "mines": T.known_mines(w, fid), "base": base, "safe": base,
		"buildings": ctx.buildings if ctx.has("buildings") else w.buildings_of(fid),
		"units": ctx.units if ctx.has("units") else w.units_of(fid), "in_form": in_form, "arty": arty,
		"enemy_dir": (tgt - base).normalized() if tgt.distance_to(base) > 1.0 else U.front_dir(w, fid)}


## Formation units leave the G5 army pools (ai_army / ai_tactics / recon never order them).
static func _release(ctx: Dictionary, in_form: Dictionary) -> void:
	if in_form.is_empty():
		return
	for key in ["army", "officers", "recon"]:
		if ctx.has(key) and typeof(ctx[key]) == TYPE_ARRAY:
			ctx[key] = (ctx[key] as Array).filter(func(e) -> bool: return not in_form.has(int(e.id)))
	if ctx.has("busy") and typeof(ctx.busy) == TYPE_DICTIONARY:
		for id in in_form:
			ctx.busy[id] = true


# ================================================================ G6.1 OFF61: order API (GEN61 / CHAIN61 / PLAN61)
## Orders live in w.sys_state.ops.orders61 {"<fid>:<node key>": rec} (saved + hashed; created by the
## first order only, so a match that never orders a formation is unchanged). rec = {fid, key, node,
## order, fs (formation state as in doc_operational), t0, h, st (bookkeeping for a side without an AI
## controller)}. Ordered formations are driven by drive_orders (Ops.tick, every drill_every ticks,
## staggered), whatever side they belong to; Doctrine.think leaves them alone.
const ORDER_TYPES := {"take": "attack", "attack": "attack", "breach": "attack", "raid": "attack", "strike": "attack",
	"hold": "hold", "defend": "hold", "screen": "hold", "withdraw": "retreat", "retreat": "retreat"}


static func _orders(w: SimWorld, make: bool) -> Dictionary:
	if not w.sys_state.has("ops"):
		if not make:
			return {}
		w.sys_state["ops"] = {"groups": {}, "next_gid": 1}
	var ost: Dictionary = w.sys_state.ops
	if not ost.has("orders61"):
		if not make:
			return {}
		ost["orders61"] = {}
	return ost.orders61


static func _v2(v):
	match typeof(v):
		TYPE_VECTOR2:
			return v
		TYPE_VECTOR2I:
			return Vector2(v) + Vector2(0.5, 0.5)
		TYPE_DICTIONARY:
			if (v as Dictionary).has("x") and (v as Dictionary).has("y"):
				return Vector2(float(v.x), float(v.y))
			if (v as Dictionary).has("pos"):
				return _v2(v.pos)
		TYPE_ARRAY:
			if (v as Array).size() >= 2:
				return Vector2(float(v[0]), float(v[1]))
	return null


## Node key of a command node: int = company id, "c<cid>" / "g<gid>" strings, or a CommandNet node dict
## ({cid | company | company_id}, {gid | platoon}, {officer} or {unit_ids, key}). "" when unknown.
static func node_key(w: SimWorld, fid: int, node) -> String:
	match typeof(node):
		TYPE_INT, TYPE_FLOAT:
			return "c%d" % int(node)
		TYPE_STRING, TYPE_STRING_NAME:
			var s := String(node)
			if (s.begins_with("c:") or s.begins_with("p:")) and s.substr(2).is_valid_int():
				return ("c%d" if s.begins_with("c:") else "g%d") % int(s.substr(2))  # CommandNet node keys
			if s.begins_with("c") or s.begins_with("g") or s.begins_with("u"):
				return s
			if s.is_valid_int():
				return "c%d" % int(s)
		TYPE_DICTIONARY:
			var n: Dictionary = node
			for k in ["cid", "company", "company_id"]:
				if n.has(k) and int(n[k]) >= 0:
					return "c%d" % int(n[k])
			for k in ["gid", "platoon"]:
				if n.has(k) and int(n[k]) >= 0:
					return "g%d" % int(n[k])
			if n.has("officer"):
				var oid := int(n.officer)
				var g := Ops.group_led_by(w, oid)
				if not g.is_empty():
					return "g%d" % int(g.id)
				var e = D.unit(w, fid, oid)
				if e != null and e.has("company"):
					return "c%d" % int(e.company)
			if n.has("key") and n.has("unit_ids"):
				return "u:" + String(n.key)
			if n.has("unit_ids") and not (n.unit_ids as Array).is_empty():
				var ids: Array = (n.unit_ids as Array).duplicate()
				ids.sort()
				return "u%d" % int(ids[0])
	return ""


## The formation a node key stands for now: {key, cid, gids, elems, units, recon} or {} (gone).
static func node_form(w: SimWorld, fid: int, key: String, rec: Dictionary = {}) -> Dictionary:
	if key.begins_with("c"):
		var cid := int(key.substr(1))
		for c in Companies.companies_of(w, fid):
			if int(c.id) == cid:
				var fs := formations(w, fid, {"detached": {}}, [c], false)
				return fs[0] if not fs.is_empty() else {}
		return {}
	var ids := []
	if key.begins_with("g"):
		var g: Dictionary = w.sys_state.get("ops", {}).get("groups", {}).get(int(key.substr(1)), {})
		if g.is_empty() or int(g.owner) != fid:
			return {}
		ids = [int(g.officer)] + (g.members as Array)
	else:
		ids = rec.get("node", {}).get("unit_ids", []) if typeof(rec.get("node", null)) == TYPE_DICTIONARY else []
	ids = ids.filter(func(x) -> bool: return D.unit(w, fid, int(x)) != null)
	if ids.is_empty():
		return {}
	var elems := split(w, fid, ids)
	if elems.size() == 1 and (elems[0] as Array).size() >= 2:
		var all: Array = elems[0]
		var half := (all.size() + 1) / 2
		elems = [all.slice(0, half), all.slice(half)]
	return {"key": key, "cid": -1, "gids": [], "elems": elems, "units": ids, "recon": [], "alive": ids.size()}


## Execute a chain-of-command order on a node (company / platoon / unit set) of side fid. order = {type:
## take | hold | raid | screen | breach | withdraw (attack, defend, strike, retreat accepted), target,
## phase_lines: [Vector2], deadline: tick, main_effort: bool, rally}. Returns {ok, reason, key, drill}.
## A new order replaces the node's previous one; {type: "cancel"} releases the node.
static func execute_order(w: SimWorld, fid: int, node, order: Dictionary) -> Dictionary:
	var key := node_key(w, fid, node)
	if key == "":
		return {"ok": false, "reason": "Unknown command node.", "key": "", "drill": ""}
	var rk := "%d:%s" % [fid, key]
	var typ := String(order.get("type", ""))
	if typ == "cancel":
		_orders(w, true).erase(rk)
		return {"ok": true, "reason": "", "key": rk, "drill": ""}
	if not ORDER_TYPES.has(typ):
		return {"ok": false, "reason": "Unknown order type '%s'." % typ, "key": rk, "drill": ""}
	var tgt = _v2(order.get("target", null))
	var rec := {"fid": fid, "key": key, "node": node if typeof(node) == TYPE_DICTIONARY else {}, "order": {}, "fs": {},
		"t0": w.tick, "h": absi(hash(rk)) % 997, "st": {}}
	var form := node_form(w, fid, key, rec)
	if form.is_empty():
		return {"ok": false, "reason": "That command node has no units left.", "key": rk, "drill": ""}
	var cen := D.centroid(D.movers(w, fid, form.units), D.centroid(_units(w, fid, form.units)))
	if tgt == null:
		tgt = cen
	tgt = T.clamp_map(w, tgt)
	var ords := _orders(w, true)
	var old: Dictionary = ords.get(rk, {})
	var fs: Dictionary = old.get("fs", {})
	if fs.is_empty():
		fs = Op.new_fs(key, int(form.get("cid", -1)), cen)
	fs.task = String(ORDER_TYPES[typ])
	fs.otype = typ
	fs.obj = tgt
	fs.phase = ""
	fs.hp = []
	fs.hp_for = ""
	fs.done = false
	fs.drill = ""
	fs.line61 = ""
	fs.main = bool(order.get("main_effort", false))
	var rl = _v2(order.get("rally", null))
	fs.rally = rl if rl != null else (tgt if typ in ["withdraw", "retreat"] else cen)
	var pl := []
	for p in order.get("phase_lines", []):
		var v = _v2(p)
		if v != null:
			pl.append(T.clamp_map(w, v))
	fs.olines = pl
	rec.fs = fs
	rec.order = {"type": typ, "target": tgt, "deadline": int(order.get("deadline", -1)), "main_effort": fs.main,
		"phase_lines": pl}
	if not old.is_empty():
		rec.st = old.get("st", {})
	ords[rk] = rec
	return {"ok": true, "reason": "", "key": rk, "drill": String(fs.task)}


static func _units(w: SimWorld, fid: int, ids: Array) -> Array:
	var out := []
	for id in ids:
		var e = D.unit(w, fid, int(id))
		if e != null:
			out.append(e)
	return out


## Current drill of a node for the UI: {key, order, task, drill, phase, line, objective, strength,
## leaderless} ({} when the node has no order and no AI formation state).
static func drill_state(w: SimWorld, fid: int, node) -> Dictionary:
	var key := node_key(w, fid, node)
	if key == "":
		return {}
	var rec: Dictionary = _orders(w, false).get("%d:%s" % [fid, key], {})
	var fs: Dictionary = rec.get("fs", {})
	if fs.is_empty():
		var st: Dictionary = w.ai_state.get(fid, {}) if typeof(w.ai_state) == TYPE_DICTIONARY else {}
		fs = st.get("doctrine", {}).get("forms", {}).get(key, {})
	if fs.is_empty():
		return {}
	return {"key": key, "order": String(rec.get("order", {}).get("type", "")), "task": String(fs.get("task", "")),
		"drill": String(fs.get("drill", "")), "phase": String(fs.get("phase", "")), "line": String(fs.get("line61", "")),
		"objective": fs.get("obj", Vector2.ZERO), "strength": float(fs.get("str61", 1.0)), "leaderless": int(fs.get("ll61", 0))}


## True when side fid's formation key is driven by an order (Doctrine.think leaves it to drive_orders).
static func ordered(w: SimWorld, fid: int, key: String) -> bool:
	return _orders(w, false).has("%d:%s" % [fid, key])


## Drives every ordered formation (Ops.tick calls it each tick; each order thinks every drill_every
## ticks, staggered by its key hash). Sorted keys: deterministic.
static func drive_orders(w: SimWorld) -> void:
	consume_net(w)
	var ords := _orders(w, false)
	if ords.is_empty():
		return
	var every := maxi(D.ticks("drill_every"), 1)
	var keys := ords.keys()
	keys.sort()
	for rk in keys:
		var rec: Dictionary = ords[rk]
		if (w.tick + int(rec.h)) % every != 0:
			continue
		var fid := int(rec.fid)
		var form := node_form(w, fid, String(rec.key), rec)
		if form.is_empty():
			ords.erase(rk)
			continue
		var st: Dictionary = rec.st
		if typeof(w.ai_state) == TYPE_DICTIONARY and w.ai_state.has(fid) and (w.ai_state[fid] as Dictionary).has("pending"):
			st = w.ai_state[fid]
		var fs: Dictionary = rec.fs
		var cen := D.centroid(D.movers(w, fid, form.units), fs.obj)
		var obj: Vector2 = fs.obj
		var base := U.base_pos(w, fid)
		var intel := {"vis": Fog.visible_enemies_ro(w, fid), "mines": T.known_mines(w, fid), "buildings": w.buildings_of(fid),
			"arty": [], "enemy_dir": (obj - cen).normalized() if obj.distance_to(cen) > 1.0 else U.front_dir(w, fid),
			"base": base, "units": [], "in_form": {}, "safe": base}
		Op.step(w, fid, st, fs, form, intel, null)


## OFF61-2: company orders the chain of command (CHAIN61 CommandNet) delivered to a captain become battle
## drills here: the captain's inbox is taken (CommandNet.take_orders, so the net's default executor does not
## act a second time) when every waiting order in it is a drill order (ORDER_TYPES / cancel) for a company
## node ("c:<cid>") and not a PLAN61 plan order; mixed inboxes are left to their owners. Every drill_every
## ticks; nothing to do (and no state touched) while no inbox holds anything.
static func consume_net(w: SimWorld) -> void:
	var box_all: Dictionary = w.sys_state.get("command_net", {}).get("inbox", {})
	if box_all.is_empty() or w.tick % maxi(D.ticks("drill_every"), 1) != 0:
		return
	var net = D._sys("command_net")
	if net == null or not D._has(net, "take_orders"):
		return
	var leaders := box_all.keys()
	leaders.sort()
	for uid in leaders:
		var box: Array = box_all.get(uid, [])
		if box.is_empty():
			continue
		var ok := true
		for rec in box:
			var nd := String(rec.get("node", ""))
			var typ := String(rec.get("type", ""))
			if not nd.begins_with("c:") or String(rec.get("source", "")) == "plan" or not (ORDER_TYPES.has(typ) or typ == "cancel"):
				ok = false
				break
		if not ok:
			continue
		for rec in net.take_orders(w, int(uid)):
			var r := execute_order(w, int(rec.fid), String(rec.node), rec)
			w.emit("OrderExecuted", {"fid": int(rec.fid), "node": String(rec.node), "type": String(rec.type), "by": "doctrine",
				"ok": bool(r.ok), "drill": String(r.get("drill", ""))})


static func probe(d: Dictionary) -> String:
	var parts := []
	var keys: Array = (d.forms as Dictionary).keys()
	keys.sort()
	for k in keys:
		var fs: Dictionary = d.forms[k]
		parts.append("%s:%s/%s/%s" % [k, String(fs.role), String(fs.task), String(fs.phase)])
	return "forms=[%s] launched=%s missions=%d decisions=%d tags=%s" % [" ".join(parts), str(bool(d.get("launched", false))),
		(d.missions as Dictionary).size(), int(d.decisions), str(d.tags)]
