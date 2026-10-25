extends RefCounted
## AiCommand (owner: AI7-CMD). CONTRACTS_G6 section 4, section 15, section 16 (D41).
## Player-side AI Commanders: up to 4 slots per human side. Each slot takes a formation (a company, an
## army, or a loose unit list) or a role (base_defence, air_ops, logistics, naval), a playstyle
## (defensive, aggressive, specops, combined), an objective (take | hold | raid | escort) and a stance
## (cautious, balanced, aggressive). Commanders ASSIST: they never order a unit within override_ticks
## (20 s) of the player's own command to it, and recall returns control at once.
## Commands: set_ai_commander {issuer, slot, target: {formation: id} | {role: id} | {units: [ids]},
##   playstyle, objective: {type, cell?, target_id?}, stance}; recall_ai_commander {issuer, slot};
##   ally_request {issuer, ally_fid, kind: attack | defend | air_support, cell?}.
##   formation id: int = company id; "co:N" = company N; "army:N" = army N (its companies + Commander).
## State w.sys_state.ai_cmd, created lazily by the first accepted command or by the wave AI (a match that
## never uses them is untouched, so every G5 hash stays equal):
##   {ver, slots: {fid: {slot: S}}, ally: {ally_fid: A}, wave: {fid: W}}
##   S = {slot, kind: formation|role, spec, role, playstyle, stance, objective {type, cell?, target_id},
##        since, doc (Doctrine.plan_for doc), sent {uid: [type, x, y, tick]}, units [ids], peak, mode,
##        mode_tick, next_think, tags {tag: n}, log [String]}
## Entity fields (saved, hashed; only on units an AI commander drives):
##   e.ai_cmd: String badge: "p<slot>" (player commander), "ally" (ally commitment), "wave" (wave AI).
##     The side's own AI holds these units (AI7-USE / AI7-DOC CRs).
##   e.player_order_tick: int, the tick a human side's own command last touched the unit (stamped by
##     on_applied, only for sides that have used AI commanders).
## Events: AiCommanderAssigned, AiCommanderRecalled, AllyRequest, AllyCommitted, AllyRefused,
##   AiDecision {fid, tag, unit_ids, reason} (through Doctrine.emit).

const Companies = preload("res://sim/systems/companies.gd")
const Commanders = preload("res://sim/ai/commanders.gd")
const AllyCmds = preload("res://sim/ai/ally_cmds.gd")
const WaveAI = preload("res://sim/ai/wave_ai.gd")

const PLAYSTYLES := ["defensive", "aggressive", "specops", "combined"]
const STANCES := ["cautious", "balanced", "aggressive"]
const ROLES := ["base_defence", "air_ops", "logistics", "naval"]
const OBJECTIVES := ["take", "hold", "raid", "escort"]
const ALLY_KINDS := ["attack", "defend", "air_support"]
const OWN_COMMANDS := ["set_ai_commander", "recall_ai_commander", "ally_request"]


## The ai_cmd state (created on first use).
static func state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("ai_cmd"):
		w.sys_state["ai_cmd"] = {"ver": 1, "slots": {}, "ally": {}, "wave": {}}
	return w.sys_state.ai_cmd


## Ally commitments (AllyCmds) and the survival wave AI (WaveAI, for the attacker side) run here;
## player commanders run from the world's Commanders.think_player call.
static func tick(w: SimWorld) -> void:
	if w.sys_state.has("ai_cmd"):
		AllyCmds.tick(w)
	var wv = w.sys_state.get("waves")
	if not (wv is Dictionary) or (wv.get("waves", []) as Array).is_empty():
		return
	var af := int(wv.get("attacker", -1))
	if not w.factions.has(af) or not bool(w.factions[af].alive):
		return
	var host: Dictionary
	if w.ai_state.has(af):
		host = w.ai_state[af]
	else:
		var wst: Dictionary = state(w).wave
		if not wst.has(af):
			wst[af] = {}
		host = wst[af]
	WaveAI.think(w, af, host, {})


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	match String(cmd.get("type", "")):
		"set_ai_commander":
			return _validate_set(w, fid, cmd)
		"recall_ai_commander":
			if bool(w.factions[fid].get("is_ai", false)):
				return "AI sides command themselves."
			var sl := int(cmd.get("slot", -1))
			if _slot_of(w, fid, sl).is_empty():
				return "No AI commander in slot %d." % (sl + 1)
			return ""
		"ally_request":
			return _validate_ally(w, fid, cmd)
	return "Unknown AI command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	match String(cmd.type):
		"set_ai_commander":
			_apply_set(w, fid, cmd)
		"recall_ai_commander":
			recall(w, fid, int(cmd.slot), "player")
		"ally_request":
			_apply_ally(w, fid, cmd)


## Player AI-commander slots, ascending slot: [{slot, kind, target, target_spec, formation, role,
## playstyle, objective, stance, units, phase, mode}]. target = company ids (formation of companies)
## or unit ids (role / loose units), as presentation/art/g6_vis.gd reads it; units = every unit the
## slot drives now (the badge set).
static func slots(w: SimWorld, fid: int) -> Array:
	var out := []
	if not w.sys_state.has("ai_cmd"):
		return out
	var ss: Dictionary = (w.sys_state.ai_cmd.slots as Dictionary).get(fid, {})
	var keys := ss.keys()
	keys.sort()
	for k in keys:
		var s: Dictionary = ss[k]
		var spec: Dictionary = s.spec
		var tgt: Array = (spec.get("companies", []) as Array).duplicate() if not (spec.get("companies", []) as Array).is_empty() else (s.units as Array).duplicate()
		out.append({"slot": int(s.slot), "kind": String(s.kind), "target": tgt, "target_spec": spec.duplicate(true),
			"formation": spec.get("formation", null), "role": String(s.role), "playstyle": String(s.playstyle),
			"objective": (s.objective as Dictionary).duplicate(true), "stance": String(s.stance),
			"units": (s.units as Array).duplicate(), "phase": String((s.doc as Dictionary).get("phase", "")),
			"mode": String(s.mode)})
	return out


## Hook after every applied command (CR to ORCH: world._apply_due_commands calls it after
## apply_command). Stamps e.player_order_tick on the units a human side's own command touched, so a
## commander leaves them alone for override_ticks. Commands a commander sends carry "ai_cmd" and are
## skipped; sides that never used commanders are skipped (no new entity fields: G5 hashes equal).
static func on_applied(w: SimWorld, c: Dictionary) -> void:
	if not w.sys_state.has("ai_cmd") or c.has("ai_cmd"):
		return
	var fid := int(c.get("issuer", -1))
	if not (w.sys_state.ai_cmd.slots as Dictionary).has(fid) or OWN_COMMANDS.has(String(c.get("type", ""))):
		return
	var ids := []
	for raw in c.get("unit_ids", []):
		ids.append(int(raw))
	for k in ["unit_id", "carrier_id", "pilot_id"]:
		if c.has(k):
			ids.append(int(c[k]))
	for id in ids:
		var e = w.entities.get(id)
		if e != null and e.kind == "unit" and int(e.owner) == fid:
			e.player_order_tick = w.tick


## True while the player's own order to e is fresher than override_ticks.
static func player_fresh(w: SimWorld, e: Dictionary) -> bool:
	return e.has("player_order_tick") and w.tick - int(e.player_order_tick) < int(Commanders.R("override_ticks"))


## Map position of an objective cell: [x, y] / Vector2i = a cell (its centre); Vector2 = a position.
## null when absent or malformed.
static func cell_pos(v):
	if v is Vector2:
		return v
	if v is Vector2i:
		return Vector2(v) + Vector2(0.5, 0.5)
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]) + 0.5, float(v[1]) + 0.5)
	return null


static func _in_map(w: SimWorld, p: Vector2) -> bool:
	return p.x >= 0.0 and p.y >= 0.0 and p.x < float(w.map.w) and p.y < float(w.map.h)


## Resolves a set_ai_commander target to {kind, spec} or {error}. spec = {formation?, companies: [cid],
## army: aid, units: [ids]} (formation) or {role} (role).
static func resolve_target(w: SimWorld, fid: int, tg) -> Dictionary:
	if not (tg is Dictionary):
		return {"error": "Pick a formation or a role."}
	if tg.has("role"):
		var r := String(tg.role)
		if not ROLES.has(r):
			return {"error": "Unknown role '%s'." % r}
		return {"kind": "role", "spec": {"role": r, "companies": []}}
	if tg.has("units"):
		var ids := []
		for raw in tg.units:
			var e = w.entities.get(int(raw))
			if e != null and e.kind == "unit" and int(e.owner) == fid and not ids.has(int(raw)):
				ids.append(int(raw))
		if ids.is_empty():
			return {"error": "No valid units selected."}
		ids.sort()
		return {"kind": "formation", "spec": {"units": ids, "companies": [], "army": -1}}
	if not tg.has("formation"):
		return {"error": "Pick a formation or a role."}
	var f = tg.formation
	var cs: Dictionary = w.sys_state.get("companies", {}).get("companies", {})
	if f is int or f is float or (f is String and String(f).begins_with("co:")):
		var cid := int(f) if not (f is String) else int(String(f).substr(3))
		var c: Dictionary = cs.get(cid, {})
		if c.is_empty() or int(c.get("owner", -1)) != fid:
			return {"error": "Not your company."}
		return {"kind": "formation", "spec": {"formation": f, "companies": [cid], "army": -1}}
	if f is String and String(f).begins_with("army:"):
		var aid := int(String(f).substr(5))
		var a: Dictionary = w.sys_state.get("companies", {}).get("armies", {}).get(aid, {})
		if a.is_empty() or int(a.get("owner", -1)) != fid:
			return {"error": "Not your army."}
		var cl := []
		for cid in a.get("companies", []):
			cl.append(int(cid))
		cl.sort()
		return {"kind": "formation", "spec": {"formation": f, "companies": cl, "army": aid}}
	return {"error": "Unknown formation."}


static func _validate_set(w: SimWorld, fid: int, cmd: Dictionary) -> String:
	if bool(w.factions[fid].get("is_ai", false)):
		return "AI sides command themselves."
	var sl := int(cmd.get("slot", -1))
	if sl < 0 or sl >= int(Commanders.R("max_slots")):
		return "Pick a commander slot 1-%d." % int(Commanders.R("max_slots"))
	if not PLAYSTYLES.has(String(cmd.get("playstyle", ""))):
		return "Pick a playstyle (defensive, aggressive, special ops, combined arms)."
	if not STANCES.has(String(cmd.get("stance", "balanced"))):
		return "Pick a stance (cautious, balanced, aggressive)."
	var rt := resolve_target(w, fid, cmd.get("target", null))
	if rt.has("error"):
		return String(rt.error)
	var ob = cmd.get("objective", {"type": "hold"})
	if not (ob is Dictionary) or not OBJECTIVES.has(String(ob.get("type", ""))):
		return "Pick an objective (take, hold, raid, escort)."
	var p = cell_pos(ob.get("cell", null))
	if ob.has("cell") and (p == null or not _in_map(w, p)):
		return "Objective is off the map."
	var tid := int(ob.get("target_id", -1))
	if tid >= 0 and not w.entities.has(tid):
		return "Objective target is gone."
	match String(ob.type):
		"take", "raid":
			if p == null and tid < 0:
				return "Pick an objective on the map."
		"escort":
			var te = w.entities.get(tid)
			if te == null or int(te.owner) != fid:
				return "Pick one of your units to escort."
	# a company / role is commanded by one slot at a time (reassigning the same slot replaces it)
	var ss: Dictionary = (w.sys_state.ai_cmd.slots as Dictionary).get(fid, {}) if w.sys_state.has("ai_cmd") else {}
	for k in ss:
		if int(k) == sl:
			continue
		var o: Dictionary = ss[k]
		if rt.kind == "role" and String(o.role) == String(rt.spec.role):
			return "Slot %d already runs %s." % [int(k) + 1, String(o.role)]
		for cid in rt.spec.companies:
			if (o.spec.get("companies", []) as Array).has(int(cid)):
				return "Slot %d already commands that company." % (int(k) + 1)
	return ""


static func _apply_set(w: SimWorld, fid: int, cmd: Dictionary) -> void:
	var st := state(w)
	var sl := int(cmd.slot)
	if not (st.slots as Dictionary).has(fid):
		st.slots[fid] = {}
	if not _slot_of(w, fid, sl).is_empty():
		recall(w, fid, sl, "reassigned")
	var rt := resolve_target(w, fid, cmd.target)
	var ob: Dictionary = cmd.get("objective", {"type": "hold"})
	var obj := {"type": String(ob.type), "target_id": int(ob.get("target_id", -1))}
	var p = cell_pos(ob.get("cell", null))
	if p != null:
		obj.cell = p
	var s := Commanders.new_drive(w, String(cmd.playstyle), String(cmd.get("stance", "balanced")), obj)
	s.merge({"slot": sl, "kind": String(rt.kind), "spec": rt.spec, "role": String(rt.spec.get("role", "")),
		"since": w.tick}, true)
	st.slots[fid][sl] = s
	w.emit("AiCommanderAssigned", {"fid": fid, "slot": sl, "kind": s.kind, "playstyle": s.playstyle,
		"stance": s.stance, "objective": String(obj.type)})


static func _validate_ally(w: SimWorld, fid: int, cmd: Dictionary) -> String:
	var af := int(cmd.get("ally_fid", -1))
	if af == fid or not w.factions.has(af):
		return "Pick an allied side."
	var a: Dictionary = w.factions[af]
	if not bool(a.alive) or int(a.team) != int(w.factions[fid].team):
		return "That side is not your ally."
	if not bool(a.get("is_ai", false)):
		return "Only an AI ally takes requests."
	var k := String(cmd.get("kind", ""))
	if not ALLY_KINDS.has(k):
		return "Ask for attack, defend or air support."
	var p = cell_pos(cmd.get("cell", null))
	if cmd.has("cell") and (p == null or not _in_map(w, p)):
		return "That point is off the map."
	if k != "defend" and p == null:
		return "Pick a point on the map."
	return ""


static func _apply_ally(w: SimWorld, fid: int, cmd: Dictionary) -> void:
	var req := {"from": fid, "kind": String(cmd.kind), "tick": w.tick}
	var p = cell_pos(cmd.get("cell", null))
	if p != null:
		req.cell = p
	state(w)
	w.emit("AllyRequest", {"fid": fid, "ally_fid": int(cmd.ally_fid), "kind": String(cmd.kind)})
	AllyCmds.handle(w, int(cmd.ally_fid), req)


## Slot dict of fid (or {}).
static func _slot_of(w: SimWorld, fid: int, sl: int) -> Dictionary:
	if not w.sys_state.has("ai_cmd"):
		return {}
	return (w.sys_state.ai_cmd.slots as Dictionary).get(fid, {}).get(sl, {})


## Returns control of a slot at once: badges cleared, the slot's not-yet-applied orders dropped.
static func recall(w: SimWorld, fid: int, sl: int, why: String) -> void:
	var s := _slot_of(w, fid, sl)
	if s.is_empty():
		return
	var badge := "p%d" % sl
	for id in s.units:
		var e = w.entities.get(int(id))
		if e != null and String(e.get("ai_cmd", "")) == badge:
			e.erase("ai_cmd")
	var keep := []
	for pc in w.pending:
		if int(pc.get("issuer", -1)) == fid and String(pc.get("ai_cmd", "")) == badge:
			continue
		keep.append(pc)
	w.pending = keep
	(w.sys_state.ai_cmd.slots[fid] as Dictionary).erase(sl)
	w.emit("AiCommanderRecalled", {"fid": fid, "slot": sl, "reason": why, "unit_ids": (s.units as Array).duplicate()})
