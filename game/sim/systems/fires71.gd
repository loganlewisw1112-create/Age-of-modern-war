extends RefCounted
## G7.1 FIRES71 (docs/G71_SCOPE.md B4 fire support, B1 thermobaric + incendiary, G1 forward observers, G2 MLRS).
## Last Protocol only (roster 5A Q1): commands are refused outside LP and tick() returns after one cfg check there, so
## skirmish / the 2k + 10k benches never create state (hashes equal fact w2.bench_ref).
##
## fire_mission {issuer, kind, shape, a [x, y], b? [x, y], unit_ids? / building_ids? (explicit guns; default: every
##   free own indirect gun in range of the shape centre, ids ascending, up to rules.max_guns)}
##   kind: he | smoke | thermobaric | incendiary | precision | cluster | smart | illumination (empty slot, roster Q6:
##   refused until I5) | gunship (the CONDUCTOR orbit, Q19: hands off to conductor71.gd when it exists).
##   thermobaric / cluster / smart are rocket rounds (MLRS: fuel-air for packed lanes, G2); the rest any tube.
##   shape: point (sunflower around a) | line (a -> b, a barrage along a lane) | box (rect a-b, saturate) |
##   creeping (a line across a -> b that walks from a toward b at shapes.creeping.rate_tps; ends at b).
##   Each gun fires its allotment at its own rate (weapon cooldown; rocket guns in ripples), one round per step; the
##   gun is held from automatic fire meanwhile (HotState.set_cd) and drops out on a move order (player control first).
## Observed fire (B4 [PROPOSED]): obs_tier(w, fid, pos): 2 spotted (a forward observer team of fid within its fo71.range
##   that sees pos, a Callins designation, a counter-battery radar track), 1 seen (fog: any unit / drone / radar sight),
##   0 unobserved. Scatter radius = scatter.base[gun kind] x scatter.tier_mult[tier] x the kind's scatter_mult (precision
##   is tight only when observed). observed(w, fid, pos) = tier >= 1.
## FPF (manual only: AI-stamped commands are refused): fpf_fire {issuer, face (0..3, -1 = every face)}: every free gun
##   that reaches the face's strip (KillZone71.fpf_strip) fires its max rate into it for fpf.duration_s; ammo
##   fpf.ammo_cost per face; fpf.cooldown_s per face; own units in the strip get FpfDangerClose and take round splash
##   x danger_close_mult (every mission round does). Wall MGs / turrets on that face read fpf_aim() meanwhile.
## Counter-battery: an own radar building (def.radar) tracks an enemy indirect shooter within radar.radius x
##   cb.range_mult (track_shell(): called by the slow scan of enemy indirect shooters that fired, every cb.scan_ticks,
##   and by the wave-3 siege walker / Strikes); after cb.track_s up to cb.guns free guns in range answer with a spotted
##   HE point mission on the source (per-source cooldown cb.cooldown_s).
## Incendiary: belt_lay {issuer, a, b} (drag-to-lay, PROVISIONAL instant + cost; the engineer job comes later) and
##   belt_ignite {issuer, belt? (id), all?}: a lit belt burns for belts.burn_s; incendiary rounds leave burn spots.
##   Every burn tick (belts.burn_every_ticks) enemy ground units in a burn spot take burn damage and Parts71.ignite
##   (DAMAGE71: burning stops nanite self-repair and reanimation). Thermobaric: damage x (1 + per_extra per packed
##   extra enemy in the blast, capped).
## fo_call {issuer, unit_id (an FO team), what conductor | ucav, cell}: conductor -> conductor71.gd orbit (when it
##   exists); ucav -> the wave-3 UCAV (F1) API slot: recorded + UcavCalled event (test stub).
## API (fact fires71.api): fpf_aim(w, shooter) -> Variant, observed(w, fid, pos) -> bool, obs_tier, track_shell, on.
## State (saved, hashed; created by the first command / first counter-battery track only):
##   w.sys_state.fires71 = {ver, next, missions {"n": M}, rounds [R], busy {"gid": n}, fpf {"m": {until, cd, n}},
##   cb {tr {"src": {x, y, f, t, by}}, cd {"src": tick}}, belts {"n": B}, burn [[x, y, r, until, owner]], nb, ucav []}
## Runtime caches (never saved): w.cache.f71_fo {t, by_fid}, w.cache.f71_cb {t, ids}. Determinism: ascending ids,
##   w.rng only for the round scatter (2 draws per round, fixed order) and cluster bomblets; floats snapped 1/1024.

const KEY := "fires71"
const VER := 1
const Q := 1.0 / 1024.0
const COMMANDS := ["fire_mission", "fpf_fire", "belt_lay", "belt_ignite", "fo_call"]
const KINDS := ["he", "smoke", "illumination", "thermobaric", "incendiary", "precision", "gunship", "cluster", "smart"]
const ROCKET_KINDS := ["thermobaric", "cluster", "smart"]
const SHAPES := ["point", "line", "box", "creeping"]
const KZ_PATH := "res://sim/systems/killzone71.gd"
const CONDUCTOR_PATH := "res://sim/systems/conductor71.gd"
const PARTS_PATH := "res://sim/systems/parts71.gd"
const SENSES_PATH := "res://sim/systems/senses7.gd"
const Strikes = preload("res://sim/systems/strikes.gd")
const Callins = preload("res://sim/systems/callins.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const HotState = preload("res://sim/hot_state.gd")
const Damage = preload("res://sim/systems/damage.gd")
const KillZone71 = preload("res://sim/systems/killzone71.gd")
static var _parts = null
static var _parts_ok := -1
static var _senses = null


static func R() -> Dictionary:
	return Content.rules().get("g71_fires", {})


static func _rf(d: Dictionary, k: String, dflt: float) -> float:
	return float(d.get(k, dflt))


static func _t(secs: float) -> int:
	return maxi(roundi(secs * SimWorld.TICK_RATE), 1)


static func _sn(v: Vector2) -> Vector2:
	return Vector2(snappedf(v.x, Q), snappedf(v.y, Q))


static func on(w: SimWorld) -> bool:
	return w.sys_state.has(KEY)


static func lp_on(w: SimWorld) -> bool:
	return SimWorld.LastProtocol.active(w)


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"ver": VER, "next": 1, "missions": {}, "rounds": [], "busy": {}, "fpf": {},
			"cb": {"tr": {}, "cd": {}}, "belts": {}, "burn": [], "nb": 1, "ucav": []}
	return w.sys_state[KEY]


static func _pt(v):
	if v is Vector2:
		return v
	if v is Vector2i:
		return Vector2(v)
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return null


static func _def(e: Dictionary) -> Dictionary:
	return Content.building(String(e.def)) if e.kind == "building" else Content.unit(String(e.def))


# ================================================================ guns
## "" | "mortar" | "artillery" | "rockets" for e (an own indirect shooter).
static func gun_kind(e: Dictionary) -> String:
	if e.kind != "unit" and e.kind != "building":
		return ""
	var d := _def(e)
	var wid := String(d.get("weapon", ""))
	if wid == "" or bool(d.get("is_air", false)):
		return ""
	var wd := Content.weapon(wid)
	if not bool(wd.get("indirect", false)):
		return ""
	# ORCH 2026-11-22 (owner.fpf_reach side finding): a unit is a fire-support gun only with role artillery / mortar /
	# rocket_artillery (or an MLRS def): grenadiers' indirect launchers (a_g71_grenadier, b_grenadiers) never join a
	# fire mission or FPF. Buildings (howitzer / mortar pits) carry no role and stay guns.
	if e.kind == "unit" and not (["artillery", "mortar", "rocket_artillery"].has(String(d.get("role", ""))) \
			or bool(d.get("g71_rockets", false)) or String(d.get("strike", {}).get("kind", "")) == "mlrs"):
		return ""
	if String(d.get("strike", {}).get("kind", "")) == "mlrs" or String(d.get("role", "")) == "rocket_artillery" or bool(d.get("g71_rockets", false)):
		return "rockets"
	return "mortar" if float(wd.get("range", 0.0)) <= _rf(R(), "mortar_max_range", 14.0) else "artillery"


static func _gun_ok(w: SimWorld, e, fid: int) -> bool:
	if e == null or int(e.owner) != fid or not w.entities.has(int(e.id)):
		return false
	if e.kind == "building" and not bool(e.get("built", true)):
		return false
	if e.kind == "unit" and (e.has("garrisoned_in") or e.has("in_transport") or bool(e.get("air_landed", false))):
		return false
	return gun_kind(e) != ""


static func _reach(e: Dictionary, p: Vector2, slack: float = 0.0) -> bool:
	var wd := Content.weapon(String(_def(e).get("weapon", "")))
	var d := Vector2(e.pos).distance_to(p)
	return d <= float(wd.get("range", 0.0)) + slack and d >= float(wd.get("min_range", 0.0))


## Free guns of fid that reach p (or the explicit ids), ascending, capped. kind filter: rockets only for rocket rounds.
static func assign(w: SimWorld, fid: int, p: Vector2, explicit: Array, rockets_only: bool, cap: int) -> Array:
	var st = w.sys_state.get(KEY)
	var busy: Dictionary = st.busy if st != null else {}
	var cands := []
	if not explicit.is_empty():
		var ids := explicit.duplicate()
		ids.sort()
		for id in ids:
			cands.append(w.entities.get(int(id)))
	else:
		var byo: Dictionary = SimIndex.units_by_owner(w)
		for u in byo.get(fid, []):
			cands.append(u)
		for b in SimIndex.of(w, "building"):
			if int(b.owner) == fid:
				cands.append(b)
		cands.sort_custom(func(x, y): return int(x.id) < int(y.id))
	var out := []
	for e in cands:
		if out.size() >= cap:
			break
		if not _gun_ok(w, e, fid) or busy.has(str(int(e.id))):
			continue
		if rockets_only and gun_kind(e) != "rockets":
			continue
		if _reach(e, p, _rf(R(), "range_slack", 1.0)):
			out.append(e)
	return out


# ================================================================ observed fire
## 2 spotted, 1 seen, 0 unobserved (see header).
static func obs_tier(w: SimWorld, fid: int, pos: Vector2) -> int:
	if Callins.strike_acc_mult(w, fid, -1, pos) > 1.0:
		return 2
	var st = w.sys_state.get(KEY)
	if st != null:
		for k in st.cb.tr:
			var tr: Dictionary = st.cb.tr[k]
			if int(tr.get("own", -1)) == fid and Vector2(float(tr.x), float(tr.y)).distance_to(pos) <= 2.0:
				return 2
	var vis := w.is_visible(fid, pos)
	if vis:
		for fo in _fo_units(w, fid):
			var rg := float(Content.unit(String(fo.def)).get("fo71", {}).get("range", 20.0))
			if Vector2(fo.pos).distance_to(pos) <= rg:
				return 2
	return 1 if vis else 0


static func observed(w: SimWorld, fid: int, pos: Vector2) -> bool:
	return obs_tier(w, fid, pos) >= 1


## Forward observer teams of fid (def.fo71), cached for fo_cache_ticks.
static func _fo_units(w: SimWorld, fid: int) -> Array:
	var c = w.cache.get("f71_fo")
	if c == null or int(c.t) != w.tick:   # FIRES71-7: per tick (a bucket filled lazily differs after a load)
		c = {"t": w.tick, "by": {}}
		w.cache["f71_fo"] = c
	if not (c.by as Dictionary).has(fid):
		var out := []
		for u in SimIndex.units_by_owner(w).get(fid, []):
			if w.entities.has(int(u.id)) and Content.unit(String(u.def)).has("fo71"):
				out.append(u)
		out.sort_custom(func(x, y): return int(x.id) < int(y.id))
		c.by[fid] = out
	return c.by[fid]


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var t := String(cmd.get("type", ""))
	if not COMMANDS.has(t):
		return "unknown_command"
	if not lp_on(w):
		return "Fire support missions are a Last Protocol feature."
	var fid := int(cmd.get("issuer", -1))
	match t:
		"fire_mission":
			return _mission_reason(w, fid, cmd)
		"fpf_fire":
			if cmd.has("ai_cmd"):
				return "Final protective fire is manual only."
			var fs: Array = _fpf_faces(w, cmd)
			if fs.is_empty():
				return "Pick a wall face."
			var st = w.sys_state.get(KEY)
			var ready := []
			for m in fs:
				var f = st.fpf.get(str(m)) if st != null else null
				if f == null or w.tick >= int(f.cd):
					ready.append(m)
			if ready.is_empty():
				return "FPF is cooling down."
			return w.can_afford(fid, {"ammo": int(R().get("fpf", {}).get("ammo_cost", 400)) * ready.size()}) if bool(R().get("use_ledger", true)) else ""
		"belt_lay":
			var a = _pt(cmd.get("a"))
			var b = _pt(cmd.get("b"))
			if a == null or b == null or not w.in_bounds(w.cell_of(a)) or not w.in_bounds(w.cell_of(b)):
				return "Drag the belt on the map."
			var BR: Dictionary = R().get("belts", {})
			var ln := (a as Vector2).distance_to(b)
			if ln < 1.0 or ln > _rf(BR, "max_len", 20.0):
				return "A belt is 1-%d tiles long." % int(_rf(BR, "max_len", 20.0))
			var st = w.sys_state.get(KEY)
			var n := 0
			if st != null:
				for k in st.belts:
					if int(st.belts[k].owner) == fid and String(st.belts[k].s) != "spent":
						n += 1
			if n >= int(BR.get("max_belts", 12)):
				return "Too many incendiary belts."
			return w.can_afford(fid, BR.get("cost", {}))
		"belt_ignite":
			var st = w.sys_state.get(KEY)
			if st == null or _belts_to_light(w, st, fid, cmd).is_empty():
				return "No laid incendiary belt to ignite."
		"fo_call":
			var e = w.entities.get(int(cmd.get("unit_id", -1)))
			if e == null or int(e.owner) != fid or not Content.unit(String(e.def)).has("fo71"):
				return "Select a forward observer team."
			var c = _pt(cmd.get("cell"))
			if c == null or not w.in_bounds(w.cell_of(c)):
				return "Pick a target on the map."
			var what := String(cmd.get("what", ""))
			if what == "conductor":
				return _conductor_reason(w, fid, c)
			if what != "ucav":
				return "Call the Conductor or a UCAV."
			if not w.is_visible(fid, c):
				return "The observer cannot see that point."
	return ""


static func _mission_reason(w: SimWorld, fid: int, cmd: Dictionary) -> String:
	var kind := String(cmd.get("kind", "he"))
	if not KINDS.has(kind):
		return "Pick a fire support type."
	if kind == "illumination":
		return "Illumination rounds are not issued yet."
	var a = _pt(cmd.get("a"))
	if a == null or not w.in_bounds(w.cell_of(a)):
		return "Pick a target on the map."
	if kind == "gunship":
		return _conductor_reason(w, fid, a)
	var shape := String(cmd.get("shape", "point"))
	if not SHAPES.has(shape):
		return "Pick a strike shape."
	var S: Dictionary = R().get("shapes", {}).get(shape, {})
	if shape != "point":
		var b = _pt(cmd.get("b"))
		if b == null or not w.in_bounds(w.cell_of(b)):
			return "Drag the strike shape on the map."
		var d := (a as Vector2).distance_to(b)
		if d < 1.0:
			return "Drag a longer strike."
		if shape == "box" and (absf((b as Vector2).x - (a as Vector2).x) > _rf(S, "max_side", 16.0) or absf((b as Vector2).y - (a as Vector2).y) > _rf(S, "max_side", 16.0)):
			return "That box is too big."
		if shape != "box" and d > _rf(S, "max_len", 24.0):
			return "That strike is too long."
	var guns := assign(w, fid, _centre(cmd, a), _explicit(cmd), ROCKET_KINDS.has(kind), _cap(kind))
	if guns.is_empty():
		return "No rocket artillery in range." if ROCKET_KINDS.has(kind) else "No artillery in range."
	if bool(R().get("use_ledger", true)):
		return w.can_afford(fid, {"ammo": _cost(kind, guns, shape, cmd)})
	return ""


static func _conductor_reason(w: SimWorld, fid: int, p: Vector2) -> String:
	if not ResourceLoader.exists(CONDUCTOR_PATH):
		return "The Conductor gunship is not available."
	var C = load(CONDUCTOR_PATH)
	if C == null or not C.has_method("orbit_reason"):
		return "The Conductor gunship is not available."
	return String(C.call("orbit_reason", w, fid, p))


static func _explicit(cmd: Dictionary) -> Array:
	var ids := []
	for k in ["unit_ids", "building_ids"]:
		for raw in cmd.get(k, []):
			if not ids.has(int(raw)):
				ids.append(int(raw))
	return ids


static func _cap(kind: String) -> int:
	return int(R().get("kinds", {}).get(kind, {}).get("max_guns", R().get("max_guns", 12)))


static func _centre(cmd: Dictionary, a: Vector2) -> Vector2:
	var b = _pt(cmd.get("b"))
	if b == null or String(cmd.get("shape", "point")) == "point":
		return a
	return (a + (b as Vector2)) * 0.5


## Rounds one gun of kind gk fires for this mission.
static func _rounds(kind: String, gk: String, shape: String, cmd: Dictionary) -> int:
	var K: Dictionary = R().get("kinds", {}).get(kind, {})
	if K.has("rounds"):
		return int(K.rounds) * (int(R().get("rocket_mult", 3)) if gk == "rockets" else 1)
	var n := int(R().get("shapes", {}).get(shape, {}).get("rounds", 4))
	if shape == "creeping":
		var a: Vector2 = _pt(cmd.a)
		var b: Vector2 = _pt(cmd.b)
		var S: Dictionary = R().get("shapes", {}).creeping
		n = maxi(n, ceili(a.distance_to(b) / maxf(_rf(S, "rate_tps", 0.5), 0.05) / maxf(_rf(S, "step_s", 4.0), 0.5)))
	return n * (int(R().get("rocket_mult", 3)) if gk == "rockets" else 1)


static func _cost(kind: String, guns: Array, shape: String, cmd: Dictionary) -> int:
	var per := int(R().get("kinds", {}).get(kind, {}).get("ammo", 2))
	var n := 0
	for g in guns:
		n += _rounds(kind, gun_kind(g), shape, cmd)
	return n * per


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if validate_command(w, cmd) != "":
		return
	var fid := int(cmd.issuer)
	match String(cmd.type):
		"fire_mission":
			if String(cmd.get("kind", "he")) == "gunship":
				load(CONDUCTOR_PATH).call("orbit_at", w, fid, _pt(cmd.a))
				return
			var kind := String(cmd.get("kind", "he"))
			var a: Vector2 = _pt(cmd.a)
			var guns := assign(w, fid, _centre(cmd, a), _explicit(cmd), ROCKET_KINDS.has(kind), _cap(kind))
			if bool(R().get("use_ledger", true)):
				w.spend(fid, {"ammo": _cost(kind, guns, String(cmd.get("shape", "point")), cmd)}, "fire_mission")
			var b = _pt(cmd.get("b"))
			start_mission(w, fid, kind, String(cmd.get("shape", "point")), a, b if b != null else a, guns, -1, cmd)
		"fpf_fire":
			_fpf_fire(w, fid, cmd)
		"belt_lay":
			var st := _st(w)
			var BR: Dictionary = R().get("belts", {})
			w.spend(fid, BR.get("cost", {}), "belt_lay")
			var n := int(st.nb)
			st.nb = n + 1
			var a: Vector2 = _sn(_pt(cmd.a))
			var b: Vector2 = _sn(_pt(cmd.b))
			st.belts[str(n)] = {"n": n, "owner": fid, "ax": a.x, "ay": a.y, "bx": b.x, "by": b.y, "s": "laid", "until": -1}
			w.emit("BeltLaid", {"n": n, "owner": fid, "a": [a.x, a.y], "b": [b.x, b.y]})
		"belt_ignite":
			var st := _st(w)
			var until := w.tick + _t(_rf(R().get("belts", {}), "burn_s", 30.0))
			for k in _belts_to_light(w, st, fid, cmd):
				var B: Dictionary = st.belts[k]
				B.s = "burning"
				B.until = until
				w.emit("BeltIgnited", {"n": int(B.n), "owner": fid, "until": until})
		"fo_call":
			var c: Vector2 = _sn(_pt(cmd.cell))
			if String(cmd.what) == "conductor":
				load(CONDUCTOR_PATH).call("orbit_at", w, fid, c)
			else:
				var st := _st(w)
				(st.ucav as Array).append({"by": int(cmd.unit_id), "owner": fid, "x": c.x, "y": c.y, "t": w.tick})
				w.emit("UcavCalled", {"by": int(cmd.unit_id), "owner": fid, "pos": c, "stub": true})


static func _belts_to_light(w: SimWorld, st: Dictionary, fid: int, cmd: Dictionary) -> Array:
	var out := []
	var ks: Array = (st.belts as Dictionary).keys()
	ks.sort_custom(func(x, y): return int(x) < int(y))
	for k in ks:
		var B: Dictionary = st.belts[k]
		if int(B.owner) != fid or String(B.s) != "laid":
			continue
		if bool(cmd.get("all", false)) or int(cmd.get("belt", -1)) == int(B.n):
			out.append(k)
	return out


## Starts a mission (also the FPF / counter-battery entry). guns: entity dicts (ascending). face >= 0 = FPF.
static func start_mission(w: SimWorld, fid: int, kind: String, shape: String, a: Vector2, b: Vector2, guns: Array, face: int, cmd: Dictionary = {}) -> int:
	var st := _st(w)
	var n := int(st.next)
	st.next = n + 1
	var gl := []
	var total := 0
	var until := -1
	if face >= 0:
		until = w.tick + _t(_rf(R().get("fpf", {}), "duration_s", 45.0))
	for g in guns:
		var gk := gun_kind(g)
		var left := _rounds(kind, gk, shape, cmd) if face < 0 else 1 << 20
		gl.append([int(g.id), left, w.tick + int(gl.size()) % 4])
		st.busy[str(int(g.id))] = n
		total += left if face < 0 else 0
	var M := {"n": n, "kind": kind, "shape": shape, "owner": fid, "ax": snappedf(a.x, Q), "ay": snappedf(a.y, Q),
		"bx": snappedf(b.x, Q), "by": snappedf(b.y, Q), "t0": w.tick, "k": 0, "total": total, "guns": gl, "face": face,
		"until": until, "obs": obs_tier(w, fid, (a + b) * 0.5), "ot": w.tick}
	st.missions[str(n)] = M
	var dc := _own_in_area(w, fid, M)
	w.emit("FireMission", {"n": n, "owner": fid, "kind": kind, "shape": shape, "a": [M.ax, M.ay], "b": [M.bx, M.by],
		"guns": gl.size(), "rounds": total, "obs": int(M.obs), "face": face, "danger_close": dc})
	if not dc.is_empty():
		w.emit("FireDangerClose", {"n": n, "owner": fid, "ids": dc, "face": face})
	return n


## Own ground units inside the mission area (point radius / line / box / strip) right now, ascending.
static func _own_in_area(w: SimWorld, fid: int, M: Dictionary) -> Array:
	var out := []
	var a := Vector2(float(M.ax), float(M.ay))
	var b := Vector2(float(M.bx), float(M.by))
	var pad := _rf(R(), "danger_close_pad", 2.0)
	for u in SimIndex.units_by_owner(w).get(fid, []):
		if not w.entities.has(int(u.id)) or bool(Content.unit(String(u.def)).get("is_air", false)):
			continue
		var p: Vector2 = u.pos
		var inside := false
		if int(M.face) >= 0:
			inside = KillZone71.in_strip(w, int(M.face), p)
		elif String(M.shape) == "point":
			inside = p.distance_to(a) <= _rf(R().get("shapes", {}).get("point", {}), "radius", 1.5) + pad
		elif String(M.shape) == "box":
			inside = Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs()).grow(pad).has_point(p)
		else:
			inside = Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= pad + (_rf(R().get("shapes", {}).get("creeping", {}), "width", 8.0) * 0.5 if String(M.shape) == "creeping" else 0.0)
		if inside:
			out.append(int(u.id))
	out.sort()
	return out


# ================================================================ FPF
static func _fpf_faces(w: SimWorld, cmd: Dictionary) -> Array:
	var fs: Array = KillZone71.faces(w)
	var m := int(cmd.get("face", -2))
	if m == -1:
		return fs
	return [m] if fs.has(m) else []


static func _fpf_fire(w: SimWorld, fid: int, cmd: Dictionary) -> void:
	var st := _st(w)
	var F: Dictionary = R().get("fpf", {})
	for m in _fpf_faces(w, cmd):
		var f = st.fpf.get(str(m))
		if f != null and w.tick < int(f.cd):
			continue
		if bool(R().get("use_ledger", true)) and not w.spend(fid, {"ammo": int(F.get("ammo_cost", 400))}, "fpf_fire"):
			continue
		var s := KillZone71.fpf_strip(w, m)
		var a := Vector2(float(s.a[0]), float(s.a[1]))
		var b := Vector2(float(s.b[0]), float(s.b[1]))
		var guns := []
		for g in assign(w, fid, (a + b) * 0.5, [], false, int(F.get("max_guns", 16))):
			guns.append(g)
		var n := start_mission(w, fid, "he", "fpf", a, b, guns, m)
		var until: int = int(st.missions[str(n)].until)
		st.fpf[str(m)] = {"until": until, "cd": until + _t(_rf(F, "cooldown_s", 180.0)), "n": n}
		w.emit("FpfFired", {"owner": fid, "face": m, "n": n, "guns": guns.size(), "until": until, "cd": int(st.fpf[str(m)].cd)})


## Aim point in the strip of the shooter's face while that face's FPF runs, else null (BASTION71 / ARMY71 read it).
static func fpf_aim(w: SimWorld, shooter: Dictionary) -> Variant:
	var st = w.sys_state.get(KEY)
	if st == null or (st.fpf as Dictionary).is_empty():
		return null
	var pos: Vector2 = shooter.pos
	var m := KillZone71.face_of(w, pos)
	if m < 0:
		return null
	var f = st.fpf.get(str(m))
	if f == null or w.tick >= int(f.until):
		return null
	if absf(KillZone71.out_dist(w, m, pos)) > _rf(R().get("fpf", {}), "wall_band", 4.0):
		return null
	var pts := KillZone71.strip_points(w, m, 12)
	return pts[(w.tick / 10 + int(shooter.get("id", 0))) % pts.size()] if not pts.is_empty() else null


# ================================================================ counter-battery
## Records an enemy indirect shot from `from` (shooter src of side sfid). Own radars of every side hostile to sfid
## within range track it. The wave-3 siege walker / Strikes call this; the slow scan calls it for today's shooters.
static func track_shell(w: SimWorld, sfid: int, src: int, from: Vector2) -> void:
	if not lp_on(w):
		return
	var C: Dictionary = R().get("cb", {})
	var radars := _radars(w)
	for rb in radars:
		var own := int(rb.owner)
		if not w.is_enemy(own, sfid):
			continue
		var rr := float(Content.building(String(rb.def)).get("radar", {}).get("radius", 28.0)) * _rf(C, "range_mult", 1.5)
		if Vector2(rb.pos).distance_to(from) > rr:
			continue
		var st := _st(w)
		var key := str(src)
		if (st.cb.tr as Dictionary).has(key) or w.tick < int(st.cb.cd.get(key, -1)):
			return
		if (st.cb.tr as Dictionary).size() >= int(C.get("max_tracks", 8)):
			return
		var p := _sn(from)
		st.cb.tr[key] = {"x": p.x, "y": p.y, "f": sfid, "own": own, "t": w.tick, "by": int(rb.id)}
		w.emit("CounterBatteryTrack", {"src": src, "pos": p, "radar": int(rb.id), "owner": own})
		return


static func _radars(w: SimWorld) -> Array:
	var out := []
	for b in SimIndex.of(w, "building"):
		if w.entities.has(int(b.id)) and bool(b.get("built", true)) and Content.building(String(b.def)).has("radar"):
			out.append(b)
	out.sort_custom(func(x, y): return int(x.id) < int(y.id))
	return out


static var _cbg := {}   # FIRES71-9: "kind:def" -> can be a counter-battery source (content only); reset per world
static var _cbg_w := 0


static func _cb_gun(w: SimWorld, e: Dictionary) -> bool:
	if _cbg_w != w.get_instance_id():
		_cbg = {}
		_cbg_w = w.get_instance_id()
	var k := String(e.kind) + ":" + String(e.get("def", ""))
	var v = _cbg.get(k)
	if v == null:
		v = gun_kind(e) != "" or (e.kind == "building" and Strikes.kind_of(e) == "mass_driver")
		_cbg[k] = v
	return bool(v)


## Slow scan: enemy indirect shooters (cached list, refreshed every cb.list_ticks) that fired within cb.scan_ticks.
static func _cb_scan(w: SimWorld) -> void:
	var C: Dictionary = R().get("cb", {})
	var every := maxi(int(C.get("scan_ticks", 20)), 1)
	if w.tick % every != 3:
		return
	var lp = SimWorld.LastProtocol.st(w)
	if lp == null:
		return
	var hf := int(lp.get("fid", -1))
	# FIRES71-7: the shooter list is rebuilt at every scan (every scan_ticks, LP only). The old w.cache list (refreshed
	# every list_ticks) was not saved, so a loaded world rebuilt it at another tick and tracked other shooters
	# (test_lpreserve7 save/load mid-release, red once guns reached the enemy: option A).
	# FIRES71-9: the list stays rebuilt at every scan (save-safe); only the per-def gun test is memoised (_cb_gun: a pure
	# function of the loaded content, no world state, so a loaded world gets the same list). LP-peak A/B: cache_ab17_g9.log.
	var c = null
	if true:
		var ids := []
		for e in SimIndex.of(w, "unit"):
			if w.is_enemy(hf, int(e.owner)) and _cb_gun(w, e):
				ids.append(int(e.id))
		for b in SimIndex.of(w, "building"):
			if w.is_enemy(hf, int(b.owner)) and _cb_gun(w, b):
				ids.append(int(b.id))
		ids.sort()
		c = {"t": w.tick, "ids": ids}
	for id in c.ids:
		var e = w.entities.get(int(id))
		if e == null:
			continue
		var fired := w.tick - int(e.get("last_fired_tick", -100000)) <= every
		if not fired and e.kind == "building" and e.has("strike_ready"):
			var cdt := _t(float(Content.weapon(String(_def(e).get("weapon", ""))).get("cooldown", 14.0)))
			fired = w.tick - (int(e.strike_ready) - cdt) <= every
		if fired:
			track_shell(w, int(e.owner), int(id), Vector2(e.pos))


static func _cb_answer(w: SimWorld, st: Dictionary) -> void:
	var C: Dictionary = R().get("cb", {})
	var delay := _t(_rf(C, "track_s", 3.0))
	var ks: Array = (st.cb.tr as Dictionary).keys()
	ks.sort_custom(func(x, y): return int(x) < int(y))
	for k in ks:
		var tr: Dictionary = st.cb.tr[k]
		if w.tick - int(tr.t) < delay:
			continue
		st.cb.tr.erase(k)
		st.cb.cd[k] = w.tick + _t(_rf(C, "cooldown_s", 20.0))
		var p := Vector2(float(tr.x), float(tr.y))
		var guns := assign(w, int(tr.own), p, [], false, int(C.get("guns", 2)))
		if guns.is_empty():
			w.emit("CounterBatteryNoGuns", {"src": int(k), "pos": p, "owner": int(tr.own)})
			continue
		var n := start_mission(w, int(tr.own), "he", "point", p, p, guns, -1, {"cb": true})
		st.missions[str(n)].obs = 2
		st.missions[str(n)].cb = int(k)
		w.emit("CounterBatteryAnswer", {"src": int(k), "pos": p, "owner": int(tr.own), "n": n, "guns": guns.size()})
	var cks: Array = (st.cb.cd as Dictionary).keys()
	cks.sort()
	for k in cks:
		if w.tick >= int(st.cb.cd[k]):
			st.cb.cd.erase(k)


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	if not lp_on(w):
		return
	_cb_scan(w)
	var st = w.sys_state.get(KEY)
	if st == null:
		return
	if not (st.cb.tr as Dictionary).is_empty() or not (st.cb.cd as Dictionary).is_empty():
		_cb_answer(w, st)
	if not (st.missions as Dictionary).is_empty():
		_missions_step(w, st)
	if not (st.rounds as Array).is_empty():
		_rounds_step(w, st)
	if not (st.burn as Array).is_empty() or not (st.belts as Dictionary).is_empty():
		_burn_step(w, st)
	if not (st.fpf as Dictionary).is_empty() and w.tick % 20 == 5:
		var fk: Array = (st.fpf as Dictionary).keys()
		fk.sort()
		for k in fk:
			var f: Dictionary = st.fpf[k]
			if w.tick >= int(f.cd):
				st.fpf.erase(k)
			elif w.tick >= int(f.until) and not bool(f.get("ended", false)):
				f.ended = true
				w.emit("FpfEnded", {"face": int(k), "cd": int(f.cd)})


static func _missions_step(w: SimWorld, st: Dictionary) -> void:
	var ks: Array = (st.missions as Dictionary).keys()
	ks.sort_custom(func(x, y): return int(x) < int(y))
	for k in ks:
		var M: Dictionary = st.missions[k]
		var fid := int(M.owner)
		if w.tick - int(M.ot) >= 20 and not M.has("cb"):
			M.obs = obs_tier(w, fid, (Vector2(float(M.ax), float(M.ay)) + Vector2(float(M.bx), float(M.by))) * 0.5)
			M.ot = w.tick
		var fpf_over: bool = int(M.face) >= 0 and w.tick >= int(M.until)
		var live := 0
		for g in M.guns:
			if int(g[1]) <= 0:
				continue
			var e = w.entities.get(int(g[0]))
			if fpf_over or not _gun_ok(w, e, fid) or bool(e.get("moving", false)):
				g[1] = 0
				st.busy.erase(str(int(g[0])))
				continue
			live += 1
			if w.tick < int(g[2]):
				continue
			_fire_step(w, st, M, e, g)
		if live == 0:
			for g in M.guns:
				st.busy.erase(str(int(g[0])))
			st.missions.erase(k)
			w.emit("FireMissionDone", {"n": int(M.n), "owner": fid, "kind": String(M.kind), "fired": int(M.k), "face": int(M.face)})


## One fire step of gun e (g = [id, left, next]): a round (tube) or a ripple (rocket gun).
static func _fire_step(w: SimWorld, st: Dictionary, M: Dictionary, e: Dictionary, g: Array) -> void:
	var gk := gun_kind(e)
	var d := _def(e)
	var wd := Content.weapon(String(d.weapon))
	var kind := String(M.kind)
	var K: Dictionary = R().get("kinds", {}).get(kind, {})
	var n := 1
	var gap := _t(float(wd.get("cooldown", 4.0)) * _rf(R(), "rate_mult", 1.0))
	if gk == "rockets":
		n = mini(int(R().get("ripple", 4)), int(g[1]))
		gap = _t(_rf(R(), "ripple_cd_s", 2.0))
	if int(M.face) >= 0:
		gap = maxi(roundi(float(gap) * _rf(R().get("fpf", {}), "rate_mult", 1.0)), 1)
	var SC: Dictionary = R().get("scatter", {})
	var tier := int(M.obs)
	var rad := _rf(SC.get("base", {}), gk, 1.5) * float((SC.get("tier_mult", [1.8, 1.0, 0.4]) as Array)[clampi(tier, 0, 2)])
	rad *= _rf(K, "scatter_mult" if tier >= 1 else "scatter_mult_unobs", _rf(K, "scatter_mult", 1.0))
	var flight := _t(_rf(R().get("flight_s", {}), gk, 4.0) * Callins.strike_delay_mult(w, int(M.owner), -1, Vector2(float(M.ax), float(M.ay))))
	for i in n:
		var aim := _aim(w, M, int(M.k))
		M.k = int(M.k) + 1
		var ang := w.rng.randf() * TAU
		var r := sqrt(w.rng.randf()) * rad
		var at := _sn(aim + Vector2(cos(ang), sin(ang)) * r)
		var dmg := float(wd.get("damage", 40.0)) * _rf(K, "dmg_mult", 1.0)
		var spl := float(wd.get("splash", 1.4)) * _rf(K, "splash_mult", 1.0)
		var Rd := {"n": int(M.n), "kind": kind, "owner": int(M.owner), "src": int(e.id), "x": at.x, "y": at.y,
			"t": flight + i * 2, "tt": flight + i * 2, "fx": snappedf(float(e.pos.x), Q), "fy": snappedf(float(e.pos.y), Q),
			"dmg": snappedf(dmg, Q), "spl": snappedf(spl, Q), "wpn": String(d.weapon), "gk": gk}
		(st.rounds as Array).append(Rd)
		w.emit("Fires71Shot", {"n": int(M.n), "src": int(e.id), "from": Vector2(float(Rd.fx), float(Rd.fy)), "at": at, "eta": int(Rd.t), "kind": kind, "gk": gk})
	g[1] = int(g[1]) - n
	g[2] = w.tick + gap
	if e.kind == "unit":
		HotState.set_cd(w, int(e.id), gap)
		e.last_fired_tick = w.tick
		e.firing = 4
	else:
		e.cd_ticks = gap
	if gk == "rockets" and int(g[1]) <= 0 and e.kind == "unit":
		e.strike_ready = w.tick + _t(float(d.get("strike", {}).get("reload_s", 30.0)))


## Aim point of round i of mission M (no randomness).
static func _aim(w: SimWorld, M: Dictionary, i: int) -> Vector2:
	var a := Vector2(float(M.ax), float(M.ay))
	var b := Vector2(float(M.bx), float(M.by))
	var SH: Dictionary = R().get("shapes", {})
	if int(M.face) >= 0:
		var pts := KillZone71.strip_points(w, int(M.face), 12)
		return pts[(i * 5) % pts.size()] if not pts.is_empty() else a
	match String(M.shape):
		"line":
			var T := 9
			return a.lerp(b, (float((i * 4) % T) + 0.5) / float(T))
		"box":
			var cols := 4
			var rows := 3
			var j := (i * 7) % (cols * rows)
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
			var sz := (a - b).abs()
			return lo + Vector2((float(j % cols) + 0.5) / float(cols) * sz.x, (float(j / cols) + 0.5) / float(rows) * sz.y)
		"creeping":
			var S: Dictionary = SH.get("creeping", {})
			var dir := (b - a).normalized()
			var s := minf(_rf(S, "rate_tps", 0.5) * float(w.tick - int(M.t0)) / SimWorld.TICK_RATE, a.distance_to(b))
			var perp := Vector2(-dir.y, dir.x)
			var t := (float((i * 3) % 8) + 0.5) / 8.0
			return a + dir * s + perp * (t - 0.5) * _rf(S, "width", 8.0)
	var rr := _rf(SH.get("point", {}), "radius", 1.5)
	var ga := float(i) * 2.39996
	return a + Vector2(cos(ga), sin(ga)) * rr * sqrt((float(i % 12) + 0.5) / 12.0)


# ================================================================ rounds in flight
static func _rounds_step(w: SimWorld, st: Dictionary) -> void:
	var keep := []
	var land := []
	for Rd in st.rounds:
		Rd.t = int(Rd.t) - 1
		if int(Rd.t) > 0:
			keep.append(Rd)
		else:
			land.append(Rd)
	st.rounds = keep
	for Rd in land:
		var at := Vector2(float(Rd.x), float(Rd.y))
		if Strikes._intercepted(w, at, int(Rd.owner), "rocket" if String(Rd.gk) == "rockets" else "shell"):
			w.emit("StrikeIntercepted", {"kind": "fires71", "owner": int(Rd.owner), "src": int(Rd.src), "pos": at, "n": int(Rd.n)})
			continue
		_land(w, st, Rd, at)


static func _stat(Rd: Dictionary, dmg: float, spl: float) -> Dictionary:
	return {"weapon": String(Rd.wpn), "damage": dmg, "cls": "artillery", "splash": spl}


static func _land(w: SimWorld, st: Dictionary, Rd: Dictionary, at: Vector2) -> void:
	var kind := String(Rd.kind)
	var K: Dictionary = R().get("kinds", {}).get(kind, {})
	var fid := int(Rd.owner)
	var dmg := float(Rd.dmg)
	var spl := float(Rd.spl)
	var hits := 0
	# DAMAGE71 J1 (fact gore71.api seq 1641): splash outcome class for the Damage calls of this landing
	var g_rc := kind if (kind == "thermobaric" or kind == "incendiary") else ""
	var g_prev := SimWorld.Gore71.ctx_rc
	if g_rc != "":
		SimWorld.Gore71.ctx_rc = g_rc
	match kind:
		"smoke":
			if _senses == null:
				_senses = load(SENSES_PATH)
			_senses.call("add_smoke", w, at, _rf(K, "smoke_r", 3.0), _rf(K, "smoke_s", 25.0))
		"thermobaric":
			var n := Strikes._ground_targets(w, fid, at, spl).size()
			var mult := 1.0 + minf(_rf(K, "per_extra", 0.12) * float(maxi(n - 1, 0)), _rf(K, "cap", 1.0))
			hits = Strikes._impact(w, fid, int(Rd.src), at, _stat(Rd, dmg * mult, spl))
		"cluster":
			var nb := int(K.get("bomblets", 4))
			for i in nb:
				var ang := w.rng.randf() * TAU
				var r := sqrt(w.rng.randf()) * _rf(K, "spread", 1.5)
				hits += Strikes._impact(w, fid, int(Rd.src), _sn(at + Vector2(cos(ang), sin(ang)) * r), _stat(Rd, dmg, _rf(K, "bomblet_splash", 0.8)))
		"smart":
			var best = null
			var bd := INF
			for t in Strikes._ground_targets(w, fid, at, _rf(K, "seek_r", 4.0)):
				if t.kind != "unit" or String(Content.unit(String(t.def)).get("armor", "")) == "infantry":
					continue
				var dd := at.distance_squared_to(Vector2(t.pos))
				if dd < bd:
					bd = dd
					best = t
			if best != null:
				at = _sn(Vector2(best.pos))
			hits = Strikes._impact(w, fid, int(Rd.src), at, _stat(Rd, dmg, spl))
		_:
			hits = Strikes._impact(w, fid, int(Rd.src), at, _stat(Rd, dmg, spl))
			if kind == "incendiary":
				(st.burn as Array).append([at.x, at.y, _rf(K, "burn_r", 1.5), w.tick + _t(_rf(K, "burn_s", 20.0)), fid])
	if kind != "smoke":
		_friendly(w, Rd, at, dmg * _rf(R(), "danger_close_mult", 0.5), spl)
	if g_rc != "":
		SimWorld.Gore71.ctx_rc = g_prev
	w.emit("Fires71Impact", {"n": int(Rd.n), "kind": kind, "owner": fid, "pos": at, "hits": hits, "gk": String(Rd.gk)})


## Danger close: own ground units within the splash take dmg (scaled by distance like Strikes._impact).
static func _friendly(w: SimWorld, Rd: Dictionary, at: Vector2, dmg: float, spl: float) -> void:
	if dmg <= 0.0:
		return
	var fid := int(Rd.owner)
	var se = w.entities.get(int(Rd.src))
	if se == null:
		return
	var r2 := (spl + 0.3) * (spl + 0.3)
	var hit := []
	for u in SimIndex.units_by_owner(w).get(fid, []):
		if w.entities.has(int(u.id)) and at.distance_squared_to(Vector2(u.pos)) <= r2 and not bool(Content.unit(String(u.def)).get("is_air", false)):
			hit.append(u)
	hit.sort_custom(func(x, y): return int(x.id) < int(y.id))
	for u in hit:
		if not w.entities.has(int(u.id)):
			continue
		var s := _stat(Rd, dmg * (1.0 - 0.5 * clampf(at.distance_to(Vector2(u.pos)) / maxf(spl, 0.05), 0.0, 1.0)), spl)
		Damage.apply_hit(w, se, u, s, true)
	if not hit.is_empty():
		w.emit("FireFriendlyHit", {"n": int(Rd.n), "owner": fid, "pos": at, "count": hit.size()})


# ================================================================ burning (incendiary rounds + belts)
## Burn spots now: [[x, y, r, owner]] from incendiary spots and lit belts (belt sampled every belts.step tiles).
static func burn_spots(w: SimWorld, st: Dictionary) -> Array:
	var out := []
	for b in st.burn:
		out.append([float(b[0]), float(b[1]), float(b[2]), int(b[4])])
	var BR: Dictionary = R().get("belts", {})
	var ks: Array = (st.belts as Dictionary).keys()
	ks.sort_custom(func(x, y): return int(x) < int(y))
	for k in ks:
		var B: Dictionary = st.belts[k]
		if String(B.s) != "burning":
			continue
		var a := Vector2(float(B.ax), float(B.ay))
		var b := Vector2(float(B.bx), float(B.by))
		var n := maxi(ceili(a.distance_to(b) / _rf(BR, "step", 1.0)), 1)
		for i in n + 1:
			var p := a.lerp(b, float(i) / float(n))
			out.append([p.x, p.y, _rf(BR, "burn_r", 0.9), int(B.owner)])
	return out


static func _burn_step(w: SimWorld, st: Dictionary) -> void:
	var BR: Dictionary = R().get("belts", {})
	var every := maxi(int(BR.get("burn_every_ticks", 10)), 1)
	var keep := []
	for b in st.burn:
		if w.tick < int(b[3]):
			keep.append(b)
	st.burn = keep
	var bk: Array = (st.belts as Dictionary).keys()
	bk.sort_custom(func(x, y): return int(x) < int(y))
	for k in bk:
		var B: Dictionary = st.belts[k]
		if String(B.s) == "burning" and w.tick >= int(B.until):
			B.s = "spent"
			w.emit("BeltSpent", {"n": int(B.n), "owner": int(B.owner)})
		elif String(B.s) == "spent" and w.tick >= int(B.until) + _t(_rf(BR, "keep_spent_s", 30.0)):
			st.belts.erase(k)
	if w.tick % every != 2:
		return
	var spots := burn_spots(w, st)
	if spots.is_empty():
		return
	var dmg := _rf(BR, "burn_dmg", 8.0)
	var secs := _rf(BR, "ignite_s", 8.0)
	var done := {}
	for sp in spots:
		var p := Vector2(float(sp[0]), float(sp[1]))
		var fid := int(sp[3])
		for t in Strikes._ground_targets(w, fid, p, float(sp[2])):
			if t.kind != "unit" or done.has(int(t.id)) or not w.entities.has(int(t.id)):
				continue
			done[int(t.id)] = true
			var g_prev := SimWorld.Gore71.ctx_rc
			SimWorld.Gore71.ctx_rc = "incendiary"   # DAMAGE71 J1 splash outcome (fact gore71.api)
			Damage.apply_hit(w, {"id": -1, "owner": fid, "pos": p, "kind": "unit", "def": ""}, t, {"weapon": "g71_fire", "damage": dmg, "cls": "fire", "splash": 0.0}, true)
			SimWorld.Gore71.ctx_rc = g_prev
			if w.entities.has(int(t.id)):
				_ignite(w, t, secs)


## Guarded DAMAGE71 call (fact parts71.api): Parts71.ignite(w, e, secs). No-op while the API is absent.
static func _ignite(w: SimWorld, e: Dictionary, secs: float) -> void:
	if _parts_ok < 0:
		_parts_ok = 0
		if ResourceLoader.exists(PARTS_PATH):
			_parts = load(PARTS_PATH)
			if _parts != null:
				for m in _parts.get_script_method_list():
					if String(m.name) == "ignite" and (m.args as Array).size() >= 3:
						_parts_ok = 1
	if _parts_ok == 1:
		_parts.call("ignite", w, e, secs)


# ================================================================ display provider (render_snap g71 hook)
## Plain data for presentation/view/fires71_view.gd (RenderSnap.register_g71("fires71", ...)): side fid's missions,
## rounds in flight (from, at, t / tt), burn spots, belts, FPF faces (until / cd) and counter-battery tracks.
static func snap71(w: SimWorld, fid: int) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		return {}
	var out := {"m": [], "r": [], "burn": [], "belts": [], "fpf": {}, "cb": [], "tick": w.tick}
	var ks: Array = (st.missions as Dictionary).keys()
	ks.sort_custom(func(x, y): return int(x) < int(y))
	for k in ks:
		var M: Dictionary = st.missions[k]
		if int(M.owner) == fid:
			out.m.append([int(M.n), String(M.kind), String(M.shape), float(M.ax), float(M.ay), float(M.bx), float(M.by), int(M.face), int(M.obs)])
	for Rd in st.rounds:
		if int(Rd.owner) == fid:
			out.r.append([float(Rd.fx), float(Rd.fy), float(Rd.x), float(Rd.y), int(Rd.t), int(Rd.tt), String(Rd.kind)])
	for sp in burn_spots(w, st):
		out.burn.append(sp)
	var bk: Array = (st.belts as Dictionary).keys()
	bk.sort_custom(func(x, y): return int(x) < int(y))
	for k in bk:
		var B: Dictionary = st.belts[k]
		if int(B.owner) == fid:
			out.belts.append([int(B.n), float(B.ax), float(B.ay), float(B.bx), float(B.by), String(B.s)])
	for k in st.fpf:
		out.fpf[int(k)] = [int(st.fpf[k].until), int(st.fpf[k].cd)]
	for k in st.cb.tr:
		var tr: Dictionary = st.cb.tr[k]
		if int(tr.own) == fid:
			out.cb.append([int(k), float(tr.x), float(tr.y)])
	return out
