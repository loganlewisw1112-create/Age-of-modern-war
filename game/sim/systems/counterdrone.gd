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
## State w.sys_state.counterdrone {ready: {bid: tick}, ver}: first tick each CIWS / net post may act again.
## Created on first use (G5 matches never get it); saved and hashed.
## Determinism: ascending ids, integer ticks, no rng. Never preload g6_hooks.gd, Damage, G5Mech or Movement here:
## g6_hooks preloads this file (cycle). Damage is loaded lazily for non-launched drone kills.

const Airdef = preload("res://sim/systems/airdef.gd")

const VER := 1

static var _damage = null


static func tick(w: SimWorld) -> void:
	var sub := Airdef.sub_state(w)
	if (sub.ciws as Array).is_empty() and (sub.net as Array).is_empty() and (sub.jam as Array).is_empty():
		return
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
		var c: Dictionary = Content.building(String(b.def)).get("ciws", {})
		var t = _nearest_drone(w, b, float(c.get("radius", 6.0)))
		if t == null:
			continue
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
	return false


## Interception query for strikes (MECH6b: cruise strike, MLRS rockets, loitering munitions on impact): true when
## an active, ready CIWS of an enemy of attacker_fid covers `at` (that CIWS then reloads; CiwsIntercept emitted).
static func intercept_strike(w: SimWorld, attacker_fid: int, at: Vector2, kind: String) -> bool:
	for bid in Airdef.sub_list(w, "ciws"):
		var b: Dictionary = w.entities[bid]
		if not w.is_enemy(attacker_fid, int(b.owner)) or not Airdef.source_active(w, b) or not _ready(w, int(bid)):
			continue
		var c: Dictionary = Content.building(String(b.def)).get("ciws", {})
		if Vector2(b.pos).distance_to(at) > float(c.get("radius", 6.0)):
			continue
		_spend(w, int(bid), _ciws_interval(c))
		w.emit("CiwsIntercept", {"ciws": int(bid), "owner": int(b.owner), "attacker": attacker_fid, "kind": kind, "pos": at})
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
