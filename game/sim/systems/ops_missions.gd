extends RefCounted
## Officer mission state machine (owner: agent C2), split out of ops.gd. Must NOT preload ops.gd.
## Contract: docs/CONTRACTS_G2.md section 4. Evaluated every 10 ticks per group (staggered by gid).
##
## Area missions (secure_point, hold_zone, attack_area): assess -> move -> secure -> hold.
##   secure_point / hold_zone succeed when no visible enemy is within radius of the target and >= 50%
##   of members are inside the radius for SECURE_TICKS. attack_area holds once no visible enemy is
##   left within radius. hold_zone then sets the hold stance. Enemy contact in hold -> secure again.
## patrol_route: assess -> move, cycling target + points with attack_move.
## transport_to_point (G4 TRANS): assess -> load (members board the group's carriers, greedy by
##   ascending id; the officer rides too when there is room; the rest attack-move) -> transit (the
##   carriers drive to the target and unload around it) -> move -> secure -> hold, as secure_point.
##   load ends when nobody is still boarding or after LOAD_TIMEOUT; transit ends when every live
##   carrier is empty, or after TRANSIT_TIMEOUT (the carriers then unload where they are).
## Any mission: mean ammo < rules.ops.resupply_ammo_frac -> resupply (nearest own built HQ/depot or
##   logistics truck) and back; losses > risk bound of starting strength -> withdraw to the nearest
##   own HQ/depot, result "failed", then idle.
## G6 (AI7-DOC, CONTRACTS_G6 section 16): special-operations and extraction missions on the same groups
##   (DOC_MISSIONS; ops.gd set_mission accepts them through validate_doc / init_doc). Extra mission keys:
##   target_id, extract [ids], safe (return point), t0, seen; g.last_doc = {type, result, tick, extracted}
##   records the outcome once the mission ends (the group then idles, mission {}).
##   recon: move (no engagement) -> observe (count visible enemies) -> return.
##   raid: attack-move in -> strike (hunt visible gatherers / trucks for raid_ticks) -> return.
##   sabotage: move -> strike (attack the target building until it is gone) -> return.
##   officer_hunt: move to the last seen position -> strike (attack the officer while visible) -> return.
##   exfil: fight to the extraction point -> secure (the extractees join; wounded wait for evacuation)
##   -> extract (everyone moves to the safe point) -> success when they are inside safe_radius.
##   Any doc mission past mission_timeout returns with result "failed". The G2 missions are unchanged.

const Movement = preload("res://sim/systems/movement.gd")
const Fog = preload("res://sim/systems/fog.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")  # G3b scale (PERF5): per-kind lists
const Subsets = preload("res://sim/systems/unit_subsets.gd")  # G3b scale (PERF5): per-def unit subsets
const Transport = preload("res://sim/systems/transport.gd")  # G4 TRANS: transport_to_point

const HISTORY_MAX := 10
const REPORT_EVERY := 600        # 30 s without a phase change -> status report
const SECURE_TICKS := 100        # 5 s held with the area clear
const OFFICER_BACK := 2.0        # officer trails the centroid by this many tiles
const OFFICER_SLACK := 2.5
const RESUPPLY_DONE := 0.9
const RESUPPLY_TIMEOUT := 1200   # give up waiting for ammo after 60 s
const PATROL_ARRIVE := 3.0
const BASE_ARRIVE := 4.0
const LOAD_TIMEOUT := 600        # 30 s to board
const TRANSIT_TIMEOUT := 2400    # 2 min to reach the drop point
const TRANSPORT_PHASES := ["assess", "load", "transit"]
const DOC_MISSIONS := ["raid", "sabotage", "recon", "officer_hunt", "exfil"]  # G6 AI7-DOC
const DOC_DEFAULTS := {"raid_ticks": 400, "observe_ticks": 200, "mission_timeout": 4800, "exfil_radius": 5.0,
	"safe_radius": 6.0, "secure_ticks": 400, "evac_wait": 600}


static func _rules() -> Dictionary:
	return Content.rules().get("ops", {})


# ================================================================ reports
static func set_phase(w: SimWorld, g: Dictionary, phase: String, reason: String, progress: float) -> void:
	g.phase = phase
	g.phase_tick = w.tick
	g.reason = reason
	g.progress = snappedf(clampf(progress, 0.0, 1.0), 0.01)
	report(w, g)


## Emits OfficerReport with the group's current phase/reason/progress; keeps the last 10.
static func report(w: SimWorld, g: Dictionary) -> void:
	g.last_report = w.tick
	var h: Array = g.history
	h.append({"tick": w.tick, "phase": g.phase, "reason": g.reason, "progress": g.progress})
	while h.size() > HISTORY_MAX:
		h.pop_front()
	w.emit("OfficerReport", {"gid": int(g.id), "owner": int(g.owner), "officer": int(g.officer),
		"phase": g.phase, "reason": g.reason, "progress": g.progress})


# ================================================================ group helpers
static func members(w: SimWorld, g: Dictionary) -> Array:
	var out := []
	for id in g.members:
		var e = w.entities.get(int(id))
		if e != null and e.kind == "unit":
			# G5 (AI6 CR): wounded members (immobile) and launched drones never steer, count or pin a group
			if bool(e.get("wounded", false)) or bool(Content.unit(String(e.def)).get("launched_drone", false)):
				continue
			out.append(e)
	return out


## Members the officer may command now: not under player override, not broken/retreating.
static func controlled(w: SimWorld, g: Dictionary) -> Array:
	var out := []
	for e in members(w, g):
		if int(e.get("ops_override_until", -1)) > w.tick or bool(e.get("broken", false)):
			continue
		if String(e.order.get("type", "")) == "retreat":
			continue
		out.append(e)
	return out


static func centroid(w: SimWorld, g: Dictionary) -> Vector2:
	var ms := members(w, g)
	if ms.is_empty():
		var off = w.entities.get(int(g.officer))
		return off.pos if off != null else Vector2.ZERO
	var s := Vector2.ZERO
	for e in ms:
		s += e.pos
	return s / float(ms.size())


## Ordinary orders through Movement's own handler (deterministic, never w.submit).
static func issue(w: SimWorld, g: Dictionary, units: Array, type: String, target: Vector2) -> void:
	if units.is_empty():
		return
	var ids := []
	for e in units:
		e.erase("patrol")
		e.erase("guard")
		ids.append(int(e.id))
	Movement.apply_command(w, {"type": type, "issuer": int(g.owner), "unit_ids": ids, "target": target})


static func _ammo_frac(w: SimWorld, g: Dictionary) -> float:
	var s := 0.0
	var n := 0
	for e in members(w, g):
		var mx := int(Content.unit(e.def).get("ammo_max", 0))
		if mx > 0 and e.has("ammo"):
			s += float(e.ammo) / float(mx)
			n += 1
	return s / float(n) if n > 0 else 1.0


static func _enemies_near(w: SimWorld, fid: int, p: Vector2, r: float) -> Array:
	var out := []
	for e in Fog.visible_enemies(w, fid):
		var q: Vector2 = e.pos
		if q.distance_to(p) <= r:
			out.append(e)
	return out


## Nearest own built HQ/depot (and logistics truck if trucks=true) to p, or null.
static func _nearest_support(w: SimWorld, fid: int, p: Vector2, trucks: bool):
	# PERF5: own buildings from the index, trucks from the is_supply subset. The old single scan
	# kept the FIRST (lowest id) of equally near candidates; the id tie-break below keeps that.
	var best = null
	var bd := INF
	for e in SimIndex.of(w, "building"):
		if int(e.owner) != fid or not SimIndex.alive(w, e):
			continue
		if not (bool(Content.building(e.def).get("supply_point", false)) and bool(e.get("built", false))):  # G3a flag
			continue
		var q: Vector2 = e.pos
		var d := q.distance_to(p)
		if d < bd or (d == bd and best != null and int(e.id) < int(best.id)):
			bd = d
			best = e
	if trucks:
		for e in Subsets.units(w, Subsets.SUPPLY):
			if int(e.owner) != fid:
				continue
			var q: Vector2 = e.pos
			var d := q.distance_to(p)
			if d < bd or (d == bd and best != null and int(e.id) < int(best.id)):
				bd = d
				best = e
	return best


static func _inside(units: Array, p: Vector2, r: float) -> int:
	var n := 0
	for e in units:
		var q: Vector2 = e.pos
		if q.distance_to(p) <= r:
			n += 1
	return n


static func _pct(f: float) -> int:
	return roundi(f * 100.0)


# ================================================================ state machine
static func evaluate(w: SimWorld, g: Dictionary) -> void:
	var m: Dictionary = g.mission
	var ms := members(w, g)
	var ctl := controlled(w, g)
	var cen := centroid(w, g)
	var phase := String(g.phase)
	var fid := int(g.owner)
	var bounds: Dictionary = _rules().get("risk_loss_bound", {})
	var bound := float(bounds.get(String(m.risk), 0.5))
	if phase != "withdraw" and int(g.start) > 0 and float(g.losses) / float(g.start) > bound:
		var lf := float(g.losses) / float(g.start)
		var base = _nearest_support(w, fid, cen, false)
		var dest: Vector2 = base.pos if base != null else cen
		m.goal = dest
		g.result = "failed"
		var units := ctl.duplicate()
		var off = w.entities.get(int(g.officer))
		if off != null and int(off.get("ops_override_until", -1)) <= w.tick:
			units.append(off)
		issue(w, g, units, "move", dest)
		for c in ms:
			if Transport.is_carrier(c) and not (c.get("cargo", []) as Array).is_empty():
				Transport.order_unload(w, c, dest, [])  # carriers bring their riders home
		set_phase(w, g, "withdraw", "Losses %d%% > %s risk; withdrawing." % [_pct(lf), String(m.risk)], float(g.progress))
		return
	if phase == "withdraw":
		var dest: Vector2 = m.goal
		if ms.is_empty() or _inside(ms, dest, BASE_ARRIVE + 2.0) * 2 >= ms.size():
			g.mission = {}
			set_phase(w, g, "idle", "Withdrawal complete; mission failed.", 0.0)
			return
		var late := []
		for e in ctl:
			var q: Vector2 = e.pos
			if not e.moving and String(e.order.type) == "idle" and q.distance_to(dest) > BASE_ARRIVE + 2.0:
				late.append(e)
		issue(w, g, late, "move", dest)
		return
	if phase == "resupply":
		var a := _ammo_frac(w, g)
		if a >= RESUPPLY_DONE or w.tick - int(g.phase_tick) >= RESUPPLY_TIMEOUT:
			m.goal = m.points[int(m.i)] if String(m.type) == "patrol_route" else m.target
			issue(w, g, ctl, "attack_move", m.goal)
			var why := "Resupplied (ammo %d%%); returning to the objective." if a >= RESUPPLY_DONE else "Resupply stalled at %d%% ammo; returning to the objective."
			set_phase(w, g, "move", why % _pct(a), 0.0)
		else:
			_position_officer(w, g, ms, cen)
		return
	if phase != "assess" and phase != "load" and phase != "transit":
		var a := _ammo_frac(w, g)
		if a < float(_rules().get("resupply_ammo_frac", 0.3)):
			var src = _nearest_support(w, fid, cen, true)
			if src != null:
				m.goal = src.pos
				g.resume = phase
				issue(w, g, ctl, "move", src.pos)
				set_phase(w, g, "resupply", "Ammo at %d%%; falling back to resupply at the %s." % [_pct(a), String(src.def).replace("_", " ")], float(g.progress))
				return
	if DOC_MISSIONS.has(String(m.type)):
		_eval_doc(w, g, ctl, ms, cen)
		if (g.mission as Dictionary).is_empty():
			return
	elif String(m.type) == "patrol_route":
		_eval_patrol(w, g, ctl)
	elif String(m.type) == "transport_to_point" and TRANSPORT_PHASES.has(String(g.phase)):
		_eval_transport(w, g, ctl, ms)
		return  # the officer rides or walks on its own while the lift is under way
	else:
		_eval_area(w, g, ctl, ms, cen)
	if w.tick - int(g.last_report) >= REPORT_EVERY:
		var t: Vector2 = m.get("goal", m.target)
		var en := _enemies_near(w, fid, t, float(m.radius)).size()
		g.reason = "%s: %d units, %d under command, ammo %d%%, %d visible enemies near (%d, %d)." % [
			String(g.phase).capitalize(), ms.size(), ctl.size(), _pct(_ammo_frac(w, g)), en, int(t.x), int(t.y)]
		report(w, g)
	_position_officer(w, g, ms, cen)


static func _eval_area(w: SimWorld, g: Dictionary, ctl: Array, ms: Array, cen: Vector2) -> void:
	var m: Dictionary = g.mission
	var t: Vector2 = m.target
	var r := float(m.radius)
	var typ := String(m.type)
	var enemies := _enemies_near(w, int(g.owner), t, r)
	var inside := _inside(ms, t, r)
	var half := ms.size() > 0 and inside * 2 >= ms.size()
	var where := "(%d, %d)" % [int(t.x), int(t.y)]
	match String(g.phase):
		"assess":
			m.goal = t
			issue(w, g, ctl, "attack_move", t)
			set_phase(w, g, "move", "Moving %d units to the objective at %s." % [ctl.size(), where], 0.0)
		"move":
			g.progress = snappedf(0.5 * clampf(1.0 - cen.distance_to(t) / float(m.dist0), 0.0, 1.0), 0.01)
			_regroup(w, g, ctl, t, r)
			if half:
				g.secure_ticks = 0
				if typ == "attack_area":
					m.peak = enemies.size()
					set_phase(w, g, "secure", "On target at %s; engaging %d visible enemies." % [where, enemies.size()], 0.5)
				else:
					set_phase(w, g, "secure", "Reached %s with %d of %d units; securing the area." % [where, inside, ms.size()], 0.5)
		"secure":
			if typ == "attack_area":
				m.peak = maxi(int(m.get("peak", 0)), enemies.size())
				if enemies.is_empty():
					set_phase(w, g, "hold", "Area at %s cleared of visible enemies; holding." % where, 1.0)
					return
				g.progress = snappedf(0.5 + 0.5 * (1.0 - float(enemies.size()) / float(maxi(int(m.peak), 1))), 0.01)
				_hunt(w, g, ctl, enemies)
				return
			if enemies.is_empty() and half:
				g.secure_ticks = int(g.secure_ticks) + 10
			else:
				g.secure_ticks = 0
			g.progress = snappedf(0.5 + 0.5 * minf(float(g.secure_ticks) / float(SECURE_TICKS), 1.0), 0.01)
			_regroup(w, g, ctl, t, r)
			if int(g.secure_ticks) >= SECURE_TICKS:
				if typ == "hold_zone":
					issue(w, g, ctl, "hold", t)
					set_phase(w, g, "hold", "Zone at %s secured; holding position." % where, 1.0)
				else:
					set_phase(w, g, "hold", "Secured the objective at %s; holding." % where, 1.0)
		"hold":
			if not enemies.is_empty():
				g.secure_ticks = 0
				m.peak = enemies.size()
				set_phase(w, g, "secure", "Enemy contact: %d visible enemies at %s; re-securing." % [enemies.size(), where], 0.5)
				return
			if typ != "hold_zone":
				_regroup(w, g, ctl, t, r)
				return
			var back := []
			var settle := []
			for e in ctl:
				if String(e.order.type) != "idle" or e.moving or int(e.target) >= 0:
					continue
				var q: Vector2 = e.pos
				if q.distance_to(t) > r:
					back.append(e)
				else:
					settle.append(e)
			issue(w, g, back, "attack_move", t)
			issue(w, g, settle, "hold", t)


## Idle controlled members outside the radius attack-move back to the objective.
static func _regroup(w: SimWorld, g: Dictionary, ctl: Array, t: Vector2, r: float) -> void:
	var late := []
	for e in ctl:
		var q: Vector2 = e.pos
		if String(e.order.type) == "idle" and not e.moving and int(e.target) < 0 and q.distance_to(t) > r:
			late.append(e)
	issue(w, g, late, "attack_move", t)


## Idle controlled members attack-move onto the nearest visible enemy in the area.
static func _hunt(w: SimWorld, g: Dictionary, ctl: Array, enemies: Array) -> void:
	for e in ctl:
		if String(e.order.type) != "idle" or e.moving or int(e.target) >= 0:
			continue
		var p: Vector2 = e.pos
		var best: Vector2 = enemies[0].pos
		for en in enemies:
			var q: Vector2 = en.pos
			if q.distance_to(p) < best.distance_to(p):
				best = q
		issue(w, g, [e], "attack_move", best)


static func _eval_patrol(w: SimWorld, g: Dictionary, ctl: Array) -> void:
	var m: Dictionary = g.mission
	var pts: Array = m.points
	var n := pts.size()
	if String(g.phase) == "assess":
		m.i = 0
		m.laps = 0
		m.goal = pts[0]
		issue(w, g, ctl, "attack_move", pts[0])
		set_phase(w, g, "move", "Patrolling a %d-point route; heading to waypoint 1." % n, 0.0)
		return
	if ctl.is_empty():
		return
	var goal: Vector2 = pts[int(m.i)]
	var busy := false
	for e in ctl:
		if e.moving or int(e.target) >= 0:
			busy = true
	if _inside(ctl, goal, PATROL_ARRIVE) * 2 < ctl.size() and busy:
		return
	var reached := int(m.i) + 1
	m.i = (int(m.i) + 1) % n
	if int(m.i) == 0:
		m.laps = int(m.get("laps", 0)) + 1
	m.goal = pts[int(m.i)]
	issue(w, g, ctl, "attack_move", m.goal)
	g.progress = snappedf(float(m.i) / float(n), 0.01)
	g.reason = "Waypoint %d of %d reached; moving to waypoint %d." % [reached, n, int(m.i) + 1]
	report(w, g)


## The officer trails slightly behind the members' centroid, away from the current goal.
static func _position_officer(w: SimWorld, g: Dictionary, ms: Array, cen: Vector2) -> void:
	var off = w.entities.get(int(g.officer))
	if off == null or ms.is_empty() or int(off.get("ops_override_until", -1)) > w.tick or bool(off.get("broken", false)):
		return
	var ot := String(off.order.get("type", "idle"))
	if ot == "retreat" or ot == "attack":
		return
	var goal: Vector2 = g.mission.get("goal", cen)
	var fwd := goal - cen
	fwd = fwd / fwd.length() if fwd.length() > 0.01 else Vector2.ZERO
	var want := cen - fwd * OFFICER_BACK
	want = Vector2(clampf(want.x, 0.5, float(w.map.w) - 0.5), clampf(want.y, 0.5, float(w.map.h) - 0.5))
	var op: Vector2 = off.pos
	if op.distance_to(want) <= OFFICER_SLACK:
		return
	var cur = off.order.get("target")
	if off.moving and typeof(cur) == TYPE_VECTOR2 and (cur as Vector2).distance_to(want) <= OFFICER_SLACK:
		return
	issue(w, g, [off], "move", want)


## transport_to_point lift phases (assess -> load -> transit); then _eval_area takes over at "move".
static func _eval_transport(w: SimWorld, g: Dictionary, ctl: Array, ms: Array) -> void:
	var m: Dictionary = g.mission
	var t: Vector2 = m.target
	var where := "(%d, %d)" % [int(t.x), int(t.y)]
	match String(g.phase):
		"assess":
			var carriers := []
			var riders := []
			for e in ms:
				if Transport.is_carrier(e):
					carriers.append(e)
				elif ctl.has(e):
					riders.append(e)
			var off = w.entities.get(int(g.officer))
			if off != null and int(off.get("ops_override_until", -1)) <= w.tick and not bool(off.get("broken", false)):
				riders.append(off)
			riders.sort_custom(func(a, b): return int(a.id) < int(b.id))
			var room := {}
			for c in carriers:
				room[int(c.id)] = Transport.free_slots(c)
			var boarded := []
			var walk := []
			for u in riders:
				var put = null
				for c in carriers:
					if Transport.can_carry(c, u) == "" and Transport.cargo_size_of(String(u.def)) <= int(room[int(c.id)]):
						put = c
						break
				if put == null:
					walk.append(u)
					continue
				room[int(put.id)] = int(room[int(put.id)]) - Transport.cargo_size_of(String(u.def))
				Transport.order_board(w, u, put)
				boarded.append(int(u.id))
			var cids := []
			for c in carriers:
				cids.append(int(c.id))
			m.carriers = cids
			m.riders = boarded
			m.goal = t
			issue(w, g, walk, "attack_move", t)
			set_phase(w, g, "load", "Boarding %d units onto %d transports for %s; %d on foot." % [
				boarded.size(), cids.size(), where, walk.size()], 0.1)
		"load":
			var waiting := []
			for uid in m.riders:
				var u = w.entities.get(int(uid))
				if u != null and String(u.order.get("type", "")) == "board":
					waiting.append(u)
			if not waiting.is_empty() and w.tick - int(g.phase_tick) < LOAD_TIMEOUT:
				return
			issue(w, g, waiting, "attack_move", t)  # timed out: walk instead
			var aboard := 0
			for cid in m.carriers:
				var c = w.entities.get(int(cid))
				if c == null:
					continue
				aboard += (c.get("cargo", []) as Array).size()
				if (c.get("cargo", []) as Array).is_empty():
					issue(w, g, [c], "move", t)
				else:
					Transport.order_unload(w, c, t, [])
			set_phase(w, g, "transit", "Transports carrying %d units to %s." % [aboard, where], 0.25)
		"transit":
			var busy := []
			for cid in m.carriers:
				var c = w.entities.get(int(cid))
				if c != null and not (c.get("cargo", []) as Array).is_empty():
					busy.append(c)
			if not busy.is_empty() and w.tick - int(g.phase_tick) < TRANSIT_TIMEOUT:
				var s := 0.0
				for c in busy:
					var q: Vector2 = c.pos
					s += clampf(1.0 - q.distance_to(t) / float(m.dist0), 0.0, 1.0)
				g.progress = snappedf(0.25 + 0.25 * s / float(busy.size()), 0.01)
				return
			for c in busy:  # timed out: everyone off where they are
				c.erase("unload_order")
				var p: Vector2 = c.pos
				Transport.unload(w, c, Transport.cargo_ids(c), p, "unload")
			var now := controlled(w, g)
			issue(w, g, now, "attack_move", t)
			set_phase(w, g, "move", "Dropped off near %s; moving %d units in to secure it." % [where, now.size()], 0.5)


# ================================================================ G6 doctrine missions (AI7-DOC)
static var _docr := {}


static func _doc(key: String) -> float:
	if _docr.is_empty():
		var out: Dictionary = DOC_DEFAULTS.duplicate()
		var src = Content.rules().get("g6_doctrine", null)
		var path := "res://sim/ai/doctrine/doctrine_rules.json"
		if typeof(src) != TYPE_DICTIONARY and FileAccess.file_exists(path):
			src = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(src) == TYPE_DICTIONARY:
			for k in out:
				if (src as Dictionary).has(k):
					out[k] = src[k]
		_docr = out
	return float(_docr.get(key, 0.0))


static func _vec(v):
	if typeof(v) == TYPE_VECTOR2:
		return v
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return null


## Extra checks for a doctrine mission ("" = ok). Called by ops.gd set_mission validation.
static func validate_doc(w: SimWorld, g: Dictionary, cmd: Dictionary) -> String:
	var m := String(cmd.get("mission", ""))
	var fid := int(g.owner)
	if m == "sabotage" or m == "officer_hunt":
		var t = w.entities.get(int(cmd.get("target_id", -1)))
		if t == null or int(t.owner) == fid or int(t.owner) < 0:
			return "Pick an enemy %s as the target." % ("building" if m == "sabotage" else "officer")
		if m == "sabotage" and t.kind != "building":
			return "Sabotage needs an enemy building as the target."
		if m == "officer_hunt" and t.kind != "unit":
			return "An officer hunt needs an enemy unit as the target."
		if not Fog.entity_visible(w, fid, t) and not (w.memory.get(fid, {}) as Dictionary).has(int(t.id)):
			return "The target is not in sight."
	if m == "exfil":
		var ids = cmd.get("extract", [])
		if typeof(ids) != TYPE_ARRAY or (ids as Array).size() > 20:
			return "Exfil extracts at most 20 units."
		for raw in ids:
			var e = w.entities.get(int(raw))
			if e == null or e.kind != "unit" or int(e.owner) != fid:
				return "Only own units can be extracted."
	if cmd.has("safe"):
		var sp = _vec(cmd.safe)
		if sp == null or not w.in_bounds(w.cell_of(sp)):
			return "The safe point is outside the map."
	return ""


## Fills the doctrine fields after ops.gd set g.mission (set_mission apply).
static func init_doc(w: SimWorld, g: Dictionary, cmd: Dictionary) -> void:
	var m: Dictionary = g.mission
	var ex := []
	for raw in cmd.get("extract", []):
		ex.append(int(raw))
	ex.sort()
	m.target_id = int(cmd.get("target_id", -1))
	m.extract = ex
	var sp = _vec(cmd.get("safe"))
	if sp == null:
		var base = _nearest_support(w, int(g.owner), centroid(w, g), false)
		sp = base.pos if base != null else centroid(w, g)
	m.safe = sp
	m.t0 = w.tick
	m.seen = 0


static func _doc_end(w: SimWorld, g: Dictionary, result: String, why: String, extracted: int = 0) -> void:
	g.result = result
	g.last_doc = {"type": String(g.mission.type), "result": result, "tick": w.tick, "extracted": extracted}
	g.mission = {}
	set_phase(w, g, "idle", why, 1.0 if result == "success" else 0.0)


static func _doc_return(w: SimWorld, g: Dictionary, ctl: Array, result: String, why: String) -> void:
	var m: Dictionary = g.mission
	g.result = result
	m.goal = m.safe
	issue(w, g, ctl, "move", m.safe)
	set_phase(w, g, "return", why, 0.8)


## Direct attack on one target for the given member ids (through the world's attack handler).
static func _attack(w: SimWorld, g: Dictionary, ids: Array, tid: int) -> void:
	var t = w.entities.get(tid)
	if t == null or ids.is_empty():
		return
	var h = SimWorld.COMMANDS.get("attack")
	if h != null:
		var cmd := {"type": "attack", "issuer": int(g.owner), "unit_ids": ids, "target_id": tid}
		if String(h.validate_command(w, cmd)) == "":
			h.apply_command(w, cmd)
			return
	var us := []
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null:
			us.append(e)
	issue(w, g, us, "attack_move", t.pos)


## Officer hunt: attacks the target while the group's side can see it (fair); updates the last seen
## position. False when the target is out of sight.
static func _hunt_target(w: SimWorld, g: Dictionary, ctl: Array) -> bool:
	var m: Dictionary = g.mission
	var o = w.entities.get(int(m.target_id))
	if o == null or not Fog.entity_visible(w, int(g.owner), o):
		return false
	m.goal = o.pos
	m.target = o.pos
	var ids := []
	for e in ctl:
		if int(e.order.get("target_id", -1)) != int(o.id):
			ids.append(int(e.id))
	_attack(w, g, ids, int(o.id))
	return true


## Exfil: secure the extraction point, bring the extractees in (wounded wait for evacuation), then move
## everyone to the safe point.
static func _eval_exfil(w: SimWorld, g: Dictionary, ctl: Array, ms: Array, cen: Vector2) -> void:
	var m: Dictionary = g.mission
	var fid := int(g.owner)
	var mobile := []
	var wounded := 0
	for raw in m.extract:
		var e = w.entities.get(int(raw))
		if e == null or e.kind != "unit" or int(e.owner) != fid:
			continue
		if bool(e.get("wounded", false)):
			wounded += 1
		else:
			mobile.append(e)
	var ph := String(g.phase)
	if ph == "secure":
		var late := []
		for e in mobile:
			if (e.pos as Vector2).distance_to(cen) > _doc("exfil_radius"):
				late.append(e)
		issue(w, g, late, "move", cen)
		var waited := w.tick - int(g.phase_tick)
		var gathered := late.is_empty() and (wounded == 0 or waited >= int(_doc("evac_wait")))
		if gathered or waited >= int(_doc("secure_ticks")) + int(_doc("evac_wait")):
			m.goal = m.safe
			issue(w, g, ctl + mobile, "move", m.safe)
			set_phase(w, g, "extract", "Extracting %d units to (%d, %d)." % [mobile.size(), int(m.safe.x), int(m.safe.y)], 0.6)
		return
	if ph == "extract":
		var sr := _doc("safe_radius")
		var home := _inside(mobile, m.safe, sr) == mobile.size() and (ms.is_empty() or _inside(ms, m.safe, sr) * 2 >= ms.size())
		if home:
			_doc_end(w, g, "success", "Exfil complete: %d units extracted to (%d, %d)." % [mobile.size(), int(m.safe.x), int(m.safe.y)], mobile.size())
			return
		var late := []
		for e in ctl + mobile:
			if not e.moving and String(e.order.type) == "idle" and (e.pos as Vector2).distance_to(m.safe) > sr:
				late.append(e)
		issue(w, g, late, "move", m.safe)


static func _eval_doc(w: SimWorld, g: Dictionary, ctl: Array, ms: Array, cen: Vector2) -> void:
	var m: Dictionary = g.mission
	var ty := String(m.type)
	var ph := String(g.phase)
	var fid := int(g.owner)
	var t: Vector2 = m.target
	var r := float(m.radius)
	if ph != "return" and w.tick - int(m.get("t0", w.tick)) > int(_doc("mission_timeout")):
		_doc_return(w, g, ctl, "failed", "%s timed out; returning." % ty.capitalize().replace("_", " "))
		return
	if ph == "assess":
		m.goal = t
		var stealth := ty == "recon" or ty == "sabotage" or ty == "officer_hunt"
		issue(w, g, ctl, "move" if stealth else "attack_move", t)
		set_phase(w, g, "move", "%s: moving to (%d, %d)%s." % [ty.capitalize().replace("_", " "), int(t.x), int(t.y),
			" avoiding contact" if stealth else ""], 0.1)
		return
	if ph == "move":
		if ty == "officer_hunt" and _hunt_target(w, g, ctl):
			set_phase(w, g, "strike", "Officer in sight; engaging.", 0.5)
			return
		if ms.is_empty() or _inside(ms, m.goal, r) * 2 >= ms.size():
			var nxt := {"recon": "observe", "raid": "strike", "sabotage": "strike", "officer_hunt": "strike", "exfil": "secure"}
			set_phase(w, g, String(nxt[ty]), "On the objective at (%d, %d)." % [int(t.x), int(t.y)], 0.4)
			return
		var late := []
		for e in ctl:
			if not e.moving and String(e.order.type) == "idle" and (e.pos as Vector2).distance_to(m.goal) > r:
				late.append(e)
		issue(w, g, late, "move" if ty != "raid" and ty != "exfil" else "attack_move", m.goal)
		return
	if ph == "return":
		if ms.is_empty() or _inside(ms, m.safe, _doc("safe_radius")) * 2 >= ms.size():
			_doc_end(w, g, String(g.result) if String(g.result) != "" else "success", "%s complete (%s); back at (%d, %d)." % [
				ty.capitalize().replace("_", " "), String(g.result) if String(g.result) != "" else "success", int(m.safe.x), int(m.safe.y)])
		return
	match ty:
		"recon":
			m.seen = maxi(int(m.seen), _enemies_near(w, fid, t, r * 2.0).size())
			if w.tick - int(g.phase_tick) >= int(_doc("observe_ticks")):
				_doc_return(w, g, ctl, "success", "Recon done: %d enemies observed near (%d, %d)." % [int(m.seen), int(t.x), int(t.y)])
		"raid":
			var prey := []
			for e in _enemies_near(w, fid, t, r * 2.0):
				var ud := Content.unit(String(e.def))
				if e.kind == "unit" and (bool(ud.get("can_gather", false)) or bool(ud.get("is_supply", false))):
					prey.append(e)
			if not prey.is_empty():
				_hunt(w, g, ctl, prey)
			if w.tick - int(g.phase_tick) >= int(_doc("raid_ticks")):
				_doc_return(w, g, ctl, "success", "Raid done near (%d, %d); breaking contact." % [int(t.x), int(t.y)])
		"sabotage":
			var b = w.entities.get(int(m.target_id))
			if b == null:
				_doc_return(w, g, ctl, "success", "Target destroyed; exfiltrating.")
			else:
				var ids := []
				for e in ctl:
					if int(e.order.get("target_id", -1)) != int(b.id):
						ids.append(int(e.id))
				if not ids.is_empty():
					_attack(w, g, ids, int(b.id))
		"officer_hunt":
			var o = w.entities.get(int(m.target_id))
			if o == null:
				_doc_return(w, g, ctl, "success", "Target officer down; exfiltrating.")
			elif not _hunt_target(w, g, ctl) and w.tick - int(g.phase_tick) > int(_doc("observe_ticks")) * 2:
				_doc_return(w, g, ctl, "failed", "Lost the officer; returning.")
		"exfil":
			_eval_exfil(w, g, ctl, ms, cen)
