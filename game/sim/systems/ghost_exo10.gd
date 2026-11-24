class_name GhostExo10
extends RefCounted
## G10 Ghost Exo anatomy (GHOST10 Task 14). Camo/battery/wounds/echelons — AI-read depth; Fresh/Worn/Grounded UI.
## State: w.sys_state.ghost_exo10. ORCH wires tick later; exo.gd may forward when Ghost state exists.

const Coalition10 = preload("res://sim/systems/coalition10.gd")

const KEY := "ghost_exo10"
const VER := 1
const MOTIONS := ["still", "walk", "sprint", "fire", "hit"]
const FORMATIONS := ["4op", "6op", "solo", "pair"]
const PACKAGES := ["strike", "assault", "recon"]
const ECHELONS := ["death", "shadow", "anchor"]
const ATTRS := ["precision", "nerve", "athletics", "cognition", "endurance", "bond"]


static func _rules() -> Dictionary:
	return Content.rules().get("g10_ghost", {})


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"ver": VER, "next_id": 1, "squads": {}, "ops": {}}
	return w.sys_state[KEY]


static func active(w: SimWorld) -> bool:
	return w.sys_state.has(KEY)


static func is_ghost_suit_def(def_id: String) -> bool:
	var d := Content.unit(def_id)
	return bool(d.get("ghost_regiment", false))


static func mk_for_stage(stage: int) -> int:
	var bands: Dictionary = _rules().get("mk_bands", {})
	for mk in [3, 2, 1]:
		var b: Dictionary = bands.get(str(mk), {})
		if stage >= int(b.get("stage_min", 99)) and stage <= int(b.get("stage_max", -1)):
			return mk
	if stage >= 11:
		return 3
	if stage >= 9:
		return 2
	return 1


static func form_squad(w: SimWorld, fid: int, formation: String, echelon: String) -> int:
	if not FORMATIONS.has(formation):
		return -1
	if not ECHELONS.has(echelon):
		return -1
	if not Coalition10.active(w, fid):
		return -1
	var st := _st(w)
	var forms: Dictionary = _rules().get("formations", {})
	var row: Dictionary = forms.get(formation, {})
	var size := int(row.get("size", 4))
	var roles: Array = row.get("roles", [])
	var camo: Dictionary = _rules().get("camo", {})
	var sid := int(st.next_id)
	st.next_id = sid + 1
	var stage := int(w.factions.get(fid, {}).get("stage", 8))
	var ops: Array = []
	for i in size:
		var oid := sid * 100 + i + 1
		var role := String(roles[i]) if i < roles.size() else "specialist"
		var op := {
			"id": oid,
			"squad": sid,
			"fid": fid,
			"role": role,
			"role_card": _default_role_card(role, echelon),
			"cert": _default_cert(role, echelon),
			"condition": "fresh",
			"legend": "",
			"motion": "still",
			"battery": float(camo.get("battery_max", 100.0)),
			"attrs": _default_attrs(),
			"skills": _default_skills(),
			"mastery": "rated",
			"op_wounds": [],
			"suit_wounds": [],
			"kill_switch": 0.0,
		}
		ops.append(op)
		st.ops[str(oid)] = op
	var squad := {
		"id": sid,
		"fid": fid,
		"formation": formation,
		"echelon": echelon,
		"package": "",
		"armor": "",
		"ops": ops.map(func(o): return int(o.id)),
		"cohesion": 70.0,
		"cohesion_read": "tight",
		"mk": mk_for_stage(stage),
		"blood_debt": 0,
		"hardpoints": [],
		"grounded": false,
		"aar": "",
	}
	st.squads[str(sid)] = squad
	w.emit("GhostSquadFormed", {"fid": fid, "squad": sid, "formation": formation, "echelon": echelon})
	return sid


static func _default_attrs() -> Dictionary:
	var out := {}
	for a in ATTRS:
		out[a] = 50
	return out


static func _default_skills() -> Dictionary:
	return {
		"camo_discipline": 50, "silent_movement": 50, "cqb": 50, "marksmanship": 50,
		"breach_demo": 40, "first_aid": 40, "power_management": 50, "acoustic_sense": 40,
		"night_dominance": 50, "exfil_under_pressure": 45,
	}


static func _default_role_card(role: String, echelon: String) -> String:
	var cards: Array = _rules().get("role_cards", [])
	if echelon == "shadow":
		return "spark" if cards.has("spark") else "thread"
	if echelon == "anchor":
		return "torch" if cards.has("torch") else "anvil"
	match role:
		"leader":
			return "blade"
		"point":
			return "glass"
		"gunner":
			return "anvil"
		_:
			return "hook"


static func _default_cert(role: String, echelon: String) -> String:
	if echelon == "shadow":
		return "pathfinder"
	if echelon == "anchor":
		return "combat_medic"
	match role:
		"leader":
			return "infiltrator"
		"point":
			return "sniper"
		"gunner":
			return "anti_armour"
		_:
			return "ew"


static func squad_state(w: SimWorld, squad_id: int) -> Dictionary:
	var st := _st(w)
	var s: Dictionary = st.squads.get(str(squad_id), {})
	if s.is_empty():
		return {}
	return s.duplicate(true)


static func operator_state(w: SimWorld, operator_id: int) -> Dictionary:
	var st := _st(w)
	var o: Dictionary = st.ops.get(str(operator_id), {})
	if o.is_empty():
		return {}
	return o.duplicate(true)


static func ui_read(w: SimWorld, operator_id: int) -> Dictionary:
	var o := operator_state(w, operator_id)
	if o.is_empty():
		return {}
	return {
		"condition": String(o.get("condition", "fresh")),
		"legend": String(o.get("legend", "")),
	}


static func assign_package(w: SimWorld, squad_id: int, package: Dictionary) -> String:
	var st := _st(w)
	var s: Dictionary = st.squads.get(str(squad_id), {})
	if s.is_empty():
		return "Unknown squad."
	var pkg := String(package.get("package", package.get("id", "")))
	if not PACKAGES.has(pkg):
		return "Unknown package."
	var pkgs: Dictionary = _rules().get("packages", {})
	var row: Dictionary = pkgs.get(pkg, {})
	# Hardpoint conflicts: cannot stack net+emp with breach on same slot budget.
	var hardpoints: Array = package.get("hardpoints", [])
	var chassis: Dictionary = _rules().get("chassis", {})
	var max_hp := int(chassis.get("hardpoints", 3))
	if hardpoints.size() > max_hp:
		return "Hardpoint budget exceeded (%d max)." % max_hp
	var kinds := {}
	for h in hardpoints:
		var k := String(h)
		if kinds.has(k):
			return "Duplicate hardpoint %s." % k
		kinds[k] = true
	if kinds.has("net") and kinds.has("emp") and kinds.has("breach"):
		return "Hardpoint conflict: net/EMP/breach cannot all stack."
	s.package = pkg
	s.armor = String(row.get("armor", "medium"))
	s.hardpoints = hardpoints.duplicate()
	if package.has("role_form"):
		s.role_form = String(package.role_form)
	w.emit("GhostPackageAssigned", {"squad": squad_id, "package": pkg, "armor": s.armor})
	return ""


static func set_motion(w: SimWorld, operator_id: int, motion: String) -> String:
	if not MOTIONS.has(motion):
		return "Unknown motion."
	var st := _st(w)
	var o: Dictionary = st.ops.get(str(operator_id), {})
	if o.is_empty():
		return "Unknown operator."
	o.motion = motion
	_drain_for_motion(o, motion)
	return ""


static func _drain_for_motion(o: Dictionary, motion: String) -> void:
	var camo: Dictionary = _rules().get("camo", {})
	var key := "drain_%s" % motion
	var drain := float(camo.get(key, 0.1))
	var pkgs: Dictionary = _rules().get("packages", {})
	# Package battery mult applied via squad later; per-op drain here.
	o.battery = maxf(0.0, float(o.get("battery", 100.0)) - drain)
	if float(o.battery) <= 0.0 and String(o.get("condition", "")) == "fresh":
		o.condition = "worn"


static func recharge(w: SimWorld, operator_id: int, amount: float = -1.0) -> void:
	var st := _st(w)
	var o: Dictionary = st.ops.get(str(operator_id), {})
	if o.is_empty():
		return
	var camo: Dictionary = _rules().get("camo", {})
	var add := amount if amount >= 0.0 else float(camo.get("recharge_per_tick", 0.15))
	var mx := float(camo.get("battery_max", 100.0))
	o.battery = minf(mx, float(o.get("battery", 0.0)) + add)


static func visibility(w: SimWorld, operator_id: int, observer_fid: int) -> float:
	var st := _st(w)
	var o: Dictionary = st.ops.get(str(operator_id), {})
	if o.is_empty():
		return 1.0
	if int(o.get("fid", -1)) == observer_fid:
		return 1.0
	var camo: Dictionary = _rules().get("camo", {})
	var motion := String(o.get("motion", "still"))
	var base := float(camo.get(motion, 0.5))
	if float(o.get("battery", 0.0)) <= 0.0:
		base = maxf(base, float(camo.get("empty_visibility", 0.95)))
	# Observer counters (stored on observer side state or passed via sys).
	var counters: Dictionary = _active_counters(w, observer_fid)
	var ctab: Dictionary = _rules().get("counters", {})
	for ck in counters:
		if bool(counters[ck]):
			base = minf(1.0, base + float(ctab.get(String(ck), 0.0)))
	return clampf(base, 0.0, 1.0)


static func set_counter(w: SimWorld, fid: int, kind: String, on: bool = true) -> void:
	var st := _st(w)
	if not st.has("counters"):
		st.counters = {}
	var row: Dictionary = st.counters.get(str(fid), {})
	row[kind] = on
	st.counters[str(fid)] = row


static func _active_counters(w: SimWorld, fid: int) -> Dictionary:
	var st := _st(w)
	return st.get("counters", {}).get(str(fid), {})


static func apply_wound(w: SimWorld, operator_id: int, kind: String, on_suit: bool = false) -> void:
	var st := _st(w)
	var o: Dictionary = st.ops.get(str(operator_id), {})
	if o.is_empty():
		return
	var key := "suit_wounds" if on_suit else "op_wounds"
	var arr: Array = o.get(key, [])
	if not arr.has(kind):
		arr.append(kind)
	o[key] = arr
	if on_suit and kind == "battery":
		o.battery = maxf(0.0, float(o.battery) * 0.5)
	if kind in ["limb", "joint"] and bool(_rules().get("chassis", {}).get("hardened_joints", false)):
		# Hardened joints reduce but never cancel disable.
		o["disable_mult"] = 0.5
	else:
		o["disable_mult"] = 1.0
	if String(o.get("condition", "")) == "fresh":
		o.condition = "worn"


static func ground_suit(w: SimWorld, squad_id: int) -> void:
	var st := _st(w)
	var s: Dictionary = st.squads.get(str(squad_id), {})
	if s.is_empty():
		return
	s.grounded = true
	for oid in s.get("ops", []):
		var o: Dictionary = st.ops.get(str(oid), {})
		if not o.is_empty():
			o.condition = "grounded"


static func note_unrecovered_loss(w: SimWorld, squad_id: int) -> void:
	var st := _st(w)
	var s: Dictionary = st.squads.get(str(squad_id), {})
	if s.is_empty():
		return
	var debt := int(_rules().get("chassis", {}).get("blood_debt", 5))
	s.blood_debt = int(s.get("blood_debt", 0)) + debt


static func cohesion_delta(w: SimWorld, squad_id: int, delta: float, reason: String = "") -> void:
	var st := _st(w)
	var s: Dictionary = st.squads.get(str(squad_id), {})
	if s.is_empty():
		return
	s.cohesion = clampf(float(s.get("cohesion", 70.0)) + delta, 0.0, 100.0)
	var c := float(s.cohesion)
	if c >= 60.0:
		s.cohesion_read = "tight"
	elif c >= 35.0:
		s.cohesion_read = "frayed"
	else:
		s.cohesion_read = "fractured"
	if reason != "":
		s.aar = reason


static func hot_wash(w: SimWorld, squad_id: int) -> Dictionary:
	var st := _st(w)
	var s: Dictionary = st.squads.get(str(squad_id), {})
	if s.is_empty():
		return {}
	var worn := 0
	var grounded := 0
	var battery_avg := 0.0
	var n := 0
	for oid in s.get("ops", []):
		var o: Dictionary = st.ops.get(str(oid), {})
		if o.is_empty():
			continue
		n += 1
		battery_avg += float(o.get("battery", 0.0))
		var cond := String(o.get("condition", "fresh"))
		if cond == "worn":
			worn += 1
		elif cond == "grounded":
			grounded += 1
	if n > 0:
		battery_avg /= float(n)
	var report := {
		"squad": squad_id,
		"formation": String(s.get("formation", "")),
		"echelon": String(s.get("echelon", "")),
		"package": String(s.get("package", "")),
		"cohesion": float(s.get("cohesion", 0.0)),
		"cohesion_read": String(s.get("cohesion_read", "tight")),
		"worn": worn,
		"grounded": grounded,
		"battery_avg": battery_avg,
		"blood_debt": int(s.get("blood_debt", 0)),
		"mk": int(s.get("mk", 1)),
		"aar": String(s.get("aar", "")),
	}
	s.last_hot_wash = report.duplicate(true)
	return report


## Optional forward from Exo.tick when Ghost state exists (ORCH may also call GhostExo10.tick).
static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var st := _st(w)
	for k in st.ops:
		var o: Dictionary = st.ops[k]
		var motion := String(o.get("motion", "still"))
		if motion == "still":
			recharge(w, int(o.id))
		else:
			_drain_for_motion(o, motion)


static func execution_stance(w: SimWorld, operator_id: int, target_kind: String) -> Dictionary:
	## ID 60: secured-down HVT/officer only — interruptible, yields intel, raises heat.
	if target_kind not in ["hvt", "officer"]:
		return {"ok": false, "reason": "Execution stance only vs secured HVT/officer."}
	var o := operator_state(w, operator_id)
	if o.is_empty():
		return {"ok": false, "reason": "Unknown operator."}
	return {"ok": true, "intel_delta": 1, "heat": 2, "interruptible": true, "gory": false}
