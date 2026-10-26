extends RefCounted
## G6.1 Veterancy and traits (owner: REAL61). Not a SYSTEM_ORDER system: Morale.tick drives it
## (Veterancy.on_tick every tick for the event-driven XP, Veterancy.pass_update from Morale's realism pass).
## Rules: rules.g61_realism.veterancy / .traits (content/g6/rules_g61_realism.json, PROVISIONAL).
## Entity state (saved + hashed with the entity, only present once earned): e.xp (float, snapped 1/1024),
##   e.vet (rank index 0..4: green regular veteran elite hero). A unit without e.xp is green with 0 XP.
## XP sources (all from this tick's w.events, deterministic event order):
##   Damage {shooter, target, amount}: damage_xp x amount to the shooter; the target gone from w.entities by
##   now = a kill (kill_xp + kill_value_xp per 100 of the victim's cost, credited once per victim).
##   SectorCaptured {team}: objective_xp to that team's units within objective_radius of the sector centre.
##   Surviving combat: combat_xp per second while under fire (pass_update).
##   Officers: the company captain (company.captain) gets officer_share of every member's XP.
## Traits: pure functions of (w.seed_value, uid, def, rank), never stored, so saves and hashes are unaffected.
##   Leaders (is_officer defs, company leaders / e.rank_role) roll 1-2 leader traits; soldiers at veteran+ one
##   minor trait. AI general slots: slot_traits(w, fid, slot).
## Public API (CONTRACTS: fact realism.api): xp, rank, rank_name, add_xp, traits, has_trait, trait_weight,
##   slot_traits, slot_trait_weight, company_rep, acc_mult, supp_resist, reload_mult, morale_loss_mult.

const Q := 1.0 / 1024.0
const DEF_RANKS := ["green", "regular", "veteran", "elite", "hero"]

static var _rref = null      # Content.rules() dict the caches below were built from
static var _vr: Dictionary = {}
static var _tr: Dictionary = {}
static var _thr: Array = [0, 60, 180, 420, 900]
static var _acc: Array = [0.0, 0.05, 0.10, 0.15, 0.20]
static var _res: Array = [0.0, 0.10, 0.20, 0.30, 0.40]
static var _rel: Array = [0.0, 0.04, 0.08, 0.12, 0.15]
static var _mor: Array = [0.0, 0.08, 0.16, 0.24, 0.32]
static var _leader_def: Dictionary = {}   # def -> bool
static var _tcache: Dictionary = {}       # "seed:uid:def:vet" -> Array (pure cache)
static var _tcu: Dictionary = {}          # PERF61: uid -> [seed, def, vet key (-1 = leader), traits] (same pure cache, int key)


static func _sync() -> void:
	var r: Dictionary = Content.rules()
	if is_same(r, _rref):
		return
	_rref = r
	var g: Dictionary = r.get("g61_realism", {})
	_vr = g.get("veterancy", {})
	_tr = g.get("traits", {})
	_thr = _vr.get("thresholds", [0, 60, 180, 420, 900])
	_acc = _vr.get("acc_bonus", _acc)
	_res = _vr.get("supp_resist", _res)
	_rel = _vr.get("reload_bonus", _rel)
	_mor = _vr.get("morale_bonus", _mor)
	_leader_def.clear()
	_tcache.clear()
	_tcu.clear()


static func vr() -> Dictionary:
	_sync()
	return _vr


static func _at(a: Array, i: int) -> float:
	if a.is_empty():
		return 0.0
	return float(a[clampi(i, 0, a.size() - 1)])


# ---------------------------------------------------------------- XP and ranks
static func xp(w: SimWorld, uid: int) -> float:
	var e = w.entities.get(uid)
	return float(e.get("xp", 0.0)) if e != null else 0.0


static func rank(w: SimWorld, uid: int) -> int:
	var e = w.entities.get(uid)
	return int(e.get("vet", 0)) if e != null else 0


static func rank_name(r: int) -> String:
	_sync()
	var names: Array = _vr.get("ranks", DEF_RANKS)
	return String(names[clampi(r, 0, names.size() - 1)])


static func rank_for_xp(x: float) -> int:
	_sync()
	var r := 0
	for i in _thr.size():
		if x >= float(_thr[i]):
			r = i
	return r


## Adds XP to a unit (no-op for non-units / amount <= 0); emits RankUp {id, owner, rank} on promotion.
static func add_xp(w: SimWorld, e: Dictionary, amount: float) -> void:
	if amount <= 0.0 or e.get("kind", "") != "unit":
		return
	var x := snappedf(float(e.get("xp", 0.0)) + amount, Q)
	e.xp = x
	var r := rank_for_xp(x)
	if r != int(e.get("vet", 0)):
		e.vet = r
		w.emit("RankUp", {"id": int(e.id), "owner": int(e.owner), "rank": r})


## XP for a member plus the officer share for its company captain.
static func _credit(w: SimWorld, e: Dictionary, amount: float) -> void:
	add_xp(w, e, amount)
	if not e.has("company") or not w.sys_state.has("companies"):
		return
	var c = (w.sys_state.companies.get("companies", {}) as Dictionary).get(int(e.company))
	if c == null:
		return
	var cap := int(c.get("captain", -1))
	if cap >= 0 and cap != int(e.id):
		var ce = w.entities.get(cap)
		if ce != null:
			add_xp(w, ce, amount * float(_vr.get("officer_share", 0.25)))


## Every tick (Morale.tick): XP from this tick's Damage / SectorCaptured events.
static func on_tick(w: SimWorld) -> void:
	if w.events.is_empty():
		return
	_sync()
	var dxp := float(_vr.get("damage_xp", 0.25))
	var kxp := float(_vr.get("kill_xp", 12))
	var vxp := float(_vr.get("kill_value_xp", 4))
	var killed := {}
	var defs := {}
	for ev in w.events:
		if ev.type == "EntityDestroyed":
			defs[int(ev.id)] = String(ev.get("def", ""))
	for ev in w.events:
		var t := String(ev.type)
		if t == "Damage":
			var s = w.entities.get(int(ev.get("shooter", -1)))
			if s == null or s.kind != "unit":
				continue
			var gain := dxp * float(ev.get("amount", 0.0))
			var tid := int(ev.get("target", -1))
			if not w.entities.has(tid) and not killed.has(tid):
				killed[tid] = true
				gain += kxp + vxp * _value(String(defs.get(tid, ""))) / 100.0
			_credit(w, s, gain)


static func _value(def_id: String) -> float:
	if def_id == "":
		return 0.0
	var p: Dictionary = Content.production(def_id)
	var c = p.get("cost", {})
	var v := 0.0
	if c is Dictionary:
		for k in (c as Dictionary).keys():
			v += float(c[k])
	return v


## Objective XP from sector captures: w.sys_state.territory.owner is diffed against the saved snapshot
## w.sys_state.realism.sec (SectorCaptured fires in Victory, after Morale, so events would be missed).
static func objectives(w: SimWorld) -> void:
	var ter = w.sys_state.get("territory")
	if ter == null or not (ter as Dictionary).has("owner"):
		return
	var own: Array = ter.owner
	var rs: Dictionary = w.sys_state.get("realism", {})
	var prev = rs.get("sec")
	if prev == null or (prev as Array).size() != own.size():
		rs["sec"] = own.duplicate()
		w.sys_state["realism"] = rs
		return
	var pa: Array = prev
	var flips := []   # [sector, team], ascending sector (the order _objective was called in)
	for s in own.size():
		if int(own[s]) != int(pa[s]):
			if int(own[s]) >= 0:
				flips.append([s, int(own[s])])
			pa[s] = int(own[s])
	if not flips.is_empty():
		_objectives_many(w, ter, flips, own.size())


## PERF61-2: _objective for every flipped sector with ONE pass over the entities (was one full pass per sector:
## a mass territory flip at 10k cost seconds). Same members (the exact distance test, sector centers looked up in
## the <= 3x3 sector block around the unit) and the same credit order: sectors ascending, ids ascending.
static func _objectives_many(w: SimWorld, ter: Dictionary, flips: Array, nsec: int) -> void:
	_sync()
	var size := float(ter.get("size", 12))
	var cols := maxi(int(ter.get("cols", 1)), 1)
	var r2 := float(_vr.get("objective_radius", 10.0))
	r2 *= r2
	var rr := sqrt(r2)
	var oxp := float(_vr.get("objective_xp", 20))
	var want := {}   # sector -> team
	for f in flips:
		want[int(f[0])] = int(f[1])
	var team_of := {}   # owner -> team
	for fid in w.factions:
		team_of[int(fid)] = int(w.factions[fid].get("team", int(fid)))
	var lists := {}   # sector -> [ids]
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		var tm = team_of.get(int(e.owner))
		if tm == null:
			continue
		var p: Vector2 = e.pos
		var c0 := maxi(floori((p.x - rr) / size - 0.5) - 1, 0)
		var c1 := mini(floori((p.x + rr) / size - 0.5) + 1, cols - 1)
		var r0 := maxi(floori((p.y - rr) / size - 0.5) - 1, 0)
		var r1 := floori((p.y + rr) / size - 0.5) + 1
		for row in range(r0, r1 + 1):
			for col in range(c0, c1 + 1):
				var s := row * cols + col
				if s >= nsec:
					continue
				var st = want.get(s)
				if st == null or int(st) != int(tm):
					continue
				var cp := Vector2((float(s % cols) + 0.5) * size, (float(s / cols) + 0.5) * size)
				if p.distance_squared_to(cp) <= r2:
					if not lists.has(s):
						lists[s] = []
					lists[s].append(int(e.id))
	for f in flips:
		var ids = lists.get(int(f[0]))
		if ids == null:
			continue
		(ids as Array).sort()
		for id in ids:
			_credit(w, w.entities[id], oxp)


static func _objective(w: SimWorld, ter: Dictionary, sec: int, team: int) -> void:
	_sync()
	var size := float(ter.get("size", 12))
	var cols := maxi(int(ter.get("cols", 1)), 1)
	var cp := Vector2((float(sec % cols) + 0.5) * size, (float(sec / cols) + 0.5) * size)
	var r2 := float(_vr.get("objective_radius", 10.0))
	r2 *= r2
	var oxp := float(_vr.get("objective_xp", 20))
	var ids: Array = []
	for e in w.entities.values():
		if e.kind == "unit" and w.factions.has(int(e.owner)) and int(w.factions[int(e.owner)].get("team", int(e.owner))) == team:
			if (e.pos as Vector2).distance_squared_to(cp) <= r2:
				ids.append(int(e.id))
	ids.sort()
	for id in ids:
		_credit(w, w.entities[id], oxp)


## Surviving combat: called by Morale's realism pass for a unit that is under fire, dt seconds.
static func combat_xp(w: SimWorld, e: Dictionary, dt: float) -> void:
	_sync()
	_credit(w, e, float(_vr.get("combat_xp", 0.5)) * dt)


# ---------------------------------------------------------------- traits (pure)
static func _mix(h: int) -> int:
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = h & 0x7fffffff
	h = (h ^ (h >> 16)) * 0x45d9f3b
	h = h & 0x7fffffff
	return h ^ (h >> 16)


static func _shash(s: String) -> int:
	var h := 5381
	for i in s.length():
		h = ((h * 33) + s.unicode_at(i)) & 0x7fffffff
	return h


static func is_leader_def(def_id: String) -> bool:
	_sync()
	if not _leader_def.has(def_id):
		var ud: Dictionary = Content.unit(def_id)
		var lead := bool(ud.get("is_officer", false))
		if not lead:
			var all: Dictionary = (Content.rules().get("g6_companies", {}) as Dictionary).get("leaders", {})
			for f in all:
				for r in all[f]:
					if String(all[f][r]) == def_id:
						lead = true
		_leader_def[def_id] = lead
	return bool(_leader_def[def_id])


static func is_leader(e: Dictionary) -> bool:
	return e.has("rank_role") or is_leader_def(String(e.get("def", "")))


## Pick n distinct names from pool, seeded by h.
static func _pick(pool: Array, n: int, h: int) -> Array:
	var out: Array = []
	var left := pool.duplicate()
	var x := h
	while out.size() < n and not left.is_empty():
		x = _mix(x + 0x9e3779b)
		var i := x % left.size()
		out.append(left[i])
		left.remove_at(i)
	return out


## Traits of unit uid (leader: 1-2 leader traits; soldier at minor_from_rank+: one minor trait). [] if none.
static func traits(w: SimWorld, uid: int) -> Array:
	var e = w.entities.get(uid)
	if e == null or e.kind != "unit":
		return []
	_sync()
	var vet := int(e.get("vet", 0))
	var lead := is_leader(e)
	var vk := vet if not lead else -1
	var hit = _tcu.get(uid)
	if hit != null and int(hit[0]) == int(w.seed_value) and int(hit[2]) == vk and String(hit[1]) == String(e.def):
		return hit[3]
	var out: Array = []
	var h := _mix(int(w.seed_value) * 31 + uid * 7919 + 17)
	if lead:
		var cnt: Array = _tr.get("leader_count", [1, 2])
		var n := int(cnt[0]) + (h % (int(cnt[cnt.size() - 1]) - int(cnt[0]) + 1))
		out = _pick(_tr.get("leader", []), n, h)
	elif vet >= int(_tr.get("minor_from_rank", 2)):
		out = _pick(_tr.get("minor", []), 1, h)
	_tcu[uid] = [int(w.seed_value), String(e.def), vk, out]
	return out


static func has_trait(w: SimWorld, uid: int, t: String) -> bool:
	return traits(w, uid).has(t)


static func _weight_of(ts: Array, key: String) -> float:
	var ws: Dictionary = _tr.get("weights", {})
	var v := 0.0
	for t in ts:
		if String(t) == key:
			v += 1.0
		v += float((ws.get(t, {}) as Dictionary).get(key, 0.0))
	return v


## Sum of trait weights for key (e.g. "aggression", "caution", "hold", "flank", "recon", "logistics", "morale")
## or 1.0 per trait named key. 0.0 when the unit has none.
static func trait_weight(w: SimWorld, uid: int, key: String) -> float:
	var ts := traits(w, uid)
	if ts.is_empty():
		return 0.0
	return _weight_of(ts, key)


## Traits of an AI general slot (no unit): pure function of seed, side and slot name.
static func slot_traits(w: SimWorld, fid: int, slot: String) -> Array:
	_sync()
	var h := _mix(int(w.seed_value) * 131 + fid * 977 + _shash(slot))
	var cnt: Array = _tr.get("leader_count", [1, 2])
	var n := int(cnt[0]) + (h % (int(cnt[cnt.size() - 1]) - int(cnt[0]) + 1))
	return _pick(_tr.get("leader", []), n, h)


static func slot_trait_weight(w: SimWorld, fid: int, slot: String, key: String) -> float:
	return _weight_of(slot_traits(w, fid, slot), key)


# ---------------------------------------------------------------- bonuses (hot path: entity fields only)
## Accuracy factor from rank (+ marksman). 1.0 for a green unit with no traits.
static func acc_mult(w: SimWorld, e: Dictionary) -> float:
	var r := int(e.get("vet", 0))
	if r <= 0:
		return 1.0
	_sync()
	var m := 1.0 + _at(_acc, r)
	if r >= int(_tr.get("minor_from_rank", 2)):
		m += _weight_of(traits(w, int(e.id)), "accuracy")
	return m


## Suppression intake factor from rank and traits (steady, stubborn): < 1 resists.
static func supp_resist(w: SimWorld, e: Dictionary) -> float:
	var r := int(e.get("vet", 0))
	var lead := e.has("rank_role") or is_leader_def(String(e.get("def", "")))
	if r <= 0 and not lead:
		return 1.0
	_sync()
	var m := 1.0 - _at(_res, r)
	var tw := _weight_of(traits(w, int(e.id)), "supp_resist")
	return maxf(m * (1.0 - tw), 0.2)


## Reload (cooldown) factor from rank: < 1 is faster.
static func reload_mult(e: Dictionary) -> float:
	var r := int(e.get("vet", 0))
	if r <= 0:
		return 1.0
	_sync()
	return 1.0 - _at(_rel, r)


## Morale-loss factor (squadmate deaths) from rank and traits (stubborn, inspiring "morale" weight).
static func morale_loss_mult(w: SimWorld, e: Dictionary) -> float:
	var r := int(e.get("vet", 0))
	var lead := e.has("rank_role") or is_leader_def(String(e.get("def", "")))
	if r <= 0 and not lead:
		return 1.0
	_sync()
	var m := 1.0 - _at(_mor, r) - _weight_of(traits(w, int(e.id)), "morale")
	return clampf(m, 0.3, 1.0)


## Company reputation: {avg_xp, avg_rank, rank (rounded), n} over living members (e.company == cid).
static func company_rep(w: SimWorld, cid: int) -> Dictionary:
	var n := 0
	var sx := 0.0
	var sr := 0.0
	for e in w.entities.values():
		if e.kind == "unit" and int(e.get("company", -1)) == cid:
			n += 1
			sx += float(e.get("xp", 0.0))
			sr += float(e.get("vet", 0))
	if n == 0:
		return {"avg_xp": 0.0, "avg_rank": 0.0, "rank": 0, "n": 0}
	return {"avg_xp": sx / n, "avg_rank": sr / n, "rank": roundi(sr / n), "n": n}
