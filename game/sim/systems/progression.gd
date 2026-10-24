extends RefCounted
## Progression (owner: STG4): research projects + Stage 7->8->9 advancement. CONTRACTS_G3b section 3.
## Commands (routed here by SimWorld.COMMANDS):
##   {"type": "research", "issuer", "project": id [, "building_id"]}  start a project (cost charged now)
##   {"type": "research", "issuer", "cancel": true}                     cancel the active project (full refund)
##   {"type": "advance_stage", "issuer"}                                 all gates met -> pay once, 60 s transition
## State: w.factions[fid].research {done, active, progress 0..1, facility (-1 = paused), paid}
##        w.factions[fid].advancing {to, ticks_left}
## Research runs at any completed `research: true` building of the side; losing it pauses the project
## (progress kept) until another research building is complete. Advancement never spawns anything.
## Events: ResearchStarted / ResearchPaused / ResearchResumed / ResearchCompleted / ResearchCancelled,
##         StageAdvanceStarted {fid, to}, StageAdvanced {fid, stage}.
## Tick also drives EW jamming (Status.ew_tick) since status.gd is not a system of its own.

const PData = preload("res://sim/systems/progression_data.gd")
const Gates = preload("res://sim/systems/progression_gates.gd")
const Status = preload("res://sim/systems/status.gd")


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		_research_step(w, int(fid), f)
		_advance_step(w, int(fid), f)
	Status.ew_tick(w)


static func _research_step(w: SimWorld, fid: int, f: Dictionary) -> void:
	var r: Dictionary = f.research
	var active := String(r.active)
	if active == "":
		return
	var fac = _facility(w, fid, int(r.facility))
	if fac == null:
		if int(r.facility) != -1:
			r.facility = -1
			w.emit("ResearchPaused", {"fid": fid, "project": active, "progress": float(r.progress)})
		return
	if int(fac.id) != int(r.facility):
		var was := int(r.facility)
		r.facility = int(fac.id)
		if was == -1:
			w.emit("ResearchResumed", {"fid": fid, "project": active, "building_id": int(fac.id)})
	var p := PData.project(active)
	r.progress = float(r.progress) + SimWorld.DT / maxf(float(p.get("time", 1)), 0.001)
	if float(r.progress) >= 1.0 - 0.000001:
		(r.done as Array).append(active)
		r.active = ""
		r.progress = 0.0
		r.facility = -1
		r.erase("paid")
		w.emit("ResearchCompleted", {"fid": fid, "project": active})


## The side's current research building if still valid, else its first completed research building.
static func _facility(w: SimWorld, fid: int, cur: int):
	var b = w.entities.get(cur) if cur >= 0 else null
	if b != null and _is_research_bld(b, fid):
		return b
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building" and _is_research_bld(e, fid):
			return e
	return null


static func _is_research_bld(b: Dictionary, fid: int) -> bool:
	return b.kind == "building" and int(b.owner) == fid and bool(b.built) \
		and bool(Content.building(b.def).get("research", false))


static func _advance_step(w: SimWorld, fid: int, f: Dictionary) -> void:
	var adv: Dictionary = f.advancing
	if int(adv.ticks_left) <= 0:
		return
	adv.ticks_left = int(adv.ticks_left) - 1
	if int(adv.ticks_left) == 0:
		f.stage = int(adv.to)
		adv.to = 0
		w.emit("StageAdvanced", {"fid": fid, "stage": int(f.stage)})


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.issuer)
	var f: Dictionary = w.factions[fid]
	match String(cmd.type):
		"research":
			return _validate_research(w, fid, f, cmd)
		"advance_stage":
			if int(f.advancing.ticks_left) > 0:
				return "Already advancing to Stage %d." % int(f.advancing.to)
			var to := int(f.stage) + 1
			if PData.gates_for(to).is_empty() or not _playable(to):
				return "Stage %d is the highest stage in this slice." % int(f.stage)
			return Gates.first_unmet(w, fid)
	return "Unknown progression command."


static func _validate_research(w: SimWorld, fid: int, f: Dictionary, cmd: Dictionary) -> String:
	var r: Dictionary = f.research
	if bool(cmd.get("cancel", false)):
		return "No research in progress." if String(r.active) == "" else ""
	var id := String(cmd.get("project", ""))
	var p := PData.project(id)
	if p.is_empty():
		return "Unknown research project '%s'." % id
	var nm := PData.project_name(id, String(f.faction_def))
	if (r.done as Array).has(id):
		return "%s is already researched." % nm
	if String(r.active) != "":
		return "Already researching %s." % PData.project_name(String(r.active), String(f.faction_def))
	if int(f.stage) < int(p.get("stage_min", 7)):
		return "Requires Stage %d" % int(p.get("stage_min", 7))
	if cmd.has("building_id"):
		var b: Dictionary = w.entities[int(cmd.building_id)]
		if not bool(Content.building(b.def).get("research", false)):
			return "%s cannot research." % String(Content.building(b.def).get("name", b.def))
		if not bool(b.built):
			return "The building is still under construction."
	elif _facility(w, fid, -1) == null:
		return "Requires a completed research building."
	return w.can_afford(fid, p.get("cost", {}))


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	var f: Dictionary = w.factions[fid]
	match String(cmd.type):
		"research":
			var r: Dictionary = f.research
			if bool(cmd.get("cancel", false)):
				var proj := String(r.active)
				w.credit(fid, r.get("paid", {}), "research_cancel:" + proj)
				r.active = ""
				r.progress = 0.0
				r.facility = -1
				r.erase("paid")
				w.emit("ResearchCancelled", {"fid": fid, "project": proj})
				return
			var id := String(cmd.project)
			var cost: Dictionary = PData.project(id).get("cost", {})
			if not w.spend(fid, cost, "research:" + id):
				return
			var paid := {}
			for k in SimWorld.LEDGER_KEYS:
				if int(cost.get(k, 0)) > 0:
					paid[k] = int(cost[k])
			var fac = w.entities.get(int(cmd.building_id)) if cmd.has("building_id") else _facility(w, fid, -1)
			r.active = id
			r.progress = 0.0
			r.facility = int(fac.id) if fac != null else -1
			r.paid = paid
			w.emit("ResearchStarted", {"fid": fid, "project": id, "building_id": int(r.facility)})
		"advance_stage":
			var to := int(f.stage) + 1
			var cost := PData.advance_cost(w, to)
			if not w.spend(fid, cost, "advance_stage:%d" % to):
				return
			f.advancing = {"to": to, "ticks_left": PData.transition_ticks()}
			w.emit("StageAdvanceStarted", {"fid": fid, "to": to, "ticks": PData.transition_ticks()})


static func _playable(stage: int) -> bool:
	for st in Content.stages():
		if int(st.id) == stage:
			return bool(st.get("playable_now", false))
	return false


# ================================================================ queries (UI / AI)
## Gate checklist for the side's next stage: [{key, label, have, need, ok}] ([] at the top stage).
static func gate_report(w: SimWorld, fid: int) -> Array:
	return Gates.report(w, fid)


## "" when advance_stage would be accepted now, else the reason.
static func can_advance(w: SimWorld, fid: int) -> String:
	return validate_command(w, {"type": "advance_stage", "issuer": fid})


## Research projects with per-side state, for the research panel:
## [{id, name, cost, time, stage_min, for_stage, done, active, progress, paused, reason}]
static func research_list(w: SimWorld, fid: int) -> Array:
	var f: Dictionary = w.factions[fid]
	var r: Dictionary = f.research
	var out := []
	for id in PData.project_ids():
		var p := PData.project(id)
		var is_active: bool = String(r.active) == String(id)
		out.append({"id": id, "name": PData.project_name(id, String(f.faction_def)), "cost": p.get("cost", {}),
			"time": float(p.get("time", 0)), "stage_min": int(p.get("stage_min", 7)), "for_stage": int(p.get("for_stage", 0)),
			"done": (r.done as Array).has(id), "active": is_active,
			"progress": float(r.progress) if is_active else 0.0,
			"paused": is_active and int(r.facility) == -1,
			"reason": "" if is_active else _validate_research(w, fid, f, {"type": "research", "project": id})})
	return out


## Unavailability reason for a def at this side's stage/research ("" = available). For UI buttons.
static func unavailable_reason(w: SimWorld, fid: int, d: Dictionary) -> String:
	return PData.unavailable_reason(w, fid, d)
