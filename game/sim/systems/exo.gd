extends RefCounted
## Exo (owner: EXO6). CONTRACTS_G6 sections 4, 5.1, 14; PLAN_G6 D32-D35. Numbers: rules.g6_exo.
## - Garage gating (can_produce): exo suits (unit def exo_suit) need Stage >= their stage_min (rifle and
##   missile 9, AA 10) and an own built Exo-Suit Garage (building def exo_garage); the Exo-Suit Trooper
##   (role exo_trooper, barracks) needs Stage 10. A suit is ONE vehicle element in a company (unit def
##   element_class "vehicle"; Companies counts one production item as one element).
## - Pilot eject (on_destroyed, via G6Hooks before Damage removes a unit): a destroyed suit spawns its pilot
##   (def pilot_def, "rifleman") on the nearest free cell as a G5 Wounded (Medical.wound) with
##   e.pilot_of = suit def. G5 rule (rules pilot_needs_medical): only while the side has medical
##   capability (Medical.has_medical); otherwise the pilot is lost with the suit (event PilotLost).
##   The wounded pilot is evacuated / healed by G5 medical (Medical._revive keeps pilot_of).
## - resuit {issuer, building_id (garage), pilot_id, suit?}: a treated (non-wounded) pilot within
##   rules resuit_range cells of an own built garage becomes a new suit beside the garage, instantly, for
##   resuit_cost_mult (garage def, else rules; 0.6) of the suit's production cost (each resource rounded).
##   suit defaults to pilot_of; any suit the garage produces and the side may build now is accepted.
## - set_loadout {issuer, unit_ids, loadout, building_id}: own built barracks / crawler works / Company HQ
##   (Loadouts.is_loadout_building); own units within rules loadout_range cells of its footprint that may
##   take the loadout (Loadouts.loadouts_for; "standard" reverts) and are not wounded; ineligible, far
##   or already-equipped units are skipped (rejected only when none remain); cost = per-unit cost x units.
## - tick: Loadouts.prune (keeps sys_state.loadouts.nonstandard exact for removals outside Damage).
## State (saved, hashed; created on first use): w.sys_state.exo = {ejected, lost_pilots, resuited, ver: 1}.
## Entity fields: e.pilot_of (suit def id; the pilot keeps it after treatment), e.loadout / e.art_def (Loadouts).
## Do not preload g6_hooks.gd here (cycle). Medical / Movement / SimIndex are reached through SimWorld.
## G10 (GHOST10): Ghost regiment overlay lives in ghost_exo10.gd. Pre-G10 Human exo_suit path is unchanged.
##   is_ghost_suit_def / ghost_tick are additive; garage eject/resuit/loadout still apply only to exo_suit defs.
## G10 (CG10): Counter-Ghost overlay in counter_ghost10.gd. Second owner of this file after GHOST RELEASE.
##   is_counter_ghost_def / counter_ghost_tick are additive; do not alter Pre-G10 or Ghost paths.

const Loadouts = preload("res://sim/systems/loadouts.gd")
const PData = preload("res://sim/systems/progression_data.gd")
const GhostExo10 = preload("res://sim/systems/ghost_exo10.gd")
const CounterGhost10 = preload("res://sim/systems/counter_ghost10.gd")


static func cfg() -> Dictionary:
	return Loadouts.cfg()


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("exo"):
		w.sys_state["exo"] = {"ejected": 0, "lost_pilots": 0, "resuited": 0, "ver": 1}
	return w.sys_state["exo"]


static func tick(w: SimWorld) -> void:
	Loadouts.prune(w)
	ghost_tick(w)
	counter_ghost_tick(w)


## G10 forward: no-op unless GhostExo10 state was created. ORCH may also wire GhostExo10.tick separately.
static func ghost_tick(w: SimWorld) -> void:
	if GhostExo10.active(w):
		GhostExo10.tick(w)


## G10 CG10 forward: no-op unless CounterGhost10 state was created.
static func counter_ghost_tick(w: SimWorld) -> void:
	if CounterGhost10.active(w):
		CounterGhost10.tick(w)


static func is_suit_def(def_id: String) -> bool:
	return bool(Content.unit(def_id).get("exo_suit", false))


## G10 Ghost regiment operators (Death/Shadow/Anchor). Not Pre-G10 exo_suit garage suits.
static func is_ghost_suit_def(def_id: String) -> bool:
	return GhostExo10.is_ghost_suit_def(def_id)


## G10 Human A Counter-Ghost corps defs. Not Pre-G10 exo_suit and not Ghost regiment.
static func is_counter_ghost_def(def_id: String) -> bool:
	return CounterGhost10.is_cg_def(def_id)


## Dedicated home pad/garage for a CG vehicle ("" if none).
static func cg_home_for(vehicle_def: String) -> String:
	return CounterGhost10.home_for(vehicle_def)


## Own built Exo-Suit Garages, ascending id.
static func garages_of(w: SimWorld, fid: int) -> Array:
	var out := []
	for b in SimWorld.SimIndex.of(w, "building"):
		if int(b.owner) == fid and bool(b.get("built", false)) and w.entities.has(int(b.id)) \
				and bool(Content.building(String(b.def)).get("exo_garage", false)):
			out.append(b)
	out.sort_custom(func(a, c): return int(a.id) < int(c.id))
	return out


## Production gate for exo suits ("" = ok).
static func can_produce(w: SimWorld, fid: int, def_id: String) -> String:
	var p := Content.production(def_id)
	if p.is_empty():
		return ""
	var suit := ""
	var unit := ""
	var troop_roles: Array = cfg().get("exo_trooper_roles", [])
	for u in p.get("spawns", []):
		var d := Content.unit(String(u))
		if bool(d.get("exo_suit", false)):
			suit = String(u)
			unit = suit
		elif troop_roles.has(String(d.get("role", ""))):
			unit = String(u)
	if unit == "" or not w.factions.has(fid):
		return ""
	var need := maxi(int(p.get("stage_min", 7)), int(Content.unit(unit).get("stage_min", 7)))
	if int(w.factions[fid].get("stage", 8)) < need:
		return "Requires Stage %d" % need
	if suit != "" and garages_of(w, fid).is_empty():
		return "Requires an Exo-Suit Garage"
	return ""


## Pilot eject hook (G6Hooks.on_destroyed): every unit removed by Damage passes here.
static func on_destroyed(w: SimWorld, e: Dictionary) -> void:
	if e.has("loadout"):
		Loadouts.forget(w, e)
	if String(e.get("kind", "")) != "unit":
		return
	var d := Content.unit(String(e.def))
	if bool(d.get("exo_suit", false)):
		_eject(w, e, d)


static func _eject(w: SimWorld, e: Dictionary, d: Dictionary) -> void:
	var fid := int(e.owner)
	var pdef := String(d.get("pilot_def", cfg().get("pilot_def", "rifleman")))
	var pd := Content.unit(pdef)
	if pd.is_empty() or not w.factions.has(fid):
		return
	var st := _st(w)
	if bool(cfg().get("pilot_needs_medical", true)) and not SimWorld.Medical.has_medical(w, fid):
		st.lost_pilots = int(st.lost_pilots) + 1
		w.emit("PilotLost", {"owner": fid, "suit": String(e.def), "suit_id": int(e.id), "pos": e.pos})
		return
	var mc := String(pd.get("move_class", "foot"))
	var pos := Vector2(SimWorld.Movement.nearest_free_cell(w, w.cell_of(e.pos), mc)) + Vector2(0.5, 0.5)
	var pid := w.spawn_unit(pdef, fid, pos)
	var p: Dictionary = w.entities[pid]
	p.pilot_of = String(e.def)
	SimWorld.Medical.wound(w, p)
	st.ejected = int(st.ejected) + 1
	w.emit("PilotEjected", {"id": pid, "owner": fid, "suit": String(e.def), "suit_id": int(e.id), "pos": pos})


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	match String(cmd.get("type", "")):
		"set_loadout":
			return String(plan_loadout(w, cmd).reason)
		"resuit":
			return String(plan_resuit(w, cmd).reason)
	return "Unknown command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.get("issuer", -1))
	match String(cmd.get("type", "")):
		"set_loadout":
			var pl := plan_loadout(w, cmd)
			if String(pl.reason) != "" or not w.spend(fid, pl.cost, "loadout"):
				return
			for id in pl.ids:
				Loadouts.apply(w, w.entities[id], String(cmd.loadout))
			w.emit("LoadoutChanged", {"owner": fid, "ids": (pl.ids as Array).duplicate(),
				"loadout": String(cmd.loadout), "building": int(cmd.building_id), "cost": pl.cost})
		"resuit":
			var pr := plan_resuit(w, cmd)
			if String(pr.reason) != "" or not w.spend(fid, pr.cost, "resuit"):
				return
			_resuit(w, fid, pr)


## {reason, ids (ascending), cost} for a set_loadout command; reason "" = valid.
static func plan_loadout(w: SimWorld, cmd: Dictionary) -> Dictionary:
	var out := {"reason": "", "ids": [], "cost": {}}
	var fid := int(cmd.get("issuer", -1))
	var lid := String(cmd.get("loadout", ""))
	var b = w.entities.get(int(cmd.get("building_id", -1)))
	if b == null or String(b.kind) != "building" or int(b.owner) != fid:
		out.reason = "Choose one of your barracks or a Company HQ."
		return out
	if not bool(b.get("built", false)):
		out.reason = "The building is still under construction."
		return out
	if not Loadouts.is_loadout_building(String(b.def)):
		out.reason = "Loadouts are changed at a barracks or a Company HQ."
		return out
	var avail := Loadouts.available(w, fid, lid)
	if avail != "":
		out.reason = avail
		return out
	var raw = cmd.get("unit_ids", [])
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		out.reason = "Select the squads to re-equip."
		return out
	var ids := []
	for v in raw:
		if not ids.has(int(v)):
			ids.append(int(v))
	ids.sort()
	var rng := float(cfg().get("loadout_range", 8))
	var far := false
	var inel := false
	for id in ids:
		var e = w.entities.get(id)
		if e == null or String(e.kind) != "unit" or int(e.owner) != fid:
			out.reason = "Not your unit."
			return out
		if bool(e.get("wounded", false)) or e.has("evac_by"):
			inel = true
		elif lid != "standard" and not Loadouts.loadouts_for(fid, String(e.def)).has(lid):
			inel = true
		elif Loadouts.of(e) == lid:
			continue
		elif Loadouts.footprint_dist(b, e.pos) > rng:
			far = true
		else:
			out.ids.append(id)
	if (out.ids as Array).is_empty():
		out.reason = "Move the squads next to the building first." if far \
			else ("These units cannot take that loadout." if inel else "Those squads already have that loadout.")
		return out
	var unit_cost := Loadouts.cost_of(lid)
	for k in unit_cost:
		out.cost[k] = int(unit_cost[k]) * (out.ids as Array).size()
	out.reason = w.can_afford(fid, out.cost)
	return out


## {reason, pilot, garage, suit, cost, pop_delta} for a resuit command; reason "" = valid.
static func plan_resuit(w: SimWorld, cmd: Dictionary) -> Dictionary:
	var out := {"reason": "", "pilot": -1, "garage": -1, "suit": "", "cost": {}, "pop_delta": 0}
	var fid := int(cmd.get("issuer", -1))
	var g = w.entities.get(int(cmd.get("building_id", -1)))
	if g == null or String(g.kind) != "building" or int(g.owner) != fid \
			or not bool(Content.building(String(g.def)).get("exo_garage", false)):
		out.reason = "Choose one of your Exo-Suit Garages."
		return out
	if not bool(g.get("built", false)):
		out.reason = "The garage is still under construction."
		return out
	var p = w.entities.get(int(cmd.get("pilot_id", -1)))
	if p == null or String(p.kind) != "unit" or int(p.owner) != fid:
		out.reason = "Not your unit."
		return out
	if String(p.get("pilot_of", "")) == "":
		out.reason = "Only an ejected suit pilot can re-suit."
		return out
	if bool(p.get("wounded", false)) or p.has("evac_by"):
		out.reason = "The pilot must be treated first (evacuate to a hospital)."
		return out
	if Loadouts.footprint_dist(g, p.pos) > float(cfg().get("resuit_range", 6)):
		out.reason = "Move the pilot next to the garage."
		return out
	var suit := String(cmd.get("suit", p.pilot_of))
	var pr := Content.production(suit)
	if not is_suit_def(suit) or pr.is_empty() \
			or not (Content.building(String(g.def)).get("produces", []) as Array).has(suit):
		out.reason = "This garage cannot build that suit."
		return out
	var gate := PData.production_reason(w, fid, suit)
	if gate == "":
		gate = can_produce(w, fid, suit)
	if gate != "":
		out.reason = "%s: %s." % [String(pr.get("name", suit)), gate]
		return out
	var mult := float(Content.building(String(g.def)).get("resuit_cost_mult", cfg().get("resuit_cost_mult", 0.6)))
	var pc: Dictionary = pr.get("cost", {})
	for k in pc:
		var v := roundi(float(pc[k]) * mult)
		if v > 0:
			out.cost[k] = v
	var f: Dictionary = w.factions[fid]
	var dpop := int(Content.unit(suit).get("pop", 1)) - int(Content.unit(String(p.def)).get("pop", 1))
	if dpop > 0 and int(f.get("pop", 0)) + dpop > int(f.get("pop_cap", 0)):
		out.reason = "Not enough population room for the suit."
		return out
	out.pilot = int(p.id)
	out.garage = int(g.id)
	out.suit = suit
	out.pop_delta = dpop
	out.reason = w.can_afford(fid, out.cost)
	return out


## The pilot climbs into a new suit beside the garage (the pilot entity is removed, not counted as a loss).
static func _resuit(w: SimWorld, fid: int, pr: Dictionary) -> void:
	var g: Dictionary = w.entities[int(pr.garage)]
	var p: Dictionary = w.entities[int(pr.pilot)]
	var suit := String(pr.suit)
	var mc := String(Content.unit(suit).get("move_class", "foot"))
	var c := Vector2(g.cell) + Vector2(float(g.size), float(g.size)) * 0.5 + Vector2(float(g.size) * 0.5 + 1.0, 0.0)
	var pos := Vector2(SimWorld.Movement.nearest_free_cell(w, w.cell_of(c), mc)) + Vector2(0.5, 0.5)
	var pid := int(p.id)
	Loadouts.forget(w, p)
	w.destroy(pid, "resuit")
	var f: Dictionary = w.factions[fid]
	if f.has("stats") and (f.stats as Dictionary).has("lost"):
		f.stats.lost = maxi(int(f.stats.lost) - 1, 0)   # climbing back in is not a loss
	var sid := w.spawn_unit(suit, fid, pos)
	f.pop = int(f.get("pop", 0)) + int(pr.pop_delta)   # Economy recomputes next tick (as Production does)
	var st := _st(w)
	st.resuited = int(st.resuited) + 1
	w.emit("Resuited", {"owner": fid, "pilot": pid, "id": sid, "suit": suit, "garage": int(g.id), "cost": pr.cost})
