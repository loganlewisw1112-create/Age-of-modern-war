extends RefCounted
## G7.1 FLOW71 (docs/G71_SCOPE.md A3): fewer steps to battle.
## Commands (registered by ORCH):
##   flow_send {issuer, unit_ids | building_id, to: "front" | Vector2, mode: "attack" (default) | "move"}
##     one click: the units (or the idle ground units round a building / its rally point) go to the front or a point.
##   flow_auto {issuer, key: refuel|rearm|reinforce|retrain|deploy, on: bool, scope: unit|squad|company|global|producer,
##     unit_ids? (unit / squad / company), building_id? (producer), to? ("front" | Vector2, deploy only)}
##   flow_template_save {issuer, name, unit_ids | parts {def: n}}   (a mission package: def counts)
##   flow_template_launch {issuer, template_id, target: Vector2, fill?: bool (queue the missing parts, default true)}
## "Front" (PROVISIONAL rule, cheap + deterministic): Last Protocol = the most threatened compass sector of the front
## ring (LpDefence.scan); otherwise the last-seen enemy (w.memory) nearest the side's HQ, front_back_off tiles short of
## it; otherwise front_frac_no_intel of the way from the HQ to the nearest enemy spawn.
## Auto-deploy: ProductionCompleted from a producer with deploy on -> a multi-unit item goes at once as its squad;
## single units gather for deploy_batch_wait ticks (or deploy_group units), become one squad, then go.
## Auto logistics (bits per unit e.fl71 > squad > company > global default): refuel / rearm send a unit under
## svc_low of its fuel / ammo to the nearest supply point (Supply refills it there), then back to its old task;
## reinforce / retrain register the squad's make-up and queue replacements (Production queue_unit, paid as usual) at
## an own producer; the replacements walk to the squad and join it (retrain = specialists only).
## Player control first: a unit under a fresh player order, on hold or Hold Position is never moved by this system.
## State (saved, hashed): w.sys_state.flow71 (String keys); entity field e.fl71 (explicit per-unit bits).
## Cost: tick() returns at once while nothing is on (st.on false or no state); thinking every think_every ticks,
## units in unit_every / think_every buckets by id.

const Movement = preload("res://sim/systems/movement.gd")
const SquadAI = preload("res://sim/systems/squad_ai.gd")
const Production = preload("res://sim/systems/production.gd")
const LpDefence = preload("res://sim/systems/lp_defence.gd")
const Air = preload("res://sim/systems/air.gd")

const KEY := "flow71"
const BIT := {"refuel": 1, "rearm": 2, "reinforce": 4, "retrain": 8}
const KEYS := ["refuel", "rearm", "reinforce", "retrain", "deploy"]
const SCOPES := ["unit", "squad", "company", "global", "producer"]


static func R() -> Dictionary:
	return Content.rules().get("g71_flow", {})


static func _ri(k: String, d: int) -> int:
	return int(R().get(k, d))


static func _rf(k: String, d: float) -> float:
	return float(R().get(k, d))


static func state(w: SimWorld):
	return w.sys_state.get(KEY)


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"ver": 1, "on": false, "glob": {}, "sq": {}, "co": {}, "uo": {}, "dep": {}, "batch": {},
			"svc": {}, "reg": {}, "tq": [], "tpl": [], "tnext": 1}
	return w.sys_state[KEY]


static func _k(i: int) -> String:
	return str(i)


# ================================================================ queries (UI / tests)
## Effective auto-logistics bits of a unit: explicit unit bits > squad > company > the side's global default.
static func mask_of(w: SimWorld, e: Dictionary) -> int:
	if e.has("fl71"):
		return int(e.fl71)
	var st = state(w)
	if st == null:
		return 0
	var sq := int(e.get("squad", -1))
	if sq >= 0 and st.sq.has(_k(sq)):
		return int(st.sq[_k(sq)])
	var co := int(e.get("company", -1))
	if co >= 0 and st.co.has(_k(co)):
		return int(st.co[_k(co)])
	return int(st.glob.get(_k(int(e.owner)), 0))


static func deploy_on(w: SimWorld, bid: int) -> bool:
	var st = state(w)
	return st != null and st.dep.has(_k(bid))


static func global_mask(w: SimWorld, fid: int) -> int:
	var st = state(w)
	return 0 if st == null else int(st.glob.get(_k(fid), 0))


static func templates(w: SimWorld, fid: int) -> Array:
	var out := []
	var st = state(w)
	if st == null:
		return out
	for t in st.tpl:
		if int(t.owner) == fid:
			out.append(t)
	return out


static func in_service(w: SimWorld, uid: int) -> bool:
	var st = state(w)
	return st != null and st.svc.has(_k(uid))


## Unit left alone by this system (player control first).
static func _hands_off(w: SimWorld, e: Dictionary) -> bool:
	return SquadAI.player_fresh(w, e) or String(e.order.get("type", "")) == "hold" or SquadAI.stance_of(e) == "hold_position"


static func _anchor(w: SimWorld, fid: int) -> Vector2:
	var best = null
	for b in w.buildings_of(fid):
		if bool(Content.building(String(b.def)).get("is_hq", false)):
			if best == null or int(b.id) < int(best.id):
				best = b
	if best != null:
		return best.pos
	var sp = w.factions[fid].get("spawn", Vector2i(w.map.w / 2, w.map.h / 2))
	return Vector2(sp) + Vector2(0.5, 0.5)


static func _enemy(w: SimWorld, fid: int, ofid: int) -> bool:
	if ofid == fid or ofid == SimWorld.NEUTRAL or not w.factions.has(ofid):
		return false
	var t1 = w.factions[fid].get("team", fid)
	var t2 = w.factions[ofid].get("team", ofid)
	return t1 != t2


static func _clampv(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 1.5, float(w.map.w) - 1.5), clampf(p.y, 1.5, float(w.map.h) - 1.5))


## The side's front (see header). Pure function of state; cheap (one pass over the side's intel memory).
static func front_point(w: SimWorld, fid: int) -> Vector2:
	var lp = w.sys_state.get("lp")
	if lp != null and int(lp.get("fid", -1)) == fid and lp.has("base"):
		var sc := LpDefence.scan(w, lp)
		var top := -1
		var topn := 0
		for k in 8:
			if int(sc.sectors[k]) > topn:
				topn = int(sc.sectors[k])
				top = k
		var front := 0
		while front < (lp.base.rings as Array).size() - 1 and bool(lp.base.rings[front].fallen):
			front += 1
		if top < 0:
			top = 0
			var best := INF
			var mid := Vector2(w.map.w * 0.5, w.map.h * 0.5)
			for k in 8:   # quiet walls: the face toward the map centre (lowest sector on a tie)
				var d := LpDefence.sector_point(lp, front, k).distance_to(mid)
				if d < best:
					best = d
					top = k
		return _clampv(w, LpDefence.sector_point(lp, front, top))
	var a := _anchor(w, fid)
	var mem: Dictionary = w.memory.get(fid, {})
	var best_d := INF
	var best_id := -1
	var best_p := Vector2.ZERO
	for eid in mem:
		var m: Dictionary = mem[eid]
		if not _enemy(w, fid, int(m.get("owner", -1))):
			continue
		var p: Vector2 = m.get("pos", Vector2.ZERO)
		var d := a.distance_to(p)
		if d < best_d or (d == best_d and int(eid) < best_id):
			best_d = d
			best_id = int(eid)
			best_p = p
	if best_id >= 0:
		var back := _rf("front_back_off", 6.0)
		if best_d <= back:
			return _clampv(w, best_p)
		return _clampv(w, a + (best_p - a).normalized() * (best_d - back))
	var es := INF
	var ep = null
	var ids: Array = w.factions.keys()
	ids.sort()
	for o in ids:
		if _enemy(w, fid, int(o)) and w.factions[o].alive and w.factions[o].has("spawn"):
			var p := Vector2(w.factions[o].spawn) + Vector2(0.5, 0.5)
			if a.distance_to(p) < es:
				es = a.distance_to(p)
				ep = p
	if ep == null:
		return _clampv(w, Vector2(w.map.w * 0.5, w.map.h * 0.5))
	return _clampv(w, a.lerp(ep, _rf("front_frac_no_intel", 0.4)))


static func _target_of(w: SimWorld, fid: int, to) -> Vector2:
	if typeof(to) == TYPE_VECTOR2:
		return _clampv(w, to)
	if typeof(to) == TYPE_VECTOR2I:
		return _clampv(w, Vector2(to) + Vector2(0.5, 0.5))
	return front_point(w, fid)


## Idle own ground units round a building (its footprint + rally point), ascending id.
static func units_near_building(w: SimWorld, b: Dictionary) -> Array:
	var out := []
	var r := float(b.get("size", 2)) * 0.5 + 6.0
	var bp: Vector2 = b.pos
	var rp: Vector2 = b.get("rally", bp)
	for e in w.units_of(int(b.owner)):
		if Air.is_aircraft(e) or _hands_off(w, e):
			continue
		var p: Vector2 = e.pos
		if p.distance_to(bp) > r and p.distance_to(rp) > 4.0:
			continue
		var ot := String(e.order.get("type", "idle"))
		if ot == "idle" or (ot == "move" and not e.order.has("sq")):
			out.append(int(e.id))
	return out


## Issues the group move / attack-move (formations as a player move). Returns the target.
static func send(w: SimWorld, fid: int, ids: Array, to, mode: String = "attack") -> Vector2:
	var tgt := _target_of(w, fid, to)
	if ids.is_empty():
		return tgt
	var st = state(w)
	if st != null:
		for id in ids:
			st.svc.erase(_k(int(id)))
	Movement.apply_command(w, {"type": "move" if mode == "move" else "attack_move", "issuer": fid, "unit_ids": ids, "target": tgt})
	w.emit("FlowSent", {"owner": fid, "n": ids.size(), "target": tgt, "front": typeof(to) == TYPE_STRING})
	return tgt


# ================================================================ commands
static func _parts_of(w: SimWorld, ids: Array) -> Dictionary:
	var parts := {}
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null and e.kind == "unit":
			parts[String(e.def)] = int(parts.get(String(e.def), 0)) + 1
	return parts


static func _tpl(w: SimWorld, tid: int) -> Dictionary:
	var st = state(w)
	if st != null:
		for t in st.tpl:
			if int(t.id) == tid:
				return t
	return {}


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.issuer)
	match String(cmd.type):
		"flow_send":
			if not cmd.has("unit_ids") and not cmd.has("building_id"):
				return "Select units or a building."
			var to = cmd.get("to", "front")
			if typeof(to) == TYPE_STRING and String(to) != "front":
				return "Unknown destination."
			if typeof(to) == TYPE_VECTOR2 and not w.in_bounds(w.cell_of(to)):
				return "The target is outside the map."
			if not ["attack", "move"].has(String(cmd.get("mode", "attack"))):
				return "Unknown mode."
			if cmd.has("building_id") and not cmd.has("unit_ids") and units_near_building(w, w.entities[int(cmd.building_id)]).is_empty():
				return "No idle units at this building."
			return ""
		"flow_auto":
			var key := String(cmd.get("key", ""))
			var scope := String(cmd.get("scope", "global" if key != "deploy" else "producer"))
			if not KEYS.has(key):
				return "Unknown toggle."
			if not SCOPES.has(scope):
				return "Unknown scope."
			if key == "deploy" or scope == "producer":
				if key != "deploy" or scope != "producer" or not cmd.has("building_id"):
					return "Auto-deploy is set on a producer."
				if (Content.building(String(w.entities[int(cmd.building_id)].def)).get("produces", []) as Array).is_empty():
					return "This building produces nothing."
				return ""
			if scope != "global" and not cmd.has("unit_ids"):
				return "Select units."
			return ""
		"flow_template_save":
			var nm := String(cmd.get("name", "")).strip_edges()
			if nm == "" or nm.length() > _ri("template_name_max", 24):
				return "Give the package a short name."
			var parts: Dictionary = cmd.get("parts", {}) if typeof(cmd.get("parts")) == TYPE_DICTIONARY else _parts_of(w, cmd.get("unit_ids", []))
			if parts.is_empty() or parts.size() > _ri("template_parts_max", 12):
				return "A package needs 1-%d unit types." % _ri("template_parts_max", 12)
			for d in parts:
				if Content.unit(String(d)).is_empty() or int(parts[d]) < 1 or int(parts[d]) > 60:
					return "Unknown unit in the package."
			if templates(w, fid).size() >= _ri("template_max", 12):
				return "Package list full (%d)." % _ri("template_max", 12)
			return ""
		"flow_template_launch":
			var t := _tpl(w, int(cmd.get("template_id", -1)))
			if t.is_empty() or int(t.owner) != fid:
				return "Unknown package."
			var tg = cmd.get("target", "front")
			if typeof(tg) == TYPE_VECTOR2 and not w.in_bounds(w.cell_of(tg)):
				return "The target is outside the map."
			return ""
	return "Unknown flow command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	match String(cmd.type):
		"flow_send":
			var ids: Array = cmd.get("unit_ids", [])
			if ids.is_empty() and cmd.has("building_id"):
				ids = units_near_building(w, w.entities[int(cmd.building_id)])
			send(w, fid, ids, cmd.get("to", "front"), String(cmd.get("mode", "attack")))
		"flow_auto":
			_apply_auto(w, fid, cmd)
		"flow_template_save":
			var st := _st(w)
			var parts: Dictionary = cmd.get("parts", {}) if typeof(cmd.get("parts")) == TYPE_DICTIONARY else _parts_of(w, cmd.get("unit_ids", []))
			var clean := {}
			var keys: Array = parts.keys()
			keys.sort()
			for d in keys:
				clean[String(d)] = int(parts[d])
			var t := {"id": int(st.tnext), "owner": fid, "name": String(cmd.name).strip_edges(), "parts": clean}
			st.tnext = int(st.tnext) + 1
			(st.tpl as Array).append(t)
			w.emit("FlowTemplateSaved", {"owner": fid, "id": int(t.id), "name": t.name})
		"flow_template_launch":
			launch(w, fid, _tpl(w, int(cmd.template_id)), cmd.get("target", "front"), bool(cmd.get("fill", true)))


static func _apply_auto(w: SimWorld, fid: int, cmd: Dictionary) -> void:
	var st := _st(w)
	var key := String(cmd.key)
	var on := bool(cmd.get("on", true))
	if key == "deploy":
		var bk := _k(int(cmd.building_id))
		if on:
			var to = cmd.get("to", "front")
			st.dep[bk] = {"owner": fid, "to": to if typeof(to) == TYPE_VECTOR2 else "front"}
		else:
			st.dep.erase(bk)
			st.batch.erase(bk)
		st.on = true
		w.emit("FlowAuto", {"owner": fid, "key": key, "on": on, "building_id": int(cmd.building_id)})
		return
	var bit := int(BIT[key])
	var scope := String(cmd.get("scope", "global"))
	match scope:
		"global":
			var m := int(st.glob.get(_k(fid), 0))
			st.glob[_k(fid)] = (m | bit) if on else (m & ~bit)
		"unit":
			for id in cmd.unit_ids:
				var e: Dictionary = w.entities[int(id)]
				var m := mask_of(w, e)
				e.fl71 = (m | bit) if on else (m & ~bit)
			st.uo[_k(fid)] = int(st.uo.get(_k(fid), 0)) + (cmd.unit_ids as Array).size()
		"squad", "company":
			var fld := "squad" if scope == "squad" else "company"
			var tab: Dictionary = st.sq if scope == "squad" else st.co
			var seen := {}
			for id in cmd.unit_ids:
				var g := int(w.entities[int(id)].get(fld, -1))
				if g < 0 or seen.has(g):
					continue
				seen[g] = true
				var m := int(tab.get(_k(g), int(st.glob.get(_k(fid), 0))))
				tab[_k(g)] = (m | bit) if on else (m & ~bit)
	st.on = true
	w.emit("FlowAuto", {"owner": fid, "key": key, "on": on, "scope": scope})


# ================================================================ production helpers
## [building_id, item] of the own built producer (shortest queue, then lowest id) whose item spawns exactly `defs`
## (sorted multiset) and that Production accepts right now; [] when none.
static func _item_for(w: SimWorld, fid: int, defs: Array) -> Array:
	var want := defs.duplicate()
	want.sort()
	var best := []
	var best_q := 1 << 30
	for b in w.buildings_of(fid):
		if not bool(b.get("built", false)):
			continue
		for item in Content.building(String(b.def)).get("produces", []):
			var sp: Array = (Content.production(String(item)).get("spawns", []) as Array).duplicate()
			sp.sort()
			if sp != want:
				continue
			var q := (b.get("queue", []) as Array).size()
			if q < best_q and Production.validate_command(w, {"type": "queue_unit", "issuer": fid, "building_id": int(b.id), "item": String(item)}) == "":
				best_q = q
				best = [int(b.id), String(item)]
			break
	return best


static func _queue(w: SimWorld, fid: int, bi: Array) -> bool:
	var c := {"type": "queue_unit", "issuer": fid, "building_id": int(bi[0]), "item": String(bi[1])}
	if Production.validate_command(w, c) != "":
		return false
	Production.apply_command(w, c)
	return true


# ================================================================ mission templates
static func _avail(w: SimWorld, st: Dictionary, e: Dictionary) -> bool:
	return not _hands_off(w, e) and not st.svc.has(_k(int(e.id))) and int(e.get("convoy", -1)) < 0 		and not bool(e.get("wounded", false))


## Takes the template's parts from available own units (nearest the target first), sends them (ground as one
## group, aircraft as another) and, with fill, queues the missing parts; those go to the target when they are made.
static func launch(w: SimWorld, fid: int, t: Dictionary, to, fill: bool = true) -> Dictionary:
	if t.is_empty():
		return {}
	var st := _st(w)
	var tgt := _target_of(w, fid, to)
	var used := {}
	var ground := []
	var air := []
	var missing := 0
	var queued := 0
	var pool := w.units_of(fid)
	var defs: Array = (t.parts as Dictionary).keys()
	defs.sort()
	for d in defs:
		var need := int(t.parts[d])
		var cand := []
		for e in pool:
			if String(e.def) == String(d) and _avail(w, st, e):
				cand.append(e)
		cand.sort_custom(func(a, b) -> bool:
			var da := (a.pos as Vector2).distance_squared_to(tgt)
			var db := (b.pos as Vector2).distance_squared_to(tgt)
			return da < db if da != db else int(a.id) < int(b.id))
		var got := 0
		for e in cand:
			if got >= need:
				break
			got += 1
			(air if Air.is_aircraft(e) else ground).append(int(e.id))
		var miss := need - got
		missing += miss
		if fill and miss > 0:
			var q := 0
			for i in miss:
				var bi := _item_for(w, fid, [String(d)])
				if bi.is_empty() or not _queue(w, fid, bi):
					break
				q += 1
			if q > 0:
				(st.tq as Array).append({"owner": fid, "def": String(d), "n": q, "target": tgt, "t": w.tick})
				st.on = true
			queued += q
	ground.sort()
	air.sort()
	if not ground.is_empty():
		send(w, fid, ground, tgt, "attack")
	if not air.is_empty():
		send(w, fid, air, tgt, "attack")
	var out := {"owner": fid, "id": int(t.id), "name": String(t.name), "taken": ground.size() + air.size(),
		"missing": missing, "queued": queued, "target": tgt}
	w.emit("FlowTemplateLaunched", out)
	return out


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get(KEY)
	if st == null or not bool(st.on):
		return
	if not st.dep.is_empty() or not st.tq.is_empty() or int(st.get("pend", 0)) > 0:
		_scan_events(w, st)
	var every := maxi(1, _ri("think_every", 10))
	if w.tick % every != 0:
		return
	_flush_batches(w, st)
	_service_step(w, st)
	_scan_units(w, st, every)
	_reinforce_step(w, st, every)
	var any_glob := false
	for k in st.glob:
		if int(st.glob[k]) != 0:
			any_glob = true
	var any_uo := false
	for k in st.uo:
		if int(st.uo[k]) > 0:
			any_uo = true
	st.on = any_glob or any_uo or not (st.sq.is_empty() and st.co.is_empty() and st.dep.is_empty() and st.batch.is_empty() 		and st.svc.is_empty() and st.reg.is_empty() and st.tq.is_empty())


static func _keys_sorted(d: Dictionary) -> Array:
	var ks := []
	for k in d:
		ks.append(int(k))
	ks.sort()
	return ks


static func _set_squad(w: SimWorld, e: Dictionary, sq: int) -> void:
	if int(e.get("squad", -1)) != sq:
		e.squad = sq
		SquadAI.touch(w)


## ProductionCompleted this tick: template top-ups go to their target, reinforcements join their squad, the rest
## of an auto-deploy producer's output joins its batch.
static func _scan_events(w: SimWorld, st: Dictionary) -> void:
	for ev in w.events:
		if String(ev.get("type", "")) != "ProductionCompleted":
			continue
		var fid := int(ev.get("owner", -1))
		var rest := []
		for raw in ev.get("unit_ids", []):
			var e = w.entities.get(int(raw))
			if e == null:
				continue
			if _take_tq(w, st, fid, e) or _take_reg(w, st, fid, e):
				continue
			rest.append(int(raw))
		var bk := _k(int(ev.get("building_id", -1)))
		if rest.is_empty() or not st.dep.has(bk):
			continue
		var ground := []
		for id in rest:
			if not Air.is_aircraft(w.entities[id]):
				ground.append(id)
		if ground.is_empty():
			continue
		if ground.size() >= 2:   # a squad item: it is a squad already, it goes now
			send(w, fid, ground, st.dep[bk].to, "attack")
			continue
		if not st.batch.has(bk):
			st.batch[bk] = {"owner": fid, "ids": [], "t": w.tick}
		(st.batch[bk].ids as Array).append_array(ground)


static func _take_tq(w: SimWorld, st: Dictionary, fid: int, e: Dictionary) -> bool:
	for q in st.tq:
		if int(q.owner) == fid and String(q.def) == String(e.def) and int(q.n) > 0:
			q.n = int(q.n) - 1
			send(w, fid, [int(e.id)], q.target, "attack")
			if int(q.n) <= 0:
				(st.tq as Array).erase(q)
			return true
	return false


static func _take_reg(w: SimWorld, st: Dictionary, fid: int, e: Dictionary) -> bool:
	if int(st.get("pend", 0)) <= 0:
		return false
	for sk in _keys_sorted(st.reg):
		var r: Dictionary = st.reg[_k(sk)]
		if int(r.owner) != fid or int((r.pend as Dictionary).get(String(e.def), 0)) <= 0:
			continue
		r.pend[String(e.def)] = int(r.pend[String(e.def)]) - 1
		st.pend = maxi(0, int(st.get("pend", 0)) - 1)
		var mem := SquadAI.squad_members(w, sk)
		_set_squad(w, e, sk)
		if not mem.is_empty():
			var le = w.entities.get(SquadAI.leader_of(w, mem))
			if le != null:
				SquadAI._ai_move(w, e, le.pos, "move", "flow_join")
		w.emit("FlowJoined", {"owner": fid, "unit_id": int(e.id), "squad": sk})
		return true
	return false


static func _flush_batches(w: SimWorld, st: Dictionary) -> void:
	var wait := _ri("deploy_batch_wait", 120)
	var grp := _ri("deploy_group", 4)
	for bi in _keys_sorted(st.batch):
		var b: Dictionary = st.batch[_k(bi)]
		var ids := []
		for id in b.ids:
			var e = w.entities.get(int(id))
			if e != null and not _hands_off(w, e):
				ids.append(int(id))
		if ids.is_empty():
			st.batch.erase(_k(bi))
			continue
		if ids.size() < grp and w.tick - int(b.t) < wait:
			b.ids = ids
			continue
		st.batch.erase(_k(bi))
		var sq := int(w.entities[ids[0]].get("squad", -1))
		for id in ids:
			_set_squad(w, w.entities[id], sq)
		var to = st.dep[_k(bi)].to if st.dep.has(_k(bi)) else "front"
		send(w, int(b.owner), ids, to, "attack")


static func _service_step(w: SimWorld, st: Dictionary) -> void:
	var full := _rf("svc_full", 0.9)
	var tmo := _ri("svc_timeout", 1800)
	for uid in _keys_sorted(st.svc):
		var s: Dictionary = st.svc[_k(uid)]
		var e = w.entities.get(uid)
		if e == null or SquadAI.player_fresh(w, e) or SquadAI.stance_of(e) == "hold_position" or String(e.order.get("type", "")) == "hold":
			st.svc.erase(_k(uid))
			continue
		var d := Content.unit(String(e.def))
		var am := int(d.get("ammo_max", 0))
		var fm := float(d.get("fuel_max", 0))
		var ok: bool = (am <= 0 or not e.has("ammo") or float(e.ammo) >= full * am) and (fm <= 0.0 or not e.has("fuel") or float(e.fuel) >= full * fm)
		var there: bool = (e.pos as Vector2).distance_to(s.at) <= float(s.r)
		if (there and ok) or w.tick - int(s.t0) > tmo:
			st.svc.erase(_k(uid))
			Movement.apply_command(w, {"type": String(s.rt), "issuer": int(e.owner), "unit_ids": [uid], "target": s.ret})
			w.emit("FlowService", {"unit_id": uid, "phase": "back", "owner": int(e.owner)})
		elif not there and String(e.order.get("type", "idle")) == "idle":
			s.re = int(s.re) + 1
			if int(s.re) > 3 or not SquadAI._ai_move(w, e, s.at, "move", "flow_svc"):
				st.svc.erase(_k(uid))


## Nearest own supply point to p: a built HQ / supply_point building or an is_supply unit. [pos, reach] or [].
static func _supply_pt(w: SimWorld, cache: Dictionary, fid: int, p: Vector2, self_id: int) -> Array:
	if not cache.has(fid):
		var pts := []
		var rad := float(Content.rules().get("supply", {}).get("radius", 4))
		for b in w.buildings_of(fid):
			var bd := Content.building(String(b.def))
			if bool(b.get("built", false)) and (bool(bd.get("is_hq", false)) or bool(bd.get("supply_point", false))):
				pts.append([b.pos, maxf(1.5, rad + float(b.get("size", 2)) * 0.5 - 1.0), int(b.id)])
		for u in w.units_of(fid):
			if bool(Content.unit(String(u.def)).get("is_supply", false)):
				pts.append([u.pos, maxf(1.5, rad - 1.0), int(u.id)])
		cache[fid] = pts
	var best := []
	var bd2 := INF
	for q in cache[fid]:
		if int(q[2]) == self_id:
			continue
		var dd := (q[0] as Vector2).distance_squared_to(p)
		if dd < bd2:
			bd2 = dd
			best = [q[0], q[1]]
	return best


static func _scan_units(w: SimWorld, st: Dictionary, every: int) -> void:
	var nb := maxi(1, _ri("unit_every", 30) / every)
	var phase := (w.tick / every) % nb
	var low := _rf("svc_low", 0.25)
	var cache := {}
	var fids: Array = w.factions.keys()
	fids.sort()
	var grp_any: bool = not (st.sq.is_empty() and st.co.is_empty())
	for fid in fids:
		if not grp_any and int(st.glob.get(_k(int(fid)), 0)) == 0 and int(st.uo.get(_k(int(fid)), 0)) <= 0:
			continue
		for e in w.units_of(int(fid)):
			if int(e.id) % nb != phase:
				continue
			var m := mask_of(w, e)
			if m == 0:
				continue
			var sq := int(e.get("squad", -1))
			if (m & 12) != 0 and sq >= 0 and not st.reg.has(_k(sq)):
				_register(w, st, sq, int(fid))
			if (m & 3) != 0 and not st.svc.has(_k(int(e.id))):
				_need_service(w, st, e, m, low, cache)


static func _need_service(w: SimWorld, st: Dictionary, e: Dictionary, m: int, low: float, cache: Dictionary) -> void:
	if Air.is_aircraft(e) or _hands_off(w, e) or int(e.get("convoy", -1)) >= 0 or bool(e.get("wounded", false)):
		return
	var d := Content.unit(String(e.def))
	var am := int(d.get("ammo_max", 0))
	var fm := float(d.get("fuel_max", 0))
	var need_a: bool = (m & 2) != 0 and am > 0 and e.has("ammo") and float(e.ammo) < low * am
	var need_f: bool = (m & 1) != 0 and fm > 0.0 and not bool(d.get("energy", false)) and e.has("fuel") and float(e.fuel) < low * fm
	if not need_a and not need_f:
		return
	if need_a and not need_f and int(e.get("squad", -1)) >= 0:
		for mid in SquadAI.squad_members(w, int(e.squad)):   # an ammo bearer in the squad restocks it in place
			if bool(Content.unit(String(w.entities[mid].def)).get("ammo_bearer", false)):
				return
	var pt := _supply_pt(w, cache, int(e.owner), e.pos, int(e.id))
	if pt.is_empty() or (e.pos as Vector2).distance_to(pt[0]) <= float(pt[1]):
		return
	var ot := String(e.order.get("type", "idle"))
	var t = e.order.get("target")
	var ret: Vector2 = t if typeof(t) == TYPE_VECTOR2 else e.pos
	var rt := "attack_move" if ["attack_move", "attack", "patrol", "guard"].has(ot) else "move"
	if not SquadAI._ai_move(w, e, pt[0], "move", "flow_svc"):
		return
	var need := ("a" if need_a else "") + ("f" if need_f else "")
	st.svc[_k(int(e.id))] = {"owner": int(e.owner), "need": need, "ret": ret, "rt": rt, "at": pt[0], "r": float(pt[1]),
		"t0": w.tick, "re": 0}
	w.emit("FlowService", {"unit_id": int(e.id), "phase": "out", "owner": int(e.owner), "need": need})


static func _register(w: SimWorld, st: Dictionary, sq: int, fid: int) -> void:
	var defs := {}
	for id in SquadAI.squad_members(w, sq):
		var dd := String(w.entities[id].def)
		defs[dd] = int(defs.get(dd, 0)) + 1
	if defs.is_empty():
		return
	st.reg[_k(sq)] = {"owner": fid, "defs": defs, "pend": {}, "qt": -1}


static func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


static func _drop_reg(st: Dictionary, sk: int) -> void:
	var r: Dictionary = st.reg[_k(sk)]
	st.pend = maxi(0, int(st.get("pend", 0)) - _sum(r.pend))
	st.reg.erase(_k(sk))


## Queues replacements for a registered squad below its make-up: single-unit items per missing member (reinforce:
## all; retrain: specialists only = every def but the squad's most common one); with reinforce and no single item,
## the squad's own item once half the squad is gone.
static func _reinforce_step(w: SimWorld, st: Dictionary, every: int) -> void:
	var nb := maxi(1, _ri("reinforce_every", 300) / every)
	var tmo := _ri("svc_timeout", 1800) * 2
	for sk in _keys_sorted(st.reg):
		if (w.tick / every + sk) % nb != 0:
			continue
		var r: Dictionary = st.reg[_k(sk)]
		var mem := SquadAI.squad_members(w, sk)
		if mem.is_empty():
			_drop_reg(st, sk)
			continue
		var m := mask_of(w, w.entities[mem[0]])
		if (m & 12) == 0:
			_drop_reg(st, sk)
			continue
		if int(r.qt) >= 0 and w.tick - int(r.qt) > tmo:   # replacements never came (queue cancelled / lost)
			st.pend = maxi(0, int(st.get("pend", 0)) - _sum(r.pend))
			r.pend = {}
			r.qt = -1
		var cur := {}
		for id in mem:
			var dd := String(w.entities[id].def)
			cur[dd] = int(cur.get(dd, 0)) + 1
		var dk: Array = (r.defs as Dictionary).keys()
		dk.sort()
		var basic := ""
		var bn := -1
		var total := 0
		for dd in dk:
			total += int(r.defs[dd])
			if int(r.defs[dd]) > bn:
				bn = int(r.defs[dd])
				basic = String(dd)
		var lacking := []
		for dd in dk:
			var miss := int(r.defs[dd]) - int(cur.get(dd, 0)) - int((r.pend as Dictionary).get(dd, 0))
			for i in miss:
				lacking.append(String(dd))
		if lacking.is_empty():
			continue
		var fid := int(r.owner)
		var q := 0
		var left := []
		for dd in lacking:
			var spec: bool = String(dd) != basic
			if (m & 4) == 0 and not (spec and (m & 8) != 0):
				continue
			var bi := _item_for(w, fid, [dd])
			if not bi.is_empty() and _queue(w, fid, bi):
				r.pend[dd] = int((r.pend as Dictionary).get(dd, 0)) + 1
				q += 1
			else:
				left.append(dd)
		if not left.is_empty() and (m & 4) != 0 and lacking.size() * 2 >= total:
			var all := []
			for dd in dk:
				for i in int(r.defs[dd]):
					all.append(String(dd))
			var bi2 := _item_for(w, fid, all)
			if not bi2.is_empty() and _queue(w, fid, bi2):
				for dd in left:   # only the missing ones join; the spare members stay a fresh squad of their own
					r.pend[dd] = int((r.pend as Dictionary).get(dd, 0)) + 1
				q += left.size()
		if q > 0:
			r.qt = w.tick
			st.pend = int(st.get("pend", 0)) + q
			w.emit("FlowReinforce", {"owner": fid, "squad": sk, "queued": q})
