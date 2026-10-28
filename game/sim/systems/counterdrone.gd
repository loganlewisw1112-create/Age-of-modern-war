extends RefCounted
## Counterdrone (owner: AIRDEF6). CONTRACTS_G6 §12: Laser CIWS, net capture, jamming fields, anti-drone bonus.
## Numbers: per-def flags (CONTENT6 defs) + rules.g6_airdef.counter_drone (content/g6/rules_airdef.json).
## "Drone" = an air unit whose def matches counter_drone.drone_flags / drone_roles / drone_aircraft (G5 launched
## drones and MECH6b loitering munitions [launched_drone], m_micro_drone [aircraft micro], m_mimic_drone).
## Def flags read:
##   ciws {radius, shots_per_min}  (a_laser_ciws) once every 60/shots_per_min s: destroys the nearest enemy drone in
##       radius (CiwsKill), or intercepts one enemy rocket / shell / strike landing in radius (shot_blocked for
##       combat's indirect fire, intercept_strike for MECH6b strikes incl. the cruise strike) -> CiwsIntercept.
##       Must be built, powered and not EMP-disabled (Airdef.source_active). Its own weapon still fires via Combat.
##   net_capture {salvage} (b_net_post; its weapon range = capture range, weapon cooldown = interval): captures the
##       nearest enemy drone in range intact (removed, no wreck, no kill) and the owner gains salvage (DroneCaptured).
##   jammer {radius} (m_jammer_obelisk, b_jammer_team): enemy drones inside drop (launched drones in G5Mech's drone
##       step with DroneJammed; other drone units here), and enemy guided shots aimed into the field drop
##       (shot_blocked -> GuidedJammed). jammed(w, pos, fid) is the query.
##   weapon anti_drone_mult (g6_scrap_shotgun 2.0): an anti_drone weapon deals x mult to drones (damage_mult).
## G6Hooks delegates (ORCH wires): damage_mult -> damage_mult, shot hook -> shot_blocked, mask bit -> active.
## G7 TURRET7C (13.9c-30): the CIWS head traverses (traverse7 mount, a_laser_ciws 120 deg/s) before anything is intercepted.
##   Drones: the head tracks the nearest enemy drone from track_mult x radius out (radar cue) and the laser fires only
##   once the head is laid on it inside the radius. Strikes / shells / rockets (decided in one call by the shot hook):
##   accepted when the head can lay onto the landing point within window_s from where it points now; the head then
##   swings onto it (pending lay, advanced every tick) and CiwsIntercept carries lay_ticks (the beam is drawn that late);
##   a threat the head cannot lay onto in time gets through, the head starts swinging toward it and the CIWS stays ready.
##   Numbers PROVISIONAL: content/g7/rules_g7_traverse.json _traverse7.ciws {track_mult, window_s}.
## State w.sys_state.counterdrone {ready: {bid: tick}, lay: {bid: [x, y, until tick]} (created on first use), ver}:
## first tick each CIWS / net post may act again; the point a CIWS head is still swinging onto.
## Created on first use (G5 matches never get it); saved and hashed.
## Determinism: ascending ids, integer ticks, no rng. Never preload g6_hooks.gd, Damage, G5Mech or Movement here:
## g6_hooks preloads this file (cycle). Damage is loaded lazily for non-launched drone kills.

const Airdef = preload("res://sim/systems/airdef.gd")
const Traverse7 = preload("res://sim/systems/traverse7.gd")   # G7 TURRET7C (13.9c-30): a CIWS head lays onto a threat before it intercepts

const VER := 1
const C7_PATH := "res://sim/systems/ciws7.gd"   # G7 CIWS7 (13.9c-32): roof rotary CIWS mounts (def.ciws7), lazy (no preload cycle)

static var _damage = null
static var _c7 = null


## G7 CIWS7: the Ciws7 script (lazy), or null while missing.
static func _ciws7():
	if _c7 == null and ResourceLoader.exists(C7_PATH):
		_c7 = load(C7_PATH)
	return _c7


## G7 CIWS7: true when building b is a rotary CIWS mount (def.ciws7): Ciws7 drives its fire, ammo and drum.
static func _is_c7(b: Dictionary) -> bool:
	return Content.building(String(b.def)).has("ciws7") and _ciws7() != null


static func tick(w: SimWorld) -> void:
	var sub := Airdef.sub_state(w)
	if (sub.ciws as Array).is_empty() and (sub.net as Array).is_empty() and (sub.jam as Array).is_empty():
		return
	_advance_lays(w)
	if Airdef.sub_list(w, "drone").is_empty():
		return
	var drones: Array = Airdef.sub_list(w, "drone").duplicate()
	# 1. jamming: drone units in an enemy field drop (G5-tracked launched drones drop in G5Mech's step)
	if not Airdef.sub_list(w, "jam").is_empty():
		var g5 = w.sys_state.get("g5mech")
		var tracked: Dictionary = g5.drones if g5 != null else {}
		for id in drones:
			var d = w.entities.get(id)
			if d == null or tracked.has(id) or not Airdef._airborne(w, d):
				continue
			var j = jammer_at(w, Vector2(d.pos), int(d.owner))
			if j != null:
				w.emit("DroneJammed", {"id": int(id), "type": String(d.def), "owner": int(d.owner), "pos": d.pos, "jammer": int(j.id)})
				_down(w, d, j, "jammed")
	# 2. Laser CIWS: one drone kill per interval
	for bid in Airdef.sub_list(w, "ciws").duplicate():
		var b = w.entities.get(bid)
		if b == null or not Airdef.source_active(w, b) or not _ready(w, int(bid)):
			continue
		if _is_c7(b):
			continue   # G7 CIWS7: a rotary CIWS mount engages drones in Ciws7.tick (bursts from its drum), not here
		var c: Dictionary = Content.building(String(b.def)).get("ciws", {})
		var rad := float(c.get("radius", 6.0))
		var t = _nearest_drone(w, b, rad * _track_mult())   # G7 TURRET7C: tracked (head laying) before it is in laser range
		if t == null:
			continue
		var laid := Traverse7.lay(w, b, Vector2(t.pos), float(_ciws_interval(c)) / SimWorld.TICK_RATE, false, int(t.id))
		if not laid or Vector2(b.pos).distance_squared_to(Vector2(t.pos)) > rad * rad:
			continue   # still swinging onto it, or not yet in range: the laser holds fire
		_spend(w, int(bid), _ciws_interval(c))
		w.emit("CiwsKill", {"ciws": int(bid), "owner": int(b.owner), "id": int(t.id), "def": String(t.def), "pos": t.pos, "kind": "drone"})
		_down(w, t, b, "ciws")
	# 3. net posts: capture intact (+salvage)
	var cd := ccfg()
	for bid in Airdef.sub_list(w, "net").duplicate():
		var b = w.entities.get(bid)
		if b == null or not Airdef.source_active(w, b) or not _ready(w, int(bid)):
			continue
		var bd := Content.building(String(b.def))
		var wd := Content.weapon(String(bd.get("weapon", "")))
		var t = _nearest_drone(w, b, float(wd.get("range", 7.0)))
		if t == null:
			continue
		var cool := float(wd.get("cooldown", cd.get("net_default_cooldown_s", 2.5)))
		_spend(w, int(bid), maxi(roundi(cool * SimWorld.TICK_RATE), 1))
		var salvage := int(bd.get("net_capture", {}).get("salvage", 0))
		if salvage > 0:
			w.credit(int(b.owner), {"salvage": salvage}, "net_capture")
		w.emit("DroneCaptured", {"net": int(bid), "owner": int(b.owner), "id": int(t.id), "def": String(t.def),
			"from_owner": int(t.owner), "pos": t.pos, "salvage": salvage})
		_remove(w, t, "captured", SimWorld.NEUTRAL)


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return "not_implemented"


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	pass


## True when an enemy jamming field covers pos for fid's units.
static func jammed(w: SimWorld, pos: Vector2, fid: int) -> bool:
	return jammer_at(w, pos, fid) != null


## The first (lowest id) active enemy jammer of fid whose field covers pos, or null.
static func jammer_at(w: SimWorld, pos: Vector2, fid: int):
	for id in Airdef.sub_list(w, "jam"):
		var j: Dictionary = w.entities[id]
		if not w.is_enemy(fid, int(j.owner)) or not Airdef.source_active(w, j):
			continue
		var jd: Dictionary = Airdef._def(j).get("jammer", {})
		if Vector2(j.pos).distance_to(pos) <= float(jd.get("radius", 0.0)):
			return j
	return null


## True when any CIWS or jammer exists (the G6Hooks mask bit for shot_blocked).
static func active(w: SimWorld) -> bool:
	return not Airdef.sub_list(w, "ciws").is_empty() or not Airdef.sub_list(w, "jam").is_empty()


## Shot hook (combat, after the hit roll, before the shot resolves at `at`): true = the shot is lost.
## Guided shots aimed into an enemy jam field drop (GuidedJammed); indirect shells / rockets landing inside an
## enemy CIWS radius are shot down while that CIWS is ready (CiwsIntercept).
static func shot_blocked(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary, at: Vector2) -> bool:
	var cd := ccfg()
	var fid := int(src.owner)
	if bool(s.get("guided", false)) and bool(cd.get("jam_drops_guided", true)):
		var j = jammer_at(w, at, fid)
		if j != null:
			w.emit("GuidedJammed", {"shooter": int(src.id), "owner": fid, "target": int(t.get("id", -1)), "pos": at,
				"weapon": String(s.get("weapon", "")), "jammer": int(j.id)})
			return true
	if bool(s.get("indirect", false)) and (cd.get("intercept_classes", ["artillery"]) as Array).has(String(s.get("cls", ""))):
		return intercept_strike(w, fid, at, "rocket" if int(s.get("salvo", 1)) > 1 else "shell")
	if bool(s.get("guided", false)) and _c7_any(w):
		return intercept_strike(w, fid, at, "missile", true)   # G7 CIWS7: guided missiles into a rotary CIWS's radius
	return false


## G7 CIWS7: true when any rotary CIWS mount exists (guided-missile intercepts are theirs only).
static func _c7_any(w: SimWorld) -> bool:
	var st = w.sys_state.get("ciws7")
	return st != null and not (st.m as Dictionary).is_empty()


## Interception query for strikes (MECH6b: cruise strike, MLRS rockets, loitering munitions on impact): true when
## an active, ready CIWS of an enemy of attacker_fid covers `at` (that CIWS then reloads; CiwsIntercept emitted).
## G7 CIWS7: rotary CIWS mounts (def.ciws7) are measured from their roof mount point (e.c7m), need rounds in the drum
## and their spin-up inside the lay window, spend a burst from the drum and kill with the def's intercept_pk (a miss
## lets this threat through to the next CIWS); only_c7 = guided missiles (the laser CIWS never took those).
static func intercept_strike(w: SimWorld, attacker_fid: int, at: Vector2, kind: String, only_c7: bool = false) -> bool:
	for bid in Airdef.sub_list(w, "ciws"):
		var b: Dictionary = w.entities[bid]
		var c7 := _is_c7(b)
		if only_c7 and not c7:
			continue
		if not w.is_enemy(attacker_fid, int(b.owner)) or not Airdef.source_active(w, b):
			continue
		if (not c7 and not _ready(w, int(bid))) or (c7 and not _ciws7().can_intercept(w, b)):
			continue
		var c: Dictionary = Content.building(String(b.def)).get("ciws", {})
		if Vector2(b.get("c7m", b.pos)).distance_to(at) > float(c.get("radius", 6.0)):
			continue
		var lt := _lay_ticks(w, b, at)   # G7 TURRET7C: the head must lay onto the threat first
		if c7 and lt >= 0:
			lt = maxi(lt, _ciws7().spin_left(w, b))   # G7 CIWS7: lays while the barrels spin up
			var window := roundi(float(Traverse7.cfg().get("ciws", {}).get("window_s", 0.75)) * SimWorld.TICK_RATE)
			if lt > window:
				lt = -1
		_start_lay(w, b, at, lt)
		if lt < 0:
			continue   # too far round to lay in time: it starts swinging, this one gets through, the CIWS stays ready
		if c7:
			if _ciws7().intercept(w, b, at, lt, kind):
				return true
			continue   # G7 CIWS7: the burst missed: the threat flies on (the next CIWS may still take it)
		_spend(w, int(bid), _ciws_interval(c))
		w.emit("CiwsIntercept", {"ciws": int(bid), "owner": int(b.owner), "attacker": attacker_fid, "kind": kind, "pos": at, "lay_ticks": lt})
		return true
	return false


## Target-side damage factor (G6Hooks.damage_mult delegate): an anti_drone weapon with anti_drone_mult vs a drone.
static func damage_mult(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	if not bool(s.get("anti_drone", false)) or t.get("kind", "") != "unit":
		return 1.0
	if not Airdef._has_bit(w, t, Airdef.B_DRONE):
		return 1.0
	return float(Content.weapon(String(s.get("weapon", ""))).get("anti_drone_mult", 1.0))


## True when e is a drone (counter_drone drone_* rules).
static func is_drone(w: SimWorld, e: Dictionary) -> bool:
	return e.get("kind", "") == "unit" and Airdef._has_bit(w, e, Airdef.B_DRONE)


static func ccfg() -> Dictionary:
	return Airdef.cfg().get("counter_drone", {})


static func _track_mult() -> float:
	return maxf(float(Traverse7.cfg().get("ciws", {}).get("track_mult", 3.0)), 1.0)


## Ticks the CIWS head needs to lay onto `at` from where it points now (0 = already within tolerance).
static func _full_lay_ticks(w: SimWorld, b: Dictionary, at: Vector2) -> int:
	var m := Traverse7.mount(b)
	if int(m[0]) == Traverse7.MOUNT_NONE or float(m[1]) <= 0.0:
		return 0
	var v: Vector2 = at - Vector2(b.pos)
	if v.length_squared() < 0.0001:
		return 0
	var diff := absf(wrapf(v.angle() - Traverse7.bearing(w, b, int(w.tick)), -PI, PI))
	return ceili(maxf(diff - float(m[2]), 0.0) / float(m[1]) - 0.0001)


## The lay time to intercept at `at`, or -1 when that is more than the engagement window (a threat the head cannot get
## round to in time).
static func _lay_ticks(w: SimWorld, b: Dictionary, at: Vector2) -> int:
	var ticks := _full_lay_ticks(w, b, at)
	var window := roundi(float(Traverse7.cfg().get("ciws", {}).get("window_s", 0.75)) * SimWorld.TICK_RATE)
	return ticks if ticks <= window else -1


## Records the point CIWS head b is to swing onto (advanced one tick of slew per tick by _advance_lays). A threat out of
## reach (lt < 0) still gets the head swung onto it (cued toward it), so the next one there is met laid.
static func _start_lay(w: SimWorld, b: Dictionary, at: Vector2, lt: int) -> void:
	if lt == 0:
		return
	var st := _state(w)
	if not st.has("lay"):
		st["lay"] = {}
	var span := lt if lt > 0 else _full_lay_ticks(w, b, at)
	(st.lay as Dictionary)[int(b.id)] = [snappedf(at.x, 1.0 / 1024.0), snappedf(at.y, 1.0 / 1024.0), int(w.tick) + span + 2]


## Slews every CIWS head that is still swinging onto an intercepted / unreachable threat (ascending ids).
static func _advance_lays(w: SimWorld) -> void:
	var st = w.sys_state.get("counterdrone")
	if st == null or not st.has("lay") or (st.lay as Dictionary).is_empty():
		return
	var ld: Dictionary = st.lay
	var ids := ld.keys()
	ids.sort()
	for k in ids:
		var rec: Array = ld[k]
		var b = w.entities.get(int(k))
		if b == null or int(w.tick) > int(rec[2]) or not Airdef.source_active(w, b):
			ld.erase(k)
			continue
		var c: Dictionary = Content.building(String(b.def)).get("ciws", {})
		if Traverse7.lay(w, b, Vector2(float(rec[0]), float(rec[1])), float(_ciws_interval(c)) / SimWorld.TICK_RATE, false, -1):
			ld.erase(k)


static func _ciws_interval(c: Dictionary) -> int:
	return maxi(roundi(60.0 / maxf(float(c.get("shots_per_min", 12)), 0.01) * SimWorld.TICK_RATE), 1)


static func _state(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get("counterdrone")
	if st == null:
		st = {"ready": {}, "ver": VER}
		w.sys_state["counterdrone"] = st
	return st


static func _ready(w: SimWorld, bid: int) -> bool:
	var st = w.sys_state.get("counterdrone")
	return st == null or int((st.ready as Dictionary).get(bid, 0)) <= w.tick


static func _spend(w: SimWorld, bid: int, ticks: int) -> void:
	var rd: Dictionary = _state(w).ready
	rd[bid] = w.tick + ticks
	var gone := []
	for k in rd:
		if not w.entities.has(int(k)) or int(rd[k]) <= w.tick:
			gone.append(k)
	for k in gone:
		rd.erase(k)


## Nearest airborne enemy drone within r of b (ties -> lower id), or null.
static func _nearest_drone(w: SimWorld, b: Dictionary, r: float):
	var best = null
	var bd := r * r
	var bp: Vector2 = b.pos
	for id in Airdef.sub_list(w, "drone"):
		var d: Dictionary = w.entities[id]
		if not w.is_enemy(int(b.owner), int(d.owner)) or bool(d.get("air_landed", false)):
			continue
		var dd := bp.distance_squared_to(Vector2(d.pos))
		if dd <= bd and (best == null or dd < bd):   # ascending ids: a tie keeps the lower id
			best = d
			bd = dd
	return best


## Destroys drone t: a launched drone is removed G5-style (no wreck; G5Mech / the strike owner sees it gone),
## any other drone unit takes a lethal hit from src through the Damage pipeline.
static func _down(w: SimWorld, t: Dictionary, src: Dictionary, cause: String) -> void:
	if bool(Content.unit(String(t.def)).get("launched_drone", false)):
		_remove(w, t, cause, int(src.owner))
		return
	if _damage == null:
		_damage = load("res://sim/systems/damage.gd")
	var s := {"weapon": String(Airdef._def(src).get("weapon", "")), "damage": float(ccfg().get("kill_damage", 100000.0)),
		"cls": "energy", "range": 0.0, "accuracy": 1.0, "cooldown": 1.0}
	_damage.apply_hit(w, src, t, s, true)


## Removes t without a wreck or kill stat (launched drone hit, captured drone).
static func _remove(w: SimWorld, t: Dictionary, cause: String, by_owner: int) -> void:
	w.entities.erase(int(t.id))
	w.emit("EntityDestroyed", {"id": int(t.id), "kind": "unit", "def": t.def, "owner": t.owner, "pos": t.pos,
		"cause": cause, "killer_owner": by_owner, "squad": -1})
