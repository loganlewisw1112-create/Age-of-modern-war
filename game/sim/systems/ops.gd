extends RefCounted
## Officers, groups, delegated missions (owner: agent C2). Contract: docs/CONTRACTS_G2.md section 4.
## Commands: assign_officer, set_mission, cancel_mission. Mission logic: ops_missions.gd.
##
## Saved state: w.sys_state.ops = {groups: {gid: group}, next_gid}. group = {id, owner, officer,
##   members:[unit ids], mission:{type, target, radius, risk, points, i, goal, dist0}, phase, reason,
##   progress, history:[last 10 reports], phase_tick, last_report, start, losses, secure_ticks,
##   resume, result}. Phases: idle, assess, move, secure, hold, resupply, withdraw.
## The officer drives members through Movement.apply_command directly (never w.submit, which would
## loop through on_direct_order). A member under player override (e.ops_override_until > tick) or
## broken (morale) is skipped. Officer death dissolves the group (OfficerKilled, members -20 morale).
## G6 (ARMY6, CONTRACTS_G6 section 8): a company platoon is a group with parent_company = cid. Its
## officer is the lieutenant (e.rank_role "lieutenant" counts as an officer). When he dies, the
## next-senior member (first alive in members order) takes the platoon (PlatoonLeaderPromoted);
## an empty platoon is dropped. While its company is confused (w.sys_state.companies, captain lost)
## the platoon takes no new orders and its mission is not evaluated. Groups without parent_company
## behave exactly as in G2.

const Movement = preload("res://sim/systems/movement.gd")
const Missions = preload("res://sim/systems/ops_missions.gd")
const Transport = preload("res://sim/systems/transport.gd")  # G4 TRANS: cargo-aware prune

const EVAL_EVERY := 10
const HISTORY_MAX := 10
const MORALE_HIT := 20.0
const MISSIONS := ["secure_point", "hold_zone", "attack_area", "patrol_route", "transport_to_point"]
const RISKS := ["low", "medium", "high"]


static func state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("ops"):
		w.sys_state["ops"] = {"groups": {}, "next_gid": 1}
	return w.sys_state["ops"]


static func rules() -> Dictionary:
	return Content.rules().get("ops", {})


static func _pt(v):
	if typeof(v) == TYPE_VECTOR2:
		return v
	if typeof(v) == TYPE_VECTOR2I:
		return Vector2(v) + Movement.CENTER
	return null


static func is_officer(e) -> bool:
	return e != null and e.kind == "unit" and (bool(Content.unit(e.def).get("is_officer", false)) 		or String(e.get("rank_role", "")) == "lieutenant")


## G6: true while the company owning platoon g is confused after losing its captain.
static func company_confused(w: SimWorld, g: Dictionary) -> bool:
	if not g.has("parent_company") or not w.sys_state.has("companies"):
		return false
	var c: Dictionary = w.sys_state.companies.get("companies", {}).get(int(g.parent_company), {})
	return not c.is_empty() and int(c.get("confused_until", 0)) > w.tick


## The group led by officer oid, or {} (UI/AI helper).
static func group_led_by(w: SimWorld, oid: int) -> Dictionary:
	if not w.sys_state.has("ops"):
		return {}
	var groups: Dictionary = w.sys_state.ops.groups
	for gid in groups:
		if int(groups[gid].officer) == oid:
			return groups[gid]
	return {}


## The group unit uid belongs to (as member or officer), or {} (UI/AI helper).
static func group_of(w: SimWorld, uid: int) -> Dictionary:
	if not w.sys_state.has("ops"):
		return {}
	var groups: Dictionary = w.sys_state.ops.groups
	for gid in groups:
		var g: Dictionary = groups[gid]
		if int(g.officer) == uid or (g.members as Array).has(uid):
			return g
	return {}


static func _assignable(w: SimWorld, uid: int, off: Dictionary) -> bool:
	var e = w.entities.get(uid)
	if e != null and e.has("company") and int(off.get("company", -1)) != int(e.company):
		return false  # G6: company units stay in their company's chain of command
	return e != null and e.kind == "unit" and int(e.owner) == int(off.owner) and uid != int(off.id) and not is_officer(e)


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var off = w.entities.get(int(cmd.get("officer_id", -1)))
	if not is_officer(off) or int(off.owner) != int(cmd.issuer):
		return "Select one of your officers."
	if String(cmd.type) != "cancel_mission" and company_confused(w, group_led_by(w, int(off.id))):
		return "The company is reorganising after losing its captain."
	match String(cmd.type):
		"assign_officer":
			for id in cmd.get("unit_ids", []):
				if _assignable(w, int(id), off):
					return ""
			return "Select at least one non-officer unit to put under this officer."
		"set_mission":
			var g := group_led_by(w, int(off.id))
			if g.is_empty() or (g.members as Array).is_empty():
				return "This officer has no units assigned."
			var m := String(cmd.get("mission", ""))
			if not MISSIONS.has(m) and not Missions.DOC_MISSIONS.has(m):  # G6 (AI7-DOC CR ops_doc_missions)
				return "Unknown mission type '%s'." % m
			var t = _pt(cmd.get("target"))
			if t == null or not w.in_bounds(w.cell_of(t)):
				return "The mission target is outside the map."
			var r := float(cmd.get("radius", 6.0))
			if r < 1.0 or r > 30.0:
				return "Mission radius must be between 1 and 30 tiles."
			if not RISKS.has(String(cmd.get("risk", "medium"))):
				return "Risk must be low, medium or high."
			var pts = cmd.get("points", [])
			if typeof(pts) != TYPE_ARRAY or (pts as Array).size() > 5:
				return "A patrol route takes at most 5 extra waypoints."
			for raw in pts:
				var v = _pt(raw)
				if v == null or not w.in_bounds(w.cell_of(v)):
					return "A patrol waypoint is outside the map."
			if m == "patrol_route" and (pts as Array).is_empty():
				return "A patrol route needs at least one waypoint besides the target."
			if m == "transport_to_point":
				var has := false
				for id in g.members:
					if Transport.is_carrier(w.entities.get(int(id))):
						has = true
				if not has:
					return "Assign a transport to this officer for a transport mission."
			if Missions.DOC_MISSIONS.has(m):  # G6 doctrine missions: raid / sabotage / recon / officer_hunt / exfil
				var why := Missions.validate_doc(w, g, cmd)
				if why != "":
					return why
			return ""
		"cancel_mission":
			var g := group_led_by(w, int(off.id))
			if g.is_empty() or (g.mission as Dictionary).is_empty():
				return "This officer has no active mission."
			return ""
	return "Unknown officer command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var off: Dictionary = w.entities[int(cmd.officer_id)]
	var oid := int(off.id)
	var st := state(w)
	match String(cmd.type):
		"assign_officer":
			var ids := []
			for raw in cmd.get("unit_ids", []):
				if _assignable(w, int(raw), off) and not ids.has(int(raw)):
					ids.append(int(raw))
			# a unit is in at most one group; an officer never serves under another officer
			for gid in st.groups:
				var other: Dictionary = st.groups[gid]
				if int(other.officer) != oid:
					other.members = (other.members as Array).filter(func(x) -> bool: return not ids.has(int(x)))
			var g := group_led_by(w, oid)
			if g.is_empty():
				var gid := int(st.next_gid)
				st.next_gid = gid + 1
				g = {"id": gid, "owner": int(off.owner), "officer": oid, "members": [], "mission": {},
					"phase": "idle", "reason": "", "progress": 0.0, "history": [], "phase_tick": w.tick,
					"last_report": w.tick, "start": 0, "losses": 0, "secure_ticks": 0, "resume": "", "result": ""}
				st.groups[gid] = g
			g.members = ids
			if not (g.mission as Dictionary).is_empty():
				g.start = ids.size() + int(g.losses)
			g.reason = "Officer has %d units under command." % ids.size()
			report(w, g)
		"set_mission":
			var g := group_led_by(w, oid)
			var t: Vector2 = _pt(cmd.target)
			var pts := [t]
			for raw in cmd.get("points", []):
				pts.append(_pt(raw))
			var m := String(cmd.mission)
			var risk := String(cmd.get("risk", "medium"))
			var cen := Missions.centroid(w, g)
			g.mission = {"type": m, "target": t, "radius": float(cmd.get("radius", 6.0)), "risk": risk,
				"points": pts, "i": 0, "goal": t, "dist0": maxf(cen.distance_to(t), 1.0)}
			if Missions.DOC_MISSIONS.has(m):
				Missions.init_doc(w, g, cmd)  # G6 (AI7-DOC CR ops_doc_missions)
			g.start = (g.members as Array).size()
			g.losses = 0
			g.secure_ticks = 0
			g.resume = ""
			g.result = ""
			set_phase(w, g, "assess", "Assessing %s at (%d, %d) with %d units, %s risk." % [m.replace("_", " "),
				int(t.x), int(t.y), g.start, risk], 0.0)
		"cancel_mission":
			var g := group_led_by(w, oid)
			g.mission = {}
			Missions.issue(w, g, Missions.controlled(w, g), "stop", Vector2.ZERO)
			set_phase(w, g, "idle", "Mission cancelled; standing by.", 0.0)


## Called by the world after every direct order (move/attack_move/attack/stop/hold/patrol/guard).
## Ends a unit's patrol/guard unless that is the new order, and detaches group units from mission
## control for rules.ops.override_ticks (they stay in the group).
static func on_direct_order(w: SimWorld, cmd: Dictionary) -> void:
	var t := String(cmd.get("type", ""))
	var until := w.tick + int(rules().get("override_ticks", 200))
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e == null or e.kind != "unit":
			continue
		if t != "patrol":
			e.erase("patrol")
		if t != "guard":
			e.erase("guard")
		e.erase("unload_order")  # G4 TRANS: a direct order cancels a pending unload / pickup
		e.erase("pickup")
		if not group_of(w, int(raw)).is_empty():
			e.ops_override_until = until


# ================================================================ reports / phases
## (implemented in ops_missions.gd, which must not preload this file: no cyclic preload)
static func set_phase(w: SimWorld, g: Dictionary, phase: String, reason: String, progress: float) -> void:
	Missions.set_phase(w, g, phase, reason, progress)


static func report(w: SimWorld, g: Dictionary) -> void:
	Missions.report(w, g)


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	if not w.sys_state.has("ops"):
		return
	prune(w)
	var st: Dictionary = w.sys_state.ops
	for gid in st.groups:
		var g: Dictionary = st.groups[gid]
		if not (g.mission as Dictionary).is_empty() and (w.tick + int(gid)) % EVAL_EVERY == 0 				and not company_confused(w, g):
			Missions.evaluate(w, g)


## Drop dead members (counting mission losses) and dissolve groups whose officer died.
## G4 TRANS: first resolves carriers that died this step (Transport.sweep: eject or kill cargo);
## members and officers riding in a carrier (w.cache.cargo_of) are alive and stay in the group.
## Runs in tick() AND at the end of every world step (ORCH), so no group ever outlives its
## officer past the tick it died in (found by the G2 soak invariant, seed 4).
static func prune(w: SimWorld) -> void:
	Transport.sweep(w)
	if not w.sys_state.has("ops"):
		return
	var st: Dictionary = w.sys_state.ops
	var dead := []
	for gid in st.groups:
		var g: Dictionary = st.groups[gid]
		var off = w.entities.get(int(g.officer))
		if (off == null or off.kind != "unit") and not Transport.in_cargo(w, int(g.officer)):
			if g.has("parent_company") and _succeed(w, g):
				continue
			dead.append(gid)
			continue
		var alive := []
		for m in g.members:
			var e = w.entities.get(int(m))
			if (e != null and e.kind == "unit") or (e == null and Transport.in_cargo(w, int(m))):
				alive.append(int(m))
			elif not (g.mission as Dictionary).is_empty():
				g.losses = int(g.losses) + 1
		if alive.size() != (g.members as Array).size():
			g.members = alive
	for gid in dead:
		_dissolve(w, st, gid)


## G6 company platoon: the first live member becomes its officer. False when none is left; the
## empty platoon is then dropped silently (no morale hit, nobody to hit).
static func _succeed(w: SimWorld, g: Dictionary) -> bool:
	var old := int(g.officer)
	for m in g.members:
		var e = w.entities.get(int(m))
		if e != null and e.kind == "unit":
			g.officer = int(m)
			g.members = (g.members as Array).filter(func(x) -> bool: return int(x) != int(m))
			e.rank_role = "lieutenant"
			w.emit("PlatoonLeaderPromoted", {"gid": int(g.id), "owner": int(g.owner), "company_id": int(g.parent_company),
				"old": old, "new": int(m)})
			return true
	g.members = []
	return false


static func _dissolve(w: SimWorld, st: Dictionary, gid) -> void:
	var g: Dictionary = st.groups[gid]
	if g.has("parent_company") and (g.members as Array).is_empty():
		st.groups.erase(gid)
		return
	for m in g.members:
		var e = w.entities.get(int(m))
		if e != null and e.has("morale"):
			e.morale = maxf(float(e.morale) - MORALE_HIT, 0.0)
	st.groups.erase(gid)
	w.emit("OfficerKilled", {"gid": int(g.id), "owner": int(g.owner), "officer": int(g.officer),
		"members": (g.members as Array).duplicate()})
