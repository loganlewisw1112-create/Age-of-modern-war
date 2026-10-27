extends RefCounted
## G7 (CNSIM7): advanced APC systems (master scope 6.5-6.6). Owner: CNSIM7.
## Defs: content/g7/defs_g7_cn.json units with an `apc7` block (strike APC, tactical APC, Human A and B).
##  - unhackable (def flag `unhackable`; CREEP7's can_hack asks Apc7.unhackable(e)); immune to EMP (own pulse too).
##  - strike APC: two manned .50 mounts (front, rear), NO main weapon (def main_weapon ""; its one Combat weapon
##    g7_cn_hmg50 IS the mount pair). Security gunners riding inside man the mounts; a hit on the hull may hit a
##    mount gunner (shielded), who is replaced from inside; no gunner aboard = the mounts hold fire.
##    Tactical APC: one remote twin .50 (always manned).
##  - shield dome (cn_dome, only while stopped; charge absorbs hits on the APC and friendly units inside its radius,
##    breaks at 0 and recharges after recharge_s), active protection (APS charges vs at/tank/artillery/missile shots
##    and strikes, reload one charge per reload_s), anti-drone emitter (damages the nearest enemy drone in radius once
##    per every_s), short-range EMP pulse (cn_emp: enemy machines/electronics hold fire, enemy drones go down, leeches
##    knocked off via CREEP7's Creep.detach_leeches), side panels (cn_panels kind interceptors|smoke|idrones; limited
##    stock refilled by restock at CNFAC7's facility).
## Damage hooks for ORCH to wire into G6Hooks (cheap when no CN APC exists: one dict lookup):
##   damage_mult(w, src, s, t) (dome absorption), shot_blocked(w, src, s, t, at) (APS / interceptor panel / smoke),
##   intercept_strike(w, fid, at, kind) (APS vs strikes).
## State: e.a7 per APC; w.sys_state.apc7 {ids, domes, drones, ver} created by init_apc (never in matches without the
## counter-nanite line). Determinism: ascending ids, w.rng only, integer ticks.

const VER := 1
const PANEL_KINDS := ["interceptors", "smoke", "idrones"]
static var _api := {}


static func cfg_of(def_id: String) -> Dictionary:
	var c = Content.unit(def_id).get("apc7", {})
	return c if typeof(c) == TYPE_DICTIONARY else {}


static func is_apc(e) -> bool:
	return typeof(e) == TYPE_DICTIONARY and String(e.get("kind", "")) == "unit" and not cfg_of(String(e.get("def", ""))).is_empty()


## CREEP7's can_hack must refuse these (both CN APCs, sentry turrets).
static func unhackable(e) -> bool:
	return typeof(e) == TYPE_DICTIONARY and bool(Content.unit(String(e.get("def", ""))).get("unhackable", false))


## true when the def has a main gun (the strike APC has none: its only weapon is the .50 mount pair).
static func has_main_weapon(def_id: String) -> bool:
	return String(Content.unit(def_id).get("main_weapon", Content.unit(def_id).get("weapon", ""))) != ""


static func ticks(sec: float) -> int:
	return maxi(roundi(sec * SimWorld.TICK_RATE), 1)


## Guarded call into another G7 agent's script (missing function = dflt).
static func callf(s: Script, fn: String, args: Array, dflt):
	if s == null:
		return dflt
	var key := s.resource_path + ":" + fn
	if not _api.has(key):
		var ok := false
		for m in s.get_script_method_list():
			if String(m.name) == fn:
				ok = true
				break
		_api[key] = ok
	if not bool(_api[key]):
		return dflt
	return s.callv(fn, args)


static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get("apc7")
	if st == null:
		st = {"ids": [], "domes": [], "drones": {}, "ver": VER}
		w.sys_state["apc7"] = st
	return st


## Registers a freshly spawned CN APC (CounterNanite.spawn_team calls this).
static func init_apc(w: SimWorld, e: Dictionary) -> void:
	var c := cfg_of(String(e.def))
	var st := _st(w)
	if not (st.ids as Array).has(int(e.id)):
		st.ids.append(int(e.id))
		st.ids.sort()
	e.a7 = {"dome": float(c.get("dome", {}).get("charge", 1000.0)), "dome_on": false, "dome_cd": 0,
		"aps": int(c.get("aps", {}).get("charges", 0)), "aps_cd": 0, "emp_cd": 0, "icpt_until": -1, "smoke_until": -1,
		"st": (c.get("panels", {}) as Dictionary).duplicate(), "mg": {}, "hp_last": float(e.hp), "pk": []}
	e.unhackable = true


## Refill panel stock and APS charges (CNFAC7's facility workshop calls this).
static func restock(w: SimWorld, e: Dictionary) -> void:
	if not e.has("a7"):
		return
	var c := cfg_of(String(e.def))
	e.a7.st = (c.get("panels", {}) as Dictionary).duplicate()
	e.a7.aps = int(c.get("aps", {}).get("charges", 0))
	w.emit("ApcRestocked", {"id": int(e.id), "owner": int(e.owner)})


static func refill(w: SimWorld, e: Dictionary) -> void:
	restock(w, e)


static func dome_up(e) -> bool:
	return typeof(e) == TYPE_DICTIONARY and e.has("a7") and bool(e.a7.dome_on)


## The dome-on APC (same owner) covering pos, or null.
static func dome_over(w: SimWorld, fid: int, pos: Vector2):
	var st = w.sys_state.get("apc7")
	if st == null or (st.domes as Array).is_empty():
		return null
	for id in st.domes:
		var a = w.entities.get(int(id))
		if a == null or int(a.owner) != fid or not dome_up(a):
			continue
		var r := float(cfg_of(String(a.def)).get("dome", {}).get("radius", 4.0))
		if Vector2(a.pos).distance_to(pos) <= r:
			return a
	return null


static func set_dome(w: SimWorld, e: Dictionary, on: bool) -> void:
	var st := _st(w)
	if on == bool(e.a7.dome_on):
		return
	e.a7.dome_on = on
	if on:
		if not (st.domes as Array).has(int(e.id)):
			st.domes.append(int(e.id))
			st.domes.sort()
	else:
		st.domes.erase(int(e.id))
	w.emit("ApcDome", {"id": int(e.id), "owner": int(e.owner), "on": on, "charge": float(e.a7.dome)})


# ================================================================ damage hooks (ORCH wires into G6Hooks)
## Target-side damage factor: a hit on a unit under a friendly dome is absorbed by the dome charge (0.0).
static func damage_mult(w: SimWorld, _src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	var st = w.sys_state.get("apc7")
	if st == null or (st.domes as Array).is_empty() or String(t.get("kind", "")) != "unit":
		return 1.0
	var a = dome_over(w, int(t.owner), Vector2(t.pos))
	if a == null:
		return 1.0
	absorb(w, a, float(s.get("dmg", s.get("damage", 10.0))))
	return 0.0


## Dome takes `amount`; breaks at 0 (recharge timer).
static func absorb(w: SimWorld, a: Dictionary, amount: float) -> void:
	a.a7.dome = maxf(float(a.a7.dome) - amount, 0.0)
	if float(a.a7.dome) <= 0.0:
		var c := cfg_of(String(a.def))
		a.a7.dome_cd = w.tick + ticks(float(c.get("dome", {}).get("recharge_s", 45)))
		set_dome(w, a, false)
		w.emit("ApcDomeBroken", {"id": int(a.id), "owner": int(a.owner), "pos": a.pos})


## Shot hook: APS / interceptor panel vs heavy shots at a CN APC; the dome stops indirect shells landing inside
## it; smoke makes long shots into it miss half the time.
static func shot_blocked(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary, at: Vector2) -> bool:
	var st = w.sys_state.get("apc7")
	if st == null:
		return false
	var heavy := bool(s.get("guided", false)) or bool(s.get("indirect", false))
	if t.has("a7") and _aps_try(w, t, String(s.get("cls", "")), heavy, int(src.get("owner", -1))):
		return true
	if bool(s.get("indirect", false)) and dome_over(w, int(t.get("owner", -1)), at) != null:
		w.emit("ApcDomeStop", {"pos": at, "owner": int(t.get("owner", -1))})
		return true
	for id in st.ids:
		var a = w.entities.get(int(id))
		if a == null or int(a.a7.smoke_until) < w.tick or int(a.owner) != int(t.get("owner", -2)):
			continue
		if Vector2(a.pos).distance_to(at) <= 4.0 and Vector2(src.get("pos", at)).distance_to(at) > 3.0:
			return w.rng.randf() < 0.5
	return false


static func _aps_try(w: SimWorld, a: Dictionary, cls: String, heavy: bool, attacker: int) -> bool:
	var c: Dictionary = cfg_of(String(a.def)).get("aps", {})
	if not heavy and not (c.get("classes", []) as Array).has(cls):
		return false
	if int(a.a7.icpt_until) >= w.tick:
		w.emit("ApsIntercept", {"id": int(a.id), "owner": int(a.owner), "attacker": attacker, "cls": cls, "by": "panel"})
		return true
	if int(a.a7.aps) <= 0:
		return false
	a.a7.aps = int(a.a7.aps) - 1
	a.a7.aps_cd = maxi(int(a.a7.aps_cd), w.tick + ticks(float(c.get("reload_s", 8))))
	w.emit("ApsIntercept", {"id": int(a.id), "owner": int(a.owner), "attacker": attacker, "cls": cls, "by": "aps", "left": int(a.a7.aps)})
	return true


## Strike interception (missile, shell, rocket, drone) landing at `at` near a CN APC of an enemy of attacker_fid.
static func intercept_strike(w: SimWorld, attacker_fid: int, at: Vector2, kind: String) -> bool:
	var st = w.sys_state.get("apc7")
	if st == null:
		return false
	for id in st.ids:
		var a = w.entities.get(int(id))
		if a == null or not w.is_enemy(attacker_fid, int(a.owner)) or Vector2(a.pos).distance_to(at) > 3.0:
			continue
		if _aps_try(w, a, kind, true, attacker_fid):
			return true
	return false


# ================================================================ helpers
static func R() -> Dictionary:
	return Content.rules().get("g7_cn", {})


## Units within r of p, ascending id (combat grid when built, else a full scan).
static func near(w: SimWorld, p: Vector2, r: float) -> Array:
	if w.cache.has("combat_ng") or w.cache.has("combat_grid"):
		return SimWorld.G4bMech.near_units(w, p, r)
	var out := []
	var r2 := r * r
	for u in SimWorld.SimIndex.of(w, "unit"):
		if w.entities.has(int(u.id)) and p.distance_squared_to(Vector2(u.pos)) <= r2:
			out.append(u)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


## A soldier dict riding inside a carrier dies (no map entity to destroy).
static func kill_cargo(w: SimWorld, c: Dictionary, u: Dictionary, cause: String) -> void:
	(c.cargo as Array).erase(u)
	w.cache.erase("transport")
	w.cache.erase("cargo_of")
	w.emit("EntityDestroyed", {"id": int(u.id), "kind": "unit", "def": u.def, "owner": int(u.owner), "pos": c.pos,
		"cause": cause, "killer_owner": SimWorld.NEUTRAL, "squad": int(u.get("squad", -1))})
	if w.factions.has(int(u.owner)):
		w.factions[int(u.owner)].stats.lost += 1


static func _disable(w: SimWorld, t: Dictionary, dur: int) -> void:
	t.emp_until = w.tick + dur
	t.jammed_until = maxi(int(t.get("jammed_until", -1)), w.tick + dur)
	SimWorld.HotState.set_cd(w, int(t.id), maxi(SimWorld.HotState.get_cd(w, int(t.id)), dur))


# ================================================================ system tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get("apc7")
	if st == null:
		return
	var keep := []
	for id in st.ids:
		var e = w.entities.get(int(id))
		if e == null:
			if SimWorld.Transport.in_cargo(w, int(id)):
				keep.append(int(id))   # inside a dropship
			else:
				st.domes.erase(int(id))
			continue
		keep.append(int(id))
		_tick_apc(w, e)
	st.ids = keep
	if not (st.drones as Dictionary).is_empty():
		var dk: Array = st.drones.keys()
		dk.sort()
		for k in dk:
			if w.tick >= int(st.drones[k]):
				st.drones.erase(k)
				if w.entities.has(int(k)):
					w.destroy(int(k), "expired")


## Crew drill under fire: a hit APC pops its smoke panel by itself (limited stock, at most once per smoke cloud +
## apc7.auto_smoke_gap_s); smoke spoils the enemy's aim (shot_blocked) while the motorcade pushes through.
static func _auto_smoke(w: SimWorld, e: Dictionary, c: Dictionary) -> void:
	var a: Dictionary = e.a7
	if not bool(c.get("auto_smoke", true)) or int(a.st.get("smoke", 0)) <= 0:
		return
	if w.tick < int(a.smoke_until) + ticks(float(c.get("auto_smoke_gap_s", 6.0))):
		return
	fire_panel(w, e, "smoke")


static func _tick_apc(w: SimWorld, e: Dictionary) -> void:
	var a: Dictionary = e.a7
	var c := cfg_of(String(e.def))
	var id := int(e.id)
	var hp := float(e.hp)
	if hp < float(a.hp_last) - 0.01:
		if bool(c.get("manned_mounts", false)):
			_gunner_hit(w, e, float(a.hp_last) - hp, c)
		_auto_smoke(w, e, c)
	a.hp_last = hp
	var dc: Dictionary = c.get("dome", {})
	if bool(a.dome_on) and bool(e.get("moving", false)):
		set_dome(w, e, false)   # the dome only holds while the APC is stopped
	if not bool(a.dome_on) and w.tick >= int(a.dome_cd) and float(a.dome) < float(dc.get("charge", 1000)):
		a.dome = minf(float(a.dome) + float(dc.get("regen_per_s", 20)) * SimWorld.DT, float(dc.get("charge", 1000)))
	var ac: Dictionary = c.get("aps", {})
	if int(a.aps) < int(ac.get("charges", 0)) and w.tick >= int(a.aps_cd):
		a.aps = int(a.aps) + 1
		a.aps_cd = w.tick + ticks(float(ac.get("reload_s", 8)))
	if bool(c.get("manned_mounts", false)):
		_man_mounts(w, e, c)
	var ec: Dictionary = c.get("emitter", {})
	if not ec.is_empty() and (w.tick + id) % ticks(float(ec.get("every_s", 1.0))) == 0:
		_emitter(w, e, ec)


## Security gunners riding inside man the mounts (ascending id); a missing gunner is replaced from inside.
static func _man_mounts(w: SimWorld, e: Dictionary, c: Dictionary) -> void:
	var mg: Dictionary = e.a7.mg
	var gunners := []
	if e.has("cargo"):
		for u in e.cargo:
			if String(Content.unit(String(u.def)).get("cn_role", "")) == "gunner":
				gunners.append(int(u.id))
	var manned := 0
	for slot in c.get("mounts", []):
		var cur := int(mg.get(slot, -1))
		if cur >= 0 and gunners.has(cur):
			manned += 1
			continue
		var pick := -1
		for gid in gunners:
			if not mg.values().has(gid):
				pick = int(gid)
				break
		if pick >= 0:
			mg[slot] = pick
			manned += 1
			if cur >= 0:
				w.emit("MountGunnerSwap", {"id": int(e.id), "owner": int(e.owner), "slot": slot, "from": cur, "to": pick})
		elif mg.has(slot):
			mg.erase(slot)
	e.a7.manned = manned
	if manned == 0 and SimWorld.HotState.get_cd(w, int(e.id)) < 2:
		SimWorld.HotState.set_cd(w, int(e.id), 2)   # no gunner aboard: the mounts hold fire


static func _gunner_hit(w: SimWorld, e: Dictionary, dmg: float, c: Dictionary) -> void:
	var mg: Dictionary = e.a7.mg
	if mg.is_empty() or not e.has("cargo"):
		return
	if w.rng.randf() >= float(R().get("gunner", {}).get("hit_chance", 0.25)):
		return
	var slots: Array = mg.keys()
	slots.sort()
	var slot = slots[w.rng.randi_range(0, slots.size() - 1)]
	var gid := int(mg[slot])
	for u in e.cargo:
		if int(u.id) != gid:
			continue
		u.hp = snappedf(float(u.hp) - dmg * float(c.get("gunner_shield", 0.3)), 0.01)
		w.emit("MountGunnerHit", {"id": int(e.id), "owner": int(e.owner), "slot": slot, "gunner": gid, "hp": float(u.hp)})
		if float(u.hp) <= 0.0:
			mg.erase(slot)
			kill_cargo(w, e, u, "mount_gunner")
		return


static func _emitter(w: SimWorld, e: Dictionary, ec: Dictionary) -> void:
	var best = null
	var bd := INF
	for u in near(w, e.pos, float(ec.get("radius", 6.0))):
		if not w.is_enemy(int(e.owner), int(u.owner)) or not SimWorld.Counterdrone.is_drone(w, u):
			continue
		var d := Vector2(u.pos).distance_to(e.pos)
		if d < bd:
			bd = d
			best = u
	if best == null:
		return
	var hp := snappedf(float(best.hp) - float(ec.get("damage", 30)), 0.01)
	SimWorld.HotState.set_hp(w, int(best.id), hp)
	w.emit("ApcEmitter", {"id": int(e.id), "owner": int(e.owner), "target": int(best.id), "pos": best.pos})
	if hp <= 0.0:
		w.destroy(int(best.id), "apc_emitter", int(e.owner))


# ================================================================ commands: cn_dome, cn_emp, cn_panels
static func _apcs(w: SimWorld, cmd: Dictionary) -> Array:
	var out := []
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null and e.has("a7") and int(e.owner) == int(cmd.get("issuer", -1)):
			out.append(e)
	return out


static func _dome_ok(w: SimWorld, a: Dictionary) -> bool:
	return not bool(a.get("moving", false)) and w.tick >= int(a.a7.dome_cd) and float(a.a7.dome) > 0.0


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var t := String(cmd.get("type", ""))
	var apcs := _apcs(w, cmd)
	if apcs.is_empty():
		return "Select a counter-nanite APC."
	match t:
		"cn_dome":
			if not bool(cmd.get("on", true)):
				return ""
			for a in apcs:
				if _dome_ok(w, a):
					return ""
			return "The dome needs a stopped APC with charge."
		"cn_emp":
			for a in apcs:
				if w.tick >= int(a.a7.emp_cd):
					return ""
			return "The EMP pulse is recharging."
		"cn_panels":
			var k := String(cmd.get("kind", ""))
			if not PANEL_KINDS.has(k):
				return "Unknown panel kind '%s'." % k
			for a in apcs:
				if int(a.a7.st.get(k, 0)) > 0:
					return ""
			return "Out of %s: restock at the facility." % k
	return "Unknown APC command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var t := String(cmd.get("type", ""))
	for a in _apcs(w, cmd):
		match t:
			"cn_dome":
				var on := bool(cmd.get("on", true))
				if not on or _dome_ok(w, a):
					set_dome(w, a, on)
			"cn_emp":
				if w.tick >= int(a.a7.emp_cd):
					emp_pulse(w, a)
			"cn_panels":
				var k := String(cmd.get("kind", ""))
				if int(a.a7.st.get(k, 0)) > 0:
					fire_panel(w, a, k)


## Short-range EMP: enemy drones go down, enemy machines / electronics hold fire, leeches are knocked off.
## Unhackable units (CN APCs, sentries) are immune.
static func emp_pulse(w: SimWorld, a: Dictionary) -> void:
	var c: Dictionary = cfg_of(String(a.def)).get("emp", {})
	var r := float(c.get("radius", 3.5))
	var dur := int(c.get("ticks", 140))
	a.a7.emp_cd = w.tick + ticks(float(c.get("cooldown_s", 40)))
	var n := 0
	var downed := 0
	for u in near(w, a.pos, r):
		if not w.entities.has(int(u.id)) or not w.is_enemy(int(a.owner), int(u.owner)) or unhackable(u):
			continue
		var ud := Content.unit(String(u.def))
		if bool(ud.get("launched_drone", false)) or SimWorld.Counterdrone.is_drone(w, u):
			w.destroy(int(u.id), "emp", int(a.owner))
			downed += 1
		elif bool(ud.get("energy", false)) or u.has("comp") or String(ud.get("faction", "")) == "machine":
			_disable(w, u, dur)
			n += 1
	var leeches := int(callf(SimWorld.Creep, "detach_leeches", [w, int(a.id)], 0))
	w.emit("ApcEmp", {"id": int(a.id), "owner": int(a.owner), "pos": a.pos, "disabled": n, "drones_downed": downed,
		"leeches": leeches, "until": w.tick + dur})


## Side panels: interceptors (APS window + nearest enemy drones down), smoke, interceptor drones. Limited stock.
static func fire_panel(w: SimWorld, a: Dictionary, k: String) -> void:
	a.a7.st[k] = int(a.a7.st.get(k, 0)) - 1
	var extra := {}
	match k:
		"interceptors":
			a.a7.icpt_until = w.tick + ticks(5.0)
			var killed := 0
			for u in near(w, a.pos, 8.0):
				if killed >= 2:
					break
				if w.entities.has(int(u.id)) and w.is_enemy(int(a.owner), int(u.owner)) and SimWorld.Counterdrone.is_drone(w, u):
					w.destroy(int(u.id), "interceptor", int(a.owner))
					killed += 1
			extra.killed = killed
		"smoke":
			a.a7.smoke_until = w.tick + ticks(12.0)
		"idrones":
			var st := _st(w)
			var ids := []
			for i in 2:
				var off := Vector2(-1.0 if i == 0 else 1.0, -1.0)
				var did := w.spawn_unit("g7_cn_interceptor_drone", int(a.owner), Vector2(a.pos) + off)
				st.drones[did] = w.tick + ticks(float(Content.unit("g7_cn_interceptor_drone").get("cn_life_s", 45)))
				ids.append(did)
			extra.drones = ids
	var ev := {"id": int(a.id), "owner": int(a.owner), "kind": k, "left": int(a.a7.st[k]), "pos": a.pos}
	ev.merge(extra)
	w.emit("ApcPanel", ev)
