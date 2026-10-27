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
##  - pop-out 6-tube micro rocket launcher (owner amendment 2026-10-26; strike and tactical APCs, top rear right
##    behind the gunner pod): canisters tandem / emp / thermite / he_frag / disruptor / smoke (rules.g7_cn.launcher,
##    chosen with the mission loadout, refilled by restock). Pops up (pop_s), fires salvos, reloads the tubes from
##    the rack, stows when no target is left. Auto-fires at heavy Machine units in range unless a CounterNanite
##    engagement (pincer) drives it (rl.eng). Render: g7v[id].rl 0 stowed / 1 popping / 2 popped / 3 firing.
##  - heavy walkers (is_heavy_walker): hit_heavy applies front armour, the pincer bonus (flank / rear hits while
##    another of our units fixes it frontally), stun / mark windows and the topple: stagger from flank / rear leg
##    hits -> topple (fall, down, rise: cannot move or fire, x down_mult damage) -> rights itself, stagger reset.
##    Render: g7v[id].topple ("stagger" | "fall" | "down" | "rise"), topple_dir (radians), stagger (0..1).
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
		"st": (c.get("panels", {}) as Dictionary).duplicate(), "mg": {}, "hp_last": float(e.hp), "pk": [],
		"rl": _rl_new(L().get("default_load", {}))}
	e.unhackable = true


## Refill panel stock and APS charges (CNFAC7's facility workshop calls this).
static func restock(w: SimWorld, e: Dictionary) -> void:
	if not e.has("a7"):
		return
	var c := cfg_of(String(e.def))
	e.a7.st = (c.get("panels", {}) as Dictionary).duplicate()
	e.a7.aps = int(c.get("aps", {}).get("charges", 0))
	if e.a7.has("rl"):   # launcher: the chosen canister loadout, tubes full
		var ld: Dictionary = e.a7.rl.load
		e.a7.rl = _rl_new(ld)
	if e.has("cargo"):   # limpets carried by the soldiers aboard (CounterNanite ops_engage.limpet.carry)
		for u in e.cargo:
			u.erase("lim_n")
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
static func damage_mult(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	var st = w.sys_state.get("apc7")
	if st == null or String(t.get("kind", "")) != "unit":
		return 1.0
	if is_heavy_walker(t) and is_cn_unit(src):   # rifles / .50s / harpoon guns barely scratch a heavy walker
		var H := HV()
		return float(H.get("direct_mult", 0.3)) * agility_hit(t) * (float(H.get("front_mult", 0.35)) if Dmg().hit_side(src.pos, t) == "front" else 1.0)
	if (st.domes as Array).is_empty():
		return 1.0
	var a = dome_over(w, int(t.owner), Vector2(t.pos))
	if a == null:
		return 1.0
	var hv := float(HV().get("dome_mult", 1.0)) if is_heavy_walker(_src_unit(src)) else 1.0   # a walker slug hammers the dome
	absorb(w, a, float(s.get("dmg", s.get("damage", 10.0))) * hv)
	return 0.0


static func _src_unit(src) -> Variant:
	return src if typeof(src) == TYPE_DICTIONARY else null


## A counter-nanite APC or soldier (direct fire through Combat, not the launcher / kit path).
static func is_cn_unit(u: Dictionary) -> bool:
	if u.has("a7"):
		return true
	var dd := String(u.get("def", ""))
	return dd != "" and Content.unit(dd).has("cn_role")


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
	# a heavy walker's rail / core-cannon slug is too fast for the APS (the dome and the armour have to take it)
	if t.has("a7") and not is_heavy_walker(src) and _aps_try(w, t, String(s.get("cls", "")), heavy, int(src.get("owner", -1))):
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


## Units within r of p, ascending id. Always an exact scan: Combat's neighbour-grid cache can differ right after a
## load (THREAT7 finding), and this runs only while CN APCs exist (a few calls per think).
static func near(w: SimWorld, p: Vector2, r: float) -> Array:
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


## EMP / jam: holds fire for dur ticks. A heavy walker shakes it off: emp_scale of the time, then emp_immune_s
## before the next stun takes (EMP rockets, grenades and pulses cannot chain-lock it).
static func _disable(w: SimWorld, t: Dictionary, dur: int) -> void:
	if is_heavy_walker(t):
		if w.tick < int(t.get("emp_imm", -1)):
			return
		var H := HV()
		dur = maxi(roundi(float(dur) * float(H.get("emp_scale", 1.0))), 1)
		t.emp_imm = w.tick + dur + ticks(float(H.get("emp_immune_s", 0.0)))
	t.emp_until = w.tick + dur
	t.jammed_until = maxi(int(t.get("jammed_until", -1)), w.tick + dur)
	SimWorld.HotState.set_cd(w, int(t.id), maxi(int(t.get("cd_ticks", 0)), dur))   # e.cd_ticks: the hot array can lag


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
	if st.has("fx") and not (st.fx as Array).is_empty() and w.tick % 5 == 0:
		_tick_fx(w, st)
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
	if (w.tick + id) % int(L().get("think", 5)) == 0:
		_tick_launcher(w, e)


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
	if manned == 0 and int(e.get("cd_ticks", 0)) < 2:   # e.cd_ticks, not the hot array (it can lag: save round-trip)
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
			var wrecked := true
			for a in apcs:
				if panels_ok(a):
					wrecked = false
					if int(a.a7.st.get(k, 0)) > 0:
						return ""
			return "Side panels wrecked." if wrecked else "Out of %s: restock at the facility." % k
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
## Side panels work while at least one of them is intact (THREAT7 leeches wreck panel_l / panel_r).
static func panels_ok(a: Dictionary) -> bool:
	return bool(callf(SimWorld.Threats7, "part_ok", [a, "panel_l"], true)) or bool(callf(SimWorld.Threats7, "part_ok", [a, "panel_r"], true))


static func fire_panel(w: SimWorld, a: Dictionary, k: String) -> void:
	if not panels_ok(a):
		return
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


# ================================================================ pop-out micro rocket launcher (owner amendment 2026-10-26)
static var _dmg: Script = null
static var _hw := {}


## damage.gd loaded at runtime (damage.gd -> g6_hooks.gd -> this file: a preload here would be a cycle).
static func Dmg() -> Script:
	if _dmg == null:
		_dmg = load("res://sim/systems/damage.gd")
	return _dmg


static func L() -> Dictionary:
	return R().get("launcher", {})


static func HV() -> Dictionary:
	return R().get("heavy", {})


static func TP() -> Dictionary:
	return R().get("topple", {})


static func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


## A canister loadout {kind: count} clipped to the launcher capacity (rules-table kind order).
static func clamp_load(load: Dictionary) -> Dictionary:
	var cap := int(L().get("capacity", 18))
	var out := {}
	var used := 0
	for k in (L().get("kinds", {}) as Dictionary):
		var n := clampi(int(load.get(k, 0)), 0, cap - used)
		if n > 0:
			out[k] = n
			used += n
	return out


static func _rl_new(load: Dictionary) -> Dictionary:
	var ld := clamp_load(load)
	return {"st": 0, "t": 0, "tube": mini(int(L().get("tubes", 6)), _sum(ld)), "rk": ld.duplicate(), "load": ld, "cd": 0,
		"rel": -1, "tgt": -1, "seen": -100000, "eng": -1, "fire_until": -1, "k": ""}


## Mission loadout (CounterNanite cn_set_loadout at the facility): new canister mix, tubes and rack full.
static func set_rockets(w: SimWorld, e: Dictionary, load: Dictionary) -> void:
	if not e.has("a7"):
		return
	e.a7.rl = _rl_new(load)
	_rl_render(w, e)


## Rounds that can hurt a walker (everything but smoke).
static func attack_rounds_left(e) -> int:
	return rockets_left(e) - (int(e.a7.rl.rk.get("smoke", 0)) if rockets_left(e) > 0 else 0)


static func rockets_left(e) -> int:
	return _sum(e.a7.rl.rk) if typeof(e) == TYPE_DICTIONARY and e.has("a7") and e.a7.has("rl") else 0


## Heavy Machine walker: def flag heavy_walker, rules heavy.defs, or a heavy-armoured walking Machine unit.
static func is_heavy_walker(u) -> bool:
	if typeof(u) != TYPE_DICTIONARY or String(u.get("kind", "")) != "unit":
		return false
	var dd := String(u.def)
	if _hw.has(dd):
		return bool(_hw[dd])
	var d := Content.unit(dd)
	var H := HV()
	var v := bool(d.get("heavy_walker", false)) or (H.get("defs", []) as Array).has(dd) \
		or (String(d.get("faction", "")) == "machine" and String(d.get("armor", "")) == "heavy" \
			and (H.get("walk_classes", []) as Array).has(String(d.get("move_class", ""))) \
			and float(d.get("hp", 0)) >= float(H.get("min_hp", 900)))
	_hw[dd] = v
	return v


## Hit factor for a heavy walker's stride (rules heavy.agility_*, PROVISIONAL): micro rockets and direct fire land
## less often on a fast-striding walker than on a lumbering colossus. (speed_ref / def speed) ^ exp, floored; 1.0 at
## or below speed_ref, for anything that is not a heavy walker, and while it lies toppled (a sitting target).
static func agility_hit(t) -> float:
	if not is_heavy_walker(t) or is_down(t):
		return 1.0
	var H := HV()
	var ref := float(H.get("agility_speed_ref", 0.0))
	var sp := float(Content.unit(String(t.def)).get("speed", 0.0))
	if ref <= 0.0 or sp <= ref:
		return 1.0
	return maxf(pow(ref / sp, float(H.get("agility_exp", 0.5))), float(H.get("agility_min", 0.5)))


## Launcher auto targets: heavy-armoured Machine units.
static func is_heavy_target(u) -> bool:
	if not (typeof(u) == TYPE_DICTIONARY and String(u.get("kind", "")) == "unit"):
		return false
	var d := Content.unit(String(u.def))
	return String(d.get("faction", "")) == "machine" and String(d.get("armor", "")) == "heavy"


static func auto_target(w: SimWorld, e: Dictionary, r: float):
	var best = null
	var bd := INF
	for u in near(w, e.pos, r):
		if not w.is_enemy(int(e.owner), int(u.owner)) or not is_heavy_target(u):
			continue
		var d := Vector2(u.pos).distance_to(e.pos)
		if d < bd and d >= float(L().get("min_range", 1.5)):
			bd = d
			best = u
	return best


static func _tick_launcher(w: SimWorld, e: Dictionary) -> void:
	var a: Dictionary = e.a7
	if not a.has("rl"):
		a.rl = _rl_new(L().get("default_load", {}))
	var rl: Dictionary = a.rl
	var C := L()
	var rng := float(C.get("range", 9.0))
	var total := _sum(rl.rk)
	if int(rl.tube) <= 0 and int(rl.rel) < 0 and total > 0:
		rl.rel = w.tick + ticks(float(C.get("reload_s", 15)))
	if int(rl.rel) >= 0 and w.tick >= int(rl.rel):
		rl.tube = mini(int(C.get("tubes", 6)), total)
		rl.rel = -1
		w.emit("ApcLauncher", {"id": int(e.id), "owner": int(e.owner), "state": "reloaded", "tube": int(rl.tube)})
	var tgt = null
	if int(rl.eng) >= 0:   # a CounterNanite engagement picks the target and the volley timing
		tgt = w.entities.get(int(rl.tgt)) if int(rl.tgt) >= 0 else null
		if tgt != null and Vector2(tgt.pos).distance_to(e.pos) > rng + 3.0:
			tgt = null
	else:
		tgt = auto_target(w, e, rng)
		rl.tgt = int(tgt.id) if tgt != null else -1
	if tgt != null:
		rl.seen = w.tick
	var st0 := int(rl.st)
	match st0:
		0:
			if tgt != null and total > 0:
				rl.st = 1
				rl.t = w.tick + ticks(float(C.get("pop_s", 1.5)))
		1:
			if w.tick >= int(rl.t):
				rl.st = 2
		2:
			if w.tick - int(rl.seen) >= ticks(float(C.get("stow_s", 6))) or total <= 0:
				rl.st = 0
	if int(rl.st) != st0:
		w.emit("ApcLauncher", {"id": int(e.id), "owner": int(e.owner), "state": ["stowed", "popping", "popped"][int(rl.st)],
			"tube": int(rl.tube), "left": total})
		_rl_render(w, e)
	if int(rl.eng) < 0 and tgt != null and int(rl.st) == 2:
		var pref := ["tandem", "thermite", "disruptor"]
		if int(tgt.get("emp_until", -1)) < w.tick and not is_down(tgt):
			pref.push_front("emp")   # open a stun window first
		fire_salvo(w, e, tgt, pref)
	if int(rl.fire_until) >= 0 and w.tick >= int(rl.fire_until):
		rl.fire_until = -1
		_rl_render(w, e)


## true when the launcher is up, loaded, off cooldown and tgt is in range.
static func can_fire(w: SimWorld, e: Dictionary, tgt) -> bool:
	if tgt == null or not e.has("a7") or not e.a7.has("rl"):
		return false
	var rl: Dictionary = e.a7.rl
	var d := Vector2(tgt.pos).distance_to(e.pos)
	return int(rl.st) == 2 and w.tick >= int(rl.cd) and int(rl.tube) > 0 \
		and d <= float(L().get("range", 9.0)) and d >= float(L().get("min_range", 1.5))


static func _pick_kind(rl: Dictionary, pref: Array) -> String:
	for k in pref + ["tandem", "thermite", "disruptor", "emp", "he_frag"]:
		if int(rl.rk.get(k, 0)) > 0:
			return String(k)
	return ""


## One salvo (rules launcher.salvo rounds, canister by preference). Returns the rounds fired.
static func fire_salvo(w: SimWorld, e: Dictionary, tgt: Dictionary, pref: Array) -> int:
	if not can_fire(w, e, tgt):
		return 0
	var rl: Dictionary = e.a7.rl
	var C := L()
	var n := mini(int(C.get("salvo", 2)), int(rl.tube))
	var used := []
	var to: Vector2 = tgt.pos
	for i in n:
		var k := _pick_kind(rl, pref)
		if k == "":
			break
		rl.rk[k] = int(rl.rk[k]) - 1
		if int(rl.rk[k]) <= 0:
			rl.rk.erase(k)
		rl.tube = int(rl.tube) - 1
		used.append(k)
		_round(w, e, tgt, k)
		if not w.entities.has(int(tgt.id)):
			break
	if used.is_empty():
		return 0
	rl.cd = w.tick + ticks(float(C.get("salvo_gap_s", 2.0)))
	rl.fire_until = w.tick + ticks(float(C.get("firing_show_s", 0.6)))
	rl.k = String(used[0])
	w.emit("RocketSalvo", {"id": int(e.id), "owner": int(e.owner), "target": int(tgt.id), "from": e.pos, "to": to,
		"kinds": used, "tube": int(rl.tube), "left": _sum(rl.rk)})
	_rl_render(w, e)
	return used.size()


## One canister on tgt (hit roll w.rng; a downed walker is a sitting target).
static func _round(w: SimWorld, e: Dictionary, tgt: Dictionary, k: String) -> void:
	var K: Dictionary = L().get("kinds", {}).get(k, {})
	if k == "smoke":
		e.a7.smoke_until = maxi(int(e.a7.smoke_until), w.tick + ticks(float(K.get("smoke_s", 12))))
		return
	if not is_down(tgt) and w.rng.randf() >= float(L().get("accuracy", 0.85)) * agility_hit(tgt):
		return
	if k == "he_frag":
		var at: Vector2 = tgt.pos
		var r := float(K.get("radius", 2.0))
		for u in near(w, at, r):
			if w.entities.has(int(u.id)) and w.is_enemy(int(e.owner), int(u.owner)):
				var f := 1.0 - 0.5 * Vector2(u.pos).distance_to(at) / r
				Dmg().apply_hit(w, e, u, {"damage": float(K.get("damage", 30)) * f, "cls": String(K.get("cls", "autocannon")), "weapon": ""}, true)
		return
	hit_heavy(w, e, tgt, float(K.get("damage", 10)), String(K.get("cls", "at")), float(K.get("stagger", 0.0)))
	if not w.entities.has(int(tgt.id)):
		return
	match k:
		"emp":
			if not unhackable(tgt):
				_disable(w, tgt, ticks(float(K.get("stun_s", 3.0))))
		"thermite":
			tgt.cn_burn = {"until": w.tick + ticks(float(K.get("burn_s", 6))), "dps": float(K.get("burn_dps", 5)), "by": int(e.owner)}
			_fx_add(w, tgt)
		"disruptor":
			mark(w, tgt, float(K.get("mark_s", 10)), float(K.get("sensors", 30)))


## Nanite-disruptor on the sensor eyes: sensors component down, marked (x mark_mult damage taken) for mark_s.
static func mark(w: SimWorld, t: Dictionary, sec: float, sensors: float) -> void:
	t.cn_mark = w.tick + ticks(sec)
	if t.has("comp"):
		var fl := float(HV().get("sensors_floor", 0.0)) if is_heavy_walker(t) else 0.0   # it keeps some of its eyes
		t.comp.sensors = maxf(float(t.comp.get("sensors", 100)) - sensors, minf(fl, float(t.comp.get("sensors", 100))))
	_fx_add(w, t)


static func _g7v(w: SimWorld, id: int) -> Dictionary:
	var v = w.sys_state.get("g7v")
	if v == null:
		v = {}
		w.sys_state["g7v"] = v
	if not v.has(id):
		v[id] = {}
	return v[id]


## LOOK7 / ARTCN7 render keys of a CN APC: rl 0 stowed, 1 popping, 2 popped, 3 firing; rl_n rounds in the tubes;
## rl_k last canister fired.
static func _rl_render(w: SimWorld, e: Dictionary) -> void:
	var rl: Dictionary = e.a7.rl
	var g := _g7v(w, int(e.id))
	g.rl = 3 if int(rl.fire_until) >= w.tick else int(rl.st)
	g.rl_n = int(rl.tube)
	g.rl_k = String(rl.k)


# ================================================================ heavy walkers: pincer bonus, stun / mark windows, topple
## Fixed frontally: the walker is busy with ANOTHER unit of src's side (its combat target, or a unit of ours closer
## to it than src standing in its front arc, within heavy.fix_range).
static func fixed_by(w: SimWorld, t: Dictionary, src: Dictionary) -> bool:
	var fr := float(HV().get("fix_range", 7.0))
	var sid := int(src.get("id", -1))
	var tg := int(t.get("target", -1))
	if tg >= 0 and tg != sid:
		var u = w.entities.get(tg)
		if u != null and int(u.owner) == int(src.owner) and Vector2(u.pos).distance_to(t.pos) <= fr:
			return true
	var ds := minf(Vector2(src.pos).distance_to(t.pos), fr)
	for u in near(w, t.pos, ds):
		if int(u.id) != sid and int(u.owner) == int(src.owner) and Dmg().hit_side(u.pos, t) == "front":
			return true
	return false


## Every CN hit on a heavy Machine unit goes through here (launcher canisters, limpets, harpoons, disruptor rounds).
## Damage pipeline (armour table, facing) via Damage.apply_hit, plus: heavy-walker front armour (front_mult, almost
## no stagger), the pincer bonus on flank / rear hits while it is fixed frontally, stun (EMP) and mark (disruptor)
## windows, x down_mult while it lies toppled. Then the stagger build-up (topple).
static func hit_heavy(w: SimWorld, src: Dictionary, t: Dictionary, dmg: float, cls: String, stagger: float) -> void:
	var H := HV()
	var T := TP()
	var mult := 1.0
	var sg := stagger
	if is_heavy_walker(t):
		var side: String = Dmg().hit_side(src.pos, t) if t.has("comp") else "front"
		if side == "front":
			mult *= float(H.get("front_mult", 0.5))
			sg *= float(T.get("front_gain", 0.1))
		elif fixed_by(w, t, src):
			mult *= float(H.get("rear_fixed_mult" if side == "rear" else "flank_fixed_mult", 1.5))
			sg *= float(T.get("rear_gain" if side == "rear" else "side_gain", 1.0))
		else:
			sg *= float(T.get("unfixed_gain", 0.35))
		if int(t.get("emp_until", -1)) >= w.tick:
			mult *= float(H.get("stun_mult", 1.25))
			sg *= float(T.get("stun_gain", 1.5))
	else:
		sg = 0.0
	if int(t.get("cn_mark", -1)) >= w.tick:
		mult *= float(L().get("kinds", {}).get("disruptor", {}).get("mark_mult", 1.2))
	if is_down(t):
		mult *= float(H.get("down_mult", 2.5))
		sg = 0.0
	Dmg().apply_hit(w, src, t, {"damage": dmg * mult, "cls": cls, "weapon": ""}, true)
	if sg > 0.0 and w.entities.has(int(t.id)):
		add_stagger(w, t, sg, Vector2(src.pos))


static func topple_phase(t) -> String:
	if typeof(t) != TYPE_DICTIONARY or not t.has("tpl"):
		return ""
	return String(t.tpl.ph)


## Lying on the ground (fall / down): cannot move or fire, every hit x down_mult.
static func is_down(t) -> bool:
	var p := topple_phase(t)
	return p == "fall" or p == "down"


static func topple_threshold(t: Dictionary) -> float:
	var T := TP()
	var hp := float(Content.unit(String(t.def)).get("hp", 950))
	return minf(float(T.get("threshold", 8.0)) * sqrt(maxf(hp, 1.0) / float(T.get("threshold_hp_ref", 950))),
		float(T.get("threshold_max", 18.0)))


## Seconds a toppled walker lies down: topple.down_s x (hp / threshold_hp_ref) ^ down_exp, at most down_s_max
## (a heavier machine takes longer to right itself; PROVISIONAL).
static func down_secs(t: Dictionary) -> float:
	var T := TP()
	var base := float(T.get("down_s", 8.0))
	var ex := float(T.get("down_exp", 0.0))
	if ex <= 0.0:
		return base
	var hp := float(Content.unit(String(t.def)).get("hp", 950))
	return minf(base * pow(maxf(hp, 1.0) / float(T.get("threshold_hp_ref", 950)), ex), float(T.get("down_s_max", base)))


static func _fx_add(w: SimWorld, t: Dictionary) -> void:
	var st := _st(w)
	if not st.has("fx"):
		st.fx = []
	if not (st.fx as Array).has(int(t.id)):
		st.fx.append(int(t.id))
		st.fx.sort()


static func _tpl(w: SimWorld, t: Dictionary) -> Dictionary:
	if not t.has("tpl"):
		t.tpl = {"sg": 0.0, "ph": "", "until": 0, "imm": 0, "px": 0.0, "py": 0.0, "last": w.tick, "mob": -1.0, "dir": 0.0}
	_fx_add(w, t)
	return t.tpl


## Stagger from a hit at `from` (the push direction decides which way it falls).
static func add_stagger(w: SimWorld, t: Dictionary, sg: float, from: Vector2) -> void:
	if sg <= 0.0 or not is_heavy_walker(t):
		return
	var tp := _tpl(w, t)
	if String(tp.ph) != "" or w.tick < int(tp.imm):
		return
	tp.sg = snappedf(float(tp.sg) + sg, 0.001)
	var v := Vector2(t.pos) - from
	if v.length_squared() > 1e-6:
		v = v.normalized() * sg
		tp.px = snappedf(float(tp.px) + v.x, 0.001)
		tp.py = snappedf(float(tp.py) + v.y, 0.001)
	tp.last = w.tick
	if float(tp.sg) >= topple_threshold(t):
		topple(w, t)
	else:
		_tpl_render(w, t)


## Knocked down: fall (fall_s) -> down (down_s) -> rise (rise_s); no movement (mobility 0) and no fire (cooldown)
## for the whole window; then it rights itself with the stagger reset and a short immunity.
static func topple(w: SimWorld, t: Dictionary) -> void:
	var tp := _tpl(w, t)
	var T := TP()
	tp.ph = "fall"
	tp.until = w.tick + ticks(float(T.get("fall_s", 1.0)))
	var push := Vector2(float(tp.px), float(tp.py))
	tp.dir = snappedf(push.angle() if push.length() > 0.001 else float(t.get("facing", 0.0)) + PI, 0.01)
	if t.has("comp") and float(tp.mob) < 0.0:
		tp.mob = float(t.comp.get("mobility", 100))
	_pin(w, t, ticks(float(T.get("fall_s", 1.0)) + down_secs(t) + float(T.get("rise_s", 2.0))))
	w.emit("WalkerToppled", {"id": int(t.id), "owner": int(t.owner), "def": String(t.def), "pos": t.pos, "dir": float(tp.dir)})
	_tpl_render(w, t)


static func _pin(w: SimWorld, t: Dictionary, dur: int) -> void:
	if t.has("comp"):
		t.comp.mobility = 0.0
	SimWorld.Movement.stop_path(t)
	SimWorld.HotState.set_cd(w, int(t.id), maxi(int(t.get("cd_ticks", 0)), dur))   # e.cd_ticks: the hot array can lag


static func _tick_tpl(w: SimWorld, t: Dictionary, dt: float) -> bool:
	var tp: Dictionary = t.tpl
	var T := TP()
	var ph := String(tp.ph)
	if ph == "":
		if w.tick - int(tp.last) >= ticks(float(T.get("decay_after_s", 4.0))):
			tp.sg = snappedf(maxf(float(tp.sg) - float(T.get("decay_per_s", 0.35)) * dt, 0.0), 0.001)
			if float(tp.sg) <= 0.0:
				tp.px = 0.0
				tp.py = 0.0
		if float(tp.sg) <= 0.0 and w.tick >= int(tp.imm):
			t.erase("tpl")
			_tpl_render(w, t)
			return false
		_tpl_render(w, t)
		return true
	if w.tick >= int(tp.until):
		match ph:
			"fall":
				tp.ph = "down"
				tp.until = w.tick + ticks(down_secs(t))
				w.emit("WalkerDown", {"id": int(t.id), "owner": int(t.owner), "pos": t.pos, "dir": float(tp.dir)})
			"down":
				tp.ph = "rise"
				tp.until = w.tick + ticks(float(T.get("rise_s", 2.0)))
			"rise":
				tp.ph = ""
				tp.sg = 0.0
				tp.px = 0.0
				tp.py = 0.0
				tp.imm = w.tick + ticks(float(T.get("immune_s", 6.0)))
				if t.has("comp") and float(tp.mob) >= 0.0:
					t.comp.mobility = float(tp.mob)
				tp.mob = -1.0
				w.emit("WalkerRighted", {"id": int(t.id), "owner": int(t.owner), "pos": t.pos})
	if String(tp.ph) != "":
		_pin(w, t, maxi(int(tp.until) - w.tick, 1) + (ticks(float(T.get("rise_s", 2.0))) if String(tp.ph) != "rise" else 0))
	_tpl_render(w, t)
	return true


## Machine units under a CN effect (burn, mark, harpoon tether, stagger / topple), every 5 ticks.
static func _tick_fx(w: SimWorld, st: Dictionary) -> void:
	var keep := []
	var dt := 5.0 / float(SimWorld.TICK_RATE)
	var v = w.sys_state.get("g7v")
	for id in st.fx:
		var t = w.entities.get(int(id))
		if t == null:
			if v != null and v.has(int(id)):
				var was := String(v[int(id)].get("topple", ""))
				if was == "fall" or was == "down" or was == "rise":
					w.emit("WalkerBlownUp", {"id": int(id), "dir": float(v[int(id)].get("topple_dir", 0.0))})
				v.erase(int(id))
			continue
		var live := false
		if t.has("cn_burn"):
			var b: Dictionary = t.cn_burn
			if w.tick >= int(b.until):
				t.erase("cn_burn")
			else:
				live = true
				var fake := {"id": -1, "kind": "unit", "owner": int(b.by), "pos": t.pos}
				Dmg().apply_hit(w, fake, t, {"damage": float(b.dps) * dt, "cls": "at", "weapon": ""}, true)
				if not w.entities.has(int(id)):
					continue
		if t.has("cn_mark"):
			if w.tick >= int(t.cn_mark):
				t.erase("cn_mark")
			else:
				live = true
		if t.has("cn_harp"):
			var hp: Dictionary = t.cn_harp
			if w.tick >= int(hp.until):
				t.erase("cn_harp")
			else:
				live = true
				var lp := Vector2(float(hp.lx), float(hp.ly))
				var cur: Vector2 = t.pos
				if cur.distance_squared_to(lp) > 1e-6:   # tethered: only part of each step gets through
					var np := lp + (cur - lp) * float(hp.slow)
					SimWorld.HotState.set_pos(w, int(id), np)
					cur = np
				hp.lx = snappedf(cur.x, 0.001)
				hp.ly = snappedf(cur.y, 0.001)
		if t.has("tpl"):
			live = _tick_tpl(w, t, dt) or live
		if live:
			keep.append(int(id))
	st.fx = keep


## Net / harpoon tether: the walker keeps only `slow` of its movement for sec seconds.
static func tether(w: SimWorld, t: Dictionary, slow: float, sec: float) -> void:
	t.cn_harp = {"until": w.tick + ticks(sec), "slow": slow, "lx": snappedf(Vector2(t.pos).x, 0.001), "ly": snappedf(Vector2(t.pos).y, 0.001)}
	_fx_add(w, t)


## g7v[id].topple "stagger" | "fall" | "down" | "rise", topple_dir (radians, the way it falls), stagger 0..1.
static func _tpl_render(w: SimWorld, t: Dictionary) -> void:
	var id := int(t.id)
	if not t.has("tpl"):
		var v = w.sys_state.get("g7v")
		if v != null and v.has(id):
			for k in ["topple", "topple_dir", "stagger"]:
				v[id].erase(k)
			if (v[id] as Dictionary).is_empty():
				v.erase(id)
		return
	var tp: Dictionary = t.tpl
	var g := _g7v(w, id)
	g.topple = String(tp.ph) if String(tp.ph) != "" else "stagger"
	g.topple_dir = float(tp.dir) if String(tp.ph) != "" else snappedf(Vector2(float(tp.px), float(tp.py)).angle(), 0.01)
	g.stagger = snappedf(clampf(float(tp.sg) / topple_threshold(t), 0.0, 1.0), 0.05) if String(tp.ph) == "" else 1.0
