extends RefCounted
## Advancement gate evaluation (owner: STG4, CONTRACTS_G3b section 3.2). Preload, no class_name.
## report(w, fid) -> Array[{key, label, have, need, ok}] for the side's NEXT stage ([] at the top
## stage). It is the single source for UI and AI (Progression.gate_report wraps it).
## Keys: ore_refined | comms | power | officers | line | people | research | cost.
## Extra fields: people {alt_have, alt_need} (explored %), research {missing: [ids]}, cost {cost: {...}}.

const PData = preload("res://sim/systems/progression_data.gd")


static func _entry(key: String, label: String, have, need, ok: bool) -> Dictionary:
	return {"key": key, "label": label, "have": have, "need": need, "ok": ok}


static func report(w: SimWorld, fid: int) -> Array:
	if not w.factions.has(fid):
		return []
	var f: Dictionary = w.factions[fid]
	var to := int(f.stage) + 1
	var g := PData.gates_for(to)
	if g.is_empty():
		return []
	var st: Dictionary = f.stats
	var out := []
	if g.has("ore_refined"):
		var have := int(st.get("ore_refined", 0))
		out.append(_entry("ore_refined", "Ore refined", have, int(g.ore_refined), have >= int(g.ore_refined)))
	if g.has("comms_buildings"):
		var have := comms_buildings(w, fid)
		out.append(_entry("comms", "Comms buildings completed", have, int(g.comms_buildings), have >= int(g.comms_buildings)))
	if g.has("power_ok_seconds"):
		var need_s := int(g.power_ok_seconds)
		var ticks := int(st.get("power_ok_ticks", 0))
		var ok := ticks >= need_s * SimWorld.TICK_RATE
		out.append(_entry("power", "Stable power (%d s without shortfall)" % need_s, mini(ticks / SimWorld.TICK_RATE, need_s), need_s, ok))
	if g.has("officers_trained"):
		var have := int(st.get("officers_trained", 0))
		out.append(_entry("officers", "Officers trained", have, int(g.officers_trained), have >= int(g.officers_trained)))
	if g.has("line_trained"):
		var have := int(st.get("line_trained", 0))
		out.append(_entry("line", "Line infantry / anti-tank trained", have, int(g.line_trained), have >= int(g.line_trained)))
	if g.has("recon_alive"):
		var have := recon_alive(w, fid)
		var need := int(g.recon_alive)
		var frac := float(g.get("or_explored_fraction", 2.0))
		var ex := explored_fraction(w, fid)
		var e := _entry("people", "Recon units alive (or %d%% of the map explored)" % int(round(frac * 100.0)), have, need, have >= need or ex >= frac)
		e.alt_have = int(floor(ex * 100.0))
		e.alt_need = int(round(frac * 100.0))
		out.append(e)
	if g.has("research"):
		var req: Array = g.research
		var missing := []
		for rid in req:
			if not PData.has_research(w, fid, String(rid)):
				missing.append(String(rid))
		var names := []
		for rid in req:
			names.append(PData.project_name(String(rid), String(f.faction_def)))
		var e := _entry("research", "Research: " + ", ".join(names), req.size() - missing.size(), req.size(), missing.is_empty())
		e.missing = missing
		out.append(e)
	if g.has("cost"):
		var cost := PData.advance_cost(w, to)
		var e := _entry("cost", "Cost: " + PData.cost_label(cost), 1 if w.can_afford(fid, cost) == "" else 0, 1, w.can_afford(fid, cost) == "")
		e.cost = cost
		out.append(e)
	return out


## Completed buildings of this side flagged `comms`.
static func comms_buildings(w: SimWorld, fid: int) -> int:
	var n := 0
	for b in w.buildings_of(fid):
		if bool(b.built) and bool(Content.building(b.def).get("comms", false)):
			n += 1
	return n


## Living units of the side's recon role (infantry role when the faction has no recon).
static func recon_alive(w: SimWorld, fid: int) -> int:
	var item := PData.role(w, fid, "recon")
	if item == "":
		item = PData.role(w, fid, "infantry")
	var defs: Array = Content.production(item).get("spawns", [])
	if defs.is_empty():
		return 0
	var n := 0
	for u in w.units_of(fid):
		if defs.has(String(u.def)):
			n += 1
	return n


## Fraction of map cells explored by the side's team (fog explored arrays are team-shared).
static func explored_fraction(w: SimWorld, fid: int) -> float:
	var fg = w.fog.get(fid)
	if fg == null:
		return 0.0
	var ex: PackedByteArray = fg.explored
	if ex.is_empty():
		return 0.0
	return float(ex.size() - ex.count(0)) / float(ex.size())


## First unmet gate as a player-facing sentence, or "" when every gate is met.
static func first_unmet(w: SimWorld, fid: int) -> String:
	for e in report(w, fid):
		if bool(e.ok):
			continue
		if String(e.key) == "cost":
			return "Not enough resources to advance (%s). %s" % [String(e.label), w.can_afford(fid, e.cost)]
		if String(e.key) == "research":
			var names := []
			for rid in e.missing:
				names.append(PData.project_name(String(rid), String(w.factions[fid].faction_def)))
			return "Requires research: %s" % ", ".join(names)
		return "Gate not met: %s (%s / %s)." % [String(e.label), str(e.have), str(e.need)]
	return ""
