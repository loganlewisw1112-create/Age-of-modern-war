extends RefCounted
## G7 ACCURACY8B (G7_REFERENCE 13.9c-53, owner: "all stray hits + makes shot placement crucial"): stray rounds.
## A missed direct-fire round keeps flying along its scatter line (shooter -> the miss point Combat._fire already
## rolled, so the line costs no extra draw) up to the weapon's range, and can hit the FIRST unit or building it
## crosses: enemy, friendly or neutral. Damage goes through the normal Damage.apply_hit path (the round's energy
## falls with the shooter -> victim distance there: Ballistics8.vel_ratio; vehicle facing = Damage.hit_side of the
## shooter). Skipped like Accuracy8: indirect, guided, air shooter / air target, skip classes (melee, flame,
## demolition, crush, torpedo). Rules: content/g7/rules_g8_accuracy.json rules.accuracy8.stray (PROVISIONAL).
## Cost: candidates from the tick's combat grid (native RtsGrid w.cache.combat_ng, else the GDScript bucket grid
## w.cache.combat_grid) sampled every `step` tiles along the capped line; buildings from Construction's per-tick
## footprint map; one Damage.line_clear for the chosen victim. RNG: at most ONE w.rng draw per miss, and only when
## the line crosses something (the "does it connect" roll).
## Events: StrayHit {shooter, target, aimed, friendly, from, at} for every stray hit; FriendlyFire {shooter, target,
## owner, at} when the victim is the shooter's own side or an ally (not an enemy and not neutral-unowned).
## Env STRAY8_OFF=1: off (A/B only).

const Accuracy8 = preload("res://sim/systems/accuracy8.gd")
const Damage = preload("res://sim/systems/damage.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Roof7 = preload("res://sim/systems/roof7.gd")   # G7 REG8B: strays never hit a roof mount (13.9c-39)

static var _off = null
static var _rref = null
static var _c := {}
static var n_calls := 0   # bench / test counters (runtime only, never saved)
static var n_hits := 0
static var n_ff := 0
static var n_blocked := 0   # STRAY8B: discipline holds / sidesteps started (runtime only, never saved)
static var n_steps := 0
static var n_retarget := 0
static var why := {}   # bench diagnostics only (runtime): why a blocked man did not sidestep
static var bench := false   # bench only: time on_miss into us_total (two clock reads per miss when on)
static var us_total := 0
static var us_disc := 0   # bench only: time inside muzzle_blocked (discipline check + reposition search)


static func cfg() -> Dictionary:
	var r: Dictionary = Content.rules()
	if is_same(r, _rref):
		return _c
	_rref = r
	var a: Dictionary = r.get("accuracy8", {})
	var c = a.get("stray", {})
	_c = c if c is Dictionary else {}
	var ov := OS.get_environment("STRAY8B_DISC")   # A/B only: JSON merged over stray.discipline (and its sidestep)
	if ov != "":
		var j = JSON.parse_string(ov)
		if j is Dictionary:
			_c = _c.duplicate(true)
			var dd: Dictionary = _c.get("discipline", {})
			for k in j:
				if k == "sidestep" and j[k] is Dictionary:
					(dd.get("sidestep", {}) as Dictionary).merge(j[k], true)
				else:
					dd[k] = j[k]
	return _c


static func enabled() -> bool:
	if _off == null:
		_off = OS.get_environment("STRAY8_OFF") == "1"
	return not bool(_off) and bool(cfg().get("enabled", false)) and Accuracy8.enabled()


## Called by Combat._fire after a missed direct-fire shot (after the near-miss suppression).
static func on_miss(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary, from: Vector2, to: Vector2) -> void:
	if not enabled():
		return
	if bench:
		var t0 := Time.get_ticks_usec()
		_on_miss(w, e, s, t, from, to)
		us_total += Time.get_ticks_usec() - t0
		return
	_on_miss(w, e, s, t, from, to)


## PERF8B: the native grid has query_capsule (rts_core >= the PERF8B build); checked once per grid class.
static var _capq = null
static func _has_capq(ng) -> bool:
	if _capq == null:
		_capq = ng.grid.has_method("query_capsule_along")
	return bool(_capq)


static func _on_miss(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary, from: Vector2, to: Vector2) -> void:
	if s.indirect or s.get("guided", false) or s.get("is_air", false):
		return
	var sp: Array = Accuracy8._profile_of(e)
	if sp[8] or int(sp[0]) == Accuracy8.C_AIR:
		return
	if t.kind == "unit" and int(Accuracy8._profile_of(t)[0]) == Accuracy8.C_AIR:
		return   # a miss at an aircraft flies into the sky
	var dv := to - from
	var l0 := dv.length()
	if l0 < 0.01:
		return
	n_calls += 1
	var c := cfg()
	var dir := dv / l0
	var u0 := float(c.get("start_tiles", 0.5))
	var ln := minf(float(sp[9]) * float(c.get("range_frac", 1.0)), float(c.get("max_tiles", 30.0)))
	if ln <= u0:
		return
	var step := float(c.get("step_tiles", 2.0))
	var hr: Dictionary = c.get("hit_r", {})
	var r_inf := float(hr.get("inf", 0.3))
	var r_prone := float(hr.get("inf_prone", 0.2))
	var r_veh := float(hr.get("vehicle", 0.7))
	var r_hv := float(hr.get("heavy", 0.9))
	var rq := step * 0.5 + r_hv + 0.05
	var eid := int(e.id)
	var tid := int(t.id)
	var eo := int(e.owner)
	var fdo: Dictionary = c.get("discipline", {})
	var fo_u := float(fdo.get("over_tiles", fdo.get("clear_tiles", 0.0))) + 0.3 if bool(fdo.get("over_prone", false)) else -1.0   # rounds pass over low mates this far out
	var best = null
	var bu := INF
	var bid := 1 << 30
	var ng = w.cache.get("combat_ng")
	var grid = w.cache.get("combat_grid") if ng == null else null
	var ents: Dictionary = w.entities
	var tq := Time.get_ticks_usec() if SimIndex.profiling else 0
	# PERF8 (exact): inside Combat.tick (cmb_ev live) unit positions are fixed and equal the grid's packed npos, so the
	# along-line / side-offset test runs on npos before any Dictionary read; survivors repeat the same test on e.pos.
	var pk := ng != null and w.cache.has("cmb_ev")
	var nix: PackedInt32Array = ng.idx if pk else PackedInt32Array()
	var npos: PackedVector2Array = ng.npos if pk else PackedVector2Array()
	var nsz := nix.size()
	if pk:
		# PERF8 (exact): every unit passing the geometry test lies in the capsule (cu in [u0, ln], off <= r_hv); fewer,
		# larger discs (half-length 3 tiles) still cover it, and the pick is the (cu, id) argmin, so query layout and
		# candidate order do not change the result. Outside Combat.tick the original 2-tile layout is kept.
		step = 6.0
		rq = sqrt(9.0 + r_hv * r_hv) + 0.05
	var one := pk and _has_capq(ng)   # PERF8B (exact): one native capsule query = the prefilter set below (+ slack)
	var u := u0 + step * 0.5
	while u - step * 0.5 < ln and u - step * 0.5 < bu:
		var cands
		if one:
			cands = ng.grid.query_capsule_along(from, dir, u0 - 0.01, ln + 0.01, r_hv + 0.01)   # ascending along-line distance
		else:
			var p := from + dir * u
			cands = ng.grid.query_radius(p, rq) if ng != null else _near(w, grid, p, rq)
		for cv in cands:
			if pk:
				var ci: int = nix[cv] if cv < nsz else -1
				if ci >= 0:
					var rp: Vector2 = npos[ci] - from
					var cp := rp.dot(dir)
					if one and cp > bu + 0.01:
						break   # PERF8B (exact): sorted along the line, every later unit lies beyond the current best
					if cp < u0 or cp > ln or cp > bu or absf(rp.cross(dir)) > r_hv:
						continue
			var ce = ents.get(cv) if ng != null else cv
			if ce == null:
				continue
			var cid: int = ce.id
			if cid == eid or cid == tid:
				continue
			# geometry first (cheap): along-line distance and side offset against the largest body radius
			var rel: Vector2 = Vector2(ce.pos) - from
			var cu := rel.dot(dir)
			if cu < u0 or cu > ln or cu > bu or (cu == bu and cid >= bid):
				continue
			var off := absf(rel.cross(dir))
			if off > r_hv:
				continue
			if ce.kind != "unit" or int(ce.get("garrisoned_in", -1)) >= 0 or ce.has("evac_by"):
				continue
			if cu <= fo_u and int(ce.get("owner", -1)) == eo and low(ce):
				continue   # STRAY8B fire over: the round passes over a mate kneeling / lying in the muzzle zone
			var pr: Array = Accuracy8._profile_of(ce)
			var code := int(pr[0])
			if code == Accuracy8.C_AIR:
				continue
			var rr := r_veh
			if code == Accuracy8.C_INF:
				rr = r_prone if Accuracy8._prone_any(ce) else r_inf
			elif float(pr[7]) > float(Accuracy8.K.hs_veh):
				rr = r_hv
			if off > rr:
				continue
			best = ce
			bu = cu
			bid = cid
		if one:
			break
		u += step
	if SimIndex.profiling:
		tq = SimIndex.pt("PERF8_sq", tq)
	var bb = _bld_on_line(w, from, dir, u0, minf(ln, bu), tid, int(e.id), int(e.get("garrisoned_in", -1)), e.pos if e.kind == "unit" else null)   # G7 FIX8: never its own shooter / garrison; DRONE8: nor the wall / tower it stands on
	if bb != null:
		best = bb[0]
		bu = float(bb[1])
	if SimIndex.profiling:
		tq = SimIndex.pt("PERF8_sbld", tq)
	if best == null:
		return
	var victim: Dictionary = best
	var at: Vector2 = from + dir * bu
	var lcok := Damage.line_clear(w, from, at)
	if SimIndex.profiling:
		tq = SimIndex.pt("PERF8_slc", tq)
	if not lcok:
		return   # the round stops in blocking terrain first
	var ph: Dictionary = c.get("connect", {})
	var pc := float(ph.get("building", 0.95))
	if victim.kind == "unit":
		var vc := int(Accuracy8._profile_of(victim)[0])
		if vc == Accuracy8.C_INF:
			pc = float(ph.get("inf", 0.55))
			if Accuracy8._prone_any(victim):
				pc *= float(ph.get("prone_mult", 0.5))
		else:
			pc = float(ph.get("vehicle", 0.85))
	if not w.rng.chance(pc):   # the one extra draw: does the round connect (height / body shape)
		return
	n_hits += 1
	var vo := int(victim.get("owner", -1))
	var friendly := vo >= 0 and not w.is_enemy(int(e.owner), vo) and (vo == int(e.owner) or _allied(w, int(e.owner), vo))
	var vid := int(victim.id)
	w.emit("StrayHit", {"shooter": eid, "target": vid, "aimed": tid, "friendly": friendly, "from": from, "at": at,
		"weapon": s.get("weapon", "")})
	if friendly:
		n_ff += 1
		w.emit("FriendlyFire", {"shooter": eid, "target": vid, "owner": vo, "at": at})
	Damage.apply_hit(w, e, victim, s, true)


## G7 STRAY8B (13.9c-53 friendly-fire follow-up, owner: "Discipline + reposition"). Fire discipline: true when one
## of the shooter's OWN men stands within clear_off tiles of the line of fire in the first clear_tiles tiles from the
## muzzle; Combat._fire then holds fire for hold_s (no shot, no ammo, no draw) instead of shooting through him.
## Reposition: a blocked foot soldier free to move (order idle / attack / attack_move, not Hold Position, not
## garrisoned, not pinned, not boarded) makes ONE short lateral sidestep (offsets_tiles, perpendicular to the line,
## side order by id parity: no rng) to the nearest walkable, unoccupied spot whose own muzzle line is clear, through
## Movement.order_path; then fires from there. Anti-jitter: one sidestep per target per cooldown_s (retarget_s for a
## new target), and a search that finds nothing clear also starts the cooldown (he just holds). Vehicles hold
## (turret buildings are not checked) (their mount traverses / re-targets as usual), never sidestep. Friends farther along the line, and
## strays, stay live. State: e.ss8 = [target id, tick of the last sidestep or search, tick the step ends] (saved,
## hashed with the entity). Same skip list as strays. Geometry first, one grid query per check.
static func muzzle_blocked(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary) -> bool:
	if bench:
		var t0 := Time.get_ticks_usec()
		var r := _muzzle_blocked(w, e, s, t)
		us_disc += Time.get_ticks_usec() - t0
		return r
	return _muzzle_blocked(w, e, s, t)


static func _muzzle_blocked(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary) -> bool:
	if not enabled() or e.kind != "unit":
		return false   # buildings (turrets, drone bays) keep firing / launching over men at their walls (FIX8: a drone-bay launch counted as a blocked shot)
	if s.indirect or s.get("guided", false) or s.get("is_air", false):
		return false
	var c := cfg()
	var fd: Dictionary = c.get("discipline", {})
	var cl := float(fd.get("clear_tiles", 0.0))
	if cl <= 0.0:
		return false
	var sp: Array = Accuracy8._profile_of(e)
	if sp[8] or int(sp[0]) == Accuracy8.C_AIR:
		return false
	var from: Vector2 = e.pos
	var dv: Vector2 = Vector2(t.pos) - from
	var d := dv.length()
	if d < 0.01:
		return false
	var dir := dv / d
	var u0 := 0.3
	if e.kind == "building":
		u0 = float(e.get("size", 1)) * 0.5 + 0.3   # the round leaves the footprint first (towers shoot over men at the wall)
	var ln := minf(cl + u0 - 0.3, d - 0.3)
	if ln <= u0:
		return false
	var co := float(fd.get("clear_off", 0.45))
	var eid := int(e.id)
	var eo := int(e.owner)
	var ng = w.cache.get("combat_ng")
	var mid := from + dir * (ln * 0.5)
	var rq := ln * 0.5 + co
	var pk0 := ng != null and w.cache.has("cmb_ev") and _has_capq(ng)   # PERF8B (exact): capsule = the npos prefilter below (+ slack)
	var cands = (ng.grid.query_capsule(from, dir, u0 - 0.01, ln + 0.01, co + 0.01) if pk0 else ng.grid.query_radius(mid, rq)) if ng != null else _near(w, w.cache.get("combat_grid"), mid, rq)
	var ents: Dictionary = w.entities
	var blocked := false
	var ovp := bool(fd.get("over_prone", false))
	var pk := ng != null and w.cache.has("cmb_ev")   # PERF8 (exact): geometry on the packed npos first (see _on_miss)
	var nix: PackedInt32Array = ng.idx if pk else PackedInt32Array()
	var npos: PackedVector2Array = ng.npos if pk else PackedVector2Array()
	var nsz := nix.size()
	for cv in cands:
		if pk:
			var ci: int = nix[cv] if cv < nsz else -1
			if ci >= 0:
				var rp: Vector2 = npos[ci] - from
				var cp := rp.dot(dir)
				if cp < u0 or cp > ln or absf(rp.cross(dir)) > co:
					continue
		var ce = ents.get(cv) if ng != null else cv
		if ce == null or int(ce.id) == eid or int(ce.get("owner", -1)) != eo:
			continue
		var rel: Vector2 = Vector2(ce.pos) - from
		var cu := rel.dot(dir)
		if cu < u0 or cu > ln or absf(rel.cross(dir)) > co:
			continue
		if ce.kind != "unit" or int(ce.get("garrisoned_in", -1)) >= 0 or int(Accuracy8._profile_of(ce)[0]) == Accuracy8.C_AIR:
			continue
		if ovp and low(ce):
			continue   # fire over: the rear man fires over a mate lying, crouched or kneeling to fire in front of him
		blocked = true
		break
	if blocked:
		n_blocked += 1
		var tss := Time.get_ticks_usec() if SimIndex.profiling else 0
		_sidestep(w, e, s, t, dir, fd, int(sp[0]) == Accuracy8.C_INF and e.kind == "unit")
		if SimIndex.profiling:
			SimIndex.pt("PERF8_sidestep", tss)
	return blocked


## Candidate offsets (lateral, forward) in search order: each forward band (0 = pure sidestep first), then each
## lateral offset, own side first. Pure function of the rules and the id parity.
static func _cands(offs: Array, fwd: Array, side: float) -> Array:
	var out := []
	for f in fwd:
		for o in offs:
			out.append(Vector2(float(o) * side, float(f)))
			out.append(Vector2(-float(o) * side, float(f)))
	return out


## STRAY8B fire over: a soldier lying / crouched low (prone flags) or kneeling to fire (a foot soldier standing still
## with a target: the front rank kneels so the rank behind fires over it). Pure read of entity state, no new state.
static func low(ce: Dictionary) -> bool:
	if Accuracy8._prone_any(ce):
		return true
	if bool(ce.get("moving", false)) or int(Accuracy8._profile_of(ce)[0]) != Accuracy8.C_INF:
		return false
	return int(ce.get("target", -1)) >= 0 or _kneel_still()


## SPREAD8 (cost): the kneel_still rule, cached with the rules dict (low() ran a cfg() + two dict reads per mate).
static var _ks_ref = null
static var _ks := false
static func _kneel_still() -> bool:
	var c := cfg()
	if not is_same(c, _ks_ref):
		_ks_ref = c
		_ks = bool((c.get("discipline", {}) as Dictionary).get("kneel_still", false))
	return _ks


## True when no own mate (own[i] == 1) stands within co of the line p -> q in its first cl tiles.
static func _muzzle_clear(p: Vector2, q: Vector2, pts: PackedVector2Array, own: PackedByteArray, cl: float, co: float) -> bool:
	var dv := q - p
	var d := dv.length()
	if d < 0.01:
		return false
	var dr := dv / d
	var ln := minf(cl, d - 0.3)
	for i in pts.size():
		if own[i] == 1:
			var rel: Vector2 = pts[i] - p
			var cu := rel.dot(dr)
			if cu >= 0.3 and cu <= ln and absf(rel.cross(dr)) <= co:
				return false
	return true


## True while e walks its sidestep: Combat._engage then does not stop the walk to fire (fires on arrival / when clear).
static func stepping(w: SimWorld, e: Dictionary) -> bool:
	var v = e.get("ss8")
	return v != null and bool(e.moving) and w.tick < int(v[2])


static func _may_step(w: SimWorld, e: Dictionary) -> bool:
	var ot := String(e.order.get("type", "idle"))
	if ot != "idle" and ot != "attack" and ot != "attack_move":
		return false   # a move / retreat / hold / build order: the player's order stands, he just holds fire
	if String(e.get("stance", "")) == "hold_position" or bool(e.get("pinned", false)):
		return false
	if int(e.get("garrisoned_in", -1)) >= 0 or e.has("evac_by") or int(e.get("transport_id", -1)) >= 0 or bool(e.get("deployed", false)):
		return false
	return true


## The sidestep: deterministic candidate order (offsets x side, side first by id parity), first spot that is walkable,
## at least min_gap from every unit, and has its own muzzle line clear of mates. Nothing clear: hold (cooldown starts).
static func _sidestep(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary, dir: Vector2, fd: Dictionary, foot: bool) -> void:
	var ss: Dictionary = fd.get("sidestep", {})
	var ot0 := String(e.order.get("type", "idle")) if e.kind == "unit" else "idle"
	var may := foot and _may_step(w, e)
	var may_rt := int(ss.get("retarget_n", 0)) > 0 and (ot0 == "idle" or ot0 == "attack_move" or ot0 == "hold")
	if not bool(ss.get("enabled", false)) or not (may or may_rt):
		if bench:
			why["no_step:" + String(e.order.get("type", "idle")) + ("/pin" if bool(e.get("pinned", false)) else "")] = int(why.get("no_step:" + String(e.order.get("type", "idle")) + ("/pin" if bool(e.get("pinned", false)) else ""), 0)) + 1
		return
	var tid := int(t.id)
	var v = e.get("ss8")
	if v != null:
		var gap := w.tick - int(v[1])
		var need := int(round(float(ss.get("cooldown_s", 3.0)) * 20.0)) if int(v[0]) == tid else int(round(float(ss.get("retarget_s", 1.5)) * 20.0))
		if int(v[2]) == int(v[1]):
			need = mini(need, int(round(float(ss.get("fail_s", 1.5)) * 20.0)))   # the last search found nothing: look again sooner (no move = no jitter)
		if gap < need:
			if bench:
				why["cool"] = int(why.get("cool", 0)) + 1
			return
	# cost cap: at most max_search_per_tick reposition searches per tick in the whole world (call order is the sim's
	# deterministic shooter order; w.cache is per-tick scratch, a man over budget just tries at his next block)
	var bud = w.cache.get("ss8_bud")
	if bud == null or int(bud[0]) != w.tick:
		bud = [w.tick, 0]
		w.cache["ss8_bud"] = bud
	if int(bud[1]) >= int(ss.get("max_search_per_tick", 4)):
		if bench:
			why["budget"] = int(why.get("budget", 0)) + 1
		return
	bud[1] = int(bud[1]) + 1
	if SimIndex.profiling:
		SimIndex.pt("PERF8_ss_search_n", Time.get_ticks_usec())
	var from: Vector2 = e.pos
	var nrm := Vector2(-dir.y, dir.x)
	var side := 1.0 if int(e.id) % 2 == 0 else -1.0
	var offs: Array = ss.get("offsets_tiles", [0.6, 1.0, 1.5])
	var fwd: Array = ss.get("forward_tiles", [0.0])
	var omax := float(offs[offs.size() - 1]) if not offs.is_empty() else 1.5
	var cl := float(fd.get("clear_tiles", 1.5))
	var co := float(fd.get("clear_off", 0.3))
	var mg := float(ss.get("min_gap", 0.35))
	var eid := int(e.id)
	var eo := int(e.owner)
	# one grid query covers every candidate spot and its muzzle zone: own mates (muzzle) and any unit (occupancy)
	var ng = w.cache.get("combat_ng")
	var mid := from + dir * (cl * 0.5)
	var fmax := float(fwd.max()) if not fwd.is_empty() else 0.0
	var rq := cl * 0.5 + omax + fmax + co + mg
	var tc0 := Time.get_ticks_usec() if SimIndex.profiling else 0
	var cands = ng.grid.query_radius(mid, rq) if ng != null else _near(w, w.cache.get("combat_grid"), mid, rq)
	var ents: Dictionary = w.entities
	var pts := PackedVector2Array()
	var own := PackedByteArray()
	var foes := []
	# PERF8 (exact): a mate / unit only matters to a check if it lies within rb of a candidate spot (min_gap test,
	# or the spot's / the shooter's own muzzle zone: cu <= cl, off <= co); spots lie in the box lateral [-omax, omax]
	# x forward [fmin, fmax] around the shooter. Inside Combat.tick (packed npos == pos) units farther than rb (+ a
	# float margin) from that box are skipped before any Dictionary read, unless they may be a retarget foe.
	var pk := ng != null and w.cache.has("cmb_ev")
	var nix: PackedInt32Array = ng.idx if pk else PackedInt32Array()
	var npos: PackedVector2Array = ng.npos if pk else PackedVector2Array()
	var nsz := nix.size()
	var fmin := float(fwd.min()) if not fwd.is_empty() else 0.0
	var rb := maxf(mg, sqrt(cl * cl + co * co)) + 0.05
	var rb2 := rb * rb
	var ovp := bool(fd.get("over_prone", false))
	for cv in cands:
		if pk:
			var ci: int = nix[cv] if cv < nsz else -1
			if ci >= 0:
				var rp: Vector2 = npos[ci] - from
				var la := absf(rp.dot(nrm))
				var lo := rp.dot(dir)
				var dla := maxf(la - omax, 0.0)
				var dlo := maxf(maxf(fmin - lo, lo - fmax), 0.0)
				if dla * dla + dlo * dlo > rb2:
					if not may_rt:
						continue
					var cwn = ents.get(cv)
					if cwn == null or int(cwn.get("owner", -1)) == eo:
						continue   # an own mate this far out takes part in no check; others below decide as before
		var ce = ents.get(cv) if ng != null else cv
		if ce == null or int(ce.id) == eid or ce.kind != "unit" or int(ce.get("garrisoned_in", -1)) >= 0:
			continue
		if int(Accuracy8._profile_of(ce)[0]) == Accuracy8.C_AIR:
			continue
		pts.append(Vector2(ce.pos))
		var co2 := int(ce.get("owner", -1))
		own.append((2 if ovp and low(ce) else 1) if co2 == eo else 0)
		if may_rt and co2 != eo and int(ce.id) != int(t.id) and co2 >= 0 and w.is_enemy(eo, co2):
			foes.append(ce)
	if SimIndex.profiling:
		tc0 = SimIndex.pt("PERF8_ss_collect", tc0)
		prof_n("PERF8_ss_cands", cands.size())
	var tp: Vector2 = t.pos
	var mg2 := mg * mg
	var goal = null
	# 1) "traverse": switch to one of the retarget_n nearest enemies in that zone with a clear line from here (no move)
	if may_rt and not foes.is_empty():
		var rng_t := float(s.range)
		var used := {}
		for k in mini(int(ss.get("retarget_n", 0)), foes.size()):
			var bi := -1
			var bd := INF
			for i in foes.size():
				if used.has(i):
					continue
				var dd := from.distance_squared_to(Vector2(foes[i].pos))
				if dd < bd or (dd == bd and bi >= 0 and int(foes[i].id) < int(foes[bi].id)):
					bd = dd
					bi = i
			if bi < 0:
				break
			used[bi] = true
			var fe: Dictionary = foes[bi]
			if sqrt(bd) > rng_t or not _muzzle_clear(from, Vector2(fe.pos), pts, own, cl, co):
				continue
			if SimWorld.Combat._valid_target(w, eo, int(fe.id), s) == null or not Damage.line_clear(w, from, Vector2(fe.pos)):
				continue
			e.target = int(fe.id)
			n_retarget += 1
			e.ss8 = [int(fe.id), w.tick, w.tick]
			return
	if SimIndex.profiling:
		tc0 = SimIndex.pt("PERF8_ss_retarget", tc0)
	if not may:
		e.ss8 = [tid, w.tick, w.tick]
		return
	for cand in _cands(offs, fwd, side):
		var p: Vector2 = from + nrm * float(cand.x) + dir * float(cand.y)
		if not w.in_bounds(w.cell_of(p)) or not Movement.is_passable_e(w, e, w.cell_of(p)):
			continue
		var dv2 := tp - p
		var d2 := dv2.length()
		if d2 < 0.5:
			continue
		var dr := dv2 / d2
		var ln := minf(cl, d2 - 0.3)
		var ok := true
		for i in pts.size():
			var rel: Vector2 = pts[i] - p
			if rel.length_squared() < mg2:
				ok = false
				break
			if own[i] == 1:
				var cu := rel.dot(dr)
				if cu >= 0.3 and cu <= ln and absf(rel.cross(dr)) <= co:
					ok = false
					break
		if ok and Damage.line_clear(w, p, tp):
			goal = p
			break
	if SimIndex.profiling:
		tc0 = SimIndex.pt("PERF8_ss_spots", tc0)
	var until := w.tick
	if bench:
		why["search_ok" if goal != null else "search_none"] = int(why.get("search_ok" if goal != null else "search_none", 0)) + 1
		why["pts_sum"] = int(why.get("pts_sum", 0)) + pts.size()
	var top := Time.get_ticks_usec() if SimIndex.profiling else 0
	var opk: bool = goal != null and Movement.order_path(w, e, goal)
	if SimIndex.profiling and goal != null:
		SimIndex.pt("PERF8_ss_path", top)
	if opk:
		n_steps += 1
		until = w.tick + int(round(float(ss.get("max_s", 2.0)) * 20.0))
	e.ss8 = [tid, w.tick, until]


static func prof_n(k: String, n: int) -> void:
	var a = SimIndex.prof.get(k)
	if a == null:
		SimIndex.prof[k] = [n, 1]
	else:
		a[0] += n
		a[1] += 1


static func hold_ticks() -> int:
	return maxi(int(round(float((cfg().get("discipline", {}) as Dictionary).get("hold_s", 0.5)) * 20.0)), 1)


static func _allied(w: SimWorld, a: int, b: int) -> bool:
	var fa = w.factions.get(a)
	var fb = w.factions.get(b)
	if fa == null or fb == null:
		return false
	return int(fa.get("team", a)) == int(fb.get("team", b))


## Units near p (radius r) from the GDScript combat grid, else a full scan (tests / no combat this tick).
static func _near(w: SimWorld, grid, p: Vector2, r: float) -> Array:
	var out := []
	if grid == null:
		for ce in SimIndex.of(w, "unit"):
			if Vector2(ce.pos).distance_squared_to(p) <= r * r and SimIndex.alive(w, ce):
				out.append(ce)
		return out
	var bx := floori(p.x / Damage.BUCKET)
	var by := floori(p.y / Damage.BUCKET)
	for o in grid:
		var g: Dictionary = grid[o]
		for yy in range(by - 1, by + 2):
			for xx in range(bx - 1, bx + 2):
				var arr = g.get(xx + yy * Damage.GRID_STRIDE)
				if arr == null:
					continue
				for ce in arr:
					if w.entities.has(int(ce.id)):
						out.append(ce)
	return out


## [building, u] of the first live building footprint cell the line crosses within (u0, u1], else null.
## The aimed target (tid) is skipped (the miss went past it).
## The shooter and its garrison building are skipped: a stray never hits its own shooter (G7 FIX8).
static func _bld_on_line(w: SimWorld, from: Vector2, dir: Vector2, u0: float, u1: float, tid: int, sid: int = -1, gid: int = -1, spos = null):
	var blds: Array = SimIndex.of(w, "building")
	if u1 <= u0 or blds.is_empty():
		return null
	if blds.size() <= 64:
		# SPREAD8 (cost, exact): the sampled points all lie on the segment, so when no footprint's box (grown by one
		# cell) touches the segment's box the sampler below cannot find a cell. Skips the 0.5-tile walk (up to 60
		# dict reads per miss) in the usual case of a line far from every building.
		var pa := from + dir * u0
		var pb := from + dir * u1
		var lx := minf(pa.x, pb.x) - 1.0
		var hx := maxf(pa.x, pb.x) + 1.0
		var ly := minf(pa.y, pb.y) - 1.0
		var hy := maxf(pa.y, pb.y) + 1.0
		var any := false
		for b in blds:
			var bc: Vector2i = b.cell
			var sz := float(b.size)
			if float(bc.x) <= hx and float(bc.x) + sz >= lx and float(bc.y) <= hy and float(bc.y) + sz >= ly:
				any = true
				break
		if not any:
			return null
	var occ: Dictionary = SimWorld.Construction._occupancy(w)
	if occ.is_empty():
		return null
	# G7 DRONE8: a man firing from a wall-walk or a tower top stands inside that building's footprint; his round leaves
	# over its parapet, so the building under his feet is never his stray's victim (it was: wall / tower self-hits at
	# 0.5 tiles). One occupancy lookup; a man on open ground is unaffected.
	var stid := -1
	if spos != null:
		var sc := Vector2i(floori(Vector2(spos).x), floori(Vector2(spos).y))
		if occ.has(sc):
			var sb = _bld_at(w, sc)
			if sb != null:
				stid = int(sb.id)
	var u := u0
	var last := Vector2i(-99999, -99999)
	while u <= u1:
		var p := from + dir * u
		var cell := Vector2i(floori(p.x), floori(p.y))
		if cell != last:
			last = cell
			if occ.has(cell):
				var b = _bld_at(w, cell, true)
				if b != null and int(b.id) != tid and int(b.id) != sid and int(b.id) != gid and int(b.id) != stid:
					return [b, u]
		u += 0.5
	return null


## no_roof (G7 REG8B, 13.9c-39 roof7): a roof mount (def roof_mount) is skipped: a stray flies at body height, under
## the roof, so it hits the building the mount stands on (or nothing), never the mount; guns still hit a mount they aim at.
static func _bld_at(w: SimWorld, cell: Vector2i, no_roof: bool = false):
	for b in SimIndex.of(w, "building"):
		var bc: Vector2i = b.cell
		var sz := int(b.size)
		if cell.x >= bc.x and cell.y >= bc.y and cell.x < bc.x + sz and cell.y < bc.y + sz and SimIndex.alive(w, b):
			if no_roof and Roof7.is_roof(b):
				continue
			return b
	return null
