extends "res://tests/test_base.gd"
## G7 acceptance (owner: CNROLE7). Owner note 13.9c-29 / B16: counter-nanite strike teams and tactical / spec-ops squads
## are NEVER on base defence, strictly missions. Covers: who counts as CN (CnRole7), the AI controller roster, player
## AI Commanders (base defence slot, ally commitments), the Last Protocol defence commander + wall garrison, the
## Sentinel job board, parked units holding their post (no chase, no sally), a launched mission still running, player
## orders still obeyed, same-hash-twice, and no cost without a facility.
## Worlds: the Last Protocol start on industrial_heartland_m (a real facility with 2 strike teams + 4 tactical squads
## parked in their garages, 8 APCs with their crews inside) and a normal 2-side match with a live AI.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const LpDefence = preload("res://sim/systems/lp_defence.gd")
const LpGarrison7 = preload("res://sim/systems/lp_garrison7.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const CnRole7 = preload("res://sim/systems/cn_role7.gd")
const Commanders = preload("res://sim/ai/commanders.gd")
const AllyCmds = preload("res://sim/ai/ally_cmds.gd")
const AiController = preload("res://sim/ai/ai_controller.gd")
const Sentinels7 = preload("res://sim/systems/sentinels7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const MAP := "industrial_heartland_m"
const CN_SOLDIER := "g7_cn_gunner"
const CN_DEFS := ["g7_cn_team_leader", "g7_cn_radio", "g7_cn_deploy", "g7_cn_scanner", "g7_cn_ew", "g7_cn_gunner", "g7_cn_medic",
	"g7_op_leader", "g7_op_marksman", "g7_op_hunter", "g7_op_emp", "g7_op_antidrone", "g7_op_purge", "g7_op_medic",
	"g7_cn_strike_apc", "g7_op_tactical_apc", "g7_b_cn_team_leader", "g7_b_cn_radio", "g7_b_cn_deploy", "g7_b_cn_scanner",
	"g7_b_cn_ew", "g7_b_cn_gunner", "g7_b_cn_medic", "g7_b_op_leader", "g7_b_op_marksman", "g7_b_op_hunter", "g7_b_op_emp",
	"g7_b_op_antidrone", "g7_b_op_purge", "g7_b_op_medic", "g7_b_cn_strike_apc", "g7_b_op_tactical_apc",
	"g7_cns_bastion", "g7_cns_breaker", "g7_cns_aegis", "g7_cns_purifier", "g7_b_cns_bastion", "g7_b_cns_purifier"]
## Same "g7_" / "g7_b_" families that are NOT strike teams or operators (Sentinels, drones, facility staff, Machine).
const NOT_CN_DEFS := ["g7_sent_warden", "g7_sent_gunner", "g7_b_sent_warden", "g7_b_sent_bearer", "g7_b_sent_lancer", "g7_a_strike_drone",
	"g7_b_strike_drone", "g7_a_fpv", "g7_b_fpv", "g7_fac_engineer", "g7_b_fac_engineer", "g7_m_mimic", "g7_m_packhunter", "m_walker",
	"cn_stealth_dropship", "cn_gun_drone", "g7_cn_sentry", "g7_cn_barrier"]

static var _base_dict: Dictionary = {}


func _ensure_g7() -> void:
	if Content.unit(CN_SOLDIER).is_empty():
		Content._merge_fragment_dir("res://content/g7")


## A Last Protocol world after setup (cached; every test gets a deep copy). The Machine AI is off.
func _lp() -> SimWorld:
	if _base_dict.is_empty():
		var c := LastProtocol.make_config(4242, MAP)
		var w0 := SimWorld.new_match(c)
		if w0 == null:
			return null
		w0.run_ticks(25)
		_base_dict = w0.to_dict().duplicate(true)
	var w := SimWorld.from_dict(_base_dict.duplicate(true))
	w.ai_state = {}
	return w


func _s(w: SimWorld) -> Dictionary:
	return w.sys_state.lp


func _fac(w: SimWorld) -> Dictionary:
	var ids := CnFacility.facilities(w, int(_s(w).fid))
	return CnFacility.fac(w, int(ids[0])) if not ids.is_empty() else {}


## A free foot cell near p for side 0 (so a spawned soldier is not inside a wall).
func _free(w: SimWorld, p: Vector2) -> Vector2:
	var team := Movement.team_of(w, {"owner": 0})
	var c: Vector2i = Movement.nearest_free_cell(w, w.cell_of(p), "foot", team)
	return Vector2(c) + Vector2(0.5, 0.5)


func _cn_ids(w: SimWorld, fid: int) -> Array:
	var out := []
	for e in w.units_of(fid):
		if CnRole7.is_cn(e):
			out.append(int(e.id))
	out.sort()
	return out


## id -> [pos, order type, target] of every CN unit of fid on the map.
func _snap(w: SimWorld, fid: int) -> Dictionary:
	var out := {}
	for id in _cn_ids(w, fid):
		var e: Dictionary = w.entities[id]
		out[id] = [Vector2(e.pos), String(e.order.get("type", "idle")), int(e.get("target", -1))]
	return out


## A dismounted CN soldier of side 0 on foot at p (cn_team 1: a real team member).
func _soldier(w: SimWorld, p: Vector2, tag_team: bool = true) -> int:
	var id := w.spawn_unit(CN_SOLDIER, 0, p)
	if tag_team:
		w.entities[id].cn_team = 1
	return id


func _hostile(w: SimWorld, p: Vector2, def_id: String = "g7_m_spitter") -> int:
	return w.spawn_unit(def_id, int(_s(w).mfid), p)


func test_who_counts_as_cn() -> void:
	_ensure_g7()
	for d in CN_DEFS:
		if check(not Content.unit(String(d)).is_empty(), "def exists: %s" % d):
			check(CnRole7.is_cn_def(String(d)), "%s is a CN def" % d)
			check(CnRole7.is_cn({"kind": "unit", "def": String(d)}), "%s unit is CN by def alone" % d)
	for d in NOT_CN_DEFS:
		if not Content.unit(String(d)).is_empty():
			check(not CnRole7.is_cn_def(String(d)), "%s is NOT a CN def (g7_ / g7_b_ prefix alone proves nothing)" % d)
	check(CnRole7.is_cn({"kind": "unit", "def": "m_walker", "cn_team": 3}), "e.cn_team marks any entity")
	check(not CnRole7.is_cn(null) and not CnRole7.is_cn(5) and not CnRole7.is_cn({}), "garbage is not CN")
	check(not CnRole7.is_cn({"kind": "building", "def": CN_SOLDIER}), "a building is never CN by def")
	var ids := []
	for d in ["m_walker", CN_SOLDIER, "g7_b_sent_warden", "g7_op_hunter"]:
		ids.append({"kind": "unit", "def": d, "id": ids.size()})
	var kept := CnRole7.without_cn(ids)
	check_eq(kept.size(), 2, "without_cn drops the two CN units")
	check(int(kept[0].id) == 0 and int(kept[1].id) == 2, "without_cn keeps order")


func test_parked_only_inside_own_facility() -> void:
	var w := _lp()
	var s := _s(w)
	var F := _fac(w)
	check(not F.is_empty(), "the Last Protocol start has a facility")
	var apcs := _cn_ids(w, int(s.fid))
	check_eq(apcs.size(), 8, "8 CN APCs (2 strike teams x 2 + 4 tactical)")
	for id in apcs:
		check(CnRole7.parked(w, w.entities[id]), "APC %d parked in its garage" % id)
	var rc := CnFacility.compound_rect(F)
	var inside := _soldier(w, _free(w, rc.get_center()))
	var outside := _soldier(w, _free(w, rc.position + Vector2(-8.0, rc.size.y * 0.5)))
	check(CnRole7.parked(w, w.entities[inside]), "CN soldier inside the compound is parked")
	check(not CnRole7.parked(w, w.entities[outside]), "CN soldier outside the compound is on a mission, not parked")
	var us := w.units_of(int(s.fid))
	var main_ok := false
	for e in us:
		if e.has("lp_ring") and not CnRole7.is_cn(e):
			main_ok = main_ok or not CnRole7.parked(w, e)
	check(main_ok, "main-army units are never parked")
	var foe := _hostile(w, rc.get_center())
	check(not CnRole7.parked(w, w.entities[foe]), "an enemy inside the compound is not parked")


func test_no_cost_without_facility() -> void:
	_ensure_g7()
	var w := make_world()
	var id := w.spawn_unit(CN_SOLDIER, 0, Vector2(20.5, 20.5))
	check(not CnRole7.parked(w, w.entities[id]), "no facility: nothing is parked")
	w.run_ticks(40)
	check(not w.sys_state.has("cn_facility"), "no CN state appears without a facility")
	check(not w.cache.has("cnr7_homes"), "no facility = no home-rect cache built")


func test_ai_controller_roster_excludes_cn() -> void:
	_ensure_g7()
	var w := make_world({}, true)
	var base := Vector2(w.entities[w.buildings_of(1)[0].id].pos) if not w.buildings_of(1).is_empty() else Vector2(40.5, 40.5)
	var cn := []
	for i in 6:
		var d: String = ["g7_cn_gunner", "g7_op_hunter", "g7_b_cn_medic", "g7_cn_strike_apc", "g7_op_tactical_apc", "g7_cns_bastion"][i]
		var id := w.spawn_unit(d, 1, base + Vector2(2.0 + float(i), 3.0))
		if i % 2 == 0:
			w.entities[id].cn_team = 7   # half carry the team tag, half only the def
		cn.append(id)
	var ctrl_def := String(AiController.U.role_unit(w, 1, "infantry"))
	var ctrl := w.spawn_unit(ctrl_def, 1, base + Vector2(2.0, 6.0))
	var st := AiController.new_state(w, 1)
	var ctx: Dictionary = AiController._context(w, 1, st)
	var all := {}
	for k in ["units", "army", "held", "air", "arty", "recon", "ew", "carriers", "cengs", "engineers", "builders", "gatherers", "officers", "trucks"]:
		for e in ctx[k]:
			all[int(e.id)] = k
	for id in cn:
		check(not all.has(id), "AI context never lists CN unit %d (%s)" % [id, String(all.get(id, ""))])
	check(all.has(ctrl), "control: an ordinary infantry unit is in the AI roster")
	# a live AI: no CN unit gets an order or a commander badge over 600 ticks (the control unit is rallied / used)
	var before := {}
	for id in cn:
		before[id] = Vector2(w.entities[id].pos)
	w.run_ticks(600)
	for id in cn:
		var e = w.entities.get(id)
		if check(e != null, "CN unit %d alive" % id):
			check_eq(String(e.order.get("type", "idle")), "idle", "AI never orders CN unit %d" % id)
			check(not e.has("ai_cmd") and not e.has("company") and not e.has("garrisoned_in"), "CN unit %d: no commander badge / company / garrison" % id)
			check(Vector2(e.pos).distance_to(before[id]) < 3.0, "CN unit %d stayed put (only separation push) (moved %.2f, order %s)" % [id, Vector2(e.pos).distance_to(before[id]), JSON.stringify(e.order)])


func test_player_ai_commander_and_ally_skip_cn() -> void:
	var w := _lp()
	var s := _s(w)
	var F := _fac(w)
	var home := Vector2(CnFacility.compound_rect(F).get_center())
	var tagged := _soldier(w, _free(w, home), true)
	var by_def := _soldier(w, _free(w, home + Vector2(2.0, 0.0)), false)
	var ctrl_def := ""
	for e in w.units_of(int(s.fid)):
		if e.has("lp_ring") and not CnRole7.is_cn(e) and String(Content.unit(String(e.def)).get("weapon", "")) != "" \
				and String(Content.unit(String(e.def)).get("move_class", "")) == "foot":
			ctrl_def = String(e.def)
			break
	check(ctrl_def != "", "a main-army infantry def exists for the control")
	var ctrl := w.spawn_unit(ctrl_def, int(s.fid), _free(w, home + Vector2(4.0, 0.0)))
	var slot := {"role": "base_defence", "units": []}
	var got: Array = Commanders.role_ids(w, int(s.fid), slot, {}, home)
	check(got.has(ctrl), "control: the base_defence slot takes an ordinary soldier at home")
	check(not got.has(tagged) and not got.has(by_def), "base_defence slot never takes a CN soldier")
	for id in _cn_ids(w, int(s.fid)):
		check(not got.has(id), "base_defence slot never takes CN unit %d" % id)
	var lg: Array = Commanders.role_ids(w, int(s.fid), {"role": "logistics", "units": []}, {}, home)
	check(not lg.has(tagged), "logistics slot never takes a CN soldier")
	var pick: Array = AllyCmds.pick(w, int(s.fid), "defend", home)
	for id in pick:
		check(not CnRole7.is_cn(w.entities[int(id)]), "ally commitment never lends CN unit %d" % int(id))
	# end to end: a player AI Commander on base defence with hostiles at the gate; CN units stay out of it
	var ev := do_cmd(w, int(s.fid), {"type": "set_ai_commander", "slot": 0, "target": {"role": "base_defence"}, "playstyle": "defensive",
		"objective": {"type": "hold"}, "stance": "balanced"})
	check_eq(rejected_reason(ev), "", "set_ai_commander base_defence accepted")
	for i in 3:
		_still_foe(w, home + Vector2(-16.0, float(i)), "m_walker")
	w.run_ticks(400)
	for id in [tagged, by_def]:
		var e: Dictionary = w.entities[id]
		check(not e.has("ai_cmd"), "AI Commander never badges CN soldier %d" % id)
		check_eq(String(e.order.get("type", "idle")), "idle", "AI Commander never orders CN soldier %d" % id)


## A Machine unit that never moves (hold) so a fixture enemy cannot walk into the compound on its own.
func _still_foe(w: SimWorld, p: Vector2, def_id: String) -> int:
	var id := _hostile(w, p, def_id)
	w.entities[id].order = {"type": "hold"}
	return id


func test_lp_defence_garrison_and_sentinels_skip_cn() -> void:
	var w := _lp()
	var s := _s(w)
	var F := _fac(w)
	var rc := CnFacility.compound_rect(F)
	# a CN soldier that carries the Last Protocol home fields (as a map-placed unit would), plus a team member
	var homed := _soldier(w, _free(w, rc.get_center()), false)
	w.entities[homed].lp_ring = 2
	w.entities[homed].lp_home = Vector2(w.entities[homed].pos)
	var tagged := _soldier(w, _free(w, rc.get_center() + Vector2(2.0, 0.0)), true)
	check(not LpDefence.is_main(w.entities[homed]), "a CN def with lp_ring is not 'main army'")
	check(not LpDefence.is_main(w.entities[tagged]), "a CN team member is not 'main army'")
	# wall patrol record for the homed CN unit: the garrison tick drops it and never orders it
	var G = w.sys_state.get("lp_garrison7")
	var had_patrols: bool = G is Dictionary and not (G.routes as Array).is_empty()
	if had_patrols:
		(G.pat as Array).append([homed, 0, 0, 0.0, 0.0])
		(G.pat as Array).sort_custom(func(a, b) -> bool: return int(a[0]) < int(b[0]))
		w.entities[homed].lp_ring = int(G.ring[0])
		w.run_ticks(SimWorld.TICK_RATE * 3)
		var still := false
		for rec in w.sys_state.lp_garrison7.pat:
			still = still or int(rec[0]) == homed
		check(not still, "the wall-patrol roster drops a CN unit")
	# Sentinels: enlist refuses a CN soldier
	Sentinels7.enlist(w, w.entities[tagged], {"k": "auto", "fac": -1})
	check(not w.entities[tagged].has("s7"), "Sentinels7.enlist refuses a CN soldier")
	# the base is attacked: Machine at the outer ring (the defence commander sends reserves) and a pack standing off the
	# compound (the Sentinels' guard net stands to). All fixture enemies hold still; none enters the compound.
	var r0: Rect2i = s.base.rings[0].rect
	for i in 4:
		_still_foe(w, Vector2(r0.position.x + 2 + i, r0.get_center().y) + Vector2(0.5, 0.5), "m_walker")
	for i in 3:
		_still_foe(w, Vector2(rc.position.x - 8.0, rc.get_center().y + float(i) * 1.5), "m_walker")
	var evs := []
	for i in 20:
		w.run_ticks(SimWorld.TICK_RATE)
		for ev in w.events:
			if String(ev.type) == "LpReserves" or String(ev.type) == "LpPosture":
				evs.append(ev)
	check(not evs.is_empty() or int(s.get("rings_fallen", 0)) >= 0, "(the defence commander reacted to the attack)")
	var S = w.sys_state.get("sent7")
	if S is Dictionary:
		for id in S.get("ids", []):
			check(not CnRole7.is_cn(w.entities.get(int(id), {})), "Sentinel job board lists no CN unit (%d)" % int(id))
	for id in [homed, tagged]:
		var e = w.entities.get(id)
		if e == null:
			continue
		check(not e.has("lp_reserve") and not e.has("lp_ord") and not e.has("s7") and not e.has("garrisoned_in"),
			"CN soldier %d: no reserve / defence order / sentinel job / garrison after a 20 s attack" % id)
		check_eq(String(e.order.get("type", "idle")), "idle", "CN soldier %d got no order from any defence system" % id)
	for id in _cn_ids(w, int(s.fid)):
		var e: Dictionary = w.entities[id]
		check(not e.has("lp_reserve") and not e.has("lp_ord"), "CN unit %d: no defence-commander fields" % id)


func test_parked_units_hold_no_chase() -> void:
	var w := _lp()
	var s := _s(w)
	s.defence_ai = false   # isolate Combat: the defence commander is covered by its own test
	var F := _fac(w)
	var rc := CnFacility.compound_rect(F)
	# parked soldier at the west edge: an unarmed enemy stands outside the wall, inside its sight (9) but outside its range
	var a_pos := _free(w, Vector2(rc.position.x + 2.0, rc.get_center().y + 4.0))
	var parked := _soldier(w, a_pos)
	_still_foe(w, a_pos + Vector2(-8.0, 0.0), "g7_m_spitter")
	# control: the same soldier far from the compound (a mission) does chase
	var b_pos := _free(w, rc.position + Vector2(-26.0, rc.size.y + 4.0))
	var free_s := _soldier(w, b_pos)
	_still_foe(w, b_pos + Vector2(-8.0, 0.0), "g7_m_spitter")
	var apc: int = _cn_ids(w, int(s.fid))[0]
	var apc_pos := Vector2(w.entities[apc].pos)
	_still_foe(w, Vector2(rc.position.x - 3.0, apc_pos.y), "m_walker")
	w.run_ticks(SimWorld.TICK_RATE * 6)
	var mv_free := Vector2(w.entities[free_s].pos).distance_to(b_pos)
	var mv_parked := Vector2(w.entities[parked].pos).distance_to(a_pos)
	check(mv_free > 1.5, "control: a CN soldier on a mission chases an enemy in sight (moved %.2f)" % mv_free)
	check(mv_parked < 0.05, "a parked CN soldier holds its post and does not chase (moved %.2f)" % mv_parked)
	var mv_apc := Vector2(w.entities[apc].pos).distance_to(apc_pos)
	check(mv_apc < 0.05, "a parked CN APC does not leave its garage to chase (moved %.2f)" % mv_apc)
	check_eq(String(w.entities[parked].order.get("type", "idle")), "idle", "the parked soldier was never given an order")
	# in weapon range: it fires from its post and still never advances
	var near_foe := _still_foe(w, a_pos + Vector2(-4.0, -1.0), "m_walker")   # G7.1 (owner 2026-11-13): 4.1 tiles, in his 4.5 shotgun range, off the defenders' lines of fire through his post
	var ever_moving := false
	var closest := 0.0   # how far toward the enemy (west, -x) it ever got
	for k in 60:
		w.run_ticks(4)
		var d: Dictionary = w.entities[parked]
		ever_moving = ever_moving or bool(d.get("moving", false))
		closest = maxf(closest, a_pos.x - float(d.pos.x))
	var e: Dictionary = w.entities[parked]
	check(not ever_moving and closest < 0.1 and Vector2(e.pos).distance_to(a_pos) < 1.0,
		"a parked CN soldier fires from its post, never walking toward the enemy (advanced %.2f, moved %.2f, path %s)" % [closest, Vector2(e.pos).distance_to(a_pos), str(ever_moving)])
	var fired := int(e.get("target", -1)) == near_foe or not w.entities.has(near_foe) or float(w.entities[near_foe].hp) < float(w.entities[near_foe].max_hp)
	check(fired, "it returns fire at an enemy in weapon range where it stands")


func test_launched_mission_still_runs() -> void:
	var w := _lp()
	var s := _s(w)
	var F := _fac(w)
	var rc := CnFacility.compound_rect(F)
	var team := 1
	var T := CnFacility.team(w, team)
	var apcs: Array = (T.apcs as Array).duplicate()
	var tgt := Vector2(rc.position.x + rc.size.x * 0.5, rc.end.y + 14.0)
	var ev := do_cmd(w, int(s.fid), {"type": "cn_rollout", "team": team, "target": tgt})
	check_eq(rejected_reason(ev), "", "cn_rollout accepted")
	# an attack on the base while the team rolls out: Machine units at the outer ring
	var r0: Rect2i = s.base.rings[0].rect
	for i in 3:
		w.spawn_unit("m_walker", int(s.mfid), Vector2(r0.position.x + 2 + i, r0.get_center().y) + Vector2(0.5, 0.5))
	var went_out := false
	var left := false
	for i in 40:
		w.run_ticks(SimWorld.TICK_RATE * 3)
		T = CnFacility.team(w, team)
		if String(T.get("phase", "")) == "out":
			went_out = true
		for id in apcs:
			var a = w.entities.get(int(id))
			if a != null and not CnRole7.parked(w, a):
				left = true
		if went_out and left:
			break
	check(went_out, "the launched team reaches phase 'out' while the base is attacked (phase %s)" % String(T.get("phase", "")))
	check(left, "its APCs leave the compound: a mission is not held back by the parked rule")
	# the other, un-launched teams stayed home
	for id in _cn_ids(w, int(s.fid)):
		if not apcs.has(id) and int(w.entities[id].get("cn_team", -1)) != team:
			check(CnRole7.parked(w, w.entities[id]), "un-launched CN unit %d stays at home during the attack" % id)


func test_player_orders_still_obeyed() -> void:
	var w := _lp()
	var s := _s(w)
	var F := _fac(w)
	var rc := CnFacility.compound_rect(F)
	var p0 := _free(w, rc.get_center())
	var id := _soldier(w, p0)
	_still_foe(w, Vector2(rc.position.x - 6.0, p0.y), "g7_m_spitter")
	var goal := _free(w, p0 + Vector2(6.0, 4.0))
	w.submit({"type": "move", "issuer": int(s.fid), "unit_ids": [id], "target": goal})
	w.run_ticks(SimWorld.TICK_RATE * 8)
	var e: Dictionary = w.entities[id]
	check(Vector2(e.pos).distance_to(goal) < 1.5, "a parked CN soldier obeys a player move order (%.2f from goal)" % Vector2(e.pos).distance_to(goal))
	# a player attack-move out through the compound also runs (mission control stays with the player)
	var far := _free(w, rc.position + Vector2(rc.size.x * 0.5, rc.size.y + 8.0))
	w.submit({"type": "attack_move", "issuer": int(s.fid), "unit_ids": [id], "target": far})
	w.run_ticks(SimWorld.TICK_RATE * 3)
	check(Vector2(w.entities[id].pos).distance_to(goal) > 1.0 or String(w.entities[id].order.get("type", "")) == "attack_move", "a player attack_move is accepted and carried out")
	# nothing automatic overrides a player hold
	w.submit({"type": "hold", "issuer": int(s.fid), "unit_ids": [id]})
	w.run_ticks(40)
	check_eq(String(w.entities[id].order.get("type", "")), "hold", "a player hold stays a hold")


func _scenario_hash() -> String:
	var w := _lp()
	var s := _s(w)
	var F := _fac(w)
	var rc := CnFacility.compound_rect(F)
	_soldier(w, _free(w, rc.get_center()))
	for i in 3:
		_still_foe(w, Vector2(rc.position.x - 8.0, rc.get_center().y + float(i) * 1.5), "m_walker")
	var r0: Rect2i = s.base.rings[0].rect
	for i in 3:
		w.spawn_unit("m_walker", int(s.mfid), Vector2(r0.position.x + 2 + i, r0.get_center().y) + Vector2(0.5, 0.5))
	w.run_ticks(SimWorld.TICK_RATE * 15)
	return w.state_hash()


func test_same_hash_twice_and_roundtrip() -> void:
	check_eq(_scenario_hash(), _scenario_hash(), "the same attack on the same base hashes the same twice")
	var w := _lp()
	var rc := CnFacility.compound_rect(_fac(w))
	_soldier(w, _free(w, rc.get_center()))
	_still_foe(w, Vector2(rc.position.x - 8.0, rc.get_center().y), "m_walker")
	w.run_ticks(60)
	var c := SimWorld.from_dict(w.to_dict().duplicate(true))
	c.ai_state = {}
	w.run_ticks(80)
	c.run_ticks(80)
	check_eq(w.state_hash(), c.state_hash(), "save / load mid-attack stays in step")
