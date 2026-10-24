extends RefCounted
## Officer mission state machine (owner: agent C2), split out of ops.gd. Must NOT preload ops.gd.
## Contract: docs/CONTRACTS_G2.md section 4. Evaluated every 10 ticks per group (staggered by gid).
##
## Area missions (secure_point, hold_zone, attack_area): assess -> move -> secure -> hold.
##   secure_point / hold_zone succeed when no visible enemy is within radius of the target and >= 50%
##   of members are inside the radius for SECURE_TICKS. attack_area holds once no visible enemy is
##   left within radius. hold_zone then sets the hold stance. Enemy contact in hold -> secure again.
## patrol_route: assess -> move, cycling target + points with attack_move.
## Any mission: mean ammo < rules.ops.resupply_ammo_frac -> resupply (nearest own built HQ/depot or
##   logistics truck) and back; losses > risk bound of starting strength -> withdraw to the nearest
##   own HQ/depot, result "failed", then idle.

const Movement = preload("res://sim/systems/movement.gd")
const Fog = preload("res://sim/systems/fog.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")  # G3b scale (PERF5): per-kind lists
const Subsets = preload("res://sim/systems/unit_subsets.gd")  # G3b scale (PERF5): per-def unit subsets

const HISTORY_MAX := 10
const REPORT_EVERY := 600        # 30 s without a phase change -> status report
const SECURE_TICKS := 100        # 5 s held with the area clear
const OFFICER_BACK := 2.0        # officer trails the centroid by this many tiles
const OFFICER_SLACK := 2.5
const RESUPPLY_DONE := 0.9
const RESUPPLY_TIMEOUT := 1200   # give up waiting for ammo after 60 s
const PATROL_ARRIVE := 3.0
const BASE_ARRIVE := 4.0


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
	if phase != "assess":
		var a := _ammo_frac(w, g)
		if a < float(_rules().get("resupply_ammo_frac", 0.3)):
			var src = _nearest_support(w, fid, cen, true)
			if src != null:
				m.goal = src.pos
				g.resume = phase
				issue(w, g, ctl, "move", src.pos)
				set_phase(w, g, "resupply", "Ammo at %d%%; falling back to resupply at the %s." % [_pct(a), String(src.def).replace("_", " ")], float(g.progress))
				return
	if String(m.type) == "patrol_route":
		_eval_patrol(w, g, ctl)
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
