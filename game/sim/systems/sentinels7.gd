extends RefCounted
## Sentinels7 (owner: SENT7). G7_REFERENCE 13.9c-10 (Sentinels: the counter-nanite facility's guard force) and
## 13.9c-11 (sidearm + ready-ammo lockers + Sentinel Ammo Bearer; watch structure). Content:
## content/g7/defs_g7_sentinels.json (units with def.sentinel = type key, rules.g7_sentinels). Every number PROVISIONAL.
##  - Seven types (warden, marksman, gunner, bulwark, lancer, arc, mender) + the ammo bearer, Human A and Human B.
##    Trained only at the Sentinel Barracks (cn_sentinel_barracks, a facility part FACB7 places). No chain of command:
##    on spawn e.squad = -1 and no rank_role (def.no_command), so Companies / CommandNet / SquadAI never lead them.
##  - Garrison caps (Garrison.slots_of / admits read rules.g7_sentinels.posts / post_only): tower 4, foot entry 15,
##    barracks 120, Sentinels only.
##  - Self-heal (tick): regen out of combat (no hit for quiet_s, not suppressed, not EMP'd / jammed), faster inside
##    the facility zone; a punctured suit reseals. Sealed suit (e.suit) = no creep exposure while the armour is up;
##    an EMP drops it.
##  - Defence bonus (damage_mult, via the G6Hooks dispatcher): x defence_mult inside an own facility zone (compound
##    + zone_pad, e.s7_z refreshed every zone_every ticks) or garrisoned in a Sentinel post; Bulwark shield; EMP'd
##    armour takes x emp_mult and loses the bonus. Shooter side: x anti_nanite_mult vs Machine units (disruptor
##    rounds), sidearm x dmg_mult; range_mult: sidearm x range_mult.
##  - Ammo (13.9c-11): primary empty -> sidearm (e.s7_sa, sidearm rounds); sidearm empty -> nearest stocked ready-ammo
##    locker (cn_ammo_locker), take one load, short reload, back to the job. Bearers restock Sentinels where they
##    stand and refill lockers, refilling themselves at the barracks / magazine.
##  - Starting garrison: when a facility is raised, its owner gets rules.start (entry booth, tower pairs, wall-walk
##    pairs, interior patrol pairs, a quick reaction force). Patrols walk deterministic loops (staggered thinking);
##    on alarm (BaseState7 not secure) patrol pairs and the QRF move on the threat. A fresh player order frees a unit
##    from its job (it is never pulled back while the player owns it).
## State (saved, hashed): w.sys_state.sent7 = {ver, seeded [fac ids], ids [uid], lockers {"bid": stock}, jobs
## {"uid": job}}; created only when a facility with Sentinels exists or a Sentinel is trained. No facility and no
## Sentinel: tick returns after one dictionary lookup and every hook is neutral (one has() per hit).
## Public API (facts sent7.api): is_sentinel, damage_mult, range_mult, locker_stock, locker_add, lockers_of,
## repair_part, seed_facility, sentinels_of.

const KEY := "sent7"
const VER := 1

static var _mv = null
static var _gar = null
static var _cf = null
static var _a7 = null


static func _movement():
	if _mv == null:
		_mv = load("res://sim/systems/movement.gd")
	return _mv


static func _garrison():
	if _gar == null:
		_gar = load("res://sim/systems/garrison.gd")
	return _gar


static func _cnfac():
	if _cf == null:
		_cf = load("res://sim/systems/cn_facility.gd")
	return _cf


static func _apc7():
	if _a7 == null:
		_a7 = load("res://sim/systems/apc7.gd")
	return _a7


static func R() -> Dictionary:
	return Content.rules().get("g7_sentinels", {})


static func ticks(sec: float) -> int:
	return maxi(roundi(sec * SimWorld.TICK_RATE), 1)


static func state(w: SimWorld):
	return w.sys_state.get(KEY)


static func _st(w: SimWorld) -> Dictionary:
	var S = w.sys_state.get(KEY)
	if S == null:
		S = {"ver": VER, "seeded": [], "ids": [], "lockers": {}, "jobs": {}, "board": {}}
		w.sys_state[KEY] = S
	return S


## Sentinel type key of a unit def ("" = not a Sentinel).
static func type_of_def(def_id: String) -> String:
	return String(Content.unit(def_id).get("sentinel", ""))


static func is_sentinel(e) -> bool:
	return e is Dictionary and e.has("s7")


## Live Sentinels of side fid (ascending ids).
static func sentinels_of(w: SimWorld, fid: int) -> Array:
	var out := []
	var S = state(w)
	if S == null:
		return out
	for id in S.ids:
		var e = w.entities.get(int(id))
		if e != null and int(e.owner) == fid:
			out.append(int(id))
	return out


# ================================================================ G6Hooks delegates (neutral without Sentinels)
## Target-side and shooter-side damage factor (G6Hooks.damage_mult).
static func damage_mult(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	var m := 1.0
	if src.has("s7"):
		if bool(src.get("s7_sa", false)):
			m *= float(R().get("sidearm", {}).get("dmg_mult", 0.45))
		if t.kind == "unit" and (R().get("machine_factions", ["machine"]) as Array).has(String(Content.unit(String(t.def)).get("faction", ""))):
			m *= float(R().get("anti_nanite_mult", 1.0))
	if t.has("s7"):
		var r := R()
		# SENT7-4 13.9c-10/-13 "anti-armour / artillery still kill them": the slim nanotech armour and the Bulwark's
		# nanoweave shield stop small arms, fragments and nanite; an anti-tank round or a shell (weapon class in
		# heavy_classes) is not reduced by them (cover and the wall parapet still count, WallWalk7 / terrain).
		var heavy := (r.get("heavy_classes", []) as Array).has(String(s.get("cls", s.get("class", ""))))
		if int(t.get("emp_until", -1)) >= w.tick or int(t.get("jammed_until", -1)) >= w.tick:
			m *= float(r.get("emp_mult", 1.0))
		elif bool(t.get("s7_z", false)) or t.has("garrisoned_in"):
			m *= float(r.get("heavy_defence_mult", 1.0)) if heavy else float(r.get("defence_mult", 1.0))
		if not heavy and (r.get("shield_types", []) as Array).has(String(t.s7)):
			m *= float(r.get("shield_mult", 1.0))
	return m


## Shooter-side range factor (G6Hooks.range_mult): the sidearm reaches less far.
static func range_mult(_w: SimWorld, src: Dictionary, _s: Dictionary) -> float:
	if src.has("s7") and bool(src.get("s7_sa", false)):
		return float(R().get("sidearm", {}).get("range_mult", 1.0))
	return 1.0


# ================================================================ lockers + repair API (Facility Engineer, bearers)
## Stock (loads) of ready-ammo locker bid; -1 when bid is not a locker.
static func locker_stock(w: SimWorld, bid: int) -> int:
	var b = w.entities.get(bid)
	if b == null or b.kind != "building" or not bool(Content.building(String(b.def)).get("s7_locker", false)):
		return -1
	var S = state(w)
	if S == null or not S.lockers.has(str(bid)):
		return int(R().get("locker", {}).get("stock", 0))
	return int(S.lockers[str(bid)])


## Adds n loads (negative takes) to locker bid, clamped to 0..cap; returns the change actually made.
static func locker_add(w: SimWorld, bid: int, n: int) -> int:
	var cur := locker_stock(w, bid)
	if cur < 0:
		return 0
	var cap := int(R().get("locker", {}).get("cap", 14))
	var nv := clampi(cur + n, 0, cap)
	_st(w).lockers[str(bid)] = nv
	return nv - cur


## Ready-ammo lockers of side fid (ascending ids).
static func lockers_of(w: SimWorld, fid: int) -> Array:
	var out := []
	for b in w.entities.values():
		if b.kind == "building" and int(b.owner) == fid and bool(Content.building(String(b.def)).get("s7_locker", false)):
			out.append(int(b.id))
	out.sort()
	return out


## Repairs building bid by hp (up to max_hp); returns the hp restored. Used by Menders and the Facility Engineer.
static func repair_part(w: SimWorld, bid: int, hp: float) -> float:
	var b = w.entities.get(bid)
	if b == null or b.kind != "building" or hp <= 0.0:
		return 0.0
	var before := float(b.hp)
	b.hp = minf(float(b.max_hp), before + hp)
	return float(b.hp) - before


# ================================================================ enlisting + starting garrison
## Def-id prefix of side fid's Sentinels ("" = no Sentinels for that faction).
static func prefix(w: SimWorld, fid: int) -> String:
	if not w.factions.has(fid):
		return ""
	match String(w.factions[fid].get("faction_def", "")):
		"human_a":
			return "g7_sent_"
		"human_b":
			return "g7_b_sent_"
	return ""


## Makes unit e a Sentinel under job (no squad, no leader; sealed armour).
static func enlist(w: SimWorld, e: Dictionary, job: Dictionary) -> void:
	var S := _st(w)
	e.s7 = type_of_def(String(e.def))
	e.squad = -1
	e.erase("rank_role")
	e.suit = true
	var id := int(e.id)
	if not (S.ids as Array).has(id):
		S.ids.append(id)
		S.ids.sort()
	S.jobs[str(id)] = job


static func _spawn(w: SimWorld, fid: int, kind: String, at: Vector2, job: Dictionary) -> int:
	var def_id := prefix(w, fid) + kind
	if Content.unit(def_id).is_empty():
		return -1
	var mv = _movement()
	var c: Vector2i = w.cell_of(at)
	if not mv.is_passable(w, c, "foot", _team(w, fid)):
		c = mv.nearest_free_cell(w, c, "foot", _team(w, fid))
		at = Vector2(c) + Vector2(0.5, 0.5)
	var uid := w.spawn_unit(def_id, fid, at)
	var e: Dictionary = w.entities[uid]
	e.order = {"type": "idle"}
	enlist(w, e, job)
	return uid


static func _team(w: SimWorld, fid: int) -> int:
	var f = w.factions.get(fid)
	return int(f.get("team", fid)) if f != null else fid


static func _loc(F: Dictionary, x: float, y: float) -> Vector2:
	return Vector2(float(F.origin[0]) + x, float(F.origin[1]) + y)


static func _parts_of(w: SimWorld, F: Dictionary, def_id: String) -> Array:
	var out := []
	for pid in F.get("parts", []):
		var b = w.entities.get(int(pid))
		if b != null and String(b.def) == def_id:
			out.append(b)
	return out


static func _post_job(kind: String, fac: int, bid: int) -> Dictionary:
	return {"k": kind, "fac": fac, "bid": bid, "in": false}


static func _route_job(fac: int, route: Array, wp: int, dirn: int, off: Vector2) -> Dictionary:
	return {"k": "patrol", "fac": fac, "route": route, "wp": wp, "dir": dirn, "ox": off.x, "oy": off.y}


## The starting Sentinel garrison of a raised facility F (rules.start.force: the type mix), mustered at the barracks /
## ready room, then put straight onto the job board's posts: entry booth and tower posts garrisoned, wall-walk and
## interior patrol pairs at their route starts, the rest in the barracks (quick reaction force / off-duty roster).
static func seed_facility(w: SimWorld, F: Dictionary) -> Array:
	var fid := int(F.owner)
	var fac := int(F.id)
	var S := _st(w)
	if (S.seeded as Array).has(fac):
		return []
	S.seeded.append(fac)
	S.seeded.sort()
	var out := []
	if prefix(w, fid) == "":
		return out
	var home := _home(w, F)
	for k in R().get("start", {}).get("force", []):
		var uid := _spawn(w, fid, String(k), home, {"k": "auto", "fac": fac})
		if uid >= 0:
			out.append(uid)
	plan(w, F)
	var G = _garrison()
	for uid in out:
		var e: Dictionary = w.entities[uid]
		var job: Dictionary = S.jobs[str(uid)]
		match String(job.k):
			"post", "entry", "rest":
				if int(job.get("bid", -1)) >= 0 and G.place_inside(w, int(job.bid), uid) == "":
					job["in"] = true
			"wall", "int":
				var p: Vector2 = Vector2(job.route[int(job.wp)]) + Vector2(float(job.get("ox", 0.0)), float(job.get("oy", 0.0)))
				var c: Vector2i = w.cell_of(p)
				if not _movement().is_passable(w, c, "foot", _team(w, fid)):
					c = _movement().nearest_free_cell(w, c, "foot", _team(w, fid))
				SimWorld.HotState.set_pos(w, uid, Vector2(c) + Vector2(0.5, 0.5))
	w.emit("SentinelsMustered", {"fac": fac, "owner": fid, "units": out.duplicate()})
	return out


static func _home(w: SimWorld, F: Dictionary) -> Vector2:
	var bk := _parts_of(w, F, "cn_sentinel_barracks")
	if not bk.is_empty():
		return _bpos(bk[0]) + Vector2(0.0, float(bk[0].get("size", 2)) * 0.5 + 0.6)
	var rr: Rect2 = _cnfac().zone(F, "ready_room")
	var cs := float(_cnfac().conf().get("compound", 28))
	return rr.get_center() if rr.size.x > 0.0 else _loc(F, cs * 0.5, cs * 0.5)


# ================================================================ facility job board (13.9c-12)
## One board per facility, re-planned every plan_every ticks (staggered by facility id): S.board["<fac>"] =
## {at, shift, jobs: [job]}; job = {id, kind, pos, prio, roles ["*" | type key | worker role], slots, bid, route,
## loop, taken [uid]}. The most urgent job (prio desc, id asc) takes its previous holders first (until the shift
## changes), then the nearest fit free unit (distance + duty fatigue). Units left over rest in the barracks.
## Workers of other agents (Facility Engineer: add_worker) are planned on the same board and run their own jobs
## (job_of). External jobs: post_job / done_job.
static func _job(id: String, kind: String, pos: Vector2, prio: float, roles: Array, slots: int, bid: int = -1) -> Dictionary:
	return {"id": id, "kind": kind, "pos": pos, "prio": prio, "roles": roles, "slots": slots, "bid": bid, "taken": []}


static func _jobs_for(w: SimWorld, S: Dictionary, F: Dictionary) -> Array:
	var P: Dictionary = R().get("plan", {})
	var fac := int(F.id)
	var fid := int(F.owner)
	var cs := float(_cnfac().conf().get("compound", 28))
	var th = threat(w, fac)
	var alarm := th != null
	var guards := ["warden", "marksman", "gunner", "bulwark", "lancer", "arc", "mender"]
	var jobs := []
	var cp = w.entities.get(int(F.get("cp", 0)))
	if cp != null:
		jobs.append(_job("entry", "entry", _bpos(cp), 5.0, ["bulwark", "warden", "marksman", "gunner", "lancer"], int(P.get("entry", 4)), int(cp.id)))
	var gc: Vector2 = _cnfac().zone(F, "gate_outer").get_center()
	var towers := _parts_of(w, F, "cn_tower")
	towers.sort_custom(func(a, b) -> bool:
		var da := Vector2(a.cell).distance_squared_to(gc)
		var db := Vector2(b.cell).distance_squared_to(gc)
		return da < db if da != db else int(a.id) < int(b.id))
	var nt := int(P.get("towers_alarm", 6)) if alarm else int(P.get("towers", 3))
	for i in mini(nt, towers.size()):
		var t: Dictionary = towers[i]
		jobs.append(_job("tower:%d" % int(t.id), "post", _bpos(t), 4.0, ["marksman", "gunner", "lancer", "warden"], int(P.get("per_tower", 2)), int(t.id)))
	var walls := _wall_routes(F)
	for i in walls.size():
		var j := _job("wall:%d" % i, "wall", walls[i][1], 3.0, ["warden", "gunner", "lancer", "marksman", "arc"], 2)
		j["route"] = walls[i]
		j["ck"] = [0, 2]   # check in at the towers at both ends of the run
		jobs.append(j)
	var a0 := 4.5
	var a1 := cs - 5.5
	var base := [_loc(F, a0, a0), _loc(F, a1, a0), _loc(F, a1, a1), _loc(F, a0, a1)]
	var loop := _with_blind(w, F, base)   # 13.9c-11: the interior loop also walks the cameras' blind spots
	var flip := 1 if (w.tick / ticks(float(P.get("shift_s", 240.0)))) % 2 == 0 else -1   # direction varies by shift
	for i in 2:
		var j := _job("int:%d" % i, "int", base[i * 2], 2.0, guards, 2)
		j["route"] = loop
		j["loop"] = true
		j["start"] = maxi(loop.find(base[i * 2]), 0)
		j["dir"] = (1 if i == 0 else -1) * flip
		jobs.append(j)
	var bk := _parts_of(w, F, "cn_sentinel_barracks")
	var qj := _job("qrf", "qrf", th[0] if alarm else _home(w, F), 6.0 if alarm else 1.0, guards, int(P.get("qrf", 4)), int(bk[0].id) if not bk.is_empty() else -1)
	jobs.append(qj)
	# resupply, locker refills, repairs
	var low := float(R().get("bearer", {}).get("low_frac", 0.5))
	for id in S.ids:
		var u = w.entities.get(int(id))
		if u == null or int(u.owner) != fid or String(u.s7) == "bearer" or not u.has("ammo"):
			continue
		var am := float(Content.unit(String(u.def)).get("ammo_max", 0))
		if bool(u.get("s7_sa", false)) or float(u.ammo) < low * am:
			var urg := 1.0 - float(u.ammo) / maxf(am, 1.0) + (1.0 if bool(u.get("s7_sa", false)) else 0.0)
			var rj := _job("restock:%d" % int(id), "restock", Vector2(u.pos), 3.0 + urg, ["bearer"], 1)
			rj["uid"] = int(id)
			jobs.append(rj)
	# 13.9c-13 casualty drill: the Mender comes forward to every Sentinel that is down
	var Wd = SimWorld.Wounds
	var zc: Rect2 = _cnfac().compound_rect(F).grow(float(R().get("zone_pad", 6)) + 4.0)
	for id in S.ids:
		var u = w.entities.get(int(id))
		if u != null and int(u.owner) == fid and Wd.is_down(u) and not u.has("evac_by") and zc.has_point(u.pos):
			var cj := _job("cas:%d" % int(id), "casualty", Vector2(u.pos), float(_tac().get("cas_prio", 7.0)), ["mender"], 1)
			cj["uid"] = int(id)
			jobs.append(cj)
	var cap := int(R().get("locker", {}).get("cap", 14))
	for lid in lockers_of(w, fid):
		var stk := locker_stock(w, lid)
		if stk < cap / 2:
			jobs.append(_job("locker:%d" % lid, "locker", _bpos(w.entities[lid]), 2.0 + 1.0 - float(stk) / float(cap), ["bearer", "engineer"], 1, lid))   # ENG7 (13.9c-11): engineers refill lockers by forklift
	for pid in F.parts:
		var b = w.entities.get(int(pid))
		if b != null and float(b.hp) < float(P.get("repair_below", 0.9)) * float(b.max_hp):
			jobs.append(_job("repair:%d" % int(pid), "repair", _bpos(b), 1.0 + 3.0 * (1.0 - float(b.hp) / maxf(float(b.max_hp), 1.0)), ["mender", "engineer"], 1, int(pid)))
	var ext: Dictionary = S.get("ext", {}).get(str(fac), {})
	var ek := ext.keys()
	ek.sort()
	for k in ek:
		var x: Dictionary = ext[k]
		if int(x.get("until", 1 << 60)) < w.tick:
			ext.erase(k)
			continue
		var j := x.duplicate(true)
		j["taken"] = []
		jobs.append(j)
	jobs.sort_custom(func(a, b) -> bool: return float(a.prio) > float(b.prio) if float(a.prio) != float(b.prio) else String(a.id) < String(b.id))
	return jobs


## Role of an automatic unit on the board ("" = not plannable now: player-owned, on an ammo run, manual).
static func _role(w: SimWorld, S: Dictionary, uid: int) -> String:
	var job: Dictionary = S.jobs.get(str(uid), {})
	var k := String(job.get("k", "free"))
	if k == "free" or k == "player" or k == "ammo" or bool(job.get("wd", false)):
		return ""   # withdrawing by bounds: finishes the withdrawal before it is re-planned
	if S.get("workers", {}).has(str(uid)):
		return String(S.workers[str(uid)])
	var e = w.entities.get(uid)
	return String(e.s7) if e != null and e.has("s7") else ""


## Re-plans facility F's board and hands every automatic unit of its owner a job (or rest). 13.9c-12: score =
## distance + duty fatigue + creep exposure; wounded / just-withdrawn units rest; under alarm every off-duty Sentinel
## goes to its own pre-assigned stand-to position. Two holders of one job are a buddy pair (record "bud").
static func plan(w: SimWorld, F: Dictionary) -> void:
	var S := _st(w)
	if not S.has("board"):
		S["board"] = {}
	var P: Dictionary = R().get("plan", {})
	var T := _tac()
	var fac := int(F.id)
	var fid := int(F.owner)
	var key := str(fac)
	var old: Dictionary = S.board.get(key, {"at": -1, "shift": 0, "jobs": []})
	var shift := w.tick / ticks(float(P.get("shift_s", 240.0)))
	var alarm := threat(w, fac) != null
	var keep_old := shift == int(old.get("shift", 0)) or alarm
	var jobs := _jobs_for(w, S, F)
	var cands := []
	var ids: Array = (S.ids as Array).duplicate()
	for k in S.get("workers", {}):
		ids.append(int(k))
	ids.sort()
	var Wd = SimWorld.Wounds
	for uid in ids:
		var e = w.entities.get(int(uid))
		if e == null or int(e.owner) != fid or _role(w, S, int(uid)) == "" or Wd.is_down(e):
			continue
		var jf := int(S.jobs.get(str(uid), {}).get("fac", -1))
		if jf >= 0 and jf != fac:
			continue
		var pb = w.entities.get(int(S.jobs.get(str(uid), {}).get("bud", -1)))
		if pb != null and Wd.is_down(pb) and not pb.has("evac_by") and Wd._needs_care(pb):
			continue   # casualty drill: he stays with his downed buddy (keeps the job and the pair) until he is cared for
		cands.append(int(uid))
	var used := {}
	var dw := float(P.get("duty_w", 4.0))
	var xw := float(T.get("exp_w", 3.0))
	for j in jobs:
		var roles: Array = j.roles
		var care := String(j.kind) == "repair" or String(j.kind) == "restock" or String(j.kind) == "casualty"
		if keep_old:
			for uid in cands:
				if used.has(uid) or (j.taken as Array).size() >= int(j.slots):
					continue
				var cur: Dictionary = S.jobs.get(str(uid), {})
				if String(cur.get("j", "")) == String(j.id) and _fits(roles, _role(w, S, uid)) and (care or not _unfit(w, w.entities[uid], P)):
					j.taken.append(uid)
					used[uid] = true
		while (j.taken as Array).size() < int(j.slots):
			var best := -1
			var bs := INF
			for uid in cands:
				if used.has(uid) or not _fits(roles, _role(w, S, uid)):
					continue
				var e: Dictionary = w.entities[uid]
				if not care and _unfit(w, e, P):
					continue   # wounded / just withdrawn: rests (barracks / Mender) instead of taking a post
				var sc := Vector2(e.pos).distance_to(j.pos) + dw * float(e.get("s7_duty", 0)) / float(SimWorld.TICK_RATE * 60) \
					+ xw * clampf(float(e.get("cn_exp", 0.0)), 0.0, 1.0)
				if sc < bs:
					bs = sc
					best = uid
			if best < 0:
				break
			j.taken.append(best)
			used[best] = true
	var bk := _parts_of(w, F, "cn_sentinel_barracks")
	var rest := _job("rest", "rest", _home(w, F), 0.0, ["*"], 9999, int(bk[0].id) if not bk.is_empty() else -1)
	var pts := _standto_pts(F) if alarm else []
	for uid in cands:
		if used.has(uid):
			continue
		var role := _role(w, S, uid)
		if not pts.is_empty() and role != "bearer" and role != "engineer" and role != "mender" and not _unfit(w, w.entities[uid], P):
			var idx := maxi((S.ids as Array).find(uid), 0)
			var sj := _job("standto:%d" % uid, "standto", pts[idx % pts.size()], 0.5, ["*"], 1)
			sj.taken.append(uid)
			jobs.append(sj)
		else:
			rest.taken.append(uid)
	jobs.append(rest)
	var dt := int(P.get("every", 100))
	for j in jobs:
		var tk: Array = j.taken
		var pair := String(j.kind) != "rest" and String(j.kind) != "standto" and int(j.slots) >= 2
		var buds := _pairs(S, tk, String(j.id)) if pair else {}
		for i in tk.size():
			var uid := int(tk[i])
			_assign(w, S, uid, j, fac)
			S.jobs[str(uid)]["bud"] = int(buds.get(uid, -1))
			var e: Dictionary = w.entities[uid]
			if String(j.kind) == "rest":
				e.s7_duty = maxi(0, int(e.get("s7_duty", 0)) - 2 * dt)
			else:
				e.s7_duty = int(e.get("s7_duty", 0)) + dt
	S.board[key] = {"at": w.tick, "shift": shift, "jobs": jobs}


## Buddy pairs among the holders tk of job jid: two men who were already a pair on this job stay together (a pair is
## a fixed team, not re-dealt every plan); the rest pair up in holder order. {uid: buddy uid}.
static func _pairs(S: Dictionary, tk: Array, jid: String) -> Dictionary:
	var out := {}
	var rest := []
	for u in tk:
		var uid := int(u)
		if out.has(uid):
			continue
		var oj: Dictionary = S.jobs.get(str(uid), {})
		var pb := int(oj.get("bud", -1))
		var pj: Dictionary = S.jobs.get(str(pb), {})
		if pb >= 0 and not out.has(pb) and tk.has(pb) and String(oj.get("j", "")) == jid and String(pj.get("j", "")) == jid 				and int(pj.get("bud", -1)) == uid:
			out[uid] = pb
			out[pb] = uid
		else:
			rest.append(uid)
	for i in range(0, rest.size() - 1, 2):
		out[int(rest[i])] = int(rest[i + 1])
		out[int(rest[i + 1])] = int(rest[i])
	return out


static func _unfit(w: SimWorld, e: Dictionary, P: Dictionary) -> bool:
	return float(e.hp) < float(P.get("wounded_frac", 0.35)) * float(e.max_hp) or int(e.get("s7_wd", -1)) > w.tick


## The three wall-walk runs (north, east, west faces) of facility F: [start, middle, end] each.
static func _wall_routes(F: Dictionary) -> Array:
	var cs := float(_cnfac().conf().get("compound", 28))
	return [[_loc(F, 1.0, 1.0), _loc(F, cs * 0.5, 1.0), _loc(F, cs - 1.0, 1.0)],
		[_loc(F, cs - 1.0, 1.0), _loc(F, cs - 1.0, cs * 0.5), _loc(F, cs - 1.0, cs - 3.0)],
		[_loc(F, 1.0, cs - 3.0), _loc(F, 1.0, cs * 0.5), _loc(F, 1.0, 1.0)]]


## Stand-to positions (alarm drill): evenly spaced along the wall-walk runs; unit i of the roster always gets point
## i % n (pre-assigned, so every Sentinel knows where it goes).
static func _stand_pt(r: Array, t: float) -> Vector2:
	return Vector2(r[0]).lerp(r[1], t * 2.0) if t < 0.5 else Vector2(r[1]).lerp(r[2], (t - 0.5) * 2.0)


static func _standto_pts(F: Dictionary) -> Array:
	var out := []
	for r in _wall_routes(F):
		for t in [0.2, 0.4, 0.6, 0.8]:
			out.append(_stand_pt(r, t))
	return out


## The interior loop with the cameras' blind spots spliced in (cells on a 4-tile grid of the compound that no camera
## or tower part of F sees; at most 4, each inserted after the loop corner nearest to it).
static func _with_blind(w: SimWorld, F: Dictionary, base: Array) -> Array:
	var cs := float(_cnfac().conf().get("compound", 28))
	var eyes := []
	for pid in F.get("parts", []):
		var b = w.entities.get(int(pid))
		if b == null:
			continue
		var d := String(b.def)
		if d.contains("camera") or d == "cn_tower":
			eyes.append([_bpos(b), float(Content.building(d).get("sight", 8.0)) * 0.8])
	var blind := []
	var mv = _movement()
	var team := _team(w, int(F.owner))
	var y := 6.5
	while y < cs - 5.0 and blind.size() < 4:
		var x := 6.5
		while x < cs - 5.0 and blind.size() < 4:
			var p := _loc(F, x, y)
			var seen := false
			for ey in eyes:
				if p.distance_to(ey[0]) <= float(ey[1]):
					seen = true
					break
			if not seen and mv.is_passable(w, w.cell_of(p), "foot", team):
				blind.append(p)
			x += 4.0
		y += 4.0
	if blind.is_empty():
		return base
	var after := {}
	for p in blind:
		var bi := 0
		for i in base.size():
			if Vector2(base[i]).distance_squared_to(p) < Vector2(base[bi]).distance_squared_to(p):
				bi = i
		if not after.has(bi):
			after[bi] = []
		after[bi].append(p)
	var out := []
	for i in base.size():
		out.append(base[i])
		for p in after.get(i, []):
			out.append(p)
	return out


static func _fits(roles: Array, role: String) -> bool:
	return role != "" and (roles.has(role) or (roles.has("*") and role != "bearer" and role != "engineer"))


## Writes unit uid's execution record for board job j (kept as is when it already holds j: route progress stays).
static func _assign(w: SimWorld, S: Dictionary, uid: int, j: Dictionary, fac: int) -> void:
	var cur: Dictionary = S.jobs.get(str(uid), {})
	if String(cur.get("j", "")) == String(j.id) and String(cur.get("k", "")) == String(j.kind):
		cur["pos"] = j.pos
		return
	var r := {"k": String(j.kind), "j": String(j.id), "fac": fac, "bid": int(j.get("bid", -1)), "pos": j.pos, "in": false}
	var ok := String(cur.get("k", "free"))
	if ok != "free" and ok != "player" and not cur.is_empty():
		r["hand"] = true   # the unit's current order / post came from this system (see _think)
	if j.has("uid"):
		r["uid"] = int(j.uid)
	if j.has("route"):
		var route: Array = j.route
		var e: Dictionary = w.entities[uid]
		var wp := int(j.get("start", 0))
		var bd := INF
		for i in route.size():
			var d := Vector2(e.pos).distance_squared_to(route[i])
			if d < bd:
				bd = d
				wp = i
		r["route"] = route
		r["loop"] = bool(j.get("loop", false))
		r["wp"] = wp
		r["dir"] = int(j.get("dir", 1))
		r["ck"] = (j.get("ck", []) as Array).duplicate()
		var n := (j.taken as Array).find(uid)
		r["ox"] = 0.0 if n <= 0 else 0.45
		r["oy"] = 0.0 if n <= 0 else 0.45
	S.jobs[str(uid)] = r


## ---- board API (ENG7 Facility Engineer and others): see fact facility.job_board
static func job_board(w: SimWorld, fac: int) -> Array:
	var S = state(w)
	return (S.board.get(str(fac), {}).get("jobs", []) as Array).duplicate(true) if S != null else []


static func job_of(w: SimWorld, uid: int) -> Dictionary:
	var S = state(w)
	return (S.jobs.get(str(uid), {}) as Dictionary).duplicate(true) if S != null else {}


## External job on facility fac's board (kind, pos, prio, roles, slots, bid, ttl_s); returns its id.
static func post_job(w: SimWorld, fac: int, job: Dictionary) -> String:
	var S := _st(w)
	if not S.has("ext"):
		S["ext"] = {}
	if not S.ext.has(str(fac)):
		S.ext[str(fac)] = {}
	var id := String(job.get("id", "%s:%d" % [String(job.get("kind", "ext")), int(job.get("bid", w.tick))]))
	var j := _job(id, String(job.get("kind", "ext")), Vector2(job.get("pos", Vector2.ZERO)), float(job.get("prio", 1.0)), job.get("roles", ["engineer"]), int(job.get("slots", 1)), int(job.get("bid", -1)))
	if job.has("ttl_s"):
		j["until"] = w.tick + ticks(float(job.ttl_s))
	S.ext[str(fac)][id] = j
	return id


static func done_job(w: SimWorld, fac: int, jid: String) -> void:
	var S = state(w)
	if S != null and S.has("ext") and S.ext.has(str(fac)):
		S.ext[str(fac)].erase(jid)


## Adds a non-Sentinel worker (e.g. Facility Engineer, role "engineer") to the board of facility fac.
## Sets worker uid's execution record (ENG7: instead of writing state(w).jobs directly); {} frees it to the planner.
static func set_worker_job(w: SimWorld, uid: int, job: Dictionary) -> void:
	var S := _st(w)
	S.jobs[str(uid)] = job.duplicate(true) if not job.is_empty() else {"k": "auto", "fac": int(S.jobs.get(str(uid), {}).get("fac", -1))}


static func add_worker(w: SimWorld, uid: int, role: String, fac: int) -> void:
	var S := _st(w)
	if not S.has("workers"):
		S["workers"] = {}
	S.workers[str(uid)] = role
	S.jobs[str(uid)] = {"k": "auto", "fac": fac}


# ================================================================ system
static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "Unknown Sentinel command."


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass


static func tick(w: SimWorld) -> void:
	var S = w.sys_state.get(KEY)
	var cn = w.sys_state.get("cn_facility")
	if S == null and cn == null:
		return
	if cn != null:
		if w.tick % 10 == 3:
			var ks := []
			for k in cn.facs:
				ks.append(int(k))
			ks.sort()
			for k in ks:
				if S == null or not (S.seeded as Array).has(k):
					seed_facility(w, cn.facs[str(k)])
					S = state(w)
		_enlist_trained(w)
		S = state(w)
	if S == null or (S.ids as Array).is_empty():
		return
	var r := R()
	var rg: Dictionary = r.get("regen", {})
	var every := int(rg.get("every", 10))
	var zone_t := w.tick % int(r.get("zone_every", 20)) == 0
	var zones := _zones(w) if zone_t else []
	var think := int(r.get("think_every", 20))
	var keep := []
	var dirty := false
	for id in S.ids:
		var e = w.entities.get(int(id))
		if e == null or e.kind != "unit":
			dirty = true
			S.jobs.erase(str(id))
			continue
		keep.append(int(id))
		if zone_t:
			var z := _in_zone(zones, e)
			if bool(e.get("s7_z", false)) != z:
				e.s7_z = z
		if w.tick % every == 0:
			_vitals(w, e, rg, every)
			var dn := SimWorld.Wounds.is_down(e)
			if dn != e.has("s7_dn"):   # "man down!": the board re-plans at once so the nearest Mender comes forward
				if dn:
					e.s7_dn = 1
					S["call"] = true
					w.emit("SentinelManDown", {"id": int(id), "owner": int(e.owner)})
				else:
					e.erase("s7_dn")
		if (w.tick + int(id)) % think == 0:
			_think(w, S, e)
	if dirty:
		S.ids = keep
	if cn != null:
		var pe := int(R().get("plan", {}).get("every", 100))
		var ne := int(_tac().get("net_every", 10))
		var call := bool(S.get("call", false))
		S.erase("call")
		for k in cn.facs:
			var F: Dictionary = cn.facs[k]
			if (w.tick + int(k)) % ne == 0 and not sentinels_of(w, int(F.owner)).is_empty():
				_alarm_scan(w, S, F)
			if call and (w.tick + int(k)) % pe != 0 and not sentinels_of(w, int(F.owner)).is_empty():
				plan(w, F)
			if (w.tick + int(k)) % pe == 0 and not sentinels_of(w, int(F.owner)).is_empty():
				plan(w, F)


# ================================================================ thinking (staggered: (tick + id) % think_every)
static func _go(w: SimWorld, e: Dictionary, job: Dictionary, goal: Vector2, ty: String = "attack_move") -> void:
	e.order = {"type": ty, "target": goal}
	job["g"] = goal
	_movement().order_path(w, e, goal)
	SimWorld.HotState.touch(w, int(e.id))


static func _garrison_in(w: SimWorld, e: Dictionary, job: Dictionary, bid: int) -> void:
	job["g"] = null
	_garrison().apply_command(w, {"type": "garrison", "issuer": int(e.owner), "unit_ids": [int(e.id)], "building_id": bid})


## True when the player re-tasked e (any order this system did not give): the unit is left to the player from then on.
static func _player_took(e: Dictionary, job: Dictionary) -> bool:
	var o: Dictionary = e.order
	var ty := String(o.get("type", "idle"))
	if e.has("garrisoned_in"):
		return int(e.garrisoned_in) != int(job.get("bid", -1))
	if o.has("care"):
		return false   # the Wounds care chain (casualty drill)
	if ty == "idle":
		return bool(job.get("in", false))   # was inside its post, now out and idle: ungarrisoned by the player
	if ty == "garrison":
		return int(o.get("building_id", -1)) != int(job.get("bid", -2))
	if ty == "hold":
		return not bool(job.get("hold", false))   # this system holds units only in cover (job.hold)
	var g = job.get("g")
	var tg = o.get("target")
	if g == null or not (tg is Vector2):
		return true
	return Vector2(tg).distance_to(Vector2(g)) > 0.01


## Nearest enemy inside facility fac's zone while the facility is not secure (cached per tick), else null.
static func threat(w: SimWorld, fac: int):
	var c = w.cache.get("s7_thr")
	if c == null or int(c[0]) != w.tick:
		c = [w.tick, {}]
		w.cache["s7_thr"] = c
	var key := str(fac)
	if (c[1] as Dictionary).has(key):
		return c[1][key]
	var out = null
	var F: Dictionary = _cnfac().fac(w, fac)
	if not F.is_empty() and _cnfac().secure_state(w, fac) == "secure":
		out = _alarm(w, F)   # 13.9c-13 stand-to: the guard net saw them coming (before any breach)
	elif not F.is_empty():
		var zr: Rect2 = _cnfac().compound_rect(F).grow(float(R().get("zone_pad", 6)) + 4.0)
		var ctr := zr.get_center()
		var best := INF
		for u in SimWorld.SimIndex.of(w, "unit"):
			if not w.is_enemy(int(F.owner), int(u.owner)) or not zr.has_point(u.pos):
				continue
			var d := Vector2(u.pos).distance_squared_to(ctr)
			if d < best or (d == best and out != null and int(u.id) < int(out[1])):
				best = d
				out = [Vector2(u.pos), int(u.id)]
	c[1][key] = out
	return out


## Latched stand-to alarm of facility F (13.9c-13): [pos, id] of the contact that raised / last refreshed it while it
## holds (alarm_hold_s after the last contact), else null. Position follows the contact while it lives.
static func _alarm(w: SimWorld, F: Dictionary):
	var S = w.sys_state.get(KEY)
	if S == null or not S.has("alarm"):
		return null
	var a = S.alarm.get(str(int(F.id)))
	if a == null or w.tick > int(a.u):
		return null
	var t = w.entities.get(int(a.id))
	return [Vector2(t.pos) if t != null else Vector2(a.p), int(a.id)]


## Guard-net alarm (13.9c-13, every net_every ticks per facility): a sentry who sees the enemy approaching sounds
## stand-to before the wall is breached. Contact = any enemy the owner can see (Sentinels, towers, cameras, wall
## turrets feed fog) inside the compound + alarm_r, or an enemy firing on a Sentinel or a facility building (it was
## hit by him within hit_recent_s, even from beyond sight). The nearest contact to the compound centre refreshes
## the alarm; it holds alarm_hold_s after the last contact, then the shift stands down (SentinelStandDown).
static func _alarm_scan(w: SimWorld, S: Dictionary, F: Dictionary) -> void:
	var T := _tac()
	var key := str(int(F.id))
	var fid := int(F.owner)
	var cr: Rect2 = _cnfac().compound_rect(F)
	var zr: Rect2 = cr.grow(float(T.get("alarm_r", 22.0)))
	var ctr := cr.get_center()
	var best := INF
	var hit = null
	var Fg = SimWorld.Fog
	for u in SimWorld.SimIndex.of(w, "unit"):
		if not w.is_enemy(fid, int(u.owner)) or not zr.has_point(u.pos) or not Fg.is_visible(w, fid, u.pos):
			continue
		var d := Vector2(u.pos).distance_squared_to(ctr)
		if d < best or (d == best and hit != null and int(u.id) < int(hit.id)):
			best = d
			hit = u
	if hit == null:   # fired on from out of sight: the attacker of a hit Sentinel / facility building
		var rec := ticks(float(T.get("hit_recent_s", 3.0)))
		var srcs := []
		for id in S.ids:
			srcs.append(int(id))
		for pid in F.get("parts", []):
			srcs.append(int(pid))
		for id in srcs:
			var e = w.entities.get(id)
			if e == null or int(e.owner) != fid or w.tick - int(e.get("last_hit_tick", -100000)) > rec:
				continue
			var at = w.entities.get(int(e.get("last_attacker", -1)))
			if at == null or not w.is_enemy(fid, int(at.owner)):
				continue
			var d := Vector2(at.pos).distance_squared_to(ctr)
			if d < best or (d == best and hit != null and int(at.id) < int(hit.id)):
				best = d
				hit = at
	if not S.has("alarm"):
		S["alarm"] = {}
	var a = S.alarm.get(key)
	if hit != null:
		if a == null or w.tick > int(a.u):
			w.emit("SentinelStandTo", {"fac": int(F.id), "owner": fid, "by": int(hit.id), "pos": Vector2(hit.pos)})
		S.alarm[key] = {"u": w.tick + ticks(float(T.get("alarm_hold_s", 45.0))), "p": Vector2(hit.pos), "id": int(hit.id)}
	elif a != null and w.tick > int(a.u):
		S.alarm.erase(key)
		w.emit("SentinelStandDown", {"fac": int(F.id), "owner": fid})


static func _think(w: SimWorld, S: Dictionary, e: Dictionary) -> void:
	var uid := int(e.id)
	var job: Dictionary = S.jobs.get(str(uid), {"k": "free"})
	var kind := String(e.s7)
	if SimWorld.Wounds.is_down(e):
		return   # a casualty does nothing; its buddy and the Mender run the casualty drill
	if kind == "mender":
		_mender(w, S, e)
	elif kind == "arc":
		_arc(w, e)
	var k := String(job.get("k", "free"))
	if k == "free" or k == "auto":
		return
	if k == "player":   # 13.9c-12: back on automatic duty when the order is done or after own_timeout_s
		var ot := String(e.order.get("type", "idle"))
		if (ot == "idle" and not e.has("garrisoned_in")) or w.tick - int(job.get("t", 0)) > ticks(float(R().get("own_timeout_s", 45.0))):
			S.jobs[str(uid)] = {"k": "auto", "fac": int(job.get("fac", -1))}
		return
	if _caring(w, uid):
		# SENT7-4 13.9c-13 gait in the care chain: sprint to the casualty, hunched duck-run while dragging him,
		# kneel while treating (the Wounds care chain owns the order; this only sets how he moves).
		if e.has("wdrg"):
			_set_gait(w, e, 2)
		elif bool(e.get("moving", false)):
			_set_gait(w, e, 3)
		else:
			_set_gait(w, e, 1)
		if k == "casualty" and not job.has("tr"):   # the Mender is working on the casualty of his job (care chain)
			var st = w.sys_state.get("wounds")
			var cv = st.care.get(uid, st.care.get(str(uid))) if st != null else null
			if cv != null and int(cv.get("c", -1)) == int(job.get("uid", -2)):
				job["tr"] = true
				w.emit("SentinelMenderTreats", {"id": int(job.uid), "by": uid, "owner": int(e.owner)})
		return   # dragging / treating a casualty: the Wounds care chain drives the order
	if job.has("hand"):   # a new job from the board: the old job's order / post was this system's, hand it over
		job.erase("hand")
		if e.has("garrisoned_in") and int(e.garrisoned_in) != int(job.get("bid", -1)):
			_garrison()._leave(w, e, "retask")
		if not e.has("garrisoned_in"):
			_idle(e)
	if _player_took(e, job):
		S.jobs[str(uid)] = {"k": "player", "t": w.tick, "fac": int(job.get("fac", -1))}
		return
	if k != "ammo" and bool(e.get("s7_sa", false)) and int(e.get("ammo", 1)) <= 0:
		if _start_ammo(w, S, e, job):
			return
	if k == "ammo" or kind == "bearer":
		if k == "ammo":
			_ammo_trip(w, S, e, job)
		elif k == "restock" or k == "locker" or k == "bear":
			_bearer(w, S, e, job)
		elif k == "rest":
			_post(w, S, e, job)
		return
	if _casualty_drill(w, S, e, job):
		return
	var F := _fac_of(w, job)
	var th = threat(w, int(F.id)) if not F.is_empty() else null
	if bool(job.get("wd", false)):
		_withdraw(w, S, e, job, F, th[0] if th != null else null)
		return
	if th != null:
		_reload_check(w, S, e, job, th[0])
		_aim(w, S, e, job, F)
	match k:
		"wall", "int", "patrol":
			_patrol(w, S, e, job)
		"post", "entry", "qrf", "rest", "tower":
			_post(w, S, e, job)
		"standto":
			_standto(w, S, e, job)
		"casualty":
			_casualty_job(w, S, e, job)
		"repair":
			_repair(w, S, e, job)


static func _repair(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary) -> void:
	var b = w.entities.get(int(job.get("bid", -1)))
	if b == null or float(b.hp) >= float(b.max_hp):
		S.jobs[str(int(e.id))] = {"k": "auto", "fac": int(job.get("fac", -1))}
		return
	var M: Dictionary = R().get("mender", {})
	if _bdist(e.pos, b) <= float(M.get("radius", 3.5)):
		var dt := float(R().get("think_every", 20)) / float(SimWorld.TICK_RATE)
		repair_part(w, int(b.id), float(M.get("repair_hp_s", 40.0)) * dt)
	elif not bool(e.get("moving", false)):
		_go(w, e, job, _bpos(b), "move")


## Wall-walk and interior patrols. Quiet: walk the route (walking gait), pause at each waypoint to observe (varied,
## deterministic timing) and check in at the towers. Alarm: the pair bounds (one moves, the buddy covers) to the
## threatened face / towards contact, then fights from cover; outmatched or badly hurt, it withdraws by bounds.
static func _patrol(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary) -> void:
	if e.has("garrisoned_in"):
		return
	var th = threat(w, int(job.get("fac", -1)))
	var route: Array = job.route
	var off := Vector2(float(job.get("ox", 0.0)), float(job.get("oy", 0.0)))
	if th != null:
		var tp: Vector2 = th[0]
		if _withdraw(w, S, e, job, _fac_of(w, job), tp):
			return
		job.erase("wt")
		var goal := tp
		if String(job.k) == "wall":   # pairs bound along the wall-walk to the threatened face, then hold the parapet
			var bi := 0
			for i in route.size():
				if Vector2(route[i]).distance_squared_to(tp) < Vector2(route[bi]).distance_squared_to(tp):
					bi = i
			goal = Vector2(route[bi]) + off
		else:
			goal = _contact_goal(e, tp)
		if _has_shot(w, e) or _bound_to(w, S, e, job, goal, tp):
			_settle(w, S, e, job, tp)
		return
	if int(e.get("target", -1)) >= 0:
		return
	job.erase("hold")
	var wp := int(job.wp)
	var goal: Vector2 = Vector2(route[wp]) + off
	var ot := String(e.order.get("type", "idle"))
	if job.has("wt"):
		if w.tick < int(job.wt):
			return
		job.erase("wt")
		_next_wp(w, e, job, route, off)
		return
	if Vector2(e.pos).distance_to(goal) <= float(R().get("arrive", 1.4)):
		var T := _tac()
		var ps: Array = T.get("pause_s", [2, 6])
		var span := maxi(1, int(ps[1]) - int(ps[0]) + 1)
		var bd := int(job.get("bud", -1))
		var sd := int(e.id) if bd < 0 else mini(int(e.id), bd)
		var sec := float(int(ps[0]) + (sd * 7 + wp * 13 + w.tick / ticks(60.0)) % span)
		if (job.get("ck", []) as Array).has(wp):
			sec += float(T.get("checkin_s", 4.0))
			w.emit("SentinelCheckIn", {"id": int(e.id), "owner": int(e.owner), "fac": int(job.get("fac", -1)), "wp": wp})
		job["wt"] = w.tick + ticks(sec)
		_idle(e)
		_set_gait(w, e, 0)
		_face(w, e, job, null)
		return
	if ot == "idle" or ot == "hold":
		if ot == "idle" and job.get("g") != null and Vector2(job.g).distance_to(goal) < 0.01:
			_next_wp(w, e, job, route, off)   # could not get there: take the next leg
			return
	elif bool(e.get("moving", false)) and job.get("g") != null and Vector2(job.g).distance_to(goal) < 0.01:
		return   # still on its leg
	_set_gait(w, e, 0)
	_go(w, e, job, goal)


static func _next_wp(w: SimWorld, e: Dictionary, job: Dictionary, route: Array, off: Vector2) -> void:
	var wp := int(job.wp)
	var d := int(job.get("dir", 1))
	var n := wp + d
	if bool(job.get("loop", false)):
		n = (n + route.size()) % route.size()
	elif n < 0 or n >= route.size():
		d = -d
		job.dir = d
		n = wp + d
	job.wp = n
	_set_gait(w, e, 0)
	if e.has("f7_hd"):
		e.erase("f7_hd")
		_sq7d().put(w, e)
	_go(w, e, job, Vector2(route[n]) + off)


## Posts (towers, entry booth), the quick reaction force and rest (barracks). Under alarm a pair bounds to its post,
## stacks at the door (Bulwark first) and goes in; the QRF turns out, bounds towards contact and fights from cover.
static func _post(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary) -> void:
	var bid := int(job.get("bid", -1))
	var b = w.entities.get(bid)
	var th = threat(w, int(job.get("fac", -1)))
	if e.has("garrisoned_in") and int(e.garrisoned_in) == bid:
		job["in"] = true
		if e.has("f7_clr"):
			e.erase("f7_clr")
			_sq7d().put(w, e)
		if String(job.k) == "qrf" and th != null:   # the quick reaction force turns out, one man of a pair at a time
			var bb = w.entities.get(int(job.get("bud", -1)))
			if bb != null and int(bb.owner) == int(e.owner) and not _down(bb):
				if bb.has("garrisoned_in") and int(bb.garrisoned_in) == bid and int(bb.id) < int(e.id):
					return   # buddy goes first
				if not bb.has("garrisoned_in") and _up(w, S, bb):
					return   # buddy is still up: wait for him to get down
			job["in"] = false
			var cg := _contact_goal(e, th[0])
			var me := Vector2(e.pos)
			var bl := float(_tac().get("bound_len", 5.0))
			if me.distance_to(cg) > bl:
				cg = _cover_near(w, e, me + (cg - me).normalized() * bl, 1, th[0])
			_set_gait(w, e, 3 if _under_fire(w, e) else 2)
			_go(w, e, job, cg, "move")
		return
	job["in"] = false
	if String(job.k) == "qrf" and th != null:
		if _withdraw(w, S, e, job, _fac_of(w, job), th[0]):
			return
		if _has_shot(w, e) or _bound_to(w, S, e, job, _contact_goal(e, th[0]), th[0]):
			_settle(w, S, e, job, th[0])
		return
	if b == null or b.kind != "building" or int(b.owner) != int(e.owner):
		var hp = job.get("pos", job.get("home"))
		if hp is Vector2 and Vector2(e.pos).distance_to(hp) > 2.0 and String(e.order.get("type", "idle")) == "idle":
			_go(w, e, job, hp, "move")
		return
	if String(e.order.get("type", "")) == "garrison" or _garrison().free_slots(w, b) <= 0:
		return
	if th != null and String(job.k) != "rest" and String(e.s7) != "bearer":
		if _bdist(e.pos, b) > 3.0:
			_bound_to(w, S, e, job, _bpos(b), th[0])   # bound to the post under fire
			return
		var T := _tac()
		if not job.has("stk"):   # stack at the door, Bulwark first, then go in
			var lag := 0.0 if String(e.s7) == "bulwark" else float(T.get("stack_s", 1.5))
			job["stk"] = w.tick + ticks(float(T.get("stack_s", 1.5)) + lag)
			e.f7_clr = 1
			_sq7d().put(w, e)
			_idle(e)
			_set_gait(w, e, 1)
			return
		if w.tick < int(job.stk):
			return
	job.erase("stk")
	_garrison_in(w, e, job, bid)


## Primary and sidearm both empty: walk to the nearest stocked ready-ammo locker. False when there is none.
static func _start_ammo(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary) -> bool:
	var lid := _nearest_locker(w, e, 1, float(R().get("locker", {}).get("search_r", 40)))
	if lid < 0:
		return false
	var prev := job.duplicate(true)
	prev["in"] = false
	var nj := {"k": "ammo", "bid": lid, "fac": int(job.get("fac", -1)), "prev": prev}
	S.jobs[str(int(e.id))] = nj
	_go(w, e, nj, _bpos(w.entities[lid]), "move")
	return true


static func _bpos(b: Dictionary) -> Vector2:
	var sz := float(b.get("size", 1))
	return Vector2(b.cell) + Vector2(sz, sz) * 0.5


## Nearest own locker with at least min_stock loads (or below cap when min_stock < 0) within r; -1 when none.
static func _nearest_locker(w: SimWorld, e: Dictionary, min_stock: int, r: float) -> int:
	var best := -1
	var bd := r * r
	var cap := int(R().get("locker", {}).get("cap", 14))
	for lid in lockers_of(w, int(e.owner)):
		var s := locker_stock(w, lid)
		if (min_stock >= 0 and s < min_stock) or (min_stock < 0 and s >= cap):
			continue
		var d := Vector2(e.pos).distance_squared_to(_bpos(w.entities[lid]))
		if d < bd:
			bd = d
			best = lid
	return best


static func _ammo_trip(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary) -> void:
	var lid := int(job.bid)
	var L: Dictionary = R().get("locker", {})
	if locker_stock(w, lid) <= 0:
		lid = _nearest_locker(w, e, 1, float(L.get("search_r", 40)))
		if lid < 0:
			S.jobs[str(int(e.id))] = job.get("prev", {"k": "free"})
			return
		job.bid = lid
		_go(w, e, job, _bpos(w.entities[lid]), "move")
		return
	var at := _bpos(w.entities[lid])
	if Vector2(e.pos).distance_to(at) <= float(L.get("reach", 1.6)) + 0.5:
		locker_add(w, lid, -1)
		e.ammo = int(Content.unit(String(e.def)).get("ammo_max", 0))
		e.s7_sa = false
		SimWorld.HotState.set_cd(w, int(e.id), ticks(float(L.get("reload_s", 2.0))))
		w.emit("SentinelRearmed", {"id": int(e.id), "owner": int(e.owner), "locker": lid})
		var prev: Dictionary = job.get("prev", {"k": "free"})
		S.jobs[str(int(e.id))] = prev
		_idle(e)
		return
	if not bool(e.get("moving", false)):
		_go(w, e, job, at, "move")


static func _idle(e: Dictionary) -> void:
	e.order = {"type": "idle"}
	e.path = []
	e.path_i = 0
	e.moving = false


# ================================================================ specialists
## Mender: heals Sentinels around it (also under fire) and, out of combat, repairs the most damaged facility part
## (walls, towers, wall turrets, buildings) within reach.
static func _mender(w: SimWorld, S: Dictionary, e: Dictionary) -> void:
	var M: Dictionary = R().get("mender", {})
	var dt := float(R().get("think_every", 20)) / float(SimWorld.TICK_RATE)
	var rad := float(M.get("radius", 3.5))
	var heal := float(M.get("heal_hp_s", 10.0)) * dt
	for id in S.ids:
		var u = w.entities.get(int(id))
		if u == null or int(u.owner) != int(e.owner) or float(u.hp) >= float(u.max_hp):
			continue
		if Vector2(u.pos).distance_to(e.pos) <= rad:
			SimWorld.HotState.set_hp(w, int(id), minf(float(u.max_hp), snappedf(float(u.hp) + heal, 0.01)))


static func _bdist(p: Vector2, b: Dictionary) -> float:
	var sz := float(b.get("size", 1))
	var lo := Vector2(b.cell)
	var q := Vector2(clampf(p.x, lo.x, lo.x + sz), clampf(p.y, lo.y, lo.y + sz))
	return p.distance_to(q)


## Arc: EMP grenade at its current target when that is a drone or a Machine unit within reach (drones drop, Machine
## units are stunned / their link jammed through Apc7._disable, like the counter-nanite EMP grenade).
static func _arc(w: SimWorld, e: Dictionary) -> void:
	var A: Dictionary = R().get("arc", {})
	if w.tick < int(e.get("s7_kcd", 0)) or emp_down(w, e):
		return
	var t = w.entities.get(int(e.get("target", -1)))
	if t == null or t.kind != "unit" or not w.is_enemy(int(e.owner), int(t.owner)):
		return
	if Vector2(t.pos).distance_to(e.pos) > float(A.get("radius", 7.0)):
		return
	var mf: Array = R().get("machine_factions", ["machine"])
	var cd = SimWorld.Counterdrone
	if not cd.is_drone(w, t) and not mf.has(String(Content.unit(String(t.def)).get("faction", ""))):
		return
	var at: Vector2 = t.pos
	var A7 = _apc7()
	var hit := []
	for u in A7.near(w, at, float(A.get("blast_r", 2.5))):
		if u.kind == "unit" and w.is_enemy(int(e.owner), int(u.owner)) and not A7.unhackable(u):
			hit.append(u)
	hit.sort_custom(func(a, b) -> bool: return int(a.id) < int(b.id))
	for u in hit:
		if not w.entities.has(int(u.id)):
			continue
		if cd.is_drone(w, u):
			w.destroy(int(u.id), "emp", int(e.owner))
		elif mf.has(String(Content.unit(String(u.def)).get("faction", ""))):
			A7._disable(w, u, int(A.get("stun_ticks", 120)))
	e.s7_kcd = w.tick + ticks(float(A.get("cooldown_s", 22.0)))
	w.emit("SentinelEmp", {"id": int(e.id), "owner": int(e.owner), "pos": at, "hit": hit.size()})


## Sentinel Ammo Bearer: restocks Sentinels on post where they stand (on the sidearm or below low_frac), then
## refills lockers below cap; empty, it refills at the Sentinel Barracks or the facility magazine.
static func _bearer(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary) -> void:
	var B: Dictionary = R().get("bearer", {})
	if not e.has("s7_carry"):
		e.s7_carry = int(B.get("carry", 10))
	var reach := float(B.get("reach", 1.6))
	var carry := int(e.s7_carry)
	if carry <= 0:
		var src = _refill_point(w, e)
		if src == null:
			return
		if _bdist(e.pos, src) <= float(B.get("refill_r", 2.5)):
			e.s7_carry = int(B.get("carry", 10))
			w.emit("SentinelBearerRefilled", {"id": int(e.id), "owner": int(e.owner), "at": int(src.id)})
		elif not bool(e.get("moving", false)):
			_go(w, e, job, _bpos(src), "move")
		return
	var k := String(job.k)
	var low := float(B.get("low_frac", 0.5))
	if k == "restock":
		var u = w.entities.get(int(job.get("uid", -1)))
		var am := float(Content.unit(String(u.def)).get("ammo_max", 0)) if u != null else 0.0
		if u == null or (not bool(u.get("s7_sa", false)) and float(u.ammo) >= low * am):
			S.jobs[str(int(e.id))] = {"k": "auto", "fac": int(job.get("fac", -1))}
			return
		if Vector2(u.pos).distance_to(e.pos) <= reach + (1.2 if u.has("garrisoned_in") else 0.0):
			u.ammo = int(am)
			u.s7_sa = false
			e.s7_carry = carry - 1
			w.emit("SentinelRestocked", {"id": int(u.id), "by": int(e.id), "owner": int(e.owner)})
			S.jobs[str(int(e.id))] = {"k": "auto", "fac": int(job.get("fac", -1))}
		elif job.get("g") == null or Vector2(job.g).distance_to(u.pos) > 1.0 or not bool(e.get("moving", false)):
			_go(w, e, job, Vector2(u.pos), "move")
	elif k == "locker":
		var lid := int(job.get("bid", -1))
		if locker_stock(w, lid) < 0:
			S.jobs[str(int(e.id))] = {"k": "auto", "fac": int(job.get("fac", -1))}
			return
		var at := _bpos(w.entities[lid])
		if Vector2(e.pos).distance_to(at) <= reach + 0.5:
			e.s7_carry = carry - locker_add(w, lid, carry)
			S.jobs[str(int(e.id))] = {"k": "auto", "fac": int(job.get("fac", -1))}
		elif not bool(e.get("moving", false)):
			_go(w, e, job, at, "move")


## Nearest own Sentinel Barracks or facility magazine (bearer refill), else null.
static func _refill_point(w: SimWorld, e: Dictionary):
	var cn = w.sys_state.get("cn_facility")
	if cn == null:
		return null
	var best = null
	var bd := INF
	for k in cn.facs:
		var F: Dictionary = cn.facs[k]
		if int(F.owner) != int(e.owner):
			continue
		var cands := _parts_of(w, F, "cn_sentinel_barracks")
		var mg = w.entities.get(int(F.get("mag", 0)))
		if mg != null:
			cands.append(mg)
		for b in cands:
			var d := _bdist(e.pos, b)
			if d < bd or (d == bd and best != null and int(b.id) < int(best.id)):
				bd = d
				best = b
	return best


## Sentinels the barracks finished this tick (ProductionCompleted) join the force: bearers go to work, the rest obey
## the player (job "free").
static func _enlist_trained(w: SimWorld) -> void:
	for ev in w.events:
		if String(ev.type) != "ProductionCompleted":
			continue
		for uid in ev.get("unit_ids", []):
			var e = w.entities.get(int(uid))
			if e == null or e.has("s7") or type_of_def(String(e.def)) == "":
				continue
			var k := type_of_def(String(e.def))
			enlist(w, e, {"k": "auto", "fac": -1})


static func _zones(w: SimWorld) -> Array:
	var out := []
	var cn = w.sys_state.get("cn_facility")
	if cn == null:
		return out
	var pad := float(R().get("zone_pad", 6))
	for k in cn.facs:
		var F: Dictionary = cn.facs[k]
		out.append([_cnfac().compound_rect(F).grow(pad), int(F.owner)])
	return out


static func _in_zone(zones: Array, e: Dictionary) -> bool:
	for z in zones:
		if int(z[1]) == int(e.owner) and (z[0] as Rect2).has_point(e.pos):
			return true
	return false


static func _supp_at() -> float:
	return float(Content.rules().get("g61_realism", {}).get("suppression", {}).get("suppressed_at", 25.0))


static func emp_down(w: SimWorld, e: Dictionary) -> bool:
	return int(e.get("emp_until", -1)) >= w.tick or int(e.get("jammed_until", -1)) >= w.tick


## Armour, sidearm switch and self-heal (every regen.every ticks).
static func _vitals(w: SimWorld, e: Dictionary, rg: Dictionary, every: int) -> void:
	var emp := emp_down(w, e)
	if bool(e.get("suit", false)) == emp:
		e.suit = not emp   # an EMP drops the sealed nanotech armour (creep exposure gets through)
	var sa: Dictionary = R().get("sidearm", {})
	if e.has("ammo"):
		var rounds := int(sa.get("rounds", 40))
		if int(e.ammo) <= 0 and not bool(e.get("s7_sa", false)):
			e.s7_sa = true
			e.ammo = rounds
			w.emit("SentinelSidearm", {"id": int(e.id), "owner": int(e.owner)})
		elif bool(e.get("s7_sa", false)) and int(e.ammo) > rounds:
			e.s7_sa = false   # resupplied by other means (supply truck, ammo bearer)
		var mag := _mag(e)
		if mag > 0:   # 13.9c-13 ammo discipline: magazines, a real reload when one runs dry
			var am := int(e.ammo)
			var last := int(e.get("s7_al", am))
			if am < last:
				e.s7_mg = int(e.get("s7_mg", mag)) - (last - am)
			elif am > last:
				e.s7_mg = mini(mag, am)
			if int(e.get("s7_al", -1)) != am:
				e.s7_al = am
			if int(e.get("s7_mg", mag)) <= 0 and am > 0 and w.tick >= int(e.get("s7_rl", 0)):
				_reload(w, e, mag, false)
	if emp or float(e.hp) >= float(e.max_hp):
		return
	if w.tick - int(e.get("last_hit_tick", -100000)) < ticks(float(rg.get("quiet_s", 6.0))):
		return
	if float(e.get("supp", 0.0)) >= _supp_at():
		return
	var rate := float(rg.get("zone_hp_s", 8.0)) if bool(e.get("s7_z", false)) else float(rg.get("hp_s", 4.0))
	var hp := minf(float(e.max_hp), snappedf(float(e.hp) + rate * float(every) / float(SimWorld.TICK_RATE), 0.01))
	SimWorld.HotState.set_hp(w, int(e.id), hp)
	if bool(rg.get("reseal", true)) and e.has("wpunct"):
		e.erase("wpunct")


# ================================================================ 13.9c-13 realism and expert tactics (SENT7-2)
## Real infantry / security-force practice, built from the existing systems (no new combat numbers):
##  - Buddy pairs: the two holders of one board job (record "bud"). Under alarm they move by bounds: the trailing man
##    rushes (duck-run, sprint when under fire) past his buddy by tactics.bound_len and drops into the best cover cell
##    there; the buddy, stationary, covers (order hold, crouched, sector set). Nobody bounds while his buddy reloads.
##  - Cover: a landing / fighting spot is the best cell near it by terrain cover, the wall-walk parapet (+0.6) and hard
##    cover beside it (walls, buildings: moving along walls); a man left standing in the open (< open_v) moves to
##    cover within cover_r once per spot. A corner between him and the threat: he steps out wide (pie_r) to the side
##    with a clear line (cutting the pie) instead of crowding it.
##  - Sector of fire: e.f7_hd (deg) outward from the compound / towards the threat, buddies split +-pair_spread so the
##    pair's fields overlap; targets in sector score in_sector, outside out_sector (interlocking fields from posts).
##  - Guard net (13.9c-11/-12): every enemy the owner can see (Sentinels, towers, cameras, wall turrets all feed fog)
##    inside the compound + net_r is shared with every Sentinel (S.net, refreshed every net_every ticks under alarm).
##    Target choice: class priority x the type's preference (Lancer: armour / walkers; Arc: drones / Machine;
##    Marksman: crew-served weapons and leaders; Gunner: infantry) x sector x focus fire (already engaged by others)
##    x closeness. Only targets in weapon range; Combat still resolves every shot.
##  - Ammo discipline: magazines (tactics.mag by type, sidearm_mag), a reload of reload_s when one runs dry
##    (SentinelReloading event = the "reloading" call; the buddy holds and covers), a tactical reload when low with
##    nothing to shoot and the buddy not reloading; a man reloading in the open first gets into cover.
##  - Casualty drill: a buddy goes down -> the other drags him (Wounds drag) to cover away from the threat, then gives
##    buddy aid; the board posts a "casualty" job and the nearest Mender comes forward and treats him.
##  - Withdrawal by bounds: a pair below withdraw_hp, or outnumbered withdraw_ratio:1 within local_r, bounds back to
##    the barracks facing the enemy (order.bk) and rests (s7_wd) before taking a post again.
##  - Gait (e.gait, SQUAD7 field: speed via Formations7.gait_mult, drawn by LOOK7): walk on patrol, duck-run when
##    bounding, sprint under fire, crouch while holding / covering / stacked.
static var _sq = null


static func _sq7d():
	if _sq == null:
		_sq = load("res://sim/systems/sq7_display.gd")
	return _sq


static func _tac() -> Dictionary:
	return R().get("tactics", {})


static func _fac_of(w: SimWorld, job: Dictionary) -> Dictionary:
	var f := int(job.get("fac", -1))
	return _cnfac().fac(w, f) if f >= 0 else {}


static func _set_gait(w: SimWorld, e: Dictionary, g: int) -> void:
	if g <= 0:
		if not e.has("gait"):
			return
		e.erase("gait")
	elif int(e.get("gait", 0)) == g:
		return
	else:
		e.gait = g
	_sq7d().put(w, e)


## Watched sector (e.f7_hd, degrees): towards the threat, else outward from the compound; buddies split +-spread.
static func _face(w: SimWorld, e: Dictionary, job: Dictionary, tp) -> void:
	var F := _fac_of(w, job)
	var dir := Vector2.ZERO
	if tp != null:
		dir = Vector2(tp) - Vector2(e.pos)
	elif not F.is_empty():
		dir = Vector2(e.pos) - _cnfac().compound_rect(F).get_center()
	if dir.length_squared() < 0.0001:
		return
	var sp := float(_tac().get("pair_spread_deg", 25.0))
	var bd := int(job.get("bud", -1))
	var off := 0.0 if bd < 0 else (sp if int(e.id) < bd else -sp)
	var hd := roundi(rad_to_deg(dir.angle()) + off)
	if int(e.get("f7_hd", 99999)) != hd:
		e.f7_hd = hd
		_sq7d().put(w, e)


static func _under_fire(w: SimWorld, e: Dictionary) -> bool:
	var T := _tac()
	return w.tick - int(e.get("last_hit_tick", -100000)) < ticks(float(T.get("hit_recent_s", 3.0))) \
		or float(e.get("supp", 0.0)) >= float(T.get("rush_supp", 12.0))


## Live buddy on the same job (not down, not inside a building), else null.
static func _bud(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary):
	var bd := int(job.get("bud", -1))
	if bd < 0:
		return null
	var b = w.entities.get(bd)
	if b == null or int(b.owner) != int(e.owner) or b.has("garrisoned_in") or SimWorld.Wounds.is_down(b):
		return null
	if String(S.jobs.get(str(bd), {}).get("j", "")) != String(job.get("j", "?")):
		return null
	return b


## Cover value of a cell: terrain cover, the wall-walk parapet, hard cover beside it (moving along walls).
static func _cover_v(w: SimWorld, c: Vector2i, team: int) -> float:
	var mv = _movement()
	var v := 1.0 - Terrain.cover_mult(w.terrain_at(c), "foot")
	if mv.wallwalk_team(w, c) >= 0:
		v += 0.6   # behind the parapet: heavy cover, not skylined
	var n := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = c + d
		if w.in_bounds(q) and not mv.is_passable(w, q, "foot", team):
			n += 1
	return v + 0.15 * float(mini(n, 2))


## Best cover cell within r of p (still in weapon range of tp when one is given).
static func _cover_near(w: SimWorld, e: Dictionary, p: Vector2, r: int, tp) -> Vector2:
	var mv = _movement()
	var team := _team(w, int(e.owner))
	var c0: Vector2i = w.cell_of(p)
	var rng := INF
	if tp != null:
		var s: Dictionary = SimWorld.Combat.stats(e)
		rng = float(s.get("range", 6.0)) * range_mult(w, e, s)
	var best := p
	var bv := -INF
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := c0 + Vector2i(dx, dy)
			if not w.in_bounds(c) or not mv.is_passable(w, c, "foot", team):
				continue
			var q := Vector2(c) + Vector2(0.5, 0.5)
			var v := _cover_v(w, c, team) - 0.08 * q.distance_to(p)
			if tp != null and q.distance_to(tp) > rng:
				v -= 0.5
			if v > bv:
				bv = v
				best = q
	return best


## Cutting the pie: a wall / building corner right between p and the threat masks it; step out wide (pie_r) to the
## side that has a clear line instead of crowding the corner.
static func _pie(w: SimWorld, e: Dictionary, p: Vector2, tp) -> Vector2:
	if tp == null or Vector2(tp).distance_to(p) < 2.0:
		return p
	var mv = _movement()
	var team := _team(w, int(e.owner))
	var dir := (Vector2(tp) - p).normalized()
	var q: Vector2i = w.cell_of(p + dir)
	if not w.in_bounds(q) or mv.is_passable(w, q, "foot", team):
		return p
	var pie := float(_tac().get("pie_r", 1.5))
	for side in [1.0, -1.0]:
		var o: Vector2 = p + dir.orthogonal() * float(side) * pie
		var oc: Vector2i = w.cell_of(o)
		var nc: Vector2i = w.cell_of(o + dir)
		if w.in_bounds(oc) and w.in_bounds(nc) and mv.is_passable(w, oc, "foot", team) and mv.is_passable(w, nc, "foot", team):
			return Vector2(oc) + Vector2(0.5, 0.5)
	return p


## Where a man stops when closing with the threat: at 0.7 x his weapon range from it (never onto it).
static func _contact_goal(e: Dictionary, tp: Vector2) -> Vector2:
	var s: Dictionary = SimWorld.Combat.stats(e)
	var rng := float(s.get("range", 6.0)) * 0.7
	var me: Vector2 = e.pos
	if me.distance_to(tp) <= rng:
		return me
	return tp + (me - tp).normalized() * rng


static func _has_shot(w: SimWorld, e: Dictionary) -> bool:
	var t = w.entities.get(int(e.get("target", -1)))
	if t == null or not w.is_enemy(int(e.owner), int(t.owner)):
		return false
	var s: Dictionary = SimWorld.Combat.stats(e)
	return SimWorld.Combat.dist_to(e.pos, t) <= float(s.get("range", 6.0)) * range_mult(w, e, s)


## One bound of a buddy pair towards goal. True when e is there. The trailing man rushes past his buddy by bound_len
## to the best cover cell there; the leading one (or anyone whose buddy is up or reloading) covers from where he is.
static func _bound_to(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary, goal: Vector2, tp, back: bool = false) -> bool:
	var T := _tac()
	var me: Vector2 = e.pos
	var arr := float(T.get("arrive", 1.2))
	if bool(e.get("moving", false)) and job.get("g") != null and String(e.order.get("type", "")) == "move":
		return false   # mid-rush: finish it
	var dm := me.distance_to(goal)
	if dm <= arr:
		return true
	var b = _bud(w, S, e, job)
	var adv := float(T.get("bound_len", 5.0))
	if b != null:
		var db := Vector2(b.pos).distance_to(goal)
		if _up(w, S, b) or w.tick < int(b.get("s7_rl", 0)) or dm < db - 0.5 or (absf(dm - db) <= 0.5 and int(e.id) > int(b.id)):
			_settle(w, S, e, job, tp)   # buddy is up (or reloading): I cover him
			return false
		adv = minf(dm, maxf(dm - db, 0.0) + adv)
	else:
		adv = minf(dm, adv)
	var p := me + (goal - me) / dm * adv
	if p.distance_to(goal) > arr:
		p = _cover_near(w, e, p, 1, tp)
	_set_gait(w, e, 3 if _under_fire(w, e) else 2)
	if e.has("f7_clr"):
		e.erase("f7_clr")
		_sq7d().put(w, e)
	job.erase("hold")
	job.erase("adj")
	_go(w, e, job, p, "move")
	if back:
		e.order["bk"] = true   # withdrawing: backs off facing the enemy
		SimWorld.Combat.note_bk(w, int(e.id))
	return false


## Buddy b is up: moving, or still on a rush (move order short of its goal), so he is not covering anyone.
static func _down(e: Dictionary) -> bool:
	return SimWorld.Wounds.is_down(e)


static func _up(w: SimWorld, S: Dictionary, b: Dictionary) -> bool:
	if bool(b.get("moving", false)):
		return true
	if String(b.order.get("type", "")) != "move":
		return false
	var g = S.jobs.get(str(int(b.id)), {}).get("g")
	return g is Vector2 and Vector2(b.pos).distance_to(g) > float(_tac().get("arrive", 1.2))


## Stops and fights from where he is: into cover first (once per spot), around a masking corner, then hold (fires at
## targets in range, never chases), crouched, sector set. While his buddy is up he stays put and covers him (the
## shift into better cover waits until the buddy is down again).
static func _settle(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary, tp) -> void:
	if e.has("garrisoned_in") or bool(e.get("moving", false)):
		return
	var T := _tac()
	var team := _team(w, int(e.owner))
	var c: Vector2i = w.cell_of(e.pos)
	var b = _bud(w, S, e, job)
	if String(job.get("adj", "")) != str(c) and (b == null or not _up(w, S, b)):
		job["adj"] = str(c)
		var p := Vector2(e.pos)
		if _cover_v(w, c, team) < float(T.get("open_v", 0.35)):
			p = _cover_near(w, e, p, int(T.get("cover_r", 2)), tp)   # never stand in the open
		p = _pie(w, e, p, tp)
		if p.distance_to(e.pos) > 0.4:
			_set_gait(w, e, 2)
			job.erase("hold")
			_go(w, e, job, p, "move")
			return
	if String(e.order.get("type", "")) != "hold":
		e.order = {"type": "hold"}
		SimWorld.HotState.touch(w, int(e.id))
	job["hold"] = true
	job["g"] = null
	_set_gait(w, e, 1)
	_face(w, e, job, tp)


## Off-duty Sentinels under alarm: to the pre-assigned stand-to position, then hold it from cover.
static func _standto(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary) -> void:
	var th = threat(w, int(job.get("fac", -1)))
	var tp = th[0] if th != null else null
	if tp != null and _withdraw(w, S, e, job, _fac_of(w, job), tp):
		return
	if _has_shot(w, e) or _bound_to(w, S, e, job, Vector2(job.get("pos", e.pos)), tp):
		_settle(w, S, e, job, tp)


## Withdrawal by bounds (true while withdrawing): triggered when the pair is badly hurt or heavily outnumbered.
static func _withdraw(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary, F: Dictionary, tp) -> bool:
	if F.is_empty():
		return false
	var T := _tac()
	if not bool(job.get("wd", false)):
		if tp == null or not _outmatched(w, S, e, job, F):
			return false
		job["wd"] = true
		e.s7_wd = w.tick + ticks(float(T.get("withdraw_rest_s", 30.0)))
		w.emit("SentinelWithdraw", {"id": int(e.id), "owner": int(e.owner), "fac": int(F.id)})
	if _bound_to(w, S, e, job, _home(w, F), tp, true):
		S.jobs[str(int(e.id))] = {"k": "auto", "fac": int(F.id)}
		_idle(e)
		_set_gait(w, e, 0)
	return true


static func _outmatched(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary, F: Dictionary) -> bool:
	var T := _tac()
	var b = _bud(w, S, e, job)
	var hf := float(e.hp) / maxf(float(e.max_hp), 1.0)
	if b != null:
		hf = (hf + float(b.hp) / maxf(float(b.max_hp), 1.0)) * 0.5
	if hf < float(T.get("withdraw_hp", 0.4)):
		return true
	var r := float(T.get("local_r", 10.0))
	var ne := 0
	for tid in _net(w, S, F):
		var t = w.entities.get(int(tid))
		if t != null and Vector2(t.pos).distance_to(e.pos) <= r:
			ne += 1
	if ne < int(T.get("withdraw_min", 4)):
		return false
	var own := 0
	for id in S.ids:
		var u = w.entities.get(int(id))
		if u != null and int(u.owner) == int(e.owner) and Vector2(u.pos).distance_to(e.pos) <= r and not SimWorld.Wounds.is_down(u):
			own += 1
	return float(ne) >= float(T.get("withdraw_ratio", 3.0)) * float(maxi(own, 1))


## Guard net: ids of the enemies the owner sees inside facility F's compound + net_r (ascending), saved in S.net.
static func _net(w: SimWorld, S: Dictionary, F: Dictionary) -> Array:
	var key := str(int(F.id))
	if threat(w, int(F.id)) == null:
		if S.has("net") and (S.net as Dictionary).has(key):
			S.net.erase(key)
		return []
	if not S.has("net"):
		S["net"] = {}
	var T := _tac()
	var n = S.net.get(key)
	if n != null and w.tick - int(n.at) < int(T.get("net_every", 10)):
		return n.c
	var fid := int(F.owner)
	var zr: Rect2 = _cnfac().compound_rect(F).grow(float(T.get("net_r", 22.0)))
	var Fg = SimWorld.Fog
	var out := []
	for u in SimWorld.SimIndex.of(w, "unit"):
		if w.is_enemy(fid, int(u.owner)) and zr.has_point(u.pos) and Fg.is_visible(w, fid, u.pos):
			out.append(int(u.id))
	out.sort()
	S.net[key] = {"at": w.tick, "c": out}
	return out


## Own Sentinels per target id this tick (focus fire).
static func _focus(w: SimWorld, S: Dictionary) -> Dictionary:
	var c = w.cache.get("s7_foc")
	if c != null and int(c[0]) == w.tick:
		return c[1]
	var m := {}
	for id in S.ids:
		var u = w.entities.get(int(id))
		if u == null:
			continue
		var t := int(u.get("target", -1))
		if t >= 0:
			m[t] = int(m.get(t, 0)) + 1
	w.cache["s7_foc"] = [w.tick, m]
	return m


static func _is_machine(t: Dictionary) -> bool:
	return (R().get("machine_factions", ["machine"]) as Array).has(String(Content.unit(String(t.def)).get("faction", "")))


## Target class: drone, vehicle (vehicles, walkers, heavy armour), heavy_inf (crew-served weapons, AT, snipers,
## leaders), inf.
static func _tclass(w: SimWorld, t: Dictionary) -> String:
	if SimWorld.Counterdrone.is_drone(w, t):
		return "drone"
	var d := Content.unit(String(t.def))
	if String(d.get("move_class", "foot")) != "foot" or String(d.get("armor", "")) == "heavy":
		return "vehicle"
	var id := String(t.def)
	for k in ["at_", "_at", "mg", "sniper", "rpg", "officer", "mortar", "heavy"]:
		if id.contains(k):
			return "heavy_inf"
	return "inf"


## Target choice from the guard net (see the section header). Only while holding / idle / on an attack-move halt.
static func _aim(w: SimWorld, S: Dictionary, e: Dictionary, _job: Dictionary, F: Dictionary) -> void:
	if bool(e.get("moving", false)) or w.tick < int(e.get("s7_rl", 0)):
		return
	var ot := String(e.order.get("type", "idle"))
	if ot != "hold" and ot != "idle" and ot != "attack_move":
		return
	var net := _net(w, S, F)
	if net.is_empty():
		return
	var Cb = SimWorld.Combat
	var s: Dictionary = Cb.stats(e)
	if String(s.get("weapon", "")) == "":
		return
	var rng := float(s.range) * range_mult(w, e, s)
	var T := _tac()
	var pr: Dictionary = T.get("prio", {})
	var pf: Dictionary = (T.get("pref", {}) as Dictionary).get(String(e.s7), {})
	var half := deg_to_rad(float(T.get("sector_half_deg", 60.0)))
	var hd = e.get("f7_hd")
	var foc := _focus(w, S)
	var fw := float(T.get("focus", 0.25))
	var best := -1
	var bs := 0.0
	for tid in net:
		var t = w.entities.get(int(tid))
		if t == null or not Cb.can_target(s, t):
			continue
		var d: float = Cb.dist_to(e.pos, t)
		if d > rng or d < float(s.get("min_range", 0.0)):
			continue
		var c := _tclass(w, t)
		var sc := float(pr.get(c, 1.0)) * float(pf.get(c, 1.0))
		if c != "drone" and pf.has("machine") and _is_machine(t):
			sc *= float(pf.machine)
		if hd != null:
			var ang := absf(angle_difference(deg_to_rad(float(hd)), (Vector2(t.pos) - Vector2(e.pos)).angle()))
			sc *= float(T.get("in_sector", 1.5)) if ang <= half else float(T.get("out_sector", 0.6))
		sc *= 1.0 + fw * float(mini(int(foc.get(int(tid), 0)), 4))
		sc *= 1.5 - 0.5 * d / maxf(rng, 0.1)
		if sc > bs:
			bs = sc
			best = int(tid)
	if best >= 0 and int(e.get("target", -1)) != best:
		SimWorld.HotState.set_target(w, int(e.id), best)


## Magazine size of e's current weapon (0 = no magazine model: single-shot launchers reload per shot already).
static func _mag(e: Dictionary) -> int:
	var T := _tac()
	if bool(e.get("s7_sa", false)):
		return int(T.get("sidearm_mag", 15))
	return int((T.get("mag", {}) as Dictionary).get(String(e.get("s7", "")), 0))


## Reload: weapon down for reload_s (arm wounds slow it), magazine refilled; the event is the "reloading" call.
static func _reload(w: SimWorld, e: Dictionary, mag: int, tactical: bool) -> void:
	var T := _tac()
	var rs := float(T.get("sidearm_reload_s", 2.0)) if bool(e.get("s7_sa", false)) else float((T.get("reload_s", {}) as Dictionary).get(String(e.s7), 2.5))
	var t := ticks(rs / maxf(SimWorld.Wounds.reload_mult(e), 0.1))
	SimWorld.HotState.set_cd(w, int(e.id), t)
	e.s7_rl = w.tick + t
	e.s7_mg = mini(mag, int(e.ammo))
	var S = state(w)
	var bud := int(S.jobs.get(str(int(e.id)), {}).get("bud", -1)) if S != null else -1
	w.emit("SentinelReloading", {"id": int(e.id), "owner": int(e.owner), "buddy": bud, "tactical": tactical})


## Under alarm: a man reloading in the open first gets into cover; a low magazine with nothing to shoot and the
## buddy not reloading gets a tactical reload.
static func _reload_check(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary, tp) -> void:
	if e.has("garrisoned_in") or bool(e.get("moving", false)):
		return
	if w.tick < int(e.get("s7_rl", 0)):
		_settle(w, S, e, job, tp)
		return
	var mag := _mag(e)
	if mag <= 1:
		return
	var mg := int(e.get("s7_mg", mag))
	if mg < int(float(mag) * float(_tac().get("tac_reload_frac", 0.34))) and int(e.get("target", -1)) < 0 and int(e.get("ammo", 0)) > mg:
		var b = _bud(w, S, e, job)
		if b == null or w.tick >= int(b.get("s7_rl", 0)):
			_reload(w, e, mag, true)


static func _caring(w: SimWorld, uid: int) -> bool:
	var st = w.sys_state.get("wounds")
	return st != null and ((st.care as Dictionary).has(uid) or (st.care as Dictionary).has(str(uid)))


static func _being_treated(w: SimWorld, cid: int) -> bool:
	var st = w.sys_state.get("wounds")
	if st == null:
		return false
	for v in (st.care as Dictionary).values():
		if int(v.get("c", -1)) == cid:
			return true
	return false


## The downed buddy of e, else -1: his own buddy, or a downed Sentinel within drag_r * 2 whose job still names e as
## his buddy (the board re-pairs the living every plan; the man who went down keeps the partner he went down beside).
static func _down_bud(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary) -> int:
	var Wd = SimWorld.Wounds
	var bd := int(job.get("bud", -1))
	var b = w.entities.get(bd) if bd >= 0 else null
	if b != null and Wd.is_down(b):
		return bd
	var dc = w.cache.get("s7_down")   # downed Sentinels, refreshed once per tick (runtime cache)
	if dc == null or int(dc[0]) != w.tick:
		var dn := []
		for id in S.ids:
			var u = w.entities.get(int(id))
			if u != null and Wd.is_down(u):
				dn.append(int(id))
		dc = [w.tick, dn]
		w.cache["s7_down"] = dc
	var me := int(e.id)
	var r := float(_tac().get("drag_r", 4.0)) * 2.0
	for id in dc[1]:
		var c = w.entities.get(int(id))
		if c != null and int(S.jobs.get(str(id), {}).get("bud", -1)) == me and Vector2(c.pos).distance_to(e.pos) <= r:
			return int(id)
	return -1


## Casualty drill: the buddy drags a downed partner to cover away from the threat, then gives buddy aid.
static func _casualty_drill(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary) -> bool:
	var bd := _down_bud(w, S, e, job)
	if bd < 0:
		return false
	var b = w.entities.get(bd)
	var Wd = SimWorld.Wounds
	if b == null or int(b.owner) != int(e.owner) or not Wd.is_down(b) or b.has("evac_by") or b.has("wdby") or not Wd._can_care(e):
		return false
	if _being_treated(w, bd):
		return false
	if int(job.get("drg", -1)) == bd:
		if Wd._needs_care(b):
			Wd.start_care(w, e, b, "buddy")
			return true
		return false
	var F := _fac_of(w, job)
	var th = threat(w, int(F.id)) if not F.is_empty() else null
	var tp = th[0] if th != null else null
	var bp: Vector2 = b.pos
	var dr := float(_tac().get("drag_r", 4.0))
	var away := bp
	if tp != null and Vector2(tp).distance_to(bp) > 0.1:
		away = bp + (bp - Vector2(tp)).normalized() * dr
	elif not F.is_empty():
		away = bp + (_home(w, F) - bp).limit_length(dr)
	var p := _cover_near(w, b, away, 2, null)
	job["drg"] = bd
	job.erase("hold")
	_set_gait(w, e, 3)   # "man down": he sprints to his partner
	Wd.start_care(w, e, b, "drag", p)
	w.emit("SentinelCasualtyDrill", {"id": bd, "by": int(e.id), "owner": int(e.owner), "to": p})
	return true


## Mender on a "casualty" job: comes forward (duck-run, sprint under fire) and treats the casualty.
static func _casualty_job(w: SimWorld, S: Dictionary, e: Dictionary, job: Dictionary) -> void:
	var Wd = SimWorld.Wounds
	var c = w.entities.get(int(job.get("uid", -1)))
	if c == null or c.has("evac_by") or (not Wd.is_down(c) and not Wd._needs_care(c)):
		S.jobs[str(int(e.id))] = {"k": "auto", "fac": int(job.get("fac", -1))}
		return
	if Vector2(c.pos).distance_to(e.pos) > 1.3:
		if not bool(e.get("moving", false)) or job.get("g") == null or Vector2(job.g).distance_to(c.pos) > 1.0:
			_set_gait(w, e, 3)   # SENT7-4: the Mender answers "man down" at a run (minimum time exposed, both cases)
			_go(w, e, job, Vector2(c.pos), "move")
		return
	if not _caring(w, int(e.id)) and Wd._can_care(e) and Wd._needs_care(c):
		Wd.start_care(w, e, c, "medic")
		job["tr"] = true
		w.emit("SentinelMenderTreats", {"id": int(c.id), "by": int(e.id), "owner": int(e.owner)})
