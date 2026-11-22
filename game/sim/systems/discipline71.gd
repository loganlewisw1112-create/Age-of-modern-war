extends RefCounted
## G7.1 ARMY71 D4 DISCIPLINE (docs/G71_SCOPE.md D4; roster 5A Q1: Last Protocol only, on the GDScript combat path).
## Data: rules.g71_discipline (content/g71/rules_g71_discipline.json, PROVISIONAL numbers).
## Hooks (ARMY71's own files, each behind one per-tick LP flag so skirmish / the benches stay hash-identical):
##   SquadAI._squad_think -> squad_think(w, sq, mem, pool): threat-based squad target choice in place of the old
##                           armour-mult _score loop (members without a pick get the old support move)
##   Combat._pick         -> keep(w, e, cur): a squad soldier keeps the target its squad gave it while it is valid
##   Combat._fire         -> on_shot(w, e, s, cd): magazines + staggered reloads for foot soldiers
## Threat: threat(t) = t's damage per second against the member it threatens most, x in_range_mult when that member is
## inside t's range, x targets_us_mult when t shoots one of us. The squad focus-fires the top threat when it is >=
## focus_ratio x the median (a "big one", NCO calls "Shift fire"); otherwise every member takes the top threat in its
## own sector of fire (auto arcs over the squad front, overlapping; KillZone71.sector_of when painted). Ties: lower id.
## NCO: the squad leader when the squad is first seen (e.d71n). NCO down: "Sergeant's down", the squad re-picks only
## every lost_switch_every thinks, never focus-fires and keeps no reload stagger until a survivor steps up (step_up_s).
## State: w.sys_state.discipline71 {ver, sq: {"<sq>": {nco, lost, focus, n, last_t}}} and per soldier e.d71n (NCO),
## e.d71m (shots left in the magazine), e.d71r (tick its reload ends). All saved + hashed with the world; LP only.
## Outside LP (no w.sys_state.discipline71) every query returns its neutral value at once.
##   threat_of(w, e, t) -> float      threat score of t to soldier e (higher = shoot first; ties: lower id)
##   squad_target(w, sid) -> int      the squad's focus-fire target id (-1 = none / sector fire)
##   nco_of(w, sid) -> int            the squad's NCO id (-1 = none: the squad is sloppy)
##   sloppy(w, e) -> float            1.0 = sharp; > 1 = NCO lost (slot error mult)
##   may_reload(w, e) -> bool         staggered reloads: false = hold the tactical reload, enough mates are reloading
##   cover_pose(e) -> int             0 none, 1 hug, 2 peek, 3 bounding (snapshot, signals layer)
##   stack_of(w, eid) -> Dictionary   {} none, else {bld, slot, door [x,y]} (stacked on a door before entry)
##   signal_of(w, sid) -> Dictionary  {} none, else {kind, at [x,y], until} (leader's hand signal)

const KEY := "discipline71"
const Radio71 = preload("res://sim/systems/radio71.gd")
const KillZone71 = preload("res://sim/systems/killzone71.gd")
const HIT_RECENT := 40

static var _rref = null
static var _c: Dictionary = {}
static var _cmb = null
static var _sqa = null
static var _a8 = null


static func cfg() -> Dictionary:
	var r: Dictionary = Content.rules()
	if is_same(r, _rref):
		return _c
	_rref = r
	_c = r.get("g71_discipline", {})
	return _c


static func enabled() -> bool:
	return bool(cfg().get("enabled", false))


static func _C():
	if _cmb == null:
		_cmb = load("res://sim/systems/combat.gd")
	return _cmb


static func _SQ():
	if _sqa == null:
		_sqa = load("res://sim/systems/squad_ai.gd")
	return _sqa


static func _A8():
	if _a8 == null:
		_a8 = load("res://sim/systems/accuracy8.gd")
	return _a8


static func on(w: SimWorld) -> bool:
	return w.sys_state.has(KEY)


static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		st = {"ver": 1, "sq": {}}
		w.sys_state[KEY] = st
	return st


static func _rec(w: SimWorld, sid: int):
	var st = w.sys_state.get(KEY)
	if st == null:
		return null
	return (st.sq as Dictionary).get(str(sid))


static func _ticks(secs: float) -> int:
	return maxi(roundi(secs * SimWorld.TICK_RATE), 1)


# ================================================================ squad think (LP hook in SquadAI._squad_think)

## G1 NVG vs thermal (LP): mark a squad soldier's gear once (e.g71g). NVG only for soldiers without thermals / old nvg.
static func _gear(e: Dictionary, c: Dictionary) -> void:
	e.g71g = 1
	var g: Dictionary = c.get("gear", {})
	if bool(g.get("nvg_infantry", false)) and not bool(e.get("nvg", false)) and not bool(e.get("thermal", false)):
		e.g71nvg = true


## I2 hand-to-hand on the wall-walk (LP): damage mult for a shot from a soldier on the wall-walk at a target within
## melee range (bayonet / shotgun / flamer by weapon class; rules.g71_discipline.melee, PROVISIONAL). 1.0 otherwise.
## No rng, no saved state; emits Melee71 for the view. Ids decide nothing (one shooter, one target).
static func melee_mult(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary) -> float:
	if e.kind != "unit" or not e.has("morale"):
		return 1.0
	var M: Dictionary = cfg().get("melee", {})
	if M.is_empty():
		return 1.0
	var r := float(M.get("range", 1.6))
	if Vector2(e.pos).distance_squared_to(Vector2(t.pos)) > r * r:
		return 1.0
	if not SimWorld.WallWalk7.on_wall(w, e):
		return 1.0
	var cls := String(s.cls)
	var kind := "other"
	if cls == "flame":
		kind = "flame"
	elif cls == "assault" or String(s.weapon).contains("shotgun"):
		kind = "shotgun"
	elif cls == "small_arms" or cls == "sniper":
		kind = "bayonet"
	w.emit("Melee71", {"shooter": int(e.id), "target": int(t.id), "kind": kind, "pos": e.pos})
	return float(M.get(kind, 1.0))


## One squad think (LP). mem = live, unbroken members (dicts, ascending id); pool = SquadAI's candidate enemies
## {id: n}. Sets members' targets; returns the members that got no target (SquadAI moves idle ones up in support).
static func squad_think(w: SimWorld, sq: int, mem: Array, pool: Dictionary) -> Array:
	var c := cfg()
	var st := _st(w)
	var key := str(sq)
	var rec = st.sq.get(key)
	if rec == null:
		rec = {"nco": -1, "lost": -1, "focus": -1, "n": 0, "last_t": -100000}
		st.sq[key] = rec
	rec.n = int(rec.n) + 1
	for e in mem:
		if not e.has("g71g"):
			_gear(e, c)   # G1: LP gear flags once per soldier
	_nco(w, rec, mem, c)
	var nc: Dictionary = c.get("nco", {})
	var sloppy := int(rec.lost) >= 0
	if sloppy and int(rec.n) % maxi(int(nc.get("lost_switch_every", 3)), 1) != 0:
		return []   # NCO down: slow target switching (members keep what they have)
	var fr := int(rec.focus)
	if fr >= 0 and not pool.has(fr) and _alive_enemy(w, mem[0], fr) != null:
		pool[fr] = 0
	if pool.is_empty():
		rec.focus = -1
		return mem.duplicate()
	var Cm = _C()
	var T: Dictionary = c.get("threat", {})
	var ids: Array = pool.keys()
	ids.sort()
	var thr := {}
	var vals: Array = []
	var cen := Vector2.ZERO
	for e in mem:
		cen += Vector2(e.pos)
	cen /= float(mem.size())
	var tc := Vector2.ZERO
	for tid in ids:
		var t: Dictionary = w.entities[tid]
		var v := _threat_mem(w, t, mem, T)
		thr[tid] = v
		vals.append(v)
		tc += Vector2(t.pos)
	tc /= float(ids.size())
	vals.sort()
	var top := -1
	var tv := -1.0
	for tid in ids:
		if float(thr[tid]) > tv:
			tv = float(thr[tid])
			top = int(tid)
	var med: float = float(vals[vals.size() / 2])
	var focus := -1
	if not sloppy and top >= 0 and (ids.size() == 1 or tv >= float(T.get("focus_ratio", 2.0)) * maxf(med, 0.0001)):
		focus = top
	var R: Dictionary = c.get("radio", {})
	if w.tick - int(rec.last_t) >= _ticks(float(R.get("contact_quiet_s", 8.0))):
		Radio71.say(w, "army71.contact_" + _dir_word(cen, tc, mem[0]), cen, int(mem[0].owner))
	rec.last_t = w.tick
	if focus >= 0 and focus != int(rec.focus) and ids.size() > 1:
		Radio71.say(w, "army71.shift_fire", cen, int(mem[0].owner))
	rec.focus = focus
	var fwd := tc - cen
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector2.RIGHT
	var S: Dictionary = c.get("sector", {})
	var n := mem.size()
	var assigned := {}
	var nopick: Array = []
	var SQ = _SQ()
	for i in n:
		var e: Dictionary = mem[i]
		var ot := String(e.order.get("type", "idle"))
		if ot != "idle" and ot != "hold" and ot != "attack_move":
			continue
		var s: Dictionary = Cm.stats(e)
		if String(s.weapon) == "":
			continue
		var fresh: bool = SQ.player_fresh(w, e)
		var rad: float = float(s.range) if (ot == "hold" or fresh) else maxf(float(s.sight), float(s.range))
		var arc := _arc(w, e, i, n, fwd, S)
		var pick := -1
		var psc := -1.0
		for tid in ids:
			var t: Dictionary = w.entities[tid]
			if not Cm.can_target(s, t):
				continue
			var d: float = Cm.dist_to(e.pos, t)
			if d > rad or d < float(s.min_range):
				continue
			var sc := float(thr[tid]) * Content.armor_mult(String(s.cls), String(Cm.stats(t).armor))
			if int(tid) == focus:
				sc *= 4.0
			elif not _in_arc(Vector2(e.pos), Vector2(t.pos), arc):
				sc *= float(S.get("painted_out_mult", 0.1)) if bool(arc[2]) else float(S.get("out_mult", 0.4))
			if float(assigned.get(tid, 0.0)) >= float(t.hp) * float(T.get("overkill", 1.3)):
				sc *= float(T.get("overkill_mult", 0.3))
			if sc > psc:
				psc = sc
				pick = int(tid)
		if pick >= 0:
			if int(e.target) != pick:
				e.target = pick
			assigned[pick] = float(assigned.get(pick, 0.0)) + float(Cm.shot_damage(e, w.entities[pick]))
		else:
			nopick.append(e)
	return nopick


## NCO bookkeeping: first think names the NCO; a missing NCO starts the loss clock; after step_up_s a survivor steps up.
static func _nco(w: SimWorld, rec: Dictionary, mem: Array, c: Dictionary) -> void:
	var nid := int(rec.nco)
	var alive := false
	for e in mem:
		if int(e.id) == nid:
			alive = true
			break
	if alive:
		return
	var nc: Dictionary = c.get("nco", {})
	if nid >= 0 and int(rec.lost) < 0:
		rec.lost = w.tick
		Radio71.say(w, "army71.nco_down", Vector2(mem[0].pos), int(mem[0].owner))
		return
	if nid < 0 or w.tick - int(rec.lost) >= _ticks(float(nc.get("step_up_s", 10.0))):
		var lid: int = _SQ().leader_of(w, mem.map(func(x): return int(x.id)))
		if lid < 0:
			return
		w.entities[lid].d71n = 1
		rec.nco = lid
		rec.lost = -1


static func _alive_enemy(w: SimWorld, e: Dictionary, tid: int):
	if tid < 0:
		return null
	var t = w.entities.get(tid)
	if t == null or int(t.owner) == int(e.owner) or float(t.get("hp", 0.0)) <= 0.0:
		return null
	return t


## Threat of t to the squad: its dps against the member it threatens most.
static func _threat_mem(w: SimWorld, t: Dictionary, mem: Array, T: Dictionary) -> float:
	var best := 0.0
	for e in mem:
		best = maxf(best, threat_of(w, e, t))
	var tg := int(t.get("target", -1))
	if tg >= 0:
		for e in mem:
			if int(e.id) == tg:
				best *= float(T.get("targets_us_mult", 1.5))
				break
	return best


static func threat_of(w: SimWorld, e: Dictionary, t: Dictionary) -> float:
	var Cm = _C()
	var ts: Dictionary = Cm.stats(t)
	if String(ts.weapon) == "" or not Cm.can_target(ts, e):
		return 0.0
	var v: float = float(Cm.shot_damage(t, e)) / maxf(float(ts.cooldown), 0.05)
	if Cm.dist_to(t.pos, e) <= float(ts.range):
		v *= float((cfg().get("threat", {}) as Dictionary).get("in_range_mult", 2.0))
	return v


## [centre angle, half width, painted] of member i's sector of fire: a painted KillZone71 sector, else the squad's
## own overlapping arcs (FIRES71's advisory auto zones are coarser than these and are not used).
static func _arc(w: SimWorld, e: Dictionary, i: int, n: int, fwd: Vector2, S: Dictionary) -> Array:
	var ps: Dictionary = KillZone71.sector_of(w, int(e.id)) if w.sys_state.has(KillZone71.KEY) else {}
	if not ps.is_empty() and not bool(ps.get("auto", false)):   # a painted sector binds; FIRES71's advisory auto zone does not
		return [float(ps.get("arc_c", 0.0)), float(ps.get("arc_w", PI)) * 0.5, true]
	var spread := deg_to_rad(float(S.get("spread_deg", 120.0)))
	var step := spread / float(maxi(n, 1))
	var a := fwd.angle() + (float(i) - float(n - 1) * 0.5) * step
	return [a, step * 0.5 * float(S.get("overlap", 1.5)), false]


static func _in_arc(p: Vector2, q: Vector2, arc: Array) -> bool:
	var d := q - p
	if d.length_squared() < 0.0001:
		return true
	return absf(angle_difference(float(arc[0]), d.angle())) <= float(arc[1])


static func _dir_word(cen: Vector2, tc: Vector2, e: Dictionary) -> String:
	var face := float(e.get("facing", 0.0))
	var a := angle_difference(face, (tc - cen).angle())
	if absf(a) <= PI * 0.25:
		return "front"
	if absf(a) >= PI * 0.75:
		return "rear"
	return "right" if a > 0.0 else "left"


# ================================================================ combat hooks

## Combat._pick (LP): a squad soldier keeps the target its squad gave it while it is valid in radius (cur != null).
static func keep(e: Dictionary, cur) -> bool:
	return cur != null and int(e.get("squad", -1)) >= 0 and e.has("d71m")


## Combat._fire (LP): magazine use for foot soldiers; returns the cooldown (a reload when the magazine runs out or a
## staggered tactical reload starts).
static func on_shot(w: SimWorld, e: Dictionary, s: Dictionary, cd: int) -> int:
	if e.kind != "unit" or int(e.get("squad", -1)) < 0:
		return cd
	var mg := _mag(e, s)
	if mg.is_empty():
		return cd
	var cap := int(mg[0])
	var M: Dictionary = cfg().get("mag", {})
	var tac := ceili(float(cap) * float(M.get("tactical_frac", 0.34)))
	var m := int(e.get("d71m", _first_mag(w, e, cap, tac)))
	m -= 1
	if m <= 0 or (m <= tac and may_reload(w, e)):
		var rt := _ticks(float(mg[1]) * SimWorld.Morale.reload_mult(e))
		e.d71m = cap
		e.d71r = w.tick + rt
		Radio71.say(w, "army71.reloading", Vector2(e.pos), int(e.owner))
		return maxi(cd, rt)
	e.d71m = m
	return cd


## First magazine: with an NCO the squad's thirds start a third of a magazine apart (id % 3), so their reloads never
## line up; without one every soldier starts full and they fire (and run dry) in step.
static func _first_mag(w: SimWorld, e: Dictionary, cap: int, tac: int) -> int:
	if nco_of(w, int(e.get("squad", -1))) < 0:
		return cap
	return cap - (int(e.id) % 3) * maxi(tac, 1)


## Staggered reloads (NCO alive): a soldier down to his last round holds it while the stagger cap of his squad is
## reloading, so his own reload starts only when a mate is back up (Combat._fire skips the shot, no draw).
static func hold_fire(w: SimWorld, e: Dictionary) -> bool:
	return int(e.get("d71m", 0)) == 1 and not may_reload(w, e) and nco_of(w, int(e.get("squad", -1))) >= 0


## [shots, reload s] for a foot soldier's weapon, or [] (no magazine model: the old cooldown cycle).
static func _mag(e: Dictionary, s: Dictionary) -> Array:
	var M: Dictionary = cfg().get("mag", {})
	var bw: Dictionary = M.get("by_weapon", {})
	var wid := String(s.get("weapon", ""))
	if bw.has(wid):
		return bw[wid]
	if int(_A8()._profile_of(e)[0]) != 0:   # Accuracy8.C_INF: foot soldiers only
		return []
	var bc: Dictionary = M.get("by_class", {})
	return bc.get(String(s.get("cls", "")), [])


static func may_reload(w: SimWorld, e: Dictionary) -> bool:
	var sq := int(e.get("squad", -1))
	var rec = _rec(w, sq)
	if rec == null:
		return true
	if int(rec.lost) >= 0 and not bool((cfg().get("nco", {}) as Dictionary).get("lost_stagger", false)):
		return false   # NCO down: nobody times a tactical reload (the squad fires dry, reloads bunch up)
	var lst = _SQ()._cache(w).squads.get(sq)
	if lst == null:
		return true
	var n := 0
	var rel := 0
	for id in lst:
		var o = w.entities.get(id)
		if o == null or int(o.get("squad", -1)) != sq:
			continue
		n += 1
		if int(o.get("d71r", 0)) > w.tick:
			rel += 1
	var frac := float((cfg().get("mag", {}) as Dictionary).get("max_reloading_frac", 0.34))
	return rel < maxi(floori(float(n) * frac), 1)


static func reloading(w: SimWorld, e: Dictionary) -> bool:
	return int(e.get("d71r", 0)) > w.tick


# ================================================================ queries (API)

static func squad_target(w: SimWorld, sid: int) -> int:
	var rec = _rec(w, sid)
	return -1 if rec == null else int(rec.focus)


static func nco_of(w: SimWorld, sid: int) -> int:
	var rec = _rec(w, sid)
	if rec == null or int(rec.lost) >= 0:
		return -1
	return int(rec.nco)


static func sloppy(w: SimWorld, e: Dictionary) -> float:
	var rec = _rec(w, int(e.get("squad", -1)))
	if rec == null or int(rec.lost) < 0:
		return 1.0
	return float((cfg().get("nco", {}) as Dictionary).get("lost_slot_mult", 1.6))


static func cover_pose(e: Dictionary) -> int:
	return int(e.get("d71c", 0))


## Read from the garrison clear drill (Garrison st.clears, phase stack: e.f7_clr 1), which stack_enter starts in LP.
static func stack_of(w: SimWorld, eid: int) -> Dictionary:
	if not w.sys_state.has(KEY):
		return {}
	var e = w.entities.get(eid)
	if e == null or int(e.get("f7_clr", 0)) != 1:
		return {}
	var gs = w.sys_state.get("garrison")
	if gs == null:
		return {}
	for c in gs.get("clears", []):
		if int(c.bid) == int(e.get("f7_bld", -1)):
			return {"bld": int(c.bid), "slot": (c.units as Array).find(int(eid)), "door": [float(c.door.x), float(c.door.y)]}
	return {}


static func signal_of(w: SimWorld, sid: int) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		return {}
	return (st.get("sig", {}) as Dictionary).get(str(sid), {})


# ================================================================ ARMY71-9 D4 writers (LP: called from SquadAI only when d71)

static var _gar = null


## Cover poses per member (e.d71c; erased = 0): 3 bound (a mover of the bounding team: f7_tech 2, no f7_bw), else
## in cover (Morale.cover_level >= 1, not garrisoned): 1 hug when reloading / suppressed >= cover.hug_supp / no target,
## 2 peek when it has a target (fires from cover); 0 in the open. Accuracy8 scales hits on a pose by pose_mult.
static func poses(w: SimWorld, mem: Array) -> void:
	var C: Dictionary = cfg().get("cover", {})
	var hs := float(C.get("hug_supp", 60.0))
	for e in mem:
		var p := 0
		if bool(e.get("moving", false)) and int(e.get("f7_tech", 0)) == 2 and not e.has("f7_bw"):   # 2 = bounding overwatch (Formations7.technique_for; gen 9 had 3, never set)
			p = 3
		elif int(e.get("garrisoned_in", -1)) < 0 and SimWorld.Morale.cover_level(w, e) >= 1:
			p = 2 if int(e.get("target", -1)) >= 0 else 1
			if int(e.get("d71r", 0)) > w.tick or float(e.get("supp", 0.0)) >= hs:
				p = 1
		if p == 0:
			if e.has("d71c"):
				e.erase("d71c")
		elif int(e.get("d71c", 0)) != p:
			e.d71c = p


## Hit chance mult on a soldier in pose p (Accuracy8.mult, LP only: no soldier carries d71c off LP).
static func pose_mult(p: int) -> float:
	var C: Dictionary = cfg().get("cover", {})
	match p:
		1:
			return float(C.get("hug_mult", 0.55))
		2:
			return float(C.get("peek_mult", 1.0))
		3:
			return float(C.get("bound_mult", 1.0))
	return 1.0


## Formation catch-up: while the leader moves, a moving member farther than catchup.dist from him sprints (SquadAI
## sets gait 3) to close up, instead of the squad waiting for him.
static func catchup(w: SimWorld, e: Dictionary, le: Dictionary) -> bool:
	if int(e.id) == int(le.id) or not bool(le.get("moving", false)) or not bool(e.get("moving", false)):
		return false
	var ot := String(e.order.get("type", ""))
	if ot != "move" and ot != "attack_move":
		return false
	var dd := float((cfg().get("catchup", {}) as Dictionary).get("dist", 3.0))
	return Vector2(e.pos).distance_squared_to(Vector2(le.pos)) > dd * dd


## Door stacking: members of one squad ordered into the same building of ours (>= 2, still > stack.min_dist tiles from
## it, none in a drill yet) stack on its door first: Garrison.clear_building (phase stack -> clear -> enter garrisons
## them). Buildings in ascending id order.
static func stack_enter(w: SimWorld, mem: Array) -> void:
	var K: Dictionary = cfg().get("stack", {})
	if not bool(K.get("on_enter", true)):
		return
	var by := {}
	for e in mem:
		if String(e.order.get("type", "")) != "garrison" or e.has("f7_clr"):
			continue
		var bid := int(e.order.get("building_id", -1))
		var b = w.entities.get(bid)
		if b == null or b.kind != "building" or int(b.owner) != int(e.owner):
			continue
		var bc := Vector2(b.cell) + Vector2(float(b.size), float(b.size)) * 0.5
		if Vector2(e.pos).distance_to(bc) <= float(b.size) * 0.5 + float(K.get("min_dist", 2.5)):
			continue
		if not by.has(bid):
			by[bid] = []
		by[bid].append(int(e.id))
	if by.is_empty():
		return
	if _gar == null:
		_gar = load("res://sim/systems/garrison.gd")
	var bids: Array = by.keys()
	bids.sort()
	for bid in bids:
		if (by[bid] as Array).size() >= 2:
			_gar.clear_building(w, int(mem[0].owner), by[bid], int(bid))
