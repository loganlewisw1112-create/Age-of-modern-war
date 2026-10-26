extends RefCounted
## AmmoBearer (G6.1, owner: BEARER61). Infantry ammo bearer: joins a squad, follows it a few tiles behind its
## centre and restocks members (then nearby friendlies) from its own load; reloads at supply points.
## Commands: join_squad {issuer, unit_ids (bearers), squad_unit_id}, leave_squad {issuer, unit_ids}.
##
## Content: unit def `ammo_bearer: true`, `bearer_load_max` (restocks carried, default 3),
## `bearer_rounds_per_restock` (faction ammo stock spent per restock on refill, default 60).
## State (saved + hashed with the entity): e.bearer_load = load in thousandths of a restock (int, so
## 3000 = 3.0 restocks: integer math keeps it deterministic), e.bearer_trip = true while an empty bearer
## walks back to a supply point. Membership: e.squad / e.platoon / e.company like any squad member.
## Restocking a unit from a% ammo costs (1 - a) restock: cost = ceil(1000 * rounds / ammo_max).
## Cost: bearers are found through w.cache.bearer61 (never saved; ids ascending, new ids appended, dead
## ids dropped), each thinks once per EVERY ticks on (tick + id) % EVERY == 0. No bearers = no work.

const Supply = preload("res://sim/systems/supply.gd")
const SquadAI = preload("res://sim/systems/squad_ai.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")

const EVERY := 10                 # think period (0.5 s)
const MILLI := 1000               # load unit: 1000 = one full restock
const RESTOCK_BELOW := 0.5        # members under this ammo fraction get restocked
const RESTOCK_R := 2.0            # restock reach (tiles)
const SEEK_R := 10.0              # needy squad members within this are walked to
const FOLLOW_BACK := 2.5          # tiles behind the squad centre
const FOLLOW_SLACK := 1.5         # no new move while within this of the follow point
const REFILL_STEP := 500          # load refilled per think at a supply point (3 restocks in 3 s)
const TRIP_R := 48.0              # an empty bearer walks back to a supply point this close
const WHY := "bearer"             # order.sq tag of the moves this system issues


# ================================================================ helpers (public)
static func is_bearer(e) -> bool:
	return e != null and String(e.get("kind", "")) == "unit" and bool(Content.unit(String(e.def)).get("ammo_bearer", false))


static func load_max(def_id: String) -> int:
	return int(round(float(Content.unit(def_id).get("bearer_load_max", 3)) * MILLI))


static func load_of(e: Dictionary) -> int:
	return int(e.get("bearer_load", load_max(String(e.def))))


## Inspector line, e.g. "Ammo load 2.4 / 3" ("" for a non-bearer). The shown load rounds down.
static func load_line(e) -> String:
	if not is_bearer(e):
		return ""
	var mx := load_max(String(e.def))
	var mxs := "%d" % (mx / MILLI) if mx % MILLI == 0 else "%.1f" % (float(mx) / MILLI)
	return "Ammo load %.1f / %s" % [float(load_of(e) / 100) / 10.0, mxs]


## Load fraction 0..1 for a small marker (1.0 for a non-bearer).
static func load_frac(e) -> float:
	if not is_bearer(e):
		return 1.0
	return clampf(float(load_of(e)) / float(maxi(load_max(String(e.def)), 1)), 0.0, 1.0)


static func _ammo_max(e: Dictionary) -> int:
	return int(Content.unit(String(e.def)).get("ammo_max", 0))


## Thousandths of a restock it takes to fully restock unit e (0 when full or ammo-less).
static func restock_cost(e: Dictionary) -> int:
	var amax := _ammo_max(e)
	if amax <= 0 or not e.has("ammo"):
		return 0
	var r := maxi(0, amax - int(e.ammo))
	return (MILLI * r + amax - 1) / amax


# ================================================================ cache
static func _ids(w: SimWorld) -> Array:
	var c = w.cache.get("bearer61")
	if c == null or int(c.nid) > int(w.next_id):
		var ids := []
		for e in SimIndex.of(w, "unit"):
			if SimIndex.alive(w, e) and is_bearer(e):
				ids.append(int(e.id))
		ids.sort()
		c = {"nid": int(w.next_id), "ids": ids}
		w.cache["bearer61"] = c
	elif int(c.nid) != int(w.next_id):
		for id in range(int(c.nid), int(w.next_id)):
			var e = w.entities.get(id)
			if e != null and is_bearer(e):
				c.ids.append(id)
		c.nid = int(w.next_id)
	return c.ids


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var ids: Array = cmd.get("unit_ids", [])
	if ids.is_empty():
		return "Select an ammo bearer first."
	var issuer := int(cmd.get("issuer", -1))
	for raw in ids:
		var e = w.entities.get(int(raw))
		if e == null or String(e.kind) != "unit":
			return "That unit is gone."
		if int(e.owner) != issuer:
			return "Not your unit."
		if not is_bearer(e):
			return "Only ammo bearers can join or leave a squad this way."
	if String(cmd.type) == "join_squad":
		var t = w.entities.get(int(cmd.get("squad_unit_id", -1)))
		if t == null or String(t.kind) != "unit":
			return "That squad is gone."
		if int(t.owner) != issuer:
			return "Pick a friendly squad."
		if int(t.get("squad", -1)) < 0:
			return "That unit is not in a squad."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var ids := []
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if is_bearer(e) and int(e.owner) == int(cmd.get("issuer", -1)):
			ids.append(int(raw))
	ids.sort()
	var t = w.entities.get(int(cmd.get("squad_unit_id", -1)))
	for id in ids:
		var e: Dictionary = w.entities[id]
		_detach(w, e)
		if String(cmd.type) == "join_squad" and t != null and int(t.get("squad", -1)) >= 0:
			_attach(w, e, t)
	SquadAI.touch(w)


## Removes e from its squad / platoon (ops group members) / company.
static func _detach(w: SimWorld, e: Dictionary) -> void:
	var gid := int(e.get("platoon", -1))
	if gid >= 0 and w.sys_state.has("ops"):
		var g = (w.sys_state.ops.get("groups", {}) as Dictionary).get(gid)
		if g != null and (g.members as Array).has(int(e.id)):
			g.members.erase(int(e.id))
	e.squad = -1
	e.erase("platoon")
	if not e.has("element"):
		e.erase("company")   # a bearer trained as a company element stays on its company's roster


## Puts e into t's squad, and t's platoon (ops group members, as Companies does) and company when it has them.
static func _attach(w: SimWorld, e: Dictionary, t: Dictionary) -> void:
	e.squad = int(t.squad)
	var gid := int(t.get("platoon", -1))
	if gid >= 0 and w.sys_state.has("ops"):
		var g = (w.sys_state.ops.get("groups", {}) as Dictionary).get(gid)
		if g != null:
			e.platoon = gid
			if not (g.members as Array).has(int(e.id)):
				g.members.append(int(e.id))
	if t.has("company"):
		e.company = int(t.company)
	if String(e.order.get("type", "idle")) == "hold" or e.has("bearer_trip"):
		return
	e.order = {"type": "idle"}


# ================================================================ AI helpers (enemy / ally AI, OFF61 hook)
## The faction's bearer unit/production id ("" when it has none). Content-driven: the lowest id of a unit def
## with ammo_bearer for that faction that has a production entry of the same id.
static func bearer_def_for(w: SimWorld, fid: int) -> String:
	var fac := String(w.factions.get(fid, {}).get("faction_def", ""))
	var ids: Array = Content.ids("units")
	ids.sort()
	for id in ids:
		var d := Content.unit(String(id))
		if bool(d.get("ammo_bearer", false)) and String(d.get("faction", "")) == fac and not Content.production(String(id)).is_empty():
			return String(id)
	return ""


## Infantry squads of fid (squad id -> [member ids]); a squad counts when it has an armed infantry member.
static func _inf_squads(w: SimWorld, fid: int) -> Dictionary:
	var out := {}
	for e in SimIndex.units_by_owner(w).get(fid, []):
		var sq := int(e.get("squad", -1))
		if sq < 0 or not SimIndex.alive(w, e):
			continue
		if not out.has(sq):
			out[sq] = []
		out[sq].append(int(e.id))
	var keep := {}
	for sq in out:
		for id in out[sq]:
			var d := Content.unit(String(w.entities[id].def))
			if String(d.get("armor", "")) == "infantry" and String(d.get("weapon", "")) != "":
				keep[sq] = out[sq]
				break
	return keep


## How many more bearers fid should train: one per ~3 infantry squads (ceil), minus the bearers it has.
static func ai_wanted(w: SimWorld, fid: int) -> int:
	var n := 0
	for id in _ids(w):
		var e = w.entities.get(id)
		if e != null and int(e.owner) == fid:
			n += 1
	return maxi(0, (_inf_squads(w, fid).size() + 2) / 3 - n)


## Attaches each of fid's free bearers to the nearest infantry squad without one (sim-side, deterministic:
## sorted ids). Call on a staggered AI cadence. Returns how many were attached.
static func ai_attach(w: SimWorld, fid: int) -> int:
	var sqs := _inf_squads(w, fid)
	if sqs.is_empty():
		return 0
	var covered := {}
	var free := []
	for id in _ids(w):
		var e = w.entities.get(id)
		if e == null or int(e.owner) != fid:
			continue
		if int(e.get("squad", -1)) >= 0 and sqs.has(int(e.squad)):
			covered[int(e.squad)] = true
		elif int(e.get("squad", -1)) < 0:
			free.append(e)
	var keys: Array = sqs.keys()
	keys.sort()
	var n := 0
	for b in free:
		var best := -1
		var bd := INF
		for sq in keys:
			if covered.has(sq):
				continue
			var d := Vector2(b.pos).distance_to(w.entities[int(sqs[sq][0])].pos)
			if d < bd:
				bd = d
				best = int(sq)
		if best < 0:
			break
		_attach(w, b, w.entities[int(sqs[best][0])])
		covered[best] = true
		n += 1
	if n > 0:
		SquadAI.touch(w)
	return n


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var ids := _ids(w)
	if ids.is_empty():
		return
	var dead := false
	for id in ids:
		var e = w.entities.get(id)
		if e == null:
			dead = true
			continue
		if not e.has("bearer_load"):
			e.bearer_load = load_max(String(e.def))
		if (w.tick + int(id)) % EVERY == 0:
			_think(w, e)
	if dead:
		var keep := []
		for id in ids:
			if w.entities.has(id):
				keep.append(id)
		w.cache.bearer61.ids = keep


static func _think(w: SimWorld, e: Dictionary) -> void:
	var fid := int(e.owner)
	if not w.factions.has(fid):
		return
	var mx := load_max(String(e.def))
	if int(e.bearer_load) < mx:
		var srcs := _sources(w)
		var radius := float(Content.rules().get("supply", {}).get("radius", 8))
		if srcs.has(fid) and Supply._in_range(e, srcs[fid], radius):
			_refill(w, e, mx)
	if int(e.bearer_load) > 0 and _restock(w, e):
		return
	if not _may_move(w, e):
		return
	if e.has("bearer_trip"):
		_trip(w, e)
	elif int(e.bearer_load) <= 0 and int(w.factions[fid].stock.get("ammo", 0)) > 0:
		e.bearer_trip = true
		_trip(w, e)
	else:
		_follow(w, e)


## Supply points per faction, built once per tick for all bearers (runtime cache, never saved).
static func _sources(w: SimWorld) -> Dictionary:
	var c = w.cache.get("bearer61_src")
	if c == null or int(c.tick) != w.tick:
		c = {"tick": w.tick, "srcs": Supply._sources(w)}
		w.cache["bearer61_src"] = c
	return c.srcs


## Reload at a supply point: spends faction ammo stock (Supply._draw, so the ledger stays conserved).
static func _refill(w: SimWorld, e: Dictionary, mx: int) -> void:
	var rpr := maxi(1, int(Content.unit(String(e.def)).get("bearer_rounds_per_restock", 60)))
	var add := mini(mx - int(e.bearer_load), REFILL_STEP)
	var rounds := (rpr * add + MILLI - 1) / MILLI
	var flags := {"ammo": false, "fuel": false}
	var got := Supply._draw(w, int(e.owner), "ammo", rounds, flags)
	if got < rounds:
		add = mini(add, got * MILLI / rpr)
	e.bearer_load = mini(mx, int(e.bearer_load) + add)
	if e.has("bearer_trip") and (int(e.bearer_load) >= mx or got <= 0):
		e.erase("bearer_trip")   # full, or the faction is out of ammo stock: back to the squad


## Restocks the neediest unit in reach: squad members first, then (squad all above the bar) nearby friendlies.
## One unit per think. True when it restocked someone.
static func _restock(w: SimWorld, e: Dictionary) -> bool:
	var sq := int(e.get("squad", -1))
	var pos: Vector2 = e.pos
	var best = null
	var bf := RESTOCK_BELOW
	var squad_needs := false
	if sq >= 0:
		for id in SquadAI.squad_members(w, sq):
			var m: Dictionary = w.entities[id]
			var f := _frac(m)
			if f >= RESTOCK_BELOW or int(m.id) == int(e.id):
				continue
			squad_needs = true
			if pos.distance_to(m.pos) <= RESTOCK_R and f < bf:
				bf = f
				best = m
	if best == null and not squad_needs:
		var own: Array = SimIndex.units_by_owner(w).get(int(e.owner), [])
		for m in own:
			if int(m.id) == int(e.id) or not m.has("ammo") or not SimIndex.alive(w, m):
				continue
			var f := _frac(m)
			if f < bf and pos.distance_to(m.pos) <= RESTOCK_R:
				bf = f
				best = m
	if best == null:
		return false
	var amax := _ammo_max(best)
	var r := mini(amax - int(best.ammo), int(e.bearer_load) * amax / MILLI)
	if r <= 0:
		return false
	var cost := (MILLI * r + amax - 1) / amax
	best.ammo = int(best.ammo) + r
	e.bearer_load = maxi(0, int(e.bearer_load) - cost)
	w.emit("AmmoRestock", {"id": int(e.id), "target": int(best.id), "rounds": r, "owner": int(e.owner)})
	return true


## Ammo fraction (1.0 for ammo-less units, so they are never picked).
static func _frac(m: Dictionary) -> float:
	var amax := _ammo_max(m)
	if amax <= 0 or not m.has("ammo"):
		return 1.0
	return float(m.ammo) / float(amax)


## Player control first: no move on Hold, within the player-order window, or while another system drives it.
static func _may_move(w: SimWorld, e: Dictionary) -> bool:
	var ot := String(e.order.get("type", "idle"))
	if ot == "hold" or SquadAI.stance_of(e) == "hold_position" or SquadAI.player_fresh(w, e):
		return false
	if bool(e.get("broken", false)):
		return false
	return ot == "idle" or e.order.has("sq")


static func _move(w: SimWorld, e: Dictionary, goal: Vector2) -> void:
	goal = Vector2(clampf(goal.x, 0.5, float(w.map.w) - 0.5), clampf(goal.y, 0.5, float(w.map.h) - 0.5))
	if String(e.order.get("sq", "")) == WHY and bool(e.moving) and Vector2(e.order.target).distance_to(goal) <= FOLLOW_SLACK:
		return
	e.target = -1
	e.order = {"type": "move", "target": goal, "sq": WHY}
	if not Movement.order_path(w, e, goal):
		e.order = {"type": "idle"}


## Follow the squad FOLLOW_BACK tiles behind its centre (away from where it is heading or shooting); walk to a
## needy member within SEEK_R that is out of reach.
static func _follow(w: SimWorld, e: Dictionary) -> void:
	var sq := int(e.get("squad", -1))
	if sq < 0:
		return
	var mem := []
	for id in SquadAI.squad_members(w, sq):
		if int(id) != int(e.id) and not is_bearer(w.entities[id]):
			mem.append(w.entities[id])
	if mem.is_empty():
		return
	var pos: Vector2 = e.pos
	var need = null
	var nf := RESTOCK_BELOW
	var cen := Vector2.ZERO
	for m in mem:
		cen += Vector2(m.pos)
		var f := _frac(m)
		if f < nf and pos.distance_to(m.pos) <= SEEK_R:
			nf = f
			need = m
	cen /= float(mem.size())
	if need != null:
		var np: Vector2 = need.pos
		if pos.distance_to(np) > RESTOCK_R * 0.75:
			_move(w, e, np + (pos - np).limit_length(1.0))
		return
	var le: Dictionary = w.entities[SquadAI.leader_of(w, mem.map(func(x): return int(x.id)))]
	var dir := Vector2.from_angle(float(le.get("facing", 0.0)))
	var lo := String(le.order.get("type", "idle"))
	var tg = w.entities.get(int(le.target))
	if tg != null:
		dir = Vector2(tg.pos) - cen
	elif (lo == "move" or lo == "attack_move") and le.order.has("target"):
		dir = Vector2(le.order.target) - cen
	if dir.length() < 0.01:
		dir = Vector2.RIGHT
	var goal: Vector2 = cen - dir.normalized() * FOLLOW_BACK
	if pos.distance_to(goal) > FOLLOW_SLACK:
		_move(w, e, goal)


## Empty: walk to the nearest own supply point within TRIP_R (refill happens in _think when in range).
## None in reach: give up and keep following.
static func _trip(w: SimWorld, e: Dictionary) -> void:
	var srcs: Array = _sources(w).get(int(e.owner), [])
	if not srcs.is_empty() and Supply._in_range(e, srcs, float(Content.rules().get("supply", {}).get("radius", 8))):
		return   # at a supply point: _think refills it
	var pos: Vector2 = e.pos
	var best = null
	var bd := TRIP_R
	for s in srcs:
		var p: Vector2
		if String(s.kind) == "b":
			p = Vector2(s.cell) + Vector2.ONE * (float(s.size) * 0.5)
		else:
			if int(s.id) == int(e.id):
				continue
			p = s.pos
		var d := pos.distance_to(p)
		if d < bd:
			bd = d
			best = p
	if best == null:
		e.erase("bearer_trip")
		_follow(w, e)
		return
	if bool(e.moving) and String(e.order.get("sq", "")) == WHY:
		return
	var bp: Vector2 = best
	_move(w, e, bp + (pos - bp).limit_length(2.0))
