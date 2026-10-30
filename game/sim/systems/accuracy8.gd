extends RefCounted
## G7 ACCURACY8 (G7_REFERENCE 13.9c-49, owner 2026-10-29: "make it realistic - shots could be missed with movement,
## lack of proper sighting, getting shot themselves, etc"). One multiplier on the weapon's accuracy, applied in
## Combat._fire next to the existing ones (same single w.rng hit roll: the draw count never changes).
## Data: rules.accuracy8 (content/g7/rules_g8_accuracy.json, PROVISIONAL numbers).
##
## Existing factors are reused where they are and NOT repeated here: suppression / pinned (Status.accuracy_mult),
## fatigue + rank / traits (Morale.acc_mult -> Fatigue / Veterancy), arm wounds (Wounds.acc_mult), dead sensors
## (Status), cohesion / loadouts / designation / auras / air defence (G6 hooks). New factors (mult()):
##   range      d vs effective range (weapon range x eff_frac[class]): point-blank bonus, falling past it
##   flight     the round's flight time tf (Ballistics8 rounds8 v0 / k): drop / wind error, and the lead error on a
##              target crossing the line (speed x tf x |sin| / target half size)
##   shooter    moving: infantry far worse (and the sight picture restarts), stabilised vehicles barely, Machine gyro
##   target     moving: tracking penalty
##   aim        sight picture: aim time on THIS target from the first shot at it; snap -> steady over settle_s;
##              optics / fire control settle faster and steadier
##   visibility senses7 light (night) unless thermal / NVG; smoke on the line (senses7 clouds); fog edge (past the
##              shooter's own sight); infantry target silhouette (prone / crouch / forest, senses7 numbers); weather
##   under fire a fresh hit (last_hit_tick) shakes the shooter; concussion daze (e.b8d, BLAST8)
##   posture    prone or braced (garrison / wall / cover / deployed) steadier (the larger, not both)
##   training   tier by def.training / def prefix
## Skipped (1.0): indirect, guided, air shooter or air target, skip_classes (melee, flame, ...).
##
## Saved state (entity fields, hashed): a8t (target id of the current sight picture), a8k (tick of the first shot at
## it), a8l (tick of the last shot at it). Written only by mult() (i.e. on a direct-fire shot), plain ints.
## Determinism: a pure function of content + world state (no rng). Cost: everything constant per def (shooter weapon,
## effective range, round v0 / k, aim profile, training) is cached in one profile Array; per-tick context (light,
## smoke clouds, weather) once per tick; tunables in typed statics; no allocation per shot when there is no smoke.
## Env ACCURACY8_OFF=1: multiplier 1.0 and no state written; ACCURACY8_SHADOW=1: computed, returns 1.0 (A/B only).

const TPS := 20.0
const Senses7 = preload("res://sim/systems/senses7.gd")
const Ballistics8 = preload("res://sim/systems/ballistics8.gd")

static var _rref = null
static var _c: Dictionary = {}
static var _on := false
static var _prof: Dictionary = {}   # def -> profile Array (see _profile_of)
static var _mach: Dictionary = {}   # owner -> bool (Machine faction), per world
static var _mach_w := 0
static var _off = null
static var _shadow = null

# per-tick context
static var _ctx_w := 0
static var _ctx_t := -1
static var _light := 1.0
static var _weather := 1.0
static var _clouds: Array = []

# flat config (read once per rules dict) + typed hot-path copies
static var K := {}
static var _mn := 0.02
static var _mx := 1.35
static var _close := 0.15
static var _far := 0.45
static var _farp := 1.5
static var _tfk := 0.15
static var _vdef := 600.0
static var _lead := 0.3
static var _xmin := 0.15
static var _spm := 1.8
static var _hsp := 0.3
static var _tmi := 0.9
static var _tmv := 0.92
static var _mvm := 0.75
static var _mvi := 0.5
static var _lose := 120
static var _night := 0.35
static var _thl := 0.9
static var _smk := 0.25
static var _smkt := 0.85
static var _efr := 0.8
static var _edge := 0.75
static var _silp := 0.5
static var _shk := 50
static var _shi := 0.7
static var _shv := 0.9
static var _daze := 0.55
static var _prn := 1.12
static var _brc := 1.1
static var _pk: Array = []
static var _sk: Array = []
static var _sp := 0.45
static var _sc := 0.7
static var _sf := 0.6
static var _fsn := 0.8
static var _fst := 1.05
static var _fse := 1.5
static var _osn := 0.7
static var _ost := 1.15
static var _ose := 1.2


static func cfg() -> Dictionary:
	var r: Dictionary = Content.rules()
	if is_same(r, _rref):
		return _c
	_rref = r
	_prof.clear()
	_c = r.get("accuracy8", {})
	_on = bool(_c.get("enabled", false))
	_flatten()
	return _c


static func enabled() -> bool:
	if _off == null:
		_off = OS.get_environment("ACCURACY8_OFF") == "1"
		_shadow = OS.get_environment("ACCURACY8_SHADOW") == "1"
	cfg()
	return _on and not bool(_off)


static func _d(sec: String) -> Dictionary:
	var v = _c.get(sec)
	return v if v is Dictionary else {}


## ACCURACY8B (13.9c-53) placement / daze-reaction knobs (flattened from rules) and the last shot's placement.
static var _pl_on := false
static var _pl: Array = []
static var _dz_cd := 1.4
static var _dz_rt := 12
static var _place = null   # Vector2(vital mult, limb mult) of the last mult() call on an infantry target, else null


## ACCURACY8B: the zone-weight multipliers of the shot mult() just computed (null = neutral), and clears them.
## Combat._fire hands them to Wounds (w.cache.a8p) around Damage.apply_hit of a HIT only.
static func take_place():
	var p = _place
	_place = null
	return p


## ACCURACY8B (13.9c-53): pure placement multipliers for quality q in [-1, 1] (tests / docs).
static func place_of(q: float) -> Vector2:
	cfg()
	return Vector2(exp(float(_pl[9]) * q), exp(-float(_pl[10]) * q))


## ACCURACY8B (13.9c-53): slower reactions while blast-dazed (e.b8d > tick). cd = the cooldown in ticks Combat._fire
## is about to set; returns it scaled (x cd_mult) plus retarget_s when t is not the target the soldier was aiming at.
## No draw. Called only for shooters with e.b8d.
static func daze_cd(w: SimWorld, e: Dictionary, t: Dictionary, cd: int) -> int:
	if not enabled() or int(e.get("b8d", -1)) <= w.tick:
		return cd
	var out := maxi(roundi(float(cd) * _dz_cd), 1)
	if int(e.get("a8t", -1)) != int(t.id):
		out += _dz_rt
	return out


static func _flatten() -> void:
	var rg := _d("range")
	var fl := _d("flight")
	var sm := _d("shooter_move")
	var tm := _d("target_move")
	var am := _d("aim")
	var vi := _d("visibility")
	var uf := _d("under_fire")
	var po := _d("posture")
	var hs: Dictionary = fl.get("half_size_m", {})
	K = {
		"skip": _c.get("skip_classes", []), "eff": rg.get("eff_frac", {}),
		"hs_inf": float(hs.get("inf", 0.45)), "hs_veh": float(hs.get("vehicle", 2.0)), "hs_heavy": float(hs.get("heavy", 2.6)),
		"mv_stab": float(sm.get("veh_stab", 0.85)), "mv_veh": float(sm.get("veh", 0.55)),
		"stab_armor": sm.get("stab_armor", ["heavy", "medium"]), "stab_defs": sm.get("stab_defs", []),
		"snap": float(am.get("snap", 0.65)), "steady": float(am.get("steady", 1.05)), "settle": float(am.get("settle_s", 2.0)),
		"weather": vi.get("weather", {}),
	}
	var pl := _d("placement")   # ACCURACY8B (13.9c-53): shot placement
	_pl_on = bool(pl.get("enabled", false)) and OS.get_environment("PLACE8_OFF") != "1"
	_pl = [float(pl.get("snap_q", -0.4)), float(pl.get("aimed_q", 0.6)), float(pl.get("move", 0.6)),
		float(pl.get("move_stab", 0.2)), float(pl.get("suppressed", 0.3)), float(pl.get("pinned", 0.6)),
		float(pl.get("shock", 0.3)), float(pl.get("daze", 0.6)), float(pl.get("braced", 0.2)),
		float(pl.get("vital_k", 0.7)), float(pl.get("limb_k", 0.7))]
	var dr := _d("daze_react")
	_dz_cd = float(dr.get("cd_mult", 1.4))
	_dz_rt = int(round(float(dr.get("retarget_s", 0.6)) * TPS))
	_mn = float(_c.get("min_mult", 0.02))
	_mx = float(_c.get("max_mult", 1.35))
	_close = float(rg.get("close_bonus", 0.15))
	_far = float(rg.get("far_drop", 0.45))
	_farp = float(rg.get("far_pow", 1.5))
	_tfk = float(fl.get("tf_k", 0.15))
	_vdef = maxf(float(fl.get("v_default", 600.0)), 1.0)
	_lead = float(fl.get("lead_err", 0.3))
	_xmin = float(fl.get("cross_min", 0.15))
	_spm = float(fl.get("speed_m_per_tile", 1.8))
	_hsp = float(hs.get("inf_prone", 0.3))
	_tmi = float(tm.get("inf", 0.9))
	_tmv = float(tm.get("vehicle", 0.92))
	_mvm = float(sm.get("machine", 0.75))
	_mvi = float(sm.get("inf", 0.5))
	_lose = int(float(am.get("lose_s", 6.0)) * TPS)
	_fsn = float(am.get("fc_snap", 0.8))
	_fst = float(am.get("fc_steady", 1.05))
	_fse = maxf(float(am.get("fc_settle_s", 1.5)), 0.01)
	_osn = float(am.get("optics_snap", 0.7))
	_ost = float(am.get("optics_steady", 1.15))
	_ose = maxf(float(am.get("optics_settle_s", 1.2)), 0.01)
	_night = float(vi.get("night", 0.35))
	_thl = float(vi.get("thermal_light", 0.9))
	_smk = float(vi.get("smoke", 0.25))
	_smkt = float(vi.get("smoke_thermal", 0.85))
	_efr = float(vi.get("edge_from", 0.8))
	_edge = float(vi.get("edge", 0.75))
	_silp = float(vi.get("sil_pow", 0.5))
	_shk = int(float(uf.get("shock_s", 2.5)) * TPS)
	_shi = float(uf.get("shock_inf", 0.7))
	_shv = float(uf.get("shock_veh", 0.9))
	_daze = float(uf.get("daze", 0.55))
	_prn = float(po.get("prone", 1.12))
	_brc = float(po.get("braced", 1.1))
	_pk = []
	for k in po.get("prone_keys", ["prone", "crawl"]):
		_pk.append(String(k))
	_sk = []
	for k in Senses7.cfg().get("prone_keys", []):
		_sk.append(String(k))
	_sp = Senses7.cf("prone_mult", 0.45)
	_sc = Senses7.cf("crouch_mult", 0.7)
	_sf = Senses7.cf("forest_mult", 0.6)


## Profile of a def (cached), as a target and as a shooter:
##  0 code (C_*), 1 stab, 2 optics, 3 thermal, 4 sight, 5 training mult, 6 speed, 7 half size m,
##  8 skip (weapon class in skip_classes / no weapon), 9 range, 10 effective range, 11 v0 (0 = no rounds8 entry),
##  12 k, 13 m per tile, 14 aim snap, 15 aim steady, 16 settle s,
##  17 move mult (0 = infantry; < 0 = unstabilised vehicle: both restart the aim)
const C_INF := 0
const C_VEH := 1
const C_AIR := 2
const C_BLD := 3


static func _profile_of(e: Dictionary) -> Array:
	var p = _prof.get(e.def)
	if p != null:
		return p
	var unit: bool = e.kind == "unit"
	var d: Dictionary = Content.unit(String(e.def)) if unit else Content.building(String(e.def))
	var code := C_BLD
	var armor := String(d.get("armor", ""))
	if unit:
		if bool(d.get("is_air", false)):
			code = C_AIR
		elif Senses7._inf_def(String(e.def)):   # foot or infantry armour (the senses7 rule)
			code = C_INF
		else:
			code = C_VEH
	var sc := Senses7.cfg()
	var dn := String(e.def)
	var optics := bool(d.get("optics", false)) or bool(d.get("scope", false)) or (sc.get("optics_defs", []) as Array).has(dn)
	var wid := String(d.get("weapon", ""))
	var wd: Dictionary = Content.weapon(wid) if wid != "" else {}
	var cls := String(wd.get("class", ""))
	if cls == "sniper":
		optics = true
	var thermal := bool(d.get("thermal", false)) or bool(d.get("nvg", false)) or (sc.get("thermal_defs", []) as Array).has(dn)
	var stab := bool(d.get("stab", (K.stab_armor as Array).has(armor) or (K.stab_defs as Array).has(dn)))
	var tier := String(d.get("training", ""))
	var tr := _d("training")
	if tier == "":
		var best := -1
		var bp: Dictionary = tr.get("by_prefix", {})
		for pre in bp:
			var ps := String(pre)
			if ps.length() > best and dn.begins_with(ps):
				best = ps.length()
				tier = String(bp[pre])
		if tier == "":
			tier = String(tr.get("default", "regular"))
	var tm := float((tr.get("tiers", {}) as Dictionary).get(tier, 1.0))
	var hs: float = K.hs_heavy if armor == "heavy" else (K.hs_inf if code == C_INF and armor != "medium" else K.hs_veh)
	var rng := maxf(float(wd.get("range", 0.0)), 0.1)
	var ef: Dictionary = K.eff
	var eff := rng * float(ef.get(cls, ef.get("default", 0.6)))
	var r = Ballistics8.round_of(wid) if wid != "" and Ballistics8.enabled() else null
	var v0 := 0.0
	var kk := 0.0
	if r != null:
		v0 = maxf(float(r.get("v0", _vdef)), 1.0)
		kk = 0.0 if bool(r.get("nofall", false)) else maxf(float(r.get("k", 0.0)), 0.0)
	var a := [K.snap, K.steady, K.settle]
	if code != C_INF:
		a = [_fsn, _fst, _fse]
	elif optics:
		a = [_osn, _ost, _ose]
	var mv := 1.0
	if code == C_INF:
		mv = 0.0
	elif code == C_VEH:
		mv = float(K.mv_stab) if stab else -float(K.mv_veh)
	p = [code, stab, optics, thermal, float(d.get("sight", 0)), tm, float(d.get("speed", 0)), hs,
		wid == "" or (K.skip as Array).has(cls), rng, eff, v0, kk, float(Ballistics8.cfg().get("m_per_tile_ballistic", 40.0)),
		float(a[0]), float(a[1]), maxf(float(a[2]), 0.01), mv]
	_prof[e.def] = p
	return p


static func _is_machine(w: SimWorld, fid: int) -> bool:
	var wid := w.get_instance_id()
	if wid != _mach_w:
		_mach_w = wid
		_mach.clear()
	var v = _mach.get(fid)
	if v == null:
		var f = w.factions.get(fid)
		v = f != null and String(f.get("faction_def", "")) == "machine"
		_mach[fid] = v
	return bool(v)


## Per-tick context: light, weather, smoke clouds (built only when some smoke exists).
static func _ctx(w: SimWorld) -> void:
	var wid := w.get_instance_id()
	if wid == _ctx_w and _ctx_t == w.tick:
		return
	_ctx_w = wid
	_ctx_t = w.tick
	_light = 1.0
	if not _clouds.is_empty():
		_clouds = []
	var st = w.sys_state.get("senses7")
	if st is Dictionary:
		_light = clampf(float(st.get("light", 1.0)), 0.0, 1.0)
		if not (st.get("smoke", []) as Array).is_empty() or w.sys_state.has("apc7"):
			_clouds = Senses7._clouds(w, st)
	elif w.sys_state.has("apc7"):
		_clouds = Senses7._clouds(w, {"smoke": []})
	var wt = w.cfg.get("weather")
	_weather = float((K.weather as Dictionary).get(String(wt), 1.0)) if wt != null else 1.0


## Flight time (s) over `dm` metres for a profile's round (v0 = 0: v_default, no velocity loss).
static func _tf(v0: float, kk: float, dm: float) -> float:
	if v0 <= 0.0:
		return dm / _vdef
	if kk <= 0.0:
		return dm / v0
	return (exp(kk * dm) - 1.0) / (kk * v0)


## Flight time (s) of weapon wid's round over `tiles` (rounds8; v_default without an entry). Tests / reports.
static func flight_s(wid: String, tiles: float) -> float:
	cfg()
	var r = Ballistics8.round_of(wid) if Ballistics8.enabled() else null
	var v0 := 0.0
	var kk := 0.0
	if r != null:
		v0 = maxf(float(r.get("v0", _vdef)), 1.0)
		kk = 0.0 if bool(r.get("nofall", false)) else maxf(float(r.get("k", 0.0)), 0.0)
	return _tf(v0, kk, tiles * float(Ballistics8.cfg().get("m_per_tile_ballistic", 40.0)))


## Senses7._silhouette with its numbers cached (prone keys / crouch gait / forest).
static func _silhouette(w: SimWorld, t: Dictionary) -> float:
	var sl := 1.0
	var pr := false
	for k in _sk:
		if t.get(k, false):
			pr = true
			break
	if pr:
		sl *= _sp
	else:
		var g := int(t.get("gait", 0))
		if g == 1 or g == 2:
			sl *= _sc
	var p: Vector2 = t.pos
	if w.terrain_at(Vector2i(floori(p.x), floori(p.y))) == 3:   # Terrain.FOREST
		sl *= _sf
	return sl


static func _prone_any(e: Dictionary) -> bool:
	for k in _pk:
		if e.get(k, false):
			return true
	return false


## Hit-chance multiplier for one direct-fire shot by e at t with stats s. Writes the sight-picture fields.
static func mult(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary) -> float:
	_place = null
	if not enabled():
		return 1.0
	if s.indirect or s.guided or s.is_air:
		return 1.0
	var sp := _profile_of(e)
	if sp[8]:
		return 1.0
	var tp := _profile_of(t)
	var tcode: int = tp[0]
	if tcode == C_AIR:
		return 1.0
	_ctx(w)
	var mach := _is_machine(w, int(e.get("owner", -1)))
	var code: int = sp[0]
	var m := 1.0
	var ep: Vector2 = e.pos
	var tpos: Vector2 = t.pos
	var d := ep.distance_to(tpos)
	# --- range vs effective range
	var rng: float = sp[9]
	var eff: float = sp[10]
	if d < eff:
		m *= 1.0 + _close * (1.0 - d / maxf(eff, 0.01))
	elif rng > eff:
		m *= 1.0 - _far * pow(clampf((d - eff) / (rng - eff), 0.0, 1.0), _farp)
	# --- flight time: drop / wind error and crossing lead error
	var tf := _tf(sp[11], sp[12], d * float(sp[13]))
	m /= 1.0 + _tfk * tf * tf
	if tcode != C_BLD and t.get("moving", false):
		m *= _tmi if tcode == C_INF else _tmv
		var spd: float = float(tp[6]) * float(t.get("mvm", 1.0)) * _spm
		if spd > 0.0 and d > 0.01:
			var cross := maxf(absf(sin(float(t.get("facing", 0.0)) - (tpos - ep).angle())), _xmin)
			var hs: float = tp[7]
			if tcode == C_INF and _prone_any(t):
				hs = _hsp
			var le := _lead * spd * tf * cross / maxf(hs, 0.05)
			m /= 1.0 + le * le
	# --- shooter moving
	var smov: bool = e.get("moving", false)
	var stab := true
	if smov and code != C_BLD:
		var mv: float = sp[17]
		if mach:
			m *= _mvm
		elif mv == 0.0:
			m *= _mvi
			stab = false
		elif mv < 0.0:
			m *= -mv
			stab = false
		else:
			m *= mv
	# --- sight picture (aim time on this target)
	var tid: int = t.id
	var now := w.tick
	if int(e.get("a8t", -1)) != tid or now - int(e.get("a8l", -1000000)) > _lose or not stab:
		e["a8t"] = tid
		e["a8k"] = now
	e["a8l"] = now
	var aim := float(now - int(e.a8k)) / TPS
	var a0: float = sp[14]
	var a1: float = sp[15]
	var st_s: float = sp[16]
	if mach:
		a0 = _fsn
		a1 = _fst
		st_s = _fse
	elif code == C_INF and not sp[2] and e.get("optics", false):
		a0 = _osn
		a1 = _ost
		st_s = _ose
	var af := clampf(aim / st_s, 0.0, 1.0)
	m *= lerpf(a0, a1, af)
	# --- visibility
	var thermal: bool = mach or sp[3] or e.get("nvg", false) or e.get("thermal", false)
	if _light < 1.0:
		m *= lerpf(_night, 1.0, _light) if not thermal else maxf(_thl, _light)
	if not _clouds.is_empty() and Senses7._smoke_blocks(_clouds, ep, tpos):
		m *= _smkt if thermal else _smk
	var sight: float = sp[4]
	if sight > 0.0:
		var ef := sight * _efr
		if d > ef:
			m *= lerpf(1.0, _edge, clampf((d - ef) / maxf(sight - ef, 0.01), 0.0, 1.0))
	if tcode == C_INF and not mach:
		var sil := _silhouette(w, t)
		if sil < 1.0:
			m *= pow(sil, _silp)
	m *= _weather
	if not mach:
		# --- under fire: fresh hit shock, concussion daze (suppression / fatigue / arm wounds: existing factors)
		if now - int(e.get("last_hit_tick", -1000000)) <= _shk:
			m *= _shi if code == C_INF else _shv
		if int(e.get("b8d", -1)) > now:
			m *= _daze
		# --- posture (infantry only; the larger of prone / braced)
		if code == C_INF and not smov:
			var pb := 1.0
			if _prone_any(e):
				pb = _prn
			if int(e.get("garrisoned_in", -1)) >= 0 or e.get("in_cover", false) or e.get("deployed", false):
				pb = maxf(pb, _brc)
			m *= pb
	# --- training (rank / traits: Veterancy)
	m *= float(sp[5])
	if _shadow:
		return 1.0
	# --- ACCURACY8B (13.9c-53) shot placement on a soldier target: aimed settled fire -> vitals, snap / moving /
	# suppressed / shocked / dazed fire -> limbs. Handed to Wounds via Combat (w.cache.a8p) on a hit; no draw.
	if _pl_on and tcode == C_INF:
		var q := lerpf(float(_pl[0]), float(_pl[1]), af)
		if smov and code != C_BLD:
			q -= float(_pl[3]) if stab else float(_pl[2])
		if not mach:
			if e.get("pinned", false):
				q -= float(_pl[5])
			elif float(e.get("supp", 0.0)) > 25.0:
				q -= float(_pl[4])
			if now - int(e.get("last_hit_tick", -1000000)) <= _shk:
				q -= float(_pl[6])
			if int(e.get("b8d", -1)) > now:
				q -= float(_pl[7])
			if code == C_INF and not smov and (_prone_any(e) or int(e.get("garrisoned_in", -1)) >= 0 or e.get("in_cover", false) or e.get("deployed", false)):
				q += float(_pl[8])
		q = clampf(q, -1.0, 1.0)
		_place = Vector2(exp(float(_pl[9]) * q), exp(-float(_pl[10]) * q))
	return clampf(m, _mn, _mx)
