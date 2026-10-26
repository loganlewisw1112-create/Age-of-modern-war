extends RefCounted
## SquadAI (G6.1, owner: SQUAD61). Squads (e.squad) and platoons (e.platoon) fight as one unit, for the
## player and the AI: shared targets (leader picks, focus fire with an overkill split, role-aware), the
## squad returns fire when any member is hit, idle members move up to support an engaged squadmate,
## cohesion (leash on the leader), smart soldiers (cover / height, spread vs splash, low-HP fallback,
## low-ammo pull-back, prone when suppressed, vehicles reverse out of AT range, kiting) and stances.
## Commands: set_stance {issuer, unit_ids, stance}, regroup {issuer, unit_ids}.
##
## Stances (e.stance, saved; absent = default G6 behaviour):
##   aggressive     engage at max range, pursue a lost target to its last seen spot.
##   defensive      hold the area (e.stance_anchor), return fire, chase at most DEF_CHASE tiles.
##   hold_fire      only self-defence: an idle unit carries order {type:"hold_fire"}, which Combat treats as a
##                  forced order (return fire only, never auto-acquire).
##   hold_position  never moves: an idle unit carries order {type:"hold"} (Combat: fire within range only).
## Player control first: a unit whose owner gave it a direct order within PLAYER_TICKS (e.sq_pt, stamped by
## on_direct_order; AiCommand.player_fresh and Ops override honoured too) is never re-ordered, and a unit on
## hold / hold_position is never moved. Moves this system issues carry order.sq = reason, so they are never
## mistaken for a player's order.
## Entity fields (saved, hashed; only on units that use the feature): stance, stance_anchor, sq_pt, sq_last
## [tid, pos, tick], sq_cd (tick of the last smart move), prone, pace_grp.
## Thinking: each unit every EVERY ticks ((tick + id) % EVERY == 0, bucketed by id); a squad thinks on its
## first live member's slot. Runtime cache w.cache.sq61 (never saved, rebuilt from state; see _cache).

const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Terrain = preload("res://sim/terrain.gd")
const Elevation = preload("res://sim/systems/elevation.gd")

const EVERY := 10                 # think period per unit (0.5 s)
const PLAYER_TICKS := 400         # 20 s player-order override window
const HIT_RECENT := 40            # a hit within 2 s counts for return fire
const LEASH := 6.0                # tiles from the squad leader before a straggler catches up
const DEF_CHASE := 8.0            # defensive stance: max chase distance from the anchor
const LOW_HP := 0.35
## Kite only from a threat whose weapon does at least this fraction of its damage against our armour.
const KITE_MIN_MULT := 0.25
const LOW_AMMO := 0.2
const SMART_CD := 60              # ticks between two smart repositions of one unit
const SUPPORT_R := 14.0           # idle squad/platoon mates within this move up to an engaged mate
const PACE_AHEAD := 1.5           # paced group: a member this far ahead of the slowest waits
const STANCES := ["aggressive", "defensive", "hold_fire", "hold_position"]


# ================================================================ public API (OFF61 / CHAIN61 / UI)
static func stance_of(e: Dictionary) -> String:
	return String(e.get("stance", ""))


## Doctrine / chain of command sets a stance without a player stamp (ids not validated for owner).
static func set_stance_internal(w: SimWorld, ids: Array, stance: String) -> void:
	for raw in ids:
		var e = w.entities.get(int(raw))
		if e == null or e.kind != "unit":
			continue
		_set_stance(w, e, stance)


## Alive member ids of a squad, ascending.
static func squad_members(w: SimWorld, squad_id: int) -> Array:
	var c := _cache(w)
	var out := []
	for id in c.squads.get(squad_id, []):
		var e = w.entities.get(id)
		if e != null and int(e.get("squad", -1)) == squad_id:
			out.append(int(id))
	return out


static func platoon_members(w: SimWorld, gid: int) -> Array:
	var c := _cache(w)
	var out := []
	for id in c.plats.get(gid, []):
		var e = w.entities.get(id)
		if e != null and int(e.get("platoon", -1)) == gid:
			out.append(int(id))
	return out


## Squad leader: a member with a rank_role, else the lowest id. -1 when the squad is gone.
## G6.1 (INTEG61, BEARER61 CR seq 332): ammo bearers never lead while a non-bearer member lives.
static func leader_of(w: SimWorld, members: Array) -> int:
	var first := -1
	for id in members:
		var e: Dictionary = w.entities[id]
		if bool(Content.unit(String(e.get("def", ""))).get("ammo_bearer", false)):
			continue
		if first < 0:
			first = int(id)
		if String(e.get("rank_role", "")) != "":
			return int(id)
	if first >= 0:
		return first
	return int(members[0]) if not members.is_empty() else -1


## Summary for doctrine / UI: {id, leader, members, alive, hp, ammo, stance, engaged, target, order,
## suppressed, formation}. {} when the squad has no live member.
static func squad_state(w: SimWorld, squad_id: int) -> Dictionary:
	var m := squad_members(w, squad_id)
	if m.is_empty():
		return {}
	var hp := 0.0
	var hpm := 0.0
	var am := 0.0
	var amm := 0.0
	var engaged := false
	var supp := 0
	var tgt := -1
	for id in m:
		var e: Dictionary = w.entities[id]
		hp += float(e.hp)
		hpm += float(e.max_hp)
		if e.has("ammo"):
			am += float(e.ammo)
			amm += float(Content.unit(String(e.def)).get("ammo_max", e.ammo))
		if int(e.target) >= 0:
			engaged = true
			if tgt < 0:
				tgt = int(e.target)
		if bool(e.get("pinned", false)) or bool(e.get("prone", false)):
			supp += 1
	var le: Dictionary = w.entities[leader_of(w, m)]
	return {"id": squad_id, "leader": int(le.id), "members": m, "alive": m.size(),
		"hp": hp / maxf(hpm, 1.0), "ammo": am / amm if amm > 0.0 else 1.0, "stance": stance_of(le),
		"engaged": engaged, "target": tgt, "order": String(le.order.get("type", "idle")), "suppressed": supp,
		"formation": String(le.get("formation", ""))}


## Chain of command (CHAIN61) / doctrine: the squad executes an order. order = {type: move | attack_move |
## hold | regroup | stance, target: Vector2, stance}. Members under a fresh player order are skipped.
static func execute_order(w: SimWorld, squad_id: int, order: Dictionary) -> void:
	var ids := []
	for id in squad_members(w, squad_id):
		if not player_fresh(w, w.entities[id]):
			ids.append(id)
	if ids.is_empty():
		return
	var t := String(order.get("type", ""))
	match t:
		"move", "attack_move":
			var tg = order.get("target")
			if typeof(tg) != TYPE_VECTOR2:
				return
			Movement.apply_command(w, {"type": t, "unit_ids": ids, "target": tg})
		"hold":
			Movement.apply_command(w, {"type": "hold", "unit_ids": ids})
		"regroup":
			_regroup(w, ids, false)
		"stance":
			set_stance_internal(w, ids, String(order.get("stance", "")))


## world.gd calls this for every applied direct order (CR to ORCH). Stamps the player-order tick on a human
## side's units; AI sides and AI-commander commands (cmd.ai_cmd) are not stamped.
static func on_direct_order(w: SimWorld, cmd: Dictionary) -> void:
	if cmd.has("ai_cmd") or w.ai_state.has(int(cmd.get("issuer", -1))):
		return
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null and e.kind == "unit":
			e.sq_pt = w.tick
			e.erase("prone")


static func player_fresh(w: SimWorld, e: Dictionary) -> bool:
	if e.has("sq_pt") and w.tick - int(e.sq_pt) < PLAYER_TICKS:
		return true
	if e.has("player_order_tick") and w.tick - int(e.player_order_tick) < PLAYER_TICKS:
		return true
	return int(e.get("ops_override_until", -1)) > w.tick


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	match String(cmd.type):
		"set_stance":
			var s := String(cmd.get("stance", ""))
			if not STANCES.has(s) and s != "default":
				return "Stance must be aggressive, defensive, hold fire, hold position or default."
			if (cmd.get("unit_ids", []) as Array).is_empty():
				return "Select units first."
			return ""
		"regroup":
			if (cmd.get("unit_ids", []) as Array).is_empty():
				return "Select units first."
			for raw in cmd.unit_ids:
				var e = w.entities.get(int(raw))
				if e != null and (int(e.get("squad", -1)) >= 0 or int(e.get("platoon", -1)) >= 0):
					return ""
			return "Only squads and platoons can regroup."
	return "Unknown order."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var ids := []
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null and e.kind == "unit":
			ids.append(int(raw))
	ids.sort()
	match String(cmd.type):
		"set_stance":
			set_stance_internal(w, ids, String(cmd.stance))
		"regroup":
			_regroup(w, ids, true)
			on_direct_order(w, {"issuer": cmd.issuer, "unit_ids": ids})


static func _set_stance(w: SimWorld, e: Dictionary, stance: String) -> void:
	var ot := String(e.order.get("type", "idle"))
	if stance == "" or stance == "default":
		e.erase("stance")
		e.erase("stance_anchor")
		if ot == "hold_fire":
			e.order = {"type": "idle"}
		return
	e.stance = stance
	e.stance_anchor = e.pos
	if ot == "hold_fire" and stance != "hold_fire":
		e.order = {"type": "idle"}
	if stance == "hold_position" and (ot == "idle" or ot == "hold_fire"):
		e.order = {"type": "hold"}
		Movement.stop_path(e)
	elif stance == "hold_fire" and (ot == "idle" or ot == "hold"):
		e.order = {"type": "hold_fire"}
		e.target = -1
		Movement.stop_path(e)
	elif ot == "hold" and stance != "hold_position" and not e.has("sq_pt"):
		pass  # a player's Hold stays a Hold until the player orders otherwise


## Squads (or platoons, for units without a squad) reform on their leader in the leader's formation.
static func _regroup(w: SimWorld, ids: Array, player: bool) -> void:
	var groups := {}
	var keys := []
	for id in ids:
		var e: Dictionary = w.entities[id]
		var k := ""
		if int(e.get("squad", -1)) >= 0:
			k = "s%d" % int(e.squad)
		elif int(e.get("platoon", -1)) >= 0:
			k = "p%d" % int(e.platoon)
		else:
			continue
		if not groups.has(k):
			groups[k] = []
			keys.append(k)
		groups[k].append(id)
	keys.sort()
	for k in keys:
		var full: Array = squad_members(w, int(String(k).substr(1))) if String(k)[0] == "s" else platoon_members(w, int(String(k).substr(1)))
		if full.is_empty():
			continue
		var lid := leader_of(w, full)
		var le: Dictionary = w.entities[lid]
		var mem := []
		for id in full:
			var e: Dictionary = w.entities[id]
			if id == lid or String(e.order.get("type", "")) == "hold" or stance_of(e) == "hold_position":
				continue
			if not player and player_fresh(w, e):
				continue
			mem.append(e)
		if mem.is_empty():
			continue
		var lp: Vector2 = le.pos
		var slots := Movement.formation_slots(w, [le] + mem, lp)
		var off: Vector2 = lp - Vector2(slots[0])
		for i in mem.size():
			var e: Dictionary = mem[i]
			_ai_move(w, e, _clamp(w, Vector2(slots[i + 1]) + off), "move", "regroup")


# ================================================================ helpers
static func _clamp(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 0.5, float(w.map.w) - 0.5), clampf(p.y, 0.5, float(w.map.h) - 0.5))


## A move / attack_move this system issues (order.sq = reason). False when no path.
static func _ai_move(w: SimWorld, e: Dictionary, goal: Vector2, type: String, why: String) -> bool:
	if _immobile(e):
		return false   # a mobility-killed / out-of-fuel unit keeps its order and keeps shooting
	goal = _clamp(w, goal)
	e.target = -1
	if type == "attack_move":
		e.order = {"type": "attack_move", "target": goal, "engaged": false, "sq": why}
	else:
		e.order = {"type": "move", "target": goal, "sq": why}
	if not Movement.order_path(w, e, goal):
		e.order = {"type": "idle"}
		return false
	e.sq_cd = w.tick
	return true


## Same immobility test as Status.move_mult (mobility component 0 or no fuel): squad AI never moves such a unit.
static func _immobile(e: Dictionary) -> bool:
	if e.has("comp") and float(e.comp.get("mobility", 100)) <= 0.0:
		return true
	return e.has("fuel") and float(e.fuel) <= 0.0


## Membership changed outside production / company formation (e.g. an ammo bearer joins a squad): call this so
## the squad index is rebuilt (saved counter, created on first use).
static func touch(w: SimWorld) -> void:
	if not w.sys_state.has("squad_ai"):
		w.sys_state["squad_ai"] = {"ver": 0}
	w.sys_state.squad_ai.ver = int(w.sys_state.squad_ai.ver) + 1


# ================================================================ cache
## w.cache.sq61 (never saved): buckets[k] = unit ids with id % EVERY == k (ascending), squads {sq: [ids]},
## plats {gid: [ids]}, pace {grp: [ids]}. Fully rebuilt when production.next_squad, ops.next_gid or
## squad_ai.ver moves (the ways squad / platoon membership of live units changes); ids spawned since the last
## look are appended in ascending order; dead ids drop out lazily. So every view is a function of state alone
## and a loaded world rebuilds the same index.
static func _cache(w: SimWorld) -> Dictionary:
	var c = w.cache.get("sq61")
	var ksq := int(w.sys_state.get("production", {}).get("next_squad", 1))
	var kg := int(w.sys_state.get("ops", {}).get("next_gid", 1))
	var kv := int(w.sys_state.get("squad_ai", {}).get("ver", 0))
	if c != null and int(c.ksq) == ksq and int(c.kg) == kg and int(c.kv) == kv:
		if int(c.nid) != int(w.next_id):
			for id in range(int(c.nid), int(w.next_id)):
				var e = w.entities.get(id)
				if e != null and e.kind == "unit":
					_add(c, e)
			c.nid = int(w.next_id)
		return c
	c = {"ksq": ksq, "kg": kg, "kv": kv, "nid": int(w.next_id), "buckets": [], "squads": {}, "plats": {}, "pace": {}, "helpers": []}
	for k in EVERY:
		c.buckets.append([])
	var ids := []
	for e in SimIndex.of(w, "unit"):
		if SimIndex.alive(w, e):
			ids.append(int(e.id))
	ids.sort()
	for id in ids:
		_add(c, w.entities[id])
	w.cache["sq61"] = c
	return c


static func _add(c: Dictionary, e: Dictionary) -> void:
	var id := int(e.id)
	c.buckets[id % EVERY].append(id)
	var sq := int(e.get("squad", -1))
	if sq >= 0:
		if not c.squads.has(sq):
			c.squads[sq] = []
		c.squads[sq].append(id)
	var gid := int(e.get("platoon", -1))
	if gid >= 0:
		if not c.plats.has(gid):
			c.plats[gid] = []
		c.plats[gid].append(id)
	_add_pace(c, e)
	var d := Content.unit(String(e.def))
	if bool(d.get("is_supply", false)) or bool(d.get("ammo_bearer", false)) or bool(d.get("med_unit", false)) 			or d.has("wounded_slots") or d.has("bearer"):
		c.helpers.append(id)


## Orders adds a paced move group (set_formation pace=true): keeps the cache equal to a rebuild.
static func on_pace_set(w: SimWorld, ids: Array) -> void:
	var c := _cache(w)
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null:
			_add_pace(c, e)


static func _add_pace(c: Dictionary, e: Dictionary) -> void:
	var pg := int(e.get("pace_grp", -1))
	if pg < 0:
		return
	if not c.pace.has(pg):
		c.pace[pg] = []
	if not c.pace[pg].has(int(e.id)):
		c.pace[pg].append(int(e.id))
		c.pace[pg].sort()


static func _first_alive(w: SimWorld, lst: Array, key: String, val: int) -> int:
	for id in lst:
		var e = w.entities.get(id)
		if e != null and int(e.get(key, -1)) == val:
			return int(id)
	return -1


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	if w.entities.is_empty():
		return
	var c := _cache(w)
	var k := posmod(-w.tick, EVERY)
	var b: Array = c.buckets[k]
	var dead := false
	for id in b:
		var e = w.entities.get(id)
		if e == null:
			dead = true
			continue
		_unit_think(w, c, e)
	if dead:
		var keep := []
		for id in b:
			if w.entities.has(id):
				keep.append(id)
		c.buckets[k] = keep


static func _unit_think(w: SimWorld, c: Dictionary, e: Dictionary) -> void:
	if bool(e.get("broken", false)) or e.has("garrisoned_in"):
		return
	# PERF61 CR 568 (hash-identical): a lone unit with nothing to do. Exactly the inputs on which the code below
	# changes nothing: no squad / pace group / stance / pending resume, not pinned or prone, no target, not hit lately.
	if int(e.target) < 0 and not e.has("sq_resume") and not e.has("prone") and String(e.get("stance", "")) == "" 			and int(e.get("squad", -1)) < 0 and int(e.get("pace_grp", -1)) < 0 and not bool(e.get("pinned", false)) 			and float(e.get("supp", 0.0)) < 60.0 and w.tick - int(e.get("last_hit_tick", -100000)) > HIT_RECENT:
		return
	var id := int(e.id)
	var sq := int(e.get("squad", -1))
	if sq >= 0:
		var lst = c.squads.get(sq)
		if lst != null and (lst as Array).size() >= 2 and _first_alive(w, lst, "squad", sq) == id:
			_squad_think(w, c, sq, lst)
	var pg := int(e.get("pace_grp", -1))
	if pg >= 0:
		var pl = c.pace.get(pg)
		if pl != null and _first_alive(w, pl, "pace_grp", pg) == id:
			_pace_think(w, pg, pl)
	var ot := String(e.order.get("type", "idle"))
	var st := String(e.get("stance", ""))
	if st != "":
		_stance_think(w, e, st, ot)
		ot = String(e.order.get("type", "idle"))
	_smart(w, c, e, ot)


static func _stance_think(w: SimWorld, e: Dictionary, st: String, ot: String) -> void:
	match st:
		"hold_position":
			if ot == "idle" or ot == "hold_fire":
				e.order = {"type": "hold"}
				Movement.stop_path(e)
		"hold_fire":
			if ot == "idle" or ot == "hold":
				e.order = {"type": "hold_fire"}
				e.target = -1
				Movement.stop_path(e)
		"defensive":
			var pos: Vector2 = e.pos
			var anc: Vector2 = e.get("stance_anchor", pos)
			if ot == "idle" and int(e.target) < 0 and not bool(e.moving):
				if pos.distance_to(anc) > 0.5:
					e.stance_anchor = pos
			elif int(e.target) >= 0 and (ot == "idle" or ot == "attack_move") and pos.distance_to(anc) > DEF_CHASE 					and not player_fresh(w, e):
				_ai_move(w, e, anc, "move", "leash")
		"aggressive":
			var tgt := int(e.target)
			if tgt >= 0:
				var t = w.entities.get(tgt)
				if t != null:
					e.sq_last = [tgt, t.pos, w.tick]
			elif ot == "idle" and e.has("sq_last"):
				var last: Array = e.sq_last
				e.erase("sq_last")
				if w.tick - int(last[2]) <= 100 and w.entities.has(int(last[0])) and not player_fresh(w, e):
					_ai_move(w, e, last[1], "attack_move", "pursue")


static func _valid_enemy(w: SimWorld, e: Dictionary, tid: int):
	if tid < 0:
		return null
	var t = w.entities.get(tid)
	if t == null or int(t.owner) == int(e.owner) or int(t.owner) == SimWorld.NEUTRAL or float(t.get("hp", 0)) <= 0.0:
		return null
	return t


## Target score for shooter e (role-aware: the weapon's armor multiplier vs the target; precision weapons
## prefer officers and crews; the squad's focus target gets a bonus; an overkilled target a malus).
static func _score(e: Dictionary, s: Dictionary, t: Dictionary, focus: int, assigned: Dictionary) -> float:
	var ts := Combat.stats(t)
	var sc := Content.armor_mult(String(s.cls), String(ts.armor))
	if int(t.id) == focus:
		sc *= 1.4
	if String(Content.unit(String(e.def)).get("role", "")) == "precision" and (String(t.get("rank_role", "")) != "" or t.has("crew")):
		sc *= 1.6
	if float(assigned.get(int(t.id), 0.0)) >= float(t.hp) * 1.3:
		sc *= 0.3
	return sc


static func _squad_think(w: SimWorld, c: Dictionary, sq: int, lst: Array) -> void:
	var mem := []
	for id in lst:
		var e = w.entities.get(id)
		if e != null and int(e.get("squad", -1)) == sq and not bool(e.get("broken", false)):
			mem.append(e)
	if mem.size() < 2:
		return
	var le: Dictionary = w.entities[leader_of(w, mem.map(func(x): return int(x.id)))]
	var pool := {}       # enemy id -> how many members target it
	var focus := -1
	var lt = _valid_enemy(w, le, int(le.target))
	if lt != null:
		focus = int(lt.id)
	for e in mem:
		var t = _valid_enemy(w, e, int(e.target))
		if t != null:
			pool[int(t.id)] = int(pool.get(int(t.id), 0)) + 1
		if w.tick - int(e.get("last_hit_tick", -100000)) <= HIT_RECENT:
			var a = _valid_enemy(w, e, int(e.get("last_attacker", -1)))
			if a != null and not pool.has(int(a.id)):
				pool[int(a.id)] = 0
	if pool.is_empty():
		_cohesion(w, mem, le)
		return
	var ids: Array = pool.keys()
	ids.sort()
	if focus < 0:
		var best := -1
		for tid in ids:
			if int(pool[tid]) > best:
				best = int(pool[tid])
				focus = int(tid)
	var assigned := {}
	var engaged_pos: Vector2 = w.entities[focus].pos
	for e in mem:
		var ot := String(e.order.get("type", "idle"))
		if ot != "idle" and ot != "hold" and ot != "attack_move":
			continue
		var s := Combat.stats(e)
		if String(s.weapon) == "":
			continue
		var fresh := player_fresh(w, e)
		var pos: Vector2 = e.pos
		var rad: float = float(s.range) if (ot == "hold" or fresh) else maxf(float(s.sight), float(s.range))
		var pick = null
		var psc := -1.0
		for tid in ids:
			var t: Dictionary = w.entities[tid]
			if not Combat.can_target(s, t):
				continue
			var d := Combat.dist_to(pos, t)
			if d > rad or d < float(s.min_range):
				continue
			var sc := _score(e, s, t, focus, assigned)
			if sc > psc:
				psc = sc
				pick = t
		if pick != null:
			if int(e.target) != int(pick.id):
				e.target = int(pick.id)
			assigned[int(pick.id)] = float(assigned.get(int(pick.id), 0.0)) + Combat.shot_damage(e, pick)
		elif ot == "idle" and int(e.target) < 0 and not bool(e.moving) and not fresh and stance_of(e) != "hold_position" 				and pos.distance_to(engaged_pos) <= SUPPORT_R + rad:
			# idle member out of reach: move up to support the engaged squad
			var dir := engaged_pos - pos
			var goal := engaged_pos - dir.normalized() * maxf(float(s.range) - 0.5, 1.0) if dir.length() > 0.01 else pos
			_ai_move(w, e, goal, "attack_move", "support")
	# platoon: idle members of other squads close by move up as well
	var gid := int(le.get("platoon", -1))
	if gid >= 0:
		for id in c.plats.get(gid, []):
			var p = w.entities.get(id)
			if p == null or int(p.get("platoon", -1)) != gid or int(p.get("squad", -1)) == sq:
				continue
			if String(p.order.get("type", "")) != "idle" or int(p.target) >= 0 or bool(p.moving) or player_fresh(w, p) 					or stance_of(p) == "hold_position" or stance_of(p) == "hold_fire" or bool(p.get("broken", false)):
				continue
			var pp: Vector2 = p.pos
			if pp.distance_to(le.pos) <= SUPPORT_R:
				_ai_move(w, p, Vector2(le.pos).lerp(pp, 0.3), "attack_move", "support")


## Quiet squad: stragglers more than LEASH tiles from the leader catch up (only units nobody else is driving).
static func _cohesion(w: SimWorld, mem: Array, le: Dictionary) -> void:
	if bool(le.moving):
		return
	var lp: Vector2 = le.pos
	for e in mem:
		if int(e.id) == int(le.id) or bool(e.moving) or String(e.order.get("type", "")) != "idle":
			continue
		if stance_of(e) == "hold_position" or player_fresh(w, e):
			continue
		var pos: Vector2 = e.pos
		var d := pos.distance_to(lp)
		if d > LEASH:
			_ai_move(w, e, lp + (pos - lp) / d * 2.0, "move", "leash")


## Paced group (set_formation pace=true): a member more than PACE_AHEAD tiles nearer its own goal than the
## slowest moving member waits (path dropped, order kept, e.sq_wait) until the slowest catches up.
static func _pace_think(w: SimWorld, pg: int, lst: Array) -> void:
	var movers := []
	var slow_speed := INF
	var slow_rem := -1.0
	for id in lst:
		var e = w.entities.get(id)
		if e == null or int(e.get("pace_grp", -1)) != pg:
			continue
		var ot := String(e.order.get("type", ""))
		if ot != "move" and ot != "attack_move" or typeof(e.order.get("target")) != TYPE_VECTOR2:
			continue
		movers.append(e)
		var sp := float(Content.unit(String(e.def)).get("speed", 1.0))
		var rem := Vector2(e.pos).distance_to(e.order.target)
		if sp < slow_speed or (sp == slow_speed and rem > slow_rem):
			slow_speed = sp
			slow_rem = rem
	if movers.size() < 2:
		return
	for e in movers:
		var rem := Vector2(e.pos).distance_to(e.order.target)
		if rem < slow_rem - PACE_AHEAD and rem > 1.0:
			if bool(e.moving) and not e.has("sq_wait"):
				Movement.stop_path(e)
				e.sq_wait = String(e.order.type)
				if String(e.order.type) == "attack_move":  # a pathless attack_move would count as arrived
					e.order = {"type": "move", "target": e.order.target, "sq": "pace"}
		elif e.has("sq_wait"):
			var t0 := String(e.sq_wait)
			e.erase("sq_wait")
			if t0 == "attack_move":
				e.order = {"type": "attack_move", "target": e.order.target, "engaged": false}
			if not Movement.order_path(w, e, e.order.target):
				e.order = {"type": "idle"}


## True when this system may re-position e now: not under a fresh player order, not on hold / hold position,
## idle or on one of its own moves (AI sides: also on an attack_move, which is resumed afterwards).
static func _free(w: SimWorld, e: Dictionary, ot: String) -> bool:
	if ot == "hold" or stance_of(e) == "hold_position" or player_fresh(w, e) or e.has("sq_wait"):
		return false
	if w.tick - int(e.get("sq_cd", -100000)) < SMART_CD:
		return false
	if ot == "idle" or not String(e.order.get("sq", "")).is_empty():
		return true
	return ot == "attack_move" and w.ai_state.has(int(e.owner))


## A smart reposition: a forced move (no auto-engage on the way); an AI attack_move resumes on arrival.
static func _reposition(w: SimWorld, e: Dictionary, goal: Vector2, why: String) -> void:
	var resume = null
	if String(e.order.get("type", "")) == "attack_move" and String(e.order.get("sq", "")).is_empty():
		resume = e.order.target
	if _ai_move(w, e, goal, "move", why) and resume != null:
		e.sq_resume = resume


static func _nearest_helper(w: SimWorld, c: Dictionary, e: Dictionary, want_med: bool, r: float):
	var best = null
	var bd := r
	var pos: Vector2 = e.pos
	for id in c.helpers:
		var h = w.entities.get(id)
		if h == null or int(h.owner) != int(e.owner) or int(h.id) == int(e.id):
			continue
		var d := Content.unit(String(h.def))
		var med := bool(d.get("med_unit", false)) or d.has("wounded_slots")
		if med != want_med:
			continue
		var dd := pos.distance_to(h.pos)
		if dd < bd:
			bd = dd
			best = h
	return best


static func _smart(w: SimWorld, c: Dictionary, e: Dictionary, ot: String) -> void:
	# resume an AI attack_move after a smart move ends
	if e.has("sq_resume") and ot == "idle":
		var r: Vector2 = e.sq_resume
		e.erase("sq_resume")
		_ai_move(w, e, r, "attack_move", "resume")
		e.order.erase("sq")
		return
	var pinned := bool(e.get("pinned", false)) or float(e.get("supp", 0.0)) >= 60.0
	if pinned:
		if not e.has("prone"):
			e.prone = true
			if not String(e.order.get("sq", "")).is_empty() and bool(e.moving):
				Movement.stop_path(e)
				e.order = {"type": "idle"}
		return
	if e.has("prone"):
		e.erase("prone")
	var tgt := int(e.target)
	var hit := w.tick - int(e.get("last_hit_tick", -100000)) <= HIT_RECENT
	if tgt < 0 and not hit:
		return
	if not _free(w, e, ot):
		return
	var s := Combat.stats(e)
	var pos: Vector2 = e.pos
	var mc := Movement.move_class(e)
	if Movement.is_air(mc):
		return
	var foot := mc == "foot"
	var t = _valid_enemy(w, e, tgt)
	var att = _valid_enemy(w, e, int(e.get("last_attacker", -1))) if hit else null
	var threat = att if att != null else t
	if threat == null:
		return
	var tp: Vector2 = threat.pos
	var away := pos - tp
	away = away.normalized() if away.length() > 0.01 else Vector2(0, 1)
	var dthr := pos.distance_to(tp)
	var ts := Combat.stats(threat)
	var hpf := float(e.hp) / maxf(float(e.max_hp), 1.0)
	# 1) vehicle outmatched by an AT weapon: reverse out of its range
	if not foot and att != null and hpf < 0.5 and Content.armor_mult(String(ts.cls), String(s.armor)) >= 1.2 			and dthr <= float(ts.range) + 1.0:
		_reposition(w, e, pos + away * (float(ts.range) + 2.5 - dthr), "reverse")
		return
	# 2) low HP: fall back behind the squad, toward a medic when one is near
	# (a lone soldier with no squad and no medic in reach holds and fights instead of running off)
	if foot and hpf < LOW_HP:
		var med = _nearest_helper(w, c, e, true, 20.0)
		if med != null or int(e.get("squad", -1)) >= 0:
			_reposition(w, e, Vector2(med.pos) if med != null else pos + away * 5.0, "fallback")
			return
	# 3) low ammo: pull back toward a supply truck / ammo bearer. A unit with a target in range keeps firing
	# until it is out; it pulls back only when empty, or low and not engaged, and only when a helper exists.
	if e.has("ammo"):
		var amax := float(Content.unit(String(e.def)).get("ammo_max", 0))
		if amax > 0.0 and float(e.ammo) < amax * LOW_AMMO:
			var engaged := t != null and pos.distance_to(Vector2(t.pos)) <= float(s.range)
			if float(e.ammo) <= 0.0 or not engaged:
				var sup = _nearest_helper(w, c, e, false, 25.0)
				if sup != null:
					_reposition(w, e, Vector2(sup.pos), "resupply")
					return
	if t == null:
		return
	# G6.1 (INTEG61-2): a unit that conceals by standing still (G4b conceal_still: sniper, special forces) holds:
	# kiting or spreading would move it and break or never reach its concealment (test_units_g4b
	# sniper_conceal_still, test_units_g5 special_forces_conceal). The player can still move it.
	if bool(e.get("hid", false)) or bool(Content.unit(String(e.def)).get("conceal_still", false)):
		return
	var rng := float(s.range)
	var trng := float(ts.range)
	var dt := pos.distance_to(Vector2(t.pos))
	# 4) kiting: out-range the target, step back to our own range when it closes inside its range. Only from a
	# threat that can really hurt us (owner test 2026-10-26: an MBT backed away from a rifleman, whose rifle does 5%
	# against heavy armour, and showed it its rear armour); a tank holds against rifles and autocannons.
	if rng > trng + 1.0 and dt < trng + 0.5 and Combat.can_target(ts, e) 			and Content.armor_mult(String(ts.cls), String(s.armor)) >= KITE_MIN_MULT:
		_reposition(w, e, pos + away * (rng - 0.5 - dt), "kite")
		return
	# 5) spread out against splash
	if float(ts.splash) > 0.0 or bool(ts.indirect):
		var sq := int(e.get("squad", -1))
		for id in c.squads.get(sq, []):
			var m = w.entities.get(id)
			if m == null or int(m.id) == int(e.id) or int(m.get("squad", -1)) != sq:
				continue
			var mp: Vector2 = m.pos
			if mp.distance_to(pos) < 1.2:
				var off := pos - mp
				off = off.normalized() if off.length() > 0.01 else Vector2(1, 0)
				_reposition(w, e, pos + off * 1.6, "spread")
				return
	# 6) foot soldiers in the open take cover / height within 2 tiles, still in range of the target
	if foot and not bool(e.moving) and dt <= rng:
		_take_cover(w, e, t, rng)


static func _cell_value(w: SimWorld, cell: Vector2i) -> float:
	var v := 1.0 - Terrain.cover_mult(w.terrain_at(cell), "foot")
	if Elevation.has_height(w):
		v += 0.1 * float(Elevation.height_at(w, cell))
	return v


static func _take_cover(w: SimWorld, e: Dictionary, t: Dictionary, rng: float) -> void:
	var pos: Vector2 = e.pos
	var here := w.cell_of(pos)
	var best_v := _cell_value(w, here) + 0.05
	var best := Vector2i(-1, -1)
	var tp: Vector2 = t.pos
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx == 0 and dy == 0:
				continue
			var cell := here + Vector2i(dx, dy)
			if not w.in_bounds(cell) or not Movement.is_passable(w, cell, "foot", Movement.team_of(w, e)):
				continue
			var p := Vector2(cell) + Movement.CENTER
			if p.distance_to(tp) > rng:
				continue
			var v := _cell_value(w, cell)
			if v > best_v:
				best_v = v
				best = cell
	if best.x >= 0:
		_reposition(w, e, Vector2(best) + Movement.CENTER, "cover")
