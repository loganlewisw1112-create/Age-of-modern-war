class_name GhostMission10
extends RefCounted
## G10 Ghost mission lifecycle — 11 stages under the hood (Package F). Driven by GhostConductor10.

const GhostExo10 = preload("res://sim/systems/ghost_exo10.gd")

const KEY := "ghost_mission10"
const VER := 1
const PHASES := [
	"tasking", "intel_gate", "package", "rehearsal", "insertion", "approach",
	"action", "complication", "exfil", "hot_wash", "echo",
]


static func _rules() -> Dictionary:
	return Content.rules().get("g10_ghost", {})


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"ver": VER, "next_id": 1, "missions": {}}
	return w.sys_state[KEY]


static func phases() -> Array:
	var r: Array = _rules().get("phases", PHASES)
	return r if r.size() > 0 else PHASES


static func create(w: SimWorld, fid: int, card: Dictionary) -> int:
	var st := _st(w)
	var mid := int(st.next_id)
	st.next_id = mid + 1
	var m := {
		"id": mid,
		"fid": fid,
		"phase": "tasking",
		"phase_i": 0,
		"ticks_in_phase": 0,
		"card": card.duplicate(true),
		"template": String(card.get("template", "QuietDecap")),
		"target": String(card.get("target", "")),
		"roe": String(card.get("roe", "stealth")),
		"intel_grade": String(card.get("intel_grade", "rumour")),
		"package": {},
		"squads": [],
		"refused": false,
		"refuse_reason": "",
		"success": false,
		"echo": {},
		"hot_wash": {},
		"break_contact": bool(_rules().get("break_contact_default", true)),
		"suit_loss": 0,
		"max_suit_loss": int(card.get("max_suit_loss", _rules().get("max_suit_loss", 2))),
		"risk_budget": int(card.get("risk_budget", _rules().get("risk_budget", 3))),
		"workshop_ok": bool(card.get("workshop_ok", true)),
		"suits_ready": int(card.get("suits_ready", 4)),
		"cohesion": float(card.get("cohesion", 70.0)),
		"history": ["tasking"],
	}
	st.missions[str(mid)] = m
	w.emit("GhostMissionCreated", {"fid": fid, "mission": mid, "template": m.template})
	return mid


static func mission(w: SimWorld, mission_id: int) -> Dictionary:
	var st := _st(w)
	var m: Dictionary = st.missions.get(str(mission_id), {})
	if m.is_empty():
		return {}
	return m.duplicate(true)


static func advance(w: SimWorld, mission_id: int) -> Dictionary:
	var st := _st(w)
	var m: Dictionary = st.missions.get(str(mission_id), {})
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	if bool(m.get("refused", false)):
		return {"ok": false, "reason": String(m.get("refuse_reason", "refused")), "phase": String(m.phase)}
	var plist := phases()
	var pi := int(m.get("phase_i", 0))
	if pi >= plist.size():
		return {"ok": true, "phase": "echo", "done": true}
	var phase := String(plist[pi])
	var result := _run_phase(w, m, phase)
	if bool(result.get("block", false)):
		m.refused = true
		m.refuse_reason = String(result.get("reason", "blocked"))
		m.phase = phase
		return {"ok": false, "reason": m.refuse_reason, "phase": phase, "refused": true}
	# Stay in phase for ticks_per_phase, then step.
	m.ticks_in_phase = int(m.get("ticks_in_phase", 0)) + 1
	var need := int(_rules().get("ticks_per_phase", 2))
	if int(m.ticks_in_phase) >= need or bool(result.get("force_advance", false)):
		m.ticks_in_phase = 0
		if pi + 1 < plist.size():
			m.phase_i = pi + 1
			m.phase = String(plist[m.phase_i])
			var hist: Array = m.get("history", [])
			hist.append(m.phase)
			m.history = hist
		else:
			m.phase = "echo"
			m.done = true
	else:
		m.phase = phase
	w.emit("GhostMissionPhase", {"mission": mission_id, "phase": String(m.phase), "fid": int(m.fid)})
	return {"ok": true, "phase": String(m.phase), "detail": result}


static func _run_phase(w: SimWorld, m: Dictionary, phase: String) -> Dictionary:
	match phase:
		"tasking":
			return {
				"force_advance": true,
				"target_class": String(m.get("target", "officer")),
				"roe": String(m.get("roe", "stealth")),
				"risk_budget": int(m.get("risk_budget", 3)),
				"max_suit_loss": int(m.get("max_suit_loss", 2)),
			}
		"intel_gate":
			return _intel_gate(m)
		"package":
			return _build_package(w, m)
		"rehearsal":
			return {"force_advance": true, "optional": true}
		"insertion":
			return {"force_advance": true, "method": String(m.package.get("insert", "foot"))}
		"approach":
			return {"force_advance": true, "break_contact": bool(m.get("break_contact", true))}
		"action":
			m.success = true
			return {"force_advance": true, "primary": true}
		"complication":
			return {"force_advance": true, "draw": "none"}
		"exfil":
			return {"force_advance": true, "hierarchy": ["primary", "cache", "ground"]}
		"hot_wash":
			return _hot_wash(w, m)
		"echo":
			return _echo(w, m)
	return {"force_advance": true}


static func _intel_rank(grade: String) -> int:
	var grades: Array = _rules().get("intel_grades", ["rumour", "pattern", "fix", "keyhole"])
	return grades.find(grade)


static func _intel_gate(m: Dictionary) -> Dictionary:
	var grade := String(m.get("intel_grade", "rumour"))
	var tmpl: Dictionary = _rules().get("templates", {}).get(String(m.get("template", "")), {})
	var needs_death := bool(tmpl.get("death", true))
	var min_g := String(_rules().get("death_intel_min", "pattern"))
	if needs_death and _intel_rank(grade) < _intel_rank(min_g):
		return {
			"block": true,
			"reason": "Death insert refused: intel %s below %s" % [grade, min_g],
		}
	if not bool(m.get("workshop_ok", true)):
		return {"block": true, "reason": "Workshop bottleneck: no ready suits."}
	if int(m.get("suits_ready", 0)) <= 0:
		return {"block": true, "reason": "No suits ready."}
	return {"force_advance": true, "grade": grade}


static func _build_package(w: SimWorld, m: Dictionary) -> Dictionary:
	var tmpl_id := String(m.get("template", "QuietDecap"))
	var tmpl: Dictionary = _rules().get("templates", {}).get(tmpl_id, {})
	var pkg_name := String(tmpl.get("package", "strike"))
	var fid := int(m.fid)
	var squads: Array = []
	if bool(tmpl.get("death", true)):
		var sid := GhostExo10.form_squad(w, fid, "4op", "death")
		if sid > 0:
			GhostExo10.assign_package(w, sid, {"package": pkg_name, "hardpoints": ["sensor", "breach"]})
			squads.append(sid)
	if bool(tmpl.get("shadow", false)):
		var sid2 := GhostExo10.form_squad(w, fid, "pair", "shadow")
		if sid2 > 0:
			GhostExo10.assign_package(w, sid2, {"package": "recon", "hardpoints": ["sensor"]})
			squads.append(sid2)
	if bool(tmpl.get("anchor", false)):
		var sid3 := GhostExo10.form_squad(w, fid, "pair", "anchor")
		if sid3 > 0:
			GhostExo10.assign_package(w, sid3, {"package": "assault", "hardpoints": []})
			squads.append(sid3)
	m.squads = squads
	m.package = {
		"template": tmpl_id,
		"loadout": pkg_name,
		"insert": "silent_rotor" if tmpl_id == "QuietDecap" else "foot",
		"roles": ["blade", "glass", "anvil", "hook"],
		"squads": squads.duplicate(),
		"audit": "intel=%s workshop=%s suits=%d cohesion=%.0f" % [
			String(m.get("intel_grade", "")),
			str(bool(m.get("workshop_ok", true))),
			int(m.get("suits_ready", 0)),
			float(m.get("cohesion", 0.0)),
		],
	}
	return {"force_advance": true, "package": m.package.duplicate(true)}


static func _hot_wash(w: SimWorld, m: Dictionary) -> Dictionary:
	var washes: Array = []
	for sid in m.get("squads", []):
		washes.append(GhostExo10.hot_wash(w, int(sid)))
	m.hot_wash = {"squads": washes}
	return {"force_advance": true, "hot_wash": m.hot_wash.duplicate(true)}


static func _echo(w: SimWorld, m: Dictionary) -> Dictionary:
	m.echo = {
		"success": bool(m.get("success", false)),
		"template": String(m.get("template", "")),
		"suit_loss": int(m.get("suit_loss", 0)),
		"adaptations": [],
		"grounded_squads": [],
		"hunter_tick": 0,
		"board_favour": 1 if bool(m.get("success", false)) else -1,
	}
	m.done = true
	return {"force_advance": true, "echo": m.echo.duplicate(true)}


static func force_phase(w: SimWorld, mission_id: int, phase: String) -> String:
	var st := _st(w)
	var m: Dictionary = st.missions.get(str(mission_id), {})
	if m.is_empty():
		return "Unknown mission."
	var plist := phases()
	var i := plist.find(phase)
	if i < 0:
		return "Unknown phase."
	m.phase = phase
	m.phase_i = i
	m.ticks_in_phase = 0
	return ""
