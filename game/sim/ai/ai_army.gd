extends RefCounted
## AI army state machine (owner: agent G). Objectives: build_up -> attack -> (regroup | defend).
## Target priority while attacking: enemy units near the army (attack_move auto-engages them),
## then visible production buildings, then the HQ, then the last known HQ / public enemy spawn.
## Fairness: enemy information only from ctx.visible (= w.visible_enemies(fid)) and memory.

const U = preload("res://sim/ai/ai_util.gd")
const Mil = preload("res://sim/ai/ai_mil.gd")
const Tac = preload("res://sim/ai/ai_tactics.gd")
const G3 = preload("res://sim/ai/ai_g3.gd")
const Stage = preload("res://sim/ai/ai_stage.gd")

const DEFEND_RADIUS := 14.0
const HIT_RADIUS := 16.0
const REGROUP_FRAC := 0.4
const NEAR_ARMY := 12.0
const BUILDING_NEAR_ARMY := 16.0
const COMMIT_DIST := 18.0
## G3a: objective modes (territory sweep / bridge hold) launch earlier and with fewer units.
const OBJECTIVE_THR := 0.6
## After this tick (18 sim-minutes), or once our known salvage is gone, the side goes all-in:
## smaller launch threshold, no regrouping, continuous reinforcement. Waiting gains nothing then.
const ALL_IN_TICK := 21600
## AI4-4 decisive commit (big-map stalemates between two capped sides): an army that cannot grow
## (own pop >= MASS_FRAC of the hard pop cap) or is MASS_MULT x the launch threshold goes out as ONE
## wave: reinforcements gather into blocks, and near a visible enemy HQ with no tower in reach and
## a 2:1 local edge the whole wave focuses the HQ instead of chasing the spawn stream.
const MASS_FRAC := 0.9
const MASS_MULT := 2
const HQ_FOCUS := 18.0
## No ammo in stock and at least this share of the army dry: hold the wave at the rally.
const DRY_HOLD := 0.5
## Big maps (U.map_scale > BIG_MAP): the launch threshold scales with the map (up to BIG_THR_MAX x),
## and all-in no longer means a perpetual 3-pop trickle: a beaten wave regroups and the next one
## launches at full size (valley soak v2 s2: wave 3 of pop 9 fed by 4-6 unit trickles for 30k ticks).
const BIG_MAP := 1.2
const BIG_THR_MAX := 2.5


static func _ids(units: Array) -> Array:
	var out := []
	for e in units:
		out.append(int(e.id))
	return out


static func _pop(units: Array) -> int:
	var p := 0
	for e in units:
		p += U.pop_of(String(e.def))
	return p


static func _centroid(units: Array) -> Vector2:
	var c := Vector2.ZERO
	for e in units:
		c += Vector2(e.pos)
	return c / maxf(1.0, float(units.size()))


## Nearest visible enemy unit to the HQ within DEFEND_RADIUS, or a recent hit on our base.
static func _threat(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> Dictionary:
	var base := U.base_pos(w, fid)
	var best_d := INF
	var pos := Vector2.ZERO
	var pop := 0
	for e in ctx.visible:
		if e.kind != "unit":
			continue
		var d := Vector2(e.pos).distance_to(base)
		if d <= DEFEND_RADIUS:
			pop += U.pop_of(String(e.def))
			if d < best_d:
				best_d = d
				pos = Vector2(e.pos)
	if best_d < INF:
		return {"active": true, "pos": pos, "pop": pop}
	if w.tick - int(st.hit_tick) <= 60 and Vector2(st.hit_pos).distance_to(base) <= HIT_RADIUS:
		return {"active": true, "pos": Vector2(st.hit_pos), "pop": 0}
	return {"active": false, "pos": Vector2.ZERO, "pop": 0}


## Own pop near the hard cap (the army cannot grow any more), or an army far past the threshold.
static func massed(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, army_pop: int) -> bool:
	var f: Dictionary = w.factions[fid]
	var cap_max := int(Content.rules().pop_cap_max)
	if int(f.pop) + int(ctx.get("queued_pop", 0)) >= int(float(cap_max) * MASS_FRAC) and army_pop >= int(st.attack_pop):
		return true
	return army_pop >= MASS_MULT * maxi(6, int(st.attack_pop))


## The faction has no ammo to hand out and most of the army is dry: a wave now only feeds the enemy.
static func _ammo_starved(w: SimWorld, fid: int, army: Array) -> bool:
	if int(w.factions[fid].stock.get("ammo", 0)) >= 20 or army.is_empty():
		return false
	var dry := 0
	for e in army:
		if e.has("ammo") and float(U.ud(String(e.def)).amax) > 0.0 and float(e.ammo) <= 0.0:
			dry += 1
	return float(dry) >= DRY_HOLD * float(army.size())


static func manage_army(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var army: Array = ctx.army
	var army_pop := _pop(army) + _pop(ctx.arty)  # artillery follows the wave (ai_g3_units.gd)
	var plan: Dictionary = st.get("gather_plan", {})
	var sal_out := plan.has("salvage_left") and int(plan.salvage_left) <= 0 and int(w.factions[fid].stock.salvage) < 100
	if not bool(st.get("all_in", false)) and (w.tick >= ALL_IN_TICK or sal_out):
		st.all_in = true
		U.log_line(st, w, "going all-in (%s)" % ("salvage exhausted" if sal_out else "late game"))
	var all_in := bool(st.get("all_in", false))
	var thr := int(st.attack_pop)
	var big_map := U.map_scale(w) > BIG_MAP
	if big_map:
		thr = int(round(float(thr) * minf(BIG_THR_MAX, U.map_scale(w))))
	var trickle := all_in and not big_map  # small maps: all-in reinforces continuously, never regroups
	var obj_mode := float(st.g3.terms.territory) > 0.0 or int(st.g3.terms.bridge) > 0
	if obj_mode:
		thr = maxi(6, int(round(float(thr) * OBJECTIVE_THR)))
	# AI5-3: an all-in trickle on a small map still launches at the full threshold (half-size waves of
	# 5-7 pop fed river s2's tower line for 80k ticks); reinforcement stays continuous once out.
	var threat := _threat(w, fid, st, ctx)
	if threat.active:
		st.threat_tick = w.tick
		st.threat_pos = threat.pos
	var obj := String(st.objective)
	var group := []
	var ag := U.ag_set(st, ctx)  # G3b: O(1) membership (waves of thousands)
	for e in army:
		if ag.has(int(e.id)):
			group.append(e)
	var keep := _ids(group)  # drop the dead; held (broken / resupplying) members stay in the wave
	for e in ctx.held:
		if ag.has(int(e.id)):
			keep.append(int(e.id))
	st.attack_group = keep
	_momentum(w, fid, st)
	if obj == "attack":
		var committed := false
		var finishing := false
		var foe_pop := 0
		if not group.is_empty():
			var c := _centroid(group)
			committed = c.distance_to(Vector2(st.attack_target)) <= COMMIT_DIST
			var hq_near := false
			var foes_near := false
			for e in ctx.visible:
				var d := Vector2(e.pos).distance_to(c)
				if e.kind == "unit" and d <= NEAR_ARMY:
					foes_near = true
				elif e.kind == "building" and U.is_hq_def(String(e.def)) and d <= COMMIT_DIST:
					hq_near = true
			committed = committed or hq_near
			finishing = hq_near and not foes_near
			# winning locally (no tower in reach, clearly outnumbering what we see): keep pushing
			var tower_near := false
			for e in ctx.visible:
				var d2 := Vector2(e.pos).distance_to(c)
				if e.kind == "unit" and d2 <= 14.0:
					foe_pop += U.pop_of(String(e.def))
				elif e.kind == "building" and _armed(e) and d2 <= 11.0:
					tower_near = true
			if not tower_near and _pop(group) >= 4 and _pop(group) * 2 >= foe_pop * 3:
				finishing = true
		# AI5: a decisive wave committed at the target holds there (reinforcements arrive in blocks)
		# while it still matches the local enemy pop; walking back across a big map only to relaunch
		# gave heartland v3 s1 27 launches and valley v3 s2 70-97 regroups at "down to 9 of 25".
		var hold_on := bool(st.get("decisive", false)) and committed and _pop(group) >= maxi(4, foe_pop)
		if group.is_empty() or (not finishing and not trickle and not hold_on and group.size() < int(ceil(REGROUP_FRAC * float(int(st.launch_size))))):
			st.failed_waves = int(st.failed_waves) + 1
			_set_obj(w, st, "regroup", "attack group down to %d of %d; falling back" % [group.size(), int(st.launch_size)])
			Tac.release(w, fid, st, ctx, "wave too weak, regrouping")
			_move_all(w, fid, st, army, Vector2(st.rally), "regroup")
			st.attack_group = []
			return
		# pull home only for a real threat: comparable to the attack group (base defences and
		# fresh production handle small raids), or when the group is too small to matter
		var gpop := _pop(group)
		var serious := int(threat.pop) * 2 >= gpop or gpop < 6
		if threat.active and not committed and serious and not all_in:
			_set_obj(w, st, "defend", "base under threat at %s; pulling the army home" % str(threat.pos.round()))
			Tac.release(w, fid, st, ctx, "base under threat")
			_defend(w, fid, st, army, threat.pos)
			return
		# G3a: the wave follows the current objective (target side's HQ, a sector, the bridge)
		var goal := G3.objective(w, fid, st, ctx, _centroid(group))
		if String(goal.kind) == "bridge":
			G3.note_bridge(w, fid, st, ctx, _centroid(group))
		Tac.retarget(w, fid, st, ctx, Vector2(goal.pos))
		# G2: the officer drives the wave until it nears enemy buildings; a withdraw report regroups
		var mode := Tac.manage_mission(w, fid, st, ctx, group)
		if mode == "withdraw":
			st.failed_waves = int(st.failed_waves) + 1
			_set_obj(w, st, "regroup", "officer withdrew the wave; rebuilding")
			st.attack_group = []
			return
		Tac.manage_flank(w, fid, st, ctx, group)
		if mode == "push":
			var flanking := Tac.flank_ids(st)
			var push_group := []
			for e in group:
				if not flanking.has(int(e.id)):
					push_group.append(e)
			if not push_group.is_empty():
				_push(w, fid, st, ctx, push_group)
		_reinforce(w, fid, st, ctx, army, group, trickle, thr / 2 if big_map else 0)
		return
	if threat.active:
		if obj != "defend":
			_set_obj(w, st, "defend", "enemies at the base (%s)" % str(threat.pos.round()))
		_defend(w, fid, st, army, threat.pos)
		return
	if obj == "defend":
		if w.tick - int(st.threat_tick) < 200:
			return
		_set_obj(w, st, "build_up", "threat cleared")
		_move_all(w, fid, st, army, Vector2(st.rally), "rally")
		return
	# build_up / regroup: launch at the threshold, or early to exploit a won fight (momentum)
	# Difficulty grace period: no offensive before first_attack_tick (defence still runs above).
	# Found by the UI playtest: without it the AI razed a new player's HQ at 02:57.
	var grace := int(U.diff(w, fid).get("first_attack_tick", 0))
	if obj_mode:
		grace /= 2
	if w.tick < grace:
		return
	var exploit := float(st.momentum) >= 4.0 and army_pop * 2 >= thr
	if (army_pop >= thr or exploit) and not army.is_empty():
		if _ammo_starved(w, fid, army):
			if not bool(st.get("dry_hold", false)):
				st.dry_hold = true
				U.log_line(st, w, "holding the wave at the rally: no ammo in stock, most of the army dry")
			return
		st.dry_hold = false
		if exploit and army_pop < thr:
			U.log_line(st, w, "momentum %.1f: counter-attacking early" % float(st.momentum))
		_launch(w, fid, st, ctx, army)
		return
	var idle_far := []
	for e in army:
		if String(e.order.type) == "idle" and not e.moving and Vector2(e.pos).distance_to(Vector2(st.rally)) > 6.0:
			idle_far.append(e)
	if not idle_far.is_empty():
		_move_all(w, fid, st, idle_far, Vector2(st.rally), "rally")


## Recent kills minus losses of OUR side (own faction stats), decaying ~5%/think.
static func _momentum(w: SimWorld, fid: int, st: Dictionary) -> void:
	var stats: Dictionary = w.factions[fid].stats
	var dk := int(stats.killed) - int(st.prev_killed)
	var dl := int(stats.lost) - int(st.prev_lost)
	st.prev_killed = int(stats.killed)
	st.prev_lost = int(stats.lost)
	st.momentum = snappedf(float(st.momentum) * 0.95 + float(dk - dl), 0.001)


static func _set_obj(w: SimWorld, st: Dictionary, obj: String, why: String) -> void:
	if String(st.objective) != obj:
		if obj != "attack":
			st.decisive = false
		st.objective = obj
		st.army_mode = ""
		st.focus_id = -1
		U.log_line(st, w, "objective -> %s: %s" % [obj, why])


static func _move_all(w: SimWorld, fid: int, st: Dictionary, units: Array, target: Vector2, key: String) -> void:
	if units.is_empty():
		return
	U.submit(w, fid, st, {"type": "move", "unit_ids": _ids(units), "target": target}, key)


static func _amove(w: SimWorld, fid: int, st: Dictionary, units: Array, target: Vector2, key: String) -> bool:
	if units.is_empty():
		return false
	var ok := U.submit(w, fid, st, {"type": "attack_move", "unit_ids": _ids(units), "target": target}, key)
	if ok:
		var half := U.map_center(w)
		var mine := Vector2(w.factions[fid].spawn)
		# count attack_moves into the far half of the map (used by the inspector and tests)
		if (target - half).dot(mine - half) < 0.0:
			st.amoves_enemy_half = int(st.amoves_enemy_half) + 1
	return ok


static func _launch(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, army: Array) -> void:
	var obj := G3.objective(w, fid, st, ctx, _centroid(army))
	var tgt := Vector2(obj.pos)
	st.attack_target = tgt
	# approach route (personality): direct, or via one of the two fords (public map crossings);
	# a bridge seen ruined moves route 0 to a ford (Tac.effective_route)
	var route := Tac.effective_route(st)
	var pts: Array = st.patrol
	st.attack_via = Vector2(-1, -1)
	if route == 1 and pts.size() >= 1:
		st.attack_via = Vector2(pts[0])
	elif route == 2 and pts.size() >= 3:
		st.attack_via = Vector2(pts[2])
	if Stage.multi_crossing(w):
		st.attack_via = Stage.route_via(w, fid, st, _centroid(army), tgt)  # G3b: map.bridges + fords
	st.launch_size = army.size()
	st.attack_group = _ids(army)
	st.launches = int(st.launches) + 1
	st.decisive = massed(w, fid, st, ctx, _pop(army) + _pop(ctx.arty))
	if bool(st.decisive):
		U.log_line(st, w, "decisive wave: %d units (pop %d of %d) commit together" % [army.size(), int(w.factions[fid].pop), int(w.factions[fid].pop_cap)])
	_set_obj(w, st, "attack", "army pop %d; attacking %s (wave %d)" % [_pop(army), str(tgt.round()), int(st.launches)])
	if Tac.officer(w, fid, st, ctx) != null and String(obj.kind) != "sector":
		# G2: march out, then the officer takes command and handles the crossing itself
		st.attack_via = Vector2(-1, -1)
		_amove(w, fid, st, army, tgt, "push")
		Tac.take_command(w, fid, st, ctx, army)
	else:
		_amove(w, fid, st, army, _waypoint(st, tgt), "push")
	st.army_mode = "push"


## While a via-point is set the group marches there first.
static func _waypoint(st: Dictionary, tgt: Vector2) -> Vector2:
	var via := Vector2(st.attack_via)
	return via if via.x >= 0.0 else tgt


static func _defend(w: SimWorld, fid: int, st: Dictionary, army: Array, pos: Vector2) -> void:
	var send := []
	for e in army:
		var o: Dictionary = e.order
		var going := String(o.type) == "attack_move" and Vector2(o.get("target", Vector2.ZERO)).distance_to(pos) < 6.0
		if not going and String(o.type) != "attack":
			send.append(e)
	if not send.is_empty():
		_amove(w, fid, st, send, pos, "defend")


## Main attack logic for the launched group.
static func _push(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, group: Array) -> void:
	var c := _centroid(group)
	if bool(st.get("decisive", false)) and _focus_hq(w, fid, st, ctx, group, c):
		return
	var near_unit = null
	var near_d := INF
	var bld = null
	var bld_rank := 99
	for e in ctx.visible:
		var d := Vector2(e.pos).distance_to(c)
		if e.kind == "unit":
			if d <= NEAR_ARMY and d < near_d:
				near_d = d
				near_unit = e
		elif d <= BUILDING_NEAR_ARMY:
			var rank := 2
			var gone := (st.g3.eliminated as Array).has(int(e.owner))
			if _armed(e):
				rank = 0
			elif gone:
				continue  # a beaten side's leftover buildings are not worth a wave
			elif U.is_hq_def(String(e.def)):
				rank = 1  # hq_elimination: the HQ ends the match
			elif Content.building(String(e.def)).has("produces"):
				rank = 2
			else:
				rank = 3
			if rank < bld_rank:
				bld_rank = rank
				bld = e
	if near_unit != null:
		# 1. enemy units near the army: attack_move onto them (units auto-engage the nearest)
		if String(st.army_mode) != "engage" or _any_idle(group):
			_amove(w, fid, st, group, Vector2(near_unit.pos), "engage")
			st.army_mode = "engage"
			st.focus_id = -1
		return
	if bld != null:
		# 2./3. focus fire: production buildings, then others, then the HQ (target is visible now)
		if int(st.focus_id) != int(bld.id) or _any_idle(group):
			if U.submit(w, fid, st, {"type": "attack", "unit_ids": _ids(group), "target_id": int(bld.id)}, "focus"):
				st.focus_id = int(bld.id)
				st.army_mode = "focus"
				U.log_line(st, w, "focus fire on %s at %s" % [String(bld.def), str(Vector2(bld.pos).round())])
		return
	# 4. nothing visible near the army: march (via the route point) on the last known HQ, then search
	var via := Vector2(st.attack_via)
	if via.x >= 0.0 and c.distance_to(via) < 6.0:
		st.attack_via = Vector2(-1, -1)
		U.log_line(st, w, "attack group crossed at %s" % str(via.round()))
	var obj := G3.objective(w, fid, st, ctx, c)
	var tgt := Vector2(obj.pos)
	if String(obj.kind) != "base":
		# territory / bridge: hold the point (attack_move auto-engages); no search spiral
		if c.distance_to(tgt) < G3.SECTOR_REACHED and not _any_idle_far(group, tgt, 6.0):
			st.attack_target = tgt
			return
	elif c.distance_to(tgt) < 5.0 and not bool(st.known_contacts.get("enemy_hq_known", false)):
		st.search_i = int(st.search_i) + 1
		var ang := float(int(st.search_i) % 8) * TAU / 8.0
		tgt = tgt + Vector2(cos(ang), sin(ang)) * 10.0 * U.map_scale(w)
		tgt = tgt.clamp(Vector2(2, 2), Vector2(float(w.map.w) - 3.0, float(w.map.h) - 3.0))
	if tgt.distance_to(Vector2(st.attack_target)) > 2.0 or String(st.army_mode) != "push" or _any_idle(group):
		st.attack_target = tgt
		_amove(w, fid, st, group, _waypoint(st, tgt), "push")
		st.army_mode = "push"
		st.focus_id = -1


## Decisive wave at a visible enemy HQ: no armed building in reach and a 2:1 local edge -> the
## whole wave fires on the HQ (hq_elimination ends the match) instead of chasing fresh spawns.
static func _focus_hq(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, group: Array, c: Vector2) -> bool:
	var hq = null
	var hq_d := INF
	var foe_pop := 0
	for e in ctx.visible:
		var d := Vector2(e.pos).distance_to(c)
		if e.kind == "unit":
			if d <= 14.0:
				foe_pop += U.pop_of(String(e.def))
		elif _armed(e):
			if d <= 11.0:
				return false
		elif U.is_hq_def(String(e.def)) and d <= HQ_FOCUS and d < hq_d and not (st.g3.eliminated as Array).has(int(e.owner)):
			hq = e
			hq_d = d
	if hq == null or _pop(group) < 2 * foe_pop:
		return false
	if int(st.focus_id) != int(hq.id) or _any_idle(group):
		if U.submit(w, fid, st, {"type": "attack", "unit_ids": _ids(group), "target_id": int(hq.id)}, "focus"):
			st.focus_id = int(hq.id)
			st.army_mode = "focus"
			U.log_line(st, w, "decisive wave: focus fire on the enemy HQ at %s" % str(Vector2(hq.pos).round()))
	return true


static func _any_idle(units: Array) -> bool:
	for e in units:
		if String(e.order.type) == "idle" and not e.moving:
			return true
	return false


## Units that joined after launch wait at the rally point and go out in small waves
## (a third of the threshold, at least 4 pop; any 3 pop when all-in).
static func _reinforce(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, army: Array, group: Array, all_in: bool, need_min: int = 0) -> void:
	var reserve := []
	var ag := U.ag_set(st, ctx)
	for e in army:
		if not ag.has(int(e.id)):
			reserve.append(e)
	var need := maxi(need_min, 3 if all_in else maxi(4, int(st.attack_pop) / 3))  # big maps: blocks of half a wave
	# AI4-4: a decisive wave is fed in blocks, not a 3-pop trickle across a big map; at the hard
	# cap the reserve only grows as the wave loses units, so blocks of 6 pop go
	var f: Dictionary = w.factions[fid]
	if int(f.pop) >= int(float(int(Content.rules().pop_cap_max)) * MASS_FRAC):
		need = mini(need, 6)
	elif bool(st.get("decisive", false)):
		need = maxi(need, maxi(6, int(st.attack_pop) / 3))
	if reserve.is_empty() or _pop(reserve) < need:
		return
	var tgt := Vector2(st.attack_target)
	if not group.is_empty():
		tgt = _centroid(group)
	if _amove(w, fid, st, reserve, tgt, "reinforce"):
		for e in reserve:
			st.attack_group.append(int(e.id))
		st.launch_size = int(st.launch_size) + reserve.size()
		U.log_line(st, w, "reinforcement wave of %d sent" % reserve.size())
		Tac.add_members(w, fid, st, ctx, st.attack_group)


## Enemy building with a weapon (guard tower, bunker, sentry).
static func _armed(e: Dictionary) -> bool:
	return e.kind == "building" and String(Content.building(String(e.def)).get("weapon", "")) != ""


static func _any_idle_far(units: Array, p: Vector2, r: float) -> bool:
	for e in units:
		if String(e.order.type) == "idle" and not e.moving and Vector2(e.pos).distance_to(p) > r:
			return true
	return false
