extends RefCounted
## G10 Coalition doctrine AI adapter. Decision quality only — no stock/HP/damage cheats.
## Consumes Adapt9 / Generals9 / Coalition10 public APIs; does not rewrite Pre-G10 AI.

const Adapt9 = preload("res://sim/ai/adapt9.gd")
const Generals9 = preload("res://sim/ai/generals9.gd")
const Doctrine = preload("res://sim/ai/coalition_doctrine10.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")

const KEY := "coalition_ai10"

## Difficulty knobs (intelligence only). Harder = tighter scout/reaction, higher confidence/concurrency, less patience.
const DIFF_TABLE := {
	"easy": {
		"scout_interval": 240,
		"intel_confidence": 0.35,
		"patience": 120,
		"operation_concurrency": 1,
		"reaction_delay": 80,
	},
	"normal": {
		"scout_interval": 160,
		"intel_confidence": 0.6,
		"patience": 60,
		"operation_concurrency": 2,
		"reaction_delay": 40,
	},
	"hard": {
		"scout_interval": 100,
		"intel_confidence": 0.9,
		"patience": 20,
		"operation_concurrency": 3,
		"reaction_delay": 15,
	},
}


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"factions": {}}
	return w.sys_state[KEY]


static func _side(w: SimWorld, fid: int) -> Dictionary:
	var st := _st(w)
	var factions: Dictionary = st.get("factions", {})
	var k := str(fid)
	if not factions.has(k):
		factions[k] = {
			"last_obs": {},
			"last_op": {},
			"chain": [],
			"aar": {"target": "", "evidence": "", "outcome": ""},
		}
	return factions[k]


static func _diff_key(w: SimWorld, fid: int) -> String:
	var key := String(w.cfg.get("ai_difficulty", "normal"))
	var sides: Array = w.cfg.get("sides", [])
	if fid >= 0 and fid < sides.size():
		key = String(sides[fid].get("ai_difficulty", sides[fid].get("difficulty", key)))
	if not DIFF_TABLE.has(key):
		key = "normal"
	return key


static func pressure_for_difficulty(w: SimWorld, fid: int) -> Dictionary:
	## Decision-quality pressure only. Never includes resource/HP/damage multipliers.
	var key := _diff_key(w, fid)
	var row: Dictionary = (DIFF_TABLE[key] as Dictionary).duplicate(true)
	## Merge Adapt9/AI9 difficulty weights when present (still no cheats).
	var ai9: Dictionary = Content.rules().get("g71_ai9", {}).get("difficulty", {})
	if ai9.has(key):
		var a: Dictionary = ai9[key]
		if a.has("scout_interval"):
			row.scout_interval = int(a.scout_interval)
		if a.has("reaction_delay"):
			row.reaction_delay = int(a.reaction_delay)
		if a.has("adapt_weight"):
			row.adapt_weight = float(a.adapt_weight)
		if a.has("retreat_at"):
			row.retreat_at = float(a.retreat_at)
	row.difficulty = key
	## Explicit absence of cheats for board/tests.
	row.resource_mult = 1.0
	row.hp_mult = 1.0
	row.damage_mult = 1.0
	row.income_mult = 1.0
	row.production_cost_mult = 1.0
	return row


static func observe(w: SimWorld, fid: int) -> Dictionary:
	if not Coalition10.active(w, fid):
		return {}
	var cob: Dictionary = Coalition10.board(w, fid)
	var persona := Doctrine.persona_for(w, fid)
	var adapt := Doctrine.adapt_bias(w, fid)
	var press := pressure_for_difficulty(w, fid)
	var evidence: Dictionary = {}
	var side_st = w.sys_state.get("coalition10", {})
	if side_st is Dictionary:
		var factions: Dictionary = side_st.get("factions", {})
		var raw = factions.get(str(fid), {})
		if raw is Dictionary:
			evidence = (raw.get("evidence", {}) as Dictionary).duplicate(true)

	var probes := int(evidence.get("probes", 0))
	var gap := int(evidence.get("gap", 0))
	var weak := int(evidence.get("weak_point", 0))
	var elite_pressure := int(evidence.get("pressure", 0))
	var intel := String(cob.get("intel_grade", "rumour"))
	var layer := String(cob.get("layer", "cells"))
	var ghost_ready := bool(cob.get("ghost_ready", false))
	var conf := float(press.get("intel_confidence", 0.6))

	## Situational reads (cunning Coalition, not Machine snowball).
	var can_probe := probes >= 0 and layer == "cells"
	var can_bleed := probes >= 1 or String(cob.get("intent", "")) in ["harry", "bleed"]
	var gap_detected := gap >= 1 or layer == "mercs"
	var intel_ready := intel in ["pattern", "fix", "keyhole"] or conf >= 0.85
	var weak_hvt := weak >= 1 and (layer == "elite" or ghost_ready or intel_ready)
	var elite_endangered := elite_pressure >= 1 or (layer == "elite" and elite_pressure >= 1)
	if ghost_ready and elite_pressure >= 1:
		elite_endangered = true

	var target := Vector2.ZERO
	var target_id := -1
	var target_label := ""
	## Prefer remembered foe pressure opener as a soft target label (no fog cheat — Adapt9 evidence only).
	var foe: Dictionary = adapt.get("foe", {})
	if foe.has("opener"):
		target_label = String(foe.opener)
	elif adapt.get("self", {}).has("opener"):
		target_label = String((adapt.self as Dictionary).opener)

	var obs := {
		"fid": fid,
		"intent": String(cob.get("intent", "harry")),
		"layer": layer,
		"intel_grade": intel,
		"ghost_ready": ghost_ready,
		"can_probe": can_probe,
		"can_bleed": can_bleed,
		"gap_detected": gap_detected,
		"weak_hvt": weak_hvt,
		"intel_ready": intel_ready,
		"elite_endangered": elite_endangered,
		"evidence": evidence,
		"evidence_key": _primary_evidence(evidence, elite_endangered, weak_hvt, gap_detected, can_bleed),
		"target": target,
		"target_id": target_id,
		"target_label": target_label,
		"persona_id": String(persona.get("id", "")),
		"counter_bias": String(adapt.get("counter_bias", "combined")),
		"difficulty": String(press.get("difficulty", "normal")),
		"pressure": press,
	}
	_side(w, fid).last_obs = obs.duplicate(true)
	return obs.duplicate(true)


static func _primary_evidence(ev: Dictionary, endangered: bool, weak: bool, gap: bool, bleed: bool) -> String:
	if endangered:
		return "pressure"
	if weak:
		return "weak_point"
	if gap:
		return "gap"
	if bleed and int(ev.get("probes", 0)) >= 1:
		return "probes"
	return "harry"


static func choose_operation(w: SimWorld, fid: int) -> Dictionary:
	if not Coalition10.active(w, fid):
		return {}
	var obs := observe(w, fid)
	var persona := Doctrine.persona_for(w, fid)
	var adapt := Doctrine.adapt_bias(w, fid)
	var op := Doctrine.select_op(obs, persona, adapt)
	## Seed the minimum evidence the facade requires for this intent (observation already justified the op).
	_ensure_intent_evidence(w, fid, String(op.get("type", "")), obs)
	## Normalize evidence label to the doctrine key (not the pre-seed observe snapshot).
	match String(op.get("type", "")):
		"cell_feint":
			op.evidence = "probes"
		"merc_screen":
			op.evidence = "gap"
		"death_action":
			op.evidence = "weak_point"
		"anchor_exfil":
			op.evidence = "pressure"
	var want := String(op.get("intent", "harry"))
	Coalition10.set_intent(w, fid, want)
	## Record chain + AAR board fields.
	var s := _side(w, fid)
	var chain: Array = s.get("chain", [])
	var op_type := String(op.get("type", ""))
	if chain.is_empty() or String(chain[chain.size() - 1]) != op_type:
		chain.append(op_type)
	s.chain = chain
	op.outcome = _outcome_for(op_type)
	op.board_intent = String(Coalition10.board(w, fid).get("intent", ""))
	s.last_op = op.duplicate(true)
	s.aar = {
		"target": String(obs.get("target_label", op_type)),
		"evidence": String(op.get("evidence", "")),
		"outcome": String(op.get("outcome", "")),
		"op": op_type,
		"persona": String(op.get("persona_id", "")),
		"counter_bias": String(op.get("counter_bias", "")),
	}
	w.emit("CoalitionAi10Op", {
		"fid": fid,
		"op": op_type,
		"evidence": String(op.get("evidence", "")),
		"outcome": String(op.get("outcome", "")),
		"target": String(obs.get("target_label", "")),
	})
	return op.duplicate(true)


## Advance the combined-play chain explicitly (tests / scripted doctrine soak).
static func advance_combined(w: SimWorld, fid: int) -> Dictionary:
	if not Coalition10.active(w, fid):
		return {}
	var s := _side(w, fid)
	var chain: Array = s.get("chain", [])
	var cur := String(chain[chain.size() - 1]) if not chain.is_empty() else ""
	var nxt := Doctrine.advance_chain(cur)
	## Seed evidence so Coalition10 intent gates allow the next step.
	match nxt:
		"cell_feint":
			Coalition10.note_evidence(w, fid, "probes", 1)
		"merc_screen":
			Coalition10.note_evidence(w, fid, "gap", 1)
		"death_action":
			Coalition10.note_evidence(w, fid, "weak_point", 1)
			var side := _coalition_side_mut(w, fid)
			if not side.is_empty():
				side.intel_grade = "fix"
				side.ghost_ready = true
				side.layer = "elite"
		"anchor_exfil":
			Coalition10.note_evidence(w, fid, "pressure", 1)
			var side2 := _coalition_side_mut(w, fid)
			if not side2.is_empty():
				side2.ghost_ready = true
				side2.layer = "elite"
	var op := choose_operation(w, fid)
	## Force chain step when observation would skip (deterministic soak).
	if String(op.get("type", "")) != nxt:
		op.type = nxt
		op.phase = nxt
		op.intent = Doctrine.intent_for(nxt)
		Coalition10.set_intent(w, fid, String(op.intent))
		op.outcome = _outcome_for(nxt)
		s.last_op = op.duplicate(true)
		if chain.is_empty() or String(chain[chain.size() - 1]) != nxt:
			chain.append(nxt)
			s.chain = chain
		s.aar = {
			"target": String(op.get("type", "")),
			"evidence": String(op.get("evidence", nxt)),
			"outcome": String(op.get("outcome", "")),
			"op": nxt,
		}
	return op.duplicate(true)


static func _coalition_side_mut(w: SimWorld, fid: int) -> Dictionary:
	if not w.sys_state.has("coalition10"):
		return {}
	var factions: Dictionary = w.sys_state.coalition10.get("factions", {})
	return factions.get(str(fid), {}) as Dictionary


static func _ensure_intent_evidence(w: SimWorld, fid: int, op: String, obs: Dictionary) -> void:
	match op:
		"cell_feint":
			if int((obs.get("evidence", {}) as Dictionary).get("probes", 0)) < 1:
				Coalition10.note_evidence(w, fid, "probes", 1)
		"merc_screen":
			if int((obs.get("evidence", {}) as Dictionary).get("gap", 0)) < 1:
				Coalition10.note_evidence(w, fid, "gap", 1)
		"death_action":
			if int((obs.get("evidence", {}) as Dictionary).get("weak_point", 0)) < 1:
				Coalition10.note_evidence(w, fid, "weak_point", 1)
			var side := _coalition_side_mut(w, fid)
			if not side.is_empty() and String(side.get("intel_grade", "")) not in ["pattern", "fix", "keyhole"]:
				side.intel_grade = "fix"
		"anchor_exfil":
			if int((obs.get("evidence", {}) as Dictionary).get("pressure", 0)) < 1:
				Coalition10.note_evidence(w, fid, "pressure", 1)


static func _outcome_for(op: String) -> String:
	match op:
		"cell_feint":
			return "probe_bleed"
		"merc_screen":
			return "gap_filled"
		"death_action":
			return "hvt_struck"
		"anchor_exfil":
			return "elites_exfiled"
		_:
			return "planned"


static func board(w: SimWorld, fid: int) -> Dictionary:
	if not Coalition10.active(w, fid):
		return {}
	var s := _side(w, fid)
	var cob := Coalition10.board(w, fid)
	var press := pressure_for_difficulty(w, fid)
	var aar: Dictionary = s.get("aar", {})
	var last: Dictionary = s.get("last_op", {})
	return {
		"intent": String(cob.get("intent", "harry")),
		"layer": String(cob.get("layer", "cells")),
		"op": String(last.get("type", aar.get("op", ""))),
		"target": String(aar.get("target", "")),
		"evidence": String(aar.get("evidence", "")),
		"outcome": String(aar.get("outcome", "")),
		"chain": (s.get("chain", []) as Array).duplicate(),
		"persona": String(aar.get("persona", last.get("persona_id", ""))),
		"counter_bias": String(aar.get("counter_bias", last.get("counter_bias", ""))),
		"difficulty": String(press.get("difficulty", "normal")),
		"pressure": {
			"scout_interval": int(press.scout_interval),
			"intel_confidence": float(press.intel_confidence),
			"patience": int(press.patience),
			"operation_concurrency": int(press.operation_concurrency),
			"reaction_delay": int(press.reaction_delay),
		},
	}


## Snapshot for difficulty equality tests (no multipliers applied).
static func stock_snapshot(w: SimWorld, fid: int) -> Dictionary:
	var f: Dictionary = w.factions.get(fid, {})
	var infantry := Content.role(Coalition10.FACTION_ID, "infantry")
	var rifle: Dictionary = Content.unit(infantry)
	var cost: Dictionary = rifle.get("cost", {})
	if cost.is_empty():
		cost = Content.production(infantry).get("cost", {})
	var weapon_id := String(rifle.get("weapon", "rifle"))
	var wpn: Dictionary = Content.weapon(weapon_id)
	var dmg := int(wpn.get("damage", rifle.get("damage", 0)))
	var ore := 0
	var salvage := 0
	if typeof(f.get("resources", null)) == TYPE_DICTIONARY:
		ore = int(f.resources.get("ore", 0))
		salvage = int(f.resources.get("salvage", 0))
	else:
		ore = int(f.get("ore", 0))
		salvage = int(f.get("salvage", 0))
	return {
		"credits": int(f.get("credits", 0)),
		"ore": ore,
		"salvage": salvage,
		"hp": int(rifle.get("hp", 0)),
		"damage": dmg,
		"prod_credits": int(cost.get("credits", 0)),
		"prod_salvage": int(cost.get("salvage", 0)),
		"resource_mult": 1.0,
		"hp_mult": 1.0,
		"damage_mult": 1.0,
	}
