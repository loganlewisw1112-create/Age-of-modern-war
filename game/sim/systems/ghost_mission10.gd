class_name GhostMission10
extends RefCounted
## G10 Ghost mission lifecycle — 11 stages + Task16 insertion/support/recovery vehicles.
## Mole uses Tunnels10 public API (not Machine burrower). transport.gd not edited.

const GhostExo10 = preload("res://sim/systems/ghost_exo10.gd")
const Tunnels10 = preload("res://sim/systems/tunnels10.gd")
const Transport = preload("res://sim/systems/transport.gd")

const KEY := "ghost_mission10"
const VER := 2
const PHASES := [
	"tasking", "intel_gate", "package", "rehearsal", "insertion", "approach",
	"action", "complication", "exfil", "hot_wash", "echo",
]


static func _rules() -> Dictionary:
	return Content.rules().get("g10_ghost", {})


static func _veh() -> Dictionary:
	return _rules().get("vehicles", {})


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
		"vehicles": _blank_vehicles(),
		"warnings": [],
	}
	if card.has("field"):
		m.field = (card.field as Dictionary).duplicate(true)
		m.vehicles.insert = "foot"
		m.vehicles.exfil = "foot"
	st.missions[str(mid)] = m
	w.emit("GhostMissionCreated", {"fid": fid, "mission": mid, "template": m.template})
	return mid


static func _blank_vehicles() -> Dictionary:
	return {
		"insert": "",
		"exfil": "",
		"terrain": "ground",
		"silent_rotor": {"mode": "quiet", "flipped": false, "signature": 0.08},
		"mole": {
			"primary": -1, "alternate": -1, "collapse_behind": false,
			"exit_used": -1, "collapsed": false, "planned": false,
		},
		"runner": {
			"tethered": false, "driver_op": -1, "range": 12, "link_ok": false,
			"ticks_out": 0, "lost": false, "recovered": false,
		},
		"mule": {
			"posture": "supply", "overcharge_armed": false, "overcharge_delay": 0,
			"cores_destroyed": false, "suit_cores": [], "abandonment": false,
		},
		"anchor": {
			"workshop_queue": [], "supply_log": [], "race_winner": "",
			"grounded": [],
		},
		"drones": {
			"door_kick": [], "wiretap": [], "spider": [], "reaper": [],
			"magazine": "", "nest_alive": true, "nest_stock": 4,
		},
		"kits": {"applied": []},
		"lifecycle": [],
	}


static func mission(w: SimWorld, mission_id: int) -> Dictionary:
	var st := _st(w)
	var m: Dictionary = st.missions.get(str(mission_id), {})
	if m.is_empty():
		return {}
	return m.duplicate(true)


static func _mref(w: SimWorld, mission_id: int) -> Dictionary:
	return _st(w).missions.get(str(mission_id), {})


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
	m.ticks_in_phase = int(m.get("ticks_in_phase", 0)) + 1
	if bool(result.get("wait", false)):
		return {"ok": true, "phase": phase, "detail": result}
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
	if m.has("field") and phase in ["approach", "action", "exfil"]:
		return _field_phase(w, m, phase)
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
			return _phase_insertion(m)
		"approach":
			return {"force_advance": true, "break_contact": bool(m.get("break_contact", true))}
		"action":
			m.success = true
			return {"force_advance": true, "primary": true}
		"complication":
			return {"force_advance": true, "draw": "none"}
		"exfil":
			return _phase_exfil(m)
		"hot_wash":
			return _hot_wash(w, m)
		"echo":
			return _echo(w, m)
	return {"force_advance": true}


## Orders real operators through the same movement and combat paths used by player commands.
static func _field_phase(w: SimWorld, m: Dictionary, phase: String) -> Dictionary:
	var field: Dictionary = m.field
	var fid := int(m.fid)
	var operators: Array = []
	for id in field.unit_ids:
		var e = w.entities.get(int(id))
		if e != null and int(e.owner) == fid and float(e.hp) > 0.0:
			operators.append(e)
	m.suit_loss = (field.unit_ids as Array).size() - operators.size()
	if operators.is_empty():
		m.success = false
		return {"force_advance": true, "outcome": "squad_lost"}
	var at := Vector2(field.home if phase == "exfil" else field.position)
	var elapsed := int(m.ticks_in_phase)
	if elapsed == 0:
		var ot := "attack_move" if phase == "action" else "move"
		var ids := operators.map(func(e): return int(e.id))
		w.submit({"type": ot, "issuer": fid, "unit_ids": ids, "target": at})
	var arrived := operators.any(func(e): return Vector2(e.pos).distance_squared_to(at) <= 36.0)
	var over_loss := int(m.suit_loss) > int(m.get("max_suit_loss", 2))
	match phase:
		"approach":
			field.approached = arrived and not over_loss
			if field.approached or over_loss or elapsed >= 600:
				return {"force_advance": true, "approached": field.approached}
		"action":
			if arrived and not w.entities.has(int(field.id)):
				m.success = true
				return {"force_advance": true, "primary": true}
			if over_loss or not bool(field.get("approached", false)) or elapsed >= 400:
				m.success = false
				return {"force_advance": true, "primary": false}
		"exfil":
			if operators.all(func(e): return Vector2(e.pos).distance_squared_to(at) <= 36.0) or elapsed >= 600:
				m.field["extracted"] = arrived
				if not arrived:
					m.success = false
				return _phase_exfil(m)
	return {"wait": true}


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
	var insert := String(m.vehicles.get("insert", "")) if m.has("vehicles") else ""
	if insert == "":
		insert = "silent_rotor" if tmpl_id == "QuietDecap" else "foot"
	var exfil := String(m.vehicles.get("exfil", "")) if m.has("vehicles") else ""
	if exfil == "":
		exfil = insert if insert != "drop_pod" else "silent_rotor"
	if m.has("vehicles"):
		m.vehicles.insert = insert
		m.vehicles.exfil = exfil
	m.package = {
		"template": tmpl_id,
		"loadout": pkg_name,
		"insert": insert,
		"exfil": exfil,
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


static func _phase_insertion(m: Dictionary) -> Dictionary:
	var v: Dictionary = m.get("vehicles", {})
	var method := String(v.get("insert", m.package.get("insert", "foot")))
	var life: Array = v.get("lifecycle", [])
	life.append({"phase": "insertion", "method": method, "mode": String(v.get("silent_rotor", {}).get("mode", ""))})
	v.lifecycle = life
	m.vehicles = v
	return {
		"force_advance": true,
		"method": method,
		"signature": float(v.get("silent_rotor", {}).get("signature", 0.0)),
		"terrain": String(v.get("terrain", "ground")),
	}


static func _phase_exfil(m: Dictionary) -> Dictionary:
	var v: Dictionary = m.get("vehicles", {})
	var method := String(v.get("exfil", m.package.get("exfil", "foot")))
	var sr: Dictionary = v.get("silent_rotor", {})
	if method == "silent_rotor" and bool(sr.get("flipped", false)):
		_warn(m, String(_veh().get("silent_rotor", {}).get("warning", "weapons_open_high_signature")))
	var life: Array = v.get("lifecycle", [])
	life.append({
		"phase": "exfil",
		"method": method,
		"gunship": bool(sr.get("flipped", false)),
		"hierarchy": ["primary", "cache", "ground"],
	})
	v.lifecycle = life
	m.vehicles = v
	return {
		"force_advance": true,
		"method": method,
		"hierarchy": ["primary", "cache", "ground"],
		"signature": float(sr.get("signature", 0.0)),
	}


static func _warn(m: Dictionary, code: String) -> void:
	var warr: Array = m.get("warnings", [])
	if not warr.has(code):
		warr.append(code)
	m.warnings = warr


static func _hot_wash(w: SimWorld, m: Dictionary) -> Dictionary:
	var washes: Array = []
	for sid in m.get("squads", []):
		washes.append(GhostExo10.hot_wash(w, int(sid)))
	m.hot_wash = {"squads": washes}
	return {"force_advance": true, "hot_wash": m.hot_wash.duplicate(true)}


static func _echo(w: SimWorld, m: Dictionary) -> Dictionary:
	if m.has("field") and bool(m.get("success", false)):
		SimWorld.CoalitionTech10.note_evidence(w, int(m.fid), "raid")
	m.echo = {
		"success": bool(m.get("success", false)),
		"template": String(m.get("template", "")),
		"suit_loss": int(m.get("suit_loss", 0)),
		"adaptations": [],
		"grounded_squads": [],
		"hunter_tick": 0,
		"board_favour": 1 if bool(m.get("success", false)) else -1,
		"vehicle_lifecycle": (m.get("vehicles", {}) as Dictionary).get("lifecycle", []).duplicate(),
		"warnings": (m.get("warnings", []) as Array).duplicate(),
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


# --- Task 16: insert/exfil contracts -------------------------------------------------

static func _is_tunnel_entrance(w: SimWorld, eid: int) -> bool:
	var e = w.entities.get(eid)
	if e == null:
		return false
	return String(e.get("def", "")) == "x_tunnel_entrance" and bool(e.get("built", true))


static func insert_methods() -> Array:
	var out: Array = []
	var tab: Dictionary = _veh().get("insert_methods", {})
	var keys: Array = tab.keys()
	keys.sort()
	for k in keys:
		out.append(String(k))
	return out


static func validate_method(method: String, terrain: String, stage: int, for_exfil: bool = false) -> Dictionary:
	var tab: Dictionary = _veh().get("insert_methods", {})
	if not tab.has(method):
		return {"ok": false, "reason": "Unknown method %s." % method}
	var row: Dictionary = tab[method]
	if for_exfil and not bool(row.get("exfil", true)):
		return {"ok": false, "reason": "%s cannot exfil." % method}
	if stage < int(row.get("stage_min", 1)):
		return {"ok": false, "reason": "%s needs stage ≥ %d." % [method, int(row.stage_min)]}
	var terrains: Array = row.get("terrains", [])
	if not terrains.has(terrain):
		return {"ok": false, "reason": "%s illegal on terrain %s." % [method, terrain]}
	var def_id := String(row.get("def", ""))
	if def_id != "" and not bool(row.get("mission_asset", false)):
		var u := Content.unit(def_id)
		if u.is_empty():
			return {"ok": false, "reason": "Missing vehicle def %s." % def_id}
		# Public transport seam only — capacity query; no transport.gd edits.
		var _cap := Transport.capacity(def_id)
	return {
		"ok": true,
		"method": method,
		"terrain": terrain,
		"stage_min": int(row.get("stage_min", 1)),
		"def": def_id,
		"mission_asset": bool(row.get("mission_asset", false)),
	}


static func assign_insert(w: SimWorld, mission_id: int, method: String, terrain: String = "ground") -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var stage := int(w.factions.get(int(m.fid), {}).get("stage", 8))
	var vcheck := validate_method(method, terrain, stage, false)
	if not bool(vcheck.ok):
		return vcheck
	m.vehicles.insert = method
	m.vehicles.terrain = terrain
	if method == "silent_rotor":
		var sr_r: Dictionary = _veh().get("silent_rotor", {})
		m.vehicles.silent_rotor = {
			"mode": "quiet",
			"flipped": false,
			"signature": float(sr_r.get("quiet_signature", 0.08)),
		}
	return {"ok": true, "insert": method, "terrain": terrain}


static func assign_exfil(w: SimWorld, mission_id: int, method: String, terrain: String = "ground") -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var stage := int(w.factions.get(int(m.fid), {}).get("stage", 8))
	var vcheck := validate_method(method, terrain, stage, true)
	if not bool(vcheck.ok):
		return vcheck
	m.vehicles.exfil = method
	return {"ok": true, "exfil": method, "terrain": terrain}


# --- Silent Rotor flip (13) ----------------------------------------------------------

static func silent_rotor_flip(w: SimWorld, mission_id: int) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var insert := String(m.vehicles.get("insert", ""))
	var exfil := String(m.vehicles.get("exfil", ""))
	if insert != "silent_rotor" and exfil != "silent_rotor":
		return {"ok": false, "reason": "No Silent Rotor on this mission."}
	var sr: Dictionary = m.vehicles.get("silent_rotor", {})
	if bool(sr.get("flipped", false)):
		return {"ok": false, "reason": "Already flipped; one-way."}
	var cfg: Dictionary = _veh().get("silent_rotor", {})
	sr.mode = "gunship"
	sr.flipped = true
	sr.signature = float(cfg.get("gunship_signature", 0.92))
	m.vehicles.silent_rotor = sr
	m.vehicles.exfil = "silent_rotor"
	_warn(m, String(cfg.get("warning", "weapons_open_high_signature")))
	_warn(m, "counter:%s" % String(cfg.get("counter", "aa_and_sensor")))
	w.emit("GhostSilentRotorFlip", {"mission": mission_id, "signature": float(sr.signature)})
	return {"ok": true, "mode": "gunship", "one_way": true, "signature": float(sr.signature), "warning": true}


# --- Mole multipath (14) via Tunnels10 ------------------------------------------------

static func mole_plan(w: SimWorld, mission_id: int, primary: int, alternate: int, collapse_behind: bool = false) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	if String(m.vehicles.get("insert", "")) != "mole" and String(m.vehicles.get("exfil", "")) != "mole":
		# Allow plan before assign when caller sets insert next; require assign for run.
		pass
	var cfg: Dictionary = _veh().get("mole", {})
	if bool(cfg.get("not_machine_burrower", true)) and String(cfg.get("uses", "")) != "tunnels10":
		return {"ok": false, "reason": "Mole must use Tunnels10, not Machine burrower."}
	if primary == alternate:
		return {"ok": false, "reason": "Alternate exit must differ from primary."}
	if not _is_tunnel_entrance(w, primary) or not _is_tunnel_entrance(w, alternate):
		return {"ok": false, "reason": "Mole exits must be tunnel entrances."}
	# Ghost Mole never shares Machine burrower naming.
	m.vehicles.mole = {
		"primary": primary,
		"alternate": alternate,
		"collapse_behind": collapse_behind,
		"exit_used": -1,
		"collapsed": false,
		"planned": true,
		"asset": "x_mole",
		"uses": "tunnels10",
	}
	m.vehicles.insert = "mole"
	m.vehicles.terrain = "tunnel"
	if collapse_behind:
		_warn(m, String(cfg.get("collapse_warning", "tunnel_collapse_readable")))
	return {"ok": true, "primary": primary, "alternate": alternate, "collapse_behind": collapse_behind}


static func mole_run(w: SimWorld, mission_id: int, unit_ids: Array, entrance: int, use_alternate: bool = false) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var mole: Dictionary = m.vehicles.get("mole", {})
	if not bool(mole.get("planned", false)):
		return {"ok": false, "reason": "Mole route not planned."}
	var exit_id := int(mole.alternate) if use_alternate else int(mole.primary)
	if not Tunnels10.linked(w, entrance, exit_id):
		if not Tunnels10.link(w, entrance, exit_id):
			return {"ok": false, "reason": "Cannot link Mole path."}
	var err := Tunnels10.transit(w, int(m.fid), unit_ids, entrance, exit_id)
	if err != "":
		return {"ok": false, "reason": err}
	mole.exit_used = exit_id
	mole.used_alternate = use_alternate
	m.vehicles.mole = mole
	var life: Array = m.vehicles.get("lifecycle", [])
	life.append({"phase": "mole_run", "exit": exit_id, "alternate": use_alternate})
	m.vehicles.lifecycle = life
	if bool(mole.get("collapse_behind", false)):
		Tunnels10.collapse(w, entrance, "ghost_mole_collapse")
		mole.collapsed = true
		m.vehicles.mole = mole
		_warn(m, "tunnel_collapse_readable")
	return {"ok": true, "exit": exit_id, "collapsed": bool(mole.get("collapsed", false))}


# --- Ghost Runner tether (15) --------------------------------------------------------

static func runner_tether(w: SimWorld, mission_id: int, driver_op: int, tether_range: int = -1) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var cfg: Dictionary = _veh().get("runner", {})
	var rng := tether_range if tether_range > 0 else int(cfg.get("tether_range", 12))
	if driver_op <= 0:
		return {"ok": false, "reason": "Remote driver required."}
	m.vehicles.runner = {
		"tethered": true,
		"driver_op": driver_op,
		"range": rng,
		"link_ok": true,
		"ticks_out": 0,
		"lost": false,
		"recovered": false,
		"ownership": "remote_driver",
	}
	m.vehicles.insert = "ghost_runner" if String(m.vehicles.get("insert", "")) == "" else m.vehicles.insert
	return {"ok": true, "driver_op": driver_op, "range": rng}


static func runner_set_distance(w: SimWorld, mission_id: int, distance: int) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var r: Dictionary = m.vehicles.get("runner", {})
	if not bool(r.get("tethered", false)):
		return {"ok": false, "reason": "Runner not tethered."}
	if bool(r.get("lost", false)):
		return {"ok": false, "reason": "Link already lost."}
	var in_range := distance <= int(r.get("range", 12))
	r.link_ok = in_range
	if not in_range:
		r.ticks_out = int(r.get("ticks_out", 0)) + 1
		var loss_need := int(_veh().get("runner", {}).get("link_loss_ticks", 8))
		if int(r.ticks_out) >= loss_need:
			r.lost = true
			r.link_ok = false
			_warn(m, "runner_link_lost")
	else:
		r.ticks_out = 0
	m.vehicles.runner = r
	return {"ok": true, "link_ok": bool(r.link_ok), "lost": bool(r.lost), "ticks_out": int(r.ticks_out)}


static func runner_recover(w: SimWorld, mission_id: int) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var r: Dictionary = m.vehicles.get("runner", {})
	if not bool(r.get("tethered", false)):
		return {"ok": false, "reason": "No Runner."}
	if not bool(r.get("lost", false)) and bool(r.get("link_ok", false)):
		return {"ok": false, "reason": "Runner still linked; recover only after loss."}
	r.recovered = true
	r.lost = false
	r.link_ok = false
	r.tethered = false
	m.vehicles.runner = r
	return {"ok": true, "recovered": true}


# --- Guardian Mule (17/44) -----------------------------------------------------------

static func mule_set_posture(w: SimWorld, mission_id: int, posture: String) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var postures: Array = _veh().get("guardian_mule", {}).get("postures", ["supply", "guardian", "overcharge"])
	if not postures.has(posture):
		return {"ok": false, "reason": "Unknown mule posture."}
	if posture == "overcharge":
		return {"ok": false, "reason": "Use mule_arm_overcharge; overcharge is not a free posture."}
	var mule: Dictionary = m.vehicles.get("mule", {})
	mule.posture = posture
	m.vehicles.mule = mule
	return {"ok": true, "posture": posture}


static func mule_load_cores(w: SimWorld, mission_id: int, cores: Array) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var mule: Dictionary = m.vehicles.get("mule", {})
	var arr: Array = []
	for c in cores:
		arr.append(String(c))
	arr.sort()
	mule.suit_cores = arr
	m.vehicles.mule = mule
	return {"ok": true, "n": arr.size()}


static func mule_mark_abandonment(w: SimWorld, mission_id: int, squad_loss: bool = true) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	if squad_loss:
		m.suit_loss = int(m.get("suit_loss", 0)) + 1
	m.vehicles.mule.abandonment = true
	return {"ok": true, "suit_loss": int(m.suit_loss)}


static func mule_arm_overcharge(w: SimWorld, mission_id: int) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var cfg: Dictionary = _veh().get("guardian_mule", {})
	var mule: Dictionary = m.vehicles.get("mule", {})
	var ok_reason := bool(mule.get("abandonment", false)) or int(m.get("suit_loss", 0)) > 0
	if not ok_reason:
		return {"ok": false, "reason": "Overcharge arms only after squad loss/abandonment."}
	mule.overcharge_armed = true
	mule.overcharge_delay = int(cfg.get("overcharge_delay_ticks", 6))
	mule.posture = "overcharge"
	m.vehicles.mule = mule
	_warn(m, String(cfg.get("warning", "denial_overcharge_armed")))
	return {"ok": true, "delay": int(mule.overcharge_delay), "warning": true}


static func mule_tick_overcharge(w: SimWorld, mission_id: int) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var mule: Dictionary = m.vehicles.get("mule", {})
	if not bool(mule.get("overcharge_armed", false)):
		return {"ok": false, "reason": "Not armed."}
	if bool(mule.get("cores_destroyed", false)):
		return {"ok": true, "done": true, "cores_destroyed": true}
	mule.overcharge_delay = maxi(0, int(mule.get("overcharge_delay", 0)) - 1)
	m.vehicles.mule = mule
	if int(mule.overcharge_delay) > 0:
		return {"ok": true, "delay_left": int(mule.overcharge_delay), "done": false}
	# Detonate: destroys carried suit cores only — not a generic area bomb.
	mule.suit_cores = []
	mule.cores_destroyed = true
	mule.overcharge_armed = false
	m.vehicles.mule = mule
	var life: Array = m.vehicles.get("lifecycle", [])
	life.append({"phase": "mule_denial", "cores_destroyed": true, "area_bomb": false})
	m.vehicles.lifecycle = life
	w.emit("GhostMuleDenial", {"mission": mission_id, "cores_destroyed": true})
	return {"ok": true, "done": true, "cores_destroyed": true, "area_bomb": false}


# --- Anchor supply / recovery / workshop queue ---------------------------------------

static func anchor_queue_suit(w: SimWorld, mission_id: int, suit_id: String, intact: bool, grounded: bool = true) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var anchor: Dictionary = m.vehicles.get("anchor", {})
	var q: Array = anchor.get("workshop_queue", [])
	q.append({"suit": suit_id, "intact": intact, "grounded": grounded, "tick": int(w.tick)})
	# Intact suits race ahead of damaged/grounded scraps.
	q.sort_custom(func(a, b):
		var ai := 1 if bool(a.get("intact", false)) else 0
		var bi := 1 if bool(b.get("intact", false)) else 0
		if ai != bi:
			return ai > bi
		return int(a.get("tick", 0)) < int(b.get("tick", 0))
	)
	anchor.workshop_queue = q
	if grounded:
		var g: Array = anchor.get("grounded", [])
		if not g.has(suit_id):
			g.append(suit_id)
		anchor.grounded = g
	m.vehicles.anchor = anchor
	return {"ok": true, "queue_len": q.size(), "head": String(q[0].suit) if q.size() > 0 else ""}


static func anchor_race_step(w: SimWorld, mission_id: int) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var anchor: Dictionary = m.vehicles.get("anchor", {})
	var q: Array = anchor.get("workshop_queue", [])
	if q.is_empty():
		return {"ok": false, "reason": "Empty workshop queue."}
	var head: Dictionary = q.pop_front()
	anchor.workshop_queue = q
	anchor.race_winner = String(head.get("suit", ""))
	m.vehicles.anchor = anchor
	return {"ok": true, "recovered": String(head.suit), "intact": bool(head.get("intact", false))}


static func anchor_supply(w: SimWorld, mission_id: int, squad_id: int) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	# Anchor echelon gets supply priority.
	var sq := GhostExo10.squad_state(w, squad_id)
	var prio := String(sq.get("echelon", "")) == "anchor"
	var log: Array = m.vehicles.anchor.get("supply_log", [])
	log.append({"squad": squad_id, "priority": prio, "tick": int(w.tick)})
	m.vehicles.anchor.supply_log = log
	if prio and sq.has("ops"):
		for oid in sq.ops:
			GhostExo10.recharge(w, int(oid), 10.0)
	return {"ok": true, "priority": prio, "squad": squad_id}


# --- Support drones 9/10/37/38/40/41 -------------------------------------------------

static func drone_op(w: SimWorld, mission_id: int, kind: String, action: String, opts: Dictionary = {}) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var drones_cfg: Dictionary = _veh().get("drones", {})
	if not drones_cfg.has(kind):
		return {"ok": false, "reason": "Unknown drone kind."}
	var row: Dictionary = drones_cfg[kind]
	var actions: Array = row.get("actions", [])
	if kind == "magazines" or kind == "nest":
		return {"ok": false, "reason": "Use magazine_swap / nest_* APIs."}
	if not actions.has(action):
		return {"ok": false, "reason": "Illegal %s action %s." % [kind, action]}
	var d: Dictionary = m.vehicles.get("drones", {})
	var log: Array = d.get(kind, [])
	log.append({"action": action, "opts": opts.duplicate(true), "tick": int(w.tick)})
	d[kind] = log
	m.vehicles.drones = d
	var life: Array = m.vehicles.get("lifecycle", [])
	life.append({"phase": "drone", "kind": kind, "action": action, "id": int(row.get("id", 0))})
	m.vehicles.lifecycle = life
	return {"ok": true, "kind": kind, "action": action, "id": int(row.get("id", 0))}


static func magazine_swap(w: SimWorld, mission_id: int, kind: String, on_pad: bool = true) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var cfg: Dictionary = _veh().get("drones", {}).get("magazines", {})
	var kinds: Array = cfg.get("kinds", [])
	if not kinds.has(kind):
		return {"ok": false, "reason": "Unknown magazine kind."}
	if bool(cfg.get("pad_only", true)) and not on_pad:
		return {"ok": false, "reason": "Magazine swap is pad-only."}
	m.vehicles.drones.magazine = kind
	var life: Array = m.vehicles.get("lifecycle", [])
	life.append({"phase": "magazine_swap", "kind": kind})
	m.vehicles.lifecycle = life
	return {"ok": true, "magazine": kind, "saved": true}


static func nest_repair(w: SimWorld, mission_id: int) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var d: Dictionary = m.vehicles.get("drones", {})
	if not bool(d.get("nest_alive", true)):
		return {"ok": false, "reason": "Nest destroyed."}
	d.nest_stock = int(d.get("nest_stock", 0)) + 1
	m.vehicles.drones = d
	return {"ok": true, "stock": int(d.nest_stock)}


static func nest_replenish(w: SimWorld, mission_id: int) -> Dictionary:
	return nest_repair(w, mission_id)


static func nest_destroy(w: SimWorld, mission_id: int) -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	m.vehicles.drones.nest_alive = false
	m.vehicles.drones.nest_stock = 0
	_warn(m, "nest_destroyed")
	return {"ok": true, "nest_alive": false, "saved": true}


# --- Kits 20–22 ----------------------------------------------------------------------

static func kit_apply(w: SimWorld, mission_id: int, kit: String, subtype: String = "", target_tag: String = "") -> Dictionary:
	var m := _mref(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	var kits: Dictionary = _veh().get("kits", {})
	if not kits.has(kit):
		return {"ok": false, "reason": "Unknown kit."}
	var row: Dictionary = kits[kit]
	match kit:
		"breach_charges":
			var kinds: Array = row.get("kinds", [])
			if not kinds.has(subtype):
				return {"ok": false, "reason": "Breach kind must be soft/hard/collapse."}
		"emp_scalpel":
			var strong: Array = row.get("strong_vs", [])
			var weak: Array = row.get("weak_vs", [])
			var potency := "neutral"
			if strong.has(target_tag):
				potency = "strong"
			elif weak.has(target_tag):
				potency = "weak"
			var rec := {"kit": kit, "subtype": subtype, "target": target_tag, "potency": potency}
			var applied: Array = m.vehicles.kits.get("applied", [])
			applied.append(rec)
			m.vehicles.kits.applied = applied
			if potency == "weak":
				_warn(m, "emp_scalpel_weak_vs_human")
			return {"ok": true, "potency": potency, "narrow": bool(row.get("narrow", true))}
		"backdoor_spike":
			var need := String(row.get("requires_provenance", "syndicate_compromised"))
			var prov := String(subtype) if subtype != "" else target_tag
			if prov != need:
				return {"ok": false, "reason": "Backdoor requires %s provenance." % need, "universal": false}
	var applied2: Array = m.vehicles.kits.get("applied", [])
	applied2.append({"kit": kit, "subtype": subtype, "target": target_tag})
	m.vehicles.kits.applied = applied2
	return {"ok": true, "kit": kit, "subtype": subtype}
