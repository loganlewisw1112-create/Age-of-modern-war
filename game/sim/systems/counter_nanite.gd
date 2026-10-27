extends RefCounted
## G7 (CNSIM7): counter-nanite strike team and tactical operators (master scope 6.3-6.8). Owner: CNSIM7.
## Content: content/g7/defs_g7_cn.json (units with cn_role / cn_line / sealed_suit, APCs with an apc7 block,
## rules.g7_cn). Human A and Human B only. Spawned by CNFAC7's facility through spawn_team (no production entry).
##  - Strike team: 20 soldiers in two squads of 10, each squad INSIDE its strike APC at spawn; one team leader
##    (squad A); when the leader falls, squad A's second-in-command takes over (then squad B's). Operates only as
##    the full pair: deployment needs both strike APCs alive, and a lone move order on one APC is mirrored to the other.
##  - Tactical operator squad: 8 operators inside a tactical APC; at most rules.tac_cap (3) live per side in normal
##    matches (set_tac_cap lifts it for Last Protocol).
##  - Loadout: packages chosen at the facility (cn_set_loadout) within each strike APC's pkg_capacity; locked in
##    the field (rules.loadout_leash from spawn and from every cn_facility building).
##  - Deployment (cn_deploy): scan (scanner technicians, Creep.reveal) -> jam (EW specialists, Creep.jam_link) ->
##    arm (deployment specialists under a raised dome) -> purge (Creep.purge / Cores.core_breaker). A missing role,
##    a dead APC or a down dome stalls it. The medic-engineers place portable barriers and sentry turrets by
##    themselves (threat side first) and pack them up afterwards. Hero detonation (cn_hero_detonate): one operator
##    stays, instant arming, short withdrawal window, certain death, call sign kept in the "Remembered" list.
##  - Suits and exposure: sealed suits (e.suit) take no exposure until punctured (a hit on the soldier ->
##    Wounds.puncture, e.wpunct); ordinary soldiers on foot in creep build exposure (e.cn_exp 0..1), which hurts
##    and slows (e.cn_slow; CR to the mvm owner) until decontaminate (CNFAC7 decon walkway, or near a cn_decon def).
## State: w.sys_state.cn7 (created by the first spawn_team; matches without the line never get it, and the
## exposure pass for ordinary soldiers runs only while CREEP7's creep state exists). Saved and hashed.
## Determinism: ascending ids/team ids, w.rng only, staggered cadence, integer ticks.

const Apc7 = preload("res://sim/systems/apc7.gd")
const VER := 1
const STRIKE_A := ["leader", "second", "deploy", "deploy", "scanner", "ew", "gunner", "gunner", "gunner", "medic"]
const STRIKE_B := ["second", "deploy", "deploy", "scanner", "ew", "gunner", "gunner", "gunner", "gunner", "medic"]
const TACTICAL := ["op_leader", "marksman", "hunter", "hunter", "emp", "antidrone", "purge", "op_medic"]
const ROLE_ART := {"leader": "cn_team_leader", "second": "cn_radio", "deploy": "cn_deploy", "scanner": "cn_scanner",
	"ew": "cn_ew", "gunner": "cn_gunner", "medic": "cn_medic", "op_leader": "op_leader", "marksman": "op_marksman",
	"hunter": "op_hunter", "emp": "op_emp", "antidrone": "op_antidrone", "purge": "op_purge", "op_medic": "op_medic"}


static func R() -> Dictionary:
	return Content.rules().get("g7_cn", {})


static func ticks(sec: float) -> int:
	return maxi(roundi(sec * SimWorld.TICK_RATE), 1)


static func state(w: SimWorld):
	return w.sys_state.get("cn7")


static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get("cn7")
	if st == null:
		st = {"ver": VER, "next_team": 1, "teams": {}, "remembered": [], "tac_cap": {}, "exposed": []}
		w.sys_state["cn7"] = st
	return st


## Def-id prefix of a side ("g7_" Human A, "g7_b_" Human B, "" = not a counter-nanite faction).
static func prefix(w: SimWorld, fid: int) -> String:
	if not w.factions.has(fid):
		return ""
	match String(w.factions[fid].get("faction_def", "")):
		"human_a":
			return "g7_"
		"human_b":
			return "g7_b_"
	return ""


static func role_of(e) -> String:
	return String(Content.unit(String(e.def)).get("cn_role", "")) if typeof(e) == TYPE_DICTIONARY else ""


## A team member's entity dict: on the map or riding in a carrier; null when dead.
static func find(w: SimWorld, id: int):
	var e = w.entities.get(id)
	if e != null:
		return e
	var cid := SimWorld.Transport.carrier_of(w, id)
	if cid < 0:
		return null
	var c = w.entities.get(cid)
	if c == null or not c.has("cargo"):
		return null
	for u in c.cargo:
		if int(u.id) == id:
			return u
	return null


static func alive(w: SimWorld, id: int) -> bool:
	return w.entities.has(id) or SimWorld.Transport.in_cargo(w, id)


static func team(w: SimWorld, tid: int):
	var st = w.sys_state.get("cn7")
	return null if st == null else st.teams.get(tid)


static func team_of(e) -> int:
	return int(e.get("cn_team", -1)) if typeof(e) == TYPE_DICTIONARY else -1


static func team_ids(w: SimWorld) -> Array:
	var st = w.sys_state.get("cn7")
	if st == null:
		return []
	var ks: Array = st.teams.keys()
	ks.sort()
	return ks


static func live_members(w: SimWorld, t: Dictionary) -> Array:
	var out := []
	for id in t.members:
		if alive(w, int(id)):
			out.append(int(id))
	return out


static func live_apcs(w: SimWorld, t: Dictionary) -> Array:
	var out := []
	for id in t.apcs:
		if alive(w, int(id)):
			out.append(int(id))
	return out


# ================================================================ spawning (CNFAC7 calls spawn_team)
## kind strike_team | tactical_squad. APC(s) at pos with their crew already inside. {} when not allowed.
static func spawn_team(w: SimWorld, fid: int, kind: String, pos: Vector2) -> Dictionary:
	var pre := prefix(w, fid)
	if pre == "":
		return {}
	if kind == "tactical_squad" and tac_reason(w, fid) != "":
		return {}
	var st := _st(w)
	var tid := int(st.next_team)
	st.next_team = tid + 1
	var strike := kind == "strike_team"
	var names: Array = R().get("team_names" if strike else "op_names", ["Team"])
	var t := {"id": tid, "kind": "strike" if strike else "tactical", "fid": fid, "name": String(names[(tid - 1) % names.size()]),
		"apcs": [], "squads": {}, "members": [], "leader": -1, "spawn": pos, "locked": false, "dep": null,
		"hold": [], "conv": -1, "xp": 0}
	var plan := [["A", STRIKE_A], ["B", STRIKE_B]] if strike else [["A", TACTICAL]]
	var n := 0
	for sq in plan:
		n += 1
		var apc_def := pre + ("cn_strike_apc" if strike else "op_tactical_apc")
		var at := pos + Vector2(0.0, 2.5 * float(n - 1))
		var aid := w.spawn_unit(apc_def, fid, at)
		var a: Dictionary = w.entities[aid]
		a.cn_team = tid
		a.cn_sq = String(sq[0])
		Apc7.init_apc(w, a)
		t.apcs.append(aid)
		var ids := []
		var k := 0
		for role in sq[1]:
			k += 1
			var sid := w.spawn_unit(pre + String(ROLE_ART[role]), fid, at)
			var s: Dictionary = w.entities[sid]
			s.cn_team = tid
			s.cn_sq = String(sq[0])
			s.suit = true
			s.call_sign = "%s %d-%d" % [t.name, n, k]
			ids.append(sid)
			if role == "leader" or (not strike and role == "op_leader"):
				t.leader = sid
				s.cn_lead = true
			board_now(w, a, s)
		t.squads[String(sq[0])] = ids
		t.members.append_array(ids)
	st.teams[tid] = t
	if strike:
		var dl: Array = R().get("default_loadout", [])
		_split(w, t, dl + dl)   # the default kit for each APC, interleaved
	w.emit("CnTeamSpawned", {"team": tid, "kind": t.kind, "owner": fid, "name": t.name, "apcs": t.apcs.duplicate(),
		"members": t.members.size(), "pos": pos})
	return {"team": tid, "apcs": t.apcs.duplicate(), "members": t.members.duplicate()}


## Puts a map soldier inside carrier c now (same bookkeeping as Transport loading).
static func board_now(w: SimWorld, c: Dictionary, u: Dictionary) -> void:
	SimWorld.Movement.stop_path(u)
	u.order = {"type": "idle"}
	u.target = -1
	w.entities.erase(int(u.id))
	if not c.has("cargo"):
		c.cargo = []
	var cargo: Array = c.cargo
	var at := cargo.size()
	for i in cargo.size():
		if int(cargo[i].id) > int(u.id):
			at = i
			break
	cargo.insert(at, u)
	for key in ["transport", "cargo_of", "sim_index", "unit_subsets"]:
		w.cache.erase(key)
	w.emit("UnitLoaded", {"id": int(u.id), "carrier": int(c.id), "owner": int(u.owner)})


## Live tactical squads of side fid vs the cap ("" = another may deploy).
static func tac_reason(w: SimWorld, fid: int) -> String:
	var cap := tac_cap(w, fid)
	if cap < 0:
		return ""
	var n := 0
	for tid in team_ids(w):
		var t: Dictionary = w.sys_state.cn7.teams[tid]
		if int(t.fid) == fid and String(t.kind) == "tactical" and not live_members(w, t).is_empty():
			n += 1
	return "" if n < cap else "At most %d tactical squads may be deployed." % cap


static func tac_cap(w: SimWorld, fid: int) -> int:
	var st = w.sys_state.get("cn7")
	if st != null and (st.tac_cap as Dictionary).has(fid):
		return int(st.tac_cap[fid])
	return int(w.cfg.get("cn_tac_cap", R().get("tac_cap", 3)))


## Last Protocol hook: lift (n < 0 = unlimited) or change the tactical squad cap of a side.
static func set_tac_cap(w: SimWorld, fid: int, n: int) -> void:
	_st(w).tac_cap[fid] = n


# ================================================================ loadout (facility only)
static func pkg_size(kind: String) -> int:
	return int((R().get("packages", {}) as Dictionary).get(kind, {}).get("size", 1))


static func _fill(w: SimWorld, a: Dictionary, kinds: Array) -> Array:
	var cap := int(Apc7.cfg_of(String(a.def)).get("pkg_capacity", 0))
	var used := 0
	var pk := []
	var rest := []
	for k in kinds:
		if used + pkg_size(String(k)) <= cap:
			pk.append(String(k))
			used += pkg_size(String(k))
		else:
			rest.append(k)
	a.a7.pk = pk
	return rest


## Split loadout: each package goes to the APC holding the fewest of its kind (then the least loaded, then A), so
## losing one strike APC never loses every package of a kind. Returns what did not fit.
static func _split(w: SimWorld, t: Dictionary, kinds: Array) -> Array:
	var apcs := []
	for aid in t.apcs:
		var a = find(w, int(aid))
		if a != null:
			a.a7.pk = []
			apcs.append(a)
	var rest := []
	for k in kinds:
		var best = null
		var bk := 1 << 30
		for a in apcs:
			var used := 0
			var same := 0
			for p in a.a7.pk:
				used += pkg_size(String(p))
				same += 1 if String(p) == String(k) else 0
			if used + pkg_size(String(k)) > int(Apc7.cfg_of(String(a.def)).get("pkg_capacity", 0)):
				continue
			var score := same * 1000 + used
			if score < bk:
				bk = score
				best = a
		if best == null:
			rest.append(k)
		else:
			best.a7.pk.append(String(k))
	return rest


static func loadout(w: SimWorld, tid: int) -> Dictionary:
	var out := {}
	var t = team(w, tid)
	if t == null:
		return out
	for aid in t.apcs:
		var a = find(w, int(aid))
		if a != null:
			out[int(aid)] = (a.a7.pk as Array).duplicate()
	return out


static func unlock_loadout(w: SimWorld, tid: int) -> void:
	var t = team(w, tid)
	if t != null and bool(t.locked):
		t.locked = false
		w.emit("CnLoadoutUnlocked", {"team": tid, "owner": int(t.fid)})


## Any own building flagged cn_facility (or listed in rules.facility_defs) within r of pos.
static func near_facility(w: SimWorld, fid: int, pos: Vector2, r: float) -> bool:
	var defs: Array = R().get("facility_defs", [])
	for b in w.buildings_of(fid):
		if (defs.has(String(b.def)) or bool(Content.building(String(b.def)).get("cn_facility", false))) \
				and Vector2(b.pos).distance_to(pos) <= r:
			return true
	return false


## Clears exposure and repairs a punctured suit (CNFAC7's decon walkway; APCs clean their whole crew).
static func decontaminate(w: SimWorld, e: Dictionary) -> void:
	var had := float(e.get("cn_exp", 0.0)) > 0.0 or bool(e.get("wpunct", false))
	e.erase("cn_exp")
	e.erase("cn_slow")
	e.erase("wpunct")
	if e.has("cargo"):
		for u in e.cargo:
			decontaminate(w, u)
	_render(w, e)
	if had:
		w.emit("CnDecontaminated", {"id": int(e.id), "owner": int(e.owner)})


## LOOK7 render fields (w.sys_state.g7v[id]): sb suit breached, ex exposure (0..1, 0.05 steps). Own keys only.
static func _render(w: SimWorld, e: Dictionary) -> void:
	var v = w.sys_state.get("g7v")
	var id := int(e.id)
	var sb := bool(e.get("wpunct", false)) and bool(e.get("suit", false))
	var ex := snappedf(float(e.get("cn_exp", 0.0)), 0.05)
	if not sb and ex <= 0.0:
		if v != null and v.has(id):
			v[id].erase("sb")
			v[id].erase("ex")
			if (v[id] as Dictionary).is_empty():
				v.erase(id)
		return
	if v == null:
		v = {}
		w.sys_state["g7v"] = v
	if not v.has(id):
		v[id] = {}
	if sb:
		v[id].sb = true
	else:
		v[id].erase("sb")
	v[id].ex = ex


# ================================================================ deployment, site hold, hero detonation
static func on_foot_near(w: SimWorld, t: Dictionary, role: String, site: Vector2, r: float) -> Array:
	var out := []
	for id in t.members:
		var e = w.entities.get(int(id))
		if e != null and (role == "" or role_of(e) == role) and Vector2(e.pos).distance_to(site) <= r:
			out.append(int(id))
	return out


static func pair_ok(w: SimWorld, t: Dictionary) -> bool:
	return String(t.kind) != "strike" or live_apcs(w, t).size() == 2


static func pkg_apc(w: SimWorld, t: Dictionary, kind: String):
	for aid in t.apcs:
		var a = find(w, int(aid))
		if a != null and a.has("a7") and (a.a7.pk as Array).has(kind):
			return a
	return null


static func deploy_reason(w: SimWorld, t: Dictionary, site: Vector2, kind: String) -> String:
	if String(t.kind) != "strike":
		return "Only the strike team deploys packages."
	if not pair_ok(w, t):
		return "The strike team operates only as the full pair."
	if t.dep != null:
		return "The team is already deploying."
	if not (R().get("packages", {}) as Dictionary).has(kind):
		return "Unknown package '%s'." % kind
	if pkg_apc(w, t, kind) == null:
		return "No %s package in this team's loadout." % kind
	var r := float(R().get("deploy", {}).get("site_radius", 7.0))
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null and Vector2(a.pos).distance_to(site) <= r:
			return ""
	return "Move the strike APCs to the site first."


## Unit vector from the site towards the nearest enemy mass within 16 tiles (else along the approach from spawn).
static func _threat_dir(w: SimWorld, t: Dictionary, site: Vector2) -> Vector2:
	var dir := Vector2.ZERO
	for u in Apc7.near(w, site, 16.0):
		if w.is_enemy(int(t.fid), int(u.owner)):
			dir += Vector2(u.pos) - site
	if dir.length() < 0.01:
		dir = site - Vector2(t.spawn)
	return Vector2.RIGHT if dir.length() < 0.01 else dir.normalized()


static func _post(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 1.0, float(w.map.w) - 2.0), clampf(p.y, 1.0, float(w.map.h) - 2.0))


## Deployment drill, vehicles: the motorcade breaks up at the site; the two strike APCs bracket the site across the
## threat axis (their domes overlap the arming point), the escorting tactical APCs take overwatch on the threat side
## and the flanks.
static func _deploy_posts(w: SimWorld, t: Dictionary, site: Vector2) -> void:
	var cid := int(t.conv)
	if cid >= 0:
		Apc7.callf(SimWorld.Convoy, "disband", [w, cid], null)
		t.conv = -1
	var dir := _threat_dir(w, t, site)
	var side := dir.orthogonal()
	var k := 0
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null:
			SimWorld.Movement.order_move(w, a, _post(w, site + side * (2.2 if k == 0 else -2.2) - dir * 0.8))
		k += 1
	var j := 0
	for tt in _teams(w, int(t.fid), t.get("esc", [])):
		for aid in tt.apcs:
			var a = w.entities.get(int(aid))
			if a == null:
				continue
			var ang: float = [0.0, 70.0, -70.0, 140.0, -140.0][j % 5]
			SimWorld.Movement.order_move(w, a, _post(w, site + dir.rotated(deg_to_rad(ang)) * 7.5))
			j += 1


## Deployment drill, on foot: scanner technicians, EW specialists and deployment specialists go to the arming point
## under the dome; the leader, radio man and medic-engineers just behind it; the security gunners spread into a
## perimeter ring (an arc of 250 degrees centred on the threat). System moves carry order.sq = "cn".
static func _take_posts(w: SimWorld, t: Dictionary, site: Vector2) -> void:
	var dir := _threat_dir(w, t, site)
	var inner := []
	var guns := []
	var back := []
	for id in t.members:
		var u = w.entities.get(int(id))
		if u == null or bool(u.get("cn_hero", false)):
			continue
		match role_of(u):
			"scanner", "ew", "deploy":
				inner.append(u)
			"gunner":
				guns.append(u)
			_:
				back.append(u)
	for i in inner.size():
		var p := site + Vector2.RIGHT.rotated(TAU * float(i) / float(maxi(inner.size(), 1))) * (0.9 + 0.5 * float(i % 2))
		SimWorld.Movement.order_move(w, inner[i], _post(w, p))
		inner[i].order.sq = "cn"
	for i in guns.size():
		var f := (float(i) + 0.5) / float(maxi(guns.size(), 1)) - 0.5
		SimWorld.Movement.order_move(w, guns[i], _post(w, site + dir.rotated(f * deg_to_rad(250.0)) * 5.2))
		guns[i].order.sq = "cn"
	for i in back.size():
		var a := deg_to_rad(-40.0 + 80.0 * float(i) / float(maxi(back.size() - 1, 1)))
		SimWorld.Movement.order_move(w, back[i], _post(w, site - dir.rotated(a) * 2.4))
		back[i].order.sq = "cn"


static func start_deploy(w: SimWorld, t: Dictionary, site: Vector2, kind: String) -> void:
	t.dep = {"site": site, "kind": kind, "phase": "scan", "prog": 0, "stalled": "", "hero": -1, "hero_at": -1,
		"t0": w.tick, "dis": false}
	_deploy_posts(w, t, site)
	w.emit("CnDeployStarted", {"team": int(t.id), "owner": int(t.fid), "site": site, "kind": kind})


## Ticks a phase needs (arming: package arm time, faster with more deployment specialists and team level).
static func need_ticks(w: SimWorld, t: Dictionary, phase: String) -> int:
	var D: Dictionary = R().get("deploy", {})
	match phase:
		"scan":
			return ticks(float(D.get("scan_s", 6)))
		"jam":
			return ticks(float(D.get("jam_s", 4)))
	var d: Dictionary = t.dep
	var P: Dictionary = (R().get("packages", {}) as Dictionary).get(String(d.kind), {})
	var n := on_foot_near(w, t, "deploy", d.site, float(D.get("site_radius", 7.0))).size()
	var lvl := clampi(int(Apc7.callf(SimWorld.CnFacility, "team_level", [w, int(t.id)], 0)), 0, 3)
	var f := 1.0 / (1.0 + 0.25 * float(maxi(n - 1, 0))) * (1.0 - 0.1 * float(lvl))
	return ticks(float(P.get("arm_s", 20)) * f)


static func _tick_deploy(w: SimWorld, t: Dictionary, every: int) -> void:
	var d: Dictionary = t.dep
	var D: Dictionary = R().get("deploy", {})
	var site: Vector2 = d.site
	var r := float(D.get("site_radius", 7.0))
	if String(d.phase) == "hero":
		if w.tick >= int(d.hero_at):
			_detonate(w, t, true)
		return
	if not bool(d.dis):
		var ready := true   # dismount once both strike APCs are parked at the site (or after rules.deploy.park_s)
		for aid in t.apcs:
			var a = w.entities.get(int(aid))
			if a != null and (bool(a.get("moving", false)) or Vector2(a.pos).distance_to(site) > 4.0):
				ready = false
		if ready or w.tick - int(d.t0) > ticks(float(D.get("park_s", 25))):
			dismount(w, t)
			_take_posts(w, t, site)
			d.dis = true
		return
	if (t.hold as Array).is_empty() and not on_foot_near(w, t, "medic", site, r).is_empty():
		_setup_hold(w, t, site)
	var why := ""
	if not pair_ok(w, t):
		why = "apc_lost"
	else:
		match String(d.phase):
			"scan":
				if on_foot_near(w, t, "scanner", site, r).is_empty():
					why = "no_scanner"
			"jam":
				if on_foot_near(w, t, "ew", site, r).is_empty():
					why = "no_ew"
			"arm":
				if on_foot_near(w, t, "deploy", site, r).is_empty():
					why = "no_deployer"
				elif bool(D.get("need_dome", true)) and not _dome_ready(w, t, site, r):
					why = "dome_down"
	if why != "":
		if String(d.stalled) != why:
			d.stalled = why
			w.emit("CnDeployStalled", {"team": int(t.id), "owner": int(t.fid), "reason": why, "phase": String(d.phase)})
		return
	if String(d.stalled) != "":
		d.stalled = ""
		w.emit("CnDeployResumed", {"team": int(t.id), "owner": int(t.fid), "phase": String(d.phase)})
	d.prog = int(d.prog) + every
	if int(d.prog) < need_ticks(w, t, String(d.phase)):
		return
	d.prog = 0
	var fid := int(t.fid)
	match String(d.phase):
		"scan":
			var found = Apc7.callf(SimWorld.Creep, "reveal", [w, site, r * 1.5, fid], 0)
			d.found = int(found) if typeof(found) == TYPE_INT else 0
			d.phase = "jam"
		"jam":
			Apc7.callf(SimWorld.Creep, "jam_link", [w, site, float(D.get("jam_radius", 9.0)),
				w.tick + ticks(float(D.get("jam_hold_s", 60))), fid], null)
			d.phase = "arm"
		"arm":
			_detonate(w, t, false)
			return
	w.emit("CnDeployPhase", {"team": int(t.id), "owner": fid, "phase": String(d.phase), "site": site})


## A team APC near the site has its dome up; the crew raises it themselves when they can.
static func _dome_ready(w: SimWorld, t: Dictionary, site: Vector2, r: float) -> bool:
	var cand = null
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a == null or Vector2(a.pos).distance_to(site) > r:
			continue
		if Apc7.dome_up(a):
			return true
		if cand == null and Apc7._dome_ok(w, a):
			cand = a
	if cand != null:
		Apc7.set_dome(w, cand, true)
		return true
	return false


## The ground is cleared: Creep.purge (+ Cores.core_breaker on the nearest core for a core-breaker).
static func _detonate(w: SimWorld, t: Dictionary, hero: bool) -> void:
	var d: Dictionary = t.dep
	var kind := String(d.kind)
	var site: Vector2 = d.site
	var fid := int(t.fid)
	var P: Dictionary = (R().get("packages", {}) as Dictionary).get(kind, {})
	var a = pkg_apc(w, t, kind)
	if a != null:
		(a.a7.pk as Array).erase(kind)
	var ckind := kind if kind == "seed_hunter" or kind == "barrier" else "standard"
	var bdir := Vector2.ZERO
	if kind == "barrier" and (site - Vector2(t.spawn)).length() > 0.01:
		bdir = (site - Vector2(t.spawn)).normalized().orthogonal()   # a firebreak across the approach
	var res = Apc7.callf(SimWorld.Creep, "purge", [w, site, float(P.get("radius", 6.0)), ckind, fid, bdir], {})
	var core := -1
	if kind == "core_breaker":
		core = _core_near(w, site, float(P.get("radius", 3.0)) + 2.0)
		if core >= 0:
			Apc7.callf(SimWorld.Cores, "finish", [w, core, fid], null)
	if hero:
		_hero_blast(w, t, site)
	w.emit("CnPurge", {"team": int(t.id), "owner": fid, "site": site, "kind": kind, "hero": hero,
		"cleared": int(res.get("cells", 0)) if typeof(res) == TYPE_DICTIONARY else 0, "core": core})
	t.dep = null
	t.xp = int(t.xp) + 1
	_pack_hold(w, t)
	remount(w, t)   # after a hero blast the survivors board too (they withdrew during the window)


## Index of the nearest live doomsday core (CREEP7 Cores.list) within r of site, or -1.
static func _core_near(w: SimWorld, site: Vector2, r: float) -> int:
	var best := -1
	var bd := INF
	var L = Apc7.callf(SimWorld.Cores, "list", [w], [])
	if typeof(L) != TYPE_ARRAY:
		return -1
	for c in L:
		if typeof(c) != TYPE_DICTIONARY or not bool(c.get("alive", false)):
			continue
		var dd := Vector2(c.get("pos", Vector2(-999, -999))).distance_to(site)
		if dd <= r and dd < bd:
			bd = dd
			best = int(c.get("ix", -1))
	return best


static func hero_pick(w: SimWorld, t: Dictionary, uid: int) -> int:
	if t.dep == null:
		return -1
	var r := float(R().get("deploy", {}).get("site_radius", 7.0))
	var near := on_foot_near(w, t, "", t.dep.site, r)
	if uid >= 0 and near.has(uid):
		return uid
	var dep := on_foot_near(w, t, "deploy", t.dep.site, r)
	if not dep.is_empty():
		return int(dep[0])
	return -1 if near.is_empty() else int(near[0])


static func hero_reason(w: SimWorld, t: Dictionary, uid: int) -> String:
	if t.dep == null:
		return "No package is being deployed."
	if String(t.dep.phase) == "hero":
		return "Already detonating."
	if hero_pick(w, t, uid) < 0:
		return "No operator at the site to stay behind."
	return ""


## Hero window: everyone else pulls back as a formed group (formed_withdraw: APC line between the blast and the
## soldiers, smoke on the threat side, soldiers in a block behind the hulls). They remount after the blast.
static func _withdraw(w: SimWorld, t: Dictionary, hid: int, site: Vector2) -> void:
	var br := float(R().get("hero", {}).get("blast_radius", 3.5))
	formed_withdraw(w, [t], site, -_threat_dir(w, t, site), br, [hid])


## One operator stays and arms by hand: instant arming, the rest withdraw out of the blast, then it goes off.
static func start_hero(w: SimWorld, t: Dictionary, uid: int) -> void:
	var hid := hero_pick(w, t, uid)
	var d: Dictionary = t.dep
	var H: Dictionary = R().get("hero", {})
	d.phase = "hero"
	d.hero = hid
	d.hero_at = w.tick + ticks(float(H.get("window_s", 6)))
	d.stalled = ""
	var h: Dictionary = w.entities[hid]
	SimWorld.Movement.stop_path(h)
	h.order = {"type": "hold"}
	h.cn_hero = true
	var v = w.sys_state.get("g7v")
	if v == null:
		v = {}
		w.sys_state["g7v"] = v
	if not v.has(hid):
		v[hid] = {}
	v[hid].hero = true
	_withdraw(w, t, hid, d.site)
	w.emit("CnHeroDetonation", {"team": int(t.id), "owner": int(t.fid), "id": hid, "call_sign": String(h.get("call_sign", "")),
		"site": d.site, "at": int(d.hero_at)})


static func _hero_blast(w: SimWorld, t: Dictionary, site: Vector2) -> void:
	var H: Dictionary = R().get("hero", {})
	var br := float(H.get("blast_radius", 3.5))
	var hid := int(t.dep.hero)
	for u in Apc7.near(w, site, br):
		if int(u.id) == hid or not w.entities.has(int(u.id)):
			continue
		var dmg := float(H.get("blast_damage", 600)) * (1.0 - 0.5 * Vector2(u.pos).distance_to(site) / br)
		var hp := snappedf(float(u.hp) - dmg, 0.01)
		SimWorld.HotState.set_hp(w, int(u.id), hp)
		if hp <= 0.0:
			w.destroy(int(u.id), "package_blast", int(t.fid))
	var h = w.entities.get(hid)
	if h != null:
		var st := _st(w)
		st.remembered.append({"call_sign": String(h.get("call_sign", "")), "def": String(h.def), "team": int(t.id),
			"team_name": String(t.name), "tick": w.tick, "owner": int(t.fid)})
		w.destroy(hid, "hero_detonation")
		var v = w.sys_state.get("g7v")
		if v != null:
			v.erase(hid)
		w.emit("CnRemembered", {"team": int(t.id), "owner": int(t.fid), "call_sign": String(h.get("call_sign", ""))})


## The engineers place the hold by themselves: barriers on an arc facing the threat, sentries just inside it.
static func _setup_hold(w: SimWorld, t: Dictionary, site: Vector2) -> void:
	var H: Dictionary = R().get("hold", {})
	var fid := int(t.fid)
	var dir := Vector2.ZERO
	for u in Apc7.near(w, site, 16.0):
		if w.is_enemy(fid, int(u.owner)):
			dir += Vector2(u.pos) - site
	if dir.length() < 0.01:
		dir = site - Vector2(t.spawn)
	dir = Vector2.RIGHT if dir.length() < 0.01 else dir.normalized()
	var ring := float(H.get("ring", 3.5))
	var ids := []
	var nb := int(H.get("barriers", 4))
	var ns := int(H.get("sentries", 2))
	for i in nb + ns:
		var sentry := i >= nb
		var j := i - nb if sentry else i
		var span := 70.0 if sentry else 120.0
		var cnt := ns if sentry else nb
		var ang := deg_to_rad(-span * 0.5 + span * float(j) / maxf(float(cnt - 1), 1.0))
		var p := site + dir.rotated(ang) * (ring - 1.2 if sentry else ring)
		p = Vector2(clampf(p.x, 1.0, float(w.map.w) - 2.0), clampf(p.y, 1.0, float(w.map.h) - 2.0))
		var id := w.spawn_unit("g7_cn_sentry" if sentry else "g7_cn_barrier", fid, p)
		w.entities[id].order = {"type": "hold"}
		w.entities[id].cn_hold = int(t.id)
		ids.append(id)
	t.hold = ids
	w.emit("CnHoldSetup", {"team": int(t.id), "owner": fid, "dir": dir, "barriers": nb, "sentries": ns, "site": site})


static func _pack_hold(w: SimWorld, t: Dictionary) -> void:
	if (t.hold as Array).is_empty():
		return
	for id in t.hold:
		if w.entities.has(int(id)):
			w.destroy(int(id), "packed")
			if w.factions.has(int(t.fid)):
				w.factions[int(t.fid)].stats.lost -= 1
	t.hold = []
	w.emit("CnHoldPacked", {"team": int(t.id), "owner": int(t.fid)})


static func dismount(w: SimWorld, t: Dictionary) -> void:
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a == null or not a.has("cargo") or (a.cargo as Array).is_empty():
			continue
		var ids := []
		for u in a.cargo:
			ids.append(int(u.id))
		SimWorld.Transport.unload(w, a, ids, Vector2(a.pos), "cn_dismount")
		_squad_touch(w)
	w.emit("CnDismount", {"team": int(t.id), "owner": int(t.fid)})


## Every on-foot member boards its own squad's APC (the other one when it is gone). skip = stays outside.
static func remount(w: SimWorld, t: Dictionary, skip: int = -1) -> void:
	for id in t.members:
		var u = w.entities.get(int(id))
		if u == null or int(id) == skip:
			continue
		var idx := 1 if String(u.get("cn_sq", "A")) == "B" and t.apcs.size() > 1 else 0
		var c = w.entities.get(int(t.apcs[idx]))
		if c == null or SimWorld.Transport.free_slots(c) <= 0:
			c = null
			for aid in t.apcs:
				var o = w.entities.get(int(aid))
				if o != null and SimWorld.Transport.free_slots(o) > 0:
					c = o
					break
		if c != null:
			SimWorld.Transport.order_board(w, u, c)
	w.emit("CnRemount", {"team": int(t.id), "owner": int(t.fid)})


# ================================================================ team upkeep (every 10 ticks per team)
static func _tick_team(w: SimWorld, t: Dictionary) -> void:
	if live_members(w, t).is_empty() and live_apcs(w, t).is_empty():
		t.dead = true
		_pack_hold(w, t)
		return
	_succession(w, t)
	if String(t.kind) == "strike":
		_pair_follow(w, t)
	var leash := float(R().get("loadout_leash", 12.0))
	var on_map := []
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null:
			on_map.append(a)
	var at_fac := false
	var away := not on_map.is_empty()
	for a in on_map:
		if near_facility(w, int(t.fid), a.pos, leash):
			at_fac = true
			away = false
		elif Vector2(a.pos).distance_to(t.spawn) <= leash:
			away = false
	if bool(t.locked) and at_fac:
		unlock_loadout(w, int(t.id))
	elif not bool(t.locked) and away:
		t.locked = true
		w.emit("CnLoadoutLocked", {"team": int(t.id), "owner": int(t.fid)})
	if t.dep == null and not (t.hold as Array).is_empty():
		_pack_hold(w, t)


static func _succession(w: SimWorld, t: Dictionary) -> void:
	if int(t.leader) >= 0 and alive(w, int(t.leader)):
		return
	var cand := -1
	for sq in ["A", "B"]:
		for id in t.squads.get(sq, []):
			if cand < 0 and alive(w, int(id)) and role_of(find(w, int(id))) == "second":
				cand = int(id)
	if cand < 0:
		for sq in ["A", "B"]:
			for id in t.squads.get(sq, []):
				if cand < 0 and alive(w, int(id)):
					cand = int(id)
	var old := int(t.leader)
	if cand == old:
		return
	t.leader = cand
	var e = find(w, cand) if cand >= 0 else null
	if e != null:
		e.cn_lead = true
	w.emit("CnLeaderChange", {"team": int(t.id), "owner": int(t.fid), "from": old, "to": cand,
		"call_sign": String(e.get("call_sign", "")) if e != null else ""})


## A lone move order on one strike APC pulls its partner along (the pair never splits up).
static func _pair_follow(w: SimWorld, t: Dictionary) -> void:
	if t.apcs.size() < 2:
		return
	var a = w.entities.get(int(t.apcs[0]))
	var b = w.entities.get(int(t.apcs[1]))
	if a == null or b == null or int(Apc7.callf(SimWorld.Convoy, "of_unit", [w, int(a.id)], -1)) >= 0:
		return
	var leash := float(R().get("pair_leash", 8.0))
	for pr in [[a, b], [b, a]]:
		var x: Dictionary = pr[0]
		var y: Dictionary = pr[1]
		var xt := String(x.order.get("type", ""))
		if (xt == "move" or xt == "attack_move") and String(y.order.get("type", "")) == "idle" \
				and Vector2(x.pos).distance_to(y.pos) > leash and typeof(x.order.get("target")) == TYPE_VECTOR2:
			SimWorld.Movement.order_move(w, y, Vector2(x.order.target) + Vector2(0.0, 2.5))
			w.emit("CnPairFollow", {"team": int(t.id), "owner": int(t.fid), "id": int(y.id)})
			return


# ================================================================ system tick
static func tick(w: SimWorld) -> void:
	_tick_exposure(w)
	var st = w.sys_state.get("cn7")
	if st == null:
		return
	var every := int(R().get("deploy", {}).get("think_every", 5))
	for tid in team_ids(w):
		var t: Dictionary = st.teams[tid]
		if bool(t.get("dead", false)):
			continue
		if t.dep != null and (w.tick + int(tid)) % every == 0:
			_tick_deploy(w, t, every)
		if (w.tick + int(tid)) % 10 == 0:
			_tick_team(w, t)
			_tick_kit(w, t)
		if (w.tick + int(tid)) % int(R().get("pincer", {}).get("think", 5)) == 0:
			_tick_eng(w, t)


# ================================================================ suits and exposure (every rules.exposure.every ticks)
static func _creep_on(w: SimWorld, pos: Vector2) -> bool:
	return bool(Apc7.callf(SimWorld.Creep, "on_creep", [w, w.cell_of(pos)], false))


static func _expose(w: SimWorld, e: Dictionary, amt: float) -> void:
	if amt <= 0.0:
		return
	var st := _st(w)
	var X: Dictionary = R().get("exposure", {})
	e.cn_exp = minf(float(e.get("cn_exp", 0.0)) + amt, float(X.get("max", 1.0)))
	if not (st.exposed as Array).has(int(e.id)):
		st.exposed.append(int(e.id))
		st.exposed.sort()
	_render(w, e)


static func _tick_exposure(w: SimWorld) -> void:
	var X: Dictionary = R().get("exposure", {})
	var every := int(X.get("every", 10))
	if w.tick % every != 0:
		return
	var st = w.sys_state.get("cn7")
	var creep := w.sys_state.has("creep")
	var per_s := float(every) / float(SimWorld.TICK_RATE)
	if creep:   # ordinary soldiers on foot in creep (half of them per pass, by id parity)
		var par := (w.tick / every) % 2
		for u in SimWorld.SimIndex.of(w, "unit"):
			if int(u.id) % 2 != par or not u.has("morale") or bool(u.get("suit", false)):
				continue
			if String(Content.unit(String(u.def)).get("move_class", "")) != "foot" or not _creep_on(w, u.pos):
				continue
			_expose(w, u, float(X.get("creep_rate", 0.02)) * per_s * 2.0)
	if st == null:
		return
	for tid in team_ids(w):   # sealed suits: any hit punctures; punctured suits build exposure
		var t: Dictionary = st.teams[tid]
		if bool(t.get("dead", false)):
			continue
		for id in t.members:
			var e = w.entities.get(int(id))
			if e == null:
				continue
			if float(e.hp) < float(e.get("cn_hp", e.max_hp)) - 0.01 and not bool(e.get("wpunct", false)):
				var src := int(e.get("last_attacker", -1))
				if not bool(Apc7.callf(SimWorld.Wounds, "puncture", [w, e, src], false)) and not bool(e.get("wpunct", false)):
					e.wpunct = true
					w.emit("SuitPunctured", {"id": int(e.id), "owner": int(e.owner), "src": src})
				_render(w, e)
			e.cn_hp = float(e.hp)
			if bool(e.get("wpunct", false)):
				var rate := float(X.get("punct_rate", 0.03))
				if creep and _creep_on(w, e.pos):
					rate += float(X.get("creep_rate", 0.02))
				_expose(w, e, rate * per_s)
	if (st.exposed as Array).is_empty():
		return
	var decon := {}
	var keep := []
	for id in st.exposed:
		var e = w.entities.get(int(id))
		if e == null:
			if alive(w, int(id)):
				keep.append(int(id))   # riding inside: sealed cabin, no change
			continue
		var fid := int(e.owner)
		if not decon.has(fid):
			decon[fid] = _decon_spots(w, fid)
		var cleaned := false
		for p in decon[fid]:
			if Vector2(p).distance_to(e.pos) <= float(R().get("decon_radius", 2.5)):
				cleaned = true
				break
		if cleaned:
			decontaminate(w, e)
			continue
		var x := float(e.get("cn_exp", 0.0))
		if x <= 0.0:
			continue
		e.cn_slow = maxf(float(X.get("slow_min", 0.5)), 1.0 - float(X.get("slow_per", 0.5)) * x)
		if x >= float(X.get("hurt_at", 0.25)):
			var hp := snappedf(float(e.hp) - float(X.get("hurt_hp", 2.0)) * x * per_s, 0.01)
			SimWorld.HotState.set_hp(w, int(e.id), hp)
			e.cn_hp = hp
			if hp <= 0.0:
				w.destroy(int(e.id), "nanite_exposure")
				continue
		keep.append(int(id))
	st.exposed = keep


static func _decon_spots(w: SimWorld, fid: int) -> Array:
	var out := []
	var defs: Array = R().get("decon_defs", [])
	for b in w.buildings_of(fid):
		if defs.has(String(b.def)) or bool(Content.building(String(b.def)).get("cn_decon", false)):
			out.append(Vector2(b.pos))
	return out


# ================================================================ kit: EMP grenades (security gunners, EMP grenadier)
static func _tick_kit(w: SimWorld, t: Dictionary) -> void:
	var K: Dictionary = R().get("kit", {}).get("emp_grenade", {})
	var rng := float(K.get("range", 5.0))
	for id in t.members:
		var e = w.entities.get(int(id))
		if e == null or w.tick < int(e.get("kit_cd", 0)):
			continue
		var role := role_of(e)
		if role != "gunner" and role != "emp":
			continue
		var tgt = null
		for u in Apc7.near(w, e.pos, rng):
			if w.is_enemy(int(e.owner), int(u.owner)) and not Apc7.unhackable(u) \
					and String(Content.unit(String(u.def)).get("faction", "")) == "machine":
				tgt = u
				break
		if tgt == null:
			continue
		e.kit_cd = w.tick + ticks(float(K.get("cooldown_s", 30)))
		var at: Vector2 = tgt.pos
		var n := 0
		for u in Apc7.near(w, at, float(K.get("radius", 2.5))):
			if not w.entities.has(int(u.id)) or not w.is_enemy(int(e.owner), int(u.owner)) or Apc7.unhackable(u):
				continue
			if SimWorld.Counterdrone.is_drone(w, u):
				w.destroy(int(u.id), "emp", int(e.owner))
			else:
				Apc7._disable(w, u, int(K.get("ticks", 100)))
			n += 1
		w.emit("CnEmpGrenade", {"id": int(e.id), "owner": int(e.owner), "pos": at, "hit": n})


# ================================================================ commands
static func _pt(v):
	if typeof(v) == TYPE_VECTOR2:
		return v
	if typeof(v) == TYPE_VECTOR2I:
		return Vector2(v) + Vector2(0.5, 0.5)
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 2:
		return Vector2(float(v[0]), float(v[1]))
	return null


static func _cmd_team(w: SimWorld, cmd: Dictionary):
	if cmd.has("team_id"):
		return team(w, int(cmd.team_id))
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null and team_of(e) >= 0:
			return team(w, team_of(e))
	return null


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var ty := String(cmd.get("type", ""))
	var t = _cmd_team(w, cmd)
	if t == null:
		return "Select a counter-nanite team."
	if int(t.fid) != int(cmd.get("issuer", -1)):
		return "Not your team."
	if bool(t.get("dead", false)):
		return "That team is gone."
	match ty:
		"cn_set_loadout":
			if String(t.kind) != "strike" and not (cmd.get("packages", []) as Array).is_empty():
				return "Only strike APCs carry packages."
			if bool(t.locked) and cmd.has("rockets"):
				return "The loadout is locked in the field: return to the facility to re-equip."
			if cmd.has("rockets") and typeof(cmd.rockets) != TYPE_DICTIONARY:
				return "Rockets: {canister: count}."
			if cmd.has("rockets"):
				var nr := 0
				for k in cmd.rockets:
					if not (Apc7.L().get("kinds", {}) as Dictionary).has(String(k)):
						return "Unknown canister '%s'." % String(k)
					nr += int(cmd.rockets[k])
				if nr > int(Apc7.L().get("capacity", 18)):
					return "The launcher holds %d rounds." % int(Apc7.L().get("capacity", 18))
				if String(t.kind) != "strike":
					return ""
			if bool(t.locked):
				return "The loadout is locked in the field: return to the facility to re-equip."
			var cap := 0
			for aid in t.apcs:
				var a = find(w, int(aid))
				if a != null:
					cap += int(Apc7.cfg_of(String(a.def)).get("pkg_capacity", 0))
			var used := 0
			var count := {}
			for k in cmd.get("packages", []):
				if not (R().get("packages", {}) as Dictionary).has(String(k)):
					return "Unknown package '%s'." % String(k)
				used += pkg_size(String(k))
				count[String(k)] = int(count.get(String(k), 0)) + 1
			if used > cap:
				return "Too many packages: the APCs hold %d." % cap
			if _has_lab(w, int(t.fid)):
				for k in count:
					if int(Apc7.callf(SimWorld.CnFacility, "stock", [w, int(t.fid), k], 0)) < int(count[k]):
						return "Not enough %s packages in the lab." % k
			return ""
		"cn_deploy":
			var p = _pt(cmd.get("target"))
			if p == null:
				return "Pick a deployment site."
			return deploy_reason(w, t, p, String(cmd.get("package", "purge")))
		"cn_hero_detonate":
			return hero_reason(w, t, int(cmd.get("unit_id", -1)))
		"cn_dismount", "cn_mount":
			return ""
		"cn_move":
			return "" if _pt(cmd.get("target")) != null else "Pick a destination."
		"cn_pincer":
			if t.dep != null:
				return "The team is deploying a package."
			if _group_apcs(w, t).is_empty():
				return "No APC left."
			if not ["", "pincer", "head_on"].has(String(cmd.get("mode", ""))):
				return "Unknown engagement mode."
			return "" if pincer_target(w, t, int(cmd.get("target_id", -1))) != null else "No heavy Machine walker in reach."
		"cn_break_contact":
			return ""
	return "Unknown counter-nanite command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var t = _cmd_team(w, cmd)
	match String(cmd.get("type", "")):
		"cn_set_loadout":
			if String(t.kind) == "strike" and cmd.has("packages"):
				_set_loadout(w, t, cmd.get("packages", []))
			if cmd.has("rockets"):
				for aid in t.apcs:
					var ra = find(w, int(aid))
					if ra != null:
						Apc7.set_rockets(w, ra, cmd.rockets)
				w.emit("CnRocketsSet", {"team": int(t.id), "owner": int(t.fid), "rockets": Apc7.clamp_load(cmd.rockets)})
		"cn_pincer":
			start_eng(w, t, pincer_target(w, t, int(cmd.get("target_id", -1))), "player", String(cmd.get("mode", "")))
		"cn_break_contact":
			var bw = w.entities.get(int(t.eng.tgt)) if t.get("eng") != null else null
			break_contact(w, t, Vector2(bw.pos) if bw != null else _threat_pos(w, t))
		"cn_deploy":
			start_deploy(w, t, _pt(cmd.target), String(cmd.get("package", "purge")))
		"cn_hero_detonate":
			start_hero(w, t, int(cmd.get("unit_id", -1)))
		"cn_dismount":
			dismount(w, t)
		"cn_mount":
			remount(w, t)
		"cn_move":
			move_team(w, t, _pt(cmd.target), cmd.get("escort_teams", []))


## Packages come from CNFAC7's lab stock (CnFacility.take_packages) when it exists; split across the APCs in order.
static func _set_loadout(w: SimWorld, t: Dictionary, kinds: Array) -> void:
	var want := []
	var count := {}
	for k in kinds:
		count[String(k)] = int(count.get(String(k), 0)) + 1
	var got := {}
	var ks: Array = count.keys()
	ks.sort()
	var lab := _has_lab(w, int(t.fid))
	for k in ks:
		got[k] = int(Apc7.callf(SimWorld.CnFacility, "take_packages", [w, int(t.fid), k, int(count[k])], int(count[k]))) \
			if lab else int(count[k])
	for k in kinds:
		if int(got.get(String(k), 0)) > 0:
			got[String(k)] = int(got[String(k)]) - 1
			want.append(String(k))
	_split(w, t, want)
	w.emit("CnLoadoutSet", {"team": int(t.id), "owner": int(t.fid), "loadout": loadout(w, int(t.id))})


## true when side fid has a CNFAC7 facility (then packages come from its lab stock; scenario-spawned teams without
## a facility load their packages free).
static func _has_lab(w: SimWorld, fid: int) -> bool:
	var f = Apc7.callf(SimWorld.CnFacility, "facilities", [w, fid], [])
	return typeof(f) == TYPE_ARRAY and not (f as Array).is_empty()


## One order moves everything: SQUAD7's motorcade convoy (strike APCs = core, tactical APCs and on-foot
## members = escorts / moving cover); without the Convoy API each APC drives on its own.
static func move_team(w: SimWorld, t: Dictionary, target: Vector2, escort_teams: Array = []) -> void:
	var esc := []   # remembered so the deployment drill can post the escorts at the site
	for tt in _teams(w, int(t.fid), escort_teams):
		esc.append(int(tt.id))
	if not esc.is_empty() or not t.has("esc"):
		t.esc = esc
	var ids := []
	var core := []
	for tt in [t] + _teams(w, int(t.fid), escort_teams):
		for aid in tt.apcs:
			if w.entities.has(int(aid)):
				ids.append(int(aid))
				if String(tt.kind) == "strike":
					core.append(int(aid))
		for mid in tt.members:
			if w.entities.has(int(mid)):
				ids.append(int(mid))
	ids.sort()
	if ids.is_empty():
		return
	t.mv_to = target
	var cid := int(Apc7.callf(SimWorld.Convoy, "form", [w, int(t.fid), ids, core], -1))
	if cid >= 0:
		t.conv = cid
		Apc7.callf(SimWorld.Convoy, "move", [w, cid, target], null)
	else:
		var k := 0
		for id in ids:
			var e: Dictionary = w.entities[id]
			if e.has("a7"):
				SimWorld.Movement.order_move(w, e, target + Vector2(0.0, 2.5 * float(k)))
				k += 1
	w.emit("CnMove", {"team": int(t.id), "owner": int(t.fid), "target": target, "convoy": cid, "units": ids.size()})


static func _teams(w: SimWorld, fid: int, tids: Array) -> Array:
	var out := []
	for raw in tids:
		var tt = team(w, int(raw))
		if tt != null and int(tt.fid) == fid and not bool(tt.get("dead", false)):
			out.append(tt)
	return out


# ================================================================ anti-walker pincer (owner addition 2026-10-26)
## One element (the fixer, a tactical APC when there is one) rushes the walker head-on and stops in its face (dome up);
## the other APCs take flank / rear slots (rules pincer.slot_angles around the walker->fixer axis) and fire
## synchronised volleys (EMP opens a stun window, a disruptor marks it, tandem / thermite into the flanks; everything
## into the belly once it is down). Tactical operators dismount when the walker is fixed and go for it with their
## kit; strike gunners run out with limpets while it lies toppled. Auto (the group handles contact itself, also under
## an AI Commander) or one player order (cn_pincer). State t.eng (lead team: the strike team, or a lone tactical squad).
static func P() -> Dictionary:
	return R().get("pincer", {})


static func _frac(e: Dictionary) -> float:
	return float(e.hp) / maxf(float(Content.unit(String(e.def)).get("hp", 1)), 1.0)


## The strike team this tactical squad escorts (then that team leads the group), or null.
static func _lead_of(w: SimWorld, t: Dictionary):
	if String(t.kind) == "strike":
		return null
	for tid in team_ids(w):
		var o: Dictionary = w.sys_state.cn7.teams[tid]
		if String(o.kind) == "strike" and not bool(o.get("dead", false)) and (o.get("esc", []) as Array).has(int(t.id)):
			return o
	return null


static func _group_teams(w: SimWorld, t: Dictionary) -> Array:
	return [t] + _teams(w, int(t.fid), t.get("esc", []))


static func _group_apcs(w: SimWorld, t: Dictionary) -> Array:
	var out := []
	for tt in _group_teams(w, t):
		for aid in tt.apcs:
			var a = w.entities.get(int(aid))
			if a != null and a.has("a7"):
				out.append(a)
	return out


static func pincer_target(w: SimWorld, t: Dictionary, tid: int):
	var fid := int(t.fid)
	if tid >= 0:
		var u = w.entities.get(tid)
		return u if u != null and w.is_enemy(fid, int(u.owner)) and Apc7.is_heavy_walker(u) else null
	var best = null
	var bd := INF
	for a in _group_apcs(w, t):
		for u in Apc7.near(w, a.pos, float(P().get("detect", 12.0))):
			if not w.is_enemy(fid, int(u.owner)) or not Apc7.is_heavy_walker(u):
				continue
			var d := Vector2(u.pos).distance_to(a.pos)
			if d < bd:
				bd = d
				best = u
	return best


static func _threat_pos(w: SimWorld, t: Dictionary) -> Vector2:
	var apcs := _group_apcs(w, t)
	var c := Vector2(t.spawn) if apcs.is_empty() else Vector2(apcs[0].pos)
	return c + _threat_dir(w, t, c) * 6.0


## Player control first: an auto pincer never moves a unit on Hold Position or with a fresh player order.
static func _held(w: SimWorld, e: Dictionary) -> bool:
	return String(e.order.get("type", "")) == "hold" or bool(Apc7.callf(SimWorld.AiCommand, "player_fresh", [w, e], false))


## Unloaded soldiers come back into w.entities under their old ids, which SquadAI's runtime index (w.cache.sq61,
## extended only by new ids) misses until something rebuilds it, and a loaded save always rebuilds it: bump its saved
## version so the live and the loaded match index them the same way (CNSIM7-5 save round-trip mid-pincer).
static func _squad_touch(w: SimWorld) -> void:
	Apc7.callf(SimWorld.SquadAI, "touch", [w], null)


## The attack is stalling (rules pincer.stall_*, PROVISIONAL): stall_s x (hp / topple.threshold_hp_ref) ^ stall_exp
## seconds into the engagement the walker still has more than stall_hp of its hp and is not lying toppled.
static func _stalled(w: SimWorld, E: Dictionary, wk: Dictionary) -> bool:
	var s := float(P().get("stall_s", 0.0))
	if s <= 0.0 or Apc7.is_down(wk):
		return false
	var hp := float(Content.unit(String(wk.def)).get("hp", 950))
	s *= pow(maxf(hp, 1.0) / float(Apc7.TP().get("threshold_hp_ref", 950)), float(P().get("stall_exp", 0.5)))
	return w.tick - int(E.get("t0", w.tick)) >= Apc7.ticks(s) and _frac(wk) > float(P().get("stall_hp", 0.6))


## mode "head_on": every hull in its front arc and the operators come at it from the front (a straight fight; the
## pincer is the default and the right way).
static func start_eng(w: SimWorld, t: Dictionary, wk, by: String, mode: String = "") -> void:
	if wk == null:
		return
	if int(t.get("conv", -1)) >= 0:
		Apc7.callf(SimWorld.Convoy, "disband", [w, int(t.conv)], null)
		t.conv = -1
	t.wd = null
	t.eng = {"tgt": int(wk.id), "fix": -1, "ax": 0.0, "by": by, "t0": w.tick, "volley": w.tick, "volleys": 0,
		"reslot": w.tick, "gunners": [], "mode": "head_on" if mode == "head_on" else "pincer", "dv": false}
	var apcs := _group_apcs(w, t)
	_assign(w, t, wk, apcs, null)
	_place(w, t, wk, apcs)
	w.emit("CnPincer", {"team": int(t.id), "owner": int(t.fid), "target": int(wk.id), "by": by, "fixer": int(t.eng.fix),
		"apcs": apcs.size(), "pos": wk.pos})


## Fixer: the healthiest-nearest tactical APC (strike APCs only when no tactical one is fit).
static func _assign(w: SimWorld, t: Dictionary, wk: Dictionary, apcs: Array, old) -> void:
	var E: Dictionary = t.eng
	var best = null
	var bs := INF
	var swap := float(P().get("fixer_swap_hp", 0.3))
	for a in apcs:
		if old != null and int(a.id) == int(old.id) and apcs.size() > 1:
			continue
		var sc := Vector2(a.pos).distance_to(wk.pos) + (0.0 if String(Apc7.cfg_of(String(a.def)).get("kind", "")) == "tactical" else 6.0) \
			+ (20.0 if _frac(a) < swap else 0.0)
		if sc < bs:
			bs = sc
			best = a
	if best == null:
		return
	E.fix = int(best.id)
	var v := Vector2(best.pos) - Vector2(wk.pos)
	E.ax = snappedf((v if v.length() > 0.1 else Vector2.RIGHT).angle(), 0.001)
	E.reslot = w.tick
	if old != null:
		w.emit("CnPincerSwap", {"team": int(t.id), "owner": int(t.fid), "from": int(old.id), "to": int(best.id)})


static func _go(w: SimWorld, u: Dictionary, goal: Vector2, tol: float = 1.0) -> void:
	goal = _post(w, goal)
	var cur = u.order.get("target")
	if Vector2(u.pos).distance_to(goal) <= tol:
		return
	if String(u.order.get("type", "")) == "move" and typeof(cur) == TYPE_VECTOR2 and Vector2(cur).distance_to(goal) <= tol:
		return
	SimWorld.Movement.order_move(w, u, goal)
	u.order.sq = "cn"


## Slots around the walker; the axis follows the fixer, who stays in its face.
static func _place(w: SimWorld, t: Dictionary, wk: Dictionary, apcs: Array) -> void:
	var E: Dictionary = t.eng
	var W: Vector2 = wk.pos
	var fxe = w.entities.get(int(E.fix))
	if fxe != null and Vector2(fxe.pos).distance_to(W) > 0.5:
		E.ax = snappedf((Vector2(fxe.pos) - W).angle(), 0.001)
	var a := Vector2.from_angle(float(E.ax))
	var slots := {}
	if fxe != null:
		slots[int(fxe.id)] = _post(w, W + a * float(P().get("fix_dist", 4.0)))
	var free := []
	for e in apcs:
		if int(e.id) != int(E.fix):
			free.append(e)
	var angs: Array = P().get("head_on_angles", [25, -25, 40, -40, 0]) if String(E.get("mode", "")) == "head_on" 		else P().get("slot_angles", [110, -110, 150, -150, 180])
	var i := 0
	while not free.is_empty() and i < angs.size():
		var sp := _post(w, W + a.rotated(deg_to_rad(float(angs[i]))) * float(P().get("flank_dist", 6.0)))
		var bj := 0
		var bd := INF
		for j in free.size():
			var d := Vector2(free[j].pos).distance_to(sp)
			if d < bd:
				bd = d
				bj = j
		slots[int(free[bj].id)] = sp
		free.remove_at(bj)
		i += 1
	var drift := float(P().get("reslot_drift", 2.0))
	for e in apcs:
		e.a7.rl.eng = int(t.id)
		e.a7.rl.tgt = int(wk.id)
		if not slots.has(int(e.id)) or (String(E.by) == "auto" and _held(w, e)):
			continue
		_go(w, e, slots[int(e.id)], minf(drift, 1.2) if Vector2(e.pos).distance_to(slots[int(e.id)]) > drift else drift)
	E.slots = slots
	if fxe != null and slots.has(int(fxe.id)) and Vector2(fxe.pos).distance_to(slots[int(fxe.id)]) <= 1.6 \
			and not bool(fxe.get("moving", false)) and Apc7._dome_ok(w, fxe):
		Apc7.set_dome(w, fxe, true)


static func _tick_eng(w: SimWorld, t: Dictionary) -> void:
	_limpets(w, t)
	if t.get("wd") != null:
		_tick_wd(w, t)
		return
	if t.get("resume_at") != null and w.tick >= int(t.resume_at):
		t.erase("resume_at")
		if t.has("mv_to") and t.get("eng") == null:
			move_team(w, t, t.mv_to, t.get("esc", []))
	if t.get("eng") == null:
		if t.dep != null or _lead_of(w, t) != null:
			return
		var cand = pincer_target(w, t, -1)
		if cand != null:
			start_eng(w, t, cand, "auto")
		return
	var E: Dictionary = t.eng
	var wk = w.entities.get(int(E.tgt))
	var apcs := _group_apcs(w, t)
	if wk == null:
		_end_eng(w, t, "killed")
		return
	if apcs.is_empty():
		t.eng = null
		return
	var far := true
	for a in apcs:
		if Vector2(a.pos).distance_to(wk.pos) <= float(P().get("detect", 12.0)) * 2.0:
			far = false
	if far:
		_end_eng(w, t, "lost")
		return
	var hpf := 0.0
	var ammo := 0
	for a in apcs:
		hpf += _frac(a)
		ammo += Apc7.attack_rounds_left(a)
	hpf /= float(apcs.size())
	if hpf < float(P().get("break_hp", 0.35)) or (ammo == 0 and _frac(wk) > 0.5 and not Apc7.is_down(wk)) or _stalled(w, E, wk):
		break_contact(w, t, wk.pos)
		return
	var fxe = w.entities.get(int(E.fix))
	if fxe == null or (_frac(fxe) < float(P().get("fixer_swap_hp", 0.3)) and apcs.size() > 1):
		_assign(w, t, wk, apcs, fxe)
	if w.tick >= int(E.reslot):
		E.reslot = w.tick + ticks(float(P().get("reslot_s", 2.0)))
		_place(w, t, wk, apcs)
	_volley(w, t, wk, apcs)
	if w.entities.has(int(wk.id)):
		_ops(w, t, wk)


## Time on target: every popped launcher of the group fires on the same tick, every pincer.volley_s.
static func _volley(w: SimWorld, t: Dictionary, wk: Dictionary, apcs: Array) -> void:
	var E: Dictionary = t.eng
	var down := Apc7.is_down(wk)
	if not down:
		E.dv = false
	if w.tick < int(E.volley) and not (down and not bool(E.get("dv", false))):   # it just went down: fire at once
		return
	if down:
		E.dv = true
	var stun := int(wk.get("emp_until", -1)) >= w.tick
	var marked := int(wk.get("cn_mark", -1)) >= w.tick
	var fired := 0
	for e in apcs:
		if not Apc7.can_fire(w, e, wk):
			continue
		var pref := ["tandem", "thermite"]
		if not down:
			if int(e.id) == int(E.fix):
				pref = ["tandem"] if stun else ["emp", "tandem"]
			elif not marked and int(e.a7.rl.rk.get("disruptor", 0)) > 0:
				pref.push_front("disruptor")
				marked = true
			elif not stun and int(e.a7.rl.rk.get("emp", 0)) > 0 and w.entities.get(int(E.fix)) == null:
				pref.push_front("emp")
		if pref[0] == "emp":
			stun = true
		if Apc7.fire_salvo(w, e, wk, pref) > 0:
			fired += 1
		if not w.entities.has(int(wk.id)):
			break
	if fired > 0:
		E.volley = w.tick + ticks(float(P().get("volley_s", 4.0)))
		E.volleys = int(E.volleys) + 1
		w.emit("CnVolley", {"team": int(t.id), "owner": int(t.fid), "target": int(wk.id), "apcs": fired, "down": down})


## Operators fight armour: they dismount once the walker is fixed (fixer in its face) and their APC is in reach;
## hunters tether it (net / harpoon: slowed + stagger) and plant limpets on the legs from the flank, the EMP
## grenadier closes to grenade range (stun window), the marksman puts nanite-disruptor rounds into the sensor eyes
## (sensors down + marked), the rest keep to the sheltered side of their APC. Strike security gunners run out with
## limpets while the walker lies toppled and get back in when it rises.
static func _ops(w: SimWorld, t: Dictionary, wk: Dictionary) -> void:
	var E: Dictionary = t.eng
	var O: Dictionary = R().get("ops_engage", {})
	var W: Vector2 = wk.pos
	var a := Vector2.from_angle(float(E.ax))
	var fxe = w.entities.get(int(E.fix))
	var fixed_ok := fxe != null and Vector2(fxe.pos).distance_to(W) <= float(P().get("fix_dist", 4.0)) + 2.5
	var down := Apc7.is_down(wk)
	for tt in _group_teams(w, t):
		var tac := String(tt.kind) == "tactical"
		for aid in tt.apcs:
			var c = w.entities.get(int(aid))
			if c == null or not c.has("cargo") or (c.cargo as Array).is_empty():
				continue
			if Vector2(c.pos).distance_to(W) > float(O.get("range", 10.0)) or (String(E.by) == "auto" and _held(w, c)):
				continue
			var ids := []
			var gn := 0
			for u in c.cargo:
				if tac:
					ids.append(int(u.id))
				elif down and role_of(u) == "gunner" and lim_left(u) > 0 and gn < int(O.get("gunners_per_apc", 2)) and not (E.gunners as Array).has(int(u.id)) 						and _gunners_out(w, E, c) + gn < int(O.get("gunners_per_apc", 2)) 						and Vector2(c.pos).distance_to(W) <= float(O.get("gunner_limpet_r", 6.0)):
					ids.append(int(u.id))
					u.cn_apc = int(c.id)
					gn += 1
			if ids.is_empty() or (tac and (not fixed_ok or bool(tt.get("ops_out", false)))):
				continue
			SimWorld.Transport.unload(w, c, ids, Vector2(c.pos), "cn_engage")
			_squad_touch(w)
			if tac:
				tt.ops_out = true
			else:
				E.gunners.append_array(ids)
			w.emit("CnOpsDismount", {"team": int(tt.id), "owner": int(tt.fid), "apc": int(c.id), "ids": ids, "target": int(wk.id)})
	if not down and not (E.gunners as Array).is_empty():   # it got up: the gunners get back in
		for gid in E.gunners:
			var g = w.entities.get(int(gid))
			if g != null:
				_board_own(w, t, g)
		E.gunners = []
	for tt in _group_teams(w, t):
		var out := String(tt.kind) == "tactical" and bool(tt.get("ops_out", false))
		for id in tt.members:
			var u = w.entities.get(int(id))
			if u == null:
				continue
			var role := role_of(u)
			if (out or (E.gunners as Array).has(int(id))) and not (String(E.by) == "auto" and _held(w, u)):
				_op_act(w, t, u, role, wk, a, O)


static func _board_own(w: SimWorld, t: Dictionary, u: Dictionary) -> void:
	var idx := 1 if String(u.get("cn_sq", "A")) == "B" and t.apcs.size() > 1 else 0
	var c = w.entities.get(int(t.apcs[idx]))
	if c == null or SimWorld.Transport.free_slots(c) <= 0:
		for aid in t.apcs:
			var o = w.entities.get(int(aid))
			if o != null and SimWorld.Transport.free_slots(o) > 0:
				c = o
				break
	if c != null:
		SimWorld.Transport.order_board(w, u, c)


static func _op_act(w: SimWorld, t: Dictionary, u: Dictionary, role: String, wk: Dictionary, a: Vector2, O: Dictionary) -> void:
	var W: Vector2 = wk.pos
	var s := 1.0 if int(u.id) % 2 == 0 else -1.0   # both flanks
	var d := Vector2(u.pos).distance_to(W)
	var ho := String(t.eng.get("mode", "")) == "head_on"
	match role:
		"hunter", "gunner":
			var hp: Dictionary = O.get("harpoon", {})
			if role == "hunter" and w.tick >= int(u.get("harp_cd", 0)) and d <= float(hp.get("range", 5.0)):
				u.harp_cd = w.tick + ticks(float(hp.get("cooldown_s", 18)))
				Apc7.tether(w, wk, float(hp.get("slow", 0.5)), float(hp.get("slow_s", 6)))
				Apc7.hit_heavy(w, u, wk, float(hp.get("damage", 4.0)), "at", float(hp.get("stagger", 1.5)))
				w.emit("CnHarpoon", {"id": int(u.id), "owner": int(u.owner), "target": int(wk.id), "from": u.pos, "to": W})
				if not w.entities.has(int(wk.id)):
					return
			var lm: Dictionary = O.get("limpet", {})
			var flank := a.rotated(deg_to_rad((25.0 if ho else 120.0) * s))
			if lim_left(u) <= 0:   # out of limpets: gunners get back in, hunters keep the tether on from range
				if role == "gunner":
					_board_own(w, t, u)
				else:
					_go(w, u, W + flank * 4.5)
			elif w.tick >= int(u.get("lim_cd", 0)):
				var reach := float(lm.get("reach", 1.6))
				if d <= reach:
					u.lim_cd = w.tick + ticks(float(lm.get("cooldown_s", 25)))
					u.lim_n = lim_left(u) - 1
					var off := Vector2(u.pos) - W
					if not t.has("limp"):
						t.limp = []
					t.limp.append({"at": w.tick + ticks(float(lm.get("fuse_s", 3.0))), "tgt": int(wk.id), "ox": snappedf(off.x, 0.001),
						"oy": snappedf(off.y, 0.001), "own": int(u.owner), "by": int(u.id)})
					w.emit("CnLimpetPlanted", {"id": int(u.id), "owner": int(u.owner), "target": int(wk.id), "pos": u.pos})
					# planting under a standing walker is the risky part: a stomp / kick (not while it is down or stunned)
					if not Apc7.is_down(wk) and int(wk.get("emp_until", -1)) < w.tick and w.rng.randf() < float(lm.get("stomp_chance", 0.0)):
						w.emit("WalkerStomp", {"id": int(wk.id), "target": int(u.id), "pos": u.pos})
						Apc7.Dmg().apply_hit(w, wk, u, {"damage": float(lm.get("stomp_dmg", 110)), "cls": "artillery", "weapon": ""}, true)
						if not w.entities.has(int(u.id)):
							return
					_go(w, u, W + flank * 6.0)
				else:
					_go(w, u, W + flank * (reach - 0.5), 0.4)
			else:
				_go(w, u, W + flank * 5.5)
		"marksman":
			var dr: Dictionary = O.get("disruptor", {})
			_go(w, u, W + a.rotated(deg_to_rad((15.0 if ho else 70.0) * s)) * (float(dr.get("range", 11.0)) - 2.0), 1.5)
			if w.tick >= int(u.get("dsr_cd", 0)) and d <= float(dr.get("range", 11.0)):
				u.dsr_cd = w.tick + ticks(float(dr.get("cooldown_s", 12)))
				Apc7.hit_heavy(w, u, wk, float(dr.get("damage", 12)), "at", float(dr.get("stagger", 0.2)))
				if w.entities.has(int(wk.id)):
					Apc7.mark(w, wk, float(dr.get("mark_s", 10)), float(dr.get("sensors", 25)))
				w.emit("CnDisruptorShot", {"id": int(u.id), "owner": int(u.owner), "target": int(wk.id), "from": u.pos, "to": W})
		"emp":
			_go(w, u, W + a.rotated(deg_to_rad((20.0 if ho else 95.0) * s)) * 4.0, 1.0)
		_:
			var c = null
			for aid in t.apcs + _team_apcs_of(w, u):
				c = w.entities.get(int(aid))
				if c != null:
					break
			if c != null:
				var away := Vector2(c.pos) - W
				_go(w, u, Vector2(c.pos) + (away.normalized() if away.length() > 0.1 else Vector2.RIGHT) * 1.6, 1.0)


## Strike gunners from APC c already out on the downed walker.
static func _gunners_out(w: SimWorld, E: Dictionary, c: Dictionary) -> int:
	var n := 0
	for gid in E.gunners:
		var g = w.entities.get(int(gid))
		if g != null and int(g.get("cn_apc", int(c.id))) == int(c.id):
			n += 1
	return n


## Limpets this soldier still carries (rules ops_engage.limpet.carry by role; refilled when the APC restocks).
static func lim_left(u: Dictionary) -> int:
	if u.has("lim_n"):
		return int(u.lim_n)
	return int(R().get("ops_engage", {}).get("limpet", {}).get("carry", {}).get(role_of(u), 0))


static func _team_apcs_of(w: SimWorld, u: Dictionary) -> Array:
	var tt = team(w, team_of(u))
	return [] if tt == null else tt.apcs


## Limpets stick to the walker and go off after the fuse (the hit side is where they were planted).
static func _limpets(w: SimWorld, t: Dictionary) -> void:
	if not t.has("limp") or (t.limp as Array).is_empty():
		return
	var lm: Dictionary = R().get("ops_engage", {}).get("limpet", {})
	var keep := []
	for L in t.limp:
		if w.tick < int(L.at):
			keep.append(L)
			continue
		var wk = w.entities.get(int(L.tgt))
		if wk == null:
			continue
		var src := {"id": -1, "kind": "unit", "owner": int(L.own), "pos": Vector2(wk.pos) + Vector2(float(L.ox), float(L.oy))}
		Apc7.hit_heavy(w, src, wk, float(lm.get("damage", 180)), String(lm.get("cls", "at")), float(lm.get("stagger", 3.0)))
		w.emit("CnLimpet", {"owner": int(L.own), "target": int(L.tgt), "pos": src.pos, "by": int(L.by)})
	t.limp = keep


static func _end_eng(w: SimWorld, t: Dictionary, result: String) -> void:
	var E: Dictionary = t.eng
	for a in _group_apcs(w, t):
		if a.a7.has("rl"):
			a.a7.rl.eng = -1
			a.a7.rl.tgt = -1
	for tt in _group_teams(w, t):
		if bool(tt.get("ops_out", false)):
			tt.ops_out = false
			remount(w, tt)
	for gid in E.gunners:
		var g = w.entities.get(int(gid))
		if g != null:
			_board_own(w, t, g)
	t.eng = null
	w.emit("CnPincerEnd", {"team": int(t.id), "owner": int(t.fid), "target": int(E.tgt), "result": result,
		"volleys": int(E.volleys), "ticks": w.tick - int(E.t0)})
	if result == "killed" and String(E.by) == "auto" and t.has("mv_to"):
		t.resume_at = w.tick + ticks(6.0)   # back on the road once everyone is aboard


## Break contact: everyone mounts under smoke, then the group pulls back as a formed group (formed_withdraw).
static func break_contact(w: SimWorld, t: Dictionary, from: Vector2) -> void:
	if t.get("eng") != null:
		_end_eng(w, t, "broke")
	t.erase("resume_at")
	for tt in _group_teams(w, t):
		remount(w, tt)
	for a in _group_apcs(w, t):
		if int(a.a7.st.get("smoke", 0)) > 0 and int(a.a7.smoke_until) < w.tick:
			Apc7.fire_panel(w, a, "smoke")
	t.wd = {"x": snappedf(from.x, 0.001), "y": snappedf(from.y, 0.001), "ph": "mount", "until": w.tick + ticks(6.0),
		"end": w.tick + ticks(float(R().get("withdraw", {}).get("break_s", 30)))}
	w.emit("CnBreakContact", {"team": int(t.id), "owner": int(t.fid), "from": from})


static func _tick_wd(w: SimWorld, t: Dictionary) -> void:
	var D: Dictionary = t.wd
	if String(D.ph) == "mount":
		var foot := 0
		for tt in _group_teams(w, t):
			for id in tt.members:
				foot += 1 if w.entities.has(int(id)) else 0
		if foot > 0 and w.tick < int(D.until):
			return
		var from := Vector2(float(D.x), float(D.y))
		var c := Vector2.ZERO
		var apcs := _group_apcs(w, t)
		for a in apcs:
			c += Vector2(a.pos)
		var back := (c / float(maxi(apcs.size(), 1))) - from if not apcs.is_empty() else -_threat_dir(w, t, from)
		formed_withdraw(w, _group_teams(w, t), from, back, float(R().get("withdraw", {}).get("break_dist", 12.0)), [], true)
		D.ph = "move"
	elif w.tick >= int(D.end):
		t.wd = null
		w.emit("CnWithdrawn", {"team": int(t.id), "owner": int(t.fid)})


## Formed withdrawal away from `from` along `back`: the APCs in a line across the axis (base + apc_back out), smoke
## on the threat side, the soldiers on foot in a block of rules.withdraw.cols columns right behind the hulls (the
## sheltered side), slots assigned in their current left-right order so nobody crosses the line. bk = fall back
## facing the enemy and keep firing (SquadAI ordered fall-back flag).
static func formed_withdraw(w: SimWorld, teams: Array, from: Vector2, back: Vector2, base: float, skip: Array, bk: bool = false) -> void:
	var D: Dictionary = R().get("withdraw", {})
	back = back.normalized() if back.length() > 0.01 else Vector2.RIGHT
	var perp := back.orthogonal()
	var apcs := []
	var foot := []
	for tt in teams:
		for aid in tt.apcs:
			var a = w.entities.get(int(aid))
			if a != null:
				apcs.append(a)
		for id in tt.members:
			var u = w.entities.get(int(id))
			if u != null and not skip.has(int(id)):
				foot.append(u)
	var by_perp := func(x, y):
		var px := Vector2(x.pos).dot(perp)
		var py := Vector2(y.pos).dot(perp)
		return px < py or (px == py and int(x.id) < int(y.id))
	apcs.sort_custom(by_perp)
	foot.sort_custom(by_perp)
	var n := apcs.size()
	var ab := base + float(D.get("apc_back", 2.5))
	for i in n:
		var a: Dictionary = apcs[i]
		SimWorld.Movement.order_move(w, a, _post(w, from + back * ab + perp * ((float(i) - float(n - 1) * 0.5) * float(D.get("apc_gap", 2.5)))))
		a.order.sq = "cn"
		if int(a.a7.st.get("smoke", 0)) > 0 and int(a.a7.smoke_until) < w.tick:
			Apc7.fire_panel(w, a, "smoke")
	var cols := maxi(int(D.get("cols", 5)), 1)
	var fb := ab + float(D.get("foot_back", 1.6))
	for i in foot.size():
		var row := i / cols
		var in_row := mini(cols, foot.size() - row * cols)
		var col := i % cols
		var p := from + back * (fb + float(row) * float(D.get("row_gap", 0.9))) \
			+ perp * ((float(col) - float(in_row - 1) * 0.5) * float(D.get("col_gap", 1.0)))
		var u: Dictionary = foot[i]
		SimWorld.Movement.order_move(w, u, _post(w, p))
		u.order.sq = "cn"
		if bk:
			u.order.bk = true
	w.emit("CnFormedWithdraw", {"owner": int(teams[0].fid) if not teams.is_empty() else -1, "from": from, "back": back,
		"apcs": n, "foot": foot.size()})
