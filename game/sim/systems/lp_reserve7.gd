extends RefCounted
## LpReserve7 (owner: LPRES7). G7_REFERENCE 13.9c-34: in Last Protocol the pre-built facility keeps its normal starting
## garrison and units PLUS a reserve of rules.g7_lpreserve.size (100) Sentinels held inside the Sentinel Barracks
## (garrisoned, not on the map). The reserve filters out in tiers as the fighting grows heavier:
##   1 POSTS  a post / roster Sentinel killed -> one reserve man (same type when there is one) joins the duty roster and
##            the facility job board puts him on the vacant post (one-for-one, per_step a cadence);
##   2 QRF    a wall sector or the gate under heavy attack (sector pressure >= sector.heavy) -> a quick-reaction squad
##            of 4-8 (buddy pairs) bounds from cover to that sector (Sentinels7 stand-to drill: bound / cover / settle,
##            withdraw by bounds when outmatched); more squads while the sector's need exceeds the men committed;
##   3 SURGE  a real breach (enemies inside the walls, pressure >= breach.min_p) -> a big counter-attack surge (Sentinels7
##            QRF drill: turn out pair by pair, close with the deepest intruder) to throw them out;
##   LAST STAND  about 20% of the reserve (last_stand.frac) is always held back and committed only when the command
##            centre / core rooms are threatened (enemy inside last_stand.core_rect + core_r): it holds the core doors.
## Released men come back into the barracks (rest, refill ammo) when their sector has been quiet for quiet_s.
## Control: automatic by default; the barracks card (presentation/ui7/lpreserve_card.gd) sends lpres_release (a squad
## to the most pressed sector), lpres_recall (everyone back, auto release held recall_hold_s) and lpres_auto (on / off).
## Replenish: a finite pool with a slow paid trickle (trickle.every_s, the barracks' own training cost) back up to
## size; it stops when the barracks is gone (the reserve then joins the duty roster; the last stand holds the core).
## Pressure comes from the Sentinels7 guard net (Sentinels7._net: enemies the owner sees in the compound + net_r, only
## while Sentinels7.threat is up): weight clamp(max_hp / hp_ref) per enemy, by side of the compound (n / e / s / w),
## inside the walls ("in") and at the core ("core").
## Cost: one evaluation per facility every every_s (staggered by facility id); no per-tick scans; ids not in
## w.entities are skipped (SimIndex liveness rule). Sentinels7._role never plans a reserve member (st.m) on the board.
## Never touches CN strike teams / spec ops (13.9c-29): it only ever moves the Sentinels it spawned.
## State (saved, hashed): w.sys_state.lpres7 = {ver, m {"uid": fac}, facs {"fac": Rr}}; created only by seed (Last
## Protocol's fill_facility). Skirmish: no state, tick returns after one dictionary lookup.
## The barracks of a reserve gets b.g7_xs = barracks_extra_slots (Garrison.free_slots / cap_of): 120 -> 140 in LP.
## Every number PROVISIONAL (content/g7/defs_g7_lpreserve.json).

const KEY := "lpres7"
const VER := 1
const SECS := ["n", "e", "s", "w"]
const TYPES := ["warden", "marksman", "gunner", "bulwark", "lancer", "arc", "mender", "bearer"]
const TIER_NAMES := ["CALM", "POSTS", "QRF", "SURGE", "LAST STAND"]
const S7 = preload("res://sim/systems/sentinels7.gd")

## Measurement toggle (never saved): false -> seed() creates no reserve (LP then behaves as before LPRES7).
static var enabled := true
static var _gar = null
static var _mv = null
static var _cf = null


static func _garrison():
	if _gar == null:
		_gar = load("res://sim/systems/garrison.gd")
	return _gar


static func _movement():
	if _mv == null:
		_mv = load("res://sim/systems/movement.gd")
	return _mv


static func _cnfac():
	if _cf == null:
		_cf = load("res://sim/systems/cn_facility.gd")
	return _cf


static func R() -> Dictionary:
	return Content.rules().get("g7_lpreserve", {})


static func ticks(sec: float) -> int:
	return maxi(roundi(sec * SimWorld.TICK_RATE), 1)


static func state(w: SimWorld):
	return w.sys_state.get(KEY)


static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		st = {"ver": VER, "m": {}, "facs": {}}
		w.sys_state[KEY] = st
	return st


## Reserve record of facility fac ({} when it has none).
static func rec(w: SimWorld, fac: int) -> Dictionary:
	var st = state(w)
	return st.facs.get(str(fac), {}) if st != null else {}


## True when unit uid belongs to a barracks reserve (Sentinels7 never plans it on the job board).
static func is_member(w: SimWorld, uid: int) -> bool:
	var st = state(w)
	return st != null and (st.m as Dictionary).has(str(uid))


## Facilities of side fid that hold a reserve (ascending ids).
static func reserves_of(w: SimWorld, fid: int) -> Array:
	var out := []
	var st = state(w)
	if st == null:
		return out
	for k in st.facs:
		if int(st.facs[k].owner) == fid:
			out.append(int(k))
	out.sort()
	return out


# ================================================================ type mix
## Largest-remainder split of n over counts {key: weight} (keys in TYPES order, then sorted).
static func _split(counts: Dictionary, n: int) -> Dictionary:
	var keys := _ordered(counts.keys())
	var tot := 0
	for k in keys:
		tot += int(counts[k])
	var out := {}
	if tot <= 0 or n <= 0:
		return out
	var used := 0
	var rems := []
	for i in keys.size():
		var k: String = keys[i]
		var num := n * int(counts[k])
		var f := num / tot
		out[k] = f
		used += f
		rems.append([num - f * tot, i])   # integer remainders: exact, platform-independent
	rems.sort_custom(func(a, b) -> bool: return int(a[0]) > int(b[0]) if int(a[0]) != int(b[0]) else int(a[1]) < int(b[1]))
	var j := 0
	while used < n and j < rems.size():
		out[keys[int(rems[j][1])]] += 1
		used += 1
		j += 1
	return out


static func _ordered(ks: Array) -> Array:
	var out := []
	for t in TYPES:
		if ks.has(t):
			out.append(t)
	var rest := []
	for k in ks:
		if not TYPES.has(String(k)):
			rest.append(String(k))
	rest.sort()
	out.append_array(rest)
	return out


## Reserve type mix of n Sentinels: rules.g7_sentinels.start.force proportions without exclude_types (the bearer).
static func mix(n: int) -> Dictionary:
	var ex: Array = R().get("exclude_types", ["bearer"])
	var cnt := {}
	for k in S7.R().get("start", {}).get("force", []):
		if not ex.has(String(k)):
			cnt[String(k)] = int(cnt.get(String(k), 0)) + 1
	return _split(cnt, n)


# ================================================================ seeding (Last Protocol fill_facility)
static func _barracks(w: SimWorld, F: Dictionary):
	var b = w.entities.get(int(F.get("bar", -1)))
	if b != null and b.kind == "building" and String(b.def) == "cn_sentinel_barracks":
		return b
	for pid in F.get("parts", []):
		var p = w.entities.get(int(pid))
		if p != null and String(p.def) == "cn_sentinel_barracks":
			return p
	return null


static func _home(b: Dictionary) -> Vector2:
	var sz := float(b.get("size", 2))
	return Vector2(b.cell) + Vector2(sz * 0.5, sz + 0.6)


static func _rest_job(fac: int, bid: int, home: Vector2) -> Dictionary:
	return {"k": "rest", "j": "lpr:in", "fac": fac, "bid": bid, "pos": home, "in": false}


## Puts the reserve into facility F's barracks (Last Protocol only: LpSetup.fill_facility). Returns the new unit ids.
static func seed(w: SimWorld, F: Dictionary) -> Array:
	var out := []
	if F.is_empty() or not enabled:
		return out
	var fac := int(F.id)
	var fid := int(F.owner)
	var st := _st(w)
	if st.facs.has(str(fac)):
		return out
	var pre := S7.prefix(w, fid)
	var b = _barracks(w, F)
	if pre == "" or b == null:
		return out
	var r := R()
	var size := int(r.get("size", 100))
	b.g7_xs = int(r.get("barracks_extra_slots", 20))
	var m := mix(size)
	var ls := _split(m, roundi(float(size) * float(r.get("last_stand", {}).get("frac", 0.2))))
	var Rr := {"fac": fac, "owner": fid, "bar": int(b.id), "size": size, "ls_n": 0, "auto": true, "hold_u": -1,
		"mem": {}, "sq": {}, "nsq": 0, "ros": [], "need": [], "cd": {}, "bcd": -1, "lp": {}, "p": {}, "tier": 0, "tier_max": 0,
		"post_t": -100000, "rel": {"post": 0, "qrf": 0, "surge": 0, "ls": 0, "man": 0}, "lost": 0, "trained": 0,
		"tr_at": w.tick + ticks(float(r.get("trickle", {}).get("every_s", 45.0))), "gone": false}
	st.facs[str(fac)] = Rr
	var home := _home(b)
	for k in _ordered(m.keys()):
		for i in int(m[k]):
			var uid := _spawn_in(w, Rr, String(k), "l" if i < int(ls.get(k, 0)) else "r")
			if uid >= 0:
				out.append(uid)
	Rr.ls_n = 0
	for k in ls:
		Rr.ls_n += int(ls[k])
	w.emit("LpReserveSeeded", {"fac": fac, "owner": fid, "barracks": int(b.id), "units": out.size(), "last_stand": int(Rr.ls_n)})
	return out


## Spawns one reserve Sentinel of type kind straight into the barracks (group "r" reserve / "l" last stand).
static func _spawn_in(w: SimWorld, Rr: Dictionary, kind: String, grp: String) -> int:
	var fid := int(Rr.owner)
	var b = w.entities.get(int(Rr.bar))
	var def_id := S7.prefix(w, fid) + kind
	if b == null or Content.unit(def_id).is_empty():
		return -1
	var home := _home(b)
	var mv = _movement()
	var team := S7._team(w, fid)
	var c: Vector2i = w.cell_of(home)
	if not mv.is_passable(w, c, "foot", team):
		c = mv.nearest_free_cell(w, c, "foot", team)
	var uid := w.spawn_unit(def_id, fid, Vector2(c) + Vector2(0.5, 0.5))
	var e: Dictionary = w.entities[uid]
	e.order = {"type": "idle"}
	var job := _rest_job(int(Rr.fac), int(b.id), home)
	S7.enlist(w, e, job)
	if _garrison().place_inside(w, int(b.id), uid) == "":
		job["in"] = true
	Rr.mem[str(uid)] = {"g": grp, "st": "in", "sq": -1, "t": kind}
	_st(w).m[str(uid)] = int(Rr.fac)
	return uid


# ================================================================ system
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get(KEY)
	if st == null:
		return
	var ev := ticks(float(R().get("every_s", 1.0)))
	var ks := []
	for k in st.facs:
		ks.append(int(k))
	ks.sort()
	for k in ks:
		if (w.tick + k) % ev == 0:
			var tq := Time.get_ticks_usec() if SimWorld.SimIndex.profiling else 0
			_step(w, st, st.facs[str(k)])
			if SimWorld.SimIndex.profiling:
				SimWorld.SimIndex.pt("lpres7.step", tq)


static func _fit(w: SimWorld, e: Dictionary) -> bool:
	return float(e.hp) >= float(R().get("fit_frac", 0.6)) * float(e.max_hp) and not SimWorld.Wounds.is_down(e) and not S7.emp_down(w, e)


static func _sorted_keys(d: Dictionary) -> Array:
	var ks := []
	for k in d:
		ks.append(int(k))
	ks.sort()
	return ks


static func _step(w: SimWorld, st: Dictionary, Rr: Dictionary) -> void:
	var S = S7.state(w)
	if S == null:
		return
	var fac := int(Rr.fac)
	var fid := int(Rr.owner)
	var F: Dictionary = _cnfac().fac(w, fac)
	var b = w.entities.get(int(Rr.bar))
	var bar_ok: bool = b != null and b.kind == "building" and int(b.owner) == fid
	var home: Vector2 = _home(b) if bar_ok else Vector2.ZERO
	# ---- membership upkeep: the dead leave, the returned are back in reserve, withdrawn / timed-out men come home
	var av := {"r": [], "l": []}
	var sqn := {}   # squad id -> live, standing men in it
	for uid in _sorted_keys(Rr.mem):
		var k := str(uid)
		var M: Dictionary = Rr.mem[k]
		var e = w.entities.get(uid)
		if e == null or e.kind != "unit" or int(e.owner) != fid:
			Rr.mem.erase(k)
			st.m.erase(k)
			Rr.lost += 1
			continue
		var job: Dictionary = S.jobs.get(k, {})
		var jk := String(job.get("k", "free"))
		if jk == "ammo":
			continue   # a Sentinels7 ammo run: the job comes back to us afterwards
		if jk == "player":
			M.st = "own"
			continue
		var inside: bool = bar_ok and e.has("garrisoned_in") and int(e.garrisoned_in) == int(Rr.bar)
		var mine := String(job.get("j", "")).begins_with("lpr:")
		if String(M.st) == "out" or String(M.st) == "own":
			if not mine or jk == "auto" or jk == "free":   # withdrew by bounds / player order timed out: back to the barracks
				_send_home(w, S, Rr, k, M, bar_ok, home)
			elif not SimWorld.Wounds.is_down(e):
				sqn[int(M.sq)] = int(sqn.get(int(M.sq), 0)) + 1
			continue
		if not bar_ok:
			continue
		if inside:
			if String(M.st) != "in":
				M.st = "in"   # back in: rest and refill
				var am := int(Content.unit(String(e.def)).get("ammo_max", 0))
				if e.has("ammo") and am > 0:
					e.ammo = am
					e.s7_sa = false
			if not mine or jk != "rest":
				S.jobs[k] = _rest_job(fac, int(Rr.bar), home)
				S.jobs[k]["in"] = true
			if _fit(w, e):
				av[String(M.g)].append(uid)
		elif not mine or jk != "rest":
			_send_home(w, S, Rr, k, M, bar_ok, home)
	# ---- squads: drop the empty ones
	for q in _sorted_keys(Rr.sq):
		if not sqn.has(q):
			var any := false
			for k in Rr.mem:
				if int(Rr.mem[k].sq) == q and (String(Rr.mem[k].st) == "out" or String(Rr.mem[k].st) == "own"):
					any = true
					break
			if not any:
				Rr.sq.erase(str(q))
	# ---- barracks lost: the reserve joins the duty roster, the last stand holds the core
	if not bar_ok:
		if not bool(Rr.gone):
			Rr.gone = true
			_dissolve(w, S, Rr, F)
		return
	# ---- pressure from the guard net
	var P := _pressure(w, S, Rr, F)
	var r := R()
	var quiet := ticks(float(r.get("quiet_s", 20.0)))
	# ---- tier 1 bookkeeping: roster casualties (dead post / duty Sentinels) since the last step
	_roster(w, S, Rr)
	if bool(Rr.auto):
		var held := w.tick < int(Rr.hold_u)
		# LAST STAND: only when the core is threatened
		if float(P.core) > 0.0 and not av.l.is_empty():
			_release(w, S, Rr, F, av.l, "l", "core", P)
			av.l = []
		# 3 SURGE: a real breach
		var B: Dictionary = r.get("breach", {})
		var brk: bool = float(P.get("in", 0.0)) >= float(B.get("min_p", 2.0)) or (float(P.get("in", 0.0)) > 0.0 and _cnfac().secure_state(w, fac) == "breached")
		if brk and w.tick >= int(Rr.bcd) and not av.r.is_empty():
			var com := _committed(Rr, sqn, "b", "")
			var need := ceili(float(P["in"]) * float(B.get("mult", 2.0))) - com
			if com == 0:
				need = maxi(need, int(B.get("min", 12)))
			if need > 0:
				_release(w, S, Rr, F, _pick(Rr, av.r, mini(need, av.r.size()), "in", P), "b", "in", P)
				Rr.bcd = w.tick + ticks(float(B.get("cd_s", 10.0)))
		# 2 QRF: wall sectors / gate under heavy attack, heaviest first
		if not held:
			var C: Dictionary = r.get("sector", {})
			var order := SECS.duplicate()
			order.sort_custom(func(a, c) -> bool: return float(P[a]) > float(P[c]) if float(P[a]) != float(P[c]) else SECS.find(a) < SECS.find(c))
			for sec in order:
				if float(P[sec]) < float(C.get("heavy", 6.0)) or w.tick < int(Rr.cd.get(sec, -1)) or av.r.size() < 2:
					continue
				var need := ceili(float(P[sec]) * float(C.get("men_per_p", 1.0))) - _committed(Rr, sqn, "q", sec)
				if need < 2:
					continue
				var n := mini(clampi(need, int(C.get("squad_min", 4)), int(C.get("squad_max", 8))), av.r.size())
				_release(w, S, Rr, F, _pick(Rr, av.r, n, sec, P), "q", sec, P)
				Rr.cd[sec] = w.tick + ticks(float(C.get("cd_s", 12.0)))
		# 1 POSTS: one-for-one replacements for dead roster Sentinels
		var per := int(r.get("post", {}).get("per_step", 2))
		while per > 0 and not (Rr.need as Array).is_empty() and not av.r.is_empty():
			var want := String(Rr.need[0])
			Rr.need.remove_at(0)
			var uid := -1
			for u in av.r:
				if String(Rr.mem[str(u)].t) == want:
					uid = int(u)
					break
			if uid < 0:
				uid = int(av.r[0])
			av.r.erase(uid)
			_to_board(w, S, Rr, uid)
			per -= 1
		# recall squads whose sector has been quiet
		for q in _sorted_keys(Rr.sq):
			var Q: Dictionary = Rr.sq[str(q)]
			if String(Q.t) == "m":
				continue   # a squad the player released stays out until he recalls it
			if w.tick - int(Rr.lp.get(String(Q.sec), -100000)) >= quiet and w.tick - int(Q.at) >= quiet:
				_recall_squad(w, S, Rr, q, home, "quiet")
	# ---- trickle: slow paid replacements up to size
	var T: Dictionary = r.get("trickle", {})
	if w.tick >= int(Rr.tr_at):
		Rr.tr_at = w.tick + ticks(float(T.get("every_s", 45.0)))
		_trickle(w, Rr, T)
	# ---- tier shown on the card
	var tier := 0
	for q in Rr.sq:
		match String(Rr.sq[q].t):
			"l":
				tier = maxi(tier, 4)
			"b":
				tier = maxi(tier, 3)
			"q", "m":
				tier = maxi(tier, 2)
	if tier == 0 and w.tick - int(Rr.post_t) < quiet:
		tier = 1
	Rr.tier = tier
	Rr.tier_max = maxi(int(Rr.tier_max), tier)


## Sector of a compound-local point outside the inner walls.
static func _sector(lp: Vector2, cs: float) -> String:
	var dx := lp.x - cs * 0.5
	var dy := lp.y - cs * 0.5
	if absf(dy) >= absf(dx):
		return "n" if dy < 0.0 else "s"
	return "w" if dx < 0.0 else "e"


static func _weight(t: Dictionary) -> float:
	var W: Dictionary = R().get("weights", {})
	return clampf(float(t.get("max_hp", 100.0)) / float(W.get("hp_ref", 100.0)), float(W.get("min", 0.5)), float(W.get("max", 8.0)))


## Pressure by sector from the Sentinels7 guard net; also stores Rr.p, Rr.lp (last pressed tick) and Rr.cen.
static func _pressure(w: SimWorld, S: Dictionary, Rr: Dictionary, F: Dictionary) -> Dictionary:
	var P := {"n": 0.0, "e": 0.0, "s": 0.0, "w": 0.0, "in": 0.0, "core": 0.0}
	var cen := {}
	var hv := {}
	if F.is_empty():
		Rr.p = P
		return P
	var fac := int(F.id)
	if S7.threat(w, fac) != null:
		var cs := float(_cnfac().conf().get("compound", 28))
		var o := Vector2(_cnfac().origin(F))
		var L: Dictionary = R().get("last_stand", {})
		var cr: Array = L.get("core_rect", [2, 2, 11, 15])
		var core := Rect2(float(cr[0]), float(cr[1]), float(cr[2]), float(cr[3])).grow(float(L.get("core_r", 3.0)))
		var inner := Rect2(1.0, 1.0, cs - 2.0, cs - 2.0)
		for tid in S7._net(w, S, F):
			var t = w.entities.get(int(tid))
			if t == null or t.kind != "unit" or not w.is_enemy(int(Rr.owner), int(t.owner)):
				continue   # SimIndex liveness: the net is cached for net_every ticks
			var wt := _weight(t)
			var lp: Vector2 = Vector2(t.pos) - o
			if core.has_point(lp):
				P.core += wt
			if inner.has_point(lp):
				P["in"] += wt
				continue
			var sec := _sector(lp, cs)
			P[sec] += wt
			hv[sec] = maxf(float(hv.get(sec, 0.0)), wt)
			var c: Array = cen.get(sec, [0.0, 0.0, 0.0])
			cen[sec] = [float(c[0]) + lp.x * wt, float(c[1]) + lp.y * wt, float(c[2]) + wt]
	for k in P:
		P[k] = snappedf(float(P[k]), 0.01)
		if float(P[k]) > 0.0:
			Rr.lp[k] = w.tick
	var cc := {}
	for sec in cen:
		var c: Array = cen[sec]
		cc[sec] = [snappedf(float(c[0]) / float(c[2]), 0.01), snappedf(float(c[1]) / float(c[2]), 0.01)]
	Rr.cen = cc
	Rr.hv = hv
	Rr.p = P
	return P


## Live standing men of type-t squads (sector sec, "" = any) out now.
static func _committed(Rr: Dictionary, sqn: Dictionary, t: String, sec: String) -> int:
	var n := 0
	for q in Rr.sq:
		var Q: Dictionary = Rr.sq[q]
		var qt := String(Q.t)
		if (qt == t or (t == "q" and qt == "m")) and (sec == "" or String(Q.sec) == sec):
			n += int(sqn.get(int(q), 0))
	return n


## Duty-roster casualties: Sentinels of the owner outside the reserve (not bearers) that were alive at the last step and
## are gone now queue a one-for-one replacement of their type (Rr.need).
static func _roster(w: SimWorld, S: Dictionary, Rr: Dictionary) -> void:
	var fid := int(Rr.owner)
	var fac := int(Rr.fac)
	var st := _st(w)
	for p in Rr.ros:
		var e = w.entities.get(int(p[0]))
		if e == null or int(e.owner) != fid:
			if (Rr.need as Array).size() < int(R().get("post", {}).get("queue_max", 40)):
				Rr.need.append(String(p[1]))
	var cur := []
	for id in S.ids:
		var uid := int(id)
		var e = w.entities.get(uid)
		if e == null or int(e.owner) != fid or st.m.has(str(uid)) or String(e.get("s7", "")) == "bearer":
			continue
		var jf := int(S.jobs.get(str(uid), {}).get("fac", -1))
		if jf == fac or jf < 0:
			cur.append([uid, String(e.s7)])
	Rr.ros = cur


## Picks n men from avail (ascending ids) for a squad: the squad template for its job (armour-heavy sectors put the
## Lancers first), then anyone. Removes them from avail.
static func _pick(Rr: Dictionary, avail: Array, n: int, sec: String, P: Dictionary) -> Array:
	var C: Dictionary = R().get("sector", {})
	var tpl: Array = C.get("template", ["warden", "gunner", "warden", "lancer", "marksman", "bulwark", "mender", "warden"])
	if sec == "in":
		tpl = R().get("breach", {}).get("template", tpl)
	elif float(Rr.get("hv", {}).get(sec, 0.0)) >= float(C.get("armour_w", 4.0)):
		tpl = C.get("template_armour", tpl)
	var out := []
	for k in tpl:
		if out.size() >= n:
			break
		for u in avail:
			if String(Rr.mem[str(u)].t) == String(k) and not out.has(int(u)):
				out.append(int(u))
				break
	for u in avail:
		if out.size() >= n:
			break
		if not out.has(int(u)):
			out.append(int(u))
	for u in out:
		avail.erase(u)
	return out


## Goal of pair slot i of n men for sector sec: on the wall-walk of that face (slid towards the attackers' centre of
## mass), the gate staging yard for the south face, the core doors for the last stand. World position, passable cell.
static func _goal(w: SimWorld, Rr: Dictionary, F: Dictionary, sec: String, i: int, n: int) -> Vector2:
	var cs := float(_cnfac().conf().get("compound", 28))
	var C: Dictionary = R().get("sector", {})
	var pts: Dictionary = C.get("points", {})
	var np := maxi((n + 1) / 2, 1)
	var pi := i / 2
	var gap := float(C.get("pair_gap", 2.5))
	var along := (float(pi) - float(np - 1) * 0.5) * gap + (0.9 if i % 2 == 1 else 0.0)
	var lp := Vector2(cs * 0.5, cs * 0.5)
	if sec == "core":
		var cp: Array = R().get("last_stand", {}).get("points", [[4.5, 7.5]])
		var p: Array = cp[pi % cp.size()]
		lp = Vector2(float(p[0]), float(p[1])) + Vector2(0.9 if i % 2 == 1 else 0.0, 0.0)
	else:
		var p: Array = pts.get(sec, [cs * 0.5, cs * 0.5])
		lp = Vector2(float(p[0]), float(p[1]))
		var cc = Rr.get("cen", {}).get(sec)
		var lo := float(C.get("slide_min", 3.0))
		var hi := cs - lo
		match sec:
			"n", "s":
				if cc != null and sec == "n":
					lp.x = clampf(float(cc[0]), lo, hi)
				lp.x = clampf(lp.x + along, 1.5, cs - 1.5)
			"e", "w":
				if cc != null:
					lp.y = clampf(float(cc[1]), lo, hi)
				lp.y = clampf(lp.y + along, 1.5, cs - 1.5)
	var wp := Vector2(_cnfac().origin(F)) + lp
	var mv = _movement()
	var team := S7._team(w, int(Rr.owner))
	var c: Vector2i = w.cell_of(wp)
	if not w.in_bounds(c) or not mv.is_passable(w, c, "foot", team):
		c = mv.nearest_free_cell(w, c, "foot", team)
	return Vector2(c) + Vector2(0.5, 0.5)


## Sends men out as squad type t ("q" QRF to sector sec, "b" breach surge, "l" last stand, "m" manual QRF).
static func _release(w: SimWorld, S: Dictionary, Rr: Dictionary, F: Dictionary, men: Array, t: String, sec: String, _P: Dictionary) -> int:
	if men.is_empty() or F.is_empty():
		return -1
	var fac := int(Rr.fac)
	var q := int(Rr.nsq) + 1
	Rr.nsq = q
	Rr.sq[str(q)] = {"t": t, "sec": sec, "at": w.tick}
	var bar := int(Rr.bar)
	var b = w.entities.get(bar)
	var home: Vector2 = _home(b) if b != null else Vector2.ZERO
	for i in men.size():
		var uid := int(men[i])
		var mate := -1
		if i % 2 == 0 and i + 1 < men.size():
			mate = int(men[i + 1])
		elif i % 2 == 1:
			mate = int(men[i - 1])
		var job: Dictionary
		if t == "b":   # Sentinels7 QRF drill: turn out pair by pair, close with the deepest intruder, back in when clear
			job = {"k": "qrf", "j": "lpr:%d" % q, "fac": fac, "bid": bar, "pos": home, "in": true, "bud": mate}
		else:          # Sentinels7 stand-to drill: bound from cover to the goal, settle in cover, withdraw by bounds
			job = {"k": "standto", "j": "lpr:%d" % q, "fac": fac, "bid": -1, "pos": _goal(w, Rr, F, sec, i, men.size()), "in": false,
				"bud": mate, "hand": true}
		S.jobs[str(uid)] = job
		var M: Dictionary = Rr.mem[str(uid)]
		M.st = "out"
		M.sq = q
	var tag := String({"q": "qrf", "b": "surge", "l": "ls", "m": "man"}[t])
	Rr.rel[tag] = int(Rr.rel.get(tag, 0)) + men.size()
	w.emit("LpReserveRelease", {"fac": fac, "owner": int(Rr.owner), "tier": tag, "sector": sec, "squad": q, "units": men.duplicate()})
	return q


static func _send_home(w: SimWorld, S: Dictionary, Rr: Dictionary, k: String, M: Dictionary, bar_ok: bool, home: Vector2) -> void:
	if not bar_ok:
		return
	var job := _rest_job(int(Rr.fac), int(Rr.bar), home)
	var cur: Dictionary = S.jobs.get(k, {})
	if String(cur.get("k", "")) != "rest":
		job["hand"] = true
	S.jobs[k] = job
	M.st = "ret"
	M.sq = -1


static func _recall_squad(w: SimWorld, S: Dictionary, Rr: Dictionary, q: int, home: Vector2, why: String) -> void:
	var ids := []
	for uid in _sorted_keys(Rr.mem):
		var M: Dictionary = Rr.mem[str(uid)]
		if int(M.sq) == q and (String(M.st) == "out" or String(M.st) == "own"):
			_send_home(w, S, Rr, str(uid), M, true, home)
			ids.append(uid)
	Rr.sq.erase(str(q))
	if not ids.is_empty():
		w.emit("LpReserveRecall", {"fac": int(Rr.fac), "owner": int(Rr.owner), "squad": q, "units": ids, "why": why})


## Tier 1: reserve man uid joins the duty roster; the facility job board puts him on the vacant post.
static func _to_board(w: SimWorld, S: Dictionary, Rr: Dictionary, uid: int) -> void:
	var k := str(uid)
	Rr.mem.erase(k)
	_st(w).m.erase(k)
	S.jobs[k] = {"k": "auto", "fac": int(Rr.fac)}
	S["call"] = true   # the board re-plans at once
	Rr.rel.post = int(Rr.rel.get("post", 0)) + 1
	Rr.post_t = w.tick
	(Rr.ros as Array).append([uid, String(w.entities[uid].s7)])
	w.emit("LpReserveRelease", {"fac": int(Rr.fac), "owner": int(Rr.owner), "tier": "post", "sector": "", "squad": -1, "units": [uid]})


## Barracks lost: reserve men join the duty roster; the last-stand group holds the core doors for good.
static func _dissolve(w: SimWorld, S: Dictionary, Rr: Dictionary, F: Dictionary) -> void:
	var ls := []
	for uid in _sorted_keys(Rr.mem):
		var M: Dictionary = Rr.mem[str(uid)]
		if String(M.g) == "l":   # ejected men read as player-owned (idle outside their post): the loss re-tasks them all
			if String(M.st) != "out" or int(M.sq) < 0 or String(Rr.sq.get(str(M.sq), {}).get("t", "")) != "l":
				ls.append(uid)
		else:
			_to_board(w, S, Rr, uid)
			Rr.rel.post -= 1   # not a post refill
	Rr.need = []
	if not ls.is_empty():
		_release(w, S, Rr, F, ls, "l", "core", {})
	w.emit("LpReserveBarracksLost", {"fac": int(Rr.fac), "owner": int(Rr.owner)})


## Slow paid trickle (one man per every_s while the reserve is below size): the type furthest below its share of the
## mix, paid at the barracks' own training cost x cost_mult; he goes straight into the barracks.
static func _trickle(w: SimWorld, Rr: Dictionary, T: Dictionary) -> void:
	var size := int(Rr.size)
	if Rr.mem.size() >= size:
		return
	var b = w.entities.get(int(Rr.bar))
	if b == null or _garrison().free_slots(w, b) <= 0:
		return
	var m := mix(size)
	var have := {}
	var nl := 0
	for k in Rr.mem:
		var M: Dictionary = Rr.mem[k]
		have[String(M.t)] = int(have.get(String(M.t), 0)) + 1
		if String(M.g) == "l":
			nl += 1
	var best := ""
	var bd := -1
	for k in _ordered(m.keys()):
		var d := int(m[k]) - int(have.get(k, 0))
		if d > bd:
			bd = d
			best = String(k)
	if best == "":
		return
	var def_id := S7.prefix(w, int(Rr.owner)) + best
	var cost := {}
	var pc: Dictionary = Content.production(def_id).get("cost", {})
	var cm := float(T.get("cost_mult", 1.0))
	for k in pc:
		cost[k] = roundi(float(pc[k]) * cm)
	if not w.spend(int(Rr.owner), cost, "lp_reserve_trickle"):
		return
	var uid := _spawn_in(w, Rr, best, "l" if nl < int(Rr.ls_n) else "r")
	if uid >= 0:
		Rr.trained += 1
		w.emit("LpReserveTrained", {"fac": int(Rr.fac), "owner": int(Rr.owner), "unit": uid, "type": best})


# ================================================================ commands (barracks card)
static func _rec_for(w: SimWorld, cmd: Dictionary) -> Dictionary:
	var st = state(w)
	if st == null:
		return {}
	var fid := int(cmd.get("issuer", -1))
	if cmd.has("building_id"):
		var bid := int(cmd.building_id)
		for k in st.facs:
			var Rr: Dictionary = st.facs[k]
			if (int(Rr.bar) == bid or int(Rr.fac) == bid) and int(Rr.owner) == fid:
				return Rr
		return {}
	var l := reserves_of(w, fid)
	return {} if l.is_empty() else st.facs[str(l[0])]


static func _avail(w: SimWorld, Rr: Dictionary, grp: String) -> Array:
	var out := []
	for uid in _sorted_keys(Rr.mem):
		var M: Dictionary = Rr.mem[str(uid)]
		var e = w.entities.get(uid)
		if e != null and String(M.g) == grp and String(M.st) == "in" and e.has("garrisoned_in") and int(e.garrisoned_in) == int(Rr.bar) and _fit(w, e):
			out.append(uid)
	return out


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var t := String(cmd.get("type", ""))
	if not ["lpres_release", "lpres_recall", "lpres_auto"].has(t):
		return "Unknown command."
	var Rr := _rec_for(w, cmd)
	if Rr.is_empty():
		return "Needs the Last Protocol barracks reserve."
	var b = w.entities.get(int(Rr.bar))
	if b == null:
		return "The Sentinel Barracks is gone."
	match t:
		"lpres_release":
			if _avail(w, Rr, "r").is_empty():
				return "No reserve Sentinels ready in the barracks."
		"lpres_recall":
			var out := false
			for k in Rr.mem:
				if ["out", "own"].has(String(Rr.mem[k].st)):
					out = true
					break
			if not out:
				return "No reserve Sentinels out."
		"lpres_auto":
			if not cmd.has("on"):
				return "Missing on."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if validate_command(w, cmd) != "":
		return
	var Rr := _rec_for(w, cmd)
	var S = S7.state(w)
	if S == null:
		return
	var F: Dictionary = _cnfac().fac(w, int(Rr.fac))
	var r := R()
	match String(cmd.type):
		"lpres_release":
			var P: Dictionary = Rr.get("p", {})
			var sec := "s"
			var bp := 0.0
			for s in SECS:
				if float(P.get(s, 0.0)) > bp:
					bp = float(P.get(s, 0.0))
					sec = s
			var av := _avail(w, Rr, "r")
			var n := mini(int(cmd.get("count", r.get("manual_n", 6))), av.size())
			_release(w, S, Rr, F, _pick(Rr, av, maxi(n, 1), sec, P), "m", sec, P)
		"lpres_recall":
			var home := _home(w.entities[int(Rr.bar)])
			for q in _sorted_keys(Rr.sq):
				_recall_squad(w, S, Rr, q, home, "order")
			for uid in _sorted_keys(Rr.mem):   # men the player took out by hand
				var M: Dictionary = Rr.mem[str(uid)]
				if String(M.st) == "out" or String(M.st) == "own":
					_send_home(w, S, Rr, str(uid), M, true, home)
			Rr.hold_u = w.tick + ticks(float(r.get("recall_hold_s", 20.0)))
		"lpres_auto":
			Rr.auto = bool(cmd.on)
			w.emit("LpReserveAuto", {"fac": int(Rr.fac), "owner": int(Rr.owner), "on": bool(cmd.on)})


# ================================================================ read API (card, tests, playtest)
## {fac, bar, size, total, in, field, ls, ls_in, auto, tier, tier_name, p, rel, trained, lost, need, squads, next_s, gone}
static func summary(w: SimWorld, fac: int) -> Dictionary:
	var Rr := rec(w, fac)
	if Rr.is_empty():
		return {}
	var n_in := 0
	var field := 0
	var ls := 0
	var ls_in := 0
	for uid in _sorted_keys(Rr.mem):
		var M: Dictionary = Rr.mem[str(uid)]
		var e = w.entities.get(uid)
		if e == null:
			continue
		var inside: bool = e.has("garrisoned_in") and int(e.garrisoned_in) == int(Rr.bar)
		if inside and String(M.st) == "in":
			n_in += 1
		else:
			field += 1
		if String(M.g) == "l":
			ls += 1
			if inside:
				ls_in += 1
	var sqs := []
	for q in _sorted_keys(Rr.sq):
		var Q: Dictionary = Rr.sq[str(q)]
		var c := 0
		for k in Rr.mem:
			if int(Rr.mem[k].sq) == q:
				c += 1
		sqs.append({"id": q, "t": String(Q.t), "sec": String(Q.sec), "n": c})
	return {"fac": int(Rr.fac), "bar": int(Rr.bar), "size": int(Rr.size), "total": n_in + field, "in": n_in, "field": field,
		"ls": ls, "ls_in": ls_in, "auto": bool(Rr.auto), "tier": int(Rr.tier), "tier_name": TIER_NAMES[clampi(int(Rr.tier), 0, 4)],
		"tier_max": int(Rr.tier_max), "p": (Rr.get("p", {}) as Dictionary).duplicate(), "rel": (Rr.rel as Dictionary).duplicate(),
		"trained": int(Rr.trained), "lost": int(Rr.lost), "need": (Rr.need as Array).size(), "squads": sqs,
		"next_s": maxf(0.0, float(int(Rr.tr_at) - w.tick) / float(SimWorld.TICK_RATE)), "gone": bool(Rr.gone)}
