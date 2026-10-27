extends RefCounted
## Turrets7 (owner: TURRET7). G7 master scope section 7: the eight new Human A turrets (content/g7/defs_g7_turrets.json).
## Every turret def carries a "t7" block and NO def.weapon, so Combat's tower path skips it and this system drives it:
##   gun    (Heavy MG nest, Autocannon, Hull-down tank turret): direct fire at the best target by t7.prefer.
##   mortar (Auto-mortar pit): indirect, min range, splash on enemies; fires only at a target SPOTTED by a friendly
##          tower-type building (t7.spotters, within its sight) or a friendly airborne drone (within its sight).
##   emp    (EMP projector): when >= min_targets Machine units / enemy drones are in radius: MachineEW7.stun for stun_s
##          and every enemy airborne drone in radius is dropped (killed). Long recharge (weapon cooldown).
##   flame  (Thermite): flame shot + splash on small ground units; burns creep at the impact (Creep.burn) and, with no
##          target, burns the nearest creep cell in range (scan every creep_scan_s). Seeds in the burn die when
##          Creep exposes burn_seeds (guarded call).
##   cone   (Microwave): soft-kill cone (cone_deg) toward the best target; hits only swarm / drone / leech classes.
##   rail   (Rail cannon): extreme range; the hit pierces along the line: up to t7.pierce more enemies within t7.lane
##          of the line take damage x falloff^n. Prefers the walking core, then the biggest Machine units.
## A turret acts only when built, powered (requires_power) and not EMP-disabled (Airdef.source_active).
## State: w.sys_state.turrets7 {ver, ready: {bid: tick}, aim: {bid: target id}} created on the first turret's first
## act (matches without turrets never create it: hash-identical). Cache: w.cache.t7_sub (turret ids, by next_id) and
## w.cache.t7_grid (8-tile buckets of units, rebuilt on scan ticks only). Both derive from state.
## Determinism: ascending ids, integer ticks, w.rng only for the accuracy roll of a gun / mortar / rail shot.
## Cost: retarget only every SCAN ticks (one shared bucket grid); between scans a turret fires at its held target.
## Events: ShotFired (as Combat, so FX draw tracers), T7Emp {bid,pos,radius,n,drones}, T7Burn {bid,pos,radius,cells},
## T7Cone {bid,pos,dir,range,half,n}, T7Rail {bid,from,to,n}.
const VER := 1
const SCAN := 10
const BK := 8.0
const HotState = preload("res://sim/hot_state.gd")
const Airdef = preload("res://sim/systems/airdef.gd")
const PData = preload("res://sim/systems/progression_data.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Inert7 = preload("res://sim/systems/inert7.gd")   # G7 PERF7A: spotter-def building list, on/off switch
const BBK := 16.0   # G7 PERF7A: building bucket size (tiles) for the enemy-building candidate scans

const TAGS := ["inf", "swarm", "drone", "air", "leech", "pack", "walker_l", "walker_h", "light_v", "heavy", "big", "core", "machine", "building"]

static var _dmg = null
static var _ew = null
static var _tagc := {}   # def id -> static tag bits


static func _damage():
	if _dmg == null:
		_dmg = load("res://sim/systems/damage.gd")
	return _dmg


static func _mew():
	if _ew == null:
		_ew = load("res://sim/systems/machine_ew7.gd")
	return _ew


# ================================================================ content helpers
static func is_turret(def_id: String) -> bool:
	return Content.building(def_id).has("t7")


static func cfg_of(def_id: String) -> Dictionary:
	return Content.building(def_id).get("t7", {})


static func weapon_of(def_id: String) -> Dictionary:
	return Content.weapon(String(cfg_of(def_id).get("weapon", "")))


## All turret def ids (content order).
static func defs() -> Array:
	var out := []
	for id in Content.ids("buildings"):
		if is_turret(String(id)):
			out.append(String(id))
	return out


static func bit(tag: String) -> int:
	var i := TAGS.find(tag)
	return 0 if i < 0 else (1 << i)


static func bits_of(tags: Array) -> int:
	var m := 0
	for t in tags:
		m |= bit(String(t))
	return m


# ================================================================ target classes
## Static class bits of a unit def (cached per def id). A THREAT7 def may set t7_class (swarm|leech|packhunter|
## light_walker|heavy_walker) to override the heuristics.
static func _def_bits(def_id: String) -> int:
	if _tagc.has(def_id):
		return int(_tagc[def_id])
	var d := Content.unit(def_id)
	var m := 0
	var s := (def_id + " " + String(d.get("role", ""))).to_lower()
	var tc := String(d.get("t7_class", ""))
	var armor := String(d.get("armor", "infantry"))
	var air := bool(d.get("is_air", false))
	if air:
		m |= bit("air")
	if armor == "infantry":
		m |= bit("inf")
	if tc == "swarm" or s.find("swarm") >= 0 or String(d.get("aircraft", "")) == "micro" or s.find("micro") >= 0:
		m |= bit("swarm")
	if air and (bool(d.get("launched_drone", false)) or d.has("drone") or String(d.get("aircraft", "")) == "micro" or s.find("drone") >= 0):
		m |= bit("drone")
	if tc == "leech" or s.find("leech") >= 0:
		m |= bit("leech")
	if tc == "packhunter" or s.find("packhunter") >= 0:
		m |= bit("pack")
	if tc == "light_walker" or (not air and armor == "light" and (s.find("crawler") >= 0 or s.find("stalker") >= 0 or s.find("spider") >= 0 or s.find("synth") >= 0)):
		m |= bit("walker_l")
	if tc == "heavy_walker" or (not air and armor == "heavy" and (s.find("walker") >= 0 or s.find("colossus") >= 0 or s.find("weaver") >= 0)):
		m |= bit("walker_h")
	if not air and armor == "light" and m & (bit("inf") | bit("swarm") | bit("leech")) == 0:
		m |= bit("light_v")
	if not air and armor == "heavy":
		m |= bit("heavy")
	if float(d.get("hp", 0)) >= 2000.0 or tc == "heavy_walker" and float(d.get("hp", 0)) >= 1500.0:
		m |= bit("big")
	_tagc[def_id] = m
	return m


## Class bits of entity t as seen by owner fid (dynamic: walking core, latched leech, Machine side, building).
static func tags_of(w: SimWorld, t: Dictionary) -> int:
	var m := 0
	if t.kind == "building":
		m = bit("building")
		if t.has("core7"):
			m |= bit("core") | bit("big")
	else:
		m = _def_bits(String(t.def))
		if t.has("core7"):
			m |= bit("core") | bit("big") | bit("walker_h") | bit("heavy")
		if t.has("leech_on"):
			m |= bit("leech")
	if SimWorld.Creep.machine_fids(w).has(int(t.owner)):
		m |= bit("machine")
	return m


static func _airborne(t: Dictionary) -> bool:
	return t.kind == "unit" and bool(Content.unit(String(t.def)).get("is_air", false)) and not bool(t.get("air_landed", false))


## May turret config c engage t at all (air rule, buildings rule, t7.only)?
static func allowed(w: SimWorld, c: Dictionary, t: Dictionary) -> bool:
	var m := tags_of(w, t)
	if _airborne(t) and not bool(c.get("air", false)):
		return false
	if t.kind == "building" and not bool(c.get("buildings", false)):
		return false
	var only: Array = c.get("only", [])
	if not only.is_empty() and m & bits_of(only) == 0:
		return false
	return true


## Preference rank of t for config c: index of the first matching prefer tag (lower is better), prefer.size() if none.
static func rank(w: SimWorld, c: Dictionary, t: Dictionary) -> int:
	var m := tags_of(w, t)
	var pref: Array = c.get("prefer", [])
	for i in pref.size():
		if m & bit(String(pref[i])) != 0:
			return i
	return pref.size()


static func pos_of(w: SimWorld, t: Dictionary) -> Vector2:
	if t.kind == "building":
		return Vector2(t.cell) + Vector2(float(t.size), float(t.size)) * 0.5
	return HotState.get_pos(w, int(t.id))


static func center(b: Dictionary) -> Vector2:
	return Vector2(b.cell) + Vector2(float(b.size), float(b.size)) * 0.5


# ================================================================ lists, state, grid
static func _add(sub: Dictionary, e: Dictionary) -> void:
	if e.kind == "building" and is_turret(String(e.def)):
		(sub.ids as Array).append(int(e.id))


## Live turret building ids, ascending (incremental by next_id, like Airdef.sub_state).
static func turret_ids(w: SimWorld) -> Array:
	var sub = w.cache.get("t7_sub")
	var nid := int(w.next_id)
	if sub == null:
		sub = {"ids": [], "next_id": nid}
		var ids: Array = w.entities.keys()
		ids.sort()
		for id in ids:
			_add(sub, w.entities[id])
		w.cache["t7_sub"] = sub
	elif nid > int(sub.next_id):
		for id in range(int(sub.next_id), nid):
			var e = w.entities.get(id)
			if e != null:
				_add(sub, e)
		sub.next_id = nid
	var arr: Array = sub.ids
	for id in arr:
		if not w.entities.has(id):
			var keep := []
			var s = w.sys_state.get("turrets7")
			for j in arr:
				if w.entities.has(j):
					keep.append(j)
				elif s != null:
					(s.ready as Dictionary).erase(j)
					(s.aim as Dictionary).erase(j)
			sub.ids = keep
			return keep
	return arr


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get("turrets7")
	if s == null:
		s = {"ver": VER, "ready": {}, "aim": {}}
		w.sys_state["turrets7"] = s
	return s


## Unit buckets (BK tiles), rebuilt at most once per tick and only when a turret asks. Ascending id per bucket.
static func _grid(w: SimWorld) -> Dictionary:
	var g = w.cache.get("t7_grid")
	if g != null and int(g.t) == w.tick:
		return g.b
	var b := {}
	for e in SimIndex.of(w, "unit"):
		if not w.entities.has(int(e.id)):
			continue
		var p := HotState.get_pos(w, int(e.id))
		var k := floori(p.x / BK) + floori(p.y / BK) * 4096
		var arr = b.get(k)
		if arr == null:
			b[k] = [e]
		else:
			arr.append(e)
	w.cache["t7_grid"] = {"t": w.tick, "b": b}
	return b


## Enemy units of fid within r of p (live, current position), ascending bucket order. margin widens the bucket scan.
static func _near(w: SimWorld, fid: int, p: Vector2, r: float, ground_only := false) -> Array:
	var b: Dictionary = _grid(w)
	var out := []
	var r2 := r * r
	for by in range(floori((p.y - r) / BK), floori((p.y + r) / BK) + 1):
		for bx in range(floori((p.x - r) / BK), floori((p.x + r) / BK) + 1):
			var arr = b.get(bx + by * 4096)
			if arr == null:
				continue
			for e in arr:
				if not w.entities.has(int(e.id)) or not w.is_enemy(fid, int(e.owner)):
					continue
				if ground_only and _airborne(e):
					continue
				if HotState.get_pos(w, int(e.id)).distance_squared_to(p) <= r2:
					out.append(e)
	return out


## G7 PERF7A: buildings bucketed by center (BBK tiles) as [list index, entity]; follows SimIndex's building array
## like Inert7 (a new array -> rebuilt, the same array grown -> only the tail added). Runtime cache only
## (w.cache.t7_bgrid): a building's cell and size never change, so it derives from state.
static func _bgrid(w: SimWorld) -> Dictionary:
	var src: Array = SimIndex.of(w, "building")
	var n := src.size()
	var g = w.cache.get("t7_bgrid")
	if g == null or not is_same(g.src, src) or int(g.n) > n:
		g = {"src": src, "n": 0, "b": {}, "ms": 0.0}
		w.cache["t7_bgrid"] = g
	if int(g.n) < n:
		var b: Dictionary = g.b
		for i in range(int(g.n), n):
			var e: Dictionary = src[i]
			var c := center(e)
			var k := floori(c.x / BBK) + floori(c.y / BBK) * 4096
			var arr = b.get(k)
			if arr == null:
				b[k] = [[i, e]]
			else:
				arr.append([i, e])
			g.ms = maxf(float(g.ms), float(e.size))
		g.n = n
	return g


## G7 PERF7A: the buildings of SimIndex.of(w, "building") that are live enemies of fid with their center within
## r + their size of p, in list order. Every caller keeps exactly these tests (or stricter ones) itself, so its
## candidate list is unchanged; only buckets near p are visited. Inert7.enabled = false: the whole list (the on/off
## hash check).
static func _blds_near(w: SimWorld, fid: int, p: Vector2, r: float) -> Array:
	if not Inert7.enabled:
		return SimIndex.of(w, "building")
	var g := _bgrid(w)
	var rr := r + float(g.ms)
	var b: Dictionary = g.b
	var en := {}   # owner -> is_enemy(fid, owner), per query
	var idx := []
	for by in range(floori((p.y - rr) / BBK), floori((p.y + rr) / BBK) + 1):
		for bx in range(floori((p.x - rr) / BBK), floori((p.x + rr) / BBK) + 1):
			var arr = b.get(bx + by * 4096)
			if arr == null:
				continue
			for q in arr:
				var e: Dictionary = q[1]
				var o := int(e.owner)
				var ev = en.get(o)
				if ev == null:
					ev = w.is_enemy(fid, o)
					en[o] = ev
				if ev and w.entities.has(int(e.id)) and center(e).distance_to(p) <= r + float(e.size):
					idx.append(int(q[0]))
	if idx.is_empty():
		return idx
	idx.sort()
	var src: Array = g.src
	var out := []
	for i in idx:
		out.append(src[i])
	return out


# ================================================================ targeting
static func _visible(w: SimWorld, fid: int, t: Dictionary) -> bool:
	return SimWorld.Fog.entity_visible(w, fid, t)


## Mortar spotting: t is within the sight of a friendly built spotter building (t7.spotters; radar uses its radius)
## or of a friendly airborne drone (t7.spot_drones).
static func spotted(w: SimWorld, fid: int, c: Dictionary, t: Dictionary) -> bool:
	var tp := pos_of(w, t)
	var sp: Array = c.get("spotters", [])
	if not sp.is_empty():
		for s in Inert7.blds(w, Inert7.SPOTTER):   # G7 PERF7A: spotter defs only (was every building)
			if not sp.has(String(s.def)) or not w.entities.has(int(s.id)) or not bool(s.get("built", false)):
				continue
			if int(s.owner) != fid and not w.is_ally(fid, int(s.owner)):
				continue
			var sd := Content.building(String(s.def))
			var r := maxf(float(sd.get("sight", 0)), float(sd.get("radar", {}).get("radius", 0)))
			if center(s).distance_to(tp) <= r:
				return true
	if bool(c.get("spot_drones", false)):
		for d in Airdef.sub_list(w, "drone"):
			var e = w.entities.get(d)
			if e == null or not _airborne(e) or (int(e.owner) != fid and not w.is_ally(fid, int(e.owner))):
				continue
			if HotState.get_pos(w, int(d)).distance_to(tp) <= float(Content.unit(String(e.def)).get("sight", 6)):
				return true
	return false


## Can turret b (config c, weapon wd) fire at t now (range, min range, class rules, visibility, LOS, spotting)?
static func can_engage(w: SimWorld, b: Dictionary, c: Dictionary, wd: Dictionary, t: Dictionary) -> bool:
	if t == null or not w.entities.has(int(t.id)) or not w.is_enemy(int(b.owner), int(t.owner)):
		return false
	if t.kind == "building" and String(t.get("state", "")) == "ruined":
		return false
	var bp := center(b)
	var tp := pos_of(w, t)
	var d := bp.distance_to(tp)
	if d > float(wd.get("range", 0)) or d < float(wd.get("min_range", 0)):
		return false
	if not allowed(w, c, t) or not _visible(w, int(b.owner), t):
		return false
	var kind := String(c.get("kind", "gun"))
	if kind == "mortar":
		return spotted(w, int(b.owner), c, t)
	if not _airborne(t) and not _damage().line_clear(w, bp, tp):
		return false
	return true


## Best target: lowest prefer rank, then nearest, then lowest id. Units from the bucket grid; enemy buildings too
## when t7.buildings.
static func pick(w: SimWorld, b: Dictionary, c: Dictionary, wd: Dictionary):
	var bp := center(b)
	var fid := int(b.owner)
	var best = null
	var bk := INF
	var cands := _near(w, fid, bp, float(wd.get("range", 0)))
	if bool(c.get("buildings", false)):
		for s in _blds_near(w, fid, bp, float(wd.get("range", 0))):   # G7 PERF7A: nearby buckets only
			if w.entities.has(int(s.id)) and w.is_enemy(fid, int(s.owner)) and center(s).distance_to(bp) <= float(wd.get("range", 0)) + float(s.size):
				cands.append(s)
	# G7 PERF7A: the key (pure: tags, position, id) first; a candidate whose key cannot beat the best so far is
	# never picked, so its can_engage (fog, LOS, spotting) is skipped. Same pick as testing can_engage first.
	var lazy := Inert7.enabled
	for t in cands:
		if not lazy and not can_engage(w, b, c, wd, t):
			continue
		var k := float(rank(w, c, t)) * 100000.0 + bp.distance_to(pos_of(w, t)) * 10.0 + float(int(t.id)) * 1e-6
		if k < bk:
			if lazy and not can_engage(w, b, c, wd, t):
				continue
			bk = k
			best = t
	return best


# ================================================================ system API (ORCH slot)
static func tick(w: SimWorld) -> void:
	var ids := turret_ids(w)
	if ids.is_empty():
		return
	_tick2(w, ids)


static func _tick2(w: SimWorld, ids: Array) -> void:
	var scan := w.tick % SCAN == 0
	var st = null
	for bid in ids:
		var b = w.entities.get(bid)
		if b == null or not bool(b.get("built", false)) or not Airdef.source_active(w, b):
			continue
		if st == null:
			st = w.sys_state.get("turrets7")
			if st == null:
				if not scan:
					continue   # first act waits for a scan tick (no state before a turret can act)
				st = _st(w)
		if int(st.ready.get(bid, 0)) > w.tick:
			continue
		var c := cfg_of(String(b.def))
		var kind := String(c.get("kind", "gun"))
		if kind == "emp":
			if scan:
				_emp(w, st, b, c)
			continue
		var wd := weapon_of(String(b.def))
		var t = null
		var aim := int(st.aim.get(bid, -1))
		if scan:
			t = pick(w, b, c, wd)
		elif aim >= 0:
			t = w.entities.get(aim)
			if t != null and not can_engage(w, b, c, wd, t):
				t = null
		if t == null:
			if aim >= 0:
				(st.aim as Dictionary).erase(bid)
			if kind == "flame" and (w.tick + int(bid)) % maxi(roundi(float(c.get("creep_scan_s", 2.0)) * SimWorld.TICK_RATE), 1) == 0:
				_burn_creep(w, st, b, c, wd)
			continue
		if aim != int(t.id):
			st.aim[bid] = int(t.id)
		_spend(w, st, int(bid), wd)
		match kind:
			"mortar":
				_mortar(w, b, wd, t)
			"flame":
				_flame(w, b, c, wd, t)
			"cone":
				_cone(w, b, c, wd, t)
			"rail":
				_rail(w, b, c, wd, t)
			_:
				_gun(w, b, wd, t)


static func _spend(w: SimWorld, st: Dictionary, bid: int, wd: Dictionary) -> void:
	st.ready[bid] = w.tick + maxi(roundi(float(wd.get("cooldown", 1.0)) * SimWorld.TICK_RATE), 1)


static func _s(b: Dictionary, wd: Dictionary, wid: String, dmg: float) -> Dictionary:
	return {"weapon": wid, "cls": String(wd.get("class", "")), "damage": dmg}


static func _wid(b: Dictionary) -> String:
	return String(cfg_of(String(b.def)).get("weapon", ""))


static func _shot(w: SimWorld, b: Dictionary, t, to: Vector2, hit: bool, indirect := false) -> void:
	w.emit("ShotFired", {"shooter": int(b.id), "target": -1 if t == null else int(t.id), "weapon": _wid(b), "hit": hit,
		"from": center(b), "to": to, "indirect": indirect, "t7": String(cfg_of(String(b.def)).get("kind", "gun"))})


static func _gun(w: SimWorld, b: Dictionary, wd: Dictionary, t: Dictionary) -> void:
	var hit := w.rng.chance(float(wd.get("accuracy", 1.0)))
	_shot(w, b, t, pos_of(w, t), hit)
	_damage().apply_hit(w, b, t, _s(b, wd, _wid(b), float(wd.get("damage", 0))), hit)


## Splash on enemy ground units (and enemy buildings when bld) within rad of at: damage x (1 - 0.5 d / rad).
static func _splash(w: SimWorld, b: Dictionary, wd: Dictionary, at: Vector2, rad: float, bld: bool) -> int:
	var fid := int(b.owner)
	var hits := _near(w, fid, at, rad, true)
	if bld:
		for s in _blds_near(w, fid, at, rad):   # G7 PERF7A: nearby buckets only
			if w.entities.has(int(s.id)) and w.is_enemy(fid, int(s.owner)) and center(s).distance_to(at) <= rad + float(s.size) * 0.5:
				hits.append(s)
	var n := 0
	for t in hits:
		if not w.entities.has(int(t.id)):
			continue
		var d := minf(pos_of(w, t).distance_to(at), rad)
		_damage().apply_hit(w, b, t, _s(b, wd, _wid(b), float(wd.get("damage", 0)) * (1.0 - 0.5 * d / maxf(rad, 0.01))), true)
		n += 1
	return n


static func _mortar(w: SimWorld, b: Dictionary, wd: Dictionary, t: Dictionary) -> void:
	var hit := w.rng.chance(float(wd.get("accuracy", 1.0)))
	var to := pos_of(w, t)
	if not hit:
		to += Vector2(w.rng.randf_range(-1.5, 1.5), w.rng.randf_range(-1.5, 1.5))
	_shot(w, b, t, to, hit, true)
	_splash(w, b, wd, to, float(wd.get("splash", 1.0)), true)


static func _flame(w: SimWorld, b: Dictionary, c: Dictionary, wd: Dictionary, t: Dictionary) -> void:
	var at := pos_of(w, t)
	_shot(w, b, t, at, true)
	_splash(w, b, wd, at, float(wd.get("splash", 1.0)), false)
	_burn_at(w, b, c, at)


## Thermite burn at `at` (only in creep matches: Creep.burn would otherwise create the creep state).
static func _burn_at(w: SimWorld, b: Dictionary, c: Dictionary, at: Vector2) -> int:
	if not SimWorld.Creep.enabled(w):
		return 0
	var r := float(c.get("burn_radius", 2.5))
	var cells := int(SimWorld.Creep.burn(w, at, r))
	var seeds := 0
	var bs := Callable(SimWorld.Creep, "burn_seeds")
	if bs.is_valid():
		seeds = int(bs.call(w, at, r))
	w.emit("T7Burn", {"bid": int(b.id), "owner": int(b.owner), "pos": at, "radius": r, "cells": cells, "seeds": seeds})
	return cells


## No target: burn the nearest creep tile in range (cell-size steps, fixed row/column order).
static func _burn_creep(w: SimWorld, st: Dictionary, b: Dictionary, c: Dictionary, wd: Dictionary) -> void:
	if not SimWorld.Creep.enabled(w):
		return
	var bp := center(b)
	var r := float(wd.get("range", 6))
	var best := Vector2(-1, -1)
	var bd := INF
	var step := 2
	for y in range(floori(bp.y - r), floori(bp.y + r) + 1, step):
		for x in range(floori(bp.x - r), floori(bp.x + r) + 1, step):
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(bp)
			if d <= r and d < bd and SimWorld.Creep.on_creep(w, Vector2i(x, y)):
				bd = d
				best = p
	if bd == INF:
		return
	_spend(w, st, int(b.id), wd)
	_shot(w, b, null, best, true)
	_burn_at(w, b, c, best)


static func _cone(w: SimWorld, b: Dictionary, c: Dictionary, wd: Dictionary, t: Dictionary) -> void:
	var bp := center(b)
	var dir := (pos_of(w, t) - bp).normalized()
	var half := deg_to_rad(float(c.get("cone_deg", 50.0)) * 0.5)
	var rr := float(wd.get("range", 8))
	var n := 0
	for e in _near(w, int(b.owner), bp, rr):
		if not w.entities.has(int(e.id)) or not allowed(w, c, e) or not _visible(w, int(b.owner), e):
			continue
		var v := HotState.get_pos(w, int(e.id)) - bp
		if v.length_squared() > 0.0001 and absf(dir.angle_to(v)) > half:
			continue
		_damage().apply_hit(w, b, e, _s(b, wd, _wid(b), float(wd.get("damage", 0))), true)
		n += 1
	w.emit("T7Cone", {"bid": int(b.id), "owner": int(b.owner), "pos": bp, "dir": dir, "range": rr, "half": half, "n": n})


## Rail: primary hit, then up to t7.pierce more enemy ground units within t7.lane of the line (out to full range),
## nearest first along the line, each at damage x falloff^k.
static func _rail(w: SimWorld, b: Dictionary, c: Dictionary, wd: Dictionary, t: Dictionary) -> void:
	var bp := center(b)
	var tp := pos_of(w, t)
	var dir := (tp - bp).normalized()
	var rr := float(wd.get("range", 30))
	var end := bp + dir * rr
	var hit := w.rng.chance(float(wd.get("accuracy", 1.0)))
	var dmg := float(wd.get("damage", 0))
	_shot(w, b, t, end, hit)
	_damage().apply_hit(w, b, t, _s(b, wd, _wid(b), dmg), hit)
	var lane := float(c.get("lane", 0.7))
	var rows := []
	for e in _near(w, int(b.owner), bp + dir * rr * 0.5, rr * 0.5 + lane, true):
		if int(e.id) == int(t.id) or not w.entities.has(int(e.id)):
			continue
		var v := HotState.get_pos(w, int(e.id)) - bp
		var u := v.dot(dir)
		if u <= 0.0 or u > rr or absf(v.cross(dir)) > lane:
			continue
		rows.append([u, int(e.id)])
	rows.sort()
	var n := 0
	var f := float(c.get("falloff", 0.7))
	for row in rows:
		if n >= int(c.get("pierce", 4)):
			break
		var e = w.entities.get(int(row[1]))
		if e == null:
			continue
		n += 1
		_damage().apply_hit(w, b, e, _s(b, wd, _wid(b), dmg * pow(f, n)), true)
	w.emit("T7Rail", {"bid": int(b.id), "owner": int(b.owner), "from": bp, "to": end, "target": int(t.id), "hit": hit, "n": n})


## EMP: fires when >= t7.min_targets Machine units / enemy airborne drones are in radius. Stuns every Machine unit
## in radius (MachineEW7.stun) and drops every enemy airborne drone in radius. Recharge = weapon cooldown.
static func _emp(w: SimWorld, st: Dictionary, b: Dictionary, c: Dictionary) -> void:
	var bp := center(b)
	var fid := int(b.owner)
	var r := float(c.get("radius", 7.0))
	var mf: Array = SimWorld.Creep.machine_fids(w)
	var mach := 0
	var drones := []
	for e in _near(w, fid, bp, r):
		if not _visible(w, fid, e):
			continue
		if bool(c.get("drones", true)) and _airborne(e) and tags_of(w, e) & bit("drone") != 0:
			drones.append(e)
		elif mf.has(int(e.owner)):
			mach += 1
	if mach + drones.size() < int(c.get("min_targets", 1)):
		return
	var wd := weapon_of(String(b.def))
	_spend(w, st, int(b.id), wd)
	var n := 0
	if mach > 0:
		n = int(_mew().stun(w, bp, r, float(c.get("stun_s", 8.0)), int(b.id)))
	for d in drones:
		if w.entities.has(int(d.id)):
			_damage().apply_hit(w, b, d, _s(b, {"class": "energy"}, _wid(b), 1.0e6), true)
	w.emit("T7Emp", {"bid": int(b.id), "owner": fid, "pos": bp, "radius": r, "n": n, "drones": drones.size()})


# ================================================================ AI + Last Protocol helpers
## AI defence rows for the Human A AI (ai_g6_def._defences, wired by ORCH): [[def_id, cap], ...] the side may build
## now (faction, stage, requires), by seen threat t {inf:int, armour:bool, drone:bool, air:bool, machine:bool}.
static func ai_rows(w: SimWorld, fid: int, t: Dictionary, late: bool) -> Array:
	var want := []
	var mach := bool(t.get("machine", false))
	if int(t.get("inf", 0)) > 0 or mach or not bool(t.get("armour", false)):
		want.append(["a_t7_hmg_nest", 2])
	if bool(t.get("armour", false)):
		want.append(["a_t7_hulldown", 1])
	if bool(t.get("drone", false)) or bool(t.get("armour", false)) or mach:
		want.append(["a_t7_autocannon", 1])
	if bool(t.get("drone", false)) or mach:
		want.append(["a_t7_microwave", 1])
	if mach:
		want.append(["a_t7_emp", 1])
		if SimWorld.Creep.enabled(w):
			want.append(["a_t7_thermite", 2])
	if late:
		want.append(["a_t7_automortar", 1])
		if bool(t.get("armour", false)) or mach:
			want.append(["a_t7_railgun", 1])
	var fac := String(w.factions[fid].get("faction_def", "")) if w.factions.has(fid) else ""
	var out := []
	for row in want:
		var d := Content.building(String(row[0]))
		if d.is_empty() or String(d.get("faction", "")) != fac or PData.unavailable_reason(w, fid, d) != "":
			continue
		out.append(row)
	return out


## Last Protocol outer-ring mix (LPMODE7 places): one wall segment's turret order, repeated around the ring.
static func lp_ring_mix() -> Array:
	return ["a_t7_hmg_nest", "a_t7_autocannon", "a_t7_hulldown", "a_t7_thermite", "a_t7_microwave", "a_t7_hmg_nest",
		"a_t7_emp", "a_t7_automortar", "a_t7_hulldown", "a_t7_railgun"]


## Places a finished turret (pre-built bases, tests). Returns the building id (-1 when def is not a turret).
static func place(w: SimWorld, fid: int, def_id: String, cell: Vector2i) -> int:
	if not is_turret(def_id):
		return -1
	return w.spawn_building(def_id, fid, cell, true)


static func validate_command(_w: SimWorld, cmd: Dictionary) -> String:
	return "%s: not a turret command" % String(cmd.get("type", ""))


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
