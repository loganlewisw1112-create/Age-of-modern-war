class_name CounterGhost10
extends RefCounted
## G10 Human A Counter-Ghost Corps (CG10 Task 17 + owner addendum 171).
## Weaker reverse-exo vs Coalition Death. No CN/Blackglass. State: w.sys_state.counter_ghost10.
## Vehicle homes: each CG vehicle parks/repairs/rearms only at its matching home pad/garage.

const GhostExo10 = preload("res://sim/systems/ghost_exo10.gd")

const KEY := "counter_ghost10"
const VER := 1
const FORMATIONS := ["4op", "6op", "ward_pair"]
const LOADOUTS := ["interceptor", "bulwark", "seeker", "ward"]
const INTENTS := [
	"cg_sweep", "cg_intercept", "cg_strip_killswitch", "cg_recover_suit",
	"cg_break_contact", "cg_escort_vip", "cg_hunt_ghosts", "cg_contest_suit",
]
const SCENARIO_PHASES := ["detect", "intercept", "disable", "strip", "recover"]
const SPIDER_MODES := ["flechette", "sticky_foam", "ultrasonic_peel"]


static func _rules() -> Dictionary:
	return Content.rules().get("g10_counterghost", {})


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {
			"ver": VER,
			"next_id": 1,
			"squads": {},
			"ops": {},
			"ops_live": {},
			"tracks": {},
			"strips": {},
			"recoveries": {},
			"scenarios": {},
			"spiders": {},
			"foam": {},
			"next_op": 1,
			"next_scenario": 1,
			"next_strip": 1,
			"next_recover": 1,
		}
	return w.sys_state[KEY]


static func active(w: SimWorld) -> bool:
	return w.sys_state.has(KEY)


static func is_human_a(w: SimWorld, fid: int) -> bool:
	if not w.factions.has(fid):
		return false
	var f: Dictionary = w.factions[fid]
	var id := String(f.get("faction_def", f.get("faction", "")))
	return id == "human_a"


static func is_cg_def(def_id: String) -> bool:
	var d := Content.unit(def_id)
	return bool(d.get("counter_ghost", false))


static func stage_ok(w: SimWorld, fid: int) -> bool:
	var need := int(_rules().get("stage_min", 10))
	return int(w.factions.get(fid, {}).get("stage", 0)) >= need


static func loadout_stats(loadout: String) -> Dictionary:
	var row: Dictionary = _rules().get("loadouts", {}).get(loadout, {})
	return row.duplicate(true) if not row.is_empty() else {}


static func weaker_than_death(loadout: String) -> bool:
	var lo := loadout_stats(loadout)
	var death: Dictionary = _rules().get("death_baseline", {})
	if lo.is_empty() or death.is_empty():
		return false
	return float(lo.get("camo", 1.0)) < float(death.get("camo", 1.0)) \
		and float(lo.get("armor", 1.0)) < float(death.get("armor", 1.0)) \
		and float(lo.get("power", 1.0)) < float(death.get("power", 1.0))


static func no_coalition_production(def_id: String) -> bool:
	var d := Content.unit(def_id)
	if d.is_empty():
		d = Content.building(def_id)
	if bool(d.get("counter_ghost", false)):
		return String(d.get("faction", "")) != "shadow_coalition"
	var p := Content.production(def_id)
	if not p.is_empty() and bool(_rules().get("no_coalition_production", true)):
		return String(p.get("faction", "")) == "human_a"
	return true


static func home_for(vehicle_def: String) -> String:
	var map: Dictionary = _rules().get("vehicle_homes", {})
	if map.has(vehicle_def):
		return String(map[vehicle_def])
	var d := Content.unit(vehicle_def)
	return String(d.get("cg_home", ""))


static func can_service_at(vehicle_def: String, building_def: String) -> bool:
	var home := home_for(vehicle_def)
	if home == "":
		return false
	return home == building_def


static func shade_dart_board(ops_count: int) -> String:
	var sd: Dictionary = _rules().get("shade_dart", {})
	var cap := int(sd.get("capacity_ops", 4))
	if bool(sd.get("no_6op", true)) and ops_count > cap:
		return "Shade Dart carries 4-op only."
	if ops_count > cap:
		return "Shade Dart capacity exceeded."
	return ""


static func form_squad(w: SimWorld, fid: int, formation: String, loadout: String = "") -> int:
	if not is_human_a(w, fid):
		return -1
	if not stage_ok(w, fid):
		return -1
	if not FORMATIONS.has(formation):
		return -1
	var forms: Dictionary = _rules().get("formations", {})
	var row: Dictionary = forms.get(formation, {})
	if row.is_empty():
		return -1
	var allowed: Array = row.get("loadouts", LOADOUTS)
	var lo := loadout
	if lo == "":
		lo = String(allowed[0]) if not allowed.is_empty() else "interceptor"
	if formation == "ward_pair":
		lo = "ward"
	elif not allowed.has(lo):
		return -1
	if not weaker_than_death(lo):
		return -1
	var st := _st(w)
	var size := int(row.get("size", 4))
	var roles: Array = row.get("roles", [])
	var sid := int(st.next_id)
	st.next_id = sid + 1
	var ops: Array = []
	var lo_row := loadout_stats(lo)
	var def_id := String(lo_row.get("def", "a_cg_intercept"))
	for i in size:
		var oid := sid * 100 + i + 1
		var role := String(roles[i]) if i < roles.size() else "specialist"
		var op_def := def_id
		if formation == "ward_pair":
			op_def = "a_cg_ward_prime" if role == "prime" else "a_cg_ward_shadow"
		var op := {
			"id": oid,
			"squad": sid,
			"fid": fid,
			"role": role,
			"loadout": lo,
			"def": op_def,
			"specialty": "",
			"peel_on_hunt": bool(lo_row.get("peel_on_hunt", true)) if lo != "ward" else false,
		}
		ops.append(op)
		st.ops[str(oid)] = op
	var squad := {
		"id": sid,
		"fid": fid,
		"formation": formation,
		"loadout": lo,
		"roles": roles.duplicate(),
		"ops": ops.map(func(o): return int(o.id)),
		"legend": false,
		"vip_id": -1,
		"intent": "",
	}
	st.squads[str(sid)] = squad
	w.emit("CgSquadFormed", {"fid": fid, "squad": sid, "formation": formation, "loadout": lo})
	return sid


static func mark_legend(w: SimWorld, squad_id: int, on: bool = true) -> String:
	var st := _st(w)
	var s: Dictionary = st.squads.get(str(squad_id), {})
	if s.is_empty():
		return "Unknown squad."
	s.legend = on
	return ""


static func assign_specialty(w: SimWorld, operator_id: int, specialty: String) -> String:
	var core: Array = _rules().get("specialties_core", [])
	var sig: Array = _rules().get("specialties_signature", [])
	if not core.has(specialty) and not sig.has(specialty):
		return "Unknown specialty."
	var st := _st(w)
	var o: Dictionary = st.ops.get(str(operator_id), {})
	if o.is_empty():
		return "Unknown operator."
	o.specialty = specialty
	return ""


static func squad_state(w: SimWorld, squad_id: int) -> Dictionary:
	var s: Dictionary = _st(w).squads.get(str(squad_id), {})
	return s.duplicate(true) if not s.is_empty() else {}


static func operator_state(w: SimWorld, operator_id: int) -> Dictionary:
	var o: Dictionary = _st(w).ops.get(str(operator_id), {})
	return o.duplicate(true) if not o.is_empty() else {}


static func intents() -> Array:
	return INTENTS.duplicate()


static func validate_intent(w: SimWorld, fid: int, squad_id: int, intent: String) -> String:
	if not INTENTS.has(intent):
		return "Unknown intent."
	if not is_human_a(w, fid) or not stage_ok(w, fid):
		return "Human A Stage 10 Counter-Ghost only."
	var s := squad_state(w, squad_id)
	if s.is_empty() or int(s.get("fid", -1)) != fid:
		return "Unknown squad."
	# Ward pairs never peel on hunt intents.
	if intent == "cg_hunt_ghosts" and String(s.get("formation", "")) == "ward_pair":
		return "Ward detail does not peel for hunts."
	if intent == "cg_hunt_ghosts":
		for oid in s.get("ops", []):
			var o := operator_state(w, int(oid))
			if o.get("peel_on_hunt") == false and String(o.get("loadout", "")) == "ward":
				return "Wards do not peel for hunts."
	return ""


static func assign_intent(w: SimWorld, fid: int, squad_id: int, intent: String) -> String:
	var err := validate_intent(w, fid, squad_id, intent)
	if err != "":
		return err
	var st := _st(w)
	var s: Dictionary = st.squads[str(squad_id)]
	s.intent = intent
	w.emit("CgIntent", {"fid": fid, "squad": squad_id, "intent": intent})
	return ""


static func bind_vip(w: SimWorld, squad_id: int, vip_id: int) -> String:
	var st := _st(w)
	var s: Dictionary = st.squads.get(str(squad_id), {})
	if s.is_empty():
		return "Unknown squad."
	if String(s.get("formation", "")) != "ward_pair" and String(s.get("loadout", "")) != "ward":
		return "Only Ward details escort VIPs."
	s.vip_id = vip_id
	return ""


## Sweep: raise GhostExo10 observer counters (thermal/sensor/dog/tracker).
static func cg_sweep(w: SimWorld, fid: int, kinds: Array = []) -> String:
	if not is_human_a(w, fid) or not stage_ok(w, fid):
		return "Human A Stage 10 only."
	var sweep: Dictionary = _rules().get("sweep", {})
	var use: Array = kinds if not kinds.is_empty() else sweep.keys()
	for k in use:
		var key := String(k)
		if not sweep.has(key):
			continue
		GhostExo10.set_counter(w, fid, key, true)
	var st := _st(w)
	st["last_sweep"] = {"fid": fid, "kinds": use.duplicate(), "tick": w.tick}
	w.emit("CgSweep", {"fid": fid, "kinds": use})
	return ""


static func cg_intercept(w: SimWorld, fid: int, ghost_op_id: int, squad_id: int = -1) -> String:
	if not is_human_a(w, fid) or not stage_ok(w, fid):
		return "Human A Stage 10 only."
	var go := GhostExo10.operator_state(w, ghost_op_id)
	if go.is_empty():
		return "Unknown ghost operator."
	var st := _st(w)
	var oid := int(st.next_op)
	st.next_op = oid + 1
	st.ops_live[str(oid)] = {
		"id": oid,
		"type": "intercept",
		"fid": fid,
		"ghost_op": ghost_op_id,
		"squad": squad_id,
		"tick": w.tick,
		"done": false,
	}
	w.emit("CgIntercept", {"fid": fid, "ghost_op": ghost_op_id, "op": oid})
	return ""


static func cg_disable(w: SimWorld, fid: int, ghost_op_id: int, mode: String = "emp") -> String:
	if not is_human_a(w, fid) or not stage_ok(w, fid):
		return "Human A Stage 10 only."
	var disable: Dictionary = _rules().get("disable", {})
	if not disable.has(mode):
		return "Unknown disable mode."
	var go := GhostExo10.operator_state(w, ghost_op_id)
	if go.is_empty():
		return "Unknown ghost operator."
	var row: Dictionary = disable[mode]
	var ticks := int(row.get("ticks", 3))
	# Honor Ghost disable_mult (hardened joints shorten but never cancel).
	var mult := float(go.get("disable_mult", 1.0))
	ticks = maxi(1, int(ceil(float(ticks) * mult)))
	GhostExo10.apply_wound(w, ghost_op_id, mode, true)
	var st := _st(w)
	st.ops_live[str(st.next_op)] = {
		"id": int(st.next_op),
		"type": "disable",
		"fid": fid,
		"ghost_op": ghost_op_id,
		"mode": mode,
		"until": w.tick + ticks,
		"done": false,
	}
	st.next_op = int(st.next_op) + 1
	w.emit("CgDisable", {"fid": fid, "ghost_op": ghost_op_id, "mode": mode, "ticks": ticks})
	return ""


static func cg_strip_killswitch(w: SimWorld, fid: int, ghost_op_id: int, engineer_id: int, under_fire: bool = false) -> String:
	if not is_human_a(w, fid) or not stage_ok(w, fid):
		return "Human A Stage 10 only."
	var go := GhostExo10.operator_state(w, ghost_op_id)
	if go.is_empty():
		return "Unknown ghost operator."
	var eng = w.entities.get(engineer_id)
	# Allow abstract engineer id (ops table) when no world entity.
	var ok_eng := eng != null and int(eng.get("owner", -1)) == fid
	var oeng := operator_state(w, engineer_id)
	if not ok_eng and oeng.is_empty():
		return "Need engineer."
	var strip: Dictionary = _rules().get("strip", {})
	var ticks := int(strip.get("ticks", 6))
	if under_fire:
		ticks = int(ceil(float(ticks) * float(strip.get("under_fire_mult", 1.5))))
	var late := int(strip.get("late_window", 10))
	var st := _st(w)
	var sid := int(st.next_strip)
	st.next_strip = sid + 1
	st.strips[str(sid)] = {
		"id": sid,
		"fid": fid,
		"ghost_op": ghost_op_id,
		"engineer": engineer_id,
		"start": w.tick,
		"end": w.tick + ticks,
		"late_deadline": w.tick + ticks + late,
		"under_fire": under_fire,
		"done": false,
		"failed": false,
		"feeds": String(strip.get("feeds", "counter_ghost_track")),
	}
	w.emit("CgStripStarted", {"fid": fid, "strip": sid, "ghost_op": ghost_op_id})
	return ""


static func cg_recover_suit(w: SimWorld, fid: int, ghost_op_id: int, contested: bool = false) -> String:
	if not is_human_a(w, fid) or not stage_ok(w, fid):
		return "Human A Stage 10 only."
	var go := GhostExo10.operator_state(w, ghost_op_id)
	if go.is_empty():
		return "Unknown ghost operator."
	var rec: Dictionary = _rules().get("recovery", {})
	var ticks := int(rec.get("race_ticks", 8))
	var st := _st(w)
	var rid := int(st.next_recover)
	st.next_recover = rid + 1
	st.recoveries[str(rid)] = {
		"id": rid,
		"fid": fid,
		"ghost_op": ghost_op_id,
		"start": w.tick,
		"end": w.tick + ticks,
		"contested": contested,
		"done": false,
		"lost": false,
		"feeds": String(rec.get("feeds", "counter_ghost_track")),
		"not_research9": bool(rec.get("not_research9", true)),
		"not_coalition_tech": bool(rec.get("not_coalition_tech", true)),
	}
	w.emit("CgRecoverStarted", {"fid": fid, "recover": rid, "ghost_op": ghost_op_id})
	return ""


static func cg_break_contact(w: SimWorld, fid: int, squad_id: int) -> String:
	var err := validate_intent(w, fid, squad_id, "cg_break_contact")
	if err != "":
		return err
	var st := _st(w)
	var s: Dictionary = st.squads[str(squad_id)]
	s.intent = "cg_break_contact"
	w.emit("CgBreakContact", {"fid": fid, "squad": squad_id})
	return ""


static func track_feed(w: SimWorld, fid: int) -> Dictionary:
	var st := _st(w)
	var t: Dictionary = st.tracks.get(str(fid), {})
	if t.is_empty():
		t = {"suits": 0, "strips": 0, "source": "counter_ghost_track", "research9": false, "coalition_tech": false}
		st.tracks[str(fid)] = t
	return t


static func _feed_track(w: SimWorld, fid: int, kind: String) -> void:
	var t := track_feed(w, fid)
	if kind == "strip":
		t.strips = int(t.get("strips", 0)) + 1
	elif kind == "suit":
		t.suits = int(t.get("suits", 0)) + 1
	t.research9 = false
	t.coalition_tech = false
	t.source = "counter_ghost_track"


## Focused scenario: detect → intercept → disable → strip → recover.
static func start_scenario(w: SimWorld, fid: int, ghost_op_id: int, engineer_id: int = 1) -> int:
	if not is_human_a(w, fid):
		return -1
	var st := _st(w)
	var sid := int(st.next_scenario)
	st.next_scenario = sid + 1
	st.scenarios[str(sid)] = {
		"id": sid,
		"fid": fid,
		"ghost_op": ghost_op_id,
		"engineer": engineer_id,
		"phase": "detect",
		"history": [],
		"failed": false,
		"fail_reason": "",
		"done": false,
		"success": false,
	}
	return sid


static func scenario(w: SimWorld, scenario_id: int) -> Dictionary:
	var s: Dictionary = _st(w).scenarios.get(str(scenario_id), {})
	return s.duplicate(true) if not s.is_empty() else {}


static func advance_scenario(w: SimWorld, scenario_id: int, opts: Dictionary = {}) -> Dictionary:
	var st := _st(w)
	var s: Dictionary = st.scenarios.get(str(scenario_id), {})
	if s.is_empty() or bool(s.get("done", false)):
		return scenario(w, scenario_id)
	var fid := int(s.fid)
	var ghost_op := int(s.ghost_op)
	var eng := int(s.get("engineer", 1))
	var phase := String(s.phase)
	match phase:
		"detect":
			cg_sweep(w, fid)
			s.history.append("detect")
			s.phase = "intercept"
		"intercept":
			cg_intercept(w, fid, ghost_op)
			s.history.append("intercept")
			s.phase = "disable"
		"disable":
			cg_disable(w, fid, ghost_op, String(opts.get("disable_mode", "emp")))
			s.history.append("disable")
			s.phase = "strip"
		"strip":
			if bool(opts.get("late_strip", false)):
				s.failed = true
				s.fail_reason = "late_strip"
				s.done = true
				s.history.append("strip_fail")
			else:
				cg_strip_killswitch(w, fid, ghost_op, eng, bool(opts.get("under_fire", false)))
				# Complete strip immediately for scenario pacing (tick advances separately).
				_complete_open_strips(w, true)
				s.history.append("strip")
				s.phase = "recover"
		"recover":
			if bool(opts.get("lose_race", false)):
				cg_recover_suit(w, fid, ghost_op, true)
				_fail_open_recoveries(w)
				s.failed = true
				s.fail_reason = "lost_recovery_race"
				s.done = true
				s.history.append("recover_fail")
			else:
				cg_recover_suit(w, fid, ghost_op, false)
				_complete_open_recoveries(w, true)
				s.history.append("recover")
				s.phase = "recover"
				s.done = true
				s.success = true
	return scenario(w, scenario_id)


static func run_scenario(w: SimWorld, fid: int, ghost_op_id: int, engineer_id: int = 1, opts: Dictionary = {}) -> Dictionary:
	var sid := start_scenario(w, fid, ghost_op_id, engineer_id)
	if sid < 0:
		return {}
	for _i in 8:
		var sc := advance_scenario(w, sid, opts)
		if bool(sc.get("done", false)):
			return sc
	return scenario(w, sid)


static func spider_clear(w: SimWorld, fid: int, bot_id: int, mode: String, target: String = "spider") -> String:
	if not is_human_a(w, fid):
		return "Human A only."
	if not SPIDER_MODES.has(mode):
		return "Unknown spider-killer mode."
	var bot = w.entities.get(bot_id)
	var def_id := ""
	if bot != null:
		def_id = String(bot.get("def", ""))
		if int(bot.get("owner", -1)) != fid:
			return "Not your bot."
	else:
		def_id = String(_rules().get("spider_killer", {}).get("def", "a_cg_spider_killer"))
	var d := Content.unit(def_id)
	if not bool(d.get("spider_killer", false)) and def_id != String(_rules().get("spider_killer", {}).get("def", "")):
		return "Need spider-killer bot."
	if bool(d.get("no_coalition_camo", true)) == false:
		return "Bot must not receive Coalition camo."
	var sk: Dictionary = _rules().get("spider_killer", {})
	if bool(sk.get("no_reaper", true)) and mode == "reaper":
		return "No Reaper tech."
	if bool(sk.get("no_suit_tech", true)) and mode == "suit_tech":
		return "No suit tech."
	var st := _st(w)
	var key := "%d:%s" % [fid, target]
	st.spiders[key] = {
		"fid": fid,
		"bot": bot_id,
		"mode": mode,
		"target": target,
		"cleared": true,
		"tick": w.tick,
	}
	w.emit("CgSpiderClear", {"fid": fid, "mode": mode, "target": target})
	return ""


static func spider_cleared(w: SimWorld, fid: int, target: String = "spider") -> bool:
	var st := _st(w)
	var row: Dictionary = st.spiders.get("%d:%s" % [fid, target], {})
	return bool(row.get("cleared", false))


static func apply_foam(w: SimWorld, target_kind: String, hardened_joints: bool = false) -> Dictionary:
	var foam: Dictionary = _rules().get("foam", {})
	var dur := 1.0
	if target_kind == "exo":
		dur = float(foam.get("exo_duration_mult", 0.5)) if hardened_joints and bool(foam.get("exo_mitigated_by_hardened_joints", true)) \
			else 1.0
		# Even with hardened joints: shortened, never immune.
		if hardened_joints:
			dur = float(foam.get("exo_duration_mult", 0.5))
	elif target_kind == "drone":
		dur = float(foam.get("drone_duration_mult", 1.0))
	return {
		"duration_mult": dur,
		"immune": false,
		"mitigated": target_kind == "exo" and hardened_joints,
	}


static func counter_to_ghost(threat: String) -> String:
	var m: Dictionary = _rules().get("counters_to_ghost", {})
	return String(m.get(threat, ""))


static func _complete_open_strips(w: SimWorld, force: bool = false) -> void:
	var st := _st(w)
	for k in st.strips.keys():
		var row: Dictionary = st.strips[k]
		if bool(row.get("done", false)) or bool(row.get("failed", false)):
			continue
		if force or w.tick >= int(row.get("end", 0)):
			if not force and w.tick > int(row.get("late_deadline", 0)):
				row.failed = true
				row.done = true
				continue
			row.done = true
			_feed_track(w, int(row.fid), "strip")
			w.emit("CgStripDone", {"fid": int(row.fid), "strip": int(row.id)})


static func _complete_open_recoveries(w: SimWorld, force: bool = false) -> void:
	var st := _st(w)
	for k in st.recoveries.keys():
		var row: Dictionary = st.recoveries[k]
		if bool(row.get("done", false)) or bool(row.get("lost", false)):
			continue
		if force or w.tick >= int(row.get("end", 0)):
			if bool(row.get("contested", false)) and not force:
				row.lost = true
				row.done = true
				continue
			row.done = true
			_feed_track(w, int(row.fid), "suit")
			w.emit("CgRecoverDone", {"fid": int(row.fid), "recover": int(row.id)})


static func _fail_open_recoveries(w: SimWorld) -> void:
	var st := _st(w)
	for k in st.recoveries.keys():
		var row: Dictionary = st.recoveries[k]
		if bool(row.get("done", false)):
			continue
		row.lost = true
		row.done = true


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	_complete_open_strips(w, false)
	_complete_open_recoveries(w, false)


static func board(w: SimWorld, fid: int = -1) -> Dictionary:
	if not active(w):
		return {}
	var st := _st(w)
	var out := {
		"squads": (st.squads as Dictionary).size(),
		"strips": (st.strips as Dictionary).size(),
		"recoveries": (st.recoveries as Dictionary).size(),
		"scenarios": (st.scenarios as Dictionary).size(),
		"vehicle_homes": (_rules().get("vehicle_homes", {}) as Dictionary).size(),
		"intents": intents(),
	}
	if fid >= 0:
		out["track"] = track_feed(w, fid)
	return out
