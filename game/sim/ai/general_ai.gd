extends RefCounted
## AI-side generals (owner: GEN61; G6.1 GEN61-2). An AI-controlled side (enemy or ally AI, w.ai_state) can run
## the SAME General engine (general.gd + general_war*.gd + general_net.gd) for its companies: one drive per
## side with objective {type: "auto"}, driven through Commanders.drive under badge "general". Units carrying
## e.ai_cmd are skipped by that side's own Doctrine / army AI (the AI7-CMD skip rule), so there is no double
## control. The side's own economy keeps building; the general has no budget of its own (it never spends).
## Guarded: OFF unless content/rules.json ai_cmd.general.enemy_general is true, or the side's faction dict
## carries ai_general = true (match setup / tests). A match that never enables it creates no state.
## State: w.sys_state.ai_cmd.egen {fid: drive (Commanders.new_drive + spec {companies}, slot -1 - fid)}.
## Events: the General's own (AiGeneralOp, AiFireSupport, AiGeneralOrder) with slot = -1 - fid.

const RULES := {"enemy_general": false, "enemy_min_companies": 1, "enemy_playstyle": "combined",
	"enemy_stance": "balanced"}

static var _cs: Script = null
static var _us: Script = null


static func C() -> Script:
	if _cs == null:
		_cs = load("res://sim/ai/commanders.gd")
	return _cs


static func ER(key: String):
	var ac = Content.rules().get("ai_cmd", null)
	var src = ac.get("general", null) if ac is Dictionary else null
	if src is Dictionary and src.has(key):
		return src[key]
	return RULES.get(key)


## True when AI side fid runs a general.
static func enabled(w: SimWorld, fid: int) -> bool:
	if not w.factions.has(fid) or not w.ai_state.has(fid):
		return false
	var f: Dictionary = w.factions[fid]
	if f.has("ai_general"):
		return bool(f.ai_general)
	return bool(ER("enemy_general"))


## Called from AiCommand.tick every tick; cheap no-op while no AI side runs a general.
static func tick(w: SimWorld) -> void:
	var ai0 = w.sys_state.get("ai_cmd", null)
	if not bool(ER("enemy_general")) and not (ai0 is Dictionary and (ai0 as Dictionary).has("egen")):
		var any := false
		for fid in w.ai_state:
			if bool((w.factions.get(fid, {}) as Dictionary).get("ai_general", false)):
				any = true
				break
		if not any:
			return
	var ai: Dictionary = load("res://sim/systems/ai_command.gd").state(w)
	if not ai.has("egen"):
		ai.egen = {}
	var eg: Dictionary = ai.egen
	var fids := w.ai_state.keys()
	fids.sort()
	for fid in fids:
		fid = int(fid)
		if not w.factions.has(fid):
			continue
		var on := enabled(w, fid) and bool(w.factions[fid].get("alive", true))
		if not on:
			if eg.has(fid):
				C().clear_badge(w, eg[fid], "general")
				eg.erase(fid)
			continue
		if not eg.has(fid):
			var d: Dictionary = C().new_drive(w, String(ER("enemy_playstyle")), String(ER("enemy_stance")), {"type": "auto"})
			d.slot = -1 - fid
			d.spec = {"companies": []}
			d.next_think = w.tick + (fid % 20)   # staggered per side
			eg[fid] = d
		var s: Dictionary = eg[fid]
		if w.tick < int(s.next_think):
			continue
		s.next_think = w.tick + int(C().R("think_ticks"))
		_sync_companies(w, fid, s)
		if ((s.spec as Dictionary).companies as Array).size() < int(ER("enemy_min_companies")):
			C().clear_badge(w, s, "general")
			continue
		var ids: Array = C().formation_ids(w, fid, s)
		if _us == null:
			_us = load("res://sim/ai/ai_util.gd")
		C().drive(w, fid, s, ids, "general", _us.base_pos(w, fid))


## The general takes every formed company of the side (ascending id); dead ones drop out.
static func _sync_companies(w: SimWorld, fid: int, s: Dictionary) -> void:
	var cs: Dictionary = w.sys_state.get("companies", {}).get("companies", {})
	var out := []
	var keys := cs.keys()
	keys.sort()
	for cid in keys:
		var c: Dictionary = cs[cid]
		if int(c.get("owner", -1)) != fid or bool(c.get("disbanded", false)):
			continue
		var us: Array = C().company_units(w, fid, c)
		var other := false
		for id in us:
			var e = w.entities.get(int(id))  # AI-FAIR: own company members only
			if e != null and e.has("ai_cmd") and String(e.ai_cmd) != "general":
				other = true  # an ally commitment / wave owns it
				break
		if not us.is_empty() and not other:
			out.append(int(cid))
	s.spec.companies = out
