extends RefCounted
## G10 Coalition doctrine selector. Consumes Adapt9 pressure + Generals9 persona; never rewrites them.

const Adapt9 = preload("res://sim/ai/adapt9.gd")
const Generals9 = preload("res://sim/ai/generals9.gd")
const Coalition10 = preload("res://sim/systems/coalition10.gd")

## Combined play chain: cells probe → mercs screen → Death strike → Anchor exfil.
const OP_CHAIN := ["cell_feint", "merc_screen", "death_action", "anchor_exfil"]
const INTENT_FOR_OP := {
	"cell_feint": "bleed",
	"merc_screen": "flex",
	"death_action": "strike",
	"anchor_exfil": "exfil",
}


static func R() -> Dictionary:
	return Content.rules().get("g71_ai9", {})


static func persona_for(w: SimWorld, fid: int) -> Dictionary:
	var prefer := ""
	if w.factions.has(fid) and typeof(w.factions[fid]) == TYPE_DICTIONARY:
		prefer = String(w.factions[fid].get("persona_id", ""))
	var id := Generals9.pick(w, fid, prefer if prefer != "" else "ghost_knife")
	var d := Generals9.doctrine(id)
	d["id"] = id
	return d


static func adapt_bias(w: SimWorld, fid: int) -> Dictionary:
	## Counter choices come from this side’s battle losses and its own combat history.
	var self_p: Dictionary = Adapt9.pressure(w, fid)
	var foe_p := Adapt9.observed_pressure(w, fid)
	return {
		"self": self_p.duplicate(true),
		"foe": foe_p.duplicate(true),
		"counter_bias": String(foe_p.get("counter_bias", self_p.get("counter_bias", "combined"))),
		"kill_mix": (foe_p.get("kill_mix", self_p.get("kill_mix", {})) as Dictionary).duplicate(true),
	}


static func select_op(obs: Dictionary, persona: Dictionary, adapt: Dictionary) -> Dictionary:
	## Pick next doctrine op from observation flags. Prefer exfil when elites are endangered.
	if bool(obs.get("elite_endangered", false)):
		return _op("anchor_exfil", obs, persona, adapt, "elite_under_pressure")
	if bool(obs.get("weak_hvt", false)) and bool(obs.get("intel_ready", false)):
		return _op("death_action", obs, persona, adapt, "weak_high_value")
	if bool(obs.get("gap_detected", false)):
		return _op("merc_screen", obs, persona, adapt, "fill_gap")
	if bool(obs.get("can_probe", false)) or bool(obs.get("can_bleed", false)):
		return _op("cell_feint", obs, persona, adapt, "probe_bleed")
	## Default harry with cells when nothing special is seen.
	return _op("cell_feint", obs, persona, adapt, "default_harry")


static func advance_chain(current: String) -> String:
	var i := OP_CHAIN.find(String(current))
	if i < 0:
		return OP_CHAIN[0]
	return OP_CHAIN[mini(i + 1, OP_CHAIN.size() - 1)]


static func intent_for(op: String) -> String:
	return String(INTENT_FOR_OP.get(op, "harry"))


static func _op(op: String, obs: Dictionary, persona: Dictionary, adapt: Dictionary, reason: String) -> Dictionary:
	return {
		"type": op,
		"intent": intent_for(op),
		"phase": op,
		"target": obs.get("target", Vector2.ZERO),
		"target_id": int(obs.get("target_id", -1)),
		"evidence": String(obs.get("evidence_key", reason)),
		"reason": reason,
		"persona_id": String(persona.get("id", "")),
		"persona_priority": String(persona.get("priority", "")),
		"counter_bias": String(adapt.get("counter_bias", "combined")),
		"outcome": "planned",
	}
