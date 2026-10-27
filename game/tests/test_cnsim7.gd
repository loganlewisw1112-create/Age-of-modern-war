extends "res://tests/test_base.gd"
## G7 acceptance (owner: CNSIM7). Master scope 6.3-6.8: counter-nanite strike team, operators, APCs, packages.

const CN = preload("res://sim/systems/counter_nanite.gd")
const Apc7 = preload("res://sim/systems/apc7.gd")
const Movement = preload("res://sim/systems/movement.gd")


func _ensure_g7() -> void:
	if Content.unit("g7_cn_strike_apc").is_empty():
		Content._merge_fragment_dir("res://content/g7")


## Inert 2-side world with a 48x36 GRASS arena; returns [w, arena origin].
func _setup(sd: int = 0) -> Array:
	var ov := {} if sd == 0 else {"seed": sd}
	var w := make_world(ov)
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var o := Vector2i(mw / 2 - 24, int(w.map.h) / 2 - 18)
	var r := Rect2i(o, Vector2i(48, 36))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.grow(16).has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	Movement.rebuild_nav(w)
	return [w, Vector2(o) + Vector2(0.5, 0.5)]


## Validate + apply directly (works before ORCH registers the command names).
func _cmd(w: SimWorld, sys, fid: int, cmd: Dictionary) -> String:
	cmd.issuer = fid
	var r: String = sys.validate_command(w, cmd)
	if r == "":
		sys.apply_command(w, cmd)
	return r


func _run(w: SimWorld, n: int, types: Array = []) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.is_empty() or types.has(String(ev.type)):
				out.append(ev)
	return out


func _has(evs: Array, type: String) -> bool:
	for ev in evs:
		if String(ev.type) == type:
			return true
	return false


func _roles(w: SimWorld, t: Dictionary) -> Dictionary:
	var out := {}
	for id in t.members:
		var r := CN.role_of(CN.find(w, int(id)))
		out[r] = int(out.get(r, 0)) + 1
	return out


func _on_map(w: SimWorld, t: Dictionary) -> int:
	var n := 0
	for id in t.members:
		if w.entities.has(int(id)):
			n += 1
	return n


func test_team_composition_and_succession() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var res := CN.spawn_team(w, 0, "strike_team", s[1] + Vector2(10, 10))
	check_eq(res.apcs.size(), 2, "strike team = 2 APCs")
	check_eq(res.members.size(), 20, "strike team = 20 soldiers")
	var t: Dictionary = CN.team(w, int(res.team))
	check_eq(_roles(w, t), {"leader": 1, "second": 2, "deploy": 4, "scanner": 2, "ew": 2, "gunner": 7, "medic": 2}, "role table 6.4")
	check_eq(t.squads.A.size(), 10, "squad A = 10")
	check_eq(t.squads.B.size(), 10, "squad B = 10")
	check_eq(CN.role_of(CN.find(w, int(t.leader))), "leader", "one team leader")
	check(t.squads.A.has(int(t.leader)), "the leader is in squad A")
	var lead := 0
	for id in t.members:
		if bool(CN.find(w, int(id)).get("cn_lead", false)):
			lead += 1
	check_eq(lead, 1, "exactly one leader flag")
	# the leader falls -> squad A's second-in-command; then squad B's
	var a: Dictionary = w.entities[int(t.apcs[0])]
	Apc7.kill_cargo(w, a, CN.find(w, int(t.leader)), "test")
	var evs := _run(w, 12, ["CnLeaderChange"])
	check(_has(evs, "CnLeaderChange"), "leader change announced")
	check_eq(CN.role_of(CN.find(w, int(t.leader))), "second", "squad A second takes over")
	check(t.squads.A.has(int(t.leader)), "successor from squad A")
	Apc7.kill_cargo(w, a, CN.find(w, int(t.leader)), "test")
	_run(w, 12)
	check(t.squads.B.has(int(t.leader)) and CN.role_of(CN.find(w, int(t.leader))) == "second", "then squad B second")
	# Human B uses its own defs
	w.factions[1].faction_def = "human_b"
	var rb := CN.spawn_team(w, 1, "strike_team", s[1] + Vector2(30, 10))
	check(String(w.entities[int(rb.apcs[0])].def) == "g7_b_cn_strike_apc", "Human B strike APC def")
	w.factions[1].faction_def = "machine"
	check(CN.spawn_team(w, 1, "strike_team", s[1]).is_empty(), "Machine cannot field the line")


func test_spawn_inside_dismount_remount_and_pair() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var res := CN.spawn_team(w, 0, "strike_team", s[1] + Vector2(12, 12))
	var t: Dictionary = CN.team(w, int(res.team))
	check_eq(_on_map(w, t), 0, "soldiers spawn inside the APCs")
	for aid in t.apcs:
		check_eq((w.entities[int(aid)].cargo as Array).size(), 10, "10 aboard each strike APC")
	check_eq(_cmd(w, CN, 0, {"type": "cn_dismount", "team_id": int(t.id)}), "", "dismount valid")
	check_eq(_on_map(w, t), 20, "all 20 dismounted")
	check_eq(_cmd(w, CN, 0, {"type": "cn_mount", "team_id": int(t.id)}), "", "remount valid")
	_run(w, 200)
	check_eq(_on_map(w, t), 0, "all 20 remounted")
	# pair: a lone move on one APC pulls the partner along
	var a: Dictionary = w.entities[int(t.apcs[0])]
	var b: Dictionary = w.entities[int(t.apcs[1])]
	Movement.order_move(w, a, s[1] + Vector2(40, 12))
	_run(w, 60)
	check(String(b.order.get("type", "")) == "move" or Vector2(b.pos).distance_to(s[1] + Vector2(12, 14.5)) > 2.0, "partner follows")
	# pair-only: losing one strike APC blocks deployment
	w.destroy(int(t.apcs[1]), "test")
	var r := _cmd(w, CN, 0, {"type": "cn_deploy", "team_id": int(t.id), "target": a.pos, "package": "purge"})
	check(r.contains("full pair"), "deploy needs the full pair (%s)" % r)


func test_tactical_cap() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	for i in 3:
		var r := CN.spawn_team(w, 0, "tactical_squad", s[1] + Vector2(5 + 6 * i, 5))
		check_eq(r.members.size(), 8, "tactical squad = 8")
		check_eq((w.entities[int(r.apcs[0])].cargo as Array).size(), 8, "8 inside the tactical APC")
	check(CN.spawn_team(w, 0, "tactical_squad", s[1] + Vector2(30, 5)).is_empty(), "4th squad refused (cap 3)")
	check(CN.tac_reason(w, 0) != "", "cap reason")
	var t: Dictionary = CN.team(w, 1)
	check_eq(_roles(w, t), {"op_leader": 1, "marksman": 1, "hunter": 2, "emp": 1, "antidrone": 1, "purge": 1, "op_medic": 1}, "operator roles 6.6")
	CN.set_tac_cap(w, 0, -1)   # Last Protocol lifts it
	check(not CN.spawn_team(w, 0, "tactical_squad", s[1] + Vector2(30, 5)).is_empty(), "cap hook lifts it")


func test_unhackable_and_no_main_weapon() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var res := CN.spawn_team(w, 0, "strike_team", s[1] + Vector2(12, 12))
	var a: Dictionary = w.entities[int(res.apcs[0])]
	check(Apc7.unhackable(a), "strike APC unhackable")
	var ew = load("res://sim/systems/machine_ew7.gd")
	if ew != null and Apc7.callf(ew, "can_hack", [a, w], null) != null:
		check(not bool(ew.can_hack(a, w)), "Machine can_hack refuses the strike APC")
	check(not Apc7.has_main_weapon("g7_cn_strike_apc"), "no main weapon on the strike APC")
	check_eq(String(Content.weapon(String(Content.unit("g7_cn_strike_apc").weapon)).get("class", "")), "small_arms", "its only gun is the .50 pair")
	_run(w, 2)
	check_eq(int(a.a7.manned), 2, "two mounts manned by security gunners")
	var front := int(a.a7.mg.front)
	var gun = null
	for u in a.cargo:
		if int(u.id) == front:
			gun = u
	Apc7.kill_cargo(w, a, gun, "test")
	var evs := _run(w, 2, ["MountGunnerSwap"])
	check(_has(evs, "MountGunnerSwap") and int(a.a7.mg.front) != front, "a hit gunner is replaced from inside")
	var gunners := []
	for u in a.cargo:
		if CN.role_of(u) == "gunner":
			gunners.append(u)
	for u in gunners:
		Apc7.kill_cargo(w, a, u, "test")
	_run(w, 2)
	check_eq(int(a.a7.manned), 0, "no gunner aboard")
	check(Apc7.callf(SimWorld.HotState, "get_cd", [w, int(a.id)], 0) >= 1, "unmanned mounts hold fire")


func test_dome_aps_emp_panels() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var res := CN.spawn_team(w, 0, "strike_team", s[1] + Vector2(12, 12))
	var a: Dictionary = w.entities[int(res.apcs[0])]
	var src := {"id": -1, "owner": 1, "pos": a.pos + Vector2(6, 0)}
	check(Apc7.damage_mult(w, src, {"dmg": 50.0}, a) == 1.0, "no dome yet: full damage")
	check_eq(_cmd(w, Apc7, 0, {"type": "cn_dome", "unit_ids": [int(a.id)], "on": true}), "", "dome up while stopped")
	check(Apc7.dome_up(a), "dome is up")
	var c0 := float(a.a7.dome)
	check(Apc7.damage_mult(w, src, {"dmg": 100.0}, a) == 0.0 and is_equal_approx(float(a.a7.dome), c0 - 100.0), "dome absorbs a hit on the APC")
	CN.dismount(w, CN.team(w, int(res.team)))
	var inside = null
	for id in CN.team(w, int(res.team)).members:
		var u = w.entities.get(int(id))
		if u != null and Vector2(u.pos).distance_to(a.pos) <= 3.5:
			inside = u
			break
	check(inside != null and Apc7.damage_mult(w, src, {"dmg": 10.0}, inside) == 0.0, "dome covers soldiers inside it")
	var far := w.spawn_unit("rifleman", 0, s[1] + Vector2(40, 30))
	check(Apc7.damage_mult(w, src, {"dmg": 10.0}, w.entities[far]) == 1.0, "outside the dome: full damage")
	var evs := []
	Apc7.absorb(w, a, 99999.0)
	check(not Apc7.dome_up(a) and int(a.a7.dome_cd) > w.tick, "dome breaks at 0 and recharges")
	check(_cmd(w, Apc7, 0, {"type": "cn_dome", "unit_ids": [int(a.id)], "on": true}) != "", "no dome while recharging")
	# active protection
	var aps0 := int(a.a7.aps)
	check(Apc7.shot_blocked(w, src, {"cls": "at"}, a, a.pos), "APS stops an anti-tank shot")
	check_eq(int(a.a7.aps), aps0 - 1, "one APS charge spent")
	check(not Apc7.shot_blocked(w, src, {"cls": "small_arms"}, a, a.pos), "APS ignores small arms")
	check(Apc7.intercept_strike(w, 1, a.pos, "missile"), "APS intercepts a strike")
	a.a7.aps = 0
	check(not Apc7.shot_blocked(w, src, {"cls": "at"}, a, a.pos), "no charges: the shot lands")
	# EMP pulse
	var mw := w.spawn_unit("m_walker", 1, a.pos + Vector2(1.5, 0))
	check_eq(_cmd(w, Apc7, 0, {"type": "cn_emp", "unit_ids": [int(a.id)]}), "", "EMP pulse")
	check(int(w.entities[mw].get("emp_until", -1)) > w.tick, "enemy machine disabled by the pulse")
	check(int(a.get("emp_until", -1)) < w.tick, "the APC itself is immune")
	check(_cmd(w, Apc7, 0, {"type": "cn_emp", "unit_ids": [int(a.id)]}).contains("recharging"), "EMP cooldown")
	# side panels and stock
	for i in 4:
		check_eq(_cmd(w, Apc7, 0, {"type": "cn_panels", "unit_ids": [int(a.id)], "kind": "smoke"}), "", "smoke %d" % i)
	check(_cmd(w, Apc7, 0, {"type": "cn_panels", "unit_ids": [int(a.id)], "kind": "smoke"}).contains("Out of smoke"), "smoke stock runs out")
	check_eq(_cmd(w, Apc7, 0, {"type": "cn_panels", "unit_ids": [int(a.id)], "kind": "interceptors"}), "", "interceptors")
	check(int(a.a7.icpt_until) > w.tick, "interceptor window")
	a.a7.aps = 0
	check(Apc7.shot_blocked(w, src, {"cls": "at"}, a, a.pos), "panel interceptors stop a shot with APS empty")
	check_eq(_cmd(w, Apc7, 0, {"type": "cn_panels", "unit_ids": [int(a.id)], "kind": "idrones"}), "", "interceptor drones")
	var st: Dictionary = w.sys_state.apc7
	check_eq(st.drones.size(), 2, "2 interceptor drones up")
	for k in st.drones.keys():
		st.drones[k] = w.tick + 1
	_run(w, 3)
	check_eq(st.drones.size(), 0, "drones expire")
	Apc7.restock(w, a)
	check_eq(int(a.a7.st.smoke), 4, "restocked at the facility")


func _deploy_world(sd: int = 0) -> Array:
	var s := _setup(sd)
	var w: SimWorld = s[0]
	var site: Vector2 = s[1] + Vector2(20, 18)
	var res := CN.spawn_team(w, 0, "strike_team", site + Vector2(-2, -1))
	return [w, CN.team(w, int(res.team)), site]


func test_loadout_locked_in_field() -> void:
	var d := _deploy_world()
	var w: SimWorld = d[0]
	var t: Dictionary = d[1]
	check_eq(CN.loadout(w, int(t.id)).size(), 2, "both APCs carry packages")
	check_eq(_cmd(w, CN, 0, {"type": "cn_set_loadout", "team_id": int(t.id), "packages": ["core_breaker", "purge", "purge", "seed_hunter", "barrier", "purge"]}), "", "loadout at the facility")
	var lo := CN.loadout(w, int(t.id))
	check_eq(lo[int(t.apcs[0])], ["core_breaker", "purge", "purge"], "APC A filled to capacity (core-breaker = 2)")
	check(_cmd(w, CN, 0, {"type": "cn_set_loadout", "team_id": int(t.id), "packages": ["core_breaker", "core_breaker", "core_breaker", "core_breaker", "core_breaker"]}).contains("Too many"), "capacity enforced")
	for aid in t.apcs:
		SimWorld.HotState.set_pos(w, int(aid), Vector2(w.entities[int(aid)].pos) + Vector2(-20, 0))
	_run(w, 12)
	check(bool(t.locked), "loadout locks in the field")
	check(_cmd(w, CN, 0, {"type": "cn_set_loadout", "team_id": int(t.id), "packages": ["purge"]}).contains("locked"), "no field swaps")
	CN.unlock_loadout(w, int(t.id))
	check(not bool(t.locked), "facility unlocks it")


func test_deployment_sequence_and_hold() -> void:
	var d := _deploy_world()
	var w: SimWorld = d[0]
	var t: Dictionary = d[1]
	var site: Vector2 = d[2]
	check_eq(_cmd(w, CN, 0, {"type": "cn_deploy", "team_id": int(t.id), "target": site, "package": "purge"}), "", "deploy valid")
	var evs := _run(w, 700, ["CnDismount", "CnDeployPhase", "CnHoldSetup", "CnPurge", "CnHoldPacked", "CnDeployStalled", "ApcDome"])
	var phases := []
	for ev in evs:
		if String(ev.type) == "CnDeployPhase":
			phases.append(String(ev.phase))
	check_eq(phases, ["jam", "arm"], "scan -> jam -> arm")
	check(_has(evs, "CnDismount"), "team dismounted at the site")
	check(_has(evs, "ApcDome"), "crew raised the dome to arm")
	check(_has(evs, "CnHoldSetup"), "engineers set up the hold by themselves")
	check(_has(evs, "CnPurge"), "package went off")
	check(_has(evs, "CnHoldPacked"), "hold packed up afterwards")
	check(not _has(evs, "CnDeployStalled"), "no stall with everyone alive")
	var n := 0
	for kinds in CN.loadout(w, int(t.id)).values():
		n += (kinds as Array).count("purge")
	check_eq(n, 3, "one purge package used")


func test_deployment_stalls() -> void:
	var d := _deploy_world()
	var w: SimWorld = d[0]
	var t: Dictionary = d[1]
	_cmd(w, CN, 0, {"type": "cn_deploy", "team_id": int(t.id), "target": d[2], "package": "purge"})
	var dis := false
	for i in 400:   # the drill parks both APCs at the site first, then dismounts
		if _has(_run(w, 1, ["CnDismount"]), "CnDismount"):
			dis = true
			break
	_run(w, 2)
	check(dis, "the team dismounts at the site after parking")
	for id in t.members:
		if w.entities.has(int(id)) and CN.role_of(w.entities[int(id)]) == "scanner":
			w.destroy(int(id), "test")
	var evs := _run(w, 200, ["CnDeployStalled", "CnPurge"])
	check(_has(evs, "CnDeployStalled") and String(t.dep.stalled) == "no_scanner", "dead scanners stall it")
	check(not _has(evs, "CnPurge"), "no purge while stalled")
	var d2 := _deploy_world()
	var w2: SimWorld = d2[0]
	var t2: Dictionary = d2[1]
	for aid in t2.apcs:
		w2.entities[int(aid)].a7.dome = 0.0
		w2.entities[int(aid)].a7.dome_cd = 1000000
	_cmd(w2, CN, 0, {"type": "cn_deploy", "team_id": int(t2.id), "target": d2[2], "package": "purge"})
	evs = _run(w2, 400, ["CnDeployStalled", "CnPurge"])
	check(t2.dep != null and String(t2.dep.stalled) == "dome_down", "dome failing stalls arming")
	check(not _has(evs, "CnPurge"), "no purge without the dome")


func test_hero_detonation() -> void:
	var d := _deploy_world()
	var w: SimWorld = d[0]
	var t: Dictionary = d[1]
	for aid in t.apcs:
		w.entities[int(aid)].a7.dome = 0.0
		w.entities[int(aid)].a7.dome_cd = 1000000
	_cmd(w, CN, 0, {"type": "cn_deploy", "team_id": int(t.id), "target": d[2], "package": "purge"})
	_run(w, 400)
	check(t.dep != null and String(t.dep.stalled) == "dome_down", "package cannot arm (dome down)")
	var evs := []
	check_eq(_cmd(w, CN, 0, {"type": "cn_hero_detonate", "team_id": int(t.id)}), "", "hero order valid")
	var hid := int(t.dep.hero)
	check(hid >= 0 and CN.role_of(w.entities[hid]) == "deploy", "a deployment specialist stays")
	evs = _run(w, 160, ["CnPurge", "CnRemembered"])
	check(_has(evs, "CnPurge") and _has(evs, "CnRemembered"), "instant arming, it goes off after the window")
	check(not w.entities.has(hid) and not CN.alive(w, hid), "certain death")
	var rem: Array = w.sys_state.cn7.remembered
	check(rem.size() == 1 and String(rem[0].call_sign).begins_with(String(t.name)), "call sign kept for Remembered")
	check(CN.live_members(w, t).size() >= 17, "the rest got clear (%d alive)" % CN.live_members(w, t).size())


func test_suit_puncture_and_exposure() -> void:
	var d := _deploy_world()
	var w: SimWorld = d[0]
	var t: Dictionary = d[1]
	CN.dismount(w, t)
	_run(w, 10)
	var e: Dictionary = w.entities[int(t.squads.B[1])]
	check(not bool(e.get("wpunct", false)) and float(e.get("cn_exp", 0.0)) == 0.0, "sealed suit: no exposure")
	SimWorld.HotState.set_hp(w, int(e.id), float(e.hp) - 15.0)
	var evs := _run(w, 10, ["SuitPunctured"])
	check(bool(e.get("wpunct", false)) and _has(evs, "SuitPunctured"), "a hit punctures the suit")
	_run(w, 200)
	check(float(e.get("cn_exp", 0.0)) > 0.0 and float(e.get("cn_slow", 1.0)) < 1.0, "punctured: exposure builds and slows")
	check(bool(w.sys_state.g7v[int(e.id)].sb), "breached-suit render field")
	CN.decontaminate(w, e)
	check(not e.has("cn_exp") and not bool(e.get("wpunct", false)), "decon clears exposure and repairs the suit")
	var other: Dictionary = w.entities[int(t.squads.B[2])]
	check(float(other.get("cn_exp", 0.0)) == 0.0, "unhit suits stay clean")


func test_one_order_moves_the_motorcade() -> void:
	var d := _deploy_world()
	var w: SimWorld = d[0]
	var t: Dictionary = d[1]
	var tac := CN.spawn_team(w, 0, "tactical_squad", d[2] + Vector2(-8, 3))
	var goal: Vector2 = d[2] + Vector2(18, 10)
	check_eq(_cmd(w, CN, 0, {"type": "cn_move", "team_id": int(t.id), "target": goal, "escort_teams": [int(tac.team)]}), "", "cn_move valid")
	check(int(t.conv) >= 0, "SQUAD7 convoy formed (strike APCs core, tactical APC escort)")
	var a: Dictionary = w.entities[int(t.apcs[0])]
	var p0: Vector2 = a.pos
	_run(w, 200)
	check(Vector2(a.pos).distance_to(goal) < p0.distance_to(goal) - 3.0, "the strike APC moved toward the goal")
	var e: Dictionary = w.entities[int(tac.apcs[0])]
	check(Vector2(e.pos).distance_to(goal) < (d[2] + Vector2(-8, 3)).distance_to(goal) - 3.0, "the escort moved too")


func _scenario_hash(sd: int) -> String:
	var d := _deploy_world(sd)
	var w: SimWorld = d[0]
	var t: Dictionary = d[1]
	CN.spawn_team(w, 0, "tactical_squad", d[2] + Vector2(-6, 4))
	_cmd(w, CN, 0, {"type": "cn_deploy", "team_id": int(t.id), "target": d[2], "package": "purge"})
	w.spawn_unit("m_walker", 1, d[2] + Vector2(9, 0))
	_run(w, 300)
	return w.state_hash()


func test_determinism_and_unused_is_free() -> void:
	check_eq(_scenario_hash(7), _scenario_hash(7), "same seed twice = same hash")
	var a: SimWorld = _setup(5)[0]
	var b: SimWorld = _setup(5)[0]
	for i in 200:
		a.step()
		b.step()
		CN.tick(b)     # extra passes must be no-ops when the line is unused
		Apc7.tick(b)
	check(not a.sys_state.has("cn7") and not a.sys_state.has("apc7"), "no counter-nanite state without the unlock")
	check_eq(a.state_hash(), b.state_hash(), "a match without the line is unchanged by these systems")


func test_sim_cost_full_group() -> void:
	var base: SimWorld = _setup(9)[0]
	var d := _deploy_world(9)
	var w: SimWorld = d[0]
	for i in 3:
		CN.spawn_team(w, 0, "tactical_squad", d[2] + Vector2(-8 + 4 * i, 6))
	_cmd(w, CN, 0, {"type": "cn_deploy", "team_id": int(d[1].id), "target": d[2], "package": "purge"})
	var t0 := Time.get_ticks_usec()
	_run(base, 300)
	var t1 := Time.get_ticks_usec()
	_run(w, 300)
	var t2 := Time.get_ticks_usec()
	var t3 := Time.get_ticks_usec()
	for i in 300:
		CN.tick(w)
		Apc7.tick(w)
	var t4 := Time.get_ticks_usec()
	print("CNSIM7_COST base_300=%.1fms group_300=%.1fms cn_apc7_systems_300=%.3fms (strike team + 3 tactical squads, 44 soldiers, 5 APCs)" % [
		(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t4 - t3) / 1000.0])
	check(true, "cost reported")


func test_deploy_drill_posts_withdrawal_and_crew_smoke() -> void:
	var d := _deploy_world()
	var w: SimWorld = d[0]
	var t: Dictionary = d[1]
	var site: Vector2 = d[2]
	for aid in t.apcs:
		w.entities[int(aid)].a7.dome = 0.0   # arming stalls (dome down) so the posts can be checked, then the hero
		w.entities[int(aid)].a7.dome_cd = 1000000
	check_eq(_cmd(w, CN, 0, {"type": "cn_deploy", "team_id": int(t.id), "target": site, "package": "purge"}), "", "deploy")
	var dis := false
	for i in 400:
		if _has(_run(w, 1, ["CnDismount"]), "CnDismount"):
			dis = true
			break
	check(dis, "dismounts after parking")
	for aid in t.apcs:
		check(Vector2(w.entities[int(aid)].pos).distance_to(site) <= 4.0, "strike APC parked at the site")
	_run(w, 200)
	var inner := 0
	var ring := 0
	for id in t.members:
		var u = w.entities.get(int(id))
		if u == null:
			continue
		var dd := Vector2(u.pos).distance_to(site)
		match CN.role_of(u):
			"scanner", "ew", "deploy":
				inner += 1 if dd <= 2.5 else 0
			"gunner":
				ring += 1 if dd >= 3.8 and dd <= 6.8 else 0
	check(inner >= 8, "specialists at the arming point (%d/10)" % inner)
	check(ring >= 5, "security gunners in the perimeter ring (%d/7)" % ring)
	var alive0 := CN.live_members(w, t).size()
	check_eq(_cmd(w, CN, 0, {"type": "cn_hero_detonate", "team_id": int(t.id)}), "", "hero")
	var evs := _run(w, 200, ["CnPurge"])
	check(_has(evs, "CnPurge"), "blast")
	check_eq(CN.live_members(w, t).size(), alive0 - 1, "only the hero dies: the rest withdrew out of the blast")
	var a: Dictionary = w.entities[int(t.apcs[0])]
	var s0 := int(a.a7.st.get("smoke", 0))
	SimWorld.HotState.set_hp(w, int(a.id), float(a.hp) - 40.0)
	evs = _run(w, 3, ["ApcPanel"])
	check(_has(evs, "ApcPanel") and int(a.a7.st.smoke) == s0 - 1 and int(a.a7.smoke_until) > w.tick, "a hit APC pops smoke by itself")
	SimWorld.HotState.set_hp(w, int(a.id), float(a.hp) - 40.0)
	_run(w, 3)
	check_eq(int(a.a7.st.smoke), s0 - 1, "no second smoke while the cloud stands")
