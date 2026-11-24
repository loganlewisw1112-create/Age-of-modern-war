extends RefCounted
## Named rival generals: deterministic selection and doctrine data shared by AI, UI and AAR.

const IDS := ["iron_wall", "storm_spear", "long_reach", "swarm_tide", "ghost_knife"]
const OP_PHASES := ["recon", "fix", "assault", "exploit"]


static func R() -> Dictionary:
	return Content.rules().get("g71_ai9", {}).get("personas", {})


static func pick(w: SimWorld, fid: int, prefer: String = "") -> String:
	if prefer != "" and R().has(prefer):
		return prefer
	var seed := int(w.cfg.get("seed", 0))
	return IDS[posmod(seed + fid * 17, IDS.size())]


static func doctrine(persona_id: String) -> Dictionary:
	return (R().get(persona_id, {}) as Dictionary).duplicate(true)


static func attach(w: SimWorld, fid: int, drive: Dictionary, prefer: String = "") -> String:
	var id := pick(w, fid, prefer)
	var d := doctrine(id)
	drive.persona_id = id
	drive.persona_name = String(d.get("name", id.capitalize()))
	drive.playstyle = String(d.get("playstyle", drive.get("playstyle", "combined")))
	drive.stance = String(d.get("stance", drive.get("stance", "balanced")))
	w.emit("AiGeneralNamed", {"fid": fid, "persona": id, "name": drive.persona_name,
		"priority": String(d.get("priority", ""))})
	return id


static func board(w: SimWorld) -> Dictionary:
	var out := {}
	var ai = w.sys_state.get("ai_cmd")
	if not (ai is Dictionary):
		return out
	for fid in (ai.get("egen", {}) as Dictionary):
		var d: Dictionary = ai.egen[fid]
		out[str(fid)] = {"id": String(d.get("persona_id", "")), "name": String(d.get("persona_name", "")),
			"playstyle": String(d.get("playstyle", "")), "stance": String(d.get("stance", ""))}
	return out


## Compact phase contract used by commander objectives and scripted tests.
static func advance_operation(w: SimWorld, fid: int, op: Dictionary) -> String:
	var i := OP_PHASES.find(String(op.get("phase", "")))
	i = 0 if i < 0 else mini(i + 1, OP_PHASES.size() - 1)
	op.phase = OP_PHASES[i]
	op.phase_tick = w.tick
	w.emit("AiGeneralOp", {"fid": fid, "slot": int(op.get("slot", -1)), "op": String(op.get("type", "attack")),
		"phase": String(op.phase), "target": op.get("target", Vector2.ZERO), "reason": "ai9_phase"})
	return String(op.phase)
