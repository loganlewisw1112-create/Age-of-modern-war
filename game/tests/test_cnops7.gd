extends "res://tests/test_base.gd"
## G7 acceptance (owner: CNOPS7). Master scope 6.9 (overwatch drone, fire support, relief convoy), 6.10 and 13.4
## (named operators, team XP, veterans, bonds, signature skills).

const CN = preload("res://sim/systems/counter_nanite.gd")
const CnOps7 = preload("res://sim/systems/cn_ops7.gd")
const CnProgress7 = preload("res://sim/systems/cn_progress7.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Intel = preload("res://sim/systems/intel.gd")
const Movement = preload("res://sim/systems/movement.gd")
const NOFIRE := 100000


func _ensure_g7() -> void:
	if not Content.rules().has("g7_cnops"):
		Content._merge_fragment_dir("res://content/g7")


## Inert 2-side world with a 60x60 GRASS arena; returns [w, arena origin].
func _setup(sd: int = 0) -> Array:
	var w := make_world({} if sd == 0 else {"seed": sd})
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(60, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.grow(16).has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	w.factions[0].credits = 200000
	return [w, o]


## True once ORCH has put the CNOPS7 systems in SYSTEM_ORDER; until then the tests tick them after each step.
func _registered() -> bool:
	return SimWorld.SYSTEM_ORDER.has(CnOps7)


func _step(w: SimWorld, n: int, types: Array = []) -> Array:
	var out := []
	for i in n:
		w.step()
		if not _registered():
			CnOps7.tick(w)
			CnProgress7.tick(w)
		for ev in w.events:
			if types.is_empty() or types.has(String(ev.type)):
				out.append(ev)
	return out


## Through w.submit (validated + applied at the next tick) once ORCH registered the command, else validate/apply.
func _cmd(w: SimWorld, sys, fid: int, cmd: Dictionary) -> String:
	cmd.issuer = fid
	if SimWorld.COMMANDS.has(String(cmd.type)):
		var sr: Dictionary = w.submit(cmd)
		if not bool(sr.ok):
			return String(sr.reason)
		_step(w, 1)
		return rejected_reason(w.events)
	var r: String = sys.validate_command(w, cmd)
	if r == "":
		sys.apply_command(w, cmd)
	return r


func _has(evs: Array, type: String, key: String = "", val = null) -> bool:
	for ev in evs:
		if String(ev.type) == type and (key == "" or ev.get(key) == val):
			return true
	return false


func _enemy(w: SimWorld, pos: Vector2, tough: bool = true) -> int:
	var id := w.spawn_unit("a_old_tank" if tough else "rifleman", 1, pos)   # a vehicle: no lethal WOUND7 zones
	var e: Dictionary = w.entities[id]
	e.order = {"type": "hold"}
	e.cd_ticks = NOFIRE
	if tough:
		e.hp = 100000.0
		e.max_hp = 100000.0
	return id


func _team(w: SimWorld, pos: Vector2) -> Dictionary:
	var r := CN.spawn_team(w, 0, "strike_team", pos)
	return CN.team(w, int(r.team))


## A death outside a tick (test driver): its event is handled the way the system sees it inside a tick.
func _kill(w: SimWorld, id: int, ko: int) -> Array:
	w.events = []
	w.destroy(id, "test", ko)
	CnProgress7._events(w, CnProgress7.state(w))
	return w.events.duplicate()


func _dismount(w: SimWorld, t: Dictionary) -> void:
	CN.dismount(w, t)
	_step(w, 60)


func _facility(w: SimWorld, o: Vector2i) -> int:
	var off: Array = CnFacility.conf().core_offset
	var id := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	_step(w, CnFacility.DISCOVER_EVERY + 1)
	return id


# ================================================================ overwatch
func test_overwatch_drone_shares_a_sighting() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var o: Vector2i = S[1]
	var base := Vector2(o) + Vector2(20, 30)
	var t := _team(w, base)
	_step(w, 2)
	var did := CnOps7.drone_of(w, int(t.id))
	check(did > 0 and w.entities.has(did), "a strike team gets an overwatch drone")
	check(w.entities.get(did, {}).get("def", "") == "a_drone_recon" and int(w.entities[did].get("cn_ow", -1)) == int(t.id), "Human A overwatch drone (recon airframe) tagged to the team")
	check(SimWorld.DronePilot.pilot_kind("a_drone_recon") == "recon", "the overwatch drone can be flown (recon)")
	var eid := _enemy(w, base + Vector2(15, 0))
	check(not CnOps7.team_sees(w, t, w.entities[eid]), "no team member sees the enemy 15 tiles out (crew is mounted)")
	var evs := _step(w, 80, ["CnOverwatchWarning"])
	check(_has(evs, "CnOverwatchWarning", "target", eid), "overwatch warns of the threat near the team")
	check(not Intel.known(w, 0, eid).is_empty(), "the sighting is shared with the side (Intel contact)")
	check(CnOps7.team_sees(w, t, w.entities[eid]), "the team can now target what the drone saw")
	var p0: Vector2 = w.entities[did].pos
	_step(w, 20)
	check(Vector2(w.entities[did].pos).distance_to(p0) > 0.5, "the drone circles (moved %.2f)" % Vector2(w.entities[did].pos).distance_to(p0))
	check(Vector2(w.entities[did].pos).distance_to(base) < 9.0, "the drone stays over the team")


# ================================================================ fire support
func test_fire_support_visible_target_and_call_limit() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var o: Vector2i = S[1]
	var base := Vector2(o) + Vector2(15, 30)
	var t := _team(w, base)
	_step(w, 2)
	var nears := [_enemy(w, base + Vector2(5, 0)), _enemy(w, base + Vector2(5, 2)), _enemy(w, base + Vector2(5, -2))]
	var near: int = nears[0]
	var far := _enemy(w, base + Vector2(40, 0))
	_step(w, 30)
	var why := _cmd(w, CnOps7, 0, {"type": "cn_fire_support", "team_id": int(t.id), "kind": "artillery", "target_id": far})
	check(why != "", "a target nobody on the team can see is refused (%s)" % why)
	why = _cmd(w, CnOps7, 0, {"type": "cn_fire_support", "team_id": int(t.id), "kind": "nuke", "target_id": near})
	check(why != "", "unknown kind refused")
	why = _cmd(w, CnOps7, 1, {"type": "cn_fire_support", "team_id": int(t.id), "kind": "artillery", "target_id": near})
	check(why != "", "another side can't call this team's fire support")
	var limit := int(CnOps7.FS().get("calls_per_mission", 3))
	var spots := []
	var impacts := []
	var kinds := ["artillery", "rockets", "air"]
	for i in limit:
		if not w.entities.has(near):   # strikes are lethal (WOUND7 zones): a fresh target for each call
			near = _enemy(w, base + Vector2(5, 2 * i - 2))
			_step(w, 15)
		spots.append(Vector2(w.entities[near].pos))
		why = _cmd(w, CnOps7, 0, {"type": "cn_fire_support", "team_id": int(t.id), "kind": kinds[i % 3], "target_id": near})
		check_eq(why, "", "call %d (%s) accepted" % [i + 1, kinds[i % 3]])
		impacts += _step(w, CnOps7.ticks(float(CnOps7.FS().get("cooldown_s", 15))) + 2, ["StrikeImpact", "StrikeLaunched"])
	check_eq(CnOps7.calls_left(w, int(t.id)), 0, "every call used")
	if not w.entities.has(near):
		near = _enemy(w, base + Vector2(5, 0))
		_step(w, 15)
	why = _cmd(w, CnOps7, 0, {"type": "cn_fire_support", "team_id": int(t.id), "kind": "artillery", "target_id": near})
	check(why.contains("No fire-support calls"), "call limit respected (%s)" % why)
	var n_imp := 0
	var worst := 0.0
	for ev in impacts:
		if String(ev.type) == "StrikeImpact":
			n_imp += 1
			var d := 1000.0
			for p in spots:
				d = minf(d, Vector2(ev.pos).distance_to(p))
			worst = maxf(worst, d)
	check(n_imp >= 15, "shots landed (%d)" % n_imp)
	check(worst <= 3.6, "every shot lands on a seen target (worst %.2f tiles)" % worst)
	var hit := 0
	for n in nears:
		if not w.entities.has(int(n)) or float(w.entities[int(n)].hp) < 100000.0:
			hit += 1
	check(hit >= 1, "the seen targets were hit (%d of 3)" % hit)
	check(w.entities.has(far) and float(w.entities[far].hp) == 100000.0, "the unseen enemy was never hit")


# ================================================================ relief convoy
func test_relief_convoy_arrives() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var o: Vector2i = S[1]
	var fac := _facility(w, o)
	check(fac > 0 and CnFacility.active(w), "facility raised")
	var t := _team(w, Vector2(o) + Vector2(48, 50))
	_step(w, 2)
	var why := _cmd(w, CnOps7, 0, {"type": "cn_relief", "team_id": int(t.id), "kind": "reload"})
	check_eq(why, "", "reload APC sent")
	why = _cmd(w, CnOps7, 0, {"type": "cn_relief", "team_id": int(t.id), "kind": "operators"})
	check(why != "", "cooldown blocks a second relief at once (%s)" % why)
	var evs := _step(w, 1600, ["CnReliefArrived", "CnReliefLost"])
	check(_has(evs, "CnReliefArrived", "kind", "reload"), "the reload APC reached the team")
	for ev in evs:
		if String(ev.type) == "CnReliefArrived":
			check(not (ev.restocked as Array).is_empty(), "team APCs restocked on arrival")
	CnOps7.state(w).relief_cd.clear()
	why = _cmd(w, CnOps7, 0, {"type": "cn_relief", "team_id": int(t.id), "kind": "operators"})
	check_eq(why, "", "fresh operator squad sent")
	evs = _step(w, 1600, ["CnReliefArrived", "CnReliefLost"])
	check(_has(evs, "CnReliefArrived", "kind", "operators"), "the operator squad reached the team")
	# specialist upgrade path through the facility (workshop path for a gunner)
	var gun := int(t.squads.A[6])
	why = _cmd(w, CnProgress7, 0, {"type": "cn_specialize", "unit_id": gun, "path": "lab"})
	check(why != "", "a gunner can't take the lab path (%s)" % why)
	var g0 := CnProgress7.skill_mult(w, gun, "gunner_acc")
	why = _cmd(w, CnProgress7, 0, {"type": "cn_specialize", "unit_id": gun, "path": "workshop"})
	check_eq(why, "", "workshop path taken")
	check(CnProgress7.skill_mult(w, gun, "gunner_acc") > g0, "the path improves the specialist")


# ================================================================ progression
func _names(w: SimWorld, t: Dictionary) -> Array:
	var out := []
	for id in t.members:
		var o := CnProgress7.op(w, int(id))
		out.append("%s|%s|%s|%s" % [o.get("name", ""), o.get("cs", ""), o.get("pers", ""), o.get("skill", "")])
	return out


func test_names_and_call_signs_stable_per_seed() -> void:
	var lists := []
	for sd in [7, 7, 8]:
		var S := _setup(sd)
		var w: SimWorld = S[0]
		var t := _team(w, Vector2(S[1]) + Vector2(20, 20))
		_step(w, 2)
		lists.append(_names(w, t))
		if sd == 8:
			var card := CnProgress7.team_card(w, int(t.id))
			check(String(card.name).begins_with("Team "), "named team (%s)" % card.name)
			check_eq((card.members as Array).size(), 20, "card lists 20 operators")
			var uniq := {}
			for mm in card.members:
				uniq[String(mm.name)] = true
			check_eq(uniq.size(), 20, "20 distinct operator names in a team")
			var m: Dictionary = card.members[0]
			check(String(m.name).contains(" ") and String(m.cs) != "" and CnProgress7.PERS.has(String(m.pers)) and String(m.skill_label) != "",
				"operator has name, call sign, personality, skill (%s / %s / %s / %s)" % [m.name, m.cs, m.pers, m.skill_label])
	check_eq(lists[0], lists[1], "same seed -> same names, call signs, personalities, skills")
	check(lists[0] != lists[2], "another seed -> other names")


func _mission(w: SimWorld, t: Dictionary) -> void:
	w.events = []
	w.emit("CnPurge", {"team": int(t.id), "owner": int(t.fid), "site": Vector2.ZERO, "kind": "standard", "hero": false})
	CnProgress7._events(w, CnProgress7.state(w))   # the purge as CNSIM7 emits it (a full deployment is CNSIM7's test)


func test_xp_levels_and_veteran_loss() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var t := _team(w, Vector2(S[1]) + Vector2(20, 20))
	_step(w, 2)
	_mission(w, t)
	_mission(w, t)
	var tr := CnProgress7.team_rec(w, int(t.id))
	check_eq(int(tr.missions), 2, "two missions recorded")
	check_eq(CnProgress7.level(w, int(t.id)), 1, "80 XP -> level 1")
	check(CnProgress7.level_mult(w, int(t.id), "arm") < 1.0, "level speeds up arming")
	check(CnProgress7.arm_mult(w, t) < 1.0, "arm_mult < 1 at level 1")
	_dismount(w, t)
	var vet := -1
	for id in t.members:
		if w.entities.has(int(id)) and int(id) != int(t.leader):
			vet = int(id)
			break
	check(vet > 0, "a veteran on foot")
	check(CnProgress7._is_vet(CnProgress7.op(w, vet)), "two missions make a veteran")
	# kill credit: an enemy last hit by the veteran dies
	# REGFIX7-4: the team holds fire while this is staged (the rifleman 3 tiles off was shot dead by a team mate 4
	# ticks in, so the kill below never happened and the veteran was never his last attacker)
	for id in (t.members as Array) + (t.apcs as Array):
		if w.entities.has(int(id)):
			w.entities[int(id)].cd_ticks = NOFIRE
	var eid := _enemy(w, Vector2(w.entities[vet].pos) + Vector2(3, 0), false)
	w.entities[eid].last_attacker = vet
	_step(w, 12)
	_kill(w, eid, 0)
	check_eq(int(CnProgress7.op(w, vet).kills), 1, "kill credited to the operator")
	var xp0 := float(CnProgress7.team_rec(w, int(t.id)).xp)
	var evs := _kill(w, vet, 1)
	check(_has(evs, "CnVeteranLost", "id", vet), "losing a veteran is reported")
	check(float(CnProgress7.team_rec(w, int(t.id)).xp) < xp0, "losing a veteran costs XP")
	check_eq(CnProgress7.level(w, int(t.id)), 0, "and the level")
	check(_has(evs, "CnTeamLevel", "level", 0), "level drop event")


## REGFIX7-4: an enemy shot dead within a few ticks of its first hit (before any 10-tick hit sample) is still credited,
## to the team member whose hit killed it (the Damage event, not the sample).
func test_quick_kill_credited_to_the_shooter() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var t := _team(w, Vector2(S[1]) + Vector2(20, 20))
	_step(w, 2)
	_dismount(w, t)
	var vet := -1
	for id in t.members:
		if w.entities.has(int(id)) and int(id) != int(t.leader):
			vet = int(id)
			break
	var eid := _enemy(w, Vector2(w.entities[vet].pos) + Vector2(3, 0), false)
	var killer := -1
	var died := -1
	for i in 9:
		for ev in _step(w, 1):
			if String(ev.type) == "Damage" and int(ev.target) == eid:
				killer = int(ev.shooter)
			if String(ev.type) == "EntityDestroyed" and int(ev.id) == eid:
				died = i
		if died >= 0:
			break
	check(died >= 0 and died < 9, "the team drops the rifleman within 9 ticks (died at %d)" % died)
	check(killer >= 0 and not CnProgress7.op(w, killer).is_empty(), "a team operator hit him last (%d)" % killer)
	check_eq(int(CnProgress7.op(w, killer).kills) if killer >= 0 else -1, 1, "the kill is credited to that operator")
	check_eq(int(CnProgress7.team_rec(w, int(t.id)).kills), 1, "and to the team")


func test_bond_reactions() -> void:
	var S := _setup()
	var w: SimWorld = S[0]
	var t := _team(w, Vector2(S[1]) + Vector2(20, 20))
	_step(w, 2)
	_mission(w, t)
	_mission(w, t)
	_dismount(w, t)
	var a := int(t.squads.A[1])
	var b := CnProgress7.buddy_of(w, a)
	check(b > 0 and CnProgress7.bond(w, a, b) >= 2, "missions together make buddies (%d bond %d)" % [b, CnProgress7.bond(w, a, b)])
	w.entities[b].pos = Vector2(w.entities[a].pos) + Vector2(1, 0)
	w.events = []
	w.emit("Wound", {"id": a, "owner": 0, "zone": "leg_l", "dmg": 20.0, "result": "wounded"})
	CnProgress7._events(w, CnProgress7.state(w))
	var evs: Array = w.events.duplicate()
	check(_has(evs, "CnBuddyCallout", "id", b), "the buddy calls out the wound")
	check((CnProgress7.op(w, a).scars as Array).has("leg_l"), "the wound leaves a scar")
	var m0 := float(w.entities[b].get("morale", 0.0))
	evs = _kill(w, a, 1)
	check(_has(evs, "CnBondLoss", "id", b), "a close teammate's death hits the buddy")
	check(float(w.entities[b].morale) < m0 or m0 <= 0.0, "morale drops (%.1f -> %.1f)" % [m0, float(w.entities[b].morale)])


func _heal_run(skill: String) -> float:
	var S := _setup()
	var w: SimWorld = S[0]
	var t := _team(w, Vector2(S[1]) + Vector2(20, 20))
	_step(w, 2)
	_dismount(w, t)
	var med := int(t.squads.A[9])
	var pat := int(t.squads.A[6])
	CnProgress7.op(w, med).skill = skill   # the roll is a pure function of the seed; pin it to test the effect
	for id in [med, pat]:
		w.entities[id].order = {"type": "hold"}
	w.entities[pat].pos = Vector2(w.entities[med].pos) + Vector2(1, 0)
	w.entities[pat].hp = float(w.entities[pat].max_hp) - 60.0
	var h0 := float(w.entities[pat].hp)
	_step(w, 100)
	return float(w.entities[pat].hp) - h0 if w.entities.has(pat) else -999.0


func test_signature_skill_effect() -> void:
	var with_skill := _heal_run("field_surgeon")
	var without := _heal_run("cocoon_cutter")
	check(with_skill > without + 5.0, "field surgeon heals a nearby teammate (%.1f vs %.1f hp)" % [with_skill, without])
	var S := _setup()
	var w: SimWorld = S[0]
	var t := _team(w, Vector2(S[1]) + Vector2(20, 20))
	_step(w, 2)
	var dep := int(t.squads.A[2])
	CnProgress7.op(w, dep).skill = "quick_arm"
	check(CnProgress7.skill_mult(w, dep, "arm") < 1.0, "quick arming skill shortens arming")
	check(CnProgress7.arm_mult(w, t) < 1.0, "team arm_mult uses its specialists' skills")


# ================================================================ determinism, isolation, saves
func _scenario(sd: int) -> SimWorld:
	var S := _setup(sd)
	var w: SimWorld = S[0]
	var base := Vector2(S[1]) + Vector2(15, 30)
	var t := _team(w, base)
	_step(w, 2)
	var e := _enemy(w, base + Vector2(6, 2))
	_step(w, 30)
	_cmd(w, CnOps7, 0, {"type": "cn_fire_support", "team_id": int(t.id), "kind": "rockets", "target_id": e})
	_step(w, 200)
	return w


func test_same_seed_same_hash() -> void:
	var a := _scenario(11)
	var b := _scenario(11)
	check_eq(a.state_hash(), b.state_hash(), "same seed twice = same hash")
	check(a.sys_state.has("cnops7") and a.sys_state.has("cnprog7"), "CNOPS7 state saved in sys_state")


func test_match_without_cn_is_hash_identical() -> void:
	var a := make_world({"seed": 5})
	var b := make_world({"seed": 5})
	for i in 300:
		a.step()
		b.step()
		CnOps7.tick(b)
		CnProgress7.tick(b)
	check_eq(a.state_hash(), b.state_hash(), "no counter-nanite units -> identical hash with CNOPS7 ticking")
	check(not b.sys_state.has("cnops7") and not b.sys_state.has("cnprog7"), "no CNOPS7 state created")


func test_save_load_round_trip() -> void:
	var a := _scenario(13)
	var b := SimWorld.from_dict(a.to_dict().duplicate(true))
	check_eq(b.state_hash(), a.state_hash(), "loaded hash = live hash")
	_step(a, 200)
	_step(b, 200)
	check_eq(b.state_hash(), a.state_hash(), "live and loaded stay identical 200 ticks on")
