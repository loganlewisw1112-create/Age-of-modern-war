extends RefCounted
## G7 BLAST8 (G7_REFERENCE 13.9c-47): blast throw and concussion ("short comas"). Rules: content/g7/rules_g7_blast8.json.
##   on_burst(w, pos, prof, ids, src): called at the end of Shrapnel.burst (every explosion: artillery / mortar splash,
##     grenades, drone and strike munitions) with the ground units that burst considered (ascending id).
##     Charge W (kg) from the profile; scaled distance Z = d_m / W^(1/3). Throwable bodies (single soldiers, light
##     drones / crawlers: light armour, hp <= light_hp_max, or def blast_mass_kg) with Z < z_throw fly away from the
##     burst: distance D by charge, Z, mass and armour; peak height by D; landing point walked along the line and
##     clamped to the last cell the unit could stand on (never inside a building, through a wall or off a wall-walk).
##     Soldiers with Z < z_conc and line of sight to the burst may be knocked unconscious (concussion) for seconds up
##     to about a minute (applied on landing when thrown).
##   tick(w): flights (position along the line every tick, exact), landing (fall damage, knock-down pose, then
##     concussion or a short lie before getting up), concussion clocks (wake, or die of wounds through WOUND7).
##   Unconscious = WOUND7's e.wunc (so the care chain drags / treats them, senses / AI see them as down and the view
##   draws the unconscious pose) WITHOUT the G5 Medical "wounded" state (no hospital needed; they wake on their own).
##   While flying, lying or unconscious a unit cannot act: path stopped, order idle, no target, fire held, and its
##   position is held (except while dragged) - an order given then is dropped at once.
## State (saved, hashed): w.sys_state.blast8 = {fl: {id: [sx, sy, ex, ey, peak_m, t0, dur, turns, conc_ticks, land_dmg]},
##   lie: {id: get-up tick}, unc: {id: [wake tick, hold x, hold y, treated 0/1]}, sv: {id: 1} (wsv set by blast8)}.
##   Created on the first throw / concussion, erased when empty (a match without blasts carries nothing).
## Display (w.sys_state.g7v[id], read by the view only): bt = [sx, sy, ex, ey, peak_m, t0, dur, turns] while flying,
##   b8u = wake tick while unconscious from a blast; WOUND7's kd (landing knock-down) and unc keys as usual.
## RNG: w.rng only for the concussion duration variation (one draw per concussed soldier, ascending id).

const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const Damage = preload("res://sim/systems/damage.gd")

const Q := 1.0 / 1024.0
const G := 9.81
const DEF := {"tile_m": 4.0, "charge_kg": {"grenade": 0.18, "drone": 0.45, "mortar": 0.9}, "shell_kg_per_dmg": 0.05,
	"shell_kg_min": 1.0, "shell_kg_max": 15.0, "z_throw": 5.5, "throw_k": 4.5, "throw_pow": 2.0, "dist_min_m": 0.5,
	"height_k": 0.35, "height_max_m": 5.0, "height_min_m": 0.3, "min_flight_s": 0.35, "step_t": 0.2, "lie_s": 1.6,
	"land_safe_m": 1.0, "land_dmg_per_m": 6.0, "mass_kg": {"soldier": 95.0, "light": 30.0}, "light_hp_max": 120.0,
	"mass_ref": 95.0, "mass_fac_max": 2.5, "armour": {"none": {"throw": 1.0, "conc": 1.0}}, "z_conc": 9.0,
	"conc_pow": 1.5, "conc_min": 0.12, "conc_min_s": 3.0, "conc_max_s": 60.0, "conc_var": 0.2, "treated_wake_s": 4.0,
	"z_daze": 16.0, "daze_pow": 1.0, "daze_min": 0.05, "daze_min_s": 1.5, "daze_max_s": 8.0}

static var _reg = null


## True once world.gd ticks this system (SYSTEM_ORDER): until then a burst throws / knocks out nobody (nothing would
## land or wake).
static func registered() -> bool:
	if _reg == null:
		_reg = SimWorld.SYSTEM_ORDER.has(load("res://sim/systems/blast8.gd"))
	return bool(_reg)


static var _rref = null
static var _c := {}


static func cfg() -> Dictionary:
	var r: Dictionary = Content.rules()
	if is_same(r, _rref):
		return _c
	_rref = r
	var c: Dictionary = DEF.duplicate(true)
	c.merge(r.get("g7_blast8", {}), true)
	_c = c
	return _c


## Charge (kg TNT-equivalent) of a Shrapnel profile: profile charge_kg, else rules charge_kg[name], else shells by
## their blast damage (shell_kg_per_dmg, clamped).
static func charge(prof: Dictionary) -> float:
	if prof.has("charge_kg"):
		return maxf(float(prof.charge_kg), 0.01)
	var c := cfg()
	var nm := String(prof.get("name", "grenade"))
	var tab: Dictionary = c.charge_kg
	if nm != "shell" and tab.has(nm):
		return float(tab[nm])
	return clampf(float(prof.get("blast_dmg", 60.0)) * float(c.shell_kg_per_dmg), float(c.shell_kg_min), float(c.shell_kg_max))


## Mass (kg) of a throwable body; 0 = not thrown (vehicles, squads, buildings, heavy units).
static func mass(e: Dictionary) -> float:
	if e.get("kind", "") != "unit":
		return 0.0
	var d := Content.unit(String(e.def))
	if d.has("blast_mass_kg"):
		return float(d.blast_mass_kg)
	var mk: Dictionary = cfg().mass_kg
	if SimWorld.Wounds.applies(e):
		return float(mk.get("soldier", 95.0))
	if int(e.get("squad_size", d.get("squad_size", 1))) > 1:
		return 0.0
	if String(d.get("armor", "")) == "light" and float(d.get("hp", 1000)) <= float(cfg().light_hp_max):
		return float(mk.get("light", 30.0))
	return 0.0


## Personal armour class: entity / def armour_class (LETHAL8 round model, guarded), exo suits "exo", machines
## (non-soldier throwables) "machine", else "none".
static func armour_class(e: Dictionary) -> String:
	if e.has("armour_class"):
		return String(e.armour_class)
	var d := Content.unit(String(e.def))
	if d.has("armour_class"):
		return String(d.armour_class)
	if d.has("body_armor"):
		return String(d.body_armor)
	if e.has("exo") or d.has("exo"):
		return "exo"
	if not SimWorld.Wounds.applies(e):
		return "machine"
	return "none"


static func _arm(e: Dictionary) -> Dictionary:
	var a: Dictionary = cfg().armour
	return a.get(armour_class(e), a.get("none", {"throw": 1.0, "conc": 1.0}))


## Pure: throw distance (m) for charge W at distance d_m, body mass and armour throw factor. 0 = not thrown.
static func throw_m(w_kg: float, d_m: float, mass_kg: float, arm_throw: float) -> float:
	if mass_kg <= 0.0:
		return 0.0
	var c := cfg()
	var w3 := pow(maxf(w_kg, 0.001), 1.0 / 3.0)
	var z := d_m / w3
	var zt := float(c.z_throw)
	if z >= zt:
		return 0.0
	var mf := clampf(float(c.mass_ref) / mass_kg, 0.0, float(c.mass_fac_max))
	return float(c.throw_k) * w3 * pow(1.0 - z / zt, float(c.throw_pow)) * mf * arm_throw


## Pure: peak height (m) of a throw of D metres.
static func peak_m(d_m: float) -> float:
	var c := cfg()
	return clampf(float(c.height_k) * d_m, float(c.height_min_m), float(c.height_max_m))


## Pure: concussion severity 0..1 (0 = none) for charge W at d_m, armour conc factor.
static func conc_sev(w_kg: float, d_m: float, arm_conc: float) -> float:
	var c := cfg()
	var z := d_m / pow(maxf(w_kg, 0.001), 1.0 / 3.0)
	var zc := float(c.z_conc)
	if z >= zc:
		return 0.0
	var s := pow(1.0 - z / zc, float(c.conc_pow)) * arm_conc
	return s if s >= float(c.conc_min) else 0.0


## Pure: base concussion duration (s) for severity sev (> 0).
static func conc_s(sev: float) -> float:
	var c := cfg()
	var lo := float(c.conc_min_s)
	var mn := float(c.conc_min)
	return lo + (float(c.conc_max_s) - lo) * clampf((sev - mn) / maxf(1.0 - mn, 1e-6), 0.0, 1.0)


static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get("blast8")
	if st == null:
		st = {"fl": {}, "lie": {}, "unc": {}, "sv": {}}
		w.sys_state["blast8"] = st
	return st


static func _g7v(w: SimWorld, id: int) -> Dictionary:
	var g = w.sys_state.get("g7v")
	if g == null:
		g = {}
		w.sys_state["g7v"] = g
	var d = g.get(id)
	if d == null:
		d = {}
		g[id] = d
	return d


static func _g7v_erase(w: SimWorld, id: int, k: String) -> void:
	var g = w.sys_state.get("g7v")
	if g == null or not g.has(id):
		return
	var d: Dictionary = g[id]
	d.erase(k)
	if d.is_empty():
		g.erase(id)


static func flying(w: SimWorld, id: int) -> bool:
	var st = w.sys_state.get("blast8")
	return st != null and (st.fl as Dictionary).has(id)


static func unconscious(w: SimWorld, id: int) -> bool:
	var st = w.sys_state.get("blast8")
	return st != null and (st.unc as Dictionary).has(id)


## Ticks until a blast-concussed soldier wakes (-1 when not blast-concussed).
static func wake_in(w: SimWorld, id: int) -> int:
	var st = w.sys_state.get("blast8")
	if st == null or not (st.unc as Dictionary).has(id):
		return -1
	return maxi(int(st.unc[id][0]) - w.tick, 0)


## True while the unit cannot act because of a blast (flying, lying after landing, unconscious).
static func disabled(w: SimWorld, id: int) -> bool:
	var st = w.sys_state.get("blast8")
	return st != null and ((st.fl as Dictionary).has(id) or (st.lie as Dictionary).has(id) or (st.unc as Dictionary).has(id))


# ================================================================ burst hook
## Before the fragments: throwable soldiers within throw reach of the burst {id: [pos, def, owner]} (so the men the
## blast kills are still thrown: display event BlastCorpse, the body flies and lands; no sim state).
static func pre(w: SimWorld, pos: Vector2, prof: Dictionary, cands: Array) -> Dictionary:
	var out := {}
	if cands.is_empty() or not registered():
		return out
	var c := cfg()
	var reach := float(c.z_throw) * pow(charge(prof), 1.0 / 3.0) / float(c.tile_m)
	var r2 := reach * reach
	for id in cands:
		var e = w.entities.get(id)
		if e != null and e.kind == "unit" and SimWorld.Wounds.applies(e) and Vector2(e.pos).distance_squared_to(pos) <= r2:
			out[int(id)] = [Vector2(e.pos), String(e.def), int(e.owner)]
	return out


static func on_burst(w: SimWorld, pos: Vector2, prof: Dictionary, ids: Array, src: Dictionary, pre_in: Dictionary = {}) -> void:
	if not registered():
		return
	if not pre_in.is_empty():
		_corpses(w, pos, prof, pre_in)
	if ids.is_empty():
		return
	var c := cfg()
	var wkg := charge(prof)
	var w3 := pow(wkg, 1.0 / 3.0)
	var tm := float(c.tile_m)
	var reach := maxf(maxf(float(c.z_throw), float(c.z_conc)), float(c.get("z_daze", 0.0))) * w3 / tm   # tiles (ACCURACY8B: + daze reach)
	var r2 := reach * reach
	var st0 = w.sys_state.get("blast8")
	for id in ids:
		var e = w.entities.get(id)
		if e == null or e.kind != "unit":
			continue
		var ep: Vector2 = e.pos
		var d2 := ep.distance_squared_to(pos)
		if d2 > r2:
			continue
		if st0 != null and (st0.fl as Dictionary).has(int(id)):
			continue   # already in the air: one throw at a time
		if bool(e.get("wounded", false)) or e.has("evac_by"):
			continue   # Medical casualties lie pinned (G5 rule); aboard a carrier
		var dm := sqrt(d2) * tm
		if d2 > 0.0025 and not Damage.line_clear(w, pos, ep):
			continue
		var zone: bool = SimWorld.Wounds.applies(e)
		var am := _arm(e)
		var ct := 0
		if zone and not bool(e.get("wunc", false)) or (zone and unconscious(w, int(id))):
			var sev := conc_sev(wkg, dm, float(am.get("conc", 1.0)))
			if sev > 0.0:
				var s := conc_s(sev) * (1.0 + float(c.conc_var) * (2.0 * w.rng.randf() - 1.0))
				ct = maxi(int(round(s * SimWorld.TICK_RATE)), 1)
		var dist := throw_m(wkg, dm, mass(e), float(am.get("throw", 1.0)))
		if dist >= float(c.dist_min_m):
			_throw(w, e, pos, dist, ct, int(src.get("id", -1)))
			st0 = w.sys_state.get("blast8")
		else:
			if ct > 0:
				concuss(w, e, ct)
				st0 = w.sys_state.get("blast8")
			if zone and dist > 0.0:
				SimWorld.Wounds.vis_kd(w, e)
		if zone and ct == 0 and not bool(e.get("wunc", false)):
			# G7 ACCURACY8B (13.9c-53, owner "Yes, dazed"): not knocked out = dazed for a few seconds (no draw)
			var dsev := daze_sev(wkg, dm, float(am.get("conc", 1.0)))
			if dsev > 0.0:
				daze(w, e, maxi(int(round(daze_s(dsev) * SimWorld.TICK_RATE)), 1))
				st0 = w.sys_state.get("blast8")


## Men killed by this burst: their bodies are thrown too (display event only, ascending id).
static func _corpses(w: SimWorld, pos: Vector2, prof: Dictionary, pre_in: Dictionary) -> void:
	var c := cfg()
	var wkg := charge(prof)
	var tm := float(c.tile_m)
	var ids: Array = pre_in.keys()
	ids.sort()
	for id in ids:
		if w.entities.has(int(id)):
			continue
		var q: Array = pre_in[id]
		var p0: Vector2 = q[0]
		var dm := p0.distance_to(pos) * tm
		var dist := throw_m(wkg, dm, float((c.mass_kg as Dictionary).get("soldier", 95.0)), 1.0)
		if dist < float(c.dist_min_m):
			continue
		var dir := p0 - pos
		if dir.length_squared() < 0.0001:
			dir = Vector2.RIGHT.rotated(deg_to_rad(float((int(id) * 137) % 360)))
		dir = dir.normalized()
		var end := land_point_mc(w, "foot", -1, p0, dir, dist / tm)
		var h := snappedf(peak_m(maxf(p0.distance_to(end) * tm, dist * 0.5)), Q)
		var dur := maxi(int(ceil(maxf(2.0 * sqrt(2.0 * h / G), float(c.min_flight_s)) * SimWorld.TICK_RATE)), 2)
		w.emit("BlastCorpse", {"id": int(id), "def": String(q[1]), "owner": int(q[2]), "from": p0, "to": end,
			"peak_m": h, "ticks": dur, "turns": clampi(int(round(h * 0.8)), 1, 3) * (1 if int(id) % 2 == 0 else -1)})


## Throws e away from `at` by dist_m metres (sim state, exact).
static func _throw(w: SimWorld, e: Dictionary, at: Vector2, dist_m: float, conc_ticks: int, src_id: int) -> void:
	var c := cfg()
	var id := int(e.id)
	var p0: Vector2 = e.pos
	var dir := p0 - at
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT.rotated(deg_to_rad(float((id * 137) % 360)))   # dead centre: a fixed per-unit direction
	dir = dir.normalized()
	var tm := float(c.tile_m)
	var end := land_point(w, e, p0, dir, dist_m / tm)
	var flown := p0.distance_to(end) * tm
	var h := snappedf(peak_m(maxf(flown, dist_m * 0.5)), Q)
	var tsec := maxf(2.0 * sqrt(2.0 * h / G), float(c.min_flight_s))
	var dur := maxi(int(ceil(tsec * SimWorld.TICK_RATE)), 2)
	var turns := clampi(int(round(h * 0.8)), 1, 3) * (1 if id % 2 == 0 else -1)
	var ld := snappedf(maxf(h - float(c.land_safe_m), 0.0) * float(c.land_dmg_per_m), Q)
	var st := _st(w)
	var sx := snappedf(p0.x, Q)
	var sy := snappedf(p0.y, Q)
	st.fl[id] = [sx, sy, end.x, end.y, h, w.tick, dur, turns, conc_ticks, ld, src_id]
	st.lie.erase(id)
	_freeze(w, e)
	_g7v(w, id)["bt"] = [sx, sy, end.x, end.y, h, w.tick, dur, turns]
	w.emit("BlastThrown", {"id": id, "owner": int(e.owner), "from": p0, "to": end, "peak_m": h, "ticks": dur})


## Landing point: walks from p0 along dir in step_t tiles up to want tiles; stops before the first cell the unit
## could not stand on (building footprint, wall, cliff, water for foot, map edge) or another wall-walk level.
static func land_point(w: SimWorld, e: Dictionary, p0: Vector2, dir: Vector2, want: float) -> Vector2:
	Movement._ensure_nav(w)
	return land_point_mc(w, Movement.move_class(e), Movement.team_of(w, e), p0, dir, want)


static func land_point_mc(w: SimWorld, mc: String, team: int, p0: Vector2, dir: Vector2, want: float) -> Vector2:
	var stp := float(cfg().step_t)
	var n := maxi(int(ceil(want / stp)), 1)
	var last := p0
	var lc := w.cell_of(p0)
	var ww0 := Movement.wallwalk_any(w) and Movement.wallwalk_team(w, lc) >= 0
	for i in range(1, n + 1):
		var q := p0 + dir * minf(float(i) * stp, want)
		var qc := w.cell_of(q)
		if qc != lc:
			if not Movement.is_passable(w, qc, mc, team):
				break
			if Movement.wallwalk_any(w) and (Movement.wallwalk_team(w, qc) >= 0) != ww0:
				break
			if qc.x != lc.x and qc.y != lc.y:   # diagonal step: both side cells must be open (no corner cutting through walls)
				if not Movement.is_passable(w, Vector2i(qc.x, lc.y), mc, team) or not Movement.is_passable(w, Vector2i(lc.x, qc.y), mc, team):
					break
			lc = qc
		last = q
	return Vector2(snappedf(last.x, Q), snappedf(last.y, Q))


## G7 ACCURACY8B (13.9c-53) pure: daze severity 0..1 (0 = none) for charge W at d_m, armour conc factor (the
## concussion curve with the wider reach z_daze).
static func daze_sev(w_kg: float, d_m: float, arm_conc: float) -> float:
	var c := cfg()
	var zd := float(c.get("z_daze", 0.0))
	if zd <= 0.0:
		return 0.0
	var z := d_m / pow(maxf(w_kg, 0.001), 1.0 / 3.0)
	if z >= zd:
		return 0.0
	var s := pow(1.0 - z / zd, float(c.get("daze_pow", 1.0))) * arm_conc
	return clampf(s, 0.0, 1.0) if s >= float(c.get("daze_min", 0.05)) else 0.0


## Pure: daze duration (s) for daze severity sev (> 0).
static func daze_s(sev: float) -> float:
	var c := cfg()
	var lo := float(c.get("daze_min_s", 1.5))
	return lo + (float(c.get("daze_max_s", 8.0)) - lo) * clampf(sev, 0.0, 1.0)


## ACCURACY8B: dazes soldier e for `ticks` (extends a running daze): e.b8d = until tick (saved with the entity; read
## by Accuracy8: aim x under_fire.daze, placement, slower reactions); st.dz {id: until} lets tick() clear it.
static func daze(w: SimWorld, e: Dictionary, ticks: int) -> void:
	if not w.entities.has(int(e.id)):
		return
	var until := maxi(int(e.get("b8d", -1)), w.tick + ticks)
	e.b8d = until
	var st := _st(w)
	if not st.has("dz"):
		st["dz"] = {}
	st.dz[int(e.id)] = until
	w.emit("Dazed", {"id": int(e.id), "owner": int(e.owner), "until": until})


static func _dz_pass(w: SimWorld, st: Dictionary) -> void:
	var dz: Dictionary = st.dz
	var done := []
	for id in dz:
		if int(dz[id]) <= w.tick:
			done.append(id)
	done.sort()
	for id in done:
		dz.erase(id)
		var e = w.entities.get(id)
		if e != null and int(e.get("b8d", -1)) <= w.tick:
			e.erase("b8d")


## Knocks soldier e unconscious for `ticks` (extends a running concussion).
static func concuss(w: SimWorld, e: Dictionary, ticks: int) -> void:
	if not SimWorld.Wounds.applies(e) or not w.entities.has(int(e.id)):
		return
	var id := int(e.id)
	var st := _st(w)
	var wake := w.tick + ticks
	if st.unc.has(id):
		var u: Array = st.unc[id]
		u[0] = maxi(int(u[0]), wake)
		_g7v(w, id)["b8u"] = int(u[0])
		return
	st.lie.erase(id)
	if not bool(e.get("wunc", false)):
		e.wunc = true
		if not bool(e.get("wsv", false)):
			e.wsv = true   # a concussion is not a wound: no survival roll when a medic first treats him
			st.sv[id] = 1
	var p: Vector2 = e.pos
	st.unc[id] = [wake, snappedf(p.x, Q), snappedf(p.y, Q), 0]
	_freeze(w, e)
	_g7v(w, id)["b8u"] = wake
	SimWorld.Wounds.vis_mark(w, id)
	w.emit("Concussed", {"id": id, "owner": int(e.owner), "pos": p, "ticks": ticks})


## No action this tick: path stopped, idle order, no target, fire held.
static func _freeze(w: SimWorld, e: Dictionary) -> void:
	if bool(e.get("moving", false)) or not (e.get("path", []) as Array).is_empty():
		Movement.stop_path(e)
	if String((e.get("order", {}) as Dictionary).get("type", "idle")) != "idle":
		e.order = {"type": "idle"}
	if int(e.get("target", -1)) != -1:
		e.target = -1
	if int(e.get("cd_ticks", 0)) < 2:
		e.cd_ticks = 2
		e.cooldown = 2.0 / SimWorld.TICK_RATE
	HotState.touch(w, int(e.id))


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("blast8")
	if st == null:
		return
	var fl: Dictionary = st.fl
	if not fl.is_empty():
		_fl_pass(w, st, fl)
	if not (st.lie as Dictionary).is_empty():
		_lie_pass(w, st)
	if not (st.unc as Dictionary).is_empty():
		_unc_pass(w, st)
	if st.has("dz"):
		if not (st.dz as Dictionary).is_empty():
			_dz_pass(w, st)
		if (st.dz as Dictionary).is_empty():
			st.erase("dz")
	if fl.is_empty() and (st.lie as Dictionary).is_empty() and (st.unc as Dictionary).is_empty() and not st.has("dz"):
		w.sys_state.erase("blast8")


static func _fl_pass(w: SimWorld, st: Dictionary, fl: Dictionary) -> void:
	var ids: Array = fl.keys()
	ids.sort()
	for id in ids:
		var f: Array = fl[id]
		var e = w.entities.get(id)
		if e == null:
			fl.erase(id)
			_g7v_erase(w, int(id), "bt")
			continue
		var t := w.tick - int(f[5])
		var dur := int(f[6])
		if t < dur:
			var k := float(t) / float(dur)
			var p := Vector2(snappedf(lerpf(float(f[0]), float(f[2]), k), Q), snappedf(lerpf(float(f[1]), float(f[3]), k), Q))
			e.pos = p
			_freeze(w, e)
			HotState.set_pos(w, int(id), p)
			continue
		# landing
		fl.erase(id)
		_g7v_erase(w, int(id), "bt")
		var end := Vector2(float(f[2]), float(f[3]))
		e.pos = end
		_freeze(w, e)
		HotState.set_pos(w, int(id), end)
		w.emit("BlastLanded", {"id": int(id), "owner": int(e.owner), "pos": end})
		var ld := float(f[9])
		if ld > 0.0:
			var src = w.entities.get(int(f[10])) if f.size() > 10 else null
			if src == null:
				src = {"id": -1, "owner": -1, "pos": end, "kind": "none"}
			Damage.wound_hit(w, src, e, ld, "")
			if not w.entities.has(int(id)):
				continue
			if float(e.hp) <= 0.0:
				continue
		if SimWorld.Wounds.applies(e):
			SimWorld.Wounds.vis_kd(w, e)
		if int(f[8]) > 0 and not bool(e.get("wounded", false)):
			concuss(w, e, int(f[8]))
		elif not bool(e.get("wounded", false)):
			st.lie[int(id)] = w.tick + maxi(int(round(float(cfg().lie_s) * SimWorld.TICK_RATE)), 1)


static func _lie_pass(w: SimWorld, st: Dictionary) -> void:
	var lie: Dictionary = st.lie
	var ids: Array = lie.keys()
	ids.sort()
	for id in ids:
		var e = w.entities.get(id)
		if e == null or w.tick >= int(lie[id]) or bool(e.get("wounded", false)):
			lie.erase(id)
			continue
		_freeze(w, e)


static func _unc_pass(w: SimWorld, st: Dictionary) -> void:
	var unc: Dictionary = st.unc
	var ids: Array = unc.keys()
	ids.sort()
	var tw := int(round(float(cfg().treated_wake_s) * SimWorld.TICK_RATE))
	for id in ids:
		var u: Array = unc[id]
		var e = w.entities.get(id)
		if e == null:
			unc.erase(id)
			st.sv.erase(id)
			_g7v_erase(w, int(id), "b8u")
			continue
		if bool(e.get("wstab", false)) and int(u[3]) == 0:
			u[3] = 1   # stabilised by a medic: comes round soon
			u[0] = mini(int(u[0]), w.tick + tw)
			_g7v(w, int(id))["b8u"] = int(u[0])
		if w.tick >= int(u[0]):
			unc.erase(id)
			_g7v_erase(w, int(id), "b8u")
			var mine: bool = (st.sv as Dictionary).has(id)
			st.sv.erase(id)
			if not bool(e.get("wounded", false)):   # went down from wounds meanwhile: WOUND7 / Medical keep him
				e.erase("wunc")
				if mine:
					e.erase("wsv")
				HotState.touch(w, int(id))
				SimWorld.Wounds.vis_mark(w, int(id))
				w.emit("Regained", {"id": int(id), "owner": int(e.owner), "pos": e.pos})
			continue
		if bool(e.get("wounded", false)):
			continue   # Medical holds him (wnd_pos) while down
		var hp := Vector2(float(u[1]), float(u[2]))
		if e.has("wdby") or e.has("evac_by"):
			var p: Vector2 = e.pos
			u[1] = snappedf(p.x, Q)
			u[2] = snappedf(p.y, Q)
		elif Vector2(e.pos) != hp:
			e.pos = hp
			HotState.set_pos(w, int(id), hp)
		_freeze(w, e)
