extends RefCounted
## Doctrine special operations (owner: AI7-DOC). CONTRACTS_G6 section 16: picks raid / sabotage / recon /
## officer_hunt / exfil for one platoon and launches it with set_mission (ops_missions.gd runs it); the
## platoon is detached from its company manoeuvre until the mission ends. One special op at a time.
## Priority: exfil (pilots and cut-off squads under threat) > officer hunt (a visible enemy leader) >
## raid (visible gatherers / trucks) > sabotage (a remembered power / supply / HQ building) > recon.
## Intel is fair: own units, ctx.visible and fog memory. Outcome tags: exfil_done (on success).

const D = preload("res://sim/ai/doctrine/doc_util.gd")
const T = preload("res://sim/ai/doctrine/doc_tactical.gd")
const U = preload("res://sim/ai/ai_util.gd")

const LEADERS := ["captain", "lieutenant", "commander"]


static func manage(w: SimWorld, fid: int, st: Dictionary, d: Dictionary, forms: Array, intel: Dictionary) -> void:
	_track(w, fid, st, d)
	if w.tick < D.ticks("mission_first_tick") or w.tick < int(d.next_mission) or not (d.missions as Dictionary).is_empty():
		return
	var pick := pick_mission(w, fid, d, forms, intel)
	if pick.is_empty():
		d.next_mission = w.tick + D.ticks("mission_retry")  # nothing worth a platoon yet: look again soon
		return
	d.next_mission = w.tick + D.ticks("mission_every")
	var t: Vector2 = pick.target
	var cmd := {"type": "set_mission", "officer_id": int(pick.officer), "mission": String(pick.mission), "target": t,
		"radius": float(pick.get("radius", 5.0)), "risk": "high", "safe": intel.safe}
	cmd.merge(pick.get("extra", {}), true)
	if not U.submit(w, fid, st, cmd, "doc:mission"):
		return
	var k := "g%d" % int(pick.gid)
	d.missions[k] = {"gid": int(pick.gid), "type": String(pick.mission), "tick": w.tick}
	d.detached[k] = true
	var tag := String(pick.mission)
	if ["raid", "sabotage", "officer_hunt"].has(tag):
		D.decide(w, fid, st, tag, pick.units, String(pick.reason))
	else:
		U.log_line(st, w, "doctrine: %s" % String(pick.reason))


## Ends the bookkeeping of finished missions (group idle again or gone); a successful exfil is tagged.
static func _track(w: SimWorld, fid: int, st: Dictionary, d: Dictionary) -> void:
	var groups: Dictionary = w.sys_state.get("ops", {}).get("groups", {})
	var ms: Dictionary = d.missions
	var keys := ms.keys()
	keys.sort()
	for k in keys:
		var rec: Dictionary = ms[k]
		var g: Dictionary = groups.get(int(rec.gid), {})
		if not g.is_empty() and int(g.owner) == fid and not (g.mission as Dictionary).is_empty():
			continue
		if w.tick - int(rec.tick) < 20 and not g.is_empty():
			continue  # the set_mission command applies next tick
		var last: Dictionary = g.get("last_doc", {}) if not g.is_empty() else {}
		if String(rec.type) == "exfil" and String(last.get("result", "")) == "success" and int(last.get("tick", -1)) >= int(rec.tick):
			D.decide(w, fid, st, "exfil_done", D.ids_of(D.movers(w, fid, (g.members as Array) + [int(g.officer)])),
				"Exfil complete: %d units extracted to safety." % int(last.get("extracted", 0)))
		elif not last.is_empty():
			U.log_line(st, w, "doctrine: %s ended (%s)" % [String(rec.type), String(last.get("result", "?"))])
		ms.erase(k)
		(d.detached as Dictionary).erase(k)


## {gid, officer, mission, target, radius, extra, units, reason} or {} (no platoon free or nothing to do).
static func pick_mission(w: SimWorld, fid: int, d: Dictionary, forms: Array, intel: Dictionary) -> Dictionary:
	var plt := _platoon(w, fid, d, forms)
	if plt.is_empty():
		return {}
	var at: Vector2 = plt.pos
	var out := {"gid": int(plt.gid), "officer": int(plt.officer), "units": plt.units}
	# exfil: own pilots and cut-off units with enemies close and no friends near
	var ex := []
	var inform: Dictionary = intel.in_form
	for e in intel.units:
		if inform.has(int(e.id)) or ex.size() >= 6:
			continue
		var p: Vector2 = e.pos
		var pilot: bool = e.has("pilot_of")
		if p.distance_to(intel.base) < 25.0 and not pilot:
			continue
		if D.near(intel.vis, p, D.num("contact_range")).is_empty() and not pilot:
			continue
		var friends := 0
		for f in D.near(intel.units, p, 6.0):
			if int(f.id) != int(e.id):
				friends += 1
		if friends == 0 or pilot:
			ex.append(e)
	if not ex.is_empty():
		var c := D.centroid(ex)
		out.merge({"mission": "exfil", "target": c, "extra": {"extract": D.ids_of(ex)},
			"reason": "Exfil: extracting %d units from (%d, %d)." % [ex.size(), int(c.x), int(c.y)]})
		return out
	var best = null
	var bd := D.num("officer_hunt_range")
	for e in intel.vis:
		if e.kind == "unit" and (LEADERS.has(String(e.get("rank_role", ""))) or U.uflag(String(e.def), "is_officer")):
			var dd := (e.pos as Vector2).distance_to(at)
			if dd < bd:
				bd = dd
				best = e
	if best != null:
		out.merge({"mission": "officer_hunt", "target": best.pos, "extra": {"target_id": int(best.id)},
			"reason": "Officer hunt: enemy %s (%s) at (%d, %d)." % [String(best.get("rank_role", "officer")), String(best.def), int(best.pos.x), int(best.pos.y)]})
		return out
	var prey := []
	for e in intel.vis:
		if e.kind == "unit" and (U.uflag(String(e.def), "can_gather") or U.uflag(String(e.def), "is_supply")):
			prey.append(e)
	if not prey.is_empty():
		var c2 := D.centroid(prey)
		out.merge({"mission": "raid", "target": c2, "reason": "Raid on %d enemy gatherers / trucks at (%d, %d)." % [prey.size(), int(c2.x), int(c2.y)]})
		return out
	var tgt := {}
	var td := INF
	for b in D.known_buildings(w, fid):
		var def := String(b.def)
		if U.is_energy(def) or U.bflag(def, "supply_point") or U.is_hq_def(def) or U.bflag(def, "radar"):
			var dd := (b.pos as Vector2).distance_to(at)
			if dd < td:
				td = dd
				tgt = b
	if not tgt.is_empty():
		out.merge({"mission": "sabotage", "target": tgt.pos, "extra": {"target_id": int(tgt.id)},
			"reason": "Sabotage: %s at (%d, %d)." % [String(tgt.def).replace("_", " "), int(tgt.pos.x), int(tgt.pos.y)]})
		return out
	if (intel.vis as Array).is_empty() and D.known_buildings(w, fid).is_empty():
		var rp := T.clamp_map(w, at.lerp(U.enemy_spawn(w, fid), 0.5))
		out.merge({"mission": "recon", "target": rp, "reason": "Recon toward (%d, %d): no enemy located." % [int(rp.x), int(rp.y)]})
		return out
	return {}


## A platoon free for special operations: the last platoon of a reserve company first, then of any
## company holding the line; never a company's only platoon, never one in an attack. {gid, officer, pos, units}.
static func _platoon(w: SimWorld, fid: int, d: Dictionary, forms: Array) -> Dictionary:
	for want in ["reserve", "fixing", "main"]:
		for form in forms:
			var fs: Dictionary = d.forms.get(String(form.key), {})
			if fs.is_empty() or String(fs.role) != want or String(fs.task) == "attack" or String(fs.task) == "retreat":
				continue
			var gids: Array = form.gids
			if gids.size() < 2:
				continue
			var gid := int(gids[gids.size() - 1])
			var g: Dictionary = w.sys_state.get("ops", {}).get("groups", {}).get(gid, {})
			if g.is_empty() or int(g.owner) != fid:
				continue
			var us := D.movers(w, fid, (g.members as Array) + [int(g.officer)])
			if us.size() < 2 or D.unit(w, fid, int(g.officer)) == null:
				continue
			return {"gid": gid, "officer": int(g.officer), "pos": D.centroid(us), "units": D.ids_of(us)}
	return {}
