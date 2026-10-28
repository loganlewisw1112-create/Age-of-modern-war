extends RefCounted
## G7 TURRET7B (spec G7_REFERENCE 13.9c-30, owner: "ensure all turret types actually turn towards enemies and fire
## towards them ... make it realistic"): every turret / mount traverses toward its target at a per-def rate and fires
## only once it is laid on it (within a small tolerance). Numbers PROVISIONAL in content/g7/rules_g7_traverse.json.
##
## State (saved + hashed with the entity, Q-snapped floats):
##   e.tf  world bearing of the mount (radians, (-PI, PI]) at its last lay
##   e.tft tick of that lay
##   e.tfh tick until which the mount holds that bearing (hold_s, at least the weapon cooldown + 0.5 s); after it the
##         mount returns to its rest bearing at the same rate (and direct-fire building mounts scan around it).
## The current bearing at any tick is a PURE function of that state (bearing()), so idle mounts cost nothing per tick
## and the display (render_snap "tb") draws exactly the bearing the sim lays from.
##
## Modes (per def): MOUNT_TURRET (separate turret / mount: tanks, IFVs, CN APC mounts: the hull never swings to fire),
## MOUNT_HULL (turreted vehicle or ship whose art has no separate turret: the whole hull traverses at the gun rate
## instead of snapping; while moving it fires as before), MOUNT_BLD (every armed building, Turrets7 and WallTurret7
## turrets). Unlisted unit defs (infantry, turretless vehicles, aircraft) keep the old instant turn.
## Callers: Combat._fire (lay + face), Turrets7.tick, WallTurret7.tick; render_snap (bearing for the display).

const CFG_PATH := "res://content/g7/rules_g7_traverse.json"
const Q := 1.0 / 1024.0            # same quantum as Combat.Q (saved floats exact in decimal text)
const TR := 20.0                   # SimWorld.TICK_RATE (no preload: world.gd preloads the systems)
const MOUNT_NONE := 0
const MOUNT_TURRET := 1
const MOUNT_HULL := 2
const MOUNT_BLD := 3

static var _cfg = null
static var _m := {}                # def id -> [mode, rad per tick, tol rad, tol indirect rad, scan amp rad (0 = none)]
static var counters := {"lay": 0, "laid": 0, "slew": 0}   # test / playtest evidence (not state)
static var enabled := true         # cost A/B only (.plan/sim_ab7_turret.gd): false = every def is unmounted (the old instant turn)


static func cfg() -> Dictionary:
	if _cfg == null:
		var d = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
		_cfg = d.get("_traverse7", {}) if d is Dictionary else {}
	return _cfg


## Test hook: forget the cached config and per-def mounts (after a test edits the rules).
static func reset_cache() -> void:
	_cfg = null
	_m.clear()


static func _deg(v) -> float:
	return deg_to_rad(float(v)) / TR


## [mode, rad per tick, tol, tol indirect, scan amp] for entity e (cached per def).
static func mount(e: Dictionary) -> Array:
	if not enabled:
		return [MOUNT_NONE, 0.0, 0.0, 0.0, 0.0]
	var key := String(e.get("def", ""))
	var m = _m.get(key)
	if m != null:
		return m
	var c := cfg()
	var tol := deg_to_rad(float(c.get("tol_deg", 5.0)))
	var toli := deg_to_rad(float(c.get("tol_indirect_deg", 10.0)))
	var scan := deg_to_rad(float(c.get("scan_deg", 20.0)))
	m = [MOUNT_NONE, 0.0, tol, toli, 0.0]
	if String(e.get("kind", "")) == "unit":
		var u: Dictionary = c.get("units", {})
		if (u.get("turret", {}) as Dictionary).has(key):
			m = [MOUNT_TURRET, _deg(u.turret[key]), tol, toli, 0.0]
		elif (u.get("hull", {}) as Dictionary).has(key):
			m = [MOUNT_HULL, _deg(u.hull[key]), tol, toli, 0.0]
	elif String(e.get("kind", "")) == "building" and not (c.get("no_lay_buildings", []) as Array).has(key):
		var bo: Dictionary = c.get("buildings", {})
		var d: Dictionary = Content.building(key)
		var wid := String(d.get("weapon", ""))
		var wd: Dictionary = Content.weapon(wid) if wid != "" else {}
		var ind := bool(wd.get("indirect", false))
		if bo.has(key):
			m = [MOUNT_BLD, _deg(bo[key]), tol, toli, 0.0 if ind else scan]
		elif not wd.is_empty():
			var dv: Dictionary = c.get("derive", {})
			var aa := bool(wd.get("anti_air", false)) or bool(wd.get("anti_air_low", false)) or bool(wd.get("anti_air_high", false))
			var dmg := float(wd.get("damage", 0))
			var r := float(dv.get("light", 110.0))
			if aa:
				r = float(dv.get("aa", 110.0))
			elif bool(wd.get("guided", false)):
				r = float(dv.get("guided", 60.0))
			elif ind:
				r = float(dv.get("indirect", 25.0))
			elif dmg >= float(dv.get("heavy_dmg", 80.0)):
				r = float(dv.get("heavy", 35.0))
			elif dmg >= float(dv.get("mid_dmg", 25.0)):
				r = float(dv.get("mid", 60.0))
			m = [MOUNT_BLD, _deg(r), tol, toli, 0.0 if ind else scan]
	_m[key] = m
	return m


static func mode_of(e: Dictionary) -> int:
	return int(mount(e)[0])


## Rest bearing: a vehicle turret rides hull-forward; a wall turret its mount normal; any other building faces the
## map centre; direct-fire building mounts sweep +-scan around it (pure function of the tick, phase by id).
static func rest_of(w, e: Dictionary, m: Array, tick: int) -> float:
	if int(m[0]) != MOUNT_BLD:
		return float(e.get("facing", 0.0))
	var base := 0.0
	if e.has("wt_m"):
		base = float(e.get("facing", 0.0))
	else:
		var mp = w.map if w != null else {}
		var cpos := Vector2(float(mp.get("w", 0)), float(mp.get("h", 0))) * 0.5
		var v: Vector2 = cpos - Vector2(e.pos)
		base = v.angle() if v.length_squared() > 1.0 else 0.0
		base = snappedf(base, PI / 4.0)   # rest on a whole aim step (the drawn head reads square-on)
	var amp := float(m[4])
	if amp > 0.0:
		var per := maxf(float(cfg().get("scan_period_s", 16.0)) * TR, 1.0)
		base += amp * sin(TAU * float(tick + int(e.get("id", 0)) * 53) / per)
	return base


## Current world bearing of e's mount at `tick` (pure; the display reads it through render_snap "tb").
static func bearing(w, e: Dictionary, tick: int) -> float:
	var m := mount(e)
	if int(m[0]) == MOUNT_HULL:
		return float(e.get("facing", 0.0))
	var rest := rest_of(w, e, m, tick)
	if not e.has("tf"):
		return rest
	var tf := float(e.tf)
	var over := tick - int(e.get("tfh", 0))
	if over <= 0:
		return tf
	var d := wrapf(rest - tf, -PI, PI)
	var mv := float(m[1]) * float(over)
	return rest if absf(d) <= mv else wrapf(tf + signf(d) * mv, -PI, PI)


## Lay e's mount toward world point `to`. Returns true when laid within tolerance (the weapon may fire this tick),
## false while it still traverses (the caller holds fire). cd_s: the weapon cooldown (s), keeps the hold past it.
## Called on the ticks the weapon is ready (no per-tick cost between shots); tracking the same target (tid, saved as
## e.tfa) the bearing covers the ticks since its last lay (at most max_catch_ticks); a new target gets one tick.
static func lay(w, e: Dictionary, to: Vector2, cd_s: float, indirect := false, tid := -1) -> bool:
	var m := mount(e)
	var mode := int(m[0])
	if mode == MOUNT_NONE or float(m[1]) <= 0.0:
		return true
	if mode == MOUNT_HULL and bool(e.get("moving", false)):
		return true   # a hull-laid gun on the move fires as before (its art has no turret to traverse)
	var v: Vector2 = to - Vector2(e.pos)
	if v.length_squared() < 0.0001:
		return true
	counters.lay += 1
	var want := v.angle()
	var tick := int(w.tick)
	var step := float(m[1])
	var cur: float
	if mode == MOUNT_HULL:
		cur = float(e.get("facing", 0.0))
	else:
		cur = bearing(w, e, tick)
		if e.has("tft"):
			# the same target tracked between shots while held covers the ticks since the last lay; a new target, or a
			# returning / idle mount, starts from bearing() with one tick of slew (no free swing onto a new target)
			var same := tid >= 0 and int(e.get("tfa", -1)) == tid
			var held := (tick - int(e.tft)) if same and tick <= int(e.get("tfh", tick)) else 1
			step *= float(clampi(held, 1, int(cfg().get("max_catch_ticks", 10))))
	var d := wrapf(want - cur, -PI, PI)
	var nb := want if absf(d) <= step else cur + signf(d) * step
	nb = snappedf(wrapf(nb, -PI, PI), Q)
	if mode == MOUNT_HULL:
		e.facing = nb
	else:
		e.tf = nb
		e.tft = tick
		e.tfa = tid
		var hold := roundi(float(cfg().get("hold_s", 2.5)) * TR)
		e.tfh = tick + maxi(hold, roundi((cd_s + 0.5) * TR))
	var ok := absf(wrapf(want - nb, -PI, PI)) <= float(m[3] if indirect else m[2])
	if ok:
		counters.laid += 1
	else:
		counters.slew += 1
	return ok


## The hull facing Combat writes on a shot: a mounted weapon never swings the hull (MOUNT_TURRET keeps it; MOUNT_HULL
## already laid it); unmounted units (infantry, turretless vehicles) turn to the shot as before.
static func face(e: Dictionary, shot_angle: float) -> float:
	var mode := mode_of(e)
	if mode == MOUNT_TURRET or mode == MOUNT_BLD or (mode == MOUNT_HULL and not bool(e.get("moving", false))):
		return float(e.get("facing", shot_angle))
	return shot_angle


## render_snap helper: the drawn bearing of a static (armed building) or a mounted unit, or null when it has none.
static func snap_bearing(w, e: Dictionary):
	var mode := mode_of(e)
	if mode == MOUNT_NONE or mode == MOUNT_HULL:
		return null
	if mode == MOUNT_TURRET and not e.has("tf"):
		return null   # never laid: the turret rides hull-forward (the display's hull row)
	return bearing(w, e, int(w.tick))


## Display helper (G5Art.building_state): G6 turrets with only rot_<f> art turn the whole sprite to the nearest quarter
## of the simulated bearing (rules rot_aim). Returns the rot index, or -1 when the def is not listed.
static func rot_aim_index(def_id: String, tb: float) -> int:
	var c := cfg()
	if not (c.get("rot_aim", []) as Array).has(def_id):
		return -1
	return posmod(roundi((tb - deg_to_rad(float(c.get("rot_aim_offset_deg", 0.0)))) / (PI * 0.5)), 4)
