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
			if not bool(form.confused):
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
	var intel := {"vis": w.visible_enemies(fid), "mines": T.known_mines(w, fid), "buildings": w.buildings_of(fid),
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


static func formations(w: SimWorld, fid: int, d: Dictionary, cos: Array) -> Array:
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
			var ids: Array = ([int(g.officer)] + (g.members as Array)).filter(func(x): return not _cmd_held(w, int(x)))
			if ids.is_empty():
				continue
			gids.append(int(gid))
			elems.append(ids)
		if elems.size() == 1:
			var all: Array = elems[0]
			var half := (all.size() + 1) / 2
			elems = [all.slice(0, half), all.slice(half)] if all.size() >= 2 else elems
		var cap := int(c.get("captain", -1))
		if cap >= 0 and _cmd_held(w, cap):
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


static func probe(d: Dictionary) -> String:
	var parts := []
	var keys: Array = (d.forms as Dictionary).keys()
	keys.sort()
	for k in keys:
		var fs: Dictionary = d.forms[k]
		parts.append("%s:%s/%s/%s" % [k, String(fs.role), String(fs.task), String(fs.phase)])
	return "forms=[%s] launched=%s missions=%d decisions=%d tags=%s" % [" ".join(parts), str(bool(d.get("launched", false))),
		(d.missions as Dictionary).size(), int(d.decisions), str(d.tags)]
