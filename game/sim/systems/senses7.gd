extends RefCounted
## G7 SENSE7: realistic senses + per-squad knowledge (G7 master scope section 2 "Realistic senses", section 3
## "Per-squad knowledge"). Numbers: content/g7/rules_g7_senses.json rules.g7_senses (all PROVISIONAL). No class_name: preload it.
##
## How it plugs in (small hooks, nothing rewritten):
## - Spot gate. The fog grid (fog.gd) stays the coarse "could be seen" stamp. Every spot_every ticks, per TEAM
##   (staggered), Senses7.tick (called from Fog.tick, which runs after Combat) re-checks every enemy INFANTRY unit
##   standing on a team-visible cell: is any observer of the team actually spotting it? The ones nobody spots go
##   into the team's hidden set (saved, hashed); Fog.concealed() returns true for them, so combat target search,
##   AI (visible_enemies), Intel and the player's fog/markers all honour the senses through the one existing gate.
##   Firing reveals (the G2 muzzle rule, reveal_ticks). Vehicles, aircraft and buildings as TARGETS keep the fog
##   grid rule (big, loud: their simple profile is "seen inside sight").
## - Observers. Infantry: a view cone from the head (e.facing): full range inside cone_deg; peripheral up to
##   periph_deg spots MOVEMENT only (periph_mult range); nothing behind except within `near` (footsteps). Scopes
##   (optics_defs / def.optics): optics_deg cone at optics_mult range. Thermals / NVG (thermal_defs, def.thermal,
##   def.nvg, e.nvg; aircraft when air_thermal) ignore smoke and darkness. Vehicles / aircraft / buildings: 360
##   degrees at sight x their mult. Unconscious soldiers see nothing. Machine observers keep their own sensor rule:
##   omni, through smoke and dark, plain sight range (= the old behaviour), so a Machine-only team never hides
##   anything (its hidden set stays empty).
## - Target silhouette: posture (prone keys / gait 1-2 = crouch), forest cover, light (st.light, 1 = day), movement
##   (move_mult). Effective range = observer range x silhouette.
## - Smoke: clouds from add_smoke() plus every Apc7 smoke panel (a7.smoke_until); a sight line through a cloud is
##   blocked unless the observer has thermals.
## - Hearing: ShotFired events (and noise_events blasts) are collected each tick; at the team pass a shot from a
##   shooter the team does not see, within hear_range (hear_range_loud for indirect fire / blasts) of a team unit,
##   becomes a HEARD contact: a guessed position (error = heard_err_frac x distance, a pure hash, no RNG draw),
##   direction and rough distance from the listener. Gunfire also goes to Intel as an unidentified "heard" contact
##   (conf = intel_report_conf) so AI reacts to it; blasts stay in the heard list only (no fake enemy).
## - Per-squad knowledge: a squad on the radio net shares its side's picture (Intel: own sight + reports + drones).
##   A squad that is cut off (CommandNet comms_state cut / jammed, or a forced cut) takes a SNAPSHOT of what it knew
##   and from then on only adds what its own soldiers see and hear; its contacts age (stale). Back on the net, the
##   snapshot is dropped. Squad key = e.squad (>= 0) or -id for a unit outside a squad.
## - Cost: per team every spot_every ticks; observers bucketed once per pass (REDUCED-tier units skipped: they have
##   no enemy within contact radius); targets that fired recently cost nothing; per-target checks capped
##   (max_checks, max_checks_big when the team has > big_n observers) and fail open (= old behaviour).
## - Off switch: rules g7_senses enabled=false (or cfg.g7_senses=false): no state, no hidden set, old behaviour.
##
## Saved state (hashed): w.sys_state.senses7 = {ver, spot: {team: {eid: 1}} (enemy soldiers spotted at the last
##   pass; absent team = no gate, e.g. a Machine-only team), hq: {shooter: [pos, owner, tick, loud]},
##   heard: {team: {cluster: {pos, t, err, dir, dist, from, sq, fid, kind}}}, hc: {fid: {cluster: intel cid}},
##   kn: {fid: {sq: {t0, c: {eid: [pos, t, src]}}}}, cut: {fid: {sq: 1}}, smoke: [[x, y, r, until]], light, pass}
##
## API (fact senses.api): enabled, hidden, can_see, squad_key, cut_off, knowledge, knows, last_known,
##   suppress_point, heard, add_smoke, set_light, force_cut.

const SimIndex = preload("res://sim/systems/sim_index.gd")
const Tiers = preload("res://sim/systems/tiers.gd")

const CFG_PATH := "res://content/g7/rules_g7_senses.json"
const VER := 1
const TPS := 20.0
const KST := 4096
const P_INF := 0
const P_VEH := 1
const P_AIR := 2
const P_BLD := 3
const P_MACH := 4

## Tests / bench A/B: -1 = rules, 0 = off, 1 = on.
static var force := -1
static var _cfg: Dictionary = {}
static var _prof: Dictionary = {}   # "kind:def" -> [code, sight, optics, thermal]
static var _inf: Dictionary = {}    # unit def -> infantry target?
## Bench-only profiler (usec totals; never touches sim state).
static var prof := {"tick": 0, "spot": 0, "hear": 0, "squads": 0}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var d := {"enabled": true, "spot_every": 8}
		if FileAccess.file_exists(CFG_PATH):
			var j = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
			if j is Dictionary:
				var g: Dictionary = j.get("rules", {}).get("g7_senses", {})
				for k in g:
					d[k] = g[k]
		_cfg = d
	return _cfg


static func cf(k: String, d: float) -> float:
	return float(cfg().get(k, d))


static func enabled(w: SimWorld) -> bool:
	if force >= 0:
		return force == 1
	var c = w.cfg.get("g7_senses")
	if c != null:
		return bool(c)
	var r = Content.rules().get("g7_senses")
	if r is Dictionary and r.has("enabled"):
		return bool(r.enabled)
	return bool(cfg().get("enabled", true))


static func state(w: SimWorld) -> Dictionary:
	if not w.sys_state.has("senses7"):
		w.sys_state["senses7"] = {"ver": VER, "spot": {}, "hq": {}, "heard": {}, "hc": {}, "kn": {}, "cut": {},
			"smoke": [], "light": 1.0, "pass": 0}
	return w.sys_state["senses7"]


## Team key of side fid: the lowest fid of its team (allies share one fog grid, one hidden set).
static func tkey(w: SimWorld, fid: int) -> int:
	var tm = w.cache.get("s7_tk")
	if tm == null or int(tm.get("_n", -1)) != w.factions.size():
		tm = {"_n": w.factions.size()}
		var fids: Array = w.factions.keys()
		fids.sort()
		for a in fids:
			var k := int(a)
			for b in fids:
				if int(b) < k and w.is_ally(int(a), int(b)):
					k = int(b)
			tm[int(a)] = k
		w.cache["s7_tk"] = tm
	return int(tm.get(fid, fid))


static func _teams(w: SimWorld) -> Array:
	var out := []
	var fids: Array = w.factions.keys()
	fids.sort()
	for f in fids:
		var k := tkey(w, int(f))
		if not out.has(k):
			out.append(k)
	return out


static func _members(w: SimWorld, tk: int) -> Array:
	var out := []
	var fids: Array = w.factions.keys()
	fids.sort()
	for f in fids:
		if tkey(w, int(f)) == tk:
			out.append(int(f))
	return out


static func _is_machine(w: SimWorld, fid: int) -> bool:
	var f = w.factions.get(fid)
	return f != null and String(f.get("faction_def", "")) == "machine"


## Is enemy entity e hidden from side fid by the senses (Fog.concealed hook)? Cheap: one dict lookup.
## Fail-closed: an enemy soldier is seen only when the team's last pass spotted him (or he fired: the muzzle rule
## in Fog.concealed runs first), so one stepping onto a visible cell between passes stays unseen until the next
## pass (<= spot_every ticks, ~0.8 s: a reaction time) instead of leaking through for free.
static func hidden(w: SimWorld, fid: int, e: Dictionary) -> bool:
	var st = w.sys_state.get("senses7")
	if st == null:
		return false
	var sp = st.spot.get(tkey(w, fid))
	return sp != null and not sp.has(int(e.id)) and is_inf_target(e)


## Squad key of a unit: e.squad when in a squad, else -id.
static func squad_key(e: Dictionary) -> int:
	var s := int(e.get("squad", -1))
	return s if s >= 0 else -int(e.id)


## Tests / scenarios / EW: force squad sq of side fid cut off the radio (on=false clears the force).
static func force_cut(w: SimWorld, fid: int, sq: int, on: bool = true) -> void:
	var st := state(w)
	if not st.cut.has(fid):
		st.cut[fid] = {}
	if on:
		st.cut[fid][sq] = 1
	else:
		st.cut[fid].erase(sq)


## Smoke cloud at pos (radius r tiles, secs seconds): blocks sight lines except for thermals.
static func add_smoke(w: SimWorld, pos: Vector2, r: float = -1.0, secs: float = 12.0) -> void:
	var rr := r if r > 0.0 else cf("smoke_radius", 3.0)
	state(w).smoke.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), rr, w.tick + int(secs * TPS)])


## Ambient light 0..1 (1 = day). Darkness shrinks sight for everyone without thermals / NVG.
static func set_light(w: SimWorld, l: float) -> void:
	state(w).light = clampf(l, 0.05, 1.0)


## Heard contacts of side fid's team: [{pos (guess), err, dir (rad, listener -> sound), dist, from, age (s), kind:
## gunfire|blast}], sorted by age then x.
static func heard(w: SimWorld, fid: int) -> Array:
	var out: Array = []
	var st = w.sys_state.get("senses7")
	if st == null:
		return out
	var hb: Dictionary = st.heard.get(tkey(w, fid), {})
	var keys: Array = hb.keys()
	keys.sort()
	for k in keys:
		var h: Dictionary = hb[k]
		out.append({"pos": Vector2(h.pos), "err": float(h.err), "dir": float(h.dir), "dist": float(h.dist),
			"from": Vector2(h.from), "age": float(w.tick - int(h.t)) / TPS, "kind": String(h.kind)})
	return out


# ================================================================ observer / target profiles
## [code, sight, optics, thermal] of an observer (cached per kind:def; e.nvg / e.thermal checked per call).
static func _profile(w: SimWorld, o: Dictionary) -> Array:
	var key := String(o.kind) + ":" + String(o.def)
	var p = _prof.get(key)
	if p == null:
		var c := cfg()
		var unit: bool = o.kind == "unit"
		var d: Dictionary = Content.unit(String(o.def)) if unit else Content.building(String(o.def))
		var code := P_BLD
		if unit:
			if bool(d.get("is_air", false)):
				code = P_AIR
			elif _inf_def(String(o.def)):
				code = P_INF
			else:
				code = P_VEH
		var optics := bool(d.get("optics", false)) or bool(d.get("scope", false)) or (c.get("optics_defs", []) as Array).has(String(o.def))
		var thermal := bool(d.get("thermal", false)) or bool(d.get("nvg", false)) or (c.get("thermal_defs", []) as Array).has(String(o.def))
		if code == P_AIR and bool(c.get("air_thermal", true)):
			thermal = true
		p = [code, float(d.get("sight", 0)), optics, thermal]
		_prof[key] = p
	if int(o.get("owner", -1)) >= 0 and _is_machine(w, int(o.owner)):
		return [P_MACH, p[1], false, true]
	return p


static func _inf_def(def_id: String) -> bool:
	var v = _inf.get(def_id)
	if v == null:
		var d := Content.unit(def_id)
		v = not bool(d.get("is_air", false)) and (String(d.get("move_class", "")) == "foot" or String(d.get("armor", "")) == "infantry")
		_inf[def_id] = v
	return bool(v)


## Is target e an infantry soldier the senses apply to?
static func is_inf_target(e: Dictionary) -> bool:
	return e.kind == "unit" and e.has("morale") and _inf_def(String(e.def))


## Silhouette of target t before light / movement: posture x cover.
static func _silhouette(w: SimWorld, t: Dictionary) -> float:
	var s := 1.0
	var prone := false
	for k in cfg().get("prone_keys", []):
		if bool(t.get(String(k), false)):
			prone = true
			break
	if prone:
		s *= cf("prone_mult", 0.45)
	else:
		var g := int(t.get("gait", 0))
		if g == 1 or g == 2:
			s *= cf("crouch_mult", 0.7)
	var p: Vector2 = t.pos
	if w.terrain_at(Vector2i(floori(p.x), floori(p.y))) == 3:   # Terrain.FOREST
		s *= cf("forest_mult", 0.6)
	return s


## Active smoke clouds [[center Vector2, r]] (add_smoke clouds + Apc7 smoke panels).
static func _clouds(w: SimWorld, st: Dictionary) -> Array:
	var out := []
	for c in st.smoke:
		if int(c[3]) >= w.tick:
			out.append([Vector2(float(c[0]), float(c[1])), float(c[2])])
	var a7 = w.sys_state.get("apc7")
	if a7 != null:
		var r := cf("apc_smoke_radius", 4.0)
		for id in a7.get("ids", []):
			var a = w.entities.get(int(id))
			if a != null and a.has("a7") and int(a.a7.get("smoke_until", -1)) >= w.tick:
				out.append([Vector2(a.pos), r])
	return out


static func _smoke_blocks(clouds: Array, a: Vector2, b: Vector2) -> bool:
	var ab := b - a
	var l2 := ab.length_squared()
	for c in clouds:
		var cp: Vector2 = c[0]
		var r: float = c[1]
		var t := 0.0 if l2 <= 0.0 else clampf((cp - a).dot(ab) / l2, 0.0, 1.0)
		if (a + ab * t).distance_squared_to(cp) <= r * r:
			return true
	return false


static func _opos(o: Dictionary) -> Vector2:
	if o.kind == "building":
		var s := float(o.get("size", 1))
		return Vector2(o.cell) + Vector2(s, s) * 0.5
	return o.pos


## Does observer o spot target t now? sil = _silhouette(t), clouds = _clouds().
static func _sees(w: SimWorld, st: Dictionary, o: Dictionary, t: Dictionary, sil: float, moving: bool, clouds: Array) -> bool:
	var op := _opos(o)
	var tp: Vector2 = t.pos
	var d := op.distance_to(tp)
	if d <= cf("near", 1.5):
		return not bool(o.get("wunc", false))
	var pr := _profile(w, o)
	var code: int = pr[0]
	var R: float = pr[1]
	if code == P_MACH:
		return d <= R
	if bool(o.get("wunc", false)):
		return false
	var thermal: bool = pr[3] or bool(o.get("nvg", false)) or bool(o.get("thermal", false))
	var s := sil
	if moving:
		s = minf(1.0, s * cf("move_mult", 1.5))
	if not thermal:
		s *= float(st.light)
		if not clouds.is_empty() and _smoke_blocks(clouds, op, tp):
			return false
	if code == P_INF:
		var to := (tp - op) / d
		var cosa := Vector2.from_angle(float(o.get("facing", 0.0))).dot(to)
		if (pr[2] or bool(o.get("optics", false))) and cosa >= cos(deg_to_rad(cf("optics_deg", 25.0))) and d <= R * cf("optics_mult", 1.6) * s:
			return true
		if cosa >= cos(deg_to_rad(cf("cone_deg", 60.0))):
			return d <= R * s
		if cosa >= cos(deg_to_rad(cf("periph_deg", 100.0))):
			return moving and d <= R * s * cf("periph_mult", 0.6)
		return false
	var m := cf("vehicle_mult", 0.85)
	if code == P_AIR:
		m = cf("air_mult", 1.0)
	elif code == P_BLD:
		m = cf("building_mult", 0.9)
	return d <= R * s * m


## Exact one-pair check (tests, targeting change_requests): would observer o spot target t right now? Ignores the
## fog grid; a non-infantry target is seen inside the observer's sight.
static func can_see(w: SimWorld, o: Dictionary, t: Dictionary) -> bool:
	var st = w.sys_state.get("senses7")
	if st == null:
		st = {"smoke": [], "light": 1.0}
	if not is_inf_target(t):
		return _opos(o).distance_to(Vector2(t.pos)) <= float(_profile(w, o)[1])
	return _sees(w, st, o, t, _silhouette(w, t), bool(t.get("moving", false)), _clouds(w, st))


# ================================================================ per-tick driver (called from Fog.tick)
static func tick(w: SimWorld) -> void:
	if not enabled(w):
		if w.sys_state.has("senses7"):
			w.sys_state.erase("senses7")
		return
	var t0 := Time.get_ticks_usec()
	var st := state(w)
	_collect_noise(w, st)
	var se := maxi(2, int(cf("spot_every", 8)))
	var teams := _teams(w)
	var ran := false
	for k in teams.size():
		if posmod(w.tick - 2 - 2 * k, se) == 0:
			_pass(w, st, int(teams[k]))
			ran = true
	if ran:
		st.pass = int(st.pass) + 1
		var drop := []
		for sid in st.hq:
			if int(st.hq[sid][2]) <= w.tick - se:
				drop.append(sid)
		for sid in drop:
			st.hq.erase(sid)
		if not st.smoke.is_empty():
			var keep := []
			for c in st.smoke:
				if int(c[3]) >= w.tick:
					keep.append(c)
			st.smoke = keep
	prof.tick += Time.get_ticks_usec() - t0


## Blasts (noise_events) of this tick -> st.hq {-(tick*64+n): [pos, owner, tick, 2, ""]}. Gunfire needs no event
## scan: the team pass reads each enemy's last_fired_tick (set by Combat._fire) while it walks the enemies anyway.
static var _ne := {}


static func _collect_noise(w: SimWorld, st: Dictionary) -> void:
	if _ne.is_empty():
		for t in cfg().get("noise_events", []):
			_ne[String(t)] = true
		_ne["_"] = false
	var nb := 0
	for ev in w.events:
		if nb < 64 and _ne.has(ev.get("type", "")) and (typeof(ev.get("pos")) == TYPE_VECTOR2 or typeof(ev.get("pos")) == TYPE_VECTOR2I):
			nb += 1
			st.hq[-(w.tick * 64 + nb)] = [Vector2(ev.pos), int(ev.get("owner", -1)), w.tick, 2, ""]


static var _loud := {}


## 1 when the def's weapon is indirect (artillery / mortar: heard far), else 0.
static func _loud_def(def_id: String) -> int:
	var v = _loud.get(def_id)
	if v == null:
		var wid = Content.unit(def_id).get("weapon", "")
		v = 1 if typeof(wid) == TYPE_STRING and bool(Content.weapon(String(wid)).get("indirect", false)) else 0
		_loud[def_id] = v
	return int(v)


## One team pass: walk the enemies once (spot candidates + shooters heard from the fog), build the observer
## buckets only when something needs them, then hidden set, hearing, and (1 pass in squad_check_every) squads.
static func _pass(w: SimWorld, st: Dictionary, tk: int) -> void:
	var f = w.fog.get(tk)
	if f == null:
		return
	var members := _members(w, tk)
	var vis: PackedByteArray = f.visible
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var tiers_on := Tiers.enabled(w)
	var uown: Dictionary = SimIndex.units_by_owner(w)
	var se := maxi(2, int(cf("spot_every", 8)))
	var reveal := int(cf("reveal_ticks", 60))
	var all_machine := true
	for fm in members:
		if not _is_machine(w, int(fm)):
			all_machine = false
	var need := []
	var snd := []
	var owners: Array = uown.keys()
	owners.sort()
	for o in owners:
		if not w.is_enemy(tk, int(o)):
			continue
		for t: Dictionary in uown[o]:
			if tiers_on and int(t.get("tier", 0)) == Tiers.REDUCED:
				continue
			var lf := int(t.get("last_fired_tick", -9999))
			var p: Vector2 = t.pos
			var cx := floori(p.x)
			var cy := floori(p.y)
			var on_vis := cx >= 0 and cy >= 0 and cx < mw and cy < mh and vis[cy * mw + cx] == 1
			if w.tick - lf < reveal:
				if not on_vis and w.tick - lf < se:
					snd.append([int(t.id), p, int(o), lf, _loud_def(String(t.def)), String(t.def)])
				if w.tick - lf < reveal - se:
					continue   # still revealed by his own fire until the next pass
			if not on_vis or all_machine or not t.has("morale") or not _inf_def(String(t.def)):
				continue
			if w.entities.has(int(t.id)):
				need.append(t)
	for sid in st.hq:
		var h: Array = st.hq[sid]
		if int(h[2]) > w.tick - se:
			snd.append([int(sid), h[0], int(h[1]), int(h[2]), 2, ""])
	var B := maxf(2.0, cf("bucket", 8.0))
	var idx := {}
	var nobs := 0
	if not need.is_empty() or not snd.is_empty():
		for fm in members:
			for o: Dictionary in uown.get(fm, []):
				if tiers_on and int(o.get("tier", 0)) == Tiers.REDUCED:
					continue
				if not w.entities.has(int(o.id)):
					continue
				var p: Vector2 = o.pos
				var key := floori(p.x / B) + floori(p.y / B) * KST
				var a = idx.get(key)
				if a == null:
					idx[key] = [o]
				else:
					a.append(o)
				nobs += 1
		if not need.is_empty():
			var mbs := cf("min_building_sight", 4.0)
			for b: Dictionary in SimIndex.of(w, "building"):
				if not members.has(int(b.owner)) or not w.entities.has(int(b.id)) or float(_profile(w, b)[1]) < mbs:
					continue
				var bp := _opos(b)
				var key := floori(bp.x / B) + floori(bp.y / B) * KST
				var a = idx.get(key)
				if a == null:
					idx[key] = [b]
				else:
					a.append(b)
				nobs += 1
	var clouds := _clouds(w, st)
	if all_machine:
		st.spot.erase(tk)   # Machine sensors: the fog grid rule, no gate
	else:
		var spot := {}
		var maxc := int(cf("max_checks", 24)) if nobs <= int(cf("big_n", 1500)) else int(cf("max_checks_big", 6))
		for t: Dictionary in need:
			if _spotted_any(w, st, idx, B, t, maxc, clouds):
				spot[int(t.id)] = 1
		st.spot[tk] = spot
	var t1 := Time.get_ticks_usec()
	_hear(w, st, tk, members, idx, B, vis, mw, mh, snd)
	var t2 := Time.get_ticks_usec()
	var chk := maxi(1, int(cf("squad_check_every", 4)))
	if posmod(floori(float(w.tick) / float(se)), chk) == 0 or not st.cut.is_empty():
		var reps := {}
		for fm in members:
			var rp := {}
			reps[fm] = rp
			for o: Dictionary in uown.get(fm, []):
				var sq := int(o.get("squad", -1))
				if sq >= 0 and not rp.has(sq) and w.entities.has(int(o.id)):
					rp[sq] = o
		_squads(w, st, members, reps, clouds)
	prof.hear += t2 - t1
	prof.squads += Time.get_ticks_usec() - t2


## Ring search (nearest buckets first) for any observer that spots t; fails open after maxc checks.
static func _spotted_any(w: SimWorld, st: Dictionary, idx: Dictionary, B: float, t: Dictionary, maxc: int, clouds: Array) -> bool:
	var p: Vector2 = t.pos
	var sil := _silhouette(w, t)
	var moving := bool(t.get("moving", false))
	var bx := floori(p.x / B)
	var by := floori(p.y / B)
	var kmax := ceili(cf("max_range", 24.0) / B)
	var n := 0
	for k in range(0, kmax + 1):
		for yy in range(by - k, by + k + 1):
			var step := 1 if (k == 0 or yy == by - k or yy == by + k) else 2 * k
			var xx := bx - k
			while xx <= bx + k:
				var a = idx.get(xx + yy * KST)
				if a != null:
					for o in a:
						if _sees(w, st, o, t, sil, moving, clouds):
							return true
						n += 1
						if n >= maxc:
							return true
				xx += step
	return false


## A listener for a sound at p within r: the nearest observer of the first bucket ring holding any observer
## (ring order, then distance; unconscious ones skipped). Coarse on purpose: hearing only needs "someone, there".
static func _listener(idx: Dictionary, B: float, p: Vector2, r: float):
	var bx := floori(p.x / B)
	var by := floori(p.y / B)
	var kmax := ceili(r / B)
	var r2 := r * r
	for k in range(0, kmax + 1):
		var best = null
		var bd := INF
		var any := false
		for yy in range(by - k, by + k + 1):
			var step := 1 if (k == 0 or yy == by - k or yy == by + k) else 2 * k
			var xx := bx - k
			while xx <= bx + k:
				var a = idx.get(xx + yy * KST)
				if a != null:
					any = true
					var m := mini((a as Array).size(), 4)
					for i in m:
						var o: Dictionary = a[i]
						var d2 := _opos(o).distance_squared_to(p)
						if d2 <= r2 and d2 < bd and not bool(o.get("wunc", false)):
							bd = d2
							best = o
				xx += step
		if best != null or any:
			return best
	return null


const HK := 1099511627776   # 1 << 40: snapshot key offset for heard entries (never an entity / intel id)


## Heard contacts for team tk from this period's noise (shooters the team does not see).
static func _hear(w: SimWorld, st: Dictionary, tk: int, members: Array, idx: Dictionary, B: float, vis: PackedByteArray, mw: int, mh: int, snd: Array) -> void:
	if not st.heard.has(tk):
		st.heard[tk] = {}
	var hb: Dictionary = st.heard[tk]
	var keep_t := int(cf("heard_keep_s", 30.0) * TPS)
	var drop := []
	for k in hb:
		if w.tick - int(hb[k].t) > keep_t:
			drop.append(k)
	for k in drop:
		hb.erase(k)
		for fm in members:
			if st.hc.has(fm):
				st.hc[fm].erase(k)
	var se := maxi(2, int(cf("spot_every", 8)))
	var maxh := int(cf("max_heard_per_pass", 32))
	var n := 0
	var HB := maxf(1.0, cf("heard_cluster", 6.0))
	var done := {}
	for h: Array in snd:   # [key, pos, owner, tick, loud, def]: enemies in id order, then blasts
		var sid := int(h[0])
		var owner := int(h[2])
		var loud := int(h[4])
		if loud < 2 and (owner < 0 or not w.is_enemy(tk, owner)):
			continue
		if loud == 2 and members.has(owner):
			continue   # our own blast: no news
		var sp: Vector2 = h[1]
		var cl := (floori(sp.x / HB) + floori(sp.y / HB) * KST) * 2 + (1 if loud == 2 else 0)
		if done.has(cl):
			continue   # one heard contact per cluster cell and pass ("contact, north-east, ~300 m")
		done[cl] = true
		var cx := floori(sp.x)
		var cy := floori(sp.y)
		if loud < 2 and cx >= 0 and cy >= 0 and cx < mw and cy < mh and vis[cy * mw + cx] == 1:
			continue   # the shooter is on a cell we see: the muzzle rule shows him, nothing to guess
		var lis = _listener(idx, B, sp, cf("hear_range_loud", 80.0) if loud > 0 else cf("hear_range", 36.0))
		if lis == null:
			continue
		n += 1
		if n > maxh:
			break
		var lp := _opos(lis)
		var d := lp.distance_to(sp)
		var err := maxf(cf("heard_err_min", 1.5), d * cf("heard_err_frac", 0.2))
		var hh := hash([int(sid), w.tick, tk])
		var guess := sp + Vector2.from_angle(float(hh & 1023) / 1024.0 * TAU) * (float((hh >> 10) & 1023) / 1024.0 * err)
		guess = Vector2(snappedf(clampf(guess.x, 0.5, mw - 0.5), 0.01), snappedf(clampf(guess.y, 0.5, mh - 0.5), 0.01))
		var kind := "blast" if loud == 2 else "gunfire"
		var lsq := squad_key(lis) if lis.kind == "unit" else 0
		hb[cl] = {"pos": guess, "t": w.tick, "err": snappedf(err, 0.01), "dir": snappedf((sp - lp).angle(), 0.001),
			"dist": snappedf(d, 1.0), "from": lp, "sq": lsq, "fid": int(lis.owner), "kind": kind}
		var snap = _snap(st, int(lis.owner), lsq)
		if snap != null:
			snap.c[-HK + cl] = [guess, w.tick, "heard"]
		elif kind == "gunfire":
			for fm in members:
				if not st.hc.has(fm):
					st.hc[fm] = {}
				var cid := int(st.hc[fm].get(cl, 0))
				st.hc[fm][cl] = SimWorld.Intel.note_contact(w, int(fm), guess, String(h[5]), 0.0, "heard", cid)


static func _snap(st: Dictionary, fid: int, sq: int):
	var kf = st.kn.get(fid)
	return null if kf == null else kf.get(sq)


static func _is_cut(w: SimWorld, st: Dictionary, fid: int, sq: int, rep: Dictionary) -> bool:
	if st.cut.has(fid) and st.cut[fid].has(sq):
		return true
	var s := SimWorld.CommandNet.comms_state(w, int(rep.id))
	return s == "cut" or s == "jammed"


## Cut-off squads (checked 1 in squad_check_every passes): snapshot on cut, own eyes after, drop on reconnect.
static func _squads(w: SimWorld, st: Dictionary, members: Array, reps: Dictionary, clouds: Array) -> void:
	for fm in members:
		var rp: Dictionary = reps.get(fm, {})
		if st.kn.has(fm):
			for sq in (st.kn[fm] as Dictionary).keys():
				if not rp.has(sq):
					st.kn[fm].erase(sq)   # the whole squad is gone
		for sq in rp:
			var rep: Dictionary = rp[sq]
			if not _is_cut(w, st, int(fm), int(sq), rep):
				if st.kn.has(fm) and st.kn[fm].has(sq):
					st.kn[fm].erase(sq)
				continue
			if not st.kn.has(fm):
				st.kn[fm] = {}
			if not st.kn[fm].has(sq):
				var c := {}
				for x in SimWorld.Intel.contacts(w, int(fm), Vector2(rep.pos), cf("snap_radius", 60.0)):
					c[int(x.id)] = [Vector2(x.pos), w.tick - int(float(x.age) * TPS), String(x.src)]
				st.kn[fm][sq] = {"t0": w.tick, "c": c}
			_own_update(w, st, int(fm), int(sq), clouds)


## A cut-off squad adds what its own soldiers see now; old entries are forgotten after kn_forget_s.
static func _own_update(w: SimWorld, st: Dictionary, fid: int, sq: int, clouds: Array) -> void:
	var k: Dictionary = st.kn[fid][sq]
	var mem := []
	for o: Dictionary in SimIndex.units_by_owner(w).get(fid, []):
		if int(o.get("squad", -1)) == sq and w.entities.has(int(o.id)):
			mem.append(o)
	if mem.is_empty():
		st.kn[fid].erase(sq)
		return
	var c: Dictionary = k.c
	for x: Dictionary in SimWorld.Fog.visible_enemies_ro(w, fid):
		if x.kind != "unit" and x.kind != "building":
			continue
		var xp := _opos(x)
		var inf := is_inf_target(x)
		var sil := _silhouette(w, x) if inf else 1.0
		for o in mem:
			var ok := false
			if inf:
				ok = _sees(w, st, o, x, sil, bool(x.get("moving", false)), clouds)
			else:
				ok = _opos(o).distance_to(xp) <= float(_profile(w, o)[1])
			if ok:
				c[int(x.id)] = [xp, w.tick, "eye"]
				break
	var forget := int(cf("kn_forget_s", 120.0) * TPS)
	var drop := []
	for id in c:
		if w.tick - int(c[id][1]) > forget:
			drop.append(id)
	for id in drop:
		c.erase(id)


# ================================================================ per-squad knowledge API (fact senses.api)
## Is unit e's squad acting on its own (stale) picture because it is cut off the radio?
static func cut_off(w: SimWorld, e: Dictionary) -> bool:
	var st = w.sys_state.get("senses7")
	return st != null and _snap(st, int(e.owner), squad_key(e)) != null


## What unit e's squad knows: [{id, pos, age (s), conf, src (sight|report|recon|heard|eye), stale}], nearest
## know_radius of e for a squad on the net (its side's Intel picture), or the squad's own snapshot when cut off.
static func knowledge(w: SimWorld, e: Dictionary) -> Array:
	var st = w.sys_state.get("senses7")
	var k = null if st == null else _snap(st, int(e.owner), squad_key(e))
	if k == null:
		var lst := SimWorld.Intel.contacts(w, int(e.owner), Vector2(e.pos), cf("know_radius", 60.0))
		for c in lst:
			c["stale"] = false
		return lst
	var out := []
	var keys: Array = k.c.keys()
	keys.sort()
	var dk := maxf(1.0, cf("kn_decay_s", 90.0))
	for id in keys:
		var c: Array = k.c[id]
		var age := float(w.tick - int(c[1])) / TPS
		var conf := maxf(0.0, 1.0 - age / dk) * (0.7 if String(c[2]) == "heard" else 1.0)
		out.append({"id": int(id), "pos": Vector2(c[0]), "age": age, "conf": conf, "src": String(c[2]), "stale": true})
	return out


## Does e's squad hold a fresh (<= fresh_s) sighting of entity tid?
static func knows(w: SimWorld, e: Dictionary, tid: int) -> bool:
	var st = w.sys_state.get("senses7")
	var k = null if st == null else _snap(st, int(e.owner), squad_key(e))
	if k == null:
		var c := SimWorld.Intel.known(w, int(e.owner), tid)
		return not c.is_empty() and float(c.age) <= cf("fresh_s", 4.0)
	var c = k.c.get(tid)
	return c != null and w.tick - int(c[1]) <= int(cf("fresh_s", 4.0) * TPS)


## Last-known position of entity tid in e's squad picture (Vector2), or null.
static func last_known(w: SimWorld, e: Dictionary, tid: int):
	var st = w.sys_state.get("senses7")
	var k = null if st == null else _snap(st, int(e.owner), squad_key(e))
	if k == null:
		var c := SimWorld.Intel.known(w, int(e.owner), tid)
		return null if c.is_empty() else Vector2(c.pos)
	var c = k.c.get(tid)
	return null if c == null else Vector2(c[0])


## Where e should put suppressive fire: tid's last-known position when given and known, else the nearest contact
## of its squad picture no older than supp_max_age_s (heard contacts included). null = nothing to suppress.
static func suppress_point(w: SimWorld, e: Dictionary, tid: int = 0):
	if tid != 0:
		var lk = last_known(w, e, tid)
		if lk != null:
			return lk
	var best = null
	var bd := INF
	var maxa := cf("supp_max_age_s", 30.0)
	var ep: Vector2 = e.pos
	for c in knowledge(w, e):
		if float(c.age) > maxa or bool(c.get("decoy", false)):
			continue
		var d := ep.distance_squared_to(c.pos)
		if d < bd:
			bd = d
			best = Vector2(c.pos)
	return best
