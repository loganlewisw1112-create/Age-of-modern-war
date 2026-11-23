extends RefCounted
## G7 (CREEP7): doomsday / living cores, escalation phases, learned-reaction driver (master scope sections 8, 10).
## Numbers: rules.g7_machine.cores / phases / react (content/g7/rules_g7_machine.json), all PROVISIONAL.
##
## A core is a Machine building (rules cores.def, current art) registered with register()/place() or regrown from a
## burrowed-core seed (Creep). Living cores pulse (CorePulse), grow armour plating over time (+plate_hp max/cur hp per
## plate, up to plate_max: CorePlated) and report hits (CoreHit {id, ix, pos, dmg, intensity 0..1} for the radio
## screams). The LAST core alive, at or below phase2_hp_frac of its hp, tears out of the ground (CoreUprooted) and
## walks: a walker unit (rules walker_def) with the core's hp that heads for the enemy facility / HQ. It is held by EMP
## (MachineEW7), slowed by leg damage (speed x max(hp share, walker_leg_slow_min)) and stopped by barrier lines.
## finish(w, ix, by) is the core-breaker hook (CNSIM7): it destroys the core or walker outright.
## e.core7 = core index on the core building / walker (damage.gd may floor hp for non core-breaker damage, see CR).
##
## State: w.sys_state.cores = {ver, phase, list [{ix, id, alive, plate, hp_last, walk, tgt, t0}], lost, pending,
##   react {learned [], ...}, wave_t} created on the first core, set_phase() or in a creep match.
## countdown_rate(w): Last Protocol doomsday countdown speed = max(min, base + per_coverage x creep coverage
##   - per_core_lost x cores lost).
## Learned reactions: MachineReact7 (sim/ai/machine_react7.gd) learns from last tick's events and acts for AI-run
##   Machine sides; both are driven from here (cadenced) so the AI hook needs no other file.

const HotState = preload("res://sim/hot_state.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Creep = preload("res://sim/systems/creep.gd")
const MachineEW7 = preload("res://sim/systems/machine_ew7.gd")
const MachineReact7 = preload("res://sim/ai/machine_react7.gd")

const VER := 1


static func RK() -> Dictionary:
	return Content.rules().get("g7_machine", {}).get("cores", {})


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get("cores")
	if s == null:
		s = {}
		w.sys_state["cores"] = s
	if not s.has("ver"):
		s.merge({"ver": VER, "phase": 0, "list": [], "lost": 0, "pending": [], "react": {"learned": []}, "wave_t": 0})
	return s


static func _t(secs: float) -> int:
	return maxi(roundi(secs * SimWorld.TICK_RATE), 1)


# ================================================================ public API
## Makes building bid a doomsday core. Returns its core index.
static func register(w: SimWorld, bid: int) -> int:
	var s := _st(w)
	var e = w.entities.get(bid)
	if e == null:
		return -1
	for c in s.list:
		if int(c.id) == bid:
			return int(c.ix)
	var ix: int = (s.list as Array).size()
	e.core7 = ix
	(s.list as Array).append({"ix": ix, "id": bid, "alive": true, "plate": 0, "hp_last": float(e.hp), "walk": -1,
		"tgt": null, "t0": w.tick})
	Creep.enable(w)
	w.cache.erase("creep_src")
	return ix


## Spawns a complete core building for fid at cell (origin) and registers it. Returns the building id.
static func place(w: SimWorld, fid: int, cell: Vector2i, def: String = "") -> int:
	var d := def if def != "" else String(RK().get("def", "m_core"))
	var bid := w.spawn_building(d, fid, cell, true)
	register(w, bid)
	return bid


## [{ix, id, pos, hp, max_hp, plate, alive, walking}] in core order (dead cores included, alive=false).
static func list(w: SimWorld) -> Array:
	var s = w.sys_state.get("cores")
	if s == null or not s.has("list"):
		return []
	var out := []
	for c in s.list:
		var id := int(c.walk) if int(c.walk) >= 0 else int(c.id)
		var e = w.entities.get(id) if bool(c.alive) else null
		var hp := 0.0
		if e != null:
			hp = HotState.get_hp(w, id) if e.kind == "unit" else float(e.hp)
		out.append({"ix": c.ix, "id": id, "pos": e.pos if e != null else Vector2.ZERO, "hp": hp,
			"max_hp": float(e.max_hp) if e != null else 0.0, "plate": c.plate, "alive": bool(c.alive),
			"walking": int(c.walk) >= 0})
	return out


static func alive_count(w: SimWorld) -> int:
	var n := 0
	for c in list(w):
		if c.alive:
			n += 1
	return n


static func lost(w: SimWorld) -> int:
	var s = w.sys_state.get("cores")
	return 0 if s == null else int(s.get("lost", 0))


## Unit id of the walking last core, or -1.
static func walker(w: SimWorld) -> int:
	for c in list(w):
		if c.alive and c.walking:
			return int(c.id)
	return -1


## Doomsday countdown speed multiplier (1.0 = nominal).
static func countdown_rate(w: SimWorld) -> float:
	var cd: Dictionary = RK().get("countdown", {})
	var r := float(cd.get("base", 1.0)) + float(cd.get("per_coverage", 2.0)) * Creep.coverage(w) \
		- float(cd.get("per_core_lost", 0.25)) * float(lost(w))
	return maxf(r, float(cd.get("min", 0.25)))


## Escalation phase (LPMODE7 drives it): creep speed, unit tier, assault waves (rules.g7_machine.phases).
static func set_phase(w: SimWorld, n: int) -> void:
	var s := _st(w)
	var nn := clampi(n, 0, maxi((Content.rules().get("g7_machine", {}).get("phases", []) as Array).size() - 1, 0))
	if int(s.phase) == nn:
		return
	s.phase = nn
	s.wave_t = w.tick
	w.emit("EscalationPhase", {"phase": nn})


static func phase(w: SimWorld) -> int:
	var s = w.sys_state.get("cores")
	return 0 if s == null else int(s.get("phase", 0))


static func phase_info(w: SimWorld) -> Dictionary:
	var n := phase(w)
	for p in Content.rules().get("g7_machine", {}).get("phases", []):
		if int(p.get("n", -1)) == n:
			return p
	return {"n": n, "creep_mult": 1.0, "unit_tier": 1, "wave_every_s": 0, "wave_size": 0}


## Core-breaker hook: destroys core ix (building or walker) outright. Returns true when something was destroyed.
static func finish(w: SimWorld, ix: int, by: int = -1) -> bool:
	var s = w.sys_state.get("cores")
	if s == null or ix < 0 or ix >= (s.list as Array).size():
		return false
	var c: Dictionary = s.list[ix]
	if not bool(c.alive):
		return false
	var id := int(c.walk) if int(c.walk) >= 0 else int(c.id)
	if not w.entities.has(id):
		return false
	w.destroy(id, "core_breaker", by)
	_mark_dead(w, s, c)
	return true


static func _mark_dead(w: SimWorld, s: Dictionary, c: Dictionary) -> void:
	if not bool(c.alive):
		return
	c.alive = false
	s.lost = int(s.lost) + 1
	w.emit("CoreDestroyed", {"ix": c.ix, "walking": int(c.walk) >= 0, "left": alive_count(w)})


static func tick(w: SimWorld) -> void:
	var s = w.sys_state.get("cores")
	if s == null:
		if not Creep.enabled(w):
			return
		s = _st(w)
	elif not s.has("ver"):
		s = _st(w)
	if not (s.pending as Array).is_empty():
		var pend: Array = s.pending
		s.pending = []
		for bid in pend:
			register(w, int(bid))
	var rk := RK()
	var pulse := _t(float(rk.get("pulse_every_s", 3.0)))
	var plate := _t(float(rk.get("plate_every_s", 30.0)))
	var alive := 0
	for c in s.list:
		if bool(c.alive):
			alive += 1
	for c in s.list:
		if not bool(c.alive):
			continue
		if int(c.walk) >= 0:
			_walk_step(w, s, c, rk)
			continue
		var b = w.entities.get(int(c.id))
		if b == null:
			_mark_dead(w, s, c)
			alive -= 1
			continue
		var age := w.tick - int(c.t0)
		if age > 0 and (age + int(c.ix)) % pulse == 0:
			w.emit("CorePulse", {"id": c.id, "ix": c.ix, "pos": b.pos, "plate": c.plate})
		if age > 0 and age % plate == 0 and int(c.plate) < int(rk.get("plate_max", 12)):
			var add := float(rk.get("plate_hp", 250.0))
			c.plate = int(c.plate) + 1
			b.max_hp = float(b.max_hp) + add
			b.hp = float(b.hp) + add
			c.hp_last = float(c.hp_last) + add
			w.emit("CorePlated", {"id": c.id, "ix": c.ix, "plate": c.plate, "max_hp": b.max_hp})
		_hit_check(w, c, b, float(b.hp), rk)
		if alive == 1 and float(b.hp) <= float(rk.get("phase2_hp_frac", 0.3)) * float(b.max_hp):
			_uproot(w, s, c, b, rk)
	var rre = s.get("react")
	if rre is Dictionary and not bool(rre.get("fell", false)) and (rre.get("learned", []) as Array).size() < 4:
		if _machine_fell(w, Creep.machine_fids(w), float(MachineReact7.RR().get("major_hp", 2500.0))):
			rre.fell = true
	MachineReact7.learn_step(w, s)
	if not w.ai_state.is_empty():
		for fid in Creep.machine_fids(w):
			if w.ai_state.has(fid) and w.factions[fid].alive:
				MachineReact7.think(w, fid)


## Learned reaction 3 trigger (moved here from sim/ai/machine_react7.gd by REGRESS7-2: an AI file may not read the world
## event history, AI-02): did a major structure of a Machine side (HQ role, or hp >= major) fall LAST tick, other than
## a core uprooting itself? Reads last tick's EntityDestroyed events from w.event_log.
static func _machine_fell(w: SimWorld, mfs: Array, major: float) -> bool:
	var elog: Array = w.event_log
	var i := elog.size() - 1
	while i >= 0:
		var ev: Dictionary = elog[i]
		var t := int(ev.get("tick", 0))
		if t < w.tick - 1:
			break
		i -= 1
		if t != w.tick - 1 or String(ev.type) != "EntityDestroyed" or String(ev.get("kind", "")) != "building":
			continue
		if not mfs.has(int(ev.owner)) or String(ev.get("cause", "")) == "core_uprooted":
			continue
		var d := Content.building(String(ev.def))
		var hq := ""
		var f = w.factions.get(int(ev.owner))
		if f != null:
			hq = String(Content.faction(String(f.get("faction_def", ""))).get("roles", {}).get("hq", ""))
		if float(d.get("hp", 0.0)) >= major or String(ev.def) == hq:
			return true
	return false


static func _hit_check(w: SimWorld, c: Dictionary, e: Dictionary, hp: float, rk: Dictionary) -> void:
	var dmg := float(c.hp_last) - hp
	c.hp_last = hp
	if dmg >= float(rk.get("hit_event_min", 1.0)):
		var inten := clampf(dmg / maxf(float(e.max_hp) * 0.05, 1.0), 0.0, 1.0)
		w.emit("CoreHit", {"id": e.id, "ix": c.ix, "pos": e.pos, "dmg": snappedf(dmg, 0.01),
			"intensity": snappedf(inten, 0.001), "walking": int(c.walk) >= 0})


## Phase 2: the last core tears out of the ground and becomes a walker with the same hp share.
static func _uproot(w: SimWorld, s: Dictionary, c: Dictionary, b: Dictionary, rk: Dictionary) -> void:
	var wd := String(rk.get("walker_def", "m_colossus"))
	if Content.unit(wd).is_empty():
		return
	var pos: Vector2 = b.pos
	var mult := float(rk.get("walker_hp_mult", 1.0))
	var uid := w.spawn_unit(wd, int(b.owner), pos)
	var u: Dictionary = w.entities[uid]
	u.max_hp = snappedf(float(b.max_hp) * mult, 1.0 / 1024.0)
	u.hp = snappedf(float(b.hp) * mult, 1.0 / 1024.0)
	u.core7 = c.ix
	u.order = {"type": "hold"}
	HotState.touch(w, uid)
	c.walk = uid
	c.hp_last = float(u.hp)
	w.destroy(int(c.id), "core_uprooted")
	w.emit("CoreUprooted", {"ix": c.ix, "unit": uid, "pos": pos})


static func _walk_target(w: SimWorld, fid: int, from: Vector2) -> Variant:
	var defs: Array = RK().get("walker_target_defs", ["g7_cn_facility"])
	var best = null
	var bd := INF
	var hq_best = null
	var hd := INF
	for e in SimIndex.of(w, "building"):
		if not w.is_enemy(fid, int(e.owner)) or not w.entities.has(int(e.id)):
			continue
		var d2 := (e.pos as Vector2).distance_squared_to(from)
		if defs.has(String(e.def)):
			if d2 < bd:
				bd = d2
				best = e.pos
		elif d2 < hd:
			hd = d2
			hq_best = e.pos
	return best if best != null else hq_best


## G7 (THREAT7): walker pathing. Coarse A* over cell x cell tile blocks (rules g7_threats.walker_path, cell 4),
## a block is open when its centre tile is vehicle-passable. Barrier lines are NOT planned around: they still stop
## the walker (CoreWalkerBlocked). Returns world waypoints ending at `to`, or [] (no route: walk straight as before).
## The block grid is rebuilt from terrain (deterministic) and cached in w.cache (not saved).
static func walk_path(w: SimWorld, from: Vector2, to: Vector2) -> Array:
	var wp: Dictionary = Content.rules().get("g7_threats", {}).get("walker_path", {})
	var cs := maxi(int(wp.get("cell", 4)), 1)
	var gw := ceili(float(w.map.w) / cs)
	var gh := ceili(float(w.map.h) / cs)
	var key := "core_walk_grid_%d" % cs
	var g = w.cache.get(key)
	if g == null or (g as AStarGrid2D).region.size != Vector2i(gw, gh):
		g = AStarGrid2D.new()
		g.region = Rect2i(0, 0, gw, gh)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.update()
		for y in gh:
			for x in gw:
				var tc := Vector2i(mini(x * cs + cs / 2, int(w.map.w) - 1), mini(y * cs + cs / 2, int(w.map.h) - 1))
				if not Terrain.passable(w.terrain_at(tc), "vehicle"):
					g.set_point_solid(Vector2i(x, y), true)
		w.cache[key] = g
	var a := Vector2i(clampi(floori(from.x / cs), 0, gw - 1), clampi(floori(from.y / cs), 0, gh - 1))
	var b := Vector2i(clampi(floori(to.x / cs), 0, gw - 1), clampi(floori(to.y / cs), 0, gh - 1))
	if a == b:
		return [to]
	var sa: bool = g.is_point_solid(a)
	var sb: bool = g.is_point_solid(b)
	g.set_point_solid(a, false)
	g.set_point_solid(b, false)
	var ids: Array = g.get_id_path(a, b)
	g.set_point_solid(a, sa)
	g.set_point_solid(b, sb)
	if ids.is_empty():
		return []
	var out := []
	for i in range(1, ids.size() - 1):
		var c: Vector2i = ids[i]
		out.append(Vector2((c.x + 0.5) * cs, (c.y + 0.5) * cs))
	out.append(to)
	return out


static func _walk_step(w: SimWorld, s: Dictionary, c: Dictionary, rk: Dictionary) -> void:
	var uid := int(c.walk)
	var u = w.entities.get(uid)
	if u == null:
		_mark_dead(w, s, c)
		return
	var hp := HotState.get_hp(w, uid)
	_hit_check(w, c, u, hp, rk)
	var p := HotState.get_pos(w, uid)
	if c.tgt == null or (w.tick + uid) % 100 == 0:
		var nt = _walk_target(w, int(u.owner), p)
		if nt != c.tgt or not c.has("path"):
			c.tgt = nt
			c.path = [] if nt == null else walk_path(w, p, nt)
	if c.tgt == null or MachineEW7.held(w, uid) != "":
		return
	var path: Array = c.get("path", [])
	while path.size() > 1 and p.distance_to(path[0]) < 0.75:
		path.pop_front()
	var goal: Vector2 = path[0] if not path.is_empty() else c.tgt
	var share := clampf(hp / maxf(float(u.max_hp), 1.0), float(rk.get("walker_leg_slow_min", 0.35)), 1.0)
	var spd := float(rk.get("walker_speed", 0.9)) * share / SimWorld.TICK_RATE
	var np := p.move_toward(goal, spd)
	np = Vector2(snappedf(np.x, 1.0 / 1024.0), snappedf(np.y, 1.0 / 1024.0))
	var nc := w.cell_of(np)
	# G7.1 I4: wildfire fire lines also stop the walker (same as creep barriers / impassable terrain).
	var Fire71 = preload("res://sim/systems/fire71.gd")
	var on_fire := Fire71.blocks_at(w, np)
	if Creep.is_barrier(w, nc) or not Terrain.passable(w.terrain_at(nc), "vehicle") or on_fire:
		if not bool(c.get("stopped", false)):
			c.stopped = true
			w.emit("CoreWalkerBlocked", {"ix": c.ix, "unit": uid, "pos": p, "fire": on_fire})
			if not Creep.is_barrier(w, nc) and not on_fire:
				c.path = walk_path(w, p, c.tgt)   # terrain corner: re-plan once
		return
	c.stopped = false
	HotState.set_pos(w, uid, np)
	u.facing = snappedf((goal - p).angle(), 1.0 / 1024.0)


static func validate_command(_w: SimWorld, cmd: Dictionary) -> String:
	return "%s: not implemented yet" % String(cmd.get("type", ""))


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
