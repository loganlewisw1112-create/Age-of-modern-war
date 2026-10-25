extends RefCounted
## Strikes (owner: MECH6b). CONTRACTS_G6 §4 (`strike`), §10. Runs after MachineG6 each tick (SYSTEM_ORDER).
## `strike` {issuer, unit_ids, cell, target_id?} for strike units; batteries (buildings) use
## {issuer, building_id, cell, target_id?} because world._common_validate keeps only unit ids in unit_ids.
## Striker kinds (kind_of):
##   loiter       unit def strike {kind:"loiter", munitions, munition_def, reload_s} (a_loiter_truck): each
##                strike launches one loitering munition (the G5 launched-drone entity, munition_def) within
##                strikes.loiter.launch_range; it flies to the cell, loiters loiter_s searching search_radius
##                (target_id first), then dives on a target (or the cell) and hits with its def payload.
##                e.munitions (6 per load); at 0 the truck reloads for reload_s (e.strike_ready), then refills.
##   mlrs         unit def strike {kind:"mlrs", rockets, reload_s} (a_mlrs): a salvo of `rockets` scattered
##                (w.rng: angle, radius per rocket) over strikes.mlrs.area_radius around the cell, salvo_gap
##                ticks apart; range = its weapon range / min_range; then reload_s.
##   mass_driver  building whose weapon is strikes.mass_driver.source_weapon (m_mass_driver): one slug at a
##                cell within that weapon's range / min_range; cooldown = the weapon cooldown; needs power.
##   cruise       building def strike {kind:"cruise", range:"global", cooldown_s, damage, splash}
##                (a_cruise_battery): global range, flight at strikes.cruise.speed, cooldown_s; needs power.
## Every shot (cruise, MLRS rocket, mass-driver "shell") is offered to the enemy Laser CIWS as it lands:
##   Counterdrone.intercept_strike (AIRDEF6) -> StrikeIntercepted instead of the impact. Loitering munitions are
##   entities: CIWS / nets / jam fields remove them (LoiterLost / LoiterJammed here).
## JTAC designation (MECH6c): flight times x Callins.strike_delay_mult, MLRS scatter / Callins.strike_acc_mult.
## Entity fields (strikers, saved): e.strike_ready (tick the striker can fire again), e.munitions (loiter).
## State (saved, hashed; created on the first strike only): w.sys_state.strikes = {ver, next, fired,
##   intercepted, shots: [{n, kind, owner, src, from, at, t, total, weapon}], loiter: {drone id: {owner, src,
##   goal, target, phase "fly"|"loiter"|"dive", t}}}.
## Events: StrikeLaunched, StrikeImpact, StrikeIntercepted, LoiterLost, LoiterJammed.
## Determinism: ascending ids / shot order, w.rng only for the MLRS scatter (fixed draw order), floats snapped.

const SimIndex = preload("res://sim/systems/sim_index.gd")
const HotState = preload("res://sim/hot_state.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Counterdrone = preload("res://sim/systems/counterdrone.gd")   # AIRDEF6: intercept_strike, jammed
const Callins = preload("res://sim/systems/callins.gd")             # MECH6c: JTAC designation multipliers

const VER := 1
const Q := 1.0 / 1024.0
const KINDS := ["loiter", "mlrs", "mass_driver", "cruise"]

static func R() -> Dictionary:
	return Content.rules().get("g6_machine", {}).get("strikes", {})


static func _ticks(s: float) -> int:
	return maxi(roundi(s * SimWorld.TICK_RATE), 1)


static func _snap(v: Vector2) -> Vector2:
	return Vector2(snappedf(v.x, Q), snappedf(v.y, Q))


static func _def(e: Dictionary) -> Dictionary:
	return Content.building(String(e.def)) if e.kind == "building" else Content.unit(String(e.def))


static func _powered(w: SimWorld, fid: int) -> bool:
	var f = w.factions.get(fid)
	return f != null and int(f.get("power_prod", 0)) >= int(f.get("power_use", 0))


static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get("strikes")
	if st == null:
		st = {"ver": VER, "next": 1, "fired": 0, "intercepted": 0, "shots": [], "loiter": {}}
		w.sys_state["strikes"] = st
	return st


## Weapon stats in the Damage.apply_hit shape (as G4bMech._wpn).
static func _wpn(id: String) -> Dictionary:
	var wd := Content.weapon(id)
	return {"weapon": id, "damage": float(wd.get("damage", 0)), "cls": String(wd.get("class", "")),
		"splash": float(wd.get("splash", 0))}


static func _cell(cmd: Dictionary):
	var c = cmd.get("cell")
	if c is Vector2i:
		return c
	if c is Vector2:
		return Vector2i(floori(c.x), floori(c.y))
	if c is Array and (c as Array).size() >= 2:
		return Vector2i(int(c[0]), int(c[1]))
	return null


# ================================================================ queries
## "loiter" | "mlrs" | "mass_driver" | "cruise" | "" for entity e.
static func kind_of(e: Dictionary) -> String:
	if e.kind != "unit" and e.kind != "building":
		return ""
	var d := _def(e)
	var k := String(d.get("strike", {}).get("kind", ""))
	if KINDS.has(k):
		return k
	if e.kind == "building" and d.has("weapon") \
			and String(d.weapon) == String(R().get("mass_driver", {}).get("source_weapon", "g6_mass_slug")):
		return "mass_driver"
	return ""


## Loitering munitions ready on a truck (lazy refill once its reload is over).
static func munitions_left(w: SimWorld, e: Dictionary) -> int:
	var mx := int(_def(e).get("strike", {}).get("munitions", 6))
	if not e.has("munitions"):
		return mx
	if int(e.munitions) <= 0 and w.tick >= int(e.get("strike_ready", 0)):
		return mx
	return int(e.munitions)


## Ticks until e can strike again (0 = ready).
static func cooldown_left(w: SimWorld, e: Dictionary) -> int:
	return maxi(int(e.get("strike_ready", 0)) - w.tick, 0)


## [min, max] strike range of e in tiles (max -1 = global).
static func range_of(e: Dictionary) -> Array:
	var d := _def(e)
	match kind_of(e):
		"loiter":
			return [0.0, float(R().get("loiter", {}).get("launch_range", 30.0))]
		"mlrs", "mass_driver":
			var wd := Content.weapon(String(d.get("weapon", "")))
			return [float(wd.get("min_range", 0.0)), float(wd.get("range", 20.0))]
		"cruise":
			return [0.0, -1.0]
	return [0.0, 0.0]


## "" when e can strike at world point p now, else the reason.
static func strike_error(w: SimWorld, e: Dictionary, p: Vector2) -> String:
	var k := kind_of(e)
	if k == "":
		return "Only strike units and batteries can strike."
	if e.kind == "building":
		if not bool(e.get("built", true)):
			return "The battery is not finished."
		if bool(_def(e).get("requires_power", false)) and not _powered(w, int(e.owner)):
			return "The battery needs power."
	if k == "loiter":
		if munitions_left(w, e) <= 0:
			return "No munitions left (reloading)."
	elif cooldown_left(w, e) > 0:
		return "Reloading (%d s)." % ceili(float(cooldown_left(w, e)) / SimWorld.TICK_RATE)
	var rg := range_of(e)
	var dist := Vector2(e.pos).distance_to(p)
	if float(rg[1]) >= 0.0 and dist > float(rg[1]):
		return "Target out of range."
	if dist < float(rg[0]):
		return "Target too close."
	return ""


# ================================================================ commands
static func _strikers(w: SimWorld, cmd: Dictionary) -> Array:
	var out := []
	if cmd.has("building_id"):
		var b = w.entities.get(int(cmd.building_id))
		if b != null:
			out.append(b)
	var ids: Array = (cmd.get("unit_ids", []) as Array).duplicate()
	ids.sort()
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null:
			out.append(e)
	return out


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if String(cmd.get("type", "")) != "strike":
		return "unknown_command"
	var c = _cell(cmd)
	if c == null or not w.in_bounds(c):
		return "Pick a target on the map."
	var fid := int(cmd.get("issuer", -1))
	var list := _strikers(w, cmd)
	if list.is_empty():
		return "Select strike units or a battery."
	var p := Vector2(c) + Vector2(0.5, 0.5)
	var first := ""
	for e in list:
		if int(e.owner) != fid:
			return "Select your own units."
		var err := strike_error(w, e, p)
		if err == "":
			return ""
		if first == "":
			first = err
	return first


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var c: Vector2i = _cell(cmd)
	var p := Vector2(c) + Vector2(0.5, 0.5)
	var tid := int(cmd.get("target_id", -1))
	for e in _strikers(w, cmd):
		if strike_error(w, e, p) != "":
			continue
		var dm := Callins.strike_delay_mult(w, int(e.owner), tid, p)   # JTAC designation (1.0 when none)
		match kind_of(e):
			"loiter":
				_launch_loiter(w, e, p, tid)
			"mlrs":
				_launch_mlrs(w, e, p, dm, Callins.strike_acc_mult(w, int(e.owner), tid, p))
			"mass_driver":
				_launch_shot(w, e, p, "shell", _ticks(float(R().get("mass_driver", {}).get("flight_s", 1.5)) * dm),
					String(R().get("mass_driver", {}).get("weapon", "g6_mass_slug_strike")))
				e.strike_ready = w.tick + _ticks(float(Content.weapon(String(_def(e).weapon)).get("cooldown", 14.0)))
			"cruise":
				var cr: Dictionary = R().get("cruise", {})
				var secs := maxf(float(cr.get("min_flight_s", 4.0)), Vector2(e.pos).distance_to(p) / maxf(float(cr.get("speed", 8.0)), 0.1))
				_launch_shot(w, e, p, "cruise", _ticks(secs * dm), String(cr.get("weapon", "g6_cruise_warhead")))
				e.strike_ready = w.tick + _ticks(float(_def(e).strike.get("cooldown_s", 180.0)))


static func _launch_shot(w: SimWorld, e: Dictionary, at: Vector2, kind: String, flight: int, weapon: String) -> void:
	var st := _st(w)
	var n := int(st.next)
	st.next = n + 1
	st.fired = int(st.fired) + 1
	(st.shots as Array).append({"n": n, "kind": kind, "owner": int(e.owner), "src": int(e.id), "from": _snap(Vector2(e.pos)),
		"at": _snap(at), "t": flight, "total": flight, "weapon": weapon})
	w.emit("StrikeLaunched", {"kind": kind, "src": int(e.id), "owner": int(e.owner), "pos": _snap(at), "n": n, "eta": flight})


## dm / am: designation delay and accuracy multipliers (Callins); accuracy shrinks the scatter radius.
static func _launch_mlrs(w: SimWorld, e: Dictionary, p: Vector2, dm: float = 1.0, am: float = 1.0) -> void:
	var mr: Dictionary = R().get("mlrs", {})
	var n := int(_def(e).strike.get("rockets", 12))
	var rad := float(mr.get("area_radius", 3.0)) / maxf(am, 0.1)
	var gap := int(mr.get("salvo_gap_ticks", 2))
	var flight := _ticks(float(mr.get("flight_s", 3.0)) * dm)
	var wpn := String(mr.get("weapon", "g6_mlrs_salvo_rocket"))
	for i in n:
		var ang := w.rng.randf() * TAU
		var r := sqrt(w.rng.randf()) * rad
		_launch_shot(w, e, p + Vector2(cos(ang), sin(ang)) * r, "rocket", flight + i * gap, wpn)
	e.strike_ready = w.tick + _ticks(float(_def(e).strike.get("reload_s", 30.0)))


static func _launch_loiter(w: SimWorld, e: Dictionary, p: Vector2, tid: int) -> void:
	var sd: Dictionary = _def(e).strike
	var left := munitions_left(w, e) - 1
	e.munitions = left
	if left <= 0:
		e.strike_ready = w.tick + _ticks(float(sd.get("reload_s", 60.0)))
	var mdef := String(sd.get("munition_def", "a_drone_strike"))
	var did := w.spawn_unit(mdef, int(e.owner), Vector2(e.pos))
	var dr: Dictionary = w.entities[did]
	dr.facing = snappedf(Vector2(e.pos).angle_to_point(p), Q)
	HotState.touch(w, did)
	var st := _st(w)
	st.fired = int(st.fired) + 1
	st.loiter[did] = {"owner": int(e.owner), "src": int(e.id), "goal": _snap(p), "target": tid, "phase": "fly", "t": 0}
	w.emit("StrikeLaunched", {"kind": "loiter", "src": int(e.id), "owner": int(e.owner), "pos": _snap(p), "n": did,
		"munitions": left})


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("strikes")
	if st == null:
		return
	if not (st.loiter as Dictionary).is_empty():
		_loiter_step(w, st)
	if not (st.shots as Array).is_empty():
		_shots_step(w, st)


## Removes a munition entity without a wreck or a loss stat (impact, jamming), as G5 drones do.
static func _remove(w: SimWorld, e: Dictionary, cause: String) -> void:
	w.entities.erase(int(e.id))
	w.emit("EntityDestroyed", {"id": int(e.id), "kind": "unit", "def": e.def, "owner": e.owner, "pos": e.pos,
		"cause": cause, "killer_owner": SimWorld.NEUTRAL, "squad": -1})


## Moves e toward goal by stp (HotState write); true on arrival.
static func _fly(w: SimWorld, e: Dictionary, goal: Vector2, stp: float) -> bool:
	var pos: Vector2 = e.pos
	var dist := pos.distance_to(goal)
	if dist <= maxf(stp, 0.05):
		HotState.set_pos(w, int(e.id), goal)
		return true
	HotState.set_pos(w, int(e.id), _snap(pos + (goal - pos) / dist * stp))
	return false


static func _loiter_step(w: SimWorld, st: Dictionary) -> void:
	var lr: Dictionary = R().get("loiter", {})
	var lo: Dictionary = st.loiter
	var ids: Array = lo.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = lo[id]
		var e = w.entities.get(int(id))
		if e == null:
			lo.erase(id)
			w.emit("LoiterLost", {"id": int(id), "owner": int(r.owner), "src": int(r.src)})
			continue
		if Counterdrone.jammed(w, Vector2(e.pos), int(r.owner)):
			lo.erase(id)
			_remove(w, e, "jammed")
			w.emit("LoiterJammed", {"id": int(id), "owner": int(r.owner), "pos": e.pos})
			continue
		var stp := float(Content.unit(String(e.def)).get("speed", 9.0)) / SimWorld.TICK_RATE
		match String(r.phase):
			"fly":
				if _fly(w, e, Vector2(r.goal), stp):
					r.phase = "loiter"
					r.t = _ticks(float(lr.get("loiter_s", 20.0)))
			"loiter":
				r.t = int(r.t) - 1
				if (w.tick + int(id)) % maxi(int(lr.get("search_every_ticks", 5)), 1) == 0 or int(r.t) <= 0:
					var tgt := _pick_target(w, int(r.owner), Vector2(r.goal), float(lr.get("search_radius", 6.0)), int(r.target))
					if tgt >= 0 or int(r.t) <= 0:
						r.phase = "dive"
						r.target = tgt
			"dive":
				var t = w.entities.get(int(r.target)) if int(r.target) >= 0 else null
				if t != null:
					r.goal = _snap(Vector2(t.pos))
				if _fly(w, e, Vector2(r.goal), stp * float(lr.get("dive_speed_mult", 1.5))):
					var pl := String(Content.unit(String(e.def)).get("payload", "g5_drone_strike"))
					var hits := _impact(w, int(r.owner), int(r.src), Vector2(r.goal), _wpn(pl))
					lo.erase(id)
					_remove(w, e, "impact")
					w.emit("StrikeImpact", {"kind": "loiter", "src": int(r.src), "owner": int(r.owner), "pos": Vector2(r.goal),
						"hits": hits, "target": int(r.target)})


## Loiter target: target_id when it is an enemy within radius of p, else the nearest enemy ground unit or
## building within radius (ties: lower id). -1 when none.
static func _pick_target(w: SimWorld, fid: int, p: Vector2, radius: float, pref: int) -> int:
	var t = w.entities.get(pref) if pref >= 0 else null
	if t != null and (t.kind == "unit" or t.kind == "building") and w.is_enemy(fid, int(t.owner)) \
			and Vector2(t.pos).distance_to(p) <= radius:
		return pref
	var best := -1
	var bd := radius * radius + 0.0001
	for c in _ground_targets(w, fid, p, radius):
		var d2 := p.distance_squared_to(Vector2(c.pos))
		if d2 < bd:
			bd = d2
			best = int(c.id)
	return best


## Enemy ground units (every tier) and buildings of fid within radius of p, ascending id.
static func _ground_targets(w: SimWorld, fid: int, p: Vector2, radius: float) -> Array:
	var out := []
	var r2 := radius * radius
	var byo: Dictionary = SimIndex.units_by_owner(w)
	var owners: Array = byo.keys()
	owners.sort()
	for o in owners:
		if not w.is_enemy(fid, int(o)):
			continue
		for u in byo[o]:
			if w.entities.has(int(u.id)) and not bool(Content.unit(String(u.def)).get("is_air", false)) \
					and p.distance_squared_to(Vector2(u.pos)) <= r2:
				out.append(u)
	for b in SimIndex.of(w, "building"):
		if w.entities.has(int(b.id)) and w.is_enemy(fid, int(b.owner)) and p.distance_squared_to(Vector2(b.pos)) <= r2:
			out.append(b)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


## Splash hit at `at` (full damage at the centre, 50% at the edge; buildings by footprint distance).
static func _impact(w: SimWorld, fid: int, src: int, at: Vector2, s: Dictionary) -> int:
	var rad := maxf(float(s.splash), 0.05)
	var se = w.entities.get(src)
	var shooter: Dictionary = se if se != null else {"id": src, "owner": fid, "pos": at, "kind": "unit", "def": ""}
	var list := []
	for t in _ground_targets(w, fid, at, rad + 2.5):
		var d := at.distance_to(Vector2(t.pos))
		if t.kind == "building":
			var o: Vector2i = t.cell
			var sz := float(t.size)
			d = at.distance_to(Vector2(clampf(at.x, float(o.x), float(o.x) + sz), clampf(at.y, float(o.y), float(o.y) + sz)))
		elif d > rad + 0.3:
			continue
		if d <= rad + (0.3 if t.kind == "unit" else 0.0):
			list.append([t, d])
	for it in list:
		var t: Dictionary = it[0]
		if not w.entities.has(int(t.id)):
			continue
		var s2 := s.duplicate()
		s2.damage = float(s.damage) * (1.0 - 0.5 * clampf(float(it[1]) / rad, 0.0, 1.0))
		Damage.apply_hit(w, shooter, t, s2, true)
	return list.size()


static func _shots_step(w: SimWorld, st: Dictionary) -> void:
	var keep := []
	for s in st.shots:
		s.t = int(s.t) - 1
		if int(s.t) > 0:
			keep.append(s)
			continue
		var kind := String(s.kind)
		var at: Vector2 = s.at
		if _intercepted(w, at, int(s.owner), kind):
			st.intercepted = int(st.intercepted) + 1
			w.emit("StrikeIntercepted", {"kind": kind, "owner": int(s.owner), "src": int(s.src), "pos": at, "n": int(s.n)})
			continue
		var hits := _impact(w, int(s.owner), int(s.src), at, _wpn(String(s.weapon)))
		w.emit("StrikeImpact", {"kind": kind, "src": int(s.src), "owner": int(s.owner), "pos": at, "hits": hits, "n": int(s.n)})
	st.shots = keep


# ================================================================ CIWS interception
## True when an enemy Laser CIWS shoots down fid's projectile of `kind` ("cruise" | "rocket" | "shell") as it
## lands at `at`: AIRDEF6's Counterdrone.intercept_strike (it owns the CIWS radius, power and rate limit, and
## emits CiwsIntercept).
static func _intercepted(w: SimWorld, at: Vector2, fid: int, kind: String) -> bool:
	return Counterdrone.intercept_strike(w, fid, at, kind)
