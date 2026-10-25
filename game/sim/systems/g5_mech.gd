extends RefCounted
## G5Mech (owner: UNITS5). CONTRACTS_G5 sections 3.1, 4, 5, 6, 9. Runs after G4bMech each tick.
## Squads, the Drone Team (launched drones + tactical mode), heal auras. HMG deploy/pack and Special
## Forces concealment/charges reuse G4bMech (setup_ticks / conceal_still / can_charge def flags).
##
## Unit def flags (content/g5/units_g5.json):
##   squad_size n   one entity = n soldiers; hp = n x member hp. G5 entity fields: e.squad_size,
##                  e.squad_alive = ceil(hp / max_hp x n) (>= 1 while alive). A weakened squad fires
##                  slower: each shot's cooldown becomes full_cd x squad_size / squad_alive (e.sq_cd).
##   drone_team     G5 entity fields: e.drone_charges (def drone_charges, 4), e.dmode "drone"|"tactical",
##                  e.restock_t (ticks spent near a supply source), e.tact (running tactical order
##                  {ability, target, cell, t, tries}), e.infil_until, e.stacked, e.stack_until, e.tact_cd.
##                  launch_drone spends a charge and spawns a launched drone; at 0 charges dmode becomes
##                  "tactical". RESTOCK_TICKS near an own supply point (Supply sources: HQ, depot, supply
##                  truck) or restock_drones() refills the charges and sets dmode "drone".
##   launched_drone short-lived air_low unit (is_air; shootable by anti_air weapons). Flight state in
##                  w.sys_state.g5mech.drones {id: {owner_squad, type, t, goal, target}} (t = ticks left).
##                  Arrival: strike/frag hit the impact point (Human B: spread scatter from w.rng),
##                  recon loiters and marks enemies (e.marked_until, e.marked_team), emp disables enemy
##                  machines/electronics/turrets (e.emp_until, cooldown held) and downs enemy drones.
##                  A drone jammed by enemy EW (Status.is_jammed) crashes.
##   heal_aura      {radius, hp_per_sec, morale_per_sec, armor?|energy?}: every AURA_EVERY ticks friendly
##                  matching units in radius heal (Medical.is_wounded units excluded: SUPPORT's).
##   wounded_slots  ambulance / medic capacity, read by Medical (SUPPORT) through wounded_slots(e).
## Events: SquadLoss, DroneLaunched, DroneImpact, DroneLost, DroneJammed, TargetsMarked, EmpBurst,
##   DroneTeamTactical, DronesRestocked, Infiltrate, Takedown, Breach, StackedUp, FirstStrike, ArmoredAttack.
## Determinism: ascending ids, w.rng only (Human B spread), integer tick state, floats snapped to Q.
## G6 (owner: AIRDEF6, CONTRACTS_G6 section 12): a launched drone inside an enemy jamming field
##   (Counterdrone.jammed: m_jammer_obelisk, b_jammer_team) crashes like an EW-jammed one (DroneJammed).
##   Drone Control Center (a_drone_cc; bonuses computed by MECH6c's Callins.drone_cap_bonus / drone_range_mult /
##   drone_restock_mult): a drone team near a friendly DCC holds more charges (charge_cap), launches farther
##   (launch_range) and restocks faster (dcc_bonus). No DCC on the map = the G5 numbers exactly.

const Movement = preload("res://sim/systems/movement.gd")
const Damage = preload("res://sim/systems/damage.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Supply = preload("res://sim/systems/supply.gd")
const Status = preload("res://sim/systems/status.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const Medical = preload("res://sim/systems/medical.gd")
const Callins = preload("res://sim/systems/callins.gd")            # G6 MECH6c: Drone CC bonuses (preloads only SimIndex)
const Counterdrone = preload("res://sim/systems/counterdrone.gd")  # G6 AIRDEF6: jamming fields

const DRONE_TYPES := ["strike", "frag", "recon", "emp"]
const ABILITIES := ["infiltrate", "takedown", "breach", "stack_up", "armored_attack"]
const LAUNCH_RANGE := 20.0      # max distance team -> drone goal
const ARRIVE := 0.35
const RESTOCK_EVERY := 10
const RESTOCK_PHASE := 3
const RESTOCK_TICKS := 60
const AURA_EVERY := 20
const AURA_PHASE := 7
const SQUAD_EVERY := 4
const MARK_EVERY := 10
const INFIL_TICKS := 600
const STACK_TICKS := 40
const STACK_HOLD := 600
const BURST_R := 3.0
const TAKEDOWN_REACH := 1.2
const BREACH_REACH := 1.6
const BREACH_TICKS := 30
const AT_RANGE := 4.0
const TACT_COOLDOWN := 40
const Q := 1.0 / 1024.0

const M_SQUAD := 1
const M_DTEAM := 2
const M_AURA := 4


# ================================================================ public API (units5.api_ready)
static func drone_charges(e: Dictionary) -> int:
	if e.has("drone_charges"):
		return int(e.drone_charges)
	return int(Content.unit(String(e.get("def", ""))).get("drone_charges", 0))


## "drone" | "tactical" for a Drone Team ("" for any other unit).
static func mode(e: Dictionary) -> String:
	if not bool(Content.unit(String(e.get("def", ""))).get("drone_team", false)):
		return ""
	return String(e.get("dmode", "drone"))


## Refill a Drone Team's charges and return it to drone mode (supply source / Support truck).
static func restock_drones(w: SimWorld, e: Dictionary) -> void:
	var d := Content.unit(String(e.get("def", "")))
	if not bool(d.get("drone_team", false)):
		return
	e.drone_charges = charge_cap(w, e)
	e.dmode = "drone"
	e.restock_t = 0
	e.erase("tact")
	w.emit("DronesRestocked", {"id": int(e.id), "owner": int(e.owner), "charges": int(e.drone_charges)})


static func squad_size(e: Dictionary) -> int:
	return int(e.get("squad_size", Content.unit(String(e.get("def", ""))).get("squad_size", 1)))


static func squad_alive(e: Dictionary) -> int:
	return int(e.get("squad_alive", squad_size(e)))


## Wounded carry capacity of a med unit (ambulance A 6, B 4, medic team 2); 0 otherwise.
static func wounded_slots(e: Dictionary) -> int:
	return int(Content.unit(String(e.get("def", ""))).get("wounded_slots", 0))


## G6 (AIRDEF6 hook, MECH6c CR seq 436): Drone Control Center bonus for drone team e, from MECH6c's Callins
## (a friendly a_drone_cc in range; neutral with none): {charge_cap_bonus, range_mult, restock_mult}.
static func dcc_bonus(w: SimWorld, e: Dictionary) -> Dictionary:
	return {"charge_cap_bonus": Callins.drone_cap_bonus(w, e), "range_mult": Callins.drone_range_mult(w, e),
		"restock_mult": Callins.drone_restock_mult(w, e)}


## G6 (AIRDEF6): full charge count of drone team e (def drone_charges + DCC charge cap bonus).
static func charge_cap(w: SimWorld, e: Dictionary) -> int:
	return int(Content.unit(String(e.get("def", ""))).get("drone_charges", 4)) + Callins.drone_cap_bonus(w, e)


## G6 (AIRDEF6): max team -> drone goal distance (LAUNCH_RANGE x DCC range factor).
static func launch_range(w: SimWorld, e: Dictionary) -> float:
	return LAUNCH_RANGE * Callins.drone_range_mult(w, e)


static func is_launched_drone(e: Dictionary) -> bool:
	return e.get("kind", "") == "unit" and bool(Content.unit(String(e.def)).get("launched_drone", false))


# ================================================================ unit subset (cache, never saved)
static func _mask(st: Dictionary, def_id: String) -> int:
	var m = st.defs.get(def_id)
	if m != null:
		return int(m)
	var d := Content.unit(def_id)
	var v := 0
	if int(d.get("squad_size", 0)) > 1:
		v |= M_SQUAD
	if bool(d.get("drone_team", false)):
		v |= M_DTEAM
	st.charges[def_id] = int(d.get("drone_charges", 4))
	if d.has("heal_aura"):
		v |= M_AURA
	st.defs[def_id] = v
	return v


static func _add(st: Dictionary, e: Dictionary) -> void:
	var m := _mask(st, String(e.def))
	if m != 0:
		init_unit(e)
	if m & M_SQUAD:
		(st.sqb[int(e.id) % SQUAD_EVERY] as Array).append(int(e.id))
	if m & M_DTEAM:
		(st.dt as Array).append(int(e.id))
		if _tact_active(e):
			st.act[int(e.id)] = true
	if m & M_AURA:
		(st.au as Array).append(int(e.id))


## Ids per mechanic (squads, drone teams, auras), ascending. Never compacted: a unit in a carrier's
## cargo leaves w.entities and comes back with the same id, so dead ids are only skipped.
static func _state(w: SimWorld) -> Dictionary:
	var st = w.cache.get("g5_sub")
	var nid := int(w.next_id)
	if st == null:
		st = {"next_id": nid, "defs": {}, "sqb": [[], [], [], []], "act": {}, "dt": [], "au": [], "charges": {}, "heal": {}, "fullcd": {}}
		var all := []
		for e in SimIndex.of(w, "unit"):
			all.append(e)
			for c in e.get("cargo", []):
				all.append(c)
		all.sort_custom(func(a, b): return int(a.id) < int(b.id))
		for e in all:
			_add(st, e)
		w.cache["g5_sub"] = st
		return st
	var from := int(st.next_id)
	if nid > from:
		for id in range(from, nid):
			var e = w.entities.get(id)
			if e != null and e.kind == "unit":
				_add(st, e)
		st.next_id = nid
	return st


## G5 fields for a fresh squad / drone team (idempotent; called lazily from tick).
static func init_unit(e: Dictionary) -> void:
	var d := Content.unit(String(e.def))
	var n := int(d.get("squad_size", 0))
	if n > 1 and not e.has("squad_size"):
		e.squad_size = n
		e.squad_alive = n
	if bool(d.get("drone_team", false)) and not e.has("drone_charges"):
		e.drone_charges = int(d.get("drone_charges", 4))
		e.dmode = "drone"
		e.restock_t = 0


# ================================================================ tick
## PERF (5k units): no per-unit scan of all units. Squads/teams run O(1) each per tick; heal auras
## pulse together on tick % AURA_EVERY == AURA_PHASE over one bucket grid of the units that need
## healing (built that tick from current positions, never cached across ticks: save/load exact);
## drone-team restock checks run on tick % RESTOCK_EVERY == RESTOCK_PHASE (one Supply._sources pass).
static func _tact_active(e: Dictionary) -> bool:
	return e.has("tact") or e.has("infil_until") or bool(e.get("stacked", false))


static func tick(w: SimWorld) -> void:
	var st := _state(w)
	var ents: Dictionary = w.entities
	# squads: one cadence bucket per tick ((tick + id) % SQUAD_EVERY == 0)
	for id in st.sqb[(SQUAD_EVERY - w.tick % SQUAD_EVERY) % SQUAD_EVERY]:
		var e = ents.get(id)
		if e == null or (float(e.hp) >= float(e.max_hp) and int(e.squad_alive) == int(e.squad_size) and not e.has("sq_cd")):
			continue   # gone (or carried) / full strength: nothing to do
		_squad_step(w, st, e)
	# drone teams: running tactical orders every tick (small set), restock checks on the phase tick
	if not (st.act as Dictionary).is_empty():
		var ids: Array = st.act.keys()
		ids.sort()
		for id in ids:
			var e = ents.get(id)
			if e != null:
				_tactical_step(w, e)
			if e == null or not _tact_active(e):
				st.act.erase(id)
	if w.tick % RESTOCK_EVERY == RESTOCK_PHASE:
		var srcs = null
		for id in st.dt:
			var e = ents.get(id)
			if e == null or int(e.drone_charges) >= int(st.charges[String(e.def)]):
				if e == null or int(e.drone_charges) >= charge_cap(w, e):
					continue
			if srcs == null:
				srcs = Supply._sources(w)
			_restock_step(w, e, srcs)
	if not (st.au as Array).is_empty() and w.tick % AURA_EVERY == AURA_PHASE:
		var auras := []
		for id in st.au:
			var e = ents.get(id)
			if e != null:
				auras.append(e)
		if not auras.is_empty():
			_aura_pulse(w, st, auras)
	var gs = w.sys_state.get("g5mech")
	if gs != null and not (gs.drones as Dictionary).is_empty():
		_drones_step(w, gs)


# ---------------------------------------------------------------- squads
## Updates squad_alive from hp (every SQUAD_EVERY ticks, staggered by id). A squad under strength
## fires slower: a shot since the last check shows as cd_ticks above the recorded e.sq_cd minus the
## elapsed ticks; that shot's cooldown then gains full_cd x (squad_size / squad_alive - 1) ticks.
static func _squad_step(w: SimWorld, st: Dictionary, e: Dictionary) -> void:
	var n := int(e.squad_size)
	var mh := maxf(float(e.max_hp), 1.0)
	var alive := clampi(ceili(float(e.hp) / mh * float(n) - 1e-6), 1, n)
	if alive != int(e.squad_alive):
		if alive < int(e.squad_alive):
			w.emit("SquadLoss", {"id": int(e.id), "owner": int(e.owner), "alive": alive, "size": n})
		e.squad_alive = alive
	if alive >= n:
		if e.has("sq_cd"):
			e.erase("sq_cd")
		return
	var cd := int(e.get("cd_ticks", 0))
	if e.has("sq_cd") and cd > maxi(int(e.sq_cd) - SQUAD_EVERY, 0):
		cd += ceili(float(_full_cd(st, String(e.def))) * (float(n) / float(alive) - 1.0))
		e.cd_ticks = cd
		e.cooldown = float(cd) / SimWorld.TICK_RATE
	e.sq_cd = cd


static func _full_cd(st: Dictionary, def_id: String) -> int:
	var v = st.fullcd.get(def_id)
	if v == null:
		var wd := Content.weapon(String(Content.unit(def_id).get("weapon", "")))
		v = maxi(roundi(float(wd.get("cooldown", 1.0)) * SimWorld.TICK_RATE), 1)
		st.fullcd[def_id] = v
	return int(v)


# ---------------------------------------------------------------- heal aura (medics, field ambulance, maint swarm)
const AURA_BUCKET := 4.0
const AURA_STRIDE := 4096


## Per def: [infantry, energy, morale_max] for heal targets (cache, content is read-only).
static func _heal_info(st: Dictionary, def_id: String) -> Array:
	var v = st.heal.get(def_id)
	if v == null:
		var d := Content.unit(def_id)
		v = [String(d.get("armor", "")) == "infantry" and not bool(d.get("launched_drone", false)),
			bool(d.get("energy", false)), float(d.get("morale", 0))]
		st.heal[def_id] = v
	return v


static func _aura_pulse(w: SimWorld, st: Dictionary, auras: Array) -> void:
	var grid := {}   # bucket key -> [units needing hp/morale], ascending id
	for u in SimIndex.of(w, "unit"):
		var hi := _heal_info(st, String(u.def))
		if not (hi[0] or hi[1]):
			continue
		if float(u.hp) >= float(u.max_hp) and not (u.has("morale") and float(u.morale) < float(hi[2])):
			continue
		if not w.entities.has(int(u.id)):
			continue
		var p: Vector2 = u.pos
		var k := floori(p.x / AURA_BUCKET) + floori(p.y / AURA_BUCKET) * AURA_STRIDE
		var arr = grid.get(k)
		if arr == null:
			grid[k] = [u]
		else:
			arr.append(u)
	if grid.is_empty():
		return
	for e in auras:
		_aura_step(w, st, e, grid)


static func _aura_step(w: SimWorld, st: Dictionary, e: Dictionary, grid: Dictionary) -> void:
	var a: Dictionary = Content.unit(String(e.def)).heal_aura
	var r := float(a.get("radius", 3.0))
	var r2 := r * r
	var secs := float(AURA_EVERY) / SimWorld.TICK_RATE
	var dh := float(a.get("hp_per_sec", 0.0)) * secs
	var dm := float(a.get("morale_per_sec", 0.0)) * secs
	var energy := bool(a.get("energy", false))
	var p: Vector2 = e.pos
	var n := 0
	var x0 := floori((p.x - r) / AURA_BUCKET)
	var x1 := floori((p.x + r) / AURA_BUCKET)
	var y0 := floori((p.y - r) / AURA_BUCKET)
	var y1 := floori((p.y + r) / AURA_BUCKET)
	var cand := []
	for by in range(y0, y1 + 1):
		for bx in range(x0, x1 + 1):
			var arr = grid.get(bx + by * AURA_STRIDE)
			if arr != null:
				for u in arr:
					if p.distance_squared_to(Vector2(u.pos)) <= r2 and w.is_ally(int(e.owner), int(u.owner)):
						cand.append(u)
	for u in cand:   # each candidate is healed independently: the visit order cannot change results
		var hi := _heal_info(st, String(u.def))
		if (not hi[1]) if energy else (not hi[0]):
			continue
		if Medical.is_wounded(u):
			continue
		var healed := false
		if float(u.hp) < float(u.max_hp) and dh > 0.0:
			u.hp = snappedf(minf(float(u.max_hp), float(u.hp) + dh), Q)
			healed = true
		if dm > 0.0 and u.has("morale") and float(u.morale) < float(hi[2]):
			u.morale = snappedf(minf(float(hi[2]), float(u.morale) + dm), Q)
			healed = true
		if healed:
			n += 1
	if n > 0:
		w.emit("AuraHealed", {"id": int(e.id), "owner": int(e.owner), "n": n})


# ---------------------------------------------------------------- restock (drone team)
static func _restock_step(w: SimWorld, e: Dictionary, srcs: Dictionary) -> void:
	var radius := float(Content.rules().get("supply", {}).get("radius", 6.0))
	if Supply._in_range(e, srcs.get(int(e.owner), []), radius):
		var step := RESTOCK_EVERY
		var rm := Callins.drone_restock_mult(w, e)
		if rm != 1.0:
			step = roundi(float(RESTOCK_EVERY) * rm)
		e.restock_t = int(e.get("restock_t", 0)) + step
		if int(e.restock_t) >= RESTOCK_TICKS:
			restock_drones(w, e)
	else:
		e.restock_t = 0


# ---------------------------------------------------------------- launched drones
static func _gstate(w: SimWorld) -> Dictionary:
	var gs = w.sys_state.get("g5mech")
	if gs == null:
		gs = {"drones": {}, "ver": 1}
		w.sys_state["g5mech"] = gs
	return gs


static func _launch(w: SimWorld, team: Dictionary, kind: String, tid: int, goal: Vector2) -> int:
	var def_id := String(Content.unit(String(team.def)).get("drone_prefix", "a_drone_")) + kind
	var d := Content.unit(def_id)
	var did: int = w.spawn_unit(def_id, int(team.owner), Vector2(team.pos))
	w.entities[did].facing = snappedf(Vector2(team.pos).angle_to_point(goal), Q)
	_gstate(w).drones[did] = {"owner_squad": int(team.id), "type": kind, "t": int(d.get("drone_life", 240)),
		"goal": goal, "target": tid, "phase": "fly"}
	team.drone_charges = int(team.drone_charges) - 1
	w.emit("DroneLaunched", {"id": did, "def": def_id, "type": kind, "owner": int(team.owner), "squad": int(team.id),
		"target": tid, "goal": goal, "charges": int(team.drone_charges)})
	if int(team.drone_charges) <= 0:
		team.dmode = "tactical"
		w.emit("DroneTeamTactical", {"id": int(team.id), "owner": int(team.owner)})
	return did


## Removes a launched drone without a wreck or a loss stat (impact, expiry, jamming).
static func _remove(w: SimWorld, e: Dictionary, cause: String) -> void:
	w.entities.erase(int(e.id))
	w.emit("EntityDestroyed", {"id": int(e.id), "kind": "unit", "def": e.def, "owner": e.owner, "pos": e.pos,
		"cause": cause, "killer_owner": SimWorld.NEUTRAL, "squad": -1})


static func _drones_step(w: SimWorld, gs: Dictionary) -> void:
	var drones: Dictionary = gs.drones
	var ids := drones.keys()
	ids.sort()
	for id in ids:
		if not drones.has(id):
			continue   # downed by an EMP earlier this tick
		var r: Dictionary = drones[id]
		var e = w.entities.get(int(id))
		if e == null:
			drones.erase(id)
			w.emit("DroneLost", {"id": int(id), "type": r.type, "squad": int(r.owner_squad)})
			continue
		r.t = int(r.t) - 1
		if Status.is_jammed(w, e) or Counterdrone.jammed(w, Vector2(e.pos), int(e.owner)):
			drones.erase(id)
			_remove(w, e, "jammed")
			w.emit("DroneJammed", {"id": int(id), "type": r.type, "owner": int(e.owner), "pos": e.pos})
			continue
		var d := Content.unit(String(e.def))
		if String(r.phase) == "loiter":
			if (w.tick + int(id)) % MARK_EVERY == 0:
				_mark(w, e, d)
		else:
			var t = w.entities.get(int(r.target)) if int(r.target) >= 0 else null
			if t != null and t.kind == "unit":
				r.goal = Vector2(t.pos)   # tracks a moving unit
			var goal: Vector2 = r.goal
			var p: Vector2 = e.pos
			var stp := float(d.get("speed", 8.0)) / SimWorld.TICK_RATE
			var dist := p.distance_to(goal)
			if dist <= maxf(stp, ARRIVE):
				e.pos = goal
				_arrive(w, gs, e, r, d)
				if not drones.has(id):
					continue
			else:
				var np := p + (goal - p) / dist * stp
				e.pos = Vector2(snappedf(np.x, Q), snappedf(np.y, Q))   # e.moving stays false: Movement must not path it
		if int(r.t) <= 0:
			drones.erase(id)
			_remove(w, e, "expired")


static func _arrive(w: SimWorld, gs: Dictionary, e: Dictionary, r: Dictionary, d: Dictionary) -> void:
	var kind := String(r.type)
	if kind == "recon":
		r.phase = "loiter"
		_mark(w, e, d)
		return
	var at: Vector2 = e.pos
	if kind == "emp":
		_emp(w, gs, e, d)
	else:
		var spread := float(d.get("spread", 0.0))
		if spread > 0.0:   # Human B rigged FPV: scatter on impact (fixed draw order: angle, radius)
			var ang := w.rng.randf() * TAU
			var rad := w.rng.randf() * spread
			at = Vector2(snappedf(at.x + cos(ang) * rad, Q), snappedf(at.y + sin(ang) * rad, Q))
		var pl := String(d.get("payload", ""))
		var hits := _impact(w, e, at, G4bMech._wpn(pl)) if pl != "" else 0
		w.emit("DroneImpact", {"id": int(e.id), "type": kind, "owner": int(e.owner), "squad": int(r.owner_squad),
			"pos": at, "aim": Vector2(r.goal), "hits": hits})
	gs.drones.erase(int(e.id))
	_remove(w, e, "impact")


## Payload hit at `at`: every enemy ground unit / building within splash, 50% at the edge. Returns hits.
static func _impact(w: SimWorld, src: Dictionary, at: Vector2, s: Dictionary) -> int:
	var rad := maxf(float(s.splash), 0.05)
	var fid := int(src.owner)
	var list := []
	for u in G4bMech.near_units(w, at, rad + 0.3):
		if w.entities.has(int(u.id)) and w.is_enemy(fid, int(u.owner)) and not G4bMech._is_air(u) \
				and at.distance_to(Vector2(u.pos)) <= rad + 0.3:
			list.append([u, at.distance_to(Vector2(u.pos))])
	for b in SimIndex.of(w, "building"):
		if w.entities.has(int(b.id)) and w.is_enemy(fid, int(b.owner)):
			var bd := G4bMech._dist_to(at, b)
			if bd <= rad:
				list.append([b, bd])
	for it in list:
		var t: Dictionary = it[0]
		if not w.entities.has(int(t.id)):
			continue
		var s2 := s.duplicate()
		s2.damage = float(s.damage) * (1.0 - 0.5 * clampf(float(it[1]) / rad, 0.0, 1.0))
		Damage.apply_hit(w, src, t, s2, true)
	return list.size()


## Recon: enemies within mark_radius are marked for mark_ticks (e.marked_until, e.marked_team).
static func _mark(w: SimWorld, e: Dictionary, d: Dictionary) -> void:
	var r := float(d.get("mark_radius", 8.0))
	var until := w.tick + int(d.get("mark_ticks", 300))
	var tm := G4bMech.team_of(w, int(e.owner))
	var p: Vector2 = e.pos
	var n := 0
	for u in G4bMech.near_units(w, p, r):
		if w.entities.has(int(u.id)) and w.is_enemy(int(e.owner), int(u.owner)) and p.distance_to(Vector2(u.pos)) <= r:
			u.marked_until = until
			u.marked_team = tm
			n += 1
	if n > 0:
		w.emit("TargetsMarked", {"id": int(e.id), "owner": int(e.owner), "n": n, "until": until})


## EMP: enemy machines / vehicles (electronics) / armed buildings within emp_radius hold fire for
## emp_ticks (cooldown held, e.emp_until, jammed); enemy launched drones in the radius go down.
static func _emp(w: SimWorld, gs: Dictionary, e: Dictionary, d: Dictionary) -> void:
	var r := float(d.get("emp_radius", 3.0))
	var dur := int(d.get("emp_ticks", 120))
	var fid := int(e.owner)
	var p: Vector2 = e.pos
	var n := 0
	var downed := 0
	for u in G4bMech.near_units(w, p, r):
		if not w.entities.has(int(u.id)) or not w.is_enemy(fid, int(u.owner)) or p.distance_to(Vector2(u.pos)) > r:
			continue
		var ud := Content.unit(String(u.def))
		if bool(ud.get("launched_drone", false)):
			gs.drones.erase(int(u.id))
			_remove(w, u, "emp")
			downed += 1
		elif bool(ud.get("energy", false)) or u.has("comp") or String(ud.get("faction", "")) == "machine":
			_disable(w, u, dur)
			n += 1
	for b in SimIndex.of(w, "building"):
		if w.entities.has(int(b.id)) and w.is_enemy(fid, int(b.owner)) and G4bMech._dist_to(p, b) <= r \
				and String(Content.building(String(b.def)).get("weapon", "")) != "":
			_disable(w, b, dur)
			n += 1
	w.emit("EmpBurst", {"id": int(e.id), "owner": fid, "pos": p, "disabled": n, "drones_downed": downed, "until": w.tick + dur})


static func _disable(w: SimWorld, t: Dictionary, dur: int) -> void:
	t.emp_until = w.tick + dur
	t.jammed_until = maxi(int(t.get("jammed_until", -1)), w.tick + dur)
	var cd := maxi(int(t.get("cd_ticks", 0)), dur)
	t.cd_ticks = cd
	t.cooldown = float(cd) / SimWorld.TICK_RATE
	if t.has("sq_cd"):
		t.sq_cd = cd   # not a shot: no squad-loss stretch




# ---------------------------------------------------------------- tactical team mode
static func _tactical_step(w: SimWorld, e: Dictionary) -> void:
	if e.has("infil_until"):
		var fired := int(e.get("last_fired_tick", -100000)) >= int(e.get("infil_from", 0))
		if w.tick >= int(e.infil_until) or fired or Medical.is_wounded(e):
			e.erase("infil_until")
			e.erase("infil_from")
			e.hid = false
			e.spot = []
		else:
			e.hid = true
			e.spot = G4bMech._spot_teams(w, e)
	if bool(e.get("stacked", false)) and not e.has("tact"):
		if w.tick >= int(e.get("stack_until", 0)):
			e.stacked = false
		else:
			var foe = _nearest_enemy(w, e, BURST_R)
			if foe != null:
				_burst(w, e, foe)
	if not e.has("tact"):
		return
	if String(e.order.get("type", "")) != "tactical":
		e.erase("tact")   # the player gave another order
		return
	var o: Dictionary = e.tact
	var ab := String(o.ability)
	var tid := int(o.get("target", -1))
	var t = w.entities.get(tid) if tid >= 0 else null
	var goal := Vector2.ZERO
	var reach := 0.6
	var dist := 0.0
	if ab == "takedown" or ab == "breach" or ab == "armored_attack":
		if t == null or tact_target_error(w, int(e.owner), ab, t) != "":
			_end_tact(e)
			return
		goal = Vector2(t.pos) if t.kind == "unit" else G4bMech._approach(e, t)
		dist = G4bMech._dist_to(e.pos, t)
		reach = TAKEDOWN_REACH if ab == "takedown" else (BREACH_REACH if ab == "breach" else AT_RANGE)
	else:
		var c: Vector2i = o.cell
		goal = Vector2(c) + Vector2(0.5, 0.5)
		dist = Vector2(e.pos).distance_to(goal)
	if dist > reach:
		if not bool(e.moving) or (t != null and t.kind == "unit" and (w.tick + int(e.id)) % 10 == 0):
			o.tries = int(o.get("tries", 0)) + 1
			if int(o.tries) > 40 or not Movement.order_path(w, e, goal):
				_end_tact(e)
		return
	if bool(e.moving):
		Movement.stop_path(e)
	o.t = int(o.get("t", 0)) + 1
	var stacked := bool(e.get("stacked", false))
	var info := {"id": int(e.id), "owner": int(e.owner), "target": tid}
	match ab:
		"takedown":   # silent: no last_fired_tick, infiltration holds
			Damage.apply_hit(w, e, t, G4bMech._wpn("g5_takedown"), true)
			w.emit("Takedown", info)
			_end_tact(e)
		"breach":
			if int(o.t) >= (1 if stacked else BREACH_TICKS):
				var s := G4bMech._wpn("g5_breach")
				if stacked:
					s.damage = float(s.damage) * 2.0
					e.stacked = false
				Damage.apply_hit(w, e, t, s, true)
				info["stacked"] = stacked
				w.emit("Breach", info)
				_end_tact(e)
		"armored_attack":   # one short-range AT rocket per soldier still standing
			var s2 := G4bMech._wpn("g5_team_at")
			if stacked:
				s2.damage = float(s2.damage) * 1.5
				e.stacked = false
			var shots := squad_alive(e)
			for i in shots:
				if w.entities.has(tid):
					Damage.apply_hit(w, e, t, s2, true)
			e.last_fired_tick = w.tick
			info["shots"] = shots
			w.emit("ArmoredAttack", info)
			_end_tact(e)
		"stack_up":
			if int(o.t) >= STACK_TICKS:
				e.stacked = true
				e.stack_until = w.tick + STACK_HOLD
				w.emit("StackedUp", {"id": int(e.id), "owner": int(e.owner), "until": int(e.stack_until)})
				e.erase("tact")
				e.order = {"type": "tactical", "ability": "stacked"}   # ambush: return fire only
		_:
			_end_tact(e)


static func _end_tact(e: Dictionary) -> void:
	e.erase("tact")
	e.order = {"type": "idle"}


static func _nearest_enemy(w: SimWorld, e: Dictionary, r: float):
	var best = null
	var bd := r
	var p: Vector2 = e.pos
	for u in G4bMech.near_units(w, p, r):
		if not w.entities.has(int(u.id)) or not w.is_enemy(int(e.owner), int(u.owner)) or G4bMech._is_air(u):
			continue
		var d := p.distance_to(Vector2(u.pos))
		if d < bd or (d == bd and best != null and int(u.id) < int(best.id)) or (best == null and d <= bd):
			bd = d
			best = u
	return best


## Stack-up first strike: a burst (scaled by squad_alive) on the first enemy that comes close.
static func _burst(w: SimWorld, e: Dictionary, foe: Dictionary) -> void:
	var s := G4bMech._wpn("g5_burst")
	s.damage = float(s.damage) * float(squad_alive(e)) / float(maxi(squad_size(e), 1))
	e.stacked = false
	e.last_fired_tick = w.tick
	e.order = {"type": "idle"}
	var hits := _impact(w, e, Vector2(foe.pos), s)
	w.emit("FirstStrike", {"id": int(e.id), "owner": int(e.owner), "target": int(foe.id), "hits": hits})


static func tact_target_error(w: SimWorld, fid: int, ab: String, t: Dictionary) -> String:
	match ab:
		"takedown":
			if t.kind != "unit" or not w.is_enemy(fid, int(t.owner)) or G4bMech._is_air(t) \
					or String(Content.unit(String(t.def)).get("armor", "")) != "infantry":
				return "Takedown needs an enemy soldier."
			return "" if squad_alive(t) <= 1 else "Takedown needs a lone soldier."
		"breach":
			return G4bMech.charge_target_error(w, fid, t)
		"armored_attack":
			if (t.kind != "unit" and t.kind != "building") or not w.is_enemy(fid, int(t.owner)):
				return "Pick an enemy target."
			return ""
	return ""


# ================================================================ commands
## launch_drone {issuer, unit_id, drone, target_id?, cell?}; tactical {issuer, unit_id, ability, target_id?, cell?}.
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	var e = w.entities.get(int(cmd.get("unit_id", -1)))
	if e == null or e.kind != "unit" or int(e.owner) != fid:
		return "Not your unit."
	if not bool(Content.unit(String(e.def)).get("drone_team", false)):
		return "Only Drone Teams can do that."
	if Medical.is_wounded(e):
		return "The team is wounded."
	match String(cmd.get("type", "")):
		"launch_drone":
			if mode(e) != "drone" or drone_charges(e) <= 0:
				return "No drones left: restock at a supply point."
			if not DRONE_TYPES.has(String(cmd.get("drone", ""))):
				return "Unknown drone type."
			var g = _goal(w, fid, cmd)
			if typeof(g) == TYPE_STRING:
				return g
			return "Target out of drone range." if Vector2(e.pos).distance_to(g) > launch_range(w, e) else ""
		"tactical":
			if mode(e) != "tactical":
				return "Tactical abilities unlock when all drones are spent."
			var ab := String(cmd.get("ability", ""))
			if not ABILITIES.has(ab):
				return "Unknown ability."
			if w.tick < int(e.get("tact_cd", 0)):
				return "Ability recharging."
			if ab == "infiltrate" or ab == "stack_up":
				if cmd.has("cell"):
					var c = G4bMech._cell_arg(cmd.cell)
					return "Outside the map." if c == null or not w.in_bounds(c) else ""
				if int(cmd.get("target_id", -1)) >= 0 and not w.entities.has(int(cmd.target_id)):
					return "No target."
				return ""
			var t = w.entities.get(int(cmd.get("target_id", -1)))
			if t == null:
				return "No target."
			return tact_target_error(w, fid, ab, t)
	return "Unknown command."


## Drone goal: a target entity (enemy ones must be visible) or a cell centre; else a reason String.
static func _goal(w: SimWorld, fid: int, cmd: Dictionary):
	if int(cmd.get("target_id", -1)) >= 0:
		var t = w.entities.get(int(cmd.target_id))
		if t == null:
			return "No target."
		if w.is_enemy(fid, int(t.owner)) and not w.is_visible(fid, Vector2(t.pos)):
			return "Target not visible."
		return Vector2(t.pos)
	if not cmd.has("cell"):
		return "No target given."
	var c = G4bMech._cell_arg(cmd.cell)
	if c == null or not w.in_bounds(c):
		return "Outside the map."
	return Vector2(c) + Vector2(0.5, 0.5)


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var e: Dictionary = w.entities[int(cmd.unit_id)]
	init_unit(e)
	if String(cmd.type) == "launch_drone":
		var g: Vector2 = _goal(w, int(cmd.issuer), cmd)
		_launch(w, e, String(cmd.drone), int(cmd.get("target_id", -1)), g)
		return
	var ab := String(cmd.ability)
	var tid := int(cmd.get("target_id", -1))
	e.erase("patrol")
	e.erase("guard")
	e.target = -1
	e.tact_cd = w.tick + TACT_COOLDOWN
	_state(w).act[int(e.id)] = true
	var cell = G4bMech._cell_arg(cmd.cell) if cmd.has("cell") else null
	if cell == null and (ab == "infiltrate" or ab == "stack_up"):
		var t = w.entities.get(tid) if tid >= 0 else null
		if t != null:
			cell = w.cell_of(G4bMech._approach(e, t) if t.kind != "unit" else Vector2(t.pos))
		elif ab == "stack_up":
			cell = w.cell_of(e.pos)
	if ab == "infiltrate":
		e.infil_until = w.tick + INFIL_TICKS
		e.infil_from = w.tick
		e.hid = true
		e.spot = []
		w.emit("Infiltrate", {"id": int(e.id), "owner": int(e.owner), "until": int(e.infil_until)})
		if cell == null:
			return   # conceal in place
	e.tact = {"ability": ab, "target": tid, "cell": cell, "t": 0, "tries": 0}
	e.order = {"type": "tactical", "ability": ab}
	Movement.stop_path(e)
