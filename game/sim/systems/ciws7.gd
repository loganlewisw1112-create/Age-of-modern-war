extends RefCounted
## Ciws7 (owner: CIWS7). G7_REFERENCE 13.9c-32 (owner: "add in phalanx style turret(s) on top of main command building
## inside facility / future modified anti machine version of the us phlanx Gatling style turret belt fed"; owner answers
## via ORCH: 2 mounts on opposite corners of the command centre roof; air first, ground too; Facility Engineers swap
## the empty drum). Content: content/g7/defs_g7_ciws.json (def cn_ciws7 "Thresher Rotary CIWS", block ciws7). Every
## number PROVISIONAL. Original design (no copied real model): art tools/art/g7_ciws7.gd (group g7_ciws7).
##
## Mounts: when a counter-nanite facility is first seen, its two mounts are raised as real 1x1 buildings of the facility
## owner (complete, unhackable, e.cn_fac = facility id, e.ciws7 = slot) on cells of the planning zone (the 4-storey
## command centre) from ciws7.slots; e.c7m = the roof-corner mount point (range and bearing are measured from it), e.pos
## = c7m + sort_shift (the view sorts the mount over the roof; the art pivot carries the same shift + the roof height).
## Not buildable anywhere (buildable false); destroyed with the building: when the facility core (F.id) is gone or the
## facility state is gone, its mounts are destroyed (cause "ciws7_host"). Damaged mounts are repaired by the Facility
## Engineers like every facility building outside F.parts (Engineer7 external repair jobs).
##
## Fire (each tick, ascending ids): the mount needs no base power (backup power) but stops while EMP-disabled.
##  - Target: air first (the nearest enemy airborne drone within track_radius, radar cue: the mount lays onto it
##    before it is in range), else a Machine ground unit INSIDE its own compound (+ ground_pad) within ground_range
##    whose Turrets7 tags match ground_tags (crawlers / swarms / leeches / packs / light walkers / Machine infantry).
##    A held target is kept while valid; air pre-empts ground on the next scan. Ground scans share Turrets7's unit grid
##    (w.tick % 10 == 0); air checks every scan_s staggered by id.
##  - Depression limit (CIWS7-6, 13.9c-32b, owner choice "Realistic: ~25 deg limit"): the barrels cannot aim lower than
##    elev.depress_min_deg (-25, PROVISIONAL). A GROUND target whose line from the muzzle would need more depression is
##    not engageable (_ground_ok / _ground_pick skip it, a held target that walks into the ring is dropped): the blind
##    ring round the mount point, blind_radius(c, false) = ~8.63 tiles from the 15.5 m roof (air: ~8.42). Sentinels, towers
##    and wall turrets cover it. Pure function of the content and the target's range (no rng). Air and intercept
##    engagement are unchanged; no drawn or shown band is ever below the limit (el_band skips any), so an air target
##    inside the ring is laid at the lowest band.
##  - Traverse7 lay (13.9c-30, rate in rules_g7_traverse.json buildings.cn_ciws7) toward the target as seen from c7m;
##    the barrels spin up meanwhile (spin_up_s); it fires only laid, spun up, in range and outside the burst pause.
##  - Burst: rate_rpm rounds per minute (2-3 a tick), burst_min_s..burst_max_s, then pause_s; the barrels spin down
##    spin_down_s after the last target. One ShotFired per fire tick (tracer stream from the barrel cluster: muzzle7
##    tips of the art state the view draws), rounds counted from the drum.
##  - Dispersion cone (CIWS7-4, 13.9c-32a: "shooting in a strait line wherever the barrel is point w realistic bullet
##    spread the further they shoot"): the rounds leave the bore inside a cone of half-angle spread.half_mrad; the hit
##    share of a burst = the fraction of the cone's cross-section at the target's range that the target covers,
##    share = clamp((r / (d tan a))^2, 0, 1) (cone_share; r = target_r: the def radius clamped to r_min..r_max), so
##    close in the whole group lands and far out it outgrows the target. ONE rule for drones, intercepts and ground
##    fire (pure function of state, no extra rng draw): a burst whose full-share kill chance is p downs its target with
##    p_share(p, share) = 1 - (1 - p)^share; ground damage = rounds x share x damage.
##  - Air: each fire tick downs the drone with p_share(drone_p_tick, share) (w.rng), through Counterdrone._down
##    (Ciws7Kill). Ground: rounds x share x damage of ground_weapon as one Damage hit (the cone replaces the weapon's
##    flat accuracy and the old linear drone_falloff, which ciws7 no longer reads).
##  - Shells / rockets / strikes / guided missiles: Counterdrone's intercept path (def.ciws) calls can_intercept /
##    intercept: the head lays first (Counterdrone lay window incl. the spin-up still needed), a burst of
##    intercept_rounds is spent and the threat is destroyed with p_share(intercept_pk[kind], share at the threat's aim
##    point, r = spread.icpt_r) (w.rng); a miss gets through.
##  - ShotFired (ciws7) also carries the stream for the display: brg (the mount's bearing this tick: the rounds fly
##    straight along it, never bending to the target), sp (cone half-angle, rad), sh (share), rt (target radius), d
##    (range) and sd (per-fire-tick seed = tick x 977 + id x 131: the view fans its rounds from it, never randf).
##  - Drum: drum rounds. Dry = silent: the mount posts a "ciws7" job (id "ciws7:<bid>", role engineer, at the command
##    centre stair door) on the facility job board (Sentinels7.post_job) every job_every_s until it is swapped; the
##    Engineer (Engineer7 job kind "ciws7") walks to the door, climbs (climb_s), swaps the drum (swap_s: begin_swap ->
##    swap_drum, drum_ammo_cost from the side's ammo stock when it keeps one) and comes back down (down_s).
## Display (sim fields, deterministic): e.facing_i = el * 8 + ph (el = elevation band 0..4 of elev.bands_deg, CIWS7-5:
## 0..3 depressed onto ground / low drone targets, 4 level = rest, 5 high = intercepts; ph 0 idle,
## 1 spinning, 2 firing, 3 drum swap, 4 dry), e.firing = 2 while firing; turret bearing = Traverse7 (render_snap "tb").
## State (saved, hashed; created when the first facility is seen, a match without one never creates it):
##   w.sys_state.ciws7 = {ver, raised {"fac": [bid]}, m {"bid": {fac, a ammo, sp spin ticks, t target, b0 burst start,
##   pu pause until, rn fire ticks, el, job, rl swap on (1/0), eng uid, fx display-fire until}}}.
## Events: Ciws7Raised {fac, owner, ids}, ShotFired (shooter, target, weapon, hit, from, to, ciws7 true, rounds),
##   Ciws7Kill {ciws, owner, id, def, pos}, Ciws7Intercept {ciws, owner, kind, pos, hit, lay_ticks},
##   Ciws7Dry {ciws, owner}, Ciws7Reloaded {ciws, owner, unit}, EntityDestroyed via w.destroy.
## Public API (fact ciws7.api): is_mount, mounts_of, cfg, raise, ammo, can_intercept, intercept, needs_swap,
##   stair_door, begin_swap, swap_drum, job_id.

const KEY := "ciws7"
const VER := 1
const DEF := "cn_ciws7"
const TR := 20.0
const Q := 1.0 / 1024.0
const SCAN_GROUND := 10        # = Turrets7.SCAN: the ground scan shares Turrets7's per-tick unit grid
const Airdef = preload("res://sim/systems/airdef.gd")
const Traverse7 = preload("res://sim/systems/traverse7.gd")
const Turrets7 = preload("res://sim/systems/turrets7.gd")
const HotState = preload("res://sim/hot_state.gd")
const Cards8a = preload("res://sim/systems/cards8a.gd")   # G7 CARDS8A (13.9c-48): defence card fire mode / priority
const CF_PATH := "res://sim/systems/cn_facility.gd"
const CD_PATH := "res://sim/systems/counterdrone.gd"
const S7_PATH := "res://sim/systems/sentinels7.gd"
const DMG_PATH := "res://sim/systems/damage.gd"
## CIWS7-5 (13.9c-32a "wherever the barrel is point"): elevation bands the art draws (tools/art/g7_ciws7.gd reads the
## same elev.bands_deg). The band is the one whose barrel is closest to the REAL line from that band's muzzle to the
## target as the view draws it (trunnion roof_z + elev.trunnion_m up, muzzle elev.barrel_m out along the bore, the
## target elev.tz_ground_m / tz_air_m up, 4 m per tile): rest = level.
const EL_REST := 4
const EL_HIGH := 5
const EL_BANDS := [-25.0, -21.5, -18.0, -14.5, 8.0, 32.0]   # fallback when content has no elev block (CIWS7-6: nothing below DEPRESS_MIN)
const DEPRESS_MIN := -25.0   # fallback depression limit (deg) when content has no elev.depress_min_deg (13.9c-32b, PROVISIONAL)

static var _cf = null
static var _cd = null
static var _s7 = null
static var _dm = null
static var enabled := true   # test / A-B switch only (not state): false = no mounts are raised, nothing fires
static var counters := {"fire": 0, "kill": 0, "icpt": 0, "icpt_hit": 0, "ground_hits": 0, "ring_viol": 0, "watch": -1, "watch_hits": 0, "watch_min_d": 99.0}   # test / playtest evidence (not state). CIWS7-6: ring_viol = ground fire ticks at a range inside the blind ring (must stay 0); watch = a target id whose ground hits / nearest fired-on range are tallied


static func CF():
	if _cf == null:
		_cf = load(CF_PATH)
	return _cf


static func CD():
	if _cd == null:
		_cd = load(CD_PATH)
	return _cd


static func S7():
	if _s7 == null and ResourceLoader.exists(S7_PATH):
		_s7 = load(S7_PATH)
	return _s7


static func DM():
	if _dm == null:
		_dm = load(DMG_PATH)
	return _dm


# ================================================================ content
static func cfg() -> Dictionary:
	return Content.building(DEF).get("ciws7", {})


static func is_mount(b) -> bool:
	return b is Dictionary and String(b.get("kind", "")) == "building" and Content.building(String(b.get("def", ""))).has("ciws7")


static func ticks(sec: float) -> int:
	return maxi(roundi(sec * TR), 1)


static func _c(b: Dictionary) -> Dictionary:
	return Content.building(String(b.def)).get("ciws7", {})


## Rounds fired on fire tick n (0-based) of a mount: rate_rpm spread evenly over the ticks (integers only).
static func rounds_at(c: Dictionary, n: int) -> int:
	var per_min := int(c.get("rate_rpm", 3000))
	var den := int(TR) * 60
	return (n + 1) * per_min / den - n * per_min / den


# ================================================================ dispersion cone (CIWS7-4, 13.9c-32a)
## Depression limit (deg, negative = below level): the lowest pitch the barrels can take (CIWS7-6, 13.9c-32b, owner choice
## "Realistic: ~25 deg limit").
static func depress_min(c: Dictionary) -> float:
	return float((c.get("elev", {}) as Dictionary).get("depress_min_deg", DEPRESS_MIN))


## Horizontal distance (tiles, from the mount point) inside which a target at height `gz` m cannot be aimed at: the bore
## at the depression limit p0 passes through the target at exactly this range. Closed form of "the line from the muzzle
## (trunnion roof_z + trunnion_m up, trunnion_fwd_m forward, barrel_m out along the bore at p0) to the target has pitch
## p0": hz = barrel_m cos p0 + (gz - tz - barrel_m sin p0) / tan p0, range = (hz + trunnion_fwd_m) / tile_m. 0 when there is
## no limit (p0 <= -89 deg or p0 >= 0). Pure function of the content.
static func blind_radius(c: Dictionary, air: bool) -> float:
	var E: Dictionary = c.get("elev", {})
	var lim := depress_min(c)
	if lim <= -89.0 or lim >= -0.5:
		return 0.0
	var p0 := deg_to_rad(lim)
	var tz := float(c.get("roof_z", 15.5)) + float(E.get("trunnion_m", 1.54))
	var gz := float(E.get("tz_air_m", 1.4)) if air else float(E.get("tz_ground_m", 1.0))
	var bl := float(E.get("barrel_m", 2.54))
	var hz := bl * cos(p0) + (gz - tz - bl * sin(p0)) / tan(p0)
	return maxf(hz + float(E.get("trunnion_fwd_m", 0.14)), 0.0) / maxf(float(E.get("tile_m", 4.0)), 0.01)


## True when a target at range d (tiles from the mount point) is inside the blind ring: aiming at it would need more
## depression than the limit. Ground targets in the ring are not engageable (CIWS7-6); the ring edge itself is not blind.
static func blind(c: Dictionary, d: float, air: bool = false) -> bool:
	return d < blind_radius(c, air)


## Elevation band (0..5, never the rest band) for a target at range d (tiles) from the mount point: the band whose barrel (pitch p) is
## closest to the line from ITS muzzle (trunnion + barrel_m along p) to the target, in degrees (pure; CIWS7-5). CIWS7-6: a
## band below the depression limit is never chosen, so an air target inside the ring is laid at the lowest allowed band.
static func el_band(c: Dictionary, d: float, air: bool) -> int:
	var E: Dictionary = c.get("elev", {})
	var bands: Array = E.get("bands_deg", EL_BANDS)
	var lim := depress_min(c)
	var tz := float(c.get("roof_z", 15.5)) + float(E.get("trunnion_m", 1.54))
	var hz := d * float(E.get("tile_m", 4.0)) - float(E.get("trunnion_fwd_m", 0.14))
	var gz := float(E.get("tz_air_m", 1.4)) if air else float(E.get("tz_ground_m", 1.0))
	var bl := float(E.get("barrel_m", 2.54))
	var best := EL_REST
	var bd := 1e9
	for i in bands.size():
		if i == EL_REST or float(bands[i]) < lim - 0.001:
			continue
		var p := deg_to_rad(float(bands[i]))
		var a := atan2(gz - (tz + bl * sin(p)), maxf(hz - bl * cos(p), 0.5))
		var dd := absf(p - a)
		if dd < bd:
			bd = dd
			best = i
	return best


static func spread_of(c: Dictionary) -> Dictionary:
	return c.get("spread", {})


## Cone half-angle (radians) of mount content c.
static func half_angle(c: Dictionary) -> float:
	return float(spread_of(c).get("half_mrad", 80.0)) * 0.001


## Fraction of a cone of half-angle `half` that a target of radius r covers at range d (tiles): (r / (d tan a))^2,
## clamped to [0, 1]. 1 while the whole group fits on the target; falls with the square of the range past that.
static func cone_share(d: float, r: float, half: float) -> float:
	var rc := maxf(d, 0.05) * tan(maxf(half, 0.0001))
	return clampf((r / rc) * (r / rc), 0.0, 1.0)


## Presented radius (tiles) of target t: its unit def radius, clamped to spread r_min .. r_max (r_default otherwise).
static func target_r(c: Dictionary, t: Dictionary) -> float:
	var sp := spread_of(c)
	var r := float(sp.get("r_default", 0.4))
	if String(t.get("kind", "")) == "unit":
		r = float(Content.unit(String(t.get("def", ""))).get("radius", r))
	return clampf(r, float(sp.get("r_min", 0.25)), float(sp.get("r_max", 1.2)))


## Chance a burst downs its target when its full-share chance is p and only a share s of its rounds lands on it.
static func p_share(p: float, s: float) -> float:
	return 1.0 - pow(clampf(1.0 - p, 0.0, 1.0), clampf(s, 0.0, 1.0))


# ================================================================ state
static func state(w: SimWorld):
	return w.sys_state.get(KEY)


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"ver": VER, "raised": {}, "m": {}}
	return w.sys_state[KEY]


static func _rec(w: SimWorld, bid: int):
	var st = state(w)
	return null if st == null else (st.m as Dictionary).get(str(bid))


## Mount ids of facility fac (ascending; live ones only).
static func mounts_of(w: SimWorld, fac: int) -> Array:
	var out := []
	var st = state(w)
	if st == null:
		return out
	for bid in st.raised.get(str(fac), []):
		if w.entities.has(int(bid)):
			out.append(int(bid))
	out.sort()
	return out


## Rounds left in mount bid's drum (-1 = not a mount).
static func ammo(w: SimWorld, bid: int) -> int:
	var M = _rec(w, bid)
	return -1 if M == null else int(M.a)


static func job_id(bid: int) -> String:
	return "ciws7:%d" % bid


# ================================================================ raising
## Raises facility F's mounts (once per facility); returns the new ids.
static func raise(w: SimWorld, F: Dictionary) -> Array:
	var out := []
	var st := _st(w)
	var fk := str(int(F.id))
	if st.raised.has(fk):
		return out
	var c := cfg()
	var O: Vector2i = CF().origin(F)
	var owner := int(F.owner)
	var sh := float(c.get("sort_shift", 0.6))
	var slots: Array = c.get("slots", [])
	for i in slots.size():
		var s: Array = slots[i]
		var cell := O + Vector2i(int(s[0]), int(s[1]))
		if not w.in_bounds(cell):
			continue
		var bid := w.spawn_building(DEF, owner, cell, true)
		var e: Dictionary = w.entities[bid]
		e.unhackable = true
		e.cn_fac = int(F.id)
		e.ciws7 = i
		var mp := Vector2(O) + Vector2(float(s[2]), float(s[3]))
		mp = Vector2(snappedf(mp.x, Q), snappedf(mp.y, Q))
		e.c7m = mp
		e.pos = Vector2(snappedf(mp.x + sh, Q), snappedf(mp.y + sh, Q))
		e.facing_i = EL_REST * 8
		e.firing = 0
		HotState.touch(w, bid)
		st.m[str(bid)] = {"fac": int(F.id), "a": int(c.get("drum", 1200)), "sp": 0, "t": -1, "b0": -1, "pu": 0, "rn": 0,
			"el": EL_REST, "job": 0, "rl": 0, "eng": -1, "fx": 0}
		out.append(bid)
	st.raised[fk] = out.duplicate()
	w.emit("Ciws7Raised", {"fac": int(F.id), "owner": owner, "ids": out.duplicate()})
	return out


static func _raise_new(w: SimWorld, cn: Dictionary) -> void:
	if Content.building(DEF).is_empty():
		return
	var st = state(w)
	var ks := []
	for k in cn.facs:
		ks.append(int(k))
	ks.sort()
	for k in ks:
		if st == null or not (st.raised as Dictionary).has(str(k)):
			raise(w, cn.facs[str(k)])
			st = state(w)


# ================================================================ targeting
static func _airborne(t: Dictionary) -> bool:
	return Turrets7._airborne(t)


## Nearest airborne enemy drone of b within r of the mount point (ties -> lower id), or null.
static func _air_pick(w: SimWorld, b: Dictionary, mp: Vector2, r: float):
	var best = null
	var bd := r * r
	for id in Airdef.sub_list(w, "drone"):
		var d = w.entities.get(id)
		if d == null or not w.is_enemy(int(b.owner), int(d.owner)) or bool(d.get("air_landed", false)):
			continue
		var dd := mp.distance_squared_to(Vector2(d.pos))
		if dd <= bd and (best == null or dd < bd):
			best = d
			bd = dd
	return best


static func _ground_ok(w: SimWorld, b: Dictionary, c: Dictionary, mp: Vector2, t: Dictionary, area: Rect2) -> bool:
	if t.kind != "unit" or not w.entities.has(int(t.id)) or not w.is_enemy(int(b.owner), int(t.owner)) or _airborne(t):
		return false
	var p := HotState.get_pos(w, int(t.id))
	var dg := p.distance_to(mp)
	if not area.has_point(p) or dg > float(c.get("ground_range", 15.0)):
		return false
	if blind(c, dg, false):   # CIWS7-6 (13.9c-32b): the barrels cannot depress that far: a target in the blind ring is never engaged
		return false
	var m := Turrets7.tags_of(w, t)
	return m & Turrets7.bit("machine") != 0 and m & Turrets7.bits_of(c.get("ground_tags", [])) != 0


## The compound (+ ground_pad) of mount b's facility; empty when the facility is gone.
static func _area(w: SimWorld, M: Dictionary, c: Dictionary) -> Rect2:
	var F: Dictionary = CF().fac(w, int(M.fac))
	if F.is_empty():
		return Rect2()
	return CF().compound_rect(F).grow(float(c.get("ground_pad", 0.5)))


## Nearest valid Machine ground unit inside the compound (ties -> lower id), or null.
static func _ground_pick(w: SimWorld, b: Dictionary, c: Dictionary, M: Dictionary, mp: Vector2):
	var area := _area(w, M, c)
	if area.size == Vector2.ZERO:
		return null
	var best = null
	var bd := INF
	for t in Turrets7._near(w, int(b.owner), mp, float(c.get("ground_range", 15.0)), true):
		if not _ground_ok(w, b, c, mp, t, area):
			continue
		var dd := HotState.get_pos(w, int(t.id)).distance_squared_to(mp)
		if dd < bd or (dd == bd and best != null and int(t.id) < int(best.id)):
			best = t
			bd = dd
	return best


static func _tpos(w: SimWorld, t: Dictionary) -> Vector2:
	return HotState.get_pos(w, int(t.id)) if t.kind == "unit" else Vector2(t.pos)


# ================================================================ system
static func tick(w: SimWorld) -> void:
	if not enabled:
		return
	var cn = w.sys_state.get("cn_facility")
	var st = w.sys_state.get(KEY)
	if cn == null and st == null:
		return
	if cn != null and w.tick % 10 == 3:
		_raise_new(w, cn)
		st = w.sys_state.get(KEY)
	if st == null or (st.m as Dictionary).is_empty():
		return
	var ks := []
	for k in st.m:
		ks.append(int(k))
	ks.sort()
	var hc := ticks(float(cfg().get("host_check_s", 0.5)))
	for bid in ks:
		var M: Dictionary = st.m[str(bid)]
		var b = w.entities.get(bid)
		if b == null or String(b.get("kind", "")) != "building":
			_drop(w, st, bid, M)
			continue
		if (w.tick + bid) % hc == 0 and not _host_ok(w, M):
			_drop(w, st, bid, M)
			w.destroy(bid, "ciws7_host", SimWorld.NEUTRAL)
			continue
		_tick_mount(w, st, b, M)


static func _host_ok(w: SimWorld, M: Dictionary) -> bool:
	var fac := int(M.fac)
	return w.entities.has(fac) and not CF().fac(w, fac).is_empty()


static func _drop(w: SimWorld, st: Dictionary, bid: int, M: Dictionary) -> void:
	if int(M.get("job", 0)) == 1 and S7() != null:
		S7().done_job(w, int(M.fac), job_id(bid))
	(st.m as Dictionary).erase(str(bid))


static func _disp(b: Dictionary, M: Dictionary, ph: int, firing: bool) -> void:
	b.facing_i = clampi(int(M.el), 0, EL_HIGH) * 8 + ph
	b.firing = 2 if firing else 0


static func _spin_down(w: SimWorld, M: Dictionary, c: Dictionary) -> void:
	if int(M.sp) <= 0:
		return
	if w.tick - int(M.get("lt", 0)) >= ticks(float(c.get("spin_down_s", 2.0))):
		M.sp = 0


static func _end_burst(w: SimWorld, M: Dictionary, c: Dictionary) -> void:
	if int(M.b0) >= 0:
		M.b0 = -1
		# fire resumes at t >= pu: + 1 so the silent gap is the full pause (ticks(pause_s) ticks), not one short
		M.pu = w.tick + ticks(float(c.get("pause_s", 0.25))) + 1


static func _tick_mount(w: SimWorld, st: Dictionary, b: Dictionary, M: Dictionary) -> void:
	var c := _c(b)
	var bid := int(b.id)
	var t := int(w.tick)
	if int(M.a) <= 0:
		M.t = -1
		M.b0 = -1
		_spin_down(w, M, c)
		if int(M.rl) == 1:
			if (t + bid) % 20 == 0 and not _swap_alive(w, M, bid):
				M.rl = 0
				M.eng = -1
			M.el = EL_REST
			_disp(b, M, 3 if int(M.rl) == 1 else 4, false)
		else:
			M.el = EL_REST
			_disp(b, M, 4, false)
		if (t + bid) % ticks(float(c.get("job_every_s", 2.0))) == 0:
			_post_job(w, b, M, c)
		return
	if not Airdef.source_active(w, b):
		M.t = -1
		_end_burst(w, M, c)
		_spin_down(w, M, c)
		_disp(b, M, 0, false)
		return
	var mp: Vector2 = b.get("c7m", b.pos)
	var tgt = w.entities.get(int(M.t)) if int(M.t) >= 0 else null
	var air := tgt != null and _airborne(tgt)
	if tgt != null:
		if air:
			if not w.is_enemy(int(b.owner), int(tgt.owner)) or mp.distance_to(Vector2(tgt.pos)) > float(c.get("track_radius", 15.0)):
				tgt = null
		elif not _ground_ok(w, b, c, mp, tgt, _area(w, M, c)):
			tgt = null
	if tgt == null or not air:
		var sc := ticks(float(c.get("scan_s", 0.5)))
		if tgt == null or (t + bid) % sc == 0:
			var a = _air_pick(w, b, mp, float(c.get("track_radius", 15.0)))
			if a != null:
				tgt = a
				air = true
		if tgt == null and t % SCAN_GROUND == 0:
			tgt = _ground_pick(w, b, c, M, mp)
			air = false
	if tgt != null and w.sys_state.has("cards8a"):   # G7 CARDS8A (13.9c-48): hold / return fire / priority
		var tr := float(c.get("track_radius", 15.0))
		var ar := _area(w, M, c)
		tgt = Cards8a.filter(w, b, tgt, maxf(tr, float(c.get("ground_range", 15.0))), func(x): return (_airborne(x) and w.is_enemy(int(b.owner), int(x.owner)) and mp.distance_to(Vector2(x.pos)) <= tr) or _ground_ok(w, b, c, mp, x, ar))
		air = tgt != null and _airborne(tgt)
	if tgt == null or int(tgt.id) != int(M.t):
		_end_burst(w, M, c)
	if tgt == null:
		M.t = -1
		_spin_down(w, M, c)
		var fxo := t < int(M.get("fx", 0))
		if not fxo and int(M.sp) <= 0:   # back to rest once the barrels stopped (spin-down / intercept display keep the band)
			M.el = EL_REST
		_disp(b, M, 2 if fxo else (1 if int(M.sp) > 0 else 0), fxo)
		return
	M.t = int(tgt.id)
	var tp := _tpos(w, tgt)
	var d := mp.distance_to(tp)
	M.el = el_band(c, d, air)
	var full := ticks(float(c.get("spin_up_s", 0.5)))
	M.sp = mini(int(M.sp) + 1, full)
	M.lt = t
	var laid := Traverse7.lay(w, b, tp + (Vector2(b.pos) - mp), 1.0 / TR, false, int(tgt.id))
	var rng_ok := d <= (float(c.get("air_radius", 10.0)) if air else float(c.get("ground_range", 15.0)))
	if not laid or not rng_ok or int(M.sp) < full or t < int(M.pu):
		_disp(b, M, 1, false)
		return
	if int(M.b0) < 0:
		M.b0 = t
	var n := mini(rounds_at(c, int(M.rn)), int(M.a))
	M.rn = int(M.rn) + 1
	M.a = int(M.a) - n
	counters.fire += 1
	var done := false
	var wid := String(c.get("ground_weapon", ""))
	# 13.9c-32a: the cone's hit share at this range (one rule for air and ground) + the stream for the display
	var half := half_angle(c)
	var rt := target_r(c, tgt)
	var sh := cone_share(d, rt, half)
	var sev := {"shooter": bid, "target": int(tgt.id), "weapon": wid, "hit": true, "from": mp, "to": tp,
		"indirect": false, "ciws7": true, "rounds": n, "brg": Traverse7.bearing(w, b, t), "sp": half, "sh": sh, "rt": rt,
		"d": d, "sd": t * 977 + bid * 131}
	if air:
		var hit := w.rng.chance(p_share(float(c.get("drone_p_tick", 0.3)), sh))
		sev.hit = hit
		w.emit("ShotFired", sev)
		if hit:
			counters.kill += 1
			w.emit("Ciws7Kill", {"ciws": bid, "owner": int(b.owner), "id": int(tgt.id), "def": String(tgt.def), "pos": tp})
			CD()._down(w, tgt, b, "ciws7")
			done = true
	else:
		var wd: Dictionary = Content.weapon(wid)
		var dmg := float(n) * sh * float(wd.get("damage", 6.0))
		sev.hit = sh > 0.0
		w.emit("ShotFired", sev)
		counters.ground_hits += 1
		if blind(c, d, false):   # tripwire only (_ground_ok already refuses these): evidence for the tests / playtest
			counters["ring_viol"] = int(counters.get("ring_viol", 0)) + 1
		if int(tgt.id) == int(counters.get("watch", -1)):
			counters["watch_hits"] = int(counters.get("watch_hits", 0)) + 1
			counters["watch_min_d"] = minf(float(counters.get("watch_min_d", 99.0)), d)
		DM().apply_hit(w, b, tgt, {"weapon": wid, "cls": String(wd.get("class", "autocannon")), "damage": dmg}, true)
		done = not w.entities.has(int(tgt.id))
	_disp(b, M, 2, true)
	if int(M.a) <= 0:
		M.b0 = -1
		w.emit("Ciws7Dry", {"ciws": bid, "owner": int(b.owner)})
		_post_job(w, b, M, c)
		return
	var dur := t - int(M.b0) + 1
	if dur >= ticks(float(c.get("burst_max_s", 1.5))) or (done and dur >= ticks(float(c.get("burst_min_s", 0.4)))):
		_end_burst(w, M, c)
	if done:
		M.t = -1


# ================================================================ intercept path (Counterdrone delegates, def.ciws)
## True when mount b may take an intercept now (rounds in the drum, no drum swap, not EMP-disabled).
static func can_intercept(w: SimWorld, b: Dictionary) -> bool:
	var M = _rec(w, int(b.id))
	return M != null and int(M.a) > 0 and int(M.rl) == 0 and Airdef.source_active(w, b)


## Ticks of spin-up mount b still needs before it can fire (added to the lay time of an intercept).
static func spin_left(w: SimWorld, b: Dictionary) -> int:
	var M = _rec(w, int(b.id))
	if M == null:
		return 0
	return maxi(ticks(float(_c(b).get("spin_up_s", 0.5))) - int(M.sp), 0)


## Mount b fires an intercept burst at a threat landing at `at` (laid in lt ticks): spends intercept_rounds, rolls
## intercept_pk[kind] (w.rng). Returns true when the threat is destroyed.
static func intercept(w: SimWorld, b: Dictionary, at: Vector2, lt: int, kind: String) -> bool:
	var M = _rec(w, int(b.id))
	if M == null:
		return false
	var c := _c(b)
	var n := mini(int(c.get("intercept_rounds", 60)), int(M.a))
	M.a = int(M.a) - n
	M.sp = ticks(float(c.get("spin_up_s", 0.5)))
	M.lt = w.tick
	M.el = EL_HIGH
	M.fx = w.tick + maxi(lt, 0) + maxi(ceili(float(n) / maxf(float(c.get("rate_rpm", 3000)) / 60.0 / TR, 0.1)), 1)
	var pk: Dictionary = c.get("intercept_pk", {})
	var mp: Vector2 = b.get("c7m", b.pos)
	# 13.9c-32a: the same cone rule, at the threat's aim point (the burst meets it as it comes down on it)
	var d := mp.distance_to(at)
	var half := half_angle(c)
	var rt := float(spread_of(c).get("icpt_r", 0.5))
	var sh := cone_share(d, rt, half)
	var hit := w.rng.chance(p_share(float(pk.get(kind, pk.get("default", 0.75))), sh))
	counters.icpt += 1
	if hit:
		counters.icpt_hit += 1
	_disp(b, M, 2, true)
	w.emit("ShotFired", {"shooter": int(b.id), "target": -1, "weapon": String(c.get("ground_weapon", "")), "hit": hit,
		"from": mp, "to": at, "indirect": false, "ciws7": true, "rounds": n, "lay_ticks": lt,
		"brg": Traverse7.bearing(w, b, int(w.tick)), "sp": half, "sh": sh, "rt": rt, "d": d, "icpt": kind,
		"sd": int(w.tick) * 977 + int(b.id) * 131})
	w.emit("Ciws7Intercept", {"ciws": int(b.id), "owner": int(b.owner), "kind": kind, "pos": at, "hit": hit, "lay_ticks": lt})
	if int(M.a) <= 0:
		w.emit("Ciws7Dry", {"ciws": int(b.id), "owner": int(b.owner)})
	return hit


# ================================================================ drum swap (Engineer7 job kind "ciws7")
static func needs_swap(w: SimWorld, bid: int) -> bool:
	var M = _rec(w, bid)
	return M != null and int(M.a) <= 0 and w.entities.has(bid)


## World point of the command centre stair door (the engineer's job position) of mount bid's facility.
static func stair_door(w: SimWorld, bid: int) -> Vector2:
	var M = _rec(w, bid)
	var F: Dictionary = CF().fac(w, int(M.fac)) if M != null else {}
	if F.is_empty():
		var b = w.entities.get(bid)
		return Vector2(b.pos) if b != null else Vector2.ZERO
	var dr: Array = cfg().get("door", [12.5, 10.5])
	return Vector2(CF().origin(F)) + Vector2(float(dr[0]), float(dr[1]))


static func _post_job(w: SimWorld, b: Dictionary, M: Dictionary, c: Dictionary) -> void:
	var s7 = S7()
	if s7 == null:
		return
	var bid := int(b.id)
	s7.post_job(w, int(M.fac), {"id": job_id(bid), "kind": "ciws7", "pos": stair_door(w, bid), "prio": float(c.get("job_prio", 3.5)),
		"roles": ["engineer"], "slots": 1, "bid": bid, "ttl_s": float(c.get("job_ttl_s", 8.0))})
	M.job = 1


static func _swap_alive(w: SimWorld, M: Dictionary, bid: int) -> bool:
	var e = w.entities.get(int(M.get("eng", -1)))
	if e == null or S7() == null:
		return false
	return String(S7().job_of(w, int(e.id)).get("j", "")) == job_id(bid)


## The engineer uid is on the roof at mount bid: the drum swap starts (the mount shows its swap frames).
static func begin_swap(w: SimWorld, bid: int, uid: int) -> bool:
	var M = _rec(w, bid)
	if M == null or int(M.a) > 0:
		return false
	M.rl = 1
	M.eng = uid
	return true


## Completes the drum swap of mount bid by engineer uid: drum_ammo_cost from the side's ammo stock (when it keeps one;
## false = not enough, try again), a full drum, the board job taken down. Returns true when swapped.
static func swap_drum(w: SimWorld, bid: int, uid: int) -> bool:
	var M = _rec(w, bid)
	var b = w.entities.get(bid)
	if M == null or b == null:
		return false
	var c := _c(b)
	var cost := int(c.get("drum_ammo_cost", 0))
	var fac = w.factions[int(b.owner)] if int(b.owner) >= 0 and int(b.owner) < w.factions.size() else null
	if cost > 0 and fac != null and (fac.stock as Dictionary).has("ammo"):
		if int(fac.stock.ammo) < cost:
			return false
		fac.stock.ammo = int(fac.stock.ammo) - cost
	M.a = int(c.get("drum", 1200))
	M.rl = 0
	M.eng = -1
	M.rn = 0
	if int(M.get("job", 0)) == 1 and S7() != null:
		S7().done_job(w, int(M.fac), job_id(bid))
	M.job = 0
	_disp(b, M, 0, false)
	w.emit("Ciws7Reloaded", {"ciws": bid, "owner": int(b.owner), "unit": uid})
	return true


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "Unknown CIWS command."


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
