extends RefCounted
## Morale (owner: agent A2). Cover flags, suppression decay, morale, break/rally.
## Contract: docs/CONTRACTS_G2.md section 2. Runs in SYSTEM_ORDER right after Combat.
## Infantry only (units with a `morale` field: riflemen, AT, recon, engineers, officers).
## Every tick: squadmate deaths queued by damage.gd this tick (w.cache.morale_deaths; plus any
##   EntityDestroyed event that carries a `squad` field) cost per_squadmate_death morale to living
##   same-owner units of that squad within SQUAD_RADIUS of the death.
## Every UPDATE_EVERY ticks (dt = 0.2 s), per infantry unit:
##   in_cover = on FOREST, or within COVER_R of a building footprint or wreck.
##   supp decays decay_per_second once the unit has not been suppressed for UNDER_FIRE_TICKS.
##   pinned = supp >= pinned_at.
##   morale: -pinned_drain_per_second while pinned; +recover_per_second once out of combat
##   (no suppression for OUT_OF_COMBAT_TICKS); clamped to 0..units.json morale.
##   break (morale < break_at): broken, order {type:"retreat", target}, path to the nearest own
##   HQ/depot (Movement.order_path), UnitBroken. Rally (morale >= rally_at): broken=false, a retreat
##   order becomes idle, UnitRallied.

const Movement = preload("res://sim/systems/movement.gd")
const Tiers = preload("res://sim/systems/tiers.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")  # G6 PERF6: morale_delta
const NativeCore = preload("res://sim/native_core.gd")  # G6 PERF6-4: morale_scan
## G3b PERF4: loops read the shared SimIndex. REDUCED-tier units (Tiers: no enemy near) update on
## every 2nd morale update (staggered by id) with twice the dt, so recovery/decay rates are kept.
## Squadmate losses use one squad index per tick instead of one full pass per death.

const Q := 1.0 / 1024.0
const UPDATE_EVERY := 4
const UNDER_FIRE_TICKS := 20
const OUT_OF_COMBAT_TICKS := 60
const SQUAD_RADIUS := 8.0
const COVER_R := 1.0
const CB := 4.0              # cover-index bucket size (tiles)
const CB_STRIDE := 1024
const FOREST := 3            # Terrain.FOREST
const HOME_DEFS := ["hq", "depot"]

static var _mmax: Dictionary = {}   # def -> max morale (units.json `morale`)


static func max_morale(def_id: String) -> float:
	if not _mmax.has(def_id):
		_mmax[def_id] = float(Content.unit(def_id).get("morale", 100))
	return _mmax[def_id]


## ================================================================ G6.1 REAL61: suppression states
## States: alert < suppressed (supp >= suppressed_at: accuracy / speed down) < pinned (supp >= pinned_at: prone,
## crawls at move_pinned, fires at acc_pinned) < broken (break/rally above). Rules: rules.g61_realism.suppression.
## Incoming suppression goes through add_supp (Damage.suppress, ORCH CR realism_damage): weapon factor
## (weapon_supp) x target resistance (live cover level x e.rz, the pass-computed leader / rank / trait / fatigue /
## high-ground factor); in heavy cover a non-heavy weapon cannot push supp past heavy_cover_cap.
## Realism pass (every fatigue.update_every ticks, phase REAL_PHASE): fatigue, combat XP, e.rz, e.mvm (movement
## factor from the suppressed state, fatigue and the fast trait; Movement multiplies it in, ORCH CR realism_move),
## objective XP. e.rz / e.mvm exist only when != 1.0 (saved + hashed with the entity).
const Veterancy = preload("res://sim/systems/veterancy.gd")
const Fatigue = preload("res://sim/systems/fatigue.gd")
const Elevation = preload("res://sim/systems/elevation.gd")
const Fieldworks = preload("res://sim/systems/fieldworks.gd")
const REAL_PHASE := 7
const RECENT_FIRE_TICKS := 40

static var _srref = null
static var _sr: Dictionary = {}
static var _supp_at := 25.0
static var _pin_at := 60.0
static var _mv_s := 0.75
## Movement factor of a pinned unit (Movement reads it; synced from rules each Morale tick).
static var pin_move := 0.1
## Bench / A-B toggle only (never set in a match): false skips the XP events and the realism pass.
static var realism_on := true
static var _wf: Dictionary = {}   # weapon id -> suppression factor
static var _ldef: Dictionary = {}  # PERF61-2: def -> is_leader_def (content-static; cleared when rules change)


static func _ssync() -> void:
	var r: Dictionary = Content.rules()
	if is_same(r, _srref):
		return
	_srref = r
	_sr = (r.get("g61_realism", {}) as Dictionary).get("suppression", {})
	_supp_at = float(_sr.get("suppressed_at", 25))
	_pin_at = float((r.get("suppression", {}) as Dictionary).get("pinned_at", 60))
	_mv_s = float(_sr.get("move_suppressed", 0.75))
	pin_move = float(_sr.get("move_pinned", 0.1))
	_wf.clear()
	_ldef.clear()


static func is_pinned(w: SimWorld, e: Dictionary) -> bool:
	return bool(e.get("pinned", false))


static func is_suppressed(w: SimWorld, e: Dictionary) -> bool:
	_ssync()
	return float(e.get("supp", 0.0)) >= _supp_at


## "alert" | "suppressed" | "pinned" | "broken" ("" for units without morale).
static func state(w: SimWorld, e: Dictionary) -> String:
	if not e.has("morale"):
		return ""
	if bool(e.get("broken", false)):
		return "broken"
	if bool(e.get("pinned", false)):
		return "pinned"
	return "suppressed" if is_suppressed(w, e) else "alert"


## Suppression 0..1 (supp / 100).
static func supp_level(w: SimWorld, e: Dictionary) -> float:
	return clampf(float(e.get("supp", 0.0)) / 100.0, 0.0, 1.0)


## Suppression factor of a weapon stats dict (Combat.stats: weapon, cls, cooldown): weapon def `suppress`,
## else class_factor by class (small_arms with cooldown <= mg_cooldown = "mg"). Cached per weapon id.
static func weapon_supp(s: Dictionary) -> float:
	_ssync()
	var wid := String(s.get("weapon", ""))
	if _wf.has(wid):
		return float(_wf[wid])
	var wd: Dictionary = Content.weapon(wid) if wid != "" else {}
	var f := 1.0
	if wd.has("suppress"):
		f = float(wd.suppress)
	else:
		var cls := String(s.get("cls", wd.get("class", "")))
		if cls == "small_arms" and float(s.get("cooldown", wd.get("cooldown", 1.0))) <= float(_sr.get("mg_cooldown", 0.5)):
			cls = "mg"
		f = float((_sr.get("class_factor", {}) as Dictionary).get(cls, 1.0))
	_wf[wid] = f
	return f


## 0 open, 1 light cover (forest / near a building or wreck: e.in_cover), 2 heavy (garrisoned, or a fieldwork
## whose cover factor <= heavy_cover_at).
static func cover_level(w: SimWorld, e: Dictionary) -> int:
	if int(e.get("garrisoned_in", -1)) >= 0:
		return 2
	var p: Vector2 = e.pos
	if Fieldworks.cover_at(w, Vector2i(floori(p.x), floori(p.y))) <= float(_sr.get("heavy_cover_at", 0.6)):
		return 2
	if bool(e.get("in_cover", false)) or w.terrain_at(Vector2i(floori(p.x), floori(p.y))) == FOREST:
		return 1
	return 0


## Adds suppression to an infantry unit: amount (rules base) x sf (weapon_supp) x resistance, clamped to 0..cap;
## marks it under fire and pins at pinned_at. Returns the new supp. Called by Damage.suppress.
static func add_supp(w: SimWorld, e: Dictionary, amount: float, sf: float = 1.0) -> float:
	if not e.has("morale"):
		return 0.0
	_ssync()
	var f := amount * sf * float(e.get("rz", 1.0))
	var cap := 100.0
	var cl := cover_level(w, e)
	if cl == 2:
		f *= float(_sr.get("cover_heavy", 0.45))
		if sf < float(_sr.get("heavy_weapon_at", 2.0)):
			cap = float(_sr.get("heavy_cover_cap", 55))
	elif cl == 1:
		f *= float(_sr.get("cover_light", 0.6))
	var cur := float(e.get("supp", 0.0))
	var v := snappedf(clampf(cur + f, 0.0, maxf(cap, cur)), Q)
	e.supp = v
	e.supp_tick = w.tick
	if v >= _pin_at:
		e.pinned = true
	return v


## Shooter accuracy factor: fatigue x rank / marksman (G6Hooks.accuracy_mult). The suppressed / pinned accuracy
## penalties stay in Status.accuracy_mult (supp > 25 x0.8, pinned x0.5): single source, no double count (ORCH
## directive realism.double_count).
static func acc_mult(w: SimWorld, e: Dictionary) -> float:
	var m := 1.0
	if e.has("fat"):
		m *= Fatigue.acc_mult(e)
	if e.has("vet"):
		m *= Veterancy.acc_mult(w, e)
	return m


## Movement factor (pinned crawl x e.mvm). Movement / Status inline the same: see ORCH CR realism_move.
static func speed_mult(w: SimWorld, e: Dictionary) -> float:
	var m := pin_move if bool(e.get("pinned", false)) and not bool(e.get("broken", false)) else 1.0
	var fm = e.get("mvm")
	return m * (float(fm) if fm != null else 1.0)


## Cooldown factor from rank (Combat._fire, ORCH CR realism_reload).
static func reload_mult(e: Dictionary) -> float:
	return Veterancy.reload_mult(e) if e.has("vet") else 1.0


static func _set_or_erase(e: Dictionary, k: String, v: float) -> void:
	if absf(v - 1.0) < 1e-9:
		if e.has(k):
			e.erase(k)
	else:
		e[k] = snappedf(v, Q)


## The realism pass (see header above). Ground units in SimIndex order; leaders listed first per owner.
## G6.1 PERF61-2 (ORCH-approved behaviour change): staggered by unit id. It runs every tick for the units whose
## (tick + id) % every == REAL_PHASE, so each unit still runs once per `every` ticks with the same dt, and the
## once-per-second spike (every unit on one tick) is gone. Leaders are this tick's (positions, broken state).
static func _realism_pass(w: SimWorld, every: int) -> void:
	_ssync()
	var dt := float(every) / float(SimWorld.TICK_RATE)
	var all: Array = SimIndex.of(w, "unit")
	var uids: PackedInt32Array = SimIndex.unit_ids(w)
	var ph := posmod(REAL_PHASE - w.tick, every)   # id % every == ph  <=>  (tick + id) % every == REAL_PHASE
	var units: Array = []   # this tick's bucket, SimIndex (ascending id) order
	for i in uids.size():
		if uids[i] % every == ph:
			units.append(all[i])
	if units.is_empty():
		return
	var rest := Fatigue.rest_points(w, SimIndex.of(w, "building"))
	var ents: Dictionary = w.entities
	var lr := float(_sr.get("leader_radius", 6.0))
	var lr2 := lr * lr
	# PERF61: leaders bucketed per owner in cells of cs >= lr tiles (a 3x3 block covers radius lr; the min over
	# leaders in range is order-free, so the result is identical); is_leader_def cached per def (content-static).
	var cs := maxf(lr, 1.0)
	var lead_def := _ldef   # def -> bool
	var leaders := {}    # owner -> {Vector2i cell: [[pos, inspiring]]}
	for e in all:
		if not e.has("morale"):
			continue
		var d := String(e.get("def", ""))
		var ld = lead_def.get(d)
		if ld == null:
			ld = Veterancy.is_leader_def(d)
			lead_def[d] = ld
		if (e.has("rank_role") or bool(ld)) and ents.has(int(e.id)) and not bool(e.get("broken", false)):
			var o := int(e.owner)
			var lp: Vector2 = e.pos
			var lc := Vector2i(floori(lp.x / cs), floori(lp.y / cs))
			if not leaders.has(o):
				leaders[o] = {}
			var bk: Dictionary = leaders[o]
			var rec := [lp, Veterancy.has_trait(w, int(e.id), "inspiring")]
			for dy in range(-1, 2):   # listed in every cell of its 3x3 block: a unit reads its own cell only
				for dx in range(-1, 2):
					var nc := Vector2i(lc.x + dx, lc.y + dy)
					if not bk.has(nc):
						bk[nc] = []
					bk[nc].append(rec)
	var f_ld := float(_sr.get("leader_near", 0.85))
	var f_in := float(_sr.get("inspiring_near", 0.7))
	var f_hg := float(_sr.get("high_ground", 0.85))
	var fpen := float(_sr.get("fatigue_penalty", 0.4))
	var hgt := Elevation.has_height(w)
	var hgm: PackedByteArray = w.map.height if hgt else PackedByteArray()
	var hmw := int(w.map.w)
	var hmh := int(w.map.h)
	for e in units:
		if not ents.has(int(e.id)):
			continue
		var uf := w.tick - int(e.get("supp_tick", -100000)) < RECENT_FIRE_TICKS
		Fatigue.update_unit(w, e, dt, uf, rest)
		if uf:
			Veterancy.combat_xp(w, e, dt)
		var mv := Fatigue.speed_mult(e) if e.has("fat") else 1.0
		if e.has("vet") and int(e.vet) >= 2:
			mv *= 1.0 + Veterancy.trait_weight(w, int(e.id), "speed")
		if not e.has("morale"):
			_set_or_erase(e, "mvm", mv)
			continue
		if float(e.get("supp", 0.0)) >= _supp_at and not bool(e.get("pinned", false)):
			mv *= _mv_s
		_set_or_erase(e, "mvm", mv)
		var rz := 1.0
		if int(e.get("vet", 0)) > 0 or e.has("rank_role"):
			rz = Veterancy.supp_resist(w, e)
		else:
			var d := String(e.get("def", ""))
			var ld = lead_def.get(d)
			if ld == null:
				ld = Veterancy.is_leader_def(d)
				lead_def[d] = ld
			if bool(ld):
				rz = Veterancy.supp_resist(w, e)   # else 1.0, as supp_resist returns for a green non-leader
		rz *= Fatigue.resist_mult(e, fpen)
		var best := 1.0
		var p: Vector2 = e.pos
		var lb = leaders.get(int(e.owner))
		if lb != null:
			var lst = lb.get(Vector2i(floori(p.x / cs), floori(p.y / cs)))
			if lst != null:
				for l in lst:
					if p.distance_squared_to(l[0]) <= lr2:
						best = minf(best, f_in if bool(l[1]) else f_ld)
		rz *= best
		if hgt:   # Elevation.height_at(w, cell) > PLAIN, inlined (PLAIN off the map)
			var hx := floori(p.x)
			var hy := floori(p.y)
			var lvl := Elevation.PLAIN
			if hx >= 0 and hy >= 0 and hx < hmw and hy < hmh:
				lvl = hgm[hy * hmw + hx]
			if lvl > Elevation.PLAIN:   # PERF61-2 (ORCH-approved fix): only raised ground; PLAIN is 1, not 0
				rz *= f_hg
		_set_or_erase(e, "rz", rz)


## G6 PERF6 (CONTRACTS_G6 section 5.1): SimIndex.g6h().morale_delta(w, e) is added to morale on every morale update
## (x2 for REDUCED units, which update every 2nd time with 2x dt) when the MORALE bit of SimIndex.g6m(w)
## is set. A steady-state unit (full morale, unsuppressed) still skips the update when the delta is >= 0
## (the clamp keeps it at max); a negative delta runs the update.
static func tick(w: SimWorld) -> void:
	_process_deaths(w)
	_ssync()
	if realism_on:
		Veterancy.on_tick(w)   # G6.1 REAL61: XP from this tick's Damage events
		var every := maxi(int(Fatigue.rules().get("update_every", 20)), 1)
		_realism_pass(w, every)   # PERF61-2: this tick's id bucket
		if w.tick % every == REAL_PHASE:
			Veterancy.objectives(w)   # objective XP: once per cycle on the phase tick, as before
	if w.tick % UPDATE_EVERY != 0:
		return
	var R: Dictionary = Content.rules()
	var sup: Dictionary = R.get("suppression", {})
	var mor: Dictionary = R.get("morale", {})
	var dt := float(UPDATE_EVERY) / float(SimWorld.TICK_RATE)
	var p := {
		"decay": float(sup.get("decay_per_second", 12)) * dt,
		"pin_at": float(sup.get("pinned_at", 60)),
		"drain": float(mor.get("pinned_drain_per_second", 3)) * dt,
		"recover": float(mor.get("recover_per_second", 4)) * dt,
		"break_at": float(mor.get("break_at", 25)),
		"rally_at": float(mor.get("rally_at", 60)),
		"md": 0.0,
	}
	var g6m: bool = SimIndex.g6m(w) & SimIndex.G6_MORALE != 0
	var ctx := [null, int(w.map.w), w.map.terrain]   # [cover index (lazy), map w, terrain]
	var tiers_on := Tiers.enabled(w)
	var ents: Dictionary = w.entities
	var tick := w.tick
	# G3b PERF4-2: FULL units from the Tiers list (no pass over REDUCED units). The update phase is
	# unchanged (every unit on tick % UPDATE_EVERY == 0): per-unit staggering was tried and broke
	# phase-dependent morale scenarios (test_g2_scenarios s4), so it was not kept.
	var idx := Tiers.lists(w)
	var t0 := Time.get_ticks_usec() if SimIndex.profiling else 0
	# PERF4-4: _step_unit inlined for the FULL loop (the same steps in the same order, no call per
	# unit; steady-state units, the vast majority, return after the cover write).
	var mw: int = ctx[1]
	var terr: PackedByteArray = ctx[2]
	var nterr := terr.size()
	var fl: Array = idx.full if tiers_on else idx.kinds.get("unit", [])
	# G6 PERF6-4: the same loop as one native batch when the MORALE hook bit is clear (exact port)
	var nat_done := native_scan and not g6m and _native_full(w, fl, p, idx if tiers_on else {}, mw, terr)
	for e: Dictionary in ([] if nat_done else fl):
		if not e.has("morale") or not ents.has(int(e.id)):
			continue
		var pos: Vector2 = e.pos
		var cx := floori(pos.x)
		var cy := floori(pos.y)
		var cov := false
		if cx >= 0 and cy >= 0 and cx < mw and cy * mw + cx < nterr and terr[cy * mw + cx] == FOREST:
			cov = true
		else:
			if ctx[0] == null:
				ctx[0] = _cover_index(w)
			cov = _near_cover(ctx[0], pos)
		e.in_cover = cov
		var md: float = SimIndex.g6h().morale_delta(w, e) if g6m else 0.0
		p.md = md
		if md >= 0.0 and float(e.get("supp", 0.0)) <= 0.0 and not e.get("pinned", false) and not e.get("broken", false):
			var mm = _mmax.get(e.def)
			if float(e.morale) >= (float(mm) if mm != null else max_morale(e.def)):
				continue
		_update_unit(w, e, p)
	if SimIndex.profiling:
		t0 = SimIndex.pt("mor.full", t0)
	if not tiers_on:
		return
	# REDUCED units: every 2nd update ((id + slot) % 2 == 0, as before) with 2x dt, read from the
	# Tiers slot lists (rslot[j] holds id % 8 == j, so id % 2 == slot means j % 2 == slot)
	var p2 := p.duplicate()
	for k in ["decay", "drain", "recover"]:
		p2[k] = float(p[k]) * 2.0
	p2["g6"] = g6m
	var slot := (tick / UPDATE_EVERY) % 2
	var j := slot
	while j < Tiers.SCAN_STRIDE:
		for e: Dictionary in idx.rslot[j]:
			if not e.has("morale") or not ents.has(int(e.id)) or int(e.get("tier", 0)) != Tiers.REDUCED:
				continue
			_step_unit(w, e, p2, ctx)
		j += 2


## G6 PERF6-4: tests / bench toggle for the native FULL loop (RtsCombat.morale_scan, rts_core >= 0.5.1).
static var native_scan := true


## Cover rectangles in _cover_index source order, as their Rect2 (f32) [px, py, sx, sy].
static func _cover_rects(w: SimWorld) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var src: Array = SimIndex.of(w, "building") + SimIndex.of(w, "wreck")
	for e in src:
		if not w.entities.has(int(e.id)):
			continue
		var r: Rect2
		if e.kind == "building":
			var o: Vector2i = e.cell
			r = Rect2(Vector2(o), Vector2(float(e.size), float(e.size)))
		elif e.kind == "wreck":
			var h := float(e.get("size", 1)) * 0.5
			var wp: Vector2 = e.pos
			r = Rect2(wp - Vector2(h, h), Vector2(2.0 * h, 2.0 * h))
		else:
			continue
		out.append_array(PackedFloat32Array([r.position.x, r.position.y, r.size.x, r.size.y]))
	return out


## The FULL loop (MORALE bit clear: md = 0.0) as RtsCombat.morale_scan: cover + in_cover, steady exit and
## _update_unit's writes in native; _break / _rally run here afterwards in list order (they change only
## the unit itself, the path queue and the event log, none of which a later unit's update reads).
## False (nothing written) when the native batch is unavailable: the GDScript loop then runs.
static func _native_full(w: SimWorld, fl: Array, p: Dictionary, idx: Dictionary, mw: int, terr: PackedByteArray) -> bool:
	if fl.is_empty() or not NativeCore.enabled(w):
		return false
	var lc = w.cache.get("combat_lc")   # the shared RtsCombat (combat.gd _combat_obj, same cache key)
	if lc == null:
		lc = NativeCore.new_combat(w)
		w.cache["combat_lc"] = lc if lc != null else false
	var cobj = lc if lc is Object else null
	if cobj == null or not cobj.has_method("morale_scan"):
		return false
	var tab = w.cache.get("mor_mmax")   # per id max morale (def never changes after spawn; runtime only)
	var mm: PackedFloat64Array = tab if tab != null else PackedFloat64Array()
	if mm.size() < int(w.next_id) + 1:
		mm.resize(int(w.next_id) + 1)
	var ids := PackedInt32Array()   # combat.gd _list_ids cache of this list (empty: native reads e.id)
	var ci = idx.get("cmb_ids")
	if ci != null and is_same(ci.src, fl) and int(ci.n) == fl.size():
		ids = ci.ids
	var prm := PackedFloat64Array([float(p.decay), float(p.pin_at), float(p.drain), float(p.recover), float(p.break_at),
		float(p.rally_at), Q, COVER_R, CB, float(CB_STRIDE), float(UNDER_FIRE_TICKS), float(OUT_OF_COMBAT_TICKS), float(FOREST), 0.0])
	var rects := _cover_rects(w)
	var ents: Dictionary = w.entities
	var r: Array = cobj.morale_scan(fl, ents, ids, mm, terr, mw, rects, prm, w.tick)
	if r.size() == 1:
		for nid in r[0]:
			mm[nid] = max_morale(ents[nid].def)
		r = cobj.morale_scan(fl, ents, ids, mm, terr, mw, rects, prm, w.tick)
	w.cache["mor_mmax"] = mm
	if r.size() != 2:
		return false
	var ix: PackedInt32Array = r[0]
	var cd: PackedInt32Array = r[1]
	for k in ix.size():
		var e: Dictionary = fl[ix[k]]
		if cd[k] == 1:
			_break(w, e)
		else:
			_rally(w, e)
	return true


static func _step_unit(w: SimWorld, e: Dictionary, pu: Dictionary, ctx: Array) -> void:
	var pos: Vector2 = e.pos
	var mw: int = ctx[1]
	var terr: PackedByteArray = ctx[2]
	var cx := floori(pos.x)
	var cy := floori(pos.y)
	var cov := false
	if cx >= 0 and cy >= 0 and cx < mw and cy * mw + cx < terr.size() and terr[cy * mw + cx] == FOREST:
		cov = true
	else:
		if ctx[0] == null:
			var tc := Time.get_ticks_usec() if SimIndex.profiling else 0
			ctx[0] = _cover_index(w)
			if SimIndex.profiling:
				SimIndex.pt("mor.cover_idx", tc)
		cov = _near_cover(ctx[0], pos)
	e.in_cover = cov
	# G6: morale_delta for this update (2x for a REDUCED unit: every 2nd update, 2x dt)
	var md: float = SimIndex.g6h().morale_delta(w, e) * 2.0 if bool(pu.get("g6", false)) else 0.0
	pu["md"] = md
	# steady state (unsuppressed, full morale, not broken): nothing else can change
	if md >= 0.0 and float(e.get("supp", 0.0)) <= 0.0 and not e.get("pinned", false) and not e.get("broken", false) and float(e.morale) >= max_morale(e.def):
		return
	_update_unit(w, e, pu)


static func _update_unit(w: SimWorld, e: Dictionary, p: Dictionary) -> void:
	var since := w.tick - int(e.get("supp_tick", -100000))
	var supp := float(e.get("supp", 0.0))
	if supp > 0.0 and since >= UNDER_FIRE_TICKS:
		supp = snappedf(maxf(supp - float(p.decay), 0.0), Q)
		e.supp = supp
	var pinned := supp >= float(p.pin_at)
	e.pinned = pinned
	var m := float(e.morale)
	var mmax := max_morale(e.def)
	if pinned:
		m -= float(p.drain)
	elif since >= OUT_OF_COMBAT_TICKS:
		m += float(p.recover)
	m += float(p.get("md", 0.0))  # G6 morale_delta (+0.0 when neutral: bit-identical)
	m = snappedf(clampf(m, 0.0, mmax), Q)
	e.morale = m
	var broken := bool(e.get("broken", false))
	if not broken and m < float(p.break_at):
		_break(w, e)
	elif broken and m >= float(p.rally_at):
		_rally(w, e)


static func _break(w: SimWorld, e: Dictionary) -> void:
	e.broken = true
	e.target = -1
	var home = _home_of(w, e)
	if home == null:
		e.order = {"type": "retreat", "target": e.pos}
		Movement.stop_path(e)
	else:
		var hp: Vector2 = home
		e.order = {"type": "retreat", "target": hp}
		if not Movement.order_path(w, e, hp):
			Movement.stop_path(e)
	w.emit("UnitBroken", {"id": int(e.id), "owner": int(e.owner)})


static func _rally(w: SimWorld, e: Dictionary) -> void:
	e.broken = false
	if String(e.order.get("type", "idle")) == "retreat":
		e.order = {"type": "idle"}
		e.target = -1
		Movement.stop_path(e)
	w.emit("UnitRallied", {"id": int(e.id), "owner": int(e.owner)})


## Position of the nearest own built HQ or depot (ties -> lower id), or null.
static func _home_of(w: SimWorld, e: Dictionary):
	var pos: Vector2 = e.pos
	var best = null
	var best_d := INF
	for b in SimIndex.of(w, "building"):
		if int(b.owner) != int(e.owner) or not bool(b.get("built", false)) or not w.entities.has(int(b.id)):
			continue
		if not bool(Content.building(b.def).get("home", false)):  # G3a: flag replaces HOME_DEFS
			continue
		var bp: Vector2 = b.pos
		var d := pos.distance_squared_to(bp)
		if d < best_d:
			best_d = d
			best = bp
	return best


## Squadmate losses. Deaths come from damage.gd's queue (combat kills) and from EntityDestroyed
## events that carry a squad (if world.destroy adds it); each id counts once.
static func _process_deaths(w: SimWorld) -> void:
	var deaths: Array = []
	var seen := {}
	var q = w.cache.get("morale_deaths")
	if q != null:
		for d in q:
			if not seen.has(int(d.id)):
				seen[int(d.id)] = true
				deaths.append(d)
		w.cache.erase("morale_deaths")
	for ev in w.events:
		if ev.type == "EntityDestroyed" and ev.get("kind", "") == "unit" and ev.has("squad"):
			if not seen.has(int(ev.id)):
				seen[int(ev.id)] = true
				deaths.append({"id": int(ev.id), "owner": int(ev.owner), "squad": int(ev.squad), "pos": ev.pos})
	if deaths.is_empty():
		return
	var loss := float((Content.rules().get("morale", {}) as Dictionary).get("per_squadmate_death", 15))
	var r2 := SQUAD_RADIUS * SQUAD_RADIUS
	var want := {}   # squad -> true
	for d in deaths:
		if int(d.squad) >= 0:
			want[int(d.squad)] = true
	if want.is_empty():
		return
	var members := {}   # squad -> [living infantry of that squad], entity order
	for e in SimIndex.of(w, "unit"):
		if not e.has("morale"):
			continue
		var sq := int(e.get("squad", -1))
		if sq >= 0 and want.has(sq) and w.entities.has(int(e.id)):
			if members.has(sq):
				members[sq].append(e)
			else:
				members[sq] = [e]
	for d in deaths:
		var sq := int(d.squad)
		if sq < 0 or not members.has(sq):
			continue
		var dp: Vector2 = d.pos
		for e in members[sq]:
			if int(e.owner) != int(d.owner):
				continue
			var ep: Vector2 = e.pos
			if ep.distance_squared_to(dp) <= r2:
				var lm := Veterancy.morale_loss_mult(w, e) if (e.has("vet") or e.has("rank_role")) else 1.0  # G6.1 REAL61
				e.morale = snappedf(maxf(float(e.morale) - loss * lm, 0.0), Q)


## Buckets of cover rectangles (building footprints and wrecks), each grown by COVER_R.
## Built from current state when needed; never saved (lives only in this call).
static func _cover_index(w: SimWorld) -> Dictionary:
	var idx := {}
	var src: Array = SimIndex.of(w, "building") + SimIndex.of(w, "wreck")
	for e in src:
		if not w.entities.has(int(e.id)):
			continue
		var r: Rect2
		if e.kind == "building":
			var o: Vector2i = e.cell
			r = Rect2(Vector2(o), Vector2(float(e.size), float(e.size)))
		elif e.kind == "wreck":
			var h := float(e.get("size", 1)) * 0.5
			var wp: Vector2 = e.pos
			r = Rect2(wp - Vector2(h, h), Vector2(2.0 * h, 2.0 * h))
		else:
			continue
		var g := r.grow(COVER_R)
		for by in range(floori(g.position.y / CB), floori(g.end.y / CB) + 1):
			for bx in range(floori(g.position.x / CB), floori(g.end.x / CB) + 1):
				var k := bx + by * CB_STRIDE
				if idx.has(k):
					idx[k].append(r)
				else:
					idx[k] = [r]
	return idx


static func _near_cover(idx: Dictionary, p: Vector2) -> bool:
	var arr = idx.get(floori(p.x / CB) + floori(p.y / CB) * CB_STRIDE)
	if arr == null:
		return false
	for r in arr:
		var rr: Rect2 = r
		var q := Vector2(clampf(p.x, rr.position.x, rr.end.x), clampf(p.y, rr.position.y, rr.end.y))
		if p.distance_squared_to(q) <= COVER_R * COVER_R:
			return true
	return false
