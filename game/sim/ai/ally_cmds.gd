extends RefCounted
## AllyCmds (ally AI requests) (owner: AI7-CMD). CONTRACTS_G6 section 16.
## A human player asks an allied AI side (ally_request): "attack here", "defend me", "send air support".
## The ally commits forces within its means and AI7-CMD drives them through the Commanders engine
## (Doctrine.plan_for); its own AI holds them while they carry e.ai_cmd = "ally" (AI7-USE / AI7-DOC CRs).
##   attack      : its nearest company (else up to half its loose ground army, <= ally_max_units),
##                 combined-arms take of the cell.
##   defend      : the same pick, defensive hold of the cell (default: the requester's base).
##   air_support : its aircraft (<= ally_max_units) strike enemies seen near the cell for air_support_ticks.
## One commitment per ally (a new request replaces it); released after ally_ticks, when spent, or when
## the ally dies. State: w.sys_state.ai_cmd.ally {ally_fid: drive + {kind, from, until, pool, role?}}.
## Events: AllyCommitted {fid, ally_fid, kind, unit_ids}, AllyRefused {fid, ally_fid, kind, reason},
##   AllyReleased {ally_fid, kind, reason}. Never preloads ai_command.gd (it preloads this file).

const Commanders = preload("res://sim/ai/commanders.gd")
const Companies = preload("res://sim/systems/companies.gd")
const DU = preload("res://sim/ai/doctrine/doc_util.gd")
const U = preload("res://sim/ai/ai_util.gd")


## An allied AI side acts on a player ally_request (req = {from, kind, tick, cell?}).
static func handle(w: SimWorld, fid: int, req: Dictionary) -> void:
	if not w.sys_state.has("ai_cmd"):
		return
	var ally: Dictionary = w.sys_state.ai_cmd.ally
	if ally.has(fid):
		release(w, fid, "replaced")
	var kind := String(req.kind)
	var from := int(req.from)
	var cell: Vector2 = req.cell if req.has("cell") else U.base_pos(w, from)
	var ids := pick(w, fid, kind, cell)
	if ids.is_empty():
		w.emit("AllyRefused", {"fid": from, "ally_fid": fid, "kind": kind,
			"reason": "no aircraft to send" if kind == "air_support" else "no forces to spare"})
		return
	var ps := "combined" if kind == "attack" else "defensive"
	var d := Commanders.new_drive(w, ps, "balanced", {"type": "take" if kind == "attack" else "hold", "cell": cell, "target_id": -1})
	d.kind = kind
	d.from = from
	d.pool = ids
	d.until = w.tick + int(Commanders.R("air_support_ticks" if kind == "air_support" else "ally_ticks"))
	if kind == "air_support":
		d.role = "air_ops"
	ally[fid] = d
	w.emit("AllyCommitted", {"fid": from, "ally_fid": fid, "kind": kind, "unit_ids": ids.duplicate()})
	Commanders.tag(w, fid, d, "reserve_commit", ids, "Ally side %d commits %d units to %s at (%d, %d) for side %d." % [
		fid, ids.size(), kind.replace("_", " "), int(cell.x), int(cell.y), from], false)


## Units the ally can spare for kind (ascending ids): aircraft for air support; else its company
## nearest the cell, or up to half of its loose armed ground units (nearest first, <= ally_max_units).
static func pick(w: SimWorld, fid: int, kind: String, cell: Vector2) -> Array:
	var cap := int(Commanders.R("ally_max_units"))
	var out := []
	if kind == "air_support":
		for e in w.units_of(fid):
			var u := Content.unit(String(e.def))
			if String(u.get("move_class", "")).begins_with("air") and not bool(u.get("launched_drone", false)) \
					and String(u.get("weapon", "")) != "" and not e.has("ai_cmd") and out.size() < cap:
				out.append(int(e.id))
		return out
	var best = null
	var bd := INF
	for c in Companies.companies_of(w, fid):
		var cap_e = w.entities.get(int(c.get("captain", -1)))  # AI-FAIR: own company's captain (companies_of(fid))
		var cu := Commanders.company_units(w, fid, c)
		if cu.is_empty() or Commanders.alive(w, fid, cu).any(func(e): return e.has("ai_cmd")):
			continue
		var p: Vector2 = cap_e.pos if cap_e != null else DU.centroid(Commanders.alive(w, fid, cu))
		if p.distance_to(cell) < bd:
			bd = p.distance_to(cell)
			best = cu
	if best != null:
		out = (best as Array).duplicate()
		out.sort()
		return out
	var loose := []
	for e in w.units_of(fid):
		var u := Content.unit(String(e.def))
		var mc := String(u.get("move_class", "foot"))
		if String(u.get("weapon", "")) == "" or mc.begins_with("air") or mc.begins_with("naval") or e.has("company") \
				or e.has("ai_cmd") or bool(e.get("wounded", false)) or bool(u.get("can_build", false)) \
				or bool(u.get("can_gather", false)) or bool(u.get("is_supply", false)) or bool(u.get("is_officer", false)):
			continue
		loose.append(e)
	loose.sort_custom(func(a, b):
		var da := (a.pos as Vector2).distance_to(cell)
		var db := (b.pos as Vector2).distance_to(cell)
		return da < db or (da == db and int(a.id) < int(b.id)))
	var n := mini(cap, loose.size() / 2) if loose.size() >= 2 else 0
	for i in n:
		out.append(int(loose[i].id))
	out.sort()
	return out


## Drives every ally commitment (called by AiCommand.tick).
static func tick(w: SimWorld) -> void:
	var ally: Dictionary = w.sys_state.ai_cmd.ally
	if ally.is_empty():
		return
	var keys := ally.keys()
	keys.sort()
	for af in keys:
		var d: Dictionary = ally[af]
		var fid := int(af)   # the committed ally side drives its own units here (validated side id)
		if not bool(w.factions[fid].alive) or w.tick >= int(d.until):
			release(w, fid, "done")
			continue
		if w.tick < int(d.next_think):
			continue
		d.next_think = w.tick + int(Commanders.R("think_ticks"))
		if Commanders.alive(w, int(af), d.pool).is_empty():
			release(w, int(af), "spent")
			continue
		if String(d.kind) == "air_support":
			Commanders.drive_role(w, int(af), d, d.pool, "ally", Vector2(d.objective.cell))
		else:
			Commanders.drive(w, int(af), d, d.pool, "ally", U.base_pos(w, int(af)))


## Ends a commitment: badges cleared, the ally's own AI takes the units back.
static func release(w: SimWorld, af: int, why: String) -> void:
	var ally: Dictionary = w.sys_state.ai_cmd.ally
	var d: Dictionary = ally.get(af, {})
	if d.is_empty():
		return
	Commanders.clear_badge(w, d, "ally")
	ally.erase(af)
	w.emit("AllyReleased", {"ally_fid": af, "kind": String(d.get("kind", "")), "reason": why})
