extends RefCounted
## G7 (CNOPS7): counter-nanite operation support, master scope 6.9 (support bullets). Owner: CNOPS7.
##  - Overwatch drone (one per strike team, def rules.overwatch.defs[faction]: the recon drone a_drone_recon /
##    b_drone_recon with overwatch hp, tagged e.cn_ow = team id): launched from the facility drone bay
##    (or at the team when the side has no facility), parks in the bay while the team is in its garage, otherwise
##    circles the convoy (or the deployment site). Every overwatch.every ticks it shares what it sees: the team's
##    sighting table (used by fire support) + Intel.note_contact(src "overwatch") for the side. Knowledge API:
##    SENSE7's senses7.gd has no push call, so sharing goes through intel.gd; Senses7.hidden() is respected.
##    New threats inside warn_r of the team -> CnOverwatchWarning. Flyable with the existing drone piloting
##    (def pilot.kind recon): while DronePilot flies it, this system does not move it. Lost -> relaunch after relaunch_s.
##  - Fire support on call (cn_fire_support {issuer, team_id, kind artillery|rockets|air, target_id | pos}): the
##    team leader (alive) calls a strike from base on a target the team can see (a member / APC sees it, or the
##    overwatch drone shared it within share_ttl_s). Shots go through Strikes (StrikeLaunched / StrikeImpact,
##    CIWS interception). calls_per_mission per team, refilled when the team rolls out again (CnTeamOut).
##  - Relief convoy (cn_relief {issuer, team_id, kind operators|reload}): from the side's facility gate, either a
##    fresh tactical operator squad (CounterNanite.spawn_team, tactical cap applies) or a reload APC that restocks
##    the team's APCs (Apc7.restock) on arrival. Cost + per-side cooldown. CnReliefSent / CnReliefArrived / CnReliefLost.
## Content: content/g7/defs_g7_cnops.json rules.g7_cnops (PROVISIONAL).
## State: w.sys_state.cnops7 (string keys), created only once CNSIM7's cn7 state has a team. Saved and hashed.
## Determinism: sorted ids, staggered cadence, w.rng only for strike scatter (fixed draw order), snapped floats.

const Senses7 = preload("res://sim/systems/senses7.gd")
const CnProgress7 = preload("res://sim/systems/cn_progress7.gd")
const VER := 1
const KEY := "cnops7"


static func R() -> Dictionary:
	return Content.rules().get("g7_cnops", {})


static func OW() -> Dictionary:
	return R().get("overwatch", {})


static func ticks(sec: float) -> int:
	return maxi(roundi(sec * SimWorld.TICK_RATE), 1)


static func state(w: SimWorld):
	return w.sys_state.get(KEY)


static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		st = {"ver": VER, "drones": {}, "seen": {}, "warned": {}, "calls": {}, "relief": {}, "next_relief": 1, "relief_cd": {}}
		w.sys_state[KEY] = st
	return st


static func _sv(v: Vector2) -> Vector2:
	return Vector2(snappedf(v.x, 0.001), snappedf(v.y, 0.001))


static func _cn(w: SimWorld, tid: int):
	return SimWorld.CounterNanite.team(w, tid)


## Facility team record (CNFAC7) whose ext is CN team tid, or {}.
static func fac_team(w: SimWorld, tid: int) -> Dictionary:
	var fs = w.sys_state.get("cn_facility")
	if fs == null:
		return {}
	var ks: Array = (fs.get("teams", {}) as Dictionary).keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		if int(fs.teams[k].get("ext", 0)) == tid:
			return fs.teams[k]
	return {}


## Where the team is: the first live APC on the map, else a member on the map; null when all are gone or carried.
static func anchor(w: SimWorld, t: Dictionary):
	for id in t.apcs:
		var a = w.entities.get(int(id))
		if a != null:
			return Vector2(a.pos)
	for id in t.members:
		var e = w.entities.get(int(id))
		if e != null:
			return Vector2(e.pos)
	return null


static func _clamp_map(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 0.5, float(w.map.w) - 0.5), clampf(p.y, 0.5, float(w.map.h) - 0.5))


# ================================================================ overwatch drone
static func drone_of(w: SimWorld, tid: int) -> int:
	var st = state(w)
	if st == null:
		return -1
	var d = (st.drones as Dictionary).get(str(tid))
	return -1 if d == null else int(d.id)


static func _bay(w: SimWorld, tid: int):
	var T := fac_team(w, tid)
	if T.is_empty():
		return null
	var z: Dictionary = SimWorld.CnFacility.zones(w, int(T.fac))
	if z.has("drone_bay"):
		return (z.drone_bay as Rect2).get_center()
	return null


static func _launch(w: SimWorld, st: Dictionary, t: Dictionary) -> void:
	var fdef := String(w.factions[int(t.fid)].get("faction_def", "human_a"))
	var def_id := String((OW().get("defs", {}) as Dictionary).get(fdef, "a_drone_recon"))
	if Content.unit(def_id).is_empty():
		def_id = "a_drone_recon"
	var at = _bay(w, int(t.id))
	if at == null:
		at = anchor(w, t)
	if at == null:
		return
	var id := w.spawn_unit(def_id, int(t.fid), _sv(at))
	var e: Dictionary = w.entities[id]
	e.cn_ow = int(t.id)
	e.order = {"type": "hold"}
	if OW().has("hp"):
		e.hp = float(OW().hp)
		e.max_hp = float(OW().hp)
	st.drones[str(int(t.id))] = {"id": id, "ang": 0.0, "relaunch": -1}
	w.emit("CnOverwatchLaunched", {"team": int(t.id), "owner": int(t.fid), "id": id, "pos": e.pos})


## Orbit centre: the deployment site while deploying, else the team; the bay while the team is garaged.
static func _orbit_centre(w: SimWorld, t: Dictionary):
	var T := fac_team(w, int(t.id))
	if not T.is_empty() and String(T.get("phase", "")) == "garage":
		return null
	if t.get("dep") != null and (t.dep as Dictionary).has("site"):
		return Vector2(t.dep.site)
	return anchor(w, t)


static func _fly_drone(w: SimWorld, d: Dictionary, e: Dictionary, t: Dictionary) -> void:
	if SimWorld.DronePilot.is_piloted(w, int(e.id)):
		return
	var spd := float(OW().get("speed", 6.0)) / float(SimWorld.TICK_RATE)
	var c = _orbit_centre(w, t)
	var goal: Vector2
	if c == null:
		var b = _bay(w, int(t.id))
		goal = Vector2(e.pos) if b == null else Vector2(b)
	else:
		var r := float(OW().get("orbit_r", 6.0))
		d.ang = wrapf(snappedf(float(d.ang) + spd / r, 0.0001), 0.0, TAU)
		goal = Vector2(c) + Vector2(cos(float(d.ang)), sin(float(d.ang))) * r
	goal = _clamp_map(w, goal)
	var pos: Vector2 = e.pos
	var dist := pos.distance_to(goal)
	if dist < 0.001:
		return
	var stp := spd * 1.5
	var np := goal if dist <= stp else pos + (goal - pos) / dist * stp
	SimWorld.HotState.set_pos(w, int(e.id), _sv(np))
	e.facing = snappedf((goal - pos).angle(), 0.001)


## One sighting pass: shares what the drone sees and warns of new threats near the team.
static func _spot(w: SimWorld, st: Dictionary, t: Dictionary, e: Dictionary) -> void:
	var fid := int(t.fid)
	var tk := str(int(t.id))
	var sight := float(OW().get("sight", Content.unit(String(e.def)).get("sight", 14)))
	var seen: Dictionary = st.seen.get(tk, {})
	var warned: Dictionary = st.warned.get(tk, {})
	st.seen[tk] = seen
	st.warned[tk] = warned
	var ttl := ticks(float(OW().get("share_ttl_s", 30)))
	for k in seen.keys():
		if w.tick - int(seen[k]) > ttl:
			seen.erase(k)
	var c = anchor(w, t)
	var wr := float(OW().get("warn_r", 18.0))
	var cd := ticks(float(OW().get("warn_cd_s", 20)))
	var found := []
	for u in SimWorld.G4bMech.near_units(w, Vector2(e.pos), sight):
		if not w.is_enemy(fid, int(u.owner)) or String(u.get("kind", "unit")) != "unit":
			continue
		if Senses7.hidden(w, fid, u):
			continue
		found.append(u)
	found.sort_custom(func(a, b): return int(a.id) < int(b.id))
	for u in found:
		var uid := int(u.id)
		seen[str(uid)] = w.tick
		SimWorld.Intel.note_contact(w, fid, Vector2(u.pos), String(u.def), float(OW().get("strength", 1.0)), "recon", uid)
		if c == null:
			continue
		var dist := Vector2(c).distance_to(Vector2(u.pos))
		if dist <= wr and w.tick - int(warned.get(str(uid), -1000000)) > cd:
			warned[str(uid)] = w.tick
			w.emit("CnOverwatchWarning", {"team": int(t.id), "owner": fid, "drone": int(e.id), "target": uid,
				"def": String(u.def), "pos": _sv(Vector2(u.pos)), "dist": snappedf(dist, 0.01),
				"bearing": snappedf((Vector2(u.pos) - Vector2(c)).angle(), 0.01)})
	for k in warned.keys():
		if w.tick - int(warned[k]) > cd * 4:
			warned.erase(k)


static func _tick_overwatch(w: SimWorld, st: Dictionary, t: Dictionary) -> void:
	var tk := str(int(t.id))
	var d = (st.drones as Dictionary).get(tk)
	if d == null:
		if String(t.kind) == "strike" and not bool(t.get("dead", false)):
			_launch(w, st, t)
		return
	var e = w.entities.get(int(d.id))
	if e == null:
		if int(d.relaunch) < 0:
			d.relaunch = w.tick + ticks(float(OW().get("relaunch_s", 60)))
			w.emit("CnOverwatchLost", {"team": int(t.id), "owner": int(t.fid), "id": int(d.id)})
		elif w.tick >= int(d.relaunch) and not bool(t.get("dead", false)):
			st.drones.erase(tk)
		return
	_fly_drone(w, d, e, t)
	if (w.tick + int(t.id)) % int(OW().get("every", 10)) == 0:
		_spot(w, st, t, e)


## True when team t can see entity x: a live member / APC on the map sees it (Senses7 when on, else sight range
## + eagle_eye), or the overwatch drone shared it within share_ttl_s.
static func team_sees(w: SimWorld, t: Dictionary, x: Dictionary) -> bool:
	var st = state(w)
	if st != null:
		var seen: Dictionary = (st.seen as Dictionary).get(str(int(t.id)), {})
		if seen.has(str(int(x.id))) and w.tick - int(seen[str(int(x.id))]) <= ticks(float(OW().get("share_ttl_s", 30))):
			return true
	var son := Senses7.enabled(w)
	for id in (t.members as Array) + (t.apcs as Array):
		var m = w.entities.get(int(id))
		if m == null:
			continue
		var sr := float(Content.unit(String(m.def)).get("sight", 8)) + CnProgress7.skill_mult(w, int(id), "sight_add")
		if Vector2(m.pos).distance_to(Vector2(x.pos)) > sr:
			continue
		if not son or Senses7.can_see(w, m, x) or Senses7.knows(w, m, int(x.id)):
			return true
	return false


# ================================================================ fire support on call
static func FS() -> Dictionary:
	return R().get("fire_support", {})


static func calls_left(w: SimWorld, tid: int) -> int:
	var st = state(w)
	var c = null if st == null else (st.calls as Dictionary).get(str(tid))
	return int(FS().get("calls_per_mission", 3)) if c == null else int(c.left)


## The first live enemy unit the team can see within pos_snap of p (ascending id), or null.
static func _seen_near(w: SimWorld, t: Dictionary, p: Vector2):
	var best = null
	for u in SimWorld.G4bMech.near_units(w, p, float(FS().get("pos_snap", 2.5))):
		if w.is_enemy(int(t.fid), int(u.owner)) and String(u.get("kind", "unit")) == "unit" and team_sees(w, t, u):
			if best == null or int(u.id) < int(best.id):
				best = u
	return best


static func fire_reason(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	var t = _cn(w, int(cmd.get("team_id", -1)))
	if t == null or int(t.fid) != fid or bool(t.get("dead", false)):
		return "No such team."
	if int(t.leader) < 0 or not SimWorld.CounterNanite.alive(w, int(t.leader)):
		return "The team leader must make the call."
	var K: Dictionary = (FS().get("kinds", {}) as Dictionary).get(String(cmd.get("kind", "")), {})
	if K.is_empty():
		return "Unknown fire support."
	if calls_left(w, int(t.id)) <= 0:
		return "No fire-support calls left this mission."
	var st = state(w)
	var c = null if st == null else (st.calls as Dictionary).get(str(int(t.id)))
	if c != null and w.tick < int(c.get("ready", 0)):
		return "Fire support is still busy."
	if cmd.has("target_id"):
		var x = w.entities.get(int(cmd.target_id))
		if x == null or not w.is_enemy(fid, int(x.owner)):
			return "No target."
		if not team_sees(w, t, x):
			return "The team can't see that target."
		return ""
	if not cmd.has("pos"):
		return "No target."
	if _seen_near(w, t, Vector2(cmd.pos)) == null:
		return "The team can't see a target there."
	return ""


static func _caller(w: SimWorld, t: Dictionary):
	var l = w.entities.get(int(t.leader))
	if l != null:
		return l
	for id in t.apcs:
		var a = w.entities.get(int(id))
		if a != null:
			return a
	return null


static func _fire(w: SimWorld, cmd: Dictionary) -> void:
	var t: Dictionary = _cn(w, int(cmd.team_id))
	var kind := String(cmd.kind)
	var K: Dictionary = FS().kinds[kind]
	var src = _caller(w, t)
	if src == null:
		return
	var at: Vector2
	var tgt := -1
	if cmd.has("target_id"):
		tgt = int(cmd.target_id)
		at = Vector2(w.entities[tgt].pos)
	else:
		at = Vector2(cmd.pos)
	at = _sv(at)
	var st := _st(w)
	var tk := str(int(t.id))
	var c = (st.calls as Dictionary).get(tk)
	if c == null:
		c = {"left": int(FS().get("calls_per_mission", 3)), "ready": 0, "used": 0}
		st.calls[tk] = c
	c.left = int(c.left) - 1
	c.used = int(c.get("used", 0)) + 1
	c.ready = w.tick + ticks(float(FS().get("cooldown_s", 15)))
	var flight := ticks(float(K.get("flight_s", 5.0)))
	var gap := int(K.get("gap_ticks", 2))
	var rad := float(K.get("scatter", 2.0))
	for i in int(K.get("shots", 4)):
		var ang := w.rng.randf() * TAU
		var r := sqrt(w.rng.randf()) * rad
		SimWorld.Strikes._launch_shot(w, src, _sv(at + Vector2(cos(ang), sin(ang)) * r), String(K.get("strike_kind", "shell")),
			flight + i * gap, String(K.weapon))
	var lead = SimWorld.CounterNanite.find(w, int(t.leader))
	w.emit("CnFireSupport", {"team": int(t.id), "owner": int(t.fid), "kind": kind, "target": tgt, "pos": at,
		"left": int(c.left), "eta": flight, "caller": int(t.leader), "call_sign": String(lead.get("call_sign", "")) if lead != null else ""})


# ================================================================ relief convoy
static func RL() -> Dictionary:
	return R().get("relief", {})


static func relief_reason(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	var t = _cn(w, int(cmd.get("team_id", -1)))
	if t == null or int(t.fid) != fid or bool(t.get("dead", false)):
		return "No such team."
	var kind := String(cmd.get("kind", ""))
	if kind != "operators" and kind != "reload":
		return "Unknown relief."
	if SimWorld.CnFacility.facilities(w, fid).is_empty():
		return "Needs a Counter-Nanite facility."
	var st = state(w)
	if st != null and w.tick < int((st.relief_cd as Dictionary).get(str(fid), 0)):
		return "The relief convoy is not ready yet."
	if kind == "operators":
		var why := SimWorld.CounterNanite.tac_reason(w, fid)
		if why != "":
			return why
	return w.can_afford(fid, RL().get("cost", {}))


static func _send_relief(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	var t: Dictionary = _cn(w, int(cmd.team_id))
	var kind := String(cmd.kind)
	var fac := int(SimWorld.CnFacility.facilities(w, fid)[0])
	var z: Dictionary = SimWorld.CnFacility.zones(w, fac)
	var gate: Vector2 = (z.gate as Rect2).get_center() if z.has("gate") else (z.compound as Rect2).get_center()
	if not z.has("gate") and z.has("gate_outer"):
		# REGFIX7-3: zones() has no "gate" key (a code alias of gate_outer), so the convoy started in the middle of the
		# compound and drove out by plain Movement; with the gates hardened (a threat near) the outer gate never opens for
		# an uncontrolled vehicle and it sat in the wash. It now starts outside the outer gate, where the gate controller
		# hands its own APCs over (the gate mouth on the gate axis).
		var G: Dictionary = SimWorld.FacDrive7.graph()
		gate = Vector2(SimWorld.CnFacility.origin(SimWorld.CnFacility.fac(w, fac))) + Vector2(G.pos[int(G.exit)]) + Vector2(0, 1.5)
	if not w.spend(fid, RL().get("cost", {}), "cn_relief"):
		return
	var units := []
	var nt := -1
	if kind == "operators":
		var res: Dictionary = SimWorld.CounterNanite.spawn_team(w, fid, "tactical_squad", _sv(gate))
		if res.is_empty():
			return
		nt = int(res.team)
		units = (res.apcs as Array).duplicate()
	else:
		var pre := SimWorld.CounterNanite.prefix(w, fid)
		var aid := w.spawn_unit(pre + "op_tactical_apc", fid, _sv(gate))
		var a: Dictionary = w.entities[aid]
		SimWorld.Apc7.init_apc(w, a)
		a.cn_relief = int(t.id)
		units = [aid]
	var st := _st(w)
	var n := int(st.next_relief)
	st.next_relief = n + 1
	st.relief[str(n)] = {"n": n, "fid": fid, "team": int(t.id), "kind": kind, "units": units, "new_team": nt,
		"t0": w.tick, "home": _sv(gate)}
	st.relief_cd[str(fid)] = w.tick + ticks(float(RL().get("cooldown_s", 90)))
	_relief_move(w, st.relief[str(n)], t)
	w.emit("CnReliefSent", {"relief": n, "team": int(t.id), "owner": fid, "kind": kind, "units": units.duplicate(),
		"new_team": nt, "from": _sv(gate)})


static func _relief_move(w: SimWorld, r: Dictionary, t: Dictionary) -> void:
	var g = anchor(w, t)
	if g == null:
		return
	if int(r.new_team) > 0:
		var nt = _cn(w, int(r.new_team))
		if nt != null:
			SimWorld.CounterNanite.move_team(w, nt, Vector2(g))
		return
	for id in r.units:
		var u = w.entities.get(int(id))
		if u != null:
			SimWorld.Movement.order_move(w, u, Vector2(g))


static func _tick_relief(w: SimWorld, st: Dictionary) -> void:
	var ks: Array = (st.relief as Dictionary).keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		var r: Dictionary = st.relief[k]
		var t = _cn(w, int(r.team))
		var live := []
		for id in r.units:
			var u = w.entities.get(int(id))
			if u != null:
				live.append(u)
		var g = null if t == null or bool(t.get("dead", false)) else anchor(w, t)
		if live.is_empty() or g == null or w.tick - int(r.t0) > ticks(float(RL().get("max_s", 300))):
			if live.is_empty() and SimWorld.Transport.in_cargo(w, int(r.units[0])):
				continue
			w.emit("CnReliefLost", {"relief": int(r.n), "team": int(r.team), "owner": int(r.fid), "kind": String(r.kind)})
			st.relief.erase(k)
			continue
		var arrived := false
		for u in live:
			if Vector2(u.pos).distance_to(Vector2(g)) <= float(RL().get("arrive_r", 4.5)):
				arrived = true
		if arrived:
			var restocked := []
			if String(r.kind) == "reload":
				for id in t.apcs:
					var a = w.entities.get(int(id))
					if a != null:
						SimWorld.Apc7.restock(w, a)
						restocked.append(int(id))
				for u in live:
					SimWorld.Movement.order_move(w, u, Vector2(r.home))
			w.emit("CnReliefArrived", {"relief": int(r.n), "team": int(r.team), "owner": int(r.fid), "kind": String(r.kind),
				"units": (r.units as Array).duplicate(), "new_team": int(r.new_team), "restocked": restocked})
			st.relief.erase(k)
		elif (w.tick - int(r.t0)) % int(RL().get("repath_every", 40)) == 0:
			_relief_move(w, r, t)


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	match String(cmd.get("type", "")):
		"cn_fire_support":
			return fire_reason(w, cmd)
		"cn_relief":
			return relief_reason(w, cmd)
	return "Unknown command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	match String(cmd.get("type", "")):
		"cn_fire_support":
			if fire_reason(w, cmd) == "":
				_fire(w, cmd)
		"cn_relief":
			if relief_reason(w, cmd) == "":
				_send_relief(w, cmd)


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var cn = w.sys_state.get("cn7")
	if cn == null:
		return
	if state(w) == null and (cn.teams as Dictionary).is_empty():
		return
	var st := _st(w)
	for ev in w.events:
		if String(ev.type) == "CnTeamOut":   # a new sortie refills the fire-support calls
			var T: Dictionary = SimWorld.CnFacility.team(w, int(ev.get("team", -1)))
			if not T.is_empty():
				st.calls.erase(str(int(T.get("ext", 0))))
	for tid in SimWorld.CounterNanite.team_ids(w):
		_tick_overwatch(w, st, cn.teams[tid])
	if w.tick % 10 == 0 and not (st.relief as Dictionary).is_empty():
		_tick_relief(w, st)

