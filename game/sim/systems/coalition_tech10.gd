class_name CoalitionTech10
extends RefCounted
## G10 Shadow Coalition technology: buy / steal / unseal only. Denial gates for forbidden defs.
## Production/Market/Progression seams: call these public gates (ORCH wires world.gd). Do not use Research9.

const Coalition10 = preload("res://sim/systems/coalition10.gd")
const Production = preload("res://sim/systems/production.gd")
const Market = preload("res://sim/systems/market.gd")
const Research9 = preload("res://sim/systems/research9.gd")

const KEY := "coalition_tech10"
const FACTION_ID := "shadow_coalition"
const SOURCES := ["buy", "steal", "unseal"]
const RESEARCH_REJECT := "Coalition technology is bought, stolen or unsealed."


static func R() -> Dictionary:
	return Content.rules().get("coalition_tech10", {})


static func research_reject_message() -> String:
	return String(R().get("research_reject", RESEARCH_REJECT))


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"factions": {}}
	return w.sys_state[KEY]


static func _side(w: SimWorld, fid: int) -> Dictionary:
	var st := _st(w)
	var key := str(fid)
	var factions: Dictionary = st.get("factions", {})
	if not factions.has(key):
		factions[key] = {
			"unlocked": {},
			"log": [],
			"heat": 0,
			"alarm": 0,
			"evidence": {},
		}
		st.factions = factions
	return factions[key]


static func active(w: SimWorld, fid: int) -> bool:
	return Coalition10.active(w, fid)


static func unlocked(w: SimWorld, fid: int, tech_id: String) -> bool:
	if not active(w, fid):
		return false
	return (_side(w, fid).unlocked as Dictionary).has(tech_id)


static func source_log(w: SimWorld, fid: int) -> Array:
	if not active(w, fid):
		return []
	return (_side(w, fid).get("log", []) as Array).duplicate(true)


static func note_evidence(w: SimWorld, fid: int, key: String, amount: int = 1) -> void:
	if not active(w, fid):
		return
	var s := _side(w, fid)
	var ev: Dictionary = s.get("evidence", {})
	ev[key] = int(ev.get(key, 0)) + maxi(amount, 1)
	s.evidence = ev


static func evidence_count(w: SimWorld, fid: int, key: String) -> int:
	if not active(w, fid):
		return 0
	return int((_side(w, fid).get("evidence", {}) as Dictionary).get(key, 0))


static func heat(w: SimWorld, fid: int) -> int:
	if not active(w, fid):
		return 0
	return int(_side(w, fid).get("heat", 0))


static func alarm(w: SimWorld, fid: int) -> int:
	if not active(w, fid):
		return 0
	return int(_side(w, fid).get("alarm", 0))


## Deny reason for a def id ("" = allowed). Checks deny tags, explicit defs, and CN markers.
static func forbidden_reason(def_id: String) -> String:
	var id := String(def_id)
	if id == "":
		return ""
	var rules := R()
	var forbidden_defs: Array = rules.get("forbidden_defs", [])
	if forbidden_defs.has(id):
		return "Forbidden Coalition tech: %s." % id
	var tags: Array = rules.get("forbidden_tags", [])
	var def := _resolve_def(id)
	if def.is_empty():
		# Unknown ids listed only by tag name still deny when the id itself is a forbidden tag token.
		if tags.has(id):
			return "Forbidden Coalition tag: %s." % id
		return ""
	var def_tags: Array = def.get("tags", [])
	for t in tags:
		if def_tags.has(t) or bool(def.get(String(t), false)):
			return "Forbidden Coalition tag: %s." % String(t)
	# Counter-nanite line markers (Human A CN kits never leak to Coalition).
	for marker in rules.get("cn_markers", []):
		if def.has(String(marker)):
			return "Forbidden Coalition tag: counter_nanite."
	var reqs: Array = def.get("requires_research", [])
	if reqs.has("g7_counter_nanite"):
		return "Forbidden Coalition tag: counter_nanite."
	var fac := String(def.get("faction", ""))
	if tags.has("human_a_only") and fac == "human_a" and (
		bool(def.get("human_a_only", false)) or def_tags.has("human_a_only")
	):
		return "Forbidden Coalition tag: human_a_only."
	return ""


static func _resolve_def(def_id: String) -> Dictionary:
	var u: Dictionary = Content.unit(def_id)
	if not u.is_empty():
		return u
	var b: Dictionary = Content.building(def_id)
	if not b.is_empty():
		return b
	var p: Dictionary = Content.production(def_id)
	if not p.is_empty():
		return p
	return {}


## Acquisition. Returns "" on success, else a reason. source ∈ buy|steal|unseal.
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if not active(w, int(cmd.issuer)):
		return "Technology acquisition is Coalition-only."
	var id := String(cmd.get("tech", ""))
	var source := String(cmd.get("source", ""))
	var row: Dictionary = R().get("techs", {}).get(id, {})
	return "" if source in row.get("sources", []) else "Choose a valid Coalition technology source."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var reason := acquire(w, int(cmd.issuer), String(cmd.source), String(cmd.tech))
	if reason != "":
		w.emit("CoalitionActionDenied", {"fid": int(cmd.issuer), "reason": reason})


static func acquire(w: SimWorld, fid: int, source: String, tech_id: String, evidence: Dictionary = {}) -> String:
	if not active(w, fid):
		return "Not a Coalition side."
	var src := String(source)
	if not SOURCES.has(src):
		return "Unknown tech source."
	var tid := String(tech_id)
	var techs: Dictionary = R().get("techs", {})
	var tech: Dictionary = techs.get(tid, {})
	if tech.is_empty():
		return "Unknown tech."
	if unlocked(w, fid, tid):
		return "Already unlocked."
	var allowed: Array = tech.get("sources", [])
	if not allowed.has(src):
		return "Tech %s cannot be acquired via %s." % [tid, src]
	var deny := forbidden_reason(tid)
	if deny != "":
		return deny
	match src:
		"buy":
			var why := _buy(w, fid, tid, tech)
			if why != "":
				return why
		"steal":
			var why_s := _steal(w, fid, tid, tech, evidence)
			if why_s != "":
				return why_s
		"unseal":
			var why_u := _unseal(w, fid, tid, tech)
			if why_u != "":
				return why_u
	_record(w, fid, src, tid, evidence)
	return ""


static func _buy(w: SimWorld, fid: int, _tech_id: String, tech: Dictionary) -> String:
	var cost: Dictionary = tech.get("cost", {})
	var afford := w.can_afford(fid, cost)
	if afford != "":
		return afford
	var favour_need := int(tech.get("favour", 0))
	if favour_need > 0:
		var favour := _patron_favour(w, fid)
		if favour < favour_need:
			return "Need %d more patron favour." % (favour_need - favour)
	# Exercise Market public quote API when a credit cost is present (price transparency).
	if int(cost.get("credits", 0)) > 0:
		Market.price(w, "salvage", "buy")
	if not w.spend(fid, cost, "coalition_tech:buy"):
		return "Cannot afford."
	if favour_need > 0:
		_spend_favour(w, fid, favour_need)
	return ""


static func _steal(w: SimWorld, fid: int, _tech_id: String, tech: Dictionary, evidence: Dictionary) -> String:
	var reqs: Array = tech.get("requires_evidence", [])
	if reqs.is_empty():
		reqs = ["captured_gear"]
	for key in reqs:
		var k := String(key)
		var have := evidence_count(w, fid, k) + int(evidence.get(k, 0))
		if have < 1:
			return "Steal requires %s evidence." % k
	# Consume one unit of each required evidence key from side state (evidence arg seeds first).
	for key2 in reqs:
		var k2 := String(key2)
		if int(evidence.get(k2, 0)) > 0:
			note_evidence(w, fid, k2, int(evidence.get(k2, 0)))
		var side_ev: Dictionary = _side(w, fid).get("evidence", {})
		var left := int(side_ev.get(k2, 0)) - 1
		if left <= 0:
			side_ev.erase(k2)
		else:
			side_ev[k2] = left
		_side(w, fid).evidence = side_ev
	return ""


static func _unseal(w: SimWorld, fid: int, _tech_id: String, tech: Dictionary) -> String:
	if bool(tech.get("requires_vault", true)) and not _has_controlled_vault(w, fid, String(tech.get("vault_def", "x_vault_core"))):
		return "Unseal requires a controlled vault core."
	var cost: Dictionary = tech.get("cost", {})
	var afford := w.can_afford(fid, cost)
	if afford != "":
		return afford
	if not cost.is_empty() and not w.spend(fid, cost, "coalition_tech:unseal"):
		return "Cannot afford."
	var s := _side(w, fid)
	s.heat = int(s.get("heat", 0)) + maxi(int(tech.get("heat_cost", 0)), 0)
	s.alarm = int(s.get("alarm", 0)) + maxi(int(tech.get("alarm_cost", 0)), 0)
	return ""


static func _has_controlled_vault(w: SimWorld, fid: int, vault_def: String) -> bool:
	for b in w.buildings_of(fid):
		if String(b.get("def", "")) != vault_def:
			continue
		if bool(b.get("built", false)):
			return true
	return false


static func _patron_favour(w: SimWorld, fid: int) -> int:
	var board: Dictionary = Coalition10.board(w, fid)
	return int(board.get("patron_favour", 0))


static func _spend_favour(w: SimWorld, fid: int, amount: int) -> void:
	if amount <= 0:
		return
	# Mirror into Coalition10 board state (IDENT10 schema: tech_sources / patron_favour).
	if not w.sys_state.has("coalition10"):
		Coalition10.board(w, fid)  # force lazy create when active
	var st: Dictionary = w.sys_state.get("coalition10", {})
	var factions: Dictionary = st.get("factions", {})
	var side: Dictionary = factions.get(str(fid), {})
	if side.is_empty():
		return
	side.patron_favour = maxi(int(side.get("patron_favour", 0)) - amount, 0)
	factions[str(fid)] = side
	st.factions = factions
	w.sys_state["coalition10"] = st


static func _set_patron_favour(w: SimWorld, fid: int, value: int) -> void:
	Coalition10.board(w, fid)
	if not w.sys_state.has("coalition10"):
		return
	var st: Dictionary = w.sys_state["coalition10"]
	var factions: Dictionary = st.get("factions", {})
	var side: Dictionary = factions.get(str(fid), {})
	if side.is_empty():
		return
	side.patron_favour = maxi(value, 0)
	factions[str(fid)] = side
	st.factions = factions
	w.sys_state["coalition10"] = st


## Test/helper: set favour without patron system (MECH10 owns patron10).
static func debug_set_favour(w: SimWorld, fid: int, value: int) -> void:
	if active(w, fid):
		_set_patron_favour(w, fid, value)


static func _record(w: SimWorld, fid: int, source: String, tech_id: String, evidence: Dictionary) -> void:
	var s := _side(w, fid)
	var unlocked_map: Dictionary = s.get("unlocked", {})
	unlocked_map[tech_id] = {"source": source, "tick": w.tick}
	s.unlocked = unlocked_map
	var entry := {
		"tech": tech_id,
		"source": source,
		"tick": w.tick,
		"evidence": evidence.duplicate(true),
	}
	var log: Array = s.get("log", [])
	log.append(entry)
	s.log = log
	_mirror_tech_sources(w, fid, entry)
	w.emit("CoalitionTech10Acquire", {"fid": fid, "tech": tech_id, "source": source})


static func _mirror_tech_sources(w: SimWorld, fid: int, entry: Dictionary) -> void:
	Coalition10.board(w, fid)
	if not w.sys_state.has("coalition10"):
		return
	var st: Dictionary = w.sys_state["coalition10"]
	var factions: Dictionary = st.get("factions", {})
	var side: Dictionary = factions.get(str(fid), {})
	if side.is_empty():
		return
	var sources: Array = side.get("tech_sources", [])
	sources.append(entry.duplicate(true))
	side.tech_sources = sources
	factions[str(fid)] = side
	st.factions = factions
	w.sys_state["coalition10"] = st


## Research command gate for Coalition. Human/Machine keep Progression/Research9.
static func validate_research(w: SimWorld, fid: int, _cmd: Dictionary = {}) -> String:
	if active(w, fid):
		return research_reject_message()
	return ""


## Path gates — production/market call these once ORCH wires; tests exercise now.
static func gate_build(w: SimWorld, fid: int, def_id: String) -> String:
	if not active(w, fid):
		return ""
	return forbidden_reason(def_id)


static func gate_queue(w: SimWorld, fid: int, item: String, building_id: int = -1) -> String:
	if not active(w, fid):
		return ""
	var deny := forbidden_reason(item)
	if deny != "":
		return deny
	# Call Production public validate when a building context is supplied.
	if building_id >= 0:
		var cmd := {"type": "queue_unit", "issuer": fid, "building_id": building_id, "item": item}
		var prod_why := Production.validate_command(w, cmd)
		if prod_why != "":
			return prod_why
	return ""


static func gate_market(w: SimWorld, fid: int, item: String) -> String:
	if not active(w, fid):
		return ""
	var deny := forbidden_reason(item)
	if deny != "":
		return deny
	# Exercise Market public validate for black-catalog items when listed.
	if Market.black_catalog().has(item):
		return Market.validate_command(w, {"type": "market_trade", "issuer": fid, "tier": "black", "item": item})
	return ""


static func gate_capture(w: SimWorld, fid: int, def_id: String) -> String:
	if not active(w, fid):
		return ""
	return forbidden_reason(def_id)


static func gate_editor_load(w: SimWorld, fid: int, def_id: String) -> String:
	if not active(w, fid):
		return ""
	return forbidden_reason(def_id)


static func gate_difficulty(w: SimWorld, fid: int, def_id: String) -> String:
	if not active(w, fid):
		return ""
	return forbidden_reason(def_id)


## Deny matrix for a path name (build/queue/market/capture/editor_load/difficulty).
static func deny(w: SimWorld, fid: int, path: String, def_id: String, extra: Dictionary = {}) -> String:
	var p := String(path)
	match p:
		"build":
			return gate_build(w, fid, def_id)
		"queue":
			return gate_queue(w, fid, def_id, int(extra.get("building_id", -1)))
		"market":
			return gate_market(w, fid, def_id)
		"capture":
			return gate_capture(w, fid, def_id)
		"editor_load":
			return gate_editor_load(w, fid, def_id)
		"difficulty":
			return gate_difficulty(w, fid, def_id)
		"research":
			return validate_research(w, fid, {"issuer": fid})
		_:
			return "Unknown deny path."


## Research9 remains for non-Coalition (public API passthrough used by tests).
static func research9_can_start(w: SimWorld, fid: int, tech: String) -> String:
	if active(w, fid):
		return research_reject_message()
	return Research9.can_start(w, fid, tech)


static func tick(_w: SimWorld) -> void:
	pass
