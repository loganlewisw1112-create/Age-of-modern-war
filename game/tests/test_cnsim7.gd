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
	check_eq(lo[int(t.apcs[1])], ["purge", "seed_hunter", "barrier"], "split loadout: APC B carries a purge too")
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
	_run(w, maxi(int(a.a7.smoke_until) + 6 * 20 + 2 - w.tick, 0))   # the withdrawal smoke (formed withdrawal) clears first
	var s0 := int(a.a7.st.get("smoke", 0))
	SimWorld.HotState.set_hp(w, int(a.id), float(a.hp) - 40.0)
	evs = _run(w, 3, ["ApcPanel"])
	check(_has(evs, "ApcPanel") and int(a.a7.st.smoke) == s0 - 1 and int(a.a7.smoke_until) > w.tick, "a hit APC pops smoke by itself")
	SimWorld.HotState.set_hp(w, int(a.id), float(a.hp) - 40.0)
	_run(w, 3)
	check_eq(int(a.a7.st.smoke), s0 - 1, "no second smoke while the cloud stands")


# ================================================================ CNSIM7-3: launcher, pincer, topple, operators, withdrawal
func _bare_apc(w: SimWorld, def: String, pos: Vector2) -> Dictionary:
	var a: Dictionary = w.entities[w.spawn_unit(def, 0, pos)]
	Apc7.init_apc(w, a)
	return a


func _walker(w: SimWorld, pos: Vector2, facing: float) -> Dictionary:
	var k: Dictionary = w.entities[w.spawn_unit("m_walker", 1, pos)]
	k.facing = facing
	return k


## Steps until wid is gone (or n ticks); [ticks, events of `types`].
func _until_dead(w: SimWorld, wid: int, n: int, types: Array) -> Array:
	var evs := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.has(String(ev.type)):
				evs.append(ev)
		if not w.entities.has(wid):
			return [i + 1, evs]
	return [n, evs]


func test_lone_apc_launcher_cannot_solo_a_heavy_walker() -> void:
	var s := _setup(3)
	var w: SimWorld = s[0]
	var c: Vector2 = s[1] + Vector2(24, 18)
	var k := _walker(w, c, PI)
	var a := _bare_apc(w, "g7_op_tactical_apc", c + Vector2(-7, 0))
	var seen_pop := false
	var evs := []
	for i in 3600:   # 3 minutes, the whole rocket stock
		w.step()
		for ev in w.events:
			if ["RocketSalvo", "ApcLauncher", "WalkerToppled"].has(String(ev.type)):
				evs.append(ev)
		var g = w.sys_state.get("g7v", {}).get(int(a.id), {})
		seen_pop = seen_pop or int(g.get("rl", 0)) >= 2
	var salvos := 0
	for ev in evs:
		salvos += 1 if String(ev.type) == "RocketSalvo" else 0
	check(seen_pop, "the launcher popped up (g7v rl popped / firing)")
	check(salvos >= 6, "it fired salvos (%d)" % salvos)
	check(Apc7.rockets_left(a) < 18, "rockets spent (%d left)" % Apc7.rockets_left(a))
	check(w.entities.has(int(k.id)), "a lone APC cannot solo a heavy walker")
	if w.entities.has(int(k.id)):
		print("CNSIM7_LONE walker hp %.0f / 950 after 180 s, salvos %d" % [float(k.hp), salvos])
		check(float(k.hp) < 950.0, "but it put some hurt on it")
	check(not _has(evs, "WalkerToppled"), "a straight-on fight does not topple it")


## 5 bare APCs vs one heavy walker: all in its front arc (head-on) vs one fixer in its face + 4 on the flanks / rear.
func _five_apcs(sd: int, pincer: bool) -> Array:
	return _five_apcs_def(sd, pincer, "m_walker")


func _five_apcs_def(sd: int, pincer: bool, def: String) -> Array:
	var dbg := {}
	var s := _setup(sd)
	var w: SimWorld = s[0]
	var c: Vector2 = s[1] + Vector2(24, 18)
	var k: Dictionary = w.entities[w.spawn_unit(def, 1, c)]
	k.facing = PI
	if pincer:
		_bare_apc(w, "g7_op_tactical_apc", c + Vector2(-4, 0))
		for deg in [110, -110, 150, -150]:
			_bare_apc(w, "g7_op_tactical_apc", c + Vector2(-6, 0).rotated(deg_to_rad(float(deg))))
	else:
		for off in [Vector2(-6.5, -2), Vector2(-6.5, 0), Vector2(-6.5, 2), Vector2(-8.5, -1), Vector2(-8.5, 1)]:
			_bare_apc(w, "g7_op_tactical_apc", c + off)   # all inside its front arc whichever of them it turns to
	var r := _until_dead(w, int(k.id), 3600, ["WalkerToppled", "WalkerBlownUp", "RocketSalvo", "Damage"])
	for ev in r[1]:
		if String(ev.type) == "Damage" and int(ev.target) == int(k.id):
			var key := "%d_%s" % [int(ev.shooter), String(ev.get("hit_side", ""))]
			dbg[key] = snappedf(float(dbg.get(key, 0.0)) + float(ev.amount), 0.1)
	print("CNSIM7_DBG %s pincer=%s dmg_by_shooter=%s hp_def=%s" % [def, pincer, dbg, Content.unit(def).get("hp")])
	return [r[0], r[1], w, k]


func test_pincer_kills_much_faster_than_head_on_and_topples() -> void:
	var ho := _five_apcs(4, false)
	var pi := _five_apcs(4, true)
	var co := _five_apcs_def(4, true, "m_colossus")
	print("CNSIM7_TTK m_colossus pincer=%d ticks (%s)" % [int(co[0]), "killed" if not co[2].entities.has(int(co[3].id)) else "ALIVE hp %.0f" % float(co[3].hp)])
	print("CNSIM7_TTK head_on=%d ticks (%s) pincer=%d ticks" % [int(ho[0]), "killed" if not ho[2].entities.has(int(ho[3].id)) else "ALIVE hp %.0f" % float(ho[3].hp), int(pi[0])])
	check(not pi[2].entities.has(int(pi[3].id)), "the pincer kills the heavy walker")
	check(_has(pi[1], "WalkerToppled"), "flank / rear leg hits while it is fixed topple it")
	check(not _has(ho[1], "WalkerToppled"), "straight-on fire builds almost no stagger: no topple")
	check(int(pi[0]) * 3 <= int(ho[0]), "the pincer is at least 3x faster than the same 5 APCs head-on (%d vs %d ticks)" % [int(pi[0]), int(ho[0])])
	check(int(ho[0]) >= 600, "head-on stays a sustained engagement (>= 30 s, got %d ticks)" % int(ho[0]))


func test_topple_window_bonus_damage_and_righting() -> void:
	var s := _setup(5)
	var w: SimWorld = s[0]
	var c: Vector2 = s[1] + Vector2(24, 18)
	var k := _walker(w, c, PI)
	var fixer := _bare_apc(w, "g7_op_tactical_apc", c + Vector2(-4, 0))
	var flank := _bare_apc(w, "g7_op_tactical_apc", c + Vector2(0, 6))
	var front := _bare_apc(w, "g7_op_tactical_apc", c + Vector2(-5, 1))
	for a in [fixer, flank, front]:
		a.a7.rl.eng = 99   # no auto fire: the test drives the hits
	check(Apc7.is_heavy_walker(k), "m_walker is a heavy walker")
	check(Apc7.fixed_by(w, k, flank), "fixed frontally by the APC in its face")
	var hp0 := float(k.hp)
	Apc7.hit_heavy(w, front, k, 40.0, "at", 1.0)
	var d_front := hp0 - float(k.hp)
	hp0 = float(k.hp)
	Apc7.hit_heavy(w, flank, k, 40.0, "at", 1.0)
	var d_flank := hp0 - float(k.hp)
	check(d_flank >= d_front * 3.0, "flank hit on a fixed walker does markedly more (%.1f vs %.1f front)" % [d_flank, d_front])
	check(float(k.tpl.sg) > 1.0 and float(k.tpl.sg) < 1.2, "front hit built almost no stagger, flank hit built it (%.2f)" % float(k.tpl.sg))
	var evs := []
	for i in 8:
		Apc7.hit_heavy(w, flank, k, 1.0, "at", 1.0)
	check_eq(Apc7.topple_phase(k), "fall", "past the threshold it topples")
	var g: Dictionary = w.sys_state.g7v[int(k.id)]
	check(String(g.topple) == "fall" and absf(float(g.topple_dir) + PI * 0.5) < 0.3, "g7v topple phase + direction (pushed away from the flank: %.2f)" % float(g.topple_dir))
	var p0: Vector2 = k.pos
	evs = _run(w, 40, ["WalkerDown"])
	check(_has(evs, "WalkerDown") and Apc7.is_down(k), "down")
	check(float(k.comp.mobility) == 0.0 and SimWorld.HotState.get_cd(w, int(k.id)) > 0, "cannot move or fire while down")
	hp0 = float(k.hp)
	Apc7.hit_heavy(w, flank, k, 40.0, "at", 1.0)
	check(hp0 - float(k.hp) >= d_flank * 2.0, "hits on a downed walker do heavy bonus damage (%.1f)" % (hp0 - float(k.hp)))
	evs = _run(w, 200, ["WalkerRighted"])
	check(_has(evs, "WalkerRighted") and Apc7.topple_phase(k) == "", "it rights itself after a failed window")
	check(float(k.tpl.sg) == 0.0 and float(k.comp.mobility) > 0.0, "stagger reset, legs back")
	check(Vector2(k.pos).distance_to(p0) < 0.5, "it did not move while down")
	Apc7.hit_heavy(w, flank, k, 1.0, "at", 5.0)
	check(float(k.tpl.sg) == 0.0, "short immunity after rising")
	_run(w, 600)
	check(not k.has("tpl") and not (w.sys_state.g7v.get(int(k.id), {}) as Dictionary).has("topple"), "state and render key cleared")


## Full group (strike team + 3 tactical squads as its escorts) meets a heavy walker.
func _group_world(sd: int, walker_off: Vector2) -> Array:
	var d := _deploy_world(sd)
	var w: SimWorld = d[0]
	var t: Dictionary = d[1]
	var esc := []
	for i in 3:
		esc.append(int(CN.spawn_team(w, 0, "tactical_squad", d[2] + Vector2(-2 + 3 * i, 5)).team))
	t.esc = esc
	var k := _walker(w, d[2] + walker_off, PI)
	return [w, t, k, d[2], esc]


func test_group_pincer_auto_operators_engage_then_remount() -> void:
	var g := _group_world(6, Vector2(11, 1))
	var w: SimWorld = g[0]
	var t: Dictionary = g[1]
	var k: Dictionary = g[2]
	var types := ["CnPincer", "CnOpsDismount", "CnHarpoon", "CnLimpetPlanted", "CnLimpet", "CnDisruptorShot", "CnVolley",
		"WalkerToppled", "WalkerBlownUp", "CnPincerEnd", "RocketSalvo"]
	var r := _until_dead(w, int(k.id), 2400, types)
	var evs: Array = r[1]
	var by := ""
	for ev in evs:
		if String(ev.type) == "CnPincer":
			by = String(ev.by)
			break
	check_eq(by, "auto", "the group chose the pincer by itself on contact")
	check(_has(evs, "CnVolley"), "synchronised launcher volleys")
	var tac_out := false
	for ev in evs:
		if String(ev.type) == "CnOpsDismount" and (g[4] as Array).has(int(ev.team)):
			tac_out = true
	check(tac_out, "tactical operators dismounted to fight the walker")
	check(_has(evs, "CnHarpoon") or _has(evs, "CnLimpetPlanted") or _has(evs, "CnDisruptorShot"), "operators used their anti-Machine kit")
	check(not w.entities.has(int(k.id)), "the group took the heavy walker down (%d ticks)" % int(r[0]))
	print("CNSIM7_GROUP ttk=%d ticks toppled=%s kit harpoon=%s limpet=%s disruptor=%s" % [int(r[0]), _has(evs, "WalkerToppled"),
		_has(evs, "CnHarpoon"), _has(evs, "CnLimpetPlanted"), _has(evs, "CnDisruptorShot")])
	evs = _run(w, 500, ["CnPincerEnd"])
	check(_has(evs, "CnPincerEnd") or _has(r[1], "CnPincerEnd"), "engagement closed")
	var on_foot := 0
	for tid in g[4]:
		on_foot += _on_map(w, CN.team(w, int(tid)))
	check_eq(on_foot, 0, "operators remounted")


func test_player_pincer_order_and_hold_respected() -> void:
	var g := _group_world(8, Vector2(16, 1))   # outside auto detect of the parked group
	var w: SimWorld = g[0]
	var t: Dictionary = g[1]
	var k: Dictionary = g[2]
	SimWorld.HotState.set_hp(w, int(k.id), 6000.0)   # a sturdier walker so the slots can be checked mid-fight
	_run(w, 20)
	check(t.get("eng") == null, "no auto pincer out of reach")
	check(_cmd(w, CN, 0, {"type": "cn_pincer", "team_id": int(t.id), "target_id": 12345678}).contains("No heavy"), "needs a heavy walker")
	for aid in t.apcs:   # bring it into reach of the order
		SimWorld.HotState.set_pos(w, int(aid), Vector2(k.pos) + Vector2(-9, 0))
	check_eq(_cmd(w, CN, 0, {"type": "cn_pincer", "team_id": int(t.id), "target_id": int(k.id)}), "", "one order triggers the pincer")
	check(t.eng != null and String(t.eng.by) == "player", "player pincer started")
	var fx = w.entities.get(int(t.eng.fix))
	check(fx != null and String(Apc7.cfg_of(String(fx.def)).kind) == "tactical", "a tactical APC rushes head-on to fix it")
	_run(w, 160)
	check(t.eng != null, "still engaged")
	var slots: Dictionary = t.eng.slots if t.eng != null else {}
	var a := Vector2.from_angle(float(t.eng.ax)) if t.eng != null else Vector2.LEFT
	var flankers := 0
	for id in slots:
		var e = w.entities.get(int(id))
		if e != null and int(id) != int(t.eng.fix):
			var v := (Vector2(e.pos) - Vector2(k.pos)).normalized()
			flankers += 1 if v.dot(a) < 0.2 else 0
	check(flankers >= 3, "the others went to the flanks / rear (%d)" % flankers)


func test_formed_withdrawal_after_hero_and_on_break_contact() -> void:
	var d := _deploy_world()
	var w: SimWorld = d[0]
	var t: Dictionary = d[1]
	var site: Vector2 = d[2]
	for aid in t.apcs:
		w.entities[int(aid)].a7.dome = 0.0
		w.entities[int(aid)].a7.dome_cd = 1000000
	_cmd(w, CN, 0, {"type": "cn_deploy", "team_id": int(t.id), "target": site, "package": "purge"})
	for i in 400:
		if _has(_run(w, 1, ["CnDismount"]), "CnDismount"):
			break
	_run(w, 200)
	check_eq(_cmd(w, CN, 0, {"type": "cn_hero_detonate", "team_id": int(t.id)}), "", "hero")
	var hid := int(t.dep.hero)
	var back := Vector2.ZERO
	for ev in w.events:   # emitted by the command itself (applied directly here)
		if String(ev.type) == "CnFormedWithdraw":
			back = ev.back
	check(back != Vector2.ZERO, "formed withdrawal ordered")
	var evs := []
	_run(w, int(t.dep.hero_at) - w.tick - 1)
	var apc_proj := 0.0
	var foot_proj := 0.0
	var nf := 0
	var worst := 0.0
	var inside := 0
	for id in t.apcs + t.members:
		var u = w.entities.get(int(id))
		if u == null or int(id) == hid:
			continue
		var off := Vector2(u.pos) - site
		inside += 1 if off.length() <= 3.6 else 0
		worst = maxf(worst, absf(rad_to_deg(back.angle_to(off))))
		if u.has("a7"):
			apc_proj += off.dot(back) * 0.5
		else:
			foot_proj += off.dot(back)
			nf += 1
	check_eq(inside, 0, "nobody left inside the blast radius when it goes off")
	check(worst < 75.0, "one formed group on one side, not a radial scatter (widest %.0f deg off the axis)" % worst)
	check(nf > 0 and foot_proj / float(nf) > apc_proj, "soldiers behind the APC line (sheltered side)")
	evs = _run(w, 200, ["CnPurge"])
	check_eq(CN.live_members(w, t).size(), 19, "only the hero dies")
	# break contact from a pincer: mount up under smoke, then the hulls pull back in a line
	var k := _walker(w, site + Vector2(9, 0), PI)
	check_eq(_cmd(w, CN, 0, {"type": "cn_pincer", "team_id": int(t.id), "target_id": int(k.id)}), "", "pincer")
	_run(w, 40)
	check_eq(_cmd(w, CN, 0, {"type": "cn_break_contact", "team_id": int(t.id)}), "", "break contact")
	check(_has(w.events, "CnBreakContact"), "break contact: mount up under smoke")
	evs = _run(w, 400, ["CnFormedWithdraw"])
	check(_has(evs, "CnFormedWithdraw"), "then the formed withdrawal")
	var a0: Dictionary = w.entities[int(t.apcs[0])]
	var a1: Dictionary = w.entities[int(t.apcs[1])]
	check(Vector2(a0.pos).distance_to(k.pos) > 10.0 and Vector2(a1.pos).distance_to(k.pos) > 10.0, "both strike APCs pulled back")
	check(Vector2(a0.pos).distance_to(a1.pos) < 5.0, "together, as a formed pair")
	check_eq(_on_map(w, t), 0, "everyone aboard")


func test_split_loadout_and_rocket_loadout() -> void:
	var d := _deploy_world()
	var w: SimWorld = d[0]
	var t: Dictionary = d[1]
	var lo := CN.loadout(w, int(t.id))
	check(lo[int(t.apcs[0])].has("purge") and lo[int(t.apcs[1])].has("purge"), "default loadout split: a purge in each APC")
	check_eq(_cmd(w, CN, 0, {"type": "cn_set_loadout", "team_id": int(t.id), "packages": ["purge", "purge", "seed_hunter", "seed_hunter"]}), "", "loadout")
	lo = CN.loadout(w, int(t.id))
	check_eq(lo[int(t.apcs[0])], ["purge", "seed_hunter"], "APC A: one of each")
	check_eq(lo[int(t.apcs[1])], ["purge", "seed_hunter"], "APC B: one of each")
	w.destroy(int(t.apcs[0]), "killed")
	check(CN.pkg_apc(w, t, "purge") != null and CN.pkg_apc(w, t, "seed_hunter") != null, "losing APC A keeps every package kind")
	var tac := CN.spawn_team(w, 0, "tactical_squad", d[2] + Vector2(-6, 4))
	var e: Dictionary = w.entities[int(tac.apcs[0])]
	check_eq(Apc7.rockets_left(e), 18, "default launcher stock")
	check_eq(_cmd(w, CN, 0, {"type": "cn_set_loadout", "team_id": int(tac.team), "rockets": {"tandem": 12, "emp": 6}}), "", "rocket loadout at the facility")
	check(int(e.a7.rl.rk.tandem) == 12 and int(e.a7.rl.rk.emp) == 6 and int(e.a7.rl.tube) == 6, "chosen canister mix, tubes full")
	check(_cmd(w, CN, 0, {"type": "cn_set_loadout", "team_id": int(tac.team), "rockets": {"tandem": 30}}).contains("holds"), "launcher capacity")
	check(_cmd(w, CN, 0, {"type": "cn_set_loadout", "team_id": int(tac.team), "packages": ["purge"]}).contains("strike"), "tactical APCs carry no packages")
	e.a7.rl.rk = {"tandem": 1}
	e.a7.rl.tube = 1
	Apc7.restock(w, e)
	check(int(e.a7.rl.rk.tandem) == 12 and int(e.a7.rl.rk.emp) == 6, "facility restock refills the chosen mix")
