extends RefCounted
## Companies, armies and the chain of command (owner: ARMY6). CONTRACTS_G6 sections 3.5, 4, 5.2, 6, 8.
## Commands: train_company, train_commander, form_army, disband_army, set_company_refill.
## Numbers: content/g6/rules_companies.json -> Content.rules().g6_companies (PROVISIONAL).
##
## Saved state (hashed): w.sys_state.companies = {companies: {cid: company}, armies: {aid: army},
##   custom: {fid: {name: template}}, training: [entry], refill: [entry], next_cid, next_aid, next_tid, ver}
##   company  = {id, owner, template, name, size, captain, platoons: [gid], refill, army, losses,
##               elements: [{id, item, units: [uid], platoon: gid}], next_eid, confused_until, hq}
##   army     = {id, owner, commander, companies: [cid]}
##   training = {id, owner, hq, kind: "company"|"commander", template, tdef, scaled, size, plan,
##               progress, paid}  (one active entry per HQ, list order)
##   refill   = {id, owner, company, item, platoon, paid ({} until paid), progress} (one per side)
## Entity fields: e.company (cid), e.platoon (gid), e.element (element id inside its company),
##   e.rank_role ("captain" | "lieutenant" | "commander").
## A template slot names a PRODUCTION item; one item = one element (a squad counts once).
## Platoons are G2 ops groups (ops.gd) with parent_company = cid whose officer is the lieutenant.
## Losses are found in tick() (and at once from on_destroyed when G6Hooks is wired): a lost element
## counts in losses (+ a refill request when refill is on); captain death -> field promotion of the
## senior lieutenant (confusion, morale hit); Commander death -> ArmySplit. A lieutenant's death is
## handled in Ops.prune (the next squad leader takes the platoon).
## Do not preload g6_hooks.gd, production.gd or construction.gd here (cycles: construction calls can_build).

const Ops = preload("res://sim/systems/ops.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Transport = preload("res://sim/systems/transport.gd")
const PData = preload("res://sim/systems/progression_data.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Economy = preload("res://sim/systems/economy.gd")  # G6 ORCH: per-side supply cap max (Company HQ -> 200)
const MachineG6 = preload("res://sim/systems/machine_g6.gd")  # G6 ORCH (MECH6b CR): Overmind = global Coordinator range

const VER := 1
const ROLES := ["captain", "lieutenant", "commander"]
const LEDGER := ["credits", "salvage", "ore", "fuel", "ammo"]
const MORALE_DT := 0.2  # Morale updates every 4 ticks at 20 Hz (morale.gd UPDATE_EVERY)


static func rules() -> Dictionary:
	return Content.rules().get("g6_companies", {})


## Mutable state (creates it). Readers that must not mutate use _st().
static func state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("companies"):
		w.sys_state["companies"] = {"companies": {}, "armies": {}, "custom": {}, "training": [], "refill": [],
			"next_cid": 1, "next_aid": 1, "next_tid": 1, "ver": VER}
	return w.sys_state["companies"]


static func _st(w: SimWorld) -> Dictionary:
	return w.sys_state.get("companies", {})


static func _sorted(d: Dictionary) -> Array:
	var ks: Array = d.keys()
	ks.sort()
	return ks


# ================================================================ faction / leaders
static func faction_of(w: SimWorld, fid: int) -> String:
	if w == null or not w.factions.has(fid):
		return ""
	return String(w.factions[fid].get("faction_def", ""))


## fid may be a side id (needs w) or a faction def id ("human_a").
static func _faction_arg(fid, w: SimWorld) -> String:
	if typeof(fid) == TYPE_STRING or typeof(fid) == TYPE_STRING_NAME:
		return String(fid)
	return faction_of(w, int(fid))


static func leaders(faction: String) -> Dictionary:
	return rules().get("leaders", {}).get(faction, {})


## Unit def for a leader role; falls back to the faction officer until CONTENT6 defines the leader.
static func leader_def(faction: String, role: String) -> String:
	var l := leaders(faction)
	var d := String(l.get(role, ""))
	if d == "" or Content.unit(d).is_empty():
		d = String(l.get("fallback", ""))
	return d


static func is_leader_def(def_id: String) -> bool:
	var all: Dictionary = rules().get("leaders", {})
	for f in _sorted(all):
		for r in ROLES:
			if String(all[f].get(r, "")) == def_id:
				return true
	return false


static func is_hq_def(def_id: String) -> bool:
	if bool(Content.building(def_id).get("company_hq", false)):
		return true
	var all: Dictionary = rules().get("leaders", {})
	for f in _sorted(all):
		if String(all[f].get("hq", "")) == def_id:
			return true
	return false


## The side's Company HQ entity (built or not), or {}.
static func hq_of(w: SimWorld, fid: int) -> Dictionary:
	for b in SimIndex.of(w, "building"):
		if int(b.owner) == fid and SimIndex.alive(w, b) and is_hq_def(String(b.def)):
			return b
	return {}


static func _leader_cost(def_id: String, role: String) -> Dictionary:
	var p := Content.production(def_id)
	if p.has("cost"):
		return p.cost
	return rules().get("leader_cost", {}).get(role, {})


static func _leader_time(def_id: String, role: String) -> float:
	var p := Content.production(def_id)
	if p.has("train_time"):
		return float(p.train_time)
	return float(rules().get("leader_time", {}).get(role, 12))


# ================================================================ templates
static func presets() -> Dictionary:
	return rules().get("templates", {})


## Preset + custom template ids for a side ("custom:<name>" needs w and an int side id).
## fid may also be a faction def id. Preset ids first (ascending), then custom (ascending).
static func templates_for(fid, w: SimWorld = null) -> Array:
	var faction := _faction_arg(fid, w)
	var out := []
	var ps := presets()
	for id in _sorted(ps):
		if String(ps[id].get("faction", "")) == faction:
			out.append(String(id))
	if w != null and typeof(fid) == TYPE_INT:
		var cu: Dictionary = _st(w).get("custom", {}).get(int(fid), {})
		for n in _sorted(cu):
			out.append("custom:" + String(n))
	return out


## Template dict by id for side fid ({} when unknown or another faction's preset).
static func template(w: SimWorld, fid: int, tid: String) -> Dictionary:
	if tid.begins_with("custom:"):
		return _st(w).get("custom", {}).get(fid, {}).get(tid.substr(7), {})
	var t: Dictionary = presets().get(tid, {})
	if t.is_empty() or String(t.get("faction", "")) != faction_of(w, fid):
		return {}
	return t


## The production item a slot uses now: def when it exists and is available to the side, else alt.
static func _slot_item(w: SimWorld, fid: int, slot: Dictionary) -> String:
	var d := String(slot.get("def", ""))
	var alt := String(slot.get("alt", ""))
	for cand in [d, alt]:
		if cand == "" or Content.production(cand).is_empty():
			continue
		if w == null or not w.factions.has(fid) or PData.production_reason(w, fid, cand) == "":
			return cand
	if not Content.production(d).is_empty() or alt == "":
		return d
	return alt


## Element item list (template order). Presets scale by size_mult; custom templates are exact.
static func elements_of(w: SimWorld, fid: int, t: Dictionary, size: String, scaled: bool) -> Array:
	var mult := int(rules().get("size_mult", {}).get(size, 1)) if scaled else 1
	var out := []
	for slot in t.get("slots", []):
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		var item := _slot_item(w, fid, slot)
		for i in maxi(int(slot.get("count", 0)), 0) * mult:
			out.append(item)
	return out


## "" when a custom template is legal (exact counts), else the reason. fid: side id (with w, also
## checks stage/research) or faction def id.
static func validate_template(fid, t, w: SimWorld = null) -> String:
	return _validate(w, fid, t, 1)


static func _validate(w: SimWorld, fid, t, mult: int) -> String:
	if typeof(t) != TYPE_DICTIONARY:
		return "A company template must be a dictionary."
	var faction := _faction_arg(fid, w)
	var side := int(fid) if typeof(fid) == TYPE_INT else -1
	if t.has("faction") and faction != "" and String(t.faction) != faction:
		return "This template belongs to another faction."
	var slots = t.get("slots", [])
	if typeof(slots) != TYPE_ARRAY or (slots as Array).is_empty():
		return "A company needs at least one platoon (add a unit slot)."
	var total := 0
	var excl: Array = rules().get("excluded_move_classes", [])
	for slot in slots:
		if typeof(slot) != TYPE_DICTIONARY:
			return "Invalid template slot."
		var n := int(slot.get("count", 0))
		if n < 1:
			return "Every slot needs a count of at least 1."
		var item := _slot_item(w, side, slot)
		var p := Content.production(item)
		if p.is_empty():
			return "Unknown unit '%s'." % item
		var pname := String(p.get("name", item))
		var pf := String(p.get("faction", ""))
		if faction != "" and pf != "" and pf != "shared" and pf != faction:
			return "%s belongs to another faction." % pname
		if is_leader_def(item):
			return "Leaders join a company automatically; remove %s." % pname
		for u in p.get("spawns", []):
			var ud := Content.unit(String(u))
			if bool(ud.get("is_officer", false)) or is_leader_def(String(u)):
				return "Officers lead a company; they cannot fill a slot (%s)." % pname
			if excl.has(String(ud.get("move_class", ""))):
				return "%s cannot serve in a company (aircraft and ships train at their own facility)." % pname
		if w != null and w.factions.has(side):
			var gate := PData.production_reason(w, side, item)
			if gate != "":
				return "%s: %s." % [pname, gate]
		total += n * mult
	var cap := int(rules().get("element_cap", 45))
	if total > cap:
		return "A company holds at most %d elements (this one has %d)." % [cap, total]
	if total < 1:
		return "A company needs at least one platoon."
	return ""


## Training plan: {elements: [item], platoons, leaders: [{role, def}], cost, pop, time (s)}.
## Cost and pop = sum of every member incl. leaders (D28); time = slowest member x time_mult.
static func plan(w: SimWorld, fid: int, t: Dictionary, size: String, scaled: bool) -> Dictionary:
	var faction := faction_of(w, fid)
	var els := elements_of(w, fid, t, size, scaled)
	var pmax := maxi(int(rules().get("platoon_max", 15)), 1)
	var npl := maxi(int(ceil(float(els.size()) / float(pmax))), 1)
	var lead := [{"role": "captain", "def": leader_def(faction, "captain")}]
	for i in npl:
		lead.append({"role": "lieutenant", "def": leader_def(faction, "lieutenant")})
	var cost := {}
	for k in LEDGER:
		cost[k] = 0
	var pop := 0
	var slow := 0.0
	for item in els:
		var p := Content.production(String(item))
		for k in LEDGER:
			cost[k] = int(cost[k]) + int(p.get("cost", {}).get(k, 0))
		for u in p.get("spawns", []):
			pop += int(Content.unit(String(u)).get("pop", 1))
		slow = maxf(slow, float(p.get("train_time", 0)))
	for l in lead:
		var lc := _leader_cost(String(l.def), String(l.role))
		for k in LEDGER:
			cost[k] = int(cost[k]) + int(lc.get(k, 0))
		pop += int(Content.unit(String(l.def)).get("pop", 1))
		slow = maxf(slow, _leader_time(String(l.def), String(l.role)))
	return {"elements": els, "platoons": npl, "leaders": lead, "cost": cost, "pop": pop,
		"time": slow * float(rules().get("time_mult", 1.25))}


# ================================================================ queries (UI / AI)
## The company a unit belongs to (member or leader), or {}.
static func company_of(w: SimWorld, uid: int) -> Dictionary:
	var e = w.entities.get(uid)
	if e == null or not e.has("company"):
		return {}
	return _st(w).get("companies", {}).get(int(e.company), {})


## The army a unit belongs to (its Commander, or a member of one of its companies), or {}.
static func army_of(w: SimWorld, uid: int) -> Dictionary:
	var armies: Dictionary = _st(w).get("armies", {})
	for aid in _sorted(armies):
		if int(armies[aid].commander) == uid:
			return armies[aid]
	var c := company_of(w, uid)
	if c.is_empty() or int(c.get("army", -1)) < 0:
		return {}
	return armies.get(int(c.army), {})


## Companies of a side (ascending id).
static func companies_of(w: SimWorld, fid: int) -> Array:
	var cs: Dictionary = _st(w).get("companies", {})
	var out := []
	for cid in _sorted(cs):
		if int(cs[cid].owner) == fid:
			out.append(cs[cid])
	return out


## Armies of a side (ascending id).
static func armies_of(w: SimWorld, fid: int) -> Array:
	var a: Dictionary = _st(w).get("armies", {})
	var out := []
	for aid in _sorted(a):
		if int(a[aid].owner) == fid:
			out.append(a[aid])
	return out


## Every unit id of a company: captain, lieutenants, members (alive ones only).
static func units_of(w: SimWorld, c: Dictionary) -> Array:
	var out := []
	if w.entities.has(int(c.get("captain", -1))):
		out.append(int(c.captain))
	var groups: Dictionary = w.sys_state.get("ops", {}).get("groups", {})
	for gid in c.get("platoons", []):
		var g: Dictionary = groups.get(int(gid), {})
		if not g.is_empty() and w.entities.has(int(g.officer)) and not out.has(int(g.officer)):
			out.append(int(g.officer))
	for el in c.get("elements", []):
		for u in el.units:
			if w.entities.has(int(u)):
				out.append(int(u))
	return out


## Commanders of a side alive now, ascending id.
static func commanders_of(w: SimWorld, fid: int) -> Array:
	var out := []
	for e in SimIndex.of(w, "unit"):
		if int(e.owner) == fid and String(e.get("rank_role", "")) == "commander" and SimIndex.alive(w, e):
			out.append(int(e.id))
	out.sort()
	return out


## True when e is within cohesion_radius of its company captain.
static func in_cohesion(w: SimWorld, e: Dictionary) -> bool:
	if not e.has("company") or not w.sys_state.has("companies"):
		return false
	var c: Dictionary = w.sys_state.companies.companies.get(int(e.company), {})
	if c.is_empty():
		return false
	var cap = w.entities.get(int(c.captain))
	if cap == null:
		return false
	var r := float(rules().get("cohesion_radius", 12)) * research_mult(w, int(e.owner), "cohesion_radius_mult")
	if (e.pos as Vector2).distance_squared_to(cap.pos) <= r * r:
		return true
	# CONTRACTS_G6 section 10: a built, powered Overmind Uplink gives its Machine side global Coordinator
	# range, so every company unit of that side is in cohesion (checked only outside the normal radius).
	return MachineG6.overmind_online(w, int(e.owner))


## Research effect owned by ARMY6 (CONTRACTS_G6 3.3): g6_company_drills_1 -> cohesion_radius_mult,
## g6_command_net_1 -> confusion_time_mult (value from research.json). 1.0 until researched.
static func research_mult(w: SimWorld, fid: int, effect: String) -> float:
	var rid := String(rules().get("research", {}).get(effect, ""))
	if rid == "" or not w.factions.has(fid):
		return 1.0
	if not (w.factions[fid].get("research", {}).get("done", []) as Array).has(rid):
		return 1.0
	return float(Content.research(rid).get("value", 1.0))


## Platoon officers (lieutenants) of a company in platoon order: the captain's chain for missions.
static func platoon_officers(w: SimWorld, c: Dictionary) -> Array:
	var out := []
	var groups: Dictionary = w.sys_state.get("ops", {}).get("groups", {})
	for gid in c.get("platoons", []):
		if groups.has(int(gid)) and w.entities.has(int(groups[int(gid)].officer)):
			out.append(int(groups[int(gid)].officer))
	return out


# ================================================================ G6Hooks delegates / gates
## Production gate for company-only defs ("" = ok). Captains and lieutenants never train alone; a
## Commander may also be queued as a normal item at the HQ while fewer than max_commanders exist.
static func can_produce(w: SimWorld, fid: int, def_id: String) -> String:
	if not is_leader_def(def_id):
		return ""
	if is_commander_def(def_id):
		if commanders_pending(w, fid) >= int(rules().get("max_commanders", 2)):
			return "At most %d Commanders at a time" % int(rules().get("max_commanders", 2))
		return ""
	return "Leaders are trained with a company at the Company HQ"


static func is_commander_def(def_id: String) -> bool:
	var all: Dictionary = rules().get("leaders", {})
	for f in _sorted(all):
		if String(all[f].get("commander", "")) == def_id:
			return true
	return false


## Commanders alive + queued (train_commander entries and HQ production queue items).
static func commanders_pending(w: SimWorld, fid: int) -> int:
	var n := commanders_of(w, fid).size()
	for t in _st(w).get("training", []):
		if int(t.owner) == fid and String(t.kind) == "commander":
			n += 1
	var b := hq_of(w, fid)
	if not b.is_empty():
		for q in b.get("queue", []):
			if is_commander_def(String(q.get("item", ""))):
				n += 1
	return n


## Construction gate (CR to MECH6a): one Company HQ per side at a time (D31). "" = ok.
static func can_build(w: SimWorld, fid: int, def_id: String) -> String:
	if is_hq_def(def_id) and not hq_of(w, fid).is_empty():
		return "Only one Company HQ per side at a time"
	return ""


## Accuracy factor from company cohesion (G6Hooks.accuracy_mult): +10% within 12 tiles of the captain.
static func cohesion_acc(w: SimWorld, src: Dictionary) -> float:
	if not src.has("company"):
		return 1.0
	return float(rules().get("cohesion_acc", 1.1)) if in_cohesion(w, src) else 1.0


## Morale delta per morale update from cohesion (G6Hooks.morale_delta). D29's "+10 morale" is a
## recovery of cohesion_morale_per_s while in cohesion and below the unit's maximum morale.
static func cohesion_morale(w: SimWorld, e: Dictionary) -> float:
	if not e.has("company") or not e.has("morale"):
		return 0.0
	if float(e.morale) >= float(Content.unit(String(e.def)).get("morale", 100)):
		return 0.0
	return float(rules().get("cohesion_morale_per_s", 2.0)) * MORALE_DT if in_cohesion(w, e) else 0.0


# ================================================================ commands
static func _hq_reason(w: SimWorld, fid: int, b) -> String:
	if b == null or b.kind != "building" or int(b.owner) != fid:
		return "Select your Company HQ."
	if not is_hq_def(String(b.def)):
		return "Companies and Commanders train at a Company HQ."
	if not b.built:
		return "The Company HQ is still under construction."
	return ""


static func _queued(w: SimWorld, hq_id: int) -> int:
	var n := 0
	for t in _st(w).get("training", []):
		if int(t.hq) == hq_id:
			n += 1
	return n


## {t, scaled, tid, reason} for a train_company template field (id or custom dict).
static func _resolve_template(w: SimWorld, fid: int, tv) -> Dictionary:
	if typeof(tv) == TYPE_DICTIONARY:
		var name := String(tv.get("name", "custom"))
		return {"t": tv, "scaled": false, "tid": "custom:" + name, "reason": ""}
	var tid := String(tv) if tv != null else ""
	var t := template(w, fid, tid)
	if t.is_empty():
		if presets().has(tid):
			return {"reason": "That company template belongs to another faction."}
		return {"reason": "Unknown company template '%s'." % tid}
	return {"t": t, "scaled": not tid.begins_with("custom:"), "tid": tid, "reason": ""}


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.issuer)
	var st := _st(w)
	var R := rules()
	match String(cmd.type):
		"train_company":
			var b = w.entities.get(int(cmd.get("building_id", -1)))
			var r := _hq_reason(w, fid, b)
			if r != "":
				return r
			var size := String(cmd.get("size", "company"))
			if not (R.get("sizes", []) as Array).has(size):
				return "Company size must be platoon, company or battalion."
			var res := _resolve_template(w, fid, cmd.get("template"))
			if String(res.reason) != "":
				return String(res.reason)
			var mult := int(R.get("size_mult", {}).get(size, 1)) if bool(res.scaled) else 1
			r = _validate(w, fid, res.t, mult)
			if r != "":
				return r
			if _queued(w, int(b.id)) >= int(R.get("queue_max", 3)):
				return "The Company HQ queue is full (%d)." % int(R.get("queue_max", 3))
			var pl := plan(w, fid, res.t, size, bool(res.scaled))
			var cap_max := Economy.cap_max_for(w, fid)  # 200 with a built Company HQ, else rules.pop_cap_max
			if int(pl.pop) > cap_max:
				return "This company needs %d supply; the supply cap is %d." % [int(pl.pop), cap_max]
			return w.can_afford(fid, pl.cost)
		"train_commander":
			var b = w.entities.get(int(cmd.get("building_id", -1)))
			var r := _hq_reason(w, fid, b)
			if r != "":
				return r
			var cdef := leader_def(faction_of(w, fid), "commander")
			if cdef == "" or Content.unit(cdef).is_empty():
				return "This faction has no Commander."
			if commanders_pending(w, fid) >= int(R.get("max_commanders", 2)):
				return "At most %d Commanders at a time." % int(R.get("max_commanders", 2))
			if _queued(w, int(b.id)) >= int(R.get("queue_max", 3)):
				return "The Company HQ queue is full (%d)." % int(R.get("queue_max", 3))
			return w.can_afford(fid, _leader_cost(cdef, "commander"))
		"form_army":
			var c = w.entities.get(int(cmd.get("commander_id", -1)))
			if c == null or c.kind != "unit" or int(c.owner) != fid or String(c.get("rank_role", "")) != "commander":
				return "Select one of your Commanders."
			if not army_of(w, int(c.id)).is_empty():
				return "This Commander already leads an army."
			var ids := []
			for raw in cmd.get("company_ids", []):
				if not ids.has(int(raw)):
					ids.append(int(raw))
			if ids.size() < int(R.get("army_min", 2)) or ids.size() > int(R.get("army_max", 4)):
				return "An army needs %d to %d companies." % [int(R.get("army_min", 2)), int(R.get("army_max", 4))]
			var cs: Dictionary = st.get("companies", {})
			for cid in ids:
				var co: Dictionary = cs.get(cid, {})
				if co.is_empty() or int(co.owner) != fid:
					return "Select companies you command."
				if int(co.get("army", -1)) >= 0:
					return "%s is already part of an army." % String(co.get("name", "A company"))
			if armies_of(w, fid).size() >= int(R.get("max_armies", 2)):
				return "At most %d armies at a time." % int(R.get("max_armies", 2))
			return ""
		"disband_army":
			var a: Dictionary = st.get("armies", {}).get(int(cmd.get("army_id", -1)), {})
			if a.is_empty() or int(a.owner) != fid:
				return "Select one of your armies."
			return ""
		"set_company_refill":
			var co: Dictionary = st.get("companies", {}).get(int(cmd.get("company_id", -1)), {})
			if co.is_empty() or int(co.owner) != fid:
				return "Select one of your companies."
			return ""
	return "Unknown company command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	var st := state(w)
	match String(cmd.type):
		"train_company":
			var b: Dictionary = w.entities[int(cmd.building_id)]
			var size := String(cmd.get("size", "company"))
			var res := _resolve_template(w, fid, cmd.get("template"))
			var pl := plan(w, fid, res.t, size, bool(res.scaled))
			if not w.spend(fid, pl.cost, "train_company:" + String(res.tid)):
				return
			if typeof(cmd.get("template")) == TYPE_DICTIONARY:
				if not st.custom.has(fid):
					st.custom[fid] = {}
				var tdef: Dictionary = (res.t as Dictionary).duplicate(true)
				tdef.faction = faction_of(w, fid)
				st.custom[fid][String(res.tid).substr(7)] = tdef
			var tid := int(st.next_tid)
			st.next_tid = tid + 1
			st.training.append({"id": tid, "owner": fid, "hq": int(b.id), "kind": "company", "template": String(res.tid),
				"tdef": (res.t as Dictionary).duplicate(true), "scaled": bool(res.scaled), "size": size, "plan": pl,
				"progress": 0.0, "paid": pl.cost})
			w.emit("CompanyQueued", {"building_id": int(b.id), "owner": fid, "template": String(res.tid), "size": size,
				"entry": tid})
		"train_commander":
			var b: Dictionary = w.entities[int(cmd.building_id)]
			var cdef := leader_def(faction_of(w, fid), "commander")
			var cost := _leader_cost(cdef, "commander")
			if not w.spend(fid, cost, "train_commander"):
				return
			var tid := int(st.next_tid)
			st.next_tid = tid + 1
			st.training.append({"id": tid, "owner": fid, "hq": int(b.id), "kind": "commander", "template": cdef,
				"size": "", "plan": {"time": _leader_time(cdef, "commander"),
				"pop": int(Content.unit(cdef).get("pop", 1)), "cost": cost}, "progress": 0.0, "paid": cost})
			w.emit("CommanderQueued", {"building_id": int(b.id), "owner": fid, "entry": tid})
		"form_army":
			var aid := int(st.next_aid)
			st.next_aid = aid + 1
			var ids := []
			for raw in cmd.company_ids:
				if not ids.has(int(raw)):
					ids.append(int(raw))
			st.armies[aid] = {"id": aid, "owner": fid, "commander": int(cmd.commander_id), "companies": ids}
			for cid in ids:
				st.companies[cid].army = aid
			w.emit("ArmyFormed", {"army_id": aid, "owner": fid, "commander": int(cmd.commander_id), "companies": ids.duplicate()})
		"disband_army":
			var aid := int(cmd.army_id)
			_end_army(w, st, aid, "ArmyDisbanded")
		"set_company_refill":
			var co: Dictionary = st.companies[int(cmd.company_id)]
			co.refill = bool(cmd.get("on", true))
			if not co.refill:
				st.refill = (st.refill as Array).filter(func(r) -> bool:
					return int(r.company) != int(co.id) or not (r.paid as Dictionary).is_empty())
			w.emit("CompanyRefillSet", {"company_id": int(co.id), "owner": fid, "on": bool(co.refill)})


static func _end_army(w: SimWorld, st: Dictionary, aid: int, ev: String) -> void:
	var a: Dictionary = st.armies.get(aid, {})
	if a.is_empty():
		return
	for cid in a.companies:
		if st.companies.has(int(cid)):
			st.companies[int(cid)].army = -1
	st.armies.erase(aid)
	w.emit(ev, {"army_id": aid, "owner": int(a.owner), "commander": int(a.commander), "companies": (a.companies as Array).duplicate()})


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	if not w.sys_state.has("companies"):
		return
	var st: Dictionary = w.sys_state.companies
	_tick_training(w, st)
	_tick_refill(w, st)
	# the loss pass is idempotent: skip it while no entity spawned, died or entered cargo (runtime key)
	var key := [int(w.next_id), w.entities.size(), (st.companies as Dictionary).size(), (st.armies as Dictionary).size()]
	if w.cache.get("companies_prune_key") == key:
		return
	_prune(w, st, -1)
	w.cache["companies_prune_key"] = [int(w.next_id), w.entities.size(), (st.companies as Dictionary).size(), (st.armies as Dictionary).size()]


static func _blocked(w: SimWorld, b: Dictionary, pop: int) -> String:
	var f: Dictionary = w.factions[int(b.owner)]
	if bool(Content.building(b.def).get("requires_power", false)) and int(f.power_use) > int(f.power_prod):
		return "LOW_POWER"
	if int(f.pop) + pop > int(f.pop_cap):
		return "SUPPLY_CAP"
	return ""


## One active entry per HQ (the first in list order); entries of a lost HQ are dropped.
static func _tick_training(w: SimWorld, st: Dictionary) -> void:
	if (st.training as Array).is_empty():
		return
	var seen := {}
	var keep := []
	var done := []
	for t in st.training:
		var b = w.entities.get(int(t.hq))
		if b == null or b.kind != "building" or int(b.owner) != int(t.owner):
			w.emit("CompanyTrainingLost", {"entry": int(t.id), "owner": int(t.owner), "kind": String(t.kind)})
			continue
		keep.append(t)
		if seen.has(int(t.hq)):
			continue
		seen[int(t.hq)] = true
		var pl: Dictionary = t.plan
		var p := float(t.progress)
		if p < 1.0 - 0.000001:
			p += SimWorld.DT / maxf(float(pl.time), 0.001)
			t.progress = minf(p, 1.0)
		if float(t.progress) >= 1.0 - 0.000001:
			var why := _blocked(w, b, int(pl.pop))
			if why == "":
				done.append(t)
			elif String(t.get("status", "")) != why:
				t.status = why
				w.emit("CompanyTrainingBlocked", {"entry": int(t.id), "building_id": int(b.id), "owner": int(t.owner), "reason": why})
	for t in done:
		keep.erase(t)
	st.training = keep
	for t in done:
		var b: Dictionary = w.entities[int(t.hq)]
		if String(t.kind) == "commander":
			_spawn_commander(w, b, t)
		else:
			_spawn_company(w, st, b, t)


## Free passable cells around the HQ for move class mc, nearest the rally point first.
static func _cells(w: SimWorld, b: Dictionary, mc: String, need: int) -> Array:
	var rally: Vector2 = b.get("rally", b.pos)
	var occ := {}
	for o in SimIndex.of(w, "building"):
		if SimIndex.alive(w, o):
			for y in range(o.cell.y, o.cell.y + int(o.size)):
				for x in range(o.cell.x, o.cell.x + int(o.size)):
					occ[Vector2i(x, y)] = true
	var cands := []
	for margin in range(1, 9):
		for c in _ring(b.cell, int(b.size), margin):
			if not w.in_bounds(c) or occ.has(c) or not Movement.is_passable(w, c, mc):
				continue
			cands.append({"c": c, "m": margin, "d": (Vector2(c) + Movement.CENTER).distance_squared_to(rally)})
		if cands.size() >= need:
			break
	cands.sort_custom(func(a, bb):
		if a.m != bb.m:
			return a.m < bb.m
		if a.d != bb.d:
			return a.d < bb.d
		if a.c.y != bb.c.y:
			return a.c.y < bb.c.y
		return a.c.x < bb.c.x)
	var out := []
	for k in cands:
		out.append(k.c)
	if out.is_empty():
		out.append(w.cell_of(b.pos))
	return out


## Cells of the square ring `margin` cells outside a footprint (row-major), as Construction.ring_cells.
static func _ring(cell: Vector2i, size: int, margin: int) -> Array:
	var out := []
	for y in range(cell.y - margin, cell.y + size + margin):
		for x in range(cell.x - margin, cell.x + size + margin):
			if x == cell.x - margin or x == cell.x + size + margin - 1 or y == cell.y - margin or y == cell.y + size + margin - 1:
				out.append(Vector2i(x, y))
	return out


## Spawns def next to HQ b using a per-move-class cell cursor (ctx = {mc: {cells, i}}).
static func _spawn_at(w: SimWorld, b: Dictionary, def_id: String, fid: int, ctx: Dictionary, need: int) -> Dictionary:
	var mc := String(Content.unit(def_id).get("move_class", "foot"))
	if not ctx.has(mc):
		ctx[mc] = {"cells": _cells(w, b, mc, need), "i": 0}
	var cur: Dictionary = ctx[mc]
	var c: Vector2i = cur.cells[int(cur.i) % (cur.cells as Array).size()]
	cur.i = int(cur.i) + 1
	var uid := w.spawn_unit(def_id, fid, Vector2(c) + Movement.CENTER)
	var u: Dictionary = w.entities[uid]
	var rally: Vector2 = b.get("rally", b.pos)
	u.facing = (rally - u.pos).angle() if rally.distance_to(u.pos) > 0.01 else 0.0
	w.factions[fid].stats.trained += 1
	return u


static func _next_squad(w: SimWorld) -> int:
	var pst: Dictionary = w.sys_state.get("production", {"next_squad": 1})
	var squad := int(pst.next_squad)
	pst.next_squad = squad + 1
	w.sys_state["production"] = pst
	return squad


static func _spawn_commander(w: SimWorld, b: Dictionary, t: Dictionary) -> void:
	var fid := int(t.owner)
	var u := _spawn_at(w, b, String(t.template), fid, {}, 1)
	u.rank_role = "commander"
	w.factions[fid].pop = int(w.factions[fid].pop) + int(t.plan.pop)
	w.emit("CommanderTrained", {"building_id": int(b.id), "owner": fid, "unit_id": int(u.id)})


static func _spawn_company(w: SimWorld, st: Dictionary, b: Dictionary, t: Dictionary) -> void:
	var fid := int(t.owner)
	var pl: Dictionary = t.plan
	var els: Array = pl.elements
	var npl := maxi(int(pl.platoons), 1)
	var cid := int(st.next_cid)
	st.next_cid = cid + 1
	var ost := Ops.state(w)
	var need := els.size() * 2 + npl + 1
	var ctx := {}
	var ids := []
	var cap := _spawn_at(w, b, String(pl.leaders[0].def), fid, ctx, need)
	cap.rank_role = "captain"
	cap.company = cid
	ids.append(int(cap.id))
	var gids := []
	var groups := []
	for k in npl:
		var lt := _spawn_at(w, b, String(pl.leaders[k + 1].def), fid, ctx, need)
		lt.rank_role = "lieutenant"
		lt.company = cid
		var gid := int(ost.next_gid)
		ost.next_gid = gid + 1
		lt.platoon = gid
		var g := {"id": gid, "owner": fid, "officer": int(lt.id), "members": [], "mission": {}, "phase": "idle",
			"reason": "", "progress": 0.0, "history": [], "phase_tick": w.tick, "last_report": w.tick, "start": 0,
			"losses": 0, "secure_ticks": 0, "resume": "", "result": "", "parent_company": cid}
		ost.groups[gid] = g
		gids.append(gid)
		groups.append(g)
		ids.append(int(lt.id))
	# elements are dealt round-robin so every platoon gets a similar mix (<= platoon_max each)
	var elements := []
	for i in els.size():
		var item := String(els[i])
		var g: Dictionary = groups[i % npl]
		var squad := _next_squad(w)
		var units := []
		for sdef in Content.production(item).get("spawns", []):
			var u := _spawn_at(w, b, String(sdef), fid, ctx, need)
			u.squad = squad
			u.company = cid
			u.platoon = int(g.id)
			u.element = i + 1
			units.append(int(u.id))
			g.members.append(int(u.id))
			ids.append(int(u.id))
		elements.append({"id": i + 1, "item": item, "units": units, "platoon": int(g.id)})
	var tname := String((t.get("tdef", {}) as Dictionary).get("name", "Company"))
	st.companies[cid] = {"id": cid, "owner": fid, "template": String(t.template), "name": "%s %d" % [tname, cid],
		"size": String(t.size), "captain": int(cap.id), "platoons": gids, "refill": false, "army": -1, "losses": 0,
		"elements": elements, "next_eid": els.size() + 1, "confused_until": 0, "hq": int(b.id)}
	for g in groups:
		g.reason = "Platoon formed with %d units." % (g.members as Array).size()
		Ops.report(w, g)
	w.factions[fid].pop = int(w.factions[fid].pop) + int(pl.pop)
	w.emit("CompanyTrained", {"company_id": cid, "building_id": int(b.id), "owner": fid, "unit_ids": ids,
		"template": String(t.template), "size": String(t.size)})


## One replacement in progress per side; it is paid when it starts (normal cost) and waits for money
## and for a built Company HQ.
static func _tick_refill(w: SimWorld, st: Dictionary) -> void:
	if (st.refill as Array).is_empty():
		return
	var seen := {}
	var done := []
	for r in st.refill:
		var fid := int(r.owner)
		if seen.has(fid):
			continue
		seen[fid] = true
		var b := hq_of(w, fid)
		if b.is_empty() or not b.built:
			continue
		var p := Content.production(String(r.item))
		if (r.paid as Dictionary).is_empty():
			if not w.spend(fid, p.get("cost", {}), "refill:" + String(r.item)):
				continue
			r.paid = (p.get("cost", {}) as Dictionary).duplicate()
		r.progress = minf(float(r.progress) + SimWorld.DT / maxf(float(p.get("train_time", 1.0)), 0.001), 1.0)
		var pop := 0
		for u in p.get("spawns", []):
			pop += int(Content.unit(String(u)).get("pop", 1))
		if float(r.progress) >= 1.0 - 0.000001 and _blocked(w, b, pop) == "":
			done.append(r)
	for r in done:
		st.refill.erase(r)
		_spawn_refill(w, st, hq_of(w, int(r.owner)), r)


static func _spawn_refill(w: SimWorld, st: Dictionary, b: Dictionary, r: Dictionary) -> void:
	var fid := int(r.owner)
	var item := String(r.item)
	var p := Content.production(item)
	var c: Dictionary = st.companies.get(int(r.company), {})
	var groups: Dictionary = w.sys_state.get("ops", {}).get("groups", {})
	var gid := int(r.platoon)
	if not groups.has(gid) or int(groups[gid].get("parent_company", -1)) != int(r.company):
		gid = -1
		for pg in c.get("platoons", []):
			if groups.has(int(pg)):
				gid = int(pg)
				break
	var target: Vector2 = b.pos
	if gid >= 0 and w.entities.has(int(groups[gid].officer)):
		target = w.entities[int(groups[gid].officer)].pos
	var eid := int(c.get("next_eid", 1))
	var squad := _next_squad(w)
	var units := []
	var pop := 0
	var ctx := {}
	for sdef in p.get("spawns", []):
		var u := _spawn_at(w, b, String(sdef), fid, ctx, (p.spawns as Array).size())
		pop += int(Content.unit(String(sdef)).get("pop", 1))
		u.squad = squad
		if not c.is_empty():
			u.company = int(c.id)
			u.element = eid
		if gid >= 0:
			u.platoon = gid
			groups[gid].members.append(int(u.id))
		u.order = {"type": "move", "target": target}
		Movement.order_path(w, u, target)
		units.append(int(u.id))
	if not c.is_empty():
		c.elements.append({"id": eid, "item": item, "units": units, "platoon": gid})
		c.next_eid = eid + 1
	w.factions[fid].pop = int(w.factions[fid].pop) + pop
	w.emit("CompanyRefilled", {"company_id": int(r.company), "owner": fid, "item": item, "unit_ids": units, "platoon": gid})


# ================================================================ losses / promotion
static func _alive(w: SimWorld, uid: int, dying: int) -> bool:
	if uid < 0 or uid == dying:
		return false
	var e = w.entities.get(uid)
	if e != null:
		return e.kind == "unit"
	return Transport.in_cargo(w, uid)


## Leader loss / promotion hook (G6Hooks.on_destroyed): runs the loss pass at once, e still present.
static func on_destroyed(w: SimWorld, e: Dictionary) -> void:
	if not w.sys_state.has("companies"):
		return
	if not e.has("company") and String(e.get("rank_role", "")) != "commander":
		return
	_prune(w, w.sys_state.companies, int(e.id))


## Loss pass (ascending ids). dying = an entity about to be removed (on_destroyed), else -1.
static func _prune(w: SimWorld, st: Dictionary, dying: int) -> void:
	var cs: Dictionary = st.companies
	var groups: Dictionary = w.sys_state.get("ops", {}).get("groups", {})
	var gone := []
	for cid in _sorted(cs):
		var c: Dictionary = cs[cid]
		var keep := []
		for el in c.elements:
			var alive := []
			for u in el.units:
				if _alive(w, int(u), dying):
					alive.append(int(u))
			if alive.size() != (el.units as Array).size():
				el.units = alive
			if not alive.is_empty():
				keep.append(el)
				continue
			c.losses = int(c.losses) + 1
			w.emit("CompanyElementLost", {"company_id": int(cid), "owner": int(c.owner), "item": String(el.item)})
			if bool(c.refill) and (st.refill as Array).size() < int(rules().get("refill_queue_max", 30)):
				var rid := int(st.next_tid)
				st.next_tid = rid + 1
				st.refill.append({"id": rid, "owner": int(c.owner), "company": int(cid), "item": String(el.item),
					"platoon": int(el.platoon), "paid": {}, "progress": 0.0})
		if keep.size() != (c.elements as Array).size():
			c.elements = keep
		var pls := []
		for gid in c.platoons:
			if groups.has(int(gid)):
				pls.append(int(gid))
		if pls.size() != (c.platoons as Array).size():
			c.platoons = pls
		if int(c.captain) >= 0 and not _alive(w, int(c.captain), dying):
			_promote(w, st, c, dying)
		if int(c.captain) < 0 and (c.elements as Array).is_empty() and (c.platoons as Array).is_empty():
			gone.append(cid)
	for cid in gone:
		var c: Dictionary = cs[cid]
		cs.erase(cid)
		w.emit("CompanyDestroyed", {"company_id": int(cid), "owner": int(c.owner), "army": int(c.army)})
	var armies: Dictionary = st.armies
	for aid in _sorted(armies):
		var a: Dictionary = armies[aid]
		if not _alive(w, int(a.commander), dying):
			_end_army(w, st, int(aid), "ArmySplit")
			continue
		var live := (a.companies as Array).filter(func(x) -> bool: return cs.has(int(x)))
		if live.size() != (a.companies as Array).size():
			a.companies = live
		if live.is_empty():
			_end_army(w, st, int(aid), "ArmyDisbanded")


## Captain lost: the senior lieutenant (first platoon with a live officer) becomes captain; his platoon
## goes to its next-senior squad leader, or is dropped when empty. Confusion + morale hit (D-8).
static func _promote(w: SimWorld, st: Dictionary, c: Dictionary, dying: int) -> void:
	var groups: Dictionary = w.sys_state.get("ops", {}).get("groups", {})
	var old := int(c.captain)
	var nc := -1
	var from_gid := -1
	for gid in c.platoons:
		var g = groups.get(int(gid))
		if g != null and int(g.officer) != dying and w.entities.has(int(g.officer)):
			nc = int(g.officer)
			from_gid = int(gid)
			break
	if nc < 0:
		for el in c.elements:
			for u in el.units:
				if int(u) != dying and w.entities.has(int(u)):
					nc = int(u)
					break
			if nc >= 0:
				break
	c.captain = nc
	if nc < 0:
		w.emit("CaptainKilled", {"company_id": int(c.id), "owner": int(c.owner), "old": old, "new": -1})
		return
	var e: Dictionary = w.entities[nc]
	e.rank_role = "captain"
	e.erase("platoon")
	if from_gid >= 0:
		var g: Dictionary = groups[from_gid]
		var nxt := -1
		for m in g.members:
			if int(m) != dying and w.entities.has(int(m)):
				nxt = int(m)
				break
		if nxt >= 0:
			g.officer = nxt
			g.members = (g.members as Array).filter(func(x) -> bool: return int(x) != nxt)
			w.entities[nxt].rank_role = "lieutenant"
		else:
			groups.erase(from_gid)
			c.platoons = (c.platoons as Array).filter(func(x) -> bool: return int(x) != from_gid)
	else:
		for gid in c.platoons:
			var g = groups.get(int(gid))
			if g != null:
				g.members = (g.members as Array).filter(func(x) -> bool: return int(x) != nc)
	c.confused_until = w.tick + int(float(rules().get("confusion_s", 10)) * SimWorld.TICK_RATE 		* research_mult(w, int(c.owner), "confusion_time_mult"))
	var hit := float(rules().get("promotion_morale", -15))
	for uid in units_of(w, c):
		var u: Dictionary = w.entities[uid]
		if u.has("morale") and int(uid) != dying:
			u.morale = clampf(float(u.morale) + hit, 0.0, float(Content.unit(String(u.def)).get("morale", 100)))
	w.emit("CaptainPromoted", {"company_id": int(c.id), "owner": int(c.owner), "old": old, "new": nc})


## True while a company is confused after losing its captain (no new orders).
static func confused(w: SimWorld, cid: int) -> bool:
	var c: Dictionary = _st(w).get("companies", {}).get(cid, {})
	return not c.is_empty() and int(c.get("confused_until", 0)) > w.tick
