class_name Coalition10
extends RefCounted
## G10 Shadow Coalition facade — doctrine state, stage openers, readable board schema.

const FACTION_ID := "shadow_coalition"
const KEY := "coalition10"
const INTENTS := ["harry", "bleed", "flex", "strike", "exfil"]

## Authoritative Stage 7–10 core gameplay IDs (61). Roster tasks must not rename these.
const CORE_IDS := [
	"x_cell_rifle", "x_cell_at", "x_cell_sapper", "x_cell_medic", "x_ambush_cell", "x_sleeper_cell",
	"x_backdoor_hacker", "x_broker", "x_pmc_rifle", "x_pmc_assault", "x_pmc_sniper", "x_pmc_ew", "x_officer",
	"x_ghost_infiltrator",
	"x_technical_mg", "x_technical_rocket", "x_technical_aa", "x_technical_mortar", "x_technical_recoilless",
	"x_captured_tank", "x_refit_ifv", "x_shock_truck", "x_stealth_apc", "x_ghost_runner", "x_exo_mule",
	"x_recovery_truck", "x_ghost_drone_carrier", "x_prototype_walker",
	"x_stealth_drone", "x_shock_drone", "x_recon_drone", "x_silent_rotor", "x_stealth_transport", "x_patron_cas",
	"x_river_ghost", "x_mini_sub", "x_smuggler_boat", "x_patrol_boat",
	"x_death_strike", "x_death_assault", "x_death_recon", "x_shadow_pathfinder", "x_shadow_ew",
	"x_shadow_signal", "x_shadow_decoy", "x_anchor_tech", "x_anchor_medic",
	"x_safehouse", "x_tunnel_entrance", "x_cache", "x_weld_shop", "x_black_market", "x_broker_exchange",
	"x_patron_office", "x_disguised_workshop", "x_bunker_hatch", "x_underground_barracks",
	"x_underground_factory", "x_ghost_complex", "x_forward_repair", "x_vault_core",
]


static func _rules() -> Dictionary:
	return Content.rules().get("coalition10", {})


static func match_has_coalition(w: SimWorld) -> bool:
	for fid in w.factions:
		var f = w.factions[fid]
		if typeof(f) == TYPE_DICTIONARY and String(f.get("faction_def", "")) == FACTION_ID:
			return true
	return false


## Lazy state: created only when a Coalition side exists or an API is first called for one.
static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		if not match_has_coalition(w):
			return {}
		var factions := {}
		var keys: Array = []
		for fid in w.factions:
			var f = w.factions[fid]
			if typeof(f) == TYPE_DICTIONARY and String(f.get("faction_def", "")) == FACTION_ID:
				keys.append(int(fid))
		keys.sort()
		for fid in keys:
			factions[str(fid)] = _new_side()
		w.sys_state[KEY] = {"factions": factions}
	return w.sys_state[KEY]


static func _new_side() -> Dictionary:
	return {
		"intent": String(_rules().get("default_intent", "harry")),
		"layer": "cells",
		"cells": 0,
		"contracts": [],
		"patron_favour": 0,
		"intel_grade": "rumour",
		"ghost_ready": false,
		"tech_sources": [],
		"evidence": {},
		"resources_seen": 0,
	}


static func _side(w: SimWorld, fid: int) -> Dictionary:
	var st := _st(w)
	if st.is_empty():
		return {}
	var key := str(fid)
	var factions: Dictionary = st.get("factions", {})
	if not factions.has(key):
		if not active(w, fid):
			return {}
		factions[key] = _new_side()
	return factions[key]


static func active(w: SimWorld, fid: int) -> bool:
	if not w.factions.has(fid):
		return false
	var f = w.factions[fid]
	return typeof(f) == TYPE_DICTIONARY and String(f.get("faction_def", "")) == FACTION_ID


static func layer(w: SimWorld, fid: int) -> String:
	if not active(w, fid):
		return ""
	var s := _side(w, fid)
	return String(s.get("layer", "cells"))


static func set_intent(w: SimWorld, fid: int, intent: String) -> void:
	if not active(w, fid):
		return
	var want := String(intent)
	if not INTENTS.has(want):
		return
	var s := _side(w, fid)
	if s.is_empty():
		return
	# Doctrine transitions only from evidence/resources — not free spam.
	if want != String(s.get("intent", "harry")):
		var evidence: Dictionary = s.get("evidence", {})
		var resources_seen := int(s.get("resources_seen", 0))
		var ok := false
		match want:
			"harry":
				ok = true
			"bleed":
				ok = int(evidence.get("probes", 0)) >= 1 or resources_seen >= 1
			"flex":
				ok = int(evidence.get("gap", 0)) >= 1 or int(s.get("patron_favour", 0)) >= 10
			"strike":
				ok = int(evidence.get("weak_point", 0)) >= 1 and String(s.get("intel_grade", "")) in ["pattern", "fix", "keyhole"]
			"exfil":
				ok = int(evidence.get("pressure", 0)) >= 1 or bool(s.get("ghost_ready", false))
		if not ok:
			return
	s.intent = want
	_refresh_layer(s)
	w.emit("Coalition10Intent", {"fid": fid, "intent": want, "layer": String(s.layer)})


static func note_evidence(w: SimWorld, fid: int, key: String, amount: int = 1) -> void:
	if not active(w, fid):
		return
	var s := _side(w, fid)
	if s.is_empty():
		return
	var ev: Dictionary = s.get("evidence", {})
	ev[key] = int(ev.get(key, 0)) + maxi(amount, 1)
	s.evidence = ev
	_refresh_layer(s)


static func note_resources(w: SimWorld, fid: int, amount: int = 1) -> void:
	if not active(w, fid):
		return
	var s := _side(w, fid)
	if s.is_empty():
		return
	s.resources_seen = int(s.get("resources_seen", 0)) + maxi(amount, 1)
	_refresh_layer(s)


static func _refresh_layer(s: Dictionary) -> void:
	var favour := int(s.get("patron_favour", 0))
	var ghost := bool(s.get("ghost_ready", false))
	var contracts: Array = s.get("contracts", [])
	if ghost or favour >= 40 or contracts.size() >= 3:
		s.layer = "elite"
	elif favour >= 10 or contracts.size() >= 1:
		s.layer = "mercs"
	else:
		s.layer = "cells"


static func board(w: SimWorld, fid: int) -> Dictionary:
	if not active(w, fid):
		return {}
	var s := _side(w, fid)
	if s.is_empty():
		return {}
	return {
		"intent": String(s.get("intent", "harry")),
		"layer": String(s.get("layer", "cells")),
		"cells": int(s.get("cells", 0)),
		"contracts": (s.get("contracts", []) as Array).duplicate(),
		"patron_favour": int(s.get("patron_favour", 0)),
		"intel_grade": String(s.get("intel_grade", "rumour")),
		"ghost_ready": bool(s.get("ghost_ready", false)),
		"tech_sources": (s.get("tech_sources", []) as Array).duplicate(),
	}


## Legal opener for a Coalition stage: base + builder/gatherer + combat unit defs resolve.
static func validate_stage_opener(stage: int) -> Dictionary:
	var openers: Dictionary = _rules().get("stage_openers", {})
	var row: Dictionary = openers.get(str(stage), {})
	if row.is_empty():
		return {"ok": false, "reason": "missing opener for stage %d" % stage, "stage": stage}
	var base := String(row.get("base", ""))
	var builder := String(row.get("builder", ""))
	var gatherer := String(row.get("gatherer", builder))
	var combat := String(row.get("combat", ""))
	var missing: Array = []
	if Content.building(base).is_empty():
		missing.append("base:%s" % base)
	if Content.unit(builder).is_empty():
		missing.append("builder:%s" % builder)
	if Content.unit(gatherer).is_empty():
		missing.append("gatherer:%s" % gatherer)
	if Content.unit(combat).is_empty():
		missing.append("combat:%s" % combat)
	if not missing.is_empty():
		return {"ok": false, "reason": "unresolved %s" % ",".join(missing), "stage": stage, "opener": row}
	return {
		"ok": true,
		"stage": stage,
		"profile": String(row.get("profile", "")),
		"base": base,
		"builder": builder,
		"gatherer": gatherer,
		"combat": combat,
		"opener": row,
	}


## No tick work when Coalition is absent (state never created).
static func tick(w: SimWorld) -> void:
	if not w.sys_state.has(KEY):
		return
	# Passivekeeping reserved for later pillars; keep deterministic no-op shell.
	pass


static func snap_provider(w: SimWorld, _snap: Dictionary) -> Variant:
	if not w.sys_state.has(KEY):
		return null
	var out := {}
	var factions: Dictionary = w.sys_state[KEY].get("factions", {})
	var keys: Array = factions.keys()
	keys.sort()
	for k in keys:
		var fid := int(k)
		out[k] = board(w, fid)
	return out
